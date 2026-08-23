-- Query 3940 — Backend do Bloco 2 do Pricing Admin (Pendências + Resolução de Mapeamentos)
-- Status: CONFIRMADO EXECUTADO em 2026-08-22 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: ampliar o vocabulário controlado de pricing_admin_action_log
-- (mesmo padrão de 3 CHECKs já usado em catalog_admin_action_log) para
-- aceitar PRICING_CARD_MAPPING/PRICING_MAPPING_CONFIRMED/
-- PRICING_MAPPING_REJECTED, e criar as 3 RPCs admin-only necessárias para
-- Pendências + Resolução de Mapeamentos:
--   - admin_list_pricing_pending_mappings — listagem paginada/filtrada
--     server-side (status PENDING/NOT_FOUND, Set, busca).
--   - admin_get_pricing_mapping_detail — carta, variantes locais,
--     candidatos externos (roles/qualifiers/preços), flag missing_variant.
--   - admin_resolve_pricing_mapping — write atômico único: CONFIRMED
--     (1..N identity_assignments, single ou multi-identity) ou REJECTED
--     (motivo obrigatório, não cria identity nova). Guardas: mapping deve
--     continuar PENDING/NOT_FOUND no momento do write (FOR UPDATE),
--     identidades do lote devem estar PENDING e pertencer ao mapping
--     (aborta em incompatibilidade), nunca cria card_variant_type, nunca
--     toca pricing_product/pricing_observation. Exatamente 1 audit log por
--     decisão.
--
-- Divergência de arquitetura identificada durante os testes (registrada
-- aqui e no relatório final do Bloco 2, não corrigida — é comportamento
-- correto do domínio, não um defeito): a trigger
-- validate_pricing_source_card_identity_canonical (BEFORE INSERT OR
-- UPDATE em pricing_source_card_identity) exige que o canonical_identity_id
-- de uma ALIAS já esteja match_status='CONFIRMED' com identity_role IN
-- ('PRIMARY','ALTERNATE') no momento do write. Logo, uma candidata ALIAS
-- PENDING nunca existe estruturalmente hoje (confirmado: zero linhas
-- ALIAS reais em todo o banco). A "Fase 2" desta função (confirmação de
-- ALIAS) é código defensivo/preparado para o futuro — nenhum
-- identity_assignment PENDING com identity_role=ALIAS chega a esse trecho
-- na V1. Multi-identity, na prática, é múltiplas candidatas
-- PRIMARY/ALTERNATE PENDING confirmadas juntas em uma única chamada.
--
-- Testado transacionalmente (BEGIN + toda a suíte + rollback automático
-- por fechamento de conexão, sem residual em produção) cobrindo os 9
-- requisitos obrigatórios de Fabrício: listagem PENDING+NOT_FOUND
-- (75+18=93, bate com baseline conhecido); filtro de status travado a
-- PENDING/NOT_FOUND mesmo se outro valor for passado; busca+paginação;
-- missing_variant=true/identity_count=0 em mapping real sem variantes
-- locais (Rillaboom); multi-identity CONFIRMED atômico (PRIMARY+ALTERNATE
-- sintéticas); exatamente 1 audit log PRICING_MAPPING_CONFIRMED;
-- reprocessamento bloqueado (ADMIN_RESOLVE_PRICING_MAPPING_ALREADY_DECIDED);
-- REJECTED com motivo vazio bloqueado
-- (ADMIN_RESOLVE_PRICING_MAPPING_REJECT_REASON_REQUIRED); REJECTED com
-- motivo real cria exatamente 1 audit log PRICING_MAPPING_REJECTED;
-- identity incompatível (já CONFIRMED por outro fluxo) bloqueada
-- (ADMIN_RESOLVE_PRICING_MAPPING_IDENTITY_INCOMPATIBLE); as 3 RPCs
-- rejeitam chamada não-admin/não-autenticada com o *_FORBIDDEN nomeado.
--
-- Pós-aplicação real: grants confirmados via information_schema.
-- role_routine_grants (apenas authenticated e postgres têm EXECUTE nas 3
-- funções novas, nenhum anon/PUBLIC). EXPLAIN ANALYZE em
-- admin_list_pricing_pending_mappings(NULL,NULL,NULL,20,0) como admin:
-- Execution Time 16.909 ms (Buffers: shared hit=1727). get_advisors
-- (security) completo (58 WARN + 11 INFO, zero ERROR/CRITICAL): as 3
-- funções novas só disparam o WARN
-- authenticated_security_definer_function_executable já aceito para
-- dezenas de outras RPCs admin do projeto; nenhuma classe nova de
-- achado introduzida por esta migration (o INFO rls_enabled_no_policy em
-- pricing_admin_action_log é o mesmo padrão pré-existente de
-- catalog_admin_action_log/admin_action_log — tabelas de audit log só são
-- acessadas via função SECURITY DEFINER, nunca diretamente).
--
-- Nota de implementação: o SELECT de admin_list_pricing_pending_mappings
-- exigiu casts explícitos ::text em c.name/c.collector_number/cs.code/
-- cs.name/ps.code — sem eles, a primeira execução falhou com
-- "42804: structure of query does not match function result type"
-- porque essas colunas são character varying(N) na origem e a
-- RETURNS TABLE declara text.
--
-- Como validar:
--   SELECT * FROM public.admin_list_pricing_pending_mappings(); -- como admin
--   SELECT public.admin_get_pricing_mapping_detail('<uuid de um mapping>');

