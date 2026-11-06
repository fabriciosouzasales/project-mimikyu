/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5880B (v1.1) - Comparação 3983 × 3989 em AMOSTRA de variantes reais
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-11-06, fatias 1–6 (R1-B PRICING 3989 VALIDATION RECOVERY-03)
Rastreia....: 5880 v1.0 checagens 1.1 (conjunto real) e 8.1 (equivalência monetária)

Por que v1.1: a 5880 v1.0 rodava tudo num comando só e não cabia nos limites do
conector (2 min). Esta parte compara UMA fatia de no máximo 100 variantes por execução.

Como funciona
  - Transação REPEATABLE READ e SOMENTE LEITURA, ROLLBACK no fim: nenhuma escrita
    (nem função temporária). Um único SELECT calcula referência e 3989, portanto as
    duas leem exatamente a mesma visão dos dados.
  - Referência = o corpo da 3983 (RETURN QUERY, linhas 94–147 do corpo de md5
    de9088a98c8e09a8b65180286a50547e) copiado como consulta, com p_card_variant_ids
    trocado pela lista da fatia. A 3983 também rodava como dona (postgres), igual aqui.
  - Comparação: as 11 colunas, multiconjunto (EXCEPT ALL nos dois sentidos). Os aliases
    de coluna da referência só nomeiam as saídas; a lógica é a da 3983 sem alteração.
  - statement_timeout local de 100 s (ABAIXO do limite do conector; não é aumento).

Fatias (trocar SÓ o número em cfg; uma execução por fatia)
  1  acervo (todas as contas), variantes 1–100 por id
  2  acervo, variantes 601–700
  3  acervo, variantes 1.202–1.301
  4  variantes com ≥ 2 produtos ativos com observação MARKET/NM (100, ordem md5(id))
  5  caminho sem preço/fallback: 50 sem produto + 50 com produto ativo sem MARKET
  6  empates reais: entre TODAS as variantes com ≥ 2 produtos ativos, as que têm o
     observed_at mais recente repetido em 2+ produtos (até 100). Em 2026-11-06: 2 variantes
     (subconjunto da fatia 4; a v1.1 inicial limitava a 3.000 por md5 e voltou vazia → 22023)
  (câmbio indisponível e desempate por id: só nos casos sintéticos, 5880A)

Saída: fatia, ids, linhas ref/3989, divergências, Σ BRL e Σ origem ref/3989,
contagem por base (VARIANT/CARD_FALLBACK/sem preço) e por fx_status. PASS = 0 divergências
e Σ idênticas. Cobre SÓ a fatia — não é prova sobre todos os dados reais.
================================================================
*/
begin isolation level repeatable read read only;
set local statement_timeout = '100s';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000058b1","role":"authenticated"}', true);

