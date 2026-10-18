/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5193 - apply_master_set_finishes(): grava a diferença
              entre os acabamentos atuais e os pedidos (função interna)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018170513; 5836 v1.3 74/74 PASS,
              5837 v1.2 10/10 PASS; baseline 5840 inalterado
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Reaproveita o desenho de apply_master_set_scope_diff (5079) com a nova
granularidade: KEEP (não toca a linha; preserva adopted_at), ADD
(INSERT), REMOVE (DELETE). Idempotente: o mesmo conjunto duas vezes →
zero escrita na segunda. Chamada só por 5194/5195, que já travaram a
linha da coleção (FOR UPDATE) e já normalizaram o conjunto (5190).

Ordem: DELETE antes de INSERT na mesma transação; os gatilhos diferidos
(5076/5186) avaliam a presença só no COMMIT, então trocar todos os
acabamentos de uma vez é válido (o conjunto nunca é vazio no fim).

Contrato:
  apply_master_set_finishes(p_collection_id uuid, p_actor uuid,
                            p_variant_type_ids uuid[])
  → (added_count, removed_count, kept_count)

Função interna: SECURITY DEFINER, VOLATILE, search_path vazio, EXECUTE
revogado de PUBLIC/anon/authenticated.
Como validar: 5836 casos 5.x.
================================================================
*/

begin;

create or replace function public.apply_master_set_finishes(
    p_collection_id    uuid,
    p_actor            uuid,
    p_variant_type_ids uuid[]
)
returns table (
    added_count   integer,
    removed_count integer,
    kept_count    integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_added   integer := 0;
    v_removed integer := 0;
    v_kept    integer := 0;
begin
    select count(*) into v_kept
    from public.collection_master_set_finish f
    where f.collection_id = p_collection_id
      and f.variant_type_id = any (p_variant_type_ids);

    delete from public.collection_master_set_finish f
    where f.collection_id = p_collection_id
      and not (f.variant_type_id = any (p_variant_type_ids));
    get diagnostics v_removed = row_count;

    insert into public.collection_master_set_finish (collection_id, variant_type_id, adopted_by_user_id)
    select p_collection_id, x, p_actor
    from unnest(p_variant_type_ids) x
    where not exists (
        select 1 from public.collection_master_set_finish f
        where f.collection_id = p_collection_id
          and f.variant_type_id = x
    );
    get diagnostics v_added = row_count;

    return query select v_added, v_removed, v_kept;
end;
$$;

revoke all on function public.apply_master_set_finishes(uuid, uuid, uuid[]) from public, anon, authenticated;

commit;
