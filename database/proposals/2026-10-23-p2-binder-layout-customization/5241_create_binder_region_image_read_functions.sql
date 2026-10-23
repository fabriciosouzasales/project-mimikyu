/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5241 - Create Binder Region Image Read Function
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23 (P2-BINDER-LAYOUT-CUSTOMIZATION-IMPLEMENTATION-PROPOSAL-01)
Descrição...:
Leitura das mesclagens com imagem das páginas visíveis, no mesmo contrato
de get_my_collection_binder_slot_images (5234): coleção do usuário
(proprietária ou convidada), no máximo 4 páginas por chamada, nunca
enumera fichário alheio (devolve vazio). O cliente assina as URLs
(1 h, bucket privado) como já faz com os bolsos.
Dependências: 5234 (binder_slot_image_resolve_layout), 5239.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_region_image') is null
     or to_regprocedure('public.binder_slot_image_resolve_layout(uuid)') is null then
    raise exception 'PRECHECK 5241: aplique 5234 e 5239 antes';
  end if;
end;
$pre$;

create function public.get_my_collection_binder_region_images(
  p_collection_id uuid,
  p_first_page    integer,
  p_page_count    integer
)
returns table (
  region_id    uuid,
  page_number  integer,
  top_row      integer,
  left_column  integer,
  height       integer,
  width        integer,
  storage_path text,
  focal_x      smallint,
  focal_y      smallint,
  updated_at   timestamptz
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
  select rg.id, p.page_number, rg.top_row, rg.left_column, rg.height, rg.width,
         ri.storage_path, ri.focal_x, ri.focal_y, ri.updated_at
  from public.collection_layout_page p
  join public.collection_layout_region rg       on rg.page_id = p.id
  join public.collection_layout_region_image ri on ri.region_id = rg.id
  where p.layout_id = v_layout
    and p.page_number between p_first_page and p_first_page + p_page_count - 1
  order by p.page_number, rg.top_row, rg.left_column;
end;
$$;

comment on function public.get_my_collection_binder_region_images(uuid, integer, integer) is
  'Fichário Digital (5241): mesclagens com imagem das páginas pedidas (até 4), para a coleção proprietária ou convidada. Nunca enumera fichário alheio.';

revoke all on function public.get_my_collection_binder_region_images(uuid, integer, integer) from public, anon;
grant execute on function public.get_my_collection_binder_region_images(uuid, integer, integer) to authenticated;

commit;
