/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5800 - Validation Queries: Collections Physical Increment 01A (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01 —
               adicionados testes de provisionamento/backfill, provas
               explícitas de escrita negada em ambas as tabelas, e
               isolamento RLS de Inventory)

Descrição...:
Bateria de validação pós-migration para public.inventory e
public.physical_card, cobrindo os 14 itens exigidos em
COLLECTIONS-PHYSICAL-INCREMENT-01A (item 8) e os invariantes listados
em COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01 (Gate 5).

NÃO EXECUTAR nesta rodada — as tabelas/função referenciadas ainda não
existem no banco físico. Este arquivo só pode ser executado após a
aplicação real das Queries 5000-5012.

Convenção usada abaixo: cada bloco é numerado e comentado com o
invariante que valida. Blocos marcados [SQL ESTÁTICO] são queries
diretas, executáveis como estão assim que as tabelas existirem.
Blocos marcados [TESTE FUNCIONAL] exigem duas sessões autenticadas
distintas (usuário A e usuário B) e não podem ser expressos como uma
única query SELECT — descritos como roteiro de teste, não como SQL
pronto para rodar isolado.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- 1. [SQL ESTÁTICO] users_without_inventory = 0
-- ================================================================
SELECT count(*) AS users_without_inventory
FROM auth.users u
WHERE NOT EXISTS (
    SELECT 1 FROM public.inventory i WHERE i.owner_user_id = u.id
);
-- Esperado: 0

-- ================================================================
-- 2. [SQL ESTÁTICO] users_with_multiple_inventories = 0
-- (já impossível por UNIQUE(owner_user_id) — validação confirmatória)
-- ================================================================
SELECT owner_user_id, count(*) AS total
FROM public.inventory
GROUP BY owner_user_id
HAVING count(*) > 1;
-- Esperado: 0 linhas

-- ================================================================
-- 3. [SQL ESTÁTICO] physical_cards_invalid_inventory = 0
-- (já impossível por FK RESTRICT — validação confirmatória)
-- ================================================================
SELECT count(*) AS physical_cards_invalid_inventory
FROM public.physical_card pc
WHERE pc.inventory_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.inventory i WHERE i.id = pc.inventory_id
  );
-- Esperado: 0

-- ================================================================
-- 4. [SQL ESTÁTICO] grants anon = 0 (inventory + physical_card)
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('inventory', 'physical_card')
  AND grantee = 'anon';
-- Esperado: 0 linhas

-- ================================================================
-- 5. [SQL ESTÁTICO] authenticated sem INSERT/UPDATE/DELETE direto
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('inventory', 'physical_card')
  AND grantee = 'authenticated'
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
-- Esperado: 0 linhas (authenticated deve ter só SELECT)

-- ================================================================
-- 6. [TESTE FUNCIONAL] RLS: usuário A não vê Physical Card de B
-- Roteiro:
--   a) autenticar como usuário A, chamar add_physical_cards() com
--      1 item válido -> confirmar 1 linha retornada;
--   b) autenticar como usuário B, executar
--      SELECT * FROM public.physical_card;
--   c) esperado: o registro criado por A não aparece no resultado
--      de B (RLS via subquery de inventory_id ligada ao auth.uid()
--      de B).
-- ================================================================

-- ================================================================
-- 7. [TESTE FUNCIONAL] authenticated sem INSERT direto na tabela
-- Roteiro:
--   autenticado como qualquer usuário, tentar:
--   INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
--   VALUES (...);
--   Esperado: erro de permissão (ausência de GRANT INSERT + ausência
--   de policy de INSERT) — falha antes mesmo de avaliar RLS.
-- ================================================================

-- ================================================================
-- 8. [TESTE FUNCIONAL] RPC só cria no Inventory do próprio auth.uid()
-- Roteiro:
--   autenticado como A, chamar add_physical_cards() e inspecionar o
--   inventory_id das linhas retornadas -> deve ser sempre igual ao id
--   de public.inventory WHERE owner_user_id = A.
-- ================================================================

-- ================================================================
-- 9. [ESTRUTURAL] inventory_id não pode ser forjado
-- A assinatura de add_physical_cards(p_items jsonb) não aceita
-- inventory_id como parâmetro — não há superfície para o cliente
-- especificar o Inventory de destino. Confirmar via:
-- ================================================================
SELECT pg_get_function_identity_arguments(oid) AS assinatura
FROM pg_proc
WHERE proname = 'add_physical_cards' AND pronamespace = 'public'::regnamespace;
-- Esperado: "p_items jsonb" — nenhum parâmetro de inventory_id

-- ================================================================
-- 10. [TESTE FUNCIONAL] batch válido N -> N Physical Cards
-- Roteiro:
--   autenticado como A, chamar:
--   SELECT * FROM public.add_physical_cards(
--     '[{"card_variant_id":"<uuid1>","language_id":"<uuid_lang>"},
--       {"card_variant_id":"<uuid2>","language_id":"<uuid_lang>"}]'::jsonb
--   );
--   Esperado: 2 linhas retornadas, 2 linhas persistidas.
-- ================================================================

-- ================================================================
-- 11. [TESTE FUNCIONAL] duplicate variant+language permitido
-- Roteiro:
--   chamar add_physical_cards() com o mesmo card_variant_id +
--   language_id repetido 2x no array -> esperado: 2 linhas distintas
--   (2 ids diferentes), sem erro de unicidade.
-- ================================================================

-- ================================================================
-- 12. [TESTE FUNCIONAL] batch com item inválido -> 0 inserts
-- Roteiro:
--   chamar add_physical_cards() com 2 itens válidos + 1 com
--   card_variant_id inexistente -> esperado: exceção de violação de
--   FK, 0 linhas persistidas (atomicidade — nenhum dos 3 itens entra).
-- ================================================================

