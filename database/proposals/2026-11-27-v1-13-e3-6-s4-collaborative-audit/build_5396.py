#!/usr/bin/env python3
"""
V1-13 · E3-6 / S4-c — gera 5396 (e o rollback) a partir do texto CANÔNICO implantado:

  - 5258 (titular): apply_my_binder_species_references, clear_my_binder_species_references,
    set_my_binder_species_reference_visibility;
  - 5383 protegida G1 (EDITOR): editor_apply_binder_species_references,
    editor_clear_binder_species_references, editor_set_binder_species_reference_visibility;
  - 5384: binder_activity_event_editor_type_guard (tipos permitidos ao EDITOR);
  - 5341: binder_activity_category (categoria SPECIES).

Inserções em pontos fixos, entre "-- [5396+]" / "-- [5396-]", para a verificação estática provar
que, removidos os blocos, cada corpo é o canônico (md5). Uma primitiva interna nova
(binder_activity_record_species) grava UM evento por operação efetiva, sem itens.

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s4-collaborative-audit/build_5396.py
"""
import hashlib
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
S = os.path.join(ROOT, "database", "schema")
P = os.path.join(ROOT, "database", "proposals")
A, Z = "-- [5396+]", "-- [5396-]"
md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()


def fn_def(path, name):
    t = open(path, encoding="utf-8").read()
    m = re.search(r"create\s+(?:or\s+replace\s+)?function\s+public\." + re.escape(name) + r"\s*\(", t, re.I)
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", t[m.end():], re.I)
    s = m.end() + a.end()
    e = t.index(a.group(1), s) + len(a.group(1))
    return t[m.start():e] + ";"


def prosrc(d):
    a = re.search(r"\bas\s+(\$[a-z_]*\$)", d, re.I)
    s = a.end()
    return d[s:d.index(a.group(1), s)]


def as_replace(d):  # mesmo texto, "create function" → "create or replace function" (fora do corpo)
    return re.sub(r"^create\s+function\s+", "create or replace function ", d, count=1, flags=re.I)


def ins_after(text, anchor, block):
    assert text.count(anchor) == 1, anchor[:70]
    return text.replace(anchor, anchor + "\n" + A + "\n" + block.rstrip("\n") + "\n" + Z, 1)


def ins_before(text, anchor, block):
    assert text.count(anchor) == 1, anchor[:70]
    return text.replace(anchor, A + "\n" + block.rstrip("\n") + "\n" + Z + "\n" + anchor, 1)


R = "  -- [5396~]"   # marca de linha SUBSTITUÍDA (o static check desfaz a lista declarada em REPL)
REPL: dict[str, list[tuple[str, str]]] = {}


def rep(name, text, old, new):
    """Substitui um trecho exato (único) e marca a 1ª linha nova com [5396~]."""
    assert text.count(old) == 1, (name, old[:70])
    first, nl, rest = new.partition("\n")
    marked = first + R + nl + rest
    assert marked not in text
    REPL.setdefault(name, []).append((old, marked))
    return text.replace(old, marked, 1)


def unrep(name, text):
    for old, marked in REPL.get(name, []):
        text = text.replace(marked, old, 1)
    return text


F5258 = os.path.join(S, "5258_create_binder_species_reference_writes.sql")
F5383 = os.path.join(P, "2026-11-15-v1-13-e1e-security-evidence", "g1", "protected", "5383_create_editor_binder_species_reference_operations.sql")
F5384 = os.path.join(P, "2026-11-15-v1-13-e1c2-remaining-bulk-operations", "5384_extend_editor_binder_activity_event_types.sql")
F5341 = os.path.join(S, "5341_extend_binder_activity_auto_arrange_event.sql")
F5269 = os.path.join(S, "5269_create_binder_activity_reads.sql")
F5388 = os.path.join(P, "2026-11-15-v1-13-e1e-security-evidence", "e1deploy", "5388_create_get_shared_binder_activity_functions_R1.sql")

