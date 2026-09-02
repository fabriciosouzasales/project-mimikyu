/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5811 - Performance Test Plan: Collections Physical Increment 02E (PROPOSTA)
Versão......: 1.5 (comentário residual do workload C corrigido —
               sem mudança de lógica)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-01;
               revisada em COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-
               REVISION-01, -REVISION-02, -FINAL-AUDIT-01, -FINAL-FIX-01
               e -EXECUTION-SAFETY-FIX-01)

NOTA v1.5 (STAGING-EXECUTION-SAFETY-FIX-01, item 4). O bloco de
sintetização do workload C (Passo 2c) já alocava, desde a v1.1, 1
Physical Card por linha de perf_set_variants (pool_size posições),
nunca por total_positions — mas o comentário daquele bloco ainda dizia
"workload C: 100% do total_positions", divergindo do próprio código e
do rótulo dinâmico já calculado no Passo 5 (v1.4). Corrigido apenas o
comentário, sem nenhuma mudança de lógica: workload C = máxima
cobertura disponível no pool atual, 1 Physical Card por posição
disponível, só equivale a 100% quando pool_size = total_positions.

NOTA v1.4 (STAGING-FINAL-FIX-01, itens 5/6/7). (5) Workload C não
afirma mais "100%" incondicionalmente — o rótulo agora é calculado em
runtime comparando pool_size a total_positions, só usando "100%"
quando são iguais; caso contrário, rotula como "máxima cobertura
disponível no fixture atual" e registra uma linha extra de contexto
(expected_satisfied = pool_size, expected_percentage = round(pool_size
/ total_positions * 100, 2), is_100_percent). (6) Uma SELECT de
contexto (card_set_id/total_positions/pool_size/wl_b_target) agora é
emitida ANTES de qualquer plano do Passo 5, para que a interpretação
dos workloads B/C não dependa de reler comentário. (7) Workload I
passa a extrair execution_time_summary_ms/execution_time_positions_ms
de cada JSON e grava uma linha extra com combined_execution_time_ms
explicitamente documentado como a soma dos dois — nunca uma medição
de tempo de parede separada.

NOTA v1.3 (STAGING-FINAL-AUDIT-01, item 13). owner_a (Passo 1) agora é
resolvido explicitamente excluindo public.admin_user — o mandato exige
que o benchmark que mede 5070/5071 rode no contexto de um usuário
comum, nunca de um admin (que, via catalog_admin_select, teria um
caminho de leitura adicional sobre card/card_variant, mascarando uma
eventual regressão de RLS). Precondição fail-loud atualizada para
exigir >= 1 Owner NÃO-ADMIN com Inventory; prova real de
is_admin() = false adicionada logo após a troca de role no Passo 4,
antes de qualquer workload.

NOTA v1.2 (REVISION-02, item 11). A conversão de 5070/5071 de
SECURITY INVOKER para SECURITY DEFINER (ver 5070 v2.0) não altera a
semântica destes workloads: o Passo 4 já trocava para
role=authenticated + jwt.claim.sub=owner_a ANTES de qualquer chamada
às funções (Passo 5, workloads A-I) — nenhum workload deste arquivo
jamais mediu como role privilegiada/admin. As 6 Collections de
fixture (Passo 2b) já são criadas com owner_user_id = owner_a,
compatível com a nova fronteira de ownership manual dentro das
funções. Nenhuma linha alterada no Passo 5 — confirmado por auditoria
desta revisão, não por suposição.

