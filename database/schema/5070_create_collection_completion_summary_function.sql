/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5070 - Create collection_completion_summary Function
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01)

Descrição...:
CORREÇÃO DE SEGURANÇA (v2.0, substitui integralmente a v1.0 —
SECURITY INVOKER). Achado real, confirmado por evidência já registrada
no próprio repositório em `ADR-030-card-search-projection.md`
(linhas 17/139): o Catálogo Editorial (`ADR-022`) fecha `card`/
`card_variant`/`card_set` etc. a SELECT direto de usuário comum —
`public.card` tem RLS habilitado SEM NENHUMA policy (nem
`catalog_admin_select`); `public.card_variant` tem só
`catalog_admin_select` (`is_admin()`-gated). Um `authenticated` comum
faz `SELECT count(*) FROM card` e recebe sempre 0 linhas — confirmado
por teste real, documentado no próprio ADR-030. A v1.0 desta função
(`SECURITY INVOKER`) herdava esse bloqueio por construção:
`total_positions`/`satisfied_positions` seriam sempre 0 para qualquer
Owner real não-admin — quebrado para o único usuário que a função
existe para servir. Achado formalmente confirmado e a correção
autorizada em `COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-REVISION-02`.

Correção: `SECURITY DEFINER`, seguindo o precedente já aprovado pelo
projeto em `ADR-030` (`search_cards()`/`search_card_filter_options()`)
— mesma disciplina: `STABLE`, `SET search_path = ''`, referências
100% schema-qualified, verificação explícita de
`(select auth.uid()) IS NOT NULL` (nunca `is_admin()` — Completion não
é operação administrativa), `REVOKE ALL FROM PUBLIC`/`anon` + `GRANT
EXECUTE TO authenticated`.

Diferença estrutural em relação a `search_cards()`: esta função é
escopada a UMA Collection específica de UM Owner, não uma busca
global — logo, ao contrário de `search_cards()` (que só precisa negar
anon/sessão nula), aqui `SECURITY DEFINER` também bypassa a RLS de
`collection`/`collection_reference`/`collection_card_set_reference`/
`collection_allocation`/`physical_card`, que hoje protege
corretamente o Owner. Ownership deixa de ser garantido implicitamente
pela RLS e passa a ser reconstituído explicitamente dentro da própria
função — a CTE `target` só resolve uma linha quando
`c.id = p_collection_id AND c.owner_user_id = (select auth.uid())`,
e todo o restante da query (`denom`/`numer`) deriva exclusivamente
dessa CTE. Nenhuma tabela de Catálogo ou de Collection é consultada
antes dessa fronteira de autorização — ownership é sempre a primeira
fronteira lógica, nunca uma checagem posterior.

Contrato de retorno mantido idêntico ao da v1.0 (`SECURITY DEFINER`
não amplia superfície de retorno):
A. Collection do próprio Owner, `REFERENCE_BASED`/`STANDARD_SET`
   -> exatamente 1 linha;
B. Collection inexistente -> 0 rows;
C. Collection de outro Owner -> 0 rows — idêntico a B, sem mensagem
   ou exceção que diferencie os dois casos. Não-enumeração preservada
   mesmo com RLS bypassada, porque a checagem de ownership é manual
   e idêntica para ambos: nenhuma linha de `target` satisfaz
   `c.owner_user_id = (select auth.uid())`, seja porque a Collection
   não existe, seja porque pertence a outro Owner;
D. Collection `OPEN_CURATION`/`NONE` -> 0 rows (`mode = 'REFERENCE_
   BASED'` e `completion_policy = 'STANDARD_SET'` continuam filtrados
   explicitamente na CTE `target`, ambos, mesmo sendo redundante com
   `chk_collection_completion_policy` de `5067` — explícito por
   disciplina de SECURITY DEFINER, nunca implícito via constraint de
   outra camada).

Zero-denominator, arredondamento e shape das CTEs `denom`/`numer`
inalterados da v1.0: DENOMINADOR (`card.card_set_id =
referenced_card_set_id`, independente de Allocation, via `LEFT JOIN`
a partir de `target`) e NUMERADOR (`collection_allocation ->
physical_card -> card_variant -> card`, com o mesmo filtro explícito
`card.card_set_id = t.card_set_id` — autocontido, não depende
implicitamente da eligibility já garantida pelo 02D) permanecem duas
metades independentes, nunca um único `GROUP BY`. `total_positions =
0` -> `progress_percentage = 0.00`, `is_complete = false`, nunca
divisão por zero.

O que NÃO muda: o catálogo continua fechado a SELECT direto de
`authenticated` — nenhuma policy nova, nenhum GRANT novo em
`card`/`card_variant`/`card_set`; `is_admin()` não é usado em nenhum
ponto desta função (Completion não é operação administrativa).

EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01,
Fase 1): aplicada via apply_migration. Postcheck físico da Fase 2
confirmou SECURITY DEFINER/STABLE/search_path=''/PUBLIC sem EXECUTE/
anon sem EXECUTE/authenticated com EXECUTE. Validada funcionalmente em
5810 (Casos G/I/J/K/L/M/N/O/P/Q/R/S/T/Y/U/X/SEC-A/SEC-BYPASS/SEC-H/
SEC-I..L, todos PASS) e medida em performance real em 5811 (workloads
A/B/C/D/E/F/G/I, todos < 30ms, Function Scan, zero shared_read_blocks
— sem gargalo comprovado, nenhum índice novo criado).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
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
          AND c.completion_policy = 'STANDARD_SET'
    ),
    denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(card.id) AS total_positions
        FROM target t
        LEFT JOIN public.card card
            ON card.card_set_id = t.card_set_id
        GROUP BY t.collection_id, t.completion_policy
    ),
    numer AS (
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
        GROUP BY t.collection_id
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
