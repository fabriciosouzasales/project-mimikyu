-- ============================================================================
-- 2830H · E05P — PRECHECK COMPLEMENTAR DA SEÇÃO 2-QUATER (lote L3, 10 casos)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12-2830-P5-L2-CLOSEOUT-AND-L3-IMPLEMENTATION-01).
--                 Somente SELECT: um único statement, sem DML, sem DDL, sem
--                 set_config, sem TEMP. Execução exige mandato próprio.
-- Ordem ......... roda DEPOIS do E00 (gate_pass = true) e imediatamente ANTES
--                 do E05. O E00 canônico NÃO é alterado.
-- gate_pass ..... TRUE só se TODOS os g_* forem TRUE. Qualquer FALSE ou NULL
--                 = STOP antes do E05. Nenhum gate é ajustado ao estado
--                 observado: divergência = STOP e adjudicação.
-- Pinos ......... md5 do corpo com CRLF→LF (D-6): 5 funções da 2207 e
--                 public.normalize_external_catalog_value (2095) = pinos do E00
--                 e do E04P, este já demonstrado no LIVE em 2026-09-27
--                 (LIVE-L2-E04-EXECUTION-RECORD.md §3).
-- N-3 .......... 2Q.8/2Q.10 usam literais sem marcador (tokens em escopo de
--                 fixture marcado; Set literal 'dp1' com token marcado).
--                 g_n3_normalization prova, pela própria função pinada, que
--                 os literais normalizam como o contrato exige; g_marker_
--                 absent_now prova que nenhum mapping LIVE ocupa escopo ou
--                 token marcado (colisão = STOP). d_n3_live informa quantos
--                 mappings LIVE usam os literais (informativo, sem gate: as
--                 chaves das fixtures são disjuntas por construção).
-- ============================================================================
WITH
tbl(name) AS (
    VALUES ('card_edition_context_trait'),
           ('card_edition_context_external_mapping'),
           ('card_edition_context_external_mapping_trait')
),
rel AS (
    SELECT t.name, to_regclass('public.' || t.name) AS oid FROM tbl t
),
-- ------------------------------------------------------------------------
-- triggers esperados (2207): nome, tabela, tgtype, função, constraint
-- trigger (deferrable + initially deferred) e colunas de UPDATE OF.
-- tgtype: ROW=1, BEFORE=2, INSERT=4, DELETE=8, UPDATE=16.
-- ------------------------------------------------------------------------
trg_exp(tgname, relname, tgtype, fn, is_constraint, attrs) AS (
    VALUES ('trg_cecem_normalize',       'card_edition_context_external_mapping',       7,  'internal.normalize_edition_context_external_mapping()',          false, ARRAY[]::text[]),
           ('trg_cecem_header',          'card_edition_context_external_mapping',       19, 'internal.enforce_edition_context_mapping_header()',              false, ARRAY[]::text[]),
           ('trg_cecem_seal',            'card_edition_context_external_mapping',       5,  'internal.seal_edition_context_external_mapping()',               true,  ARRAY[]::text[]),
           ('trg_cecem_signature_write', 'card_edition_context_external_mapping',       19, 'internal.enforce_edition_context_mapping_signature_write()',     false, ARRAY['traits_signature']),
           ('trg_cecemt_immutable',      'card_edition_context_external_mapping_trait', 31, 'internal.guard_edition_context_mapping_composition_immutable()', false, ARRAY[]::text[])
),
trg AS (
    SELECT tg.tgname::text AS tgname, r.name AS relname, tg.tgtype::int AS tgtype,
           tg.tgenabled::text AS enabled, tg.tgfoid AS fn_oid, tg.tgfoid::regprocedure::text AS fn,
           (tg.tgconstraint <> 0) AS is_constraint, tg.tgdeferrable AS deferrable,
           tg.tginitdeferred AS initdeferred,
           COALESCE((SELECT array_agg(a.attname::text ORDER BY k.ord)
                       FROM unnest(tg.tgattr::int2[]) WITH ORDINALITY AS k(attnum, ord)
                       JOIN pg_attribute a ON a.attrelid = tg.tgrelid AND a.attnum = k.attnum),
                    ARRAY[]::text[]) AS attrs
      FROM rel r JOIN pg_trigger tg ON tg.tgrelid = r.oid AND NOT tg.tgisinternal
),
-- ------------------------------------------------------------------------
-- constraints das 3 tabelas escritas e constraints exigidas (2203, 2207)
-- ------------------------------------------------------------------------
con AS (
    SELECT c.conname::text AS conname, r.name AS relname, c.contype::text AS contype,
           c.convalidated, c.condeferrable, c.condeferred
      FROM rel r JOIN pg_constraint c ON c.conrelid = r.oid
),
con_exp(conname, relname, contype) AS (
    VALUES ('ck_cecem_raw_field',              'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_token_not_blank',        'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_external_set_not_blank', 'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_signature_not_empty',    'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_signature_shape',        'card_edition_context_external_mapping',       'c'),
           ('uq_cecem_id_game',                'card_edition_context_external_mapping',       'u'),
           ('pk_cecemt',                       'card_edition_context_external_mapping_trait', 'p'),
           ('fk_cecemt_mapping',               'card_edition_context_external_mapping_trait', 'f'),
           ('fk_cecemt_trait',                 'card_edition_context_external_mapping_trait', 'f'),
           ('uq_cect_game_code',               'card_edition_context_trait',                  'u'),
           ('uq_cect_game_family_order',       'card_edition_context_trait',                  'u'),
           ('uq_cect_id_game',                 'card_edition_context_trait',                  'u'),
           ('ck_cect_code_format',             'card_edition_context_trait',                  'c'),
           ('ck_cect_family',                  'card_edition_context_trait',                  'c'),
           ('ck_cect_display_order_positive',  'card_edition_context_trait',                  'c')
),
-- índices parciais de lifecycle (2207 v3.0): predicado comparado sem
-- parênteses (a forma deparsada varia só em parênteses)
act_idx(idxname, pred, cols) AS (
    VALUES ('uq_cecem_active_global', 'external_set_id IS NULL AND is_active',
            ARRAY['game_id','asset_source_id','raw_field','normalized_token']),
           ('uq_cecem_active_scoped', 'external_set_id IS NOT NULL AND is_active',
            ARRAY['game_id','asset_source_id','external_set_id','raw_field','normalized_token'])
),
idx AS (
    SELECT e.idxname, i.indrelid, i.indisunique, i.indisvalid, i.indisready,
           regexp_replace(pg_get_expr(i.indpred, i.indrelid), '[()]', '', 'g') AS pred_np,
           e.pred AS pred_exp, e.cols AS cols_exp,
           (SELECT array_agg(a.attname::text ORDER BY k.ord)
              FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
             WHERE k.ord <= i.indnkeyatts) AS cols
      FROM act_idx e
      LEFT JOIN pg_index i ON i.indexrelid = to_regclass('public.' || e.idxname)
),
-- nomes dos dois constraint triggers de selo no schema public (SET
-- CONSTRAINTS age sobre TODAS as correspondências do nome)
seal_con AS (
    SELECT c.conname::text AS conname, c.contype::text AS contype, c.condeferrable, c.condeferred,
           c.conrelid::regclass::text AS relation
      FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
     WHERE n.nspname = 'public' AND c.conname IN ('trg_cecp_seal', 'trg_cecem_seal')
),
-- ------------------------------------------------------------------------
-- funções da 2207: pino md5 (CRLF→LF) = E00 e tokens de erro usados pelo E05
-- ------------------------------------------------------------------------
fn_exp(proname, pin, tokens) AS (
    VALUES ('normalize_edition_context_external_mapping',          '15ea6245b8b8ce2173abb3d6b72c6736', ARRAY['EDITION_CONTEXT_MAPPING_EMPTY_TOKEN:']),
           ('enforce_edition_context_mapping_header',              '9e5fba31721c5e84212bd2116d3fa214', ARRAY['EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:','EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN:']),
           ('seal_edition_context_external_mapping',               '49a4ea4b34ccf06a4efdcf06270c52eb', ARRAY[]::text[]),
           ('guard_edition_context_mapping_composition_immutable', 'ad0c472cfa82c71ee955d9b653755bdc', ARRAY[]::text[]),
           ('enforce_edition_context_mapping_signature_write',     '28084443cf6f32f9336d470ca16b7e72', ARRAY[]::text[])
),
fn AS (
    SELECT e.proname, e.pin, e.tokens, p.oid AS fn_oid, p.prosrc,
           md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) AS body_md5_lf
      FROM fn_exp e
      LEFT JOIN pg_proc p ON p.oid = to_regprocedure('internal.' || e.proname || '()')
),
fn_tok AS (
    SELECT f.proname, t.tok, (strpos(f.prosrc, t.tok) > 0) AS present
      FROM fn f CROSS JOIN LATERAL unnest(f.tokens) AS t(tok)
),
-- ------------------------------------------------------------------------
-- 2095 (normalização do token) e expectativas N-3 do contrato (2Q.8/2Q.9)
-- ------------------------------------------------------------------------
norm_fn AS (
    SELECT p.oid AS fn_oid, l.lanname::text AS lang, p.provolatile::text AS vol, p.prosecdef AS secdef,
           p.proconfig::text[] AS cfg, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) AS body_md5_lf
      FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
     WHERE p.oid = to_regprocedure('public.normalize_external_catalog_value(text)')
),
n3(raw, expected) AS (
    VALUES ('set-logo', 'SET-LOGO'), ('Pokébola', 'POKEBOLA'), ('BLUE  BORDER', 'BLUE BORDER'), ('   ', '')
),
n3_eval AS (
    SELECT n.raw, n.expected, btrim(public.normalize_external_catalog_value(n.raw)) AS got FROM n3 n
),
-- ------------------------------------------------------------------------
-- P6 — sequences das 3 tabelas escritas (OWNED BY / identity ou default
-- nextval); mesmo critério do CTE seq do E00. A N:N é touched_now = false
-- no E00: a prova de ausência de sequence é exigida aqui.
-- ------------------------------------------------------------------------
l3_seq AS (
    SELECT r.name AS relname, s.oid::regclass::text AS sequence_name, 'owned_by' AS link
      FROM rel r
      JOIN pg_depend d ON d.refobjid = r.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('a','i')
      JOIN pg_class s ON s.oid = d.objid AND s.relkind = 'S'
    UNION
    SELECT r.name, NULL, 'default:' || a.attname || '=' || pg_get_expr(ad.adbin, ad.adrelid)
      FROM rel r
      JOIN pg_attrdef ad ON ad.adrelid = r.oid
      JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
     WHERE pg_get_expr(ad.adbin, ad.adrelid) ILIKE '%nextval(%'
),
l3_own AS (
    SELECT r.name AS relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
           pg_get_userbyid(c.relowner) AS owner
      FROM rel r JOIN pg_class c ON c.oid = r.oid
),
mk AS (
    SELECT (SELECT count(*) FROM public.card_edition_context_trait WHERE strpos(code, 'H2830') > 0) AS marker_trait,
           (SELECT count(*) FROM public.card_edition_context_external_mapping
             WHERE strpos(normalized_token, 'H2830') > 0 OR strpos(COALESCE(external_set_id, ''), 'H2830') > 0) AS marker_mapping
),
gates AS (
    SELECT
        (SELECT count(*) FROM public.game WHERE code = 'POKEMON') = 1                 AS g_game_pokemon_one,
        (SELECT count(*) FROM public.asset_source WHERE code = 'TCGDEX') = 1          AS g_source_tcgdex_one,
        ((SELECT count(*) FROM trg_exp e JOIN trg t ON t.tgname = e.tgname AND t.relname = e.relname
           WHERE t.tgtype = e.tgtype AND t.enabled = 'O'
             AND t.fn_oid = to_regprocedure(e.fn)
             AND t.is_constraint = e.is_constraint
             AND t.deferrable = e.is_constraint AND t.initdeferred = e.is_constraint
             AND t.attrs = e.attrs) = 5
         AND (SELECT count(*) FROM trg t JOIN trg_exp e ON e.tgname = t.tgname) = 5)  AS g_l3_triggers,
        NOT EXISTS (SELECT 1 FROM trg t
                     WHERE NOT EXISTS (SELECT 1 FROM trg_exp e
                                        WHERE e.tgname = t.tgname AND e.relname = t.relname)) AS g_no_other_triggers_l3,
        ((SELECT count(*) FROM seal_con WHERE conname = 'trg_cecp_seal') = 1
         AND (SELECT count(*) FROM seal_con WHERE conname = 'trg_cecem_seal') = 1
         AND NOT EXISTS (SELECT 1 FROM seal_con
                          WHERE contype <> 't' OR NOT condeferrable OR NOT condeferred)) AS g_seal_constraint_names_unique,
        (NOT EXISTS (SELECT 1 FROM con
                      WHERE condeferrable
                        AND NOT (conname = 'trg_cecem_seal' AND relname = 'card_edition_context_external_mapping'))
         AND (SELECT count(*) FROM con
               WHERE condeferrable AND conname = 'trg_cecem_seal'
                 AND relname = 'card_edition_context_external_mapping') = 1)          AS g_deferrable_only_seal_l3,
        ((SELECT count(*) FROM con_exp e JOIN con c ON c.conname = e.conname AND c.relname = e.relname
           WHERE c.contype = e.contype AND c.convalidated) = 15
         AND (SELECT count(*) FROM idx
               WHERE indrelid = to_regclass('public.card_edition_context_external_mapping')
                 AND indisunique AND indisvalid AND indisready
                 AND pred_np = pred_exp AND cols = cols_exp) = 2)                     AS g_l3_constraints,
        (SELECT count(*) FROM fn_tok WHERE present) = 3                               AS g_l3_error_tokens,
        (SELECT count(*) FROM fn WHERE fn_oid IS NOT NULL AND body_md5_lf = pin) = 5  AS g_l3_function_pins,
        (SELECT count(*) FROM norm_fn
          WHERE lang = 'sql' AND vol = 's' AND NOT secdef AND cfg = ARRAY['search_path=""']
            AND body_md5_lf = '1fdc2e7ebe2297f8db85be4aad2e5d33') = 1                AS g_normalize_identity,
        (SELECT count(*) FROM n3_eval WHERE got = expected) = 4                       AS g_n3_normalization,
        NOT EXISTS (SELECT 1 FROM l3_seq)                                             AS g_l3_no_sequence,
        (SELECT count(*) FROM l3_own WHERE NOT force_rls AND owner = current_user) = 3 AS g_l3_rls_bypass,
        (SELECT marker_trait = 0 AND marker_mapping = 0 FROM mk)                      AS g_marker_absent_now
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_triggers',       COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'fn_oid' ORDER BY t.relname, t.tgname) FROM trg t), '[]'::jsonb),
        'd_constraints',    COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.relname, c.conname) FROM con c), '[]'::jsonb),
        'd_active_indexes', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'index', x.idxname, 'relation', x.indrelid::regclass::text, 'unique', x.indisunique,
                                  'valid', x.indisvalid, 'ready', x.indisready,
                                  'predicate_np', x.pred_np, 'columns', x.cols) ORDER BY x.idxname) FROM idx x), '[]'::jsonb),
        'd_seal_constraints', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.conname, s.relation) FROM seal_con s), '[]'::jsonb),
        'd_function_pins',  COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'fn', 'internal.' || f.proname || '()', 'resolved', f.fn_oid IS NOT NULL,
                                  'body_md5_lf', f.body_md5_lf, 'pin', f.pin) ORDER BY f.proname) FROM fn f), '[]'::jsonb),
        'd_error_tokens',   COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.proname, t.tok) FROM fn_tok t), '[]'::jsonb),
        'd_normalize_identity', COALESCE((SELECT jsonb_agg(to_jsonb(f) - 'fn_oid') FROM norm_fn f), '[]'::jsonb),
        'd_n3_normalization', COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.raw) FROM n3_eval e), '[]'::jsonb),
        'd_n3_live',        (SELECT jsonb_build_object(
                                'literal_tokens', (SELECT count(*) FROM public.card_edition_context_external_mapping
                                                    WHERE normalized_token IN ('SET-LOGO','POKEBOLA','BLUE BORDER')),
                                'set_dp1',        (SELECT count(*) FROM public.card_edition_context_external_mapping
                                                    WHERE external_set_id = 'dp1'))),
        'd_l3_sequences',   COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM l3_seq s), '[]'::jsonb),
        'd_l3_ownership_rls', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.relname) FROM l3_own o), '[]'::jsonb),
        'd_marker_counts',  (SELECT to_jsonb(m) FROM mk m),
        'd_session',        jsonb_build_object(
                                'current_user',       current_user,
                                'server_version_num', current_setting('server_version_num'),
                                'lock_timeout',       current_setting('lock_timeout'),
                                'backend_pid',        pg_backend_pid(),
                                'checked_at',         clock_timestamp())
    ) AS e05p_precheck
  FROM gates g;
