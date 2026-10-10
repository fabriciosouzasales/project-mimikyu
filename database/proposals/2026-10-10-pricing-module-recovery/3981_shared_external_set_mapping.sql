/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3981 - Set externo compartilhado (N Sets locais -> 1 Set JustTCG)
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 3
Mandato.....: Fabrício, 2026-10-10 ("Permitir Set compartilhado (Recomendado)")

Problema
  Trainer Kits têm 2 decks no catálogo (ex.: TK-XY-B Bisharp e TK-XY-W Wigglytuff),
  mas a JustTCG publica os dois num único Set ("XY Trainer Kit: Bisharp & Wigglytuff").
  uq_pricing_set_mapping_source_external_confirmed impedia o 2º vínculo.

O que faz
  1. pricing_set_mapping.is_shared_external (default false) — opt-in explícito.
  2. Índice único passa a valer só para vínculos NÃO compartilhados.
  3. Trigger: num mesmo (fonte, Set externo) CONFIRMED, ou todos são compartilhados
     ou só existe um — nunca mistura (evita "compartilhar" um Set principal já usado).
     Serializa por advisory lock do par (fonte, Set externo).
  4. admin_confirm_pricing_set_mapping ganha p_shared_external (default false);
     chamadas antigas continuam idênticas.
  A segurança no nível da carta continua no índice existente
  uq_pricing_card_mapping_source_external_confirmed: uma carta externa nunca vai
  para duas cartas locais. O matching dos Sets compartilhados exige número + nome
  (bootstrap, ver _shared/pricing-justtcg-matching/card-matching.ts).
===============================================================================
*/
BEGIN;

ALTER TABLE public.pricing_set_mapping
  ADD COLUMN is_shared_external boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.pricing_set_mapping.is_shared_external IS
  'true = este Set local divide o Set externo com outros Sets locais (ex.: decks de Trainer Kit). Matching de cartas exige número + nome. (3981)';

DROP INDEX public.uq_pricing_set_mapping_source_external_confirmed;
CREATE UNIQUE INDEX uq_pricing_set_mapping_source_external_confirmed
  ON public.pricing_set_mapping (pricing_source_id, external_set_id)
  WHERE match_status = 'CONFIRMED' AND NOT is_shared_external;

CREATE OR REPLACE FUNCTION public.enforce_pricing_set_mapping_shared_external()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $f$
BEGIN
  IF NEW.match_status IS DISTINCT FROM 'CONFIRMED' OR NEW.external_set_id IS NULL THEN
    RETURN NEW;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.pricing_source_id::text || '|' || NEW.external_set_id, 3981));
  IF EXISTS (
    SELECT 1 FROM public.pricing_set_mapping o
     WHERE o.pricing_source_id = NEW.pricing_source_id
       AND o.external_set_id = NEW.external_set_id
       AND o.match_status = 'CONFIRMED'
       AND o.id <> NEW.id
       AND (o.is_shared_external IS DISTINCT FROM true OR NEW.is_shared_external IS DISTINCT FROM true)
  ) THEN
    RAISE EXCEPTION 'PRICING_SET_MAPPING_SHARED_EXTERNAL_CONFLICT: o Set externo % já está vinculado a outro Set sem compartilhamento.', NEW.external_set_id
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$f$;
REVOKE ALL ON FUNCTION public.enforce_pricing_set_mapping_shared_external() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_pricing_set_mapping_shared_external
  BEFORE INSERT OR UPDATE OF match_status, external_set_id, is_shared_external ON public.pricing_set_mapping
  FOR EACH ROW EXECUTE FUNCTION public.enforce_pricing_set_mapping_shared_external();

DROP FUNCTION public.admin_confirm_pricing_set_mapping(uuid, uuid, text, text, text, jsonb);

