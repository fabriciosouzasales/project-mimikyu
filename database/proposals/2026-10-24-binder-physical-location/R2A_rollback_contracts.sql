/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R2A - Rollback de CONTRATOS da fase A (sem tocar no modelo de dados)
              desfaz 5255, 5254, 5253, 5250 e 5249; mantém 5247/5248/5251/5252
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização de Fabrício,
              e só com a 5256 ausente (rode R1 antes, se ela existir).
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-FINAL-CORRECTIONS-01)

Quando usar: algum contrato novo (associação, transferência, desassociação,
posicionar pelo exemplar, mover/organizar com confirmação) se mostrou
defeituoso depois da ativação, MESMO que já existam posições de exemplar
sem coleção ou de coleção não participante. Sempre possível: nenhuma linha
de dado é lida para decidir, alterada ou apagada por este script.

O que fica (modelo de dados preservado): local próprio do fichário (5247),
posição pelo exemplar (5248), plano v2 (5251) e leituras v1.2 (5252) — as
leituras continuam mostrando TODAS as posições, inclusive as que o modelo
antigo não representaria. O frontend volta à versão anterior (que não
chama nada removido aqui; R1 recria a leitura de 3 argumentos se a fase B
tiver sido aplicada).

Efeitos de comportamento (contratos antigos, intencionais):
  - desassociar volta a retirar as posições DAQUELA convidada (5229), só
    quando o colecionador desassocia explicitamente;
  - associação volta a comparar com o local padrão dos participantes;
  - mudar local de carta posicionada volta ao comportamento anterior (sem
    confirmação) — a 5256 já terá sido removida por R1.
Corpos restaurados = canônicos de database/schema/ (static check S7).
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard') then
    raise exception 'R2A: a 5256 está aplicada — rode R1 antes';
  end if;
  if to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)') is null then
    raise exception 'R2A: fase A não aplicada (ou R2A já executado)';
  end if;
end;
$pre$;

