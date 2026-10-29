#!/usr/bin/env python3
"""Verificação estática da P3-B S5 (5287–5289): instrumentação de E06a, E06b e E07.

Não conecta em banco. Prova:
  · diff mínimo — tirando as linhas marcadas "-- P3B-S5" e voltando o delimitador $fn$ → $$,
    cada corpo tem o md5 do LIVE (= corpo canônico 5249/5165, conferido em 2026-10-28);
  · cabeçalho (assinatura, retorno, linguagem, SECURITY, SET) idêntico ao canônico;
  · contrato W3 (I-1..I-6) pelo verificador da S1; um único begin textual por função;
  · tipos de evento e efeitos dentro dos CHECKs da 5267 (CARD/LEFT pelo helper 5271);
  · I-10: itens lidos ANTES do DELETE do bolso, com o mesmo predicado do DELETE (E06a/E06b) ou
    com a posição travada antes da exclusão do exemplar (E07, cascata);
  · E06: begin/end dentro do mesmo laço por fichário, sem RETURN no laço; E07: chamadas
    condicionadas por WHERE e end imediatamente antes do RETURN final;
  · sobrecargas antigas (5024 de 2 argumentos e 5222 de 5) NÃO recriadas;
  · lint de colisão variável × alias (regra da 5285); ACL original reaplicado; precheck por md5;
  · mutações negativas detectadas; verificações S1, S2, S3, S4, 5285 e 5286 continuam PASS.
Uso: python3 static_check_p3b_s5.py   (a partir desta pasta). Código de saída 0 = PASS.
"""
import contextlib, hashlib, importlib.util, io, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parents[1] / "schema"
MARK = "-- P3B-S5"
S5 = {  # arquivo: (canônico, função, regex da assinatura, md5 LIVE, tipo de evento, origem)
    "5287_instrument_set_physical_cards_storage.sql": ("5249_binder_storage_change_writers.sql", "set_physical_cards_storage",
        r"set_physical_cards_storage\(\s*p_storage_container_id uuid,\s*p_physical_card_ids\s+uuid\[\],\s*p_unplace_from_binder",
        "c68a460ce75a7384f521aee751e50335", "CARDS_LEFT_BY_STORAGE", "ACERVO"),
    "5288_instrument_organize_my_collection_storage.sql": ("5249_binder_storage_change_writers.sql", "organize_my_collection_storage",
        r"organize_my_collection_storage\(\s*p_collection_id\s+uuid,\s*p_storage_container_id uuid,\s*p_mode\s+text,\s*p_expected_count\s+integer,\s*p_plan_token\s+text,\s*p_unplace_from_binder",
        "083dc24206720b084c0bc5434d93e1fa", "CARDS_LEFT_BY_COLLECTION_STORAGE", "COLECAO"),
    "5289_instrument_remove_my_physical_card.sql": ("5165_create_remove_my_physical_card_function.sql", "remove_my_physical_card",
        r"remove_my_physical_card\(p_physical_card_id uuid\)",
        "1322db0293d346dd1911240b44881e99", "CARD_LEFT_BY_INVENTORY_EXIT", "ACERVO"),
}
results = []
def check(cid, ok, detail): results.append((cid, bool(ok), detail))
def strip_comments(sql): return re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", sql, flags=re.S))
def ddl_of(text, sig):
    m = re.search(r"(?is)(create (?:or replace )?function public\." + sig + r".*?\$(fn)?\$;)", text)
    return m.group(1) if m else None
def head_body(d):
    m = re.search(r"(?is)^(.*?\bas\s+)(\$[a-z_]*\$)(.*?)\2;$", d); return m.group(1), m.group(3)
def unmark(d): return "\n".join(l for l in d.split("\n") if MARK not in l).replace("$fn$", "$$")
norm = lambda h: re.sub(r"(?i)^create (or replace )?function", "create function", re.sub(r"\s+", " ", h.strip()).lower())
def acl(text, fn, keep):
    return [re.sub(r"\s+", " ", x) for x in re.findall(r"(?ims)^\s*((?:revoke|grant)\b[^;]*;)", text)
            if re.search(r"public\." + fn + r"\(", x) and keep(x)]

