/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3986 - Pricing 80: famílias reverse/holo no fallback + impressão única
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE qjfutqujxrbzgrtkpgkg, após dry-run
              abortado de propósito; reconciliação aplicada: 1.626 produtos ligados, carta errada 0)
Frente......: PRICING-CATALOG-VARIANT-RECONCILIATION-01 (Pricing 80), remedição 2026-10-11
Depende.....: 3974, 3977, 3985
Mandato.....: Fabrício, 2026-10-11: "As três" (R1, R2, R3); fila residual "documentada, não bloqueia".

Remedição (LIVE, 2026-10-11): 2.342 produtos sem variante (NO_CANDIDATE 2.289, UNIQUE_CONTEXT_ONLY 28,
AMBIGUOUS 25), todos com observação de preço.

Regras (só produto SEM qualificador, só quando as regras anteriores não acharam candidata,
só grava com exatamente 1 candidata; nunca sobrescreve vínculo existente):
  R1  "Reverse Holofoil" aceita a família reverse (ENERGY_REVERSE, COSMOS_REVERSE, TINSEL_REVERSE,
      *_BALL_REVERSE, ROCKET_REVERSE…) — dado em pricing_source_printing_finish_fallback.
      Ex.: EX5/EX6 (Energy Reverse), SVE (Tinsel Reverse), BOG (Cosmos Reverse).
  R2  "Holofoil"/"Unlimited Holofoil" passam a aceitar também CRACKED_ICE_HOLO, TINSEL_HOLO,
      GALAXY_HOLO e MASTER_BALL_HOLO — mesmo mecanismo da 3977 (dado).
  R3  Impressão única (código, resolução UNIQUE_SINGLE_PRINTING): rótulo sem Printing, a identidade
      da fonte tem um único rótulo de impressão e a carta tem uma única Card Variant (base ou
      UNLIMITED, com ou sem Edition Context). Ex.: SMP (fonte "Holofoil", catálogo STANDARD),
      ME5.5 (fonte "Holofoil", catálogo STANDARD 30th), 2022SWSH, RU1, Alph Lithograph.
      Limite conhecido: se a fonte acrescentar depois um segundo rótulo à mesma identidade, os
      produtos já ligados permanecem (o vínculo nunca é sobrescrito) e os novos seguem a regra
      normal.

Aceita por admin_reconcile_pricing_product_variants (log rule 3974+3977+3985+3986) e pelo
trigger de inserção. Dry-run da simulação: R1 671 · R2 80 · R3 875 produtos.
===============================================================================
*/

-- R1 + R2: vocabulário de fallback (dado)
INSERT INTO public.pricing_source_printing_finish_fallback (printing_mapping_id, card_variant_type_id)
SELECT pm.id, t.id
  FROM public.pricing_source_printing_mapping pm
  JOIN public.pricing_source s ON s.id = pm.pricing_source_id AND s.code = 'JUSTTCG'
  JOIN public.card_variant_type t ON t.code LIKE '%REVERSE%' AND t.code <> 'REVERSE_HOLO'
 WHERE pm.source_printing_label = 'Reverse Holofoil'
ON CONFLICT DO NOTHING;

INSERT INTO public.pricing_source_printing_finish_fallback (printing_mapping_id, card_variant_type_id)
SELECT pm.id, t.id
  FROM public.pricing_source_printing_mapping pm
  JOIN public.pricing_source s ON s.id = pm.pricing_source_id AND s.code = 'JUSTTCG'
  JOIN public.card_variant_type t ON t.code IN ('CRACKED_ICE_HOLO','TINSEL_HOLO','GALAXY_HOLO','MASTER_BALL_HOLO')
 WHERE pm.source_printing_label IN ('Holofoil','Unlimited Holofoil')
ON CONFLICT DO NOTHING;

