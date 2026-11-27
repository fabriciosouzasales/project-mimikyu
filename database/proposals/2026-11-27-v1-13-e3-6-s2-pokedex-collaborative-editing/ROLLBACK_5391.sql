/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5391 - Reversão da 5391 (época, segredo, identificador, leitura do EDITOR)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só se a
              5391 estiver confirmada no LIVE. NUNCA depois de uma 5391 abortada
              (transação única: nada persistiu, não há o que reverter).
Efeito......: remove tudo o que a 5391 criou. Todos os identificadores opacos
              deixam de existir. Não toca nenhum dado do produto nem as funções de
              participação. Recusa se a 5392 existir (ela depende da 5391).
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
    raise exception 'PRECHECK R5391: 5392 presente — reverter a 5392 antes';
  end if;
  if to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)') is null
     or to_regclass('public.collection_membership_epoch') is null
     or to_regclass('public.v1_13_copy_token_secret') is null then
    raise exception 'PRECHECK R5391: 5391 ausente ou incompleta — nada a reverter (diagnosticar)';
  end if;
end;
$pre$;

lock table public.collection_membership in share row exclusive mode nowait;

drop function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer);
drop trigger trg_collection_membership_epoch on public.collection_membership;
drop function public.collection_membership_epoch_touch();
drop function public.v1_13_pokedex_copy_token(uuid, uuid, bigint);
drop function public.v1_13_editor_membership(uuid);
drop table public.v1_13_copy_token_secret;
drop table public.collection_membership_epoch;
drop sequence public.collection_membership_epoch_seq;

do $post$
begin
  if to_regclass('public.collection_membership_epoch') is not null
     or to_regclass('public.collection_membership_epoch_seq') is not null
     or to_regclass('public.v1_13_copy_token_secret') is not null
     or exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.collection_membership'::regclass and not t.tgisinternal) then
    raise exception 'POSTCHECK R5391: objeto da 5391 ainda presente';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.invite_collection_member(uuid, text, text)')) is distinct from '5a5ea20616ded5b1a8e8bfe0487743ff'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_collection_member_role(uuid, uuid, text)')) is distinct from '840d1e5c3cc55f253a2579eda7b7703d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.respond_collection_invite(uuid, boolean)')) is distinct from '08f28dcd1bce04bcf50ad2077bddeaa7'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_collection_member(uuid, uuid)')) is distinct from '2c267678b7ff711fb47d8f6b2ee8071a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.leave_shared_collection(uuid)')) is distinct from 'da8aeedd4a155794e794757590d86f62' then
    raise exception 'POSTCHECK R5391: funções de participação alteradas';
  end if;
end;
$post$;

commit;
