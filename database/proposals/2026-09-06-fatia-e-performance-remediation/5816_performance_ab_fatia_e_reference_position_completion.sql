/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5816 - A/B transacional Fatia E: CURRENT LIVE vs CANDIDATE B
Versão......: 1.1 (AB-HARNESS-FINAL-FIX-01 — gate fail-closed)
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-
               PERFORMANCE-REMEDIATION-STAGING-01; harness corrigido em
               COLLECTIONS-POKEDEX-FATIA-E-AB-HARNESS-FINAL-FIX-01 após
               auditoria direta — 5102 PASS, 5103 PASS, 1 BLOCKER no
               harness do 5816 v1.0)

================================================================
CORREÇÃO v1.1 (AB-HARNESS-FINAL-FIX-01) — gate FAIL-CLOSED
================================================================
BLOCKER encontrado na auditoria direta do v1.0: o mandato exige que
divergência semântica seja um STOP que impeça a bateria de prosseguir
para performance. O v1.0 apenas REGISTRAVA `semantic_equivalent = FALSE`
em `equiv_results` e seguia executando os `measure_pair()` — isto é
FAIL-OPEN, e produziria números de performance sobre uma candidata
semanticamente divergente.

Corrigido: `gate_summary()` e `gate_positions()` passaram a ser
FAIL-CLOSED. Após calcular `rowcount_current`, `rowcount_candidate`,
`current_except_candidate` e `candidate_except_current`, ambos derivam
`v_equivalent BOOLEAN` e, se FALSE, emitem `RAISE EXCEPTION`
IMEDIATAMENTE — antes de qualquer `measure_pair` subsequente.

A mensagem do erro carrega obrigatoriamente:
  SEMANTIC_GATE_FAILED seq=% workload=% current_rows=% candidate_rows=%
  current_except_candidate=% candidate_except_current=%

Consequências garantidas por construção:
  - qualquer divergência ABORTA a CALL 1;
  - nenhum workload do estado corrente é medido;
  - nenhum estado posterior é executado;
  - o PostgreSQL desfaz a transação (fixtures, funções candidatas,
    TEMP TABLEs, GRANTs) — zero resíduo preservado;
  - a evidência do diagnóstico viaja na própria mensagem de erro.

Se o gate passa, a linha entra em `equiv_results` com
`semantic_equivalent = TRUE` (valor literal, não mais uma expressão).

`all_gates_passed` permanece no SELECT final como DEFESA ADICIONAL: se
o PASSO 7 for alcançado, ele será TRUE por construção — qualquer outro
valor indicaria falha do próprio harness.

Esta correção SUPERA a decisão registrada no v1.0 (que evitava `RAISE`
por receio de destruir evidência). A evidência necessária está toda na
mensagem do `RAISE`, e a prioridade do mandato é impedir que números de
performance sejam produzidos sobre semântica divergente.

NADA MAIS FOI ALTERADO no v1.1: os corpos das funções candidatas
(lógica de 5102/5103), os 13 gates, os 26 EXPLAINs, as fixtures, os
volumes, o batching <= 500, a alternância CURRENT/CANDIDATE, o
`plan_json` bruto, o BEGIN/ROLLBACK, o zero resíduo e a ausência de
qualquer índice permanecem exatamente como no v1.0.

================================================================
OBJETIVO
================================================================
Provar SEMANTICAMENTE e medir, lado a lado e sem tocar produção:

  CURRENT LIVE  = public.collection_completion_summary(uuid)          [5100 v4.0]
                  public.collection_pokedex_scope_positions(uuid,bool)[5101 v1.0]

  CANDIDATE B   = lógica EXATA de 5102 v5.0 e 5103 v2.0, criada dentro
                  da transação com nomes distintos:
                  public.collection_completion_summary_fatia_e_candidate(uuid)
                  public.collection_pokedex_scope_positions_fatia_e_candidate(uuid,bool)

As funções LIVE NÃO são substituídas. Nenhuma migration é executada.
Toda a bateria vive dentro de um único BEGIN ... ROLLBACK — DDL de
função é transacional no PostgreSQL, portanto o ROLLBACK remove as
candidatas, as fixtures e os GRANTs temporários. Zero resíduo.

NENHUM ÍNDICE É CRIADO.

================================================================
CONTEXTO — o BLOCKER que motivou esta bateria
================================================================
5815 v1.2 mediu as duas funções LIVE sobre a Pokédex NATIONAL real
(1025 Positions) e encontrou custo proporcional ao PRODUTO
|Scope| x |Allocations da Collection|, com constante estável de ~3,02
shared blocks por par em quatro estados independentes (desvio < 0,5%):

  seq  4/5/6  FULL_REFERENCE 1025 / 828 Alloc .. ~1357 ms / 2 557 414 blocks
  seq  11     + 50 duplicatas (878 Alloc) ...... ~1454 ms / 2 713 214 blocks
  seq  9/10   GENERATION_FILTERED 156 / 156 .... ~44 ms   /    73 677 blocks
  seq  12/13  + 200 fora do Scope (356 Alloc) .. ~96 ms   /   167 745 blocks

Causa estrutural (grafo de junção, não plano interno): `scope` e
`collection_allocation` são irmãos ligados apenas a `target` pelo mesmo
`collection_id`, sem predicado direto entre si; o predicado que os
correlaciona vive numa terceira relação. Detalhamento completo nos
cabeçalhos de 5102 e 5103.

