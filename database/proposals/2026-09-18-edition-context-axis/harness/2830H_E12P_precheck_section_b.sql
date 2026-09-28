-- ============================================================================
-- 2830H · PRECHECK E12P — SEÇÃO B · lote L10 · SELECT único, read-only
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO.
-- Gate .......... gate_pass = true exige: Game/fonte únicos; identidade pinada da
--                 2211/2176/normalize/scope; guard 2214 estrito (tokens) e CHECKs;
--                 nenhum job em voo; universos baratos medidos (sem 2211): total,
--                 V5 e CANCELLED VALID+PENDING > 0; >= 1 UUID gravado.
-- Evidência ..... distribuição observado × validation × persistence × job (V12),
--                 sempre evidência, nunca gate.
-- ============================================================================
WITH
gs AS (
    SELECT (SELECT id FROM public.game WHERE code = 'POKEMON') AS game_id,
           (SELECT id FROM public.asset_source WHERE code = 'TCGDEX') AS src_id
),
rc_exp(sig, pin, lang, vol, secdef, cfg, result) AS (
    VALUES ('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)', 'f10af378c2d5d9fdfd207d9c7d9ff046', 'plpgsql', 's', true,
            ARRAY['search_path=""'],
            'TABLE(printing_state text, printing_profile_id uuid, printing_trait_ids uuid[], edition_context_state text, edition_context_profile_id uuid, edition_context_trait_ids uuid[], residual_type text, residual_foil text, residual_subtype text, residual_stamp text[])'),
           ('internal.compute_variant_residual_signature(jsonb,uuid,uuid)', 'b15a527d3b6adb1e50cbaafae22431bc', 'plpgsql', 's', true,
            ARRAY['search_path=""'],
            'TABLE(residual_type text, residual_foil text, residual_subtype text, residual_stamp text[], printing_state text, trait_ids uuid[], printing_profile_id uuid)'),
           ('public.normalize_external_catalog_value(text)', '1fdc2e7ebe2297f8db85be4aad2e5d33', 'sql', 's', false,
            ARRAY['search_path=""'],
            'text'),
           ('internal.resolve_variant_mapping_scope(uuid,uuid)', '21a57ebf7e0d15fc14e576999523cd51', 'sql', 's', true,
            ARRAY['search_path=""'],
            'TABLE(external_set_id text, reference_id uuid)')
),
rc AS (
    SELECT e.sig, e.pin, p.oid AS fn_oid,
           md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) AS body_md5_lf,
           l.lanname::text AS lang, p.provolatile::text AS vol, p.prosecdef AS secdef,
           p.proconfig::text[] AS cfg, pg_get_function_result(p.oid) AS result,
           (p.oid IS NOT NULL AND l.lanname = e.lang AND p.provolatile = e.vol AND p.prosecdef = e.secdef
            AND p.proconfig::text[] = e.cfg AND pg_get_function_result(p.oid) = e.result
            AND md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) = e.pin) AS ok
      FROM rc_exp e
      LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.sig)
      LEFT JOIN pg_language l ON l.oid = p.prolang
),
jr_guard AS (
    SELECT p.prosrc
      FROM pg_proc p WHERE p.oid = to_regprocedure('internal.guard_cvir_normalized_shape()')
),
jr_tok(tok) AS (
    VALUES ('CVIR_SHAPE_INVALID_PRINTING:'), ('CVIR_SHAPE_INVALID_EDITION_CONTEXT:'), ('nao e UUID valido'),
           ('CVIR_VALID_REQUIRES_VARIANT_TYPE:'), ('CVIR_VALID_REQUIRES_PRINTING_KEY:'),
           ('CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:'), ('CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN:')
),
jr_ck AS (
    SELECT c.conrelid::regclass::text AS rel, c.conname::text AS conname, pg_get_constraintdef(c.oid) AS def
      FROM pg_constraint c
     WHERE c.conname IN ('ck_catalog_variant_import_job_status', 'ck_catalog_variant_import_job_source',
                         'ck_catalog_variant_import_row_validation_status', 'ck_catalog_variant_import_row_decision_status',
                         'ck_catalog_variant_import_row_persistence_status', 'ck_catalog_variant_import_row_printing_profile_shape',
                         'ck_catalog_variant_import_row_valid_requires_printing_key')
),
jr_fx AS (
    SELECT (SELECT count(*) FROM (SELECT 1 FROM public.card c JOIN public.card_set cs ON cs.id = c.card_set_id
                                   JOIN public.expansion e ON e.id = cs.expansion_id, gs
                                  WHERE e.game_id = gs.game_id LIMIT 16) z) AS cards,
           (SELECT count(*) FROM public.card_variant_type t, gs WHERE t.game_id = gs.game_id) AS vts,
           (SELECT count(*) FROM public.card_printing_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS pps,
           (SELECT count(*) FROM public.card_edition_context_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS ecs,
           (SELECT count(*) FROM public.card_variant) AS cvs
),
vu AS (
    SELECT (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND r.persistence_status = 'PENDING') AS op, j.status AS job_status,
           r.validation_status AS val, r.persistence_status AS per,
           CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                ELSE 'UUID' END AS obs
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
),
vcell AS (
    SELECT obs, val, per, job_status, count(*) AS n FROM vu GROUP BY 1, 2, 3, 4
),
gates AS (
    SELECT
        ((SELECT count(*) FROM public.game WHERE code = 'POKEMON') = 1
         AND (SELECT count(*) FROM public.asset_source WHERE code = 'TCGDEX') = 1)    AS g_game_source_one,
        ((SELECT count(*) FROM rc WHERE ok) = 4
         AND has_function_privilege(current_user, to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)'), 'EXECUTE')
         AND has_function_privilege(current_user, to_regprocedure('internal.resolve_variant_mapping_scope(uuid,uuid)'), 'EXECUTE')) AS g_rc_identity,
        (SELECT count(*) FROM jr_tok k, jr_guard g WHERE strpos(g.prosrc, k.tok) > 0) = 7
         AND NOT EXISTS (SELECT 1 FROM jr_guard g WHERE strpos(g.prosrc, 'CVIR_PENDING_VALID_REQUIRES_EDITION_CONTEXT_KEY') > 0)
                                                                                      AS g_jr_guard_tokens,
        ((SELECT count(*) FROM jr_ck) = 7
         AND (SELECT count(*) FROM jr_ck WHERE conname = 'ck_catalog_variant_import_job_status'
               AND strpos(def, '''RECEIVED''') > 0 AND strpos(def, '''PROCESSING''') > 0 AND strpos(def, '''STAGED''') > 0
               AND strpos(def, '''CONFIRMING''') > 0 AND strpos(def, '''COMPLETED''') > 0
               AND strpos(def, '''COMPLETED_WITH_ERRORS''') > 0 AND strpos(def, '''FAILED''') > 0
               AND strpos(def, '''CANCELLED''') > 0) = 1
         AND (SELECT count(*) FROM jr_ck WHERE conname = 'ck_catalog_variant_import_row_persistence_status'
               AND strpos(def, '''PENDING''') > 0 AND strpos(def, '''INSERTED''') > 0
               AND strpos(def, '''UNCHANGED''') > 0 AND strpos(def, '''FAILED''') > 0) = 1)     AS g_jr_checks,
        (SELECT count(*) FROM pg_index i
          WHERE i.indexrelid = to_regclass('public.uq_catalog_variant_import_job_fingerprint_active')
            AND i.indisunique AND i.indisvalid AND i.indpred IS NOT NULL) = 1
         AND (SELECT count(*) FROM pg_index i
          WHERE i.indexrelid = to_regclass('public.uq_cvir_row_identity') AND i.indisunique AND i.indisvalid) = 1
                                                                                      AS g_jr_indexes,
        ((SELECT cards FROM jr_fx) = 16 AND (SELECT vts FROM jr_fx) >= 1 AND (SELECT pps FROM jr_fx) >= 1
         AND (SELECT ecs FROM jr_fx) >= 1 AND (SELECT cvs FROM jr_fx) >= 1)          AS g_jr_fixture_available,
        (SELECT count(*) FROM public.catalog_variant_import_job
          WHERE status IN ('RECEIVED','PROCESSING','CONFIRMING')) = 0                 AS g_jr_no_job_in_flight,
        ((SELECT count(*) FROM vu) > 0
         AND (SELECT count(*) FROM vu WHERE NOT op AND val = 'VALID' AND obs = 'ABSENT') > 0
         AND (SELECT count(*) FROM vu WHERE job_status = 'CANCELLED' AND val = 'VALID' AND per = 'PENDING') > 0
         AND (SELECT count(*) FROM vu WHERE obs = 'UUID') > 0)                         AS g_v_universes
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_rc_identity',    COALESCE((SELECT jsonb_agg(to_jsonb(r) - 'fn_oid' ORDER BY r.sig) FROM rc r), '[]'::jsonb),
        'd_v_universes',    jsonb_build_object(
                                'total', (SELECT count(*) FROM vu),
                                'op', (SELECT count(*) FROM vu WHERE op),
                                'op_valid', (SELECT count(*) FROM vu WHERE op AND val = 'VALID'),
                                'hist_with_key', (SELECT count(*) FROM vu WHERE NOT op AND obs <> 'ABSENT'),
                                'recheck_universe', (SELECT count(*) FROM vu WHERE op OR obs <> 'ABSENT'),
                                'v5', (SELECT count(*) FROM vu WHERE NOT op AND val = 'VALID' AND obs = 'ABSENT'),
                                'cancel_vp', (SELECT count(*) FROM vu WHERE job_status = 'CANCELLED' AND val = 'VALID' AND per = 'PENDING')),
        'd_jr_checks',      COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.conname) FROM jr_ck c), '[]'::jsonb),
        'd_v12_cells',      COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.obs, c.val, c.per, c.job_status) FROM vcell c), '[]'::jsonb),
        'd_session',        jsonb_build_object(
                                'current_user',       current_user,
                                'server_version_num', current_setting('server_version_num'),
                                'lock_timeout',       current_setting('lock_timeout'),
                                'search_path',        current_setting('search_path'),
                                'backend_pid',        pg_backend_pid(),
                                'checked_at',         clock_timestamp())
    ) AS e12p_precheck
  FROM gates g;
