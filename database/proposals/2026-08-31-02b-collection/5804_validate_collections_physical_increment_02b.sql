/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5804 - Validation Queries: Collections Physical Increment 02B (PROPOSTA)
Versão......: 1.3
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-
               FINAL-01, item 4 → -STAGING-REVISION-01, item 5 →
               -IMPLEMENTATION-01, correção pré-Fase 2 — remoção do
               Caso D (game.is_active não existe fisicamente) → Fase 6,
               item 7 novo (EXECUTE de trigger functions revogado))

Descrição...:
Bateria de validação pós-migration para public.collection e as seis
RPCs create_collection()/update_collection_metadata()/
set_collection_default_storage()/archive_collection()/
reactivate_collection()/delete_collection(), cobrindo os invariantes
fixados em COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01 até
-STAGING-REVISION-01.

NÃO EXECUTAR nesta rodada — collection ainda não existe no banco
físico. Este arquivo só pode ser executado após a aplicação real das
Queries 5030-5039.

REVISÃO (COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-REVISION-01, item
5). A versão 1.0 já cobria "ARCHIVED bloqueia edição" (Casos J/K) e
"archive/reactivate repetido não gera erro" (Casos L/M), mas com
asserções fracas — não capturavam nem comparavam os valores exatos de
archived_at/updated_at entre a primeira chamada real e as chamadas
idempotentes seguintes, que é exatamente o que a correção de
concorrência de 5035-5038 precisa provar. Casos novos adicionados:
Caso R (PASS explícito em ACTIVE, contraponto de J), Caso S (PASS
explícito em ACTIVE, contraponto de K), e L/M reescritos para exigir
captura e comparação literal de archived_at/updated_at. Caso T (SQL
ESTÁTICO) audita que as quatro RPCs de escrita têm o guard de
lifecycle_status no texto do próprio UPDATE. Caso U esboça (sem
executar) um teste de concorrência real com duas sessões.

Mesma convenção de 5802: blocos [SQL ESTÁTICO] são queries diretas
sobre catálogo (information_schema/pg_constraint/pg_proc); blocos
[TESTE FUNCIONAL] exigem sessões autenticadas distintas (simuladas via
set_config('role','authenticated', true) +
set_config('request.jwt.claim.sub', '<uuid>', true), técnica já
validada em 5802) e são descritos como roteiro; blocos [ESTRUTURAL]
validam diretamente o comportamento de constraints/triggers via
tentativa de escrita real.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- 1. [SQL ESTÁTICO] grants anon = 0 (collection)
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'collection'
  AND grantee = 'anon';
-- Esperado: 0 linhas

-- ================================================================
-- 2. [SQL ESTÁTICO] authenticated sem INSERT/UPDATE/DELETE direto em
-- collection
-- ================================================================
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'collection'
  AND grantee = 'authenticated'
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
-- Esperado: 0 linhas (authenticated deve ter só SELECT)

-- ================================================================
-- 3. [SQL ESTÁTICO] confirmar as 6 CHECK constraints de collection
-- ================================================================
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.collection'::regclass
  AND contype = 'c'
ORDER BY conname;
-- Esperado: 6 linhas — chk_collection_mode ('OPEN_CURATION'),
-- chk_collection_lifecycle_status ('ACTIVE','ARCHIVED'),
-- chk_collection_visibility ('PRIVATE'),
-- chk_collection_name_not_blank (btrim(name) <> ''),
-- chk_collection_archived_at_consistency (par condicional),
-- chk_collection_reference_locked_at_null (IS NULL)

-- ================================================================
-- 4. [SQL ESTÁTICO] confirmar os dois triggers BEFORE em collection
-- ================================================================
SELECT tgname, pg_get_triggerdef(oid) AS definicao
FROM pg_trigger
WHERE tgrelid = 'public.collection'::regclass
  AND NOT tgisinternal
ORDER BY tgname;
-- Esperado: 3 linhas — trg_collection_set_updated_at (BEFORE UPDATE),
-- trg_collection_validate_structural_identity (BEFORE UPDATE),
-- trg_collection_validate_default_storage_owner
-- (BEFORE INSERT OR UPDATE OF default_storage_container_id)

-- ================================================================
-- 5. [SQL ESTÁTICO] EXECUTE das 6 RPCs restrito a authenticated
-- ================================================================
SELECT p.proname, r.routine_name, g.grantee, g.privilege_type
FROM information_schema.role_routine_grants g
JOIN pg_proc p ON p.proname = g.routine_name
JOIN information_schema.routines r ON r.routine_name = g.routine_name
WHERE g.routine_schema = 'public'
  AND g.routine_name IN (
      'create_collection', 'update_collection_metadata',
      'set_collection_default_storage', 'archive_collection',
      'reactivate_collection', 'delete_collection'
  );
