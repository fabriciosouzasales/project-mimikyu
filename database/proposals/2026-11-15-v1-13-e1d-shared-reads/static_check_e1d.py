#!/usr/bin/env python3
"""
V1-13 · E1-D — verificação ESTÁTICA da proposta 5323, 5324 e 5388 (+ 5894, ROLLBACK_E1D).

Sem banco. Comprova só propriedades do texto: forma, autorização pela 5302 antes de
qualquer leitura, espelho fiel das grades do titular (5198/5204) MENOS tudo o que lê o
acervo, retorno sem colunas privadas, lista de permissão do histórico igual à da C-241
(+D13) e à lista de gravação do EDITOR (5384), regra de item visível idêntica nos dois
pontos, L01 só com origem, nada de summary/detail/ids na saída, reversão literal e
cobertura do harness. Não comprova comportamento, desempenho nem concorrência.

    python3 -I -B database/proposals/2026-11-15-v1-13-e1d-shared-reads/static_check_e1d.py
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
PROP = os.path.join(ROOT, "database", "proposals")
PRIOR = ["2026-11-14-v1-13-e1a-editor-role", "2026-11-15-v1-13-e1b1-editor-core-binder",
         "2026-11-15-v1-13-e1b2-editor-curation", "2026-11-15-v1-13-e1b3-pokedex-history",
         "2026-11-15-v1-13-e1c-bulk-operations", "2026-11-15-v1-13-e1c2-remaining-bulk-operations"]
MIG = ["5323_create_get_shared_master_set_positions_function.sql",
       "5324_create_get_shared_pokedex_positions_function.sql",
       "5388_create_get_shared_binder_activity_functions.sql"]
HARNESS = "5894_validate_shared_reads_HARNESS.sql"
ROLLBACK = "ROLLBACK_E1D.sql"
FICH = ["CARD_PLACED", "CARD_MOVED", "CARDS_SWAPPED", "CARDS_REMOVED", "POCKET_RESERVED", "RESERVATIONS_RELEASED",
        "POCKETS_LOCKED", "POCKETS_UNLOCKED", "GAP_OPENED", "GAP_CLOSED", "PAGES_ADDED", "PAGE_REMOVED",
        "PAGES_REORDERED", "CARDS_AUTO_ARRANGED"]
HIDDEN = ["BINDER_ASSEMBLED", "CARDS_LEFT_BY_STORAGE", "CARDS_LEFT_BY_COLLECTION_STORAGE", "CARD_LEFT_BY_INVENTORY_EXIT",
          "COLLECTION_ATTACHED", "COLLECTION_DETACHED", "BINDER_DISMANTLED", "BINDER_DELETED_EMPTY",
          "BINDER_OWNERSHIP_TRANSFERRED"]
PAGES = ["GAP_OPENED", "GAP_CLOSED", "PAGES_ADDED", "PAGE_REMOVED", "PAGES_REORDERED"]
PRIVATE = r"(copies_available|copies_elsewhere|acervo_state|inventory|storage_container|condition|grading|certif|acquisition|price|valu|favorite|wishlist|email|username)"

R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, "rb") as fh:
        b = fh.read()
    return b, b.decode("utf-8")


def prosrc(text, fname):
    i = text.lower().index("function public." + fname + "(")
    m = re.search(r"\bas\s+(\$[A-Za-z0-9_]*\$)", text[i:], re.I)
    a = i + m.end()
    return text[a:text.index(m.group(1), a)]


def header(text, fname):
    i = text.lower().index("function public." + fname + "(")
    return text[i:i + re.search(r"\bas\s+\$", text[i:], re.I).start()]


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def ws(t):
    return re.sub(r"\s+", " ", nc(t)).strip().lower()


def schema(prefix):
    return rd(os.path.join(SCHEMA, next(f for f in os.listdir(SCHEMA) if f.startswith(prefix))))[1]


F = {n: rd(os.path.join(HERE, n)) for n in MIG + [HARNESS, ROLLBACK]}
T = {n: v[1] for n, v in F.items()}
t23, t24, t88 = (T[m] for m in MIG)
h, rb = T[HARNESS], T[ROLLBACK]
b23 = prosrc(t23, "get_shared_master_set_positions")
b24 = prosrc(t24, "get_shared_pokedex_positions")
b88 = prosrc(t88, "get_shared_binder_activity")
b88s = prosrc(t88, "get_shared_binder_activity_status")
o98 = prosrc(schema("5198_"), "get_my_master_set_positions")
o04 = prosrc(schema("5204_"), "get_my_pokedex_positions")
s20 = prosrc(schema("5320_"), "get_shared_collection_positions")
g84 = prosrc(rd(os.path.join(PROP, PRIOR[5], "5384_extend_editor_binder_activity_event_types.sql"))[1],
             "binder_activity_event_editor_type_guard")

# 1. Forma ---------------------------------------------------------------------------------------
for n, (b, t) in F.items():
    check(f"1.{n[:4]}", b"\r" not in b and t.endswith("\n") and "NÃO EXECUTAD" in t, f"{n}: sem CRLF, nova linha final, não executado")
for n in MIG:
    t = T[n]
    check(f"2.{n[:4]}", t.count("\nbegin;\n") == 1 and t.rstrip().endswith("commit;") and "do $pre$" in t and "do $post$" in t
          and "JÁ APLICADA ou ESTADO DIVERGENTE" in t and "lock_timeout" in t and not re.search(r"create or replace function", t, re.I),
          f"{n}: uma transação, precheck (recusa reaplicação) e postcheck; CREATE sem OR REPLACE")

# 2. Segurança das funções ---------------------------------------------------------------------------
fns = {"get_shared_master_set_positions": (t23, b23), "get_shared_pokedex_positions": (t24, b24),
       "get_shared_binder_activity": (t88, b88), "get_shared_binder_activity_status": (t88, b88s)}
for fn, (t, b) in fns.items():
    hd = ws(header(t, fn))
    sig = re.search(r"public\." + fn + r"\(([^)]*)\)", hd).group(1)
    types = ", ".join(re.sub(r"\s+default.*", "", a.strip()).split()[1] for a in sig.split(","))
    check(f"3.{fn}", "stable" in hd and "security definer" in hd and "set search_path = ''" in hd
          and f"revoke all on function public.{fn}({types}) from public, anon;" in t.lower()
          and f"grant execute on function public.{fn}({types}) to authenticated;" in t.lower()
          and not re.search(r"\b(insert|update|delete)\b", nc(b), re.I),
          f"{fn}({types}): STABLE, definer, search_path vazio, só authenticated; nenhuma escrita")
    # Autorização pela 5302 antes de qualquer tabela.
    i_auth = b.find("v_role := public.collection_share_role(p_collection_id);")
    i_tab = min(x for x in (b.find("from public."), b.find("join public.")) if x >= 0)
    check(f"4.{fn}", 0 <= i_auth < i_tab
          and "if v_role is null or v_role not in ('OWNER', 'VIEWER') then" in b
          and "collection_member_role" not in b and "auth.uid()" not in b,
          f"{fn}: 5302 (OWNER/VIEWER) antes de qualquer leitura; sem auth.uid() nem papel EDITOR na decisão de leitura")
    ret = ws(re.search(r"returns table \((.*?)\)\s*language", hd, re.S).group(1))
    check(f"5.{fn}", not re.search(PRIVATE, ret) and not re.search(r"\b(summary|detail|collection_name|binder_name|actor_user_id|owner_user_id|layout_key|physical_card_id|collection_id)\b", ret),
          f"{fn}: retorno sem coluna de acervo, local, condição, valor, e-mail, resumo, detalhe, nome gravado ou id interno")

# 3. Espelhos (5323 ↔ 5198, 5324 ↔ 5204) -------------------------------------------------------------
for fn, b in (("5323", b23), ("5324", b24)):
    check(f"6.{fn}", not re.search(PRIVATE, nc(b), re.I) and "public.inventory" not in b and "pc.inventory_id" not in b
          and "storage_container" not in b and "condition" not in b,
          f"{fn}: nenhuma leitura de inventory, local, condição ou colunas de acervo")
cte = lambda body, name: re.search(name + r" as \((.*?)\n  \),?\n", body, re.S)
same98 = all(ws(cte(b23, n).group(1)) == ws(cte(o98, n).group(1)) for n in ("positions", "in_collection", "in_by_card"))
check("7.1", same98 and "available" not in re.sub(r"is_satisfied|available_by_card", "", b23.split("return query")[1]).replace("copies_available", "")
      and ws(o98.split("order by (ast.language_id = f.lang)")[1].split("end;")[0]) == ws(b23.split("order by (ast.language_id = f.lang)")[1].split("end;")[0])
      and "c.completion_policy = 'MASTER_SET'" in b23 and "public.master_set_positions(v_set, v_types)" in b23
      and ws(cte(o98, "filtered").group(1)) == ws(cte(b23, "filtered").group(1)),
      "5323 = 5198 nas CTEs positions/in_collection/in_by_card/filtered, imagem e ordem; sem available/available_by_card")
same04 = all(ws(cte(b24, n).group(1)) == ws(cte(o04, n).group(1)) for n in ("scope", "links", "assigned", "page", "rep"))
check("7.2", same04 and " inv as (" not in b24 and "iv." not in b24
      and ws(o04.split(") art on true")[0].split("left join lateral (")[-1]) == ws(b24.split(") art on true")[0].split("left join lateral (")[-1])
      and ws(o04.split("left join lateral (\n    select c.name")[1]) == ws(b24.split("left join lateral (\n    select c.name")[1])
      and "c.completion_policy = 'REFERENCE_POSITION'" in b24 and "cr.reference_kind = 'POKEDEX'" in b24,
      "5324 = 5204 nas CTEs scope/links/assigned/page/rep, arte e representante; sem a CTE inv")
check("7.3", all(x in b for b in (b23, b24) for x in ("'INVALID_FILTER'", "'INVALID_PAGE'", "p_offset > 100000", "p_limit > 500"))
      and "c.owner_user_id" not in b23 and "c.owner_user_id" not in b24,
      "5323/5324: mesma validação de filtro e página da 5320; sem fronteira por titular (acesso só pela 5302)")
auth = lambda b: ws(b.split("v_role := public.collection_share_role(p_collection_id);")[1]).split("end if;")[0]
check("7.4", auth(s20) == auth(b23) == auth(b24) and "if v_role is null or v_role not in ('owner', 'viewer') then return;" in auth(s20) + "end if;",
      "5323/5324: decisão de acesso idêntica à da 5320 (V1-12)")

# 4. Histórico compartilhado (5388) ------------------------------------------------------------------
pg = b88.split("with page as (")[1].split("\n  ),\n  vis as (")[0]
fich = re.search(r"e\.source = 'FICHARIO'\s+and e\.event_type in \(([^)]*)\)", pg)
lst = re.findall(r"'([A-Z_]+)'", fich.group(1)) if fich else []
g_fich = re.findall(r"'([A-Z_]+)'", re.search(r"new\.event_type in \(([^)]*)\)", g84).group(1))
check("8.1", sorted(lst) == sorted(FICH) and sorted(lst) == sorted(g_fich)
      and "(e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')" in pg
      and not any(x in pg for x in HIDDEN),
      "lista de permissão = C-241 + D13 (14 tipos FICHARIO + E16 CATALOGO) = lista de gravação do EDITOR (5384); E01/E06/E07/E17–E20 ausentes")
check("8.2", "e.owner_user_id = v_owner" in pg and "e.layout_key = v_layout" in pg and "e.collection_id = p_collection_id" in pg
      and re.search(r"\(e\.item_collection_recorded\s+and", pg)
      and "select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;" in b88
      and "select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;" in b88
      and "p_layout_key" not in b88,
      "evento: titular de X, fichário ATUAL de X (derivado no servidor), coleção do evento = X, atribuição confiável (D12)")
check("8.3", re.search(r"e\.event_type = 'LEGACY_CATALOG_INCORPORATION' and e\.source = 'LEGADO' and e\.actor_user_id is null\s+"
                       r"and exists \(select 1 from public\.collection_layout_catalog_incorporation ci\s+"
                       r"where ci\.layout_id = e\.layout_key\s+and ci\.collection_id = p_collection_id\s+"
                       r"and ci\.item_key = e\.summary ->> 'item_key'\)", pg) is not None,
      "L01 (D12): só com a linha de origem desta coleção neste fichário e a mesma chave")
rules = re.findall(r"\(case\s+when e\.source = 'LEGADO'.*?end\)", b88, re.S)
check("8.4", len(rules) == 2 and ws(rules[0]) == ws(rules[1])
      and "i.collection_id is not distinct from p_collection_id" in rules[0]
      and sorted(re.findall(r"'([A-Z_]+)'", rules[0].split("i.item_kind = 'PAGE' then")[1].split("else")[0])) == sorted(PAGES)
      and re.search(r"else false\s+end", rules[0]) and "'COLLECTION'" not in rules[0] and "'BINDER'" not in rules[0],
      "regra de item visível idêntica no filtro de existência e na lista: conteúdo só de X, PAGE só em eventos de páginas, estrutura nunca")
agg = b88.split("agg as (")[1].split("\n  )\n")[0]
outk = re.findall(r"'([a-z_]+)', v\.", agg)
check("8.5", "row_number() over (partition by i.event_id order by i.ordinal) as rn" in b88 and "'ordinal', v.rn" in agg
      and "filter (where v.rn <= 50)" in agg and "count(*)::integer as n" in agg
      and "a.n > 50" in b88 and "join agg a on a.event_id = pg.id" in b88
      and set(outk) <= {"ordinal", "kind", "effect", "card_id", "card_name", "collector_number", "card_set_code",
                        "variant_type_code", "variant_type_name", "from_page", "from_row", "from_col", "to_page", "to_row", "to_col"}
      and not re.search(r"\b(summary|detail|collection_name|binder_name|owner_user_id|layout_key|created_xact)\b",
                        b88.split("return query")[1].split("from public.binder_activity_event e")[0] + agg + b88.split("\n  )\n  select pg.id")[1])
      # o ator só entra nas duas expressões de papel e nome (nunca como coluna de saída)
      and b88.split("\n  )\n  select pg.id")[1].count("pg.actor_user_id") == 4
      and re.search(r"case when pg\.actor_user_id is null then null\s+else \(select up\.display_name", b88),
      "itens: até 50 visíveis, ordinal renumerado, contagem só dos visíveis, evento sem item visível descartado; nenhum summary/detail/id/nome gravado na saída")
check("8.6", "when pg.actor_user_id = v_owner then 'OWNER'" in b88 and "else 'PARTICIPANT' end" in b88
      and "select up.display_name::text from public.user_profile up where up.id = pg.actor_user_id" in b88
      and "username" not in b88 and "email" not in b88 and "auth.users" not in b88,
      "ator: papel (Titular/Participante) e nome de exibição público; nunca e-mail, nome de usuário ou id")
check("8.7", "order by e.occurred_at desc, e.id desc" in pg and "limit v_limit" in pg
      and "least(greatest(coalesce(p_limit, 20), 1), 50)" in b88
      and "(p_before_id is null or (e.occurred_at, e.id) < (p_before_occurred_at, p_before_id))" in pg
      and "'BINDER_ACTIVITY_CURSOR'" in b88 and "'BINDER_ACTIVITY_CATEGORY'" in b88
      and "public.binder_activity_category(e.event_type) = any (p_categories)" in pg,
      "ordem determinística (occurred_at, id), cursor e categorias com as mesmas regras e erros da 5269; limite 1..50")
st_f = re.search(r"e\.source = 'FICHARIO'\s+and e\.event_type in \(([^)]*)\)", b88s)
check("8.8", "e.collection_id = p_collection_id" in b88s and "not e.item_collection_recorded" in b88s
      and st_f is not None and sorted(re.findall(r"'([A-Z_]+)'", st_f.group(1))) == sorted(FICH)
      and "(e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')" in b88s
      and "e.source <> 'LEGADO'" not in b88s
      and re.search(r"and \(\(not e\.item_collection_recorded\s+and \(\(e\.source = 'FICHARIO'", b88s) is not None
      and "collection_layout_catalog_incorporation" in b88s and "return query select false, false;" in b88s
      and re.search(r"returns table \(\s*has_binder\s+boolean,\s*history_may_be_partial boolean\s*\)", t88)
      and b88s.count("v_role := public.collection_share_role(p_collection_id);") == 1,
      "estado: mesmo acesso e fichário; só dois booleanos; parcial = evento de X de tipo da lista de permissão omitido só por falta de atribuição ou de origem (D12)")

CAT = r"and \(e\.collection_id = p_collection_id\s+or \(e\.collection_id is null and e\.actor_user_id = e\.owner_user_id\)\)"
L01A = r"or \(e\.collection_id = p_collection_id\s+and e\.event_type = 'LEGACY_CATALOG_INCORPORATION'"
check("8.9", re.search(CAT, pg) and re.search(CAT, b88s) and re.search(L01A, pg) and re.search(L01A, b88s)
      and all(re.search(r"i\.item_kind = 'PAGE' then e\.collection_id is not distinct from p_collection_id\s+and e\.event_type in", r_) for r_ in rules)
      and pg.count("from public.binder_activity_item i") == 1 and "e.collection_id is not null" not in b88
      and "e.collection_id," in pg.split("from public.binder_activity_event e")[0]
      and len(re.findall(r"e\.collection_id = p_collection_id", pg)) == 2
      and "e.owner_user_id = v_owner" in pg and "e.owner_user_id = v_owner" in b88s,
      "D14: categoria A (registrado para X) ou B (sem coleção, ator gravado = titular gravado); L01 só na A; PAGE só na A; nenhuma condição genérica por item; outra coleção nunca entra; estado com as mesmas categorias")

# 5. Compatibilidade --------------------------------------------------------------------------------
untouched = ["get_my_master_set_positions", "get_my_pokedex_positions", "get_my_binder_activity", "collection_share_role",
             "binder_activity_add_item", "binder_activity_event_editor_type_guard", "get_shared_collection_positions",
             "collection_completion_summary_shared", "binder_activity_category"]
allc = "".join(nc(T[n]) for n in MIG)
check("9.1", not any(re.search(r"function\s+public\." + u + r"\s*\(", allc, re.I) for u in untouched)
      and not re.search(r"\b(alter|drop)\s+(table|trigger|policy|index)\b|create\s+(index|trigger|policy|table)", allc, re.I),
      "nenhuma função existente redefinida (titular, 5302, gravação, gatilho, V1-12); nenhuma tabela, índice, gatilho ou política")
check("9.2", md5(prosrc(schema("5302_"), "collection_share_role")) == "efdb495b5b703e9f093eb0f49a1d0a5d"
      and md5(o98) in h and md5(o04) in h and md5(prosrc(schema("5269_"), "get_my_binder_activity")) in h
      and "efdb495b5b703e9f093eb0f49a1d0a5d" in h and "f8cfba40e442e85056e7c8ce7954d4f4" in h,
      "harness 0.2 exige os md5 canônicos de 5302, 5198, 5204, 5269 e da gravação 5379")

# 6. Reversão -----------------------------------------------------------------------------------------
o = [rb.find(f"-- R{n} ") for n in ("5388", "5324", "5323")]
check("10.1", -1 not in o and o == sorted(o) and rb.count("drop function if exists") == 4
      and all(f"drop function if exists public.{fn}" in rb for fn in fns)
      and not re.search(r"\b(delete|truncate|update|insert|drop\s+table|drop\s+column|drop\s+trigger|drop\s+index)\b", nc(rb), re.I),
      "ROLLBACK_E1D: ordem inversa, 4 funções, nada de dado tocado")

# 7. Harness ------------------------------------------------------------------------------------------
ids = sorted(set(re.findall(r"jsonb_build_object\('id','([0-9.]+)'", h)))
exp = int(re.search(r"v_expected := (\d+);", h).group(1))
check("11.1", len(ids) + 1 == exp and f"{exp}/{exp} PASS" in h, f"5894: {len(ids)} verificações + F.2 = {exp}")
need = {"estrutura": "0.1", "inalterados": "0.2", "EDITOR nas leituras V1-12": "1.1", "negados (estranho/pendente/removido/outro titular)": "1.2",
        "anônimo": "1.3", "Master Set paridade": "2.1", "Master Set filtros": "2.2", "Master Set sem inferência": "2.3",
        "Pokédex paridade": "3.1", "Pokédex sem inferência": "3.2", "Pokédex filtros": "3.3", "lista de eventos": "4.1",
        "D13 filtrado": "4.2", "não exposição": "4.3", "ator": "4.4", "VIEWER = EDITOR, titular íntegro": "4.5",
        "convidada": "4.6", "categorias e cursor": "4.7", "L01": "4.8", "histórico parcial": "5.1", "fichário encerrado": "5.2",
        "revogação": "6.1", "D14 titular sem coleção": "4.9", "arquivada": "6.2", "sem escrita": "7.1", "resíduo": "99.1",
        "agregados Master Set/Pokédex": "3.4", "transferência de âncora": "5.3"}
check("11.2", all(v in ids for v in need.values()), f"5894 cobre os cenários ({[x for x, v in need.items() if v not in ids]})")
check("11.3", not re.search(r"^\s*(begin|commit|rollback)\s*;", h, re.I | re.M) and "MS894" in h and "PENDENTE" in h
      and "binder_activity_item)" in h and "collection_pokedex_position_assignment)" in h,
      "5894: sem BEGIN/COMMIT, sentinela, concorrência pendente, resíduo inclui histórico e atribuições")
for ev in ("'CARDS_AUTO_ARRANGED'", "'CARD_LEFT_BY_INVENTORY_EXIT'", "'COLLECTION_ATTACHED'", "'LEGACY_CATALOG_INCORPORATION'",
           "'CATALOG_NOVELTIES_INCORPORATED', 'FICHARIO'", "'CARD_MOVED', 'FICHARIO', null, true",
           "values (l_m, v_cf, k1::text || ':*'), (l_f, v_cm, k2::text || ':*')", "transfer_my_binder_ownership(v_cf, v_cg)", "wh_5894_ev(u_c, l_f, 34, u_c, 'CARD_MOVED', 'FICHARIO', null, true)"):
    check(f"11.4{ev[:12]}", ev in h, f"5894 grava o caso {ev}")

# 8. Entregas anteriores ------------------------------------------------------------------------------
st = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "web", "database/schema"]
                    + [os.path.join("database", "proposals", d) for d in PRIOR], capture_output=True, text=True).stdout.strip()
check("12.1", st == "", f"frontend, schema canônico e E1-A … E1-C2 sem alterações ({st or 'limpo'})")
check("12.2", all(not os.path.exists(os.path.join(SCHEMA, m)) for m in MIG)
      and not any(f.startswith(("5323", "5324", "5388", "5894")) for f in os.listdir(SCHEMA)),
      "nada copiado para database/schema (só entra depois de executado)")

passes = sum(1 for _, ok, _ in R if ok)
for cid, ok, det in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:<14} {det}")
print(f"GATE  {'PASS' if passes == len(R) else 'FAIL'}  {passes}/{len(R)}")
sys.exit(0 if passes == len(R) else 1)
