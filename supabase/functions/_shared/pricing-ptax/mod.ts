// Project Mimikyu — supabase/functions/_shared/pricing-ptax/mod.ts
// Ponto único de importação do núcleo compartilhado de ingestão PTAX (Incremento
// P13.2). Consumidores (adapter manual hoje, futura Edge Function agendada em
// P13.3+) devem importar só por aqui — nunca os módulos internos diretamente — mesmo
// padrão já usado em supabase/functions/_shared/catalog-normalization/mod.ts.

export { runPtaxSync } from "./core.ts";
export type { RunPtaxSyncInput } from "./core.ts";

export {
  DEFAULT_WINDOW_DAYS,
  enumerateCivilDates,
  isValidCivilDate,
  MAX_OVERRIDE_WINDOW_DAYS,
  resolveDefaultPeriod,
  resolveOverridePeriod,
} from "./period.ts";
export type { PeriodResolution } from "./period.ts";

export { BCB_PTAX_API_BASE, buildPtaxPeriodUrl } from "./url.ts";

export {
  DEFAULT_TIMEOUT_MS,
  fetchPtaxPeriodWithRetry,
  isRetryableStatus,
  MAX_ATTEMPTS,
  RETRY_DELAYS_MS,
} from "./http.ts";
export type { PtaxHttpResult } from "./http.ts";

export { extractRateDate, validatePtaxResponseShape } from "./validate.ts";

export { selectClosingRatesByDate } from "./select-closing.ts";

export { persistPtaxRates } from "./persist.ts";

export { sanitize, truncateForDiagnostics } from "./sanitize.ts";

export {
  buildErrorSummary,
  classifyStartAttempt,
  decideFinalStatus,
} from "./sync-run-orchestration.ts";
export type {
  FinalSyncRunStatus,
  StartAttemptOutcome,
} from "./sync-run-orchestration.ts";

// Ciclo de vida de pricing_sync_run/pricing_sync_run_call para BCB_PTAX — Incremento
// P13.3. Reaproveitado tanto pelo adapter manual (triggered_by='MANUAL') quanto pela
// Edge Function agendada ptax-fx-refresh (triggered_by='SCHEDULED'). Depende só da
// porta funcional PtaxSyncRunPort — nunca de um tipo que reproduza o PostgREST.
export {
  computeReferenceDateSaoPaulo,
  finalizeSyncRun,
  FROM_CURRENCY,
  persistCallLog,
  RATE_SOURCE_CODE,
  TO_CURRENCY,
  tryStartSyncRun,
} from "./run-lifecycle.ts";
export type {
  InsertSyncRunCallsResult,
  InsertSyncRunResult,
  PtaxSyncRunPort,
  SyncRunTrigger,
  UpdateSyncRunPatch,
} from "./run-lifecycle.ts";

// Adapter de infraestrutura compartilhado — a ÚNICA implementação de PtaxSyncRunPort
// sobre o SupabaseClient real. CLI (scripts/sync-ptax-fx-rate.ts) e Edge Function
// (ptax-fx-refresh/index.ts) constroem este adapter uma única vez cada, nunca
// duplicando queries entre os dois chamadores.
export { buildPricingPtaxSupabaseAdapter } from "./supabase-adapter.ts";

export type {
  CivilDate,
  DivergenceDetail,
  FetchLike,
  InvalidDetail,
  PersistCounts,
  PtaxCallLogEntry,
  PtaxFetchOutcome,
  PtaxPeriod,
  PtaxRate,
  PtaxRateRepository,
  PtaxRawItem,
  PtaxRunResult,
  WaitLike,
} from "./types.ts";
