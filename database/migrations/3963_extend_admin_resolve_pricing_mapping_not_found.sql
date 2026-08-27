-- Query 3963 — Extensão mínima do fluxo de resolução: NOT_FOUND manual
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: fechar o gap real identificado por Fabrício em produção — um
-- pricing_card_mapping PENDING sem nenhuma pricing_source_card_identity
-- candidata não tinha nenhuma ação administrativa útil (Confirmar fica
-- desabilitado por falta de candidata; Rejeitar é semanticamente errado
-- aqui, porque REJECTED no domínio significa "um candidato específico foi
-- rejeitado", não "busca concluída sem candidato nenhum" — ver
-- docs/05f-pricing.md, correção de precisão 1.1). Estende a mesma RPC já
-- existente (admin_resolve_pricing_mapping, migration 3940) com um
-- terceiro p_decision = 'NOT_FOUND', em vez de criar uma RPC quase
-- idêntica — mesma diretriz já aplicada na convergência de Mapeamentos de
-- Cartas (migrations 3961/3962).
--
-- Regras do ramo NOT_FOUND: só a partir de PENDING (NOT_FOUND→NOT_FOUND é
-- no-op explícito, mesmo padrão de erro nomeado de
-- admin_reclassify_pricing_card_mapping); motivo obrigatório (mesma
-- disciplina de REJECTED); nunca aceita p_identity_assignments (bloqueado
-- explicitamente, não apenas ignorado — não cria matching fictício);
-- nunca preenche confirmed_at/confirmed_by (a trigger
-- set_pricing_mapping_confirmed_at_authority, migration 3920, já zera
-- confirmed_at para qualquer NEW.match_status fora de
-- CONFIRMED/REJECTED; confirmed_by simplesmente não é tocado pelo UPDATE,
-- permanece NULL como já estava em PENDING — ambos exigidos NULL pelo
-- CHECK ck_pricing_card_mapping_confirmation_consistency); atualiza
-- last_checked_at = now() (exigido por
-- ck_pricing_card_mapping_not_found_requires_last_checked); grava
-- exatamente 1 audit log PRICING_MAPPING_NOT_FOUND com previous_status +
-- motivo. Ramos CONFIRMED/REJECTED preservados byte-a-byte (confirmado
-- por diff contra a definição ao vivo antes desta migration).
--
-- Testado transacionalmente (BEGIN + toda a suíte + rollback automático
-- por fechamento de conexão, sem residual em produção), 7 cenários:
-- PENDING sem candidata → NOT_FOUND com audit log (status/confirmed_at/
-- confirmed_by/last_checked_at/log_count corretos); NOT_FOUND→NOT_FOUND
-- bloqueado (ADMIN_RESOLVE_PRICING_MAPPING_NO_OP); motivo vazio bloqueado
-- (ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_REASON_REQUIRED); identity
-- assignments não vazio bloqueado
-- (ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_ASSIGNMENTS_NOT_ALLOWED);
-- REJECTED sem regressão; CONFIRMED sem regressão (identity sintética,
-- pois não havia PENDING com candidata real no momento do teste — dados
-- reais já majoritariamente resolvidos pelo dispatcher); FORBIDDEN para
-- chamador não-admin.
--
-- Como validar:
--   SELECT public.admin_resolve_pricing_mapping('<uuid PENDING sem candidata>', 'NOT_FOUND', NULL, 'sem candidata na fonte'); -- como admin
--   SELECT match_status, last_checked_at, confirmed_at, confirmed_by FROM public.pricing_card_mapping WHERE id = '<uuid>';
--   SELECT * FROM public.pricing_admin_action_log WHERE entity_id = '<uuid>' ORDER BY created_at DESC LIMIT 1;

