-- P3-A — LIVE_90: postcheck SÓ LEITURA depois de 5244 → 5245 → 5246 (mimikyu-core).
-- Rodar após CADA migration o bloco correspondente (A após 5244, B após 5245, C após 5246) e, no fim, D.
-- Qualquer FALSE = STOP (não aplicar a próxima; avaliar R0).

-- A — 5244
select
  (select count(*) from information_schema.columns where table_schema='public' and table_name='collection_layout'
     and column_name in ('display_name','show_brand_mark')) = 2                                                    as a1_cols,
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='collection_layout'
     and column_name='show_brand_mark' and is_nullable='NO' and column_default='true')                             as a2_mark_default,
  exists (select 1 from pg_constraint where conrelid='public.collection_layout'::regclass
     and conname='chk_collection_layout_display_name_format' and convalidated)                                     as a3_check,
  (select count(*) from public.collection_layout where display_name is not null or show_brand_mark is not true) = 0 as a4_no_data_change,
  (select md5(string_agg(id::text||grid_rows||grid_columns||updated_at::text, ',' order by id)) from public.collection_layout)
     = '2d276f17c8dd8f21905131cc7ece9280'                                                                          as a5_layout_rows_untouched,
  not has_table_privilege('authenticated','public.collection_layout','UPDATE')                                     as a6_still_no_dml,
  (select count(*) from supabase_migrations.schema_migrations where name='5244_add_collection_layout_identity') = 1 as a7_ledger;

-- B — 5245 (e C — 5246: incluir get_my_binder_participants)
select p.proname,
       p.prosecdef                                             as definer,
       p.proconfig @> array['search_path=""']                  as empty_path,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,   -- true
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_exec,   -- false
       not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0) as no_public,
       case p.proname when 'set_my_binder_identity' then p.proconfig @> array['lock_timeout=5s'] else true end as lock_timeout_ok
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('set_my_binder_identity','get_my_binder_identity','get_my_binder_occupancy','get_my_binder_participants')
order by 1;
-- Esperado: 3 linhas após 5245, 4 após 5246; definer/empty_path/auth_exec/no_public/lock_timeout_ok = true; anon_exec = false.
-- Ledger: 5245_create_binder_identity_functions e 5246_create_get_my_binder_participants presentes (1 cada).

-- D — final: dados intocados (comparar com o baseline do LIVE_00) e nenhuma chamada anônima possível
select (select count(*) from public.collection_layout)                       = 1   as d1_layouts,
       (select count(*) from public.collection_layout_guest)                 = 1   as d2_guests,
       (select count(*) from public.collection_layout_page)                  = 24  as d3_pages,
       (select count(*) from public.collection_layout_slot)                  = 216 as d4_slots,
       (select count(*) from public.collection_layout_slot_assignment)       = 155 as d5_assignments,
       (select count(*) from public.collection_layout_slot_expected_content) = 158 as d6_reservations,
       (select count(*) from public.collection_layout_region)                = 1   as d7_regions,
       (select count(*) from public.collection_layout_region_image)          = 1   as d8_region_images,
       (select count(*) from public.collection_allocation)                   = 211 as d9_allocations;
-- Se o usuário usar o fichário entre o precheck e o postcheck, as contagens podem mudar legitimamente:
-- nesse caso comparar com uma releitura imediatamente anterior à 5244, não com estes números.
-- Depois: Security Advisor — esperado +4 avisos 0029 (authenticated_security_definer_function_executable),
-- o mesmo aceito para todas as RPCs do app; nenhum 0028 (anon) e nenhum 0011 (search_path) novo.
