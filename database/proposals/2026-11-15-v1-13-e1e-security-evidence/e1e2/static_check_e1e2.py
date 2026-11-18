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
# 5888 v1.1-E1E (TARGETED HARNESS CORRECTION-01): o G2 usa o harness corrigido; a disciplina da correção é a 3.3.
_h88c = rd(os.path.join(HERE, "harness", "5888_validate_editor_role_foundation_HARNESS_v1.1-E1E.sql")).decode("utf-8")
h88a = _h88c[_h88c.index("create or replace function pg_temp.wh_5888_"):_h88c.index("$fn$;", _h88c.index("create or replace function pg_temp.wh_5888_validate()")) + 5].strip()
h88b = sect(T["A"], "-- @@T8 harness 5888 ").split("\n", 1)[1].split("insert into pg_temp.g2_evidence")[0].strip()
p1_marks = re.findall(r"(?m)^-- @@(T\d+)", p1)
a_marks = re.findall(r"(?m)^-- @@(T\d+)", T["A"])
check("3.1", all(same) and h88a == h88b and sorted(set(p1_marks)) == sorted(set(a_marks))
      and "T3: PostgreSQL < 14" in p1 and "G2 T3: PostgreSQL < 14" in T["A"]
      and "LOCK TABLE public.collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT;" in p1,
      "P1-G preserva a moldura do P1 (mesmos blocos T0–T11), 5366–5368 byte a byte e o corpo da 5888 v1.1-E1E; muda: 5389 antes, 5369/5370 protegidas, 5861 em CLOSED, 5888 em OPEN, postcheck da barreira, SQLSTATE E2AOK/E2ANO")
# 3.3 Correções de harness E1E (5861 v1.5-E1E, 5888 v1.1-E1E): originais preservados, delta só em linhas "-- E1E",
#     mesmas verificações, sem GRANT/REVOKE/política, e nenhuma leitura direta de tabela sob o papel do cliente na 5888
#     além da negativa 7.4 (classe C).
import difflib as _dl
_orig = {"5861": (os.path.join(PROP, "2026-11-14-v1-13-e1a-editor-role", "5861_validate_collection_sharing_v1.4.sql"), "9135bd0b8ab0dc7cd0d25bb630bf45cce0b835f66bd381544b33a55ee64bf146",
                  os.path.join(HERE, "harness", "5861_validate_collection_sharing_v1.5-E1E.sql")),
         "5888": (os.path.join(PROP, "2026-11-14-v1-13-e1a-editor-role", "5888_validate_editor_role_foundation_HARNESS.sql"), "c6e336396ba57fdcfddc849ee99f6f65a8cf4b688a32bd5efd9db0bdf70a8e48",
                  os.path.join(HERE, "harness", "5888_validate_editor_role_foundation_HARNESS_v1.1-E1E.sql"))}
_okc = []
for _n, (_po, _ho, _pc) in _orig.items():
    _bo = rd(_po); _o = _bo.decode("utf-8"); _c = rd(_pc).decode("utf-8")
    _hdr = _c.index("*/")
    _add = [l[1:] for l in _dl.unified_diff(_o.split("\n"), _c.split("\n"), lineterm="", n=0) if l.startswith("+") and not l.startswith("+++")]
    _body_add = [l for l in _add if l in _c[_hdr:]]
    _okc.append(sha(_bo) == _ho
                and re.findall(r"'id','([^']+)'", _o) == re.findall(r"'id','([^']+)'", _c)
                and all("E1E" in l for l in _body_add)
                and not any(re.search(r"(?i)\b(grant|revoke|policy|row level|security definer|alter table)\b", l) for l in _body_add))
_L = _orig["5888"][2]; _L = rd(_L).decode("utf-8").split("\n")
_st = "owner"; _cli = []
for _i in range([i for i, l in enumerate(_L) if "function pg_temp.wh_5888_validate()" in l][0], len(_L)):
    _l = _L[_i]
    if "wh_5888_as(" in _l and "perform" in _l: _st = "client"
    if "execute 'reset role'" in _l: _st = "owner"
    for _m in re.finditer(r"(from|update|into|join)\s+(public|auth|storage)\.([a-z_]+)(\s*\()?", _l):
        if not _m.group(4) and _st == "client": _cli.append(_l.strip())
