-- ============================================================================
-- 2830H · E08P — PRECHECK DO LOTE L6 (Seção 4)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.
-- Cobre ......... P7X (card_variant e demais), P6, RLS, fixture disponível (par
--                 livre, profiles ativos), XBASELINE, marcador, 2 profiles EC.
-- ============================================================================
WITH
gs AS (
    SELECT (SELECT id FROM public.game WHERE code = 'POKEMON') AS game_id,
           (SELECT id FROM public.asset_source WHERE code = 'TCGDEX') AS src_id
),
p7x_tbl(name) AS (
    VALUES ('game'), ('card_variant'), ('catalog_variant_import_job'), ('catalog_variant_import_row')
),
p7x_rel AS (
    SELECT t.name, to_regclass('public.' || t.name) AS oid FROM p7x_tbl t
),
p7x_trg_exp(tgname, relname, tgtype, fn, attrs) AS (
    VALUES ('trg_game_set_updated_at',                       'game',                       19, 'public.set_updated_at()',                                      ARRAY[]::text[]),
           ('trg_card_variant_set_updated_at',               'card_variant',               19, 'public.set_updated_at()',                                      ARRAY[]::text[]),
           ('trg_card_variant_validate_game_consistency',    'card_variant',               23, 'public.validate_card_variant_game_consistency()',              ARRAY['card_id','variant_type_id']),
           ('trg_card_variant_printing_profile_game',        'card_variant',               23, 'internal.enforce_card_variant_printing_profile_game()',        ARRAY['card_id','printing_profile_id']),
           ('trg_card_variant_edition_context_profile_game', 'card_variant',               23, 'internal.enforce_card_variant_edition_context_profile_game()', ARRAY['card_id','edition_context_profile_id']),
           ('trg_catalog_variant_import_job_normalize',      'catalog_variant_import_job', 23, 'public.normalize_catalog_variant_import_job()',                ARRAY[]::text[]),
           ('trg_catalog_variant_import_job_set_updated_at', 'catalog_variant_import_job', 19, 'public.set_updated_at()',                                      ARRAY[]::text[]),
           ('trg_catalog_variant_import_row_normalize',      'catalog_variant_import_row', 23, 'public.normalize_catalog_variant_import_row()',                ARRAY[]::text[]),
           ('trg_catalog_variant_import_row_set_updated_at', 'catalog_variant_import_row', 19, 'public.set_updated_at()',                                      ARRAY[]::text[]),
           ('trg_cvir_normalized_shape',                     'catalog_variant_import_row', 23, 'internal.guard_cvir_normalized_shape()',                       ARRAY['normalized_data','persistence_status','validation_status'])
),
p7x_trg AS (
    SELECT tg.tgname::text AS tgname, r.name AS relname, tg.tgtype::int AS tgtype, tg.tgenabled::text AS enabled,
           tg.tgfoid AS fn_oid, (tg.tgconstraint <> 0) AS is_constraint,
           COALESCE((SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                       FROM unnest(tg.tgattr::int2[]) AS k(attnum)
                       JOIN pg_attribute a ON a.attrelid = tg.tgrelid AND a.attnum = k.attnum),
                    ARRAY[]::text[]) AS attrs
      FROM p7x_rel r JOIN pg_trigger tg ON tg.tgrelid = r.oid AND NOT tg.tgisinternal
),
p7x_roots AS (
    SELECT t.fn_oid AS fn, 'trigger ' || t.tgname AS via FROM p7x_trg t
    UNION
    SELECT d.refobjid, 'check ' || c.conname
      FROM p7x_rel r JOIN pg_constraint c ON c.conrelid = r.oid
      JOIN pg_depend d ON d.classid = 'pg_constraint'::regclass AND d.objid = c.oid AND d.refclassid = 'pg_proc'::regclass
    UNION
    SELECT d.refobjid, 'default ' || a.attname
      FROM p7x_rel r JOIN pg_attrdef ad ON ad.adrelid = r.oid
      JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
      JOIN pg_depend d ON d.classid = 'pg_attrdef'::regclass AND d.objid = ad.oid AND d.refclassid = 'pg_proc'::regclass
    UNION
    SELECT d.refobjid, 'index ' || i.indexrelid::regclass::text
      FROM p7x_rel r JOIN pg_index i ON i.indrelid = r.oid
      JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = i.indexrelid AND d.refclassid = 'pg_proc'::regclass
),
p7x_allow(sig, lang, secdef, vol, cfg, pin, class) AS (
    VALUES ('public.set_updated_at()',                                      'plpgsql', false, 'v', ARRAY['search_path=""'],         '98a97559965c2e0ff884d95155ab5d3a', 'SAFE'),
           ('public.validate_card_variant_game_consistency()',              'plpgsql', false, 'v', ARRAY['search_path=""'],         'c1fe17587dfb3b0f6d7d5d690ca13636', 'SAFE'),
           ('public.normalize_catalog_variant_import_job()',                'plpgsql', false, 'v', ARRAY['search_path=""'],         'c01adb02245bd5a305e8f8987a30f1c1', 'SAFE'),
           ('public.normalize_catalog_variant_import_row()',                'plpgsql', false, 'v', ARRAY['search_path=""'],         '7ae9bd52e030b13c3a241debda491a99', 'SAFE'),
           ('internal.enforce_card_variant_printing_profile_game()',        'plpgsql', true,  'v', ARRAY['search_path=""'],         'e847a065643a7836085eefc8116bb9c5', 'SAFE'),
           ('internal.enforce_card_variant_edition_context_profile_game()', 'plpgsql', true,  'v', ARRAY['search_path=""'],         '27c1845dea596dd9b46413019799ab33', 'SAFE'),
           ('internal.guard_cvir_normalized_shape()',                       'plpgsql', false, 'v', ARRAY['search_path=""'],         'f5bcae1bd83a6880c63519b31f36c5c4', 'SAFE'),
           ('internal.axis_identity_token(jsonb,text)',                     'sql',     false, 'i', ARRAY['search_path=""'],         '18682dce935281b0a4437628a6e8309a', 'SAFE')
),
p7x_fn AS (
    SELECT DISTINCT x.fn, p.oid IS NOT NULL AS exists_fn, a.sig, a.class,
           (a.sig IS NOT NULL AND l.lanname = a.lang AND p.prosecdef = a.secdef AND p.provolatile::text = a.vol
            AND p.proconfig::text[] IS NOT DISTINCT FROM a.cfg
            AND md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) = a.pin) AS pinned,
           md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) AS body_md5_lf, p.proconfig::text[] AS cfg
      FROM p7x_roots x
      LEFT JOIN pg_proc p ON p.oid = x.fn
      LEFT JOIN pg_language l ON l.oid = p.prolang
      LEFT JOIN p7x_allow a ON to_regprocedure(a.sig) = x.fn
),
p7x_path AS (
    SELECT s.nsp, n.oid AS nsp_oid
      FROM unnest(current_schemas(false)) AS s(nsp)
      JOIN pg_namespace n ON n.nspname = s.nsp
     WHERE s.nsp NOT IN ('pg_catalog', 'pg_temp')
),
p7x_seq AS (
    SELECT r.name AS relname, s.oid::regclass::text AS sequence_name
      FROM p7x_rel r
      JOIN pg_depend d ON d.refobjid = r.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('a','i')
      JOIN pg_class s ON s.oid = d.objid AND s.relkind = 'S'
    UNION
    SELECT r.name, 'default:' || a.attname
      FROM p7x_rel r
      JOIN pg_attrdef ad ON ad.adrelid = r.oid
      JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
     WHERE pg_get_expr(ad.adbin, ad.adrelid) ILIKE '%nextval(%'
),
p7x_own AS (
    SELECT r.name AS relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
           pg_get_userbyid(c.relowner) AS owner
      FROM p7x_rel r JOIN pg_class c ON c.oid = r.oid
),
xbase AS (
    -- XBASELINE-BUILDER:BEGIN
    SELECT jsonb_build_object(
        'game',                 (SELECT count(*) FROM public.game),
        'game_max_upd_utc',     (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.game),
        'cv_max_created_utc',   (SELECT to_char(max(created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.card_variant),
        'cv_max_upd_utc',       (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.card_variant),
        'job_max_created_utc',  (SELECT to_char(max(created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_job),
        'cvir_max_created_utc', (SELECT to_char(max(created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_row),
        'marker_game',          (SELECT count(*) FROM public.game WHERE strpos(code, 'H2830') > 0 OR strpos(name, 'H2830') > 0),
        'marker_job',           (SELECT count(*) FROM public.catalog_variant_import_job WHERE strpos(external_set_id, 'H2830') > 0),
        'marker_trait_name',    (SELECT count(*) FROM public.card_edition_context_trait WHERE strpos(name, 'H2830') > 0),
        'marker_profile_name',  (SELECT count(*) FROM public.card_edition_context_profile WHERE strpos(name, 'H2830') > 0),
        'marker_mapping_set',   (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE strpos(COALESCE(external_set_id, ''), 'H2830') > 0)
    ) AS x
    -- XBASELINE-BUILDER:END
),
fx AS (
    SELECT (SELECT count(*) FROM (
               SELECT 1 FROM public.card c
                 JOIN public.card_set cs ON cs.id = c.card_set_id
                 JOIN public.expansion e ON e.id = cs.expansion_id
                 JOIN public.card_variant_type t ON t.game_id = e.game_id, gs
                WHERE e.game_id = gs.game_id
                  AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
                LIMIT 1) z) AS free_pair,
           (SELECT count(*) FROM public.card_printing_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS pp_active,
           (SELECT count(*) FROM public.card_edition_context_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS ec_active
),
gates AS (
    SELECT
        ((SELECT count(*) FROM public.game WHERE code = 'POKEMON') = 1
         AND (SELECT count(*) FROM public.asset_source WHERE code = 'TCGDEX') = 1)    AS g_game_source_one,
        ((SELECT count(*) FROM p7x_trg_exp e JOIN p7x_trg t ON t.tgname = e.tgname AND t.relname = e.relname
           WHERE t.tgtype = e.tgtype AND t.enabled = 'O' AND NOT t.is_constraint
             AND t.fn_oid = to_regprocedure(e.fn) AND t.attrs = e.attrs) = 10
         AND (SELECT count(*) FROM p7x_trg) = 10)                                    AS g_p7x_triggers,
        ((SELECT count(*) FROM p7x_fn WHERE exists_fn AND pinned) = 8
         AND (SELECT count(*) FROM p7x_fn) = 8)                                      AS g_p7x_roots_pinned,
        ((SELECT count(*) FROM p7x_fn WHERE cfg = ARRAY['search_path=""']) = 8
         AND NOT EXISTS (SELECT 1 FROM p7x_fn WHERE class IS DISTINCT FROM 'SAFE'))  AS g_p7x_search_path_empty,
        NOT EXISTS (SELECT 1 FROM p7x_rel r JOIN pg_rewrite rw ON rw.ev_class = r.oid
                     WHERE rw.rulename <> '_RETURN')                                  AS g_p7x_no_rules,
        NOT EXISTS (SELECT 1 FROM pg_publication_tables pt JOIN p7x_tbl t ON t.name = pt.tablename
                     WHERE pt.schemaname = 'public')                                  AS g_p7x_no_publication,
        NOT EXISTS (SELECT 1 FROM p7x_seq)                                            AS g_p7x_no_sequence,
        (SELECT count(*) FROM p7x_own WHERE NOT force_rls AND owner = current_user) = 4 AS g_p7x_rls_bypass,
        ((SELECT x->>'marker_game' FROM xbase)::int = 0 AND (SELECT x->>'marker_job' FROM xbase)::int = 0
         AND (SELECT x->>'marker_trait_name' FROM xbase)::int = 0 AND (SELECT x->>'marker_profile_name' FROM xbase)::int = 0
         AND (SELECT x->>'marker_mapping_set' FROM xbase)::int = 0)                  AS g_xmarker_absent_now,
        ((SELECT count(*) FROM public.card_edition_context_trait WHERE strpos(code, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_edition_context_profile WHERE strpos(code, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE strpos(normalized_token, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_printing_external_mapping WHERE strpos(normalized_token, 'H2830') > 0) = 0) AS g_marker_absent_now,
        ((SELECT free_pair FROM fx) = 1 AND (SELECT pp_active FROM fx) >= 1 AND (SELECT ec_active FROM fx) >= 2) AS g_4x_fixture_available,
        (to_regclass('public.uq_card_variant_identity') IS NOT NULL
         AND to_regclass('public.uq_card_variant_card_order') IS NOT NULL
         AND to_regclass('public.uq_card_variant_one_default_per_card') IS NOT NULL)   AS g_4x_objects
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_p7x_triggers',   COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'fn_oid' ORDER BY t.relname, t.tgname) FROM p7x_trg t), '[]'::jsonb),
        'd_p7x_functions',  COALESCE((SELECT jsonb_agg(jsonb_build_object('fn', f.fn::regprocedure::text, 'class', f.class, 'pinned', f.pinned,
                                  'body_md5_lf', f.body_md5_lf, 'proconfig', f.cfg) ORDER BY f.fn::regprocedure::text) FROM p7x_fn f), '[]'::jsonb),
        'd_p7x_search_path', (SELECT jsonb_agg(nsp ORDER BY nsp) FROM p7x_path),
        'd_p7x_ownership_rls', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.relname) FROM p7x_own o), '[]'::jsonb),
        'd_xbaseline',      (SELECT x FROM xbase),
        'd_xbaseline_md5',  (SELECT md5(x::text) FROM xbase),
        'd_4x_fixture',     (SELECT to_jsonb(f) FROM fx f),
        'd_session',        jsonb_build_object(
                                'current_user',       current_user,
                                'server_version_num', current_setting('server_version_num'),
                                'lock_timeout',       current_setting('lock_timeout'),
                                'search_path',        current_setting('search_path'),
                                'backend_pid',        pg_backend_pid(),
                                'checked_at',         clock_timestamp())
    ) AS e08p_precheck
  FROM gates g;
