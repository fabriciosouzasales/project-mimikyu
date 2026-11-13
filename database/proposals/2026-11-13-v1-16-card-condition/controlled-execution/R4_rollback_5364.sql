/*
================================================================
RECUPERAÇÃO R4 — DERIVADO, NÃO EDITAR À MÃO (controlled-execution/derive_singlecall.py)
Desfaz.....: 5364 (set_my_physical_cards_condition). Condições já gravadas permanecem.
Quando.....: SÓ com decisão explícita do proprietário (ver
             CONTROLLED-EXECUTION-PROTOCOL.md §7). Ordem obrigatória R4 → R1;
             cada R recusa rodar fora de ordem (PRECHECK).
Corpos copiados byte a byte de:
  (nenhum corpo copiado)
Status.....: PREPARADO, NÃO EXECUTADO.
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
declare v_oid oid := to_regprocedure('public.set_my_physical_cards_condition(uuid[],text)');
begin
  if v_oid is null then raise exception 'PRECHECK R4: 5364 ausente — nada a desfazer'; end if;
  if (select md5(prosrc) from pg_proc where oid = v_oid) <> 'b569ecdbe202428a6bdc9461c6d62e37' then
    raise exception 'PRECHECK R4: ESTADO DIVERGENTE — corpo vigente difere da 5364 v1.1'; end if;
  if exists (select 1 from pg_depend d where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then
    raise exception 'PRECHECK R4: há objetos dependentes'; end if;
end;
$pre$;

drop function public.set_my_physical_cards_condition(uuid[], text);

do $post$
begin
  if to_regprocedure('public.set_my_physical_cards_condition(uuid[],text)') is not null then raise exception 'POSTCHECK R4: função ainda existe'; end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;