SRC = {  # nome: (arquivo, assinatura, md5 canônico do corpo)
    "apply_my_binder_species_references": (F5258, "(uuid, text)", "1fc0bbcbb88ef4722478cbd74db996c2"),
    "clear_my_binder_species_references": (F5258, "(uuid, integer)", "723724fb7d47c135021ffe3c2cac3d1c"),
    "set_my_binder_species_reference_visibility": (F5258, "(uuid, boolean)", "bf3385f8ddb943581a19a0502b40b8c7"),
    "editor_apply_binder_species_references": (F5383, "(uuid, text)", "54d14043bc2826f687867c60c241db1f"),
    "editor_clear_binder_species_references": (F5383, "(uuid, integer)", "dcc32db55aef7978b37c4ba1dc55f44b"),
    "editor_set_binder_species_reference_visibility": (F5383, "(uuid, boolean)", "0a1955ff43cdc3a3b23f87bf38efa42d"),
    "binder_activity_event_editor_type_guard": (F5384, "()", "78fa0d34dad161eac1165f3143874260"),
    "binder_activity_category": (F5341, "(text)", "a7f9f99fa1f98171897904ed6d380bc4"),
    "get_my_binder_activity": (F5269, "(uuid, text[], timestamptz, bigint, integer)", "fab40eb28280d7c62ca207642b35ff65"),
    "get_shared_binder_activity": (F5388, "(uuid, text[], timestamptz, bigint, integer)", "5b2887919ed00aca98b20d048f10722b"),
}
READS = ["get_my_binder_activity", "get_shared_binder_activity"]
OWNER = ["apply_my_binder_species_references", "clear_my_binder_species_references", "set_my_binder_species_reference_visibility"]
EDITOR = ["editor_apply_binder_species_references", "editor_clear_binder_species_references", "editor_set_binder_species_reference_visibility"]
CANON = {n: as_replace(fn_def(p, n)) for n, (p, _, _) in SRC.items()}
for n, (_, _, h) in SRC.items():
    assert md5(prosrc(CANON[n])) == h, n

SPECIES = ["SPECIES_REFERENCES_APPLIED", "SPECIES_REFERENCES_CLEARED", "SPECIES_REFERENCES_SHOWN", "SPECIES_REFERENCES_HIDDEN"]
TYPES_5341 = ["BINDER_ASSEMBLED", "CARD_PLACED", "CARD_MOVED", "CARDS_SWAPPED", "CARDS_REMOVED", "CARDS_LEFT_BY_STORAGE",
              "CARDS_LEFT_BY_COLLECTION_STORAGE", "CARD_LEFT_BY_INVENTORY_EXIT", "POCKET_RESERVED", "RESERVATIONS_RELEASED",
              "POCKETS_LOCKED", "POCKETS_UNLOCKED", "GAP_OPENED", "GAP_CLOSED", "PAGES_ADDED", "PAGE_REMOVED", "PAGES_REORDERED",
              "CATALOG_NOVELTIES_INCORPORATED", "COLLECTION_ATTACHED", "COLLECTION_DETACHED", "BINDER_DISMANTLED",
              "BINDER_DELETED_EMPTY", "BINDER_OWNERSHIP_TRANSFERRED", "LEGACY_CATALOG_INCORPORATION", "CARDS_AUTO_ARRANGED"]
assert all("'" + x + "'" in open(F5341, encoding="utf-8").read() for x in TYPES_5341)
SPECIES_SQL = ", ".join(f"'{x}'" for x in SPECIES)

NEW = {}

# 5258 — titular: aplicar (APPLIED → APPLIED; ALREADY_APPLIED com referências ocultas → SHOWN)
t = CANON["apply_my_binder_species_references"]
t = ins_after(t, "  v_count integer;", """  v_audit        boolean := false;
  v_prev_visible boolean;""")
t = ins_before(t, "  if pv.already_applied then", """  v_audit := public.v1_13_capability_open();
  if v_audit then
    select st.references_visible into v_prev_visible
    from public.collection_layout_species_reference_setting st
    where st.layout_id = t.layout_id
    for update;
    v_prev_visible := coalesce(v_prev_visible, true);
  end if;""")
t = ins_after(t, """  select count(*)::integer into v_count
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;""", """  if v_audit then
    if operation = 'APPLIED' then
      perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_APPLIED', null);
    elsif not v_prev_visible then
      perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_SHOWN', null);
    end if;
  end if;""")
NEW["apply_my_binder_species_references"] = t

# 5258 — titular: remover (REMOVED com contagem > 0)
t = CANON["clear_my_binder_species_references"]
t = ins_after(t, "  get diagnostics v_removed = row_count;", """  if v_removed > 0 and public.v1_13_capability_open() then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_CLEARED', v_removed);
  end if;""")
NEW["clear_my_binder_species_references"] = t

