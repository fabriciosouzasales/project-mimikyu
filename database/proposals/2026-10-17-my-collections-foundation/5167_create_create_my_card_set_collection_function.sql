/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5167 - create_my_card_set_collection(): CT-01 —
              coleção de Set + local numa única transação idempotente
              (MY-COLLECTIONS-FOUNDATION-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (autorização
              condicionada de Fabrício) — ledger 20261017152413; 5830 v1.1 35/35 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Autoridade: North Star §2.6 (NS-06, NS-07, NS-13, CT-01 itens 1–7);
C-11, C-26, C-36, C-55, C-57, C-59. Decisões de Fabrício (2026-10-17):
  D-A (regra do local, R4):
    - usuário SEM nenhum local → cria automaticamente "Local padrão";
    - usuário com UM OU MAIS locais → o local é escolha explícita do
      usuário (p_storage_container_id obrigatório); nunca escolha
      automática, nem quando só existe um.
  D-B: idempotência em tabela própria (5166).

Contrato:
  create_my_card_set_collection(
    p_idempotency_key      uuid,   -- gerada pelo cliente por envio do formulário
    p_card_set_id          uuid,
    p_name                 text,
    p_storage_container_id uuid default null)
  RETURNS TABLE(collection_id, card_set_id, storage_container_id,
                storage_container_created, replayed)

Comportamento:
  1. Serializa por usuário (advisory lock de transação): duplo envio e
     criações concorrentes do mesmo usuário nunca decidem o local em
     paralelo.
  2. Chave já usada com o mesmo pedido → devolve o resultado gravado
     (replayed = true), sem criar nada. Mesma chave com pedido diferente
     → IDEMPOTENCY_KEY_REUSED.
  3. Local:
       - p_storage_container_id informado → precisa ser do Inventory do
         usuário (STORAGE_CONTAINER_INVALID, sem revelar se existe);
       - não informado e o usuário não tem nenhum local → cria
         "Local padrão" via create_storage_container (5022);
       - não informado e o usuário já tem local → STORAGE_CONTAINER_REQUIRED.
  4. Coleção via create_reference_based_card_set_collection (5065/5069),
     Game derivado do Set. Todas as regras de 5065 valem.
  5. Grava 5166 e devolve.
  Qualquer erro desfaz tudo (função única = transação única): nunca
  fica local órfão nem coleção pela metade.

  Nenhuma carta é atribuída a local algum (NS-13, C-26): a função não
  toca physical_card. O local é só o Default Storage Container (C-36),
  destino sugerido e alterável (5036).

Erros:
  28000  not_authenticated
  22023  INVALID_REQUEST (chave, Set ou nome ausentes / nome vazio)
  22023  CARD_SET_NOT_FOUND
  22023  STORAGE_CONTAINER_INVALID (não é do usuário ou não existe)
  55000  STORAGE_CONTAINER_REQUIRED (usuário já tem local; escolha exigida)
  22023  IDEMPOTENCY_KEY_REUSED (mesma chave, pedido diferente)

Contratos reutilizados sem alteração: 5022, 5065/5069.
Segurança: SECURITY DEFINER, VOLATILE, search_path '', dono por
auth.uid(), EXECUTE só authenticated.

Como validar: Query 5830.
================================================================
*/

begin;

create or replace function public.create_my_card_set_collection(
  p_idempotency_key      uuid,
  p_card_set_id          uuid,
  p_name                 text,
  p_storage_container_id uuid default null
)
returns table (
  collection_id             uuid,
  card_set_id               uuid,
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
  v_inventory   uuid;
  v_game        uuid;
  v_name        text := btrim(p_name);
  v_hash        text;
  v_prev        public.collection_creation_request%rowtype;
  v_storage     uuid;
  v_created     boolean := false;
  v_collection  uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_idempotency_key is null or p_card_set_id is null or v_name is null or v_name = '' then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  -- 1. Serialização por usuário (inclui o duplo envio da mesma chave).
  perform pg_advisory_xact_lock(hashtextextended('create_my_card_set_collection:' || v_user::text, 0));

  v_hash := md5(concat_ws('|', p_card_set_id::text, v_name, coalesce(p_storage_container_id::text, '-')));

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
    select v_prev.collection_id, p_card_set_id, v_prev.storage_container_id,
           v_prev.storage_container_created, true;
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    raise exception 'inventory not found for current user' using errcode = '22023';
  end if;

  select e.game_id into v_game
  from public.card_set cs
  join public.expansion e on e.id = cs.expansion_id
  where cs.id = p_card_set_id;

  if v_game is null then
    raise exception 'CARD_SET_NOT_FOUND' using errcode = '22023';
  end if;

  -- 3. Local (D-A).
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

  -- 4. Coleção pelas regras de 5065/5069.
  select c.id into v_collection
  from public.create_reference_based_card_set_collection(v_game, v_name, null, v_storage, p_card_set_id) c;

  -- 5. Registro de idempotência (mesma transação).
  insert into public.collection_creation_request
    (owner_user_id, idempotency_key, request_hash, collection_id, storage_container_id, storage_container_created)
  values
    (v_user, p_idempotency_key, v_hash, v_collection, v_storage, v_created);

  return query
  select v_collection, p_card_set_id, v_storage, v_created, false;
end;
$$;

comment on function public.create_my_card_set_collection(uuid, uuid, text, uuid) is
  'CT-01 (Query 5167): cria coleção de Set e, se o usuário não tem nenhum local, o "Local padrão" — numa transação, idempotente por chave do cliente. Com locais existentes, o local é escolha explícita (55000 STORAGE_CONTAINER_REQUIRED). Não toca cartas.';

revoke all on function public.create_my_card_set_collection(uuid, uuid, text, uuid) from public;
revoke all on function public.create_my_card_set_collection(uuid, uuid, text, uuid) from anon;
grant execute on function public.create_my_card_set_collection(uuid, uuid, text, uuid) to authenticated;

commit;
