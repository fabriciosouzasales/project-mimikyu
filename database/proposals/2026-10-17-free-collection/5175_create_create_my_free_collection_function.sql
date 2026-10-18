/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5175 - create_my_free_collection(): CT-01 estendido —
              Coleção livre + local numa única transação idempotente
              (COLLECTIONS-FUNCTIONAL-RECOVERY-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (autorização
              de Fabrício) — ledger 20261017222919; 5832 v1.1 25/25 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Autoridade: North Star v1.6 — NS-18 (taxonomia de criação), Fluxo 1.2/1.3
("Coleção livre" → nenhuma configuração além do nome), §2.6 CT-01 itens
1–7 (requisito 8: a extensão para coleção SEM referência é contrato
aditivo), NS-13, NS-15 (regra D-A); C-02, C-20 (curadoria aberta, sem
progresso), C-26, C-36, C-57.

Por que um contrato novo (e não uma alteração):
  - 5167 exige Card Set (p_card_set_id NOT NULL por regra) e chama
    create_reference_based_card_set_collection (5065/5069). Alterá-la
    mudaria um contrato LIVE e validado (5830 35/35) — vedado por CT-01
    item 4 e por NS-07.
  - create_collection (5034/5068) já cria a coleção de curadoria aberta
    (mode = OPEN_CURATION, completion_policy = NONE), mas exige um local
    já existente e não é idempotente: chamada sozinha não cumpre CT-01
    itens 1 e 2. Esta função apenas a orquestra numa transação, como 5167
    faz com 5065.

Contrato:
  create_my_free_collection(
    p_idempotency_key      uuid,   -- gerada pelo cliente por envio do formulário
    p_name                 text,
    p_storage_container_id uuid default null)
  RETURNS TABLE(collection_id, storage_container_id,
                storage_container_created, replayed)

Comportamento (espelho de 5167; só a criação da coleção muda):
  1. Serializa por usuário com a MESMA chave de advisory lock de 5167
     ('create_my_card_set_collection:' || auth.uid()). As duas portas de
     criação decidem o local (D-A) em fila única: uma criação de Set e uma
     Coleção livre simultâneas nunca criam dois "Local padrão".
  2. Idempotência na mesma tabela de 5166 (sem coluna nova). O hash do
     pedido começa com o marcador 'FREE', que nunca coincide com o hash de
     5167 (lá o primeiro campo é um uuid de Card Set). Mesma chave usada
     antes em qualquer das duas portas com outro pedido →
     IDEMPOTENCY_KEY_REUSED; mesmo pedido → mesmo resultado (replayed).
  3. Local (D-A), idêntico a 5167:
       - p_storage_container_id informado → precisa ser do Inventory do
         usuário (STORAGE_CONTAINER_INVALID, sem revelar se existe);
       - não informado e o usuário não tem nenhum local → cria
         "Local padrão" via create_storage_container (5022);
       - não informado e o usuário já tem local → STORAGE_CONTAINER_REQUIRED.
  4. Game: o produto é Pokémon TCG (ADR-011); a Coleção livre não pede
     escolha de jogo ao colecionador. O Game é resolvido pelo código
     estável 'POKEMON' (mesmo critério de 5090 e 2247). Ausente →
     GAME_NOT_FOUND (falha de configuração, nada é gravado).
  5. Coleção via create_collection (5034/5068), sem alteração: dono por
     auth.uid(), mode OPEN_CURATION (default da tabela), completion_policy
     NONE — sem referência e sem progresso (C-20).
  6. Grava 5166 e devolve.
  Qualquer erro desfaz tudo (função única = transação única): nunca fica
  local órfão nem coleção pela metade.

  Nenhuma carta é tocada (NS-13, C-26): sem leitura ou escrita em
  physical_card nem em collection_allocation.

Erros:
  28000  not_authenticated
  22023  INVALID_REQUEST (chave ou nome ausentes / nome vazio)
  22023  STORAGE_CONTAINER_INVALID (não é do usuário ou não existe)
  55000  STORAGE_CONTAINER_REQUIRED (usuário já tem local; escolha exigida)
  22023  IDEMPOTENCY_KEY_REUSED (mesma chave, pedido diferente)
  P0001  GAME_NOT_FOUND (configuração do catálogo)

Contratos reutilizados sem alteração: 5022, 5034/5068, 5166 (tabela).
Contrato vizinho preservado: 5167 (nenhuma linha alterada).
Segurança: SECURITY DEFINER, VOLATILE, search_path '', dono por
auth.uid(), EXECUTE só authenticated (sem PUBLIC, anon ou service_role
explícito).

Como validar: Query 5832.
================================================================
*/

begin;

create or replace function public.create_my_free_collection(
  p_idempotency_key      uuid,
  p_name                 text,
  p_storage_container_id uuid default null
)
returns table (
  collection_id             uuid,
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

  if p_idempotency_key is null or v_name is null or v_name = '' then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  -- 1. Serialização por usuário, compartilhada com 5167 (mesma chave).
  perform pg_advisory_xact_lock(hashtextextended('create_my_card_set_collection:' || v_user::text, 0));

  v_hash := md5(concat_ws('|', 'FREE', v_name, coalesce(p_storage_container_id::text, '-')));

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
    select v_prev.collection_id, v_prev.storage_container_id,
           v_prev.storage_container_created, true;
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    raise exception 'inventory not found for current user' using errcode = '22023';
  end if;

  select g.id into v_game
  from public.game g
  where g.code = 'POKEMON';

  if v_game is null then
    raise exception 'GAME_NOT_FOUND';
  end if;

  -- 3. Local (D-A), idêntico a 5167.
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

  -- 4. Coleção de curadoria aberta pelas regras de 5034/5068
  --    (OPEN_CURATION, completion_policy NONE, sem referência).
  select c.id into v_collection
  from public.create_collection(v_game, v_name, null, v_storage) c;

  -- 5. Registro de idempotência (mesma transação, tabela de 5166).
  insert into public.collection_creation_request
    (owner_user_id, idempotency_key, request_hash, collection_id, storage_container_id, storage_container_created)
  values
    (v_user, p_idempotency_key, v_hash, v_collection, v_storage, v_created);

  return query
  select v_collection, v_storage, v_created, false;
end;
$$;

comment on function public.create_my_free_collection(uuid, text, uuid) is
  'CT-01 estendido (Query 5175): cria Coleção livre (curadoria aberta, sem referência, sem progresso) e, se o usuário não tem nenhum local, o "Local padrão" — numa transação, idempotente por chave do cliente (tabela 5166, fila compartilhada com 5167). Com locais existentes, o local é escolha explícita (55000 STORAGE_CONTAINER_REQUIRED). Não toca cartas.';

revoke all on function public.create_my_free_collection(uuid, text, uuid) from public;
revoke all on function public.create_my_free_collection(uuid, text, uuid) from anon;
grant execute on function public.create_my_free_collection(uuid, text, uuid) to authenticated;

commit;