-- Esperado: 6 linhas, todas grantee = 'authenticated',
-- privilege_type = 'EXECUTE'; nenhuma linha para 'anon'/'PUBLIC'

-- ================================================================
-- 6. [SQL ESTÁTICO] índice de listagem existe e é usável
-- ================================================================
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'collection'
  AND indexname = 'ix_collection_owner_lifecycle';
-- Esperado: 1 linha, (owner_user_id, lifecycle_status)

-- ================================================================
-- 7. [SQL ESTÁTICO] EXECUTE das funções de trigger revogado de
-- PUBLIC/anon/authenticated (COLLECTIONS-PHYSICAL-INCREMENT-02B-
-- IMPLEMENTATION-01, Fase 6 — achado real do Supabase Advisor: v1.0
-- de 5032/5033 nunca revogava EXECUTE, deixando as duas trigger
-- functions chamáveis diretamente via /rest/v1/rpc/... por anon e
-- authenticated, fora do contexto de trigger)
-- ================================================================
SELECT p.proname, g.grantee, g.privilege_type
FROM information_schema.role_routine_grants g
JOIN pg_proc p ON p.proname = g.routine_name
WHERE g.routine_schema = 'public'
  AND g.routine_name IN (
      'validate_collection_structural_identity',
      'validate_collection_default_storage_owner'
  );
-- Esperado: 0 linhas (EXECUTE revogado de todas as roles; o disparo
-- via CREATE TRIGGER não depende de EXECUTE concedido a nenhuma role)

-- ================================================================
-- Caso A — [TESTE FUNCIONAL] Owner A + Storage do próprio Inventory
-- de A -> create_collection() PASS
-- ================================================================
-- Como authenticated/Owner A: SELECT * FROM public.create_collection(
--     <game_id_valido>, 'Coleção Teste A', 'desc', <storage_de_A>);
-- Esperado: 1 linha, mode='OPEN_CURATION', lifecycle_status='ACTIVE',
-- visibility='PRIVATE'

-- ================================================================
-- Caso B — [TESTE FUNCIONAL] Owner A + Storage de Owner B (outro
-- Inventory) -> create_collection() FAIL
-- ================================================================
-- Como authenticated/Owner A: SELECT * FROM public.create_collection(
--     <game_id_valido>, 'Coleção Teste B', 'desc', <storage_de_B>);
-- Esperado: ERROR 'default_storage_container_id does not belong to
-- caller inventory'

-- ================================================================
-- Caso C — [TESTE FUNCIONAL] Game inexistente -> create_collection()
-- FAIL
-- ================================================================
-- SELECT * FROM public.create_collection(gen_random_uuid(), 'X', NULL,
--     <storage_de_A>);
-- Esperado: ERROR 'game not found'

-- ================================================================
-- Caso D — REMOVIDO (COLLECTIONS-PHYSICAL-INCREMENT-02B-
-- IMPLEMENTATION-01, correção pré-Fase 2). Testava "Game com
-- is_active = false -> create_collection() FAIL", mas public.game não
-- tem fisicamente coluna is_active — a checagem correspondente foi
-- removida de create_collection() (Query 5034 v1.1). Não existe mais
-- noção de Game ativo/inativo neste incremento; a garantia estrutural
-- de fundo (game_id deve existir) permanece coberta pelo Caso C acima
-- e pela FK collection.game_id -> game.id.
-- ================================================================
-- Caso E — [ESTRUTURAL] UPDATE direto tentando alterar owner_user_id
-- -> FAIL (trg_collection_validate_structural_identity)
-- ================================================================
-- UPDATE public.collection SET owner_user_id = <outro_uuid>
-- WHERE id = <collection_de_teste>;
-- Esperado: ERROR 'owner_user_id é imutável'

-- ================================================================
-- Caso F — [ESTRUTURAL] UPDATE direto tentando alterar game_id ->
-- FAIL (trg_collection_validate_structural_identity)
-- ================================================================
-- UPDATE public.collection SET game_id = <outro_game_id>
-- WHERE id = <collection_de_teste>;
-- Esperado: ERROR 'game_id é imutável'

-- ================================================================
-- Caso G — [ESTRUTURAL] INSERT direto com mode <> 'OPEN_CURATION' ->
-- FAIL (chk_collection_mode)
-- ================================================================
-- INSERT INTO public.collection (owner_user_id, game_id, name,
-- default_storage_container_id, mode) VALUES (..., 'REFERENCE_BASED');
-- Esperado: ERROR violates check constraint "chk_collection_mode"

-- ================================================================
-- Caso H — [ESTRUTURAL] INSERT/UPDATE com visibility <> 'PRIVATE' ->
-- FAIL (chk_collection_visibility)
-- ================================================================
-- UPDATE public.collection SET visibility = 'PUBLIC'
-- WHERE id = <collection_de_teste>;
-- Esperado: ERROR violates check constraint "chk_collection_visibility"

