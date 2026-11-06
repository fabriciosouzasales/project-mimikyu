/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3990B - ME5.5CC WRONG LINK CONTAINMENT-01 — HARNESS (dry-run, termina em ROLLBACK)
Status......: PROPOSTO — NÃO EXECUTADO
Data........: 2026-11-06

Objetivo
  Executar EXATAMENTE o corpo da contenção (3990C) dentro de uma transação, com pré-condições,
  postchecks estruturais e o postcheck funcional da 3989 — e desfazer tudo no fim. Prova que a
  alteração é segura antes de autorizar a 3990C.

Resultado esperado
  Dois NOTICEs "Q3990 estrutura: ..." e "Q3990 funcional: ..."; ROLLBACK; a 3990A, reexecutada
  depois, devolve exatamente a linha de base (5 CONFIRMED, preços inalterados).
Falha
  Qualquer EXCEPTION Q3990_* aborta a transação (nada persiste). Não corrigir no improviso.
================================================================
*/
begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

-- Linhas-alvo (identificadores exatos, conferidos na 3990A).
create temp table _q3990_target on commit drop as
select * from (values
  ('63ad9941-d8b2-495f-9260-5fc92f38bceb'::uuid, '004', 'Genesect EX',               'pokemon-me-30th-celebration-classic-collection-charizard-classic-collection'),
  ('1d3f88ea-3706-4763-90aa-70c8c20f668f'::uuid, '005', 'Misty',                     'pokemon-me-30th-celebration-classic-collection-delcatty-classic-collection'),
  ('61c330ab-dd73-4d4c-99e0-1c3ab0af8bbe'::uuid, '018', 'Gengar',                    'pokemon-me-30th-celebration-classic-collection-misty-classic-collection'),
  ('bb3044be-7e6e-4e59-a2f1-98ef938e2740'::uuid, '019', 'Darkrai & Cresselia LENDA', 'pokemon-me-30th-celebration-classic-collection-dark-tyranitar-classic-collection'),
  ('001152c1-b86c-4957-86a0-345fd09f0f4c'::uuid, '025', 'Scizor ex',                 'pokemon-me-30th-celebration-classic-collection-sneasel-classic-collection')
) as t(mapping_id, collector_number, local_name, external_card_id);

-- Fotografia "antes" (comparada nos postchecks).
create temp table _q3990_before on commit drop as
select m.id, m.confirmed_at, m.confirmed_sync_run_id, m.match_method, m.external_card_id, m.external_card_name, m.card_id
from public.pricing_card_mapping m where m.id in (select mapping_id from _q3990_target);

create temp table _q3990_global on commit drop as
select
  (select count(*) from public.pricing_card_mapping where match_status = 'CONFIRMED') confirmed_mappings,
  (select count(*) from public.pricing_card_mapping where match_status = 'REJECTED') rejected_mappings,
  (select count(*) from public.pricing_source_card_identity where match_status = 'CONFIRMED') confirmed_identities,
  (select count(*) from public.pricing_source_card_identity where match_status = 'REJECTED') rejected_identities,
  (select count(*) from public.pricing_product) products,
  (select count(*) from public.pricing_product where is_active) active_products,
  (select count(*) from public.pricing_observation) observations,
  (select count(*) from public.pricing_product p join public.pricing_observation o on o.pricing_product_id = p.id
    where p.pricing_card_mapping_id in (select mapping_id from _q3990_target)) target_observations;

do $$
declare
  v_admin uuid;
  v_n integer;
  v_reason constant text := 'ME5.5CC WRONG LINK CONTAINMENT-01 (Query 3990): número original da reimpressão JustTCG (ex.: 4/102) casado com a numeração local 001–030; nome e total divergentes. Vínculo comprovadamente incorreto; histórico preservado.';
