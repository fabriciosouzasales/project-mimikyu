-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-22.
-- Testada em BEGIN/ROLLBACK (junto com 3931/3932/3933) antes da aplicacao real; validacao
-- funcional pos-aplicacao (45 linhas de backfill, 3 RPCs criadas, 30 jobs antigos
-- inalterados, migration 3926 intacta, zero pricing_sync_run ativo) registrada no relatorio
-- desta rodada.
-- P15, Scheduler Durável por Set, MUST HAVE item 1.
-- Cria a entidade de estado operacional do novo scheduler por Set (contrato final aprovado
-- na revisao "P15 -- CONTRATO FINAL DO SCHEDULER POR SET REVISADO", 2026-08-22, com os 2
-- ajustes desta rodada: reconciliacao de cobertura por identidade (colunas
-- cycle_seen_external_card_ids/cycle_expected_card_count) e last_outcome inclui
-- RECONCILIATION_INCOMPLETE).
--
-- pricing_set_mapping continua sendo propriedade exclusiva do pipeline de matching (CLI) --
-- esta tabela e o UNICO lugar que o novo dispatcher escreve. 1:1 via UNIQUE.

CREATE TABLE public.pricing_set_refresh_state (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_set_mapping_id    uuid NOT NULL UNIQUE
                             REFERENCES public.pricing_set_mapping(id) ON DELETE CASCADE,

  is_paused                 boolean NOT NULL DEFAULT false,
  pause_reason              text,
  paused_at                 timestamptz,

  next_due_at               timestamptz NOT NULL DEFAULT now(),
  last_success_at           timestamptz,

  resume_offset             integer NOT NULL DEFAULT 0,
  cycle_seen_external_card_ids text[] NOT NULL DEFAULT '{}',
  cycle_expected_card_count integer,

  lease_until                timestamptz,
  leased_by                  uuid,

  attempt_count              integer NOT NULL DEFAULT 0,
  last_outcome                text NOT NULL DEFAULT 'NEVER_RUN',
  last_error_summary          text,
  last_sync_run_id            uuid,
  last_started_at             timestamptz,

  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_prs_lease_pair CHECK ((lease_until IS NULL) = (leased_by IS NULL)),
  CONSTRAINT ck_prs_pause_pair CHECK (
    (is_paused = false AND pause_reason IS NULL AND paused_at IS NULL)
    OR (is_paused = true AND pause_reason IS NOT NULL AND paused_at IS NOT NULL)
  ),
  CONSTRAINT ck_prs_pause_reason CHECK (
    pause_reason IS NULL OR pause_reason IN ('SET_TERMINAL_ERROR', 'MANUAL_PAUSE')
  ),
  CONSTRAINT ck_prs_last_outcome CHECK (last_outcome IN (
    'NEVER_RUN', 'SUCCESS', 'BUDGET_STOPPED', 'DEADLINE_STOPPED',
    'TRANSIENT_ERROR', 'SET_TERMINAL_ERROR', 'AUTH_FAILURE', 'RECONCILIATION_INCOMPLETE'
  )),
  CONSTRAINT ck_prs_resume_offset_nonneg CHECK (resume_offset >= 0),
  CONSTRAINT ck_prs_attempt_count_nonneg CHECK (attempt_count >= 0)
);

CREATE INDEX ix_prs_claim
  ON public.pricing_set_refresh_state (next_due_at ASC, last_started_at ASC NULLS FIRST, id ASC)
  WHERE is_paused = false;

CREATE INDEX ix_prs_lease_observability
  ON public.pricing_set_refresh_state (lease_until)
  WHERE lease_until IS NOT NULL;

ALTER TABLE public.pricing_set_refresh_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select ON public.pricing_set_refresh_state
  FOR SELECT USING (is_admin());

GRANT SELECT ON public.pricing_set_refresh_state TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pricing_set_refresh_state TO service_role;

COMMENT ON TABLE public.pricing_set_refresh_state IS
  'Estado operacional do scheduler durável por Set (P15). Único escritor: service_role, via RPCs open_pricing_set_refresh_attempt/checkpoint_pricing_set_refresh_page/close_pricing_set_refresh_attempt. Nunca escrito pelo pipeline de matching.';
