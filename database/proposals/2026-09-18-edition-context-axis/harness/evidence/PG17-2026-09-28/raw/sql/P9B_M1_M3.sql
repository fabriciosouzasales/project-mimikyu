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

