-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817005151
-- Recuperado em: 2026-08-17
-- ============================================================================


CREATE TABLE public.pricing_product (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pricing_card_mapping_id   UUID NOT NULL REFERENCES public.pricing_card_mapping (id) ON DELETE CASCADE,
    external_product_id       TEXT NOT NULL,
    source_printing_label     TEXT NOT NULL,
    language_status           TEXT NOT NULL DEFAULT 'UNDETERMINED',
    language_id               UUID REFERENCES public.language (id) ON DELETE RESTRICT,
    card_variant_id           UUID REFERENCES public.card_variant (id) ON DELETE SET NULL,
    is_active                 BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_product_mapping_external
        UNIQUE (pricing_card_mapping_id, external_product_id),
    CONSTRAINT ck_pricing_product_external_product_id_not_blank
        CHECK (BTRIM(external_product_id) <> ''),
    CONSTRAINT ck_pricing_product_printing_label_not_blank
        CHECK (BTRIM(source_printing_label) <> ''),
    CONSTRAINT ck_pricing_product_language_status
        CHECK (language_status IN ('CONFIRMED', 'INFERRED', 'UNDETERMINED')),
    CONSTRAINT ck_pricing_product_language_id_consistency
        CHECK (
            (language_status IN ('CONFIRMED', 'INFERRED') AND language_id IS NOT NULL)
            OR (language_status = 'UNDETERMINED' AND language_id IS NULL)
        )
);

-- Desvio deliberado da hipótese original de 05f-pricing.md: nenhum índice isolado em
-- pricing_card_mapping_id é criado aqui, porque a própria UNIQUE acima (que começa
-- por esse prefixo) já serve integralmente a leitura "produtos de um mapping".

CREATE INDEX ix_pricing_product_external_product_id
    ON public.pricing_product (external_product_id);

CREATE INDEX ix_pricing_product_card_variant_id
    ON public.pricing_product (card_variant_id)
    WHERE card_variant_id IS NOT NULL;

CREATE INDEX ix_pricing_product_variant_language_confirmed
    ON public.pricing_product (card_variant_id, language_id)
    WHERE card_variant_id IS NOT NULL AND language_status = 'CONFIRMED';

ALTER TABLE public.pricing_product ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select ON public.pricing_product
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_product TO authenticated;
GRANT SELECT, INSERT ON public.pricing_product TO service_role;
GRANT UPDATE (source_printing_label, language_status, language_id, card_variant_id, is_active)
    ON public.pricing_product TO service_role;

-- pg_default_acl concede TRUNCATE/REFERENCES/TRIGGER/MAINTAIN a service_role por padrão
-- em tabelas criadas pelo papel postgres — revogado explicitamente aqui por exigência
-- explícita deste incremento (mais restritivo que P1-P3, que deixaram esses defaults
-- intocados para service_role). DELETE nunca é concedido por padrão; revogado apenas
-- por simetria defensiva/documental.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN, DELETE
    ON public.pricing_product FROM service_role;

-- anon/authenticated não recebem nada por padrão (tabela criada por postgres) — revoke
-- aqui é defensivo/documental, mesmo padrão já usado em P1-P3 (STD-001).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_product FROM anon, authenticated;
