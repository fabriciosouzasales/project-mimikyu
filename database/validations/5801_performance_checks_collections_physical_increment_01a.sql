/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5801 - Performance Checks: Collections Physical Increment 01A
Versão......: 2.0
Status......: EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Plano de performance de public.physical_card sob volume representativo
(>= 20.000 linhas), executado em contexto transacional reversível
(BEGIN...ROLLBACK) contra o Inventory real do User A
(a6a3f086-f73c-452b-8c74-401647fd7456) — nenhuma linha sintética
permanece em produção. Objetivo: confirmar por EXPLAIN (ANALYZE,
BUFFERS), não apenas pela existência dos índices, que os dois índices
compostos de physical_card (Query 5010) e o UNIQUE(owner_user_id) de
inventory (Query 5000) são de fato utilizados pelos padrões de acesso
reais, incluindo a própria RLS.

Técnica de geração de volume: tabelas TEMP (perf_variants/
perf_languages) numerando as 6.483 Card Variant e as 2 Language reais
via row_number(), combinadas por aritmética modular
((g.n-1) % total)+1 contra generate_series(1,20000) — determinística e
uniforme, muito mais rápida que ORDER BY random() LIMIT 1 por linha
(hipótese original do rascunho pré-execução, descartada nesta
execução por custo). Para a chamada bulk-500 (Query D), o payload
JSONB foi pré-materializado em uma TEMP table adicional
(perf_payload) e GRANT SELECT explícito emitido para authenticated
ANTES do SET LOCAL role — achado real desta execução: TEMP tables
criadas sob o papel padrão da conexão (postgres) não são visíveis
para authenticated dentro da mesma transação sem esse GRANT
explícito, mesmo estando ambos os comandos na mesma sessão/transação.

STATUS DESTA QUERY: EXECUTADA. Resultados abaixo refletem o plano de
execução real, não apenas a intenção de índice.
================================================================
*/

-- ================================================================
-- Preparação (dentro de BEGIN...ROLLBACK): volume de 20.000 Physical
-- Cards no Inventory real de User A, ANALYZE explícito antes de medir.
-- ================================================================
-- BEGIN;
-- CREATE TEMP TABLE perf_variants AS SELECT id, row_number() OVER () AS rn FROM public.card_variant;
-- CREATE TEMP TABLE perf_languages AS SELECT id, row_number() OVER () AS rn FROM public.language;
-- INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
-- SELECT v.id, l.id, 'a6a3f086-f73c-452b-8c74-401647fd7456'
-- FROM generate_series(1,20000) AS g(n)
-- JOIN perf_variants v ON v.rn = ((g.n - 1) % 6483) + 1
-- JOIN perf_languages l ON l.rn = ((g.n - 1) % 2) + 1;
-- ANALYZE public.physical_card;
-- SET LOCAL role authenticated;
-- SET LOCAL request.jwt.claim.sub = 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';

-- ================================================================
-- A. Listar Physical Cards do próprio Inventory (padrão de acesso mais
-- comum — tela de Binder/Collection Library)
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.physical_card ORDER BY created_at DESC LIMIT 50;
--
-- [RESULTADO] Execution Time: 13.518 ms. Index Scan using
-- ix_physical_card_inventory_language para a leitura da tabela;
-- resolução de RLS via Index Scan using inventory_owner_user_id_key
-- (o UNIQUE(owner_user_id) de inventory serve diretamente como índice
-- da subquery de RLS).   [STATUS] PASS — índice realmente usado, não
-- apenas presente.

-- ================================================================
-- B. Contagem por Card Variant (ex.: "quantas cópias tenho desta
-- carta")
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT card_variant_id, count(*) FROM public.physical_card
-- GROUP BY card_variant_id;
--
-- [RESULTADO] Execution Time: 0.751 ms. Index Only Scan using
-- ix_physical_card_inventory_variant, com inventory_id E
-- card_variant_id ambos aparecendo no Index Cond — leitura
-- inteiramente coberta pelo índice, sem acesso à tabela heap.
--   [STATUS] PASS

-- ================================================================
-- C. Filtro por Language, ordenado por criação (ex.: "minhas cartas em
-- inglês, mais recentes primeiro")
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.physical_card
-- WHERE language_id = '7a7d7c56-80f7-49c6-a837-24486e820484'
-- ORDER BY created_at DESC LIMIT 50;
--
-- [RESULTADO] Execution Time: 7.439 ms. Index Scan using
-- ix_physical_card_inventory_language, com inventory_id E language_id
-- ambos aparecendo no Index Cond.   [STATUS] PASS

-- ================================================================
-- D. Chamada bulk de 500 itens via add_physical_cards() (payload
-- pré-materializado em TEMP table + GRANT SELECT para authenticated
-- antes do SET LOCAL role — ver nota técnica acima)
-- ================================================================
-- CREATE TEMP TABLE perf_payload AS
-- SELECT jsonb_agg(jsonb_build_object('card_variant_id', v.id, 'language_id', l.id)) AS payload
-- FROM generate_series(1,500) AS g(n)
-- JOIN perf_variants v ON v.rn = ((g.n - 1) % 6483) + 1
-- JOIN perf_languages l ON l.rn = ((g.n - 1) % 2) + 1;
-- GRANT SELECT ON perf_payload TO authenticated;
-- SET LOCAL role authenticated;
-- SET LOCAL request.jwt.claim.sub = 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
-- EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
-- SELECT * FROM public.add_physical_cards((SELECT payload FROM perf_payload));
-- ROLLBACK;
--
-- [RESULTADO] Execution Time: 52.525 ms para 500 linhas inseridas e
-- retornadas (Function Scan on add_physical_cards, rows=500,
-- Buffers: shared hit=11169 dirtied=16 written=16). O corpo interno
-- da função (SECURITY DEFINER, PL/pgSQL) é opaco ao EXPLAIN externo —
-- não é possível decompor o plano do INSERT/SELECT interno a partir
-- desta chamada; a métrica confiável aqui é o tempo de execução
-- ponta a ponta da RPC, não um Index Scan interno visível. A
-- resolução de v_inventory_id (mesma forma de lookup confirmada no
-- item A: SELECT ... WHERE owner_user_id = auth.uid()) usa o mesmo
-- UNIQUE(owner_user_id) já comprovado indexado.   [STATUS] PASS —
-- tempo aceitável para o pior caso do limite de payload (500/500),
-- sem sinal de scan sequencial na única parte observável do plano.

-- ================================================================
-- RESUMO: quatro consultas medidas sob volume de 20.000 Physical
-- Cards reais no Inventory de um usuário real, contexto
-- integralmente reversível (ROLLBACK, sem resíduo em produção —
-- confirmado por database/validations/5800_..., item 24).
-- ix_physical_card_inventory_variant, ix_physical_card_inventory_
-- language e inventory_owner_user_id_key (UNIQUE) confirmados em uso
-- real pelos planos de execução, não apenas presentes no schema —
-- performance aprovada com base em EXPLAIN (ANALYZE, BUFFERS), não
-- apenas na existência dos índices.
-- ================================================================
