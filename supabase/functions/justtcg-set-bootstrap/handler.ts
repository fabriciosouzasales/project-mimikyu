// Project Mimikyu — supabase/functions/justtcg-set-bootstrap/handler.ts
// Handler puro e testável do dispatcher de bootstrap de Set (CARD_SYNC, P16.5.4,
// 2026-08-26) — consome executeBootstrapAttempt() (_shared/pricing-justtcg-bootstrap/
// bootstrap-core.ts, já testado offline em P16.5.2/P16.5.3), que decide inteiramente QUAL
// Set processar (via a RPC open_pricing_set_bootstrap_attempt, migration 3955) — este
// handler nunca aceita nem interpreta nenhum parâmetro de Set/wave no corpo da requisição.
//
// Mesma disciplina de dependency injection de justtcg-price-refresh-set/handler.ts: nenhum
// Deno.env, nenhum fetch global direto, nenhum SupabaseClient concreto criado aqui — tudo
// resolvido pelo chamador (index.ts) e injetado via HandlerDeps. Nenhuma lógica de matching
// duplicada aqui — buildExternalNumberIndex/classifyCardMatch/decideMappingUpsert vivem
// exclusivamente em bootstrap-core.ts/pricing-justtcg-matching (reuso integral).
//
// Ordem de execução:
//   1. Método — só POST.
//   2. Autenticação — segredo dedicado via header apikey, ANTES de qualquer acesso a
//      banco/rede.
//   3. pricing_source_id — resolvido pelo chamador (index.ts); ausente = fonte JUSTTCG não
//      encontrada/mal configurada, nunca um erro do lado do chamador HTTP.
//   4. executeBootstrapAttempt() do núcleo compartilhado — toda a decisão de negócio
//      (NO_CANDIDATE/SOURCE_BUSY/lease perdida/aquisição paginada/matching) já vive lá;
//      este handler só traduz o resultado em HTTP.
//   5. Resposta JSON mínima e sanitizada — nunca credencial, URL interna, ou detalhe cru de
//      erro.

