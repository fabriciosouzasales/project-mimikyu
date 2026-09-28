-- ============================================================================
-- 2830H · ENVELOPE E09 — SEÇÃO S (STAGING) · lote L7, 12 casos: S1–S11 com S2-BIS
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E09P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 571–622). Contratos de erro =
--                 LIVE (internal.guard_cvir_normalized_shape, 2214 v3.1, pinado).
-- Autoridades ... 2210 (axis_identity_token, uq_cvir_row_identity), 2214 (guard
--                 G1/G2/G3), 2136/2138 (job/row, CHECKs, fingerprint).
-- Fixtures ...... Card real ORDER BY id do Game real e o seu Card Set; Variant Type
--                 e profiles ORDER BY id. Jobs sentinela TCGDEX com
--                 external_set_id = marcador || _J<n> (P5). Rows só em job de
--                 fixture. Nenhum UPDATE/DELETE.
-- S10 ........... 4 sub-asserções (a)–(d) do contrato v7.0, com (a) nos dois
--                 regimes de job e contraprova de (d) no COMPLETED.
-- Escrita (R4) .. job 1–2 por caso · row: S4 2, S5 1 + 1 recusada, S6 2, S7 2,
--                 S8 6 recusadas, S9 2 recusadas, S10 1 + 5 recusadas, S11 2.
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e09$
DECLARE
    c_env      CONSTANT text   := 'E09_SECAO_S_STAGING';
    c_expected CONSTANT text[] := ARRAY['S1','S2','S2-BIS','S3','S4','S5','S6','S7','S8','S9','S10','S11'];
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
    v_job1     uuid;
    v_job2     uuid;
    v_r1       uuid;
    v_r2       uuid;
    v_u        uuid;
    v_a        text;
    v_nn       text;
    v_uu       text;
    v_c1       text;
    v_c2       text;
    v_b        boolean;
    v_cfg      text[];
    v_arr      text[];
    v_k        bigint;
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

    -- ================================================================== --
    -- S1 — axis_identity_token: ausente 'A'; JSON null 'N'; uuid 'U:<uuid>'; ->> SQL NULL em A e N (RC)
    -- ================================================================== --
    v_case := 'S1';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
    BEGIN
        v_u := gen_random_uuid();
        v_a := internal.axis_identity_token('{}'::jsonb, 'edition_context_profile_id');
        v_nn := internal.axis_identity_token(jsonb_build_object('edition_context_profile_id', NULL), 'edition_context_profile_id');
        v_uu := internal.axis_identity_token(jsonb_build_object('edition_context_profile_id', v_u), 'edition_context_profile_id');
        IF v_a IS DISTINCT FROM 'A' OR v_nn IS DISTINCT FROM 'N' OR v_uu IS DISTINCT FROM 'U:' || v_u::text THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tokens divergentes: ausente=%s null=%s uuid=%s (esperado A, N, U:<uuid>)', c_env, v_case, v_a, v_nn, v_uu);
        END IF;
        IF ('{}'::jsonb ->> 'edition_context_profile_id') IS NOT NULL
           OR (jsonb_build_object('edition_context_profile_id', NULL) ->> 'edition_context_profile_id') IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ->> não colapsa A e N em SQL NULL', c_env, v_case);
        END IF;
        IF internal.axis_identity_token('{}'::jsonb, 'edition_context_profile_id') IS NULL OR internal.axis_identity_token(jsonb_build_object('edition_context_profile_id', NULL), 'edition_context_profile_id') IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token nulo para entrada A ou N (função deixou de ser total)', c_env, v_case);
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
    -- S2 — axis_identity_token IMMUTABLE + PARALLEL SAFE + search_path='' e NÃO STRICT (RO)
    -- ================================================================== --
    v_case := 'S2';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
    BEGIN
        SELECT p.provolatile::text, p.proparallel::text, p.proisstrict, p.proconfig::text[],
               md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))
          INTO STRICT v_c1, v_c2, v_b, v_cfg, v_txt
          FROM pg_proc p WHERE p.oid = to_regprocedure('internal.axis_identity_token(jsonb,text)');
        IF v_c1 IS DISTINCT FROM 'i' OR v_c2 IS DISTINCT FROM 's' OR v_b IS DISTINCT FROM false
           OR v_cfg IS DISTINCT FROM ARRAY['search_path=""'] OR v_txt IS DISTINCT FROM '18682dce935281b0a4437628a6e8309a' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s axis_identity_token divergente: vol=%s parallel=%s strict=%s config=%s md5=%s', c_env, v_case, v_c1, v_c2, v_b, v_cfg, v_txt);
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
    -- S2-BIS — COMMENT contém 'REINDEX' e a proibição de STRICT (RO)
    -- ================================================================== --
    v_case := 'S2-BIS';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
    BEGIN
        v_txt := obj_description(to_regprocedure('internal.axis_identity_token(jsonb,text)'), 'pg_proc');
        IF v_txt IS NULL OR strpos(v_txt, 'REINDEX') = 0 OR strpos(v_txt, 'NAO adicionar STRICT') = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s COMMENT sem ''REINDEX'' e/ou sem a proibição de STRICT: %s', c_env, v_case, v_txt);
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
    -- S3 — uq_cvir_row_identity UNIQUE com 5 expressões; nomes antigos ausentes; UNIQUE = {pkey, uq_cvir_row_identity} (RO)
    -- ================================================================== --
    v_case := 'S3';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
    BEGIN
        SELECT i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts = 5
               AND (SELECT array_agg(a.attname::text ORDER BY k.ord)
                      FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
                      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
                     WHERE k.attnum <> 0) = ARRAY['job_id', 'card_id'],
               ARRAY[regexp_replace(regexp_replace(lower(pg_get_indexdef(i.indexrelid, 3, true)), '[[:space:]()]|::text', '', 'g'), 'internal[.]', '', 'g'),
                     regexp_replace(regexp_replace(lower(pg_get_indexdef(i.indexrelid, 4, true)), '[[:space:]()]|::text', '', 'g'), 'internal[.]', '', 'g'),
                     regexp_replace(regexp_replace(lower(pg_get_indexdef(i.indexrelid, 5, true)), '[[:space:]()]|::text', '', 'g'), 'internal[.]', '', 'g'),
                     regexp_replace(regexp_replace(lower(pg_get_expr(i.indpred, i.indrelid)), '[[:space:]()]|::text', '', 'g'), 'internal[.]', '', 'g')]
          INTO STRICT v_b, v_arr
          FROM pg_index i
         WHERE i.indexrelid = to_regclass('public.uq_cvir_row_identity')
           AND i.indrelid = to_regclass('public.catalog_variant_import_row');
        IF NOT v_b OR v_arr IS DISTINCT FROM ARRAY['normalized_data->>''variant_type_id''',
                                              'axis_identity_tokennormalized_data,''printing_profile_id''',
                                              'axis_identity_tokennormalized_data,''edition_context_profile_id''',
                                              'normalized_data->>''variant_type_id''isnotnull'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_cvir_row_identity divergente: estrutura=%s expressões=%s', c_env, v_case, v_b, v_arr);
        END IF;
        SELECT count(*) INTO v_n FROM unnest(ARRAY['uq_cvir_job_card_type_no_printing', 'uq_cvir_job_card_type_printing',
                                                'uq_catalog_variant_import_row_job_card_variant_type']) AS x(n)
         WHERE to_regclass('public.' || x.n) IS NOT NULL;
        SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO v_arr
          FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
         WHERE i.indrelid = to_regclass('public.catalog_variant_import_row') AND i.indisunique;
        IF v_n <> 0 OR v_arr IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey', 'uq_cvir_row_identity'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s nomes antigos presentes=%s ou UNIQUE da tabela=%s (esperado {pkey, uq_cvir_row_identity})', c_env, v_case, v_n, v_arr);
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
    -- S4 — mesmo job/card/vt/printing coexistem diferindo só em EC ('N' × 'U'); contraprova de 3 componentes (FX)
    -- ================================================================== --
    v_case := 'S4';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', v_ec), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r2;
        SELECT count(*), count(DISTINCT internal.axis_identity_token(normalized_data, 'edition_context_profile_id')),
               count(DISTINCT internal.axis_identity_token(normalized_data, 'printing_profile_id'))
          INTO v_n, v_m, v_k FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF NOT (v_n = 2 AND v_m = 2 AND v_k = 1) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s coexistência N × U no eixo EC: linhas=%s tokens_ec=%s tokens_pp=%s', c_env, v_case, v_n, v_m, v_k);
        END IF;
        SELECT count(DISTINCT (job_id, card_id, normalized_data ->> 'variant_type_id', internal.axis_identity_token(normalized_data, 'printing_profile_id'))),
               count(DISTINCT (job_id, card_id, normalized_data ->> 'variant_type_id', internal.axis_identity_token(normalized_data, 'printing_profile_id'),
                               internal.axis_identity_token(normalized_data, 'edition_context_profile_id')))
          INTO v_n, v_m FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF v_n <> 1 OR v_m <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s contraprova: chave de 3 componentes=%s (esperado 1, colidiriam) · chave de 5=%s (esperado 2)', c_env, v_case, v_n, v_m);
        END IF;
        SELECT array_agg(internal.axis_identity_token(normalized_data, 'edition_context_profile_id') ORDER BY 1) INTO v_arr FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF v_arr IS DISTINCT FROM ARRAY['N', 'U:' || v_ec::text] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tokens EC divergentes: %s', c_env, v_case, v_arr);
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
    -- S5 — duplicata real nos 5 componentes ⇒ 23505 uq_cvir_row_identity (FX)
    -- ================================================================== --
    v_case := 'S5';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r1;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
            RETURNING id INTO v_r2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata real nos 5 componentes foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_cvir_row_identity' OR v_tab IS DISTINCT FROM 'catalog_variant_import_row' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata real nos 5 componentes: rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*), count(DISTINCT internal.axis_identity_token(normalized_data, 'edition_context_profile_id')),
               count(DISTINCT internal.axis_identity_token(normalized_data, 'printing_profile_id'))
          INTO v_n, v_m, v_k FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF NOT (v_n = 1) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: linhas=%s tokens_ec=%s tokens_pp=%s', c_env, v_case, v_n, v_m, v_k);
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
    -- S6 — 'A' × 'N' coexistem (FX)
    -- ================================================================== --
    v_case := 'S6';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r2;
        SELECT count(*), count(DISTINCT internal.axis_identity_token(normalized_data, 'edition_context_profile_id')),
               count(DISTINCT internal.axis_identity_token(normalized_data, 'printing_profile_id'))
          INTO v_n, v_m, v_k FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF NOT (v_n = 2 AND v_m = 2 AND v_k = 1) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s coexistência A × N no eixo EC: linhas=%s tokens_ec=%s tokens_pp=%s', c_env, v_case, v_n, v_m, v_k);
        END IF;
        SELECT array_agg(internal.axis_identity_token(normalized_data, 'edition_context_profile_id') ORDER BY 1) INTO v_arr FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF v_arr IS DISTINCT FROM ARRAY['A', 'N'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tokens EC divergentes: %s', c_env, v_case, v_arr);
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
    -- S7 — 'N' × 'U' coexistem no eixo printing_profile_id (FX)
    -- ================================================================== --
    v_case := 'S7';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', v_pp, 'edition_context_profile_id', NULL), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r2;
        SELECT count(*), count(DISTINCT internal.axis_identity_token(normalized_data, 'edition_context_profile_id')),
               count(DISTINCT internal.axis_identity_token(normalized_data, 'printing_profile_id'))
          INTO v_n, v_m, v_k FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF NOT (v_n = 2 AND v_m = 1 AND v_k = 2) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s coexistência N × U no eixo Printing: linhas=%s tokens_ec=%s tokens_pp=%s', c_env, v_case, v_n, v_m, v_k);
        END IF;
        SELECT array_agg(internal.axis_identity_token(normalized_data, 'printing_profile_id') ORDER BY 1) INTO v_arr FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF v_arr IS DISTINCT FROM ARRAY['N', 'U:' || v_pp::text] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tokens Printing divergentes: %s', c_env, v_case, v_arr);
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
    -- S8 — tipo inválido no eixo ⇒ CVIR_SHAPE_INVALID_EDITION_CONTEXT / _PRINTING (FX)
    -- ================================================================== --
    v_case := 'S8';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('edition_context_profile_id', 1), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id número foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_EDITION_CONTEXT:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id número: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('edition_context_profile_id', jsonb_build_array('x')), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id array foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_EDITION_CONTEXT:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id array: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('edition_context_profile_id', jsonb_build_object('x', 1)), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id objeto foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_EDITION_CONTEXT:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id objeto: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('printing_profile_id', 1), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id número foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_PRINTING:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id número: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('printing_profile_id', jsonb_build_array('x')), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id array foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_PRINTING:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id array: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('printing_profile_id', jsonb_build_object('x', 1)), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id objeto foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_PRINTING:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id objeto: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois dos negativos: %s row(s) no job de fixture (esperado 0)', c_env, v_case, v_n);
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
    -- S9 — string não-UUID ('banana') ⇒ CVIR_SHAPE_INVALID_* 'nao e UUID valido' (FX)
    -- ================================================================== --
    v_case := 'S9';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('edition_context_profile_id', 'banana'), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id ''banana'' foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_EDITION_CONTEXT:') OR strpos(v_msg, 'nao e UUID valido') = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s edition_context_profile_id ''banana'': rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('printing_profile_id', 'banana'), 'NEEDS_REVIEW', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id ''banana'' foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_SHAPE_INVALID_PRINTING:') OR strpos(v_msg, 'nao e UUID valido') = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s printing_profile_id ''banana'': rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois dos negativos: %s row(s) no job de fixture (esperado 0)', c_env, v_case, v_n);
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
    -- S10 — VALID exige as chaves no seu escopo: (a) vt · (b)/(c) printing, não job-aware · (d) EC job-aware (FX)
    -- ================================================================== --
    v_case := 'S10';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'COMPLETED')
        RETURNING id INTO v_job2;
        IF v_job2 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (a) VALID sem variant_type_id em job STAGED foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_VALID_REQUIRES_VARIANT_TYPE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (a) VALID sem variant_type_id em job STAGED: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job2, v_card, '{}'::jsonb, jsonb_build_object('printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (a) VALID sem variant_type_id em job COMPLETED foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_VALID_REQUIRES_VARIANT_TYPE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (a) VALID sem variant_type_id em job COMPLETED: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'edition_context_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (b) VALID sem a chave printing_profile_id em job STAGED (operacional) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_VALID_REQUIRES_PRINTING_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (b) VALID sem a chave printing_profile_id em job STAGED (operacional): rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job2, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'edition_context_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (c) VALID sem a chave printing_profile_id em job COMPLETED (terminal) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_VALID_REQUIRES_PRINTING_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (c) VALID sem a chave printing_profile_id em job COMPLETED (terminal): rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (d) VALID+PENDING sem a chave edition_context_profile_id em job STAGED foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (d) VALID+PENDING sem a chave edition_context_profile_id em job STAGED: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job2, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE job_id = v_job1;
        SELECT count(*) INTO v_m FROM public.catalog_variant_import_row WHERE job_id = v_job2 AND id = v_r1 AND validation_status = 'VALID'
           AND persistence_status = 'PENDING' AND NOT jsonb_exists(normalized_data, 'edition_context_profile_id');
        IF v_n <> 0 OR v_m <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s (d) contraprova: rows no STAGED=%s (esperado 0) · mesmo payload aceito no COMPLETED=%s (esperado 1)', c_env, v_case, v_n, v_m);
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
    -- S11 — row NEEDS_REVIEW em job operacional sem as duas chaves: permitido (FX)
    -- ================================================================== --
    v_case := 'S11';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    v_u := NULL;
    v_a := NULL;
    v_nn := NULL;
    v_uu := NULL;
    v_c1 := NULL;
    v_c2 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_arr := NULL;
    v_k := NULL;
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
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, '{}'::jsonb, 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r1;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt), 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r2;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row
         WHERE job_id = v_job1 AND validation_status = 'NEEDS_REVIEW' AND persistence_status = 'PENDING'
           AND NOT jsonb_exists(normalized_data, 'printing_profile_id')
           AND NOT jsonb_exists(normalized_data, 'edition_context_profile_id');
        IF v_n <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s NEEDS_REVIEW sem as duas chaves em job operacional: %s row(s) (esperado 2)', c_env, v_case, v_n);
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
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END
$h2830_e09$;