# 5258 — titular: mostrar/ocultar (só UPDATED)
t = CANON["set_my_binder_species_reference_visibility"]
t = ins_after(t, "    do update set references_visible = excluded.references_visible, updated_at = now();", """    if public.v1_13_capability_open() then
      perform public.binder_activity_record_species(v_layout, p_collection_id,
        case when p_visible then 'SPECIES_REFERENCES_SHOWN' else 'SPECIES_REFERENCES_HIDDEN' end, null);
    end if;""")
NEW["set_my_binder_species_reference_visibility"] = t

# 5383 — EDITOR (a barreira já foi exigida no início de cada função: registro obrigatório)
t = CANON["editor_apply_binder_species_references"]
t = ins_after(t, "  v_count integer;", """  v_prev_visible boolean;""")
t = ins_before(t, "  if s.already_applied then", """  select st.references_visible into v_prev_visible
  from public.collection_layout_species_reference_setting st
  where st.layout_id = t.layout_id
  for update;
  v_prev_visible := coalesce(v_prev_visible, true);""")
t = ins_after(t, """  select count(*)::integer into v_count
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;""", """  if v_op = 'APPLIED' then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_APPLIED', null);
  elsif not v_prev_visible then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_SHOWN', null);
  end if;""")
NEW["editor_apply_binder_species_references"] = t

t = CANON["editor_clear_binder_species_references"]
t = ins_after(t, "  get diagnostics v_removed = row_count;", """  if v_removed > 0 then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_CLEARED', v_removed);
  end if;""")
NEW["editor_clear_binder_species_references"] = t

t = CANON["editor_set_binder_species_reference_visibility"]
t = ins_after(t, "  do update set references_visible = excluded.references_visible, updated_at = now();", """  perform public.binder_activity_record_species(t.layout_id, p_collection_id,
    case when p_visible then 'SPECIES_REFERENCES_SHOWN' else 'SPECIES_REFERENCES_HIDDEN' end, null);""")
NEW["editor_set_binder_species_reference_visibility"] = t

# 5384 — o EDITOR pode gravar os 4 tipos (origem FICHARIO, coleção obrigatória — regra existente)
t = CANON["binder_activity_event_editor_type_guard"]
t = ins_after(t, "          and new.source = 'FICHARIO')", f"""         or (new.event_type in ({SPECIES_SQL}) and new.source = 'FICHARIO')""")
NEW["binder_activity_event_editor_type_guard"] = t

# 5341 — categoria SPECIES
t = CANON["binder_activity_category"]
t = ins_after(t, "                          'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED') then 'BINDER'",
              f"""    when p_event_type in ({SPECIES_SQL.replace(", ", ",")}) then 'SPECIES'""")
NEW["binder_activity_category"] = t

# 5269 — titular: o filtro aceita SPECIES (demais valores e comportamento inalterados) — D-5396-2
CAT_OLD = "  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER']) then"
CAT_NEW = "  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER','SPECIES']) then"
t = CANON["get_my_binder_activity"]
t = rep("get_my_binder_activity", t, CAT_OLD, CAT_NEW)
NEW["get_my_binder_activity"] = t

# 5388 — participante ACTIVE (D-5396-1): eventos SPECIES de X, atribuídos, origem FICHARIO, sem itens.
# Acesso (barreira, collection_share_role OWNER/VIEWER, titular e fichário de X), cursor, ordem e
# colunas inalterados; summary continua NÃO devolvido. Os demais tipos continuam exigindo item de X.
n5388 = "get_shared_binder_activity"
t = CANON[n5388]
t = rep(n5388, t, CAT_OLD, CAT_NEW)
t = ins_after(t, "              or (e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')))",
              f"""        or (e.item_collection_recorded and e.source = 'FICHARIO' and e.collection_id = p_collection_id
            and e.event_type in ({SPECIES_SQL}))""")
t = rep(n5388, t, "      and exists (\n        select 1 from public.binder_activity_item i",
        f"      and (e.event_type in ({SPECIES_SQL}) or exists (\n        select 1 from public.binder_activity_item i")
t = rep(n5388, t, "               end))\n    order by e.occurred_at desc, e.id desc",
        "               end)))\n    order by e.occurred_at desc, e.id desc")
t = rep(n5388, t, "         a.n,\n", "         coalesce(a.n, 0),\n")
t = rep(n5388, t, "         a.n > 50\n", "         coalesce(a.n, 0) > 50\n")
t = rep(n5388, t, "  join agg a on a.event_id = pg.id", "  left join agg a on a.event_id = pg.id")
NEW[n5388] = t

