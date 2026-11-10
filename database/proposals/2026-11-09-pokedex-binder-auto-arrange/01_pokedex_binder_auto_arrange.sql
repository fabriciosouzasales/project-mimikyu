-- =============================================================================
-- 5360 — CONFIRMADO EXECUTADO no LIVE em 2026-11-09 (migration pokedex_binder_auto_arrange) — Organização automática do fichário: Pokédex
-- =============================================================================
-- Estende P2 (5342/5343/5344, contrato binder-auto-arrange v1.5) às coleções Pokédex
-- (REFERENCE_POSITION). Decisão do proprietário (2026-11-09): com várias cópias da mesma
-- espécie, vai para o bolso a REPRESENTANTE (mesma regra da grade 5204: representante
-- escolhida → vínculo mais antigo); as demais ficam em "Cartas disponíveis".
--
-- Ramo Pokédex: bolsos = referências de espécie (5257–5260) vazios e livres; candidatas =
-- exemplares da coleção no local do fichário, fora de bolsos; par = (bolso da espécie,
-- representante). 1:1 por construção (uma referência por espécie, um vínculo por alocação).
-- Novo motivo de exclusão: NOT_REPRESENTATIVE. Bolsos de espécie sem carta NÃO viram
-- UNFILLED_SLOT (seriam até 1.025 linhas sem valor para o colecionador).
-- Set/Master Set: `slots` ganha só `not dex` (falso) e `cands` uma coluna extra → plano e
-- token idênticos (conferido em dry-run). Fórmula do token inalterada (aa1.2).
-- Grants/revokes preservados (CREATE OR REPLACE mantém ACL).
-- =============================================================================

begin;

