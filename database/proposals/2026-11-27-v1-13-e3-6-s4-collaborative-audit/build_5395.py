#!/usr/bin/env python3
"""
V1-13 · E3-6 / S4-b — gera 5395 (e o rollback) a partir do texto CANÔNICO implantado das 4 funções
do titular da Pokédex (6123, 6124, 6126, 6125), com inserções em pontos fixos:

  - DECLARE: variáveis de auditoria;
  - antes da 1ª escrita: v_audit := v1_13_capability_open(); se verdadeiro, estado anterior + open();
  - depois da escrita efetiva: se verdadeiro, record_pokedex() (um evento por operação efetiva).

Com a barreira CLOSED (capability falsa) as funções executam exatamente o caminho de hoje.
Cada inserção vem entre marcadores "-- [5395+]" / "-- [5395-]" para a verificação estática provar
que, removidos os blocos marcados, o corpo é o canônico (md5 do LIVE).

    python3 -I -B database/proposals/2026-11-27-v1-13-e3-6-s4-collaborative-audit/build_5395.py
"""
import hashlib
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
S = os.path.join(ROOT, "database", "schema")
A, Z = "-- [5395+]", "-- [5395-]"


def fn_def(path, name):
    t = open(path, encoding="utf-8").read()
    m = re.search(r"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\." + re.escape(name) + r"\s*\(", t)
    a = re.search(r"\bAS\s+(\$[a-z_]*\$)", t[m.end():])
    s = m.end() + a.end()
    e = t.index(a.group(1), s) + len(a.group(1))
    return t[m.start():e] + ";"


def prosrc(d):
    a = re.search(r"\bAS\s+(\$[a-z_]*\$)", d)
    s = a.end()
    return d[s:d.index(a.group(1), s)]


def ins_after(text, anchor, block):
    assert text.count(anchor) == 1, anchor[:60]
    return text.replace(anchor, anchor + "\n" + A + "\n" + block.rstrip("\n") + "\n" + Z, 1)


def ins_before(text, anchor, block):
    assert text.count(anchor) == 1, anchor[:60]
    return text.replace(anchor, A + "\n" + block.rstrip("\n") + "\n" + Z + "\n" + anchor, 1)


SRC = {
    "set_pokedex_position_assignment": (os.path.join(S, "6123_fix_fatia_d_applied_objects_pause_sql_direct_audit.sql"), "8c572182a03025503e993e5ecc25e07a"),
    "remove_pokedex_position_assignment": (os.path.join(S, "6124_create_remove_pokedex_position_assignment_function.sql"), "26ef2d5da3312661111df0194dfc8ba2"),
    "set_pokedex_position_primary_representative": (os.path.join(S, "6126_fix_primary_representative_on_conflict_ambiguity.sql"), "6353dffe6c3877967997033dcc2bfd4c"),
    "clear_pokedex_position_primary_representative": (os.path.join(S, "6125_create_primary_representative_functions.sql"), "eeede3a5b871fbf07f81eb59ecea932f"),
}
CANON = {n: fn_def(p, n) for n, (p, _) in SRC.items()}
for n, (_, h) in SRC.items():
    assert hashlib.md5(prosrc(CANON[n]).encode()).hexdigest() == h, n

NEW = {}

# 6123 — atribuir / mover
t = CANON["set_pokedex_position_assignment"]
t = ins_after(t, "    v_basis                    TEXT;", """    v_audit                    BOOLEAN := false;
    v_rep_cleared              BOOLEAN := false;""")
t = ins_before(t, """    IF v_existing_position_id IS NOT NULL THEN
        -- MOVE: DELETE + INSERT""", """    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        IF v_existing_position_id IS NOT NULL THEN
            SELECT EXISTS (SELECT 1 FROM public.collection_pokedex_position_primary_representative r
                            WHERE r.collection_allocation_id = v_collection_allocation_id) INTO v_rep_cleared;
        END IF;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;""")
t = ins_after(t, """        collection_pokedex_position_assignment.assignment_basis,
        collection_pokedex_position_assignment.assigned_at;""", """    IF v_audit THEN
        PERFORM public.collection_activity_record_pokedex(v_collection_id,
            CASE WHEN v_existing_position_id IS NULL THEN 'POKEDEX_POSITION_ASSIGNED' ELSE 'POKEDEX_POSITION_MOVED' END,
            v_collection_allocation_id, v_existing_position_id, p_pokedex_position_id, NULL, v_basis,
            CASE WHEN v_existing_position_id IS NULL THEN NULL ELSE v_rep_cleared END);
    END IF;""")
NEW["set_pokedex_position_assignment"] = t

