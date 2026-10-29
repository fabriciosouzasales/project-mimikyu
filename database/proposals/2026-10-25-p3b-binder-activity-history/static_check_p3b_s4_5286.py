#!/usr/bin/env python3
"""static_check_p3b_s4_5286.py — hardening de remove_layout_page(uuid, integer) (5286).

Só leitura de arquivos locais. PASS/FAIL por critério e GATE final.

R.1  5285 intacta (SHA-256 aprovado).
R.2  Diff mínimo: removidas as linhas "-- P3B-HARDEN", o corpo da 5286 == corpo da 5285 e o
     md5(prosrc) == LIVE 5285 (e4823996…).
R.3  Só acréscimos: nenhuma linha da 5285 alterada ou removida; todas as linhas novas marcadas.
R.4  Recusa de mínimo de páginas presente, ANTES da contagem de filhos e de qualquer DELETE/E14.
R.5  Recusa de bolso fixado presente, ANTES de referências de espécie, DELETE e E14.
R.6  E14 preservado: 1 begin PAGE_REMOVED, add_item PAGE_REMOVED + PAGE_RENUMBERED, 1 end;
     ordem begin < DELETE e end após o UPDATE de renumeração; variável v_renum (5285) preservada.
R.7  Confirmação de referências de espécie (5260) inalterada.
R.8  Cabeçalho (assinatura, RETURNS, DEFINER, search_path) e REVOKE/GRANT idênticos à 5285.
R.9  Uma única função criada; sem DROP; invólucro (uuid) e funções de espaço não recriados.
R.10 Pré-check exige md5 LIVE da 5285, a 5285 no ledger e o invólucro inalterado.
R.11 Lint de colisão variável × alias (mesma regra da 5285) na 5286: 0 ocorrências.
R.12 Mensagens novas reconhecidas pela interface (lib/colecoes/binder-page-removal.ts).
R.13 Controle negativo: mutação que move a recusa de fixação para depois do DELETE é detectada.
"""
import glob, hashlib, re, sys

HERE = __file__.rsplit('/', 1)[0] if '/' in __file__ else '.'
SHA_5285 = 'ee787a7d'
MD5_5285_LIVE = 'e482399664eeb4980436372b57cf378b'
MD5_5286_EXPECTED = None  # preenchido abaixo (impresso em R.2c)
MARK = '-- P3B-HARDEN'

results = []
def check(cid, desc, ok):
    results.append((cid, desc, bool(ok)))

def read(pattern):
    path = sorted(glob.glob(f'{HERE}/{pattern}'))[0]
    with open(path, encoding='utf-8') as fh:
        return fh.read()

