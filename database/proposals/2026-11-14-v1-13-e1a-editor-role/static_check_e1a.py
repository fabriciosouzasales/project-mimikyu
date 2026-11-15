#!/usr/bin/env python3
"""
V1-13 · E1-A — verificação ESTÁTICA da proposta 5366–5370 (+ 5888, ROLLBACK).

Não conecta em banco nenhum: só lê os arquivos desta pasta, os canônicos de
database/schema/ e o frontend em web/. Uso (na raiz do repositório ou em
qualquer lugar):

    python3 database/proposals/2026-11-14-v1-13-e1a-editor-role/static_check_e1a.py

Saída: uma linha PASS/FAIL por verificação e o GATE final. Código de saída 0
só com todas PASS.
"""
from __future__ import annotations

import difflib
import glob
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
WEB = os.path.join(ROOT, "web")

MIGRATIONS = [
    "5366_widen_collection_membership_role_editor.sql",
    "5367_create_collection_member_role_function.sql",
    "5368_expose_member_role_in_sharing_reads.sql",
    "5369_replace_invite_collection_member_with_role.sql",
    "5370_create_set_collection_member_role_function.sql",
]
HARNESS = "5888_validate_editor_role_foundation_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1A.sql"

CANON_MD5 = {  # md5(prosrc) dos canônicos V1-12 (derivados de database/schema/)
    "5302": "efdb495b5b703e9f093eb0f49a1d0a5d",
    "5303": "ed7418f20c1004b23c58c68c84a6ae73",
    "5308": "e36aa9c675f6b8097b6a43292b62603f",
    "5309": "74ea7dc1af9032e337b6c0e04ae7c478",
    "5311": "67b4395f013a2591fcb1e1585ba53a16",
    "5312": "254d56f3f9c8097ee3d36e580c851c29",
}

results: list[tuple[str, bool, str]] = []


def check(cid: str, ok: bool, detail: str) -> None:
    results.append((cid, bool(ok), detail))


def read(path: str) -> str:
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8")


def bodies(sql: str) -> list[str]:
    """Texto entre AS $$ e $$ (= pg_proc.prosrc), na ordem do arquivo."""
    out, i = [], 0
    while True:
        k = sql.find("AS $$", i)
        if k < 0:
            return out
        a = k + len("AS $$")
        b = sql.index("$$", a)
        out.append(sql[a:b])
        i = b + 2


def md5(text: str) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def canon(num: str) -> str:
    return read(glob.glob(os.path.join(SCHEMA, f"{num}_*.sql"))[0])


def canon_fn(num: str) -> str:
    s = canon(num)
    i = s.index("CREATE OR REPLACE FUNCTION")
    return s[i : s.index("$$;", i) + 3]


files = {name: read(os.path.join(HERE, name)) for name in MIGRATIONS + [HARNESS, ROLLBACK]}

# 1. Higiene de arquivo -----------------------------------------------------------------------
for name, s in files.items():
    raw = open(os.path.join(HERE, name), "rb").read()
    check(f"1.{name[:4]}", b"\r" not in raw and s.endswith("\n") and "@N" not in s,
          f"{name}: sem CRLF, termina em nova linha, sem marcador de md5 pendente")

# 2. Forma de migration (transação única, pre/post, lock_timeout) -------------------------------
for name in MIGRATIONS:
    s = files[name]
    check(f"2.{name[:4]}",
          s.count("\nbegin;\n") == 1 and s.rstrip().endswith("commit;")
          and "do $pre$" in s and "do $post$" in s and "set local lock_timeout = '5s';" in s
          and "PROPOSTA — NÃO EXECUTADA" in s,
          f"{name}: begin/commit único, precheck, postcheck, lock_timeout, status PROPOSTA")

# 3. Toda função criada: SECURITY DEFINER + search_path vazio + nomes qualificados --------------
create_re = re.compile(r"CREATE (?:OR REPLACE )?FUNCTION public\.(\w+)\((.*?)\)\s*RETURNS(.*?)AS \$\$", re.S)
unqualified = re.compile(r"(?<!DISTINCT )\b(?:FROM|JOIN)\s+(?!public\.|pg_catalog\.|LATERAL\b|jsonb_|unnest\b|\()([a-z_]+)", re.I)
fn_defs = []
for name in MIGRATIONS:
    for m in create_re.finditer(files[name]):
        fn_defs.append((name, m.group(1), m.group(3)))
