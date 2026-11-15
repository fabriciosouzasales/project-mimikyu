#!/usr/bin/env python3
"""
V1-13 · E1-B2 — verificação ESTÁTICA da proposta 5375–5377 (+ 5890, ROLLBACK_E1B2).

Sem banco. Comprova só propriedades do texto: forma, privilégios, titular
intocado, escopo das escritas, regras de classificação, Storage e cobertura do
harness. Não comprova comportamento, políticas na API do Storage, atomicidade
nem concorrência.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1b2-editor-curation/static_check_e1b2.py
"""
from __future__ import annotations

import glob
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
MIG = ["5375_create_editor_binder_curation_writes.sql", "5376_create_editor_collection_metadata_writes.sql",
       "5377_create_editor_collection_cover_storage_policies.sql"]
HARNESS = "5890_validate_editor_curation_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1B2.sql"
OWNER = {"set_slot_expected_content": ("5276", "33dde5013dbb491bd4a0452ab7ce8132"),
         "clear_slot_expected_content": ("5277", "0b8f26825ff713a24226548ffe3a63b7"),
         "set_slot_lock": ("5278", "651048a4bf7d3229904ef2a073c509c5"),
         "update_collection_metadata": ("5035", "a581235db9cabaf7043707a290f963b7"),
         "set_my_collection_cover_finish": ("5172", "4f48d9161b4a29ecb23e7443e31d1806"),
         "set_my_collection_cover_code": ("5180", "d0d8cbfa517b9da3728a55af47de21cb"),
         "set_my_collection_cover_logo": ("5178", "5868fb1c8de760787d1128ac20a09507")}
E1B1 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1b1-editor-core-binder")
E1A = os.path.join(ROOT, "database", "proposals", "2026-11-14-v1-13-e1a-editor-role")

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
t75, t76, t77 = (T[m] for m in MIG)