CORREÇÃO (v1.1). A v1.0 exigia Card Set com cobertura de Card Variant
100% como PRÉ-CONDIÇÃO do benchmark — tratamento incorreto: STANDARD_
SET denomina por Card, nunca por Card Variant (item 3 desta rodada), e
cobertura de catálogo nunca pode condicionar arquitetura ou o desenho
do benchmark. Corrigido: seleção agora usa o Card Set com maior POOL
de Cards com >= 1 Variant (praticidade de fixture, registrada como
tal), total_positions é sempre a contagem REAL de Cards do Set
(idêntica ao denominador de produção), e pool_size é uma chave
separada. Corrigido também um bug real introduzido pela suposição
anterior: os workloads E/F ciclavam physical cards via
`rn = (n % total_positions) + 1` contra perf_set_variants, que só tem
linhas até pool_size — quando pool_size < total_positions o JOIN
descartava silenciosamente linhas sem gerar erro, produzindo menos
Physical Cards que o volume pretendido. Corrigido para ciclar por
pool_size.

Descrição...:
Plano de teste de performance pós-migration para
collection_completion_summary()/collection_completion_positions()
(Queries 5070/5071). NÃO EXECUTAR nesta rodada; requer que as Queries
5067-5071 estejam aplicadas.

Primeiro rascunho estruturado (mesmo aviso já registrado em 5810) —
scripts de performance deste projeto historicamente levaram 1-2
rodadas de correção real antes de ficarem executáveis sem ajuste (ver
histórico de 5807/5809). Este arquivo já é SQL real (não roteiro
comentado), pensado para colar em UMA chamada, mas pode exigir uma
rodada -STAGING-REVISION-01 antes da execução real, exatamente como
os precedentes.

Diferença estrutural relevante frente a 5807/5809: aqueles incrementos
sintetizavam catálogo mínimo (Card/Card Variant) porque a query media
só volume de Allocation. Aqui a query shape tem DUAS metades
independentes (COLLECTIONS-PHYSICAL-INCREMENT-02E-MODELING-REVISION-01,
item 21) — DENOMINADOR (public.card por card_set_id, independe de
Allocation) e NUMERADOR (collection_allocation -> physical_card ->
card_variant -> card). Sintetizar um Card Set catalógico inteiro do
zero (Game/Expansion/Card Set/Rarity/Category/Card/Card Variant) para
o benchmark seria desproporcional e divergiria do catálogo real que a
feature efetivamente vai consultar em produção — este script REUTILIZA
um Card Set já existente e real do catálogo (resolvido dinamicamente,
sem hardcode de UUID), sintetizando apenas a camada física de
Collections/Physical Cards/Allocations sobre ele, dentro de uma
transação revertida.

Seleção do Card Set de referência (Passo 1) — CORRIGIDA em
COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-REVISION-01, item 7. O
denominador de STANDARD_SET depende de Card, não de Card Variant
(item 3 do relatório de modelagem) — "cobertura de Card Variant 100%"
NUNCA é requisito conceitual de Completion, só uma conveniência
opcional de fixture para tornar o benchmark mais legível. Por isso: o
Card Set escolhido é o de MAIOR POOL de Cards com >= 1 Card Variant
(sem exigir que 100% das Cards do Set tenham Variant) — escolha
registrada explicitamente aqui como PRATICIDADE DE BENCHMARK, nunca
como requisito de STANDARD_SET. `total_positions` usado nas medições
é sempre a contagem REAL e completa de public.card por card_set_id
(exatamente o mesmo denominador que collection_completion_summary()
calcula em produção) — inclusive quando esse total for maior que o
pool de Cards com Variant disponível para fixture; nesse caso o
workload C (abaixo) atinge a MAIOR cobertura possível com os dados
atuais, não necessariamente 100% — e isso é o comportamento correto e
esperado, coerente com a premissa de catálogo comercial completo
(a lacuna é transitória de desenvolvimento, não da arquitetura).

