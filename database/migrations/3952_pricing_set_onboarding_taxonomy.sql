-- STATUS: PROPOSTA -- ainda NAO aplicada. P16.4.1, Estados de Onboarding e Saude --
-- corrige o gap semantico de observabilidade identificado por Fabricio apos a confirmacao
-- real do SWSH8 (P16.4): `pricing_set_refresh_state.last_outcome = 'NEVER_RUN'` (Set recem
-- confirmado, nunca sincronizado) estava sendo contado junto com falhas operacionais reais
-- na mesma categoria binaria "problem" (`last_outcome != SUCCESS => problem`), fazendo a
-- Visao Geral virar CRITICA e a Saude das Fontes marcar a fonte como COM PROBLEMA por um
-- Set que simplesmente ainda nao teve sua primeira janela do dispatcher.
--
-- Nao cria coluna/tabela/status fisico novo -- P16.4.1 e so uma correcao de DERIVACAO,
-- nunca de persistencia. `pricing_set_refresh_state.last_outcome` continua exatamente com o
-- mesmo vocabulario de 8 valores da migration 3930 (nunca alterado aqui: NEVER_RUN, SUCCESS,
-- BUDGET_STOPPED, DEADLINE_STOPPED, TRANSIENT_ERROR, SET_TERMINAL_ERROR, AUTH_FAILURE,
-- RECONCILIATION_INCOMPLETE). `pricing_set_mapping.match_status` tambem continua intocado
-- (identidade externa confirmada != situacao operacional da sincronizacao, ver item 8 do
-- pedido de Fabricio -- nunca confundir os dois).
--
-- === Auditoria real dos 8 outcomes (item 1 do pedido) ===
-- Cada outcome foi confirmado por leitura direta de
-- supabase/functions/_shared/pricing-justtcg-refresh/set-refresh-core.ts (comentarios e
-- decideRunStatus/pageLoop reais), nao inferido:
--
--   NEVER_RUN                 -> ONBOARDING_PENDING  (default da migration 3930; nenhuma
--                                 tentativa aconteceu ainda -- exatamente o caso SWSH8)
--   BUDGET_STOPPED             -> PROCESSING           (core.ts linha ~18: "continuacao normal
--                                 (p_run_status=COMPLETED, nunca FAILED) -- o proprio desenho
--                                 da RPC close_ ja libera a lease com next_due_at=now(), entao
--                                 o proximo tick do dispatcher retoma via resume_offset")
--   DEADLINE_STOPPED           -> PROCESSING           (mesmo comentario acima -- deadline
--                                 interno de 110s por invocacao, nunca falha, so pausa segura
--                                 de pagina)
--   SUCCESS                    -> HEALTHY              (unico outcome que decideRunStatus()
--                                 nunca associa a COMPLETED_WITH_ERRORS/FAILED)
--   TRANSIENT_ERROR             -> PROBLEM              (decideRunStatus(): vira
--                                 COMPLETED_WITH_ERRORS -- falha real, ainda que retentavel no
--                                 proximo tick)
--   SET_TERMINAL_ERROR          -> PROBLEM              (decideRunStatus(): tambem
--                                 COMPLETED_WITH_ERRORS; alem disso e o unico outcome que a
--                                 RPC de fechamento (migration 3933, fora de escopo aqui) usa
--                                 para pausar o Set com pause_reason=SET_TERMINAL_ERROR --
--                                 estrutural, ex.: 404 na JustTCG, exige intervencao manual)
--   AUTH_FAILURE                -> PROBLEM              (decideRunStatus(): sempre FAILED,
--                                 mesmo com paginas anteriores bem-sucedidas no mesmo ciclo --
--                                 credencial quebrada e severo o bastante para nunca
--                                 aparecer como sucesso parcial)
--   RECONCILIATION_INCOMPLETE   -> PROBLEM              (core.ts linha ~21: "nunca e tratado
--                                 como SUCCESS" -- produzido pela reconciliacao de cobertura
--                                 por identidade da RPC de fechamento quando o ciclo termina
--                                 sem erro tecnico mas a contagem esperada/vista nao bate;
--                                 nao e falha de rede, mas e um sinal real de inconsistencia
--                                 de dados que merece revisao -- classificado como PROBLEM,
--                                 nao como um 5o bucket neutro, por decisao explicita desta
--                                 rodada, documentada aqui para Fabricio poder contestar)
--
-- Estados adicionais que participam da derivacao, fora do vocabulario de last_outcome:
--   is_paused=true              -> PAUSED (prioridade maxima -- um Set pausado nunca e
--                                 reclassificado como HEALTHY/PROBLEM/ONBOARDING_PENDING por
--                                 causa do outcome que o levou a pausa; ja existia como bucket
--                                 proprio antes desta migration, comportamento preservado)
--   lease_until > now()         -> PROCESSING (segunda prioridade -- uma tentativa esta
--                                 literalmente em andamento agora, independente do
--                                 last_outcome da tentativa ANTERIOR)
--
-- === Helper centralizado (unica fonte de verdade da taxonomia) ===
-- `pricing_derive_refresh_bucket()` -- funcao STABLE pura (sem leitura de tabela, so os 3
-- parametros), usada pelas 3 RPCs de leitura afetadas para nunca duplicar a regra em SQL
-- (e se um 4o outcome for adicionado no futuro, corrige-se em 1 lugar so). Nao e
-- SECURITY DEFINER (nao precisa -- nao acessa nada alem dos parametros).
CREATE OR REPLACE FUNCTION public.pricing_derive_refresh_bucket(
  p_is_paused boolean,
  p_lease_until timestamptz,
  p_last_outcome text
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_is_paused THEN 'PAUSED'
    WHEN p_lease_until IS NOT NULL AND p_lease_until > now() THEN 'PROCESSING'
    WHEN p_last_outcome = 'NEVER_RUN' THEN 'ONBOARDING_PENDING'
    WHEN p_last_outcome IN ('BUDGET_STOPPED', 'DEADLINE_STOPPED') THEN 'PROCESSING'
    WHEN p_last_outcome = 'SUCCESS' THEN 'HEALTHY'
    ELSE 'PROBLEM' -- TRANSIENT_ERROR, SET_TERMINAL_ERROR, AUTH_FAILURE, RECONCILIATION_INCOMPLETE
  END;
$function$;

REVOKE ALL ON FUNCTION public.pricing_derive_refresh_bucket(boolean, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pricing_derive_refresh_bucket(boolean, timestamptz, text) TO authenticated;

COMMENT ON FUNCTION public.pricing_derive_refresh_bucket(boolean, timestamptz, text) IS
  'P16.4.1 -- fonte unica da taxonomia ONBOARDING_PENDING/PROCESSING/HEALTHY/PROBLEM/PAUSED derivada de pricing_set_refresh_state (is_paused, lease_until, last_outcome). Nunca persiste nada -- pura funcao de leitura/derivacao, consumida por get_pricing_admin_overview(), admin_get_pricing_source_health() e admin_list_pricing_set_mappings(). Ver cabecalho da migration 3952 para a auditoria completa dos 8 valores de last_outcome (migration 3930) e a justificativa de cada classificacao.';

-- ===========================================================================================
-- 1) get_pricing_admin_overview() -- bloco "sets" ganha 2 buckets novos (onboarding_pending,
--    processing); healthy/paused/total preservam o MESMO calculo de antes (o helper produz
--    exatamente os mesmos valores para esses 3 nomes -- so "problem" muda de valor, nunca de
--    nome, porque a regra binaria antiga estava simplesmente errada). jsonb como retorno =
--    CREATE OR REPLACE de verdade, sem precisar de DROP.
-- ===========================================================================================
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

  -- P16.4.1: substitui a regra binaria antiga (last_outcome != SUCCESS OR is_paused =>
  -- problem) pelo helper de taxonomia -- healthy/paused/total continuam identicos em valor;
  -- "problem" agora so conta falha operacional REAL (nunca mais NEVER_RUN/BUDGET_STOPPED/
  -- DEADLINE_STOPPED); onboarding_pending/processing sao buckets novos, mutuamente
  -- exclusivos entre si e com healthy/problem/paused (healthy+onboarding_pending+processing+
  -- problem+paused = total, sempre).
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

  -- P16.1: Cobertura de Sets -- bloco independente de "sets" (Saude, acima), INTOCADO nesta
  -- migration (mesma regra da 3950).
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

COMMENT ON FUNCTION public.get_pricing_admin_overview() IS
  'P16.4.1 -- bloco "sets" ganha onboarding_pending/processing (taxonomia de pricing_derive_refresh_bucket); healthy/paused/total preservam o mesmo valor de antes, so "problem" muda de significado (agora so falha operacional real, nunca mais NEVER_RUN/BUDGET_STOPPED/DEADLINE_STOPPED). "coverage"/"mappings.coverage_pct" continuam com a semantica das migrations 3939/3950, intocadas.';

-- ===========================================================================================
-- 2) admin_get_pricing_source_health() -- ganha sets_onboarding_pending/sets_processing
--    (colunas novas, apendadas ao final da RETURNS TABLE para minimizar disrupcao). Requer
--    DROP porque RETURNS TABLE muda de forma -- CREATE OR REPLACE sozinho nao é suficiente
--    quando colunas são adicionadas.
-- ===========================================================================================
DROP FUNCTION IF EXISTS public.admin_get_pricing_source_health();

CREATE FUNCTION public.admin_get_pricing_source_health()
RETURNS TABLE(
  pricing_source_id uuid, pricing_source_code text, pricing_source_name text, is_active boolean,
  last_run_id uuid, last_run_type text, last_run_status text, last_run_finished_at timestamptz, last_run_triggered_by text,
  mappings_confirmed integer, mappings_pending integer, mappings_not_found integer, mappings_total integer, coverage_pct numeric,
  sets_healthy integer, sets_problem integer, sets_paused integer, sets_total integer,
  recent_failed_runs integer, recent_rate_limit_hits integer, last_error_summary text,
  sets_onboarding_pending integer, sets_processing integer
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
    rf.failed_count::int, rf.rate_limit_hits::int, rf.last_error_summary,
    sc.onboarding_pending::int, sc.processing::int
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
    -- P16.4.1: mesma substituicao da regra binaria pelo helper de taxonomia (ver
    -- get_pricing_admin_overview() acima) -- healthy/paused/total preservam o mesmo valor,
    -- "problem" passa a significar so falha operacional real.
    SELECT
      count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(psrs.is_paused, psrs.lease_until, psrs.last_outcome) = 'HEALTHY') AS healthy,
      count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(psrs.is_paused, psrs.lease_until, psrs.last_outcome) = 'ONBOARDING_PENDING') AS onboarding_pending,
      count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(psrs.is_paused, psrs.lease_until, psrs.last_outcome) = 'PROCESSING') AS processing,
      count(*) FILTER (WHERE public.pricing_derive_refresh_bucket(psrs.is_paused, psrs.lease_until, psrs.last_outcome) = 'PROBLEM') AS problem,
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

