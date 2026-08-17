-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817005755
-- Recuperado em: 2026-08-17
-- ============================================================================


-- Correção pontual detectada pelo advisor de performance (unindexed_foreign_keys) após
-- a validação inicial: a FK language_id não tinha cobertura de índice. card_variant_id
-- já estava coberta pelo índice parcial existente; language_id não. Índice parcial
-- (mesmo raciocínio de card_variant_id: maioria das linhas terá language_id NULL
-- enquanto o idioma não for confirmado/inferido) — cobre a checagem de integridade
-- referencial (ON DELETE RESTRICT) sem custo de armazenamento sobre linhas UNDETERMINED.
CREATE INDEX ix_pricing_product_language_id
    ON public.pricing_product (language_id)
    WHERE language_id IS NOT NULL;
