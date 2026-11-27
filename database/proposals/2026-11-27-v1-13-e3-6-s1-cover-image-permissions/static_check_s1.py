#!/usr/bin/env python3
"""
V1-13 · E3-6 / S1 — verificação ESTÁTICA da 5390, ROLLBACK_S1 e checks somente leitura.

Sem banco. Prova só propriedades do TEXTO: forma da migration; md5 do precheck/postcheck
iguais aos corpos implantados (5376/5377 protegidas) e canônicos (5178, 5172, 5180, 5035);
ordem DROP POLICY → DROP FUNCTION → REVOKE; nenhum DROP/REVOKE/ALTER sobre objeto do titular,
da E3-3, da 5329 ou da barreira; nenhuma escrita em tabela nem em storage.objects; trava NOWAIT;
I1 mantida (compatível com EMERGENCY_STOP_V1_13.sql); rollback com o texto exato da 5377;
checks somente leitura sem nomes de arquivos nem de usuários. NÃO prova execução.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s1-cover-image-permissions/static_check_s1.py
"""
from __future__ import annotations

import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
PROT = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1", "protected")
EMER = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1", "EMERGENCY_STOP_V1_13.sql")
MIG = os.path.join(HERE, "5390_revoke_editor_cover_image_capabilities.sql")
RB = os.path.join(HERE, "ROLLBACK_S1.sql")
CHK = os.path.join(HERE, "S1_DEPLOY_readonly_checks.sql")
R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def prosrc(text, fname):
    i = text.lower().index("function public." + fname + "(")
    m = re.search(r"\bas\s+(\$[A-Za-z0-9_]*\$)", text[i:], re.I)
    a = i + m.end()
    return text[a:text.index(m.group(1), a)]


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


mig, rb, chk, emer = rd(MIG), rd(RB), rd(CHK), rd(EMER)
p5376, p5377 = rd(os.path.join(PROT, "5376_create_editor_collection_metadata_writes.sql")), rd(os.path.join(PROT, "5377_create_editor_collection_cover_storage_policies.sql"))
code = nc(mig)

expected = {
    "editor_set_collection_cover_logo": md5(prosrc(p5376, "editor_set_collection_cover_logo")),
    "collection_cover_editor_folder_ok": md5(prosrc(p5377, "collection_cover_editor_folder_ok")),
    "collection_cover_editor_can_upload": md5(prosrc(p5377, "collection_cover_editor_can_upload")),
    "editor_update_collection_metadata": md5(prosrc(p5376, "editor_update_collection_metadata")),
    "editor_set_collection_cover_finish": md5(prosrc(p5376, "editor_set_collection_cover_finish")),
    "editor_set_collection_cover_code": md5(prosrc(p5376, "editor_set_collection_cover_code")),
    "assert_collection_editor": md5(prosrc(p5376, "assert_collection_editor")),
}
# Constantes do titular: as mesmas que a 5376 implantada conferiu no precheck dela (5035/5172/5178/5180).
owner_consts = dict(re.findall(r"to_regprocedure\('public\.(update_collection_metadata|set_my_collection_cover_finish|set_my_collection_cover_code|set_my_collection_cover_logo)\([^)]*\)'\)\) is distinct from '([0-9a-f]{32})'", p5376))
expected.update(owner_consts)
check("C0", len(owner_consts) == 4, "constantes do titular lidas do precheck da 5376 implantada: " + ", ".join(f"{k}={v[:8]}" for k, v in owner_consts.items()))
s5178 = os.path.join(SCHEMA, "5178_create_set_my_collection_cover_logo_function.sql")
check("C0b", md5(prosrc(rd(s5178), "set_my_collection_cover_logo")) == owner_consts.get("set_my_collection_cover_logo"), "md5 da 5178 canônica (database/schema) = constante usada")

