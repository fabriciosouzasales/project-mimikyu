/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5805 - Performance Test Plan: Collections Physical Increment 02B (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-
               FINAL-01, item 2 — correção de metodologia transacional)

Descrição...:
Plano de teste de performance pós-migration para public.collection,
com volume representativo de pelo menos 20.000 Collections sintéticas
distribuídas entre múltiplos Users/contextos de teste. NÃO EXECUTAR
nesta rodada; requer que as Queries 5030-5039 estejam aplicadas.

CORREÇÃO DE METODOLOGIA (2026-08-31, COLLECTIONS-PHYSICAL-INCREMENT-
02B-MODELING-FINAL-01, item 2). O plano original de 5803 (Storage,
02A) continha um roteiro dividido em múltiplos blocos de comentário
(BEGIN em um bloco, EXPLAIN em outro, ROLLBACK em outro), como se
pudessem ser executados em chamadas execute_sql separadas mantendo a
mesma transação — isso é FALSO. Cada chamada ao tool execute_sql é sua
própria conexão/sessão Postgres (confirmado experimentalmente em
COLLECTIONS-PHYSICAL-INCREMENT-01B, Fase 4, e reconfirmado na execução
real de 02A): um BEGIN sem COMMIT explícito é descartado quando a
chamada/conexão termina — não sobra "aberto" para a próxima chamada.
Qualquer plano que dependa disso silenciosamente não mede nada (ou
mede contra uma tabela vazia, sem erro visível).

Metodologia CORRIGIDA — preferencial, já provada em 01B/02A: todo o
ciclo (setup sintético + EXPLAIN/medições + ROLLBACK) executa dentro
de UMA ÚNICA chamada execute_sql, como um script sequencial de
múltiplas statements na mesma sessão:

  1. BEGIN;
  2. Geração do volume sintético (>= 20.000 Collections, distribuídas
     entre >= 2 Owners/Inventories de teste reais, cada Collection com
     um default_storage_container_id válido do mesmo Owner);
  3. set_config('role','authenticated', true) +
     set_config('request.jwt.claim.sub', '<uuid>', true) para simular
     o Owner de teste (mesma técnica de 5802/5804);
  4. Para cada consulta A-D: EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
     capturado via bloco PL/pgSQL (DO $$ ... $$ com
     EXECUTE '...' INTO v_json), persistido em TEMP TABLE criada e
     com GRANT INSERT/SELECT concedido a authenticated ANTES da troca
     de role (evita o problema de permissão em TEMP TABLE já observado
     em 01B, Fase 4) — DO blocks não retornam linhas diretamente;
  5. SELECT final lendo a TEMP TABLE, ainda na mesma sessão;
  6. ROLLBACK;

Fallback documentado (só se o passo acima se mostrar inviável pelo
mecanismo real disponível no momento da execução — não antecipado,
mas registrado por pedido explícito desta rodada): usar dados de teste
com nome/prefixo identificável (ex. 'PERF-TEST-02B-<timestamp>') em vez
de transação revertida, medir com EXPLAIN normalmente, e then executar
cleanup explícito (DELETE FROM collection WHERE name LIKE
'PERF-TEST-02B-%') com prova de zero resíduo ao final
(SELECT count(*) ... = 0), no mesmo padrão de rigor já exigido para
qualquer escrita sintética neste projeto.

Nenhuma alegação de performance deve ser feita antes desta execução
real — nem por extrapolação dos números já observados em 01B/02A.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- ESBOÇO DO SCRIPT ÚNICO (uma só chamada execute_sql na execução real)
-- ================================================================
-- BEGIN;
--
-- -- Passo 0a: game/inventory/storage_container de teste já existentes
-- -- (reaproveitar fixtures reais de 01B/02A, não sintetizar de novo)
--
-- -- Passo 0b: volume sintético de Collections
-- INSERT INTO public.collection (
--     owner_user_id, game_id, name, default_storage_container_id
-- )
-- SELECT
--     :'owner_a_id'::uuid,
--     :'game_id'::uuid,
--     'PERF-TEST-02B-' || n,
--     :'storage_a_id'::uuid
-- FROM generate_series(1, 20000) AS n;
--
-- -- Passo 0c: simular Owner autenticado
-- SELECT set_config('role', 'authenticated', true);
-- SELECT set_config('request.jwt.claim.sub', :'owner_a_id', true);
--
-- -- TEMP TABLE para capturar os planos (GRANT antes da troca de role
-- -- já ocorreu acima, então isto deve ser criado ANTES do set_config)
-- -- CREATE TEMP TABLE perf_results (case_label text, plan_json jsonb);
-- -- GRANT INSERT, SELECT ON perf_results TO authenticated;
--
-- -- DO $$ ... $$ com EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) para cada
-- -- caso A-D abaixo, INSERT INTO perf_results
--
-- -- SELECT * FROM perf_results;
--
-- ROLLBACK;

-- ================================================================
-- A. Collections do Owner (sem filtro de status)
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.collection WHERE owner_user_id = :'owner_a_id'::uuid;
-- Esperado no plano: Index Scan via ix_collection_owner_lifecycle
-- (prefixo owner_user_id sozinho).

-- ================================================================
-- B. Collections ACTIVE do Owner
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.collection
-- WHERE owner_user_id = :'owner_a_id'::uuid AND lifecycle_status = 'ACTIVE';
-- Esperado no plano: Index Scan via ix_collection_owner_lifecycle
-- (owner_user_id + lifecycle_status), sem Seq Scan.

-- ================================================================
-- C. Collections ARCHIVED do Owner
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.collection
-- WHERE owner_user_id = :'owner_a_id'::uuid AND lifecycle_status = 'ARCHIVED';
-- Mesmo índice do caso B; volume esperado bem menor (a maioria das
-- Collections sintéticas nasce ACTIVE) — confirmar que o planner ainda
-- prefere o índice mesmo com seletividade baixa.

-- ================================================================
-- D. Abertura de uma Collection específica por id (PK)
-- ================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.collection WHERE id = :'algum_collection_id'::uuid;
-- Esperado no plano: Index Scan (PK), trivial, independe do volume.

-- ================================================================
-- Nota: sem volume representativo (>= 20.000 linhas, distribuição real
-- entre ACTIVE/ARCHIVED), o planner pode preferir Seq Scan mesmo com
-- os índices presentes — mesma ressalva já registrada em 5801/5803.
-- Nenhuma conclusão de performance é declarada nesta rodada.
-- ================================================================
