#!/usr/bin/env python3
# P14A — comparador LIVE x CN1 (BATCH12-P14A-LIVE-CAPTURE-READINESS-02), alinhado a
# P14A_FINGERPRINT.sql md5 2738566c55f7a4792159362ce29bb3e0.
# Uso: python3 p14a_compare.py <cn1.csv> <live.(csv|json)>
#   live.json = corpo JSON da resposta MCP (array) ou invólucro {"result": "..."}.
# Determinístico, sem banco, sem escrita. Critérios FIXOS (não adaptativos).
#
# Pré-condição do baseline CN1 (falha => INVALID_BASELINE):
#   31 ITEM; 27 PRESENT; 4 ABSENT_OK; 0 outro status; agregados recalculados = reportados.
# Integridade da saída LIVE (falha => STOP_DIVERGENT):
#   agregados recalculados com a fórmula do SQL = agregados reportados pela própria saída.
# Classes por item (chave = obj_type, obj_schema, obj_table, obj_name, obj_signature):
#   EXACT        colunas do instrumento iguais e status/found_count/flags/def_bytes/has_cr/md5_raw/md5_lf iguais
#   EOL_ONLY     só FUNCTION, status igual: md5_raw difere, md5_lf igual, flags iguais
#   RENDER_ONLY  só INDEX/CONSTRAINT/TRIGGER, status igual: definição e flags iguais após remover "public."
#   MISSING      item do CN1 ausente na saída, ou status LIVE = MISSING
#   EXTRA        linha ITEM com status EXTRA ou chave fora do baseline
#   DIVERGENT    qualquer outra diferença (DUPLICATE, UNEXPECTED_PRESENT, md5_lf, definição, flags,
#                ou colunas constantes do instrumento — provenance/expectation — divergentes)
# VERDICT:
#   PASS_EXACT                  31/31 EXACT, contexto igual, agregados iguais e íntegros
#   STOP_DIVERGENT              algum DIVERGENT/MISSING/EXTRA ou agregado incoerente/não íntegro
#   STOP_REQUIRES_ADJUDICATION  só EOL_ONLY e/ou RENDER_ONLY e/ou contexto diferente
# EOL_ONLY e RENDER_ONLY nunca viram PASS aqui.
import csv, io, json, re, sys, hashlib

CN1_MD5 = '07cbe1369cf2768f00a72f17bd5dfdb3'  # P14A_CN1_OUTPUT.csv preservado (CN1-4-P14A-LOCAL)
KEY = ('obj_type', 'obj_schema', 'obj_table', 'obj_name', 'obj_signature')
INSTR = ('provenance', 'expectation')

def norm(v):
    if v is None: return ''
    if isinstance(v, bool): return 'true' if v else 'false'
    return str(v)

def load(path):
    t = open(path, 'rb').read().decode('utf-8-sig')
    s = t.lstrip()
    if s.startswith('{') or s.startswith('['):
        j = json.loads(s)
        if isinstance(j, dict) and 'result' in j:
            m = re.search(r'<untrusted-data-([0-9a-f-]+)>\n(.*)\n</untrusted-data-\1>', j['result'], re.S)
            j = json.loads(m.group(2))
        return [{k: norm(v) for k, v in r.items()} for r in j]
    return [{k: norm(v) for k, v in r.items()} for r in csv.DictReader(io.StringIO(t))]

def agg_formula(items, col):
    # = md5(string_agg(concat_ws('|', obj_type, obj_schema, obj_table, obj_name, obj_signature,
    #        expectation, found_count, status, flags, <col>), E'\n' ORDER BY sk, obj_table, obj_name))
    it = sorted(items, key=lambda r: (int(r['sort_key']), r['obj_table'], r['obj_name']))
    s = '\n'.join('|'.join([r['obj_type'], r['obj_schema'], r['obj_table'], r['obj_name'], r['obj_signature'],
                            r['expectation'], r['found_count'], r['status'], r['flags'], r[col]]) for r in it)
    return hashlib.md5(s.encode()).hexdigest()

def reported(R, name, col):
    r = next((x for x in R if x.get('row_kind') == 'AGGREGATE' and x.get('obj_name') == name), None)
    return (r[col], r['found_count']) if r else (None, None)

def flags(s):
    return dict(x.split('=', 1) for x in s.split() if '=' in x) if s else {}

def unq(s):
    return re.sub(r'\bpublic\.', '', s or '')

