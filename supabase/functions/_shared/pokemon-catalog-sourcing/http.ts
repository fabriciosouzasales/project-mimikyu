// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/http.ts
// HTTP com retry/timeout/Retry-After + pool de concorrência configurável —
// Seção 12 do contrato ("HTTP / Fair Use"): concorrência default 5, configurável
// 1..10; retries/timeout limitados; retry de 429/5xx respeitando Retry-After.
//
// fetch e a função de espera são sempre injetados pelo chamador — este módulo
// nunca referencia o `fetch` global nem `setTimeout` diretamente fora dos
// parâmetros recebidos, o que permite testar retry/timeout/concorrência
// inteiramente sem rede real (mesmo padrão de _shared/pricing-ptax/http.ts).

import type { FetchLike, SourcingCallLogEntry, WaitLike } from "./types.ts";
import { sanitize, truncateForDiagnostics } from "./sanitize.ts";

export const DEFAULT_MAX_ATTEMPTS = 3;
export const DEFAULT_RETRY_DELAYS_MS = [1_000, 3_000] as const;
export const DEFAULT_TIMEOUT_MS = 15_000;
export const DEFAULT_CONCURRENCY = 5;
export const MIN_CONCURRENCY = 1;
export const MAX_CONCURRENCY = 10;

// REVISION-03 (Bloco 3) — nenhum GET desta ferramenta é feito para fora da
// PokéAPI oficial, mesmo que um `next`/resource url malicioso ou corrompido
// apareça em uma resposta (discovery paginado ou detail fetch). Único ponto
// de checagem: fetchJsonWithRetry() é o funil ÚNICO de toda chamada HTTP
// deste módulo (discovery.ts e acquisition.ts nunca chamam fetch por conta
// própria), então validar aqui cobre 100% dos GETs por construção.
export const ALLOWED_POKEAPI_URL_PREFIX = "https://pokeapi.co/api/v2/";

export function isAllowedPokeApiUrl(url: string): boolean {
  return url.startsWith(ALLOWED_POKEAPI_URL_PREFIX);
}

// Heartbeat TEMPORAL (Seção 7.2 + auditoria Bloco 3): renovação gated por
// tempo decorrido real, nunca por contagem de itens — cobre igualmente uma
// fase de discovery paginada (poucos itens, muitas páginas lentas) e uma
// fase de detail fetch com milhares de itens rápidos. `nowImpl` é sempre
// injetado (nunca `Date.now` referenciado diretamente aqui), mantendo este
// módulo livre de qualquer acesso a relógio/ambiente global, e permitindo
// controle determinístico em teste.
export const HEARTBEAT_MIN_INTERVAL_MS = 5 * 60 * 1000; // 5min — folga ampla sobre o stale threshold de 30min (Query 6103)

export function createHeartbeatGate(
  onHeartbeat: (() => Promise<void>) | undefined,
  nowImpl: () => number,
  minIntervalMs: number = HEARTBEAT_MIN_INTERVAL_MS,
): () => Promise<void> {
  let lastBeatAt = nowImpl();
  return async () => {
    if (!onHeartbeat) return;
    const now = nowImpl();
    if (now - lastBeatAt >= minIntervalMs) {
      lastBeatAt = now;
      await onHeartbeat();
    }
  };
}

// Concorrência HTTP default 5, configurável entre 1..10 (Seção 12) — nunca
// aceita um valor fora dessa faixa silenciosamente incorreto; sempre clampa.
export function clampConcurrency(value: number): number {
  if (!Number.isFinite(value)) return DEFAULT_CONCURRENCY;
  return Math.min(
    MAX_CONCURRENCY,
    Math.max(MIN_CONCURRENCY, Math.trunc(value)),
  );
}

export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 429 || (status >= 500 && status <= 599);
}

// Retry-After pode vir em segundos (inteiro) ou como data HTTP (RFC 7231) —
// Seção 12 exige respeitá-lo quando presente em 429/5xx.
export function parseRetryAfterMs(headerValue: string | null): number | null {
  if (!headerValue) return null;
  const trimmed = headerValue.trim();
  if (/^[0-9]+$/.test(trimmed)) {
    return Number(trimmed) * 1000;
  }
  const asDate = Date.parse(trimmed);
  if (!Number.isNaN(asDate)) {
    const delta = asDate - Date.now();
    return delta > 0 ? delta : 0;
  }
  return null;
}

export interface FetchJsonDeps {
  fetchImpl: FetchLike;
  waitImpl: WaitLike;
  timeoutMs?: number;
  maxAttempts?: number;
  retryDelaysMs?: readonly number[];
}

export type FetchJsonResult =
  | { status: "SUCCESS"; json: unknown; callLog: SourcingCallLogEntry[] }
  | {
    status: "TECHNICAL_FAILURE";
    detail: string;
    callLog: SourcingCallLogEntry[];
  };