Workloads (COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-01, seção 14 e
-STAGING-REVISION-01, item 8):
  A. Collection vazia (STANDARD_SET, 0 Allocations) — summary isolado
  B. ~75% do total_positions do Card Set escolhido (proxy de "90/120")
     — summary isolado + positions completo (only_missing=false)
  C. máxima cobertura disponível no pool de Variants do fixture atual
     (rótulo e expected_satisfied/expected_percentage calculados em
     runtime — "100%" só quando pool_size = total_positions; senão,
     cobertura parcial real, nunca alegada como completa — ver NOTA
     v1.4) — summary isolado + linha de contexto
  D. muitas duplicatas (2.000 Physical Cards concentradas em só 5
     posições distintas -> satisfied_positions = 5) — summary isolado
  E. 500 Allocations — summary isolado
  F. 5.000 Allocations (maior workload), cicladas pelo pool de
     posições disponíveis -> várias dezenas/centenas de duplicatas por
     posição quando o pool é menor que 5.000, prova de que
     COUNT(DISTINCT) permanece eficiente sob duplicação pesada —
     summary isolado
  G. várias Collections do mesmo Card Set — já satisfeito
     estruturalmente por A-F compartilharem o mesmo card_set_id;
     medido explicitamente chamando summary() em sequência sobre as 6
     Collections de teste, provando ausência de degradação por
     "vizinhança" de outras Collections do mesmo catálogo
  H. only_missing = true sobre a Collection do workload B (a mais
     representativa — tem faltantes reais)
  I. experiência de abertura de tela real — summary() + primeira
     leitura de positions() (only_missing = false) sobre a Collection
     do workload B, capturados em sequência, mais uma linha de
     combined_execution_time_ms extraída dos dois JSONs (NOTA v1.4)

Ordem de execução (mesmo Passo -1..8 de 5807/5809):
  Passo -1 (fora de transação) — baseline de resíduo.
  Passo 0  — BEGIN; pré-condições (>= 1 Owner com Inventory; >= 1 Game;
             >= 1 Language; >= 1 Card Set com pool de >= 50 Cards
             tendo >= 1 Card Variant — SEM exigir cobertura 100%).
  Passo 1  — resolver contexto (Owner A, Inventory A, Card Set
             escolhido, Game desse Card Set, total_positions REAL
             — todas as Cards do Set —, pool de 1 Card Variant por
             Card com Variant disponível) em TEMP TABLEs.
  Passo 2  — sintetizar (role privilegiada, INSERT direto): Storage
             Container, Physical Cards dos 5 workloads com volume
             (B/C/D/E/F), as 6 Collections REFERENCE_BASED/
             STANDARD_SET apontando para o mesmo Card Set, e as
             Collection Allocations de B/C/D/E/F (workload A fica
             deliberadamente vazia).
  Passo 3  — TEMP TABLE perf_results + GRANT em TODAS as TEMP TABLEs
             que os blocos pós-troca-de-role vão precisar ler (mesma
             correção já aplicada em 5807 -STAGING-FINAL-FIX-01 desde
             o primeiro rascunho, não como correção posterior).
  Passo 4  — set_config('role','authenticated', true) +
             set_config('request.jwt.claim.sub', <owner_a>, true).
  Passo 5  — workloads A-I medidos via EXPLAIN (ANALYZE, BUFFERS,
             FORMAT JSON), cada um capturado em perf_results.
  Passo 6  — SELECT * FROM perf_results (leitura final, dentro da
             transação).
  Passo 7  — ROLLBACK.
  Passo 8  (fora de transação) — prova de zero resíduo.

Nenhuma alegação de performance deve ser feita antes da execução real.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo ANTES do setup
-- ================================================================
SELECT count(*) AS physical_card_count_antes
FROM public.physical_card
WHERE inventory_id = (
    SELECT id FROM public.inventory ORDER BY owner_user_id LIMIT 1
);
-- Registrar o valor retornado (N0) — comparado no Passo 8.

SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection
WHERE name LIKE 'PERF-TEST-02E-%';
-- Esperado: 0 (nenhuma execução anterior deixou resíduo)

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

    -- Pool = Cards com >= 1 Card Variant (fixture de Physical Card).
    -- SEM exigir cobertura 100% do Card Set — cobertura de catálogo
    -- não é requisito de STANDARD_SET (COLLECTIONS-PHYSICAL-INCREMENT-
    -- 02E-STAGING-REVISION-01, item 7), só escolhe-se o Set com maior
    -- pool disponível, por praticidade de benchmark.
    SELECT count(*) INTO v_best_set_count
    FROM (
        SELECT c.card_set_id, count(DISTINCT c.id) AS pool_size
        FROM public.card c
        JOIN public.card_variant cv ON cv.card_id = c.id
        GROUP BY c.card_set_id
        HAVING count(DISTINCT c.id) >= 50
    ) elegiveis;

    IF v_best_set_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Card Set com pool de >= 50 Cards possuindo Card Variant encontrado';
    END IF;
END $$;

-- ================================================================
-- PASSO 1 — resolver contexto em TEMP TABLEs
-- ================================================================
CREATE TEMP TABLE perf_ctx (key TEXT PRIMARY KEY, value TEXT);

-- owner_a: explicitamente NÃO-ADMIN (mandato STAGING-FINAL-AUDIT-01,
-- item 13 — o benchmark que mede 5070/5071 deve rodar no contexto de
-- um usuário comum, mesma disciplina já aplicada em 5810). Excluído
-- via public.admin_user, nunca via is_admin() (sem parâmetro, por
-- design do ADR-021).
INSERT INTO perf_ctx (key, value)
SELECT 'owner_a', owner_user_id::text
FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
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

-- Card Set com maior POOL de Cards possuindo >= 1 Card Variant —
-- escolha de praticidade de benchmark (item 7 desta rodada), nunca
-- requisito de cobertura 100%. O Set pode legitimamente ter Cards sem
-- nenhuma Variant hoje; elas continuam entrando no denominador real
-- (total_positions, abaixo) e aparecerão como faltantes por ausência
-- de Physical Card possível no fixture atual — coerente com o produto
-- final (premissa de catálogo comercial completo no lançamento).
INSERT INTO perf_ctx (key, value)
SELECT 'card_set_id', card_set_id::text
FROM (
    SELECT c.card_set_id, count(DISTINCT c.id) AS pool_size
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    GROUP BY c.card_set_id
    HAVING count(DISTINCT c.id) >= 50
    ORDER BY pool_size DESC
    LIMIT 1
) best;

INSERT INTO perf_ctx (key, value)
SELECT 'game_id', ex.game_id::text
FROM public.card_set cs
JOIN public.expansion ex ON ex.id = cs.expansion_id
WHERE cs.id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id');

-- 1 Card Variant por Card COM Variant disponível (pool de fixture) —
-- pode ser um subconjunto de total_positions, nunca o próprio
-- denominador
CREATE TEMP TABLE perf_set_variants (card_id UUID, card_variant_id UUID, rn BIGINT);

INSERT INTO perf_set_variants (card_id, card_variant_id, rn)
SELECT card_id, card_variant_id, row_number() OVER (ORDER BY collector_order)
FROM (
    SELECT DISTINCT ON (c.id) c.id AS card_id, cv.id AS card_variant_id, c.collector_order
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    WHERE c.card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id')
    ORDER BY c.id, cv.variant_order
) sub;

