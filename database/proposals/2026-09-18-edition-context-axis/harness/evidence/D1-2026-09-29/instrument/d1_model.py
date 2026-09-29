# Modelo lógico OFFLINE do instrumento D1 (sem SQL, sem banco).
# Objetivo: demonstrar (a) que os gates reproduzem a partição de 19/09 num
# universo sintético fiel às composições; (b) que trocas compensadas preservam
# TODAS as contagens e só são detectadas pelos digests por id; (c) que mutações
# do próprio instrumento quebram gates.
# Uso: python3 d1_model.py <D1-ID-IDENTITY.sql> <dir_evidence>
import hashlib, json, pathlib, random, re, sys, uuid, copy

SQL = pathlib.Path(sys.argv[1]).read_text()
EV = pathlib.Path(sys.argv[2])

# --- 1. Constantes lidas do PRÓPRIO instrumento (VALUES) --------------------
def values(name):
    m = re.search(rf"{name}\([^)]*\) AS \(\s*VALUES (.*?)\n\)", SQL, re.S)
    return re.findall(r"\(([^()]*)\)", m.group(1))
def tup(s): return [x.strip().strip("'") for x in s.split(',')]
FIN = {tup(x)[0] for x in values('h_finish')}
H_READY = {c: int(n) for c, n in map(tup, values('h_ready'))}
H_HOLD = {k: int(n) for k, n in map(tup, values('h_hold'))}
H_NC = {k: int(n) for k, n in map(tup, values('h_nc'))}
H_H6 = {c: (int(p) > 0, int(v) > 0) for c, p, v in map(tup, values('h_h6'))}

# --- 2. Re-derivação independente a partir da evidência bruta ----------------
def rows(p):
    o = json.loads(p.read_text())['result']; a = o.index('\n[{'); b = o.rindex('}]') + 2
    return json.loads(o[a + 1:b])
cen = {r['code']: r for r in rows(EV / 'census_19-09_original/census_raw_response_2026-09-19T01-27-53Z.txt')}
sl = {x['code']: dict((q.split(':')[0], int(q.split(':')[1])) for q in x['por_set'].split())
      for x in rows(EV / 'census_19-09_original/setlogo_by_set_raw_response_2026-09-19T01-37-39Z.txt')}
EX = {f'EX{i}' for i in range(7, 17)}; OK = {'DP1', 'SWSH9', 'SVP'}
assert len(FIN) == 28
assert {k: v for k, v in json.loads((EV / 'c3_expected_from_raw_19-09.json').read_text()).items() if v > 0} == H_READY
assert H_HOLD == {'PROMO_STAMPED': cen['PROMO_STAMPED']['variants'],
                  **{f'{c}@{s}': n for c, d in sl.items() for s, n in d.items() if s not in EX and s not in OK}}
assert H_NC == {f'{c}@{s}': n for c, d in sl.items() for s, n in d.items() if s in EX}
# D2: composição por tipo do HOLD de referência
by_t = {}
for k, n in H_HOLD.items(): by_t[k.split('@')[0]] = by_t.get(k.split('@')[0], 0) + n
assert by_t == {'PROMO_STAMPED': 33, 'SET_LOGO_REVERSE': 59, 'SET_LOGO_STANDARDS': 11,
                'SET_LOGO_COSMOS_HOLO': 3, 'SET_LOGO_STAFF_HOLO': 1}, by_t

# --- 3. Universo sintético fiel às composições -------------------------------
rng = random.Random(20260928)
def nid(): return str(uuid.UUID(int=rng.getrandbits(128), version=4))
DB = []  # (id, type_code, set_code)
for c in FIN:
    DB += [(nid(), c, 'BASE') for _ in range(cen[c]['variants'])]
for c, n in H_READY.items():   # SET_LOGO% READY só existe em DP1/SWSH9/SVP
    DB += [(nid(), c, 'SVP' if c.startswith('SET_LOGO') else 'PROMOSET') for _ in range(n)]
for k, n in H_HOLD.items():
    c, s = (k.split('@') + ['PROMOSET'])[:2]
    DB += [(nid(), c, s) for _ in range(n)]