check("3.1", len(fn_defs) == 6,
      f"6 definições de função nas migrations (encontradas {len(fn_defs)}: {[d[1] for d in fn_defs]})")
for name, fname, attrs in fn_defs:
    check(f"3.{fname}", "SECURITY DEFINER" in attrs and "SET search_path = ''" in attrs,
          f"{fname} ({name[:4]}): SECURITY DEFINER e SET search_path = ''")
leaks = []
for name in MIGRATIONS:
    for body in bodies(files[name]):
        for m in unqualified.finditer(body):
            if m.group(1).lower() not in ("x",):
                leaks.append((name[:4], m.group(1)))
check("3.2", not leaks, f"objetos qualificados em todos os corpos (não qualificados: {leaks})")

# 4. Privilégios ----------------------------------------------------------------------------------
s67 = files["5367_create_collection_member_role_function.sql"]
check("4.1", "REVOKE ALL ON FUNCTION public.collection_member_role(UUID) FROM PUBLIC, anon, authenticated;" in s67
      and "GRANT" not in s67.split("*/", 1)[1].upper().replace("GRANTS", ""),
      "5367: interna — REVOKE de PUBLIC, anon e authenticated; nenhum GRANT")
s69 = files["5369_replace_invite_collection_member_with_role.sql"]
check("4.2", "REVOKE ALL ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) FROM PUBLIC, anon;" in s69
      and "GRANT EXECUTE ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) TO authenticated;" in s69,
      "5369: só authenticated executa o convite novo")
s70 = files["5370_create_set_collection_member_role_function.sql"]
check("4.3", "REVOKE ALL ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) FROM PUBLIC, anon;" in s70
      and "GRANT EXECUTE ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) TO authenticated;" in s70,
      "5370: só authenticated executa a troca de papel")
s68 = files["5368_expose_member_role_in_sharing_reads.sql"]
check("4.4", all(f"GRANT EXECUTE ON FUNCTION {sig} TO authenticated;" in s68 and f"REVOKE ALL ON FUNCTION {sig} FROM PUBLIC, anon;" in s68
                 for sig in ("public.get_my_collection_invites()", "public.get_collections_shared_with_me()",
                             "public.get_shared_collection(uuid)")),
      "5368: ACL das três leituras reafirmada (authenticated; nunca anon)")
all_sql = "".join(files[n] for n in MIGRATIONS)
check("4.5", not re.search(r"GRANT\s+\w+.*\bTO\s+(anon|public)\b", all_sql, re.I)
      and not re.search(r"GRANT\s+.*ON\s+(TABLE\s+)?public\.collection_membership", all_sql, re.I),
      "nenhum GRANT para anon/PUBLIC e nenhum privilégio de tabela em collection_membership")

# 5. Assinatura antiga do convite ---------------------------------------------------------------
pos_drop = s69.find("DROP FUNCTION public.invite_collection_member(UUID, TEXT);")
pos_create = s69.find("CREATE FUNCTION public.invite_collection_member(")
check("5.1", 0 < pos_drop < pos_create and "CREATE OR REPLACE FUNCTION public.invite_collection_member" not in s69,
      "5369: DROP da (uuid, text) antes do CREATE da (uuid, text, text), na mesma transação")
check("5.2", "p_role TEXT DEFAULT 'VIEWER'" in s69 and "assinatura antiga ainda existe" in s69
      and "sobrecarga inesperada" in s69,
      "5369: padrão VIEWER; postcheck exige assinatura antiga ausente e sobrecarga única")
check("5.3", "ed7418f20c1004b23c58c68c84a6ae73" in s69, "5369: precheck exige o corpo canônico da 5303")

# 6. Regras de papel no convite e na troca -------------------------------------------------------
b69 = bodies(s69)[0]
check("6.1", "INVALID_ROLE" in b69 and b69.index("INVALID_ROLE") < b69.index("FROM public.collection c"),
      "convite: papel validado antes de ler a coleção")
