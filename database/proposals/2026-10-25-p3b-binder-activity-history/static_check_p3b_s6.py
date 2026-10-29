#!/usr/bin/env python3
"""Verificação estática da P3-B S6 (5290–5296): instrumentação de E01, E16, E17, E18, E19, E19b e E20.

Não conecta em banco. Prova:
  · diff mínimo — tirando as linhas "-- P3B-S6" e voltando $fn$ → $$, cada corpo tem o md5 do LIVE
    (dismantle: corpo LIVE sem os comentários da canônica 5242; código idêntico);
  · cabeçalho (assinatura, retorno, linguagem, SECURITY, SET) idêntico ao canônico; CREATE OR REPLACE;
  · contrato W3 (I-1..I-6) pelo verificador da S1; begin textual único antes de toda gravação;
  · tipos de evento, origens e efeitos dentro dos CHECKs da 5267;
  · ordem por evento (I-10 / C-206): retornos idempotentes antes do begin; itens de origem antes das
    escritas destrutivas; itens de destino depois das escritas;
  · lint de colisão variável × alias (regra da 5285); ACL original; precheck por md5 e dependências;
  · mutações negativas detectadas; verificações S1–S5 (e 5285/5286) continuam PASS.
Uso: python3 static_check_p3b_s6.py   (a partir desta pasta). Código de saída 0 = PASS.
"""
import contextlib, hashlib, importlib.util, io, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parents[1] / "schema"
MARK = "-- P3B-S6"
S6 = {  # arquivo: (canônico, função, md5 LIVE, tipo, origem, efeitos)
    "5290_instrument_attach_my_collection_to_binder.sql": ("5255_binder_attach_by_physical_location.sql", "attach_my_collection_to_binder",
        "1b87933cf804aa3fc29f8659dc947e2c", "COLLECTION_ATTACHED", "FICHARIO", {"ATTACHED"}),
    "5291_instrument_detach_my_collection_from_binder.sql": ("5253_binder_detach_keeps_positions.sql", "detach_my_collection_from_binder",
        "09570bf964a8351c0f97acbc7ba9c736", "COLLECTION_DETACHED", "FICHARIO", {"UNLOCKED", "RELEASED", "DETACHED"}),
    "5292_instrument_transfer_my_binder_ownership.sql": ("5254_create_transfer_my_binder_ownership.sql", "transfer_my_binder_ownership",
        "4755a772e002c5a3994c6ad81ac53bb9", "BINDER_OWNERSHIP_TRANSFERRED", "FICHARIO", {"TRANSFERRED"}),
    "5293_instrument_delete_collection_layout.sql": ("5124_create_delete_collection_layout_function.sql", "delete_collection_layout",
        "1b4bf89732af4ef36c834a30b08fec44", "BINDER_DELETED_EMPTY", "FICHARIO", {"CLOSED"}),
    "5294_instrument_dismantle_my_collection_binder.sql": ("5242_update_binder_dismantle_for_region_images.sql", "dismantle_my_collection_binder",
        "6aa90085a3a97c5b149fde6f3c4a6096", "BINDER_DISMANTLED", "FICHARIO", {"REMOVED", "RELEASED", "CLOSED"}),
    "5295_instrument_create_my_collection_binder.sql": ("5224_create_collection_binder_plan_preview_create.sql", "create_my_collection_binder",
        "5ba7941f175137f322179eff72f7a37c", "BINDER_ASSEMBLED", "FICHARIO", {"PAGE_ADDED", "PLACED", "RESERVED"}),
    "5296_instrument_apply_my_binder_catalog_reconciliation.sql": ("5266_create_binder_catalog_reconciliation_apply.sql", "apply_my_binder_catalog_reconciliation",
        "aa58b231484cc1ed533c50c51c38f2cc", "CATALOG_NOVELTIES_INCORPORATED", "CATALOGO", {"INCORPORATED", "SHIFTED", "RESERVED"}),
}
results = []
def check(cid, ok, detail): results.append((cid, bool(ok), detail))
def strip_comments(sql): return re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", sql, flags=re.S))
def ddl_of(text, fn):
    ms = list(re.finditer(r"(?is)(create (?:or replace )?function public\." + fn + r"\s*\(.*?\bas\s+(\$[a-z_]*\$).*?\2;)", text))
    return ms[-1].group(1) if ms else None
