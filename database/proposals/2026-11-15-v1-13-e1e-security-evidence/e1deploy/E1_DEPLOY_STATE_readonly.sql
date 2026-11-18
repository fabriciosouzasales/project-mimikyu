/*
V1-13 · Etapa 7 — Implantação controlada da E1 — estado da cadeia (SOMENTE LEITURA)
Uma única instrução SELECT; não escreve, não chama capacidade, não muda modo da barreira.
Usada pelo executor E1_DEPLOY_CLI_executor.ps1 com --read-only:
  (a) depois da 5389 (barreira CLOSED, registro vazio, nada além da 5389);
  (b) depois da 5377 (cadeia completa, fechada);
  (c) depois de qualquer falha (diagnóstico do ponto de interrupção).
Marcadores: um objeto criado por migration; null = migration sem marcador próprio
(CREATE OR REPLACE de função existente: 5378, 5384), identificada pelo registro do executor.
Capacidades: as 37 da barreira (mesma lista do postcheck T9 do G2_B v3).
Correção (INITIAL STATE READ CORRECTION-01): nenhuma referência estática a relação criada pela E1.
As tabelas da 5389 só são lidas por query_to_xml (texto analisado apenas quando executado; forma <table>,
que com zero linhas devolve NULL em vez de erro), dentro de
CASE guardado por to_regclass; antes da 5389 o ramo não é avaliado e nada é resolvido (sem 42P01).
Nenhuma conversão literal ::regclass/::regprocedure: só to_regclass/to_regprocedure (devolvem NULL).
*/
select jsonb_build_object(
  'barreira', case when to_regclass('public.v1_13_barrier_state') is null then null
                   else (pg_catalog.xpath('/table/row/m/text()', pg_catalog.query_to_xml(
                           'select s.mode as m from public.v1_13_barrier_state s where s.id = 1', false, false, '')))[1]::text end,
  'identidades', case when to_regclass('public.v1_13_barrier_identity') is null then null
                      else ((pg_catalog.xpath('/table/row/n/text()', pg_catalog.query_to_xml(
                           'select count(*) as n from public.v1_13_barrier_identity', false, false, '')))[1]::text)::bigint end,
  'marcadores', jsonb_build_object(
    '5389', to_regclass('public.v1_13_barrier_state') is not null,
    '5366', exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = to_regclass('public.collection_membership')
                     and k.contype = 'c' and pg_catalog.pg_get_constraintdef(k.oid) like '%EDITOR%'),
    '5367', to_regprocedure('public.collection_member_role(uuid)') is not null,
    '5368', coalesce((select position('collection_member_role' in p.prosrc) > 0 from pg_catalog.pg_proc p
                       where p.oid = to_regprocedure('public.get_shared_collection(uuid)')), false),
    '5369', to_regprocedure('public.invite_collection_member(uuid, text, text)') is not null
            and to_regprocedure('public.invite_collection_member(uuid, text)') is null,
    '5370', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'set_collection_member_role'),
    '5371', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'assert_collection_binder_editor'),
    '5372', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'binder_activity_add_item' and position('EDITOR' in p.prosrc) > 0),
    '5373', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'get_shared_binder_placeable_cards'),
    '5374', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_place_card_in_binder'),
    '5375', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_set_binder_reservation'),
    '5376', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_update_collection_metadata'),
    '5378', null::boolean,
    '5379', (select count(*) from information_schema.columns c where c.table_schema = 'public'
              and ((c.table_name = 'binder_activity_item' and c.column_name = 'collection_id')
                or (c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded'))) = 2,
    '5380', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_set_pokedex_position_assignment'),
    '5381', exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = to_regclass('public.binder_activity_event')
                     and t.tgname = 'trg_bae_editor_event_type' and not t.tgisinternal),
    '5382', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_add_binder_page'),
    '5383', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_apply_binder_species_references'),
    '5384', null::boolean,
    '5385', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_insert_binder_gap'),
    '5386', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_apply_binder_auto_arrange'),
    '5387', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'editor_apply_binder_catalog_reconciliation'),
    '5323', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'get_shared_master_set_positions'),
    '5324', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'get_shared_pokedex_positions'),
    '5388', exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'get_shared_binder_activity'),
    '5377', (select count(*) from pg_catalog.pg_policies pol where pol.schemaname = 'storage' and pol.tablename = 'objects'
              and pol.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')) = 3
            and to_regprocedure('public.collection_cover_editor_can_upload(text)') is not null),
  'capacidades_presentes', (select count(distinct p.proname) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any (c.nomes)),
  'expostas_sem_porta', (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any (c.nomes)
       and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') and position('public.v1_13_' in p.prosrc) = 0),
  'expostas_anon', (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any (c.nomes) and pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')),
  'server_version_num', current_setting('server_version_num')::integer,
  'lido_em', pg_catalog.clock_timestamp()
) as e1_estado
from (select array['collection_cover_editor_can_upload', 'collection_cover_editor_folder_ok', 'editor_add_binder_page',
  'editor_apply_binder_auto_arrange', 'editor_apply_binder_catalog_reconciliation', 'editor_apply_binder_species_references',
  'editor_clear_binder_reservation', 'editor_clear_binder_species_references', 'editor_clear_pokedex_position_primary_representative',
  'editor_close_binder_gap', 'editor_insert_binder_gap', 'editor_move_binder_card', 'editor_place_card_in_binder',
  'editor_preview_binder_auto_arrange', 'editor_preview_binder_catalog_reconciliation', 'editor_preview_binder_insert_gap',
  'editor_preview_binder_species_references', 'editor_remove_binder_card', 'editor_remove_binder_page',
  'editor_remove_pokedex_position_assignment', 'editor_reorder_binder_pages', 'editor_set_binder_lock',
  'editor_set_binder_reservation', 'editor_set_binder_species_reference_visibility', 'editor_set_collection_cover_code',
  'editor_set_collection_cover_finish', 'editor_set_collection_cover_logo', 'editor_set_pokedex_position_assignment',
  'editor_set_pokedex_position_primary_representative', 'editor_update_collection_metadata', 'get_shared_binder_activity',
  'get_shared_binder_activity_status', 'get_shared_binder_placeable_cards', 'get_shared_master_set_positions',
  'get_shared_pokedex_positions', 'invite_collection_member', 'set_collection_member_role']::name[] as nomes) c;