-- 1) Ampliar CHECKs de pricing_admin_action_log (preservando vocabulário controlado)
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_check;
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_entity_type_check;
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_action_check
  CHECK (action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED'::text, 'PRICING_MAPPING_CONFIRMED'::text, 'PRICING_MAPPING_REJECTED'::text]));

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_entity_type_check
  CHECK (entity_type = ANY (ARRAY['PRICING_SOURCE'::text, 'PRICING_CARD_MAPPING'::text]));

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check
  CHECK (
    ((entity_type = 'PRICING_SOURCE'::text) AND (action = 'PRICING_REFRESH_FREQUENCY_CHANGED'::text))
    OR ((entity_type = 'PRICING_CARD_MAPPING'::text) AND (action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED'::text, 'PRICING_MAPPING_REJECTED'::text])))
  );

-- 2) admin_list_pricing_pending_mappings — paginação/filtro server-side
CREATE OR REPLACE FUNCTION public.admin_list_pricing_pending_mappings(
  p_status text[] DEFAULT ARRAY['PENDING', 'NOT_FOUND'],
  p_card_set_id uuid DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  card_id uuid,
  card_name text,
  collector_number text,
  collector_total integer,
  card_set_id uuid,
  card_set_code text,
  card_set_name text,
  pricing_source_id uuid,
  pricing_source_code text,
  match_status text,
  identity_count integer,
  last_checked_at timestamptz,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_limit int;
  v_offset int;
  v_search text;
  v_status text[];
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_PENDING_MAPPINGS_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');

  -- Vocabulário travado a PENDING/NOT_FOUND, independente do que for
  -- passado — esta RPC é exclusiva da fila de Pendências, nunca deve
  -- vazar CONFIRMED/REJECTED mesmo que o chamador passe um valor errado.
  v_status := ARRAY(SELECT x FROM unnest(COALESCE(p_status, ARRAY['PENDING', 'NOT_FOUND'])) AS x WHERE x IN ('PENDING', 'NOT_FOUND'));
  IF array_length(v_status, 1) IS NULL THEN
    v_status := ARRAY['PENDING', 'NOT_FOUND'];
  END IF;

  RETURN QUERY
  SELECT
    pcm.id, c.id, c.name::text, c.collector_number::text, c.collector_total,
    cs.id, cs.code::text, cs.name::text,
    pcm.pricing_source_id, ps.code::text,
    pcm.match_status,
    (SELECT count(*)::int FROM public.pricing_source_card_identity psci WHERE psci.pricing_card_mapping_id = pcm.id),
    pcm.last_checked_at,
    count(*) OVER() AS total_count
  FROM public.pricing_card_mapping pcm
  JOIN public.card c ON c.id = pcm.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
  JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id
  WHERE pcm.match_status = ANY(v_status)
    AND (p_card_set_id IS NULL OR cs.id = p_card_set_id)
    AND (
      v_search IS NULL
      OR c.name ILIKE '%' || v_search || '%'
      OR c.collector_number ILIKE '%' || v_search || '%'
    )
  ORDER BY cs.release_date DESC NULLS LAST, c.collector_order ASC NULLS LAST, pcm.id
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_pending_mappings(text[], uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_pending_mappings(text[], uuid, text, integer, integer) TO authenticated;

-- 3) admin_get_pricing_mapping_detail — carta, variantes locais, candidatos, preços
CREATE OR REPLACE FUNCTION public.admin_get_pricing_mapping_detail(p_mapping_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_MAPPING_DETAIL_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  SELECT jsonb_build_object(
    'mapping', jsonb_build_object(
      'id', pcm.id,
      'match_status', pcm.match_status,
      'match_method', pcm.match_method,
      'external_card_id', pcm.external_card_id,
      'external_card_name', pcm.external_card_name,
      'last_checked_at', pcm.last_checked_at,
      'pricing_source_id', pcm.pricing_source_id,
      'pricing_source_code', ps.code
    ),
    'card', jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'collector_number', c.collector_number,
      'collector_total', c.collector_total,
      'card_set_id', cs.id,
      'card_set_code', cs.code,
      'card_set_name', cs.name
    ),
    'local_variants', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cv.id,
        'variant_type_id', cvt.id,
        'code', cvt.code,
        'name', cvt.name,
        'is_default', cv.is_default
      ) ORDER BY cv.variant_order)
      FROM public.card_variant cv
      JOIN public.card_variant_type cvt ON cvt.id = cv.variant_type_id
      WHERE cv.card_id = c.id
    ), '[]'::jsonb),
    'identities', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', psci.id,
        'external_card_id', psci.external_card_id,
        'external_card_name', psci.external_card_name,
        'identity_role', psci.identity_role,
        'canonical_identity_id', psci.canonical_identity_id,
        'match_status', psci.match_status,
        'match_method', psci.match_method,
        'match_evidence', psci.match_evidence,
        'card_variant_type_id', psci.card_variant_type_id,
        'card_variant_type_name', cvt2.name,
        'external_variant_key', psci.external_variant_key,
        'last_checked_at', psci.last_checked_at,
        'prices', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'condition_id', o.condition_id,
            'price_type', o.price_type,
            'currency_code', o.currency_code,
            'market_label', o.market_label,
            'price', o.price,
            'observed_at', o.observed_at
          ) ORDER BY o.observed_at DESC)
          FROM public.pricing_product pp
          JOIN public.pricing_observation o ON o.pricing_product_id = pp.id
          WHERE pp.pricing_source_card_identity_id = psci.id
        ), '[]'::jsonb)
      ) ORDER BY psci.identity_role, psci.external_card_id)
      FROM public.pricing_source_card_identity psci
      LEFT JOIN public.card_variant_type cvt2 ON cvt2.id = psci.card_variant_type_id
      WHERE psci.pricing_card_mapping_id = pcm.id
    ), '[]'::jsonb),
    'missing_variant', NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id)
  )
  INTO v_result
  FROM public.pricing_card_mapping pcm
  JOIN public.card c ON c.id = pcm.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
  JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id
  WHERE pcm.id = p_mapping_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_MAPPING_DETAIL_NOT_FOUND: id=%', p_mapping_id;
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_mapping_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_mapping_detail(uuid) TO authenticated;

