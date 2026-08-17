-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817002601
-- Recuperado em: 2026-08-17
-- ============================================================================

-- Query 3081 — Trigger de updated_at em public.pricing_sync_run (Incremento P3)
CREATE TRIGGER trg_pricing_sync_run_set_updated_at
    BEFORE UPDATE ON public.pricing_sync_run
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();