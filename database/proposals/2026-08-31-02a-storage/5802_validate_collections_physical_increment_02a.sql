/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5802 - Validation Queries: Collections Physical Increment 02A (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em
               COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01 —
               renomeado assign_physical_cards_to_storage() para
               set_physical_cards_storage() em todos os itens
               afetados; adicionados casos F/G/H)

Descrição...:
Bateria de validação pós-migration para public.storage_container,
physical_card.storage_container_id e as RPCs
create_storage_container()/set_physical_cards_storage(), cobrindo os
invariantes de COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01 (itens 1 e 2
— validade e semântica da FK composta, casos A/B/C/D + caso E) e de
COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01 (semântica de
NULL para limpar Storage corrente, deduplicação de IDs no bulk, e
rejeição atômica de lote misto Owner/não-Owner — casos F/G/H).

NÃO EXECUTAR nesta rodada — storage_container ainda não existe no
banco físico. Este arquivo só pode ser executado após a aplicação real
das Queries 5020-5024.

Mesma convenção de 5800: blocos [SQL ESTÁTICO] são queries diretas;
blocos [TESTE FUNCIONAL] exigem sessões autenticadas distintas e são
descritos como roteiro; blocos [ESTRUTURAL] validam diretamente o
comportamento de constraints/RPC via tentativa de escrita.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- 1. [SQL ESTÁTICO] grants anon = 0 (storage_container)
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'storage_container'
  AND grantee = 'anon';
-- Esperado: 0 linhas

-- ================================================================
-- 2. [SQL ESTÁTICO] authenticated sem INSERT/UPDATE/DELETE direto em
-- storage_container
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'storage_container'
  AND grantee = 'authenticated'
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
-- Esperado: 0 linhas (authenticated deve ter só SELECT)

-- ================================================================
-- 3. [SQL ESTÁTICO] confirmar existência da FK composta e do CHECK
-- ================================================================
SELECT conname, contype, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.physical_card'::regclass
  AND conname IN ('fk_physical_card_storage_same_inventory',
                   'chk_physical_card_storage_requires_inventory');
-- Esperado: 2 linhas — 1 'f' (foreign key) com
-- FOREIGN KEY (storage_container_id, inventory_id) REFERENCES
-- storage_container(id, inventory_id); 1 'c' (check) com
-- CHECK (storage_container_id IS NULL OR inventory_id IS NOT NULL)

-- ================================================================
-- 4. [SQL ESTÁTICO] confirmar UNIQUE(id, inventory_id) em
-- storage_container
-- ================================================================
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.storage_container'::regclass
  AND conname = 'uq_storage_container_id_inventory';
-- Esperado: 1 linha, UNIQUE (id, inventory_id)

-- ================================================================
-- 5. [ESTRUTURAL] Caso A — mesmo Inventory -> PASS
-- Roteiro: com um Storage Container e um Physical Card do MESMO
-- Inventory, executar:
--   UPDATE public.physical_card
--   SET storage_container_id = '<id_do_storage_do_mesmo_inventory>'
--   WHERE id = '<id_do_physical_card>';
-- Esperado: sucesso, 1 linha afetada.
-- ================================================================

-- ================================================================
-- 6. [ESTRUTURAL] Caso B — Inventory diferente -> FAIL
-- Roteiro: com um Storage Container do Inventory B e um Physical Card
-- do Inventory A (A ≠ B), executar:
--   UPDATE public.physical_card
--   SET storage_container_id = '<id_do_storage_do_inventory_B>'
--   WHERE id = '<id_do_physical_card_do_inventory_A>';
-- Esperado: erro de violação de FK
-- (fk_physical_card_storage_same_inventory).
-- ================================================================

-- ================================================================
-- 7. [ESTRUTURAL] Caso C — storage_container_id NULL -> PASS
-- Roteiro: inserir/manter um Physical Card com storage_container_id
-- NULL, independentemente do valor de inventory_id.
-- Esperado: sucesso — MATCH SIMPLE não avalia a FK quando qualquer
-- coluna referenciadora é NULL; o CHECK também não bloqueia.
-- ================================================================

-- ================================================================
-- 8. [ESTRUTURAL] Caso D — mudar inventory_id mantendo Storage de
-- outro Inventory -> FAIL
-- Roteiro: com um Physical Card já associado a um Storage Container
-- do Inventory A, tentar:
--   UPDATE public.physical_card
--   SET inventory_id = '<id_do_inventory_B>'
--   WHERE id = '<id_do_physical_card>'; -- storage_container_id
--                                        -- permanece o de A
-- Esperado: erro de violação de FK. Nota: hoje não existe RPC que
-- altere inventory_id de um Physical Card já existente — este teste
-- só é executável via UPDATE direto de superusuário/service_role em
-- ambiente de teste.
-- ================================================================

-- ================================================================
-- 9. [ESTRUTURAL] Caso E — inventory_id NULL com storage_container_id
-- preenchido -> FAIL, via CHECK (não via FK)
-- Roteiro:
--   UPDATE public.physical_card
--   SET inventory_id = NULL, storage_container_id = '<algum_storage>'
--   WHERE id = '<id_do_physical_card>';
-- Esperado: erro de violação do CHECK
-- chk_physical_card_storage_requires_inventory — cobre exatamente o
-- caso que a FK composta (MATCH SIMPLE) sozinha não fecharia.
-- ================================================================

