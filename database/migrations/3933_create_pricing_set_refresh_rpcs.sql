-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-22.
-- Testada em BEGIN/ROLLBACK (claim real, exclusao mutua 3926/3907, gate de reconciliacao
-- RECONCILIATION_INCOMPLETE e SUCCESS com cobertura real, reconciliacao de run orfao)
-- antes da aplicacao real.
-- P15, Scheduler Durável por Set, MUST HAVE itens 3/5/9/10/11 (claim
-- atômico, checkpoint por página, finalização atômica, reconciliação de cobertura, run
-- órfão) + os 2 ajustes desta rodada (gate de reconciliação por cobertura; reconciliação de
-- run órfão dentro do claim).
--
-- Grants: NENHUM grant novo é necessário. pricing_set_mapping_id (coluna nova, migration
-- 3931) e todo o resto do INSERT de pricing_sync_run cabem no grant de INSERT ja existente
-- (tabela inteira, "service_role=ar") -- por isso open_pricing_set_refresh_attempt grava
-- pricing_set_mapping_id DIRETO no INSERT, nunca num UPDATE separado. As unicas colunas de
-- pricing_sync_run alteradas por UPDATE nestas RPCs sao exatamente as 6 ja concedidas
-- column-level a service_role (status, requests_made, rate_limit_hits, error_summary,
-- finished_at, requests_remaining_at_end -- esta ultima nao usada aqui). updated_at nunca
-- e setado explicitamente -- trg_pricing_sync_run_set_updated_at cuida disso sozinho, mesmo
-- padrao ja usado por supabase-adapter.ts::updateSyncRun. pricing_set_refresh_state tem
-- grant de UPDATE de tabela inteira para service_role (migration 3930) -- sem restricao
-- column-level ali.
--
-- SECURITY INVOKER (nao DEFINER) nas 3 -- unico chamador real e sempre service_role, que ja
-- possui todos os grants diretos necessarios (mesmo racional de resolve_pricing_products_batch,
-- migration 3928). EXECUTE concedido somente a service_role.

