-- STATUS: PROPOSTA -- ainda NAO aplicada em producao. Parte da correcao de proveniencia da
-- confirmacao automatica (P16.5.2/P16.5.3), decidida por Fabricio em 2026-08-26 apos revisao de
-- duas propostas anteriores (embutir marcador em match_evidence -- rejeitada explicitamente por
-- nao ser fonte estrutural de autoria; UUID sentinela em confirmed_by -- rejeitada por criar um
-- ator ficticio em admin_user). Renumerada nesta rodada: esta migration (autoria relacional)
-- passa a ser 3957, ocupando o numero antes usado pela RPC de persistencia em lote, que passa a
-- ser 3958 -- nenhuma excecao de ordem de aplicacao e mantida (STD-001: migrations sao sempre
-- aplicadas em ordem numerica ascendente; 3958 depende desta).
--
-- Objetivo -- introduzir uma segunda coluna de autoria, `confirmed_sync_run_id`, irma de
-- `confirmed_by`, para que uma linha CONFIRMED possa ser atribuida a exatamente UM responsavel:
-- um admin_user real (confirmed_by, papel humano inalterado) OU um pricing_sync_run real
-- (confirmed_sync_run_id, papel automatizado -- CARD_SYNC do executor de bootstrap). Nenhum
-- ator ficticio e criado em nenhuma tabela; a autoria automatizada aponta para uma entidade que
-- ja existe e ja e auditada (pricing_sync_run, com seus proprios started_at/finished_at/status/
-- triggered_by).
--
-- Por que ON DELETE RESTRICT e nao SET NULL (diferente das outras 3 referencias existentes a
-- pricing_sync_run.id -- pricing_observation.sync_run_id, pricing_sync_run_call.sync_run_id,
-- pricing_set_bootstrap_state.leased_by/last_sync_run_id, todas SET NULL/CASCADE por serem
-- vinculos operacionais ou telemetria descartavel): aqui a coluna e autoridade de confirmacao,
-- papel irmao de confirmed_by, nao um ponteiro de conveniencia. Permitir SET NULL deixaria uma
-- linha CONFIRMED sem nenhuma autoria apos seu pricing_sync_run ser apagado, violando
-- silenciosamente o CHECK "exatamente um" reescrito abaixo. Nenhuma DELETE FROM
-- pricing_sync_run existe hoje em nenhum lugar do repositorio (grep confirmado nesta rodada) --
-- RESTRICT nao tem custo operacional conhecido, so o beneficio de tornar essa violacao
-- impossivel.
--
-- Impacto em dados existentes: zero. ADD COLUMN ... NULL sem DEFAULT e metadata-only (sem
-- reescrita de tabela). Toda linha CONFIRMED/REJECTED ja existente tem confirmed_by NOT NULL e
-- (por esta coluna nao existir antes) confirmed_sync_run_id nasce NULL -- portanto
-- num_nonnulls(confirmed_by, confirmed_sync_run_id) = 1 e satisfeito por 100% das linhas atuais
-- sem nenhum backfill (validado nesta rodada via teste transacional BEGIN/ROLLBACK contra a
-- producao real). Nenhuma policy RLS referencia estas colunas (unica policy das duas tabelas e
-- SELECT admin-only). GRANT SELECT de authenticated e GRANT SELECT/INSERT de service_role sao
-- concedidos a nivel de tabela (migrations 3040/3923 e a fase P8) e cobrem a coluna nova
-- automaticamente; o UPDATE column-scoped de service_role (migration 3912) nao inclui
-- confirmed_sync_run_id e nao precisa incluir nesta rodada -- a unica escrita automatica desta
-- coluna acontece via persist_pricing_bootstrap_card_batch (3958), SECURITY DEFINER, que roda
-- com os privilegios do dono da funcao e ignora grants de coluna do chamador.
--
-- REJECTED permanece exclusivamente humano nas duas tabelas nesta fase -- confirmed_sync_run_id
-- e forcado a NULL nesse ramo do CHECK, entao nenhuma rejeicao automatica passa, mesmo que um
-- codigo futuro tente.

