-- ============================================================================
-- B12 LOCAL PG17 — IMPRESSÃO DIGITAL DE PARIDADE (read-only, SELECT único)
-- ============================================================================
-- Roda IDÊNTICO no LIVE e no container local. A paridade é aceita só se
-- d_fp_core_md5 for igual nos dois lados (ver parity_compare.sql).
-- Escopo: as 22 tabelas carregadas (DATA_TABLES do .ps1) + o fecho de funções
-- alcançado pela 2211/2176/2192/axis_identity_token/guard 2214 e pelos
-- triggers das tabelas do escopo. Nada aqui chama a 2211 (custo baixo no LIVE).
-- Pré-condição de comparação: TimeZone = UTC nos dois lados (reportado em
-- d_env; o conteúdo usa to_jsonb, que depende do TimeZone para timestamptz).
-- ============================================================================
WITH
tbl(name) AS (
    VALUES ('game'),('asset_source'),('expansion'),('card_set'),('card_set_external_reference'),
           ('card_category'),('rarity'),('card'),('card_variant_type'),
           ('card_printing_trait'),('card_printing_profile'),('card_printing_profile_trait'),
           ('card_printing_external_mapping'),('card_printing_external_mapping_trait'),
           ('card_edition_context_trait'),('card_edition_context_profile'),('card_edition_context_profile_trait'),
           ('card_edition_context_external_mapping'),('card_edition_context_external_mapping_trait'),
           ('card_variant'),('catalog_variant_import_job'),('catalog_variant_import_row')
),
rel AS (SELECT t.name, ('public.' || t.name)::regclass AS oid FROM tbl t),
fn_seed(oid) AS (
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname, p.proname) IN (('internal','resolve_variant_row_axes'),('internal','compute_variant_residual_signature'),
                                      ('internal','resolve_variant_mapping_scope'),('internal','axis_identity_token'),
                                      ('internal','guard_cvir_normalized_shape'))
    UNION
    SELECT tg.tgfoid FROM rel r JOIN pg_trigger tg ON tg.tgrelid = r.oid AND NOT tg.tgisinternal
),
fn_walk AS (
    WITH RECURSIVE w(oid, depth) AS (
        SELECT oid, 1 FROM fn_seed
        UNION
        SELECT c.oid, w.depth + 1 FROM w JOIN pg_proc p ON p.oid = w.oid
         CROSS JOIN LATERAL regexp_matches(p.prosrc, '(internal|public|extensions)\.([a-z_0-9]+)\s*\(', 'g') m
         JOIN pg_namespace n ON n.nspname = m[1]
         JOIN pg_proc c ON c.pronamespace = n.oid AND c.proname = m[2]
         WHERE w.depth < 6
    )
    SELECT DISTINCT oid FROM w
),
fn AS (
    SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
           l.lanname AS lang, p.provolatile::text AS vol, p.prosecdef AS secdef, p.proconfig::text[] AS cfg,
           pg_get_function_result(p.oid) AS result,
           CASE WHEN l.lanname IN ('c','internal') THEN p.prosrc
                ELSE md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) END AS body
      FROM fn_walk w JOIN pg_proc p ON p.oid = w.oid
      JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
),
cols AS (
    SELECT r.name, string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull
                              || ':' || COALESCE(pg_get_expr(d.adbin, d.adrelid), '') , ',' ORDER BY a.attnum) AS d
      FROM rel r JOIN pg_attribute a ON a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
     GROUP BY r.name
),
idx AS (SELECT r.name, i.indexrelid::regclass::text AS iname, pg_get_indexdef(i.indexrelid) AS d
          FROM rel r JOIN pg_index i ON i.indrelid = r.oid),
con AS (SELECT r.name, c.conname::text AS cname, c.contype::text || ':' || c.condeferrable || ':' || c.condeferred || ':' || pg_get_constraintdef(c.oid) AS d
          FROM rel r JOIN pg_constraint c ON c.conrelid = r.oid),
trg AS (SELECT r.name, tg.tgname::text AS tname, tg.tgenabled::text || ':' || pg_get_triggerdef(tg.oid) AS d
          FROM rel r JOIN pg_trigger tg ON tg.tgrelid = r.oid AND NOT tg.tgisinternal),
own AS (SELECT r.name, pg_get_userbyid(c.relowner) || ':' || c.relrowsecurity || ':' || c.relforcerowsecurity AS d
          FROM rel r JOIN pg_class c ON c.oid = r.oid),
pol AS (SELECT p.tablename::text AS name, p.policyname::text || ':' || p.cmd || ':' || array_to_string(p.roles, '|')
               || ':' || COALESCE(p.qual, '') || ':' || COALESCE(p.with_check, '') AS d
          FROM pg_policies p JOIN tbl t ON t.name = p.tablename WHERE p.schemaname = 'public'),
