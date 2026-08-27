-- STATUS: PROPOSTA -- ainda NAO aplicada em producao. Testada em BEGIN/ROLLBACK nesta
-- rodada (P16.5.1, item 3 do escopo autorizado por Fabricio em 2026-08-26). Aguarda
-- autorizacao explicita para aplicacao real.
--
-- REVISAO POS-REVIEW (mesmo dia, antes de qualquer aplicacao) -- 4 pontos exigidos por
-- Fabricio, todos incorporados nesta versao:
--
-- 1. COMPLETE PROVADO PELO BANCO -- close_pricing_set_bootstrap_attempt() NAO recebe mais
--    cards_confirmed/cards_pending/cards_not_found do caller. Em MATCHING_COMPLETE, a
--    propria RPC deriva as contagens via SQL e so marca COMPLETE se: (a) toda carta ativa
--    local do Set tem pricing_card_mapping para esta fonte (mesmo criterio ja validado do
--    backfill em 3956), e (b) todo mapping CONFIRMED tem ao menos 1 pricing_source_card_identity
--    CONFIRMED com identity_role PRIMARY/ALTERNATE (mesmo gate que ja protege o dispatcher de
--    price-refresh em 3933). Se a prova falha, NUNCA marca COMPLETE -- vira
--    RECONCILIATION_INCOMPLETE (mesmo espirito do RECONCILIATION_INCOMPLETE de 3933): erro
--    observavel, backoff, sem pausa automatica, staging preservado para o proximo ciclo.
--
-- 2. MAQUINA DE ESTADOS PROTEGIDA -- checkpoint_pricing_set_bootstrap_acquisition_page() só
--    aceita progresso quando status IN ('PENDING','ACQUIRING') e nunca aceita
--    acquisition_resume_offset menor que o atual (RAISE EXCEPTION -- indicativo de bug do
--    caller, nunca aplicado silenciosamente). close_...() só aceita NO_MORE_PAGES a partir de
--    ACQUIRING e MATCHING_COMPLETE só a partir de MATCHING -- qualquer outra combinacao
--    devolve 'INVALID_TRANSITION' sem tocar em pricing_set_bootstrap_state. COMPLETE/PAUSED
--    nunca podem ser alterados por uma tentativa antiga por construcao: os dois unicos
--    UPDATEs que atribuem esses status tambem zeram lease_until/leased_by no mesmo comando,
--    e tanto checkpoint quanto close exigem lease_until > now() para encontrar a linha --
--    logo uma linha COMPLETE/PAUSED nunca tem lease valida para ser reaberta.
--
-- 3. LEASE -- close_...() agora bloqueia e valida pricing_set_bootstrap_state (leased_by =
--    run E lease_until > now()) ANTES de tocar em pricing_sync_run. Se a lease nao for mais
--    valida (expirou, ou ja foi reconciliada/reclamada por outro run), devolve 'LEASE_INVALID'
--    sem escrever nada -- nem em pricing_sync_run, nem em pricing_set_bootstrap_state. O run
--    problematico fica para a reconciliacao de lease orfa de open_...() no proximo ciclo.
--    Diverge deliberadamente de close_pricing_set_refresh_attempt (3933), que só checa
--    leased_by (sem checar lease_until) -- aqui a exigencia é mais estrita a pedido de
--    Fabricio.
--
-- 4. RETRY SEM AUTO-PAUSE -- o auto-pause por MAX_ATTEMPTS_EXCEEDED (existente na primeira
--    versao desta migration) foi REMOVIDO para TRANSIENT_ERROR/AUTH_FAILURE/
--    RECONCILIATION_INCOMPLETE. Os 3 continuam incrementando attempt_count, aplicando backoff
--    exponencial com teto de 3600s (mesma formula de 3933) e gravando last_error_summary
--    observavel -- viram retry automatico indefinido, nunca pausam sozinhos. Só
--    SET_TERMINAL_ERROR continua pausando imediatamente (é uma decisao explicita do caller,
--    nao uma falha transitoria). A politica de pausa por excesso de tentativas fica para
--    quando existir uma acao administrativa de retomada -- 'MAX_ATTEMPTS_EXCEEDED' permanece
--    no vocabulario de pause_reason (3953) para esse uso futuro, mas nenhuma logica aqui o
--    aciona mais.
--
-- Runs de bootstrap continuam usando run_type='CARD_SYNC' (nao um run_type novo) --
-- reaproveita os indices unicos parciais 3907/3926 ja existentes para a serializacao total
-- por fonte, sem exigir nenhuma migration adicional (ver nota completa em 3953).

