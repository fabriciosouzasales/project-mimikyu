/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5807 - Performance Test Plan: Collections Physical Increment 02C (PROPOSTA)
Versão......: 1.3
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
               REVISION-01, item 9 → -FINAL-01, item 6 →
               -STAGING-REVISION-01, itens 4/5 → -STAGING-FINAL-01 —
               script efetivamente executável → -STAGING-FINAL-FIX-01
               — GRANT de TEMP TABLE antes da troca de role (BLOCKER),
               contagem de Collections corrigida para 24, nota de
               interpretação do planner neutralizada)

Descrição...:
Plano de teste de performance pós-migration para public.
collection_allocation e as duas RPCs allocate_physical_cards_to_
collection()/deallocate_physical_cards_from_collection(). NÃO EXECUTAR
nesta rodada; requer que as Queries 5040-5048 estejam aplicadas.

CORREÇÃO (COLLECTIONS-PHYSICAL-INCREMENT-02C-STAGING-FINAL-01). As
versões 1.0/1.1 eram majoritariamente esboço comentado (blocos `--`
descrevendo a intenção, sem SQL literal executável, com placeholders
tipo `:'owner_a_id'` que nem sequer são sintaxe SQL válida — são
sintaxe de variável do psql). Esta versão é SQL real, pensado para ser
colado e executado em UMA ÚNICA chamada execute_sql (mesma conexão/
sessão do início ao fim), sem edição manual de UUID em nenhum ponto —
toda resolução de identificadores é feita dinamicamente pelo próprio
script, via tabelas TEMP e subqueries.

Correções de quantidade/escopo desta rodada (itens 2/3 de
-STAGING-REVISION-01, fechados aqui):
- Quantidade de Physical Cards corrigida para refletir
  UNIQUE(collection_allocation.physical_card_id): >= 20.000 Allocations
  de baseline exigem >= 20.000 Physical Cards DISTINTAS (não é possível
  reusar a mesma Physical Card em duas Allocations). Total sintetizado:
  21.601 Physical Cards distintas — ver "Orçamento de Physical Cards"
  abaixo para o detalhamento exato de cada uso;
- Pré-condição reduzida de >= 2 Owners para >= 1 Owner com Inventory
  existente — os workloads A-E usam só Owner A; cross-user (RLS entre
  Owners) é responsabilidade de 5806, não deste arquivo de performance.

Orçamento de Physical Cards (total 21.601, todas do mesmo Owner A e do
mesmo Game, sintetizadas dentro da transação revertida):
  5.000  -> workload A (Collection dedicada, volume alto de propósito,
            prova de seletividade real do índice mesmo sem ser a
            maior fatia do dataset)
 15.000  -> baseline distribuído round-robin entre 20 Collections
            "filler" (750 cada) — completa as >= 20.000 Allocations de
            baseline exigidas, sem concentrar tudo numa única Collection
    500  -> workload E, pré-alocadas no setup (Collection dedicada,
            isolada do pool de leitura de A, para não interferir com a
            medição de A quando E for desalocado)
    500  -> workload C, livres no início da medição (Collection
            dedicada, ainda sem nenhuma Allocation -> started_at NULL)
      1  -> priming de workload D (1 allocate real, via RPC, ANTES da
            medição, só para popular started_at legitimamente)
    500  -> workload D, livres no início da medição (mesma Collection
            do priming acima, já com started_at definido)
    100  -> margem técnica (Physical Cards sintetizadas mas não usadas
            por nenhum workload — buffer contra qualquer imprecisão de
            contagem, nunca tocadas)
 ------
 21.601  TOTAL

