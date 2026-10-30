/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5313 - Create get_shared_collection_cards()
Versão......: 1.1 (V1-12 PUBLIC BINDER EXPERIENCE: só participante)
Status......: PROPOSTA — NÃO EXECUTADA (V1-12) — depende de 5300–5302
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Galeria somente leitura das cartas ALOCADAS à coleção (C-157), agrupadas
por versão + idioma, para o titular e o participante VIEWER. Desde a v1.1
o visitante de coleção pública NÃO lê a galeria: a vitrine pública é só o
fichário (5317/5318).

Regras de Negócio:
- Acesso por collection_share_role() (5302) checado ANTES de qualquer
  leitura de exemplares; sem acesso → zero linhas.
- Só exemplares com collection_allocation nesta coleção — nunca o acervo
  do titular (C-157), nunca exemplares de outras coleções.
- Projeção de catálogo + quantidade: nome, número, Set, versão, idioma,
  imagem, códigos de acabamento/raridade. NUNCA: id do exemplar, local
  físico, condição, certificação, valor, datas de aquisição (C-158–C-161).
  A ordem usa a data de entrada na coleção, que não é devolvida.
- Página de 1..96 linhas; offset ≤ 100000; total_count em cada linha.
- Custo: um passo por alocação da coleção (ix_collection_allocation_collection)
  + catálogo só das linhas da página.
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection_cards(
    p_collection_id UUID,
    p_limit INTEGER DEFAULT 48,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    card_variant_id UUID,
    language_code TEXT,
    card_name TEXT,
    collector_number TEXT,
    collector_total INTEGER,
    card_set_code TEXT,
    card_set_name TEXT,
    variant_label TEXT,
    variant_type_code TEXT,
    rarity_code TEXT,
    copies_count INTEGER,
    image_path TEXT,
    total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
BEGIN
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 96
       OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 THEN
        RAISE EXCEPTION 'INVALID_PAGE' USING ERRCODE = '22023';
    END IF;

    IF coalesce(public.collection_share_role(p_collection_id), '') NOT IN ('OWNER', 'VIEWER') THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH grouped AS (
        SELECT pc.card_variant_id, pc.language_id,
               count(*)::integer AS n, max(ca.created_at) AS last_added
        FROM public.collection_allocation ca
        JOIN public.physical_card pc ON pc.id = ca.physical_card_id
        WHERE ca.collection_id = p_collection_id
        GROUP BY pc.card_variant_id, pc.language_id
    ),
    page AS (
        SELECT g.*, count(*) OVER () AS total
        FROM grouped g
        ORDER BY g.last_added DESC, g.card_variant_id, g.language_id
        LIMIT p_limit OFFSET p_offset
    )
    SELECT
        pg.card_variant_id,
        l.code::text,
        c.name::text,
        c.collector_number::text,
        c.collector_total,
        cs.code::text,
        cs.name::text,
        nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
        vt.code::text,
        r.code::text,
        pg.n,
        img.storage_path::text,
        pg.total
    FROM page pg
    JOIN public.card_variant cv ON cv.id = pg.card_variant_id
    JOIN public.card c          ON c.id = cv.card_id
    JOIN public.card_set cs     ON cs.id = c.card_set_id
    JOIN public.language l      ON l.id = pg.language_id
    LEFT JOIN public.card_variant_type vt            ON vt.id = cv.variant_type_id
    LEFT JOIN public.rarity r                        ON r.id = c.rarity_id
    LEFT JOIN public.card_printing_profile pp        ON pp.id = cv.printing_profile_id
    LEFT JOIN public.card_edition_context_profile ec ON ec.id = cv.edition_context_profile_id
    LEFT JOIN LATERAL (
        SELECT ast.storage_path
        FROM public.card_asset ast
        JOIN public.card_asset_type cat ON cat.id = ast.asset_type_id AND cat.code = 'CARD_FRONT'
        JOIN public.language al ON al.id = ast.language_id
        WHERE ast.card_id = c.id
          AND ast.is_primary
          AND ast.is_active
          AND ast.storage_path IS NOT NULL
        ORDER BY (ast.language_id = pg.language_id) DESC,
                 (al.code = 'pt-BR') DESC,
                 (al.code = 'en') DESC,
                 al.language_order ASC
        LIMIT 1
    ) img ON true
    ORDER BY pg.last_added DESC, pg.card_variant_id, pg.language_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection_cards(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_cards(UUID, INTEGER, INTEGER) TO authenticated;
