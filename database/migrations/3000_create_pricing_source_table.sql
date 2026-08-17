-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816232230
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3000 - Create Pricing Source Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria a tabela public.pricing_source — cadastro de fontes externas de
dados de mercado (ex.: JustTCG, TCGplayer, futuras fontes brasileiras).
Nenhuma fonte é cadastrada ou ativada nesta Query (fora de escopo do
Incremento P1 — homologação de fontes ainda pendente). Carrega apenas
o escopo de mercado default declarado (default_market_scope), que
isoladamente nunca autoriza a classificação BRAZIL_ITEM_VALUATION
(essa decisão depende da observação individual — ver pricing_observation,
fora de escopo deste incremento). Ver ADR-029 e docs/05f-pricing.md.

Regras de Negócio:
- code único e imutável após criação, maiúsculo;
- default_market_scope restrito a INTERNATIONAL/BRAZIL, é um default
  ajustável, não uma trava, e nunca autoriza sozinho Valor Brasil;
- base_currency no formato ISO 4217 (3 letras maiúsculas);
- nenhuma exclusão física prevista — apenas is_active = FALSE;
- RLS habilitado desde a criação; única policy é leitura administrativa
  (pricing_admin_select); nenhuma função de escrita administrativa é
  criada nesta Query (fora de escopo deste incremento);
- GRANT mínimo (authenticated: SELECT; anon: nenhum) e REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de anon/authenticated, aplicados
  desde o nascimento da tabela (STD-001, revisão 1.19).
================================================================
*/

CREATE TABLE public.pricing_source (
    id                             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code                           TEXT NOT NULL,
    name                           TEXT NOT NULL,
    source_type                    TEXT NOT NULL,
    default_market_scope           TEXT NOT NULL,
    base_currency                  TEXT NOT NULL,
    base_url                       TEXT,
    api_base_url                   TEXT,
    documentation_url              TEXT,
    terms_url                      TEXT,
    attribution_text               TEXT,
    requires_commercial_agreement  BOOLEAN NOT NULL DEFAULT FALSE,
    supports_api                   BOOLEAN NOT NULL DEFAULT FALSE,
    is_active                      BOOLEAN NOT NULL DEFAULT TRUE,
    source_order                   INTEGER NOT NULL,
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_source_code UNIQUE (code),
    CONSTRAINT uq_pricing_source_order UNIQUE (source_order),
    CONSTRAINT ck_pricing_source_code_format
        CHECK (code = UPPER(code) AND code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_pricing_source_name_not_blank CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_pricing_source_type
        CHECK (source_type IN ('API', 'DATASET', 'MANUAL')),
    CONSTRAINT ck_pricing_source_default_market_scope
        CHECK (default_market_scope IN ('INTERNATIONAL', 'BRAZIL')),
    CONSTRAINT ck_pricing_source_base_currency_format
        CHECK (base_currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_pricing_source_base_url
        CHECK (base_url IS NULL OR (BTRIM(base_url) <> '' AND base_url ~* '^https://')),
    CONSTRAINT ck_pricing_source_api_base_url
        CHECK (api_base_url IS NULL OR (BTRIM(api_base_url) <> '' AND api_base_url ~* '^https://')),
    CONSTRAINT ck_pricing_source_documentation_url
        CHECK (documentation_url IS NULL OR (BTRIM(documentation_url) <> '' AND documentation_url ~* '^https://')),
    CONSTRAINT ck_pricing_source_terms_url
        CHECK (terms_url IS NULL OR (BTRIM(terms_url) <> '' AND terms_url ~* '^https://')),
    CONSTRAINT ck_pricing_source_source_order_positive
        CHECK (source_order > 0)
);

COMMENT ON TABLE public.pricing_source IS
    'Cadastro de fontes externas de dados de mercado (Pricing). default_market_scope é apenas capacidade/default declarado — nunca autoriza sozinho BRAZIL_ITEM_VALUATION. Nenhuma fonte cadastrada nesta Query (homologação pendente). Ver ADR-029 e docs/05f-pricing.md.';

ALTER TABLE public.pricing_source ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
    ON public.pricing_source
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_source TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pricing_source FROM anon, authenticated;
