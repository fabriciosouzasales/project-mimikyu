// Project Mimikyu — supabase/functions/_shared/pricing-ptax/supabase-adapter.ts
// Adapter de infraestrutura compartilhado: implementa PtaxSyncRunPort (run-lifecycle.ts)
// sobre um SupabaseClient real — correção estrutural, 2026-08-18.
//
// Único arquivo de todo o módulo _shared/pricing-ptax que importa
// "@supabase/supabase-js" — run-lifecycle.ts e core.ts permanecem livres de qualquer
// dependência concreta de SDK, dependendo só da porta (PtaxSyncRunPort/PtaxRateRepository).
// Construído UMA ÚNICA VEZ por cada chamador (scripts/sync-ptax-fx-rate.ts para o
// adapter manual, supabase/functions/ptax-fx-refresh/index.ts para a Edge Function
// agendada) — nenhuma query é duplicada entre os dois: ambos chamam
// buildPricingPtaxSupabaseAdapter(supabase) e reaproveitam o mesmo objeto para tudo
// (repositório de taxas + ciclo de vida do run), já que PtaxSyncRunPort estende
// PtaxRateRepository.
//
// Cada método aqui é uma tradução direta e mínima de uma operação de domínio para uma
// chamada real ao PostgREST — nunca uma tentativa de modelar a API fluente do
// PostgREST em si (essa tentativa anterior, via tipos estruturais recursivos, foi
// abandonada nesta rodada por não refletir com segurança o SupabaseClient real).

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  FROM_CURRENCY,
  type InsertSyncRunCallsResult,
  type InsertSyncRunResult,
  type PtaxSyncRunPort,
  RATE_SOURCE_CODE,
  TO_CURRENCY,
} from "./run-lifecycle.ts";
import { classifyStartAttempt } from "./sync-run-orchestration.ts";
import { sanitize } from "./sanitize.ts";

export function buildPricingPtaxSupabaseAdapter(
  supabase: SupabaseClient,
): PtaxSyncRunPort {
  return {
    async findExistingRates(dates) {
      const result = new Map<string, number>();
      if (dates.length === 0) return result;

      const { data, error } = await supabase
        .from("pricing_fx_rate")
        .select("rate_date, rate")
        .eq("from_currency", FROM_CURRENCY)
        .eq("to_currency", TO_CURRENCY)
        .eq("rate_source_code", RATE_SOURCE_CODE)
        .in("rate_date", dates);

      if (error) {
        throw new Error(
          `PRICING_FX_RATE_QUERY_FAILED: ${sanitize(error.message)}`,
        );
      }
      const rows = data as Array<{ rate_date: string; rate: number }> | null;
      for (const row of rows ?? []) {
        result.set(row.rate_date, Number(row.rate));
      }
      return result;
    },

    async insertRate(entry) {
      // ON CONFLICT DO NOTHING real via ignoreDuplicates — corrigido e validado no
      // Incremento P9, comportamento preservado sem alteração nesta rodada.
      const { data, error } = await supabase
        .from("pricing_fx_rate")
        .upsert(
          {
            from_currency: FROM_CURRENCY,
            to_currency: TO_CURRENCY,
            rate: entry.rate,
            rate_date: entry.rateDate,
            rate_source_code: RATE_SOURCE_CODE,
          },
          {
            onConflict: "from_currency,to_currency,rate_source_code,rate_date",
            ignoreDuplicates: true,
          },
        )
        .select("rate_date");

      if (error) {
        throw new Error(
          `PRICING_FX_RATE_UPSERT_FAILED(${entry.rateDate}): ${
            sanitize(error.message)
          }`,
        );
      }
      const rows = data as Array<{ rate_date: string }> | null;
      return (rows?.length ?? 0) > 0 ? "INSERTED" : "CONFLICT_IGNORED";
    },

    async insertSyncRun(trigger): Promise<InsertSyncRunResult> {
      // started_at nunca é enviado (Query 3909) — o trigger
      // trg_pricing_sync_run_server_timestamps é a única autoridade sobre o campo.
      const { data, error } = await supabase
        .from("pricing_sync_run")
        .insert({
          pricing_source_id: null,
          run_type: "FX_REFRESH",
          status: "PROCESSING",
          triggered_by: trigger.triggeredBy,
          confirmed_by: trigger.triggeredBy === "MANUAL"
            ? trigger.confirmedBy
            : null,
          fx_source_code: RATE_SOURCE_CODE,
        })
        .select("id")
        .single();

      // Reaproveita a mesma classificação pura já usada pelo núcleo (código Postgres
      // 23505 == conflito de concorrência via índice único parcial, Query 3907) — a
      // porta nunca expõe o formato bruto do erro do Postgres a run-lifecycle.ts.
      const outcome = classifyStartAttempt(error);
      if (outcome === "CONCURRENT_CONFLICT") {
        return { outcome: "CONCURRENT_CONFLICT" };
      }
      if (outcome === "OTHER_ERROR") {
        return { outcome: "OTHER_ERROR", message: error?.message ?? null };
      }
      return { outcome: "STARTED", syncRunId: (data as { id: string }).id };
    },

    async insertSyncRunCalls(
      syncRunId,
      callLog,
    ): Promise<InsertSyncRunCallsResult> {
      // error_detail já chega sanitizado por run-lifecycle.ts (camada de domínio) —
      // este adapter só faz a tradução de nome de campo para coluna.
      const { error } = await supabase.from("pricing_sync_run_call").insert(
        callLog.map((c) => ({
          sync_run_id: syncRunId,
          sequence_number: c.sequenceNumber,
          endpoint: c.endpoint,
          http_status_code: c.httpStatusCode,
          // outcome de pricing_sync_run_call só aceita SUCCESS/TECHNICAL_FAILURE/
          // BUDGET_STOPPED (ck_pricing_sync_run_call_outcome) — PTAX nunca usa
          // BUDGET_STOPPED (sem orçamento de requisições), mapeamento direto.
          outcome: c.outcome,
          error_detail: c.errorDetail,
          api_requests_remaining: c.apiRequestsRemaining,
        })),
      );

      if (error) return { ok: false, message: error.message };
      return { ok: true };
    },

    async updateSyncRun(syncRunId, patch): Promise<void> {
      // finished_at nunca é enviado (Query 3909) — mesma autoridade do trigger do
      // servidor. error_summary já chega sanitizado por run-lifecycle.ts.
      await supabase
        .from("pricing_sync_run")
        .update({
          status: patch.status,
          requests_made: patch.requestsMade,
          requests_remaining_at_end: null, // BCB não expõe orçamento de requisições
          rate_limit_hits: patch.rateLimitHits,
          error_summary: patch.errorSummary,
        })
        .eq("id", syncRunId);
    },
  };
}
