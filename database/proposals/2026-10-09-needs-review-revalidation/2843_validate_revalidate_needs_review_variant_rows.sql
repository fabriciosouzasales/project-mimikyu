-- =============================================================================
-- Query 2843 — Validação da 2238 + 2239 (NEEDS-REVIEW-REVALIDATION-01)
-- STATUS: EXECUTADA NO LIVE em 2026-10-09 — NRR_2843_ROLLBACK_PASS (plano 1.085,
--         conflitos 0, H2 379, H3 57, não resolvíveis 121). v1.1: S1b passou a usar
--         'search_path=""' = ANY(proconfig) (a v1.0 comparava o texto escapado e falhava
--         por defeito do próprio teste, não da função).
-- -----------------------------------------------------------------------------
-- Objetivo: provar, contra o LIVE e SEM PERSISTIR NADA, que a reavaliação faz
--   exatamente o que promete. Um único DO block que termina SEMPRE em
--   RAISE EXCEPTION — portanto toda escrita feita dentro dele é desfeita, mesmo
--   que alguém rode o arquivo sem BEGIN/ROLLBACK (padrão dos harnesses 2830).
--
--   Resultado de sucesso = ERRO com prefixo  NRR_2843_ROLLBACK_PASS
--   Qualquer outro erro                       = FALHA (mensagem diz o caso)
--
-- Pré-requisito: 2238 e 2239 aplicadas.
-- Casos:
--   S1  estrutura: action nova nas 2 CHECK; função SECURITY DEFINER,
--       search_path='', sem EXECUTE para anon/authenticated/service_role
--   N1  ator nulo                 -> REVALIDATE_NR_MISSING_ACTOR
--   N2  ator não-admin            -> REVALIDATE_NR_ACTOR_NOT_ADMIN
--   N3  apply sem expected        -> REVALIDATE_NR_EXPECTED_REQUIRED
--   D1  dry-run não escreve nada (snapshot de contagens idêntico)
--   D2  dry-run: plano > 0, conflitos = 0, H3 excluídas >= 1
--   N4  apply com expected errado -> REVALIDATE_NR_PLAN_DRIFT, nada escrito
--   A1  apply: rows_revalidated = plano
--   A2  NEEDS_REVIEW caiu exatamente o plano; VALID subiu exatamente o plano
--   A3  nenhuma linha de HOLD (H2/H3) mudou
--   A4  toda linha promovida tem as 3 chaves com shape válido e variant_type_id
--   A5  decision/persistence intocados (continuam PENDING/PENDING)
--   A6  auditoria: 1 linha por job afetado, run_id único, soma = plano
--   A7  idempotência: 2º dry-run devolve plano 0; 2º apply(0) não audita
--   A8  zero card_variant criado
-- =============================================================================
DO $h$
DECLARE
    v_admin  UUID;
    v_fake   UUID := gen_random_uuid();
    v_dry    JSONB;
    v_dry2   JSONB;
    v_app    JSONB;
    v_app2   JSONB;
    v_plan   INTEGER;
    v_nr0    INTEGER; v_nr1 INTEGER; v_nr2 INTEGER;
    v_va0    INTEGER; v_va1 INTEGER;
    v_cv0    INTEGER; v_cv1 INTEGER;
    v_log0   INTEGER; v_log1 INTEGER;
    v_hold0  TEXT;    v_hold1 TEXT;
    v_n      INTEGER;
    v_ok     BOOLEAN;
    v_err    TEXT;
    v_nr_ids UUID[];
