#!/usr/bin/env python3
"""
V1-13 · E3-6 / S2 — verificação ESTÁTICA da 5391, ROLLBACK_5391 e checks somente leitura.

Sem banco. Prova só propriedades do TEXTO (STD-005 §2): forma da transação; md5 das
funções preservadas = corpos canônicos; nenhuma mudança em objetos existentes além do
gatilho; definer + search_path vazio; privilégios; colunas proibidas ausentes do retorno;
barreira primeiro; limites; escopo ASSIGNABLE restrito à coleção; época/segredo; rollback
simétrico; checks somente leitura. NÃO prova execução nem comportamento.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s2-pokedex-collaborative-editing/static_check_5391.py
"""
from __future__ import annotations

import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
G1 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1")
E1A = os.path.join(ROOT, "database", "proposals", "2026-11-14-v1-13-e1a-editor-role")
SCHEMA = os.path.join(ROOT, "database", "schema")
MIG = os.path.join(HERE, "5391_create_editor_pokedex_copy_identity_and_read.sql")
RB = os.path.join(HERE, "ROLLBACK_5391.sql")
PRE = os.path.join(HERE, "S2_5391_PRE_readonly.sql")
POST = os.path.join(HERE, "S2_5391_POST_readonly.sql")
R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def nolit(t):
    return re.sub(r"'[^']*'", "''", nc(t))


def prosrc(text, name):
    t = text[text.lower().index("\nbegin;") + 1:] if "\nbegin;" in text.lower() else text
    m = re.search(r"create\s+(or\s+replace\s+)?function\s+public\." + re.escape(name) + r"\s*\(", t, re.I)
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", t[m.end():], re.I)
    s = m.end() + a.end()
    return t[s:t.index(a.group(1), s)]


md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()
mig, rb = rd(MIG), rd(RB)
pre_t, post_t = rd(PRE), rd(POST)
chk = pre_t + "\n" + post_t
code = nc(mig)
body = mig[mig.index("\nbegin;\n") + 1:]

# Cabeçalho: um único comentário de bloco, sem "*/" interno (lição da 5388).
head = mig[:mig.index("\nbegin;\n")].strip()
check("H0", head.startswith("/*") and head.endswith("*/") and head.count("*/") == 1 and head.count("/*") == 1,
      "cabeçalho = um único comentário de bloco (sem `*/` interno — lição 5388)")

# Estrutura léxica (substituto parcial do parser, indisponível no sandbox): aspas e parênteses
# balanceados em cada arquivo, por instrução, fora de comentários e literais; $fn$ pareados.
def balanced(t):
    t = re.sub(r"'(?:[^']|'')*'", "''", nc(t))
    if t.count("'") % 2:
        return False
    depth = 0
    for ch in t:
        depth += (ch == "(") - (ch == ")")
        if depth < 0:
            return False
    return depth == 0


check("S0", all(balanced(x) for x in (mig, rb, pre_t, post_t)) and nc(mig).count("$fn$") % 2 == 0
      and nc(mig).count("$pre$") == 2 and nc(mig).count("$post$") == 2,
      "aspas, parênteses e delimitadores $…$ balanceados (NÃO substitui compilação)")

