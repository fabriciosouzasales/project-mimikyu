# B12 — lint estrutural e de nomes (substituto DECLARADO de compilação).
# Não existe parser PostgreSQL/PL-pgSQL no ambiente (sem servidor, sem
# pglast/libpg_query, registry bloqueado). Este lint NÃO prova que o SQL
# compila; prova, sobre o texto, as classes de erro abaixo, e é calibrado
# contra E03–E06, que compilaram e rodaram no LIVE (controle positivo).
#   L-1  parênteses balanceados fora de literal/comentário
#   L-2  BEGIN/END, IF/END IF e CASE/END pareados (PL/pgSQL + SQL)
#   L-3  toda variável v_*/c_* usada está declarada no DECLARE do DO
#   L-4  format(): nº de %s = nº de argumentos após o molde
#   L-5  SELECT … INTO: nº de expressões da lista = nº de alvos
#   L-6  jsonb_build_object: nº par de argumentos e <= 100 (FUNC_MAX_ARGS)
#   L-7  public.<tabela> existe no DDL do repositório
#   L-8  <alias>.<coluna> e colunas de INSERT/UPDATE existem na tabela
#   L-9  internal./public.<função>( existe no DDL, com a aridade usada
#   L-10 nomes de constraint/índice citados como literal existem no DDL
# Catálogo = DDL do repositório (schema/, functions/, migrations/, proposals
# 22xx executadas). Superconjunto do LIVE em nomes de objeto; divergência
# LIVE × repositório não é detectável aqui.
import re, pathlib, sys

G = pathlib.Path(__file__).resolve().parent
H = G.parent.parent
DB = H.parent.parent.parent
EC = H.parent


def strip_comments(t):
    out, i, n = [], 0, len(t)
    while i < n:
        if t.startswith('--', i):
            j = t.find('\n', i)
            i = n if j < 0 else j
            continue
        if t[i] == "'":
            j = i + 1
            while j < n:
                if t[j] == "'" and (j + 1 >= n or t[j + 1] != "'"):
                    break
                j += 2 if t[j] == "'" else 1
            out.append(t[i:j + 1]); i = j + 1
            continue
        out.append(t[i]); i += 1
    return ''.join(out)


def nolit(t):
    return re.sub(r"'(?:[^']|'')*'", "''", t)


