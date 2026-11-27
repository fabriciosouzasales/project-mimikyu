/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5392 - Reversão SEGURA da 5392 (escritas do EDITOR por identificador)
Versão......: 1.1 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5392
              confirmada no LIVE. Nunca depois de uma 5392 abortada (nada persistiu).
Efeito......: remove as 4 RPCs e os 2 ajudantes internos. As 4 escritas da 5380 CONTINUAM
              revogadas: depois desta reversão o EDITOR fica SEM escrita de Pokédex (estado
              seguro). Restaurar a 5380 é uma operação EXCEPCIONAL e separada
              (RESTORE_5380_EXCECAO_5392.sql), nunca parte do rollback.
              Não apaga eventos já gravados (auditoria não é revertida).
Interromper.: para só suspender a funcionalidade sem remover nada, usar o complemento de
              emergência EMERGENCY_STOP_V1_13_ADD_S2.sql (REVOKE, reversível por GRANT).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if to_regprocedure('public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean)') is null
     or to_regprocedure('public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)') is null
     or to_regprocedure('public.v1_13_pokedex_position_in_scope(uuid, uuid)') is null then
    raise exception 'PRECHECK R5392: 5392 ausente ou incompleta — nada a reverter (diagnosticar)';
  end if;
end;
$pre$;

drop function public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean);
drop function public.editor_unassign_pokedex_copy(uuid, text, uuid);
drop function public.editor_choose_pokedex_representative(uuid, text, uuid, text);
drop function public.editor_restore_pokedex_automatic_representative(uuid, uuid, text);
drop function public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid);
drop function public.v1_13_pokedex_position_in_scope(uuid, uuid);

do $post$
begin
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('v1_13_resolve_pokedex_copy', 'v1_13_pokedex_position_in_scope', 'editor_move_pokedex_copy',
                                 'editor_unassign_pokedex_copy', 'editor_choose_pokedex_representative',
                                 'editor_restore_pokedex_automatic_representative')) then
    raise exception 'POSTCHECK R5392: objeto da 5392 ainda presente';
  end if;
  -- Estado seguro: nenhuma escrita da 5380 executável por papel de cliente.
  if exists (select 1 from pg_catalog.pg_roles x
             cross join unnest(array[to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)'),
                                     to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)'),
                                     to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)'),
                                     to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')]) g(oid)
             where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
               and pg_catalog.has_function_privilege(x.oid, g.oid, 'EXECUTE')) then
    raise exception 'POSTCHECK R5392: escrita da 5380 executável — a reversão não pode reativá-la';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a' then
    raise exception 'POSTCHECK R5392: funções do titular alteradas';
  end if;
end;
$post$;

commit;
