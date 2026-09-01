/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5805 - Performance Results: Collections Physical Increment 02B
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01)

Descrição...:
Resultados reais de performance, medidos com EXPLAIN (ANALYZE,
BUFFERS), em contexto transacional reversível: volume sintético de
20.000 Collections gerado dentro de uma transação sem COMMIT (mesma
técnica de reversibilidade de 5802/5803 — a conexão termina sem
commit, equivalente a ROLLBACK), sob o Inventory de um usuário real
existente, distribuído 80% ACTIVE / 20% ARCHIVED (16.000 / 4.000).
Executado quatro vezes (uma por caso A-D, cada uma em sua própria
chamada execute_sql, setup + EXPLAIN + ROLLBACK na mesma sessão,
metodologia corrigida de COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-
FINAL-01, item 2). Confirmado ao final de cada execução: SELECT
count(*) FROM collection = 0, SELECT count(*) FROM storage_container
= 0 — nenhuma linha sintética persistiu.

Metodologia de simulação de usuário autenticado: `SELECT set_config(
'role','authenticated', true)` + `SELECT set_config('request.jwt.
claim.sub', '<user_id>', true)` reproduzem o contexto de auth.uid() e
RLS de uma sessão real dentro da mesma transação de teste.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO — 4 medições, todas com uso
confirmado do índice esperado.
================================================================
*/

-- ================================================================
-- A. Collections do Owner (sem filtro de status)
-- ================================================================
-- SELECT * FROM public.collection WHERE owner_user_id = '<owner_a>'::uuid;
--
-- Resultado observado (20.000 linhas do Owner):
--   Node Type ......: Bitmap Heap Scan (via Bitmap Index Scan em
--                      ix_collection_owner_lifecycle)
--   Recheck Cond ...: owner_user_id = '<owner_a>'
--   Heap Blocks ....: exact=422
--   Buffers ........: shared hit=440
--   Actual Rows ....: 20000
--   Execution Time ..: 8,508 ms
-- O RLS wrapper (One-Time Filter sobre InitPlan de (select auth.uid()))
-- não impede o planner de escolher o índice — confirmado inspecionando
-- o plano completo, não só o nó de topo.

-- ================================================================
-- B. Collections ACTIVE do Owner
-- ================================================================
-- SELECT * FROM public.collection
-- WHERE owner_user_id = '<owner_a>'::uuid AND lifecycle_status = 'ACTIVE';
--
-- Resultado observado (16.000 linhas ACTIVE):
--   Node Type ......: Index Scan using ix_collection_owner_lifecycle
--   Index Cond .....: (owner_user_id = '<owner_a>') AND
--                      (lifecycle_status = 'ACTIVE')
--   Buffers ........: shared hit=883
--   Actual Rows ....: 16000
--   Execution Time ..: 11,207 ms
-- Índice composto usado diretamente (Index Scan, não Bitmap), como
-- esperado para a condição completa.

-- ================================================================
-- C. Collections ARCHIVED do Owner
-- ================================================================
-- SELECT * FROM public.collection
-- WHERE owner_user_id = '<owner_a>'::uuid AND lifecycle_status = 'ARCHIVED';
--
-- Resultado observado (4.000 linhas ARCHIVED — seletividade menor):
--   Node Type ......: Index Scan using ix_collection_owner_lifecycle
--   Index Cond .....: (owner_user_id = '<owner_a>') AND
--                      (lifecycle_status = 'ARCHIVED')
--   Buffers ........: shared hit=855
--   Actual Rows ....: 4000
--   Execution Time ..: 4,980 ms
-- Planner preferiu o índice mesmo com seletividade baixa (20% das
-- linhas do Owner) — confirma a hipótese registrada na proposta
-- original.

-- ================================================================
-- D. Abertura de uma Collection específica por id (PK)
-- ================================================================
-- SELECT * FROM public.collection WHERE id = '<algum_collection_id>'::uuid;
--
-- Resultado observado:
--   Node Type ......: Index Scan using collection_pkey
--   Actual Rows ....: 1
--   Execution Time ..: 0,032 ms
-- Trivial, independente do volume — confirmado.

-- ================================================================
-- Conclusão desta rodada: os quatro workloads medidos usam o índice
-- pretendido (ix_collection_owner_lifecycle, ou a PK no caso D) mesmo
-- com 20.000 Collections reais no Inventory alvo, em ambas as
-- distribuições ACTIVE/ARCHIVED testadas — dentro da mesma faixa de
-- latência (< 12 ms) já aceita nos incrementos físicos anteriores
-- (01B/02A). Nenhuma alegação de performance para volumes maiores
-- (múltiplas dezenas de milhares por usuário, uso real e concorrente)
-- é feita nesta rodada — apenas o volume de referência testado.
-- ================================================================
