/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5397 - Reversão SEGURA da 5397 (GERADA por build_5397.py)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5397 confirmada.
Efeito......: remove get_shared_binder_placeable_copies e editor_place_copy_in_binder; restaura o
              texto canônico da prévia 5386. As antigas 5373/5374 CONTINUAM REVOGADAS: o EDITOR fica
              sem colocar carta (estado seguro, sem reabrir o P0). Reabri-las é exceção separada
              (RESTORE_5373_5374_EXCECAO_5397.sql), nunca parte da reversão.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)')) is distinct from '1c544a74420bdbcdebacdf0168c3d7f0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)')) is distinct from '09ea8105066f51e519c78f1149e7b9e4'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)')) is distinct from 'ba412a9ce16502e211bdac89f5146163' then
    raise exception 'PRECHECK R5397: 5397 ausente ou divergente — nada a reverter (diagnosticar)';
  end if;
end;
$pre$;

drop function public.get_shared_binder_placeable_copies(uuid, integer, integer);
drop function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text);

create or replace function public.editor_preview_binder_auto_arrange(p_collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  c_limit  constant integer := 500;
  r        record;
  v_mode   text;
  v_policy text;
  v_slots  uuid[];
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select * into r from public.editor_binder_exclusive_read(p_collection_id) x;
  select c.mode, c.completion_policy into v_mode, v_policy from public.collection c where c.id = p_collection_id;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select array_agg(h.slot_id) filter (where h.item_kind = 'INSERT') into v_slots
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id, v_slots) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a organização alcançaria bolsos que só o titular pode alterar';
  end if;

  return (
    with plan as materialized (
      select * from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id)
    ),
    h as (
      select p.insert_count as n, p.plan_token as t,
             case when p.insert_count = 0 then 'EMPTY'
                  when p.insert_count > c_limit then 'LIMIT_EXCEEDED'
                  else 'READY' end as st
      from plan p where p.item_kind = 'HEADER'
    )
    select jsonb_build_object(
      'status',         h.st,
      'insert_count',   h.n,
      'limit',          c_limit,
      'plan_token',     h.t,
      'excluded_cards', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'EXCLUDED_CARD' group by p.reason) x), '{}'::jsonb),
      'unfilled_slots', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'UNFILLED_SLOT' group by p.reason) x), '{}'::jsonb),
      'unfilled_count', (select count(*) from plan p where p.item_kind = 'UNFILLED_SLOT'),
      'pages',          coalesce((select jsonb_agg(distinct p.page_number order by p.page_number)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb),
      'items',          case when h.st = 'LIMIT_EXCEEDED' then '[]'::jsonb
                             else coalesce((select jsonb_agg(jsonb_build_object(
                                     'ord', p.ord, 'physical_card_id', p.physical_card_id,
                                     'page_number', p.page_number, 'row_index', p.row_index,
                                     'column_index', p.column_index, 'card_id', p.card_id,
                                     'card_variant_id', p.card_variant_id) order by p.ord)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb) end
    )
    from h
  );
end;
$fn$;

do $post$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)')) is distinct from '0cb490ec67f551d0044226ab3c34fda1'
     or to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is not null then
    raise exception 'POSTCHECK R5397: reversão incompleta';
  end if;
  if not (not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)'), 'EXECUTE')))
     or not (not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'), 'EXECUTE'))) then
    raise exception 'POSTCHECK R5397: a reversão não pode reabrir o contrato com physical_card_id';
  end if;
end;
$post$;

commit;
