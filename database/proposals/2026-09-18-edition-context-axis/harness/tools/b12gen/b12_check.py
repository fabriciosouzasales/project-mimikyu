# BATCH12 — INTEGRATED COMPLETION: perfil estático ÚNICO dos artefatos L5–L13
# (E07–E15, prechecks, E98, P9A). Não conecta a banco. Três blocos com total
# próprio: B12-PERFIL, B12-VERIFICADOR-NEG (mutações que TÊM de ser
# rejeitadas) e B12-VERIFICADOR-POS (controles positivos). Chamado pelo
# tools/static_check.py (bloco anexado ao final; blocos anteriores intactos).
import re, sys, json, hashlib, pathlib

G = pathlib.Path(__file__).resolve().parent          # tools/b12gen
H = G.parent.parent                                   # harness
DB = H.parent.parent.parent                           # database/
sys.path.insert(0, str(G))
import lib, pre, jr, l8, l9, l10, l11, l13, gen_all, b12_lint   # noqa: E402

# ---------------------------------------------------------------------------
# utilitários
# ---------------------------------------------------------------------------
def code(s):
    out = []
    for l in s.splitlines():
        i = l.find('--')
        out.append(l if i < 0 else l[:i])
    return '\n'.join(out)


def nostr(c):
    return re.sub(r"'(?:[^']|'')*'", "''", c)


def md5(t):
    return hashlib.md5(t.encode()).hexdigest()