COMMENT ON FUNCTION public.admin_get_pricing_source_health() IS
  'P16.4.1 -- ganha sets_onboarding_pending/sets_processing (apendados ao final); sets_healthy/sets_paused/sets_total preservam o mesmo valor de antes, sets_problem passa a significar so falha operacional real (ver pricing_derive_refresh_bucket, migration 3952).';

-- ===========================================================================================
-- 3) admin_list_pricing_set_mappings() -- ganha 3 colunas novas derivadas de
--    pricing_set_refresh_state via LEFT JOIN (zero N+1 -- mesma query, 1 JOIN a mais):
--    refresh_status (taxonomia, NULL quando nao existe linha em pricing_set_mapping ainda
--    ou quando ela existe mas nunca foi CONFIRMED -- so mapping CONFIRMED ganha autoentrada
--    via trigger da migration 3932), refresh_last_outcome, refresh_last_success_at (brutos,
--    uteis para tooltip/detalhe sem reimplementar a taxonomia no frontend). Requer DROP pelo
--    mesmo motivo do item 2.
-- ===========================================================================================
DROP FUNCTION IF EXISTS public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer);

CREATE FUNCTION public.admin_list_pricing_set_mappings(
  p_status text[] DEFAULT NULL::text[],
  p_pricing_source_id uuid DEFAULT NULL::uuid,
  p_search text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  card_set_id uuid,
  card_set_code text,
  card_set_name text,
  pricing_source_id uuid,
  pricing_source_code text,
  external_set_id text,
  external_set_name text,
  match_status text,
  match_method text,
  last_checked_at timestamp with time zone,
  has_dependency boolean,
  refresh_status text,
  refresh_last_outcome text,
  refresh_last_success_at timestamp with time zone,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_limit int; v_offset int; v_search text; v_status text[];
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_SET_MAPPINGS_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');
  v_status := NULLIF(
    ARRAY(SELECT x FROM unnest(p_status) AS x WHERE x IN ('CONFIRMED', 'PENDING', 'NOT_FOUND', 'REJECTED', 'UNMAPPED')),
    ARRAY[]::text[]
  );

  RETURN QUERY
  WITH eligible_sets AS (
    SELECT cs.id, cs.code, cs.name, cs.release_date
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    JOIN public.game g ON g.id = ex.game_id
    WHERE g.code = 'POKEMON'
  ),
  eligible_sources AS (
    SELECT ps.id, ps.code
    FROM public.pricing_source ps
    WHERE ps.is_active
  )
  SELECT
    psm.id,
    es.id,
    es.code::text,
    es.name::text,
    esrc.id,
    esrc.code::text,
    psm.external_set_id::text,
    psm.external_set_name::text,
    COALESCE(psm.match_status, 'UNMAPPED') AS match_status,
    psm.match_method,
    psm.last_checked_at,
    public.pricing_set_mapping_dependency_exists(es.id, esrc.id) AS has_dependency,
    -- P16.4.1: taxonomia de onboarding/saude por linha -- NULL quando nao ha autoentrada em
    -- pricing_set_refresh_state ainda (Set UNMAPPED, ou mapping PENDING/NOT_FOUND/REJECTED
    -- que nunca chegou a ser CONFIRMED -- a trigger da migration 3932 so cria a linha em
    -- refresh_state quando match_status vira CONFIRMED).
    CASE WHEN psrs.id IS NULL THEN NULL
         ELSE public.pricing_derive_refresh_bucket(psrs.is_paused, psrs.lease_until, psrs.last_outcome)
    END AS refresh_status,
    psrs.last_outcome AS refresh_last_outcome,
    psrs.last_success_at AS refresh_last_success_at,
    count(*) OVER() AS total_count
  FROM eligible_sets es
  CROSS JOIN eligible_sources esrc
  LEFT JOIN public.pricing_set_mapping psm
    ON psm.card_set_id = es.id
    AND psm.pricing_source_id = esrc.id
  LEFT JOIN public.pricing_set_refresh_state psrs
    ON psrs.pricing_set_mapping_id = psm.id
  WHERE (p_pricing_source_id IS NULL OR esrc.id = p_pricing_source_id)
    AND (v_status IS NULL OR COALESCE(psm.match_status, 'UNMAPPED') = ANY(v_status))
    AND (v_search IS NULL OR es.name ILIKE '%' || v_search || '%' OR es.code ILIKE '%' || v_search || '%')
  ORDER BY es.release_date DESC NULLS LAST, es.code ASC
  LIMIT v_limit OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer) IS
  'P16.4.1 -- ganha refresh_status/refresh_last_outcome/refresh_last_success_at via LEFT JOIN pricing_set_refresh_state (zero N+1). refresh_status usa a mesma taxonomia central (pricing_derive_refresh_bucket, migration 3952) das demais RPCs de leitura -- NULL quando o mapping nunca foi CONFIRMED (sem autoentrada ainda, trigger da migration 3932). match_status/external_set_*/grade Set x Fonte preservam exatamente a semantica da migration 3950 (P16.1), intocada.';

