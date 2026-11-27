#!/usr/bin/env python3
"""
V1-13 · E3-7b — gera a 5397 (identidade opaca no fichário compartilhado do EDITOR) e os artefatos do
executor a partir do texto CANÔNICO implantado (versões protegidas G1):

  - 5373 get_shared_binder_placeable_cards  → NOVA get_shared_binder_placeable_copies (copy_token no lugar
    de physical_card_id); a antiga fica sem EXECUTE para clientes;
  - 5374 editor_place_card_in_binder         → NOVA editor_place_copy_in_binder (p_copy_token text); a
    antiga fica sem EXECUTE para clientes;
  - 5386 editor_preview_binder_auto_arrange  → CREATE OR REPLACE sem 'physical_card_id' nos itens.

Token: o MESMO da 5391 (v1_13_pokedex_copy_token = 'pc1.' + HMAC(alocação|participação|época)),
resolvido pelo MESMO ajudante interno da 5392 (v1_13_resolve_pokedex_copy). Nenhuma infraestrutura nova.
Inserções entre "-- [5397+]"/"-- [5397-]"; linhas substituídas marcadas "-- [5397~]" (lista declarada em
REPL); a verificação estática desfaz ambas e exige o texto canônico (md5 do LIVE, conferido no G1).

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-7b-binder-opaque-identity/build_5397.py
"""
import hashlib
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PROT = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1", "protected")
S = os.path.join(ROOT, "database", "schema")
A, Z, RM = "-- [5397+]", "-- [5397-]", "  -- [5397~]"
md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()
PKG = "database\\proposals\\2026-11-27-v1-13-e3-7b-binder-opaque-identity\\"


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


F5373 = os.path.join(PROT, "5373_create_get_shared_binder_placeable_cards.sql")
F5374 = os.path.join(PROT, "5374_create_editor_binder_core_writes.sql")
F5386 = os.path.join(PROT, "5386_create_editor_binder_auto_arrange.sql")
F5391 = os.path.join(S, "5391_create_editor_pokedex_copy_identity_and_read.sql") if os.path.exists(os.path.join(S, "5391_create_editor_pokedex_copy_identity_and_read.sql")) else None
if F5391 is None:
    F5391 = next(os.path.join(S, f) for f in sorted(os.listdir(S)) if f.startswith("5391_"))
F5392 = next(os.path.join(S, f) for f in sorted(os.listdir(S)) if f.startswith("5392_"))

OLD = {  # nome: (arquivo, assinatura, md5 canônico do corpo — = md5_protected do G1)
    "get_shared_binder_placeable_cards": (F5373, "(uuid, integer, integer)", "8e9bf913f422eb60fb4dfc82f8741328"),
    "editor_place_card_in_binder": (F5374, "(uuid, integer, integer, integer, uuid)", "d95ab478018a0dd431083cf0af492311"),
    "editor_preview_binder_auto_arrange": (F5386, "(uuid)", "0cb490ec67f551d0044226ab3c34fda1"),
}
DEPS = {  # assinatura: (arquivo, nome, md5) — reutilizados, nunca alterados
    "v1_13_pokedex_copy_token(uuid, uuid, bigint)": (F5391, "v1_13_pokedex_copy_token", "64fa85659b6b999796deeef94dad4e4c"),
    "v1_13_editor_membership(uuid)": (F5391, "v1_13_editor_membership", "856ddff63fd4946f712bca1deeaa7a6c"),
    "v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)": (F5392, "v1_13_resolve_pokedex_copy", "20a6fbe856c0e2ba3987e236d1f00fb3"),
    "v1_13_assert_capability()": (None, None, "e4f710904f50e6e8c3f1d8e2337639e0"),
    "v1_13_capability_open()": (None, None, "32e2f636361732b497e8401e50f0bbe0"),
}
G1 = json.load(open(os.path.join(PROT, "..", "G1_MANIFEST.json"), encoding="utf-8"))
G1MD5 = {k: v["md5_protected"] for f in G1["files"] for k, v in f["functions"].items()}
CANON = {n: fn_def(p, n) for n, (p, _, _) in OLD.items()}
for n, (_, _, h) in OLD.items():
    assert md5(prosrc(CANON[n])) == h == G1MD5[n], n
for sig, (p, n, h) in DEPS.items():
    if p:
        assert md5(prosrc(fn_def(p, n))) == h, sig

REPL: dict[str, list[tuple[str, str]]] = {}


