#!/usr/bin/env python3
"""
V1-13 · E1-B3 — verificação ESTÁTICA da proposta 5378–5380 (+ 5891, ROLLBACK_E1B3).

Sem banco. Comprova só propriedades do texto: forma, cadeia de md5 com a E1-B1,
mudança mínima nas funções substituídas, privilégios, titular intocado, escopo
das escritas, ausência de atribuição retroativa, reversão literal e cobertura do
harness. Não comprova comportamento, atomicidade nem concorrência.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1b3-pokedex-history/static_check_e1b3.py
"""
from __future__ import annotations

import difflib
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
E1A = os.path.join(ROOT, "database", "proposals", "2026-11-14-v1-13-e1a-editor-role")
E1B1 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1b1-editor-core-binder")
E1B2 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1b2-editor-curation")
MIG = ["5378_fix_binder_slot_editor_scope_species_reference.sql",
       "5379_attribute_binder_activity_items_to_collection.sql",
       "5380_create_editor_pokedex_position_writes.sql"]
HARNESS = "5891_validate_editor_pokedex_history_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1B3.sql"
ADD = "binder_activity_add_item"
SCOPE = "binder_slot_editor_scope"
OWNER_DEX = {"set_pokedex_position_assignment": "6122_create_set_pokedex_position_assignment_function.sql",
             "remove_pokedex_position_assignment": "6124_create_remove_pokedex_position_assignment_function.sql",
             "set_pokedex_position_primary_representative": "6126_fix_primary_representative_on_conflict_ambiguity.sql",
             "clear_pokedex_position_primary_representative": "6125_create_primary_representative_functions.sql"}

R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, "rb") as fh:
        b = fh.read()
    return b, b.decode("utf-8")


def prosrc(text, fname):
    i = text.lower().index("function public." + fname + "(")
    m = re.search(r"\bas\s+(\$[A-Za-z0-9_]*\$)", text[i:], re.I)
    a = i + m.end()
    return text[a:text.index(m.group(1), a)]


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


F = {n: rd(os.path.join(HERE, n)) for n in MIG + [HARNESS, ROLLBACK]}
T = {n: v[1] for n, v in F.items()}
t78, t79, t80 = (T[m] for m in MIG)
t71 = rd(os.path.join(E1B1, "5371_create_binder_editor_authorization.sql"))[1]
t72 = rd(os.path.join(E1B1, "5372_allow_editor_actor_in_binder_activity.sql"))[1]
t76 = rd(os.path.join(E1B2, "5376_create_editor_collection_metadata_writes.sql"))[1]
h, rb = T[HARNESS], T[ROLLBACK]

