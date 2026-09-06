/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5100 - Update collection_completion_summary Function (v4.0 — ramo REFERENCE_POSITION)
Versão......: 4.0 (estende 5083 v3.0, 02F)
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-STAGING-01,
               após -PHYSICAL-MODELING-AUDIT-01 e -PHYSICAL-MODELING-
               REVISION-01, ambas read-only)

Descrição...:
Estende `collection_completion_summary()` (CANÔNICA desde `5070` v2.0,
02E; estendida para MASTER_SET em `5083` v3.0, 02F) para suportar
`REFERENCE_POSITION` (Collections Pokédex, LDM-177/179/180/181/184) —
terceiro ramo mutuamente exclusivo por construção, já que
`completion_policy` é um valor único por Collection. Contrato externo
de campos permanece idêntico (mesmo princípio já aplicado em 5083):
nenhum consumer futuro quebra.

DECISÃO CENTRAL (FATIA-E-MODELING-REVISION-01, item 2): a `target` CTE
existente (CARD_SET, usada por STANDARD_SET/MASTER_SET) NÃO foi tornada
polimórfica. Este arquivo adiciona quatro CTEs independentes e novas —
`reference_position_target`, `reference_position_scope`,
`reference_position_denom`, `reference_position_numer` — preservando
`target`/`standard_denom`/`standard_numer`/`master_denom`/`master_numer`
e o SELECT final byte-idênticos a `5083`. Mínimo blast radius: regressão
zero de STANDARD_SET/MASTER_SET (ver 5814, casos N/O).

`reference_position_target`: mesma disciplina de fronteira de
autorização de `target` — primeiro passo da query, ownership
reconstituído manualmente, `auth.uid() IS NOT NULL` explícito, nunca
`is_admin()`. Filtra `c.mode = 'REFERENCE_BASED'` AND
`c.completion_policy = 'REFERENCE_POSITION'`, join explícito
`collection -> collection_reference (reference_kind='POKEDEX') ->
collection_pokedex_reference`. Não há autorização posterior em nenhuma
CTE downstream — todas dependem de `reference_position_target` já
filtrado.

`reference_position_scope` (LDM-177): grão = 1 linha por
`pokedex_position_id` do Scope corrente da Collection. `UNION ALL` de
dois ramos mutuamente exclusivos por construção (`scope_kind` é valor
único por Collection Pokédex Reference):
- FULL_REFERENCE: todas as `pokedex_position` da Pokédex referenciada;
- GENERATION_FILTERED: `pokedex_position -> pokemon_species ->
  collection_pokedex_scope_generation` casado por `generation_id` E
  `collection_reference_id` (nunca vaza para outra Collection).

CORREÇÃO CENTRAL DESTA RODADA (FATIA-E-MODELING-REVISION-01, item 1) —
numerator Scope-aware: `reference_position_numer` NÃO conta todo
`collection_pokedex_position_assignment` da Collection (isso incluiria
Assignments preservados fora do Scope corrente, violando LDM-177/
LDM-181). O numerator é construído como
`reference_position_scope INNER JOIN collection_allocation (pela
collection_id) INNER JOIN collection_pokedex_position_assignment (pela
collection_allocation_id E pela mesma pokedex_position_id do Scope)` —
um Assignment cuja `pokedex_position_id` não aparece em
`reference_position_scope` simplesmente nunca casa neste JOIN: ele
permanece fisicamente preservado na tabela, mas não contribui nem para
o denominator nem para o numerator. SPECIES_MATCH e USER_OVERRIDE
contam igualmente (nenhum filtro em `assignment_basis`). Nunca consulta
Primary Representative nem `card_primary_species` (LDM-182/184 são
responsabilidade de outra fatia, não de completion).

`reference_position_denom`: shape idêntico a `standard_denom`/
`master_denom` (`collection_id UUID, completion_policy TEXT,
total_positions BIGINT`) — `count(...)` retorna BIGINT nativamente,
nunca casteado para INTEGER. Construído via `LEFT JOIN` de
`reference_position_target` (no máximo 1 linha, pela própria
`p_collection_id`) contra `reference_position_scope`: quando o Scope
tem 0 linhas (GENERATION_FILTERED sem nenhuma Generation cobrindo
nenhuma Position, cenário estruturalmente raro mas não impossível),
`count()` de uma coluna do lado direito de um LEFT JOIN sem match
retorna 0 — zero-denominator preservado sem CASE adicional, mesmo
efeito líquido de `standard_denom`/`master_denom` (que usam o mesmo
padrão LEFT JOIN + count).

