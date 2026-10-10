/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3974 - Resolução pricing_product → card_variant (regra única)
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-CATALOG-VARIANT-RECONCILIATION-01 (Pricing 80)
Depende.....: 3973

Regra (uma só, usada pelo backfill, pela reconciliação admin e pelo trigger):
  Finish   = qualificador.catalog_finish_type_id, senão rótulo.card_variant_type_id
  Printing = rótulo.printing_profile_id (igualdade exata, NULL = impressão base)
  Edition Context: a variante precisa conter o traço exigido pelo qualificador
           (se houver); entre as candidatas vence a de MENOS traços.
  Resultado:
    UNIQUE                 1 candidata — vínculo gravado
    UNIQUE_CONTEXT_ONLY    1 candidata, mas produto sem qualificador e a variante
                           tem Edition Context (ex.: promo carimbada) — NÃO gravado,
                           fica para revisão
    AMBIGUOUS              >1 candidata empatada — não gravado
    NO_CANDIDATE           catálogo sem a variante — não gravado
    NO_LABEL_RULE / NO_QUALIFIER_RULE / NO_IDENTITY — vocabulário incompleto
  Nunca sobrescreve card_variant_id já preenchido (decisão manual preservada).

Objetos
  internal.resolve_pricing_product_card_variant(uuid[])  STABLE, sem efeito
  public.admin_reconcile_pricing_product_variants(bool, uuid)  admin, idempotente
  trigger AFTER INSERT (statement, transition table) em pricing_product:
    produtos novos do sync já nascem ligados quando a regra der UNIQUE.
===============================================================================
*/
BEGIN;

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
  )
  SELECT r.id,
         CASE WHEN r.identity_id IS NULL THEN 'NO_IDENTITY'
              WHEN r.pm_id IS NULL THEN 'NO_LABEL_RULE'
              WHEN r.k IS NOT NULL AND r.q_id IS NULL THEN 'NO_QUALIFIER_RULE'
              WHEN b.id IS NULL THEN 'NO_CANDIDATE'
              WHEN b.n > 1 THEN 'AMBIGUOUS'
              WHEN r.k IS NULL AND b.ntraits > 0 THEN 'UNIQUE_CONTEXT_ONLY'
              ELSE 'UNIQUE' END,
         CASE WHEN b.n = 1 THEN b.cv END,
         COALESCE(b.n, 0)::int
    FROM r LEFT JOIN best b ON b.id = r.id;
$f$;
REVOKE ALL ON FUNCTION internal.resolve_pricing_product_card_variant(uuid[]) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION internal.resolve_pricing_product_card_variant(uuid[]) IS
  'Regra única pricing_product → card_variant (3974, Pricing 80). Somente leitura.';

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

  CREATE TEMP TABLE _ppv ON COMMIT DROP AS
    SELECT * FROM internal.resolve_pricing_product_card_variant(COALESCE(v_ids, '{}'));

  SELECT jsonb_object_agg(resolution, n) INTO v_summary
    FROM (SELECT resolution, count(*) n FROM _ppv GROUP BY 1) x;

  IF p_apply THEN
    UPDATE public.pricing_product pp
       SET card_variant_id = r.card_variant_id
      FROM _ppv r
     WHERE r.pricing_product_id = pp.id AND r.resolution = 'UNIQUE'
       AND pp.card_variant_id IS NULL;
    GET DIAGNOSTICS v_applied = ROW_COUNT;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_PRODUCT_VARIANT_RECONCILED', 'PRICING_SOURCE', v_source,
            jsonb_build_object('rule', '3974', 'evaluated', COALESCE(array_length(v_ids, 1), 0),
                               'applied', v_applied, 'by_resolution', COALESCE(v_summary, '{}'::jsonb)));
  END IF;

  RETURN jsonb_build_object('pricing_source_id', v_source, 'apply', p_apply,
                            'evaluated', COALESCE(array_length(v_ids, 1), 0),
                            'applied', v_applied, 'by_resolution', COALESCE(v_summary, '{}'::jsonb));
END;
$f$;
REVOKE ALL ON FUNCTION public.admin_reconcile_pricing_product_variants(boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reconcile_pricing_product_variants(boolean, uuid) TO authenticated;

-- Produtos novos: vínculo automático quando a regra der UNIQUE
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
   WHERE r.pricing_product_id = pp.id AND r.resolution = 'UNIQUE' AND pp.card_variant_id IS NULL;
  RETURN NULL;
END;
$f$;
REVOKE ALL ON FUNCTION internal.link_new_pricing_products_to_variant() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_pricing_product_link_card_variant
  AFTER INSERT ON public.pricing_product
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION internal.link_new_pricing_products_to_variant();

COMMIT;