# Constantes md5 = corpos canônicos implantados.
canon = {
    "invite_collection_member": prosrc(rd(os.path.join(G1, "protected", "5369_replace_invite_collection_member_with_role.sql")), "invite_collection_member"),
    "set_collection_member_role": prosrc(rd(os.path.join(G1, "protected", "5370_create_set_collection_member_role_function.sql")), "set_collection_member_role"),
    "respond_collection_invite": prosrc(rd(os.path.join(SCHEMA, "5304_create_respond_collection_invite_function.sql")), "respond_collection_invite"),
    "remove_collection_member": prosrc(rd(os.path.join(SCHEMA, "5305_create_remove_collection_member_function.sql")), "remove_collection_member"),
    "leave_shared_collection": prosrc(rd(os.path.join(SCHEMA, "5306_create_leave_shared_collection_function.sql")), "leave_shared_collection"),
    "collection_member_role": prosrc(rd(os.path.join(E1A, "5367_create_collection_member_role_function.sql")), "collection_member_role"),
    "v1_13_assert_capability": prosrc(rd(os.path.join(G1, "5389_create_v1_13_capability_barrier.sql")), "v1_13_assert_capability"),
    "v1_13_capability_open": prosrc(rd(os.path.join(G1, "5389_create_v1_13_capability_barrier.sql")), "v1_13_capability_open"),
}
sig = {"invite_collection_member": "(uuid, text, text)", "set_collection_member_role": "(uuid, uuid, text)",
       "respond_collection_invite": "(uuid, boolean)", "remove_collection_member": "(uuid, uuid)",
       "leave_shared_collection": "(uuid)", "collection_member_role": "(uuid)",
       "v1_13_assert_capability": "()", "v1_13_capability_open": "()"}
check("C0", md5(canon["collection_member_role"]) == "1e90ce8a9f4d88c067e9125bf602eff8"
      and md5(canon["v1_13_assert_capability"]) == "e4f710904f50e6e8c3f1d8e2337639e0",
      "extrator de prosrc reproduz md5 já fixados (5367, 5389)")
bad = []
for fn, src in canon.items():
    pat = re.escape(f"to_regprocedure('public.{fn}{sig[fn]}')")
    found = re.findall(pat + r"\)\s*is distinct from\s*'([0-9a-f]{32})'", code) + re.findall(pat + r"\)\s*=\s*'([0-9a-f]{32})'", nc(chk))
    if not found or any(h != md5(src) for h in found):
        bad.append(fn)
check("C1", not bad, f"constantes md5 = corpos canônicos (migration e checks){' — divergem: ' + ', '.join(bad) if bad else ''}")
check("C2", all(sum(1 for _ in re.finditer(re.escape(f"public.{fn}{sig[fn]}"), code)) >= 2 for fn in canon if fn.startswith(("invite", "set_coll", "respond", "remove", "leave", "collection_member"))),
      "funções de participação conferidas no precheck E no postcheck")

# Forma.
check("M1", body.count("begin;") == 1 and body.rstrip().endswith("commit;") and "set local lock_timeout = '3s';" in body,
      "uma transação, lock_timeout 3 s")
i_lock = code.find("lock table public.collection_membership in share row exclusive mode nowait;")
check("M2", 0 < i_lock < code.find("create trigger") and i_lock < code.find("insert into public.collection_membership_epoch (membership_id, role_epoch)\nselect"),
      "trava NOWAIT de collection_membership antes do gatilho e do backfill")
ddl = [l.strip() for l in code.splitlines() if re.match(r"\s*(create|alter|drop|grant|revoke|comment|lock)\b", l, re.I)]
created = sorted(set(re.findall(r"create (?:function|table|sequence|trigger) (?:public\.)?([a-z0-9_]+)", code)))
check("M3", created == sorted(["collection_membership_epoch", "collection_membership_epoch_seq", "collection_membership_epoch_touch",
                               "get_editor_pokedex_position_copies", "trg_collection_membership_epoch", "v1_13_copy_token_secret",
                               "v1_13_editor_membership", "v1_13_pokedex_copy_token"])
      and "or replace" not in code.lower() and not re.search(r"\bdrop\b", code, re.I)
      and not any(re.match(r"alter table public\.(?!collection_membership_epoch|v1_13_copy_token_secret)", l) for l in ddl),
      "só os 8 objetos novos; nenhum CREATE OR REPLACE, DROP ou ALTER de objeto existente")
funcs = re.findall(r"create function public\.([a-z0-9_]+)\((?:.|\n)*?\nas \$fn\$", code)
blocks = re.findall(r"create function public\.[a-z0-9_]+\((?:.|\n)*?\nas \$fn\$", code)
check("M4", len(funcs) == 4 and all("security definer" in b and "set search_path = ''" in b for b in blocks),
      "4 funções, todas SECURITY DEFINER com search_path vazio")
