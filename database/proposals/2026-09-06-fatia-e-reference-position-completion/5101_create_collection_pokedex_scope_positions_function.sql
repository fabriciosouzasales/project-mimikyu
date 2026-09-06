/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5101 - Create collection_pokedex_scope_positions Function
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-STAGING-01,
               após -PHYSICAL-MODELING-AUDIT-01 e -PHYSICAL-MODELING-
               REVISION-01, ambas read-only)

Descrição...:
Read model específico de Collections Pokédex (REFERENCE_POSITION),
espelho direto de `collection_master_set_scope_positions()` (Query
5084, precedente arquitetural congelado em FATIA-E-MODELING-
REVISION-01, item 3): as Positions do Scope corrente da Collection
(LDM-177) mais a satisfação de cada uma (LDM-179/180/181), sem nenhum
dado de UX, Primary Representative, Physical Card ou Card/Card Variant.

Assinatura, contrato e nome CONGELADOS pelo mandato de revisão:
`public.collection_pokedex_scope_positions(p_collection_id UUID,
p_only_missing BOOLEAN DEFAULT FALSE) RETURNS TABLE
(pokedex_position_id UUID, position_number INTEGER, species_id UUID,
species_name VARCHAR(150), is_satisfied BOOLEAN)`.

OWNERSHIP NO TARGET (mandato item 6, obrigatório): toda a fronteira de
autorização vive na CTE `target` — mesma fronteira do ramo
REFERENCE_POSITION de `5100`, byte-a-byte: `auth.uid() IS NOT NULL`
explícito, `owner_user_id = auth.uid()`, `mode = 'REFERENCE_BASED'`,
`completion_policy = 'REFERENCE_POSITION'`, `reference_kind =
'POKEDEX'`. Nenhuma subquery posterior revalida owner — `scope` e
`satisfied` dependem inteiramente de `target` já filtrado, mesmo
padrão de `5084` (que também resolve tudo dentro de `target`).

`scope` (LDM-177): mesma semântica de `reference_position_scope` de
`5100` (UNION ALL de FULL_REFERENCE/GENERATION_FILTERED, mutuamente
exclusivos por `scope_kind`), acrescida de `position_number`,
`species_id` e `pokemon_species.canonical_name AS species_name` — os
três campos exigidos pelo contrato que `5100` não precisa expor.

`satisfied` (LDM-179/180/181): CTE própria, mesmo estilo de `5084` —
`target -> collection_allocation -> collection_pokedex_position_
assignment`, `SELECT DISTINCT pokedex_position_id`. A relação com
`scope` acontece só no SELECT final via `LEFT JOIN` — como `scope` já
exclui por construção qualquer Position fora do Scope corrente, um
Assignment fora do Scope nunca aparece aqui: ele nunca teve como entrar
em `satisfied` porque `satisfied` já faz o JOIN contra `scope`
internamente (mesmo raciocínio do numerator corrigido de `5100`).
SPECIES_MATCH e USER_OVERRIDE contam igualmente (sem filtro em
`assignment_basis`). Nunca consulta Primary Representative nem
`card_primary_species`.

`p_only_missing = TRUE`: filtra para `sat.pokedex_position_id IS
NULL` no SELECT final — mesmo padrão de `5084`.

Ordenação determinística obrigatória (mandato item 6): `ORDER BY
position_number, pokedex_position_id` — não opcional, garante contrato
estável para paginação/exibição futura no frontend.

Fora do contrato, deliberadamente ausentes (mandato item 6): Primary
Representative, `assignment_count`, Physical Card, Card/Card Variant,
imagens, qualquer campo de UX.

Segurança: mesmo padrão de `5084`/`5100` — `LANGUAGE SQL`, `STABLE`,
`SECURITY DEFINER`, `SET search_path = ''`, `REVOKE ALL FROM PUBLIC`/
`anon` + `GRANT EXECUTE TO authenticated`. Não-enumeração: Collection
inexistente, de outro Owner, `mode` diferente de REFERENCE_BASED, ou
`completion_policy` diferente de REFERENCE_POSITION -> `target` produz
0 linhas -> função inteira retorna 0 linhas, nunca erro.

