-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816232405
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3011 - Create Card Condition Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.card_condition, reaproveitando a função já existente
public.set_updated_at().

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de linha,
  nunca definido manualmente pela aplicação.
================================================================
*/

CREATE TRIGGER trg_card_condition_set_updated_at
    BEFORE UPDATE ON public.card_condition
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