def head_body(d):
    m = re.search(r"(?is)^(.*?\bas\s+)(\$[a-z_]*\$)(.*?)\2;$", d); return m.group(1), m.group(3)
def unmark(d): return "\n".join(l for l in d.split("\n") if MARK not in l).replace("$fn$", "$$")
norm = lambda h: re.sub(r"(?i)^create (or replace )?function", "create function", re.sub(r"\s+", " ", re.sub(r"--[^\n]*", "", h).strip()).lower())
def acl(text, fn): return [re.sub(r"\s+", " ", x) for x in re.findall(r"(?ims)^\s*((?:revoke|grant)\b[^;]*;)", text) if re.search(r"public\." + fn + r"\(", x)]
def collisions(body):
    decl = re.search(r"\bDECLARE\b([\s\S]*?)\bBEGIN\b", body, re.I)
    names = set()
    if decl:
        for line in decl.group(1).split("\n"):
            m = re.match(r"([a-z_][a-z0-9_]*)\s+(?:constant\s+)?[a-z]", line.split("--")[0].strip(), re.I)
            if m: names.add(m.group(1).lower())
    code = "\n".join(l.split("--")[0] for l in body.split("\n"))
    aliases = {a.lower() for a in re.findall(r"\b(?:from|join|update|using)\s+(?:only\s+)?[a-z_][a-z0-9_.]*\s+(?:as\s+)?([a-z_][a-z0-9_]*)\b", code, re.I)}
    return names & (aliases - {"on", "where", "set", "using", "join", "left", "right", "inner", "cross", "order", "group", "limit", "with", "and", "or", "for", "loop", "into", "select"})
def first(ls, pat, start=0): return next(i for i, l in enumerate(ls) if i >= start and re.search(pat, l))
def last(ls, pat): return max(i for i, l in enumerate(ls) if re.search(pat, l))

_spec = importlib.util.spec_from_file_location("s1", HERE / "static_check_p3b_s1.py")
_s1 = importlib.util.module_from_spec(_spec)
with contextlib.redirect_stdout(io.StringIO()):
    try: _spec.loader.exec_module(_s1)
    except SystemExit: pass
w3 = _s1.w3_violations
s1_text = (HERE / "5267_create_binder_activity_structures.sql").read_text(encoding="utf-8")
EVENT_TYPES = set(re.findall(r"'([A-Z_]+)',?\s*--\s*(?:E\d|L01)", s1_text))
EFFECTS = set(re.findall(r"'([A-Z_]+)'", re.search(r"chk_bai_effect check \(effect in \((.*?)\)\)", s1_text, re.S).group(1)))
SOURCES = {"FICHARIO", "ACERVO", "COLECAO", "CATALOGO"}

bodies = {}
for f, (canon, fn, md5, ev, src, efs) in S6.items():
    t = (HERE / f).read_text(encoding="utf-8"); c = strip_comments(t); k = f[:4]
    check("S6.1/" + k, c.strip().lower().startswith("begin;") and c.strip().lower().endswith("commit;")
          and len(re.findall(r"\$[a-z_]*\$", c)) % 2 == 0, "begin;…commit; e delimitadores pareados")
    d = ddl_of(t, fn); h, b = head_body(d); uh, ub = head_body(unmark(d)); bodies[fn] = b
    ctext = (SCHEMA / canon).read_text(encoding="utf-8"); ch, _ = head_body(ddl_of(ctext, fn))
    check("S6.2/" + k, hashlib.md5(ub.encode()).hexdigest() == md5, f"diff mínimo: sem as linhas P3B-S6 o corpo de {fn} tem o md5 do LIVE ({md5[:8]}…)")
    check("S6.3/" + k, norm(uh) == norm(ch) and re.match(r"(?i)create or replace function", d), "cabeçalho idêntico ao canônico; CREATE OR REPLACE")
    v = w3(b); check("S6.4/" + k, not v, "W3 I-1..I-6 sem violações" + (f" {v}" if v else ""))
    beg = " ".join(l for l in b.split("\n") if "binder_activity_begin(" in l)
    used_ev = set(re.findall(r"'([A-Z_]+)'", beg)) & EVENT_TYPES
    used_src = set(re.findall(r"'([A-Z_]+)'", beg)) & SOURCES
    used_ef = (set(re.findall(r"binder_activity_add_item\('[A-Z]+',\s*'([A-Z_]+)'", b, re.I))
               | set(re.findall(r"add_card_item\('([A-Z_]+)'", b)) | set(re.findall(r"add_reservation_item\('([A-Z_]+)'", b))
               | ({"SHIFTED"} if "add_pocket_shift_items(" in b else set()))
    check("S6.5/" + k, used_ev == {ev} and used_src == {src} and used_ef == efs and efs <= EFFECTS,
          f"tipo {sorted(used_ev)} / origem {sorted(used_src)} / efeitos {sorted(used_ef)} = contrato e dentro dos CHECKs")
    cg, sg = acl(ctext, fn), acl(t, fn)
    check("S6.6/" + k, cg == sg and cg, "REVOKE/GRANT idênticos aos do canônico")
    pre = t[t.index("do $pre$"):t.index("$pre$;")]
    check("S6.7/" + k, f"is distinct from '{md5}'" in pre and "add_reservation_item(text, uuid)" in pre, "precheck: md5 da base LIVE e dependências")
    lines = b.split("\n"); bi = [i for i, l in enumerate(lines) if "binder_activity_begin(" in l]
    calls = [i for i, l in enumerate(lines) if re.search(r"binder_activity_(add_item|add_card_item|add_reservation_item|add_pocket_shift_items|end)\(", l)]
    check("S6.8/" + k, len(bi) == 1 and all(bi[0] < i for i in calls) and all(MARK in lines[i] for i in calls + bi),
          "begin textual único antes de todas as gravações; chamadas marcadas")
    check("S6.9/" + k, not collisions(b), "lint de colisão variável × alias (regra da 5285): 0 ocorrências")

