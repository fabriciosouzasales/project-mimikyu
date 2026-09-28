-- ============================================================================
-- 2830H · ENVELOPE E12 — SEÇÃO B (BACKFILL SEMÂNTICO, V1–V14) · lote L10, 14 casos
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E12P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 Seção B; fonte lógica 2832 v3.1 (arquivo NÃO alterado).
-- Desvios v7.0 .. V1 existência = asserção; V10 invertido (guard estrito); V12
--                 asserção; V13/V14 universo medido. Sem CREATE TEMP; sem NOTICE.
-- P13 ........... cada predicado roda sobre rows REAIS e sobre 1 row de CONTROLE em
--                 memória (VALUES) com o MESMO texto: real = 0 e controle = 1.
-- Desempenho .... 2211 só no universo op ∪ (NOT op ∧ observado ≠ ABSENT) — prova de
--                 equivalência no cabeçalho do gerador; plano em P9A (EXPLAIN).
-- Escrita ....... NENHUMA (nem fixture). Término em exceção por uniformidade (P2).
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e12$
DECLARE
    c_env      CONSTANT text   := 'E12_SECAO_B_BACKFILL_SEMANTICO';
    c_expected CONSTANT text[] := ARRAY['V1','V2','V3','V4','V5','V6','V7','V8','V9','V10','V11','V12','V13','V14'];
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
    v_agg      jsonb;
    v_occ      bigint;
    v_u8       bigint;
    v_a1       bigint;
    v_a2       bigint;
    v_a3       bigint;
    v_a4       bigint;
    v_a5       bigint;
    v_a6       bigint;
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
    -- RECOMPUTO ÚNICO (VREC) — subtransação própria; erro = H2830_FAIL
    -- ------------------------------------------------------------------ --
    v_case := 'VREC';
    BEGIN
        WITH base AS (
            SELECT r.id, j.status AS job_status,
                   (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND r.persistence_status = 'PENDING') AS op,
                   r.validation_status AS val, r.persistence_status AS per, r.decision_status AS dec,
                   CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                        WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                        ELSE 'UUID' END AS obs,
                   r.normalized_data ->> 'edition_context_profile_id' AS obs_uuid,
                   r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.raw_data, c.card_set_id
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card c ON c.id = r.card_id
        ),
        rc AS (
            SELECT b.id,
                   CASE ax.edition_context_state
                        WHEN 'RESOLVED_WITH_EC_PROFILE'    THEN 'UUID'
                        WHEN 'RESOLVED_NO_EDITION_CONTEXT' THEN 'NULL'
                        ELSE 'ABSENT' END AS exp,
                   ax.edition_context_profile_id::text AS exp_uuid
              FROM base b
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(b.card_set_id, v_src) sc ON true
             CROSS JOIN LATERAL internal.resolve_variant_row_axes(b.raw_data, v_game, v_src, sc.external_set_id) ax
             WHERE b.op OR b.obs <> 'ABSENT'
        ),
        ctrl(src, job_status, per, val, dec, obs, obs_uuid, exp, exp_uuid, res, mat) AS (
            VALUES ('CTRL_v1_div', 'STAGED', 'PENDING', 'VALID', 'APPROVED', 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, 'UUID', '00000000-0000-4000-8000-0000000000c2'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v2', 'STAGED', 'PENDING', 'VALID', 'PENDING', 'NULL', NULL::text, 'ABSENT', NULL::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v3', 'STAGED', 'PENDING', 'NEEDS_REVIEW', 'PENDING', 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, 'ABSENT', NULL::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v4', 'STAGED', 'PENDING', 'VALID', 'PENDING', 'ABSENT', NULL::text, 'ABSENT', NULL::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v6', 'CONFIRMING', 'PENDING', 'VALID', 'APPROVED', 'NULL', NULL::text, 'UUID', '00000000-0000-4000-8000-0000000000c2'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v7a', 'COMPLETED', 'INSERTED', 'VALID', 'APPROVED', 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v7b', 'COMPLETED', 'UNCHANGED', 'VALID', 'APPROVED', 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v7c', 'STAGED', 'PENDING', 'VALID', 'APPROVED', 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, '00000000-0000-4000-8000-0000000000c2'::uuid, NULL::uuid),
                   ('CTRL_v9', 'RECEIVED', 'PENDING', 'NEEDS_REVIEW', 'PENDING', 'ABSENT', NULL::text, 'NULL', NULL::text, NULL::uuid, NULL::uuid),
                   ('CTRL_v13', 'COMPLETED', 'INSERTED', 'VALID', 'APPROVED', 'NULL', NULL::text, 'ABSENT', NULL::text, '00000000-0000-4000-8000-0000000000c2'::uuid, NULL::uuid),
                   ('CTRL_v14c', 'CANCELLED', 'PENDING', 'VALID', 'PENDING', 'UUID', '00000000-0000-4000-8000-0000000000c1'::text, 'ABSENT', NULL::text, NULL::uuid, NULL::uuid)
        ),
        x AS (
            SELECT 'REAL'::text AS src, b.job_status, b.op, b.val, b.per, b.dec, b.obs, b.obs_uuid,
                   r.exp, r.exp_uuid, b.res, b.mat, (r.id IS NOT NULL) AS rechecked
              FROM base b LEFT JOIN rc r ON r.id = b.id
            UNION ALL
            SELECT c.src, c.job_status, (c.job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND c.per = 'PENDING'), c.val, c.per, c.dec, c.obs, c.obs_uuid,
                   c.exp, c.exp_uuid, c.res, c.mat, true
              FROM ctrl c
        )
        SELECT jsonb_build_object(
            'v1_div', count(*) FILTER (WHERE src = 'REAL' AND (op AND exp = 'UUID' AND obs_uuid IS DISTINCT FROM exp_uuid)),
            'v1_div_ctrl', count(*) FILTER (WHERE src = 'CTRL_v1_div' AND (op AND exp = 'UUID' AND obs_uuid IS DISTINCT FROM exp_uuid)),
            'v2', count(*) FILTER (WHERE src = 'REAL' AND (op AND obs = 'NULL' AND exp <> 'NULL')),
            'v2_ctrl', count(*) FILTER (WHERE src = 'CTRL_v2' AND (op AND obs = 'NULL' AND exp <> 'NULL')),
            'v3', count(*) FILTER (WHERE src = 'REAL' AND (op AND exp = 'ABSENT' AND obs <> 'ABSENT')),
            'v3_ctrl', count(*) FILTER (WHERE src = 'CTRL_v3' AND (op AND exp = 'ABSENT' AND obs <> 'ABSENT')),
            'v4', count(*) FILTER (WHERE src = 'REAL' AND (op AND val = 'VALID' AND obs = 'ABSENT')),
            'v4_ctrl', count(*) FILTER (WHERE src = 'CTRL_v4' AND (op AND val = 'VALID' AND obs = 'ABSENT')),
            'v6', count(*) FILTER (WHERE src = 'REAL' AND (op AND obs <> exp)),
            'v6_ctrl', count(*) FILTER (WHERE src = 'CTRL_v6' AND (op AND obs <> exp)),
            'v7a', count(*) FILTER (WHERE src = 'REAL' AND (per = 'INSERTED' AND res IS NULL)),
            'v7a_ctrl', count(*) FILTER (WHERE src = 'CTRL_v7a' AND (per = 'INSERTED' AND res IS NULL)),
            'v7b', count(*) FILTER (WHERE src = 'REAL' AND (per = 'UNCHANGED' AND dec <> 'SKIPPED' AND res IS NULL AND mat IS NULL)),
            'v7b_ctrl', count(*) FILTER (WHERE src = 'CTRL_v7b' AND (per = 'UNCHANGED' AND dec <> 'SKIPPED' AND res IS NULL AND mat IS NULL)),
            'v7c', count(*) FILTER (WHERE src = 'REAL' AND (per = 'PENDING' AND res IS NOT NULL)),
            'v7c_ctrl', count(*) FILTER (WHERE src = 'CTRL_v7c' AND (per = 'PENDING' AND res IS NOT NULL)),
            'v9', count(*) FILTER (WHERE src = 'REAL' AND (op AND obs = 'ABSENT' AND exp IN ('UUID','NULL'))),
            'v9_ctrl', count(*) FILTER (WHERE src = 'CTRL_v9' AND (op AND obs = 'ABSENT' AND exp IN ('UUID','NULL'))),
            'v13', count(*) FILTER (WHERE src = 'REAL' AND (NOT op AND obs = 'NULL' AND exp = 'ABSENT')),
            'v13_ctrl', count(*) FILTER (WHERE src = 'CTRL_v13' AND (NOT op AND obs = 'NULL' AND exp = 'ABSENT')),
            'v14c', count(*) FILTER (WHERE src = 'REAL' AND (job_status = 'CANCELLED' AND obs <> 'ABSENT' AND exp = 'ABSENT')),
            'v14c_ctrl', count(*) FILTER (WHERE src = 'CTRL_v14c' AND (job_status = 'CANCELLED' AND obs <> 'ABSENT' AND exp = 'ABSENT')),
            'u_total', count(*) FILTER (WHERE src = 'REAL' AND (true)),
            'u_op', count(*) FILTER (WHERE src = 'REAL' AND (op)),
            'u_rechecked', count(*) FILTER (WHERE src = 'REAL' AND (rechecked)),
            'u_v1_occ', count(*) FILTER (WHERE src = 'REAL' AND (rechecked AND exp = 'UUID')),
            'u_v5', count(*) FILTER (WHERE src = 'REAL' AND (NOT op AND val = 'VALID' AND obs = 'ABSENT')),
            'u_hist_null', count(*) FILTER (WHERE src = 'REAL' AND (NOT op AND obs = 'NULL')),
            'u_cancel_vp', count(*) FILTER (WHERE src = 'REAL' AND (job_status = 'CANCELLED' AND val = 'VALID' AND per = 'PENDING')),
            'u_v14b', count(*) FILTER (WHERE src = 'REAL' AND (job_status = 'CANCELLED' AND op)),
            'u_v7_skip', count(*) FILTER (WHERE src = 'REAL' AND (per = 'UNCHANGED' AND dec = 'SKIPPED' AND res IS NULL AND mat IS NULL)),
            'u_op_missing', count(*) FILTER (WHERE src = 'REAL' AND (op AND NOT rechecked)),
            'u_exp_null', count(*) FILTER (WHERE src = 'REAL' AND (rechecked AND exp IS NULL)),
            'rc_rows', (SELECT count(*) FROM rc),
            'rc_ids', (SELECT count(DISTINCT id) FROM rc))
          FROM x
          INTO STRICT v_agg;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=VREC recomputo falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;
    IF (v_agg->>'rc_rows')::bigint IS DISTINCT FROM (v_agg->>'rc_ids')::bigint
       OR (v_agg->>'u_op_missing')::bigint <> 0 OR (v_agg->>'u_exp_null')::bigint <> 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=VREC recomputo não é 1:1 rc_rows=%s rc_ids=%s op_sem_recheck=%s exp_nulo=%s',
            c_env, v_agg->>'rc_rows', v_agg->>'rc_ids', v_agg->>'u_op_missing', v_agg->>'u_exp_null');
    END IF;

    -- ================================================================== --
    -- V1 [AUTO EX] UUID gravado = UUID do routing (op); >=1 ocorrência é ASSERÇÃO
    -- ================================================================== --
    v_case := 'V1';
    BEGIN
        IF (v_agg->>'v1_div')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v1_div: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v1_div')::bigint);
        END IF;
        IF (v_agg->>'v1_div_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v1_div: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v1_div_ctrl')::bigint);
        END IF;
        v_occ := (v_agg->>'u_v1_occ')::bigint;
        IF v_occ = 0 THEN
            SELECT count(*) INTO v_occ
              FROM (SELECT 1
                      FROM public.catalog_variant_import_row r
                      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
                      JOIN public.card c ON c.id = r.card_id
                      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, v_src) sc ON true
                     CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, v_game, v_src, sc.external_set_id) ax
                     WHERE NOT (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND r.persistence_status = 'PENDING')
                       AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
                       AND ax.edition_context_state = 'RESOLVED_WITH_EC_PROFILE'
                     LIMIT 1) z;
        END IF;
        IF v_occ = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V1_NO_OCCURRENCE: nenhuma row da staging resolve para profile (tabela inteira)', c_env, v_case);
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
    -- V2 [AUTO EX] JSON null só onde o routing confirma RESOLVED_NO_EDITION_CONTEXT
    -- ================================================================== --
    v_case := 'V2';
    BEGIN
        IF (v_agg->>'v2')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v2: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v2')::bigint);
        END IF;
        IF (v_agg->>'v2_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v2: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v2_ctrl')::bigint);
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
    -- V3 [AUTO EX] eixo EC não-terminal não recebeu chave
    -- ================================================================== --
    v_case := 'V3';
    BEGIN
        IF (v_agg->>'v3')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v3: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v3')::bigint);
        END IF;
        IF (v_agg->>'v3_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v3: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v3_ctrl')::bigint);
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
    -- V4 [AUTO EX] zero row operacional VALID+PENDING sem chave
    -- ================================================================== --
    v_case := 'V4';
    BEGIN
        IF (v_agg->>'v4')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v4: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v4')::bigint);
        END IF;
        IF (v_agg->>'v4_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v4: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v4_ctrl')::bigint);
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
    -- V5 [AUTO EX] >= 1 row histórica VALID legitimamente sem chave
    -- ================================================================== --
    v_case := 'V5';
    BEGIN
        IF (v_agg->>'u_v5')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V5: nenhuma row HISTÓRICA VALID sem chave (escopo vazou ou HOLD recebeu null)', c_env, v_case);
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
    -- V6 [AUTO EX] destino observado = recomputado, row a row (op)
    -- ================================================================== --
    v_case := 'V6';
    BEGIN
        IF (v_agg->>'v6')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v6: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v6')::bigint);
        END IF;
        IF (v_agg->>'v6_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v6: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v6_ctrl')::bigint);
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
    -- V7 [AUTO EX] estados e lineage por classe (INSERTED / UNCHANGED não-SKIPPED / PENDING)
    -- ================================================================== --
    v_case := 'V7';
    BEGIN
        IF (v_agg->>'v7a')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v7a: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v7a')::bigint);
        END IF;
        IF (v_agg->>'v7a_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v7a: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v7a_ctrl')::bigint);
        END IF;
        IF (v_agg->>'v7b')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v7b: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v7b')::bigint);
        END IF;
        IF (v_agg->>'v7b_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v7b: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v7b_ctrl')::bigint);
        END IF;
        IF (v_agg->>'v7c')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v7c: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v7c')::bigint);
        END IF;
        IF (v_agg->>'v7c_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v7c: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v7c_ctrl')::bigint);
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
    -- V8 [AUTO EX] lineage 1:N sem destinos divergentes para o mesmo raw_data
    -- ================================================================== --
    v_case := 'V8';
    BEGIN
        WITH l AS (
            SELECT 'REAL'::text AS src, r.resulting_variant_id AS res, r.raw_data,
                   CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                        WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                        ELSE 'UUID' END AS obs
              FROM public.catalog_variant_import_row r
             WHERE r.resulting_variant_id IS NOT NULL
            UNION ALL
            SELECT 'CTRL', '00000000-0000-4000-8000-0000000000c1'::uuid, '{}'::jsonb, 'UUID'
            UNION ALL
            SELECT 'CTRL', '00000000-0000-4000-8000-0000000000c1'::uuid, '{}'::jsonb, 'NULL'
        ), d AS (
            SELECT src, res FROM l GROUP BY src, res
            HAVING count(DISTINCT obs) > 1 AND count(DISTINCT raw_data) = 1
        )
        SELECT count(*) FILTER (WHERE src = 'REAL'), count(*) FILTER (WHERE src = 'CTRL'),
               (SELECT count(DISTINCT res) FROM l WHERE src = 'REAL')
          INTO v_n, v_m, v_u8
          FROM d;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V8: %s Variant(s) com rows de mesmo raw_data e destinos diferentes', c_env, v_case, v_n);
        END IF;
        IF v_m <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V8: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, v_m);
        END IF;
        IF v_u8 = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V8: universo de lineage vazio (nenhuma Variant com row)', c_env, v_case);
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
    -- V9 [AUTO EX] write-set operacional de uma reavaliação = 0 (sem escrita)
    -- ================================================================== --
    v_case := 'V9';
    BEGIN
        IF (v_agg->>'v9')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v9: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v9')::bigint);
        END IF;
        IF (v_agg->>'v9_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v9: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v9_ctrl')::bigint);
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
    -- V10 [AUTO RO] guard ESTRITO presente (trigger, tgfoid, tokens; obsoleto ausente)
    -- ================================================================== --
    v_case := 'V10';
    BEGIN
        SELECT count(*) INTO v_n
          FROM pg_trigger t
         WHERE t.tgrelid = to_regclass('public.catalog_variant_import_row')
           AND t.tgname = 'trg_cvir_normalized_shape' AND NOT t.tgisinternal AND t.tgenabled = 'O'
           AND t.tgfoid = to_regprocedure('internal.guard_cvir_normalized_shape()');
        SELECT p.prosrc INTO v_txt FROM pg_proc p WHERE p.oid = to_regprocedure('internal.guard_cvir_normalized_shape()');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V10: trg_cvir_normalized_shape ausente, desabilitado ou com tgfoid divergente (%s)', c_env, v_case, v_n);
        END IF;
        IF v_txt IS NULL OR strpos(v_txt, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY') = 0
           OR strpos(v_txt, 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN') = 0
           OR strpos(v_txt, 'CVIR_PENDING_VALID_REQUIRES_EDITION_CONTEXT_KEY') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V10: guard não é o ESTRITO da 2214 v3.1 (tokens exigidos ausentes ou token obsoleto presente)', c_env, v_case);
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
    -- V11 [AUTO EX] tri-estado não degradado; identidades de staging únicas
    -- ================================================================== --
    v_case := 'V11';
    BEGIN
        WITH ids AS (
            SELECT 'REAL'::text AS src, r.job_id, r.card_id, (r.normalized_data ->> 'variant_type_id') AS vt,
                   internal.axis_identity_token(r.normalized_data, 'printing_profile_id') AS tp,
                   internal.axis_identity_token(r.normalized_data, 'edition_context_profile_id') AS te
              FROM public.catalog_variant_import_row r
             WHERE (r.normalized_data ->> 'variant_type_id') IS NOT NULL
            UNION ALL
            SELECT 'CTRL', '00000000-0000-4000-8000-0000000000c1'::uuid, '00000000-0000-4000-8000-0000000000c2'::uuid, 'vt',
                   internal.axis_identity_token(jsonb_build_object('printing_profile_id', NULL), 'printing_profile_id'),
                   internal.axis_identity_token('{}'::jsonb, 'edition_context_profile_id')
              FROM generate_series(1, 2)
        ), d AS (
            SELECT src FROM ids GROUP BY src, job_id, card_id, vt, tp, te HAVING count(*) > 1
        )
        SELECT count(*) FILTER (WHERE src = 'REAL'), count(*) FILTER (WHERE src = 'CTRL') INTO v_n, v_m FROM d;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V11: %s identidade(s) de staging duplicada(s)', c_env, v_case, v_n);
        END IF;
        IF v_m <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V11: controle negativo NÃO detectado (%s, esperado 1)', c_env, v_case, v_m);
        END IF;
        IF internal.axis_identity_token('{}'::jsonb, 'k') IS DISTINCT FROM 'A'
           OR internal.axis_identity_token('{"k":null}'::jsonb, 'k') IS DISTINCT FROM 'N'
           OR internal.axis_identity_token('{"k":"11111111-1111-4111-8111-111111111111"}'::jsonb, 'k')
              IS DISTINCT FROM 'U:11111111-1111-4111-8111-111111111111' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V11: tri-estado A/N/U degradado', c_env, v_case);
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
    -- V12 [AUTO RO] partição fechada + zero UUID órfão (>= 1 UUID)
    -- ================================================================== --
    v_case := 'V12';
    BEGIN
        WITH o AS (
            SELECT j.status AS job_status, r.validation_status AS val, r.persistence_status AS per,
                   jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') AS ty,
                   jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
                   r.normalized_data ->> 'edition_context_profile_id' AS uuid_txt
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
        ), cells AS (
            SELECT CASE WHEN NOT has_key THEN 'ABSENT' WHEN ty = 'null' THEN 'NULL' ELSE 'UUID' END AS obs,
                   val, per, job_status, count(*) AS n
              FROM o GROUP BY 1, 2, 3, 4
        ), orf AS (
            SELECT 'REAL'::text AS src, uuid_txt FROM o WHERE ty = 'string'
            UNION ALL
            SELECT 'CTRL', gen_random_uuid()::text
        )
        SELECT (SELECT count(*) FROM o),
               (SELECT count(*) FROM o WHERE NOT has_key),
               (SELECT count(*) FROM o WHERE ty = 'null'),
               (SELECT count(*) FROM o WHERE ty = 'string'),
               (SELECT COALESCE(sum(n), 0) FROM cells),
               (SELECT count(*) FROM orf f WHERE f.src = 'REAL'
                   AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.id::text = lower(f.uuid_txt))),
               (SELECT count(*) FROM orf f WHERE f.src = 'CTRL'
                   AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.id::text = lower(f.uuid_txt)))
          INTO v_n, v_a1, v_a2, v_a3, v_a4, v_a5, v_a6;
        IF v_a1 + v_a2 + v_a3 <> v_n OR v_a4 <> v_n THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V12(i): partição não fecha total=%s ausente=%s null=%s string=%s soma_células=%s', c_env, v_case, v_n, v_a1, v_a2, v_a3, v_a4);
        END IF;
        IF v_a3 = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V12(ii): nenhum UUID gravado (universo vazio)', c_env, v_case);
        END IF;
        IF v_a5 <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V12(ii): %s UUID(s) órfão(s)', c_env, v_case, v_a5);
        END IF;
        IF v_a6 <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V12(ii): controle de órfão NÃO detectado (%s, esperado 1)', c_env, v_case, v_a6);
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
    -- V13 [AUTO EX] histórico intocado: nenhum JSON null histórico onde o routing diz indeterminado
    -- ================================================================== --
    v_case := 'V13';
    BEGIN
        IF (v_agg->>'v13')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v13: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v13')::bigint);
        END IF;
        IF (v_agg->>'v13_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v13: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v13_ctrl')::bigint);
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
    -- V14 [AUTO EX] CANCELLED terminal: universo > 0, nunca operacional, nenhuma indeterminada com chave
    -- ================================================================== --
    v_case := 'V14';
    BEGIN
        IF (v_agg->>'u_cancel_vp')::bigint = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V14: universo CANCELLED VALID+PENDING vazio (P13)', c_env, v_case);
        END IF;
        IF (v_agg->>'u_v14b')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s V14: %s row(s) de job CANCELLED classificadas como operacionais', c_env, v_case, (v_agg->>'u_v14b')::bigint);
        END IF;
        IF (v_agg->>'v14c')::bigint <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v14c: %s row(s) REAIS violam o predicado', c_env, v_case, (v_agg->>'v14c')::bigint);
        END IF;
        IF (v_agg->>'v14c_ctrl')::bigint <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v14c: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', c_env, v_case, (v_agg->>'v14c_ctrl')::bigint);
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
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s u_total=%s u_op=%s u_rechecked=%s u_v1_occ=%s v1_occ_total=%s u_v5=%s u_hist_null=%s u_cancel_vp=%s v7_skip=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), v_agg->>'u_total', v_agg->>'u_op', v_agg->>'u_rechecked', v_agg->>'u_v1_occ', v_occ, v_agg->>'u_v5', v_agg->>'u_hist_null', v_agg->>'u_cancel_vp', v_agg->>'u_v7_skip');
END
$h2830_e12$;