export async function fetchJsonWithRetry(
  url: string,
  deps: FetchJsonDeps,
): Promise<FetchJsonResult> {
  // REVISION-03 (Bloco 3) — allowlist de origem ANTES de qualquer tentativa
  // de rede: um `next`/resource url fora de https://pokeapi.co/api/v2/
  // nunca chega a `deps.fetchImpl`. Como este é o único funil de HTTP do
  // módulo inteiro, isso cobre discovery (paginação) e detail fetch por
  // igual, sem precisar duplicar a checagem em cada chamador.
  if (!isAllowedPokeApiUrl(url)) {
    return {
      status: "TECHNICAL_FAILURE",
      detail: `URL_FORA_DO_ALLOWLIST: "${sanitize(truncateForDiagnostics(url)) ?? ""}"`,
      callLog: [],
    };
  }

  const timeoutMs = deps.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxAttempts = deps.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const retryDelays = deps.retryDelaysMs ?? DEFAULT_RETRY_DELAYS_MS;
  const callLog: SourcingCallLogEntry[] = [];

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const controller = new AbortController();
    const timeoutHandle = setTimeout(() => controller.abort(), timeoutMs);

    let outcome: "SUCCESS" | "TECHNICAL_FAILURE" = "TECHNICAL_FAILURE";
    let httpStatusCode: number | null = null;
    let errorDetail: string | null = null;
    let retryable = true;
    let retryAfterMs: number | null = null;
    let successJson: unknown;

    try {
      const res = await deps.fetchImpl(url, {
        method: "GET",
        headers: { Accept: "application/json" },
        signal: controller.signal,
        // REVISION-03 (Bloco 3) — nunca seguir redirect para origem não
        // permitida (nem qualquer origem, por padrão): "error" faz o fetch
        // rejeitar caso a resposta seja um redirect, ao invés de segui-lo
        // silenciosamente. Cai no catch abaixo como falha retryable comum.
        redirect: "error",
      });
      httpStatusCode = res.status;
      if (!res.ok) {
        const rawBody = await res.text().catch(() => "");
        errorDetail = `HTTP ${res.status}: ${
          sanitize(truncateForDiagnostics(rawBody)) ?? ""
        }`;
        retryable = isRetryableStatus(res.status);
        if (retryable) {
          retryAfterMs = parseRetryAfterMs(res.headers.get("Retry-After"));
        }
      } else {
        successJson = await res.json();
        outcome = "SUCCESS";
      }
    } catch (error) {
      const message = error instanceof Error
        ? error.message
        : "UNEXPECTED_ERROR";
      const isAbort = message === "AbortError" || /aborted/i.test(message);
      errorDetail = isAbort
        ? `TIMEOUT_APOS_${timeoutMs}MS`
        : sanitize(truncateForDiagnostics(message)) ?? "FALHA_DE_CONEXAO";
      retryable = true; // falha de rede/timeout é sempre elegível a retry
    } finally {
      clearTimeout(timeoutHandle);
    }

    callLog.push({
      sequenceNumber: callLog.length + 1,
      endpoint: url,
      httpStatusCode,
      outcome,
      errorDetail,
    });

    if (outcome === "SUCCESS") {
      return { status: "SUCCESS", json: successJson, callLog };
    }
    if (!retryable || attempt === maxAttempts) {
      return {
        status: "TECHNICAL_FAILURE",
        detail: errorDetail ?? "FALHA_TECNICA",
        callLog,
      };
    }
    const fallbackDelay = retryDelays[attempt - 1] ??
      retryDelays[retryDelays.length - 1] ?? 1_000;
    await deps.waitImpl(retryAfterMs ?? fallbackDelay);
  }

  const last = callLog[callLog.length - 1];
  return {
    status: "TECHNICAL_FAILURE",
    detail: last?.errorDetail ?? "FALHA_TECNICA_APOS_RETRIES",
    callLog,
  };
}

// Pool de concorrência simples — nunca dispara mais de `concurrency` chamadas
// simultâneas. Preserva a correspondência de índice entre entrada e saída
// (results[i] é sempre o resultado de items[i], independente da ordem real de
// conclusão).
//
// `onItemSettled`, quando fornecido, é chamado após CADA item concluído (com
// a contagem acumulada e o total) — usado por acquisition.ts para renovar o
// heartbeat periodicamente durante uma aquisição longa (Seção 7.2), não
// apenas uma vez no início. Opcional e sem efeito no resultado retornado.
export async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  worker: (item: T, index: number) => Promise<R>,
  onItemSettled?: (completedCount: number, total: number) => void | Promise<void>,
): Promise<R[]> {
  const limit = clampConcurrency(concurrency);
  const results: R[] = new Array(items.length);
  let nextIndex = 0;
  let completed = 0;

  async function runNext(): Promise<void> {
    for (;;) {
      const current = nextIndex++;
      if (current >= items.length) return;
      results[current] = await worker(items[current], current);
      completed++;
      if (onItemSettled) await onItemSettled(completed, items.length);
    }
  }

  const workerCount = Math.min(limit, items.length);
  const workers = Array.from({ length: workerCount }, () => runNext());
  await Promise.all(workers);
  return results;
}
