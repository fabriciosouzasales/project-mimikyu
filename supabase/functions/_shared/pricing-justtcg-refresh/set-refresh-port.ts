// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/set-refresh-port.ts
// Porta funcional do dispatcher durável por Set (P15) — implementa o ciclo de vida de
// pricing_sync_run/pricing_set_refresh_state EXCLUSIVAMENTE via as 3 RPCs da migration
// 3933 (open_/checkpoint_/close_pricing_set_refresh_attempt), aprovadas e aplicadas em
// produção na rodada anterior.
//
// Reaproveita de port.ts (sem alteração) só o que continua válido no novo desenho:
// leitura de identidades confirmadas/mapa de condições/últimas observações, e escrita em
// pricing_product (RPC resolve_pricing_products_batch — correção R1/R5, migration 3928,
// NEW/REUSE pela chave econômica real) e pricing_observation (INSERT-only). NUNCA
// reaproveita insertPriceRefreshRun/insertSyncRunCalls/updateSyncRun de port.ts — o ciclo
// de vida de pricing_sync_run agora pertence inteiramente às 3 RPCs novas, que já
// encapsulam lease/resume_offset/cycle_seen_external_card_ids em pricing_set_refresh_state
// (este núcleo nunca lê/escreve essa tabela diretamente — só através das RPCs).
//
// Telemetria pricing_sync_run_call (correção desta rodada, 2026-08-22, a pedido de
// Fabrício): REAPROVEITA insertSyncRunCalls tal como já existe em port.ts/
// supabase-adapter.ts — mesma tabela, mesmo contrato, zero coluna nova, zero lógica
// duplicada. sequence_number/outcome/http_status_code continuam vindo de
// JustTcgClient.callLog (client.ts) sem transformação — CallLogEntry (types.ts) e
// PriceRefreshCallLogEntry (port.ts) têm exatamente a mesma forma estrutural.
//
// Regra 11 preservada estruturalmente (mesma garantia de port.ts): nenhuma operação desta
// porta escreve em pricing_set_mapping, pricing_card_mapping ou
// pricing_source_card_identity — a porta simplesmente não expõe nenhuma operação de
// escrita nessas três tabelas.

import type {
  InsertObservationInput,
  InsertObservationsResult,
  LatestObservationKey,
  LatestObservationRow,
  PriceRefreshCallLogEntry,
  RefreshIdentityRow,
  ResolvedProductRow,
  ResolveProductsBatchInput,
  ResolveProductsBatchResult,
} from "./port.ts";

export type {
  InsertObservationInput,
  InsertObservationsResult,
  LatestObservationKey,
  LatestObservationRow,
  PriceRefreshCallLogEntry,
  RefreshIdentityRow,
  ResolvedProductRow,
  ResolveProductsBatchInput,
  ResolveProductsBatchResult,
};

// ============================================================================
// open_pricing_set_refresh_attempt (migration 3933) — reivindica até 1 Set elegível da
// fonte informada, abrindo um pricing_sync_run PROCESSING e arrendando (lease) o Set por
// 180s. NO_CANDIDATE = nenhum Set elegível agora (equivalente a "NO_WORK" no vocabulário
// do pedido); SOURCE_BUSY = já existe outro PRICE_REFRESH/CARD_SYNC ativo para esta fonte
// (unique_violation em pricing_sync_run — migrations 3907/3926).
// ============================================================================

export type OpenAttemptResult =
  | { outcome: "NO_CANDIDATE" }
  | { outcome: "SOURCE_BUSY" }
  | {
    outcome: "CLAIMED";
    syncRunId: string;
    pricingSetMappingId: string;
    cardSetId: string;
    externalSetId: string;
    // Offset/cobertura já acumulados de tentativas anteriores deste MESMO ciclo (Set
    // nunca reiniciado do zero após um BUDGET_STOPPED/DEADLINE_STOPPED — retomada real).
    resumeOffset: number;
    cycleSeenExternalCardIds: string[];
  };

