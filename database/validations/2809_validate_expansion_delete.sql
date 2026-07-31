/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2809 - Validate Expansion Delete
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Validação estrutural e funcional da emenda de exclusão real de
Expansion (ADR-023, 2026-07-31): constraints atualizadas
(Query 2043) e admin_delete_expansion() (Query 2044). Mesmo
roteiro de validação já usado em Game (Query 2808).
================================================================
*/

-- 1. Constraints de catalog_admin_action_log incluem EXPANSION_DELETED
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
  AND conname IN ('ck_catalog_admin_action_log_action_valid', 'ck_catalog_admin_action_log_action_entity_match');

-- 2. Estrutura de admin_delete_expansion()
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_delete_expansion';

-- 3. Privilégios
SELECT
    has_function_privilege('anon', 'public.admin_delete_expansion(uuid)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_delete_expansion(uuid)', 'EXECUTE') AS auth_execute;

-- ================================================================
-- Validação estrutural (queries 1–3 acima): CONFIRMADA EXECUTADA
-- em 2026-07-31 — constraints com EXPANSION_DELETED, função com
-- prosecdef/proconfig corretos, anon sem EXECUTE / authenticated
-- com EXECUTE.
--
-- Validação funcional: CONFIRMADA por Fabrício em 2026-07-31,
-- testada diretamente pela interface (botão "excluir" na galeria
-- de Expansões) — "Validei todos na tela. Todos funcionando
-- corretamente." Cobre o caminho principal do usuário (exclusão
-- bem-sucedida e bloqueio ao tentar excluir Expansão com Card Sets
-- associados). Os cenários T3 (id inexistente) e T4 (sessão não-
-- administrativa) não são alcançáveis pela UI normal — permanecem
-- como cobertura teórica da função (mesma lógica já confirmada em
-- admin_delete_game(), Query 2808), não re-testados isoladamente.
-- ================================================================