INTERNAL PLAN VISIBILITY = NOT OBSERVABLE — o EXPLAIN de uma chamada
externa a estas funções expõe apenas `Function Scan`. Esta bateria,
como a 5815, NÃO faz alegação sobre nós de scan internos. A decisão é
tomada por tempo, buffers, cardinalidade e crescimento entre estados.

================================================================
DESENHO DA BATERIA
================================================================
PASSO -1  Baseline de resíduo (fora da transação).
PASSO 0   BEGIN; fixtures de contexto; pool integral de Species
          resolvidas (sem LIMIT); TEMP TABLEs `perf_results` e
          `equiv_results`.
PASSO 0A  Criação das DUAS funções candidatas, com a lógica EXATA de
          5102/5103, ANTES de qualquer impersonação. Nomes distintos;
          as LIVE permanecem intactas.
PASSO 0B  GRANTs em objetos TEMP e EXECUTE nas candidatas para
          `authenticated`; helpers `pg_temp`. Tudo ANTES do primeiro
          SET ROLE.
PASSO 1   Owner A autenticado cria as duas Collections de teste via RPC
          real (FULL_REFERENCE sobre NATIONAL e GENERATION_FILTERED
          sobre a Generation de maior cobertura).
PASSOS 2-6  Cinco estados, na MESMA ordem conceitual do 5815 v1.2.
          Em cada estado, para cada workload: primeiro o GATE de
          equivalência, depois o par de medições.
PASSO 7   SELECT consolidado único (última instrução da CALL 1).
PASSO 8   RESET ROLE; auth cleanup; ROLLBACK.
PASSO 9   Postcheck de zero resíduo (fora da transação).

Fixtures e dimensões — reutilizadas integralmente do 5815 v1.2:
  - Pokédex NATIONAL real, 1025 Positions;
  - pool INTEGRAL de Species resolvidas (card_primary_species +
    Card Variant), 1 Variant por Species, SEM LIMIT;
  - batching <= 500 por chamada de add_physical_cards() /
    allocate_physical_cards_to_collection() (tetos reais das RPCs);
  - high-density consumindo o pool inteiro em laço WHILE;
  - GENERATION_FILTERED sobre a Generation de maior cobertura;
  - 50 Physical Cards duplicadas da mesma Variant na mesma Position;
  - até 200 Assignments fora do Scope corrente.

Prefixo das fixtures: 'AB-TEST-FATIA-E-%' (distinto do
'PERF-TEST-FATIA-E-%' do 5815, para que os postchecks de resíduo das
duas baterias nunca se confundam).

================================================================
GATE DE EQUIVALÊNCIA SEMÂNTICA
================================================================
ANTES de qualquer par de medição, cada workload passa por um gate que
compara CURRENT vs CANDIDATE por IGUALDADE DE CONJUNTO nos dois
sentidos:

  count(CURRENT   EXCEPT CANDIDATE) = 0
  count(CANDIDATE EXCEPT CURRENT)   = 0

Para `summary` o `SELECT *` cobre os 7 campos do contrato
(collection_id, completion_policy, total_positions, satisfied_positions,
missing_positions, progress_percentage, is_complete).
Para `positions` o `SELECT *` cobre os 5 campos do contrato congelado
(pokedex_position_id, position_number, species_id, species_name,
is_satisfied).

Como `EXCEPT` é set-based e deduplica, o gate registra TAMBÉM a
contagem bruta de linhas de cada lado e exige igualdade — isso captura
regressões de MULTIPLICIDADE (linha duplicada na saída) que o `EXCEPT`
sozinho esconderia.

`semantic_equivalent` = (except_a = 0) AND (except_b = 0) AND
                        (rowcount_current = rowcount_candidate).

GATE FAIL-CLOSED (v1.1). Se `v_equivalent` for FALSE, o gate emite
`RAISE EXCEPTION` imediatamente:

  SEMANTIC_GATE_FAILED seq=% workload=% current_rows=% candidate_rows=%
  current_except_candidate=% candidate_except_current=%

O `RAISE` aborta a CALL 1 inteira. Nenhum `measure_pair` do estado
corrente é alcançado, nenhum estado posterior é executado, e o
PostgreSQL desfaz a transação — fixtures, funções candidatas, TEMP
TABLEs e GRANTs desaparecem, preservando o zero resíduo. Toda a
evidência necessária ao diagnóstico viaja na mensagem do erro.

ORDEM PRESERVADA em cada estado: gates do estado -> somente se TODOS
passarem -> `measure_pair` daquele estado. É essa ordem, somada ao
`RAISE`, que torna estruturalmente impossível medir performance sobre
uma candidata semanticamente divergente.

`all_gates_passed` permanece no SELECT final como DEFESA ADICIONAL: se
o PASSO 7 for alcançado, ele será TRUE por construção — qualquer outro
valor indicaria falha do próprio harness, e a bateria deve ser
considerada REPROVADA.

================================================================
MEDIÇÃO A/B
================================================================
Os mesmos 13 workloads do 5815 v1.2, medidos para CURRENT e para
CANDIDATE = 26 planos `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`,
capturados em `perf_results` com coluna `implementation`
('CURRENT' | 'CANDIDATE') e `plan_json` bruto preservado.

