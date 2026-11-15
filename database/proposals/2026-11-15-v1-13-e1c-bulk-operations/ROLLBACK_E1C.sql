/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_E1C — reversão de 5381–5383 (V1-13 · E1-C)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Ordem obrigatória:
              R5383 → R5382 → R5381 (inversa da aplicação), cada bloco uma
              transação própria (psql). Vem ANTES de ROLLBACK_E1B3.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Efeito......: retira as capacidades do EDITOR (páginas e referências de espécie) e
              o gatilho de tipos de evento. NÃO apaga nada: páginas, referências e
              preferências gravadas por EDITOR e os eventos do histórico
              PERMANECEM (estado do fichário e histórico imutável, C-155/C-179).
              Sem o gatilho (R5381), a gravação continua exigindo EDITOR ativo da
              coleção do evento (5372) e itens da coleção (5379).
================================================================
*/

-- R5383 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_set_binder_species_reference_visibility(uuid, boolean);
drop function if exists public.editor_clear_binder_species_references(uuid, integer);
drop function if exists public.editor_apply_binder_species_references(uuid, text);
drop function if exists public.editor_preview_binder_species_references(uuid);
drop function if exists public.editor_species_reference_target_locked(uuid);
drop function if exists public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid);
commit;

-- R5382 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_reorder_binder_pages(uuid, integer[]);
drop function if exists public.editor_remove_binder_page(uuid, integer, integer);
drop function if exists public.editor_add_binder_page(uuid);
drop function if exists public.assert_collection_binder_editor_exclusive(uuid);
commit;

-- R5381 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop trigger if exists trg_bae_editor_event_type on public.binder_activity_event;
drop function if exists public.binder_activity_event_editor_type_guard();
commit;
