/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S3_00_precheck_readonly.sql — P3-B S3, antes de 5275
Versão......: 1.0 (2026-10-27, P3-B S3)
Status......: PROPOSTA. SÓ LEITURA. Um único SELECT. Esperado: ok = true em todas as linhas.
              Janela quieta: usar também o G-PRE do gate v1.2 (P.04 = 0, P.12 ≥ 5 min).
================================================================
*/
select '00.1' as id,
       (select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1) as detail,
       coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
         = '20261027030849|5274_instrument_remove_slot_assignment' as ok   -- baseline: última migration da S2
union all
select '00.2', 'S1 (10 funções) e helper 5271 presentes; 5275 ausente',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                            'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                            'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')) = 10
       and to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is not null
       and to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
union all
select '00.3', 'funções-base iguais ao canônico (md5 de prosrc): 5229 / 5129 / 5130',
       (select md5(prosrc) from pg_proc where oid = 'public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)'::regprocedure) = '56a9aa74307e3708b34c014f471a4cd6'
       and (select md5(prosrc) from pg_proc where oid = 'public.clear_slot_expected_content(uuid[])'::regprocedure) = 'd4e229d6db9196bf8caa738b5ba2e8b0'
       and (select md5(prosrc) from pg_proc where oid = 'public.set_slot_lock(uuid[], boolean)'::regprocedure) = '782a551d7c3af03e74a56020802432d5'
union all
select '00.4', 'numeração 5275–5278 livre no ledger',
       not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5275|5276|5277|5278)_')
union all
select '00.5', 'nenhum evento das fatias S3 ainda',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED'))
union all
select '00.6', 'fora da S1, só as funções da S2 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['binder_activity_add_card_item','move_slot_assignment','place_my_physical_card_in_slot','remove_slot_assignment'];
