#!/usr/bin/env python3
"""static_check_p3b_s4_5285.py — P3-B S4, hotfix 5285 (colisão variável × alias em remove_layout_page).

Só leitura de arquivos locais. Saída: PASS/FAIL por critério e GATE final.

H.1  5281 intacta (SHA-256 aprovado na S4).
H.2  5285: corpo da função = corpo da 5281 com a variável do laço renomeada (r → v_renum);
     revertida a renomeação, md5 do corpo = md5 LIVE da 5281 (5ea978d5…).
H.3  Diff restrito: exatamente 3 linhas diferentes, todas marcadas "-- P3B-S4" e todas só pela renomeação.
H.4  Alias "r" de collection_layout_region preservado e sem variável homônima declarada.
H.5  Assinatura, RETURNS, SECURITY DEFINER, SET search_path, REVOKE/GRANT idênticos à 5281.
H.6  W3 preservado (1 begin, 2 add_item, 1 end) e nenhuma outra função criada/alterada.
H.7  Pré-check da 5285 exige md5 LIVE da 5281 e a 5281 no ledger.
H.8  PROTEÇÃO GERAL (lint de colisão): em 5271–5285, nenhuma variável PL/pgSQL declarada tem o
     mesmo nome de um alias de tabela usado no corpo da mesma função.
H.9  Controles negativos do lint: acusa a 5281 (defeito real) e uma mutação sintética.
H.10 md5 esperado do corpo corrigido (usado pelo pós-check) bate com o arquivo.
"""
import glob, hashlib, re, sys

HERE = __file__.rsplit('/', 1)[0] if '/' in __file__ else '.'
SHA_5281 = '1073cda8'
MD5_5281_LIVE = '5ea978d582f055fb8690f9974a2bea2f'
MD5_5285_EXPECTED = 'e482399664eeb4980436372b57cf378b'  # copiado para o pós-check

results = []
def check(cid, desc, ok):
    results.append((cid, desc, bool(ok)))

def read(pattern):
    path = sorted(glob.glob(f'{HERE}/{pattern}'))[0]
    with open(path, encoding='utf-8') as fh:
        return path, fh.read()

def fn_bodies(sql):
    """[(header, body)] de cada CREATE [OR REPLACE] FUNCTION … AS $tag$ … $tag$."""
    out = []
    for m in re.finditer(r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+[\s\S]*?\bAS\s+)\$(\w*)\$\n?([\s\S]*?)\$\2\$', sql, re.I):
        out.append((m.group(1), m.group(3)))
    return out

def prosrc(body):
    # apply_migration/PG guardam o prosrc entre os delimitadores, incluindo a quebra inicial
    return '\n' + body if not body.startswith('\n') else body

def collisions(body):
    decl = re.search(r'\bDECLARE\b([\s\S]*?)\bBEGIN\b', body, re.I)
    if not decl:
        return set()
    names = set()
    for line in decl.group(1).split('\n'):
        line = line.split('--')[0].strip()
        m = re.match(r'([a-z_][a-z0-9_]*)\s+(?:constant\s+)?[a-z]', line, re.I)
        if m:
            names.add(m.group(1).lower())
    code = '\n'.join(l.split('--')[0] for l in body.split('\n'))
    aliases = set(a.lower() for a in re.findall(
        r'\b(?:from|join|update|using)\s+(?:only\s+)?[a-z_][a-z0-9_.]*\s+(?:as\s+)?([a-z_][a-z0-9_]*)\b', code, re.I))
    aliases -= {'on', 'where', 'set', 'using', 'join', 'left', 'right', 'inner', 'cross', 'order', 'group',
                'limit', 'with', 'and', 'or', 'returning', 'for', 'loop', 'into', 'values', 'select'}
    return names & aliases

# H.1
p81, s81 = read('5281_*.sql')
check('H.1', '5281 intacta (SHA-256 aprovado)', hashlib.sha256(s81.encode()).hexdigest().startswith(SHA_5281))

# H.2/H.3
p85, s85 = read('5285_*.sql')
b81 = fn_bodies(s81); b85 = fn_bodies(s85)
ok_one = len(b81) == 1 and len(b85) == 1
body81 = b81[0][1] if ok_one else ''
body85 = b85[0][1] if ok_one else ''
reverted = body85.replace('v_renum       RECORD', 'r             RECORD').replace('FOR v_renum IN', 'FOR r IN').replace('v_renum.n', 'r.n')
check('H.2a', 'uma única função em cada arquivo', ok_one)
check('H.2b', 'revertida a renomeação, corpo 5285 == corpo 5281 (byte a byte)', ok_one and reverted == body81)
check('H.2c', f'revertida a renomeação, md5(prosrc) == LIVE 5281 ({MD5_5281_LIVE[:8]}…)',
      ok_one and hashlib.md5(prosrc(reverted).encode()).hexdigest() == MD5_5281_LIVE)
