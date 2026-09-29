-- ============================================================================
-- 2830H · ENVELOPE E15 — SEÇÃO 5 (LEGADO / HOLD / EXCLUSÃO) · lote L13, 5 casos: 5.1 5.2 5.3 5.6 5.7
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL. BLOQUEADO pela pendência 5.3/5.7: READY_DEF = C3
--                 adjudicado (B5X-C3-ADJUDICATION-RECORD.md); 5.3/5.7 reescritas
--                 sobre o D1 (D1X) aguardam auditoria independente. O PREFLIGHT
--                 levanta H2830_FAIL enquanto E15_BLOCKED_53_57 = True no gerador.
-- Contrato ...... 2830 v7.0 Seção 5; derivação 2831 v2.0 PASSO 0/0B/1 (arquivo
--                 NÃO alterado), sem TEMP, bloco DERIV-5X idêntico ao E15P.
-- Escrita ....... NENHUMA. Término em exceção por uniformidade (P2).
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- 5.3/5.7 ....... DERIV-D1X = DERIV-5X histórico (inalterado) + bloco do
--                 instrumento D1 executado no LIVE em 2026-09-29, byte a byte
--                 (evidence/D1-2026-09-29, md5 efb3217e…). Provas: universo U_raw
--                 independente, partição exata, composição HOLD/NC por (tipo, Set),
--                 plano contratual por código ≡ plano derivado por id, pscid e psvm
--                 separados, HOLD/C3 do DERIV ≡ D1 por id e as quatro âncoras
--                 congeladas (HOLD, PLAN, READY, CONDITIONED).
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
    v_d1       jsonb;
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
    -- B-5X: sem READY_DEF adjudicado, ou com 5.3/5.7 sem auditoria
    -- independente do desbloqueio, nenhum caso roda (fail-closed)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
        'H2830_FAIL: envelope=%s caso=PREFLIGHT B-5X: READY_DEF=%s adjudicado; 5.3/5.7 reescritas (D1X) aguardam auditoria independente; E15 bloqueado', c_env, 'c3');

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
    -- ------------------------------------------------------------------ --
    -- DERIV-D1X (5.3/5.7): DERIV-5X histórico + bloco do instrumento D1
    -- executado no LIVE (evidence/D1-2026-09-29), byte a byte. Só lê: HOLD
    -- (d5_hold) e C3 (d5_c3) do DERIV; o restante do DERIV (inclusive C2 e a
    -- 2211) não é referenciado e não é avaliado. Subtransação própria.
    -- ------------------------------------------------------------------ --
    v_case := 'DERIV-D1X';
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
        ),
        h_finish(code) AS (
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
        h_ready(code, n) AS (
            VALUES ('COSMOS_PROFESSOR_REVERSE', 16),
                   ('COSMOS_REWARDS_HOLO', 18),
                   ('COSMOS_REWARDS_REVERSE', 17),
                   ('COSMO_HOLO_EBGAMES', 1),
                   ('EBGAMES_HOLO', 8),
                   ('EBGAMES_REVERSE', 2),
                   ('GAMESTOP_HOLO', 9),
                   ('GYM_CHALLENGE_HOLO', 3),
                   ('HORIZONS_HOLO', 1),
                   ('INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO', 1),
                   ('INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE', 1),
                   ('INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF', 1),
                   ('NATIONAL_CHAMPIONSHIPS_REVERSE', 1),
                   ('NATIONAL_CHAMPIONSHIPS_REVERSE_STAFF', 1),
                   ('PLAYER_REWARD_REVERSE', 1),
                   ('POKEDAY_HOLO', 1),
                   ('POKEMON_CENTER_HOLO', 19),
                   ('PRERELEASE_COSMOS_HOLO', 1),
                   ('PRERELEASE_HOLO', 1),
                   ('REWARDS_HOLO', 30),
                   ('SATANDARD_REWARDS', 51),
                   ('SET_LOGO_REVERSE', 40),
                   ('SET_LOGO_STANDARDS', 4),
                   ('STAFF_HOLO', 40),
                   ('STANDARDS_ASIA_2023_2024', 1),
                   ('STANDARDS_GAMESTOP', 2),
                   ('STANDARDS_HORIZONS', 3),
                   ('STANDARDS_LEAGUE', 4),
                   ('STANDARDS_POKEMON_CENTER', 1),
                   ('STANDARDS_POKEMON_TOGETHER', 2),
                   ('STANDARDS_TEACHER_PROGRAM', 14),
                   ('STANDARDS_WORLDS_2023', 1),
                   ('STANDARDS_WORLDS_2023_STAFF', 1),
                   ('STANDARDS_WORLDS_2023_TOP_16', 1),
                   ('STANDARDS_WORLDS_2023_TOP_2', 1),
                   ('STANDARDS_WORLDS_2023_TOP_32', 1),
                   ('STANDARDS_WORLDS_2023_TOP_4', 1),
                   ('STANDARDS_WORLDS_2023_TOP_8', 1),
                   ('STANDARDS_WORLDS_2024_STAFF', 1),
                   ('STANDARDS_WORLDS_2024_TOP_16', 1),
                   ('STANDARDS_WORLDS_2024_TOP_2', 1),
                   ('STANDARDS_WORLDS_2024_TOP_32', 1),
                   ('STANDARDS_WORLDS_2024_TOP_4', 1),
                   ('STANDARDS_WORLDS_2024_TOP_8', 1),
                   ('STANDARDS_WORLDS_2025', 1),
                   ('STANDARDS_WORLDS_2025_STAFF', 1),
                   ('STANDARDS_WORLDS_2025_TOP_16', 1),
                   ('STANDARDS_WORLDS_2025_TOP_2', 1),
                   ('STANDARDS_WORLDS_2025_TOP_32', 1),
                   ('STANDARDS_WORLDS_2025_TOP_4', 1),
                   ('STANDARDS_WORLDS_2026_TOP_8', 1),
                   ('STANDARD_FIRST_MOVIE', 4),
                   ('STANDARD_FIRST_MOVIE_INVERTED', 4),
                   ('STANDARD_GYM_CHALLENGE', 9),
                   ('STANDARD_PIKACHU_WORLD_2000', 6),
                   ('STANDARD_POKEMON_4EVER', 2),
                   ('STANDARD_POKEMON_CENTER_NY', 2),
                   ('STANDARD_POKETOUR_1999', 1),
                   ('STANDARD_REGIONAL_CHAMPIONSHIPS', 8),
                   ('STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF', 4),
                   ('STANDARD_ULTRA_BALL_LEAGUE', 1),
                   ('STANDARD_WORLDS_2024', 3),
                   ('W_PROMO_STAMPED', 6)
        ),
        h_hold(k, n) AS (
            VALUES ('PROMO_STAMPED', 33),
                   ('SET_LOGO_COSMOS_HOLO@SV10.5B', 1),
                   ('SET_LOGO_COSMOS_HOLO@SV5', 1),
                   ('SET_LOGO_COSMOS_HOLO@SV6', 1),
                   ('SET_LOGO_REVERSE@HGSS4', 1),
                   ('SET_LOGO_REVERSE@SV10', 9),
                   ('SET_LOGO_REVERSE@SV10.5W', 2),
                   ('SET_LOGO_REVERSE@SV2', 2),
                   ('SET_LOGO_REVERSE@SV3', 1),
                   ('SET_LOGO_REVERSE@SV4', 1),
                   ('SET_LOGO_REVERSE@SV5', 4),
                   ('SET_LOGO_REVERSE@SV6', 3),
                   ('SET_LOGO_REVERSE@SV6.5', 1),
                   ('SET_LOGO_REVERSE@SV7', 6),
                   ('SET_LOGO_REVERSE@SV8', 4),
                   ('SET_LOGO_REVERSE@SV8.5', 13),
                   ('SET_LOGO_REVERSE@SV9', 7),
                   ('SET_LOGO_REVERSE@SWSH10', 2),
                   ('SET_LOGO_REVERSE@SWSH2', 1),
                   ('SET_LOGO_REVERSE@SWSH3', 1),
                   ('SET_LOGO_REVERSE@SWSH4', 1),
                   ('SET_LOGO_STAFF_HOLO@HGSS4', 1),
                   ('SET_LOGO_STANDARDS@COL1', 1),
                   ('SET_LOGO_STANDARDS@DP2', 2),
                   ('SET_LOGO_STANDARDS@SV3.5', 1),
                   ('SET_LOGO_STANDARDS@SV5', 2),
                   ('SET_LOGO_STANDARDS@SV7', 2),
                   ('SET_LOGO_STANDARDS@SV8.5', 1),
                   ('SET_LOGO_STANDARDS@SWSH11', 1),
                   ('SET_LOGO_STANDARDS@SWSH12', 1)
        ),
        h_nc(k, n) AS (
            VALUES ('SET_LOGO_REVERSE@EX11', 18),
                   ('SET_LOGO_REVERSE@EX12', 14),
                   ('SET_LOGO_REVERSE@EX13', 16),
                   ('SET_LOGO_REVERSE@EX14', 13),
                   ('SET_LOGO_REVERSE@EX15', 12),
                   ('SET_LOGO_REVERSE@EX16', 13),
                   ('SET_LOGO_STANDARDS@EX11', 89),
                   ('SET_LOGO_STANDARDS@EX12', 68),
                   ('SET_LOGO_STANDARDS@EX13', 82),
                   ('SET_LOGO_STANDARDS@EX14', 75),
                   ('SET_LOGO_STANDARDS@EX15', 77),
                   ('SET_LOGO_STANDARDS@EX16', 78)
        ),
        h_h6(code, pscid, psvm) AS (
            VALUES ('SET_LOGO_REVERSE', 1, 0),
                   ('STAFF_HOLO', 17, 1)
        ),
        d1_cv AS MATERIALIZED (
            SELECT cv.id, vt.id AS type_id, vt.code, cs.code AS set_code,
                   (vt.code IN (SELECT code FROM h_finish)) AS is_finish,
                   (vt.code = 'PROMO_STAMPED'
                    OR (vt.code LIKE 'SET_LOGO%'
                        AND cs.code !~ '^EX(7|8|9|10|11|12|13|14|15|16)$'
                        AND cs.code NOT IN ('DP1','SWSH9','SVP'))) AS is_hold,
                   (vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$') AS is_nc,
                   (vt.code NOT IN (SELECT code FROM h_finish)
                    AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$')
                    AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code NOT IN ('DP1','SWSH9','SVP'))
                    AND vt.code <> 'PROMO_STAMPED') AS is_ready
              FROM public.card_variant cv
              JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
              JOIN public.card c  ON c.id  = cv.card_id
              JOIN public.card_set cs ON cs.id = c.card_set_id
        ),
        d1_cls AS (
            SELECT d.*,
                   COALESCE(d.is_finish::int, 0) + COALESCE(d.is_hold::int, 0)
                   + COALESCE(d.is_nc::int, 0) + COALESCE(d.is_ready::int, 0) AS n_cls
              FROM d1_cv d
        ),
        d1_pscid AS (
            SELECT x.card_variant_type_id AS type_id, count(*) AS n FROM public.pricing_source_card_identity x GROUP BY 1
        ),
        d1_psvm AS (
            SELECT x.variant_type_id AS type_id, count(*) AS n FROM public.pricing_source_variant_mapping x GROUP BY 1
        ),
        d1_ready AS (SELECT id, type_id, code FROM d1_cls WHERE is_ready),
        d1_hold AS (SELECT id, code, set_code FROM d1_cls WHERE is_hold),
        d1_plan_contract AS (
            SELECT id FROM d1_ready WHERE code NOT IN ('STAFF_HOLO', 'SET_LOGO_REVERSE')
        ),
        d1_plan_derived AS (
            SELECT r.id FROM d1_ready r
             WHERE NOT EXISTS (SELECT 1 FROM d1_pscid s WHERE s.type_id = r.type_id)
               AND NOT EXISTS (SELECT 1 FROM d1_psvm v WHERE v.type_id = r.type_id)
        ),
        d1_cond AS (
            SELECT r.id, r.code FROM d1_ready r
             WHERE EXISTS (SELECT 1 FROM d1_pscid s WHERE s.type_id = r.type_id)
                OR EXISTS (SELECT 1 FROM d1_psvm v WHERE v.type_id = r.type_id)
        ),
        d1_ready_pr AS (
            SELECT r.code, max(s.n) AS pscid, max(v.n) AS psvm
              FROM d1_ready r
              LEFT JOIN d1_pscid s ON s.type_id = r.type_id
              LEFT JOIN d1_psvm  v ON v.type_id = r.type_id
             GROUP BY r.code
            HAVING COALESCE(max(s.n), 0) + COALESCE(max(v.n), 0) > 0
        ),
        d1_ready_bt AS (SELECT code, count(*) AS n FROM d1_ready GROUP BY code),
        d1_hold_bk AS (
            SELECT CASE WHEN code = 'PROMO_STAMPED' THEN code ELSE code || '@' || set_code END AS k, count(*) AS n
              FROM d1_hold GROUP BY 1
        ),
        d1_nc_bk AS (SELECT code || '@' || set_code AS k, count(*) AS n FROM d1_cls WHERE is_nc GROUP BY 1),
        d1_m AS (
            SELECT (SELECT count(*) FROM public.card_variant) AS cv_total,
                   (SELECT count(*) FROM d1_cls) AS cv_joined,
                   (SELECT count(*) FROM (SELECT code FROM public.card_variant_type GROUP BY code HAVING count(*) > 1) z) AS type_code_dup,
                   (SELECT count(*) FROM d1_cls WHERE is_finish) AS n_finish,
                   (SELECT count(*) FROM d1_cls WHERE NOT COALESCE(is_finish, false)) AS n_uraw,
                   (SELECT count(*) FROM d1_cls WHERE is_ready) AS n_ready,
                   (SELECT count(*) FROM d1_cls WHERE is_hold) AS n_hold,
                   (SELECT count(*) FROM d1_cls WHERE is_nc) AS n_nc,
                   (SELECT count(*) FROM d1_cls WHERE n_cls <> 1) AS n_bad_partition,
                   (SELECT count(*) FROM (((SELECT code, n FROM d1_ready_bt) EXCEPT (SELECT code, n FROM h_ready))
                                          UNION ALL
                                          ((SELECT code, n FROM h_ready) EXCEPT (SELECT code, n FROM d1_ready_bt))) z) AS ready_bt_diff,
                   (SELECT count(*) FROM (((SELECT k, n FROM d1_hold_bk) EXCEPT (SELECT k, n FROM h_hold))
                                          UNION ALL
                                          ((SELECT k, n FROM h_hold) EXCEPT (SELECT k, n FROM d1_hold_bk))) z) AS hold_bk_diff,
                   (SELECT count(*) FROM (((SELECT k, n FROM d1_nc_bk) EXCEPT (SELECT k, n FROM h_nc))
                                          UNION ALL
                                          ((SELECT k, n FROM h_nc) EXCEPT (SELECT k, n FROM d1_nc_bk))) z) AS nc_bk_diff,
                   (SELECT count(*) FROM (((SELECT code, (pscid IS NOT NULL), (psvm IS NOT NULL) FROM d1_ready_pr
                                         ) EXCEPT (SELECT code, pscid > 0, psvm > 0 FROM h_h6))
                                          UNION ALL
                                          ((SELECT code, pscid > 0, psvm > 0 FROM h_h6) EXCEPT (SELECT code, (pscid IS NOT NULL), (psvm IS NOT NULL) FROM d1_ready_pr))) z) AS h6_type_diff,
                   (SELECT count(*) FROM d1_cond) AS n_cond,
                   (SELECT count(*) FROM d1_cond WHERE code = 'STAFF_HOLO') AS n_cond_staff_holo,
                   (SELECT count(*) FROM d1_cond WHERE code = 'SET_LOGO_REVERSE') AS n_cond_set_logo_reverse,
                   (SELECT count(*) FROM d1_plan_contract) AS n_plan_contract,
                   (SELECT count(*) FROM d1_plan_derived) AS n_plan_derived,
                   (SELECT count(*) FROM d1_plan_contract p JOIN d1_ready r ON r.id = p.id
                     WHERE EXISTS (SELECT 1 FROM d1_pscid s WHERE s.type_id = r.type_id)) AS plan_x_pscid,
                   (SELECT count(*) FROM d1_plan_contract p JOIN d1_ready r ON r.id = p.id
                     WHERE EXISTS (SELECT 1 FROM d1_psvm v WHERE v.type_id = r.type_id)) AS plan_x_psvm,
                   (SELECT count(*) FROM (((SELECT id FROM d1_plan_contract) EXCEPT (SELECT id FROM d1_plan_derived))
                                          UNION ALL
                                          ((SELECT id FROM d1_plan_derived) EXCEPT (SELECT id FROM d1_plan_contract))) z) AS plan_symdiff,
                   (SELECT count(*) FROM d1_plan_contract p JOIN d1_hold h ON h.id = p.id) AS plan_x_hold,
                   (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_hold) AS md5_hold,
                   (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_plan_contract) AS md5_plan,
                   (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_plan_derived) AS md5_plan_derived,
                   (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_ready) AS md5_ready,
                   (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_cond) AS md5_cond
        ),
        gates AS (
            SELECT (m.cv_joined = m.cv_total)                                   AS g_join_complete,
                   (m.type_code_dup = 0)                                        AS g_type_code_unique,
                   (m.cv_total = 24893 AND m.n_finish = 23866)                  AS g_universe_19_09,
                   (m.n_uraw = 1027)                                            AS g_uraw_1027,
                   (m.n_ready = 365 AND m.n_hold = 107 AND m.n_nc = 555
                    AND m.n_ready + m.n_hold + m.n_nc = m.n_uraw)               AS g_partition_counts,
                   (m.n_bad_partition = 0)                                      AS g_partition_exact,
                   (m.ready_bt_diff = 0)                                        AS g_ready_by_type_19_09,
                   (m.hold_bk_diff = 0)                                         AS g_hold_by_type_set_19_09,
                   (m.nc_bk_diff = 0)                                           AS g_nc_by_type_set_19_09,
                   (m.h6_type_diff = 0)                                         AS g_h6_types,
                   (m.n_cond = 80 AND m.n_cond_staff_holo = 40
                    AND m.n_cond_set_logo_reverse = 40)                         AS g_conditioned_80_40_40,
                   (m.n_plan_contract = 285)                                    AS g_plan_contract_285,
                   (m.plan_x_pscid = 0)                                         AS g_plan_x_pscid_zero,
                   (m.plan_x_psvm = 0)                                          AS g_plan_x_psvm_zero,
                   (m.plan_symdiff = 0 AND m.md5_plan = m.md5_plan_derived)     AS g_plan_equivalence,
                   (m.plan_x_hold = 0)                                          AS g_plan_x_hold_zero
              FROM d1_m m
        )
        SELECT pg_catalog.jsonb_build_object(
            'g', pg_catalog.to_jsonb(g),
            'm', pg_catalog.to_jsonb(m),
            'x_md5_hold_deriv', (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d5_hold),
            'x_md5_ready_c3', (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d5_c3))
          FROM gates g CROSS JOIN d1_m m
          INTO STRICT v_d1;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=DERIV-D1X derivação falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;

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
    -- 5.3 [AUTO RO] exclusão do HOLD — universo independente, partição exata, composição e âncoras por id (D1)
    -- ================================================================== --
    v_case := '5.3';
    BEGIN
        IF NOT COALESCE((v_d1->'g'->>'g_join_complete')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s join card_variant × tipo × card × set completo: gate D1 g_join_complete falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_type_code_unique')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s variant_type.code único: gate D1 g_type_code_unique falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_universe_19_09')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo 24.893 / FINISH 23.866: gate D1 g_universe_19_09 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_uraw_1027')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo pré-exclusão U_raw = 1.027 (independente do plano): gate D1 g_uraw_1027 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_partition_counts')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s partição READY 365 + HOLD 107 + NÃO_CONT 555 = U_raw: gate D1 g_partition_counts falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_partition_exact')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s partição exata (cada variante em exatamente 1 classe): gate D1 g_partition_exact falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_ready_by_type_19_09')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s composição READY por tipo = 19/09: gate D1 g_ready_by_type_19_09 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_hold_by_type_set_19_09')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s composição HOLD por (tipo, Set) = 19/09 (D2): gate D1 g_hold_by_type_set_19_09 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_nc_by_type_set_19_09')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s composição NÃO_CONT por (tipo, Set) = 19/09: gate D1 g_nc_by_type_set_19_09 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF (v_d1->'m'->>'n_hold')::bigint IS DISTINCT FROM 107 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora HOLD por id (n): medido=%s esperado=107 (STOP; nunca reajuste)', c_env, v_case, (v_d1->'m'->>'n_hold')::bigint);
        END IF;
        IF (v_d1->'m'->>'md5_hold') IS DISTINCT FROM '0e56dfffc8cc9ef09b66d4f5fe958d91' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora HOLD por id: md5 medido=%s congelado=0e56dfffc8cc9ef09b66d4f5fe958d91 (troca compensada ou deriva; STOP)', c_env, v_case, (v_d1->'m'->>'md5_hold'));
        END IF;
        IF (v_d1->'m'->>'n_ready')::bigint IS DISTINCT FROM 365 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora READY por id (n): medido=%s esperado=365 (STOP; nunca reajuste)', c_env, v_case, (v_d1->'m'->>'n_ready')::bigint);
        END IF;
        IF (v_d1->'m'->>'md5_ready') IS DISTINCT FROM 'ee0e4c54336179431797e602a358bb0e' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora READY por id: md5 medido=%s congelado=ee0e4c54336179431797e602a358bb0e (troca compensada ou deriva; STOP)', c_env, v_case, (v_d1->'m'->>'md5_ready'));
        END IF;
        IF (v_d1->>'x_md5_hold_deriv') IS DISTINCT FROM (v_d1->'m'->>'md5_hold') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s HOLD 2831 PASSO 0 (d5_hold) ≡ HOLD D1: seletor histórico do DERIV-5X difere do conjunto D1 por id (%s × %s)', c_env, v_case, v_d1->>'x_md5_hold_deriv', v_d1->'m'->>'md5_hold');
        END IF;
        IF (v_d1->>'x_md5_ready_c3') IS DISTINCT FROM (v_d1->'m'->>'md5_ready') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s C3 adjudicado (d5_c3) ≡ READY D1: seletor histórico do DERIV-5X difere do conjunto D1 por id (%s × %s)', c_env, v_case, v_d1->>'x_md5_ready_c3', v_d1->'m'->>'md5_ready');
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_plan_x_hold_zero')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano ∩ HOLD = 0 (consistência de código, não prova): gate D1 g_plan_x_hold_zero falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF (v_d1->'m'->>'n_plan_contract')::bigint IS DISTINCT FROM 285 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo do plano não vazio (P13): medido=%s esperado=285 (STOP; nunca reajuste)', c_env, v_case, (v_d1->'m'->>'n_plan_contract')::bigint);
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
    -- 5.7 [AUTO RO] exclusão de PRICING_CONDITIONED — plano contratual ≡ plano derivado por id; pscid e psvm separados (D1)
    -- ================================================================== --
    v_case := '5.7';
    BEGIN
        IF NOT COALESCE((v_d1->'g'->>'g_plan_contract_285')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano contratual por código (sem Pricing) = 285: gate D1 g_plan_contract_285 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF (v_d1->'m'->>'n_plan_contract')::bigint IS DISTINCT FROM 285 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora PLAN por id (n): medido=%s esperado=285 (STOP; nunca reajuste)', c_env, v_case, (v_d1->'m'->>'n_plan_contract')::bigint);
        END IF;
        IF (v_d1->'m'->>'md5_plan') IS DISTINCT FROM 'a53343fa38bbbe6f45fea7a4dba4bbdb' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora PLAN por id: md5 medido=%s congelado=a53343fa38bbbe6f45fea7a4dba4bbdb (troca compensada ou deriva; STOP)', c_env, v_case, (v_d1->'m'->>'md5_plan'));
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_plan_equivalence')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano contratual ≡ plano derivado de Pricing por id: gate D1 g_plan_equivalence falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF (v_d1->'m'->>'plan_symdiff')::bigint IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s diferença simétrica plano contratual × derivado: medido=%s esperado=0 (STOP; nunca reajuste)', c_env, v_case, (v_d1->'m'->>'plan_symdiff')::bigint);
        END IF;
        IF (v_d1->'m'->>'md5_plan_derived') IS DISTINCT FROM 'a53343fa38bbbe6f45fea7a4dba4bbdb' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano derivado: md5 medido=%s congelado=a53343fa38bbbe6f45fea7a4dba4bbdb (STOP)', c_env, v_case, (v_d1->'m'->>'md5_plan_derived'));
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_plan_x_pscid_zero')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano ∩ tipos com pricing_source_card_identity = 0 (pscid): gate D1 g_plan_x_pscid_zero falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_plan_x_psvm_zero')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s plano ∩ tipos com pricing_source_variant_mapping = 0 (psvm): gate D1 g_plan_x_psvm_zero falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_h6_types')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s H6: padrão pscid/psvm por tipo READY = 19/09: gate D1 g_h6_types falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF NOT COALESCE((v_d1->'g'->>'g_conditioned_80_40_40')::boolean, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s PRICING_CONDITIONED 80 = STAFF_HOLO 40 + SET_LOGO_REVERSE 40: gate D1 g_conditioned_80_40_40 falso ou ausente (STOP; nunca reajuste)', c_env, v_case);
        END IF;
        IF (v_d1->'m'->>'n_cond')::bigint IS DISTINCT FROM 80 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora CONDITIONED por id (n): medido=%s esperado=80 (STOP; nunca reajuste)', c_env, v_case, (v_d1->'m'->>'n_cond')::bigint);
        END IF;
        IF (v_d1->'m'->>'md5_cond') IS DISTINCT FROM '288f9b45b8e95bfb7123fe9e8693d3a3' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s âncora CONDITIONED por id: md5 medido=%s congelado=288f9b45b8e95bfb7123fe9e8693d3a3 (troca compensada ou deriva; STOP)', c_env, v_case, (v_d1->'m'->>'md5_cond'));
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
