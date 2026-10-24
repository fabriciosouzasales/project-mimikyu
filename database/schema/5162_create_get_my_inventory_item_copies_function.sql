/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5162 - get_my_inventory_item_copies(): detalhe de um
              grupo de Meu acervo com seus exemplares individuais
              (MY-INVENTORY-IMPLEMENTATION-01, Etapa A)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17
              (MY-INVENTORY-LIVE-DEPLOYMENT-01); validado pelo 5827 (52/52 PASS)
              SUPERADA em 2026-10-24 pela 5262 (mesma assinatura + colunas
              variant_type_code/rarity_code; ledger 20261024185943) — definição
              vigente: database/schema/5262_evolve_get_my_inventory_item_copies_finish_codes.sql.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16

Descrição...:
  get_my_inventory_item_copies(p_card_variant_id uuid, p_language_code text)

Uma linha por EXEMPLAR (Physical Card) do usuário da sessão naquele
grupo Card Variant + idioma, na ordem de registro (created_at, id).
As colunas de cabeçalho (carta, Set, variante, imagem) se repetem em
cada linha — uma única chamada abre o painel de detalhe, mesmo
quando o grupo não está na página atual da galeria (deep link).

Por exemplar:
  physical_card_id, copy_number (1..N), added_at,
  collection_id/collection_name (NULL = "Sem coleção"),
  storage_name (NULL = "Sem localização definida" — N25/NS-13: a
  leitura nunca infere local; mostra só o que está gravado).

Grupo inexistente ou de outro usuário → zero linhas (mesma resposta,
não enumera). Limite defensivo: 500 exemplares por grupo (VR não
chega perto; acima disso a interface mostra os 500 primeiros e o
total real em copies_total).

Segurança: SECURITY DEFINER, STABLE, search_path '', auth.uid()
obrigatório (28000), exemplares filtrados por inventory do usuário,
coleção e local reafirmados por dono. EXECUTE só para authenticated.
Erros (22023): INVALID_ITEM (parâmetro nulo).

Como validar: Query 5827.
================================================================
*/

begin;

create or replace function public.get_my_inventory_item_copies(
  p_card_variant_id uuid,
  p_language_code   text
)
returns table (
  card_variant_id    uuid,
  language_code      text,
  language_name      text,
  card_name          text,
  collector_number   text,
  collector_total    integer,
  card_set_code      text,
  card_set_name      text,
  is_default_variant boolean,
  variant_label      text,
  image_path         text,
  copies_total       integer,
  physical_card_id   uuid,
  copy_number        integer,
  added_at           timestamptz,
  collection_id      uuid,
  collection_name    text,
  storage_name       text
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
  v_language  uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_variant_id is null or nullif(btrim(p_language_code), '') is null then
    raise exception 'INVALID_ITEM' using errcode = '22023';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  select l.id into v_language
  from public.language l
  where l.code = p_language_code;

  if v_inventory is null or v_language is null then
    return;
  end if;

  return query
  with mine as (
    select pc.id, pc.created_at, pc.storage_container_id,
           (row_number() over (order by pc.created_at, pc.id))::integer as num,
           (count(*) over ())::integer as total
    from public.physical_card pc
    where pc.inventory_id = v_inventory
      and pc.card_variant_id = p_card_variant_id
      and pc.language_id = v_language
  ),
  head as (
    select cv.id as variant_id, cv.card_id, cv.is_default,
           c.name::text as card_name, c.collector_number::text as number,
           c.collector_total as total_in_set,
           cs.code::text as set_code, cs.name::text as set_name,
           l.code as lang_code, l.name as lang_name,
           nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text as label
    from public.card_variant cv
    join public.card c       on c.id = cv.card_id
    join public.card_set cs  on cs.id = c.card_set_id
    join public.language l   on l.id = v_language
    left join public.card_variant_type vt            on vt.id = cv.variant_type_id
    left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
    left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
    where cv.id = p_card_variant_id
      and exists (select 1 from mine)
  )
  select
    h.variant_id, h.lang_code, h.lang_name, h.card_name, h.number,
    h.total_in_set, h.set_code, h.set_name, h.is_default, h.label,
    img.storage_path,
    m.total,
    m.id, m.num, m.created_at,
    co.id, co.name,
    sc.name
  from head h
  cross join mine m
  left join public.collection_allocation ca on ca.physical_card_id = m.id
  left join public.collection co           on co.id = ca.collection_id
                                          and co.owner_user_id = v_user
  left join public.storage_container sc    on sc.id = m.storage_container_id
                                          and sc.inventory_id = v_inventory
  left join lateral (
    select ca2.storage_path
    from public.card_asset ca2
    join public.card_asset_type cat on cat.id = ca2.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al on al.id = ca2.language_id
    where ca2.card_id = h.card_id
      and ca2.is_primary
      and ca2.is_active
      and ca2.storage_path is not null
    order by (ca2.language_id = v_language) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  where m.num <= 500
  order by m.num;
end;
$$;

comment on function public.get_my_inventory_item_copies(uuid, text) is
  'Meu acervo (Query 5162): detalhe de um grupo Card Variant + idioma do usuário da sessão — cabeçalho da carta e um registro por exemplar (coleção e local gravados; nunca inferidos). Grupo alheio ou inexistente → zero linhas.';

revoke all on function public.get_my_inventory_item_copies(uuid, text) from public;
revoke all on function public.get_my_inventory_item_copies(uuid, text) from anon;
grant execute on function public.get_my_inventory_item_copies(uuid, text) to authenticated;

commit;
