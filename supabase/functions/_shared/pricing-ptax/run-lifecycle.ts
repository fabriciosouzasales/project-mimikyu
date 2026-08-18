// Project Mimikyu — supabase/functions/_shared/pricing-ptax/run-lifecycle.ts
// Ciclo de vida de pricing_sync_run/pricing_sync_run_call para a fonte cambial BCB_PTAX
// — Incremento P13.3 (2026-08-18).
//
// Extraído do adapter manual (scripts/sync-ptax-fx-rate.ts, Incremento P13.2) para ser
// reaproveitado por QUALQUER chamador autenticado — hoje o adapter manual
// (triggered_by='MANUAL', confirmed_by=<admin_user_uuid>), a partir desta rodada também a
// Edge Function agendada supabase/functions/ptax-fx-refresh (triggered_by='SCHEDULED',
// confirmed_by=NULL). Nenhuma lógica de decisão foi alterada nesta extração — só
// generalizada a origem do trigger, exatamente a única variação real entre os dois
// chamadores (ver ADR-030, tabela pricing_sync_run.triggered_by).
//
// Porta funcional estreita (correção estrutural, 2026-08-18): este módulo depende
// SOMENTE de PtaxSyncRunPort — cinco operações de domínio (findExistingRates,
// insertRate, insertSyncRun, insertSyncRunCalls, updateSyncRun), nunca de um tipo que
// reproduza a API fluente do PostgREST (.from().select().eq()...). Quem implementa a
// porta sobre o SupabaseClient real é o adapter de infraestrutura compartilhado
// (./supabase-adapter.ts) — construído uma única vez por cada chamador (CLI e Edge
// Function), nunca duplicado. O mesmo objeto que implementa PtaxSyncRunPort já
// satisfaz PtaxRateRepository (exigido pelo núcleo em core.ts) por extensão de
// interface — nenhum wrapper adicional é necessário para passá-lo a runPtaxSync().
//
// started_at/finished_at NUNCA são enviados por este módulo (correção Query 3909,
// 2026-08-18, preservada sem alteração nesta extração) — o trigger
// trg_pricing_sync_run_server_timestamps é a única autoridade sobre os dois timestamps.
// Com a porta funcional, isto passou a ser garantido também em nível de tipo: nem
// SyncRunTrigger nem UpdateSyncRunPatch têm campo de timestamp algum.

import type { PtaxCallLogEntry, PtaxRateRepository } from "./types.ts";
import type { FinalSyncRunStatus } from "./sync-run-orchestration.ts";
import { sanitize } from "./sanitize.ts";

// ============================================================================
// 0. Identidade fixa da fonte cambial — mesma origem única usada pelo adapter (P13.2) e
//    agora também pela Edge Function agendada (P13.3). Nenhum outro chamador deve
//    redeclarar estas constantes.
// ============================================================================

export const FROM_CURRENCY = "USD";
export const TO_CURRENCY = "BRL";
export const RATE_SOURCE_CODE = "BCB_PTAX"; // pricing_fx_rate.rate_source_code E pricing_sync_run.fx_source_code

// ============================================================================
// 1. Porta funcional mínima de persistência — só as operações de pricing
//    realmente usadas por este módulo, orientadas ao domínio (nunca ao formato de
//    linha/tabela do Postgres). PtaxRate/PtaxCallLogEntry/PtaxRateRepository vêm de
//    types.ts; FinalSyncRunStatus vem de sync-run-orchestration.ts — nenhum tipo
//    novo duplica o que já existe.
// ============================================================================

// Origem do disparo — única variação real entre os chamadores. MANUAL sempre exige
// confirmedBy (admin_user_uuid, validado por trigger no banco — Query 3082/3083);
// SCHEDULED nunca tem confirmedBy (execução automática, sem admin por trás no momento
// da chamada — ver ADR-030/ADR-031, "execução via Edge deve usar triggered_by=SCHEDULED
// e confirmed_by=NULL"). A ausência do campo confirmedBy no variante SCHEDULED já
// impede, em nível de tipo, que um confirmed_by seja enviado nesta origem.
export type SyncRunTrigger =
  | { triggeredBy: "MANUAL"; confirmedBy: string }
  | { triggeredBy: "SCHEDULED" };

export type InsertSyncRunResult =
  | { outcome: "STARTED"; syncRunId: string }
  | { outcome: "CONCURRENT_CONFLICT" }
  | { outcome: "OTHER_ERROR"; message: string | null };

export type InsertSyncRunCallsResult =
  | { ok: true }
  | { ok: false; message: string | null };

export interface UpdateSyncRunPatch {
  status: FinalSyncRunStatus;
  errorSummary: string | null;
  requestsMade: number;
  rateLimitHits: number;
}

export interface PtaxSyncRunPort extends PtaxRateRepository {
  // Abre um novo pricing_sync_run (run_type=FX_REFRESH, fx_source_code=BCB_PTAX). A
  // classificação de conflito de concorrência (índice único parcial,
  // ux_pricing_sync_run_active_fx_per_source_type, Query 3907) é responsabilidade do
  // adapter — este módulo só reage a STARTED/CONCURRENT_CONFLICT/OTHER_ERROR.
  insertSyncRun(trigger: SyncRunTrigger): Promise<InsertSyncRunResult>;
  // Registra a telemetria de chamadas HTTP ao BCB de uma execução (pricing_sync_run_call).
  insertSyncRunCalls(
    syncRunId: string,
    callLog: PtaxCallLogEntry[],
  ): Promise<InsertSyncRunCallsResult>;
  // Finaliza um pricing_sync_run com um status/telemetria já decididos pelo chamador.
  updateSyncRun(syncRunId: string, patch: UpdateSyncRunPatch): Promise<void>;
}

