/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R2B - Rollback do MODELO DE DADOS da fase A (desfaz 5252, 5251, 5248, 5247)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização de Fabrício,
              depois de R1 (se houve fase B) e de R2A.
Versão......: 2.0 (2026-10-24, FINAL-CORRECTIONS-01: R2 dividido em R2A
              contratos + R2B modelo de dados).
Data........: 2026-10-24

Quando usar: só se for preciso voltar ao modelo antigo (posição pela
alocação, fichário sem local próprio). Exige R1 (se houve fase B) e R2A.
Os corpos restaurados são os canônicos de database/schema/ (5118, 5136,
5224, 5229, 5230, 5246), copiados sem alteração por gerador (static S7).

PRÉ-CONDIÇÕES (abortam sem mudar nada se falharem):
  P0 R2A já aplicado (posicionar/transferir não existem mais);
  P1 a 5256 não está aplicada;
  P2 toda posição tem alocação e o exemplar da alocação é o da posição;
  P3 toda posição é de coleção participante do fichário.
Se P2/P3 falharem, existem posições que o modelo antigo NÃO representa
(exemplar sem coleção / coleção não participante). Nesse caso R2B é
INADMISSÍVEL — não há desalocação, realocação, exclusão nem "quarentena"
automáticas para torná-lo possível. O sistema permanece no modelo de dados
novo com os contratos antigos (R1 + R2A + frontend anterior) e o defeito é
tratado por CORREÇÃO POSTERIOR (migration nova, para frente). Ver
R0_post_activation_diagnostic_readonly.sql e README §5.
Efeito quando admissível: todas as posições preservadas (mesmo id, bolso,
alocação e updated_at). R2B nunca apaga posição.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard') then
    raise exception 'R2B P1: a 5256 está aplicada — rode R1 antes';
  end if;
  if to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)') is not null
     or to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)') is not null then
    raise exception 'R2B P0: rode R2A antes (contratos que dependem do modelo novo ainda existem)';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
               and column_name = 'physical_card_id') then
    if exists (select 1 from public.collection_layout_slot_assignment a
               left join public.collection_allocation ca on ca.id = a.collection_allocation_id
               where ca.id is null or ca.physical_card_id <> a.physical_card_id) then
      raise exception 'R2B P2: há posição sem alocação ou com alocação de outro exemplar — decidir antes (cabeçalho)';
    end if;
  end if;
  if exists (select 1
             from public.collection_layout_slot_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id
             join public.collection_layout_slot s on s.id = a.slot_id
             join public.collection_layout_page p on p.id = s.page_id
             join public.collection_layout l on l.id = p.layout_id
             where ca.collection_id <> l.collection_id
               and not exists (select 1 from public.collection_layout_guest g
                               where g.layout_id = l.id and g.collection_id = ca.collection_id)) then
    raise exception 'R2B P3: há posição de coleção não participante — decidir antes (cabeçalho)';
  end if;
end;
$pre$;

