-- ============================================================================
-- Query 2217 — internal.write_card_variant() v3.0 (SETE argumentos) — EXPAND
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
-- v2.0: EDITION-CONTEXT-AXIS-WRITER-EXPAND-CONTRACT-CORRECTION-01
-- v1.0: CORREÇÃO 7 da GATE-A-FINAL-CORRECTION-01
--
-- ----------------------------------------------------------------------------
-- v2.0 — POR QUE O DROP SAIU DAQUI
-- ----------------------------------------------------------------------------
--   A v1.0 fazia CREATE da de sete E DROP da de seis no mesmo arquivo, com um
--   guard que exigia a 2218 já aplicada. Isso forçava a ordem 2218 → 2217 e
--   criava uma janela real: depois da 2218 e antes da 2217, o confirm chamava
--   um writer de sete argumentos que AINDA NAO EXISTIA. RPC instalada e
--   inexecutável — mesmo sob FREEZE, é um estado que não queremos.
--
--   A troca passa a seguir EXPAND → SWITCH → CONTRACT:
--
--     2217 (EXPAND)   cria a de SETE · PRESERVA a de SEIS · não dropa nada
--     2218 (SWITCH)   confirm passa a chamar SOMENTE a de sete
--     2223 (CONTRACT) prova que ninguém usa a de seis · então dropa
--
--   Em nenhum momento existe caller apontando para assinatura ausente. Cada
--   etapa é individualmente reversível e o sistema é executável entre elas.
--
--   O DROP e a prova negativa de callers migraram INTEGRALMENTE para a
--   Query 2223. Nenhum wrapper de compatibilidade foi criado: a de seis
--   permanece exatamente como está (2143 v2.0), viva e inalterada, até a 2223.
--
-- BASE: database/schema/2143_create_internal_write_card_variant_function.sql
--       v2.0 (CANÔNICA / LIVE). Este arquivo é o ESTADO FINAL proposto —
--       corpo inteiro, não um patch — porque o projeto aplica Queries
--       individualmente e `CREATE OR REPLACE FUNCTION` substitui o corpo todo.
--
-- ----------------------------------------------------------------------------
-- ACHADO DE AUDITORIA QUE MUDA O DESENHO DE CONCORRÊNCIA
-- ----------------------------------------------------------------------------
--   O CONCURRENCY-DESIGN.md dizia que matching e lock aconteciam AQUI. Não
--   acontecem. A leitura do código canônico (2143 v2.0) mostra que esta
--   função é um INSERT puro: não faz SELECT de matching, não toma lock e não
--   aloca variant_order — o próprio cabeçalho da v2.0 diz que
--   `p_variant_order` "é sempre calculado pelo chamador (Query 2145)".
--
--   Portanto o lock na Card, o matching por identidade e o tratamento de
--   `unique_violation` pertencem à Query 2218 (admin_confirm_catalog_variant_
--   import), NÃO a esta. Esta função permanece deliberadamente burra.
--
-- ----------------------------------------------------------------------------
-- v3.0 — O QUE MUDA, E SÓ ISSO
-- ----------------------------------------------------------------------------
--   + p_edition_context_profile_id UUID  (SÉTIMO argumento, SEM DEFAULT)
--   + validação de existência do profile, quando informado
--   + a coluna entra no INSERT
--
--   NADA MAIS muda: mesmo schema `internal`, mesmo SECURITY DEFINER, mesmo
--   `search_path = ''`, mesmos REVOKEs, mesmos códigos de erro, mesma recusa
--   de UPDATE, mesmo tratamento de is_default (nunca no INSERT).
--
-- POR QUE SEM `DEFAULT NULL` — mesmo argumento que a v2.0 usou para Printing
--   Um DEFAULT manteria compilando a chamada de seis argumentos. Qualquer
--   writer futuro que esquecesse o contexto gravaria NULL SILENCIOSAMENTE — e
--   NULL aqui não é placeholder, é o valor semanticamente carregado "sem
--   contexto de edição". Sem o DEFAULT, o erro de omissão vira ERRO DE
--   COMPILAÇÃO. É a mesma decisão, pelo mesmo motivo, no mesmo lugar.
--
-- O OVERLOAD É DELIBERADO E TEMPORÁRIO
--   `CREATE OR REPLACE` com aridade diferente CRIA UM OVERLOAD — não
--   substitui. Na v1.0 isso era tratado como defeito a corrigir no mesmo
--   arquivo; na v2.0 é o mecanismo do EXPAND: as duas assinaturas coexistem
--   entre 2217 e 2223, e é justamente essa coexistência que elimina a janela
--   de RPC inexecutável.
--
--   O risco que o DROP existia para eliminar — o confirm antigo gravando
--   Variants sem o quarto componente — continua eliminado, mas por outro
--   meio: a 2218 (SWITCH) substitui o corpo do confirm, e a 2223 (CONTRACT)
--   só dropa depois de PROVAR que nenhum caller executável restou. A janela
--   de coexistência é curta, está sob FREEZE, e tem prova de saída.
--
-- SAME-GAME: NÃO validado aqui, de propósito — mesma razão da v2.0. A
--   autoridade é `public.validate_card_variant_game_consistency`, que a
--   Query 2220 estende para o terceiro eixo. Duplicar a regra criaria duas
--   fontes de verdade e uma delas ficaria desatualizada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE: a coluna precisa existir (Query 2208) antes de o writer gravá-la.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'card_variant'
           AND column_name = 'edition_context_profile_id'
    ) THEN
        RAISE EXCEPTION 'WRITER_V3_BLOCKED: card_variant.edition_context_profile_id nao existe. Rode a Query 2208 antes.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
