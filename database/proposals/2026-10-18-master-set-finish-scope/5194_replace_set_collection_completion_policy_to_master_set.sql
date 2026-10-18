/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5194 - set_collection_completion_policy_to_master_set()
              v2.0: ativar o Master Set por acabamentos
Versão......: 2.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Substitui a v1.0 (5080, assinatura (uuid, jsonb) com card_variant_ids).
Mesmo nome — o conceito de "ativar Master Set" não mudou; muda o
argumento. A assinatura antiga é removida (DROP) para não restar uma
segunda função que escreva na tabela aposentada. Nenhum consumidor no
frontend (grep em web/ e supabase/ em 2026-10-18: zero ocorrências).

Contrato:
  set_collection_completion_policy_to_master_set(
      p_collection_id    uuid,
      p_variant_type_ids uuid[] default null)
  → (collection_id, completion_policy, finishes_added, finishes_removed,
     finishes_kept, total_positions, satisfied_positions)

  - p_variant_type_ids informado: valida (5190) e grava a diferença
    (5193), depois muda a política para MASTER_SET.
  - p_variant_type_ids NULL: restaura a seleção guardada (C-23/LDM-22);
    sem seleção guardada → NO_SAVED_FINISHES.
  - Coleção já MASTER_SET: NULL é no-op idempotente (devolve o estado);
    com lista, aplica a lista (mesmo efeito de 5195). Reenvio da mesma
    chamada nunca falha nem duplica (diferença da v1.0, que recusava).
  - Defesa final: se o objetivo resultante tiver zero posições
    (seleção restaurada cujos acabamentos sumiram do Set e Set sem
    secretas) → EMPTY_OBJECTIVE, nada é gravado.
  - Só altera collection.completion_policy e
    collection_master_set_finish. Nunca toca exemplares, vínculos,
    locais, referência ou fichário (C-23, LDM-194).

Segurança/concorrência: SECURITY DEFINER, search_path '', EXECUTE só
authenticated; dono por auth.uid() no WHERE com FOR UPDATE (serializa
com 5195, 5081, 5046/5047, que travam a mesma linha); coleção alheia ou
inexistente → mesma resposta.
Erros: 28000 not_authenticated; P0002 COLLECTION_NOT_FOUND;
P0001 COLLECTION_ARCHIVED; P0001 MASTER_SET_REQUIRES_SET_COLLECTION;
22023 INVALID_FINISHES; P0001 FINISH_NOT_IN_SET; P0001 NO_SAVED_FINISHES;
P0001 EMPTY_OBJECTIVE.
Como validar: 5836 casos 1.x–5.x, 7.x.
================================================================
*/

begin;

drop function if exists public.set_collection_completion_policy_to_master_set(uuid, jsonb);

create or replace function public.set_collection_completion_policy_to_master_set(
    p_collection_id    uuid,
    p_variant_type_ids uuid[] default null
)
returns table (
    collection_id       uuid,
    completion_policy   text,
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
    v_added   integer := 0;
    v_removed integer := 0;
    v_kept    integer := 0;
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

    if p_variant_type_ids is null then
        select count(*) into v_kept
        from public.collection_master_set_finish f
        where f.collection_id = p_collection_id;

        if v_kept = 0 then
            raise exception 'NO_SAVED_FINISHES' using errcode = 'P0001';
        end if;
    else
        v_types := public.normalize_master_set_finishes(v_set, v_coll.game_id, p_variant_type_ids);
        select a.added_count, a.removed_count, a.kept_count
          into v_added, v_removed, v_kept
        from public.apply_master_set_finishes(p_collection_id, v_user, v_types) a;
    end if;

    if v_coll.completion_policy <> 'MASTER_SET' then
        update public.collection
           set completion_policy = 'MASTER_SET'
         where public.collection.id = p_collection_id;
    end if;

    select s.total_positions, s.satisfied_positions
      into v_total, v_sat
    from public.collection_completion_summary(p_collection_id) s;

    if coalesce(v_total, 0) = 0 then
        raise exception 'EMPTY_OBJECTIVE' using errcode = 'P0001';
    end if;

    return query
    select p_collection_id, 'MASTER_SET'::text, v_added, v_removed, v_kept, v_total, v_sat;
end;
$$;

comment on function public.set_collection_completion_policy_to_master_set(uuid, uuid[]) is
  'Master Set (Query 5194, v2.0): ativa o Master Set de uma coleção de Set do usuário com os acabamentos informados, ou restaura os guardados (NULL). Idempotente. Nunca altera exemplares.';

revoke all on function public.set_collection_completion_policy_to_master_set(uuid, uuid[]) from public, anon;
grant execute on function public.set_collection_completion_policy_to_master_set(uuid, uuid[]) to authenticated;

commit;
