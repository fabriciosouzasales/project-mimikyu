/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5239 - Create Collection Layout Region Image (+ proteção do Storage)
Versão......: 1.1 (REVIEW-01: trava por usuário antes da checagem cruzada de caminho)
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23 (P2-BINDER-LAYOUT-CUSTOMIZATION-IMPLEMENTATION-PROPOSAL-01)
Descrição...:
Imagem decorativa única de uma mesclagem de 2 bolsos (D7: a mesclagem só
existe com imagem; D8: enquadramento em 2 eixos). Mesmo bucket privado
binder-slot-image, mesma pasta `<dono>/<fichário>/<uuid>.(webp|jpg)`,
mesmos limites (512 KB, WebP/JPEG) — um arquivo, nunca duplicado nem
dividido.

PROTEÇÃO DO STORAGE SEM TOCAR A POLÍTICA:
A política DELETE `binder_slot_image_delete_own` (5232) delega a decisão a
`public.binder_slot_image_path_is_linked(name)`. Esta migration troca SÓ
o corpo dessa função (mesma assinatura, mesmo dono, mesmos grants) para
reconhecer também os vínculos de mesclagem. Nenhum ALTER/CREATE POLICY em
storage.objects; nenhuma trava exclusiva de storage.objects.

Também:
- exclusividade do caminho entre as duas tabelas (um arquivo não pode estar
  ligado a um bolso e a uma mesclagem ao mesmo tempo) → IMAGE_PATH_IN_USE;
- teto de 500 imagens por usuário passa a contar as duas tabelas
  (gatilho em ambas, mesma trava consultiva por usuário da 5233);
- limpeza de envios abandonados (5234) e resumo de cota passam a enxergar
  as imagens de mesclagem — sem isso, arquivos vinculados seriam listados
  como "soltos" a cada visita (a exclusão seria recusada, mas inutilmente).

Dependências: 5232–5234, 5237 (canônicas), 5238 (esta proposta).
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_image') is null
     or to_regprocedure('public.binder_slot_image_path_is_linked(text)') is null
     or to_regprocedure('public.list_my_unlinked_binder_slot_images(integer)') is null
     or to_regprocedure('public.get_my_binder_slot_image_summary(uuid)') is null then
    raise exception 'PRECHECK 5239: pacote 5232–5234 ausente';
  end if;
  if to_regprocedure('public.enforce_slot_outside_layout_region()') is null then
    raise exception 'PRECHECK 5239: aplique 5238 antes';
  end if;
  if to_regclass('public.collection_layout_region_image') is not null then
    raise exception 'PRECHECK 5239: já aplicada';
  end if;
  -- A política DELETE precisa continuar delegando à função (5232): se alguém a
  -- reescreveu, trocar a função não protegeria nada.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'binder_slot_image_delete_own' and cmd = 'DELETE'
      and qual like '%binder_slot_image_path_is_linked%') then
    raise exception 'PRECHECK 5239: política DELETE do bucket não delega mais a binder_slot_image_path_is_linked';
  end if;
end;
$pre$;

-- 1. Tabela ---------------------------------------------------------------------------
create table public.collection_layout_region_image (
  region_id      uuid        primary key
                 references public.collection_layout_region(id) on update restrict on delete restrict,
  owner_user_id  uuid        not null,
  storage_path   text        not null,
  focal_x        smallint    not null default 50,
  focal_y        smallint    not null default 50,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint uq_collection_layout_region_image_path unique (storage_path),
  constraint chk_collection_layout_region_image_focal
    check (focal_x between 0 and 100 and focal_y between 0 and 100),
  constraint chk_collection_layout_region_image_path_format
    check (storage_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg)$'),
  constraint chk_collection_layout_region_image_path_owner
    check (split_part(storage_path, '/', 1) = owner_user_id::text)
);

create index ix_collection_layout_region_image_owner
  on public.collection_layout_region_image (owner_user_id);

