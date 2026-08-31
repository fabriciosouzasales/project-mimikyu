/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5800 - Validation Queries: Collections Physical Increment 01A
Versão......: 2.0
Status......: EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Bateria de validação funcional/segurança pós-migration para
public.inventory e public.physical_card, cobrindo os 23 itens exigidos
em COLLECTIONS-PHYSICAL-INCREMENT-01A (revisões 01A-REVISION-01) e os
invariantes de COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01 (Gate 5).
Executada ao vivo contra o banco físico em
COLLECTIONS-PHYSICAL-INCREMENT-01B (Fases 1, 2, 3 e 5), depois de
5000-5012 CONFIRMADO EXECUTADO. Todo teste que grava dado é
transacional com ROLLBACK (exceto o item 17, idempotente por
construção via ON CONFLICT DO NOTHING) — total_physical_cards em
produção permanece 0 após toda a bateria, confirmado no item 24.

Cada item abaixo registra: [ROTEIRO] o que foi executado,
[RESULTADO] o que o banco retornou, [STATUS] PASS/FAIL.

STATUS DESTA QUERY: EXECUTADA. Reutilizável sempre que inventory/
physical_card/add_physical_cards forem alterados novamente.
================================================================
*/

-- ================================================================
-- 1. users_without_inventory = 0
-- ================================================================
SELECT count(*) AS users_without_inventory
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.inventory i WHERE i.owner_user_id = u.id);
-- [RESULTADO] 0   [STATUS] PASS

-- ================================================================
-- 2. users_with_multiple_inventories = 0
-- ================================================================
SELECT owner_user_id, count(*) AS total
FROM public.inventory
GROUP BY owner_user_id
HAVING count(*) > 1;
-- [RESULTADO] 0 linhas   [STATUS] PASS

-- ================================================================
-- 3. physical_cards_invalid_inventory = 0
-- ================================================================
SELECT count(*) AS physical_cards_invalid_inventory
FROM public.physical_card pc
WHERE pc.inventory_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.inventory i WHERE i.id = pc.inventory_id);
-- [RESULTADO] 0   [STATUS] PASS

-- ================================================================
-- 4. grants anon = 0 (inventory + physical_card)
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('inventory', 'physical_card')
  AND grantee = 'anon';
-- [RESULTADO] 0 linhas   [STATUS] PASS. Confirmado também por acesso
-- real negado a nível de tabela (SET ROLE anon; SELECT ... ->
-- ERROR 42501: permission denied for table inventory).

-- ================================================================
-- 5. authenticated sem INSERT/UPDATE/DELETE direto
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('inventory', 'physical_card')
  AND grantee = 'authenticated'
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
-- [RESULTADO] 0 linhas (authenticated tem só SELECT em ambas)   [STATUS] PASS

-- ================================================================
-- 6. RLS: usuário A não vê Physical Card de B / Inventory de B
-- [ROTEIRO] SET LOCAL role authenticated + request.jwt.claim.sub = <uid>,
-- alternando entre User A (fe316458-49dd-44e1-aac0-f4b7604ef8f2) e
-- User B (91668098-f415-4519-8558-3106fe132454); SELECT count(*)/
-- owner_user_id de public.inventory e public.physical_card em cada
-- sessão.
-- [RESULTADO] Sessão A: 1 inventory visível (owner=A), 0 physical
-- cards. Sessão B: 1 inventory visível (owner=B), 0 physical cards.
-- Nenhuma sessão viu a linha da outra.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 7. authenticated sem INSERT direto na tabela physical_card
-- [ROTEIRO] autenticado como A: INSERT INTO public.physical_card
-- (card_variant_id, language_id, inventory_id) VALUES (...);
-- [RESULTADO] ERROR 42501: permission denied for table physical_card
-- (HINT: GRANT INSERT ... TO authenticated) — falha por ausência de
-- GRANT, antes mesmo de avaliar RLS.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 8. RPC só cria no Inventory do próprio auth.uid()
-- [ROTEIRO] autenticado como A, chamar add_physical_cards() e
-- inspecionar de onde vem v_inventory_id no corpo da função —
-- resolvido exclusivamente via SELECT ... WHERE owner_user_id =
-- auth.uid(), nunca de parâmetro de entrada.
-- [RESULTADO] confirmado por leitura do corpo da função (Query 5012)
-- e pela assinatura (item 9, abaixo) — nenhuma superfície para
-- especificar outro Inventory.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 9. inventory_id não pode ser forjado (assinatura da função)
-- ================================================================
SELECT pg_get_function_identity_arguments(oid) AS assinatura
FROM pg_proc
WHERE proname = 'add_physical_cards' AND pronamespace = 'public'::regnamespace;
-- [RESULTADO] "p_items jsonb" — nenhum parâmetro de inventory_id   [STATUS] PASS