def rep(name, text, old, new):
    assert text.count(old) == 1, (name, old[:70])
    first, nl, rest = new.partition("\n")
    marked = first + RM + nl + rest
    REPL.setdefault(name, []).append((old, marked))
    return text.replace(old, marked, 1)


def ins_after(text, anchor, block):
    assert text.count(anchor) == 1, anchor[:70]
    return text.replace(anchor, anchor + "\n" + A + "\n" + block.rstrip("\n") + "\n" + Z, 1)


def ins_before(text, anchor, block):
    assert text.count(anchor) == 1, anchor[:70]
    return text.replace(anchor, A + "\n" + block.rstrip("\n") + "\n" + Z + "\n" + anchor, 1)


def unrep(name, text):
    for old, marked in REPL.get(name, []):
        text = text.replace(marked, old, 1)
    return text


NEW = {}
NEWNAME = {
    "get_shared_binder_placeable_cards": ("get_shared_binder_placeable_copies", "(uuid, integer, integer)"),
    "editor_place_card_in_binder": ("editor_place_copy_in_binder", "(uuid, integer, integer, integer, text)"),
    "editor_preview_binder_auto_arrange": ("editor_preview_binder_auto_arrange", "(uuid)"),
}

# 5373 → leitura das cartas que o EDITOR pode colocar, por token opaco ---------------------------------
k = "get_shared_binder_placeable_cards"
t = CANON[k]
t = rep(k, t, "create function public.get_shared_binder_placeable_cards(", "create function public.get_shared_binder_placeable_copies(")
t = rep(k, t, "  physical_card_id uuid,\n", "  copy_token       text,\n")
t = ins_after(t, "  v_container uuid;", "  v_mid       uuid;\n  v_epoch     bigint;")
t = ins_after(t, "  if v_owner is null then\n    return;\n  end if;", """  -- 5397: participação e época vigentes do EDITOR — a base do token (5391).
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    return;
  end if;""")
t = rep(k, t, "    select pc.id as pcid, pc.card_variant_id, pc.language_id\n", "    select pc.id as pcid, ca.id as alloc_id, pc.card_variant_id, pc.language_id\n")
t = rep(k, t, "    el.pcid,\n    c.name::text,", "    public.v1_13_pokedex_copy_token(el.alloc_id, v_mid, v_epoch),\n    c.name::text,")
NEW[k] = t

# 5374 → colocar (e desfazer) por token opaco ----------------------------------------------------------
k = "editor_place_card_in_binder"
t = CANON[k]
t = rep(k, t, "create function public.editor_place_card_in_binder(", "create function public.editor_place_copy_in_binder(")
t = rep(k, t, "  p_physical_card_id uuid\n)", "  p_copy_token     text\n)")
t = ins_after(t, "  v_op        text;", "  v_mid       uuid;\n  v_epoch     bigint;\n  v_alloc     uuid;\n  v_pc        uuid;")
t = rep(k, t, "or p_column is null or p_physical_card_id is null\n", "or p_column is null or p_copy_token is null or p_copy_token !~ '^pc1\\.[0-9a-f]{64}$'\n")
t = ins_before(t, "  -- 3. Exemplar elegível (C-235 + DR-1), relido sob trava: do titular, alocado a X,", """  -- 5397: token opaco (5391) → alocação de X pela participação e época VIGENTES do chamador (5392).
  -- Token inválido, de outra coleção, de outra participação ou de época anterior: mesma recusa de sempre.
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  v_alloc := public.v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, null);
  select ca.physical_card_id into v_pc
  from public.collection_allocation ca
  where ca.id = v_alloc and ca.collection_id = p_collection_id;
  if v_mid is null or v_pc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;""")
t = rep(k, t, "  where pc.id = p_physical_card_id\n", "  where pc.id = v_pc\n")
t = rep(k, t, "  where a.physical_card_id = p_physical_card_id\n", "  where a.physical_card_id = v_pc\n")
t = rep(k, t, "    values (v_slot, p_physical_card_id);", "    values (v_slot, v_pc);")
t = rep(k, t, "  perform public.binder_activity_add_card_item('PLACED', p_physical_card_id, null, v_slot);", "  perform public.binder_activity_add_card_item('PLACED', v_pc, null, v_slot);")
NEW[k] = t

