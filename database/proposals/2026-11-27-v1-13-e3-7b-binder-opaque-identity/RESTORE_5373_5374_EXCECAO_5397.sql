/*
================================================================
Projeto.....: Project Mimikyu
Query.......: RESTORE-5373/5374 — EXCEÇÃO à 5397 (reabre o contrato com physical_card_id)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Uso EXCEPCIONAL, com decisão e autorização próprias: REABRE o P0.
Exige.......: 5397 ausente (revertida) e barreira CLOSED. Só os 2 GRANTs da 5373/5374 originais.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is not null
     or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED' then
    raise exception 'PRECHECK RESTORE: exige 5397 revertida e barreira CLOSED';
  end if;
end;
$pre$;

grant execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) to authenticated;
grant execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) to authenticated;

commit;