// ============================================================================
// 2. Orquestração de pricing_sync_run/pricing_sync_run_call — depende só da porta
//    acima; nenhuma função aqui sabe o nome de uma tabela ou coluna do Postgres.
// ============================================================================

export async function tryStartSyncRun(
  port: PtaxSyncRunPort,
  trigger: SyncRunTrigger,
): Promise<
  | { status: "STARTED"; syncRunId: string }
  | { status: "CONCURRENT_CONFLICT" }
  | { status: "OTHER_ERROR"; detail: string }
> {
  // Primeira operação de qualquer chamador, de propósito ANTES de qualquer fetch ao
  // BCB (adapter manual ou Edge Function agendada) — ver PtaxSyncRunPort.insertSyncRun.
  //
  // started_at NUNCA é enviado (correção Query 3909, 2026-08-18): o trigger
  // trg_pricing_sync_run_server_timestamps é a única autoridade sobre started_at,
  // atribuindo sempre now() do próprio Postgres — e SyncRunTrigger não tem campo de
  // timestamp algum, então este módulo nem teria como enviar um mesmo que quisesse.
  const result = await port.insertSyncRun(trigger);
  if (result.outcome === "CONCURRENT_CONFLICT") {
    return { status: "CONCURRENT_CONFLICT" };
  }
  if (result.outcome === "OTHER_ERROR") {
    return {
      status: "OTHER_ERROR",
      detail: sanitize(result.message) ?? "ERRO_DESCONHECIDO",
    };
  }
  return { status: "STARTED", syncRunId: result.syncRunId };
}

// Persiste pricing_sync_run_call ANTES de qualquer finalização do run (correção Query
// 3909/reordenação de telemetria, 2026-08-18) — um run só pode assumir status terminal
// depois de sua telemetria de chamadas já estar gravada. Devolve o resultado da tentativa
// em vez de lançar, para que o chamador decida como finalizar o run (nunca como
// COMPLETED se isto falhar).
export async function persistCallLog(
  port: PtaxSyncRunPort,
  syncRunId: string,
  callLog: PtaxCallLogEntry[],
): Promise<{ ok: true } | { ok: false; detail: string }> {
  if (callLog.length === 0) return { ok: true };

  // Nunca distorcido por divergência de dado — error_detail aqui é sempre o resultado
  // bruto da CHAMADA HTTP em si (sucesso ou falha técnica), nunca uma reformulação por
  // causa de um achado de persistência. Sanitizado aqui (camada de domínio) antes de
  // chegar à porta, mesma disciplina já usada em toda mensagem livre desta rodada.
  const sanitizedCallLog = callLog.map((c) => ({
    ...c,
    errorDetail: c.errorDetail ? sanitize(c.errorDetail) : null,
  }));

  const result = await port.insertSyncRunCalls(syncRunId, sanitizedCallLog);
  if (!result.ok) {
    return {
      ok: false,
      detail: sanitize(result.message) ?? "ERRO_DESCONHECIDO",
    };
  }
  return { ok: true };
}

// Finaliza pricing_sync_run com um status JÁ DECIDIDO pelo chamador — nunca decide
// sozinho se o resultado "merece" COMPLETED, exatamente para que a regra "calls
// persistidas antes de COMPLETED" fique explícita no ponto de chamada, não escondida
// aqui dentro.
//
// finished_at NUNCA é enviado (correção Query 3909, 2026-08-18): o trigger
// trg_pricing_sync_run_server_timestamps é a única autoridade sobre finished_at,
// atribuindo now() do servidor na primeira transição para um status terminal e
// preservando o valor já gravado em qualquer atualização posterior de um run já
// terminal — e UpdateSyncRunPatch não tem campo de timestamp algum.
export async function finalizeSyncRun(
  port: PtaxSyncRunPort,
  syncRunId: string,
  status: FinalSyncRunStatus,
  errorSummary: string | null,
  requestsMade: number,
  rateLimitHits: number,
  dryRun: boolean,
): Promise<void> {
  if (dryRun) return; // dry-run nunca cria nem finaliza pricing_sync_run/pricing_sync_run_call

  await port.updateSyncRun(syncRunId, {
    status,
    requestsMade,
    rateLimitHits,
    errorSummary: errorSummary ? sanitize(errorSummary) : null,
  });
}

// ============================================================================
// 3. Data civil (YYYY-MM-DD) de America/Sao_Paulo — nunca o fuso do processo local. O
//    núcleo compartilhado (core.ts) nunca lê o relógio do sistema diretamente; é
//    responsabilidade do CHAMADOR resolver "hoje" e passar como referenceDate. Extraído
//    do adapter (P13.2) para P13.3 por ser a mesma resolução de data exigida pela Edge
//    Function agendada — função pura (recebe `now` injetado, nunca lê Date.now()/o
//    relógio do processo sozinha), por isso cabe neste módulo sem violar a regra de
//    "núcleo sem Deno.env/fetch global/cliente Supabase".
// ============================================================================

export function computeReferenceDateSaoPaulo(now: Date): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(now); // en-CA formata como YYYY-MM-DD diretamente
}