def classify(c, l):
    if c['sort_key'] != l['sort_key']:
        return 'DIVERGENT', f"sort_key {c['sort_key']} -> {l['sort_key']}"
    if any(c[k] != l[k] for k in INSTR):
        return 'DIVERGENT', 'colunas do instrumento diferentes (provenance/expectation)'
    if l['status'] == 'MISSING':
        return 'MISSING', 'status MISSING na saída'
    if l['status'] == 'EXTRA':
        return 'EXTRA', 'status EXTRA'
    if c['status'] != l['status'] or c['found_count'] != l['found_count']:
        return 'DIVERGENT', f"status {c['status']}/{c['found_count']} -> {l['status']}/{l['found_count']}"
    same = all(c[k] == l[k] for k in ('flags', 'def_bytes', 'has_cr', 'md5_raw', 'md5_lf', 'definition'))
    if same:
        return 'EXACT', ''
    if c['obj_type'] == 'FUNCTION':
        if c['md5_lf'] == l['md5_lf'] and c['md5_raw'] != l['md5_raw'] and c['flags'] == l['flags']:
            return 'EOL_ONLY', f"raw {c['md5_raw']} -> {l['md5_raw']}; lf igual; has_cr {c['has_cr']} -> {l['has_cr']}; bytes {c['def_bytes']} -> {l['def_bytes']}"
        return 'DIVERGENT', f"md5_lf {c['md5_lf']} -> {l['md5_lf']}"
    if c['definition'] and l['definition'] and c['definition'] != l['definition'] or c['flags'] != l['flags']:
        fc = {k: unq(v) for k, v in flags(c['flags']).items()}
        fl = {k: unq(v) for k, v in flags(l['flags']).items()}
        if unq(c['definition']) == unq(l['definition']) and fc == fl:
            return 'RENDER_ONLY', 'difere só pela qualificação public.'
    return 'DIVERGENT', f"md5 {c['md5_raw']} -> {l['md5_raw']}"

SHAPE_FIXED = {('CONTEXT', 'session'): '90001', ('AGGREGATE', 'agg_raw'): '90002', ('AGGREGATE', 'agg_lf'): '90003'}

def shape_problems(R):
    # Formato exato do P14A_FINGERPRINT.sql: 31 ITEM + 1 CONTEXT(session) + 2 AGGREGATE(agg_raw, agg_lf) = 34;
    # sort_key estruturais fixos e sort_key únicos nas 34 linhas. Nenhuma "primeira ocorrência" silenciosa.
    p = []
    kinds = {}
    for r in R: kinds[r.get('row_kind')] = kinds.get(r.get('row_kind'), 0) + 1
    if set(kinds) - {'ITEM', 'CONTEXT', 'AGGREGATE'}: p.append(f'row_kind inesperado: {sorted(set(kinds) - {"ITEM", "CONTEXT", "AGGREGATE"}, key=str)}')
    if kinds.get('ITEM', 0) != 31: p.append(f"ITEM={kinds.get('ITEM', 0)} (esperado 31)")
    if kinds.get('CONTEXT', 0) != 1: p.append(f"CONTEXT={kinds.get('CONTEXT', 0)} (esperado 1)")
    if kinds.get('AGGREGATE', 0) != 2: p.append(f"AGGREGATE={kinds.get('AGGREGATE', 0)} (esperado 2)")
    if len(R) != 34: p.append(f'total={len(R)} (esperado 34)')
    for (kind, name), sk in SHAPE_FIXED.items():
        hits = [r for r in R if r.get('row_kind') == kind and r.get('obj_name') == name]
        if len(hits) != 1: p.append(f'{kind}/{name}: {len(hits)} linhas (esperado 1)')
        elif hits[0].get('sort_key') != sk: p.append(f"{kind}/{name}: sort_key {hits[0].get('sort_key')} (esperado {sk})")
    unknown = [r.get('obj_name') for r in R if r.get('row_kind') in ('CONTEXT', 'AGGREGATE') and (r.get('row_kind'), r.get('obj_name')) not in SHAPE_FIXED]
    if unknown: p.append(f'CONTEXT/AGGREGATE desconhecido: {unknown}')
    sks = [r.get('sort_key') for r in R]
    dup = sorted({s for s in sks if sks.count(s) > 1}, key=str)
    if dup: p.append(f'sort_key duplicado: {dup}')
    return p

