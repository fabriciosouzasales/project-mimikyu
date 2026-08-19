-- Query 3915 — CONFIRMADO EXECUTADO (correção mínima de escala do P14.3, 3ª rodada), a
-- pedido de Fabrício, ANTES da reexecução real do piloto BASE4.
-- Aplicada via Supabase MCP em 2026-08-19.
--
-- Contexto: a Query 3914 corrigiu o produto cartesiano na pré-busca de pricing_observation,
-- mas ainda comparava por tupla EXATA (incluindo observed_at). Provado por teste dedicado
-- que duas execuções em dias diferentes com o MESMO preço criavam duas linhas, porque
-- observed_at nunca coincide entre execuções reais (vem de variant.lastUpdated da JustTCG,
-- que avança a cada dia, ou do fallback new Date()). Projeção: 18.700 cartas x ~5
-- produtos/variantes x execução diária ~= 34,1 milhões de linhas/ano sem essa correção,
-- mesmo sem nenhuma mudança real de preço.
--
-- Esta função substitui a pré-busca por tupla exata (batch_select_pricing_observation_by_
-- identity, Query 3914) por uma busca da ÚLTIMA observação conhecida por grupo (produto +
-- condição + price_type + currency_code + market_label, SEM observed_at na chave de busca),
-- via LATERAL...ORDER BY observed_at DESC LIMIT 1 por chave, reaproveitando o índice já
-- existente ix_pricing_observation_snapshot_lookup. O TypeScript decide então: preço igual
-- ao último conhecido -> reaproveita, sem INSERT; mesmo observed_at exato com preço diferente
-- -> colisão real, preservada e sinalizada; preço diferente do último -> mudança material,
-- grava observação nova.
--
-- Deduplicação interna via CTE (SELECT DISTINCT sobre jsonb_to_recordset(p_keys)): a função
-- é resiliente a chaves duplicadas na entrada independentemente do comportamento do
-- TypeScript chamador — nunca depende só da camada de aplicação para essa garantia.
--
-- A função batch_select_pricing_observation_by_identity (tupla exata, Query 3914) É MANTIDA
-- nesta rodada, intacta: SECURITY INVOKER, sem mutação, restrita a service_role — mantê-la
-- não representa risco, e removê-la agora criaria uma janela de incompatibilidade com
-- versões anteriores do script ainda não substituídas em produção. Sua remoção poderá
-- ocorrer depois que o novo código (que já passou a chamar esta função) estiver commitado.
--
-- Testada transacionalmente (BEGIN/ROLLBACK) antes desta aplicação real, contra dados reais
-- de pricing_product/pricing_observation/card_condition (2 produtos de teste isolados,
-- IDs fixos fora de qualquer dado real, removidos pelo ROLLBACK — zero resíduo confirmado
-- pós-teste):
-- (1) sem observação anterior para a chave pedida -> nenhuma linha retornada (join LATERAL
--     sem correspondência, comportamento de INNER JOIN).
-- (2) mesmo preço (5) em duas datas diferentes (2026-08-18/2026-08-19) -> retorna a
--     observação de 2026-08-19 (a mais recente), preço 5.
-- (3) histórico 7 (17/08) -> 8 (18/08) -> 7 (19/08), inserido fora de ordem cronológica ->
--     retorna sempre a cronologicamente mais recente (19/08, preço 7), nunca a de maior
--     preço nem a primeira inserida.
-- (4) duas identidades distintas (produto A e produto B) pedidas na mesma chamada -> cada
--     uma retorna seu próprio pricing_product_id/preço, nenhuma mistura entre grupos.
-- (5) a mesma chave enviada 5 vezes na mesma chamada -> exatamente 1 linha retornada
--     (dedup interno via SELECT DISTINCT na CTE, não depende do chamador deduplicar).
--
-- Reexecutado pós-aplicação, contra a função já publicada: os mesmos 5 cenários confirmados
-- idênticos aos resultados pré-aplicação. Zero resíduo (produtos/observações de teste
-- removidos pelo ROLLBACK). Confirmado via pg_proc: prosecdef=false (SECURITY INVOKER),
-- search_path='public, pg_temp', proacl = {postgres=X/postgres, service_role=X/postgres}
-- (sem PUBLIC, sem anon, sem authenticated) — tanto na função nova quanto na de tupla exata
-- (Query 3914), que segue intacta. Advisors de segurança e performance revisados pós-
-- aplicação: nenhum achado novo relacionado a esta função ou a pricing_observation.
--
-- SECURITY INVOKER (nunca SECURITY DEFINER), search_path fixo, EXECUTE restrito a
-- service_role. Ver 05f-pricing.md / ADR-029 (P14.3).

CREATE FUNCTION public.batch_select_latest_pricing_observation_by_identity(p_keys jsonb)
RETURNS TABLE(
  pricing_product_id uuid,
  condition_id uuid,
  price_type text,
  currency_code text,
  market_label text,
  observed_at timestamptz,
  price numeric
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH distinct_keys AS (
    SELECT DISTINCT pricing_product_id, condition_id, price_type, currency_code, market_label
    FROM jsonb_to_recordset(p_keys) AS k(
      pricing_product_id uuid,
      condition_id uuid,
      price_type text,
      currency_code text,
      market_label text
    )
  )
  SELECT k.pricing_product_id, k.condition_id, k.price_type, k.currency_code, k.market_label,
         latest.observed_at, latest.price
  FROM distinct_keys k
  CROSS JOIN LATERAL (
    SELECT o.observed_at, o.price
    FROM public.pricing_observation o
    WHERE o.pricing_product_id = k.pricing_product_id
      AND o.condition_id = k.condition_id
      AND o.price_type = k.price_type
      AND o.currency_code = k.currency_code
      AND o.market_label IS NOT DISTINCT FROM k.market_label
    ORDER BY o.observed_at DESC
    LIMIT 1
  ) latest;
$function$;

COMMENT ON FUNCTION public.batch_select_latest_pricing_observation_by_identity(jsonb) IS
  'P14.3 (correção de escala 2026-08-19, 3ª rodada) — busca em lote da ULTIMA observação conhecida por grupo (produto+condição+price_type+currency+market_label, SEM observed_at na chave), via LATERAL...ORDER BY observed_at DESC LIMIT 1, deduplicando internamente as chaves de entrada (CTE SELECT DISTINCT). Substitui batch_select_pricing_observation_by_identity (Query 3914, tupla exata) na pré-busca de Fase 3 — permite reaproveitar a observação existente quando o preço não muda, mesmo com observed_at diferente entre execuções diárias. SECURITY INVOKER (SELECT já concedido a service_role desde Query 3091/3002, nenhum GRANT novo). Nunca chamada por anon/authenticated. A função de tupla exata (Query 3914) é mantida por compatibilidade até o código chamador estar commitado. Ver Query 3915 e ADR-029/05f-pricing.md (P14.3).';

REVOKE ALL ON FUNCTION public.batch_select_latest_pricing_observation_by_identity(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_select_latest_pricing_observation_by_identity(jsonb) TO service_role;