check("6.2", "INVITE_PENDING_ROLE_IMMUTABLE" in b69 and "v_existing.role IS DISTINCT FROM v_role" in b69,
      "convite pendente com outro papel → INVITE_PENDING_ROLE_IMMUTABLE")
check("6.3", "ALREADY_MEMBER" in b69 and "SET role" not in b69,
      "convite nunca altera o papel de linha existente (sem UPDATE de role)")
check("6.4", "DELETE FROM public.collection_membership m" in b69 and "m.status = 'DECLINED'" in b69,
      "recusado + outro papel → apaga a linha recusada e cria convite novo (id novo)")
b70 = bodies(s70)[0]
check("6.5", "c.owner_user_id = v_user" in b70 and "FOR UPDATE" in b70 and "v_row.user_id = v_user" in b70,
      "troca: só titular (coleção do usuário da sessão), trava, defesa contra a própria participação")
check("6.6", "INVITE_PENDING_ROLE_IMMUTABLE" in b70 and "MEMBER_NOT_ACTIVE" in b70 and "'UNCHANGED'" in b70,
      "troca: pendente imutável, recusado não ativo, idempotente")
check("6.7", re.search(r"UPDATE public\.collection_membership m\s+SET role = v_role\s+WHERE", b70) is not None
      and "owner_user_id =" not in b70.split("UPDATE", 1)[1],
      "troca: só escreve collection_membership.role — nunca titularidade")
check("6.8", "NOT IN ('VIEWER', 'EDITOR')" in b70 and "NOT IN ('VIEWER', 'EDITOR')" in b69,
      "papéis aceitos: só VIEWER e EDITOR (OWNER/PUBLIC recusados)")

# 7. Leituras: diferença mínima em relação ao canônico ----------------------------------------
expected_add = {
    "5309": "               m.role               AS role,",
    "5311": "               m.role              AS role,",
    "5312": "        'role', public.collection_member_role(c.id),",
}
for num, line in expected_add.items():
    a = canon_fn(num)
    name = re.search(r"FUNCTION (public\.\w+)", a).group(1)
    i = s68.index(f"CREATE OR REPLACE FUNCTION {name}")
    b = s68[i : s68.index("$$;", i) + 3]
    diff = [l for l in difflib.unified_diff(a.splitlines(), b.splitlines(), lineterm="", n=0)
            if l[:1] in "+-" and l[:3] not in ("+++", "---")]
    check(f"7.{num}", diff == ["+" + line], f"{name}: única mudança = {line.strip()}")
b12 = s68[s68.index("CREATE OR REPLACE FUNCTION public.get_shared_collection"):]
check("7.access", "'access', v_role," in b12 and "CASE WHEN v_role = 'VIEWER'" in b12,
      "5312: access continua o nível de leitura; membership_id para todo participante")

# 8. md5 embutidos = corpos dos arquivos ---------------------------------------------------------
pairs = [("5367_create_collection_member_role_function.sql", 1), ("5368_expose_member_role_in_sharing_reads.sql", 3),
         ("5369_replace_invite_collection_member_with_role.sql", 1), ("5370_create_set_collection_member_role_function.sql", 1)]
for name, nbodies in pairs:
    s = files[name]
    hs = [md5(b) for b in bodies(s)]
    check(f"8.{name[:4]}", len(hs) == nbodies and all(s.count(h) >= 2 for h in hs),
          f"{name[:4]}: md5 dos corpos usado no precheck (JÁ APLICADA) e no postcheck")
for num in ("5303", "5309", "5311", "5312"):
    check(f"8.canon{num}", md5(bodies(canon(num))[0]) == CANON_MD5[num],
          f"{num}: md5 canônico conferido no arquivo de database/schema/")

# 9. Contratos intocados -------------------------------------------------------------------------
check("9.1", "FUNCTION public.collection_share_role" not in all_sql and "get_my_collection_sharing" not in re.sub(r"/\*.*?\*/", "", all_sql, flags=re.S),
      "5302 (collection_share_role) e 5308 (painel do titular) não são redefinidas")