comment on table public.collection_layout_region_image is
  'Fichário Digital (5239): imagem decorativa única de uma mesclagem horizontal de 2 bolsos. Elemento visual, não colecionável. Mesmo bucket privado binder-slot-image. Escrita só pelas RPCs 5240; leitura só pela 5241.';

alter table public.collection_layout_region_image enable row level security;
revoke all on public.collection_layout_region_image from public, anon, authenticated;

create trigger trg_collection_layout_region_image_updated_at
  before update on public.collection_layout_region_image
  for each row execute function public.set_collection_layout_slot_image_updated_at();

-- 2. Integridade da imagem de mesclagem -------------------------------------------------
create function public.enforce_collection_layout_region_image_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_page_id   uuid;
  v_top       integer;
  v_left      integer;
  v_height    integer;
  v_width     integer;
  v_layout_id uuid;
  v_owner     uuid;
begin
  if tg_op = 'UPDATE'
     and (new.region_id is distinct from old.region_id
          or new.owner_user_id is distinct from old.owner_user_id) then
    raise exception 'REGION_IMAGE_IMMUTABLE_KEY' using errcode = '55000';
  end if;

  select r.page_id, r.top_row, r.left_column, r.height, r.width, p.layout_id, c.owner_user_id
    into v_page_id, v_top, v_left, v_height, v_width, v_layout_id, v_owner
  from public.collection_layout_region r
  join public.collection_layout_page p on p.id = r.page_id
  join public.collection_layout l      on l.id = p.layout_id
  join public.collection c             on c.id = l.collection_id
  where r.id = new.region_id;
  if not found then
    raise exception 'REGION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if new.owner_user_id <> v_owner then
    raise exception 'REGION_IMAGE_OWNER_MISMATCH' using errcode = '23514';
  end if;
  if split_part(new.storage_path, '/', 2) <> v_layout_id::text then
    raise exception 'INVALID_IMAGE_PATH' using errcode = '22023',
      hint = 'o arquivo precisa estar na pasta do fichário';
  end if;
  -- Escopo aprovado da primeira versão: exatamente 2 bolsos lado a lado.
  if v_height <> 1 or v_width <> 2 then
    raise exception 'REGION_SHAPE_NOT_SUPPORTED' using errcode = '55000';
  end if;
  -- REVIEW-01: serializa por usuário ANTES da checagem cruzada (a UNIQUE só
  -- protege dentro de cada tabela; sem a trava, duas transações simultâneas
  -- poderiam ligar o mesmo arquivo a um bolso e a uma mesclagem).
  perform pg_advisory_xact_lock(hashtextextended('binder-slot-image:' || new.owner_user_id::text, 0));
  if exists (select 1 from public.collection_layout_slot_image i where i.storage_path = new.storage_path) then
    raise exception 'IMAGE_PATH_IN_USE' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_collection_layout_region_image_integrity()
  from public, anon, authenticated;

create trigger trg_collection_layout_region_image_integrity
  before insert or update on public.collection_layout_region_image
  for each row execute function public.enforce_collection_layout_region_image_integrity();

-- 3. O mesmo arquivo não pode ir para um bolso se já está numa mesclagem -------------------
create function public.enforce_slot_image_path_not_in_region()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('binder-slot-image:' || new.owner_user_id::text, 0));   -- REVIEW-01
  if exists (select 1 from public.collection_layout_region_image ri where ri.storage_path = new.storage_path) then
    raise exception 'IMAGE_PATH_IN_USE' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_slot_image_path_not_in_region()
  from public, anon, authenticated;

create trigger trg_slot_image_path_not_in_region
  before insert or update of storage_path on public.collection_layout_slot_image
  for each row execute function public.enforce_slot_image_path_not_in_region();

-- 4. Teto único de 500 imagens por usuário (bolsos + mesclagens) -------------------------
create function public.enforce_binder_custom_image_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_images constant integer := 500;
  v_count integer;
