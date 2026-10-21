/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5216 - create_my_storage_container(): criar local físico,
              idempotente por chave do cliente — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024206; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Por que existe: create_storage_container (5022) cria um local, mas não é
idempotente (retry após timeout duplica) e não conhece tipo. Esta função
REUTILIZA a 5022 para a inserção (mesma regra de ownership por Inventory,
C-57) e acrescenta só o que falta: chave de idempotência (5215), tipo
opcional (5212/5213) e erros com código.

Contrato:
  create_my_storage_container(p_idempotency_key uuid,
                              p_name            text,
                              p_kind_code       text default null)
  → storage_container_id, name, kind_code, replayed

  1. 28000 not_authenticated sem identidade.
  2. 22023 INVALID_REQUEST: chave nula.
     22023 INVALID_NAME: nome vazio (após btrim) ou > 60 caracteres.
     22023 INVALID_KIND: tipo informado inexistente ou inativo.
  3. Serialização por usuário (advisory lock de transação, chave própria
     'create_my_storage_container:<user>').
  4. Replay (mesma chave): mesmo payload → devolve o local já criado com
     replayed = true, sem nova escrita. Se esse local foi excluído
     depois (5218), devolve storage_container_id NULL (e name/kind_code
     NULL) com replayed = true — nunca recria. Payload diferente →
     22023 IDEMPOTENCY_KEY_REUSED.
  5. 22023 INVENTORY_NOT_FOUND se o usuário não tem acervo.
  6. Insere via public.create_storage_container (5022); grava kind_code
     quando informado; grava o pedido (5215) na mesma transação.

  Não atribui nenhuma carta ao local (NS-13/NS-15). Não altera coleções.
  Nome não precisa ser único (nenhuma regra canônica exige).

Segurança: SECURITY DEFINER, VOLATILE, search_path '', objetos
qualificados; EXECUTE só authenticated.
Recuperação: drop function if exists public.create_my_storage_container(uuid, text, text);
Como validar: 5847, seção 3.
================================================================
*/

begin;

create or replace function public.create_my_storage_container(
  p_idempotency_key uuid,
  p_name            text,
  p_kind_code       text default null
)
returns table (
  storage_container_id uuid,
  name                 text,
  kind_code            text,
  replayed             boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_name      text := btrim(p_name);
  v_kind      text := nullif(btrim(p_kind_code), '');
  v_hash      text;
  v_prev      public.storage_container_creation_request%rowtype;
  v_inventory uuid;
  v_id        uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_idempotency_key is null then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  if v_name is null or v_name = '' or char_length(v_name) > 60 then
    raise exception 'INVALID_NAME' using errcode = '22023';
  end if;

  if v_kind is not null and not exists (
    select 1 from public.storage_container_kind k
    where k.code = v_kind and k.is_active
  ) then
    raise exception 'INVALID_KIND' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('create_my_storage_container:' || v_user::text, 0));

  v_hash := md5(concat_ws('|', 'STORAGE', v_name, coalesce(v_kind, '-')));

  select r.* into v_prev
  from public.storage_container_creation_request r
  where r.owner_user_id = v_user
    and r.idempotency_key = p_idempotency_key;

  if found then
    if v_prev.request_hash <> v_hash then
      raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '22023';
    end if;
    return query
    select v_prev.storage_container_id, sc.name, sc.kind_code, true
    from (select 1) one
    left join public.storage_container sc on sc.id = v_prev.storage_container_id;
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    raise exception 'INVENTORY_NOT_FOUND' using errcode = '22023';
  end if;

  -- Reutiliza a 5022 (ownership pelo Inventory do chamador, C-57).
  select s.id into v_id
  from public.create_storage_container(v_name) s;

  if v_kind is not null then
    update public.storage_container sc
       set kind_code = v_kind
     where sc.id = v_id;
  end if;

  insert into public.storage_container_creation_request
    (owner_user_id, idempotency_key, request_hash, storage_container_id)
  values
    (v_user, p_idempotency_key, v_hash, v_id);

  return query
  select sc.id, sc.name, sc.kind_code, false
  from public.storage_container sc
  where sc.id = v_id;
end;
$$;

revoke all on function public.create_my_storage_container(uuid, text, text) from public;
revoke all on function public.create_my_storage_container(uuid, text, text) from anon;
grant execute on function public.create_my_storage_container(uuid, text, text) to authenticated;

commit;
