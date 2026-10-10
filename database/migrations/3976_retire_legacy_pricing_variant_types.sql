/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3976 - Aposentar os tipos legados usados só pelo Pricing
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-CATALOG-VARIANT-RECONCILIATION-01 (Pricing 80)
Depende.....: 3973 (a semântica de catálogo do qualificador já mora no vocabulário)

O que faz
  card_variant_type_id da identidade de preço e variant_type_id do vocabulário
  deixam de apontar para tipos que não existem no catálogo:
    STAFF_HOLO          (17 identidades + chave 'staff')  → HOLO
    SET_LOGO_REVERSE    (1 identidade PRIMARY, SVP 019)   → STANDARD (igual às demais PRIMARY)
    POKE_BALL_PATTERN   (256 + chave)                     → POKE_BALL_REVERSE
    MASTER_BALL_PATTERN (209 + chave)                     → MASTER_BALL_REVERSE
  Depois desativa os 4 tipos. Gate: nenhuma referência restante em card_variant,
  card_variant_type_external_mapping, identidade ou vocabulário.
  Nada muda em pricing_product.card_variant_id (o vínculo já vem da regra 3974).
===============================================================================
*/
BEGIN;

WITH m(old_code, new_code) AS (VALUES
  ('STAFF_HOLO','HOLO'), ('SET_LOGO_REVERSE','STANDARD'),
  ('POKE_BALL_PATTERN','POKE_BALL_REVERSE'), ('MASTER_BALL_PATTERN','MASTER_BALL_REVERSE')),
ids AS (
  SELECT o.id AS old_id, n.id AS new_id FROM m
    JOIN public.card_variant_type o ON o.code = m.old_code
    JOIN public.card_variant_type n ON n.code = m.new_code)
UPDATE public.pricing_source_card_identity i SET card_variant_type_id = ids.new_id
  FROM ids WHERE i.card_variant_type_id = ids.old_id;

WITH m(old_code, new_code) AS (VALUES
  ('STAFF_HOLO','HOLO'), ('SET_LOGO_REVERSE','STANDARD'),
  ('POKE_BALL_PATTERN','POKE_BALL_REVERSE'), ('MASTER_BALL_PATTERN','MASTER_BALL_REVERSE')),
ids AS (
  SELECT o.id AS old_id, n.id AS new_id FROM m
    JOIN public.card_variant_type o ON o.code = m.old_code
    JOIN public.card_variant_type n ON n.code = m.new_code)
UPDATE public.pricing_source_variant_mapping v SET variant_type_id = ids.new_id
  FROM ids WHERE v.variant_type_id = ids.old_id;

DO $g$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM public.card_variant_type t
   WHERE t.code IN ('STAFF_HOLO','SET_LOGO_REVERSE','POKE_BALL_PATTERN','MASTER_BALL_PATTERN')
     AND (EXISTS (SELECT 1 FROM public.card_variant x WHERE x.variant_type_id = t.id)
       OR EXISTS (SELECT 1 FROM public.card_variant_type_external_mapping x WHERE x.variant_type_id = t.id)
       OR EXISTS (SELECT 1 FROM public.pricing_source_card_identity x WHERE x.card_variant_type_id = t.id)
       OR EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping x WHERE x.variant_type_id = t.id OR x.catalog_finish_type_id = t.id)
       OR EXISTS (SELECT 1 FROM public.pricing_source_printing_mapping x WHERE x.card_variant_type_id = t.id));
  IF v <> 0 THEN RAISE EXCEPTION 'G1_TIPO_LEGADO_AINDA_REFERENCIADO: %', v; END IF;
END $g$;

UPDATE public.card_variant_type SET is_active = false
 WHERE code IN ('STAFF_HOLO','SET_LOGO_REVERSE','POKE_BALL_PATTERN','MASTER_BALL_PATTERN');

COMMIT;

-- Como validar
-- SELECT code, is_active FROM public.card_variant_type
--  WHERE code IN ('STAFF_HOLO','SET_LOGO_REVERSE','POKE_BALL_PATTERN','MASTER_BALL_PATTERN');  -- 4 linhas, false