-- R3: resolver (corpo da 3985 + estágio sp)
CREATE OR REPLACE FUNCTION internal.resolve_pricing_product_card_variant(p_product_ids uuid[])
RETURNS TABLE (pricing_product_id uuid, resolution text, card_variant_id uuid, candidate_count int)
LANGUAGE sql STABLE
SET search_path = ''
AS $f$
  WITH p AS (
    SELECT pp.id, m.card_id, m.pricing_source_id, pp.pricing_source_card_identity_id AS identity_id,
           i.external_variant_key AS k, pp.source_printing_label AS lbl
      FROM public.pricing_product pp
      JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
      LEFT JOIN public.pricing_source_card_identity i ON i.id = pp.pricing_source_card_identity_id
     WHERE pp.id = ANY (p_product_ids)
  ), r AS (
    SELECT p.*, pm.id AS pm_id, pm.card_variant_type_id AS lbl_type, pm.printing_profile_id AS pprof,
           pm.fallback_printing_profile_id AS fb_pprof,
           q.id AS q_id, q.catalog_finish_type_id AS q_type, q.edition_context_trait_id AS q_trait
      FROM p
      LEFT JOIN public.pricing_source_printing_mapping pm
             ON pm.pricing_source_id = p.pricing_source_id AND pm.source_printing_label = p.lbl
      LEFT JOIN public.pricing_source_variant_mapping q
             ON q.pricing_source_id = p.pricing_source_id AND q.external_variant_key = p.k
  ), c AS (
    SELECT r.id, cv.id AS cv_id,
           (SELECT count(*) FROM public.card_edition_context_profile_trait t
             WHERE t.profile_id = cv.edition_context_profile_id) AS ntraits
      FROM r
      JOIN public.card_variant cv
        ON cv.card_id = r.card_id
       AND cv.variant_type_id = COALESCE(r.q_type, r.lbl_type)
       AND cv.printing_profile_id IS NOT DISTINCT FROM r.pprof
     WHERE r.identity_id IS NOT NULL AND r.pm_id IS NOT NULL AND (r.k IS NULL OR r.q_id IS NOT NULL)
       AND (r.q_trait IS NULL OR EXISTS (
             SELECT 1 FROM public.card_edition_context_profile_trait t
              WHERE t.profile_id = cv.edition_context_profile_id AND t.trait_id = r.q_trait))
  ), best AS (
    SELECT x.id, count(*) AS n, min(x.cv_id::text)::uuid AS cv, min(x.ntraits) AS ntraits
      FROM (SELECT c.*, min(c.ntraits) OVER (PARTITION BY c.id) AS mn FROM c) x
     WHERE x.ntraits = x.mn
     GROUP BY x.id
  ), fb AS (
    -- 3977: fallback só para produto sem qualificador e sem candidata na regra principal
    SELECT r.id, count(*) AS n, min(cv.id::text)::uuid AS cv
      FROM r
      JOIN public.card_variant cv
        ON cv.card_id = r.card_id AND cv.edition_context_profile_id IS NULL
     WHERE r.identity_id IS NOT NULL AND r.pm_id IS NOT NULL AND r.k IS NULL
       AND NOT EXISTS (SELECT 1 FROM best b WHERE b.id = r.id)
       AND (cv.variant_type_id = r.lbl_type
            OR cv.variant_type_id IN (SELECT f.card_variant_type_id FROM public.pricing_source_printing_finish_fallback f
                                       WHERE f.printing_mapping_id = r.pm_id))
       AND (cv.printing_profile_id IS NOT DISTINCT FROM r.pprof
            OR (r.pprof IS NULL AND r.fb_pprof IS NOT NULL AND cv.printing_profile_id = r.fb_pprof))
     GROUP BY r.id
  ), sp AS (
    -- 3986 (R3): impressão única dos dois lados. Produto sem qualificador e sem Printing no
    -- rótulo, nenhuma candidata nas regras anteriores, a identidade da fonte tem um único
    -- rótulo de impressão e a carta tem uma única Card Variant (base ou UNLIMITED). Os dois
    -- lados concordam que só existe uma versão; o nome do acabamento pode divergir.
    SELECT r.id, min(cv.id::text)::uuid AS cv
      FROM r
      JOIN public.card_variant cv ON cv.card_id = r.card_id
      LEFT JOIN public.card_printing_profile cpp ON cpp.id = cv.printing_profile_id
     WHERE r.identity_id IS NOT NULL AND r.pm_id IS NOT NULL AND r.k IS NULL AND r.pprof IS NULL
       AND NOT EXISTS (SELECT 1 FROM best b WHERE b.id = r.id)
       AND NOT EXISTS (SELECT 1 FROM fb x WHERE x.id = r.id)
       AND (cpp.code IS NULL OR cpp.code = 'UNLIMITED')
       AND (SELECT count(*) FROM public.card_variant v WHERE v.card_id = r.card_id) = 1
       AND (SELECT count(DISTINCT p2.source_printing_label) FROM public.pricing_product p2
             WHERE p2.pricing_source_card_identity_id = r.identity_id) = 1
     GROUP BY r.id
  )
  SELECT r.id,
         CASE WHEN r.identity_id IS NULL THEN 'NO_IDENTITY'
              WHEN r.pm_id IS NULL THEN 'NO_LABEL_RULE'
              WHEN r.k IS NOT NULL AND r.q_id IS NULL THEN 'NO_QUALIFIER_RULE'
              WHEN b.id IS NULL AND f.n = 1 THEN 'UNIQUE_FALLBACK'
              WHEN b.id IS NULL AND f.n > 1 THEN 'AMBIGUOUS'
              WHEN b.id IS NULL AND s.id IS NOT NULL THEN 'UNIQUE_SINGLE_PRINTING'
              WHEN b.id IS NULL THEN 'NO_CANDIDATE'
              WHEN b.n > 1 THEN 'AMBIGUOUS'
              -- 3985: contexto inerente — o catálogo não tem NENHUMA variante sem Edition Context
              -- para esta carta (a carta só existe em forma contextual: promo de evento, McDonald's,
              -- Prerelease...). Produto sem qualificador então só pode ser essa variante.
              WHEN r.k IS NULL AND b.ntraits > 0 AND NOT EXISTS (
                     SELECT 1 FROM public.card_variant v
                      WHERE v.card_id = r.card_id
                        AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile_trait t
                                         WHERE t.profile_id = v.edition_context_profile_id))
                   THEN 'UNIQUE_INHERENT_CONTEXT'
              WHEN r.k IS NULL AND b.ntraits > 0 THEN 'UNIQUE_CONTEXT_ONLY'
              ELSE 'UNIQUE' END,
         CASE WHEN b.n = 1 THEN b.cv WHEN b.id IS NULL AND f.n = 1 THEN f.cv
              WHEN b.id IS NULL AND f.id IS NULL AND s.id IS NOT NULL THEN s.cv END,
         COALESCE(b.n, f.n, CASE WHEN s.id IS NOT NULL THEN 1 END, 0)::int
    FROM r LEFT JOIN best b ON b.id = r.id LEFT JOIN fb f ON f.id = r.id LEFT JOIN sp s ON s.id = r.id;