-- total_positions REAL — TODAS as Cards do Card Set, exatamente o
-- mesmo denominador que collection_completion_summary() calcula em
-- produção (público.card por card_set_id, independente de Variant)
INSERT INTO perf_ctx (key, value)
SELECT 'total_positions', count(*)::text
FROM public.card
WHERE card_set_id = (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id');

INSERT INTO perf_ctx (key, value)
SELECT 'pool_size', count(*)::text FROM perf_set_variants;

-- alvo do workload B: 75% do total_positions REAL, mas nunca acima do
-- pool de fixture disponível (LEAST) — se o pool for menor que 75% do
-- total, o benchmark usa o máximo que o fixture atual permite,
-- registrado como tal, não forjado
INSERT INTO perf_ctx (key, value)
SELECT 'wl_b_target', greatest(1, least(
    (SELECT count(*) FROM perf_set_variants),
    round((SELECT value::bigint FROM perf_ctx WHERE key = 'total_positions') * 0.75)
))::text;

-- ================================================================
-- PASSO 2a — Storage Container
-- ================================================================
CREATE TEMP TABLE perf_storage (id UUID);

WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    SELECT (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a'),
           'PERF-TEST-02E-STORAGE'
    RETURNING id
)
INSERT INTO perf_storage (id) SELECT id FROM ins;

-- ================================================================
-- PASSO 2b — Collections de teste (6: A, B, C, D, E, F), todas
-- REFERENCE_BASED/STANDARD_SET apontando para o mesmo Card Set
-- ================================================================
CREATE TEMP TABLE perf_collections (kind TEXT, id UUID, reference_id UUID);

DO $$
DECLARE
    v_kind    TEXT;
    v_col_id  UUID;
    v_ref_id  UUID;
BEGIN
    FOREACH v_kind IN ARRAY ARRAY['wl_a','wl_b','wl_c','wl_d','wl_e','wl_f'] LOOP
        INSERT INTO public.collection (
            owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
        )
        VALUES (
            (SELECT value::uuid FROM perf_ctx WHERE key = 'owner_a'),
            (SELECT value::uuid FROM perf_ctx WHERE key = 'game_id'),
            (SELECT id FROM perf_storage),
            'PERF-TEST-02E-' || upper(v_kind),
            'REFERENCE_BASED',
            'STANDARD_SET'
        )
        RETURNING id INTO v_col_id;

        INSERT INTO public.collection_reference (collection_id, reference_kind)
        VALUES (v_col_id, 'CARD_SET')
        RETURNING id INTO v_ref_id;

        INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
        VALUES (v_ref_id, (SELECT value::uuid FROM perf_ctx WHERE key = 'card_set_id'));

        INSERT INTO perf_collections (kind, id, reference_id) VALUES (v_kind, v_col_id, v_ref_id);
    END LOOP;
END $$;

-- ================================================================
-- PASSO 2c — Physical Cards + Allocations dos workloads B/C/D/E/F
-- (workload A fica vazia de propósito). INSERT direto, set-based,
-- triggers ativos (5042/estrutural).
-- ================================================================

-- workload B: ~75% do total_positions, 1 Physical Card por posição
WITH new_pc AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM perf_set_variants psv
    WHERE psv.rn <= (SELECT value::bigint FROM perf_ctx WHERE key = 'wl_b_target')
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_b') FROM new_pc;

-- workload C: maxima cobertura disponivel no pool atual — 1 Physical
-- Card por posicao do pool de fixture (perf_set_variants); so equivale
-- a 100% do total_positions quando pool_size = total_positions (ver
-- bloco de medicao do workload C no Passo 5, que calcula o rotulo e o
-- expected_percentage em runtime — mandato STAGING-FINAL-FIX-01, item
-- 5, e comentario corrigido em STAGING-EXECUTION-SAFETY-FIX-01, item 4)
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

-- workload D: 2.000 Physical Cards concentradas em só 5 posições
-- distintas (rn 1-5) -> satisfied_positions esperado = 5
WITH new_pc AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM generate_series(1, 2000) AS gs(n)
    JOIN perf_set_variants psv ON psv.rn = ((gs.n - 1) % 5) + 1
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_d') FROM new_pc;

-- workload E: 500 Allocations, ciclando pelo POOL de fixture (pool_size
-- — nunca total_positions, que pode exceder o pool quando o Card Set
-- tem Cards sem Variant; ciclar por total_positions faria o modulo
-- apontar para rn inexistente em perf_set_variants e o JOIN
-- silenciosamente descartar linhas, gerando menos de 500 Physical
-- Cards — bug corrigido em -STAGING-REVISION-01)
WITH new_pc AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM generate_series(1, 500) AS gs(n)
    JOIN perf_set_variants psv
        ON psv.rn = ((gs.n - 1) % (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size')) + 1
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_e') FROM new_pc;

-- workload F: 5.000 Allocations (maior volume), ciclando pelo POOL de
-- fixture (pool_size, mesma correção do workload E acima) — se
-- pool_size < 5.000, gera dezenas/centenas de duplicatas por posição
-- por construção, prova real de COUNT(DISTINCT) sob duplicação pesada
WITH new_pc AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT psv.card_variant_id,
           (SELECT value::uuid FROM perf_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM perf_ctx WHERE key = 'inventory_a')
    FROM generate_series(1, 5000) AS gs(n)
    JOIN perf_set_variants psv
        ON psv.rn = ((gs.n - 1) % (SELECT value::bigint FROM perf_ctx WHERE key = 'pool_size')) + 1
    RETURNING id
)
INSERT INTO public.collection_allocation (physical_card_id, collection_id)
SELECT id, (SELECT id FROM perf_collections WHERE kind = 'wl_f') FROM new_pc;

-- ================================================================
-- PASSO 3 — TEMP TABLE de resultados + GRANT ANTES da troca de role
-- (mesma correção já incorporada desde o primeiro rascunho, aprendida
-- com 02C -STAGING-FINAL-FIX-01)
-- ================================================================
CREATE TEMP TABLE perf_results (case_label TEXT, plan_json JSON);

GRANT SELECT ON perf_ctx TO authenticated;
GRANT SELECT ON perf_collections TO authenticated;
GRANT SELECT ON perf_set_variants TO authenticated;
GRANT INSERT, SELECT ON perf_results TO authenticated;

SELECT
    'perf_ctx' AS temp_table,
    has_table_privilege('authenticated', 'pg_temp.perf_ctx', 'SELECT') AS authenticated_pode_ler
UNION ALL
SELECT 'perf_collections', has_table_privilege('authenticated', 'pg_temp.perf_collections', 'SELECT')
UNION ALL
SELECT 'perf_set_variants', has_table_privilege('authenticated', 'pg_temp.perf_set_variants', 'SELECT')
UNION ALL
SELECT 'perf_results', has_table_privilege('authenticated', 'pg_temp.perf_results', 'SELECT');
-- Esperado: true nas 4 linhas — se qualquer uma vier false, corrigir
-- o GRANT correspondente antes de prosseguir.

-- ================================================================
-- PASSO 4 — trocar para o contexto do Owner A autenticado
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub',
                   (SELECT value FROM perf_ctx WHERE key = 'owner_a'),
                   true);

-- PRECOND-ADMIN — prova real (mandato STAGING-FINAL-AUDIT-01, item
-- 13): Owner A, já impersonado, não é admin. Se isto falhar, os
-- workloads abaixo não medem o caminho real de um usuário comum.
DO $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT public.is_admin() INTO v_is_admin;
    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION 'fixture invalido: Owner A resolvido em perf_ctx e ADMIN (is_admin()=%) — refazer selecao de owner_a excluindo public.admin_user', v_is_admin;
    END IF;
END $$;

-- CONTEXTO DO BENCHMARK (mandato STAGING-FINAL-FIX-01, item 6) —
-- exposto ANTES de qualquer plano, para que a interpretação dos
-- workloads B/C seja inequívoca sem depender de reler comentário.
SELECT
    (SELECT value FROM perf_ctx WHERE key = 'card_set_id')       AS card_set_id,
    (SELECT value FROM perf_ctx WHERE key = 'total_positions')   AS total_positions,
    (SELECT value FROM perf_ctx WHERE key = 'pool_size')         AS pool_size,
    (SELECT value FROM perf_ctx WHERE key = 'wl_b_target')       AS wl_b_target;

-- ================================================================
-- PASSO 5 — workloads A-I medidos (todos como authenticated
-- não-admin, confirmado acima)
-- ================================================================

-- Workload A — summary de Collection vazia
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_a';
    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('A - summary Collection vazia', v_json);
END $$;

-- Workload B — summary + positions de Collection ~75%
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_b';
    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('B - summary ~75% (proxy 90/120)', v_json);

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_positions(%L::uuid, FALSE)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('B - positions only_missing=false', v_json);
END $$;

-- Workload C — summary com a MAIOR cobertura disponível no fixture
-- atual (mandato STAGING-FINAL-FIX-01, item 5). O código sempre alocou
-- 1 Physical Card por linha de perf_set_variants (pool_size posições),
-- nunca por total_positions — logo só é "100%" quando pool_size =
-- total_positions; caso contrário é cobertura parcial real, e chamar
-- isso de "Collection completa (100%)" seria uma alegação falsa
-- sempre que o Card Set escolhido tiver Cards sem nenhum Card Variant
-- cadastrado hoje (situação normal em catálogo parcial de
-- desenvolvimento). Rótulo e expected_* calculados dinamicamente.
DO $$
DECLARE
    v_id                  UUID;
    v_json                JSON;
    v_total_positions     BIGINT;
    v_pool_size           BIGINT;
    v_expected_satisfied  BIGINT;
    v_expected_percentage NUMERIC;
    v_label               TEXT;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_c';
    SELECT value::bigint INTO v_total_positions FROM perf_ctx WHERE key = 'total_positions';
    SELECT value::bigint INTO v_pool_size FROM perf_ctx WHERE key = 'pool_size';

    v_expected_satisfied  := v_pool_size;
    v_expected_percentage := round((v_pool_size::numeric / v_total_positions::numeric) * 100, 2);

    v_label := CASE
        WHEN v_pool_size = v_total_positions THEN
            format('C - summary Collection completa (100%%, pool_size=%s = total_positions=%s)', v_pool_size, v_total_positions)
        ELSE
            format('C - summary maxima cobertura disponivel no fixture atual (pool_size=%s / total_positions=%s = %s%%, NAO 100%% — escolha de fixture, nao requisito de STANDARD_SET)',
                v_pool_size, v_total_positions, v_expected_percentage)
    END;

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES (v_label, v_json);

    INSERT INTO perf_results (case_label, plan_json) VALUES (
        'C - contexto (expected_satisfied/expected_percentage)',
        json_build_object(
            'total_positions', v_total_positions,
            'pool_size', v_pool_size,
            'expected_satisfied', v_expected_satisfied,
            'expected_percentage', v_expected_percentage,
            'is_100_percent', v_pool_size = v_total_positions
        )
    );
END $$;

-- Workload D — summary de Collection com muitas duplicatas (2.000
-- Physical Cards, 5 posições distintas)
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_d';
    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('D - summary muitas duplicatas (2000 PC / 5 posicoes)', v_json);
END $$;

-- Workload E — summary de Collection com 500 Allocations
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_e';
    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('E - summary 500 Allocations', v_json);
END $$;

-- Workload F — summary de Collection com 5.000 Allocations (maior
-- volume)
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_f';
    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('F - summary 5000 Allocations', v_json);
END $$;

-- Workload G — summary em sequência sobre as 6 Collections do mesmo
-- Card Set (prova de ausência de degradação por vizinhança catalogal)
DO $$
DECLARE
    v_kind TEXT;
    v_id   UUID;
    v_json JSON;
BEGIN
    FOR v_kind, v_id IN SELECT kind, id FROM perf_collections ORDER BY kind LOOP
        EXECUTE format(
            'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
            v_id
        ) INTO v_json;
        INSERT INTO perf_results (case_label, plan_json)
        VALUES ('G - summary em sequencia (' || v_kind || ')', v_json);
    END LOOP;
END $$;

-- Workload H — positions com only_missing = true sobre a Collection
-- do workload B
DO $$
DECLARE
    v_id UUID;
    v_json JSON;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_b';
    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_positions(%L::uuid, TRUE)',
        v_id
    ) INTO v_json;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('H - positions only_missing=true', v_json);
