/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5159 - get_my_inventory_items(): galeria paginada de
              Meu acervo (MY-INVENTORY-IMPLEMENTATION-01, Etapa A)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17
              (MY-INVENTORY-LIVE-DEPLOYMENT-01); validado pelo 5827 (52/52 PASS)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16

Descrição...:
Leitura customer-facing, somente do acervo do usuário da sessão.
Cada linha é um GRUPO VISUAL = Card Variant + idioma (decisão de UX
aprovada: cópias agrupadas por Carta + variante + idioma). O grupo
não é entidade: cada exemplar continua sendo um Physical Card
(C-47/C-48/LDM-23 inalterados).

Contrato:
  get_my_inventory_items(
    p_search               text    default null,  -- nome ou número (025, 25, 25/094)
    p_card_set_code        text    default null,  -- card_set.code
    p_language_code        text    default null,  -- language.code
    p_collection_id        uuid    default null,  -- só exemplares nessa coleção do usuário
    p_without_collection   boolean default false, -- só exemplares sem coleção
    p_sort                 text    default 'RECENT', -- 'RECENT' | 'SET_NUMBER'
    p_limit                integer default 48,    -- 1..96
    p_offset               integer default 0      -- 0..100000
  )
  RETURNS TABLE(card_variant_id, language_code, language_name,
    card_name, collector_number, collector_total, card_set_code,
    card_set_name, is_default_variant, variant_label, copies_count,
    last_added_at, image_path, total_count)

- Filtros de coleção e idioma são aplicados por EXEMPLAR antes do
  agrupamento: copies_count conta os exemplares que satisfazem o
  filtro.
- variant_label: acabamento · tiragem · contexto de edição (mesma ordem
  de eixos de card-variant-display.ts, I5). A interface só mostra a
  etiqueta quando is_default_variant = false.
- image_path: CARD_FRONT primário ativo da carta, preferindo o idioma
  do grupo, depois pt-BR, depois en, depois language_order. Resolvido
  só para as linhas da página (LATERAL após LIMIT).
- total_count: total de grupos que satisfazem os filtros (para
  paginação), repetido em cada linha.
- Coleção inexistente ou de outro usuário: resultado vazio (mesma
  resposta de uma coleção própria vazia — não enumera).

Segurança (padrão 6137/5034):
- SECURITY DEFINER, STABLE, SET search_path = '', objetos qualificados.
- auth.uid() obrigatório: sem sessão → 'not_authenticated' (28000).
- O dono nunca é parâmetro: inventory.owner_user_id = auth.uid().
- Nenhum dado de catálogo além do necessário para exibir as cartas
  que o próprio usuário possui; RLS admin-only do catálogo (ADR-022)
  permanece intacta.
- EXECUTE: revogado de PUBLIC e anon; concedido só a authenticated.

Erros (22023): INVALID_SORT, INVALID_PAGE, INVALID_SEARCH,
INVALID_COLLECTION_FILTER (p_collection_id com p_without_collection).

Performance:
- Ponto de entrada: ix_physical_card_inventory_variant
  (inventory_id, card_variant_id) — só o acervo do usuário.
- Duas fases. Fase 1 escolhe as chaves da página; fase 2 monta a
  apresentação só dessas linhas (catálogo por PK + imagem LATERAL).
- Caminho rápido na visão padrão (RECENT, sem busca, sem Set): a
  paginação acontece sobre o agrupamento dos exemplares, sem tocar o
  catálogo. Busca, Set e SET_NUMBER precisam do catálogo de todos os
  grupos do usuário (caminho completo; medido separadamente em 5827).
- Critério B4: p95 ≤ 150 ms em VR (harness 5827, Seção P).

Pré-requisitos: 5000-5002, 5010-5012 (Physical Card), 5023, 5030,
5040+ (Collection Allocation), catálogo (card, card_variant,
card_set, language, card_asset, card_asset_type, eixos 150/2166/2204).

Como validar: Query 5827.
================================================================
*/

begin;

