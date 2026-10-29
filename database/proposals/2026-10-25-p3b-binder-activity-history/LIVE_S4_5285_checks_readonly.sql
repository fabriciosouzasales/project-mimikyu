/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S4_5285_checks_readonly.sql — P3-B S4, hotfix 5285
Versão......: 1.0 (2026-10-27)
Status......: SÓ LEITURA. Dois SELECTs independentes: PRE (antes da 5285) e POST (depois).
              ok = true em todas as linhas; qualquer false = STOP.
              Depois do POST e da homologação pela interface: bloco B de LIVE_S4_90 (inalterado).
================================================================
*/

-- PRE ----------------------------------------------------------------------------------------
select 'P.1' as id, 'última migration = 5284; 5285 livre' as detail,
       (select name from supabase_migrations.schema_migrations order by version desc limit 1) = '5284_instrument_close_my_binder_gap'
       and not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^5285_') as ok
union all
select 'P.2', 'remove_layout_page(uuid, integer) = corpo da 5281 (md5 5ea978d5…)',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) = '5ea978d582f055fb8690f9974a2bea2f'
union all
select 'P.3', 'invólucro e demais funções da S4 nos md5 instalados',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid)'::regprocedure) = '98736e42641bb8a592f2d8e4fd40fab1'
       and (select md5(prosrc) from pg_proc where oid = 'public.close_my_binder_gap(uuid, uuid, uuid, text, uuid)'::regprocedure) = 'd6b4d852a008f3a582e59f4ab9045885'
       and (select md5(prosrc) from pg_proc where oid = 'public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)'::regprocedure) = 'c76e6881dd2a40126c03b86e717904ad'
union all
select 'P.4', 'ACL de remove_layout_page(uuid, integer): só authenticated (sem anon/PUBLIC)',
       has_function_privilege('authenticated', 'public.remove_layout_page(uuid, integer)'::regprocedure, 'EXECUTE')
       and not has_function_privilege('anon', 'public.remove_layout_page(uuid, integer)'::regprocedure, 'EXECUTE')
       and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure)) x where x.grantee = 0)
union all
select 'P.5', 'janela quieta: 0 sessões cliente ativas, 0 transações ociosas',
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle')
       and not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and state like 'idle in transaction%')
union all
select 'P.6 INFORMATIVO', 'última autenticação: ' || coalesce((select max(created_at)::text from auth.audit_log_entries), '-'), true;

-- POST ---------------------------------------------------------------------------------------
select 'Q.1' as id, 'ledger: 5285 imediatamente depois da 5284' as detail,
       (select array_agg(name order by version desc) from (select version, name from supabase_migrations.schema_migrations order by version desc limit 2) x)
         = array['5285_fix_remove_layout_page_variable_collision', '5284_instrument_close_my_binder_gap'] as ok
union all
select 'Q.2', 'remove_layout_page(uuid, integer) = corpo da 5285 (md5 e4823996…)',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) = 'e482399664eeb4980436372b57cf378b'
union all
select 'Q.3', 'nenhuma variável "r" declarada; alias r de collection_layout_region presente',
       (select prosrc from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) !~ '\n\s+r\s+RECORD'
       and (select prosrc from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) ~ 'collection_layout_region r\s+WHERE r\.page_id = p_page_id'
union all
select 'Q.4', 'invólucro, insert/close e binder_gap_move_pocket inalterados',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid)'::regprocedure) = '98736e42641bb8a592f2d8e4fd40fab1'
       and (select md5(prosrc) from pg_proc where oid = 'public.close_my_binder_gap(uuid, uuid, uuid, text, uuid)'::regprocedure) = 'd6b4d852a008f3a582e59f4ab9045885'
       and (select md5(prosrc) from pg_proc where oid = 'public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)'::regprocedure) = 'c76e6881dd2a40126c03b86e717904ad'
       and (select md5(prosrc) from pg_proc where oid = 'public.binder_gap_move_pocket(uuid, uuid)'::regprocedure) = 'ea19694de441a7a2d2ac6e63813d5035'
union all
select 'Q.5', 'assinatura/retorno/DEFINER/search_path/ACL preservados',
       pg_get_function_result('public.remove_layout_page(uuid, integer)'::regprocedure) = 'void'
       and (select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure)
       and has_function_privilege('authenticated', 'public.remove_layout_page(uuid, integer)'::regprocedure, 'EXECUTE')
       and not has_function_privilege('anon', 'public.remove_layout_page(uuid, integer)'::regprocedure, 'EXECUTE')
       and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure)) x where x.grantee = 0);
