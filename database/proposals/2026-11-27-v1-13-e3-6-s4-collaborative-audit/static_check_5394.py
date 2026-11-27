#!/usr/bin/env python3
"""
V1-13 · E3-6 / S4-a — verificação ESTÁTICA da 5394, ROLLBACK_5394, PRE/POST e manifesto.

Sem banco. Prova só propriedades do TEXTO (STD-005 V03, V04, V05, V08–V14): forma da
transação; md5 das funções do titular = corpos canônicos; nenhum objeto existente alterado;
definer + search_path vazio; nenhum privilégio para a API; gatilhos e ordem de travas;
marcação explícita respeitada por toda captura derivada; autor derivado no servidor; resumo
de chaves fechadas, sem identificadores físicos; imutabilidade; rollback simétrico e
conservador; checks somente leitura; manifesto. NÃO prova execução nem comportamento.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s4-collaborative-audit/static_check_5394.py
"""
from __future__ import annotations

import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
G1 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1")
MIG = os.path.join(HERE, "5394_create_collection_activity_audit_infrastructure.sql")
RB = os.path.join(HERE, "ROLLBACK_5394.sql")
PRE = os.path.join(HERE, "S4A_5394_PRE_readonly.sql")
POST = os.path.join(HERE, "S4A_5394_POST_readonly.sql")
MAN = os.path.join(HERE, "S4A_5394_MANIFEST.txt")
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
    depth = 0
    for ch in t:
        depth += (ch == "(") - (ch == ")")
        if depth < 0:
            return False
    return depth == 0


md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()
mig, rb, pre, post = rd(MIG), rd(RB), rd(PRE), rd(POST)
code = nc(mig)
body = mig[mig.index("\nbegin;\n") + 1:]

head = mig[:mig.index("\nbegin;\n")].strip()
check("H0", head.startswith("/*") and head.endswith("*/") and head.count("*/") == 1 and head.count("/*") == 1,
      "cabeçalho = um único comentário de bloco (V11, lição 5388)")
check("S0", all(balanced(x) for x in (mig, rb, pre, post)) and code.count("$fn$") % 2 == 0
      and code.count("$pre$") == 2 and code.count("$post$") == 2,
      "aspas, parênteses e $…$ balanceados (NÃO substitui compilação)")

canon = {
    ("set_pokedex_position_assignment", "(uuid, uuid, boolean)"): prosrc(rd(os.path.join(SCHEMA, "6123_fix_fatia_d_applied_objects_pause_sql_direct_audit.sql")), "set_pokedex_position_assignment"),
    ("remove_pokedex_position_assignment", "(uuid)"): prosrc(rd(os.path.join(SCHEMA, "6124_create_remove_pokedex_position_assignment_function.sql")), "remove_pokedex_position_assignment"),
    ("set_pokedex_position_primary_representative", "(uuid)"): prosrc(rd(os.path.join(SCHEMA, "6126_fix_primary_representative_on_conflict_ambiguity.sql")), "set_pokedex_position_primary_representative"),
    ("clear_pokedex_position_primary_representative", "(uuid, uuid)"): prosrc(rd(os.path.join(SCHEMA, "6125_create_primary_representative_functions.sql")), "clear_pokedex_position_primary_representative"),
    ("v1_13_assert_capability", "()"): prosrc(rd(os.path.join(G1, "5389_create_v1_13_capability_barrier.sql")), "v1_13_assert_capability"),
    ("v1_13_capability_open", "()"): prosrc(rd(os.path.join(G1, "5389_create_v1_13_capability_barrier.sql")), "v1_13_capability_open"),
}
bad = []
for (fn, sig), src in canon.items():
    pat = re.escape(f"to_regprocedure('public.{fn}{sig}')")
    found = []
    for t in (code, nc(rb), nc(pre), nc(post)):
        found += re.findall(pat + r"\)\s*is distinct from\s*'([0-9a-f]{32})'", t) + re.findall(pat + r"\)\s*=\s*'([0-9a-f]{32})'", t)
    if not found or any(h != md5(src) for h in found):
        bad.append(fn)
check("C1", not bad, "md5 do titular (6123/6124/6126/6125) e da barreira = corpos canônicos em migration, rollback, PRE e POST"
      + (f" — divergem: {', '.join(bad)}" if bad else ""))
writers = sorted(set(re.findall(r"'([a-z_]+)'", code[code.index("perform set_config('mmkyu.s4a_5394_writers'"):code.index("$pre$;")])))
check("C2", all(w in writers for w in ("allocate_physical_cards_to_collection", "deallocate_physical_cards_from_collection",
                                         "auto_assign_pokedex_position_species_match", "editor_set_pokedex_position_assignment"))
      and code.count("mmkyu.s4a_5394_writers") == 2,
      "retrato dos corpos de todos os escritores conhecidos (titular, alocação, 6119, 5380) comparado no postcheck")