readers = ["5312", "5313", "5314", "5316", "5320", "5321", "5326", "5328"]
gate_ok = all("'OWNER', 'VIEWER'" in canon(n) or "('OWNER', 'VIEWER')" in canon(n) for n in readers)
share_canon = canon("5302")
check("9.2", gate_ok and "THEN 'VIEWER'" in share_canon and "m.role" not in bodies(share_canon)[0],
      "leituras 5312–5328 aceitam 'VIEWER' da 5302, que não olha o papel → EDITOR ativo lê o mesmo recorte")
s5329 = canon("5329")
check("9.3", "m.status = 'ACTIVE'" in s5329 and "role" not in re.sub(r"/\*.*?\*/", "", s5329, flags=re.S),
      "Storage 5329: decide por participação ACTIVE, sem papel → imagens/capa iguais para EDITOR")
check("9.4", md5(bodies(share_canon)[0]) == CANON_MD5["5302"] and md5(bodies(canon("5308"))[0]) == CANON_MD5["5308"],
      "md5 de 5302/5308 canônicas = valor que o harness 0.5 exige")

# 10. Frontend publicado ---------------------------------------------------------------------------
actions = read(os.path.join(WEB, "app", "colecoes", "compartilhar", "actions.ts"))
inv_calls = re.findall(r'rpc\("invite_collection_member",\s*(\{[^}]*\})', actions)
check("10.1", len(inv_calls) == 1 and "p_role" not in inv_calls[0] and "p_collection_id" in inv_calls[0] and "p_username" in inv_calls[0],
      "frontend chama o convite por nome com 2 argumentos → resolve para a nova assinatura com padrão VIEWER")
sharing = read(os.path.join(WEB, "lib", "colecoes", "sharing.ts"))
check("10.2", "Object.keys" not in sharing and "access === \"VIEWER\"" in sharing,
      "analisadores leem por chave (ignoram 'role' novo); access VIEWER continua sendo o critério")
routes = [read(p) for p in glob.glob(os.path.join(WEB, "app", "colecoes", "compartilhada", "**", "page.tsx"), recursive=True)]
check("10.3", routes and all("\"EDITOR\"" not in r for r in routes) and any('access !== "VIEWER"' in r for r in routes),
      "rotas compartilhadas exigem access VIEWER — preservado para o EDITOR (access não muda)")
web_rpcs = set()
for p in glob.glob(os.path.join(WEB, "**", "*.ts*"), recursive=True):
    if "node_modules" in p:
        continue
    web_rpcs.update(re.findall(r'rpc\("(set_collection_member_role|collection_member_role)"', read(p)))
check("10.4", not web_rpcs, "nenhuma chamada do frontend às funções novas (interface fora da E1-A)")

# 11. Harness 5888 ----------------------------------------------------------------------------------
h = files[HARNESS]
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected integer := (\d+);", h).group(1))
check("11.1", len(ids) == exp and f"GATE esperado: {exp}/{exp} PASS" in h,
      f"harness: {len(ids)} verificações = esperado {exp}")
need = {
    "convite VIEWER/padrão": "1.1", "convite EDITOR": "1.2", "papel inválido": "1.3",
    "pendente + outro papel": "2.2", "troca VIEWER↔EDITOR": "4.2", "autopromoção": "5.1",
    "removido": "5.11", "saiu": "5.12", "leitura EDITOR = VIEWER": "3.2", "sem dados adicionais": "6.4",
    "sem escrita": "7.1",
}
missing = [k for k, v in need.items() if v not in ids]
check("11.2", not missing, f"cenários obrigatórios do pedido cobertos (faltando: {missing})")
check("11.3", "VALIDATION-STRATEGY-E1A.md" in h and "NÃO EXECUTADA" in h and "raise exception 'MS888'" in h and "'99.1'" in h
      and not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "PostgreSQL ISOLADO" not in h,
      "harness: só sob o protocolo controlado (C-244 revisada), não executado, sem BEGIN/COMMIT próprios, com sentinela e resíduo zero")