_c61 = rd(_orig["5861"][2]).decode("utf-8")
check("3.3", all(_okc) and len(_cli) == 1 and "perform count(*) from public.collection_membership" in _cli[0]
      and "'binder_name','show_brand_mark'" in _c61 and "jsonb_typeof(j -> 'show_brand_mark') = 'boolean'" in _c61,
      "harnesses corrigidos: originais E1-A preservados (sha256), delta só em linhas -- E1E, mesmas verificações, sem GRANT/REVOKE/política; 5888 sem leitura direta de tabela sob o cliente exceto a negativa 7.4; 5861 3.8 com as chaves da 5321 tipadas")
check("3.2", sha(rd(P1)) == next(l.split()[0] for l in rd(os.path.join(os.path.dirname(P1), "MANIFEST.sha256")).decode().splitlines()
                                  if l.endswith("P1_DRYRUN_E1A_rollback.sql")),
      "P1 original preservado (sha256 igual ao do MANIFEST da E1-A)")

# 4. Variante 5863 -------------------------------------------------------------------------------
base63 = rd(os.path.join(PROP, "2026-10-30-v1-12-shared-binder-visual-assets", "5863_validate_shared_binder_visual_assets.sql")).decode()
var63 = rd(os.path.join(HERE, "harness", "5863_validate_shared_binder_visual_assets_v1.3-E1E.sql")).decode()
vlines = var63[var63.index("*/\n") + 3:].split("\n")
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
check("4.1", var63.startswith("/* E1-E2 — VARIANTE 5863 v1.3-E1E") and all("-- E1E" in l for l in added)
      and all(l in s4_base.split("\n") for l in removed) and all(l in s4_var for l in added)
      and "AUTORIZADA" in var63.split("\n")[0] + var63.split("\n")[1],
      f"5863 v1.3-E1E: só a S.4 muda ({len(added)} linhas novas, todas marcadas; {len(removed)} retiradas, todas da S.4 original); AUTORIZADA")
check("4.2", all(s4_var.count(f"'{n}'") >= 1 for n in names12) and ") = 7" in s4_var and ") = 2" in s4_var and ") = 3" in s4_var
      and ") = 12" in s4_var and "pol.permissive = 'PERMISSIVE'" in s4_var and "pol.roles = array['authenticated']::name[]" in s4_var
      and "'anon' = any(pol.roles) and pol.cmd <> 'SELECT'" in s4_var and "'public' = any(pol.roles)" in s4_var
      and "pol.policyname not in (" in s4_var and "foldername(name))[1]" in s4_var
      and "collection_cover_editor_can_upload(name)" in s4_var and "collection_cover_editor_folder_ok(name)" in s4_var
      and "q.prosrc like '%public.v1_13_capability_open()%'" in s4_var and "m.role = ''EDITOR''" in s4_var
      and "if v_owner = v_uid then%return false;" in s4_var and "not has_function_privilege('anon', q.oid, 'EXECUTE')" in s4_var,
      "5863 S.4: 12 políticas individualmente (nome, comando, papéis, predicado, permissiva), conjunto fechado, sem escrita anon nem PUBLIC; ajudantes presos à identidade, à participação EDITOR ativa e à barreira; pasta do titular só com as políticas do dono — não é só troca de contagem")

# 4.3 STOP 12 (SQLSTATE 55000 na S.4): alias de pg_policies não colide com a variável record p; a v1.2-E1E
#     e o G2_B MGMTAPI executados ficam preservados; nenhum homônimo alias/record nos quatro ensaios G2_B/G2_C.
import runpy as _rp
_sc = _rp.run_path(os.path.join(HERE, "scan_alias_collisions.py"))
_v12 = rd(os.path.join(HERE, "harness", "5863_validate_shared_binder_visual_assets_v1.2-E1E.sql")).decode()
_s4_12 = _v12[_v12.index("res := res || jsonb_build_object('id','S.4'"):]
_s4_12 = _s4_12[:_s4_12.index("res := res || jsonb_build_object('id','S.5'")]
_rows = [r for f in ("G2_B_CHAIN_STORAGE_LAST_rollback.sql", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI.sql",
                     "G2_C_CHAIN_FULL_FINAL_rollback.sql", "G2_C_CHAIN_FULL_FINAL_rollback_MGMTAPI.sql")
         for r in _sc["scan"](os.path.join(HERE, f))]
