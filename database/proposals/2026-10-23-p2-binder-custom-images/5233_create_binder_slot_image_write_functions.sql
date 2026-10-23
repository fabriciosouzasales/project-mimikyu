/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5233 - Imagem personalizada do bolso: escrita
              binder_slot_image_lock_target(uuid, uuid)            — interna
              set_my_binder_slot_image(uuid, uuid, text, smallint) — incluir/substituir
              set_my_binder_slot_image_focus(uuid, uuid, smallint) — enquadramento
              clear_my_binder_slot_image(uuid, uuid)               — remover
              (P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01)
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: objeto travado FOR SHARE
              antes do vínculo; precheck de privilégio)
              1.0 (2026-10-23)
Status......: PROPOSTA — NÃO EXECUTADA. Depende de 5231 e 5232.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Autorização (D2): o usuário gerencia as imagens pelo fichário acessado
através de QUALQUER coleção participante — proprietária ou convidada
(5229). p_collection_id é a coleção pela qual a tela foi aberta; o bolso
precisa pertencer ao fichário dela. Coleção alheia, inexistente, fora do
fichário ou bolso de outro fichário colapsam em respostas sem enumeração.

Travas (mesma ordem de assign_card_to_slot, 5229): proprietária → fichário
(5122, que também exige proprietária ACTIVE) → convidada FOR SHARE (se a
tela veio da convidada; exige ACTIVE e revalida o vínculo sob a trava) →
bolso FOR UPDATE. Toda escrita de bolso do produto usa a mesma trava de
fichário, então imagem × carta × reserva × trava × mesclagem serializam.

set_my_binder_slot_image(p_collection_id, p_slot_id, p_storage_path, p_focal_y)
  → (slot_id, storage_path, focal_y, operation, previous_path)
  operation: ADDED | REPLACED | UNCHANGED
  - Caminho: `<auth.uid()>/<layout do bolso>/<uuid>.(webp|jpg)`.
  - O objeto é travado FOR SHARE até o fim da transação (AUDIT-
    CORRECTION-01): um DELETE concorrente (limpeza de órfãos) ou já
    terminou — e o vínculo falha com IMAGE_FILE_NOT_FOUND, sem tocar a
    imagem atual — ou espera o vínculo e, ao reavaliar, a política DELETE
    (5232) vê o arquivo vinculado e não apaga. Nunca sobra bolso apontando
    para arquivo inexistente.
  - O arquivo precisa EXISTIR no bucket, enviado pelo próprio usuário
    (owner_id texto ou owner uuid legado, como a 5178), e os METADADOS
    gravados pelo Storage precisam confirmar tipo e tamanho:
    mimetype = image/webp (.webp) ou image/jpeg (.jpg) e 1 ≤ size ≤ 524288.
    Defesa em profundidade além do bucket: não confia no navegador.
  - ADDED: bolso livre — sem posição, sem reserva, solto, fora de Region
    (gatilho 5232 com os erros SLOT_OCCUPIED/SLOT_RESERVED/SLOT_LOCKED/
    SLOT_IN_REGION) — e limite de 500 imagens vinculadas por usuário
    (IMAGE_QUOTA_REACHED), contado sob advisory lock do usuário (dois
    fichários do mesmo usuário em paralelo não ultrapassam o limite).
  - REPLACED: o bolso já tinha imagem; troca o caminho e devolve
    previous_path. O CLIENTE apaga o arquivo antigo DEPOIS desta resposta
    (nunca antes). Esta função não apaga arquivos.
  - UNCHANGED: mesmo caminho já vinculado a este bolso (repetição/retry):
    só aplica p_focal_y; previous_path NULL. Idempotente.
  - Caminho já vinculado a OUTRO bolso → IMAGE_PATH_IN_USE.

set_my_binder_slot_image_focus(p_collection_id, p_slot_id, p_focal_y)
  → (slot_id, focal_y). Bolso sem imagem → IMAGE_NOT_FOUND. Idempotente.

clear_my_binder_slot_image(p_collection_id, p_slot_id)
  → (slot_id, outcome, previous_path). outcome: REMOVED | ALREADY_ABSENT.
  O cliente apaga previous_path depois. Idempotente.

Nada aqui toca physical_card, collection_allocation, slot_assignment,
slot_expected_content, locked, region, progresso ou valor.