-- ================================================================
-- Caso I — [ESTRUTURAL] INSERT/UPDATE com reference_locked_at NOT
-- NULL -> FAIL (chk_collection_reference_locked_at_null)
-- ================================================================
-- UPDATE public.collection SET reference_locked_at = NOW()
-- WHERE id = <collection_de_teste>;
-- Esperado: ERROR violates check constraint
-- "chk_collection_reference_locked_at_null"

-- ================================================================
-- Caso R — [TESTE FUNCIONAL] update_collection_metadata() em
-- Collection ACTIVE -> PASS (contraponto de J)
-- ================================================================
-- (Collection de teste recém-criada, ainda ACTIVE)
-- SELECT * FROM public.update_collection_metadata(<id>, 'Novo Nome',
--     NULL);
-- Esperado: 1 linha, name = 'Novo Nome', updated_at avançou em relação
-- ao created_at

-- ================================================================
-- Caso J — [TESTE FUNCIONAL] update_collection_metadata() em
-- Collection ARCHIVED -> FAIL
-- ================================================================
-- (arquivar a Collection de teste via archive_collection() primeiro)
-- SELECT * FROM public.update_collection_metadata(<id>, 'Novo Nome',
--     NULL);
-- Esperado: ERROR 'collection is archived — reactivate before editing
-- metadata'; nenhuma linha de collection foi alterada (conferir via
-- SELECT direto que name/updated_at permanecem os de antes da
-- tentativa)

-- ================================================================
-- Caso S — [TESTE FUNCIONAL] set_collection_default_storage() em
-- Collection ACTIVE -> PASS (contraponto de K)
-- ================================================================
-- (Collection de teste ACTIVE, Storage alternativo do mesmo Inventory
-- de A)
-- SELECT * FROM public.set_collection_default_storage(<id>,
--     <outro_storage_de_A>);
-- Esperado: 1 linha, default_storage_container_id = <outro_storage_de_A>

-- ================================================================
-- Caso K — [TESTE FUNCIONAL] set_collection_default_storage() em
-- Collection ARCHIVED -> FAIL
-- ================================================================
-- SELECT * FROM public.set_collection_default_storage(<id>,
--     <outro_storage_de_A>);
-- Esperado: ERROR 'collection is archived — reactivate before editing
-- default storage'; nenhuma linha de collection foi alterada

-- ================================================================
-- Caso L — [TESTE FUNCIONAL] archive_collection() chamado duas vezes
-- -> segunda chamada PASS idempotente, archived_at/updated_at
-- preservados byte-a-byte (COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-
-- REVISION-01, item 5 — assertividade reforçada em relação à v1.0)
-- ================================================================
-- Roteiro:
--   1. SELECT lifecycle_status, archived_at, updated_at
--      FROM public.collection WHERE id = <id>; -- deve ser ACTIVE,
--      archived_at IS NULL (estado pré-condição)
--   2. r1 := SELECT * FROM public.archive_collection(<id>); -- 1ª
--      chamada real: lifecycle_status='ARCHIVED', archived_at = t1
--      (não-nulo)
--   3. u1 := SELECT updated_at FROM public.collection WHERE id = <id>;
--      -- captura updated_at logo após a 1ª chamada
--   4. r2 := SELECT * FROM public.archive_collection(<id>); -- 2ª
--      chamada (idempotente)
--   5. u2 := SELECT updated_at FROM public.collection WHERE id = <id>;
-- Esperado: r2.archived_at = r1.archived_at (mesmo valor exato, não
-- apenas "não-nulo"); u2 = u1 (updated_at não muda numa chamada
-- idempotente, porque não houve novo UPDATE — o trigger
-- trg_collection_set_updated_at só dispara em UPDATE de fato)

-- ================================================================
-- Caso M — [TESTE FUNCIONAL] reactivate_collection() chamado duas
-- vezes -> segunda chamada PASS idempotente, updated_at preservado
-- byte-a-byte (mesmo reforço de asserção do Caso L, espelhado)
-- ================================================================
-- Roteiro (a partir de uma Collection já ARCHIVED, ex. resultado do
-- Caso L):
--   1. r1 := SELECT * FROM public.reactivate_collection(<id>); -- 1ª
--      chamada real: lifecycle_status='ACTIVE', archived_at IS NULL
--   2. u1 := SELECT updated_at FROM public.collection WHERE id = <id>;
--   3. r2 := SELECT * FROM public.reactivate_collection(<id>); -- 2ª
--      chamada (idempotente)
--   4. u2 := SELECT updated_at FROM public.collection WHERE id = <id>;
-- Esperado: r1.archived_at IS NULL e r2.archived_at IS NULL (ambas);
-- u2 = u1 (updated_at não muda na chamada idempotente)

