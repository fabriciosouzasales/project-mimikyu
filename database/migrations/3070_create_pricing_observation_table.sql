-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817015400
-- Recuperado em: 2026-08-17
-- ============================================================================


CREATE TABLE public.pricing_observation (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pricing_product_id          UUID NOT NULL REFERENCES public.pricing_product (id) ON DELETE RESTRICT,
    condition_id                UUID NOT NULL REFERENCES public.card_condition (id) ON DELETE RESTRICT,
    sync_run_id                 UUID REFERENCES public.pricing_sync_run (id) ON DELETE SET NULL,
    price_type                  TEXT NOT NULL DEFAULT 'MARKET',
    price                       NUMERIC(12,2) NOT NULL,
    currency_code               TEXT NOT NULL,
    market_label                TEXT,
    market_scope                TEXT NOT NULL DEFAULT 'UNDETERMINED',
    market_evidence             JSONB NOT NULL DEFAULT '{}'::JSONB,
    market_evidence_confirmed   BOOLEAN NOT NULL DEFAULT FALSE,
    observed_at                 TIMESTAMPTZ NOT NULL,
    raw_payload                 JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Correção obrigatória de identidade (Incremento P6, market-aware): a hipótese de
    -- 05f-pricing.md v1.7 (UNIQUE product+condition+price_type+observed_at) colide
    -- observações de mercados/moedas diferentes reportadas pela mesma fonte agregadora no
    -- mesmo instante. NULLS NOT DISTINCT garante que duas observações igualmente sem
    -- market_label também sejam consideradas duplicadas entre si.
    CONSTRAINT uq_pricing_observation_identity_market_aware
        UNIQUE NULLS NOT DISTINCT (
            pricing_product_id, condition_id, price_type, currency_code, market_label, observed_at
        ),
    CONSTRAINT ck_pricing_observation_price_type
        CHECK (price_type IN ('MARKET', 'LOW', 'MID', 'HIGH', 'LISTING', 'LAST_SALE')),
    CONSTRAINT ck_pricing_observation_price_non_negative
        CHECK (price >= 0),
    CONSTRAINT ck_pricing_observation_currency_format
        CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_pricing_observation_market_label_not_blank
        CHECK (market_label IS NULL OR BTRIM(market_label) <> ''),
    CONSTRAINT ck_pricing_observation_market_scope
        CHECK (market_scope IN ('INTERNATIONAL', 'BRAZIL', 'UNDETERMINED')),
    CONSTRAINT ck_pricing_observation_market_evidence_is_object
        CHECK (jsonb_typeof(market_evidence) = 'object'),
    CONSTRAINT ck_pricing_observation_market_evidence_not_empty
        CHECK (market_scope = 'UNDETERMINED' OR market_evidence <> '{}'::JSONB),
    CONSTRAINT ck_pricing_observation_market_evidence_confirmed_requires_scope
        CHECK (NOT market_evidence_confirmed OR market_scope <> 'UNDETERMINED'),
    CONSTRAINT ck_pricing_observation_raw_payload_is_object
        CHECK (jsonb_typeof(raw_payload) = 'object')
);

-- Desvio deliberado da hipótese original de 05f-pricing.md: nenhum índice isolado em
-- pricing_product_id (já é a primeira coluna da própria UNIQUE market-aware, que também
-- serve como índice). Índice de leitura recente cobre "última observação de
-- produto/condição/tipo" quando moeda/mercado não são conhecidos previamente (a UNIQUE
-- não serve esse padrão, pois currency_code/market_label ficam entre price_type e
-- observed_at). condition_id não está em posição utilizável em nenhum índice acima
-- (sempre precedido por pricing_product_id) — recebe cobertura própria para a FK.
-- sync_run_id, opcional e populado só quando a observação vier de sincronização
-- automática, recebe índice parcial.
CREATE INDEX ix_pricing_observation_latest_lookup
    ON public.pricing_observation (pricing_product_id, condition_id, price_type, observed_at DESC);

CREATE INDEX ix_pricing_observation_condition_id
    ON public.pricing_observation (condition_id);

CREATE INDEX ix_pricing_observation_sync_run_id
    ON public.pricing_observation (sync_run_id)
    WHERE sync_run_id IS NOT NULL;

ALTER TABLE public.pricing_observation ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select ON public.pricing_observation
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_observation TO authenticated;
GRANT SELECT, INSERT ON public.pricing_observation TO service_role;

-- pg_default_acl concede TRUNCATE/REFERENCES/TRIGGER/MAINTAIN a service_role por padrão em
-- tabelas criadas pelo papel postgres — revogado explicitamente aqui, mesmo padrão já
-- usado em pricing_product (Query 3050) e pricing_fx_rate (Query 3060). UPDATE/DELETE
-- nunca são concedidos por padrão a service_role; revogados aqui por simetria
-- defensiva/documental — a tabela é append-only por design (sem updated_at, sem trigger,
-- sem qualquer rotina administrativa de sobrescrita ou exclusão; reprocessamento usa
-- ON CONFLICT DO NOTHING contra a UNIQUE de identidade).
REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_observation FROM service_role;

-- anon/authenticated não recebem nada por padrão (tabela criada pelo papel postgres) —
-- revoke aqui é defensivo/documental, mesmo padrão já usado em P1-P5 (STD-001).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_observation FROM anon, authenticated;
