/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5318 - Create get_public_collection_binder_pages()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12 PUBLIC BINDER EXPERIENCE) — depende de 5315
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Bolsos (até 4 páginas) da vitrine pública do fichário, sem sessão.
Mesmo núcleo mascarado do participante (5315): cartas e reservas de
OUTRAS coleções do mesmo fichário nunca aparecem só porque esta foi
publicada.

Regras de Negócio:
- Autoriza SOMENTE coleção PUBLIC e ACTIVE (mesma regra da 5317); caso
  contrário COLLECTION_NOT_FOUND (P0002) — privada, arquivada e
  inexistente indistinguíveis. Despublicar revoga na próxima chamada.
- anon + authenticated. Sem auth.uid() na decisão.
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_public_collection_binder_pages(
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
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.collection c
        WHERE c.id = p_collection_id
          AND c.visibility = 'PUBLIC'
          AND c.lifecycle_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'COLLECTION_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    RETURN QUERY SELECT * FROM public.collection_binder_masked_pages(p_collection_id, p_first_page, p_page_count);
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_collection_binder_pages(UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_collection_binder_pages(UUID, INTEGER, INTEGER) TO anon, authenticated;
