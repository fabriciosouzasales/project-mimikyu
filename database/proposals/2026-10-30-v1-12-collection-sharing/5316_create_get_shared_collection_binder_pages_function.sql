/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5316 - Create get_shared_collection_binder_pages()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12) — depende de 5300–5302, 5315
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Porta do PARTICIPANTE para os bolsos do fichário (até 4 páginas), já
mascarados para a coleção autorizada pelo núcleo 5315.

Regras de Negócio:
- Acesso: collection_share_role() IN ('OWNER','VIEWER'). Qualquer outro
  caso (PUBLIC sem participação, convite pendente/recusado,
  ex-participante, estranho) → COLLECTION_NOT_FOUND (P0002), igual a
  coleção inexistente. Visitante de coleção pública usa a 5318.
- Só authenticated (anon sem EXECUTE).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection_binder_pages(
    p_collection_id UUID,
    p_first_page    INTEGER,
    p_page_count    INTEGER
)
RETURNS TABLE (
    page_number      INTEGER,
    row_index        INTEGER,
    column_index     INTEGER,
    pocket_state     TEXT,
    card_name        TEXT,
    collector_number TEXT,
    collector_total  INTEGER,
    card_set_code    TEXT,
    variant_label    TEXT,
    language_code    TEXT,
    image_path       TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_role TEXT;
BEGIN
    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RAISE EXCEPTION 'COLLECTION_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    RETURN QUERY SELECT * FROM public.collection_binder_masked_pages(p_collection_id, p_first_page, p_page_count);
END;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection_binder_pages(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_binder_pages(UUID, INTEGER, INTEGER) TO authenticated;
