/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5397 - Identidade opaca no fichário compartilhado do EDITOR (V1-13 · E3-7b, P0)
Versão......: 1.0 (2026-11-27, `E3-7b — BINDER OPAQUE IDENTITY / P0 PRIVACY CORRECTION-01`)
Status......: PROPOSTA — NÃO EXECUTADA. GERADA por build_5397.py a partir do texto canônico
              implantado (versões protegidas G1). Execução só com PRE aprovado, expectativas de
              inventário, auditoria independente e autorização expressa, pelo executor por arquivo.
Autor.......: Fabrício Sales / Claude
Problema....: 5373 devolvia physical_card_id ao EDITOR; 5386 devolvia physical_card_id no JSON da prévia;
              5374 aceitava physical_card_id para colocar (e desfazer). Identificador global e estável
              do exemplar do titular — sem autoridade, mas vazamento de identidade patrimonial.
Corrige.....: - CRIA get_shared_binder_placeable_copies(uuid, integer, integer): mesma leitura da 5373,
                copy_token no lugar de physical_card_id;
              - CRIA editor_place_copy_in_binder(uuid, integer, integer, integer, text): mesmo
                comportamento da 5374 (colocar/substituir/UNCHANGED, travas, elegibilidade, evento),
                com o exemplar por token; token inválido/obsoleto → PHYSICAL_CARD_NOT_ELIGIBLE (P0002);
              - CREATE OR REPLACE editor_preview_binder_auto_arrange(uuid): itens sem 'physical_card_id'
                (card_id e card_variant_id ficam: catálogo público); plano e token do plano inalterados;
              - REVOGA de PUBLIC/anon/authenticated/service_role as antigas 5373 e 5374 (permanecem
                no banco para o STOP de emergência G1 e para a reversão).
Token.......: o MESMO da 5391 ('pc1.' + HMAC-SHA256(alocação|participação|época)), resolvido pelo
              MESMO ajudante interno da 5392 — limitado à coleção e à participação EDITOR ACTIVE,
              invalidado por mudança de participação ou época. Não concede permissão nova.
