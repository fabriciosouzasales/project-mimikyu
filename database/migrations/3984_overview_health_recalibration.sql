/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3984 - Visão Geral: alertas recalibrados + orçamento da API
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 5 (saúde contínua)

Problemas (LIVE 2026-10-10)
  1. 139 Sets em implantação (bootstrap) deixavam a Visão Geral em "Atenção" —
     implantação é estado normal; só é problema se PARAR.
  2. sets.next_due_at incluía Sets cujo bootstrap não terminou (next_due_at = hora da
     confirmação) → falso "Fila de atualização atrasada há mais de 1 hora".
  3. "Sets aguardando configuração" (8) misturava 6 Sets que a JustTCG não publica e
     2 Sets sem cartas no catálogo (SP, EXU) — nenhum acionável.
  4. Sem visão de consumo do mês × plano (10.000/mês, 1.000/dia — ADR-029).

O que faz
  A. pricing_source.monthly_request_limit / daily_request_limit (nullable, > 0);
     JUSTTCG = 10.000 / 1.000 (premissas comerciais confirmadas por Fabrício, ADR-029).
  B. Action log aceita PRICING_SET_MAPPING_NOT_FOUND (entidade PRICING_SET_MAPPING).
  C. Os 6 Sets sem correspondência na JustTCG (validação da Fase 3c) passam a ter
     pricing_set_mapping NOT_FOUND — tratamento explícito e reversível (a confirmação
     manual faz upgrade NOT_FOUND → CONFIRMED). Gate: exatamente 6, sem mapping prévio.
  D. get_pricing_admin_overview():
     - coverage: elegível = Set POKEMON com ≥1 carta ativa; + not_found, without_cards;
     - sets.next_due_at: só Sets que já tiveram o 1º refresh (aplicado em 2 passos no LIVE:
       migration 3984_overview_health_recalibration + 3984_overview_next_due_excludes_onboarding;
       este arquivo é o estado final);
     - onboarding: fila do bootstrap (pendentes/adquirindo/casando/concluídos/pausados),
       requisições restantes estimadas, último progresso, stalled (> 2 h sem progresso
       com fila ativa), ETA aproximada (1 Set por tick de 5 min);
     - api_budget: consumo do mês (UTC) e de hoje da fonte, limites, estimativa diária
       em regime (último refresh bem-sucedido de cada Set ou ceil(cartas/100), dividido
       pela frequência do Set) e projeção do mês;
     - cards_without_mapping (Sets já implantados) e products_without_variant.
     Resto do payload idêntico ao LIVE anterior.
===============================================================================
*/

-- A. Limites do plano por fonte
ALTER TABLE public.pricing_source
  ADD COLUMN monthly_request_limit integer CHECK (monthly_request_limit IS NULL OR monthly_request_limit > 0),
  ADD COLUMN daily_request_limit integer CHECK (daily_request_limit IS NULL OR daily_request_limit > 0);
COMMENT ON COLUMN public.pricing_source.monthly_request_limit IS 'Limite mensal de requisições do plano contratado (NULL = sem limite conhecido). (3984)';
COMMENT ON COLUMN public.pricing_source.daily_request_limit IS 'Limite diário de requisições do plano contratado (NULL = sem limite conhecido). (3984)';
UPDATE public.pricing_source SET monthly_request_limit = 10000, daily_request_limit = 1000 WHERE code = 'JUSTTCG';

