/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S4_00_precheck_readonly.sql — P3-B S4, antes de 5279
Versão......: 1.0 (2026-10-27, P3-B S4)
Status......: PROPOSTA. SÓ LEITURA. Um único SELECT. Esperado: ok = true em todas as linhas.
              Janela quieta: usar também o G-PRE do gate v1.2 (P.04 = 0, P.12 ≥ 5 min).
================================================================
*/
select '00.1' as id,
       (select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1) as detail,
       coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
         = '20261027221757|5278_instrument_set_slot_lock' as ok   -- baseline: última migration da S3
union all
select '00.2', 'S1 (10 funções) + helpers 5271/5275 presentes; 5279 ausente',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                            'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                            'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')) = 10
       and to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is not null
       and to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is not null
       and to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
union all
select '00.3', 'funções-base iguais ao LIVE de referência (md5 de prosrc): 5125 / 5260 / 5127 / 5243 ×2',
       (select md5(prosrc) from pg_proc where oid = 'public.add_layout_page(uuid)'::regprocedure) = 'cdcf89d386ed87ab69b8a17496170017'
       and (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid, integer)'::regprocedure) = '4baf044d8df24aa957873fce2cf5529a'
       and (select md5(prosrc) from pg_proc where oid = 'public.remove_layout_page(uuid)'::regprocedure) = '98736e42641bb8a592f2d8e4fd40fab1'
       and (select md5(prosrc) from pg_proc where oid = 'public.reorder_layout_pages(uuid, uuid[])'::regprocedure) = '39b8b80f3f3cb0f0a0f88a98352a52c9'
       and (select md5(prosrc) from pg_proc where oid = 'public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)'::regprocedure) = 'a99a90c572d2bd35424b4c725fff0150'
       and (select md5(prosrc) from pg_proc where oid = 'public.close_my_binder_gap(uuid, uuid, uuid, text, uuid)'::regprocedure) = 'eef3073f5ad98ffe6fdfe36f1adb9f49'
       and (select md5(prosrc) from pg_proc where oid = 'public.binder_gap_move_pocket(uuid, uuid)'::regprocedure) = 'ea19694de441a7a2d2ac6e63813d5035'
union all
select '00.4', 'numeração 5279–5284 livre no ledger',
       not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5279|5280|5281|5282|5283|5284)_')
union all
select '00.5', 'nenhum evento das fatias S4 ainda',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED'))
union all
select '00.6', 'fora da S1, só S2 + S3 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['binder_activity_add_card_item','binder_activity_add_reservation_item','clear_slot_expected_content',
               'move_slot_assignment','place_my_physical_card_in_slot','remove_slot_assignment',
               'set_slot_expected_content','set_slot_lock'];