-- 4) admin_resolve_pricing_mapping — write atômico único (CONFIRMED | REJECTED)
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

  IF p_decision NOT IN ('CONFIRMED', 'REJECTED') THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_INVALID_DECISION: %', p_decision;
  END IF;

  -- Trava a linha e valida o estado atual — guarda contra reprocessamento
  -- concorrente (mapping deve continuar PENDING/NOT_FOUND no momento do write).
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

  IF p_decision = 'REJECTED' THEN
    IF p_reject_reason IS NULL OR BTRIM(p_reject_reason) = '' THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_REJECT_REASON_REQUIRED';
    END IF;

    -- REJECTED nunca cria identity nova — só marca o mapping.
    UPDATE public.pricing_card_mapping
    SET match_status = 'REJECTED', confirmed_by = v_actor
    WHERE id = p_mapping_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
      v_actor, 'PRICING_MAPPING_REJECTED', 'PRICING_CARD_MAPPING', p_mapping_id,
      jsonb_build_object(
        'previous_status', v_previous_status,
        'decision', 'REJECTED',
        'reject_reason', p_reject_reason
      )
    );

    RETURN jsonb_build_object('mapping_id', p_mapping_id, 'decision', 'REJECTED');
  END IF;

  -- CONFIRMED — exige 1..N identity_assignments válidos.
  IF p_identity_assignments IS NULL OR jsonb_array_length(p_identity_assignments) = 0 THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_ASSIGNMENTS_REQUIRED';
  END IF;

  -- Aborta se qualquer identity do lote não pertencer a este mapping ou já
  -- não estiver mais PENDING (identity CONFIRMED/REJECTED incompatível,
  -- ou id inexistente) — mesma trava de reprocessamento, no nível de identity.
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

  -- Fase 1: confirma PRIMARY/ALTERNATE (sem dependência de canonical).
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

  -- Fase 2: confirma ALIAS (canonical já CONFIRMED PRIMARY/ALTERNATE pela
  -- Fase 1, dentro da mesma transação — validate_pricing_source_card_identity_canonical
  -- exige isso). Dormante na V1 — ver nota de divergência no topo deste
  -- arquivo: nenhuma candidata ALIAS PENDING existe estruturalmente hoje.
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

  -- external_card_id/name do mapping vêm da identity PRIMARY confirmada
  -- nesta mesma chamada.
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
    jsonb_build_object(
      'previous_status', v_previous_status,
      'decision', 'CONFIRMED',
      'identity_assignments', p_identity_assignments
    )
  );

  RETURN jsonb_build_object('mapping_id', p_mapping_id, 'decision', 'CONFIRMED', 'external_card_id', v_ext_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_resolve_pricing_mapping(uuid, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_pricing_mapping(uuid, text, jsonb, text) TO authenticated;