create or replace function public.binder_auto_arrange_plan(
  p_collection_id uuid,
  p_layout_id     uuid,
  p_container_id  uuid
)
returns table (
  item_kind        text,     -- HEADER | INSERT | EXCLUDED_CARD | UNFILLED_SLOT
  ord              integer,
  slot_id          uuid,
  physical_card_id uuid,
  page_number      integer,
  row_index        integer,
  column_index     integer,
  card_id          uuid,
  card_variant_id  uuid,
  reason           text,
  insert_count     integer,
  plan_token       text
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  with
  owner_ as (
    select c.owner_user_id as uid
    from public.collection c
    where c.id = p_collection_id
  ),
  -- Pokédex (REFERENCE_POSITION) usa os bolsos de espécie (5257–5260) no lugar das reservas.
  kind_ as (
    select coalesce(bool_or(c.completion_policy = 'REFERENCE_POSITION'), false) as dex
    from public.collection c
    where c.id = p_collection_id
  ),
  slots as (
    select s.id as sid, p.page_number as pg, s.row_index as rw, s.column_index as cl,
           e.card_id as e_card, e.card_variant_id as e_var, e.expected_variant_type_id as e_vt
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = p_layout_id
      and not (select k.dex from kind_ k)
      and (e.collection_id is null or e.collection_id = p_collection_id)
      and not s.locked
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
      and not exists (
        select 1 from public.collection_layout_region r
        where r.page_id = p.id
          and s.row_index    between r.top_row     and r.top_row     + r.height - 1
          and s.column_index between r.left_column and r.left_column + r.width  - 1)
  ),
  dex_slots as (   -- bolso de espécie vazio e livre (sem reserva, imagem, região ou trava)
    select s.id as sid, p.page_number as pg, s.row_index as rw, s.column_index as cl,
           r.pokedex_position_id as pos
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    join public.collection_layout_slot_species_reference r on r.slot_id = s.id
    where (select k.dex from kind_ k)
      and p.layout_id = p_layout_id
      and r.layout_id = p_layout_id
      and r.collection_id = p_collection_id
      and not s.locked
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
      and not exists (
        select 1 from public.collection_layout_region rg
        where rg.page_id = p.id
          and s.row_index    between rg.top_row     and rg.top_row     + rg.height - 1
          and s.column_index between rg.left_column and rg.left_column + rg.width  - 1)
  ),
  all_slots as (
    select s.sid, s.pg, s.rw, s.cl from slots s
    union all
    select d.sid, d.pg, d.rw, d.cl from dex_slots d
  ),
  dex_rep as (     -- representante da espécie: a mesma regra da grade (5204)
    select distinct on (a.pokedex_position_id) a.pokedex_position_id as pos, ca.physical_card_id as pid
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
      on pr.collection_allocation_id = ca.id and pr.collection_id = p_collection_id
    where (select k.dex from kind_ k)
      and ca.collection_id = p_collection_id
    order by a.pokedex_position_id, (pr.collection_allocation_id is not null) desc, a.assigned_at, ca.id
  ),
  cands as (
    select pc.id as pid, pc.card_variant_id as var, cv.card_id as card, cv.variant_type_id as vt,
           cv.is_active as active, pa.pokedex_position_id as dpos
    from public.collection_allocation ca
    left join public.collection_pokedex_position_assignment pa on pa.collection_allocation_id = ca.id
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i on i.id = pc.inventory_id
    join owner_ o on o.uid = i.owner_user_id
    join public.card_variant cv on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
      and pc.storage_container_id = p_container_id
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  pairs as (
    select s.sid, c.pid, c.active
    from slots s
    join cands c
      on c.card = s.e_card
     and (s.e_var is null or s.e_var = c.var)
     and (s.e_vt  is null or s.e_vt  = c.vt)
    union all
    select d.sid, c.pid, c.active
    from dex_slots d
    join cands c on c.dpos = d.pos
    join dex_rep rp on rp.pos = d.pos and rp.pid = c.pid
  ),
  sdeg as (select pr.sid, count(*) as n from pairs pr group by pr.sid),
  cdeg as (select pr.pid, count(*) as n from pairs pr group by pr.pid),
  ins as (
    select s.sid, c.pid, s.pg, s.rw, s.cl, c.card, c.var,
           row_number() over (order by s.pg, s.rw, s.cl, s.sid)::integer as o
    from pairs pr
    join sdeg sd on sd.sid = pr.sid and sd.n = 1
    join cdeg cd on cd.pid = pr.pid and cd.n = 1
    join all_slots s on s.sid = pr.sid
    join cands c on c.pid = pr.pid
    where pr.active
  ),
  slot_peer as (   -- maior grau entre os exemplares compatíveis com cada bolso
    select pr.sid, max(cd.n) as mx from pairs pr join cdeg cd on cd.pid = pr.pid group by pr.sid
  ),
  card_reason as (
    select c.pid, c.card, c.var,
           case
             when not c.active then 'INACTIVE_VARIANT'
             when cd.n is null and rp.pid is not null and rp.pid <> c.pid then 'NOT_REPRESENTATIVE'
             when cd.n is null then 'NO_COMPATIBLE_RESERVATION'
             when cd.n > 1     then 'MULTIPLE_DESTINATIONS'
             else 'COMPETING_CANDIDATES'
           end as why
    from cands c
    left join cdeg cd on cd.pid = c.pid
    left join dex_rep rp on rp.pos = c.dpos
    where not exists (select 1 from ins x where x.pid = c.pid)
  ),
  slot_reason as (
    select s.sid, s.pg, s.rw, s.cl, s.e_card, s.e_var,
           case
             when sd.n is null then 'NO_CANDIDATE'
             when sd.n > 1     then 'COMPETING_CANDIDATES'
             when sp.mx > 1    then 'MULTIPLE_DESTINATIONS'
             else 'INACTIVE_VARIANT'
           end as why
    from slots s
    left join sdeg sd on sd.sid = s.sid
    left join slot_peer sp on sp.sid = s.sid
    where not exists (select 1 from ins x where x.sid = s.sid)
  ),
  epoch as (
    select coalesce((select max(e.id)
                     from public.binder_activity_event e
                     join owner_ o on o.uid = e.owner_user_id
                     where e.layout_key = p_layout_id
                       and e.event_type = 'CARDS_AUTO_ARRANGED'), 0)::text
           || '/'
           || coalesce((select cv.reason || '@' || (extract(epoch from cv.updated_at) * 1000000)::bigint::text
                        from public.binder_activity_coverage cv
                        join owner_ o on o.uid = cv.owner_user_id
                        where cv.layout_key = p_layout_id), '-') as v
  ),
  tok as (
    select (select count(*) from ins)::integer as n,
           'aa1:' || encode(sha256(convert_to(
             'aa1.2|' || p_collection_id::text || '|' || p_layout_id::text || '|'
             || coalesce(p_container_id::text, '-') || '|e=' || (select v from epoch)
             || '|' || (select count(*) from ins)::text
             || E'\n'
             || coalesce((select string_agg(x.sid::text || '|' || x.pid::text, E'\n' order by x.o) from ins x), ''),
             'UTF8')), 'hex') as t
  )
  select 'HEADER'::text, 0, null::uuid, null::uuid, null::integer, null::integer, null::integer,
         null::uuid, null::uuid, null::text, t.n, t.t
  from tok t
  union all
  select 'INSERT', x.o, x.sid, x.pid, x.pg, x.rw, x.cl, x.card, x.var, null, t.n, t.t
  from ins x cross join tok t
  union all
  select 'EXCLUDED_CARD', (row_number() over (order by r.why, r.pid))::integer, null, r.pid,
         null, null, null, r.card, r.var, r.why, t.n, t.t
  from card_reason r cross join tok t
  union all
  select 'UNFILLED_SLOT', (row_number() over (order by r.pg, r.rw, r.cl, r.sid))::integer, r.sid, null,
         r.pg, r.rw, r.cl, r.e_card, r.e_var, r.why, t.n, t.t
  from slot_reason r cross join tok t
$fn$;

comment on function public.binder_auto_arrange_plan(uuid, uuid, uuid) is
  'P2 5342 (C-220..C-226) + Pokédex (2026-11-09): plano determinístico e somente leitura da organização automática (proprietária; Set/Master Set: bolsos reservados vazios e livres; Pokédex: bolsos de espécie vazios e livres recebem a representante da espécie; exemplares alocados no local do fichário fora de bolsos; 1:1 estrito sem desempate; token aa1). Interna: chamada só por 5343/5344.';

create or replace function public.preview_my_binder_auto_arrange(p_collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  c_limit     constant integer := 500;
  v_uid       uuid := auth.uid();
  v_mode      text;
  v_policy    text;
  v_status    text;
  v_layout    uuid;
  v_container uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.mode, c.completion_policy, c.lifecycle_status
    into v_mode, v_policy, v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select l.id, l.storage_container_id into v_layout, v_container
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'AUTO_ARRANGE_NOT_BINDER_OWNER' using errcode = '42501';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Plano calculado UMA vez (CTE referenciada várias vezes ⇒ materializada).
  return (
    with plan as materialized (
      select * from public.binder_auto_arrange_plan(p_collection_id, v_layout, v_container)
    ),
    h as (
      select p.insert_count as n, p.plan_token as t,
             case when p.insert_count = 0 then 'EMPTY'
                  when p.insert_count > c_limit then 'LIMIT_EXCEEDED'
                  else 'READY' end as st
      from plan p where p.item_kind = 'HEADER'
    )
    select jsonb_build_object(
      'status',         h.st,
      'insert_count',   h.n,
      'limit',          c_limit,
      'plan_token',     h.t,
      'excluded_cards', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'EXCLUDED_CARD' group by p.reason) x), '{}'::jsonb),
      'unfilled_slots', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'UNFILLED_SLOT' group by p.reason) x), '{}'::jsonb),
      'unfilled_count', (select count(*) from plan p where p.item_kind = 'UNFILLED_SLOT'),
      'pages',          coalesce((select jsonb_agg(distinct p.page_number order by p.page_number)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb),
      'items',          case when h.st = 'LIMIT_EXCEEDED' then '[]'::jsonb
                             else coalesce((select jsonb_agg(jsonb_build_object(
                                     'ord', p.ord, 'slot_id', p.slot_id, 'physical_card_id', p.physical_card_id,
                                     'page_number', p.page_number, 'row_index', p.row_index,
                                     'column_index', p.column_index, 'card_id', p.card_id,
                                     'card_variant_id', p.card_variant_id) order by p.ord)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb) end
    )
    from h
  );
