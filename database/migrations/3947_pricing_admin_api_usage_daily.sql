-- Query 3947 — RPC de consumo diário da API JustTCG (Visão Geral v3.2)
-- Status: CONFIRMADO EXECUTADO em 2026-08-23 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: pedido de Fabrício para substituir o gráfico "Saúde dos Sets" da
-- faixa principal da Visão Geral (/pricing) — já suficientemente
-- representada no Hero Gerencial e no KPI "Saúde dos Sets" — por um novo
-- gráfico "Consumo da API", mostrando requests feitos por dia para apoiar
-- decisão sobre plano contratado/frequência de atualização ideal.
--
-- admin_get_pricing_api_usage_daily(p_days default 30, clamp 1-365):
--   soma diária de pricing_sync_run.requests_made, a partir de
--   pricing_sync_run.started_at. Mesmo padrão exato de
--   admin_get_pricing_sync_run_daily (migration 3945) — SEM generate_series,
--   então dias sem execução simplesmente não aparecem no resultado (nenhum
--   preenchimento artificial, requisito explícito de Fabrício). Tabela
--   pequena (pricing_sync_run, ~150 linhas) — agregação trivial, <1ms.
--
-- Segurança: mesmo padrão de admin_get_pricing_sync_run_daily/
-- get_pricing_admin_overview — SECURITY DEFINER, SET search_path TO '',
-- checagem explícita public.is_admin() com exceção nomeada por função,
-- REVOKE ALL FROM PUBLIC, GRANT EXECUTE restrito a authenticated. p_days
-- clampado no servidor antes de qualquer uso em interval.
--
-- Validação (transacional, BEGIN...ROLLBACK, zero resíduo):
--   - EXPLAIN (ANALYZE, BUFFERS) confirmou GroupAggregate trivial sobre
--     pricing_sync_run filtrado por started_at.
--   - Chamador não-admin: rejeitado com
--     ADMIN_GET_PRICING_API_USAGE_DAILY_FORBIDDEN — confirmado tanto no
--     teste transacional quanto pós-aplicação real (chamada direta como
--     postgres sem impersonação também rejeitada, prova que o guard roda em
--     produção, não só no teste).
--   - Chamador admin real (impersonado via request.jwt.claims, admin_user
--     real fe316458-49dd-44e1-aac0-f4b7604ef8f2): usage_daily(30) devolveu
--     6 dias reais (17/08 a 22/08/2026), coerente com pricing_sync_run.
--   - Limites de p_days: 0 clampa para 1; 9999 clampa para 365.
--   - Grants confirmados via information_schema.role_routine_grants pós-
--     aplicação real: apenas authenticated e postgres têm EXECUTE.
--
-- Como validar (como admin autenticado):
--   SELECT public.admin_get_pricing_api_usage_daily(30);

CREATE OR REPLACE FUNCTION public.admin_get_pricing_api_usage_daily(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_days integer;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_API_USAGE_DAILY_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_days := greatest(1, least(coalesce(p_days, 30), 365));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'day', to_char(day, 'YYYY-MM-DD'),
    'requests', requests
  ) ORDER BY day), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT date_trunc('day', started_at)::date AS day, sum(requests_made) AS requests
    FROM public.pricing_sync_run
    WHERE started_at >= now() - (v_days || ' days')::interval
    GROUP BY 1
  ) grouped;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_api_usage_daily(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_api_usage_daily(integer) TO authenticated;
