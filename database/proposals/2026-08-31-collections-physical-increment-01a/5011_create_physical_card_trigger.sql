/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5011 - Create Physical Card Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.physical_card, reaproveitando public.set_updated_at().

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de
  linha, nunca definido manualmente pela aplicação.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TRIGGER trg_physical_card_set_updated_at
    BEFORE UPDATE ON public.physical_card
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