Setup via INSERT direto (role privilegiada da própria conexão,
respeitando literalmente o item 4 de -STAGING-REVISION-01): Storage
Container, as 24 Collections de teste (1 workload_a + 20 filler + 1
workload_c + 1 workload_d + 1 workload_e = 24; workload_c/workload_d
são criadas vazias — workload_d só recebe sua primeira Allocation via
RPC, no priming, e workload_c permanece sem nenhuma Allocation até o
próprio workload C ser medido) e as 20.500 Allocations de
baseline+E são INSERT set-based direto em collection_allocation — SEM
bypass de trigger: 5042 (validação estrutural) e 5045 (materialização
de started_at) dispararam normalmente sobre esses INSERTs, porque o
Owner/Game/Inventory sintéticos são internamente consistentes (mesmo
Owner, mesmo Game, mesmo Inventory em toda a massa de dados). Os
workloads C/D/E, por instrução explícita da rodada anterior, chamam as
RPCs reais (allocate_physical_cards_to_collection()/
deallocate_physical_cards_from_collection()), não INSERT/DELETE direto.

Ordem de execução (Passo 3 = TEMP TABLE de resultados + GRANT, SEMPRE
antes do Passo 4 = troca de role — sem a contradição textual das
versões anteriores):
  Passo -1 (fora de transação) — baseline de resíduo ANTES do setup.
  Passo 0  — BEGIN; pré-condição (>= 1 Owner com Inventory; catálogo
             mínimo presente: >= 1 Game, >= 1 Card Variant encadeável a
             esse Game, >= 1 Language); aborta com RAISE EXCEPTION e
             diagnóstico explícito se qualquer pré-condição falhar.
  Passo 1  — resolver contexto (Owner A, Inventory A, Game, Card
             Variant, Language) em TEMP TABLE perf_ctx.
  Passo 2  — sintetizar (role privilegiada): Storage Container,
             21.601 Physical Cards, 24 Collections, 20.500 Allocations
             de baseline+E (INSERT direto, triggers ativos).
  Passo 3  — CREATE TEMP TABLE perf_results + GRANT SELECT em TODAS as
             TEMP TABLEs que os blocos pós-troca-de-role precisam ler
             (perf_ctx, perf_collections, perf_physical_cards) + GRANT
             INSERT, SELECT em perf_results — TUDO antes do Passo 4
             (correção -STAGING-FINAL-FIX-01, item 1 — ver "TEMP TABLE
             privileges" abaixo). perf_storage NÃO precisa de GRANT —
             nenhum bloco a consulta depois da troca de role.
  Passo 4  — set_config('role','authenticated', true) +
             set_config('request.jwt.claim.sub', <owner_a>, true) —
             ambos com is_local = true, portanto revertidos
             automaticamente pelo ROLLBACK final, sem necessidade de
             reset explícito (fecha o ponto de "garantir que a sessão
             consiga retornar ao contexto necessário" — o contexto
             correto pós-ROLLBACK é simplesmente o original, porque
             set_config(..., true) nunca escapa da transação).
  Passo 5  — priming de workload D (1 allocate real, não medido) +
             workloads A-E medidos via EXPLAIN (ANALYZE, BUFFERS,
             FORMAT JSON), cada um capturado em perf_results por um
             bloco DO $$ ... $$ com EXECUTE ... INTO (mesma técnica já
             descrita, em intenção, desde 5805).
  Passo 6  — SELECT * FROM perf_results (leitura final, ainda dentro
             da transação).
  Passo 7  — ROLLBACK.
  Passo 8  (fora de transação, mesma sessão/chamada) — prova de zero
             resíduo pós-ROLLBACK: repetir a contagem do Passo -1
             (deve bater exatamente) + confirmar 0 Collections/Storage
             Container com o prefixo de nome sintético.

TEMP TABLE privileges (BLOCKER corrigido em -STAGING-FINAL-FIX-01,
item 1). set_config('role', 'authenticated', true) muda a identidade
de verificação de privilégio da sessão a partir daquele ponto — TEMP
TABLEs criadas pela role privilegiada original NÃO ficam
automaticamente legíveis pela nova role só por estarem na mesma sessão;
privilégio em tabela (inclusive temp) é por role, não por sessão. Sem
GRANT explícito, todo `SELECT ... FROM perf_ctx/perf_collections/
perf_physical_cards` dentro dos blocos DO executados como authenticated
(o `set_config('request.jwt.claim.sub', ...)` do próprio Passo 4, o
priming de workload D, e os 5 workloads A-E) falharia com "permission
denied for table". Corrigido: os quatro GRANTs (perf_ctx,
perf_collections, perf_physical_cards, perf_results) agora acontecem
no Passo 3, antes de qualquer set_config de role. perf_storage não
precisa de GRANT — nenhum bloco a consulta depois da troca de role (o
id do Storage Container só é necessário durante a síntese das
Collections, no Passo 2, ainda como role privilegiada).

