/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S5_00_precheck_readonly.sql — P3-B S5, antes de 5287
Versão......: 1.0 (2026-10-28, P3-B S5)
Status......: PROPOSTA. SÓ LEITURA. Um único SELECT. Esperado: ok = true em todas as linhas
              (00.8 é informativo). Janela quieta: 0 sessões cliente ativas e 0 transações
              ociosas (00.7) na hora da instalação.
================================================================
*/
select '00.1' as id,
       (select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1) as detail,
       coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
         = '20261028002709|5286_harden_remove_layout_page' as ok   -- baseline: última migration da S4
union all
select '00.2', 'gravação do histórico (5268) e helper de carta (5271) presentes; numeração 5287–5289 livre',
       to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is not null
       and to_regprocedure('public.binder_activity_end()') is not null
       and to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is not null
       and not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5287|5288|5289)_')
union all
select '00.3', 'funções-base = canônico (md5 de prosrc): 5249 ×2 / 5165; sobrecargas antigas 5024 / 5222 como lidas em 2026-10-28',
       (select md5(prosrc) from pg_proc where oid = 'public.set_physical_cards_storage(uuid, uuid[], boolean)'::regprocedure) = 'c68a460ce75a7384f521aee751e50335'
       and (select md5(prosrc) from pg_proc where oid = 'public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)'::regprocedure) = '083dc24206720b084c0bc5434d93e1fa'
       and (select md5(prosrc) from pg_proc where oid = 'public.remove_my_physical_card(uuid)'::regprocedure) = '1322db0293d346dd1911240b44881e99'
       and (select md5(prosrc) from pg_proc where oid = 'public.set_physical_cards_storage(uuid, uuid[])'::regprocedure) = 'cf8d15bcbd1f0842541bfac99be3eb72'
       and (select md5(prosrc) from pg_proc where oid = 'public.organize_my_collection_storage(uuid, uuid, text, integer, text)'::regprocedure) = '595e5229051e4dc6e16a1c9e484a6e9b'
union all
select '00.4', 'premissas da S5: só 5249 ×2 tiram bolso ao mudar local; 5256 ativa; bolso cai em cascata com o exemplar; 1 bolso por exemplar',
       (select coalesce(array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text), '{}') from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.prosrc ~* 'update\s+public\.physical_card' and p.prosrc ~* 'storage_container_id'
           and p.prosrc ~* 'delete\s+from\s+public\.collection_layout_slot_assignment')
         = array['organize_my_collection_storage(uuid,uuid,text,integer,text,boolean)', 'set_physical_cards_storage(uuid,uuid[],boolean)']
       and exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard'
                   and tgrelid = 'public.physical_card'::regclass and tgenabled = 'O')
       and (select confdeltype from pg_constraint c where c.conrelid = 'public.collection_layout_slot_assignment'::regclass and c.contype = 'f'
              and c.confrelid = 'public.physical_card'::regclass) = 'c'
       and exists (select 1 from pg_constraint where conname = 'uq_collection_layout_slot_assignment_physical_card')
       and (select coalesce(array_agg(p.oid::regprocedure::text), '{}') from pg_proc p
             where p.pronamespace = 'public'::regnamespace and p.prosrc ~* 'delete\s+from\s+public\.physical_card') = array['remove_my_physical_card(uuid)']
union all
select '00.5', 'nenhum evento da S5 ainda',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT'))
union all
select '00.6', 'fora da S1, só S2 + S3 + S4 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['add_layout_page','binder_activity_add_card_item','binder_activity_add_pocket_shift_items','binder_activity_add_reservation_item',
               'clear_slot_expected_content','close_my_binder_gap','insert_my_binder_gap','move_slot_assignment',
               'place_my_physical_card_in_slot','remove_layout_page','remove_slot_assignment','reorder_layout_pages',
               'set_slot_expected_content','set_slot_lock']
union all
select '00.7', 'janela quieta: 0 sessões cliente ativas, 0 transações ociosas',
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle')
       and not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and state like 'idle in transaction%')
union all
select '00.8 INFORMATIVO',
       'bolsos com carta: ' || (select count(*) from public.collection_layout_slot_assignment)
       || ' | bolsos com exemplar sem alocação (alvo de E07): ' || (select count(*) from public.collection_layout_slot_assignment where collection_allocation_id is null)
       || ' | máx. evento: ' || coalesce((select max(id)::text from public.binder_activity_event), '-'),
       true;
