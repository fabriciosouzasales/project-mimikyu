-- ============================================================================
-- Query 2214 — GUARD DE TRANSIÇÃO OPERACIONAL (job-aware)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 3.0
-- CORREÇÕES 1, 2 e 8 da OPERATIONAL-BOUNDARY-CORRECTION-01
--
-- ----------------------------------------------------------------------------
-- O DEFEITO DA v2.0
-- ----------------------------------------------------------------------------
--   Predicado:  validation_status = 'VALID' AND persistence_status = 'PENDING'
--
--   Medido no LIVE, ele atinge **415 rows, TODAS de jobs CANCELLED**
--   (414 decision SKIPPED + 1 decision PENDING) e **ZERO rows operacionais**
--   (jobs STAGED/CONFIRMING com PENDING + VALID = 0).
--
--   Errava nas duas direcoes. Causa raiz conceitual: persistence_status
--   descreve a ROW; "operacional" e propriedade do JOB. Row PENDING em job
--   cancelado nao e backlog — e trabalho abandonado.
--
-- ----------------------------------------------------------------------------
-- POR QUE NÃO `CHECK` (Correcao 2)
-- ----------------------------------------------------------------------------
--   Um CHECK de catalog_variant_import_row so enxerga colunas da propria row.
--   job.status vive noutra tabela. As alternativas foram descartadas:
--     * CHECK row-local ......... semanticamente FALSO (atinge as 415)
--     * coluna job_status na row  duplica fonte de verdade
--     * CHECK com funcao "IMMUTABLE" que le outra tabela .. corrupcao
--   Resta TRIGGER, que consulta o job legitimamente. Nao se forca uma regra
--   row-local falsa apenas para poder usar CHECK.
--
--   Defesa em TRES camadas, nenhuma substituindo a outra:
--     1. este trigger — barra a transicao no banco;
--     2. routing/propagation (2211 · 2219) — so marca VALID apos resolver;
--     3. revalidacao defensiva no confirm (2218) — fail-closed com mensagem
--        de negocio, no mesmo padrao que 2145:324 ja usa para validation.
--
-- ----------------------------------------------------------------------------
-- PREDICADO v3.0
-- ----------------------------------------------------------------------------
--     job.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
--     AND row.persistence_status = 'PENDING'
--     AND row.validation_status  = 'VALID'
--       ->  edition_context_profile_id PRESENTE
--
--   RECEIVED/PROCESSING entram porque uma row pode nascer VALID durante o
--   processamento; deixa-los de fora abriria janela gravavel.
--
--   O conjunto CONFIRMAVEL (2145:270/307/314/324) e mais estreito —
--   exige ainda decision_status='APPROVED'. O guard protege o conjunto
--   MAIOR, de proposito: barrar so na confirmacao seria tarde, a row ja
--   teria sido exibida ao revisor como pronta.
--
--   Provado pela Query 2833 (11 gates) contra as combinacoes reais.
--
-- ----------------------------------------------------------------------------
-- AUSÊNCIA DE LOCKOUT
-- ----------------------------------------------------------------------------
--   1. O estado proibido NAO EXISTE hoje (0 rows). O guard so impede cria-lo.
--   2. Sair de PENDING e sempre permitido: o predicado testa
--      NEW.persistence_status='PENDING'; o confirm grava INSERTED/UNCHANGED/
--      FAILED e o guard nao dispara.
--   3. O gatilho e estreito: mexer em error_detail ou decision_status nao o
--      aciona.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE: vocabulario de job.status conhecido + universo operacional pronto.
DO $$
DECLARE v_n INT; v_lista TEXT;
BEGIN
    SELECT string_agg(DISTINCT j.status, ', ') INTO v_lista
      FROM public.catalog_variant_import_job j
     WHERE j.status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING',
                            'COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED');
    IF v_lista IS NOT NULL THEN
        RAISE EXCEPTION 'GUARD_BLOCKED_UNKNOWN_JOB_STATUS: %. Rode a Query 2833 e reavalie a fronteira antes de promover o guard.', v_lista;
    END IF;

    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND r.persistence_status = 'PENDING'
       AND r.validation_status  = 'VALID'
       AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'GUARD_PROMOTION_BLOCKED: % rows OPERACIONAIS VALID sem a chave. Rode 2212 e valide com 2832/2833.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'CANCELLED' AND r.validation_status = 'VALID'
       AND r.persistence_status = 'PENDING';
    RAISE NOTICE 'HISTORICO CANCELLED: % rows VALID+PENDING permanecem intocadas e sem exigencia de chave.', v_n;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
