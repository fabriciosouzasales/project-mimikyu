#!/usr/bin/env python3
"""
V1-13 · E3-7b — verificação ESTÁTICA da 5397, reversão, exceção, emergência, PRE/POST, expectativas e
manifesto, com testes de MUTAÇÃO. Sem banco: prova só propriedades do TEXTO (STD-005). NÃO prova execução.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-7b-binder-opaque-identity/static_check_5397.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("build_5397", os.path.join(HERE, "build_5397.py"))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)
with tempfile.TemporaryDirectory() as td:
    real = B.HERE
    B.HERE = td
    GEN_MIG, GEN_RB = B.build()
    B.HERE = real

F = {n: os.path.join(HERE, n) for n in [
    "5397_binder_opaque_copy_identity.sql", "ROLLBACK_5397.sql", "RESTORE_5373_5374_EXCECAO_5397.sql",
    "EMERGENCY_STOP_V1_13_ADD_E37B.sql", "E37B_5397_PRE_readonly.sql", "E37B_5397_POST_readonly.sql",
    "E37B_5397_EXPECTATIVAS.json", "E37B_5397_MANIFEST.txt"]}
rd = lambda p: open(p, encoding="utf-8").read()
md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()


def nc(t):
    return re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", t, flags=re.S))


def nolit(t):
    return re.sub(r"'(?:[^']|'')*'", "''", nc(t))


def ro(s):  # espelho do Test-ReadOnlySql do executor v1.4
    s = re.sub(r"/\*[\s\S]*?\*/", " ", s)
    s = re.sub(r"--[^\r\n]*", " ", s)
    s = re.sub(r"'(?:[^']|'')*'", "''", s).strip()
    if not re.match(r"(?i)^select\b", s) or len(re.findall(";", s)) != 1 or not s.endswith(";") or "$" in s:
        return False
    return not re.search(r"(?i)\b(insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|lock|comment|copy|call|do|execute|vacuum|analyze|refresh|reindex|cluster|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend|dblink)\b", s)


def fn_def(t, name):
    m = re.search(r"create\s+(?:or\s+replace\s+)?function\s+public\." + re.escape(name) + r"\s*\(", t, re.I)
    if not m:
        return None
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", t[m.end():], re.I)
    s = m.end() + a.end()
    return t[m.start():t.index(a.group(1), s) + len(a.group(1))] + ";"


def strip_marked(t):
    return re.sub(re.escape(B.A) + r"\n.*?\n" + re.escape(B.Z) + r"\n?", "", t, flags=re.S)


def blocks(t):
    return re.findall(re.escape(B.A) + r"\n(.*?)\n" + re.escape(B.Z), t, flags=re.S)


def body(d):
    return B.prosrc(d) if d else ""


def run(mig, rb, rs, em, pre, post, exp, man, gen=True):
    R = []
    ck = lambda c, ok, d: R.append((c, bool(ok), d))
    if gen:
        ck("G0", mig == GEN_MIG and rb == GEN_RB, "migration e rollback = saída reproduzível de build_5397.py")
    ck("C1", all(md5(B.prosrc(B.CANON[k])) == h == B.G1MD5[k] for k, (_, _, h) in B.OLD.items()), "texto-fonte (G1 protegido) = md5 canônico do LIVE (G1_MANIFEST)")
    newname = {k: B.NEWNAME[k][0] for k in B.OLD}
    defs = {k: fn_def(mig, newname[k]) for k in B.OLD}
    ck("C2", all(defs[k] and B.unrep(k, strip_marked(defs[k])) == B.CANON[k] for k in B.OLD)
       and [len(B.REPL[k]) for k in B.OLD] == [4, 7, 2],
       "removidos os blocos [5397+]…[5397-] e desfeitas as substituições declaradas, cada função = texto canônico")
    ck("C3", all(defs[k] and md5(body(defs[k])) == B.NEWMD5[k] for k in B.OLD), "md5 dos corpos novos = constantes do POST e da reversão")

    pl = defs["get_shared_binder_placeable_cards"] or ""
    hdr = pl[:pl.find("language plpgsql")]
    ck("P1", "copy_token       text," in hdr and "physical_card_id" not in hdr
       and "public.v1_13_pokedex_copy_token(el.alloc_id, v_mid, v_epoch)" in pl
       and re.search(r"select\s+public\.v1_13_pokedex_copy_token\(el\.alloc_id, v_mid, v_epoch\),\s+-- \[5397~\]\s+c\.name::text", pl) is not None
       and "public.v1_13_editor_membership(p_collection_id)" in pl and "if v_mid is null then\n    return;" in pl
       and pl.find("if not public.v1_13_capability_open() then return; end if;") < pl.find("v1_13_editor_membership"),
       "leitura: devolve copy_token (alocação+participação+época vigentes), nunca o id do exemplar; barreira e EDITOR ACTIVE preservados")
    pc = defs["editor_place_card_in_binder"] or ""
    pcb = nc(body(pc))
    ck("P2", "p_copy_token     text" in pc and "p_physical_card_id" not in pc
       and "p_copy_token !~ '^pc1\\.[0-9a-f]{64}$'" in pc
       and "v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, null)" in pc
       and "ca.id = v_alloc and ca.collection_id = p_collection_id" in pc
       and pc.find("perform public.v1_13_assert_capability();") < pc.find("assert_collection_binder_editor(p_collection_id)") < pc.find("v1_13_editor_membership") < pc.find("-- 3. Exemplar elegível")
       and pcb.count("v_pc") >= 6 and "  if v_mid is null or v_pc is null then\n    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';" in blocks(pc)[1],
       "colocar/desfazer: só token; resolvido pela participação e época do chamador; mesma recusa; travas e autorização antes; nenhum id físico na entrada")
    pv = defs["editor_preview_binder_auto_arrange"] or ""
    ck("P3", "'physical_card_id'" not in pv and "'card_id', p.card_id" in pv and "'card_variant_id', p.card_variant_id" in pv and "'plan_token'" in pv,
       "prévia: sem physical_card_id; card_id/card_variant_id (catálogo público) e token do plano preservados")
    grl = [re.sub(r"\s+", " ", x.strip()) for x in re.findall(r"(?im)^\s*(?:grant|revoke)\b[^;]*;", nc(mig))]
    ck("G1", grl == [
        "revoke all on function public.get_shared_binder_placeable_copies(uuid, integer, integer) from public, anon, service_role;",
        "grant execute on function public.get_shared_binder_placeable_copies(uuid, integer, integer) to authenticated;",
        "revoke all on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) from public, anon, service_role;",
        "grant execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) to authenticated;",
        "revoke execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon, authenticated, service_role;",
        "revoke execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) from public, anon, authenticated, service_role;"],
       "privilégios: novas só para authenticated; antigas (com physical_card_id) revogadas de todo cliente; nada mais")
    objs = re.findall(r"(?i)\bcreate(?:\s+or\s+replace)?\s+function\s+public\.([a-z0-9_]+)", nc(mig))
    ck("G2", sorted(objs) == ["editor_place_copy_in_binder", "editor_preview_binder_auto_arrange", "get_shared_binder_placeable_copies"]
       and not re.search(r"(?i)\b(drop|alter|truncate|create\s+table|create\s+trigger)\b", nolit(mig)) and "nextval" not in mig,
       "objetos: 2 funções novas + prévia (OR REPLACE); nada removido; nenhuma estrutura nova (token reutilizado da 5391)")
    pre_blk = re.search(r"do \$pre\$(.*?)\$pre\$;", mig, re.S)
    post_blk = re.search(r"do \$post\$(.*?)\$post\$;", mig, re.S)
    pt, qt = (pre_blk.group(1) if pre_blk else ""), (post_blk.group(1) if post_blk else "")
    ck("T1", "\nbegin;\nset local lock_timeout = '3s';\n" in mig and mig.rstrip().endswith("commit;") and mig.count("commit;") == 1
       and all(h in pt for _, _, h in B.OLD.values()) and all(h in pt for _, _, h in B.DEPS.values()) and "'CLOSED'" in pt
       and all(h in qt for h in B.NEWMD5.values()) and "inventário" not in qt and "''physical_card_id''" in qt and "'CLOSED'" in qt,
       "transação única com lock_timeout 3 s; precheck (barreira, canônicos, ajudantes, ausência) e postcheck (texto, ACL, antigas revogadas, exposição vazia, barreira)")
    ck("T2", not re.search(r"(?i)=\s*any\s*\(\s*\(\s*select", nolit(mig + rb + pre + post)), "sem 'x = any ((select …))' (lição 22P02)")
    rbn = nc(rb)
    ck("RB1", "drop function public.get_shared_binder_placeable_copies(uuid, integer, integer);" in rbn
       and "drop function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text);" in rbn
       and B.CANON["editor_preview_binder_auto_arrange"].replace("create function public.", "create or replace function public.", 1) in rb
       and not re.search(r"(?i)\bgrant\b", rbn) and "a reversão não pode reabrir" in rb and all(h in rb for h in B.NEWMD5.values()),
       "reversão: remove as novas, restaura a prévia canônica, NÃO reabre as antigas (postcheck exige revogadas)")
    rsn = nc(rs)
    ck("RS1", re.findall(r"(?im)^grant [^;]+;", rsn) == [
        "grant execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) to authenticated;",
        "grant execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) to authenticated;"]
       and "is distinct from 'CLOSED'" in rs and "is not null" in rs,
       "exceção separada: só os 2 GRANTs originais, exige 5397 ausente e barreira CLOSED")
    emn = nc(em)
    ck("E1", sorted(re.findall(r"revoke execute on function public\.([a-z_]+)\(", emn)) == ["editor_place_copy_in_binder", "get_shared_binder_placeable_copies"]
       and not re.search(r"(?i)\bgrant\b", emn) and "from public, anon, authenticated;" in emn,
       "emergência E2d: revoga as 2 RPCs novas; nenhum GRANT")
    ck("K1", ro(pre) and ro(post), "PRE e POST passam no validador de somente leitura do executor")
    try:
        ex = json.loads(exp)
    except ValueError:
        ex = {}
    m = re.search(r"'inventario_bolso_pos',.*?\n\s*= '([^']+)'", post, re.S)
    ck("K2", sorted(ex) == ["escritores_bolso", "escritores_exposicao_fisica"]
       and ex["escritores_bolso"] == B.WRITERS_PRE and ex["escritores_exposicao_fisica"] == B.EXPO_PRE
       and m and m.group(1).split(", ") == B.WRITERS_POST == sorted(B.WRITERS_PRE + ["public.editor_place_copy_in_binder(uuid,integer,integer,integer,text)"], key=lambda s: s.encode())
       and "'escritores_bolso'" in pre and "'escritores_exposicao_fisica'" in pre and not re.search(r"'escritores_[a-z_]+'", post)
       and re.search(r"'inventario_exposicao_pos',\s+\(select coalesce\(string_agg[\s\S]*?\)\) = '',\n  'inventario_bolso_pos'", post) is not None,
       "expectativas (4 escritores, 3 exposições) e POST (escritores + a nova; exposição VAZIA) por assinatura completa")
    live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_|[A-Za-z]:\\\\Users", re.I)
    ck("X1", not any(live.search(nc(x)) for x in (mig, rb, rs, em, pre, post)), "sem projeto, URL, credencial ou caminho privado")
    rows = [l.split("|") for l in man.splitlines() if l and not l.startswith("#")]
    content = {"E37B_5397_PRE_readonly.sql": pre, "5397_binder_opaque_copy_identity.sql": mig, "E37B_5397_POST_readonly.sql": post}
    ok = [r[3] for r in rows] == ["gate", "write", "gate"]
    for r in rows:
        base = r[1].split("\\")[-1]
        ok = ok and base in content and hashlib.sha256(content[base].encode()).hexdigest() == r[2]
    ck("X2", ok and [r[1].split("\\")[-1] for r in rows] == list(content), "manifesto PRE → 5397 → POST com sha256 dos arquivos")
    return R


FILES = dict(mig=rd(F["5397_binder_opaque_copy_identity.sql"]), rb=rd(F["ROLLBACK_5397.sql"]), rs=rd(F["RESTORE_5373_5374_EXCECAO_5397.sql"]),
             em=rd(F["EMERGENCY_STOP_V1_13_ADD_E37B.sql"]), pre=rd(F["E37B_5397_PRE_readonly.sql"]), post=rd(F["E37B_5397_POST_readonly.sql"]),
             exp=rd(F["E37B_5397_EXPECTATIVAS.json"]), man=rd(F["E37B_5397_MANIFEST.txt"]))
R = run(**FILES)
disk = [open(p, "rb").read() for p in F.values()]
R.append(("X3", all(b"\r\n" not in d and not d.startswith(b"\xef\xbb\xbf") for d in disk), "UTF-8 sem BOM e LF"))

M = FILES["mig"]


def sub(t, a, b):
    assert a in t, a[:70]
    return t.replace(a, b, 1)


MUT = [
    ("leitura volta a devolver o id físico", "P1", dict(mig=sub(M, "    public.v1_13_pokedex_copy_token(el.alloc_id, v_mid, v_epoch),", "    el.pcid::text,"))),
    ("leitura sem participação vigente", "P1", dict(mig=sub(M, "  if v_mid is null then\n    return;\n  end if;", "  null;"))),
    ("colocar aceita id físico", "P2", dict(mig=sub(M, "v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, null)", "nullif(p_copy_token, '')::uuid"))),
    ("colocar sem validar formato do token", "P2", dict(mig=sub(M, " or p_copy_token !~ '^pc1\\.[0-9a-f]{64}$'", ""))),
    ("colocar resolve em qualquer coleção", "P2", dict(mig=sub(M, "ca.id = v_alloc and ca.collection_id = p_collection_id", "ca.id = v_alloc"))),
    ("colocar ignora token sem alocação", "P2", dict(mig=sub(M, "  if v_mid is null or v_pc is null then\n    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE'", "  if false then\n    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE'"))),
    ("prévia mantém o id físico", "P3", dict(mig=sub(M, "                                     'ord', p.ord,  -- [5397~]", "                                     'ord', p.ord, 'physical_card_id', p.physical_card_id,  -- [5397~]"))),
    ("antiga 5373 continua para authenticated", "G1", dict(mig=sub(M, "revoke execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon, authenticated, service_role;", "revoke execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon, service_role;"))),
    ("nova para anon", "G1", dict(mig=sub(M, "grant execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) to authenticated;", "grant execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) to authenticated, anon;"))),
    ("corpo canônico alterado fora dos marcadores", "C2", dict(mig=sub(M, "raise exception 'SLOT_LOCKED' using errcode = '55000';", "raise exception 'SLOT_LOCKED' using errcode = '55001';"))),
    ("barreira removida", "C2", dict(mig=sub(M, "  perform public.v1_13_assert_capability();  -- G1 (D-E1)\n", ""))),
    ("drop das antigas na migration", "G2", dict(mig=sub(M, "\ndo $post$", "\ndrop function public.get_shared_binder_placeable_cards(uuid, integer, integer);\n\ndo $post$"))),
    ("reversão reabre as antigas", "RB1", dict(rb=sub(FILES["rb"], "\ndo $post$", "\ngrant execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) to authenticated;\n\ndo $post$"))),
    ("exceção sem exigir barreira", "RS1", dict(rs=sub(FILES["rs"], "is distinct from 'CLOSED'", "is distinct from 'OPEN'"))),
    ("emergência com GRANT", "E1", dict(em=sub(FILES["em"], "commit;", "grant execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) to anon;\ncommit;"))),
    ("PRE com escrita", "K1", dict(pre=sub(FILES["pre"], ") as e37b_5397_pre;", ") as e37b_5397_pre; delete from public.collection_layout_slot_assignment;"))),
    ("POST aceita exposição", "K2", dict(post=sub(FILES["post"], "'inventario_exposicao_pos',    ", "'inventario_exposicao_pos',    'x' <> "))),
    ("expectativa divergente", "K2", dict(exp=json.dumps({"escritores_bolso": [], "escritores_exposicao_fisica": []}))),
    ("manifesto com hash errado", "X2", dict(man=re.sub(r"\|([0-9a-f]{64})\|write", "|" + "0" * 64 + "|write", FILES["man"]))),
]
res_m = []
for name, target, change in MUT:
    args = dict(FILES)
    args.update(change)
    got = {c: ok for c, ok, _ in run(**args, gen=False)}
    res_m.append((name, target, got.get(target) is False))
R.append(("MUT", all(x[2] for x in res_m), f"{sum(x[2] for x in res_m)}/{len(res_m)} mutações reprovadas pelo controle-alvo"))
fails = [r for r in R if not r[1]]
for c, ok, d in R:
    print(f"{'PASS' if ok else 'FAIL'}  {c:4} {d}")
for n, t, k in res_m:
    print(f"      {'morta' if k else 'VIVA '}  [{t}] {n}")
print(f"\nSTATIC CHECK 5397: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
