#!/usr/bin/env python3
"""Verificação estática das migrations 5263–5266 e do harness 5859
(BINDER-CATALOG-RECONCILIATION). Não conecta em banco.

Uso (a partir da raiz do repositório):
    python3 database/proposals/2026-10-24-binder-catalog-reconciliation/static_check_catalog_reconciliation.py

Regras:
  S1  cada migration: exatamente um BEGIN; e um COMMIT; (fora de corpos e
      comentários), nenhum ROLLBACK;
  S2  toda função criada é SECURITY DEFINER com SET search_path = ''
  S3  RPCs: REVOKE de PUBLIC/anon e GRANT só a authenticated; internas:
      REVOKE de public, anon, authenticated, service_role e nenhum GRANT
  S4  nenhuma função criada já existe em database/schema (nada substituído:
      5187, 5224/5251, 5243, 5257–5260 intactas)
  S5  tabelas escritas diretamente: collection_layout_slot_expected_content
      e collection_layout_catalog_incorporation (W5); nenhuma escrita em
      referências de espécie, alocações, exemplares, regiões ou imagens;
      DDL só na 5263 (1 tabela + 1 índice), nenhum gatilho/política/view
  S6  leituras STABLE; aplicação VOLATILE com lock_timeout = '5s'
  S7  sem nome de coluna-saída não qualificado comparado com '=' em funções
      com #variable_conflict use_column (armadilha de resolução)
  S8  ordem idêntica ao planejamento original: a chave ORDER BY de
      binder_catalog_positions é textualmente a do ramo MASTER_SET de
      collection_binder_plan (5251, canônica)
  S9  limites e token: 500 linhas movidas, 100 itens, prefixo rc1
  S10 harness: total declarado = checagens distintas; status NÃO EXECUTADA
  S11 W1: token sem texto dependente de sessão (sem marker_at::text, sem md5(e::text))
  S12 W2: na aplicação, OVER_LIMIT é tratado antes da comparação do token
  S13 W3/W6: plano tem UPGRADE_RESERVATION, REVIEW_REQUIRED, OUT_OF_ORDER e NEEDS_REVIEW;
      aplicação converte reserva genérica com UPDATE de exatamente 1 linha
  S14 W5 tabela (5263): PK (layout_id, collection_id, item_key); FKs fichário e
      coleção ON DELETE CASCADE; CHECK de formato; RLS ligada; REVOKE ALL de
      public, anon, authenticated, service_role; nenhum GRANT nem política
  S15 W5 escrita: só apply_my_binder_catalog_reconciliation insere na tabela,
      com ON CONFLICT DO NOTHING e contagem exata, DEPOIS das pós-condições
      e sem UPDATE/DELETE; só binder_catalog_novelties a lê; 5264 exige 5263
  S16 A7 marco (5263 v2.1): tabela com PK (layout_id, collection_id), FKs CASCADE, 2 CHECKs,
      coluna ended_xact xid8 nula, RLS, REVOKE de 4 papéis, sem GRANT; 5 gatilhos AFTER
      comuns com os nomes previstos, nenhum de restrição nem diferido (independência de
      SET CONSTRAINTS); limpeza encerra (UPDATE ended_xact), não apaga; reativação
      compara ended_xact com pg_current_xact_id(); LOCK TABLE convidadas → fichários
      DENTRO de bloco PL/pgSQL; preenchimento só com datas existentes depois da trava e
      da recusa por indício de transferência
  S17 A7 leitura: só binder_catalog_context lê a tabela de marcos (só linhas com
      ended_xact NULL) e só as funções de gatilho a escrevem; o contexto não deriva o
      marco de created_at do fichário ou da convidada e trata ausência como
      MARKER_MISSING; 5264 exige a tabela de marcos
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MIGRATIONS = sorted(HERE.glob("526[3-6]_*.sql"))
TABLE = "collection_layout_catalog_incorporation"
MARKER = "collection_layout_catalog_marker"
TRIGGER_FUNCS = {
    "binder_catalog_marker_on_layout_insert",
    "binder_catalog_marker_on_owner_change",
    "binder_catalog_marker_on_guest_insert",
    "binder_catalog_marker_cleanup",
}
PUBLIC_RPCS = {
    "get_my_binder_catalog_novelties",
    "preview_my_binder_catalog_reconciliation",
    "apply_my_binder_catalog_reconciliation",
}
INTERNAL = {
    "binder_catalog_context",
    "binder_catalog_assert_eligible",
    "binder_catalog_positions",
    "binder_catalog_novelties",
    "binder_catalog_plan",
}
STABLE = {"get_my_binder_catalog_novelties", "preview_my_binder_catalog_reconciliation"} | INTERNAL
OUT_NAMES = ("layout_id", "card_id", "variant_type_id", "collection_id", "outcome", "reason", "kind",
             "item_key", "pos_ord", "owner_user_id", "owner_collection_id", "marker_at", "card_set_id")

failures: list[str] = []


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def strip_bodies(sql: str) -> str:
    return re.sub(r"\$(\w*)\$.*?\$\1\$", "$$", sql, flags=re.S)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()


def check(rule: str, ok: bool, detail: str) -> None:
    print(f"{'PASS' if ok else 'FAIL'}  {rule}  {detail}")
    if not ok:
        failures.append(f"{rule}: {detail}")


check("S0", len(MIGRATIONS) == 4 and MIGRATIONS[0].name.startswith("5263_create_binder_catalog_reconciliation_structures"), f"migrations encontradas: {[p.name for p in MIGRATIONS]}")

created: dict[str, str] = {}
bodies: dict[str, str] = {}
headers: dict[str, str] = {}
for path in MIGRATIONS:
    raw = path.read_text(encoding="utf-8")
    no_comments = strip_comments(raw)
    code = strip_bodies(no_comments)
    begins = len(re.findall(r"^\s*begin\s*;", code, flags=re.I | re.M))
    commits = len(re.findall(r"^\s*commit\s*;", code, flags=re.I | re.M))
    rollbacks = len(re.findall(r"\brollback\s*;", code, flags=re.I))
    check("S1", begins == 1 and commits == 1 and rollbacks == 0,
          f"{path.name}: begin={begins} commit={commits} rollback={rollbacks}")

    for m in re.finditer(r"create\s+function\s+public\.(\w+)\s*\((.*?)\)\s*returns(.*?)as\s+\$\$(.*?)\$\$",
                         no_comments, flags=re.I | re.S):
        name, header, body = m.group(1), m.group(3), m.group(4)
        created[name] = path.name
        headers[name] = header
        bodies[name] = body
        ok_def = re.search(r"security\s+definer", header, flags=re.I) is not None
        ok_sp = re.search(r"set\s+search_path\s*=\s*''", header, flags=re.I) is not None
        check("S2", ok_def and ok_sp, f"{path.name}: {name} definer={ok_def} search_path_vazio={ok_sp}")
        revoke = re.search(rf"revoke\s+all\s+on\s+function\s+public\.{name}\s*\([^;]*from\s+([^;]+);", no_comments, flags=re.I)
        grants = re.findall(rf"grant\s+execute\s+on\s+function\s+public\.{name}\s*\([^;]*to\s+(\w+)", no_comments, flags=re.I)
        targets = {t.strip().lower() for t in revoke.group(1).split(",")} if revoke else set()
        if name in PUBLIC_RPCS:
            check("S3", {"public", "anon"} <= targets and grants == ["authenticated"],
                  f"{path.name}: {name} revoke {sorted(targets)} grant {grants}")
        elif name in INTERNAL or name in TRIGGER_FUNCS:
            check("S3", {"public", "anon", "authenticated", "service_role"} <= targets and not grants,
                  f"{path.name}: {name} interna revoke {sorted(targets)} grant {grants}")
        else:
            check("S3", False, f"{path.name}: função não classificada {name}")

check("S0", set(created) == PUBLIC_RPCS | INTERNAL | TRIGGER_FUNCS, f"funções criadas: {sorted(created)}")

schema_dir = ROOT / "database" / "schema"
existing = set()
for p in schema_dir.glob("*.sql"):
    txt = strip_comments(p.read_text(encoding="utf-8", errors="ignore"))
    existing.update(m.group(1) for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)", txt, flags=re.I))
clash = sorted(set(created) & existing)
check("S4", not clash, f"funções existentes substituídas: {clash or 'nenhuma'}")

all_code = "\n".join(strip_comments(p.read_text(encoding="utf-8")) for p in MIGRATIONS)
writes = re.findall(r"\b(insert\s+into|update|delete\s+from)\s+public\.(\w+)", all_code, flags=re.I)
written = sorted({t.lower() for _, t in writes})
ddl_by_file = {p.name: re.findall(r"\b(create|alter|drop)\s+(table|trigger|policy|index|view)\b",
                                  strip_comments(p.read_text(encoding="utf-8")), flags=re.I) for p in MIGRATIONS}
ddl_5263 = sorted((a.lower(), b.lower()) for a, b in ddl_by_file[MIGRATIONS[0].name])
ddl_other = {n: d for n, d in ddl_by_file.items() if n != MIGRATIONS[0].name and d}
ctrg_5263 = len(re.findall(r"\bcreate\s+constraint\s+trigger\b", strip_comments(MIGRATIONS[0].read_text(encoding="utf-8")), flags=re.I))
check("S5", written == sorted(["collection_layout_slot_expected_content", TABLE, MARKER])
      and ddl_5263 == [("alter", "table")] * 2 + [("create", "index")] * 2 + [("create", "table")] * 2 + [("create", "trigger")] * 5
      and ctrg_5263 == 0 and not ddl_other,
      f"tabelas escritas: {written}; DDL 5263: {ddl_5263} + {ctrg_5263} constraint triggers; DDL fora da 5263: {ddl_other or 'nenhum'}")
check("S5", "collection_layout_slot_species_reference" not in re.sub(r"exists\s*\(\s*select\s+1\s+from\s+public\.collection_layout_slot_species_reference", "", all_code, flags=re.I)
      or all_code.lower().count("collection_layout_slot_species_reference") <= 2,
      "referências de espécie: só 'existe alguma?' (contexto) e precheck de existência da tabela")

for name in sorted(created):
    vol = "volatile" if re.search(r"\bvolatile\b", headers[name], flags=re.I) else (
        "stable" if re.search(r"\bstable\b", headers[name], flags=re.I) else "?")
    if name in STABLE:
        check("S6", vol == "stable", f"{name}: {vol}")
    elif name in TRIGGER_FUNCS:
        check("S6", vol == "volatile" and "returns trigger" in norm("returns " + headers[name]), f"{name}: gatilho {vol}")
    else:
        lt = re.search(r"set\s+lock_timeout\s*=\s*'5s'", headers[name], flags=re.I) is not None
        check("S6", vol == "volatile" and lt, f"{name}: {vol}, lock_timeout 5s={lt}")

for name, body in bodies.items():
    if "#variable_conflict use_column" not in body:
        continue
    b = strip_comments(body)
    b = re.sub(r"'(?:[^']|'')*'", "''", b)
    hits = []
    for col in OUT_NAMES:
        for mm in re.finditer(rf"(?<![\.\w:]){col}\s*=(?![=>])", b):
            hits.append(col)
        for mm in re.finditer(rf"(?<![:<>!])=\s*{col}(?![\w.(])", b):
            hits.append(col + "(lado direito)")
    check("S7", not hits, f"{name}: comparações não qualificadas com nomes de coluna-saída: {sorted(set(hits)) or 'nenhuma'}")

src_5251 = strip_comments((schema_dir / "5251_update_binder_plan_physical_location.sql").read_text(encoding="utf-8"))
m_ref = re.search(r"row_number\(\) over \(order by c\.collector_order, c\.collector_number, c\.id,\s*\(m\.variant_type_id is null\),.*?m\.variant_type_id\)\)", src_5251, flags=re.S)
m_new = re.search(r"row_number\(\) over \(order by c\.collector_order, c\.collector_number, c\.id,\s*\(m\.variant_type_id is null\),.*?m\.variant_type_id\)\)", bodies.get("binder_catalog_positions", ""), flags=re.S)
check("S8", bool(m_ref) and bool(m_new) and norm(m_ref.group(0)) == norm(m_new.group(0)),
      "ORDER BY de binder_catalog_positions = ramo MASTER_SET de collection_binder_plan (5251)")

plan = bodies.get("binder_catalog_plan", "")
appl = bodies.get("apply_my_binder_catalog_reconciliation", "")
check("S9", re.search(r"c_row_limit\s+constant integer := 500", plan) is not None
      and re.search(r"c_item_limit\s+constant integer := 100", plan) is not None
      and "'rc1:'" in plan and "^rc1:[0-9a-f]{64}$" in appl,
      "limites 500/100 no plano; token rc1 gerado no plano e exigido na aplicação")

check("S11", "marker_at::text" not in plan and "md5(e::text)" not in plan
      and "extract(epoch from x.marker_at)" in plan,
      "token: marco em epoch, reserva assinada por colunas de identidade (sem datas)")
i_over = appl.find("st.outcome = 'OVER_LIMIT'")
i_tok = appl.find("st.plan_token is distinct from p_plan_token")
check("S12", 0 <= i_over < i_tok, f"OVER_LIMIT (pos {i_over}) antes da comparação do token (pos {i_tok})")
check("S13", all(k in plan for k in ("'UPGRADE_RESERVATION'", "'REVIEW_REQUIRED'", "'OUT_OF_ORDER'", "'NEEDS_REVIEW'"))
      and "set expected_variant_type_id = st.variant_type_id" in appl and "if k <> 1 then" in appl
      and "'RECONCILE_NEEDS_REVIEW'" in appl,
      "W3/W6 presentes no plano e na aplicação (UPDATE de 1 linha; NEEDS_REVIEW recusa)")

# W5 — tabela (5263) --------------------------------------------------------------------------
t_src = strip_comments(MIGRATIONS[0].read_text(encoding="utf-8"))
t_n = norm(t_src)
check("S14", f"create table public.{TABLE} (" in t_n
      and "primary key (layout_id, collection_id, item_key)" in t_n
      and "foreign key (layout_id) references public.collection_layout (id) on update restrict on delete cascade" in t_n
      and "foreign key (collection_id) references public.collection (id) on update restrict on delete cascade" in t_n
      and "check ( item_key ~ '^[0-9a-f]{8}-" in t_n
      and f"alter table public.{TABLE} enable row level security" in t_n
      and f"revoke all on table public.{TABLE} from public, anon, authenticated, service_role" in t_n
      and not re.search(r"\bgrant\b", t_src, flags=re.I)
      and not re.search(r"create\s+policy", all_code, flags=re.I),
      "5263: PK, FKs CASCADE, CHECK, RLS, REVOKE ALL de public/anon/authenticated/service_role, sem GRANT e sem política")

touch = {n for n, b in bodies.items() if TABLE in b}
ins_in = {n for n, b in bodies.items() if re.search(rf"insert\s+into\s+public\.{TABLE}", b, flags=re.I)}
upd_del = re.findall(rf"\b(update|delete\s+from)\s+public\.{TABLE}", all_code, flags=re.I)
i_post = appl.find("where nv.is_reserved is distinct from true")
i_ins = appl.find(f"insert into public.{TABLE}")
check("S15", ins_in == {"apply_my_binder_catalog_reconciliation"}
      and touch == {"apply_my_binder_catalog_reconciliation", "binder_catalog_novelties"}
      and not upd_del
      and "on conflict (layout_id, collection_id, item_key) do nothing" in appl
      and re.search(r"if k <> cardinality\(v_pending\) then", appl[i_ins:] if i_ins >= 0 else "") is not None
      and 0 <= i_post < i_ins
      and "not exists (select 1 from inc where inc.k = pos.pos_key)" in bodies.get("binder_catalog_novelties", "")
      and f"to_regclass('public.{TABLE}') is null" in (HERE / MIGRATIONS[1].name).read_text(encoding="utf-8"),
      f"escrita só na aplicação (ON CONFLICT DO NOTHING + contagem exata, após pós-condições pos {i_post} < {i_ins}); "
      f"leitura só nas novidades; sem UPDATE/DELETE; 5264 exige 5263; funções que tocam: {sorted(touch)}")

# A7 — marco de participação (5263) -------------------------------------------------------------
check("S16", f"create table public.{MARKER} (" in t_n
      and "primary key (layout_id, collection_id)" in t_n
      and t_n.count("references public.collection_layout (id) on update restrict on delete cascade") == 2
      and t_n.count("references public.collection (id) on update restrict on delete cascade") == 2
      and "constraint chk_cl_cm_source check" in t_n and "constraint chk_cl_cm_role check" in t_n
      and f"alter table public.{MARKER} enable row level security" in t_n
      and f"revoke all on table public.{MARKER} from public, anon, authenticated, service_role" in t_n
      and all(f"create trigger {tg} after" in t_n for tg in ("trg_cl_catalog_marker_layout_insert",
                                                          "trg_cl_catalog_marker_owner_change",
                                                          "trg_cl_catalog_marker_guest_insert",
                                                          "trg_cl_catalog_marker_guest_cleanup",
                                                          "trg_cl_catalog_marker_owner_cleanup"))
      and "deferrable" not in t_n and "constraint trigger" not in t_n
      and "ended_xact xid8 null" in t_n
      and "set ended_xact = pg_current_xact_id()" in t_n
      and t_n.count("m.ended_xact = pg_current_xact_id()") >= 4
      and f"delete from public.{MARKER}" not in t_n
      and re.search(r"do \$pre2\$ begin [^$]*lock table public\.collection_layout_guest, public\.collection_layout in share row exclusive mode", t_n) is not None
      and not re.search(r"^\s*lock\s+table", strip_comments(MIGRATIONS[0].read_text(encoding="utf-8")).split("do $pre2$")[0], flags=re.I | re.M)
      and "select l.id, l.collection_id, l.created_at, 'backfill_owner', 'owner' from public.collection_layout l" in t_n
      and "select g.layout_id, g.collection_id, g.created_at, 'backfill_guest', 'guest' from public.collection_layout_guest g" in t_n
      and 0 <= t_n.find("lock table public.collection_layout_guest, public.collection_layout in share row exclusive mode")
             < t_n.find("e.created_at < g.created_at") < t_n.find("'backfill_owner'"),
      "5263 marcos: estrutura, deny-by-default, 5 gatilhos imediatos sem diferimento, encerramento por ended_xact, trava convidadas→fichários dentro do bloco, preenchimento com datas existentes após recusa por indício")

mk_touch = {n for n, b in bodies.items() if MARKER in b}
mk_write = {n for n, b in bodies.items() if re.search(rf"(insert\s+into|update|delete\s+from)\s+public\.{MARKER}", b, flags=re.I)}
ctx = bodies.get("binder_catalog_context", "")
check("S17", mk_write == TRIGGER_FUNCS
      and mk_touch == TRIGGER_FUNCS | {"binder_catalog_context"}
      and "l.created_at" not in ctx and "g.created_at" not in ctx
      and f"from public.{MARKER} m" in ctx and "'MARKER_MISSING'" in ctx and "m.ended_xact is null" in ctx
      and f"to_regclass('public.{MARKER}') is null" in (HERE / MIGRATIONS[1].name).read_text(encoding="utf-8"),
      f"marco: escrito só pelos gatilhos {sorted(mk_write)}; lido só pelo contexto; sem created_at derivado; MARKER_MISSING; 5264 exige a tabela")

harness = next(HERE.glob("5859_*.sql")).read_text(encoding="utf-8")
ids = re.findall(r"jsonb_build_object\('id','([0-9A-Z.]+)'", harness)
real = sorted({i for i in ids if not (i.startswith("X.") or i.startswith("F.0"))})
expected = int(re.search(r"v_expected integer := (\d+);", harness).group(1))
check("S10", len(real) == expected and "NÃO EXECUTADA" in harness,
      f"harness: {len(real)} checagens distintas, esperado declarado {expected}; status NÃO EXECUTADA")

print()
print("RESULTADO:", "PASS" if not failures else f"FAIL ({len(failures)})")
sys.exit(1 if failures else 0)
