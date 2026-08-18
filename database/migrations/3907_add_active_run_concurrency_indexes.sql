-- Query 3907 — CONFIRMADO EXECUTADO (Incremento P13.1 — Fundação de Orquestração Programada
-- de Pricing, 2026-08-18). Aplicada originalmente via Supabase MCP no mesmo dia; versionada
-- retroativamente durante a auditoria final do P13.1 (ver nota de proveniência em 3905).
--
-- Contexto: aquisição atômica de execução ativa via índice único parcial (nunca advisory lock
-- de conexão poolada). Dois índices, um por identidade de fonte. Estados ativos: RECEIVED e
-- PROCESSING — mesmo conjunto já usado por ix_pricing_sync_run_active. Cada índice filtra pela
-- coluna correspondente IS NOT NULL, então nunca indexa NULL — NULLS NOT DISTINCT não é
-- necessário aqui (diferente de pricing_observation/Query 3070, onde a chave completa podia
-- ter NULLs relevantes à unicidade).

-- 1. Execução ativa de preço: uma por (pricing_source_id, run_type)
CREATE UNIQUE INDEX ux_pricing_sync_run_active_price_per_source_type
  ON public.pricing_sync_run (pricing_source_id, run_type)
  WHERE status IN ('RECEIVED', 'PROCESSING') AND pricing_source_id IS NOT NULL;

-- 2. Execução ativa cambial: uma por (fx_source_code, run_type)
CREATE UNIQUE INDEX ux_pricing_sync_run_active_fx_per_source_type
  ON public.pricing_sync_run (fx_source_code, run_type)
  WHERE status IN ('RECEIVED', 'PROCESSING') AND fx_source_code IS NOT NULL;
