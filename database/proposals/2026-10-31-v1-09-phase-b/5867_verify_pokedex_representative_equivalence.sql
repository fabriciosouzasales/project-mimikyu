/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5867 - Equivalência real do representante da Pokédex:
              5204 × 5209 × 5334 (fecha a ressalva da 5866 Parte 4.2)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (somente leitura) no LIVE em 2026-10-31,
              LOCAL HOMOLOGATION-04: 0 posições antes do vínculo (ok=false,
              nada comprovado); após o vínculo real Nº 0001 (2 exemplares),
              1/1 posição ok, 0 divergências de número/Set, variante e imagem
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Por que existe
  A 5866 v1.1 passou 12/12, mas a 4.2 não comparou nada: a única coleção
  Pokédex do LIVE não tinha exemplares vinculados. Esta verificação roda
  sobre vínculos REAIS criados pelo titular pela interface (sem fixture,
  sem INSERT) e compara, posição a posição, os três caminhos de leitura:
    5204 get_my_pokedex_positions        — carta exibida (número, Set, imagem)
    5209 get_my_pokedex_position_copies  — 1ª linha = exemplar escolhido
                                           pela grade (physical_card_id)
    5334 get_my_pokedex_representative_variants — variante da etiqueta

Somente leitura
  BEGIN READ ONLY … ROLLBACK. Nenhuma escrita é possível (o Postgres
  rejeita). A identidade do titular é simulada só para auth.uid() dentro
  da transação (set_config local), como o PostgREST faz.

Como usar
  Substituir <COLLECTION_ID> pelo id da coleção Pokédex (nunca o id do
  usuário; o titular é lido da própria coleção). Executar o bloco inteiro.

Resultado esperado
  Linha de resumo: positions_owned >= 1, rep_rows = positions_owned,
  mismatch_number_set = 0, mismatch_variant = 0, mismatch_image = 0.
  Linhas por posição: todas com ok = true. price_available false NÃO é
  falha (ausência de cotação ≠ divergência de representante).
================================================================
*/

begin read only;

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', c.owner_user_id, 'role', 'authenticated')::text
     from public.collection c where c.id = '<COLLECTION_ID>'::uuid),
  true) is not null as identity_set;

with
p as (  -- 5204: posições conquistadas (até 500; a página da grade usa 120)
  select * from public.get_my_pokedex_positions('<COLLECTION_ID>'::uuid, 'OWNED', null, 500, 0)
),
r as (  -- 5334: variante do representante
  select * from public.get_my_pokedex_representative_variants(
    '<COLLECTION_ID>'::uuid, coalesce((select array_agg(pokedex_position_id) from p), array[gen_random_uuid()]))
),
c as (  -- 5209: exemplares da posição na ordem da grade; 1ª linha = representante
  select p.pokedex_position_id, f.physical_card_id, f.collector_number, f.card_set_code,
         f.image_path, f.is_representative, f.total_count
  from p cross join lateral (
    select * from public.get_my_pokedex_position_copies('<COLLECTION_ID>'::uuid, p.pokedex_position_id) limit 1
  ) f
),
pr as (  -- 3983: só informativo (cotação disponível?)
  select card_variant_id, has_pricing from public.get_card_variants_pricing_summary(
    coalesce((select (array_agg(distinct card_variant_id))[1:100] from r), array[gen_random_uuid()]))
),
cmp as (
  select
    p.position_number,
    p.species_name,
    c.total_count                                   as copies_linked,
    c.is_representative                             as has_primary_choice,
    p.representative_set_code || ' ' || p.representative_collector_number as shown_5204,
    r.card_set_code || ' ' || r.collector_number    as label_5334,
    c.card_set_code || ' ' || c.collector_number    as first_copy_5209,
    r.variant_label,
    (r.pokedex_position_id is not null
       and r.collector_number = p.representative_collector_number
       and lower(r.card_set_code) = lower(p.representative_set_code)) as same_number_set,
    (pc.card_variant_id is not distinct from r.card_variant_id)        as same_variant,
    (c.image_path is not distinct from p.representative_image_path)    as same_image,
    coalesce(pr.has_pricing, false)                                     as price_available
  from p
  left join r  on r.pokedex_position_id = p.pokedex_position_id
  left join c  on c.pokedex_position_id = p.pokedex_position_id
  left join public.physical_card pc on pc.id = c.physical_card_id
  left join pr on pr.card_variant_id = r.card_variant_id
)
select 'POSITION' as kind, position_number, species_name, copies_linked, has_primary_choice,
       shown_5204, label_5334, first_copy_5209, variant_label,
       same_number_set, same_variant, same_image, price_available,
       (same_number_set and same_variant and same_image) as ok
from cmp
union all
select 'SUMMARY', count(*)::int, null, null, null, null, null, null, null,
       count(*) filter (where not same_number_set) = 0,
       count(*) filter (where not same_variant) = 0,
       count(*) filter (where not same_image) = 0,
       null,
       count(*) > 0 and bool_and(same_number_set and same_variant and same_image)
from cmp
order by 1 desc, 2;

rollback;