rev = {
    "sequence public.collection_membership_epoch_seq": "public, anon, authenticated, service_role",
    "table public.collection_membership_epoch": "public, anon, authenticated, service_role",
    "table public.v1_13_copy_token_secret": "public, anon, authenticated, service_role",
    "function public.collection_membership_epoch_touch()": "public, anon, authenticated, service_role",
    "function public.v1_13_editor_membership(uuid)": "public, anon, authenticated, service_role",
    "function public.v1_13_pokedex_copy_token(uuid, uuid, bigint)": "public, anon, authenticated, service_role",
    "function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)": "public, anon, service_role",
}
grants = re.findall(r"grant [^;]+;", code)
check("M5", all(f"revoke all on {k} from {v};" in code for k, v in rev.items())
      and grants == ["grant execute on function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer) to authenticated;"],
      "interno sem privilégio para a API; RPC: único GRANT, só authenticated")
_r0 = code.index("create function public.get_editor_pokedex_position_copies")
rpc = code[_r0:code.index("\n$fn$;", _r0)]  # só o corpo da RPC
ret = rpc[rpc.index("returns table ("):rpc.index(")\nlanguage plpgsql")]
forbidden = r"physical_card_id|allocation|membership|storage_name|condition|grade|certif|price|value|cost|acquir|purchase|note|assigned_by|assigned_at|owner|inventory|epoch|secret"
check("M6", re.search(forbidden, ret, re.I) is None and ret.count("\n  ") == 15,
      "retorno: 15 colunas, nenhuma patrimonial, de identidade física, participação, época ou segredo")
first = rpc[rpc.index("\nbegin\n") + 7:].lstrip()
check("M7", first.startswith("perform public.v1_13_assert_capability();"), "RPC: barreira é a primeira instrução")
check("M8", "p_limit < 1 or p_limit > 100" in rpc and "p_offset > 10000" in rpc and "char_length(v_q) > 64" in rpc
      and "'^[0-9]{1,4}$'" in rpc and "escape '\\'" in rpc and "replace(replace(replace(v_q, '\\', '\\\\'), '%', '\\%'), '_', '\\_')" in rpc,
      "limites (1–100, offset ≤ 10 000, filtro ≤ 64), filtro numérico = número nacional, LIKE escapado")
auth_i = rpc.index("from public.v1_13_editor_membership(p_collection_id) em;")
check("M9", auth_i < rpc.index("from public.collection_allocation ca")
      and rpc.count("where ca.collection_id = p_collection_id") == 2
      and re.search(r"\b(inventory|storage_container|acervo|physical_card_condition|price)\b", nc(rpc).replace("storage_path", "")) is None
      and "v1_13_copy_token_secret" not in rpc,
      "autorização antes de ler exemplares; os dois modos limitados às alocações de X; sem acervo/local/preço; segredo só via ajudante")
touch = code[code.index("create function public.collection_membership_epoch_touch()"):code.index("create trigger")]
check("M10", "after insert or update of role, status on public.collection_membership" in code
      and "nextval('public.collection_membership_epoch_seq'::regclass)" in touch
      and "if tg_op = 'UPDATE' then" in touch and "no cycle" in code
      and "unique (role_epoch)" in code and "on delete cascade" in code,
      "época: gatilho em INSERT e UPDATE de role/status, sequência sem ciclo, valor único, some com a participação")
tok = code[code.index("create function public.v1_13_pokedex_copy_token"):code.index("create function public.get_editor_pokedex_position_copies")]
check("M11", "'pc1.' || encode(extensions.hmac(" in tok and "'sha256'" in tok
      and "p_allocation_id::text || '|' || p_membership_id::text || '|' || p_role_epoch::text" in tok
      and "extensions.gen_random_bytes(32)" in code and "octet_length(secret) = 32" in code,
      "identificador = pc1 + HMAC-SHA256(alocação|participação|época) com segredo de 32 bytes")
