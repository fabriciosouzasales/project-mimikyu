#!/usr/bin/env python3
"""Verificação estática da P3-B S4 (5279–5284): instrumentação de E11–E15.

Não conecta em banco. Prova:
  · diff mínimo — tirando as linhas marcadas "-- P3B-S4" e voltando o delimitador $fn$ → $$,
    cada corpo tem o md5 do LIVE (para 5243 o LIVE não tem os comentários do arquivo canônico;
    a base é o corpo do LIVE, conferido em 2026-10-27);
  · cabeçalho (assinatura, retorno, linguagem, SECURITY, SET) idêntico ao canônico;
  · contrato W3 (I-1..I-6) pelo verificador da S1; um único begin por função;
  · tipos de evento e efeitos dentro dos CHECKs da 5267;
  · R5: insert/close chamam add_layout_page/remove_layout_page DEPOIS do begin; itens de
    deslocamento de close gravados ANTES da remoção da página (I-10);
  · ACL original reaplicado; precheck por md5 e dependências;
  · helper 5279 interno; binder_gap_move_pocket NÃO instrumentada (E16 sem contexto até a S6);
  · verificações da S1, S2 e S3 continuam PASS.
Uso: python3 static_check_p3b_s4.py   (a partir desta pasta). Código de saída 0 = PASS.
"""
import contextlib, hashlib, importlib.util, io, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parents[1] / "schema"
MARK = "-- P3B-S4"
S4 = {  # arquivo: (canônico, função, md5 LIVE, tipos de evento, efeitos)
    "5280_instrument_add_layout_page.sql": ("5125_create_add_layout_page_function.sql", "add_layout_page",
        "cdcf89d386ed87ab69b8a17496170017", {"PAGES_ADDED"}, {"PAGE_ADDED"}),
    "5281_instrument_remove_layout_page.sql": ("5260_update_remove_layout_page_species_references.sql", "remove_layout_page",
        "4baf044d8df24aa957873fce2cf5529a", {"PAGE_REMOVED"}, {"PAGE_REMOVED", "PAGE_RENUMBERED"}),
    "5282_instrument_reorder_layout_pages.sql": ("5127_create_reorder_layout_pages_function.sql", "reorder_layout_pages",
        "39b8b80f3f3cb0f0a0f88a98352a52c9", {"PAGES_REORDERED"}, {"PAGE_RENUMBERED"}),
    "5283_instrument_insert_my_binder_gap.sql": ("5243_create_binder_insert_gap_functions.sql", "insert_my_binder_gap",
        "a99a90c572d2bd35424b4c725fff0150", {"GAP_OPENED"}, {"SHIFTED"}),
    "5284_instrument_close_my_binder_gap.sql": ("5243_create_binder_insert_gap_functions.sql", "close_my_binder_gap",
        "eef3073f5ad98ffe6fdfe36f1adb9f49", {"GAP_CLOSED"}, {"SHIFTED"}),
}
HELPER = "5279_create_binder_activity_add_pocket_shift_items.sql"
results = []
def check(cid, ok, detail): results.append((cid, bool(ok), detail))
def strip_comments(sql): return re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", sql, flags=re.S))
def ddl_of(text, fn):
    m = re.search(r"(?is)(create (?:or replace )?function public\." + fn + r"\(.*?\$(fn)?\$;)", text)
    return m.group(1) if m else None
def head_body(d):
    m = re.search(r"(?is)^(.*?\bas\s+)(\$[a-z_]*\$)(.*?)\2;$", d); return m.group(1), m.group(3)
def unmark(d): return "\n".join(l for l in d.split("\n") if MARK not in l).replace("$fn$", "$$")
norm = lambda h: re.sub(r"(?i)^create (or replace )?function", "create function", re.sub(r"\s+", " ", h.strip()).lower())

