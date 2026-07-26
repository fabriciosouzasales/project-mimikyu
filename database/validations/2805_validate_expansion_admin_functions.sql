/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2805 - Validate Expansion Admin Functions
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação estrutural e funcional de admin_create_expansion()
(Query 2033) e admin_update_expansion() (Query 2034).
================================================================
*/

-- 1. Estrutura
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('admin_create_expansion', 'admin_update_expansion');

-- 2. Privilégios
SELECT
    has_function_privilege('anon', 'public.admin_create_expansion(uuid, text, text, integer)', 'EXECUTE') AS anon_create,
    has_function_privilege('authenticated', 'public.admin_create_expansion(uuid, text, text, integer)', 'EXECUTE') AS auth_create,
    has_function_privilege('anon', 'public.admin_update_expansion(uuid, text, integer)', 'EXECUTE') AS anon_update,
    has_function_privilege('authenticated', 'public.admin_update_expansion(uuid, text, integer)', 'EXECUTE') AS auth_update;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
--
-- Estrutural: prosecdef = true e proconfig = {search_path=""} para as duas
-- funções. anon_create = false; auth_create = true; anon_update = false;
-- auth_update = true.
--
-- Funcional (11 cenários reais, simulando a sessão do administrador via
-- set_config('request.jwt.claim.sub', ...) dentro de uma transação com
-- RAISE EXCEPTION forçado ao final — ROLLBACK total confirmado, 0
-- Expansões/linhas de auditoria residuais com prefixo 'ZZ_', total real de
-- Expansões inalterado (1: 'ME' de POKEMON)):
-- - T1 CREATE bem-sucedido: code normalizado para maiúsculas.
-- - T2 Duplicidade de code no mesmo Game: bloqueado.
-- - T3 Duplicidade de release_order no mesmo Game: bloqueado.
-- - T4 game_id inexistente: bloqueado.
-- - T5 Code em formato inválido: bloqueado.
-- - T6 Nome vazio no CREATE: bloqueado.
-- - T7 UPDATE bem-sucedido (nome e release_order).
-- - T8 UPDATE colidindo release_order com outra Expansão do mesmo Game:
--   bloqueado.
-- - T9 UPDATE de id inexistente: bloqueado.
-- - T10 Nome vazio no UPDATE: bloqueado.
-- - T11 Chamada sem sessão administrativa: bloqueada.
-- - Auditoria: 2 linhas EXPANSION_CREATED e 1 linha EXPANSION_UPDATED
--   confirmadas antes do rollback.
-- ================================================================