-- conteúdo integral por tabela (ordem estável por texto da linha)
content AS (
    SELECT 'game' AS name, count(*) AS n, md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) AS h FROM public.game x
    UNION ALL SELECT 'asset_source', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.asset_source x
    UNION ALL SELECT 'expansion', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.expansion x
    UNION ALL SELECT 'card_set', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_set x
    UNION ALL SELECT 'card_set_external_reference', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_set_external_reference x
    UNION ALL SELECT 'card_category', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_category x
    UNION ALL SELECT 'rarity', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.rarity x
    UNION ALL SELECT 'card', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card x
    UNION ALL SELECT 'card_variant_type', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_variant_type x
    UNION ALL SELECT 'card_printing_trait', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_printing_trait x
    UNION ALL SELECT 'card_printing_profile', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_printing_profile x
    UNION ALL SELECT 'card_printing_profile_trait', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_printing_profile_trait x
    UNION ALL SELECT 'card_printing_external_mapping', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_printing_external_mapping x
    UNION ALL SELECT 'card_printing_external_mapping_trait', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_printing_external_mapping_trait x
    UNION ALL SELECT 'card_edition_context_trait', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_edition_context_trait x
    UNION ALL SELECT 'card_edition_context_profile', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_edition_context_profile x
    UNION ALL SELECT 'card_edition_context_profile_trait', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_edition_context_profile_trait x
    UNION ALL SELECT 'card_edition_context_external_mapping', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_edition_context_external_mapping x
    UNION ALL SELECT 'card_edition_context_external_mapping_trait', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_edition_context_external_mapping_trait x
    UNION ALL SELECT 'card_variant', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.card_variant x
    UNION ALL SELECT 'catalog_variant_import_job', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.catalog_variant_import_job x
    UNION ALL SELECT 'catalog_variant_import_row', count(*), md5(string_agg(md5(to_jsonb(x)::text), '' ORDER BY md5(to_jsonb(x)::text))) FROM public.catalog_variant_import_row x
),
rows_base AS (
    SELECT j.status AS js, r.validation_status AS val, r.persistence_status AS per, r.decision_status AS dec,
           (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND r.persistence_status = 'PENDING') AS op,
           CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                ELSE 'UUID' END AS obs,
           jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
           (jsonb_exists(r.raw_data, 'subtype') OR jsonb_exists(r.raw_data, 'stamp')) AS has_ec_tokens
      FROM public.catalog_variant_import_row r JOIN public.catalog_variant_import_job j ON j.id = r.job_id
),
dist AS (
    SELECT jsonb_build_object(
        'jobs_by_status', (SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) n FROM public.catalog_variant_import_job GROUP BY 1) s),
        'rows_js_val_per_dec', (SELECT jsonb_object_agg(k, n) FROM (SELECT js||'/'||val||'/'||per||'/'||dec AS k, count(*) n FROM rows_base GROUP BY 1) s),
        'ec_key_by_op', (SELECT jsonb_object_agg(k, n) FROM (SELECT op::text||'/'||obs AS k, count(*) n FROM rows_base GROUP BY 1) s),
        'ec_uuid_distinct', (SELECT count(DISTINCT r.normalized_data ->> 'edition_context_profile_id') FROM public.catalog_variant_import_row r
                              WHERE jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string'),
        'cv_ec_nonnull', (SELECT count(*) FROM public.card_variant WHERE edition_context_profile_id IS NOT NULL),
        'cv_pp_nonnull', (SELECT count(*) FROM public.card_variant WHERE printing_profile_id IS NOT NULL),
        -- universos percorridos (predicados de P9B, sem a 2211)
        'u_M1_total', (SELECT count(*) FROM rows_base),
        'u_M1_op', (SELECT count(*) FROM rows_base WHERE op),
        'u_M1_rc_domain', (SELECT count(*) FROM rows_base WHERE op OR obs <> 'ABSENT'),
        'u_M2_domain', (SELECT count(*) FROM rows_base WHERE NOT op AND obs = 'ABSENT'),
        'u_M2_domain_with_ec_tokens', (SELECT count(*) FROM rows_base WHERE NOT op AND obs = 'ABSENT' AND has_ec_tokens),
        'u_M3_rows', (SELECT count(*) FROM rows_base),
        'u_M3_has_key', (SELECT count(*) FROM rows_base WHERE obs <> 'ABSENT'),
        'u_M3_has_pp', (SELECT count(*) FROM rows_base WHERE has_pp)
    ) AS d
),
core AS (
    SELECT jsonb_build_object(
        'pg_major',   current_setting('server_version_num')::int / 10000,
        'functions',  (SELECT jsonb_object_agg(sig, jsonb_build_array(lang, vol, secdef, cfg, result, body)) FROM fn),
        'columns',    (SELECT jsonb_object_agg(name, md5(d)) FROM cols),
        'indexes',    (SELECT jsonb_object_agg(iname, md5(d)) FROM idx),
        'constraints',(SELECT jsonb_object_agg(name || '.' || cname, md5(d)) FROM con),
        'triggers',   (SELECT jsonb_object_agg(name || '.' || tname, md5(d)) FROM trg),
        'ownership',  (SELECT jsonb_object_agg(name, d) FROM own),
        'policies_md5', (SELECT md5(COALESCE(string_agg(name || '|' || d, E'\n' ORDER BY name, d), '')) FROM pol),
        'content',    (SELECT jsonb_object_agg(name, jsonb_build_array(n, h)) FROM content),
        'distribution', (SELECT d FROM dist)
    ) AS c
)
SELECT jsonb_build_object(
    'd_fp_core_md5', md5(c::text),
    'd_fp_core',     c,
    'd_env', jsonb_build_object(
        'server_version',     current_setting('server_version'),
        'server_version_num', current_setting('server_version_num'),
        'timezone',           current_setting('TimeZone'),
        'search_path',        current_setting('search_path'),
        'lock_timeout',       current_setting('lock_timeout'),
        'statement_timeout',  current_setting('statement_timeout'),
        'current_user',       current_user,
        'work_mem',           current_setting('work_mem'),
        'random_page_cost',   current_setting('random_page_cost'),
        'effective_cache_size', current_setting('effective_cache_size'),
        'jit',                current_setting('jit'),
        'max_parallel_workers_per_gather', current_setting('max_parallel_workers_per_gather'),
        'shared_buffers',     current_setting('shared_buffers'),
        'checked_at',         clock_timestamp())
) AS b12_parity_fingerprint
  FROM core;
