/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5315 - Create collection_binder_masked_pages() (interna)
Versão......: 2.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142611 `5315_create_collection_binder_masked_pages_function`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Núcleo ÚNICO de leitura mascarada do Fichário Digital de uma coleção, para
quem não é o titular. Interna: sem EXECUTE para PUBLIC/anon/authenticated.
Só as portas com autorização própria a chamam:
  - 5316 get_shared_collection_binder_pages  → participante (OWNER/VIEWER)
  - 5318 get_public_collection_binder_pages  → visitante (coleção PUBLIC e ACTIVE)
Um só núcleo garante que participante e visitante recebam exatamente o
mesmo mascaramento (v1.0 desta query era a própria porta do VIEWER).

Regras de Negócio:
- NÃO autoriza: a autorização é da porta que chama. Aqui só validação de
  argumentos e a janela (1..4 páginas, página ≤ 100000).
- Mesma resolução de fichário de 5252 (próprio ou convidada).
- Mascaramento por bolso (C-157–C-161):
    CARD     → exemplar ALOCADO A ESTA coleção: só a face pública do
               catálogo (nome, número, Set, variante, idioma, imagem do
               catálogo);
    RESERVED → reserva DESTA coleção sem exemplar dela no bolso;
    EMPTY    → todo o resto (vazio, carta de OUTRA coleção, carta sem
               coleção, reserva alheia, mesclagem/imagem personalizada) —
               indistinguíveis de propósito.
- NUNCA devolve: page_id, slot_id, assignment_id, collection_allocation_id,
  physical_card_id, card_id/variant_id, storage_container_id, coleção ou
  nome de outra coleção, fixação, mesclagens, imagens personalizadas
  (Storage privado), referências de espécie.
