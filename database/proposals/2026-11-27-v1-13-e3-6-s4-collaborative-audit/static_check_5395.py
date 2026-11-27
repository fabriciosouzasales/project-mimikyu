#!/usr/bin/env python3
"""
V1-13 · E3-6 / S4-b — verificação ESTÁTICA da 5395, ROLLBACK_5395, PRE/POST, expectativas,
complemento de emergência E2c e manifesto, com testes de MUTAÇÃO dos controles críticos.

Sem banco. Prova só propriedades do TEXTO (STD-005): reprodutibilidade a partir do canônico;
removidos os blocos [5395+]…[5395-], cada função do titular é IDÊNTICA ao texto implantado
(6123/6124/6126/6125, md5 do LIVE); blocos só leem e chamam as primitivas da 5394; open antes da
primeira escrita e record depois da escrita efetiva, ambos sob v1_13_capability_open(); um registro
por função; leitura do histórico com barreira, papel por collection_share_role e sem identificadores
patrimoniais; privilégios; rollback volta ao canônico; PRE/POST somente leitura; inventário de
escritores inalterado. NÃO prova execução nem comportamento.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s4-collaborative-audit/static_check_5395.py
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
S2 = os.path.join(ROOT, "database", "proposals", "2026-11-27-v1-13-e3-6-s2-pokedex-collaborative-editing")
MIG = os.path.join(HERE, "5395_instrument_owner_pokedex_audit_and_activity_read.sql")
RB = os.path.join(HERE, "ROLLBACK_5395.sql")
PRE = os.path.join(HERE, "S4B_5395_PRE_readonly.sql")
POST = os.path.join(HERE, "S4B_5395_POST_readonly.sql")
EXP = os.path.join(HERE, "S4B_5395_EXPECTATIVAS.json")
MAN = os.path.join(HERE, "S4B_5395_MANIFEST.txt")
EMF = os.path.join(HERE, "EMERGENCY_STOP_V1_13_ADD_S4.sql")
A, Z = "-- [5395+]", "-- [5395-]"


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
    m = re.search(r"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\." + re.escape(name) + r"\s*\(", t)
    if not m:
        return None
    a = re.search(r"\bAS\s+(\$[a-z_]*\$)", t[m.end():])
    s = m.end() + a.end()
    e = t.index(a.group(1), s) + len(a.group(1))
    return t[m.start():e] + ";"


def prosrc(d):
    a = re.search(r"\b(?:AS|as)\s+(\$[a-z_]*\$)", d)
    s = a.end()
    return d[s:d.index(a.group(1), s)]


def strip_marked(t):
    return re.sub(re.escape(A) + r"\n.*?\n" + re.escape(Z) + r"\n?", "", t, flags=re.S)


def blocks(t):
    return re.findall(re.escape(A) + r"\n(.*?)\n" + re.escape(Z), t, flags=re.S)


def rb_outside(rb):  # rollback sem os 4 corpos canônicos (que têm suas próprias escritas)
    for n in B.SIGS:
        rb = rb.replace(B.CANON[n], "")
    return rb


# ------------------------------------------------------------------ gerador (sem escrever no pacote)
spec = importlib.util.spec_from_file_location("build_5395", os.path.join(HERE, "build_5395.py"))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)
with tempfile.TemporaryDirectory() as td:
    B.HERE = td
    GEN_MIG, GEN_RB = B.build()

WRITE = {  # primeira e última escrita efetiva (âncoras do texto canônico)
    "set_pokedex_position_assignment": ("DELETE FROM public.collection_pokedex_position_assignment", "assignment.assigned_at;"),
    "remove_pokedex_position_assignment": ("DELETE FROM public.collection_pokedex_position_assignment", "_NOT_FOUND: nenhuma Assignment existente"),
    "set_pokedex_position_primary_representative": ("INSERT INTO public.collection_pokedex_position_primary_representative", "primary_representative.collection_allocation_id;"),
    "clear_pokedex_position_primary_representative": ("DELETE FROM public.collection_pokedex_position_primary_representative", "_NOT_FOUND: nenhum Primary Representative"),
}
EVENTS = {
    "set_pokedex_position_assignment": {"POKEDEX_POSITION_ASSIGNED", "POKEDEX_POSITION_MOVED"},
    "remove_pokedex_position_assignment": {"POKEDEX_POSITION_REMOVED"},
    "set_pokedex_position_primary_representative": {"POKEDEX_REPRESENTATIVE_SET", "POKEDEX_REPRESENTATIVE_REPLACED"},
    "clear_pokedex_position_primary_representative": {"POKEDEX_REPRESENTATIVE_RESTORED"},
}
OUT_COLS = ["event_id bigint", "occurred_at timestamptz", "event_type text", "origin text", "actor_role text",
            "actor_display_name text", "summary jsonb"]
PATRIMONIAL = r"physical_card|collection_allocation|allocation_id|owner_user_id|actor_user_id|storage|location|condition|price|value"
SIG = "n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')'"


def run(mig, rb, pre, post, em, exp, man_txt, gen=True):
    R: list[tuple[str, bool, str]] = []
    ck = lambda cid, ok, d: R.append((cid, bool(ok), d))
    head = mig[:mig.index("\nbegin;\n")].strip() if "\nbegin;\n" in mig else ""
    ck("H0", head.startswith("/*") and head.endswith("*/") and head.count("*/") == 1 and head.count("/*") == 1,
       "cabeçalho = um único comentário de bloco")
    ck("S0", all(balanced(x) for x in (mig, rb, pre, post, em)) and nc(mig).count("$pre$") == 2 and nc(mig).count("$post$") == 2
       and nc(mig).count("$fn$") == 2 and nc(mig).count("$$") == 8 and nc(rb).count("$$") == 8,
       "aspas, parênteses e $…$ balanceados (NÃO substitui compilação)")
    if gen:
        ck("G0", mig == GEN_MIG and rb == GEN_RB, "migration e rollback = saída reproduzível de build_5395.py")

    # --- funções do titular
    ok_c1 = all(md5(prosrc(B.CANON[n])) == h for n, (_, h) in B.SRC.items())
    ck("C1", ok_c1, "texto-fonte (database/schema 6123/6124/6126/6125) = md5 canônico do LIVE")
    defs = {n: fn_def(mig, n) for n in B.SIGS}
    ck("C2", all(defs[n] and strip_marked(defs[n]) == B.CANON[n] for n in B.SIGS),
       "removidos os blocos [5395+]…[5395-], cada função é IDÊNTICA ao texto canônico (assinatura, retorno, definer, search_path, corpo)")
    ck("C3", all(defs[n] and md5(prosrc(defs[n])) == B.NEWMD5[n] for n in B.SIGS) and len(B.SIGS) == 4,
       "4 funções instrumentadas com md5 = constantes do POST e do rollback")
    c4 = True
    for n in B.SIGS:
        d = defs[n] or ""
        bl = blocks(d)
        joined = "\n".join(bl)
        body = re.sub(r"(?i)\bFOR UPDATE\b", "", nolit(joined))
        c4 = c4 and len(bl) == 3 and not re.search(r"(?i)\b(insert|update|delete|set_config|execute|grant|revoke)\b", body) \
            and set(re.findall(r"public\.([a-z0-9_]+)\s*\(", joined)) <= {"v1_13_capability_open", "collection_activity_open", "collection_activity_record_pokedex"} \
            and joined.count("public.v1_13_capability_open()") == 1 and joined.count("collection_activity_open(") == 1 \
            and joined.count("collection_activity_record_pokedex(") == 1
        first_w, last_w = WRITE[n]
        i_open, i_w1 = d.find("collection_activity_open("), d.find(first_w)
        i_w2, i_rec = d.rfind(last_w), d.find("collection_activity_record_pokedex(")
        c4 = c4 and 0 < d.find("v_audit := public.v1_13_capability_open();") < i_open < i_w1 and 0 < i_w2 < i_rec
        # open e record dentro de "IF v_audit"
        ob = next((b for b in bl if "collection_activity_open(" in b), "")
        rbk = next((b for b in bl if "collection_activity_record_pokedex(" in b), "")
        c4 = c4 and ob.startswith("    v_audit := public.v1_13_capability_open();\n    IF v_audit THEN\n") \
            and ob.rstrip().endswith("\n    END IF;") and ob.count("\n    END IF;") == 1 and "collection_activity_open(" in ob \
            and re.match(r"\s*IF v_audit( AND v_prev IS DISTINCT FROM p_collection_allocation_id)? THEN\n", rbk) is not None \
            and rbk.rstrip().endswith("END IF;")
    ck("C4", c4, "blocos só leem e chamam capability_open/open/record; open antes da 1ª escrita e record depois da escrita efetiva, ambos sob IF v_audit")
    c5 = True
    for n in B.SIGS:
        d = defs[n] or ""
        rbk = next((b for b in blocks(d) if "collection_activity_record_pokedex(" in b), "")
        c5 = c5 and set(re.findall(r"'(POKEDEX_[A-Z_]+)'", rbk)) == EVENTS[n]
    sp = defs["set_pokedex_position_primary_representative"] or ""
    ob = next((b for b in blocks(sp) if "collection_activity_open(" in b), "")
    c5 = c5 and "IF v_audit AND v_prev IS DISTINCT FROM p_collection_allocation_id THEN" in sp and "FOR UPDATE;" in ob
    cl = defs["clear_pokedex_position_primary_representative"] or ""
    c5 = c5 and "FOR UPDATE;" in next((b for b in blocks(cl) if "collection_activity_open(" in b), "")
    ck("C5", c5, "tipos de evento por função; representante: estado anterior travado e registro só com mudança efetiva")

    # --- ciclo de vida da marcação (REVIEW-01): toda marcação é consumida por record ou desfeita por erro
    t1 = True
    for n in B.SIGS:
        d = defs[n] or ""
        i_o, i_r = d.find("PERFORM public.collection_activity_open("), d.find("PERFORM public.collection_activity_record_pokedex(")
        seg = nc(d[i_o:i_r]) if 0 < i_o < i_r else "RETURN;"
        t1 = t1 and not re.search(r"(?i)\bRETURN\s*;|\bRETURN\s+(QUERY\s+SELECT|NEXT)\b|\bEXIT\b|\bCONTINUE\b", seg) \
            and not re.search(r"(?i)\bEXCEPTION\s+WHEN\b", nc(d))
    ck("T1", t1, "marcação → record sem saída intermediária: entre open e record nenhum RETURN/EXIT e nenhum tratador EXCEPTION na função (erro aborta e desfaz a marcação)")
    t2 = True
    d6123 = defs["set_pokedex_position_assignment"] or ""
    t2 = t2 and re.search(r"(?i)ON\s+CONFLICT", d6123) is None
    for n in ("remove_pokedex_position_assignment", "clear_pokedex_position_primary_representative"):
        d = defs[n] or ""
        i_o, i_w = d.find("PERFORM public.collection_activity_open("), d.find(WRITE[n][0])
        i_nf, i_r = d.find("IF NOT FOUND THEN\n        RAISE EXCEPTION '" + n.upper() + "_NOT_FOUND:", i_w), d.find("PERFORM public.collection_activity_record_pokedex(")
        t2 = t2 and 0 < i_o < i_w < i_nf < i_r
    noop = ("""         FOR UPDATE;
        -- Sem mudança efetiva: nenhuma escrita, nenhuma marcação, nenhum evento (como o UNCHANGED da 5392).
        -- Evita a marcação residual na transação e o evento derivado do UPDATE do upsert.
        IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN
            RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;
            RETURN;
        END IF;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;""")
    t2 = t2 and sp.count(noop) == 1 and sp.find(noop) < sp.find(WRITE["set_pokedex_position_primary_representative"][0]) \
        and sp.count("collection_activity_open(") == 1
    ck("T2", t2, "marcação só em operação efetiva: 6123 INSERT sem ON CONFLICT; 6124/6125 DELETE seguido de NOT_FOUND → erro; 6126 sem mudança sai ANTES de marcar e de escrever")
    t3 = "VALUES (v_collection_id, v_pokedex_position_id, p_collection_allocation_id)" in sp \
        and ordered(sp, "RETURNING", "primary_representative.collection_id,", "primary_representative.pokedex_position_id,", "primary_representative.collection_allocation_id;")
    ck("T3", t3 and "RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;" in sp,
       "no-op do 6126 devolve a mesma linha que o upsert canônico devolveria (collection_id, posição, alocação)")
    sa = defs["set_pokedex_position_assignment"] or ""
    sab = sa[sa.find("\nBEGIN\n"):] if "\nBEGIN\n" in sa else ""
    ck("C6", ordered(sab, "IF FOUND AND v_existing_position_id = p_pokedex_position_id THEN", "RETURN;", "v_basis := 'USER_OVERRIDE';", A)
       and sab.find(A) == sab.find(A + "\n    v_audit := public.v1_13_capability_open();"),
       "no-op e recusas do 6123 retornam/abortam ANTES de qualquer bloco 5395 (sem marcação, sem evento)")

    # --- leitura do histórico
    rm = re.search(r"create function public\.get_collection_activity\((.*?)\$fn\$;", mig, re.S)
    rt = rm.group(0) if rm else ""
    outc = re.search(r"returns table \((.*?)\)\nlanguage", rt, re.S)
    cols = [re.sub(r"\s+", " ", c.strip()) for c in outc.group(1).split(",")] if outc else []
    sel = re.search(r"return query\n(.*?)\n  from public\.collection_activity_event e", rt, re.S)
    selt = sel.group(1) if sel else ""
    seltop = re.sub(r"case when e\.actor_user_id is null then null\s+else \(select up\.display_name::text from public\.user_profile up where up\.id = e\.actor_user_id\) end", "<NOME>", selt)
    ck("R1", cols == OUT_COLS and ordered(rt, "language plpgsql", "stable", "security definer", "set search_path = ''", "as $fn$")
       and ordered(rt, "begin", "perform public.v1_13_assert_capability();", "p_limit < 1 or p_limit > 100", "public.collection_share_role(p_collection_id)",
                   "v_role not in ('OWNER', 'VIEWER')", "return query")
       and not re.search(PATRIMONIAL, seltop) and "<NOME>" in seltop
       and "where e.collection_id = p_collection_id" in rt and "e.id = p_before_id and e.collection_id = p_collection_id" in rt
       and "order by e.occurred_at desc, e.id desc" in rt and "limit p_limit;" in rt
       and not re.search(r"(?i)\b(insert|update|delete|set_config)\b", nolit(rt)),
       "leitura: barreira primeiro; página 1–100; papel por collection_share_role (titular/participante ACTIVE); sem colunas patrimoniais; keyset na mesma coleção; ordem (occurred_at, id) desc; só leitura")
    gr = re.findall(r"(?im)^\s*(grant|revoke)\b[^;]*;", nc(mig))
    gl = [re.sub(r"\s+", " ", x.strip()) for x in re.findall(r"(?im)^\s*(?:grant|revoke)\b[^;]*;", nc(mig))]
    ck("G1", gl == ["revoke all on function public.get_collection_activity(uuid, bigint, integer) from public, anon, service_role;",
                    "grant execute on function public.get_collection_activity(uuid, bigint, integer) to authenticated;"] and len(gr) == 2,
       "privilégios: leitura só para authenticated; funções do titular sem GRANT/REVOKE (CREATE OR REPLACE preserva ACL)")
    objs = re.findall(r"(?i)\b(create(?:\s+or\s+replace)?\s+(?:function|table|view|trigger|policy|index|sequence))\s+public\.([a-z0-9_]+)", nc(mig))
    ck("G2", sorted(o[1] for o in objs) == sorted(list(B.SIGS) + ["get_collection_activity"])
       and sum(1 for o in objs if "replace" in o[0].lower()) == 4 and not re.search(r"(?i)\b(drop|alter|truncate)\b", nolit(mig).replace("drop function", "")),
       "objetos: só as 4 funções do titular (OR REPLACE) e a leitura nova; nada removido ou alterado")

    # --- pré e pós da migration
    prem = re.search(r"do \$pre\$(.*?)\$pre\$;", mig, re.S)
    pst = re.search(r"do \$post\$(.*?)\$post\$;", mig, re.S)
    pt, qt = (prem.group(1) if prem else ""), (pst.group(1) if pst else "")
    ck("P1", all(h in pt for h in B.DEPS.values()) and all(h in pt for _, h in B.SRC.values()) and "'CLOSED'" in pt
       and "v1_13_barrier_identity" in pt and "get_collection_activity(uuid, bigint, integer)') is not null" in pt
       and "editor_move_pokedex_copy" in pt and "user_profile" in pt,
       "PRECHECK: dependências por md5, titular canônico, barreira CLOSED/0 identidades, 5392/5394/perfil presentes, leitura ausente")
    ck("P2", all(h in qt for h in B.NEWMD5.values()) and "collection_activity_event" in qt and "'CLOSED'" in qt
       and "a.grantee = 0" in qt and "'service_role'" in qt and "'s'" in qt,
       "POSTCHECK: texto instrumentado, segurança/ACL do titular (sem PUBLIC), leitura, nenhum evento, barreira CLOSED")

    # --- rollback
    rbs = nc(rb)
    ck("RB1", all(B.CANON[n] in rb for n in B.SIGS) and "drop function public.get_collection_activity(uuid, bigint, integer);" in rbs
       and all(h in rb for h in B.NEWMD5.values()) and all(h in rb for _, h in B.SRC.values())
       and not re.search(r"(?i)\b(grant|revoke|delete|truncate|insert|update)\b", nolit(rb_outside(rb))) and A not in rb
       and rbs.count("begin;") == 1 and rbs.count("commit;") == 1,
       "rollback: exige texto 5395; restaura o canônico exato das 4 funções; remove a leitura; não mexe em ACL nem apaga eventos")

    # --- emergência
    emc = nc(em)
    ck("E1", re.findall(r"revoke execute on function public\.([a-z0-9_]+)\(", emc) == ["get_collection_activity"]
       and "from public, anon, authenticated;" in emc and not re.search(r"(?i)\bgrant\b", emc)
       and emc.count("begin;") == 1 and emc.count("commit;") == 1,
       "emergência E2c: revoga só a leitura nova; nenhum GRANT; não toca funções do titular")

    # --- PRE/POST do executor, expectativas e manifesto
    ck("K1", ro(pre) and ro(post), "PRE e POST passam no validador de somente leitura do executor (SELECT único)")
    ck("K2", pre.count(SIG) == 4 and 'collate "C"' in pre and "'escritores_atribuicao'" in pre and "'escritores_representante'" in pre
       and not re.search(r"'escritores_[a-z_]+'", post) and post.count(SIG) == 4 and "_md5'" not in pre + post
       and all(h in pre for h in B.DEPS.values()) and all(h in pre for _, h in B.SRC.values())
       and all(h in post for h in B.NEWMD5.values()) and "'sem_eventos'" in pre and "'sem_eventos'" in post
       and "'ausente_5395'" in pre and "'leitura_historico'" in post,
       "PRE: inventário por assinatura (ordem C), canônico e dependências; POST: instrumentado, leitura, inventário booleano")
    try:
        ex = json.loads(exp)
    except ValueError:
        ex = {}
    p92 = rd(os.path.join(S2, "S2_5392_POST_readonly.sql"))
    a92 = re.search(r"= '([^']+)',\n  'inventario_representante_pos'", p92)
    r92 = re.search(r"= '([^']+)',\n  'titular_canonico'", p92)
    ap = re.search(r"'inventario_atribuicao_pos',.*?\n\s*= '([^']+)'", post, re.S)
    rp = re.search(r"'inventario_representante_pos',.*?\n\s*= '([^']+)'", post, re.S)
    ck("K3", sorted(ex) == ["escritores_atribuicao", "escritores_representante"] and a92 and r92 and ap and rp
       and ex.get("escritores_atribuicao") == a92.group(1).split(", ") == ap.group(1).split(", ")
       and ex.get("escritores_representante") == r92.group(1).split(", ") == rp.group(1).split(", ")
       and len(ex["escritores_atribuicao"]) == 7 and len(ex["escritores_representante"]) == 6,
       "expectativas = inventário confirmado no POST da 5392 (7 + 6 assinaturas); POST exige o MESMO inventário (nenhum escritor novo)")
    live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_|[A-Za-z]:\\\\Users", re.I)
    ck("X1", not any(live.search(nc(x)) for x in (mig, rb, pre, post, em)), "nenhuma referência ao projeto, URL, credencial ou caminho privado")
    man = [l.split("|") for l in man_txt.splitlines() if l and not l.startswith("#")]
    okm = len(man) == 3 and [m[0] for m in man] == ["1", "2", "3"] and [m[3] for m in man] == ["gate", "write", "gate"]
    content = {os.path.basename(MIG): mig, os.path.basename(PRE): pre, os.path.basename(POST): post}
    for m in man if okm else []:
        base = os.path.basename(m[1].replace("\\", "/"))
        okm = okm and base in content and hashlib.sha256(content[base].encode("utf-8")).hexdigest() == m[2] \
            and m[1].startswith("database\\proposals\\2026-11-27-v1-13-e3-6-s4-collaborative-audit\\")
    ck("X2", okm and [os.path.basename(m[1].replace("\\", "/")) for m in man] == [os.path.basename(PRE), os.path.basename(MIG), os.path.basename(POST)],
       "manifesto: PRE (gate) → 5395 (write) → POST (gate), sha256 = arquivos")
    return R


FILES = dict(mig=rd(MIG), rb=rd(RB), pre=rd(PRE), post=rd(POST), em=rd(EMF), exp=rd(EXP), man_txt=rd(MAN))
R = run(**FILES)
with open(MIG, "rb") as fh:
    disk = fh.read()
R.append(("X3", disk == FILES["mig"].encode("utf-8") and b"\r\n" not in disk and not disk.startswith(b"\xef\xbb\xbf"),
          "migration em UTF-8 sem BOM e LF (sha256 estável entre Windows e sandbox)"))


# ------------------------------------------------------------------ mutações (cada uma deve reprovar o controle-alvo)
def sub1(t, a, b):
    assert t.count(a) >= 1, a[:70]
    return t.replace(a, b, 1)


def drop_in_fn(t, fn, a, b=""):
    d = fn_def(t, fn)
    assert d and a in d, (fn, a[:60])
    return t.replace(d, d.replace(a, b, 1), 1)


M = FILES["mig"]
MUT = [
    ("sem open no 6123", "C4", dict(mig=drop_in_fn(M, "set_pokedex_position_assignment", "        PERFORM public.collection_activity_open(v_collection_id);\n"))),
    ("record sem IF v_audit (6124)", "C4", dict(mig=drop_in_fn(M, "remove_pokedex_position_assignment", "    IF v_audit THEN\n        PERFORM public.collection_activity_record_pokedex", "    IF true THEN\n        PERFORM public.collection_activity_record_pokedex"))),
    ("record antes da escrita (6125)", "C4", dict(mig=drop_in_fn(M, "clear_pokedex_position_primary_representative", "    RETURN QUERY\n    DELETE FROM public.collection_pokedex_position_primary_representative pr",
                                                                 "    PERFORM public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_REPRESENTATIVE_RESTORED', NULL, NULL, p_pokedex_position_id, v_prev, NULL, NULL);\n    RETURN QUERY\n    DELETE FROM public.collection_pokedex_position_primary_representative pr"))),
    ("escrita dentro do bloco", "C4", dict(mig=drop_in_fn(M, "remove_pokedex_position_assignment", "        PERFORM public.collection_activity_open(v_collection_id);",
                                                         "        PERFORM public.collection_activity_open(v_collection_id);\n        DELETE FROM public.collection_activity_event;"))),
    ("registro sem mudança efetiva (6126)", "C5", dict(mig=drop_in_fn(M, "set_pokedex_position_primary_representative", " AND v_prev IS DISTINCT FROM p_collection_allocation_id", ""))),
    ("open condicionado no 6126", "T2", dict(mig=drop_in_fn(M, "set_pokedex_position_primary_representative", "        PERFORM public.collection_activity_open(v_collection_id);",
                                                           "        IF v_prev IS DISTINCT FROM p_collection_allocation_id THEN PERFORM public.collection_activity_open(v_collection_id); END IF;"))),
    ("REVIEW-01: sem saída no-op no 6126 (marcação residual)", "T2", dict(mig=drop_in_fn(M, "set_pokedex_position_primary_representative",
        "        IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN\n            RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;\n            RETURN;\n        END IF;\n", ""))),
    ("REVIEW-01: saída no-op depois do open", "T1", dict(mig=drop_in_fn(M, "set_pokedex_position_primary_representative",
        "        IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN\n            RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;\n            RETURN;\n        END IF;\n        PERFORM public.collection_activity_open(v_collection_id);",
        "        PERFORM public.collection_activity_open(v_collection_id);\n        IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN\n            RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;\n            RETURN;\n        END IF;"))),
    ("REVIEW-01: condição no-op invertida", "T2", dict(mig=drop_in_fn(M, "set_pokedex_position_primary_representative", "IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN", "IF v_prev IS DISTINCT FROM p_collection_allocation_id THEN"))),
    ("REVIEW-01: RETURN entre open e escrita (6125)", "T1", dict(mig=drop_in_fn(M, "clear_pokedex_position_primary_representative",
        "        PERFORM public.collection_activity_open(p_collection_id);\n    END IF;", "        PERFORM public.collection_activity_open(p_collection_id);\n        RETURN;\n    END IF;"))),
    ("REVIEW-01: tratador EXCEPTION engole erro (6124)", "T1", dict(mig=drop_in_fn(M, "remove_pokedex_position_assignment", "\nEND;\n$$;", "\nEXCEPTION WHEN OTHERS THEN\n    RETURN;\nEND;\n$$;"))),
    ("REVIEW-01: retirada sem NOT_FOUND (6124)", "T2", dict(mig=drop_in_fn(M, "remove_pokedex_position_assignment", "    IF NOT FOUND THEN\n        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_FOUND", "    IF false THEN\n        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_FOUND"))),
    ("REVIEW-01: INSERT idempotente silencioso (6123)", "T2", dict(mig=drop_in_fn(M, "set_pokedex_position_assignment", "    RETURNING\n        collection_pokedex_position_assignment.collection_allocation_id,", "    ON CONFLICT DO NOTHING\n    RETURNING\n        collection_pokedex_position_assignment.collection_allocation_id,"))),
    ("REVIEW-01: no-op devolve linha diferente", "T3", dict(mig=drop_in_fn(M, "set_pokedex_position_primary_representative", "RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;", "RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, v_prev;"))),
    ("tipo de evento trocado", "C5", dict(mig=drop_in_fn(M, "remove_pokedex_position_assignment", "'POKEDEX_POSITION_REMOVED'", "'POKEDEX_POSITION_MOVED'"))),
    ("corpo canônico alterado fora dos marcadores", "C2", dict(mig=drop_in_fn(M, "set_pokedex_position_assignment", "v_basis := 'USER_OVERRIDE';", "v_basis := 'SPECIES_MATCH';"))),
    ("SECURITY DEFINER removido do titular", "C2", dict(mig=drop_in_fn(M, "remove_pokedex_position_assignment", "SECURITY DEFINER\n", ""))),
    ("bloco 5395 antes do no-op do 6123", "C6", dict(mig=drop_in_fn(M, "set_pokedex_position_assignment", "    IF FOUND AND v_existing_position_id = p_pokedex_position_id THEN",
                                                                   A + "\n    v_audit := v_audit;\n" + Z + "\n    IF FOUND AND v_existing_position_id = p_pokedex_position_id THEN"))),
    ("leitura sem barreira", "R1", dict(mig=sub1(M, "  perform public.v1_13_assert_capability();  -- barreira", "  -- barreira"))),
    ("leitura sem papel", "R1", dict(mig=sub1(M, "  if v_role is null or v_role not in ('OWNER', 'VIEWER') then\n    return;\n  end if;\n", ""))),
    ("leitura expõe autor por id", "R1", dict(mig=sub1(M, "  select e.id, e.occurred_at,", "  select e.id, e.actor_user_id, e.occurred_at,"))),
    ("leitura sem limite superior", "R1", dict(mig=sub1(M, "p_limit < 1 or p_limit > 100", "p_limit < 1"))),
    ("keyset de outra coleção", "R1", dict(mig=sub1(M, "where e.id = p_before_id and e.collection_id = p_collection_id", "where e.id = p_before_id"))),
    ("leitura para anon", "G1", dict(mig=sub1(M, "to authenticated;\n\n", "to authenticated, anon;\n\n"))),
    ("GRANT extra no titular", "G1", dict(mig=sub1(M, "\ndo $post$", "\ngrant execute on function public.remove_pokedex_position_assignment(uuid) to anon;\n\ndo $post$"))),
    ("precheck sem barreira", "P1", dict(mig=sub1(M, "is distinct from 'CLOSED'", "is distinct from 'OPEN'"))),
    ("rollback sem drop da leitura", "RB1", dict(rb=sub1(FILES["rb"], "drop function public.get_collection_activity(uuid, bigint, integer);", ""))),
    ("rollback com corpo diferente do canônico", "RB1", dict(rb=sub1(FILES["rb"], "v_basis := 'USER_OVERRIDE';", "v_basis := 'SPECIES_MATCH';"))),
    ("rollback regrava ACL", "RB1", dict(rb=sub1(FILES["rb"], "\ndo $post$", "\ngrant execute on function public.get_collection_activity(uuid, bigint, integer) to anon;\ndo $post$"))),
    ("emergência com GRANT", "E1", dict(em=sub1(FILES["em"], "commit;", "grant execute on function public.get_collection_activity(uuid, bigint, integer) to anon;\ncommit;"))),
    ("emergência revoga titular", "E1", dict(em=sub1(FILES["em"], "commit;", "revoke execute on function public.remove_pokedex_position_assignment(uuid) from public, anon, authenticated;\ncommit;"))),
    ("PRE com escrita", "K1", dict(pre=sub1(FILES["pre"], ") as s4b_5395_pre;", ") as s4b_5395_pre; delete from public.collection_activity_event;"))),
    ("POST com chave escritores_*", "K2", dict(post=sub1(FILES["post"], "'inventario_atribuicao_pos'", "'escritores_atribuicao_pos'"))),
    ("POST aceita escritor novo", "K3", dict(post=sub1(FILES["post"], "public.set_pokedex_position_assignment(uuid,uuid,boolean)'", "public.set_pokedex_position_assignment(uuid,uuid,boolean), public.x(uuid)'"))),
    ("expectativa divergente", "K3", dict(exp=json.dumps({"escritores_atribuicao": [], "escritores_representante": []}))),
    ("manifesto com hash errado", "X2", dict(man_txt=re.sub(r"\|([0-9a-f]{64})\|write", "|" + "0" * 64 + "|write", FILES["man_txt"]))),
    ("manifesto fora de ordem", "X2", dict(man_txt=FILES["man_txt"].replace("|gate\n", "|read\n", 1))),
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
print(f"\nSTATIC CHECK 5395: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
