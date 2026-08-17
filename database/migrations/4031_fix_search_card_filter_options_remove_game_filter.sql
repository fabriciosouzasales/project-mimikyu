-- Query 4031 | public.search_card_filter_options() — correção: remover Jogo do contrato público
-- Objetivo: mesma correção de escopo da Query 4030, aplicada à função de opções de filtro. A
-- Query 4020 implementou `p_game_code` e a lista `games` na saída, e escopava
-- cardSets/categories/rarities por Jogo — tudo fora do escopo aprovado desta versão. Dropa a
-- assinatura antiga explicitamente e recria sem o parâmetro, sem a lista `games` e sem o
-- campo `gameCode` nos demais itens; cardSets/categories/rarities passam a listar todos os
-- valores existentes, sem escopo por Jogo. Mesmo endurecimento de segurança da Query 4020.
-- CONFIRMADO EXECUTADO em 2026-08-17 via Supabase MCP (apply_migration).

drop function if exists public.search_card_filter_options(text);

create or replace function public.search_card_filter_options()
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
    'cardSets', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object('code', cs.code, 'name', cs.name)
          order by cs.release_date desc nulls last, cs.release_order desc nulls last, cs.name
        ),
        '[]'::jsonb
      )
      from public.card_set cs
    ),
    'categories', (
      select coalesce(
        jsonb_agg(jsonb_build_object('code', cc.code, 'name', cc.name) order by cc.display_order, cc.name),
        '[]'::jsonb
      )
      from public.card_category cc
    ),
    'rarities', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object('code', r.code, 'name', r.name, 'symbolCode', r.symbol_code)
          order by r.display_order, r.name
        ),
        '[]'::jsonb
      )
      from public.rarity r
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.search_card_filter_options() from public;
revoke all on function public.search_card_filter_options() from anon;
grant execute on function public.search_card_filter_options() to authenticated;
