// Project Mimikyu — supabase/functions/_shared/pricing-justtcg/client.ts
// Cliente HTTP tipado da JustTCG v1 — extraído verbatim (mesma lógica, zero mudança de
// comportamento) de scripts/sync-justtcg-pricing.ts (Incrementos P8/P14.1/P14.4.2) para
// o Incremento de Atualização Diária JustTCG (2026-08-21), item A do pedido de Fabrício:
// "Extraia o cliente HTTP/paginação e os tipos puros da JustTCG... O script CLI e a nova
// Edge Function devem consumir o mesmo núcleo. Não duplique parser, paginação,
// normalização ou controle de orçamento. Preserve todas as assinaturas/comportamentos
// existentes do CLI."
//
// Timeout, tratamento de 401 (AUTH_FAILURE — nunca segue tentando)/429 (backoff + 1
// retry, budget permitindo)/5xx, orçamento local conservador (effectiveBudget, nunca
// acima de MAX_REQUESTS_PER_RUN), 3s de intervalo entre chamadas, fetchImpl injetável
// (permite testar 100% offline, mesmo padrão de _shared/pricing-ptax/core.ts).
//
// MAX_REQUESTS_PER_RUN aqui é o teto de SEGURANÇA do PROCESSO — o CLI o usa como teto
// único (MAX_REQUESTS_PER_RUN=30, ver histórico abaixo). O núcleo de refresh diário
// (_shared/pricing-justtcg-refresh) tem seu PRÓPRIO teto por onda (também 30, mas um
// conceito de negócio distinto — "requisições desta onda agendada", não "requisições
// deste processo") passado via `requestBudget` no construtor; JustTcgClient sempre usa
// Math.min(requestBudget, MAX_REQUESTS_PER_RUN) — nenhum orçamento de onda jamais afrouxa
// o teto de segurança global.

import type {
  CallLogEntry,
  FetchLike,
  JustTcgMeta,
  JustTcgResult,
} from "./types.ts";
import { sanitize } from "./sanitize.ts";

// ============================================================================
// Constantes fixas do cliente — inalteradas desde P8/P14.1/P14.4.2.
// ============================================================================

export const JUSTTCG_API_BASE = "https://api.justtcg.com/v1";
export const REQUEST_TIMEOUT_MS = 15_000;
// Teto de segurança local do PROCESSO, independente do plano contratado (Starter:
// 10.000/mês, 1.000/dia, 50/min). A 3s de intervalo entre chamadas
// (DELAY_BETWEEN_REQUESTS_MS), o ritmo real fica em ~20/min — bem abaixo dos 50/min do
// plano.
export const MAX_REQUESTS_PER_RUN = 30;
export const DELAY_BETWEEN_REQUESTS_MS = 3_000;
export const RATE_LIMIT_BACKOFF_MS = 10_000;
// Máximo de cartas por página de GET /v1/cards no plano Starter/Pro contratado
// (https://justtcg.com/docs/api/cards, tabela "Max cards per request": Free=20,
// Starter=100, Pro=100, Enterprise=200).
export const CARDS_PAGE_LIMIT = 100;
export const GAME_CODE = "pokemon";

export class JustTcgClient {
  private requestCount = 0;
  readonly callLog: CallLogEntry[] = [];
  rateLimitHits = 0;
  private readonly fetchImpl: FetchLike;
  // Teto local autoritativo desta execução — quando informado (onda do CLI ou onda do
  // refresh diário), é o MENOR dos dois que vale (Math.min() nunca permite que um
  // orçamento de onda relaxe o teto de segurança global). budgetOk() nunca inicia uma
  // chamada que ultrapasse este valor: a checagem acontece ANTES de qualquer fetch.
  private readonly effectiveBudget: number;

  constructor(
    private readonly apiKey: string,
    fetchImpl?: FetchLike,
    requestBudget?: number,
  ) {
    this.fetchImpl = fetchImpl ?? fetch;
    this.effectiveBudget = typeof requestBudget === "number"
      ? Math.min(requestBudget, MAX_REQUESTS_PER_RUN)
      : MAX_REQUESTS_PER_RUN;
  }

  private budgetOk(): boolean {
    return this.requestCount < this.effectiveBudget;
  }

