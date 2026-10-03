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
)
SELECT to_jsonb(m) FROM d5_m m;
