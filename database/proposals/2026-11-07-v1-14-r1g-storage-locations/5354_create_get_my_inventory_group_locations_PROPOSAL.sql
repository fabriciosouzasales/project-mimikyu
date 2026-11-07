/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5354 - get_my_inventory_group_locations(uuid[]): localização física dos
              exemplares do titular, por grupo variante + idioma (V1-14 R1-G)
Versão......: 0.1
Status......: PROPOSTO — NÃO EXECUTADO (R1-G PERFORMANCE & LOCATION DESIGN APPROVAL-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-07

Objetivo
  Uma leitura em LOTE (sem N+1) que devolve, para cada grupo variante + idioma do acervo do
  titular dentre as variantes pedidas, a distribuição de TODOS os exemplares por local de
  armazenamento (nome e tipo do recipiente, quantidade) e as páginas do fichário quando o
  exemplar está posicionado no fichário digital vinculado àquele recipiente. Nenhuma unidade é
  rotulada como "adicional": a distribuição é só para localização.

Contrato
  get_my_inventory_group_locations(p_card_variant_ids uuid[])
  RETURNS TABLE(card_variant_id uuid, language_code text, copies integer, locations jsonb)
    locations = [{ "storage_container_id": uuid|null, "name": text|null, "kind_code": text|null,
                   "kind_label": text|null, "copies": int, "pages": int[] }]
    ordenados por copies desc, nome, id (null = "Sem local definido", sempre por último).
  - Uma linha por grupo (variante + idioma): no máximo cardinalidade(ids) × idiomas — nunca uma
    linha por local (evita o corte silencioso de 1.000 linhas do PostgREST).
  - copies = Σ locations[].copies = exemplares do grupo (o chamador concilia com a 5159).
  - Variantes de terceiros ou inexistentes: simplesmente não aparecem (não enumera).

Segurança
  SECURITY DEFINER — justificativa: (1) `public.language` só é legível por administrador
  (policy catalog_admin_select), e o código do idioma é parte da chave do grupo, como na 5159;
  (2) a cadeia de posicionamento (slot_assignment → slot → page → layout) teria 4 policies EXISTS
  aninhadas por linha em SECURITY INVOKER. O isolamento é explícito e único: o inventário do
  titular é resolvido por auth.uid() e TODAS as junções partem de physical_card desse
  inventário; recipiente e layout são exigidos do MESMO inventário/dono. search_path '',
  objetos qualificados, STABLE, EXECUTE só para authenticated (revogado de PUBLIC/anon).
  Entrada: não nula, 1 dimensão, 1..500 ids (22023); sem sessão → 28000. Somente leitura.

Desempenho (medido em 2026-11-07, leitura do acervo inteiro do titular, 2.955 exemplares,
  1.302 variantes): ~130 ms de execução (plano em hash joins; índices existentes:
  ix_physical_card_inventory_variant, uq_collection_layout_slot_assignment_physical_card,
  uq_collection_layout_storage_container). O relatório chama só com as variantes repetidas
  (448 hoje → 1 chamada de até 500 ids), em paralelo com os preços.
================================================================
*/

create or replace function public.get_my_inventory_group_locations(p_card_variant_ids uuid[])
returns table (
  card_variant_id uuid,
  language_code   text,
  copies          integer,
  locations       jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_inventory uuid;
  v_count integer;
begin
  if v_user is null then
    raise exception 'INVENTORY_LOCATIONS_REQUIRES_AUTHENTICATION' using errcode = '28000';
  end if;
  if p_card_variant_ids is null then
    raise exception 'INVENTORY_LOCATIONS_EMPTY_INPUT' using errcode = '22023';
  end if;
  v_count := cardinality(p_card_variant_ids);
  if v_count = 0 then
    raise exception 'INVENTORY_LOCATIONS_EMPTY_INPUT' using errcode = '22023';
  end if;
  if array_ndims(p_card_variant_ids) <> 1 then
    raise exception 'INVENTORY_LOCATIONS_INVALID_PAYLOAD_SHAPE' using errcode = '22023';
  end if;
  if v_count > 500 then
    raise exception 'INVENTORY_LOCATIONS_TOO_MANY_IDS' using errcode = '22023';
  end if;

  select i.id into v_inventory from public.inventory i where i.owner_user_id = v_user;
  if v_inventory is null then
    return; -- titular sem acervo: nenhuma linha
  end if;

  return query
  with ids as (
    select distinct x as id from unnest(p_card_variant_ids) as x where x is not null
  ),
  cards as (
    select pc.id, pc.card_variant_id, l.code as language_code, pc.storage_container_id
    from public.physical_card pc
    join ids on ids.id = pc.card_variant_id
    join public.language l on l.id = pc.language_id
    where pc.inventory_id = v_inventory
  ),
  placed as (
    -- Página do fichário: só quando o exemplar está num slot do layout vinculado ao MESMO
    -- recipiente físico do exemplar (e o recipiente é do mesmo inventário).
    select c.id as physical_card_id, p.page_number
    from cards c
    join public.collection_layout_slot_assignment a on a.physical_card_id = c.id
    join public.collection_layout_slot s on s.id = a.slot_id
    join public.collection_layout_page p on p.id = s.page_id
    join public.collection_layout lay on lay.id = p.layout_id and lay.storage_container_id = c.storage_container_id
  ),
  per_place as (
    select c.card_variant_id, c.language_code, c.storage_container_id,
           sc.name, sc.kind_code, k.label as kind_label,
           count(*)::integer as copies,
           coalesce(array_agg(distinct pl.page_number order by pl.page_number) filter (where pl.page_number is not null), '{}') as pages
    from cards c
    left join public.storage_container sc on sc.id = c.storage_container_id and sc.inventory_id = v_inventory
    left join public.storage_container_kind k on k.code = sc.kind_code
    left join placed pl on pl.physical_card_id = c.id
    group by c.card_variant_id, c.language_code, c.storage_container_id, sc.name, sc.kind_code, k.label
  )
  select pp.card_variant_id, pp.language_code, sum(pp.copies)::integer,
         jsonb_agg(jsonb_build_object(
           'storage_container_id', pp.storage_container_id, 'name', pp.name, 'kind_code', pp.kind_code,
           'kind_label', pp.kind_label, 'copies', pp.copies, 'pages', to_jsonb(pp.pages))
           order by (pp.storage_container_id is null), pp.copies desc, pp.name, pp.storage_container_id)
  from per_place pp
  group by pp.card_variant_id, pp.language_code;
end;
$$;

revoke all on function public.get_my_inventory_group_locations(uuid[]) from public;
revoke all on function public.get_my_inventory_group_locations(uuid[]) from anon;
grant execute on function public.get_my_inventory_group_locations(uuid[]) to authenticated;

comment on function public.get_my_inventory_group_locations(uuid[]) is
  'V1-14 R1-G (Query 5354): localização física dos exemplares do titular por grupo variante + idioma (recipiente, quantidade, páginas do fichário vinculado). Somente leitura; titular por auth.uid(); 1..500 variantes; uma linha por grupo.';
