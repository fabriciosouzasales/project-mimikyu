/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3978 - Frequência de atualização de preço por Expansão
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 2 (orçamento antes de ampliar)
Mandato.....: Fabrício, 2026-10-10: "Para essas 4 expansões atualizações diárias
              [Mega Evolution, Scarlet & Violet, Sword & Shield, Sun & Moon].
              Para as demais a cada 3 dias."

O que faz
  - pricing_refresh_expansion_policy: override de frequência por (fonte, Expansão).
  - Seed JUSTTCG: ME, SV, SWSH, SM = 1 dia.
  - Padrão da fonte JUSTTCG: 1 → 3 dias (log PRICING_REFRESH_FREQUENCY_CHANGED).
  - close_pricing_set_refresh_attempt: próxima execução = override da Expansão do
    Set, senão padrão da fonte, senão 1. Nada mais muda na função.
  - get_pricing_admin_overview: refresh_policy[].expansion_overrides (para a tela).
  Efeito: vale a partir do próximo sucesso de cada Set (sem reagendar à força).

Segurança
  Tabela nova com RLS (SELECT só admin); escrita só por migration.
===============================================================================
*/
BEGIN;

CREATE TABLE public.pricing_refresh_expansion_policy (
  pricing_source_id uuid NOT NULL REFERENCES public.pricing_source(id) ON DELETE CASCADE,
  expansion_id      uuid NOT NULL REFERENCES public.expansion(id) ON DELETE CASCADE,
  frequency_days    integer NOT NULL CHECK (frequency_days IN (1, 2, 3, 5)),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (pricing_source_id, expansion_id)
);
CREATE TRIGGER trg_pricing_refresh_expansion_policy_set_updated_at
  BEFORE UPDATE ON public.pricing_refresh_expansion_policy
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.pricing_refresh_expansion_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY pricing_admin_select ON public.pricing_refresh_expansion_policy
  FOR SELECT TO authenticated USING ((SELECT public.is_admin()));
REVOKE ALL ON public.pricing_refresh_expansion_policy FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.pricing_refresh_expansion_policy TO authenticated, service_role;
COMMENT ON TABLE public.pricing_refresh_expansion_policy IS
  'Frequência de atualização de preço por Expansão; sobrepõe pricing_refresh_policy da fonte (3978).';

INSERT INTO public.pricing_refresh_expansion_policy (pricing_source_id, expansion_id, frequency_days)
SELECT s.id, e.id, 1
  FROM public.pricing_source s
  JOIN public.expansion e ON e.code IN ('ME', 'SV', 'SWSH', 'SM')
 WHERE s.code = 'JUSTTCG';

DO $p$
DECLARE v_src uuid; v_old int;
BEGIN
  SELECT id INTO v_src FROM public.pricing_source WHERE code = 'JUSTTCG';
  SELECT frequency_days INTO v_old FROM public.pricing_refresh_policy WHERE pricing_source_id = v_src FOR UPDATE;
  UPDATE public.pricing_refresh_policy SET frequency_days = 3 WHERE pricing_source_id = v_src;
  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES ('fe316458-49dd-44e1-aac0-f4b7604ef8f2'::uuid, 'PRICING_REFRESH_FREQUENCY_CHANGED', 'PRICING_SOURCE', v_src,
          jsonb_build_object('old_frequency_days', v_old, 'new_frequency_days', 3, 'operation', '3978',
                             'expansion_overrides', jsonb_build_object('ME', 1, 'SV', 1, 'SWSH', 1, 'SM', 1)));
END $p$;

CREATE OR REPLACE FUNCTION public.close_pricing_set_refresh_attempt(p_sync_run_id uuid, p_page_outcome text, p_run_status text, p_requests_made integer, p_rate_limit_hits integer DEFAULT 0, p_error_summary text DEFAULT NULL::text)
 RETURNS TABLE(final_outcome text, seen_count integer, expected_count integer)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_state record;
  v_expected_count integer;
  v_seen_count integer;
  v_final_outcome text;
  v_frequency_days integer;
