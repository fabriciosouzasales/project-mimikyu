/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5806 - Validation Queries: Collections Physical Increment 02C (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
               FINAL-01, item 6 → -STAGING-REVISION-01, item 3 —
               privilege validation explícita + prova de não-
               enumeração)

CORREÇÃO (COLLECTIONS-PHYSICAL-INCREMENT-02C-STAGING-REVISION-01, item
3). Os itens 6/7 da v1.0 provavam ausência de EXECUTE só via
information_schema.role_routine_grants, filtrando por grantee = uma
role específica — isso PROVA que aquela role não tem a linha, mas não
prova de forma explícita que PUBLIC (o pseudo-grantee "todo mundo", que
recebe EXECUTE por padrão em toda função nova, salvo REVOKE explícito)
está de fato revogado, nem lista o que realmente sobra no ACL (que
pode legitimamente incluir o owner/role administrativa que aplicou a
migration — sobra que não deve ser confundida com um vazamento).
Reescritos usando has_function_privilege() (teste direto, por role,
independente de information_schema) combinado com aclexplode(proacl)
(inspeção explícita do ACL completo, incluindo a entrada de grantee=0,
que é como o Postgres representa PUBLIC internamente). Adicionados
também os Casos X/Y/Z — prova funcional de que uma tentativa de
allocate/deallocate/delete sobre Collection alheia produz a mesma
classe de erro independentemente de essa Collection possuir ou não
Collection Allocations (a garantia comportamental correspondente às
correções de 5046/5047/5048 desta mesma rodada).

Descrição...:
Bateria de validação pós-migration para public.collection_allocation,
a extensão de public.collection (started_at), e as duas RPCs
allocate_physical_cards_to_collection()/
deallocate_physical_cards_from_collection(), cobrindo os invariantes
fixados em COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-01 até
-MODELING-FINAL-01.

NÃO EXECUTAR nesta rodada — collection_allocation ainda não existe no
banco físico. Este arquivo só pode ser executado após a aplicação real
das Queries 5040-5048, em uma futura rodada de implementação.

Numeração 5806/5807 (não 5804/5805) deliberada para não colidir com os
arquivos de validação/performance já CONFIRMADO EXECUTADO do
incremento 2B (mesma pasta database/schema, mesmo milhar 5000-5999) —
ver README.md desta pasta para a nota completa de numeração.

Mesma convenção de 5804: blocos [SQL ESTÁTICO] são queries diretas
sobre catálogo (information_schema/pg_constraint/pg_proc/pg_trigger);
blocos [TESTE FUNCIONAL] exigem sessões autenticadas distintas
(simuladas via set_config('role','authenticated', true) +
set_config('request.jwt.claim.sub', '<uuid>', true)) e são descritos
como roteiro; blocos [ESTRUTURAL] validam diretamente o comportamento
de constraints/triggers via tentativa de escrita real.

Casos A-H cobrem especificamente o mecanismo de started_at pedido em
COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-FINAL-01, item 5. Casos
subsequentes (letras seguintes) cobrem os pontos já fechados em
-MODELING-01/-REVISION-01 (C-05 Game matching, Owner×Inventory,
Physical Card sem Inventory, lifecycle, RLS, bulk fail-closed, delete
guard).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- 1. [SQL ESTÁTICO] grants anon = 0 (collection_allocation)
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'collection_allocation'
  AND grantee = 'anon';
-- Esperado: 0 linhas

-- ================================================================
-- 2. [SQL ESTÁTICO] authenticated sem INSERT/UPDATE/DELETE direto em
-- collection_allocation (única via de escrita são as duas RPCs)
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'collection_allocation'
  AND grantee = 'authenticated'
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
-- Esperado: 0 linhas (authenticated deve ter só SELECT)

-- ================================================================
-- 3. [SQL ESTÁTICO] policy RLS collection_allocation_select_own existe
-- ================================================================
SELECT polname, pg_get_expr(polqual, polrelid) AS using_expr
FROM pg_policy
WHERE polrelid = 'public.collection_allocation'::regclass;
-- Esperado: 1 linha, using_expr referenciando
-- collection.owner_user_id = auth.uid() via subquery em collection

