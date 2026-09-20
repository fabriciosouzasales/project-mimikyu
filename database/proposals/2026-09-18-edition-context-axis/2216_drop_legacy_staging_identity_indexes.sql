-- ============================================================================
-- Query 2216 — REMOÇÃO das identidades antigas de catalog_variant_import_row
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 3.0
--
-- v3.0 (OPERATIONAL-BOUNDARY-CORRECTION-01): a pre-condicao B passa a ser
-- JOB-AWARE. "VALID + PENDING" (row-local) atingia 415 rows de jobs
-- CANCELLED e zero operacionais — teria bloqueado o DROP por um universo
-- que e historico terminal.
--
-- v2.0 (BACKFILL-SEMANTICS-CORRECTION-01): a pre-condicao B deixou de ser
-- "toda VALID tem a chave" (regra global, semanticamente falsa) e passou a
-- ser o universo OPERACIONAL — VALID + PENDING. Rows terminais em HOLD
-- permanecem legitimamente com a chave AUSENTE, e isso NAO bloqueia o DROP.
-- CORREÇÃO 1 da GATE-A-FINAL-CORRECTION-01
--
-- O DEFEITO QUE ESTA QUERY CORRIGE
--   Os dois DROPs viviam COMENTADOS no corpo da Query 2210. Os índices
--   medidos no LIVE:
--
--     uq_cvir_job_card_type_no_printing
--         (job_id, card_id, (normalized_data->>'variant_type_id'))
--       WHERE variant_type_id IS NOT NULL
--         AND jsonb_typeof(normalized_data->'printing_profile_id') = 'null'
--     uq_cvir_job_card_type_printing
--         (job_id, card_id, (normalized_data->>'variant_type_id'),
--                           (normalized_data->>'printing_profile_id'))
--       WHERE variant_type_id IS NOT NULL
--         AND jsonb_typeof(normalized_data->'printing_profile_id') = 'string'
--
--   Nenhum dos dois considera edition_context_profile_id. Enquanto viverem,
--   duas rows do MESMO job, MESMA Card, MESMO acabamento e MESMA tiragem que
--   difiram SOMENTE em contexto de edição continuam colidindo — a própria
--   prova S4 do harness falharia. **2210 sem 2216 não entrega o eixo.**
--
-- PRÉ-REQUISITO DE ORDEM (não negociável)
--   2210 (índice novo + shape permissivo)
--     -> 2212 (backfill)  -> 2832 (prova)  -> 2214 (guard estrito)
--     -> **2216 (esta)**
--   Remover os antigos ANTES do backfill não causaria erro, mas deixaria o
--   staging sem nenhuma proteção contra duplicata durante a janela em que o
--   índice novo ainda não cobre todas as rows (rows sem a chave produzem o
--   token 'A' e continuariam distintas entre si — ver 2210).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRÉ-CONDIÇÃO A: o índice novo existe, é único e é válido.
DO $$
DECLARE v_unique BOOLEAN; v_valid BOOLEAN; v_nkeys INT;
BEGIN
    SELECT i.indisunique, i.indisvalid, i.indnkeyatts
      INTO v_unique, v_valid, v_nkeys
      FROM pg_index i
     WHERE i.indexrelid = 'public.uq_cvir_row_identity'::REGCLASS;

    IF v_unique IS NOT TRUE OR v_valid IS NOT TRUE THEN
        RAISE EXCEPTION 'NEW_STAGING_IDENTITY_NOT_READY: uq_cvir_row_identity ausente, nao-unico ou invalido. Rode a Query 2210 antes.';
    END IF;
    IF v_nkeys <> 5 THEN
        RAISE EXCEPTION 'NEW_STAGING_IDENTITY_SHAPE: esperado 5 colunas-chave (job, card, vt, token_pp, token_ec), encontrado %.', v_nkeys;
    END IF;
END $$;

-- PRÉ-CONDIÇÃO B: o backfill semântico já cobriu o universo OPERACIONAL.
-- Escopo VALID + PENDING, não "toda VALID": rows terminalmente VALID cuja
-- resolução permanece indeterminada mantêm a chave AUSENTE por design
-- (token 'A'), e isso é correto — não é backfill pendente.
DO $$
DECLARE v_falta INT; v_hist INT; v_canc INT;
BEGIN
    -- OPERACIONAL = job vivo E row pendente. job_status e obrigatorio aqui.
    SELECT COUNT(*) INTO v_falta
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND r.persistence_status = 'PENDING'
       AND r.validation_status  = 'VALID'
       AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id');
    IF v_falta <> 0 THEN
        RAISE EXCEPTION 'OPERATIONAL_NOT_RESOLVED: % rows OPERACIONAIS VALID sem a chave. Rode a Query 2212 antes.', v_falta;
    END IF;

    SELECT COUNT(*) INTO v_hist
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
       AND (j.status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
            OR r.persistence_status <> 'PENDING');

    SELECT COUNT(*) INTO v_canc
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'CANCELLED' AND r.validation_status = 'VALID'
       AND r.persistence_status = 'PENDING';

    RAISE NOTICE 'HISTORICO: % rows sem chave (legitimo). Destas, % sao VALID+PENDING em job CANCELLED — terminal, nao backlog.', v_hist, v_canc;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
