/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5202 - create_my_pokedex_collection(): cria uma coleção
              "Completar a Pokédex" com as gerações escolhidas —
              idempotente, com "Local padrão" quando necessário
Versão......: 1.0
Status......: PROPOSTA — não executada no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-01-IMPLEMENTATION-01)

Contrato (irmão da 5167 — CT-01):
  create_my_pokedex_collection(p_idempotency_key uuid, p_name text,
                               p_generation_codes text[],
                               p_storage_container_id uuid default null)
  → collection_id, generation_codes, storage_container_id,
    storage_container_created, replayed

  - Universo: Pokédex Nacional (code 'NATIONAL'). Jogo: POKEMON.
  - Escopo SEMPRE explícito (GENERATION_FILTERED com a lista recebida).
    Nunca grava FULL_REFERENCE: gerações catalogadas depois não entram
    sozinhas nesta coleção (C-02; decisão do proprietário 2026-10-19).
    "Todas por padrão" = a interface envia todas as linhas de 5201.
  - Cada código precisa ser de geração ATIVA e CATALOGADA (≥ 1 posição na
    Pokédex Nacional); repetidos são ignorados; 1..64 códigos.
  - Local (D-A, igual à 5167): informado → precisa ser do usuário; sem
    local e sem nenhum local no acervo → cria "Local padrão" na mesma
    transação; sem local e com locais existentes → 55000
    STORAGE_CONTAINER_REQUIRED.
  - Idempotência: chave do cliente em collection_creation_request (5166,
    sem alteração). Mesma chave + mesmo pedido → mesma coleção
    (replayed = true), nunca duas; mesma chave + pedido diferente → 22023
    IDEMPOTENCY_KEY_REUSED. Hash prefixado com 'POKEDEX' (não colide com
    pedidos de Set/Livre).
  - Escrita delegada à 5098 (create_reference_based_pokedex_collection),
    que segue com todas as validações estruturais. Não toca cartas.

Erros: 28000 not_authenticated; 22023 INVALID_REQUEST /
GENERATION_NOT_AVAILABLE / IDEMPOTENCY_KEY_REUSED / STORAGE_CONTAINER_INVALID;
55000 STORAGE_CONTAINER_REQUIRED / POKEDEX_NOT_AVAILABLE.
Segurança: SECURITY DEFINER, VOLATILE, search_path '', serialização por
usuário (advisory lock), EXECUTE só authenticated. Depende da 5098 ser
executável pelo dono das funções (postgres) — continua após a 5205.
Como validar: 5844 v1.0.
Recuperação: drop function if exists public.create_my_pokedex_collection(uuid, text, text[], uuid);
================================================================
*/

begin;