NEWMD5 = {n: md5(prosrc(NEW[n])) for n in NEW}

RECORD = """create function public.binder_activity_record_species(
  p_layout_id     uuid,
  p_collection_id uuid,
  p_event_type    text,
  p_removed_count integer
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid      uuid := (select auth.uid());
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_owner    uuid;
  v_main     uuid;
  v_binder   text;
  v_collname text;
  v_visible  boolean;
  v_n        integer;
  v_first    integer;
  v_last     integer;
  v_sum      jsonb;
  v_id       bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_layout_id is null or p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  -- Operação de referências nunca é aninhada numa operação de fichário aberta (5268).
  if v_ctx is not null and (v_ctx ->> 'depth')::integer > 0 then
    raise exception 'binder activity: species event inside an open operation' using errcode = 'P0001',
      hint = 'BINDER_ACTIVITY_NESTED_SPECIES';
  end if;

  -- Titular = dono do fichário agora; coleção = a dona do fichário ou convidada do mesmo titular.
  select c.owner_user_id, l.collection_id, coalesce(nullif(l.display_name, ''), c.name)
    into v_owner, v_main, v_binder
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = p_layout_id;
  if v_owner is null then
    raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
  end if;
  select c.name into v_collname
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner
    and (c.id = v_main or exists (select 1 from public.collection_layout_guest g
                                  where g.layout_id = p_layout_id and g.collection_id = c.id));
  if v_collname is null then
    raise exception 'binder activity: collection not in binder' using errcode = '42501', hint = 'BINDER_ACTIVITY_SPECIES_COLLECTION';
  end if;
  -- Autor derivado no servidor: o titular, ou EDITOR ativo da coleção dona do fichário.
  if v_uid <> v_owner
     and not (p_collection_id = v_main
              and exists (select 1 from public.collection_membership m
                          where m.collection_id = p_collection_id and m.user_id = v_uid
                            and m.status = 'ACTIVE' and m.role = 'EDITOR')) then
    raise exception 'binder activity: actor not authorized' using errcode = '42501', hint = 'BINDER_ACTIVITY_NOT_OWNER';
  end if;

  select st.references_visible into v_visible
  from public.collection_layout_species_reference_setting st where st.layout_id = p_layout_id;
  v_visible := coalesce(v_visible, true);

  -- Resumo montado aqui, a partir do estado gravado: só contagens e números nacionais.
  if p_event_type = 'SPECIES_REFERENCES_APPLIED' and p_removed_count is null then
    select count(*)::integer, min(pp.position_number), max(pp.position_number) into v_n, v_first, v_last
    from public.collection_layout_slot_species_reference r
    join public.pokedex_position pp on pp.id = r.pokedex_position_id
    where r.layout_id = p_layout_id and r.collection_id = p_collection_id;
    if v_n > 0 and v_visible then
      v_sum := jsonb_build_object('reference_count', v_n, 'first_number', v_first, 'last_number', v_last, 'visible', true);
    end if;
  elsif p_event_type = 'SPECIES_REFERENCES_CLEARED' and p_removed_count > 0 then
    if not exists (select 1 from public.collection_layout_slot_species_reference r
                   where r.layout_id = p_layout_id and r.collection_id = p_collection_id) then
      v_sum := jsonb_build_object('removed_count', p_removed_count);
    end if;
  elsif p_event_type = 'SPECIES_REFERENCES_SHOWN' and p_removed_count is null and v_visible then
    v_sum := '{}'::jsonb;
  elsif p_event_type = 'SPECIES_REFERENCES_HIDDEN' and p_removed_count is null and not v_visible then
    v_sum := '{}'::jsonb;
  end if;
  if v_sum is null then
    raise exception 'binder activity: invalid species event' using errcode = '22023', hint = 'BINDER_ACTIVITY_SPECIES_EVENT';
  end if;

  insert into public.binder_activity_event
    (owner_user_id, layout_key, actor_user_id, event_type, source,
     collection_id, collection_name, binder_name, summary, item_collection_recorded)
  values
    (v_owner, p_layout_id, v_uid, p_event_type, 'FICHARIO',
     p_collection_id, left(v_collname, 200), left(v_binder, 200), v_sum, true)
  returning id into v_id;
  return v_id;
end;
$fn$;"""

