/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5802 - Validation Results: Collections Physical Increment 02A
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01)

Descrição...:
Resultados reais da bateria de validação pós-migration de
storage_container, physical_card.storage_container_id e as RPCs
create_storage_container()/set_physical_cards_storage(), executada ao
vivo contra o banco após a aplicação de 5020-5024. Todos os testes que
escrevem dado usaram transações sem COMMIT (cada chamada via
execute_sql é sua própria conexão/sessão — confirmado experimentalmente
que uma transação sem COMMIT explícito é descartada quando a conexão
termina, equivalente a ROLLBACK) — nenhuma linha sintética permanece no
banco. Confirmado ao final: SELECT count(*) FROM storage_container = 0,
SELECT count(*) FROM physical_card = 0.

Metodologia de simulação de usuário autenticado: dentro de cada
transação de teste, `SELECT set_config('role','authenticated', true)`
+ `SELECT set_config('request.jwt.claim.sub', '<user_id>', true)`
reproduzem o contexto de auth.uid() e RLS de uma sessão real, sem
depender de sessão HTTP/JWT verdadeira. Usuários reais usados como
Owner A / Owner B nos testes de isolamento: contas já existentes no
projeto (não sintéticas) — nenhum dado de catálogo ou de terceiros foi
alterado, apenas linhas de teste em storage_container/physical_card,
todas revertidas.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO — 19 itens, todos PASS.
================================================================
*/

-- 1. [PASS] grants anon = 0 em storage_container.
-- 2. [PASS] authenticated sem INSERT/UPDATE/DELETE direto em storage_container
--    (0 linhas em information_schema.role_table_grants para esses privilégios).
-- 3. [PASS] fk_physical_card_storage_same_inventory e
--    chk_physical_card_storage_requires_inventory confirmadas via
--    pg_constraint, com a definição exata esperada.
-- 4. [PASS] uq_storage_container_id_inventory confirmada via pg_constraint.

-- 5. [PASS] Caso A — Physical Card do Inventory A + Storage Container do
--    mesmo Inventory A: UPDATE aceito.
-- 6. [PASS] Caso B — Physical Card do Inventory A + Storage Container do
--    Inventory B: rejeitado —
--    ERROR 23503 violates foreign key constraint
--    "fk_physical_card_storage_same_inventory".
-- 7. [PASS] Caso C — storage_container_id NULL: aceito, independente de
--    inventory_id.
-- 8. [PASS] Caso D — Physical Card já com Storage do Inventory A, tentativa
--    de UPDATE inventory_id para B mantendo o mesmo storage_container_id:
--    rejeitado — mesmo erro de FK do Caso B (chave composta
--    (storage_A, inventory_B) não existe em storage_container).
-- 9. [PASS] Caso E (identificado durante a validação, não solicitado
--    explicitamente, fechando a lacuna de MATCH SIMPLE) — Physical Card
--    com storage_container_id preenchido + tentativa de UPDATE
--    inventory_id para NULL: rejeitado —
--    ERROR 23514 violates check constraint
--    "chk_physical_card_storage_requires_inventory" (via CHECK, não via
--    FK — confirma que os dois mecanismos cobrem casos complementares).

-- 10. [PASS] Caso F — set_physical_cards_storage(NULL, [id]) sobre um card
--     já em Storage A: retorno com storage_container_id = NULL,
--     persistido.
-- 11. [PASS] Caso G — payload [A, A, B] (A duplicado): retorno com
--     exatamente 2 linhas (A e B, uma vez cada) — confirma
--     array_agg(DISTINCT ...) efetivo antes do UPDATE.
-- 12. [PASS] Caso H — lote com 2 cards do próprio Owner (A) + 1 card de
--     outro User (B): RAISE EXCEPTION 'um ou mais physical_card_ids não
--     pertencem ao inventory do chamador'; confirmado em seguida que
--     ZERO cards de A foram alterados (não 2 de 3) — atomicidade real,
--     não apenas nos ids inválidos.
--     Nota de metodologia: a primeira tentativa deste caso construiu o
--     array de physical_card_ids via uma subquery executada já sob
--     role='authenticated', que a própria RLS de physical_card filtrou
--     silenciosamente (removendo o id do card de B antes mesmo de
--     chegar à RPC) — produzindo um falso PASS por um motivo diferente
--     do pretendido (o card de B nunca chegou a ser testado). Corrigido
--     capturando os 3 ids como variáveis PL/pgSQL antes da troca de
--     role, garantindo que o array realmente contivesse um id de outro
--     Owner. O reteste confirmou o comportamento correto da RPC.
-- 13. [PASS] Caso I — payload de 501 elementos (poucos ids distintos
--     entre eles, gerados com gen_random_uuid()): RAISE EXCEPTION 'lote
--     excede o limite de 500 itens por chamada' — confirma que o teto é
--     avaliado sobre array_length() do array recebido, ANTES da
--     deduplicação (nenhuma tentativa de checar existência/pertencimento
--     dos ids ocorreu antes dessa rejeição).
-- 14. [PASS] Caso J — Storage Container pertencente ao Inventory de outro
--     User: RAISE EXCEPTION 'storage container does not belong to
--     caller inventory'.

-- 15. [PASS] create_storage_container() cria sempre no Inventory do
--     próprio chamador — matches_own_inventory = true confirmado via
--     JOIN entre o retorno da função e storage_container.inventory_id.
-- 16. [PASS] RLS: usuário B não vê Storage Container criado por A
--     (mesma transação, troca de auth.uid() de A para B) — count = 0.
-- 17. [PASS] INSERT direto em storage_container como authenticated:
--     ERROR 42501 permission denied for table storage_container
--     (hint: GRANT INSERT ON public.storage_container TO authenticated).
-- 18. [PASS] SELECT em storage_container como anon: ERROR 42501
--     permission denied for table storage_container (hint: GRANT SELECT
--     ON public.storage_container TO anon) — confirma ausência total de
--     acesso, não apenas 0 linhas.
-- 19. [PASS] índice ix_physical_card_storage_container existe (via
--     pg_indexes) e foi de fato escolhido pelo planner (Index Scan) na
--     validação de performance — ver 5803.
