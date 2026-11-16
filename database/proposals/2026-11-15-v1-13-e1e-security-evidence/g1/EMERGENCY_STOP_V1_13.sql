/*
================================================================
Projeto.....: Project Mimikyu
Query.......: EMERGENCY_STOP_V1_13 — desligamento emergencial das capacidades
              da V1-13 (D-E1, segunda camada). GERADO por g1/build_g1_protected.py.
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com
              autorização. Não depende da porta 5389 (camada 2).
Blocos......: E1 (camada 1, sem trava): modo CLOSED.
              E2 (camada 2): REVOKE EXECUTE de todas as RPCs novas, exceto o
              convite (compartilhado com a V1-12; contingência: R5369 do
              ROLLBACK_E1A, que devolve a 5303). Titular e VIEWER da V1-12
              não usam nenhuma destas funções.
              E3 (camada 2, Storage): DROP das 3 políticas novas da 5377.
              ACCESS EXCLUSIVE em storage.objects (risco O2): LOCK NOWAIT; se
              55P03, repetir em janela. NÃO revogar EXECUTE dos ajudantes:
              a avaliação das políticas falharia para TODOS os usuários do
              bucket (inclusive o titular).
Limites.....: não cancela chamadas em curso (encerrar as sessões pelo painel ou
              pg_cancel_backend, decisão do operador); não desfaz o que já foi
              gravado; mudanças compartilhadas (5366, 5368, 5369, 5372/5379,
              5381/5384) só saem pelos ROLLBACK_E1x.
================================================================
*/

-- E1 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
update public.v1_13_barrier_state set mode = 'CLOSED', changed_at = now(), change_note = 'EMERGENCY_STOP E1' where id = 1;
commit;

-- E2 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
revoke execute on function public.set_collection_member_role(UUID, UUID, TEXT) from public, anon, authenticated;
revoke execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) from public, anon, authenticated;
revoke execute on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_remove_binder_card(uuid, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) from public, anon, authenticated;
revoke execute on function public.editor_update_collection_metadata(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.editor_set_collection_cover_finish(uuid, text) from public, anon, authenticated;
revoke execute on function public.editor_set_collection_cover_code(uuid, text) from public, anon, authenticated;
revoke execute on function public.editor_set_collection_cover_logo(uuid, text) from public, anon, authenticated;
revoke execute on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.editor_remove_pokedex_position_assignment(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.editor_add_binder_page(uuid) from public, anon, authenticated;
revoke execute on function public.editor_remove_binder_page(uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_reorder_binder_pages(uuid, integer[]) from public, anon, authenticated;
revoke execute on function public.editor_preview_binder_species_references(uuid) from public, anon, authenticated;
revoke execute on function public.editor_apply_binder_species_references(uuid, text) from public, anon, authenticated;
revoke execute on function public.editor_clear_binder_species_references(uuid, integer) from public, anon, authenticated;
revoke execute on function public.editor_set_binder_species_reference_visibility(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) from public, anon, authenticated;
revoke execute on function public.editor_preview_binder_auto_arrange(uuid) from public, anon, authenticated;
revoke execute on function public.editor_apply_binder_auto_arrange(uuid, text) from public, anon, authenticated;
revoke execute on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) from public, anon, authenticated;
revoke execute on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.get_shared_master_set_positions(uuid, text, integer, integer) from public, anon, authenticated;
revoke execute on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) from public, anon, authenticated;
revoke execute on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) from public, anon, authenticated;
revoke execute on function public.get_shared_binder_activity_status(uuid) from public, anon, authenticated;
commit;

-- E3 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '2s';
lock table storage.objects in access exclusive mode nowait;
drop policy if exists collection_cover_insert_editor on storage.objects;
drop policy if exists collection_cover_select_editor on storage.objects;
drop policy if exists collection_cover_delete_editor on storage.objects;
commit;
