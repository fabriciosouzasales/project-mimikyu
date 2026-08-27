-- Query 3965 — Expõe thumbnail_storage_path em admin_get_pricing_mapping_detail
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: dar suporte ao cabeçalho visual de /pricing/resolucao-mapeamentos
-- (imagem da carta ao lado das informações principais), reaproveitando a
-- exata mesma regra de seleção de imagem já usada na fila de Mapeamentos de
-- Cartas (migration 3964): card_asset primário, asset_type CARD_FRONT,
-- prioridade pt-BR > en, sem chamada externa, sem alteração de vínculo.
-- Assinatura e tipo de retorno (jsonb) não mudam — CREATE OR REPLACE é
-- suficiente, sem DROP; grants existentes (authenticated/postgres) permanecem
-- intactos automaticamente.
--
-- Como validar:
--   SELECT public.admin_get_pricing_mapping_detail('<mapping_id>') -> 'card' ->> 'thumbnail_storage_path';
--
-- Validado transacionalmente (BEGIN/ROLLBACK) contra 5 mappings PENDING/
-- REJECTED reais antes da aplicação: thumbnail do detail idêntico ao da fila
-- (admin_list_pricing_card_mapping_issues, migration 3964) em todos os casos,
-- incluindo fallback pt-BR->en; last_checked_at do mapping já vinha exposto
-- desde a migration 3940, sem custo adicional.

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
      'card_set_id', cs.id, 'card_set_code', cs.code, 'card_set_name', cs.name,
      'thumbnail_storage_path', thumb.storage_path),
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
  WHERE pcm.id = p_mapping_id;
  IF v_result IS NULL THEN RAISE EXCEPTION 'ADMIN_GET_PRICING_MAPPING_DETAIL_NOT_FOUND: id=%', p_mapping_id; END IF;
  RETURN v_result;
END; $function$;
