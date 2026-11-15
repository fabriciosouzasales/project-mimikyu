#!/usr/bin/env python3
"""
V1-13 · E1-C — verificação ESTÁTICA da proposta 5381–5383 (+ 5892, ROLLBACK_E1C).

Sem banco. Comprova só propriedades do texto: forma, lista fechada de tipos de
evento do EDITOR (e que ela é exatamente a união do que as funções do EDITOR
produzem), fichário exclusivo antes de qualquer escrita, escopo das escritas,
token igual ao do titular, ausência de contagem de bolsos ocupados na prévia,
titular intocado, reversão não destrutiva e cobertura do harness. Não comprova
comportamento, atomicidade nem concorrência.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1c-bulk-operations/static_check_e1c.py
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PROP = os.path.join(ROOT, "database", "proposals")
SCHEMA = os.path.join(ROOT, "database", "schema")
E1A = os.path.join(PROP, "2026-11-14-v1-13-e1a-editor-role")
E1B1 = os.path.join(PROP, "2026-11-15-v1-13-e1b1-editor-core-binder")
E1B2 = os.path.join(PROP, "2026-11-15-v1-13-e1b2-editor-curation")
E1B3 = os.path.join(PROP, "2026-11-15-v1-13-e1b3-pokedex-history")
MIG = ["5381_restrict_editor_binder_activity_event_types.sql", "5382_create_editor_binder_page_operations.sql",
       "5383_create_editor_binder_species_reference_operations.sql"]
HARNESS = "5892_validate_editor_bulk_operations_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1C.sql"
ALLOW = ["CARD_PLACED", "CARD_MOVED", "CARDS_SWAPPED", "CARDS_REMOVED", "POCKET_RESERVED", "RESERVATIONS_RELEASED",
         "POCKETS_LOCKED", "POCKETS_UNLOCKED", "PAGES_ADDED", "PAGE_REMOVED", "PAGES_REORDERED"]

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


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


F = {n: rd(os.path.join(HERE, n)) for n in MIG + [HARNESS, ROLLBACK]}
T = {n: v[1] for n, v in F.items()}
t81, t82, t83 = (T[m] for m in MIG)
h, rb = T[HARNESS], T[ROLLBACK]
allc = "".join(nc(T[n]) for n in MIG)

# 1. Forma ---------------------------------------------------------------------------------------
for n, (b, t) in F.items():
    check(f"1.{n[:4]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t, f"{n}: sem CRLF, nova linha final, não executado")
for n in MIG:
    t = T[n]
    check(f"2.{n[:4]}", t.count("\nbegin;\n") == 1 and t.rstrip().endswith("commit;") and "do $pre$" in t and "do $post$" in t,
          f"{n}: transação única com precheck e postcheck")

# 2. 5381: tipos de evento --------------------------------------------------------------------------
g = nc(prosrc(t81, "binder_activity_event_editor_type_guard"))
lst = re.search(r"new\.event_type not in \((.*?)\)", g, re.S)
types = re.findall(r"'([A-Z_]+)'", lst.group(1)) if lst else []
check("3.1", types == ALLOW, f"lista fechada de 11 tipos de curadoria: {types}")
check("3.2", "new.actor_user_id is not null and new.actor_user_id is distinct from new.owner_user_id" in g
      and "new.source is distinct from 'FICHARIO'" in g and "new.collection_id is null" in g
      and "BINDER_ACTIVITY_EVENT_TYPE" in g and "errcode = '42501'" in g,
      "só ator ≠ titular (legado NULL e titular intactos); origem FICHARIO; coleção obrigatória; recusa 42501")
check("3.3", re.search(r"create trigger trg_bae_editor_event_type\s+before insert on public\.binder_activity_event\s+for each row", nc(t81))
      and "security definer" not in nc(t81).lower().split("create function public.binder_activity_event_editor_type_guard")[1].split("$fn$")[0]
      and "revoke all on function public.binder_activity_event_editor_type_guard() from public, anon, authenticated, service_role;" in t81,
      "gatilho BEFORE INSERT por linha, função sem SECURITY DEFINER e sem EXECUTE para a API")
check("3.4", "function public.binder_activity_add_item" not in allc and "'f8cfba40e442e85056e7c8ce7954d4f4'" in t81,
      "gravação (5379) não é redefinida; precheck exige o corpo da 5379")
emitted = set()
srcs = [os.path.join(E1B1, "5374_create_editor_binder_core_writes.sql"),
        os.path.join(E1B2, "5375_create_editor_binder_curation_writes.sql"), os.path.join(HERE, MIG[1]), os.path.join(HERE, MIG[2])]
for p in srcs:
    for m in re.finditer(r"binder_activity_begin\((.*?)\);", nc(rd(p)[1]), re.S):
        emitted |= set(re.findall(r"'([A-Z_]{4,})'", m.group(1))) - {"FICHARIO", "SWAP"}
check("3.5", emitted == set(ALLOW), f"lista = exatamente os tipos que as funções do EDITOR abrem (E1-B1, E1-B2, E1-C): {sorted(emitted)}")

# 3. 5382: páginas --------------------------------------------------------------------------------
ex = nc(prosrc(t82, "assert_collection_binder_editor_exclusive"))
check("4.1", "public.assert_collection_binder_editor(p_collection_id)" in ex
      and "r.anchor_collection_id is distinct from p_collection_id" in ex
      and "collection_layout_guest g where g.layout_id = r.layout_id" in ex and "OPERATION_RESERVED_TO_OWNER" in ex,
      "ajudante: autorização da 5371 + fichário exclusivo (proprietária = X, nenhuma convidada)")
ok42 = True
for f in ("editor_add_binder_page", "editor_remove_binder_page", "editor_reorder_binder_pages"):
    b = nc(prosrc(t82, f))
    i = b.find("assert_collection_binder_editor_exclusive(p_collection_id)")
    w = [b.find(x) for x in ("binder_activity_begin", "insert into", "delete from", "update public") if b.find(x) >= 0]
    ok42 = ok42 and i >= 0 and all(i < x for x in w)
check("4.2", ok42, "toda escrita e todo evento vêm depois da autorização do fichário exclusivo")
rmv = nc(prosrc(t82, "editor_remove_binder_page"))
k = [rmv.find(x) for x in ("for update", "BINDER_MUST_KEEP_ONE_PAGE", "collection_layout_slot_assignment", "collection_layout_slot_expected_content",
                           "collection_layout_region", "collection_layout_slot_image", "s.locked", "PAGE_NOT_EMPTY",
                           "SPECIES_REFERENCES_ON_PAGE", "binder_activity_begin", "delete from public.collection_layout_page")]
check("4.3", -1 not in k and k == sorted(k) and "has %" not in rmv,
      "remover: página travada; ≥ 1 página; vazia de carta, reserva, região, imagem e trava; referências confirmadas; só então grava; sem contagens")
k = [rmv.find(x) for x in ("binder_slot_editor_scope(v_layout, p_collection_id, p_collection_id, s.id) = 'FOREIGN'",
                           "OPERATION_RESERVED_TO_OWNER", "PAGE_NOT_EMPTY", "binder_activity_begin")]
check("4.6", -1 not in k and k == sorted(k) and "s.page_id = v_page" in rmv[k[0] - 200:k[0]],
      "remover: cada bolso da página é classificado; qualquer FOREIGN (terceiros, inclusive convidada desassociada) → reservada ao titular, antes de PAGE_NOT_EMPTY e de gravar")
ro = nc(prosrc(t82, "editor_reorder_binder_pages"))
k = [ro.find(x) for x in ("order by p.id for update", "INVALID_PAGE_ORDER", "binder_activity_begin", "update public.collection_layout_page")]
check("4.4", -1 not in k and k == sorted(k) and "p.page_number = src.old_n" in ro,
      "reordenar: trava todas as páginas (ordem por id), valida a permutação e só então grava; endereçado por número")
dml82 = {x for _, x in re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t82), re.I)}
check("4.5", dml82 == {"public.collection_layout_page", "public.collection_layout_slot", "public.collection_layout_slot_species_reference"},
      f"5382 escreve só páginas, bolsos novos e referências da página removida: {sorted(dml82)}")

# 4. 5383: referências de espécie --------------------------------------------------------------------
o58 = rd(os.path.join(SCHEMA, "5258_create_binder_species_reference_writes.sql"))[1]
tok = lambda t: re.sub(r"\s+", " ", re.search(r"encode\(sha256\(convert_to\((.*?)'UTF8'\)\), 'hex'\)", t, re.S).group(1))
check("5.1", tok(prosrc(o58, "preview_my_binder_species_references")).replace("t.layout_id", "L")
      == tok(prosrc(t83, "editor_species_reference_summary")).replace("p_layout_id", "L")
      and "binder_species_reference_plan(" in t83 and "function public.binder_species_reference_plan" not in t83,
      "token = fórmula da 5258 sobre o mesmo plano canônico (não redefinido)")
pv = nc(prosrc(t83, "editor_preview_binder_species_references"))
check("5.2", "slots_with_content" not in t83.split("create function public.editor_preview_binder_species_references")[1].split("$fn$")[0]
      and "for update" not in pv and "for share" not in pv and "collection_layout_guest g where g.layout_id = v_layout" in pv
      and "m.role = 'EDITOR'" in pv,
      "prévia: sem contagem de bolsos ocupados; sem trava; exige EDITOR ativo e fichário exclusivo")
tl = nc(prosrc(t83, "editor_species_reference_target_locked"))
check("5.3", "assert_collection_binder_editor_exclusive(p_collection_id)" in tl and "NOT_POKEDEX_COLLECTION" in tl
      and all("editor_species_reference_target_locked(p_collection_id)" in nc(prosrc(t83, f))
              for f in ("editor_apply_binder_species_references", "editor_clear_binder_species_references",
                        "editor_set_binder_species_reference_visibility")),
      "aplicar, remover e mostrar/ocultar passam pelo fichário exclusivo travado e exigem Pokédex")
fr = "r.collection_id <> p_collection_id"
k1 = [pv.find(x) for x in (fr, "OPERATION_RESERVED_TO_OWNER", "NOT_POKEDEX_COLLECTION", "editor_species_reference_summary(")]
k2 = [tl.find(x) for x in ("assert_collection_binder_editor_exclusive(p_collection_id)", fr, "OPERATION_RESERVED_TO_OWNER", "return query")]
cl = nc(prosrc(t83, "editor_clear_binder_species_references"))
check("5.6", -1 not in k1 and k1[0] < k1[2] < k1[3] and -1 not in k2 and k2 == sorted(k2)
      and cl.count("r.layout_id = t.layout_id and r.collection_id = p_collection_id") == 2,
      "referências de outra coleção no fichário (proprietária anterior) → reservado ao titular na prévia e nas escritas; remover só apaga e conta as de X")
dml83 = {x for _, x in re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t83), re.I)}
check("5.4", dml83 == {"public.collection_layout_slot_species_reference", "public.collection_layout_species_reference_setting"},
      f"5383 escreve só a camada de referências e a preferência de exibição: {sorted(dml83)}")
ap = nc(prosrc(t83, "editor_apply_binder_species_references"))
k = [ap.find(x) for x in ("editor_species_reference_target_locked", "PLAN_CHANGED", "SPECIES_REFERENCES_PRESENT", "NOTHING_TO_APPLY",
                          "insert into public.collection_layout_slot_species_reference")]
check("5.5", -1 not in k and k == sorted(k), "aplicar: trava → token → referências presentes → nada a aplicar → grava (regras da 5258)")

# 5. Privilégios e titular ------------------------------------------------------------------------------
rpcs = {"editor_add_binder_page(uuid)": t82, "editor_remove_binder_page(uuid, integer, integer)": t82,
        "editor_reorder_binder_pages(uuid, integer[])": t82, "editor_preview_binder_species_references(uuid)": t83,
        "editor_apply_binder_species_references(uuid, text)": t83, "editor_clear_binder_species_references(uuid, integer)": t83,
        "editor_set_binder_species_reference_visibility(uuid, boolean)": t83}
internal = {"assert_collection_binder_editor_exclusive(uuid)": t82, "editor_species_reference_summary(uuid, uuid, uuid, text, uuid)": t83,
            "editor_species_reference_target_locked(uuid)": t83}
check("6.1", all(f"revoke all on function public.{s} from public, anon;" in t and f"grant execute on function public.{s} to authenticated;" in t
                 for s, t in rpcs.items())
      and all(f"revoke all on function public.{s} from public, anon, authenticated, service_role;" in t
              and f"grant execute on function public.{s}" not in t for s, t in internal.items())
      and not re.search(r"\bgrant\b[^;]*\bto\s+(anon|public|service_role)\b", allc, re.I),
      "7 RPCs só authenticated; 3 ajudantes internos sem EXECUTE para a API")
defs = re.findall(r"create function public\.(\w+)\((.*?)\)\s*returns(.*?)\bas \$", t82 + t83, re.I | re.S)
check("6.2", len(defs) == 10 and all(re.search(r"security definer", a, re.I) and "set search_path = ''" in a.lower() for _, _, a in defs),
      f"10 funções novas em 5382/5383, todas SECURITY DEFINER com search_path vazio ({len(defs)})")
owner = r"function public\.(add_layout_page|remove_layout_page|reorder_layout_pages|insert_my_binder_gap|close_my_binder_gap|" \
        r"apply_my_binder_auto_arrange|apply_my_binder_catalog_reconciliation|apply_my_binder_species_references|" \
        r"clear_my_binder_species_references|set_my_binder_species_reference_visibility|preview_my_binder_species_references|" \
        r"binder_species_reference_plan|assert_collection_layout_mutable|assert_collection_binder_editor|binder_slot_editor_scope)\("
check("6.3", not re.search(owner, allc, re.I) and "alter table" not in allc.lower() and "drop " not in allc.lower(),
      "nenhuma função do titular, da E1-B1 ou da E1-B3 redefinida; nenhum ALTER/DROP")

# 6. Reversão ------------------------------------------------------------------------------------------
o = [rb.find(f"-- R{n} ") for n in ("5383", "5382", "5381")]
check("7.1", -1 not in o and o == sorted(o) and rb.count("drop function if exists") == 11
      and "drop trigger if exists trg_bae_editor_event_type on public.binder_activity_event;" in rb
      and not re.search(r"\b(delete|truncate|drop\s+table|drop\s+column|update)\b", nc(rb), re.I),
      "ROLLBACK_E1C: ordem inversa; 10 funções + função do gatilho e o gatilho; nada apagado")

# 7. Harness -------------------------------------------------------------------------------------------
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected := (\d+);", h).group(1))
check("8.1", len(ids) + 1 == exp and f"{exp}/{exp} PASS" in h, f"5892: {len(ids)} verificações + F.2 = {exp}")
need = {"adicionar página": "1.1", "reordenar": "1.2", "página com conteúdo": "1.4", "várias coleções": "2.1",
        "aplicar referências": "3.1", "referência sobre conteúdo do titular": "3.3", "mostrar/ocultar": "3.4",
        "remover página com referências": "3.5", "remover referências": "3.6", "não membro/VIEWER/ex-membro/anon": "4.1",
        "coleção livre": "4.2", "tipos de evento": "5.2", "revogação": "6.1", "titular": "7.1", "patrimônio": "8.1",
        "arquivada": "9.1", "exclusivo com terceiros": "7.2", "terceiros intactos": "7.3"}
check("8.2", all(v in ids for v in need.values()), f"5892 cobre os cenários pedidos ({[x for x, v in need.items() if v not in ids]})")
check("8.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "MS892" in h and "PENDENTE" in h
      and "binder_activity_item)]" in h,
      "5892: sem BEGIN/COMMIT, sentinela, concorrência pendente, resíduo inclui o histórico")

# 8. Escopo -----------------------------------------------------------------------------------------------
outs = re.findall(r"function public\.(\w*gap\w*|\w*auto_arrange\w*|\w*catalog\w*|\w*merge\w*|\w*region\w*|\w*image\w*|"
                  r"get_shared_\w+|\w*objective\w*|\w*orphan\w*|\w*identity\w*|\w*grid\w*|\w*storage\w*)\(", allc, re.I)
check("9.1", not outs and "storage.objects" not in allc,
      f"nada de espaços, organização automática, novidades, mesclagem, imagens, leituras da E1-D, identidade, grade ou Storage ({outs})")
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema"]
                    + [os.path.relpath(x, ROOT) for x in (E1A, E1B1, E1B2, E1B3)],
                    capture_output=True, text=True).stdout.strip()
check("9.2", st == "", f"frontend, schema canônico, E1-A, E1-B1, E1-B2 e E1-B3 sem alterações ({st or 'limpo'})")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<10} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
