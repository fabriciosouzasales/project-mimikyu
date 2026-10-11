/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3985 - Vínculo produto → variante: contexto inerente à carta
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — pós-Fase 5 (fila residual de variantes)
Depende.....: 3974, 3977
Mandato.....: Fabrício, 2026-10-10 ("Vamos resolver os produtos com uma única variante possível")

Problema
  UNIQUE_CONTEXT_ONLY = 1 candidata, mas o produto da fonte não tem qualificador e a
  variante tem Edition Context (traits). Ficava sem vínculo por segurança: o produto
  genérico poderia ser a versão "comum" que o catálogo não tem.

Auditoria (LIVE, 563 produtos)
  SVP Prerelease (169, nome externo "(Prerelease)"), McDonald's 2021/2012/2014 (370),
  Worlds 2023-25 (8) e BASEP Pokémon 4Ever (10): o contexto É a identidade da carta —
  o catálogo não tem variante sem contexto. SWSH4 League Staff (3): o catálogo tem a
  versão comum (STANDARD sem contexto) e só o Reverse com ROLE_STAFF → o produto
  "Reverse Holofoil" provavelmente é o reverse comum que falta no catálogo. NÃO vincular.

Regra (permanente, vale também para produtos novos via trigger)
  Nova resolução UNIQUE_INHERENT_CONTEXT: produto sem qualificador, 1 candidata de menor
  número de traits, e a carta NÃO tem nenhuma variante sem Edition Context. Aceita pelo
  trigger de inserção e por admin_reconcile_pricing_product_variants (log rule 3974+3977+3985).
  UNIQUE_CONTEXT_ONLY continua sem vínculo (fila editorial).
===============================================================================
*/
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
  )
  SELECT r.id,
         CASE WHEN r.identity_id IS NULL THEN 'NO_IDENTITY'
              WHEN r.pm_id IS NULL THEN 'NO_LABEL_RULE'
              WHEN r.k IS NOT NULL AND r.q_id IS NULL THEN 'NO_QUALIFIER_RULE'
              WHEN b.id IS NULL AND f.n = 1 THEN 'UNIQUE_FALLBACK'
              WHEN b.id IS NULL AND f.n > 1 THEN 'AMBIGUOUS'
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
         CASE WHEN b.n = 1 THEN b.cv WHEN b.id IS NULL AND f.n = 1 THEN f.cv END,
         COALESCE(b.n, f.n, 0)::int
    FROM r LEFT JOIN best b ON b.id = r.id LEFT JOIN fb f ON f.id = r.id;
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
     WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT')
       AND pp.card_variant_id IS NULL;
    GET DIAGNOSTICS v_applied = ROW_COUNT;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_PRODUCT_VARIANT_RECONCILED', 'PRICING_SOURCE', v_source,
            jsonb_build_object('rule', '3974+3977+3985', 'evaluated', COALESCE(array_length(v_ids, 1), 0),
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
   WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT')
     AND pp.card_variant_id IS NULL;
  RETURN NULL;
END;
$f$;
