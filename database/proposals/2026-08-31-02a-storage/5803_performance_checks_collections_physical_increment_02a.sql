/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5803 - Performance Test Plan: Collections Physical Increment 02A (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Plano de teste de performance pós-migration para storage_container e
physical_card.storage_container_id, com volume representativo de pelo
menos 20.000 Physical Cards (mesmo volume de referência de 5801),
distribuídos entre múltiplos Storage Containers, em contexto
transacional e reversível (BEGIN...ROLLBACK). NÃO EXECUTAR nesta
rodada; requer que as Queries 5020-5024 (e as 5000-5012 já
CONFIRMADO EXECUTADO) estejam aplicadas.

Revisado em COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01:
referências a assign_physical_cards_to_storage() substituídas por
set_physical_cards_storage() (Query 5024, v2.0) — mesma classe de
custo esperada, já que a mudança foi de nome/semântica (suporte a
NULL para limpar Storage, deduplicação de IDs), não de estratégia de
escrita (continua um único UPDATE...WHERE...RETURNING set-based).

Nenhuma alegação de performance deve ser feita antes desta execução
real.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO 0 — Geração de volume (transacional/reversível, NÃO EXECUTAR
-- nesta rodada). Reaproveita o mesmo Inventory de teste e volume de
-- Physical Cards de 5801 (Passo 0); distribui um subconjunto entre
-- alguns Storage Containers recém-criados no mesmo Inventory.
-- ================================================================

-- BEGIN;
--
-- INSERT INTO public.storage_container (inventory_id, name)
-- SELECT :'perf_id'::uuid, 'Storage Teste ' || n
-- FROM generate_series(1, 10) AS n
-- RETURNING id \gset perf_storage_
--
-- -- Atribui storage_container_id a metade das Physical Cards geradas
-- -- no Passo 0 de 5801 (mesmo Inventory de teste), distribuídas entre
-- -- os 10 Storage Containers recém-criados
-- UPDATE public.physical_card pc
-- SET storage_container_id = (
--     SELECT sc.id FROM public.storage_container sc
--     WHERE sc.inventory_id = :'perf_id'::uuid
--     ORDER BY random() LIMIT 1
-- )
-- WHERE pc.inventory_id = :'perf_id'::uuid
--   AND random() < 0.5;
--
-- -- (executar os EXPLAIN dos passos A-C aqui, dentro da mesma transação)
--
-- ROLLBACK; -- reverte tudo

-- ================================================================
-- A. Listar conteúdo de um Storage Container específico
-- ================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM public.physical_card
WHERE storage_container_id = '00000000-0000-0000-0000-000000000000' -- substituir por id real de teste
  AND inventory_id = (
      SELECT i.id FROM public.inventory i WHERE i.owner_user_id = auth.uid()
  );
-- Esperado no plano: Index Scan via ix_physical_card_storage_container
-- para o filtro de storage_container_id; RLS aplica o filtro de
-- inventory_id em paralelo (mesma policy já vigente em physical_card).

-- ================================================================
-- B. create_storage_container() — custo de escrita single-row
-- ================================================================
-- BEGIN;
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.create_storage_container('Storage Teste Perf');
-- ROLLBACK;
-- Esperado no plano: Insert on storage_container, custo dominado pela
-- checagem de FK (inventory_id) via índice — operação single-row, sem
-- relevância de escala (Storage Container não é bulk).

-- ================================================================
-- C. set_physical_cards_storage() com 500 itens, atribuição
-- (escrita — medir dentro de transação revertida)
-- ================================================================
-- BEGIN;
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.set_physical_cards_storage(
--     '<algum_storage_container_id_do_inventory_de_teste>',
--     (SELECT array_agg(id) FROM (
--         SELECT id FROM public.physical_card
--         WHERE inventory_id = :'perf_id'::uuid
--         LIMIT 500
--     ) sub)
-- );
-- ROLLBACK;
-- Esperado no plano: um único Update on physical_card por baixo do
-- UPDATE...WHERE...RETURNING da função; custo dominado pela checagem
-- prévia de atomicidade (count() sobre até 500 ids distintos, via PK)
-- somada à checagem de FK composta por linha (via
-- UNIQUE(id, inventory_id) de storage_container) — mesma classe de
-- custo já observada em add_physical_cards() (52,525ms para 500 itens
-- sobre 20k linhas, Query 5801/5012), sem multiplicador adicional
-- relevante esperado. A deduplicação via array_agg(DISTINCT...)
-- sobre unnest() é O(n log n) sobre no máximo 500 elementos —
-- desprezível frente ao custo do UPDATE em si.

-- ================================================================
-- D. set_physical_cards_storage() com p_storage_container_id NULL
-- (limpeza em lote — mesma forma, sem o bloco de verificação de
-- Storage Container)
-- ================================================================
-- BEGIN;
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.set_physical_cards_storage(
--     NULL,
--     (SELECT array_agg(id) FROM (
--         SELECT id FROM public.physical_card
--         WHERE inventory_id = :'perf_id'::uuid
--           AND storage_container_id IS NOT NULL
--         LIMIT 500
--     ) sub)
-- );
-- ROLLBACK;
-- Esperado no plano: custo igual ou levemente menor que o passo C —
-- pula inteiramente a consulta a storage_container (bloco condicional
-- só executado quando p_storage_container_id IS NOT NULL).

-- ================================================================
-- Nota: mesma ressalva de 5801 — sem volume representativo, o planner
-- pode preferir Seq Scan mesmo com os índices presentes. Os EXPLAINs
-- acima só devem ser lidos como conclusivos depois do PASSO 0 (>= 20.000
-- linhas, com distribuição real entre Storage Containers) ter sido
-- executado na mesma sessão. Nenhuma conclusão de performance é
-- declarada nesta rodada.
-- ================================================================
