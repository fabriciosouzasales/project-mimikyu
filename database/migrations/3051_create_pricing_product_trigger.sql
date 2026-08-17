-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817005200
-- Recuperado em: 2026-08-17
-- ============================================================================


CREATE TRIGGER trg_pricing_product_set_updated_at
    BEFORE UPDATE ON public.pricing_product
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
