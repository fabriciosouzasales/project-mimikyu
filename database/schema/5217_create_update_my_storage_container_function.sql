/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5217 - update_my_storage_container(): renomear e definir o
              tipo de um local — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024214; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Contrato:
  update_my_storage_container(p_storage_container_id uuid,
                              p_name                 text,
                              p_kind_code            text)
  → storage_container_id, name, kind_code, updated_at, changed

  Substituição completa dos atributos descritivos: p_name obrigatório;
  p_kind_code NULL (ou vazio) = "sem tipo".

  1. 28000 not_authenticated; 22023 INVALID_REQUEST (id nulo);
     22023 INVALID_NAME; 22023 INVALID_KIND (inexistente ou inativo,
     exceto se for o tipo que o local já tem).
  2. Trava o local do Inventory do chamador (FOR UPDATE).
     Inexistente ou de outro usuário → P0002 STORAGE_NOT_FOUND
     (indistinguíveis — não enumera).
  3. Sem mudança → nada é escrito (updated_at preservado), changed = false.
     Com mudança → UPDATE de name/kind_code (trigger 5021 atualiza
     updated_at), changed = true.

  Renomear não move cartas, não altera coleções nem o local padrão de
  nenhuma coleção (C-58/C-59). "Local padrão" (nome provisório do local
  criado pelo CT-01, NS-13/N25) é renomeável como qualquer outro.
  Repetir a mesma chamada é seguro (idempotente por estado).

Segurança: SECURITY DEFINER, VOLATILE, search_path '', objetos
qualificados; EXECUTE só authenticated.
Recuperação: drop function if exists public.update_my_storage_container(uuid, text, text);
Como validar: 5847, seção 4.
================================================================
*/

begin;

create or replace function public.update_my_storage_container(
  p_storage_container_id uuid,
  p_name                 text,
  p_kind_code            text
)
returns table (
  storage_container_id uuid,
  name                 text,
  kind_code            text,
  updated_at           timestamptz,
  changed              boolean
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
  v_cur_name  text;
  v_cur_kind  text;
  v_changed   boolean := false;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_storage_container_id is null then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  if v_name is null or v_name = '' or char_length(v_name) > 60 then
    raise exception 'INVALID_NAME' using errcode = '22023';
  end if;

  select sc.name, sc.kind_code into v_cur_name, v_cur_kind
  from public.storage_container sc
  join public.inventory i on i.id = sc.inventory_id
  where sc.id = p_storage_container_id
    and i.owner_user_id = v_user
  for update of sc;

  if not found then
    raise exception 'STORAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_kind is not null
     and v_kind is distinct from v_cur_kind
     and not exists (
       select 1 from public.storage_container_kind k
       where k.code = v_kind and k.is_active
     ) then
    raise exception 'INVALID_KIND' using errcode = '22023';
  end if;

  if v_name is distinct from v_cur_name or v_kind is distinct from v_cur_kind then
    update public.storage_container sc
       set name = v_name,
           kind_code = v_kind
     where sc.id = p_storage_container_id;
    v_changed := true;
  end if;

  return query
  select sc.id, sc.name, sc.kind_code, sc.updated_at, v_changed
  from public.storage_container sc
  where sc.id = p_storage_container_id;
end;
$$;

revoke all on function public.update_my_storage_container(uuid, text, text) from public;
revoke all on function public.update_my_storage_container(uuid, text, text) from anon;
grant execute on function public.update_my_storage_container(uuid, text, text) to authenticated;

commit;
