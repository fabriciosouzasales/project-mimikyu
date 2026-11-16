#!/usr/bin/env python3
"""
V1-13 · G1 (D-E1) — gerador determinístico das versões PROTEGIDAS das propostas
E1-A … E1-D e do procedimento de STOP emergencial.

Não executa nada no banco. Lê os arquivos auditados (que NÃO são alterados) e
escreve em g1/protected/ cópias com uma única classe de mudança:

  1. a porta da 5389 consultada como PRIMEIRA instrução do corpo de cada
     capacidade nova (convite: só no ramo papel = 'EDITOR', logo depois da
     validação do papel e antes de qualquer leitura);
  2. um precheck que recusa aplicar sem a 5389;
  3. na 5369 e na 5370, as constantes md5 do próprio corpo (pre/postcheck)
     trocadas pelo md5 do corpo protegido;
  4. um cabeçalho de rastreabilidade.

Toda linha inserida termina com "-- G1 (D-E1)". static_check_g1.py desfaz as
mudanças e exige igualdade byte a byte com o arquivo auditado.

    python3 -I -B .../g1/build_g1_protected.py          # gera
    python3 -I -B .../g1/build_g1_protected.py --check  # confere (não escreve)
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROP = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "protected")
TAG = "-- G1 (D-E1)"

A = "2026-11-14-v1-13-e1a-editor-role"
B1 = "2026-11-15-v1-13-e1b1-editor-core-binder"
B2 = "2026-11-15-v1-13-e1b2-editor-curation"
B3 = "2026-11-15-v1-13-e1b3-pokedex-history"
C1 = "2026-11-15-v1-13-e1c-bulk-operations"
C2 = "2026-11-15-v1-13-e1c2-remaining-bulk-operations"
D = "2026-11-15-v1-13-e1d-shared-reads"

W, R, H, INV = "write", "read", "helper", "invite"

# (pasta, arquivo, [(função, tipo)]) — inventário fechado de 37 capacidades.
SOURCES = [
    (A, "5369_replace_invite_collection_member_with_role.sql", [("invite_collection_member", INV)]),
    (A, "5370_create_set_collection_member_role_function.sql", [("set_collection_member_role", W)]),
    (B1, "5373_create_get_shared_binder_placeable_cards.sql", [("get_shared_binder_placeable_cards", R)]),
    (B1, "5374_create_editor_binder_core_writes.sql",
     [("editor_place_card_in_binder", W), ("editor_move_binder_card", W), ("editor_remove_binder_card", W)]),
    (B2, "5375_create_editor_binder_curation_writes.sql",
     [("editor_set_binder_reservation", W), ("editor_clear_binder_reservation", W), ("editor_set_binder_lock", W)]),
    (B2, "5376_create_editor_collection_metadata_writes.sql",
     [("editor_update_collection_metadata", W), ("editor_set_collection_cover_finish", W),
      ("editor_set_collection_cover_code", W), ("editor_set_collection_cover_logo", W)]),
    (B2, "5377_create_editor_collection_cover_storage_policies.sql",
     [("collection_cover_editor_folder_ok", H), ("collection_cover_editor_can_upload", H)]),
    (B3, "5380_create_editor_pokedex_position_writes.sql",
     [("editor_set_pokedex_position_assignment", W), ("editor_remove_pokedex_position_assignment", W),
      ("editor_set_pokedex_position_primary_representative", W),
      ("editor_clear_pokedex_position_primary_representative", W)]),
    (C1, "5382_create_editor_binder_page_operations.sql",
     [("editor_add_binder_page", W), ("editor_remove_binder_page", W), ("editor_reorder_binder_pages", W)]),
    (C1, "5383_create_editor_binder_species_reference_operations.sql",
     [("editor_preview_binder_species_references", W), ("editor_apply_binder_species_references", W),
      ("editor_clear_binder_species_references", W), ("editor_set_binder_species_reference_visibility", W)]),
    (C2, "5385_create_editor_binder_gap_operations.sql",
     [("editor_preview_binder_insert_gap", W), ("editor_insert_binder_gap", W), ("editor_close_binder_gap", W)]),
    (C2, "5386_create_editor_binder_auto_arrange.sql",
     [("editor_preview_binder_auto_arrange", W), ("editor_apply_binder_auto_arrange", W)]),
    (C2, "5387_create_editor_binder_catalog_reconciliation.sql",
     [("editor_preview_binder_catalog_reconciliation", W), ("editor_apply_binder_catalog_reconciliation", W)]),
    (D, "5323_create_get_shared_master_set_positions_function.sql", [("get_shared_master_set_positions", R)]),
    (D, "5324_create_get_shared_pokedex_positions_function.sql", [("get_shared_pokedex_positions", R)]),
    (D, "5388_create_get_shared_binder_activity_functions.sql",
     [("get_shared_binder_activity", R), ("get_shared_binder_activity_status", R)]),
]
STORAGE_POLICIES = ["collection_cover_insert_editor", "collection_cover_select_editor", "collection_cover_delete_editor"]
SELF_MD5 = {"invite_collection_member", "set_collection_member_role"}

GATE = {
    W: "perform public.v1_13_assert_capability();",
    R: "if not public.v1_13_capability_open() then return; end if;",
    H: "if not public.v1_13_capability_open() then return false; end if;",
}
INVITE_ANCHOR = ("    IF v_role NOT IN ('VIEWER', 'EDITOR') THEN\n"
                 "        RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';\n"
                 "    END IF;\n")
INVITE_GATE = "    IF v_role = 'EDITOR' THEN PERFORM public.v1_13_assert_capability(); END IF;  " + TAG + "\n"
PRE_GATE = ("  if to_regprocedure('public.v1_13_assert_capability()') is null "
            "or to_regprocedure('public.v1_13_capability_open()') is null then "
            "raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  " + TAG + "\n")


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def md5(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def body_span(text: str, fn: str) -> tuple[int, int]:
    m = re.search(r"(?is)create (?:or replace )?function\s+public\." + fn + r"\s*\(.*?\bas\s+(\$[A-Za-z0-9_]*\$)", text)
    if not m:
        raise SystemExit(f"função {fn} não encontrada")
    a = m.end()
    return a, text.index(m.group(1), a)


def signature(text: str, fn: str) -> str:
    m = re.search(r"(?i)grant execute on function (public\." + fn + r"\([^)]*\)) to authenticated", text)
    if not m:
        raise SystemExit(f"GRANT de {fn} não encontrado")
    return m.group(1)


def protect(folder: str, fname: str, funcs: list) -> tuple[str, dict]:
    src = os.path.join(PROP, folder, fname)
    raw = open(src, "rb").read()
    t = raw.decode("utf-8")
    info = {"base": f"{folder}/{fname}", "base_sha256": sha256(raw), "functions": {}}
    old_md5 = {fn: md5(t[slice(*body_span(t, fn))]) for fn, _ in funcs}
    for fn, kind in funcs:
        a, z = body_span(t, fn)
        body = t[a:z]
        if kind == INV:
            if body.count(INVITE_ANCHOR) != 1:
                raise SystemExit("âncora do convite não encontrada")
            nb = body.replace(INVITE_ANCHOR, INVITE_ANCHOR + INVITE_GATE)
        else:
            m = re.search(r"(?im)^[ \t]*begin[ \t]*\n", body)
            if not m:
                raise SystemExit(f"begin do corpo de {fn} não encontrado")
            nxt = re.search(r"(?m)^([ \t]*)\S", body[m.end():])
            ind = nxt.group(1) if nxt else "  "
            nb = body[:m.end()] + ind + GATE[kind] + "  " + TAG + "\n" + body[m.end():]
        t = t[:a] + nb + t[z:]
    # precheck da 5389
    m = re.search(r"(?im)^do \$pre\$\n(declare\n(?:.*\n)*?)?begin\n", t)
    if not m:
        raise SystemExit(f"bloco $pre$ não encontrado em {fname}")
    t = t[:m.end()] + PRE_GATE + t[m.end():]
    for fn, kind in funcs:
        new = md5(t[slice(*body_span(t, fn))])
        info["functions"][fn] = {"kind": kind, "md5_base": old_md5[fn], "md5_protected": new,
                                 "signature": signature(t, fn) if kind != INV else signature(t, fn)}
        if fn in SELF_MD5:
            if t.count(old_md5[fn]) < 1:
                raise SystemExit(f"constante md5 de {fn} não encontrada")
            t = t.replace(old_md5[fn], new)
            if md5(t[slice(*body_span(t, fn))]) != new:
                raise SystemExit("md5 do corpo mudou ao trocar constantes")
    banner = (
        "/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.\n"
        f"   Base auditada: database/proposals/{folder}/{fname}\n"
        f"   sha256 da base: {info['base_sha256']}\n"
        f"   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em {len(funcs)} função(ões); "
        "precheck da 5389"
        + ("; constantes md5 do próprio corpo atualizadas" if any(f in SELF_MD5 for f, _ in funcs) else "")
        + ".\n   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */\n")
    return banner + t, info


def emergency(infos: list) -> str:
    sigs = [f["signature"] for i in infos for fn, f in i["functions"].items()
            if f["kind"] in (W, R) and fn != "invite_collection_member"]
    lines = [
        "/*",
        "================================================================",
        "Projeto.....: Project Mimikyu",
        "Query.......: EMERGENCY_STOP_V1_13 — desligamento emergencial das capacidades",
        "              da V1-13 (D-E1, segunda camada). GERADO por g1/build_g1_protected.py.",
        "Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com",
        "              autorização. Não depende da porta 5389 (camada 2).",
        "Blocos......: E1 (camada 1, sem trava): modo CLOSED.",
        "              E2 (camada 2): REVOKE EXECUTE de todas as RPCs novas, exceto o",
        "              convite (compartilhado com a V1-12; contingência: R5369 do",
        "              ROLLBACK_E1A, que devolve a 5303). Titular e VIEWER da V1-12",
        "              não usam nenhuma destas funções.",
        "              E3 (camada 2, Storage): DROP das 3 políticas novas da 5377.",
        "              ACCESS EXCLUSIVE em storage.objects (risco O2): LOCK NOWAIT; se",
        "              55P03, repetir em janela. NÃO revogar EXECUTE dos ajudantes:",
        "              a avaliação das políticas falharia para TODOS os usuários do",
        "              bucket (inclusive o titular).",
        "Limites.....: não cancela chamadas em curso (encerrar as sessões pelo painel ou",
        "              pg_cancel_backend, decisão do operador); não desfaz o que já foi",
        "              gravado; mudanças compartilhadas (5366, 5368, 5369, 5372/5379,",
        "              5381/5384) só saem pelos ROLLBACK_E1x.",
        "================================================================",
        "*/",
        "",
        "-- E1 -------------------------------------------------------------------------------------",
        "begin;",
        "set local lock_timeout = '5s';",
        "update public.v1_13_barrier_state set mode = 'CLOSED', changed_at = now(), change_note = 'EMERGENCY_STOP E1' where id = 1;",
        "commit;",
        "",
        "-- E2 -------------------------------------------------------------------------------------",
        "begin;",
        "set local lock_timeout = '5s';",
    ]
    lines += [f"revoke execute on function {s} from public, anon, authenticated;" for s in sigs]
    lines += [
        "commit;",
        "",
        "-- E3 -------------------------------------------------------------------------------------",
        "begin;",
        "set local lock_timeout = '2s';",
        "lock table storage.objects in access exclusive mode nowait;",
    ]
    lines += [f"drop policy if exists {p} on storage.objects;" for p in STORAGE_POLICIES]
    lines += ["commit;", ""]
    return "\n".join(lines)


def main() -> int:
    check = "--check" in sys.argv
    outputs, infos = {}, []
    for folder, fname, funcs in SOURCES:
        text, info = protect(folder, fname, funcs)
        outputs[os.path.join(OUT, fname)] = text.encode("utf-8")
        info["protected"] = f"g1/protected/{fname}"
        info["protected_sha256"] = sha256(text.encode("utf-8"))
        infos.append(info)
    outputs[os.path.join(HERE, "EMERGENCY_STOP_V1_13.sql")] = emergency(infos).encode("utf-8")
    manifest = {"generator": "g1/build_g1_protected.py", "capabilities": sum(len(i["functions"]) for i in infos),
                "files": infos}
    outputs[os.path.join(HERE, "G1_MANIFEST.json")] = (json.dumps(manifest, ensure_ascii=False, indent=1) + "\n").encode("utf-8")
    bad = []
    for path, data in outputs.items():
        if check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                bad.append(os.path.relpath(path, HERE))
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as fh:
                fh.write(data)
    if check:
        print("EM DIA" if not bad else "DIVERGENTE: " + ", ".join(bad))
        return 1 if bad else 0
    print(f"gerado: {len(outputs)} arquivos, {manifest['capabilities']} capacidades")
    return 0


if __name__ == "__main__":
    sys.exit(main())
