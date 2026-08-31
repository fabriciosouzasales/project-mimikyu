/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5001 - Create Inventory Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.inventory, reaproveitando a função já existente
public.set_updated_at() (mesmo padrão de card_condition/Query 3011,
user_profile/Query 1001).

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de
  linha, nunca definido manualmente pela aplicação.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TRIGGER trg_inventory_set_updated_at
    BEFORE UPDATE ON public.inventory
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