begin
  -- ---------------- Pré-condições (qualquer falha aborta sem escrita) ----------------
  select count(*) into v_n from public.admin_user;
  if v_n <> 1 then raise exception 'Q3990_PRE_ADMIN_NOT_UNIQUE: % administradores', v_n; end if;
  select id into v_admin from public.admin_user;

  select count(*) into v_n
  from _q3990_target t
  join public.pricing_card_mapping m on m.id = t.mapping_id
  join public.card c on c.id = m.card_id and c.collector_number = t.collector_number and c.name = t.local_name
  join public.card_set cs on cs.id = c.card_set_id and cs.code = 'ME5.5CC'
  where m.match_status = 'CONFIRMED' and m.external_card_id = t.external_card_id
    and m.confirmed_by is null and m.confirmed_sync_run_id is not null;
  if v_n <> 5 then raise exception 'Q3990_PRE_TARGETS_CHANGED: % de 5 vínculos no estado esperado', v_n; end if;

  -- Produtos e observações exclusivos dos 5 vínculos (nenhum compartilhado com outra carta).
  select count(*) into v_n from public.pricing_product p
  join public.pricing_product q on q.external_product_id = p.external_product_id and q.id <> p.id
  where p.pricing_card_mapping_id in (select mapping_id from _q3990_target);
  if v_n <> 0 then raise exception 'Q3990_PRE_SHARED_PRODUCT: % produto(s) compartilhado(s)', v_n; end if;

  select count(*) into v_n from public.pricing_card_mapping o
  where o.external_card_id in (select external_card_id from _q3990_target) and o.id not in (select mapping_id from _q3990_target);
  if v_n <> 0 then raise exception 'Q3990_PRE_EXTERNAL_REUSED: % outro(s) vínculo(s) com o mesmo external_card_id', v_n; end if;

  select count(*) into v_n from public.pricing_manual_price mp
  where mp.card_id in (select card_id from _q3990_before);
  if v_n <> 0 then raise exception 'Q3990_PRE_MANUAL_PRICE: % preço(s) manual(is) — fallback manteria valor', v_n; end if;

  -- ---------------- Contenção (uma única alteração de estado) ----------------
  -- CONFIRMED -> REJECTED: a 3989, a 3972 (fallback), o snapshot e os relatórios admin exigem
  -- pcm.match_status = 'CONFIRMED'. confirmed_at é preservado pelo trigger de autoridade; o CHECK
  -- de REJECTED exige confirmed_by (decisão humana) e confirmed_sync_run_id nulo — o run original
  -- fica guardado na evidência e no log (rastreabilidade). Produtos, identidades e observações
  -- não são tocados.
  update public.pricing_card_mapping m set
    match_status = 'REJECTED',
    confirmed_by = v_admin,
    confirmed_sync_run_id = null,
    match_evidence = m.match_evidence || jsonb_build_object('containment_3990', jsonb_build_object(
      'reason', v_reason,
      'previous_status', 'CONFIRMED',
      'previous_match_method', m.match_method,
      'previous_confirmed_sync_run_id', m.confirmed_sync_run_id,
      'previous_confirmed_at', m.confirmed_at,
      'decided_at', now()))
  where m.id in (select mapping_id from _q3990_target) and m.match_status = 'CONFIRMED';
  get diagnostics v_n = row_count;
  if v_n <> 5 then raise exception 'Q3990_APPLY_ROWCOUNT: % de 5', v_n; end if;

  insert into public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  select v_admin, 'PRICING_MAPPING_REJECTED', 'PRICING_CARD_MAPPING', b.id,
         jsonb_build_object('old_status', 'CONFIRMED', 'new_status', 'REJECTED', 'reason', v_reason, 'query', '3990',
                            'previous_confirmed_sync_run_id', b.confirmed_sync_run_id, 'external_card_id', b.external_card_id,
                            'external_card_name', b.external_card_name)
  from _q3990_before b;
  get diagnostics v_n = row_count;
  if v_n <> 5 then raise exception 'Q3990_LOG_ROWCOUNT: % de 5', v_n; end if;

  -- ---------------- Postchecks (estrutura) ----------------
  select count(*) into v_n from public.pricing_card_mapping m join _q3990_before b on b.id = m.id
  where m.match_status = 'REJECTED' and m.confirmed_at = b.confirmed_at and m.confirmed_by = v_admin
    and m.confirmed_sync_run_id is null and m.external_card_id = b.external_card_id
    and (m.match_evidence -> 'containment_3990' ->> 'previous_confirmed_sync_run_id')::uuid = b.confirmed_sync_run_id;
  if v_n <> 5 then raise exception 'Q3990_POST_MAPPING_STATE: % de 5', v_n; end if;

  select count(*) into v_n from public.pricing_card_mapping m
  where m.updated_at = now() and m.id not in (select mapping_id from _q3990_target);
  if v_n <> 0 then raise exception 'Q3990_POST_OTHER_MAPPINGS_TOUCHED: %', v_n; end if;

  perform 1 from _q3990_global g where
    g.confirmed_mappings - 5 = (select count(*) from public.pricing_card_mapping where match_status = 'CONFIRMED')
    and g.rejected_mappings + 5 = (select count(*) from public.pricing_card_mapping where match_status = 'REJECTED')
    and g.confirmed_identities = (select count(*) from public.pricing_source_card_identity where match_status = 'CONFIRMED')
    and g.rejected_identities = (select count(*) from public.pricing_source_card_identity where match_status = 'REJECTED')
    and g.products = (select count(*) from public.pricing_product)
    and g.active_products = (select count(*) from public.pricing_product where is_active)
    and g.observations = (select count(*) from public.pricing_observation)
    and g.target_observations = (select count(*) from public.pricing_product p join public.pricing_observation o on o.pricing_product_id = p.id
                                  where p.pricing_card_mapping_id in (select mapping_id from _q3990_target));
  if not found then raise exception 'Q3990_POST_GLOBAL_COUNTS: contagens divergentes (só 5 vínculos podem mudar; nenhuma observação perdida)'; end if;

  raise notice 'Q3990 estrutura: 5 vínculos REJECTED, 5 registros de auditoria, identidades/produtos/observações intactos.';
end $$;

-- ---------------- Postcheck funcional: 3989 como o titular ----------------
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.admin_user limit 1), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare
  v_priced integer;
  v_control integer;
begin
  -- As 5 cartas ficam sem cotação (nunca zero, sem fallback).
  select count(*) filter (where s.has_pricing or s.brl_amount is not null or s.price_basis is not null) into v_priced
  from public.card_variant cv
  join public.card c on c.id = cv.card_id
  join public.card_set cs on cs.id = c.card_set_id and cs.code = 'ME5.5CC'
  cross join lateral public.get_card_variants_pricing_summary(array[cv.id]) s
  where c.collector_number in ('004', '005', '018', '019', '025');
  if v_priced <> 0 then raise exception 'Q3990_POST_3989_STILL_PRICED: % variante(s) ainda com preço', v_priced; end if;

  -- Controle: Haunter MEP 027 (vínculo correto) continua cotado pela própria variante.
  select count(*) into v_control
  from public.get_card_variants_pricing_summary(array['499f1580-0ba9-4ddb-8e8b-e1480751e8a2'::uuid]) s
  where s.has_pricing and s.price_basis = 'VARIANT' and s.brl_amount > 0;
  if v_control <> 1 then raise exception 'Q3990_POST_CONTROL_LOST: Haunter MEP 027 sem preço'; end if;

  raise notice 'Q3990 funcional: 5 variantes sem cotação na 3989; controle preservado.';
end $$;

reset role;

rollback;
