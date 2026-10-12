-- Query 6133 | Pokédex P3a — fundação do enriquecimento das espécies
--
-- Status: CONFIRMADO EXECUTADO em 2026-10-12 via Supabase MCP (apply_migration
-- "6133_create_pokemon_species_enrichment_foundation", versão 20261012191446), versão de
-- execução v1.0 — conteúdo idêntico à proposta ensaiada (sha256 do arquivo de proposta
-- edbb9336…3517cd; aplicada sem as linhas só de comentário). Validação: ensaio 6133+6844
-- com ROLLBACK = PASS; após aplicar, 6844 v1.1 = "6844 PASS" (rollback integral dos
-- fixtures; 0 linhas de dados remanescentes). Postcheck: 5 tabelas, 4 funções, 18 tipos;
-- espécies (1.025), imagens (1.025 / 2.050 objetos), card_asset e contrato de
-- get_pokedex_national_species idênticos ao baseline.
--
-- Objetivo
-- Preparar, sem importar nenhum dado, a estrutura que recebe as informações de referência
-- autorizadas pela emenda do AP-017 (02-architecture-principles.md v1.10 / ADR-011 v1.4):
--   1. pokemon_type             — vocabulário dos 18 tipos elementais (código canônico +
--                                 rótulos por idioma), semeado aqui.
--   2. pokemon_form             — Pokémon Form/Variety (LDM-175): nesta etapa SÓ a forma
--                                 padrão de cada espécie (altura, peso, referência oficial).
--   3. pokemon_form_type        — tipos da forma, com a ordem oficial (slot 1 = primário).
--   4. pokemon_species_profile  — indicadores da espécie (lendário/mítico/bebê), vínculo com a
--                                 forma padrão, proveniência, hash de conteúdo, status de
--                                 importação e direitos dos textos.
--   5. pokemon_species_text     — classificação (GENUS) e descrição (FLAVOR) por idioma, com
--                                 origem (SOURCE = PokéAPI; MMKYU_EDITORIAL = tradução futura),
--                                 versão de origem e direitos.
--   6. Funções admin (SECURITY DEFINER + is_admin()):
--        admin_record_pokemon_species_profile(n, payload)       — grava/atualiza; UNCHANGED
--                                                                  quando o conteúdo é igual
--        admin_record_pokemon_species_profile_failure(n, ...)   — falha sem apagar dado válido
--        admin_list_pokemon_species_profile_status(...)         — cobertura e retomada
--   7. get_pokedex_species_detail(n, idioma) — leitura para usuários autenticados (página de
--      detalhes futura). get_pokedex_national_species NÃO é alterada.
--
-- Decisões de desenho
-- - Identidade por referência oficial, nunca por igualdade de ids: o source_species_id do
--   payload precisa ser o external_species_id já cadastrado (POKEAPI) para a espécie; o id e
--   o nome do Pokémon da forma padrão são gravados como vieram (o importador confere o
--   caminho espécie -> varieties[is_default] -> pokemon.species antes de enviar).
-- - pokemon_form: CHECK is_default = true nesta etapa (formas alternativas exigem decisão e
--   migration próprias) + índice único parcial "uma forma padrão por espécie". O vínculo
--   profile.default_form_id usa FK composta (form, espécie) — a forma padrão não pode
--   pertencer a outra espécie.
-- - Idioma dos textos: código BCP 47 em texto (mesmo formato de public.language), SEM FK para
--   public.language — aquela tabela governa idiomas de impressão de cartas; acoplar os
--   idiomas da Pokédex a ela poria opções novas no catálogo de cartas.
-- - Tipos: identidade = code (FIRE...), estável; rótulos em labels jsonb {"pt-BR","en"};
--   novos idiomas = nova chave, sem coluna nova. Rótulos pt-BR conforme a terminologia
--   oficial usada pela The Pokémon Company no Brasil (Pokémon GO / TCG pt-BR).
-- - Conteúdo idempotente: o banco calcula sha256 do payload sem retrieved_at. Mesmo hash e
--   status IMPORTED -> UNCHANGED, nenhuma escrita.
-- - Textos SOURCE da espécie são substituídos em bloco a cada gravação (o payload é a lista
--   completa); textos MMKYU_EDITORIAL nunca são tocados pela importação.
-- - Direitos: textos SOURCE = THIRD_PARTY_UNLICENSED (© Nintendo/Creatures/GAME FREAK/The
--   Pokémon Company, via PokéAPI) — disponibilidade não é autorização comercial.
-- - Todas as tabelas: RLS ligada, nenhuma policy, nenhum GRANT a anon/authenticated (mesmo
--   padrão de pokemon_species/pokemon_species_artwork). Leitura só pelas funções.
-- - Índices: só os exigidos por unicidade + ix_pokemon_form_type_type (filtro por tipo da
--   Pesquisa Avançada, próxima entrega declarada da P3).
--
-- Escopo: nenhuma alteração em pokemon_species, números nacionais, vínculos carta–espécie,
-- pokemon_species_artwork/bucket, get_pokedex_national_species, Pricing, Collections ou
-- inventário. Habilidades, estatísticas, golpes, evoluções e formas alternativas: fora.

