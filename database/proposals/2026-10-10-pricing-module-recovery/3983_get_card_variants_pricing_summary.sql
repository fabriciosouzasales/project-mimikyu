/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3983 - Preço por variante: get_card_variants_pricing_summary(uuid[])
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 4 (preço por variante chegando ao produto)

Objetivo
  Contrato de leitura por Card Variant — base da avaliação de Collection (Physical
  Card referencia card_variant_id). Mesmo modelo de segurança e de payload do
  get_cards_pricing_summary (3904/3918/3968/3972): SECURITY DEFINER, search_path
  vazio, exige auth.uid(), até 100 ids, array 1-D, sem expor ids externos.

Regra
  1. VARIANT — observação MARKET/NM mais recente de produto ATIVO ligado à própria
     variante (pricing_product.card_variant_id, Pricing 80), com mapping de carta e
     identidade PRIMARY CONFIRMED e fonte ativa. Empate de produtos da mesma variante:
     observação mais recente vence.
  2. CARD_FALLBACK — sem preço da variante (produto não ligado, catálogo sem a variante
     na fonte, câmbio ausente): usa o resumo da carta (get_cards_pricing_summary:
     hierarquia de printing + fallback manual). price_basis deixa explícito.
  3. Nada encontrado — has_pricing=false, price_basis NULL.
  Conversão BRL: PTAX venda (BCB_PTAX) da data da observação ou anterior.
===============================================================================
*/
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

REVOKE ALL ON FUNCTION public.get_card_variants_pricing_summary(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_card_variants_pricing_summary(uuid[]) TO authenticated;
COMMENT ON FUNCTION public.get_card_variants_pricing_summary(uuid[]) IS
  'Preço por Card Variant (3983): VARIANT (produto ligado à variante) ou CARD_FALLBACK (resumo da carta). Base da avaliação de Collection.';
