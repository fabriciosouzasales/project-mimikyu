/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3973 - Vocabulário Pricing → Catálogo nos três eixos
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-CATALOG-VARIANT-RECONCILIATION-01 (Pricing 80)
Origem......: database/proposals/2026-10-10-pricing-80-variant-reconciliation/README.md

Objetivo
  Dar à fonte de preço um vocabulário que fala a língua do catálogo de três
  eixos (Finish + Printing + Edition Context), para que cada pricing_product
  seja ligado à sua card_variant:
  - pricing_source_printing_mapping (nova): rótulo de impressão da fonte
    ("Normal", "1st Edition Holofoil"...) → Finish + Printing Profile.
  - pricing_source_variant_mapping (existente) ganha duas colunas:
      catalog_finish_type_id   — Finish que o qualificador impõe (ex.: "poke
                                  ball pattern" → POKE_BALL_REVERSE); NULL =
                                  Finish vem do rótulo de impressão.
      edition_context_trait_id — traço de Edition Context que o qualificador
                                  exige (ex.: "staff" → ROLE_STAFF).
    variant_type_id continua como classificação legada da fonte.
  - pricing_admin_action_log aceita PRICING_PRODUCT_VARIANT_RECONCILED
    (entidade PRICING_SOURCE).

Segurança
  Tabela nova: RLS ligada, SELECT só para admin (mesma policy do Pricing),
  sem grant para anon; escrita só via migration.
===============================================================================
*/
BEGIN;

CREATE TABLE public.pricing_source_printing_mapping (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_source_id     uuid NOT NULL REFERENCES public.pricing_source(id) ON DELETE CASCADE,
  source_printing_label text NOT NULL CHECK (btrim(source_printing_label) <> ''),
  card_variant_type_id  uuid NOT NULL REFERENCES public.card_variant_type(id) ON DELETE RESTRICT,
  printing_profile_id   uuid NULL REFERENCES public.card_printing_profile(id) ON DELETE RESTRICT,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_pricing_source_printing_mapping_label UNIQUE (pricing_source_id, source_printing_label)
);
CREATE TRIGGER trg_pricing_source_printing_mapping_set_updated_at
  BEFORE UPDATE ON public.pricing_source_printing_mapping
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.pricing_source_printing_mapping ENABLE ROW LEVEL SECURITY;
CREATE POLICY pricing_admin_select ON public.pricing_source_printing_mapping
  FOR SELECT TO authenticated USING ((SELECT public.is_admin()));
REVOKE ALL ON public.pricing_source_printing_mapping FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.pricing_source_printing_mapping TO authenticated, service_role;
COMMENT ON TABLE public.pricing_source_printing_mapping IS
  'Rótulo de impressão da fonte de preço → Finish + Printing Profile do catálogo (3973, Pricing 80).';

ALTER TABLE public.pricing_source_variant_mapping
  ADD COLUMN catalog_finish_type_id   uuid NULL REFERENCES public.card_variant_type(id) ON DELETE RESTRICT,
  ADD COLUMN edition_context_trait_id uuid NULL REFERENCES public.card_edition_context_trait(id) ON DELETE RESTRICT;
COMMENT ON COLUMN public.pricing_source_variant_mapping.catalog_finish_type_id IS
  'Finish do catálogo imposto pelo qualificador; NULL = Finish vem do rótulo de impressão (3973).';
COMMENT ON COLUMN public.pricing_source_variant_mapping.edition_context_trait_id IS
  'Traço de Edition Context exigido pelo qualificador (ex.: staff → ROLE_STAFF) (3973).';

-- Seed: rótulos de impressão JustTCG
INSERT INTO public.pricing_source_printing_mapping (pricing_source_id, source_printing_label, card_variant_type_id, printing_profile_id, notes)
SELECT s.id, v.lbl, t.id, pp.id, v.notes
  FROM (VALUES
    ('Normal',               'STANDARD', NULL,            'impressão comum'),
    ('Holofoil',             'HOLO',     NULL,            'holo'),
    ('Reverse Holofoil',     'REVERSE_HOLO', NULL,        'reverse holo'),
    ('Unlimited',            'STANDARD', NULL,            'era WotC: Unlimited = impressão base'),
    ('Unlimited Holofoil',   'HOLO',     NULL,            'era WotC: Unlimited = impressão base'),
    ('1st Edition',          'STANDARD', 'FIRST_EDITION', 'era WotC'),
    ('1st Edition Holofoil', 'HOLO',     'FIRST_EDITION', 'era WotC')
  ) v(lbl, finish, pprof, notes)
  JOIN public.pricing_source s ON s.code = 'JUSTTCG'
  JOIN public.card_variant_type t ON t.code = v.finish
  LEFT JOIN public.card_printing_profile pp ON pp.code = v.pprof;

-- Seed: semântica de catálogo dos qualificadores existentes
UPDATE public.pricing_source_variant_mapping m
   SET catalog_finish_type_id = ft.id, edition_context_trait_id = tr.id
  FROM (VALUES
    ('cosmos holofoil', 'COSMOS_HOLO', NULL),
    ('cosmo holo', 'COSMOS_HOLO', NULL),
    ('cosmos holo', 'COSMOS_HOLO', NULL),
    ('cracked ice holo', 'CRACKED_ICE_HOLO', NULL),
    ('dusk ball', 'DUSK_BALL_REVERSE', NULL),
    ('energy symbol pattern', 'ENERGY_REVERSE', NULL),
    ('friend ball', 'FRIEND_BALL_REVERSE', NULL),
    ('love ball', 'LOVE_BALL_REVERSE', NULL),
    ('quick ball', 'QUICK_BALL_REVERSE', NULL),
    ('team rocket', 'ROCKET_REVERSE', NULL),
    ('poke ball', 'POKE_BALL_REVERSE', NULL),
    ('poke ball pattern', 'POKE_BALL_REVERSE', NULL),
    ('master ball pattern', 'MASTER_BALL_REVERSE', NULL),
    ('pokemon center', NULL, 'CHANNEL_POKEMON_CENTER'),
    ('pokemon center exclusive', NULL, 'CHANNEL_POKEMON_CENTER'),
    ('pokémon center exclusive', NULL, 'CHANNEL_POKEMON_CENTER'),
    ('staff', NULL, 'ROLE_STAFF')
  ) v(k, finish, trait)
  JOIN public.pricing_source s ON s.code = 'JUSTTCG'
  LEFT JOIN public.card_variant_type ft ON ft.code = v.finish
  LEFT JOIN public.card_edition_context_trait tr ON tr.code = v.trait
 WHERE m.pricing_source_id = s.id AND m.external_variant_key = v.k;

-- Log administrativo: nova ação
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_check;
ALTER TABLE public.pricing_admin_action_log ADD CONSTRAINT pricing_admin_action_log_action_check CHECK (action = ANY (ARRAY[
  'PRICING_REFRESH_FREQUENCY_CHANGED','PRICING_SOURCE_UPDATED','PRICING_MAPPING_CONFIRMED','PRICING_MAPPING_REJECTED',
  'PRICING_MAPPING_NOT_FOUND','PRICING_SET_MAPPING_DETAILS_UPDATED','PRICING_SET_MAPPING_CONFIRMED','PRICING_SET_MAPPING_REJECTED',
  'CARD_CONDITION_CREATED','CARD_CONDITION_UPDATED','PRICING_CONDITION_MAPPING_UPDATED','PRICING_MANUAL_PRICE_SET',
  'PRICING_PRODUCT_VARIANT_RECONCILED']));
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;
ALTER TABLE public.pricing_admin_action_log ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check CHECK (
     (entity_type = 'PRICING_SOURCE' AND action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED','PRICING_SOURCE_UPDATED','PRICING_PRODUCT_VARIANT_RECONCILED']))
  OR (entity_type = 'PRICING_CARD_MAPPING' AND action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED','PRICING_MAPPING_REJECTED','PRICING_MAPPING_NOT_FOUND']))
  OR (entity_type = 'PRICING_SET_MAPPING' AND action = ANY (ARRAY['PRICING_SET_MAPPING_DETAILS_UPDATED','PRICING_SET_MAPPING_CONFIRMED','PRICING_SET_MAPPING_REJECTED']))
  OR (entity_type = 'CARD_CONDITION' AND action = ANY (ARRAY['CARD_CONDITION_CREATED','CARD_CONDITION_UPDATED']))
  OR (entity_type = 'PRICING_CONDITION_MAPPING' AND action = 'PRICING_CONDITION_MAPPING_UPDATED')
  OR (entity_type = 'PRICING_MANUAL_PRICE' AND action = 'PRICING_MANUAL_PRICE_SET'));

-- Gates
DO $g$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM public.pricing_source_printing_mapping;
  IF v <> 7 THEN RAISE EXCEPTION 'G1_PRINTING_SEED: %', v; END IF;
  SELECT count(*) INTO v FROM public.pricing_source_printing_mapping WHERE source_printing_label LIKE '1st%' AND printing_profile_id IS NULL;
  IF v <> 0 THEN RAISE EXCEPTION 'G2_FIRST_EDITION_SEM_PERFIL: %', v; END IF;
  SELECT count(*) INTO v FROM public.pricing_source_variant_mapping WHERE catalog_finish_type_id IS NULL AND edition_context_trait_id IS NULL;
  IF v <> 0 THEN RAISE EXCEPTION 'G3_QUALIFICADOR_SEM_SEMANTICA: %', v; END IF;
  -- todo rótulo usado por produto tem regra
  SELECT count(DISTINCT pp.source_printing_label) INTO v FROM public.pricing_product pp
   WHERE NOT EXISTS (SELECT 1 FROM public.pricing_source_printing_mapping m WHERE m.source_printing_label = pp.source_printing_label);
  IF v <> 0 THEN RAISE EXCEPTION 'G4_ROTULO_SEM_REGRA: %', v; END IF;
END $g$;

COMMIT;