-- 5252 → canônicas 5230/5246 ---------------------------------------------------------------
drop function if exists public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid);
drop function public.get_my_collection_binder_pages(uuid, integer, integer);
drop function public.get_my_collection_binder(uuid);
create function public.get_my_collection_binder(p_collection_id uuid)
returns table (
  collection_id                uuid,
  collection_name              text,
  collection_kind              text,
  completion_policy            text,
  lifecycle_status             text,
  has_binder                   boolean,
  layout_id                    uuid,
  grid_columns                 integer,
  grid_rows                    integer,
  capacity_per_page            integer,
  page_count                   integer,
  slot_count                   integer,
  filled_count                 integer,
  reserved_count               integer,
  reserved_empty_count         integer,
  is_editable                  boolean,
  can_create                   boolean,
  default_storage_container_id uuid,
  default_storage_name         text,
  default_storage_kind_code    text,
  binder_role                  text,
  owner_collection_id          uuid,
  owner_collection_name        text,
  participant_count            integer,
  own_filled_count             integer,
  own_unplaced_count           integer,
  join_candidate_count         integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid       uuid := auth.uid();
  v_name      text;
  v_mode      text;
  v_policy    text;
  v_status    text;
  v_default   uuid;
  v_kind      text;
  v_layout    uuid;
  v_role      text;
  v_owner     uuid;
  v_owner_nm  text;
  v_owner_st  text;
  v_cols      integer;
  v_rows      integer;
  v_pages     integer := 0;
  v_slots     integer := 0;
  v_filled    integer := 0;
  v_resv      integer := 0;
  v_resv_e    integer := 0;
  v_parts     integer := 0;
  v_own_fill  integer := 0;
  v_own_unpl  integer := 0;
  v_cand      integer := 0;
  v_sc_name   text;
  v_sc_kind   text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer outra tabela.
  select c.name::text, c.mode, c.completion_policy, c.lifecycle_status, c.default_storage_container_id
    into v_name, v_mode, v_policy, v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_kind := case
    when v_mode = 'OPEN_CURATION' then 'FREE'
    when v_policy = 'STANDARD_SET' then 'SET'
    when v_policy = 'MASTER_SET' then 'MASTER_SET'
    when v_policy = 'REFERENCE_POSITION' then 'POKEDEX'
    else 'UNKNOWN' end;

  if v_default is not null then
    select sc.name::text, sc.kind_code::text into v_sc_name, v_sc_kind
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;

  -- Fichário próprio ou como convidada.
  select l.id, l.grid_columns, l.grid_rows into v_layout, v_cols, v_rows
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is not null then
    v_role := 'OWNER';
  else
    select l.id, l.grid_columns, l.grid_rows into v_layout, v_cols, v_rows
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
    if v_layout is not null then
      v_role := 'GUEST';
    end if;
  end if;

  if v_layout is not null then
    select l.collection_id, oc.name::text, oc.lifecycle_status into v_owner, v_owner_nm, v_owner_st
    from public.collection_layout l
    join public.collection oc on oc.id = l.collection_id
    where l.id = v_layout;

    select count(*)::integer into v_pages
    from public.collection_layout_page p where p.layout_id = v_layout;

    select count(*)::integer,
           count(a.id)::integer,
           count(e.slot_id)::integer,
           count(e.slot_id) filter (where a.id is null)::integer,
           count(a.id) filter (where ca.collection_id = p_collection_id)::integer
      into v_slots, v_filled, v_resv, v_resv_e, v_own_fill
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    left join public.collection_layout_slot_assignment a on a.slot_id = s.id
    left join public.collection_allocation ca on ca.id = a.collection_allocation_id
    left join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = v_layout;

    v_parts := 1 + (select count(*) from public.collection_layout_guest g where g.layout_id = v_layout)::integer;

    select count(*)::integer into v_own_unpl
    from public.collection_allocation ca
    where ca.collection_id = p_collection_id
      and not exists (select 1 from public.collection_layout_slot_assignment a
                      where a.collection_allocation_id = ca.id);
  else
    select count(*)::integer into v_cand
    from public.list_my_binder_join_candidates(p_collection_id);
  end if;

  return query
  select p_collection_id,
         v_name,
         v_kind,
         v_policy,
         v_status,
         v_layout is not null,
         v_layout,
         v_cols,
         v_rows,
         case when v_layout is null then null else v_cols * v_rows end,
         v_pages,
         v_slots,
         v_filled,
         v_resv,
         v_resv_e,
         v_layout is not null and v_status = 'ACTIVE' and coalesce(v_owner_st, v_status) = 'ACTIVE',
         v_layout is null and v_status = 'ACTIVE' and v_sc_kind = 'BINDER' and v_kind <> 'UNKNOWN',
         v_default,
         v_sc_name,
         v_sc_kind,
         v_role,
         v_owner,
         v_owner_nm,
         v_parts,
         v_own_fill,
         v_own_unpl,
         v_cand;
end;
$$;

revoke all on function public.get_my_collection_binder(uuid) from public;
revoke all on function public.get_my_collection_binder(uuid) from anon;
grant execute on function public.get_my_collection_binder(uuid) to authenticated;
create function public.get_my_collection_binder_pages(
  p_collection_id uuid,
  p_first_page    integer,
  p_page_count    integer
)
returns table (
  page_id                      uuid,
  page_number                  integer,
  slot_id                      uuid,
  row_index                    integer,
  column_index                 integer,
  locked                       boolean,
  region_id                    uuid,
  slot_state                   text,
  expected_card_id             uuid,
  expected_card_variant_id     uuid,
  expected_variant_type_id     uuid,
  expected_variant_type_code   text,
  expected_variant_type_name   text,
  expected_card_name           text,
  expected_collector_number    text,
  expected_collector_total     integer,
  expected_card_set_code       text,
  expected_image_path          text,
  assignment_id                uuid,
  collection_allocation_id     uuid,
  physical_card_id             uuid,
  present_card_id              uuid,
  present_card_variant_id      uuid,
  present_variant_type_id      uuid,
  present_variant_type_code    text,
  present_variant_label        text,
  present_is_default_variant   boolean,
  present_language_code        text,
  present_card_name            text,
  present_collector_number     text,
  present_collector_total      integer,
  present_card_set_code        text,
  present_image_path           text,
  present_storage_container_id uuid,
  present_collection_id        uuid,
  expected_collection_id       uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_pages constant integer := 4;
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_owner  uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_first_page is null or p_page_count is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_first_page < 1 or p_first_page > 100000
     or p_page_count < 1 or p_page_count > c_max_pages then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id, l.collection_id into v_layout, v_owner
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is null then
    select l.id, l.collection_id into v_layout, v_owner
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null then
    return;
  end if;

  return query
  with pg as (
    select p.id, p.page_number
    from public.collection_layout_page p
    where p.layout_id = v_layout
      and p.page_number between p_first_page and p_first_page + p_page_count - 1
  ),
  sl as (
    select s.id, s.page_id, s.row_index, s.column_index, s.locked, pg.page_number
    from public.collection_layout_slot s
    join pg on pg.id = s.page_id
  ),
  parts as (
    select v_owner as collection_id
    union all
    select g.collection_id from public.collection_layout_guest g where g.layout_id = v_layout
  )
  select
    sl.page_id,
    sl.page_number,
    sl.id,
    sl.row_index,
    sl.column_index,
    sl.locked,
    rg.id,
    case
      when e.slot_id is null and a.id is null then 'EMPTY'
      when e.slot_id is not null and a.id is null then 'RESERVED_EMPTY'
      when e.slot_id is null then 'OCCUPIED_UNPLANNED'
      when cv.card_id = e.card_id
           and (e.card_variant_id is null or e.card_variant_id = cv.id)
           and (e.expected_variant_type_id is null or e.expected_variant_type_id = cv.variant_type_id)
        then 'OCCUPIED_MATCH'
      else 'OCCUPIED_MISMATCH'
    end,
    e.card_id,
    e.card_variant_id,
    e.expected_variant_type_id,
    evt.code::text,
    evt.name::text,
    ec.name::text,
    ec.collector_number::text,
    ec.collector_total,
    ecs.code::text,
    eimg.storage_path::text,
    a.id,
    ca.id,
    pc.id,
    c.id,
    cv.id,
    cv.variant_type_id,
    vt.code::text,
    nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')::text,
    cv.is_default,
    l.code::text,
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    pimg.storage_path::text,
    pc.storage_container_id,
    ca.collection_id,
    case when e.slot_id is null then null else coalesce(e.collection_id, v_owner) end
  from sl
  left join public.collection_layout_slot_expected_content e on e.slot_id = sl.id
  left join public.card ec              on ec.id = e.card_id
  left join public.card_set ecs         on ecs.id = ec.card_set_id
  left join public.card_variant_type evt
         on evt.id = coalesce(e.expected_variant_type_id,
                              (select v.variant_type_id from public.card_variant v where v.id = e.card_variant_id))
  left join public.collection_layout_slot_assignment a on a.slot_id = sl.id
  left join public.collection_allocation ca
         on ca.id = a.collection_allocation_id
        and ca.collection_id in (select parts.collection_id from parts)
  left join public.physical_card pc     on pc.id = ca.physical_card_id
  left join public.card_variant cv      on cv.id = pc.card_variant_id
  left join public.card c               on c.id = cv.card_id
  left join public.card_set cs          on cs.id = c.card_set_id
  left join public.language l           on l.id = pc.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
  left join lateral (
    select r.id
    from public.collection_layout_region r
    where r.page_id = sl.page_id
      and sl.row_index    between r.top_row     and r.top_row     + r.height - 1
      and sl.column_index between r.left_column and r.left_column + r.width  - 1
    limit 1
  ) rg on true
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where c.id is not null
      and ast.card_id = c.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = pc.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) pimg on true
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where e.card_id is not null
      and ast.card_id = e.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) eimg on true
  order by sl.page_number, sl.row_index, sl.column_index;
