-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817002552
-- Recuperado em: 2026-08-17
-- ============================================================================

-- Query 3080 — Criação de public.pricing_sync_run (Incremento P3)
-- Objetivo: registro de alto nível de uma execução de sincronização com uma fonte de Pricing.

CREATE TABLE public.pricing_sync_run (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pricing_source_id           UUID NOT NULL REFERENCES public.pricing_source (id) ON DELETE RESTRICT,
    run_type                    TEXT NOT NULL,
    status                      TEXT NOT NULL DEFAULT 'RECEIVED',
    requests_made               INTEGER NOT NULL DEFAULT 0,
    requests_remaining_at_end   INTEGER,
    rate_limit_hits             INTEGER NOT NULL DEFAULT 0,
    error_summary               TEXT,
    triggered_by                TEXT NOT NULL DEFAULT 'MANUAL',
    started_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at                 TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_pricing_sync_run_type
        CHECK (run_type IN ('SET_DISCOVERY', 'CARD_SYNC', 'PRICE_REFRESH')),
    CONSTRAINT ck_pricing_sync_run_status
        CHECK (status IN ('RECEIVED', 'PROCESSING', 'COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_pricing_sync_run_triggered_by
        CHECK (triggered_by IN ('MANUAL', 'SCHEDULED')),
    CONSTRAINT ck_pricing_sync_run_counts_non_negative
        CHECK (requests_made >= 0 AND rate_limit_hits >= 0
               AND (requests_remaining_at_end IS NULL OR requests_remaining_at_end >= 0)),
    CONSTRAINT ck_pricing_sync_run_finished_consistency
        CHECK (
            (status IN ('RECEIVED', 'PROCESSING') AND finished_at IS NULL)
            OR (status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED', 'CANCELLED') AND finished_at IS NOT NULL)
        ),
    CONSTRAINT ck_pricing_sync_run_finished_after_started
        CHECK (finished_at IS NULL OR finished_at >= started_at)
);

-- Índices orientados às consultas reais previstas (não copiados automaticamente do modelo hipotético):
-- 1) últimas execuções de uma fonte, ordenadas por started_at DESC;
-- 2) localização de execuções ainda ativas (RECEIVED/PROCESSING), por fonte ou globalmente.
CREATE INDEX ix_pricing_sync_run_source_started
    ON public.pricing_sync_run (pricing_source_id, started_at DESC);

CREATE INDEX ix_pricing_sync_run_active
    ON public.pricing_sync_run (pricing_source_id)
    WHERE status IN ('RECEIVED', 'PROCESSING');

ALTER TABLE public.pricing_sync_run ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select ON public.pricing_sync_run
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_sync_run TO authenticated;
GRANT SELECT ON public.pricing_sync_run TO service_role;
GRANT INSERT ON public.pricing_sync_run TO service_role;
-- UPDATE restrito por coluna: apenas os campos operacionais do ciclo de vida da execução.
-- id, pricing_source_id, run_type, triggered_by, started_at, created_at permanecem
-- inalteráveis pelo fluxo normal após a inserção (nenhum GRANT UPDATE nessas colunas).
GRANT UPDATE (status, requests_made, requests_remaining_at_end, rate_limit_hits, error_summary, finished_at)
    ON public.pricing_sync_run TO service_role;
-- Nenhum GRANT DELETE concedido (histórico permanente).

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pricing_sync_run FROM anon, authenticated;