Erros: 28000 not_authenticated; 22023 INVALID_ARGUMENT, INVALID_FOCAL,
INVALID_IMAGE_PATH; P0002 COLLECTION_NOT_FOUND, BINDER_NOT_FOUND,
SLOT_NOT_FOUND, IMAGE_FILE_NOT_FOUND, IMAGE_NOT_FOUND; 55000
COLLECTION_ARCHIVED, SLOT_* (5232), IMAGE_QUOTA_REACHED, IMAGE_PATH_IN_USE;
22023 INVALID_IMAGE_FILE.
Segurança: SECURITY DEFINER, search_path vazio, lock_timeout 5s; EXECUTE só
authenticated; a função interna sem EXECUTE para a API.
Como validar: Query 5852 (Seções 0–3).
Como reverter: drop das quatro funções.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_image') is null then
    raise exception 'PRECHECK 5233: aplique 5232 antes';
  end if;
  if to_regprocedure('public.set_my_binder_slot_image(uuid, uuid, text, smallint)') is not null then
    raise exception 'PRECHECK 5233: funções já existem';
  end if;
  -- FOR SHARE em storage.objects exige privilégio UPDATE para o dono das funções.
  if not has_table_privilege(current_user, 'storage.objects', 'UPDATE') then
    raise exception 'PRECHECK 5233: % sem UPDATE em storage.objects (necessário ao FOR SHARE)', current_user;
  end if;
end;
$pre$;

-- 0. Interna: resolve e trava o alvo ------------------------------------------------------
create function public.binder_slot_image_lock_target(
  p_collection_id uuid,
  p_slot_id       uuid
)
returns uuid   -- layout_id
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_layout  uuid;
  v_guest   boolean := false;
  v_status  text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_slot_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout
    from public.collection_layout_guest g
    where g.collection_id = p_collection_id;
    v_guest := v_layout is not null;
  end if;
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform 1
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = v_layout;
  if not found then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Proprietária → fichário (+ ACTIVE da proprietária).
  begin
    perform public.assert_collection_layout_mutable(v_layout);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'a coleção dona do fichário está arquivada — reative-a para editar';
      end if;
      raise;
  end;

  -- Convidada: FOR SHARE (como assign 5229), ACTIVE e vínculo revalidado.
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

  -- Bolso: trava + revalidação.
  perform 1
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = v_layout
  for update of s;
  if not found then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;

  return v_layout;
end;
$$;

revoke all on function public.binder_slot_image_lock_target(uuid, uuid)
  from public, anon, authenticated, service_role;

-- 1. Incluir / substituir ---------------------------------------------------------------
create function public.set_my_binder_slot_image(
  p_collection_id uuid,
  p_slot_id       uuid,
  p_storage_path  text,
  p_focal_y       smallint default 50
)
returns table (
  slot_id       uuid,
  storage_path  text,
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
  c_max_images constant integer := 500;
  c_max_bytes  constant bigint  := 524288;
  v_uid    uuid := auth.uid();
  v_path   text := nullif(btrim(coalesce(p_storage_path, '')), '');
  v_focal  smallint := coalesce(p_focal_y, 50);
  v_layout uuid;
  v_mime   text;
  v_size   text;
  v_old    text;
  v_count  integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_focal < 0 or v_focal > 100 then
    raise exception 'INVALID_FOCAL' using errcode = '22023';
  end if;
  if v_path is null
     or v_path !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg)$'
     or split_part(v_path, '/', 1) <> v_uid::text then
    raise exception 'INVALID_IMAGE_PATH' using errcode = '22023';
  end if;

  v_layout := public.binder_slot_image_lock_target(p_collection_id, p_slot_id);

  if split_part(v_path, '/', 2) <> v_layout::text then
    raise exception 'INVALID_IMAGE_PATH' using errcode = '22023',
      hint = 'o arquivo precisa estar na pasta do fichário do bolso';
  end if;

  -- Arquivo: existe, é do usuário e o Storage confirma tipo e tamanho.
  select o.metadata ->> 'mimetype', o.metadata ->> 'size'
    into v_mime, v_size
  from storage.objects o
  where o.bucket_id = 'binder-slot-image'
    and o.name = v_path
    and (o.owner_id = v_uid::text or o.owner = v_uid)
  for share of o;
  if not found then
    raise exception 'IMAGE_FILE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_mime is distinct from (case when v_path like '%.webp' then 'image/webp' else 'image/jpeg' end)
     or v_size is null or v_size !~ '^[0-9]{1,12}$'
     or v_size::bigint < 1 or v_size::bigint > c_max_bytes then
    raise exception 'INVALID_IMAGE_FILE' using errcode = '22023',
      hint = 'só WebP ou JPEG de até 512 KB';
  end if;

  select i.storage_path into v_old
  from public.collection_layout_slot_image i
  where i.slot_id = p_slot_id;

  if found then
    if v_old = v_path then
      update public.collection_layout_slot_image i
         set focal_y = v_focal
       where i.slot_id = p_slot_id and i.focal_y is distinct from v_focal;
      return query
      select i.slot_id, i.storage_path, i.focal_y, 'UNCHANGED'::text, null::text
      from public.collection_layout_slot_image i where i.slot_id = p_slot_id;
      return;
    end if;
    begin
      update public.collection_layout_slot_image i
         set storage_path = v_path, focal_y = v_focal
       where i.slot_id = p_slot_id;
    exception
      when unique_violation then
        raise exception 'IMAGE_PATH_IN_USE' using errcode = '55000';
    end;
    return query
    select i.slot_id, i.storage_path, i.focal_y, 'REPLACED'::text, v_old
    from public.collection_layout_slot_image i where i.slot_id = p_slot_id;
    return;
  end if;

  -- ADDED: limite por usuário, serializado por usuário.
  perform pg_advisory_xact_lock(hashtextextended('binder-slot-image:' || v_uid::text, 0));
  select count(*)::integer into v_count
  from public.collection_layout_slot_image i
  where i.owner_user_id = v_uid;
  if v_count >= c_max_images then
    raise exception 'IMAGE_QUOTA_REACHED' using errcode = '55000',
      hint = 'limite de 500 imagens personalizadas — remova alguma para incluir outra';
  end if;

  begin
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path, focal_y)
    values (p_slot_id, v_uid, v_path, v_focal);
  exception
    when unique_violation then
      raise exception 'IMAGE_PATH_IN_USE' using errcode = '55000';
  end;

  return query
  select i.slot_id, i.storage_path, i.focal_y, 'ADDED'::text, null::text
  from public.collection_layout_slot_image i where i.slot_id = p_slot_id;