HEAD = """/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5396 - Auditoria das referências de espécie no histórico do fichário
              (V1-13 · E3-6 / S4-c, D-E3-8, D-5395-1, D-5396-1, D-5396-2)
Versão......: 1.2 (2026-11-27, `S4-c/5396 SQLSTATE 22P02 ROOT CAUSE & CORRECTION-01`: postcheck com
              pertencimento tipado ao proconfig); 1.1: HISTORY VISIBILITY & CONTRACT CORRECTION-01;
              1.0: PREPARATION-01. Tentativa 1.1 → STOP-LIVE (run-20261127T151841Z).
Status......: PROPOSTA — NÃO EXECUTADA. GERADA por build_5396.py a partir do texto canônico
              implantado. Execução só com PRE aprovado, expectativas de escritores,
              auditoria independente e autorização expressa, pelo executor por arquivo.
Autor.......: Fabrício Sales / Claude
Altera......: CREATE OR REPLACE de 10 funções, com o texto implantado + blocos [5396+]…[5396-]
              (inserções) e linhas marcadas [5396~] (substituições declaradas no gerador):
              - 3 do titular (5258) e 3 do EDITOR (5383 G1) — aplicar, remover, mostrar/ocultar:
                chamam binder_activity_record_species depois da escrita efetiva; titular só com
                v1_13_capability_open() (CLOSED → caminho de hoje); EDITOR sempre (barreira já
                exigida no início da função);
              - binder_activity_category (5341): + categoria SPECIES;
              - binder_activity_event_editor_type_guard (5384): o EDITOR pode gravar os 4 tipos;
              - get_my_binder_activity (5269): filtro aceita SPECIES (D-5396-2);
              - get_shared_binder_activity (5388 R1): eventos SPECIES de X para titular e
                participantes ACTIVE, sem itens e sem summary (D-5396-1).
              chk_bae_event_type (5267/5341): + 4 tipos — por ÚLTIMO, para o ACCESS EXCLUSIVE
              ficar o menor tempo possível antes do commit.
Cria........: binder_activity_record_species(uuid, uuid, text, integer) — interna, sem EXECUTE
              para a API: um evento por operação efetiva, sem itens, autor e resumo derivados.
Não altera..: get_shared_binder_activity_status, demais funções 5258/5269/5383, 5394/5395.
Reversão....: ROLLBACK_5396.sql (restaura o canônico; nunca apaga eventos; mantém o CHECK
              ampliado se já houver eventos SPECIES_*).
================================================================
*/
"""


def md5_line(sig, h, op="is distinct from"):
    return f"(select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.{sig}')) {op} '{h}'"


def types_sql(lst):
    return "array[" + ", ".join(f"'{x}'" for x in sorted(lst, key=lambda s: s.encode())) + "]::text[]"


TYPES_EXPR = ("(select array_agg(m.v[1] order by m.v[1] collate \"C\") from pg_catalog.pg_constraint k "
              "cross join lateral regexp_matches(pg_catalog.pg_get_constraintdef(k.oid), '''([A-Z0-9_]+)''', 'g') as m(v) "
              "where k.conrelid = 'public.binder_activity_event'::regclass and k.conname = 'chk_bae_event_type')")


def constraint_sql(types, indent=""):
    body = ("alter table public.binder_activity_event drop constraint chk_bae_event_type;\n"
            "alter table public.binder_activity_event add constraint chk_bae_event_type check (event_type in (\n    "
            + ",\n    ".join(f"'{x}'" for x in types) + "\n  ));")
    return "\n".join(indent + l for l in body.split("\n"))


ORDER = ["binder_activity_category", "binder_activity_event_editor_type_guard"] + OWNER + EDITOR + READS
SPECIES_EXISTS = f"exists (select 1 from public.binder_activity_event e where e.event_type in ({SPECIES_SQL}))"
OWNER_TBL = ("pg_catalog.pg_has_role(current_user, (select c.relowner from pg_catalog.pg_class c "
             "where c.oid = 'public.binder_activity_event'::regclass), 'USAGE')")