-- ================================================================
-- 4. [SQL ESTÁTICO] confirmar chk_collection_started_at_not_before_created
-- em collection
-- ================================================================
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.collection'::regclass
  AND conname = 'chk_collection_started_at_not_before_created';
-- Esperado: 1 linha, CHECK (started_at IS NULL OR started_at >= created_at)

-- ================================================================
-- 5. [SQL ESTÁTICO] confirmar os triggers de collection_allocation
-- ================================================================
SELECT tgname, pg_get_triggerdef(oid) AS definicao
FROM pg_trigger
WHERE tgrelid = 'public.collection_allocation'::regclass
  AND NOT tgisinternal
ORDER BY tgname;
-- Esperado: 4 linhas — trg_collection_allocation_set_updated_at
-- (BEFORE UPDATE), trg_collection_allocation_validate_insert
-- (AFTER INSERT ... REFERENCING NEW TABLE ... FOR EACH STATEMENT),
-- trg_collection_allocation_validate_update (AFTER UPDATE ...
-- REFERENCING NEW TABLE ... FOR EACH STATEMENT),
-- trg_collection_allocation_started_at_insert (AFTER INSERT ...
-- REFERENCING NEW TABLE ... FOR EACH STATEMENT)

-- ================================================================
-- 6. [ESTRUTURAL] EXECUTE das 2 RPCs restrito a authenticated —
-- has_function_privilege() explícito por role (não depende de
-- information_schema, testa a privilege_check real do Postgres,
-- já considerando o que PUBLIC concede por herança)
-- ================================================================
SELECT
    'allocate_physical_cards_to_collection' AS rpc,
    has_function_privilege('anon',
        'public.allocate_physical_cards_to_collection(uuid, uuid[])',
        'EXECUTE') AS anon_pode_executar,
    has_function_privilege('authenticated',
        'public.allocate_physical_cards_to_collection(uuid, uuid[])',
        'EXECUTE') AS authenticated_pode_executar
UNION ALL
SELECT
    'deallocate_physical_cards_from_collection',
    has_function_privilege('anon',
        'public.deallocate_physical_cards_from_collection(uuid, uuid[])',
        'EXECUTE'),
    has_function_privilege('authenticated',
        'public.deallocate_physical_cards_from_collection(uuid, uuid[])',
        'EXECUTE');
-- Esperado: anon_pode_executar = false nas 2 linhas (se PUBLIC ainda
-- tivesse EXECUTE, apareceria aqui como true, mesmo sem grant
-- explícito a anon — has_function_privilege sempre soma o que a role
-- herda de PUBLIC); authenticated_pode_executar = true nas 2 linhas

-- ================================================================
-- 6b. [ESTRUTURAL] ACL completo das 2 RPCs via aclexplode(proacl) —
-- prova direta de que PUBLIC (grantee interno = 0, sem nome de role
-- correspondente) não aparece com EXECUTE em nenhuma das duas
-- ================================================================
SELECT
    p.proname,
    COALESCE(r.rolname, 'PUBLIC') AS grantee,
    acl.privilege_type,
    acl.is_grantable
FROM pg_proc p
CROSS JOIN LATERAL aclexplode(p.proacl) AS acl
LEFT JOIN pg_roles r ON r.oid = acl.grantee
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
      'allocate_physical_cards_to_collection',
      'deallocate_physical_cards_from_collection'
  )
  AND acl.privilege_type = 'EXECUTE'
ORDER BY p.proname, grantee;
-- Esperado: nenhuma linha com grantee = 'PUBLIC'; deve haver uma linha
-- com grantee = 'authenticated'. Pode legitimamente haver uma linha
-- extra para a role que aplicou a migration (dono da função, cujo
-- privilégio pleno o Postgres preserva explicitamente no ACL quando
-- proacl deixa de ser NULL por causa dos REVOKE/GRANT desta Query) —
-- essa linha NÃO é um vazamento, é o dono; confirmar manualmente que
-- nenhuma linha além de 'authenticated' e do dono aparece aqui.

