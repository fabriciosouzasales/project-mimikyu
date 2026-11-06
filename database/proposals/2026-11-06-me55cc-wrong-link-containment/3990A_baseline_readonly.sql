/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3990A - ME5.5CC WRONG LINK CONTAINMENT-01 — linha de base (SOMENTE LEITURA)
Status......: PROPOSTO — NÃO EXECUTADO
Data........: 2026-11-06

Objetivo
  Registrar, antes da contenção, o estado exato dos 5 vínculos incorretos do Card Set ME5.5CC
  (numeração original das reimpressões JustTCG casada com a numeração local 001–030) e a
  referência hoje devolvida pela 3989. Nenhuma escrita.

Como executar
  SQL Editor (postgres). A parte B simula o titular (admin único) dentro de uma transação
  desfeita no fim — a 3989 exige auth.uid().

Resultado esperado (coletado em 2026-11-06, leitura)
  A: 5 linhas, todas CONFIRMED/PRIMARY CONFIRMED, 19 produtos, 213 observações, 0 aliases,
     0 preços manuais, 0 produtos externos compartilhados, 0 outros mapeamentos com o mesmo
     external_card_id.
  B: 004 R$ 808,39 · 005 R$ 25,29 · 018 R$ 28,57 · 019 R$ 55,00 · 025 R$ 22,78 — todos
     price_basis = VARIANT.
================================================================
*/

-- A. Vínculos, identidades, produtos e dependências
with target(mapping_id, collector_number, external_card_id) as (values
  ('63ad9941-d8b2-495f-9260-5fc92f38bceb'::uuid, '004', 'pokemon-me-30th-celebration-classic-collection-charizard-classic-collection'),
  ('1d3f88ea-3706-4763-90aa-70c8c20f668f'::uuid, '005', 'pokemon-me-30th-celebration-classic-collection-delcatty-classic-collection'),
  ('61c330ab-dd73-4d4c-99e0-1c3ab0af8bbe'::uuid, '018', 'pokemon-me-30th-celebration-classic-collection-misty-classic-collection'),
  ('bb3044be-7e6e-4e59-a2f1-98ef938e2740'::uuid, '019', 'pokemon-me-30th-celebration-classic-collection-dark-tyranitar-classic-collection'),
  ('001152c1-b86c-4957-86a0-345fd09f0f4c'::uuid, '025', 'pokemon-me-30th-celebration-classic-collection-sneasel-classic-collection')
)
select t.collector_number, c.name, m.id mapping_id, m.match_status, m.external_card_id = t.external_card_id as external_ok,
  m.confirmed_at, m.confirmed_by, m.confirmed_sync_run_id,
  (select string_agg(i.id::text || ':' || i.identity_role || ':' || i.match_status, ' | ') from public.pricing_source_card_identity i where i.pricing_card_mapping_id = m.id) identities,
  (select count(*) from public.pricing_product p where p.pricing_card_mapping_id = m.id) products,
  (select count(*) from public.pricing_product p where p.pricing_card_mapping_id = m.id and p.is_active) active_products,
  (select count(*) from public.pricing_product p join public.pricing_observation o on o.pricing_product_id = p.id where p.pricing_card_mapping_id = m.id) observations,
  (select count(*) from public.pricing_source_card_identity a where a.canonical_identity_id in (select i.id from public.pricing_source_card_identity i where i.pricing_card_mapping_id = m.id)) alias_refs,
  (select count(*) from public.pricing_manual_price mp where mp.card_id = m.card_id) manual_prices,
  (select count(*) from public.pricing_product p join public.pricing_product q on q.external_product_id = p.external_product_id and q.id <> p.id where p.pricing_card_mapping_id = m.id) shared_external_products,
  (select count(*) from public.pricing_card_mapping o2 where o2.external_card_id = m.external_card_id and o2.id <> m.id) other_mappings_same_external
from target t
join public.pricing_card_mapping m on m.id = t.mapping_id
join public.card c on c.id = m.card_id
order by 1;

-- B. Referência devolvida pela 3989 (titular simulado; nada persiste)
begin;
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.admin_user limit 1), 'role', 'authenticated')::text, true);
set local role authenticated;
select c.collector_number, c.name, s.has_pricing, s.brl_amount, s.source_amount, s.price_basis, s.observed_at
from public.card_variant cv
join public.card c on c.id = cv.card_id
join public.card_set cs on cs.id = c.card_set_id
cross join lateral public.get_card_variants_pricing_summary(array[cv.id]) s
where cs.code = 'ME5.5CC' and c.collector_number in ('004', '005', '018', '019', '025')
order by 1;
rollback;

-- C. Contagens globais (comparadas no postcheck: só o ME5.5CC pode mudar)
select
  (select count(*) from public.pricing_card_mapping where match_status = 'CONFIRMED') confirmed_mappings,
  (select count(*) from public.pricing_card_mapping where match_status = 'REJECTED') rejected_mappings,
  (select count(*) from public.pricing_source_card_identity where match_status = 'CONFIRMED') confirmed_identities,
  (select count(*) from public.pricing_source_card_identity where match_status = 'REJECTED') rejected_identities,
  (select count(*) from public.pricing_product) products,
  (select count(*) from public.pricing_product where is_active) active_products,
  (select count(*) from public.pricing_observation) observations;