BEGIN
  IF p_page_outcome NOT IN ('NO_MORE_PAGES', 'BUDGET_STOPPED', 'DEADLINE_STOPPED',
                             'TRANSIENT_ERROR', 'SET_TERMINAL_ERROR', 'AUTH_FAILURE') THEN
    RAISE EXCEPTION 'p_page_outcome invalido: %', p_page_outcome;
  END IF;

  UPDATE public.pricing_sync_run
  SET status = p_run_status,
      finished_at = now(),
      requests_made = p_requests_made,
      rate_limit_hits = p_rate_limit_hits,
      error_summary = p_error_summary
  WHERE id = p_sync_run_id;

  SELECT prs.* INTO v_state
  FROM public.pricing_set_refresh_state prs
  WHERE prs.leased_by = p_sync_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'STATE_NOT_FOUND'::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF p_page_outcome = 'AUTH_FAILURE' THEN
    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        last_outcome = 'AUTH_FAILURE', last_error_summary = p_error_summary,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT 'AUTH_FAILURE'::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF p_page_outcome = 'SET_TERMINAL_ERROR' THEN
    UPDATE public.pricing_set_refresh_state
    SET is_paused = true, pause_reason = 'SET_TERMINAL_ERROR', paused_at = now(),
        lease_until = NULL, leased_by = NULL,
        attempt_count = attempt_count + 1,
        last_outcome = 'SET_TERMINAL_ERROR', last_error_summary = p_error_summary,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT 'SET_TERMINAL_ERROR'::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF p_page_outcome = 'TRANSIENT_ERROR' THEN
    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        attempt_count = attempt_count + 1,
        next_due_at = now() + make_interval(secs => LEAST(3600, 30 * power(2, attempt_count))::integer),
        last_outcome = 'TRANSIENT_ERROR', last_error_summary = p_error_summary,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT 'TRANSIENT_ERROR'::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF p_page_outcome IN ('BUDGET_STOPPED', 'DEADLINE_STOPPED') THEN
    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        next_due_at = now(),
        last_outcome = p_page_outcome,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT p_page_outcome, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  SELECT COUNT(DISTINCT psci.external_card_id) INTO v_expected_count
  FROM public.pricing_source_card_identity psci
  JOIN public.pricing_card_mapping pcm ON pcm.id = psci.pricing_card_mapping_id
  JOIN public.card c ON c.id = pcm.card_id
  JOIN public.pricing_set_mapping psm ON psm.id = v_state.pricing_set_mapping_id
  WHERE c.card_set_id = psm.card_set_id
    AND psci.pricing_source_id = psm.pricing_source_id
    AND psci.match_status = 'CONFIRMED'
    AND psci.identity_role IN ('PRIMARY', 'ALTERNATE');

  v_seen_count := cardinality(v_state.cycle_seen_external_card_ids);

  IF v_expected_count = 0 OR v_seen_count >= v_expected_count THEN
    v_final_outcome := 'SUCCESS';

    -- 3978: override da Expansão do Set > padrão da fonte > 1 dia
    SELECT COALESCE(prep.frequency_days, prp.frequency_days, 1) INTO v_frequency_days
    FROM public.pricing_set_mapping psm
    JOIN public.card_set cs ON cs.id = psm.card_set_id
    LEFT JOIN public.pricing_refresh_expansion_policy prep
      ON prep.pricing_source_id = psm.pricing_source_id AND prep.expansion_id = cs.expansion_id
    LEFT JOIN public.pricing_refresh_policy prp ON prp.pricing_source_id = psm.pricing_source_id
    WHERE psm.id = v_state.pricing_set_mapping_id;

    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        resume_offset = 0,
        cycle_seen_external_card_ids = '{}',
        cycle_expected_card_count = NULL,
        attempt_count = 0,
        next_due_at = now() + make_interval(days => v_frequency_days),
        last_success_at = now(),
        last_outcome = 'SUCCESS', last_error_summary = NULL,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
  ELSE
    v_final_outcome := 'RECONCILIATION_INCOMPLETE';
    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        resume_offset = 0,
        cycle_seen_external_card_ids = '{}',
        cycle_expected_card_count = v_expected_count,
        attempt_count = attempt_count + 1,
        next_due_at = now() + make_interval(secs => LEAST(3600, 30 * power(2, attempt_count))::integer),
        last_outcome = 'RECONCILIATION_INCOMPLETE',
        last_error_summary = format('cobertura %s/%s', v_seen_count, v_expected_count),
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
  END IF;

  RETURN QUERY SELECT v_final_outcome, v_seen_count, v_expected_count;