create or replace function public.create_my_pokedex_collection(
  p_idempotency_key      uuid,
  p_name                 text,
  p_generation_codes     text[],
  p_storage_container_id uuid default null
)
returns table (
  collection_id             uuid,
  generation_codes          text[],
  storage_container_id      uuid,
  storage_container_created boolean,
  replayed                  boolean
)
language plpgsql
security definer
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_default_name constant text := 'Local padrão';
  v_user        uuid := auth.uid();
  v_name        text := btrim(p_name);
  v_codes       text[];
  v_gen_ids     uuid[];
  v_out_codes   text[];
  v_inventory   uuid;
  v_game        uuid;
  v_dex         uuid;
  v_hash        text;
  v_prev        public.collection_creation_request%rowtype;
  v_storage     uuid;
  v_created     boolean := false;
  v_collection  uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_idempotency_key is null or v_name is null or v_name = ''
     or p_generation_codes is null
     or coalesce(cardinality(p_generation_codes), 0) = 0
     or cardinality(p_generation_codes) > 64
     or exists (select 1 from unnest(p_generation_codes) x where x is null or btrim(x) = '') then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  select array_agg(distinct btrim(x) order by btrim(x)) into v_codes
  from unnest(p_generation_codes) x;

  -- 1. Serialização por usuário (inclui o duplo envio da mesma chave).
  perform pg_advisory_xact_lock(hashtextextended('create_my_pokedex_collection:' || v_user::text, 0));

  v_hash := md5(concat_ws('|', 'POKEDEX', v_name, array_to_string(v_codes, ','),
                          coalesce(p_storage_container_id::text, '-')));

  -- 2. Replay.
  select r.* into v_prev
  from public.collection_creation_request r
  where r.owner_user_id = v_user
    and r.idempotency_key = p_idempotency_key;

  if found then
    if v_prev.request_hash <> v_hash then
      raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '22023';
    end if;
    return query
    select v_prev.collection_id,
           (select array_agg(g.code::text order by g.ordinal_number)
              from public.pokemon_generation g where g.code = any(v_codes)),
           v_prev.storage_container_id, v_prev.storage_container_created, true;
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    raise exception 'inventory not found for current user' using errcode = '22023';
  end if;

  select g.id into v_game from public.game g where g.code = 'POKEMON';
  select d.id into v_dex from public.pokedex d where d.code = 'NATIONAL' and d.is_active;

  if v_game is null or v_dex is null then
    raise exception 'POKEDEX_NOT_AVAILABLE' using errcode = '55000';
  end if;

  -- 3. Gerações: ativas e catalogadas na Pokédex Nacional.
  select array_agg(g.id order by g.ordinal_number), array_agg(g.code::text order by g.ordinal_number)
    into v_gen_ids, v_out_codes
  from public.pokemon_generation g
  where g.code = any(v_codes)
    and g.is_active
    and exists (
      select 1
      from public.pokemon_species s
      join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex
      where s.generation_id = g.id
    );

  if coalesce(cardinality(v_gen_ids), 0) <> cardinality(v_codes) then
    raise exception 'GENERATION_NOT_AVAILABLE' using errcode = '22023';
  end if;

  -- 4. Local (D-A), igual à 5167.
  if p_storage_container_id is not null then
    if not exists (
      select 1 from public.storage_container sc
      where sc.id = p_storage_container_id
        and sc.inventory_id = v_inventory
    ) then
      raise exception 'STORAGE_CONTAINER_INVALID' using errcode = '22023';
    end if;
    v_storage := p_storage_container_id;
  elsif exists (
    select 1 from public.storage_container sc
    where sc.inventory_id = v_inventory
  ) then
    raise exception 'STORAGE_CONTAINER_REQUIRED' using errcode = '55000';
  else
    select s.id into v_storage
    from public.create_storage_container(c_default_name) s;
    v_created := true;
  end if;

  -- 5. Coleção pelas regras da 5098, sempre com escopo explícito.
  select c.id into v_collection
  from public.create_reference_based_pokedex_collection(
         v_game, v_name, null, v_storage, v_dex, 'GENERATION_FILTERED', v_gen_ids) c;

  -- 6. Registro de idempotência (mesma transação).
  insert into public.collection_creation_request
    (owner_user_id, idempotency_key, request_hash, collection_id, storage_container_id, storage_container_created)
  values
    (v_user, p_idempotency_key, v_hash, v_collection, v_storage, v_created);

  return query
  select v_collection, v_out_codes, v_storage, v_created, false;
end;
$$;

comment on function public.create_my_pokedex_collection(uuid, text, text[], uuid) is
  'Pokédex (Query 5202, CT-01): cria coleção "Completar a Pokédex" (Pokédex Nacional) com a lista EXPLÍCITA de gerações catalogadas escolhidas — nunca FULL_REFERENCE, então gerações futuras não entram sozinhas. Local padrão quando o usuário não tem nenhum; idempotente por chave do cliente. Não toca cartas.';

revoke all on function public.create_my_pokedex_collection(uuid, text, text[], uuid) from public, anon;
grant execute on function public.create_my_pokedex_collection(uuid, text, text[], uuid) to authenticated;

commit;
