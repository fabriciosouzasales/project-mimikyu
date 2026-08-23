-- Query 3941 — Backend do Bloco 3 do Pricing Admin (Saúde das Fontes,
-- Histórico de Execuções, Sincronizações)
-- Status: CONFIRMADO EXECUTADO em 2026-08-22 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: 4 RPCs de LEITURA (nenhuma escrita, nenhuma trigger, nenhuma
-- alteração de cron/next_due_at), admin-only, para as 3 telas do Bloco 3:
--   - admin_get_pricing_source_health() — 1 linha por fonte (hoje só
--     JUSTTCG): última execução, cobertura de mappings, Sets
--     saudáveis/com problema/pausados, erros/rate limits recentes.
--   - admin_list_pricing_sync_runs(...) — pricing_sync_run paginado
--     server-side, filtros status/fonte/Set/período. O filtro por Set usa
--     pricing_sync_run.pricing_set_mapping_id → pricing_set_mapping.card_set_id
--     → card_set (decisão explícita de Fabrício: não filtrar apenas por
--     pricing_source_id). Runs sem Set associado continuam visíveis quando
--     nenhum filtro de Set está ativo.
--   - admin_get_pricing_sync_run_detail(p_run_id) — run + array de
--     pricing_sync_run_call, para o Dialog de detalhe.
--   - admin_list_pricing_set_refresh_states(...) — visão operacional por
--     Set (pricing_set_refresh_state + pricing_set_mapping + card_set +
--     cobertura de pricing_card_mapping), com status derivado
--     HEALTHY/PROBLEM/PAUSED, paginado/filtrado server-side mesmo com
--     apenas 45 Sets hoje.
--
-- Correções aplicadas durante o teste transacional (a primeira rodada de
-- teste falhou 3 vezes antes de passar — registradas aqui porque mudam a
-- forma final das 4 funções, não são só ruído de tentativa):
--   1) admin_get_pricing_source_health: ambiguidade de "pricing_source_id"
--      entre a coluna OUT da RETURNS TABLE e a coluna de tabela usada sem
--      qualificação dentro das LATERALs (erro 42702) — corrigido
--      qualificando todas as ocorrências com o alias da subquery
--      (psr_h/pcm_h/psr_rf/psr_err).
--   2) admin_list_pricing_sync_runs e admin_get_pricing_sync_run_detail: o
--      JOIN (INNER) original com pricing_source excluía silenciosamente os
--      8 runs FX_REFRESH, que têm pricing_source_id IS NULL por desenho
--      (refresh cambial não é por fonte — ver ADR-030). Trocado para LEFT
--      JOIN nas duas funções — confirmado que o total_count do teste
--      passou de 94 para 102 (o total real da tabela pricing_sync_run) após
--      a correção.
--   3) admin_list_pricing_set_refresh_states: a subquery interna usava
--      "cs.code::text, cs.name::text, ps.code" sem alias, então o Postgres
--      nomeava as colunas resultantes pelo nome de origem ("code"), o que
--      quebrava a referência externa "rows.card_set_code" no ORDER BY
--      (erro 42703, "column rows.card_set_code does not exist"). Corrigido
--      com AS explícito (card_set_code/card_set_name/pricing_source_code/
--      mappings_confirmed/mappings_total).
--
-- Validação transacional (BEGIN/ROLLBACK): 17 cenários cobrindo as 4 RPCs
-- como admin (contagens, filtros status/Set/HEALTHY/PROBLEM/busca, detail
-- de run real com 2 calls, detail NOT_FOUND) e as 4 respectivas exceções
-- *_FORBIDDEN sem claims de admin. Após aplicação real, reconfirmado
-- total_count=102 em admin_list_pricing_sync_runs (paridade com a correção
-- do item 2 acima).
--
-- Segurança pós-aplicação: get_advisors(security) — 0 ERROR/0 CRITICAL; os
-- únicos WARN novos são authenticated_security_definer_function_executable
-- nas 4 funções, mesma classe já aceita desde a migration 3940 (o guard
-- is_admin() está dentro do corpo da função, não em GRANT). Grants
-- confirmados via information_schema.role_routine_grants: apenas
-- postgres (owner) e authenticated — sem PUBLIC/anon.
--
-- Performance pós-aplicação: EXPLAIN (ANALYZE, BUFFERS) em
-- admin_list_pricing_sync_runs (32ms) e admin_list_pricing_set_refresh_states
-- (30ms com cache aquecido — a primeira chamada, com cache frio, levou
-- 574ms pelo mesmo I/O de buffers; não é um problema de plano de consulta,
-- confirmado reexecutando a query interna crua com o mesmo EXPLAIN). Volume
-- atual: 102 pricing_sync_run, 45 pricing_set_refresh_state, 7429
-- pricing_card_mapping — nenhum índice novo foi necessário; os já
-- existentes (uq_card_card_set_collector_number em card(card_set_id, ...),
-- uq_pricing_card_mapping_card_source em pricing_card_mapping(card_id,
-- pricing_source_id)) já cobrem os padrões de acesso das 4 RPCs.

