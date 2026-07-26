/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2808 - Validate Game Delete
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação estrutural e funcional da emenda de exclusão real de
Game (ADR-023, 2026-07-26): constraints atualizadas (Query 2041)
e admin_delete_game() (Query 2042).
================================================================
*/

-- 1. Constraints de catalog_admin_action_log incluem GAME_DELETED
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
  AND conname IN ('ck_catalog_admin_action_log_action_valid', 'ck_catalog_admin_action_log_action_entity_match');

-- 2. Estrutura de admin_delete_game()
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_delete_game';

-- 3. Privilégios
SELECT
    has_function_privilege('anon', 'public.admin_delete_game(uuid)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_delete_game(uuid)', 'EXECUTE') AS auth_execute;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
--
-- Estrutural: as duas constraints passaram a incluir 'GAME_DELETED'.
-- admin_delete_game(): prosecdef = true, proconfig = {search_path=""}.
-- anon_execute = false; auth_execute = true.
--
-- Funcional (4 cenários reais, simulando a sessão do administrador via
-- set_config('request.jwt.claim.sub', ...) dentro de uma transação com
-- RAISE EXCEPTION forçado ao final — ROLLBACK total confirmado, 0
-- Jogos/linhas de auditoria residuais com prefixo 'ZZ_', total real de
-- Jogos inalterado (2: POKEMON + LORCANA)):
-- - T1 Exclusão de Game de teste sem Expansions: sucesso, linha
--   removida, 1 linha GAME_DELETED gravada em catalog_admin_action_log.
-- - T2 Tentativa de excluir POKEMON (tem Expansion associada): bloqueada
--   com ADMIN_DELETE_GAME_HAS_DEPENDENTS; POKEMON preservado.
-- - T3 Id inexistente: bloqueado com ADMIN_DELETE_GAME_NOT_FOUND.
-- - T4 Sem sessão administrativa: bloqueado com
--   ADMIN_DELETE_GAME_FORBIDDEN.
-- ================================================================