-- ================================================================
-- 7. [ESTRUTURAL] EXECUTE das trigger functions revogado de
-- PUBLIC/anon/authenticated — has_function_privilege() por role
-- (substitui a checagem só-information_schema da v1.0, mesma
-- auditoria já aplicada em 5804, item 7, para o incremento 2B, agora
-- com prova mais forte)
-- ================================================================
SELECT
    'validate_collection_allocation_integrity' AS trigger_function,
    has_function_privilege('anon',
        'public.validate_collection_allocation_integrity()',
        'EXECUTE') AS anon_pode_executar,
    has_function_privilege('authenticated',
        'public.validate_collection_allocation_integrity()',
        'EXECUTE') AS authenticated_pode_executar
UNION ALL
SELECT
    'materialize_collection_started_at',
    has_function_privilege('anon',
        'public.materialize_collection_started_at()', 'EXECUTE'),
    has_function_privilege('authenticated',
        'public.materialize_collection_started_at()', 'EXECUTE');
-- Esperado: false em todas as 4 colunas (nem anon nem authenticated
-- podem chamar as trigger functions diretamente via RPC; elas só
-- executam no contexto interno de CREATE TRIGGER, que não depende de
-- EXECUTE concedido a nenhuma role de aplicação)

-- ================================================================
-- 7b. [ESTRUTURAL] ACL completo das 2 trigger functions via
-- aclexplode(proacl) — mesma prova direta do item 6b, agora exigindo
-- ausência TOTAL de EXECUTE para roles de aplicação (nem authenticated
-- deve aparecer aqui, diferente do item 6b)
-- ================================================================
SELECT
    p.proname,
    COALESCE(r.rolname, 'PUBLIC') AS grantee,
    acl.privilege_type,
    acl.is_grantable
FROM pg_proc p
CROSS JOIN LATERAL aclexplode(p.proacl) AS acl
LEFT JOIN pg_roles r ON r.oid = acl.grantee
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
      'validate_collection_allocation_integrity',
      'materialize_collection_started_at'
  )
  AND acl.privilege_type = 'EXECUTE'
ORDER BY p.proname, grantee;
-- Esperado: nenhuma linha com grantee IN ('PUBLIC', 'anon',
-- 'authenticated'). Só pode legitimamente aparecer o dono/role
-- administrativa (mesma ressalva do item 6b) — confirmar manualmente.

-- ================================================================
-- 8. [SQL ESTÁTICO] índice de listagem por Collection existe
-- ================================================================
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'collection_allocation'
  AND indexname = 'ix_collection_allocation_collection';
-- Esperado: 1 linha, (collection_id)

-- ================================================================
-- 9. [SQL ESTÁTICO] unicidade de physical_card_id (1 Physical Card =
-- no máximo 1 Collection Allocation ativa)
-- ================================================================
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.collection_allocation'::regclass
  AND contype = 'u';
-- Esperado: 1 linha, UNIQUE (physical_card_id)

-- ================================================================
-- Caso A — [ESTRUTURAL] Collection sem nenhuma Collection Allocation,
-- tentativa direta de UPDATE started_at para um valor não-NULL -> FAIL
-- (validate_collection_structural_identity(), Query 5044)
-- ================================================================
-- (Collection de teste recém-criada, started_at IS NULL, zero
-- collection_allocation associadas)
-- UPDATE public.collection SET started_at = NOW()
-- WHERE id = <collection_sem_allocation>;
-- Esperado: ERROR 'started_at não pode ser definido sem nenhuma
-- Collection Allocation existente'

-- ================================================================
-- Caso B — [TESTE FUNCIONAL] primeiro allocate_physical_cards_to_
-- collection() bem-sucedido -> collection.started_at passa de NULL
-- para não-NULL
-- ================================================================
-- Pré-condição: SELECT started_at FROM public.collection WHERE id =
-- <collection_de_teste>; -- IS NULL
-- Como authenticated/Owner A: SELECT * FROM public.
-- allocate_physical_cards_to_collection(<collection_de_teste>,
-- ARRAY[<physical_card_id_1>]);
-- Pós-condição: SELECT started_at FROM public.collection WHERE id =
-- <collection_de_teste>; -- IS NOT NULL
-- Esperado: started_at preenchido automaticamente pela trigger de
-- 5045, sem nenhuma escrita explícita na RPC (5046 não referencia
-- started_at em nenhum ponto do seu corpo — conferir via Caso Q)

