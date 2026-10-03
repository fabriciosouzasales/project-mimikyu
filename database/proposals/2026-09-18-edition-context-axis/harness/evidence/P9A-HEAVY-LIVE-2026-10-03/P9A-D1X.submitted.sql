EXPLAIN (COSTS OFF)
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
  FROM gates g CROSS JOIN d1_m m;
