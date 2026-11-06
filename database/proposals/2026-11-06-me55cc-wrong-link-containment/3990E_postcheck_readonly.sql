/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3990E - ME5.5CC WRONG LINK CONTAINMENT-01 — postcheck após a 3990C (SOMENTE LEITURA)
Status......: PROPOSTO — NÃO EXECUTADO
Data........: 2026-11-06

Resultado esperado
  A: 5 linhas REJECTED, confirmed_at igual ao da linha de base, run original na evidência,
     identidades ainda CONFIRMED (inertes), 19 produtos e as observações da base (+ eventuais
     novas do refresh diário — ver README), 5 registros PRICING_MAPPING_REJECTED da 3990.
  B: as 5 variantes com has_pricing = false, brl_amount nulo, price_basis nulo.
  C: controle — Haunter MEP 027 e uma carta do ME5.5 (Set irmão) continuam cotadas (VARIANT).
  D: valor do acervo: só os 3 exemplares afetados saem do valor estimado (R$ 808,39 + 28,57 + 22,78).
  E: permissões inalteradas na 3989/3972 e nas tabelas.
================================================================
*/

-- A. Estado dos vínculos e dependências
select c.collector_number, c.name, m.match_status, m.confirmed_at, m.confirmed_sync_run_id,
  m.match_evidence -> 'containment_3990' ->> 'previous_confirmed_sync_run_id' previous_run,
  (select string_agg(i.match_status, ',') from public.pricing_source_card_identity i where i.pricing_card_mapping_id = m.id) identities,
  (select count(*) from public.pricing_product p where p.pricing_card_mapping_id = m.id) products,
  (select count(*) from public.pricing_product p join public.pricing_observation o on o.pricing_product_id = p.id where p.pricing_card_mapping_id = m.id) observations,
  (select count(*) from public.pricing_admin_action_log l where l.entity_id = m.id and l.metadata ->> 'query' = '3990') audit_rows
from public.pricing_card_mapping m join public.card c on c.id = m.card_id
where m.id in ('63ad9941-d8b2-495f-9260-5fc92f38bceb', '1d3f88ea-3706-4763-90aa-70c8c20f668f', '61c330ab-dd73-4d4c-99e0-1c3ab0af8bbe',
               'bb3044be-7e6e-4e59-a2f1-98ef938e2740', '001152c1-b86c-4957-86a0-345fd09f0f4c')
order by 1;

-- B/C/D. Leituras como o titular (nada persiste)
begin;
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.admin_user limit 1), 'role', 'authenticated')::text, true);
set local role authenticated;

select 'afetada' kind, c.collector_number, c.name, s.has_pricing, s.brl_amount, s.price_basis
from public.card_variant cv join public.card c on c.id = cv.card_id join public.card_set cs on cs.id = c.card_set_id and cs.code = 'ME5.5CC'
cross join lateral public.get_card_variants_pricing_summary(array[cv.id]) s
where c.collector_number in ('004', '005', '018', '019', '025')
union all
select 'controle', c.collector_number, c.name, s.has_pricing, s.brl_amount, s.price_basis
from public.card_variant cv join public.card c on c.id = cv.card_id join public.card_set cs on cs.id = c.card_set_id
cross join lateral public.get_card_variants_pricing_summary(array[cv.id]) s
where (cs.code = 'MEP' and c.collector_number = '027') or (cs.code = 'ME5.5' and c.collector_number = '002')
order by 1, 2;

-- D. Resumo do acervo do titular: grupos sem cotação entre os afetados
select count(*) filter (where s.has_pricing) priced_groups, count(*) groups
from public.card_variant cv join public.card c on c.id = cv.card_id join public.card_set cs on cs.id = c.card_set_id and cs.code = 'ME5.5CC'
join lateral (select 1 from public.physical_card pc where pc.card_variant_id = cv.id limit 1) owned on true
cross join lateral public.get_card_variants_pricing_summary(array[cv.id]) s;
rollback;

-- E. Permissões (devem ser as mesmas de antes)
select p.oid::regprocedure fn, array_to_string(p.proacl, ',') acl, p.prosecdef
from pg_proc p where p.oid in ('public.get_card_variants_pricing_summary(uuid[])'::regprocedure, 'public.get_cards_pricing_summary(uuid[])'::regprocedure);
select c.relname, c.relrowsecurity, array_to_string(c.relacl, ',') acl
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('pricing_card_mapping', 'pricing_source_card_identity', 'pricing_product', 'pricing_observation', 'pricing_admin_action_log');
