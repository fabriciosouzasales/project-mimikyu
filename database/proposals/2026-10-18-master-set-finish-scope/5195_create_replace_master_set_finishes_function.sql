/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5195 - replace_master_set_finishes(): editar os
              acabamentos de uma coleção em Master Set — substitui 5082
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: C-188 (edição a qualquer momento, por ação explícita),
LDM-194. Remove replace_master_set_scope(uuid, jsonb) (5082), que
recebia card_variant_ids e escrevia na tabela aposentada.

Contrato:
  replace_master_set_finishes(p_collection_id uuid,
                              p_variant_type_ids uuid[])
  → (collection_id, finishes_added, finishes_removed, finishes_kept,
     total_positions, satisfied_positions)
  - Só coleção ACTIVE em MASTER_SET (em STANDARD_SET a escolha é feita
    na ativação, 5194) → caso contrário MASTER_SET_NOT_ACTIVE.
  - Mesmo conjunto atual → zero escrita (idempotente).
  - Acabamento mantido preserva adopted_at/adopted_by_user_id.
  - Defesa final EMPTY_OBJECTIVE como em 5194.
  - Nunca toca exemplares, vínculos, locais ou fichário.

Segurança/concorrência: idem 5194 (FOR UPDATE na linha da coleção).
Erros: 28000; P0002 COLLECTION_NOT_FOUND; P0001 COLLECTION_ARCHIVED;
P0001 MASTER_SET_NOT_ACTIVE; 22023 INVALID_FINISHES;
P0001 FINISH_NOT_IN_SET; P0001 EMPTY_OBJECTIVE.
Como validar: 5836 casos 5.x, 7.x, 9.x.
================================================================
*/

begin;

drop function if exists public.replace_master_set_scope(uuid, jsonb);

create or replace function public.replace_master_set_finishes(
    p_collection_id    uuid,
    p_variant_type_ids uuid[]
)
returns table (
    collection_id       uuid,
    finishes_added      integer,
    finishes_removed    integer,
    finishes_kept       integer,
    total_positions     bigint,
    satisfied_positions bigint
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
    v_user    uuid := auth.uid();
    v_coll    public.collection%rowtype;
    v_set     uuid;
    v_types   uuid[];
    v_added   integer;
    v_removed integer;
    v_kept    integer;
    v_total   bigint;
    v_sat     bigint;
begin
    if v_user is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    select c.* into v_coll
    from public.collection c
    where c.id = p_collection_id
      and c.owner_user_id = v_user
    for update;

    if not found then
        raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
    end if;

    if v_coll.lifecycle_status <> 'ACTIVE' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = 'P0001';
    end if;

    if v_coll.completion_policy is distinct from 'MASTER_SET' then
        raise exception 'MASTER_SET_NOT_ACTIVE' using errcode = 'P0001';
    end if;

    select ccsr.card_set_id into v_set
    from public.collection_reference cr
    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id
      and cr.reference_kind = 'CARD_SET';

    v_types := public.normalize_master_set_finishes(v_set, v_coll.game_id, p_variant_type_ids);

    select a.added_count, a.removed_count, a.kept_count
      into v_added, v_removed, v_kept
    from public.apply_master_set_finishes(p_collection_id, v_user, v_types) a;

    select s.total_positions, s.satisfied_positions
      into v_total, v_sat
    from public.collection_completion_summary(p_collection_id) s;

    if coalesce(v_total, 0) = 0 then
        raise exception 'EMPTY_OBJECTIVE' using errcode = 'P0001';
    end if;

    return query
    select p_collection_id, v_added, v_removed, v_kept, v_total, v_sat;
end;
$$;

comment on function public.replace_master_set_finishes(uuid, uuid[]) is
  'Master Set (Query 5195): troca os acabamentos do objetivo de uma coleção em Master Set do usuário. Idempotente; preserva a adoção dos acabamentos mantidos; nunca altera exemplares.';

revoke all on function public.replace_master_set_finishes(uuid, uuid[]) from public, anon;
grant execute on function public.replace_master_set_finishes(uuid, uuid[]) to authenticated;

commit;