Zero-denominator no SELECT final: `total_positions = 0 ->
progress_percentage = 0.00, is_complete = false` — cláusula
inalterada, já cobre os três ramos por construção (não referencia
nenhum ramo por nome).

UNION FINAL: `denom`/`numer` passam de 2 branches (`UNION ALL` de
standard/master) para 3 (`UNION ALL` de standard/master/
reference_position). SELECT final permanece semanticamente idêntico —
nenhuma coluna nova, nenhuma lógica condicional por policy no SELECT
externo (a policy já vem resolvida de dentro de cada branch).

Segurança inalterada da v3.0: `LANGUAGE SQL`, `STABLE`, `SECURITY
DEFINER`, `SET search_path = ''`, ownership reconstituído manualmente
em CADA target CTE (nunca uma única checagem compartilhada entre
branches), `(select auth.uid()) IS NOT NULL` explícito. Não-enumeração
preservada: Collection inexistente/de outro Owner/policy incompatível
(STANDARD_SET/MASTER_SET não entram no ramo REFERENCE_POSITION, e
vice-versa) -> 0 rows daquele ramo, nunca erro. `REVOKE ALL FROM
PUBLIC`/`anon` + `GRANT EXECUTE TO authenticated`, inalterado.

Performance: nenhum índice novo nesta rodada (decisão explícita do
mandato de staging, item 8) — plano a ser medido em 5815 contra os
cenários listados (FULL_REFERENCE 1025, GENERATION_FILTERED, 0
Assignments, parcial, completa, duplicatas por Position, Assignments
fora do Scope). Índice já existente relevante:
`idx_collection_pokedex_position_assignment_position_id` (Query 6117)
cobre o lado `pokedex_position_id` do JOIN de
`reference_position_numer`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

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

    -- Ramo STANDARD_SET (inalterado de 5070 v2.0/5083 v3.0): denominador
    -- = Card do Card Set referenciado; numerador = Card satisfeita por
    -- qualquer Variant daquela Card alocada à Collection.
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

    -- Ramo MASTER_SET (inalterado de 5083 v3.0): denominador = Adopted
    -- Scope; numerador = Variant do Scope com correspondência EXATA de
    -- Physical Card alocada (LDM-19/LDM-20/LDM-21).
    master_denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(s.card_variant_id) AS total_positions
        FROM target t
        LEFT JOIN public.collection_master_set_scope s
            ON s.collection_id = t.collection_id
        WHERE t.completion_policy = 'MASTER_SET'
        GROUP BY t.collection_id, t.completion_policy
    ),
    master_numer AS (
        SELECT
            t.collection_id,
            count(DISTINCT s.card_variant_id) AS satisfied_positions
        FROM target t
        JOIN public.collection_master_set_scope s
            ON s.collection_id = t.collection_id
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.physical_card pc
            ON pc.id = ca.physical_card_id
           AND pc.card_variant_id = s.card_variant_id   -- correspondência EXATA de Variant
        WHERE t.completion_policy = 'MASTER_SET'
        GROUP BY t.collection_id
    ),

    -- ============================================================
    -- Ramo REFERENCE_POSITION (novo, Fatia E) — Collections Pokédex.
    -- Independente de `target` (CARD_SET-específico) por desenho
    -- explícito (FATIA-E-MODELING-REVISION-01, item 2).
    -- ============================================================

    -- Fronteira de autorização própria deste ramo — mesma disciplina
    -- de `target`, mas contra o subtipo POKEDEX.
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

    -- Numerador CORRIGIDO (FATIA-E-MODELING-REVISION-01, item 1):
    -- Positions do Scope corrente INTERSECTADAS com Positions que
    -- possuem >= 1 Assignment da mesma Collection. Um Assignment fora
    -- do Scope nunca casa com nenhuma linha de reference_position_scope
    -- (o JOIN exige pokedex_position_id igual a uma linha do Scope) —
    -- por isso permanece preservado fisicamente, mas nunca conta aqui.
    -- SPECIES_MATCH e USER_OVERRIDE contam igualmente (sem filtro em
    -- assignment_basis). Nunca consulta Primary Representative nem
    -- card_primary_species.
    reference_position_numer AS (
        SELECT
            t.collection_id,
            count(DISTINCT s.pokedex_position_id) AS satisfied_positions
        FROM reference_position_target t
        JOIN reference_position_scope s
            ON s.collection_id = t.collection_id
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a
            ON a.collection_allocation_id = ca.id
           AND a.pokedex_position_id = s.pokedex_position_id
        GROUP BY t.collection_id
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
