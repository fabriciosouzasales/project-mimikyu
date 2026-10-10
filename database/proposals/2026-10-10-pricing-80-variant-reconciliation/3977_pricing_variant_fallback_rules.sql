/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3977 - Regras de fallback da resolução pricing_product → card_variant
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-CATALOG-VARIANT-RECONCILIATION-01 (Pricing 80)
Depende.....: 3973, 3974
Mandato.....: Fabrício, 2026-10-10: "Aplique as duas regras do grupo 1 e 2"

Regras (só para produto SEM qualificador e só quando a regra principal deu
NO_CANDIDATE; a variante candidata não pode ter Edition Context):
  1. Família holo: o rótulo "Holofoil"/"Unlimited Holofoil" também aceita
     RAINBOW_HOLO, GOLD_HOLO e COSMOS_HOLO (carta que só existe nesse foil).
  2. Impressão base: rótulo sem Printing ("Normal", "Holofoil", "Unlimited",
     "Unlimited Holofoil") também aceita o perfil UNLIMITED (Base Set e
     afins, onde o catálogo separa Unlimited de Shadowless).
  Grava só com exatamente 1 candidata → resolução UNIQUE_FALLBACK.

Dados (vocabulário, não código):
  pricing_source_printing_mapping.fallback_printing_profile_id
  pricing_source_printing_finish_fallback (rótulo → Finishes aceitos no fallback)
Dry-run: 1.583 produtos (1.153 "Holofoil" + 430 "Normal"), todos com 1 candidata.
===============================================================================
*/
BEGIN;

ALTER TABLE public.pricing_source_printing_mapping
  ADD COLUMN fallback_printing_profile_id uuid NULL REFERENCES public.card_printing_profile(id) ON DELETE RESTRICT;
COMMENT ON COLUMN public.pricing_source_printing_mapping.fallback_printing_profile_id IS
  'Printing aceito quando não há variante na impressão base (ex.: UNLIMITED no Base Set) (3977).';

CREATE TABLE public.pricing_source_printing_finish_fallback (
  printing_mapping_id  uuid NOT NULL REFERENCES public.pricing_source_printing_mapping(id) ON DELETE CASCADE,
  card_variant_type_id uuid NOT NULL REFERENCES public.card_variant_type(id) ON DELETE RESTRICT,
  created_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (printing_mapping_id, card_variant_type_id)
);
ALTER TABLE public.pricing_source_printing_finish_fallback ENABLE ROW LEVEL SECURITY;
CREATE POLICY pricing_admin_select ON public.pricing_source_printing_finish_fallback
  FOR SELECT TO authenticated USING ((SELECT public.is_admin()));
REVOKE ALL ON public.pricing_source_printing_finish_fallback FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.pricing_source_printing_finish_fallback TO authenticated, service_role;
COMMENT ON TABLE public.pricing_source_printing_finish_fallback IS
  'Finishes aceitos no fallback para um rótulo de impressão (ex.: Holofoil → RAINBOW/GOLD/COSMOS) (3977).';

UPDATE public.pricing_source_printing_mapping pm
   SET fallback_printing_profile_id = (SELECT id FROM public.card_printing_profile WHERE code = 'UNLIMITED')
  FROM public.pricing_source s
 WHERE s.id = pm.pricing_source_id AND s.code = 'JUSTTCG'
   AND pm.source_printing_label IN ('Normal','Holofoil','Unlimited','Unlimited Holofoil');

INSERT INTO public.pricing_source_printing_finish_fallback (printing_mapping_id, card_variant_type_id)
SELECT pm.id, t.id
  FROM public.pricing_source_printing_mapping pm
  JOIN public.pricing_source s ON s.id = pm.pricing_source_id AND s.code = 'JUSTTCG'
  JOIN public.card_variant_type t ON t.code IN ('RAINBOW_HOLO','GOLD_HOLO','COSMOS_HOLO')
 WHERE pm.source_printing_label IN ('Holofoil','Unlimited Holofoil');

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
     WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK')
       AND pp.card_variant_id IS NULL;
    GET DIAGNOSTICS v_applied = ROW_COUNT;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_PRODUCT_VARIANT_RECONCILED', 'PRICING_SOURCE', v_source,
            jsonb_build_object('rule', '3974+3977', 'evaluated', COALESCE(array_length(v_ids, 1), 0),
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
   WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK')
     AND pp.card_variant_id IS NULL;
  RETURN NULL;
END;
$f$;

DO $g$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM public.pricing_source_printing_mapping WHERE fallback_printing_profile_id IS NOT NULL;
  IF v <> 4 THEN RAISE EXCEPTION 'G1_FALLBACK_PRINTING: %', v; END IF;
  SELECT count(*) INTO v FROM public.pricing_source_printing_finish_fallback;
  IF v <> 6 THEN RAISE EXCEPTION 'G2_FALLBACK_FINISH: %', v; END IF;
END $g$;

COMMIT;

-- Aplicação (admin, idempotente) — CONFIRMADO EXECUTADO 2026-10-10:
--   dry-run UNIQUE_FALLBACK 1.583 (gate) → apply 1.583; total ligado 49.899/50.470; carta errada 0.
--   Ajuste no mesmo ciclo (3977b): a RPC faz DROP TABLE IF EXISTS pg_temp._ppv antes do CREATE,
--   para permitir dry-run + apply na mesma transação (já refletido acima).
