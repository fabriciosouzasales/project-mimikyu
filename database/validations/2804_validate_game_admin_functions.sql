/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2804 - Validate Game Admin Functions
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação estrutural e funcional de admin_create_game() (Query
2031) e admin_update_game() (Query 2032).
================================================================
*/

-- 1. Estrutura: SECURITY DEFINER, search_path vazio
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('admin_create_game', 'admin_update_game');

-- 2. Privilégios: anon sem EXECUTE; authenticated com EXECUTE
SELECT
    has_function_privilege('anon', 'public.admin_create_game(text, text)', 'EXECUTE') AS anon_create,
    has_function_privilege('authenticated', 'public.admin_create_game(text, text)', 'EXECUTE') AS auth_create,
    has_function_privilege('anon', 'public.admin_update_game(uuid, text)', 'EXECUTE') AS anon_update,
    has_function_privilege('authenticated', 'public.admin_update_game(uuid, text)', 'EXECUTE') AS auth_update;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
--
-- Estrutural: prosecdef = true e proconfig = {search_path=""} para as
-- duas funções. anon_create = false; auth_create = true; anon_update =
-- false; auth_update = true.
--
-- Funcional (8 cenários reais, simulando a sessão do administrador via
-- set_config('request.jwt.claim.sub', ...) dentro de uma transação com
-- RAISE EXCEPTION forçado ao final — ROLLBACK total confirmado, 0
-- Jogos/linhas de auditoria residuais com prefixo 'ZZ_TEST'):
-- - T1 CREATE bem-sucedido: code normalizado para maiúsculas (zz_test →
--   ZZ_TEST).
-- - T2 Duplicidade de code: bloqueado com ADMIN_CREATE_GAME_DUPLICATE_CODE.
-- - T3 Code em formato inválido (começa com dígito): bloqueado com
--   ADMIN_CREATE_GAME_INVALID_CODE.
-- - T4 Nome vazio no CREATE: bloqueado com ADMIN_CREATE_GAME_INVALID_NAME.
-- - T5 UPDATE bem-sucedido: nome alterado, code preservado (parâmetro nem
--   existe na assinatura de admin_update_game()).
-- - T6 UPDATE de id inexistente: bloqueado com ADMIN_UPDATE_GAME_NOT_FOUND.
-- - T7 Nome vazio no UPDATE: bloqueado com ADMIN_UPDATE_GAME_INVALID_NAME.
-- - T8 Chamada sem sessão administrativa: bloqueada com
--   ADMIN_CREATE_GAME_FORBIDDEN.
-- - Auditoria: exatamente 1 linha GAME_CREATED e 1 linha GAME_UPDATED
--   gravadas para o Jogo de teste (T1/T5), confirmadas antes do rollback.
--
-- Pendente (fora do escopo de uma validação SQL): teste da tela
-- /catalogo/jogos pela própria interface (listagem, cadastro, edição) —
-- ambiente desta sessão sem acesso a npm/CDN para rodar `npm run dev`;
-- fica para confirmação de Fabrício em seu próprio ambiente.
-- ================================================================
