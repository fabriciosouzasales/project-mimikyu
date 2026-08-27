-- Query 3964 — Confirmação por candidato de match_evidence + hardening NOT_FOUND +
-- fila PENDING/REJECTED + thumbnail em Mapeamentos de Cartas
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: fechar o fluxo dos 75 PENDING ambíguos atuais sem materializar
-- identity para candidatos não escolhidos (decisão explícita de Fabrício,
-- 2026-08-27, revisão da proposta anterior que criava todas as PENDING de
-- uma vez). admin_resolve_pricing_mapping ganha um caminho novo de CONFIRMED
-- (por candidato de match_evidence, sem identity_assignments) e um guard novo
-- em NOT_FOUND (bloqueado se a evidência já persistida mostrar candidatos).
-- admin_list_pricing_card_mapping_issues perde NOT_FOUND do vocabulário (item
-- sai da fila assim que decidido) e ganha thumbnail (storage_path bruto, sem
-- URL pronta, sem nova chamada externa).
--
-- Vocabulário de match_method: confirmado ausência de qualquer CHECK
-- constraint em pricing_card_mapping.match_method /
-- pricing_source_card_identity.match_method (coluna livre) — decisão de
-- Fabrício de não criar um rótulo novo respeitada: o caminho novo reusa
-- 'ADMIN_MANUAL_CONFIRMATION', já usado pelo caminho existente de
-- identity_assignments. A proveniência (veio de match_evidence.candidatos,
-- não de uma identity PENDING pré-existente) fica registrada no próprio
-- match_evidence da nova identity e no metadata do action log — não precisa
-- de um método novo para ser rastreável.
--
-- Hardening de identidade (a pedido de Fabrício): nunca depende só do
-- ON CONFLICT ON CONSTRAINT uq_pricing_source_card_identity_mapping_external.
-- Antes do INSERT, busca a PRIMARY ativa (PENDING/CONFIRMED) do mapping:
--   - nenhuma -> cria a escolhida;
--   - mesma external_card_id -> reutiliza (promove se ainda PENDING, no-op se
--     já CONFIRMED);
--   - external_card_id diferente -> bloqueia com erro de domínio explícito
--     (ADMIN_RESOLVE_PRICING_MAPPING_PRIMARY_IDENTITY_CONFLICT) antes de
--     qualquer INSERT — nunca cria duas PRIMARY economicamente conflitantes
--     para o mesmo mapping. O SELECT ... FOR UPDATE já feito em
--     pricing_card_mapping no topo da função serializa esta checagem (só uma
--     sessão por vez resolve o mesmo mapping_id).
--
-- Como validar:
--   SELECT public.admin_resolve_pricing_mapping('<mapping_id>', 'CONFIRMED', NULL, NULL, '<external_card_id>');
--   SELECT * FROM public.admin_list_pricing_card_mapping_issues(); -- nunca mais devolve NOT_FOUND

-- DROP necessário: adicionar p_candidate_external_card_id muda a lista de
-- tipos de parâmetros posicionais (4 -> 5) — Postgres trataria isso como um
-- OVERLOAD novo em vez de substituir o existente (CREATE OR REPLACE só
-- substitui quando a lista de tipos é idêntica), deixando as duas versões
-- coexistirem e tornando qualquer chamada com 4 argumentos ambígua
-- ("function is not unique"). DROP explícito da assinatura antiga evita isso.
DROP FUNCTION IF EXISTS public.admin_resolve_pricing_mapping(uuid, text, jsonb, text);

