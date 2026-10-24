-- BINDER-PHYSICAL-LOCATION — R0: diagnóstico SÓ LEITURA para recuperação após ativação (mimikyu-core).
-- Status: PROPOSTO — NÃO EXECUTADO. Nenhuma escrita; seguro a qualquer momento.
-- Responde: qual nível de recuperação é admissível agora (README §5)?
--   N1 operacional (frontend anterior [+ R1])  → sempre
--   N2 rollback de contratos (R2A)              → sempre (exige R1 se a 5256 existir)
--   N3 rollback do modelo de dados (R2B)        → só se d03 = 0 e d04 = 0
--   senão                                      → correção posterior (migration nova, para frente)

select
  exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard')   as d01_phase_b_active,
  to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)') is not null     as d02_phase_a_contracts_present,
  -- posições que o modelo antigo NÃO representa (bloqueiam R2B):
  (select count(*) from public.collection_layout_slot_assignment a
     left join public.collection_allocation ca on ca.id = a.collection_allocation_id
    where ca.id is null or ca.physical_card_id <> a.physical_card_id)                          as d03_positions_without_allocation,
  (select count(*) from public.collection_layout_slot_assignment a
     join public.collection_allocation ca on ca.id = a.collection_allocation_id
     join public.collection_layout_slot s on s.id = a.slot_id
     join public.collection_layout_page p on p.id = s.page_id
     join public.collection_layout l on l.id = p.layout_id
    where ca.collection_id <> l.collection_id
      and not exists (select 1 from public.collection_layout_guest g
                      where g.layout_id = l.id and g.collection_id = ca.collection_id))         as d04_positions_non_participant,
  -- posições fora do local físico do fichário (bloqueiam a 5256; indicam movimento pelo frontend antigo):
  (select count(*) from public.collection_layout_slot_assignment a
     join public.physical_card pc on pc.id = a.physical_card_id
     join public.collection_layout_slot s on s.id = a.slot_id
     join public.collection_layout_page p on p.id = s.page_id
     join public.collection_layout l on l.id = p.layout_id
    where pc.storage_container_id is distinct from l.storage_container_id)                    as d05_positions_outside_location,
  (select count(*) from public.collection_layout_slot_assignment)                              as d06_positions_total;

-- Detalhe dos casos que bloqueiam R2B (ids técnicos; sem dados pessoais além do dono do fichário):
select a.id as assignment_id, a.slot_id, a.physical_card_id, a.collection_allocation_id,
       ca.collection_id as card_collection_id, l.id as layout_id, l.collection_id as owner_collection_id,
       case when ca.id is null then 'SEM_COLECAO'
            when ca.physical_card_id <> a.physical_card_id then 'ALOCACAO_DIVERGENTE'
            else 'COLECAO_NAO_PARTICIPANTE' end as motivo
from public.collection_layout_slot_assignment a
left join public.collection_allocation ca on ca.id = a.collection_allocation_id
join public.collection_layout_slot s on s.id = a.slot_id
join public.collection_layout_page p on p.id = s.page_id
join public.collection_layout l on l.id = p.layout_id
where ca.id is null
   or ca.physical_card_id <> a.physical_card_id
   or (ca.collection_id <> l.collection_id
       and not exists (select 1 from public.collection_layout_guest g
                       where g.layout_id = l.id and g.collection_id = ca.collection_id))
order by l.id, p.page_number, s.row_index, s.column_index
limit 500;
