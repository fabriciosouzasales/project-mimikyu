EXPLAIN (COSTS OFF)
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