-- B. Ação de log para Set sem correspondência
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_check;
ALTER TABLE public.pricing_admin_action_log ADD CONSTRAINT pricing_admin_action_log_action_check CHECK (action = ANY (ARRAY[
  'PRICING_REFRESH_FREQUENCY_CHANGED','PRICING_SOURCE_UPDATED','PRICING_MAPPING_CONFIRMED','PRICING_MAPPING_REJECTED',
  'PRICING_MAPPING_NOT_FOUND','PRICING_SET_MAPPING_DETAILS_UPDATED','PRICING_SET_MAPPING_CONFIRMED','PRICING_SET_MAPPING_REJECTED',
  'CARD_CONDITION_CREATED','CARD_CONDITION_UPDATED','PRICING_CONDITION_MAPPING_UPDATED','PRICING_MANUAL_PRICE_SET',
  'PRICING_PRODUCT_VARIANT_RECONCILED','PRICING_SET_BOOTSTRAP_REOPENED','PRICING_SET_REFRESH_PAUSED',
  'PRICING_SET_MAPPING_NOT_FOUND']::text[]));
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;
ALTER TABLE public.pricing_admin_action_log ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check CHECK (
  ((entity_type = 'PRICING_SOURCE') AND (action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED','PRICING_SOURCE_UPDATED','PRICING_PRODUCT_VARIANT_RECONCILED']::text[])))
  OR ((entity_type = 'PRICING_CARD_MAPPING') AND (action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED','PRICING_MAPPING_REJECTED','PRICING_MAPPING_NOT_FOUND']::text[])))
  OR ((entity_type = 'PRICING_SET_MAPPING') AND (action = ANY (ARRAY['PRICING_SET_MAPPING_DETAILS_UPDATED','PRICING_SET_MAPPING_CONFIRMED','PRICING_SET_MAPPING_REJECTED','PRICING_SET_BOOTSTRAP_REOPENED','PRICING_SET_REFRESH_PAUSED','PRICING_SET_MAPPING_NOT_FOUND']::text[])))
  OR ((entity_type = 'CARD_CONDITION') AND (action = ANY (ARRAY['CARD_CONDITION_CREATED','CARD_CONDITION_UPDATED']::text[])))
  OR ((entity_type = 'PRICING_CONDITION_MAPPING') AND (action = 'PRICING_CONDITION_MAPPING_UPDATED'))
  OR ((entity_type = 'PRICING_MANUAL_PRICE') AND (action = 'PRICING_MANUAL_PRICE_SET')));

-- C. 6 Sets sem correspondência na JustTCG → NOT_FOUND (gate exato)
DO $$
DECLARE
  v_source uuid;
  v_n integer;
BEGIN
  SELECT id INTO v_source FROM public.pricing_source WHERE code = 'JUSTTCG';
  SELECT count(*) INTO v_n
    FROM public.card_set cs
   WHERE cs.code IN ('FUT2020','TK-EX-M','TK-EX-P','EX5.5','TK-EX-LATIA','TK-EX-LATIO')
     AND NOT EXISTS (SELECT 1 FROM public.pricing_set_mapping m WHERE m.card_set_id = cs.id AND m.pricing_source_id = v_source);
  IF v_n <> 6 THEN
    RAISE EXCEPTION '3984_GATE: esperados 6 Sets sem mapping, encontrados %', v_n;
  END IF;

  WITH ins AS (
    INSERT INTO public.pricing_set_mapping (card_set_id, pricing_source_id, match_status, match_method, match_evidence, last_checked_at)
    SELECT cs.id, v_source, 'NOT_FOUND', 'ADMIN_MANUAL_SELECTION',
           jsonb_build_object('flow', 'BATCH_DISCOVERY_REVIEW', 'reason', 'Set não publicado pela JustTCG (validação Fase 3c, 2026-10-10)'),
           now()
      FROM public.card_set cs
     WHERE cs.code IN ('FUT2020','TK-EX-M','TK-EX-P','EX5.5','TK-EX-LATIA','TK-EX-LATIO')
    RETURNING id, card_set_id
  )
  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  SELECT NULL, 'PRICING_SET_MAPPING_NOT_FOUND', 'PRICING_SET_MAPPING', ins.id,
         jsonb_build_object('outcome', 'INSERTED', 'migration', '3984', 'card_set_code', cs.code,
                            'reason', 'Set não publicado pela JustTCG (validação Fase 3c)')
    FROM ins JOIN public.card_set cs ON cs.id = ins.card_set_id;
END $$;

-- D. Visão Geral recalibrada
CREATE OR REPLACE FUNCTION public.get_pricing_admin_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_mapping_counts record;
  v_set_counts record;
  v_coverage record;
  v_onboarding record;
  v_budget record;
  v_steady numeric;
  v_last_progress timestamptz;
  v_month_start timestamptz := date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_start timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_days_in_month integer := extract(day FROM (date_trunc('month', now() AT TIME ZONE 'UTC') + interval '1 month - 1 day'))::int;
  v_day_of_month integer := extract(day FROM now() AT TIME ZONE 'UTC')::int;
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
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(rs.is_paused, rs.lease_until, rs.last_outcome) = 'HEALTHY') AS healthy,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(rs.is_paused, rs.lease_until, rs.last_outcome) = 'ONBOARDING_PENDING') AS onboarding_pending,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(rs.is_paused, rs.lease_until, rs.last_outcome) = 'PROCESSING') AS processing,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(rs.is_paused, rs.lease_until, rs.last_outcome) = 'PROBLEM') AS problem,
    count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(rs.is_paused, rs.lease_until, rs.last_outcome) = 'PAUSED') AS paused,
    -- 3984: Set ainda sem 1º refresh (implantação) não conta como fila atrasada — seu next_due_at é a
    -- hora da confirmação, não um vencimento real. Parada da implantação é sinalizada por onboarding.stalled.
    min(rs.next_due_at) FILTER (WHERE NOT rs.is_paused AND rs.last_outcome <> 'NEVER_RUN') AS next_due_at
  INTO v_set_counts
  FROM public.pricing_set_refresh_state rs
  LEFT JOIN public.pricing_set_bootstrap_state bs ON bs.pricing_set_mapping_id = rs.pricing_set_mapping_id;

  -- 3984: elegível = Set POKEMON com ao menos uma carta ativa (Set vazio não tem o que precificar).
  WITH sets AS (
    SELECT cs.id,
           EXISTS (SELECT 1 FROM public.card c WHERE c.card_set_id = cs.id AND c.is_active) AS has_cards,
           (SELECT psm.match_status FROM public.pricing_set_mapping psm
             WHERE psm.card_set_id = cs.id
               AND psm.pricing_source_id IN (SELECT ps.id FROM public.pricing_source ps WHERE ps.is_active)
             ORDER BY (psm.match_status = 'CONFIRMED') DESC LIMIT 1) AS status
      FROM public.card_set cs
      JOIN public.expansion ex ON ex.id = cs.expansion_id
      JOIN public.game g ON g.id = ex.game_id
     WHERE g.code = 'POKEMON'
  )
  SELECT count(*) FILTER (WHERE has_cards) AS eligible_total,
         count(*) FILTER (WHERE has_cards AND status IS NOT NULL) AS covered,
         count(*) FILTER (WHERE has_cards AND status = 'CONFIRMED') AS confirmed,
         count(*) FILTER (WHERE has_cards AND status = 'NOT_FOUND') AS not_found,
         count(*) FILTER (WHERE has_cards AND (status IS NULL OR status = 'PENDING')) AS unconfigured,
         count(*) FILTER (WHERE NOT has_cards AND status IS NULL) AS without_cards
    INTO v_coverage
    FROM sets;

  -- Fila do bootstrap (implantação de Sets confirmados)
  SELECT
    count(*) FILTER (WHERE bs.status = 'PENDING') AS pending,
    count(*) FILTER (WHERE bs.status = 'ACQUIRING') AS acquiring,
    count(*) FILTER (WHERE bs.status = 'MATCHING') AS matching,
    count(*) FILTER (WHERE bs.status = 'COMPLETE') AS complete,
    count(*) FILTER (WHERE bs.status = 'PAUSED') AS paused,
    count(*) AS total,
    COALESCE(sum(CASE WHEN bs.status IN ('PENDING', 'ACQUIRING') THEN
      greatest(1, ceil(greatest(cnt.n - bs.acquisition_resume_offset, 0) / 100.0)) ELSE 0 END), 0)::int AS remaining_requests
  INTO v_onboarding
  FROM public.pricing_set_bootstrap_state bs
  JOIN public.pricing_set_mapping m ON m.id = bs.pricing_set_mapping_id AND m.match_status = 'CONFIRMED'
  CROSS JOIN LATERAL (SELECT count(*)::int AS n FROM public.card c WHERE c.card_set_id = m.card_set_id AND c.is_active) cnt;

  SELECT max(sr.finished_at) INTO v_last_progress
    FROM public.pricing_sync_run sr
   WHERE sr.run_type = 'CARD_SYNC' AND sr.status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS');

  -- Orçamento da fonte ativa com limite conhecido
  SELECT ps.id, ps.code, ps.monthly_request_limit, ps.daily_request_limit,
         COALESCE((SELECT sum(sr.requests_made) FROM public.pricing_sync_run sr
                    WHERE sr.pricing_source_id = ps.id AND sr.started_at >= v_month_start), 0)::int AS month_to_date,
         COALESCE((SELECT sum(sr.requests_made) FROM public.pricing_sync_run sr
                    WHERE sr.pricing_source_id = ps.id AND sr.started_at >= v_day_start), 0)::int AS today
    INTO v_budget
    FROM public.pricing_source ps
   WHERE ps.is_active
   ORDER BY (ps.monthly_request_limit IS NOT NULL) DESC, ps.source_order
   LIMIT 1;

  -- Consumo diário em regime: custo do último refresh bem-sucedido do Set (ou páginas de 100 cartas) / frequência.
  SELECT COALESCE(sum(
           COALESCE(NULLIF(lr.requests_made, 0), greatest(1, ceil(cnt.n / 100.0)))::numeric
           / COALESCE(ep.frequency_days, rp.frequency_days, 1)), 0)
    INTO v_steady
    FROM public.pricing_set_refresh_state rs
    JOIN public.pricing_set_mapping m ON m.id = rs.pricing_set_mapping_id AND m.match_status = 'CONFIRMED'
    JOIN public.card_set cs ON cs.id = m.card_set_id
    LEFT JOIN public.pricing_refresh_expansion_policy ep ON ep.pricing_source_id = m.pricing_source_id AND ep.expansion_id = cs.expansion_id
    LEFT JOIN public.pricing_refresh_policy rp ON rp.pricing_source_id = m.pricing_source_id
    LEFT JOIN public.pricing_sync_run lr ON lr.id = rs.last_sync_run_id AND rs.last_outcome = 'SUCCESS'
    CROSS JOIN LATERAL (SELECT count(*)::int AS n FROM public.card c WHERE c.card_set_id = m.card_set_id AND c.is_active) cnt
   WHERE NOT rs.is_paused
     AND m.pricing_source_id = v_budget.id;

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
      'eligible_total', v_coverage.eligible_total,
      'covered', v_coverage.covered,
      'confirmed', v_coverage.confirmed,
      'not_found', v_coverage.not_found,
      'unconfigured', v_coverage.unconfigured,
      'without_cards', v_coverage.without_cards
    ),
    'products_count', (SELECT count(*) FROM public.pricing_product),
    'products_without_variant', (SELECT count(*) FROM public.pricing_product WHERE is_active AND card_variant_id IS NULL),
    'cards_without_mapping', (
      SELECT count(*)
        FROM public.pricing_set_mapping m
        JOIN public.pricing_set_bootstrap_state bs ON bs.pricing_set_mapping_id = m.id AND bs.status = 'COMPLETE'
        JOIN public.card c ON c.card_set_id = m.card_set_id AND c.is_active
       WHERE m.match_status = 'CONFIRMED'
         AND NOT EXISTS (SELECT 1 FROM public.pricing_card_mapping pcm
                          WHERE pcm.card_id = c.id AND pcm.pricing_source_id = m.pricing_source_id)
    ),
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
    'onboarding', jsonb_build_object(
      'pending', v_onboarding.pending,
      'acquiring', v_onboarding.acquiring,
      'matching', v_onboarding.matching,
      'complete', v_onboarding.complete,
      'paused', v_onboarding.paused,
      'total', v_onboarding.total,
      'remaining_requests', v_onboarding.remaining_requests,
      'last_progress_at', v_last_progress,
      'eta_minutes', ((v_onboarding.pending + v_onboarding.acquiring) * 2 + v_onboarding.matching) * 5,
      'stalled', (v_onboarding.pending + v_onboarding.acquiring + v_onboarding.matching) > 0
                 AND (v_last_progress IS NULL OR v_last_progress < now() - interval '2 hours')
    ),
    'api_budget', CASE WHEN v_budget.id IS NULL THEN NULL ELSE jsonb_build_object(
      'pricing_source_code', v_budget.code,
      'monthly_limit', v_budget.monthly_request_limit,
      'daily_limit', v_budget.daily_request_limit,
      'month_to_date', v_budget.month_to_date,
      'today', v_budget.today,
      'steady_daily_estimate', round(v_steady)::int,
      'onboarding_remaining', v_onboarding.remaining_requests,
      'days_in_month', v_days_in_month,
      'day_of_month', v_day_of_month,
      'projected_month', (v_budget.month_to_date
                          + greatest(round(v_steady) - v_budget.today, 0)
                          + round(v_steady) * (v_days_in_month - v_day_of_month)
                          + v_onboarding.remaining_requests)::int
    ) END,
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