L = {fn: b.split("\n") for fn, b in bodies.items()}
a = L["attach_my_collection_to_binder"]
check("S6.10/E17", last(a, r"outcome := 'ALREADY_ATTACHED'") < first(a, "binder_activity_begin") < first(a, r"insert into public\.collection_layout_guest")
      < first(a, r"'ATTACHED'") < first(a, r"binder_activity_end"), "E17: ALREADY_ATTACHED antes do begin; item depois da associação")
dt = L["detach_my_collection_from_binder"]
check("S6.11/E18", last(dt, r"outcome := 'ALREADY_DETACHED'") < first(dt, "LOCKED_SLOTS_REQUIRE_CONFIRMATION") < first(dt, "binder_activity_begin")
      < first(dt, r"'UNLOCKED'") < first(dt, r"add_reservation_item\('RELEASED'") < first(dt, r"set locked = false")
      < first(dt, r"delete from public\.collection_layout_slot_expected_content") < first(dt, r"'DETACHED'") < first(dt, r"binder_activity_end"),
      "E18: retornos e confirmação antes do begin; itens de origem antes do UPDATE/DELETE")
tr = L["transfer_my_binder_ownership"]
check("S6.12/E20", first(tr, r"'UNCHANGED'") < first(tr, "binder_activity_begin") < first(tr, r"set collection_id = p_to_collection_id where l\.id")
      < first(tr, r"'TRANSFERRED'") < first(tr, r"binder_activity_end") < last(tr, r"return query select 'TRANSFERRED'")
      and sum(1 for l in tr if MARK in l and re.search(r"binder_activity_", l)) == 3,
      "E20 (§14.7): UNCHANGED antes do begin; só begin/add_item/end; item depois da troca")
dl = L["delete_collection_layout"]
check("S6.13/E19b", first(dl, "remove all pages before deleting") < first(dl, "binder_activity_begin") < first(dl, r"'CLOSED'")
      < first(dl, r"DELETE FROM public\.collection_layout$") < first(dl, r"binder_activity_end"),
      "E19b: recusa por páginas antes do begin; item antes do DELETE; end no fim")
ds = L["dismantle_my_collection_binder"]
check("S6.14/E19", first(ds, "ALREADY_ABSENT") < first(ds, "DISMANTLE_PLAN_CHANGED") < first(ds, "binder_activity_begin")
      < first(ds, r"add_card_item\('REMOVED'") < first(ds, r"add_reservation_item\('RELEASED'") < first(ds, r"'CLOSED'")
      < first(ds, r"set locked = false") < first(ds, r"delete from public\.collection_layout_slot_assignment") < first(ds, r"delete from public\.collection_layout l"),
      "E19: retornos e token antes do begin; cartas, reservas e encerramento ANTES de qualquer escrita")