-- ---------------------------------------------------------------------------------
-- 0. Gatilho comum de updated_at
-- ---------------------------------------------------------------------------------
create or replace function public.touch_pokedex_reference_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.touch_pokedex_reference_updated_at() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 1. Vocabulário de tipos
-- ---------------------------------------------------------------------------------
create table public.pokemon_type (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  pokeapi_name text not null,
  display_order integer not null,
  labels jsonb not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_pokemon_type_code unique (code),
  constraint uq_pokemon_type_pokeapi_name unique (pokeapi_name),
  constraint uq_pokemon_type_display_order unique (display_order),
  constraint ck_pokemon_type_code check (code ~ '^[A-Z][A-Z_]*$'),
  constraint ck_pokemon_type_pokeapi_name check (pokeapi_name ~ '^[a-z][a-z-]*$'),
  constraint ck_pokemon_type_display_order check (display_order > 0),
  constraint ck_pokemon_type_labels check (
    jsonb_typeof(labels) = 'object'
    and coalesce(btrim(labels ->> 'pt-BR'), '') <> ''
    and coalesce(btrim(labels ->> 'en'), '') <> ''
  )
);

comment on table public.pokemon_type is
  'Pokédex P3a (Query 6133): vocabulário dos tipos elementais da espécie (videogame) — código canônico, nome PokéAPI, ordem oficial e rótulos por idioma. Não confundir com o tipo de energia impresso na Card.';

-- Ordem = id oficial da PokéAPI (1..18).
insert into public.pokemon_type (code, pokeapi_name, display_order, labels) values
  ('NORMAL',   'normal',    1, '{"pt-BR":"Normal","en":"Normal"}'),
  ('FIGHTING', 'fighting',  2, '{"pt-BR":"Lutador","en":"Fighting"}'),
  ('FLYING',   'flying',    3, '{"pt-BR":"Voador","en":"Flying"}'),
  ('POISON',   'poison',    4, '{"pt-BR":"Venenoso","en":"Poison"}'),
  ('GROUND',   'ground',    5, '{"pt-BR":"Terrestre","en":"Ground"}'),
  ('ROCK',     'rock',      6, '{"pt-BR":"Pedra","en":"Rock"}'),
  ('BUG',      'bug',       7, '{"pt-BR":"Inseto","en":"Bug"}'),
  ('GHOST',    'ghost',     8, '{"pt-BR":"Fantasma","en":"Ghost"}'),
  ('STEEL',    'steel',     9, '{"pt-BR":"Aço","en":"Steel"}'),
  ('FIRE',     'fire',     10, '{"pt-BR":"Fogo","en":"Fire"}'),
  ('WATER',    'water',    11, '{"pt-BR":"Água","en":"Water"}'),
  ('GRASS',    'grass',    12, '{"pt-BR":"Planta","en":"Grass"}'),
  ('ELECTRIC', 'electric', 13, '{"pt-BR":"Elétrico","en":"Electric"}'),
  ('PSYCHIC',  'psychic',  14, '{"pt-BR":"Psíquico","en":"Psychic"}'),
  ('ICE',      'ice',      15, '{"pt-BR":"Gelo","en":"Ice"}'),
  ('DRAGON',   'dragon',   16, '{"pt-BR":"Dragão","en":"Dragon"}'),
  ('DARK',     'dark',     17, '{"pt-BR":"Sombrio","en":"Dark"}'),
  ('FAIRY',    'fairy',    18, '{"pt-BR":"Fada","en":"Fairy"}');

create trigger trg_pokemon_type_touch_updated_at
  before update on public.pokemon_type
  for each row execute function public.touch_pokedex_reference_updated_at();

