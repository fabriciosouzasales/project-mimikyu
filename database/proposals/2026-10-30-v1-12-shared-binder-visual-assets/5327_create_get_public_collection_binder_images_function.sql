/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5327 - Create get_public_collection_binder_images() (porta da vitrine)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12 SHARED BINDER VISUAL ASSETS-01)
              — depende de 5325
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Imagens decorativas do fichário na vitrine pública — mesma fronteira e
mesmo erro da 5318 (páginas públicas): coleção PUBLIC e ACTIVE, decidida
a cada chamada. Privatizar ou arquivar → COLLECTION_NOT_FOUND na hora.

Conteúdo = núcleo 5325 (só o fichário da coleção dona; convidada →
vazio). A URL é assinada pelo próprio visitante (papel anon), autorizada
pela política escopada da 5329.

Segurança: SECURITY DEFINER, STABLE, search_path '', EXECUTE para anon e
authenticated (a vitrine abre com ou sem sessão). Sem escrita.
Como validar: 5863 (seções S, PB, N).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_public_collection_binder_images(
    p_collection_id UUID,
    p_first_page    INTEGER,
    p_page_count    INTEGER
)
RETURNS TABLE (
    page_number  INTEGER,
    row_index    INTEGER,
    column_index INTEGER,
    height       INTEGER,
    width        INTEGER,
    is_region    BOOLEAN,
    storage_path TEXT,
    focal_x      SMALLINT,
    focal_y      SMALLINT,
    updated_at   TIMESTAMPTZ
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
    RETURN QUERY SELECT * FROM public.collection_binder_shared_images(p_collection_id, p_first_page, p_page_count);
END;
$$;

COMMENT ON FUNCTION public.get_public_collection_binder_images(UUID, INTEGER, INTEGER) IS
  'V1-12 (Query 5327): imagens decorativas do fichário na vitrine (coleção PUBLIC e ACTIVE). Só fichário da coleção dona. Sem acesso → COLLECTION_NOT_FOUND.';

REVOKE ALL ON FUNCTION public.get_public_collection_binder_images(UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_collection_binder_images(UUID, INTEGER, INTEGER) TO anon, authenticated;