def main(cn1_path, live_path):
    pin = hashlib.md5(open(cn1_path, 'rb').read()).hexdigest()
    if pin != CN1_MD5:
        print(f'baseline md5 {pin} != pino {CN1_MD5}'); print('VERDICT: INVALID_BASELINE'); return 'INVALID_BASELINE'
    C, L = load(cn1_path), load(live_path)
    bp = shape_problems(C)
    if bp:
        print(f'baseline shape: {bp}'); print('VERDICT: INVALID_BASELINE'); return 'INVALID_BASELINE'
    citems = [r for r in C if r['row_kind'] == 'ITEM']
    st = {}
    for r in citems: st[r['status']] = st.get(r['status'], 0) + 1
    base_ok = (len(citems) == 31 and st == {'PRESENT': 27, 'ABSENT_OK': 4}
               and agg_formula(citems, 'md5_raw') == reported(C, 'agg_raw', 'md5_raw')[0]
               and agg_formula(citems, 'md5_lf') == reported(C, 'agg_lf', 'md5_lf')[0])
    print(f'baseline_cn1: items={len(citems)} status={st} agg_recomputed_ok={base_ok}')
    if not base_ok:
        print('VERDICT: INVALID_BASELINE'); return 'INVALID_BASELINE'
    ci = {tuple(r[k] for k in KEY): r for r in citems}
    litems = [r for r in L if r.get('row_kind') == 'ITEM']
    li, extra = {}, []
    for r in litems:
        k = tuple(r.get(x, '') for x in KEY)
        if k in ci and k not in li: li[k] = r
        else: extra.append(k)
    for r in L:
        if r.get('row_kind') not in ('ITEM', 'CONTEXT', 'AGGREGATE'):
            extra.append((r.get('row_kind'),))
    res = []
    for k, c in sorted(ci.items(), key=lambda kv: int(kv[1]['sort_key'])):
        if k not in li: res.append((c['sort_key'], k, 'MISSING', 'linha ausente')); continue
        cls, why = classify(c, li[k]); res.append((c['sort_key'], k, cls, why))
    for k in extra: res.append(('-', k + ('',) * (5 - len(k)), 'EXTRA', 'fora do baseline'))
    ctx = lambda R: next(((x['flags'], x['definition']) for x in R if x.get('row_kind') == 'CONTEXT'), None)
    ctx_eq = ctx(C) is not None and ctx(C) == ctx(L)
    live_integrity = bool(litems) and \
        agg_formula(litems, 'md5_raw') == reported(L, 'agg_raw', 'md5_raw')[0] and \
        agg_formula(litems, 'md5_lf') == reported(L, 'agg_lf', 'md5_lf')[0] and \
        reported(L, 'agg_raw', 'md5_raw')[1] == str(len(litems)) and \
        reported(L, 'agg_lf', 'md5_lf')[1] == str(len(litems))
    a = {n: (reported(C, n, col)[0], reported(L, n, col)[0]) for n, col in (('agg_raw', 'md5_raw'), ('agg_lf', 'md5_lf'))}
    counts = {}
    for _, _, cls, _ in res: counts[cls] = counts.get(cls, 0) + 1
    all_exact = counts == {'EXACT': 31}
    only_eol = set(counts) <= {'EXACT', 'EOL_ONLY'}
    agg_incoherent = (all_exact and a['agg_raw'][0] != a['agg_raw'][1]) or \
                     (only_eol and a['agg_lf'][0] != a['agg_lf'][1])
    lp = shape_problems(L)
    print(f'live_shape_ok={not lp} {lp if lp else ""}')
    if lp or any(c in counts for c in ('DIVERGENT', 'MISSING', 'EXTRA')) or not live_integrity or agg_incoherent:
        verdict = 'STOP_DIVERGENT'
    elif all_exact and ctx_eq and a['agg_raw'][0] == a['agg_raw'][1] and a['agg_lf'][0] == a['agg_lf'][1]:
        verdict = 'PASS_EXACT'
    else:
        verdict = 'STOP_REQUIRES_ADJUDICATION'
    print(f'live: items={len(litems)} matched={len(li)} extra={len(extra)} agg_integrity={live_integrity}')
    print(f'counts={counts}')
    print(f'context_equal={ctx_eq} cn1={ctx(C)!r} live={ctx(L)!r}')
    for n, (x, y) in a.items(): print(f'{n}: cn1={x} live={y} equal={x == y}')
    for sk, k, cls, why in res:
        print(f'{sk:>6} {cls:<11} {k[0]:<10} {k[1]}.{k[2]} {k[3]} ({k[4]}) {why}')
    print('VERDICT:', verdict)
    return verdict

EXIT = {'PASS_EXACT': 0, 'STOP_REQUIRES_ADJUDICATION': 2, 'STOP_DIVERGENT': 3, 'INVALID_BASELINE': 4}

if __name__ == '__main__':
    # Fail-closed: só PASS_EXACT retorna 0; veredito desconhecido -> 3; exceção de parsing/IO -> 5.
    try:
        v = main(sys.argv[1], sys.argv[2])
    except Exception as e:
        print(f'ERRO: {type(e).__name__}: {e}'); print('VERDICT: ERROR'); sys.exit(5)
    sys.exit(EXIT.get(v, 3))
