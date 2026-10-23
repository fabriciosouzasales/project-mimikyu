-- P2-BINDER-LAYOUT-CUSTOMIZATION — R1-pós (SOMENTE LEITURA). NÃO EXECUTADO.

begin transaction read only;

-- POST-1 Proteções de mesclagem (5238): todos true.
select
  not has_function_privilege('authenticated', 'public.merge_layout_region(uuid, integer, integer, integer, integer)', 'EXECUTE') as merge_closed,
  not has_function_privilege('authenticated', 'public.unmerge_layout_region(uuid)', 'EXECUTE')                                as unmerge_closed,
  (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O'
     and tgname in ('trg_slot_assignment_outside_region', 'trg_slot_expected_content_outside_region',
                    'trg_region_slots_without_content', 'trg_slot_lock_outside_region')) = 4      as guards_on,
  to_regclass('public.ix_collection_layout_region_page') is not null                       as region_page_index;

-- POST-2 Storage (5239): política intocada (fp = PRE-5), função de vínculo cobre mesclagens.
select
  md5(string_agg(policyname || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by policyname)) as fp_storage_policies,
  pg_get_functiondef('public.binder_slot_image_path_is_linked(text)'::regprocedure) like '%collection_layout_region_image%' as linked_covers_regions,
  has_function_privilege('authenticated', 'public.binder_slot_image_path_is_linked(text)', 'EXECUTE')     as linked_exec_auth,
  not has_function_privilege('anon', 'public.binder_slot_image_path_is_linked(text)', 'EXECUTE')          as linked_no_anon
from pg_policies where schemaname = 'storage' and tablename = 'objects';

-- POST-3 Tabela nova fechada e vazia.
select
  (select relrowsecurity from pg_class where oid = 'public.collection_layout_region_image'::regclass) as rls_on,
  not has_table_privilege('authenticated', 'public.collection_layout_region_image', 'SELECT')        as no_client_select,
  (select count(*) from public.collection_layout_region_image) = 0                                   as empty;

-- POST-4 Funções novas: SECURITY DEFINER, search_path vazio, sem anon; internas sem authenticated.
select p.proname,
       p.prosecdef,
       coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=""%' as empty_search_path,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('merge_my_binder_slots_with_image', 'set_my_binder_region_image', 'set_my_binder_region_image_focus',
                    'separate_my_binder_slots', 'get_my_collection_binder_region_images',
                    'preview_my_binder_insert_gap', 'insert_my_binder_gap', 'close_my_binder_gap',
                    'binder_layout_lock_for_collection', 'binder_image_file_check', 'binder_region_lock_in_layout',
                    'binder_gap_chain', 'binder_gap_evaluate', 'binder_gap_move_pocket', 'binder_gap_undo_token')
order by p.proname;
-- Esperado: 15 linhas; prosecdef e empty_search_path = true em todas; 8 públicas auth_exec = true;
-- 7 internas auth_exec = false; anon_exec = false em todas.

-- POST-5 Ledger: 5238 → 5243, nesta ordem, uma vez cada.
select version, name from supabase_migrations.schema_migrations
where name ~ '^52(3[89]|4[0-3])_' order by version;

rollback;
