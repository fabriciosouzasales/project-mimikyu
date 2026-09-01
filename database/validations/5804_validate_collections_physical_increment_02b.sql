/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5804 - Validation Results: Collections Physical Increment 02B
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01)

Descrição...:
Resultados reais da bateria de validação pós-migration de
public.collection e das seis RPCs create_collection()/
update_collection_metadata()/set_collection_default_storage()/
archive_collection()/reactivate_collection()/delete_collection(),
executada ao vivo contra o banco, fase por fase (Fases 1-7 do plano de
implementação), imediatamente após a aplicação de cada Query.

Todos os testes que escrevem dado usaram transações sem COMMIT
explícito dentro de uma única chamada execute_sql (BEGIN ... ROLLBACK
na mesma sessão) — nenhuma linha sintética permanece no banco.
Confirmado ao final de cada fase e ao final da rodada: SELECT count(*)
FROM collection = 0, SELECT count(*) FROM storage_container = 0.

Metodologia de simulação de usuário autenticado: dentro de cada
transação de teste, `SELECT set_config('role','authenticated', true)`
+ `SELECT set_config('request.jwt.claim.sub', '<user_id>', true)`
reproduzem o contexto de auth.uid() e RLS de uma sessão real. Usuários
reais usados como Owner A / Owner B: contas já existentes no projeto
(não sintéticas) — nenhum dado de catálogo ou de terceiros foi
alterado.

