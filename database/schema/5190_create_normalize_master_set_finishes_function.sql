/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5190 - normalize_master_set_finishes(): validação única
              do conjunto de acabamentos (função interna)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018170423; 5836 v1.3 74/74 PASS,
              5837 v1.2 10/10 PASS; baseline 5840 inalterado
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Por quê: a prévia (5192), a ativação (5194) e a edição (5195) precisam
aceitar e recusar exatamente os mesmos conjuntos — senão a prévia
mostraria algo que a gravação recusa. Uma função só, chamada pelas três.
O gatilho 5185 continua como barreira estrutural independente.

Contrato:
  normalize_master_set_finishes(p_card_set_id uuid, p_game_id uuid,
                                p_variant_type_ids uuid[]) → uuid[]
  Devolve o conjunto ordenado, ou levanta:
    22023 INVALID_FINISHES  — nulo, vazio, elemento nulo, repetido ou
                              mais de 64 itens;
    P0001 FINISH_NOT_IN_SET — algum acabamento não é do Game da coleção
                              ou não tem nenhuma carta ativa com variante
                              ativa no Set (DETAIL = id recusado).
Não aceita "um só" como inválido: qualquer conjunto não vazio de
acabamentos existentes no Set é válido (decisão de Fabrício).

Função interna: SECURITY DEFINER, STABLE, search_path vazio, EXECUTE
revogado de PUBLIC/anon/authenticated. Não verifica dono (quem chama já
verificou).
Como validar: 5836 casos 4.x.
================================================================
*/

begin;

create or replace function public.normalize_master_set_finishes(
    p_card_set_id      uuid,
    p_game_id          uuid,
    p_variant_type_ids uuid[]
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_bad    uuid;
    v_result uuid[];
begin
    if p_variant_type_ids is null
       or cardinality(p_variant_type_ids) = 0
       or cardinality(p_variant_type_ids) > 64
       or array_position(p_variant_type_ids, null) is not null
       or (select count(distinct x) from unnest(p_variant_type_ids) x) <> cardinality(p_variant_type_ids) then
        raise exception 'INVALID_FINISHES' using errcode = '22023';
    end if;

    select x into v_bad
    from unnest(p_variant_type_ids) x
    where not exists (
        select 1
        from public.card_variant_type t
        join public.card_variant cv on cv.variant_type_id = t.id and cv.is_active
        join public.card c          on c.id = cv.card_id and c.is_active
        where t.id = x
          and t.game_id = p_game_id
          and c.card_set_id = p_card_set_id
    )
    limit 1;

    if v_bad is not null then
        raise exception 'FINISH_NOT_IN_SET' using errcode = 'P0001', detail = v_bad::text;
    end if;

    select array_agg(x order by x) into v_result from unnest(p_variant_type_ids) x;
    return v_result;
end;
$$;

revoke all on function public.normalize_master_set_finishes(uuid, uuid, uuid[]) from public, anon, authenticated;

commit;
