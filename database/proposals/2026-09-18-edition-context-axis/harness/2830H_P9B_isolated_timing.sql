-- ============================================================================
-- 2830H · P9B — TEMPO REAL DAS SEÇÕES PESADAS · EXPLAIN (ANALYZE, BUFFERS) · SOMENTE AMBIENTE ISOLADO
-- ============================================================================
-- Status ........ PREPARADO — NÃO EXECUTADO. PROIBIDO no LIVE sem autorização
--                 específica (ANALYZE executa a consulta). Clone isolado com
--                 paridade de volume provada (P14a).
-- Cenários ...... M1 VREC (E12): 2211 sobre op ∪ histórico com chave.
--                 M2 V1-complemento (E12): 2211 sobre histórico SEM chave (pior caso
--                 de V1 quando não há ocorrência no VREC).
--                 M3 SMREC (E13): varredura agregada da staging.
--                 M4 DERIV-5X (E15P/E15): HOLD, PRICING e C2 (2211 por variant).
--                 M5 envelopes completos E12, E13, E15P: elapsed_ms do H283P /
--                 tempo do statement; limite do protocolo 120 s por envelope.
-- Critério ...... cada Mn < 60 s (metade do orçamento, margem para 2x); acima
--                 disso a seção é dividida antes do LIVE (AD-2).
-- ============================================================================

-- M1  VREC (E12)
EXPLAIN (ANALYZE, BUFFERS)
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
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(b.card_set_id, (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')) sc ON true
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(b.raw_data, (SELECT id FROM public.game WHERE code = 'POKEMON'), (SELECT id FROM public.asset_source WHERE code = 'TCGDEX'), sc.external_set_id) ax
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
  FROM x;

-- M2  V1-complemento (E12, sem LIMIT: pior caso)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM (
    SELECT 1
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card c ON c.id = r.card_id
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')) sc ON true
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, (SELECT id FROM public.game WHERE code = 'POKEMON'), (SELECT id FROM public.asset_source WHERE code = 'TCGDEX'), sc.external_set_id) ax
     WHERE NOT (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND r.persistence_status = 'PENDING')
       AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
       AND ax.edition_context_state = 'RESOLVED_WITH_EC_PROFILE') z;

-- M3  SMREC (E13)
EXPLAIN (ANALYZE, BUFFERS)
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
  FROM x;

-- M4  DERIV-5X (E15P/E15)
EXPLAIN (ANALYZE, BUFFERS)
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