with cfg as (select 1::int as chunk),
nm as (select id from public.card_condition where code = 'NM'),
acervo as (select distinct card_variant_id as id from public.physical_card),
sample as (
  (select id from acervo where (select chunk from cfg) = 1 order by id limit 100)
  union all
  (select id from acervo where (select chunk from cfg) = 2 order by id offset 600 limit 100)
  union all
  (select id from acervo where (select chunk from cfg) = 3 order by id offset 1201 limit 100)
  union all
  (select pp.card_variant_id from public.pricing_product pp
    where (select chunk from cfg) = 4 and pp.is_active and pp.card_variant_id is not null
      and exists (select 1 from public.pricing_observation po
                   where po.pricing_product_id = pp.id and po.condition_id = (select id from nm) and po.price_type = 'MARKET')
    group by pp.card_variant_id having count(*) >= 2
    order by md5(pp.card_variant_id::text) limit 100)
  union all
  (select cv.id from public.card_variant cv
    where (select chunk from cfg) = 5
      and not exists (select 1 from public.pricing_product pp where pp.card_variant_id = cv.id)
    order by md5(cv.id::text) limit 50)
  union all
  (select distinct pp.card_variant_id from public.pricing_product pp
    where (select chunk from cfg) = 5 and pp.is_active and pp.card_variant_id is not null
      and not exists (select 1 from public.pricing_observation po where po.pricing_product_id = pp.id and po.price_type = 'MARKET')
    limit 50)
  union all
  (select y.card_variant_id from (
      select t.card_variant_id, t.last_obs, count(*) as c,
             max(t.last_obs) over (partition by t.card_variant_id) as mx
        from (
          select pp.card_variant_id,
                 (select po.observed_at from public.pricing_observation po
                   where po.pricing_product_id = pp.id and po.condition_id = (select id from nm) and po.price_type = 'MARKET'
                   order by po.observed_at desc limit 1) as last_obs
            from public.pricing_product pp
           where (select chunk from cfg) = 6 and pp.is_active
             and pp.card_variant_id in (
               select card_variant_id from public.pricing_product
                where is_active and card_variant_id is not null
                group by card_variant_id having count(*) >= 2)) t
       where t.last_obs is not null
       group by t.card_variant_id, t.last_obs) y
    where y.c >= 2 and y.last_obs = y.mx
    limit 100)
),
p as (select array_agg(distinct id) as a from sample),
-- Referência: corpo da 3983 (RETURN QUERY), p_card_variant_ids → p.a
ref_rows as (
  WITH v AS (
    SELECT cv.id AS card_variant_id, cv.card_id, c.price, c.currency_code, c.source_printing_label, c.observed_at,
           (c.price IS NOT NULL AND (c.currency_code = 'BRL' OR fx.rate IS NOT NULL)) AS usable,
           CASE WHEN c.currency_code = 'BRL' THEN c.price
                WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) END AS brl
      FROM (SELECT DISTINCT x FROM p, unnest(p.a) AS x) i
      JOIN public.card_variant cv ON cv.id = i.x
      LEFT JOIN LATERAL (
        SELECT po.price, po.currency_code, po.observed_at, pp.source_printing_label
          FROM public.pricing_product pp
          JOIN public.pricing_card_mapping pcm
            ON pcm.id = pp.pricing_card_mapping_id AND pcm.match_status = 'CONFIRMED' AND pcm.card_id = cv.card_id
          JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active
          JOIN public.pricing_source_card_identity psci
            ON psci.id = pp.pricing_source_card_identity_id
           AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
          JOIN public.pricing_observation po ON po.pricing_product_id = pp.id AND po.price_type = 'MARKET'
          JOIN public.card_condition cc ON cc.id = po.condition_id AND cc.code = 'NM'
         WHERE pp.card_variant_id = cv.id AND pp.is_active
         ORDER BY po.observed_at DESC, po.created_at DESC, po.id DESC
         LIMIT 1
      ) c ON TRUE
      LEFT JOIN LATERAL (
        SELECT r.rate FROM public.pricing_fx_rate r
         WHERE c.currency_code = 'USD' AND r.from_currency = 'USD' AND r.to_currency = 'BRL'
           AND r.rate_source_code = 'BCB_PTAX'
           AND r.rate_date <= (c.observed_at AT TIME ZONE 'UTC')::date
         ORDER BY r.rate_date DESC LIMIT 1
      ) fx ON TRUE
  ),
  fb_ids AS (
    SELECT array_agg(DISTINCT v.card_id) AS ids FROM v WHERE NOT v.usable
  ),
  fb AS (
    SELECT s.* FROM (SELECT ids FROM fb_ids WHERE ids IS NOT NULL) f
    CROSS JOIN LATERAL public.get_cards_pricing_summary(f.ids) s
  )
  SELECT
    v.card_variant_id,
    v.card_id,
    CASE WHEN v.usable THEN TRUE ELSE COALESCE(fb.has_pricing, FALSE) END AS has_pricing,
    CASE WHEN v.usable THEN v.brl ELSE fb.brl_amount END AS brl_amount,
    CASE WHEN v.usable THEN v.price END AS source_amount,
    CASE WHEN v.usable THEN v.currency_code END AS source_currency,
    CASE WHEN v.usable THEN 'CONVERTED'
         WHEN fb.fx_status IS NOT NULL THEN fb.fx_status
         WHEN v.price IS NOT NULL THEN 'FX_RATE_UNAVAILABLE' END AS fx_status,
    CASE WHEN v.usable THEN v.source_printing_label ELSE fb.printing_label END AS printing_label,
    CASE WHEN v.usable THEN 'VARIANT' WHEN fb.has_pricing THEN 'CARD_FALLBACK' END AS price_basis,
    CASE WHEN v.usable THEN 'AUTOMATIC' ELSE fb.price_origin END AS price_origin,
    CASE WHEN v.usable THEN v.observed_at END AS observed_at
  FROM v
  LEFT JOIN fb ON fb.card_id = v.card_id
),
new_rows as (
  select * from public.get_card_variants_pricing_summary((select a from p))
),
d as (
  select count(*) as n from (
    (select * from ref_rows except all select * from new_rows)
    union all
    (select * from new_rows except all select * from ref_rows)) x
)
select (select chunk from cfg) as fatia,
       (select cardinality(a) from p) as ids,
       (select count(*) from ref_rows) as linhas_ref,
       (select count(*) from new_rows) as linhas_3989,
       (select n from d) as divergencias,
       (select sum(brl_amount) from ref_rows) as soma_brl_ref,
       (select sum(brl_amount) from new_rows) as soma_brl_3989,
       (select sum(source_amount) from ref_rows) as soma_origem_ref,
       (select sum(source_amount) from new_rows) as soma_origem_3989,
       (select format('VARIANT %s / CARD_FALLBACK %s / sem preço %s',
                      count(*) filter (where price_basis = 'VARIANT'),
                      count(*) filter (where price_basis = 'CARD_FALLBACK'),
                      count(*) filter (where not has_pricing)) from new_rows) as bases_3989,
       (select string_agg(fx || ' ' || n, ', ' order by fx) from
          (select coalesce(fx_status, '∅') as fx, count(*) as n from new_rows group by 1) z) as fx_3989,
       case when (select n from d) = 0
             and (select sum(brl_amount) from ref_rows) is not distinct from (select sum(brl_amount) from new_rows)
             and (select sum(source_amount) from ref_rows) is not distinct from (select sum(source_amount) from new_rows)
            then 'PASS' else 'FAIL' end as status;
rollback;
