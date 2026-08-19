-- Query 3916 — CONFIRMADO EXECUTADO (fix P14.4.1 — truncamento de 1.000 linhas do Data API),
-- a pedido de Fabrício.
-- Aplicada via Supabase MCP em 2026-08-19.
--
-- Contexto: o piloto real do modo --expansion-plan (scripts/sync-justtcg-pricing.ts) reportou
-- 11 Sets/1.000 cartas contra os 45 Sets/7.429 cartas confirmados por introspecção. Causa raiz:
-- a leitura original de fetchLocalCatalogRows() fazia um único `.select()` sem paginação em
-- `card` (7.429 linhas ativas) — o Data API do Supabase/PostgREST corta silenciosamente em
-- 1.000 linhas por requisição quando nenhum `.range()` é informado, sem erro.
--
-- Esta migration resolve as DUAS superfícies de truncamento do plano de expansão:
--
-- (1) GRANT SELECT ON catalog_card_set_metrics TO service_role — a view já existia (P4 do
--     ROADMAP frontend, contagem de cards_ativas por Set) e já era usada pelo frontend
--     autenticado, mas NUNCA tinha sido lida por um script server-side com Service Role Key.
--     has_table_privilege('service_role', 'public.catalog_card_set_metrics', 'SELECT')
--     confirmava FALSE antes desta migration. O fix do conector (scripts/sync-justtcg-pricing.ts,
--     mesma rodada) passou a reusar cards_ativas (agregado, 1 linha por Set) em vez de contar
--     cartas uma a uma no cliente — eliminando a leitura de 7.429 linhas por completo.
--
-- (2) Nova view pricing_set_coverage: agrega products_count/observations_count por
--     card_set_id x pricing_source_id, substituindo o desenho anterior do conector que
--     encadeava pricing_card_mapping -> pricing_product -> pricing_observation inteiros no
--     cliente (a segunda superfície de truncamento — hoje 136/667/851 linhas, abaixo de
--     1.000, mas P14.4 mira ~18.700 cartas). A view nunca cresce com o volume de
--     produtos/observações: no máximo 1 linha por combinação Set x Fonte (hoje 3 linhas —
--     BASE1/BASE4/ME1). WHERE crd.is_active = TRUE (ajuste pedido por Fabrício na aprovação):
--     cartas inativas nunca entram na contagem de cobertura.
--
-- Testada transacionalmente (BEGIN/ROLLBACK) antes desta aplicação real, contra dados reais:
-- (1) BASE1 = 15 produtos / 30 observações — confere com o piloto P14.1 já registrado.
-- (2) BASE4 = 635 produtos / 787 observações — confere com o piloto P14.2 (real pilot).
-- (3) ME1 = 17 produtos / 34 observações — confere com o piloto P8/P14.3 original.
-- (4) Teste sintético: uma carta do ME1 marcada is_active=FALSE dentro da própria transação,
--     com mapping/produto/observação novos inseridos para ela -> ME1 permaneceu 17/34
--     (não 18/35), confirmando que WHERE crd.is_active = TRUE exclui cartas inativas mesmo
--     quando têm cobertura JustTCG associada. Revertido pelo ROLLBACK, zero resíduo.
-- (5) has_table_privilege('anon', ..., 'SELECT') = FALSE e ('authenticated', ..., 'SELECT')
--     = FALSE em pricing_set_coverage (REVOKE ALL FROM PUBLIC, anon, authenticated).
-- (6) has_table_privilege('service_role', ..., 'SELECT') = TRUE em pricing_set_coverage E em
--     catalog_card_set_metrics.
--
-- Reexecutado pós-aplicação real: os mesmos 3 Sets confirmados idênticos (15/30, 635/787,
-- 17/34); reloptions confirma security_invoker=true na view nova; ACL confirmada sem
-- PUBLIC/anon/authenticated. Advisors de segurança e performance revisados pós-aplicação:
-- nenhum achado novo relacionado a pricing_set_coverage ou catalog_card_set_metrics.
--
-- security_invoker=true (nunca security_definer implícito de view), EXECUTE/SELECT restrito a
-- service_role. Ver 05f-pricing.md / ADR-029 (P14.4.1, fix de truncamento).

GRANT SELECT ON public.catalog_card_set_metrics TO service_role;

CREATE VIEW public.pricing_set_coverage
WITH (security_invoker = true) AS
SELECT
  crd.card_set_id,
  pcm.pricing_source_id,
  count(DISTINCT pp.id) AS products_count,
  count(po.id) AS observations_count
FROM public.pricing_card_mapping pcm
JOIN public.card crd
  ON crd.id = pcm.card_id
LEFT JOIN public.pricing_product pp
  ON pp.pricing_card_mapping_id = pcm.id
LEFT JOIN public.pricing_observation po
  ON po.pricing_product_id = pp.id
WHERE crd.is_active = TRUE
GROUP BY crd.card_set_id, pcm.pricing_source_id;

REVOKE ALL ON public.pricing_set_coverage
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.pricing_set_coverage TO service_role;

COMMENT ON VIEW public.pricing_set_coverage IS
  'Fix P14.4.1 (2026-08-19) — cobertura Pricing agregada por Card Set x Fonte (products_count/observations_count), 1 linha por combinação, nunca sujeita ao limite de 1.000 linhas do Data API. Só cartas ativas (WHERE card.is_active = TRUE) entram na contagem. security_invoker=true. SELECT restrito a service_role (REVOKE ALL FROM PUBLIC/anon/authenticated) — nunca exposta ao frontend. Usada por scripts/sync-justtcg-pricing.ts (--expansion-plan) para substituir a leitura linha-a-linha de pricing_card_mapping/pricing_product/pricing_observation. Ver Query 3916 e ADR-029/05f-pricing.md.';
