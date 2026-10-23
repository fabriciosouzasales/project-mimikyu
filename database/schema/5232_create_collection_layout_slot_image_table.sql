/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5232 - Imagem personalizada do bolso: tabela + exclusividade
              (P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01, C-198 / LDM-196)
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: §5 — arquivo vinculado
              não pode ser apagado; política DELETE do bucket criada aqui)
              1.0 (2026-10-23)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-BINDER-CUSTOM-IMAGES-LIVE-APPLY-01, autorização expressa de
              Fabrício; ledger 20261023185205 `5232_create_collection_layout_slot_image_table`).
              Do `begin;` ao `commit;` byte a byte idêntica ao texto aplicado e
              ao arquivo da pasta database/proposals/2026-10-23-p2-binder-custom-images/
              (só este bloco Status difere). POST-1 13/13 PASS; baseline
              preservado (contagens e md5); harness 5852 NÃO EXECUTADO (cria
              dados — proibido no LIVE); prova funcional F1–F7 PENDENTE (sem
              prova comportamental).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

C-198: a imagem personalizada é um ELEMENTO VISUAL do fichário, não um
colecionável. Pertence ao bolso (portanto ao fichário), nunca a uma
coleção: no fichário compartilhado todas as participantes a veem.
Não é Physical Card, não é Allocation, não é Expected Content (C-42
continua exclusivamente editorial), não entra em progresso, valor,
contagem de cartas nem Lock.

Tabela-satélite do bolso, no mesmo desenho de slot_assignment (5115) e
slot_expected_content (5113):
  slot_id        PK; FK → slot ON DELETE RESTRICT. Imagem é CONTEÚDO
                 (como Region, 5119): a página só sai depois de removê-la
                 (5235); a desmontagem a remove explicitamente (5236).
  owner_user_id  dono (= dono da proprietária do fichário; gatilho). Serve
                 ao limite por usuário e à limpeza de órfãos (índice).
  storage_path   `<owner>/<layout>/<uuid>.(webp|jpg)` — UNIQUE (um arquivo
                 nunca serve dois bolsos), formato e dono por CHECK,
                 fichário por gatilho.
  focal_y        enquadramento vertical em % (0 = topo, 100 = base).
                 Não destrutivo: a imagem é exibida com object-fit cover e
                 object-position 50% focal_y%. Nunca distorce.

EXCLUSIVIDADE (gatilhos de última linha, mesmo princípio da 5118 — as
RPCs fazem precheck amigável, mas a regra não depende delas):
  slot_image INSERT/UPDATE   → bolso sem posição, sem reserva, solto,
                               fora de Region; slot_id e dono imutáveis;
                               dono e fichário do caminho = do bolso.
  slot_assignment INSERT/UPDATE OF slot_id     → destino sem imagem.
  slot_expected_content INSERT/UPDATE OF slot_id → destino sem imagem.
  collection_layout_slot UPDATE OF locked (false→true) → sem imagem.
  collection_layout_region INSERT/UPDATE        → retângulo sem imagem.
  Erro único: SLOT_HAS_IMAGE (55000) — nenhuma operação de carta,
  reserva, trava ou mesclagem SUBSTITUI uma imagem: todas recusam.
  Os contratos existentes (5131/5132/5128→5229/5130/5134) não mudam;
  só ganham esta recusa nova num caso que antes não existia.

CONCORRÊNCIA: toda escrita em bolso passa por
assert_collection_layout_mutable (5122: trava proprietária → fichário),
inclusive as RPCs novas (5233). Imagem e carta concorrentes no mesmo
bolso serializam na trava do fichário; a segunda vê a primeira e recusa.

DEFESA DA TABELA: RLS ligada sem políticas; REVOKE explícito de toda DML
e de SELECT para PUBLIC/anon/authenticated (§9 da 5119). Leitura só pelas
RPCs de 5234. Funções de gatilho SECURITY DEFINER, search_path vazio, sem
EXECUTE para a API.