Zero resíduo — estratégia (item 8 da rodada -STAGING-REVISION-01,
fechado aqui). A garantia estrutural primária é o próprio ROLLBACK:
nenhum efeito de um INSERT/UPDATE/DELETE dentro de uma transação
revertida sobrevive a ela — isso vale simetricamente para as 21.601
Physical Cards, as 24 Collections, os >= 21.000 Collection Allocations
e o Storage Container sintéticos, sem exceção, por ser uma garantia do
motor (ACID), não algo que dependa de nenhuma lógica deste script.
Ainda assim, como pedido explicitamente, o Passo 8 executa uma prova
adicional PÓS-ROLLBACK, na MESMA chamada/sessão (o ROLLBACK encerra a
transação, não a conexão — instruções SQL soltas depois dele continuam
executando normalmente na mesma sessão, voltando a autocommit): (a)
recontagem de Physical Cards do Owner A resolvido, comparada
byte-a-byte contra a contagem feita no Passo -1, antes de qualquer
synthesize; (b) contagem de Collections/Storage Container com o prefixo
`PERF-TEST-02C-%`, que deve ser exatamente 0. physical_card não tem
coluna de marcação textual (schema real, Query 5010) — por isso o (a)
é uma comparação de contagem total do Inventory, não um filtro por
nome; é comparável porque a resolução do Owner A é determinística
(mesmo critério de ordenação em ambas as chamadas) e nenhuma escrita
real (fora desta própria transação revertida) deveria alterar essa
contagem entre o Passo -1 e o Passo 8 numa execução isolada.

Nenhuma alegação de performance deve ser feita antes da execução real.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo ANTES do setup.
-- Mesmo critério de resolução determinística de Owner A usado dentro
-- do script (ORDER BY owner_user_id LIMIT 1), para que a contagem
-- "antes" e a contagem "depois" (Passo 8) apontem para o mesmo
-- Inventory.
-- ================================================================
SELECT count(*) AS physical_card_count_antes
FROM public.physical_card
WHERE inventory_id = (
    SELECT id FROM public.inventory ORDER BY owner_user_id LIMIT 1
);
-- Registrar o valor retornado (N0) na execução real — comparado no
-- Passo 8, na mesma chamada/sessão, depois do ROLLBACK.

-- ================================================================
-- PASSO 0 — BEGIN + pré-condições
-- ================================================================
BEGIN;

DO $$
DECLARE
    v_owner_count INT;
    v_game_count  INT;
    v_variant_count INT;
    v_language_count INT;
BEGIN
    SELECT count(DISTINCT owner_user_id) INTO v_owner_count FROM public.inventory;
    IF v_owner_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: >= 1 Owner com Inventory necessário (encontrados: %)', v_owner_count;
    END IF;

    SELECT count(*) INTO v_game_count FROM public.game;
    IF v_game_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Game encontrado em public.game';
    END IF;

    SELECT count(*) INTO v_variant_count
    FROM public.card_variant cv
    JOIN public.card c ON c.id = cv.card_id
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion ex ON ex.id = cs.expansion_id;
    IF v_variant_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Card Variant encadeável a um Game via card->card_set->expansion';
    END IF;

    SELECT count(*) INTO v_language_count FROM public.language;
    IF v_language_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Language encontrada em public.language';
    END IF;
END $$;