cr = L["create_my_collection_binder"]
check("S6.15/E01", first(cr, "ALREADY_EXISTS") < first(cr, "BINDER_ASSEMBLY_INCONSISTENT", first(cr, r"get diagnostics v_n_asg")) < first(cr, "binder_activity_begin")
      < first(cr, r"'PAGE_ADDED'") < first(cr, r"add_card_item\('PLACED'") < first(cr, r"add_reservation_item\('RESERVED'") < first(cr, r"binder_activity_end")
      < first(cr, r"outcome\s+:= 'CREATED'"), "E01: ALREADY_EXISTS antes; itens de destino depois de todas as escritas e da conferência")
ap = L["apply_my_binder_catalog_reconciliation"]
mv = first(ap, r"binder_gap_move_pocket\(v_chain\[k\]")
check("S6.16/E16", last(ap, r"outcome := 'ALREADY_APPLIED'") < first(ap, "binder_activity_begin") < first(ap, r"for st in")
      and re.search(r"add_pocket_shift_items\(v_chain\[k\], v_chain\[k \+ 1\]\)", ap[mv + 1])
      and first(ap, r"v_upg := v_upg \+ 1") < first(ap, r"'INCORPORATED'") and first(ap, r"v_res := v_res \+ 1") < first(ap, r"add_reservation_item\('RESERVED'")
      and first(ap, r"add_layout_page\(v_layout\)") > first(ap, "binder_activity_begin") and first(ap, r"binder_activity_end") < first(ap, r"outcome := 'APPLIED'"),
      "E16: idempotência antes do begin; página embutida dentro do evento (R5); SHIFTED logo após cada movimento; reservas depois do INSERT/UPDATE")

mut = {
    "begin antes do retorno idempotente (E17)": bodies["attach_my_collection_to_binder"].replace(
        "  -- 4. Idempotência", "  perform public.binder_activity_begin(p_layout_id, 'COLLECTION_ATTACHED', 'FICHARIO', p_collection_id);\n  -- 4. Idempotência", 1),
    "end ausente (E19b)": bodies["delete_collection_layout"].replace("    PERFORM public.binder_activity_end();  -- P3B-S6\n", ""),
    "insert direto (E16)": bodies["apply_my_binder_catalog_reconciliation"].replace("  outcome := 'APPLIED';", "  insert into public.binder_activity_event (owner_user_id) values (null);\n  outcome := 'APPLIED';", 1),
}
for k2, b in mut.items(): check("S6.17/NEG", bool(w3(b)), f"W3 detecta mutação — {k2}")
moved = L["dismantle_my_collection_binder"]
blk_i, blk_j = first(moved, "binder_activity_begin") - 2, first(moved, r"jsonb_build_object\('reason', 'DISMANTLED'\)")
seg = moved[blk_i:blk_j + 1]; rest = moved[:blk_i] + moved[blk_j + 1:]
pos = first(rest, r"delete from public\.collection_layout l"); mut_ds = rest[:pos + 1] + seg + rest[pos + 1:]
check("S6.17/NEG", not (first(mut_ds, r"add_card_item\('REMOVED'") < first(mut_ds, r"delete from public\.collection_layout_slot_assignment")),
      "regra I-10 detecta mutação — itens do E19 movidos para depois das exclusões")
check("S6.17/NEG", bool(collisions(bodies["dismantle_my_collection_binder"].replace("  v_act     record;", "  p         record;"))),
      "lint detecta mutação — variável com nome de alias (p)")

for chk in ("static_check_p3b_s1.py", "static_check_p3b_s2.py", "static_check_p3b_s3.py", "static_check_p3b_s4.py",
            "static_check_p3b_s4_5285.py", "static_check_p3b_s4_5286.py", "static_check_p3b_s5.py"):
    p = subprocess.run([sys.executable, str(HERE / chk)], capture_output=True, text=True, cwd=HERE)
    g = [l for l in p.stdout.splitlines() if l.startswith("GATE")]
    check("S6.18", p.returncode == 0, chk + ": " + (g[0].split(None, 1)[1].strip() if g else "sem GATE"))
w = max(len(c) for c, _, _ in results); fails = 0
for cid, ok, det in results:
    fails += 0 if ok else 1; print(f"{cid:<{w}}  {'PASS' if ok else 'FAIL'}  {det}")
print(f"{'GATE':<{w}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
for f in S6: print(f"SHA-256 {f}: {hashlib.sha256((HERE / f).read_bytes()).hexdigest()}")
sys.exit(0 if fails == 0 else 1)
