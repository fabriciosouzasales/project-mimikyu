#!/usr/bin/env python3
"""
V1-13 · E1-C2 — verificação ESTÁTICA da proposta 5384–5387 (+ 5893, ROLLBACK_E1C2).

Sem banco. Comprova só propriedades do texto: forma, lista de tipos de evento =
tipos efetivamente abertos pelas funções do EDITOR (com a origem certa), fichário
exclusivo e conjunto afetado conferidos antes de qualquer escrita, reuso dos planos
canônicos (sem redefinir função do titular), escopo das escritas, prévias sem dados
de terceiros, reversão literal e cobertura do harness. Não comprova comportamento,
atomicidade nem concorrência.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1c2-remaining-bulk-operations/static_check_e1c2.py
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
PROP = os.path.join(ROOT, "database", "proposals")
DIRS = {k: os.path.join(PROP, v) for k, v in {
    "E1A": "2026-11-14-v1-13-e1a-editor-role", "E1B1": "2026-11-15-v1-13-e1b1-editor-core-binder",
    "E1B2": "2026-11-15-v1-13-e1b2-editor-curation", "E1B3": "2026-11-15-v1-13-e1b3-pokedex-history",
    "E1C1": "2026-11-15-v1-13-e1c-bulk-operations"}.items()}
MIG = ["5384_extend_editor_binder_activity_event_types.sql", "5385_create_editor_binder_gap_operations.sql",
       "5386_create_editor_binder_auto_arrange.sql", "5387_create_editor_binder_catalog_reconciliation.sql"]
HARNESS = "5893_validate_editor_remaining_bulk_operations_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1C2.sql"
GUARD = "binder_activity_event_editor_type_guard"
FICH = ["CARD_PLACED", "CARD_MOVED", "CARDS_SWAPPED", "CARDS_REMOVED", "POCKET_RESERVED", "RESERVATIONS_RELEASED",
        "POCKETS_LOCKED", "POCKETS_UNLOCKED", "PAGES_ADDED", "PAGE_REMOVED", "PAGES_REORDERED",
        "GAP_OPENED", "GAP_CLOSED", "CARDS_AUTO_ARRANGED"]

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
t84, t85, t86, t87 = (T[m] for m in MIG)
h, rb = T[HARNESS], T[ROLLBACK]
allc = "".join(nc(T[n]) for n in MIG)
t81 = rd(os.path.join(DIRS["E1C1"], "5381_restrict_editor_binder_activity_event_types.sql"))[1]

# 1. Forma ---------------------------------------------------------------------------------------
for n, (b, t) in F.items():
    check(f"1.{n[:4]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t, f"{n}: sem CRLF, nova linha final, não executado")
for n in MIG:
    t = T[n]
    check(f"2.{n[:4]}", t.count("\nbegin;\n") == 1 and t.rstrip().endswith("commit;") and "do $pre$" in t and "do $post$" in t,
          f"{n}: transação única com precheck e postcheck")

# 2. 5384: tipos de evento ------------------------------------------------------------------------
g81, g84 = prosrc(t81, GUARD), prosrc(t84, GUARD)
m81, m84 = md5(g81), md5(g84)
b84 = nc(g84)
fich = re.findall(r"'([A-Z_]+)'", re.search(r"new\.event_type in \((.*?)\)\s*and new\.source = 'FICHARIO'", b84, re.S).group(1))
check("3.1", fich == FICH and "(new.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and new.source = 'CATALOGO')" in b84
      and "new.collection_id is null" in b84 and "new.actor_user_id is distinct from new.owner_user_id" in b84,
      f"5384: 14 tipos com origem FICHARIO + novidades só com CATALOGO; coleção obrigatória; só ator ≠ titular ({len(fich)})")
emit = {}
srcs = [os.path.join(DIRS["E1B1"], "5374_create_editor_binder_core_writes.sql"),
        os.path.join(DIRS["E1B2"], "5375_create_editor_binder_curation_writes.sql"),
        os.path.join(DIRS["E1C1"], "5382_create_editor_binder_page_operations.sql"),
        os.path.join(DIRS["E1C1"], "5383_create_editor_binder_species_reference_operations.sql")] + [os.path.join(HERE, m) for m in MIG[1:]]
for p in srcs:
    for m in re.finditer(r"binder_activity_begin\((.*?)\);", nc(rd(p)[1]), re.S):
        args = m.group(1)
        src = re.findall(r"'(FICHARIO|CATALOGO|ACERVO|COLECAO|LEGADO)'", args)
        for ty in set(re.findall(r"'([A-Z_]{4,})'", args)) - {"FICHARIO", "CATALOGO", "SWAP"}:
            emit.setdefault(ty, set()).update(src)
want = {t: {"FICHARIO"} for t in FICH}
want["CATALOG_NOVELTIES_INCORPORATED"] = {"CATALOGO"}
check("3.2", emit == want, f"lista = exatamente os pares (tipo, origem) que as funções do EDITOR abrem: {sorted((k, sorted(v)) for k, v in emit.items())}")
check("3.3", f"is distinct from '{m81}'" in t84 and t84.count(f"'{m84}'") >= 2 and f"'{m84}'" in h and f"'{m84}'" in rb
      and "create or replace function public.binder_activity_event_editor_type_guard()" in t84
      and "create trigger" not in nc(t84).lower() and "grant" not in nc(t84).lower(),
      f"5384: precheck = 5381 ({m81}); md5 novo ({m84}) coerente em 5384, 5893 e rollback; só o corpo muda")

# 3. 5385: espaços --------------------------------------------------------------------------------
GUARD_RE = re.compile(r"if public\.binder_editor_any_foreign\([^;]*?\) then\s+raise exception 'OPERATION_RESERVED_TO_OWNER'", re.S)


def order(body, *xs):
    """Posições em ordem; o marcador GUARD exige o teste completo: if ... then raise reservada ao titular."""
    i = []
    for x in xs:
        if x == "GUARD":
            m = GUARD_RE.search(body)
            i.append(m.start() if m else -1)
        else:
            i.append(body.find(x))
    return -1 not in i and i == sorted(i)
ins = nc(prosrc(t85, "editor_insert_binder_gap"))
cls = nc(prosrc(t85, "editor_close_binder_gap"))
pvg = nc(prosrc(t85, "editor_preview_binder_insert_gap"))
check("4.1", order(ins, "assert_collection_binder_editor_exclusive(p_collection_id)", "binder_gap_evaluate(v_layout, v_slot)",
                   "GAP_PLAN_CHANGED", "GUARD", "binder_activity_begin", "binder_editor_append_page",
                   "for update", "binder_gap_move_pocket") and "add_layout_page" not in ins,
      "inserir: exclusivo → plano canônico → token → conjunto inteiro sem terceiros → só então evento, página, travas e deslocamento")
check("4.2", "v_chain || case when e.target_slot_id is null" in ins and "e.moved_pockets" in ins,
      "inserir: o conjunto afetado são todos os bolsos que andam + o destino")
check("4.3", order(cls, "assert_collection_binder_editor_exclusive(p_collection_id)", "binder_gap_undo_token", "GAP_UNDO_EXPIRED",
                   "GUARD", "for update", "binder_activity_begin",
                   "binder_gap_move_pocket")
      and "collection_layout_slot_species_reference sr where sr.slot_id = s.id" in cls and "remove_layout_page" not in cls,
      "fechar: token de desfazer → trecho inteiro sem terceiros → travas → deslocamento; página só sai vazia de tudo, inclusive referência")
check("4.4", GUARD_RE.search(pvg) and "for update" not in pvg and "editor_binder_exclusive_read(p_collection_id)" in pvg
      and not re.search(r"barrier_|moved_images|slot_id\s+uuid", t85.split("function public.editor_preview_binder_insert_gap")[1].split("$fn$")[0])
      and "binder_editor_any_foreign(" in pvg,
      "prévia: sem trava; exclusivo; recusa terceiros; não devolve barreira, imagens nem ids de bolso")
dml85 = {x for _, x in re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t85), re.I)}
check("4.5", dml85 == {"public.collection_layout_page", "public.collection_layout_slot"}
      and "binder_gap_move_pocket(" in ins and "binder_gap_move_pocket(" in cls,
      f"5385 escreve direto só página/bolsos novos e página removida; o deslocamento é o da 5243: {sorted(dml85)}")
ex = nc(prosrc(t85, "editor_binder_exclusive_read"))
check("4.6", all(x in ex for x in ("m.role = 'EDITOR'", "c.owner_user_id <> v_uid", "collection_layout_guest g where g.layout_id = v_layout",
                                   "OPERATION_RESERVED_TO_OWNER", "COLLECTION_ARCHIVED")) and "for update" not in ex
      and "binder_slot_editor_scope(p_layout_id, p_collection_id, p_collection_id, u.sid) = 'FOREIGN'" in nc(prosrc(t85, "binder_editor_any_foreign")),
      "ajudantes: leitura sem trava com as recusas da 5382; terceiros = classificação 5371/5378")

# 4. 5386: organização automática -----------------------------------------------------------------
ap = nc(prosrc(t86, "editor_apply_binder_auto_arrange"))
pa = nc(prosrc(t86, "editor_preview_binder_auto_arrange"))
check("5.1", order(ap, "assert_collection_binder_editor_exclusive(p_collection_id)", "binder_auto_arrange_plan(", "ALREADY_APPLIED",
                   "AUTO_ARRANGE_LIMIT_EXCEEDED", "GUARD", "for update of s", "for update of pc",
                   "binder_activity_begin", "insert into public.collection_layout_slot_assignment")
      and "AUTO_ARRANGE_PLAN_CHANGED" in ap[ap.find("for update of pc"):ap.find("binder_activity_begin")]
      and "binder_auto_arrange_plan(" in ap[ap.find("for update of pc"):ap.find("binder_activity_begin")]
      and "e.owner_user_id = r.owner_user_id" in ap,
      "aplicar: exclusivo → plano canônico → já aplicado (titular do fichário) → limite → destinos sem terceiros → travas → replano → grava")
check("5.2", GUARD_RE.search(pa) is not None and "for update" not in pa and "'slot_id'" not in pa
      and "function public.binder_auto_arrange_plan" not in t86,
      "prévia: plano canônico (não redefinido), destinos sem terceiros, sem ids de bolso, sem trava")
dml86 = {x for _, x in re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t86), re.I)}
check("5.3", dml86 == {"public.collection_layout_slot_assignment"}, f"5386 só cria posições: {sorted(dml86)}")

# 5. 5387: novidades do Catálogo --------------------------------------------------------------------
ac = nc(prosrc(t87, "editor_apply_binder_catalog_reconciliation"))
pc = nc(prosrc(t87, "editor_preview_binder_catalog_reconciliation"))
fr = "sr.collection_id <> p_collection_id"
check("6.1", order(ac, "assert_collection_binder_editor_exclusive(p_collection_id)", fr, "binder_catalog_assert_eligible(",
                   "RECONCILE_PLAN_CHANGED", "RECONCILE_CONFIRMATION_REQUIRED", "GUARD",
                   "binder_activity_begin(v_layout, 'CATALOG_NOVELTIES_INCORPORATED', 'CATALOGO', p_collection_id)",
                   "binder_editor_append_page", "binder_gap_move_pocket", "insert into public.collection_layout_catalog_incorporation")
      and "add_layout_page" not in ac and "barrier_page" not in ac,
      "aplicar: exclusivo → referência de terceiros → elegibilidade → cabeçalho → conjunto sem terceiros → evento CATALOGO → passos → registro")
aff = nc(prosrc(t87, "binder_editor_catalog_affected"))
check("6.2", all(x in aff for x in ("'IN_PLACE', 'RESERVE_PLACED', 'UPGRADE_RESERVATION', 'SHIFT'", "st.kind = 'SHIFT'",
                                    ">= (st.target_page, st.target_row, st.target_column)", "<= (st.end_page, st.end_row, st.end_column)")),
      "conjunto afetado = destinos de todos os passos + trechos inteiros dos deslocamentos")
check("6.3", order(pc, "editor_binder_exclusive_read(p_collection_id)", fr, "binder_catalog_assert_eligible(", "GUARD")
      and "null::uuid, p.total_items" in pc and "null::integer,\n         null::integer, null::integer, p.plan_token" in pc
      and "case when bf.foreign_ then null else p.barrier_page end" in pc,
      "prévia: sem layout, capacidade e bolsos livres; posição de barreira só se for de X")
dml87 = {x for _, x in re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t87), re.I)}
check("6.4", dml87 == {"public.collection_layout_slot_expected_content", "public.collection_layout_catalog_incorporation"}
      and "values (v_target, st.card_id, null, st.variant_type_id, null)" in ac,
      f"5387 escreve só reservas (sem coleção explícita: X é a proprietária) e o registro; nada de Set, escopo ou acabamento: {sorted(dml87)}")

# 6. Privilégios, titular, escopo ------------------------------------------------------------------
rpcs = {"editor_preview_binder_insert_gap(uuid, integer, integer, integer)": t85,
        "editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)": t85,
        "editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)": t85,
        "editor_preview_binder_auto_arrange(uuid)": t86, "editor_apply_binder_auto_arrange(uuid, text)": t86,
        "editor_preview_binder_catalog_reconciliation(uuid, text[])": t87,
        "editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)": t87}
internal = {"editor_binder_exclusive_read(uuid)": t85, "binder_editor_any_foreign(uuid, uuid, uuid[])": t85,
            "binder_editor_append_page(uuid)": t85, "binder_editor_catalog_affected(uuid, uuid, text[])": t87}
check("7.1", all(f"revoke all on function public.{s} from public, anon;" in t and f"grant execute on function public.{s} to authenticated;" in t
                 for s, t in rpcs.items())
      and all(f"revoke all on function public.{s} from public, anon, authenticated, service_role;" in t
              and f"grant execute on function public.{s}" not in t for s, t in internal.items())
      and not re.search(r"\bgrant\b[^;]*\bto\s+(anon|public|service_role)\b", allc, re.I),
      "7 RPCs só authenticated; 4 ajudantes internos sem EXECUTE para a API")
defs = re.findall(r"create function public\.(\w+)\((.*?)\)\s*returns(.*?)\bas \$", t85 + t86 + t87, re.I | re.S)
check("7.2", len(defs) == 11 and all(re.search(r"security definer", a, re.I) and "set search_path = ''" in a.lower() for _, _, a in defs),
      f"11 funções novas, todas SECURITY DEFINER com search_path vazio ({len(defs)})")
owner = r"function public\.(binder_gap_\w+|insert_my_binder_gap|close_my_binder_gap|preview_my_binder_insert_gap|binder_auto_arrange_plan|" \
        r"\w+_my_binder_auto_arrange|binder_catalog_\w+|\w+_my_binder_catalog_reconciliation|add_layout_page|remove_layout_page|" \
        r"binder_activity_add_\w+|binder_activity_begin|binder_slot_editor_scope|assert_collection_\w+)\("
check("7.3", not re.search(owner, allc, re.I) and "alter table" not in allc.lower() and not re.search(r"\bdrop\b", allc, re.I),
      "nenhuma função do titular ou das entregas anteriores redefinida; planos reusados; nenhum ALTER/DROP")
outs = re.findall(r"function public\.(\w*merge\w*|\w*region\w*|\w*image\w*|get_shared_\w+|\w*objective\w*|\w*orphan\w*|"
                  r"\w*identity\w*|\w*grid\w*|\w*storage\w*|\w*allocat\w*|\w*species_reference\w*)\(", allc, re.I)
check("7.4", not outs and "storage.objects" not in allc
      and not re.search(r"\b(insert\s+into|update|delete\s+from)\s+public\.(collection_allocation|physical_card|collection|collection_reference|card_set|collection_master_set_finish)\b", allc, re.I),
      f"nada de mesclagem, imagens, leituras da E1-D, identidade, grade, Storage, alocação ou escopo ({outs})")

# 7. Reversão --------------------------------------------------------------------------------------
o = [rb.find(f"-- R{n} ") for n in ("5387", "5386", "5385", "5384")]
check("8.1", -1 not in o and o == sorted(o) and rb.count("drop function if exists") == 11
      and md5(prosrc(rb, GUARD)) == m81
      and not re.search(r"\b(delete|truncate|drop\s+table|drop\s+column|drop\s+trigger)\b", nc(rb), re.I),
      "ROLLBACK_E1C2: ordem inversa; 11 funções; devolve a lista da 5381 byte a byte; nada apagado")

# 8. Harness -----------------------------------------------------------------------------------------
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected := (\d+);", h).group(1))
check("9.1", len(ids) + 1 == exp and f"{exp}/{exp} PASS" in h, f"5893: {len(ids)} verificações + F.2 = {exp}")
need = {"várias coleções": "1.1", "convidada desassociada na cadeia": "1.2", "inserir": "1.3", "fechar": "1.4",
        "imagem do titular": "1.6", "token u1 de outro usuário": "1.5", "desfazer com terceiros no trecho": "1.7",
        "elegibilidade alterada": "2.3", "efeitos da incorporação": "3.3", "organização": "2.1", "histórico da organização": "2.2", "novidade": "3.1",
        "novidade alcança terceiros": "3.2", "tipos de evento": "4.1", "origem forjada": "4.2", "recusas": "4.3",
        "revogação": "4.4", "titular": "5.1", "patrimônio": "6.1", "arquivada": "7.1"}
check("9.2", all(v in ids for v in need.values()), f"5893 cobre os cenários pedidos ({[x for x, v in need.items() if v not in ids]})")
check("9.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "MS893" in h and "PENDENTE" in h
      and "binder_activity_item)" in h,
      "5893: sem BEGIN/COMMIT, sentinela, concorrência pendente, resíduo inclui o histórico")

# 9. Entregas anteriores ------------------------------------------------------------------------------
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema"]
                    + [os.path.relpath(x, ROOT) for x in DIRS.values()], capture_output=True, text=True).stdout.strip()
check("10.1", st == "", f"frontend, schema canônico e E1-A … E1-C1 sem alterações ({st or 'limpo'})")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<10} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
