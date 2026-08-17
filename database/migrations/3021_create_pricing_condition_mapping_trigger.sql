-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816232457
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3021 - Create Pricing Condition Mapping Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.pricing_condition_mapping, reaproveitando a função já existente
public.set_updated_at().

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de linha,
  nunca definido manualmente pela aplicação.
================================================================
*/

CREATE TRIGGER trg_pricing_condition_mapping_set_updated_at
    BEFORE UPDATE ON public.pricing_condition_mapping
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