-- ================================================================
-- Caso C — [TESTE FUNCIONAL] started_at materializado é exatamente
-- MIN(collection_allocation.created_at) para a Collection
-- ================================================================
-- (a partir do estado deixado pelo Caso B)
-- SELECT c.started_at, (SELECT MIN(ca.created_at) FROM
--     public.collection_allocation ca
--     WHERE ca.collection_id = c.id) AS min_allocated_at
-- FROM public.collection c WHERE c.id = <collection_de_teste>;
-- Esperado: started_at = min_allocated_at, byte-idêntico (mesmo
-- TIMESTAMPTZ, sem diferença de microssegundos)

-- ================================================================
-- Caso D — [TESTE FUNCIONAL] segundo allocate na mesma Collection ->
-- started_at permanece byte-idêntico ao valor do primeiro allocate
-- ================================================================
-- s1 := SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste>; -- valor após o Caso B
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_de_teste>, ARRAY[<physical_card_id_2>]);
-- s2 := SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste>;
-- Esperado: s2 = s1 (started_at não muda — a trigger de 5045 só
-- escreve WHERE started_at IS NULL, e já não é mais NULL)

-- ================================================================
-- Caso E — [TESTE FUNCIONAL] deallocate parcial (remove 1 de 2
-- Physical Cards alocadas) -> started_at preservado
-- ================================================================
-- (a partir do estado deixado pelo Caso D, 2 Physical Cards alocadas)
-- s1 := SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste>;
-- SELECT * FROM public.deallocate_physical_cards_from_collection(
--     <collection_de_teste>, ARRAY[<physical_card_id_1>]);
-- s2 := SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste>;
-- Esperado: s2 = s1 (deallocate nunca escreve em started_at — 5047
-- não referencia a coluna em nenhum ponto)

-- ================================================================
-- Caso F — [TESTE FUNCIONAL] deallocate total (remove a última
-- Physical Card restante, Collection volta a zero Allocations) ->
-- started_at preservado, NÃO volta a NULL
-- ================================================================
-- (a partir do estado deixado pelo Caso E, 1 Physical Card restante)
-- s1 := SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste>;
-- SELECT * FROM public.deallocate_physical_cards_from_collection(
--     <collection_de_teste>, ARRAY[<physical_card_id_2>]);
-- SELECT count(*) FROM public.collection_allocation WHERE
--     collection_id = <collection_de_teste>; -- 0
-- s2 := SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste>;
-- Esperado: s2 = s1, ambos não-NULL (started_at é fato histórico —
-- "esta Collection já teve uma primeira alocação alguma vez" — não
-- reflete o estado atual de composição)

-- ================================================================
-- Caso G — [ESTRUTURAL] tentativa posterior de alterar started_at já
-- definido (para qualquer outro valor, inclusive NULL) -> FAIL
-- (validate_collection_structural_identity(), Query 5044)
-- ================================================================
-- (a partir do estado deixado pelo Caso F, started_at já não-NULL)
-- UPDATE public.collection SET started_at = NOW()
-- WHERE id = <collection_de_teste>;
-- Esperado: ERROR 'started_at é imutável após definido'
-- UPDATE public.collection SET started_at = NULL
-- WHERE id = <collection_de_teste>;
-- Esperado: ERROR 'started_at é imutável após definido' (o guard
-- compara NEW.started_at IS DISTINCT FROM OLD.started_at, cobre
-- também a tentativa de reset para NULL)

