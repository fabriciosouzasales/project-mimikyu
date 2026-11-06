/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3989 - Preço por variante: get_card_variants_pricing_summary(uuid[])
              otimizada (substitui a DEFINIÇÃO da 3983; assinatura e contrato iguais)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO (R1-B PRICING PERFORMANCE CORRECTION-01, 2026-11-06)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-06

Por que (diagnóstico R1-B INVENTORY PERFORMANCE DIAGNOSIS-01, aprovado)
  O Inventário detalhado por Card Set caía com SQLSTATE 57014 (statement_timeout de
  8 s do papel authenticated) na etapa de preços. Causa comprovada na 3983: para
  achar a observação MARKET/NM mais recente de uma variante, o LATERAL junta TODO o
  histórico de observações de todos os produtos elegíveis e só depois ordena e
  corta (≈ 55 observações/variante; ≈ 100 buffers/variante no acervo real de
  1.301 variantes). O custo cresce a cada sincronização.

O que muda (só isto)
  Dentro do LATERAL de preço por variante, a observação é escolhida POR PRODUTO
  (LIMIT 1 por produto, servido pelo índice existente
  ix_pricing_observation_latest_lookup + Incremental Sort no desempate) e depois a
  melhor entre os produtos. A condição NM é resolvida uma vez no início.
  Equivalência: a chave de ordenação (observed_at DESC, created_at DESC, id DESC)
  é total (id é PK); o máximo de uma união é o máximo dos máximos de cada parte —
  portanto a observação escolhida é a mesma da 3983 em qualquer cenário.
  Prova prévia (somente leitura, 2026-11-06): acervo real de 1.301 variantes,
  0 divergências; buffers do trecho de observações 6.797 → 1.148 por lote de 100.

O que NÃO muda
  Assinatura, colunas e tipos de retorno; validações de entrada e mensagens
  (28000, 22023); SECURITY DEFINER; STABLE; search_path vazio; REVOKE/GRANT
  (EXECUTE só authenticated); filtros de elegibilidade (produto ativo, mapping
  CONFIRMED da mesma carta, fonte ativa, identidade PRIMARY CONFIRMED, MARKET, NM);
  câmbio PTAX (BCB_PTAX, data ≤ observação); fallback por carta
  (get_cards_pricing_summary); preço ausente (has_pricing = false, basis NULL).
  Nenhuma tabela, índice, dado ou regra de Pricing é alterado.

Pré-condição (fail-closed)
  A definição em vigor deve ser EXATAMENTE a da 3983 (md5 do corpo
  de9088a98c8e09a8b65180286a50547e). Se divergir, a migration aborta sem alterar nada.

Validação: Query 5880 (harness, executar DEPOIS desta migration).
Rollback : R3989_restore_3983_get_card_variants_pricing_summary.sql.
===============================================================================
*/
BEGIN;

DO $pre$
DECLARE
  v_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO v_md5
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.oid = to_regprocedure('public.get_card_variants_pricing_summary(uuid[])');
  IF v_md5 IS DISTINCT FROM 'de9088a98c8e09a8b65180286a50547e' THEN
    RAISE EXCEPTION '3989_PRECONDITION: definição em vigor diferente da 3983 (md5 %). Nada alterado.', coalesce(v_md5, 'ausente');
  END IF;
  -- Contrato e ACL em vigor, para o pós-check comparar (mesma transação).
  PERFORM set_config('mmkyu.m3989_result',
    pg_catalog.pg_get_function_result(to_regprocedure('public.get_card_variants_pricing_summary(uuid[])')), true);
  PERFORM set_config('mmkyu.m3989_acl',
    (SELECT coalesce(p.proacl::text, '') FROM pg_catalog.pg_proc p
      WHERE p.oid = to_regprocedure('public.get_card_variants_pricing_summary(uuid[])')), true);
END
$pre$;