# 1. Forma ---------------------------------------------------------------------------------------
for n, (b, t) in F.items():
    check(f"1.{n[:4]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t, f"{n}: sem CRLF, nova linha final, não executado")
for n in MIG:
    t = T[n]
    check(f"2.{n[:4]}", t.count("\nbegin;\n") == 1 and t.rstrip().endswith("commit;") and "do $pre$" in t and "do $post$" in t,
          f"{n}: transação única com precheck e postcheck")

# 2. 5378: uma linha sobre a 5371 ------------------------------------------------------------------
s71, s78 = prosrc(t71, SCOPE), prosrc(t78, SCOPE)
d = [l for l in difflib.ndiff(s71.splitlines(), s78.splitlines()) if l[:2] in ("+ ", "- ")]
m71, m78 = md5(s71), md5(s78)
check("3.1", d == ["+     v_own := true;   -- E1-B3 (5378): referência de espécie de X = bolso de X (C-237)"],
      f"5378 = 5371 + exatamente uma linha ({len(d)} diferenças)")
check("3.2", f"is distinct from '{m71}'" in t78 and t78.count(f"'{m78}'") == 2 and f"'{m78}'" in h,
      f"5378: precheck = md5 da 5371 ({m71}); postcheck e 5891 = md5 novo ({m78})")
check("3.3", "create or replace function public.binder_slot_editor_scope(" in t78
      and "revoke" not in nc(t78).lower() and "grant" not in nc(t78).lower(),
      "5378: CREATE OR REPLACE (ACL e comentário preservados), sem GRANT/REVOKE")
check("3.4", "return 'FOREIGN'" in s78.split("collection_layout_slot_species_reference")[1].split("v_own := true")[0],
      "referência de OUTRA coleção continua FOREIGN antes do v_own")

# 3. 5379: coleção por item ------------------------------------------------------------------------
a72, a79 = prosrc(t72, ADD), prosrc(t79, ADD)
m72, m79 = md5(a72), md5(a79)
removed = [l[2:].strip() for l in difflib.ndiff(a72.splitlines(), a79.splitlines()) if l[:2] == "- "]
check("4.1", m72 == "59ec5791e514026b7a8340e104d66f30" and f"is distinct from '{m72}'" in t79,
      f"5379: precheck exige o corpo da 5372 ({m72})")
check("4.2", sorted(removed) == sorted([
    "collection_id, collection_name, binder_name, summary)",
    "coalesce(v_ctx -> 'summary', '{}'::jsonb))",
    "variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail)",
    "left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail);"]),
      f"5379 sobre a 5372: só as listas de colunas dos dois INSERT mudam; o resto é acréscimo ({removed})")
sig = lambda t: re.search(r"function public\.binder_activity_add_item\((.*?)\)\s*returns", t, re.S).group(1)
check("4.3", sig(t72) == sig(t79) and "create or replace function public.binder_activity_add_item(" in t79
      and "grant " not in nc(t79).lower(),
      "assinatura, ACL e SECURITY DEFINER preservados (CREATE OR REPLACE, sem GRANT)")
b79 = nc(a79)
i = [b79.find(x) for x in ("v_ev_xact is distinct from pg_catalog.pg_current_xact_id()", "if p_kind = 'CARD' then",
                           "c.owner_user_id = v_ev_owner", "BINDER_ACTIVITY_CROSS_COLLECTION",
                           "insert into public.binder_activity_item")]
check("4.4", -1 not in i and i == sorted(i),
      "ordem: contexto da operação → atribuição → só coleção do mesmo titular → guarda do EDITOR → gravação do item")
check("4.5", "v_uid is distinct from v_ev_owner" in b79 and "p_kind in ('COLLECTION', 'BINDER')" in b79
      and "v_icoll is distinct from v_ev_coll" in b79,
      "ator ≠ titular: item de conteúdo só da coleção do evento; itens estruturais recusados")
check("4.6", "summary, item_collection_recorded)" in b79 and "'{}'::jsonb), true)" in b79
      and re.search(r"p_detail,\s*v_icoll\);", b79),
      "evento novo marcado (item_collection_recorded = true); item grava a coleção derivada")
check("4.7", "p_collection" not in b79 and not re.search(r"v_icoll\s*:=\s*\(?v_ctx", b79)
      and "collection_layout_slot_species_reference" in b79,
      "coleção do item nunca vem do contexto/cliente; bolso considera carta → reserva → referência")
alters = re.findall(r"alter table ([\w.]+) (.*?);", nc(t79), re.I)
check("4.8", alters == [("public.binder_activity_item", "add column if not exists collection_id uuid null"),
                        ("public.binder_activity_event", "add column if not exists item_collection_recorded boolean not null default false")],
      f"só duas colunas novas, sem DEFAULT na do item (sem reescrita), reaplicáveis: {alters}")
pre79 = t79[t79.index("do $pre$"):t79.index("$pre$;")]
check("4.11", "c.data_type = 'uuid'" in pre79 and "c.column_default is null" in pre79 and "c.column_default = 'false'" in pre79
      and "(v_ci <> v_ce)" in pre79 and "is distinct from '59ec5791e514026b7a8340e104d66f30' then" in pre79,
      "reaplicação depois de reversão conservadora: colunas existentes só com a forma exata; corpo vigente = 5372")
allc = "".join(nc(T[n]) for n in MIG)
check("4.9", not re.search(r"\bupdate\s+public\.binder_activity_(event|item)\b", allc, re.I)
      and not re.search(r"\binsert\s+into\s+public\.binder_activity_(event|item)\b", nc(t79).replace(nc(a79), ""), re.I)
      and not re.search(r"(alter|drop|disable)\s+trigger", allc, re.I),
      "nenhuma atribuição retroativa (sem UPDATE no histórico) e gatilhos de imutabilidade intactos")
check("4.10", f"'{m79}'" in t79 and f"'{m79}'" in h and f"'{m79}'" in rb,
      f"md5 novo da gravação ({m79}) coerente em 5379, 5891 e ROLLBACK_E1B3")

# 4. 5380: Pokédex ---------------------------------------------------------------------------------
defs = re.findall(r"create function public\.(\w+)\((.*?)\)\s*returns(.*?)\bas \$", t80, re.I | re.S)
names = sorted(x[0] for x in defs)
check("5.1", names == sorted(["editor_pokedex_of_collection", "editor_set_pokedex_position_assignment",
                              "editor_remove_pokedex_position_assignment", "editor_set_pokedex_position_primary_representative",
                              "editor_clear_pokedex_position_primary_representative"]), f"5 funções: {names}")
check("5.2", all(re.search(r"security definer", a, re.I) and "set search_path = ''" in a.lower() for _, _, a in defs),
      "todas SECURITY DEFINER com search_path vazio")
rpcs = {"editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)", "editor_remove_pokedex_position_assignment(uuid, uuid)",
        "editor_set_pokedex_position_primary_representative(uuid, uuid)", "editor_clear_pokedex_position_primary_representative(uuid, uuid)"}
check("5.3", all(f"revoke all on function public.{s} from public, anon;" in t80 and f"grant execute on function public.{s} to authenticated;" in t80
                 for s in rpcs)
      and "revoke all on function public.editor_pokedex_of_collection(uuid) from public, anon, authenticated, service_role;" in t80
      and "grant execute on function public.editor_pokedex_of_collection" not in t80
      and not re.search(r"\bgrant\b[^;]*\bto\s+(anon|public|service_role)\b", nc(t80), re.I),
      "4 RPCs só authenticated; ajudante interno sem EXECUTE para a API")
ok54 = True
for f in ("editor_set_pokedex_position_assignment", "editor_remove_pokedex_position_assignment",
          "editor_set_pokedex_position_primary_representative", "editor_clear_pokedex_position_primary_representative"):
    b = nc(prosrc(t80, f))
    j = [b.find("public.assert_collection_editor(p_collection_id)"), b.find("public.editor_pokedex_of_collection(p_collection_id)")]
    if "physical_card_id" in f or f != "editor_clear_pokedex_position_primary_representative":
        j.append(b.find("ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id\n  for update"))
    ok54 = ok54 and -1 not in j and j == sorted(j)
check("5.4", ok54 and "PHYSICAL_CARD_NOT_ELIGIBLE" in t80 and "create function public.assert_collection_editor(" in t76,
      "autorização (5376) → Pokédex → alocação de X travada; exemplar fora de X = recusa única")
dml = re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t80), re.I)
check("5.5", dml and {x for _, x in dml} == {"public.collection_pokedex_position_assignment",
                                              "public.collection_pokedex_position_primary_representative"},
      f"5380 escreve só posição e representante — nada de alocação, exemplar, local ou condição: {sorted({x for _, x in dml})}")
