-- Migration 3966 — Corrige candidate_count de admin_list_pricing_card_mapping_issues
-- CONFIRMADO EXECUTADO em 2026-08-27 via Supabase MCP (apply_migration).
--
-- Bug reportado por Fabrício: a coluna "Candidatas" em /pricing/mapeamentos-cartas
-- exibia 0 para mappings PENDING que, ao abrir "Resolver", mostravam múltiplos
-- candidatos em match_evidence.candidatos. Causa raiz: a RPC contava
-- pricing_source_card_identity materializadas (o DESTINO da escolha do admin),
-- não os candidatos ainda não resolvidos, que no desenho da migration 3964
-- (confirmação por candidato bruto) permanecem apenas em match_evidence até a
-- decisão. Corrige a semântica: candidate_count agora deriva de
-- jsonb_array_length(match_evidence->'candidatos'), com fallback seguro 0
-- quando a chave está ausente ou não é array (ex.: REJECTED sem evidência
-- válida) — nunca usa pricing_source_card_identity como proxy.
--
-- Requer DROP+CREATE (não CREATE OR REPLACE) porque a coluna de saída
-- identity_count foi renomeada para candidate_count — Postgres não permite
-- renomear coluna de RETURNS TABLE via CREATE OR REPLACE (42P13).
--
-- Nota operacional: como toda função nova via CREATE FUNCTION, o Postgres
-- concede EXECUTE a PUBLIC por padrão. Isso foi detectado e revertido no
-- mesmo ciclo (REVOKE ... FROM PUBLIC, ao final desta migration) para
-- preservar a postura de privilégio mínimo já estabelecida para esta RPC
-- (apenas postgres e authenticated, gate interno via is_admin()).

DROP FUNCTION public.admin_list_pricing_card_mapping_issues(text[], uuid, uuid, text, integer, integer);

CREATE FUNCTION public.admin_list_pricing_card_mapping_issues(
  p_status text[] DEFAULT ARRAY['PENDING'::text, 'REJECTED'::text],
  p_pricing_source_id uuid DEFAULT NULL::uuid,
  p_card_set_id uuid DEFAULT NULL::uuid,
  p_search text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
 RETURNS TABLE(
   id uuid, card_id uuid, card_name text, collector_number text, collector_total integer,
   card_set_id uuid, card_set_code text, card_set_name text,
   pricing_source_id uuid, pricing_source_code text,
   match_status text,
   candidate_count integer,
   last_checked_at timestamp with time zone,
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
    CASE
      WHEN jsonb_typeof(pcm.match_evidence -> 'candidatos') = 'array'
        THEN jsonb_array_length(pcm.match_evidence -> 'candidatos')
      ELSE 0
    END,
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

GRANT EXECUTE ON FUNCTION public.admin_list_pricing_card_mapping_issues(text[], uuid, uuid, text, integer, integer) TO authenticated;

-- Correção do grant residual de PUBLIC criado automaticamente pelo CREATE FUNCTION acima.
REVOKE EXECUTE ON FUNCTION public.admin_list_pricing_card_mapping_issues(text[], uuid, uuid, text, integer, integer) FROM PUBLIC;
