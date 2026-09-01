/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5021 - Create Storage Container Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Cria o trigger de manutenção automática de updated_at em
public.storage_container, reaproveitando public.set_updated_at() —
mesmo padrão de inventory (Query 5001) e physical_card (Query 5011).

Regras de Negócio:
- updated_at é atualizado automaticamente em qualquer UPDATE de
  linha, nunca definido manualmente pela aplicação.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TRIGGER trg_storage_container_set_updated_at
    BEFORE UPDATE ON public.storage_container
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
