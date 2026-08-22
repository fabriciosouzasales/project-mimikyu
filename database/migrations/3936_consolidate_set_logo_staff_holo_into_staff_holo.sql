-- Query 3936 — Consolidar SET_LOGO_STAFF_HOLO em STAFF_HOLO
-- Status: CONFIRMADO EXECUTADO em 2026-08-22 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: remapear os card_variant vinculados a SET_LOGO_STAFF_HOLO para
-- STAFF_HOLO (preservando o id de card_variant), abortando se houver conflito
-- de unicidade (card_id, variant_type_id) no momento da execução, e desativar
-- (is_active=false, sem deletar) o variant_type redundante. SET_LOGO_REVERSE
-- e as tabelas pricing_* não são tocadas nesta migration.
--
-- Diagnóstico que motivou esta correção: auditoria de impacto (Fase B —
-- Resíduos de Pricing, revalidação SVP) identificou duplicação semântica
-- entre SET_LOGO_STAFF_HOLO (cadastrado em 2026-08-22, 0 identidades/preços
-- vinculados) e STAFF_HOLO (já usado em produção com 16 identidades e
-- observações de preço reais desde antes do cadastro específico de SVP).
-- SET_LOGO_REVERSE foi mantido separado por representar uma variante física
-- comprovadamente distinta (coexiste com STANDARD no mesmo card em Sets
-- mainline SV6-SV10.5W).
--
-- Resultado confirmado pós-execução:
--   STAFF_HOLO: 1 -> 40 vínculos (+39)
--   SET_LOGO_STAFF_HOLO: 39 -> 0 vínculos, is_active = false
--   SET_LOGO_REVERSE: 83 -> 83 (inalterado)
--   pricing_card_mapping / pricing_source_card_identity / pricing_product /
--   pricing_observation: contagens idênticas antes/depois (zero impacto)

DO $$
DECLARE
  v_staff_holo_id uuid;
  v_set_logo_staff_holo_id uuid;
  v_conflitos int;
BEGIN
  SELECT id INTO v_staff_holo_id FROM card_variant_type WHERE code = 'STAFF_HOLO';
  SELECT id INTO v_set_logo_staff_holo_id FROM card_variant_type WHERE code = 'SET_LOGO_STAFF_HOLO';

  IF v_staff_holo_id IS NULL OR v_set_logo_staff_holo_id IS NULL THEN
    RAISE EXCEPTION 'Um dos variant_type (STAFF_HOLO / SET_LOGO_STAFF_HOLO) não existe.';
  END IF;

  SELECT count(*) INTO v_conflitos
  FROM card_variant cv
  WHERE cv.variant_type_id = v_set_logo_staff_holo_id
    AND EXISTS (
      SELECT 1 FROM card_variant cv2
      WHERE cv2.card_id = cv.card_id AND cv2.variant_type_id = v_staff_holo_id
    );

  IF v_conflitos > 0 THEN
    RAISE EXCEPTION 'Abortado: % conflito(s) de unicidade (card já possui STAFF_HOLO).', v_conflitos;
  END IF;

  UPDATE card_variant
  SET variant_type_id = v_staff_holo_id, updated_at = now()
  WHERE variant_type_id = v_set_logo_staff_holo_id;

  UPDATE card_variant_type
  SET is_active = false, updated_at = now()
  WHERE id = v_set_logo_staff_holo_id;
END $$;