CREATE FUNCTION public.admin_resolve_pricing_mapping(
  p_mapping_id uuid,
  p_decision text,
  p_identity_assignments jsonb DEFAULT NULL,
  p_reject_reason text DEFAULT NULL,
  p_candidate_external_card_id text DEFAULT NULL
) RETURNS jsonb
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
  v_candidatos jsonb;
  v_candidato jsonb;
  v_existing_primary public.pricing_source_card_identity;
  v_identity_id uuid;
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
  v_candidatos := COALESCE(v_mapping.match_evidence -> 'candidatos', '[]'::jsonb);

  IF p_decision = 'NOT_FOUND' THEN
    IF v_previous_status = 'NOT_FOUND' THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NO_OP: id=% já está NOT_FOUND.', p_mapping_id;
    END IF;

    -- Hardening 2026-08-27: NOT_FOUND só é aceito quando a evidência já
    -- persistida (match_evidence.candidatos) provar zero candidatos. Se
    -- houver qualquer candidato registrado na última classificação, o caso é
    -- AMBIGUOUS (não ABSENT) e precisa ser resolvido escolhendo um candidato,
    -- nunca marcado como ausência.
    IF jsonb_array_length(v_candidatos) > 0 THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_HAS_CANDIDATES: id=% possui % candidato(s) em match_evidence — resolva escolhendo um candidato.', p_mapping_id, jsonb_array_length(v_candidatos);
    END IF;

    IF p_identity_assignments IS NOT NULL AND jsonb_array_length(p_identity_assignments) > 0 THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_ASSIGNMENTS_NOT_ALLOWED';
    END IF;

    IF p_reject_reason IS NULL OR BTRIM(p_reject_reason) = '' THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND_REASON_REQUIRED';
    END IF;

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
    -- Inalterado: REJECTED continua no nível do mapping, nunca por candidato
    -- individual (decisão de Fabrício, 2026-08-27) — com múltiplos
    -- candidatos, significa "nenhuma das alternativas analisadas corresponde
    -- a esta carta", não a rejeição de uma identity específica. Nenhuma
    -- linha de pricing_source_card_identity é tocada aqui.
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

  -- CONFIRMED — dois caminhos mutuamente exclusivos a partir daqui:
  --   (a) p_candidate_external_card_id: novo caminho (2026-08-27), confirma
  --       exatamente 1 candidato lido de match_evidence.candidatos, sem
  --       depender de identity PENDING pré-existente;
  --   (b) p_identity_assignments: caminho original (migration 3940),
  --       inalterado — promove 1..N identities PENDING já persistidas.
  IF p_candidate_external_card_id IS NOT NULL THEN
    IF p_identity_assignments IS NOT NULL AND jsonb_array_length(p_identity_assignments) > 0 THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_CANDIDATE_ASSIGNMENTS_CONFLICT: informe candidato OU identity_assignments, nunca os dois.';
    END IF;

    SELECT elem INTO v_candidato
    FROM jsonb_array_elements(v_candidatos) elem
    WHERE elem ->> 'id' = p_candidate_external_card_id;

    IF v_candidato IS NULL THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_CANDIDATE_NOT_IN_EVIDENCE: mapping=% external_card_id=% não consta em match_evidence.candidatos.', p_mapping_id, p_candidate_external_card_id;
    END IF;

    -- Hardening de identidade: nunca confiar só no ON CONFLICT da unique
    -- constraint — checar explicitamente o estado atual antes de escrever.
    SELECT * INTO v_existing_primary
    FROM public.pricing_source_card_identity
    WHERE pricing_card_mapping_id = p_mapping_id
      AND identity_role = 'PRIMARY'
      AND match_status IN ('PENDING', 'CONFIRMED');

    IF v_existing_primary IS NULL THEN
      INSERT INTO public.pricing_source_card_identity (
        pricing_card_mapping_id, pricing_source_id,
        external_card_id, external_card_name,
        match_status, identity_role, confirmed_by,
        match_method, match_evidence, last_checked_at
      ) VALUES (
        p_mapping_id, v_mapping.pricing_source_id,
        v_candidato ->> 'id', v_candidato ->> 'name',
        'CONFIRMED', 'PRIMARY', v_actor,
        'ADMIN_MANUAL_CONFIRMATION',
        jsonb_build_object(
          'origem', 'match_evidence.candidatos',
          'external_card_id', v_candidato ->> 'id',
          'external_card_name', v_candidato ->> 'name',
          'external_number', v_candidato ->> 'number',
          'mapping_match_method', v_mapping.match_method
        ),
        now()
      )
      RETURNING id INTO v_identity_id;
    ELSIF v_existing_primary.external_card_id = p_candidate_external_card_id THEN
      -- Reentrância/retry: a identity já existe (ex.: chamada duplicada) —
      -- reutiliza em vez de criar de novo. Promove se ainda PENDING; se já
      -- CONFIRMED, segue sem escrita adicional (idempotente).
      v_identity_id := v_existing_primary.id;
      IF v_existing_primary.match_status = 'PENDING' THEN
        UPDATE public.pricing_source_card_identity
        SET match_status = 'CONFIRMED', confirmed_by = v_actor, match_method = 'ADMIN_MANUAL_CONFIRMATION'
        WHERE id = v_existing_primary.id;
      END IF;
    ELSE
      -- Já existe uma PRIMARY ativa apontando para OUTRO external_card_id —
      -- nunca criar uma segunda PRIMARY economicamente conflitante para o
      -- mesmo mapping (reforça uq_pricing_source_card_identity_active_primary_per_mapping
      -- com um erro de domínio explícito, em vez de deixar estourar a unique
      -- violation crua).
      RAISE EXCEPTION 'ADMIN_RESOLVE_PRICING_MAPPING_PRIMARY_IDENTITY_CONFLICT: mapping=% já tem PRIMARY ativa (external_card_id=%), incompatível com o candidato escolhido (external_card_id=%).',
        p_mapping_id, v_existing_primary.external_card_id, p_candidate_external_card_id;
    END IF;

    v_ext_id := v_candidato ->> 'id';
    v_ext_name := v_candidato ->> 'name';

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
        'previous_status', v_previous_status, 'decision', 'CONFIRMED',
        'source', 'match_evidence_candidate',
        'candidate', v_candidato,
        'identity_id', v_identity_id
      )
    );

    RETURN jsonb_build_object('mapping_id', p_mapping_id, 'decision', 'CONFIRMED', 'external_card_id', v_ext_id);
  END IF;

  -- Caminho original (migration 3940) — inalterado, byte a byte.
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

