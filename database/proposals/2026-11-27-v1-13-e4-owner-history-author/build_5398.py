#!/usr/bin/env python3
"""V1-13 · D-E3-2 — 5398: autoria no histórico do fichário do TITULAR (leitura nova, aditiva).

Gera a migration, PRE/POST somente leitura, reversão e manifesto do executor v1.4.
A função nova NÃO altera a 5269 (`get_my_binder_activity`): devolve só o autor dos eventos que o titular
já vê, pelos ids da página. Atrás da barreira 5389 (capability_open): fechada → nenhuma linha (tela de sempre).
"""
import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = "database\\proposals\\2026-11-27-v1-13-e4-owner-history-author"
MD5_ASSERT = "e4f710904f50e6e8c3f1d8e2337639e0"
MD5_OPEN = "32e2f636361732b497e8401e50f0bbe0"
SIG = "public.get_my_binder_activity_actors(uuid, bigint[])"

BODY = """
declare
  v_uid uuid := (select auth.uid());
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1): fechada → nenhuma linha
  if v_uid is null or p_layout_key is null or p_event_ids is null then
    return;
  end if;
  if cardinality(p_event_ids) > 50 then
    raise exception 'too many events' using errcode = '22023', hint = 'BINDER_ACTIVITY_ACTORS_LIMIT';
  end if;

  -- Só eventos do PRÓPRIO titular (owner_user_id = sessão) e deste fichário; ids alheios somem em silêncio.
  return query
  select e.id,
         case when e.actor_user_id is null then null
              when e.actor_user_id = v_uid then 'OWNER'
              else 'PARTICIPANT' end,
         case when e.actor_user_id is null then null
              else (select up.display_name::text from public.user_profile up where up.id = e.actor_user_id) end
  from public.binder_activity_event e
  where e.owner_user_id = v_uid
    and e.layout_key = p_layout_key
    and e.id = any (p_event_ids)
  order by e.id desc
  limit 50;
end;
"""
MD5_BODY = hashlib.md5(BODY.encode()).hexdigest()

GATES_DOOR = (
    f"(select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = '{MD5_ASSERT}'\n"
    f"                                and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '{MD5_OPEN}'"
)

MIGRATION = f"""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5398 - Autoria no histórico do fichário do titular (V1-13 · D-E3-2)
Versão......: 1.0 (2026-11-27, `E4 — rodada de correção`)
Status......: PROPOSTA — NÃO EXECUTADA. Execução só pelo executor por arquivo (manifesto do pacote), com PRE
              aprovado e autorização expressa.
Problema....: D-E3-2 — o titular não via quem fez cada ação no histórico do fichário: a 5269
              (`get_my_binder_activity`) não devolve o autor; os participantes já veem pela 5388.
Corrige.....: CRIA {SIG} → (event_id, actor_role, actor_display_name):
              autor ('OWNER' | 'PARTICIPANT' | null) e nome público (C-241) dos eventos do PRÓPRIO titular
              neste fichário, pelos ids da página (até 50). Aditiva: a 5269 não muda.
Barreira....: atrás de v1_13_capability_open() (5389): fechada → nenhuma linha (a tela segue sem autor).
Reversão....: ROLLBACK_5398.sql (DROP da função nova).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5398: barreira não está CLOSED com registro vazio';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from '{MD5_ASSERT}'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '{MD5_OPEN}' then
    raise exception 'PRECHECK 5398: funções da porta diferem do canônico';
  end if;
  if to_regprocedure('{SIG}') is not null then
    raise exception 'PRECHECK 5398: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.get_my_binder_activity_actors(
  p_layout_key uuid,
  p_event_ids  bigint[]
)
returns table (
  event_id           bigint,
  actor_role         text,
  actor_display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn${BODY}$fn$;

comment on function {SIG} is
  'V1-13 D-E3-2 (5398): autor dos eventos do histórico do fichário do PRÓPRIO titular (ids da página, até 50); nome público (C-241). Atrás da barreira 5389.';

revoke all on function {SIG} from public, anon, service_role;
grant execute on function {SIG} to authenticated;

do $post$
declare
  f oid := to_regprocedure('{SIG}');
begin
  if f is null
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from '{MD5_BODY}'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
     or not (array['search_path=""'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then
    raise exception 'POSTCHECK 5398: função nova fora do estado esperado';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5398: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
"""