CREATE OR REPLACE FUNCTION internal.guard_cvir_normalized_shape()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_pp  TEXT := jsonb_typeof(NEW.normalized_data -> 'printing_profile_id');
    v_ec  TEXT := jsonb_typeof(NEW.normalized_data -> 'edition_context_profile_id');
    v_job TEXT;
BEGIN
    -- ===================== G3 — FORMA ====================================
    IF v_pp IS NOT NULL AND v_pp NOT IN ('null','string') THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_PRINTING: printing_profile_id deve ser JSON null ou string UUID, recebido %.', v_pp;
    END IF;
    IF v_ec IS NOT NULL AND v_ec NOT IN ('null','string') THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_EDITION_CONTEXT: edition_context_profile_id deve ser JSON null ou string UUID, recebido %.', v_ec;
    END IF;
    IF v_pp = 'string' AND (NEW.normalized_data ->> 'printing_profile_id')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_PRINTING: printing_profile_id nao e UUID valido (%).',
              NEW.normalized_data ->> 'printing_profile_id';
    END IF;
    IF v_ec = 'string' AND (NEW.normalized_data ->> 'edition_context_profile_id')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_EDITION_CONTEXT: edition_context_profile_id nao e UUID valido (%).',
              NEW.normalized_data ->> 'edition_context_profile_id';
    END IF;

    -- ===================== G2 — NÃO-REGRESSÃO ============================
    -- Uma vez resolvido, nao volta a indeterminado. Vale inclusive para
    -- historico: e o que impede burlar G1 removendo a chave antes.
    IF TG_OP = 'UPDATE'
       AND OLD.validation_status = 'VALID'
       AND jsonb_exists(OLD.normalized_data, 'edition_context_profile_id')
       AND NOT jsonb_exists(NEW.normalized_data, 'edition_context_profile_id') THEN
        RAISE EXCEPTION 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN: row % e VALID e ja tinha a chave resolvida; remove-la rebaixaria uma decisao a "nao resolvido".', NEW.id;
    END IF;

    -- ===================== G1 — PRESENÇA, escopo OPERACIONAL =============
    IF NEW.validation_status = 'VALID' THEN
        IF (NEW.normalized_data ->> 'variant_type_id') IS NULL THEN
            RAISE EXCEPTION 'CVIR_VALID_REQUIRES_VARIANT_TYPE: row % marcada VALID sem variant_type_id.', NEW.id;
        END IF;
        IF v_pp IS NULL THEN
            RAISE EXCEPTION 'CVIR_VALID_REQUIRES_PRINTING_KEY: row % marcada VALID sem a chave printing_profile_id.', NEW.id;
        END IF;

        -- A chave de Edition Context so e exigida no universo OPERACIONAL.
        -- O lookup do job so acontece quando a row esta PENDING e VALID —
        -- caminho estreito, e o job normalmente ja esta em cache/locked pelo
        -- confirm (2145:264 faz SELECT ... FOR UPDATE do job).
        IF NEW.persistence_status = 'PENDING' AND v_ec IS NULL THEN
            SELECT j.status INTO v_job
              FROM public.catalog_variant_import_job j
             WHERE j.id = NEW.job_id;

            IF v_job IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') THEN
                RAISE EXCEPTION 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY: row % pertence a job % (operacional) e esta VALID+PENDING sem a chave edition_context_profile_id. Resolva o eixo pelo routing; use JSON null apenas quando o contrato devolver RESOLVED_NO_EDITION_CONTEXT.', NEW.id, v_job;
            END IF;
            -- job terminal (CANCELLED/COMPLETED/COMPLETED_WITH_ERRORS/FAILED):
            -- historico. Nao ha exigencia — e a correcao desta versao.
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION internal.guard_cvir_normalized_shape() IS
'Guard de transicao OPERACIONAL (Query 2214 v3.0). G1 presenca: job.status em (RECEIVED,PROCESSING,STAGED,CONFIRMING) + persistence PENDING + validation VALID exige a chave edition_context_profile_id. O escopo e JOB-AWARE porque "operacional" e propriedade do job, nao da row: o predicado anterior (VALID+PENDING, row-local) atingia 415 rows historicas de jobs CANCELLED e zero operacionais. G2 nao-regressao: row VALID que ja tem a chave nunca a perde. G3 forma: tipo e formato UUID. CHECK nao serve — nao enxerga outra tabela.';

