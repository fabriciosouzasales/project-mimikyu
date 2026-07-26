/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1860 - Validate Admin Functions
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação estrutural de is_admin(), admin_list_users(),
admin_grant_admin() e admin_revoke_admin(): SECURITY DEFINER,
assinatura e privilégios de EXECUTE. Não inclui chamada
funcional direta — todas exigem is_admin() internamente, que só
resolve com uma sessão real (auth.uid()), inexistente no SQL
Editor. A validação funcional acontece a partir do app.
================================================================
*/

-- 1. SECURITY DEFINER e número de parâmetros
SELECT p.proname, p.prosecdef, p.pronargs
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('is_admin', 'admin_list_users', 'admin_grant_admin', 'admin_revoke_admin')
ORDER BY p.proname;

-- 2. Privilégios de EXECUTE (esperado: authenticated + postgres, nunca anon)
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public'
  AND routine_name IN ('is_admin', 'admin_list_users', 'admin_grant_admin', 'admin_revoke_admin')
ORDER BY routine_name, grantee;
