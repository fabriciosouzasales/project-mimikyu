/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5252 - Leituras do fichário pelo local físico
              get_my_collection_binder(uuid)                     — DROP + CREATE (+3 colunas)
              get_my_collection_binder_pages(uuid, int, int)     — DROP + CREATE (+2 colunas)
              get_my_collection_binder_unplaced(uuid, int, int, text, uuid) — NOVA sobrecarga (a 3-arg 5230 fica até a 5256)
              get_my_binder_participants(uuid)                   — CREATE OR REPLACE (mesmo contrato)
Versão......: 1.2 (2026-10-24, BINDER-PHYSICAL-LOCATION-FINAL-CORRECTIONS-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-24
              (Fase A, autorização expressa de Fabrício; ledger
              20261024121613 `5252_evolve_binder_reads_physical_location`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-binder-
              physical-location/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo (md5). LIVE_90 7/7 PASS.
              Ver LIVE-PHASE-A-2026-10-24.md da proposta.
v1.1 (expand/contract): a leitura antiga de disponíveis (3 argumentos, 5230)
      NÃO é removida aqui — o frontend atual continua funcionando igual
      durante a implantação; a nova tem os 4 parâmetros SEM DEFAULT (nunca
      ambígua). A antiga sai na 5256, depois do frontend novo.
v1.2: 5º parâmetro p_origin_collection_id (sem DEFAULT) — o recorte por
      coleção da reserva deixa de ser feito no navegador sobre a 1ª página.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

O que muda em cada leitura (o resto do corpo é o canônico 5230/5246,
conferido pelo static_check S6):
  Cabeçalho  own_filled_count e participantes contam pela alocação ATUAL do
             exemplar; own_unplaced_count = exemplares DESTA coleção guardados
             no fichário físico e sem bolso; novas colunas
             binder_storage_container_id, binder_storage_name e
             available_count (todas as origens).
  Páginas    a carta do bolso vem do exemplar (5248), de qualquer origem —
             antes uma carta de coleção não participante sumia da leitura;
             novas colunas present_collection_name e
             present_collection_lifecycle (origem; NULL = sem coleção).
  Disponíveis elegibilidade por local físico (README §2) + filtro de origem
             p_origin: ALL | THIS | OTHER_COLLECTIONS | NO_COLLECTION;
             p_origin_collection_id (opcional, NULL = sem recorte): só exemplares
             alocados àquela coleção — usado no bolso reservado por outra
             coleção; recorte, total e paginação no SERVIDOR (v1.2).
             ordem: primeiro as da coleção aberta, depois Set/número;
             colunas de origem; collection_allocation_id pode ser NULL.
  Participantes contagem por coleção pela alocação atual do exemplar.
Colunas novas só no FIM: o frontend atual lê por nome e ignora as novas.
Implantação (README §6): cabeçalho e páginas só GANHAM colunas no fim (o
frontend atual lê por nome); a leitura nova de disponíveis é outra
assinatura — o frontend atual não a vê. Nenhuma janela de incompatibilidade.
Segurança: todas SECURITY DEFINER, search_path '', fronteira de dono pela
coleção pedida e pelo inventário do usuário; EXECUTE só authenticated.
Dependências: 5223, 5230, 5246, 5247, 5248.
================================================================
*/

begin;

do $pre$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                   and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5252: aplique a 5248 antes';
  end if;
  if to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is null
     or to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)') is null
     or to_regprocedure('public.get_my_collection_binder(uuid)') is null
     or to_regprocedure('public.get_my_binder_participants(uuid)') is null then
    raise exception 'PRECHECK 5252: leituras 5230/5246 ausentes';
  end if;
  if to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)') is not null then
    raise exception 'PRECHECK 5252: leitura nova de disponíveis já existe';
  end if;
end;
$pre$;

drop function public.get_my_collection_binder_pages(uuid, integer, integer);
drop function public.get_my_collection_binder(uuid);

-- 1. Cabeçalho --------------------------------------------------------------------
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
  join_candidate_count         integer,
  binder_storage_container_id  uuid,
  binder_storage_name          text,
  available_count              integer
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
  v_bsc       uuid;
  v_bsc_name  text;
  v_avail     integer := 0;
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
    left join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
    left join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = v_layout;

    v_parts := 1 + (select count(*) from public.collection_layout_guest g where g.layout_id = v_layout)::integer;

    -- 5252: o fichário é um local físico (5247). Fora dos bolsos = guardado
    -- nele e sem posição. own_unplaced: desta coleção; available: qualquer
    -- origem (outra coleção, nenhuma ou arquivada — D1).
    select l.storage_container_id, sc.name::text into v_bsc, v_bsc_name
    from public.collection_layout l
    join public.storage_container sc on sc.id = l.storage_container_id
    where l.id = v_layout;

    select count(*)::integer,
           (count(*) filter (where ca.collection_id = p_collection_id))::integer
      into v_avail, v_own_unpl
    from public.physical_card pc
    join public.inventory i on i.id = pc.inventory_id and i.owner_user_id = v_uid
    left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.storage_container_id = v_bsc
      and not exists (select 1 from public.collection_layout_slot_assignment a
                      where a.physical_card_id = pc.id);
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
         v_cand,
         v_bsc,
         v_bsc_name,
         v_avail;
end;
$$;

comment on function public.get_my_collection_binder(uuid) is
  'Fichário Digital (5223 → 5230 → 5252): cabeçalho da coleção — fichário próprio ou compartilhado, proprietária, participantes, contagens; local físico do fichário e cartas guardadas nele fora dos bolsos (desta coleção e de todas as origens). Não enumera; arquivada é legível.';
