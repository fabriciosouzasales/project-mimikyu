/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5880A - v1.2 | Equivalência funcional em casos sintéticos (escrita transacional + ROLLBACK)
Versão......: 1.2
Status......: PLANO — NÃO EXECUTADO (R1-B 5880A v1.2 FIXTURE CORRECTION, 2026-11-06).

v1.2 — muda SOMENTE a descoberta/validação do fixture. A v1.1 exigia uma variante com 2
produtos elegíveis E observação NM/MARKET real nos dois: não existe nenhuma no LIVE (34.481
variantes têm ≥ 2 produtos elegíveis PRIMARY; 0 têm observação nos dois) e a varredura
estourava 30 s (57014, execução de 2026-11-06 interrompida antes de qualquer escrita).
Critério v1.2: ≥ 2 produtos elegíveis PRIMARY; ≥ 1 observação NM/MARKET real utilizável em
um dos 2 produtos usados (os 2 menores ids, como na v1.1); os demais cenários usam as
observações sintéticas. Candidatas = lista FIXA e ordenada (verificada no LIVE em 2026-11-06),
REVALIDADA aqui, por índice, antes de qualquer escrita; a primeira que passar é usada.
Nenhuma candidata válida → TR_FIXTURE antes de qualquer escrita (comportamento da v1.1).
Autor.......: Fabrício Sales / Claude

Rastreabilidade com o 5880 v1.0: corpo IDÊNTICO às checagens 2.1, 2.2, 2.3, 6.1, 6.2, 5.1, 5.2,
4.1 e 3.1 (linhas 285–408 do v1.0, copiadas sem alteração), mais a referência pg_temp da 3983
(byte a byte, md5 conferido = 0.1) e o diff multiconjunto. Ficam FORA (já cobertos por 5880B/C/E):
0.2/0.3/7.x (5880C), 1.1/8.1 (5880B), 9.1 (5880E), 10.1 (5880D + fingerprint aqui).

Escritas que ocorrem (todas dentro de UMA transação, desfeitas duas vezes: sentinela TR000 no
subbloco + ROLLBACK final):
  - CREATE FUNCTION pg_temp.* (3 funções temporárias da sessão)
  - INSERT pricing_observation: 8 linhas sintéticas (market_label 'H5880-%'; 2 com ids fixos
    00000000-0000-4000-8000-00000000580[01]) nos 2 produtos elegíveis de menor id de UMA
    variante real da lista fixa de candidatas — datas após a última observação real
  - UPDATE pricing_product SET is_active = false em 1 produto (6.2) — dispara os triggers da
    tabela (updated_at, guard, validate, link); tudo desfeito
Impacto: bloqueio de linha em 1 pricing_product e índices de pricing_observation por poucos
segundos; o cron justtcg-price-refresh pode esperar esse tempo se tocar o mesmo produto.
Nenhum COMMIT. statement_timeout local 30 s (abaixo do conector; não altera papel nem banco).
Saída: uma linha por checagem (PASS/FAIL), checagem 0.1 (referência byte a byte), FP (fingerprint
de Pricing/variantes/acervo igual antes e depois do subbloco) e GATE (esperado 11/11).
================================================================
*/
begin;
set local statement_timeout = '30s';