Mapeamento dos 13 workloads (idêntico ao 5815 v1.2):
   1  C1 FULL_REFERENCE 1025 / 0 Assignments   summary
   2  C1                                       positions FALSE
   3  C1                                       positions TRUE
   4  C2 FULL_REFERENCE 1025 / high-density    summary
   5  C2                                       positions FALSE
   6  C2                                       positions TRUE
   7  C3 GENERATION_FILTERED                   summary vazio
   8  C3                                       positions FALSE vazio
   9  C3                                       summary parcial
  10  C3                                       positions TRUE parcial
  11  C4 duplicatas concentradas               summary
  12  C5 Assignments fora do Scope             summary
  13  C5                                       positions FALSE

ALTERNÂNCIA ANTI-VIÉS DE CACHE: em `sequence_number` ÍMPAR mede-se
CURRENT primeiro e CANDIDATE depois; em PAR, CANDIDATE primeiro e
CURRENT depois. A regra vive em um único lugar
(`pg_temp.measure_pair`), é determinística e auditável.

EQUIDADE DE MECANISMO: os dois lados de cada par são medidos pelo
MESMO helper, com o mesmo envelope `EXECUTE ... INTO`, no mesmo estado
de fixture, a instantes adjacentes. O texto do statement medido difere
apenas no nome da função chamada.

CONTINUIDADE COM 5815 v1.2: o argumento é passado como a MESMA
subquery `(SELECT value::uuid FROM perf_ctx WHERE key = '...')` usada
lá, e não como UUID interpolado. Isso mantém os números de CURRENT
diretamente comparáveis com a linha de base já medida.

================================================================
ESTRATÉGIA OPERACIONAL DE EXECUÇÃO — quando houver GO
================================================================
Mesma estratégia validada em 5814 e 5815 v1.2, imposta pela limitação
real do `execute_sql` do Supabase MCP (retorna apenas o result set da
ÚLTIMA instrução de cada chamada):

CALL 1 — do `BEGIN` (PASSO 0) até o SELECT consolidado (PASSO 7),
         inclusive. O SELECT consolidado deve ser a ÚLTIMA instrução
         submetida. A transação permanece ABERTA ao final da chamada; o
         PostgreSQL garante rollback automático no encerramento da
         conexão (nunca faz auto-commit de transação aberta).
CALL 2 — apenas PASSO 8 (RESET ROLE, auth cleanup, ROLLBACK) e PASSO 9
         (postcheck de zero resíduo). O ROLLBACK é no-op caso a conexão
         da CALL 1 já tenha sido encerrada e auto-revertida.
PASSO -1 está fora da transação e pode ser executado isoladamente como
         precheck, antes da CALL 1.

================================================================
CRITÉRIO DE DECISÃO (mandato -REMEDIATION-STAGING-01, seção 8)
================================================================
A candidata só pode avançar se TODOS forem verdadeiros:
  1. equivalência semântica = 100% (13/13 gates, all_gates_passed);
  2. nenhum runtime error;
  3. o comportamento |Scope| x |Allocations| deixar de aparecer
     materialmente — verificável recalculando blocks/par por estado:
     na CURRENT a constante é ~3,02; na CANDIDATE ela deve DEIXAR de
     ser constante e passar a decrescer conforme o produto cresce;
  4. FULL_REFERENCE high-density (seq 4/5/6) com redução substancial
     frente aos ~1357 ms / ~2,56 M blocks da CURRENT;
  5. duplicatas (seq 11) não recriarem comportamento multiplicativo;
  6. out-of-scope (seq 12/13) crescendo aproximadamente com o número de
     Assignments acrescentadas, não com Scope x Assignments;
  7. nenhuma regressão aparente nos estados vazios (seq 1/2/3/7/8).

NENHUM THRESHOLD ARTIFICIAL é fixado antes da medição.

Após um A/B aprovado, e SOMENTE então, 5102/5103 poderão ser propostos
para aplicação — e `5814` v1.3 (87 casos) deverá ser reexecutado
INALTERADO como regressão funcional obrigatória.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo
-- ================================================================
SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection
WHERE name LIKE 'AB-TEST-FATIA-E-%';

-- ================================================================
-- ============ INÍCIO DA CALL 1 (BEGIN -> PASSO 7) ===============
-- ================================================================

-- ================================================================
-- PASSO 0 — BEGIN + contexto + pool + TEMP TABLEs de evidência
-- ================================================================
BEGIN;

CREATE TEMP TABLE perf_ctx (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO perf_ctx (key, value)
SELECT 'owner_a', owner_user_id::text FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
ORDER BY owner_user_id LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'inventory_a', id::text FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a');

INSERT INTO perf_ctx (key, value)
SELECT 'language_id', id::text FROM public.language LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'game_id', id::text FROM public.game WHERE code = 'POKEMON';

INSERT INTO perf_ctx (key, value)
SELECT 'pokedex_national_id', id::text FROM public.pokedex WHERE code = 'NATIONAL';

WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a'), 'AB-TEST-FATIA-E-STORAGE')
    RETURNING id
)
INSERT INTO perf_ctx (key, value) SELECT 'storage_a', id::text FROM ins;

-- Generation real com maior cobertura de Species resolvidas.
INSERT INTO perf_ctx (key, value)
SELECT 'gen_top_id', generation_id::text
FROM (
    SELECT sp.generation_id, count(DISTINCT sp.id) AS resolved_count
    FROM public.pokemon_species sp
    JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
    JOIN public.card_variant cv ON cv.card_id = cps.card_id
    GROUP BY sp.generation_id
    ORDER BY resolved_count DESC
    LIMIT 1
) top;

