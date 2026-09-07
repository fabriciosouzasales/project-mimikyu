/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5109 - Create Collection Layout Page updated_at Trigger
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Mantém collection_layout_page.updated_at. Mesma convenção física de
5106 (função dedicada por tabela, SECURITY DEFINER, search_path = '',
EXECUTE revogado de anon/authenticated).

Dependências:
- public.collection_layout_page (Query 5108).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_collection_layout_page_updated_at()
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

REVOKE EXECUTE ON FUNCTION public.set_collection_layout_page_updated_at()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_page_updated_at
    BEFORE UPDATE ON public.collection_layout_page
    FOR EACH ROW
    EXECUTE FUNCTION public.set_collection_layout_page_updated_at();

COMMIT;