create or replace function pg_temp.ref_3983_get_card_variants_pricing_summary(p_card_variant_ids uuid[])
returns table (
  card_variant_id uuid,
  card_id uuid,
  has_pricing boolean,
  brl_amount numeric,
  source_amount numeric,
  source_currency text,
  fx_status text,
  printing_label text,
  price_basis text,
  price_origin text,
  observed_at timestamptz
)
language plpgsql
stable security definer
set search_path to ''
as $function$
DECLARE
  v_raw_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'VARIANT_PRICING_SUMMARY_REQUIRES_AUTHENTICATION' USING ERRCODE = '28000';
  END IF;
  IF p_card_variant_ids IS NULL THEN
    RAISE EXCEPTION 'VARIANT_PRICING_SUMMARY_EMPTY_INPUT' USING ERRCODE = '22023';
  END IF;
  v_raw_count := cardinality(p_card_variant_ids);
  IF v_raw_count = 0 THEN
    RAISE EXCEPTION 'VARIANT_PRICING_SUMMARY_EMPTY_INPUT' USING ERRCODE = '22023';
  END IF;
  IF array_ndims(p_card_variant_ids) <> 1 THEN
    RAISE EXCEPTION 'VARIANT_PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE' USING ERRCODE = '22023';
  END IF;
  IF v_raw_count > 100 THEN
    RAISE EXCEPTION 'VARIANT_PRICING_SUMMARY_TOO_MANY_IDS' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH v AS (
    SELECT cv.id AS card_variant_id, cv.card_id, c.price, c.currency_code, c.source_printing_label, c.observed_at,
           (c.price IS NOT NULL AND (c.currency_code = 'BRL' OR fx.rate IS NOT NULL)) AS usable,
           CASE WHEN c.currency_code = 'BRL' THEN c.price
                WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) END AS brl
      FROM (SELECT DISTINCT x FROM unnest(p_card_variant_ids) AS x) i
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
    CASE WHEN v.usable THEN TRUE ELSE COALESCE(fb.has_pricing, FALSE) END,
    CASE WHEN v.usable THEN v.brl ELSE fb.brl_amount END,
    CASE WHEN v.usable THEN v.price END,
    CASE WHEN v.usable THEN v.currency_code END,
    CASE WHEN v.usable THEN 'CONVERTED'
         WHEN fb.fx_status IS NOT NULL THEN fb.fx_status
         WHEN v.price IS NOT NULL THEN 'FX_RATE_UNAVAILABLE' END,
    CASE WHEN v.usable THEN v.source_printing_label ELSE fb.printing_label END,
    CASE WHEN v.usable THEN 'VARIANT' WHEN fb.has_pricing THEN 'CARD_FALLBACK' END,
    CASE WHEN v.usable THEN 'AUTOMATIC' ELSE fb.price_origin END,
    CASE WHEN v.usable THEN v.observed_at END
  FROM v
  LEFT JOIN fb ON fb.card_id = v.card_id;
END;
$function$;

-- Diferença linha a linha (todas as colunas, multiconjunto) entre referência e 3989.
create or replace function pg_temp.h5880_diff(p_ids uuid[])
returns integer
language sql
volatile
as $$
  select count(*)::integer from (
    (select * from pg_temp.ref_3983_get_card_variants_pricing_summary(p_ids)
     except all
     select * from public.get_card_variants_pricing_summary(p_ids))
    union all
    (select * from public.get_card_variants_pricing_summary(p_ids)
     except all
     select * from pg_temp.ref_3983_get_card_variants_pricing_summary(p_ids))
  ) d
$$;

-- Somas de controle (Pricing, catálogo de variantes e acervo).
create or replace function pg_temp.h5880_fingerprint()
returns text
language sql
stable
as $$
  select concat_ws('|',
    (select count(*)::text || ':' || coalesce(sum(price)::text, '') || ':' || coalesce(max(created_at)::text, '') from public.pricing_observation),
    (select count(*)::text || ':' || count(*) filter (where is_active)::text || ':' || coalesce(sum(hashtext(id::text || is_active::text || coalesce(card_variant_id::text, '')))::text, '') from public.pricing_product),
    (select count(*)::text || ':' || coalesce(sum(rate)::text, '') from public.pricing_fx_rate),
    (select count(*)::text || ':' || coalesce(sum(hashtext(id::text || match_status))::text, '') from public.pricing_card_mapping),
    (select count(*)::text from public.pricing_source_card_identity),
    (select count(*)::text from public.card_variant),
    (select count(*)::text from public.card_condition),
    (select count(*)::text from public.physical_card))