DROP INDEX IF EXISTS public.uq_cvir_job_card_type_no_printing;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'uq_cvir_job_card_type_no_printing') THEN
        RAISE EXCEPTION 'DROP_FAILED_1: uq_cvir_job_card_type_no_printing ainda existe.';
    END IF;
    PERFORM 1 FROM pg_index WHERE indexrelid = 'public.uq_cvir_row_identity'::REGCLASS;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NEW_STAGING_IDENTITY_LOST: uq_cvir_row_identity desapareceu durante o passo 2.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
DROP INDEX IF EXISTS public.uq_cvir_job_card_type_printing;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'uq_cvir_job_card_type_printing') THEN
        RAISE EXCEPTION 'DROP_FAILED_2: uq_cvir_job_card_type_printing ainda existe.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- PROVA TERMINAL: somente a identidade nova permanece no staging.
DO $$
DECLARE v_legado INT; v_uniq INT;
BEGIN
    SELECT COUNT(*) INTO v_legado FROM pg_class
     WHERE relname IN ('uq_cvir_job_card_type_no_printing',
                       'uq_cvir_job_card_type_printing');
    IF v_legado <> 0 THEN
        RAISE EXCEPTION 'LEGACY_STAGING_INDEX_SURVIVED: % ainda existem.', v_legado;
    END IF;

    -- Índices ÚNICOS sobre catalog_variant_import_row que envolvem job_id.
    -- Deve restar EXATAMENTE UM: uq_cvir_row_identity.
    SELECT COUNT(*) INTO v_uniq
      FROM pg_index i
     WHERE i.indrelid = 'public.catalog_variant_import_row'::REGCLASS
       AND i.indisunique
       AND EXISTS (
           SELECT 1 FROM unnest(i.indkey) k
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k
           WHERE a.attname = 'job_id'
       );
    IF v_uniq <> 1 THEN
        RAISE EXCEPTION 'STAGING_IDENTITY_NOT_UNIQUE_SOURCE: esperado 1, encontrado %.', v_uniq;
    END IF;

    RAISE NOTICE 'IDENTIDADE staging: somente uq_cvir_row_identity permanece. 3/3 provas OK.';
END $$;

-- ---------------------------------------------------------------- PASSO 5 ---
-- PROVA FUNCIONAL: a coexistência que os índices antigos impediam agora é
-- possível. Este é o teste S4 do harness, executado aqui como aceite do DROP.
-- Roda em SAVEPOINT e é desfeito — não deixa resíduo.
SAVEPOINT s4_probe;
DO $$
DECLARE
    v_job  UUID;
    v_card UUID;
    v_vt   UUID;
    v_n    INT;
BEGIN
    SELECT j.id INTO v_job FROM public.catalog_variant_import_job j LIMIT 1;
    SELECT c.id INTO v_card FROM public.card c LIMIT 1;
    SELECT t.id INTO v_vt FROM public.card_variant_type t LIMIT 1;
    IF v_job IS NULL OR v_card IS NULL OR v_vt IS NULL THEN
        RAISE EXCEPTION 'S4_PROBE_NO_FIXTURE: sem job/card/variant_type para exercitar a prova.';
    END IF;

    -- α: resolvida SEM contexto (token 'N').  β: COM contexto (token 'U:...').
    -- Ambas NEEDS_REVIEW para não acionar o guard estrito de 2214.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status)
    VALUES
        (v_job, v_card, '{}'::JSONB,
         jsonb_build_object('variant_type_id', v_vt,
                            'printing_profile_id', NULL,
                            'edition_context_profile_id', NULL),
         'NEEDS_REVIEW'),
        (v_job, v_card, '{}'::JSONB,
         jsonb_build_object('variant_type_id', v_vt,
                            'printing_profile_id', NULL,
                            'edition_context_profile_id', gen_random_uuid()),
         'NEEDS_REVIEW');

    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = v_job AND r.card_id = v_card
       AND (r.normalized_data ->> 'variant_type_id') = v_vt::TEXT;
    IF v_n < 2 THEN
        RAISE EXCEPTION 'S4_PROBE_FAILED: esperado >= 2 rows coexistindo, obtido %.', v_n;
    END IF;

    RAISE NOTICE 'S4 OK — duas rows do mesmo job/card/finish/printing coexistem diferindo so em Edition Context.';
END $$;
ROLLBACK TO SAVEPOINT s4_probe;

-- ============================================================================
-- ROLLBACK COMPLETO
--   Os dois índices antigos podem ser recriados enquanto os dados ainda os
--   satisfizerem — o que deixa de valer assim que a primeira dupla de rows
--   como a do PASSO 5 for gravada de verdade.
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
