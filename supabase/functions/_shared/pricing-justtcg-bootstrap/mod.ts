// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-bootstrap/mod.ts
// Ponto único de importação do executor de bootstrap de Set (P16.5.2/P16.5.3, 2026-08-26).
// Mesmo padrão já usado por _shared/pricing-justtcg-refresh/mod.ts (se existir) e
// _shared/pricing-justtcg-matching/mod.ts — um futuro consumidor (Edge Function/CLI) deve
// importar só por aqui, nunca os módulos internos diretamente.

export {
  BOOTSTRAP_INTERNAL_DEADLINE_MS,
  BOOTSTRAP_REQUEST_BUDGET,
  decideAcquisitionRunStatus,
  dedupeCardsForStaging,
  executeBootstrapAttempt,
} from "./bootstrap-core.ts";
export type { BootstrapExecutionResult } from "./bootstrap-core.ts";

export type {
  BootstrapPhaseOutcome,
  BootstrapPort,
  BootstrapRunStatus,
  CheckpointAcquisitionResult,
  CloseBootstrapAttemptResult,
  LocalActiveCard,
  OpenBootstrapAttemptResult,
  PersistBootstrapBatchResult,
  PersistBootstrapRowInput,
  PersistBootstrapRowResult,
  StagedCardInput,
  StagedCardRow,
} from "./bootstrap-port.ts";

export { buildBootstrapSupabaseAdapter } from "./bootstrap-supabase-adapter.ts";
export type { SanitizedLogger } from "./bootstrap-supabase-adapter.ts";