# contrato 2830 v7.0: casos automáticos por lote (L5–L13)
CONTRACT = {
    'E07': ['2.6', '3.3'],
    'E08': ['4.1', '4.2', '4.3', '4.4', '4.5', '4.6', '4.7', '4.8'],
    'E09': ['S1', 'S2', 'S2-BIS', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S10', 'S11'],
    'E10': ['R%d' % i for i in range(1, 13)],
    'E11': ['K3', 'K4', 'K8'],
    'E12': ['V%d' % i for i in range(1, 15)],
    'E13': ['SM%d' % i for i in range(1, 12)],
    'E14': ['G%d' % i for i in range(1, 9)],
    'E15': ['5.1', '5.2', '5.3', '5.6', '5.7'],
}
TAG = {e: 'h2830_' + e.lower() for e in CONTRACT}
T_EC = ['card_edition_context_trait', 'card_edition_context_profile', 'card_edition_context_profile_trait',
        'card_edition_context_external_mapping', 'card_edition_context_external_mapping_trait']
T_JR = ['catalog_variant_import_job', 'catalog_variant_import_row']
# write-set autorizado por envelope (INSERT / UPDATE), DP-5
WRITES = {
    'E07': (['game'] + T_EC, []),
    'E08': (['card_variant'], []),
    'E09': (T_JR, []),
    'E10': (['card_edition_context_trait', 'card_edition_context_external_mapping',
             'card_edition_context_external_mapping_trait'], ['card_edition_context_external_mapping']),
    'E11': ([], []),
    'E12': ([], []),
    'E13': (T_JR, []),
    'E14': (T_JR, T_JR),
    'E15': ([], []),
}
FORB = [r'\bCOMMIT\b', r'\bROLLBACK\b', r'\bCREATE\b', r'\bALTER\b', r'\bDROP\b', r'\bTEMP\b', r'\bTEMPORARY\b',
        r'\bTRUNCATE\b', r'\bGRANT\b', r'\bREVOKE\b', r'\bEXECUTE\s+[\'"A-Z_]', r'\bPERFORM\b', r'SET_CONFIG',
        r'\bSET\s+ROLE\b', r'\bSET\s+SESSION\b', r'RAISE\s+NOTICE', r'RAISE\s+WARNING', r'RAISE\s+INFO', r'PG_SLEEP',
        r'DBLINK', r'\bCOPY\b', r'\bLOCK\s+TABLE\b', r'\bCALL\b', r'\bDELETE\b', r'\bMERGE\b', r'\bLOOP\b',
        r'SET\s+CONSTRAINTS', r'\bNOTIFY\b', r'\bLISTEN\b', r'\bCOMMENT\s+ON\b', r'\bREINDEX\s+(INDEX|TABLE)\b',
        r'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT\s*\(', r'IS_ADMIN\s*\(']
LT = "    SET LOCAL lock_timeout = '5s';\n    IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN"


# ---------------------------------------------------------------------------
# regras do envelope
# ---------------------------------------------------------------------------
def env_rules(eid, src, ctx_expected=None):
    out = []
    ck = lambda r, n, c, d='': out.append((f'{eid} {r}: {n}', bool(c), d))
    tag = TAG[eid]
    c = code(src)
    parts = c.split('$' + tag + '$')
    ck('B-1', 'um único DO $tag$ … $tag$; e nada executável fora', len(re.findall(r'\bDO\s+\$', c)) == 1 and len(parts) == 3
       and parts[0].strip().upper() == 'DO' and parts[2].strip() == ';')
    body = parts[1] if len(parts) == 3 else ''
    bns = nostr(body).upper()
    bad = [t for t in FORB if re.search(t, bns)]
    ck('B-2', 'nenhum comando proibido (DDL, TEMP, transação, dinâmico, NOTICE, DELETE, confirm/is_admin)', not bad, str(bad))
    ins = re.findall(r'INSERT\s+INTO\s+PUBLIC\.(\w+)', bns)
    upd = re.findall(r'UPDATE\s+PUBLIC\.(\w+)', bns)
    ai, au = WRITES[eid]
    ck('B-3', 'INSERT só no write-set autorizado do lote', all(t.lower() in ai for t in ins), str(sorted(set(ins))))
    ck('B-4', 'UPDATE só no write-set autorizado do lote', all(t.lower() in au for t in upd), str(sorted(set(upd))))
    ups = re.findall(r'UPDATE\s+public\.\w+\s+SET\s+.*?;', body, re.S)
    ck('B-5', 'todo UPDATE filtra por id de fixture (WHERE id = v_…)', all(re.search(r'WHERE\s+id\s*=\s*v_\w+', u) for u in ups), '')
    ck('B-6', 'nenhum UUID literal gravado (INSERT/UPDATE)',
       not any(re.search(r"'[0-9a-f]{8}-[0-9a-f]{4}-", s) for s in re.findall(r'(?:INSERT|UPDATE)\b.*?;', body, re.S)))
    ck('B-7', 'P8: SET LOCAL lock_timeout 5s + asserção é a 1ª instrução', body.split('BEGIN\n', 1)[-1].lstrip('\n').split('\n', 3)[-1].startswith(LT)
       or LT in body.split('-- PREFLIGHT', 1)[0])
    cases = re.findall(r"\n    v_case := '([^']+)';", body)
    cases = [x for x in cases if x not in ('VREC', 'SMREC', 'DERIV-5X')]
    exp = re.search(r"c_expected CONSTANT text\[\] := ARRAY\[(.*?)\];", c)
    exp = [x.strip("'") for x in exp.group(1).split(',')] if exp else []
    ck('B-8', 'casos = contrato 2830 v7.0, na ordem, uma vez', cases == CONTRACT[eid] and exp == CONTRACT[eid], str(cases))
    ck('B-9', 'H283P exatamente 1; H283C 1 por caso + 1 no handler', src.count("ERRCODE = 'H283P'") == 1
       and src.count("ERRCODE = 'H283C', MESSAGE = v_case") == len(CONTRACT[eid]))
    ck('B-10', 'gate v_done = c_expected antes do terminal', src.index('IF v_done IS DISTINCT FROM c_expected') < src.index("ERRCODE = 'H283P'"))
    n_neg = body.count('v_got := false;')
    ck('B-11', 'todo negativo exige falha (IF NOT v_got) e identidade exata', n_neg == body.count('IF NOT v_got THEN')
       and n_neg == len(re.findall(r"v_state <> '(?:P0001|23\d{3})'", body)))
    ck('B-12', 'P0001 comparado por starts_with (nunca LIKE)', not re.search(r'V_MSG\s+(NOT\s+)?I?LIKE', bns))
    ck('B-13', 'sem RETURN QUERY/RETURN NEXT; sem COMMIT implícito', not re.search(r'\bRETURN\s+(QUERY|NEXT)\b', bns))
    ck('B-14', 'marcador por gen_random_uuid (nunca literal)', "v_marker   text := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''))" in src)
    jobs = re.findall(r"INSERT INTO public\.catalog_variant_import_job .*?VALUES \((.*?)\)", body, re.S)
    ck('B-15', 'job de fixture sempre marcado (external_set_id = marcador || _J<n>)', all("v_marker || '_J" in j for j in jobs))
    games = re.findall(r"INSERT INTO public\.game .*?VALUES \((.*?)\)", body, re.S)
    ck('B-16', 'Game sentinela sempre marcado (code = marcador)', all(g.strip().startswith('v_marker') for g in games))
    ck('B-17', 'aspas balanceadas e dollar-quote íntegro', src.count("'") % 2 == 0 and src.count('$' + tag + '$') == 2)
    lines = src.split('\n')
    do_l = next((i for i, l in enumerate(lines, 1) if l.startswith('DO $')), 0)
    p_l = next((i for i, l in enumerate(lines, 1) if "ERRCODE = 'H283P'" in l), 0)
    ck('B-18', 'linha CONTEXT do H283P = manifesto', ctx_expected is None or p_l - do_l + 1 == ctx_expected, str(p_l - do_l + 1))
    ck('B-19', 'higiene (LF, sem TAB, sem espaço final, termina em LF)', '\r' not in src and '\t' not in src
       and not re.search(r' +\n', src) and src.endswith('\n'))
    return out


def pre_rules(pid, src):
    out = []
    ck = lambda r, n, c, d='': out.append((f'{pid} {r}: {n}', bool(c), d))
    c = nostr(code(src)).upper()
    ck('P-1', 'um único statement SELECT (WITH … SELECT …;)', c.strip().startswith('WITH') and c.count(';') == 1 and c.strip().endswith(';'))
    forb = [r'\bINSERT\b', r'\bUPDATE\b', r'\bDELETE\b', r'\bCREATE\b', r'\bALTER\b', r'\bDROP\b', r'\bSET\b\s+\w+\s*=',
            r'SET_CONFIG', r'\bDO\b\s*\$', r'\bCALL\b']
    # E15P é a MEDIÇÃO A4 exigida pela 2830 5.2 ("medidos pelo precheck com a
    # mesma derivação") — a leitura C2 do B-5X chama a 2211; única exceção.
    if pid != 'E15P':
        forb.append(r'RESOLVE_VARIANT_ROW_AXES\s*\(')
    bad = [t for t in forb if re.search(t, c)]
    ck('P-2', 'read-only; nenhum precheck chama a 2211', not bad, str(bad))
    ck('P-3', 'gate_pass = bool_and E nenhum gate NULL', "AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL)" in src)
    return out


# ---------------------------------------------------------------------------
# avaliador offline dos predicados P13 (SQL -> Python) para controles em memória
# ---------------------------------------------------------------------------
def sql_pred(p):
    s = p
    s = re.sub(r'\bIS DISTINCT FROM\b', '!=', s)
    s = re.sub(r'\bIS NOT NULL\b', '!= None', s)
    s = re.sub(r'\bIS NULL\b', '== None', s)
    s = re.sub(r'\bNOT IN\b', 'not in', s)
    s = re.sub(r'\bIN\b', 'in', s)
    s = s.replace('<>', '!=')
    s = re.sub(r'(?<![<>!=])=(?!=)', '==', s)
    s = re.sub(r'\bAND\b', 'and', s)
    s = re.sub(r'\bOR\b', 'or', s)
    s = re.sub(r'\bNOT\b', 'not', s)
    s = re.sub(r'\btrue\b', 'True', s)
    return s


def ev(p, row):
    """semântica de 3 valores simplificada: comparação com None -> False (= NULL em FILTER)"""
    try:
        return bool(eval(sql_pred(p), {}, dict(row)))
    except TypeError:
        return False


def v_ctrl_rows():
    ops = ('RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING')
    rows = []
    for (t, js, per, val, dec, obs, ou, ex, eu, rs, mt) in l10.CTRL:
        f = lambda x: None if x == 'NULL' else x.strip("'")
        rows.append((t, dict(job_status=js, per=per, val=val, dec=dec, obs=obs, obs_uuid=f(ou), exp=ex, exp_uuid=f(eu),
                             res=f(rs), mat=f(mt), op=(js in ops and per == 'PENDING'), rechecked=True)))
    return rows


def sm_ctrl_rows():
    rows = []
    for (t, js, v, d, p, hk, hp, vt, rs, mt) in l11.CTRL:
        f = lambda x: None if x == 'NULL' else x.strip("'")
        rows.append((t, dict(job_status=js, val=v, dec=d, per=p, has_key=hk == 'true', has_pp=hp == 'true', vt=f(vt), res=f(rs), mat=f(mt))))
    return rows


# ---------------------------------------------------------------------------
# md5 LF de corpos de função no repositório (pinos P7X/E11)
# ---------------------------------------------------------------------------
def repo_bodies(fqname):
    found = set()
    pat = re.compile(r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+' + re.escape(fqname) + r'\s*\(', re.I)
    for f in DB.rglob('*.sql'):
        t = f.read_text(encoding='utf-8', errors='replace').replace('\r\n', '\n')
        for m in pat.finditer(t):
            mm = re.compile(r'AS\s+\$(\w*)\$').search(t, m.end())
            if not mm:
                continue
            end = t.find('$' + mm.group(1) + '$', mm.end())
            if end > 0:
                found.add(md5(t[mm.end():end]))
    return found


def r27_ok(q):
    c = code(q)
    pre_, post_ = c[c.index('DO $pre$'):c.index('$pre$;')], c[c.index('DO $post$'):c.index('$post$;')]
    return (all(k in pre_ for k in ["'pg_catalog.timestamptz'::pg_catalog.regtype", "set_config('mmkyu.p2234_fn'",
                                     "set_config('mmkyu.p2234_dep'", "to_regclass('public.card_variant_type')"])
            and all(k in post_ for k in ["IF v_fn IS DISTINCT FROM current_setting('mmkyu.p2234_fn', true) THEN",
                                         "IF v_dep IS DISTINCT FROM current_setting('mmkyu.p2234_dep', true) THEN",
                                         'FROM pg_depend d', "ARRAY['search_path=\"\"']"])
            and c.index('$pre$;') < c.index('\nALTER FUNCTION public.') < c.index('DO $post$') < c.index('COMMIT;')
            and 'RESET search_path' in q and 'SET search_path = public, pg_temp;' in q)


def r21_ok(e15, e15p):
    pre15 = e15[:e15.index("v_case := 'DERIV-5X'")]
    c52 = e15[e15.index("v_case := '5.2'"):e15.index("v_case := '5.3'")]
    return (l13.READY_DEF is None and 'B-5X: READY_STRUCTURAL não adjudicado' in pre15
            and re.search(r'\bfalse\s+AS g_5x_ready_adjudicated', e15p) is not None
            and re.search(r'\bfalse\s+AS g_5x_adjudicated_candidate_ok', e15p) is not None
            and 'AS g_5x_unique_candidate_equals_a' in e15p and "'d_5x_candidate_ok'" in e15p
            and all(f'd5_{c} AS (' in l13.DERIV and f'd5_{c}_bt AS (' in l13.DERIV for c in ('c0', 'c1', 'c2', 'c3'))
            and 'AS g_5x_type_code_unique' in e15p
            and "IF (v_agg->>'type_code_dup')::bigint IS DISTINCT FROM 0 THEN" in e15
            and 'IF NOT COALESCE(' in c52 and "_fp_named_bad')::bigint = 0" in c52
            and all(f"_fp_{k}')::bigint = {l13.MAP_FP[k]}" in c52
                    for k in ('worlds_types', 'worlds_n', 'single_types', 'single_n', 'single_non1')))


# Cópia INDEPENDENTE (verificador) da lista FINISH do seletor histórico,
# LIVE 2026-09-19T02:04:20Z — não importada do gerador.
HIST_FINISH = ['STANDARD', 'HOLO', 'COSMOS_HOLO', 'REVERSE_HOLO', 'ENERGY_REVERSE', 'POKE_BALL_REVERSE', 'LOVE_BALL_REVERSE',
               'FRIEND_BALL_REVERSE', 'QUICK_BALL_REVERSE', 'DUSK_BALL_REVERSE', 'ROCKET_REVERSE', 'MASTER_BALL_REVERSE',
               'GOLD_HOLO', 'TINSEL_HOLO', 'TINSEL_REVERSE', 'CRACKED_ICE_HOLO', 'GALAXY_HOLO', 'RAINBOW_HOLO', 'METAL',
               'METAL_GOLD', 'LENTICULAR', 'COSMOS_REVERSE', 'MASTER_BALL_PATTERN', 'POKE_BALL_PATTERN', 'MASTER_BALL_HOLO',
               'SNOWFLAKE_COSMOS_HOLO', 'STANDARDS_SNOWFLAKE', 'SHOWFLAKE_HOLO']
HIST_C3 = """d5_c3 AS (
    SELECT cv.id, cv.variant_type_id, c.card_set_id
      FROM public.card_variant cv
      JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
      JOIN public.card c  ON c.id  = cv.card_id
      JOIN public.card_set cs ON cs.id = c.card_set_id
     WHERE vt.code NOT IN (SELECT code FROM d5_finish)
       AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$')
       AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code NOT IN ('DP1','SWSH9','SVP'))
       AND vt.code <> 'PROMO_STAMPED'
),"""


def r29_ok(deriv):
    """C3 = seletor histórico verbatim: bloco d5_c3 idêntico ao do verificador e
    lista d5_finish = os 28 códigos FINISH na ordem original, sem acréscimo"""
    fin = re.search(r"d5_finish\(code\) AS \(\n    VALUES (.*?)\n\),", deriv, re.S)
    codes = re.findall(r"\('([A-Z_]+)'\)", fin.group(1)) if fin else None
    return (fin is not None and codes == HIST_FINISH and len(codes) == 28
            and deriv.count(HIST_C3) == 1 and deriv.count('d5_c3 AS (') == 1
            and 'type_code_dup' in deriv)


def r31_ok(e15p):
    """g_scope_unique mede a unicidade EFETIVA por Card Set distinto (fonte +
    função), nunca linhas da função por variant"""
    sc = e15p[e15p.index('d5_scope AS ('):]
    sc = sc[:sc.index('\n),') + 3]
    return ('FROM (SELECT DISTINCT e.card_set_id FROM d5_ev e) s' in sc
            and 'FROM public.card_set_external_reference r' in sc
            and 'r.card_set_id = s.card_set_id AND r.asset_source_id = gs.src_id AND r.is_active' in sc
            and 'FROM internal.resolve_variant_mapping_scope(s.card_set_id, gs.src_id)) AS n_fn' in sc
            and 'count(sc.*)' not in sc and 'GROUP BY' not in sc
            and '(SELECT bool_and(n_active <= 1 AND n_fn = n_active) FROM d5_scope)' in e15p
            and 'AS g_scope_unique' in e15p)


def r22_ok(e10):
    r12 = e10[e10.index("v_case := 'R12'"):]
    return (r12.count("IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING'") == 3
            and r12.count("IS DISTINCT FROM 'NEEDS_REVIEW_INVALID_EC_MAPPING'") == 3
            and r12.count("IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE'") == 1
            and r12.count('v_rst IS DISTINCT FROM v_tok6') == 2 and 'v_rst IS NOT NULL' in r12)


def fp_map_ok(named, fp):
    """impressão digital de A consistente, TIPOS separados de VARIANTES (STOP-7):
    variantes 320 + 21 + 24 = 365; tipos 23 + 21 + 19 = 63; WORLDS/ASIA 21
    tipos × 1 = 21; residual 19 tipos = 14 unitários + 5 duplos = 24 (com
    single_non1 tipos de n >= 2 e soma single_n, os não unitários são
    exatamente 2 cada)"""
    return (len(named) == 23 and len({c for c, _ in named}) == 23 and sum(n for _, n in named) == fp['named_sum'] == 320
            and fp['named_sum'] + fp['worlds_n'] + fp['single_n'] == 365
            and len(named) + fp['worlds_types'] + fp['single_types'] == fp['n_types'] == 63
            and fp['worlds_types'] == fp['worlds_n'] == 21
            and fp['single_types'] == 19 and fp['single_n'] == 24 and fp['single_non1'] == 5
            and 0 <= fp['single_non1'] <= fp['single_types']
            and (fp['single_types'] - fp['single_non1']) + 2 * fp['single_non1'] == fp['single_n']
            and fp['slr_svp'] + fp['slr_dp1'] == dict(named).get('SET_LOGO_REVERSE', -1)
            and fp['sls_dp1'] <= dict(named).get('SET_LOGO_STANDARDS', -1))


# ---------------------------------------------------------------------------
# execução
# ---------------------------------------------------------------------------
def run():
    res, neg, pos = [], [], []
    files, meta, total = gen_all.build()
    man = json.loads((H / 'B12-INTEGRATED-MANIFEST.json').read_text(encoding='utf-8'))
    ctx = {m['id']: m.get('context_line') for m in man['artifacts']}
    # 1. arquivos = saída do gerador (determinismo, nenhuma edição manual)
    for name, text in files.items():
        disk = (H / name).read_bytes().decode('utf-8')
        res.append((f'B12 R-1: {name} = saída do gerador (byte a byte)', disk == text, ''))
    res.append(('B12 R-2: manifesto = gerador (md5, casos, CONTEXT)', [(m['file'], m['md5']) for m in man['artifacts']]
                == [(m['file'], m['md5']) for m in meta], ''))
    res.append(('B12 R-3: 75 casos automáticos novos; 60 + 75 = 135', total == 75 and man['automatic_cases_total'] == 135
                and sum(len(v) for v in CONTRACT.values()) == 75, str(total)))
    # 2. envelopes
    for eid, name, _, _ in gen_all.ENVELOPES:
        res += env_rules(eid, files[name], ctx[eid])
    # 3. prechecks / E98
    for pid, name, _, _ in gen_all.PRECHECKS + gen_all.OTHER:
        res += pre_rules(pid, files[name])
    # 4. blocos compartilhados byte-idênticos (I-3c / I-4c / reuso E06P)
    e06p = (H / '2830H_E06P_precheck_section3.sql').read_text(encoding='utf-8')
    F = lambda n: files[n]
    for n in ['2830H_E07P_precheck_game_sentinel.sql', '2830H_E08P_precheck_section4.sql', '2830H_E09P_precheck_section_s.sql',
              '2830H_E13P_precheck_section_m.sql', '2830H_E14P_precheck_section_g.sql']:
        res.append((f'B12 R-4: {n} contém P7X e XBASELINE idênticos', pre.P7X in F(n) and pre.XBASE in F(n) and pre.P7X_GATES in F(n), ''))
    res.append(('B12 R-5: XBASELINE-BUILDER do E98 = o dos prechecks', pre.XBASE.rstrip(',') in F('2830H_E98_postcheck_extended_residue.sql'), ''))
    for n in ['2830H_E09P_precheck_section_s.sql', '2830H_E12P_precheck_section_b.sql', '2830H_E13P_precheck_section_m.sql',
              '2830H_E14P_precheck_section_g.sql']:
        res.append((f'B12 R-6: {n} contém o bloco JOB/ROW idêntico', jr.JR_CTES in F(n) and jr.JR_GATES.rstrip(',') in F(n), ''))
    res.append(('B12 R-7: RC (identidade 2211/2176/normalize/scope) do E10P/E12P = E06P',
                pre.RC in e06p and pre.RC in F('2830H_E10P_precheck_section_r.sql') and pre.RC in F('2830H_E12P_precheck_section_b.sql'), ''))
    blocks = [pre.e06p_cte(n) for n in pre.E06P_STRUCT_CTES] + [pre.e06p_gate(g) for g in pre.E06P_STRUCT_GATES]
    res.append(('B12 R-8: blocos estruturais do E10P extraídos LITERALMENTE do E06P (executado no L4)',
                all(b in e06p and b in F('2830H_E10P_precheck_section_r.sql') for b in blocks), ''))
    p9 = F('2830H_P9A_heavy_sections_explain.sql')
    res.append(('B12 R-9: P9A usa o mesmo texto de VREC/SMREC/DERIV-5X dos envelopes',
                l10.vrec(gen_all.GAME, gen_all.SRC) in p9 and l11.smrec() in p9 and l13.deriv_select() in p9
                and lib.ind(l10.vrec('v_game', 'v_src'), 8) in F('2830H_E12_section_b_backfill_semantic.sql')
                and lib.ind(l11.smrec(), 8) in F('2830H_E13_section_m_state_machine.sql')
                and l13.DERIV in F('2830H_E15P_measure_section5.sql')
                and lib.ind(l13.deriv_select(), 8) in F('2830H_E15_section5_legacy_hold.sql'), ''))
    res.append(('B12 R-10: P9A só EXPLAIN (COSTS OFF), sem ANALYZE', code(p9).count('EXPLAIN (COSTS OFF)') == 3 and 'ANALYZE' not in code(p9).upper(), ''))
    # 5. pinos = corpos do repositório
    pins = re.findall(r"\('([\w.]+)\((?:[^)]*)\)',\s+'\w+',\s+\w+,\s+'\w',\s+[^,]+(?:,[^,]+)?,\s+'([0-9a-f]{32})'", pre.P7X)
    res.append(('B12 R-11: P7X tem 8 pinos', len(pins) == 8, str(len(pins))))
    for fn, pin in pins:
        res.append((f'B12 R-12: pino P7X de {fn} = md5 LF de um corpo do repositório', pin in repo_bodies(fn), pin))
    res.append(('B12 R-13: pino do confirm (E11) = corpo da 2218 no repositório',
                l9.CONFIRM_PIN in repo_bodies('public.admin_confirm_catalog_variant_import'), ''))
    # 6. E11: espelho offline dos predicados sobre o corpo real
    body2218 = None
    t = (H.parent / '2218_redefine_admin_confirm_catalog_variant_import.sql').read_text(encoding='utf-8')
    s = t[t.index('CREATE OR REPLACE FUNCTION'):]
    m = re.search(r'AS \$(\w*)\$', s)
    body2218 = s[m.end():s.index('$' + m.group(1) + '$', m.end())]
    res.append(('B12 R-14: K3/K4/K8 verdadeiros no corpo real da 2218', all(l9.k_eval(body2218).values()), str(l9.k_eval(body2218))))
    # 7. P13: cada controle em memória viola EXATAMENTE o seu predicado (offline)
    for tag, row in v_ctrl_rows():
        k = tag
        res.append((f'B12 R-15: controle V {k} dispara o próprio predicado', ev(l10.P[k], row), sql_pred(l10.P[k])))
    for tag, row in sm_ctrl_rows():
        res.append((f'B12 R-16: controle SM {tag} dispara o próprio predicado', ev(l11.P[tag], row), sql_pred(l11.P[tag])))
    res.append(('B12 R-17: SM8 declarado = SM7 (mesmo texto)', l11.P['sm8'] == l11.P['sm7'], ''))
    res.append(('B12 R-18: E15 marcado BLOQUEADO por B-5X no cabeçalho', 'BLOQUEADO por B-5X' in F('2830H_E15_section5_legacy_hold.sql'), ''))

    # 8. INTEGRATED TECHNICAL RESOLUTION — B-5X, D-P7X, D-V1, R6, R12, P9B, 2234
    allow = pre.P7X[pre.P7X.index('p7x_allow('):pre.P7X.index('p7x_fn AS (')]
    res.append(('B12 R-20: P7X exige search_path="" nas 8 raízes; nenhuma classe admitida por mitigação',
                allow.count("ARRAY['search_path=\"\"']") == 8 and 'LEGACY_SP' not in pre.P7X + pre.P7X_GATES
                and 'g_p7x_search_path_empty' in pre.P7X_GATES and 'g_p7x_legacy_sp_mitigated' not in ''.join(files.values()), ''))
    e15 = F('2830H_E15_section5_legacy_hold.sql')
    pre15 = e15[:e15.index("v_case := 'DERIV-5X'")]
    res.append(('B12 R-21: B-5X — E15 fail-closed antes de qualquer caso (READY_DEF não adjudicado)',
                r21_ok(e15, F('2830H_E15P_measure_section5.sql')), ''))
    res.append(('B12 R-28: B-5X — impressão digital de A consistente (variantes 320 + 21 + 24 = 365; tipos 23 + 21 + 19 = 63; residual 14×1 + 5×2)',
                fp_map_ok(l13.MAP_NAMED, l13.MAP_FP), ''))
    res.append(('B12 R-29: B-5X — C3 = seletor histórico verbatim (FINISH 28 literal + regras SET_LOGO + PROMO_STAMPED) e gate de unicidade de code',
                r29_ok(l13.DERIV) and r29_ok(F('2830H_E15P_measure_section5.sql')), ''))
    res.append(('B12 R-31: E15P g_scope_unique = unicidade efetiva por Card Set distinto (fonte ativa + função), não linhas por variant',
                r31_ok(F('2830H_E15P_measure_section5.sql')), ''))
    e10 = F('2830H_E10_section_r_routing_2211.sql')
    r12 = e10[e10.index("v_case := 'R12'"):]
    res.append(('B12 R-22: R12 cobre as 4 saídas A4 + contraprovas (residual integral após consumo; terminal NO_EC_PROFILE consome)',
                r22_ok(e10), ''))
    r6 = e10[e10.index("v_case := 'R6'"):e10.index("v_case := 'R7'")]
    res.append(('B12 R-23: R6 compara 8 contagens de vocabulário (EC 5 + Printing 3) como vetor',
                r6.count('SELECT count(*) FROM public.card_') == 16 and 'v_cnt1 IS DISTINCT FROM v_cnt0' in r6, ''))
    e12 = F('2830H_E12_section_b_backfill_semantic.sql')
    v1 = e12[e12.index("v_case := 'V1'"):e12.index("v_case := 'V2'")]
    res.append(('B12 R-24: D-V1 — existência medida na tabela inteira (complemento histórico sem chave, EXISTS/LIMIT 1)',
                'IF v_occ = 0 THEN' in v1 and "NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')" in v1 and 'LIMIT 1' in v1, ''))
    p9b = F('2830H_P9B_isolated_timing.sql')
    res.append(('B12 R-25: P9B só EXPLAIN (ANALYZE, BUFFERS) de SELECT, marcado ambiente isolado',
                code(p9b).count('EXPLAIN (ANALYZE, BUFFERS)') == 4 and 'PROIBIDO no LIVE' in p9b
                and not re.search(r'\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b', nostr(code(p9b)).upper()), ''))
    q2234 = (H.parent / '2234_harden_search_path_edition_context_write_surface.sql').read_text(encoding='utf-8')
    alters = re.findall(r"ALTER FUNCTION (public\.\w+\(\)) SET search_path = '';", q2234)
    res.append(('B12 R-26: 2234 corrige exatamente as 4 funções inseguras do E00, com search_path=\'\' e pinos do repositório',
                sorted(alters) == sorted(['public.set_updated_at()', 'public.validate_card_variant_game_consistency()',
                                          'public.normalize_catalog_variant_import_job()', 'public.normalize_catalog_variant_import_row()'])
                and all(pin in q2234 for fn, pin in pins if fn.startswith('public.'))
                and code(q2234).count('BEGIN;') == 1 and code(q2234).count('COMMIT;') == 1 and 'PROPOSTA — NÃO EXECUTADA' in q2234, str(alters)))
    res.append(('B12 R-30: 2234 — estrutura SQL integral verificada (lint_migration: M-1..M-6 e L-1..L-10 por bloco DO)',
                all(ok for _, ok, _ in b12_lint.lint_migration('2234', q2234, b12_lint.build_catalog())), ''))
    res.append(('B12 R-27: 2234 prova alcance de set_updated_at (updated_at TIMESTAMPTZ em todo trigger) e preserva metadados/triggers/pg_depend',
                r27_ok(q2234), ''))
    # 9. lint estrutural (substituto declarado de compilação)
    lres, cat = b12_lint.run()
    res += [('B12 LINT ' + n, ok, d) for n, ok, d in lres]

    # -------------------------------------------------------------------
    # VERIFICADOR-NEG: mutações que o perfil TEM de rejeitar
    # -------------------------------------------------------------------
    def mf(label, eid, mutated, rule):
        name = dict((e, n) for e, n, _, _ in gen_all.ENVELOPES)[eid]
        failed = [n for n, ok, _ in env_rules(eid, mutated, ctx[eid]) if not ok]
        neg.append((f'VERIFICADOR rejeita: {label} [{rule}]', mutated != files[name] and any(f' {rule}:' in n for n in failed), str(failed[:3])))
    E = lambda eid: files[dict((e, n) for e, n, _, _ in gen_all.ENVELOPES)[eid]]
    pf = "    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';\n"
    ins = lambda eid, stmt: E(eid).replace(pf, pf + stmt, 1)
    mf('COMMIT', 'E14', ins('E14', '    COMMIT;\n'), 'B-2')
    mf('CREATE TEMP TABLE', 'E12', ins('E12', '    CREATE TEMP TABLE t AS SELECT 1;\n'), 'B-2')
    mf('EXECUTE dinâmico', 'E13', ins('E13', "    EXECUTE 'SELECT 1';\n"), 'B-2')
    mf('RAISE NOTICE', 'E12', ins('E12', "    RAISE NOTICE 'x';\n"), 'B-2')
    mf('DELETE em row', 'E14', ins('E14', '    DELETE FROM public.catalog_variant_import_row WHERE id = v_r1;\n'), 'B-2')
    mf('chamada do confirm', 'E11', ins('E11', "    SELECT count(*) INTO v_n FROM public.admin_confirm_catalog_variant_import(NULL, NULL);\n"), 'B-2')
    mf('LOOP', 'E13', ins('E13', '    LOOP EXIT; END LOOP;\n'), 'B-2')
    mf('INSERT fora do write-set (card_variant no L12)', 'E14', ins('E14', '    INSERT INTO public.card_variant (card_id) VALUES (v_card);\n'), 'B-3')
    mf('escrita em envelope read-only (E12)', 'E12', ins('E12', "    INSERT INTO public.catalog_variant_import_job (card_set_id) VALUES (NULL);\n"), 'B-3')
    mf('UPDATE de job fora do L12', 'E13', ins('E13', "    UPDATE public.catalog_variant_import_job SET status = 'STAGED' WHERE id = v_job1;\n"), 'B-4')
    mf('UPDATE sem filtro de id', 'E14', E('E14').replace("SET status = 'STAGED' WHERE id = v_job1;", "SET status = 'STAGED' WHERE status = 'CANCELLED';", 1), 'B-5')
    mf('UUID literal gravado', 'E14', E('E14').replace("VALUES (v_job1, v_card, '{}'::jsonb, '{}'::jsonb, 'NEEDS_REVIEW', 'PENDING')",
                                                         "VALUES (v_job1, '00000000-0000-4000-8000-000000000001', '{}'::jsonb, '{}'::jsonb, 'NEEDS_REVIEW', 'PENDING')", 1), 'B-6')
    mf("P8 '10s'", 'E12', E('E12').replace("SET LOCAL lock_timeout = '5s';", "SET LOCAL lock_timeout = '10s';", 1), 'B-7')
    mf('caso fora do contrato (V15)', 'E12', E('E12').replace("v_case := 'V14';", "v_case := 'V15';", 1), 'B-8')
    mf('caso removido do c_expected', 'E14', E('E14').replace("'G1','G2'", "'G2'", 1), 'B-8')
    mf('H283P duplicado', 'E11', ins('E11', "    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = 'x';\n"), 'B-9')
    mf('negativo sem exigir falha', 'E14', E('E14').replace('        IF NOT v_got THEN', '        IF false THEN', 1), 'B-11')
    mf('negativo aceitando qualquer SQLSTATE', 'E14', E('E14').replace("OR v_state <> 'P0001' OR", 'OR', 1), 'B-11')
    mf('LIKE sobre v_msg', 'E14', E('E14').replace("NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:')",
                                                     "v_msg NOT LIKE 'CVIR%'", 1), 'B-12')
    mf('marcador literal', 'E13', E('E13').replace("'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''))", "'H2830_FIXO'", 1), 'B-14')
    mf('job sem marcador', 'E14', E('E14').replace("v_marker || '_J1'", "'swsh9'", 1), 'B-15')
    mf('Game sentinela sem marcador', 'E07', E('E07').replace("VALUES (v_marker, 'H2830 fixture Game ' || v_marker)", "VALUES ('POKEMON2', 'x')", 1), 'B-16')
    mf('aspas desbalanceadas', 'E11', ins('E11', "    v_txt := 'x;\n"), 'B-17')
    mf('CONTEXT deslocado (linha extra antes do H283P)', 'E12', E('E12').replace('    -- TERMINAL:', '\n    -- TERMINAL:', 1), 'B-18')
    mf('espaço final', 'E15', E('E15').replace('BEGIN\n', 'BEGIN \n', 1), 'B-19')
    # mutações semânticas nos espelhos offline
    muts = {'K3 RAISE no handler': body2218.replace('WHEN OTHERS THEN', 'RAISE;\n WHEN OTHERS THEN', 1),
            'K4 igualdade simples': body2218.replace('cv.printing_profile_id        IS NOT DISTINCT FROM v_printing_profile_id',
                                                     'cv.printing_profile_id = v_printing_profile_id', 1),
            'K8 sem ORDER BY': body2218.replace('ORDER BY c.id\n        FOR UPDATE;', 'FOR UPDATE;', 1)}
    for k, b in muts.items():
        neg.append((f'VERIFICADOR rejeita (espelho E11): {k}', b != body2218 and not all(l9.k_eval(b).values()), str(l9.k_eval(b))))
    # controle que NÃO viola o predicado tem de ser detectado como inútil
    good = dict(job_status='COMPLETED', per='INSERTED', val='VALID', dec='APPROVED', obs='UUID', obs_uuid='a', exp='UUID',
                exp_uuid='a', res='r', mat=None, op=False, rechecked=True)
    neg.append(('VERIFICADOR rejeita: controle V saudável não dispara nenhum predicado', not any(ev(p, good) for p in l10.P.values()), ''))
    pr = [p for n, p in [('prechk', F('2830H_E12P_precheck_section_b.sql'))]][0]
    mut_pre = pr.replace('WITH\n', "WITH\nx AS (SELECT internal.resolve_variant_row_axes('{}'::jsonb, NULL, NULL, NULL)),\n", 1)
    neg.append(('VERIFICADOR rejeita: precheck que chama a 2211 [P-2]', any(' P-2:' in n for n, ok, _ in pre_rules('E12P', mut_pre) if not ok), ''))
    mut_pre2 = pr.replace('WHERE v IS NULL', 'WHERE false', 1)
    neg.append(('VERIFICADOR rejeita: gate_pass tolerando NULL [P-3]', any(' P-3:' in n for n, ok, _ in pre_rules('E12P', mut_pre2) if not ok), ''))
    neg.append(('VERIFICADOR rejeita: pino P7X adulterado [R-12]', '98a97559965c2e0ff884d95155ab5d3b' not in repo_bodies('public.set_updated_at'), ''))

    def ml(label, name, mutated, rule):
        failed = [n for n, ok, _ in b12_lint.lint(name, mutated, cat) if not ok]
        neg.append((f'VERIFICADOR rejeita (lint): {label} [{rule}]', any(f' {rule}:' in n for n in failed), str(failed[:2])))
    e13 = F('2830H_E13_section_m_state_machine.sql')
    ml('parêntese a mais', 'E13', e13.replace('count(*) FILTER (WHERE src', 'count(*) FILTER ((WHERE src', 1), 'L-1')
    ml('END IF removido', 'E14', E('E14').replace('        END IF;\n', '', 1), 'L-2')
    ml('variável não declarada', 'E14', E('E14').replace('INTO v_job1;', 'INTO v_job9;', 1), 'L-3')
    ml('format() com argumento a menos', 'E14', E('E14').replace("c_env, v_case, v_state, v_msg);", "c_env, v_case, v_state);", 1), 'L-4')
    ml('SELECT INTO com alvo a mais', 'E12', e12.replace('INTO v_n, v_m, v_u8', 'INTO v_n, v_m, v_u8, v_a1', 1), 'L-5')
    ml('jsonb_build_object ímpar', 'E13', e13.replace("'st_distinct', count(DISTINCT job_status) FILTER (WHERE src = 'REAL'),", "'st_distinct',", 1), 'L-6')
    ml('tabela inexistente', 'E14', E('E14').replace('public.catalog_variant_import_job', 'public.catalog_variant_import_jobs', 1), 'L-7')
    ml('coluna inexistente no INSERT', 'E14', E('E14').replace('(card_set_id, source, external_set_id, status)', '(card_set_id, source, external_set, status)', 1), 'L-8')
    ml('função com aridade errada', 'E12', e12.replace('internal.resolve_variant_mapping_scope(b.card_set_id, v_src)', 'internal.resolve_variant_mapping_scope(b.card_set_id)', 1), 'L-9')
    ml('constraint inexistente', 'E08', E('E08').replace("'uq_card_variant_identity'", "'uq_card_variant_identidade'", 1), 'L-10')

    # mutações das regras B-5X / R12 / 2234 (resolução técnica final)
    e10 = F('2830H_E10_section_r_routing_2211.sql')
    neg.append(('VERIFICADOR rejeita: contraprova R12 enfraquecida (residual integral → NULL) [R-22]',
                not r22_ok(e10.replace('v_rst IS DISTINCT FROM v_tok6', 'v_rst IS NOT NULL', 1)), ''))
    e15m = F('2830H_E15_section5_legacy_hold.sql').replace('IF NOT COALESCE(', 'IF NOT (', 1)
    neg.append(('VERIFICADOR rejeita: impressão digital do 5.2 tolerando NULL [R-21]',
                not r21_ok(e15m, F('2830H_E15P_measure_section5.sql')), ''))
    neg.append(('VERIFICADOR rejeita: E15P adjudicando sem READY_DEF [R-21]',
                not r21_ok(F('2830H_E15_section5_legacy_hold.sql'),
                           F('2830H_E15P_measure_section5.sql').replace('false           AS g_5x_adjudicated_candidate_ok', 'true AS g_5x_adjudicated_candidate_ok', 1)), ''))
    neg.append(('VERIFICADOR rejeita: 2234 sem comparação de triggers/pg_depend na pós-condição [R-27]',
                not r27_ok(q2234.replace("IF v_dep IS DISTINCT FROM current_setting('mmkyu.p2234_dep', true) THEN", "IF false THEN", 1)), ''))
    neg.append(('VERIFICADOR rejeita: 2234 sem prova de alcance TIMESTAMPTZ [R-27]',
                not r27_ok(q2234.replace("'pg_catalog.timestamptz'::pg_catalog.regtype", "'pg_catalog.timestamp'::pg_catalog.regtype", 1)), ''))
    neg.append(('VERIFICADOR rejeita: impressão digital de A adulterada (nomeado 51 → 50) [R-28]',
                not fp_map_ok([(c, n - 1 if i == 0 else n) for i, (c, n) in enumerate(l13.MAP_NAMED)], l13.MAP_FP), ''))
    for k, bad, why in [('worlds_types', 16, 'WORLDS/ASIA 21 → 16 (leitura antiga)'),
                        ('single_types', 24, 'residual 19 → 24 tipos (tipos ≡ variantes)'),
                        ('single_n', 23, 'residual 24 → 23 variantes'),
                        ('single_non1', 0, 'duplos 5 → 0 (singletons puros)')]:
        neg.append((f'VERIFICADOR rejeita: MAP_FP {why} [R-28]', not fp_map_ok(l13.MAP_NAMED, dict(l13.MAP_FP, **{k: bad})), ''))
    e15p_real = F('2830H_E15P_measure_section5.sql')
    neg.append(('VERIFICADOR rejeita: 5.2 com single_non1 = 0 (constante antiga) [R-21]',
                not r21_ok(F('2830H_E15_section5_legacy_hold.sql').replace("_fp_single_non1')::bigint = 5", "_fp_single_non1')::bigint = 0", 1), e15p_real), ''))
    neg.append(('VERIFICADOR rejeita: E15P sem gate de unicidade de code [R-21]',
                not r21_ok(F('2830H_E15_section5_legacy_hold.sql'), e15p_real.replace('AS g_5x_type_code_unique', 'AS g_5x_type_code_uniq', 1)), ''))
    old_scope = ("""d5_scope AS (
    SELECT e.card_set_id, count(sc.*) AS n
      FROM d5_ev e
      CROSS JOIN gs
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(e.card_set_id, gs.src_id) sc ON true
     GROUP BY e.card_set_id
),""")
    cur_scope = e15p_real[e15p_real.index('d5_scope AS ('):]
    cur_scope = cur_scope[:cur_scope.index('\n),') + 3]
    neg.append(('VERIFICADOR rejeita: d5_scope por variant com count(sc.*) (cardinalidade repetida por Set) [R-31]',
                not r31_ok(e15p_real.replace(cur_scope, old_scope, 1)
                           .replace('(SELECT bool_and(n_active <= 1 AND n_fn = n_active) FROM d5_scope)', '(SELECT COALESCE(max(n), 0) <= 1 FROM d5_scope)', 1)), ''))
    neg.append(('VERIFICADOR rejeita: g_scope_unique sem conferir função × fonte (n_fn = n_active removido) [R-31]',
                not r31_ok(e15p_real.replace('bool_and(n_active <= 1 AND n_fn = n_active)', 'bool_and(n_active <= 1)', 1)), ''))
    neg.append(('VERIFICADOR rejeita: d5_scope sem DISTINCT por Card Set [R-31]',
                not r31_ok(e15p_real.replace('FROM (SELECT DISTINCT e.card_set_id FROM d5_ev e) s', 'FROM (SELECT e.card_set_id FROM d5_ev e) s', 1)), ''))
    neg.append(('VERIFICADOR rejeita: C3 sem SHOWFLAKE_HOLO na lista FINISH [R-29]',
                not r29_ok(l13.DERIV.replace(",\n           ('SHOWFLAKE_HOLO')", '', 1)), ''))
    neg.append(('VERIFICADOR rejeita: C3 sem exclusão de PROMO_STAMPED [R-29]',
                not r29_ok(l13.DERIV.replace("\n       AND vt.code <> 'PROMO_STAMPED'\n),", '\n),', 1)), ''))
    neg.append(('VERIFICADOR rejeita: C3 com regime SET_LOGO alterado (SWSH9 removido) [R-29]',
                not r29_ok(l13.DERIV.replace("cs.code NOT IN ('DP1','SWSH9','SVP'))\n       AND vt.code <> 'PROMO_STAMPED'", "cs.code NOT IN ('DP1','SVP'))\n       AND vt.code <> 'PROMO_STAMPED'", 1)), ''))

    # 2234 — estrutura integral (lint_migration); incidente BATCH12-2234-LIVE-01
    fixed_tail = "normalize_catalog_variant_import_row()'))))\n      INTO v_dep;"
    def mm(label, mutated, rule):
        failed = [n for n, ok, _ in b12_lint.lint_migration('2234', mutated, cat) if not ok]
        neg.append((f'VERIFICADOR rejeita (2234): {label} [{rule}]', mutated != q2234 and any(f' {rule}:' in n for n in failed), str(failed[:2])))
    mm("v1.1 publicada (blob c3a8cbce): ')' excedente no SELECT concat_ws do DO $post$ (42601 no LIVE)",
       q2234.replace(fixed_tail, "normalize_catalog_variant_import_row()')))))\n      INTO v_dep;", 1), 'M-1')
    mm("')' faltante no set_config do DO $pre$",
       q2234.replace("normalize_catalog_variant_import_row()'))))), true);", "normalize_catalog_variant_import_row()')))), true);", 1), 'M-1')
    mm('dollar-quote desemparelhado ($post$ → $pst$)', q2234.replace('$post$;', '$pst$;', 1), 'M-2')
    mm('RAISE com marcador a mais', q2234.replace("'2234_POSTCONDITION: % de 4 funções", "'2234_POSTCONDITION: % % de 4 funções", 1), 'M-5')

    # -------------------------------------------------------------------
    # VERIFICADOR-POS
    # -------------------------------------------------------------------
    for eid, name, _, _ in gen_all.ENVELOPES:
        r = env_rules(eid, files[name], ctx[eid])
        pos.append((f'VERIFICADOR positivo: {eid} real passa todas as regras', all(ok for _, ok, _ in r), str([n for n, ok, _ in r if not ok])))
    pos.append(('VERIFICADOR positivo: comentário citando DELETE/COMMIT não reprova',
                all(ok for n, ok, _ in env_rules('E14', E('E14').replace(pf, pf + '    -- nunca DELETE nem COMMIT aqui\n', 1)) if ' B-18:' not in n), ''))
    pos.append(('VERIFICADOR positivo: E06 (L4) reprovado pelo perfil B12 (perfis independentes)',
                not all(ok for _, ok, _ in env_rules('E11', (H / '2830H_E06_section3_routing_fail_closed.sql').read_text(encoding='utf-8'))), ''))
    for f in ['2830H_E03_section2_profile_composition.sql', '2830H_E04_section2b_2t_mapping.sql', '2830H_E05_section2q_mapping_header.sql',
              '2830H_E06_section3_routing_fail_closed.sql', '2830H_E06P_precheck_section3.sql']:
        r = b12_lint.lint(f, (H / f).read_text(encoding='utf-8'), cat)
        pos.append((f'VERIFICADOR positivo (lint): {f} (compilado e executado no LIVE) passa todas as regras', all(ok for _, ok, _ in r),
                    str([n for n, ok, _ in r if not ok])))
    for f in ['2212_backfill_staging_edition_context_key.sql', '2230_seed_edition_context_traits.sql',
              '2231_seed_edition_context_profiles.sql', '2232_seed_edition_context_external_mappings.sql',
              '2233_repair_staging_edition_context_scope_resolution.sql']:
        r = b12_lint.lint_migration(f[:4], (H.parent / f).read_text(encoding='utf-8'), cat)
        pos.append((f'VERIFICADOR positivo (lint de migration): {f} (executada no LIVE) passa M-1..M-6 e L-1..L-10', all(ok for _, ok, _ in r),
                    str([n for n, ok, _ in r if not ok])))
    return res, neg, pos


if __name__ == '__main__':
    tot_bad = 0
    for title, lst in zip(['B12-PERFIL', 'B12-VERIFICADOR-NEG', 'B12-VERIFICADOR-POS'], run()):
        bad = [r for r in lst if not r[1]]
        tot_bad += len(bad)
        for n, ok, d in lst:
            print(('PASS ' if ok else 'FAIL ') + '[' + title + '] ' + n + (' ' + d if d and not ok else ''))
        print(f'{title} TOTAL {len(lst)} PASS {len(lst) - len(bad)} FAIL {len(bad)}')
    sys.exit(1 if tot_bad else 0)