_spec = importlib.util.spec_from_file_location("s1", HERE / "static_check_p3b_s1.py")
_s1 = importlib.util.module_from_spec(_spec)
with contextlib.redirect_stdout(io.StringIO()):
    try: _spec.loader.exec_module(_s1)
    except SystemExit: pass
w3 = _s1.w3_violations
s1_text = (HERE / "5267_create_binder_activity_structures.sql").read_text(encoding="utf-8")
EVENT_TYPES = set(re.findall(r"'([A-Z_]+)',?\s*--\s*(?:E\d|L01)", s1_text))
EFFECTS = set(re.findall(r"'([A-Z_]+)'", re.search(r"chk_bai_effect check \(effect in \((.*?)\)\)", s1_text, re.S).group(1)))

bodies = {}
for f, (canon, fn, md5, evs, efs) in S4.items():
    t = (HERE / f).read_text(encoding="utf-8"); c = strip_comments(t)
    check("S4.1/" + f[:4], c.strip().lower().startswith("begin;") and c.strip().lower().endswith("commit;")
          and len(re.findall(r"\$[a-z_]*\$", c)) % 2 == 0, "begin;…commit; e delimitadores pareados")
    d = ddl_of(t, fn); h, b = head_body(d); uh, ub = head_body(unmark(d)); bodies[fn] = b
    ch, _ = head_body(ddl_of((SCHEMA / canon).read_text(encoding="utf-8"), fn))
    check("S4.2/" + f[:4], hashlib.md5(ub.encode()).hexdigest() == md5, f"diff mínimo: sem as linhas P3B-S4 o corpo de {fn} tem o md5 do LIVE ({md5[:8]}…)")
    check("S4.3/" + f[:4], norm(uh) == norm(ch) and re.match(r"(?i)create or replace function", d), "cabeçalho idêntico ao canônico; CREATE OR REPLACE")
    v = w3(b); check("S4.4/" + f[:4], not v, "W3 I-1..I-6 sem violações" + (f" {v}" if v else ""))
    beg = " ".join(l for l in b.split("\n") if "binder_activity_begin" in l)
    used_ev = set(re.findall(r"'([A-Z_]+)'", beg)) - {"FICHARIO"}
    used_ef = set(re.findall(r"binder_activity_add_item\('[A-Z]+',\s*'([A-Z_]+)'", b))
    if "binder_activity_add_pocket_shift_items(" in b: used_ef |= {"SHIFTED"}
    check("S4.5/" + f[:4], used_ev == evs and used_ef == efs and evs <= EVENT_TYPES and efs <= EFFECTS,
          f"tipos {sorted(used_ev)} / efeitos {sorted(used_ef)} = contrato e dentro dos CHECKs")
    cg = [re.sub(r"\s+", " ", x) for x in re.findall(r"(?ims)^\s*((?:revoke|grant)\b[^;]*;)", (SCHEMA / canon).read_text(encoding="utf-8")) if re.search(r"public\." + fn + r"\(", x)]
    if fn == "remove_layout_page": cg = [x for x in cg if "(uuid, integer)" in x]
    sg = [re.sub(r"\s+", " ", x) for x in re.findall(r"(?ims)^\s*((?:revoke|grant)\b[^;]*;)", t)]
    check("S4.6/" + f[:4], cg == sg and cg, "REVOKE/GRANT idênticos aos do canônico")
    check("S4.7/" + f[:4], f"is distinct from '{md5}'" in t, "precheck: recusa se a função LIVE divergir da base (md5)")
    lines = b.split("\n"); bi = [i for i, l in enumerate(lines) if "binder_activity_begin" in l]
    calls = [i for i, l in enumerate(lines) if re.search(r"binder_activity_(add_item|add_pocket_shift_items|end)\(", l)]
    check("S4.8/" + f[:4], len(bi) == 1 and all(bi[0] < i for i in calls) and all(MARK in lines[i] for i in calls + bi), "begin único antes de todas as gravações; chamadas marcadas")

