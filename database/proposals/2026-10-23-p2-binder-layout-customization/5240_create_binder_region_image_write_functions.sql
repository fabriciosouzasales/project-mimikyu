/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5240 - Create Binder Region Image Write Functions
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23 (P2-BINDER-LAYOUT-CUSTOMIZATION-IMPLEMENTATION-PROPOSAL-01)
Descrição...:
Funções do colecionador para a imagem em 2 bolsos. Autorização igual à da
imagem de bolso (5233): coleção do usuário, proprietária ou convidada do
fichário, ACTIVE; fichário mutável e TRAVADO (assert 5122 FOR UPDATE) —
toda escrita no fichário serializa.

  binder_layout_lock_for_collection(collection) → layout   (interna)
  merge_my_binder_slots_with_image(collection, left_slot, path, fx, fy)
      ADDED | UNCHANGED (repetição da mesma chamada)
  set_my_binder_region_image(collection, region, path, fx, fy)
      REPLACED (+ previous_path) | UNCHANGED
  set_my_binder_region_image_focus(collection, region, fx, fy)
  separate_my_binder_slots(collection, region)
      SEPARATED (+ previous_path) | ALREADY_ABSENT

Ordem segura dos arquivos (a mesma homologada para os bolsos):
o cliente envia para um caminho NOVO, a RPC vincula, e só depois do
REPLACED/SEPARATED o cliente apaga o arquivo anterior. A política DELETE
(via 5239) recusa apagar arquivo ainda vinculado.

Nada aqui toca cartas, alocações, reservas, travas, progresso ou valor.
Dependências: 5122, 5233 (padrão), 5238, 5239.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_region_image') is null then
    raise exception 'PRECHECK 5240: aplique 5239 antes';
  end if;
  if to_regprocedure('public.merge_my_binder_slots_with_image(uuid, uuid, text, smallint, smallint)') is not null then
    raise exception 'PRECHECK 5240: funções já existem';
  end if;
  if not has_table_privilege(current_user, 'storage.objects', 'UPDATE') then
    raise exception 'PRECHECK 5240: % sem UPDATE em storage.objects (necessário ao FOR SHARE)', current_user;
  end if;
end;
$pre$;