-- ---------------------------------------------------------------- PASSO 3 ---
DROP TRIGGER IF EXISTS trg_cvir_normalized_shape ON public.catalog_variant_import_row;

CREATE TRIGGER trg_cvir_normalized_shape
    BEFORE INSERT OR UPDATE OF normalized_data, validation_status, persistence_status
    ON public.catalog_variant_import_row
    FOR EACH ROW EXECUTE FUNCTION internal.guard_cvir_normalized_shape();

-- ---------------------------------------------------------------- PASSO 4 ---
-- POSTCHECK — os 7 casos da Correcao 8, em SAVEPOINT revertido.
SAVEPOINT guard_probe;
DO $$
DECLARE
    v_card UUID; v_vt UUID; v_erro TEXT; v_id UUID; v_cs UUID;
    v_job_staged UUID; v_job_cancelled UUID; v_job_completed UUID;
    v_nd_ok JSONB; v_nd_sem JSONB;
BEGIN
    SELECT c.id, c.card_set_id INTO v_card, v_cs FROM public.card c LIMIT 1;
    SELECT t.id INTO v_vt FROM public.card_variant_type t LIMIT 1;
    IF v_card IS NULL OR v_vt IS NULL THEN
        RAISE EXCEPTION 'GUARD_PROBE_NO_FIXTURE: sem card/variant_type.';
    END IF;

    -- Fixtures de job nos TRES regimes. Sem eles, os casos 5 e 6 seriam
    -- PASS por ausencia de fixture — proibido.
    INSERT INTO public.catalog_variant_import_job (card_set_id, status)
         VALUES (v_cs,'STAGED')    RETURNING id INTO v_job_staged;
    INSERT INTO public.catalog_variant_import_job (card_set_id, status)
         VALUES (v_cs,'CANCELLED') RETURNING id INTO v_job_cancelled;
    INSERT INTO public.catalog_variant_import_job (card_set_id, status)
         VALUES (v_cs,'COMPLETED') RETURNING id INTO v_job_completed;

    v_nd_sem := jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL);
    v_nd_ok  := v_nd_sem || '{"edition_context_profile_id": null}'::JSONB;

    -- CASO 1 — STAGED + PENDING + NEEDS_REVIEW + chave ausente ⇒ PERMITIDO.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
    VALUES (v_job_staged, v_card, '{}'::JSONB, '{}'::JSONB, 'NEEDS_REVIEW', 'PENDING');

    -- CASO 2 — STAGED + PENDING + VALID + chave ausente ⇒ BLOQUEADO.
    BEGIN
        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job_staged, v_card, '{}'::JSONB, v_nd_sem, 'VALID', 'PENDING');
        RAISE EXCEPTION 'CASO2_FAIL: VALID operacional sem chave foi ACEITO.';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_erro = MESSAGE_TEXT;
        IF v_erro LIKE 'CASO2_FAIL%' THEN RAISE; END IF;
        IF v_erro NOT LIKE 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY%' THEN
            RAISE EXCEPTION 'CASO2_WRONG_ERROR: %', v_erro;
        END IF;
    END;

    -- CASO 3 — STAGED + PENDING + VALID + JSON null ⇒ PERMITIDO.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
    VALUES (v_job_staged, v_card, '{}'::JSONB, v_nd_ok, 'VALID', 'PENDING')
    RETURNING id INTO v_id;

    -- CASO 4 — a mesma proibicao vale em CONFIRMING (fail-closed).
    UPDATE public.catalog_variant_import_job SET status='CONFIRMING' WHERE id=v_job_staged;
    BEGIN
        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job_staged, v_card, '{}'::JSONB, v_nd_sem, 'VALID', 'PENDING');
        RAISE EXCEPTION 'CASO4_FAIL: VALID sem chave aceito em job CONFIRMING.';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_erro = MESSAGE_TEXT;
        IF v_erro LIKE 'CASO4_FAIL%' THEN RAISE; END IF;
        IF v_erro NOT LIKE 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY%' THEN
            RAISE EXCEPTION 'CASO4_WRONG_ERROR: %', v_erro;
        END IF;
    END;

    -- CASO 5 — COMPLETED terminal + VALID + chave ausente ⇒ PERMITIDO.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
    VALUES (v_job_completed, v_card, '{}'::JSONB, v_nd_sem, 'VALID', 'INSERTED');

    -- CASO 6 — CANCELLED + VALID + **PENDING** + chave ausente ⇒ PERMITIDO.
    -- Reproduz exatamente as 415 rows do LIVE. Sob a v2.0 isto era recusado.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
    VALUES (v_job_cancelled, v_card, '{}'::JSONB, v_nd_sem, 'VALID', 'PENDING', 'SKIPPED');

    -- CASO 7 — transicao terminal -> operacional nao passa em silencio.
    -- Reativar o job nao e barrado aqui (e contrato do job), MAS a primeira
    -- escrita na row passa a ser recusada.
    UPDATE public.catalog_variant_import_job SET status='STAGED' WHERE id=v_job_cancelled;
    BEGIN
        UPDATE public.catalog_variant_import_row
           SET normalized_data = normalized_data
         WHERE job_id = v_job_cancelled;
        RAISE EXCEPTION 'CASO7_FAIL: row reativada aceitou escrita sem a chave.';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_erro = MESSAGE_TEXT;
        IF v_erro LIKE 'CASO7_FAIL%' THEN RAISE; END IF;
        IF v_erro NOT LIKE 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY%' THEN
            RAISE EXCEPTION 'CASO7_WRONG_ERROR: %', v_erro;
        END IF;
    END;

    -- G2 — remover a chave de uma row VALID ⇒ BLOQUEADO.
    BEGIN
        UPDATE public.catalog_variant_import_row
           SET normalized_data = normalized_data - 'edition_context_profile_id'
         WHERE id = v_id;
        RAISE EXCEPTION 'G2_FAIL: remocao da chave aceita.';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_erro = MESSAGE_TEXT;
        IF v_erro LIKE 'G2_FAIL%' THEN RAISE; END IF;
        IF v_erro NOT LIKE 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN%' THEN
            RAISE EXCEPTION 'G2_WRONG_ERROR: %', v_erro;
        END IF;
    END;

    -- SAIDA DE PENDING sempre permitida — prova de ausencia de lockout.
    UPDATE public.catalog_variant_import_row
       SET persistence_status = 'FAILED'
     WHERE job_id = v_job_cancelled;

    RAISE NOTICE 'GUARD OPERACIONAL v3.0 OK — casos 1..7 + G2 + no-lockout.';
END $$;
ROLLBACK TO SAVEPOINT guard_probe;

-- ============================================================================
-- ROLLBACK
--   Reaplicar a Query 2210 devolve o guard ao estagio permissivo e recria o
--   trigger sem persistence_status. Nenhum dado e perdido.
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
