#!/usr/bin/env python3
"""
V1-13 · E3-6 / S2 — verificação ESTÁTICA da 5392, ROLLBACK_5392, PRE/POST, expectativas e manifesto.

Sem banco. Prova só propriedades do TEXTO (STD-005): forma; md5 das dependências = corpos
canônicos; só objetos novos; definer + search_path vazio; privilégios (4 RPCs para authenticated,
resolvedor interno, 5380 revogada); em cada RPC a ordem barreira → autorização com trava → época →
identificador → trava da alocação → trava da representante → comparação com o estado esperado →
collection_activity_open → escrita → collection_activity_record_pokedex; UNCHANGED e recusas antes
de open e sem evento; um registro por resultado efetivo; nenhuma identidade física na interface;
inventário por assinatura completa. NÃO prova execução nem comportamento.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s2-pokedex-collaborative-editing/static_check_5392.py
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
PROT = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1", "protected")
G1 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1")
MIG = os.path.join(HERE, "5392_create_editor_pokedex_copy_writes.sql")
RB = os.path.join(HERE, "ROLLBACK_5392.sql")
PRE = os.path.join(HERE, "S2_5392_PRE_readonly.sql")
POST = os.path.join(HERE, "S2_5392_POST_readonly.sql")
EXP = os.path.join(HERE, "S2_5392_EXPECTATIVAS.json")
MAN = os.path.join(HERE, "S2_5392_MANIFEST.txt")
R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def nolit(t):
    return re.sub(r"'(?:[^']|'')*'", "''", nc(t))


def prosrc(text, name):
    t = text[text.lower().index("\nbegin;") + 1:] if "\nbegin;" in text.lower() else text
    m = re.search(r"create\s+(or\s+replace\s+)?function\s+public\." + re.escape(name) + r"\s*\(", t, re.I)
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", t[m.end():], re.I)
    s = m.end() + a.end()
    return t[s:t.index(a.group(1), s)]


def balanced(t):
    t = nolit(t)
    d = 0
    for ch in t:
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


def ordered(s, *subs):  # todas presentes e em ordem crescente (sem exceção)
    pos = [s.find(x) for x in subs]
    return all(p >= 0 for p in pos) and pos == sorted(pos) and len(set(pos)) == len(pos)
mig, rb, pre, post = rd(MIG), rd(RB), rd(PRE), rd(POST)
code = nc(mig)
body = mig[mig.index("\nbegin;\n") + 1:]

head = mig[:mig.index("\nbegin;\n")].strip()
check("H0", head.startswith("/*") and head.endswith("*/") and head.count("*/") == 1 and head.count("/*") == 1,
      "cabeçalho = um único comentário de bloco (lição 5388)")
check("S0", all(balanced(x) for x in (mig, rb, pre, post)) and code.count("$fn$") % 2 == 0
      and code.count("$pre$") == 2 and code.count("$post$") == 2, "aspas, parênteses e $…$ balanceados (NÃO substitui compilação)")

canon = {
    ("assert_collection_editor", "(uuid)"): (os.path.join(PROT, "5376_create_editor_collection_metadata_writes.sql"), None),
    ("editor_pokedex_of_collection", "(uuid)"): (os.path.join(PROT, "5380_create_editor_pokedex_position_writes.sql"), None),
    ("editor_set_pokedex_position_assignment", "(uuid, uuid, uuid, boolean)"): (os.path.join(PROT, "5380_create_editor_pokedex_position_writes.sql"), None),
    ("editor_remove_pokedex_position_assignment", "(uuid, uuid)"): (os.path.join(PROT, "5380_create_editor_pokedex_position_writes.sql"), None),
    ("editor_set_pokedex_position_primary_representative", "(uuid, uuid)"): (os.path.join(PROT, "5380_create_editor_pokedex_position_writes.sql"), None),
    ("editor_clear_pokedex_position_primary_representative", "(uuid, uuid)"): (os.path.join(PROT, "5380_create_editor_pokedex_position_writes.sql"), None),
    ("v1_13_pokedex_copy_token", "(uuid, uuid, bigint)"): (os.path.join(SCHEMA, "5391_create_editor_pokedex_copy_identity_and_read.sql"), None),
    ("v1_13_editor_membership", "(uuid)"): (os.path.join(SCHEMA, "5391_create_editor_pokedex_copy_identity_and_read.sql"), None),
    ("collection_activity_open", "(uuid)"): (os.path.join(SCHEMA, "5394_create_collection_activity_audit_infrastructure.sql"), None),
    ("collection_activity_record_pokedex", "(uuid, text, uuid, uuid, uuid, uuid, text, boolean)"): (os.path.join(SCHEMA, "5394_create_collection_activity_audit_infrastructure.sql"), None),
    ("set_pokedex_position_assignment", "(uuid, uuid, boolean)"): (os.path.join(SCHEMA, "6123_fix_fatia_d_applied_objects_pause_sql_direct_audit.sql"), None),
    ("remove_pokedex_position_assignment", "(uuid)"): (os.path.join(SCHEMA, "6124_create_remove_pokedex_position_assignment_function.sql"), None),
    ("set_pokedex_position_primary_representative", "(uuid)"): (os.path.join(SCHEMA, "6126_fix_primary_representative_on_conflict_ambiguity.sql"), None),
    ("clear_pokedex_position_primary_representative", "(uuid, uuid)"): (os.path.join(SCHEMA, "6125_create_primary_representative_functions.sql"), None),
    ("v1_13_assert_capability", "()"): (os.path.join(G1, "5389_create_v1_13_capability_barrier.sql"), None),
    ("v1_13_capability_open", "()"): (os.path.join(G1, "5389_create_v1_13_capability_barrier.sql"), None),
}
check("C0", md5(prosrc(rd(canon[("assert_collection_editor", "(uuid)")][0]), "assert_collection_editor")) == "9a7482588b5c7995f40a5d945c957f31",
      "extrator de prosrc reproduz md5 já fixado (assert_collection_editor, S1)")
bad = []
for (fn, sig), (path, _) in canon.items():
    h = md5(prosrc(rd(path), fn))
    pat = re.escape(f"to_regprocedure('public.{fn}{sig}')")
    found = []
    for t in (code, nc(rb), nc(pre), nc(post)):
        found += re.findall(pat + r"\)\s*is distinct from\s*'([0-9a-f]{32})'", t) + re.findall(pat + r"\)\s*=\s*'([0-9a-f]{32})'", t)
    if not found or any(x != h for x in found):
        bad.append(fn)
check("C1", not bad, "md5 de todas as dependências (5376, 5380, 5389, 5391, 5394, titular) = corpos canônicos" + (f" — divergem: {bad}" if bad else ""))

check("M1", body.count("begin;") == 1 and body.rstrip().endswith("commit;") and "set local lock_timeout = '3s';" in body, "uma transação, lock_timeout 3 s")
RPCS = ["editor_move_pokedex_copy", "editor_unassign_pokedex_copy", "editor_choose_pokedex_representative", "editor_restore_pokedex_automatic_representative"]
created = sorted(re.findall(r"create function public\.([a-z0-9_]+)\(", code))
check("M2", created == sorted(RPCS + ["v1_13_resolve_pokedex_copy", "v1_13_pokedex_position_in_scope"]) and "or replace" not in code.lower()
      and not re.search(r"\b(drop|alter|create\s+(table|trigger|index|sequence))\b", code, re.I),
      "só 6 funções novas; nenhum CREATE OR REPLACE, DROP, ALTER, tabela, gatilho ou índice")


def fbody(name):
    i = code.index(f"create function public.{name}(")
    return code[i:code.index("\n$fn$;", i)]


blocks = {n: fbody(n) for n in created}
check("M3", all("security definer" in b and "set search_path = ''" in b for b in blocks.values())
      and all("\nvolatile\n" in blocks[n] for n in RPCS) and "\nstable\n" in blocks["v1_13_resolve_pokedex_copy"] and "\nstable\n" in blocks["v1_13_pokedex_position_in_scope"],
      "todas SECURITY DEFINER, search_path vazio; RPCs VOLATILE, resolvedor STABLE")
grants = re.findall(r"grant execute on function public\.([a-z0-9_]+)\([^)]*\) to ([a-z_]+);", code)
r5380 = ["editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)", "editor_remove_pokedex_position_assignment(uuid, uuid)",
         "editor_set_pokedex_position_primary_representative(uuid, uuid)", "editor_clear_pokedex_position_primary_representative(uuid, uuid)"]
check("M4", sorted(grants) == sorted((n, "authenticated") for n in RPCS)
      and "revoke all on function public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid) from public, anon, authenticated, service_role;" in code
      and "revoke all on function public.v1_13_pokedex_position_in_scope(uuid, uuid) from public, anon, authenticated, service_role;" in code
      and all(f"revoke execute on function public.{s} from public, anon, authenticated, service_role;" in code for s in r5380),
      "4 GRANTs só para authenticated; resolvedor sem EXECUTE para a API; 4 escritas da 5380 revogadas de todos os papéis de cliente")

order_ok, audit_ok, unch_ok = [], [], []
effective = {"editor_move_pokedex_copy": ["CREATED", "MOVED"], "editor_unassign_pokedex_copy": ["REMOVED"],
             "editor_choose_pokedex_representative": ["SET", "REPLACED"], "editor_restore_pokedex_automatic_representative": ["CLEARED"]}
for n in RPCS:
    b = blocks[n][blocks[n].index("\nbegin\n") + len("\nbegin\n"):]
    seq = ["perform public.v1_13_assert_capability();", "perform public.assert_collection_editor(p_collection_id);",
           "from public.v1_13_editor_membership(p_collection_id) em;"]
    pos = [b.find(x) for x in seq]
    i_open = b.find("perform public.collection_activity_open(p_collection_id);")
    writes = [m.start() for m in re.finditer(r"(insert into|delete from) public\.collection_pokedex_position_(assignment|primary_representative)", b)]
    recs = [m.start() for m in re.finditer(r"perform public\.collection_activity_record_pokedex\(", b)]
    rets = {op: b.find(f"return query select '{op}'::text") for op in effective[n]}
    unchanged = b.find("return query select 'UNCHANGED'::text")
    raises = [m.start() for m in re.finditer(r"raise exception '(STATE_CHANGED|COPY_NOT_FOUND|CONFIRMATION_REQUIRED|POKEDEX_POSITION_NOT_FOUND|INVALID_ARGUMENT)'", b)]
    resolve = b.find("v1_13_resolve_pokedex_copy(")
    lock_alloc = b.find("for update;")
    order_ok.append(b.lstrip().startswith("perform public.v1_13_assert_capability();") and all(p >= 0 for p in pos) and pos == sorted(pos)
                    and (n == "editor_restore_pokedex_automatic_representative" or (pos[2] < resolve < lock_alloc)))
    audit_ok.append(i_open > 0 and writes and all(i_open < w for w in writes) and len(recs) == len(effective[n])
                    and all(max(writes) < r for r in recs) and all(rets[op] > 0 for op in rets)
                    and sorted(recs) == recs and all(r < rets[op] for r, op in zip(recs, effective[n])))
    unch_ok.append(0 < unchanged < i_open and all(r < i_open for r in raises) and b.count("collection_activity_open") == 1)
check("M5", all(order_ok), "cada RPC: barreira 1ª → assert_collection_editor (trava) → época vigente → identificador → trava da alocação")
check("M6", all(audit_ok), "cada RPC: collection_activity_open antes de toda escrita; um record_pokedex por resultado efetivo, depois das escritas e antes do retorno")
check("M7", all(unch_ok), "UNCHANGED e todas as recusas (STATE_CHANGED, COPY_NOT_FOUND, CONFIRMATION_REQUIRED…) antes de open — sem evento")
mv = blocks["editor_move_pokedex_copy"]
check("M8", ordered(mv, "return query select 'UNCHANGED'::text", "raise exception 'STATE_CHANGED'", "raise exception 'CONFIRMATION_REQUIRED'")
      and ordered(mv, "select exists (select 1 from public.collection_pokedex_position_primary_representative r", "delete from public.collection_pokedex_position_assignment"),
      "mover: UNCHANGED antes do estado esperado, que vem antes da espécie (6122 v1.1); cascata da representante medida antes do DELETE")
ch = blocks["editor_choose_pokedex_representative"]
check("M9", ordered(ch, "for update;", "from public.collection_pokedex_position_primary_representative r\n  where r.collection_id = p_collection_id and r.pokedex_position_id = v_cur\n  for update;")
      and "if p_expected_representative_token is null then" in ch and "v_exp is distinct from v_prev" in ch
      and "v_exp is distinct from v_prev" in blocks["editor_restore_pokedex_automatic_representative"],
      "travas na ordem alocação → representante; representante esperada comparada (NULL = automática)")
_st = "if v_cur is distinct from p_expected_position_id then\n    raise exception 'STATE_CHANGED' using errcode = '22023';"
check("M13", all(ordered(blocks[n], _st, "perform public.collection_activity_open(p_collection_id);") for n in ("editor_move_pokedex_copy", "editor_unassign_pokedex_copy", "editor_choose_pokedex_representative"))
      and all("v_exp is distinct from v_prev then\n      raise exception 'STATE_CHANGED'" in blocks[n] or "v_exp is distinct from v_prev then\n    raise exception 'STATE_CHANGED'" in blocks[n]
              for n in ("editor_choose_pokedex_representative", "editor_restore_pokedex_automatic_representative")),
      "estado esperado (posição e representante) comparado em toda RPC, depois das travas e antes de open; diferença → STATE_CHANGED")
sc = blocks["v1_13_pokedex_position_in_scope"]
check("M14", all(x in sc for x in ("cpr.scope_kind = 'FULL_REFERENCE'", "public.collection_pokedex_scope_generation sg",
                                    "sg.collection_reference_id = cr.id and sg.generation_id = s.generation_id", "pp.pokedex_id = cpr.pokedex_id",
                                    "c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION'"))
      and ordered(blocks["editor_move_pokedex_copy"], "v1_13_pokedex_position_in_scope(p_collection_id, p_target_position_id)", "perform public.collection_activity_open(")
      and ordered(blocks["editor_choose_pokedex_representative"], "raise exception 'STATE_CHANGED'", "v1_13_pokedex_position_in_scope(p_collection_id, v_cur)",
                  "for update;\n  if v_prev is not distinct from v_alloc", "perform public.collection_activity_open(")
      and ordered(blocks["editor_restore_pokedex_automatic_representative"], "v1_13_pokedex_position_in_scope(p_collection_id, p_pokedex_position_id)", "for update;", "perform public.collection_activity_open(")
      and "pp.pokedex_id = v_dex" not in blocks["editor_restore_pokedex_automatic_representative"],
      "posição restrita ao escopo de gerações (mesmo critério da leitura 5391) em mover, escolher e restaurar, antes das travas da representante e de open")
mark_ok = []
for n in RPCS:
    b = blocks[n]
    i_open = b.find("perform public.collection_activity_open(")
    recs = [m.start() for m in re.finditer(r"perform public\.collection_activity_record_pokedex\(", b)]
    seg = b[i_open:min(recs)] if i_open >= 0 and recs else ""
    mark_ok.append(i_open >= 0 and recs and b.count("collection_activity_open(") == 1 and re.search(r"\breturn\b|raise exception", seg) is None
                   and all(re.search(r"\breturn\b", b[i_open:r]) is None or b[i_open:r].count("return query select") <= k for k, r in enumerate(recs)))
check("M15", all(mark_ok),
      "marcação de auditoria: um open por RPC; nenhum return nem raise entre open e o primeiro record (erro posterior aborta a transação inteira)")
sigs = {n: blocks[n][:blocks[n].index("returns table")] for n in RPCS}
rets_cols = {n: blocks[n][blocks[n].index("returns table"):blocks[n].index("\nlanguage plpgsql")] for n in RPCS}
check("M10", all(re.search(r"physical_card|allocation|membership|epoch", s) is None for s in sigs.values())
      and all(re.search(r"physical|allocation|membership|token|epoch|owner|user", c) is None for c in rets_cols.values()),
      "interface sem identidade física, alocação, participação ou época (entrada só por identificador opaco)")
rs = blocks["v1_13_resolve_pokedex_copy"]
check("M11", "p_token !~ '^pc1\\.[0-9a-f]{64}$'" in rs and rs.count("where ca.collection_id = p_collection_id") == 3
      and rs.count("public.v1_13_pokedex_copy_token(ca.id, p_membership_id, p_role_epoch) = p_token") == 3
      and ordered(rs, "if p_hint_position_id is not null then", "if v_alloc is null then"),
      "resolvedor: formato pc1 validado; escopo esperado primeiro, depois a coleção; sempre limitado a X e à época vigente")
pc = code[code.index("do $post$"):]
check("M12", all(x in pc for x in ("provolatile", "has_function_privilege('service_role', f, 'EXECUTE') is not false", "a.grantee = 0",
                                    "escrita da 5380 ainda executável", "a migration não deveria gerar eventos", "barreira não está CLOSED")),
      "postcheck: RPCs, resolvedor interno, 5380 revogada para papéis de cliente, sem eventos, barreira")
rbc = nc(rb)
ALLF = RPCS + ["v1_13_resolve_pokedex_copy", "v1_13_pokedex_position_in_scope"]
check("R1", sorted(re.findall(r"drop function public\.([a-z0-9_]+)\(", rbc)) == sorted(ALLF)
      and re.search(r"\bgrant\b", rbc, re.I) is None and "a reversão não pode reativá-la" in rbc
      and re.search(r"\b(insert|update|delete)\b", nolit(rbc), re.I) is None,
      "rollback SEGURO: remove as 6 funções, NÃO concede nada; postcheck exige a 5380 ainda revogada para todo papel de cliente")
XR = rd(os.path.join(HERE, "RESTORE_5380_EXCECAO_5392.sql"))
check("R2", "EXCEÇÃO — NÃO É ROLLBACK" in XR and "5392 presente" in nc(XR) and "barreira não está CLOSED" in nc(XR)
      and sorted(re.findall(r"grant execute on function public\.([a-z0-9_]+)\(", nc(XR))) == sorted(s.split("(")[0] for s in r5380)
      and re.search(r"\b(revoke|drop|insert|update|delete)\b", nolit(XR), re.I) is None,
      "restauração da 5380 só em arquivo EXCEPCIONAL separado: exige 5392 ausente e barreira CLOSED; só os 4 GRANTs")
EM = nc(rd(os.path.join(HERE, "EMERGENCY_STOP_V1_13_ADD_S2.sql")))
em_rev = sorted(re.findall(r"revoke execute on function public\.([a-z0-9_]+)\([^)]*\) from public, anon, authenticated;", EM))
check("E1", em_rev == sorted(RPCS + ["get_editor_pokedex_position_copies"]) and re.search(r"\bgrant\b", EM, re.I) is None
      and "get_shared_collection_binder_pages_with_species" not in EM and "editor_set_pokedex_position_assignment" not in EM
      and EM.count("begin;") == 1 and EM.count("commit;") == 1,
      "emergência E2b: revoga as 4 RPCs da 5392 e a leitura da 5391; nenhum GRANT; não reativa a 5380; não toca a 5393")
check("K1", ro(pre) and ro(post), "PRE e POST passam no validador de somente leitura do executor (SELECT único)")
SIG = "n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')'"
check("K2", pre.count(SIG) == 4 and "'escopo_geracoes_presente'" in pre and "'v1_13_pokedex_position_in_scope'" in pre and "'ajudantes_internos'" in post and 'collate "C"' in pre and "'escritores_atribuicao'" in pre and "'escritores_representante'" in pre
      and not re.search(r"'escritores_[a-z_]+'", post) and "'inventario_atribuicao_pos'" in post,
      "PRE: inventário por ASSINATURA completa (ordem C); POST sem chaves escritores_* (o inventário pós-5392 é booleano)")
exp = json.load(open(EXP, encoding="utf-8"))
after_a = re.search(r"= '([^']+)',\n  'inventario_representante_pos'", post)
after_r = re.search(r"= '([^']+)',\n  'titular_canonico'", post)
names = lambda lst: [s.split(".", 1)[1].split("(")[0] for s in lst]
exp91 = json.load(open(os.path.join(HERE, "S2_5391_EXPECTATIVAS.json"), encoding="utf-8"))
new_a = ["public.editor_move_pokedex_copy(uuid,text,uuid,uuid,boolean)", "public.editor_unassign_pokedex_copy(uuid,text,uuid)"]
new_r = ["public.editor_choose_pokedex_representative(uuid,text,uuid,text)", "public.editor_restore_pokedex_automatic_representative(uuid,uuid,text)"]
check("K3", sorted(exp) == ["escritores_atribuicao", "escritores_representante"]
      and names(exp["escritores_atribuicao"]) == exp91["escritores_atribuicao"] and names(exp["escritores_representante"]) == exp91["escritores_representante"]
      and after_a and after_r
      and after_a.group(1).split(", ") == sorted(exp["escritores_atribuicao"] + new_a, key=lambda s: s.encode())
      and after_r.group(1).split(", ") == sorted(exp["escritores_representante"] + new_r, key=lambda s: s.encode()),
      "expectativas = inventário confirmado no LIVE (mesmos nomes, por assinatura); POST = antes + as 4 RPCs novas, em ordem C")
live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_", re.I)
check("X1", not any(live.search(nc(x)) for x in (mig, rb, pre, post)), "nenhuma referência ao projeto, URL ou credencial")
man = [l.split("|") for l in rd(MAN).splitlines() if l and not l.startswith("#")]
okm = [m[0] for m in man] == ["1", "2", "3"] and [m[3] for m in man] == ["gate", "write", "gate"]
for m in man:
    p = os.path.join(ROOT, *m[1].split("\\"))
    okm = okm and os.path.isfile(p) and hashlib.sha256(open(p, "rb").read()).hexdigest() == m[2]
check("X2", okm and [os.path.basename(m[1].replace("\\", "/")) for m in man] == [os.path.basename(PRE), os.path.basename(MIG), os.path.basename(POST)],
      "manifesto: PRE (gate) → 5392 (write) → POST (gate), sha256 = arquivos")

fails = [r for r in R if not r[1]]
for cid, ok, detail in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:4} {detail}")
print(f"\nSTATIC CHECK 5392: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
