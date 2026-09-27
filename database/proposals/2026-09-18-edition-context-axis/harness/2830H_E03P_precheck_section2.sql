-- ============================================================================
-- 2830H · E03P — PRECHECK COMPLEMENTAR DA SEÇÃO 2 (lote L1, 13 casos)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12-2830-P5-L1-E03-IMPLEMENTATION-01).
--                 Somente SELECT: um único statement, sem DML, sem DDL, sem
--                 set_config, sem TEMP. Execução exige mandato próprio.
-- Contrato ...... L1-E03-IMPLEMENTATION-READINESS.md v1.1 (blob 220fbd8b…),
--                 §5: 11 gates g_* + gate_pass. O E00 canônico NÃO é alterado:
--                 este SELECT roda DEPOIS do E00 (gate_pass = true) e
--                 imediatamente ANTES do E03 (protocolo S4 → S5).
-- gate_pass ..... TRUE só se TODOS os g_* forem TRUE. Qualquer FALSE ou NULL
--                 = STOP antes do E03. Nenhum gate é ajustado ao estado
--                 observado: divergência = STOP e adjudicação.
-- Pinos ......... md5 do corpo com CRLF→LF das 4 funções da 2206 v2.0 (blob
--                 2fcd4d74…), iguais aos pinos do E00 (p7_allowlist) e
--                 recalculados pelo tools/static_check.py a partir da 2206.
-- ============================================================================
WITH
tbl(name) AS (
    VALUES ('card_edition_context_trait'),
           ('card_edition_context_profile'),
           ('card_edition_context_profile_trait')
),
rel AS (
    SELECT t.name, to_regclass('public.' || t.name) AS oid FROM tbl t
),
-- ------------------------------------------------------------------------
-- triggers esperados (readiness §5, g_s2_triggers): nome, tabela, tgtype,
-- função, constraint trigger (deferrable + initially deferred) e colunas
-- de UPDATE OF. tgtype: ROW=1, BEFORE=2, INSERT=4, DELETE=8, UPDATE=16.
-- ------------------------------------------------------------------------
trg_exp(tgname, relname, tgtype, fn, is_constraint, attrs) AS (
    VALUES ('trg_cecp_seal',            'card_edition_context_profile',       5,  'internal.seal_edition_context_composition()',            true,  ARRAY[]::text[]),
           ('trg_cecp_signature_write', 'card_edition_context_profile',       19, 'internal.enforce_edition_context_signature_write()',     false, ARRAY['traits_signature']),
           ('trg_cecpt_immutable',      'card_edition_context_profile_trait', 31, 'internal.guard_edition_context_composition_immutable()', false, ARRAY[]::text[]),
           ('trg_cecpt_trait_active',   'card_edition_context_profile_trait', 7,  'internal.guard_edition_context_trait_active()',          false, ARRAY[]::text[])
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
-- constraints das 3 tabelas escritas e constraints exigidas (§5)
-- ------------------------------------------------------------------------
con AS (
    SELECT c.conname::text AS conname, r.name AS relname, c.contype::text AS contype,
           c.convalidated, c.condeferrable, c.condeferred
      FROM rel r JOIN pg_constraint c ON c.conrelid = r.oid
),
con_exp(conname, relname, contype) AS (
    VALUES ('pk_cecpt',                    'card_edition_context_profile_trait', 'p'),
           ('fk_cecpt_profile',            'card_edition_context_profile_trait', 'f'),
           ('fk_cecpt_trait',              'card_edition_context_profile_trait', 'f'),
           ('uq_cecp_game_code',           'card_edition_context_profile',       'u'),
           ('uq_cecp_game_order',          'card_edition_context_profile',       'u'),
           ('uq_cect_game_code',           'card_edition_context_trait',         'u'),
           ('uq_cect_game_family_order',   'card_edition_context_trait',         'u'),
           ('ck_cecp_signature_not_empty', 'card_edition_context_profile',       'c'),
           ('ck_cecp_signature_shape',     'card_edition_context_profile',       'c'),
           ('ck_cect_code_format',         'card_edition_context_trait',         'c'),
           ('ck_cecp_code_format',         'card_edition_context_profile',       'c')
),
sig_idx AS (
    SELECT i.indrelid, i.indisunique, i.indisvalid, i.indisready,
           pg_get_expr(i.indpred, i.indrelid) AS pred,
           (SELECT array_agg(a.attname::text ORDER BY k.ord)
              FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
             WHERE k.ord <= i.indnkeyatts) AS cols
      FROM pg_index i
     WHERE i.indexrelid = to_regclass('public.uq_cecp_game_signature')
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
-- funções da 2206: pino md5 (CRLF→LF) e tokens de erro por função (§1.2)
-- ------------------------------------------------------------------------
fn_exp(proname, pin, tokens) AS (
    VALUES ('seal_edition_context_composition',            '6077409ac2b5de7f788076e3b4b3f0c0', ARRAY['EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:']),
           ('guard_edition_context_composition_immutable', 'cfdcb500bb1090cd44c0e73d94c3f72e', ARRAY['EDITION_CONTEXT_COMPOSITION_IMMUTABLE:']),
           ('enforce_edition_context_signature_write',     'caa2e4d40d8e4995e217d7284f9d6c3b', ARRAY['EDITION_CONTEXT_SIGNATURE_MISMATCH:','EDITION_CONTEXT_SIGNATURE_IMMUTABLE:']),
           ('guard_edition_context_trait_active',          '68fb05f1c23db63a59611b0a12f79edd', ARRAY['EDITION_CONTEXT_TRAIT_INACTIVE:'])
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
-- P6 — sequences da N:N (OWNED BY / identity ou default nextval); mesmo
-- critério do CTE seq do E00, restrito à tabela que o E00 marca
-- touched_now = false
-- ------------------------------------------------------------------------
nn AS (
    SELECT to_regclass('public.card_edition_context_profile_trait') AS oid
),
nn_seq AS (
    SELECT s.oid::regclass::text AS sequence_name, 'owned_by' AS link
      FROM nn
      JOIN pg_depend d ON d.refobjid = nn.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('a','i')
      JOIN pg_class s ON s.oid = d.objid AND s.relkind = 'S'
    UNION
    SELECT NULL, 'default:' || a.attname || '=' || pg_get_expr(ad.adbin, ad.adrelid)
      FROM nn
      JOIN pg_attrdef ad ON ad.adrelid = nn.oid
      JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
     WHERE pg_get_expr(ad.adbin, ad.adrelid) ILIKE '%nextval(%'
),
nn_own AS (
    SELECT c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
           pg_get_userbyid(c.relowner) AS owner
      FROM nn JOIN pg_class c ON c.oid = nn.oid
),
mk AS (
    SELECT (SELECT count(*) FROM public.card_edition_context_trait   WHERE code LIKE '%H2830%') AS marker_trait,
           (SELECT count(*) FROM public.card_edition_context_profile WHERE code LIKE '%H2830%') AS marker_profile
),
gates AS (
    SELECT
        (SELECT count(*) FROM public.game WHERE code = 'POKEMON') = 1                 AS g_game_pokemon_one,
        ((SELECT count(*) FROM trg_exp e JOIN trg t ON t.tgname = e.tgname AND t.relname = e.relname
           WHERE t.tgtype = e.tgtype AND t.enabled = 'O'
             AND t.fn_oid = to_regprocedure(e.fn)
             AND t.is_constraint = e.is_constraint
             AND t.deferrable = e.is_constraint AND t.initdeferred = e.is_constraint
             AND t.attrs = e.attrs) = 4
         AND (SELECT count(*) FROM trg t JOIN trg_exp e ON e.tgname = t.tgname) = 4)  AS g_s2_triggers,
        NOT EXISTS (SELECT 1 FROM trg t
                     WHERE NOT EXISTS (SELECT 1 FROM trg_exp e
                                        WHERE e.tgname = t.tgname AND e.relname = t.relname)) AS g_no_other_triggers_l1,
        ((SELECT count(*) FROM seal_con WHERE conname = 'trg_cecp_seal') = 1
         AND (SELECT count(*) FROM seal_con WHERE conname = 'trg_cecem_seal') = 1
         AND NOT EXISTS (SELECT 1 FROM seal_con
                          WHERE contype <> 't' OR NOT condeferrable OR NOT condeferred)) AS g_seal_constraint_names_unique,
        (NOT EXISTS (SELECT 1 FROM con
                      WHERE condeferrable
                        AND NOT (conname = 'trg_cecp_seal' AND relname = 'card_edition_context_profile'))
         AND (SELECT count(*) FROM con
               WHERE condeferrable AND conname = 'trg_cecp_seal'
                 AND relname = 'card_edition_context_profile') = 1)                   AS g_deferrable_only_seal,
        ((SELECT count(*) FROM con_exp e JOIN con c ON c.conname = e.conname AND c.relname = e.relname
           WHERE c.contype = e.contype AND c.convalidated) = 11
         AND (SELECT count(*) FROM sig_idx
               WHERE indrelid = to_regclass('public.card_edition_context_profile')
                 AND indisunique AND indisvalid AND indisready
                 AND pred = '(traits_signature IS NOT NULL)'
                 AND cols = ARRAY['game_id','traits_signature']) = 1)                 AS g_s2_constraints,
        (SELECT count(*) FROM fn_tok WHERE present) = 5                               AS g_s2_error_tokens,
        (SELECT count(*) FROM fn WHERE fn_oid IS NOT NULL AND body_md5_lf = pin) = 4  AS g_s2_function_pins,
        NOT EXISTS (SELECT 1 FROM nn_seq)                                             AS g_nn_no_sequence,
        (SELECT count(*) FROM nn_own WHERE NOT force_rls AND owner = current_user) = 1 AS g_nn_rls_bypass,
        (SELECT marker_trait = 0 AND marker_profile = 0 FROM mk)                      AS g_marker_absent_now
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_triggers',       COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'fn_oid' ORDER BY t.relname, t.tgname) FROM trg t), '[]'::jsonb),
        'd_constraints',    COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.relname, c.conname) FROM con c), '[]'::jsonb),
        'd_signature_index', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'relation', s.indrelid::regclass::text, 'unique', s.indisunique,
                                  'valid', s.indisvalid, 'ready', s.indisready,
                                  'predicate', s.pred, 'columns', s.cols)) FROM sig_idx s), '[]'::jsonb),
        'd_seal_constraints', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.conname, s.relation) FROM seal_con s), '[]'::jsonb),
        'd_function_pins',  COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'fn', 'internal.' || f.proname || '()', 'resolved', f.fn_oid IS NOT NULL,
                                  'body_md5_lf', f.body_md5_lf, 'pin', f.pin) ORDER BY f.proname) FROM fn f), '[]'::jsonb),
        'd_error_tokens',   COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.proname, t.tok) FROM fn_tok t), '[]'::jsonb),
        'd_nn_sequences',   COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM nn_seq s), '[]'::jsonb),
        'd_nn_ownership_rls', COALESCE((SELECT jsonb_agg(to_jsonb(o)) FROM nn_own o), '[]'::jsonb),
        'd_marker_counts',  (SELECT to_jsonb(m) FROM mk m),
        'd_session',        jsonb_build_object(
                                'current_user',       current_user,
                                'server_version_num', current_setting('server_version_num'),
                                'lock_timeout',       current_setting('lock_timeout'),
                                'backend_pid',        pg_backend_pid(),
                                'checked_at',         clock_timestamp())
    ) AS e03p_precheck
  FROM gates g;
