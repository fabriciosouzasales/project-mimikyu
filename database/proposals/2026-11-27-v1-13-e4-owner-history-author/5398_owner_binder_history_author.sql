/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5398 - Autoria no histórico do fichário do titular (V1-13 · D-E3-2)
Versão......: 1.0 (2026-11-27, `E4 — rodada de correção`)
Status......: PROPOSTA — NÃO EXECUTADA. Execução só pelo executor por arquivo (manifesto do pacote), com PRE
              aprovado e autorização expressa.
Problema....: D-E3-2 — o titular não via quem fez cada ação no histórico do fichário: a 5269
              (`get_my_binder_activity`) não devolve o autor; os participantes já veem pela 5388.
Corrige.....: CRIA public.get_my_binder_activity_actors(uuid, bigint[]) → (event_id, actor_role, actor_display_name):
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
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0' then
    raise exception 'PRECHECK 5398: funções da porta diferem do canônico';
  end if;
  if to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])') is not null then
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
as $fn$
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
$fn$;

comment on function public.get_my_binder_activity_actors(uuid, bigint[]) is
  'V1-13 D-E3-2 (5398): autor dos eventos do histórico do fichário do PRÓPRIO titular (ids da página, até 50); nome público (C-241). Atrás da barreira 5389.';

revoke all on function public.get_my_binder_activity_actors(uuid, bigint[]) from public, anon, service_role;
grant execute on function public.get_my_binder_activity_actors(uuid, bigint[]) to authenticated;

do $post$
declare
  f oid := to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])');
begin
  if f is null
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from 'f395a0f109b760a863e8e00832c177b6'
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
