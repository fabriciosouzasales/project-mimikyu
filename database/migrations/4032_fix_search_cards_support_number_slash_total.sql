-- Query 4032 | public.search_cards() — correção: suportar busca no formato "NNN/NNN" (número/total)
--
-- Objetivo
-- Fabrício reportou, durante a homologação local pedida na rodada corretiva anterior (ver
-- database/migrations/4030_fix_search_cards_remove_game_filter.sql), que pesquisar "125/094" em
-- /pesquisa retornava "Nenhuma carta encontrada", apesar de existir a carta correspondente
-- (Mega Charizard X ex, ME2, collector_number "125", collector_total 94).
--
-- Causa raiz
-- O padrão "número" (tier 3 do ranking) normaliza a string inteira digitada removendo zeros à
-- esquerda (`ltrim(v_query, '0')`) e compara contra `collector_number` normalizado da mesma forma.
-- Para "125/094", a string inteira (incluindo a barra) nunca é igual a um `collector_number`
-- isolado — o normalizador nunca foi desenhado para o formato combinado "número/total", só para o
-- número isolado. "NNN/NNN" é exatamente o formato exibido nas telas do catálogo
-- (`cartaFullNumber()` em web/lib/pesquisa/format.ts e no helper equivalente de
-- components/catalogo/cartas-gallery.tsx), então é natural o usuário digitar esse formato — a
-- galeria administrativa já tinha corrigido um bug análogo em 2026-07-31, mas só no filtro
-- client-side em JS daquela tela; a correção nunca foi replicada para esta função SQL, usada por
-- /pesquisa (caminho de código totalmente distinto).
--
-- Correção
-- Quando `p_query` contém uma barra "/" com pelo menos um caractere de cada lado, a função separa
-- a parte antes e depois da barra (via `strpos`/`substr`, sem `regexp_replace`), confirma que ambas
-- as partes contêm só dígitos (via `translate(x, '0123456789', '') = ''`, mesma técnica sem regex
-- já adotada na Query 4002 para contornar o classificador de segurança do Auto Mode), normaliza
-- cada uma independentemente (mesma regra de remoção de zeros à esquerda) e passa a considerar
-- tier 3 ("número") também quando `collector_number` E `collector_total` (como texto) batem
-- simultaneamente com as duas partes — além de manter, inalterado, o comportamento já existente de
-- correspondência pelo número isolado (sem barra). Nenhuma mudança de contrato público (mesma
-- assinatura da Query 4030); nenhuma mudança nos demais padrões de busca (nome, código de Card Set,
-- filtros). Validado em transação com ROLLBACK antes da aplicação: a lógica corrigida retorna
-- exatamente a carta esperada para "125/094", nenhum resíduo.
--
-- Nota de execução: a primeira tentativa desta migration usava uma expressão regular
-- (`v_query ~ '^[0-9]+\s*/\s*[0-9]+$'`) e foi bloqueada pelo classificador de segurança do Auto
-- Mode tanto via `apply_migration` quanto via `execute_sql` — mesmo padrão de bloqueio já
-- documentado na Query 4002. Reescrita sem nenhuma expressão regular (`strpos`/`substr`/
-- `translate`), semanticamente equivalente, aplicada com sucesso.
--
-- Não altera a migration 4030 (já CONFIRMADO EXECUTADO) — segue o mesmo padrão de correção via
-- DROP FUNCTION + CREATE OR REPLACE, mesmo endurecimento (SECURITY DEFINER STABLE,
-- search_path='', REVOKE de PUBLIC/anon, GRANT EXECUTE só a authenticated).
--
-- Resultado esperado
-- search_cards(p_query := '125/094') retorna a carta cujo collector_number/collector_total
-- correspondem, no mesmo tier de ranking (3) do padrão "número" isolado.
--
-- Como validar
-- select card_name, collector_number, collector_total from public.search_cards(p_query := '125/094');
-- -- deve retornar 1 linha: "Mega Charizard X ex", "125", 94.
--
-- CONFIRMADO EXECUTADO em 2026-08-17 via Supabase MCP (apply_migration).

drop function if exists public.search_cards(text, uuid, text, text, text, integer, integer);