-- Pool INTEGRAL de Species resolvidas, 1 Variant por Species, SEM LIMIT.
CREATE TEMP TABLE perf_resolved_pool AS
SELECT DISTINCT ON (sp.id)
    sp.id            AS species_id,
    sp.generation_id AS generation_id,
    cv.id            AS variant_id
FROM public.pokemon_species sp
JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
JOIN public.card_variant cv ON cv.card_id = cps.card_id
ORDER BY sp.id, cv.id;

-- Evidência de PERFORMANCE. Guarda somente o plano bruto; toda
-- derivação de métrica acontece no SELECT consolidado do PASSO 7,
-- depois do fim de todas as medições.
CREATE TEMP TABLE perf_results (
    sequence_number  INTEGER NOT NULL,
    implementation   TEXT    NOT NULL CHECK (implementation IN ('CURRENT', 'CANDIDATE')),
    scenario_label   TEXT    NOT NULL,
    workload_label   TEXT    NOT NULL,
    plan_json        JSON    NOT NULL,
    PRIMARY KEY (sequence_number, implementation)
);

-- Evidência de EQUIVALÊNCIA SEMÂNTICA, uma linha por workload.
CREATE TEMP TABLE equiv_results (
    sequence_number          INTEGER PRIMARY KEY,
    scenario_label           TEXT    NOT NULL,
    workload_label           TEXT    NOT NULL,
    rowcount_current         BIGINT  NOT NULL,
    rowcount_candidate       BIGINT  NOT NULL,
    current_except_candidate BIGINT  NOT NULL,
    candidate_except_current BIGINT  NOT NULL,
    semantic_equivalent      BOOLEAN NOT NULL
);

-- ================================================================
-- PASSO 0A — funções CANDIDATAS (lógica EXATA de 5102 v5.0 e 5103
-- v2.0), criadas DENTRO da transação, com nomes distintos, ANTES de
-- qualquer impersonação. As funções LIVE não são tocadas. O ROLLBACK
-- do PASSO 8 remove estas duas.
-- ================================================================

CREATE FUNCTION public.collection_completion_summary_fatia_e_candidate(
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
AS $fn$
    WITH target AS (
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
          AND (select auth.uid()) IS NOT NULL
          AND c.owner_user_id = (select auth.uid())
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy IN ('STANDARD_SET', 'MASTER_SET')
    ),
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
           AND pc.card_variant_id = s.card_variant_id
        WHERE t.completion_policy = 'MASTER_SET'
        GROUP BY t.collection_id
    ),
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
          AND (select auth.uid()) IS NOT NULL
          AND c.owner_user_id = (select auth.uid())
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'REFERENCE_POSITION'
    ),
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
    -- ALTERNATIVA B — conjunto satisfeito calculado SEM o Scope.
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
    -- ALTERNATIVA B — numerator como interseção explícita.
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
$fn$;

