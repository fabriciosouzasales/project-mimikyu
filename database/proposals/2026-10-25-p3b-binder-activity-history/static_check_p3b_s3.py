#!/usr/bin/env python3
"""Verificação estática da P3-B S3 (5275–5278): instrumentação de E08–E10.

Não conecta em banco. Prova:
  · diff mínimo — tirando as linhas marcadas "-- P3B-S3" e voltando o delimitador
    $fn$ → $$, cada função instrumentada é byte a byte a canônica (md5 do corpo = LIVE);
  · cabeçalho (assinatura, retorno, linguagem, SET) idêntico ao canônico;
  · contrato W3 (README §20, I-1..I-6) pelo mesmo verificador da S1;
  · helper 5275 interno e sem acesso de cliente;
  · tipos de evento e efeitos dentro dos CHECKs da 5267;
  · as verificações da S1 e da S2 continuam PASS.

Uso: python3 static_check_p3b_s3.py   (a partir desta pasta). Código de saída 0 = PASS.
"""
import contextlib
import hashlib
import importlib.util
import io
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parents[1] / "schema"
MARK = "-- P3B-S3"
S3 = {
    "5276_instrument_set_slot_expected_content.sql":
        ("5229_create_collection_binder_sharing.sql", "set_slot_expected_content", "56a9aa74307e3708b34c014f471a4cd6", {"POCKET_RESERVED"}),
    "5277_instrument_clear_slot_expected_content.sql":
        ("5129_create_clear_slot_expected_content_function.sql", "clear_slot_expected_content", "d4e229d6db9196bf8caa738b5ba2e8b0", {"RESERVATIONS_RELEASED"}),
    "5278_instrument_set_slot_lock.sql":
        ("5130_create_set_slot_lock_function.sql", "set_slot_lock", "782a551d7c3af03e74a56020802432d5", {"POCKETS_LOCKED", "POCKETS_UNLOCKED"}),
}
HELPER = "5275_create_binder_activity_add_reservation_item.sql"

results = []


def check(cid, ok, detail):
    results.append((cid, bool(ok), detail))


def strip_comments(sql):
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def ddl_of(text, fn):
    m = re.search(r"(?is)(create (?:or replace )?function public\." + fn + r"\(.*?\$(fn)?\$;)", text)
    return m.group(1) if m else None


def body_and_head(ddl):
    m = re.search(r"(?is)^(.*?\bas\s+)(\$[a-z_]*\$)(.*?)\2;$", ddl)
    return m.group(1), m.group(3)


def unmark(ddl):
    lines = [l for l in ddl.split("\n") if MARK not in l]
    return "\n".join(lines).replace("$fn$", "$$")


# carrega o verificador W3 da S1 (o arquivo roda as próprias checagens e chama sys.exit)
_spec = importlib.util.spec_from_file_location("s1", HERE / "static_check_p3b_s1.py")
_s1 = importlib.util.module_from_spec(_spec)
_buf = io.StringIO()
with contextlib.redirect_stdout(_buf):
    try:
        _spec.loader.exec_module(_s1)
    except SystemExit:
        pass
w3_violations = _s1.w3_violations

s1_text = (HERE / "5267_create_binder_activity_structures.sql").read_text(encoding="utf-8")
EVENT_TYPES = set(re.findall(r"'([A-Z_]+)',?\s*--\s*(?:E\d|L01)", s1_text))
EFFECTS = set(re.findall(r"'([A-Z_]+)'", re.search(r"chk_bai_effect check \(effect in \((.*?)\)\)", s1_text, re.S).group(1)))

