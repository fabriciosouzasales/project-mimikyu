/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3979 - Reabrir bootstrap de Sets que ganharam cartas + limpeza
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 1 (destravar)
Mandato.....: Fabrício, 2026-10-10: "Vamos para a Fase 1 do plano"

Problema
  O bootstrap de Set (casamento carta a carta com a fonte) roda uma vez. SM12 e
  SWSH10.5 foram mapeados em 10/09 antes de terem cartas no catálogo (cartas
  criadas horas depois): bootstrap COMPLETE com 0 cartas, refresh NEVER_RUN
  para sempre — origem do alerta "fila atrasada".

O que faz
  1. internal.reopen_stale_pricing_set_bootstraps(): reabre (status PENDING,
     offset 0, contadores NULL) o bootstrap COMPLETE de todo Set CONFIRMED que
     tenha carta ativa SEM pricing_card_mapping criada DEPOIS da última
     conclusão do bootstrap. A condição de data impede loop: carta que o
     bootstrap já viu e não casou não reabre de novo. O matching é idempotente
     (mappings existentes viram NOOP). Log em pricing_admin_action_log.
  2. Agendamento diário (pg_cron, 05:15 UTC) — só SQL, sem custo de API; o
     dispatcher de bootstrap existente faz o resto.
  3. Execução imediata: reabre SM12 (271) e SWSH10.5 (88).
  4. MFB: a fonte não devolveu nenhuma das 34 cartas (nome externo nulo em
     todas) → refresh pausado (MANUAL_PAUSE) para sair da fila de atraso;
     reversível pela UI de Sincronizações.
  5. Remove os 30 jobs inativos justtcg-price-refresh-wave-* (modelo por ondas,
     substituído pelo dispatcher por Set).
