-- STATUS: CONFIRMADO EXECUTADO em 2026-08-26. P16.5.5, aprovado por Fabricio apos a primeira
-- execucao real de justtcg-set-bootstrap contra SWSH8 (aquisicao concluida, 328 cartas em
-- staging, status=MATCHING, zero mappings/identities, zero PRICE_REFRESH disparado).
--
-- Objetivo -- fechar uma janela de corrida entre o bootstrap de Set (P16.5.2/P16.5.3) e o
-- dispatcher de PRICE_REFRESH (open_pricing_set_refresh_attempt, ver migration do dispatcher
-- Set, 3933): a fase de matching do bootstrap pode persistir pricing_card_mapping/
-- pricing_source_card_identity CONFIRMED linha a linha, ANTES de close_pricing_set_bootstrap_attempt
-- (3955) fechar formalmente pricing_set_bootstrap_state.status em COMPLETE. Sem este gate, o
-- dispatcher poderia -- teoricamente, em uma corrida real -- reivindicar um Set ainda em
-- MATCHING assim que a primeira identity CONFIRMED daquele lote fosse gravada, disparando
-- PRICE_REFRESH contra um catalogo de identidades parcial/nao reconciliado.
--
-- Mudanca -- uma unica clausula EXISTS adicional no WHERE de selecao de candidato, exigindo
-- pricing_set_bootstrap_state.status = 'COMPLETE' para o mesmo pricing_set_mapping_id, ao lado
-- (nunca em substituicao) da clausula EXISTS de identity CONFIRMED PRIMARY/ALTERNATE ja
-- existente. Nenhuma outra parte da funcao muda -- mesma assinatura (RETURNS TABLE identico),
-- mesmo corpo (reconciliacao de run orfao, INSERT em pricing_sync_run com tratamento de
-- unique_violation, lease em pricing_set_refresh_state, os 3 ramos de RETURN QUERY). O nucleo de
-- refresh (_shared/pricing-justtcg-refresh/*) e o dispatcher Set (Edge Function
-- justtcg-price-refresh-set) nao sao alterados por esta migration.
--
-- Testado em transacao BEGIN/ROLLBACK contra producao real nesta mesma rodada (zero residuo
-- apos o teste): SWSH8 (MATCHING + 0 identity) nao elegivel; SWSH8 com identity CONFIRMED
-- sintetica ainda em MATCHING -- nao elegivel sob o gate novo (mas SERIA elegivel sob o gate
-- antigo, provando a vulnerabilidade real que esta migration fecha); SWSH8 apos status=COMPLETE
-- sintetico + identity -- elegivel; COMPLETE + zero identity -- nao elegivel; os 45 Sets
-- historicos (todos ja com bootstrap_state.status=COMPLETE) permanecem elegiveis sem nenhuma
-- exclusao nova (gate antigo=45, gate novo=45).
--
-- Impacto em dados existentes: zero -- CREATE OR REPLACE FUNCTION e metadata-only, nenhuma
-- tabela e alterada, nenhum dado e reescrito. SWSH8 continua PAUSADO operacionalmente ate seu
-- bootstrap fechar em COMPLETE (proximo incremento, fora do escopo desta migration -- nenhuma
-- segunda chamada de justtcg-set-bootstrap e feita aqui).

CREATE OR REPLACE FUNCTION public.open_pricing_set_refresh_attempt(p_pricing_source_id uuid)
 RETURNS TABLE(outcome text, sync_run_id uuid, pricing_set_mapping_id uuid, card_set_id uuid, external_set_id text, resume_offset integer, cycle_seen_external_card_ids text[])
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_run_id uuid;
  v_lease_seconds constant integer := 180;
BEGIN
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
    -- P16.5.5: o bootstrap do Set precisa ter FECHADO em COMPLETE -- nunca elegivel
    -- enquanto esta PENDING/ACQUIRING/MATCHING/PAUSED, mesmo que ja existam identities
    -- CONFIRMED criadas no meio do matching (antes do fechamento).
    AND EXISTS (
      SELECT 1
      FROM public.pricing_set_bootstrap_state pbs
      WHERE pbs.pricing_set_mapping_id = psm.id
        AND pbs.status = 'COMPLETE'
    )
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

  UPDATE public.pricing_set_refresh_state
  SET lease_until = now() + make_interval(secs => v_lease_seconds),
      leased_by = v_run_id,
      last_started_at = now()
  WHERE id = v_candidate.refresh_state_id;

  RETURN QUERY SELECT 'CLAIMED'::text, v_run_id, v_candidate.pricing_set_mapping_id,
                      v_candidate.card_set_id, v_candidate.external_set_id,
                      v_candidate.resume_offset, v_candidate.cycle_seen_external_card_ids;
END;
$function$;
