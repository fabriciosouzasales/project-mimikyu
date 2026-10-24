"""
BINDER-PHYSICAL-LOCATION — verificação estática da proposta 5247–5256 + 5854 + R1/R2 (v2.0, READINESS).

Não conecta em banco algum. Uso (na raiz do repositório):
    python -I database/proposals/2026-10-24-binder-physical-location/static_check_binder_physical_location.py

Verifica:
  S1  cada migration: BEGIN/COMMIT únicos, delimitadores $tag$ balanceados,
      status "NÃO EXECUTADA";
  S2  toda função criada é SECURITY DEFINER com search_path vazio (exceto
      o harness, que é pg_temp) e tem REVOKE de PUBLIC/anon; RPCs têm
      GRANT a authenticated; funções de gatilho NÃO têm GRANT;
  S3  nenhum service_role, nenhum "grant ... to anon", nenhum DROP TABLE;
  S4  5251 = canônica 5224 (collection_binder_plan) exceto os 2 patches
      documentados (filtro de local físico + versão v2);
  S5  5252/5253: diffs contra as canônicas 5230/5246/5229 são reportados
      (tamanho) e os marcadores obrigatórios de cada patch existem;
  S6  harness 5854: sentinela, v_expected = nº de ids distintos, sem COMMIT,
      resíduo zero (99.1) presente, "NUNCA executar no LIVE".
Saída: uma linha PASS/FAIL por item e GATE final; código de saída 1 se FAIL.
"""
import difflib
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parents[1] / "schema"
results = []


def check(cid, ok, detail):
    results.append((cid, bool(ok), detail))


def read(p):
    return p.read_text(encoding="utf-8")


def strip_comments(sql):
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def function_body(text, name):
    m = re.search(
        r"^create (?:or replace )?function public\." + re.escape(name) + r"\(.*?^\$\$;\n",
        text, re.S | re.M | re.I)
    return m.group(0) if m else None


def norm_lines(body):
    out = []
    for line in strip_comments(body).splitlines():
        line = line.rstrip()
        if line.strip():
            out.append(line)
    return out


def head_neutral(lines):
    """Ignora 'create'/'create or replace' na 1ª linha."""
    if lines:
        lines = [re.sub(r"^create (or replace )?function", "create function", lines[0], flags=re.I)] + lines[1:]
    return lines


def diff(a, b):
    d = [l for l in difflib.unified_diff(head_neutral(a), head_neutral(b), lineterm="", n=0)
         if (l.startswith("+") or l.startswith("-")) and not l.startswith(("+++", "---"))]
    return d


migrations = sorted(HERE.glob("52[45][0-9]_*.sql"))
check("S0", [p.name[:4] for p in migrations] == [str(n) for n in range(5247, 5257)],
      "10 migrations 5247…5256: " + ", ".join(p.name[:4] for p in migrations))

