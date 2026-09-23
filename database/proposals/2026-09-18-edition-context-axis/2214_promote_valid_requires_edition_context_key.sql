-- ============================================================================
-- Query 2214 — GUARD DE TRANSIÇÃO OPERACIONAL (job-aware)
-- Status: ✅ EXECUTADA NO LIVE / LIVE VALIDATED / CLOSED · Versão 3.1
-- CORREÇÕES 1, 2 e 8 da OPERATIONAL-BOUNDARY-CORRECTION-01
--
-- ----------------------------------------------------------------------------
-- EXECUÇÃO NO LIVE — 2026-09-22 (BATCH8-BIS-2214-CLOSEOUT-01)
-- ----------------------------------------------------------------------------
--   CONFIRMADO EXECUTADO, na v3.1.
--
--   DOIS BLOBS — NAO CONFUNDIR:
--     * blob EXECUTADO no LIVE ... 30e19523d91d9bc127dcefe6f4cb09e6c263ab73
--     * blob ATUAL deste arquivo . DIFERENTE do acima, e deliberadamente NAO
--       gravado aqui: um arquivo nao pode conter o proprio hash. Obtenha-o com
--       `git hash-object` neste arquivo quando precisar cita-lo.
--   Eles diferem porque ESTE bloco de rastreabilidade foi acrescentado ao
--   cabecalho DEPOIS da execucao. O blob atual NAO e o blob executado e nao
--   deve ser citado como tal.
--
--   O que NAO mudou e o que importa: tudo entre `BEGIN;` e `COMMIT;` permanece
--   byte a byte o que o Postgres recebeu — md5 do intervalo
--   db0341940115eab9b73e9d0ed81c74cd, identico antes e depois do closeout.
--   Nenhuma linha executavel, gate, probe ou comentario interno foi tocado.
--
--   COMO RODOU: manualmente, no SQL Editor do Supabase, em uma unica
--   submissao. Retorno: `Success. No rows returned`.
--
--   POSTCHECK LIVE (BATCH8-BIS-2214-LIVE-POSTCHECK-01, read-only, 15 GATEs):
--   **PASS / LIVE VALIDATED — 15/15.** Trigger unico · tgtype = 23 exato
--   (BEFORE + ROW + INSERT + UPDATE, sem DELETE/TRUNCATE/INSTEAD) ·
--   `UPDATE OF` = normalized_data + persistence_status + validation_status ·
--   `tgfoid` = OID da funcao canonica · G1 e G2 presentes no corpo ·
--   SECURITY INVOKER · `proconfig = ARRAY['search_path=""']` · ACL sem
--   EXECUTE para PUBLIC/anon/authenticated · exatamente os 3 triggers
--   canonicos na tabela · nenhum outro trigger usando o guard · operacional
--   VALID+PENDING sem a chave = **0** · historico CANCELLED sem chave
--   **847** e VALID+PENDING **415** PRESERVADOS · jobs em voo = 0 ·
--   residuo `GUARD2214-%` = 0 (o SAVEPOINT do PASSO 4 reverteu).
--
--   LEDGER = 0 — DIVERGENCIA DE RASTREABILIDADE, DECLARADA, NAO MASCARADA.
--   Nao existe entrada para '2214_promote_valid_requires_edition_context_key'
--   em `supabase_migrations.schema_migrations`, e isso NAO significa "nao
--   executada". O ledger e escrito pela CLI do Supabase (`db push` /
--   `migration up`), nunca pelo motor do Postgres: a execucao pelo SQL Editor
--   aplica e comita o DDL sem passar por ele. Quem prova o estado fisico sao
--   os catalogos que o proprio motor mantem (`pg_trigger`, `pg_proc`) — e
--   foram eles que os 15 gates mediram. A inversa tambem vale: ledger = 1 nao
--   provaria nada, porque a linha pode ser inserida a mao sem o DDL ter
--   rodado. Reconciliacao do ledger: FORA DESTA RODADA, por mandato.
--   Precedente da mesma classe no repositorio: a `2202`, tambem executada
--   direto no SQL Editor e tambem sem linha no ledger.
--
--   ⚠️ CURRENT LIVE — NAO REEXECUTAR sem novo mandato de Fabricio. O arquivo
--   e estruturalmente reentrante (`CREATE OR REPLACE FUNCTION` +
--   `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`), mas os gates do PASSO 1 e o
--   probe do PASSO 4 voltariam a rodar sobre um LIVE ja validado, sem ganho.
--
-- ----------------------------------------------------------------------------
-- v3.1 (BATCH8-BIS-2214-CORRECTION-01) — FIXTURE DO PROBE + ACL
-- ----------------------------------------------------------------------------
--   A SEMANTICA DO GUARD NAO MUDOU. G1/G2/G3, escopo job-aware, tri-state
--   ausencia/JSON null/UUID, timing e eventos do trigger, prechecks, SAVEPOINT
--   e terminador COMMIT seguem byte-equivalentes a v3.0. Mudaram a fixture do
--   PASSO 4 e o epilogo de ACL.
--
--   B1 — os tres INSERTs de job do probe omitiam `source` e `external_set_id`,
--   ambos NOT NULL SEM DEFAULT (2136:66-67), e `source` ainda tem
--   CHECK (source = 'TCGDEX') (2136:98-99). A primeira execucao levantava
--   23502 not_null_violation, o DO abortava, a transacao inteira abortava e o
--   guard NAO era instalado. Fail-safe, porem inexecutavel.
--
--   B2 — o indice parcial `uq_catalog_variant_import_job_fingerprint_active`
--   (2136:120-122) e UNIQUE em (card_set_id, external_set_id) WHERE status
--   nao-terminal. No CASO 7 o job CANCELLED e reativado para STAGED enquanto o
--   primeiro ja esta em CONFIRMING: com `external_set_id` igual entre as
--   fixtures, ou igual ao de um job real do mesmo Card Set, isso viraria
--   23505 unique_violation. O probe tambem nao escolhe um Card Set "sem job
--   ativo" — e nem deve: precisa valer para qualquer Card retornada.
--
--   CORRECAO: cada fixture recebe `source='TCGDEX'` e um `external_set_id`
--   SINTETICO derivado de um UUID gerado no proprio probe
--   (`GUARD2214-<uuid>-S|-C|-K`). Unico por execucao, distinto entre as tres, e
--   fora do espaco de nomes de qualquer `external_set_id` real da fonte.
--
--   ACL — a 2210:205 ja faz REVOKE desta funcao, e CREATE OR REPLACE FUNCTION
--   PRESERVA o ACL existente, entao no LIVE nada regredia. O REVOKE passa a ser
--   repetido aqui mesmo assim: numa instalacao limpa sem a 2210 antes, a funcao
--   nasceria executavel por PUBLIC. Idempotente, custo zero.
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
'Guard de transicao OPERACIONAL (Query 2214 v3.1). G1 presenca: job.status em (RECEIVED,PROCESSING,STAGED,CONFIRMING) + persistence PENDING + validation VALID exige a chave edition_context_profile_id. O escopo e JOB-AWARE porque "operacional" e propriedade do job, nao da row: o predicado anterior (VALID+PENDING, row-local) atingia 415 rows historicas de jobs CANCELLED e zero operacionais. G2 nao-regressao: row VALID que ja tem a chave nunca a perde. G3 forma: tipo e formato UUID. CHECK nao serve — nao enxerga outra tabela.';