REVOKE ALL ON FUNCTION public.admin_resolve_pricing_mapping(uuid, text, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_pricing_mapping(uuid, text, jsonb, text, text) TO authenticated;

-- ============================================================================
-- admin_list_pricing_card_mapping_issues — vocabulário PENDING/REJECTED
-- (NOT_FOUND some da fila assim que decidido, decisão de Fabrício
-- 2026-08-27) + thumbnail (storage_path bruto do card_asset primário
-- CARD_FRONT, prioridade pt-BR > en, sem URL pronta, sem chamada externa).
-- ============================================================================

-- DROP necessário: a assinatura de retorno muda (thumbnail_storage_path
-- novo, entre last_checked_at e total_count) — Postgres não permite
-- CREATE OR REPLACE mudar o tipo de retorno de uma função RETURNS TABLE.
DROP FUNCTION IF EXISTS public.admin_list_pricing_card_mapping_issues(text[], uuid, uuid, text, integer, integer);

CREATE FUNCTION public.admin_list_pricing_card_mapping_issues(
  p_status text[] DEFAULT ARRAY['PENDING', 'REJECTED'],
  p_pricing_source_id uuid DEFAULT NULL,
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
  thumbnail_storage_path text,
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
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_CARD_MAPPING_ISSUES_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');

  -- Vocabulário travado a PENDING/REJECTED (2026-08-27 — NOT_FOUND some da
  -- fila assim que decidido; a RPC de resolução continua aceitando NOT_FOUND
  -- como decisão possível, só a listagem para de devolvê-lo).
  v_status := ARRAY(SELECT x FROM unnest(COALESCE(p_status, ARRAY['PENDING', 'REJECTED'])) AS x WHERE x IN ('PENDING', 'REJECTED'));
  IF array_length(v_status, 1) IS NULL THEN
    v_status := ARRAY['PENDING', 'REJECTED'];
  END IF;

  RETURN QUERY
  SELECT
    pcm.id, c.id, c.name::text, c.collector_number::text, c.collector_total,
    cs.id, cs.code::text, cs.name::text,
    pcm.pricing_source_id, ps.code::text,
    pcm.match_status,
    (SELECT count(*)::int FROM public.pricing_source_card_identity psci WHERE psci.pricing_card_mapping_id = pcm.id),
    pcm.last_checked_at,
    thumb.storage_path,
    count(*) OVER() AS total_count
  FROM public.pricing_card_mapping pcm
  JOIN public.card c ON c.id = pcm.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
  JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id
  LEFT JOIN LATERAL (
    SELECT ca.storage_path
    FROM public.card_asset ca
    JOIN public.card_asset_type cat ON cat.id = ca.asset_type_id
    JOIN public.language lg ON lg.id = ca.language_id
    WHERE ca.card_id = c.id
      AND ca.is_primary = true
      AND cat.code = 'CARD_FRONT'
      AND lg.code IN ('pt-BR', 'en')
    ORDER BY CASE lg.code WHEN 'pt-BR' THEN 0 WHEN 'en' THEN 1 ELSE 2 END
    LIMIT 1
  ) thumb ON true
  WHERE pcm.match_status = ANY(v_status)
    AND (p_pricing_source_id IS NULL OR pcm.pricing_source_id = p_pricing_source_id)
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

REVOKE ALL ON FUNCTION public.admin_list_pricing_card_mapping_issues(text[], uuid, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_card_mapping_issues(text[], uuid, uuid, text, integer, integer) TO authenticated;

-- ============================================================================
-- admin_get_pricing_mapping_detail — expõe match_evidence no nível do mapping.
-- Gap identificado nesta rodada: a UI de confirmação por candidato (frontend,
-- próximo incremento) precisa ler match_evidence.candidatos para renderizar
-- as opções, e a função não devolvia esse campo (só devolvia identities já
-- persistidas). Assinatura e tipo de retorno (jsonb) não mudam — CREATE OR
-- REPLACE é suficiente, sem DROP.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_pricing_mapping_detail(p_mapping_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_GET_PRICING_MAPPING_DETAIL_FORBIDDEN: acesso restrito a administradores.'; END IF;
  SELECT jsonb_build_object(
    'mapping', jsonb_build_object('id', pcm.id, 'match_status', pcm.match_status, 'match_method', pcm.match_method,
      'external_card_id', pcm.external_card_id, 'external_card_name', pcm.external_card_name,
      'last_checked_at', pcm.last_checked_at, 'pricing_source_id', pcm.pricing_source_id, 'pricing_source_code', ps.code,
      'match_evidence', pcm.match_evidence),
    'card', jsonb_build_object('id', c.id, 'name', c.name, 'collector_number', c.collector_number, 'collector_total', c.collector_total,
      'card_set_id', cs.id, 'card_set_code', cs.code, 'card_set_name', cs.name),
    'local_variants', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', cv.id, 'variant_type_id', cvt.id, 'code', cvt.code, 'name', cvt.name, 'is_default', cv.is_default) ORDER BY cv.variant_order)
      FROM public.card_variant cv JOIN public.card_variant_type cvt ON cvt.id = cv.variant_type_id WHERE cv.card_id = c.id), '[]'::jsonb),
    'identities', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', psci.id, 'external_card_id', psci.external_card_id, 'external_card_name', psci.external_card_name,
        'identity_role', psci.identity_role, 'canonical_identity_id', psci.canonical_identity_id,
        'match_status', psci.match_status, 'match_method', psci.match_method, 'match_evidence', psci.match_evidence,
        'card_variant_type_id', psci.card_variant_type_id, 'card_variant_type_name', cvt2.name,
        'external_variant_key', psci.external_variant_key, 'last_checked_at', psci.last_checked_at,
        'prices', COALESCE((SELECT jsonb_agg(jsonb_build_object('condition_id', o.condition_id, 'price_type', o.price_type, 'currency_code', o.currency_code, 'market_label', o.market_label, 'price', o.price, 'observed_at', o.observed_at) ORDER BY o.observed_at DESC)
          FROM public.pricing_product pp JOIN public.pricing_observation o ON o.pricing_product_id = pp.id WHERE pp.pricing_source_card_identity_id = psci.id), '[]'::jsonb)
      ) ORDER BY psci.identity_role, psci.external_card_id)
      FROM public.pricing_source_card_identity psci LEFT JOIN public.card_variant_type cvt2 ON cvt2.id = psci.card_variant_type_id
      WHERE psci.pricing_card_mapping_id = pcm.id), '[]'::jsonb),
    'missing_variant', NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id)
  ) INTO v_result
  FROM public.pricing_card_mapping pcm JOIN public.card c ON c.id = pcm.card_id JOIN public.card_set cs ON cs.id = c.card_set_id JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id
  WHERE pcm.id = p_mapping_id;
  IF v_result IS NULL THEN RAISE EXCEPTION 'ADMIN_GET_PRICING_MAPPING_DETAIL_NOT_FOUND: id=%', p_mapping_id; END IF;
  RETURN v_result;
END; $function$;
