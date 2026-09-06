/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5815 - Performance Fatia E (REFERENCE_POSITION Completion)
Versão......: 1.2 (PERFORMANCE-HARNESS-REVISION-01)
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-STAGING-01,
               revisado em COLLECTIONS-POKEDEX-FATIA-E-STAGING-REVISION-01
               após auditoria direta — PASS; harness de captura revisado
               em COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-HARNESS-
               REVISION-01, após STOP legítimo em COLLECTIONS-POKEDEX-
               FATIA-E-PERFORMANCE-01)

================================================================
CORREÇÃO v1.2 (PERFORMANCE-HARNESS-REVISION-01)
================================================================
Revisão EXCLUSIVA do mecanismo de CAPTURA dos planos de execução.
NENHUM workload foi removido, acrescentado ou semanticamente alterado.
NENHUM fixture, volume, batching, Collection, parâmetro, cenário ou
ordem conceitual de estados foi tocado.

MOTIVO — limitação real de integração (STOP legítimo):
A execução desta bateria acontece via a ferramenta `execute_sql` do
Supabase MCP, que retorna SOMENTE o result set da ÚLTIMA instrução de
cada chamada (comportamento confirmado empiricamente na execução de
5814). A v1.1 emitia 13 instruções `EXPLAIN (ANALYZE, BUFFERS, FORMAT
TEXT)` independentes, cada uma devolvendo seu próprio result set:

- Submetido o arquivo inteiro, a ferramenta devolveria apenas o
  postcheck de resíduo (última instrução) — os 13 planos seriam
  perdidos.
- Submetido até o último EXPLAIN, devolveria 1 plano e perderia 12.
- Executar cada EXPLAIN em chamada separada é impossível: cada chamada
  é uma conexão independente, e as fixtures vivem dentro de uma
  transação não commitada — elas não existem na conexão seguinte.

Como o PostgreSQL não persiste os result sets de `EXPLAIN` em lugar
nenhum consultável posteriormente, não havia caminho de captura sem
alterar este arquivo. Daí o STOP em COLLECTIONS-POKEDEX-FATIA-E-
PERFORMANCE-01 — considerado CORRETO pelo mandato seguinte, que
autorizou esta revisão de harness.

PRECEDENTE ARQUITETURAL (obrigatório, mandato item 2):
`database/proposals/2026-09-02-02f-master-set/
5813_performance_checks_collections_physical_increment_02f.sql`
— mesmo padrão: TEMP TABLE `perf_results`, `EXPLAIN ... FORMAT JSON`
capturado com `EXECUTE ... INTO v_json`, `INSERT INTO perf_results`,
e um único SELECT consolidado ao final.

O QUE MUDOU (somente harness):
1. `FORMAT TEXT` -> `FORMAT JSON` nos 13 EXPLAINs.
2. Cada EXPLAIN passou a ser executado via `EXECUTE ... INTO v_json`
   dentro de um bloco `DO`, com o plano inserido em `perf_results`.
   O texto do SELECT medido é preservado byte-a-byte (ver abaixo).
3. TEMP TABLE nova `perf_results (sequence_number, scenario_label,
   workload_label, plan_json)` criada no PASSO 0, com
   GRANT SELECT/INSERT a `authenticated` no PASSO 0B — ANTES do
   primeiro `SET ROLE authenticated`.
4. Um único SELECT consolidado sobre `perf_results` acrescentado como
   PASSO 1B, imediatamente antes do `RESET ROLE`/`ROLLBACK`,
   devolvendo os 13 planos em UMA resposta.
5. Marcadores explícitos de fronteira CALL 1 / CALL 2, para a mesma
   estratégia operacional já validada na execução de 5814.

O QUE NÃO MUDOU:
- As 13 instruções `SELECT` funcionais medidas são BYTE-IDÊNTICAS às
  da v1.1, inclusive as subqueries
  `(SELECT value::uuid FROM perf_ctx WHERE key = '...')` usadas como
  argumento. Nenhum `collection_id`, nenhum `p_only_missing`, nenhum
  parâmetro e nenhum momento de medição foi alterado. Por isso o
  EXECUTE usa string literal dollar-quoted, e NÃO `format()` com
  interpolação de UUID — interpolar o UUID resolvido antes da medição
  mudaria o texto do statement medido (o precedente 5813 podia usar
  `format()` porque lá os workloads já nasceram assim; aqui a
  fidelidade ao statement da v1.1 tem precedência sobre a forma
  cosmética do precedente).
