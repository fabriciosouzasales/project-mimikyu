/*
================================================================
Projeto.....: Project Mimikyu
Query.......: LIVE_90 - Pós-checagem somente leitura da P2 (independente do harness)
Versão......: 1.0
Status......: PREPARADO — NÃO EXECUTADO (P2 OPERATIONAL ROUTE CORRECTION-11, 2026-11-01)
Classe......: R1 (somente leitura).

Uso (após 5341–5344 aplicadas e 5872 executado):
  POST  → todas as linhas ok = true.
  FP    → repetir o bloco FP do LIVE_00 e comparar linha a linha com a saída
          guardada: n e fp idênticos em todas as tabelas (resíduo zero e dados
          reais intocados).
  SRC   → md5 dos corpos no banco; comparar com o md5 do trecho entre $fn$ … $fn$
          de cada arquivo (comando local no README).
  Mais: get_advisors(security) sem achado novo ligado às três funções.
================================================================
*/

-- POST -------------------------------------------------------------------------------
set transaction read only;
with
f as (select to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)') as plan,
             to_regprocedure('public.preview_my_binder_auto_arrange(uuid)')      as prev,
             to_regprocedure('public.apply_my_binder_auto_arrange(uuid,text)')   as apply),
live_types(t) as (select m[1] from regexp_matches(pg_get_constraintdef(
  (select oid from pg_constraint where conrelid = 'public.binder_activity_event'::regclass and conname = 'chk_bae_event_type')),
  '''([A-Z_0-9]+)''', 'g') m)
select 'POST-1' as id,
       (select p.prolang = (select oid from pg_language where lanname = 'sql') and p.provolatile = 's' and not p.prosecdef
               and p.proconfig = array['search_path=""']
               and not has_function_privilege('anon', p.oid, 'EXECUTE')
               and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
               and not has_function_privilege('service_role', p.oid, 'EXECUTE')
        from pg_proc p, f where p.oid = f.plan) as ok,
       '5342: SQL, STABLE, INVOKER, search_path vazio, sem EXECUTE para papéis de API' as detail
union all
select 'POST-2',
       (select p.prolang = (select oid from pg_language where lanname = 'plpgsql') and p.provolatile = 's' and p.prosecdef
               and p.proconfig = array['search_path=""']
               and has_function_privilege('authenticated', p.oid, 'EXECUTE')
               and not has_function_privilege('anon', p.oid, 'EXECUTE')
               and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
        from pg_proc p, f where p.oid = f.prev),
       '5343: plpgsql, STABLE, DEFINER, search_path vazio, EXECUTE só authenticated'
union all
select 'POST-3',
       (select p.prolang = (select oid from pg_language where lanname = 'plpgsql') and p.provolatile = 'v' and p.prosecdef
               and p.proconfig @> array['search_path=""','lock_timeout=5s'] and cardinality(p.proconfig) = 2
               and has_function_privilege('authenticated', p.oid, 'EXECUTE')
               and not has_function_privilege('anon', p.oid, 'EXECUTE')
               and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
        from pg_proc p, f where p.oid = f.apply),
       '5344: plpgsql, VOLATILE (snapshot novo por comando), DEFINER, search_path vazio + lock_timeout 5s, EXECUTE só authenticated'
union all
select 'POST-4',
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('binder_auto_arrange_plan','preview_my_binder_auto_arrange','apply_my_binder_auto_arrange')) = 3,
       'uma versão de cada função'
union all
select 'POST-5',
       (select count(*) from live_types) = 25
       and exists (select 1 from live_types where t = 'CARDS_AUTO_ARRANGED')
       and public.binder_activity_category('CARDS_AUTO_ARRANGED') = 'CARDS'
       and public.binder_activity_category('CARD_PLACED') = 'CARDS'
       and public.binder_activity_category('BINDER_ASSEMBLED') = 'BINDER',
       '5341: 24 tipos anteriores + CARDS_AUTO_ARRANGED; categorias preservadas'
union all
select 'POST-6',
       (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = 0,
       'nenhum evento CARDS_AUTO_ARRANGED persistido (harness desfeito; ninguém usou a função)'
union all
select 'POST-7',
       (select count(*) from supabase_migrations.schema_migrations
        where name in ('p2_5341_extend_binder_activity_auto_arrange_event','p2_5342_create_binder_auto_arrange_plan',
                       'p2_5343_create_preview_my_binder_auto_arrange','p2_5344_create_apply_my_binder_auto_arrange')) = 4,
       'ledger com as quatro migrations (nomes do plano executivo)';

-- SRC --------------------------------------------------------------------------------
set transaction read only;
select p.proname, md5(p.prosrc) as md5_body
from pg_proc p
where p.oid in (to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)'),
                to_regprocedure('public.preview_my_binder_auto_arrange(uuid)'),
                to_regprocedure('public.apply_my_binder_auto_arrange(uuid,text)'),
                to_regprocedure('public.binder_activity_category(text)'))
order by 1;

-- FP: repetir o bloco FP do LIVE_00 sem alteração.