END;
$function$;

-- Overview: expõe os overrides por Expansão junto da política da fonte
CREATE OR REPLACE FUNCTION public.get_pricing_admin_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_mapping_counts record;
  v_set_counts record;
  v_coverage_counts record;
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
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(is_paused, lease_until, last_outcome) = 'HEALTHY') AS healthy,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(is_paused, lease_until, last_outcome) = 'ONBOARDING_PENDING') AS onboarding_pending,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(is_paused, lease_until, last_outcome) = 'PROCESSING') AS processing,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(is_paused, lease_until, last_outcome) = 'PROBLEM') AS problem,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(is_paused, lease_until, last_outcome) = 'PAUSED') AS paused,
    min(next_due_at) FILTER (WHERE NOT is_paused) AS next_due_at
  INTO v_set_counts
  FROM public.pricing_set_refresh_state;

  SELECT
    count(DISTINCT cs.id) AS eligible_total,
    count(DISTINCT cs.id) FILTER (WHERE psm.id IS NOT NULL) AS covered
  INTO v_coverage_counts
  FROM public.card_set cs
  JOIN public.expansion ex ON ex.id = cs.expansion_id
  JOIN public.game g ON g.id = ex.game_id
  LEFT JOIN public.pricing_set_mapping psm
    ON psm.card_set_id = cs.id
    AND psm.pricing_source_id IN (SELECT ps.id FROM public.pricing_source ps WHERE ps.is_active)
  WHERE g.code = 'POKEMON';

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
    'coverage', jsonb_build_object(
      'eligible_total', v_coverage_counts.eligible_total,
      'covered', v_coverage_counts.covered
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
      'onboarding_pending', v_set_counts.onboarding_pending,
      'processing', v_set_counts.processing,
      'problem', v_set_counts.problem,
      'paused', v_set_counts.paused,
      'next_due_at', v_set_counts.next_due_at
    ),
    'refresh_policy', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'pricing_source_id', ps.id,
        'pricing_source_code', ps.code,
        'pricing_source_name', ps.name,
        'frequency_days', COALESCE(prp.frequency_days, 1),
        'expansion_overrides', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'expansion_code', e.code, 'expansion_name', e.name, 'frequency_days', prep.frequency_days
          ) ORDER BY e.code), '[]'::jsonb)
          FROM public.pricing_refresh_expansion_policy prep
          JOIN public.expansion e ON e.id = prep.expansion_id
          WHERE prep.pricing_source_id = ps.id
        )
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

-- Gates
DO $g$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM public.pricing_refresh_expansion_policy WHERE frequency_days = 1;
  IF v <> 4 THEN RAISE EXCEPTION 'G1_OVERRIDES: %', v; END IF;
  SELECT frequency_days INTO v FROM public.pricing_refresh_policy prp JOIN public.pricing_source s ON s.id = prp.pricing_source_id WHERE s.code = 'JUSTTCG';
  IF v <> 3 THEN RAISE EXCEPTION 'G2_DEFAULT: %', v; END IF;
END $g$;

COMMIT;
