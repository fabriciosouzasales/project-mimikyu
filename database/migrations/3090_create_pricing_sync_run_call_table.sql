-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817002617
-- Recuperado em: 2026-08-17
-- ============================================================================

-- Query 3090 — Criação de public.pricing_sync_run_call (Incremento P3)
-- Objetivo: registro append-only de cada chamada HTTP individual feita durante uma pricing_sync_run.

CREATE TABLE public.pricing_sync_run_call (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sync_run_id               UUID NOT NULL REFERENCES public.pricing_sync_run (id) ON DELETE CASCADE,
    sequence_number            INTEGER NOT NULL,
    endpoint                   TEXT NOT NULL,
    http_status_code           INTEGER,
    outcome                    TEXT NOT NULL,
    error_detail               TEXT,
    api_requests_remaining     INTEGER,
    called_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_sync_run_call_run_sequence
        UNIQUE (sync_run_id, sequence_number),
    CONSTRAINT ck_pricing_sync_run_call_sequence_positive
        CHECK (sequence_number > 0),
    CONSTRAINT ck_pricing_sync_run_call_endpoint_not_blank
        CHECK (BTRIM(endpoint) <> ''),
    CONSTRAINT ck_pricing_sync_run_call_outcome
        CHECK (outcome IN ('SUCCESS', 'TECHNICAL_FAILURE', 'BUDGET_STOPPED')),
    CONSTRAINT ck_pricing_sync_run_call_remaining_non_negative
        CHECK (api_requests_remaining IS NULL OR api_requests_remaining >= 0),
    CONSTRAINT ck_pricing_sync_run_call_http_status_range
        CHECK (http_status_code IS NULL OR (http_status_code BETWEEN 100 AND 599))
);

-- Nenhum índice isolado em sync_run_id: a UNIQUE (sync_run_id, sequence_number) já é um
-- índice composto cujo prefixo (sync_run_id) e ordenação (sequence_number ASC) atendem
-- exatamente à leitura ordenada das chamadas de uma execução — índice redundante evitado
-- por decisão explícita (ver docs/05f-pricing.md, seção "Índices — Incremento P3").

ALTER TABLE public.pricing_sync_run_call ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select ON public.pricing_sync_run_call
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_sync_run_call TO authenticated;
GRANT SELECT ON public.pricing_sync_run_call TO service_role;
GRANT INSERT ON public.pricing_sync_run_call TO service_role;
-- Nenhum GRANT UPDATE/DELETE — tabela append-only. Nenhum GRANT TRUNCATE/REFERENCES/TRIGGER/MAINTAIN concedido.

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pricing_sync_run_call FROM anon, authenticated;