# 6124 — retirar
t = CANON["remove_pokedex_position_assignment"]
t = ins_after(t, "    v_lifecycle_status         TEXT;", """    v_audit                    BOOLEAN := false;
    v_from                     UUID;
    v_rep_cleared              BOOLEAN := false;""")
t = ins_before(t, """    RETURN QUERY
    DELETE FROM public.collection_pokedex_position_assignment""", """    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        SELECT a.pokedex_position_id INTO v_from
          FROM public.collection_pokedex_position_assignment a
         WHERE a.collection_allocation_id = v_collection_allocation_id;
        SELECT EXISTS (SELECT 1 FROM public.collection_pokedex_position_primary_representative r
                        WHERE r.collection_allocation_id = v_collection_allocation_id) INTO v_rep_cleared;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;""")
t = ins_after(t, """        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_FOUND: nenhuma Assignment existente para este physical_card.';
    END IF;""", """    IF v_audit THEN
        PERFORM public.collection_activity_record_pokedex(v_collection_id, 'POKEDEX_POSITION_REMOVED',
            v_collection_allocation_id, v_from, NULL, NULL, NULL, v_rep_cleared);
    END IF;""")
NEW["remove_pokedex_position_assignment"] = t

# 6126 — escolher / substituir representante
t = CANON["set_pokedex_position_primary_representative"]
t = ins_after(t, "    v_lifecycle_status    TEXT;", """    v_audit               BOOLEAN := false;
    v_prev                UUID;""")
t = ins_before(t, """    RETURN QUERY
    INSERT INTO public.collection_pokedex_position_primary_representative""", """    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        SELECT r.collection_allocation_id INTO v_prev
          FROM public.collection_pokedex_position_primary_representative r
         WHERE r.collection_id = v_collection_id AND r.pokedex_position_id = v_pokedex_position_id
         FOR UPDATE;
        -- Sem mudança efetiva: nenhuma escrita, nenhuma marcação, nenhum evento (como o UNCHANGED da 5392).
        -- Evita a marcação residual na transação e o evento derivado do UPDATE do upsert.
        IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN
            RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;
            RETURN;
        END IF;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;""")
t = ins_after(t, """        collection_pokedex_position_primary_representative.pokedex_position_id,
        collection_pokedex_position_primary_representative.collection_allocation_id;""", """    IF v_audit AND v_prev IS DISTINCT FROM p_collection_allocation_id THEN
        PERFORM public.collection_activity_record_pokedex(v_collection_id,
            CASE WHEN v_prev IS NULL THEN 'POKEDEX_REPRESENTATIVE_SET' ELSE 'POKEDEX_REPRESENTATIVE_REPLACED' END,
            p_collection_allocation_id, NULL, v_pokedex_position_id, v_prev, NULL, NULL);
    END IF;""")
NEW["set_pokedex_position_primary_representative"] = t

# 6125 — voltar à representante automática
t = CANON["clear_pokedex_position_primary_representative"]
t = ins_after(t, "    v_lifecycle_status TEXT;", """    v_audit            BOOLEAN := false;
    v_prev             UUID;""")
t = ins_before(t, """    RETURN QUERY
    DELETE FROM public.collection_pokedex_position_primary_representative pr""", """    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        SELECT r.collection_allocation_id INTO v_prev
          FROM public.collection_pokedex_position_primary_representative r
         WHERE r.collection_id = p_collection_id AND r.pokedex_position_id = p_pokedex_position_id
         FOR UPDATE;
        PERFORM public.collection_activity_open(p_collection_id);
    END IF;""")
t = ins_after(t, """        RAISE EXCEPTION 'CLEAR_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_NOT_FOUND: nenhum Primary Representative existente para esta Position.';
    END IF;""", """    IF v_audit THEN
        PERFORM public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_REPRESENTATIVE_RESTORED',
            NULL, NULL, p_pokedex_position_id, v_prev, NULL, NULL);
    END IF;""")
NEW["clear_pokedex_position_primary_representative"] = t

NEWMD5 = {n: hashlib.md5(prosrc(NEW[n]).encode()).hexdigest() for n in NEW}

if __name__ == "__main__":
    for n in NEW:
        print(f"{n:48} canônico {SRC[n][1]}  instrumentado {NEWMD5[n]}")


# ------------------------------------------------------------------ emissão dos arquivos
SIGS = {"set_pokedex_position_assignment": "(uuid, uuid, boolean)", "remove_pokedex_position_assignment": "(uuid)",
        "set_pokedex_position_primary_representative": "(uuid)", "clear_pokedex_position_primary_representative": "(uuid, uuid)"}