END $$;

-- Workload I — experiência de abertura de tela real: summary +
-- positions(only_missing=false) sobre a Collection do workload B,
-- capturados em sequência. Mandato STAGING-FINAL-FIX-01, item 7:
-- execution_time de cada plano extraído do próprio JSON (chave
-- "Execution Time", topo do array retornado por FORMAT JSON, em ms)
-- e o combined_execution_time_ms explicitamente calculado como a
-- SOMA dos dois — nunca uma medição própria de tempo de parede, só a
-- soma dos Execution Time individuais já capturados, registrada como
-- tal em vez de deixar implícito em comentário.
DO $$
DECLARE
    v_id                UUID;
    v_json_summary      JSON;
    v_json_positions    JSON;
    v_exec_summary_ms   NUMERIC;
    v_exec_positions_ms NUMERIC;
BEGIN
    SELECT id INTO v_id FROM perf_collections WHERE kind = 'wl_b';

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_summary(%L::uuid)',
        v_id
    ) INTO v_json_summary;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('I - summary (parte 1 da tela)', v_json_summary);

    EXECUTE format(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM public.collection_completion_positions(%L::uuid, FALSE)',
        v_id
    ) INTO v_json_positions;
    INSERT INTO perf_results (case_label, plan_json) VALUES ('I - positions (parte 2 da tela)', v_json_positions);

    v_exec_summary_ms   := (v_json_summary->0->>'Execution Time')::numeric;
    v_exec_positions_ms := (v_json_positions->0->>'Execution Time')::numeric;

    INSERT INTO perf_results (case_label, plan_json) VALUES (
        'I - combined execution time (summary + positions)',
        json_build_object(
            'execution_time_summary_ms', v_exec_summary_ms,
            'execution_time_positions_ms', v_exec_positions_ms,
            'combined_execution_time_ms', v_exec_summary_ms + v_exec_positions_ms,
            'nota', 'combined = soma dos Execution Time dos dois planos acima, nao uma medicao de tempo de parede separada'
        )
    );
