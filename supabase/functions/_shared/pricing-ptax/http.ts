// Project Mimikyu — supabase/functions/_shared/pricing-ptax/http.ts
// Consulta HTTP com retry — Incremento P13.2.
//
// Três tentativas totais, esperas de 1s antes da 2ª e 3s antes da 3ª. Retry somente
// para falha de rede/timeout e para HTTP 408/429/5xx — qualquer outro 4xx é uma falha
// definitiva do lado do cliente (URL/parâmetros errados, por exemplo) e nunca é
// repetido, porque repetir não muda o resultado. fetch e a função de espera são
// sempre injetados pelo chamador — este módulo nunca referencia o `fetch` global nem
// `setTimeout` diretamente fora dos parâmetros recebidos, o que permite testar retry
// e timeout inteiramente sem rede real.

import type {
  FetchLike,
  PtaxCallLogEntry,
  PtaxFetchOutcome,
  WaitLike,
} from "./types.ts";
import { sanitize, truncateForDiagnostics } from "./sanitize.ts";

export const MAX_ATTEMPTS = 3;
export const RETRY_DELAYS_MS = [1_000, 3_000] as const; // espera antes da tentativa 2 e da tentativa 3
export const DEFAULT_TIMEOUT_MS = 15_000;

export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 429 || (status >= 500 && status <= 599);
}

export type PtaxHttpResult =
  | { status: "SUCCESS"; json: unknown; callLog: PtaxCallLogEntry[] }
  | {
    status: "TECHNICAL_FAILURE";
    detail: string;
    callLog: PtaxCallLogEntry[];
  };

export interface FetchWithRetryDeps {
  fetchImpl: FetchLike;
  waitImpl: WaitLike;
  timeoutMs?: number;
  endpointLabel?: string;
}

export async function fetchPtaxPeriodWithRetry(
  url: string,
  deps: FetchWithRetryDeps,
): Promise<PtaxHttpResult> {
  const timeoutMs = deps.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const endpoint = deps.endpointLabel ?? "CotacaoDolarPeriodo";
  const callLog: PtaxCallLogEntry[] = [];

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    if (attempt > 1) await deps.waitImpl(RETRY_DELAYS_MS[attempt - 2]);

    const controller = new AbortController();
    const timeoutHandle = setTimeout(() => controller.abort(), timeoutMs);

    let outcome: PtaxFetchOutcome = "TECHNICAL_FAILURE";
    let httpStatusCode: number | null = null;
    let errorDetail: string | null = null;
    let retryable = true;
    let successJson: unknown;

    try {
      const res = await deps.fetchImpl(url, {
        method: "GET",
        headers: { Accept: "application/json" },
        signal: controller.signal,
      });
      httpStatusCode = res.status;
      if (!res.ok) {
        const rawBody = await res.text().catch(() => "");
        errorDetail = `HTTP ${res.status}: ${
          sanitize(truncateForDiagnostics(rawBody)) ?? ""
        }`;
        retryable = isRetryableStatus(res.status);
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
      endpoint,
      httpStatusCode,
      outcome,
      errorDetail,
      apiRequestsRemaining: null,
    });

    if (outcome === "SUCCESS") {
      return { status: "SUCCESS", json: successJson, callLog };
    }
    if (!retryable) {
      return {
        status: "TECHNICAL_FAILURE",
        detail: errorDetail ?? "FALHA_TECNICA",
        callLog,
      };
    }
    // retryable === true: o loop continua para a próxima tentativa (ou termina abaixo
    // se esta já era a última das MAX_ATTEMPTS).
  }

  const last = callLog[callLog.length - 1];
  return {
    status: "TECHNICAL_FAILURE",
    detail: last?.errorDetail ?? "FALHA_TECNICA_APOS_RETRIES",
    callLog,
  };
}
