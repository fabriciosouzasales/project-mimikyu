/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5114 - Create Slot Expected Content updated_at Trigger
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Mantém collection_layout_slot_expected_content.updated_at. Mesma
convenção de 5106/5109/5111.

Dependências:
- public.collection_layout_slot_expected_content (Query 5113).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_collection_layout_slot_expected_content_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_collection_layout_slot_expected_content_updated_at()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_slot_expected_content_updated_at
    BEFORE UPDATE ON public.collection_layout_slot_expected_content
    FOR EACH ROW
    EXECUTE FUNCTION public.set_collection_layout_slot_expected_content_updated_at();

COMMIT;
