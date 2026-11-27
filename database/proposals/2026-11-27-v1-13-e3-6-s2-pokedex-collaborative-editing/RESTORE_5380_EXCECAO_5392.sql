/*
================================================================
Projeto.....: Project Mimikyu
Query.......: X5392 - RESTAURAÇÃO EXCEPCIONAL do EXECUTE das 4 escritas da 5380
Versão......: 1.0 (2026-11-27)
Status......: EXCEÇÃO — NÃO É ROLLBACK, NÃO EXECUTAR SEM AUTORIZAÇÃO ESPECÍFICA E ESCRITA DO
              TITULAR PARA ESTE ARQUIVO. Reintroduz o caminho de escrita do EDITOR por
              physical_card_id, SEM estado esperado e SEM registro explícito de auditoria
              (só a captura agregada da 5394). Só se aplica com a 5392 AUSENTE (depois do
              ROLLBACK_5392) e a barreira CLOSED; conferir "acl_5380" no PRE da 5392 antes
              (service_role só se constava).
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
    raise exception 'PRECHECK X5392: 5392 presente — não manter dois caminhos de escrita do EDITOR';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED' then
    raise exception 'PRECHECK X5392: barreira não está CLOSED';
  end if;
end;
$pre$;

grant execute on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.editor_remove_pokedex_position_assignment(uuid, uuid) to authenticated;
grant execute on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) to authenticated;
grant execute on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) to authenticated;

commit;
