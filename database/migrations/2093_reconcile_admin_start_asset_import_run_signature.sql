-- ============================================================
-- Migration 2093 - Reconcile admin_start_asset_import_run() signature
-- Status: MIGRATION (histórica) — incorporada à versão canônica
-- de `2092 - Create admin_start_asset_import_run() Function` a
-- partir da v1.3.
--
-- Amplia admin_start_asset_import_run() de 3 para 4 parâmetros
-- (adiciona `p_language_code TEXT DEFAULT 'en'`) — suporte real a
-- EN + PT-BR simultâneos no pipeline de importação de imagens,
-- pedido explícito de Fabrício (2026-08-02) depois de notar que a
-- importação automática nunca trazia as imagens em português (só
-- 'en' era usado, hardcoded em todo o pipeline desde sempre). Mesmo
-- motivo de `210 - Create Card External Reference` v2.0 / Migration
-- 277 (ver lá para o raciocínio completo sobre a TCGdex e o
-- `external_card_id` estável entre idiomas).
--
-- Duas mudanças de comportamento, ambas já documentadas no cabeçalho
-- da versão canônica (Query 2092 v1.3):
-- 1. `v_language_id` passa a ser resolvido a partir de
--    `p_language_code` em vez de sempre `'en'` fixo.
-- 2. A checagem de "run já ativa" (evita runs duplicadas) passa a
--    também considerar `language_id` — uma run RUNNING em `en` não
--    bloqueia mais abrir uma run em `pt-BR` para o mesmo Card Set.
--
-- A assinatura muda (novo parâmetro), então CREATE OR REPLACE
-- sozinho criaria uma segunda função sobrecarregada em vez de
-- substituir a existente — por isso a v1.2 (3 parâmetros) é removida
-- explicitamente antes de criar a nova versão, mesmo padrão já usado
-- pela Migration 2091.
--
-- Ver docs/05-modelo-de-dados.md e a versão canônica desta função em
-- database/schema/2092_create_admin_start_asset_import_run_function.sql.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.admin_start_asset_import_run(UUID, TEXT, TEXT);

