// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-bootstrap/bootstrap-supabase-adapter.ts
// Única implementação de BootstrapPort sobre o SupabaseClient real — executor de bootstrap de
// Set (P16.5.2/P16.5.3, 2026-08-26). Chama exclusivamente as 3 RPCs de P16.5.1 (migration
// 3955, PROPOSTA) para o ciclo de vida de pricing_sync_run/pricing_set_bootstrap_state, mais a
// RPC persist_pricing_bootstrap_card_batch (migration 3958, PROPOSTA nesta rodada) para a
// persistência em lote — nenhuma das migrations foi aplicada em produção; este adapter existe e
// é testável, mas não deve ser wireado a nenhum cron/Edge Function real nesta rodada.
//
// Falhas de RPC (erro de rede/servidor, nunca um resultado de negócio esperado) SEMPRE lançam
// — mesma disciplina de set-refresh-supabase-adapter.ts — nunca retornam um valor "de
// negócio" ambíguo.
//
// Autoria (revisada nesta rodada — substitui o UUID sentinela usado na versão anterior, que
// Fabrício rejeitou explicitamente por criar um ator fictício em admin_user): a promoção
// 100% automatizada do CARD_SYNC nunca escreve confirmed_by. Ela sempre envia
// p_confirmed_by=NULL e p_confirmed_sync_run_id=<o próprio syncRunId desta invocação> — um UUID
// real de pricing_sync_run, entidade que já existe e já é auditada (started_at/finished_at/
// status/triggered_by), nunca um valor inventado. A migration 3957 garante, via CHECK, que
// confirmed_by e confirmed_sync_run_id são mutuamente exclusivos sempre que match_status=
// CONFIRMED — este adapter só precisa respeitar essa regra, nunca reimplementá-la.

// deno-lint-ignore no-explicit-any
type SupabaseClientLike = any;

import type {
  BootstrapPhaseOutcome,
  BootstrapPort,
  BootstrapRunStatus,
  CheckpointAcquisitionResult,
  CloseBootstrapAttemptResult,
  LocalActiveCard,
  OpenBootstrapAttemptResult,
  PersistBootstrapBatchResult,
  PersistBootstrapRowInput,
  StagedCardInput,
  StagedCardRow,
} from "./bootstrap-port.ts";

export type SanitizedLogger = (
  code: string,
  context?: Readonly<Record<string, unknown>>,
) => void;

function defaultSanitizedLogger(
  code: string,
  context?: Readonly<Record<string, unknown>>,
): void {
  if (context && Object.keys(context).length > 0) {
    console.error(code, context);
  } else {
    console.error(code);
  }
}