def collisions(body):  # mesma regra do lint da 5285/5286
    decl = re.search(r"\bDECLARE\b([\s\S]*?)\bBEGIN\b", body, re.I)
    names = set()
    if decl:
        for line in decl.group(1).split("\n"):
            m = re.match(r"([a-z_][a-z0-9_]*)\s+(?:constant\s+)?[a-z]", line.split("--")[0].strip(), re.I)
            if m: names.add(m.group(1).lower())
    code = "\n".join(l.split("--")[0] for l in body.split("\n"))
    aliases = {a.lower() for a in re.findall(r"\b(?:from|join|update|using)\s+(?:only\s+)?[a-z_][a-z0-9_.]*\s+(?:as\s+)?([a-z_][a-z0-9_]*)\b", code, re.I)}
    return names & (aliases - {"on", "where", "set", "using", "join", "left", "right", "inner", "cross", "order", "group", "limit", "with", "and", "or", "for", "loop", "into", "select"})

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
for f, (canon, fn, sig, md5, ev, src) in S5.items():
    t = (HERE / f).read_text(encoding="utf-8"); c = strip_comments(t)
    k = f[:4]
    check("S5.1/" + k, c.strip().lower().startswith("begin;") and c.strip().lower().endswith("commit;")
          and len(re.findall(r"\$[a-z_]*\$", c)) % 2 == 0, "begin;…commit; e delimitadores pareados")
    d = ddl_of(t, sig); h, b = head_body(d); uh, ub = head_body(unmark(d)); bodies[fn] = b
    ctext = (SCHEMA / canon).read_text(encoding="utf-8")
    ch, cb = head_body(ddl_of(ctext, sig))
    check("S5.2/" + k, hashlib.md5(ub.encode()).hexdigest() == md5 and hashlib.md5(cb.encode()).hexdigest() == md5,
          f"diff mínimo: sem as linhas P3B-S5 o corpo de {fn} tem o md5 do LIVE e do canônico ({md5[:8]}…)")
    check("S5.3/" + k, norm(uh) == norm(ch) and re.match(r"(?i)create or replace function", d), "cabeçalho idêntico ao canônico; CREATE OR REPLACE")
    v = w3(b); check("S5.4/" + k, not v, "W3 I-1..I-6 sem violações" + (f" {v}" if v else ""))
    beg = [l for l in b.split("\n") if "binder_activity_begin(" in l]
    used_ev = set(re.findall(r"'([A-Z_]+)'", " ".join(beg))) - {src}
    used_src = set(re.findall(r"'(ACERVO|COLECAO|FICHARIO|CATALOGO)'", " ".join(beg)))
    used_ef = set(re.findall(r"binder_activity_add_card_item\('([A-Z_]+)'", b)) | set(re.findall(r"binder_activity_add_item\('[A-Z]+',\s*'([A-Z_]+)'", b))
    check("S5.5/" + k, used_ev == {ev} and used_src == {src} and used_ef == {"LEFT"} and ev in EVENT_TYPES and "LEFT" in EFFECTS,
          f"tipo {sorted(used_ev)} / origem {sorted(used_src)} / efeitos {sorted(used_ef)} = contrato e dentro dos CHECKs")
    keep = (lambda x: "boolean" in x) if fn != "remove_my_physical_card" else (lambda x: True)
    cg, sg = acl(ctext, fn, keep), acl(t, fn, lambda x: True)
    check("S5.6/" + k, cg == sg and cg, "REVOKE/GRANT idênticos aos do canônico")
    pre = t[t.index("do $pre$"):t.index("$pre$;")]
    check("S5.7/" + k, f"is distinct from '{md5}'" in pre and "binder_activity_add_card_item(text, uuid, uuid, uuid)" in pre,
          "precheck: recusa se a função LIVE divergir da base (md5) ou faltar 5268/5271")
    lines = b.split("\n"); bi = [i for i, l in enumerate(lines) if "binder_activity_begin(" in l]
    calls = [i for i, l in enumerate(lines) if re.search(r"binder_activity_(add_item|add_card_item|end)\(", l)]
    check("S5.8/" + k, len(bi) == 1 and all(bi[0] < i for i in calls) and all(MARK in lines[i] for i in calls + bi),
          "begin textual único antes de todas as gravações; chamadas marcadas")
    check("S5.9/" + k, not collisions(b), "lint de colisão variável × alias (regra da 5285): 0 ocorrências")

def idx(ls, pat, start=0): return next(i for i, l in enumerate(ls) if i >= start and re.search(pat, l))
def loop_ok(b):
    """begin/add/end dentro do laço externo por fichário; end é a última instrução do laço; sem RETURN no laço."""
    ls = b.split("\n")
    lo = idx(ls, r"for v_act_layout in"); le = idx(ls, r"^\s*end loop;  -- P3B-S5", idx(ls, r"binder_activity_end\("))
    seg = ls[lo:le + 1]
    return (lo < idx(ls, "binder_activity_begin") < idx(ls, "binder_activity_add_card_item") < idx(ls, r"binder_activity_end\(") < le
            and re.search(r"binder_activity_end\(", ls[le - 1]) and not any(re.match(r"\s*return\b", x, re.I) for x in seg))
def pred_after(ls, i):
    out = []
    for l in ls[i + 1:]:
        s = l.replace(MARK, "").rstrip()
        if s.strip() == "loop": break
        out.append(re.sub(r"\s+", " ", s).strip().rstrip(";"))
        if s.endswith(";"): break
    return out

