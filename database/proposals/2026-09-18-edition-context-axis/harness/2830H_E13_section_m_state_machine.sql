-- ============================================================================
-- 2830H · ENVELOPE E13 — SEÇÃO M (STATE MACHINE job-aware, SM1–SM11) · lote L11, 11 casos
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E13P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 Seção M; fonte lógica 2833 v2.0 (arquivo NÃO alterado).
-- Classificador . pode_mutar / pode_confirmar = texto único (2145), usado em REAL,
--                 controles em memória e fixtures.
-- P13 ........... SM1–3, SM7, SM8, SM10(ii): real = 0 e controle = 1 (mesmo texto).
--                 SM4, SM6, SM10(i), SM11: fixture. SM5/SM9: universo medido > 0
--                 (propriedade da definição, declarada). SM8 = SM7 (declarado).
-- Escrita (R4) .. job 1–8 por caso · row: SM4 1, SM6 512, SM10 5, SM11 2.
--                 Nenhum UPDATE/DELETE. Tudo desfeito pelo término em exceção.
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e13$
DECLARE
    c_env      CONSTANT text   := 'E13_SECAO_M_STATE_MACHINE';
    c_expected CONSTANT text[] := ARRAY['SM1','SM2','SM3','SM4','SM5','SM6','SM7','SM8','SM9','SM10','SM11'];
    v_marker   text := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''));
    v_t0       timestamptz := clock_timestamp();
    v_done     text[] := ARRAY[]::text[];
    v_case     text;
    v_game     uuid;
    v_src      uuid;
    v_n        bigint;
    v_m        bigint;
    v_got      boolean;
    v_state    text;
    v_con      text;
    v_tab      text;
    v_msg      text;
    v_txt      text;
    v_card     uuid;
    v_cs       uuid;
    v_vt       uuid;
    v_pp       uuid;
    v_ec       uuid;
    v_agg      jsonb;
    v_cards    uuid[];
    v_jobs     uuid[];
    v_job1     uuid;
    v_job2     uuid;
    v_cv       uuid;
    v_r1       uuid;
    v_r2       uuid;
    v_r3       uuid;
    v_r4       uuid;
    v_r5       uuid;
    v_k        bigint;
    v_barr     boolean[];
