/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_5286_checks_readonly.sql — hardening de remove_layout_page (5286)
Versão......: 1.0 (2026-10-27)
Status......: SÓ LEITURA. PRE (antes da 5286) e POST (depois), um SELECT cada.
              ok = true em todas as linhas; qualquer false = STOP.
================================================================
*/

-- PRE ----------------------------------------------------------------------------------------
select 'P.1' as id, 'última migration = 5285; 5286 livre' as detail,
       (select name from supabase_migrations.schema_migrations order by version desc limit 1) = '5285_fix_remove_layout_page_variable_collision'
       and not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^5286_') as ok
union all
select 'P.2', 'remove_layout_page(uuid, integer) = corpo da 5285',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) = 'e482399664eeb4980436372b57cf378b'
union all
select 'P.3', 'invólucro, insert/close e binder_gap_move_pocket nos md5 instalados',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid)'::regprocedure) = '98736e42641bb8a592f2d8e4fd40fab1'
       and (select md5(prosrc) from pg_proc where oid = 'public.close_my_binder_gap(uuid, uuid, uuid, text, uuid)'::regprocedure) = 'd6b4d852a008f3a582e59f4ab9045885'
       and (select md5(prosrc) from pg_proc where oid = 'public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)'::regprocedure) = 'c76e6881dd2a40126c03b86e717904ad'
       and (select md5(prosrc) from pg_proc where oid = 'public.binder_gap_move_pocket(uuid, uuid)'::regprocedure) = 'ea19694de441a7a2d2ac6e63813d5035'
union all
select 'P.4', 'ACL: só authenticated executa (sem anon/PUBLIC)',
       has_function_privilege('authenticated', 'public.remove_layout_page(uuid, integer)'::regprocedure, 'EXECUTE')
       and not has_function_privilege('anon', 'public.remove_layout_page(uuid, integer)'::regprocedure, 'EXECUTE')
       and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure)) x where x.grantee = 0)
union all
select 'P.5', 'janela quieta: 0 sessões cliente ativas, 0 transações ociosas',
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle')
       and not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and state like 'idle in transaction%')
union all
select 'P.6 INFORMATIVO',
       'fichários com 1 página: ' || (select count(*) from (select layout_id from public.collection_layout_page group by layout_id having count(*) = 1) x)
       || ' | refs de espécie de outra coleção: ' || (select count(*) from public.collection_layout_slot_species_reference sr join public.collection_layout l on l.id = sr.layout_id where sr.collection_id <> l.collection_id)
       || ' | máx. evento: ' || coalesce((select max(id)::text from public.binder_activity_event), '-'),
       true;

-- POST ---------------------------------------------------------------------------------------
select 'Q.1' as id, 'ledger: 5286 imediatamente depois da 5285' as detail,
       (select array_agg(name order by version desc) from (select version, name from supabase_migrations.schema_migrations order by version desc limit 2) x)
         = array['5286_harden_remove_layout_page', '5285_fix_remove_layout_page_variable_collision'] as ok
union all
select 'Q.2', 'remove_layout_page(uuid, integer) = corpo da 5286 (md5 ed4215f4…)',
       (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) = 'ed4215f449ab0b547e0cc0164d7f73b8'
union all
select 'Q.3', 'recusas novas presentes; alias r e variável v_renum preservados',
       (select prosrc from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) ~ 'a binder must keep at least one page'
       and (select prosrc from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) ~ 'locked slot\(s\) — unlock them'
       and (select prosrc from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) ~ 'collection_layout_region r\s+WHERE r\.page_id = p_page_id'
       and (select prosrc from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) ~ 'FOR v_renum IN'
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