# ---------------------------------------------------------------------------
# catálogo a partir do DDL do repositório
# ---------------------------------------------------------------------------
def build_catalog():
    files = sorted(list((DB / 'schema').glob('*.sql')) + list((DB / 'functions').glob('*.sql'))
                   + list((DB / 'migrations').glob('*.sql')) + list(EC.glob('22*.sql')))
    tables, cons, idx, funcs = {}, set(), set(), {}
    for f in files:
        t = nolit(strip_comments(f.read_text(encoding='utf-8', errors='replace').replace('\r\n', '\n')))
        for m in re.finditer(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.(\w+)\s*\((.*?)\n\);', t, re.S | re.I):
            cols = tables.setdefault(m.group(1).lower(), set())
            depth, cur, parts = 0, '', []
            for ch in m.group(2):
                depth += ch == '('; depth -= ch == ')'
                if ch == ',' and depth == 0:
                    parts.append(cur); cur = ''
                else:
                    cur += ch
            parts.append(cur)
            for p in parts:
                w = p.strip().split()
                if not w:
                    continue
                if w[0].upper() == 'CONSTRAINT':
                    cons.add(w[1].lower())
                elif w[0].upper() not in ('PRIMARY', 'UNIQUE', 'CHECK', 'FOREIGN', 'EXCLUDE'):
                    cols.add(w[0].strip('"').lower())
        for m in re.finditer(r'ALTER\s+TABLE\s+(?:ONLY\s+)?public\.(\w+)\s+(.*?);', t, re.S | re.I):
            for c in re.findall(r'ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)', m.group(2), re.I):
                tables.setdefault(m.group(1).lower(), set()).add(c.lower())
            for c in re.findall(r'ADD\s+CONSTRAINT\s+(\w+)', m.group(2), re.I):
                cons.add(c.lower())
            for c in re.findall(r'RENAME\s+CONSTRAINT\s+\w+\s+TO\s+(\w+)', m.group(2), re.I):
                cons.add(c.lower())
        for c in re.findall(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:CONCURRENTLY\s+)?(?:IF\s+NOT\s+EXISTS\s+)?(\w+)', t, re.I):
            idx.add(c.lower())
        for c in re.findall(r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:CONSTRAINT\s+)?TRIGGER\s+(\w+)', t, re.I):
            idx.add(c.lower())
        for m in re.finditer(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(\w+)\.(\w+)\s*\((.*?)\)\s*RETURNS', t, re.S | re.I):
            args = [a for a in re.split(r',(?![^(]*\))', m.group(3)) if a.strip()]
            nreq = sum(1 for a in args if not re.search(r'\bDEFAULT\b|=', a, re.I) and not re.match(r'\s*OUT\b', a, re.I))
            nall = sum(1 for a in args if not re.match(r'\s*OUT\b', a, re.I))
            funcs.setdefault(f'{m.group(1).lower()}.{m.group(2).lower()}', set()).add((nreq, nall))
    return tables, cons, idx, funcs


BUILTIN_SCHEMAS = ('pg_catalog',)
# nomes citados APENAS para provar AUSÊNCIA (identidades antigas removidas pela
# 2177/2215/2216); não precisam existir no DDL
ABSENT_OK = {'uq_catalog_variant_import_row_job_card_variant_type'}


# ---------------------------------------------------------------------------
# regras
# ---------------------------------------------------------------------------
def _scan(s):
    """gera (índice, char, profundidade, dentro_de_literal)"""
    depth, q = 0, False
    i = 0
    while i < len(s):
        ch = s[i]
        if q:
            if ch == "'" and i + 1 < len(s) and s[i + 1] == "'":
                yield i, ch, depth, True; i += 1; yield i, s[i], depth, True; i += 1; continue
            if ch == "'":
                q = False
            yield i, ch, depth, True
        else:
            if ch == "'":
                q = True; yield i, ch, depth, True
            else:
                if ch in '([':
                    depth += 1
                elif ch in ')]':
                    depth -= 1
                yield i, ch, depth, False
        i += 1


def split_top(s, sep=','):
    parts, cur = [], []
    for i, ch, d, q in _scan(s):
        if ch == sep and not q and d == 0:
            parts.append(''.join(cur)); cur = []
        else:
            cur.append(ch)
    parts.append(''.join(cur))
    return [p for p in parts if p.strip()]


def args_of(s, start):
    """s[start] == '(' → texto até o ')' correspondente (literal-aware)"""
    base = None
    for i, ch, d, q in _scan(s[start:]):
        if not q and ch == ')' and d == 0:
            return s[start + 1:start + i]
    return None


def lint(name, src, cat):
    tables, cons, idx, funcs = cat
    out = []
    ck = lambda r, n, ok, d='': out.append((f'{name} {r}: {n}', bool(ok), d))
    t = strip_comments(src)
    nl = nolit(t)
    U = nl.upper()
    ck('L-1', 'parênteses balanceados', nl.count('(') == nl.count(')'), f"{nl.count('(')}/{nl.count(')')}")
    is_do = bool(re.search(r'\bDO\s+\$', nl))
    if is_do:
        body = re.split(r'\$\w+\$', nl)[1]
        B = body.upper()
        n_begin = len(re.findall(r'\bBEGIN\b', B))
        n_if = len(re.findall(r'(?m)^\s*IF\b', B))
        n_endif = len(re.findall(r'\bEND\s+IF\b', B))
        n_case = len(re.findall(r'\bCASE\b', B))
        n_end = len(re.findall(r'\bEND\b(?!\s+IF\b)(?!\s+LOOP\b)', B))
        ck('L-2', 'IF/END IF pareados', n_if == n_endif, f'{n_if}/{n_endif}')
        ck('L-2', 'BEGIN + CASE = END', n_begin + n_case == n_end, f'{n_begin}+{n_case}/{n_end}')
        decl = re.search(r'\bDECLARE\b(.*?)\bBEGIN\b', body, re.S | re.I).group(1)
        declared = set(re.findall(r'^\s*([vc]_\w+)\s', decl, re.M))
        used = set(re.findall(r'\b([vc]_[a-z0-9_]+)\b', body))
        # colunas de tabela que começam com v_/c_ não existem no escopo usado
        ck('L-3', 'toda variável usada está declarada', used <= declared, str(sorted(used - declared)))
    # L-4 format()
    bad = []
    for m in re.finditer(r'\bformat\s*\(', t):
        a = args_of(t, m.end() - 1)
        if a is None:
            continue
        ps = split_top(a)
        if not ps or not ps[0].strip().startswith("'"):
            continue
        mold = ps[0].strip()
        n_ph = len(re.findall(r'%[sIL]', mold.replace('%%', '')))
        if n_ph != len(ps) - 1:
            bad.append(mold[:60])
    ck('L-4', 'format(): marcadores = argumentos', not bad, str(bad[:3]))
    # L-6 jsonb_build_object
    bad = []
    for m in re.finditer(r'\bjsonb_build_object\s*\(', nl):
        a = args_of(nl, m.end() - 1)
        n = len(split_top(a)) if a and a.strip() else 0
        if n % 2 or n > 100:
            bad.append(n)
    ck('L-6', 'jsonb_build_object com nº par de argumentos e <= 100', not bad, str(bad))
    # L-5 SELECT … INTO (só no corpo PL/pgSQL)
    if is_do:
        bad = []
        body = re.split(r'\$\w+\$', nl)[1]
        for st in split_top(body, ';'):
            s2 = st.strip()
            m = re.search(r'\bINTO\s+(?:STRICT\s+)?((?:v_\w+(?:\[\w+\])?\s*,\s*)*v_\w+)', s2, re.I)
            if not m or not re.search(r'\bSELECT\b', s2, re.I) or re.match(r'(INSERT|UPDATE)\b', s2, re.I) \
                    or re.search(r'RETURNING\s+\w+\s+INTO', s2, re.I):
                continue
            targets = [x for x in m.group(1).split(',') if x.strip()]
            # lista de seleção: SELECT de nível 0 mais próximo antes do INTO
            head = s2[:m.start()]
            depth, pos = 0, None
            for k in range(len(head) - 1, -1, -1):
                ch = head[k]
                depth += ch == ')'; depth -= ch == '('
                if depth == 0 and head[k:k + 6].upper() == 'SELECT' and (k == 0 or not head[k - 1].isalnum()):
                    pos = k; break
            if pos is None:
                continue
            sel = head[pos + 6:]
            fr = re.search(r'\bFROM\b', sel, re.I)
            depth, cut = 0, None
            for k in range(len(sel)):
                depth += sel[k] == '('; depth -= sel[k] == ')'
                if depth == 0 and sel[k:k + 4].upper() == 'FROM' and not sel[k - 1].isalnum() and (k + 4 >= len(sel) or not sel[k + 4].isalnum()):
                    cut = k; break
            lst = sel[:cut] if cut is not None else sel
            items = split_top(lst)
            if len(items) != len(targets):
                bad.append(f'{len(items)}≠{len(targets)}: ' + ' '.join(s2.split())[:80])
        ck('L-5', 'SELECT … INTO: expressões = alvos', not bad, str(bad[:3]))
    # L-7 / L-8 nomes
    alias = {}
    for m in re.finditer(r'\bpublic\.(\w+)(?:\s+AS)?\s+(\w+)', nl, re.I):
        tb, al = m.group(1).lower(), m.group(2).lower()
        if al.upper() in ('WHERE', 'ON', 'SET', 'VALUES', 'JOIN', 'LEFT', 'CROSS', 'INNER', 'GROUP', 'ORDER', 'USING', 'LIMIT',
                          'RETURNING', 'FOR', 'UNION', 'WITH', 'AND', 'OR', 'INTO', 'FROM', 'SELECT', 'IS', 'NOT', 'AS', 'THEN', 'TO'):
            continue
        alias.setdefault(al, set()).add(tb)
    other = set()
    for m in re.finditer(r'(?=\b(?:FROM|JOIN)\s+(?!public\.)(?!LATERAL\b)[\w.]+\s+(?:AS\s+)?(\w+)\b)', nl, re.I):
        other.add(m.group(1).lower())
    for m in re.finditer(r'(?=\)\s+(?:AS\s+)?(\w+)\s*(?:\(|\bON\b|;|\n|,|$))', nl, re.I):
        other.add(m.group(1).lower())
    for m in re.finditer(r'\b(\w+)\s+AS\s*\(', nl, re.I):
        other.add(m.group(1).lower())
    refs = set(x.lower() for x in re.findall(r'\bpublic\.(\w+)\b(?!\s*\()', nl))
    refs |= set(x.lower() for x in re.findall(r'\b(?:INTO|UPDATE|FROM|JOIN)\s+public\.(\w+)', nl, re.I))
    missing = sorted(r for r in refs if r not in tables and r not in idx and r not in funcs.get('public.' + r, {'x'}) - {'x'}
                     and ('public.' + r) not in funcs)
    ck('L-7', 'public.<relação> existe no DDL do repositório', not missing, str(missing))
    bad = set()
    for al, tbs in alias.items():
        if al in other or len(tbs) > 1:
            continue
        cols = set().union(*[tables.get(tb, set()) for tb in tbs])
        if not cols:
            continue
        for c in re.findall(r'\b' + re.escape(al) + r'\.(\w+)', nl, re.I):
            if c.lower() not in cols and c.lower() not in ('*',):
                bad.add(f'{al}.{c}')
    for m in re.finditer(r'INSERT\s+INTO\s+public\.(\w+)\s*\(([^)]*)\)', nl, re.I):
        for c in m.group(2).split(','):
            if c.strip().lower() not in tables.get(m.group(1).lower(), set()):
                bad.add(f'{m.group(1)}({c.strip()})')
    for m in re.finditer(r'UPDATE\s+public\.(\w+)\s+SET\s+(\w+)\s*=', nl, re.I):
        if m.group(2).lower() not in tables.get(m.group(1).lower(), set()):
            bad.add(f'{m.group(1)}.{m.group(2)}')
    # colunas qualificadas por alias ambíguo (mesmo alias para tabelas diferentes) não são falhas
    ck('L-8', 'colunas citadas existem na tabela do alias / INSERT / UPDATE', not bad, str(sorted(bad)[:8]))
    # L-9 funções
    bad = []
    for m in re.finditer(r'\b(internal|public)\.(\w+)\s*\(', nl):
        fq = f'{m.group(1)}.{m.group(2)}'.lower()
        if m.group(1).lower() == 'public' and m.group(2).lower() in tables:
            continue
        a = args_of(nl, m.end() - 1)
        n = len(split_top(a)) if a and a.strip() else 0
        sig = funcs.get(fq)
        if not sig:
            bad.append(fq)
        elif not any(r <= n <= al for r, al in sig):
            bad.append(f'{fq}/{n}')
    ck('L-9', 'função existe no DDL com a aridade usada', not bad, str(sorted(set(bad))))
    # L-10 constraint/índice citados
    names = set(x.lower() for x in re.findall(r"'((?:uq|ck|fk|ix|pk|trg)_\w+)'", t))
    names |= set(x.lower() for x in re.findall(r"to_regclass\('public\.(\w+)'\)", t))
    missing = sorted(n for n in names if n not in cons and n not in idx and n not in tables
                     and not n.endswith('_pkey') and not n.startswith('uq_card_variant_card_type')
                     and not n.startswith('uq_cvir_job_card_type') and n not in ABSENT_OK)
    ck('L-10', 'constraints/índices/triggers citados existem no DDL', not missing, str(missing))
    return out


def run():
    cat = build_catalog()
    targets = sorted(H.glob('2830H_E0[3-9]*.sql')) + sorted(H.glob('2830H_E1[0-5]*.sql')) + [H / '2830H_E98_postcheck_extended_residue.sql']
    res = []
    for f in targets:
        res += lint(f.name, f.read_text(encoding='utf-8'), cat)
    return res, cat


if __name__ == '__main__':
    res, cat = run()
    bad = [r for r in res if not r[1]]
    for n, ok, d in res:
        if not ok:
            print('FAIL ' + n + ' ' + d)
    print(f'B12-LINT TOTAL {len(res)} PASS {len(res) - len(bad)} FAIL {len(bad)} · catálogo: {len(cat[0])} tabelas, {len(cat[1])} constraints, {len(cat[2])} índices/triggers, {len(cat[3])} funções')
    sys.exit(1 if bad else 0)
