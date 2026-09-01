/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5031 - Create Collection updated_at Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01)

Descrição...:
Mantém collection.updated_at automaticamente em qualquer UPDATE,
reaproveitando a função compartilhada public.set_updated_at() já usada
por inventory (5001), physical_card (5011) e storage_container (5021)
— nenhuma função nova criada.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TRIGGER trg_collection_set_updated_at
    BEFORE UPDATE ON public.collection
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