l81, l85 = body81.split('\n'), body85.split('\n')
diff = [(a, b) for a, b in zip(l81, l85) if a != b]
check('H.3a', 'mesmo número de linhas; exatamente 3 linhas diferentes', len(l81) == len(l85) and len(diff) == 3)
check('H.3b', 'linhas diferentes todas marcadas "-- P3B-S4" e só pela renomeação r → v_renum',
      all(a.rstrip().endswith('-- P3B-S4') and b.rstrip().endswith('-- P3B-S4') and 'v_renum' in b and 'v_renum' not in a
          for a, b in diff))

# H.4
check('H.4a', 'alias "r" de collection_layout_region preservado na 5285',
      re.search(r'FROM public\.collection_layout_region r\s*\n\s*WHERE r\.page_id = p_page_id;', body85) is not None)
check('H.4b', 'nenhuma variável "r" declarada na 5285', 'r' not in collisions(body85) and
      not re.search(r'^\s+r\s+RECORD', body85, re.M))

# H.5
def sig(sql):
    hdr = fn_bodies(sql)[0][0]
    return re.sub(r'\s+', ' ', hdr).strip()
def acl(sql):
    return re.findall(r'(?m)^(?:REVOKE|GRANT)[^;]+;', sql)
check('H.5a', 'cabeçalho (assinatura, RETURNS, LANGUAGE, SECURITY DEFINER, SET) idêntico à 5281', sig(s81) == sig(s85))
check('H.5b', 'REVOKE/GRANT idênticos à 5281', acl(s81) == acl(s85) and len(acl(s85)) == 2)

# H.6
check('H.6a', 'W3 preservado: 1 begin, 2 add_item, 1 end',
      body85.count('binder_activity_begin(') == 1 and body85.count('binder_activity_add_item(') == 2
      and body85.count('binder_activity_end(') == 1)
check('H.6b', 'nenhuma outra função criada/alterada; sem DROP',
      len(re.findall(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION', s85, re.I)) == 1 and not re.search(r'\bDROP\b', s85, re.I))

# H.7
pre = s85[s85.index('do $pre$'):s85.index('$pre$;')]
check('H.7', 'pré-check exige md5 LIVE da 5281 e a 5281 no ledger',
      MD5_5281_LIVE in pre and "'5281_instrument_remove_layout_page'" in pre and 'raise exception' in pre)

# H.8 — lint de colisão em toda a família P3-B instrumentada
files = sorted(glob.glob(f'{HERE}/527[1-9]_*.sql') + glob.glob(f'{HERE}/528[0-5]_*.sql'))
offenders = []
for f in files:
    if f.endswith(tuple(['5281_instrument_remove_layout_page.sql'])):
        continue  # defeito conhecido, superado pela 5285 (ver H.9a)
    with open(f, encoding='utf-8') as fh:
        for _, body in fn_bodies(fh.read()):
            c = collisions(body)
            if c:
                offenders.append((f.rsplit('/', 1)[-1], sorted(c)))
check('H.8', f'lint de colisão variável × alias: 0 ocorrências em {len(files) - 1} arquivos (5271–5285 exceto 5281)', not offenders)
for o in offenders:
    print('   colisão:', o)

# H.9 — controles negativos
check('H.9a', 'lint ACUSA a 5281 (variável "r" × alias "r")', 'r' in collisions(body81))
mut = body85.replace('v_renum       RECORD;', 'p             RECORD;')
check('H.9b', 'lint ACUSA mutação sintética (variável "p" × alias "p" de collection_layout_page)', 'p' in collisions(mut))

# H.10
md5_new = hashlib.md5(prosrc(body85).encode()).hexdigest()
check('H.10', f'md5(prosrc) da 5285 = esperado do pós-check ({MD5_5285_EXPECTED[:8]}…)', md5_new == MD5_5285_EXPECTED)

width = max(len(c[0]) for c in results)
for cid, desc, ok in results:
    print(f'{cid:<{width}}  {"PASS" if ok else "FAIL"}  {desc}')
n_ok = sum(ok for _, _, ok in results)
print(f'GATE  {"PASS" if n_ok == len(results) else "STOP"}  {n_ok}/{len(results)}')
print(f'SHA-256 5285: {hashlib.sha256(s85.encode()).hexdigest()}')
sys.exit(0 if n_ok == len(results) else 1)
