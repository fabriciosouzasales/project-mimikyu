/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5084 - Create collection_master_set_scope_positions Function
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Read model NOVO, específico de `MASTER_SET` — decisão fechada em
MODELING-REVISION-01 (item 7)/MODELING-FINAL-FIX-02: `collection_
completion_positions()` (5071, Card-oriented) permanece EXATAMENTE
como está, contrato intocado, zero risco a qualquer consumer futuro.
Grão desta função nova é 1 linha por `card_variant_id` adotada no
Scope — genuinamente diferente do grão de `5071` (1 linha por Card),
porque uma mesma Card pode ter várias Variants adotadas
simultaneamente no Master Set.

AUDITORIA DE `variant_type` (MODELING-REVISION-01, item 7, confirmada
não-assumida): `public.card_variant` NÃO tem coluna `variant_type_code`
— tem `variant_type_id UUID NOT NULL REFERENCES card_variant_type(id)`.
`code`/`name`/`display_order` moram em `card_variant_type`, exigindo
`JOIN` explícito (ver `docs/05b-cartas-e-raridade.md`, tabela
`card_variant_type`). Contrato de retorno construído com esse `JOIN`.

Mesma fronteira de autorização e mesma disciplina `SECURITY DEFINER`
de `5070`/`5071`/`5083` — ownership reconstituído manualmente na CTE
`target` (`c.owner_user_id = (select auth.uid())`, sempre primeiro
passo, antes de qualquer tabela do Catálogo Editorial), `mode =
'REFERENCE_BASED' AND completion_policy = 'MASTER_SET'` explícito
(Collection `STANDARD_SET`/`OPEN_CURATION`/inexistente/de outro Owner
-> 0 rows, mesma forma, não-enumerável).

`satisfied` é calculado por correspondência EXATA de `card_variant_id`
entre `physical_card` e o Scope (LDM-19) — nunca "qualquer Variant da
mesma Card", mesmo raciocínio de `5083`/ramo MASTER_SET.
`p_only_missing BOOLEAN DEFAULT FALSE` — mesmo padrão de nome
explícito de `5071` (nunca um nome de função que já pressuponha
"faltantes").

Ordenação determinística: `card.collector_order`, `card.collector_
number` (mesmo desempate de `5071`), mais `card_variant_type.
display_order` como terceiro nível — necessário aqui e não em `5071`,
porque uma mesma Card pode aparecer em múltiplas linhas (uma por
Variant adotada), então precisa de um critério de ordem estável entre
elas.

`EXECUTE` revogado de `PUBLIC`/`anon`, concedido só a `authenticated`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_master_set_scope_positions(
    p_collection_id UUID,
    p_only_missing  BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    card_variant_id   UUID,
    card_id           UUID,
    collector_number  VARCHAR(20),
    name              VARCHAR(200),
    variant_type_code VARCHAR(50),
    variant_type_name VARCHAR(100),
    is_satisfied      BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        -- Fronteira de autorização: idêntica em espírito a 5070/5071 —
        -- ownership reconstituído manualmente, primeiro passo.
        SELECT
            c.id AS collection_id
        FROM public.collection c
        WHERE c.id = p_collection_id
          AND (select auth.uid()) IS NOT NULL          -- defesa explícita, nunca is_admin()
          AND c.owner_user_id = (select auth.uid())    -- ownership reconstituído manualmente
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'MASTER_SET'
    ),
    satisfied AS (
        SELECT DISTINCT pc.card_variant_id
        FROM target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.physical_card pc
            ON pc.id = ca.physical_card_id
    )
    SELECT
        s.card_variant_id                 AS card_variant_id,
        card.id                           AS card_id,
        card.collector_number             AS collector_number,
        card.name                         AS name,
        cvt.code                          AS variant_type_code,
        cvt.name                          AS variant_type_name,
        (sat.card_variant_id IS NOT NULL) AS is_satisfied
    FROM target t
    JOIN public.collection_master_set_scope s
        ON s.collection_id = t.collection_id
    JOIN public.card_variant cv
        ON cv.id = s.card_variant_id
    JOIN public.card card
        ON card.id = cv.card_id
    JOIN public.card_variant_type cvt
        ON cvt.id = cv.variant_type_id
    LEFT JOIN satisfied sat
        ON sat.card_variant_id = s.card_variant_id
    WHERE (NOT p_only_missing) OR sat.card_variant_id IS NULL
    ORDER BY card.collector_order, card.collector_number, cvt.display_order, card.id;
$$;

REVOKE ALL ON FUNCTION public.collection_master_set_scope_positions(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_master_set_scope_positions(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.collection_master_set_scope_positions(uuid, boolean) TO authenticated;