-- ===========================================================================================
-- 4) admin_list_pricing_set_refresh_states() -- P16.4.1 revisao final (pedido de Fabricio,
--    2026-08-25): esta RPC (migration 3941, alimenta /pricing/sincronizacoes -- "Estado dos
--    Sets") tinha exatamente o mesmo antipadrao binario corrigido nas 3 RPCs acima
--    (`WHEN psrs.last_outcome = 'SUCCESS' THEN 'HEALTHY' ELSE 'PROBLEM'`), nao coberto pela
--    versao original desta migration -- gap identificado pelo proprio agente ao fechar
--    P16.4.1 e confirmado por Fabricio para correcao AGORA, na mesma migration ainda
--    PROPOSTA (nunca uma 3953 separada).
--
--    `derived_status` e seu CASE de 3 valores (HEALTHY/PROBLEM/PAUSED) sao preservados
--    BYTE-IDENTICOS -- nenhum consumidor existente quebra. `refresh_bucket` e uma coluna
--    NOVA (apendada, mesmo padrao dos itens 2/3 acima), usando o helper central para os
--    mesmos 5 valores das demais telas (ONBOARDING_PENDING/PROCESSING/HEALTHY/PROBLEM/
--    PAUSED). O filtro de status (`p_status`) passa a comparar contra `refresh_bucket`, nao
--    mais `derived_status` -- os 3 valores antigos (HEALTHY/PROBLEM/PAUSED) continuam
--    aceitos (sao um subconjunto valido do dominio novo), e a tela ganha capacidade de
--    filtrar tambem por ONBOARDING_PENDING/PROCESSING sem quebrar nenhuma URL/filtro salvo
--    que ja use os 3 valores antigos. Requer DROP pelo mesmo motivo dos itens 2/3 (RETURNS
--    TABLE muda de forma).
-- ===========================================================================================
DROP FUNCTION IF EXISTS public.admin_list_pricing_set_refresh_states(text, text[], uuid, integer, integer);

CREATE FUNCTION public.admin_list_pricing_set_refresh_states(
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
  mappings_confirmed integer, mappings_total integer,
  refresh_bucket text,
  total_count bigint
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
      -- P16.4.1: preservado byte-identico -- consumidores existentes de derived_status
      -- (nenhum a esta altura, mas o contrato nao muda) continuam recebendo exatamente o
      -- mesmo valor de antes.
      CASE WHEN psrs.is_paused THEN 'PAUSED'
           WHEN psrs.last_outcome = 'SUCCESS' THEN 'HEALTHY'
           ELSE 'PROBLEM' END AS derived_status,
      psrs.last_started_at, psrs.last_success_at, psrs.next_due_at,
      psrs.last_outcome, psrs.attempt_count,
      psrs.is_paused, psrs.pause_reason, psrs.paused_at,
      psrs.lease_until, psrs.leased_by, psrs.resume_offset, psrs.cycle_expected_card_count,
      mc.confirmed::int AS mappings_confirmed, mc.total::int AS mappings_total,
      -- P16.4.1: taxonomia central, mesma fonte unica das demais 3 RPCs de leitura desta
      -- migration -- NEVER_RUN/BUDGET_STOPPED/DEADLINE_STOPPED nunca mais aparecem como
      -- PROBLEM aqui.
      public.pricing_derive_refresh_bucket(psrs.is_paused, psrs.lease_until, psrs.last_outcome) AS refresh_bucket,
      count(*) OVER() AS total_count
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
  -- P16.4.1: filtro migrado de derived_status para refresh_bucket -- HEALTHY/PROBLEM/PAUSED
  -- continuam valores validos (subconjunto do dominio novo), ONBOARDING_PENDING/PROCESSING
  -- passam a ser filtraveis tambem.
  WHERE (p_status IS NULL OR array_length(p_status, 1) IS NULL OR rows.refresh_bucket = ANY(p_status))
  ORDER BY rows.next_due_at ASC NULLS LAST, rows.card_set_code
  LIMIT v_limit OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_set_refresh_states(text, text[], uuid, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_set_refresh_states(text, text[], uuid, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.admin_list_pricing_set_refresh_states(text, text[], uuid, integer, integer) IS
  'P16.4.1 (revisao final, 2026-08-25) -- ganha refresh_bucket (taxonomia central de pricing_derive_refresh_bucket, mesma fonte unica das demais RPCs de leitura desta migration). derived_status preservado byte-identico (HEALTHY/PROBLEM/PAUSED) para compatibilidade. Filtro p_status agora compara contra refresh_bucket -- os 3 valores antigos continuam aceitos, ONBOARDING_PENDING/PROCESSING passam a ser filtraveis tambem. Alimenta /pricing/sincronizacoes (Estado dos Sets).';