ARQUIVO VINCULADO É INDELÉVEL (§5, AUDIT-CORRECTION-01): a política DELETE
do bucket só deixa apagar arquivo da própria pasta que NÃO esteja vinculado
a nenhum bolso, conferido por binder_slot_image_path_is_linked(). Assim a
limpeza de órfãos (5234), um retry tardio ou um bug do app nunca removem a
imagem de um bolso: a API do Storage só apaga do armazenamento as linhas
que o DELETE efetivamente removeu. A função é VOLATILE de propósito: sob
READ COMMITTED, cada chamada usa um retrato novo — inclusive na reavaliação
(EvalPlanQual) de uma linha que estava travada por um vínculo em andamento
(5233 trava o objeto FOR SHARE antes de vincular), então um DELETE que
esperou o vínculo terminar vê o vínculo e não apaga.

Como validar: Query 5852 (Seções 0, 1 e 2).
Como reverter (tabela vazia): drop policy binder_slot_image_delete_own on
storage.objects; drop dos 6 gatilhos, das 7 funções e da tabela, nesta ordem.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_guest') is null then
    raise exception 'PRECHECK 5232: aplique 5229/5230 antes';
  end if;
  if not exists (select 1 from storage.buckets b where b.id = 'binder-slot-image') then
    raise exception 'PRECHECK 5232: aplique 5231 antes';
  end if;
  if to_regclass('public.collection_layout_slot_image') is not null then
    raise exception 'PRECHECK 5232: collection_layout_slot_image já existe';
  end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
             and p.policyname = 'binder_slot_image_delete_own') then
    raise exception 'PRECHECK 5232: política binder_slot_image_delete_own já existe';
  end if;
end;
$pre$;

-- 1. Tabela -----------------------------------------------------------------------
create table public.collection_layout_slot_image (
  slot_id        uuid        primary key
                 references public.collection_layout_slot(id) on update restrict on delete restrict,
  owner_user_id  uuid        not null,
  storage_path   text        not null,
  focal_y        smallint    not null default 50,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint uq_collection_layout_slot_image_path unique (storage_path),
  constraint chk_collection_layout_slot_image_focal
    check (focal_y between 0 and 100),
  constraint chk_collection_layout_slot_image_path_format
    check (storage_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg)$'),
  constraint chk_collection_layout_slot_image_path_owner
    check (split_part(storage_path, '/', 1) = owner_user_id::text)
);

create index ix_collection_layout_slot_image_owner
  on public.collection_layout_slot_image (owner_user_id);

comment on table public.collection_layout_slot_image is
  'Fichário Digital (5232, C-198): imagem personalizada de um bolso. Elemento visual do fichário, não colecionável: não é carta, alocação, reserva nem progresso. Exclusiva com posição, reserva, trava e mesclagem (gatilhos). Arquivo privado no bucket binder-slot-image. Escrita só pelas RPCs 5233; leitura só pelas RPCs 5234.';

alter table public.collection_layout_slot_image enable row level security;

revoke all on public.collection_layout_slot_image from public, anon, authenticated;

-- 2. updated_at ----------------------------------------------------------------------
create function public.set_collection_layout_slot_image_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function public.set_collection_layout_slot_image_updated_at()
  from public, anon, authenticated;

create trigger trg_collection_layout_slot_image_updated_at
  before update on public.collection_layout_slot_image
  for each row execute function public.set_collection_layout_slot_image_updated_at();

-- 3. Integridade da própria imagem ---------------------------------------------------------
create function public.enforce_collection_layout_slot_image_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_page_id   uuid;
  v_row       integer;
  v_col       integer;
  v_locked    boolean;
  v_layout_id uuid;
  v_owner     uuid;
begin
  if tg_op = 'UPDATE' then
    if new.slot_id is distinct from old.slot_id
       or new.owner_user_id is distinct from old.owner_user_id then
      raise exception 'SLOT_IMAGE_IMMUTABLE_KEY' using errcode = '55000',
        hint = 'slot_id e owner_user_id não mudam; remova e inclua de novo';
    end if;
  end if;

  select s.page_id, s.row_index, s.column_index, s.locked, p.layout_id, c.owner_user_id
    into v_page_id, v_row, v_col, v_locked, v_layout_id, v_owner
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  join public.collection_layout l      on l.id = p.layout_id
  join public.collection c             on c.id = l.collection_id
  where s.id = new.slot_id;

  if not found then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if new.owner_user_id <> v_owner then
    raise exception 'SLOT_IMAGE_OWNER_MISMATCH' using errcode = '23514';
  end if;
  if split_part(new.storage_path, '/', 2) <> v_layout_id::text then
    raise exception 'INVALID_IMAGE_PATH' using errcode = '22023',
      hint = 'o arquivo precisa estar na pasta do fichário do bolso';
  end if;

  -- Exclusividade (só na criação; no UPDATE a chave é imutável e as outras
  -- tabelas já recusam escrever num bolso com imagem).
  if tg_op = 'INSERT' then
    if v_locked then
      raise exception 'SLOT_LOCKED' using errcode = '55000';
    end if;
    if exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = new.slot_id) then
      raise exception 'SLOT_OCCUPIED' using errcode = '55000';
    end if;
    if exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = new.slot_id) then
      raise exception 'SLOT_RESERVED' using errcode = '55000';
    end if;
    if exists (select 1 from public.collection_layout_region r
               where r.page_id = v_page_id
                 and v_row between r.top_row and r.top_row + r.height - 1
                 and v_col between r.left_column and r.left_column + r.width - 1) then
      raise exception 'SLOT_IN_REGION' using errcode = '55000';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_collection_layout_slot_image_integrity()
  from public, anon, authenticated;