bad = []
for txt, name in ((mig, "5390"), (chk, "checks"), (rb, "rollback")):
    for fn, h in re.findall(r"to_regprocedure\('public\.([a-z_]+)\([^)]*\)'\)\)\s*(?:is distinct from|=)\s*'([0-9a-f]{32})'", txt):
        if fn in expected and expected[fn] != h:
            bad.append(f"{name}:{fn}")
    for h in re.findall(r"md5\(p\.prosrc\) = '([0-9a-f]{32})'", txt):
        if h not in expected.values():
            bad.append(f"{name}:{h[:8]}")
check("C1", not bad, "todas as constantes md5 = corpos implantados/canônicos" + (f" — divergentes: {bad}" if bad else ""))

check("M1", code.strip().lower().startswith("begin;") and code.strip().lower().endswith("commit;") and code.lower().count("begin;") == 1, "uma transação")
check("M2", "set local lock_timeout = '3s';" in code and "lock table storage.objects in access exclusive mode nowait;" in code
      and code.index("lock table storage.objects") < code.index("drop policy"), "trava curta e NOWAIT antes do primeiro DROP POLICY")
i_pol = [code.index(f"drop policy collection_cover_{k}_editor on storage.objects;") for k in ("insert", "select", "delete")]
i_fun = [code.index("drop function public.collection_cover_editor_can_upload(text);"), code.index("drop function public.collection_cover_editor_folder_ok(text);")]
i_rev = code.index("revoke all on function public.editor_set_collection_cover_logo(uuid, text) from public, anon, authenticated, service_role;")
check("M3", max(i_pol) < min(i_fun) < max(i_fun) < i_rev, "ordem: 3 DROP POLICY → verificação de dependentes → 2 DROP FUNCTION → REVOKE da I1")
drops = re.findall(r"\bdrop\s+(policy|function|table|trigger|view|index)\s+([^\s;(]+)", code, re.I)
check("M4", sorted(d[1] for d in drops) == sorted(["collection_cover_insert_editor", "collection_cover_select_editor", "collection_cover_delete_editor",
                                                     "public.collection_cover_editor_can_upload", "public.collection_cover_editor_folder_ok"]),
      "só os 5 objetos de I2–I4 são removidos")
check("M5", "drop function public.editor_set_collection_cover_logo" not in code and re.search(r"\bdrop\s+\w+\s+if\s+exists", code, re.I) is None, "I1 mantida (sem DROP); DROP sem IF EXISTS (ausência = estado divergente)")
check("M6", re.search(r"\b(insert|update|delete)\s+(into\s+|from\s+)?(public|storage)\.", code, re.I) is None and "truncate" not in code.lower(),
      "nenhuma escrita em tabela nem em storage.objects")
forbidden = r"(set_my_collection_cover_|update_collection_metadata|editor_update_collection_metadata|editor_set_collection_cover_finish|editor_set_collection_cover_code|assert_collection_editor|collection_cover_(select|insert|update|delete)_own|collection_cover_select_shared|v1_13_barrier|v1_13_capability)"
ddl = [l for l in code.splitlines() if re.match(r"\s*(drop|revoke|grant|alter|create|comment)\b", l, re.I)]
check("M7", not any(re.search(forbidden, l) for l in ddl), "nenhum DDL sobre titular, E3-3, 5329 ou barreira")
check("M8", "provolatile" not in code and "mmkyu.s1_5390_keep" in code and "mmkyu.s1_5390_e33_acl" in code, "retrato das políticas e ACLs que ficam comparado no postcheck da mesma transação")
check("M9", all(x in code for x in ("'anon', 'authenticated', 'service_role', 'authenticator'", "has_function_privilege(r.oid, v_i1, 'EXECUTE')", "a.grantee <> v_owner")),
      "postcheck: ACL da I1 só com o dono; papéis de cliente sem EXECUTE efetivo (herança incluída)")
check("M10", "privilégio inesperado na I1" in code and "not in ('authenticated', 'service_role')" in code, "precheck: qualquer EXECUTE inesperado na I1 → STOP")
check("E1", "revoke execute on function public.editor_set_collection_cover_logo(uuid, text)" in emer, "EMERGENCY_STOP revoga a I1 sem guarda — por isso ela fica (compatibilidade)")