CREATE FUNCTION public.collection_pokedex_scope_positions_fatia_e_candidate(
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
AS $fn$
    WITH target AS (
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
          AND (select auth.uid()) IS NOT NULL
          AND c.owner_user_id = (select auth.uid())
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'REFERENCE_POSITION'
    ),
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
    -- ALTERNATIVA B — satisfied calculada SEM referência ao Scope.
    satisfied AS (
        SELECT DISTINCT
            t.collection_id,
            a.pokedex_position_id
        FROM target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a
            ON a.collection_allocation_id = ca.id
    )
    SELECT
        s.pokedex_position_id,
        s.position_number,
        s.species_id,
        s.species_name,
        (sat.pokedex_position_id IS NOT NULL) AS is_satisfied
    FROM scope s
    LEFT JOIN satisfied sat
        ON sat.collection_id        = s.collection_id
       AND sat.pokedex_position_id  = s.pokedex_position_id
    WHERE (NOT p_only_missing) OR sat.pokedex_position_id IS NULL
    ORDER BY
        s.position_number,
        s.pokedex_position_id;
$fn$;

REVOKE ALL ON FUNCTION public.collection_completion_summary_fatia_e_candidate(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_completion_summary_fatia_e_candidate(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.collection_pokedex_scope_positions_fatia_e_candidate(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_pokedex_scope_positions_fatia_e_candidate(uuid, boolean) FROM anon;

-- ================================================================
-- PASSO 0B — GRANTs (TEMP + candidatas) e helpers pg_temp, ANTES do
-- primeiro SET ROLE. Objetos TEMP não herdam privilégio de PUBLIC.
-- ================================================================
GRANT SELECT, INSERT ON perf_ctx           TO authenticated;
GRANT SELECT           ON perf_resolved_pool TO authenticated;
GRANT SELECT, INSERT ON perf_results       TO authenticated;
GRANT SELECT, INSERT ON equiv_results      TO authenticated;

GRANT EXECUTE ON FUNCTION public.collection_completion_summary_fatia_e_candidate(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.collection_pokedex_scope_positions_fatia_e_candidate(uuid, boolean) TO authenticated;

-- Helper de captura: mesmo envelope para os dois lados de cada par.
CREATE FUNCTION pg_temp.capture(
    p_seq  INTEGER,
    p_impl TEXT,
    p_scn  TEXT,
    p_wl   TEXT,
    p_sql  TEXT
) RETURNS VOID
LANGUAGE plpgsql
AS $h$
DECLARE
    v_json JSON;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_sql INTO v_json;
    INSERT INTO perf_results (sequence_number, implementation, scenario_label, workload_label, plan_json)
    VALUES (p_seq, p_impl, p_scn, p_wl, v_json);
END
$h$;

-- Helper de par com alternância anti-viés de cache: sequence_number
-- ímpar mede CURRENT primeiro; par mede CANDIDATE primeiro.
CREATE FUNCTION pg_temp.measure_pair(
    p_seq           INTEGER,
    p_scn           TEXT,
    p_wl            TEXT,
    p_sql_current   TEXT,
    p_sql_candidate TEXT
) RETURNS VOID
LANGUAGE plpgsql
AS $h$
BEGIN
    IF p_seq % 2 = 1 THEN
        PERFORM pg_temp.capture(p_seq, 'CURRENT',   p_scn, p_wl, p_sql_current);
        PERFORM pg_temp.capture(p_seq, 'CANDIDATE', p_scn, p_wl, p_sql_candidate);
    ELSE
        PERFORM pg_temp.capture(p_seq, 'CANDIDATE', p_scn, p_wl, p_sql_candidate);
        PERFORM pg_temp.capture(p_seq, 'CURRENT',   p_scn, p_wl, p_sql_current);
    END IF;
END
$h$;

-- Gate de equivalência para `summary` (7 campos do contrato).
CREATE FUNCTION pg_temp.gate_summary(
    p_seq        INTEGER,
    p_scn        TEXT,
    p_wl         TEXT,
    p_collection UUID
) RETURNS VOID
LANGUAGE plpgsql
AS $h$
DECLARE
    v_rc_cur     BIGINT;
    v_rc_cand    BIGINT;
    v_a          BIGINT;
    v_b          BIGINT;
    v_equivalent BOOLEAN;
BEGIN
    SELECT count(*) INTO v_rc_cur
    FROM public.collection_completion_summary(p_collection);

    SELECT count(*) INTO v_rc_cand
    FROM public.collection_completion_summary_fatia_e_candidate(p_collection);

    SELECT count(*) INTO v_a FROM (
        SELECT * FROM public.collection_completion_summary(p_collection)
        EXCEPT
        SELECT * FROM public.collection_completion_summary_fatia_e_candidate(p_collection)
    ) d;

    SELECT count(*) INTO v_b FROM (
        SELECT * FROM public.collection_completion_summary_fatia_e_candidate(p_collection)
        EXCEPT
        SELECT * FROM public.collection_completion_summary(p_collection)
    ) d;

    v_equivalent := (v_a = 0 AND v_b = 0 AND v_rc_cur = v_rc_cand);

    -- GATE FAIL-CLOSED (v1.1). Divergência semântica ABORTA a bateria
    -- imediatamente, ANTES de qualquer measure_pair subsequente. O
    -- RAISE propaga, a CALL 1 inteira falha, o PostgreSQL desfaz a
    -- transação (fixtures, candidatas, TEMP TABLEs) e nenhum workload
    -- deste estado nem de qualquer estado posterior é medido.
    -- A mensagem carrega toda a evidência necessária ao diagnóstico.
    IF NOT v_equivalent THEN
        RAISE EXCEPTION
            'SEMANTIC_GATE_FAILED seq=% workload=% current_rows=% candidate_rows=% current_except_candidate=% candidate_except_current=%',
            p_seq, p_wl, v_rc_cur, v_rc_cand, v_a, v_b;
    END IF;

    INSERT INTO equiv_results (
        sequence_number, scenario_label, workload_label,
        rowcount_current, rowcount_candidate,
        current_except_candidate, candidate_except_current,
        semantic_equivalent
    )
    VALUES (
        p_seq, p_scn, p_wl,
        v_rc_cur, v_rc_cand,
        v_a, v_b,
        TRUE
    );
END
$h$;

-- Gate de equivalência para `positions` (5 campos do contrato congelado).
CREATE FUNCTION pg_temp.gate_positions(
    p_seq          INTEGER,
    p_scn          TEXT,
    p_wl           TEXT,
    p_collection   UUID,
    p_only_missing BOOLEAN
) RETURNS VOID
LANGUAGE plpgsql
AS $h$
DECLARE
    v_rc_cur     BIGINT;
    v_rc_cand    BIGINT;
    v_a          BIGINT;
    v_b          BIGINT;
    v_equivalent BOOLEAN;
BEGIN
    SELECT count(*) INTO v_rc_cur
    FROM public.collection_pokedex_scope_positions(p_collection, p_only_missing);

    SELECT count(*) INTO v_rc_cand
    FROM public.collection_pokedex_scope_positions_fatia_e_candidate(p_collection, p_only_missing);

    SELECT count(*) INTO v_a FROM (
        SELECT * FROM public.collection_pokedex_scope_positions(p_collection, p_only_missing)
        EXCEPT
        SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate(p_collection, p_only_missing)
    ) d;

    SELECT count(*) INTO v_b FROM (
        SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate(p_collection, p_only_missing)
        EXCEPT
        SELECT * FROM public.collection_pokedex_scope_positions(p_collection, p_only_missing)
    ) d;

    v_equivalent := (v_a = 0 AND v_b = 0 AND v_rc_cur = v_rc_cand);

    -- GATE FAIL-CLOSED (v1.1). Divergência semântica ABORTA a bateria
    -- imediatamente, ANTES de qualquer measure_pair subsequente. O
    -- RAISE propaga, a CALL 1 inteira falha, o PostgreSQL desfaz a
    -- transação (fixtures, candidatas, TEMP TABLEs) e nenhum workload
    -- deste estado nem de qualquer estado posterior é medido.
    -- A mensagem carrega toda a evidência necessária ao diagnóstico.
    IF NOT v_equivalent THEN
        RAISE EXCEPTION
            'SEMANTIC_GATE_FAILED seq=% workload=% current_rows=% candidate_rows=% current_except_candidate=% candidate_except_current=%',
            p_seq, p_wl, v_rc_cur, v_rc_cand, v_a, v_b;
    END IF;

    INSERT INTO equiv_results (
        sequence_number, scenario_label, workload_label,
        rowcount_current, rowcount_candidate,
        current_except_candidate, candidate_except_current,
        semantic_equivalent
    )
    VALUES (
        p_seq, p_scn, p_wl,
        v_rc_cur, v_rc_cand,
        v_a, v_b,
        TRUE
    );
END
$h$;

GRANT EXECUTE ON FUNCTION pg_temp.capture(INTEGER, TEXT, TEXT, TEXT, TEXT)                TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.measure_pair(INTEGER, TEXT, TEXT, TEXT, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.gate_summary(INTEGER, TEXT, TEXT, UUID)                 TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.gate_positions(INTEGER, TEXT, TEXT, UUID, BOOLEAN)      TO authenticated;

-- ================================================================
-- PASSO 1 — Owner A autenticado cria as duas Collections via RPC real
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM perf_ctx WHERE key = 'owner_a'), true);

WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        'AB-TEST-FATIA-E-COL-FULL', NULL,
        (SELECT value::uuid FROM perf_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'pokedex_national_id'),
        'FULL_REFERENCE', NULL
    )
)
INSERT INTO perf_ctx (key, value) SELECT 'col_full', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        'AB-TEST-FATIA-E-COL-GEN', NULL,
        (SELECT value::uuid FROM perf_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'pokedex_national_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM perf_ctx WHERE key = 'gen_top_id')]
    )
)
INSERT INTO perf_ctx (key, value) SELECT 'col_gen', id::text FROM ins;

-- ================================================================
-- PASSO 2 — ESTADO 1: FULL_REFERENCE, 1025 Positions, 0 Assignments.
-- Workloads 1, 2 e 3.
-- ================================================================
SELECT pg_temp.gate_summary(1, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'summary',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'));
SELECT pg_temp.gate_positions(2, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'positions FALSE',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE);
SELECT pg_temp.gate_positions(3, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'positions TRUE',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE);

SELECT pg_temp.measure_pair(1, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'summary',
$q$SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$,
$q$SELECT * FROM public.collection_completion_summary_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$);

SELECT pg_temp.measure_pair(2, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'positions FALSE',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE)$q$);

SELECT pg_temp.measure_pair(3, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'positions TRUE',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE)$q$);