sa = nc(prosrc(t80, "editor_set_pokedex_position_assignment"))
k = [sa.find(x) for x in ("'UNCHANGED'", "POKEDEX_POSITION_NOT_FOUND", "CONFIRMATION_REQUIRED", "delete from", "insert into")]
check("5.6", -1 not in k and k == sorted(k) and "case when v_base = 'USER_OVERRIDE' then v_uid end" in sa,
      "posição: mesma posição → UNCHANGED antes de validar; mover = DELETE + INSERT; USER_OVERRIDE registra o EDITOR")
ok57, hashes = True, {}
for f, fn in OWNER_DEX.items():
    hsh = md5(prosrc(rd(os.path.join(SCHEMA, fn))[1], f))
    hashes[f] = hsh
    ok57 = ok57 and t80.count(f"'{hsh}'") == 2 and f"'{hsh}'" in h
check("5.7", ok57 and not re.search(r"function public\.(" + "|".join(OWNER_DEX) + r")\(", nc(t80), re.I),
      f"titular da Pokédex intocado: md5 dos arquivos no pre/postcheck e na 5891 {hashes}")
check("5.8", "collection_allocation_id" not in re.sub(r"returns table \([^)]*\)", "", " ".join(x[1] for x in defs))
      and all("collection_allocation_id" not in m.group(1)
              for m in re.finditer(r"returns table \(([^)]*)\)", t80)),
      "nenhum parâmetro ou retorno expõe collection_allocation_id ao EDITOR")

# 5. Reversão --------------------------------------------------------------------------------------
o = [rb.find(f"-- R{n} ") for n in ("5380", "5379", "5378", "5379-D")]
r79 = rb[o[1]:o[2]]
r79d = rb[o[3]:]
check("6.1", -1 not in o and o == sorted(o) and rb.count("drop function if exists") == 5,
      "ROLLBACK_E1B3: ordem inversa R5380 → R5379 → R5378; R5379-D opcional no fim; 5 funções")
