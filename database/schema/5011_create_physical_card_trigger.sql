/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5011 - Create Physical Card Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.physical_card, reaproveitando public.set_updated_at() — mesmo
padrão de inventory/Query 5001.

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de
  linha, nunca definido manualmente pela aplicação.

CONFIRMADO EXECUTADO em 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-01B,
Fase 2) via apply_migration (versão de migration Supabase
20260831232106). Associação correta ao trigger confirmada via
information_schema.triggers.
================================================================
*/

CREATE TRIGGER trg_physical_card_set_updated_at
    BEFORE UPDATE ON public.physical_card
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