-- ================================================================
-- PASSO 3 — ESTADO 2: FULL_REFERENCE high-density. Consome TODO o
-- perf_resolved_pool em lotes de no máximo 500 por chamada de
-- add_physical_cards()/allocate_physical_cards_to_collection().
-- Workloads 4, 5 e 6.
-- ================================================================
DO $$
DECLARE
    v_batch_size  CONSTANT INT := 500;
    v_total       INT;
    v_offset      INT := 0;
    v_batch       JSONB;
    v_pc_ids      UUID[];
BEGIN
    SELECT count(*) INTO v_total FROM perf_resolved_pool;

    WHILE v_offset < v_total LOOP
        SELECT jsonb_agg(jsonb_build_object(
            'card_variant_id', variant_id,
            'language_id', (SELECT value FROM perf_ctx WHERE key = 'language_id')
        ))
        INTO v_batch
        FROM (
            SELECT variant_id FROM perf_resolved_pool
            ORDER BY species_id
            OFFSET v_offset LIMIT v_batch_size
        ) sub;

        SELECT array_agg(id) INTO v_pc_ids FROM public.add_physical_cards(v_batch);

        PERFORM public.allocate_physical_cards_to_collection(
            (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'),
            v_pc_ids
        );

        v_offset := v_offset + v_batch_size;
    END LOOP;
END $$;

SELECT pg_temp.gate_summary(4, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'summary',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'));
SELECT pg_temp.gate_positions(5, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'positions FALSE',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE);
SELECT pg_temp.gate_positions(6, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'positions TRUE',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE);

SELECT pg_temp.measure_pair(4, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'summary',
$q$SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$,
$q$SELECT * FROM public.collection_completion_summary_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$);

SELECT pg_temp.measure_pair(5, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'positions FALSE',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE)$q$);

SELECT pg_temp.measure_pair(6, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'positions TRUE',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE)$q$);

-- ================================================================
-- PASSO 4 — ESTADO 3: GENERATION_FILTERED, primeiro vazio (workloads
-- 7 e 8), depois parcial (workloads 9 e 10). Mesmo batching <= 500.
-- ================================================================
SELECT pg_temp.gate_summary(7, 'CENARIO 3 - GENERATION_FILTERED', 'summary vazio',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'));
SELECT pg_temp.gate_positions(8, 'CENARIO 3 - GENERATION_FILTERED', 'positions FALSE vazio',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE);

SELECT pg_temp.measure_pair(7, 'CENARIO 3 - GENERATION_FILTERED', 'summary vazio',
$q$SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$,
$q$SELECT * FROM public.collection_completion_summary_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$);

SELECT pg_temp.measure_pair(8, 'CENARIO 3 - GENERATION_FILTERED', 'positions FALSE vazio',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE)$q$);

DO $$
DECLARE
    v_batch_size  CONSTANT INT := 500;
    v_total       INT;
    v_offset      INT := 0;
    v_batch       JSONB;
    v_pc_ids      UUID[];