a = p5377.index("create function public.collection_cover_editor_folder_ok(p_name text)")
b = p5377.index("do $post$")
check("R1", p5377[a:b].rstrip() in rb, "rollback: ajudantes e políticas com o texto exato da 5377 implantada")
check("R2", "grant execute on function public.editor_set_collection_cover_logo(uuid, text) to authenticated;" in rb and "REINTRODUZ" in rb, "rollback devolve EXECUTE da I1 e avisa que reintroduz as capacidades")
check("R3", re.search(r"\b(insert|update|delete)\s+(into\s+|from\s+)?storage\.objects", nc(rb), re.I) is None, "rollback não toca arquivos")

blocks = [x for x in re.split(r"-- (?:PRE|POST) -+", chk) if x.strip().lower().startswith("select")]
# Literais ('UPDATE', 'DELETE' em has_table_privilege; chaves do jsonb) não são instruções: removidos antes da varredura.
nolit = lambda t: re.sub(r"'[^']*'", "''", nc(t))
check("K1", len(blocks) == 2 and all(re.search(r"\b(insert|update|delete|drop|alter|create|grant|revoke|lock|set_config)\b", nolit(x), re.I) is None for x in blocks)
      and all(nolit(x).count(";") == 1 for x in blocks),
      "checks: dois SELECTs somente leitura (uma instrução cada; palavras-chave fora de literais)")
names = re.sub(r"storage\.foldername\(o\.name\)|o\.name = c\.cover_logo_path", "", nc(chk))
check("K2", "o.name" not in names and re.search(r"email|username|rolname, ', ' order by r\.rolname\), ''\)\s*from pg_catalog\.pg_roles r\s*where r\.rolcanlogin and r\.rolsuper", names) is None,
      "checks sem nomes de arquivos ou de usuários (só contagens; nomes de PAPÉIS do banco aparecem nos itens de privilégio)")
check("K3", all(k in chk for k in ("arquivos_dono_comprovado", "arquivos_terceiros", "arquivos_sem_titularidade", "capas_atuais_de_terceiros", "acl_i1_inesperado", "herdeiros_dono_i1", "login_sem_execute")),
      "PRE classifica arquivos e privilégios; POST mostra herança e logins")
# PRECHECK CORRECTION-01 — critério de pertencimento ao dono de storage.objects substituído.
pre = blocks[0] if blocks else ""
check("K4", "pode_alterar_objects" not in nc(chk) and "'MEMBER'" not in nc(pre).split("'privilegios_observaveis'")[0]
      and "'pode_travar_objects'" in pre and all(f"'storage.objects', '{p}')" in pre for p in ("UPDATE", "DELETE", "TRUNCATE", "MAINTAIN")),
      "PRE: sem critério de pertencimento ao dono; trava conferida por UPDATE/DELETE/TRUNCATE/MAINTAIN (regra do LOCK no PG 17)")
check("K5", "'precedente_5377_mesmo_papel'" in pre and "collection_cover_editor_folder_ok(text)" in pre.split("'precedente_5377_mesmo_papel'")[1]
      and "p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)" in pre
      and "NÃO prova" in chk and "'privilegios_observaveis'" in pre and "'membro_dono_objects'" in pre,
      "PRE: precedente da 5377 (ajudantes da mesma transação pertencem ao executor) como evidência, não garantia; privilégios observáveis em relatório")
sha = lambda t: hashlib.sha256(t.encode("utf-8")).hexdigest()
check("K6", sha(mig) == "6202bb9876ab60c6753b19e61040f6d49b51ae645170a6f8cf3dba3899ec5212"
      and sha(rb) == "01c719fd43cb0d23cddb68752bc6f05369e3440e9f3ca8a87db1121c697ec6b3" and "pg_has_role" not in nc(mig),
      "5390 e ROLLBACK_S1 inalterados (sha256 da preparação); a 5390 não exige pertencimento ao dono")
live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_", re.I)
check("H1", not any(live.search(nc(x)) for x in (mig, rb, chk)), "nenhuma referência ao projeto, URL ou credencial")

fails = [r for r in R if not r[1]]
for cid, ok, detail in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:4} {detail}")
print(f"\nSTATIC CHECK S1: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