CREATE OR REPLACE FUNCTION internal.write_card_variant(
    p_mode TEXT,
    p_variant_id UUID,
    p_card_id UUID,
    p_variant_type_id UUID,
    p_variant_order INTEGER,
    p_printing_profile_id UUID,
    p_edition_context_profile_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_variant_id UUID;
BEGIN
    IF p_mode NOT IN ('CREATE', 'UPDATE') THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_MODE: p_mode deve ser CREATE ou UPDATE (recebido: %).', p_mode;
    END IF;

    IF p_mode = 'UPDATE' THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UPDATE_NOT_SUPPORTED: nenhum fluxo atual atualiza uma Card Variant existente — ela é tratada como UNCHANGED. Parâmetro reservado para uma necessidade futura ainda não desenhada.';
    END IF;

    -- p_mode = 'CREATE'
    IF p_variant_id IS NOT NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UNEXPECTED_ID: p_variant_id não deve ser informado em modo CREATE.';
    END IF;
    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_CARD: p_card_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_TYPE: p_variant_type_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_order IS NULL OR p_variant_order <= 0 THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_ORDER: p_variant_order deve ser um inteiro positivo (recebido: %).', p_variant_order;
    END IF;

    -- Se um perfil de impressão foi informado, ele precisa existir. Same-Game
    -- NAO e checado aqui de proposito: o trigger da Query 2170 e a autoridade.
    IF p_printing_profile_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.card_printing_profile p WHERE p.id = p_printing_profile_id
       ) THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_PRINTING_PROFILE_NOT_FOUND: Perfil de Impressão % não encontrado.', p_printing_profile_id;
    END IF;

    -- v3.0 — MESMA disciplina para o terceiro eixo. Existência SIM; same-Game
    -- NAO (autoridade em validate_card_variant_game_consistency, Query 2220).
    -- NENHUMA criacao automatica de profile. Jamais.
    IF p_edition_context_profile_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.card_edition_context_profile e WHERE e.id = p_edition_context_profile_id
       ) THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_EDITION_CONTEXT_NOT_FOUND: Perfil de Contexto de Edição % não encontrado.', p_edition_context_profile_id;
    END IF;

    INSERT INTO public.card_variant
        (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
    VALUES
        (p_card_id, p_variant_type_id, p_variant_order, p_printing_profile_id, p_edition_context_profile_id)
    RETURNING id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID, UUID) FROM anon;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID, UUID) FROM authenticated;