$$;

create or replace function pg_temp.tr_5880a_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_ref     oid := to_regprocedure('pg_temp.ref_3983_get_card_variants_pricing_summary(uuid[])');
  p_user_a  uuid := gen_random_uuid();
  v_fp0     text;
  v_nm      uuid;
  v_lp      uuid;
  v_vm      uuid;
  v_prods   uuid[];
  v_p1      uuid;
  v_p2      uuid;
  v_vmiss   uuid;
  v_cand    uuid;
  v_t       timestamptz;
  v_c       timestamptz := now();
  v_rate    numeric;
  v_ids     uuid[];
  v_d       integer;
  v_n       integer;
  r_new     record;
  r_ref     record;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  v_fp0 := pg_temp.h5880_fingerprint();
  res := res || jsonb_build_object('id','0.1','ok',
    (select md5(prosrc) from pg_catalog.pg_proc where oid = v_ref) = 'de9088a98c8e09a8b65180286a50547e',
    'detail','referência pg_temp = corpo exato da 3983 (md5)');
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);

  select cc.id into v_nm from public.card_condition cc where cc.code = 'NM';
  select cc.id into v_lp from public.card_condition cc where cc.code = 'LP';

  -- Fixtures (desfeitas pela sentinela TR000)
  begin
    -- v1.2: variante de teste = 1ª candidata da lista fixa que, revalidada agora, tem ≥ 2 produtos
    -- elegíveis (ativo, mapping CONFIRMED da mesma carta, fonte ativa, identidade PRIMARY CONFIRMED)
    -- e ≥ 1 observação NM/MARKET real utilizável (BRL, ou USD com PTAX ≤ data) em um dos 2 produtos
    -- usados (v_prods[1:2]). Sem varredura do catálogo: só os ids da lista, por índice.
    for v_cand in
      select c.id from unnest(array[
        '00310f13-a9ee-48b6-adad-d97157e6dad7',
        '00cd0a28-d9be-4115-b496-9b255930bc32',
        '0178ff7d-8e17-4ee9-884d-17cae0a91c8d'
      ]::uuid[]) with ordinality as c(id, ord) order by c.ord
    loop
      select array_agg(pp.id order by pp.id) into v_prods
        from public.pricing_product pp
        join public.card_variant cv on cv.id = pp.card_variant_id
        join public.pricing_card_mapping pcm
          on pcm.id = pp.pricing_card_mapping_id and pcm.match_status = 'CONFIRMED' and pcm.card_id = cv.card_id
        join public.pricing_source ps on ps.id = pcm.pricing_source_id and ps.is_active
        join public.pricing_source_card_identity psci
          on psci.id = pp.pricing_source_card_identity_id and psci.identity_role = 'PRIMARY' and psci.match_status = 'CONFIRMED'
       where pp.card_variant_id = v_cand and pp.is_active;
      if coalesce(cardinality(v_prods), 0) >= 2
         and exists (select 1 from public.pricing_observation po
                      where po.pricing_product_id = any(v_prods[1:2])
                        and po.condition_id = v_nm and po.price_type = 'MARKET'
                        and (po.currency_code = 'BRL'
                             or (po.currency_code = 'USD' and exists (
                                   select 1 from public.pricing_fx_rate r
                                    where r.from_currency = 'USD' and r.to_currency = 'BRL' and r.rate_source_code = 'BCB_PTAX'
                                      and r.rate_date <= (po.observed_at at time zone 'UTC')::date)))) then
        v_vm := v_cand;
        exit;
      end if;
      v_prods := null;
    end loop;
    -- v1.2: variante sem preço = 1ª candidata da lista fixa que, revalidada agora, existe, não tem
    -- produto e cuja carta não tem mapping (mesmo critério da v1.1, sem varrer card_variant).
    for v_cand in
      select c.id from unnest(array[
        '00fb88b7-4f39-4456-91c2-86a1116eb2e0',
        '01f91254-e168-4261-8a23-5ef7b3346b1a',
        '09774ed3-8bec-4bdb-ac10-2e0895b821e6'
      ]::uuid[]) with ordinality as c(id, ord) order by c.ord
    loop
      if exists (select 1 from public.card_variant cv where cv.id = v_cand)
         and not exists (select 1 from public.pricing_product pp where pp.card_variant_id = v_cand)
         and not exists (select 1 from public.card_variant cv
                           join public.pricing_card_mapping pcm on pcm.card_id = cv.card_id
                          where cv.id = v_cand) then
        v_vmiss := v_cand;
        exit;
      end if;
    end loop;
    if v_vm is null or v_vmiss is null or v_nm is null or v_lp is null then
      raise exception 'TR_FIXTURE: sem variante com 2 produtos elegíveis, variante sem preço ou condições NM/LP';
    end if;
    v_p1 := v_prods[1];
    v_p2 := v_prods[2];
    -- Base: depois de todas as observações dos produtos da variante.
    select max(po.observed_at) + interval '1 day' into v_t
      from public.pricing_observation po
      join public.pricing_product pp on pp.id = po.pricing_product_id
     where pp.card_variant_id = v_vm;
    v_ids := array[v_vm];

    -- 2.1 vários produtos/observações (estado real da variante)
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','2.1','ok', v_d = 0 and r_new.price_basis = 'VARIANT',
      'detail', format('variante com %s produtos elegíveis; divergências %s; base %s', cardinality(v_prods), v_d, r_new.price_basis));

    -- 2.2 empate de observed_at: created_at mais novo vence (P2)
    insert into public.pricing_observation (pricing_product_id, condition_id, price_type, price, currency_code, market_label, observed_at, created_at)
    values (v_p1, v_nm, 'MARKET', 101.11, 'USD', 'H5880-22a', v_t, v_c),
           (v_p2, v_nm, 'MARKET', 202.22, 'USD', 'H5880-22b', v_t, v_c + interval '1 second');
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','2.2','ok', v_d = 0 and r_new.source_amount = 202.22,
      'detail', format('mesmo observed_at, created_at desempata; escolhido %s (esperado 202.22); divergências %s', r_new.source_amount, v_d));

    -- 2.3 empate de observed_at e created_at: id maior vence
    insert into public.pricing_observation (id, pricing_product_id, condition_id, price_type, price, currency_code, market_label, observed_at, created_at)
    values ('00000000-0000-4000-8000-000000005801', v_p1, v_nm, 'MARKET', 404.44, 'USD', 'H5880-23a', v_t + interval '1 hour', v_c),
           ('00000000-0000-4000-8000-000000005800', v_p2, v_nm, 'MARKET', 303.33, 'USD', 'H5880-23b', v_t + interval '1 hour', v_c);
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','2.3','ok', v_d = 0 and r_new.source_amount = 404.44,
      'detail', format('mesmo observed_at e created_at, id desempata; escolhido %s (esperado 404.44); divergências %s', r_new.source_amount, v_d));

    -- 6.1 observações mais novas, porém inelegíveis (LP; LOW)
    insert into public.pricing_observation (pricing_product_id, condition_id, price_type, price, currency_code, market_label, observed_at, created_at)
    values (v_p1, v_lp, 'MARKET', 999.99, 'USD', 'H5880-61a', v_t + interval '2 hours', v_c),
           (v_p2, v_nm, 'LOW',    998.98, 'USD', 'H5880-61b', v_t + interval '2 hours', v_c);
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','6.1','ok', v_d = 0 and r_new.source_amount = 404.44,
      'detail', format('LP e LOW mais novas ignoradas; escolhido %s (esperado 404.44); divergências %s', r_new.source_amount, v_d));

    -- 6.2 produto inativo: o vencedor (P1) sai; vence a melhor observação de P2
    update public.pricing_product set is_active = false where id = v_p1;
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','6.2','ok', v_d = 0 and r_new.source_amount = 303.33,
      'detail', format('P1 inativo; escolhido %s (esperado 303.33, P2); divergências %s', r_new.source_amount, v_d));

    -- 5.1 USD → BRL pela PTAX da data (≤) da observação vencedora
    select fx.rate into v_rate from public.pricing_fx_rate fx
     where fx.from_currency = 'USD' and fx.to_currency = 'BRL' and fx.rate_source_code = 'BCB_PTAX'
       and fx.rate_date <= ((v_t + interval '1 hour') at time zone 'UTC')::date
     order by fx.rate_date desc limit 1;
    res := res || jsonb_build_object('id','5.1','ok',
      v_d = 0 and v_rate is not null and r_new.brl_amount = round(303.33 * v_rate, 2)
        and r_new.fx_status = 'CONVERTED' and r_new.source_currency = 'USD',
      'detail', format('303.33 USD × PTAX %s = %s (função: %s, %s)', v_rate, round(303.33 * v_rate, 2), r_new.brl_amount, r_new.fx_status));

    -- 5.2 observação em BRL, mais nova, no produto ativo
    insert into public.pricing_observation (pricing_product_id, condition_id, price_type, price, currency_code, market_label, observed_at, created_at)
    values (v_p2, v_nm, 'MARKET', 55.55, 'BRL', 'H5880-52', v_t + interval '3 hours', v_c);
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','5.2','ok', v_d = 0 and r_new.brl_amount = 55.55 and r_new.source_currency = 'BRL',
      'detail', format('BRL sem conversão: %s %s; divergências %s', r_new.brl_amount, r_new.source_currency, v_d));

    -- 4.1 moeda sem câmbio → fallback por carta
    insert into public.pricing_observation (pricing_product_id, condition_id, price_type, price, currency_code, market_label, observed_at, created_at)
    values (v_p2, v_nm, 'MARKET', 10.00, 'EUR', 'H5880-41', v_t + interval '4 hours', v_c);
    v_d := pg_temp.h5880_diff(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(v_ids);
    select * into r_ref from pg_temp.ref_3983_get_card_variants_pricing_summary(v_ids);
    res := res || jsonb_build_object('id','4.1','ok', v_d = 0 and r_new.price_basis is distinct from 'VARIANT'
        and r_new.price_basis is not distinct from r_ref.price_basis,
      'detail', format('EUR sem PTAX → base %s, fx %s (referência: %s, %s); divergências %s',
        coalesce(r_new.price_basis, 'nenhuma'), r_new.fx_status, coalesce(r_ref.price_basis, 'nenhuma'), r_ref.fx_status, v_d));

    -- 3.1 preço ausente, id inexistente e id repetido
    v_ids := array[v_vmiss, gen_random_uuid(), v_vm, v_vm];
    v_d := pg_temp.h5880_diff(v_ids);
    select count(*) into v_n from public.get_card_variants_pricing_summary(v_ids);
    select * into r_new from public.get_card_variants_pricing_summary(array[v_vmiss]);
    res := res || jsonb_build_object('id','3.1','ok', v_d = 0 and v_n = 2 and not r_new.has_pricing and r_new.price_basis is null,
      'detail', format('sem preço: has_pricing %s, base %s; 4 ids (1 inexistente, 1 repetido) → %s linhas (esperado 2); divergências %s',
        r_new.has_pricing, coalesce(r_new.price_basis, 'nula'), v_n, v_d));

    raise exception 'TR000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'TR000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado nas fixtures: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','FP','ok', pg_temp.h5880_fingerprint() = v_fp0,
    'detail','somas de controle de Pricing, variantes e acervo iguais antes e depois do subbloco TR000');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 11 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 11)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5880a_validate();
rollback;
