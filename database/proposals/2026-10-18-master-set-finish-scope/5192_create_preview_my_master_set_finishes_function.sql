/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5192 - preview_my_master_set_finishes(): prévia do impacto
              de um conjunto de acabamentos, sem gravar nada
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: C-188 (prévia obrigatória antes de confirmar).

Contrato:
  preview_my_master_set_finishes(p_collection_id uuid,
                                 p_variant_type_ids uuid[])
  → uma linha:
    current_policy        — política atual (STANDARD_SET | MASTER_SET);
    current_total / current_satisfied
                          — progresso atual (collection_completion_summary);
    proposed_total / proposed_satisfied
                          — progresso se o conjunto fosse gravado;
    proposed_secret_positions
                          — dessas posições, quantas são de carta secreta
                            não contemplada pelos acabamentos;
    positions_added / positions_removed
                          — diferença em relação às posições Master Set
                            atuais (em STANDARD_SET: atuais = vazio);
    copies_in_collection  — exemplares vinculados;
    copies_outside_after  — dos vinculados, quantos ficariam "fora do
                            objetivo" (não satisfazem nenhuma posição).
  Mesma validação da gravação (normalize_master_set_finishes, 5190):
  o que a prévia aceita, 5194/5195 gravam com o mesmo resultado (5836 7.x).
  Não escreve nada (STABLE).

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid(),
EXECUTE só authenticated.
Erros: 28000 not_authenticated; P0002 COLLECTION_NOT_FOUND (alheia ou
inexistente, mesma resposta); P0001 MASTER_SET_REQUIRES_SET_COLLECTION;
22023 INVALID_FINISHES; P0001 FINISH_NOT_IN_SET.
Como validar: 5836 casos 7.x.
================================================================
*/

begin;

create or replace function public.preview_my_master_set_finishes(
  p_collection_id    uuid,
  p_variant_type_ids uuid[]
)
returns table (
  current_policy            text,
  current_total             bigint,
  current_satisfied         bigint,
  proposed_total            bigint,
  proposed_satisfied        bigint,
  proposed_secret_positions bigint,
  positions_added           bigint,
  positions_removed         bigint,
  copies_in_collection      bigint,
  copies_outside_after      bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user     uuid := auth.uid();
  v_coll     public.collection%rowtype;
  v_set      uuid;
  v_types    uuid[];
  v_current  uuid[];
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select c.* into v_coll
  from public.collection c
  where c.id = p_collection_id
    and c.owner_user_id = v_user;

  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select ccsr.card_set_id into v_set
  from public.collection_reference cr
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where cr.collection_id = p_collection_id
    and cr.reference_kind = 'CARD_SET';

  if v_coll.mode is distinct from 'REFERENCE_BASED'
     or v_set is null
     or v_coll.completion_policy not in ('STANDARD_SET', 'MASTER_SET') then
    raise exception 'MASTER_SET_REQUIRES_SET_COLLECTION' using errcode = 'P0001';
  end if;

  v_types := public.normalize_master_set_finishes(v_set, v_coll.game_id, p_variant_type_ids);

  if v_coll.completion_policy = 'MASTER_SET' then
    select array_agg(f.variant_type_id) into v_current
    from public.collection_master_set_finish f
    where f.collection_id = p_collection_id;
  end if;

  return query
  with owned_copies as (
    select pc.id as physical_card_id, cv.card_id, cv.variant_type_id
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
  ),
  owned as (
    select distinct oc.card_id, oc.variant_type_id from owned_copies oc
  ),
  proposed as (
    select p.card_id, p.variant_type_id, p.is_secret
    from public.master_set_positions(v_set, v_types) p
  ),
  current_ms as (
    select p.card_id, p.variant_type_id
    from public.master_set_positions(v_set, v_current) p
    where v_coll.completion_policy = 'MASTER_SET'
  ),
  summary as (
    select s.total_positions, s.satisfied_positions
    from public.collection_completion_summary(p_collection_id) s
  )
  select
    v_coll.completion_policy,
    (select sm.total_positions from summary sm),
    (select sm.satisfied_positions from summary sm),
    (select count(*) from proposed),
    (select count(*) from proposed pp
      where exists (select 1 from owned o
                    where o.card_id = pp.card_id
                      and (pp.variant_type_id is null or o.variant_type_id = pp.variant_type_id))),
    (select count(*) from proposed pp where pp.variant_type_id is null),
    (select count(*) from proposed pp
      where not exists (select 1 from current_ms cm
                        where cm.card_id = pp.card_id
                          and cm.variant_type_id is not distinct from pp.variant_type_id)),
    (select count(*) from current_ms cm
      where not exists (select 1 from proposed pp
                        where pp.card_id = cm.card_id
                          and pp.variant_type_id is not distinct from cm.variant_type_id)),
    (select count(*) from owned_copies),
    (select count(*) from owned_copies oc
      where not exists (select 1 from proposed pp
                        where pp.card_id = oc.card_id
                          and (pp.variant_type_id is null or pp.variant_type_id = oc.variant_type_id)));
end;
$$;

comment on function public.preview_my_master_set_finishes(uuid, uuid[]) is
  'Master Set (Query 5192): prévia, sem gravar, do progresso e das posições que um conjunto de acabamentos produziria numa coleção de Set do usuário. Mesma validação de 5194/5195.';

revoke all on function public.preview_my_master_set_finishes(uuid, uuid[]) from public, anon;
grant execute on function public.preview_my_master_set_finishes(uuid, uuid[]) to authenticated;

commit;