CREATE OR REPLACE FUNCTION public.get_card_variants_pricing_summary(p_card_variant_ids uuid[])
RETURNS TABLE (
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
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_raw_count integer;
  v_nm_condition_id uuid;
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

  -- Condição NM resolvida uma vez (card_condition.code é UNIQUE). Ausente → NULL → nenhuma
  -- observação casa, exatamente como o JOIN card_condition cc ON cc.code = 'NM' da 3983.
  SELECT cc.id INTO v_nm_condition_id FROM public.card_condition cc WHERE cc.code = 'NM';

  RETURN QUERY
  WITH v AS (
    SELECT cv.id AS card_variant_id, cv.card_id, c.price, c.currency_code, c.source_printing_label, c.observed_at,
           (c.price IS NOT NULL AND (c.currency_code = 'BRL' OR fx.rate IS NOT NULL)) AS usable,
           CASE WHEN c.currency_code = 'BRL' THEN c.price
                WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) END AS brl
      FROM (SELECT DISTINCT x FROM unnest(p_card_variant_ids) AS x) i
      JOIN public.card_variant cv ON cv.id = i.x
      LEFT JOIN LATERAL (
        -- 3989: a observação elegível mais recente é escolhida POR PRODUTO pelo índice
        -- ix_pricing_observation_latest_lookup (produto, condição, tipo, observed_at DESC),
        -- e só então a melhor entre os produtos elegíveis — mesma chave total
        -- (observed_at, created_at, id) da 3983, sem varrer o histórico.
        SELECT o.price, o.currency_code, o.observed_at, pp.source_printing_label
          FROM public.pricing_product pp
          JOIN public.pricing_card_mapping pcm
            ON pcm.id = pp.pricing_card_mapping_id AND pcm.match_status = 'CONFIRMED' AND pcm.card_id = cv.card_id
          JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active
          JOIN public.pricing_source_card_identity psci
            ON psci.id = pp.pricing_source_card_identity_id
           AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
          CROSS JOIN LATERAL (
            SELECT po.price, po.currency_code, po.observed_at, po.created_at, po.id
              FROM public.pricing_observation po
             WHERE po.pricing_product_id = pp.id
               AND po.condition_id = v_nm_condition_id
               AND po.price_type = 'MARKET'
             ORDER BY po.observed_at DESC, po.created_at DESC, po.id DESC
             LIMIT 1
          ) o
         WHERE pp.card_variant_id = cv.id AND pp.is_active
         ORDER BY o.observed_at DESC, o.created_at DESC, o.id DESC
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

REVOKE ALL ON FUNCTION public.get_card_variants_pricing_summary(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_card_variants_pricing_summary(uuid[]) TO authenticated;
COMMENT ON FUNCTION public.get_card_variants_pricing_summary(uuid[]) IS
  'Preço por Card Variant (3983, otimizada pela 3989): VARIANT (produto ligado à variante) ou CARD_FALLBACK (resumo da carta). Base da avaliação de Collection.';

DO $post$
DECLARE
  r record;
BEGIN
  SELECT md5(p.prosrc) AS body, p.prosecdef, p.provolatile, p.proconfig,
         pg_catalog.pg_get_function_result(p.oid) AS result,
         coalesce(p.proacl::text, '') AS acl,
         has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
    INTO r
    FROM pg_catalog.pg_proc p
   WHERE p.oid = to_regprocedure('public.get_card_variants_pricing_summary(uuid[])');
  IF r.body IS DISTINCT FROM 'e253fcc5613bbef1181c6564b56f5b8a'
     OR NOT r.prosecdef OR r.provolatile <> 's'
     OR r.proconfig IS DISTINCT FROM ARRAY['search_path=""']
     OR r.anon_exec OR NOT r.auth_exec
     OR r.result IS DISTINCT FROM current_setting('mmkyu.m3989_result', true)
     OR r.acl IS DISTINCT FROM current_setting('mmkyu.m3989_acl', true) THEN
    RAISE EXCEPTION '3989_POSTCHECK: definição, segurança ou contrato inesperados (%)', row_to_json(r);
  END IF;
END
$post$;

COMMIT;
