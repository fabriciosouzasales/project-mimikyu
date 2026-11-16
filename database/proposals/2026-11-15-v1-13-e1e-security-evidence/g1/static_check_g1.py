#!/usr/bin/env python3
"""
V1-13 · G1 (D-E1) — verificação ESTÁTICA da barreira preparada.

Sem banco. Comprova só propriedades do texto: forma e controles da 5389, inventário
fechado das capacidades expostas (toda função da cadeia com EXECUTE para
authenticated está protegida ou é leitura V1-12 compartilhada listada), porta como
primeira instrução, tipo de resposta por capacidade, diferença mínima e reversível
em relação aos arquivos auditados, STOP emergencial, reversão, cobertura do harness
5895 e preservação das entregas anteriores. NÃO é prova de segurança dinâmica.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1e-security-evidence/g1/static_check_g1.py
"""
from __future__ import annotations

import glob
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
PROP = os.path.join(ROOT, "database", "proposals")
TAG = "-- G1 (D-E1)"
LEGACY_SHARED = {"get_collections_shared_with_me", "get_my_collection_invites", "get_shared_collection"}
REPLACED_REVOKED = {"binder_activity_add_item", "binder_slot_editor_scope", "binder_activity_event_editor_type_guard"}
PRIOR = ["2026-11-14-v1-13-e1a-editor-role", "2026-11-15-v1-13-e1b1-editor-core-binder",
         "2026-11-15-v1-13-e1b2-editor-curation", "2026-11-15-v1-13-e1b3-pokedex-history",
         "2026-11-15-v1-13-e1c-bulk-operations", "2026-11-15-v1-13-e1c2-remaining-bulk-operations",
         "2026-11-15-v1-13-e1d-shared-reads"]

# Alterações AUTORIZADAS nas entregas anteriores (correção E2-D1, `CANONICAL BASELINE
# RECONCILIATION AND G2 CORRECTION-02`): só estes arquivos podem diferir do HEAD, e só com este sha256.
AUTHORIZED = {
    "database/proposals/2026-11-15-v1-13-e1b3-pokedex-history/5380_create_editor_pokedex_position_writes.sql":
        "32d4657c94b3157692ce00e14374f5e751b1d6df047917d3db5bd1d256bfb5e0",
    "database/proposals/2026-11-15-v1-13-e1b3-pokedex-history/5891_validate_editor_pokedex_history_HARNESS.sql":
        "133d0cc534fdfc82976f016bac341a3045fab54ece4d6a337c96af188ff53a77",
    "database/proposals/2026-11-15-v1-13-e1b3-pokedex-history/static_check_e1b3.py":
        "7db893cf9da7218bf4ce3127f44872600d2bf2bb9a57058306e3cd862198d1e0",
    "database/proposals/2026-11-15-v1-13-e1b3-pokedex-history/README.md":
        "e7e98c8702ed561699935137ca0bcbce438dc0ab2796046a4ab52fcd32cfdb57",
}


def unauthorized(status: str) -> list:
    out = []
    for line in status.splitlines():
        code, path = line.strip().split(None, 1)   # a saída do git vem com strip()
        full = os.path.join(ROOT, path)
        if code != "M" or path not in AUTHORIZED or not os.path.exists(full) \
                or hashlib.sha256(open(full, "rb").read()).hexdigest() != AUTHORIZED[path]:
            out.append(line)
    return out

R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, "rb") as fh:
        b = fh.read()
    return b, b.decode("utf-8")


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def body(text, fn):
    m = re.search(r"(?is)create (?:or replace )?function\s+public\." + fn + r"\s*\((.*?)\)\s*returns\s+(.*?)\s+language\s+(\w+)(.*?)\bas\s+(\$[A-Za-z0-9_]*\$)", text)
    a = m.end()
    return text[a:text.index(m.group(5), a)], m.group(2), m.group(3), m.group(4)


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


man = json.load(open(os.path.join(HERE, "G1_MANIFEST.json"), encoding="utf-8"))
F = {f["protected"]: f for f in man["files"]}
b89, t89 = rd(os.path.join(HERE, "5389_create_v1_13_capability_barrier.sql"))
_, h95 = rd(os.path.join(HERE, "5895_validate_v1_13_barrier_HARNESS.sql"))
_, em = rd(os.path.join(HERE, "EMERGENCY_STOP_V1_13.sql"))
_, rb = rd(os.path.join(HERE, "ROLLBACK_G1.sql"))
_, rdme = rd(os.path.join(HERE, "README.md"))
caps = {fn: f for i in man["files"] for fn, f in i["functions"].items()}