ib, cb = bodies["insert_my_binder_gap"].split("\n"), bodies["close_my_binder_gap"].split("\n")
idx = lambda ls, pat: next(i for i, l in enumerate(ls) if re.search(pat, l))
check("S4.9", idx(ib, r"binder_activity_begin") < idx(ib, r"add_layout_page\(") and idx(ib, r"ALREADY_FREE'; gap_slot_id") < idx(ib, r"binder_activity_begin"),
      "R5/C-206 (insert): begin depois do retorno ALREADY_FREE e antes da página embutida")
check("S4.10", idx(cb, r"binder_activity_begin") < idx(cb, r"binder_gap_move_pocket") < idx(cb, r"add_pocket_shift_items") < idx(cb, r"remove_layout_page\("),
      "R5/I-10 (close): itens de deslocamento antes da remoção embutida da página")
rb = bodies["remove_layout_page"].split("\n")
check("S4.11", idx(rb, r"'PAGE_REMOVED', NULL") < idx(rb, r"DELETE FROM public.collection_layout_page") and idx(rb, r"'PAGE_RENUMBERED'") < idx(rb, r"SET page_number = page_number - 1"),
      "I-10 (remove): itens antes do DELETE e da renumeração")

ht = (HERE / HELPER).read_text(encoding="utf-8"); hc = strip_comments(ht)
check("S4.12", "create function public.binder_activity_add_pocket_shift_items" in hc and "security definer" in hc and "set search_path = ''" in hc
      and re.search(r"revoke all on function public\.binder_activity_add_pocket_shift_items\(uuid, uuid\) from public, anon, authenticated, service_role", hc)
      and not re.search(r"grant\s+execute", hc, re.I) and not re.search(r"binder_activity_(begin|end)\s*\(", hc)
      and not re.search(r"insert\s+into\s+public\.binder_activity_", hc, re.I) and "mmkyu.binder_activity_ctx" not in hc
      and set(re.findall(r"'(CARD|RESERVATION|POCKET)', 'SHIFTED'|add_card_item\('(SHIFTED)'", hc)) != set(),
      "5279 interna: DEFINER, search_path vazio, sem EXECUTE de cliente, sem begin/end, grava só via 5268/5271")
allsql = " ".join((HERE / f).read_text(encoding="utf-8") for f in list(S4) + [HELPER])
check("S4.13", not re.search(r"(?i)function public\.binder_gap_move_pocket", strip_comments(allsql)),
      "binder_gap_move_pocket NÃO é recriada (chamada pela E16 sem contexto até a S6)")
mut = {
    "begin duplicado (add)": bodies["add_layout_page"].replace("    RETURN QUERY", "    PERFORM public.binder_activity_begin(p_layout_id, 'PAGES_ADDED', 'FICHARIO');\n    RETURN QUERY", 1),
    "end ausente (reorder)": bodies["reorder_layout_pages"].replace("    PERFORM public.binder_activity_end();  -- P3B-S4\n", ""),
    "insert direto (close)": bodies["close_my_binder_gap"].replace("  page_removed := false;", "  insert into public.binder_activity_item (event_id) values (1);\n  page_removed := false;"),
}
for k, b in mut.items(): check("S4.14/NEG", bool(w3(b)), f"mutação detectada — {k}")
for chk in ("static_check_p3b_s1.py", "static_check_p3b_s2.py", "static_check_p3b_s3.py"):
    p = subprocess.run([sys.executable, str(HERE / chk)], capture_output=True, text=True, cwd=HERE)
    g = [l for l in p.stdout.splitlines() if l.startswith("GATE")]
    check("S4.15", p.returncode == 0, chk + ": " + (g[0].split(None, 1)[1].strip() if g else "sem GATE"))
w = max(len(c) for c, _, _ in results); fails = 0
for cid, ok, det in results:
    fails += 0 if ok else 1; print(f"{cid:<{w}}  {'PASS' if ok else 'FAIL'}  {det}")
print(f"{'GATE':<{w}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
sys.exit(0 if fails == 0 else 1)