end;
$$;

revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_pages(uuid, integer, integer) to authenticated;
create or replace function public.get_my_binder_participants(p_collection_id uuid)
returns table (
  collection_id     uuid,
  collection_name   text,
  binder_role       text,
  lifecycle_status  text,
  is_current        boolean,
  card_pocket_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_owner  uuid;
  v_role   text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id, l.collection_id into v_layout, v_owner
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is not null then
    v_role := 'OWNER';
  else
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
    if v_layout is null then
      return;
    end if;
    select l.collection_id into v_owner from public.collection_layout l where l.id = v_layout;
    v_role := 'GUEST';
  end if;

  return query
  with members as (
    select v_owner as cid, 'OWNER'::text as role
    union all
    select g.collection_id, 'GUEST'::text
    from public.collection_layout_guest g
    where g.layout_id = v_layout
      and (v_role = 'OWNER' or g.collection_id = p_collection_id)
  )
  select c.id,
         c.name::text,
         m.role,
         c.lifecycle_status::text,
         c.id = p_collection_id,
         (select count(*)
            from public.collection_layout_page p
            join public.collection_layout_slot s            on s.page_id = p.id
            join public.collection_layout_slot_assignment a on a.slot_id = s.id
            join public.collection_allocation ca            on ca.id = a.collection_allocation_id
           where p.layout_id = v_layout
             and ca.collection_id = c.id)::integer
  from members m
  join public.collection c on c.id = m.cid and c.owner_user_id = v_uid
  order by (m.role = 'OWNER') desc, c.name, c.id
  limit 200;
end;
$$;

revoke all on function public.get_my_binder_participants(uuid) from public;
revoke all on function public.get_my_binder_participants(uuid) from anon;
grant execute on function public.get_my_binder_participants(uuid) to authenticated;

-- 5251 → plano canônico 5224 (v1) ----------------------------------------------------------
create or replace function public.collection_binder_plan(
  p_collection_id uuid,
  p_grid_columns  integer,
  p_grid_rows     integer,
  p_extra_policy  text
)
returns table (
  item_kind                text,     -- HEADER | POSITION | EXTRA
  item_ord                 integer,  -- 0 no HEADER; 1.. por tipo
  page_number              integer,  -- null: adicional sem bolso
  row_index                integer,
  column_index             integer,
  expected_card_id         uuid,
  expected_variant_type_id uuid,
  collection_allocation_id uuid,
  extra_category           text,
  main_count               integer,
  extra_count              integer,
  pages_total              integer,
  plan_token               text
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_version  constant text := 'p2a1-plan-v1';
  v_cap      integer;
  v_mode     text;
  v_policy   text;
  v_kind     text;
  v_set      uuid;
  v_types    uuid[] := '{}';
  v_types_k  text := '';
  v_ref      uuid;
  v_dex      uuid;
  v_scope    text;
begin
  if p_collection_id is null or p_grid_columns is null or p_grid_rows is null
     or p_grid_columns < 1 or p_grid_rows < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_extra_policy is null or p_extra_policy not in ('PRINCIPAL_ONLY', 'APPEND_PAGES') then
    raise exception 'INVALID_EXTRA_POLICY' using errcode = '22023';
  end if;
  v_cap := p_grid_columns * p_grid_rows;

  select c.mode, c.completion_policy into v_mode, v_policy
  from public.collection c where c.id = p_collection_id;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_kind := case
    when v_mode = 'OPEN_CURATION' then 'FREE'
    when v_policy = 'STANDARD_SET' then 'SET'
    when v_policy = 'MASTER_SET' then 'MASTER_SET'
    when v_policy = 'REFERENCE_POSITION' then 'POKEDEX'
    else null end;
  if v_kind is null then
    raise exception 'COLLECTION_KIND_UNSUPPORTED' using errcode = '22023';
  end if;

  if v_kind in ('SET', 'MASTER_SET') then
    select ccsr.card_set_id into v_set
    from public.collection_reference cr
    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id;
    if v_set is null then
      raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
    end if;
  end if;

  if v_kind = 'MASTER_SET' then
    select coalesce(array_agg(f.variant_type_id order by f.variant_type_id), '{}')
      into v_types
    from public.collection_master_set_finish f
    where f.collection_id = p_collection_id;
    v_types_k := array_to_string(v_types, ',');
  end if;

  if v_kind = 'POKEDEX' then
    select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_scope
    from public.collection_reference cr
    join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id and cr.reference_kind = 'POKEDEX';
    if v_ref is null then
      raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
    end if;
  end if;

  return query
  with
  alloc as (
    select ca.id                as alloc_id,
           ca.created_at        as alloc_created,
           pc.id                as pc_id,
           pc.created_at        as pc_created,
           pc.language_id       as lang_id,
           l.language_order     as lord,
           cv.id                as var_id,
           cv.card_id           as card_id,
           cv.variant_type_id   as vt_id,
           cv.variant_order     as vord,
           coalesce(vt.display_order, 2147483647) as vt_ord,
           c.collector_order    as c_ord,
           cs.code::text        as set_code,
           pa.pokedex_position_id as link_pos,
           pa.assigned_at       as assigned_at,
           (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_set cs      on cs.id = c.card_set_id
    join public.language l       on l.id = pc.language_id
    left join public.card_variant_type vt on vt.id = cv.variant_type_id
    left join public.collection_pokedex_position_assignment pa
           on v_kind = 'POKEDEX' and pa.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
           on v_kind = 'POKEDEX' and pr.collection_allocation_id = ca.id
          and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
  ),
  dex_pos as (
    select pp.id as pos_id, pp.position_number as pnum
    from public.pokedex_position pp
    join public.pokemon_species s on s.id = pp.species_id
    where v_kind = 'POKEDEX'
      and pp.pokedex_id = v_dex
      and pp.id in (select a.link_pos from alloc a where a.link_pos is not null)
      and (v_scope = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref
                        and sg.generation_id = s.generation_id))
  ),
  pos as (
    select c.id::text as pos_key, c.id as exp_card, null::uuid as exp_vt,
           (row_number() over (order by c.collector_order, c.collector_number, c.id))::integer as pos_ord
    from public.card c
    where v_kind = 'SET' and c.card_set_id = v_set
    union all
    select m.card_id::text || ':' || coalesce(m.variant_type_id::text, '*'),
           m.card_id, m.variant_type_id,
           (row_number() over (order by c.collector_order, c.collector_number, c.id,
                                        (m.variant_type_id is null),
                                        coalesce(t.display_order, 2147483647),
                                        m.variant_type_id))::integer
    from public.master_set_positions(case when v_kind = 'MASTER_SET' then v_set end, v_types) m
    join public.card c on c.id = m.card_id
    left join public.card_variant_type t on t.id = m.variant_type_id
    where v_kind = 'MASTER_SET'
    union all
    select d.pos_id::text, null::uuid, null::uuid,
           (row_number() over (order by d.pnum, d.pos_id))::integer
    from dex_pos d
    union all
    select a.alloc_id::text, null::uuid, null::uuid,
           (row_number() over (order by a.alloc_created, a.set_code, a.c_ord, a.vt_ord,
                                        a.vord, a.lord, a.pc_created, a.pc_id))::integer
    from alloc a
    where v_kind = 'FREE'
  ),
  grouped as (
    select a.*,
           case v_kind
             when 'SET'        then p_card.pos_key
             when 'MASTER_SET' then coalesce(p_type.pos_key, p_star.pos_key)
             when 'POKEDEX'    then p_dex.pos_key
             when 'FREE'       then a.alloc_id::text
           end as grp,
           case when v_kind = 'POKEDEX' then (case when a.is_rep then 0 else 1 end) else 0 end as k_rep,
           case when v_kind = 'POKEDEX' then a.assigned_at end                               as k_assigned,
           case when v_kind = 'POKEDEX' then 0 else a.vt_ord end                             as k_vt,
           case when v_kind = 'POKEDEX' then 0 else a.vord end                               as k_vord,
           case when v_kind = 'POKEDEX' then 0 else a.lord end                               as k_lord,
           case when v_kind = 'POKEDEX'
                then (case when a.link_pos is null then a.alloc_created end)
                else a.pc_created end                                                        as k_created,
           case when v_kind = 'POKEDEX' then a.alloc_id else a.pc_id end                      as k_tie
    from alloc a
    left join pos p_card on v_kind = 'SET'        and p_card.pos_key = a.card_id::text
    left join pos p_type on v_kind = 'MASTER_SET' and p_type.pos_key = a.card_id::text || ':' || a.vt_id::text
    left join pos p_star on v_kind = 'MASTER_SET' and p_star.pos_key = a.card_id::text || ':*'
    left join pos p_dex  on v_kind = 'POKEDEX'    and p_dex.pos_key  = a.link_pos::text
  ),
  ranked as (
    select g.*,
           row_number() over (partition by g.grp
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk,
           row_number() over (partition by g.grp, g.var_id, g.lang_id
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk_vl,
           row_number() over (partition by g.grp, g.var_id
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk_v
    from grouped g
  ),
  main as (
    select p.pos_ord as m_ord, p.exp_card, p.exp_vt, r.alloc_id
    from pos p
    left join ranked r on r.grp = p.pos_key and r.rk = 1
  ),
  extras as (
    select r.alloc_id,
           case when r.grp is null then 'OUT_OF_OBJECTIVE'
                when r.rk_vl > 1  then 'IDENTICAL_COPY'
                when r.rk_v  > 1  then 'OTHER_LANGUAGE'
                else 'OTHER_VARIANT' end as category,
           (row_number() over (order by (r.grp is null), p.pos_ord nulls last,
                                        case when v_kind in ('SET', 'MASTER_SET') then r.c_ord else 0 end,
                                        case when v_kind in ('SET', 'MASTER_SET') then r.card_id end,
                                        r.k_rep, r.k_assigned nulls last, r.k_vt, r.k_vord, r.k_lord,
                                        r.k_created nulls last, r.k_tie))::integer as x_ord
    from ranked r
    left join pos p on p.pos_key = r.grp
    where r.grp is null or r.rk > 1
  ),
  geo as (
    select d.m_cnt, d.e_cnt,
           ((d.m_cnt + v_cap - 1) / v_cap)::integer as main_pages,
           (case when p_extra_policy = 'APPEND_PAGES' then (d.e_cnt + v_cap - 1) / v_cap else 0 end)::integer as extra_pages
    from (select (select count(*) from main)::integer as m_cnt,
                 (select count(*) from extras)::integer as e_cnt) d
  ),
  placed as (
    select 'POSITION'::text as k,
           m.m_ord as o,
           ((m.m_ord - 1) / v_cap + 1)::integer as pg,
           (((m.m_ord - 1) % v_cap) / p_grid_columns + 1)::integer as rw,
           (((m.m_ord - 1) % v_cap) % p_grid_columns + 1)::integer as cl,
           m.exp_card as ec, m.exp_vt as ev, m.alloc_id as al, null::text as cat
    from main m
    union all
    select 'EXTRA'::text,
           x.x_ord,
           case when p_extra_policy = 'APPEND_PAGES'
                then (g.main_pages + (x.x_ord - 1) / v_cap + 1)::integer end,
           case when p_extra_policy = 'APPEND_PAGES'
                then (((x.x_ord - 1) % v_cap) / p_grid_columns + 1)::integer end,
           case when p_extra_policy = 'APPEND_PAGES'
                then (((x.x_ord - 1) % v_cap) % p_grid_columns + 1)::integer end,
           null::uuid, null::uuid, x.alloc_id, x.category
    from extras x
    cross join geo g
  ),
  tok as (
    select 'v1:' || encode(sha256(convert_to(
             c_version || '|' || p_collection_id::text || '|' || v_kind || '|' || coalesce(v_policy, '') || '|'
             || p_grid_columns::text || 'x' || p_grid_rows::text || '|' || p_extra_policy || '|' || v_types_k || '|'
             || (select greatest(1, g.main_pages + g.extra_pages)::text from geo g)
             || E'\n'
             || coalesce(string_agg(
                  concat_ws('|', pl.k, pl.o,
                            coalesce(pl.pg::text, '-'), coalesce(pl.rw::text, '-'), coalesce(pl.cl::text, '-'),
                            coalesce(pl.ec::text, '-'), coalesce(pl.ev::text, '-'),
                            coalesce(pl.al::text, '-'), coalesce(pl.cat, '-')),
                  E'\n' order by pl.k, pl.o), ''),
             'UTF8')), 'hex') as t
    from placed pl
  )
  select 'HEADER'::text, 0, null::integer, null::integer, null::integer, null::uuid, null::uuid, null::uuid, null::text,
         g.m_cnt, g.e_cnt, greatest(1, g.main_pages + g.extra_pages)::integer, t.t
  from geo g cross join tok t
  union all
  select pl.k, pl.o, pl.pg, pl.rw, pl.cl, pl.ec, pl.ev, pl.al, pl.cat,
         g.m_cnt, g.e_cnt, greatest(1, g.main_pages + g.extra_pages)::integer, t.t
  from placed pl cross join geo g cross join tok t;
end;
$$;

revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from public;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from anon;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from authenticated;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from service_role;

-- 5248 → posição pela alocação (5115/5117/5118/5229) ----------------------------------------
create or replace function public.enforce_collection_layout_slot_assignment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allocation_collection_id uuid;
  v_layout_id                uuid;
  v_layout_collection_id     uuid;
  v_status                   text;
begin
  -- §6 (5117) collection_allocation_id imutável.
  if tg_op = 'UPDATE'
     and new.collection_allocation_id is distinct from old.collection_allocation_id then
    raise exception
      'collection_allocation_id de uma Slot Assignment é IMUTÁVEL — use a operação REPLACE (assign_card_to_slot), que remove a Assignment antiga e cria uma nova; UPDATE direto contornaria o enforcement de Lock';
  end if;

  select ca.collection_id into v_allocation_collection_id
  from public.collection_allocation ca
  where ca.id = new.collection_allocation_id;
  if not found then
    raise exception 'collection_allocation_id % não existe', new.collection_allocation_id;
  end if;

  select l.id, l.collection_id into v_layout_id, v_layout_collection_id
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  join public.collection_layout l      on l.id = p.layout_id
  where s.id = new.slot_id;
  if not found then
    raise exception 'slot_id % não existe', new.slot_id;
  end if;

  if v_allocation_collection_id is distinct from v_layout_collection_id then
    -- 5229: convidada do MESMO fichário também pode ocupar bolsos.
    if not exists (select 1 from public.collection_layout_guest g
                   where g.collection_id = v_allocation_collection_id
                     and g.layout_id = v_layout_id) then
      raise exception
        'Physical Card não está alocada a uma coleção participante deste fichário — Slot Assignment exige alocação prévia à proprietária ou a uma convidada';
    end if;
    -- Convidada arquivada é somente leitura (C-37). Leitura SEM trava de
    -- propósito (AUDIT-CORRECTION-01): o gatilho roda depois de a posição
    -- já estar travada; travar a coleção aqui inverteria a ordem da 5047
    -- (coleção → alocação → posição em cascata) e formaria ciclo com
    -- move_slot_assignment (5132). A RPC de entrada (5131 evoluída) trava a
    -- convidada ANTES da alocação; move/troca ficam com esta checagem.
    select c.lifecycle_status into v_status
    from public.collection c where c.id = v_allocation_collection_id;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED'
        using hint = 'a coleção desta carta está arquivada — reative-a para organizar';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_collection_layout_slot_assignment_integrity() from public, anon, authenticated;
create or replace function public.enforce_collection_layout_slot_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_locked BOOLEAN;
BEGIN
    -- ---------------------------------------------------------------
    -- DELETE: origem locked bloqueia, EXCETO cascade de desalocação.
    -- ---------------------------------------------------------------
    IF TG_OP = 'DELETE' THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.collection_allocation ca
            WHERE ca.id = OLD.collection_allocation_id
        ) THEN
            -- A Allocation já não existe: este DELETE é o CASCADE da
            -- desalocação da Physical Card da Collection. Lock não se
            -- aplica (C-43 não lista desalocação).
            RETURN OLD;
        END IF;

        SELECT s.locked INTO v_locked
          FROM public.collection_layout_slot s
         WHERE s.id = OLD.slot_id;

        IF COALESCE(v_locked, FALSE) THEN
            RAISE EXCEPTION
                'Slot bloqueado (locked) — Remove/Bandeja não permitido enquanto o Lock estiver ativo';
        END IF;

        RETURN OLD;
    END IF;

    -- ---------------------------------------------------------------
    -- UPDATE (MOVE/SWAP): origem OU destino locked bloqueia.
    -- ---------------------------------------------------------------
    IF TG_OP = 'UPDATE' THEN

        IF NEW.slot_id IS DISTINCT FROM OLD.slot_id THEN

            SELECT s.locked INTO v_locked
              FROM public.collection_layout_slot s
             WHERE s.id = OLD.slot_id;

            IF COALESCE(v_locked, FALSE) THEN
                RAISE EXCEPTION
                    'Slot de origem bloqueado (locked) — Move/Swap não permitido';
            END IF;

            SELECT s.locked INTO v_locked
              FROM public.collection_layout_slot s
             WHERE s.id = NEW.slot_id;

            IF COALESCE(v_locked, FALSE) THEN
                RAISE EXCEPTION
                    'Slot de destino bloqueado (locked) — Move/Swap não permitido';
            END IF;

        END IF;

        RETURN NEW;
    END IF;

    -- ---------------------------------------------------------------
    -- INSERT (ADD/REPLACE): destino locked bloqueia.
    -- ---------------------------------------------------------------
    SELECT s.locked INTO v_locked
      FROM public.collection_layout_slot s
     WHERE s.id = NEW.slot_id;

    IF COALESCE(v_locked, FALSE) THEN
        RAISE EXCEPTION
            'Slot bloqueado (locked) — Add/Replace não permitido enquanto o Lock estiver ativo';
    END IF;

    RETURN NEW;
END;
$$;

revoke all on function public.enforce_collection_layout_slot_lock() from public, anon, authenticated;

alter table public.collection_layout_slot_assignment drop constraint if exists fk_collection_layout_slot_assignment_allocation;
alter table public.collection_layout_slot_assignment
  alter column collection_allocation_id set not null,
  add constraint collection_layout_slot_assignment_collection_allocation_id_fkey
    foreign key (collection_allocation_id) references public.collection_allocation(id)
    on update restrict on delete cascade;
alter table public.collection_layout_slot_assignment
  drop constraint if exists uq_collection_layout_slot_assignment_physical_card,
  drop constraint if exists fk_collection_layout_slot_assignment_physical_card,
  drop column if exists physical_card_id;

-- 5247 → fichário sem local próprio --------------------------------------------------------
drop trigger if exists trg_storage_container_binder_kind on public.storage_container;
drop function if exists public.enforce_storage_container_binder_kind();
drop trigger if exists trg_collection_layout_storage_container on public.collection_layout;
drop function if exists public.enforce_collection_layout_storage_container();
alter table public.collection_layout
  drop constraint if exists uq_collection_layout_storage_container,
  drop constraint if exists fk_collection_layout_storage_container,
  drop column if exists storage_container_id;

do $post$
begin
  if exists (select 1 from public.collection_layout_slot_assignment where collection_allocation_id is null) then
    raise exception 'R2B POSTCHECK: posição sem alocação';
  end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;

/*
Depois do R2B: rodar LIVE_00 (deve voltar a PASS nas p03–p06) e comparar
assignments_md5 com o valor anotado antes da fase A (mesmo id, bolso,
alocação e updated_at — DROP COLUMN não reescreve linhas visíveis).
O frontend precisa estar na versão anterior (o novo depende da 5250/5252).
*/