  async get<T>(
    endpoint: string,
    params: Record<string, string>,
  ): Promise<JustTcgResult<T>> {
    if (!this.budgetOk()) {
      this.callLog.push({
        sequence_number: this.callLog.length + 1,
        endpoint,
        http_status_code: null,
        outcome: "BUDGET_STOPPED",
        error_detail: `Teto local de ${this.effectiveBudget} requisições atingido.`,
        api_requests_remaining: null,
      });
      return { status: "BUDGET_STOPPED" };
    }

    if (this.requestCount > 0) {
      await new Promise((r) => setTimeout(r, DELAY_BETWEEN_REQUESTS_MS));
    }

    const query = new URLSearchParams(params).toString();
    const url = `${JUSTTCG_API_BASE}${endpoint}${query ? `?${query}` : ""}`;

    const attempt = async (): Promise<{ res: Response | null; err: string | null }> => {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
      try {
        const res = await this.fetchImpl(url, {
          method: "GET",
          headers: { "x-api-key": this.apiKey, Accept: "application/json" },
          signal: controller.signal,
        });
        return { res, err: null };
      } catch (error) {
        const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
        return { res: null, err: sanitize(message) };
      } finally {
        clearTimeout(timeout);
      }
    };

    this.requestCount++;
    const seq = this.callLog.length + 1;
    let { res, err } = await attempt();

    if (res?.status === 401) {
      const body = sanitize(await res.text().catch(() => ""));
      this.callLog.push({
        sequence_number: seq,
        endpoint,
        http_status_code: 401,
        outcome: "TECHNICAL_FAILURE",
        error_detail: `401 Unauthorized: ${body}`,
        api_requests_remaining: null,
      });
      return { status: "AUTH_FAILURE" };
    }

    if (res?.status === 429) {
      this.rateLimitHits++;
      await new Promise((r) => setTimeout(r, RATE_LIMIT_BACKOFF_MS));
      if (!this.budgetOk()) {
        this.callLog.push({
          sequence_number: seq,
          endpoint,
          http_status_code: 429,
          outcome: "BUDGET_STOPPED",
          error_detail: "429 seguido de orçamento esgotado antes do retry.",
          api_requests_remaining: null,
        });
        return { status: "BUDGET_STOPPED" };
      }
      this.requestCount++;
      ({ res, err } = await attempt());
    }

    if (!res) {
      this.callLog.push({
        sequence_number: seq,
        endpoint,
        http_status_code: null,
        outcome: "TECHNICAL_FAILURE",
        error_detail: err ?? "FALHA_DE_CONEXAO",
        api_requests_remaining: null,
      });
      return {
        status: "TECHNICAL_FAILURE",
        httpStatus: null,
        errorDetail: err ?? "FALHA_DE_CONEXAO",
      };
    }

    if (!res.ok) {
      const body = sanitize(await res.text().catch(() => "")) ?? "";
      this.callLog.push({
        sequence_number: seq,
        endpoint,
        http_status_code: res.status,
        outcome: "TECHNICAL_FAILURE",
        error_detail: `HTTP ${res.status}: ${body}`,
        api_requests_remaining: null,
      });
      return {
        status: "TECHNICAL_FAILURE",
        httpStatus: res.status,
        errorDetail: `HTTP ${res.status}: ${body}`,
      };
    }

    const json = await res.json();
    // apiRequestsRemaining é gravado exatamente como recebido, sem transformação — nunca
    // tratado como saldo monotônico ou autoritativo (achado P14.1: a metadata da JustTCG
    // pode repetir o mesmo valor por várias chamadas reais e distintas).
    const apiRequestsRemaining = json?._metadata?.apiRequestsRemaining ?? null;
    const meta: JustTcgMeta = json?.meta ?? null;
    this.callLog.push({
      sequence_number: seq,
      endpoint,
      http_status_code: res.status,
      outcome: "SUCCESS",
      error_detail: null,
      api_requests_remaining: apiRequestsRemaining,
    });
    return {
      status: "SUCCESS",
      data: json as T,
      meta,
      httpStatus: res.status,
      apiRequestsRemaining,
    };
  }

  get requestsMade(): number {
    return this.requestCount;
  }

  // Saldo local autoritativo restante — usado só para relatório/resumo (nunca para
  // decidir se uma chamada pode prosseguir; isso é budgetOk(), interno).
  get requestsRemainingLocal(): number {
    return Math.max(0, this.effectiveBudget - this.requestCount);
  }
}
