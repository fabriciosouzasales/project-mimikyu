# Blocos compartilhados dos prechecks do Batch 12 (L5–L13). Cada bloco existe
# UMA vez aqui e é emitido byte a byte em todo precheck que o usa; o
# static_check prova a identidade das cópias (mesma disciplina do
# BASELINE-BUILDER do E00/E99).

# ---------------------------------------------------------------------------
# P7X — fecho de triggers/dependências das 4 tabelas fora do gate_scope do E00
# (game, card_variant, catalog_variant_import_job, catalog_variant_import_row).
# Identidade FAIL-CLOSED por função: assinatura, linguagem, SECURITY DEFINER,
# volatilidade, proconfig EXATO e md5 do corpo com CRLF→LF. Os 8 pinos são os
# md5 LF medidos no LIVE pelo E00 desta sessão (d_p7_functions) e são IGUAIS
# ao md5 LF do corpo no repositório (provado pelo static_check). Corpos
# auditados: só builtins de pg_catalog, tabelas sempre qualificadas, nenhum
# efeito externo, nenhum DDL, nenhuma escrita fora da própria linha (NEW).
# D-P7X (BATCH12 — INTEGRATED TECHNICAL RESOLUTION): as 8 raízes TÊM de ter
# proconfig exatamente {search_path=""}. Não existe mais classe admitida por
# mitigação: set_updated_at, validate_card_variant_game_consistency e as duas
# normalize_* (inseguras pelo E00) só passam depois da Query 2234 (proposta,
# não executada). Até lá, E07P/E08P/E09P/E13P/E14P falham em
# g_p7x_roots_pinned e g_p7x_search_path_empty — fail-closed.
# ---------------------------------------------------------------------------
P7X = """p7x_tbl(name) AS (
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
),"""

P7X_GATES = """        ((SELECT count(*) FROM p7x_trg_exp e JOIN p7x_trg t ON t.tgname = e.tgname AND t.relname = e.relname
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
        (SELECT count(*) FROM p7x_own WHERE NOT force_rls AND owner = current_user) = 4 AS g_p7x_rls_bypass,"""

P7X_DETAIL = """        'd_p7x_triggers',   COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'fn_oid' ORDER BY t.relname, t.tgname) FROM p7x_trg t), '[]'::jsonb),
        'd_p7x_functions',  COALESCE((SELECT jsonb_agg(jsonb_build_object('fn', f.fn::regprocedure::text, 'class', f.class, 'pinned', f.pinned,
                                  'body_md5_lf', f.body_md5_lf, 'proconfig', f.cfg) ORDER BY f.fn::regprocedure::text) FROM p7x_fn f), '[]'::jsonb),
        'd_p7x_search_path', (SELECT jsonb_agg(nsp ORDER BY nsp) FROM p7x_path),
        'd_p7x_ownership_rls', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.relname) FROM p7x_own o), '[]'::jsonb),"""

P7X_GATE_NAMES = ['g_p7x_triggers', 'g_p7x_roots_pinned', 'g_p7x_search_path_empty', 'g_p7x_no_rules',
                  'g_p7x_no_publication', 'g_p7x_no_sequence', 'g_p7x_rls_bypass']

# ---------------------------------------------------------------------------
# XBASELINE-BUILDER — baseline COMPLEMENTAR ao do E00 (bloco idêntico nos
# prechecks de lote e no E98). Cobre o que o E99 não cobre: `game`, datas de
# criação de card_variant/job/row e o marcador nos campos textuais usados
# pelas fixtures fora de trait.code/profile.code/mapping.normalized_token.
# ---------------------------------------------------------------------------
XBASE = """xbase AS (
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
),"""

XBASE_GATE = """        ((SELECT x->>'marker_game' FROM xbase)::int = 0 AND (SELECT x->>'marker_job' FROM xbase)::int = 0
         AND (SELECT x->>'marker_trait_name' FROM xbase)::int = 0 AND (SELECT x->>'marker_profile_name' FROM xbase)::int = 0
         AND (SELECT x->>'marker_mapping_set' FROM xbase)::int = 0)                  AS g_xmarker_absent_now,"""

XBASE_DETAIL = """        'd_xbaseline',      (SELECT x FROM xbase),
        'd_xbaseline_md5',  (SELECT md5(x::text) FROM xbase),"""

# ---------------------------------------------------------------------------
# RC — identidade da 2211/2176/2095/2192 (bloco IDÊNTICO ao E06P, demonstrado
# no LIVE pelo L4: 4/4 ok)
# ---------------------------------------------------------------------------
RC = """rc_exp(sig, pin, lang, vol, secdef, cfg, result) AS (
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
),"""

RC_GATE = """        ((SELECT count(*) FROM rc WHERE ok) = 4
         AND has_function_privilege(current_user, to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)'), 'EXECUTE')
         AND has_function_privilege(current_user, to_regprocedure('internal.resolve_variant_mapping_scope(uuid,uuid)'), 'EXECUTE')) AS g_rc_identity,"""

RC_DETAIL = """        'd_rc_identity',    COALESCE((SELECT jsonb_agg(to_jsonb(r) - 'fn_oid' ORDER BY r.sig) FROM rc r), '[]'::jsonb),"""

GS = """gs AS (
    SELECT (SELECT id FROM public.game WHERE code = 'POKEMON') AS game_id,
           (SELECT id FROM public.asset_source WHERE code = 'TCGDEX') AS src_id
),"""