-- 1) admin_get_pricing_source_health — 1 linha por fonte
CREATE OR REPLACE FUNCTION public.admin_get_pricing_source_health()
RETURNS TABLE(
  pricing_source_id uuid, pricing_source_code text, pricing_source_name text, is_active boolean,
  last_run_id uuid, last_run_type text, last_run_status text, last_run_finished_at timestamptz, last_run_triggered_by text,
  mappings_confirmed integer, mappings_pending integer, mappings_not_found integer, mappings_total integer, coverage_pct numeric,
  sets_healthy integer, sets_problem integer, sets_paused integer, sets_total integer,
  recent_failed_runs integer, recent_rate_limit_hits integer, last_error_summary text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_SOURCE_HEALTH_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  RETURN QUERY
  SELECT
    ps.id, ps.code, ps.name, ps.is_active,
    lr.id, lr.run_type, lr.status, lr.finished_at, lr.triggered_by,
    mc.confirmed::int, mc.pending::int, mc.not_found::int, mc.total::int,
    CASE WHEN mc.total > 0 THEN round((mc.confirmed::numeric / mc.total) * 100, 1) ELSE NULL END,
    sc.healthy::int, sc.problem::int, sc.paused::int, sc.total::int,
    rf.failed_count::int, rf.rate_limit_hits::int, rf.last_error_summary
  FROM public.pricing_source ps
  LEFT JOIN LATERAL (
    SELECT psr_h.id, psr_h.run_type, psr_h.status, psr_h.finished_at, psr_h.triggered_by
    FROM public.pricing_sync_run psr_h
    WHERE psr_h.pricing_source_id = ps.id AND psr_h.finished_at IS NOT NULL
    ORDER BY psr_h.finished_at DESC LIMIT 1
  ) lr ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE pcm_h.match_status = 'CONFIRMED') AS confirmed,
      count(*) FILTER (WHERE pcm_h.match_status = 'PENDING') AS pending,
      count(*) FILTER (WHERE pcm_h.match_status = 'NOT_FOUND') AS not_found, count(*) AS total
    FROM public.pricing_card_mapping pcm_h WHERE pcm_h.pricing_source_id = ps.id
  ) mc ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE NOT psrs.is_paused AND psrs.last_outcome = 'SUCCESS') AS healthy,
      count(*) FILTER (WHERE NOT psrs.is_paused AND psrs.last_outcome IS DISTINCT FROM 'SUCCESS') AS problem,
      count(*) FILTER (WHERE psrs.is_paused) AS paused, count(*) AS total
    FROM public.pricing_set_refresh_state psrs
    JOIN public.pricing_set_mapping psm ON psm.id = psrs.pricing_set_mapping_id
    WHERE psm.pricing_source_id = ps.id
  ) sc ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE psr_rf.status = 'FAILED') AS failed_count, COALESCE(sum(psr_rf.rate_limit_hits), 0) AS rate_limit_hits,
      (SELECT psr_err.error_summary FROM public.pricing_sync_run psr_err
        WHERE psr_err.pricing_source_id = ps.id AND psr_err.error_summary IS NOT NULL
        ORDER BY psr_err.created_at DESC LIMIT 1) AS last_error_summary
    FROM public.pricing_sync_run psr_rf
    WHERE psr_rf.pricing_source_id = ps.id AND psr_rf.created_at >= now() - interval '7 days'
  ) rf ON true
  ORDER BY ps.source_order;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_source_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_source_health() TO authenticated;