check("M1", body.count("begin;") == 1 and body.rstrip().endswith("commit;") and "set local lock_timeout = '3s';" in body,
      "uma transação, lock_timeout 3 s")
locks = [m.start() for m in re.finditer(r"lock table public\.(collection_allocation|collection_pokedex_position_assignment|collection_pokedex_position_primary_representative) in share row exclusive mode nowait;", code)]
order = re.findall(r"lock table public\.([a-z_]+) in share row exclusive mode nowait;", code)
check("M2", order == ["collection_allocation", "collection_pokedex_position_assignment", "collection_pokedex_position_primary_representative"]
      and max(locks) < code.index("create trigger"),
      "três travas NOWAIT (alocação → atribuição → representante) antes de qualquer gatilho")
created = sorted(set(re.findall(r"create (?:function|table|trigger|index) (?:public\.)?([a-z0-9_]+)", code)))
expected_fns = ["collection_activity_capture_assignment_delete", "collection_activity_capture_assignment_insert",
                "collection_activity_capture_deallocation", "collection_activity_capture_representative_delete",
                "collection_activity_capture_representative_set", "collection_activity_derived_add",
                "collection_activity_event_guard", "collection_activity_open", "collection_activity_record_pokedex"]
expected_trg = ["trg_900_collection_activity_assignment_delete", "trg_900_collection_activity_assignment_insert",
                "trg_900_collection_activity_deallocation", "trg_900_collection_activity_event_guard",
                "trg_900_collection_activity_representative_delete", "trg_900_collection_activity_representative_insert",
                "trg_900_collection_activity_representative_update"]
check("M3", created == sorted(expected_fns + expected_trg + ["collection_activity_event", "ix_cae_collection_time", "ix_cae_owner"])
      and "or replace" not in code.lower() and not re.search(r"\bdrop\b", code, re.I)
      and re.findall(r"alter table public\.([a-z_]+)", code) == ["collection_activity_event"]
      and re.search(r"\b(insert into|update|delete from)\s+public\.(?!collection_activity_event\b)", nolit(code), re.I) is None,
      "só objetos novos (9 funções, 7 gatilhos, 1 tabela, 2 índices); nenhum CREATE OR REPLACE, DROP, ALTER ou escrita em tabela existente")
blocks = re.findall(r"create function public\.([a-z0-9_]+)\((?:.|\n)*?\nas \$fn\$", code)
fblocks = re.findall(r"create function public\.[a-z0-9_]+\((?:.|\n)*?\nas \$fn\$", code)
check("M4", sorted(blocks) == expected_fns and all("security definer" in b and "set search_path = ''" in b for b in fblocks),
      "9 funções, todas SECURITY DEFINER com search_path vazio")
check("M5", re.search(r"\bgrant\b", code, re.I) is None
      and "revoke all on table public.collection_activity_event from public, anon, authenticated, service_role;" in code
      and all(re.search(r"revoke all on function public\." + f + r"\([^)]*\) from public, anon, authenticated, service_role;", code) for f in expected_fns),
      "nenhum GRANT; tabela e as 9 funções revogadas de public/anon/authenticated/service_role (internas)")
trg = {m.group(1): m.group(0) for m in re.finditer(r"create trigger (trg_900_[a-z_]+)\n[^;]+;", code)}
want = {
    "trg_900_collection_activity_assignment_insert": ("after insert on public.collection_pokedex_position_assignment", "referencing new table as new_rows", "for each statement"),
    "trg_900_collection_activity_assignment_delete": ("after delete on public.collection_pokedex_position_assignment", "referencing old table as old_rows", "for each statement"),
    "trg_900_collection_activity_representative_insert": ("after insert on public.collection_pokedex_position_primary_representative", "referencing new table as new_rows", "for each statement"),
    "trg_900_collection_activity_representative_update": ("after update on public.collection_pokedex_position_primary_representative", "referencing new table as new_rows", "for each statement"),
    "trg_900_collection_activity_representative_delete": ("after delete on public.collection_pokedex_position_primary_representative", "referencing old table as old_rows", "for each statement"),
    "trg_900_collection_activity_deallocation": ("before delete on public.collection_allocation", "for each row"),
    "trg_900_collection_activity_event_guard": ("before update on public.collection_activity_event", "for each row"),
}
check("M6", set(trg) == set(want) and all(all(p in trg[k] for p in v) for k, v in want.items()),
      "gatilhos: 5 de instrução com tabela de transição, 1 BEFORE DELETE na alocação, 1 guarda BEFORE UPDATE")


