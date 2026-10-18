/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5196 - get_my_master_set_out_of_scope_copies(): exemplares
              vinculados que não satisfazem o objetivo atual, com motivo
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018170621; 5836 v1.3 74/74 PASS,
              5837 v1.2 10/10 PASS; baseline 5840 inalterado
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: C-188 (exemplares fora do objetivo continuam na coleção),
LDM-193, LDM-195 (evidência para que mudanças de progresso causadas por
correção/desativação do catálogo não fiquem inexplicáveis — cuidado C).
Não cria histórico: descreve o estado atual.

Contrato:
  get_my_master_set_out_of_scope_copies(p_collection_id uuid,
                                        p_limit integer default 200,
                                        p_offset integer default 0)
  Uma linha por exemplar vinculado que não satisfaz nenhuma posição:
    physical_card_id, card_id, collector_number, card_name,
    variant_type_code, variant_type_name, reason, total_count.
  reason (primeiro que se aplicar):
    CARD_INACTIVE        — a carta foi desativada no catálogo;
    PAIR_NOT_IN_CATALOG  — não há mais variante ativa dessa carta nesse
                           acabamento (ex.: variante desativada);
    FINISH_NOT_SELECTED  — o acabamento não está no objetivo.
  Só coleção MASTER_SET do próprio usuário; outra → zero linhas.

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid(),
EXECUTE só authenticated. Erros: 28000; 22023 INVALID_PAGE.
Como validar: 5836 casos 6.x e 10.x.
================================================================
*/

begin;

create or replace function public.get_my_master_set_out_of_scope_copies(
  p_collection_id uuid,
  p_limit         integer default 200,
  p_offset        integer default 0
)
returns table (
  physical_card_id  uuid,
  card_id           uuid,
  collector_number  text,
  card_name         text,
  variant_type_code text,
  variant_type_name text,
  reason            text,
  total_count       bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user  uuid := auth.uid();
  v_set   uuid;
  v_types uuid[];
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 or p_offset is null or p_offset < 0 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'MASTER_SET';

  if v_set is null then
    return;
  end if;

  select array_agg(f.variant_type_id) into v_types
  from public.collection_master_set_finish f
  where f.collection_id = p_collection_id;

  return query
  with positions as (
    select p.card_id, p.variant_type_id
    from public.master_set_positions(v_set, v_types) p
  ),
  copies as (
    select pc.id as physical_card_id, c.id as card_id, c.collector_number::text as number,
           c.collector_order, c.name::text as card_name, c.is_active as card_active,
           cv.variant_type_id, t.code::text as type_code, t.name::text as type_name
    from public.collection_allocation ca
    join public.physical_card pc       on pc.id = ca.physical_card_id
    join public.card_variant cv        on cv.id = pc.card_variant_id
    join public.card c                 on c.id = cv.card_id
    join public.card_variant_type t    on t.id = cv.variant_type_id
    where ca.collection_id = p_collection_id
  ),
  outside as (
    select cp.*,
           case
             when not cp.card_active then 'CARD_INACTIVE'
             when not exists (select 1 from public.card_variant v
                              where v.card_id = cp.card_id
                                and v.variant_type_id = cp.variant_type_id
                                and v.is_active) then 'PAIR_NOT_IN_CATALOG'
             else 'FINISH_NOT_SELECTED'
           end as why
    from copies cp
    where not exists (
      select 1 from positions p
      where p.card_id = cp.card_id
        and (p.variant_type_id is null or p.variant_type_id = cp.variant_type_id)
    )
  )
  select o.physical_card_id, o.card_id, o.number, o.card_name, o.type_code, o.type_name,
         o.why, count(*) over ()
  from outside o
  order by o.collector_order, o.number, o.type_code, o.physical_card_id
  limit p_limit offset p_offset;
end;
$$;

comment on function public.get_my_master_set_out_of_scope_copies(uuid, integer, integer) is
  'Master Set (Query 5196): exemplares vinculados a uma coleção MASTER_SET do usuário que não satisfazem nenhuma posição atual, com o motivo (carta inativa, combinação fora do catálogo vigente, acabamento não escolhido). Nunca altera nada.';

revoke all on function public.get_my_master_set_out_of_scope_copies(uuid, integer, integer) from public, anon;
grant execute on function public.get_my_master_set_out_of_scope_copies(uuid, integer, integer) to authenticated;

commit;