# 5386 → prévia sem identidade de exemplar (card_id/card_variant_id: catálogo público) ------------------
k = "editor_preview_binder_auto_arrange"
t = CANON[k]
t = rep(k, t, "create function public.editor_preview_binder_auto_arrange(p_collection_id uuid)", "create or replace function public.editor_preview_binder_auto_arrange(p_collection_id uuid)")
t = rep(k, t, "                                     'ord', p.ord, 'physical_card_id', p.physical_card_id,", "                                     'ord', p.ord,")
NEW[k] = t

NEWMD5 = {k: md5(prosrc(NEW[k])) for k in NEW}
NEWSIG = {k: n + s for k, (n, s) in NEWNAME.items()}
OLDSIG = {k: k + OLD[k][1] for k in OLD}

# Inventários (assinatura completa, ordem C) ------------------------------------------------------------
# escritores_bolso: funções da V1-13 (portão 5389) que gravam collection_layout_slot_assignment.
WRITERS_PRE = sorted([
    "public.editor_apply_binder_auto_arrange(uuid,text)",
    "public.editor_move_binder_card(uuid,integer,integer,integer,integer,integer,integer)",
    "public.editor_place_card_in_binder(uuid,integer,integer,integer,uuid)",
    "public.editor_remove_binder_card(uuid,integer,integer,integer)",
], key=lambda s: s.encode())
WRITERS_POST = sorted(WRITERS_PRE + ["public.editor_place_copy_in_binder(uuid,integer,integer,integer,text)"], key=lambda s: s.encode())
# escritores_exposicao_fisica: funções do EDITOR/participante (editor_/get_shared_/get_editor_) da V1-13,
# executáveis por authenticated, que recebem/devolvem physical_card_id (argumento, coluna ou chave JSON).
EXPO_PRE = sorted([
    "public.editor_place_card_in_binder(uuid,integer,integer,integer,uuid)",
    "public.editor_preview_binder_auto_arrange(uuid)",
    "public.get_shared_binder_placeable_cards(uuid,integer,integer)",
], key=lambda s: s.encode())

GSIG = "n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')'"
GATED = "p.prosrc ~ 'v1_13_(assert_capability|capability_open)'"


def inv_writers():
    return (f"(select coalesce(string_agg({GSIG}, ', ' order by {GSIG} collate \"C\"), '')\n"
            "                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace\n"
            f"                               where n.nspname = 'public' and {GATED}\n"
            "                                 and p.prosrc ~* '(insert\\s+into|delete\\s+from|update)\\s+public\\.collection_layout_slot_assignment\\y')")


def inv_expo():
    return (f"(select coalesce(string_agg({GSIG}, ', ' order by {GSIG} collate \"C\"), '')\n"
            "                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace\n"
            f"                               where n.nspname = 'public' and {GATED} and p.proname ~ '^(editor_|get_shared_|get_editor_)'\n"
            "                                 and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')\n"
            "                                 and (exists (select 1 from unnest(coalesce(p.proargnames, array[]::text[])) a(nm) where a.nm like '%physical_card_id%')\n"
            "                                      or p.prosrc like '%''physical_card_id''%'))")


def md5_line(sig, h, op="is distinct from"):
    return f"(select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.{sig}')) {op} '{h}'"


CLIENTS = "('anon', 'authenticated', 'service_role', 'authenticator')"


def no_client_exec(sig):
    return (f"not exists (select 1 from pg_catalog.pg_roles x where x.rolname in {CLIENTS}\n"
            f"                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.{sig}'), 'EXECUTE'))")