revoke all on function public.get_my_collection_binder(uuid) from public;
revoke all on function public.get_my_collection_binder(uuid) from anon;
grant execute on function public.get_my_collection_binder(uuid) to authenticated;

-- 2. Páginas ----------------------------------------------------------------------
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
  expected_collection_id       uuid,
  present_collection_name      text,
  present_collection_lifecycle text
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
    case when e.slot_id is null then null else coalesce(e.collection_id, v_owner) end,
    pcol.name::text,
    pcol.lifecycle_status::text
  from sl
  left join public.collection_layout_slot_expected_content e on e.slot_id = sl.id
  left join public.card ec              on ec.id = e.card_id
  left join public.card_set ecs         on ecs.id = ec.card_set_id
  left join public.card_variant_type evt
         on evt.id = coalesce(e.expected_variant_type_id,
                              (select v.variant_type_id from public.card_variant v where v.id = e.card_variant_id))
  left join public.collection_layout_slot_assignment a on a.slot_id = sl.id
  -- 5252: a carta do bolso vem do exemplar (5248); a origem é a alocação
  -- ATUAL do exemplar, de qualquer coleção (ou nenhuma).
  left join public.physical_card pc     on pc.id = a.physical_card_id
  left join public.collection_allocation ca on ca.physical_card_id = pc.id
  left join public.collection pcol      on pcol.id = ca.collection_id
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
  'Fichário Digital (5223 → 5230 → 5252): bolsos de até 4 páginas; a carta vem do exemplar posicionado (qualquer origem) e a origem é a alocação atual dele (present_collection_*; NULL = sem coleção). Não enumera; arquivada é legível.';
revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_pages(uuid, integer, integer) to authenticated;

-- 3. Cartas disponíveis -------------------------------------------------------------
create function public.get_my_collection_binder_unplaced(
  p_collection_id uuid,
  p_limit         integer,
  p_offset        integer,
  p_origin        text,     -- ALL | THIS | OTHER_COLLECTIONS | NO_COLLECTION (sem DEFAULT: não colide com a 5230)
  p_origin_collection_id uuid  -- NULL = sem recorte; senão só exemplares alocados a esta coleção
)
returns table (
  collection_allocation_id uuid,          -- NULL quando o exemplar não tem coleção
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
  total_count              integer,
  origin_collection_id     uuid,
  origin_collection_name   text,
  origin_lifecycle_status  text,
  origin_kind              text           -- THIS | OTHER_COLLECTION | NO_COLLECTION
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_limit constant integer := 96;
  v_uid       uuid := auth.uid();
  v_layout    uuid;
  v_container uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_limit is null or p_offset is null
     or p_limit < 1 or p_limit > c_max_limit or p_offset < 0 or p_offset > 1000000
     or p_origin is null or p_origin not in ('ALL', 'THIS', 'OTHER_COLLECTIONS', 'NO_COLLECTION') then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  -- Sem fichário (próprio ou compartilhado) não há "fora do fichário".
  if v_layout is null then
    return;
  end if;
  select l.storage_container_id into v_container from public.collection_layout l where l.id = v_layout;

  return query
  with un as (
    -- Elegível (README §2): do usuário, guardado no fichário físico, sem bolso.
    select pc.id as pc_id, pc.created_at, ca.id as alloc_id, ca.collection_id as col_id
    from public.physical_card pc
    join public.inventory i on i.id = pc.inventory_id and i.owner_user_id = v_uid
    left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.storage_container_id = v_container
      and not exists (select 1 from public.collection_layout_slot_assignment a
                      where a.physical_card_id = pc.id)
      and case p_origin
            when 'THIS' then ca.collection_id = p_collection_id
            when 'OTHER_COLLECTIONS' then ca.collection_id is not null and ca.collection_id <> p_collection_id
            when 'NO_COLLECTION' then ca.id is null
            else true
          end
      and (p_origin_collection_id is null or ca.collection_id = p_origin_collection_id)
  ),
  tot as (select count(*)::integer as n from un)
  select un.alloc_id,
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
         tot.n,
         un.col_id,
         oc.name::text,
         oc.lifecycle_status::text,
         case when un.col_id is null then 'NO_COLLECTION'
              when un.col_id = p_collection_id then 'THIS'
              else 'OTHER_COLLECTION' end
  from un
  cross join tot
  join public.physical_card pc on pc.id = un.pc_id
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.card c           on c.id = cv.card_id
  join public.card_set cs      on cs.id = c.card_set_id
  left join public.collection oc on oc.id = un.col_id
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
  order by (un.col_id = p_collection_id) desc nulls last,
           cs.code, c.collector_order nulls last, c.collector_number, cv.variant_order,
           un.created_at, un.pc_id
  limit p_limit offset p_offset;
end;
$$;

comment on function public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid) is
  'Fichário Digital (5252): exemplares do usuário GUARDADOS no fichário físico e sem bolso, de qualquer origem (coleção aberta, outra coleção, nenhuma, arquivada), filtráveis por origem e, opcionalmente, por coleção de origem (recorte, total e paginação no servidor), paginados (≤ 96), com total. Não enumera.';
revoke all on function public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid) from public;
revoke all on function public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid) from anon;
grant execute on function public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid) to authenticated;

-- 4. Participantes ------------------------------------------------------------------
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
            join public.collection_allocation ca            on ca.physical_card_id = a.physical_card_id
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

notify pgrst, 'reload schema';

commit;

/*
Como validar (só leitura):
select p.oid::regprocedure, p.prosecdef, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('get_my_collection_binder', 'get_my_collection_binder_pages',
  'get_my_collection_binder_unplaced', 'get_my_binder_participants');
*/
