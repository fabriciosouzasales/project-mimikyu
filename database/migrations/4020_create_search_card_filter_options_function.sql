-- Query 4020 | public.search_card_filter_options() — opções de filtro para a Pesquisa Global de Cartas
-- Objetivo: alimentar os selects de Jogo/Coleção/Categoria/Raridade da página /pesquisa sem
-- expor SELECT direto nas tabelas base do Catálogo Editorial. Mesmo padrão de segurança de
-- public.search_cards() (Query 4010) — ver docs/adr/ADR-030-card-search-projection.md.
-- Retorna um único jsonb agregando as quatro listas, opcionalmente filtradas por p_game_code.
-- CONFIRMADO EXECUTADO em 2026-08-16/17 via Supabase MCP (apply_migration).

create or replace function public.search_card_filter_options(p_game_code text default null)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'games', (
      select coalesce(jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name) order by g.name), '[]'::jsonb)
      from public.game g
    ),
    'cardSets', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object('code', cs.code, 'name', cs.name, 'gameCode', g.code)
          order by cs.release_date desc nulls last, cs.release_order desc nulls last, cs.name
        ),
        '[]'::jsonb
      )
      from public.card_set cs
      join public.expansion e on e.id = cs.expansion_id
      join public.game g on g.id = e.game_id
      where p_game_code is null or lower(g.code) = lower(p_game_code)
    ),
    'categories', (
      select coalesce(
        jsonb_agg(jsonb_build_object('code', cc.code, 'name', cc.name, 'gameCode', g.code) order by cc.display_order, cc.name),
        '[]'::jsonb
      )
      from public.card_category cc
      join public.game g on g.id = cc.game_id
      where p_game_code is null or lower(g.code) = lower(p_game_code)
    ),
    'rarities', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object('code', r.code, 'name', r.name, 'symbolCode', r.symbol_code, 'gameCode', g.code)
          order by r.display_order, r.name
        ),
        '[]'::jsonb
      )
      from public.rarity r
      join public.game g on g.id = r.game_id
      where p_game_code is null or lower(g.code) = lower(p_game_code)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.search_card_filter_options(text) from public;
revoke all on function public.search_card_filter_options(text) from anon;
grant execute on function public.search_card_filter_options(text) to authenticated;