-- ================================================================
-- 10. batch válido N -> N Physical Cards
-- [ROTEIRO] autenticado como A, add_physical_cards() com 3 itens.
-- [RESULTADO] 3 linhas retornadas, 3 ids distintos.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 11. duplicate variant+language permitido
-- [ROTEIRO] mesmo lote do item 10 — 2 dos 3 itens com o mesmo
-- card_variant_id + language_id.
-- [RESULTADO] 3 linhas distintas persistidas (3 ids diferentes), sem
-- erro de unicidade — não existe UNIQUE(card_variant_id, language_id)
-- em physical_card.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 12. batch com item inválido -> 0 inserts (atomicidade)
-- [ROTEIRO] autenticado como A, 2 itens válidos + 1 com
-- card_variant_id = 00000000-0000-0000-0000-000000000000
-- (inexistente).
-- [RESULTADO] ERROR 23503: insert or update on table "physical_card"
-- violates foreign key constraint "physical_card_card_variant_id_fkey"
-- — exceção na própria instrução INSERT...SELECT...RETURNING, os 3
-- itens abortam juntos (nenhum commit parcial possível dentro de um
-- único statement).   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 13. batch >500 rejeitado
-- [ROTEIRO] autenticado como A, 501 itens com UUIDs aleatórios.
-- [RESULTADO] ERROR P0001: lote excede o limite de 500 itens por
-- chamada — falha antes de qualquer tentativa de INSERT.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 14. batch vazio rejeitado
-- [ROTEIRO] autenticado como A, add_physical_cards('[]'::jsonb).
-- [RESULTADO] ERROR P0001: p_items não pode ser vazio   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 15. payload não-array rejeitado
-- [ROTEIRO] autenticado como A, add_physical_cards('{"card_variant_id":"x"}'::jsonb).
-- [RESULTADO] ERROR P0001: p_items deve ser um array JSON   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 16. Provisionamento: novo User -> exatamente 1 Inventory criado
-- automaticamente, via fluxo real de signup (não INSERT direto em
-- auth.users, bloqueado pelo classificador de segurança do Auto Mode)
-- [ROTEIRO] Fabrício realizou um cadastro real na aplicação
-- (yasmimlinssales@gmail.com); id resultante consultado via SQL após
-- o cadastro: SELECT u.id, (SELECT count(*) FROM inventory WHERE
-- owner_user_id = u.id) FROM auth.users u WHERE u.email = '...'.
-- [RESULTADO] id 71d0ac05-1533-480d-91c4-303acf957676, exatamente 1
-- Inventory (babe3e5e-25f7-4075-8f51-59d1315eb70b), owner_user_id
-- correto. Comportamento observado ao vivo, critério explícito de
-- Fabrício para PASS.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 17. Idempotência do backfill/provisionamento consolidado (Query 5002)
-- [ROTEIRO] reexecutado manualmente o bloco de backfill isolado:
-- INSERT INTO public.inventory (owner_user_id) SELECT id FROM
-- auth.users ON CONFLICT (owner_user_id) DO NOTHING; count(*) de
-- inventory antes e depois.
-- [RESULTADO] 3 antes, 3 depois (3 Users reais: A, B, signup de
-- teste) — nenhuma linha nova, nenhum erro.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 18. inventory: INSERT direto negado (authenticated)
-- [ROTEIRO] autenticado, INSERT INTO public.inventory (owner_user_id)
-- VALUES (auth.uid());
-- [RESULTADO] ERROR 42501: permission denied for table inventory
-- (mesma classe de erro confirmada no item 7, reexecutada
-- especificamente para inventory).   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 19. inventory: UPDATE direto negado (authenticated)
-- [ROTEIRO] autenticado como A, UPDATE public.inventory SET
-- updated_at = now() WHERE owner_user_id = auth.uid();
-- [RESULTADO] ERROR 42501: permission denied for table inventory
-- (HINT: GRANT UPDATE ... TO authenticated)   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 20. inventory: DELETE direto negado (authenticated)
-- [ROTEIRO] autenticado como A, DELETE FROM public.inventory WHERE
-- owner_user_id = auth.uid();
-- [RESULTADO] ERROR 42501: permission denied for table inventory
-- (HINT: GRANT DELETE ... TO authenticated)   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 21. physical_card: UPDATE direto negado (authenticated)
-- [ROTEIRO] autenticado como A, criar 1 Physical Card via RPC (dentro
-- da mesma transação), depois UPDATE public.physical_card SET
-- language_id = <outro_uuid> WHERE id = <id_criado>.
-- [RESULTADO] ERROR 42501: permission denied for table physical_card
-- (HINT: GRANT UPDATE ... TO authenticated) — RPC continua sendo a
-- única superfície de escrita, mesmo para o próprio dado do usuário.
--   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 22. physical_card: DELETE direto negado (authenticated)
-- [ROTEIRO] mesmo padrão do item 21, com DELETE FROM public.
-- physical_card WHERE id = <id_criado>.
-- [RESULTADO] ERROR 42501: permission denied for table physical_card
-- (HINT: GRANT DELETE ... TO authenticated)   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 23. RLS: usuário A não vê Inventory de B (id conhecido)
-- [ROTEIRO] autenticado como B, capturar id de public.inventory
-- (51c1bc97-ed89-45b6-9c5e-090acab0d47b); autenticado como A,
-- SELECT * FROM public.inventory WHERE id = '<id de B>'.
-- [RESULTADO] 0 linhas — a policy inventory_select_own restringe a
-- leitura a owner_user_id = (select auth.uid()), o Inventory de B
-- nunca aparece para A mesmo conhecendo o id.   [STATUS] PASS
-- ================================================================

-- ================================================================
-- 24. Confirmação de ausência de resíduo em produção após toda a
-- bateria (todo teste com escrita foi ROLLBACK; item 16 é dado real
-- de um cadastro genuíno, item 17 é idempotente por construção)
-- ================================================================
SELECT
  (SELECT count(*) FROM public.inventory) AS total_inventories,
  (SELECT count(*) FROM public.physical_card) AS total_physical_cards;
-- [RESULTADO] total_inventories = 3 (A, B, signup de teste — todos
-- reais, nenhum sintético); total_physical_cards = 0 (nenhum resíduo
-- de teste).   [STATUS] PASS

-- ================================================================
-- RESUMO: 23/23 itens funcionais/segurança PASS. Nenhuma falha,
-- nenhuma parada exigida pelas condições de gate de
-- COLLECTIONS-PHYSICAL-INCREMENT-01B.
-- ================================================================
