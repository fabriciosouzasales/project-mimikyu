#!/usr/bin/env python3
"""
Verificação estática do ensaio 6850 (Pokédex P6.1) — não conecta a banco.

Prova, byte a byte, que o conteúdo ensaiado em 6850 é o conteúdo funcional
aprovado de 6136, 6137 e 6849 v2.1, e faz checagens estruturais de segurança.

Uso (a partir desta pasta):  python3 verify_6850_identity.py
Saída: uma linha por verificação (PASS/FAIL) e código de saída 0 só se tudo PASS.

Regras de extração (as mesmas citadas no cabeçalho de 6850):
- DDL de 6136/6137 = texto entre a linha "begin;" e a linha "commit;" do arquivo
  (sem as duas linhas), incluindo a quebra de linha final do último comando.
- Validador = do "create or replace function pg_temp.p6_6849_validate" até o
  "$fn$;" de fechamento, em 6849; prosrc = texto entre os dois "$fn$".
- Hashes calculados sobre o texto sem "\\r".
"""
import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
F36 = HERE / "6136_create_pokedex_species_favorite_table.sql"
F37 = HERE / "6137_create_pokedex_species_favorite_functions.sql"
F49 = HERE / "6849_validate_pokedex_species_favorite.sql"
F50 = HERE / "6850_dryrun_pokedex_species_favorite.sql"

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))


def h(text):
    return hashlib.sha256(text.replace("\r", "").encode("utf-8")).hexdigest()


def inner(s):
    a = s.index("\nbegin;\n") + len("\nbegin;\n")
    b = s.rindex("\ncommit;\n") + 1
    return s[a:b]


def strip_dollar_literals(s):
    # Remove o conteúdo de literais dollar-quoted ($$…$$, $tag$…$tag$), preservando os delimitadores.
    return re.sub(r"(\$[A-Za-z0-9_]*\$)(.*?)(\1)", r"\1\3", s, flags=re.S)


def strip_sql_comments(s):
    # Remove comentários de bloco e de linha (suficiente para estes arquivos;
    # nenhum literal deles contém "--" ou "/*" relevante para as checagens abaixo).
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"--[^\n]*", "", s)


s36, s37, s49, s50 = (p.read_text(encoding="utf-8") for p in (F36, F37, F49, F50))

i36, i37 = inner(s36), inner(s37)
st = s49.index("create or replace function pg_temp.p6_6849_validate")
f1 = s49.index("$fn$")
f2 = s49.index("$fn$", f1 + 4)
vfun = s49[st:f2 + len("$fn$;")]
prosrc = s49[f1 + 4:f2]

# 1. Identidade do conteúdo embutido
m36 = re.search(r"\$p6136\$(.*?)\$p6136\$", s50, flags=re.S)
m37 = re.search(r"\$p6137\$(.*?)\$p6137\$", s50, flags=re.S)
check("I1 DDL 6136 embutido == 6136 (begin..commit)", m36 and m36.group(1) == i36)
check("I2 DDL 6137 embutido == 6137 (begin..commit)", m37 and m37.group(1) == i37)
check("I3 validador embutido == 6849 v2.1 (função completa)", s50.count(vfun) == 1)
check("I4 constante c_hash_6136 == sha256(DDL 6136)", f"c_hash_6136  constant text := '{h(i36)}'" in s50, h(i36))
check("I5 constante c_hash_6137 == sha256(DDL 6137)", f"c_hash_6137  constant text := '{h(i37)}'" in s50, h(i37))
check("I6 constante c_hash_6849 == sha256(prosrc 6849)", f"c_hash_6849  constant text := '{h(prosrc)}'" in s50, h(prosrc))
header50 = s50.split("*/", 1)[0]
check("I8 cabeçalho cita os três hashes de conteúdo (uma vez cada)",
      all(header50.count(x) == 1 for x in (h(i36), h(i37), h(prosrc))))
check("I7 cabeçalho cita sha256 dos arquivos completos",
      all(hashlib.sha256(x.encode("utf-8")).hexdigest() in s50 for x in (s36, s37, s49)))