DEPS = {  # dependências conferidas por md5 (corpos canônicos implantados)
    "v1_13_assert_capability()": "e4f710904f50e6e8c3f1d8e2337639e0",
    "v1_13_capability_open()": "32e2f636361732b497e8401e50f0bbe0",
    "collection_activity_open(uuid)": "d5f52bf5a2a29f1a4d8279c560b97043",
    "collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)": "c7245940a39d7c2a3d0674deb3be06dd",
    "collection_share_role(uuid)": "efdb495b5b703e9f093eb0f49a1d0a5d",
}


def md5_line(fn_sig, h, op="is distinct from"):
    return f"(select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.{fn_sig}')) {op} '{h}'"


READ = """create function public.get_collection_activity(
  p_collection_id uuid,
  p_before_id     bigint  default null,
  p_limit         integer default 50
)
returns table (
  event_id           bigint,
  occurred_at        timestamptz,
  event_type         text,
  origin             text,
  actor_role         text,
  actor_display_name text,
  summary            jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_role text;
  v_at   timestamptz;
  v_id   bigint;
begin
  perform public.v1_13_assert_capability();  -- barreira: CLOSED → CAPABILITY_NOT_ENABLED (42501)
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if p_collection_id is null then
    return;
  end if;
  -- Titular ou participante ACTIVE (EDITOR lê como VIEWER, 5302); removido, recusado ou pendente → zero linhas.
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;
  if p_before_id is not null then
    select e.occurred_at, e.id into v_at, v_id
    from public.collection_activity_event e
    where e.id = p_before_id and e.collection_id = p_collection_id;
    if v_id is null then
      return;
    end if;
  end if;
  return query
  select e.id, e.occurred_at, e.event_type, e.origin, e.actor_role,
         case when e.actor_user_id is null then null
              else (select up.display_name::text from public.user_profile up where up.id = e.actor_user_id) end,
         e.summary
  from public.collection_activity_event e
  where e.collection_id = p_collection_id
    and (v_id is null or (e.occurred_at, e.id) < (v_at, v_id))
  order by e.occurred_at desc, e.id desc
  limit p_limit;
end;
$fn$;"""

HEAD = """/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5395 - Auditoria explícita das operações do titular na Pokédex e leitura do
              histórico por coleção (V1-13 · E3-6 / S4-b, D-E3-8)
Versão......: 1.1 (2026-11-27, `S4-b/5395 TRANSACTIONAL AUDIT MARKER REVIEW-01`; 1.0: PREPARATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. GERADA por build_5395.py a partir do texto canônico
              implantado. Execução só com PRE aprovado, expectativas de escritores,
              auditoria independente e autorização expressa, pelo executor por arquivo.
Autor.......: Fabrício Sales / Claude
Substitui...: CREATE OR REPLACE das 4 funções do titular (6123 set_pokedex_position_assignment,
              6124 remove_pokedex_position_assignment, 6126 set_pokedex_position_primary_
              representative, 6125 clear_pokedex_position_primary_representative): mesmo
              corpo, mesma assinatura, mesmo retorno, mesmos privilégios, MAIS blocos
              marcados [5395+]…[5395-] que, com a capacidade aberta para a sessão
              (v1_13_capability_open), chamam collection_activity_open antes da escrita e
              collection_activity_record_pokedex depois da escrita efetiva. Com a barreira
              CLOSED o caminho é exatamente o de hoje (nenhum evento).
Cria........: get_collection_activity(uuid, bigint, integer) — histórico da coleção para o
              titular e participantes ACTIVE (C-241), sem identificadores patrimoniais.
Fora........: referências de espécie no histórico do fichário (5258/5383) → 5396 (fluxo do
              fichário, outro conjunto de funções; decisão registrada no README §10).
Reversão....: ROLLBACK_5395.sql (restaura o texto canônico das 4 funções e remove a leitura;
              não apaga eventos).
================================================================
*/
"""