# 1. Forma -----------------------------------------------------------------------------------
for p in glob.glob(os.path.join(HERE, "*.sql")) + glob.glob(os.path.join(HERE, "protected", "*.sql")):
    b, t = rd(p)
    check(f"1.{os.path.basename(p)[:12]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t,
          f"{os.path.relpath(p, HERE)}: sem CRLF, nova linha final, não executado")

# 2. Barreira 5389 ---------------------------------------------------------------------------
n89 = nc(t89)
check("2.1", t89.count("\nbegin;\n") == 1 and t89.rstrip().endswith("commit;") and "do $pre$" in t89 and "do $post$" in t89
      and "ORDEM — capacidades da V1-13 já existem" in t89,
      "5389: uma transação, precheck (inclusive ordem: antes de 5366) e postcheck")
check("2.2", all(f"alter table public.{t} enable row level security;" in n89 for t in ("v1_13_barrier_state", "v1_13_barrier_identity"))
      and all(f"revoke all on table public.{t} from public, anon, authenticated, service_role;" in n89
              for t in ("v1_13_barrier_state", "v1_13_barrier_identity"))
      and not re.search(r"(?i)create\s+policy|grant\s+", n89),
      "tabelas: RLS ativa, nenhuma política, REVOKE ALL de PUBLIC/anon/authenticated/service_role, nenhum GRANT")
check("2.3", "values (1, 'CLOSED'," in n89 and "check (mode in ('CLOSED', 'TEST', 'OPEN'))" in n89
      and "check (id = 1)" in n89 and "on delete cascade" in n89,
      "estado único criado em CLOSED; modos fechados; registro removido com a conta de teste")
ob, oret, olang, oopt = body(t89, "v1_13_capability_open")
ab, _, alang, aopt = body(t89, "v1_13_assert_capability")
check("2.4", all("security definer" in o.lower() and "set search_path = ''" in o and "stable" in o.lower() for o in (oopt, aopt))
      and all(f"revoke all on function public.{f}() from public, anon, authenticated, service_role;" in n89
              for f in ("v1_13_capability_open", "v1_13_assert_capability")),
      "porta: definer, STABLE, search_path vazio, sem EXECUTE para qualquer papel de cliente")
check("2.5", re.search(r"select \(select auth\.uid\(\)\) is not null\s+and coalesce\(", ob) is not None
      and "when 'OPEN' then true" in ob and "when 'TEST' then exists (select 1 from public.v1_13_barrier_identity i" in ob
      and "i.user_id = (select auth.uid())" in ob and "else false" in ob and "where s.id = 1), false)" in ob
      and "current_setting" not in ob and "request." not in ob,
      "negação por padrão: sem usuário, sem linha ou modo desconhecido → falso; identidade só por auth.uid(); nada declarado pelo cliente")
check("2.6", "if not public.v1_13_capability_open() then" in ab and "'CAPABILITY_NOT_ENABLED' using errcode = '42501', hint = 'V1_13_BARRIER'" in ab,
      "assert: 42501 CAPABILITY_NOT_ENABLED quando a porta fecha")

# 3. Gerador ----------------------------------------------------------------------------------
g = subprocess.run([sys.executable, "-I", "-B", os.path.join(HERE, "build_g1_protected.py"), "--check"],
                   capture_output=True, text=True)
check("3.1", g.returncode == 0 and g.stdout.strip() == "EM DIA", f"gerador --check: {g.stdout.strip() or g.stderr.strip()}")

# 4. Inventário fechado -----------------------------------------------------------------------
grants, missing_revoke = {}, []
for f in sorted(glob.glob(os.path.join(PROP, "2026-11-1[45]-v1-13-*", "53*.sql"))):
    t = nc(rd(f)[1])
    for fn in set(re.findall(r"(?i)create (?:or replace )?function\s+public\.([a-z_0-9]+)", t)):
        if re.search(r"(?i)grant execute on function public\." + fn + r"\(", t):
            grants[fn] = os.path.basename(f)
        elif not re.search(r"(?i)revoke all on function public\." + fn + r"\([^)]*\) from [^;]*authenticated", t) \
                and fn not in REPLACED_REVOKED:
            missing_revoke.append(fn)
check("4.1", set(grants) == set(caps) | LEGACY_SHARED and len(caps) == 37 == man["capabilities"] and not missing_revoke,
      f"toda função da cadeia com EXECUTE para authenticated: 37 protegidas + 3 leituras V1-12 ({sorted(set(grants) - set(caps) - LEGACY_SHARED)}); funções sem GRANT revogam authenticated ({missing_revoke}); substituídas herdam ACL revogada ({sorted(REPLACED_REVOKED)})")
kinds = {}
for c in caps.values():
    kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
