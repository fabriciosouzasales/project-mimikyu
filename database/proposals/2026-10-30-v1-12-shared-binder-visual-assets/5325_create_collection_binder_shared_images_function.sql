/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5325 - Create collection_binder_shared_images() (núcleo interno)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12 SHARED BINDER VISUAL ASSETS-01)
              — depende de 5232/5239 (imagens de bolso e de mesclagem)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Núcleo ÚNICO das imagens decorativas do fichário vistas por quem não é o
titular — o mesmo papel da 5315 para as cartas. Devolve, das páginas
pedidas (1..4), as imagens de bolso (5232) e as imagens em vários bolsos
(mesclagens, 5239) com posição, recorte e enquadramento, sem nenhum id
interno (bolso, região, fichário ou dono).

Regra de propriedade (C-198 + regra de identidade do V1-12):
- A personalização pertence ao FICHÁRIO, e o fichário pertence à coleção
  DONA (`collection_layout.collection_id`). Compartilhar a coleção dona
  compartilha a apresentação do seu fichário → imagens devolvidas.
- Coleção CONVIDADA (fichário de outra coleção do titular): o modelo não
  registra a que coleção uma imagem se refere. Sem propriedade
  determinável, nenhum fallback: zero linhas (bolso continua vazio, como
  hoje). Mesma regra já aprovada para nome e logomarca (5321/5322).

Sem autorização aqui: é interna (sem EXECUTE para API). As portas 5326
(participante) e 5327 (vitrine) decidem o acesso antes de chamar.

Recorte: imagem de bolso → height = width = 1, focal_x = 50 (só eixo
vertical, 5232); mesclagem → retângulo top_row/left_column/height/width e
dois eixos (5239). Ordem: página, linha, coluna.

Custo: bolsos/regiões das ≤ 4 páginas do fichário (índices por page_id) +
PK das tabelas de imagem. Nenhuma leitura do Storage.
Como validar: 5863 (seções I, G).
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_binder_shared_images(
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
#variable_conflict use_column
DECLARE
    c_max_pages CONSTANT INTEGER := 4;
    v_layout UUID;
BEGIN
    IF p_collection_id IS NULL OR p_first_page IS NULL OR p_page_count IS NULL THEN
        RAISE EXCEPTION 'INVALID_ARGUMENT' USING ERRCODE = '22023';
    END IF;
    IF p_first_page < 1 OR p_first_page > 100000
       OR p_page_count < 1 OR p_page_count > c_max_pages THEN
        RAISE EXCEPTION 'INVALID_PAGE' USING ERRCODE = '22023';
    END IF;

    -- Só o fichário cuja DONA é a coleção pedida. Convidada → nada.
    SELECT l.id INTO v_layout
    FROM public.collection_layout l
    WHERE l.collection_id = p_collection_id;
    IF v_layout IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT p.page_number, s.row_index, s.column_index, 1, 1, false,
           i.storage_path, 50::SMALLINT, i.focal_y, i.updated_at
    FROM public.collection_layout_page p
    JOIN public.collection_layout_slot s       ON s.page_id = p.id
    JOIN public.collection_layout_slot_image i ON i.slot_id = s.id
    WHERE p.layout_id = v_layout
      AND p.page_number BETWEEN p_first_page AND p_first_page + p_page_count - 1
    UNION ALL
    SELECT p.page_number, rg.top_row, rg.left_column, rg.height, rg.width, true,
           ri.storage_path, ri.focal_x, ri.focal_y, ri.updated_at
    FROM public.collection_layout_page p
    JOIN public.collection_layout_region rg       ON rg.page_id = p.id
    JOIN public.collection_layout_region_image ri ON ri.region_id = rg.id
    WHERE p.layout_id = v_layout
      AND p.page_number BETWEEN p_first_page AND p_first_page + p_page_count - 1
    ORDER BY 1, 2, 3;
END;
$$;

COMMENT ON FUNCTION public.collection_binder_shared_images(UUID, INTEGER, INTEGER) IS
  'V1-12 (Query 5325): núcleo interno das imagens decorativas do fichário (bolso e mesclagem) para participante/vitrine. Só o fichário da coleção DONA; convidada → zero linhas. Sem ids internos. Sem EXECUTE para API.';

REVOKE ALL ON FUNCTION public.collection_binder_shared_images(UUID, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
