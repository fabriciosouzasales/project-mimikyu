-- CONFIRMADO EXECUTADO em 2026-08-22
-- =============================================================================
-- Migration 3942 — Pricing Admin: Cadastros (Bloco 4)
-- Fontes de Preço, Mapeamentos de Sets, Mapeamentos de Cartas (todos os
-- status, não só Pendências), Condições.
--
-- 4 RPCs de leitura + 6 RPCs de write, todas SECURITY DEFINER admin-only
-- (public.is_admin()), mesma disciplina de search_path/GRANT das migrations
-- 3939-3941. Uma função helper interna (NÃO exposta via GRANT) concentra a
-- checagem de dependência econômica downstream de um Set+fonte, reusada por
-- admin_update_pricing_set_mapping_details e admin_reclassify_pricing_set_mapping
-- — fonte única de verdade, pedido explícito de Fabrício.
--
-- Decisões de Fabrício embutidas neste desenho:
--   1. pricing_card_mapping CONFIRMED com pricing_product dependente: BLOQUEAR
--      reclassificação direta (RAISE nomeado). Reconciliação fica para fluxo futuro.
--   2. card_condition: is_active=false SEMPRE permitido, mesmo com histórico
--      dependente (pricing_observation/pricing_condition_mapping) — a desativação
--      preserva histórico, esse é o propósito. Nunca DELETE físico. Condição
--      inativa não pode receber novo pricing_condition_mapping.
--   3. pricing_set_mapping: editar external_set_id NUNCA dispara refresh
--      automático (dispatcher continua único executor); a alteração só marca
--      last_checked_at=NULL como sinal de "precisa revalidar". external_set_id
--      e a reclassificação CONFIRMED→REJECTED são BLOQUEADOS quando existe
--      dependência econômica downstream (card → pricing_card_mapping →
--      identities/products/observations) no Set+fonte; external_set_name
--      descritivo continua sempre editável (não muda identidade).
--   4. CONFIRMED↔REJECTED nunca é toggle simples: sempre reason obrigatório +
--      audit log, tanto para Set quanto para Card mapping.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Schema incremental — is_active em card_condition (não existia antes).
-- -----------------------------------------------------------------------------

ALTER TABLE public.card_condition
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.card_condition.is_active IS
  'Condições inativas ficam indisponíveis para novo pricing_condition_mapping, mas permanecem referenciáveis em pricing_observation existente (histórico nunca é apagado). Nunca há DELETE físico de card_condition.';

-- -----------------------------------------------------------------------------
-- 1. Amplia pricing_admin_action_log para os 4 novos tipos de entidade do
--    Bloco 4 (PRICING_SOURCE ganha uma ação nova; PRICING_CARD_MAPPING já
--    existe desde 3940 e é reaproveitada; PRICING_SET_MAPPING, CARD_CONDITION
--    e PRICING_CONDITION_MAPPING são novos).
-- -----------------------------------------------------------------------------