def fn_bodies(sql):
    return [(m.group(1), m.group(3)) for m in re.finditer(
        r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+[\s\S]*?\bAS\s+)\$(\w*)\$\n?([\s\S]*?)\$\2\$', sql, re.I)]

def prosrc(body):
    return body if body.startswith('\n') else '\n' + body

def collisions(body):
    decl = re.search(r'\bDECLARE\b([\s\S]*?)\bBEGIN\b', body, re.I)
    names = set()
    if decl:
        for line in decl.group(1).split('\n'):
            m = re.match(r'([a-z_][a-z0-9_]*)\s+(?:constant\s+)?[a-z]', line.split('--')[0].strip(), re.I)
            if m:
                names.add(m.group(1).lower())
    code = '\n'.join(l.split('--')[0] for l in body.split('\n'))
    aliases = {a.lower() for a in re.findall(r'\b(?:from|join|update|using)\s+(?:only\s+)?[a-z_][a-z0-9_.]*\s+(?:as\s+)?([a-z_][a-z0-9_]*)\b', code, re.I)}
    return names & (aliases - {'on', 'where', 'set', 'using', 'join', 'left', 'right', 'inner', 'cross', 'order', 'group', 'limit', 'with', 'and', 'or', 'for', 'loop', 'into', 'select'})

s85 = read('5285_*.sql')
s86 = read('5286_*.sql')
check('R.1', '5285 intacta (SHA-256 aprovado)', hashlib.sha256(s85.encode()).hexdigest().startswith(SHA_5285))

b85, b86 = fn_bodies(s85), fn_bodies(s86)
one = len(b85) == 1 and len(b86) == 1
body85 = b85[0][1] if one else ''
body86 = b86[0][1] if one else ''
stripped = '\n'.join(l for l in body86.split('\n') if not l.rstrip().endswith(MARK))
check('R.2a', 'uma função em cada arquivo', one)
check('R.2b', 'sem as linhas P3B-HARDEN, corpo 5286 == corpo 5285 (byte a byte)', one and stripped == body85)
check('R.2c', f'sem as linhas P3B-HARDEN, md5(prosrc) == LIVE 5285 ({MD5_5285_LIVE[:8]}…)',
      one and hashlib.md5(prosrc(stripped).encode()).hexdigest() == MD5_5285_LIVE)

l85, l86 = body85.split('\n'), body86.split('\n')
new_lines = [l for l in l86 if l.rstrip().endswith(MARK)]
check('R.3', 'só acréscimos marcados (linhas da 5285 preservadas em ordem)',
      [l for l in l86 if not l.rstrip().endswith(MARK)] == l85 and len(new_lines) > 0)

def pos(text, needle):
    return text.find(needle)
p_min = pos(body86, "a binder must keep at least one page")
p_children = pos(body86, "slot assignment(s)")
p_locked = pos(body86, "locked slot(s) — unlock them")
p_species = pos(body86, "species reference(s) — confirm")
p_begin = pos(body86, "binder_activity_begin(")
p_delete = pos(body86, "DELETE FROM public.collection_layout_slot_species_reference")
p_delpage = pos(body86, "DELETE FROM public.collection_layout_page")
check('R.4', 'mínimo de páginas: recusa presente, conta páginas do fichário travado, antes de filhos/DELETE/E14',
      p_min > 0 and 'IF v_count <= 1 THEN' in body86 and p_min < p_children < p_begin < p_delete)
check('R.5', 'bolso fixado: recusa presente (s.locked na página), antes de espécie/DELETE/E14',
      p_locked > 0 and 'AND s.locked;' in body86 and p_locked < p_species < p_begin < p_delete < p_delpage)

e14 = (body86.count("binder_activity_begin(v_layout_id, 'PAGE_REMOVED', 'FICHARIO')") == 1
       and body86.count("'PAGE', 'PAGE_REMOVED'") == 1 and body86.count("'PAGE', 'PAGE_RENUMBERED'") == 1
       and body86.count('binder_activity_end()') == 1
       and body86.rfind('SET page_number = page_number - 1') < body86.rfind('binder_activity_end()')
       and 'FOR v_renum IN' in body86 and 'v_renum.n, v_renum.n - 1' in body86)
check('R.6', 'E14 preservado (begin/itens/end, ordem e variável v_renum da 5285)', e14)

def species_block(body):
    a = body.find('-- 5b) 5260')
    z = body.find('-- E14:')
    return body[a:z]
check('R.7', 'confirmação de referências de espécie (5260) idêntica', species_block(body85) == species_block(body86) and species_block(body86) != '')

def hdr(sql):
    return re.sub(r'\s+', ' ', fn_bodies(sql)[0][0]).strip()
def acl(sql):
    return re.findall(r'(?m)^(?:REVOKE|GRANT)[^;]+;', sql)
check('R.8', 'cabeçalho e REVOKE/GRANT idênticos à 5285', one and hdr(s85) == hdr(s86) and acl(s85) == acl(s86) and len(acl(s86)) == 2)
check('R.9', 'uma função criada, sem DROP; invólucro e funções de espaço não recriados',
      len(re.findall(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION', s86, re.I)) == 1 and not re.search(r'\bDROP\b', s86, re.I)
      and not re.search(r'FUNCTION\s+public\.remove_layout_page\(\s*p_page_id\s+UUID\s*\)', s86, re.I)
      and 'FUNCTION public.close_my_binder_gap' not in s86 and 'FUNCTION public.insert_my_binder_gap' not in s86)
pre = s86[s86.index('do $pre$'):s86.index('$pre$;')]
check('R.10', 'pré-check: md5 LIVE da 5285, 5285 no ledger, invólucro inalterado',
      MD5_5285_LIVE in pre and "'5285_fix_remove_layout_page_variable_collision'" in pre and '98736e42641bb8a592f2d8e4fd40fab1' in pre)
check('R.11', 'lint de colisão variável × alias: 0 na 5286', not collisions(body86))

lib = open(f'{HERE}/../../../web/lib/colecoes/binder-page-removal.ts', encoding='utf-8').read()
check('R.12', 'interface reconhece as mensagens novas (locked slot / at least one page)',
      'locked slot' in lib and 'at least one page' in lib)

mut = body86.replace('AND s.locked;', 'AND false;')
mp = pos(mut, "locked slot(s) — unlock them")
moved = body86
blk = re.search(r'  -- P3B-HARDEN\n    -- 5a\)[\s\S]*?END IF;  -- P3B-HARDEN\n', moved)
moved = moved.replace(blk.group(0), '') if blk else moved
moved = moved.replace('    PERFORM public.binder_activity_end();', (blk.group(0) if blk else '') + '    PERFORM public.binder_activity_end();')
ml, md = pos(moved, "locked slot(s) — unlock them"), pos(moved, "DELETE FROM public.collection_layout_page")
check('R.13', 'controle negativo: recusa de fixação movida para depois do DELETE é detectada pela regra R.5',
      blk is not None and not (0 < ml < md))

MD5_5286_EXPECTED = hashlib.md5(prosrc(body86).encode()).hexdigest() if one else None
w = max(len(c[0]) for c in results)
for cid, desc, ok in results:
    print(f'{cid:<{w}}  {"PASS" if ok else "FAIL"}  {desc}')
n = sum(ok for *_, ok in results)
print(f'GATE  {"PASS" if n == len(results) else "STOP"}  {n}/{len(results)}')
print(f'md5(prosrc) 5286: {MD5_5286_EXPECTED}')
print(f'SHA-256 5286: {hashlib.sha256(s86.encode()).hexdigest()}')
sys.exit(0 if n == len(results) else 1)