create trigger trg_collection_layout_slot_image_integrity
  before insert or update on public.collection_layout_slot_image
  for each row execute function public.enforce_collection_layout_slot_image_integrity();

-- 4. Exclusividade vista pelas outras tabelas --------------------------------------------
-- 4a. Posição e reserva: destino com imagem é recusado.
create function public.enforce_slot_without_custom_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = new.slot_id) then
    raise exception 'SLOT_HAS_IMAGE' using errcode = '55000',
      hint = 'este bolso tem uma imagem personalizada — remova a imagem antes';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_slot_without_custom_image()
  from public, anon, authenticated;

create trigger trg_slot_assignment_without_custom_image
  before insert or update of slot_id on public.collection_layout_slot_assignment
  for each row execute function public.enforce_slot_without_custom_image();

create trigger trg_slot_expected_content_without_custom_image
  before insert or update of slot_id on public.collection_layout_slot_expected_content
  for each row execute function public.enforce_slot_without_custom_image();

-- 4b. Trava: travar um bolso com imagem é recusado (destravar sempre pode).
create function public.enforce_slot_lock_without_custom_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.locked and not old.locked
     and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = new.id) then
    raise exception 'SLOT_HAS_IMAGE' using errcode = '55000',
      hint = 'bolso com imagem personalizada não é fixado';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_slot_lock_without_custom_image()
  from public, anon, authenticated;

create trigger trg_slot_lock_without_custom_image
  before update of locked on public.collection_layout_slot
  for each row execute function public.enforce_slot_lock_without_custom_image();

-- 4c. Mesclagem: retângulo que contenha bolso com imagem é recusado.
create function public.enforce_region_without_custom_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.collection_layout_slot s
    join public.collection_layout_slot_image i on i.slot_id = s.id
    where s.page_id = new.page_id
      and s.row_index between new.top_row and new.top_row + new.height - 1
      and s.column_index between new.left_column and new.left_column + new.width - 1
  ) then
    raise exception 'SLOT_HAS_IMAGE' using errcode = '55000',
      hint = 'a mesclagem inclui bolso com imagem personalizada';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_region_without_custom_image()
  from public, anon, authenticated;

create trigger trg_region_without_custom_image
  before insert or update on public.collection_layout_region
  for each row execute function public.enforce_region_without_custom_image();

-- 5. Arquivo vinculado não é apagado (política DELETE do bucket) ---------------------
-- Só responde sobre a PRÓPRIA pasta (outro usuário → false, sem oráculo).
create function public.binder_slot_image_path_is_linked(p_name text)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  select p_name is not null
     and split_part(p_name, '/', 1) = (select auth.uid())::text
     and exists (select 1 from public.collection_layout_slot_image i
                 where i.storage_path = p_name);
$$;

comment on function public.binder_slot_image_path_is_linked(text) is
  'Fichário Digital (5232, AUDIT-CORRECTION-01): true se o arquivo da própria pasta está vinculado a um bolso. Usada pela política DELETE de binder-slot-image para que nenhum arquivo em uso seja apagado. VOLATILE de propósito (retrato novo por chamada).';

revoke all on function public.binder_slot_image_path_is_linked(text) from public, anon;
grant execute on function public.binder_slot_image_path_is_linked(text) to authenticated;

create policy binder_slot_image_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'binder-slot-image'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and not public.binder_slot_image_path_is_linked(name)
  );

commit;