-- ================================================================
-- 10. [TESTE FUNCIONAL] Caso F — set_physical_cards_storage() com
-- p_storage_container_id NULL limpa Storage corrente -> PASS
-- Roteiro:
--   a) autenticado como A, com um Physical Card já em Storage A
--      (storage_container_id preenchido), chamar:
--      SELECT * FROM public.set_physical_cards_storage(
--          NULL, ARRAY['<id_do_physical_card>']::uuid[]
--      );
--   b) esperado: 1 linha retornada, storage_container_id = NULL;
--      SELECT storage_container_id FROM physical_card WHERE id = '<id>'
--      confirma NULL persistido. Nenhum bloco de verificação de
--      Storage Container é executado (não há container a checar
--      quando o parâmetro é NULL).
-- ================================================================

-- ================================================================
-- 11. [TESTE FUNCIONAL] Caso G — IDs duplicados no payload,
-- [A, A, B] -> A e B afetados exatamente uma vez
-- Roteiro:
--   autenticado como A, com dois Physical Cards próprios (ids "A" e
--   "B"), chamar:
--   SELECT * FROM public.set_physical_cards_storage(
--       '<algum_storage_do_proprio_inventory>',
--       ARRAY['<id_A>','<id_A>','<id_B>']::uuid[]
--   );
--   Esperado: exatamente 2 linhas retornadas (uma para "A", uma para
--   "B") — a deduplicação via array_agg(DISTINCT ...) elimina a
--   repetição antes do UPDATE, então o RETURNING nunca produz uma
--   segunda linha para o mesmo id. Confirmar adicionalmente que o
--   limite de 500 é avaliado sobre o payload recebido (3 elementos
--   neste exemplo, incluindo a repetição), não sobre os 2 ids
--   distintos — testável com um payload de 501 elementos onde apenas
--   poucos ids são distintos (ver item 16, variante consolidada).
-- ================================================================

-- ================================================================
-- 12. [TESTE FUNCIONAL] Caso H — lote com carta do Owner + carta de
-- outro User -> FAIL atômico, nenhuma carta do lote alterada
-- Roteiro:
--   autenticado como A, chamar:
--   SELECT * FROM public.set_physical_cards_storage(
--       '<algum_storage_de_A>',
--       ARRAY['<id_de_A_1>','<id_de_A_2>','<id_de_B>']::uuid[]
--   );
--   Esperado: RAISE EXCEPTION 'um ou mais physical_card_ids não
--   pertencem ao inventory do chamador'; verificar em seguida que
--   NENHUM dos dois Physical Cards de A teve storage_container_id
--   alterado (0 updates no total, não 2 de 3) — a checagem de
--   pertencimento roda por completo, sobre o lote inteiro já
--   deduplicado, antes de qualquer UPDATE.
-- ================================================================

-- ================================================================
-- 13. [TESTE FUNCIONAL] create_storage_container() cria no Inventory
-- do próprio chamador
-- Roteiro:
--   autenticado como A, chamar:
--   SELECT * FROM public.create_storage_container('Binder Vermelho');
--   -> inspecionar storage_container.inventory_id da linha criada;
--   deve ser sempre igual ao id de public.inventory WHERE
--   owner_user_id = A.
-- ================================================================

-- ================================================================
-- 14. [TESTE FUNCIONAL] RLS: usuário A não vê Storage Container de B
-- Roteiro:
--   a) autenticar como B, criar um Storage Container, capturar seu id;
--   b) autenticar como A, executar
--      SELECT * FROM public.storage_container WHERE id = '<id_de_B>';
--   c) esperado: 0 linhas.
-- ================================================================

-- ================================================================
-- 15. [TESTE FUNCIONAL] set_physical_cards_storage() só move/limpa
-- Physical Cards do próprio Inventory do chamador
-- Roteiro:
--   autenticado como A, chamar set_physical_cards_storage() com um
--   storage_container_id de A e uma lista de physical_card_ids todos
--   de A -> esperado: N linhas atualizadas, todas com
--   storage_container_id = o informado.
-- ================================================================

-- ================================================================
-- 16. [TESTE FUNCIONAL] set_physical_cards_storage() rejeita
-- storage_container de outro Inventory
-- Roteiro:
--   autenticado como A, chamar set_physical_cards_storage()
--   informando um storage_container_id que pertence a B -> esperado:
--   RAISE EXCEPTION 'storage container does not belong to caller
--   inventory', 0 updates.
-- ================================================================

-- ================================================================
-- 17. [SQL ESTÁTICO] batch >500 rejeitado (payload recebido, antes da
-- deduplicação — consolida a observação do Caso G)
-- ================================================================
-- SELECT * FROM public.set_physical_cards_storage(
--   '<algum_storage_container_id>',
--   (SELECT array_agg(x) FROM (
--       SELECT '<mesmo_id_A>'::uuid AS x FROM generate_series(1, 500)
--       UNION ALL SELECT '<algum_id_B>'::uuid
--   ) sub)  -- 501 elementos no array recebido, só 2 ids distintos
-- );
-- Esperado: RAISE EXCEPTION 'lote excede o limite de 500 itens por
-- chamada' — a checagem de tamanho roda sobre array_length() do
-- parâmetro recebido, ANTES da deduplicação; o fato de existirem só 2
-- ids distintos entre os 501 elementos não evita a rejeição.

-- ================================================================
-- 18. [SQL ESTÁTICO] índice ix_physical_card_storage_container existe
-- ================================================================
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'physical_card'
  AND indexname = 'ix_physical_card_storage_container';
-- Esperado: 1 linha

-- ================================================================
-- 19. [SQL ESTÁTICO] assinatura de set_physical_cards_storage()
-- confirma p_storage_container_id nulável (sem DEFAULT que mascare a
-- semântica de NULL)
-- ================================================================
SELECT pg_get_function_identity_arguments(oid) AS assinatura
FROM pg_proc
WHERE proname = 'set_physical_cards_storage' AND pronamespace = 'public'::regnamespace;
-- Esperado: "p_storage_container_id uuid, p_physical_card_ids uuid[]"