Reversão....: ROLLBACK_5397.sql (remove as novas e restaura a prévia; as antigas ficam REVOGADAS —
              estado seguro). Reabrir as antigas é exceção separada: RESTORE_5373_5374_EXCECAO_5397.sql.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5397: barreira não está CLOSED';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)')) is distinct from '8e9bf913f422eb60fb4dfc82f8741328'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)')) is distinct from 'd95ab478018a0dd431083cf0af492311'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)')) is distinct from '0cb490ec67f551d0044226ab3c34fda1'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')) is distinct from '64fa85659b6b999796deeef94dad4e4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_editor_membership(uuid)')) is distinct from '856ddff63fd4946f712bca1deeaa7a6c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)')) is distinct from '20a6fbe856c0e2ba3987e236d1f00fb3'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0' then
    raise exception 'PRECHECK 5397: ESTADO DIVERGENTE — 5373/5374/5386 ou ajudantes 5389/5391/5392 diferem do canônico';
  end if;
  if to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is not null then
    raise exception 'PRECHECK 5397: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.get_shared_binder_placeable_copies(  -- [5397~]
  p_collection_id uuid,
  p_limit         integer default 96,
  p_offset        integer default 0
)
returns table (
  copy_token       text,  -- [5397~]
  card_name        text,
  collector_number text,
  collector_total  integer,
  card_set_code    text,
  variant_label    text,
  language_code    text,
  image_path       text,
  total_count      integer
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_layout    uuid;
  v_anchor    uuid;
  v_container uuid;
-- [5397+]
  v_mid       uuid;
  v_epoch     bigint;
-- [5397-]
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if p_limit is null or p_limit < 1 or p_limit > 96 or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if v_uid is null or p_collection_id is null then
    return;
  end if;

  -- EDITOR ACTIVE de X, coleção ativa, de outro titular.
  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid
    and c.lifecycle_status = 'ACTIVE';
  if v_owner is null then
    return;
  end if;
-- [5397+]
  -- 5397: participação e época vigentes do EDITOR — a base do token (5391).
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    return;
  end if;
-- [5397-]

  select l.id, l.collection_id, l.storage_container_id into v_layout, v_anchor, v_container
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select l.id, l.collection_id, l.storage_container_id into v_layout, v_anchor, v_container
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null or v_container is null then
    return;
  end if;
  if not exists (select 1 from public.collection c
                 where c.id = v_anchor and c.owner_user_id = v_owner and c.lifecycle_status = 'ACTIVE') then
    return;
  end if;

  return query
  with el as (
    select pc.id as pcid, ca.id as alloc_id, pc.card_variant_id, pc.language_id  -- [5397~]
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i      on i.id = pc.inventory_id
    where ca.collection_id = p_collection_id
      and i.owner_user_id = v_owner
      and pc.storage_container_id = v_container
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  tot as (select count(*)::integer as n from el)
  select
    public.v1_13_pokedex_copy_token(el.alloc_id, v_mid, v_epoch),  -- [5397~]
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')::text,
    l.code::text,
    img.storage_path::text,
    tot.n
  from el
  cross join tot
  join public.card_variant cv                       on cv.id = el.card_variant_id
  join public.card c                                on c.id = cv.card_id
  join public.card_set cs                           on cs.id = c.card_set_id
  left join public.card_variant_type vt             on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp         on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
  left join public.language l                       on l.id = el.language_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = c.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = el.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by cs.code, c.collector_order, c.collector_number, l.code, el.pcid
  limit p_limit offset p_offset;
end;
$fn$;

create function public.editor_place_copy_in_binder(  -- [5397~]
  p_collection_id    uuid,
  p_page             integer,
  p_row              integer,
  p_column           integer,
  p_copy_token     text  -- [5397~]
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_locked    boolean;
  v_card_cont uuid;
  v_here      uuid;
  v_here_slot uuid;
  v_old_asg   uuid;
  v_old_card  uuid;
  v_op        text;
-- [5397+]
  v_mid       uuid;
  v_epoch     bigint;
  v_alloc     uuid;
  v_pc        uuid;
-- [5397-]
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null or p_copy_token is null or p_copy_token !~ '^pc1\.[0-9a-f]{64}$'  -- [5397~]
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Autorização EDITOR + travas proprietária → layout → convidada → participação.
  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  -- 2. Bolso pela posição, travado; classificação sob a trava.
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select s.locked into v_locked from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

-- [5397+]
  -- 5397: token opaco (5391) → alocação de X pela participação e época VIGENTES do chamador (5392).
  -- Token inválido, de outra coleção, de outra participação ou de época anterior: mesma recusa de sempre.
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  v_alloc := public.v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, null);
  select ca.physical_card_id into v_pc
  from public.collection_allocation ca
  where ca.id = v_alloc and ca.collection_id = p_collection_id;
  if v_mid is null or v_pc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;
-- [5397-]
  -- 3. Exemplar elegível (C-235 + DR-1), relido sob trava: do titular, alocado a X,
  --    guardado no local do fichário. Uma só recusa para qualquer falha.
  select pc.storage_container_id into v_card_cont
  from public.physical_card pc
  join public.inventory i            on i.id = pc.inventory_id
  join public.collection_allocation ca on ca.physical_card_id = pc.id
  where pc.id = v_pc  -- [5397~]
    and i.owner_user_id = v_owner
    and ca.collection_id = p_collection_id
  for update of pc for share of ca;
  if not found or v_container is null or v_card_cont is distinct from v_container then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  -- 4. Já posicionado? (igual ao titular)
  select a.id, a.slot_id into v_here, v_here_slot
  from public.collection_layout_slot_assignment a
  where a.physical_card_id = v_pc  -- [5397~]
  for update;
  if v_here is not null then
    if v_here_slot = v_slot then
      return query select 'UNCHANGED'::text;
      return;
    end if;
    raise exception 'CARD_ALREADY_PLACED' using errcode = '23505',
      hint = 'o exemplar já está em outro bolso — mova-o em vez de posicioná-lo de novo';
  end if;

  -- 5. Escrita (espelho da 5272): evento com a coleção X; REPLACE só de exemplar de X.
  perform public.binder_activity_begin(v_layout, 'CARD_PLACED', 'FICHARIO', p_collection_id);
  select a.id, a.physical_card_id into v_old_asg, v_old_card
  from public.collection_layout_slot_assignment a
  where a.slot_id = v_slot
  for update;
  if v_old_asg is not null then
    if not exists (select 1 from public.collection_allocation ca
                   where ca.physical_card_id = v_old_card and ca.collection_id = p_collection_id) then
      raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
    end if;
    perform public.binder_activity_add_card_item('REMOVED', v_old_card, v_slot, null);
    delete from public.collection_layout_slot_assignment where id = v_old_asg;
    v_op := 'REPLACE';
  else
    v_op := 'ADD';
  end if;

  begin
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
    values (v_slot, v_pc);  -- [5397~]
  exception
    when unique_violation then
      raise exception 'CARD_ALREADY_PLACED' using errcode = '23505';
  end;

  perform public.binder_activity_add_card_item('PLACED', v_pc, null, v_slot);  -- [5397~]
  return query select v_op;
  perform public.binder_activity_end();
end;
$fn$;

create or replace function public.editor_preview_binder_auto_arrange(p_collection_id uuid)  -- [5397~]
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
                                     'ord', p.ord,  -- [5397~]
                                     'page_number', p.page_number, 'row_index', p.row_index,
                                     'column_index', p.column_index, 'card_id', p.card_id,
                                     'card_variant_id', p.card_variant_id) order by p.ord)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb) end
    )
    from h
  );