ALTER TABLE public.pricing_admin_action_log
  DROP CONSTRAINT pricing_admin_action_log_entity_type_check,
  DROP CONSTRAINT pricing_admin_action_log_action_check,
  DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_entity_type_check
    CHECK (entity_type = ANY (ARRAY[
      'PRICING_SOURCE', 'PRICING_CARD_MAPPING', 'PRICING_SET_MAPPING',
      'CARD_CONDITION', 'PRICING_CONDITION_MAPPING'
    ])),
  ADD CONSTRAINT pricing_admin_action_log_action_check
    CHECK (action = ANY (ARRAY[
      'PRICING_REFRESH_FREQUENCY_CHANGED', 'PRICING_SOURCE_UPDATED',
      'PRICING_MAPPING_CONFIRMED', 'PRICING_MAPPING_REJECTED',
      'PRICING_SET_MAPPING_DETAILS_UPDATED', 'PRICING_SET_MAPPING_CONFIRMED', 'PRICING_SET_MAPPING_REJECTED',
      'CARD_CONDITION_CREATED', 'CARD_CONDITION_UPDATED',
      'PRICING_CONDITION_MAPPING_UPDATED'
    ])),
  ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check
    CHECK (
      ((entity_type = 'PRICING_SOURCE') AND (action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED', 'PRICING_SOURCE_UPDATED'])))
      OR ((entity_type = 'PRICING_CARD_MAPPING') AND (action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED', 'PRICING_MAPPING_REJECTED'])))
      OR ((entity_type = 'PRICING_SET_MAPPING') AND (action = ANY (ARRAY['PRICING_SET_MAPPING_DETAILS_UPDATED', 'PRICING_SET_MAPPING_CONFIRMED', 'PRICING_SET_MAPPING_REJECTED'])))
      OR ((entity_type = 'CARD_CONDITION') AND (action = ANY (ARRAY['CARD_CONDITION_CREATED', 'CARD_CONDITION_UPDATED'])))
      OR ((entity_type = 'PRICING_CONDITION_MAPPING') AND (action = 'PRICING_CONDITION_MAPPING_UPDATED'))
    );

-- -----------------------------------------------------------------------------
-- 2. Helpers internos de dependência — NUNCA expostos via GRANT a
--    authenticated/anon (REVOKE ALL FROM PUBLIC no fim). São a fonte única de
--    verdade da checagem de dependência econômica, reusados pelas RPCs de
--    write e pelas RPCs de leitura (para sinalizar "protegido" na UI sem
--    round trip extra).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.pricing_set_mapping_dependency_exists(p_card_set_id uuid, p_pricing_source_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.pricing_card_mapping pcm
    JOIN public.card c ON c.id = pcm.card_id
    WHERE c.card_set_id = p_card_set_id
      AND pcm.pricing_source_id = p_pricing_source_id
      AND (
        pcm.match_status = 'CONFIRMED'
        OR EXISTS (SELECT 1 FROM public.pricing_product pp WHERE pp.pricing_card_mapping_id = pcm.id)
        OR EXISTS (SELECT 1 FROM public.pricing_source_card_identity psci WHERE psci.pricing_card_mapping_id = pcm.id)
      )
  );
$function$;

COMMENT ON FUNCTION public.pricing_set_mapping_dependency_exists(uuid, uuid) IS
  'Fonte única de verdade: existe algum pricing_card_mapping CONFIRMED, ou com pricing_product/pricing_source_card_identity vinculado, para este Set+fonte. Reusada por admin_update_pricing_set_mapping_details, admin_reclassify_pricing_set_mapping e admin_list_pricing_set_mappings. Função interna — nunca GRANT a authenticated/anon.';

REVOKE ALL ON FUNCTION public.pricing_set_mapping_dependency_exists(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.pricing_card_mapping_dependency_exists(p_pricing_card_mapping_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.pricing_product pp WHERE pp.pricing_card_mapping_id = p_pricing_card_mapping_id);
$function$;

COMMENT ON FUNCTION public.pricing_card_mapping_dependency_exists(uuid) IS
  'Fonte única de verdade: existe pricing_product (logo, pricing_observation) vinculado a este mapping. Reusada por admin_reclassify_pricing_card_mapping e admin_list_pricing_card_mappings. Função interna — nunca GRANT a authenticated/anon.';

REVOKE ALL ON FUNCTION public.pricing_card_mapping_dependency_exists(uuid) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3. RPCs de leitura (paginadas server-side onde o volume justifica).
-- -----------------------------------------------------------------------------

-- 3.1 Fontes de Preço — hoje 1 linha (JUSTTCG), sem paginação.
CREATE OR REPLACE FUNCTION public.admin_list_pricing_sources()
RETURNS TABLE (
  id uuid, code text, name text, source_type text, default_market_scope text, base_currency text,
  base_url text, api_base_url text, documentation_url text, terms_url text, attribution_text text,
  requires_commercial_agreement boolean, supports_api boolean, is_active boolean, source_order integer,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_LIST_PRICING_SOURCES_FORBIDDEN: acesso restrito a administradores.'; END IF;
  RETURN QUERY
  SELECT ps.id, ps.code::text, ps.name::text, ps.source_type::text, ps.default_market_scope::text, ps.base_currency::text,
    ps.base_url::text, ps.api_base_url::text, ps.documentation_url::text, ps.terms_url::text, ps.attribution_text::text,
    ps.requires_commercial_agreement, ps.supports_api, ps.is_active, ps.source_order, ps.updated_at
  FROM public.pricing_source ps
  ORDER BY ps.source_order ASC, ps.code ASC;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_sources() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_sources() TO authenticated;

-- 3.2 Mapeamentos de Sets — paginado/filtrado, com has_dependency embutido.
CREATE OR REPLACE FUNCTION public.admin_list_pricing_set_mappings(
  p_status text[] DEFAULT NULL,
  p_pricing_source_id uuid DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid, card_set_id uuid, card_set_code text, card_set_name text,
  pricing_source_id uuid, pricing_source_code text,
  external_set_id text, external_set_name text, match_status text, match_method text,
  last_checked_at timestamptz, has_dependency boolean, total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_limit int; v_offset int; v_search text; v_status text[];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_LIST_PRICING_SET_MAPPINGS_FORBIDDEN: acesso restrito a administradores.'; END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');
  v_status := NULLIF(ARRAY(SELECT x FROM unnest(p_status) AS x WHERE x IN ('CONFIRMED', 'PENDING', 'NOT_FOUND', 'REJECTED')), ARRAY[]::text[]);

  RETURN QUERY
  SELECT psm.id, cs.id, cs.code::text, cs.name::text,
    psm.pricing_source_id, ps.code::text,
    psm.external_set_id::text, psm.external_set_name::text, psm.match_status, psm.match_method,
    psm.last_checked_at,
    public.pricing_set_mapping_dependency_exists(cs.id, psm.pricing_source_id),
    count(*) OVER() AS total_count
  FROM public.pricing_set_mapping psm
  JOIN public.card_set cs ON cs.id = psm.card_set_id
  JOIN public.pricing_source ps ON ps.id = psm.pricing_source_id
  WHERE (v_status IS NULL OR psm.match_status = ANY(v_status))
    AND (p_pricing_source_id IS NULL OR psm.pricing_source_id = p_pricing_source_id)
    AND (v_search IS NULL OR cs.name ILIKE '%' || v_search || '%' OR cs.code ILIKE '%' || v_search || '%')
  ORDER BY cs.release_date DESC NULLS LAST, cs.code ASC
  LIMIT v_limit OFFSET v_offset;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer) TO authenticated;

-- 3.3 Mapeamentos de Cartas — todos os status (inclui CONFIRMED/REJECTED,
--     não só Pendências); mesmo padrão de admin_list_pricing_pending_mappings
--     (migration 3940), mas sem travar o vocabulário de status.
CREATE OR REPLACE FUNCTION public.admin_list_pricing_card_mappings(
  p_status text[] DEFAULT NULL,
  p_pricing_source_id uuid DEFAULT NULL,
  p_card_set_id uuid DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid, card_id uuid, card_name text, collector_number text, collector_total integer,
  card_set_id uuid, card_set_code text, card_set_name text,
  pricing_source_id uuid, pricing_source_code text,
  external_card_id text, external_card_name text, match_status text, match_method text,
  identity_count integer, last_checked_at timestamptz, has_dependency boolean, total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_limit int; v_offset int; v_search text; v_status text[];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_LIST_PRICING_CARD_MAPPINGS_FORBIDDEN: acesso restrito a administradores.'; END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');
  v_status := NULLIF(ARRAY(SELECT x FROM unnest(p_status) AS x WHERE x IN ('CONFIRMED', 'PENDING', 'NOT_FOUND', 'REJECTED')), ARRAY[]::text[]);

  RETURN QUERY
  SELECT pcm.id, c.id, c.name::text, c.collector_number::text, c.collector_total,
    cs.id, cs.code::text, cs.name::text,
    pcm.pricing_source_id, ps.code::text,
    pcm.external_card_id::text, pcm.external_card_name::text, pcm.match_status, pcm.match_method,
    (SELECT count(*)::int FROM public.pricing_source_card_identity psci WHERE psci.pricing_card_mapping_id = pcm.id),
    pcm.last_checked_at,
    public.pricing_card_mapping_dependency_exists(pcm.id),
    count(*) OVER() AS total_count
  FROM public.pricing_card_mapping pcm
  JOIN public.card c ON c.id = pcm.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
  JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id
  WHERE (v_status IS NULL OR pcm.match_status = ANY(v_status))
    AND (p_pricing_source_id IS NULL OR pcm.pricing_source_id = p_pricing_source_id)
    AND (p_card_set_id IS NULL OR cs.id = p_card_set_id)
    AND (v_search IS NULL OR c.name ILIKE '%' || v_search || '%' OR c.collector_number ILIKE '%' || v_search || '%')
  ORDER BY cs.release_date DESC NULLS LAST, c.collector_order ASC NULLS LAST, pcm.id
  LIMIT v_limit OFFSET v_offset;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_card_mappings(text[], uuid, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_card_mappings(text[], uuid, uuid, text, integer, integer) TO authenticated;

-- 3.4 Condições — hoje 5 linhas, sem paginação; cada condição traz seus
--     pricing_condition_mapping aninhados (hoje 1:1, mas o formato já
--     suporta N fontes futuras).
CREATE OR REPLACE FUNCTION public.admin_list_card_conditions()
RETURNS TABLE (
  id uuid, code text, name text, condition_order integer, is_active boolean,
  has_dependent_observations boolean, mappings jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_LIST_CARD_CONDITIONS_FORBIDDEN: acesso restrito a administradores.'; END IF;
  RETURN QUERY
  SELECT cc.id, cc.code::text, cc.name::text, cc.condition_order, cc.is_active,
    EXISTS (SELECT 1 FROM public.pricing_observation o WHERE o.condition_id = cc.id),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pcm.id, 'pricing_source_id', pcm.pricing_source_id, 'pricing_source_code', ps.code,
        'external_condition_code', pcm.external_condition_code
      ) ORDER BY ps.code)
      FROM public.pricing_condition_mapping pcm JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id
      WHERE pcm.condition_id = cc.id
    ), '[]'::jsonb)
  FROM public.card_condition cc
  ORDER BY cc.condition_order ASC;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_list_card_conditions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_card_conditions() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. RPCs de write.
-- -----------------------------------------------------------------------------

-- 4.1 Fontes — só toggle+metadados; nunca frequency_days (isso é
--     admin_set_pricing_refresh_frequency, migration 3937/3938).
CREATE OR REPLACE FUNCTION public.admin_update_pricing_source(
  p_pricing_source_id uuid,
  p_name text,
  p_base_url text,
  p_api_base_url text,
  p_documentation_url text,
  p_terms_url text,
  p_attribution_text text,
  p_requires_commercial_agreement boolean,
  p_supports_api boolean,
  p_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_before public.pricing_source;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_UPDATE_PRICING_SOURCE_FORBIDDEN: acesso restrito a administradores.'; END IF;

  SELECT * INTO v_before FROM public.pricing_source WHERE id = p_pricing_source_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_UPDATE_PRICING_SOURCE_NOT_FOUND: id=%', p_pricing_source_id; END IF;

  IF NULLIF(BTRIM(p_name), '') IS NULL THEN RAISE EXCEPTION 'ADMIN_UPDATE_PRICING_SOURCE_MISSING_NAME'; END IF;

  UPDATE public.pricing_source SET
    name = BTRIM(p_name),
    base_url = NULLIF(BTRIM(p_base_url), ''),
    api_base_url = NULLIF(BTRIM(p_api_base_url), ''),
    documentation_url = NULLIF(BTRIM(p_documentation_url), ''),
    terms_url = NULLIF(BTRIM(p_terms_url), ''),
    attribution_text = NULLIF(BTRIM(p_attribution_text), ''),
    requires_commercial_agreement = p_requires_commercial_agreement,
    supports_api = p_supports_api,
    is_active = p_is_active,
    updated_at = now()
  WHERE id = p_pricing_source_id;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'PRICING_SOURCE_UPDATED', 'PRICING_SOURCE', p_pricing_source_id,
    jsonb_build_object('before', to_jsonb(v_before), 'is_active', p_is_active));
END; $function$;

REVOKE ALL ON FUNCTION public.admin_update_pricing_source(uuid, text, text, text, text, text, text, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_pricing_source(uuid, text, text, text, text, text, text, boolean, boolean, boolean) TO authenticated;

-- 4.2 Mapeamentos de Sets — detalhes cadastrais. external_set_name sempre
--     editável; external_set_id protegido por dependência (fonte única:
--     pricing_set_mapping_dependency_exists). Nunca dispara refresh — só
--     sinaliza revalidação (last_checked_at=NULL) quando o identificador
--     externo realmente muda.
CREATE OR REPLACE FUNCTION public.admin_update_pricing_set_mapping_details(
  p_id uuid,
  p_external_set_id text,
  p_external_set_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_row public.pricing_set_mapping; v_new_external_id text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_UPDATE_PRICING_SET_MAPPING_DETAILS_FORBIDDEN: acesso restrito a administradores.'; END IF;

  SELECT * INTO v_row FROM public.pricing_set_mapping WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_UPDATE_PRICING_SET_MAPPING_DETAILS_NOT_FOUND: id=%', p_id; END IF;

  v_new_external_id := NULLIF(BTRIM(p_external_set_id), '');

  IF v_new_external_id IS DISTINCT FROM v_row.external_set_id THEN
    IF public.pricing_set_mapping_dependency_exists(v_row.card_set_id, v_row.pricing_source_id) THEN
      RAISE EXCEPTION 'SET_MAPPING_HAS_DEPENDENT_PRICING_DATA: este Set+fonte já tem mapeamentos de carta confirmados ou dados de preço vinculados — alterar o identificador externo fica reservado para um fluxo de reconciliação futuro.';
    END IF;

    UPDATE public.pricing_set_mapping SET
      external_set_id = v_new_external_id,
      external_set_name = NULLIF(BTRIM(p_external_set_name), ''),
      last_checked_at = NULL,
      updated_at = now()
    WHERE id = p_id;
  ELSE
    UPDATE public.pricing_set_mapping SET
      external_set_name = NULLIF(BTRIM(p_external_set_name), ''),
      updated_at = now()
    WHERE id = p_id;
  END IF;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'PRICING_SET_MAPPING_DETAILS_UPDATED', 'PRICING_SET_MAPPING', p_id,
    jsonb_build_object(
      'old_external_set_id', v_row.external_set_id, 'new_external_set_id', v_new_external_id,
      'old_external_set_name', v_row.external_set_name, 'new_external_set_name', NULLIF(BTRIM(p_external_set_name), '')
    ));
END; $function$;

REVOKE ALL ON FUNCTION public.admin_update_pricing_set_mapping_details(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_pricing_set_mapping_details(uuid, text, text) TO authenticated;

-- 4.3 Mapeamentos de Sets — reclassificação CONFIRMED<->REJECTED. Nunca
--     toggle simples: reason obrigatório, guardado pela mesma fonte única de
--     verdade quando a direção é CONFIRMED->REJECTED (a única que pode
--     descartar um vínculo com dados de preço reais).
CREATE OR REPLACE FUNCTION public.admin_reclassify_pricing_set_mapping(
  p_id uuid,
  p_new_status text,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_row public.pricing_set_mapping; v_reason text; v_action text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_SET_MAPPING_FORBIDDEN: acesso restrito a administradores.'; END IF;

  IF p_new_status NOT IN ('CONFIRMED', 'REJECTED') THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_SET_MAPPING_INVALID_STATUS: só CONFIRMED ou REJECTED.';
  END IF;

  v_reason := NULLIF(BTRIM(p_reason), '');
  IF v_reason IS NULL THEN RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_SET_MAPPING_MISSING_REASON'; END IF;

  SELECT * INTO v_row FROM public.pricing_set_mapping WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_SET_MAPPING_NOT_FOUND: id=%', p_id; END IF;

  IF v_row.match_status NOT IN ('CONFIRMED', 'REJECTED') THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_SET_MAPPING_INVALID_CURRENT_STATUS: só reclassifica CONFIRMED/REJECTED — % use o fluxo normal de confirmação.', v_row.match_status;
  END IF;

  IF v_row.match_status = p_new_status THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_SET_MAPPING_NO_OP: já está %.', p_new_status;
  END IF;

  IF v_row.match_status = 'CONFIRMED' AND p_new_status = 'REJECTED' THEN
    IF public.pricing_set_mapping_dependency_exists(v_row.card_set_id, v_row.pricing_source_id) THEN
      RAISE EXCEPTION 'SET_MAPPING_HAS_DEPENDENT_PRICING_DATA: este Set+fonte já tem mapeamentos de carta confirmados ou dados de preço vinculados — reclassificação fica reservada para um fluxo de reconciliação futuro.';
    END IF;
  END IF;

  UPDATE public.pricing_set_mapping SET
    match_status = p_new_status,
    confirmed_at = now(),
    confirmed_by = auth.uid(),
    updated_at = now()
  WHERE id = p_id;

  v_action := CASE p_new_status WHEN 'CONFIRMED' THEN 'PRICING_SET_MAPPING_CONFIRMED' ELSE 'PRICING_SET_MAPPING_REJECTED' END;
  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), v_action, 'PRICING_SET_MAPPING', p_id,
    jsonb_build_object('old_status', v_row.match_status, 'new_status', p_new_status, 'reason', v_reason));
END; $function$;

REVOKE ALL ON FUNCTION public.admin_reclassify_pricing_set_mapping(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reclassify_pricing_set_mapping(uuid, text, text) TO authenticated;

-- 4.4 Mapeamentos de Cartas — reclassificação CONFIRMED<->REJECTED.
--     CONFIRMED->REJECTED é BLOQUEADO se existir pricing_product dependente
--     (decisão 1 de Fabrício) — nunca reconciliado automaticamente aqui.
CREATE OR REPLACE FUNCTION public.admin_reclassify_pricing_card_mapping(
  p_id uuid,
  p_new_status text,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_row public.pricing_card_mapping; v_reason text; v_action text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_FORBIDDEN: acesso restrito a administradores.'; END IF;

  IF p_new_status NOT IN ('CONFIRMED', 'REJECTED') THEN
    RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_INVALID_STATUS: só CONFIRMED ou REJECTED.';
  END IF;

  v_reason := NULLIF(BTRIM(p_reason), '');
  IF v_reason IS NULL THEN RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_MISSING_REASON'; END IF;

  SELECT * INTO v_row FROM public.pricing_card_mapping WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NOT_FOUND: id=%', p_id; END IF;

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

  UPDATE public.pricing_card_mapping SET
    match_status = p_new_status,
    confirmed_at = now(),
    confirmed_by = auth.uid(),
    updated_at = now()
  WHERE id = p_id;

  v_action := CASE p_new_status WHEN 'CONFIRMED' THEN 'PRICING_MAPPING_CONFIRMED' ELSE 'PRICING_MAPPING_REJECTED' END;
  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), v_action, 'PRICING_CARD_MAPPING', p_id,
    jsonb_build_object('old_status', v_row.match_status, 'new_status', p_new_status, 'reason', v_reason));
END; $function$;

REVOKE ALL ON FUNCTION public.admin_reclassify_pricing_card_mapping(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reclassify_pricing_card_mapping(uuid, text, text) TO authenticated;

-- 4.5 Condições — create/edit; código/nome únicos (UNIQUE já existente na
--     tabela); is_active=false SEMPRE permitido mesmo com histórico
--     dependente (decisão 2 de Fabrício); nunca DELETE físico em nenhum
--     caminho desta RPC.
CREATE OR REPLACE FUNCTION public.admin_upsert_card_condition(
  p_id uuid,
  p_code text,
  p_name text,
  p_condition_order integer,
  p_is_active boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_code text; v_name text; v_id uuid; v_before public.card_condition; v_action text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_FORBIDDEN: acesso restrito a administradores.'; END IF;

  v_code := NULLIF(BTRIM(p_code), '');
  v_name := NULLIF(BTRIM(p_name), '');
  IF v_code IS NULL THEN RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_MISSING_CODE'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_MISSING_NAME'; END IF;
  IF p_condition_order IS NULL OR p_condition_order < 1 THEN RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_INVALID_ORDER'; END IF;

  IF p_id IS NULL THEN
    IF EXISTS (SELECT 1 FROM public.card_condition WHERE code = v_code) THEN
      RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_DUPLICATE_CODE: código % já cadastrado.', v_code;
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_condition WHERE name = v_name) THEN
      RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_DUPLICATE_NAME: nome % já cadastrado.', v_name;
    END IF;

    INSERT INTO public.card_condition (code, name, condition_order, is_active)
    VALUES (v_code, v_name, p_condition_order, COALESCE(p_is_active, true))
    RETURNING id INTO v_id;

    v_action := 'CARD_CONDITION_CREATED';
    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_action, 'CARD_CONDITION', v_id,
      jsonb_build_object('code', v_code, 'name', v_name, 'condition_order', p_condition_order, 'is_active', COALESCE(p_is_active, true)));
  ELSE
    SELECT * INTO v_before FROM public.card_condition WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_NOT_FOUND: id=%', p_id; END IF;

    IF EXISTS (SELECT 1 FROM public.card_condition WHERE code = v_code AND id <> p_id) THEN
      RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_DUPLICATE_CODE: código % já cadastrado.', v_code;
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_condition WHERE name = v_name AND id <> p_id) THEN
      RAISE EXCEPTION 'ADMIN_UPSERT_CARD_CONDITION_DUPLICATE_NAME: nome % já cadastrado.', v_name;
    END IF;

    UPDATE public.card_condition SET
      code = v_code, name = v_name, condition_order = p_condition_order, is_active = COALESCE(p_is_active, true),
      updated_at = now()
    WHERE id = p_id;
    v_id := p_id;

    v_action := 'CARD_CONDITION_UPDATED';
    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_action, 'CARD_CONDITION', v_id,
      jsonb_build_object('before', to_jsonb(v_before), 'code', v_code, 'name', v_name, 'condition_order', p_condition_order, 'is_active', COALESCE(p_is_active, true)));
  END IF;

  RETURN v_id;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_upsert_card_condition(uuid, text, text, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_card_condition(uuid, text, text, integer, boolean) TO authenticated;

-- 4.6 Vínculo Condição<->Fonte externa — create/edit; nunca aponta para
--     condição inativa (decisão 2 de Fabrício); sem DELETE físico.
CREATE OR REPLACE FUNCTION public.admin_upsert_pricing_condition_mapping(
  p_id uuid,
  p_pricing_source_id uuid,
  p_external_condition_code text,
  p_condition_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_external_code text; v_condition_active boolean; v_id uuid; v_before public.pricing_condition_mapping;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_UPSERT_PRICING_CONDITION_MAPPING_FORBIDDEN: acesso restrito a administradores.'; END IF;

  v_external_code := NULLIF(BTRIM(p_external_condition_code), '');
  IF v_external_code IS NULL THEN RAISE EXCEPTION 'ADMIN_UPSERT_PRICING_CONDITION_MAPPING_MISSING_EXTERNAL_CODE'; END IF;
  IF p_pricing_source_id IS NULL THEN RAISE EXCEPTION 'ADMIN_UPSERT_PRICING_CONDITION_MAPPING_MISSING_SOURCE'; END IF;
  IF p_condition_id IS NULL THEN RAISE EXCEPTION 'ADMIN_UPSERT_PRICING_CONDITION_MAPPING_MISSING_CONDITION'; END IF;

  SELECT is_active INTO v_condition_active FROM public.card_condition WHERE id = p_condition_id;
  IF v_condition_active IS NULL THEN RAISE EXCEPTION 'ADMIN_UPSERT_PRICING_CONDITION_MAPPING_CONDITION_NOT_FOUND: id=%', p_condition_id; END IF;
  IF NOT v_condition_active THEN
    RAISE EXCEPTION 'CONDITION_INACTIVE_CANNOT_RECEIVE_MAPPING: a condição % está inativa — reative-a antes de vinculá-la a uma fonte.', p_condition_id;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.pricing_condition_mapping (pricing_source_id, external_condition_code, condition_id)
    VALUES (p_pricing_source_id, v_external_code, p_condition_id)
    RETURNING id INTO v_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_CONDITION_MAPPING_UPDATED', 'PRICING_CONDITION_MAPPING', v_id,
      jsonb_build_object('created', true, 'pricing_source_id', p_pricing_source_id, 'external_condition_code', v_external_code, 'condition_id', p_condition_id));
  ELSE
    SELECT * INTO v_before FROM public.pricing_condition_mapping WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'ADMIN_UPSERT_PRICING_CONDITION_MAPPING_NOT_FOUND: id=%', p_id; END IF;

    UPDATE public.pricing_condition_mapping SET
      external_condition_code = v_external_code, condition_id = p_condition_id, updated_at = now()
    WHERE id = p_id;
    v_id := p_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_CONDITION_MAPPING_UPDATED', 'PRICING_CONDITION_MAPPING', v_id,
      jsonb_build_object('before', to_jsonb(v_before), 'external_condition_code', v_external_code, 'condition_id', p_condition_id));
  END IF;

  RETURN v_id;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_upsert_pricing_condition_mapping(uuid, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_pricing_condition_mapping(uuid, uuid, text, uuid) TO authenticated;