def build():
    pre = ["  if " + "\n     or ".join(md5_line(s, h) for s, h in DEPS.items()) + " then\n    raise exception 'PRECHECK 5395: barreira, primitivas da 5394 ou collection_share_role divergentes';\n  end if;",
           "  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'\n     or (select count(*) from public.v1_13_barrier_identity) <> 0 then\n    raise exception 'PRECHECK 5395: barreira não está CLOSED';\n  end if;",
           "  if " + "\n     or ".join(md5_line(n + SIGS[n], SRC[n][1]) for n in SIGS) + " then\n    raise exception 'PRECHECK 5395: ESTADO DIVERGENTE — funções do titular diferem do canônico (6123/6124/6126/6125)';\n  end if;",
           "  if to_regprocedure('public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean)') is null\n     or to_regclass('public.collection_activity_event') is null\n     or to_regclass('public.user_profile') is null then\n    raise exception 'PRECHECK 5395: dependência ausente (5392, 5394 ou user_profile)';\n  end if;",
           "  if to_regprocedure('public.get_collection_activity(uuid, bigint, integer)') is not null then\n    raise exception 'PRECHECK 5395: JÁ APLICADA ou ESTADO DIVERGENTE';\n  end if;"]
    post = ["  if " + "\n     or ".join(md5_line(n + SIGS[n], NEWMD5[n]) for n in SIGS) + " then\n    raise exception 'POSTCHECK 5395: funções do titular fora do texto instrumentado';\n  end if;",
            "  foreach f in array array[" + ",\n                           ".join(f"to_regprocedure('public.{n}{SIGS[n]}')" for n in SIGS) + "] loop\n    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true\n       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=\"\"']\n       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true\n       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false\n       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a\n                  where p.oid = f and a.grantee = 0) then\n      raise exception 'POSTCHECK 5395: privilégios ou segurança de função do titular alterados (%)', f::regprocedure;\n    end if;\n  end loop;",
            "  f := to_regprocedure('public.get_collection_activity(uuid, bigint, integer)');\n  if f is null\n     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true\n     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=\"\"']\n     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'\n     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true\n     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false\n     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then\n    raise exception 'POSTCHECK 5395: leitura do histórico fora do estado esperado';\n  end if;",
            "  if exists (select 1 from public.collection_activity_event) then\n    raise exception 'POSTCHECK 5395: a migration não deveria gerar eventos';\n  end if;",
            "  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'\n     or (select count(*) from public.v1_13_barrier_identity) <> 0 then\n    raise exception 'POSTCHECK 5395: barreira não está CLOSED';\n  end if;"]
    mig = (HEAD + "\nbegin;\nset local lock_timeout = '3s';\n\ndo $pre$\nbegin\n" + "\n".join(pre) + "\nend;\n$pre$;\n\n"
           + "\n\n".join(NEW[n] for n in SIGS) + "\n\n" + READ + "\n\n"
           + "comment on function public.get_collection_activity(uuid, bigint, integer) is\n  'V1-13 E3-6/S4-b (5395): histórico da coleção (Pokédex) para o titular e participantes ACTIVE (C-241); nome público do autor resolvido na leitura; sem exemplar, alocação, local, condição ou valores. Sem acesso → zero linhas.';\n"
           + "revoke all on function public.get_collection_activity(uuid, bigint, integer) from public, anon, service_role;\n"
           + "grant execute on function public.get_collection_activity(uuid, bigint, integer) to authenticated;\n\n"
           + "do $post$\ndeclare\n  f oid;\nbegin\n" + "\n".join(post) + "\nend;\n$post$;\n\ncommit;\n")
    rb = ("""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5395 - Reversão da 5395 (GERADA por build_5395.py)
Versão......: 1.1 (2026-11-27; precheck com o md5 da 5395 v1.1)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5395
              confirmada. Restaura o texto canônico (6123/6124/6126/6125) das 4 funções do
              titular e remove get_collection_activity. Não apaga eventos já gravados. A
              captura derivada da 5394 volta a cobrir as operações do titular (agregada).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if """ + "\n     or ".join(md5_line(n + SIGS[n], NEWMD5[n]) for n in SIGS) + """ then
    raise exception 'PRECHECK R5395: funções do titular não estão no texto da 5395 — diagnosticar';
  end if;
end;
$pre$;

""" + "\n\n".join(CANON[n] for n in SIGS) + """

drop function public.get_collection_activity(uuid, bigint, integer);

do $post$
begin
  if """ + "\n     or ".join(md5_line(n + SIGS[n], SRC[n][1]) for n in SIGS) + """ then
    raise exception 'POSTCHECK R5395: funções do titular não voltaram ao canônico';
  end if;
  if to_regprocedure('public.get_collection_activity(uuid, bigint, integer)') is not null then
    raise exception 'POSTCHECK R5395: leitura ainda presente';
  end if;
end;
$post$;

commit;
""")
    open(os.path.join(HERE, "5395_instrument_owner_pokedex_audit_and_activity_read.sql"), "w", encoding="utf-8").write(mig)
    open(os.path.join(HERE, "ROLLBACK_5395.sql"), "w", encoding="utf-8").write(rb)
    return mig, rb


if __name__ == "__main__":
    m, r = build()
    print("5395:", hashlib.sha256(m.encode()).hexdigest(), "| rollback:", hashlib.sha256(r.encode()).hexdigest())
