EXPLAIN (COSTS OFF)
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