for k, n in H_NC.items():
    c, s = k.split('@'); DB += [(nid(), c, s) for _ in range(n)]
PRICING = {'pscid': {'STAFF_HOLO': 17, 'SET_LOGO_REVERSE': 1}, 'psvm': {'STAFF_HOLO': 1}}
EXRE = re.compile(r'^EX(7|8|9|10|11|12|13|14|15|16)$')

# --- 4. Predicados (espelho do d1_cv) ----------------------------------------
def P_base(c, s):
    sl_ = c.startswith('SET_LOGO')
    return dict(
        finish=c in FIN,
        hold=c == 'PROMO_STAMPED' or (sl_ and not EXRE.match(s) and s not in OK),
        nc=sl_ and bool(EXRE.match(s)),
        ready=(c not in FIN and not (sl_ and EXRE.match(s)) and not (sl_ and s not in OK)
               and c != 'PROMO_STAMPED'))

def md5ids(ids): return hashlib.md5(','.join(sorted(ids)).encode()).hexdigest()
# Nota: ORDER BY uuid no PG ordena pelos 16 bytes; para UUID em texto minúsculo
# canônico a ordem lexicográfica coincide. O modelo usa sorted(str).

def run(db, pricing, P=P_base, plan_excl=('STAFF_HOLO', 'SET_LOGO_REVERSE')):
    cls = [(i, c, s, P(c, s)) for i, c, s in db]
    ready = [(i, c) for i, c, s, f in cls if f['ready']]
    hold = [(i, c, s) for i, c, s, f in cls if f['hold']]
    nc = [(i, c, s) for i, c, s, f in cls if f['nc']]
    pr = lambda c: (pricing['pscid'].get(c, 0) > 0, pricing['psvm'].get(c, 0) > 0)
    plan_c = {i for i, c in ready if c not in plan_excl}
    plan_d = {i for i, c in ready if pr(c) == (False, False)}
    cond = [(i, c) for i, c in ready if pr(c) != (False, False)]
    cnt = lambda it: {k: sum(1 for x in it if x == k) for k in set(it)}
    rbt = cnt([c for _, c in ready])
    hbk = cnt([c if c == 'PROMO_STAMPED' else f'{c}@{s}' for _, c, s in hold])
    nbk = cnt([f'{c}@{s}' for _, c, s in nc])
    h6 = {c: pr(c) for c in rbt if pr(c) != (False, False)}
    code_of = dict((i, c) for i, c in ready)
    n_fin = sum(1 for *_, f in cls if f['finish'])
    m = dict(cv_total=len(db), n_finish=n_fin, n_uraw=len(db) - n_fin,
             n_ready=len(ready), n_hold=len(hold), n_nc=len(nc),
             n_bad=sum(1 for *_, f in cls if sum(map(bool, f.values())) != 1),
             n_cond=len(cond), n_cond_sh=sum(1 for _, c in cond if c == 'STAFF_HOLO'),
             n_cond_slr=sum(1 for _, c in cond if c == 'SET_LOGO_REVERSE'),
             n_plan=len(plan_c),
             plan_x_pscid=sum(1 for i in plan_c if pr(code_of[i])[0]),
             plan_x_psvm=sum(1 for i in plan_c if pr(code_of[i])[1]),
             plan_symdiff=len(plan_c ^ plan_d),
             plan_x_hold=len(plan_c & {i for i, *_ in hold}))
    g = dict(
        g_universe_19_09=m['cv_total'] == 24893 and m['n_finish'] == 23866,
        g_uraw_1027=m['n_uraw'] == 1027,
        g_partition_counts=(m['n_ready'], m['n_hold'], m['n_nc']) == (365, 107, 555)
                           and m['n_ready'] + m['n_hold'] + m['n_nc'] == m['n_uraw'],
        g_partition_exact=m['n_bad'] == 0,
        g_ready_by_type_19_09=rbt == H_READY,
        g_hold_by_type_set_19_09=hbk == H_HOLD,
        g_nc_by_type_set_19_09=nbk == H_NC,
        g_h6_types=h6 == H_H6,
        g_conditioned_80_40_40=(m['n_cond'], m['n_cond_sh'], m['n_cond_slr']) == (80, 40, 40),
        g_plan_contract_285=m['n_plan'] == 285,
        g_plan_x_pscid_zero=m['plan_x_pscid'] == 0,
        g_plan_x_psvm_zero=m['plan_x_psvm'] == 0,
        g_plan_equivalence=m['plan_symdiff'] == 0 and md5ids(plan_c) == md5ids(plan_d),
        g_plan_x_hold_zero=m['plan_x_hold'] == 0)
    dig = dict(hold=md5ids(i for i, *_ in hold), plan=md5ids(plan_c),
               ready=md5ids(i for i, _ in ready), cond=md5ids(i for i, _ in cond))
    return g, dig, m