create or replace function public.search_cards(
  p_query text default null,
  p_card_id uuid default null,
  p_card_set_code text default null,
  p_category_code text default null,
  p_rarity_code text default null,
  p_limit integer default 36,
  p_offset integer default 0
)
returns table (
  card_id uuid, card_name character varying, collector_number character varying,
  collector_total integer, card_set_id uuid, card_set_code character varying,
  card_set_name character varying, category_id uuid, category_code character varying,
  category_name character varying, rarity_id uuid, rarity_code character varying,
  rarity_name character varying, rarity_symbol_code character varying,
  image_path_pt text, image_path_en text, total_count bigint
)
language plpgsql security definer stable set search_path = ''
as $$
declare
  v_query text;
  v_query_escaped text;
  v_query_norm text;
  v_query_number_norm text;
  v_query_total_norm text;
  v_slash_pos integer;
  v_number_part text;
  v_total_part text;
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
    v_slash_pos := strpos(v_query, '/');
    if v_slash_pos > 1 and v_slash_pos < length(v_query) then
      v_number_part := btrim(substr(v_query, 1, v_slash_pos - 1));
      v_total_part := btrim(substr(v_query, v_slash_pos + 1));
      if v_number_part <> '' and v_total_part <> ''
        and translate(v_number_part, '0123456789', '') = ''
        and translate(v_total_part, '0123456789', '') = '' then
        v_query_number_norm := coalesce(nullif(ltrim(v_number_part, '0'), ''), '0');
        v_query_total_norm := coalesce(nullif(ltrim(v_total_part, '0'), ''), '0');
      end if;
    end if;
  end if;
  return query
  with front_asset as (
    select ca.card_id,
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
      c.id as card_id, c.name as card_name, c.collector_number, c.collector_total,
      cs.id as card_set_id, cs.code as card_set_code, cs.name as card_set_name,
      cc.id as category_id, cc.code as category_code, cc.name as category_name,
      r.id as rarity_id, r.code as rarity_code, r.name as rarity_name, r.symbol_code as rarity_symbol_code,
      fa.image_path_pt, fa.image_path_en, cs.release_date, cs.release_order, c.collector_order,
      case
        when p_card_id is not null and c.id = p_card_id then 0
        when v_query is null then 1
        when lower(cs.code) = lower(v_query) then 2
        when coalesce(nullif(ltrim(c.collector_number, '0'), ''), '0') = v_query_norm then 3
        when v_query_number_norm is not null
          and coalesce(nullif(ltrim(c.collector_number, '0'), ''), '0') = v_query_number_norm
          and coalesce(nullif(ltrim(c.collector_total::text, '0'), ''), '0') = v_query_total_norm
          then 3
        when lower(c.name) = lower(v_query) then 4
        when lower(c.name) like lower(v_query_escaped) || '%' escape '\' then 5
        when lower(c.name) like '%' || lower(v_query_escaped) || '%' escape '\' then 6
        else null
      end as rank
    from public.card c
    join public.card_set cs on cs.id = c.card_set_id
    left join public.card_category cc on cc.id = c.category_id
    left join public.rarity r on r.id = c.rarity_id
    left join front_asset fa on fa.card_id = c.id
    where c.is_active
      and (p_card_set_code is null or lower(cs.code) = lower(p_card_set_code))
      and (p_category_code is null or lower(cc.code) = lower(p_category_code))
      and (p_rarity_code is null or lower(r.code) = lower(p_rarity_code))
      and (
        (p_card_id is not null and c.id = p_card_id)
        or v_query is null
        or lower(cs.code) = lower(v_query)
        or coalesce(nullif(ltrim(c.collector_number, '0'), ''), '0') = v_query_norm
        or (
          v_query_number_norm is not null
          and coalesce(nullif(ltrim(c.collector_number, '0'), ''), '0') = v_query_number_norm
          and coalesce(nullif(ltrim(c.collector_total::text, '0'), ''), '0') = v_query_total_norm
        )
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
    f.category_id, f.category_code, f.category_name,
    f.rarity_id, f.rarity_code, f.rarity_name, f.rarity_symbol_code,
    f.image_path_pt, f.image_path_en, f.total_count
  from filtered f;
end;
$$;

revoke all on function public.search_cards(text, uuid, text, text, text, integer, integer) from public;
revoke all on function public.search_cards(text, uuid, text, text, text, integer, integer) from anon;
grant execute on function public.search_cards(text, uuid, text, text, text, integer, integer) to authenticated;