-- ================================================================
-- Caso H — [TESTE FUNCIONAL] allocate que falha (ex.: Game
-- incompatível) em uma Collection sem nenhuma Allocation -> nenhuma
-- Collection Allocation é criada e started_at permanece NULL
-- ================================================================
-- (Collection de teste nova, started_at IS NULL, Physical Card de um
-- Game diferente do game_id da Collection)
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_de_teste_2>, ARRAY[<physical_card_de_outro_game>]);
-- Esperado: ERROR 'uma ou mais physical_card_ids não pertencem ao
-- inventory do chamador ou ao Game da Collection'
-- SELECT count(*) FROM public.collection_allocation WHERE
--     collection_id = <collection_de_teste_2>; -- 0
-- SELECT started_at FROM public.collection WHERE id =
--     <collection_de_teste_2>; -- IS NULL (nenhum efeito colateral —
-- a falha na pré-validação da RPC nunca chega a executar o INSERT,
-- então nem a trigger de 5042 nem a de 5045 disparam)

-- ================================================================
-- Caso I — [ESTRUTURAL] Physical Card sem Inventory corrente
-- (physical_card.inventory_id IS NULL) inserida diretamente em
-- collection_allocation (bypass da RPC) -> FAIL (trg_collection_
-- allocation_validate_insert, Query 5042, primeiro check, JOIN-free)
-- ================================================================
-- INSERT INTO public.collection_allocation (physical_card_id,
-- collection_id) VALUES (<physical_card_sem_inventory>,
-- <collection_de_teste>);
-- Esperado: ERROR 'uma ou mais physical_card_ids não possuem
-- Inventory corrente e não podem ser alocadas'

-- ================================================================
-- Caso J — [ESTRUTURAL] Physical Card de outro Owner inserida
-- diretamente em collection_allocation (bypass da RPC) -> FAIL
-- (trg_collection_allocation_validate_insert, segundo check)
-- ================================================================
-- INSERT INTO public.collection_allocation (physical_card_id,
-- collection_id) VALUES (<physical_card_de_owner_B>,
-- <collection_de_owner_A>);
-- Esperado: ERROR 'uma ou mais physical_card_ids não pertencem ao
-- Owner da Collection'

-- ================================================================
-- Caso K — [ESTRUTURAL] Physical Card de Game diferente inserida
-- diretamente em collection_allocation (bypass da RPC) -> FAIL
-- (trg_collection_allocation_validate_insert, terceiro check)
-- ================================================================
-- INSERT INTO public.collection_allocation (physical_card_id,
-- collection_id) VALUES (<physical_card_de_outro_game>,
-- <collection_de_teste>);
-- Esperado: ERROR 'uma ou mais physical_card_ids pertencem a um Game
-- diferente do Game da Collection'

-- ================================================================
-- Caso L — [TESTE FUNCIONAL] allocate em Collection ARCHIVED -> FAIL
-- ================================================================
-- (Collection de teste arquivada via archive_collection() primeiro)
-- SELECT * FROM public.allocate_physical_cards_to_collection(<id>,
--     ARRAY[<physical_card_id>]);
-- Esperado: ERROR 'collection is archived — reactivate before
-- allocating'

-- ================================================================
-- Caso M — [TESTE FUNCIONAL] deallocate em Collection ARCHIVED ->
-- FAIL (C-37 — ARCHIVED bloqueia mudança de composição em ambas as
-- direções)
-- ================================================================
-- (mesma Collection ARCHIVED do Caso L, com Allocations pré-
-- existentes de antes do archive)
-- SELECT * FROM public.deallocate_physical_cards_from_collection(<id>,
--     ARRAY[<physical_card_id>]);
-- Esperado: ERROR 'collection is archived — reactivate before
-- deallocating'

-- ================================================================
-- Caso N — [TESTE FUNCIONAL] cross-user RLS — Owner B não vê
-- Collection Allocation de Owner A
-- ================================================================
-- Como authenticated/Owner B:
-- SELECT count(*) FROM public.collection_allocation WHERE
--     collection_id = <collection_de_A>;
-- Esperado: 0