HEAD = """/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5397 - Identidade opaca no fichário compartilhado do EDITOR (V1-13 · E3-7b, P0)
Versão......: 1.0 (2026-11-27, `E3-7b — BINDER OPAQUE IDENTITY / P0 PRIVACY CORRECTION-01`)
Status......: PROPOSTA — NÃO EXECUTADA. GERADA por build_5397.py a partir do texto canônico
              implantado (versões protegidas G1). Execução só com PRE aprovado, expectativas de
              inventário, auditoria independente e autorização expressa, pelo executor por arquivo.
Autor.......: Fabrício Sales / Claude
Problema....: 5373 devolvia physical_card_id ao EDITOR; 5386 devolvia physical_card_id no JSON da prévia;
              5374 aceitava physical_card_id para colocar (e desfazer). Identificador global e estável
              do exemplar do titular — sem autoridade, mas vazamento de identidade patrimonial.
Corrige.....: - CRIA get_shared_binder_placeable_copies(uuid, integer, integer): mesma leitura da 5373,
                copy_token no lugar de physical_card_id;
              - CRIA editor_place_copy_in_binder(uuid, integer, integer, integer, text): mesmo
                comportamento da 5374 (colocar/substituir/UNCHANGED, travas, elegibilidade, evento),
                com o exemplar por token; token inválido/obsoleto → PHYSICAL_CARD_NOT_ELIGIBLE (P0002);
              - CREATE OR REPLACE editor_preview_binder_auto_arrange(uuid): itens sem 'physical_card_id'
                (card_id e card_variant_id ficam: catálogo público); plano e token do plano inalterados;
              - REVOGA de PUBLIC/anon/authenticated/service_role as antigas 5373 e 5374 (permanecem
                no banco para o STOP de emergência G1 e para a reversão).
Token.......: o MESMO da 5391 ('pc1.' + HMAC-SHA256(alocação|participação|época)), resolvido pelo
              MESMO ajudante interno da 5392 — limitado à coleção e à participação EDITOR ACTIVE,
              invalidado por mudança de participação ou época. Não concede permissão nova.
Reversão....: ROLLBACK_5397.sql (remove as novas e restaura a prévia; as antigas ficam REVOGADAS —
              estado seguro). Reabrir as antigas é exceção separada: RESTORE_5373_5374_EXCECAO_5397.sql.
================================================================
*/
"""