-- ---------------------------------------------------------------- PASSO 3 ---
-- POSTCHECK DO EXPAND. As DUAS assinaturas devem existir, e ambas limpas.
-- O DROP da de seis NÃO acontece aqui — pertence à Query 2223 (CONTRACT).
DO $$
DECLARE v_n INT; v_n6 INT; v_n7 INT; v_def INT; v_sec BOOLEAN; v_cfg TEXT[];
BEGIN
    SELECT COUNT(*) FILTER (WHERE p.pronargs = 6),
           COUNT(*) FILTER (WHERE p.pronargs = 7),
           COUNT(*)
      INTO v_n6, v_n7, v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    -- E1 — a de SETE nasceu.
    IF v_n7 <> 1 THEN
        RAISE EXCEPTION 'EXPAND_V3_MISSING: esperada 1 assinatura de 7 args, encontrada %.', v_n7;
    END IF;

    -- E2 — a de SEIS foi PRESERVADA. Se sumiu, alguem dropou fora de contrato
    -- e o confirm vivo (que ainda chama com seis) esta quebrado agora.
    IF v_n6 <> 1 THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_LOST: a assinatura de 6 args deveria estar PRESERVADA neste passo (encontrada %). O DROP pertence a Query 2223.', v_n6;
    END IF;

    -- E3 — exatamente duas, nem mais.
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'EXPAND_V3_UNEXPECTED_SIGNATURES: esperadas 2 assinaturas durante o EXPAND, encontradas %.', v_n;
    END IF;

    -- E4 — a de SETE: sem DEFAULT, SECURITY DEFINER, search_path.
    SELECT p.pronargdefaults, p.prosecdef, p.proconfig
      INTO v_def, v_sec, v_cfg
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant'
       AND p.pronargs = 7;

    IF v_def <> 0 THEN RAISE EXCEPTION 'WRITER_V3_HAS_DEFAULT: nenhum argumento pode ter DEFAULT (obtido %).', v_def; END IF;
    IF v_sec IS NOT TRUE THEN RAISE EXCEPTION 'WRITER_V3_NOT_SECDEF: SECURITY DEFINER perdido.'; END IF;
    IF NOT (v_cfg::TEXT LIKE '%search_path=%') THEN
        RAISE EXCEPTION 'WRITER_V3_NO_SEARCH_PATH: proconfig sem search_path.';
    END IF;

    -- E5 — a de SEIS preservou SECURITY DEFINER e search_path (nada foi
    -- tocado nela, este gate so prova que continua intacta).
    SELECT p.prosecdef, p.proconfig INTO v_sec, v_cfg
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant'
       AND p.pronargs = 6;

    IF v_sec IS NOT TRUE THEN RAISE EXCEPTION 'EXPAND_V3_LEGACY_NOT_SECDEF: a de 6 args perdeu SECURITY DEFINER.'; END IF;
    IF NOT (v_cfg::TEXT LIKE '%search_path=%') THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_NO_SEARCH_PATH: a de 6 args perdeu search_path.';
    END IF;

    -- E6 — ACL: NENHUMA das duas pode ter grant publico.
    IF EXISTS (
        SELECT 1 FROM information_schema.role_routine_grants
         WHERE routine_schema = 'internal' AND routine_name = 'write_card_variant'
           AND grantee IN ('anon','authenticated','PUBLIC')
    ) THEN
        RAISE EXCEPTION 'WRITER_V3_GRANT_LEAK: grant indevido para anon/authenticated/PUBLIC em alguma das assinaturas.';
    END IF;

    RAISE NOTICE 'EXPAND OK — write_card_variant com 2 assinaturas (6 preservada + 7 nova), 0 defaults, SECDEF, search_path, sem grants publicos. CONTRACT = Query 2223.';
END $$;

-- ============================================================================
-- PAYLOAD BOUNDS: inalterados. Esta função grava UMA linha por chamada; o
--   limite de lote é do chamador (2218), não daqui.
-- MENSAGENS: todos os códigos de erro da v2.0 preservados literalmente. O
--   único código novo é INTERNAL_WRITE_CARD_VARIANT_EDITION_CONTEXT_NOT_FOUND,
--   espelhando o de Printing.
-- LOCKS: nenhum tomado aqui, nem antes nem agora. Ver 2218.
--
-- ESTADO APÓS ESTA QUERY (EXPAND):
--   internal.write_card_variant  ......... 2 assinaturas
--     (TEXT,UUID,UUID,UUID,INTEGER,UUID)         6 args — 2143 v2.0, INTACTA
--     (TEXT,UUID,UUID,UUID,INTEGER,UUID,UUID)    7 args — v3.0, NOVA
--   admin_confirm_catalog_variant_import ... ainda chama a de SEIS
--   → sistema executável. Nenhum caller aponta para assinatura ausente.
--
-- PRÓXIMOS PASSOS OBRIGATÓRIOS, NESTA ORDEM:
--   2218 (SWITCH)   → confirm passa a chamar SOMENTE a de sete
--   2223 (CONTRACT) → prova negativa de callers + DROP da de seis
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
