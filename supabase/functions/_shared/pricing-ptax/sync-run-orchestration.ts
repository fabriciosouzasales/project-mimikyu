// Project Mimikyu — supabase/functions/_shared/pricing-ptax/sync-run-orchestration.ts
// Decisões puras de orquestração de pricing_sync_run/pricing_sync_run_call —
// Incremento P13.2. Extraídas do adapter manual para serem testáveis sem nenhum
// cliente Supabase real (nem fake com formato de SDK) — só recebem/devolvem dados
// simples. O adapter (scripts/sync-ptax-fx-rate.ts) é quem efetivamente chama
// supabase.from(...) e usa estas funções só para decidir O QUE gravar.

import type { PtaxRunResult } from "./types.ts";

export type StartAttemptOutcome =
  | "STARTED"
  | "CONCURRENT_CONFLICT"
  | "OTHER_ERROR";

// Classifica o resultado de uma tentativa de INSERT em pricing_sync_run. O código
// Postgres 23505 (unique_violation) nesta tabela só pode vir dos índices únicos
// parciais de concorrência (ux_pricing_sync_run_active_fx_per_source_type, Query
// 3907) — ou seja, já existe uma execução FX_REFRESH ativa (RECEIVED/PROCESSING).
// Este é o sinal que o adapter usa para abortar ANTES de qualquer chamada ao BCB.
export function classifyStartAttempt(
  error: { code?: string; message?: string } | null,
): StartAttemptOutcome {
  if (!error) return "STARTED";
  if (error.code === "23505") return "CONCURRENT_CONFLICT";
  return "OTHER_ERROR";
}

export type FinalSyncRunStatus =
  | "COMPLETED"
  | "COMPLETED_WITH_ERRORS"
  | "FAILED";

// Mapeia o resultado estruturado do núcleo para o status terminal de
// pricing_sync_run — reaproveita o mesmo domínio já usado pelo conector JustTCG
// (COMPLETED / COMPLETED_WITH_ERRORS / FAILED), nunca introduz um valor novo.
// Divergência e item inválido NÃO são falha técnica — o run termina
// COMPLETED_WITH_ERRORS (dado real foi processado, só precisa de revisão), nunca
// FAILED, preservando a distinção "warning" vs "erro" pedida nesta rodada.
export function decideFinalStatus(result: PtaxRunResult): FinalSyncRunStatus {
  if (
    result.kind === "TECHNICAL_FAILURE" || result.kind === "FUNCTIONAL_FAILURE"
  ) return "FAILED";
  if (result.counts.divergent > 0 || result.counts.invalid > 0) {
    return "COMPLETED_WITH_ERRORS";
  }
  return "COMPLETED";
}

// Constrói o texto de pricing_sync_run.error_summary — a ÚNICA coluna de texto
// livre disponível em pricing_sync_run (não existe uma coluna "warnings" separada).
// Quando o run é COMPLETED (sem divergência/inválido), o resultado é sempre null —
// nunca escreve um "resumo" vazio ou artificial num run limpo. Divergência/inválido
// aqui é informação, não uma mensagem de erro técnico — por isso o texto nomeia
// explicitamente "divergência(s)"/"inválida(s)", nunca a palavra genérica "erro".
export function buildErrorSummary(result: PtaxRunResult): string | null {
  if (
    result.kind === "TECHNICAL_FAILURE" || result.kind === "FUNCTIONAL_FAILURE"
  ) {
    return result.detail;
  }
  if (result.kind !== "COMPLETED") return null;

  const parts: string[] = [];
  if (result.divergences.length > 0) {
    const detalhe = result.divergences.map((d) =>
      `${d.rateDate}(existente=${d.existingRate},recebido=${d.incomingRate})`
    ).join(", ");
    parts.push(
      `${result.divergences.length} divergência(s) — mantida a taxa já gravada, nunca sobrescrita: ${detalhe}`,
    );
  }
  if (result.invalidDetails.length > 0) {
    const detalhe = result.invalidDetails.map((d) => d.reason).join(" | ");
    parts.push(
      `${result.invalidDetails.length} item(ns) inválido(s) ignorado(s): ${detalhe}`,
    );
  }
  return parts.length > 0 ? parts.join(" || ") : null;
}