def pick(db, c, s=None, k=0):
    return [n for n, (i, cc, ss) in enumerate(db) if cc == c and (s is None or ss == s)][k]

g0, d0, m0 = run(DB, PRICING)
assert all(g0.values()), g0
print('BASE  gate_pass=True  digests capturados (sintéticos):', {k: v[:8] for k, v in d0.items()})

# --- 5. Cenários ---------------------------------------------------------------
def scenario(name, db=None, pricing=None, **kw):
    g, d, m = run(db if db is not None else DB, pricing or PRICING, **kw)
    failed = [k for k, v in g.items() if not v]
    changed = [k for k in d if d[k] != d0[k]]
    print(f'{name:<52} gates_FAIL={failed or "—"}  digests_MUDAM={changed or "—"}')
    return failed, changed

res = {}
# CP-1: 1 PROMO_STAMPED (HOLD) ↔ 1 REWARDS_HOLO (READY/plano) — troca de tipo
db = copy.copy(DB); a = pick(db, 'PROMO_STAMPED'); b = pick(db, 'REWARDS_HOLO')
db[a] = (db[a][0], 'REWARDS_HOLO', db[a][2]); db[b] = (db[b][0], 'PROMO_STAMPED', db[b][2])
res['CP-1'] = scenario('CP-1 troca de tipo PROMO_STAMPED↔REWARDS_HOLO', db)
# CP-2: SLR@SV8.5 (HOLD) ↔ SLR@SVP (READY condicionado) — troca de Set
db = copy.copy(DB); a = pick(db, 'SET_LOGO_REVERSE', 'SV8.5'); b = pick(db, 'SET_LOGO_REVERSE', 'SVP')
db[a] = (db[a][0], 'SET_LOGO_REVERSE', 'SVP'); db[b] = (db[b][0], 'SET_LOGO_REVERSE', 'SV8.5')
res['CP-2'] = scenario('CP-2 troca de Set SLR SV8.5↔SVP', db)
# CP-2b: SLS@SV5 (HOLD) ↔ SLS@SVP (READY, NO plano) — troca de Set que atinge o plano
db = copy.copy(DB); a = pick(db, 'SET_LOGO_STANDARDS', 'SV5'); b = pick(db, 'SET_LOGO_STANDARDS', 'SVP')
db[a] = (db[a][0], 'SET_LOGO_STANDARDS', 'SVP'); db[b] = (db[b][0], 'SET_LOGO_STANDARDS', 'SV5')
res['CP-2b'] = scenario('CP-2b troca de Set SLS SV5↔SVP (plano)', db)
# CP-5a: SLS@EX11 → SV1 (sem evidência) e SLS@SV5 → EX12 — totais 107/555 preservados
db = copy.copy(DB); a = pick(db, 'SET_LOGO_STANDARDS', 'EX11'); b = pick(db, 'SET_LOGO_STANDARDS', 'SV5')
db[a] = (db[a][0], 'SET_LOGO_STANDARDS', 'SV1'); db[b] = (db[b][0], 'SET_LOGO_STANDARDS', 'EX12')
res['CP-5a'] = scenario('CP-5a EX↔HOLD para Sets sem evidência', db)
# CP-5b: troca pura SLS@EX11 ↔ SLS@SV5 — mapas por (tipo,Set) preservados
db = copy.copy(DB); a = pick(db, 'SET_LOGO_STANDARDS', 'EX11'); b = pick(db, 'SET_LOGO_STANDARDS', 'SV5')
db[a] = (db[a][0], 'SET_LOGO_STANDARDS', 'SV5'); db[b] = (db[b][0], 'SET_LOGO_STANDARDS', 'EX11')
res['CP-5b'] = scenario('CP-5b troca pura EX11↔SV5 (mesmas chaves)', db)
# CP-4: REWARDS_HOLO ganha psvm (tipo READY invasor)
res['CP-4'] = scenario('CP-4 REWARDS_HOLO ganha psvm', pricing={'pscid': PRICING['pscid'],
                        'psvm': {**PRICING['psvm'], 'REWARDS_HOLO': 1}})
