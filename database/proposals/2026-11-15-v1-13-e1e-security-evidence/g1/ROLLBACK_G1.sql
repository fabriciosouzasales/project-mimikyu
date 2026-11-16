/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_G1 — reversão da barreira 5389 (V1-13 · D-E1 · G1)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com
              autorização. Vem DEPOIS de ROLLBACK_E1D … ROLLBACK_E1A (todas as
              capacidades protegidas removidas): as funções protegidas chamam a
              porta e passariam a falhar sem ela.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Efeito......: remove a porta, o estado e o registro de identidades de teste.
              Recusa se qualquer capacidade protegida ainda existir.
              A desabilitação imediata das capacidades NÃO é este script: é o
              modo CLOSED ou EMERGENCY_STOP_V1_13.sql.
================================================================
*/

-- R5389 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
do $pre$
begin
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and (p.proname like 'editor\_%'
                    or p.proname in ('invite_collection_member', 'set_collection_member_role',
                                     'get_shared_binder_placeable_cards', 'get_shared_master_set_positions',
                                     'get_shared_pokedex_positions', 'get_shared_binder_activity',
                                     'get_shared_binder_activity_status', 'collection_cover_editor_folder_ok',
                                     'collection_cover_editor_can_upload'))
               and position('v1_13_' in p.prosrc) > 0) then
    raise exception 'ROLLBACK_G1: ainda há capacidades protegidas que chamam a porta — reverter E1-D … E1-A antes';
  end if;
end;
$pre$;
drop function if exists public.v1_13_assert_capability();
drop function if exists public.v1_13_capability_open();
drop table if exists public.v1_13_barrier_identity;
drop table if exists public.v1_13_barrier_state;
commit;