-- ================================================================
-- 13. [SQL ESTÁTICO] batch >500 rejeitado
-- ================================================================
-- SELECT * FROM public.add_physical_cards(
--   (SELECT jsonb_agg(jsonb_build_object(
--       'card_variant_id', gen_random_uuid(),
--       'language_id', gen_random_uuid()))
--    FROM generate_series(1, 501))
-- );
-- Esperado: RAISE EXCEPTION 'lote excede o limite de 500 itens por chamada'
-- (falha antes de qualquer tentativa de INSERT — os UUIDs aleatórios
-- nem precisam ser válidos, a checagem de tamanho ocorre primeiro).

-- ================================================================
-- 14. [SQL ESTÁTICO] batch vazio rejeitado
-- ================================================================
-- SELECT * FROM public.add_physical_cards('[]'::jsonb);
-- Esperado: RAISE EXCEPTION 'p_items não pode ser vazio'

-- ================================================================
-- 15. [SQL ESTÁTICO] payload não-array rejeitado
-- ================================================================
-- SELECT * FROM public.add_physical_cards('{"card_variant_id":"x"}'::jsonb);
-- Esperado: RAISE EXCEPTION 'p_items deve ser um array JSON'

-- ================================================================
-- BLOCOS ADICIONADOS EM COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01
-- ================================================================

-- ================================================================
-- 16. [TESTE FUNCIONAL] Provisionamento: novo User -> exatamente 1
-- Inventory criado automaticamente
-- Roteiro:
--   a) criar um novo usuário (signup real ou, em ambiente de teste,
--      INSERT direto em auth.users) -> capturar o id gerado;
--   b) SELECT count(*) FROM public.inventory WHERE owner_user_id = <novo_id>;
--   Esperado: 1 (nem 0, nem >1) — confirma que a Query 5002
--   (trigger on_auth_user_created_inventory) disparou exatamente uma
--   vez e respeitou o UNIQUE(owner_user_id).
-- ================================================================

-- ================================================================
-- 17. [TESTE FUNCIONAL] Idempotência do backfill/provisionamento
-- consolidado (Query 5002)
-- Roteiro:
--   a) com o banco já provisionado (trigger + backfill aplicados),
--      reexecutar manualmente o bloco de backfill da Query 5002:
--      INSERT INTO public.inventory (owner_user_id)
--      SELECT id FROM auth.users
--      ON CONFLICT (owner_user_id) DO NOTHING;
--   b) verificar count(*) de public.inventory antes e depois;
--   Esperado: nenhuma linha nova inserida na segunda execução, nenhum
--   erro — confirma ON CONFLICT DO NOTHING efetivo tanto para o
--   backfill quanto para reexecuções acidentais do trigger.
-- ================================================================

-- ================================================================
-- 18. [TESTE FUNCIONAL] inventory: INSERT direto negado (authenticated)
-- Roteiro: autenticado como qualquer usuário, tentar:
--   INSERT INTO public.inventory (owner_user_id) VALUES (auth.uid());
--   Esperado: erro de permissão (ausência de GRANT INSERT + ausência
--   de policy de INSERT).
-- ================================================================

-- ================================================================
-- 19. [TESTE FUNCIONAL] inventory: UPDATE direto negado (authenticated)
-- Roteiro: autenticado, tentar:
--   UPDATE public.inventory SET updated_at = now()
--   WHERE owner_user_id = auth.uid();
--   Esperado: erro de permissão (ausência de GRANT UPDATE + ausência
--   de policy de UPDATE).
-- ================================================================

-- ================================================================
-- 20. [TESTE FUNCIONAL] inventory: DELETE direto negado (authenticated)
-- Roteiro: autenticado, tentar:
--   DELETE FROM public.inventory WHERE owner_user_id = auth.uid();
--   Esperado: erro de permissão (ausência de GRANT DELETE + ausência
--   de policy de DELETE).
-- ================================================================

-- ================================================================
-- 21. [TESTE FUNCIONAL] physical_card: UPDATE direto negado (authenticated)
-- Roteiro: autenticado, com um Physical Card já existente no próprio
-- Inventory, tentar:
--   UPDATE public.physical_card SET language_id = '<outro_uuid>'
--   WHERE id = '<id_do_proprio_card>';
--   Esperado: erro de permissão — RPC add_physical_cards() continua
--   sendo a única superfície de escrita; não existe caminho de UPDATE
--   direto nem para o próprio dado do usuário.
-- ================================================================

-- ================================================================
-- 22. [TESTE FUNCIONAL] physical_card: DELETE direto negado (authenticated)
-- Roteiro: autenticado, tentar:
--   DELETE FROM public.physical_card WHERE id = '<id_do_proprio_card>';
--   Esperado: erro de permissão — nenhuma policy de DELETE, nenhum
--   GRANT DELETE para authenticated.
-- ================================================================

-- ================================================================
-- 23. [TESTE FUNCIONAL] RLS: usuário A não vê Inventory de B
-- Roteiro:
--   a) autenticar como usuário B, capturar o id de public.inventory
--      onde owner_user_id = B (via SELECT próprio, permitido);
--   b) autenticar como usuário A, executar:
--      SELECT * FROM public.inventory WHERE id = '<id_do_inventory_de_B>';
--   c) esperado: 0 linhas — a policy inventory_select_own restringe a
--      leitura a owner_user_id = (select auth.uid()), então o
--      Inventory de B nunca aparece para A, mesmo conhecendo o id.
-- ================================================================
