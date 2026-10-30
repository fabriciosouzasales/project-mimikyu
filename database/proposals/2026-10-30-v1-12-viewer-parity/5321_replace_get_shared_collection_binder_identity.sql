/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5321 - Replace get_shared_collection_binder() (+ identidade)
Versão......: 1.2 (substitui o corpo da 5314 v1.x; mesma assinatura) —
              v1.1: nome só para a coleção DONA do fichário;
              v1.2 (BINDER IDENTITY PRIVACY CORRECTION-01): convidada recebe
              show_brand_mark = true (padrão), nunca a preferência do
              fichário dono
Status......: PROPOSTA — NÃO EXECUTADA (V1-12 VIEWER EXPERIENCE PARITY
              CORRECTION-02) — depende de 5302 e 5244/5245
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Acrescenta ao cabeçalho do fichário do participante a identidade visual
que o titular vê na contracapa: `binder_name` (nome próprio gravado) e
`show_brand_mark` (logomarca). Nada mais muda: mesmo acesso
(collection_share_role OWNER/VIEWER), mesmas chaves de antes, mesma
contagem só desta coleção.

Privacidade:
- `binder_name` = collection_layout.display_name SOMENTE quando a coleção
  compartilhada é a dona do fichário (collection_layout.collection_id =
  p_collection_id). Coleção convidada (fichário de OUTRA coleção do
  titular) → NULL, sempre: a identidade de um fichário alheio à coleção
  autorizada não é exposta. Sem nome gravado → NULL (o titular vê o nome
  da coleção dona = a própria coleção compartilhada).
- `show_brand_mark` = preferência real SOMENTE para a coleção dona; convidada
  → `true` (padrão visual MMKYU), sem ler a preferência do fichário dono e
  sem alterá-la. Preferência visual não autoriza leitura de imagens.
- O id da coleção proprietária nunca é lido nem devolvido.

Compatibilidade: chaves novas são aditivas; o frontend já aceita a
resposta antiga (identidade nula → fallback).
Como validar: 5862 (casos B1–B4).
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
    v_name   TEXT;
    v_own    BOOLEAN := false;
    v_brand  BOOLEAN;
BEGIN
    IF p_collection_id IS NULL THEN
        RETURN NULL;
    END IF;

    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RETURN NULL;
    END IF;

    SELECT l.id, l.grid_columns, l.grid_rows, l.display_name, l.show_brand_mark
      INTO v_layout, v_cols, v_rows, v_name, v_brand
    FROM public.collection_layout l
    WHERE l.collection_id = p_collection_id;
    v_own := v_layout IS NOT NULL;
    IF v_layout IS NULL THEN
        -- Convidada: identidade do fichário de OUTRA coleção não atravessa a
        -- fronteira — nem nome, nem preferência de logomarca (padrão MMKYU).
        SELECT l.id, l.grid_columns, l.grid_rows, NULL::TEXT, true
          INTO v_layout, v_cols, v_rows, v_name, v_brand
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
        'own_filled_count', v_filled,
        -- Identidade do fichário (5244/5245): o nome PRÓPRIO gravado só
        -- quando a coleção compartilhada é a DONA do fichário. Convidada
        -- (fichário pertencente a outra coleção do titular) → NULL: nem o
        -- nome do fichário nem o da coleção dona atravessam a fronteira; o
        -- cliente usa o nome da coleção vista.
        'binder_name', CASE WHEN v_own THEN nullif(btrim(v_name), '') END,
        'show_brand_mark', coalesce(v_brand, true)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection_binder(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_binder(UUID) TO authenticated;
