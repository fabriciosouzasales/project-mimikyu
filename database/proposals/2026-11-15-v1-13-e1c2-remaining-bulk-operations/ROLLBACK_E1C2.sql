/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_E1C2 — reversão de 5384–5387 (V1-13 · E1-C2)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Ordem obrigatória:
              R5387 → R5386 → R5385 → R5384 (inversa da aplicação), cada bloco uma
              transação própria (psql). Vem ANTES de ROLLBACK_E1C.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Efeito......: retira as operações em massa complementares do EDITOR e devolve a
              lista de tipos de evento à da 5381 (cópia literal; md5 b5da9a1258f26e53f31c206c5d5c442b). NÃO
              apaga nada: deslocamentos, posições, reservas, páginas e registros de
              incorporação feitos por EDITOR e os eventos do histórico PERMANECEM
              (estado do fichário e histórico imutável, C-155/C-179).
================================================================
*/

-- R5387 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean);
drop function if exists public.editor_preview_binder_catalog_reconciliation(uuid, text[]);
drop function if exists public.binder_editor_catalog_affected(uuid, uuid, text[]);
commit;

-- R5386 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_apply_binder_auto_arrange(uuid, text);
drop function if exists public.editor_preview_binder_auto_arrange(uuid);
commit;

-- R5385 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer);
drop function if exists public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean);
drop function if exists public.editor_preview_binder_insert_gap(uuid, integer, integer, integer);
drop function if exists public.binder_editor_append_page(uuid);
drop function if exists public.binder_editor_any_foreign(uuid, uuid, uuid[]);
drop function if exists public.editor_binder_exclusive_read(uuid);
commit;

-- R5384 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) is distinct from '78fa0d34dad161eac1165f3143874260' then
    raise exception 'R5384: corpo vigente não é o da 5384 — reversão interrompida';
  end if;
end;
$pre$;

create or replace function public.binder_activity_event_editor_type_guard()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.actor_user_id is not null and new.actor_user_id is distinct from new.owner_user_id then
    if new.event_type not in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                              'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                              'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED')
       or new.source is distinct from 'FICHARIO'
       or new.collection_id is null then
      raise exception 'binder activity: event type not allowed for this actor' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_EVENT_TYPE';
    end if;
  end if;
  return new;
end;
$fn$;

do $post$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) is distinct from 'b5da9a1258f26e53f31c206c5d5c442b' then
    raise exception 'R5384: corpo restaurado diverge da 5381';
  end if;
end;
$post$;
commit;
