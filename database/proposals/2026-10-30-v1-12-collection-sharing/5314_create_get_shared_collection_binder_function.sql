/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5314 - Create get_shared_collection_binder()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12 SHARING CORRECTION) — depende de 5300–5302
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Cabeçalho do Fichário Digital para o participante VIEWER (C-145): se a
coleção tem fichário, a grade, o número de páginas e quantas cartas DESTA
coleção estão nos bolsos. Contrato próprio — não abre get_my_collection_binder
(5223/5252), que é do titular e devolve local físico, participantes e
cartas disponíveis.

Regras de Negócio:
- Acesso: collection_share_role() IN ('OWNER','VIEWER'). PUBLIC e sem
  acesso → NULL (indistinguíveis de coleção inexistente). PUBLIC fica
  fora por decisão conservadora (deny by default); estender é trocar o
  IN — decisão do produto, não técnica.
- Fichário próprio da coleção ou o fichário em que ela é convidada
  (collection_layout_guest, 5230) — mesma resolução de 5223.
- Projeção mínima: has_binder, grid_columns, grid_rows, page_count,
  own_filled_count (bolsos com carta alocada a ESTA coleção). NUNCA:
  layout_id, local físico (storage_container), nome/quantidade de outras
  coleções do fichário, cartas disponíveis, papel OWNER/GUEST, ids.
- Só leitura, STABLE; nenhuma escrita.
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection_binder(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_role   TEXT;
    v_layout UUID;
    v_cols   INTEGER;
    v_rows   INTEGER;
    v_pages  INTEGER := 0;
    v_filled INTEGER := 0;
BEGIN
    IF p_collection_id IS NULL THEN
        RETURN NULL;
    END IF;

    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RETURN NULL;
    END IF;

    SELECT l.id, l.grid_columns, l.grid_rows INTO v_layout, v_cols, v_rows
    FROM public.collection_layout l
    WHERE l.collection_id = p_collection_id;
    IF v_layout IS NULL THEN
        SELECT l.id, l.grid_columns, l.grid_rows INTO v_layout, v_cols, v_rows
        FROM public.collection_layout_guest g
        JOIN public.collection_layout l ON l.id = g.layout_id
        WHERE g.collection_id = p_collection_id;
    END IF;

    IF v_layout IS NULL THEN
        RETURN jsonb_build_object('has_binder', false);
    END IF;

    SELECT count(*)::INTEGER INTO v_pages
    FROM public.collection_layout_page p
    WHERE p.layout_id = v_layout;

    SELECT count(*)::INTEGER INTO v_filled
    FROM public.collection_layout_page p
    JOIN public.collection_layout_slot s              ON s.page_id = p.id
    JOIN public.collection_layout_slot_assignment a   ON a.slot_id = s.id
    JOIN public.collection_allocation ca              ON ca.physical_card_id = a.physical_card_id
    WHERE p.layout_id = v_layout
      AND ca.collection_id = p_collection_id;

    RETURN jsonb_build_object(
        'has_binder', true,
        'grid_columns', v_cols,
        'grid_rows', v_rows,
        'page_count', v_pages,
        'own_filled_count', v_filled
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection_binder(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_binder(UUID) TO authenticated;
