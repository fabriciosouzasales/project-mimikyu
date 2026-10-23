/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5223 - Fichário Digital (P2-A1): leitura segura e paginada
              get_my_collection_binder(uuid)              — cabeçalho
              get_my_collection_binder_pages(uuid, int, int) — bolsos
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: can_create exclui tipo
              UNKNOWN; ordem do pacote com a 5227)
Status......: PROPOSTA — NÃO EXECUTADA. Aguarda auditoria independente e
              autorização expressa de Fabrício. Não aplicar no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22 (P2-A1-PROPOSAL-01)

Dependência: 5225 (coluna expected_variant_type_id). Ordem do pacote:
5225 → 5223 → 5224 → 5226 → 5227 → 5228.

Por que existe (P2-A1 DISCOVERY-01 §2): o Fichário Digital precisa mostrar
arte, nome, número, acabamento e idioma de cada bolso. A estrutura do
layout (5105–5121) é legível pelo dono via RLS, mas o catálogo (card,
card_variant, card_set, card_asset, language) é admin-only (Query 274,
ADR-022). Nenhuma leitura definer existente devolve "bolso → exemplar →
carta" (5162 é por item; 5169/5189/5204 por posição de completude; 5220
agrupa por variante+idioma, sem allocation nem bolso, ≤ 96 por página).
Compor no cliente exigiria varrer a coleção inteira a cada abertura.

──────────────────────────────────────────────────────────────────────
1. get_my_collection_binder(p_collection_id uuid) → 1 linha (cabeçalho)
   collection_id                uuid
   collection_name              text
   collection_kind              text   SET | MASTER_SET | POKEDEX | FREE
   completion_policy            text   STANDARD_SET | MASTER_SET |
                                       REFERENCE_POSITION | NONE
   lifecycle_status             text   ACTIVE | ARCHIVED
   has_binder                   boolean
   layout_id                    uuid   (null sem fichário)
   grid_columns                 integer  convenção visual colunas × linhas
   grid_rows                    integer
   capacity_per_page            integer  colunas × linhas (derivada)
   page_count                   integer
   slot_count                   integer
   filled_count                 integer  bolsos com exemplar
   reserved_count               integer  bolsos com conteúdo planejado
   reserved_empty_count         integer  reservados e vazios (faltantes)
   is_editable                  boolean  has_binder e ACTIVE (5122 recusa
                                         edição em coleção arquivada)
   can_create                   boolean  sem fichário, ACTIVE e local padrão
                                         do tipo BINDER (D1; a 5224
                                         revalida no servidor)
   default_storage_container_id uuid
   default_storage_name         text
   default_storage_kind_code    text
   Coleção inexistente ou de outro usuário → P0002 COLLECTION_NOT_FOUND
   (mesma resposta: não enumera). Arquivada é LEGÍVEL (somente leitura).

2. get_my_collection_binder_pages(p_collection_id uuid,
                                   p_first_page  integer,
                                   p_page_count  integer)
   Bolsos das páginas [p_first_page, p_first_page + p_page_count − 1],
   1 ≤ p_page_count ≤ 4 (página atual + vizinhas para pré-carregamento;
   D7: uma por vez no celular, duas no desktop). Página inexistente →
   nenhuma linha (sem erro). Sem fichário → nenhuma linha.
   Ordem: page_number, row_index, column_index. Uma linha por bolso:
     page_id, page_number, slot_id, row_index, column_index, locked,
     region_id                       região mesclada que cobre o bolso
                                     (C-46; null se nenhuma)
     slot_state                      ver §3
     -- conteúdo planejado (reserva)
     expected_card_id, expected_card_variant_id, expected_variant_type_id,
     expected_variant_type_code, expected_variant_type_name,
     expected_card_name, expected_collector_number, expected_collector_total,
     expected_card_set_code, expected_image_path
     -- exemplar atribuído
     assignment_id, collection_allocation_id, physical_card_id,
     present_card_id, present_card_variant_id, present_variant_type_id,
     present_variant_type_code, present_variant_label (acabamento ·
     impressão · contexto, mesma composição da 5220), present_is_default_variant,
     present_language_code, present_card_name, present_collector_number,
     present_collector_total, present_card_set_code, present_image_path,
     present_storage_container_id    D6: o detalhe compara com
                                     default_storage_container_id do
                                     cabeçalho; a grade NÃO mostra isso.

3. slot_state (derivado no servidor; C-42 — divergência nunca bloqueia):
   EMPTY              sem reserva e sem exemplar
   RESERVED_EMPTY     reserva sem exemplar (carta faltante)
   OCCUPIED_UNPLANNED exemplar sem reserva (adicionais, coleção livre,
                      Pokédex, bolso para onde o usuário moveu a carta)
   OCCUPIED_MATCH     exemplar compatível com a reserva, na granularidade
                      da reserva:
                        carta            → mesma carta;
                        carta+acabamento → mesma carta E mesmo acabamento;
                        carta+variante   → mesma variante.
                      Mesma carta com outro acabamento NÃO é MATCH.
   OCCUPIED_MISMATCH  exemplar e reserva incompatíveis

