/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3975 - Backfill pricing_product.card_variant_id (regra 3974)
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-CATALOG-VARIANT-RECONCILIATION-01 (Pricing 80)
Depende.....: 3973, 3974

Executado como admin via RPC (idempotente: só preenche card_variant_id NULL,
grava 1 linha em pricing_admin_action_log). Gate: exatamente o número de
UNIQUE medido no dry-run.

Resultado LIVE (2026-10-10)
  avaliados 50.470 · ligados 48.316 (UNIQUE)
  ficaram sem vínculo 2.154: NO_CANDIDATE 1.939 · UNIQUE_CONTEXT_ONLY 190 ·
  AMBIGUOUS 25. Produtos ligados a variante de outra carta: 0.
  Reexecução: avaliados 2.154, UNIQUE 0 (idempotente).
===============================================================================
*/
DO $a$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','fe316458-49dd-44e1-aac0-f4b7604ef8f2','role','authenticated')::text, true);
  r := public.admin_reconcile_pricing_product_variants(true);
  IF (r->>'applied')::int <> 48316 THEN RAISE EXCEPTION 'G_APPLIED_DIVERGENTE: %', r; END IF;
  RAISE NOTICE 'APPLY_OK %', r;
END $a$;

-- Como validar
SELECT count(*) AS total, count(card_variant_id) AS linked,
       (SELECT count(*) FROM public.pricing_product pp
          JOIN public.card_variant cv ON cv.id = pp.card_variant_id
          JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
         WHERE cv.card_id <> m.card_id) AS wrong_card
  FROM public.pricing_product;
