#!/usr/bin/env python3
"""
V1-13 · E3-6 / S4-c — verificação ESTÁTICA da 5396, ROLLBACK_5396, PRE/POST, expectativas e
manifesto, com testes de MUTAÇÃO dos controles críticos.

Sem banco. Prova só propriedades do TEXTO (STD-005): reprodutibilidade; removidos os blocos
[5396+]…[5396-], cada uma das 8 funções é IDÊNTICA ao texto implantado (5258, 5383 G1, 5384, 5341);
blocos só leem e chamam a primitiva depois da escrita efetiva; nenhum evento em recusa, UNCHANGED,
ALREADY_APPLIED visível ou remoção de 0; titular sob v1_13_capability_open(); primitiva interna sem
EXECUTE, autor derivado, tipos e chaves fechados, sem itens nem identificadores patrimoniais;
leituras 5269/5388 e fluxo da coleção (5394/5395) intocados; rollback ao canônico; PRE/POST somente
leitura; inventário de escritores inalterado. NÃO prova execução nem comportamento.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s4-collaborative-audit/static_check_5396.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MIG = os.path.join(HERE, "5396_audit_binder_species_references.sql")
RB = os.path.join(HERE, "ROLLBACK_5396.sql")
PRE = os.path.join(HERE, "S4C_5396_PRE_readonly.sql")
POST = os.path.join(HERE, "S4C_5396_POST_readonly.sql")
EXP = os.path.join(HERE, "S4C_5396_EXPECTATIVAS.json")
MAN = os.path.join(HERE, "S4C_5396_MANIFEST.txt")
A, Z = "-- [5396+]", "-- [5396-]"
RM = "  -- [5396~]"


def rd(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def nolit(t):
    return re.sub(r"'(?:[^']|'')*'", "''", nc(t))


def balanced(t):
    d = 0
    for ch in nolit(t):
        d += (ch == "(") - (ch == ")")
        if d < 0:
            return False
    return d == 0


def ro(s):  # espelho do Test-ReadOnlySql do executor v1.4
    s = re.sub(r"/\*[\s\S]*?\*/", " ", s)
    s = re.sub(r"--[^\r\n]*", " ", s)
    s = re.sub(r"'(?:[^']|'')*'", "''", s).strip()
    if not re.match(r"(?i)^select\b", s) or len(re.findall(";", s)) != 1 or not s.endswith(";") or "$" in s:
        return False
    return not re.search(r"(?i)\b(insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|lock|comment|copy|call|do|execute|vacuum|analyze|refresh|reindex|cluster|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend|dblink)\b", s)


md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()


def ordered(s, *subs):
    pos = [s.find(x) for x in subs]
    return all(p >= 0 for p in pos) and pos == sorted(pos) and len(set(pos)) == len(pos)


def fn_def(t, name):
    m = re.search(r"create\s+or\s+replace\s+function\s+public\." + re.escape(name) + r"\s*\(", t, re.I)
    if not m:
        return None
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", t[m.end():], re.I)
    s = m.end() + a.end()
    e = t.index(a.group(1), s) + len(a.group(1))
    return t[m.start():e] + ";"


def prosrc(d):
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", d, re.I)
    s = a.end()
    return d[s:d.index(a.group(1), s)]


def strip_marked(t):
    return re.sub(re.escape(A) + r"\n.*?\n" + re.escape(Z) + r"\n?", "", t, flags=re.S)


def blocks(t):
    return re.findall(re.escape(A) + r"\n(.*?)\n" + re.escape(Z), t, flags=re.S)


spec = importlib.util.spec_from_file_location("build_5396", os.path.join(HERE, "build_5396.py"))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)
with tempfile.TemporaryDirectory() as td:
    B.HERE = td
    GEN_MIG, GEN_RB = B.build()

REC = "public.binder_activity_record_species("
WRITE = {  # última escrita efetiva antes do registro
    "apply_my_binder_species_references": "do update set references_visible = true, updated_at = now()",
    "clear_my_binder_species_references": "delete from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;",
    "set_my_binder_species_reference_visibility": "do update set references_visible = excluded.references_visible, updated_at = now();",
    "editor_apply_binder_species_references": "do update set references_visible = true, updated_at = now()",
    "editor_clear_binder_species_references": "delete from public.collection_layout_slot_species_reference r\n  where r.layout_id = t.layout_id and r.collection_id = p_collection_id;",
    "editor_set_binder_species_reference_visibility": "do update set references_visible = excluded.references_visible, updated_at = now();",
}
REFUSALS = {
    "apply_my_binder_species_references": ["'PLAN_CHANGED'", "'SPECIES_REFERENCES_PRESENT'", "'NOTHING_TO_APPLY'"],
    "editor_apply_binder_species_references": ["'PLAN_CHANGED'", "'SPECIES_REFERENCES_PRESENT'", "'NOTHING_TO_APPLY'"],
    "clear_my_binder_species_references": ["'COUNT_MISMATCH'"],
    "editor_clear_binder_species_references": ["'COUNT_MISMATCH'"],
    "set_my_binder_species_reference_visibility": ["operation := 'UNCHANGED';"],
    "editor_set_binder_species_reference_visibility": ["'UNCHANGED'::text;\n    return;"],
}
EVENTS = {
    "apply_my_binder_species_references": ["SPECIES_REFERENCES_APPLIED", "SPECIES_REFERENCES_SHOWN"],
    "editor_apply_binder_species_references": ["SPECIES_REFERENCES_APPLIED", "SPECIES_REFERENCES_SHOWN"],
    "clear_my_binder_species_references": ["SPECIES_REFERENCES_CLEARED"],
    "editor_clear_binder_species_references": ["SPECIES_REFERENCES_CLEARED"],
    "set_my_binder_species_reference_visibility": ["SPECIES_REFERENCES_HIDDEN", "SPECIES_REFERENCES_SHOWN"],
    "editor_set_binder_species_reference_visibility": ["SPECIES_REFERENCES_HIDDEN", "SPECIES_REFERENCES_SHOWN"],
}
SIG = "n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')'"
PATRIMONIAL = r"physical_card|allocation|slot_id|storage|condition|price|card_id|owner_user_id|actor_user_id"


def run(mig, rb, pre, post, exp, man_txt, gen=True):
    R: list[tuple[str, bool, str]] = []
    ck = lambda cid, ok, d: R.append((cid, bool(ok), d))
    head = mig[:mig.index("\nbegin;\n")].strip() if "\nbegin;\n" in mig else ""
    ck("H0", head.startswith("/*") and head.endswith("*/") and head.count("*/") == 1, "cabeçalho = um único comentário de bloco")
    ck("S0", all(balanced(x) for x in (mig, rb, pre, post)) and nc(mig).count("$pre$") == 2 and nc(mig).count("$post$") == 2
       and nc(rb).count("$pre$") == 2 and nc(rb).count("$post$") == 2 and nc(rb).count("$chk$") == 2, "aspas, parênteses e $…$ balanceados (NÃO substitui compilação)")
    if gen:
        ck("G0", mig == GEN_MIG and rb == GEN_RB, "migration e rollback = saída reproduzível de build_5396.py")
    ck("C1", all(md5(prosrc(B.CANON[n])) == h for n, (_, _, h) in B.SRC.items()) and len(B.SRC) == 10,
       "texto-fonte (5258, 5383 G1, 5384, 5341, 5269, 5388 R1) = md5 canônico; 10 funções")
    defs = {n: fn_def(mig, n) for n in B.SRC}
    ck("C2", all(defs[n] and B.unrep(n, strip_marked(defs[n])) == B.CANON[n] for n in B.SRC)
       and all(defs[n].count(RM) == len(B.REPL.get(n, [])) for n in B.SRC if defs[n])
       and sorted(B.REPL) == ["get_my_binder_activity", "get_shared_binder_activity"]
       and len(B.REPL["get_my_binder_activity"]) == 1 and len(B.REPL["get_shared_binder_activity"]) == 6,
       "removidos os blocos [5396+]…[5396-] e desfeitas as substituições declaradas [5396~] (1 na 5269, 6 na 5388), cada função é IDÊNTICA ao canônico (assinatura, retorno, definer, search_path, lock_timeout, corpo)")
    ck("C3", all(defs[n] and md5(prosrc(defs[n])) == B.NEWMD5[n] for n in B.SRC), "10 funções com md5 = constantes do POST e do rollback")

    c4 = True
    for n in B.OWNER + B.EDITOR:
        d = defs[n] or ""
        bl = blocks(d)
        j = "\n".join(bl)
        body = re.sub(r"(?i)\bfor update\b", "", nolit(j))
        c4 = c4 and not re.search(r"(?i)\b(insert|update|delete|set_config|execute|grant|revoke|return)\b", body) \
            and set(re.findall(r"public\.([a-z0-9_]+)\s*\(", j)) <= {"v1_13_capability_open", "binder_activity_record_species"}
        i_w = d.rfind(WRITE[n])
        recs = [m.start() for m in re.finditer(re.escape(REC), d)]
        c4 = c4 and i_w > 0 and recs and min(recs) > i_w
    ck("C4", c4, "blocos só leem (FOR UPDATE) e chamam capability_open/record; todo registro vem depois da última escrita efetiva")
    c5 = True
    for n in B.OWNER + B.EDITOR:
        d = defs[n] or ""
        rb_ = [b for b in blocks(d) if REC in b]
        c5 = c5 and len(rb_) == 1 and sorted(set(re.findall(r"'(SPECIES_[A-Z_]+)'", rb_[0]))) == EVENTS[n]
    for n in B.OWNER:  # titular: só com a capacidade aberta para a sessão
        r0 = next((b for b in blocks(defs[n] or "") if REC in b), "")
        c5 = c5 and ("v1_13_capability_open()" in r0 or "if v_audit then" in r0)
    ap = defs["apply_my_binder_species_references"] or ""
    c5 = c5 and "v_audit := public.v1_13_capability_open();" in ap
    for n in ("apply_my_binder_species_references", "editor_apply_binder_species_references"):
        r0 = next((b for b in blocks(defs[n] or "") if REC in b), "")
        c5 = c5 and re.search(r"if (operation|v_op) = 'APPLIED' then\n\s+perform public\.binder_activity_record_species\([^;]*'SPECIES_REFERENCES_APPLIED', null\);\n\s+elsif not v_prev_visible then\n\s+perform public\.binder_activity_record_species\([^;]*'SPECIES_REFERENCES_SHOWN', null\);\n\s+end if;", r0) is not None
    for n in ("clear_my_binder_species_references", "editor_clear_binder_species_references"):
        r0 = next((b for b in blocks(defs[n] or "") if REC in b), "")
        c5 = c5 and re.match(r"\s*if v_removed > 0( and public\.v1_13_capability_open\(\))? then\n", r0) is not None
    ck("C5", c5, "um registro por função; tipos por operação; APPLIED, ou SHOWN só se estava oculta; CLEARED só com remoção > 0; titular sob capability_open")
    c6 = True
    for n, refs in REFUSALS.items():
        d = defs[n] or ""
        i_rec = d.find(REC)
        c6 = c6 and all(0 < d.find(x) < i_rec for x in refs)
    vo = defs["set_my_binder_species_reference_visibility"] or ""
    c6 = c6 and ordered(vo, "if coalesce(v_current, true) = p_visible then", "operation := 'UNCHANGED';", "  else\n", REC, "operation := 'UPDATED';")
    ve = defs["editor_set_binder_species_reference_visibility"] or ""
    c6 = c6 and ordered(ve, "'UNCHANGED'::text;\n    return;", REC, "'UPDATED'::text;")
    for n in B.EDITOR:
        c6 = c6 and ordered(defs[n] or "", "perform public.v1_13_assert_capability();", REC)
    ck("C6", c6, "recusas, UNCHANGED e saídas antes do registro; EDITOR: barreira exigida antes de tudo")

    rm = re.search(r"create function public\.binder_activity_record_species\((.*?)\$fn\$;", mig, re.S)
    rt = rm.group(0) if rm else ""
    ins = re.findall(r"(?i)insert\s+into\s+public\.([a-z_]+)", nc(rt))
    vals = re.search(r"values\s*\((.*?)\)\s*returning", rt, re.S)
    sums = re.findall(r"jsonb_build_object\(([^;]*?)\);", rt)
    keys = [sorted(re.findall(r"'([a-z_]+)',", s)) for s in sums]
    ck("R1", ordered(rt, "language plpgsql", "security definer", "set search_path = ''", "as $fn$")
       and "v_uid      uuid := (select auth.uid());" in rt and "raise exception 'not_authenticated'" in rt
       and ins == ["binder_activity_event"] and "binder_activity_item" not in rt
       and vals and "v_uid, p_event_type, 'FICHARIO'" in vals.group(1) and vals.group(1).rstrip().endswith("true")
       and "m.status = 'ACTIVE' and m.role = 'EDITOR'" in rt and "p_collection_id = v_main" in rt
       and "'BINDER_ACTIVITY_NESTED_SPECIES'" in rt
       and keys == [["first_number", "last_number", "reference_count", "visible"], ["removed_count"]]
       and sorted(set(re.findall(r"p_event_type = '([A-Z_]+)'", rt))) == sorted(B.SPECIES)
       and not re.search(PATRIMONIAL, " ".join(sums)) and "if v_sum is null then" in rt,
       "primitiva: definer, search_path vazio; autor = auth.uid() (titular ou EDITOR ACTIVE da dona do fichário); só INSERT no evento (sem itens); tipos e chaves fechados; sem ids patrimoniais; recusa aninhamento")
    grl = [re.sub(r"\s+", " ", x.strip()) for x in re.findall(r"(?im)^\s*(?:grant|revoke)\b[^;]*;", nc(mig))]
    ck("G1", grl == ["revoke all on function public.binder_activity_record_species(uuid, uuid, text, integer) from public, anon, authenticated, service_role;"],
       "privilégios: primitiva sem EXECUTE para nenhum papel de cliente; nenhuma outra concessão (CREATE OR REPLACE preserva ACL)")
    objs = re.findall(r"(?i)\bcreate(?:\s+or\s+replace)?\s+function\s+public\.([a-z0-9_]+)", nc(mig))
    ddl = re.findall(r"(?im)^\s*(alter|drop)\b[^;]*;", nc(mig))
    code = nc(mig)
    ck("G2", sorted(objs) == sorted(list(B.SRC) + ["binder_activity_record_species"])
       and [re.sub(r"\s+", " ", x.strip()) for x in re.findall(r"(?im)^\s*alter table[^;]*?(?:drop|add) constraint chk_bae_event_type", code)]
           == ["alter table public.binder_activity_event drop constraint chk_bae_event_type", "alter table public.binder_activity_event add constraint chk_bae_event_type"]
       and len(ddl) == 2
       and not re.search(r"get_shared_binder_activity_status|collection_activity_|get_collection_activity|create\s+trigger|create\s+table", code),
       "objetos: 10 funções (OR REPLACE) + primitiva + CHECK; _status da 5388 e fluxo 5394/5395 intocados")
    # --- D-5396-1: participante (5388)
    sh = defs["get_shared_binder_activity"] or ""
    shc = nc(sh)
    ck("V1", blocks(sh) == [f"        or (e.item_collection_recorded and e.source = 'FICHARIO' and e.collection_id = p_collection_id\n            and e.event_type in ({B.SPECIES_SQL}))"]
       and ordered(sh, "if not public.v1_13_capability_open() then return; end if;", "v_role := public.collection_share_role(p_collection_id);",
                   "if v_role is null or v_role not in ('OWNER', 'VIEWER') then", "where e.owner_user_id = v_owner", "and e.layout_key = v_layout",
                   "and (e.collection_id = p_collection_id", A, f"and (e.event_type in ({B.SPECIES_SQL}) or exists (", "order by e.occurred_at desc, e.id desc", "limit v_limit")
       and "summary" not in shc.split("returns table")[1].split("language")[0] and "pg.summary" not in shc and "e.summary" not in shc.replace("e.summary ->> 'item_key'", "")
       and "left join agg a on a.event_id = pg.id" in sh and "coalesce(a.items, '[]'::jsonb)" in sh,
       "5388: barreira, papel OWNER/VIEWER (ACTIVE pela 5302), titular e fichário de X preservados; SPECIES só atribuídos, FICHARIO e de X; exceção de item só para SPECIES; sem summary; ordem e cursor iguais")
    # --- D-5396-2: titular (5269)
    my = defs["get_my_binder_activity"] or ""
    ck("V2", B.REPL.get("get_my_binder_activity") == [(B.CAT_OLD, B.CAT_NEW + RM)] and (B.CAT_NEW + RM) in my
       and B.CAT_NEW.replace(",'SPECIES'", "") == B.CAT_OLD and "where e.owner_user_id = v_uid" in my
       and "public.binder_activity_category(e.event_type) = any (p_categories)" in my and not blocks(my),
       "5269: só a lista do filtro ganha 'SPECIES' (demais valores, sem filtro, isolamento por titular e colunas iguais)")
    # --- regra de tipos: por último, antes do postcheck
    i_alter = mig.find("alter table public.binder_activity_event drop constraint chk_bae_event_type;")
    ck("L1", "\nbegin;\nset local lock_timeout = '3s';\n" in mig and i_alter > max(mig.find(f"function public.{n}(") for n in B.SRC)
       and i_alter > mig.find("create function public.binder_activity_record_species(")
       and mig.find("do $post$") > i_alter and mig.count("alter table") == 2,
       "CHECK trocado por último (ACCESS EXCLUSIVE só até o commit), lock_timeout 3 s para toda a transação")
    cons = re.search(r"add constraint chk_bae_event_type check \(event_type in \((.*?)\)\);", mig, re.S)
    ck("T1", cons and re.findall(r"'([A-Z0-9_]+)'", cons.group(1)) == B.TYPES_5341 + B.SPECIES,
       "CHECK = os 25 tipos da 5341, na mesma ordem, + os 4 SPECIES_REFERENCES_*")
    g = defs["binder_activity_event_editor_type_guard"] or ""
    cat = defs["binder_activity_category"] or ""
    ck("T2", blocks(g) == [f"         or (new.event_type in ({B.SPECIES_SQL}) and new.source = 'FICHARIO')"]
       and blocks(cat) == [f"    when p_event_type in ({B.SPECIES_SQL.replace(', ', ',')}) then 'SPECIES'"],
       "gatilho do EDITOR: só os 4 tipos, origem FICHARIO (coleção obrigatória já existente); categoria SPECIES só para os 4")

    prem = re.search(r"do \$pre\$(.*?)\$pre\$;", mig, re.S)
    pst = re.search(r"do \$post\$(.*?)\$post\$;", mig, re.S)
    pt, qt = (prem.group(1) if prem else ""), (pst.group(1) if pst else "")
    ck("P1", all(h in pt for _, _, h in B.SRC.values()) and "'CLOSED'" in pt and "v1_13_barrier_identity" in pt
       and B.types_sql(B.TYPES_5341) in pt and "binder_activity_record_species(uuid, uuid, text, integer)') is not null" in pt
       and "relowner" in pt,
       "PRECHECK: barreira CLOSED, 10 corpos canônicos, CHECK da 5341, executor dono da tabela, primitiva ausente")
    ck("P2", all(h in qt for h in B.NEWMD5.values()) and B.types_sql(B.TYPES_5341 + B.SPECIES) in qt and "'authenticator'" in qt
       and "a.grantee = 0" in qt and "'SPECIES'" in qt and "trg_bae_editor_event_type" in qt and "'CLOSED'" in qt
       and "leituras deixaram de ser STABLE" in qt,
       "POSTCHECK: texto instrumentado, CHECK, ACL das 8 RPCs (6 escritas + 2 leituras), STABLE, primitiva sem EXECUTE, categoria, gatilho, nenhum evento, barreira")
    # --- 22P02 (STOP-LIVE run-20261127T151841Z): "lit = any ((select arr))" compara com CADA LINHA (subconsulta),
    # e o literal vira text[] → malformed array literal. Só pertencimento tipado ao proconfig.
    typed_mig = "array['search_path=\"\"'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[])"
    typed_post = "array['search_path=\"\"'::text] <@ coalesce(p.proconfig, array[]::text[])"
    ck("D1", not any(re.search(r"(?i)=\s*any\s*\(\s*\(\s*select", nolit(x)) for x in (mig, rb, pre, post))
       and not any(re.search(r"(?i)'search_path=\"\"'\s*=\s*any", x) for x in (mig, rb, pre, post))
       and qt.count(typed_mig) == 1 and post.count(typed_post) == 1,
       "22P02: nenhum 'x = any ((select …))'; search_path exigido por pertencimento tipado (text[] <@ proconfig) no postcheck e no POST")
    rbo = rb
    for n in B.SRC:
        rbo = rbo.replace(B.CANON[n], "")
    ck("RB1", all(B.CANON[n] in rb for n in B.SRC) and "drop function public.binder_activity_record_species(uuid, uuid, text, integer);" in rb
       and all(h in rb for h in B.NEWMD5.values()) and all(h in rb for _, _, h in B.SRC.values())
       and B.types_sql(B.TYPES_5341) in rb and B.types_sql(B.TYPES_5341 + B.SPECIES) in rb
       and re.search(r"do \$chk\$\nbegin\n  if not exists \(select 1 from public\.binder_activity_event e where e\.event_type in \([^)]*\)\) then\n    alter table", rb) is not None
       and not re.search(r"(?i)\b(grant|revoke|delete|truncate|insert|update)\b", nolit(rbo)) and A not in rb and RM not in rb,
       "rollback: exige texto 5396; restaura os 10 corpos canônicos; remove a primitiva; NUNCA apaga eventos; volta o CHECK da 5341 só sem eventos SPECIES (senão mantém o compatível); sem ACL")

    ck("K1", ro(pre) and ro(post), "PRE e POST passam no validador de somente leitura do executor (SELECT único)")
    ck("K2", pre.count(SIG) == 4 and post.count(SIG) == 4 and 'collate "C"' in pre and "'escritores_referencias'" in pre
       and "'escritores_preferencia'" in pre and not re.search(r"'escritores_[a-z_]+'", post) and "_md5'" not in pre + post
       and all(h in pre for _, _, h in B.SRC.values()) and all(h in post for h in B.NEWMD5.values()),
       "PRE: inventário por assinatura e corpos canônicos; POST: instrumentado e inventário booleano")
    try:
        ex = json.loads(exp)
    except ValueError:
        ex = {}
    ap_ = re.search(r"'inventario_referencias_pos',.*?\n\s*= '([^']+)'", post, re.S)
    sp_ = re.search(r"'inventario_preferencia_pos',.*?\n\s*= '([^']+)'", post, re.S)
    ck("K3", sorted(ex) == ["escritores_preferencia", "escritores_referencias"] and ap_ and sp_
       and ex["escritores_referencias"] == ap_.group(1).split(", ") == sorted(ex["escritores_referencias"], key=lambda s: s.encode())
       and ex["escritores_preferencia"] == sp_.group(1).split(", ") == sorted(ex["escritores_preferencia"], key=lambda s: s.encode())
       and len(ex["escritores_referencias"]) == 6 and len(ex["escritores_preferencia"]) == 4,
       "expectativas (6 + 4 assinaturas, ordem C) = inventário exigido no POST: nenhum escritor novo")
    live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_|[A-Za-z]:\\\\Users", re.I)
    ck("X1", not any(live.search(nc(x)) for x in (mig, rb, pre, post)), "nenhuma referência ao projeto, URL, credencial ou caminho privado")
    man = [l.split("|") for l in man_txt.splitlines() if l and not l.startswith("#")]
    okm = len(man) == 3 and [m[0] for m in man] == ["1", "2", "3"] and [m[3] for m in man] == ["gate", "write", "gate"]
    content = {os.path.basename(MIG): mig, os.path.basename(PRE): pre, os.path.basename(POST): post}
    for m in man if okm else []:
        base = os.path.basename(m[1].replace("\\", "/"))
        okm = okm and base in content and hashlib.sha256(content[base].encode("utf-8")).hexdigest() == m[2]
    ck("X2", okm and [os.path.basename(m[1].replace("\\", "/")) for m in man] == [os.path.basename(PRE), os.path.basename(MIG), os.path.basename(POST)],
       "manifesto: PRE (gate) → 5396 (write) → POST (gate), sha256 = arquivos")
    return R


FILES = dict(mig=rd(MIG), rb=rd(RB), pre=rd(PRE), post=rd(POST), exp=rd(EXP), man_txt=rd(MAN))
R = run(**FILES)
disk = [open(p, "rb").read() for p in (MIG, RB, PRE, POST, EXP, MAN)]
R.append(("X3", all(b"\r\n" not in d and not d.startswith(b"\xef\xbb\xbf") for d in disk), "arquivos em UTF-8 sem BOM e LF"))


def sub_in(t, fn, a, b=""):
    d = fn_def(t, fn)
    assert d and a in d, (fn, a[:60])
    return t.replace(d, d.replace(a, b, 1), 1)


def sub1(t, a, b):
    assert a in t, a[:70]
    return t.replace(a, b, 1)


def move_check(t):
    a = t.index("alter table public.binder_activity_event drop constraint chk_bae_event_type;")
    b = t.index("));", a) + 3
    blk = t[a:b]
    t = t[:a] + t[b:]
    return t.replace("set local lock_timeout = '3s';\n", "set local lock_timeout = '3s';\n" + blk + "\n", 1)


M = FILES["mig"]
MUT = [
    ("registro antes da escrita (titular remover)", "C4", dict(mig=sub_in(M, "clear_my_binder_species_references",
        "  delete from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;",
        "  perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_CLEARED', 1);\n  delete from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;"))),
    ("escrita dentro do bloco (EDITOR visibilidade)", "C4", dict(mig=sub_in(M, "editor_set_binder_species_reference_visibility",
        "  perform public.binder_activity_record_species(t.layout_id, p_collection_id,", "  delete from public.binder_activity_event;\n  perform public.binder_activity_record_species(t.layout_id, p_collection_id,"))),
    ("titular sem barreira (remover)", "C5", dict(mig=sub_in(M, "clear_my_binder_species_references", " and public.v1_13_capability_open()", ""))),
    ("titular sem barreira (visibilidade)", "C5", dict(mig=sub_in(M, "set_my_binder_species_reference_visibility", "    if public.v1_13_capability_open() then\n", "    if true then\n"))),
    ("ALREADY_APPLIED sempre registra SHOWN", "C5", dict(mig=sub_in(M, "editor_apply_binder_species_references", "elsif not v_prev_visible then", "else"))),
    ("remoção de 0 registra", "C5", dict(mig=sub_in(M, "editor_clear_binder_species_references", "if v_removed > 0 then", "if v_removed >= 0 then"))),
    ("tipo trocado", "C5", dict(mig=sub_in(M, "clear_my_binder_species_references", "'SPECIES_REFERENCES_CLEARED'", "'SPECIES_REFERENCES_HIDDEN'"))),
    ("registro também no UNCHANGED (titular)", "C6", dict(mig=sub_in(M, "set_my_binder_species_reference_visibility", "    operation := 'UNCHANGED';",
        "    perform public.binder_activity_record_species(v_layout, p_collection_id, 'SPECIES_REFERENCES_SHOWN', null);\n    operation := 'UNCHANGED';"))),
    ("corpo canônico alterado fora dos marcadores", "C2", dict(mig=sub_in(M, "editor_clear_binder_species_references", "and r.collection_id = p_collection_id;\n  get", "; \n  get"))),
    ("barreira removida do EDITOR", "C2", dict(mig=sub_in(M, "editor_apply_binder_species_references", "  perform public.v1_13_assert_capability();  -- G1 (D-E1)\n", ""))),
    ("primitiva aceita autor por parâmetro", "R1", dict(mig=sub1(M, "    (v_owner, p_layout_id, v_uid, p_event_type, 'FICHARIO',", "    (v_owner, p_layout_id, p_collection_id, p_event_type, 'FICHARIO',"))),
    ("primitiva aceita EDITOR de convidada", "R1", dict(mig=sub1(M, "     and not (p_collection_id = v_main\n              and exists", "     and not (true\n              and exists"))),
    ("primitiva grava item", "R1", dict(mig=sub1(M, "  returning id into v_id;\n  return v_id;", "  returning id into v_id;\n  insert into public.binder_activity_item (event_id, ordinal, item_kind, effect) values (v_id, 1, 'BINDER', 'CLOSED');\n  return v_id;"))),
    ("resumo com id patrimonial", "R1", dict(mig=sub1(M, "jsonb_build_object('removed_count', p_removed_count)", "jsonb_build_object('removed_count', p_removed_count, 'slot_id', p_layout_id)"))),
    ("primitiva sem recusa de aninhamento", "R1", dict(mig=sub1(M, "hint = 'BINDER_ACTIVITY_NESTED_SPECIES'", "hint = 'X'"))),
    ("primitiva para authenticated", "G1", dict(mig=sub1(M, "from public, anon, authenticated, service_role;\n\n", "from public, anon, service_role;\n\n"))),
    ("GRANT extra", "G1", dict(mig=sub1(M, "\ndo $post$", "\ngrant execute on function public.binder_activity_record_species(uuid, uuid, text, integer) to authenticated;\n\ndo $post$"))),
    ("leitura 5388 alterada", "G2", dict(mig=sub1(M, "\ndo $post$", "\ncomment on function public.get_shared_binder_activity_status(uuid) is 'x';\n\ndo $post$"))),
    ("CHECK perde um tipo existente", "T1", dict(mig=sub1(M, "    'CARDS_AUTO_ARRANGED',\n    'SPECIES", "    'SPECIES"))),
    ("gatilho do EDITOR liberado para CATALOGO", "T2", dict(mig=sub_in(M, "binder_activity_event_editor_type_guard", "'SPECIES_REFERENCES_HIDDEN') and new.source = 'FICHARIO')", "'SPECIES_REFERENCES_HIDDEN'))"))),
    ("precheck sem barreira", "P1", dict(mig=sub1(M, "is distinct from 'CLOSED'", "is distinct from 'OPEN'"))),
    ("rollback volta o CHECK antigo mesmo com eventos", "RB1", dict(rb=sub1(FILES["rb"], "  if not exists (select 1 from public.binder_activity_event e where e.event_type in", "  if true or exists (select 1 from public.binder_activity_event e where e.event_type in"))),
    ("rollback apaga eventos", "RB1", dict(rb=sub1(FILES["rb"], "\ndrop function public.binder_activity_record_species", "\ndelete from public.binder_activity_event where event_type like 'SPECIES%';\ndrop function public.binder_activity_record_species"))),
    ("5388: SPECIES de qualquer coleção", "V1", dict(mig=sub1(M, "e.source = 'FICHARIO' and e.collection_id = p_collection_id\n            and e.event_type in", "e.source = 'FICHARIO'\n            and e.event_type in"))),
    ("5388: SPECIES sem atribuição", "V1", dict(mig=sub1(M, "        or (e.item_collection_recorded and e.source = 'FICHARIO' and e.collection_id", "        or (true and e.source = 'FICHARIO' and e.collection_id"))),
    ("5388: exceção de item para todos os tipos", "C2", dict(mig=sub1(M, "      and (e.event_type in ('SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_SHOWN', 'SPECIES_REFERENCES_HIDDEN') or exists (  -- [5396~]", "      and (true or exists (  -- [5396~]"))),
    ("5388: summary exposto", "V1", dict(mig=sub_in(M, "get_shared_binder_activity", "         coalesce(a.items, '[]'::jsonb),", "         coalesce(a.items, '[]'::jsonb) || jsonb_build_array(e.summary),"))),
    ("5388: sem papel", "C2", dict(mig=sub_in(M, "get_shared_binder_activity", "  if v_role is null or v_role not in ('OWNER', 'VIEWER') then\n    return;\n  end if;\n", ""))),
    ("5388: sem barreira", "V1", dict(mig=sub_in(M, "get_shared_binder_activity", "  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)\n", ""))),
    ("5269: filtro perde um valor", "V2", dict(mig=sub_in(M, "get_my_binder_activity", "'CATALOG','BINDER','SPECIES']", "'CATALOG','SPECIES']"))),
    ("CHECK trocado antes das funções", "L1", dict(mig=move_check(M))),
    ("rollback com corpo diferente do canônico", "RB1", dict(rb=sub1(FILES["rb"], "operation := 'UNCHANGED';", "operation := 'UPDATED';"))),
    ("PRE com escrita", "K1", dict(pre=sub1(FILES["pre"], ") as s4c_5396_pre;", ") as s4c_5396_pre; delete from public.binder_activity_event;"))),
    ("POST aceita escritor novo", "K3", dict(post=sub1(FILES["post"], "public.remove_layout_page(uuid,integer)'", "public.remove_layout_page(uuid,integer), public.x()'"))),
    ("22P02: expressão defeituosa reintroduzida no postcheck", "D1", dict(mig=sub1(M, "or not (array['search_path=\"\"'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))", "or not ('search_path=\"\"' = any ((select p.proconfig from pg_catalog.pg_proc p where p.oid = f)))"))),
    ("22P02: POST com igualdade sem tipo", "D1", dict(post=sub1(FILES["post"], "array['search_path=\"\"'::text] <@ coalesce(p.proconfig, array[]::text[])", "'search_path=\"\"' = any (p.proconfig)"))),
    ("postcheck sem exigir search_path", "D1", dict(mig=sub1(M, "       or not (array['search_path=\"\"'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))\n", ""))),
    ("manifesto com hash errado", "X2", dict(man_txt=re.sub(r"\|([0-9a-f]{64})\|write", "|" + "0" * 64 + "|write", FILES["man_txt"]))),
]
mut_ok = []
for name, target, change in MUT:
    args = dict(FILES)
    args.update(change)
    res = {cid: ok for cid, ok, _ in run(**args, gen=False)}
    mut_ok.append((name, target, res.get(target) is False))
R.append(("MUT", all(x[2] for x in mut_ok), f"{sum(x[2] for x in mut_ok)}/{len(mut_ok)} mutações reprovadas pelo controle-alvo"))

fails = [r for r in R if not r[1]]
for cid, ok, detail in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:4} {detail}")
for name, target, killed in mut_ok:
    print(f"      {'morta' if killed else 'VIVA '}  [{target}] {name}")
print(f"\nSTATIC CHECK 5396: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
