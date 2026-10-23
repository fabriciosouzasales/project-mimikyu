#!/usr/bin/env python3
"""
P2-A1-PROPOSAL-01 / AUDIT-CORRECTION-01 — verificação ESTÁTICA do pacote
5223–5228 + 5850. É análise TEXTUAL: NÃO compila SQL, NÃO prova sintaxe nem
resolução de nomes no PostgreSQL. Prova de compilação só existe executando
o pacote num banco (ambiente isolado, quando autorizado).

Não conecta a banco algum e não executa SQL. Lê os arquivos da pasta e de
database/schema/ e confere propriedades textuais verificáveis:

  S1  cada migration tem exatamente um BEGIN; e um COMMIT; executáveis (fora de
      comentários), nessa ordem;
  S2  delimitadores $tag$ balanceados em todos os arquivos;
  S3  toda função criada fixa search_path = '' ;
  S4  toda função pública revoga PUBLIC e anon; RPCs (SECURITY DEFINER) concedem
      só authenticated; helpers internos e funções de trigger não concedem a
      nenhum papel e revogam authenticated (e service_role nos helpers);
  S5  RPCs SECURITY DEFINER checam auth.uid() (exceto a função de trigger);
  S6  criação e desmontagem: lock_timeout '5s' e FOR UPDATE da coleção;
  S7  harness: sem COMMIT executável, sentinela MS850, v_expected = número de
      IDs funcionais distintos, todo public.<função>( chamado existe no pacote
      ou em database/schema/;
  S8  ordem 5225 → 5223 → 5224 → 5226 → 5227 → 5228 declarada nos cabeçalhos;
  S9  nenhum arquivo do pacote referencia service_role como concedido;
  S10 5227 revoga EXECUTE da create_collection_layout só de authenticated,
      sem GRANT, com precheck de chamadores e da 5224;
  S11 harness: alocações da Seção P em lotes de no máximo 500 (teto da
      5046); nenhuma fatia > 500;
  S12 harness: provas 0.8 e 1.7 (5227) presentes; trigger de falha não usa
      função em pg_temp e é conferido no 99.1;
  S13 5225: precheck textual de chamadores da assinatura antiga;
  S14 5228: mesma assinatura/retorno da 5137 v1.1 (CREATE OR REPLACE, sem
      DROP), lista exata dos sete modelos em (colunas, linhas), recusa 22023
      antes da contagem de páginas, regras 5137 preservadas, pré e
      pós-checagem, nenhuma DML fora do corpo da função;
  S15 5227: pós-checagem da matriz EFETIVA (has_function_privilege) e
      REVOKE de PUBLIC/anon/authenticated;
  S16 harness: provas 0.9, 0.10 e 14.1–14.6; chamada da 5228 com a ordem
      real de parâmetros (rows, columns);
  S17 mesma lista de sete modelos em 5224 (prévia e criação), 5228 e
      harness (9.1 e 14.1);
  S18 todo arquivo SQL do pacote declara NÃO EXECUTADA / NÃO EXECUTADO.

Uso:  python3 static_check_p2_a1.py   (sai com código 1 se algo falhar)
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parent.parent / "schema"
MIGRATIONS = sorted(p for p in HERE.glob("52[2-9][0-9]_*.sql"))
HARNESS = next(HERE.glob("5850_*.sql"))

results = []


def check(cid, ok, detail):
    results.append((cid, bool(ok), detail))


def strip_comments(sql: str) -> str:
    """Remove /* */ e -- fora de dollar-quotes (suficiente para estes arquivos)."""
    out, i, n = [], 0, len(sql)
    tag = None
    while i < n:
        if tag:
            j = sql.find(tag, i)
            if j < 0:
                out.append(sql[i:])
                break
            out.append(sql[i:j + len(tag)])
            i = j + len(tag)
            tag = None
            continue
        m = re.match(r"\$[A-Za-z_]*\$", sql[i:])
        if m:
            tag = m.group(0)
            out.append(tag)
            i += len(tag)
            continue
        if sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j < 0 else j
            continue
        if sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and (j + 1 >= n or sql[j + 1] != "'"):
                    break
                j += 2 if sql[j] == "'" else 1
            out.append(sql[i:j + 1])
            i = j + 1
            continue
        out.append(sql[i])
        i += 1
    return "".join(out)


def outside_dollar(sql: str) -> str:
    """Texto executável fora de corpos $...$ (para BEGIN/COMMIT de nível de arquivo)."""
    return re.sub(r"(\$[A-Za-z_]*\$).*?\1", " ", sql, flags=re.S)


def functions(sql: str):
    """(nome, assinatura_tipos, cabeçalho até o corpo) de cada CREATE FUNCTION."""
    found = []
    for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\((.*?)\)\s*returns(.*?)as\s+\$", sql, re.S | re.I):
        found.append((m.group(1), m.group(2), m.group(3)))
    return found


all_text = {p.name: p.read_text(encoding="utf-8") for p in MIGRATIONS + [HARNESS]}

# S1/S2
for p in MIGRATIONS:
    raw = all_text[p.name]
    code = outside_dollar(strip_comments(raw)).lower()
    b = len(re.findall(r"^\s*begin\s*;", code, re.M))
    c = len(re.findall(r"^\s*commit\s*;", code, re.M))
    check("S1:" + p.name[:4], b == 1 and c == 1 and code.find("begin;") < code.rfind("commit;"),
          f"BEGIN={b} COMMIT={c}")
for name, raw in all_text.items():
    tags = re.findall(r"\$[A-Za-z_]*\$", strip_comments(raw))
    check("S2:" + name[:4], len(tags) % 2 == 0, f"{len(tags)} delimitadores $tag$")

# S3–S6, S9
INTERNAL = {"collection_binder_plan", "collection_binder_dismantle_snapshot"}
TRIGGER_FN = {"enforce_expected_content_variant_type_game"}
for p in MIGRATIONS:
    code = strip_comments(all_text[p.name])
    low = code.lower()
    for name, args, header in functions(code):
        h = header.lower()
        check(f"S3:{p.name[:4]}:{name}", "search_path = ''" in h, "search_path vazio")
        rev_pub = re.search(rf"revoke\s+(all|execute)\s+on\s+function\s+public\.{name}\b[^;]*from\s+(public\b|public\s*,)", low)
        rev_anon = re.search(rf"revoke\s+(all|execute)\s+on\s+function\s+public\.{name}\b[^;]*\banon\b", low)
        grants = re.findall(rf"grant\s+execute\s+on\s+function\s+public\.{name}\b[^;]*to\s+(\w+)", low)
        if name in INTERNAL or name in TRIGGER_FN:
            rev_auth = re.search(rf"revoke\s+(all|execute)\s+on\s+function\s+public\.{name}\b[^;]*\bauthenticated\b", low)
            rev_sr = name in TRIGGER_FN or re.search(rf"revoke\s+(all|execute)\s+on\s+function\s+public\.{name}\b[^;]*\bservice_role\b", low)
            check(f"S4:{p.name[:4]}:{name}", rev_pub and rev_anon and rev_auth and rev_sr and not grants,
                  "interno: revogado de PUBLIC/anon/authenticated(/service_role), sem GRANT")
            if name in INTERNAL:
                check(f"S4i:{p.name[:4]}:{name}", "security invoker" in h, "helper SECURITY INVOKER")
        else:
            check(f"S4:{p.name[:4]}:{name}", rev_pub and rev_anon and grants == ["authenticated"],
                  f"RPC: revoga PUBLIC/anon; GRANT {grants}")
            if "security definer" in h:
                body = re.search(rf"function\s+public\.{name}\s*\(.*?\$(\w*)\$(.*?)\$\1\$", code, re.S | re.I)
                check(f"S5:{p.name[:4]}:{name}", body and "auth.uid()" in body.group(2), "checa auth.uid()")
    check("S9:" + p.name[:4], not re.search(r"grant\s+[^;]*to\s+[^;]*service_role", low), "nenhum GRANT a service_role")

for fn, fname in (("create_my_collection_binder", "5224"), ("dismantle_my_collection_binder", "5226")):
    code = strip_comments(next(t for n, t in all_text.items() if n.startswith(fname))).lower()
    seg = code[code.find(f"function public.{fn}"):]
    seg = seg[:seg.find("comment on function")]
    check(f"S6:{fn}", "set lock_timeout = '5s'" in seg and "for update" in seg and "owner_user_id = v_uid" in seg,
          "lock_timeout 5s + FOR UPDATE da coleção com dono no WHERE")

# S7 harness
h = all_text[HARNESS.name]
hc = outside_dollar(strip_comments(h)).lower()
check("S7:commit", not re.search(r"^\s*commit\s*;", hc, re.M), "harness sem COMMIT executável")
check("S7:sentinel", h.count("'MS850'") >= 3, "sentinela MS850 presente")
check("S7:gate-distinct", "count(distinct x->>'id')" in h, "GATE exige IDs distintos (repetição não compensa teste ausente)")
body = h[h.index("create or replace function pg_temp.wh_5850"):]
ids = re.findall(r"jsonb_build_object\('id','([^']+)'", body)
func_ids = {i for i in ids if not i.startswith("P.") and not i.startswith("X.") and i != "11.1"}
m = re.search(r"v_expected integer := (\d+);", h)
check("S7:expected", m and int(m.group(1)) == len(func_ids), f"v_expected={m and m.group(1)} ids funcionais distintos={len(func_ids)}")
known = set()
for p in list(SCHEMA.glob("*.sql")) + MIGRATIONS:
    known |= {x.lower() for x in re.findall(r"function\s+public\.(\w+)\s*\(", p.read_text(encoding="utf-8", errors="ignore"), re.I)}
called = set(re.findall(r"public\.(\w+)\s*\(", strip_comments(body)))
tables = {"card", "card_variant", "card_set", "expansion", "game", "card_variant_type", "physical_card", "collection",
          "collection_allocation", "collection_layout", "collection_layout_page", "collection_layout_slot",
          "collection_layout_slot_expected_content", "collection_layout_slot_assignment", "collection_layout_region",
          "storage_container", "collection_reference", "collection_pokedex_position_assignment", "language",
          "inventory", "pokedex", "pokedex_position", "pokemon_species", "pokemon_generation", "card_category"}
created_in_harness = {x.lower() for x in re.findall(r"create function public\.(\w+)\(", body)}
missing = sorted(c for c in called if c.lower() not in known and c not in tables and c.lower() not in created_in_harness)
check("S7:rpcs", not missing, "funções chamadas pelo harness existem: " + (", ".join(missing) or "todas"))

# S8
order_ok = all("5225 → 5223 → 5224 → 5226 → 5227 → 5228" in all_text[p.name] for p in MIGRATIONS)
check("S8:order", order_ok, "ordem do pacote declarada em todas as migrations")

# S10
t27 = strip_comments(next(t for n, t in all_text.items() if n.startswith("5227"))).lower()
check("S10:5227",
      re.search(r"revoke\s+execute\s+on\s+function\s+public\.create_collection_layout\(uuid, integer, integer\)\s+from\s+authenticated\s*;", t27)
      and "grant " not in t27.replace("-- grant", "")
      and "prosrc ilike '%create_collection_layout(%'" in t27
      and "create_my_collection_binder(uuid, integer, integer, text, text)" in t27,
      "revoga só de authenticated, sem GRANT; precheck de chamadores e da 5224")

# S11
hb = strip_comments(body)
slices = re.findall(r"allocate_physical_cards_to_collection\(v_cperf,\s*([^;]*)\);", hb)
sizes = [int(m) for x in slices for m in re.findall(r"least\(v_off \+ (\d+)", x)]
steps = [int(m) for m in re.findall(r"v_off := v_off \+ (\d+);", hb)]
check("S11:chunks", slices and len(sizes) == len(slices) and all(z <= 500 for z in sizes)
      and steps and all(z == sizes[0] for z in steps) and "10000)]" not in hb,
      f"Seção P aloca em lotes ≤ 500 ({len(slices)} chamada(s))")

# S12
check("S12:5227-proofs", "'id','0.8'" in body and "'id','1.7'" in body and "create_collection_layout(v_cnb" in body,
      "0.8 (privilégio) e 1.7 (chamada direta → 42501) presentes")
check("S12:fail-fn", "pg_temp.p2a1_fail" not in hb and "public.p2a1_harness_fail()" in hb
      and "to_regprocedure('public.p2a1_harness_fail()') is null" in hb,
      "função de falha em public, removida e conferida no 99.1")

# S13
t25 = strip_comments(next(t for n, t in all_text.items() if n.startswith("5225"))).lower()
check("S13:5225-callers", "prosrc ilike '%set_slot_expected_content(%'" in t25, "precheck textual de chamadores")

# S14
MODELS = "((2,2), (3,3), (3,4), (4,3), (4,4), (4,5), (5,4))"
raw28 = next(t for n, t in all_text.items() if n.startswith("5228"))
t28 = strip_comments(raw28)
l28 = t28.lower()
body28 = re.search(r"as \$\$(.*?)\$\$;", t28, re.S | re.I)
b28 = body28.group(1) if body28 else ""
outside28 = outside_dollar(t28).lower()
i_model = b28.find("INVALID_GRID")
i_pages = b28.find("SELECT count(*) INTO v_page_count")
check("S14:5228-signature",
      "create or replace function public.set_collection_layout_grid(" in l28
      and "drop function" not in l28
      and re.search(r"p_layout_id\s+uuid,\s*p_grid_rows\s+integer,\s*p_grid_columns\s+integer", l28)
      and re.search(r"returns table \(\s*id\s+uuid,\s*collection_id\s+uuid,\s*grid_rows\s+integer,\s*grid_columns\s+integer\s*\)", l28),
      "CREATE OR REPLACE, mesma assinatura (layout, rows, columns) e mesmo retorno")
check("S14:5228-models",
      "IF (p_grid_columns, p_grid_rows) NOT IN " + MODELS + " THEN" in b28
      and "ERRCODE = '22023'" in b28,
      "lista exata dos sete modelos em (colunas, linhas), 22023")
check("S14:5228-preserved",
      0 < i_model < i_pages
      and "assert_collection_layout_mutable(p_layout_id)" in b28
      and "p_grid_rows < 1 OR p_grid_rows > 10" in b28
      and "IF v_page_count > 0 THEN" in b28
      and "WHERE l.id = p_layout_id;" in b28
      and "security definer" in l28 and "set search_path = ''" in l28,
      "regra de modelo antes da contagem de páginas; 5122, faixa 1..10, bloqueio por páginas e UPDATE da 5141 preservados")
check("S14:5228-checks",
      "precheck 5228" in l28 and "postcheck 5228" in l28
      and not re.search(r"^\s*(insert|update|delete)\s", outside28, re.M),
      "pré e pós-checagem; nenhuma DML fora do corpo da função")

# S15
check("S15:5227-matrix",
      all(re.search(r"revoke\s+execute\s+on\s+function\s+public\.create_collection_layout\(uuid, integer, integer\)\s+from\s+" + r + r"\s*;", t27)
          for r in ("public", "anon", "authenticated"))
      and "postcheck 5227" in t27
      and "has_function_privilege('authenticated', v_oid, 'execute')" in t27
      and "has_function_privilege('anon', v_oid, 'execute')" in t27,
      "REVOKE PUBLIC/anon/authenticated + pós-checagem da matriz efetiva")

# S16
check("S16:grid-proofs",
      all(f"'id','{i}'" in body for i in ("0.9", "0.10", "14.1", "14.2", "14.3", "14.4", "14.5", "14.6"))
      and "set_collection_layout_grid(v_lay_g, n2, n)" in hb,
      "0.9, 0.10, 14.1–14.6 presentes; chamada (layout, rows=n2, columns=n)")

# S17
t24 = strip_comments(next(t for n, t in all_text.items() if n.startswith("5224")))
check("S17:models-consistent",
      t24.count("not in " + MODELS) == 2
      and hb.count("(values (2,2),(3,3),(3,4),(4,3),(4,4),(4,5),(5,4))") == 2,
      "mesma lista em 5224 (prévia e criação), 5228 e harness (9.1, 14.1)")

# S18
check("S18:not-executed",
      all(re.search(r"N[ÃA]O EXECUTAD[AO]", all_text[p.name]) for p in MIGRATIONS + [HARNESS]),
      "todos os SQL do pacote declaram NÃO EXECUTADA/O")

fails = [r for r in results if not r[1]]
for cid, ok, detail in results:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<55} {detail}")
print(f"\n{len(results) - len(fails)}/{len(results)} PASS")
sys.exit(1 if fails else 0)