# S1 / S2 / S3 ---------------------------------------------------------------------------
for p in migrations:
    raw = read(p)
    code = strip_comments(raw)
    n_begin = len(re.findall(r"^\s*begin;\s*$", code, re.M | re.I))
    n_commit = len(re.findall(r"^\s*commit;\s*$", code, re.M | re.I))
    tags = re.findall(r"\$([a-z_]*)\$", code)
    balanced = all(tags.count(t) % 2 == 0 for t in set(tags))
    check(f"S1.{p.name[:4]}", n_begin == 1 and n_commit == 1 and balanced and "NÃO EXECUTADA" in raw,
          f"BEGIN={n_begin} COMMIT={n_commit} $tags balanceadas={balanced} status NÃO EXECUTADA={'NÃO EXECUTADA' in raw}")

    problems = []
    for m in re.finditer(r"create (?:or replace )?function (public\.[a-z_0-9]+)\(", code, re.I):
        fname = m.group(1)
        start = m.start()
        end = code.find("$$;", start)
        header = code[start:code.find("as $$", start)]
        is_trigger = "returns trigger" in header.lower()
        short = fname.split(".")[1]
        revoked = " ".join(m2.group(1).lower() for m2 in re.finditer(
            r"revoke (?:all|execute) on function public\." + short + r"\([^)]*\) from ([^;]+);", code, re.I))
        grant = re.search(r"grant execute on function public\." + short + r"\(", code, re.I)
        internal = (not grant) and "authenticated" in revoked
        if "security definer" not in header.lower() and not (internal and "security invoker" in header.lower()):
            problems.append(f"{fname}: sem SECURITY DEFINER (e não é helper interno revogado)")
        if "set search_path = ''" not in header:
            problems.append(f"{fname}: search_path não vazio")
        if "public" not in revoked:
            problems.append(f"{fname}: sem REVOKE de PUBLIC")
        if not is_trigger and "anon" not in revoked:
            problems.append(f"{fname}: sem REVOKE de anon")
        if is_trigger and grant:
            problems.append(f"{fname}: função de gatilho com GRANT")
        if not is_trigger and not internal and not grant:
            problems.append(f"{fname}: RPC sem GRANT a authenticated")
    check(f"S2.{p.name[:4]}", not problems, "funções: definer/search_path/REVOKE/GRANT ok" if not problems else "; ".join(problems))

    bad = []
    if re.search(r"grant [^;]*\bservice_role\b", code, re.I):
        bad.append("grant a service_role")
    if re.search(r"grant [^;]* to [^;]*\banon\b", code, re.I):
        bad.append("grant a anon")
    if re.search(r"drop table", code, re.I):
        bad.append("drop table")
    check(f"S3.{p.name[:4]}", not bad, "sem grant a service_role/anon, sem drop table" if not bad else ", ".join(bad))

# S4: 5251 vs canônica 5224 ------------------------------------------------------------------
canon = function_body(read(next(SCHEMA.glob("5224_*.sql"))), "collection_binder_plan")
prop = function_body(read(next(HERE.glob("5251_*.sql"))), "collection_binder_plan")
if canon and prop:
    d = diff(norm_lines(canon), norm_lines(prop))
    plus = [l[1:].strip() for l in d if l.startswith("+")]
    minus = [l[1:].strip() for l in d if l.startswith("-")]
    ok = (len(minus) == 1 and "p2a1-plan-v1" in minus[0]
          and any("p2a1-plan-v2" in l for l in plus)
          and any("storage_container_id is not distinct from" in l for l in plus)
          and all(("p2a1-plan-v2" in l) or ("storage_container_id" in l) or ("default_storage_container_id" in l)
                  or l in (")", "and", "") or l.startswith(("(select", "from public.collection", "where c0."))
                  for l in plus))
    check("S4", ok, f"5251 × 5224: -{len(minus)} +{len(plus)} linhas; só versão v2 e filtro de local físico"
          if ok else "diff inesperado: " + " | ".join(d[:12]))
else:
    check("S4", False, "não encontrei collection_binder_plan em 5224 e/ou 5251")

# S4b: 5249 organize (6 args) = canônica 5222 + patches documentados ---------------------------
canon = function_body(read(next(SCHEMA.glob("5222_*.sql"))), "organize_my_collection_storage")
prop = function_body(read(next(HERE.glob("5249_*.sql"))), "organize_my_collection_storage")
if canon and prop:
    d = diff(norm_lines(canon), norm_lines(prop))
    minus = [l[1:].strip() for l in d if l.startswith("-")]
    plus = "\n".join(l[1:] for l in d if l.startswith("+"))
    ok = (all(m in ("p_plan_token           text", "or p_plan_token is null or p_plan_token !~ '^v1:[0-9a-f]{32}$' then") for m in minus)
          and "p_unplace_from_binder  boolean" in plus and "BINDER_POSITION_LOCKED" in plus
          and "BINDER_POSITION_CONFIRMATION_REQUIRED" in plus and "for update nowait" in plus
          and "delete from public.collection_layout_slot_assignment" in plus)
    check("S4b", ok, f"5249 organize × 5222: -{len(minus)} linhas (só assinatura/forma), bloco 6b presente" if ok else "diff inesperado: " + " | ".join(d[:10]))