CREATE FUNCTION public.admin_confirm_pricing_set_mapping(
  p_card_set_id uuid, p_pricing_source_id uuid, p_external_set_id text, p_external_set_name text,
  p_match_method text DEFAULT NULL, p_match_evidence jsonb DEFAULT '{}'::jsonb,
  p_shared_external boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_game_code text;
  v_source_active boolean;
  v_row public.pricing_set_mapping;
  v_external_id text;
  v_external_name text;
  v_evidence jsonb;
  v_id uuid;
  v_shared boolean := COALESCE(p_shared_external, false);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  IF p_card_set_id IS NULL THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_CARD_SET'; END IF;
  IF p_pricing_source_id IS NULL THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_SOURCE'; END IF;

  v_external_id := NULLIF(BTRIM(p_external_set_id), '');
  v_external_name := NULLIF(BTRIM(p_external_set_name), '');
  IF v_external_id IS NULL THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_EXTERNAL_ID'; END IF;

  v_evidence := COALESCE(p_match_evidence, '{}'::jsonb);
  IF jsonb_typeof(v_evidence) IS DISTINCT FROM 'object' THEN v_evidence := '{}'::jsonb; END IF;

  SELECT g.code INTO v_game_code
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    JOIN public.game g ON g.id = ex.game_id
   WHERE cs.id = p_card_set_id
   FOR UPDATE OF cs;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_FOUND: id=%', p_card_set_id; END IF;
  IF v_game_code IS DISTINCT FROM 'POKEMON' THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_ELIGIBLE: id=%', p_card_set_id; END IF;

  SELECT is_active INTO v_source_active FROM public.pricing_source WHERE id = p_pricing_source_id;
  IF v_source_active IS NULL THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_FOUND: id=%', p_pricing_source_id; END IF;
  IF NOT v_source_active THEN RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_ACTIVE: id=%', p_pricing_source_id; END IF;

  SELECT * INTO v_row FROM public.pricing_set_mapping
   WHERE card_set_id = p_card_set_id AND pricing_source_id = p_pricing_source_id
   FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.pricing_set_mapping (
      card_set_id, pricing_source_id, external_set_id, external_set_name,
      match_status, match_method, match_evidence, confirmed_at, confirmed_by, last_checked_at, is_shared_external
    ) VALUES (
      p_card_set_id, p_pricing_source_id, v_external_id, v_external_name,
      'CONFIRMED', p_match_method, v_evidence, now(), auth.uid(), now(), v_shared
    )
    RETURNING id INTO v_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_SET_MAPPING_CONFIRMED', 'PRICING_SET_MAPPING', v_id,
      jsonb_build_object('outcome', 'INSERTED', 'external_set_id', v_external_id, 'external_set_name', v_external_name,
                         'match_method', p_match_method, 'shared_external', v_shared));
    RETURN;
  END IF;

  IF v_row.match_status = 'CONFIRMED' THEN
    IF v_row.external_set_id = v_external_id THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_ALREADY_CONFIRMED_DIFFERENT_CANDIDATE: este Set+fonte já está confirmado com outra correspondência -- use a edição de detalhes ou a reclassificação existente para trocar o vínculo.';
  END IF;

  UPDATE public.pricing_set_mapping SET
    external_set_id = v_external_id,
    external_set_name = v_external_name,
    match_status = 'CONFIRMED',
    match_method = COALESCE(p_match_method, match_method),
    match_evidence = v_evidence,
    is_shared_external = v_shared,
    confirmed_at = now(),
    confirmed_by = auth.uid(),
    last_checked_at = now(),
    updated_at = now()
  WHERE id = v_row.id;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'PRICING_SET_MAPPING_CONFIRMED', 'PRICING_SET_MAPPING', v_row.id,
    jsonb_build_object('outcome', 'UPGRADED_TO_CONFIRMED', 'old_status', v_row.match_status,
                       'external_set_id', v_external_id, 'external_set_name', v_external_name,
                       'match_method', p_match_method, 'shared_external', v_shared));
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_confirm_pricing_set_mapping(uuid, uuid, text, text, text, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_confirm_pricing_set_mapping(uuid, uuid, text, text, text, jsonb, boolean) TO authenticated;

COMMIT;
