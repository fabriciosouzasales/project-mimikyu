/*
================================================================
RECUPERAÇÃO R1 — DERIVADO, NÃO EDITAR À MÃO (controlled-execution/derive_singlecall.py)
Desfaz.....: 5361 (remove FK e coluna condition_code). APAGA as condições gravadas: o PRECHECK recusa se houver qualquer exemplar ≠ NM.
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
set local statement_timeout = '120s';

do $pre$
declare v_non_nm bigint;
begin
  if to_regprocedure('public.set_my_physical_cards_condition(uuid[],text)') is not null or to_regprocedure('public.physical_card_unknown_condition_codes(text[])') is not null then
    raise exception 'PRECHECK R1: rode R4 e R2 antes'; end if;
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.get_my_inventory_item_copies(uuid,text)')) is distinct from 'd8cce43b511856a5e25f061e75a7cede' then
    raise exception 'PRECHECK R1: rode R3 antes'; end if;
  if not exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass and attname = 'condition_code' and not attisdropped) then
    raise exception 'PRECHECK R1: coluna ausente — nada a desfazer'; end if;
  select count(*) into v_non_nm from public.physical_card where condition_code <> 'NM';
  if v_non_nm > 0 then
    raise exception 'PRECHECK R1: % exemplar(es) com condição declarada diferente de NM — desfazer apagaria dado do usuário; exige decisão explícita do proprietário', v_non_nm; end if;
end;
$pre$;

alter table public.physical_card drop constraint fk_physical_card_condition_code;
alter table public.physical_card drop column condition_code;

do $post$
begin
  if exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass and attname = 'condition_code' and not attisdropped)
     or exists (select 1 from pg_constraint where conname = 'fk_physical_card_condition_code') then
    raise exception 'POSTCHECK R1: coluna ou FK ainda existem'; end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;