check("4.2", kinds == {"write": 29, "read": 5, "helper": 2, "invite": 1},
      f"tipos: {kinds} (29 escritas incl. troca de papel, 5 leituras, 2 ajudantes do Storage, convite)")

# 5. Diferença mínima e reversível ------------------------------------------------------------
for prot, info in F.items():
    pb, pt = rd(os.path.join(HERE, "..", prot))
    bb, bt = rd(os.path.join(PROP, info["base"]))
    lines = pt.split("\n")
    banner_end = next(i for i, l in enumerate(lines) if l.rstrip().endswith("*/")) + 1
    rest = "\n".join(l for l in lines[banner_end:] if not l.rstrip().endswith(TAG))
    for fn, fi in info["functions"].items():
        rest = rest.replace(fi["md5_protected"], fi["md5_base"])
    ins = [l for l in lines if l.rstrip().endswith(TAG)]
    check(f"5.{os.path.basename(prot)[:4]}", rest == bt and hashlib.sha256(bb).hexdigest() == info["base_sha256"]
          and hashlib.sha256(pb).hexdigest() == info["protected_sha256"]
          and len(ins) == len(info["functions"]) + 1 and lines[:banner_end][0].startswith("/* G1 (D-E1)"),
          f"{prot}: protegida = auditada + {len(info['functions'])} porta(s) + 1 precheck + cabeçalho (md5 próprios revertidos), nada mais")

# 6. Porta como primeira instrução e resposta por tipo ----------------------------------------
GATE = {"write": "perform public.v1_13_assert_capability();",
        "read": "if not public.v1_13_capability_open() then return; end if;",
        "helper": "if not public.v1_13_capability_open() then return false; end if;"}
bad = []
for prot, info in F.items():
    pt = rd(os.path.join(HERE, "..", prot))[1]
    for fn, fi in info["functions"].items():
        b, ret, lang, _ = body(pt, fn)
        if md5(b) != fi["md5_protected"]:
            bad.append(fn + ":md5")
        if fi["kind"] == "invite":
            i_role = b.find("RAISE EXCEPTION 'INVALID_ROLE'")
            i_gate = b.find("IF v_role = 'EDITOR' THEN PERFORM public.v1_13_assert_capability(); END IF;")
            i_read = min(x for x in (b.find("FROM public."), b.find("from public.")) if x >= 0)
            if not (0 <= i_role < i_gate < i_read) or b.count("v1_13_") != 1:
                bad.append(fn)
            continue
        m = re.search(r"(?im)^[ \t]*begin[ \t]*\n", b)
        first = b[m.end():].lstrip(" \t").split("\n")[0]
        ok = first.startswith(GATE[fi["kind"]]) and b.count("v1_13_") == 1 and lang.lower() == "plpgsql"
        if fi["kind"] == "read":
            ok = ok and ret.lower().startswith("table")
        if fi["kind"] == "helper":
            ok = ok and ret.strip().lower() == "boolean"
        if not ok:
            bad.append(fn)
check("6.1", not bad, f"porta é a primeira instrução do corpo (convite: logo após validar o papel e antes de qualquer leitura); escrita → 42501, leitura → zero linhas, ajudante → falso ({bad})")
check("6.2", all("PRECHECK G1: barreira 5389 ausente" in rd(os.path.join(HERE, "..", p))[1] for p in F),
      "toda versão protegida recusa aplicar sem a 5389")

# 7. Preservação V1-12 e mudanças compartilhadas ---------------------------------------------
inv = rd(os.path.join(HERE, "protected", "5369_replace_invite_collection_member_with_role.sql"))[1]
p77 = rd(os.path.join(HERE, "protected", "5377_create_editor_collection_cover_storage_policies.sql"))[1]
b77 = rd(os.path.join(PROP, PRIOR[2], "5377_create_editor_collection_cover_storage_policies.sql"))[1]
pol = lambda t: re.findall(r"(?is)create policy .*?;", nc(t))
check("7.1", "p_role TEXT DEFAULT 'VIEWER'" in inv and inv.count("v1_13_assert_capability") == 2,
      "5369: assinatura com padrão VIEWER intacta (convite de 2 argumentos da V1-12); porta só no ramo EDITOR (+ precheck)")
check("7.2", pol(p77) == pol(b77) and len(pol(p77)) == 3 and "5176" in b77,
      "5377: as 3 políticas novas idênticas; a proteção está nos ajudantes; políticas do dono (5176) e de leitura compartilhada (5329) não são tocadas")
prot_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(HERE, "protected", "*.sql")))
shared = ["5366", "5367", "5368", "5371", "5372", "5378", "5379", "5381", "5384"]
check("7.3", len(prot_files) == 16 and not any(f[:4] in shared for f in prot_files),
      f"16 arquivos protegidos; mudanças compartilhadas ({', '.join(shared)}) aplicadas como auditadas, sem porta")

