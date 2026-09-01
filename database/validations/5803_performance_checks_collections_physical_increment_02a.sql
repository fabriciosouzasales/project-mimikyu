/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5803 - Performance Results: Collections Physical Increment 02A
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01)

Descrição...:
Resultados reais de performance, medidos com EXPLAIN (ANALYZE,
BUFFERS, FORMAT JSON), em contexto transacional reversível: volume
sintético de 20.000 Physical Cards gerado dentro de uma transação sem
COMMIT (mesma técnica de reversibilidade de 5802 — a conexão termina
sem commit, equivalente a ROLLBACK), distribuído aproximadamente 50/50
entre 10 Storage Containers de teste e "sem Storage" (storage_container_id
NULL), sob o Inventory de um usuário real existente. Confirmado ao
final: SELECT count(*) FROM storage_container = 0, SELECT count(*)
FROM physical_card = 0 — nenhuma linha sintética persistiu.

Captura técnica: EXPLAIN (FORMAT JSON) executado via
`EXECUTE '...' INTO v_json` dentro de um bloco PL/pgSQL (DO $$ ... $$),
com os resultados de cada passo gravados em uma TEMP TABLE
(GRANT INSERT/SELECT concedido a authenticated antes da troca de role,
evitando o problema de permissão em TEMP TABLE já observado em rodada
anterior) e lidos por uma SELECT final na mesma sessão/transação.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO — 4 medições, nenhuma
alegação de performance feita antes desta execução real.
================================================================
*/

-- ================================================================
-- A. Listar conteúdo de um Storage Container específico (authenticated,
-- RLS ativa)
-- ================================================================
-- SELECT * FROM public.physical_card WHERE storage_container_id = '<id>';
--
-- Resultado observado:
--   Node Type ......: Index Scan
--   Index Name .....: ix_physical_card_storage_container
--   Shared Hit Blocks: 284 (0 leituras de disco — tudo em buffer cache)
--   Execution Time ..: 0,764 ms (segunda medição: 0,795 ms)
-- Confirma que o índice proposto é de fato escolhido pelo planner para
-- este workload, sem necessidade de índice composto adicional.

-- ================================================================
-- B. create_storage_container() — custo de escrita single-row
-- ================================================================
-- SELECT * FROM public.create_storage_container('...');
--
-- Resultado observado:
--   Node Type ......: Function Scan
--   Execution Time ..: 0,780 ms
-- Sem relevância de escala — operação single-row, não bulk.

-- ================================================================
-- C. set_physical_cards_storage() — atribuição em lote de 500 itens
-- ================================================================
-- SELECT * FROM public.set_physical_cards_storage('<storage_id>', ARRAY[...500 ids...]);
--
-- Resultado observado (duas medições independentes, mesmo volume de
-- 20.000 Physical Cards):
--   Node Type ......: Function Scan
--   Shared Hit Blocks: 18.934
--   Execution Time ..: 64,664 ms / 61,350 ms
-- Mesma ordem de grandeza já observada em add_physical_cards() para
-- 500 itens sobre 20k linhas (52,525 ms, COLLECTIONS-PHYSICAL-
-- INCREMENT-01A) — a validação de atomicidade (count() sobre até 500
-- ids distintos) e a checagem de FK composta por linha não introduzem
-- multiplicador relevante de custo.

-- ================================================================
-- D. set_physical_cards_storage() — limpeza em lote de 500 itens
-- (p_storage_container_id = NULL)
-- ================================================================
-- SELECT * FROM public.set_physical_cards_storage(NULL, ARRAY[...500 ids...]);
--
-- Resultado observado:
--   Node Type ......: Function Scan
--   Execution Time ..: 55,167 ms
-- Custo na mesma ordem de grandeza do passo C, como esperado — pula
-- inteiramente a consulta a storage_container (bloco condicional só
-- executado quando p_storage_container_id IS NOT NULL), sem diferença
-- prática mensurável neste volume.

-- ================================================================
-- Conclusão desta rodada: os quatro workloads medidos permanecem sob
-- ~65ms mesmo com 20.000 Physical Cards já existentes no Inventory
-- alvo e lotes de 500 itens — dentro da mesma faixa de latência já
-- aceita para add_physical_cards() na fundação anterior. Nenhuma
-- alegação de performance para volumes maiores (dezenas de milhares
-- por usuário, múltiplos Storage Containers com uso real) é feita
-- nesta rodada — apenas o volume de referência testado.
-- ================================================================