check("6.3", "drop column" not in nc(r79).lower() and "as colunas de atribuição deveriam permanecer" in r79
      and "drop column" not in nc(rb[:o[3]]).lower(),
      "reversão padrão da 5379 preserva colunas e dados (nenhum DROP fora do R5379-D)")
i3 = [r79d.find(x) for x in ("is distinct from '59ec5791e514026b7a8340e104d66f30'", "e.item_collection_recorded",
                             "i.collection_id is not null", "RECUSADO", "drop column if exists item_collection_recorded")]
check("6.4", -1 not in i3 and i3 == sorted(i3) and nc(r79d).lower().count("drop column") == 2,
      "R5379-D só remove colunas depois do R5379 e se nenhum evento foi atribuído; recusa depois de uso real")
check("6.2", md5(prosrc(rb, ADD)) == m72 and md5(prosrc(rb, SCOPE)) == m71,
      "reversão devolve add_item da 5372 e a classificação da 5371 byte a byte")

# 6. Harness ---------------------------------------------------------------------------------------
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected := (\d+);", h).group(1))
check("7.1", len(ids) + 1 == exp and f"{exp}/{exp} PASS" in h, f"5891: {len(ids)} verificações + F.2 = {exp}")
need = {"EDITOR autorizado": "1.1", "representante": "2.1", "VIEWER/não membro/ex-membro/anon": "3.2",
        "outra conta/sem alocação/outra coleção": "3.1", "coleção livre": "3.3", "referência de espécie": "4.3",
        "classificação 5378": "4.1", "evento com várias coleções": "5.3", "reserva sem coleção (C-196)": "5.4",
        "contexto forjado": "6.2", "revogação": "7.1", "titular": "8.1", "patrimônio": "9.1", "arquivada": "10.1",
        "histórico anterior": "0.4"}
check("7.2", all(v in ids for v in need.values()), f"5891 cobre os cenários pedidos ({[x for x, v in need.items() if v not in ids]})")
check("7.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "MS891" in h and "PENDENTE" in h
      and "binder_activity_item)" in h,
      "5891: sem BEGIN/COMMIT, sentinela, concorrência pendente, resíduo inclui o histórico")

# 7. Escopo e compatibilidade --------------------------------------------------------------------------
outs = re.findall(r"function public\.(\w*merge\w*|\w*species_reference\w*|get_shared_binder_activity\w*|\w*objective\w*|"
                  r"\w*orphan\w*|add_layout_page|remove_layout_page|reorder_layout_pages|\w*auto_arrange\w*|\w*gap\w*)\(", allc, re.I)
check("8.1", not outs and "storage.objects" not in allc and "alter table public.collection " not in allc,
      f"nada de mesclagem, referência em massa (E1-C), leitura de membros (E1-D), objetivo, órfãos ou Storage ({outs})")
H89 = "5889_validate_editor_core_binder_HARNESS.sql"
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema",
                     os.path.relpath(E1A, ROOT), os.path.relpath(E1B1, ROOT), os.path.relpath(E1B2, ROOT)],
                    capture_output=True, text=True).stdout.strip().splitlines()
others = [x for x in st if not x.endswith((H89, "e1b1-editor-core-binder/README.md"))]
rdif = subprocess.run(["git", "-C", ROOT, "diff", "-U0", "--", os.path.relpath(os.path.join(E1B1, "README.md"), ROOT)],
                      capture_output=True, text=True).stdout
rchg = [l for l in rdif.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
check("8.4", all(l[1:].startswith("| `5889_validate_editor_core_binder_HARNESS.sql` |") for l in rchg) and len(rchg) <= 2,
      f"README da E1-B1: só a linha da 5889 muda ({len(rchg)} linhas)")
check("8.2", not others, f"frontend, schema canônico, E1-A, E1-B2 e E1-B1 (salvo a 5889 e a linha dela no README) sem alterações ({others or 'limpo'})")
dif = subprocess.run(["git", "-C", ROOT, "diff", "-U0", "--", os.path.relpath(os.path.join(E1B1, H89), ROOT)],
                     capture_output=True, text=True).stdout
chg = [l for l in dif.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
body89 = [l for l in chg if not re.match(r"^[+-](Versão\.+:|\s{14}\S)", l)]
check("8.3", all("binder_activity_add_item" in l or "59ec5791" in l or "f8cfba40" in l or "binder_activity_begin" in l
                 or "gravação do histórico" in l for l in body89) and len(body89) <= 8,
      f"5889 (E1-B1): só o 0.4 muda — aceita a gravação da 5372 ou da 5379 ({len(chg)} linhas no diff)")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<12} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