-- 0) Guarda de concorrencia -- mesmo padrao ja usado em 3923/3924: LOCK real + bloqueia se
--    houver sync run ativo.
LOCK TABLE public.pricing_sync_run IN EXCLUSIVE MODE NOWAIT;

DO $$
DECLARE
  v_active_count int;
BEGIN
  SELECT count(*) INTO v_active_count FROM public.pricing_sync_run WHERE status IN ('RECEIVED','PROCESSING');
  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'PRICING_MIGRATION_BLOCKED_ACTIVE_SYNC_RUN: % run(s) em RECEIVED/PROCESSING', v_active_count;
  END IF;
END $$;

-- 1) pricing_card_mapping ----------------------------------------------------
ALTER TABLE public.pricing_card_mapping
  ADD COLUMN confirmed_sync_run_id uuid NULL
    REFERENCES public.pricing_sync_run (id) ON DELETE RESTRICT;

CREATE INDEX ix_pricing_card_mapping_confirmed_sync_run_id
  ON public.pricing_card_mapping (confirmed_sync_run_id);

ALTER TABLE public.pricing_card_mapping
  DROP CONSTRAINT ck_pricing_card_mapping_confirmation_consistency;

ALTER TABLE public.pricing_card_mapping
  ADD CONSTRAINT ck_pricing_card_mapping_confirmation_consistency
  CHECK (
    (match_status IN ('PENDING', 'NOT_FOUND')
      AND confirmed_at IS NULL AND confirmed_by IS NULL AND confirmed_sync_run_id IS NULL)
    OR (match_status = 'CONFIRMED'
      AND confirmed_at IS NOT NULL
      AND num_nonnulls(confirmed_by, confirmed_sync_run_id) = 1)
    OR (match_status = 'REJECTED'
      AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL AND confirmed_sync_run_id IS NULL)
  );

COMMENT ON COLUMN public.pricing_card_mapping.confirmed_sync_run_id IS
  'Autoria automatizada de uma confirmacao CONFIRMED -- UUID real de pricing_sync_run (CARD_SYNC), nunca um ator ficticio. Mutuamente exclusivo com confirmed_by (ver CHECK ck_pricing_card_mapping_confirmation_consistency); sempre NULL em PENDING/NOT_FOUND/REJECTED.';

-- 2) pricing_source_card_identity --------------------------------------------
ALTER TABLE public.pricing_source_card_identity
  ADD COLUMN confirmed_sync_run_id uuid NULL
    REFERENCES public.pricing_sync_run (id) ON DELETE RESTRICT;

CREATE INDEX ix_pricing_source_card_identity_confirmed_sync_run_id
  ON public.pricing_source_card_identity (confirmed_sync_run_id);

ALTER TABLE public.pricing_source_card_identity
  DROP CONSTRAINT ck_pricing_source_card_identity_status_fields;

ALTER TABLE public.pricing_source_card_identity
  ADD CONSTRAINT ck_pricing_source_card_identity_status_fields
  CHECK (
    (match_status = 'PENDING'
      AND confirmed_at IS NULL AND confirmed_by IS NULL AND confirmed_sync_run_id IS NULL
      AND rejected_at IS NULL AND rejected_by IS NULL)
    OR (match_status = 'CONFIRMED'
      AND confirmed_at IS NOT NULL
      AND num_nonnulls(confirmed_by, confirmed_sync_run_id) = 1
      AND rejected_at IS NULL AND rejected_by IS NULL)
    OR (match_status = 'REJECTED'
      AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL AND confirmed_sync_run_id IS NULL
      AND rejected_at IS NOT NULL AND rejected_by IS NOT NULL
      AND rejected_at >= confirmed_at)
  );

COMMENT ON COLUMN public.pricing_source_card_identity.confirmed_sync_run_id IS
  'Autoria automatizada de uma confirmacao CONFIRMED -- UUID real de pricing_sync_run (CARD_SYNC), nunca um ator ficticio. Mutuamente exclusivo com confirmed_by (ver CHECK ck_pricing_source_card_identity_status_fields); sempre NULL em PENDING/REJECTED (REJECTED permanece exclusivamente humano nesta fase).';
