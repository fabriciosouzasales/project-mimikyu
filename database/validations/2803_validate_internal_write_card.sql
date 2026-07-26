/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2803 - Validate internal.write_card()
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação estrutural (SECURITY DEFINER, search_path, privilégios)
e funcional (cinco cenários reais, executados dentro de uma
transação com ROLLBACK forçado — nenhum dado persistido) de
internal.write_card().
================================================================
*/

-- 1. Estrutura: SECURITY DEFINER, search_path vazio
SELECT
    p.proname,
    n.nspname AS schema,
    p.prosecdef AS security_definer,
    p.proconfig AS config,
    pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'internal' AND p.proname = 'write_card';

-- 2. Privilégios: anon/authenticated sem EXECUTE; postgres (owner) com EXECUTE
SELECT
    has_function_privilege('anon', 'internal.write_card(text, uuid, uuid, uuid, uuid, text, integer, integer, text)', 'EXECUTE') AS anon_pode_executar,
    has_function_privilege('authenticated', 'internal.write_card(text, uuid, uuid, uuid, uuid, text, integer, integer, text)', 'EXECUTE') AS authenticated_pode_executar,
    has_function_privilege('postgres', 'internal.write_card(text, uuid, uuid, uuid, uuid, text, integer, integer, text)', 'EXECUTE') AS postgres_pode_executar;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
--
-- Estrutural:
-- - prosecdef = true; proconfig = {search_path=""}.
-- - anon_pode_executar = false; authenticated_pode_executar = false;
--   postgres_pode_executar = true.
--
-- Funcional (5 cenários reais, dentro de BEGIN ... RAISE EXCEPTION
-- forçado ao final, garantindo ROLLBACK total — confirmado 0 linhas
-- residuais em public.card com collector_number = 'TEST-999'):
-- - T1 CREATE: sucesso, id retornado.
-- - T2 UPDATE (campos editáveis): sucesso, name refletiu a alteração.
-- - T3 UPDATE tentando alterar card_set_id: bloqueado com
--   INTERNAL_WRITE_CARD_PROTECTED_FIELD.
-- - T4 UPDATE de id inexistente: bloqueado com
--   INTERNAL_WRITE_CARD_NOT_FOUND.
-- - T5 p_mode inválido ('DELETE'): bloqueado com
--   INTERNAL_WRITE_CARD_INVALID_MODE.
--
-- Todos os 5 cenários se comportaram exatamente como especificado,
-- sem exceção da diferença esperada (bloqueio correto em T3/T4/T5).
-- ================================================================