end;
$fn$;

comment on function public.preview_my_binder_auto_arrange(uuid) is
  'P2 5343 (C-220..C-226) + Pokédex (2026-11-09): prévia somente leitura da organização automática do fichário da coleção (titular, Set/Master Set/Pokédex, proprietária). Devolve status READY/EMPTY/LIMIT_EXCEEDED, contagens por motivo, itens (até 500) e plan_token aa1 exigido por apply_my_binder_auto_arrange.';

create or replace function public.apply_my_binder_auto_arrange(
  p_collection_id uuid,
  p_plan_token    text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
declare
  c_limit     constant integer := 500;
  v_uid       uuid := auth.uid();
  v_mode      text;
  v_policy    text;
  v_status    text;
  v_layout    uuid;
  v_container uuid;
  v_n         integer;
  v_token     text;
  v_event     bigint;
  v_rows      integer;
  v_slots     uuid[];
  v_cards     uuid[];
  v_pages     jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^aa1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Fronteira de dono e tipo, sem trava (mesmas regras e ordem da prévia).
  select c.mode, c.completion_policy, c.lifecycle_status
    into v_mode, v_policy, v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'AUTO_ARRANGE_NOT_BINDER_OWNER' using errcode = '42501';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Proprietária → layout (5122: dono, ACTIVE; trava a coleção FOR UPDATE).
  --    v1.3: só os dois RAISE de domínio da 5122 (P0001) são traduzidos; trava
  --    ocupada (55P03), deadlock, permissão e demais erros propagam intactos.
  begin
    perform public.assert_collection_layout_mutable(v_layout);
  exception
    when raise_exception then
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
      elsif sqlerrm = 'collection layout not found or not owned by caller' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      end if;
      raise;
  end;

  -- Revalida sob a trava (arquivamento, troca de objetivo ou transferência concorrentes).
  select c.mode, c.completion_policy, c.lifecycle_status
    into v_mode, v_policy, v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;
  select l.storage_container_id into v_container
  from public.collection_layout l
  where l.id = v_layout and l.collection_id = p_collection_id;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 3. Primeiro recálculo + comparação (uma passada: token, contagem e pares).
  select max(h.plan_token), max(h.insert_count),
         array_agg(h.slot_id order by h.slot_id) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.physical_card_id) filter (where h.item_kind = 'INSERT')
    into v_token, v_n, v_slots, v_cards
  from public.binder_auto_arrange_plan(p_collection_id, v_layout, v_container) h;

  if v_token is distinct from p_plan_token then
    -- Repetição de uma confirmação que já foi aplicada? (idempotência)
    select e.id into v_event
    from public.binder_activity_event e
    where e.layout_key = v_layout
      and e.owner_user_id = v_uid
      and e.event_type = 'CARDS_AUTO_ARRANGED'
      and e.summary ->> 'plan_token' = p_plan_token
    order by e.id desc
    limit 1;
    if v_event is not null then
      return jsonb_build_object('status', 'ALREADY_APPLIED', 'inserted', 0, 'event_id', v_event);
    end if;
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;

  if v_n = 0 then
    return jsonb_build_object('status', 'NOTHING_TO_DO', 'inserted', 0);
  end if;
  if v_n > c_limit then
    raise exception 'AUTO_ARRANGE_LIMIT_EXCEEDED' using errcode = '54000',
      detail = format('%s inserções planejadas; limite %s por confirmação', v_n, c_limit);
  end if;

  -- 4. Travas dos bolsos e dos exemplares do plano (ordem por id, sem ciclo).
  perform 1 from public.collection_layout_slot s
  where s.id = any(v_slots)
  order by s.id
  for update of s;

  perform 1 from public.physical_card pc
  where pc.id = any(v_cards)
  order by pc.id
  for update of pc;

  -- 5. Segundo recálculo sob todas as travas; os pares a gravar vêm DESTE cálculo.
  select max(h.plan_token),
         array_agg(h.slot_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         coalesce(jsonb_agg(distinct h.page_number order by h.page_number)
                    filter (where h.item_kind = 'INSERT'), '[]'::jsonb)
    into v_token, v_slots, v_cards, v_pages
  from public.binder_auto_arrange_plan(p_collection_id, v_layout, v_container) h;
  if v_token is distinct from p_plan_token then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;

  -- 6. Escrita + histórico (evento aberto só agora, depois de toda validação).
  perform public.binder_activity_begin(v_layout, 'CARDS_AUTO_ARRANGED', 'FICHARIO', p_collection_id,
                                       jsonb_build_object('plan_token', p_plan_token, 'inserted', v_n));
  v_rows := 0;
  for i in 1 .. coalesce(array_length(v_slots, 1), 0) loop
    begin
      insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
      values (v_slots[i], v_cards[i]);
    exception
      when unique_violation then
        raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
          hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
    end;
    perform public.binder_activity_add_card_item('PLACED', v_cards[i], null, v_slots[i]);
    v_rows := v_rows + 1;
  end loop;

  if v_rows <> v_n then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001';
  end if;

  v_event := (nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb ->> 'event_id')::bigint;
  perform public.binder_activity_end();

  return jsonb_build_object('status', 'APPLIED', 'inserted', v_rows, 'event_id', v_event, 'pages', v_pages);
end;
$fn$;

comment on function public.apply_my_binder_auto_arrange(uuid, text) is
  'P2 5344 (C-220..C-226) + Pokédex (2026-11-09): confirma a organização automática do fichário (proprietária, Set/Master Set/Pokédex). Recalcula o plano sob travas (coleção → bolsos → exemplares), exige o mesmo token aa1 (senão AUTO_ARRANGE_PLAN_CHANGED 40001), limite 500 (AUTO_ARRANGE_LIMIT_EXCEEDED 54000), só INSERT de posições, um evento CARDS_AUTO_ARRANGED com um item PLACED por carta. Repetição do token já aplicado → ALREADY_APPLIED.';

commit;
