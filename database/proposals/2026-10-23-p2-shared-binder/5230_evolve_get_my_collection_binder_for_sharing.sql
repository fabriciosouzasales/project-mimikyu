/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5230 - Fichário Digital compartilhado: leituras
              get_my_collection_binder(uuid)                    — evolução (DROP+CREATE)
              get_my_collection_binder_pages(uuid, int, int)    — evolução (DROP+CREATE)
              list_my_binder_join_candidates(uuid)              — nova
              get_my_collection_binder_unplaced(uuid, int, int) — nova
Versão......: 1.0 (2026-10-23, P2-SHARED-BINDER-PROPOSAL-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depende da 5229.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Retrocompatível: mesmas assinaturas de entrada; as saídas só GANHAM
colunas no fim (o parser do app ignora colunas desconhecidas). Para uma
coleção sem compartilhamento, todas as colunas antigas mantêm o mesmo
valor da 5223.

Resolução do fichário de uma coleção C:
  próprio  — collection_layout.collection_id = C          (binder_role OWNER)
  convidado — collection_layout_guest.collection_id = C   (binder_role GUEST)
Participantes de um fichário = proprietária ∪ convidadas (todas do mesmo
dono — 5229). Nenhuma leitura devolve dado de coleção não participante.

Cabeçalho — colunas novas (no fim):
  binder_role            text     OWNER | GUEST | null
  owner_collection_id    uuid     proprietária do fichário
  owner_collection_name  text
  participant_count      integer  1 + convidadas
  own_filled_count       integer  bolsos com cartas DESTA coleção
  own_unplaced_count     integer  cartas desta coleção fora dos bolsos
  join_candidate_count   integer  fichários que esta coleção pode usar
                                  (só quando sem fichário; 5229 revalida)
  Mudanças de semântica: has_binder/layout_id passam a valer também para
  a convidada; is_editable exige proprietária E esta coleção ACTIVE;
  can_create é falso para convidada. filled/reserved_* continuam do
  fichário inteiro (o que se vê nas páginas).

Bolsos — colunas novas (no fim):
  present_collection_id  uuid  coleção da carta no bolso
  expected_collection_id uuid  coleção dona da reserva (NULL gravado →
                               proprietária)
  A carta de qualquer participante é exibida (antes: só da própria
  coleção — com convidadas, a proprietária veria bolsos "ocupados sem
  carta").

Desempenho: NÃO MEDIDO. Custo dos bolsos inalterado (≤ 4 páginas); o
filtro de participante usa a PK de collection_layout_guest. Candidatos:
coleções do dono com o mesmo local padrão (sem índice novo; volume por
usuário pequeno). Cartas fora dos bolsos: anti-join por
UNIQUE(collection_allocation_id) da posição, paginado (≤ 96).
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_guest') is null then
    raise exception 'PRECHECK 5230: aplique a 5229 antes';
  end if;
  if to_regprocedure('public.list_my_binder_join_candidates(uuid)') is not null
     or to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is not null then
    raise exception 'PRECHECK 5230: funções novas já existem';
  end if;
end;
$pre$;

drop function public.get_my_collection_binder(uuid);
drop function public.get_my_collection_binder_pages(uuid, integer, integer);

-- 1. Candidatos (usado também pelo cabeçalho) ----------------------------------------
create function public.list_my_binder_join_candidates(p_collection_id uuid)
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

comment on function public.list_my_binder_join_candidates(uuid) is
  'Fichário compartilhado (5230, C-195): fichários digitais que esta coleção pode usar — do mesmo dono, cuja proprietária está ativa e com algum participante guardado no mesmo fichário físico (local padrão). Vazio se a coleção está arquivada, já tem fichário, já é convidada ou não está num fichário físico. Não enumera.';

revoke all on function public.list_my_binder_join_candidates(uuid) from public;
revoke all on function public.list_my_binder_join_candidates(uuid) from anon;
grant execute on function public.list_my_binder_join_candidates(uuid) to authenticated;

-- 2. Cabeçalho -----------------------------------------------------------------------
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

comment on function public.get_my_collection_binder(uuid) is
  'Fichário Digital (5223 → 5230): cabeçalho da coleção — fichário próprio (OWNER) ou compartilhado (GUEST), proprietária, participantes, contagens do fichário e desta coleção (cartas nos bolsos e fora deles), editável (proprietária e esta coleção ativas), pode criar, candidatos a compartilhar e local padrão. Não enumera; arquivada é legível.';

revoke all on function public.get_my_collection_binder(uuid) from public;
revoke all on function public.get_my_collection_binder(uuid) from anon;
grant execute on function public.get_my_collection_binder(uuid) to authenticated;

-- 3. Bolsos paginados ------------------------------------------------------------------
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

comment on function public.get_my_collection_binder_pages(uuid, integer, integer) is
  'Fichário Digital (5223 → 5230): bolsos de até 4 páginas do fichário da coleção (próprio ou compartilhado) — mesmo conteúdo da 5223, com a carta de qualquer participante e as colunas present_collection_id/expected_collection_id. Não enumera; arquivada é legível.';

revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_pages(uuid, integer, integer) to authenticated;

-- 4. Cartas desta coleção fora dos bolsos --------------------------------------------
create function public.get_my_collection_binder_unplaced(
  p_collection_id uuid,
  p_limit         integer default 48,
  p_offset        integer default 0
)
returns table (
  collection_allocation_id uuid,
  physical_card_id         uuid,
  card_id                  uuid,
  card_variant_id          uuid,
  variant_type_id          uuid,
  card_name                text,
  collector_number         text,
  collector_total          integer,
  card_set_code            text,
  variant_label            text,
  language_code            text,
  image_path               text,
  total_count              integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_limit constant integer := 96;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_limit is null or p_offset is null
     or p_limit < 1 or p_limit > c_max_limit or p_offset < 0 or p_offset > 1000000 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  -- Sem fichário (próprio ou compartilhado) não há "fora do fichário".
  if not exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id)
     and not exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
    return;
  end if;

  return query
  with un as (
    select ca.id as allocation_id, ca.physical_card_id, ca.created_at
    from public.collection_allocation ca
    where ca.collection_id = p_collection_id
      and not exists (select 1 from public.collection_layout_slot_assignment a
                      where a.collection_allocation_id = ca.id)
  ),
  tot as (select count(*)::integer as n from un)
  select un.allocation_id,
         pc.id,
         c.id,
         cv.id,
         cv.variant_type_id,
         c.name::text,
         c.collector_number::text,
         c.collector_total,
         cs.code::text,
         nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')::text,
         l.code::text,
         img.storage_path::text,
         tot.n
  from un
  cross join tot
  join public.physical_card pc on pc.id = un.physical_card_id
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.card c           on c.id = cv.card_id
  join public.card_set cs      on cs.id = c.card_set_id
  left join public.language l  on l.id = pc.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = c.id and ast.is_primary and ast.is_active and ast.storage_path is not null
    order by (ast.language_id = pc.language_id) desc nulls last,
             (al.code = 'pt-BR') desc, (al.code = 'en') desc, al.language_order asc
    limit 1
  ) img on true
  order by cs.code, c.collector_order nulls last, c.collector_number, cv.variant_order, un.created_at, un.allocation_id
  limit p_limit offset p_offset;
end;
$$;

comment on function public.get_my_collection_binder_unplaced(uuid, integer, integer) is
  'Fichário Digital (5230, C-195): cartas desta coleção que ainda não ocupam bolso no fichário (próprio ou compartilhado), paginadas (≤ 96), com arte, número, acabamento e idioma, e total. Fonte para organizar manualmente. Não enumera.';

revoke all on function public.get_my_collection_binder_unplaced(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_unplaced(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_unplaced(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Reversão: drop das quatro funções e reaplicação, do begin ao commit, do
corpo canônico de database/schema/5223_create_get_my_collection_binder_functions.sql
(sem o bloco PRECHECK de inexistência). Fazer antes da reversão da 5229.

Como validar: harness 5851 (Seções 0, 2, 3, 5).
*/