# 2. DDL embutido sem controle de transação
for name, t in (("6136", i36), ("6137", i37)):
    # Corpos de função (dollar-quoted) contêm BEGIN/END de PL/pgSQL — não são controle de transação.
    body = strip_dollar_literals(strip_sql_comments(t)).lower()
    bad = re.findall(r"(?m)^\s*(begin|commit|rollback|savepoint|release|end)\s*;", body)
    check(f"T1 DDL {name} sem begin/commit/rollback/savepoint de nível de statement", not bad, str(bad))
    check(f"T2 DDL {name} sem CONCURRENTLY/VACUUM (não transacionais)",
          not re.search(r"\b(concurrently|vacuum)\b", body))
    check(f"T3 DDL {name} sem sequências/serial (efeito não transacional)",
          not re.search(r"\b(serial|bigserial|sequence|nextval)\b", body))

# 3. Estrutura do ensaio
code50 = strip_sql_comments(s50)
low = code50.lower()
check("S1 nenhum COMMIT no ensaio", not re.search(r"(?m)^\s*commit\s*;", low))
check("S2 nenhum ROLLBACK de nível de statement no ensaio (não depende de outra chamada)",
      not re.search(r"(?m)^\s*rollback\s*;", low))
check("S3 começa com begin + SET LOCAL lock_timeout/statement_timeout",
      re.search(r"begin;\s*set local lock_timeout = '5s';\s*set local statement_timeout = '120s';", low) is not None)
check("S4 último statement é o SELECT do ensaio",
      low.rstrip().endswith(") order by seq;") and "select * from pg_temp.p6_6850_dry_run(" in low)

dry = s50[s50.index("as $dry$"):s50.rindex("$dry$;")]
blk_start = dry.find("if v_pre_ok then\n    begin")
sent = dry.find("raise exception using errcode = 'P6D00'")
handler = dry.find("when sqlstate 'P6D00' then")
check("S0 marcos estruturais presentes (bloco, sentinela, handler)", min(blk_start, sent, handler) >= 0,
      f"bloco={blk_start} sentinela={sent} handler={handler}")
if min(blk_start, sent, handler) < 0:
    blk_start, sent, handler = 0, 0, 0  # força as checagens seguintes a reprovar
for needle in ("execute v_ddl_6136;", "execute v_ddl_6137;", "from pg_temp.p6_6849_validate(p_user_a, p_user_b) r;"):
    pos = dry.find(needle)
    check(f"S5 '{needle}' dentro do bloco protegido (antes da sentinela)", 0 <= blk_start < pos < sent)
check("S6 sentinela antes do handler, handler único para P6D00", 0 < sent < handler and dry.count("'P6D00'") == 2)
check("S7 nenhum RETURN dentro do bloco protegido", "return" not in dry[blk_start:handler].lower())
check("S8 salvaguarda pós-reversão aborta o statement", "raise exception 'P6_6850_REVERT_NOT_CONFIRMED'" in dry)
# Fora do bloco: só a DECLARE (com os literais $p6136$/$p6137$, que são texto, não comandos)
# e as leituras/saída. Remove-se o conteúdo dos literais antes de procurar comandos de escrita.
outside = strip_dollar_literals(dry[:blk_start] + dry[handler:]).lower()
check("S9 nenhuma escrita (insert/update/delete/execute/create/drop/alter/grant/revoke) fora do bloco protegido",
      not re.search(r"\b(insert|update|delete|execute|create|drop|alter|grant|revoke|truncate)\b", outside),
      str(re.findall(r"\b(insert|update|delete|execute|create|drop|alter|grant|revoke|truncate)\b", outside)))
check("S10 delimitadores pareados ($dry$, $p6136$, $p6137$, $fn$)",
      s50.count("$dry$") == 2 and s50.count("$p6136$") == 2 and s50.count("$p6137$") == 2
      and strip_sql_comments(s50).count("$fn$") == 2)
ids = re.findall(r"'id','(D\.[0-9X.]+)'", dry)
exp = re.search(r"v_expected\s+text\[\] := array\[(.*?)\];", dry, flags=re.S).group(1)
exp_ids = re.findall(r"'([^']+)'", exp)
check("S11 ids emitidos cobrem exatamente a lista esperada (D.X só em erro)",
      set(exp_ids) == set(ids) - {"D.X"} and len(exp_ids) == len(set(exp_ids)) == 11, f"{sorted(set(ids))}")

ok_all = True
for name, cond, detail in results:
    ok_all &= cond
    print(f"{'PASS' if cond else 'FAIL'}  {name}" + (f"  [{detail}]" if detail else ""))
print(f"\nTOTAL: {sum(c for _, c, _ in results)}/{len(results)} PASS")
sys.exit(0 if ok_all else 1)
