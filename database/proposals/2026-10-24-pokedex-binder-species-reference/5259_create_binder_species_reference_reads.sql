/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5259 - Referências de espécie: leituras
              get_my_binder_species_reference_state(uuid)                 — estado leve do fichário
              get_my_collection_binder_species_references(uuid, int, int) — até 4 páginas
Versão......: 1.0 (2026-10-24, POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depende da 5257 (e da 5234 para o
              helper binder_slot_image_resolve_layout).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Regras:
  - Fronteira: coleção do usuário (owner-scoped) antes de qualquer outra
    tabela; resolve o fichário próprio OU convidado (helper 5234, mesma regra
    das leituras de imagens/regiões). Alheia/inexistente → P0002.
  - Só valem referências cuja collection_id é a PROPRIETÁRIA ATUAL do
    fichário (transferência 5254 oculta as antigas, sem apagar).
  - Estado: has_binder, can_manage (esta coleção é a proprietária, de
    Pokédex e ativa — só ela aplica/remove), is_pokedex_owner (a proprietária
    é de Pokédex: o fichário pode ter referências), reference_count e
    references_visible (preferência; sem linha = true). Custo: PK/UNIQUE +
    contagem por índice de layout. Lida no servidor junto com o cabeçalho.
  - Página: ≤ 4 páginas por chamada (mesmo teto e mesmo lote das leituras
    5252/5234/5241); ≤ 400 linhas no pior caso (4 × 10 × 10), 64 no F002.
    Devolve as referências mesmo com a exibição desligada: alternar
    mostrar/ocultar não exige nova leitura (payload pequeno).
  - Arte: pokemon_species_artwork IMPORTED com display_storage_path (a mesma
    fonte de species_artwork_path na 5204/5211; uq_pokemon_species_artwork_species
    garante no máximo uma por espécie). Sem arte → artwork_path NULL (a
    interface mostra só o número).
  - Nada é gravado.
Dependências: 5257, 5234.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_species_reference') is null then
    raise exception 'PRECHECK 5259: aplique a 5257 antes';
  end if;
  if to_regprocedure('public.binder_slot_image_resolve_layout(uuid)') is null then
    raise exception 'PRECHECK 5259: 5234 ausente';
  end if;
  if to_regprocedure('public.get_my_collection_binder_species_references(uuid, integer, integer)') is not null then
    raise exception 'PRECHECK 5259: funções já existem';
  end if;
end;
$pre$;

-- 1. Estado leve -------------------------------------------------------------------------
create function public.get_my_binder_species_reference_state(p_collection_id uuid)
returns table (
  layout_id          uuid,
  has_binder         boolean,
  is_pokedex_owner   boolean,
  can_manage         boolean,
  reference_count    integer,
  references_visible boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_layout uuid;
  v_owner  uuid;
  v_status text;
  v_dex    boolean;
begin
  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);
  if v_layout is null then
    layout_id := null; has_binder := false; is_pokedex_owner := false;
    can_manage := false; reference_count := 0; references_visible := true;
    return next;
    return;
  end if;

  select l.collection_id, c.lifecycle_status::text into v_owner, v_status
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = v_layout;

  v_dex := exists (
    select 1 from public.collection c
    join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
    join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
    where c.id = v_owner and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION');

  layout_id        := v_layout;
  has_binder       := true;
  is_pokedex_owner := v_dex;
  can_manage       := v_dex and v_owner = p_collection_id and v_status = 'ACTIVE';
  select count(*)::integer into reference_count
  from public.collection_layout_slot_species_reference r
  where r.layout_id = v_layout and r.collection_id = v_owner;
  select coalesce((select st.references_visible
                   from public.collection_layout_species_reference_setting st
                   where st.layout_id = v_layout), true)
    into references_visible;
  return next;
end;
$$;

comment on function public.get_my_binder_species_reference_state(uuid) is
  'POKEDEX-BINDER-SPECIES-REFERENCE (5259): estado leve das referências de espécie do fichário (próprio ou convidado): proprietária é Pokédex, esta coleção pode gerenciar, quantidade e exibição. Não grava nada.';

revoke all on function public.get_my_binder_species_reference_state(uuid) from public, anon;
grant execute on function public.get_my_binder_species_reference_state(uuid) to authenticated;

-- 2. Referências por páginas -------------------------------------------------------------
create function public.get_my_collection_binder_species_references(
  p_collection_id uuid,
  p_first_page    integer,
  p_page_count    integer
)
returns table (
  page_number     integer,
  slot_id         uuid,
  national_number integer,
  species_name    text,
  artwork_path    text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_pages constant integer := 4;
  v_layout uuid;
begin
  if p_first_page is null or p_page_count is null
     or p_first_page < 1 or p_first_page > 100000
     or p_page_count < 1 or p_page_count > c_max_pages then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);
  if v_layout is null then
    return;
  end if;

  return query
  select pg.page_number, r.slot_id, pp.position_number, sp.canonical_name::text,
         aw.display_storage_path::text
  from public.collection_layout_page pg
  join public.collection_layout_slot s on s.page_id = pg.id
  join public.collection_layout_slot_species_reference r on r.slot_id = s.id
  join public.collection_layout l on l.id = r.layout_id and l.collection_id = r.collection_id
  join public.pokedex_position pp on pp.id = r.pokedex_position_id
  join public.pokemon_species sp on sp.id = pp.species_id
  left join public.pokemon_species_artwork aw
    on aw.pokemon_species_id = sp.id and aw.status = 'IMPORTED' and aw.display_storage_path is not null
  where pg.layout_id = v_layout
    and pg.page_number between p_first_page and p_first_page + p_page_count - 1
  order by pg.page_number, s.row_index, s.column_index;
end;
$$;

comment on function public.get_my_collection_binder_species_references(uuid, integer, integer) is
  'POKEDEX-BINDER-SPECIES-REFERENCE (5259): referências de espécie de até 4 páginas do fichário (próprio ou convidado) — bolso, número nacional, nome e caminho da arte oficial. Só referências da proprietária atual. Não grava nada.';

revoke all on function public.get_my_collection_binder_species_references(uuid, integer, integer) from public, anon;
grant execute on function public.get_my_collection_binder_species_references(uuid, integer, integer) to authenticated;

commit;