- Só leitura, STABLE.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_binder_masked_pages(
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
#variable_conflict use_column
DECLARE
    c_max_pages CONSTANT INTEGER := 4;
    v_layout UUID;
    v_owner  UUID;
BEGIN
    IF p_collection_id IS NULL OR p_first_page IS NULL OR p_page_count IS NULL THEN
        RAISE EXCEPTION 'INVALID_ARGUMENT' USING ERRCODE = '22023';
    END IF;
    IF p_first_page < 1 OR p_first_page > 100000
       OR p_page_count < 1 OR p_page_count > c_max_pages THEN
        RAISE EXCEPTION 'INVALID_PAGE' USING ERRCODE = '22023';
    END IF;

    SELECT l.id, l.collection_id INTO v_layout, v_owner
    FROM public.collection_layout l
    WHERE l.collection_id = p_collection_id;
    IF v_layout IS NULL THEN
        SELECT l.id, l.collection_id INTO v_layout, v_owner
        FROM public.collection_layout_guest g
        JOIN public.collection_layout l ON l.id = g.layout_id
        WHERE g.collection_id = p_collection_id;
    END IF;
    IF v_layout IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH sl AS (
        SELECT s.id, s.row_index, s.column_index, p.page_number
        FROM public.collection_layout_page p
        JOIN public.collection_layout_slot s ON s.page_id = p.id
        WHERE p.layout_id = v_layout
          AND p.page_number BETWEEN p_first_page AND p_first_page + p_page_count - 1
    ),
    v AS (
        SELECT
            sl.page_number,
            sl.row_index,
            sl.column_index,
            -- carta no bolso só se o exemplar estiver alocado a ESTA coleção
            CASE WHEN ca.collection_id = p_collection_id THEN cv.id END AS own_variant_id,
            CASE WHEN ca.collection_id = p_collection_id THEN pc.language_id END AS own_language_id,
            -- reserva só se for DESTA coleção
            CASE WHEN e.slot_id IS NOT NULL AND coalesce(e.collection_id, v_owner) = p_collection_id
                 THEN e.card_id END AS own_expected_card_id,
            CASE WHEN e.slot_id IS NOT NULL AND coalesce(e.collection_id, v_owner) = p_collection_id
                 THEN coalesce(e.expected_variant_type_id,
                               (SELECT ev.variant_type_id FROM public.card_variant ev WHERE ev.id = e.card_variant_id))
            END AS own_expected_type_id
        FROM sl
        LEFT JOIN public.collection_layout_slot_assignment a      ON a.slot_id = sl.id
        LEFT JOIN public.physical_card pc                         ON pc.id = a.physical_card_id
        LEFT JOIN public.collection_allocation ca                 ON ca.physical_card_id = pc.id
        LEFT JOIN public.card_variant cv                          ON cv.id = pc.card_variant_id
        LEFT JOIN public.collection_layout_slot_expected_content e ON e.slot_id = sl.id
    )
    SELECT
        v.page_number,
        v.row_index,
        v.column_index,
        CASE
            WHEN v.own_variant_id IS NOT NULL THEN 'CARD'
            WHEN v.own_expected_card_id IS NOT NULL THEN 'RESERVED'
            ELSE 'EMPTY'
        END,
        coalesce(c.name, ec.name)::TEXT,
        coalesce(c.collector_number, ec.collector_number)::TEXT,
        coalesce(c.collector_total, ec.collector_total),
        coalesce(cs.code, ecs.code)::TEXT,
        CASE
            WHEN v.own_variant_id IS NOT NULL THEN nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')
            WHEN v.own_expected_card_id IS NOT NULL THEN evt.name
        END::TEXT,
        l.code::TEXT,
        coalesce(pimg.storage_path, eimg.storage_path)::TEXT
    FROM v
    LEFT JOIN public.card_variant cv                  ON cv.id = v.own_variant_id
    LEFT JOIN public.card c                           ON c.id = cv.card_id
    LEFT JOIN public.card_set cs                      ON cs.id = c.card_set_id
    LEFT JOIN public.card_variant_type vt             ON vt.id = cv.variant_type_id
    LEFT JOIN public.card_printing_profile pp         ON pp.id = cv.printing_profile_id
    LEFT JOIN public.card_edition_context_profile ecx ON ecx.id = cv.edition_context_profile_id
    LEFT JOIN public.language l                       ON l.id = v.own_language_id
    -- a reserva só aparece quando não há carta desta coleção no bolso
    LEFT JOIN public.card ec
           ON ec.id = v.own_expected_card_id AND v.own_variant_id IS NULL
    LEFT JOIN public.card_set ecs                     ON ecs.id = ec.card_set_id
    LEFT JOIN public.card_variant_type evt
           ON evt.id = v.own_expected_type_id AND v.own_variant_id IS NULL
    LEFT JOIN LATERAL (
        SELECT ast.storage_path
        FROM public.card_asset ast
        JOIN public.card_asset_type cat ON cat.id = ast.asset_type_id AND cat.code = 'CARD_FRONT'
        JOIN public.language al         ON al.id = ast.language_id
        WHERE c.id IS NOT NULL
          AND ast.card_id = c.id
          AND ast.is_primary
          AND ast.is_active
          AND ast.storage_path IS NOT NULL
        ORDER BY (ast.language_id = v.own_language_id) DESC NULLS LAST,
                 (al.code = 'pt-BR') DESC,
                 (al.code = 'en') DESC,
                 al.language_order ASC
        LIMIT 1
    ) pimg ON true
    LEFT JOIN LATERAL (
        SELECT ast.storage_path
        FROM public.card_asset ast
        JOIN public.card_asset_type cat ON cat.id = ast.asset_type_id AND cat.code = 'CARD_FRONT'
        JOIN public.language al         ON al.id = ast.language_id
        WHERE ec.id IS NOT NULL
          AND ast.card_id = ec.id
          AND ast.is_primary
          AND ast.is_active
          AND ast.storage_path IS NOT NULL
        ORDER BY (al.code = 'pt-BR') DESC,
                 (al.code = 'en') DESC,
                 al.language_order ASC
        LIMIT 1
    ) eimg ON true
    ORDER BY v.page_number, v.row_index, v.column_index;
END;
$$;

REVOKE ALL ON FUNCTION public.collection_binder_masked_pages(UUID, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