-- ================================================================
-- Caso O — [TESTE FUNCIONAL] bulk allocate fail-closed: 1 de N
-- physical_card_ids já alocada (a outra Collection) -> ERROR, zero
-- inserções (nenhuma das N-1 restantes é inserida)
-- ================================================================
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_de_teste>, ARRAY[<physical_card_livre_1>,
--     <physical_card_ja_alocada>]);
-- Esperado: ERROR 'uma ou mais physical_card_ids já estão alocadas a
-- uma Collection'
-- SELECT count(*) FROM public.collection_allocation WHERE
--     physical_card_id = <physical_card_livre_1>; -- 0 (não foi
-- inserida apesar de ser válida isoladamente)

-- ================================================================
-- Caso P — [TESTE FUNCIONAL] bulk deallocate fail-closed: 1 de N
-- physical_card_ids não alocada a esta Collection (alocada em outra,
-- ou não alocada) -> ERROR, zero remoções
-- ================================================================
-- SELECT * FROM public.deallocate_physical_cards_from_collection(
--     <collection_de_teste>, ARRAY[<physical_card_alocada_aqui>,
--     <physical_card_alocada_em_outra_collection>]);
-- Esperado: ERROR 'uma ou mais physical_card_ids não estão alocadas a
-- esta Collection'
-- SELECT count(*) FROM public.collection_allocation WHERE
--     physical_card_id = <physical_card_alocada_aqui>; -- 1 (não foi
-- removida apesar de ser válida isoladamente)

-- ================================================================
-- Caso Q — [SQL ESTÁTICO] auditoria textual: allocate_physical_cards_
-- to_collection() não contém nenhuma referência literal a
-- "started_at" no seu corpo compilado — prova de que a remoção do
-- SET started_at = NOW() (COLLECTIONS-PHYSICAL-INCREMENT-02C-
-- MODELING-FINAL-01, item 3) está de fato no texto da função, não só
-- na intenção do comentário
-- ================================================================
-- SELECT pg_get_functiondef(p.oid) LIKE '%started_at%' AS
--     menciona_started_at
-- FROM pg_proc p WHERE p.proname =
--     'allocate_physical_cards_to_collection';
-- Esperado: false (0 ocorrências — nem sequer no texto)

-- ================================================================
-- Caso R — [TESTE FUNCIONAL] delete_collection() com Collection
-- Allocation existente -> FAIL, mensagem NÃO menciona archive
-- ================================================================
-- (Collection de teste com pelo menos 1 Collection Allocation ativa)
-- SELECT * FROM public.delete_collection(<collection_de_teste>);
-- Esperado: ERROR 'collection has allocated physical cards —
-- deallocate them before deleting' (string não contém a palavra
-- "archive"/"arquiv")

-- ================================================================
-- Caso S — [TESTE FUNCIONAL] delete_collection() após deallocate
-- total (zero Allocations) -> PASS
-- ================================================================
-- (a partir do estado do Caso R, após deallocate de todas as
-- Physical Cards restantes)
-- SELECT * FROM public.delete_collection(<collection_de_teste>);
-- Esperado: 1 linha, id = <collection_de_teste> — sucesso

-- ================================================================
-- Caso T — [ESTRUTURAL] tentativa de DELETE direto em collection com
-- Collection Allocation existente (bypass de delete_collection(),
-- via role privilegiada de teste) -> FAIL pela FK RESTRICT declarativa
-- de collection_allocation.collection_id (garantia real, independente
-- do pré-check em nível de RPC — Query 5040)
-- ================================================================
-- DELETE FROM public.collection WHERE id = <collection_com_allocation>;
-- Esperado: ERROR update or delete on table "collection" violates
-- foreign key constraint on table "collection_allocation"

-- ================================================================
-- Caso U — [TESTE FUNCIONAL] teto de 500 avaliado antes da
-- deduplicação (array com 501 elementos, mesmo que com repetições que
-- reduziriam a menos de 500 distintos) -> FAIL
-- ================================================================
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_de_teste>, (SELECT array_agg(<mesmo_id>) FROM
--     generate_series(1, 501)));
-- Esperado: ERROR 'lote excede o limite de 500 itens por chamada'
-- (rejeitado pelo array_length bruto, antes de qualquer
-- array_agg(DISTINCT ...))

