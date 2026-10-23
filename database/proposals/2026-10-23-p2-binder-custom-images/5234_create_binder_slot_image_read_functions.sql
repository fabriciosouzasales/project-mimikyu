/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5234 - Imagem personalizada do bolso: leituras
              get_my_collection_binder_slot_images(uuid, int, int) — por páginas
              get_my_binder_slot_image_summary(uuid)               — contagens/limite
              list_my_unlinked_binder_slot_images(int)             — arquivos sem vínculo
              (P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01)
Versão......: 1.0 (2026-10-23)
Status......: PROPOSTA — NÃO EXECUTADA. Depende de 5232.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Leitura SEPARADA de get_my_collection_binder_pages (5230, LIVE): a 5230
não muda. O app chama as duas em paralelo para a mesma faixa de páginas
e sobrepõe a imagem aos bolsos (a 5230 continua devolvendo esses bolsos
como EMPTY — nenhum consumidor existente muda de comportamento).

Resolução do fichário: idêntica à 5230 (proprietária ou convidada da
coleção do usuário). Coleção alheia/inexistente → COLLECTION_NOT_FOUND;
coleção sem fichário → zero linhas. Todas as participantes veem as mesmas
imagens (pertencem ao fichário — C-198).

get_my_collection_binder_slot_images(p_collection_id, p_first_page, p_page_count)
  → (page_number, slot_id, storage_path, focal_y, updated_at)
  Mesma janela da 5230 (1 a 4 páginas). O app assina as URLs em lote
  (createSignedUrls, 1 h, sessão do usuário — a política SELECT do bucket
  só deixa assinar arquivos da própria pasta). updated_at serve de chave
  de cache. Nenhuma URL pública.

get_my_binder_slot_image_summary(p_collection_id)
  → (layout_image_count, user_image_count, user_image_limit)
  Para o cabeçalho ("N imagens") e para avisar o limite antes do envio.

list_my_unlinked_binder_slot_images(p_limit)
  → (storage_path, created_at)
  Estratégia simples de limpeza de envios abandonados (o navegador caiu
  entre enviar e vincular, ou falhou ao apagar o arquivo antigo): lista
  arquivos da PRÓPRIA pasta sem vínculo e com mais de 1 hora (a hora de
  carência protege envios em curso). O app chama ao abrir a escolha de
  imagem e apaga o que vier (política DELETE do bucket, própria pasta).
  Sem rotina de servidor, sem service_role. Máximo 100 por chamada.
  A lista é só uma sugestão: mesmo que um arquivo seja vinculado entre a
  listagem e a remoção, a política DELETE (5232) recusa apagá-lo
  (AUDIT-CORRECTION-01); e um envio em curso (< 1 h) nunca é listado.

Segurança: SECURITY DEFINER, search_path vazio, STABLE; EXECUTE só
authenticated. Nenhuma lê dado de outro usuário.
Desempenho: imagens por PK do bolso (≤ 4 páginas × ≤ 20 bolsos); limite
por índice ix_collection_layout_slot_image_owner; órfãos por prefixo do
nome no bucket (índice do Storage em bucket_id + name) com anti-join pela
UNIQUE de storage_path.
Como validar: Query 5852 (Seções 0 e 3).
Como reverter: drop das três funções.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_image') is null then
    raise exception 'PRECHECK 5234: aplique 5232 antes';
  end if;
end;
$pre$;

-- Resolução compartilhada (mesma regra da 5230), sem trava.
create function public.binder_slot_image_resolve_layout(p_collection_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
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
  select l.id into v_layout
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout
    from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  return v_layout;
end;
$$;

revoke all on function public.binder_slot_image_resolve_layout(uuid)
  from public, anon, authenticated, service_role;

-- 1. Imagens por páginas ---------------------------------------------------------------
create function public.get_my_collection_binder_slot_images(
  p_collection_id uuid,
  p_first_page    integer,
  p_page_count    integer
)
returns table (
  page_number  integer,
  slot_id      uuid,
  storage_path text,
  focal_y      smallint,
  updated_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_pages constant integer := 4;
  v_layout uuid;
begin
  if p_first_page is null or p_page_count is null
     or p_first_page < 1 or p_first_page > 100000
     or p_page_count < 1 or p_page_count > c_max_pages then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);
  if v_layout is null then
    return;
  end if;

  return query
  select p.page_number, i.slot_id, i.storage_path, i.focal_y, i.updated_at
  from public.collection_layout_page p
  join public.collection_layout_slot s       on s.page_id = p.id
  join public.collection_layout_slot_image i on i.slot_id = s.id
  where p.layout_id = v_layout
    and p.page_number between p_first_page and p_first_page + p_page_count - 1
  order by p.page_number, s.row_index, s.column_index;
end;
$$;

comment on function public.get_my_collection_binder_slot_images(uuid, integer, integer) is
  'Fichário Digital (5234, C-198): imagens personalizadas dos bolsos de 1 a 4 páginas do fichário da coleção (proprietária ou convidada). Complementa get_my_collection_binder_pages sem alterá-la. Caminhos privados — o app assina URLs de 1 h.';

revoke all on function public.get_my_collection_binder_slot_images(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_slot_images(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_slot_images(uuid, integer, integer) to authenticated;

-- 2. Resumo -----------------------------------------------------------------------------
create function public.get_my_binder_slot_image_summary(p_collection_id uuid)
returns table (
  layout_image_count integer,
  user_image_count   integer,
  user_image_limit   integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

comment on function public.get_my_binder_slot_image_summary(uuid) is
  'Fichário Digital (5234, C-198): quantas imagens personalizadas há no fichário da coleção, quantas o usuário tem no total e o limite (500).';

revoke all on function public.get_my_binder_slot_image_summary(uuid) from public;
revoke all on function public.get_my_binder_slot_image_summary(uuid) from anon;
grant execute on function public.get_my_binder_slot_image_summary(uuid) to authenticated;

-- 3. Arquivos sem vínculo (limpeza pelo próprio usuário) --------------------------------
create function public.list_my_unlinked_binder_slot_images(p_limit integer default 50)
returns table (
  storage_path text,
  created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

comment on function public.list_my_unlinked_binder_slot_images(integer) is
  'Fichário Digital (5234): arquivos da própria pasta em binder-slot-image sem vínculo a bolso e com mais de 1 hora (envio abandonado ou arquivo antigo não apagado). O app apaga pelo Storage (política DELETE da própria pasta). Máx. 100.';

revoke all on function public.list_my_unlinked_binder_slot_images(integer) from public;
revoke all on function public.list_my_unlinked_binder_slot_images(integer) from anon;
grant execute on function public.list_my_unlinked_binder_slot_images(integer) to authenticated;

commit;