PRE = f"""/*
V1-13 · D-E3-2 — 5398: PRE SOMENTE LEITURA (um SELECT, modo gate). PASS = booleanos true, barreira CLOSED, 0 identidades.
*/

select jsonb_build_object(
  'executor',                   current_user,
  'barreira',                   (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',          (select count(*) from public.v1_13_barrier_identity),
  'funcoes_barreira_canonicas', {GATES_DOOR},
  'ausente_5398',               to_regprocedure('{SIG}') is null,
  'leitura_5269_presente',      to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)') is not null,
  'pode_criar_em_public',       pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE')
) as d_e3_2_5398_pre;
"""

POST = f"""/*
V1-13 · D-E3-2 — 5398: POST SOMENTE LEITURA (um SELECT, modo gate). PASS = booleanos true, barreira CLOSED, 0 identidades.
*/

select jsonb_build_object(
  'executor',                   current_user,
  'barreira',                   (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',          (select count(*) from public.v1_13_barrier_identity),
  'funcoes_barreira_canonicas', {GATES_DOOR},
  'funcao_5398',                (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('{SIG}')) = '{MD5_BODY}',
  'definer_estavel_search_path', (select p.prosecdef and p.provolatile = 's' and array['search_path=""'::text] <@ coalesce(p.proconfig, array[]::text[])
                                 from pg_catalog.pg_proc p where p.oid = to_regprocedure('{SIG}')),
  'so_authenticated',           pg_catalog.has_function_privilege('authenticated', to_regprocedure('{SIG}'), 'EXECUTE')
                                and not pg_catalog.has_function_privilege('anon', to_regprocedure('{SIG}'), 'EXECUTE')
                                and not pg_catalog.has_function_privilege('service_role', to_regprocedure('{SIG}'), 'EXECUTE')
) as d_e3_2_5398_post;
"""

ROLLBACK = f"""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5398 - Reversão da 5398 (remove a leitura de autoria do titular)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e com a 5398 confirmada.
Efeito......: a tela volta a não mostrar o autor no histórico do fichário do titular (estado anterior).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('{SIG}')) is distinct from '{MD5_BODY}' then
    raise exception 'PRECHECK R5398: 5398 ausente ou divergente';
  end if;
end;
$pre$;

drop function {SIG};

do $post$
begin
  if to_regprocedure('{SIG}') is not null then
    raise exception 'POSTCHECK R5398: função ainda existe';
  end if;
end;
$post$;

commit;
"""


def write(name, text):
    data = text.encode("utf-8")
    (HERE / name).write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def main():
    h = {n: write(n, t) for n, t in {
        "5398_owner_binder_history_author.sql": MIGRATION,
        "D_E3_2_5398_PRE_readonly.sql": PRE,
        "D_E3_2_5398_POST_readonly.sql": POST,
        "ROLLBACK_5398.sql": ROLLBACK,
    }.items()}
    head = "# V1-13 · D-E3-2 / 5398 — manifesto do executor por arquivo (STD-005 §3, v1.4). passo|arquivo|sha256|modo\n"
    m = head + "".join(f"{i}|{PKG}\\{n}|{h[n]}|{mode}\n" for i, (n, mode) in enumerate(
        [("D_E3_2_5398_PRE_readonly.sql", "gate"), ("5398_owner_binder_history_author.sql", "write"), ("D_E3_2_5398_POST_readonly.sql", "gate")], 1))
    h["D_E3_2_5398_MANIFEST.txt"] = write("D_E3_2_5398_MANIFEST.txt", m)
    for n, v in h.items():
        print(f"{v}  {n}")
    print(f"md5 corpo 5398: {MD5_BODY}")


if __name__ == "__main__":
    main()