GS_GATE = """        ((SELECT count(*) FROM public.game WHERE code = 'POKEMON') = 1
         AND (SELECT count(*) FROM public.asset_source WHERE code = 'TCGDEX') = 1)    AS g_game_source_one,"""

# marcador do E00 (trait.code, profile.code, mapping.normalized_token) e do
# Printing (normalized_token) — ausência AGORA
MK_GATE = """        ((SELECT count(*) FROM public.card_edition_context_trait WHERE strpos(code, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_edition_context_profile WHERE strpos(code, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE strpos(normalized_token, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_printing_external_mapping WHERE strpos(normalized_token, 'H2830') > 0) = 0) AS g_marker_absent_now,"""

SESSION_DETAIL = """        'd_session',        jsonb_build_object(
                                'current_user',       current_user,
                                'server_version_num', current_setting('server_version_num'),
                                'lock_timeout',       current_setting('lock_timeout'),
                                'search_path',        current_setting('search_path'),
                                'backend_pid',        pg_backend_pid(),
                                'checked_at',         clock_timestamp())"""

# núcleo do candidato de Printing (3.5 / R4 / R8) — IDÊNTICO ao E06P/E06
C35 = """c35 AS (
    SELECT m.id, m.raw_field::text AS raw_field, m.normalized_token,
           COALESCE(m.traits_signature,
                    ARRAY(SELECT mt.trait_id FROM public.card_printing_external_mapping_trait mt
                           WHERE mt.mapping_id = m.id ORDER BY mt.trait_id)) AS sig
      FROM public.card_printing_external_mapping m, gs
     WHERE m.game_id = gs.game_id AND m.asset_source_id = gs.src_id AND m.is_active
       AND m.raw_field IN ('subtype', 'stamp')
),
cand35 AS (
    SELECT c.id, c.raw_field, c.normalized_token, c.sig, pp.id AS profile_id,
           EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping e
                    WHERE e.game_id = gs.game_id AND e.asset_source_id = gs.src_id AND e.raw_field = c.raw_field
                      AND e.normalized_token = c.normalized_token AND e.is_active AND e.external_set_id IS NULL) AS ec_overlap
      FROM c35 c
     CROSS JOIN gs
      JOIN public.card_printing_profile pp ON pp.game_id = gs.game_id AND pp.is_active AND pp.traits_signature = c.sig
     WHERE cardinality(c.sig) > 0
       AND NOT EXISTS (SELECT 1 FROM public.card_printing_trait t WHERE t.id = ANY (c.sig) AND NOT t.is_active)
       AND public.normalize_external_catalog_value(c.normalized_token) = c.normalized_token
     ORDER BY 6 DESC, c.id
     LIMIT 1
),"""


def precheck(header, ctes, gates, details, alias):
    """monta o SELECT único: WITH <ctes> gates AS (SELECT <gates>) SELECT ..."""
    g = gates.rstrip().rstrip(',')
    d = details.rstrip().rstrip(',')
    body = ('WITH\n' + '\n'.join(c.rstrip('\n') for c in ctes).rstrip(',') + ',\n'
            + 'gates AS (\n    SELECT\n' + g + '\n)\n'
            + 'SELECT to_jsonb(g)\n    || jsonb_build_object(\n'
            + "        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))\n"
            + "                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),\n"
            + d + '\n    ) AS ' + alias + '\n  FROM gates g;\n')
    return header + body


# ---------------------------------------------------------------------------
# Reuso LITERAL de blocos do E06P (executado CONFORME no LIVE, L4): estrutura
# da 2207 nas 3 tabelas EC escritas (triggers, constraints, índices de ativo,
# selo, P6, RLS). Extraído do arquivo por nome de CTE/gate — nunca redigitado.
# ---------------------------------------------------------------------------
import pathlib as _pl
_E06P = None


def _e06p():
    global _E06P
    if _E06P is None:
        # fonte ÚNICA: o E06P do harness (tools/b12gen/ -> harness/)
        _E06P = (_pl.Path(__file__).resolve().parents[2] / '2830H_E06P_precheck_section3.sql').read_text(encoding='utf-8')
    return _E06P


def e06p_cte(name):
    t = _e06p()
    m = re.search(r'\n(' + re.escape(name) + r'(?:\([^)]*\))? AS \(\n.*?\n\),)', t, re.S)
    assert m, name
    return m.group(1)


def e06p_gate(name):
    t = _e06p()
    gi = t.index('\ngates AS (\n    SELECT\n') + len('\ngates AS (\n    SELECT\n')
    ge = t.index('\n)\nSELECT to_jsonb(g)')
    g = t[gi:ge]
    parts = re.split(r'(AS ' + r'g_[a-z0-9_]+,?)', g)
    # reconstrói "expressão AS nome," por gate
    acc = ''
    for i in range(0, len(parts) - 1, 2):
        expr, alias = parts[i], parts[i + 1]
        if alias.rstrip(',').split()[-1] == name:
            return (expr + alias).strip('\n').rstrip(',') + ','
    raise AssertionError(name)


import re
E06P_STRUCT_CTES = ['tbl', 'rel', 'trg_exp', 'trg', 'con', 'con_exp', 'act_idx', 'idx', 'seal_con', 'l3_seq', 'l3_own']
E06P_STRUCT_GATES = ['g_l4_triggers', 'g_no_other_triggers_l4', 'g_seal_constraint_names_unique', 'g_deferrable_only_seal_l4',
                     'g_l4_constraints', 'g_l4_no_sequence', 'g_l4_rls_bypass', 'g_37_no_printing']
