/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5253 - Desassociar convidada preserva as posições (D2)
              collection_binder_detach_snapshot(uuid)            — CREATE OR REPLACE
              detach_my_collection_from_binder(uuid, text, bool) — CREATE OR REPLACE
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-ELIGIBILITY-DECISIONS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depois da 5248 (README §6).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

D2 (Fabrício): remover a associação da coleção NÃO tira as cartas do
fichário; preservam-se as posições dos exemplares que continuam guardados no
mesmo local físico. Pela 5248 toda posição é de exemplar guardado no local do
fichário (e a 5249 tira a posição quando o exemplar sai), então nenhuma
posição sai na desassociação.
O que muda (o resto do corpo é o canônico 5229, conferido pelo static_check S6):
  - snapshot: assignments_count passa a ser sempre 0 e o token deixa de
    incluir posições; bolsos fixados contados só pelas reservas da convidada;
  - desassociação: não apaga posições (assignments_removed = 0); solta só os
    bolsos fixados que têm RESERVA da convidada (as reservas dela saem, como
    hoje — são o planejamento daquela coleção).
Assinaturas, retornos, travas (proprietária → layout → convidada) e ACL
inalterados. Tokens emitidos antes da aplicação → DETACH_PLAN_CHANGED.
Dependências: 5229, 5248.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.collection_binder_detach_snapshot(uuid)') is null
     or to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)') is null then
    raise exception 'PRECHECK 5253: funções da 5229 ausentes';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                   and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5253: aplique a 5248 antes';
  end if;
end;
$pre$;

create or replace function public.collection_binder_detach_snapshot(p_collection_id uuid)
returns table (
  layout_id           uuid,
  owner_collection_id uuid,
  assignments_count   integer,
  reservations_count  integer,
  locked_count        integer,
  detach_token        text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with g as (
    select x.layout_id from public.collection_layout_guest x where x.collection_id = p_collection_id
  ),
  sl as (
    select s.id, s.locked
    from g
    join public.collection_layout_page p on p.layout_id = g.layout_id
    join public.collection_layout_slot s on s.page_id = p.id
  ),
  -- 5253 (D2): posições NÃO saem na desassociação — os exemplares seguem
  -- guardados no mesmo fichário físico. Só reservas da convidada saem.
  asg as (
    select null::uuid as slot_id, null::uuid as collection_allocation_id
    where false
  ),
  exc as (
    select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id
    from public.collection_layout_slot_expected_content e
    join sl on sl.id = e.slot_id
    where e.collection_id = p_collection_id
  ),
  lk as (
    select sl.id from sl
    where sl.locked and sl.id in (select exc.slot_id from exc)
  ),
  ser as (
    select
      'G|' || p_collection_id || '|' || coalesce((select g.layout_id::text from g), '-')
      || E'\nA|' || coalesce((select string_agg(asg.slot_id || ':' || asg.collection_allocation_id, ',' order by asg.slot_id) from asg), '')
      || E'\nE|' || coalesce((select string_agg(exc.slot_id || ':' || exc.card_id || ':' || coalesce(exc.card_variant_id::text, '-') || ':' || coalesce(exc.expected_variant_type_id::text, '-'), ',' order by exc.slot_id) from exc), '')
      || E'\nK|' || coalesce((select string_agg(lk.id::text, ',' order by lk.id) from lk), '')
      as s
  )
  select g.layout_id,
         (select l.collection_id from public.collection_layout l where l.id = g.layout_id),
         (select count(*) from asg)::integer,
         (select count(*) from exc)::integer,
         (select count(*) from lk)::integer,
         'g1:' || encode(sha256(convert_to(ser.s, 'UTF8')), 'hex')
  from g cross join ser;
$$;

create or replace function public.detach_my_collection_from_binder(
  p_collection_id uuid,
  p_detach_token  text,
  p_release_locks boolean default false
)
returns table (
  outcome              text,     -- DETACHED | ALREADY_DETACHED
  assignments_removed  integer,
  reservations_removed integer,
  locks_released       integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_owner  uuid;
  r        record;
  v_unlock integer := 0;
  v_asg    integer;
  v_exc    integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_detach_token is null or p_detach_token !~ '^g1:[0-9a-f]{64}$' then
    raise exception 'INVALID_DETACH_TOKEN' using errcode = '22023';
  end if;

  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select g.layout_id, l.collection_id into v_layout, v_owner
  from public.collection_layout_guest g
  join public.collection_layout l on l.id = g.layout_id
  where g.collection_id = p_collection_id;
  if v_layout is null then
    outcome := 'ALREADY_DETACHED'; assignments_removed := 0; reservations_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  -- Ordem canônica: proprietária → layout → convidada. Qualquer lifecycle
  -- (desfazer participação é permitido mesmo arquivada, como a 5226).
  perform 1 from public.collection c where c.id = v_owner and c.owner_user_id = v_uid for update;
  perform 1 from public.collection_layout l where l.id = v_layout for update;
  perform 1 from public.collection c where c.id = p_collection_id for update;

  if not exists (select 1 from public.collection_layout_guest g
                 where g.collection_id = p_collection_id and g.layout_id = v_layout) then
    outcome := 'ALREADY_DETACHED'; assignments_removed := 0; reservations_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  select * into r from public.collection_binder_detach_snapshot(p_collection_id);
  if r.detach_token is distinct from p_detach_token then
    raise exception 'DETACH_PLAN_CHANGED';
  end if;

  if r.locked_count > 0 and not coalesce(p_release_locks, false) then
    raise exception 'LOCKED_SLOTS_REQUIRE_CONFIRMATION'
      using hint = 'confirme soltar os bolsos fixados com cartas ou reservas desta coleção';
  end if;

  -- D6: solta só os bolsos fixados afetados.
  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout)
     and exists (select 1 from public.collection_layout_slot_expected_content e
                 where e.slot_id = s.id and e.collection_id = p_collection_id);
  get diagnostics v_unlock = row_count;

  -- 5253 (D2): posições permanecem (exemplares continuam no fichário físico);
  -- só as reservas da convidada saem.
  v_asg := 0;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.collection_id = p_collection_id
     and s.id = e.slot_id and p.id = s.page_id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  delete from public.collection_layout_guest g where g.collection_id = p_collection_id;

  if v_asg <> r.assignments_count or v_exc <> r.reservations_count or v_unlock <> r.locked_count then
    raise exception 'BINDER_DETACH_INCONSISTENT';
  end if;

  outcome := 'DETACHED'; assignments_removed := v_asg; reservations_removed := v_exc; locks_released := v_unlock;
  return next;
end;
$$;

revoke all on function public.collection_binder_detach_snapshot(uuid) from public, anon, authenticated, service_role;
revoke all on function public.detach_my_collection_from_binder(uuid, text, boolean) from public;
revoke all on function public.detach_my_collection_from_binder(uuid, text, boolean) from anon;
grant execute on function public.detach_my_collection_from_binder(uuid, text, boolean) to authenticated;

notify pgrst, 'reload schema';

commit;