Imagem: mesma regra canônica de 5169/5220 — card_asset CARD_FRONT
primário e ativo da carta, preferindo o idioma do exemplar, depois pt-BR,
en e language_order. Para a reserva (sem exemplar): pt-BR, en,
language_order.

Segurança: SECURITY DEFINER, search_path vazio, objetos qualificados;
auth.uid() obrigatório (28000); o filtro de dono vem ANTES de qualquer
outra tabela; toda junção parte do layout da coleção resolvida (nada de
outra coleção entra: a alocação é revalidada contra p_collection_id);
EXECUTE só authenticated. Nenhum dado de outro usuário é exposto.

Desempenho: NÃO MEDIDO. Custo proporcional aos bolsos pedidos (≤ 4 ×
100), não ao tamanho da coleção: uq_collection_layout_page_number
(layout_id, page_number), uq_collection_layout_slot_position (page_id, …),
UNIQUE(slot_id) da posição, PK slot_id da reserva, PKs do catálogo e
uq_card_asset (card_id, asset_type_id, asset_order). Nenhum índice novo
proposto; o harness 5850 (Seção P) mede e registra o plano.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.get_my_collection_binder(uuid)') is not null
     or to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)') is not null then
    raise exception 'PRECHECK 5223: funções já existem';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public'
                   and table_name = 'collection_layout_slot_expected_content'
                   and column_name = 'expected_variant_type_id') then
    raise exception 'PRECHECK 5223: aplique a 5225 antes (expected_variant_type_id ausente)';
  end if;
  if to_regclass('public.collection_layout_region') is null
     or to_regclass('public.storage_container') is null then
    raise exception 'PRECHECK 5223: tabelas de base ausentes (5119/5020)';
  end if;
end;
$pre$;

-- 1. Cabeçalho ------------------------------------------------------------------
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
  default_storage_kind_code    text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_name    text;
  v_mode    text;
  v_policy  text;
  v_status  text;
  v_default uuid;
  v_kind    text;
  v_layout  uuid;
  v_cols    integer;
  v_rows    integer;
  v_pages   integer := 0;
  v_slots   integer := 0;
  v_filled  integer := 0;
  v_resv    integer := 0;
  v_resv_e  integer := 0;
  v_sc_name text;
  v_sc_kind text;
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

  select l.id, l.grid_columns, l.grid_rows into v_layout, v_cols, v_rows
  from public.collection_layout l
  where l.collection_id = p_collection_id;

  if v_layout is not null then
    select count(*)::integer into v_pages
    from public.collection_layout_page p where p.layout_id = v_layout;

    select count(*)::integer,
           count(a.id)::integer,
           count(e.slot_id)::integer,
           count(e.slot_id) filter (where a.id is null)::integer
      into v_slots, v_filled, v_resv, v_resv_e
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    left join public.collection_layout_slot_assignment a on a.slot_id = s.id
    left join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = v_layout;
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
         v_layout is not null and v_status = 'ACTIVE',
         v_layout is null and v_status = 'ACTIVE' and v_sc_kind = 'BINDER' and v_kind <> 'UNKNOWN',
         v_default,
         v_sc_name,
         v_sc_kind;
end;
$$;

comment on function public.get_my_collection_binder(uuid) is
  'Fichário Digital (Query 5223): cabeçalho da coleção do usuário da sessão — tipo, política, estado, existência do fichário, grade (colunas × linhas), contagens de bolsos (ocupados, reservados, reservados vazios), editável?, pode criar? (D1: sem fichário, ACTIVE e local padrão BINDER; a 5224 revalida) e local padrão (D6). Exige auth.uid(); não enumera coleção de outro usuário; coleção arquivada é legível.';

revoke all on function public.get_my_collection_binder(uuid) from public;
revoke all on function public.get_my_collection_binder(uuid) from anon;
grant execute on function public.get_my_collection_binder(uuid) to authenticated;

-- 2. Bolsos paginados --------------------------------------------------------------
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
  present_storage_container_id uuid
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

  -- Fronteira de autorização antes de qualquer outra tabela.
  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l
  where l.collection_id = p_collection_id;
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
    pc.storage_container_id
  from sl
  left join public.collection_layout_slot_expected_content e on e.slot_id = sl.id
  left join public.card ec              on ec.id = e.card_id
  left join public.card_set ecs         on ecs.id = ec.card_set_id
  left join public.card_variant_type evt
         on evt.id = coalesce(e.expected_variant_type_id,
                              (select v.variant_type_id from public.card_variant v where v.id = e.card_variant_id))
  left join public.collection_layout_slot_assignment a on a.slot_id = sl.id
  left join public.collection_allocation ca
         on ca.id = a.collection_allocation_id and ca.collection_id = p_collection_id
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
  'Fichário Digital (Query 5223): bolsos de até 4 páginas do fichário da coleção do usuário da sessão — posição, fixação, região, estado derivado (EMPTY/RESERVED_EMPTY/OCCUPIED_UNPLANNED/OCCUPIED_MATCH/OCCUPIED_MISMATCH, respeitando a granularidade da reserva: carta, carta+acabamento ou variante), reserva (carta/acabamento/variante, nome, número, arte) e exemplar (carta, variante, acabamento, idioma, arte, local físico para o detalhe — D6). Exige auth.uid(); não enumera; arquivada é legível.';

revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_pages(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_pages(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