def build():
    pre = ["  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'\n     or (select count(*) from public.v1_13_barrier_identity) <> 0 then\n    raise exception 'PRECHECK 5397: barreira não está CLOSED';\n  end if;",
           "  if " + "\n     or ".join([md5_line(OLDSIG[k], OLD[k][2]) for k in OLD] + [md5_line(sig, h) for sig, (_, _, h) in DEPS.items()]) + " then\n    raise exception 'PRECHECK 5397: ESTADO DIVERGENTE — 5373/5374/5386 ou ajudantes 5389/5391/5392 diferem do canônico';\n  end if;",
           "  if to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is not null\n     or to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is not null then\n    raise exception 'PRECHECK 5397: JÁ APLICADA ou ESTADO DIVERGENTE';\n  end if;"]
    newfns = ["get_shared_binder_placeable_cards", "editor_place_card_in_binder"]
    post = ["  if " + "\n     or ".join(md5_line(NEWSIG[k], NEWMD5[k]) for k in NEW) + " then\n    raise exception 'POSTCHECK 5397: funções fora do texto gerado';\n  end if;",
            "  foreach f in array array[" + ", ".join(f"to_regprocedure('public.{NEWSIG[k]}')" for k in newfns) + "] loop\n    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true\n       or not (array['search_path=\"\"'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))\n       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true\n       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false\n       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false\n       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then\n      raise exception 'POSTCHECK 5397: RPC nova fora do estado esperado (%)', f::regprocedure;\n    end if;\n  end loop;",
            "  if not (" + no_client_exec(OLDSIG["get_shared_binder_placeable_cards"]) + ")\n     or not (" + no_client_exec(OLDSIG["editor_place_card_in_binder"]) + ") then\n    raise exception 'POSTCHECK 5397: contrato antigo (physical_card_id) ainda executável por cliente';\n  end if;",
            "  if pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'), 'EXECUTE') is not true then\n    raise exception 'POSTCHECK 5397: prévia perdeu o EXECUTE';\n  end if;",
            "  if " + inv_expo() + " <> '' then\n    raise exception 'POSTCHECK 5397: ainda há RPC do EDITOR com physical_card_id';\n  end if;",
            "  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'\n     or (select count(*) from public.v1_13_barrier_identity) <> 0 then\n    raise exception 'POSTCHECK 5397: barreira não está CLOSED';\n  end if;"]
    grants = ""
    for k in newfns:
        sig = NEWSIG[k]
        grants += f"revoke all on function public.{sig} from public, anon, service_role;\ngrant execute on function public.{sig} to authenticated;\n"
    for k in newfns:
        grants += f"revoke execute on function public.{OLDSIG[k]} from public, anon, authenticated, service_role;\n"
    comments = ("comment on function public.get_shared_binder_placeable_copies(uuid, integer, integer) is\n  'V1-13 E3-7b (5397): cartas que o EDITOR pode colocar (mesma regra da 5373), identificadas por token opaco da participação e época (5391); nunca o id do exemplar.';\n"
                "comment on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) is\n  'V1-13 E3-7b (5397): EDITOR coloca (ou desfaz a retirada de) um exemplar de X pelo token opaco (5391/5392); mesmo comportamento da 5374.';\n")
    mig = (HEAD + "\nbegin;\nset local lock_timeout = '3s';\n\ndo $pre$\nbegin\n" + "\n".join(pre) + "\nend;\n$pre$;\n\n"
           + "\n\n".join(NEW[k] for k in ["get_shared_binder_placeable_cards", "editor_place_card_in_binder", "editor_preview_binder_auto_arrange"]) + "\n\n"
           + comments + "\n" + grants + "\n"
           + "do $post$\ndeclare\n  f oid;\nbegin\n" + "\n".join(post) + "\nend;\n$post$;\n\ncommit;\n")
    rb = ("""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5397 - Reversão SEGURA da 5397 (GERADA por build_5397.py)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5397 confirmada.
Efeito......: remove get_shared_binder_placeable_copies e editor_place_copy_in_binder; restaura o
              texto canônico da prévia 5386. As antigas 5373/5374 CONTINUAM REVOGADAS: o EDITOR fica
              sem colocar carta (estado seguro, sem reabrir o P0). Reabri-las é exceção separada
              (RESTORE_5373_5374_EXCECAO_5397.sql), nunca parte da reversão.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if """ + "\n     or ".join(md5_line(NEWSIG[k], NEWMD5[k]) for k in NEW) + """ then
    raise exception 'PRECHECK R5397: 5397 ausente ou divergente — nada a reverter (diagnosticar)';
  end if;
end;
$pre$;

drop function public.get_shared_binder_placeable_copies(uuid, integer, integer);
drop function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text);

""" + CANON["editor_preview_binder_auto_arrange"].replace("create function public.", "create or replace function public.", 1) + """

do $post$
begin
  if """ + md5_line(OLDSIG["editor_preview_binder_auto_arrange"], OLD["editor_preview_binder_auto_arrange"][2]) + """
     or to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is not null then
    raise exception 'POSTCHECK R5397: reversão incompleta';
  end if;
  if not (""" + no_client_exec(OLDSIG["get_shared_binder_placeable_cards"]) + """)
     or not (""" + no_client_exec(OLDSIG["editor_place_card_in_binder"]) + """) then
    raise exception 'POSTCHECK R5397: a reversão não pode reabrir o contrato com physical_card_id';
  end if;
end;
$post$;

commit;
""")
    restore = ("""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: RESTORE-5373/5374 — EXCEÇÃO à 5397 (reabre o contrato com physical_card_id)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Uso EXCEPCIONAL, com decisão e autorização próprias: REABRE o P0.
Exige.......: 5397 ausente (revertida) e barreira CLOSED. Só os 2 GRANTs da 5373/5374 originais.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is not null
     or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED' then
    raise exception 'PRECHECK RESTORE: exige 5397 revertida e barreira CLOSED';
  end if;
end;
$pre$;

grant execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) to authenticated;
grant execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) to authenticated;

commit;
""")
    em = ("""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: EMERGENCY_STOP_V1_13 — complemento E2d (E3-7b: 5397)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com autorização.
              Mesmo formato do g1/EMERGENCY_STOP_V1_13.sql (não alterado; a prévia 5386 já está nele).
              Revoga as 2 RPCs novas da 5397 de PUBLIC/anon/authenticated. Não concede nada.
================================================================
*/

-- E2d ------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
revoke execute on function public.get_shared_binder_placeable_copies(uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) from public, anon, authenticated;
commit;
""")
    NL = ",\n"
    old_ok = NL.join("                                    (" + md5_line(OLDSIG[k], OLD[k][2], "=") + ")" for k in OLD)
    dep_ok = NL.join("                                    (" + md5_line(sig, hh, "=") + ")" for sig, (_, _, hh) in DEPS.items())
    new_ok = NL.join("                                    (" + md5_line(NEWSIG[k], NEWMD5[k], "=") + ")" for k in NEW)
    writers_post = ", ".join(WRITERS_POST)
    pre_gate = f"""/*
V1-13 · E3-7b — 5397: PRE SOMENTE LEITURA (um SELECT). PASS = todos os booleanos de primeiro nível true;
"escritores_bolso" (funções da V1-13 que gravam bolsos) e "escritores_exposicao_fisica" (RPCs do EDITOR com
physical_card_id em argumento, coluna ou chave JSON, executáveis por authenticated) comparados pelo
executor v1.4 com E37B_5397_EXPECTATIVAS.json, por assinatura completa. Modo gate.
*/

select jsonb_build_object(
  'executor',                    current_user,
  'barreira',                    (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',           (select count(*) from public.v1_13_barrier_identity),
  'funcoes_canonicas',           (select bool_and(x.ok) from (values
{old_ok}) x(ok)),
  'ajudantes_canonicos',         (select bool_and(x.ok) from (values
{dep_ok}) x(ok)),
  'contratos_antigos_ativos',    pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.{OLDSIG["get_shared_binder_placeable_cards"]}'), 'EXECUTE')
                                 and pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.{OLDSIG["editor_place_card_in_binder"]}'), 'EXECUTE'),
  'ausente_5397',                to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is null
                                 and to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is null,
  'pode_criar_em_public',        pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE'),
  'escritores_bolso',            {inv_writers()},
  'escritores_exposicao_fisica', {inv_expo()},
  'privilegios_observaveis',     (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as e37b_5397_pre;
"""
    post_gate = f"""/*
V1-13 · E3-7b — 5397: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos true, barreira CLOSED e
0 identidades. Exposição física das RPCs do EDITOR = vazia; escritores de bolso = anteriores + a nova. Modo gate.
*/

select jsonb_build_object(
  'funcoes_5397',                (select bool_and(x.ok) from (values
{new_ok}) x(ok)),
  'ajudantes_canonicos',         (select bool_and(x.ok) from (values
{dep_ok}) x(ok)),
  'rpcs_novas',                  (select count(*) = 2 and bool_and(p.prosecdef and array['search_path=""'::text] <@ coalesce(p.proconfig, array[]::text[])
                                          and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                          and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                                          and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'))
                                  from pg_catalog.pg_proc p
                                  where p.oid in (to_regprocedure('public.{NEWSIG["get_shared_binder_placeable_cards"]}'), to_regprocedure('public.{NEWSIG["editor_place_card_in_binder"]}'))),
  'contratos_antigos_revogados', {no_client_exec(OLDSIG["get_shared_binder_placeable_cards"])}
                                 and {no_client_exec(OLDSIG["editor_place_card_in_binder"])},
  'previa_executavel',           pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'), 'EXECUTE'),
  'inventario_exposicao_pos',    {inv_expo()} = '',
  'inventario_bolso_pos',        {inv_writers()}
                                 = '{writers_post}',
  'barreira',                    (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',           (select count(*) from public.v1_13_barrier_identity)
) as e37b_5397_post;
"""
    w = lambda f, c: open(os.path.join(HERE, f), "w", encoding="utf-8", newline="\n").write(c)
    w("5397_binder_opaque_copy_identity.sql", mig)
    w("ROLLBACK_5397.sql", rb)
    w("RESTORE_5373_5374_EXCECAO_5397.sql", restore)
    w("EMERGENCY_STOP_V1_13_ADD_E37B.sql", em)
    w("E37B_5397_PRE_readonly.sql", pre_gate)
    w("E37B_5397_POST_readonly.sql", post_gate)
    w("E37B_5397_EXPECTATIVAS.json", json.dumps({"escritores_bolso": WRITERS_PRE, "escritores_exposicao_fisica": EXPO_PRE}, indent=2) + "\n")
    h = lambda f: hashlib.sha256(open(os.path.join(HERE, f), "rb").read()).hexdigest()
    w("E37B_5397_MANIFEST.txt", "# V1-13 · E3-7b / 5397 — manifesto do executor por arquivo (STD-005 §3, v1.4). passo|arquivo|sha256|modo\n"
      f"1|{PKG}E37B_5397_PRE_readonly.sql|{h('E37B_5397_PRE_readonly.sql')}|gate\n"
      f"2|{PKG}5397_binder_opaque_copy_identity.sql|{h('5397_binder_opaque_copy_identity.sql')}|write\n"
      f"3|{PKG}E37B_5397_POST_readonly.sql|{h('E37B_5397_POST_readonly.sql')}|gate\n")
    return mig, rb


if __name__ == "__main__":
    for k in OLD:
        print(f"{k:40} canônico {OLD[k][2]}  novo {NEWSIG[k]} {NEWMD5[k]}")
    build()
    for f in sorted(os.listdir(HERE)):
        if f.endswith((".sql", ".json", ".txt")):
            print(hashlib.sha256(open(os.path.join(HERE, f), "rb").read()).hexdigest(), f)