import {
  BOOTSTRAP_REQUEST_BUDGET,
  type BootstrapExecutionResult,
  executeBootstrapAttempt,
} from "../_shared/pricing-justtcg-bootstrap/bootstrap-core.ts";
import type { BootstrapPort } from "../_shared/pricing-justtcg-bootstrap/bootstrap-port.ts";
import type { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { extractProvidedSecret, isAuthorized } from "./auth.ts";

export type SanitizedLogger = (
  code: string,
  context?: Readonly<Record<string, unknown>>,
) => void;

export function defaultSanitizedLogger(
  code: string,
  context?: Readonly<Record<string, unknown>>,
): void {
  if (context && Object.keys(context).length > 0) {
    console.error(code, context);
  } else {
    console.error(code);
  }
}

export interface HandlerDeps {
  expectedSecret: string | null;
  port: BootstrapPort;
  pricingSourceId: string | null;
  // Fábrica do cliente JustTCG — chamada NO MÁXIMO uma vez por requisição, só depois de
  // método/auth/pricing_source_id já validados. Cada requisição recebe um cliente novo
  // (callLog/requestCount começam zerados). Nunca invocada quando status=MATCHING (prova
  // estrutural em bootstrap-core.ts: runMatchingPhase() nem recebe o client).
  buildClient: () => JustTcgClient;
  logError?: SanitizedLogger;
  // Relógio injetável — mesmo padrão de deadline.ts. Produção usa Date.now (default de
  // executeBootstrapAttempt); testes injetam um relógio determinístico.
  clock?: () => number;
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  extraHeaders?: Record<string, string>,
): Response {
  return Response.json(body, { status, headers: extraHeaders });
}

export async function handleJusttcgSetBootstrapRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const logError = deps.logError ?? defaultSanitizedLogger;

  // 1. Método.
  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, error: "METHOD_NOT_ALLOWED" },
      405,
      { Allow: "POST" },
    );
  }

  // 2. Autenticação — ANTES de qualquer acesso a banco/rede.
  const providedSecret = extractProvidedSecret(req);
  if (!isAuthorized(providedSecret, deps.expectedSecret)) {
    return jsonResponse({ success: false, error: "UNAUTHORIZED" }, 401);
  }

  // 3. pricing_source_id resolvido pelo chamador.
  if (!deps.pricingSourceId) {
    console.error(
      "JUSTTCG_SET_BOOTSTRAP: pricing_source_id ausente — fonte JUSTTCG não encontrada ou não resolvida pelo adapter.",
    );
    return jsonResponse({ success: false, error: "SERVER_MISCONFIGURED" }, 500);
  }

  // Corpo desta função é deliberadamente vazio de parâmetros de negócio — 1 Set por
  // invocação, decidido inteiramente pela RPC open_pricing_set_bootstrap_attempt. Um corpo
  // presente/malformado nunca é um erro (nada é lido dele).

  try {
    const client = deps.buildClient();
    const result: BootstrapExecutionResult = await executeBootstrapAttempt(
      deps.port,
      client,
      deps.pricingSourceId,
      deps.clock,
    );

    switch (result.kind) {
      case "NO_WORK":
        return jsonResponse({ success: true, outcome: "NO_WORK" }, 200);

      case "SOURCE_BUSY":
        // 409 — outro CARD_SYNC/PRICE_REFRESH já ativo para a fonte. Nunca chega a tocar a
        // rede da JustTCG.
        return jsonResponse(
          { success: false, error: "CONCURRENT_SYNC_RUN_ACTIVE" },
          409,
        );

      case "LEASE_LOST":
        // Defensivo — nunca esperado com 1 invocação por vez. 200 informativo (não é uma
        // falha deste chamador; o run em questão já foi reconciliado por outro processo).
        return jsonResponse(
          { success: true, outcome: "LEASE_LOST", syncRunId: result.syncRunId },
          200,
        );

      case "ACQUISITION_CLOSED": {
        const httpStatus = result.runStatus === "FAILED" ? 500 : 200;
        return jsonResponse(
          {
            success: result.runStatus !== "FAILED",
            outcome: "ACQUISITION_CLOSED",
            syncRunId: result.syncRunId,
            pricingSetMappingId: result.pricingSetMappingId,
            phaseOutcome: result.phaseOutcome,
            runStatus: result.runStatus,
            finalStatus: result.finalStatus,
            pagesProcessed: result.pagesProcessed,
            cardsStaged: result.cardsStaged,
            requestsMade: result.requestsMade,
            requestBudget: BOOTSTRAP_REQUEST_BUDGET,
            rateLimitHits: result.rateLimitHits,
          },
          httpStatus,
        );
      }

      case "MATCHING_CLOSED": {
        const httpStatus = result.runStatus === "FAILED" ? 500 : 200;
        return jsonResponse(
          {
            success: result.runStatus !== "FAILED",
            outcome: "MATCHING_CLOSED",
            syncRunId: result.syncRunId,
            pricingSetMappingId: result.pricingSetMappingId,
            phaseOutcome: result.phaseOutcome,
            runStatus: result.runStatus,
            finalStatus: result.finalStatus,
            cardsTotal: result.cardsTotal,
            cardsSafe: result.cardsSafe,
            cardsAmbiguous: result.cardsAmbiguous,
            cardsAbsent: result.cardsAbsent,
            mappingsInserted: result.mappingsInserted,
            mappingsUpgraded: result.mappingsUpgraded,
            mappingsNoop: result.mappingsNoop,
            identitiesCreated: result.identitiesCreated,
          },
          httpStatus,
        );
      }
    }
  } catch {
    // Defesa em profundidade — `catch` SEM binding é deliberado (mesma disciplina de
    // justtcg-price-refresh-set/handler.ts): estruturalmente impossível repassar o Error
    // cru, error.message ou error.stack para o logger ou para a resposta HTTP a partir
    // daqui.
    logError("JUSTTCG_SET_BOOTSTRAP_INTERNAL_ERROR");
    return jsonResponse({ success: false, error: "INTERNAL_ERROR" }, 500);
  }
}