Performance: nenhum índice novo nesta rodada (mandato item 8) — a
medir em 5815. Índices existentes relevantes: as duas UNIQUE de
`pokedex_position(pokedex_id, ...)` (Query 6040) cobrem o JOIN de
`scope`; `idx_collection_pokedex_position_assignment_position_id`
(Query 6117) cobre o JOIN de `satisfied`.

Pré-requisitos:
- Query 5087/5091 - Collection Pokedex Reference / Scope Generation.
- Query 6040 - Pokedex Position Table.
- Query 6117 - Collection Pokedex Position Assignment Table.
- Query 5100 (mesma rodada) - ramo REFERENCE_POSITION de
  collection_completion_summary(), mesma fronteira de autorização.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_pokedex_scope_positions(
    p_collection_id UUID,
    p_only_missing  BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    pokedex_position_id UUID,
    position_number      INTEGER,
    species_id           UUID,
    species_name         VARCHAR(150),
    is_satisfied         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        -- Fronteira de autorização: primeiro passo da query, antes de
        -- qualquer tabela do Catálogo Pokémon. Mesma fronteira,
        -- byte-a-byte, do ramo REFERENCE_POSITION de 5100. Nenhuma
        -- subquery posterior revalida owner.
        SELECT
            c.id                 AS collection_id,
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

    -- Positions do Scope corrente (LDM-177), acrescidas dos campos de
    -- exibição exigidos pelo contrato (position_number, species_id,
    -- species_name). UNION ALL de dois ramos mutuamente exclusivos por
    -- construção (scope_kind é valor único por Reference).
    scope AS (
        SELECT
            t.collection_id,
            pp.id               AS pokedex_position_id,
            pp.position_number  AS position_number,
            pp.species_id       AS species_id,
            sp.canonical_name   AS species_name
        FROM target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp
            ON sp.id = pp.species_id
        WHERE t.scope_kind = 'FULL_REFERENCE'

        UNION ALL

        SELECT
            t.collection_id,
            pp.id               AS pokedex_position_id,
            pp.position_number  AS position_number,
            pp.species_id       AS species_id,
            sp.canonical_name   AS species_name
        FROM target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp
            ON sp.id = pp.species_id
        JOIN public.collection_pokedex_scope_generation spg
            ON spg.collection_reference_id = t.reference_id
           AND spg.generation_id = sp.generation_id
        WHERE t.scope_kind = 'GENERATION_FILTERED'
    ),

    -- Positions satisfeitas (LDM-179/180/181): >= 1 Assignment da
    -- mesma Collection para aquela Position. SPECIES_MATCH e
    -- USER_OVERRIDE contam igualmente. Nunca consulta Primary
    -- Representative nem card_primary_species. O JOIN contra `scope`
    -- aqui dentro é o que naturalmente torna invisível qualquer
    -- Assignment fora do Scope corrente — ele nunca produz linha nesta
    -- CTE, mesmo permanecendo fisicamente preservado na tabela.
    satisfied AS (
        SELECT DISTINCT s.pokedex_position_id
        FROM target t
        JOIN scope s
            ON s.collection_id = t.collection_id
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a
            ON a.collection_allocation_id = ca.id
           AND a.pokedex_position_id = s.pokedex_position_id
    )
    SELECT
        s.pokedex_position_id,
        s.position_number,
        s.species_id,
        s.species_name,
        (sat.pokedex_position_id IS NOT NULL) AS is_satisfied
    FROM scope s
    LEFT JOIN satisfied sat
        ON sat.pokedex_position_id = s.pokedex_position_id
    WHERE (NOT p_only_missing) OR sat.pokedex_position_id IS NULL
    ORDER BY
        s.position_number,
        s.pokedex_position_id;
$$;

REVOKE ALL ON FUNCTION public.collection_pokedex_scope_positions(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_pokedex_scope_positions(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.collection_pokedex_scope_positions(uuid, boolean) TO authenticated;
