-- Query 6132 | Pokédex P2 Lote A — fundação das imagens das espécies (Official Artwork)
--
-- Status: CONFIRMADO EXECUTADO em 2026-10-12 via Supabase MCP (apply_migration
-- "6132_create_pokemon_species_artwork_foundation"), versão de execução v1.0 — conteúdo
-- idêntico à proposta apresentada (sha256 do arquivo de proposta 82792a1a…5b9e71).
-- Validação: Query 6842 v1.1 = "6842 PASS" (rollback integral dos fixtures; 0 linhas e
-- 0 objetos remanescentes). Postcheck: contagens e hashes de espécies/gerações, ACLs,
-- policies e funções pré-existentes idênticos ao baseline pré-execução.
--
-- Objetivo
-- Preparar, sem importar nenhuma imagem, tudo o que o processo Node + Sharp do Lote B
-- precisa para registrar a imagem principal de cada uma das 1.025 espécies:
--   1. Tabela pokemon_species_artwork — 1 imagem principal por espécie, com proveniência
--      (ids de origem, URL, data), original PNG + versão WebP de galeria (caminho,
--      dimensões, tamanho, checksum), status de processamento e situação de direitos.
--   2. Funções administrativas (SECURITY DEFINER, public.is_admin() obrigatório):
--        admin_record_pokemon_species_artwork_import(...)   — registra/troca a imagem
--        admin_record_pokemon_species_artwork_failure(...)  — registra falha sem tocar
--                                                             em imagem válida
--        admin_list_pokemon_species_artwork_status(...)     — cobertura por espécie
--   3. Bucket público pokemon-species-artwork (PNG/WebP, 1 MB) com escrita só para admin.
--   4. get_pokedex_national_species (Query 6131) estendida com UMA coluna, artwork_path.
--
-- Decisões de desenho
-- - Vínculo por identificadores, nunca por nome nem por igualdade presumida de ids:
--   source_species_id precisa ser exatamente o external_species_id já registrado para a
--   espécie em pokemon_species_external_reference (fonte POKEAPI); source_pokemon_id
--   (forma padrão) é gravado como veio da PokéAPI, sem suposição de ser igual ao número.
-- - Caminhos endereçados por conteúdo e verificados pelo banco:
--     official-artwork/<NNNN>/original-<sha256[0:16]>.png
--     official-artwork/<NNNN>/w320-<sha256[0:16]>.webp
--   <NNNN> = número nacional da espécie; o hash = início do checksum do próprio arquivo.
--   Um arquivo nunca é sobrescrito: troca de imagem = arquivo novo + troca do registro
--   (sem cache de CDN obsoleto e sem janela em que a imagem válida fica corrompida).
--   O registro só é aceito se os dois objetos já existirem no bucket.
-- - Falha nunca derruba imagem válida: em espécie já IMPORTED, a falha só atualiza os
--   campos de diagnóstico (last_error_*, attempt_count); caminhos e status ficam intactos.
-- - Direitos: rights_status = THIRD_PARTY_UNLICENSED por padrão, com nota explícita. O
--   armazenamento próprio garante disponibilidade e rastreabilidade, não autorização.
-- - Não reutiliza asset_import_run/asset_import_failure: as duas pertencem ao pipeline
--   de cartas (CHECKs de run_type e card_id obrigatório); alterá-las tocaria outro módulo.
--   O status por espécie desta tabela cobre pendente/importada/falha e o reprocessamento.
-- - Tabela sem GRANT para anon/authenticated (mesmo padrão de pokemon_species): toda
--   leitura/escrita passa pelas funções. O colecionador só recebe artwork_path.
--
-- Escopo: nenhuma alteração em tabelas existentes, em dados de espécies/cartas, em
-- card_asset/card-front ou em outros módulos.

