/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5187 - master_set_positions(): fonte única das posições
              do Master Set (função interna)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: LDM-192 (derivação), C-189 (secretas), C-190/LDM-195
(catálogo vigente). Todas as leituras do Master Set (5188 resumo,
5189 grade, 5191 opções, 5192 prévia, 5196 fora do objetivo) chamam
esta função —
resumo, grade e prévia nunca divergem.

Contrato:
  master_set_positions(p_card_set_id uuid, p_variant_type_ids uuid[])
  → (card_id uuid, variant_type_id uuid, is_secret boolean)

  1. Posição de acabamento: cada par distinto (card_id, variant_type_id)
     com Card ATIVA do Set e ≥ 1 Card Variant ATIVA naquele acabamento
     (qualquer contexto de edição ou perfil de impressão), acabamento ∈
     p_variant_type_ids.
  2. Posição de carta secreta: variant_type_id NULL. Uma por Card ATIVA
     do Set cujo collector_number é só dígitos (1–9) e maior que
     card_set.base_set_size, que tenha ≥ 1 variante ativa e que NÃO
     tenha nenhuma posição pelo item 1. Secreta com vários acabamentos
     fora da seleção → uma posição só (cuidado A da rodada).
  Sem duplicação por construção (DISTINCT no item 1; item 2 exclui
  cartas presentes no item 1).

Cast seguro: a comparação numérica só ocorre dentro de CASE após o
teste de formato (a ordem de avaliação de AND não é garantida).

Função interna: SECURITY DEFINER (catálogo tem RLS admin-only),
search_path vazio, STABLE, EXECUTE revogado de PUBLIC/anon/
authenticated. NÃO verifica dono — quem chama (5188/5189/5191/5192/5196)
já reconstituiu a fronteira de autorização antes de chamá-la; ela
recebe só ids de catálogo e devolve só ids de catálogo.

Desempenho: índices existentes uq_card_card_set_collector_number
(card_set_id, …) e uq_card_variant_identity (card_id, variant_type_id,
…). Volume máximo atual: 295 cartas / 623 variantes por Set.

Resultado esperado: função criada sem EXECUTE para clientes.
Como validar: 5836 casos 3.x e 6.x; 5837.
================================================================
*/

begin;

create or replace function public.master_set_positions(
    p_card_set_id      uuid,
    p_variant_type_ids uuid[]
)
returns table (
    card_id         uuid,
    variant_type_id uuid,
    is_secret       boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    with set_info as (
        select cs.base_set_size
        from public.card_set cs
        where cs.id = p_card_set_id
    ),
    active_cards as (
        select
            c.id,
            coalesce(
                case
                    when c.collector_number ~ '^[0-9]{1,9}$'
                        then c.collector_number::integer > si.base_set_size
                    else false
                end,
                false
            ) as is_secret
        from public.card c
        cross join set_info si
        where c.card_set_id = p_card_set_id
          and c.is_active
    ),
    finish_positions as (
        select distinct
            ac.id              as card_id,
            cv.variant_type_id as variant_type_id,
            ac.is_secret       as is_secret
        from active_cards ac
        join public.card_variant cv
            on cv.card_id = ac.id
           and cv.is_active
        where cv.variant_type_id = any (coalesce(p_variant_type_ids, '{}'::uuid[]))
    ),
    secret_positions as (
        select
            ac.id       as card_id,
            null::uuid  as variant_type_id,
            true        as is_secret
        from active_cards ac
        where ac.is_secret
          and exists (
                select 1 from public.card_variant cv
                where cv.card_id = ac.id and cv.is_active
          )
          and not exists (
                select 1 from finish_positions fp
                where fp.card_id = ac.id
          )
    )
    select fp.card_id, fp.variant_type_id, fp.is_secret from finish_positions fp
    union all
    select sp.card_id, sp.variant_type_id, sp.is_secret from secret_positions sp;
$$;

revoke all on function public.master_set_positions(uuid, uuid[]) from public, anon, authenticated;

commit;
