-- Query 4010 | public.search_cards() — projeção de leitura segura para Pesquisa Global de Cartas
-- Objetivo: expor busca por nome/coleção/número/UUID a qualquer authenticated sem ampliar
-- SELECT direto nas tabelas base do Catálogo Editorial (que permanecem admin-only, ADR-022).
-- Padrão adotado: função standalone public.* SECURITY DEFINER STABLE (mesmo padrão de
-- is_admin()) em vez do par internal.*+wrapper SECURITY INVOKER sugerido condicionalmente no
-- pedido original — a convenção do schema internal (STD-001 §9) exige que funções internal só
-- sejam chamadas por outras SECURITY DEFINER, o que um wrapper INVOKER violaria. Decisão e
-- alternativas documentadas em docs/adr/ADR-030-card-search-projection.md.
--
-- Ranking fixo determinístico (sem sort selector, por decisão de escopo):
--   0 = card_id exato (seleção direta do combobox)
--   1 = sem termo de busca (só filtros)
--   2 = card_set.code exato
--   3 = collector_number normalizado (zeros à esquerda removidos) exato
--   4 = nome exato
--   5 = nome prefixo
--   6 = nome contém
-- Desempate: release_date desc, release_order desc, collector_order asc.
--
-- Segurança: RAISE em auth.uid() nulo; EXECUTE revogado de PUBLIC/anon, concedido só a
-- authenticated (ver GRANTs ao final deste arquivo). search_path fixado em ''.
-- CONFIRMADO EXECUTADO em 2026-08-16/17 via Supabase MCP (apply_migration).

create or replace function public.search_cards(
  p_query text default null,
  p_card_id uuid default null,
  p_game_code text default null,
  p_card_set_code text default null,
  p_category_code text default null,
  p_rarity_code text default null,
  p_limit integer default 36,
  p_offset integer default 0
)
returns table (
  card_id uuid,
  card_name character varying,
  collector_number character varying,
  collector_total integer,
  card_set_id uuid,
  card_set_code character varying,
  card_set_name character varying,
  game_id uuid,
  game_code character varying,
  game_name character varying,
  category_id uuid,
  category_code character varying,
  category_name character varying,
  rarity_id uuid,
  rarity_code character varying,
  rarity_name character varying,
  rarity_symbol_code character varying,
  image_path_pt text,
  image_path_en text,
  total_count bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_query text;
  v_query_escaped text;
  v_query_norm text;
  v_limit integer;
  v_offset integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 36), 1), 60);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_query := nullif(btrim(coalesce(p_query, '')), '');

  if v_query is not null then
    v_query_escaped := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
    v_query_norm := coalesce(nullif(ltrim(v_query, '0'), ''), '0');
  end if;

  return query
  with front_asset as (
    select
      ca.card_id,
      max(ca.storage_path) filter (where l.code = 'pt-BR') as image_path_pt,
      max(ca.storage_path) filter (where l.code = 'en') as image_path_en
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id
    join public.language l on l.id = ca.language_id
    where cat.code = 'CARD_FRONT' and ca.is_primary and ca.is_active
    group by ca.card_id
  ),
  matches as (
    select
      c.id as card_id,
      c.name as card_name,
      c.collector_number,
      c.collector_total,
      cs.id as card_set_id,
      cs.code as card_set_code,
      cs.name as card_set_name,
      g.id as game_id,
      g.code as game_code,
      g.name as game_name,
      cc.id as category_id,
      cc.code as category_code,
      cc.name as category_name,
      r.id as rarity_id,
      r.code as rarity_code,
      r.name as rarity_name,
      r.symbol_code as rarity_symbol_code,
      fa.image_path_pt,
      fa.image_path_en,
      cs.release_date,
      cs.release_order,
      c.collector_order,
      case
        when p_card_id is not null and c.id = p_card_id then 0
        when v_query is null then 1
        when lower(cs.code) = lower(v_query) then 2
        when coalesce(nullif(ltrim(c.collector_number, '0'), ''), '0') = v_query_norm then 3
        when lower(c.name) = lower(v_query) then 4
        when lower(c.name) like lower(v_query_escaped) || '%' escape '\' then 5
        when lower(c.name) like '%' || lower(v_query_escaped) || '%' escape '\' then 6
        else null
      end as rank
    from public.card c
    join public.card_set cs on cs.id = c.card_set_id
    join public.expansion e on e.id = cs.expansion_id
    join public.game g on g.id = e.game_id
    left join public.card_category cc on cc.id = c.category_id
    left join public.rarity r on r.id = c.rarity_id
    left join front_asset fa on fa.card_id = c.id
    where c.is_active
      and (p_game_code is null or lower(g.code) = lower(p_game_code))
      and (p_card_set_code is null or lower(cs.code) = lower(p_card_set_code))
      and (p_category_code is null or lower(cc.code) = lower(p_category_code))
      and (p_rarity_code is null or lower(r.code) = lower(p_rarity_code))
      and (
        (p_card_id is not null and c.id = p_card_id)
        or v_query is null
        or lower(cs.code) = lower(v_query)
        or coalesce(nullif(ltrim(c.collector_number, '0'), ''), '0') = v_query_norm
        or lower(c.name) like '%' || lower(v_query_escaped) || '%' escape '\'
      )
  ),
  filtered as (
    select *, count(*) over () as total_count
    from matches
    where rank is not null
    order by rank asc, release_date desc nulls last, release_order desc nulls last, collector_order asc
    limit v_limit offset v_offset
  )
  select
    f.card_id, f.card_name, f.collector_number, f.collector_total,
    f.card_set_id, f.card_set_code, f.card_set_name,
    f.game_id, f.game_code, f.game_name,
    f.category_id, f.category_code, f.category_name,
    f.rarity_id, f.rarity_code, f.rarity_name, f.rarity_symbol_code,
    f.image_path_pt, f.image_path_en, f.total_count
  from filtered f;
end;
$$;

revoke all on function public.search_cards(text, uuid, text, text, text, text, integer, integer) from public;
revoke all on function public.search_cards(text, uuid, text, text, text, text, integer, integer) from anon;
grant execute on function public.search_cards(text, uuid, text, text, text, text, integer, integer) to authenticated;