def build():
    sig = lambda n: n + SRC[n][1]
    pre = ["  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'\n     or (select count(*) from public.v1_13_barrier_identity) <> 0 then\n    raise exception 'PRECHECK 5396: barreira não está CLOSED';\n  end if;",
           "  if " + "\n     or ".join(md5_line(sig(n), SRC[n][2]) for n in SRC) + " then\n    raise exception 'PRECHECK 5396: ESTADO DIVERGENTE — funções diferem do canônico (5258/5383/5384/5341/5269/5388)';\n  end if;",
           f"  if {TYPES_EXPR} is distinct from {types_sql(TYPES_5341)} then\n    raise exception 'PRECHECK 5396: chk_bae_event_type difere da 5341';\n  end if;",
           f"  if not {OWNER_TBL} then\n    raise exception 'PRECHECK 5396: executor não é dono de binder_activity_event';\n  end if;",
           "  if to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)') is not null then\n    raise exception 'PRECHECK 5396: JÁ APLICADA ou ESTADO DIVERGENTE';\n  end if;"]
    post = ["  if " + "\n     or ".join(md5_line(sig(n), NEWMD5[n]) for n in SRC) + " then\n    raise exception 'POSTCHECK 5396: funções fora do texto instrumentado';\n  end if;",
            f"  if {TYPES_EXPR} is distinct from {types_sql(TYPES_5341 + SPECIES)} then\n    raise exception 'POSTCHECK 5396: chk_bae_event_type fora do esperado';\n  end if;",
            "  foreach f in array array[" + ",\n                           ".join(f"to_regprocedure('public.{sig(n)}')" for n in OWNER + EDITOR + READS) + "] loop\n    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true\n       or not (array['search_path=\"\"'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))\n       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true\n       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then\n      raise exception 'POSTCHECK 5396: segurança ou privilégios alterados (%)', f::regprocedure;\n    end if;\n  end loop;",
            "  if (select bool_and(p.provolatile = 's') from pg_catalog.pg_proc p where p.oid in (" + ", ".join(f"to_regprocedure('public.{sig(n)}')" for n in READS) + ")) is not true then\n    raise exception 'POSTCHECK 5396: leituras deixaram de ser STABLE';\n  end if;",
            "  f := to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)');\n  if f is null\n     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true\n     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=\"\"']\n     or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')\n                and pg_catalog.has_function_privilege(x.oid, f, 'EXECUTE'))\n     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then\n    raise exception 'POSTCHECK 5396: primitiva fora do estado esperado';\n  end if;",
            "  if (select p.provolatile from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_category(text)')) is distinct from 'i'\n     or public.binder_activity_category('SPECIES_REFERENCES_HIDDEN') is distinct from 'SPECIES'\n     or public.binder_activity_category('CARDS_AUTO_ARRANGED') is distinct from 'CARDS'\n     or not exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass\n                    and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O') then\n    raise exception 'POSTCHECK 5396: categoria ou gatilho do EDITOR fora do esperado';\n  end if;",
            f"  if {SPECIES_EXISTS} then\n    raise exception 'POSTCHECK 5396: a migration não deveria gerar eventos';\n  end if;",
            "  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'\n     or (select count(*) from public.v1_13_barrier_identity) <> 0 then\n    raise exception 'POSTCHECK 5396: barreira não está CLOSED';\n  end if;"]
    mig = (HEAD + "\nbegin;\nset local lock_timeout = '3s';\n\ndo $pre$\nbegin\n" + "\n".join(pre) + "\nend;\n$pre$;\n\n"
           + RECORD + "\n\n"
           + "comment on function public.binder_activity_record_species(uuid, uuid, text, integer) is\n  'V1-13 E3-6/S4-c (5396, interna): um evento SPECIES_REFERENCES_* no histórico do fichário por operação efetiva de referências de espécie; autor (titular ou EDITOR ativo da dona do fichário) e resumo (contagens e números nacionais) derivados no servidor; sem itens.';\n"
           + "revoke all on function public.binder_activity_record_species(uuid, uuid, text, integer) from public, anon, authenticated, service_role;\n\n"
           + "\n\n".join(NEW[n] for n in ORDER) + "\n\n"
           + "-- Por último: ACCESS EXCLUSIVE em binder_activity_event até o commit (revalidação da tabela).\n"
           + constraint_sql(TYPES_5341 + SPECIES) + "\n\n"
           + "do $post$\ndeclare\n  f oid;\nbegin\n" + "\n".join(post) + "\nend;\n$post$;\n\ncommit;\n")
    rb = ("""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5396 - Reversão da 5396 (GERADA por build_5396.py)
Versão......: 1.1 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5396
              confirmada. Restaura o texto canônico das 10 funções (5258, 5383 G1, 5384,
              5341, 5269, 5388 R1) e remove binder_activity_record_species.
Eventos.....: NUNCA apaga eventos (histórico imutável). Sem eventos SPECIES_REFERENCES_*,
              volta o chk_bae_event_type da 5341; com eventos, MANTÉM o CHECK ampliado
              (o antigo seria incompatível com as linhas existentes) — os eventos ficam
              guardados, sem categoria e fora das leituras de participante.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if """ + "\n     or ".join(md5_line(sig(n), NEWMD5[n]) for n in SRC) + """ then
    raise exception 'PRECHECK R5396: funções não estão no texto da 5396 — diagnosticar';
  end if;
end;
$pre$;

""" + "\n\n".join(CANON[n] for n in ORDER) + """

drop function public.binder_activity_record_species(uuid, uuid, text, integer);

do $chk$
begin
  if not """ + SPECIES_EXISTS + """ then
""" + constraint_sql(TYPES_5341, "    ") + """
  end if;
end;
$chk$;

do $post$
begin
  if """ + "\n     or ".join(md5_line(sig(n), SRC[n][2]) for n in SRC) + f""" then
    raise exception 'POSTCHECK R5396: funções não voltaram ao canônico';
  end if;
  if {TYPES_EXPR} is distinct from
     (case when {SPECIES_EXISTS} then {types_sql(TYPES_5341 + SPECIES)} else {types_sql(TYPES_5341)} end) then
    raise exception 'POSTCHECK R5396: chk_bae_event_type fora do esperado';
  end if;
  if to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)') is not null then
    raise exception 'POSTCHECK R5396: primitiva ainda presente';
  end if;
end;
$post$;

commit;
""")
    open(os.path.join(HERE, "5396_audit_binder_species_references.sql"), "w", encoding="utf-8", newline="\n").write(mig)
    open(os.path.join(HERE, "ROLLBACK_5396.sql"), "w", encoding="utf-8", newline="\n").write(rb)
    return mig, rb


