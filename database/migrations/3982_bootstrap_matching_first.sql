/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3982 - Bootstrap: concluir MATCHING antes de iniciar novas aquisições
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 3

Problema
  open_pricing_set_bootstrap_attempt ordenava por next_attempt_at e depois
  last_started_at NULLS FIRST. Com ~140 Sets confirmados no mesmo minuto, todo Set
  ainda não iniciado (PENDING, last_started_at NULL) vencia o desempate contra os já
  adquiridos (MATCHING): o dispatcher (1 Set a cada 5 min) fazia TODAS as aquisições
  antes de qualquer matching — preços só ~20 h depois.

O que faz
  Única mudança: MATCHING tem prioridade no ORDER BY (fecha um Set adquirido, sem
  custo de API, antes de abrir outro). Resto da função idêntico ao LIVE.
===============================================================================
*/
CREATE OR REPLACE FUNCTION public.open_pricing_set_bootstrap_attempt(p_pricing_source_id uuid)
 RETURNS TABLE(outcome text, sync_run_id uuid, pricing_set_mapping_id uuid, card_set_id uuid, external_set_id text, status text, acquisition_resume_offset integer)
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
  ORDER BY (psbs.status = 'MATCHING') DESC, psbs.next_attempt_at ASC, psbs.last_started_at ASC NULLS FIRST, psbs.id ASC
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