CREATE FUNCTION public.open_pricing_set_refresh_attempt(p_pricing_source_id uuid)
RETURNS TABLE (
  outcome text,
  sync_run_id uuid,
  pricing_set_mapping_id uuid,
  card_set_id uuid,
  external_set_id text,
  resume_offset integer,
  cycle_seen_external_card_ids text[]
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_candidate record;
  v_run_id uuid;
  v_lease_seconds constant integer := 180; -- 150s timeout do caller (migration 3929) + 30s de margem
BEGIN
  -- Passo 0: reconciliar run orfao (lease vencido) desta fonte ANTES de qualquer claim novo.
  -- Um PRICE_REFRESH parado em RECEIVED/PROCESSING bloqueia 3926 para a fonte INTEIRA
  -- (nao so o Set do run travado) -- por isso e passo obrigatorio, nao best-effort.
  UPDATE public.pricing_sync_run sr
  SET status = 'FAILED',
      error_summary = 'ORPHANED_RUN_RECONCILED',
      finished_at = now()
  WHERE sr.pricing_source_id = p_pricing_source_id
    AND sr.status IN ('RECEIVED', 'PROCESSING')
    AND sr.run_type = 'PRICE_REFRESH'
    AND EXISTS (
      SELECT 1 FROM public.pricing_set_refresh_state prs
      WHERE prs.leased_by = sr.id AND prs.lease_until < now()
    );

  -- Passo 1: candidato elegivel, sem lock competitivo (SKIP LOCKED). Elegibilidade =
  -- match_status CONFIRMED no Set + pelo menos 1 identity PRIMARY/ALTERNATE CONFIRMED local.
  SELECT psm.id AS pricing_set_mapping_id, psm.card_set_id, psm.external_set_id,
         prs.id AS refresh_state_id, prs.resume_offset, prs.cycle_seen_external_card_ids
  INTO v_candidate
  FROM public.pricing_set_refresh_state prs
  JOIN public.pricing_set_mapping psm ON psm.id = prs.pricing_set_mapping_id
  WHERE prs.is_paused = false
    AND prs.next_due_at <= now()
    AND (prs.lease_until IS NULL OR prs.lease_until < now())
    AND psm.pricing_source_id = p_pricing_source_id
    AND psm.match_status = 'CONFIRMED'
    AND EXISTS (
      SELECT 1
      FROM public.pricing_source_card_identity psci
      JOIN public.pricing_card_mapping pcm ON pcm.id = psci.pricing_card_mapping_id
      JOIN public.card c ON c.id = pcm.card_id
      WHERE c.card_set_id = psm.card_set_id
        AND psci.pricing_source_id = psm.pricing_source_id
        AND psci.match_status = 'CONFIRMED'
        AND psci.identity_role IN ('PRIMARY', 'ALTERNATE')
    )
  ORDER BY prs.next_due_at ASC, prs.last_started_at ASC NULLS FIRST, prs.id ASC
  FOR UPDATE OF prs SKIP LOCKED
  LIMIT 1;

  IF v_candidate IS NULL THEN
    RETURN QUERY SELECT 'NO_CANDIDATE'::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
                         NULL::integer, NULL::text[];
    RETURN;
  END IF;

  -- Passo 2: abrir o run com pricing_set_mapping_id JA no INSERT (evita UPDATE separado --
  -- ver nota de grants no cabecalho). A exclusao mutua real (3926/3907) acontece aqui: se ja
  -- existir CARD_SYNC ou PRICE_REFRESH ativo da mesma fonte, o INSERT falha com 23505.
  BEGIN
    INSERT INTO public.pricing_sync_run (
      pricing_source_id, run_type, status, requests_made, rate_limit_hits,
      triggered_by, pricing_set_mapping_id
    ) VALUES (
      p_pricing_source_id, 'PRICE_REFRESH', 'PROCESSING', 0, 0, 'SCHEDULED',
      v_candidate.pricing_set_mapping_id
    )
    RETURNING id INTO v_run_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'SOURCE_BUSY'::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
                         NULL::integer, NULL::text[];
    RETURN;
  END;

  -- Passo 3: gravar o lease (tabela com grant de UPDATE completo -- migration 3930).
  UPDATE public.pricing_set_refresh_state
  SET lease_until = now() + make_interval(secs => v_lease_seconds),
      leased_by = v_run_id,
      last_started_at = now()
  WHERE id = v_candidate.refresh_state_id;

  RETURN QUERY SELECT 'CLAIMED'::text, v_run_id, v_candidate.pricing_set_mapping_id,
                      v_candidate.card_set_id, v_candidate.external_set_id,
                      v_candidate.resume_offset, v_candidate.cycle_seen_external_card_ids;
END;
$$;

CREATE FUNCTION public.checkpoint_pricing_set_refresh_page(
  p_sync_run_id uuid,
  p_new_resume_offset integer,
  p_newly_seen_external_card_ids text[]
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated integer;
BEGIN
  -- Só toca pricing_set_refresh_state (grant de UPDATE completo, migration 3930) -- nunca
  -- pricing_sync_run. Lease precisa continuar válida (defesa contra checkpoint tardio de um
  -- run já reconciliado como órfão por outra invocação).
  UPDATE public.pricing_set_refresh_state
  SET resume_offset = p_new_resume_offset,
      cycle_seen_external_card_ids = (
        SELECT array_agg(DISTINCT x) FROM unnest(
          cycle_seen_external_card_ids || coalesce(p_newly_seen_external_card_ids, '{}')
        ) AS x
      )
  WHERE leased_by = p_sync_run_id
    AND lease_until > now();

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

CREATE FUNCTION public.close_pricing_set_refresh_attempt(
  p_sync_run_id uuid,
  p_page_outcome text, -- 'NO_MORE_PAGES' | 'BUDGET_STOPPED' | 'DEADLINE_STOPPED' | 'TRANSIENT_ERROR' | 'SET_TERMINAL_ERROR' | 'AUTH_FAILURE'
  p_run_status text,   -- 'COMPLETED' | 'COMPLETED_WITH_ERRORS' | 'FAILED'
  p_requests_made integer,
  p_rate_limit_hits integer DEFAULT 0,
  p_error_summary text DEFAULT NULL
)
RETURNS TABLE (final_outcome text, seen_count integer, expected_count integer)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_state record;
  v_expected_count integer;
  v_seen_count integer;
  v_final_outcome text;
BEGIN
  IF p_page_outcome NOT IN ('NO_MORE_PAGES', 'BUDGET_STOPPED', 'DEADLINE_STOPPED',
                             'TRANSIENT_ERROR', 'SET_TERMINAL_ERROR', 'AUTH_FAILURE') THEN
    RAISE EXCEPTION 'p_page_outcome invalido: %', p_page_outcome;
  END IF;

  -- Passo 1: finalizar o run -- só as 6 colunas com grant column-level (nunca updated_at).
  -- Mesma transação do passo 2 abaixo: elimina por construção o cenário "crash entre fechar
  -- run e atualizar refresh_state".
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
    -- Global (credencial), nunca especifico do Set -- nao penaliza attempt_count nem pausa.
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
    -- Nao sao falhas: progresso ja preservado via checkpoint por pagina, proxima tentativa
    -- imediata, sem incrementar attempt_count.
    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        next_due_at = now(),
        last_outcome = p_page_outcome,
        last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
    RETURN QUERY SELECT p_page_outcome, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  -- p_page_outcome = 'NO_MORE_PAGES': gate de reconciliacao (MUST HAVE desta rodada) -- SUCCESS
  -- somente com cobertura 100% das identities PRIMARY/ALTERNATE CONFIRMED locais, recalculada
  -- agora na mesma transacao (nunca confia em contagem informada pela API externa).
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
    UPDATE public.pricing_set_refresh_state
    SET lease_until = NULL, leased_by = NULL,
        resume_offset = 0,
        cycle_seen_external_card_ids = '{}',
        cycle_expected_card_count = NULL,
        attempt_count = 0,
        next_due_at = now() + interval '24 hours',
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
$$;

GRANT EXECUTE ON FUNCTION public.open_pricing_set_refresh_attempt(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.checkpoint_pricing_set_refresh_page(uuid, integer, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.close_pricing_set_refresh_attempt(uuid, text, text, integer, integer, text) TO service_role;

COMMENT ON FUNCTION public.open_pricing_set_refresh_attempt(uuid) IS
  'P15 -- claim atômico de um Set elegível (SKIP LOCKED) + abertura do pricing_sync_run (exclusão mútua real via 3926/3907) + reconciliação de run órfão como passo 0. SECURITY INVOKER: único chamador é service_role.';
COMMENT ON FUNCTION public.checkpoint_pricing_set_refresh_page(uuid, integer, text[]) IS
  'P15 -- checkpoint incremental por página (resume_offset + cobertura acumulada de external_card_id), sem tocar pricing_sync_run.';
COMMENT ON FUNCTION public.close_pricing_set_refresh_attempt(uuid, text, text, integer, integer, text) IS
  'P15 -- finalização atômica: fecha o run e atualiza pricing_set_refresh_state na mesma transação. Gate de reconciliação por cobertura local antes de qualquer SUCCESS; nunca confia em contagem da API externa.';