END $$;

-- ================================================================
-- PASSO 6 — leitura final dos planos capturados
-- ================================================================
SELECT case_label, plan_json FROM perf_results ORDER BY case_label;

-- ================================================================
-- PASSO 7 — desfazer tudo
-- ================================================================
ROLLBACK;

-- ================================================================
-- PASSO 8 (fora de transação) — prova de zero resíduo
-- ================================================================
SELECT count(*) AS physical_card_count_depois
FROM public.physical_card
WHERE inventory_id = (
    SELECT id FROM public.inventory ORDER BY owner_user_id LIMIT 1
);
-- Esperado: physical_card_count_depois = physical_card_count_antes (Passo -1)

SELECT count(*) AS collections_residuais
FROM public.collection
WHERE name LIKE 'PERF-TEST-02E-%';
-- Esperado: 0

SELECT count(*) AS storage_containers_residuais
FROM public.storage_container
WHERE name = 'PERF-TEST-02E-STORAGE';
-- Esperado: 0

-- ================================================================
-- Nota de interpretação dos planos (mesmo espírito de 5807/5809 —
-- não tratar Seq Scan automaticamente como falha). Registrar, para
-- cada workload capturado em perf_results: tipo de nó do planner,
-- tempo total de execução, buffers (shared hit/read), e se os
-- caminhos de acesso esperados foram escolhidos — collection_
-- reference.collection_id (UNIQUE), collection_card_set_reference.
-- collection_reference_id (PK), collection_allocation.collection_id
-- (índice dedicado) + physical_card_id (UNIQUE), physical_card.id
-- (PK), card_variant.id (PK), card.id (PK) + card_set_id (coluna
-- líder de uq_card_card_set_collector_number/
-- uq_card_card_set_collector_order). Nenhum índice novo foi criado
-- para este benchmark — toda a cadeia de JOIN dos dois read models já
-- é coberta por chaves primárias/UNIQUE/índice existentes (ver
-- relatório desta rodada, item 10). Nenhuma conclusão de performance
-- é declarada nesta rodada — só o script que a produzirá quando
-- executado de fato.
-- ================================================================
