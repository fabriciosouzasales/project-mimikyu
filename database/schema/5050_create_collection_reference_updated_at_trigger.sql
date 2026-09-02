/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5050 - Create Collection Reference updated_at Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Mantém updated_at de collection_reference, reaproveitando
public.set_updated_at() já canônica (usada por collection/collection_
allocation/storage_container). Nenhuma função nova.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE TRIGGER trg_collection_reference_set_updated_at
    BEFORE UPDATE ON public.collection_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