-- 5255 → canônicas 5229/5230 ------------------------------------------------------
create or replace function public.attach_my_collection_to_binder(
  p_collection_id uuid,
  p_layout_id     uuid
)
returns table (
  outcome             text,    -- ATTACHED | ALREADY_ATTACHED
  layout_id           uuid,
  owner_collection_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid        uuid := auth.uid();
  v_owner_coll uuid;
  v_status     text;
  v_default    uuid;
  v_kind       text;
  v_current    uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_layout_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Fichário pelo dono (sem trava): inexistente e alheio no mesmo ramo.
  select l.collection_id into v_owner_coll
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = p_layout_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_owner_coll = p_collection_id then
    raise exception 'BINDER_SELF' using errcode = '22023';
  end if;

  -- 2. Proprietária → layout (trava + ACTIVE), ordem canônica (5122).
  begin
    perform public.assert_collection_layout_mutable(p_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      end if;
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'BINDER_ARCHIVED';
      end if;
      raise;
  end;

  -- 3. Convidada (trava).
  select c.lifecycle_status, c.default_storage_container_id into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED';
  end if;

  -- 4. Idempotência e participação única (D-única).
  select g.layout_id into v_current
  from public.collection_layout_guest g where g.collection_id = p_collection_id;
  if v_current is not null then
    if v_current = p_layout_id then
      outcome := 'ALREADY_ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
      return next;
      return;
    end if;
    raise exception 'COLLECTION_ALREADY_IN_BINDER';
  end if;
  if exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER';
  end if;

  -- 5. Local físico (D9): o local padrão da convidada é um fichário e é o
  --    local padrão de algum participante deste fichário.
  if v_default is not null then
    select sc.kind_code::text into v_kind
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;
  if v_kind is distinct from 'BINDER'
     or not exists (
       select 1 from public.collection pc
       where pc.owner_user_id = v_uid
         and pc.default_storage_container_id = v_default
         and (pc.id = v_owner_coll
              or exists (select 1 from public.collection_layout_guest g
                         where g.layout_id = p_layout_id and g.collection_id = pc.id))) then
    raise exception 'NOT_SAME_LOCATION'
      using hint = 'escolha como local padrão o mesmo fichário físico das coleções deste fichário';
  end if;

  -- 6. Associação: nenhum bolso, reserva ou carta é tocado (D3).
  insert into public.collection_layout_guest (collection_id, layout_id)
  values (p_collection_id, p_layout_id);

  outcome := 'ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
  return next;
end;
$$;

create or replace function public.list_my_binder_join_candidates(p_collection_id uuid)
returns table (
  layout_id             uuid,
  owner_collection_id   uuid,
  owner_collection_name text,
  grid_columns          integer,
  grid_rows             integer,
  page_count            integer,
  free_slot_count       integer,
  participant_count     integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_status  text;
  v_default uuid;
  v_kind    text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.lifecycle_status, c.default_storage_container_id into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Só faz sentido para coleção ativa, sem fichário próprio nem associação,
  -- guardada num fichário físico (mesma regra da 5229 §8).
  if v_status <> 'ACTIVE' or v_default is null
     or exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id)
     or exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
    return;
  end if;
  select sc.kind_code::text into v_kind
  from public.storage_container sc
  join public.inventory i on i.id = sc.inventory_id
  where sc.id = v_default and i.owner_user_id = v_uid;
  if v_kind is distinct from 'BINDER' then
    return;
  end if;

  return query
  with cand as (
    select l.id, l.collection_id, l.grid_columns, l.grid_rows
    from public.collection_layout l
    join public.collection oc on oc.id = l.collection_id
    where oc.owner_user_id = v_uid
      and oc.lifecycle_status = 'ACTIVE'
      and oc.id <> p_collection_id
      and exists (
        select 1 from public.collection pc
        where pc.owner_user_id = v_uid
          and pc.default_storage_container_id = v_default
          and (pc.id = l.collection_id
               or exists (select 1 from public.collection_layout_guest g
                          where g.layout_id = l.id and g.collection_id = pc.id)))
  )
  select cand.id,
         cand.collection_id,
         oc.name::text,
         cand.grid_columns,
         cand.grid_rows,
         (select count(*) from public.collection_layout_page p where p.layout_id = cand.id)::integer,
         (select count(*)
            from public.collection_layout_page p
            join public.collection_layout_slot s on s.page_id = p.id
           where p.layout_id = cand.id
             and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
             and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
         )::integer,
         1 + (select count(*) from public.collection_layout_guest g where g.layout_id = cand.id)::integer
  from cand
  join public.collection oc on oc.id = cand.collection_id
  order by oc.name, cand.id;
end;
$$;

-- 5254 → sem transferência; 5136 canônica ---------------------------------------------
drop function if exists public.transfer_my_binder_ownership(uuid, uuid);
create or replace function public.enforce_collection_layout_structural_fk_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_column TEXT := TG_ARGV[0];
    v_old    TEXT;
    v_new    TEXT;
BEGIN
    v_old := to_jsonb(OLD) ->> v_column;
    v_new := to_jsonb(NEW) ->> v_column;

    IF v_new IS DISTINCT FROM v_old THEN
        RAISE EXCEPTION
            '%.% é IMUTÁVEL na V1 — reparentar objetos do Layout mudaria a Collection efetiva do Slot sem revalidar as Slot Assignments; a operação suportada é remover e recriar',
            TG_TABLE_NAME, v_column;
    END IF;

    RETURN NEW;
END;
$$;

revoke execute on function public.enforce_collection_layout_structural_fk_immutability() from public, anon, authenticated;

-- 5253 → canônicas 5229 ------------------------------------------------------------------
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
  asg as (
    select a.slot_id, a.collection_allocation_id
    from public.collection_layout_slot_assignment a
    join sl on sl.id = a.slot_id
    join public.collection_allocation ca on ca.id = a.collection_allocation_id
    where ca.collection_id = p_collection_id
  ),
  exc as (
    select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id
    from public.collection_layout_slot_expected_content e
    join sl on sl.id = e.slot_id
    where e.collection_id = p_collection_id
  ),
  lk as (
    select sl.id from sl
    where sl.locked and (sl.id in (select asg.slot_id from asg) or sl.id in (select exc.slot_id from exc))
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
     and (exists (select 1 from public.collection_layout_slot_assignment a
                  join public.collection_allocation ca on ca.id = a.collection_allocation_id
                  where a.slot_id = s.id and ca.collection_id = p_collection_id)
          or exists (select 1 from public.collection_layout_slot_expected_content e
                     where e.slot_id = s.id and e.collection_id = p_collection_id));
  get diagnostics v_unlock = row_count;

  -- D5: só posições e reservas da convidada.
  delete from public.collection_layout_slot_assignment a
   using public.collection_allocation ca, public.collection_layout_slot s, public.collection_layout_page p
   where ca.id = a.collection_allocation_id and ca.collection_id = p_collection_id
     and s.id = a.slot_id and p.id = s.page_id and p.layout_id = v_layout;
  get diagnostics v_asg = row_count;

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

-- 5250 / 5249 → sem os objetos novos (5024 e 5222 originais nunca foram tocadas) ----------
drop function if exists public.place_my_physical_card_in_slot(uuid, uuid, uuid);
drop function if exists public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean);
drop function if exists public.set_physical_cards_storage(uuid, uuid[], boolean);
drop function if exists public.preview_my_collection_storage_binder_impact(uuid, uuid, text);
drop function if exists public.preview_my_physical_cards_binder_impact(uuid[], uuid);

notify pgrst, 'reload schema';

commit;