-- ================================================================
-- Caso V — [TESTE FUNCIONAL] dedup: array com o mesmo physical_card_id
-- repetido N vezes -> allocate resulta em exatamente 1 Collection
-- Allocation, não N
-- ================================================================
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_de_teste>, ARRAY[<physical_card_id>,
--     <physical_card_id>, <physical_card_id>]);
-- Esperado: 1 linha de retorno
-- SELECT count(*) FROM public.collection_allocation WHERE
--     physical_card_id = <physical_card_id>; -- 1

-- ================================================================
-- Caso W — [SQL ESTÁTICO] confirmar ausência de overload/assinatura
-- extra nas 2 RPCs (uma função por nome)
-- ================================================================
SELECT proname, count(*)
FROM pg_proc
WHERE proname IN (
    'allocate_physical_cards_to_collection',
    'deallocate_physical_cards_from_collection'
)
GROUP BY proname
HAVING count(*) <> 1;
-- Esperado: 0 linhas (nenhuma função com mais de 1 overload)

-- ================================================================
-- Caso X — [TESTE FUNCIONAL] prova de não-enumeração — allocate_
-- physical_cards_to_collection() sobre Collection de outro Owner
-- (COLLECTIONS-PHYSICAL-INCREMENT-02C-STAGING-REVISION-01, item 1/4)
-- ================================================================
-- (duas Collections de Owner A: <collection_a_vazia>, sem nenhuma
-- Collection Allocation, e <collection_a_com_allocations>, com pelo
-- menos 1)
-- Como authenticated/Owner B:
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_a_vazia>, ARRAY[<qualquer_physical_card_id>]);
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     <collection_a_com_allocations>, ARRAY[<qualquer_physical_card_id>]);
-- SELECT * FROM public.allocate_physical_cards_to_collection(
--     gen_random_uuid(), ARRAY[<qualquer_physical_card_id>]);
-- Esperado: as 3 chamadas retornam exatamente a mesma mensagem
-- ('collection not found or not owned by caller') — Owner B não
-- consegue distinguir "Collection de A vazia" de "Collection de A com
-- cards" de "Collection inexistente" pela resposta recebida

-- ================================================================
-- Caso Y — [TESTE FUNCIONAL] prova de não-enumeração — deallocate_
-- physical_cards_from_collection() sobre Collection de outro Owner
-- ================================================================
-- Como authenticated/Owner B, mesmas 3 Collections do Caso X:
-- SELECT * FROM public.deallocate_physical_cards_from_collection(
--     <collection_a_vazia>, ARRAY[<qualquer_physical_card_id>]);
-- SELECT * FROM public.deallocate_physical_cards_from_collection(
--     <collection_a_com_allocations>, ARRAY[<qualquer_physical_card_id>]);
-- SELECT * FROM public.deallocate_physical_cards_from_collection(
--     gen_random_uuid(), ARRAY[<qualquer_physical_card_id>]);
-- Esperado: as 3 chamadas retornam exatamente a mesma mensagem
-- ('collection not found or not owned by caller')

-- ================================================================
-- Caso Z — [TESTE FUNCIONAL] prova de não-enumeração — delete_
-- collection() sobre Collection de outro Owner, com e sem Allocations
-- (a checagem mais sensível — a v1.2 vazava exatamente esta
-- distinção; ver correção descrita no cabeçalho de 5048)
-- ================================================================
-- Como authenticated/Owner B, mesmas 3 Collections do Caso X:
-- SELECT * FROM public.delete_collection(<collection_a_vazia>);
-- SELECT * FROM public.delete_collection(<collection_a_com_allocations>);
-- SELECT * FROM public.delete_collection(gen_random_uuid());
-- Esperado: as 3 chamadas retornam exatamente a mesma mensagem
-- ('collection not found or not owned by caller') — em nenhum caso
-- Owner B recebe a mensagem 'collection has allocated physical cards
-- — deallocate them before deleting', que só pode ocorrer quando o
-- PERFORM ... FOR UPDATE inicial já confirmou que o caller é dono da
-- Collection (comparar com o Caso R, onde o próprio Owner A recebe
-- essa mensagem sobre a própria Collection)
