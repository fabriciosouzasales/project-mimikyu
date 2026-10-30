/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5322 - Replace get_public_collection_binder() — identidade
              da coleção convidada (vitrine pública)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030192249 `5322_fix_public_collection_binder_guest_identity`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-viewer-parity/
              (só este bloco Status difere); texto do ledger ≡ corpo após o cabeçalho (md5).
              Validação: 5862 v2.1 33/33 PASS, resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
A 5317 (vitrine pública) já devolvia binder_name = NULL para coleção
convidada, mas ainda devolvia show_brand_mark do fichário DONO (outra
coleção do titular). Esta migration reaplica o corpo da 5317 com uma única
mudança: no ramo convidada, show_brand_mark = true (padrão visual MMKYU),
sem ler nem alterar a preferência real.

Preservado sem mudança: assinatura, RETURNS JSONB, todas as chaves de
saída, regra de publicação (visibility PUBLIC + lifecycle ACTIVE), nome
próprio só para a coleção dona, contagem de páginas, grants (anon e
authenticated) e SECURITY DEFINER com search_path vazio.

Diff em relação à 5317 (corpo LIVE ≡ arquivo 5317 por md5 989f749b…):
  ramo convidada: `l.show_brand_mark` → `true AS show_brand_mark`.
Como validar: 5862 v2.1 (PB.1–PB.4).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_public_collection_binder(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_col     RECORD;
    v_layout  RECORD;
    v_own     BOOLEAN := false;
    v_pages   INTEGER := 0;
BEGIN
    IF p_collection_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT c.id, c.name, c.completion_policy, c.cover_finish, owner.display_name AS owner_display_name
      INTO v_col
    FROM public.collection c
    JOIN public.user_profile owner ON owner.id = c.owner_user_id
    WHERE c.id = p_collection_id
      AND c.visibility = 'PUBLIC'
      AND c.lifecycle_status = 'ACTIVE';
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT l.id, l.grid_columns, l.grid_rows, l.display_name, l.show_brand_mark INTO v_layout
    FROM public.collection_layout l
    WHERE l.collection_id = p_collection_id;
    IF FOUND THEN
        v_own := true;
    ELSE
        -- Convidada: nem o nome nem a preferência de logomarca do fichário de
        -- OUTRA coleção atravessam a fronteira (padrão MMKYU = true).
        SELECT l.id, l.grid_columns, l.grid_rows, NULL::TEXT AS display_name, true AS show_brand_mark INTO v_layout
        FROM public.collection_layout_guest g
        JOIN public.collection_layout l ON l.id = g.layout_id
        WHERE g.collection_id = p_collection_id;
    END IF;

    IF v_layout.id IS NOT NULL THEN
        SELECT count(*)::INTEGER INTO v_pages FROM public.collection_layout_page p WHERE p.layout_id = v_layout.id;
    END IF;

    RETURN jsonb_build_object(
        'collection_id', v_col.id,
        'name', v_col.name,
        'completion_policy', v_col.completion_policy,
        'cover_finish', v_col.cover_finish,
        'owner_display_name', v_col.owner_display_name,
        'card_set_code', (SELECT cs.code FROM public.collection_reference cr
                          JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
                          JOIN public.card_set cs ON cs.id = ccsr.card_set_id
                          WHERE cr.collection_id = v_col.id),
        'card_set_name', (SELECT cs.name FROM public.collection_reference cr
                          JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
                          JOIN public.card_set cs ON cs.id = ccsr.card_set_id
                          WHERE cr.collection_id = v_col.id),
        'card_set_logo_path', (SELECT cs.logo_storage_path FROM public.collection_reference cr
                          JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
                          JOIN public.card_set cs ON cs.id = ccsr.card_set_id
                          WHERE cr.collection_id = v_col.id),
        'has_binder', v_layout.id IS NOT NULL,
        'binder_name', CASE WHEN v_own THEN v_layout.display_name END,
        'show_brand_mark', coalesce(v_layout.show_brand_mark, true),
        'grid_columns', v_layout.grid_columns,
        'grid_rows', v_layout.grid_rows,
        'page_count', v_pages
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_collection_binder(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_collection_binder(UUID) TO anon, authenticated;