emb = code[code.index("create function public.v1_13_editor_membership"):code.index("create function public.v1_13_pokedex_copy_token")]
check("M12", all(x in emb for x in ("m.status = 'ACTIVE'", "m.role = 'EDITOR'", "c.owner_user_id <> (select auth.uid())",
                                     "c.lifecycle_status = 'ACTIVE'", "join public.collection_membership_epoch e")),
      "leitura só para EDITOR ACTIVE, não titular, coleção ACTIVE, com época (fail closed)")
post = code[code.index("do $post$"):]
check("M13", all(x in post for x in ("has_function_privilege('service_role', v_read", "relrowsecurity", "has_sequence_privilege",
                                      "participação sem época", "funções de participação alteradas", "barreira não está CLOSED")),
      "postcheck: privilégios, RLS, sequência, épocas completas, participação intacta, barreira")

# Rollback.
rbc = nc(rb)
drops = re.findall(r"drop (function|trigger|table|sequence) (public\.)?([a-z0-9_]+)", rbc)
check("R1", sorted(d[2] for d in drops) == sorted(created) and "5392 presente" in rbc and "nowait" in rbc
      and re.search(r"\b(insert|update|delete)\b", nolit(rbc), re.I) is None,
      "rollback remove exatamente os 8 objetos; recusa com a 5392 presente; sem DML")

# Checks somente leitura.
cb = [nc(pre_t).strip(), nc(post_t).strip()]
check("K1", all(x.lower().startswith("select") for x in cb) and all(re.search(r"\b(insert|update|delete|drop|alter|create|grant|revoke|lock|set_config|nextval)\b", nolit(x), re.I) is None
                                 and nolit(x).count(";") == 1 for x in cb),
      "PRE e POST: um SELECT somente leitura cada, em arquivos separados (executor por arquivo)")
check("K2", re.search(r"\bs\.secret\b(?!\)\s*=\s*32)", nc(chk)) is None and "role_epoch)" in chk and "e.role_epoch" in chk
      and re.search(r"select\s+e\.role_epoch\b", nc(chk), re.I) is None,
      "checks nunca devolvem o segredo nem valores de época (só contagens)")
# Lição do PRE no LIVE (2026-11-27): em expressão regular do PostgreSQL "\\b" é backspace, não limite de
# palavra (é "\\y"); o relatório escritores_* saiu vazio. Nenhum "\\b" em literal SQL.
check("V15", not any(re.search(r"'[^']*\\b[^']*'", nc(x)) for x in (mig, rb, pre_t, post_t))
      and "\\y'" in nc(pre_t),
      "regex SQL sem \\b (backspace no PostgreSQL); limite de palavra com \\y no PRE")
live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_", re.I)
check("X1", not any(live.search(nc(x)) for x in (mig, rb, chk)), "nenhuma referência ao projeto, URL ou credencial")

# Manifesto do executor por arquivo (STD-005 §3): hashes = arquivos; ordem PRE → migration → POST.
man = [l.split("|") for l in rd(os.path.join(HERE, "S2_5391_MANIFEST.txt")).splitlines() if l and not l.startswith("#")]
okm = [m[0] for m in man] == ["1", "2", "3"] and [m[3] for m in man] == ["gate", "write", "gate"]
for m in man:
    p = os.path.join(ROOT, *m[1].split("\\"))
    okm = okm and os.path.isfile(p) and hashlib.sha256(open(p, "rb").read()).hexdigest() == m[2]
check("X2", okm and [os.path.basename(m[1].replace("\\", "/")) for m in man] == [os.path.basename(PRE), os.path.basename(MIG), os.path.basename(POST)],
      "manifesto: PRE (gate) → 5391 (write) → POST (gate), sha256 = arquivos")

fails = [r for r in R if not r[1]]
for cid, ok, detail in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:4} {detail}")
print(f"\nSTATIC CHECK 5391: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
