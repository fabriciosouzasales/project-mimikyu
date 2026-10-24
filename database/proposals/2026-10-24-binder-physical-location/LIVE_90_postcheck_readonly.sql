-- BINDER-PHYSICAL-LOCATION — LIVE_90: postcheck SÓ LEITURA depois da FASE B (5256) (mimikyu-core).
-- Status: PROPOSTO — NÃO EXECUTADO. Qualquer FAIL = R1 (desfaz só a fase B; README §5).
select
  (select count(*) from supabase_migrations.schema_migrations where name ~ '^(524[7-9]|525[0-6])') = 10         as q01_ledger_10,
  exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard' and tgenabled = 'O') as q02_guard_enabled,
  (select bool_and(not has_function_privilege('authenticated', p.oid, 'EXECUTE') and p.proconfig @> array['search_path=""'])
     from pg_proc p where p.proname = 'binder_position_guard_on_storage_change')                              as q03_guard_fn_private,
  to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is null
  and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)') is not null   as q04_unplaced_contracted,
  -- 5024/5222 originais continuam (protegidas pelo gatilho)
  to_regprocedure('public.set_physical_cards_storage(uuid, uuid[])') is not null
  and to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)') is not null    as q05_legacy_writers_guarded,
  not exists (select 1 from public.collection_layout_slot_assignment a
              join public.physical_card pc on pc.id = a.physical_card_id
              join public.collection_layout_slot s on s.id = a.slot_id
              join public.collection_layout_page p on p.id = s.page_id
              join public.collection_layout l on l.id = p.layout_id
              where pc.storage_container_id is distinct from l.storage_container_id)                         as q06_positions_inside_location,
  not exists (select 1 from public.collection_layout_slot_assignment where physical_card_id is null)            as q07_positions_have_card;

-- Conferência com LIVE_00/LIVE_50 (posições só mudam por uso real do colecionador entre as fases):
select (select count(*) from public.collection_layout_slot_assignment) as assignments,
       (select count(*) from public.collection_layout_slot_expected_content) as reservations,
       (select count(*) from public.collection_layout_slot_image)            as slot_images,
       (select count(*) from public.collection_layout_region)                as regions,
       (select count(*) from public.collection_allocation)                   as allocations;

-- Homologação pela interface (frontend novo publicado): abrir o fichário pela proprietária →
-- "Cartas disponíveis" com "Todas" selecionado lista 27 (incl. Mudkip MEP 057, origem
-- "Promo Megaevolução"); filtros Desta coleção / Outras coleções / Sem coleção; posicionar o
-- Mudkip; Desfazer; mover pelo Meu acervo um exemplar posicionado → aviso + confirmação;
-- Organizar armazenamento com carta posicionada → aviso com a quantidade; contracapa e Centro
-- de Controle inalterados.