def fbody(name):
    i = code.index(f"create function public.{name}(")
    return code[i:code.index("\n$fn$;", i)]


caps = ["collection_activity_capture_assignment_insert", "collection_activity_capture_assignment_delete",
        "collection_activity_capture_representative_set", "collection_activity_capture_representative_delete"]
check("M7", all("current_setting('mmkyu.collection_activity_explicit', true)" in fbody(f) and "is distinct from v_explicit" in fbody(f)
                and "collection_activity_derived_add(" in fbody(f) for f in caps)
      and "is distinct from nullif(current_setting('mmkyu.collection_activity_explicit', true), '')" in fbody("collection_activity_capture_deallocation")
      and "return old;" in fbody("collection_activity_capture_deallocation"),
      "toda captura derivada ignora a coleção marcada por open() (sem evento duplicado); desalocação não cancela a exclusão")
rec = fbody("collection_activity_record_pokedex")
sig = rec[:rec.index("returns bigint")]
check("M8", re.search(r"p_actor|p_role|p_user|p_owner|p_summary", sig) is None
      and "v_uid   uuid := (select auth.uid());" in rec and "COLLECTION_ACTIVITY_NOT_OPEN" in rec
      and "COLLECTION_ACTIVITY_ACTOR_NOT_AUTHORIZED" in rec and "m.status = 'ACTIVE' and m.role = 'EDITOR'" in rec
      and "'EXPLICIT'" in rec and "perform set_config('mmkyu.collection_activity_explicit', '', true);" in rec,
      "registro explícito: autor = auth.uid(), papel derivado (titular ou EDITOR ACTIVE), exige open(), consome a marcação")
keys = set(re.findall(r"jsonb_build_object\(([^;]*?)\)", nolit(rec + fbody("collection_activity_derived_add")), re.S))
used = set(re.findall(r"'([a-z_]+)'", "\n".join(re.findall(r"jsonb_build_object\((?:[^()]|\([^()]*\))*\)", rec + fbody("collection_activity_derived_add"), re.S))))
allowed = {"name", "number", "set", "variant", "species", "to", "from", "card", "previous_card", "position", "basis",
           "representative_cleared", "assigned", "removed", "representatives_set", "representatives_cleared"}
check("M9", used and used <= allowed and re.search(r"physical_card_id['\"]|allocation_id'|storage|condition|price|token", rec + fbody("collection_activity_derived_add")) is None,
      f"resumo com chaves fechadas ({len(used)} usadas, todas permitidas); nenhum exemplar, alocação, local, condição, preço ou identificador")
tbl = code[code.index("create table public.collection_activity_event"):code.index("create index ix_cae_collection_time")]
check("M10", all(x in tbl for x in ("references public.collection (id) on update restrict on delete cascade",
                                     "chk_cae_origin_type check ((origin = 'DERIVED') = (event_type = 'POKEDEX_POSITIONS_CHANGED'))",
                                     "chk_cae_actor check ((actor_role = 'SYSTEM') = (actor_user_id is null))",
                                     "chk_cae_explicit_actor", "octet_length(summary::text) <= 2048"))
      and "alter table public.collection_activity_event enable row level security;" in code,
      "tabela: FK da coleção, origem ⇔ tipo, autor ⇔ papel, explícito nunca SYSTEM, resumo ≤ 2 048 bytes, RLS")
g = fbody("collection_activity_event_guard")
check("M11", "COLLECTION_ACTIVITY_IMMUTABLE" in g and "old.origin = 'DERIVED'" in g and "is not distinct from" in g,
      "imutável: só o evento derivado da própria transação acumula contagens")
pc = code[code.index("do $post$"):]
check("M12", all(x in pc for x in ("<> 9", "<> 7", "a migration não deveria gerar eventos", "mmkyu.s4a_5394_writers",
                                    "tabela exposta à API", "barreira não está CLOSED", "a.grantee = 0")),
      "postcheck: 9 funções, 7 gatilhos, sem privilégio da API nem PUBLIC, 0 eventos, escritores intactos, barreira")
gate_re = (r"\nbegin\n(?:\s*--[^\n]*\n)*\s*if not public\.v1_13_capability_open\(\)\n\s*and \(\(select auth\.uid\(\)\) is not null\n"
           r"\s*or \(select s\.mode from public\.v1_13_barrier_state s where s\.id = 1\) is distinct from 'OPEN'\) then\n\s*return( null| old)?;\n\s*end if;")
