// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/supabase-adapter.ts
// Adapter de infraestrutura: implementa PokemonCatalogSourcingPort sobre um
// SupabaseClient real, via .rpc() — único arquivo deste módulo que importa
// "@supabase/supabase-js" (mesmo isolamento já usado em
// _shared/pricing-ptax/supabase-adapter.ts). Cada método é uma tradução
// direta e mínima de uma operação de domínio para uma chamada RPC real —
// nenhum DML direto em nenhuma tabela canônica.

import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  ApplyResult,
  CloseFailedResult,
  HeartbeatResult,
  OpenRunResult,
  PlanResult,
  PokemonCatalogSourcingPort,
} from "./run-port.ts";
import type { PokemonCatalogSnapshot } from "./types.ts";
import { sanitize } from "./sanitize.ts";

// As 5 RPCs retornam TABLE (...) — o postgrest-js sempre entrega isso como um
// array de 1 linha (nunca um objeto solto), mesmo com RETURN QUERY SELECT de
// uma única linha.
function firstRow<T>(data: unknown): T {
  const rows = data as T[] | T;
  return Array.isArray(rows) ? rows[0] : rows;
}

export function buildPokemonCatalogSourcingSupabaseAdapter(
  supabase: SupabaseClient,
): PokemonCatalogSourcingPort {
  return {
    async openRun(runType, preflightRunId): Promise<OpenRunResult> {
      const { data, error } = await supabase.rpc(
        "open_pokemon_catalog_sourcing_run",
        { p_run_type: runType, p_preflight_run_id: preflightRunId },
      );
      if (error) {
        throw new Error(
          `OPEN_POKEMON_CATALOG_SOURCING_RUN_FAILED: ${sanitize(error.message)}`,
        );
      }
      const row = firstRow<{
        outcome: string;
        run_id: string | null;
        run_code: string | null;
        preflight_run_id: string | null;
        preflight_snapshot_hash: string | null;
      }>(data);
      return {
        outcome: row.outcome as OpenRunResult["outcome"],
        runId: row.run_id,
        runCode: row.run_code,
        preflightRunId: row.preflight_run_id,
        preflightSnapshotHash: row.preflight_snapshot_hash,
      };
    },

    async heartbeat(runId): Promise<HeartbeatResult> {
      const { data, error } = await supabase.rpc(
        "heartbeat_pokemon_catalog_sourcing_run",
        { p_run_id: runId },
      );
      if (error) {
        throw new Error(
          `HEARTBEAT_POKEMON_CATALOG_SOURCING_RUN_FAILED: ${
            sanitize(error.message)
          }`,
        );
      }
      const row = firstRow<
        { outcome: string; run_id: string; status: string; heartbeat_at: string }
      >(data);
      return {
        outcome: row.outcome as HeartbeatResult["outcome"],
        runId: row.run_id,
        status: row.status,
        heartbeatAt: row.heartbeat_at,
      };
    },

    async plan(
      runId: string,
      snapshot: PokemonCatalogSnapshot,
    ): Promise<PlanResult> {
      const { data, error } = await supabase.rpc(
        "plan_pokemon_catalog_sourcing_run",
        { p_run_id: runId, p_snapshot: snapshot },
      );
      if (error) {
        throw new Error(
          `PLAN_POKEMON_CATALOG_SOURCING_RUN_FAILED: ${sanitize(error.message)}`,
        );
      }
      const row = firstRow<{
        outcome: string;
        run_id: string;
        status: string;
        snapshot_hash: string | null;
        plan_summary: Record<string, unknown> | null;
      }>(data);
      return {
        outcome: row.outcome as PlanResult["outcome"],
        runId: row.run_id,
        status: row.status,
        snapshotHash: row.snapshot_hash,
        planSummary: row.plan_summary,
      };
    },

    async apply(
      runId: string,
      snapshot: PokemonCatalogSnapshot,
    ): Promise<ApplyResult> {
      const { data, error } = await supabase.rpc(
        "apply_pokemon_catalog_sourcing_run",
        { p_run_id: runId, p_snapshot: snapshot },
      );
      if (error) {
        throw new Error(
          `APPLY_POKEMON_CATALOG_SOURCING_RUN_FAILED: ${sanitize(error.message)}`,
        );
      }
      const row = firstRow<{
        outcome: string;
        run_id: string;
        status: string;
        apply_summary: Record<string, unknown>;
      }>(data);
      return {
        outcome: row.outcome as ApplyResult["outcome"],
        runId: row.run_id,
        status: row.status,
        applySummary: row.apply_summary,
      };
    },

    async closeFailed(
      runId: string,
      errorSummary: string | null,
    ): Promise<CloseFailedResult> {
      const { data, error } = await supabase.rpc(
        "close_failed_pokemon_catalog_sourcing_run",
        { p_run_id: runId, p_error_summary: errorSummary },
      );
      if (error) {
        throw new Error(
          `CLOSE_FAILED_POKEMON_CATALOG_SOURCING_RUN_FAILED: ${
            sanitize(error.message)
          }`,
        );
      }
      const row = firstRow<{ outcome: string; run_id: string; status: string }>(
        data,
      );
      return {
        outcome: row.outcome as CloseFailedResult["outcome"],
        runId: row.run_id,
        status: row.status,
      };
    },
  };
}
