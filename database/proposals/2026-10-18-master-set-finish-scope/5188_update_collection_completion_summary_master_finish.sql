/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5188 - collection_completion_summary() v6.0: ramo
              MASTER_SET por acabamento
Versão......: 6.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Base: 5102 v5.0, idêntica ao LIVE (md5 do corpo normalizado
0a644fe6…, conferido em 2026-10-18). Mesma assinatura, mesmo tipo de
retorno, mesmas permissões.

Única mudança: CTEs master_denom/master_numer reescritas (+ master_target,
master_positions, master_owned). Ramos STANDARD_SET e REFERENCE_POSITION
copiados sem alteração (5836 caso 8.x confirma resultado idêntico
antes × depois para coleções STANDARD_SET e Pokédex).

Consumidores herdam a nova regra sem mudança: Biblioteca (5182/R1),
hero da coleção, prévia (5192) e RPCs de ativação/edição (5194/5195
devolvem o resumo).

Desempenho: uma chamada de master_set_positions por coleção; vínculos
lidos por ix_collection_allocation_collection. Medido em 5837.
Como validar: 5836 casos 3.x, 6.x, 7.x, 8.x.
================================================================
*/

begin;

CREATE OR REPLACE FUNCTION public.collection_completion_summary(
    p_collection_id UUID
)
RETURNS TABLE (
    collection_id       UUID,
    completion_policy   TEXT,
    total_positions     BIGINT,
    satisfied_positions BIGINT,
    missing_positions   BIGINT,
    progress_percentage NUMERIC,
    is_complete          BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        -- Fronteira de autorização: primeiro passo da query, antes de
        -- qualquer tabela do Catálogo Editorial. SECURITY DEFINER
        -- bypassa RLS, então ownership é reconstituído manualmente
        -- aqui — nunca iniciar por card/card_variant e checar
        -- ownership depois.
        SELECT
            c.id                AS collection_id,
            c.completion_policy AS completion_policy,
            ccsr.card_set_id    AS card_set_id
        FROM public.collection c
        JOIN public.collection_reference cr
            ON cr.collection_id = c.id
        JOIN public.collection_card_set_reference ccsr
            ON ccsr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND (select auth.uid()) IS NOT NULL          -- defesa explícita, nunca is_admin()
          AND c.owner_user_id = (select auth.uid())    -- ownership reconstituído manualmente
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy IN ('STANDARD_SET', 'MASTER_SET')
    ),

    -- Ramo STANDARD_SET (inalterado de 5070 v2.0/5083 v3.0/5100 v4.0):
    -- denominador = Card do Card Set referenciado; numerador = Card
    -- satisfeita por qualquer Variant daquela Card alocada à Collection.
    standard_denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(card.id) AS total_positions
        FROM target t
        LEFT JOIN public.card card
            ON card.card_set_id = t.card_set_id
        WHERE t.completion_policy = 'STANDARD_SET'
        GROUP BY t.collection_id, t.completion_policy
    ),
    standard_numer AS (
        SELECT
            t.collection_id,
            count(DISTINCT card.id) AS satisfied_positions
        FROM target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.physical_card pc
            ON pc.id = ca.physical_card_id
        JOIN public.card_variant cv
            ON cv.id = pc.card_variant_id
        JOIN public.card card
            ON card.id = cv.card_id
           AND card.card_set_id = t.card_set_id
        WHERE t.completion_policy = 'STANDARD_SET'
        GROUP BY t.collection_id
    ),

    -- Ramo MASTER_SET — ALTERADO em v6.0 (5188, MASTER-SET-DOCUMENTATION-
    -- AND-CONTRACT-PROPOSAL-01; LDM-192/LDM-193). Posições derivadas por
    -- master_set_positions() (5187) a partir dos acabamentos escolhidos
    -- (collection_master_set_finish, 5184). Satisfação por (carta,
    -- acabamento) — qualquer contexto, impressão ou idioma — ou, na
    -- posição de carta secreta (variant_type_id NULL), por qualquer
    -- variante da carta. Duplicatas não contam (contagem de posições).
    master_target AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            t.card_set_id,
            ARRAY(
                SELECT f.variant_type_id
                FROM public.collection_master_set_finish f
                WHERE f.collection_id = t.collection_id
            ) AS variant_type_ids
        FROM target t
        WHERE t.completion_policy = 'MASTER_SET'
    ),
    master_positions AS (
        SELECT
            mt.collection_id,
            p.card_id,
            p.variant_type_id
        FROM master_target mt
        CROSS JOIN LATERAL public.master_set_positions(mt.card_set_id, mt.variant_type_ids) p
    ),
    master_owned AS (
        SELECT DISTINCT
            cv.card_id,
            cv.variant_type_id
        FROM master_target mt
        JOIN public.collection_allocation ca
            ON ca.collection_id = mt.collection_id
        JOIN public.physical_card pc
            ON pc.id = ca.physical_card_id
        JOIN public.card_variant cv
            ON cv.id = pc.card_variant_id
    ),
    master_denom AS (
        SELECT
            mt.collection_id,
            mt.completion_policy,
            count(mp.card_id) AS total_positions
        FROM master_target mt
        LEFT JOIN master_positions mp
            ON mp.collection_id = mt.collection_id
        GROUP BY mt.collection_id, mt.completion_policy
    ),
    master_numer AS (
        SELECT
            mp.collection_id,
            count(*) AS satisfied_positions
        FROM master_positions mp
        WHERE EXISTS (
            SELECT 1
            FROM master_owned o
            WHERE o.card_id = mp.card_id
              AND (mp.variant_type_id IS NULL OR o.variant_type_id = mp.variant_type_id)
        )
        GROUP BY mp.collection_id
    ),

    -- ============================================================
    -- Ramo REFERENCE_POSITION (Fatia E). Independente de `target`
    -- (CARD_SET-específico) por desenho explícito (FATIA-E-MODELING-
    -- REVISION-01, item 2).
    -- ============================================================

    -- Fronteira de autorização própria deste ramo — mesma disciplina
    -- de `target`, mas contra o subtipo POKEDEX. INALTERADA em v5.0.
    reference_position_target AS (
        SELECT
            c.id                 AS collection_id,
            c.completion_policy  AS completion_policy,
            cr.id                AS reference_id,
            cpr.pokedex_id       AS pokedex_id,
            cpr.scope_kind       AS scope_kind
        FROM public.collection c
        JOIN public.collection_reference cr
            ON cr.collection_id = c.id
           AND cr.reference_kind = 'POKEDEX'
        JOIN public.collection_pokedex_reference cpr
            ON cpr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND (select auth.uid()) IS NOT NULL          -- defesa explícita, nunca is_admin()
          AND c.owner_user_id = (select auth.uid())    -- ownership reconstituído manualmente
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'REFERENCE_POSITION'
    ),

    -- Positions do Scope corrente (LDM-177). UNION ALL de dois ramos
    -- mutuamente exclusivos por construção (scope_kind é valor único
    -- por Collection Pokédex Reference) — nenhuma duplicidade possível.
    -- INALTERADA em v5.0.
    reference_position_scope AS (
        SELECT
            t.collection_id,
            pp.id AS pokedex_position_id
        FROM reference_position_target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        WHERE t.scope_kind = 'FULL_REFERENCE'

        UNION ALL

        SELECT
            t.collection_id,
            pp.id AS pokedex_position_id
        FROM reference_position_target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp
            ON sp.id = pp.species_id
        JOIN public.collection_pokedex_scope_generation spg
            ON spg.collection_reference_id = t.reference_id
           AND spg.generation_id = sp.generation_id
        WHERE t.scope_kind = 'GENERATION_FILTERED'
    ),

    -- Denominador: contagem de Positions do Scope corrente. Shape
    -- idêntico a standard_denom/master_denom. LEFT JOIN preserva
    -- zero-denominator (Scope vazio -> total_positions = 0) sem CASE
    -- adicional, mesmo padrão dos outros dois ramos.
    -- INALTERADA em v5.0.
    reference_position_denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(s.pokedex_position_id) AS total_positions
        FROM reference_position_target t
        LEFT JOIN reference_position_scope s
            ON s.collection_id = t.collection_id
        GROUP BY t.collection_id, t.completion_policy
    ),

    -- ============================================================
    -- NOVA em v5.0 (ALTERNATIVA B) — Positions satisfeitas da
    -- Collection, calculadas SEM referência ao Scope.
    --
    -- Caminho: reference_position_target -> collection_allocation
    -- (por collection_id, via ix_collection_allocation_collection)
    -- -> collection_pokedex_position_assignment (por
    -- collection_allocation_id, via a PK única da tabela — 1 sonda,
    -- no máximo 1 Assignment por Allocation).
    -- Custo esperado: Theta(|Allocations da Collection|).
    --
    -- O DISTINCT colapsa duplicatas: N Physical Cards distintas
    -- satisfazendo a MESMA Position produzem N Assignments com o mesmo
    -- pokedex_position_id, e uma única linha aqui.
    --
    -- Assignments FORA do Scope corrente entram neste conjunto — e são
    -- eliminados na interseção logo abaixo. Permanecem fisicamente
    -- preservados na tabela, exatamente como antes.
    --
    -- Nenhum filtro em assignment_basis: SPECIES_MATCH e USER_OVERRIDE
    -- contam igualmente. Nunca consulta Primary Representative,
    -- card_primary_species, physical_card ou card_variant.
    -- ============================================================
    reference_position_satisfied AS (
        SELECT DISTINCT
            t.collection_id,
            a.pokedex_position_id
        FROM reference_position_target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a
            ON a.collection_allocation_id = ca.id
    ),

    -- ============================================================
    -- ALTERADA em v5.0 (ALTERNATIVA B) — numerator como INTERSEÇÃO
    -- EXPLÍCITA entre o Scope corrente e as Positions satisfeitas.
    --
    -- Antes (5100 v4.0): reference_position_scope JOIN
    -- collection_allocation JOIN collection_pokedex_position_assignment,
    -- com scope e allocation como irmãos sem predicado entre si — custo
    -- medido Theta(|Scope| x |Allocations|).
    --
    -- Agora: os dois conjuntos já estão prontos e a interseção é uma
    -- junção 1:1 por (collection_id, pokedex_position_id) —
    -- Theta(|Scope| + |satisfeitas|).
    --
    -- Conjunto resultante PROVADAMENTE idêntico: as Positions do Scope
    -- que possuem >= 1 Assignment na Collection.
    --
    -- count(DISTINCT ...) mantido literal em relação a v4.0 por
    -- segurança semântica (a junção já é 1:1; o DISTINCT é redundante
    -- mas inofensivo sobre no máximo |Scope| linhas).
    -- ============================================================
    reference_position_numer AS (
        SELECT
            s.collection_id,
            count(DISTINCT s.pokedex_position_id) AS satisfied_positions
        FROM reference_position_scope s
        JOIN reference_position_satisfied sat
            ON sat.collection_id        = s.collection_id
           AND sat.pokedex_position_id  = s.pokedex_position_id
        GROUP BY s.collection_id
    ),

    denom AS (
        SELECT * FROM standard_denom
        UNION ALL
        SELECT * FROM master_denom
        UNION ALL
        SELECT * FROM reference_position_denom
    ),
    numer AS (
        SELECT * FROM standard_numer
        UNION ALL
        SELECT * FROM master_numer
        UNION ALL
        SELECT * FROM reference_position_numer
    )
    SELECT
        d.collection_id,
        d.completion_policy,
        d.total_positions,
        COALESCE(n.satisfied_positions, 0) AS satisfied_positions,
        d.total_positions - COALESCE(n.satisfied_positions, 0) AS missing_positions,
        CASE
            WHEN d.total_positions = 0 THEN 0.00
            ELSE round(
                (COALESCE(n.satisfied_positions, 0)::NUMERIC / d.total_positions::NUMERIC) * 100,
                2
            )
        END AS progress_percentage,
        CASE
            WHEN d.total_positions = 0 THEN FALSE
            ELSE COALESCE(n.satisfied_positions, 0) = d.total_positions
        END AS is_complete
    FROM denom d
    LEFT JOIN numer n ON n.collection_id = d.collection_id;
$$;

REVOKE ALL ON FUNCTION public.collection_completion_summary(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_completion_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.collection_completion_summary(uuid) TO authenticated;

commit;
