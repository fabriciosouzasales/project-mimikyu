/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5398 - Reversão da 5398 (remove a leitura de autoria do titular)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e com a 5398 confirmada.
Efeito......: a tela volta a não mostrar o autor no histórico do fichário do titular (estado anterior).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])')) is distinct from 'f395a0f109b760a863e8e00832c177b6' then
    raise exception 'PRECHECK R5398: 5398 ausente ou divergente';
  end if;
end;
$pre$;

drop function public.get_my_binder_activity_actors(uuid, bigint[]);

do $post$
begin
  if to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])') is not null then
    raise exception 'POSTCHECK R5398: função ainda existe';
  end if;
end;
$post$;

commit;