- Fixtures, Collections, Pokédex NATIONAL real (1025 Positions), pool
  de Species resolvidas sem LIMIT, batching <= 500, os 5 cenários, a
  ordem conceitual dos estados, BEGIN/ROLLBACK incondicional e o
  postcheck de zero resíduo: todos preservados integralmente.
- Nenhuma métrica derivada é computada entre o EXPLAIN e o INSERT: o
  INSERT grava apenas o `plan_json` bruto. Toda derivação
  (Execution Time, Planning Time, shared hit/read, node type,
  cardinalidade raiz) acontece no SELECT consolidado final, depois de
  todas as medições terem terminado — zero risco de a leitura alterar
  a execução medida. O `plan_json` bruto permanece a autoridade.
- NENHUM índice criado. NENHUM SQL de produção alterado. NENHUMA
  alteração no banco de produção. Este arquivo continua sendo
  exclusivamente uma bateria transacional BEGIN...ROLLBACK.

================================================================
MAPEAMENTO DOS 13 WORKLOADS (obrigatório, mandato item 5)
================================================================
seq | cenário                                   | workload
----|-------------------------------------------|--------------------
  1 | 1 - FULL_REFERENCE / 0 Assignments        | summary
  2 | 1 - FULL_REFERENCE / 0 Assignments        | positions FALSE
  3 | 1 - FULL_REFERENCE / 0 Assignments        | positions TRUE
  4 | 2 - FULL_REFERENCE / high-density         | summary
  5 | 2 - FULL_REFERENCE / high-density         | positions FALSE
  6 | 2 - FULL_REFERENCE / high-density         | positions TRUE
  7 | 3 - GENERATION_FILTERED                   | summary vazio
  8 | 3 - GENERATION_FILTERED                   | positions FALSE vazio
  9 | 3 - GENERATION_FILTERED                   | summary parcial
 10 | 3 - GENERATION_FILTERED                   | positions TRUE parcial
 11 | 4 - duplicatas concentradas               | summary
 12 | 5 - Assignments fora do Scope             | summary
 13 | 5 - Assignments fora do Scope             | positions FALSE

Total: 13 planos capturados — exatamente os 13 EXPLAINs da v1.1.

================================================================
ESTRATÉGIA OPERACIONAL DE EXECUÇÃO (mandato item 7) — NÃO EXECUTAR
AGORA. Este arquivo aguarda auditoria direta antes do GO.
================================================================
CALL 1 — do `BEGIN` (PASSO 0) até o SELECT consolidado (PASSO 1B),
         inclusive. O SELECT consolidado deve ser a ÚLTIMA instrução
         submetida na chamada. Captura os 13 planos em uma resposta.
         A transação permanece ABERTA ao final da chamada; o
         PostgreSQL garante rollback automático no encerramento da
         conexão (nunca faz auto-commit de transação aberta).
CALL 2 — somente o trecho final: PASSO 2 (`RESET ROLE`, auth cleanup,
         `ROLLBACK`) e PASSO 3 (postcheck de zero resíduo). O
         `ROLLBACK` é no-op caso a conexão da CALL 1 já tenha sido
         encerrada e auto-revertida.
PASSO -1 (baseline de resíduo) está FORA da transação e pode ser
         executado isoladamente como precheck, antes da CALL 1.

================================================================
Descrição...:
Medição de performance de 5100 (ramo REFERENCE_POSITION de
collection_completion_summary()) e 5101
(collection_pokedex_scope_positions()), mesmo mecanismo já usado em
5809/5813: EXPLAIN (ANALYZE, BUFFERS) em fixtures transacionais reais
(BEGIN...ROLLBACK, zero resíduo), NUNCA em produção. Ao contrário de
5814 (que usa um Pokédex de teste isolado de 5 Positions, por precisar
de estados de negócio exatos e controláveis), esta bateria usa a
Pokédex NATIONAL real (1025 Positions, Query 6040) — o volume real é o
próprio objeto de medição.

NENHUM ÍNDICE NOVO é criado nesta rodada (decisão explícita do mandato
de staging, item 8). Se o plano revelar um gargalo real, esta Query
apenas REPORTA — corrigir exigiria nova autorização explícita, mesmo
princípio já aplicado em 5809/5813.

