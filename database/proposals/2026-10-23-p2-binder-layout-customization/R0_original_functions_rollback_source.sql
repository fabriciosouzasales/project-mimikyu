-- P2-BINDER-LAYOUT-CUSTOMIZATION — R0: definições ORIGINAIS das 5 funções substituídas por 5239/5242.
-- Capturadas do LIVE (pg_get_functiondef, papel postgres) em 2026-10-23, IMEDIATAMENTE antes de W1.
-- Uso: fonte da reversão pós-COMMIT (só com autorização). NÃO EXECUTAR sem autorização.
-- ACL das 5 no momento da captura: postgres:EXECUTE, authenticated:EXECUTE (CREATE OR REPLACE preserva a ACL).
-- md5(pg_get_functiondef):
--   binder_slot_image_path_is_linked        86e513e8f28bd9039d4b490db71b0bf9
--   dismantle_my_collection_binder          23a28f2818b35aeeeb77a87181c8a0c6
--   get_my_binder_slot_image_summary        f14b80ec3af0cb43fe4c9f63eb57f97a
--   list_my_unlinked_binder_slot_images     01e2f3ee35bfb2d805283f73a9a1f73b
--   preview_my_collection_binder_dismantle  1b45abf428317ee0ba624c4635eb71f4

CREATE OR REPLACE FUNCTION public.binder_slot_image_path_is_linked(p_name text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_name is not null
     and split_part(p_name, '/', 1) = (select auth.uid())::text
     and exists (select 1 from public.collection_layout_slot_image i
                 where i.storage_path = p_name);
$function$;

CREATE OR REPLACE FUNCTION public.dismantle_my_collection_binder(p_collection_id uuid, p_dismantle_token text)
 RETURNS TABLE(outcome text, pages_removed integer, slots_removed integer, assignments_removed integer, reservations_removed integer, regions_removed integer, locks_released integer, images_removed integer, image_paths text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_layout  uuid;
  r         record;
  v_unlock  integer;
  v_asg     integer;
  v_exc     integer;
  v_rg      integer;
  v_pg      integer;
  v_left    integer;
  v_img_n   integer;
  v_img     integer;
  v_paths   text[];
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_dismantle_token is null or p_dismantle_token !~ '^d1:[0-9a-f]{64}$' then
    raise exception 'INVALID_DISMANTLE_TOKEN' using errcode = '22023';
  end if;

  perform 1
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l
  where l.collection_id = p_collection_id
  for update;
  if v_layout is null then
    -- 5229: convidada não "desmonta" o fichário de outra coleção.
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'COLLECTION_IS_BINDER_GUEST'
        using hint = 'esta coleção usa o fichário de outra coleção — desassocie-a em vez de desmontar';
    end if;
    outcome := 'ALREADY_ABSENT';
    pages_removed := 0; slots_removed := 0; assignments_removed := 0;
    reservations_removed := 0; regions_removed := 0; locks_released := 0;
    images_removed := 0; image_paths := '{}'::text[];
    return next;
    return;
  end if;

  -- 5229 (D7): recusa ANTES de qualquer remoção, sob a trava do layout.
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout) then
    raise exception 'BINDER_HAS_GUESTS'
      using hint = 'desassocie as outras coleções deste fichário antes de desmontá-lo';
  end if;

  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);
  if r.dismantle_token is distinct from p_dismantle_token then
    raise exception 'DISMANTLE_PLAN_CHANGED';
  end if;

  -- 5236: imagens lidas sob a trava do layout (conferência no fim).
  select count(*)::integer into v_img_n
  from public.collection_layout_slot_image i
  join public.collection_layout_slot s on s.id = i.slot_id
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = v_layout;

  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout);
  get diagnostics v_unlock = row_count;

  delete from public.collection_layout_slot_assignment a
   using public.collection_layout_slot s, public.collection_layout_page p
   where a.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_asg = row_count;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  delete from public.collection_layout_region rg
   using public.collection_layout_page p
   where rg.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_rg = row_count;

  -- 5236: imagens antes das páginas (FK RESTRICT da 5232). Arquivos NÃO são
  -- apagados aqui: os caminhos voltam para o cliente apagar depois.
  with d as (
    delete from public.collection_layout_slot_image i
     using public.collection_layout_slot s, public.collection_layout_page p
     where i.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout
    returning i.storage_path as path
  )
  select count(*)::integer, coalesce(array_agg(d.path order by d.path), '{}'::text[])
    into v_img, v_paths
  from d;

  delete from public.collection_layout_page p where p.layout_id = v_layout;
  get diagnostics v_pg = row_count;

  delete from public.collection_layout l where l.id = v_layout;

  select count(*)::integer into v_left
  from public.collection_layout l where l.collection_id = p_collection_id;

  if v_left <> 0
     or v_unlock <> r.locked_count
     or v_asg <> r.assignments_count
     or v_exc <> r.reservations_count
     or v_rg <> r.regions_count
     or v_pg <> r.pages_count
     or v_img <> v_img_n then
    raise exception 'BINDER_DISMANTLE_INCONSISTENT';
  end if;

  outcome              := 'DISMANTLED';
  pages_removed        := v_pg;
  slots_removed        := r.slots_count;
  assignments_removed  := v_asg;
  reservations_removed := v_exc;
  regions_removed      := v_rg;
  locks_released       := v_unlock;
  images_removed       := v_img;
  image_paths          := v_paths;
  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_binder_slot_image_summary(p_collection_id uuid)
 RETURNS TABLE(layout_image_count integer, user_image_count integer, user_image_limit integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_layout uuid;
begin
  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);

  layout_image_count := case when v_layout is null then 0 else (
    select count(*)::integer
    from public.collection_layout_page p
    join public.collection_layout_slot s       on s.page_id = p.id
    join public.collection_layout_slot_image i on i.slot_id = s.id
    where p.layout_id = v_layout) end;
  user_image_count := (
    select count(*)::integer from public.collection_layout_slot_image i
    where i.owner_user_id = auth.uid());
  user_image_limit := 500;
  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_unlinked_binder_slot_images(p_limit integer DEFAULT 50)
 RETURNS TABLE(storage_path text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid   uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select o.name, o.created_at
  from storage.objects o
  where o.bucket_id = 'binder-slot-image'
    and o.name like v_uid::text || '/%'
    and o.created_at < now() - interval '1 hour'
    and not exists (select 1 from public.collection_layout_slot_image i
                    where i.storage_path = o.name)
  order by o.created_at
  limit v_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.preview_my_collection_binder_dismantle(p_collection_id uuid)
 RETURNS TABLE(collection_id uuid, lifecycle_status text, has_binder boolean, layout_id uuid, grid_columns integer, grid_rows integer, pages_count integer, slots_count integer, locked_count integer, assignments_count integer, reservations_count integer, regions_count integer, dismantle_token text, guest_count integer, blocked_reason text, images_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_status text;
  r        record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);

  collection_id    := p_collection_id;
  lifecycle_status := v_status;
  has_binder       := r.layout_id is not null;
  guest_count      := 0;
  images_count     := 0;
  if has_binder then
    layout_id          := r.layout_id;
    grid_columns       := r.grid_columns;
    grid_rows          := r.grid_rows;
    pages_count        := r.pages_count;
    slots_count        := r.slots_count;
    locked_count       := r.locked_count;
    assignments_count  := r.assignments_count;
    reservations_count := r.reservations_count;
    regions_count      := r.regions_count;
    dismantle_token    := r.dismantle_token;
    select count(*)::integer into guest_count
    from public.collection_layout_guest g where g.layout_id = r.layout_id;
    if guest_count > 0 then
      blocked_reason := 'BINDER_HAS_GUESTS';
    end if;
    select count(*)::integer into images_count
    from public.collection_layout_slot_image i
    join public.collection_layout_slot s on s.id = i.slot_id
    join public.collection_layout_page p on p.id = s.page_id
    where p.layout_id = r.layout_id;
  elsif exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
    blocked_reason := 'COLLECTION_IS_BINDER_GUEST';
  end if;
  return next;
end;
$function$;
