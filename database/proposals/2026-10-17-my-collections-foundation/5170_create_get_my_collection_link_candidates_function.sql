/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5170 - get_my_collection_link_candidates(): exemplares
              do acervo que podem ser vinculados a uma coleção de Set
              (R3, MY-COLLECTIONS-FOUNDATION-01)
Versão......: 1.1 (2026-10-17: só "1 de cada" — modo ALL removido por
              condição de Fabrício para a primeira experiência)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (autorização
              condicionada de Fabrício) — ledger 20261017152501; 5830 v1.1 35/35 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto:
"Vincular as cartas que já tenho" (Fluxo 2/3, C-03 "explícito não é
manual um a um", C-19 sugestão nunca automática). Sem esta leitura o
cliente teria de chamar 5162 por carta (N+1). Decisão D-C (Fabrício,
2026-10-17): "1 de cada". Condição da autorização de implantação
(2026-10-17): a primeira experiência NÃO oferece vincular todas as
repetidas — por isso a função só tem o modo "1 de cada". As repetidas
continuam no acervo (Meu acervo) e aparecem como disponíveis em 5169.

Contrato:
  get_my_collection_link_candidates(p_collection_id uuid,
                                    p_limit integer default 500)
  Exemplares do próprio Inventory, do Set referenciado pela coleção e
  que não estão em nenhuma coleção (Allocation é exclusiva —
  UNIQUE(physical_card_id); vincular nunca duplica carta).
  Só cartas ainda não satisfeitas nesta coleção, um exemplar por carta —
  variante padrão primeiro, depois o exemplar mais antigo (determinístico).
  Ordem do Set. p_limit ≤ 500 = teto de allocate_physical_cards_to_collection
  (5046). total_count = total antes do limite; o cliente repete a leitura
  após cada lote até zerar (a leitura recalcula do estado atual, então
  um envio repetido não aloca duas vezes — 5046 recusa o lote inteiro
  se algum exemplar já estiver alocado).
  Coleção arquivada, livre, alheia ou inexistente → zero linhas.

A escrita continua sendo 5046 (allocate_physical_cards_to_collection),
sem alteração.

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por
auth.uid() verificado antes do catálogo, EXECUTE só authenticated.
Performance: ix_physical_card_inventory_variant + UNIQUE de
collection_allocation(physical_card_id) para o anti-join.

Erros: 28000 not_authenticated; 22023 INVALID_LIMIT.
Como validar: Query 5830.
================================================================
*/

begin;

create or replace function public.get_my_collection_link_candidates(
  p_collection_id uuid,
  p_limit         integer default 500
)
returns table (
  physical_card_id uuid,
  card_id          uuid,
  collector_number text,
  card_name        text,
  language_code    text,
  total_count      bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
  v_set       uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'INVALID_LIMIT' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo.
  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.lifecycle_status = 'ACTIVE'
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'STANDARD_SET';

  if v_set is null then
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with eligible as (
    select pc.id, cv.card_id, c.collector_order, c.collector_number::text as number,
           c.name::text as card_name, l.code::text as lang,
           row_number() over (partition by cv.card_id
                              order by cv.is_default desc, pc.created_at, pc.id) as rn,
           pc.created_at
    from public.physical_card pc
    join public.card_variant cv on cv.id = pc.card_variant_id
    join public.card c          on c.id = cv.card_id and c.card_set_id = v_set
    left join public.language l on l.id = pc.language_id
    where pc.inventory_id = v_inventory
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
  ),
  satisfied as (
    select distinct cv.card_id
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
  ),
  picked as (
    select e.*, count(*) over () as total
    from eligible e
    where e.rn = 1
      and not exists (select 1 from satisfied s where s.card_id = e.card_id)
    order by e.collector_order, e.number, e.created_at, e.id
    limit p_limit
  )
  select p.id, p.card_id, p.number, p.card_name, p.lang, p.total
  from picked p
  order by p.collector_order, p.number, p.created_at, p.id;
end;
$$;

comment on function public.get_my_collection_link_candidates(uuid, integer) is
  'Minhas coleções (Query 5170): exemplares próprios, sem coleção, do Set de uma coleção STANDARD_SET ativa — 1 exemplar por carta ainda faltante (sem modo "todas"). ≤ 500 por chamada (teto de 5046). Coleção alheia → zero linhas.';

revoke all on function public.get_my_collection_link_candidates(uuid, integer) from public;
revoke all on function public.get_my_collection_link_candidates(uuid, integer) from anon;
grant execute on function public.get_my_collection_link_candidates(uuid, integer) to authenticated;

commit;