-- ================================================================
-- Caso T — [SQL ESTÁTICO] auditoria textual: as quatro RPCs de escrita
-- de lifecycle/config têm o guard de lifecycle_status no próprio
-- UPDATE (não em um SELECT anterior separado) — prova estrutural de
-- que a correção de concorrência (Queries 5035-5038) está de fato no
-- texto compilado da função, não só na intenção do comentário
-- ================================================================
-- SELECT p.proname,
--        pg_get_functiondef(p.oid) LIKE '%lifecycle_status = ''ACTIVE''%'
--            AS has_active_guard,
--        pg_get_functiondef(p.oid) LIKE '%lifecycle_status = ''ARCHIVED''%'
--            AS has_archived_guard
-- FROM pg_proc p
-- WHERE p.proname IN (
--     'update_collection_metadata', 'set_collection_default_storage',
--     'archive_collection', 'reactivate_collection'
-- );
-- Esperado: update_collection_metadata e set_collection_default_storage
-- com has_active_guard = true; archive_collection com has_active_guard
-- = true (transição parte de ACTIVE); reactivate_collection com
-- has_archived_guard = true (transição parte de ARCHIVED). Isto por si
-- só não prova que o guard está no WHERE do UPDATE correto (a busca é
-- textual, não estrutural) — serve como rede de segurança contra
-- regressão óbvia (ex. alguém reintroduzir um SELECT-then-UPDATE sem
-- guard no UPDATE), não como prova formal de atomicidade.

-- ================================================================
-- Caso U — [TESTE FUNCIONAL, ESBOÇO — NÃO EXECUTAR] concorrência real
-- de duas sessões chamando archive_collection() na mesma Collection
-- ACTIVE simultaneamente (preparado por pedido explícito da rodada
-- COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-REVISION-01, item 5;
-- não executado nesta rodada — requer duas conexões reais e
-- coordenação de timing que o tool execute_sql, de conexão única por
-- chamada, não reproduz sozinho)
-- ================================================================
-- Roteiro pretendido (fora do escopo de execução desta rodada):
--   1. Sessão 1: BEGIN; SELECT * FROM public.archive_collection(<id>)
--      FOR UPDATE-like lock implícito do próprio UPDATE interno; NÃO
--      COMMIT ainda (segurar a transação aberta).
--   2. Sessão 2 (conexão separada, concorrente): SELECT * FROM
--      public.archive_collection(<id>); -- deve bloquear até a Sessão
--      1 commitar (lock de linha do UPDATE), não retornar erro.
--   3. Sessão 1: COMMIT.
--   4. Sessão 2: deve destravar e retornar o estado idempotente (mesmo
--      archived_at da Sessão 1, sem novo UPDATE) — não uma segunda
--      escrita.
-- Esperado (quando executado com infraestrutura de duas conexões):
-- exatamente uma das duas chamadas realiza a transição real; a outra
-- retorna o mesmo archived_at, comprovando "só uma chamada pode
-- realizar ACTIVE -> ARCHIVED" mesmo sob concorrência real, não só sob
-- chamadas sequenciais na mesma sessão (que é tudo que os Casos L/M
-- conseguem provar com o tooling atual).

-- ================================================================
-- Caso N — [TESTE FUNCIONAL] cross-user RLS — Owner B não vê
-- Collection de Owner A
-- ================================================================
-- Como authenticated/Owner B:
-- SELECT count(*) FROM public.collection WHERE id = <collection_de_A>;
-- Esperado: 0

-- ================================================================
-- Caso O — [ESTRUTURAL] escrita direta (INSERT/UPDATE/DELETE) via
-- authenticated, sem RPC -> FAIL
-- ================================================================
-- Como authenticated: INSERT INTO public.collection (...) VALUES (...);
-- Esperado: ERROR 42501 permission denied for table collection

-- ================================================================
-- Caso P — [ESTRUTURAL] anon sem acesso a collection
-- ================================================================
-- Como anon: SELECT * FROM public.collection LIMIT 1;
-- Esperado: ERROR 42501 permission denied for table collection

-- ================================================================
-- Caso Q — [SQL ESTÁTICO] confirmar ausência de overload/assinatura
-- extra nas 6 RPCs (uma função por nome)
-- ================================================================
SELECT proname, count(*)
FROM pg_proc
WHERE proname IN (
    'create_collection', 'update_collection_metadata',
    'set_collection_default_storage', 'archive_collection',
    'reactivate_collection', 'delete_collection'
)
GROUP BY proname
HAVING count(*) <> 1;
-- Esperado: 0 linhas (nenhuma função com mais de 1 overload)
