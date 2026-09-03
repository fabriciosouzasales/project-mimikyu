/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5083 - Update collection_completion_summary Function (v3.0)
Versão......: 3.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Estende `collection_completion_summary()` (CANÔNICA desde `5070` v2.0,
02E) para suportar `MASTER_SET` além de `STANDARD_SET` — decisão
fechada em MODELING-REVISION-01 (item 7)/MODELING-FINAL-FIX-02 (não
reaberto): **contrato externo de campos idêntico**, só o cálculo
interno muda por `completion_policy`. Nenhum consumer futuro quebra.

`target` amplia o filtro de `c.completion_policy = 'STANDARD_SET'`
para `c.completion_policy IN ('STANDARD_SET', 'MASTER_SET')` — ambos
exigem `mode = 'REFERENCE_BASED'`, inalterado. Como `completion_policy`
é um valor único por Collection, os dois ramos (`standard_*`/
`master_*`) são mutuamente exclusivos por construção — nunca os dois
produzem linha para a mesma Collection na mesma chamada. Implementado
como `UNION ALL` de dois pares de CTE independentes (mantém `LANGUAGE
sql`, sem necessidade de `plpgsql`/`CASE` de controle de fluxo).

Ramo STANDARD_SET: inalterado byte-a-byte em relação a `5070` v2.0
(denominador = Card do Card Set referenciado, numerador = Card com
>= 1 Physical Card alocada via qualquer Variant daquela Card).

Ramo MASTER_SET (novo): denominador = `COUNT(DISTINCT card_variant_id)`
do Adopted Scope (`collection_master_set_scope`) — LDM-20/LDM-21.
Numerador = `COUNT(DISTINCT card_variant_id)` do Scope com >= 1
Physical Card alocada cujo `card_variant_id` corresponda EXATAMENTE
(`pc.card_variant_id = s.card_variant_id`) — nunca "qualquer Variant
da mesma Card", diferença central em relação a `STANDARD_SET` (LDM-19).
Duplicatas de Physical Card da mesma Variant contam 1 só via
`DISTINCT`, mesmo padrão já validado em `5811`/workload D para
`STANDARD_SET`.

Zero-denominator: `total_positions = 0 -> progress_percentage = 0.00,
is_complete = false`, preservado para os dois ramos — mesma defesa em
profundidade de `5070`, mesmo sendo estruturalmente inatingível para
`MASTER_SET` ativo (garantido por `5076`/`5077`/`5075`): "estado
normal MASTER vazio é estruturalmente proibido", mas a defesa
permanece por barata e consistente (item 11 do mandato de staging).

Segurança inalterada da v2.0: `SECURITY DEFINER`, `STABLE`, `SET
search_path = ''`, ownership reconstituído manualmente na CTE `target`
(`c.owner_user_id = (select auth.uid())`, sempre primeiro passo),
`(select auth.uid()) IS NOT NULL` explícito, nunca `is_admin()`. Não-
enumeração preservada: Collection inexistente/de outro Owner/
`OPEN_CURATION`/`NONE` -> 0 rows, mesma forma nos quatro casos.
Catálogo Editorial permanece fechado — nenhuma policy nova em `card`/
`card_variant`/`card_set`, esta função só os lê através da própria
projeção `SECURITY DEFINER`. `REVOKE ALL FROM PUBLIC`/`anon` + `GRANT
EXECUTE TO authenticated`, inalterado.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
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

    -- Ramo STANDARD_SET (inalterado de 5070 v2.0): denominador = Card
    -- do Card Set referenciado; numerador = Card satisfeita por
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

    -- Ramo MASTER_SET (novo): denominador = Adopted Scope; numerador =
    -- Variant do Scope com correspondência EXATA de Physical Card
    -- alocada (LDM-19/LDM-20/LDM-21) — nunca "qualquer Variant da
    -- mesma Card".
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

    denom AS (
        SELECT * FROM standard_denom
        UNION ALL
        SELECT * FROM master_denom
    ),
    numer AS (
        SELECT * FROM standard_numer
        UNION ALL
        SELECT * FROM master_numer
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
