-- P2-BINDER-LAYOUT-CUSTOMIZATION — R1-pré (SOMENTE LEITURA). NÃO EXECUTADO.
-- Rodar com o mesmo papel que fará o W1 (esperado: postgres). Um bloco por vez.

begin transaction read only;

-- PRE-1 Ledger: nada desta proposta aplicado; dependências presentes.
select
  not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^52(3[89]|4[0-3])_') as p1_none_applied,
  exists (select 1 from supabase_migrations.schema_migrations where name like '5237_%')            as p1_5237_present;

-- PRE-2 Objetos novos ausentes (todos devem ser true).
select
  to_regclass('public.collection_layout_region_image') is null                                       as t_region_image_absent,
  to_regprocedure('public.enforce_slot_outside_layout_region()') is null                             as f_guard_absent,
  to_regprocedure('public.merge_my_binder_slots_with_image(uuid, uuid, text, smallint, smallint)') is null as f_merge_absent,
  to_regprocedure('public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)') is null         as f_gap_absent;

-- PRE-3 Estado de dados que as proteções pressupõem (esperado: 0 | 0 | 0).
select
  (select count(*) from public.collection_layout_region)                                             as regions_total,
  (select count(*) from public.collection_layout_region r
     join public.collection_layout_slot s on s.page_id = r.page_id
      and s.row_index between r.top_row and r.top_row + r.height - 1
      and s.column_index between r.left_column and r.left_column + r.width - 1
    where s.locked
       or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
       or exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)) as region_slots_with_content,
  (select count(*) from public.collection_layout_slot_image)                                         as slot_images;

-- PRE-4 Superfície de privilégio atual (registrar; 5238 muda as 2 primeiras para false).
select
  has_function_privilege('authenticated', 'public.merge_layout_region(uuid, integer, integer, integer, integer)', 'EXECUTE') as merge_exec_auth,
  has_function_privilege('authenticated', 'public.unmerge_layout_region(uuid)', 'EXECUTE')                                as unmerge_exec_auth,
  has_function_privilege('authenticated', 'public.binder_slot_image_path_is_linked(text)', 'EXECUTE')                    as linked_exec_auth,
  has_function_privilege('anon',          'public.binder_slot_image_path_is_linked(text)', 'EXECUTE')                    as linked_exec_anon;

-- PRE-5 A política DELETE do bucket delega à função (premissa da 5239) + fingerprint de TODAS as políticas de storage.objects.
select
  exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
          and policyname = 'binder_slot_image_delete_own' and cmd = 'DELETE'
          and qual like '%binder_slot_image_path_is_linked%')                                       as delete_policy_delegates,
  md5(string_agg(policyname || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by policyname)) as fp_storage_policies
from pg_policies where schemaname = 'storage' and tablename = 'objects';

-- PRE-6 Corpo atual das 3 funções que a 5239 substitui (registrar md5 para o diff).
select p.proname, md5(pg_get_functiondef(p.oid)) as md5_def, pg_get_function_result(p.oid) as result
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('binder_slot_image_path_is_linked', 'list_my_unlinked_binder_slot_images',
                    'get_my_binder_slot_image_summary', 'dismantle_my_collection_binder',
                    'preview_my_collection_binder_dismantle')
order by p.proname;

-- PRE-7 Sem transação longa nem trava nas tabelas do fichário.
select count(*) filter (where xact_start < now() - interval '1 minute' and state <> 'idle') as long_tx
from pg_stat_activity where datname = current_database();

rollback;
