/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5813 - Performance Test Plan: Collections Physical Increment 02F (MASTER_SET Scope & Completion)
Versão......: 2.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01 → -STAGING-REVISION-01)

CORREÇÕES v2.0 (STAGING-REVISION-01, auditoria fonte-a-fonte):
  item 11 (BLOCKER) — depois de inserir `perf_synth_variants` em
    `public.card_variant`, a query que monta `perf_set_variants`
    reconsultava `card_variant JOIN card WHERE card_set_id = ...`, que
    JÁ incluía as Variants recém-inseridas (mesma transação, mesmo
    card_set_id) — o `UNION ALL` seguinte com `perf_synth_variants`
    duplicava cada Variant sintética no pool, podendo violar a PK de
    `collection_master_set_scope`. Corrigido: a branch "real" agora
    exclui explicitamente (`NOT EXISTS`) qualquer id presente em
    `perf_synth_variants`. Adicionada assertion explícita logo após
    montar `perf_set_variants` — `count(*) = count(DISTINCT
    card_variant_id)` — que aborta o benchmark (`RAISE EXCEPTION`) se
    a sintese produzir qualquer duplicata.
  item 12 — `synth_buffer` deixou de ser uma constante fixa (400) e
    passou a ser calculado dinamicamente a partir de `real_pool_size`,
    visando um pool COMBINADO próximo do candidato a guard de
    `apply_master_set_scope_diff()` (`c_max_variant_ids = 10000`,
    Query 5079) — nunca mais extrapolando uma conclusão de guard a
    partir de um volume muito menor (~1k) sem nunca testar carga
    materialmente próxima de 10k. Os workloads C/D/E, que operam sobre
    o pool combinado inteiro, passam a testar esse volume diretamente.

Descrição...:
Plano de teste de performance pós-migration para o read-model novo
(collection_master_set_scope_positions, 5084), a evolução de
collection_completion_summary() (5083, ramo MASTER_SET) e as três RPCs
de escrita de Scope (5079-5082). NÃO EXECUTAR nesta rodada; requer que
5072-5084 estejam aplicadas. Mesma estrutura de 5807/5809/5811:
BEGIN...ROLLBACK, EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) capturado em
perf_results, GRANT em pg_temp ANTES da troca de role, medição real
como Owner A autenticado não-admin.

