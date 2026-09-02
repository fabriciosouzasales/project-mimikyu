/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5041 - Create Collection Allocation updated_at Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02C-IMPLEMENTATION-01)

Descrição...:
Mantém collection_allocation.updated_at automaticamente em qualquer
UPDATE, reaproveitando public.set_updated_at() — mesma função já
usada por inventory/physical_card/storage_container/collection.

Nenhuma RPC desta rodada faz UPDATE em collection_allocation (só
INSERT via allocate_physical_cards_to_collection() e DELETE via
deallocate_physical_cards_from_collection()) — trigger criada por
consistência com toda tabela updated_at do projeto, sem exceção até
aqui, e para cobrir sem ALTER futuro qualquer caminho de escrita que
venha a fazer UPDATE nesta tabela (ex. uma eventual operação de
"mover" implementada como UPDATE em vez de DELETE+INSERT).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE TRIGGER trg_collection_allocation_set_updated_at
    BEFORE UPDATE ON public.collection_allocation
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
