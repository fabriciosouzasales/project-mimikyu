/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5349 - get_catalog_cards_for_species(): cartas do catálogo de
              uma espécie Pokémon, para a escolha explícita da Lista de
              desejos a partir da Pokédex (V1-11 W4 — lacuna L3)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO no LIVE. Executar só com autorização
              de Fabrício; validar com 5875 logo depois.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-02 (V1-11 W4 | POKÉDEX INTEGRATION-01)

Por que existe (lacuna L3 do contrato de produto da Wishlist)
  A posição da Pokédex é uma ESPÉCIE. O desejo é por Card Variant (5345).
  Não há leitura para o usuário final que liste as cartas do catálogo de uma
  espécie: card/card_variant/card_primary_species só são legíveis por admin
  (RLS), 5208 lista só EXEMPLARES do acervo e search_cards não filtra por
  espécie. Sem esta leitura, a Pokédex não consegue oferecer a escolha
  explícita da carta (D-W0: nunca presumir a carta pela espécie).

Contrato
  get_catalog_cards_for_species(p_species_id uuid, p_limit int = 24, p_offset int = 0)
  Uma linha por CARTA ativa, categoria POKEMON, cuja espécie primária
  (card_primary_species, 6112) é a pedida e que tem ao menos uma variante
  ATIVA — a mesma regra de "mesma espécie" do vínculo da Pokédex (5208).
  Colunas: card_id, card_name, collector_number, collector_total,
  card_set_code, card_set_name, image_path_pt, image_path_en (CARD_FRONT
  primária ativa, regra da 5336/5346), active_variant_count, total_count.
  Ordem: Set mais recente primeiro (release_date desc, nulos por último),
  depois código do Set e collector_order — estável para paginar.
  Nunca escolhe carta nem variante: a escolha de variante continua em 5163
  e a inclusão/remoção nas funções da W1 (5346). Sem dado de usuário.

Segurança
  SECURITY DEFINER, search_path '', STABLE, exige auth.uid() (28000);
  EXECUTE só authenticated (PUBLIC e anon revogados). Leitura de catálogo.

Limites e erros
  22023 INVALID_SPECIES (nula) · 22023 INVALID_PAGE (limite fora de 1..60
  ou offset fora de 0..10000). Espécie inexistente → 0 linhas.

Desempenho
  Entrada pelo índice reverso de card_primary_species (espécie → cartas,
  6112); variantes ativas por card_id; imagens só da página (CTE limitada).
  Uma chamada por abertura da escolha, nunca por posição da grade.

Como validar: 5875 (harness, sentinela TR000, resíduo zero).
================================================================
*/

begin;

create or replace function public.get_catalog_cards_for_species(
  p_species_id uuid,
  p_limit      integer default 24,
  p_offset     integer default 0
)
returns table (
  card_id              uuid,
  card_name            text,
  collector_number     text,
  collector_total      integer,
  card_set_code        text,
  card_set_name        text,
  image_path_pt        text,
  image_path_en        text,
  active_variant_count integer,
  total_count          bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_species_id is null then
    raise exception 'INVALID_SPECIES' using errcode = '22023';
  end if;

  if p_limit is null or p_limit not between 1 and 60
     or p_offset is null or p_offset not between 0 and 10000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  return query
  with eligible as (
    select c.id, c.name, c.collector_number, c.collector_total, c.collector_order,
           cs.code as set_code, cs.name as set_name, cs.release_date,
           v.n as variants
    from public.card_primary_species cps
    join public.card c           on c.id = cps.card_id and c.is_active
    join public.card_category cc on cc.id = c.category_id and cc.code = 'POKEMON'
    join public.card_set cs      on cs.id = c.card_set_id
    cross join lateral (
      select count(*)::integer as n
      from public.card_variant cv
      where cv.card_id = c.id and cv.is_active
    ) v
    where cps.pokemon_species_id = p_species_id
      and v.n > 0
  ),
  page as (
    select e.*, count(*) over () as total
    from eligible e
    order by e.release_date desc nulls last, e.set_code, e.collector_order, e.id
    limit p_limit offset p_offset
  ),
  front_asset as (
    select ca.card_id,
           max(ca.storage_path) filter (where l.code = 'pt-BR') as image_path_pt,
           max(ca.storage_path) filter (where l.code = 'en')    as image_path_en
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id
    join public.language l on l.id = ca.language_id
    where cat.code = 'CARD_FRONT' and ca.is_primary and ca.is_active
      and ca.card_id in (select p.id from page p)
    group by ca.card_id
  )
  select p.id,
         p.name::text,
         p.collector_number::text,
         p.collector_total,
         p.set_code::text,
         p.set_name::text,
         fa.image_path_pt::text,
         fa.image_path_en::text,
         p.variants,
         p.total
  from page p
  left join front_asset fa on fa.card_id = p.id
  order by p.release_date desc nulls last, p.set_code, p.collector_order, p.id;
end;
$$;

comment on function public.get_catalog_cards_for_species(uuid, integer, integer) is
  'V1-11 W4 (Query 5349): cartas ativas (POKEMON) de uma espécie com ao menos uma variante ativa — escolha explícita da carta na Lista de desejos a partir da Pokédex (lacuna L3). Leitura de catálogo paginada (1..60); exige auth.uid(). Nunca escolhe carta nem variante.';

revoke all on function public.get_catalog_cards_for_species(uuid, integer, integer) from public;
revoke all on function public.get_catalog_cards_for_species(uuid, integer, integer) from anon;
grant execute on function public.get_catalog_cards_for_species(uuid, integer, integer) to authenticated;

commit;

-- Como validar (rápido; completo na 5875):
-- select p.oid::regprocedure, p.prosecdef, p.proconfig, p.provolatile,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
-- from pg_proc p where p.oid = 'public.get_catalog_cards_for_species(uuid,integer,integer)'::regprocedure;
-- Esperado: t | {search_path=""} | s | f | t
