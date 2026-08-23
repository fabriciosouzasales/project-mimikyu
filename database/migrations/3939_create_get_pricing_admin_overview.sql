-- Query 3939 — RPC agregada de KPIs para a Visão Geral do Pricing Admin
-- Status: CONFIRMADO EXECUTADO em 2026-08-22 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: criar o único backend novo necessário para o Bloco 1 do
-- Pricing Admin (frontend, `/pricing`) — uma função agregada,
-- SECURITY DEFINER, admin-only, que computa em uma única chamada todos os
-- KPIs exigidos por Fabrício para a Visão Geral: fontes de preço ativas,
-- mappings CONFIRMED/PENDING/NOT_FOUND e cobertura percentual, produtos
-- precificados, observações de preço, última sincronização concluída,
-- Sets com refresh saudável/com problema, e um resumo da Política de
-- Sincronização (frequência vigente por fonte, próxima execução prevista,
-- status do dispatcher). Todo o cálculo é feito no servidor via agregação
-- de passagem única (count(*) FILTER (WHERE ...)) — nada de fetch
-- integral de tabela para o frontend computar KPI (requisito explícito de
-- Fabrício: "queries eficientes").
--
-- Segurança: função pertence a postgres (owner padrão de função criada
-- via migration do Supabase MCP), o que permite ler cron.job internamente
-- mesmo que authenticated não tenha GRANT direto sobre esse catálogo
-- (SELECT em cron.job é restrito a postgres). Checagem explícita
-- is_admin() no corpo da função, com exceção nomeada
-- GET_PRICING_ADMIN_OVERVIEW_FORBIDDEN para chamador não-admin. GRANT
-- EXECUTE restrito a authenticated (mesmo padrão das demais RPCs admin do
-- domínio); REVOKE ALL FROM PUBLIC.
--
-- Resultado confirmado pós-execução: como admin, retorna JSON coerente
-- com o estado real do banco (sources.active=1/total=1;
-- mappings confirmed=7336/pending=75/not_found=18/total=7429/
-- coverage_pct=98.7; products_count=47250; observations_count=69971;
-- last_sync_run com id/run_type/status/finished_at/triggered_by do run
-- COMPLETED mais recente; sets total=45/healthy=45/problem=0/paused=0/
-- next_due_at; refresh_policy como array por fonte com frequency_days;
-- dispatcher.active=true/schedule="*/5 * * * *"). Como não-admin (GUC de
-- identidade não-admin) e sem autenticação, rejeita com
-- GET_PRICING_ADMIN_OVERVIEW_FORBIDDEN (P0001). Grants confirmados via
-- information_schema.role_routine_grants: apenas authenticated e postgres
-- têm EXECUTE. get_advisors(security) sem novo ERROR/CRITICAL — apenas o
-- WARN authenticated_security_definer_function_executable já aceito para
-- dezenas de outras funções admin do domínio. EXPLAIN ANALYZE:
-- Execution Time 31.218 ms.
--
-- Como validar:
--   SELECT public.get_pricing_admin_overview(); -- como admin autenticado

CREATE OR REPLACE FUNCTION public.get_pricing_admin_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mapping_counts record;
  v_set_counts record;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'GET_PRICING_ADMIN_OVERVIEW_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  SELECT
    count(*) FILTER (WHERE match_status = 'CONFIRMED') AS confirmed,
    count(*) FILTER (WHERE match_status = 'PENDING') AS pending,
    count(*) FILTER (WHERE match_status = 'NOT_FOUND') AS not_found,
    count(*) AS total
  INTO v_mapping_counts
  FROM public.pricing_card_mapping;

  SELECT
    count(*) AS total,
    count(*) FILTER (WHERE last_outcome = 'SUCCESS' AND NOT is_paused) AS healthy,
    count(*) FILTER (WHERE last_outcome IS DISTINCT FROM 'SUCCESS' OR is_paused) AS problem,
    count(*) FILTER (WHERE is_paused) AS paused,
    min(next_due_at) FILTER (WHERE NOT is_paused) AS next_due_at
  INTO v_set_counts
  FROM public.pricing_set_refresh_state;

  SELECT jsonb_build_object(
    'sources', jsonb_build_object(
      'active', (SELECT count(*) FROM public.pricing_source WHERE is_active),
      'total', (SELECT count(*) FROM public.pricing_source)
    ),
    'mappings', jsonb_build_object(
      'confirmed', v_mapping_counts.confirmed,
      'pending', v_mapping_counts.pending,
      'not_found', v_mapping_counts.not_found,
      'total', v_mapping_counts.total,
      'coverage_pct', CASE WHEN v_mapping_counts.total > 0
        THEN round((v_mapping_counts.confirmed::numeric / v_mapping_counts.total) * 100, 1)
        ELSE NULL END
    ),
    'products_count', (SELECT count(*) FROM public.pricing_product),
    'observations_count', (SELECT count(*) FROM public.pricing_observation),
    'last_sync_run', (
      SELECT jsonb_build_object(
        'id', id, 'run_type', run_type, 'status', status,
        'finished_at', finished_at, 'triggered_by', triggered_by
      )
      FROM public.pricing_sync_run
      WHERE status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS')
      ORDER BY finished_at DESC NULLS LAST
      LIMIT 1
    ),
    'sets', jsonb_build_object(
      'total', v_set_counts.total,
      'healthy', v_set_counts.healthy,
      'problem', v_set_counts.problem,
      'paused', v_set_counts.paused,
      'next_due_at', v_set_counts.next_due_at
    ),
    'refresh_policy', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'pricing_source_id', ps.id,
        'pricing_source_code', ps.code,
        'pricing_source_name', ps.name,
        'frequency_days', COALESCE(prp.frequency_days, 1)
      ) ORDER BY ps.source_order), '[]'::jsonb)
      FROM public.pricing_source ps
      LEFT JOIN public.pricing_refresh_policy prp ON prp.pricing_source_id = ps.id
    ),
    'dispatcher', (
      SELECT jsonb_build_object('active', active, 'schedule', schedule)
      FROM cron.job
      WHERE jobname = 'justtcg-price-refresh-set-dispatcher'
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_pricing_admin_overview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pricing_admin_overview() TO authenticated;
