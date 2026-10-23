/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5236 - Desmontagem do fichário com imagens personalizadas
              preview_my_collection_binder_dismantle(uuid) — DROP+CREATE (+images_count)
              dismantle_my_collection_binder(uuid, text)   — DROP+CREATE (+images_removed, image_paths)
              (P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01)
Versão......: 1.0 (2026-10-23)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-BINDER-CUSTOM-IMAGES-LIVE-APPLY-01, autorização expressa de
              Fabrício; ledger 20261023185439 `5236_update_binder_dismantle_for_custom_images`).
              Do `begin;` ao `commit;` byte a byte idêntica ao texto aplicado e
              ao arquivo da pasta database/proposals/2026-10-23-p2-binder-custom-images/
              (só este bloco Status difere). POST-1 13/13 PASS; baseline
              preservado (contagens e md5); harness 5852 NÃO EXECUTADO (cria
              dados — proibido no LIVE); prova funcional F1–F7 PENDENTE (sem
              prova comportamental).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Base: o texto LIVE das duas funções na 5229 (bloco 7b), copiado e alterado
só onde indicado por "5236". Assinaturas de entrada iguais; as saídas só
GANHAM colunas no fim (o parser do app ignora colunas desconhecidas):
  prévia      images_count     imagens que somem com a desmontagem
  desmontagem images_removed   quantas foram removidas
              image_paths      caminhos para o cliente apagar DEPOIS
Ordem de remoção: travas liberadas → posições → reservas → mesclagens →
IMAGENS (novo) → páginas → layout. A conferência final ganha
images_removed = contagem lida sob a trava do layout.
O token de desmontagem (5226) NÃO inclui imagens: uma imagem incluída
entre a prévia e a confirmação também é removida (é aparência, não
patrimônio); a contagem devolvida é a real.
Arquivos do Storage nunca são apagados pelo SQL; se o cliente falhar ao
apagá-los, list_my_unlinked_binder_slot_images (5234) os devolve depois.

Como validar: Query 5852 (Seção 4).
Como reverter: reaplicar o bloco 7b da 5229 (DROP+CREATE das duas).
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_image') is null then
    raise exception 'PRECHECK 5236: aplique 5232 antes';
  end if;
  if to_regprocedure('public.dismantle_my_collection_binder(uuid, text)') is null
     or to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)') is null then
    raise exception 'PRECHECK 5236: funções de desmontagem (5229) ausentes';
  end if;
end;
$pre$;

drop function public.preview_my_collection_binder_dismantle(uuid);

create function public.preview_my_collection_binder_dismantle(p_collection_id uuid)
returns table (
  collection_id      uuid,
  lifecycle_status   text,
  has_binder         boolean,
  layout_id          uuid,
  grid_columns       integer,
  grid_rows          integer,
  pages_count        integer,
  slots_count        integer,
  locked_count       integer,
  assignments_count  integer,
  reservations_count integer,
  regions_count      integer,
  dismantle_token    text,
  guest_count        integer,   -- 5229: convidadas do fichário
  blocked_reason     text,      -- 5229: null | BINDER_HAS_GUESTS | COLLECTION_IS_BINDER_GUEST
  images_count       integer    -- 5236: imagens personalizadas que a desmontagem remove
)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

comment on function public.preview_my_collection_binder_dismantle(uuid) is
  'Fichário Digital (5226 → 5229): prévia da desmontagem — páginas, bolsos, travados, posições, reservas, mesclagens, token — e, desde a 5229, guest_count e blocked_reason (BINDER_HAS_GUESTS: desassocie as convidadas antes; COLLECTION_IS_BINDER_GUEST: esta coleção usa o fichário de outra — desassocie-a); desde a 5236, images_count (imagens personalizadas removidas junto). Não grava nada; não enumera.';

revoke all on function public.preview_my_collection_binder_dismantle(uuid) from public;
revoke all on function public.preview_my_collection_binder_dismantle(uuid) from anon;
grant execute on function public.preview_my_collection_binder_dismantle(uuid) to authenticated;

drop function public.dismantle_my_collection_binder(uuid, text);

create function public.dismantle_my_collection_binder(
  p_collection_id   uuid,
  p_dismantle_token text
)
returns table (
  outcome              text,
  pages_removed        integer,
  slots_removed        integer,
  assignments_removed  integer,
  reservations_removed integer,
  regions_removed      integer,
  locks_released       integer,
  images_removed       integer,   -- 5236
  image_paths          text[]     -- 5236: o cliente apaga estes arquivos DEPOIS
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
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
$$;

comment on function public.dismantle_my_collection_binder(uuid, text) is
  'Fichário Digital (5226 → 5229 → 5236): desmonta o fichário da proprietária sem convidadas (BINDER_HAS_GUESTS antes de remover), com token da prévia. Desde a 5236 remove também as imagens personalizadas e devolve images_removed e image_paths para o cliente apagar os arquivos depois. Não toca cartas, alocações nem progresso.';

revoke all on function public.dismantle_my_collection_binder(uuid, text) from public;
revoke all on function public.dismantle_my_collection_binder(uuid, text) from anon;
grant execute on function public.dismantle_my_collection_binder(uuid, text) to authenticated;

commit;