CREATE FUNCTION public.admin_start_asset_import_run(
    p_card_set_id UUID,
    p_run_type TEXT DEFAULT 'FULL_CARD_SET',
    p_initiated_by TEXT DEFAULT NULL,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE (
    supported BOOLEAN,
    run_id UUID,
    run_code TEXT,
    already_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_asset_source_id UUID;
    v_language_id UUID;
    v_external_set_id TEXT;
    v_existing_id UUID;
    v_existing_code TEXT;
    v_existing_created_at TIMESTAMPTZ;
    v_new_id UUID;
    v_new_code TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_FORBIDDEN: apenas administradores podem iniciar uma importação de imagens.';
    END IF;

    IF p_card_set_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_MISSING_CARD_SET: p_card_set_id é obrigatório.';
    END IF;

    IF p_run_type NOT IN ('MISSING_ONLY', 'REFRESH_EXISTING', 'RETRY_FAILURES', 'SINGLE_CARD', 'FULL_CARD_SET') THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_INVALID_TYPE: run_type inválido.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_set WHERE id = p_card_set_id) THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_card_set_id;
    END IF;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_SOURCE_NOT_FOUND: fonte TCGDEX não cadastrada em asset_source.';
    END IF;

    -- "Suporte" = já existe o mapeamento externo que a Edge Function exige
    -- (findCardSetExternalReference) — sem essa linha, nem vale a pena abrir
    -- uma run: import-card-assets falharia com
    -- CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND. Devolver `supported = false`
    -- aqui evita abrir uma run fadada a isso.
    SELECT external_set_id INTO v_external_set_id
        FROM public.card_set_external_reference
        WHERE card_set_id = p_card_set_id
          AND asset_source_id = v_asset_source_id
          AND is_active = true;

    IF v_external_set_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::UUID, NULL::TEXT, false;
        RETURN;
    END IF;

    -- Idioma parametrizado (v1.3) — antes sempre 'en' fixo.
    SELECT id INTO v_language_id FROM public.language WHERE code = p_language_code;
    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_LANGUAGE_NOT_FOUND: idioma % não cadastrado em language.', p_language_code;
    END IF;

    -- `asset_import_run.run_code` qualificado explicitamente (v1.1) —
    -- `RETURNS TABLE` acima declara uma variável implícita `run_code`
    -- visível aqui dentro; um `run_code` solto é ambíguo entre ela e a
    -- coluna da tabela, e falha em tempo de execução (não é um erro que
    -- `RAISE EXCEPTION`/`traduzirErroCatalogo` conseguem traduzir).
    -- Escopo por language_id (v1.3) — uma run ativa em outro idioma para
    -- o mesmo Card Set não deve ser tratada como "a mesma" importação.
    SELECT id, asset_import_run.run_code, created_at
        INTO v_existing_id, v_existing_code, v_existing_created_at
        FROM public.asset_import_run
        WHERE card_set_id = p_card_set_id
          AND asset_source_id = v_asset_source_id
          AND language_id = v_language_id
          AND status IN ('PENDING', 'RUNNING')
        ORDER BY created_at DESC
        LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        IF v_existing_created_at >= NOW() - INTERVAL '15 minutes' THEN
            -- ainda dentro da janela plausível de execução da Edge
            -- Function — trata como run de verdade em andamento.
            RETURN QUERY SELECT true, v_existing_id, v_existing_code, true;
            RETURN;
        END IF;

        -- Run "presa" (v1.2): mais velha que 15 minutos e ainda em
        -- PENDING/RUNNING — indício de a Edge Function import-card-
        -- assets ter morrido no meio do processamento (timeout de
        -- plataforma) sem chegar a chamar finishImportRun(). Fecha
        -- como FAILED em vez de deixá-la bloqueando novas tentativas
        -- para sempre; nenhuma imagem já importada é afetada
        -- (card_asset é gravado de forma incremental, fora desta
        -- função).
        UPDATE public.asset_import_run
            SET status = 'FAILED',
                error_summary = 'Run marcada como FAILED automaticamente por admin_start_asset_import_run() (v1.2): ficou parada em PENDING/RUNNING por mais de 15 minutos sem concluir — indício de timeout da Edge Function import-card-assets antes de gravar o resultado final. Uma nova run foi aberta para retomar a importação.',
                finished_at = NOW(),
                updated_at = NOW()
            WHERE id = v_existing_id;
    END IF;

    INSERT INTO public.asset_import_run (asset_source_id, card_set_id, language_id, run_type, execution_context, initiated_by)
        VALUES (v_asset_source_id, p_card_set_id, v_language_id, p_run_type, 'SYSTEM', p_initiated_by)
        RETURNING id, asset_import_run.run_code INTO v_new_id, v_new_code;

    RETURN QUERY SELECT true, v_new_id, v_new_code, false;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_start_asset_import_run(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_start_asset_import_run(UUID, TEXT, TEXT, TEXT) TO authenticated;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'admin_start_asset_import_run'
          AND pg_get_function_identity_arguments(p.oid) = 'p_card_set_id uuid, p_run_type text, p_initiated_by text, p_language_code text'
    ) THEN
        RAISE EXCEPTION 'Migration 2093 falhou: assinatura de 4 parâmetros não encontrada.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'admin_start_asset_import_run'
          AND pg_get_function_identity_arguments(p.oid) = 'p_card_set_id uuid, p_run_type text, p_initiated_by text'
    ) THEN
        RAISE EXCEPTION 'Migration 2093 falhou: assinatura antiga de 3 parâmetros ainda existe.';
    END IF;

    RAISE NOTICE 'MIGRATION 2093 CONCLUÍDA: ADMIN_START_ASSET_IMPORT_RUN AMPLIADA PARA 4 PARÂMETROS';
END;
$$;

COMMIT;