# 8. STOP emergencial ---------------------------------------------------------------------------
sig_wr = sorted(c["signature"] for fn, c in caps.items() if c["kind"] in ("write", "read"))
rev = sorted(re.findall(r"revoke execute on function (public\.[a-z_]+\([^)]*\)) from public, anon, authenticated;", em))
check("8.1", rev == sig_wr and len(rev) == 34 and "invite_collection_member" not in "".join(rev)
      and "collection_cover_editor" not in "".join(rev)
      and "update public.v1_13_barrier_state set mode = 'CLOSED'" in em
      and "lock table storage.objects in access exclusive mode nowait;" in em
      and all(f"drop policy if exists {p} on storage.objects;" in em
              for p in ("collection_cover_insert_editor", "collection_cover_select_editor", "collection_cover_delete_editor"))
      and em.index("-- E1") < em.index("-- E2") < em.index("-- E3") and em.count("begin;") == 3,
      "STOP: E1 modo CLOSED; E2 REVOKE das 34 RPCs novas (sem o convite compartilhado e sem os ajudantes, cuja revogação quebraria o bucket para todos); E3 DROP das 3 políticas com LOCK NOWAIT")

# 9. Reversão -----------------------------------------------------------------------------------
check("9.1", "ainda há capacidades protegidas que chamam a porta" in rb
      and rb.index("do $pre$") < rb.index("drop function if exists public.v1_13_assert_capability()")
      and rb.count("drop function if exists") == 2 and rb.count("drop table if exists") == 2
      and not re.search(r"\b(delete|truncate|update|insert)\b", nc(rb), re.I),
      "ROLLBACK_G1: recusa enquanto houver capacidade protegida; remove só a porta e suas tabelas")

# 10. Harness 5895 ------------------------------------------------------------------------------
arr = lambda name: re.findall(r"'(public\.[a-z_0-9]+\([^)]*\))'", re.search(name + r" text\[\] := array\[(.*?)\];", h95, re.S).group(1))
cw, cr, ch = arr("c_w"), arr("c_r"), arr("c_h")
want = lambda k: sorted(c["signature"] for c in caps.values() if c["kind"] == k)
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h95)))
exp = int(re.search(r"v_expected := (\d+);", h95).group(1))
check("10.1", sorted(cw) == want("write") and sorted(cr) == want("read") and sorted(ch) == want("helper")
      and "c_inv text := '" + caps["invite_collection_member"]["signature"] + "'" in h95,
      "5895: listas de assinaturas = inventário (29 + 5 + 2 + convite)")
need = {"estrutura da porta": "0.1", "cobertura": "0.2", "estado inicial": "0.3", "compartilhadas intactas": "0.4",
        "CLOSED": "1.1", "Storage em CLOSED": "1.2", "V1-12 em CLOSED": "1.3", "TEST não registrado": "2.1",
        "TEST registrado": "2.2", "barreira × autorização funcional": "2.3", "leituras TEST": "2.4",
        "convite por titular não registrado": "2.5", "revogação": "2.6", "OPEN futuro": "3.1",
        "configuração ausente": "3.2", "anon privilégio": "3.3", "anon chamada": "3.4", "tabelas administrativas": "3.5",
        "EDITOR aceito em CLOSED": "3.6", "resíduo": "99.1"}
check("10.2", len(ids) + 1 == exp and all(v in ids for v in need.values()) and f"{exp}/{exp} PASS" in h95,
      f"5895: {len(ids)} verificações + F.2 = {exp}; cenários {[k for k, v in need.items() if v not in ids]}")
check("10.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h95, re.I | re.M) and "MS895" in h95
      and "L1 SET LOCAL ROLE" in h95
      and "'CAPABILITY_NOT_ENABLED'" in h95,
      "5895: sem BEGIN/COMMIT, sentinela, limitações declaradas, recusa da barreira identificada pela mensagem exata")

# 11. Entregas anteriores e escopo --------------------------------------------------------------
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema"]
                    + [os.path.join("database", "proposals", d) for d in PRIOR], capture_output=True, text=True).stdout.strip()
bad_st = unauthorized(st)
check("11.1", not bad_st, f"frontend, schema canônico e E1-A … E1-D sem alterações, exceto as 4 autorizadas da E2-D1 com sha256 exato ({bad_st or 'conforme'})")
check("11.2", "5389" in rdme and "5366" in rdme and rdme.index("5389") < rdme.index("5366") and "NÃO EXECUTAD" in rdme,
      "README do G1 presente, com a 5389 antes da cadeia")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<16} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
