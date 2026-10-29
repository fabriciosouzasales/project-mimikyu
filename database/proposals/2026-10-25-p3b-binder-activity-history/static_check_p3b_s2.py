#!/usr/bin/env python3
"""Verificação estática da P3-B S2 (5271–5274): instrumentação de E02–E05.

Não conecta em banco. Prova:
  · diff mínimo — tirando as linhas marcadas "-- P3B-S2" e voltando o delimitador
    $fn$ → $$, cada função instrumentada é byte a byte a canônica (md5 do corpo = LIVE);
  · cabeçalho (assinatura, retorno, linguagem, SET) idêntico ao canônico;
  · contrato W3 (README §20, I-1..I-6) pelo mesmo verificador da S1;
  · helper 5271 interno e sem acesso de cliente;
  · tipos de evento e efeitos dentro dos CHECKs da 5267;
  · a verificação da S1 continua PASS.

Uso: python3 static_check_p3b_s2.py   (a partir desta pasta). Código de saída 0 = PASS.
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
MARK = "-- P3B-S2"
S2 = {
    "5272_instrument_place_my_physical_card_in_slot.sql":
        ("5250_create_place_my_physical_card_in_slot.sql", "place_my_physical_card_in_slot", "caecf1bd88d9955dcfe409fb85a3effd", {"CARD_PLACED"}),
    "5273_instrument_move_slot_assignment.sql":
        ("5132_create_move_slot_assignment_function.sql", "move_slot_assignment", "4e71adc22e4ee9c88e1fa21a0ddf4738", {"CARD_MOVED", "CARDS_SWAPPED"}),
    "5274_instrument_remove_slot_assignment.sql":
        ("5133_create_remove_slot_assignment_function.sql", "remove_slot_assignment", "6bf6a90e00238ee59f8014503d96beaa", {"CARDS_REMOVED"}),
}
HELPER = "5271_create_binder_activity_add_card_item.sql"

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
for f, (canon, fn, md5, evtypes) in S2.items():
    t = (HERE / f).read_text(encoding="utf-8")
    c = strip_comments(t)
    tags = re.findall(r"\$[a-z_]*\$", c)
    check("S2.1/" + f[:4], c.strip().lower().startswith("begin;") and c.strip().lower().endswith("commit;") and len(tags) % 2 == 0,
          "begin;…commit; e delimitadores $…$ pareados")
    ddl = ddl_of(t, fn)
    cddl = ddl_of((SCHEMA / canon).read_text(encoding="utf-8"), fn)
    head, body = body_and_head(ddl)
    uhead, ubody = body_and_head(unmark(ddl))
    chead, cbody = body_and_head(cddl)
    instrumented_bodies[fn] = body
    check("S2.2/" + f[:4], hashlib.md5(ubody.encode()).hexdigest() == md5 == hashlib.md5(cbody.encode()).hexdigest(),
          f"diff mínimo: sem as linhas P3B-S2 o corpo de {fn} tem o md5 do canônico/LIVE ({md5[:8]}…)")
    norm = lambda h: re.sub(r"(?i)^create (or replace )?function", "create function", re.sub(r"\s+", " ", h.strip()))
    check("S2.3/" + f[:4], norm(uhead) == norm(chead) and re.match(r"(?i)create or replace function", ddl),
          "cabeçalho (assinatura, retorno, linguagem, SECURITY, SET) idêntico ao canônico; CREATE OR REPLACE")
    v = w3_violations(body)
    check("S2.4/" + f[:4], not v, "W3 I-1..I-6 sem violações" + (f" {v}" if v else ""))
    used_ev = set(re.findall(r"'(CARD[A-Z_]*)'", " ".join(l for l in body.split("\n") if "binder_activity_begin" in l)))
    used_ef = set(re.findall(r"binder_activity_add_card_item\(\s*'([A-Z_]+)'", body)) | \
              set(re.findall(r"(?:THEN|ELSE)\s+'([A-Z_]+)'", " ".join(l for l in body.split("\n") if "add_card_item(CASE" in l)))
    check("S2.5/" + f[:4], used_ev == evtypes and used_ev <= EVENT_TYPES and used_ef and used_ef <= EFFECTS,
          f"tipos {sorted(used_ev)} e efeitos {sorted(used_ef)} dentro dos CHECKs da 5267")
    # grants originais reaplicados
    cg = re.findall(r"(?im)^\s*(?:revoke|grant)\b.*?;", (SCHEMA / canon).read_text(encoding="utf-8"), flags=re.S)
    sg = re.findall(r"(?im)^\s*(?:revoke|grant)\b.*?;", t, flags=re.S)
    check("S2.6/" + f[:4], [re.sub(r"\s+", " ", x) for x in cg] == [re.sub(r"\s+", " ", x) for x in sg],
          "REVOKE/GRANT idênticos aos do canônico (ACL preservado)")
    check("S2.7/" + f[:4], f"is distinct from '{md5}'" in t and "binder_activity_add_card_item(text, uuid, uuid, uuid)" in t,
          "precheck: recusa se a função LIVE divergir da base (md5) ou se 5271 faltar")
    lines = body.split("\n")
    bi = next(i for i, l in enumerate(lines) if "binder_activity_begin" in l)
    adds = [i for i, l in enumerate(lines) if "binder_activity_add_card_item" in l]
    ends = [i for i, l in enumerate(lines) if "binder_activity_end" in l]
    check("S2.8/" + f[:4], adds and all(bi < a < max(ends) for a in adds) and all(MARK in lines[i] for i in adds + ends + [bi]),
          "add_card_item entre begin e end, todas as chamadas marcadas P3B-S2")

# helper
ht = (HERE / HELPER).read_text(encoding="utf-8")
hc = strip_comments(ht)
check("S2.9", re.search(r"create function public\.binder_activity_add_card_item", hc)
      and "security definer" in hc and "set search_path = ''" in hc
      and re.search(r"revoke all on function public\.binder_activity_add_card_item\(text, uuid, uuid, uuid\) from public, anon, authenticated, service_role", hc)
      and not re.search(r"grant\s+execute", hc, re.I)
      and not re.search(r"binder_activity_(begin|end)\s*\(", hc)
      and not re.search(r"insert\s+into\s+public\.binder_activity_", hc, re.I)
      and "mmkyu.binder_activity_ctx" not in hc
      and "perform public.binder_activity_add_item('CARD', p_effect" in hc,
      "5271 interna: DEFINER, search_path vazio, sem EXECUTE de cliente; não abre/fecha operação nem grava direto; delega à 5268")

# mutações: o verificador pega regressões típicas da S2
mut = {
    "end removido (place)": instrumented_bodies["place_my_physical_card_in_slot"].replace("  perform public.binder_activity_end();  -- P3B-S2\n", ""),
    "begin antes do retorno UNCHANGED": instrumented_bodies["place_my_physical_card_in_slot"].replace(
        "  -- 5. Já posicionado?", "  perform public.binder_activity_begin(v_layout, 'CARD_PLACED', 'FICHARIO');\n  -- 5. Já posicionado?"),
    "end antes do RETURN ausente (remove)": instrumented_bodies["remove_slot_assignment"].replace("    PERFORM public.binder_activity_end();  -- P3B-S2\n", ""),
    "insert direto (move)": instrumented_bodies["move_slot_assignment"].replace(
        "    END IF;  -- P3B-S2", "    END IF;  -- P3B-S2\n    INSERT INTO public.binder_activity_item (event_id) VALUES (1);"),
}
for k, b in mut.items():
    check("S2.10/NEG", bool(w3_violations(b)), f"mutação detectada — {k}")

# a S1 continua íntegra
p = subprocess.run([sys.executable, str(HERE / "static_check_p3b_s1.py")], capture_output=True, text=True, cwd=HERE)
gate = [l for l in p.stdout.splitlines() if l.startswith("GATE")]
check("S2.11", p.returncode == 0, "static_check_p3b_s1: " + (gate[0].split(None, 1)[1].strip() if gate else "sem GATE"))

width = max(len(c) for c, _, _ in results)
fails = 0
for cid, ok, detail in results:
    fails += 0 if ok else 1
    print(f"{cid:<{width}}  {'PASS' if ok else 'FAIL'}  {detail}")
print(f"{'GATE':<{width}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
sys.exit(0 if fails == 0 else 1)