-- ================================================================
-- PASSO 1 — resolver contexto (Owner A, Inventory A, Game, Card
-- Variant compatível com esse Game, Language) em TEMP TABLE
-- ================================================================
CREATE TEMP TABLE perf_ctx (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO perf_ctx (key, value)
SELECT 'owner_a', owner_user_id::text
FROM public.inventory
ORDER BY owner_user_id
LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'inventory_a', id::text
FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a');

INSERT INTO perf_ctx (key, value)
SELECT 'language_id', id::text
FROM public.language
LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'card_variant_id', cv.id::text
FROM public.card_variant cv
JOIN public.card c ON c.id = cv.card_id
JOIN public.card_set cs ON cs.id = c.card_set_id
JOIN public.expansion ex ON ex.id = cs.expansion_id
LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'game_id', ex.game_id::text
FROM public.card_variant cv
JOIN public.card c ON c.id = cv.card_id
JOIN public.card_set cs ON cs.id = c.card_set_id
JOIN public.expansion ex ON ex.id = cs.expansion_id
WHERE cv.id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_variant_id');

-- ================================================================
-- PASSO 2a — sintetizar Storage Container (role privilegiada, INSERT
-- direto)
-- ================================================================
CREATE TEMP TABLE perf_storage (id UUID);

WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    SELECT (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a'),
           'PERF-TEST-02C-STORAGE'
    RETURNING id
)
INSERT INTO perf_storage (id) SELECT id FROM ins;

-- ================================================================
-- PASSO 2b — sintetizar 21.601 Physical Cards distintas (role
-- privilegiada, INSERT direto, set-based) — ver "Orçamento de
-- Physical Cards" no cabeçalho para o detalhamento de cada faixa
-- ================================================================
CREATE TEMP TABLE perf_physical_cards (id UUID, rn BIGINT);

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'card_variant_id'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM generate_series(1, 21601)
    RETURNING id
)
INSERT INTO perf_physical_cards (id, rn)
SELECT id, row_number() OVER ()
FROM ins;

-- ================================================================
-- PASSO 2c — sintetizar as 24 Collections de teste (role privilegiada,
-- INSERT direto): 1 workload_a, 20 filler (baseline), 1 workload_c,
-- 1 workload_d, 1 workload_e = 24. workload_d é criada aqui vazia —
-- sua primeira Allocation (que materializa started_at) só é feita no
-- Passo 5, via RPC real, não aqui.
-- ================================================================
CREATE TEMP TABLE perf_collections (kind TEXT, id UUID);

WITH ins AS (
    INSERT INTO public.collection (owner_user_id, game_id, default_storage_container_id, name)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        (SELECT id FROM perf_storage),
        'PERF-TEST-02C-WORKLOAD-A'
    RETURNING id
)
INSERT INTO perf_collections (kind, id) SELECT 'workload_a', id FROM ins;

WITH ins AS (
    INSERT INTO public.collection (owner_user_id, game_id, default_storage_container_id, name)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        (SELECT id FROM perf_storage),
        'PERF-TEST-02C-BASELINE-' || n
    FROM generate_series(1, 20) AS n
    RETURNING id
)
INSERT INTO perf_collections (kind, id) SELECT 'filler', id FROM ins;

WITH ins AS (
    INSERT INTO public.collection (owner_user_id, game_id, default_storage_container_id, name)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        (SELECT id FROM perf_storage),
        'PERF-TEST-02C-WORKLOAD-C'
    RETURNING id
)
INSERT INTO perf_collections (kind, id) SELECT 'workload_c', id FROM ins;

WITH ins AS (
    INSERT INTO public.collection (owner_user_id, game_id, default_storage_container_id, name)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        (SELECT id FROM perf_storage),
        'PERF-TEST-02C-WORKLOAD-D'
    RETURNING id
)
INSERT INTO perf_collections (kind, id) SELECT 'workload_d', id FROM ins;

WITH ins AS (
    INSERT INTO public.collection (owner_user_id, game_id, default_storage_container_id, name)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        (SELECT id FROM perf_storage),
        'PERF-TEST-02C-WORKLOAD-E'
    RETURNING id
)
INSERT INTO perf_collections (kind, id) SELECT 'workload_e', id FROM ins;