# 12. Reversão ------------------------------------------------------------------------------------
rb = files[ROLLBACK]
hs = [md5(b) for b in bodies(rb)]
check("12.1", hs == [CANON_MD5["5303"], CANON_MD5["5309"], CANON_MD5["5311"], CANON_MD5["5312"]],
      "ROLLBACK restaura 5303/5309/5311/5312 byte a byte (md5 canônico)")
order = [rb.find(f"-- R{n}") for n in ("5370", "5369", "5368", "5367", "5366")]
check("12.2", all(o >= 0 for o in order) and order == sorted(order) and rb.count("m.role <> 'VIEWER'") == 2,
      "ROLLBACK na ordem inversa e bloqueado enquanto houver EDITOR")

# 13. Preservação de EXECUTE (v1.1 das migrations) -------------------------------------------
acl_expr = "string_agg(a::text, ',' order by a::text)"
check("13.1", acl_expr in s69 and "set_config('mmkyu.e1a_5369_acl'" in s69
      and "ACL da nova assinatura difere da antiga" in s69 and "ACL nula na assinatura antiga" in s69,
      "5369: ACL completa da assinatura antiga guardada e exigida na nova (inclui service_role/privilégio padrão)")
check("13.2", "set_config('mmkyu.e1a_5368_acl'" in s68 and "ACL das leituras mudou" in s68,
      "5368: ACL das três leituras idêntica antes e depois")
check("13.3", "to_regprocedure('public.collection_share_role(uuid)')" in s67 and "ACL difere da collection_share_role" in s67,
      "5367: ACL idêntica à da 5302 (mesma classe: interna)")
check("13.4", "to_regprocedure('public.remove_collection_member(uuid, uuid)')" in s70 and "ACL difere da remove_collection_member" in s70,
      "5370: ACL idêntica à da 5305 (gestão de participação pelo titular)")

# 14. 5861 v1.4 (compatibilidade da cobertura V1-12) -----------------------------------------------
orig = read(os.path.join(ROOT, "database", "proposals", "2026-10-30-v1-12-collection-sharing",
                         "5861_validate_collection_sharing.sql"))
v14 = read(os.path.join(HERE, "5861_validate_collection_sharing_v1.4.sql"))
body_o = orig.split("*/", 1)[1]
body_n = v14.split("*/", 1)[1]
d = [l for l in difflib.unified_diff(body_o.splitlines(), body_n.splitlines(), lineterm="", n=0)
     if l[:1] in "+-" and l[:3] not in ("+++", "---")]
expected_d = [
    "-  f_inv  oid := to_regprocedure('public.invite_collection_member(uuid, text)');",
    "-    'access','membership_id','copies_count','total_positions','satisfied_positions','progress_percentage','is_complete'];",
    "+  f_inv  oid := coalesce(to_regprocedure('public.invite_collection_member(uuid, text, text)'),",
    "+                        to_regprocedure('public.invite_collection_member(uuid, text)'));",
    "+    'access','membership_id','copies_count','total_positions','satisfied_positions','progress_percentage','is_complete',",
    "+    'role'];  -- v1.4: chave da 5368 (papel do próprio participante)",
]
check("14.1", sorted(d) == sorted(expected_d),
      "5861 v1.4: fora do cabeçalho, só f_inv (assinatura nova ou antiga) e 'role' nas chaves permitidas")
check("14.2", "v_expected integer := 51;" in v14 and v14.count("jsonb_build_object('id','") == orig.count("jsonb_build_object('id','"),
      "5861 v1.4: mesmas 51 verificações e mesmas asserções da v1.3")
check("14.3", b"\r" not in open(os.path.join(HERE, "5861_validate_collection_sharing_v1.4.sql"), "rb").read(),
      "5861 v1.4: sem CRLF")

# Relatório -----------------------------------------------------------------------------------------
passes = sum(1 for _, ok, _ in results if ok)
for cid, ok, detail in results:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<14} {detail}")
print(f"GATE  {'PASS' if passes == len(results) else 'FAIL'}  {passes}/{len(results)}")
sys.exit(0 if passes == len(results) else 1)