alter table public.pokemon_type enable row level security;
revoke all on table public.pokemon_type from anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 2. Forma padrão (Pokémon Form/Variety — só a padrão nesta etapa)
-- ---------------------------------------------------------------------------------
create table public.pokemon_form (
  id uuid primary key default gen_random_uuid(),
  pokemon_species_id uuid not null references public.pokemon_species(id) on delete restrict,
  asset_source_id uuid not null references public.asset_source(id) on delete restrict,
  external_pokemon_id text not null,
  external_pokemon_name text not null,
  is_default boolean not null,
  height_dm integer not null,
  weight_hg integer not null,
  retrieved_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_pokemon_form_id_species unique (id, pokemon_species_id),
  constraint uq_pokemon_form_source_external unique (asset_source_id, external_pokemon_id),
  -- P3a: só a forma padrão. Formas alternativas exigem decisão e migration próprias.
  constraint ck_pokemon_form_default_only check (is_default),
  constraint ck_pokemon_form_external_id check (external_pokemon_id ~ '^[1-9][0-9]*$'),
  constraint ck_pokemon_form_external_name check (external_pokemon_name ~ '^[a-z0-9][a-z0-9-]*$'),
  -- Unidades nativas da PokéAPI: decímetros e hectogramas (exibição em m/kg na leitura).
  constraint ck_pokemon_form_height check (height_dm between 1 and 10000),
  constraint ck_pokemon_form_weight check (weight_hg between 1 and 100000)
);

create unique index uq_pokemon_form_one_default_per_species
  on public.pokemon_form (pokemon_species_id) where is_default;

comment on table public.pokemon_form is
  'Pokédex P3a (Query 6133): Pokémon Form/Variety (LDM-175). Nesta etapa só a forma padrão de cada espécie: referência oficial PokéAPI (pokemon id/nome), altura (dm) e peso (hg).';

create trigger trg_pokemon_form_touch_updated_at
  before update on public.pokemon_form
  for each row execute function public.touch_pokedex_reference_updated_at();

alter table public.pokemon_form enable row level security;
revoke all on table public.pokemon_form from anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 3. Tipos da forma (ordem oficial preservada pelo slot)
-- ---------------------------------------------------------------------------------
create table public.pokemon_form_type (
  pokemon_form_id uuid not null references public.pokemon_form(id) on delete cascade,
  slot smallint not null,
  pokemon_type_id uuid not null references public.pokemon_type(id) on delete restrict,
  created_at timestamptz not null default now(),

  constraint pk_pokemon_form_type primary key (pokemon_form_id, slot),
  constraint uq_pokemon_form_type_type unique (pokemon_form_id, pokemon_type_id),
  constraint ck_pokemon_form_type_slot check (slot in (1, 2))
);

-- Filtro por tipo (Pesquisa Avançada): tipo -> formas.
create index ix_pokemon_form_type_type on public.pokemon_form_type (pokemon_type_id, pokemon_form_id);

comment on table public.pokemon_form_type is
  'Pokédex P3a (Query 6133): tipos elementais da forma; slot 1 = primário, 2 = secundário. Slot 2 só com slot 1 (garantido pela função de gravação, única escritora).';

