/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5801 - Performance Test Plan: Collections Physical Increment 01A (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01 —
               expandido para plano de volume representativo e 4
               consultas: A/B/C/D)

Descrição...:
Plano de teste de performance pós-migration, com volume representativo
de pelo menos 20.000 Physical Cards, em contexto de teste transacional
e reversível (BEGIN...ROLLBACK) — nenhuma linha sintética deve
persistir após o teste. NÃO EXECUTAR nesta rodada; requer que as
Queries 5000-5012 já estejam aplicadas e um ambiente com dado real de
catálogo (card_variant_id/language_id válidos, exigidos pelas FKs
RESTRICT) disponível para gerar o volume.

Nenhuma alegação de performance deve ser feita antes desta execução
real (COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01, Gate 5, item 9).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO 0 — Geração de volume (transacional/reversível, NÃO EXECUTAR
-- nesta rodada)
--
-- Diferente do teste de "batch >500 rejeitado" (Query 5800, item 13),
-- que usa UUIDs aleatórios porque falha antes de qualquer INSERT, um
-- teste de volume real precisa de card_variant_id/language_id
-- GENUÍNOS do catálogo — as FKs RESTRICT rejeitariam UUIDs
-- inventados. A geração abaixo usa amostragem com repetição sobre o
-- catálogo já existente (card_variant/language), distribuída sobre um
-- Inventory de teste dedicado, e tudo dentro de uma transação que
-- termina em ROLLBACK — nenhum dado sintético fica no banco.
-- ================================================================

-- BEGIN;
--
-- -- Inventory de teste isolado (não usar um Inventory de usuário real)
-- INSERT INTO public.inventory (owner_user_id)
-- VALUES ('00000000-0000-0000-0000-000000000000') -- substituir por um auth.users de teste real
-- RETURNING id \gset perf_
--
-- -- Popula >= 20.000 Physical Cards amostrando card_variant/language
-- -- já existentes no catálogo (com repetição — duplicatas são
-- -- permitidas por design, C-47)
-- INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
-- SELECT
--     (SELECT id FROM public.card_variant ORDER BY random() LIMIT 1),
--     (SELECT id FROM public.language ORDER BY random() LIMIT 1),
--     :'perf_id'::uuid
-- FROM generate_series(1, 20000);
--
-- -- (executar os EXPLAIN dos passos A-D aqui, dentro da mesma transação)
--
-- ROLLBACK; -- reverte tudo: Inventory de teste e as 20.000 linhas geradas

-- ================================================================
-- A. Listar Physical Cards do Inventory autenticado
-- ================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM public.physical_card
WHERE inventory_id = (
    SELECT i.id FROM public.inventory i WHERE i.owner_user_id = auth.uid()
);
-- Esperado no plano: Index Scan via ix_physical_card_inventory_variant
-- (ou ix_physical_card_inventory_language, dependendo do plano
-- escolhido pelo planner) para o filtro de inventory_id; resolução de
-- auth.uid() -> inventory.id via Index Scan no UNIQUE(owner_user_id).

-- ================================================================
-- B. Buscar/contar uma Card Variant dentro do Inventory autenticado
-- ================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT card_variant_id, count(*) AS copias
FROM public.physical_card
WHERE inventory_id = (
    SELECT i.id FROM public.inventory i WHERE i.owner_user_id = auth.uid()
)
AND card_variant_id = '00000000-0000-0000-0000-000000000000' -- substituir por id real de teste
GROUP BY card_variant_id;
-- Esperado no plano: uso do prefixo (inventory_id, card_variant_id) do
-- índice composto ix_physical_card_inventory_variant.

-- ================================================================
-- C. Filtrar Physical Cards por Language dentro do Inventory
-- autenticado ("minhas cartas por idioma")
-- ================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM public.physical_card
WHERE inventory_id = (
    SELECT i.id FROM public.inventory i WHERE i.owner_user_id = auth.uid()
)
AND language_id = '00000000-0000-0000-0000-000000000000' -- substituir por id real de teste
ORDER BY created_at DESC;
-- Esperado no plano: Index Scan via ix_physical_card_inventory_language
-- (inventory_id, language_id) — introduzido nesta revisão em
-- substituição ao índice global ix_physical_card_language_id.

-- ================================================================
-- D. RPC bulk com 500 itens
-- (escrita — medir dentro de transação revertida, com
-- card_variant_id/language_id reais)
-- ================================================================
-- BEGIN;
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.add_physical_cards(
--     (SELECT jsonb_agg(jsonb_build_object(
--         'card_variant_id', cv.id,
--         'language_id', lg.id))
--      FROM (SELECT id FROM public.card_variant ORDER BY random() LIMIT 500) cv,
--           LATERAL (SELECT id FROM public.language ORDER BY random() LIMIT 1) lg)
-- );
-- ROLLBACK;
-- Esperado no plano: um único Insert on physical_card por baixo do
-- INSERT...SELECT...RETURNING da função; custo dominado pelas 3
-- checagens de FK (card_variant_id/language_id/inventory_id) por
-- linha, todas via índice.

-- ================================================================
-- Nota: sem volume de dados representativo (dezenas de milhares de
-- linhas por usuário, conforme escala prevista), o planner do
-- Postgres pode preferir Seq Scan mesmo com os índices presentes, por
-- estimar custo menor em tabelas pequenas — isso não invalidaria os
-- índices, apenas refletiria o volume real no momento do teste. Os
-- quatro EXPLAINs acima só devem ser lidos como conclusivos depois do
-- PASSO 0 (>= 20.000 linhas) ter sido executado na mesma sessão.
-- Nenhuma conclusão de performance é declarada nesta rodada.
-- ================================================================
