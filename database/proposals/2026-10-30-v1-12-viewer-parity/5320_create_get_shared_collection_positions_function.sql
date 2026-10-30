/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5320 - Create get_shared_collection_positions()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12 VIEWER EXPERIENCE PARITY
              CORRECTION-02) — depende de 5302 (collection_share_role)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Grade "Todas · Tenho · Faltam" da coleção de Set para o participante
VIEWER — a mesma navegação da página do titular (R2/5169), com a mesma
regra de satisfação (5071) e a mesma ordem do Set.

Dado mínimo que falta hoje ao participante: as POSIÇÕES do Set
referenciado pela coleção (carta + arte + "tenho"/"falta" + exemplares
NESTA coleção). 5313 só traz as cartas alocadas, então "Faltam" não pode
ser reproduzido sem esta leitura.

Diferença deliberada em relação à 5169 (privacidade):
- NÃO devolve `copies_available` (exemplares do titular fora de qualquer
  coleção): isso é o acervo privado do titular (C-157). Por isso a tag
  "No seu acervo" não existe para o participante.

Regras de Negócio:
- Acesso por collection_share_role() (5302) ANTES de qualquer leitura:
  só 'OWNER' ou 'VIEWER' (participação ACTIVE). PUBLIC, PENDING,
  DECLINED, revogado, anon → zero linhas (indistinguível de inexistente).
- Só coleções REFERENCE_BASED + STANDARD_SET com Set de referência
  (mesmo recorte da 5169); qualquer outra → zero linhas.
- Lê apenas: catálogo do Set referenciado + alocações DESTA coleção.
  Nunca inventory, nunca exemplares de outras coleções, nunca local,
  condição, valor ou datas.
- Paginado: p_limit 1..500, p_offset ≥ 0; total_count do filtro antes
  da paginação.
- Custo: um passo pelas alocações da coleção (ix por collection_id) +
  cartas do Set (ix por card_set_id) + 1 asset por linha da página.
  Mesmo perfil da 5169, sem o CTE `available`.

Segurança: SECURITY DEFINER, STABLE, search_path '', EXECUTE só
authenticated (REVOKE de PUBLIC e anon). Sem escrita.

Erros: 22023 INVALID_FILTER / INVALID_PAGE.
Como validar: 5862 (casos P1–P8).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection_positions(
    p_collection_id UUID,
    p_filter        TEXT    DEFAULT 'ALL',
    p_limit         INTEGER DEFAULT 200,
    p_offset        INTEGER DEFAULT 0
)
RETURNS TABLE (
    card_id              UUID,
    collector_number     TEXT,
    collector_total      INTEGER,
    card_name            TEXT,
    image_path           TEXT,
    is_satisfied         BOOLEAN,
    copies_in_collection INTEGER,
    total_count          BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
    v_filter TEXT := upper(btrim(coalesce(p_filter, 'ALL')));
    v_role   TEXT;
    v_set    UUID;
BEGIN
    IF v_filter NOT IN ('ALL', 'OWNED', 'MISSING') THEN
        RAISE EXCEPTION 'INVALID_FILTER' USING ERRCODE = '22023';
    END IF;
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 OR p_offset IS NULL OR p_offset < 0 OR p_offset > 100000 THEN
        RAISE EXCEPTION 'INVALID_PAGE' USING ERRCODE = '22023';
    END IF;
    IF p_collection_id IS NULL THEN
        RETURN;
    END IF;

    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RETURN;
    END IF;

    SELECT ccsr.card_set_id INTO v_set
    FROM public.collection c
    JOIN public.collection_reference cr            ON cr.collection_id = c.id
    JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
    WHERE c.id = p_collection_id
      AND c.mode = 'REFERENCE_BASED'
      AND c.completion_policy = 'STANDARD_SET';
    IF v_set IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH in_collection AS (
        SELECT cv.card_id, count(*)::INTEGER AS copies, min(pc.language_id::TEXT)::UUID AS lang
        FROM public.collection_allocation ca
        JOIN public.physical_card pc ON pc.id = ca.physical_card_id
        JOIN public.card_variant cv  ON cv.id = pc.card_variant_id
        WHERE ca.collection_id = p_collection_id
        GROUP BY cv.card_id
    ),
    positions AS (
        SELECT c.id, c.collector_number::TEXT AS number, c.collector_total, c.name::TEXT AS card_name,
               c.collector_order,
               ic.copies AS in_copies, ic.lang,
               (ic.card_id IS NOT NULL) AS satisfied
        FROM public.card c
        LEFT JOIN in_collection ic ON ic.card_id = c.id
        WHERE c.card_set_id = v_set
    ),
    filtered AS (
        SELECT p.*, count(*) OVER () AS total
        FROM positions p
        WHERE v_filter = 'ALL'
           OR (v_filter = 'OWNED' AND p.satisfied)
           OR (v_filter = 'MISSING' AND NOT p.satisfied)
        ORDER BY p.collector_order, p.number, p.id
        LIMIT p_limit OFFSET p_offset
    )
    SELECT f.id, f.number, f.collector_total, f.card_name,
           img.storage_path::TEXT,
           f.satisfied,
           coalesce(f.in_copies, 0),
           f.total
    FROM filtered f
    LEFT JOIN LATERAL (
        SELECT ast.storage_path
        FROM public.card_asset ast
        JOIN public.card_asset_type cat ON cat.id = ast.asset_type_id AND cat.code = 'CARD_FRONT'
        JOIN public.language al         ON al.id = ast.language_id
        WHERE ast.card_id = f.id
          AND ast.is_primary
          AND ast.is_active
          AND ast.storage_path IS NOT NULL
        ORDER BY (ast.language_id = f.lang) DESC NULLS LAST,
                 (al.code = 'pt-BR') DESC,
                 (al.code = 'en') DESC,
                 al.language_order ASC
        LIMIT 1
    ) img ON true
    ORDER BY f.collector_order, f.number, f.id;
END;
$$;

COMMENT ON FUNCTION public.get_shared_collection_positions(UUID, TEXT, INTEGER, INTEGER) IS
  'V1-12 (Query 5320): posições do Set de uma coleção STANDARD_SET para titular/participante VIEWER (5302) — arte, satisfação (regra 5071) e exemplares NESTA coleção. Sem acervo do titular (sem copies_available). Filtro ALL/OWNED/MISSING, paginado (≤ 500). Sem acesso → zero linhas.';

REVOKE ALL ON FUNCTION public.get_shared_collection_positions(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_positions(UUID, TEXT, INTEGER, INTEGER) TO authenticated;
