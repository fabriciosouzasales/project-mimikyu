-- P3-A — LIVE_00: precheck SÓ LEITURA antes de 5244 → 5245 → 5246 (mimikyu-core).
-- Executado em 2026-10-23 (P3A-BINDER-CONTROL-IDENTITY-LIVE-READINESS-01): todas as linhas PASS.
-- Reexecutar imediatamente antes da aplicação; qualquer FAIL = STOP.
select
  -- ledger: último aplicado é a 5243 e nenhuma 5244–5246
  (select name from supabase_migrations.schema_migrations order by version desc limit 1) = '5243_create_binder_insert_gap_functions' as p01_ledger_tip_5243,
  (select count(*) from supabase_migrations.schema_migrations where name ~ '^524[4-6]') = 0                                            as p02_no_p3a_in_ledger,
  -- objetos novos ainda ausentes
  not exists (select 1 from information_schema.columns where table_schema='public' and table_name='collection_layout'
              and column_name in ('display_name','show_brand_mark'))                                                                   as p03_cols_absent,
  to_regprocedure('public.set_my_binder_identity(uuid, text, boolean)') is null
  and to_regprocedure('public.get_my_binder_identity(uuid)') is null
  and to_regprocedure('public.get_my_binder_occupancy(uuid)') is null
  and to_regprocedure('public.get_my_binder_participants(uuid)') is null                                                               as p04_funcs_absent,
  -- dependências
  to_regclass('public.collection_layout_guest') is not null
  and to_regclass('public.collection_layout_slot_image') is not null
  and to_regclass('public.collection_layout_region_image') is not null
  and to_regclass('public.ix_collection_layout_region_page') is not null
  and to_regclass('public.ix_collection_layout_guest_layout') is not null                                                              as p05_deps_tables_idx,
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'] and not has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.oid in (to_regprocedure('public.assert_collection_layout_mutable(uuid)'),
                                    to_regprocedure('public.binder_slot_image_resolve_layout(uuid)')))                                  as p06_internal_helpers_ok,
  position('collection layout not found' in (select prosrc from pg_proc where oid=to_regprocedure('public.assert_collection_layout_mutable(uuid)'))) > 0
  and position('collection is ARCHIVED' in (select prosrc from pg_proc where oid=to_regprocedure('public.assert_collection_layout_mutable(uuid)'))) > 0 as p07_helper_messages,
  -- tabela-alvo protegida
  (select relrowsecurity from pg_class where oid='public.collection_layout'::regclass)
  and not has_table_privilege('authenticated','public.collection_layout','UPDATE')
  and not has_table_privilege('anon','public.collection_layout','SELECT')                                                              as p08_layout_protected,
  -- nenhuma função/visão depende de collection_layout.* (colunas novas não mudam tokens nem leituras)
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
              and p.prosrc ~* '(to_jsonb|row_to_json|md5)\s*\(\s*l\b|\ml\.\*')
  and not exists (select 1 from pg_views where schemaname='public' and definition ~* 'collection_layout')                             as p09_no_star_dependents,
  -- sem sessão mexendo em fichário agora
  (select count(*) from pg_stat_activity where state <> 'idle' and query ~* 'collection_layout' and pid <> pg_backend_pid()) = 0       as p10_no_active_layout_queries;

-- Baseline de integridade (anotar; o LIVE_90 compara). Valores em 2026-10-23:
-- layouts=1 guests=1 pages=24 slots=216 assignments=155 reservations=158 slot_images=0 regions=1
-- region_images=1 locked=0 allocations=211 layout_md5=2d276f17c8dd8f21905131cc7ece9280
select (select count(*) from public.collection_layout)                       as layouts,
       (select count(*) from public.collection_layout_guest)                 as guests,
       (select count(*) from public.collection_layout_page)                  as pages,
       (select count(*) from public.collection_layout_slot)                  as slots,
       (select count(*) from public.collection_layout_slot_assignment)       as assignments,
       (select count(*) from public.collection_layout_slot_expected_content) as reservations,
       (select count(*) from public.collection_layout_slot_image)            as slot_images,
       (select count(*) from public.collection_layout_region)                as regions,
       (select count(*) from public.collection_layout_region_image)          as region_images,
       (select count(*) from public.collection_layout_slot where locked)     as locked,
       (select count(*) from public.collection_allocation)                   as allocations,
       (select md5(string_agg(id::text||grid_rows||grid_columns||updated_at::text, ',' order by id)) from public.collection_layout) as layout_md5;