SÍNTESE CONTROLADA DE CATÁLOGO (mandato item 9/15 — "carga acima do
maior Card Set atual via fixture controlada quando necessário"). O
maior Card Set REAL do catálogo hoje pode não ter Card Variants
suficientes para testar "centenas de Variants" nem para exceder a si
mesmo. Este script resolve o Card Set de MAIOR pool real de Card
Variants (mesma escolha de praticidade de 5811, nunca requisito de
STANDARD_SET/MASTER_SET), grava o tamanho desse pool ANTES de
qualquer síntese (`catalog_max_pool_before_synth` — o "maior Card Set
atual" citado no mandato), e então ACRESCENTA um lote de Cards+Card
Variants sintéticas (INSERT direto, reaproveitando rarity_id/
category_id/variant_type_id REAIS do próprio Game — nunca fabricando
Game/Rarity/Category/Card Variant Type novos) ao MESMO Card Set, num
volume (`synth_buffer`, ver Passo 2) explicitamente documentado como
BUFFER OPERACIONAL DE BENCHMARK — não uma constante de domínio, não
canonizada como limite arquitetural (mesma disciplina do teto de
10.000 em `apply_master_set_scope_diff()`, Query 5079). O pool final
(`pool_size` = real + sintético) supera `catalog_max_pool_before_synth`
por construção, garantindo que o workload C/D/E abaixo testa carga
GENUINAMENTE acima do maior Card Set observado no catálogo hoje —
nunca limitado pela cobertura incompleta do catálogo atual. Nenhuma
Card/Card Variant sintética é referenciada por nenhuma leitura de
produção fora desta transação revertida — nomes/collector_numbers
prefixados `ZZSYNTH-`/`VAL-PERF-02F-SYNTH-`, resíduo verificado no
Passo 8.

Workloads (mandato item 15):
  A. Scope pequeno (20 Variants) — summary() isolado.
  B. Scope de "centenas" de Variants (~300, ou o máximo disponível se o
     pool combinado for menor) — summary() + positions(only_missing=
     false); Physical Cards concentradas (workload de duplicatas, ver
     F) e cobertura parcial (faltantes reais, ver I) construídas sobre
     esta mesma Collection.
  C. Scope = pool COMBINADO inteiro (real + sintético), deliberadamente
     ACIMA de catalog_max_pool_before_synth — summary() + positions
     (only_missing=false) sobre Collection 100% coberta (Physical Card
     para cada posição) — leitura isolada mais pesada de uma única
     Collection.
  D. replace_master_set_scope() com ALTA SOBREPOSIÇÃO (maioria KEEP,
     pequena fração ADD/REMOVE) — Collection dedicada, Scope inicial =
     90% do pool combinado; replace requisita 95% desse inicial (KEEP)
     + uma fatia do slice reservado (ADD), removendo o restante do
     inicial (REMOVE pequeno).
  E. replace_master_set_scope() com ALTA TROCA (maioria ADD/REMOVE,
     pequena fração KEEP) — mesma Collection-base de D (cópia
     independente), replace requisita só 10% do inicial (KEEP) + TODO
     o slice reservado (ADD grande), removendo os outros 90% do
     inicial (REMOVE grande).
  F. collection_completion_summary() com muitas duplicatas — Collection
     B, milhares de Physical Cards concentradas em poucas posições do
     Scope.
  G. Inventory do Owner com >= 20.000 Physical Cards no total (mesmo
     piso de volume já usado em 01B/2C/2E) — summary() sobre a
     Collection C medida com esse pano de fundo de Inventory grande.
  H. Múltiplas Collections do mesmo Card Set — summary() em sequência
     sobre A/B/C/D/E, prova de ausência de degradação por vizinhança
     catalogal (mesmo espírito do workload G de 5811).
  I. collection_master_set_scope_positions(..., only_missing=true)
     sobre a Collection B (tem faltantes reais por construção).
  J. Experiência de abertura de tela real — summary() + positions
     (only_missing=false) em sequência sobre a Collection C, mais
     combined_execution_time_ms (soma dos dois Execution Time, nunca
     medição própria de tempo de parede — mesmo padrão de 5811 item I).

Nenhum índice novo, cache ou materialized view é criado por este
script — só medição. Toda recomendação de teto operacional de payload
(guard de `apply_master_set_scope_diff()`, Query 5079) deve ser
formada a partir dos tempos REAIS medidos aqui (workloads C/D/E em
particular), nunca de suposição.

Ordem de execução (mesmo Passo -1..8 de 5807/5809/5811):
  Passo -1 (fora de transação) — baseline de resíduo.
  Passo 0  — BEGIN; pré-condições.
  Passo 1  — resolver contexto (Owner A, Inventory A, Card Set de maior
             pool real, catalog_max_pool_before_synth) em TEMP TABLEs.
  Passo 2  — sintetizar Cards+Card Variants extras no mesmo Card Set
             (synth_buffer), montar perf_set_variants (pool combinado).
  Passo 3  — sintetizar (role privilegiada): Storage Container, as 5
             Collections MASTER_SET (A-E, Scope inicial via INSERT
             direto em collection_master_set_scope), Physical Cards +
             Allocations de B/C/F/G.
  Passo 4  — TEMP TABLE perf_results + GRANT em TODAS as TEMP TABLEs
             necessárias, ANTES da troca de role.
  Passo 5  — set_config('role','authenticated', true) + jwt sub =
             owner_a; PRECOND-ADMIN.
  Passo 6  — workloads A-J medidos via EXPLAIN (ANALYZE, BUFFERS,
             FORMAT JSON).
  Passo 7  — SELECT * FROM perf_results (leitura final).
  Passo 8  — ROLLBACK.
  Passo 9  (fora de transação) — prova de zero resíduo.

Nenhuma alegação de performance deve ser feita antes da execução real.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo ANTES do setup
-- ================================================================
SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection WHERE name LIKE 'PERF-TEST-02F-%';

SELECT count(*) AS cards_sinteticas_antes
FROM public.card WHERE collector_number LIKE 'ZZSYNTH-%';

SELECT count(*) AS physical_card_count_antes
FROM public.physical_card
WHERE inventory_id IN (SELECT id FROM public.inventory);

-- ================================================================
-- PASSO 0 — BEGIN + pré-condições
-- ================================================================
BEGIN;

DO $$
DECLARE
    v_owner_count    INT;
    v_game_count     INT;
    v_language_count INT;
    v_best_set_count INT;
BEGIN
    SELECT count(DISTINCT i.owner_user_id) INTO v_owner_count
    FROM public.inventory i
    WHERE i.owner_user_id NOT IN (SELECT au.id FROM public.admin_user au);
    IF v_owner_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: >= 1 Owner NAO-ADMIN com Inventory necessário (encontrados: %)', v_owner_count;
    END IF;

    SELECT count(*) INTO v_game_count FROM public.game;
    IF v_game_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Game encontrado';
    END IF;

    SELECT count(*) INTO v_language_count FROM public.language;
    IF v_language_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Language encontrada';
    END IF;

    SELECT count(*) INTO v_best_set_count
    FROM (
        SELECT c.card_set_id
        FROM public.card c
        JOIN public.card_variant cv ON cv.card_id = c.id
        GROUP BY c.card_set_id
        HAVING count(DISTINCT cv.id) >= 10
    ) elegiveis;
    IF v_best_set_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Card Set com pool de >= 10 Card Variants encontrado (necessario como base de sintese)';
    END IF;

    SELECT count(*) INTO v_best_set_count
    FROM public.card_variant_type WHERE is_active = TRUE;
    IF v_best_set_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum card_variant_type ativo encontrado (necessario para sintetizar Card Variant)';
    END IF;
END $$;

-- ================================================================
-- PASSO 1 — resolver contexto em TEMP TABLEs
-- ================================================================
CREATE TEMP TABLE perf_ctx (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO perf_ctx (key, value)
SELECT 'owner_a', owner_user_id::text
FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
ORDER BY owner_user_id LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'inventory_a', id::text FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a');

INSERT INTO perf_ctx (key, value)
SELECT 'language_id', id::text FROM public.language LIMIT 1;

-- Card Set de MAIOR pool real de Card Variants — praticidade de
-- benchmark (mesma disciplina de 5811), nunca requisito de domínio.
INSERT INTO perf_ctx (key, value)
SELECT 'card_set_id', card_set_id::text
FROM (
    SELECT c.card_set_id, count(DISTINCT cv.id) AS pool_size
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    GROUP BY c.card_set_id
    ORDER BY pool_size DESC
    LIMIT 1
) best;

INSERT INTO perf_ctx (key, value)
SELECT 'game_id', ex.game_id::text
FROM public.card_set cs JOIN public.expansion ex ON ex.id = cs.expansion_id
WHERE cs.id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id');

-- "Maior Card Set atual" citado no mandato — o MAIOR pool real de
-- Card Variants de QUALQUER Card Set do catálogo, medido ANTES de
-- qualquer síntese desta rodada.
INSERT INTO perf_ctx (key, value)
SELECT 'catalog_max_pool_before_synth', max(pool_size)::text
FROM (
    SELECT c.card_set_id, count(DISTINCT cv.id) AS pool_size
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    GROUP BY c.card_set_id
) all_sets;

INSERT INTO perf_ctx (key, value)
SELECT 'real_pool_size', count(DISTINCT cv.id)::text
FROM public.card c JOIN public.card_variant cv ON cv.card_id = c.id
WHERE c.card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id');

INSERT INTO perf_ctx (key, value)
SELECT 'sample_rarity_id', rarity_id::text FROM public.card
WHERE card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id') LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'sample_category_id', category_id::text FROM public.card
WHERE card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id') LIMIT 1;

INSERT INTO perf_ctx (key, value)
SELECT 'max_collector_order', coalesce(max(collector_order), 0)::text FROM public.card
WHERE card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id');

INSERT INTO perf_ctx (key, value)
SELECT 'sample_variant_type_id', id::text FROM public.card_variant_type
WHERE game_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id') AND is_active = TRUE
LIMIT 1;

-- BUFFER OPERACIONAL DE BENCHMARK — ver descrição no cabeçalho. NÃO é
-- uma constante de domínio. Dimensionado dinamicamente (correção
-- STAGING-REVISION-01 item 12) para que o pool COMBINADO final fique
-- próximo do candidato a guard de apply_master_set_scope_diff()
-- (c_max_variant_ids = 10000, Query 5079) — nunca extrapolando uma
-- recomendação de guard a partir de um volume muito menor. Piso de
-- 400 preservado (garante síntese mínima mesmo se real_pool_size já
-- for grande, mantendo o pool acima de catalog_max_pool_before_synth
-- por construção, ver assertion pool_excede_maior_set_atual abaixo).
INSERT INTO perf_ctx (key, value)
SELECT 'synth_buffer', GREATEST(400, 10000 - (SELECT value::int FROM perf_ctx WHERE key = 'real_pool_size'))::text;

-- ================================================================
-- PASSO 2 — sintetizar Cards+Card Variants extras no mesmo Card Set
-- (INSERT direto, role privilegiada, reaproveitando rarity/category/
-- variant_type REAIS do próprio Game)
-- ================================================================
CREATE TEMP TABLE perf_synth_cards (id UUID);

WITH new_cards AS (
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name)
    SELECT
        (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'sample_rarity_id'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'sample_category_id'),
        'ZZSYNTH-' || gs.n,
        (SELECT value::int FROM perf_ctx WHERE key = 'max_collector_order') + gs.n,
        'VAL-PERF-02F-SYNTH-' || gs.n
    FROM generate_series(1, (SELECT value::int FROM perf_ctx WHERE key = 'synth_buffer')) AS gs(n)
    RETURNING id
)
INSERT INTO perf_synth_cards (id) SELECT id FROM new_cards;

CREATE TEMP TABLE perf_synth_variants (card_id UUID, variant_id UUID);

WITH new_variants AS (
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order)
    SELECT id, (SELECT value::uuid FROM perf_ctx WHERE key = 'sample_variant_type_id'), 1
    FROM perf_synth_cards
    RETURNING id, card_id
)
INSERT INTO perf_synth_variants (card_id, variant_id) SELECT card_id, id FROM new_variants;

-- Pool COMBINADO (real + sintético) do Card Set escolhido, numerado
-- deterministicamente (rn) para fatiar em slices por workload.
--
-- CORREÇÃO STAGING-REVISION-01 item 11 (BLOCKER): a branch "real"
-- abaixo reconsulta public.card_variant/public.card DEPOIS que as
-- Variants sintéticas já foram inseridas na mesma transação — sem o
-- filtro NOT EXISTS, ela reincluiria as próprias Variants sintéticas
-- (mesmo card_set_id), e o UNION ALL com perf_synth_variants
-- duplicaria cada uma delas no pool.
CREATE TEMP TABLE perf_set_variants (card_variant_id UUID, rn BIGINT);

INSERT INTO perf_set_variants (card_variant_id, rn)
SELECT card_variant_id, row_number() OVER (ORDER BY card_variant_id)
FROM (
    SELECT cv.id AS card_variant_id
    FROM public.card_variant cv
    JOIN public.card c ON c.id = cv.card_id
    WHERE c.card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id')
      AND NOT EXISTS (
          SELECT 1 FROM perf_synth_variants sv WHERE sv.variant_id = cv.id
      )
    UNION ALL
    SELECT variant_id FROM perf_synth_variants
) all_variants;

INSERT INTO perf_ctx (key, value) SELECT 'pool_size', count(*)::text FROM perf_set_variants;

-- Assertion explícita de zero-duplicatas (correção STAGING-REVISION-01
-- item 11) — se a síntese produzir qualquer card_variant_id repetido
-- no pool, o benchmark é abortado aqui, antes de qualquer INSERT em
-- collection_master_set_scope (que violaria a PK composta de 5072).
DO $$
DECLARE
    v_total    BIGINT;
    v_distinct BIGINT;
BEGIN
    SELECT count(*), count(DISTINCT card_variant_id) INTO v_total, v_distinct
    FROM perf_set_variants;

    IF v_total <> v_distinct THEN
        RAISE EXCEPTION 'perf_set_variants contains duplicate card_variant_id (total=%, distinct=%) — synthesis bug, benchmark aborted', v_total, v_distinct;
    END IF;
END $$;

-- Tamanhos de workload — clampeados ao pool combinado disponível
-- (LEAST), nunca hardcoded como requisito.
INSERT INTO perf_ctx (key, value)
SELECT 'wl_a_n', least(20, (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size'))::text;
INSERT INTO perf_ctx (key, value)
SELECT 'wl_b_n', least(300, (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size'))::text;
INSERT INTO perf_ctx (key, value)
SELECT 'wl_large_n', (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size')::text;

-- slice_cutoff: 90% do pool combinado — separa o "slice inicial" (D/E)
-- do "slice reservado" usado para ADD real nos replaces de D/E.
INSERT INTO perf_ctx (key, value)
SELECT 'slice_cutoff', floor((SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size') * 0.9)::text;

-- CONTEXTO DO BENCHMARK — exposto para leitura antes de qualquer plano
SELECT
    (SELECT value FROM perf_ctx WHERE key = 'card_set_id')                     AS card_set_id,
    (SELECT value FROM perf_ctx WHERE key = 'real_pool_size')                  AS real_pool_size,
    (SELECT value FROM perf_ctx WHERE key = 'synth_buffer')                    AS synth_buffer,
    (SELECT value FROM perf_ctx WHERE key = 'pool_size')                       AS pool_size_combinado,
    (SELECT value FROM perf_ctx WHERE key = 'catalog_max_pool_before_synth')   AS catalog_max_pool_before_synth,
    ((SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size')
        > (SELECT value::bigint FROM perf_ctx WHERE key = 'catalog_max_pool_before_synth')) AS pool_excede_maior_set_atual;
-- Esperado: pool_excede_maior_set_atual = true (prova de que o
-- workload C/D/E abaixo testa carga acima do maior Card Set observado
-- no catálogo ANTES desta síntese).

-- ================================================================
-- PASSO 3 — Collections de teste + Physical Cards/Allocations
-- (role privilegiada, INSERT direto — Scope inicial gravado
-- diretamente em collection_master_set_scope, não via RPC, para não
-- medir a RPC de escrita durante o SETUP)
-- ================================================================
WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a'), 'PERF-TEST-02F-STORAGE')
    RETURNING id
)
INSERT INTO perf_ctx (key, value) SELECT 'storage_a', id::text FROM ins;

CREATE TEMP TABLE perf_collections (kind TEXT, id UUID);

DO $$
DECLARE
    v_kind   TEXT;
    v_col_id UUID;
    v_ref_id UUID;
BEGIN
    FOREACH v_kind IN ARRAY ARRAY['wl_a','wl_b','wl_c','wl_d','wl_e'] LOOP
        INSERT INTO public.collection (
            owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
        )
        VALUES (
            (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
            (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
            (SELECT value::uuid FROM perf_ctx WHERE key = 'storage_a'),
            'PERF-TEST-02F-' || upper(v_kind),
            'REFERENCE_BASED',
            'MASTER_SET'
        )
        RETURNING id INTO v_col_id;

        INSERT INTO public.collection_reference (collection_id, reference_kind)
        VALUES (v_col_id, 'CARD_SET')
        RETURNING id INTO v_ref_id;

        INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
        VALUES (v_ref_id, (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id'));

        INSERT INTO perf_collections (kind, id) VALUES (v_kind, v_col_id);
    END LOOP;
END $$;

-- Scope inicial de A (20), B (~300), C (pool inteiro) — INSERT direto
INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
SELECT (SELECT id FROM perf_collections WHERE kind = 'wl_a'), psv.card_variant_id,
       (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a')
FROM perf_set_variants psv
WHERE psv.rn <= (SELECT value::bigint FROM perf_ctx WHERE key = 'wl_a_n');

INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
SELECT (SELECT id FROM perf_collections WHERE kind = 'wl_b'), psv.card_variant_id,
       (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a')
FROM perf_set_variants psv
WHERE psv.rn <= (SELECT value::bigint FROM perf_ctx WHERE key = 'wl_b_n');

INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
SELECT (SELECT id FROM perf_collections WHERE kind = 'wl_c'), psv.card_variant_id,
       (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a')
FROM perf_set_variants psv;

-- Scope inicial de D e E — "slice inicial" (90% do pool combinado,
-- rn <= slice_cutoff); o "slice reservado" (rn > slice_cutoff) fica de
-- fora do Scope inicial, disponível como fonte real de ADD nos
-- replaces medidos no Passo 6.
INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
SELECT (SELECT id FROM perf_collections WHERE kind = 'wl_d'), psv.card_variant_id,
       (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a')
FROM perf_set_variants psv
WHERE psv.rn <= (SELECT value::bigint FROM perf_ctx WHERE key = 'slice_cutoff');

INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
SELECT (SELECT id FROM perf_collections WHERE kind = 'wl_e'), psv.card_variant_id,
       (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a')
FROM perf_set_variants psv
WHERE psv.rn <= (SELECT value::bigint FROM perf_ctx WHERE key = 'slice_cutoff');

-- Physical Cards + Allocations de B: cobertura PARCIAL (só 70% das
-- posições do Scope de B) + concentração de duplicatas nas 10
-- primeiras posições (workload F/DUPLICATES) — 2.000 Physical Cards
-- cicladas nessas 10 posições.
WITH new_pc AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM perf_set_variants psv
    WHERE psv.rn <= floor((SELECT value::bigint FROM perf_ctx WHERE key = 'wl_b_n') * 0.7)
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_b') FROM new_pc;

WITH new_pc_dup AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM generate_series(1, 2000) AS gs(n)
    JOIN perf_set_variants psv ON psv.rn = ((gs.n - 1) % 10) + 1
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_b') FROM new_pc_dup;

-- Physical Cards + Allocations de C: cobertura 100% (1 Physical Card
-- por posição do pool inteiro) — Collection COMPLETA, leitura mais
-- pesada isolada (workload C/J).
WITH new_pc AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM perf_set_variants psv
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_c') FROM new_pc;

-- Inventory do Owner A com >= 20.000 Physical Cards no total (workload
-- G) — Collection "junco" OPEN_CURATION, fora do Card Set de teste,
-- só para inflar o volume real do Inventory sem interferir no Scope/
-- Completion medidos acima.
DO $$
DECLARE
    v_junk_col_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
        (SELECT value::uuid FROM perf_ctx WHERE key = 'storage_a'),
        'PERF-TEST-02F-WL-G-JUNK', 'OPEN_CURATION', 'NONE'
    )
    RETURNING id INTO v_junk_col_id;

    WITH new_pc AS (
        INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
        SELECT psv.card_variant_id,
               (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
               (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
        FROM generate_series(1, 20000) AS gs(n)
        JOIN perf_set_variants psv
            ON psv.rn = ((gs.n - 1) % (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size')) + 1
        RETURNING id
    )
    INSERT INTO public.collection_allocation (physical_card_id, collection_id)
    SELECT id, v_junk_col_id FROM new_pc;
END $$;

-- ================================================================
-- PASSO 4 — TEMP TABLE de resultados + GRANT ANTES da troca de role
-- ================================================================
CREATE TEMP TABLE perf_results (case_label TEXT, plan_json JSON);

GRANT SELECT ON perf_ctx TO authenticated;
GRANT SELECT ON perf_collections TO authenticated;
GRANT SELECT ON perf_set_variants TO authenticated;
GRANT SELECT ON perf_synth_variants TO authenticated;
GRANT INSERT, SELECT ON perf_results TO authenticated;

SELECT
    'perf_ctx' AS temp_table, has_table_privilege('authenticated', 'pg_temp.perf_ctx', 'SELECT') AS authenticated_pode_ler
UNION ALL SELECT 'perf_collections', has_table_privilege('authenticated', 'pg_temp.perf_collections', 'SELECT')
UNION ALL SELECT 'perf_set_variants', has_table_privilege('authenticated', 'pg_temp.perf_set_variants', 'SELECT')
UNION ALL SELECT 'perf_results', has_table_privilege('authenticated', 'pg_temp.perf_results', 'SELECT');
-- Esperado: true nas 4 linhas.

-- ================================================================
-- PASSO 5 — trocar para o contexto do Owner A autenticado
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM perf_ctx WHERE key = 'owner_a'), true);

DO $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT public.is_admin() INTO v_is_admin;
    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION 'fixture invalido: Owner A resolvido em perf_ctx e ADMIN (is_admin()=%)', v_is_admin;
    END IF;
END $$;

-- ================================================================
-- PASSO 6 — workloads A-J medidos
-- ================================================================

-- Workload A — Scope pequeno (20)
DO $$
DECLARE v_id UUID; v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_a';
    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('A - summary Scope pequeno (20 Variants)', v_json);
END $$;

-- Workload B — Scope "centenas" (~300): summary + positions completo
DO $$
DECLARE v_id UUID; v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_b';
    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('B - summary Scope centenas (~300 Variants, cobertura parcial + duplicatas)', v_json);

    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_master_set_scope_positions(%L::uuid, FALSE)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('B - positions only_missing=false', v_json);
END $$;

-- Workload C — Scope = pool combinado inteiro, acima do maior Card Set
-- observado antes da sintese, 100% coberto
DO $$
DECLARE v_id UUID; v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_c';
    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('C - summary Scope = pool combinado inteiro (acima do maior Card Set atual), 100% coberto', v_json);

    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_master_set_scope_positions(%L::uuid, FALSE)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('C - positions only_missing=false (pool combinado inteiro)', v_json);
END $$;

-- Workload D — replace_master_set_scope() com ALTA SOBREPOSIÇÃO
DO $$
DECLARE
    v_id UUID;
    v_slice_cutoff BIGINT := (SELECT value::bigint FROM perf_ctx WHERE key = 'slice_cutoff');
    v_pool_size    BIGINT := (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size');
    v_payload JSONB;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_d';

    -- 95% do slice inicial (KEEP) + uma fatia do slice reservado (ADD)
    SELECT jsonb_agg(card_variant_id) INTO v_payload
    FROM (
        SELECT card_variant_id FROM perf_set_variants
        WHERE rn <= floor(v_slice_cutoff * 0.95)
        UNION ALL
        SELECT card_variant_id FROM perf_set_variants
        WHERE rn > v_slice_cutoff AND rn <= v_slice_cutoff + floor((v_pool_size - v_slice_cutoff) * 0.5)
    ) payload;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.replace_master_set_scope(%L::uuid, %L::jsonb)',
        v_id, v_payload
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('D - replace_master_set_scope alta sobreposicao (maioria KEEP)', v_json);
END $$;

-- Workload E — replace_master_set_scope() com ALTA TROCA
DO $$
DECLARE
    v_id UUID;
    v_slice_cutoff BIGINT := (SELECT value::bigint FROM perf_ctx WHERE key = 'slice_cutoff');
    v_payload JSONB;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_e';

    -- 10% do slice inicial (KEEP) + TODO o slice reservado (ADD)
    SELECT jsonb_agg(card_variant_id) INTO v_payload
    FROM (
        SELECT card_variant_id FROM perf_set_variants
        WHERE rn <= floor(v_slice_cutoff * 0.10)
        UNION ALL
        SELECT card_variant_id FROM perf_set_variants
        WHERE rn > v_slice_cutoff
    ) payload;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.replace_master_set_scope(%L::uuid, %L::jsonb)',
        v_id, v_payload
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('E - replace_master_set_scope alta troca (maioria ADD/REMOVE)', v_json);
END $$;

-- Workload F — summary com muitas duplicatas (mesma Collection B, já
-- construída com 2000 Physical Cards concentradas em 10 posições)
DO $$
DECLARE v_id UUID; v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_b';
    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('F - summary com muitas duplicatas (2000 PC / 10 posicoes concentradas)', v_json);
END $$;

-- Workload G — summary sobre C com Inventory do Owner >= 20.000
-- Physical Cards no total (fundo de volume já construído no Passo 3)
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
    v_inv_total BIGINT;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_c';
    SELECT count(*) INTO v_inv_total FROM public.physical_card
    WHERE inventory_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a');

    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES (
        format('G - summary sobre Collection C com Inventory do Owner em %s Physical Cards (>= 20000)', v_inv_total), v_json);
END $$;

-- Workload H — summary em sequência sobre A-E (mesmo Card Set)
DO $$
DECLARE
    v_kind TEXT; v_id UUID; v_json JSON;
BEGIN
    FOR v_kind, v_id IN SELECT kind, id FROM perf_collections ORDER BY kind LOOP
        EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json;
        INSERT INTO perf_results (case_label, plan_json) VALUES ('H - summary em sequencia (' || v_kind || ')', v_json);
    END LOOP;
END $$;

-- Workload I — positions only_missing=true sobre B (faltantes reais)
DO $$
DECLARE v_id UUID; v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_b';
    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_master_set_scope_positions(%L::uuid, TRUE)', v_id) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('I - positions only_missing=true (Scope B, faltantes reais)', v_json);
END $$;

-- Workload J — abertura de tela real sobre C: summary + positions,
-- combined_execution_time_ms = soma dos dois Execution Time
DO $$
DECLARE
    v_id UUID;
    v_json_summary   JSON;
    v_json_positions JSON;
    v_exec_summary_ms   NUMERIC;
    v_exec_positions_ms NUMERIC;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_c';

    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)', v_id) INTO v_json_summary;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('J - summary (parte 1 da tela, Scope combinado inteiro)', v_json_summary);

    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_master_set_scope_positions(%L::uuid, FALSE)', v_id) INTO v_json_positions;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('J - positions (parte 2 da tela, Scope combinado inteiro)', v_json_positions);

    v_exec_summary_ms   := (v_json_summary->0->>'Execution Time')::numeric;
    v_exec_positions_ms := (v_json_positions->0->>'Execution Time')::numeric;

    INSERT INTO perf_results (case_label, plan_json) VALUES (
        'J - combined execution time (summary + positions)',
        json_build_object(
            'execution_time_summary_ms', v_exec_summary_ms,
            'execution_time_positions_ms', v_exec_positions_ms,
            'combined_execution_time_ms', v_exec_summary_ms + v_exec_positions_ms,
            'nota', 'combined = soma dos Execution Time dos dois planos acima, nao uma medicao de tempo de parede separada'
        )
    );
END $$;

-- ================================================================
-- PASSO 7 — leitura final dos planos capturados
-- ================================================================
SELECT case_label, plan_json FROM perf_results ORDER BY case_label;

-- ================================================================
-- PASSO 8 — desfazer tudo
-- ================================================================
ROLLBACK;

-- ================================================================
-- PASSO 9 (fora de transação) — prova de zero resíduo
-- ================================================================
SELECT count(*) AS collections_residuais FROM public.collection WHERE name LIKE 'PERF-TEST-02F-%';
-- Esperado: 0

SELECT count(*) AS cards_sinteticas_residuais FROM public.card WHERE collector_number LIKE 'ZZSYNTH-%';
-- Esperado: 0

SELECT count(*) AS storage_containers_residuais FROM public.storage_container WHERE name = 'PERF-TEST-02F-STORAGE';
-- Esperado: 0

SELECT count(*) AS physical_card_count_depois
FROM public.physical_card
WHERE inventory_id IN (SELECT id FROM public.inventory);
-- Esperado: igual ao Passo -1

-- ================================================================
-- Nota de interpretação dos planos (mesmo espírito de 5807/5809/5811 —
-- não tratar Seq Scan automaticamente como falha). Registrar, para
-- cada workload: tipo de nó do planner, tempo total de execução,
-- buffers (shared hit/read), e se os caminhos de acesso esperados
-- foram usados — collection_master_set_scope PK (collection_id,
-- card_variant_id) já cobre "todo o Scope desta Collection" sem
-- índice secundário (ver 5072); collection_allocation.collection_id
-- (índice dedicado) + physical_card_id (UNIQUE); physical_card.id
-- (PK); card_variant.id (PK); card.id (PK) + card_set_id. Nenhum
-- índice novo foi criado para este benchmark. A recomendação final de
-- teto operacional de payload para apply_master_set_scope_diff()
-- (hoje c_max_variant_ids=10000, Query 5079, marcado como PROVISÓRIO)
-- deve ser formada a partir dos tempos REAIS dos workloads C/D/E
-- acima quando executados de fato — nenhuma conclusão de performance é
-- declarada nesta rodada, só o script que a produzirá.
--
-- CORREÇÃO STAGING-REVISION-01 item 12: synth_buffer (Passo 1) agora é
-- dimensionado dinamicamente para que pool_size combinado fique
-- próximo de 10000 (o candidato a guard hoje em 5079), então os
-- workloads C/D/E acima já testam carga materialmente próxima do teto
-- — não mais um volume de ~1k extrapolado para 10k. Se, quando
-- executado de fato, o tempo medido nesses workloads for aceitável, o
-- valor 10000 pode ser confirmado; se não for, o guard deve ser
-- revisado para o maior volume que se mostrar aceitável nos tempos
-- REAIS — nunca mantido por suposição.
-- ================================================================