else:
    check("S4b", False, "organize não encontrada em 5222 e/ou 5249")

# S8: compatibilidade — sobrecargas novas sem DEFAULT (nunca ambíguas com as antigas) ------------
nodefault = []
for qn, fname in (("5249", "set_physical_cards_storage"), ("5249", "organize_my_collection_storage"), ("5252", "get_my_collection_binder_unplaced")):
    b = function_body(read(next(HERE.glob(qn + "_*.sql"))), fname) or ""
    head = strip_comments(b[: b.find("returns")])
    if re.search(r"\bdefault\b", head, re.I):
        nodefault.append(f"{fname} tem DEFAULT")
code52 = strip_comments(read(next(HERE.glob("5252_*.sql"))))
if re.search(r"drop function public\.get_my_collection_binder_unplaced\(uuid, integer, integer\)", code52, re.I):
    nodefault.append("5252 remove a leitura antiga (deveria ficar até a 5256)")
code49 = strip_comments(read(next(HERE.glob("5249_*.sql"))))
if re.search(r"drop function|create trigger|set_config", code49, re.I):
    nodefault.append("5249 com DROP/gatilho/set_config (fase A deve ser só aditiva)")
code56 = strip_comments(read(next(HERE.glob("5256_*.sql"))))
if re.search(r"set_config|current_setting", code56, re.I):
    nodefault.append("5256 com configuração de sessão (bypass)")
check("S8", not nodefault, "fase A aditiva; sobrecargas sem DEFAULT; leitura antiga só sai na 5256; guarda sem bypass" if not nodefault else "; ".join(nodefault))

# S5: 5252/5253 — tamanho do diff + marcadores ------------------------------------------------
pairs = [
    ("5252", "get_my_collection_binder", "5230_*.sql",
     ["binder_storage_container_id", "available_count", "pc.storage_container_id"]),
    ("5252", "get_my_collection_binder_pages", "5230_*.sql",
     ["a.physical_card_id", "present_collection_name", "present_collection_lifecycle"]),
    ("5252", "get_my_collection_binder_unplaced", "5230_*.sql",
     ["p_origin", "'NO_COLLECTION'", "pc.storage_container_id = v_container", "origin_lifecycle_status", "p_origin_collection_id is null or ca.collection_id = p_origin_collection_id"]),
    ("5252", "get_my_binder_participants", "5246_*.sql", ["physical_card_id"]),
    ("5253", "collection_binder_detach_snapshot", "5229_*.sql", ["where false"]),
    ("5253", "detach_my_collection_from_binder", "5229_*.sql", ["v_asg := 0"]),
    ("5255", "attach_my_collection_to_binder", "5229_*.sql", ["select l.storage_container_id from public.collection_layout l where l.id = p_layout_id"]),
    ("5255", "list_my_binder_join_candidates", "5230_*.sql", ["and l.storage_container_id = v_default"]),
]
for qn, fname, cglob, markers in pairs:
    c = function_body(read(next(SCHEMA.glob(cglob))), fname)
    pr = function_body(read(next(HERE.glob(qn + "_*.sql"))), fname)
    if not (c and pr):
        check(f"S5.{fname}", False, f"{fname}: corpo não encontrado ({cglob} / {qn})")
        continue
    d = diff(norm_lines(c), norm_lines(pr))
    miss = [mk for mk in markers if mk not in pr]
    check(f"S5.{fname}", not miss,
          f"{qn} × {cglob[:4]}: -{sum(l.startswith('-') for l in d)} +{sum(l.startswith('+') for l in d)} linhas; marcadores "
          + ("ok" if not miss else "ausentes: " + ", ".join(miss)))