// ============================================================================
// checkpoint_pricing_set_refresh_page — persiste o progresso de UMA página já processada
// (resume_offset + external_card_id vistos) em pricing_set_refresh_state. true = lease
// ainda válida (checkpoint aplicado); false = lease perdida/expirada (outro processo já
// reconciliou este run como órfão) — o chamador deve parar de processar páginas novas
// IMEDIATAMENTE e nunca chamar close_ depois disso (o run já não é mais seu).
// ============================================================================

export type CheckpointResult = boolean;

// ============================================================================
// close_pricing_set_refresh_attempt — finaliza o pricing_sync_run E decide o próximo
// estado de pricing_set_refresh_state (lease liberada, next_due_at, attempt_count,
// pausa) a partir de p_page_outcome. p_run_status é responsabilidade exclusiva do
// chamador (não validado pela função) — ver decideRunStatus() em set-refresh-core.ts.
// ============================================================================

export type PageOutcome =
  | "NO_MORE_PAGES"
  | "BUDGET_STOPPED"
  | "DEADLINE_STOPPED"
  | "TRANSIENT_ERROR"
  | "SET_TERMINAL_ERROR"
  | "AUTH_FAILURE";

export type RunStatus = "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";

export type CloseAttemptResult = {
  // Espelha exatamente o texto devolvido pela RPC — 'SUCCESS' | 'RECONCILIATION_INCOMPLETE'
  // | 'BUDGET_STOPPED' | 'DEADLINE_STOPPED' | 'TRANSIENT_ERROR' | 'SET_TERMINAL_ERROR' |
  // 'AUTH_FAILURE' | 'STATE_NOT_FOUND' (ver migration 3933) — nunca reinterpretado aqui.
  finalOutcome: string;
  seenCount: number | null;
  expectedCount: number | null;
};

export interface SetRefreshPort {
  // ---- Leitura — nunca escreve nada. --------------------------------------------
  listConfirmedIdentitiesForSet(
    pricingSourceId: string,
    cardSetId: string,
  ): Promise<RefreshIdentityRow[]>;
  getConditionMap(pricingSourceId: string): Promise<Map<string, string>>;
  findLatestObservations(
    keys: readonly LatestObservationKey[],
  ): Promise<LatestObservationRow[]>;

  // ---- Escrita — só pricing_product (RPC resolve_pricing_products_batch, NEW/REUSE
  // pela chave econômica real) e pricing_observation (INSERT-only). Nunca
  // pricing_set_mapping/pricing_card_mapping/pricing_source_card_identity (regra 11 —
  // superfície estrutural, ver cabeçalho). ------
  resolveProductsBatch(
    rows: readonly ResolveProductsBatchInput[],
  ): Promise<ResolveProductsBatchResult>;
  insertObservations(
    rows: readonly InsertObservationInput[],
  ): Promise<InsertObservationsResult>;
  // Telemetria — reaproveitada tal como já existe no adapter antigo (mesma tabela
  // pricing_sync_run_call, mesmo contrato). Chamada em checkpoints incrementais por
  // set-refresh-core.ts (nunca só uma vez no fim) — mesma disciplina de core.ts (wave-
  // based) pós-incidente 2026-08-21: nunca perde telemetria de calls já feitas por um
  // corte inesperado no meio do processamento.
  insertSyncRunCalls(
    syncRunId: string,
    callLog: readonly PriceRefreshCallLogEntry[],
  ): Promise<InsertObservationsResult>;

  // ---- Ciclo de vida do run PRICE_REFRESH por Set — RPCs 3933, único escritor de
  // pricing_sync_run/pricing_set_refresh_state a partir deste núcleo. ------
  openAttempt(pricingSourceId: string): Promise<OpenAttemptResult>;
  checkpointPage(
    syncRunId: string,
    newResumeOffset: number,
    newlySeenExternalCardIds: readonly string[],
  ): Promise<CheckpointResult>;
  closeAttempt(
    syncRunId: string,
    pageOutcome: PageOutcome,
    runStatus: RunStatus,
    requestsMade: number,
    rateLimitHits: number,
    errorSummary: string | null,
  ): Promise<CloseAttemptResult>;
}
