-- BINDER-PHYSICAL-LOCATION — LIVE_50: checagem SÓ LEITURA depois da FASE A (5247 → 5255),
-- ANTES do deploy do frontend e da FASE B (5256) (mimikyu-core).
-- Status: PROPOSTO — NÃO EXECUTADO. Qualquer FAIL = parar e decidir (R0 → R2A/R2B, README §5).
-- Rodar duas vezes: (1) logo após a fase A; (2) logo antes da 5256, depois do deploy
-- do frontend (q05 detecta posição criada fora do local na janela).
select
  (select count(*) from supabase_migrations.schema_migrations where name ~ '^(524[7-9]|525[0-5])') = 9          as q01_ledger_phase_a_9,
  (select count(*) from supabase_migrations.schema_migrations where name ~ '^5256') = 0                         as q02_phase_b_absent,
  -- compatibilidade: tudo o que o frontend atual chama continua existindo, mesma assinatura
  to_regprocedure('public.set_physical_cards_storage(uuid, uuid[])') is not null
  and to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)') is not null
  and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is not null
  and to_regprocedure('public.assign_card_to_slot(uuid, uuid)') is not null
  and to_regprocedure('public.get_my_collection_binder(uuid)') is not null
  and to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)') is not null           as q03_old_contracts_present,
  -- contratos novos do frontend novo
  to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)') is not null
  and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)') is not null
  and to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)') is not null
  and to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)') is not null
  and to_regprocedure('public.preview_my_physical_cards_binder_impact(uuid[], uuid)') is not null
  and to_regprocedure('public.preview_my_collection_storage_binder_impact(uuid, uuid, text)') is not null
  and to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)') is not null                         as q04_new_contracts_present,
  -- pré-condição da 5256: nenhuma posição fora do local do seu fichário
  not exists (select 1 from public.collection_layout_slot_assignment a
              join public.physical_card pc on pc.id = a.physical_card_id
              join public.collection_layout_slot s on s.id = a.slot_id
              join public.collection_layout_page p on p.id = s.page_id
              join public.collection_layout l on l.id = p.layout_id
              where pc.storage_container_id is distinct from l.storage_container_id)                         as q05_positions_inside_location,
  -- identidade física e backfill
  (select l.storage_container_id = '4f3a9ec2-64bc-40a1-85f3-0fac0ebf5d2d' from public.collection_layout l
    where l.id = '0d550088-b5de-46d0-bc31-3cde93d3e6b7')                                                      as q06_layout_is_f001,
  not exists (select 1 from public.collection_layout_slot_assignment where physical_card_id is null)
  and not exists (select 1 from public.collection_layout_slot_assignment a
                  join public.collection_allocation ca on ca.id = a.collection_allocation_id
                  where ca.physical_card_id <> a.physical_card_id)                                              as q07_positions_backfilled,
  -- ACL das RPCs novas
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""']
                   and has_function_privilege('authenticated', p.oid, 'EXECUTE')
                   and not has_function_privilege('anon', p.oid, 'EXECUTE'))
     from pg_proc p where p.oid in (
       to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)'),
       to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)'),
       to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)'),
       to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)'),
       to_regprocedure('public.preview_my_physical_cards_binder_impact(uuid[], uuid)'),
       to_regprocedure('public.preview_my_collection_storage_binder_impact(uuid, uuid, text)'),
       to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)')))                                   as q08_acl,
  -- elegibilidade nova: os 27 exemplares sem bolso guardados em F001 (incl. Mudkip MEP 057)
  (select count(*) from public.physical_card pc
    where pc.storage_container_id = '4f3a9ec2-64bc-40a1-85f3-0fac0ebf5d2d'
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)) = 27 as q09_available_27;

-- Comparar com o LIVE_00 (devem coincidir exatamente na 1ª execução):
select (select count(*) from public.collection_layout_slot_assignment) as assignments,
       (select md5(string_agg(a.id::text||':'||a.slot_id::text||':'||a.collection_allocation_id::text||':'||a.updated_at::text, ',' order by a.id))
          from public.collection_layout_slot_assignment a)                 as assignments_md5,
       (select md5(string_agg(id::text||grid_rows||grid_columns||updated_at::text||coalesce(display_name,'')||show_brand_mark::text, ',' order by id))
          from public.collection_layout)                                   as layout_md5,
       (select md5(string_agg(id::text||':'||collection_id::text||':'||physical_card_id::text, ',' order by id))
          from public.collection_allocation)                               as allocations_md5,
       (select count(*) from public.collection_layout_slot_expected_content) as reservations,
       (select count(*) from public.collection_layout_slot_image)            as slot_images,
       (select count(*) from public.collection_layout_region)                as regions;