export function buildBootstrapSupabaseAdapter(
  supabase: SupabaseClientLike,
  logError: SanitizedLogger = defaultSanitizedLogger,
): BootstrapPort {
  return {
    async openAttempt(
      pricingSourceId: string,
    ): Promise<OpenBootstrapAttemptResult> {
      const { data, error } = await supabase.rpc(
        "open_pricing_set_bootstrap_attempt",
        {
          p_pricing_source_id: pricingSourceId,
        },
      );
      if (error) {
        logError("PRICING_SET_BOOTSTRAP_OPEN_ATTEMPT_RPC_FAILED", {
          pricingSourceId,
        });
        throw new Error("PRICING_SET_BOOTSTRAP_OPEN_ATTEMPT_RPC_FAILED");
      }
      const row = ((data ?? []) as Array<{
        outcome: string;
        sync_run_id: string | null;
        pricing_set_mapping_id: string | null;
        card_set_id: string | null;
        external_set_id: string | null;
        status: string | null;
        acquisition_resume_offset: number | null;
      }>)[0];

      if (!row || row.outcome === "NO_CANDIDATE") {
        return { outcome: "NO_CANDIDATE" };
      }
      if (row.outcome === "SOURCE_BUSY") {
        return { outcome: "SOURCE_BUSY" };
      }
      // CLAIMED — os campos abaixo são NOT NULL pela própria RPC neste ramo (ver migration
      // 3955); non-null assertion documenta essa garantia, nunca um valor adivinhado.
      return {
        outcome: "CLAIMED",
        syncRunId: row.sync_run_id!,
        pricingSetMappingId: row.pricing_set_mapping_id!,
        cardSetId: row.card_set_id!,
        externalSetId: row.external_set_id!,
        status: row.status as "PENDING" | "ACQUIRING" | "MATCHING",
        acquisitionResumeOffset: row.acquisition_resume_offset ?? 0,
      };
    },

    async checkpointAcquisitionPage(
      syncRunId: string,
      newResumeOffset: number,
      stagedCards: readonly StagedCardInput[],
    ): Promise<CheckpointAcquisitionResult> {
      const { data, error } = await supabase.rpc(
        "checkpoint_pricing_set_bootstrap_acquisition_page",
        {
          p_sync_run_id: syncRunId,
          p_new_resume_offset: newResumeOffset,
          p_staged_cards: stagedCards.map((c) => ({
            external_card_id: c.externalCardId,
            number: c.number,
            name: c.name,
          })),
        },
      );
      if (error) {
        logError("PRICING_SET_BOOTSTRAP_CHECKPOINT_RPC_FAILED", { syncRunId });
        throw new Error("PRICING_SET_BOOTSTRAP_CHECKPOINT_RPC_FAILED");
      }
      return Boolean(data);
    },

    async closeAttempt(
      syncRunId: string,
      phaseOutcome: BootstrapPhaseOutcome,
      runStatus: BootstrapRunStatus,
      requestsMade: number,
      rateLimitHits: number,
      errorSummary: string | null,
    ): Promise<CloseBootstrapAttemptResult> {
      const { data, error } = await supabase.rpc(
        "close_pricing_set_bootstrap_attempt",
        {
          p_sync_run_id: syncRunId,
          p_phase_outcome: phaseOutcome,
          p_run_status: runStatus,
          p_requests_made: requestsMade,
          p_rate_limit_hits: rateLimitHits,
          p_error_summary: errorSummary,
        },
      );
      if (error) {
        // O run fica PROCESSING com a lease ainda ativa (180s) — a própria
        // open_pricing_set_bootstrap_attempt reconcilia como órfão na próxima invocação para
        // esta fonte. Nenhuma ação de compensação é tentada aqui — só propaga.
        logError("PRICING_SET_BOOTSTRAP_CLOSE_ATTEMPT_RPC_FAILED", {
          syncRunId,
          phaseOutcome,
          runStatus,
        });
        throw new Error("PRICING_SET_BOOTSTRAP_CLOSE_ATTEMPT_RPC_FAILED");
      }
      const row = ((data ?? []) as Array<{ final_status: string }>)[0];
      return { finalStatus: row?.final_status ?? "UNKNOWN" };
    },

    async loadFullStaging(
      pricingSetMappingId: string,
    ): Promise<StagedCardRow[]> {
      const { data, error } = await supabase
        .from("pricing_set_bootstrap_card_staging")
        .select("external_card_id, external_number, external_name")
        .eq("pricing_set_mapping_id", pricingSetMappingId);
      if (error) {
        logError("PRICING_SET_BOOTSTRAP_LOAD_STAGING_FAILED", {
          pricingSetMappingId,
        });
        throw new Error("PRICING_SET_BOOTSTRAP_LOAD_STAGING_FAILED");
      }
      return ((data ?? []) as Array<{
        external_card_id: string;
        external_number: string | null;
        external_name: string;
      }>).map((row) => ({
        externalCardId: row.external_card_id,
        externalNumber: row.external_number,
        externalName: row.external_name,
      }));
    },

    async loadLocalActiveCards(cardSetId: string): Promise<LocalActiveCard[]> {
      const { data, error } = await supabase
        .from("card")
        .select("id, name, collector_number, collector_total")
        .eq("card_set_id", cardSetId)
        .eq("is_active", true);
      if (error) {
        logError("PRICING_SET_BOOTSTRAP_LOAD_LOCAL_CARDS_FAILED", {
          cardSetId,
        });
        throw new Error("PRICING_SET_BOOTSTRAP_LOAD_LOCAL_CARDS_FAILED");
      }
      return ((data ?? []) as Array<{
        id: string;
        name: string;
        collector_number: string;
        collector_total: number | null;
      }>).map((row) => ({
        cardId: row.id,
        name: row.name,
        collectorNumber: row.collector_number,
        collectorTotal: row.collector_total,
      }));
    },

    async persistMatchingBatch(
      pricingSourceId: string,
      syncRunId: string,
      rows: readonly PersistBootstrapRowInput[],
    ): Promise<PersistBootstrapBatchResult> {
      const { data, error } = await supabase.rpc(
        "persist_pricing_bootstrap_card_batch",
        {
          p_pricing_source_id: pricingSourceId,
          p_confirmed_by: null,
          p_confirmed_sync_run_id: syncRunId,
          p_rows: rows.map((r) => ({
            card_id: r.cardId,
            classification: r.classification,
            external_card_id: r.externalCardId,
            external_card_name: r.externalCardName,
            match_method: r.matchMethod,
            match_evidence: r.matchEvidence,
          })),
        },
      );
      if (error) {
        logError("PRICING_SET_BOOTSTRAP_PERSIST_BATCH_RPC_FAILED", {
          pricingSourceId,
          rowCount: rows.length,
        });
        return { ok: false };
      }
      const resultRows = ((data ?? []) as Array<{
        card_id: string;
        action: string;
        final_match_status: string;
        identity_created: boolean;
      }>).map((row) => ({
        cardId: row.card_id,
        action: row.action,
        finalMatchStatus: row.final_match_status,
        identityCreated: Boolean(row.identity_created),
      }));
      return { ok: true, rows: resultRows };
    },
  };
}