-- 0. Interna: resolve e TRAVA o fichário da coleção ---------------------------------------
create function public.binder_layout_lock_for_collection(p_collection_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_guest  boolean := false;
  v_status text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
    v_guest := v_layout is not null;
  end if;
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  begin
    perform public.assert_collection_layout_mutable(v_layout);   -- trava o fichário (FOR UPDATE)
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'a coleção dona do fichário está arquivada — reative-a para editar';
      end if;
      raise;
  end;

  if v_guest then
    select c.lifecycle_status into v_status
    from public.collection c
    where c.id = p_collection_id and c.owner_user_id = v_uid
    for share;
    if not found then
      raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
    end if;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
        hint = 'esta coleção está arquivada — reative-a para editar o fichário';
    end if;
    perform 1 from public.collection_layout_guest g
    where g.collection_id = p_collection_id and g.layout_id = v_layout;
    if not found then
      raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  return v_layout;
end;
$$;

revoke all on function public.binder_layout_lock_for_collection(uuid)
  from public, anon, authenticated, service_role;

-- 0b. Interna: valida o arquivo enviado (dono, pasta, tipo, tamanho) ------------------------
create function public.binder_image_file_check(p_path text, p_layout uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c_max_bytes constant bigint := 524288;
  v_uid  uuid := auth.uid();
  v_mime text;
  v_size text;
begin
  if p_path is null
     or p_path !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg)$'
     or split_part(p_path, '/', 1) <> v_uid::text
     or split_part(p_path, '/', 2) <> p_layout::text then
    raise exception 'INVALID_IMAGE_PATH' using errcode = '22023';
  end if;
  select o.metadata ->> 'mimetype', o.metadata ->> 'size'
    into v_mime, v_size
  from storage.objects o
  where o.bucket_id = 'binder-slot-image'
    and o.name = p_path
    and (o.owner_id = v_uid::text or o.owner = v_uid)
  for share of o;
  if not found then
    raise exception 'IMAGE_FILE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_mime is distinct from (case when p_path like '%.webp' then 'image/webp' else 'image/jpeg' end)
     or v_size is null or v_size !~ '^[0-9]{1,12}$'
     or v_size::bigint < 1 or v_size::bigint > c_max_bytes then
    raise exception 'INVALID_IMAGE_FILE' using errcode = '22023',
      hint = 'só WebP ou JPEG de até 512 KB';
  end if;
end;
$$;

revoke all on function public.binder_image_file_check(text, uuid)
  from public, anon, authenticated, service_role;

-- 1. Mesclar 2 bolsos livres com uma imagem --------------------------------------------------
create function public.merge_my_binder_slots_with_image(
  p_collection_id uuid,
  p_left_slot_id  uuid,
  p_storage_path  text,
  p_focal_x       smallint default 50,
  p_focal_y       smallint default 50
)
returns table (
  region_id     uuid,
  left_slot_id  uuid,
  right_slot_id uuid,
  storage_path  text,
  focal_x       smallint,
  focal_y       smallint,
  operation     text
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_path   text := nullif(btrim(coalesce(p_storage_path, '')), '');
  v_fx     smallint := coalesce(p_focal_x, 50);
  v_fy     smallint := coalesce(p_focal_y, 50);
  v_layout uuid;
  v_page   uuid;
  v_row    integer;
  v_col    integer;
  v_right  uuid;
  v_region uuid;
  v_existing_path text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_fx < 0 or v_fx > 100 or v_fy < 0 or v_fy > 100 then
    raise exception 'INVALID_FOCAL' using errcode = '22023';
  end if;
  if p_left_slot_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);
  perform public.binder_image_file_check(v_path, v_layout);

  select s.page_id, s.row_index, s.column_index into v_page, v_row, v_col
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_left_slot_id and p.layout_id = v_layout;
  if not found then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Repetição segura (resposta incerta no cliente): mesma mesclagem, mesmo arquivo.
  select rg.id, ri.storage_path into v_region, v_existing_path
  from public.collection_layout_region rg
  join public.collection_layout_region_image ri on ri.region_id = rg.id
  where rg.page_id = v_page and rg.top_row = v_row and rg.left_column = v_col
    and rg.height = 1 and rg.width = 2;
  if found and v_existing_path = v_path then
    return query
    select rg.id, p_left_slot_id, s2.id, ri.storage_path, ri.focal_x, ri.focal_y, 'UNCHANGED'::text
    from public.collection_layout_region rg
    join public.collection_layout_region_image ri on ri.region_id = rg.id
    join public.collection_layout_slot s2
      on s2.page_id = rg.page_id and s2.row_index = rg.top_row and s2.column_index = rg.left_column + 1
    where rg.id = v_region;
    return;
  end if;

  select s.id into v_right
  from public.collection_layout_slot s
  where s.page_id = v_page and s.row_index = v_row and s.column_index = v_col + 1;
  if not found then
    raise exception 'NO_RIGHT_NEIGHBOR' using errcode = '55000',
      hint = 'não há bolso à direita na mesma linha';
  end if;

  -- Trava os 2 bolsos em ordem determinística e revalida "livre".
  perform 1 from public.collection_layout_slot s
  where s.id in (p_left_slot_id, v_right)
  order by s.id
  for update;

  if exists (
    select 1 from public.collection_layout_slot s
    where s.id in (p_left_slot_id, v_right)
      and (s.locked
           or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
           or exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
           or exists (select 1 from public.collection_layout_slot_image i where i.slot_id = s.id)
           or exists (select 1 from public.collection_layout_region r
                      where r.page_id = s.page_id
                        and s.row_index between r.top_row and r.top_row + r.height - 1
                        and s.column_index between r.left_column and r.left_column + r.width - 1))
  ) then
    raise exception 'SLOTS_NOT_FREE' using errcode = '55000',
      hint = 'os 2 bolsos precisam estar livres: sem carta, reserva, imagem, fixação ou mesclagem';
  end if;

  -- Gatilhos 5121 (página travada, limites, sobreposição, fixação), 5232 e 5238
  -- revalidam tudo de forma independente.
  insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
  values (v_page, v_row, v_col, 1, 2)
  returning id into v_region;

  begin
    insert into public.collection_layout_region_image (region_id, owner_user_id, storage_path, focal_x, focal_y)
    values (v_region, v_uid, v_path, v_fx, v_fy);
  exception
    when unique_violation then
      raise exception 'IMAGE_PATH_IN_USE' using errcode = '55000';
  end;

  return query
  select v_region, p_left_slot_id, v_right, v_path, v_fx, v_fy, 'ADDED'::text;
end;
$$;

comment on function public.merge_my_binder_slots_with_image(uuid, uuid, text, smallint, smallint) is
  'Fichário Digital (5240): une 2 bolsos livres lado a lado (mesma linha) numa mesclagem com uma única imagem decorativa, atomicamente. ADDED | UNCHANGED (repetição). Não toca cartas, reservas, travas nem progresso.';

revoke all on function public.merge_my_binder_slots_with_image(uuid, uuid, text, smallint, smallint) from public, anon;
grant execute on function public.merge_my_binder_slots_with_image(uuid, uuid, text, smallint, smallint) to authenticated;

-- Interna: mesclagem do fichário travado, com sua imagem travada --------------------------
create function public.binder_region_lock_in_layout(p_layout uuid, p_region_id uuid)
returns text   -- storage_path atual (null se a mesclagem não existe neste fichário)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_path text;
begin
  perform 1
  from public.collection_layout_region rg
  join public.collection_layout_page p on p.id = rg.page_id
  where rg.id = p_region_id and p.layout_id = p_layout
  for update of rg;
  if not found then
    return null;
  end if;
  select ri.storage_path into v_path
  from public.collection_layout_region_image ri
  where ri.region_id = p_region_id
  for update;
  return coalesce(v_path, '');
end;
$$;

revoke all on function public.binder_region_lock_in_layout(uuid, uuid)
  from public, anon, authenticated, service_role;

-- 2. Substituir a imagem -----------------------------------------------------------------------
create function public.set_my_binder_region_image(
  p_collection_id uuid,
  p_region_id     uuid,
  p_storage_path  text,
  p_focal_x       smallint default 50,
  p_focal_y       smallint default 50
)
returns table (
  region_id     uuid,
  storage_path  text,
  focal_x       smallint,
  focal_y       smallint,
  operation     text,
  previous_path text
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_path   text := nullif(btrim(coalesce(p_storage_path, '')), '');
  v_fx     smallint := coalesce(p_focal_x, 50);
  v_fy     smallint := coalesce(p_focal_y, 50);
  v_layout uuid;
  v_old    text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_fx < 0 or v_fx > 100 or v_fy < 0 or v_fy > 100 then
    raise exception 'INVALID_FOCAL' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);
  v_old := public.binder_region_lock_in_layout(v_layout, p_region_id);
  if v_old is null or v_old = '' then
    raise exception 'REGION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_old = v_path then
    update public.collection_layout_region_image ri
       set focal_x = v_fx, focal_y = v_fy
     where ri.region_id = p_region_id
       and (ri.focal_x is distinct from v_fx or ri.focal_y is distinct from v_fy);
    return query
    select ri.region_id, ri.storage_path, ri.focal_x, ri.focal_y, 'UNCHANGED'::text, null::text
    from public.collection_layout_region_image ri where ri.region_id = p_region_id;
    return;
  end if;

  perform public.binder_image_file_check(v_path, v_layout);
  begin
    update public.collection_layout_region_image ri
       set storage_path = v_path, focal_x = v_fx, focal_y = v_fy
     where ri.region_id = p_region_id;
  exception
    when unique_violation then
      raise exception 'IMAGE_PATH_IN_USE' using errcode = '55000';
  end;

  return query
  select ri.region_id, ri.storage_path, ri.focal_x, ri.focal_y, 'REPLACED'::text, v_old
  from public.collection_layout_region_image ri where ri.region_id = p_region_id;
end;
$$;

comment on function public.set_my_binder_region_image(uuid, uuid, text, smallint, smallint) is
  'Fichário Digital (5240): substitui a imagem de uma mesclagem. REPLACED devolve previous_path para o cliente apagar DEPOIS. UNCHANGED só ajusta o enquadramento.';

revoke all on function public.set_my_binder_region_image(uuid, uuid, text, smallint, smallint) from public, anon;
grant execute on function public.set_my_binder_region_image(uuid, uuid, text, smallint, smallint) to authenticated;

-- 3. Enquadramento ------------------------------------------------------------------------------
create function public.set_my_binder_region_image_focus(
  p_collection_id uuid,
  p_region_id     uuid,
  p_focal_x       smallint,
  p_focal_y       smallint
)
returns table (
  region_id uuid,
  focal_x   smallint,
  focal_y   smallint
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_layout uuid;
  v_old    text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_focal_x is null or p_focal_y is null
     or p_focal_x < 0 or p_focal_x > 100 or p_focal_y < 0 or p_focal_y > 100 then
    raise exception 'INVALID_FOCAL' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);
  v_old := public.binder_region_lock_in_layout(v_layout, p_region_id);
  if v_old is null or v_old = '' then
    raise exception 'REGION_NOT_FOUND' using errcode = 'P0002';
  end if;

  update public.collection_layout_region_image ri
     set focal_x = p_focal_x, focal_y = p_focal_y
   where ri.region_id = p_region_id
     and (ri.focal_x is distinct from p_focal_x or ri.focal_y is distinct from p_focal_y);

  return query
  select ri.region_id, ri.focal_x, ri.focal_y
  from public.collection_layout_region_image ri where ri.region_id = p_region_id;
end;
$$;

revoke all on function public.set_my_binder_region_image_focus(uuid, uuid, smallint, smallint) from public, anon;
grant execute on function public.set_my_binder_region_image_focus(uuid, uuid, smallint, smallint) to authenticated;

-- 4. Separar os bolsos (desvincula a imagem e desfaz a mesclagem, atomicamente) -----------------
create function public.separate_my_binder_slots(
  p_collection_id uuid,
  p_region_id     uuid
)
returns table (
  region_id     uuid,
  outcome       text,
  previous_path text
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_layout uuid;
  v_old    text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_region_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);
  v_old := public.binder_region_lock_in_layout(v_layout, p_region_id);
  if v_old is null then
    -- Repetição ou mesclagem de outro fichário: indistinguível de propósito.
    region_id := p_region_id; outcome := 'ALREADY_ABSENT'; previous_path := null;
    return next;
    return;
  end if;

  delete from public.collection_layout_region_image ri where ri.region_id = p_region_id;
  delete from public.collection_layout_region rg where rg.id = p_region_id;   -- 5121 revalida fixação

  region_id := p_region_id;
  outcome := 'SEPARATED';
  previous_path := nullif(v_old, '');
  return next;
end;
$$;

comment on function public.separate_my_binder_slots(uuid, uuid) is
  'Fichário Digital (5240): desfaz uma mesclagem e desvincula sua imagem na mesma transação; os 2 bolsos voltam livres. SEPARATED devolve previous_path para o cliente apagar DEPOIS; ALREADY_ABSENT em repetição.';

revoke all on function public.separate_my_binder_slots(uuid, uuid) from public, anon;
grant execute on function public.separate_my_binder_slots(uuid, uuid) to authenticated;

commit;

/*
Resultado esperado: 4 RPCs (authenticated) + 3 internas (sem EXECUTE para clientes).
Como validar (LIVE_90, POST-3): proacl/has_function_privilege conforme acima;
prosecdef = true e proconfig contém search_path= em todas.
*/
