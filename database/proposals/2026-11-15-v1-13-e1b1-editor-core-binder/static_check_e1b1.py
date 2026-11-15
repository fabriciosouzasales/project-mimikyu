#!/usr/bin/env python3
"""
V1-13 · E1-B1 — verificação ESTÁTICA da proposta 5371–5374 (+ 5889, ROLLBACK_E1B1).

Não conecta em banco: lê só os arquivos desta pasta, os canônicos de
database/schema/ e o estado do Git do frontend. Não comprova comportamento,
atomicidade, isolamento nem concorrência — só propriedades do texto.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1b1-editor-core-binder/static_check_e1b1.py
"""
from __future__ import annotations

import difflib
import glob
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
MIG = ["5371_create_binder_editor_authorization.sql", "5372_allow_editor_actor_in_binder_activity.sql",
       "5373_create_get_shared_binder_placeable_cards.sql", "5374_create_editor_binder_core_writes.sql"]
HARNESS = "5889_validate_editor_core_binder_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1B1.sql"
OWNER_MD5 = {"assert_collection_layout_mutable": ("5122", "d600f36fade0b67c0fd5af33e9965070"),
             "place_my_physical_card_in_slot": ("5272", "2672da179d73797ec5329c649b594202"),
             "move_slot_assignment": ("5273", "fe149c755b5f3b9181172e600c2238a3"),
             "remove_slot_assignment": ("5274", "e4b6c8cd8e8c61554ddc92304d602a73"),
             "binder_activity_add_item": ("5268", "5ac90272cf7bc203e5d2316ea4eba7d4")}
NEW_ADD_ITEM_MD5 = "59ec5791e514026b7a8340e104d66f30"

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


def bodies(text):
    out = []
    for m in re.finditer(r"(?:create|create or replace) function public\.(\w+)\(", text, re.I):
        out.append((m.group(1), prosrc(text, m.group(1))))
    return out


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


F = {n: rd(os.path.join(HERE, n)) for n in MIG + [HARNESS, ROLLBACK]}
T = {n: v[1] for n, v in F.items()}