Cenários medidos (mandato, Seção 7 da revisão):
1. FULL_REFERENCE, 1025 Positions, 0 Assignments (baseline "vazio em
   escala real").
2. FULL_REFERENCE, 1025 Positions, high-density — consome TODO o pool
   de Species resolvidas disponível no catálogo real (sem cap
   artificial), em lotes de no máximo 500 por chamada de
   add_physical_cards()/allocate_physical_cards_to_collection().
3. GENERATION_FILTERED — 1 Generation real (a de maior cobertura de
   Species resolvidas, escolhida dinamicamente) — 0 Assignments e
   parcial (mesmo batching defensivo de <=500, caso a Generation tenha
   mais de 500 Species resolvidas).
4. Duplicatas: N Physical Cards adicionais da MESMA Variant, todas
   satisfazendo a MESMA Position — mede o custo do DISTINCT do
   numerator sob concentração.
5. Assignments fora do Scope: Physical Cards cujas Species resolvidas
   pertencem a Generations FORA do filtro corrente — mede o custo de
   `reference_position_scope` filtrar essas linhas para fora do
   numerator sem nunca as excluir fisicamente.
6. collection_completion_summary() em cada estado acima.
7. collection_pokedex_scope_positions() com p_only_missing = FALSE e
   TRUE em cada estado acima.

Histórico da correção v1.1 (STAGING-REVISION-01), preservado:
1. TEMP PRIVILEGES — faltavam GRANTs explícitos em `perf_ctx`/
   `perf_resolved_pool` para o role `authenticated` (objetos TEMP não
   herdam privilégio de PUBLIC por padrão, ao contrário de funções).
2. DIVERGÊNCIA CABEÇALHO x CÓDIGO — a v1.0 afirmava "duas chamadas
   cobrem até 1000 Species", mas o código só executava UM batch de até
   500 (teto real de `allocate_physical_cards_to_collection()`, Query
   5046 v1.2). Corrigido para um laço `WHILE` que consome o pool
   inteiro em lotes de <=500. `5814` já prova COMPLETE semanticamente
   (Caso E); `5815` mede exclusivamente plano/tempo em escala real.

Índice já existente relevante (sem criação nesta rodada):
`idx_collection_pokedex_position_assignment_position_id` (Query 6117)
— cobre o lado `pokedex_position_id` do JOIN de
`reference_position_numer`/`satisfied`. As duas UNIQUE de
`pokedex_position(pokedex_id, ...)` (Query 6040) cobrem o JOIN de
`reference_position_scope`/`scope`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo
-- ================================================================
SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection
WHERE name LIKE 'PERF-TEST-FATIA-E-%';

-- ================================================================
-- ============ INÍCIO DA CALL 1 (BEGIN -> PASSO 1B) ==============
-- ================================================================

-- ================================================================
-- PASSO 0 — BEGIN
-- ================================================================
BEGIN;

CREATE TEMP TABLE perf_ctx (key TEXT PRIMARY KEY, value TEXT);

-- Owner não-admin com Inventory, Game POKEMON, Language, Pokédex NATIONAL.
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
    VALUES ((SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a'), 'PERF-TEST-FATIA-E-STORAGE')
    RETURNING id
)
INSERT INTO perf_ctx (key, value) SELECT 'storage_a', id::text FROM ins;

-- Generation real com maior cobertura de Species resolvidas
-- (card_primary_species + Card Variant) — usada no cenário
-- GENERATION_FILTERED.
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

-- Pool de TODAS as Card Variants distintas cuja Species já está
-- resolvida (card_primary_species) — 1 por Species, para não
-- concentrar todas as Assignments em poucas Positions no cenário
-- "high-density". CORREÇÃO v1.1 (item 2): sem LIMIT — "todo o pool de
-- Species resolvidas disponível", consumido em lotes de <=500 no
-- Cenário 2, nunca um cap artificial de 1000.
CREATE TEMP TABLE perf_resolved_pool AS
SELECT DISTINCT ON (sp.id)
    sp.id           AS species_id,
    sp.generation_id AS generation_id,
    cv.id           AS variant_id
FROM public.pokemon_species sp
JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
JOIN public.card_variant cv ON cv.card_id = cps.card_id
ORDER BY sp.id, cv.id;

SELECT count(*) AS resolved_pool_size FROM perf_resolved_pool;

-- TEMP TABLE de evidência do benchmark (NOVA na v1.2 — harness).
-- Contrato mínimo do mandato (item 3). Guarda SOMENTE o plano bruto;
-- nenhuma métrica é derivada no caminho de captura. Toda derivação
-- acontece no SELECT consolidado do PASSO 1B, após o fim de todas as
-- medições. `sequence_number` é INTEGER explícito (não SERIAL) — não
-- há sequence associada, logo não é preciso GRANT USAGE em sequence.
CREATE TEMP TABLE perf_results (
    sequence_number  INTEGER PRIMARY KEY,
    scenario_label   TEXT NOT NULL,
    workload_label   TEXT NOT NULL,
    plan_json        JSON NOT NULL
);

-- ================================================================
-- PASSO 0B — GRANTs em objetos TEMP (CORREÇÃO v1.1, item 1; ampliado
-- na v1.2 para incluir `perf_results`). Objetos TEMP não herdam
-- privilégio de PUBLIC por padrão — sem isto, qualquer leitura/escrita
-- em perf_ctx/perf_resolved_pool/perf_results feita sob
-- "SET ROLE authenticated" (Passo 1 em diante) falharia por permissão
-- negada. Emitidos ANTES do primeiro SET ROLE.
-- ================================================================
GRANT SELECT, INSERT ON perf_ctx TO authenticated;
GRANT SELECT ON perf_resolved_pool TO authenticated;
GRANT SELECT, INSERT ON perf_results TO authenticated;

-- ================================================================
-- PASSO 1 — Collections de performance (Owner A, via RPC real)
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM perf_ctx WHERE key = 'owner_a'), true);

WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        'PERF-TEST-FATIA-E-COL-FULL', NULL,
        (SELECT value::uuid FROM perf_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'pokedex_national_id'),
        'FULL_REFERENCE', NULL
    )
)
INSERT INTO perf_ctx (key, value) SELECT 'col_full', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        'PERF-TEST-FATIA-E-COL-GEN', NULL,
        (SELECT value::uuid FROM perf_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'pokedex_national_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM perf_ctx WHERE key = 'gen_top_id')]
    )
)
INSERT INTO perf_ctx (key, value) SELECT 'col_gen', id::text FROM ins;

-- ================================================================
-- CENÁRIO 1 — FULL_REFERENCE, 1025 Positions, 0 Assignments.
-- Workloads 1, 2 e 3.
-- ================================================================
DO $outer$
DECLARE v_json JSON;
BEGIN
    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (1, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'summary', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (2, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'positions FALSE', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (3, 'CENARIO 1 - FULL_REFERENCE 1025 / 0 Assignments', 'positions TRUE', v_json);
END $outer$;

-- ================================================================
-- CENÁRIO 2 — FULL_REFERENCE, high-density: consome TODO o
-- perf_resolved_pool disponível, em lotes de no máximo 500 por chamada
-- de add_physical_cards()/allocate_physical_cards_to_collection()
-- (CORREÇÃO v1.1, item 2 — WHILE loop, nunca um número fixo de
-- "batches" nem um cap artificial de 1000/1025).
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

DO $outer$
DECLARE v_json JSON;
BEGIN
    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (4, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'summary', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), FALSE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (5, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'positions FALSE', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'), TRUE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (6, 'CENARIO 2 - FULL_REFERENCE 1025 / high-density', 'positions TRUE', v_json);
END $outer$;

-- ================================================================
-- CENÁRIO 3 — GENERATION_FILTERED (1 Generation real), 0 Assignments
-- e depois parcial (Physical Cards restritas às Species da própria
-- Generation filtrada — reaproveita o pool, filtrado por
-- generation_id). Mesmo batching defensivo de <=500 do Cenário 2,
-- aplicado por segurança caso a Generation escolhida tenha mais de 500
-- Species resolvidas.
-- Workloads 7 e 8 (vazio), 9 e 10 (parcial).
-- ================================================================
DO $outer$
DECLARE v_json JSON;
BEGIN
    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (7, 'CENARIO 3 - GENERATION_FILTERED', 'summary vazio', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (8, 'CENARIO 3 - GENERATION_FILTERED', 'positions FALSE vazio', v_json);
END $outer$;

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

DO $outer$
DECLARE v_json JSON;
BEGIN
    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (9, 'CENARIO 3 - GENERATION_FILTERED', 'summary parcial', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), TRUE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (10, 'CENARIO 3 - GENERATION_FILTERED', 'positions TRUE parcial', v_json);
END $outer$;

-- ================================================================
-- CENÁRIO 4 — Duplicatas: 50 Physical Cards adicionais da MESMA
-- Variant (primeira do pool), todas satisfazendo a MESMA Position em
-- col_full — mede o custo do DISTINCT/COUNT DISTINCT do numerator sob
-- concentração.
-- Workload 11.
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

DO $outer$
DECLARE v_json JSON;
BEGIN
    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_full'))$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (11, 'CENARIO 4 - duplicatas concentradas', 'summary', v_json);
END $outer$;

-- ================================================================
-- CENÁRIO 5 — Assignments fora do Scope: em col_gen (Scope = 1
-- Generation), aloca Physical Cards cujas Species resolvidas
-- pertencem a OUTRAS Generations (mesma Pokédex NATIONAL, fora do
-- filtro corrente) — mede o custo de reference_position_scope excluir
-- essas linhas do numerator sob volume.
-- Workloads 12 e 13.
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

DO $outer$
DECLARE v_json JSON;
BEGIN
    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_completion_summary((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'))$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (12, 'CENARIO 5 - Assignments fora do Scope', 'summary', v_json);

    EXECUTE $q$EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM perf_ctx WHERE key = 'col_gen'), FALSE)$q$
    INTO v_json;
    INSERT INTO perf_results (sequence_number, scenario_label, workload_label, plan_json)
    VALUES (13, 'CENARIO 5 - Assignments fora do Scope', 'positions FALSE', v_json);
END $outer$;

-- ================================================================
-- PASSO 1B — LEITURA FINAL CONSOLIDADA (NOVO na v1.2 — harness).
-- Único SELECT que devolve os 13 planos em uma resposta. Todas as
-- métricas são derivadas AQUI, depois de todas as medições terem
-- terminado — nenhuma computação de métrica ocorre entre o EXPLAIN e
-- o INSERT correspondente. `plan_json` bruto vai junto e permanece a
-- autoridade sobre qualquer campo derivado.
--
-- Nota de leitura: `EXPLAIN ... FORMAT JSON` devolve um array JSON de
-- um elemento; daí o `-> 0`. Em `Shared Hit/Read Blocks`, o nó raiz do
-- plano já é cumulativo da árvore inteira (comportamento padrão do
-- PostgreSQL), portanto os valores da raiz são os totais do workload.
--
-- ESTA DEVE SER A ÚLTIMA INSTRUÇÃO DA CALL 1.
-- ================================================================
SELECT
    r.sequence_number,
    r.scenario_label,
    r.workload_label,
    (r.plan_json -> 0 ->> 'Execution Time')::numeric                 AS execution_time_ms,
    (r.plan_json -> 0 ->> 'Planning Time')::numeric                  AS planning_time_ms,
    (r.plan_json -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint     AS shared_hit_blocks,
    (r.plan_json -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint    AS shared_read_blocks,
    (r.plan_json -> 0 -> 'Plan' ->> 'Node Type')                     AS root_node_type,
    (r.plan_json -> 0 -> 'Plan' ->> 'Relation Name')                 AS root_relation_name,
    (r.plan_json -> 0 -> 'Plan' ->> 'Actual Rows')::numeric          AS root_actual_rows,
    (r.plan_json -> 0 -> 'Plan' ->> 'Plan Rows')::numeric            AS root_estimated_rows,
    r.plan_json                                                       AS plan_json
FROM perf_results r
ORDER BY r.sequence_number;

-- ================================================================
-- ============== FIM DA CALL 1 / INÍCIO DA CALL 2 ================
-- ================================================================

-- ================================================================
-- PASSO 2 — ROLLBACK incondicional (zero resíduo)
-- ================================================================
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
ROLLBACK;

-- ================================================================
-- PASSO 3 (fora de transação) — prova de zero resíduo pós-ROLLBACK
-- ================================================================
SELECT count(*) AS collections_com_prefixo_depois
FROM public.collection
WHERE name LIKE 'PERF-TEST-FATIA-E-%';

/*
------------------------------------------------------------------
RESULTADO (a preencher na execução real):
- Tempo de execução de cada EXPLAIN ANALYZE, por cenário (13 linhas do
  SELECT consolidado do PASSO 1B).
- Nós de Seq Scan (se houver) e sobre qual tabela — ler do plan_json
  bruto, que é a autoridade.
- Buffers lidos (shared hit/read), já derivados no PASSO 1B.
- Comparação Cenário 1 (0 Assignments) vs Cenário 2 (high-density, todo
  o pool disponível) vs Cenário 4 (duplicatas concentradas) vs Cenário
  5 (fora do Scope em volume) — o custo deve escalar com o tamanho do
  Scope e do número de Assignments da Collection, não com o tamanho
  total do catálogo Pokémon (mesmo padrão já confirmado em 5813 para
  MASTER_SET).
- Nenhum índice novo criado nesta rodada. Se um gargalo real for
  identificado, reportar aqui — não corrigir sem nova autorização
  explícita de Fabrício.
------------------------------------------------------------------
*/
