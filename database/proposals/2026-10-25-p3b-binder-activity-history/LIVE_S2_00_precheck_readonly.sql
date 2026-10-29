/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S2_00_precheck_readonly.sql — P3-B S2, antes de 5271
Versão......: 1.0 (2026-10-27, P3-B S2)
Status......: PROPOSTA. SÓ LEITURA. Um único SELECT. Esperado: ok = true em todas as linhas.
              Janela quieta: usar também o G-PRE do gate v1.2 (P.04 = 0, P.12 ≥ 5 min).
================================================================
*/
select '00.1' as id,
       (select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1) as detail,
       coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
         = '20261027024918|5270_create_binder_activity_purge_and_legacy' as ok   -- baseline: última migration da S1
union all
select '00.2', 'S1 presente (10 funções) e 5271 ausente',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                            'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                            'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')) = 10
       and to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
union all
select '00.3', 'funções-base iguais ao canônico (md5 de prosrc): 5250 / 5132 / 5133',
       (select md5(prosrc) from pg_proc where oid = 'public.place_my_physical_card_in_slot(uuid, uuid, uuid)'::regprocedure) = 'caecf1bd88d9955dcfe409fb85a3effd'
       and (select md5(prosrc) from pg_proc where oid = 'public.move_slot_assignment(uuid, uuid)'::regprocedure) = '4e71adc22e4ee9c88e1fa21a0ddf4738'
       and (select md5(prosrc) from pg_proc where oid = 'public.remove_slot_assignment(uuid[])'::regprocedure) = '6bf6a90e00238ee59f8014503d96beaa'
union all
select '00.4', 'numeração 5271–5274 livre no ledger',
       not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5271|5272|5273|5274)_')
union all
select '00.5', 'histórico só com legado (nenhum evento instrumentado ainda)',
       not exists (select 1 from public.binder_activity_event where source <> 'LEGADO')
union all
select '00.6', 'nenhuma função fora da S1 referencia o histórico',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public'
                     and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                           'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                           'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
                     and pg_get_functiondef(p.oid) ~* 'binder_activity_');