BEGIN
    SELECT count(*) INTO v_total FROM perf_resolved_pool
    WHERE generation_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'gen_top_id');

    WHILE v_offset < v_total LOOP
        SELECT jsonb_agg(jsonb_build_object(
            'card_variant_id', variant_id,
            'language_id', (SELECT value FROM perf_ctx WHERE key = 'language_id')
        ))
        INTO v_batch
        FROM (
            SELECT variant_id FROM perf_resolved_pool
            WHERE generation_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'gen_top_id')
            ORDER BY species_id
            OFFSET v_offset LIMIT v_batch_size
        ) sub;

        SELECT array_agg(id) INTO v_pc_ids FROM public.add_physical_cards(v_batch);

        PERFORM public.allocate_physical_cards_to_collection(
            (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'),
            v_pc_ids
        );

        v_offset := v_offset + v_batch_size;
    END LOOP;
END $$;

SELECT pg_temp.gate_summary(9, 'CENARIO 3 - GENERATION_FILTERED', 'summary parcial',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'));
SELECT pg_temp.gate_positions(10, 'CENARIO 3 - GENERATION_FILTERED', 'positions TRUE parcial',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), TRUE);

SELECT pg_temp.measure_pair(9, 'CENARIO 3 - GENERATION_FILTERED', 'summary parcial',
$q$SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$,
$q$SELECT * FROM public.collection_completion_summary_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$);

SELECT pg_temp.measure_pair(10, 'CENARIO 3 - GENERATION_FILTERED', 'positions TRUE parcial',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), TRUE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), TRUE)$q$);

-- ================================================================
-- PASSO 5 — ESTADO 4: 50 Physical Cards adicionais da MESMA Variant,
-- todas satisfazendo a MESMA Position em col_full. Workload 11.
-- ================================================================
DO $$
DECLARE
    v_variant_id UUID;
    v_batch JSONB;
    v_pc_ids UUID[];
BEGIN
    SELECT variant_id INTO v_variant_id FROM perf_resolved_pool LIMIT 1;

    SELECT jsonb_agg(jsonb_build_object(
        'card_variant_id', v_variant_id,
        'language_id', (SELECT value FROM perf_ctx WHERE key = 'language_id')
    )) INTO v_batch
    FROM generate_series(1, 50);

    SELECT array_agg(id) INTO v_pc_ids FROM public.add_physical_cards(v_batch);

    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'),
        v_pc_ids
    );
END $$;