for fn, dele in (("set_physical_cards_storage", r"^\s*delete from public\.collection_layout_slot_assignment a$"),
                 ("organize_my_collection_storage", r"^\s*delete from public\.collection_layout_slot_assignment a$")):
    ls = bodies[fn].split("\n"); di = idx(ls, dele)
    dpred = [x for x in pred_after(ls, di) if x.startswith(("where", "and"))]
    ii = idx(ls, r"^\s*for v_act in")
    ipred = [x for x in pred_after(ls, ii) if x.startswith(("where", "and"))]
    same = [x.replace("where ", "and ") for x in dpred if "pc.id = a.physical_card_id" not in x]
    got = [x.replace("where ", "and ") for x in ipred if "p.layout_id = v_act_layout" not in x]
    check("S5.10/" + fn[:8], idx(ls, "binder_activity_add_card_item") < di and set(same) <= set(got) and len(got) == len(same),
          f"I-10 ({fn}): itens antes do DELETE e com o mesmo predicado dele {same}")
    check("S5.11/" + fn[:8], loop_ok(bodies[fn]), f"{fn}: begin/add/end no laço por fichário; end fecha cada fichário; sem RETURN no laço")

rb = bodies["remove_my_physical_card"].split("\n")
sel = idx(rb, r"select a\.slot_id, p\.layout_id into v_act_slot, v_act_layout")
check("S5.12", sel < idx(rb, r"for update of a;", sel) < idx(rb, "binder_activity_begin") < idx(rb, "add_card_item")
      < idx(rb, r"delete from public\.physical_card where id = v_id") < idx(rb, r"binder_activity_end\(")
      and re.match(r"\s*return true;", rb[idx(rb, r"binder_activity_end\(") + 1])
      and all("where v_act_layout is not null;" in rb[idx(rb, p)] for p in ("binder_activity_begin", "add_card_item", r"binder_activity_end\(")),
      "E07: posição lida e travada antes da exclusão; begin/add/end condicionados; end imediatamente antes do RETURN final")

allsql = strip_comments(" ".join((HERE / f).read_text(encoding="utf-8") for f in S5))
check("S5.13", not re.search(r"(?i)function public\.set_physical_cards_storage\(\s*p_storage_container_id uuid,\s*p_physical_card_ids\s+uuid\[\]\s*\)", allsql)
      and not re.search(r"(?i)function public\.organize_my_collection_storage\([^)]*p_plan_token\s+text\s*\)", allsql)
      and not re.search(r"(?i)\bdrop\s+function\b", allsql),
      "sobrecargas antigas (5024: 2 argumentos; 5222: 5) não recriadas; nenhum DROP")

mut = {
    "begin duplicado (E06a)": bodies["set_physical_cards_storage"].replace("    return query", "    perform public.binder_activity_begin(null, 'X', 'ACERVO');\n    return query", 1),
    "end ausente (E07)": bodies["remove_my_physical_card"].replace("  perform public.binder_activity_end() where v_act_layout is not null;  -- P3B-S5\n", ""),
    "insert direto (E06b)": bodies["organize_my_collection_storage"].replace("  -- 7. Escrita", "  insert into public.binder_activity_item (event_id) values (1);\n  -- 7. Escrita", 1),
}
for k2, b in mut.items(): check("S5.14/NEG", bool(w3(b)), f"W3 detecta mutação — {k2}")
moved = bodies["set_physical_cards_storage"]
blk = re.search(r"        for v_act_layout in  -- P3B-S5\n[\s\S]*?        end loop;  -- P3B-S5\n", moved).group(0)
delete_blk = re.search(r"        delete from public\.collection_layout_slot_assignment a\n[\s\S]*?;\n", moved).group(0)
mutated = moved.replace(blk, "").replace(delete_blk, delete_blk + blk)
ml = mutated.split("\n")
check("S5.14/NEG", not (idx(ml, "binder_activity_add_card_item") < idx(ml, r"^\s*delete from public\.collection_layout_slot_assignment a$")),
      "regra I-10 detecta mutação — itens movidos para depois do DELETE")
check("S5.14/NEG", bool(collisions(bodies["remove_my_physical_card"].replace("  v_act_slot   uuid;", "  a            uuid;"))),
      "lint detecta mutação — variável com nome de alias (a)")

for chk in ("static_check_p3b_s1.py", "static_check_p3b_s2.py", "static_check_p3b_s3.py", "static_check_p3b_s4.py",
            "static_check_p3b_s4_5285.py", "static_check_p3b_s4_5286.py"):
    p = subprocess.run([sys.executable, str(HERE / chk)], capture_output=True, text=True, cwd=HERE)
    g = [l for l in p.stdout.splitlines() if l.startswith("GATE")]
    check("S5.15", p.returncode == 0, chk + ": " + (g[0].split(None, 1)[1].strip() if g else "sem GATE"))
w = max(len(c) for c, _, _ in results); fails = 0
for cid, ok, det in results:
    fails += 0 if ok else 1; print(f"{cid:<{w}}  {'PASS' if ok else 'FAIL'}  {det}")
print(f"{'GATE':<{w}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
for f in S5: print(f"SHA-256 {f}: {hashlib.sha256((HERE / f).read_bytes()).hexdigest()}")
sys.exit(0 if fails == 0 else 1)
