-- Query 3961 — Convergência Pendências -> Mapeamentos de Cartas (fila única de exceções)
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: decisão de Fabrício de convergir /pricing/pendencias para dentro
-- de /pricing/mapeamentos-cartas (opção "a" de duas alternativas
-- apresentadas — a outra era manter as duas telas diferenciadas por papel).
-- admin_list_pricing_pending_mappings é substituída por
-- admin_list_pricing_card_mapping_issues: mesmo corpo/joins/ORDER BY,
-- ampliando o vocabulário travado de ['PENDING','NOT_FOUND'] para
-- ['PENDING','NOT_FOUND','REJECTED'] e adicionando p_pricing_source_id +
-- pricing_source_id/pricing_source_code no retorno (filtro de Fonte que a
-- tela de Pendências nunca teve). CONFIRMED nunca é aceito nesse
-- vocabulário, mesmo que o chamador passe esse valor — mesma trava por
-- desenho que a função anterior já usava.
--
-- Decisão explícita de Fabrício: admin_list_pricing_card_mappings (a RPC
-- "todos os 4 status", que passa a não ter mais nenhum consumidor de UI
-- depois desta migration) NÃO é removida agora. Motivo: ele não aceita
-- perder completamente a capacidade de auditoria de CONFIRMED pela UI só
-- porque a tela deixou de exibi-los por padrão — fica reservada para uma
-- futura visão de auditoria dedicada.
--
-- Testado transacionalmente (BEGIN + ROLLBACK, sem residual em produção)
-- antes da aplicação real: total_count=93 (75 PENDING + 18 NOT_FOUND + 0
-- REJECTED, bate com o baseline conhecido); status inválido (CONFIRMED)
-- cai no default sem vazar CONFIRMED; filtro por Fonte não quebra; função
-- antiga (admin_list_pricing_pending_mappings) confirmada removida;
-- chamada sem sessão admin bloqueada com *_FORBIDDEN.
--
-- Pós-aplicação real: grants confirmados via information_schema.
-- role_routine_grants — só authenticated e postgres têm EXECUTE na função
-- nova, nenhum anon/PUBLIC; admin_list_pricing_card_mappings mantém seus
-- grants originais intactos, admin_list_pricing_pending_mappings não
-- aparece mais. Chamada real como admin confirma total_count=93 em produção.
--
-- Como validar:
--   SELECT * FROM public.admin_list_pricing_card_mapping_issues(); -- como admin
--   SELECT 1 FROM pg_proc WHERE proname = 'admin_list_pricing_pending_mappings'; -- deve vir vazio

DROP FUNCTION IF EXISTS public.admin_list_pricing_pending_mappings(text[], uuid, text, integer, integer);

CREATE FUNCTION public.admin_list_pricing_card_mapping_issues(
  p_status text[] DEFAULT ARRAY['PENDING', 'NOT_FOUND', 'REJECTED'],
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

  -- Vocabulário travado a PENDING/NOT_FOUND/REJECTED, independente do que
  -- for passado — esta RPC é a fila operacional de Mapeamentos de Cartas,
  -- nunca deve vazar CONFIRMED mesmo que o chamador passe um valor errado.
  v_status := ARRAY(SELECT x FROM unnest(COALESCE(p_status, ARRAY['PENDING', 'NOT_FOUND', 'REJECTED'])) AS x WHERE x IN ('PENDING', 'NOT_FOUND', 'REJECTED'));
  IF array_length(v_status, 1) IS NULL THEN
    v_status := ARRAY['PENDING', 'NOT_FOUND', 'REJECTED'];
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