-- ACL (v3.1). A 2210:205 ja revogou, e CREATE OR REPLACE FUNCTION preserva o
-- ACL existente — no LIVE isto e no-op. Repetido para que a postura de
-- seguranca seja EXPLICITA neste arquivo: numa instalacao limpa sem a 2210
-- antes, a funcao nasceria executavel por PUBLIC.
REVOKE ALL ON FUNCTION internal.guard_cvir_normalized_shape() FROM PUBLIC, anon, authenticated;

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
    -- Namespace SINTETICO e unico POR EXECUCAO (v3.1). O UUID nasce aqui, nao
    -- e lido de lugar nenhum: nenhum `external_set_id` real da fonte pode
    -- coincidir com ele, e duas execucoes do probe nao colidem entre si.
    -- O prefixo legivel serve so para quem inspecionar o banco durante um
    -- aborto; a unicidade vem do UUID, nao dele.
    v_tag TEXT := 'GUARD2214-' || gen_random_uuid()::TEXT;
BEGIN
    SELECT c.id, c.card_set_id INTO v_card, v_cs FROM public.card c LIMIT 1;
    SELECT t.id INTO v_vt FROM public.card_variant_type t LIMIT 1;
    IF v_card IS NULL OR v_vt IS NULL THEN
        RAISE EXCEPTION 'GUARD_PROBE_NO_FIXTURE: sem card/variant_type.';
    END IF;

    -- Fixtures de job nos TRES regimes. Sem eles, os casos 5 e 6 seriam
    -- PASS por ausencia de fixture — proibido.
    --
    -- v3.1: `source` e `external_set_id` sao NOT NULL SEM DEFAULT (2136:66-67)
    -- e `source` tem CHECK (source='TCGDEX') (2136:98-99) — omiti-los abortava
    -- a execucao inteira (B1). Os tres `external_set_id` sao SUFIXOS DISTINTOS
    -- do MESMO namespace unico por execucao, o que fecha B2: o indice parcial
    -- `uq_catalog_variant_import_job_fingerprint_active` (2136:120-122) e
    -- UNIQUE em (card_set_id, external_set_id) WHERE status nao-terminal, e no
    -- CASO 7 a fixture CANCELLED e reativada para STAGED enquanto a primeira
    -- ja esta em CONFIRMING — duas nao-terminais ao mesmo tempo, do mesmo
    -- Card Set. Com sufixos distintos elas nao colidem entre si; com o UUID no
    -- meio, nao colidem com nenhum job real nem com outra execucao do probe.
    INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
         VALUES (v_cs,'TCGDEX', v_tag || '-S','STAGED')    RETURNING id INTO v_job_staged;
    INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
         VALUES (v_cs,'TCGDEX', v_tag || '-C','CANCELLED') RETURNING id INTO v_job_cancelled;
    INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
         VALUES (v_cs,'TCGDEX', v_tag || '-K','COMPLETED') RETURNING id INTO v_job_completed;

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

    RAISE NOTICE 'GUARD OPERACIONAL v3.1 OK — casos 1..7 + G2 + no-lockout.';
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
