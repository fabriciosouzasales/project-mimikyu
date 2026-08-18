-- Query 3902 — CONFIRMADO EXECUTADO (Incremento P11, 2026-08-17)
-- Índice adicional motivado por achado real de performance na validação do Incremento P11,
-- não por hipótese antecipada. ix_pricing_observation_latest_lookup (Query 3070, Incremento P6)
-- cobre (pricing_product_id, condition_id, price_type, observed_at DESC) mas NÃO inclui
-- market_label — a nova função public.get_card_pricing_snapshot() (Query 3901) agrupa o
-- "snapshot mais recente" por produto/condição/tipo de preço/mercado (exigência explícita do
-- pedido de Fabrício: "somente o snapshot mais recente por produto/condição/tipo de preço/
-- mercado"), uma coluna a mais no agrupamento do que o índice existente cobre.
--
-- Validado por EXPLAIN (ANALYZE, BUFFERS), transacional (BEGIN...ROLLBACK), com 50.000
-- observações sintéticas distribuídas entre os 5 produtos reais de uma carta do piloto P8:
-- sem este índice, o DISTINCT ON caía num Sort externo em disco (~7 MB, Sort Method: external
-- merge) sobre TODO o histórico de cada produto, em vez de percorrer diretamente a ponta mais
-- recente de cada grupo — degradação que só piora à medida que o histórico (append-only por
-- design, P6) cresce. Mesmo precedente de índice acrescentado após achado real de validação
-- já usado no Incremento P4 (Query 3052, achado do advisor de performance).

CREATE INDEX ix_pricing_observation_snapshot_lookup
    ON public.pricing_observation (pricing_product_id, condition_id, price_type, market_label, observed_at DESC);