end;
$fn$;

comment on function public.get_shared_binder_placeable_copies(uuid, integer, integer) is
  'V1-13 E3-7b (5397): cartas que o EDITOR pode colocar (mesma regra da 5373), identificadas por token opaco da participação e época (5391); nunca o id do exemplar.';
comment on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) is
  'V1-13 E3-7b (5397): EDITOR coloca (ou desfaz a retirada de) um exemplar de X pelo token opaco (5391/5392); mesmo comportamento da 5374.';

revoke all on function public.get_shared_binder_placeable_copies(uuid, integer, integer) from public, anon, service_role;
grant execute on function public.get_shared_binder_placeable_copies(uuid, integer, integer) to authenticated;
revoke all on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) from public, anon, service_role;
grant execute on function public.editor_place_copy_in_binder(uuid, integer, integer, integer, text) to authenticated;
revoke execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon, authenticated, service_role;
revoke execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) from public, anon, authenticated, service_role;

do $post$
declare
  f oid;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)')) is distinct from '1c544a74420bdbcdebacdf0168c3d7f0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)')) is distinct from '09ea8105066f51e519c78f1149e7b9e4'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)')) is distinct from 'ba412a9ce16502e211bdac89f5146163' then
    raise exception 'POSTCHECK 5397: funções fora do texto gerado';
  end if;
  foreach f in array array[to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)'), to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)')] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or not (array['search_path=""'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then
      raise exception 'POSTCHECK 5397: RPC nova fora do estado esperado (%)', f::regprocedure;
    end if;
  end loop;
  if not (not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)'), 'EXECUTE')))
     or not (not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'), 'EXECUTE'))) then
    raise exception 'POSTCHECK 5397: contrato antigo (physical_card_id) ainda executável por cliente';
  end if;
  if pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'), 'EXECUTE') is not true then
    raise exception 'POSTCHECK 5397: prévia perdeu o EXECUTE';
  end if;
  if (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~ 'v1_13_(assert_capability|capability_open)' and p.proname ~ '^(editor_|get_shared_|get_editor_)'
                                 and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                 and (exists (select 1 from unnest(coalesce(p.proargnames, array[]::text[])) a(nm) where a.nm like '%physical_card_id%')
                                      or p.prosrc like '%''physical_card_id''%')) <> '' then
    raise exception 'POSTCHECK 5397: ainda há RPC do EDITOR com physical_card_id';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5397: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
