// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/run-port.ts
// Porta mínima exigida do caller sobre as RPCs SECURITY DEFINER de
// docs/06a-pokemon-catalog-sourcing.md (Seções 7-10) — SERVICE_ROLE ONLY.
// Nenhuma implementação desta porta faz DML direto nas tabelas canônicas: toda
// escrita/leitura privilegiada passa exclusivamente pelas 5 RPCs físicas
// (6103/6104/6105/6107/6108, ver database/schema/).

import type { PokemonCatalogSnapshot } from "./types.ts";

export type OpenRunOutcome = "CLAIMED" | "SOURCE_BUSY";

export interface OpenRunResult {
  outcome: OpenRunOutcome;
  runId: string | null;
  runCode: string | null;
  preflightRunId: string | null;
  preflightSnapshotHash: string | null;
}

export interface HeartbeatResult {
  outcome: "OK";
  runId: string;
  status: string;
  heartbeatAt: string;
}

export type PlanOutcome =
  | "COMPLETED"
  | "COMPLETED_WITH_DIVERGENCES"
  | "VALIDATION_FAILURE"
  | "PAYLOAD_GUARD_EXCEEDED";

export interface PlanResult {
  outcome: PlanOutcome;
  runId: string;
  status: string;
  snapshotHash: string | null;
  planSummary: Record<string, unknown> | null;
}

export interface ApplyResult {
  outcome: "COMPLETED";
  runId: string;
  status: string;
  applySummary: Record<string, unknown>;
}

export interface CloseFailedResult {
  outcome: "FAILED";
  runId: string;
  status: string;
}

export interface PokemonCatalogSourcingPort {
  // open_pokemon_catalog_sourcing_run (Query 6103).
  openRun(
    runType: "DRY_RUN" | "APPLY",
    preflightRunId: string | null,
  ): Promise<OpenRunResult>;
  // heartbeat_pokemon_catalog_sourcing_run (Query 6107) — PENDING->ACQUIRING,
  // chamada ANTES de iniciar a aquisição HTTP (precondição do PLAN).
  heartbeat(runId: string): Promise<HeartbeatResult>;
  // plan_pokemon_catalog_sourcing_run (Query 6104).
  plan(
    runId: string,
    snapshot: PokemonCatalogSnapshot,
  ): Promise<PlanResult>;
  // apply_pokemon_catalog_sourcing_run (Query 6105).
  apply(
    runId: string,
    snapshot: PokemonCatalogSnapshot,
  ): Promise<ApplyResult>;
  // close_failed_pokemon_catalog_sourcing_run (Query 6108).
  closeFailed(
    runId: string,
    errorSummary: string | null,
  ): Promise<CloseFailedResult>;
}
