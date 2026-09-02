/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5053 - Create Collection Card Set Reference updated_at Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Mantém updated_at de collection_card_set_reference, reaproveitando
public.set_updated_at(). Passa a ser tocado de verdade quando
set_collection_card_set_reference() (Query 5066) troca card_set_id
antes do lock.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE TRIGGER trg_collection_card_set_reference_set_updated_at
    BEFORE UPDATE ON public.collection_card_set_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