Dois achados reais durante a execução, corrigidos no mesmo ciclo (ver
cabeçalhos das Queries 5034-5039 para o detalhamento completo de cada
um):
1. `game.is_active` não existe fisicamente — a checagem correspondente
   em create_collection() v1.0 foi removida antes da Fase 2 (decisão
   de Fabrício), e o Caso D original desta bateria ("Game inativo ->
   FAIL") foi removido por não ter mais base física.
2. Referência ambígua `id` (e `lifecycle_status`, em archive/
   reactivate) entre coluna de tabela e parâmetro OUT de
   `RETURNS TABLE`, nunca detectável em CREATE FUNCTION — só apareceu
   na primeira execução real de update_collection_metadata() (Fase 3)
   e foi corrigida preventivamente em set_collection_default_storage()/
   archive_collection()/reactivate_collection()/delete_collection()
   antes de cada uma ser executada pela primeira vez.
3. As duas trigger functions (validate_collection_structural_identity/
   validate_collection_default_storage_owner) nunca tiveram EXECUTE
   revogado de PUBLIC/anon — achado pelo Supabase Advisor na Fase 6,
   corrigido com REVOKE explícito (ver cabeçalhos das Queries 5032/
   5033).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO — todos os casos abaixo PASS.
================================================================
*/

-- ================================================================
-- FASE 1 — Collection Foundation (tabela + 3 triggers) — 7/7 PASS
-- ================================================================
-- [PASS] Owner A + Storage A (mesmo Inventory) -> INSERT aceito.
-- [PASS] Owner A + Storage B (Inventory diferente) -> rejeitado pelo
--   trigger trg_collection_validate_default_storage_owner: "default_
--   storage_container_id não pertence ao Owner da Collection".
-- [PASS] mode <> 'OPEN_CURATION' -> rejeitado por chk_collection_mode.
-- [PASS] visibility <> 'PRIVATE' -> rejeitado por chk_collection_visibility.
-- [PASS] reference_locked_at <> NULL -> rejeitado por chk_collection_
--   reference_locked_at_null.
-- [PASS] UPDATE owner_user_id -> rejeitado pelo trigger trg_collection_
--   validate_structural_identity: "owner_user_id é imutável".
-- [PASS] UPDATE game_id -> rejeitado pelo mesmo trigger: "game_id é
--   imutável".
-- Zero resíduo confirmado (ROLLBACK; collection/storage_container = 0
-- linhas).

-- ================================================================
-- FASE 2 — create_collection() — 5/5 PASS
-- ================================================================
-- [PASS] Owner A + Storage do próprio Inventory -> 1 linha criada,
--   mode='OPEN_CURATION', lifecycle_status='ACTIVE', visibility='PRIVATE'.
-- [PASS] Owner A + Storage de Owner B (cross-owner) -> ERROR
--   'default_storage_container_id does not belong to caller inventory'.
-- [PASS] Game inexistente -> ERROR 'game not found' (mensagem exata
--   confirmada).
-- [PASS] p_name vazio (só espaços) -> ERROR 'p_name não pode ser vazio'.
-- [PASS] auth.uid() NULL (sem JWT) -> ERROR 'authentication required'.
-- Zero resíduo confirmado.

-- ================================================================
-- FASE 3 — update_collection_metadata() / set_collection_default_
-- storage() — 6/6 PASS
-- ================================================================
-- [PASS] Collection ACTIVE -> update_collection_metadata() aceito,
--   name atualizado.
-- [PASS] Collection ACTIVE -> set_collection_default_storage() aceito,
--   default_storage_container_id atualizado.
-- [PASS] Storage de outro Owner -> ERROR 'storage container does not
--   belong to caller inventory' (mesma Collection ACTIVE).
-- [PASS] Collection ARCHIVED (arquivada diretamente para isolar o
--   teste) -> update_collection_metadata() ERROR 'collection is
--   archived — reactivate before editing metadata'.
-- [PASS] Collection ARCHIVED -> set_collection_default_storage()
--   ERROR 'collection is archived — reactivate before editing default
--   storage'.
-- [PASS] updated_at da Collection ARCHIVED permanece idêntico antes/
--   depois de uma tentativa negada (nenhuma escrita ocorreu).
-- Zero resíduo confirmado.

-- ================================================================
-- FASE 4 — archive_collection() / reactivate_collection() — 4/4 PASS
-- ================================================================
-- [PASS] ACTIVE -> archive_collection() real: lifecycle_status=
--   'ARCHIVED', archived_at capturado (NOT NULL).
-- [PASS] ARCHIVED -> archive_collection() chamado de novo (idempotente):
--   archived_at e updated_at IDÊNTICOS byte-a-byte à chamada anterior —
--   nenhum novo UPDATE ocorreu.
-- [PASS] ARCHIVED -> reactivate_collection() real: lifecycle_status=
--   'ACTIVE', archived_at = NULL.
-- [PASS] ACTIVE -> reactivate_collection() chamado de novo (idempotente):
--   updated_at IDÊNTICO à chamada anterior — nenhum novo UPDATE ocorreu.
-- Zero resíduo confirmado.

-- ================================================================
-- FASE 5 — delete_collection() — 4/4 PASS
-- ================================================================
-- [PASS] Owner B tenta deletar Collection de Owner A -> ERROR
--   'collection not found or not owned by caller'.
-- [PASS] Collection inexistente -> mesmo ERROR.
-- [PASS] Owner A deleta a própria Collection -> aceito, id retornado
--   confere com o id deletado.
-- [PASS] Confirmado por SELECT direto (fora do papel authenticated):
--   0 linhas remanescentes com aquele id.
-- Zero resíduo confirmado.

-- ================================================================
-- FASE 6 — Security / RLS — todos PASS
-- ================================================================
-- [PASS] grants anon em collection = 0 linhas.
-- [PASS] grants authenticated INSERT/UPDATE/DELETE diretos em
--   collection = 0 linhas (só SELECT).
-- [PASS] 6 CHECK constraints confirmadas via pg_constraint com a
--   definição exata esperada.
-- [PASS] 3 triggers confirmados via pg_trigger (updated_at, structural
--   identity, default storage owner).
-- [PASS] EXECUTE das 6 RPCs restrito a authenticated (nenhuma linha
--   para anon/PUBLIC via information_schema.role_routine_grants).
-- [PASS] índice ix_collection_owner_lifecycle existe, (owner_user_id,
--   lifecycle_status).
-- [PASS] nenhuma das 6 RPCs tem mais de 1 overload (pg_proc).
-- [PASS] auditoria textual (pg_get_functiondef): update_collection_
--   metadata()/set_collection_default_storage() contêm o guard
--   lifecycle_status = 'ACTIVE' no corpo compilado; archive_collection()
--   contém ambos os guards ('ACTIVE' no WHERE de escrita, 'ARCHIVED' no
--   texto de idempotência); reactivate_collection() simétrico.
-- [PASS] todas as 6 RPCs + as 2 trigger functions confirmadas
--   SECURITY DEFINER com search_path='' (pg_proc.prosecdef/proconfig).
-- [PASS] Cross-user RLS: Owner B, via SELECT direto, não vê nenhuma
--   linha da Collection de Owner A (count = 0).
-- [PASS] INSERT/UPDATE/DELETE diretos via authenticated (sem RPC) ->
--   ERROR 42501 permission denied for table collection, nos três casos.
-- [PASS] anon: SELECT direto em collection -> ERROR 42501 permission
--   denied. anon chamando create_collection() -> ERROR permission
--   denied for function create_collection.
-- [ACHADO E CORRIGIDO] Supabase Advisor (security) apontou
--   validate_collection_structural_identity() e validate_collection_
--   default_storage_owner() chamáveis diretamente via /rest/v1/rpc/...
--   por anon/authenticated — REVOKE EXECUTE aplicado nas duas; re-teste
--   confirmou que os triggers continuam funcionando normalmente via
--   RPC (create_collection()/set_collection_default_storage() ainda
--   validam owner corretamente) e que a chamada direta agora é negada
--   ("permission denied for function
--   validate_collection_structural_identity").
-- Zero resíduo confirmado em todos os blocos.

-- ================================================================
-- Caso U — concorrência real com duas sessões: NÃO EXECUTADO nesta
-- rodada (esboço preparado no arquivo de proposta original,
-- database/proposals/2026-08-31-02b-collection/5804_...sql) — o tool
-- execute_sql usado nesta implementação é de conexão única por
-- chamada, não reproduz duas sessões concorrentes reais. A prova de
-- idempotência sequencial (Fase 4, casos 2 e 4 acima) é a evidência
-- disponível nesta rodada.
-- ================================================================