-- 1) Ampliar vocabulário de pricing_admin_action_log
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_check;
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_action_check
  CHECK (action = ANY (ARRAY[
    'PRICING_REFRESH_FREQUENCY_CHANGED'::text,
    'PRICING_SOURCE_UPDATED'::text,
    'PRICING_MAPPING_CONFIRMED'::text,
    'PRICING_MAPPING_REJECTED'::text,
    'PRICING_MAPPING_NOT_FOUND'::text,
    'PRICING_SET_MAPPING_DETAILS_UPDATED'::text,
    'PRICING_SET_MAPPING_CONFIRMED'::text,
    'PRICING_SET_MAPPING_REJECTED'::text,
    'CARD_CONDITION_CREATED'::text,
    'CARD_CONDITION_UPDATED'::text,
    'PRICING_CONDITION_MAPPING_UPDATED'::text
  ]));

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check
  CHECK (
    ((entity_type = 'PRICING_SOURCE'::text) AND (action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED'::text, 'PRICING_SOURCE_UPDATED'::text])))
    OR ((entity_type = 'PRICING_CARD_MAPPING'::text) AND (action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED'::text, 'PRICING_MAPPING_REJECTED'::text, 'PRICING_MAPPING_NOT_FOUND'::text])))
    OR ((entity_type = 'PRICING_SET_MAPPING'::text) AND (action = ANY (ARRAY['PRICING_SET_MAPPING_DETAILS_UPDATED'::text, 'PRICING_SET_MAPPING_CONFIRMED'::text, 'PRICING_SET_MAPPING_REJECTED'::text])))
    OR ((entity_type = 'CARD_CONDITION'::text) AND (action = ANY (ARRAY['CARD_CONDITION_CREATED'::text, 'CARD_CONDITION_UPDATED'::text])))
    OR ((entity_type = 'PRICING_CONDITION_MAPPING'::text) AND (action = 'PRICING_CONDITION_MAPPING_UPDATED'::text))
  );

-- 2) admin_resolve_pricing_mapping — estende com NOT_FOUND (assinatura inalterada, grants preservados)
CREATE OR REPLACE FUNCTION public.admin_resolve_pricing_mapping(
  p_mapping_id uuid,
  p_decision text,
  p_identity_assignments jsonb DEFAULT NULL,
  p_reject_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mapping public.pricing_card_mapping;
  v_actor uuid;
  v_previous_status text;
  v_invalid_ids uuid[];
  v_ext_id text;
  v_ext_name text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_actor := auth.uid();

  IF p_decision NOT IN ('CONFIRMED', 'REJECTED', 'NOT_FOUND') THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_INVALID_DECISION: %', p_decision;
  END IF;

  SELECT * INTO v_mapping
  FROM public.pricing_card_mapping
  WHERE id = p_mapping_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND: id=%', p_mapping_id;
  END IF;

  IF v_mapping.match_status NOT IN ('PENDING', 'NOT_FOUND') THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_ALREADY_DECIDED: id=% status=%', p_mapping_id, v_mapping.match_status;
  END IF;

  v_previous_status := v_mapping.match_status;

  IF p_decision = 'NOT_FOUND' THEN
    IF v_previous_status = 'NOT_FOUND' THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NO_OP: id=% já está NOT_FOUND.', p_mapping_id;
    END IF;

    IF p_identity_assignments IS NOT NULL AND jsonb_array_length(p_identity_assignments) > 0 THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_ASSIGNMENTS_NOT_ALLOWED';
    END IF;

    IF p_reject_reason IS NULL OR BTRIM(p_reject_reason) = '' THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_REASON_REQUIRED';
    END IF;

    -- NOT_FOUND nunca cria identity, nunca preenche confirmed_at/confirmed_by
    -- (a trigger set_pricing_mapping_confirmed_at_authority, migration 3920,
    -- já zera confirmed_at para NEW.match_status fora de CONFIRMED/REJECTED;
    -- confirmed_by não é tocado pelo UPDATE, permanece NULL como já estava
    -- em PENDING) — só atualiza o estado e a autoridade temporal de leitura.
    UPDATE public.pricing_card_mapping
    SET match_status = 'NOT_FOUND', last_checked_at = now()
    WHERE id = p_mapping_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
      v_actor, 'PRICING_MAPPING_NOT_FOUND', 'PRICING_CARD_MAPPING', p_mapping_id,
      jsonb_build_object('previous_status', v_previous_status, 'decision', 'NOT_FOUND', 'reason', p_reject_reason)
    );

    RETURN jsonb_build_object('mapping_id', p_mapping_id, 'decision', 'NOT_FOUND');
  END IF;

  IF p_decision = 'REJECTED' THEN
    IF p_reject_reason IS NULL OR BTRIM(p_reject_reason) = '' THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_REJECT_REASON_REQUIRED';
    END IF;

    UPDATE public.pricing_card_mapping
    SET match_status = 'REJECTED', confirmed_by = v_actor
    WHERE id = p_mapping_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
      v_actor, 'PRICING_MAPPING_REJECTED', 'PRICING_CARD_MAPPING', p_mapping_id,
      jsonb_build_object('previous_status', v_previous_status, 'decision', 'REJECTED', 'reject_reason', p_reject_reason)
    );

    RETURN jsonb_build_object('mapping_id', p_mapping_id, 'decision', 'REJECTED');
  END IF;

  -- CONFIRMED — inalterado, exige 1..N identity_assignments válidos.
  IF p_identity_assignments IS NULL OR jsonb_array_length(p_identity_assignments) = 0 THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_ASSIGNMENTS_REQUIRED';
  END IF;

  SELECT array_agg(a.identity_id) INTO v_invalid_ids
  FROM jsonb_to_recordset(p_identity_assignments)
    AS a(identity_id uuid, identity_role text, canonical_identity_id uuid, card_variant_type_id uuid)
  LEFT JOIN public.pricing_source_card_identity psci
    ON psci.id = a.identity_id
    AND psci.pricing_card_mapping_id = p_mapping_id
    AND psci.match_status = 'PENDING'
  WHERE psci.id IS NULL;

  IF v_invalid_ids IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_IDENTITY_INCOMPATIBLE: ids=%', v_invalid_ids;
  END IF;

  WITH assignments AS (
    SELECT * FROM jsonb_to_recordset(p_identity_assignments)
      AS a(identity_id uuid, identity_role text, canonical_identity_id uuid, card_variant_type_id uuid)
  )
  UPDATE public.pricing_source_card_identity t
  SET match_status = 'CONFIRMED',
      confirmed_by = v_actor,
      match_method = 'ADMIN_MANUAL_CONFIRMATION',
      identity_role = a.identity_role,
      card_variant_type_id = a.card_variant_type_id
  FROM assignments a
  WHERE t.id = a.identity_id AND a.identity_role IN ('PRIMARY', 'ALTERNATE');

  WITH assignments AS (
    SELECT * FROM jsonb_to_recordset(p_identity_assignments)
      AS a(identity_id uuid, identity_role text, canonical_identity_id uuid, card_variant_type_id uuid)
  )
  UPDATE public.pricing_source_card_identity t
  SET match_status = 'CONFIRMED',
      confirmed_by = v_actor,
      match_method = 'ADMIN_MANUAL_CONFIRMATION',
      identity_role = 'ALIAS',
      canonical_identity_id = a.canonical_identity_id,
      card_variant_type_id = a.card_variant_type_id
  FROM assignments a
  WHERE t.id = a.identity_id AND a.identity_role = 'ALIAS';

  SELECT external_card_id, external_card_name INTO v_ext_id, v_ext_name
  FROM public.pricing_source_card_identity
  WHERE pricing_card_mapping_id = p_mapping_id AND identity_role = 'PRIMARY' AND match_status = 'CONFIRMED'
  LIMIT 1;

  IF v_ext_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NO_PRIMARY_CONFIRMED: id=%', p_mapping_id;
  END IF;

  UPDATE public.pricing_card_mapping
  SET match_status = 'CONFIRMED',
      match_method = 'ADMIN_MANUAL_CONFIRMATION',
      external_card_id = v_ext_id,
      external_card_name = v_ext_name,
      confirmed_by = v_actor,
      last_checked_at = now()
  WHERE id = p_mapping_id;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (
    v_actor, 'PRICING_MAPPING_CONFIRMED', 'PRICING_CARD_MAPPING', p_mapping_id,
    jsonb_build_object('previous_status', v_previous_status, 'decision', 'CONFIRMED', 'identity_assignments', p_identity_assignments)
  );

  RETURN jsonb_build_object('mapping_id', p_mapping_id, 'decision', 'CONFIRMED', 'external_card_id', v_ext_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_resolve_pricing_mapping(uuid, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_pricing_mapping(uuid, text, jsonb, text) TO authenticated;
