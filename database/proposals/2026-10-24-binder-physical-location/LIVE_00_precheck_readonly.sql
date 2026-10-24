-- BINDER-PHYSICAL-LOCATION — LIVE_00: precheck SÓ LEITURA antes da FASE A (5247 → 5255) (mimikyu-core).
-- Status: PROPOSTO — NÃO EXECUTADO nesta forma. Os fatos de referência abaixo vêm de leituras
-- read-only de 2026-10-24 (BINDER-AVAILABLE-CARDS-ELIGIBILITY-INVESTIGATION-01 / REDESIGN-01).
-- Rodar imediatamente antes da aplicação; qualquer FAIL = STOP.
select
  -- ledger: P3-A é o topo e nada desta proposta foi aplicado
  (select name from supabase_migrations.schema_migrations order by version desc limit 1) ~ '^5246'           as p01_ledger_tip_5246,
  (select count(*) from supabase_migrations.schema_migrations where name ~ '^(524[7-9]|525[0-6])') = 0         as p02_none_applied,
  -- objetos novos ausentes / antigos presentes
  not exists (select 1 from information_schema.columns where table_schema='public' and table_name='collection_layout' and column_name='storage_container_id')
  and not exists (select 1 from information_schema.columns where table_schema='public' and table_name='collection_layout_slot_assignment' and column_name='physical_card_id') as p03_cols_absent,
  to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)') is null
  and to_regprocedure('public.preview_my_physical_cards_binder_impact(uuid[], uuid)') is null
  and to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)') is null
  and to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)') is null
  and to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)') is null
  and to_regprocedure('public.preview_my_collection_storage_binder_impact(uuid, uuid, text)') is null
  and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)') is null       as p04_new_funcs_absent,
  to_regprocedure('public.set_physical_cards_storage(uuid, uuid[])') is not null
  and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is not null
  and to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)') is not null
  and to_regprocedure('public.get_my_collection_binder(uuid)') is not null
  and to_regprocedure('public.get_my_binder_participants(uuid)') is not null
  and to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)') is not null
  and to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)') is not null
  and to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)') is not null
  and to_regprocedure('public.list_my_binder_join_candidates(uuid)') is not null                             as p05_old_contracts_present,
  position('p2a1-plan-v1' in pg_get_functiondef('public.collection_binder_plan'::regproc)) > 0               as p06_plan_v1,
  -- gatilhos que as migrations substituem/desligam temporariamente
  (select count(*) from pg_trigger where not tgisinternal and tgname in
     ('trg_collection_layout_updated_at','trg_collection_layout_slot_assignment_integrity',
      'trg_collection_layout_slot_assignment_lock','trg_collection_layout_slot_assignment_updated_at',
      'trg_collection_layout_collection_id_immutable')) = 5                                                     as p07_triggers_present,
  -- regra de backfill: proprietária com local padrão BINDER do mesmo dono, sem dois fichários por local
  not exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
              left join public.storage_container sc on sc.id = c.default_storage_container_id
              left join public.inventory i on i.id = sc.inventory_id
              where sc.id is null or sc.kind_code is distinct from 'BINDER' or i.owner_user_id is distinct from c.owner_user_id) as p08_owner_default_binder,
  -- toda posição atual já está no local físico do seu fichário (5248 aborta se não)
  not exists (select 1 from public.collection_layout_slot_assignment a
              join public.collection_allocation ca on ca.id = a.collection_allocation_id
              join public.physical_card pc on pc.id = ca.physical_card_id
              join public.collection_layout_slot s on s.id = a.slot_id
              join public.collection_layout_page p on p.id = s.page_id
              join public.collection_layout l on l.id = p.layout_id
              join public.collection c on c.id = l.collection_id
              where pc.storage_container_id is distinct from c.default_storage_container_id)                  as p09_all_positions_in_binder_location,
  -- registra: hoje nenhum bolso travado
  (select count(*) from public.collection_layout_slot where locked) = 0                                       as p10_no_locked_slots,
  (select count(*) from pg_stat_activity where state <> 'idle' and query ~* 'collection_layout|physical_card' and pid <> pg_backend_pid()) = 0 as p11_no_active_queries;

-- Fatos esperados (2026-10-24): 1 layout 0d550088-b5de-46d0-bc31-3cde93d3e6b7 (proprietária
-- "Celebração de 30 Anos", convidada "Coleção Clássica"); local padrão F001 4f3a9ec2-64bc-40a1-85f3-0fac0ebf5d2d;
-- 155 posições, todas em F001; F001 com 182 exemplares (155 posicionados + 27 "Promo Megaevolução");
-- 158 reservas; 0 travados.
select (select count(*) from public.collection_layout)                       as layouts,
       (select count(*) from public.collection_layout_guest)                 as guests,
       (select count(*) from public.collection_layout_page)                  as pages,
       (select count(*) from public.collection_layout_slot)                  as slots,
       (select count(*) from public.collection_layout_slot_assignment)       as assignments,
       (select count(*) from public.collection_layout_slot_expected_content) as reservations,
       (select count(*) from public.collection_layout_slot where locked)     as locked,
       (select count(*) from public.collection_layout_slot_image)            as slot_images,
       (select count(*) from public.collection_layout_region)                as regions,
       (select count(*) from public.collection_layout_region_image)          as region_images,
       (select count(*) from public.collection_allocation)                   as allocations,
       (select count(*) from public.physical_card pc
         where pc.storage_container_id = '4f3a9ec2-64bc-40a1-85f3-0fac0ebf5d2d')                            as f001_cards,
       -- baseline das posições (o LIVE_90 compara): id, bolso, alocação, updated_at
       (select md5(string_agg(a.id::text||':'||a.slot_id::text||':'||a.collection_allocation_id::text||':'||a.updated_at::text, ',' order by a.id))
          from public.collection_layout_slot_assignment a)                                                    as assignments_md5,
       (select md5(string_agg(id::text||grid_rows||grid_columns||updated_at::text||coalesce(display_name,'')||show_brand_mark::text, ',' order by id))
          from public.collection_layout)                                                                      as layout_md5,
       (select md5(string_agg(id::text||':'||collection_id::text||':'||physical_card_id::text, ',' order by id))
          from public.collection_allocation)                                                                  as allocations_md5;