SELECT pg_temp.gate_summary(11, 'CENARIO 4 - duplicatas concentradas', 'summary',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'));

SELECT pg_temp.measure_pair(11, 'CENARIO 4 - duplicatas concentradas', 'summary',
$q$SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$,
$q$SELECT * FROM public.collection_completion_summary_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$);

-- ================================================================
-- PASSO 6 — ESTADO 5: até 200 Assignments cujas Species pertencem a
-- Generations FORA do filtro corrente de col_gen. Workloads 12 e 13.
-- ================================================================
DO $$
DECLARE
    v_batch JSONB;
    v_pc_ids UUID[];
BEGIN
    SELECT jsonb_agg(jsonb_build_object(
        'card_variant_id', variant_id,
        'language_id', (SELECT value FROM perf_ctx WHERE key = 'language_id')
    )) INTO v_batch
    FROM (
        SELECT variant_id FROM perf_resolved_pool
        WHERE generation_id <> (SELECT value::uuid FROM perf_ctx WHERE key = 'gen_top_id')
        LIMIT 200
    ) sub;

    IF v_batch IS NOT NULL THEN
        SELECT array_agg(id) INTO v_pc_ids FROM public.add_physical_cards(v_batch);

        PERFORM public.allocate_physical_cards_to_collection(
            (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'),
            v_pc_ids
        );
    END IF;
END $$;

SELECT pg_temp.gate_summary(12, 'CENARIO 5 - Assignments fora do Scope', 'summary',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'));
SELECT pg_temp.gate_positions(13, 'CENARIO 5 - Assignments fora do Scope', 'positions FALSE',
    (SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE);

SELECT pg_temp.measure_pair(12, 'CENARIO 5 - Assignments fora do Scope', 'summary',
$q$SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$,
$q$SELECT * FROM public.collection_completion_summary_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$);

SELECT pg_temp.measure_pair(13, 'CENARIO 5 - Assignments fora do Scope', 'positions FALSE',
$q$SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE)$q$,
$q$SELECT * FROM public.collection_pokedex_scope_positions_fatia_e_candidate((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE)$q$);

-- ================================================================
-- PASSO 7 — LEITURA FINAL CONSOLIDADA.
--
-- Único SELECT que devolve, em UMA resposta: as 26 linhas de
-- performance (13 workloads x 2 implementações), o veredito de
-- equivalência semântica de cada workload, e o resumo PAREADO
-- (CURRENT vs CANDIDATE, com fatores de redução) computado por window
-- function sobre o par — atendendo aos dois pedidos do mandato em uma
-- única instrução, como exige a limitação "last-statement-only" do
-- execute_sql.
--
-- Todas as métricas são derivadas AQUI, depois do fim de todas as
-- medições. `plan_json` bruto vai junto e permanece a autoridade sobre
-- qualquer campo derivado.
--
-- Leitura: `EXPLAIN ... FORMAT JSON` devolve array de um elemento (daí
-- o `-> 0`); em `Shared Hit/Read Blocks` o nó raiz já é cumulativo da
-- árvore inteira, logo os valores da raiz são os totais do workload.
--
-- ESTA DEVE SER A ÚLTIMA INSTRUÇÃO DA CALL 1.
-- ================================================================
WITH base AS (
    SELECT
        r.sequence_number,
        r.implementation,
        r.scenario_label,
        r.workload_label,
        e.semantic_equivalent,
        e.rowcount_current,
        e.rowcount_candidate,
        e.current_except_candidate,
        e.candidate_except_current,
        (r.plan_json -> 0 ->> 'Execution Time')::numeric              AS execution_time_ms,
        (r.plan_json -> 0 ->> 'Planning Time')::numeric               AS planning_time_ms,
        (r.plan_json -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint  AS shared_hit_blocks,
        (r.plan_json -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint AS shared_read_blocks,
        (r.plan_json -> 0 -> 'Plan' ->> 'Node Type')                  AS root_node_type,
        (r.plan_json -> 0 -> 'Plan' ->> 'Actual Rows')::numeric       AS root_actual_rows,
        (r.plan_json -> 0 -> 'Plan' ->> 'Plan Rows')::numeric         AS root_plan_rows,
        r.plan_json
    FROM perf_results r
    LEFT JOIN equiv_results e
        ON e.sequence_number = r.sequence_number
),
paired AS (
    SELECT
        b.*,
        max(execution_time_ms)  FILTER (WHERE implementation = 'CURRENT')   OVER (PARTITION BY sequence_number) AS current_execution_ms,
        max(execution_time_ms)  FILTER (WHERE implementation = 'CANDIDATE') OVER (PARTITION BY sequence_number) AS candidate_execution_ms,
        max(shared_hit_blocks)  FILTER (WHERE implementation = 'CURRENT')   OVER (PARTITION BY sequence_number) AS current_shared_hit,
        max(shared_hit_blocks)  FILTER (WHERE implementation = 'CANDIDATE') OVER (PARTITION BY sequence_number) AS candidate_shared_hit,
        bool_and(COALESCE(semantic_equivalent, FALSE)) OVER ()                                                   AS all_gates_passed
    FROM base b
)
SELECT
    sequence_number,
    implementation,
    scenario_label                                    AS scenario,
    workload_label                                    AS workload,
    semantic_equivalent,
    all_gates_passed,
    rowcount_current,
    rowcount_candidate,
    current_except_candidate,
    candidate_except_current,
    execution_time_ms,
    planning_time_ms,
    shared_hit_blocks,
    shared_read_blocks,
    root_node_type,
    root_actual_rows,
    root_plan_rows,
    current_execution_ms,
    candidate_execution_ms,
    CASE WHEN candidate_execution_ms > 0
         THEN round(current_execution_ms / candidate_execution_ms, 3)
    END                                               AS execution_reduction_factor,
    current_shared_hit,
    candidate_shared_hit,
    CASE WHEN candidate_shared_hit > 0
         THEN round(current_shared_hit::numeric / candidate_shared_hit::numeric, 3)
    END                                               AS shared_hit_reduction_factor,
    plan_json
FROM paired
ORDER BY sequence_number, implementation;

-- ================================================================
-- ============== FIM DA CALL 1 / INÍCIO DA CALL 2 ================
-- ================================================================

-- ================================================================
-- PASSO 8 — ROLLBACK incondicional. Remove fixtures, TEMP TABLEs,
-- helpers pg_temp, GRANTs temporários E as duas funções candidatas
-- (DDL de função é transacional no PostgreSQL).
-- ================================================================
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
ROLLBACK;

-- ================================================================
-- PASSO 9 (fora de transação) — prova de zero resíduo pós-ROLLBACK.
-- Inclui a checagem explícita de que NENHUMA função candidata
-- sobreviveu ao ROLLBACK.
-- ================================================================
SELECT
    (SELECT count(*) FROM public.collection
      WHERE name LIKE 'AB-TEST-FATIA-E-%')                                       AS collections_com_prefixo_depois,
    (SELECT count(*) FROM public.storage_container
      WHERE name LIKE 'AB-TEST-FATIA-E-%')                                       AS storage_com_prefixo_depois,
    (SELECT count(*) FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname LIKE '%_fatia_e_candidate')                                 AS funcoes_candidatas_remanescentes;

/*
------------------------------------------------------------------
RESULTADO (a preencher na execução real):
- 26 linhas de performance (13 workloads x CURRENT/CANDIDATE).
- `all_gates_passed` e `semantic_equivalent` por workload. Com o gate
  FAIL-CLOSED do v1.1, ambos serão TRUE por construção se o PASSO 7 for
  alcançado; qualquer outro valor indica falha do próprio harness e
  REPROVA a bateria. Uma divergência semântica real não chega até aqui:
  ela aborta a CALL 1 com SEMANTIC_GATE_FAILED.
- `execution_reduction_factor` e `shared_hit_reduction_factor` por
  sequence_number.
- Recalcular blocks/par por estado para verificar se a constante de
  ~3,02 da CURRENT desaparece na CANDIDATE.
- Os 3 postchecks do PASSO 9 devem retornar 0 / 0 / 0.
- Nenhum índice criado nesta rodada. Se a candidata for aprovada,
  5102/5103 seguem para autorização de aplicação — e 5814 v1.3 deve
  ser reexecutado INALTERADO como regressão funcional obrigatória.
------------------------------------------------------------------
*/