inert = caps + ["collection_activity_capture_deallocation", "collection_activity_derived_add"]
check("M13", all(re.search(gate_re, fbody(f)) for f in inert)
      and re.search(r"return old;\n\s*end if;", fbody("collection_activity_capture_deallocation"))
      and "v1_13_barrier_state" not in fbody("collection_activity_record_pokedex"),
      "inércia: sem capacidade aberta (barreira CLOSED / TEST sem identidade) as 5 capturas e o acúmulo retornam na 1ª instrução (desalocação devolve OLD) — nenhum evento antes da abertura")

rbc = nc(rb)
rdrops = sorted(re.findall(r"drop (?:function|trigger|table) (?:public\.)?([a-z0-9_]+)", rbc))
check("R1", rdrops == sorted(expected_fns + [t for t in expected_trg if t != "trg_900_collection_activity_event_guard"] + ["collection_activity_event"])
      and "5392 presente" in rbc and "há eventos de auditoria gravados" in rbc and rbc.count("nowait") == 3
      and re.search(r"\b(insert|update|delete)\b", nolit(rbc), re.I) is None,
      "rollback: remove os mesmos objetos (a guarda sai com a tabela); recusa com 5392 ou com eventos; sem DML")
cb = [nc(pre).strip(), nc(post).strip()]
check("K1", all(x.lower().startswith("select") and nolit(x).count(";") == 1
                and re.search(r"\b(insert|update|delete|drop|alter|create|grant|revoke|lock|set_config|nextval)\b", nolit(x), re.I) is None for x in cb),
      "PRE e POST: um SELECT somente leitura cada")
check("K2", re.search(r"\b(e|ev)\.(summary|actor_user_id)\b|select\s+\*", nc(pre) + nc(post), re.I) is None
      and "'escritores_md5'" in pre and "'escritores_md5'" in post and "'sem_eventos'" in post,
      "checks sem dados de usuário; escritores_md5 em PRE e POST (o executor compara); POST exige 0 eventos")
# Lição do PRE no LIVE (2026-11-27): em expressão regular do PostgreSQL "\\b" é backspace, não limite de
# palavra (é "\\y"); o relatório escritores_* saiu vazio. Nenhum "\\b" em literal SQL.
check("V15", not any(re.search(r"'[^']*\\b[^']*'", nc(x)) for x in (mig, rb, pre, post))
      and "\\y'" in nc(pre),
      "regex SQL sem \\b (backspace no PostgreSQL); limite de palavra com \\y no PRE")
# Preparação da implantação (2026-11-27): ordem D4 (5391 implantada), travas concorrentes em relatório,
# expectativas do inventário (gate obrigatório do executor v1.4) idênticas às confirmadas no LIVE (5391).
import json as _json
_exp = _json.load(open(os.path.join(HERE, "S4A_5394_EXPECTATIVAS.json"), encoding="utf-8"))
_exp91 = _json.load(open(os.path.join(ROOT, "database", "proposals", "2026-11-27-v1-13-e3-6-s2-pokedex-collaborative-editing", "S2_5391_EXPECTATIVAS.json"), encoding="utf-8"))
check("V16", "'dependencia_5391'" in pre and "get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)" in pre
      and "trg_collection_membership_epoch" in pre and "'sessoes_com_trava'" in pre and "pg_catalog.pg_locks" in pre
      and sorted(_exp) == ["escritores_atribuicao", "escritores_representante"]
      and len(_exp["escritores_atribuicao"]) == 5 and len(_exp["escritores_representante"]) == 4
      and all(len(v) == len(set(v)) for v in _exp.values()) and _exp == _exp91,
      "PRE exige a 5391 implantada (RPC, época e gatilho habilitado); travas concorrentes em relatório; expectativas 5+4 = inventário confirmado no LIVE pela 5391")
live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_", re.I)
check("X1", not any(live.search(nc(x)) for x in (mig, rb, pre, post)), "nenhuma referência ao projeto, URL ou credencial")
man = [l.split("|") for l in rd(MAN).splitlines() if l and not l.startswith("#")]
okm = [m[0] for m in man] == ["1", "2", "3"] and [m[3] for m in man] == ["gate", "write", "gate"]
for m in man:
    p = os.path.join(ROOT, *m[1].split("\\"))
    okm = okm and os.path.isfile(p) and hashlib.sha256(open(p, "rb").read()).hexdigest() == m[2]
check("X2", okm and [os.path.basename(m[1].replace("\\", "/")) for m in man] == [os.path.basename(PRE), os.path.basename(MIG), os.path.basename(POST)],
      "manifesto: PRE (gate) → 5394 (write) → POST (gate), sha256 = arquivos")

fails = [r for r in R if not r[1]]
for cid, ok, detail in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:4} {detail}")
print(f"\nSTATIC CHECK 5394: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