===============================================================================
*/
BEGIN;

ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_check;
ALTER TABLE public.pricing_admin_action_log ADD CONSTRAINT pricing_admin_action_log_action_check CHECK (action = ANY (ARRAY[
  'PRICING_REFRESH_FREQUENCY_CHANGED','PRICING_SOURCE_UPDATED','PRICING_MAPPING_CONFIRMED','PRICING_MAPPING_REJECTED',
  'PRICING_MAPPING_NOT_FOUND','PRICING_SET_MAPPING_DETAILS_UPDATED','PRICING_SET_MAPPING_CONFIRMED','PRICING_SET_MAPPING_REJECTED',
  'CARD_CONDITION_CREATED','CARD_CONDITION_UPDATED','PRICING_CONDITION_MAPPING_UPDATED','PRICING_MANUAL_PRICE_SET',
  'PRICING_PRODUCT_VARIANT_RECONCILED','PRICING_SET_BOOTSTRAP_REOPENED','PRICING_SET_REFRESH_PAUSED']));
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;
ALTER TABLE public.pricing_admin_action_log ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check CHECK (
     (entity_type = 'PRICING_SOURCE' AND action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED','PRICING_SOURCE_UPDATED','PRICING_PRODUCT_VARIANT_RECONCILED']))
  OR (entity_type = 'PRICING_CARD_MAPPING' AND action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED','PRICING_MAPPING_REJECTED','PRICING_MAPPING_NOT_FOUND']))
  OR (entity_type = 'PRICING_SET_MAPPING' AND action = ANY (ARRAY['PRICING_SET_MAPPING_DETAILS_UPDATED','PRICING_SET_MAPPING_CONFIRMED','PRICING_SET_MAPPING_REJECTED','PRICING_SET_BOOTSTRAP_REOPENED','PRICING_SET_REFRESH_PAUSED']))
  OR (entity_type = 'CARD_CONDITION' AND action = ANY (ARRAY['CARD_CONDITION_CREATED','CARD_CONDITION_UPDATED']))
  OR (entity_type = 'PRICING_CONDITION_MAPPING' AND action = 'PRICING_CONDITION_MAPPING_UPDATED')
  OR (entity_type = 'PRICING_MANUAL_PRICE' AND action = 'PRICING_MANUAL_PRICE_SET'));

CREATE OR REPLACE FUNCTION internal.reopen_stale_pricing_set_bootstraps()
RETURNS TABLE (pricing_set_mapping_id uuid, card_set_code text, new_cards integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $f$
BEGIN
  RETURN QUERY
  WITH stale AS (
    SELECT bs.id AS bs_id, psm.id AS psm_id, cs.code::text AS code,
           (SELECT count(*) FROM public.card c
             WHERE c.card_set_id = psm.card_set_id AND c.is_active
               AND c.created_at > bs.updated_at
               AND NOT EXISTS (SELECT 1 FROM public.pricing_card_mapping m
                                WHERE m.card_id = c.id AND m.pricing_source_id = psm.pricing_source_id))::int AS n
      FROM public.pricing_set_bootstrap_state bs
      JOIN public.pricing_set_mapping psm ON psm.id = bs.pricing_set_mapping_id AND psm.match_status = 'CONFIRMED'
      JOIN public.card_set cs ON cs.id = psm.card_set_id
     WHERE bs.status = 'COMPLETE' AND bs.lease_until IS NULL
     FOR UPDATE OF bs SKIP LOCKED
  ), reopened AS (
    UPDATE public.pricing_set_bootstrap_state bs
       SET status = 'PENDING', acquisition_resume_offset = 0, attempt_count = 0,
           next_attempt_at = now(), cards_confirmed = NULL, cards_pending = NULL, cards_not_found = NULL,
           last_error_summary = NULL
      FROM stale s
     WHERE bs.id = s.bs_id AND s.n > 0
    RETURNING s.psm_id, s.code, s.n
  ), logged AS (
    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    SELECT NULL, 'PRICING_SET_BOOTSTRAP_REOPENED', 'PRICING_SET_MAPPING', r.psm_id,
           jsonb_build_object('card_set_code', r.code, 'new_cards_without_mapping', r.n, 'rule', '3979')
      FROM reopened r
    RETURNING 1
  )
  SELECT r.psm_id, r.code, r.n FROM reopened r;
END;
$f$;
REVOKE ALL ON FUNCTION internal.reopen_stale_pricing_set_bootstraps() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION internal.reopen_stale_pricing_set_bootstraps() IS
  'Reabre o bootstrap de Sets CONFIRMED que ganharam cartas sem mapping depois da última conclusão (3979). Sem custo de API.';

SELECT cron.schedule('pricing-reopen-stale-set-bootstraps', '15 5 * * *',
  $c$select internal.reopen_stale_pricing_set_bootstraps();$c$);

-- Execução imediata (gate: exatamente SM12 e SWSH10.5)
DO $r$
DECLARE v text;
BEGIN
  SELECT string_agg(card_set_code || ':' || new_cards, ',' ORDER BY card_set_code) INTO v
    FROM internal.reopen_stale_pricing_set_bootstraps();
  IF v IS DISTINCT FROM 'SM12:271,SWSH10.5:88' THEN RAISE EXCEPTION 'G1_REOPEN_DIVERGENTE: %', v; END IF;
END $r$;

-- MFB: pausa do refresh (fonte sem nenhuma das 34 cartas)
WITH t AS (
  UPDATE public.pricing_set_refresh_state rs
     SET is_paused = true, pause_reason = 'MANUAL_PAUSE', paused_at = now()
    FROM public.pricing_set_mapping psm JOIN public.card_set cs ON cs.id = psm.card_set_id
   WHERE rs.pricing_set_mapping_id = psm.id AND cs.code = 'MFB' AND NOT rs.is_paused
  RETURNING psm.id
)
INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
SELECT 'fe316458-49dd-44e1-aac0-f4b7604ef8f2'::uuid, 'PRICING_SET_REFRESH_PAUSED', 'PRICING_SET_MAPPING', t.id,
       jsonb_build_object('card_set_code', 'MFB', 'reason', 'fonte JustTCG não devolveu nenhuma das 34 cartas (nome externo nulo); revisar mapeamento do Set', 'operation', '3979')
  FROM t;

-- Limpeza: jobs de ondas inativos
DO $c$
DECLARE j record; v int := 0;
BEGIN
  FOR j IN SELECT jobname FROM cron.job WHERE jobname LIKE 'justtcg-price-refresh-wave-%' AND NOT active LOOP
    PERFORM cron.unschedule(j.jobname);
    v := v + 1;
  END LOOP;
  IF v <> 30 THEN RAISE EXCEPTION 'G2_CRON_WAVES: %', v; END IF;
END $c$;

COMMIT;