check("4.3", sha(_v12.encode("utf-8")) == "d20055b88a3b71664564e4024d0dc44b072941976cddc1329fc7a28525a5011d"
      and sha(rd(os.path.join(HERE, "executed", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI_EXECUTED-STOP12_9566d4f4.sql")))
          == "9566d4f417307f353ea749e7364e9c2395a41f8019a02d5b70a6acba9217ea32"
      and "pg_policies p  -- E1E" not in s4_var and s4_var.count("pg_policies pol  -- E1E") == 5
      and not re.search(r"(?<![a-z0-9_.'%])p\.[a-z_]", nc(s4_var))
      and s4_var.replace("pol.", "p.").replace("pg_policies pol ", "pg_policies p ") == _s4_12
      and [r for r in _sc["scan"](os.path.join(HERE, "harness", "5863_validate_shared_binder_visual_assets_v1.2-E1E.sql"))
           if r[6] == "DEFEITO"] != []
      and not any(r[6] in ("DEFEITO", "REVISAR") for r in _rows),
      f"5863 v1.3-E1E: S.4 = v1.2 com alias pg_policies p→pol (sem colisão com a variável record p; critérios idênticos); "
      f"v1.2-E1E e G2_B MGMTAPI executado (STOP 12) preservados; varredura acusa a v1.2 e nenhum DEFEITO/REVISAR nos 4 ensaios ({len(_rows)} homônimos escalares/neutros)")

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

# 9. Variante de canal MGMTAPI do G2_A -----------------------------------------------------------
va = rd(os.path.join(HERE, VAR["A"])).decode()
vm = rd(os.path.join(HERE, "G2_A_E1A_PROTECTED_rollback_MGMTAPI.sql")).decode()
def _core(t):
    a = t.index("-- @@T2 ")
    b = t.find("-- @@T10")
    c = t.find("-- [MGMTAPI] T10")
    return t[a:(c if c >= 0 else (b if b >= 0 else len(t)))].rstrip()
def _top(t):
    t = re.sub(r"\$([a-z0-9_]*)\$.*?\$\1\$", "$$", t, flags=re.S)
    t = re.sub(r"'(?:[^']|'')*'", "''", t)
    t = re.sub(r"(?s)/\*.*?\*/", "", t)
    return re.sub(r"(?m)--.*$", "", t)
tm = _top(vm)
stm = [x.strip() for x in tm.split(";") if x.strip()]
# Diferença permitida no T6 (CORRECTION-03), re-derivada aqui de forma independente do gerador.
_A_OLD = ("  if pg_catalog.current_setting('default_transaction_read_only') <> 'on' then\n"
          "    raise exception 'G2 T6: T0 não vigora nesta sessão (pooler/troca de backend?) — RECUSAR';\n"
          "  end if;\n")
_A_NEW = "  -- [MGMTAPI] default_transaction_read_only não exigido: sem T0; transação implícita única (G2A-PROOF-01).\n"
_B_OLD = "  where e.evtenabled <> 'D' and p.prosrc ~* '(net\\.|http_|pg_net|dblink)';\n"
_B_NEW = ("  where e.evtenabled <> 'D' and p.prosrc ~* '(net\\.|http_|pg_net|dblink)'\n"
          "    -- [MGMTAPI] exceção única: gatilho padrão do Supabase, só em CREATE EXTENSION (o ensaio não cria extensão)\n"
          "    and (e.evtname = 'issue_pg_net_access' and e.evtevent = 'ddl_command_end'\n"
          "             and e.evttags = array['CREATE EXTENSION']::text[]\n"
          "             and p.proname = 'grant_pg_net_access'\n"
          "             and (select x.nspname from pg_catalog.pg_namespace x where x.oid = p.pronamespace) = 'extensions') is not true;\n")
_ca = _core(va)
check("9.1", _ca.count(_A_OLD) == 1 and _ca.count(_B_OLD) == 1
      and _ca.replace(_A_OLD, _A_NEW).replace(_B_OLD, _B_NEW) == _core(vm) and len(_core(vm)) > 100000,
      "MGMTAPI: T2–T9 idênticos ao G2_A exceto as 2 substituições autorizadas do T6 (limites, trava, NOWAIT, 6 migrations, 2 harnesses, postcheck e sentinela inalterados)")
check("9.2", not re.search(r"(?m)^\s*\\", vm)
      and not any(re.match(r"(?is)(begin|start\s+transaction|commit|end|rollback|savepoint|release|prepare\s+transaction|reset|set\s+session)\b", x) for x in stm)
      and all(re.match(r"(?is)(set\s+(local|transaction)|create\s+(or\s+replace\s+)?function)\b", x) or not re.search(r"(?im)^\s*set\s", x) for x in stm),
      "MGMTAPI: sem metacomando do psql, sem controle de transação explícito (BEGIN/COMMIT/ROLLBACK/SAVEPOINT/RESET/SET SESSION); SET só LOCAL/TRANSACTION ou atributo de função")
_p = [vm.find(x) for x in ("-- @@T4", "-- @@T6 lock", "-- @@T7", "-- @@T9 sentinela")]
check("9.3", min(_p) >= 0 and _p[0] < _p[1] < _p[2] < _p[3]
      and "deferrable initially deferred" in vm and _top(vm[_p[3]:]).strip().endswith("$$;")
      and "v_total = 105 and v_passes = 105" in vm and "txid_current_if_assigned()" in vm,
      "MGMTAPI: trava de COMMIT e NOWAIT antes do DDL; sentinela (105 verificações, 2 GATEs, txid) é a última instrução")

_t6 = vm[vm.index("-- @@T6 precheck"):vm.index("-- @@T6 lock")]
check("9.4", "default_transaction_read_only') <> 'on'" not in _t6
      and "current_setting('transaction_read_only') <> 'off'" in _t6
      and _t6.count("issue_pg_net_access") == 1 and "e.evttags = array['CREATE EXTENSION']::text[]" in _t6
      and "= 'extensions') is not true;" in _t6 and "and not (e.evtname" not in _t6
      and "p.prosrc ~* '(net\\.|http_|pg_net|dblink|pg_notify|notify\\s)'" in _t6
      and not re.search(r"(?i)\b(create|alter|drop)\s+extension\b", _top(vm)),
      "MGMTAPI: T6 sem exigência de default_transaction_read_only = on; READ WRITE exigido; exceção só para issue_pg_net_access com tag {CREATE EXTENSION}; gatilhos de tabela intactos; ensaio sem CREATE/ALTER/DROP EXTENSION")

# 9.5 Variantes MGMTAPI do G2_B e do G2_C (READINESS CORRECTION-01): mesma derivação do G2_A MGMTAPI (T6 ajustado)
#     e só a montagem de v_msg da sentinela trocada pela forma compacta; critério v_ok idêntico.
def _msg_split(core, marca):
    i = core.index(marca); j = core.index("::text;\n", i) + len("::text;\n")
    return core[:i], core[i:j], core[j:]
_ok95 = []
for _k, _f in (("B", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI.sql"), ("C", "G2_C_CHAIN_FULL_FINAL_rollback_MGMTAPI.sql")):
    _ps = _core(rd(os.path.join(HERE, VAR[_k])).decode()); _mg_t = rd(os.path.join(HERE, _f)).decode(); _mg = _core(_mg_t)
    _ps = _ps.replace(_A_OLD, _A_NEW).replace(_B_OLD, _B_NEW)
    _a1, _m1, _z1 = _msg_split(_ps, "  v_msg := 'MS_G2")
    _a2, _m2, _z2 = _msg_split(_mg, "  -- [MGMTAPI] mensagem compacta")
    _st = [x.strip() for x in _top(_mg_t).split(";") if x.strip()]
    _ok95.append(_a1 == _a2 and _z1 == _z2
                 and all(x in _m2 for x in ("'gates', v_gates", "'failed_count', jsonb_array_length(v_failed)", "'failed_truncated'", "'x1_count'",
                                             "txid_current_if_assigned()", "'trap_intact', v_trap", "'duration_ms', v_ms", "'total', v_total", "'passes', v_passes"))
                 and "v_fixture, 'trap_intact'" not in _m2
                 and not re.search(r"(?m)^\s*\\", _mg_t)
                 and not any(re.match(r"(?is)(begin|start\s+transaction|commit|end|rollback|savepoint|release|prepare\s+transaction|reset|set\s+session)\b", x) for x in _st)
                 and _mg_t.find("-- @@T4") < _mg_t.find("-- @@T6 lock") < _mg_t.find("-- @@T7")
                 and "LOCK TABLE storage.objects IN ACCESS EXCLUSIVE MODE NOWAIT;" in _mg_t
                 and _top(_mg_t[_mg_t.index("-- @@T9 sentinela"):]).strip().endswith("$$;"))
check("9.5", all(_ok95),
      "G2_B/G2_C MGMTAPI: iguais ao psql exceto moldura de canal, T6 (2 ajustes aprovados) e v_msg compacta; v_ok, 417 verificações, 12 GATEs, travas NOWAIT (inclusive storage.objects), trava de COMMIT e sentinela terminal preservados; sem metacomando nem controle de transação")
# 3.4 Correções de harness E1E da cadeia (5889 v1.4, 5890 v1.3, 5891 v1.2, 5892–5893 v1.3): originais preservados, delta só em linhas -- E1E,
#     mesmas verificações, sem GRANT/REVOKE/política, e nenhuma conferência de estado sob cliente não titular.
_cad = {"5889": ("2026-11-15-v1-13-e1b1-editor-core-binder/5889_validate_editor_core_binder_HARNESS.sql", "4982135d5b3f0b859a78755b1979342ef54032f563635fb7c76a152e38d0095d", "5889_validate_editor_core_binder_HARNESS_v1.4-E1E.sql"),
        "5890": ("2026-11-15-v1-13-e1b2-editor-curation/5890_validate_editor_curation_HARNESS.sql", "ae57e56a8cfba9608b7bf654bf5e9cfc45e6ebf9ed5125498e5acec225bc03ec", "5890_validate_editor_curation_HARNESS_v1.3-E1E.sql"),
        "5891": ("2026-11-15-v1-13-e1b3-pokedex-history/5891_validate_editor_pokedex_history_HARNESS.sql", "133d0cc534fdfc82976f016bac341a3045fab54ece4d6a337c96af188ff53a77", "5891_validate_editor_pokedex_history_HARNESS_v1.2-E1E.sql"),
        "5892": ("2026-11-15-v1-13-e1c-bulk-operations/5892_validate_editor_bulk_operations_HARNESS.sql", "a3169b24312f702745529170b2a3e684b09573132c74b3e5859039cd4d70bc7d", "5892_validate_editor_bulk_operations_HARNESS_v1.3-E1E.sql"),
        "5893": ("2026-11-15-v1-13-e1c2-remaining-bulk-operations/5893_validate_editor_remaining_bulk_operations_HARNESS.sql", "10619cd07d9a63369c640b59008004bc08863122c77627e913a0eec795d176a7", "5893_validate_editor_remaining_bulk_operations_HARNESS_v1.3-E1E.sql")}
_ok34 = []; _rest = []
for _n, (_po, _ho, _pc) in _cad.items():
    _bo = rd(os.path.join(PROP, _po)); _o = _bo.decode("utf-8"); _c = rd(os.path.join(HERE, "harness", _pc)).decode("utf-8")
    _hdr = _c.index("*/")
    _add = [l[1:] for l in _dl.unified_diff(_o.split("\n"), _c.split("\n"), lineterm="", n=0) if l.startswith("+") and not l.startswith("+++")]
    _body_add = [l for l in _add if l in _c[_hdr:]]
    _ok34.append(sha(_bo) == _ho and re.findall(r"'id','([^']+)'", _o) == re.findall(r"'id','([^']+)'", _c)
                 and all("E1E" in l for l in _body_add)
                 and not any(re.search(r"(?i)\b(grant|revoke|policy|row level|security definer|alter table)\b", l) for l in _body_add))
    _hl = {m.group(1): m.group(5) for m in re.finditer(r"create or replace function (pg_temp\.wh_\w+)\(([^)]*)\)(.*?)\$(\w*)\$(.*?)\$\4\$", _c, re.S)}
    _rh = [h for h, b in _hl.items() if "validate" not in h and not h.endswith(("_as", "_try")) and re.search(r"(from|join)\s+(public|storage)\.", b)]
    _L = _c.split("\n"); _u = "owner"
    for _i in range([i for i, l in enumerate(_L) if re.search(r"function pg_temp\.wh_\w*validate\(\)", l)][0] + 1, len(_L)):
        _cc = re.sub(r"--.*$", "", _L[_i])
        for _m in re.finditer(r"pg_temp\.wh_%s_as\(\s*([a-z_0-9]+)\s*\)" % _n, _cc): _u = _m.group(1)
        if "reset role" in _cc: _u = "owner"
        if _u in ("owner", "u_a"): continue
        if re.search(r"\b(from|join)\s+(public|storage)\.([a-z_0-9]+)\b(?!\s*\()", _cc) or any(h + "(" in _cc for h in _rh):
            _rest.append(f"{_n}:{_L[_i].strip()[:60]}")
# únicas leituras restantes sob cliente não titular: 5890 6.4 (EDITOR vê só os arquivos dele, sob RLS) e 6.9 (exclusão real pelo EDITOR)
check("3.4", all(_ok34) and len(_rest) == 2 and all(x.startswith("5890:") and "storage.objects" in x for x in _rest),
      f"5889 v1.4-E1E, 5890 v1.3-E1E, 5891 v1.2-E1E e 5892–5893 v1.3-E1E: originais preservados (sha256), delta só em linhas -- E1E, mesmas verificações, sem GRANT/REVOKE/política; sob cliente não titular só restam as leituras intencionais de storage.objects da 5890 6.4/6.9 ({len(_rest)})")


# 3.5 CONSOLIDATED HARNESS CORRECTION-01 (G2_B v2 LIVE FAIL, E2BNO, TXID 815477): C1 caminhos de imagem de bolso
#     canônicos (5889/5890/5892/5893), 10.2 com pré-condição de fixture (5889), C2 sem chamada à 5310 sob
#     authenticated (5894); versões anteriores e texto executado preservados; delta só em linhas -- E1E.
_E35 = os.path.join(HERE, "harness")
_prev = {"5889": ("5889_validate_editor_core_binder_HARNESS_v1.3-E1E.sql", "974fd0e1bd8858830922a59aa51c72adc797371a6dd8b0c97b157d941d5c7f4c", "5889_validate_editor_core_binder_HARNESS_v1.4-E1E.sql"),
         "5890": ("5890_validate_editor_curation_HARNESS_v1.2-E1E.sql", "3614debf43c356dbf22c1b27495e5d40454bc0671f1c1d37c2e97550eb9e2c69", "5890_validate_editor_curation_HARNESS_v1.3-E1E.sql"),
         "5892": ("5892_validate_editor_bulk_operations_HARNESS_v1.2-E1E.sql", "3773eaa2668c113617d14e9c13d99c04e67a02e563cd0baeb927027294b11ffc", "5892_validate_editor_bulk_operations_HARNESS_v1.3-E1E.sql"),
         "5893": ("5893_validate_editor_remaining_bulk_operations_HARNESS_v1.2-E1E.sql", "6142a77d8fe7f9ec27a8db409e5b053c2c3c7ecbac626199a4ff181535390495", "5893_validate_editor_remaining_bulk_operations_HARNESS_v1.3-E1E.sql"),
         "5894": (os.path.join(PROP, "2026-11-15-v1-13-e1d-shared-reads", "5894_validate_shared_reads_HARNESS.sql"), "db567e0b7bca3ab81169969fd113992c67fff3b5877ee3d99475f9add8e1b869", "5894_validate_shared_reads_HARNESS_v1.4-E1E.sql")}
_ok35 = {}
_new = {}
for _n, (_pf, _ph, _nf) in _prev.items():
    _pb = rd(_pf if os.path.isabs(_pf) else os.path.join(_E35, _pf)); _pt = _pb.decode("utf-8")
    _nt = rd(os.path.join(_E35, _nf)).decode("utf-8"); _new[_n] = _nt
    _h = _nt.index("*/")
    _ad = [l[1:] for l in _dl.unified_diff(_pt.split("\n"), _nt.split("\n"), lineterm="", n=0) if l.startswith("+") and not l.startswith("+++")]
    _ba = [l for l in _ad if l in _nt[_h:]]
    _ok35[_n] = (sha(_pb) == _ph and re.findall(r"'id','([^']+)'", _pt) == re.findall(r"'id','([^']+)'", _nt)
                 and _ba and all("-- E1E" in l for l in _ba)
                 and not any(re.search(r"(?i)\b(grant|revoke|policy|row level|security definer|alter table|create table)\b", l) for l in _ba))
# preservação do texto executado do G2_B v2 e do v1
_x35 = (sha(rd(os.path.join(HERE, "executed", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI_EXECUTED-V2-E2BNO_ba19c2f7.sql")))
        == "ba19c2f7aee0023ae51c5581d8f45ddd4ba5572f11907511ee76137582cef814"
        and sha(rd(os.path.join(HERE, "executed", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI_EXECUTED-STOP12_9566d4f4.sql")))
        == "9566d4f417307f353ea749e7364e9c2395a41f8019a02d5b70a6acba9217ea32")
# C1: os CHECKs reais da 5232 aplicados a um caminho de exemplo de cada forma usada nos ensaios
_s5232 = rd(os.path.join(PROP, "..", "schema", "5232_create_collection_layout_slot_image_table.sql")).decode()
_rx = re.search(r"chk_collection_layout_slot_image_path_format\s+check \(storage_path ~ '([^']+)'\)", _s5232).group(1)
import uuid as _uu
_ua, _ul, _ug = (str(_uu.uuid4()) for _ in range(3))
_canon = _ua + "/" + _ul + "/" + _ug + ".webp"
_c1sim = (re.fullmatch(_rx, _canon) is not None and _canon.split("/")[0] == _ua
          and all(re.fullmatch(_rx, _ua + "/" + _ul + f"/wh{n}.webp") is None for n in ("5889", "5890", "5892", "5893")))
_insert_pat = re.compile(r"insert into public\.collection_layout_(?:slot|region)_image \(([^)]*)\)\s*values \((.*?)\);", re.S)
_canon_inline = re.compile(r"^(\w+)::text \|\| '/' \|\| [\w.]+::text \|\| '/' \|\| gen_random_uuid\(\)::text \|\| '\.(webp|jpg)'$")
_c1rows = []
for _f in ("G2_B_CHAIN_STORAGE_LAST_rollback.sql", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI.sql",
           "G2_C_CHAIN_FULL_FINAL_rollback.sql", "G2_C_CHAIN_FULL_FINAL_rollback_MGMTAPI.sql"):
    _t = rd(os.path.join(HERE, _f)).decode()
    _h8 = _t[_t.index("-- @@T8 harness"):_t.index("-- @@T9 postcheck")]
    for _m in _insert_pat.finditer(_h8):
        _cols = [c.strip() for c in _m.group(1).split(",")]
        _vals = []; _d = 0; _cur = ""
        for ch in nc(_m.group(2)):
            if ch == "(": _d += 1
            if ch == ")": _d -= 1
            if ch == "," and _d == 0: _vals.append(_cur.strip()); _cur = ""
            else: _cur += ch
        _vals.append(_cur.strip())
        _sp = _vals[_cols.index("storage_path")]; _ow = _vals[_cols.index("owner_user_id")]
        _mi = _canon_inline.match(_sp)
        if _mi: _ok = _mi.group(1) == _ow
        else:
            _ma = re.search(r"\b%s\s*:=\s*(\w+) \|\| '/' \|\| \w+ \|\| '/' \|\| gen_random_uuid\(\) \|\| '\.webp';" % re.escape(_sp), _h8)
            _ok = bool(re.fullmatch(r"\w+", _sp)) and bool(_ma) and _ma.group(1) == _ow
        _c1rows.append((_f, _ok))
_c1 = (_c1sim and len(_c1rows) == 4 * 7 and all(o for _, o in _c1rows)
       and not any(re.search(r"/wh58\d\d\.webp", rd(os.path.join(HERE, f)).decode()) for f in VAR.values()))
check("3.5a", _c1 and all(_ok35[n] for n in ("5889", "5890", "5892", "5893")) and _x35,
      f"C1: as {len(_c1rows) // 4} inserções de imagem de bolso/região de cada ensaio G2_B/G2_C usam <dono>/<uuid>/<uuid>.webp com dono = owner_user_id "
      f"(regex real de chk_collection_layout_slot_image_path_format aceita o canônico e recusa 'wh589N.webp'); 5889 v1.4, 5890/5892/5893 v1.3: "
      f"anteriores preservadas, delta só em linhas -- E1E, mesmas verificações; textos executados v1 e v2 preservados")
# 10.2: pré-condição de fixture conjuntiva, avaliada no contexto do dono; slotp devolve NULL sem a página
_t89 = _new["5889"]
_q102 = _t89[_t89.index("res := res || jsonb_build_object('id','10.2'"):]; _q102 = _q102[:_q102.index("'detail',")]
_pre102 = _t89[_t89.rindex("\n", 0, _t89.index("res := res || jsonb_build_object('id','10.2'")) - 120:_t89.index("res := res || jsonb_build_object('id','10.2'")]
_slotp = re.search(r"function pg_temp\.wh_5889_slotp\(.*?\$sp\$(.*?)\$sp\$", _t89, re.S).group(1)
_f101 = _t89[_t89.index("-- 10. Estados compostos"):_t89.index("res := res || jsonb_build_object('id','10.1'")]
check("3.5b", "and exists (select 1 from public.collection_layout_slot_image ximg" in _q102
      and "ximg.slot_id = pg_temp.wh_5889_slotp(v_layout, 2, 1, 1))" in _q102
      and "xpg.layout_id = v_layout and xpg.page_number = 2 and xreg.top_row = 2 and xreg.left_column = 1" in _q102
      and "xreg.height = 1 and xreg.width = 2)" in _q102 and " or " not in nc(_q102)
      and "execute 'reset role'" in _pre102
      and re.search(r"p\.page_number = p_page", _slotp) and "join public.collection_layout_page" in _slotp
      and "pg_temp.wh_5889_slotp(v_layout, 2, 1, 1), u_a," in _f101 and "2, 1, 1, 2);" in _f101,
      "5889 10.2: exige, em conjunção e no contexto do dono, a imagem em 2:1:1 e a mesclagem r2c1–r2c2 da página 2 que a 10.1 cria; "
      "sem a página 2, wh_5889_slotp devolve NULL e o EXISTS é falso — o PASS do G2_B v2 (página ausente) não se repete")
# C2: 5894 3.4 sem a 5310; leitura pública 5312 da mesma coleção, sob o EDITOR; critérios n/n2 intactos; 5310 continua sem EXECUTE
_t94 = _new["5894"]; _t94o = rd(_prev["5894"][0]).decode()
_b34 = _t94[_t94.index("res := res || jsonb_build_object('id','3.3'"):_t94.index("res := res || jsonb_build_object('id','4.1'")]
_b34o = _t94o[_t94o.index("res := res || jsonb_build_object('id','3.3'"):_t94o.index("res := res || jsonb_build_object('id','4.1'")]
_crit = lambda b: b[b.index("res := res || jsonb_build_object('id','3.4'"):b.index("'detail',", b.index("'id','3.4'"))]
_s68 = rd(os.path.join(PROP, "2026-11-14-v1-13-e1a-editor-role", "5368_expose_member_role_in_sharing_reads.sql")).decode()
_g68 = _s68[_s68.index("CREATE OR REPLACE FUNCTION public.get_shared_collection(p_collection_id UUID)"):]
_g68 = _g68[:_g68.index("GRANT EXECUTE ON FUNCTION public.get_shared_collection(uuid) TO authenticated;") + 10]
_s10 = rd(os.path.join(PROP, "..", "schema", "5310_create_collection_completion_summary_shared_function.sql")).decode()
_harn_calls = [h for f in VAR.values() for h in re.findall(r"-- @@T8 harness (\d+)[^\n]*\n(?:(?!-- @@T).*\n)*?.*collection_completion_summary_shared\(c\.id\)", rd(os.path.join(HERE, f)).decode())]
check("3.5c", _ok35["5894"] and "collection_completion_summary_shared" not in nc(_t94)
      and re.search(r"perform pg_temp\.wh_5894_as\(u_b\);\s*v_j := public\.get_shared_collection\(v_cm\);", _b34)
      and "v_j := public.get_shared_collection(v_cd);" in _b34
      and "(v_j ->> 'satisfied_positions')::bigint = (select count(*) filter (where x.is_satisfied) from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x)" in _b34
      and "(v_j ->> 'total_positions')::bigint = (select max(x.total_count) from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x)" in _b34
      and "(v_j ->> 'satisfied_positions')::bigint = (select count(*) filter (where x.is_satisfied) from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x)" in _b34
      and "(v_j ->> 'total_positions')::bigint = (select max(x.total_count) from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x)" in _b34
      and _crit(_b34) == _crit(_b34o)
      and "'total_positions', s.total_positions," in _g68 and "'satisfied_positions', s.satisfied_positions," in _g68
      and "LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true" in _g68 and "WHERE c.id = p_collection_id;" in _g68
      and "v_role NOT IN ('OWNER', 'VIEWER')" in _g68
      and "total_positions BIGINT" in _s10 and "satisfied_positions BIGINT" in _s10
      and "REVOKE ALL ON FUNCTION public.collection_completion_summary_shared(UUID) FROM PUBLIC, anon, authenticated;" in _s10
      and not re.search(r"(?i)grant[^;]*collection_completion_summary_shared", "".join(rd(os.path.join(HERE, f)).decode() for f in VAR.values())),
      "5894 3.4: sem chamada à 5310; o EDITOR lê satisfied/total pela 5312 (mesma 5310, mesma coleção, BIGINT), comparados às grades 5323/5324; "
      "critério final (v_ok, n, n2) idêntico; 5310 continua sem EXECUTE para authenticated e nenhum GRANT nos ensaios")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<8} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
