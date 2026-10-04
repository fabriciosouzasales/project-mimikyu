-- ============================================================================
-- P14A_FINGERPRINT.sql - impressao digital estrutural P14(a) (2830 v7.0)
-- Mandato: BATCH12-PHASE6-CN1-4-P14A-FINGERPRINT-READINESS-01
-- Status: PREPARADA - NAO EXECUTADA. Roda VERBATIM no CN1 e no LIVE.
--
-- Contrato:
--   * um unico SELECT (CTEs + UNION ALL); sem SET/set_config, sem DDL/DML,
--     sem temp table, sem lock explicito, sem funcao com efeito de escrita;
--   * nenhum OID e emitido nem usado como identidade comparavel;
--   * saida por objeto (linhas ITEM), uma linha CONTEXT (nao comparavel por
--     hash; precondicao de comparacao) e duas linhas AGGREGATE derivadas das
--     linhas ITEM canonicas (RAW e LF);
--   * md5_raw = md5 da definicao como o catalogo a devolve (flags estruturais
--     ficam na coluna flags e entram nos agregados, nao no md5 da definicao);
--     md5_lf  = md5 apos CRLF -> LF (somente o par; CR isolado preservado);
--   * escopo FECHADO = manifesto CN1-4-P14A-MANIFEST-01 (ver relatorio):
--       6 funcoes; indices UNIQUE de card_variant e catalog_variant_import_row
--       (+4 legados que devem estar AUSENTES); constraints p/u/x dessas duas
--       tabelas; triggers nao internos de card_variant, catalog_variant_import_row,
--       catalog_variant_import_job e catalog_admin_action_log. Objeto do mesmo
--       tipo nessas tabelas fora do manifesto aparece como EXTRA.
--
-- Colunas: row_kind, sort_key, obj_type, obj_schema, obj_table, obj_name,
--          obj_signature, provenance, expectation, found_count, status,
--          md5_raw, md5_lf, def_bytes, has_cr, flags, definition
-- status: PRESENT | MISSING | DUPLICATE | ABSENT_OK | UNEXPECTED_PRESENT | EXTRA
-- ============================================================================
WITH
exp_fn (ord, fn_schema, fn_name, fn_args, prov) AS (
  VALUES
    (1, 'public',   'admin_confirm_catalog_variant_import',              'uuid, uuid[]',                                  '2218 exec blob 6f4dbd9c'),
    (2, 'internal', 'write_card_variant',                                'text, uuid, uuid, uuid, integer, uuid, uuid',   '2217 exec blob c9abf5d7; 2223 exec blob 72ba009e (drop 6 args)'),
    (3, 'internal', 'guard_cvir_normalized_shape',                       '',                                              '2214 exec blob 30e19523'),
    (4, 'internal', 'enforce_card_variant_edition_context_profile_game', '',                                              '2224 exec blob 5bae844b'),
    (5, 'internal', 'axis_identity_token',                               'jsonb, text',                                   '2210 (ref 2216 C1-BIS)'),
    (6, 'internal', 'resolve_variant_row_axes',                          'jsonb, uuid, uuid, text',                       '2211')
),
fn_cat AS (
  SELECT n.nspname, p.proname, pg_catalog.oidvectortypes(p.proargtypes) AS args, p.oid AS poid
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE (n.nspname, p.proname) IN (SELECT fn_schema, fn_name FROM exp_fn)
),
fn_items AS (
  SELECT 10 * 1000 + e.ord AS sk, 'FUNCTION'::text AS obj_type, e.fn_schema AS obj_schema, ''::text AS obj_table,
         e.fn_name AS obj_name, e.fn_args AS obj_signature, e.prov AS provenance, 'PRESENT'::text AS expectation,
         (SELECT count(*) FROM fn_cat c WHERE c.nspname = e.fn_schema AND c.proname = e.fn_name) AS n_name,
         (SELECT count(*) FROM fn_cat c WHERE c.nspname = e.fn_schema AND c.proname = e.fn_name AND c.args = e.fn_args) AS n_exact,
         (SELECT pg_catalog.pg_get_functiondef(c.poid) FROM fn_cat c
           WHERE c.nspname = e.fn_schema AND c.proname = e.fn_name AND c.args = e.fn_args) AS def,
         ''::text AS flags
    FROM exp_fn e
),
exp_ix (ord, ix_table, ix_name, expectation, prov) AS (
  VALUES
    (1,  'card_variant',               'card_variant_pkey',                     'PRESENT', 'dump 28/09 (PK)'),
    (2,  'card_variant',               'uq_card_variant_card_order',            'PRESENT', '2215 retido (POST gate)'),
    (3,  'card_variant',               'uq_card_variant_id_card',               'PRESENT', '2215 retido (POST gate)'),
    (4,  'card_variant',               'uq_card_variant_identity',              'PRESENT', '2209 exec blob 39084850'),
    (5,  'card_variant',               'uq_card_variant_one_default_per_card',  'PRESENT', '2215 retido (POST gate)'),
    (6,  'catalog_variant_import_row', 'catalog_variant_import_row_pkey',       'PRESENT', 'dump 28/09 (PK); 2216 retido'),
    (7,  'catalog_variant_import_row', 'uq_cvir_row_identity',                  'PRESENT', '2210; 2216 C1/C1-BIS exec blob 3fc30f42'),
    (8,  'card_variant',               'uq_card_variant_card_type_no_printing', 'ABSENT',  '2215 exec blob 426b3555 (DROP)'),
    (9,  'card_variant',               'uq_card_variant_card_type_printing',    'ABSENT',  '2215 exec blob 426b3555 (DROP)'),
    (10, 'catalog_variant_import_row', 'uq_cvir_job_card_type_no_printing',     'ABSENT',  '2216 exec blob 3fc30f42 (DROP)'),
    (11, 'catalog_variant_import_row', 'uq_cvir_job_card_type_printing',        'ABSENT',  '2216 exec blob 3fc30f42 (DROP)')
),
ix_cat AS (
  SELECT ct.relname AS tbl, ci.relname AS ixname,
         'unique=' || i.indisunique::text || ' primary=' || i.indisprimary::text || ' valid=' || i.indisvalid::text
           || ' ready=' || i.indisready::text || ' immediate=' || i.indimmediate::text
           || ' nulls_not_distinct=' || i.indnullsnotdistinct::text AS flags,
         pg_catalog.pg_get_indexdef(i.indexrelid) AS def
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ci ON ci.oid = i.indexrelid
    JOIN pg_catalog.pg_class ct ON ct.oid = i.indrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = ci.relnamespace
   WHERE n.nspname = 'public'
     AND (ci.relname IN (SELECT ix_name FROM exp_ix)
          OR (ct.relname IN ('card_variant', 'catalog_variant_import_row') AND i.indisunique))
),
ix_items AS (
  SELECT 20 * 1000 + e.ord AS sk, 'INDEX'::text AS obj_type, 'public'::text AS obj_schema, e.ix_table AS obj_table,
         e.ix_name AS obj_name, ''::text AS obj_signature, e.prov AS provenance, e.expectation,
         (SELECT count(*) FROM ix_cat c WHERE c.ixname = e.ix_name) AS n_name,
         (SELECT count(*) FROM ix_cat c WHERE c.ixname = e.ix_name AND c.tbl = e.ix_table) AS n_exact,
         (SELECT c.def FROM ix_cat c WHERE c.ixname = e.ix_name AND c.tbl = e.ix_table) AS def,
         coalesce((SELECT c.flags FROM ix_cat c WHERE c.ixname = e.ix_name AND c.tbl = e.ix_table), '') AS flags
    FROM exp_ix e
  UNION ALL
  SELECT 29 * 1000 + (row_number() OVER (ORDER BY c.tbl, c.ixname))::int, 'INDEX', 'public', c.tbl, c.ixname, '',
         'fora do manifesto', 'NONE', 1, 1, c.def, c.flags
    FROM ix_cat c
   WHERE NOT EXISTS (SELECT 1 FROM exp_ix e WHERE e.ix_name = c.ixname)
),
exp_con (ord, con_table, con_name, prov) AS (
  VALUES
    (1, 'card_variant',               'card_variant_pkey',               'dump 28/09 (PK)'),
    (2, 'card_variant',               'uq_card_variant_card_order',      'dump 28/09; 2215 retido'),
    (3, 'card_variant',               'uq_card_variant_id_card',         'dump 28/09; 2215 retido'),
    (4, 'card_variant',               'uq_card_variant_identity',        '2209 exec blob 39084850 (ADD CONSTRAINT ... USING INDEX)'),
    (5, 'catalog_variant_import_row', 'catalog_variant_import_row_pkey', 'dump 28/09 (PK)')
),
con_cat AS (
  SELECT ct.relname AS tbl, k.conname,
         'type=' || k.contype::text || ' deferrable=' || k.condeferrable::text || ' deferred=' || k.condeferred::text
           || ' validated=' || k.convalidated::text || ' index=' || coalesce(ci.relname::text, '') AS flags,
         pg_catalog.pg_get_constraintdef(k.oid) AS def
    FROM pg_catalog.pg_constraint k
    JOIN pg_catalog.pg_class ct ON ct.oid = k.conrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = ct.relnamespace
    LEFT JOIN pg_catalog.pg_class ci ON ci.oid = k.conindid
   WHERE n.nspname = 'public'
     AND ct.relname IN ('card_variant', 'catalog_variant_import_row')
     AND (k.contype IN ('p', 'u', 'x') OR k.conname IN (SELECT con_name FROM exp_con))
),
con_items AS (
  SELECT 30 * 1000 + e.ord AS sk, 'CONSTRAINT'::text AS obj_type, 'public'::text AS obj_schema, e.con_table AS obj_table,
         e.con_name AS obj_name, ''::text AS obj_signature, e.prov AS provenance, 'PRESENT'::text AS expectation,
         (SELECT count(*) FROM con_cat c WHERE c.conname = e.con_name AND c.tbl = e.con_table) AS n_name,
         (SELECT count(*) FROM con_cat c WHERE c.conname = e.con_name AND c.tbl = e.con_table) AS n_exact,
         (SELECT min(c.def) FROM con_cat c WHERE c.conname = e.con_name AND c.tbl = e.con_table) AS def,
         coalesce((SELECT min(c.flags) FROM con_cat c WHERE c.conname = e.con_name AND c.tbl = e.con_table), '') AS flags
    FROM exp_con e
  UNION ALL
  SELECT 39 * 1000 + (row_number() OVER (ORDER BY c.tbl, c.conname))::int, 'CONSTRAINT', 'public', c.tbl, c.conname, '',
         'fora do manifesto', 'NONE', 1, 1, c.def, c.flags
    FROM con_cat c
   WHERE NOT EXISTS (SELECT 1 FROM exp_con e WHERE e.con_name = c.conname AND e.con_table = c.tbl)
),
exp_trg (ord, trg_table, trg_name, prov) AS (
  VALUES
    (1, 'card_variant',               'trg_card_variant_edition_context_profile_game', '2224 exec blob 5bae844b'),
    (2, 'card_variant',               'trg_card_variant_printing_profile_game',        'dump 28/09'),
    (3, 'card_variant',               'trg_card_variant_set_updated_at',               'dump 28/09'),
    (4, 'card_variant',               'trg_card_variant_validate_game_consistency',    'dump 28/09'),
    (5, 'catalog_variant_import_job', 'trg_catalog_variant_import_job_normalize',      'dump 28/09'),
    (6, 'catalog_variant_import_job', 'trg_catalog_variant_import_job_set_updated_at', 'dump 28/09'),
    (7, 'catalog_variant_import_row', 'trg_catalog_variant_import_row_normalize',      'dump 28/09'),
    (8, 'catalog_variant_import_row', 'trg_catalog_variant_import_row_set_updated_at', 'dump 28/09'),
    (9, 'catalog_variant_import_row', 'trg_cvir_normalized_shape',                     '2214 exec blob 30e19523')
),
trg_cat AS (
  SELECT ct.relname AS tbl, t.tgname,
         'enabled=' || t.tgenabled::text || ' function=' || t.tgfoid::regprocedure::text AS flags,
         pg_catalog.pg_get_triggerdef(t.oid, false) AS def
    FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class ct ON ct.oid = t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = ct.relnamespace
   WHERE n.nspname = 'public'
     AND ct.relname IN ('card_variant', 'catalog_variant_import_row', 'catalog_variant_import_job', 'catalog_admin_action_log')
     AND NOT t.tgisinternal
),
trg_items AS (
  SELECT 40 * 1000 + e.ord AS sk, 'TRIGGER'::text AS obj_type, 'public'::text AS obj_schema, e.trg_table AS obj_table,
         e.trg_name AS obj_name, ''::text AS obj_signature, e.prov AS provenance, 'PRESENT'::text AS expectation,
         (SELECT count(*) FROM trg_cat c WHERE c.tgname = e.trg_name AND c.tbl = e.trg_table) AS n_name,
         (SELECT count(*) FROM trg_cat c WHERE c.tgname = e.trg_name AND c.tbl = e.trg_table) AS n_exact,
         (SELECT min(c.def) FROM trg_cat c WHERE c.tgname = e.trg_name AND c.tbl = e.trg_table) AS def,
         coalesce((SELECT min(c.flags) FROM trg_cat c WHERE c.tgname = e.trg_name AND c.tbl = e.trg_table), '') AS flags
    FROM exp_trg e
  UNION ALL
  SELECT 49 * 1000 + (row_number() OVER (ORDER BY c.tbl, c.tgname))::int, 'TRIGGER', 'public', c.tbl, c.tgname, '',
         'fora do manifesto', 'NONE', 1, 1, c.def, c.flags
    FROM trg_cat c
   WHERE NOT EXISTS (SELECT 1 FROM exp_trg e WHERE e.trg_name = c.tgname AND e.trg_table = c.tbl)
),
all_items AS (
  SELECT * FROM fn_items
  UNION ALL SELECT * FROM ix_items
  UNION ALL SELECT * FROM con_items
  UNION ALL SELECT * FROM trg_items
),
items AS (
  SELECT a.sk, a.obj_type, a.obj_schema, a.obj_table, a.obj_name, a.obj_signature, a.provenance, a.expectation,
         a.n_exact AS found_count,
         CASE
           WHEN a.expectation = 'NONE'                          THEN 'EXTRA'
           WHEN a.expectation = 'ABSENT' AND a.n_name = 0       THEN 'ABSENT_OK'
           WHEN a.expectation = 'ABSENT'                        THEN 'UNEXPECTED_PRESENT'
           WHEN a.n_exact = 0                                   THEN 'MISSING'
           WHEN a.n_name > 1 OR a.n_exact > 1                   THEN 'DUPLICATE'
           ELSE 'PRESENT'
         END AS status,
         CASE WHEN a.def IS NULL THEN '' ELSE md5(a.def) END AS md5_raw,
         CASE WHEN a.def IS NULL THEN '' ELSE md5(replace(a.def, E'\r\n', E'\n')) END AS md5_lf,
         coalesce(octet_length(a.def), 0) AS def_bytes,
         coalesce(strpos(a.def, E'\r') > 0, false) AS has_cr,
         a.flags,
         CASE WHEN a.obj_type = 'FUNCTION' THEN '' ELSE coalesce(a.def, '') END AS definition
    FROM all_items a
),
agg AS (
  SELECT md5(string_agg(concat_ws('|', i.obj_type, i.obj_schema, i.obj_table, i.obj_name, i.obj_signature,
                                  i.expectation, i.found_count::text, i.status, i.flags, i.md5_raw), E'\n'
                        ORDER BY i.sk, i.obj_table, i.obj_name)) AS agg_raw,
         md5(string_agg(concat_ws('|', i.obj_type, i.obj_schema, i.obj_table, i.obj_name, i.obj_signature,
                                  i.expectation, i.found_count::text, i.status, i.flags, i.md5_lf), E'\n'
                        ORDER BY i.sk, i.obj_table, i.obj_name)) AS agg_lf,
         count(*) AS n_items
    FROM items i
)
SELECT 'ITEM' AS row_kind, i.sk AS sort_key, i.obj_type, i.obj_schema, i.obj_table, i.obj_name, i.obj_signature,
       i.provenance, i.expectation, i.found_count::text AS found_count, i.status, i.md5_raw, i.md5_lf,
       i.def_bytes::text AS def_bytes, i.has_cr::text AS has_cr, i.flags, i.definition
  FROM items i
UNION ALL
SELECT 'CONTEXT', 90001, 'CONTEXT', '', '', 'session', '', 'nao comparavel por hash; precondicao de comparacao', '', '', 'INFO',
       '', '', '', '', 'search_path=' || current_setting('search_path'), 'server_version_num=' || current_setting('server_version_num')
UNION ALL
SELECT 'AGGREGATE', 90002, 'AGGREGATE', '', '', 'agg_raw', '', 'md5 das linhas ITEM canonicas (md5_raw)', '', g.n_items::text, 'INFO',
       g.agg_raw, '', '', '', '', ''
  FROM agg g
UNION ALL
SELECT 'AGGREGATE', 90003, 'AGGREGATE', '', '', 'agg_lf', '', 'md5 das linhas ITEM canonicas (md5_lf)', '', g.n_items::text, 'INFO',
       '', g.agg_lf, '', '', '', ''
  FROM agg g
ORDER BY 2, 5, 6;
