// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/run-lifecycle.ts
// Ciclo de vida de pricing_sync_run/pricing_sync_run_call para o refresh diário JustTCG
// (run_type=PRICE_REFRESH) — Incremento de Atualização Diária JustTCG (2026-08-21),
// item B.
//
// Mesmo padrão estrutural de supabase/functions/_shared/pricing-ptax/run-lifecycle.ts:
// depende só da porta (RefreshPort/PriceRefreshRunPort — ver port.ts), nunca de um tipo
// que reproduza a API fluente do PostgREST. Diferença deliberada: aqui não existe
// SyncRunTrigger com dois variantes (MANUAL/SCHEDULED) — esta porta é SEMPRE SCHEDULED
// (regra 8, "confirmed_by=NULL"), então insertPriceRefreshRun() não recebe nem aceita
// nenhum parâmetro de trigger — impossível, em nível de tipo, abrir um run MANUAL por
// este caminho.
//
// started_at/finished_at NUNCA são enviados por este módulo — mesmo padrão de
// trg_pricing_sync_run_server_timestamps já usado por FX_REFRESH/CARD_SYNC: o trigger no
// banco é a única autoridade sobre os dois timestamps. UpdateSyncRunPatch não tem campo
// de timestamp algum (garantia em nível de tipo, não só de disciplina).

import type {
  FinalRefreshRunStatus,
  PriceRefreshCallLogEntry,
  RefreshPort,
  UpdateSyncRunPatch,
} from "./port.ts";

export interface PriceRefreshRunPort extends RefreshPort {}

export async function tryStartPriceRefreshRun(
  port: PriceRefreshRunPort,
  pricingSourceId: string,
): Promise<
  | { status: "STARTED"; syncRunId: string }
  | { status: "CONCURRENT_CONFLICT" }
  | { status: "OTHER_ERROR"; detail: string }
> {
  // Primeira operação de qualquer onda, sempre ANTES de qualquer fetch à JustTCG. O
  // conflito de concorrência (23505 no adapter real) cobre dois casos distintos, ambos
  // desta mesma porta: outro PRICE_REFRESH já ativo para a fonte (índice pré-existente,
  // Query 3907) OU um CARD_SYNC já ativo para a mesma fonte (índice novo desta rodada,
  // item D — mútua exclusão CARD_SYNC×PRICE_REFRESH). O adapter real (supabase-adapter.ts)
  // é o único responsável por classificar QUALQUER 23505 como CONCURRENT_CONFLICT,
  // independente de qual dos dois índices o disparou — este módulo nunca precisa saber
  // qual índice específico colidiu.
  const result = await port.insertPriceRefreshRun(pricingSourceId);
  if (result.outcome === "CONCURRENT_CONFLICT") {
    return { status: "CONCURRENT_CONFLICT" };
  }
  if (result.outcome === "OTHER_ERROR") {
    return {
      status: "OTHER_ERROR",
      detail: result.message ?? "ERRO_DESCONHECIDO",
    };
  }
  return { status: "STARTED", syncRunId: result.syncRunId };
}

// Persiste pricing_sync_run_call ANTES de qualquer finalização do run — mesma disciplina
// de PTAX (Query 3909). Devolve o resultado da tentativa em vez de lançar, para que o
// chamador decida como finalizar o run (nunca como COMPLETED se isto falhar).
export async function persistCallLog(
  port: PriceRefreshRunPort,
  syncRunId: string,
  callLog: readonly PriceRefreshCallLogEntry[],
): Promise<{ ok: true } | { ok: false; detail: string }> {
  if (callLog.length === 0) return { ok: true };
  const result = await port.insertSyncRunCalls(syncRunId, callLog);
  if (!result.ok) {
    return { ok: false, detail: result.message ?? "ERRO_DESCONHECIDO" };
  }
  return { ok: true };
}

// Finaliza pricing_sync_run com um status JÁ DECIDIDO pelo chamador — nunca decide
// sozinho se o resultado "merece" COMPLETED (mesma disciplina de PTAX/CLI: a regra "calls
// persistidas antes de COMPLETED" fica explícita no ponto de chamada).
export async function finalizeSyncRun(
  port: PriceRefreshRunPort,
  syncRunId: string,
  status: FinalRefreshRunStatus,
  errorSummary: string | null,
  requestsMade: number,
  rateLimitHits: number,
): Promise<void> {
  const patch: UpdateSyncRunPatch = {
    status,
    errorSummary,
    requestsMade,
    rateLimitHits,
  };
  await port.updateSyncRun(syncRunId, patch);
}
