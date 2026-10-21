/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5219 - get_my_storage_locations() e get_my_storage_summary():
              leitura de "Meus locais" — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024228; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Contratos:
  get_my_storage_locations()
  → storage_container_id, name, kind_code, kind_label, card_count,
    default_collection_count, can_delete, created_at, updated_at
    Um registro por local do acervo do chamador, ordenado por nome
    (sem distinção de maiúsculas), depois created_at e id.
    card_count: exemplares diretamente neste local (C-58).
    default_collection_count: coleções (ativas ou arquivadas) que usam o
    local como local padrão — preferência, não ordem de movimentação
    (NS-15). can_delete = card_count = 0 e default_collection_count = 0
    (mesma regra que 5218 aplica).
    kind_label vem de storage_container_kind (inclusive tipo inativo já
    usado, para nunca exibir código técnico).

  get_my_storage_summary()
  → total_cards, located_cards, unlocated_cards, location_count
    unlocated_cards = "Sem localização definida" (C-26/N25).

  Sem identidade → 28000. Sem acervo → nenhum local e contagens zero.

Desempenho: contagem por local via ix_physical_card_storage_container
(5023), proporcional às cartas localizadas, nunca às do acervo inteiro;
locais via ix_storage_container_inventory (5213); resumo via índices de
physical_card que começam por inventory_id. Nada é paginado no navegador:
a quantidade de locais por usuário é pequena por natureza; a quantidade
de cartas nunca é trafegada (só contagens).

Segurança: SECURITY DEFINER (filtro explícito pelo Inventory do
chamador, sem depender da RLS por linha), STABLE, search_path '';
EXECUTE só authenticated.
Recuperação: drop function if exists public.get_my_storage_locations();
             drop function if exists public.get_my_storage_summary();
Como validar: 5847, seção 5.
================================================================
*/

begin;

create or replace function public.get_my_storage_locations()
returns table (
  storage_container_id     uuid,
  name                     text,
  kind_code                text,
  kind_label               text,
  card_count               bigint,
  default_collection_count bigint,
  can_delete               boolean,
  created_at               timestamptz,
  updated_at               timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;
  end if;

  return query
  select sc.id,
         sc.name,
         sc.kind_code,
         k.label,
         cards.n,
         defs.n,
         (cards.n = 0 and defs.n = 0),
         sc.created_at,
         sc.updated_at
  from public.storage_container sc
  left join public.storage_container_kind k on k.code = sc.kind_code
  cross join lateral (
    select count(*) as n
    from public.physical_card pc
    where pc.storage_container_id = sc.id
  ) cards
  cross join lateral (
    select count(*) as n
    from public.collection c
    where c.default_storage_container_id = sc.id
  ) defs
  where sc.inventory_id = v_inventory
  order by lower(sc.name), sc.created_at, sc.id;
end;
$$;

create or replace function public.get_my_storage_summary()
returns table (
  total_cards     bigint,
  located_cards   bigint,
  unlocated_cards bigint,
  location_count  bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return query select 0::bigint, 0::bigint, 0::bigint, 0::bigint;
    return;
  end if;

  return query
  select t.total,
         t.located,
         t.total - t.located,
         (select count(*) from public.storage_container sc where sc.inventory_id = v_inventory)
  from (
    select count(*) as total,
           count(pc.storage_container_id) as located
    from public.physical_card pc
    where pc.inventory_id = v_inventory
  ) t;
end;
$$;

revoke all on function public.get_my_storage_locations() from public;
revoke all on function public.get_my_storage_locations() from anon;
grant execute on function public.get_my_storage_locations() to authenticated;

revoke all on function public.get_my_storage_summary() from public;
revoke all on function public.get_my_storage_summary() from anon;
grant execute on function public.get_my_storage_summary() to authenticated;

commit;
