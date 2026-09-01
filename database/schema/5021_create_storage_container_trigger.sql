/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5021 - Create Storage Container Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01)

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.storage_container, reaproveitando public.set_updated_at() —
mesmo padrão de inventory (Query 5001) e physical_card (Query 5011).

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de
  linha, nunca definido manualmente pela aplicação.

CONFIRMADO EXECUTADO em 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02A-
IMPLEMENTATION-01, Fase 1) via apply_migration (versão de migration
Supabase 20260901002938). Associação confirmada via pg_trigger.
================================================================
*/

CREATE TRIGGER trg_storage_container_set_updated_at
    BEFORE UPDATE ON public.storage_container
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
