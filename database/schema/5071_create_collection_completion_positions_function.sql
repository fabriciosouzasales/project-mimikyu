/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5071 - Create collection_completion_positions Function
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01)

Descrição...:
CORREÇÃO DE SEGURANÇA (v2.0, substitui integralmente a v1.0 —
SECURITY INVOKER). Mesmo achado e mesma autoridade de correção do
cabeçalho de `5070` v2.0 — não duplicado aqui em detalhe, ver aquele
arquivo. Resumo: `public.card`/`public.card_variant` são admin-only
sob RLS (`ADR-022`, confirmado por `ADR-030`); `SECURITY INVOKER`
fazia esta função retornar sempre 0 rows para qualquer Owner real
não-admin. Corrigido para `SECURITY DEFINER` com ownership
reconstituído manualmente, mesmo padrão de `5070` v2.0.

Nome fechado em `COLLECTIONS-PHYSICAL-INCREMENT-02E-MODELING-
REVISION-01`: NÃO "missing_positions" (nome que sugeriria
só-faltantes por padrão) — `p_only_missing BOOLEAN DEFAULT FALSE`
decide o filtro explicitamente. Contrato de retorno inalterado desta
correção — superfície mínima preservada, nenhum campo administrativo/
editorial adicional:
- Collection do próprio Owner, `REFERENCE_BASED`/`STANDARD_SET`
  visível -> as posições do Card Set (todas, ou só as não
  satisfeitas, conforme `p_only_missing`);
- Collection `OPEN_CURATION`/`NONE` -> 0 rows;
- Collection de outro Owner ou inexistente -> 0 rows, mesma forma —
  ownership reconstituído manualmente na CTE `target` (idêntico a
  `5070` v2.0: nenhuma linha satisfaz `c.owner_user_id = (select
  auth.uid())` em nenhum dos dois casos, logo nenhuma diferença
  externa entre eles);
- `p_only_missing = FALSE` -> todas as Cards do Card Set referenciado;
- `p_only_missing = TRUE` -> só as Cards sem nenhuma Collection
  Allocation satisfazendo aquela posição nesta Collection.

Ordering determinístico via `card.collector_order`, com
`card.collector_number` e `card.id` como desempate — inalterado.

`SECURITY DEFINER`, `STABLE`, `SET search_path = ''`, referências
100% schema-qualified, `(select auth.uid()) IS NOT NULL` explícito
(nunca `is_admin()`) — mesma disciplina de `5070` v2.0 e do
precedente `ADR-030`.

EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01,
Fase 1): aplicada via apply_migration. Postcheck físico da Fase 2
confirmou SECURITY DEFINER/STABLE/search_path=''/PUBLIC sem EXECUTE/
anon sem EXECUTE/authenticated com EXECUTE. Validada funcionalmente em
5810 (Casos H/Q/R/S/T/Y/W/SEC-B/SEC-BYPASS/SEC-H/SEC-I..L, todos PASS)
e medida em performance real em 5811 (workloads B/H/I, todos < 4ms,
Function Scan, zero shared_read_blocks — sem gargalo comprovado,
nenhum índice novo criado).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_completion_positions(
    p_collection_id UUID,
    p_only_missing  BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    card_id          UUID,
    collector_number VARCHAR(20),
    name             VARCHAR(200),
    is_satisfied     BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        -- Fronteira de autorização: idêntica em espírito a 5070 v2.0
        -- — ownership reconstituído manualmente, primeiro passo da
        -- query, antes de qualquer tabela do Catálogo Editorial.
        SELECT
            c.id             AS collection_id,
            ccsr.card_set_id AS card_set_id
        FROM public.collection c
        JOIN public.collection_reference cr
            ON cr.collection_id = c.id
        JOIN public.collection_card_set_reference ccsr
            ON ccsr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND (select auth.uid()) IS NOT NULL          -- defesa explícita, nunca is_admin()
          AND c.owner_user_id = (select auth.uid())    -- ownership reconstituído manualmente
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'STANDARD_SET'
    ),
    satisfied AS (
        SELECT DISTINCT card.id AS card_id
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
    )
    SELECT
        card.id                       AS card_id,
        card.collector_number         AS collector_number,
        card.name                     AS name,
        (s.card_id IS NOT NULL)       AS is_satisfied
    FROM target t
    JOIN public.card card
        ON card.card_set_id = t.card_set_id
    LEFT JOIN satisfied s
        ON s.card_id = card.id
    WHERE (NOT p_only_missing) OR s.card_id IS NULL
    ORDER BY card.collector_order, card.collector_number, card.id;
$$;

REVOKE ALL ON FUNCTION public.collection_completion_positions(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_completion_positions(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.collection_completion_positions(uuid, boolean) TO authenticated;