instrumented_bodies = {}
for f, (canon, fn, md5, evtypes) in S3.items():
    t = (HERE / f).read_text(encoding="utf-8")
    c = strip_comments(t)
    tags = re.findall(r"\$[a-z_]*\$", c)
    check("S3.1/" + f[:4], c.strip().lower().startswith("begin;") and c.strip().lower().endswith("commit;") and len(tags) % 2 == 0,
          "begin;…commit; e delimitadores $…$ pareados")
    ddl = ddl_of(t, fn)
    cddl = ddl_of((SCHEMA / canon).read_text(encoding="utf-8"), fn)
    head, body = body_and_head(ddl)
    uhead, ubody = body_and_head(unmark(ddl))
    chead, cbody = body_and_head(cddl)
    instrumented_bodies[fn] = body
    check("S3.2/" + f[:4], hashlib.md5(ubody.encode()).hexdigest() == md5 == hashlib.md5(cbody.encode()).hexdigest(),
          f"diff mínimo: sem as linhas P3B-S3 o corpo de {fn} tem o md5 do canônico/LIVE ({md5[:8]}…)")
    norm = lambda h: re.sub(r"(?i)^create (or replace )?function", "create function", re.sub(r"\s+", " ", h.strip()))
    check("S3.3/" + f[:4], norm(uhead) == norm(chead) and re.match(r"(?i)create or replace function", ddl),
          "cabeçalho (assinatura, retorno, linguagem, SECURITY, SET) idêntico ao canônico; CREATE OR REPLACE")
    v = w3_violations(body)
    check("S3.4/" + f[:4], not v, "W3 I-1..I-6 sem violações" + (f" {v}" if v else ""))
    beg = " ".join(l for l in body.split("\n") if "binder_activity_begin" in l)
    used_ev = set(re.findall(r"'([A-Z_]+)'", beg)) - {"FICHARIO"}
    used_ef = set(re.findall(r"binder_activity_add_reservation_item\(\s*'([A-Z_]+)'", body)) | \
              set(re.findall(r"(?:THEN|ELSE)\s+'([A-Z_]+)'", " ".join(l for l in body.split("\n") if "binder_activity_add_item(" in l)))
    check("S3.5/" + f[:4], used_ev == evtypes and used_ev <= EVENT_TYPES and used_ef and used_ef <= EFFECTS,
          f"tipos {sorted(used_ev)} e efeitos {sorted(used_ef)} dentro dos CHECKs da 5267")
    # grants originais reaplicados
    cg = [x for x in re.findall(r"(?im)^\s*(?:revoke|grant)\b.*?;", (SCHEMA / canon).read_text(encoding="utf-8"), flags=re.S)
          if re.search(r"public\." + fn + r"\(", x)]  # a base 5229 contém outras funções
    sg = re.findall(r"(?im)^\s*(?:revoke|grant)\b.*?;", t, flags=re.S)
    check("S3.6/" + f[:4], [re.sub(r"\s+", " ", x) for x in cg] == [re.sub(r"\s+", " ", x) for x in sg],
          "REVOKE/GRANT idênticos aos do canônico (ACL preservado)")
    check("S3.7/" + f[:4], f"is distinct from '{md5}'" in t and ("binder_activity_add_reservation_item(text, uuid)" in t
          or "binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)" in t),
          "precheck: recusa se a função LIVE divergir da base (md5) ou se a gravação (5268/5275) faltar")
    lines = body.split("\n")
    bi = next(i for i, l in enumerate(lines) if "binder_activity_begin" in l)
    adds = [i for i, l in enumerate(lines) if re.search(r"binder_activity_add_(reservation_)?item\(", l)]
    ends = [i for i, l in enumerate(lines) if "binder_activity_end" in l]
    check("S3.8/" + f[:4], adds and all(bi < a < max(ends) for a in adds) and all(MARK in lines[i] for i in adds + ends + [bi]),
          "add_*item entre begin e end, todas as chamadas marcadas P3B-S3")

# helper
ht = (HERE / HELPER).read_text(encoding="utf-8")
hc = strip_comments(ht)
check("S3.9", re.search(r"create function public\.binder_activity_add_reservation_item", hc)
      and "security definer" in hc and "set search_path = ''" in hc
      and re.search(r"revoke all on function public\.binder_activity_add_reservation_item\(text, uuid\) from public, anon, authenticated, service_role", hc)
      and not re.search(r"grant\s+execute", hc, re.I)
      and not re.search(r"binder_activity_(begin|end)\s*\(", hc)
      and not re.search(r"insert\s+into\s+public\.binder_activity_", hc, re.I)
      and "mmkyu.binder_activity_ctx" not in hc
      and "perform public.binder_activity_add_item('RESERVATION', p_effect" in hc,
      "5275 interna: DEFINER, search_path vazio, sem EXECUTE de cliente; não abre/fecha operação nem grava direto; delega à 5268")

# mutações: o verificador pega regressões típicas da S3
mut = {
    "end removido (reserva)": instrumented_bodies["set_slot_expected_content"].replace("  perform public.binder_activity_end();  -- P3B-S3\n", ""),
    "end antes do RETURN ausente (liberar)": instrumented_bodies["clear_slot_expected_content"].replace("    PERFORM public.binder_activity_end();  -- P3B-S3\n", ""),
    "begin duplicado (fixar)": instrumented_bodies["set_slot_lock"].replace("    FOR r IN  -- P3B-S3", "    PERFORM public.binder_activity_begin(v_layout_id, 'POCKETS_LOCKED', 'FICHARIO');\n    FOR r IN  -- P3B-S3"),
    "insert direto (fixar)": instrumented_bodies["set_slot_lock"].replace("    END LOOP;  -- P3B-S3", "    END LOOP;  -- P3B-S3\n    INSERT INTO public.binder_activity_item (event_id) VALUES (1);"),
}
for k, b in mut.items():
    check("S3.10/NEG", bool(w3_violations(b)), f"mutação detectada — {k}")

# a S1 e a S2 continuam íntegras
for chk in ("static_check_p3b_s1.py", "static_check_p3b_s2.py"):
    p = subprocess.run([sys.executable, str(HERE / chk)], capture_output=True, text=True, cwd=HERE)
    gate = [l for l in p.stdout.splitlines() if l.startswith("GATE")]
    check("S3.11", p.returncode == 0, chk + ": " + (gate[0].split(None, 1)[1].strip() if gate else "sem GATE"))

width = max(len(c) for c, _, _ in results)
fails = 0
for cid, ok, detail in results:
    fails += 0 if ok else 1
    print(f"{cid:<{width}}  {'PASS' if ok else 'FAIL'}  {detail}")
print(f"{'GATE':<{width}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
sys.exit(0 if fails == 0 else 1)
