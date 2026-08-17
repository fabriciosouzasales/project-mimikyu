-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817013301
-- Recuperado em: 2026-08-17
-- ============================================================================


CREATE TABLE public.pricing_fx_rate (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_currency     TEXT NOT NULL,
    to_currency       TEXT NOT NULL,
    rate              NUMERIC(18,8) NOT NULL,
    rate_date         DATE NOT NULL,
    rate_source_code  TEXT NOT NULL DEFAULT 'BCB_PTAX',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_fx_rate_pair_source_date
        UNIQUE (from_currency, to_currency, rate_source_code, rate_date),
    CONSTRAINT ck_pricing_fx_rate_from_currency_format
        CHECK (from_currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_pricing_fx_rate_to_currency_format
        CHECK (to_currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_pricing_fx_rate_different_currencies
        CHECK (from_currency <> to_currency),
    CONSTRAINT ck_pricing_fx_rate_positive
        CHECK (rate > 0),
    CONSTRAINT ck_pricing_fx_rate_source_code_format
        CHECK (rate_source_code = UPPER(rate_source_code) AND rate_source_code ~ '^[A-Z][A-Z0-9_]*$')
);

-- Desvio deliberado da hipótese original de 05f-pricing.md: nenhum índice adicional
-- (from_currency, to_currency, rate_date DESC) é criado. A própria UNIQUE acima, com as
-- colunas reordenadas (par de moedas + fonte primeiro, rate_date por último em vez da
-- ordem original fonte-por-último), já serve integralmente unicidade + os três padrões de
-- consulta reais (taxa mais recente até uma data; taxa de data exata; histórico de
-- intervalo por par+fonte) — confirmado por EXPLAIN na validação de performance. B-tree é
-- percorrido nos dois sentidos, então ORDER BY rate_date DESC não exige índice/coluna
-- DESC dedicados nem um segundo índice com o mesmo prefixo.

ALTER TABLE public.pricing_fx_rate ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select ON public.pricing_fx_rate
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_fx_rate TO authenticated;
GRANT SELECT, INSERT ON public.pricing_fx_rate TO service_role;

-- pg_default_acl concede TRUNCATE/REFERENCES/TRIGGER/MAINTAIN a service_role por padrão em
-- tabelas criadas pelo papel postgres — revogado explicitamente aqui, mesmo padrão já usado
-- em pricing_product (Query 3050, Incremento P4) e na correção retroativa (Query 3053).
-- UPDATE/DELETE nunca são concedidos por padrão a service_role; revogados aqui apenas por
-- simetria defensiva/documental — a tabela é append-only por design (sem updated_at, sem
-- trigger, sem qualquer rotina administrativa de sobrescrita ou exclusão).
REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_fx_rate FROM service_role;

-- anon/authenticated não recebem nada por padrão (tabela criada pelo papel postgres) —
-- revoke aqui é defensivo/documental, mesmo padrão já usado em P1-P4 (STD-001).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_fx_rate FROM anon, authenticated;
