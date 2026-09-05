/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5088 - Create Collection Pokedex Reference updated_at Trigger
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Mesmo padrão de set_updated_at() já reaproveitado por toda a base
(ver 5031/5041/5050/5053/5073).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE TRIGGER trg_collection_pokedex_reference_updated_at
    BEFORE UPDATE ON public.collection_pokedex_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMIT;
