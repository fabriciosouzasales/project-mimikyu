/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5394 - Reversão da 5394 (histórico por coleção da Pokédex)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5394
              confirmada no LIVE. Nunca depois de uma 5394 abortada (nada persistiu).
Efeito......: remove os 7 gatilhos, as 9 funções e a tabela. Recusa se a 5392 existir
              (ela registra por estas primitivas) ou se houver eventos gravados — apagar
              histórico de auditoria exige decisão própria do proprietário, não rollback.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('editor_move_pokedex_copy', 'editor_unassign_pokedex_copy',
                                 'editor_choose_pokedex_representative', 'editor_restore_pokedex_automatic_representative')) then
    raise exception 'PRECHECK R5394: 5392 presente — reverter a 5392 antes';
  end if;
  if to_regclass('public.collection_activity_event') is null then
    raise exception 'PRECHECK R5394: 5394 ausente — nada a reverter (diagnosticar)';
  end if;
  if exists (select 1 from public.collection_activity_event) then
    raise exception 'PRECHECK R5394: há eventos de auditoria gravados — STOP (decisão do proprietário)';
  end if;
end;
$pre$;

lock table public.collection_allocation in share row exclusive mode nowait;
lock table public.collection_pokedex_position_assignment in share row exclusive mode nowait;
lock table public.collection_pokedex_position_primary_representative in share row exclusive mode nowait;

drop trigger trg_900_collection_activity_deallocation on public.collection_allocation;
drop trigger trg_900_collection_activity_assignment_insert on public.collection_pokedex_position_assignment;
drop trigger trg_900_collection_activity_assignment_delete on public.collection_pokedex_position_assignment;
drop trigger trg_900_collection_activity_representative_insert on public.collection_pokedex_position_primary_representative;
drop trigger trg_900_collection_activity_representative_update on public.collection_pokedex_position_primary_representative;
drop trigger trg_900_collection_activity_representative_delete on public.collection_pokedex_position_primary_representative;
drop table public.collection_activity_event;
drop function public.collection_activity_event_guard();
drop function public.collection_activity_open(uuid);
drop function public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean);
drop function public.collection_activity_derived_add(uuid, integer, integer, integer, integer);
drop function public.collection_activity_capture_assignment_insert();
drop function public.collection_activity_capture_assignment_delete();
drop function public.collection_activity_capture_representative_set();
drop function public.collection_activity_capture_representative_delete();
drop function public.collection_activity_capture_deallocation();

do $post$
begin
  if to_regclass('public.collection_activity_event') is not null
     or exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname like 'collection_activity\_%')
     or exists (select 1 from pg_catalog.pg_trigger t where not t.tgisinternal and t.tgname like 'trg\_900\_collection\_activity\_%') then
    raise exception 'POSTCHECK R5394: objeto da 5394 ainda presente';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'POSTCHECK R5394: funções do titular alteradas';
  end if;
end;
$post$;

commit;