BEGIN
    SELECT a.id INTO v_admin FROM public.admin_user a ORDER BY a.id LIMIT 1;
    IF v_admin IS NULL THEN RAISE EXCEPTION 'NRR_2843_FAIL S0: nenhum admin_user.'; END IF;

    -- S1 — estrutura
    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid = 'public.catalog_admin_action_log'::regclass
       AND conname IN ('ck_catalog_admin_action_log_action_valid','ck_catalog_admin_action_log_action_entity_match')
       AND pg_get_constraintdef(oid) LIKE '%CARD_VARIANT_IMPORT_ROWS_REVALIDATED%';
    IF v_n <> 2 THEN RAISE EXCEPTION 'NRR_2843_FAIL S1a: action nova presente em % de 2 CHECK.', v_n; END IF;

    SELECT p.prosecdef
           AND 'search_path=""' = ANY (p.proconfig)
           AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
           AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
           AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
      INTO v_ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'revalidate_needs_review_variant_rows';
    IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'NRR_2843_FAIL S1b: função ausente ou ACL/segurança incorretas.'; END IF;

    -- N1..N3 — guards de entrada
    BEGIN PERFORM internal.revalidate_needs_review_variant_rows(NULL, false, NULL);
          RAISE EXCEPTION 'NRR_2843_FAIL N1: ator nulo aceito.';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
          IF v_err NOT LIKE 'REVALIDATE_NR_MISSING_ACTOR%' THEN RAISE EXCEPTION 'NRR_2843_FAIL N1: %', v_err; END IF; END;
    BEGIN PERFORM internal.revalidate_needs_review_variant_rows(v_fake, false, NULL);
          RAISE EXCEPTION 'NRR_2843_FAIL N2: ator não-admin aceito.';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
          IF v_err NOT LIKE 'REVALIDATE_NR_ACTOR_NOT_ADMIN%' THEN RAISE EXCEPTION 'NRR_2843_FAIL N2: %', v_err; END IF; END;
    BEGIN PERFORM internal.revalidate_needs_review_variant_rows(v_admin, true, NULL);
          RAISE EXCEPTION 'NRR_2843_FAIL N3: apply sem expected aceito.';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
          IF v_err NOT LIKE 'REVALIDATE_NR_EXPECTED_REQUIRED%' THEN RAISE EXCEPTION 'NRR_2843_FAIL N3: %', v_err; END IF; END;

    -- Snapshot inicial
    SELECT count(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW'),
           count(*) FILTER (WHERE r.validation_status = 'VALID')
      INTO v_nr0, v_va0
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'STAGED' AND r.persistence_status = 'PENDING';
    SELECT array_agg(r.id) INTO v_nr_ids
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'STAGED' AND r.persistence_status = 'PENDING'
       AND r.validation_status = 'NEEDS_REVIEW';
    SELECT count(*) INTO v_cv0 FROM public.card_variant;
    SELECT count(*) INTO v_log0 FROM public.catalog_admin_action_log
     WHERE action = 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED';
    SELECT md5(string_agg(r.id::TEXT || r.validation_status || r.normalized_data::TEXT, ',' ORDER BY r.id))
      INTO v_hold0
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card_set cs ON cs.id = j.card_set_id
     WHERE j.status = 'STAGED' AND r.persistence_status = 'PENDING'
       AND ( public.normalize_external_catalog_value(r.raw_data->>'foil') IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM')
          OR (cs.code IN ('EX7','EX8','EX9','EX10') AND r.raw_data::TEXT ILIKE '%set-logo%') );

    -- D1/D2 — dry-run
    v_dry  := internal.revalidate_needs_review_variant_rows(v_admin, false, NULL);
    v_plan := (v_dry->>'plan_rows')::INTEGER;
    SELECT count(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW') INTO v_nr1
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'STAGED' AND r.persistence_status = 'PENDING';
    IF v_nr1 <> v_nr0 THEN RAISE EXCEPTION 'NRR_2843_FAIL D1: dry-run escreveu (% -> %).', v_nr0, v_nr1; END IF;
    IF v_plan IS NULL OR v_plan <= 0 THEN RAISE EXCEPTION 'NRR_2843_FAIL D2a: plano vazio (%).', v_dry; END IF;
    IF (v_dry->>'identity_conflicts')::INTEGER <> 0 THEN RAISE EXCEPTION 'NRR_2843_FAIL D2b: conflitos de identidade: %.', v_dry; END IF;
    IF (v_dry->>'excluded_hold_h3')::INTEGER < 1 THEN RAISE EXCEPTION 'NRR_2843_FAIL D2c: H3 não foi excluída: %.', v_dry; END IF;

    -- N4 — pin
    BEGIN PERFORM internal.revalidate_needs_review_variant_rows(v_admin, true, v_plan + 1);
          RAISE EXCEPTION 'NRR_2843_FAIL N4: expected errado aceito.';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
          IF v_err NOT LIKE 'REVALIDATE_NR_PLAN_DRIFT%' THEN RAISE EXCEPTION 'NRR_2843_FAIL N4: %', v_err; END IF; END;

    -- A1 — apply
    v_app := internal.revalidate_needs_review_variant_rows(v_admin, true, v_plan);
    IF (v_app->>'rows_revalidated')::INTEGER <> v_plan THEN
        RAISE EXCEPTION 'NRR_2843_FAIL A1: % revalidadas, plano %.', v_app->>'rows_revalidated', v_plan; END IF;

    -- A2
    SELECT count(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW'),
           count(*) FILTER (WHERE r.validation_status = 'VALID')
      INTO v_nr2, v_va1
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'STAGED' AND r.persistence_status = 'PENDING';
    IF v_nr0 - v_nr2 <> v_plan OR v_va1 - v_va0 <> v_plan THEN
        RAISE EXCEPTION 'NRR_2843_FAIL A2: NEEDS_REVIEW % -> %, VALID % -> %, plano %.', v_nr0, v_nr2, v_va0, v_va1, v_plan; END IF;

    -- A3 — holds intocados
    SELECT md5(string_agg(r.id::TEXT || r.validation_status || r.normalized_data::TEXT, ',' ORDER BY r.id))
      INTO v_hold1
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card_set cs ON cs.id = j.card_set_id
     WHERE j.status = 'STAGED' AND r.persistence_status = 'PENDING'
       AND ( public.normalize_external_catalog_value(r.raw_data->>'foil') IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM')
          OR (cs.code IN ('EX7','EX8','EX9','EX10') AND r.raw_data::TEXT ILIKE '%set-logo%') );
    IF v_hold1 IS DISTINCT FROM v_hold0 THEN RAISE EXCEPTION 'NRR_2843_FAIL A3: linhas de HOLD foram alteradas.'; END IF;

    -- A4/A5 — shape e campos de decisão das linhas promovidas nesta execução
    SELECT count(*) FILTER (WHERE r.validation_status = 'VALID'),
           count(*) FILTER (WHERE r.validation_status = 'VALID' AND (
                 jsonb_typeof(r.normalized_data->'variant_type_id') IS DISTINCT FROM 'string'
              OR coalesce(jsonb_typeof(r.normalized_data->'printing_profile_id'), 'ausente') NOT IN ('null','string')
              OR coalesce(jsonb_typeof(r.normalized_data->'edition_context_profile_id'), 'ausente') NOT IN ('null','string')
              OR r.decision_status <> 'PENDING' OR r.persistence_status <> 'PENDING'
              OR r.resulting_variant_id IS NOT NULL))
      INTO v_n, v_err
      FROM public.catalog_variant_import_row r
     WHERE r.id = ANY (v_nr_ids);
    IF v_n <> v_plan THEN RAISE EXCEPTION 'NRR_2843_FAIL A4a: % ex-NEEDS_REVIEW agora VALID, plano %.', v_n, v_plan; END IF;
    IF v_err::INTEGER <> 0 THEN RAISE EXCEPTION 'NRR_2843_FAIL A4b/A5: % linha(s) promovida(s) com shape ou decisão inválidos.', v_err; END IF;

    -- A6 — auditoria
    SELECT count(*), sum((metadata->>'rows_revalidated')::INTEGER)::INTEGER INTO v_log1, v_n
      FROM public.catalog_admin_action_log
     WHERE action = 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED' AND metadata->>'run_id' = v_app->>'run_id';
    IF v_log1 <> (v_app->>'jobs_affected')::INTEGER OR v_n <> v_plan THEN
        RAISE EXCEPTION 'NRR_2843_FAIL A6: % linhas de log para % jobs; soma % para plano %.', v_log1, v_app->>'jobs_affected', v_n, v_plan; END IF;

    -- A7 — idempotência
    v_dry2 := internal.revalidate_needs_review_variant_rows(v_admin, false, NULL);
    IF (v_dry2->>'plan_rows')::INTEGER <> 0 THEN RAISE EXCEPTION 'NRR_2843_FAIL A7a: 2º dry-run com plano %.', v_dry2->>'plan_rows'; END IF;
    v_app2 := internal.revalidate_needs_review_variant_rows(v_admin, true, 0);
    SELECT count(*) INTO v_n FROM public.catalog_admin_action_log
     WHERE action = 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED' AND metadata->>'run_id' = v_app2->>'run_id';
    IF v_n <> 0 OR (v_app2->>'rows_revalidated')::INTEGER <> 0 THEN
        RAISE EXCEPTION 'NRR_2843_FAIL A7b: 2º apply escreveu ou auditou (%).', v_app2; END IF;

    -- A8 — nenhuma Card Variant criada
    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 <> v_cv0 THEN RAISE EXCEPTION 'NRR_2843_FAIL A8: card_variant % -> %.', v_cv0, v_cv1; END IF;

    RAISE EXCEPTION 'NRR_2843_ROLLBACK_PASS: todos os casos (S1 N1-N4 D1-D2 A1-A8) | plano=% | dry=% | apply=%', v_plan, v_dry, v_app;
END;
$h$;