-- 2) admin_list_pricing_sync_runs — paginação/filtro server-side (por Set via
-- pricing_set_mapping_id, per decisão de Fabrício); LEFT JOIN em pricing_source
-- para não excluir runs FX_REFRESH (pricing_source_id nulo por desenho).
CREATE OR REPLACE FUNCTION public.admin_list_pricing_sync_runs(
  p_status text[] DEFAULT NULL, p_pricing_source_id uuid DEFAULT NULL, p_card_set_id uuid DEFAULT NULL,
  p_date_from timestamptz DEFAULT NULL, p_date_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 20, p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid, pricing_source_id uuid, pricing_source_code text, run_type text, status text,
  card_set_id uuid, card_set_code text, card_set_name text,
  started_at timestamptz, finished_at timestamptz, duration_seconds numeric,
  requests_made integer, requests_remaining_at_end integer, rate_limit_hits integer,
  error_summary text, triggered_by text, total_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_limit int; v_offset int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_SYNC_RUNS_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  RETURN QUERY
  SELECT
    psr.id, psr.pricing_source_id, ps.code, psr.run_type, psr.status,
    psm.card_set_id, cs.code::text, cs.name::text,
    psr.started_at, psr.finished_at,
    CASE WHEN psr.finished_at IS NOT NULL THEN EXTRACT(EPOCH FROM (psr.finished_at - psr.started_at)) ELSE NULL END,
    psr.requests_made, psr.requests_remaining_at_end, psr.rate_limit_hits,
    psr.error_summary, psr.triggered_by, count(*) OVER() AS total_count
  FROM public.pricing_sync_run psr
  LEFT JOIN public.pricing_source ps ON ps.id = psr.pricing_source_id
  LEFT JOIN public.pricing_set_mapping psm ON psm.id = psr.pricing_set_mapping_id
  LEFT JOIN public.card_set cs ON cs.id = psm.card_set_id
  WHERE (p_status IS NULL OR array_length(p_status, 1) IS NULL OR psr.status = ANY(p_status))
    AND (p_pricing_source_id IS NULL OR psr.pricing_source_id = p_pricing_source_id)
    AND (p_card_set_id IS NULL OR psm.card_set_id = p_card_set_id)
    AND (p_date_from IS NULL OR psr.started_at >= p_date_from)
    AND (p_date_to IS NULL OR psr.started_at <= p_date_to)
  ORDER BY psr.started_at DESC NULLS LAST, psr.id
  LIMIT v_limit OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_sync_runs(text[], uuid, uuid, timestamptz, timestamptz, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_sync_runs(text[], uuid, uuid, timestamptz, timestamptz, integer, integer) TO authenticated;

-- 3) admin_get_pricing_sync_run_detail — run + calls (LEFT JOIN em
-- pricing_source pelo mesmo motivo do item 2)
CREATE OR REPLACE FUNCTION public.admin_get_pricing_sync_run_detail(p_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_SYNC_RUN_DETAIL_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  SELECT jsonb_build_object(
    'run', jsonb_build_object(
      'id', psr.id, 'pricing_source_id', psr.pricing_source_id, 'pricing_source_code', ps.code,
      'run_type', psr.run_type, 'status', psr.status,
      'card_set_id', psm.card_set_id, 'card_set_code', cs.code, 'card_set_name', cs.name,
      'started_at', psr.started_at, 'finished_at', psr.finished_at,
      'requests_made', psr.requests_made, 'requests_remaining_at_end', psr.requests_remaining_at_end,
      'rate_limit_hits', psr.rate_limit_hits, 'error_summary', psr.error_summary,
      'triggered_by', psr.triggered_by, 'fx_source_code', psr.fx_source_code
    ),
    'calls', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'sequence_number', c.sequence_number, 'endpoint', c.endpoint,
        'http_status_code', c.http_status_code, 'outcome', c.outcome, 'error_detail', c.error_detail,
        'api_requests_remaining', c.api_requests_remaining, 'called_at', c.called_at
      ) ORDER BY c.sequence_number)
      FROM public.pricing_sync_run_call c WHERE c.sync_run_id = psr.id
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM public.pricing_sync_run psr
  LEFT JOIN public.pricing_source ps ON ps.id = psr.pricing_source_id
  LEFT JOIN public.pricing_set_mapping psm ON psm.id = psr.pricing_set_mapping_id
  LEFT JOIN public.card_set cs ON cs.id = psm.card_set_id
  WHERE psr.id = p_run_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_SYNC_RUN_DETAIL_NOT_FOUND: id=%', p_run_id;
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_sync_run_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_sync_run_detail(uuid) TO authenticated;

-- 4) admin_list_pricing_set_refresh_states — visão operacional por Set
CREATE OR REPLACE FUNCTION public.admin_list_pricing_set_refresh_states(
  p_search text DEFAULT NULL, p_status text[] DEFAULT NULL, p_pricing_source_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 20, p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid, card_set_id uuid, card_set_code text, card_set_name text,
  pricing_source_id uuid, pricing_source_code text, derived_status text,
  last_started_at timestamptz, last_success_at timestamptz, next_due_at timestamptz,
  last_outcome text, attempt_count integer,
  is_paused boolean, pause_reason text, paused_at timestamptz,
  lease_until timestamptz, leased_by uuid, resume_offset integer, cycle_expected_card_count integer,
  mappings_confirmed integer, mappings_total integer, total_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_limit int; v_offset int; v_search text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_SET_REFRESH_STATES_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');
  RETURN QUERY
  SELECT * FROM (
    SELECT
      psrs.id, psm.card_set_id, cs.code::text AS card_set_code, cs.name::text AS card_set_name,
      psm.pricing_source_id, ps.code AS pricing_source_code,
      CASE WHEN psrs.is_paused THEN 'PAUSED'
           WHEN psrs.last_outcome = 'SUCCESS' THEN 'HEALTHY'
           ELSE 'PROBLEM' END AS derived_status,
      psrs.last_started_at, psrs.last_success_at, psrs.next_due_at,
      psrs.last_outcome, psrs.attempt_count,
      psrs.is_paused, psrs.pause_reason, psrs.paused_at,
      psrs.lease_until, psrs.leased_by, psrs.resume_offset, psrs.cycle_expected_card_count,
      mc.confirmed::int AS mappings_confirmed, mc.total::int AS mappings_total, count(*) OVER() AS total_count
    FROM public.pricing_set_refresh_state psrs
    JOIN public.pricing_set_mapping psm ON psm.id = psrs.pricing_set_mapping_id
    JOIN public.card_set cs ON cs.id = psm.card_set_id
    JOIN public.pricing_source ps ON ps.id = psm.pricing_source_id
    LEFT JOIN LATERAL (
      SELECT count(*) FILTER (WHERE pcm.match_status = 'CONFIRMED') AS confirmed, count(*) AS total
      FROM public.pricing_card_mapping pcm
      JOIN public.card c ON c.id = pcm.card_id
      WHERE c.card_set_id = cs.id AND pcm.pricing_source_id = ps.id
    ) mc ON true
    WHERE (p_pricing_source_id IS NULL OR psm.pricing_source_id = p_pricing_source_id)
      AND (v_search IS NULL OR cs.name ILIKE '%' || v_search || '%' OR cs.code ILIKE '%' || v_search || '%')
  ) rows
  WHERE (p_status IS NULL OR array_length(p_status, 1) IS NULL OR rows.derived_status = ANY(p_status))
  ORDER BY rows.next_due_at ASC NULLS LAST, rows.card_set_code
  LIMIT v_limit OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_set_refresh_states(text, text[], uuid, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_set_refresh_states(text, text[], uuid, integer, integer) TO authenticated;
