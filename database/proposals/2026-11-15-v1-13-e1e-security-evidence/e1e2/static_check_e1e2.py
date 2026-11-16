#!/usr/bin/env python3
"""
V1-13 · E1-E2 — verificação ESTÁTICA da cadeia protegida e dos ensaios G2.

Sem banco. Verifica, independentemente do gerador: hashes e manifesto; moldura T0–T11;
5389 primeiro; uso exclusivo das versões protegidas; ordem de dependências; nenhuma
redefinição desprotegida; modos da barreira antes de cada harness; travas NOWAIT;
totais da sentinela; correspondência P1 × P1-G; variante 5863; S0 só leitura e md5
canônicos; md5 fixados nos harnesses × estado final da cadeia; cobertura dos
rollbacks; entregas anteriores intactas. NÃO é prova dinâmica.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1e-security-evidence/e1e2/static_check_e1e2.py
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
EVID = os.path.dirname(HERE)
PROP = os.path.dirname(EVID)
ROOT = os.path.abspath(os.path.join(PROP, "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
P1 = os.path.join(PROP, "2026-11-14-v1-13-e1a-editor-role", "p1", "P1_DRYRUN_E1A_rollback.sql")
VAR = {"A": "G2_A_E1A_PROTECTED_rollback.sql", "B": "G2_B_CHAIN_STORAGE_LAST_rollback.sql",
       "C": "G2_C_CHAIN_FULL_FINAL_rollback.sql"}
PROTECTED = {"5369", "5370", "5373", "5374", "5375", "5376", "5377", "5380", "5382", "5383",
             "5385", "5386", "5387", "5323", "5324", "5388"}
DEPS = {"5366": ["5389"], "5368": ["5367"], "5369": ["5366"], "5370": ["5366"], "5374": ["5371", "5372"],
        "5375": ["5371", "5372"], "5378": ["5371"], "5379": ["5372"], "5380": ["5376"], "5381": ["5379"],
        "5382": ["5378", "5381"], "5383": ["5382"], "5384": ["5381"], "5385": ["5382", "5384"],
        "5386": ["5385", "5384"], "5387": ["5385", "5384"], "5388": ["5379"]}
EXPECTED = {"5861": 51, "5862": 33, "5863": 37, "5864": 7, "5888": 54, "5889": 56, "5890": 45, "5891": 33,
            "5892": 27, "5893": 24, "5894": 29, "5895": 21}
MODE = {"5861": "CLOSED", "5862": "CLOSED", "5863": "CLOSED", "5864": "CLOSED", "5895": "CLOSED"}
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
    return open(p, "rb").read()


def sha(b):
    return hashlib.sha256(b).hexdigest()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def bodies(text):
    out = []
    for m in re.finditer(r"(?is)create (?:or replace )?function\s+public\.([a-z_0-9]+)\s*\(.*?\bas\s+(\$[A-Za-z0-9_]*\$)", text):
        a = m.end()
        out.append((m.group(1), hashlib.md5(text[a:text.index(m.group(2), a)].encode()).hexdigest()))
    return out


# 1. Gerador e manifesto ------------------------------------------------------------------
g = subprocess.run([sys.executable, "-I", "-B", os.path.join(HERE, "build_g2_chain.py"), "--check"], capture_output=True, text=True)
check("1.1", g.returncode == 0 and g.stdout.strip() == "EM DIA", f"gerador --check: {g.stdout.strip() or g.stderr.strip()}")
man = [l.split("  ", 1) for l in rd(os.path.join(HERE, "G2_MANIFEST.sha256")).decode().splitlines()]
bad = [p for h, p in man if not os.path.exists(os.path.join(HERE, p)) or sha(rd(os.path.join(HERE, p))) != h]
check("1.2", not bad and len(man) >= 40, f"G2_MANIFEST: {len(man)} entradas, todas com sha256 conferido ({bad})")
g1m = json.loads(rd(os.path.join(EVID, "g1", "G1_MANIFEST.json")))
check("1.3", all(sha(rd(os.path.join(EVID, f["protected"]))) == f["protected_sha256"]
                 and sha(rd(os.path.join(PROP, f["base"]))) == f["base_sha256"] for f in g1m["files"])
      and len(g1m["files"]) == 16 and g1m["capabilities"] == 37,
      "G1_MANIFEST: 16 protegidas e 16 bases com sha256 conferido; 37 capacidades")
caps = {fn for f in g1m["files"] for fn in f["functions"]}

# 2. Moldura e sequência de cada ensaio ---------------------------------------------------------
T = {k: rd(os.path.join(HERE, v)).decode("utf-8") for k, v in VAR.items()}
for k, t in T.items():
    marks = re.findall(r"(?m)^-- @@T(\d+)", t)
    rank = [7 if x in ("7", "8") else int(x) for x in marks]   # T7 e T8 podem se alternar (5377 por último)
    order_ok = rank == sorted(rank) and marks[0] == "0" and marks[-1] == "11"
    body = nc(t)
    check(f"2.{k}.1", order_ok and body.count("BEGIN;") == 1 and "SET SESSION default_transaction_read_only = on;" in body
          and not re.search(r"(?im)^\s*(commit|end\s+transaction|savepoint|release|prepare\s+transaction|set\s+constraints)\b", body)
          and t.startswith("/*") and "\\set ON_ERROR_STOP on" in t
          and re.search(r"raise exception using message = v_msg, errcode = v_code;\s*end;\s*\$t9sentinel\$;", t)
          and "deferrable initially deferred" in t,
          f"{VAR[k]}: marcadores T0…T11 em ordem; um BEGIN; sem COMMIT/SAVEPOINT; T0, trava de COMMIT, sentinela incondicional")
    mig = re.findall(r"(?m)^-- @@T7 (\d{4}) \((\w+)\) sha256=([0-9a-f]{64})$", t)
    nums = [m[0] for m in mig]
    seen, dep_ok = set(), True
    for n in nums:
        if any(d not in seen for d in DEPS.get(n, [])) or n in seen:
            dep_ok = False
        seen.add(n)
    check(f"2.{k}.2", nums and nums[0] == "5389" and dep_ok and len(nums) == len(set(nums))
          and all((kind == "protegida") == (n in PROTECTED) for n, kind, _ in mig)
          and all(h == next(f["protected_sha256"] for f in g1m["files"] if f["protected"].endswith("/" + os.path.basename(f["protected"])) and os.path.basename(f["protected"]).startswith(n))
                  for n, kind, h in mig if kind == "protegida"),
          f"{VAR[k]}: 5389 primeiro; {len(nums)} migrations sem repetição, em ordem de dependência (inclusive 5384 → 5385–5387); as 16 só como protegidas, com o sha256 do manifesto G1")
    # capacidades: uma definição cada, sempre com porta
    defs = re.findall(r"(?is)create (?:or replace )?function\s+public\.([a-z_0-9]+)\s*\(", nc(t))
    cap_defs = [d for d in defs if d in caps]
    gated = all("public.v1_13_" in b for fn, b in
                ((m.group(1), t[m.end():t.index(m.group(2), m.end())]) for m in
                 re.finditer(r"(?is)create (?:or replace )?function\s+public\.([a-z_0-9]+)\s*\(.*?\bas\s+(\$[A-Za-z0-9_]*\$)", t))
                if fn in caps)
    want = 2 if k == "A" else 37
    check(f"2.{k}.3", len(cap_defs) == len(set(cap_defs)) == want and gated,
          f"{VAR[k]}: {want} capacidades definidas uma única vez, todas com a porta (nenhuma redefinição desprotegida)")
    # modos antes de cada harness
    pos = sorted([(m.start(), "mode", m.group(1)) for m in re.finditer(r"(?m)^update public\.v1_13_barrier_state set mode = '(\w+)'", t)]
                 + [(m.start(), "harn", m.group(1)) for m in re.finditer(r"(?m)^-- @@T8 harness (\d{4})", t)])
    cur, ok_modes, harns = "CLOSED", True, []
    for _, kind, x in pos:
        if kind == "mode":
            cur = x
        else:
            harns.append(x)
            if cur != MODE.get(x, "OPEN"):
                ok_modes = False
    first_mode = min((p for p, kind, _ in pos if kind == "mode"), default=0)
    check(f"2.{k}.4", ok_modes and cur == "CLOSED" and first_mode > t.index("-- @@T7")
          and t.rindex("update public.v1_13_barrier_state") < t.index("-- @@T9 postcheck"),
          f"{VAR[k]}: V1-12 e 5895 em CLOSED, funcionais em OPEN, modo só mudado dentro do ensaio e terminado em CLOSED ({harns})")
    total = sum(EXPECTED[h] for h in harns)
    check(f"2.{k}.5", f"v_ok := coalesce(v_total = {total} and v_passes = {total}" in t and f"= {len(harns)}, false);" in t
          and all(t.count(f"from pg_temp.wh_{h}_validate();") == 1 for h in harns),
          f"{VAR[k]}: sentinela exige {total} verificações e {len(harns)} GATEs PASS")
    locks = re.findall(r"(?m)^LOCK TABLE ([\w.]+) IN ACCESS EXCLUSIVE MODE NOWAIT;", t)
    i5377 = t.find("-- @@T7 5377 ")
    want_locks = ["public.collection_membership"] if k == "A" else \
        ["public.collection_membership", "public.binder_activity_event", "public.binder_activity_item", "storage.objects"]
    lock_ok = locks == want_locks and all(t.index(f"LOCK TABLE {r} ") < t.index("-- @@T7 5389") for r in want_locks[:3 if k != "A" else 1])
    if k != "A":
        lock_ok = lock_ok and 0 < t.index("LOCK TABLE storage.objects") < i5377 \
            and not re.search(r"(?m)^-- @@T", t[t.index("LOCK TABLE storage.objects"):i5377].split("\n", 2)[-1])
    check(f"2.{k}.6", lock_ok, f"{VAR[k]}: LOCK NOWAIT antes do DDL ({locks}); storage.objects imediatamente antes da 5377")
B = T["B"]
bl, b77 = B.find("LOCK TABLE storage.objects"), B.find("-- @@T7 5377 ")
check("2.B.7", bl > 0 and b77 > bl
      and all(0 < B.find(f"-- @@T8 harness {h}") < bl for h in ("5888", "5889", "5891", "5892", "5893", "5894"))
      and all(B.find(f"-- @@T8 harness {h}") > b77 for h in ("5863", "5890", "5895")),
      "G2_B: 5888–5894 antes da 5377 (retenção mínima de storage.objects); 5863, 5890 e 5895 no estado final")
C = T["C"]
c77 = C.find("-- @@T7 5377 ")
check("2.C.7", c77 > 0 and all(C.find(f"-- @@T8 harness {h}") > c77 for h in EXPECTED),
      "G2_C: todos os 12 harnesses no estado final completo")

# 3. P1 × P1-G -----------------------------------------------------------------------------------
p1 = rd(P1).decode("utf-8")
def sect(t, mark):
    i = t.index(mark)
    j = t.find("\n-- @@T", i + 1)
    return t[i:j]
same = []
for n in ("5366", "5367", "5368"):
    a = sect(p1, f"-- @@T7 {n}_").split("\n", 1)[1]
    b = sect(T["A"], f"-- @@T7 {n} ").split("\n", 1)[1]
    same.append(a.strip() == b.strip())
h88a = sect(p1, "-- @@T8 5888_").split("\n", 1)[1].strip()
h88b = sect(T["A"], "-- @@T8 harness 5888 ").split("\n", 1)[1].split("insert into pg_temp.g2_evidence")[0].strip()
p1_marks = re.findall(r"(?m)^-- @@(T\d+)", p1)
a_marks = re.findall(r"(?m)^-- @@(T\d+)", T["A"])
check("3.1", all(same) and h88a == h88b and sorted(set(p1_marks)) == sorted(set(a_marks))
      and "T3: PostgreSQL < 14" in p1 and "G2 T3: PostgreSQL < 14" in T["A"]
      and "LOCK TABLE public.collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT;" in p1,
      "P1-G preserva a moldura do P1 (mesmos blocos T0–T11), 5366–5368 byte a byte e o corpo da 5888; muda: 5389 antes, 5369/5370 protegidas, 5861 em CLOSED, 5888 em OPEN, postcheck da barreira, SQLSTATE E2AOK/E2ANO")
check("3.2", sha(rd(P1)) == next(l.split()[0] for l in rd(os.path.join(os.path.dirname(P1), "MANIFEST.sha256")).decode().splitlines()
                                  if l.endswith("P1_DRYRUN_E1A_rollback.sql")),
      "P1 original preservado (sha256 igual ao do MANIFEST da E1-A)")

# 4. Variante 5863 -------------------------------------------------------------------------------
base63 = rd(os.path.join(PROP, "2026-10-30-v1-12-shared-binder-visual-assets", "5863_validate_shared_binder_visual_assets.sql")).decode()
var63 = rd(os.path.join(HERE, "harness", "5863_validate_shared_binder_visual_assets_v1.2-E1E.sql")).decode()
vlines = var63.split("\n")[3:]
removed = [l for l in base63.split("\n") if l not in vlines]
added = [l for l in vlines if l not in base63.split("\n")]
s4_base = base63[base63.index("res := res || jsonb_build_object('id','S.4'"):]
s4_base = s4_base[:s4_base.index("res := res || jsonb_build_object('id','S.5'")]
names12 = ["binder_slot_image_select_own", "binder_slot_image_insert_own", "binder_slot_image_delete_own",
           "collection_cover_select_own", "collection_cover_insert_own", "collection_cover_update_own",
           "collection_cover_delete_own", "binder_slot_image_select_shared", "collection_cover_select_shared",
           "collection_cover_insert_editor", "collection_cover_select_editor", "collection_cover_delete_editor"]
s4_var = var63[var63.index("res := res || jsonb_build_object('id','S.4'"):]
s4_var = s4_var[:s4_var.index("res := res || jsonb_build_object('id','S.5'")]
check("4.1", var63.startswith("/* E1-E2 — VARIANTE 5863 v1.2-E1E") and all("-- E1E" in l for l in added)
      and all(l in s4_base.split("\n") for l in removed) and all(l in s4_var for l in added)
      and "AUTORIZADA" in var63.split("\n")[0] + var63.split("\n")[1],
      f"5863 v1.2-E1E: só a S.4 muda ({len(added)} linhas novas, todas marcadas; {len(removed)} retiradas, todas da S.4 original); AUTORIZADA")
check("4.2", all(s4_var.count(f"'{n}'") >= 1 for n in names12) and ") = 7" in s4_var and ") = 2" in s4_var and ") = 3" in s4_var
      and ") = 12" in s4_var and "p.permissive = 'PERMISSIVE'" in s4_var and "p.roles = array['authenticated']::name[]" in s4_var
      and "'anon' = any(p.roles) and p.cmd <> 'SELECT'" in s4_var and "'public' = any(p.roles)" in s4_var
      and "p.policyname not in (" in s4_var and "foldername(name))[1]" in s4_var
      and "collection_cover_editor_can_upload(name)" in s4_var and "collection_cover_editor_folder_ok(name)" in s4_var
      and "q.prosrc like '%public.v1_13_capability_open()%'" in s4_var and "m.role = ''EDITOR''" in s4_var
      and "if v_owner = v_uid then%return false;" in s4_var and "not has_function_privilege('anon', q.oid, 'EXECUTE')" in s4_var,
      "5863 S.4: 12 políticas individualmente (nome, comando, papéis, predicado, permissiva), conjunto fechado, sem escrita anon nem PUBLIC; ajudantes presos à identidade, à participação EDITOR ativa e à barreira; pasta do titular só com as políticas do dono — não é só troca de contagem")

# 5. S0 -------------------------------------------------------------------------------------------
s0 = rd(os.path.join(HERE, "S0_G2_readonly.sql")).decode()
s0b = nc(s0)
check("5.1", s0b.strip().lower().startswith("select jsonb_build_object(") and s0b.strip().endswith("as s0;")
      and not re.search(r"(?i)\b(insert|update|delete|create|alter|drop|grant|revoke|truncate|do|set_config|nextval|lock|set|reset|copy|call|vacuum|analyze|pg_sleep|pg_terminate_backend|pg_cancel_backend|pg_advisory\w*|lo_\w+|dblink\w*|txid_current)\b",
                        re.sub(r"'(?:[^']|'')*'", "''", s0b).replace("update_delete_truncate", "").replace("auth_users_escrita", "").replace("storage_objects_escrita", ""))
      and s0b.count(";") == 1,
      "S0: uma única instrução SELECT, sem escrita, DO, set_config, nextval ou LOCK")
canon = {}
for f in sorted(os.listdir(SCHEMA)):
    if f.endswith(".sql"):
        for fn, m in bodies(rd(os.path.join(SCHEMA, f)).decode("utf-8", "ignore")):
            canon[fn] = m
pins = re.findall(r"\('([a-z_]+)',\s+'([0-9a-f]{32})'\)", s0)
badp = [fn for fn, m in pins if canon.get(fn) != m]
check("5.2", len(pins) == 24 and not badp, f"S0: {len(pins)} md5 canônicos = corpo vigente em database/schema ({badp})")

check("5.3", "to_jsonb(r.rolconfig)" not in s0 and "split_part(c.cfg, '=', 1) in ('statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout')" in s0
      and all(k in s0 for k in ("'assume_anon', pg_has_role(current_user, 'anon', 'MEMBER')",
                                "'assume_authenticated', pg_has_role(current_user, 'authenticated', 'MEMBER')",
                                "'executor_e_dono_ou_membro'", "'transaction_timeout_disponivel'", "'server_version_num'"))
      and not re.search(r"(?i)\b(query|email|encrypted_password|raw_user_meta_data|phone)\b", re.sub(r"(?s)where .*?(?=,\n|\)\)|$)", "", s0b).split("as s0")[0].split("'residuo'")[0]),
      "S0: papeis_api só com chaves de timeout; pré-condições do executor (SET ROLE anon/authenticated, dono de storage.objects); versão e transaction_timeout; nenhuma coluna de dado privado na saída")
# 6. md5 fixados nos harnesses × estado final --------------------------------------------------
final = dict(canon)
order = re.findall(r"(?m)^-- @@T7 (\d{4}) \((\w+)\)", C)
srcmap = {}
for f in g1m["files"]:
    srcmap[os.path.basename(f["protected"])[:4]] = os.path.join(EVID, f["protected"])
for p in glob.glob(os.path.join(PROP, "2026-11-1[45]-v1-13-*", "53*.sql")) + [os.path.join(EVID, "g1", "5389_create_v1_13_capability_barrier.sql")]:
    srcmap.setdefault(os.path.basename(p)[:4], p)
for n, _ in order:
    for fn, m in bodies(rd(srcmap[n]).decode()):
        final[fn] = m
hfiles = re.findall(r"(?m)^-- @@T8 harness (\d{4})", C)
bad_pins = []
for h in hfiles:
    sec = sect(C, f"-- @@T8 harness {h} ")
    vars_ = dict(re.findall(r"(\w+)\s+oid := to_regprocedure\('public\.([a-z_0-9]+)\(", sec))
    for fn, vals in re.findall(r"to_regprocedure\('public\.([a-z_0-9]+)\([^)]*\)'\)\)\s*(?:=|is distinct from|in)\s*\(?((?:\s*'[0-9a-f]{32}',?(?:\s*--[^\n]*)?)+)", sec):
        ms = re.findall(r"[0-9a-f]{32}", vals)
        if final.get(fn) not in ms:
            bad_pins.append(f"{h}:{fn}")
    for var, val in re.findall(r"q\.oid = (\w+)\) = '([0-9a-f]{32})'", sec):
        if var in vars_ and final.get(vars_[var]) != val:
            bad_pins.append(f"{h}:{vars_[var]}")
state, bad_mig = dict(canon), []
for n, _ in order:
    t = rd(srcmap[n]).decode()
    own = {fn for fn, _ in bodies(t)}
    for fn, vals in re.findall(r"to_regprocedure\('public\.([a-z_0-9]+)\([^)]*\)'\)\)\s*(?:=|is distinct from|in)\s*\(?((?:\s*'[0-9a-f]{32}',?(?:\s*--[^\n]*)?)+)", t):
        if fn not in own and state.get(fn) not in re.findall(r"[0-9a-f]{32}", vals):
            bad_mig.append(f"{n}:{fn}")
    for fn, m in bodies(t):
        state[fn] = m
check("6.2", not bad_mig, f"md5 fixados nos pre/postchecks das migrations = corpo vigente antes de cada uma ({sorted(set(bad_mig))})")
check("6.1", not bad_pins, f"md5 fixados nos 12 harnesses = corpos do estado final da cadeia protegida ({bad_pins})")

# 7. Rollback -------------------------------------------------------------------------------------
rbs = {os.path.basename(p): rd(p).decode() for p in glob.glob(os.path.join(PROP, "2026-11-1[45]-v1-13-*", "ROLLBACK_*.sql"))}
rbs["ROLLBACK_G1.sql"] = rd(os.path.join(EVID, "g1", "ROLLBACK_G1.sql")).decode()
alltxt = "\n".join(rbs.values())
created = set()
for n, _ in order:
    t = nc(rd(srcmap[n]).decode())
    created |= set(re.findall(r"(?i)\bcreate function\s+public\.([a-z_0-9]+)", t))
missing_rb = sorted(fn for fn in created if not re.search(r"(?i)drop function (if exists )?public\." + fn + r"\(", alltxt))
check("7.1", not missing_rb and len(rbs) == 8,
      f"toda função CRIADA pela cadeia tem DROP em algum dos 8 rollbacks (E1A, E1B1, E1B2, E1B3, E1C, E1C2, E1D, G1) ({missing_rb})")

# 8. Entregas anteriores e governança --------------------------------------------------------------
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema"]
                    + [os.path.join("database", "proposals", d) for d in PRIOR], capture_output=True, text=True).stdout.strip()
bad_st = unauthorized(st)
check("8.1", not bad_st, f"frontend, schema canônico e E1-A … E1-D sem alterações, exceto as 4 autorizadas da E2-D1 com sha256 exato ({bad_st or 'conforme'})")
rdme = rd(os.path.join(HERE, "README.md")).decode()
check("8.2", all(x in rdme for x in ("G2 NÃO INICIADO", "NÃO EXECUTAD", "5863", "S0_G2_readonly.sql", "G3", "G4", "etapa 7")),
      "README da E1-E2: estado (G2 não iniciado, nada executado), adaptação da 5863, S0, separação G3/G4 e etapa 7")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<8} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