# 1. Higiene e forma -------------------------------------------------------------------------
for n, (b, t) in F.items():
    check(f"1.{n[:4]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t, f"{n}: sem CRLF, termina em nova linha, marcado como não executado")
for n in MIG:
    t = T[n]
    check(f"2.{n[:4]}", t.count("\nbegin;\n") == 1 and t.rstrip().endswith("commit;") and "do $pre$" in t and "do $post$" in t
          and "set local lock_timeout = '5s';" in t, f"{n}: transação única com precheck, postcheck e lock_timeout")

# 2. Funções: definer, search_path, objetos qualificados ----------------------------------------
defs = []
for n in MIG:
    for m in re.finditer(r"create (?:or replace )?function public\.(\w+)\((.*?)\)\s*returns(.*?)\bas \$", T[n], re.I | re.S):
        defs.append((n, m.group(1), m.group(3)))
names = sorted(d[1] for d in defs)
check("3.1", names == sorted(["assert_collection_binder_editor", "binder_slot_editor_scope", "binder_slot_at",
                              "binder_activity_add_item", "get_shared_binder_placeable_cards",
                              "editor_place_card_in_binder", "editor_move_binder_card", "editor_remove_binder_card"]),
      f"8 funções definidas: {names}")
for n, f, attrs in defs:
    check(f"3.{f}", re.search(r"security definer", attrs, re.I) and "set search_path = ''" in attrs.lower(),
          f"{f}: SECURITY DEFINER e search_path vazio")
unq = re.compile(r"(?<!DISTINCT )\b(?:from|join)\s+(?!public\.|pg_catalog\.|lateral\b|unnest\b|\(|el\b|tot\b)([a-z_]+)", re.I)
leaks = []
for n in MIG:
    for f, b in bodies(T[n]):
        for m in unq.finditer(strip_comments(b)):
            leaks.append((f, m.group(1)))
check("3.2", not leaks, f"objetos qualificados nos corpos (não qualificados: {leaks})")

# 3. Privilégios ------------------------------------------------------------------------------
t71 = T[MIG[0]]
check("4.1", all(f"revoke all on function public.{f}" in t71 and f"{f}" in t71 for f in
                 ["assert_collection_binder_editor(uuid) from public, anon, authenticated, service_role",
                  "binder_slot_editor_scope(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role",
                  "binder_slot_at(uuid, integer, integer, integer) from public, anon, authenticated, service_role"])
      and "grant" not in strip_comments(t71).lower(), "5371: três internas sem EXECUTE para PUBLIC/anon/authenticated/service_role; nenhum GRANT")
t73, t74 = T[MIG[2]], T[MIG[3]]
rpc = ["get_shared_binder_placeable_cards(uuid, integer, integer)",
       "editor_place_card_in_binder(uuid, integer, integer, integer, uuid)",
       "editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)",
       "editor_remove_binder_card(uuid, integer, integer, integer)"]
check("4.2", all(f"revoke all on function public.{s} from public, anon;" in (t73 + t74)
                 and f"grant execute on function public.{s} to authenticated;" in (t73 + t74) for s in rpc),
      "RPCs do EDITOR: EXECUTE só authenticated (revogado de PUBLIC e anon)")
allsql = "".join(strip_comments(T[n]) for n in MIG)
check("4.3", not re.search(r"\bgrant\b[^;]*\bto\s+(anon|public|service_role)\b", allsql, re.I)
      and not re.search(r"\bgrant\b[^;]*\bon\s+(table\s+)?public\.", allsql, re.I),
      "nenhum GRANT para anon/PUBLIC/service_role nem privilégio de tabela")

# 4. Titular e 5122 intocados ---------------------------------------------------------------
for f, (num, h) in OWNER_MD5.items():
    path = glob.glob(os.path.join(SCHEMA, f"{num}_*.sql"))[0]
    check(f"5.{num}", md5(prosrc(rd(path)[1], f)) == h, f"{f}: md5 canônico = {h}")
check("5.x", not re.search(r"function public\.(assert_collection_layout_mutable|place_my_physical_card_in_slot|move_slot_assignment|remove_slot_assignment)\(",
                           allsql, re.I),
      "nenhuma migration redefine a 5122 nem as escritas do titular 5272–5274")
check("5.y", all(OWNER_MD5[k][1] in t74 for k in ("place_my_physical_card_in_slot", "move_slot_assignment", "remove_slot_assignment"))
      and "d600f36fade0b67c0fd5af33e9965070" in t71,
      "pre/postchecks exigem a 5122 e as escritas do titular byte a byte canônicas")

# 5. 5372: mudança mínima e md5 --------------------------------------------------------------
orig = rd(glob.glob(os.path.join(SCHEMA, "5268_*.sql"))[0])[1]
oi = orig.index("create function public.binder_activity_add_item(")
ofn = orig[oi:orig.index("$fn$;", orig.index("as $fn$", oi) + 7) + 5]
t72 = T[MIG[1]]
ni = t72.index("create or replace function public.binder_activity_add_item(")
nfn = t72[ni:t72.index("$fn$;", t72.index("as $fn$", ni) + 7) + 5]
d = [l for l in difflib.unified_diff(ofn.splitlines(), nfn.splitlines(), lineterm="", n=0) if l[:1] in "+-" and l[:3] not in ("+++", "---")]
removed = [l for l in d if l.startswith("-")]
check("6.1", removed == ["-create function public.binder_activity_add_item(",
                         "-      raise exception 'binder activity: actor is not the binder owner' using errcode = '42501',",
                         "-        hint = 'BINDER_ACTIVITY_NOT_OWNER';",
                         "-    v_coll := nullif(v_ctx ->> 'collection', '')::uuid;"],
      f"5372: só saem a linha de criação, a recusa incondicional e a posição antiga de v_coll ({removed})")
added = "\n".join(l[1:] for l in d if l.startswith("+"))
check("6.2", all(x in added for x in ["m.status = 'ACTIVE' and m.role = 'EDITOR'", "c.owner_user_id = v_owner",
                                       "collection_layout_guest", "v_coll is null"])
      and added.count("raise exception 'binder activity: actor is not the binder owner'") == 1,
      "5372: ator ≠ titular só como EDITOR ACTIVE da coleção do evento, do mesmo titular, participante do fichário")
check("6.3", md5(prosrc(t72, "binder_activity_add_item")) == NEW_ADD_ITEM_MD5 and t72.count(NEW_ADD_ITEM_MD5) >= 2
      and OWNER_MD5["binder_activity_add_item"][1] in t72 and NEW_ADD_ITEM_MD5 in t74,
      "5372: md5 novo conferido (JÁ APLICADA/postcheck) e exigido pela 5374; md5 antigo no precheck")

# 6. Autorização e classificação -------------------------------------------------------------
a = prosrc(t71, "assert_collection_binder_editor")
pos = [a.find(x) for x in ["m.role = 'EDITOR'", "for update;", "for update;\n  if not found then\n    raise exception 'BINDER_NOT_FOUND'",
                            "for share;", "m.status = 'ACTIVE' and m.role = 'EDITOR'\n  for share;"]]
check("7.1", -1 not in pos and pos == sorted(pos),
      "5371: papel EDITOR ACTIVE → trava proprietária → layout → convidada (FOR SHARE) → participação (FOR SHARE), nesta ordem")
check("7.2", "c.owner_user_id <> v_uid" in a and a.count("COLLECTION_NOT_FOUND") >= 3,
      "5371: titular, não membro, VIEWER e participação inativa caem na mesma recusa COLLECTION_NOT_FOUND")
s = prosrc(t71, "binder_slot_editor_scope")
need = ["collection_layout_slot_assignment", "collection_allocation", "collection_layout_slot_expected_content",
        "coalesce(e.collection_id, p_anchor_collection_id)", "collection_layout_slot_image", "collection_layout_region",
        "collection_layout_slot_species_reference", "v_locked and not v_own"]
check("7.3", all(x in s for x in need) and s.count("return 'FOREIGN';") >= 7 and "update" not in strip_comments(s).lower()
      and "insert" not in strip_comments(s).lower() and "delete" not in strip_comments(s).lower(),
      "5371: classificação considera carta, alocação, reserva (C-196), imagem, região, espécie e trava; só lê")

# 7. Escritas do EDITOR ------------------------------------------------------------------------
w = {f: prosrc(t74, f) for f in ("editor_place_card_in_binder", "editor_move_binder_card", "editor_remove_binder_card")}
for f, b in w.items():
    c = strip_comments(b)
    i_auth = c.find("assert_collection_binder_editor(p_collection_id)")
    i_slot = c.find("binder_slot_at(")
    i_scope = c.find("binder_slot_editor_scope(")
    i_lock = c.find("raise exception 'SLOT_LOCKED'")
    i_dml = min([x for x in (c.find("insert into public.collection_layout_slot_assignment"),
                             c.find("update public.collection_layout_slot_assignment"),
                             c.find("delete from public.collection_layout_slot_assignment")) if x >= 0])
    check(f"8.{f}", 0 <= i_auth < i_slot < i_scope < i_lock < i_dml,
          f"{f}: autorização → bolso por posição → classificação → trava → escrita")
    dml = re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", c, re.I)
    check(f"9.{f}", dml and all(t == "public.collection_layout_slot_assignment" for _, t in dml),
          f"{f}: escreve só em collection_layout_slot_assignment (nada patrimonial): {sorted(set(t for _, t in dml))}")
    check(f"10.{f}", re.search(r"binder_activity_begin\([^;]*p_collection_id\)", c) is not None,
          f"{f}: evento do histórico registra a coleção autorizada (exigência da 5372)")
pl = strip_comments(w["editor_place_card_in_binder"])
check("11.1", all(x in pl for x in ["i.owner_user_id = v_owner", "ca.collection_id = p_collection_id",
                                     "v_card_cont is distinct from v_container", "for update of pc for share of ca"])
      and pl.count("PHYSICAL_CARD_NOT_ELIGIBLE") == 1,
      "colocar: exemplar do titular, alocado à coleção, no local do fichário, relido sob trava; uma só recusa")
check("11.2", "v_scope not in ('OWN', 'FREE')" in pl and "ca.physical_card_id = v_old_card and ca.collection_id = p_collection_id" in pl,
      "colocar: destino próprio ou livre; REPLACE só de exemplar da coleção")
mv = strip_comments(w["editor_move_binder_card"])
check("11.3", "v_scope_from <> 'OWN' or v_scope_to not in ('OWN', 'FREE')" in mv and mv.count("ca.collection_id = p_collection_id") == 2,
      "mover: origem própria com carta da coleção; destino próprio ou livre; troca só com carta da coleção")
rm = strip_comments(w["editor_remove_binder_card"])
check("11.4", "v_scope <> 'OWN'" in rm and "delete from public.collection_layout_slot_assignment where id = v_asg" in rm,
      "retirar: só bolso próprio; apaga só a posição")
leakmsg = re.findall(r"'(CARD_NOT_IN_BINDER_LOCATION|SLOT_NOT_FOUND|PHYSICAL_CARD_NOT_FOUND|NOT_OWNER)'", strip_comments(t74))
check("11.5", not leakmsg and strip_comments(t74).count("'SLOT_NOT_EDITABLE'") >= 8,
      f"recusas neutras: bolso inexistente e de terceiros dão a mesma SLOT_NOT_EDITABLE; nenhuma mensagem do titular que revele local ({leakmsg})")
check("11.6", all("set lock_timeout = '5s'" in t74.split(f"function public.{f}(", 1)[1].split("$fn$", 1)[0] for f in w),
      "escritas do EDITOR com lock_timeout próprio de 5 s (igual à 5272)")

# 8. Dever de espelho com o titular -----------------------------------------------------------
own = {n: prosrc(rd(glob.glob(os.path.join(SCHEMA, f"{n}_*.sql"))[0])[1], f)
       for n, f in (("5272", "place_my_physical_card_in_slot"), ("5273", "move_slot_assignment"), ("5274", "remove_slot_assignment"))}
mirror = [
    ("5272", "'CARD_PLACED', 'FICHARIO'", "editor_place_card_in_binder", "'CARD_PLACED', 'FICHARIO'"),
    ("5272", "binder_activity_add_card_item('REMOVED', v_old_card", "editor_place_card_in_binder", "binder_activity_add_card_item('REMOVED', v_old_card"),
    ("5272", "binder_activity_add_card_item('PLACED', p_physical_card_id", "editor_place_card_in_binder", "binder_activity_add_card_item('PLACED', p_physical_card_id"),
    ("5272", "raise exception 'CARD_ALREADY_PLACED' using errcode = '23505'", "editor_place_card_in_binder", "raise exception 'CARD_ALREADY_PLACED' using errcode = '23505'"),
    ("5273", "'CARDS_SWAPPED' ELSE 'CARD_MOVED'", "editor_move_binder_card", "'CARDS_SWAPPED' else 'CARD_MOVED'"),
    ("5274", "'CARDS_REMOVED', 'FICHARIO'", "editor_remove_binder_card", "'CARDS_REMOVED', 'FICHARIO'"),
]
bad = [x for x in mirror if x[1] not in own[x[0]] or x[3] not in w[x[2]]]
check("12.1", not bad, f"espelho: mesmos tipos de evento, efeitos de item e erros do titular ({bad})")

# 9. Leitura dos elegíveis -----------------------------------------------------------------------
rdb = strip_comments(prosrc(t73, "get_shared_binder_placeable_cards"))
cols = re.search(r"returns table \((.*?)\)\s*language", t73, re.S | re.I).group(1)
check("13.1", all(x in rdb for x in ["m.role = 'EDITOR'", "ca.collection_id = p_collection_id", "pc.storage_container_id = v_container",
                                      "not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)",
                                      "i.owner_user_id = v_owner"])
      and "raise exception 'COLLECTION" not in rdb,
      "elegíveis: EDITOR ACTIVE; alocado à coleção; no local do fichário; fora de bolso; não EDITOR → zero linhas (sem exceção que enumere)")
check("13.2", not re.search(r"(storage|location|condition|price|value|paid|acqui|note|favorite|wish|owner|collection_id|allocation)", cols, re.I),
      f"elegíveis: colunas sem dado privado ({' '.join(cols.split())})")
check("13.3", "p_limit > 96" in rdb and "order by cs.code, c.collector_order, c.collector_number, l.code, el.pcid" in rdb,
      "elegíveis: paginação limitada e ordem total determinística")

# 10. Harness e reversão --------------------------------------------------------------------------
h = T[HARNESS]
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected integer := (\d+);", h).group(1))
check("14.1", len(ids) + 1 == exp, f"5889: {len(ids)} verificações + F.2 = {exp}")
need_ids = {"VIEWER": "1.1", "não membro": "1.2", "titular no caminho do EDITOR": "1.3", "removido": "1.4",
            "EDITOR de outra coleção": "1.5", "anon": "1.6", "troca de papel": "1.7", "elegíveis": "2.1",
            "bolso de terceiro": "3.1", "fixado": "3.3", "inexistente": "3.4", "não alocado/outro local/forjado": "3.5",
            "mover para terceiro": "4.3", "retirar terceiro": "5.2", "várias coleções": "6.2", "histórico": "7.1",
            "titular intacto": "8.1", "patrimônio": "9.2", "imagem e mesclagem aparentemente vazias": "10.2",
            "estado composto (carta de X + reserva de terceiro)": "10.3", "convidada arquivada": "10.4"}
missing = [k for k, v in need_ids.items() if v not in ids]
check("14.2", not missing, f"5889 cobre os cenários pedidos (faltando: {missing})")
check("14.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "MS889" in h and "'99.1'" in h
      and "protocolo controlado" in h and "PENDENTES" in h,
      "5889: sem BEGIN/COMMIT próprios, sentinela, resíduo zero, só sob protocolo controlado; concorrência declarada pendente")
rbt = T[ROLLBACK]
order = [rbt.find(f"-- R{n}") for n in ("5374", "5373", "5372", "5371")]
check("15.1", -1 not in order and order == sorted(order) and md5(prosrc(rbt, "binder_activity_add_item")) == OWNER_MD5["binder_activity_add_item"][1],
      "ROLLBACK_E1B1: ordem inversa e 5268 restaurada byte a byte")

# 11. Fora do escopo ----------------------------------------------------------------------------
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web"], capture_output=True, text=True).stdout.strip()
check("16.1", st == "", f"frontend sem alterações ({st or 'limpo'})")
outscope = re.findall(r"function public\.(set_slot_expected_content|clear_slot_expected_content|set_slot_lock|merge_layout_region|unmerge_layout_region|update_collection_metadata|set_pokedex_\w+|add_layout_page|remove_layout_page)\(", allsql, re.I)
check("16.2", not outscope, f"nada de E1-B2/E1-B3/E1-C redefinido ({outscope})")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<34} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
