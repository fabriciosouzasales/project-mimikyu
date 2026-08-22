// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/set-refresh-supabase-adapter.ts
// Única implementação de SetRefreshPort sobre o SupabaseClient real — dispatcher durável
// por Set (P15).
//
// Desenho deliberado: COMPÕE buildPricingJustTcgRefreshSupabaseAdapter() (o adapter já
// validado do desenho wave-based anterior) em vez de duplicar a lógica de leitura
// paginada/lote — listConfirmedIdentitiesForSet, getConditionMap, findLatestObservations,
// resolveProductsBatch e insertObservations são EXATAMENTE os mesmos métodos, zero
// reescrita, zero risco de divergência entre os dois dispatchers (uma correção futura em
// qualquer um desses 5 métodos beneficia os dois automaticamente). Este arquivo adiciona
// só o que é genuinamente novo: as 3 chamadas RPC do ciclo de vida por Set (migration
// 3933) — insertPriceRefreshRun/insertSyncRunCalls/updateSyncRun do adapter antigo NUNCA
// são referenciados aqui (superfície de escrita em pricing_sync_run/
// pricing_set_refresh_state pertence inteiramente às 3 RPCs).
//
// Falhas de RPC (erro de rede/servidor, nunca um resultado de negócio esperado) SEMPRE
// lançam — nunca retornam um valor "de negócio" ambíguo. Isso distingue, em nível de
// tipo, uma falha de infraestrutura (propaga para o catch-all do handler, vira 500) de um
// resultado esperado da RPC (NO_CANDIDATE/SOURCE_BUSY/lease inválida/RECONCILIATION_
// INCOMPLETE, todos modelados como valores de retorno normais em set-refresh-port.ts).

import type { SupabaseClient } from "@supabase/supabase-js";
import { buildPricingJustTcgRefreshSupabaseAdapter } from "./supabase-adapter.ts";
import type { SanitizedLogger } from "./supabase-adapter.ts";
import type {
  CheckpointResult,
  CloseAttemptResult,
  OpenAttemptResult,
  PageOutcome,
  RunStatus,
  SetRefreshPort,
} from "./set-refresh-port.ts";

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

export function buildSetRefreshSupabaseAdapter(
  supabase: SupabaseClient,
  logError: SanitizedLogger = defaultSanitizedLogger,
): SetRefreshPort {
  // Reaproveita o adapter existente só pelos 5 métodos de leitura/escrita econômica —
  // os 6 métodos de ciclo de vida antigo (insertPriceRefreshRun/insertSyncRunCalls/
  // updateSyncRun, mais os de listagem de candidatos de onda que este dispatcher nunca
  // usa) ficam inacessíveis a partir daqui (SetRefreshPort não os declara).
  const legacyPort = buildPricingJustTcgRefreshSupabaseAdapter(supabase, logError);

  return {
    listConfirmedIdentitiesForSet: legacyPort.listConfirmedIdentitiesForSet,
    getConditionMap: legacyPort.getConditionMap,
    findLatestObservations: legacyPort.findLatestObservations,
    resolveProductsBatch: legacyPort.resolveProductsBatch,
    insertObservations: legacyPort.insertObservations,
    // Telemetria — mesmo método do adapter antigo, mesma tabela pricing_sync_run_call,
    // zero lógica nova (correção desta rodada, 2026-08-22).
    insertSyncRunCalls: legacyPort.insertSyncRunCalls,

    async openAttempt(pricingSourceId: string): Promise<OpenAttemptResult> {
      const { data, error } = await supabase.rpc(
        "open_pricing_set_refresh_attempt",
        { p_pricing_source_id: pricingSourceId },
      );
      if (error) {
        logError("SET_REFRESH_OPEN_ATTEMPT_RPC_FAILED", { pricingSourceId });
        throw new Error("SET_REFRESH_OPEN_ATTEMPT_RPC_FAILED");
      }
      const row = ((data ?? []) as Array<{
        outcome: string;
        sync_run_id: string | null;
        pricing_set_mapping_id: string | null;
        card_set_id: string | null;
        external_set_id: string | null;
        resume_offset: number | null;
        cycle_seen_external_card_ids: string[] | null;
      }>)[0];

      if (!row || row.outcome === "NO_CANDIDATE") {
        return { outcome: "NO_CANDIDATE" };
      }
      if (row.outcome === "SOURCE_BUSY") {
        return { outcome: "SOURCE_BUSY" };
      }
      // CLAIMED — os 5 campos abaixo são NOT NULL pela própria RPC neste ramo (ver
      // migration 3933); non-null assertion documenta essa garantia, nunca um valor
      // adivinhado.
      return {
        outcome: "CLAIMED",
        syncRunId: row.sync_run_id!,
        pricingSetMappingId: row.pricing_set_mapping_id!,
        cardSetId: row.card_set_id!,
        externalSetId: row.external_set_id!,
        resumeOffset: row.resume_offset ?? 0,
        cycleSeenExternalCardIds: row.cycle_seen_external_card_ids ?? [],
      };
    },

    async checkpointPage(
      syncRunId: string,
      newResumeOffset: number,
      newlySeenExternalCardIds: readonly string[],
    ): Promise<CheckpointResult> {
      const { data, error } = await supabase.rpc(
        "checkpoint_pricing_set_refresh_page",
        {
          p_sync_run_id: syncRunId,
          p_new_resume_offset: newResumeOffset,
          p_newly_seen_external_card_ids: [...newlySeenExternalCardIds],
        },
      );
      if (error) {
        logError("SET_REFRESH_CHECKPOINT_RPC_FAILED", { syncRunId });
        throw new Error("SET_REFRESH_CHECKPOINT_RPC_FAILED");
      }
      return Boolean(data);
    },

    async closeAttempt(
      syncRunId: string,
      pageOutcome: PageOutcome,
      runStatus: RunStatus,
      requestsMade: number,
      rateLimitHits: number,
      errorSummary: string | null,
    ): Promise<CloseAttemptResult> {
      const { data, error } = await supabase.rpc(
        "close_pricing_set_refresh_attempt",
        {
          p_sync_run_id: syncRunId,
          p_page_outcome: pageOutcome,
          p_run_status: runStatus,
          p_requests_made: requestsMade,
          p_rate_limit_hits: rateLimitHits,
          p_error_summary: errorSummary,
        },
      );
      if (error) {
        // O run fica PROCESSING com a lease ainda ativa (180s) — o próprio
        // open_pricing_set_refresh_attempt reconcilia como órfão (ORPHANED_RUN_RECONCILED)
        // assim que a lease expirar e uma próxima invocação para esta fonte rodar. Nenhuma
        // ação de compensação é tentada aqui — só propaga (catch-all do handler -> 500).
        logError("SET_REFRESH_CLOSE_ATTEMPT_RPC_FAILED", {
          syncRunId,
          pageOutcome,
          runStatus,
        });
        throw new Error("SET_REFRESH_CLOSE_ATTEMPT_RPC_FAILED");
      }
      const row = ((data ?? []) as Array<{
        final_outcome: string;
        seen_count: number | null;
        expected_count: number | null;
      }>)[0];
      return {
        finalOutcome: row?.final_outcome ?? "UNKNOWN",
        seenCount: row?.seen_count ?? null,
        expectedCount: row?.expected_count ?? null,
      };
    },
  };
}