# S7: R1/R2 restauram corpos canônicos byte a byte (normalizado) -------------------------------
restore = [
    ("R1", "get_my_collection_binder_unplaced", "5230_*.sql"),
    ("R2A", "attach_my_collection_to_binder", "5229_*.sql"),
    ("R2A", "list_my_binder_join_candidates", "5230_*.sql"),
    ("R2A", "enforce_collection_layout_structural_fk_immutability", "5136_*.sql"),
    ("R2A", "collection_binder_detach_snapshot", "5229_*.sql"),
    ("R2A", "detach_my_collection_from_binder", "5229_*.sql"),
    ("R2B", "get_my_collection_binder", "5230_*.sql"),
    ("R2B", "get_my_collection_binder_pages", "5230_*.sql"),
    ("R2B", "get_my_binder_participants", "5246_*.sql"),
    ("R2B", "collection_binder_plan", "5224_*.sql"),
    ("R2B", "enforce_collection_layout_slot_assignment_integrity", "5229_*.sql"),
    ("R2B", "enforce_collection_layout_slot_lock", "5118_*.sql"),
]
bad = []
for rf, fname, cglob in restore:
    ctext = read(next(SCHEMA.glob(cglob)))
    cands = list(re.finditer(r"^create (?:or replace )?function public\." + re.escape(fname) + r"\(.*?^\$\$;\n", ctext, re.S | re.M | re.I))
    rb = function_body(read(next(HERE.glob(rf + "_*.sql"))), fname)
    if not cands or not rb or diff(norm_lines(cands[-1].group(0)), norm_lines(rb)):
        bad.append(f"{rf}:{fname}")
for rf in ("R1", "R2A", "R2B"):
    raw = read(next(HERE.glob(rf + "_*.sql")))
    code = strip_comments(raw)
    if len(re.findall(r"^\s*begin;\s*$", code, re.M | re.I)) != 1 or len(re.findall(r"^\s*commit;\s*$", code, re.M | re.I)) != 1 or "NÃO EXECUTADA" not in raw:
        bad.append(f"{rf}: BEGIN/COMMIT/status")
    # fora dos corpos de função restaurados (a 5229 canônica apaga posições ao desassociar — é o
    # comportamento antigo restaurado, não uma ação do script)
    outside = re.sub(r"\$\$.*?\$\$", "", code, flags=re.S)
    if re.search(r"delete from public\.collection_layout_slot_assignment", outside, re.I):
        bad.append(f"{rf}: apaga posição")
r0 = strip_comments(read(next(HERE.glob("R0_*.sql"))))
if re.search(r"\b(insert|update|delete|alter|drop|create|truncate|grant|revoke)\b", r0, re.I):
    bad.append("R0 não é só leitura")
r2a = strip_comments(read(next(HERE.glob("R2A_*.sql"))))
if re.search(r"alter table|drop column|collection_binder_plan|get_my_collection_binder_pages", r2a, re.I):
    bad.append("R2A toca o modelo de dados (deveria ser só contratos)")
check("S7", not bad, f"R1/R2A/R2B: {len(restore)} corpos idênticos às canônicas; BEGIN/COMMIT únicos; nenhuma posição apagada" if not bad else "; ".join(bad))

# S6: harness --------------------------------------------------------------------------------
h = read(next(HERE.glob("5854_*.sql")))
ids = set(re.findall(r"jsonb_build_object\('id','((?:\d+|F)\.\d+)'", h))
exp = re.search(r"v_expected integer := (\d+);", h)
code_h = strip_comments(h)
check("S6", exp and int(exp.group(1)) == len(ids) and "'MS854'" in h and "99.1" in ids
      and not re.search(r"^\s*commit;", code_h, re.M | re.I) and "NUNCA executar no LIVE" in h
      and "create or replace function pg_temp.wh_5854_validate()" in h,
      f"harness: {len(ids)} ids distintos, v_expected={exp.group(1) if exp else '?'}, sentinela MS854, sem COMMIT, aviso LIVE")

fails = [r for r in results if not r[1]]
for cid, ok, detail in results:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<42} {detail}")
print(f"GATE  {'PASS' if not fails else 'FAIL'}  {len(results) - len(fails)}/{len(results)}")
sys.exit(1 if fails else 0)