-- ================================================================
-- PASSO 2d — sintetizar as Allocations de baseline (workload_a: 5.000
-- + 20 filler: 750 cada = 15.000) e de workload_e (500 pré-alocadas) —
-- INSERT direto set-based, SEM bypass de 5042/5045 (as duas triggers
-- disparam normalmente sobre estes INSERTs, porque Owner/Game/
-- Inventory são internamente consistentes em toda a massa sintética).
-- ================================================================

-- workload_a: 5.000 (rn 1-5000)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT pc.id, (SELECT id FROM perf_collections WHERE kind = 'workload_a')
FROM perf_physical_cards pc
WHERE pc.rn BETWEEN 1 AND 5000;

-- baseline filler: 15.000 (rn 5001-20000), round-robin entre as 20
-- Collections filler -> 750 cada, exatamente
WITH ranked_fillers AS (
    SELECT id, row_number() OVER (ORDER BY id) AS filler_rn
    FROM perf_collections
    WHERE kind = 'filler'
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT pc.id, rf.id
FROM perf_physical_cards pc
JOIN ranked_fillers rf ON rf.filler_rn = (((pc.rn - 5001) % 20) + 1)
WHERE pc.rn BETWEEN 5001 AND 20000;

-- workload_e: 500 pré-alocadas (rn 20001-20500)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT pc.id, (SELECT id FROM perf_collections WHERE kind = 'workload_e')
FROM perf_physical_cards pc
WHERE pc.rn BETWEEN 20001 AND 20500;

-- ================================================================
-- PASSO 3 — TEMP TABLE de resultados + GRANT em TODAS as TEMP TABLEs
-- que blocos executados como authenticated (Passo 4 em diante) vão
-- precisar ler — ANTES da troca de role (correção
-- -STAGING-FINAL-FIX-01, item 1 — BLOCKER: sem isto, todo SELECT
-- pós-troca-de-role contra perf_ctx/perf_collections/
-- perf_physical_cards falharia com "permission denied for table",
-- porque privilégio em tabela — inclusive TEMP TABLE — é por role, não
-- por sessão; set_config('role', 'authenticated', true) muda a partir
-- daquele ponto a identidade usada nessa verificação). perf_storage
-- NÃO recebe GRANT — nenhum bloco a consulta depois deste ponto.
-- ================================================================
CREATE TEMP TABLE perf_results (case_label TEXT, plan_json JSON);

GRANT SELECT ON perf_ctx TO authenticated;
GRANT SELECT ON perf_collections TO authenticated;
GRANT SELECT ON perf_physical_cards TO authenticated;
GRANT INSERT, SELECT ON perf_results TO authenticated;

-- Prova estática — confirma, ainda como role privilegiada e ANTES da
-- troca de role, que authenticated de fato tem SELECT nas 4 tabelas
-- que os blocos pós-Passo-4 vão consultar (perf_storage
-- deliberadamente fora desta lista — não é lida depois daqui).
SELECT
    'perf_ctx' AS temp_table,
    has_table_privilege('authenticated', 'pg_temp.perf_ctx', 'SELECT') AS authenticated_pode_ler
UNION ALL
SELECT 'perf_collections',
    has_table_privilege('authenticated', 'pg_temp.perf_collections', 'SELECT')
UNION ALL
SELECT 'perf_physical_cards',
    has_table_privilege('authenticated', 'pg_temp.perf_physical_cards', 'SELECT')
UNION ALL
SELECT 'perf_results',
    has_table_privilege('authenticated', 'pg_temp.perf_results', 'SELECT');
-- Esperado: authenticated_pode_ler = true nas 4 linhas. Se qualquer
-- uma vier false, os blocos do Passo 5 vão falhar — parar e corrigir
-- o GRANT correspondente antes de prosseguir (não ignorar).

-- ================================================================
-- PASSO 4 — trocar para o contexto do Owner A autenticado (is_local =
-- true em ambos: revertido automaticamente pelo ROLLBACK, sem reset
-- explícito necessário)
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub',
                   (SELECT value FROM perf_ctx WHERE key = 'owner_a'),
                   true);