# CP-6: 1 variante nova (INSERT) e 1 removida (DELETE) no mesmo tipo do plano
db = copy.copy(DB); b = pick(db, 'REWARDS_HOLO'); db[b] = (nid(), 'REWARDS_HOLO', 'PROMOSET')
res['CP-6'] = scenario('CP-6 DELETE+INSERT compensado (REWARDS_HOLO)', db)
# CP-7: STAFF_HOLO (READY condicionado) ↔ HOLO (FINISH) — troca de tipo entre as
# duas variantes; contagens por tipo, 80/40/40 e 285 preservadas; HOLD e plano intocados
db = copy.copy(DB); a = pick(db, 'STAFF_HOLO'); b = pick(db, 'HOLO')
db[a] = (db[a][0], 'HOLO', db[a][2]); db[b] = (db[b][0], 'STAFF_HOLO', db[b][2])
res['CP-7'] = scenario('CP-7 troca STAFF_HOLO(cond)↔HOLO(FINISH)', db)
# Mutações do instrumento
def P_no_promo(c, s): f = P_base(c, s); f['hold'] = f['hold'] and c != 'PROMO_STAMPED'; return f
res['M-1'] = scenario('M-1 HOLD sem PROMO_STAMPED', P=P_no_promo)
def P_hold_no_ok(c, s):
    f = P_base(c, s); f['hold'] = c == 'PROMO_STAMPED' or (c.startswith('SET_LOGO') and not EXRE.match(s)); return f
res['M-2'] = scenario('M-2 HOLD sem exceção DP1/SWSH9/SVP', P=P_hold_no_ok)
res['M-3'] = scenario('M-3 plano exclui só STAFF_HOLO', plan_excl=('STAFF_HOLO',))
db = copy.copy(DB); db.append((nid(), 'SET_LOGO_REVERSE', 'SV10'))
res['M-4'] = scenario('M-4 +1 SLR@SV10 (deriva de dado)', db)

# --- 6. Asserções da demonstração ------------------------------------------------
F, C = 0, 1
assert res['CP-1'][F] == [] and set(res['CP-1'][C]) == {'hold', 'plan', 'ready'}
assert res['CP-2'][F] == [] and set(res['CP-2'][C]) == {'hold', 'ready', 'cond'}   # HOLD já detecta
assert res['CP-2b'][F] == [] and set(res['CP-2b'][C]) == {'hold', 'plan', 'ready'}
assert 'g_hold_by_type_set_19_09' in res['CP-5a'][F] and 'g_nc_by_type_set_19_09' in res['CP-5a'][F]
assert res['CP-5b'][F] == [] and res['CP-5b'][C] == ['hold']
assert {'g_h6_types', 'g_plan_x_psvm_zero', 'g_plan_equivalence'} <= set(res['CP-4'][F])
assert res['CP-6'][F] == [] and set(res['CP-6'][C]) == {'plan', 'ready'}
assert res['CP-7'][F] == [] and set(res['CP-7'][C]) == {'ready', 'cond'}   # HOLD e PLAN inalterados
assert 'g_partition_exact' in res['M-1'][F]
assert 'g_partition_exact' in res['M-2'][F]
assert {'g_plan_contract_285', 'g_plan_x_pscid_zero', 'g_plan_equivalence'} <= set(res['M-3'][F])
assert 'g_hold_by_type_set_19_09' in res['M-4'][F] and 'g_universe_19_09' in res['M-4'][F]
print('MODELO: todas as asserções PASS')