begin
  -- Mesma chave da 5233: serializa por usuário as duas tabelas.
  perform pg_advisory_xact_lock(hashtextextended('binder-slot-image:' || new.owner_user_id::text, 0));
  select (select count(*) from public.collection_layout_slot_image i where i.owner_user_id = new.owner_user_id)
       + (select count(*) from public.collection_layout_region_image r where r.owner_user_id = new.owner_user_id)
    into v_count;
  if v_count >= c_max_images then
    raise exception 'IMAGE_QUOTA_REACHED' using errcode = '55000',
      hint = 'limite de 500 imagens personalizadas — remova alguma para incluir outra';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_binder_custom_image_quota()
  from public, anon, authenticated;

create trigger trg_slot_image_quota
  before insert on public.collection_layout_slot_image
  for each row execute function public.enforce_binder_custom_image_quota();

create trigger trg_region_image_quota
  before insert on public.collection_layout_region_image
  for each row execute function public.enforce_binder_custom_image_quota();

-- 5. Arquivo vinculado (bolso OU mesclagem) não é apagado — mesma assinatura -------------
create or replace function public.binder_slot_image_path_is_linked(p_name text)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  select p_name is not null
     and split_part(p_name, '/', 1) = (select auth.uid())::text
     and (exists (select 1 from public.collection_layout_slot_image i
                  where i.storage_path = p_name)
          or exists (select 1 from public.collection_layout_region_image r
                     where r.storage_path = p_name));
$$;

comment on function public.binder_slot_image_path_is_linked(text) is
  'Fichário Digital (5232 → 5239): true se o arquivo da própria pasta está vinculado a um bolso OU a uma mesclagem. Usada pela política DELETE de binder-slot-image para que nenhum arquivo em uso seja apagado. VOLATILE de propósito.';

-- 6. Limpeza e cota enxergam as mesclagens — mesmas assinaturas ---------------------------
create or replace function public.list_my_unlinked_binder_slot_images(p_limit integer default 50)
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
    and not exists (select 1 from public.collection_layout_region_image r
                    where r.storage_path = o.name)
  order by o.created_at
  limit v_limit;
end;
$$;

create or replace function public.get_my_binder_slot_image_summary(p_collection_id uuid)
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
      (select count(*)::integer
       from public.collection_layout_page p
       join public.collection_layout_slot s       on s.page_id = p.id
       join public.collection_layout_slot_image i on i.slot_id = s.id
       where p.layout_id = v_layout)
    + (select count(*)::integer
       from public.collection_layout_page p
       join public.collection_layout_region rg          on rg.page_id = p.id
       join public.collection_layout_region_image ri    on ri.region_id = rg.id
       where p.layout_id = v_layout)) end;
  user_image_count :=
      (select count(*)::integer from public.collection_layout_slot_image i where i.owner_user_id = auth.uid())
    + (select count(*)::integer from public.collection_layout_region_image r where r.owner_user_id = auth.uid());
  user_image_limit := 500;
  return next;
end;
$$;

-- Pós-checagem --------------------------------------------------------------------------
do $post$
begin
  if pg_get_functiondef('public.binder_slot_image_path_is_linked(text)'::regprocedure)
       not like '%collection_layout_region_image%' then
    raise exception 'POSTCHECK 5239: função de vínculo não reconhece mesclagens';
  end if;
  if has_function_privilege('anon', 'public.binder_slot_image_path_is_linked(text)', 'EXECUTE') then
    raise exception 'POSTCHECK 5239: anon com EXECUTE na função de vínculo';
  end if;
  if has_table_privilege('authenticated', 'public.collection_layout_region_image', 'SELECT')
     or has_table_privilege('authenticated', 'public.collection_layout_region_image', 'INSERT') then
    raise exception 'POSTCHECK 5239: tabela exposta a authenticated';
  end if;
end;
$post$;

commit;

/*
Resultado esperado: tabela vazia; 4 gatilhos novos; 3 funções com corpo
novo e assinatura/retorno/grants inalterados; política DELETE intocada.
Como validar (LIVE_90, POST-2): pg_policies idêntico ao PRE (fingerprint);
binder_slot_image_path_is_linked contém collection_layout_region_image;
EXECUTE: authenticated true, anon false.
*/