-- ================================================================
-- PASSO 5 — priming de workload D (1 allocate real, NÃO medido, só
-- para popular started_at legitimamente pelo caminho real de
-- produção) + os 5 workloads medidos (A-E), cada um capturado em
-- perf_results via EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
-- ================================================================

-- priming de workload D (rn 21001) — fora de medição
DO $$
DECLARE
    v_collection_d UUID;
    v_prime_id     UUID;
BEGIN
    SELECT id INTO v_collection_d FROM perf_collections WHERE kind = 'workload_d';
    SELECT id INTO v_prime_id FROM perf_physical_cards WHERE rn = 21001;

    PERFORM * FROM public.allocate_physical_cards_to_collection(v_collection_d, ARRAY[v_prime_id]);
END $$;

-- Workload A — listar as Collection Allocations de uma Collection
-- (5.000 linhas, uso mais frequente esperado)
DO $$
DECLARE
    v_collection_a UUID;
    v_json         JSON;
BEGIN
    SELECT id INTO v_collection_a FROM perf_collections WHERE kind = 'workload_a';

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_allocation WHERE collection_id = %L::uuid',
        v_collection_a
    ) INTO v_json;

    INSERT INTO perf_results (case_label, plan_json)
    VALUES ('A - listar Allocations de 1 Collection (5.000 linhas)', v_json);
END $$;

-- Workload A2 (opcional, sanity check — COLLECTIONS-PHYSICAL-
-- INCREMENT-02C-STAGING-FINAL-FIX-01, item 3) — mesma consulta do
-- workload A, mas contra uma Collection filler (750 linhas, seletiva
-- em relação ao total de ~21.000 em collection_allocation). Não é um
-- dos 5 workloads pedidos originalmente; existe só como ponto de
-- contraste barato (mesmo padrão de query, volume bem menor) para
-- interpretar o plano de A com mais contexto, sem adicionar nenhuma
-- lógica nova ao benchmark.
DO $$
DECLARE
    v_collection_filler UUID;
    v_json               JSON;
BEGIN
    SELECT id INTO v_collection_filler
    FROM perf_collections
    WHERE kind = 'filler'
    ORDER BY id
    LIMIT 1;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_allocation WHERE collection_id = %L::uuid',
        v_collection_filler
    ) INTO v_json;

    INSERT INTO perf_results (case_label, plan_json)
    VALUES ('A2 (opcional) - listar Allocations de 1 Collection filler (750 linhas)', v_json);
END $$;

-- Workload B — localizar a Collection Allocation de uma Physical Card
-- específica
DO $$
DECLARE
    v_pc   UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_pc FROM perf_physical_cards WHERE rn = 1;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_allocation WHERE physical_card_id = %L::uuid',
        v_pc
    ) INTO v_json;

    INSERT INTO perf_results (case_label, plan_json)
    VALUES ('B - localizar Allocation por physical_card_id', v_json);
END $$;

-- Workload C — allocate_physical_cards_to_collection() de 500 numa
-- Collection AINDA SEM started_at (rn 20501-21000, livres)
DO $$
DECLARE
    v_collection_c UUID;
    v_ids          UUID[];
    v_json         JSON;
BEGIN
    SELECT id INTO v_collection_c FROM perf_collections WHERE kind = 'workload_c';
    SELECT array_agg(id) INTO v_ids FROM perf_physical_cards WHERE rn BETWEEN 20501 AND 21000;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])',
        v_collection_c, v_ids
    ) INTO v_json;

    INSERT INTO perf_results (case_label, plan_json)
    VALUES ('C - allocate 500 (Collection sem started_at)', v_json);
END $$;

-- Workload D — allocate_physical_cards_to_collection() de 500 numa
-- Collection JÁ com started_at (populado pelo priming acima; rn
-- 21002-21501, livres)
DO $$
DECLARE
    v_collection_d UUID;
    v_ids          UUID[];
    v_json         JSON;
