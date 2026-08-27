-- Query 3962 — Hardening de admin_reclassify_pricing_card_mapping (REJECTED -> CONFIRMED)
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: fechar a lacuna latente identificada durante a convergência de
-- Mapeamentos de Cartas (0 casos reais até hoje, mas fisicamente possível
-- antes desta migration): reclassificar REJECTED->CONFIRMED sem nenhuma
-- identity PRIMARY confirmada. Dois cenários cobertos:
--   - mapping que chegou a REJECTED via admin_resolve_pricing_mapping
--     (external_card_id NULL) — sem esta migration, o próprio CHECK
--     ck_pricing_card_mapping_confirmed_requires_external_id já bloquearia
--     o UPDATE, mas com um erro de constraint genérico, não uma mensagem
--     de negócio.
--   - mapping que já foi CONFIRMED antes, foi rebaixado para REJECTED via
--     reclassify (external_card_id preservado, não NULL), e é reclassificado
--     de volta para CONFIRMED — este caso passava direto pelo CHECK (o
--     valor antigo já não era NULL) e podia reconfirmar com
--     external_card_id/external_card_name obsoletos, sem nenhuma identity
--     válida por trás.
-- Aplica a mesma garantia que admin_resolve_pricing_mapping já usa: exige
-- uma pricing_source_card_identity com identity_role='PRIMARY' e
-- match_status='CONFIRMED', e usa external_card_id/external_card_name
-- dela para o UPDATE (via COALESCE, preservando o valor anterior apenas no
-- ramo CONFIRMED->REJECTED, onde v_ext_id/v_ext_name nunca são
-- recalculados). Também padroniza match_method='ADMIN_MANUAL_CONFIRMATION'
-- nesse ramo, alinhado com admin_resolve_pricing_mapping.
--
-- Testado transacionalmente (BEGIN + ROLLBACK, sem residual em produção)
-- com um mapping PENDING real forçado para REJECTED dentro da própria
-- transação: reclassificar para CONFIRMED sem identity falhou com
-- ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NO_PRIMARY_IDENTITY; após inserir
-- uma identity PRIMARY CONFIRMED sintética, a mesma chamada teve sucesso e
-- preencheu corretamente match_status=CONFIRMED, match_method=
-- ADMIN_MANUAL_CONFIRMATION, external_card_id/external_card_name a partir
-- da identity. Comportamento não alterado nos demais ramos (CONFIRMED-
-- >REJECTED com dependência bloqueada, NO_OP, FORBIDDEN, motivo
-- obrigatório) — só o bloco novo foi adicionado.
--
-- Pós-aplicação real: CREATE OR REPLACE preserva grants (assinatura da
-- função inalterada: p_id uuid, p_new_status text, p_reason text) —
-- confirmado via information_schema.role_routine_grants (authenticated e
-- postgres, igual a antes).
--
-- Como validar:
--   SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'admin_reclassify_pricing_card_mapping';

CREATE OR REPLACE FUNCTION public.admin_reclassify_pricing_card_mapping(p_id uuid, p_new_status text, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_row public.pricing_card_mapping;
  v_reason text;
  v_action text;
  v_ext_id text;
  v_ext_name text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  IF p_new_status NOT IN ('CONFIRMED', 'REJECTED') THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_INVALID_STATUS: só CONFIRMED ou REJECTED.';
  END IF;

  v_reason := NULLIF(BTRIM(p_reason), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_MISSING_REASON';
  END IF;

  SELECT * INTO v_row FROM public.pricing_card_mapping WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NOT_FOUND: id=%', p_id;
  END IF;

  IF v_row.match_status NOT IN ('CONFIRMED', 'REJECTED') THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_INVALID_CURRENT_STATUS: só reclassifica CONFIRMED/REJECTED — % use Resolução de Mapeamentos.', v_row.match_status;
  END IF;

  IF v_row.match_status = p_new_status THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NO_OP: já está %.', p_new_status;
  END IF;

  IF v_row.match_status = 'CONFIRMED' AND p_new_status = 'REJECTED' THEN
    IF public.pricing_card_mapping_dependency_exists(v_row.id) THEN
      RAISE EXCEPTION 'CARD_MAPPING_HAS_DEPENDENT_PRICING_DATA: este mapeamento já tem produto/observação de preço vinculado — reclassificação direta bloqueada, fica reservada para um fluxo de reconciliação futuro.';
    END IF;
  END IF;

  IF v_row.match_status = 'REJECTED' AND p_new_status = 'CONFIRMED' THEN
    SELECT external_card_id, external_card_name INTO v_ext_id, v_ext_name
    FROM public.pricing_source_card_identity
    WHERE pricing_card_mapping_id = v_row.id AND identity_role = 'PRIMARY' AND match_status = 'CONFIRMED'
    LIMIT 1;

    IF v_ext_id IS NULL THEN
      RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NO_PRIMARY_IDENTITY: é necessária uma identity PRIMARY já confirmada antes de reclassificar para CONFIRMED.';
    END IF;
  END IF;

  UPDATE public.pricing_card_mapping SET
    match_status = p_new_status,
    match_method = CASE WHEN p_new_status = 'CONFIRMED' THEN 'ADMIN_MANUAL_CONFIRMATION' ELSE match_method END,
    external_card_id = COALESCE(v_ext_id, external_card_id),
    external_card_name = COALESCE(v_ext_name, external_card_name),
    confirmed_at = now(),
    confirmed_by = auth.uid(),
    updated_at = now()
  WHERE id = p_id;

  v_action := CASE p_new_status WHEN 'CONFIRMED' THEN 'PRICING_MAPPING_CONFIRMED' ELSE 'PRICING_MAPPING_REJECTED' END;
  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), v_action, 'PRICING_CARD_MAPPING', p_id,
    jsonb_build_object('old_status', v_row.match_status, 'new_status', p_new_status, 'reason', v_reason));
END;
$function$;
