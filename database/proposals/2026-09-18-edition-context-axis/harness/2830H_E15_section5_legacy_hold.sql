-- ============================================================================
-- 2830H · ENVELOPE E15 — SEÇÃO 5 (LEGADO / HOLD / EXCLUSÃO) · lote L13, 5 casos: 5.1 5.2 5.3 5.6 5.7
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL. BLOQUEADO pela pendência 5.3/5.7: READY_DEF = C3
--                 adjudicado (B5X-C3-ADJUDICATION-RECORD.md), mas o PREFLIGHT levanta
--                 H2830_FAIL enquanto E15_BLOCKED_53_57 = True no gerador.
-- Contrato ...... 2830 v7.0 Seção 5; derivação 2831 v2.0 PASSO 0/0B/1 (arquivo
--                 NÃO alterado), sem TEMP, bloco DERIV-5X idêntico ao E15P.
-- Escrita ....... NENHUMA. Término em exceção por uniformidade (P2).
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- Pendência ..... OBRIGATÓRIA para a readiness final do E15 (STOP-7): 5.3
--                 (plano ∩ HOLD) e 5.7 (plano ∩ PRICING_CONDITIONED) são
--                 tautológicas por construção do plano (plano = estrutural ∖
--                 PRICING; C3 exclui HOLD por definição). Reescrever antes do LIVE.
-- ============================================================================
DO $h2830_e15$
DECLARE
    c_env      CONSTANT text   := 'E15_SECAO_5_LEGADO_HOLD';
    c_expected CONSTANT text[] := ARRAY['5.1','5.2','5.3','5.6','5.7'];
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
    -- B-5X: sem READY_DEF adjudicado, ou com 5.3/5.7 ainda tautológicas,
    -- nenhum caso roda (fail-closed)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
        'H2830_FAIL: envelope=%s caso=PREFLIGHT B-5X: READY_DEF=%s adjudicado, mas 5.3/5.7 tautológicas por construção (pendência obrigatória); E15 bloqueado', c_env, 'c3');

    -- ------------------------------------------------------------------ --
    -- DERIV-5X (bloco idêntico ao E15P) — subtransação própria
    -- ------------------------------------------------------------------ --
    v_case := 'DERIV-5X';
    BEGIN
        WITH d5_hold AS (
            SELECT cv.id
              FROM public.card_variant cv
              JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
              JOIN public.card c  ON c.id  = cv.card_id
              JOIN public.card_set cs ON cs.id = c.card_set_id
             WHERE vt.code = 'PROMO_STAMPED'
                OR (vt.code LIKE 'SET_LOGO%'
                    AND cs.code !~ '^EX(7|8|9|10|11|12|13|14|15|16)$'
                    AND cs.code NOT IN ('DP1','SWSH9','SVP'))
        ),
        d5_pscid AS (
            SELECT cv.id FROM public.card_variant cv
             WHERE EXISTS (SELECT 1 FROM public.pricing_source_card_identity x WHERE x.card_variant_type_id = cv.variant_type_id)
        ),
        d5_psvm AS (
            SELECT cv.id FROM public.card_variant cv
             WHERE EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping x WHERE x.variant_type_id = cv.variant_type_id)
        ),
        d5_pricing AS (
            SELECT id FROM d5_pscid UNION SELECT id FROM d5_psvm
        ),
        d5_map(code, n) AS (
            VALUES ('SATANDARD_REWARDS', 51),
                   ('STAFF_HOLO', 40),
                   ('SET_LOGO_REVERSE', 40),
                   ('REWARDS_HOLO', 30),
                   ('POKEMON_CENTER_HOLO', 19),
                   ('COSMOS_REWARDS_HOLO', 18),
                   ('COSMOS_REWARDS_REVERSE', 17),
                   ('COSMOS_PROFESSOR_REVERSE', 16),
                   ('STANDARDS_TEACHER_PROGRAM', 14),
                   ('STANDARD_GYM_CHALLENGE', 9),
                   ('GAMESTOP_HOLO', 9),
                   ('STANDARD_REGIONAL_CHAMPIONSHIPS', 8),
                   ('EBGAMES_HOLO', 8),
                   ('STANDARD_PIKACHU_WORLD_2000', 6),
                   ('W_PROMO_STAMPED', 6),
                   ('SET_LOGO_STANDARDS', 4),
                   ('STANDARD_FIRST_MOVIE', 4),
                   ('STANDARD_FIRST_MOVIE_INVERTED', 4),
                   ('STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF', 4),
                   ('STANDARDS_LEAGUE', 4),
                   ('STANDARD_WORLDS_2024', 3),
                   ('STANDARDS_HORIZONS', 3),
                   ('GYM_CHALLENGE_HOLO', 3)
        ),
        d5_finish(code) AS (
            VALUES ('STANDARD'),
                   ('HOLO'),
                   ('COSMOS_HOLO'),
                   ('REVERSE_HOLO'),
                   ('ENERGY_REVERSE'),
                   ('POKE_BALL_REVERSE'),
                   ('LOVE_BALL_REVERSE'),
                   ('FRIEND_BALL_REVERSE'),
                   ('QUICK_BALL_REVERSE'),
                   ('DUSK_BALL_REVERSE'),
                   ('ROCKET_REVERSE'),
                   ('MASTER_BALL_REVERSE'),
                   ('GOLD_HOLO'),
                   ('TINSEL_HOLO'),
                   ('TINSEL_REVERSE'),
                   ('CRACKED_ICE_HOLO'),
                   ('GALAXY_HOLO'),
                   ('RAINBOW_HOLO'),
                   ('METAL'),
                   ('METAL_GOLD'),
                   ('LENTICULAR'),
                   ('COSMOS_REVERSE'),
                   ('MASTER_BALL_PATTERN'),
                   ('POKE_BALL_PATTERN'),
                   ('MASTER_BALL_HOLO'),
                   ('SNOWFLAKE_COSMOS_HOLO'),
                   ('STANDARDS_SNOWFLAKE'),
                   ('SHOWFLAKE_HOLO')
        ),
        d5_c0 AS (
            SELECT cv.id, cv.variant_type_id, c.card_set_id
              FROM public.card_variant cv
              JOIN public.card c ON c.id = cv.card_id
             WHERE cv.printing_profile_id IS NULL
               AND EXISTS (SELECT 1 FROM public.catalog_variant_import_row r WHERE r.resulting_variant_id = cv.id)
        ),
        d5_ev AS (
            SELECT DISTINCT ON (cv.id) cv.id, cv.variant_type_id, c.card_set_id, r.raw_data
              FROM public.card_variant cv
              JOIN public.card c ON c.id = cv.card_id
              JOIN public.catalog_variant_import_row r ON r.resulting_variant_id = cv.id
             WHERE cv.id NOT IN (SELECT id FROM d5_hold)
             ORDER BY cv.id, r.created_at ASC, r.id ASC
        ),
        d5_c1 AS (
            SELECT e.id, e.variant_type_id, e.card_set_id FROM d5_ev e
        ),
        d5_c2 AS (
            SELECT e.id, e.variant_type_id, e.card_set_id
              FROM d5_ev e
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(e.card_set_id, (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')) sc ON true
             CROSS JOIN LATERAL internal.resolve_variant_row_axes(e.raw_data, (SELECT id FROM public.game WHERE code = 'POKEMON'), (SELECT id FROM public.asset_source WHERE code = 'TCGDEX'), sc.external_set_id) ax
             WHERE (jsonb_exists(e.raw_data, 'subtype') OR jsonb_exists(e.raw_data, 'stamp'))
               AND ax.edition_context_state = 'RESOLVED_WITH_EC_PROFILE'
        ),
        d5_c3 AS (
            SELECT cv.id, cv.variant_type_id, c.card_set_id
              FROM public.card_variant cv
              JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
              JOIN public.card c  ON c.id  = cv.card_id
              JOIN public.card_set cs ON cs.id = c.card_set_id
             WHERE vt.code NOT IN (SELECT code FROM d5_finish)
               AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$')
               AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code NOT IN ('DP1','SWSH9','SVP'))
               AND vt.code <> 'PROMO_STAMPED'
        ),
        d5_c0_bt AS (
            SELECT vt.code, count(*) AS n FROM d5_c0 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code
        ),
        d5_c1_bt AS (
            SELECT vt.code, count(*) AS n FROM d5_c1 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code
        ),
        d5_c2_bt AS (
            SELECT vt.code, count(*) AS n FROM d5_c2 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code
        ),
        d5_c3_bt AS (
            SELECT vt.code, count(*) AS n FROM d5_c3 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code
        ),
        d5_m AS (
            SELECT (SELECT count(*) FROM d5_hold) AS hold,
                   (SELECT count(*) FROM (SELECT vt.code FROM public.card_variant_type vt GROUP BY vt.code HAVING count(*) > 1) z) AS type_code_dup,
                   (SELECT count(*) FROM d5_ev) AS lineage_not_hold,
                   (SELECT count(*) FROM d5_c0) AS c0_structural,
                   (SELECT count(*) FROM d5_c0 s WHERE s.id NOT IN (SELECT id FROM d5_pricing)) AS c0_unconditioned,
                   (SELECT count(*) FROM d5_c0 s WHERE s.id IN (SELECT id FROM d5_pricing)) AS c0_conditioned,
                   (SELECT count(*) FROM d5_c0 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_hold)) AS c0_plan_x_hold,
                   (SELECT count(*) FROM d5_c0 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_pricing)) AS c0_plan_x_pricing,
                   (SELECT count(*) FROM d5_c0 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'STAFF_HOLO') AS c0_cond_staff_holo,
                   (SELECT count(*) FROM d5_c0 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'SET_LOGO_REVERSE') AS c0_cond_set_logo_reverse,
                   (SELECT count(*) FROM d5_c0 s WHERE s.id IN (SELECT id FROM d5_pscid)) AS c0_cond_by_pscid,
                   (SELECT count(*) FROM d5_c0 s WHERE s.id IN (SELECT id FROM d5_psvm)) AS c0_cond_by_psvm,
                   (SELECT count(*) FROM d5_c0_bt) AS c0_fp_n_types,
                   (SELECT count(*) FROM d5_map m LEFT JOIN d5_c0_bt b ON b.code = m.code WHERE COALESCE(b.n, 0) <> m.n) AS c0_fp_named_bad,
                   (SELECT count(*) FROM d5_c0_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c0_fp_worlds_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c0_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c0_fp_worlds_n,
                   (SELECT count(*) FROM d5_c0_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c0_fp_single_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c0_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c0_fp_single_n,
                   (SELECT count(*) FROM d5_c0_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)' AND b.n <> 1) AS c0_fp_single_non1,
                   (SELECT count(*) FROM d5_c0 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'SVP') AS c0_fp_slr_svp,
                   (SELECT count(*) FROM d5_c0 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'DP1') AS c0_fp_slr_dp1,
                   (SELECT count(*) FROM d5_c0 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_STANDARDS' AND cs.code = 'DP1') AS c0_fp_sls_dp1,
                   (SELECT count(*) FROM d5_c1) AS c1_structural,
                   (SELECT count(*) FROM d5_c1 s WHERE s.id NOT IN (SELECT id FROM d5_pricing)) AS c1_unconditioned,
                   (SELECT count(*) FROM d5_c1 s WHERE s.id IN (SELECT id FROM d5_pricing)) AS c1_conditioned,
                   (SELECT count(*) FROM d5_c1 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_hold)) AS c1_plan_x_hold,
                   (SELECT count(*) FROM d5_c1 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_pricing)) AS c1_plan_x_pricing,
                   (SELECT count(*) FROM d5_c1 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'STAFF_HOLO') AS c1_cond_staff_holo,
                   (SELECT count(*) FROM d5_c1 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'SET_LOGO_REVERSE') AS c1_cond_set_logo_reverse,
                   (SELECT count(*) FROM d5_c1 s WHERE s.id IN (SELECT id FROM d5_pscid)) AS c1_cond_by_pscid,
                   (SELECT count(*) FROM d5_c1 s WHERE s.id IN (SELECT id FROM d5_psvm)) AS c1_cond_by_psvm,
                   (SELECT count(*) FROM d5_c1_bt) AS c1_fp_n_types,
                   (SELECT count(*) FROM d5_map m LEFT JOIN d5_c1_bt b ON b.code = m.code WHERE COALESCE(b.n, 0) <> m.n) AS c1_fp_named_bad,
                   (SELECT count(*) FROM d5_c1_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c1_fp_worlds_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c1_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c1_fp_worlds_n,
                   (SELECT count(*) FROM d5_c1_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c1_fp_single_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c1_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c1_fp_single_n,
                   (SELECT count(*) FROM d5_c1_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)' AND b.n <> 1) AS c1_fp_single_non1,
                   (SELECT count(*) FROM d5_c1 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'SVP') AS c1_fp_slr_svp,
                   (SELECT count(*) FROM d5_c1 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'DP1') AS c1_fp_slr_dp1,
                   (SELECT count(*) FROM d5_c1 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_STANDARDS' AND cs.code = 'DP1') AS c1_fp_sls_dp1,
                   (SELECT count(*) FROM d5_c2) AS c2_structural,
                   (SELECT count(*) FROM d5_c2 s WHERE s.id NOT IN (SELECT id FROM d5_pricing)) AS c2_unconditioned,
                   (SELECT count(*) FROM d5_c2 s WHERE s.id IN (SELECT id FROM d5_pricing)) AS c2_conditioned,
                   (SELECT count(*) FROM d5_c2 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_hold)) AS c2_plan_x_hold,
                   (SELECT count(*) FROM d5_c2 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_pricing)) AS c2_plan_x_pricing,
                   (SELECT count(*) FROM d5_c2 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'STAFF_HOLO') AS c2_cond_staff_holo,
                   (SELECT count(*) FROM d5_c2 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'SET_LOGO_REVERSE') AS c2_cond_set_logo_reverse,
                   (SELECT count(*) FROM d5_c2 s WHERE s.id IN (SELECT id FROM d5_pscid)) AS c2_cond_by_pscid,
                   (SELECT count(*) FROM d5_c2 s WHERE s.id IN (SELECT id FROM d5_psvm)) AS c2_cond_by_psvm,
                   (SELECT count(*) FROM d5_c2_bt) AS c2_fp_n_types,
                   (SELECT count(*) FROM d5_map m LEFT JOIN d5_c2_bt b ON b.code = m.code WHERE COALESCE(b.n, 0) <> m.n) AS c2_fp_named_bad,
                   (SELECT count(*) FROM d5_c2_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c2_fp_worlds_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c2_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c2_fp_worlds_n,
                   (SELECT count(*) FROM d5_c2_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c2_fp_single_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c2_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c2_fp_single_n,
                   (SELECT count(*) FROM d5_c2_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)' AND b.n <> 1) AS c2_fp_single_non1,
                   (SELECT count(*) FROM d5_c2 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'SVP') AS c2_fp_slr_svp,
                   (SELECT count(*) FROM d5_c2 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'DP1') AS c2_fp_slr_dp1,
                   (SELECT count(*) FROM d5_c2 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_STANDARDS' AND cs.code = 'DP1') AS c2_fp_sls_dp1,
                   (SELECT count(*) FROM d5_c3) AS c3_structural,
                   (SELECT count(*) FROM d5_c3 s WHERE s.id NOT IN (SELECT id FROM d5_pricing)) AS c3_unconditioned,
                   (SELECT count(*) FROM d5_c3 s WHERE s.id IN (SELECT id FROM d5_pricing)) AS c3_conditioned,
                   (SELECT count(*) FROM d5_c3 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_hold)) AS c3_plan_x_hold,
                   (SELECT count(*) FROM d5_c3 s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_pricing)) AS c3_plan_x_pricing,
                   (SELECT count(*) FROM d5_c3 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'STAFF_HOLO') AS c3_cond_staff_holo,
                   (SELECT count(*) FROM d5_c3 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                     WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'SET_LOGO_REVERSE') AS c3_cond_set_logo_reverse,
                   (SELECT count(*) FROM d5_c3 s WHERE s.id IN (SELECT id FROM d5_pscid)) AS c3_cond_by_pscid,
                   (SELECT count(*) FROM d5_c3 s WHERE s.id IN (SELECT id FROM d5_psvm)) AS c3_cond_by_psvm,
                   (SELECT count(*) FROM d5_c3_bt) AS c3_fp_n_types,
                   (SELECT count(*) FROM d5_map m LEFT JOIN d5_c3_bt b ON b.code = m.code WHERE COALESCE(b.n, 0) <> m.n) AS c3_fp_named_bad,
                   (SELECT count(*) FROM d5_c3_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c3_fp_worlds_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c3_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS c3_fp_worlds_n,
                   (SELECT count(*) FROM d5_c3_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c3_fp_single_types,
                   (SELECT COALESCE(sum(n), 0) FROM d5_c3_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS c3_fp_single_n,
                   (SELECT count(*) FROM d5_c3_bt b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)' AND b.n <> 1) AS c3_fp_single_non1,
                   (SELECT count(*) FROM d5_c3 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'SVP') AS c3_fp_slr_svp,
                   (SELECT count(*) FROM d5_c3 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'DP1') AS c3_fp_slr_dp1,
                   (SELECT count(*) FROM d5_c3 s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
                      JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_STANDARDS' AND cs.code = 'DP1') AS c3_fp_sls_dp1,
                   (SELECT count(*) FROM public.catalog_variant_import_row WHERE resulting_variant_id IS NOT NULL) AS lineage_resulting,
                   (SELECT count(*) FROM public.catalog_variant_import_row WHERE matched_variant_id IS NOT NULL) AS lineage_matched
        )
        SELECT to_jsonb(m) FROM d5_m m
          INTO STRICT v_agg;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=DERIV-5X derivação falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;
    -- C3 não tem escopo de Game (seletor histórico verbatim): fail-closed se
    -- variant_type.code não for único.
    IF (v_agg->>'type_code_dup')::bigint IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=DERIV-5X variant_type.code não único (type_code_dup=%s); C3 sem escopo de Game é inválido', c_env, v_agg->>'type_code_dup');
    END IF;

    -- ================================================================== --
    -- 5.1 [AUTO RO] hold_frozen = 107 exato (PASSO 0 da 2831)
    -- ================================================================== --
    v_case := '5.1';
    BEGIN
        IF (v_agg->>'hold')::bigint IS DISTINCT FROM 107 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s hold_frozen: medido=%s esperado=107 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'hold')::bigint);
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
    -- 5.2 [AUTO RO] READY_STRUCTURAL 365 = UNCONDITIONED 285 + PRICING_CONDITIONED 80
    -- ================================================================== --
    v_case := '5.2';
    BEGIN
        IF (v_agg->>'c3_structural')::bigint IS DISTINCT FROM 365 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s READY_STRUCTURAL: medido=%s esperado=365 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_structural')::bigint);
        END IF;
        IF (v_agg->>'c3_unconditioned')::bigint IS DISTINCT FROM 285 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s READY_UNCONDITIONED: medido=%s esperado=285 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_unconditioned')::bigint);
        END IF;
        IF (v_agg->>'c3_conditioned')::bigint IS DISTINCT FROM 80 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s READY_PRICING_CONDITIONED: medido=%s esperado=80 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_conditioned')::bigint);
        END IF;
        IF NOT COALESCE(((v_agg->>'c3_fp_named_bad')::bigint = 0 AND (v_agg->>'c3_fp_n_types')::bigint = 63 AND (v_agg->>'c3_fp_worlds_types')::bigint = 21 AND (v_agg->>'c3_fp_worlds_n')::bigint = 21 AND (v_agg->>'c3_fp_single_types')::bigint = 19 AND (v_agg->>'c3_fp_single_n')::bigint = 24 AND (v_agg->>'c3_fp_single_non1')::bigint = 5 AND (v_agg->>'c3_fp_slr_svp')::bigint = 38 AND (v_agg->>'c3_fp_slr_dp1')::bigint = 2 AND (v_agg->>'c3_fp_sls_dp1')::bigint = 4), false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s impressão digital de A (MIGRATION-MAP-365) não reproduzida pelo candidato c3', c_env, v_case);
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
    -- 5.3 [AUTO RO] plano (285) ∩ HOLD (107) = 0 — prova de EXCLUSÃO do HOLD
    -- ================================================================== --
    v_case := '5.3';
    BEGIN
        IF (v_agg->>'c3_plan_x_hold')::bigint IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano ∩ HOLD: medido=%s esperado=0 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_plan_x_hold')::bigint);
        END IF;
        IF (v_agg->>'c3_unconditioned')::bigint IS DISTINCT FROM 285 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo do plano (P13): medido=%s esperado=285 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_unconditioned')::bigint);
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
    -- 5.6 [AUTO RO] lineage intacto: resulting 23.955 · matched 1.129 (baseline de FREEZE)
    -- ================================================================== --
    v_case := '5.6';
    BEGIN
        IF (v_agg->>'lineage_resulting')::bigint IS DISTINCT FROM 23955 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s resulting_variant_id: medido=%s esperado=23955 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'lineage_resulting')::bigint);
        END IF;
        IF (v_agg->>'lineage_matched')::bigint IS DISTINCT FROM 1129 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s matched_variant_id: medido=%s esperado=1129 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'lineage_matched')::bigint);
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
    -- 5.7 [AUTO RO] plano ∩ PRICING_CONDITIONED = 0; 80 = STAFF_HOLO 40 + SET_LOGO_REVERSE 40; conceitos separados
    -- ================================================================== --
    v_case := '5.7';
    BEGIN
        IF (v_agg->>'c3_plan_x_pricing')::bigint IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano ∩ PRICING_CONDITIONED: medido=%s esperado=0 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_plan_x_pricing')::bigint);
        END IF;
        IF (v_agg->>'c3_conditioned')::bigint IS DISTINCT FROM 80 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s PRICING_CONDITIONED em READY_STRUCTURAL: medido=%s esperado=80 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_conditioned')::bigint);
        END IF;
        IF (v_agg->>'c3_cond_staff_holo')::bigint IS DISTINCT FROM 40 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s STAFF_HOLO: medido=%s esperado=40 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_cond_staff_holo')::bigint);
        END IF;
        IF (v_agg->>'c3_cond_set_logo_reverse')::bigint IS DISTINCT FROM 40 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET_LOGO_REVERSE: medido=%s esperado=40 (STOP e adjudicação; nunca reajuste)', c_env, v_case, (v_agg->>'c3_cond_set_logo_reverse')::bigint);
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
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s hold=%s structural=%s unconditioned=%s conditioned=%s by_pscid=%s by_psvm=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), v_agg->>'hold', v_agg->>'c3_structural', v_agg->>'c3_unconditioned', v_agg->>'c3_conditioned', v_agg->>'c3_cond_by_pscid', v_agg->>'c3_cond_by_psvm');
END
$h2830_e15$;