EXP_REF = sorted(["public.apply_my_binder_species_references(uuid,text)", "public.clear_my_binder_species_references(uuid,integer)",
                  "public.editor_apply_binder_species_references(uuid,text)", "public.editor_clear_binder_species_references(uuid,integer)",
                  "public.editor_remove_binder_page(uuid,integer,integer)", "public.remove_layout_page(uuid,integer)"], key=lambda x: x.encode())
EXP_SET = sorted(["public.apply_my_binder_species_references(uuid,text)", "public.editor_apply_binder_species_references(uuid,text)",
                  "public.editor_set_binder_species_reference_visibility(uuid,boolean)", "public.set_my_binder_species_reference_visibility(uuid,boolean)"],
                 key=lambda x: x.encode())
GSIG = "n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')'"


def _inv(tbl):
    return (f"(select coalesce(string_agg({GSIG}, ', ' order by {GSIG} collate \"C\"), '')\n"
            "                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace\n"
            f"                               where n.nspname = 'public' and p.prosrc ~* '(insert\\s+into|delete\\s+from|update)\\s+public\\.{tbl}\\y')")


def gates():
    sig = lambda n: n + SRC[n][1]
    eq = lambda n, h: f"(select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.{sig(n)}')) = '{h}'"
    canon = ",\n".join("                                 (" + eq(n, SRC[n][2]) + ")" for n in SRC)
    new = ",\n".join("                                 (" + eq(n, NEWMD5[n]) + ")" for n in SRC)
    trig = ("exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass\n"
            "                                       and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O')")
    pre = f"""/*
V1-13 · E3-6 / S4-c — 5396 v1.1: PRE SOMENTE LEITURA (um SELECT). PASS = todos os booleanos de primeiro
nível true; "escritores_referencias"/"escritores_preferencia" (assinatura completa) comparados pelo
executor v1.4 com S4C_5396_EXPECTATIVAS.json. Modo gate.
*/

select jsonb_build_object(
  'executor',                 current_user,
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity),
  'funcoes_canonicas',        (select bool_and(x.ok) from (values
{canon}) x(ok)),
  'tipos_5341',               {TYPES_EXPR} = {types_sql(TYPES_5341)},
  'dono_tabela_eventos',      {OWNER_TBL},
  'gatilho_editor_ativo',     {trig},
  'atribuicao_5379',          exists (select 1 from information_schema.columns c where c.table_schema = 'public'
                                       and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded'),
  'pode_criar_em_public',     pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE'),
  'sem_eventos_especie',      not exists (select 1 from public.binder_activity_event e where e.event_type like 'SPECIES%'),
  'ausente_5396',             to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)') is null,
  'escritores_referencias',   {_inv('collection_layout_slot_species_reference')},
  'escritores_preferencia',   {_inv('collection_layout_species_reference_setting')},
  'privilegios_observaveis',  (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as s4c_5396_pre;
"""
    fs = ", ".join(f"to_regprocedure('public.{sig(n)}')" for n in OWNER + EDITOR + READS)
    rs = ", ".join(f"to_regprocedure('public.{sig(n)}')" for n in READS)
    post = f"""/*
V1-13 · E3-6 / S4-c — 5396 v1.1: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos true, barreira
CLOSED e 0 identidades. Inventário de escritores inalterado (mesmas assinaturas) como booleano. Modo gate.
*/

select jsonb_build_object(
  'funcoes_instrumentadas',   (select bool_and(x.ok) from (values
{new}) x(ok)),
  'tipos_5396',               {TYPES_EXPR} = {types_sql(TYPES_5341 + SPECIES)},
  'privilegios_rpcs',         (select count(*) = {len(OWNER + EDITOR + READS)} and bool_and(p.prosecdef and array['search_path=""'::text] <@ coalesce(p.proconfig, array[]::text[])
                                       and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                       and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'))
                               from pg_catalog.pg_proc p where p.oid in ({fs})),
  'leituras_stable',          (select count(*) = {len(READS)} and bool_and(p.provolatile = 's') from pg_catalog.pg_proc p where p.oid in ({rs})),
  'primitiva_interna',        (select count(*) = 1 from pg_catalog.pg_proc p
                               where p.oid = to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)')
                                 and p.prosecdef and p.proconfig = array['search_path=""']
                                 and not exists (select 1 from pg_catalog.pg_roles x
                                                 where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                                   and pg_catalog.has_function_privilege(x.oid, p.oid, 'EXECUTE'))),
  'categoria_especie',        public.binder_activity_category('SPECIES_REFERENCES_APPLIED') = 'SPECIES'
                              and public.binder_activity_category('SPECIES_REFERENCES_HIDDEN') = 'SPECIES'
                              and public.binder_activity_category('CARDS_AUTO_ARRANGED') = 'CARDS'
                              and public.binder_activity_category('BINDER_ASSEMBLED') = 'BINDER',
  'gatilho_editor_ativo',     {trig},
  'inventario_referencias_pos', {_inv('collection_layout_slot_species_reference')}
                                = '{", ".join(EXP_REF)}',
  'inventario_preferencia_pos', {_inv('collection_layout_species_reference_setting')}
                                = '{", ".join(EXP_SET)}',
  'sem_eventos_especie',      not exists (select 1 from public.binder_activity_event e where e.event_type like 'SPECIES%'),
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity)
) as s4c_5396_post;
"""
    w = lambda f, c: open(os.path.join(HERE, f), "w", encoding="utf-8", newline="\n").write(c)
    w("S4C_5396_PRE_readonly.sql", pre)
    w("S4C_5396_POST_readonly.sql", post)
    import json
    w("S4C_5396_EXPECTATIVAS.json", json.dumps({"escritores_referencias": EXP_REF, "escritores_preferencia": EXP_SET}, indent=2) + "\n")
    h = lambda f: hashlib.sha256(open(os.path.join(HERE, f), "rb").read()).hexdigest()
    W = "database\\proposals\\2026-11-27-v1-13-e3-6-s4-collaborative-audit\\"
    w("S4C_5396_MANIFEST.txt", "# V1-13 · S4-c / 5396 — manifesto do executor por arquivo (STD-005 §3, v1.4). passo|arquivo|sha256|modo\n"
      f"1|{W}S4C_5396_PRE_readonly.sql|{h('S4C_5396_PRE_readonly.sql')}|gate\n"
      f"2|{W}5396_audit_binder_species_references.sql|{h('5396_audit_binder_species_references.sql')}|write\n"
      f"3|{W}S4C_5396_POST_readonly.sql|{h('S4C_5396_POST_readonly.sql')}|gate\n")


if __name__ == "__main__":
    for n in SRC:
        print(f"{n:48} canônico {SRC[n][2]}  instrumentado {NEWMD5[n]}")
    m, r = build()
    gates()
    print("5396:", hashlib.sha256(m.encode()).hexdigest(), "| rollback:", hashlib.sha256(r.encode()).hexdigest())