CREATE OR REPLACE FUNCTION public.open_pricing_set_bootstrap_attempt(p_pricing_source_id uuid)
RETURNS TABLE(
  outcome text,
  sync_run_id uuid,
  pricing_set_mapping_id uuid,
  card_set_id uuid,
  external_set_id text,
  status text,
  acquisition_resume_offset integer
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_run_id uuid;
  v_lease_seconds constant integer := 180;
BEGIN
  -- Reconciliacao de runs orfaos -- mesmo padrao de open_pricing_set_refresh_attempt (3933).
  UPDATE public.pricing_sync_run sr
  SET status = 'FAILED',
      error_summary = 'ORPHANED_RUN_RECONCILED',
      finished_at = now()
  WHERE sr.pricing_source_id = p_pricing_source_id
    AND sr.status IN ('RECEIVED', 'PROCESSING')
    AND sr.run_type = 'CARD_SYNC'
    AND EXISTS (
      SELECT 1 FROM public.pricing_set_bootstrap_state psbs
      WHERE psbs.leased_by = sr.id AND psbs.lease_until < now()
    );

  SELECT psm.id AS pricing_set_mapping_id, psm.card_set_id, psm.external_set_id,
         psbs.id AS bootstrap_state_id, psbs.status, psbs.acquisition_resume_offset
  INTO v_candidate
  FROM public.pricing_set_bootstrap_state psbs
  JOIN public.pricing_set_mapping psm ON psm.id = psbs.pricing_set_mapping_id
  WHERE psbs.status NOT IN ('COMPLETE', 'PAUSED')
    AND psbs.next_attempt_at <= now()
    AND (psbs.lease_until IS NULL OR psbs.lease_until < now())
    AND psm.pricing_source_id = p_pricing_source_id
    AND psm.match_status = 'CONFIRMED'
  ORDER BY psbs.next_attempt_at ASC, psbs.last_started_at ASC NULLS FIRST, psbs.id ASC
  FOR UPDATE OF psbs SKIP LOCKED
  LIMIT 1;

  IF v_candidate IS NULL THEN
    RETURN QUERY SELECT 'NO_CANDIDATE'::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
                         NULL::text, NULL::integer;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.pricing_sync_run (
      pricing_source_id, run_type, status, requests_made, rate_limit_hits,
      triggered_by, pricing_set_mapping_id
    ) VALUES (
      p_pricing_source_id, 'CARD_SYNC', 'PROCESSING', 0, 0, 'SCHEDULED',
      v_candidate.pricing_set_mapping_id
    )
    RETURNING id INTO v_run_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'SOURCE_BUSY'::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
                         NULL::text, NULL::integer;
    RETURN;
  END;

  UPDATE public.pricing_set_bootstrap_state
  SET lease_until = now() + make_interval(secs => v_lease_seconds),
      leased_by = v_run_id,
      last_started_at = now()
  WHERE id = v_candidate.bootstrap_state_id;

  RETURN QUERY SELECT 'CLAIMED'::text, v_run_id, v_candidate.pricing_set_mapping_id,
                      v_candidate.card_set_id, v_candidate.external_set_id,
                      v_candidate.status, v_candidate.acquisition_resume_offset;
END;
$function$;


CREATE OR REPLACE FUNCTION public.checkpoint_pricing_set_bootstrap_acquisition_page(
  p_sync_run_id uuid,
  p_new_resume_offset integer,
  p_staged_cards jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_state record;
BEGIN
  SELECT psbs.* INTO v_state
  FROM public.pricing_set_bootstrap_state psbs
  WHERE psbs.leased_by = p_sync_run_id
    AND psbs.lease_until > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Ponto 2 (Fabricio): checkpoint de aquisicao só é válido em PENDING/ACQUIRING -- nunca em
  -- MATCHING (que já fechou a aquisicao) nem em COMPLETE/PAUSED (terminais, estruturalmente
  -- inalcancaveis aqui por já terem lease_until NULL).
  IF v_state.status NOT IN ('PENDING', 'ACQUIRING') THEN
    RETURN false;
  END IF;

  -- Ponto 2: offset nunca retrocede -- sinal de bug do caller (ex.: reprocessou uma pagina
  -- antiga fora de ordem), nunca aplicado silenciosamente.
  IF p_new_resume_offset < v_state.acquisition_resume_offset THEN
    RAISE EXCEPTION 'acquisition_resume_offset nao pode retroceder: atual=%, recebido=%',
      v_state.acquisition_resume_offset, p_new_resume_offset;
  END IF;

  INSERT INTO public.pricing_set_bootstrap_card_staging (
    pricing_set_mapping_id, external_card_id, external_number, external_name
  )
  SELECT v_state.pricing_set_mapping_id,
         item ->> 'external_card_id',
         item ->> 'number',
         item ->> 'name'
  FROM jsonb_array_elements(coalesce(p_staged_cards, '[]'::jsonb)) AS item
  ON CONFLICT (pricing_set_mapping_id, external_card_id)
  DO UPDATE SET external_number = EXCLUDED.external_number,
                external_name = EXCLUDED.external_name,
                updated_at = now();

  -- Correcao P16.5.1 original (Fabricio): qualquer checkpoint que avance a aquisicao com
  -- sucesso reseta attempt_count -- falhas esparsas nunca acumulam indevidamente.
  UPDATE public.pricing_set_bootstrap_state
  SET acquisition_resume_offset = p_new_resume_offset,
      status = CASE WHEN status = 'PENDING' THEN 'ACQUIRING' ELSE status END,
      attempt_count = 0
  WHERE id = v_state.id;

  RETURN true;
END;
$function$;


CREATE OR REPLACE FUNCTION public.close_pricing_set_bootstrap_attempt(
  p_sync_run_id uuid,
  p_phase_outcome text,
  p_run_status text,
  p_requests_made integer,
  p_rate_limit_hits integer DEFAULT 0,
  p_error_summary text DEFAULT NULL
)
RETURNS TABLE(final_status text)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_state record;
  v_next_attempt_count integer;
  v_local_active_cards integer;
  v_mapping_count integer;
  v_confirmed_count integer;
  v_pending_count integer;
  v_not_found_count integer;
  v_confirmed_missing_identity integer;
BEGIN
  IF p_phase_outcome NOT IN ('NO_MORE_PAGES', 'BUDGET_STOPPED', 'DEADLINE_STOPPED',
                             'MATCHING_COMPLETE', 'TRANSIENT_ERROR', 'SET_TERMINAL_ERROR',
                             'AUTH_FAILURE') THEN
    RAISE EXCEPTION 'p_phase_outcome invalido: %', p_phase_outcome;
  END IF;

  -- Ponto 3 (Fabricio): valida e bloqueia PRIMEIRO o bootstrap_state -- exige leased_by E
  -- lease_until > now() (mais estrito que close_pricing_set_refresh_attempt/3933, que só
  -- checa leased_by). pricing_sync_run só é tocado depois desta validacao passar.
  SELECT psbs.* INTO v_state
  FROM public.pricing_set_bootstrap_state psbs
  WHERE psbs.leased_by = p_sync_run_id
    AND psbs.lease_until > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'LEASE_INVALID'::text;
    RETURN;
  END IF;

  UPDATE public.pricing_sync_run
  SET status = p_run_status,
      finished_at = now(),
      requests_made = p_requests_made,
      rate_limit_hits = p_rate_limit_hits,
      error_summary = p_error_summary
  WHERE id = p_sync_run_id;

  IF p_phase_outcome = 'NO_MORE_PAGES' THEN
    -- Ponto 2: só válido a partir de ACQUIRING. O caller deve sempre fazer ao menos 1
    -- checkpoint (mesmo vazio) antes de declarar NO_MORE_PAGES, mesmo para um Set sem
    -- nenhuma pagina externa -- nunca pula PENDING->MATCHING direto.
    IF v_state.status <> 'ACQUIRING' THEN
      -- Lease liberada mesmo em transicao invalida -- o status/contadores permanecem
      -- intocados (maquina de estados protegida), mas nao ha motivo para reter a lease por
      -- ate 180s so por causa de um engano do caller.
      UPDATE public.pricing_set_bootstrap_state SET lease_until = NULL, leased_by = NULL WHERE id = v_state.id;
      RETURN QUERY SELECT 'INVALID_TRANSITION'::text;
      RETURN;
    END IF;
    UPDATE public.pricing_set_bootstrap_state
    SET lease_until = NULL, leased_by = NULL,
        status = 'MATCHING',
        next_attempt_at = now(),
        attempt_count = 0,
        last_outcome = 'NO_MORE_PAGES', last_error_summary = NULL,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT 'MATCHING'::text;
    RETURN;
  END IF;

  IF p_phase_outcome IN ('BUDGET_STOPPED', 'DEADLINE_STOPPED') THEN
    UPDATE public.pricing_set_bootstrap_state
    SET lease_until = NULL, leased_by = NULL,
        next_attempt_at = now(),
        last_outcome = p_phase_outcome,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT v_state.status::text;
    RETURN;
  END IF;

  IF p_phase_outcome = 'MATCHING_COMPLETE' THEN
    -- Ponto 2: só válido a partir de MATCHING.
    IF v_state.status <> 'MATCHING' THEN
      UPDATE public.pricing_set_bootstrap_state SET lease_until = NULL, leased_by = NULL WHERE id = v_state.id;
      RETURN QUERY SELECT 'INVALID_TRANSITION'::text;
      RETURN;
    END IF;

    -- Ponto 1: COMPLETE nunca confia em contagens do caller -- deriva no banco, mesmo
    -- criterio validado do backfill (3956): toda carta ativa local precisa ter
    -- pricing_card_mapping para esta fonte, e todo mapping CONFIRMED precisa de ao menos 1
    -- identity CONFIRMED PRIMARY/ALTERNATE.
    SELECT
      count(DISTINCT c.id),
      count(DISTINCT pcm.id),
      count(*) FILTER (WHERE pcm.match_status = 'CONFIRMED'),
      count(*) FILTER (WHERE pcm.match_status = 'PENDING'),
      count(*) FILTER (WHERE pcm.match_status = 'NOT_FOUND'),
      count(*) FILTER (WHERE pcm.match_status = 'CONFIRMED' AND NOT EXISTS (
        SELECT 1 FROM public.pricing_source_card_identity psci
        WHERE psci.pricing_card_mapping_id = pcm.id
          AND psci.match_status = 'CONFIRMED'
          AND psci.identity_role IN ('PRIMARY', 'ALTERNATE')
      ))
    INTO v_local_active_cards, v_mapping_count, v_confirmed_count, v_pending_count,
         v_not_found_count, v_confirmed_missing_identity
    FROM public.pricing_set_mapping psm
    JOIN public.card c ON c.card_set_id = psm.card_set_id AND c.is_active = true
    LEFT JOIN public.pricing_card_mapping pcm ON pcm.card_id = c.id AND pcm.pricing_source_id = psm.pricing_source_id
    WHERE psm.id = v_state.pricing_set_mapping_id;

    IF v_local_active_cards <> v_mapping_count OR v_confirmed_missing_identity > 0 THEN
      -- Prova de completude falhou -- NUNCA marca COMPLETE. Ponto 4: tratado como retry
      -- automatico sem pausa (mesma politica de TRANSIENT_ERROR/AUTH_FAILURE abaixo).
      -- Staging preservado -- a proxima tentativa de matching pode precisar dele de novo.
      v_next_attempt_count := v_state.attempt_count + 1;
      UPDATE public.pricing_set_bootstrap_state
      SET lease_until = NULL, leased_by = NULL,
          attempt_count = v_next_attempt_count,
          next_attempt_at = now() + make_interval(secs => LEAST(3600, 30 * power(2, v_state.attempt_count))::integer),
          last_outcome = 'RECONCILIATION_INCOMPLETE',
          last_error_summary = format('cobertura %s/%s cartas mapeadas, %s CONFIRMED sem identity',
                                       v_mapping_count, v_local_active_cards, v_confirmed_missing_identity),
          last_sync_run_id = p_sync_run_id
      WHERE id = v_state.id;
      RETURN QUERY SELECT 'RECONCILIATION_INCOMPLETE'::text;
      RETURN;
    END IF;

    UPDATE public.pricing_set_bootstrap_state
    SET lease_until = NULL, leased_by = NULL,
        status = 'COMPLETE',
        next_attempt_at = now(),
        attempt_count = 0,
        cards_confirmed = v_confirmed_count,
        cards_pending = v_pending_count,
        cards_not_found = v_not_found_count,
        last_outcome = 'MATCHING_COMPLETE', last_error_summary = NULL,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;

    DELETE FROM public.pricing_set_bootstrap_card_staging
    WHERE pricing_set_mapping_id = v_state.pricing_set_mapping_id;

    RETURN QUERY SELECT 'COMPLETE'::text;
    RETURN;
  END IF;

  IF p_phase_outcome = 'SET_TERMINAL_ERROR' THEN
    UPDATE public.pricing_set_bootstrap_state
    SET lease_until = NULL, leased_by = NULL,
        status = 'PAUSED', pause_reason = 'SET_TERMINAL_ERROR', paused_at = now(),
        attempt_count = attempt_count + 1,
        last_outcome = 'SET_TERMINAL_ERROR', last_error_summary = p_error_summary,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;

    DELETE FROM public.pricing_set_bootstrap_card_staging
    WHERE pricing_set_mapping_id = v_state.pricing_set_mapping_id;

    RETURN QUERY SELECT 'PAUSED'::text;
    RETURN;
  END IF;

  -- TRANSIENT_ERROR / AUTH_FAILURE -- Ponto 4: auto-pause por MAX_ATTEMPTS removido nesta
  -- rodada. Mantém attempt_count, backoff exponencial (teto 3600s, mesma formula de 3933),
  -- last_error_summary observavel e retry automatico indefinido. AUTH_FAILURE aplica backoff
  -- (diferente de close_pricing_set_refresh_attempt/3933, que nao reagenda em AUTH_FAILURE) --
  -- evita o bootstrap travar indefinidamente por uma falha de auth transitoria.
  v_next_attempt_count := v_state.attempt_count + 1;
  UPDATE public.pricing_set_bootstrap_state
  SET lease_until = NULL, leased_by = NULL,
      attempt_count = v_next_attempt_count,
      next_attempt_at = now() + make_interval(secs => LEAST(3600, 30 * power(2, v_state.attempt_count))::integer),
      last_outcome = p_phase_outcome, last_error_summary = p_error_summary,
      last_sync_run_id = p_sync_run_id
  WHERE id = v_state.id;

  RETURN QUERY SELECT v_state.status::text;
END;
$function$;
