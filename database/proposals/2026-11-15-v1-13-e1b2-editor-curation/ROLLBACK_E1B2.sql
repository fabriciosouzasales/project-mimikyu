/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_E1B2 — reversão de 5375–5377 (V1-13 · E1-B2)
Versão......: 1.1 (5377 v1.1: dois ajudantes de Storage)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Ordem obrigatória:
              R5377 → R5376 → R5375, cada bloco uma transação própria (psql).
              Não toca a E1-B1 nem a E1-A (ROLLBACK_E1B1/ROLLBACK_E1A vêm
              depois, se necessário).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Efeito......: retira as capacidades do EDITOR. Reservas, fixações, metadados e
              capas gravados por EDITOR PERMANECEM (estado da coleção e do
              fichário, C-155); eventos do histórico permanecem (C-179). Arquivos
              de capa enviados por EDITOR na pasta do titular PERMANECEM: o titular
              os vê e apaga pelas políticas do dono (5176).
================================================================
*/

-- R5377 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop policy if exists collection_cover_insert_editor on storage.objects;
drop policy if exists collection_cover_select_editor on storage.objects;
drop policy if exists collection_cover_delete_editor on storage.objects;
drop function if exists public.collection_cover_editor_can_upload(text);
drop function if exists public.collection_cover_editor_folder_ok(text);
commit;

-- R5376 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_update_collection_metadata(uuid, text, text);
drop function if exists public.editor_set_collection_cover_finish(uuid, text);
drop function if exists public.editor_set_collection_cover_code(uuid, text);
drop function if exists public.editor_set_collection_cover_logo(uuid, text);
drop function if exists public.assert_collection_editor(uuid);
commit;

-- R5375 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid);
drop function if exists public.editor_clear_binder_reservation(uuid, integer, integer, integer);
drop function if exists public.editor_set_binder_lock(uuid, integer, integer, integer, boolean);
commit;
