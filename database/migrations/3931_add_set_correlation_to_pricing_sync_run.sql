-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-22.
-- P15, Scheduler Durável por Set, MUST HAVE item 4.
-- Correlaciona pricing_sync_run com o Set individual que ele processou (granularidade nova:
-- 1 run por Set por invocação, nao mais 1 run por wave). Coluna nullable -- runs antigos
-- (wave-based, PTAX, CARD_SYNC, FX_REFRESH) continuam validos sem essa correlacao.
--
-- Tambem fecha as FKs de pricing_set_refresh_state.leased_by/last_sync_run_id ->
-- pricing_sync_run(id), deferidas da migration 3930 porque a ordem logica e "a entidade de
-- estado existe primeiro, a correlacao com o run vem depois".

ALTER TABLE public.pricing_sync_run
  ADD COLUMN pricing_set_mapping_id uuid REFERENCES public.pricing_set_mapping(id) ON DELETE SET NULL;

CREATE INDEX ix_pricing_sync_run_set_mapping
  ON public.pricing_sync_run (pricing_set_mapping_id)
  WHERE pricing_set_mapping_id IS NOT NULL;

ALTER TABLE public.pricing_set_refresh_state
  ADD CONSTRAINT fk_prs_leased_by FOREIGN KEY (leased_by)
    REFERENCES public.pricing_sync_run(id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_prs_last_sync_run_id FOREIGN KEY (last_sync_run_id)
    REFERENCES public.pricing_sync_run(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.pricing_sync_run.pricing_set_mapping_id IS
  'P15 -- Set individual tratado por este run (granularidade 1 run por Set por invocação). NULL para runs de outros run_types/desenhos anteriores (wave-based, PTAX, CARD_SYNC, FX_REFRESH).';