$f$;
REVOKE ALL ON FUNCTION internal.resolve_pricing_product_card_variant(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_reconcile_pricing_product_variants(
  p_apply boolean DEFAULT false,
  p_pricing_source_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $f$
DECLARE
  v_source uuid;
  v_ids uuid[];
  v_summary jsonb;
  v_applied int := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_RECONCILE_PRICING_PRODUCT_VARIANTS_FORBIDDEN';
  END IF;

  v_source := COALESCE(p_pricing_source_id, (SELECT id FROM public.pricing_source WHERE code = 'JUSTTCG'));
  IF v_source IS NULL OR NOT EXISTS (SELECT 1 FROM public.pricing_source WHERE id = v_source) THEN
    RAISE EXCEPTION 'ADMIN_RECONCILE_PRICING_PRODUCT_VARIANTS_SOURCE_NOT_FOUND: %', p_pricing_source_id;
  END IF;

  SELECT array_agg(pp.id) INTO v_ids
    FROM public.pricing_product pp
    JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
   WHERE m.pricing_source_id = v_source AND pp.card_variant_id IS NULL;

  DROP TABLE IF EXISTS pg_temp._ppv;  -- permite 2 chamadas na mesma transação (dry-run + apply)
  CREATE TEMP TABLE _ppv ON COMMIT DROP AS
    SELECT * FROM internal.resolve_pricing_product_card_variant(COALESCE(v_ids, '{}'));

  SELECT jsonb_object_agg(resolution, n) INTO v_summary
    FROM (SELECT resolution, count(*) n FROM _ppv GROUP BY 1) x;

  IF p_apply THEN
    UPDATE public.pricing_product pp
       SET card_variant_id = r.card_variant_id
      FROM _ppv r
     WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT', 'UNIQUE_SINGLE_PRINTING')
       AND pp.card_variant_id IS NULL;
    GET DIAGNOSTICS v_applied = ROW_COUNT;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_PRODUCT_VARIANT_RECONCILED', 'PRICING_SOURCE', v_source,
            jsonb_build_object('rule', '3974+3977+3985+3986', 'evaluated', COALESCE(array_length(v_ids, 1), 0),
                               'applied', v_applied, 'by_resolution', COALESCE(v_summary, '{}'::jsonb)));
  END IF;

  RETURN jsonb_build_object('pricing_source_id', v_source, 'apply', p_apply,
                            'evaluated', COALESCE(array_length(v_ids, 1), 0),
                            'applied', v_applied, 'by_resolution', COALESCE(v_summary, '{}'::jsonb));
END;
$f$;

CREATE OR REPLACE FUNCTION internal.link_new_pricing_products_to_variant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $f$
BEGIN
  UPDATE public.pricing_product pp
     SET card_variant_id = r.card_variant_id
    FROM internal.resolve_pricing_product_card_variant(
           ARRAY(SELECT n.id FROM new_rows n WHERE n.card_variant_id IS NULL)) r
   WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT', 'UNIQUE_SINGLE_PRINTING')
     AND pp.card_variant_id IS NULL;
  RETURN NULL;
END;
$f$;
