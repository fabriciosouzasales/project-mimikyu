/*
================================================================
Projeto.....: Project Mimikyu
Query.......: EMERGENCY_STOP_V1_13 — complemento E2d (E3-7b: 5397)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com autorização.
              Mesmo formato do g1/EMERGENCY_STOP_V1_13.sql (não alterado; a prévia 5386 já está nele).
              Revoga as 2 RPCs novas da 5397 de PUBLIC/anon/authenticated. Não concede nada.
================================================================
*/

-- E2d ------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
revoke execute on function public.get_shared_binder_placeable_copies(uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) from public, anon, authenticated;
commit;