create or replace function public.get_my_inventory_items(
  p_search             text    default null,
  p_card_set_code      text    default null,
  p_language_code      text    default null,
  p_collection_id      uuid    default null,
  p_without_collection boolean default false,
  p_sort               text    default 'RECENT',
  p_limit              integer default 48,
  p_offset             integer default 0
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
  copies_count       integer,
  last_added_at      timestamptz,
  image_path         text,
  total_count        bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user        uuid := auth.uid();
  v_inventory   uuid;
  v_sort        text := upper(coalesce(nullif(btrim(p_sort), ''), 'RECENT'));
  v_q           text := nullif(btrim(coalesce(p_search, '')), '');
  v_q_like      text;
  v_q_num       text;
  v_q_tot       text;
  v_slash       integer;
  v_without     boolean := coalesce(p_without_collection, false);
  v_variants    uuid[];
  v_languages   uuid[];
  v_counts      integer[];
  v_lasts       timestamptz[];
  v_total       bigint;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_sort not in ('RECENT', 'SET_NUMBER') then
    raise exception 'INVALID_SORT' using errcode = '22023';
  end if;

  if p_limit is null or p_limit not between 1 and 96
     or p_offset is null or p_offset not between 0 and 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  if v_q is not null and length(v_q) > 100 then
    raise exception 'INVALID_SEARCH' using errcode = '22023';
  end if;

  if p_collection_id is not null and v_without then
    raise exception 'INVALID_COLLECTION_FILTER' using errcode = '22023';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;  -- usuário sem Inventory: acervo vazio, sem erro
  end if;

  if v_q is not null then
    v_q_like := replace(replace(replace(lower(v_q), '\', '\\'), '%', '\%'), '_', '\_');
    v_slash  := strpos(v_q, '/');
    if v_slash > 1 then
      v_q_num := btrim(substr(v_q, 1, v_slash - 1));
      v_q_tot := btrim(substr(v_q, v_slash + 1));
      if v_q_tot = '' or translate(v_q_tot, '0123456789', '') <> '' then
        v_q_tot := null;
      else
        v_q_tot := coalesce(nullif(ltrim(v_q_tot, '0'), ''), '0');
      end if;
    else
      v_q_num := v_q;
    end if;
    v_q_num := coalesce(nullif(ltrim(lower(v_q_num), '0'), ''), '0');
  end if;

  -- FASE 1 — chaves da página (grupo = Card Variant + idioma), em arrays.
  -- Caminho rápido (visão padrão: RECENT, sem busca e sem Set): pagina
  -- direto sobre o agrupamento dos exemplares; catálogo só para ≤ 96
  -- linhas. Caminho completo (busca, Set ou SET_NUMBER): junta o catálogo
  -- de todos os grupos do usuário, porque o filtro/ordem dependem dele.
  if v_q is null and p_card_set_code is null and v_sort = 'RECENT' then
    with copies as (
      select pc.card_variant_id, pc.language_id, pc.created_at
      from public.physical_card pc
      where pc.inventory_id = v_inventory
        and (p_language_code is null or pc.language_id = (
              select l.id from public.language l where l.code = p_language_code))
        and (p_collection_id is null or exists (
              select 1
              from public.collection_allocation ca
              join public.collection co
                on co.id = ca.collection_id
               and co.owner_user_id = v_user
              where ca.physical_card_id = pc.id
                and ca.collection_id = p_collection_id))
        and (not v_without or not exists (
              select 1 from public.collection_allocation ca
              where ca.physical_card_id = pc.id))
    ),
    grouped as (
      select g.card_variant_id, g.language_id,
             count(*)::integer as n, max(g.created_at) as last_added
      from copies g
      group by g.card_variant_id, g.language_id
    ),
    page as (
      select gr.*, count(*) over () as total
      from grouped gr
      order by gr.last_added desc, gr.card_variant_id, gr.language_id
      limit p_limit offset p_offset
    )
    select array_agg(pg.card_variant_id order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           array_agg(pg.language_id     order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           array_agg(pg.n               order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           array_agg(pg.last_added      order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           max(pg.total)
      into v_variants, v_languages, v_counts, v_lasts, v_total
    from page pg;
  else
    with copies as (
      select pc.card_variant_id, pc.language_id, pc.created_at
      from public.physical_card pc
      where pc.inventory_id = v_inventory
        and (p_language_code is null or pc.language_id = (
              select l.id from public.language l where l.code = p_language_code))
        and (p_collection_id is null or exists (
              select 1
              from public.collection_allocation ca
              join public.collection co
                on co.id = ca.collection_id
               and co.owner_user_id = v_user
              where ca.physical_card_id = pc.id
                and ca.collection_id = p_collection_id))
        and (not v_without or not exists (
              select 1 from public.collection_allocation ca
              where ca.physical_card_id = pc.id))
    ),
    grouped as (
      select g.card_variant_id, g.language_id,
             count(*)::integer as n, max(g.created_at) as last_added
      from copies g
      group by g.card_variant_id, g.language_id
    ),
    joined as (
      select gr.card_variant_id, gr.language_id, gr.n, gr.last_added,
             cv.variant_order, c.collector_order,
             cs.code as set_code, cs.release_date, cs.release_order,
             l.language_order
      from grouped gr
      join public.card_variant cv on cv.id = gr.card_variant_id
      join public.card c          on c.id = cv.card_id
      join public.card_set cs     on cs.id = c.card_set_id
      join public.language l      on l.id = gr.language_id
      where (p_card_set_code is null or cs.code = p_card_set_code)
        and (v_q is null
             or lower(c.name) like '%' || v_q_like || '%' escape '\'
             or (coalesce(nullif(ltrim(lower(c.collector_number), '0'), ''), '0') = v_q_num
                 and (v_q_tot is null
                      or coalesce(nullif(ltrim(c.collector_total::text, '0'), ''), '0') = v_q_tot)))
    ),
    page as (
      select j.card_variant_id, j.language_id, j.n, j.last_added,
             count(*) over () as total,
             row_number() over (order by
               case when v_sort = 'RECENT' then j.last_added end desc nulls last,
               case when v_sort = 'SET_NUMBER' then j.release_date end desc nulls last,
               case when v_sort = 'SET_NUMBER' then j.release_order end desc nulls last,
               case when v_sort = 'SET_NUMBER' then j.set_code end asc,
               j.collector_order asc,
               j.variant_order asc,
               j.language_order asc,
               j.card_variant_id asc,
               j.language_id asc) as ord
      from joined j
    )
    select array_agg(pg.card_variant_id order by pg.ord),
           array_agg(pg.language_id     order by pg.ord),
           array_agg(pg.n               order by pg.ord),
           array_agg(pg.last_added      order by pg.ord),
           max(pg.total)
      into v_variants, v_languages, v_counts, v_lasts, v_total
    from page pg
    where pg.ord > p_offset and pg.ord <= p_offset + p_limit;
  end if;

  if v_variants is null then
    return;  -- página vazia (sem exemplares, sem resultados ou além do fim)
  end if;

  -- FASE 2 — apresentação só das linhas da página, na ordem da fase 1.
  return query
  select
    u.variant_id,
    l.code,
    l.name,
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    cs.name::text,
    cv.is_default,
    nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
    u.n,
    u.last_added,
    img.storage_path,
    v_total
  from unnest(v_variants, v_languages, v_counts, v_lasts)
       with ordinality as u(variant_id, language_id, n, last_added, ord)
  join public.card_variant cv on cv.id = u.variant_id
  join public.card c          on c.id = cv.card_id
  join public.card_set cs     on cs.id = c.card_set_id
  join public.language l      on l.id = u.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  left join lateral (
    select ca.storage_path
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al on al.id = ca.language_id
    where ca.card_id = c.id
      and ca.is_primary
      and ca.is_active
      and ca.storage_path is not null
    order by (ca.language_id = u.language_id) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by u.ord;
end;
$$;

comment on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer) is
  'Meu acervo (Query 5159): grupos Card Variant + idioma do acervo do usuário da sessão, paginados (≤ 96), com filtros, ordenação RECENT|SET_NUMBER e imagem CARD_FRONT. Exige auth.uid(); dono resolvido no servidor.';

revoke all on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer) from public;
revoke all on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer) from anon;
grant execute on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer) to authenticated;

commit;