alter table public.pokemon_form_type enable row level security;
revoke all on table public.pokemon_form_type from anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 4. Perfil da espécie (indicadores + proveniência + status)
-- ---------------------------------------------------------------------------------
create table public.pokemon_species_profile (
  id uuid primary key default gen_random_uuid(),
  pokemon_species_id uuid not null references public.pokemon_species(id) on delete restrict,
  asset_source_id uuid not null references public.asset_source(id) on delete restrict,
  status text not null,
  default_form_id uuid,
  is_legendary boolean,
  is_mythical boolean,
  is_baby boolean,
  source_species_id text,
  source_pokemon_id text,
  source_url text,
  retrieved_at timestamptz,
  content_sha256 text,
  text_rights_status text not null default 'THIRD_PARTY_UNLICENSED',
  text_rights_note text not null default 'Textos da Pokédex (classificação e descrição) © Nintendo / Creatures / GAME FREAK / The Pokémon Company, obtidos via PokéAPI; a disponibilidade na fonte não concede autorização de uso comercial.',
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_error_code text,
  last_error_message text,
  imported_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_pokemon_species_profile_species unique (pokemon_species_id),
  constraint uq_pokemon_species_profile_form unique (default_form_id),
  constraint fk_pokemon_species_profile_default_form
    foreign key (default_form_id, pokemon_species_id)
    references public.pokemon_form (id, pokemon_species_id) on delete restrict,
  constraint ck_pokemon_species_profile_status check (status in ('IMPORTED', 'FAILED')),
  constraint ck_pokemon_species_profile_rights check (text_rights_status in ('THIRD_PARTY_UNLICENSED', 'LICENSED')),
  constraint ck_pokemon_species_profile_rights_note check (btrim(text_rights_note) <> ''),
  constraint ck_pokemon_species_profile_attempts check (attempt_count >= 0),
  constraint ck_pokemon_species_profile_error_code check (last_error_code is null or last_error_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint ck_pokemon_species_profile_source_ids check (
    (source_species_id is null or source_species_id ~ '^[1-9][0-9]*$')
    and (source_pokemon_id is null or source_pokemon_id ~ '^[1-9][0-9]*$')
  ),
  constraint ck_pokemon_species_profile_source_url check (source_url is null or source_url like 'https://%'),
  -- coalesce(..., false): numa CHECK, NULL passaria; aqui campo ausente reprova.
  constraint ck_pokemon_species_profile_imported_complete check (
    status <> 'IMPORTED' or coalesce((
      default_form_id is not null
      and is_legendary is not null and is_mythical is not null and is_baby is not null
      and source_species_id is not null and source_pokemon_id is not null
      and source_url is not null and retrieved_at is not null and imported_at is not null
      and content_sha256 ~ '^[0-9a-f]{64}$'
    ), false)
  ),
  constraint ck_pokemon_species_profile_failed_empty check (
    status <> 'FAILED' or (
      default_form_id is null and content_sha256 is null and imported_at is null
      and last_error_code is not null
    )
  )
);

comment on table public.pokemon_species_profile is
  'Pokédex P3a (Query 6133): perfil de referência da espécie — lendário/mítico/bebê, forma padrão, proveniência PokéAPI, hash de conteúdo, status de importação e direitos dos textos. Escrita só via funções admin.';

create trigger trg_pokemon_species_profile_touch_updated_at
  before update on public.pokemon_species_profile
  for each row execute function public.touch_pokedex_reference_updated_at();

alter table public.pokemon_species_profile enable row level security;
revoke all on table public.pokemon_species_profile from anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 5. Textos da espécie por idioma
-- ---------------------------------------------------------------------------------
create table public.pokemon_species_text (
  id uuid primary key default gen_random_uuid(),
  pokemon_species_id uuid not null references public.pokemon_species(id) on delete restrict,
  text_kind text not null,
  language_code text not null,
  origin text not null,
  asset_source_id uuid references public.asset_source(id) on delete restrict,
  source_version text,
  content text not null,
  rights_status text not null default 'THIRD_PARTY_UNLICENSED',
  retrieved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_pokemon_species_text unique (pokemon_species_id, text_kind, language_code, origin),
  constraint ck_pokemon_species_text_kind check (text_kind in ('GENUS', 'FLAVOR')),
  constraint ck_pokemon_species_text_language check (
    language_code ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$'
  ),
  constraint ck_pokemon_species_text_origin check (origin in ('SOURCE', 'MMKYU_EDITORIAL')),
  constraint ck_pokemon_species_text_content check (btrim(content) <> '' and length(content) <= 2000),
  constraint ck_pokemon_species_text_rights check (rights_status in ('THIRD_PARTY_UNLICENSED', 'LICENSED', 'MMKYU_EDITORIAL')),
  -- Texto da fonte: proveniência obrigatória; FLAVOR leva a versão do jogo de origem.
  constraint ck_pokemon_species_text_source_provenance check (
    origin <> 'SOURCE' or coalesce((asset_source_id is not null and retrieved_at is not null), false)
  ),
  constraint ck_pokemon_species_text_version check (
    (text_kind = 'GENUS' and source_version is null)
    or (text_kind = 'FLAVOR' and (
      origin <> 'SOURCE' or coalesce(source_version ~ '^[a-z0-9][a-z0-9-]*$', false)
    ))
  )
);

comment on table public.pokemon_species_text is
  'Pokédex P3a (Query 6133): classificação (GENUS) e descrição selecionada (FLAVOR) da espécie por idioma. origin SOURCE = texto oficial da fonte (PokéAPI, com versão de origem); MMKYU_EDITORIAL = tradução editorial futura, nunca apresentada como oficial.';

create trigger trg_pokemon_species_text_touch_updated_at
  before update on public.pokemon_species_text
  for each row execute function public.touch_pokedex_reference_updated_at();

alter table public.pokemon_species_text enable row level security;
revoke all on table public.pokemon_species_text from anon, authenticated;

-- ---------------------------------------------------------------------------------
-- 6. Gravação (admin) — idempotente por hash de conteúdo
--
-- Payload (montado pelo importador):
-- {
--   "source_species_id": "25", "source_pokemon_id": "25", "source_pokemon_name": "pikachu",
--   "source_url": "https://pokeapi.co/api/v2/pokemon-species/25/",
--   "retrieved_at": "2026-10-12T18:00:00Z",
--   "is_legendary": false, "is_mythical": false, "is_baby": false,
--   "height_dm": 4, "weight_hg": 60,
--   "types": ["ELECTRIC"],                       -- ordem = slot oficial
--   "texts": [
--     {"kind": "GENUS",  "language": "en", "content": "Mouse Pokémon"},
--     {"kind": "FLAVOR", "language": "en", "content": "...", "source_version": "shield"}
--   ]
-- }
-- ---------------------------------------------------------------------------------
create or replace function public.admin_record_pokemon_species_profile(
  p_national_dex_number integer,
  p_payload jsonb
)
returns jsonb
language plpgsql security definer volatile set search_path = ''
as $$
declare
  v_species_id uuid;
  v_source_id uuid;
  v_existing public.pokemon_species_profile%rowtype;
  v_found boolean;
  v_hash text;
  v_action text;
  v_retrieved timestamptz;
  v_types text[];
  v_type_count integer;
  v_text jsonb;
  v_text_count integer := 0;
  v_seen text[] := array[]::text[];
  v_key text;
  v_form_id uuid;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'PAYLOAD_INVALID: payload ausente' using errcode = '22023';
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

  -- Vínculo pela referência oficial já cadastrada (não por nome nem por número).
  if not exists (
    select 1 from public.pokemon_species_external_reference r
     where r.pokemon_species_id = v_species_id
       and r.asset_source_id = v_source_id
       and r.is_active
       and r.external_species_id = p_payload ->> 'source_species_id'
  ) then
    raise exception 'SOURCE_SPECIES_MISMATCH: espécie % não corresponde a source_species_id %',
      p_national_dex_number, coalesce(p_payload ->> 'source_species_id', '<null>') using errcode = 'P0001';
  end if;

  -- Escalares
  if coalesce(p_payload ->> 'source_pokemon_id', '') !~ '^[1-9][0-9]*$'
     or coalesce(p_payload ->> 'source_pokemon_name', '') !~ '^[a-z0-9][a-z0-9-]*$'
     or coalesce(p_payload ->> 'source_url', '') not like 'https://pokeapi.co/api/v2/pokemon-species/%'
     or coalesce(jsonb_typeof(p_payload -> 'is_legendary'), '') <> 'boolean'
     or coalesce(jsonb_typeof(p_payload -> 'is_mythical'), '') <> 'boolean'
     or coalesce(jsonb_typeof(p_payload -> 'is_baby'), '') <> 'boolean'
     or coalesce(p_payload ->> 'height_dm', '') !~ '^[1-9][0-9]{0,4}$'
     or coalesce(p_payload ->> 'weight_hg', '') !~ '^[1-9][0-9]{0,5}$'
     or coalesce(p_payload ->> 'retrieved_at', '') = '' then
    raise exception 'PAYLOAD_INVALID: campos escalares' using errcode = '22023';
  end if;

  v_retrieved := (p_payload ->> 'retrieved_at')::timestamptz;
  if v_retrieved > now() + interval '10 minutes' then
    raise exception 'PAYLOAD_INVALID: retrieved_at no futuro' using errcode = '22023';
  end if;

  -- Tipos: 1 ou 2 códigos distintos, todos do vocabulário ativo; a ordem é o slot.
  if coalesce(jsonb_typeof(p_payload -> 'types'), '') <> 'array'
     or jsonb_array_length(p_payload -> 'types') not between 1 and 2 then
    raise exception 'PAYLOAD_INVALID: types' using errcode = '22023';
  end if;
  select array_agg(t.code order by t.ord) into v_types
    from jsonb_array_elements_text(p_payload -> 'types') with ordinality as t(code, ord);
  if (select count(distinct x) from unnest(v_types) as x) <> cardinality(v_types) then
    raise exception 'PAYLOAD_INVALID: tipo repetido' using errcode = '22023';
  end if;
  select count(*) into v_type_count
    from public.pokemon_type pt where pt.code = any (v_types) and pt.is_active;
  if v_type_count <> cardinality(v_types) then
    raise exception 'TYPE_UNKNOWN: %', array_to_string(v_types, ',') using errcode = 'P0001';
  end if;

  -- Textos: 0..n, um por (kind, idioma).
  if coalesce(jsonb_typeof(p_payload -> 'texts'), '') <> 'array' then
    raise exception 'PAYLOAD_INVALID: texts' using errcode = '22023';
  end if;
  for v_text in select e from jsonb_array_elements(p_payload -> 'texts') as e loop
    if jsonb_typeof(v_text) <> 'object'
       or coalesce(v_text ->> 'kind', '') not in ('GENUS', 'FLAVOR')
       or coalesce(v_text ->> 'language', '') !~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$'
       or btrim(coalesce(v_text ->> 'content', '')) = ''
       or length(v_text ->> 'content') > 2000
       or (v_text ->> 'kind' = 'FLAVOR' and coalesce(v_text ->> 'source_version', '') !~ '^[a-z0-9][a-z0-9-]*$')
       or (v_text ->> 'kind' = 'GENUS' and v_text ? 'source_version') then
      raise exception 'PAYLOAD_INVALID: texto %', v_text_count + 1 using errcode = '22023';
    end if;
    v_key := (v_text ->> 'kind') || '|' || (v_text ->> 'language');
    if v_key = any (v_seen) then
      raise exception 'PAYLOAD_INVALID: texto repetido %', v_key using errcode = '22023';
    end if;
    v_seen := v_seen || v_key;
    v_text_count := v_text_count + 1;
  end loop;

  -- Hash do conteúdo (sem a data de coleta): base da idempotência.
  v_hash := encode(sha256(convert_to((p_payload - 'retrieved_at')::text, 'UTF8')), 'hex');

  -- Serializa gravações concorrentes da mesma espécie.
  perform pg_advisory_xact_lock(hashtext('pokemon_species_profile'), p_national_dex_number);

  select * into v_existing
    from public.pokemon_species_profile p
   where p.pokemon_species_id = v_species_id
   for update;
  v_found := found;

  if v_found and v_existing.status = 'IMPORTED' and v_existing.content_sha256 = v_hash then
    return jsonb_build_object('national_dex_number', p_national_dex_number, 'action', 'UNCHANGED');
  end if;

  v_action := case when not v_found then 'INSERTED'
                   when v_existing.status = 'IMPORTED' then 'UPDATED'
                   else 'RECOVERED' end;

  -- Forma padrão: uma por espécie; atualizada no lugar se a referência mudar.
  select f.id into v_form_id
    from public.pokemon_form f
   where f.pokemon_species_id = v_species_id and f.is_default;

  if v_form_id is null then
    insert into public.pokemon_form (
      pokemon_species_id, asset_source_id, external_pokemon_id, external_pokemon_name,
      is_default, height_dm, weight_hg, retrieved_at
    ) values (
      v_species_id, v_source_id, p_payload ->> 'source_pokemon_id', p_payload ->> 'source_pokemon_name',
      true, (p_payload ->> 'height_dm')::integer, (p_payload ->> 'weight_hg')::integer, v_retrieved
    )
    returning id into v_form_id;
  else
    update public.pokemon_form f set
      asset_source_id = v_source_id,
      external_pokemon_id = p_payload ->> 'source_pokemon_id',
      external_pokemon_name = p_payload ->> 'source_pokemon_name',
      height_dm = (p_payload ->> 'height_dm')::integer,
      weight_hg = (p_payload ->> 'weight_hg')::integer,
      retrieved_at = v_retrieved
    where f.id = v_form_id;
  end if;

  delete from public.pokemon_form_type ft where ft.pokemon_form_id = v_form_id;
  insert into public.pokemon_form_type (pokemon_form_id, slot, pokemon_type_id)
  select v_form_id, t.ord::smallint, pt.id
    from unnest(v_types) with ordinality as t(code, ord)
    join public.pokemon_type pt on pt.code = t.code;

  -- Textos da fonte: substituídos em bloco; editoriais preservados.
  delete from public.pokemon_species_text st
   where st.pokemon_species_id = v_species_id and st.origin = 'SOURCE';
  insert into public.pokemon_species_text (
    pokemon_species_id, text_kind, language_code, origin, asset_source_id,
    source_version, content, rights_status, retrieved_at
  )
  select v_species_id, e ->> 'kind', e ->> 'language', 'SOURCE', v_source_id,
         e ->> 'source_version', e ->> 'content', 'THIRD_PARTY_UNLICENSED', v_retrieved
    from jsonb_array_elements(p_payload -> 'texts') as e;

  insert into public.pokemon_species_profile as p (
    pokemon_species_id, asset_source_id, status, default_form_id,
    is_legendary, is_mythical, is_baby,
    source_species_id, source_pokemon_id, source_url, retrieved_at, content_sha256,
    attempt_count, last_attempt_at, last_error_code, last_error_message, imported_at
  ) values (
    v_species_id, v_source_id, 'IMPORTED', v_form_id,
    (p_payload ->> 'is_legendary')::boolean, (p_payload ->> 'is_mythical')::boolean, (p_payload ->> 'is_baby')::boolean,
    p_payload ->> 'source_species_id', p_payload ->> 'source_pokemon_id', p_payload ->> 'source_url', v_retrieved, v_hash,
    1, now(), null, null, now()
  )
  on conflict (pokemon_species_id) do update set
    asset_source_id = excluded.asset_source_id,
    status = 'IMPORTED',
    default_form_id = excluded.default_form_id,
    is_legendary = excluded.is_legendary,
    is_mythical = excluded.is_mythical,
    is_baby = excluded.is_baby,
    source_species_id = excluded.source_species_id,
    source_pokemon_id = excluded.source_pokemon_id,
    source_url = excluded.source_url,
    retrieved_at = excluded.retrieved_at,
    content_sha256 = excluded.content_sha256,
    attempt_count = p.attempt_count + 1,
    last_attempt_at = now(),
    last_error_code = null,
    last_error_message = null,
    imported_at = now();

  return jsonb_build_object(
    'national_dex_number', p_national_dex_number,
    'action', v_action,
    'types', cardinality(v_types),
    'texts', v_text_count
  );
end;
$$;

comment on function public.admin_record_pokemon_species_profile(integer, jsonb) is
  'Pokédex P3a (Query 6133): grava forma padrão, tipos, indicadores e textos de uma espécie (admin). Valida vínculo oficial e vocabulário; UNCHANGED quando o conteúdo (sha256 sem retrieved_at) é o mesmo.';

-- ---------------------------------------------------------------------------------
-- 7. Registro de falha (admin) — nunca apaga perfil válido
-- ---------------------------------------------------------------------------------
create or replace function public.admin_record_pokemon_species_profile_failure(
  p_national_dex_number integer,
  p_error_code text,
  p_error_message text
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

  perform pg_advisory_xact_lock(hashtext('pokemon_species_profile'), p_national_dex_number);

  insert into public.pokemon_species_profile as p (
    pokemon_species_id, asset_source_id, status,
    attempt_count, last_attempt_at, last_error_code, last_error_message
  ) values (
    v_species_id, v_source_id, 'FAILED',
    1, now(), p_error_code, v_message
  )
  on conflict (pokemon_species_id) do update set
    -- Perfil válido (IMPORTED) é preservado: só o diagnóstico é atualizado.
    attempt_count = p.attempt_count + 1,
    last_attempt_at = now(),
    last_error_code = excluded.last_error_code,
    last_error_message = excluded.last_error_message
  returning p.status into v_status;

  return jsonb_build_object(
    'national_dex_number', p_national_dex_number,
    'status', v_status,
    'profile_preserved', v_status = 'IMPORTED'
  );
end;
$$;

comment on function public.admin_record_pokemon_species_profile_failure(integer, text, text) is
  'Pokédex P3a (Query 6133): registra falha de importação do perfil (admin); perfil IMPORTED é preservado, só o diagnóstico muda.';

-- ---------------------------------------------------------------------------------
-- 8. Cobertura por espécie (admin) — PENDING = espécie ainda sem perfil
-- ---------------------------------------------------------------------------------
create or replace function public.admin_list_pokemon_species_profile_status(
  p_status text default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (
  national_dex_number integer,
  species_name text,
  profile_status text,
  attempt_count integer,
  last_attempt_at timestamptz,
  last_error_code text,
  last_error_message text,
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
  with profile_rows as (
    select
      s.national_dex_number,
      s.canonical_name::text as species_name,
      coalesce(p.status, 'PENDING') as profile_status,
      coalesce(p.attempt_count, 0) as attempt_count,
      p.last_attempt_at, p.last_error_code, p.last_error_message, p.imported_at
    from public.pokemon_species s
    left join public.pokemon_species_profile p on p.pokemon_species_id = s.id
    where s.is_active
  )
  select r.*, count(*) over () as total_count
    from profile_rows r
   where p_status is null or r.profile_status = p_status
   order by r.national_dex_number
   limit least(greatest(coalesce(p_limit, 200), 1), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

comment on function public.admin_list_pokemon_species_profile_status(text, integer, integer) is
  'Pokédex P3a (Query 6133): situação do perfil por espécie (PENDING/IMPORTED/FAILED) para importação, retomada e administração.';

revoke all on function public.admin_record_pokemon_species_profile(integer, jsonb) from public, anon;
revoke all on function public.admin_record_pokemon_species_profile_failure(integer, text, text) from public, anon;
revoke all on function public.admin_list_pokemon_species_profile_status(text, integer, integer) from public, anon;
grant execute on function public.admin_record_pokemon_species_profile(integer, jsonb) to authenticated;
grant execute on function public.admin_record_pokemon_species_profile_failure(integer, text, text) to authenticated;
grant execute on function public.admin_list_pokemon_species_profile_status(text, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------------
-- 9. Leitura para o colecionador — página de detalhes futura
--
-- Idioma efetivo dos textos: pede p_language (padrão pt-BR). Para cada texto vence, nesta
-- ordem: p_language oficial (SOURCE) > p_language editorial MMKYU > en oficial > en
-- editorial. O idioma efetivo e se o texto é oficial voltam junto. Rótulo de tipo:
-- labels->>p_language, senão labels->>'en'.
-- Sem linha quando a espécie não existe. profile_available = false enquanto não importado.
-- ---------------------------------------------------------------------------------
create or replace function public.get_pokedex_species_detail(
  p_national_dex_number integer,
  p_language text default 'pt-BR'
)
returns table (
  national_dex_number integer,
  species_name text,
  generation_code text,
  generation_ordinal integer,
  region_code text,
  region_name text,
  artwork_path text,
  profile_available boolean,
  primary_type_code text,
  primary_type_label text,
  secondary_type_code text,
  secondary_type_label text,
  height_m numeric,
  weight_kg numeric,
  genus text,
  genus_language text,
  genus_is_official boolean,
  description text,
  description_language text,
  description_is_official boolean,
  description_source_version text,
  is_legendary boolean,
  is_mythical boolean,
  is_baby boolean
)
language plpgsql security definer stable set search_path = ''
as $$
declare
  v_lang text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_lang := coalesce(nullif(btrim(p_language), ''), 'pt-BR');
  if v_lang !~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$' then
    raise exception 'INVALID_LANGUAGE: %', left(v_lang, 20) using errcode = '22023';
  end if;

  return query
  select
    s.national_dex_number,
    s.canonical_name::text,
    g.code::text,
    g.ordinal_number,
    r.code::text,
    r.canonical_name::text,
    case when w.status = 'IMPORTED' then w.display_storage_path end,
    coalesce(p.status = 'IMPORTED', false),
    t1.code,
    coalesce(t1.labels ->> v_lang, t1.labels ->> 'en'),
    t2.code,
    coalesce(t2.labels ->> v_lang, t2.labels ->> 'en'),
    case when p.status = 'IMPORTED' then round(f.height_dm / 10.0, 1) end,
    case when p.status = 'IMPORTED' then round(f.weight_hg / 10.0, 1) end,
    gn.content,
    gn.language_code,
    gn.origin = 'SOURCE',
    fl.content,
    fl.language_code,
    fl.origin = 'SOURCE',
    fl.source_version,
    case when p.status = 'IMPORTED' then p.is_legendary end,
    case when p.status = 'IMPORTED' then p.is_mythical end,
    case when p.status = 'IMPORTED' then p.is_baby end
  from public.pokemon_species s
  join public.pokemon_generation g on g.id = s.generation_id and g.is_active
  left join public.pokemon_region r on r.id = g.main_region_id and r.is_active
  left join public.pokemon_species_artwork w on w.pokemon_species_id = s.id
  left join public.pokemon_species_profile p on p.pokemon_species_id = s.id
  left join public.pokemon_form f on f.id = p.default_form_id and p.status = 'IMPORTED'
  left join public.pokemon_form_type ft1 on ft1.pokemon_form_id = f.id and ft1.slot = 1
  left join public.pokemon_type t1 on t1.id = ft1.pokemon_type_id
  left join public.pokemon_form_type ft2 on ft2.pokemon_form_id = f.id and ft2.slot = 2
  left join public.pokemon_type t2 on t2.id = ft2.pokemon_type_id
  left join lateral (
    select st.content, st.language_code, st.origin
      from public.pokemon_species_text st
     where st.pokemon_species_id = s.id and st.text_kind = 'GENUS'
       and st.language_code in (v_lang, 'en')
     order by (st.language_code = v_lang) desc, (st.origin = 'SOURCE') desc
     limit 1
  ) gn on true
  left join lateral (
    select st.content, st.language_code, st.origin, st.source_version
      from public.pokemon_species_text st
     where st.pokemon_species_id = s.id and st.text_kind = 'FLAVOR'
       and st.language_code in (v_lang, 'en')
     order by (st.language_code = v_lang) desc, (st.origin = 'SOURCE') desc
     limit 1
  ) fl on true
  where s.is_active and s.national_dex_number = p_national_dex_number;
end;
$$;

comment on function public.get_pokedex_species_detail(integer, text) is
  'Pokédex P3a (Query 6133): ficha pública de uma espécie para usuários autenticados — identificação, geração/região, imagem, tipos (código + rótulo no idioma), altura (m), peso (kg), classificação e descrição com idioma efetivo e indicação de texto oficial, lendário/mítico/bebê. Sem colunas administrativas.';

revoke all on function public.get_pokedex_species_detail(integer, text) from public;
revoke all on function public.get_pokedex_species_detail(integer, text) from anon;
grant execute on function public.get_pokedex_species_detail(integer, text) to authenticated;

-- Resultado esperado
-- 5 tabelas novas com RLS ligada e sem GRANT para anon/authenticated; pokemon_type com 18
-- linhas; pokemon_form/pokemon_form_type/pokemon_species_profile/pokemon_species_text vazias;
-- 3 funções admin (EXECUTE só authenticated + is_admin interno) e get_pokedex_species_detail
-- (só authenticated). Nenhuma linha existente alterada; get_pokedex_national_species intacta.
--
-- Como validar: executar 6844_validate_pokemon_species_enrichment_foundation.sql → "6844 PASS".
