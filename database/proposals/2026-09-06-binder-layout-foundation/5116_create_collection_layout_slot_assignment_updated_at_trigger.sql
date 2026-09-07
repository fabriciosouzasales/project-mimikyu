/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5116 - Create Slot Assignment updated_at Trigger
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Mantém collection_layout_slot_assignment.updated_at. Mesma convenção
de 5106/5109/5111/5114. Em um MOVE, a linha sobrevive e updated_at
avança — evidência adicional (não normativa) de que MOVE não é
delete+insert.

Dependências:
- public.collection_layout_slot_assignment (Query 5115).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_collection_layout_slot_assignment_updated_at()
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

REVOKE EXECUTE ON FUNCTION public.set_collection_layout_slot_assignment_updated_at()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_slot_assignment_updated_at
    BEFORE UPDATE ON public.collection_layout_slot_assignment
    FOR EACH ROW
    EXECUTE FUNCTION public.set_collection_layout_slot_assignment_updated_at();

COMMIT;
