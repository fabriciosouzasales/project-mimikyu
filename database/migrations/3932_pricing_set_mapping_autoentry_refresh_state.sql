-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-22.
-- P15, Scheduler Durável por Set, MUST HAVE item 7 (autoentrada).
-- Trigger: todo pricing_set_mapping que passa (ou volta) a match_status='CONFIRMED' ganha
-- automaticamente uma linha em pricing_set_refresh_state, elegível já no próximo tick do
-- dispatcher -- sem migration nova, sem edição de cron, sem SQL manual.
--
-- REJECTED nunca precisa de ação especial aqui: a query de claim já exige
-- match_status='CONFIRMED' via JOIN (ver RPC open_pricing_set_refresh_attempt, migration
-- 3933) -- o Set fica automaticamente inelegível sem tocar is_paused, e o histórico
-- operacional em refresh_state NUNCA é apagado nessa transição (ON DELETE CASCADE só atua
-- em hard delete real do mapping).

CREATE FUNCTION public.trg_pricing_set_mapping_sync_refresh_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.match_status = 'CONFIRMED' THEN
    INSERT INTO public.pricing_set_refresh_state (pricing_set_mapping_id, next_due_at)
    VALUES (NEW.id, now())
    ON CONFLICT (pricing_set_mapping_id)
    DO UPDATE SET next_due_at = LEAST(public.pricing_set_refresh_state.next_due_at, now());
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pricing_set_mapping_sync_refresh_state
  AFTER INSERT OR UPDATE OF match_status ON public.pricing_set_mapping
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_pricing_set_mapping_sync_refresh_state();

-- Backfill único: os Sets já CONFIRMED hoje entram na fila imediatamente.
INSERT INTO public.pricing_set_refresh_state (pricing_set_mapping_id, next_due_at)
SELECT id, now() FROM public.pricing_set_mapping
WHERE match_status = 'CONFIRMED'
ON CONFLICT (pricing_set_mapping_id) DO NOTHING;

COMMENT ON FUNCTION public.trg_pricing_set_mapping_sync_refresh_state() IS
  'P15 -- autoentrada no scheduler durável por Set: todo pricing_set_mapping CONFIRMED (novo ou reativado) ganha/atualiza sua linha em pricing_set_refresh_state automaticamente.';