-- ---------------------------------------------------------------------------------
-- 1. Tabela
-- ---------------------------------------------------------------------------------
create table public.pokemon_species_artwork (
  id uuid primary key default gen_random_uuid(),
  pokemon_species_id uuid not null references public.pokemon_species(id) on delete restrict,
  asset_source_id uuid not null references public.asset_source(id) on delete restrict,
  artwork_kind text not null default 'OFFICIAL_ARTWORK',
  status text not null,
  source_species_id text,
  source_pokemon_id text,
  source_url text,
  retrieved_at timestamptz,
  original_storage_path text,
  original_mime_type text,
  original_width integer,
  original_height integer,
  original_size_bytes integer,
  original_checksum_sha256 text,
  display_storage_path text,
  display_mime_type text,
  display_width integer,
  display_height integer,
  display_size_bytes integer,
  display_checksum_sha256 text,
  rights_status text not null default 'THIRD_PARTY_UNLICENSED',
  rights_note text not null default 'Arte oficial © Nintendo / Creatures / GAME FREAK / The Pokémon Company. Obtida via PokéAPI (repositório PokeAPI/sprites, sem licença declarada); a disponibilidade na fonte não concede autorização de uso comercial.',
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_error_code text,
  last_error_message text,
  imported_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_pokemon_species_artwork_species unique (pokemon_species_id),
  constraint ck_pokemon_species_artwork_kind check (artwork_kind = 'OFFICIAL_ARTWORK'),
  constraint ck_pokemon_species_artwork_status check (status in ('IMPORTED', 'FAILED')),
  constraint ck_pokemon_species_artwork_rights check (rights_status in ('THIRD_PARTY_UNLICENSED', 'LICENSED')),
  constraint ck_pokemon_species_artwork_rights_note check (btrim(rights_note) <> ''),
  constraint ck_pokemon_species_artwork_attempts check (attempt_count >= 0),
  constraint ck_pokemon_species_artwork_error_code check (last_error_code is null or last_error_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint ck_pokemon_species_artwork_source_ids check (
    (source_species_id is null or source_species_id ~ '^[1-9][0-9]*$')
    and (source_pokemon_id is null or source_pokemon_id ~ '^[1-9][0-9]*$')
  ),
  constraint ck_pokemon_species_artwork_source_url check (source_url is null or source_url like 'https://%'),
  -- IMPORTED: imagem completa e coerente; FAILED: nunca importada (sem arquivos).
  -- coalesce(..., false): numa CHECK, NULL passaria; aqui campo ausente reprova.
  constraint ck_pokemon_species_artwork_imported_complete check (
    status <> 'IMPORTED' or coalesce((
      source_species_id is not null and source_pokemon_id is not null
      and source_url is not null and retrieved_at is not null and imported_at is not null
      and original_storage_path ~ '^official-artwork/[0-9]{4}/original-[0-9a-f]{16}\.png$'
      and original_mime_type = 'image/png'
      and original_width between 1 and 4096 and original_height between 1 and 4096
      and original_size_bytes between 1 and 1048576
      and original_checksum_sha256 ~ '^[0-9a-f]{64}$'
      and display_storage_path ~ '^official-artwork/[0-9]{4}/w320-[0-9a-f]{16}\.webp$'
      and display_mime_type = 'image/webp'
      and display_width between 1 and original_width and display_height between 1 and original_height
      and display_size_bytes between 1 and 1048576
      and display_checksum_sha256 ~ '^[0-9a-f]{64}$'
    ), false)
  ),
  constraint ck_pokemon_species_artwork_failed_empty check (
    status <> 'FAILED' or (
      original_storage_path is null and display_storage_path is null
      and original_checksum_sha256 is null and display_checksum_sha256 is null
      and imported_at is null and last_error_code is not null
    )
  )
);

create index ix_pokemon_species_artwork_status on public.pokemon_species_artwork (status);

comment on table public.pokemon_species_artwork is
  'Pokédex P2 (Query 6132): imagem principal (Official Artwork) por espécie — proveniência, original PNG, versão WebP de galeria, status e direitos. Escrita só via funções admin.';

create or replace function public.touch_pokemon_species_artwork_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.touch_pokemon_species_artwork_updated_at() from public, anon, authenticated;

create trigger trg_pokemon_species_artwork_touch_updated_at
  before update on public.pokemon_species_artwork
  for each row execute function public.touch_pokemon_species_artwork_updated_at();

alter table public.pokemon_species_artwork enable row level security;
revoke all on table public.pokemon_species_artwork from anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 2. Registro de importação bem-sucedida (admin)
-- ---------------------------------------------------------------------------------
create or replace function public.admin_record_pokemon_species_artwork_import(
  p_national_dex_number integer,
  p_source_species_id text,
  p_source_pokemon_id text,
  p_source_url text,
  p_retrieved_at timestamptz,
  p_original_storage_path text,
  p_original_width integer,
  p_original_height integer,
  p_original_size_bytes integer,
  p_original_checksum_sha256 text,
  p_display_storage_path text,
  p_display_width integer,
  p_display_height integer,
  p_display_size_bytes integer,
  p_display_checksum_sha256 text
)
returns jsonb
language plpgsql security definer volatile set search_path = ''
as $$
declare
  v_species_id uuid;
  v_source_id uuid;
  v_dex text;
  v_existing public.pokemon_species_artwork%rowtype;
  v_action text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  select s.id into v_species_id
    from public.pokemon_species s
   where s.national_dex_number = p_national_dex_number and s.is_active;
  if v_species_id is null then
    raise exception 'SPECIES_NOT_FOUND: %', p_national_dex_number using errcode = 'P0001';
  end if;

  select a.id into v_source_id from public.asset_source a where a.code = 'POKEAPI' and a.is_active;
  if v_source_id is null then
    raise exception 'SOURCE_NOT_FOUND: POKEAPI' using errcode = 'P0001';
  end if;

  -- Vínculo pela referência oficial já cadastrada, não por nome nem por número.
  if not exists (
    select 1 from public.pokemon_species_external_reference r
     where r.pokemon_species_id = v_species_id
       and r.asset_source_id = v_source_id
       and r.is_active
       and r.external_species_id = p_source_species_id
  ) then
    raise exception 'SOURCE_SPECIES_MISMATCH: espécie % não tem referência POKEAPI %',
      p_national_dex_number, coalesce(p_source_species_id, '<null>') using errcode = 'P0001';
  end if;

  -- Caminhos endereçados por conteúdo, presos à espécie e ao checksum do próprio arquivo.
  v_dex := lpad(p_national_dex_number::text, 4, '0');
  if p_original_storage_path is distinct from format('official-artwork/%s/original-%s.png', v_dex, left(p_original_checksum_sha256, 16))
     or p_display_storage_path is distinct from format('official-artwork/%s/w320-%s.webp', v_dex, left(p_display_checksum_sha256, 16)) then
    raise exception 'STORAGE_PATH_MISMATCH: caminhos não correspondem à espécie % e aos checksums', p_national_dex_number
      using errcode = 'P0001';
  end if;

  if (select count(*) from storage.objects o
       where o.bucket_id = 'pokemon-species-artwork'
         and o.name in (p_original_storage_path, p_display_storage_path)) <> 2 then
    raise exception 'STORAGE_OBJECT_MISSING: envie os dois arquivos antes de registrar' using errcode = 'P0001';
  end if;

  select * into v_existing from public.pokemon_species_artwork w
   where w.pokemon_species_id = v_species_id
   for update;

  if found and v_existing.status = 'IMPORTED'
     and v_existing.original_checksum_sha256 = p_original_checksum_sha256
     and v_existing.display_checksum_sha256 = p_display_checksum_sha256
     and v_existing.original_storage_path = p_original_storage_path
     and v_existing.display_storage_path = p_display_storage_path then
    return jsonb_build_object('national_dex_number', p_national_dex_number, 'action', 'UNCHANGED');
  end if;

  v_action := case when not found then 'INSERTED'
                   when v_existing.status = 'IMPORTED' then 'REPLACED'
                   else 'RECOVERED' end;

  -- As CHECKs da tabela validam formato, dimensões, tamanhos e checksums.
  insert into public.pokemon_species_artwork as w (
    pokemon_species_id, asset_source_id, status,
    source_species_id, source_pokemon_id, source_url, retrieved_at,
    original_storage_path, original_mime_type, original_width, original_height,
    original_size_bytes, original_checksum_sha256,
    display_storage_path, display_mime_type, display_width, display_height,
    display_size_bytes, display_checksum_sha256,
    attempt_count, last_attempt_at, last_error_code, last_error_message, imported_at
  ) values (
    v_species_id, v_source_id, 'IMPORTED',
    p_source_species_id, p_source_pokemon_id, p_source_url, p_retrieved_at,
    p_original_storage_path, 'image/png', p_original_width, p_original_height,
    p_original_size_bytes, p_original_checksum_sha256,
    p_display_storage_path, 'image/webp', p_display_width, p_display_height,
    p_display_size_bytes, p_display_checksum_sha256,
    1, now(), null, null, now()
  )
  on conflict (pokemon_species_id) do update set
    asset_source_id = excluded.asset_source_id,
    status = 'IMPORTED',
    source_species_id = excluded.source_species_id,
    source_pokemon_id = excluded.source_pokemon_id,
    source_url = excluded.source_url,
    retrieved_at = excluded.retrieved_at,
    original_storage_path = excluded.original_storage_path,
    original_mime_type = excluded.original_mime_type,
    original_width = excluded.original_width,
    original_height = excluded.original_height,
    original_size_bytes = excluded.original_size_bytes,
    original_checksum_sha256 = excluded.original_checksum_sha256,
    display_storage_path = excluded.display_storage_path,
    display_mime_type = excluded.display_mime_type,
    display_width = excluded.display_width,
    display_height = excluded.display_height,
    display_size_bytes = excluded.display_size_bytes,
    display_checksum_sha256 = excluded.display_checksum_sha256,
    attempt_count = w.attempt_count + 1,
    last_attempt_at = now(),
    last_error_code = null,
    last_error_message = null,
    imported_at = now();

  return jsonb_build_object('national_dex_number', p_national_dex_number, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------------
-- 3. Registro de falha (admin) — nunca derruba imagem válida
-- ---------------------------------------------------------------------------------
create or replace function public.admin_record_pokemon_species_artwork_failure(
  p_national_dex_number integer,
  p_error_code text,
  p_error_message text,
  p_source_url text default null
)
returns jsonb
language plpgsql security definer volatile set search_path = ''
as $$
declare
  v_species_id uuid;
  v_source_id uuid;
  v_message text;
  v_status text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  select s.id into v_species_id
    from public.pokemon_species s
   where s.national_dex_number = p_national_dex_number and s.is_active;
  if v_species_id is null then
    raise exception 'SPECIES_NOT_FOUND: %', p_national_dex_number using errcode = 'P0001';
  end if;

  select a.id into v_source_id from public.asset_source a where a.code = 'POKEAPI' and a.is_active;
  if v_source_id is null then
    raise exception 'SOURCE_NOT_FOUND: POKEAPI' using errcode = 'P0001';
  end if;

  v_message := left(nullif(btrim(coalesce(p_error_message, '')), ''), 1000);
  if v_message is null then
    raise exception 'ERROR_MESSAGE_REQUIRED' using errcode = 'P0001';
  end if;

  insert into public.pokemon_species_artwork as w (
    pokemon_species_id, asset_source_id, status, source_url,
    attempt_count, last_attempt_at, last_error_code, last_error_message
  ) values (
    v_species_id, v_source_id, 'FAILED', p_source_url,
    1, now(), p_error_code, v_message
  )
  on conflict (pokemon_species_id) do update set
    -- Imagem válida (IMPORTED) é preservada: só o diagnóstico é atualizado.
    source_url = case when w.status = 'IMPORTED' then w.source_url else coalesce(excluded.source_url, w.source_url) end,
    attempt_count = w.attempt_count + 1,
    last_attempt_at = now(),
    last_error_code = excluded.last_error_code,
    last_error_message = excluded.last_error_message
  returning w.status into v_status;

  return jsonb_build_object(
    'national_dex_number', p_national_dex_number,
    'status', v_status,
    'image_preserved', v_status = 'IMPORTED'
  );
end;
$$;

-- ---------------------------------------------------------------------------------
-- 4. Cobertura por espécie (admin) — PENDING = espécie ainda sem registro
-- ---------------------------------------------------------------------------------
create or replace function public.admin_list_pokemon_species_artwork_status(
  p_status text default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (
  national_dex_number integer,
  species_name text,
  artwork_status text,
  attempt_count integer,
  last_attempt_at timestamptz,
  last_error_code text,
  last_error_message text,
  source_pokemon_id text,
  original_storage_path text,
  display_storage_path text,
  display_size_bytes integer,
  rights_status text,
  imported_at timestamptz,
  total_count bigint
)
language plpgsql security definer stable set search_path = ''
as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('PENDING', 'IMPORTED', 'FAILED') then
    raise exception 'INVALID_STATUS: %', p_status using errcode = '22023';
  end if;

  return query
  with artwork_rows as (
    select
      s.national_dex_number,
      s.canonical_name::text as species_name,
      coalesce(w.status, 'PENDING') as artwork_status,
      coalesce(w.attempt_count, 0) as attempt_count,
      w.last_attempt_at, w.last_error_code, w.last_error_message, w.source_pokemon_id,
      w.original_storage_path, w.display_storage_path, w.display_size_bytes,
      w.rights_status, w.imported_at
    from public.pokemon_species s
    left join public.pokemon_species_artwork w on w.pokemon_species_id = s.id
    where s.is_active
  )
  select r.*, count(*) over () as total_count
    from artwork_rows r
   where p_status is null or r.artwork_status = p_status
   order by r.national_dex_number
   limit least(greatest(coalesce(p_limit, 200), 1), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.admin_record_pokemon_species_artwork_import(integer, text, text, text, timestamptz, text, integer, integer, integer, text, text, integer, integer, integer, text) from public, anon;
revoke all on function public.admin_record_pokemon_species_artwork_failure(integer, text, text, text) from public, anon;
revoke all on function public.admin_list_pokemon_species_artwork_status(text, integer, integer) from public, anon;
grant execute on function public.admin_record_pokemon_species_artwork_import(integer, text, text, text, timestamptz, text, integer, integer, integer, text, text, integer, integer, integer, text) to authenticated;
grant execute on function public.admin_record_pokemon_species_artwork_failure(integer, text, text, text) to authenticated;
grant execute on function public.admin_list_pokemon_species_artwork_status(text, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------------
-- 5. Leitura da Pokédex Nacional (6131) + artwork_path
--    Mesmo corpo, mesma busca, mesmos filtros, mesma ordem; a única diferença é a
--    coluna artwork_path (caminho da versão WebP, só quando IMPORTED; NULL = moldura).
--    Mudar a lista de colunas de retorno exige DROP + CREATE.
-- ---------------------------------------------------------------------------------
drop function public.get_pokedex_national_species(text, integer);

create function public.get_pokedex_national_species(
  p_query text default null,
  p_generation integer default null
)
returns table (
  national_dex_number integer,
  species_name text,
  generation_code text,
  generation_ordinal integer,
  artwork_path text
)
language plpgsql security definer stable set search_path = ''
as $$
declare
  v_query text;
  v_digits text;
  v_number integer;
  v_name_key text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_query := nullif(btrim(left(coalesce(p_query, ''), 64)), '');

  if v_query is not null then
    v_digits := replace(replace(v_query, '#', ''), ' ', '');
    if v_digits <> '' and length(v_digits) <= 5 and translate(v_digits, '0123456789', '') = '' then
      v_number := v_digits::integer;
    else
      v_name_key := translate(lower(extensions.unaccent(v_query)), ' .''’:-♀♂', '');
    end if;
  end if;

  return query
  select
    s.national_dex_number,
    s.canonical_name::text,
    g.code::text,
    g.ordinal_number,
    case when w.status = 'IMPORTED' then w.display_storage_path end
  from public.pokemon_species s
  join public.pokemon_generation g on g.id = s.generation_id and g.is_active
  left join public.pokemon_species_artwork w on w.pokemon_species_id = s.id
  where s.is_active
    and (p_generation is null or g.ordinal_number = p_generation)
    and (
      v_query is null
      or (v_number is not null and s.national_dex_number = v_number)
      or (
        v_number is null
        and v_name_key <> ''
        and strpos(translate(lower(extensions.unaccent(s.canonical_name::text)), ' .''’:-♀♂', ''), v_name_key) > 0
      )
    )
  order by s.national_dex_number;
end;
$$;

comment on function public.get_pokedex_national_species(text, integer) is
  'Pokédex (Queries 6131/6132): espécies da Pokédex Nacional (número, nome oficial, geração, caminho da imagem WebP quando importada), com busca por número ou nome e filtro por geração. Leitura para usuários autenticados; sem colunas administrativas.';

revoke all on function public.get_pokedex_national_species(text, integer) from public;
revoke all on function public.get_pokedex_national_species(text, integer) from anon;
grant execute on function public.get_pokedex_national_species(text, integer) to authenticated;

-- ---------------------------------------------------------------------------------
-- 6. Storage: bucket público, PNG/WebP, 1 MB; escrita só para admin, sem UPDATE
--    (arquivos são imutáveis por endereçamento de conteúdo). Leitura pública pelo
--    endpoint público do bucket — sem policy de SELECT, a listagem do bucket pela API
--    continua fechada para não-admins.
-- ---------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pokemon-species-artwork', 'pokemon-species-artwork', true, 1048576, array['image/png', 'image/webp']);

create policy pokemon_species_artwork_admin_insert on storage.objects
  for insert
  with check (bucket_id = 'pokemon-species-artwork' and (select public.is_admin()));

create policy pokemon_species_artwork_admin_delete on storage.objects
  for delete
  using (bucket_id = 'pokemon-species-artwork' and (select public.is_admin()));

-- Resultado esperado
-- Tabela pokemon_species_artwork vazia (0 linhas), RLS ligada, sem GRANT para
-- anon/authenticated; 3 funções admin + get_pokedex_national_species com artwork_path
-- (1.025 linhas, todas com artwork_path NULL até o Lote B); bucket
-- pokemon-species-artwork público com limite 1 MB e só PNG/WebP; 2 policies de escrita
-- admin. Nenhuma linha existente alterada.
--
-- Como validar: executar 6842_validate_pokemon_species_artwork_foundation.sql → "6842 PASS".
