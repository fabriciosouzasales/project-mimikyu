/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5050 - Create Collection Reference updated_at Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Mantém updated_at de collection_reference, reaproveitando
public.set_updated_at() já canônica (usada por collection/collection_
allocation/storage_container). Nenhuma função nova.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TRIGGER trg_collection_reference_set_updated_at
    BEFORE UPDATE ON public.collection_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