BEGIN
    SELECT id INTO v_collection_d FROM perf_collections WHERE kind = 'workload_d';
    SELECT array_agg(id) INTO v_ids FROM perf_physical_cards WHERE rn BETWEEN 21002 AND 21501;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])',
        v_collection_d, v_ids
    ) INTO v_json;

    INSERT INTO perf_results (case_label, plan_json)
    VALUES ('D - allocate 500 (Collection com started_at ja definido)', v_json);
END $$;

-- Workload E — deallocate_physical_cards_from_collection() de 500
-- (as mesmas pré-alocadas no Passo 2d, rn 20001-20500)
DO $$
DECLARE
    v_collection_e UUID;
    v_ids          UUID[];
    v_json         JSON;
BEGIN
    SELECT id INTO v_collection_e FROM perf_collections WHERE kind = 'workload_e';
    SELECT array_agg(id) INTO v_ids FROM perf_physical_cards WHERE rn BETWEEN 20001 AND 20500;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, %L::uuid[])',
        v_collection_e, v_ids
    ) INTO v_json;

    INSERT INTO perf_results (case_label, plan_json)
    VALUES ('E - deallocate 500', v_json);
END $$;

-- ================================================================
-- PASSO 6 — leitura final dos planos capturados (ainda dentro da
-- transação)
-- ================================================================
SELECT case_label, plan_json FROM perf_results ORDER BY case_label;

-- ================================================================
-- PASSO 7 — desfazer tudo
-- ================================================================
ROLLBACK;

-- ================================================================
-- PASSO 8 (fora de transação, mesma sessão/chamada) — prova de zero
-- resíduo pós-ROLLBACK
-- ================================================================
SELECT count(*) AS physical_card_count_depois
FROM public.physical_card
WHERE inventory_id = (
    SELECT id FROM public.inventory ORDER BY owner_user_id LIMIT 1
);
-- Esperado: physical_card_count_depois = physical_card_count_antes
-- (Passo -1) — nenhuma das 21.601 Physical Cards sintéticas sobreviveu.

SELECT count(*) AS collections_residuais
FROM public.collection
WHERE name LIKE 'PERF-TEST-02C-%';
-- Esperado: 0

SELECT count(*) AS storage_containers_residuais
FROM public.storage_container
WHERE name = 'PERF-TEST-02C-STORAGE';
-- Esperado: 0

-- ================================================================
-- Nota de interpretação dos planos (revisada em -STAGING-FINAL-FIX-01,
-- item 3 — não tratar Seq Scan automaticamente como falha). Volume
-- representativo: 5.000 na Collection do workload A (~24% de ~21.000
-- linhas totais em collection_allocation após o setup), 750 na
-- Collection filler do workload A2, distribuídas entre 22 Collections
-- distintas do mesmo Owner que já têm Allocation no momento da leitura
-- (1 workload_a + 20 filler + 1 workload_e). Workload A lê uma fração
-- grande do total (~24%) — nessa faixa de seletividade, o planner PODE
-- legitimamente preferir Seq Scan em vez de Index Scan, dependendo dos
-- custos relativos estimados (não é, por si só, um sinal de problema).
-- Workload A2, por ler uma fatia bem menor (~3,6%), serve de contraste
-- de seletividade mais alta.
--
-- Para cada workload capturado em perf_results, registrar (não
-- assumir) a partir do JSON de EXPLAIN: o tipo de nó escolhido pelo
-- planner (Seq Scan/Index Scan/Bitmap Heap Scan/etc.), o tempo total
-- de execução, os buffers (shared hit/read), e se o índice
-- correspondente (ix_collection_allocation_collection para A/A2, o
-- índice único de physical_card_id para B) estava disponível e foi
-- ou não escolhido. Nenhuma conclusão de performance é declarada nesta
-- rodada — só o script que a produzirá quando executado de fato.
-- ================================================================