# 1. Forma ---------------------------------------------------------------------------------
for n, (b, t) in F.items():
    check(f"1.{n[:4]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t, f"{n}: sem CRLF, nova linha final, não executado")
for n in MIG:
    t = T[n]
    check(f"2.{n[:4]}", t.count("\nbegin;\n") == 1 and t.rstrip().endswith("commit;") and "do $pre$" in t and "do $post$" in t,
          f"{n}: transação única com precheck e postcheck")

# 2. Funções: definer, search_path, qualificação ------------------------------------------------
defs = []
for n in MIG:
    for m in re.finditer(r"create (?:or replace )?function public\.(\w+)\((.*?)\)\s*returns(.*?)\bas \$", T[n], re.I | re.S):
        defs.append((n, m.group(1), m.group(3)))
names = sorted(d[1] for d in defs)
expected = sorted(["editor_set_binder_reservation", "editor_clear_binder_reservation", "editor_set_binder_lock",
                   "assert_collection_editor", "editor_update_collection_metadata", "editor_set_collection_cover_finish",
                   "editor_set_collection_cover_code", "editor_set_collection_cover_logo", "collection_cover_editor_folder_ok",
                   "collection_cover_editor_can_upload"])
check("3.1", names == expected, f"10 funções: {names}")
for n, f, attrs in defs:
    check(f"3.{f}", re.search(r"security definer", attrs, re.I) and "set search_path = ''" in attrs.lower(), f"{f}: definer + search_path vazio")
unq = re.compile(r"(?<!DISTINCT )\b(?:from|join)\s+(?!public\.|pg_catalog\.|storage\.|lateral\b|unnest\b|\()([a-z_]+)", re.I)
leaks = []
for n in MIG:
    for m in re.finditer(r"function public\.(\w+)\(", T[n]):
        for x in unq.finditer(nc(prosrc(T[n], m.group(1)))):
            leaks.append((m.group(1), x.group(1)))
check("3.2", not leaks, f"objetos qualificados ({leaks})")

# 3. Privilégios --------------------------------------------------------------------------------
rpc = {"editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)": t75,
       "editor_clear_binder_reservation(uuid, integer, integer, integer)": t75,
       "editor_set_binder_lock(uuid, integer, integer, integer, boolean)": t75,
       "editor_update_collection_metadata(uuid, text, text)": t76,
       "editor_set_collection_cover_finish(uuid, text)": t76,
       "editor_set_collection_cover_code(uuid, text)": t76,
       "editor_set_collection_cover_logo(uuid, text)": t76}
check("4.1", all(f"revoke all on function public.{s} from public, anon;" in t and f"grant execute on function public.{s} to authenticated;" in t
                 for s, t in rpc.items()), "7 RPCs: EXECUTE só authenticated")
check("4.2", "revoke all on function public.assert_collection_editor(uuid) from public, anon, authenticated, service_role;" in t76
      and "grant execute on function public.assert_collection_editor" not in t76, "assert_collection_editor interna")
check("4.3", all(f"revoke all on function public.{s}(text) from public, anon, service_role;" in t77
                 and f"grant execute on function public.{s}(text) to authenticated;" in t77
                 for s in ("collection_cover_editor_folder_ok", "collection_cover_editor_can_upload"))
      and "(text, boolean)" not in re.sub(r"to_regprocedure\('[^']*'\)", "", nc(t77)),
      "ajudantes das políticas: authenticated (exigido pela avaliação da política), nunca anon; assinatura antiga ausente")
allc = "".join(nc(T[n]) for n in MIG)
check("4.4", not re.search(r"\bgrant\b[^;]*\bto\s+(anon|public|service_role)\b", allc, re.I)
      and not re.search(r"\bgrant\b[^;]*\bon\s+(table\s+)?(public|storage)\.", allc, re.I),
      "nenhum GRANT a anon/PUBLIC/service_role nem privilégio de tabela")

# 4. Titular intocado ---------------------------------------------------------------------------
for f, (num, h) in OWNER.items():
    path = sorted(glob.glob(os.path.join(SCHEMA, f"{num}_*.sql")))[-1]
    check(f"5.{num}", md5(prosrc(rd(path)[1], f)) == h and h in (t75 + t76), f"{f}: md5 canônico {h} e exigido no pre/postcheck")
check("5.x", not re.search(r"function public\.(" + "|".join(OWNER) + r"|assert_collection_layout_mutable)\(", allc, re.I),
      "nenhuma migration redefine função do titular nem a 5122")
check("5.y", not re.search(r"alter policy|drop policy", allc, re.I) and "collection_cover_select_own" in t77,
      "nenhuma política existente alterada ou removida (5176 intacta; só políticas novas)")

# 5. Reservas e travas ---------------------------------------------------------------------------
def body(t, f):
    return nc(prosrc(t, f))
rs, cl, lk = body(t75, "editor_set_binder_reservation"), body(t75, "editor_clear_binder_reservation"), body(t75, "editor_set_binder_lock")
for f, b in (("reservation", rs), ("clear", cl), ("lock", lk)):
    i = [b.find(x) for x in ("assert_collection_binder_editor(p_collection_id)", "binder_slot_at(", "for update", "binder_slot_editor_scope(")]
    check(f"6.{f}", -1 not in i and i == sorted(i), f"{f}: autorização → posição → trava do bolso → classificação")
check("6.1", "v_scope not in ('OWN', 'FREE')" in rs and "v_prev_coll is distinct from p_collection_id" in rs
      and re.search(r"values\s*\(v_slot, p_card_id, p_card_variant_id, p_expected_variant_type_id, p_collection_id\)", rs)
      and "EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE" in rs,
      "reservar: bolso próprio ou livre; reserva existente só de X; nova SEMPRE para X; variante e acabamento exclusivos")
check("6.2", "v_scope <> 'OWN'" in cl and "v_coll is distinct from p_collection_id" in cl and "v_had is not true" in cl,
      "liberar: só reserva de X em bolso próprio; sem reserva → UNCHANGED (NULL tratado)")
check("6.3", "if v_scope <> 'OWN' then" in lk and "'FREE'" not in lk,
      "fixar/soltar: só bolso OWN (livre e de terceiros recusados)")
dml75 = re.findall(r"\b(insert\s+into|update|delete\s+from)\s+(public\.\w+)", nc(t75), re.I)
check("6.4", dml75 and set(t for _, t in dml75) <= {"public.collection_layout_slot_expected_content", "public.collection_layout_slot"},
      f"5375: escrita direta só em reservas e na trava do bolso: {sorted(set(t for _, t in dml75))}")
check("6.5", all(re.search(r"binder_activity_begin\([^;]*p_collection_id\)", b) for b in (rs, cl, lk)),
      "5375: eventos registram a coleção autorizada (exigência da 5372)")
check("6.6", all(x in rs for x in ["'POCKET_RESERVED', 'FICHARIO'", "binder_activity_add_reservation_item('RELEASED', v_slot)",
                                    "binder_activity_add_reservation_item('RESERVED', v_slot)"])
      and "'RESERVATIONS_RELEASED', 'FICHARIO'" in cl
      and "'POCKETS_LOCKED' else 'POCKETS_UNLOCKED'" in lk and "binder_activity_add_item('POCKET'" in lk,
      "espelho do titular: mesmos tipos de evento e itens de 5276–5278")
check("6.7", not re.search(r"merge|unmerge|region", nc(t75), re.I),
      "nenhuma operação de mesclagem (toda mesclagem vigente carrega imagem do titular — C-237/C-238)")

# 6. Metadados e capa -----------------------------------------------------------------------------
ace = body(t76, "assert_collection_editor")
i = [ace.find(x) for x in ("m.role = 'EDITOR'", "for update;", "for share;", "COLLECTION_ARCHIVED")]
check("7.1", -1 not in i and i == sorted(i) and "c.owner_user_id <> v_uid" in ace,
      "assert_collection_editor: papel → coleção (FOR UPDATE) → participação (FOR SHARE) → arquivada só depois de autorizado")
upd = re.findall(r"update public\.collection c\s+set ([^;]*?)\s+where", nc(t76), re.I | re.S)
cols = sorted({c.strip().split("=")[0].strip() for s in upd for c in s.split(",")})
check("7.2", cols == ["cover_code", "cover_finish", "cover_logo_path", "description", "name"],
      f"5376 só altera nome, descrição, acabamento, código e imagem da capa: {cols}")
check("7.3", not re.search(r"\b(visibility|lifecycle_status\s*=|completion_policy\s*=|mode\s*=|owner_user_id\s*=\s*(?!v_owner|v_uid))", " ".join(upd), re.I)
      and "collection_layout" not in nc(t76),
      "nada de visibilidade, arquivamento, política, modalidade, titularidade ou fichário")
lg = body(t76, "editor_set_collection_cover_logo")
check("7.4", "left(v_path, 74) <> v_owner::text || '/' || p_collection_id::text || '/'" in lg
      and "o.owner_id in (v_uid::text, v_owner::text)" in lg and "v_prev_mine" in lg,
      "imagem da placa: pasta do TITULAR; arquivo do EDITOR ou do titular; só arquivo do EDITOR volta para exclusão")
check("7.5", "objetivo textual" in t76.lower() and "não implementado" in t76.lower(),
      "objetivo textual não implementado (sem campo no modelo — decisão de produto)")

# 7. Storage ----------------------------------------------------------------------------------------
fo = body(t77, "collection_cover_editor_folder_ok")
check("8.1", all(x in fo for x in ["m.status = 'ACTIVE' and m.role = 'EDITOR'", "c.owner_user_id = v_owner", "c.lifecycle_status = 'ACTIVE'",
                                    "v_owner = v_uid", "p_name is distinct from v_cur"]) and "count(" not in fo,
      "ajudante de ver/apagar: EDITOR ACTIVE, pasta do titular da coleção, coleção ativa, nunca a capa atual; sem contagem")
up = body(t77, "collection_cover_editor_can_upload")
attrs = {f: a.lower() for _, f, a in defs}
iu = [up.find(x) for x in ("v_owner = v_uid", "pg_catalog.pg_advisory_xact_lock(", "public.collection_cover_editor_folder_ok(p_name) is not true",
                           "count(*)", "return v_n < 3")]
check("8.4", -1 not in iu and iu == sorted(iu)
      and re.search(r"hashtextextended\(\s*'mmkyu:collection-cover-editor:' \|\| v_uid::text \|\| ':' \|\| v_coll::text", up)
      and re.search(r"\bvolatile\b", attrs["collection_cover_editor_can_upload"])
      and re.search(r"\bstable\b", attrs["collection_cover_editor_folder_ok"]),
      "envio: ajudante VOLÁTIL; trava consultiva (EDITOR, coleção) antes de reautorizar e contar; teto 3 (estático, sem prova de corrida)")
check("8.5", "SEM PROVA" in t77 and "READ COMMITTED" in t77 and "+1" not in t77 and "em 1 (" not in t77,
      "5377 declara a dependência de READ COMMITTED e da API do Storage; nenhuma alegação de \"+1\"")
pol = re.findall(r"create policy (\w+)\s+on storage\.objects\s+for (\w+)\s+to (\w+)\s+(using|with check)\s*\((.*?)\);", nc(t77), re.I | re.S)
check("8.2", sorted((p[0], p[1].upper(), p[2]) for p in pol) == [("collection_cover_delete_editor", "DELETE", "authenticated"),
                                                               ("collection_cover_insert_editor", "INSERT", "authenticated"),
                                                               ("collection_cover_select_editor", "SELECT", "authenticated")]
      and all("bucket_id = 'collection-cover'" in p[4] for p in pol),
      "três políticas novas, só authenticated, restritas ao bucket; nenhuma de UPDATE")
check("8.3", all("owner_id = (select auth.uid())::text" in p[4] for p in pol if p[1].upper() in ("SELECT", "DELETE"))
      and all("collection_cover_editor_folder_ok(name)" in p[4] for p in pol if p[1].upper() in ("SELECT", "DELETE"))
      and all("collection_cover_editor_can_upload(name)" in p[4] and "folder_ok" not in p[4] for p in pol if p[1].upper() == "INSERT"),
      "ver e apagar só arquivos enviados pelo próprio EDITOR; enviar só com o ajudante")

# 8. Harness, reversão, escopo ------------------------------------------------------------------------
h = T[HARNESS]
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected := (\d+);", h).group(1))
check("9.1", len(ids) + 1 == exp, f"5890: {len(ids)} verificações + F.2 = {exp}")
need = {"EDITOR autorizado": "1.1", "VIEWER/não membro/removido": "1.7", "reserva de outra coleção": "1.5",
        "bolso vazio com referência oculta": "1.5", "fixação de terceiros": "3.3", "mesclagem": "3.3",
        "várias coleções": "2.4", "metadados exclusivos do titular": "4.3", "Storage indevido": "6.2",
        "teto do Storage": "6.1", "exclusão real": "6.9", "trava do teto": "0.5", "mudança de papel": "7.1", "arquivada": "11.1", "titular": "9.1", "patrimônio": "10.1"}
check("9.2", all(v in ids for v in need.values()), f"5890 cobre os cenários pedidos ({[k for k, v in need.items() if v not in ids]})")
check("9.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "MS890" in h and "storage.objects)]" in h
      and "PENDENTE" in h, "5890: sem BEGIN/COMMIT, sentinela, resíduo inclui storage.objects, concorrência pendente")
rb = T[ROLLBACK]
o = [rb.find(f"-- R{n}") for n in ("5377", "5376", "5375")]
check("9.4", -1 not in o and o == sorted(o) and rb.count("drop function if exists") == 10 and rb.count("drop policy if exists") == 3
      and "collection_cover_editor_can_upload(text)" in rb and "collection_cover_editor_folder_ok(text)" in rb,
      "ROLLBACK_E1B2: ordem inversa; remove as 10 funções e as 3 políticas")
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema",
                     os.path.relpath(E1A, ROOT), os.path.relpath(E1B1, ROOT)], capture_output=True, text=True).stdout.strip()
check("9.5", st == "", f"frontend, schema canônico, E1-A e E1-B1 sem alterações ({st or 'limpo'})")
outs = re.findall(r"function public\.(set_pokedex_\w+|\w*species\w*|add_layout_page|remove_layout_page|reorder_layout_pages|\w*auto_arrange\w*|merge_\w+|binder_activity_\w+)\(", allc, re.I)
check("9.6", not outs, f"nada de E1-B3/E1-C/histórico redefinido ({outs})")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<30} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
