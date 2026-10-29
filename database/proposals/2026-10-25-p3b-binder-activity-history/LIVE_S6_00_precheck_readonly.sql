/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S6_00_precheck_readonly.sql — P3-B S6, antes de 5290
Versão......: 1.0 (2026-10-28, P3-B S6)
Status......: PROPOSTA. SÓ LEITURA. Um único SELECT. Esperado: ok = true em todas as linhas
              (00.7 é informativo).
================================================================
*/
select '00.1' as id,
       (select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1) as detail,
       coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
         = '20261028005621|5289_instrument_remove_my_physical_card' as ok   -- baseline: última migration da S5
union all
select '00.2', 'dependências 5268/5271/5275/5279 presentes; numeração 5290–5296 livre',
       to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is not null
       and to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is not null
       and to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is not null
       and to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is not null
       and not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^529[0-6]_')
union all
select '00.3', 'funções-base iguais às lidas em 2026-10-28 (md5 de prosrc)',
       (select md5(prosrc) from pg_proc where oid = 'public.attach_my_collection_to_binder(uuid, uuid)'::regprocedure) = '1b87933cf804aa3fc29f8659dc947e2c'
       and (select md5(prosrc) from pg_proc where oid = 'public.detach_my_collection_from_binder(uuid, text, boolean)'::regprocedure) = '09570bf964a8351c0f97acbc7ba9c736'
       and (select md5(prosrc) from pg_proc where oid = 'public.transfer_my_binder_ownership(uuid, uuid)'::regprocedure) = '4755a772e002c5a3994c6ad81ac53bb9'
       and (select md5(prosrc) from pg_proc where oid = 'public.delete_collection_layout(uuid)'::regprocedure) = '1b4bf89732af4ef36c834a30b08fec44'
       and (select md5(prosrc) from pg_proc where oid = 'public.dismantle_my_collection_binder(uuid, text)'::regprocedure) = '6aa90085a3a97c5b149fde6f3c4a6096'
       and (select md5(prosrc) from pg_proc where oid = 'public.create_my_collection_binder(uuid, integer, integer, text, text)'::regprocedure) = '5ba7941f175137f322179eff72f7a37c'
       and (select md5(prosrc) from pg_proc where oid = 'public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'::regprocedure) = 'aa58b231484cc1ed533c50c51c38f2cc'
       and (select md5(prosrc) from pg_proc where oid = 'public.add_layout_page(uuid)'::regprocedure) = '9df4f0978e7dcc4f940567a4f6aae12f'
union all
select '00.4', 'nenhum evento da S6 ainda',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('BINDER_ASSEMBLED','CATALOG_NOVELTIES_INCORPORATED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                                        'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED'))
union all
select '00.5', 'fora da S1, só S2–S5 referenciam o histórico (17 funções)',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['add_layout_page','binder_activity_add_card_item','binder_activity_add_pocket_shift_items','binder_activity_add_reservation_item',
               'clear_slot_expected_content','close_my_binder_gap','insert_my_binder_gap','move_slot_assignment',
               'organize_my_collection_storage','place_my_physical_card_in_slot','remove_layout_page','remove_my_physical_card',
               'remove_slot_assignment','reorder_layout_pages','set_physical_cards_storage','set_slot_expected_content','set_slot_lock']
union all
select '00.6', 'janela quieta: 0 sessões cliente ativas, 0 transações ociosas',
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle')
       and not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and state like 'idle in transaction%')
union all
select '00.7 INFORMATIVO',
       'fichários: ' || (select count(*) from public.collection_layout)
       || ' | convidadas: ' || (select count(*) from public.collection_layout_guest)
       || ' | máx. evento: ' || coalesce((select max(id)::text from public.binder_activity_event), '-'),
       true;
