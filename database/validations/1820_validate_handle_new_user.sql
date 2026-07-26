/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1820 - Validate handle_new_user
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Validação estrutural de handle_new_user(): SECURITY DEFINER
ativo, search_path configurado, trigger corretamente associado a
auth.users, e EXECUTE bloqueado para anon/authenticated (só o
trigger a invoca). Teste funcional completo (cadastro real) só é
possível depois do formulário de cadastro coletar username/
display_name (ver Task de frontend).
================================================================
*/

SELECT proname, prosecdef,
    (SELECT count(*) FROM unnest(proconfig) c WHERE c LIKE 'search_path=%') AS tem_search_path_vazio
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname = 'handle_new_user';

SELECT trigger_name, event_manipulation, action_timing, event_object_schema, event_object_table
FROM information_schema.triggers
WHERE event_object_schema = 'auth' AND event_object_table = 'users';

-- Esperado: false / false (ninguém chama diretamente, só o trigger).
SELECT
    has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE') AS anon,
    has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE') AS authenticated;