end;
$$;

comment on function public.set_my_binder_slot_image(uuid, uuid, text, smallint) is
  'Fichário Digital (5233, C-198): inclui ou substitui a imagem personalizada de um bolso livre, pela coleção proprietária ou convidada. Exige arquivo já enviado pelo usuário ao bucket privado binder-slot-image na pasta do fichário, com tipo/tamanho confirmados pelos metadados do Storage. ADDED | REPLACED (devolve previous_path para o cliente apagar DEPOIS) | UNCHANGED. Limite de 500 imagens por usuário. Não apaga arquivos; não toca cartas, reservas, travas nem progresso.';

revoke all on function public.set_my_binder_slot_image(uuid, uuid, text, smallint) from public;
revoke all on function public.set_my_binder_slot_image(uuid, uuid, text, smallint) from anon;
grant execute on function public.set_my_binder_slot_image(uuid, uuid, text, smallint) to authenticated;

-- 2. Enquadramento ----------------------------------------------------------------------
create function public.set_my_binder_slot_image_focus(
  p_collection_id uuid,
  p_slot_id       uuid,
  p_focal_y       smallint
)
returns table (
  slot_id uuid,
  focal_y smallint
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_focal_y is null or p_focal_y < 0 or p_focal_y > 100 then
    raise exception 'INVALID_FOCAL' using errcode = '22023';
  end if;

  perform public.binder_slot_image_lock_target(p_collection_id, p_slot_id);

  update public.collection_layout_slot_image i
     set focal_y = p_focal_y
   where i.slot_id = p_slot_id and i.focal_y is distinct from p_focal_y;

  return query
  select i.slot_id, i.focal_y
  from public.collection_layout_slot_image i where i.slot_id = p_slot_id;
  if not found then
    raise exception 'IMAGE_NOT_FOUND' using errcode = 'P0002';
  end if;
end;
$$;

comment on function public.set_my_binder_slot_image_focus(uuid, uuid, smallint) is
  'Fichário Digital (5233, C-198): ajusta o enquadramento vertical (0–100) da imagem de um bolso, sem reenviar arquivo. Idempotente.';

revoke all on function public.set_my_binder_slot_image_focus(uuid, uuid, smallint) from public;
revoke all on function public.set_my_binder_slot_image_focus(uuid, uuid, smallint) from anon;
grant execute on function public.set_my_binder_slot_image_focus(uuid, uuid, smallint) to authenticated;

-- 3. Remover ---------------------------------------------------------------------------
create function public.clear_my_binder_slot_image(
  p_collection_id uuid,
  p_slot_id       uuid
)
returns table (
  slot_id       uuid,
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
  v_old text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.binder_slot_image_lock_target(p_collection_id, p_slot_id);

  delete from public.collection_layout_slot_image i
   where i.slot_id = p_slot_id
  returning i.storage_path into v_old;

  slot_id       := p_slot_id;
  outcome       := case when v_old is null then 'ALREADY_ABSENT' else 'REMOVED' end;
  previous_path := v_old;
  return next;
end;
$$;

comment on function public.clear_my_binder_slot_image(uuid, uuid) is
  'Fichário Digital (5233, C-198): remove o vínculo da imagem de um bolso (REMOVED | ALREADY_ABSENT) e devolve previous_path para o cliente apagar o arquivo DEPOIS. Não apaga arquivos. Idempotente.';

revoke all on function public.clear_my_binder_slot_image(uuid, uuid) from public;
revoke all on function public.clear_my_binder_slot_image(uuid, uuid) from anon;
grant execute on function public.clear_my_binder_slot_image(uuid, uuid) to authenticated;

commit;
