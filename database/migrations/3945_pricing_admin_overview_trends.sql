-- Query 3945 — RPCs de série temporal agregada para a Visão Geral v2 do Pricing Admin
-- Status: CONFIRMADO EXECUTADO em 2026-08-23 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
-- Ver também 3946 (correção do mesmo dia — cum_total removido de
-- admin_get_pricing_coverage_trend por representar reconstrução enganosa).
--
-- Objetivo: os únicos backends novos necessários para o refinamento da
-- Visão Geral (`/pricing`) pedido por Fabrício em 2026-08-23 — um "dashboard
-- gerencial de verdade" com faixa de 3 gráficos (evolução de confirmações,
-- execuções de sincronização, saúde dos Sets). O 3º gráfico (saúde dos Sets)
-- não precisa de RPC nova: é um retrato do instante atual já coberto por
-- `get_pricing_admin_overview().sets` (migration 3939). O KPI "Política de
-- Atualização" também não precisa de RPC nova (já vem em `refresh_policy`/
-- `dispatcher` do mesmo payload).
--
-- admin_get_pricing_coverage_trend(p_days default 30, clamp 1-365):
--   série diária cumulativa de CONFIRMAÇÕES (cum_confirmed por dia) a partir
--   de pricing_card_mapping.confirmed_at. Protótipo ingênuo (generate_series
--   CROSS JOIN pricing_card_mapping) media 211ms com Nested Loop de 222.870
--   linhas intermediárias (30x multiplicação de linhas) — reprovado pelo
--   requisito explícito de Fabrício de nunca "implementar primeiro para
--   otimizar depois". Redesenhado como 1 agregação (GROUP BY
--   confirmed_at::date, 1 Seq Scan da tabela) + soma cumulativa via window
--   function sobre o conjunto pequeno de dias — caiu para poucos ms.
--
--   Correção de escopo (ver 3946): a versão original também devolvia
--   cum_total, uma reconstrução cumulativa de created_at — descartada no
--   mesmo dia por instrução explícita de Fabrício: created_at de
--   pricing_card_mapping é ele mesmo um artefato de backfill em bloco
--   (6/755/6668 linhas em 17, 19 e 20/08 — 3 dias, não crescimento
--   orgânico do catálogo), então usá-lo como "total histórico por dia"
--   implicaria — mesmo sem reaplicar o total de hoje — uma curva que
--   sugere "catálogo quase vazio até 19/08, depois um salto", o que é
--   verdade sobre o pricing_card_mapping mas enganoso sobre o catálogo
--   (as Cartas já existiam antes; só o rastreamento de preço começou
--   depois). O gráfico A na Visão Geral v2 usa cum_confirmed real +
--   denominador FIXO (mappings.total atual, de get_pricing_admin_overview)
--   — rotulado como "Evolução das Confirmações sobre a base atual", nunca
--   como "cobertura histórica".
--
-- admin_get_pricing_sync_run_daily(p_days default 14, clamp 1-365):
--   contagem diária por status a partir de pricing_sync_run.started_at.
--   Tabela pequena (102 linhas totais) — <1ms, GroupAggregate trivial.
--
-- Segurança: mesmo padrão de get_pricing_admin_overview (migration 3939) —
-- SECURITY DEFINER, SET search_path TO '', checagem explícita
-- public.is_admin() com exceção nomeada por função, REVOKE ALL FROM PUBLIC,
-- GRANT EXECUTE restrito a authenticated. p_days é clampado no servidor
-- (greatest/least) antes de qualquer uso em generate_series/interval —
-- nenhuma entrada do chamador é interpolada em SQL dinâmico.
--
-- Validação (transacional, BEGIN...ROLLBACK, zero resíduo):
--   - Chamador não-admin (postgres, sem auth.uid()): rejeitado com
--     ADMIN_GET_PRICING_COVERAGE_TREND_FORBIDDEN / ..._SYNC_RUN_DAILY_FORBIDDEN.
--   - Chamador admin real (impersonado via request.jwt.claims, mesmo
--     mecanismo do PostgREST, admin_user real fe316458-49dd-44e1-aac0-
--     f4b7604ef8f2): trend(30) devolve 30 pontos, primeiro dia
--     (2026-07-25) com cum_confirmed=0, último dia (hoje) com
--     cum_confirmed=7336 — coerente com get_pricing_admin_overview().
--     mappings.confirmed. sync_run_daily(14) devolve 10 linhas (dia x
--     status, só 6 dias de história real desde a entrada em produção do
--     dispatcher em 17/08) com contagens coerentes.
--   - Limites de p_days: 0 e -5 clampam para 1; 9999 clampa para 365 — sem
--     estourar generate_series/interval.
--   - Grants confirmados via information_schema.role_routine_grants: apenas
--     authenticated e postgres têm EXECUTE nas duas funções.
--
-- Como validar (como admin autenticado):
--   SELECT public.admin_get_pricing_coverage_trend(30);
--   SELECT public.admin_get_pricing_sync_run_daily(14);

CREATE OR REPLACE FUNCTION public.admin_get_pricing_coverage_trend(p_days integer DEFAULT 30)
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
    RAISE EXCEPTION 'ADMIN_GET_PRICING_COVERAGE_TREND_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_days := greatest(1, least(coalesce(p_days, 30), 365));

  WITH days AS (
    SELECT generate_series((now() - (v_days - 1) * interval '1 day')::date, now()::date, interval '1 day')::date AS day
  ),
  daily_confirmed AS (
    SELECT confirmed_at::date AS day, count(*) AS n
    FROM public.pricing_card_mapping
    WHERE confirmed_at IS NOT NULL
    GROUP BY 1
  ),
  joined AS (
    SELECT
      d.day,
      sum(coalesce(dc.n, 0)) OVER (ORDER BY d.day) AS cum_confirmed
    FROM days d
    LEFT JOIN daily_confirmed dc ON dc.day = d.day
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'day', to_char(day, 'YYYY-MM-DD'),
    'cum_confirmed', cum_confirmed
  ) ORDER BY day), '[]'::jsonb)
  INTO v_result
  FROM joined;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_coverage_trend(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_coverage_trend(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_pricing_sync_run_daily(p_days integer DEFAULT 14)
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
    RAISE EXCEPTION 'ADMIN_GET_PRICING_SYNC_RUN_DAILY_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_days := greatest(1, least(coalesce(p_days, 14), 365));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'day', to_char(day, 'YYYY-MM-DD'),
    'status', status,
    'count', n
  ) ORDER BY day, status), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT date_trunc('day', started_at)::date AS day, status, count(*) AS n
    FROM public.pricing_sync_run
    WHERE started_at >= now() - (v_days || ' days')::interval
    GROUP BY 1, 2
  ) grouped;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_sync_run_daily(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_sync_run_daily(integer) TO authenticated;