BEGIN
    -- ------------------------------------------------------------------ --
    -- P8 / DP-4 = A: lock_timeout transacional, primeira instrução executável
    -- ------------------------------------------------------------------ --
    SET LOCAL lock_timeout = '5s';
    IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT lock_timeout=%s (esperado 5s)', c_env, current_setting('lock_timeout'));
    END IF;

    -- ------------------------------------------------------------------ --
    -- PREFLIGHT (não é caso; falha = H2830_FAIL, nunca PASS)
    -- ------------------------------------------------------------------ --
    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT game code=POKEMON count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT count(*) INTO v_n FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT asset_source code=TCGDEX count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';

    -- ------------------------------------------------------------------ --
    -- MATRIZ ÚNICA (SMREC) — rows reais + controles em memória; erro = FAIL
    -- ------------------------------------------------------------------ --
    v_case := 'SMREC';
    BEGIN
        WITH x AS (
            SELECT 'REAL'::text AS src, j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat
            FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
            UNION ALL
            SELECT * FROM (VALUES ('CTRL_sm1', 'H2830_DESCONHECIDO', 'VALID', 'APPROVED', 'INSERTED', true, true, 'vt'::text, '00000000-0000-4000-8000-0000000000c1'::uuid, NULL::uuid),
                   ('CTRL_sm2', 'COMPLETED', 'VALID', 'APPROVED', 'H2830_DESCONHECIDO', true, true, 'vt'::text, '00000000-0000-4000-8000-0000000000c1'::uuid, NULL::uuid),
                   ('CTRL_sm3a', 'COMPLETED', 'VALID', 'APPROVED', 'INSERTED', true, true, 'vt'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_sm3b', 'COMPLETED', 'VALID', 'APPROVED', 'UNCHANGED', true, true, 'vt'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_sm4', 'STAGED', 'VALID', 'APPROVED', 'PENDING', true, true, 'vt'::text, '00000000-0000-4000-8000-0000000000c1'::uuid, NULL::uuid),
                   ('CTRL_sm7', 'STAGED', 'VALID', 'PENDING', 'PENDING', false, true, 'vt'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_sm8', 'CONFIRMING', 'VALID', 'PENDING', 'PENDING', false, true, 'vt'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_sm10ii', 'STAGED', 'VALID', 'APPROVED', 'PENDING', false, true, 'vt'::text, NULL::uuid, NULL::uuid)) AS c(src, job_status, val, dec, per, has_key, has_pp, vt, res, mat)
        )
        SELECT jsonb_build_object(
            'sm1', count(*) FILTER (WHERE src = 'REAL' AND (job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING','COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED'))),
            'sm1_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm1' AND (job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING','COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED'))),
            'sm2', count(*) FILTER (WHERE src = 'REAL' AND (per NOT IN ('PENDING','INSERTED','UNCHANGED','FAILED','SKIPPED'))),
            'sm2_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm2' AND (per NOT IN ('PENDING','INSERTED','UNCHANGED','FAILED','SKIPPED'))),
            'sm3a', count(*) FILTER (WHERE src = 'REAL' AND (per = 'INSERTED' AND res IS NULL)),
            'sm3a_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm3a' AND (per = 'INSERTED' AND res IS NULL)),
            'sm3b', count(*) FILTER (WHERE src = 'REAL' AND (per = 'UNCHANGED' AND dec <> 'SKIPPED' AND res IS NULL AND mat IS NULL)),
            'sm3b_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm3b' AND (per = 'UNCHANGED' AND dec <> 'SKIPPED' AND res IS NULL AND mat IS NULL)),
            'sm4', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND res IS NOT NULL)),
            'sm4_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm4' AND ((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND res IS NOT NULL)),
            'sm7', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND val = 'VALID' AND NOT has_key)),
            'sm7_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm7' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND val = 'VALID' AND NOT has_key)),
            'sm10ii', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND (vt IS NULL OR NOT has_pp OR NOT has_key))),
            'sm10ii_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm10ii' AND ((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND (vt IS NULL OR NOT has_pp OR NOT has_key))),
            'sm8', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND val = 'VALID' AND NOT has_key)),
            'sm8_ctrl', count(*) FILTER (WHERE src = 'CTRL_sm8' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND val = 'VALID' AND NOT has_key)),
            'u_rows', count(*) FILTER (WHERE src = 'REAL' AND (true)),
            'u_mut', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING'))),
            'u_conf', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID'))),
            'u_lineage', count(*) FILTER (WHERE src = 'REAL' AND (per IN ('INSERTED','UNCHANGED'))),
            'u_sm5_term_vp', count(*) FILTER (WHERE src = 'REAL' AND (val = 'VALID' AND per = 'PENDING' AND job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING'))),
            'u_sm5', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING'))),
            'u_sm6', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND NOT (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING'))),
            'u_mut_valid', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND val = 'VALID')),
            'u_cancel', count(*) FILTER (WHERE src = 'REAL' AND (job_status = 'CANCELLED')),
            'u_sm9', count(*) FILTER (WHERE src = 'REAL' AND (job_status = 'CANCELLED' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') OR (job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID')))),
            'u_hist_nokey', count(*) FILTER (WHERE src = 'REAL' AND (NOT (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND NOT has_key)),
            'u_sm11', count(*) FILTER (WHERE src = 'REAL' AND (NOT (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND NOT has_key AND (job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID'))),
            'u_nr_mut', count(*) FILTER (WHERE src = 'REAL' AND ((job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND val = 'NEEDS_REVIEW')),
            'st_distinct', count(DISTINCT job_status) FILTER (WHERE src = 'REAL'),
            'per_distinct', count(DISTINCT per) FILTER (WHERE src = 'REAL'))
          FROM x
          INTO STRICT v_agg;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=SMREC matriz falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;
    SELECT ARRAY(SELECT c.id FROM public.card c
                   JOIN public.card_set cs ON cs.id = c.card_set_id
                   JOIN public.expansion e ON e.id = cs.expansion_id
                  WHERE e.game_id = v_game ORDER BY c.id LIMIT 16) INTO v_cards;
    IF cardinality(v_cards) <> 16 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT fixture de 16 Cards indisponível (%s)', c_env, cardinality(v_cards));
    END IF;

    -- ================================================================== --
    -- SM1 [AUTO EX] vocabulário de job.status (8 valores do CHECK)
    -- ================================================================== --
    v_case := 'SM1';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm1')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm1: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm1')::bigint);
        END IF;
        IF (v_agg->>'sm1_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm1: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm1_ctrl')::bigint);
        END IF;
        IF (v_agg->>'u_rows')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM1: universo vazio (P13)', c_env, v_case);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM2 [AUTO EX] vocabulário de persistence_status
    -- ================================================================== --
    v_case := 'SM2';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm2')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm2: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm2')::bigint);
        END IF;
        IF (v_agg->>'sm2_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm2: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm2_ctrl')::bigint);
        END IF;
        IF (v_agg->>'u_rows')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM2: universo vazio (P13)', c_env, v_case);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM3 [AUTO EX] nenhuma row terminal sem efeito, por classe (ROWS sem lineage)
    -- ================================================================== --
    v_case := 'SM3';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm3a')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm3a: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm3a')::bigint);
        END IF;
        IF (v_agg->>'sm3a_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm3a: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm3a_ctrl')::bigint);
        END IF;
        IF (v_agg->>'sm3b')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm3b: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm3b')::bigint);
        END IF;
        IF (v_agg->>'sm3b_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm3b: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm3b_ctrl')::bigint);
        END IF;
        IF (v_agg->>'u_lineage')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM3: universo vazio (P13)', c_env, v_case);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM4 [AUTO EX+FX] nenhuma row confirmável com resulting_variant_id; controle em fixture
    -- ================================================================== --
    v_case := 'SM4';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm4')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm4: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm4')::bigint);
        END IF;
        IF (v_agg->>'sm4_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm4: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm4_ctrl')::bigint);
        END IF;
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        SELECT cv.id INTO v_cv FROM public.card_variant cv ORDER BY cv.id LIMIT 1;
        IF v_cv IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s nenhuma card_variant para o controle (STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status, resulting_variant_id)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING', 'APPROVED', v_cv)
        RETURNING id INTO v_r1;
        SELECT count(*) FILTER (WHERE (job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND res IS NOT NULL) INTO v_n
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.id
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
               WHERE j.external_set_id LIKE v_marker || '\_J%') z;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM4 fixture: row confirmável com resulting_variant_id NÃO detectada (%s, esperado 1)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM5 [AUTO EX] nenhuma row mutável em job terminal (interseção medida)
    -- ================================================================== --
    v_case := 'SM5';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'u_sm5')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM5: %s row(s) mutáveis em job terminal', c_env, v_case, (v_agg->>'u_sm5')::bigint);
        END IF;
        IF (v_agg->>'u_sm5_term_vp')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM5: universo vazio (P13)', c_env, v_case);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM6 [AUTO EX+FX] todo confirmável está no mutável; enumeração 8×4×4×4 em fixture
    -- ================================================================== --
    v_case := 'SM6';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        v_jobs := ARRAY[]::uuid[];
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'RECEIVED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela RECEIVED não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'PROCESSING')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela PROCESSING não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J3', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J4', 'CONFIRMING')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CONFIRMING não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J5', 'COMPLETED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J6', 'COMPLETED_WITH_ERRORS')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED_WITH_ERRORS não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J7', 'FAILED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela FAILED não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J8', 'CANCELLED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CANCELLED não criado', c_env, v_case);
        END IF;
        v_jobs := v_jobs || v_job1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, decision_status, persistence_status)
        SELECT jb.id, v_cards[(k.i / 4) + 1], '{}'::jsonb,
               jsonb_build_object('variant_type_id', v_vt,
                                  'printing_profile_id', CASE WHEN k.i % 2 = 1 THEN v_pp END,
                                  'edition_context_profile_id', CASE WHEN (k.i / 2) % 2 = 1 THEN v_ec END),
               k.v, k.d, k.p
          FROM unnest(v_jobs) AS jb(id)
         CROSS JOIN (SELECT p, d, v, (row_number() OVER (ORDER BY p, d, v) - 1)::int AS i
                       FROM unnest(ARRAY['PENDING','INSERTED','UNCHANGED','FAILED']) AS p
                      CROSS JOIN unnest(ARRAY['PENDING','APPROVED','REJECTED','SKIPPED']) AS d
                      CROSS JOIN unnest(ARRAY['PENDING','VALID','NEEDS_REVIEW','INVALID']) AS v) AS k;
        GET DIAGNOSTICS v_m = ROW_COUNT;
        IF v_m <> 512 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM6 fixture: %s rows enumeradas (esperado 8 × 4 × 4 × 4 = 512)', c_env, v_case, v_m);
        END IF;
        SELECT count(*) FILTER (WHERE (job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID') AND NOT (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING')) INTO v_n
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.id
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
               WHERE j.external_set_id LIKE v_marker || '\_J%') z;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM6: %s combinação(ões) confirmável(is) fora do universo mutável', c_env, v_case, v_n);
        END IF;
        SELECT count(*) FILTER (WHERE (job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID')) INTO v_k
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.id
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
               WHERE j.external_set_id LIKE v_marker || '\_J%') z;
        IF v_k <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM6: classificador confirmável marcou %s combinação(ões) (esperado 2: STAGED e CONFIRMING × PENDING/APPROVED/VALID)', c_env, v_case, v_k);
        END IF;
        SELECT count(*) FILTER (WHERE (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING')) INTO v_k
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.id
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
               WHERE j.external_set_id LIKE v_marker || '\_J%') z;
        IF v_k <> 64 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM6: classificador mutável marcou %s (esperado 4 status × PENDING × 16 = 64)', c_env, v_case, v_k);
        END IF;
        IF (v_agg->>'u_sm6')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM6 real: %s row(s) confirmáveis fora do mutável', c_env, v_case, (v_agg->>'u_sm6')::bigint);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM7 [AUTO EX] zero row mutável VALID sem a chave
    -- ================================================================== --
    v_case := 'SM7';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm7')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm7: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm7')::bigint);
        END IF;
        IF (v_agg->>'sm7_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm7: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm7_ctrl')::bigint);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM8 [AUTO EX] toda row sem chave é histórica ou não-VALID (DECLARADO = SM7)
    -- ================================================================== --
    v_case := 'SM8';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm8')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm8: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm8')::bigint);
        END IF;
        IF (v_agg->>'sm8_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm8: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm8_ctrl')::bigint);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM9 [AUTO EX] nenhuma row CANCELLED mutável ou confirmável
    -- ================================================================== --
    v_case := 'SM9';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'u_sm9')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM9: %s row(s) CANCELLED mutáveis/confirmáveis', c_env, v_case, (v_agg->>'u_sm9')::bigint);
        END IF;
        IF (v_agg->>'u_cancel')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM9: universo vazio (P13)', c_env, v_case);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM10 [AUTO FX] (i) classificador em fixture + 4 negações; (ii) universo real + controle em memória
    -- ================================================================== --
    v_case := 'SM10';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'sm10ii')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm10ii: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'sm10ii')::bigint);
        END IF;
        IF (v_agg->>'sm10ii_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sm10ii: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, (v_agg->>'sm10ii_ctrl')::bigint);
        END IF;
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'CANCELLED')
        RETURNING id INTO v_job2;
        IF v_job2 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CANCELLED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job1, v_cards[1], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING', 'APPROVED')
        RETURNING id INTO v_r1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job2, v_cards[1], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING', 'APPROVED')
        RETURNING id INTO v_r2;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job1, v_cards[2], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'FAILED', 'APPROVED')
        RETURNING id INTO v_r3;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job1, v_cards[3], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING', 'REJECTED')
        RETURNING id INTO v_r4;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job1, v_cards[4], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING', 'APPROVED')
        RETURNING id INTO v_r5;
        SELECT array_agg(((job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID')) ORDER BY z.ord)
          INTO v_barr
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, array_position(ARRAY[v_r1, v_r2, v_r3, v_r4, v_r5], r.id) AS ord
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
                 WHERE r.id = ANY (ARRAY[v_r1, v_r2, v_r3, v_r4, v_r5])) z;
        IF v_barr IS DISTINCT FROM ARRAY[true, false, false, false, false] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM10(i): classificador pode_confirmar [base, CANCELLED, persistence≠PENDING, decision≠APPROVED, NEEDS_REVIEW] = %s (esperado [t,f,f,f,f])', c_env, v_case, v_barr);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- SM11 [AUTO EX+FX] nenhuma row histórica sem chave é confirmável
    -- ================================================================== --
    v_case := 'SM11';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_jobs := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_cv := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_r3 := NULL;
    v_r4 := NULL;
    v_r5 := NULL;
    v_k := NULL;
    v_barr := NULL;
    BEGIN
        IF (v_agg->>'u_hist_nokey')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM11: universo vazio (P13)', c_env, v_case);
        END IF;
        IF (v_agg->>'u_sm11')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM11 real: %s row(s) históricas sem chave classificadas como confirmáveis', c_env, v_case, (v_agg->>'u_sm11')::bigint);
        END IF;
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'COMPLETED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'CANCELLED')
        RETURNING id INTO v_job2;
        IF v_job2 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CANCELLED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job1, v_cards[1], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING', 'APPROVED')
        RETURNING id INTO v_r1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job2, v_cards[1], '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING', 'APPROVED')
        RETURNING id INTO v_r2;
        SELECT count(*) FILTER (WHERE NOT (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND NOT has_key) INTO v_k
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.id
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
               WHERE j.external_set_id LIKE v_marker || '\_J%') z;
        IF v_k <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM11 fixture: universo histórico sem chave = %s (esperado 2)', c_env, v_case, v_k);
        END IF;
        SELECT count(*) FILTER (WHERE NOT (job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND per = 'PENDING') AND NOT has_key AND (job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID')) INTO v_n
          FROM (SELECT j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
                   r.normalized_data ->> 'variant_type_id' AS vt,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.id
                FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
               WHERE j.external_set_id LIKE v_marker || '\_J%') z;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SM11 fixture: %s row(s) históricas sem chave classificadas como confirmáveis', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ------------------------------------------------------------------ --
    -- GATE DO ENVELOPE: exatamente os casos esperados, na ordem, cada um uma vez
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s u_rows=%s u_mut=%s u_conf=%s u_nr_mut=%s u_hist_nokey=%s u_cancel=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), v_agg->>'u_rows', v_agg->>'u_mut', v_agg->>'u_conf', v_agg->>'u_nr_mut', v_agg->>'u_hist_nokey', v_agg->>'u_cancel');
END
$h2830_e13$;
