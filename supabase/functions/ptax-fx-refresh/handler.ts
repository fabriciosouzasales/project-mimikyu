// Project Mimikyu — supabase/functions/ptax-fx-refresh/handler.ts
// Handler puro e totalmente testável da Edge Function ptax-fx-refresh — Incremento
// P13.3 (2026-08-18).
//
// Toda a lógica de requisição/resposta mora aqui, como uma função pura que recebe o
// Request real e um objeto de dependências já resolvido pelo chamador (index.ts) —
// mesma disciplina de dependency injection do núcleo compartilhado (core.ts): nenhum
// Deno.env, nenhum fetch global direto, nenhum cliente Supabase concreto criado aqui
// dentro. Isso torna handlePtaxFxRefreshRequest() executável em qualquer runtime com
// Request/Response nativos (Deno real ou Node >=18, usado neste projeto só para
// validação offline no sandbox de desenvolvimento — nunca em produção).
//
// Ordem de execução (contrato desta rodada):
//   1. Método — só POST.
//   2. Autenticação — segredo dedicado via header apikey, ANTES de qualquer acesso a
//      banco, corpo da requisição ou rede (BCB). Ver auth.ts.
//   3. tryStartSyncRun (triggered_by=SCHEDULED, confirmed_by=NULL) — 409 em conflito de
//      concorrência (23505), sempre ANTES de qualquer chamada ao BCB.
//   4. runPtaxSync() do núcleo compartilhado — uma única chamada ao BCB por execução.
//   5. persistCallLog ANTES de finalizeSyncRun, em qualquer desfecho.
//   6. Resposta JSON mínima e sanitizada — nunca credencial, URL interna, ou detalhe
//      cru de erro (o texto sanitizado vai só para pricing_sync_run.error_summary, não
//      para a resposta HTTP).

import {
  buildErrorSummary,
  computeReferenceDateSaoPaulo,
  decideFinalStatus,
  finalizeSyncRun,
  persistCallLog,
  runPtaxSync,
  tryStartSyncRun,
} from "../_shared/pricing-ptax/mod.ts";
import type {
  FetchLike,
  PtaxSyncRunPort,
  WaitLike,
} from "../_shared/pricing-ptax/mod.ts";
import { extractProvidedSecret, isAuthorized } from "./auth.ts";

const REQUEST_TIMEOUT_MS = 15_000;

export interface HandlerDeps {
  expectedSecret: string | null;
  port: PtaxSyncRunPort;
  fetchImpl: FetchLike;
  waitImpl: WaitLike;
  now: Date;
  timeoutMs?: number;
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  extraHeaders?: Record<string, string>,
): Response {
  return Response.json(body, { status, headers: extraHeaders });
}

export async function handlePtaxFxRefreshRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  // 1. Método — antes de qualquer outra coisa (nem sequer lê headers de auth).
  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, error: "METHOD_NOT_ALLOWED" },
      405,
      { Allow: "POST" },
    );
  }

  // 2. Autenticação — segredo dedicado, comparação em tempo constante. Acontece ANTES
  // de qualquer acesso a banco/corpo/BCB (requisito explícito desta rodada). Esta
  // função nunca processa o corpo da requisição — não há parâmetro de entrada
  // configurável via HTTP para uma execução agendada (SCHEDULED), então não há corpo a
  // interpretar em nenhum caminho de código.
  const providedSecret = extractProvidedSecret(req);
  if (!isAuthorized(providedSecret, deps.expectedSecret)) {
    return jsonResponse({ success: false, error: "UNAUTHORIZED" }, 401);
  }

  let syncRunId: string | null = null;
  let syncRunFinalized = false;

  try {
    // 3. Abertura do run — SEMPRE triggered_by=SCHEDULED, confirmed_by=NULL nesta
    // Edge Function (nunca um admin humano por trás da chamada agendada). Único efeito
    // colateral ANTES do BCB — mesmo precedente do adapter manual (P13.2).
    const startAttempt = await tryStartSyncRun(deps.port, {
      triggeredBy: "SCHEDULED",
    });

    if (startAttempt.status === "CONCURRENT_CONFLICT") {
      // 409 — concorrência detectada via índice único parcial (Query 3907). Nunca
      // chega a tocar a rede do BCB.
      return jsonResponse(
        { success: false, error: "CONCURRENT_SYNC_RUN_ACTIVE" },
        409,
      );
    }
    if (startAttempt.status === "OTHER_ERROR") {
      return jsonResponse(
        { success: false, error: "SYNC_RUN_START_FAILED" },
        500,
      );
    }
    syncRunId = startAttempt.syncRunId;

    // 4. Núcleo compartilhado — mesma função runPtaxSync() do adapter manual, mesmo
    // contrato: uma única chamada ao BCB (com retry interno) para o período completo.
    const referenceDate = computeReferenceDateSaoPaulo(deps.now);
    const result = await runPtaxSync({
      referenceDate,
      fetchImpl: deps.fetchImpl,
      waitImpl: deps.waitImpl,
      repository: deps.port, // PtaxSyncRunPort estende PtaxRateRepository
      dryRun: false, // execução agendada real — nunca dry-run (não existe --dry-run via HTTP)
      timeoutMs: deps.timeoutMs ?? REQUEST_TIMEOUT_MS,
    });

    // 5. Telemetria ANTES da finalização — mesma disciplina do adapter (Query 3909).
    const callPersist = await persistCallLog(
      deps.port,
      syncRunId,
      result.callLog,
    );
    const rateLimitHits = result.callLog.filter((c) =>
      c.httpStatusCode === 429
    ).length;

    if (!callPersist.ok) {
      // Falha ao persistir calls nunca pode terminar como COMPLETED — finaliza como
      // FAILED. O detalhe sanitizado vai só para error_summary (banco), nunca para a
      // resposta HTTP.
      await finalizeSyncRun(
        deps.port,
        syncRunId,
        "FAILED",
        `PRICING_SYNC_RUN_CALL_INSERT_FAILED: ${callPersist.detail}`,
        result.callLog.length,
        rateLimitHits,
        false,
      );
      syncRunFinalized = true;
      return jsonResponse(
        { success: false, status: "FAILED", error: "CALL_LOG_PERSIST_FAILED" },
        500,
      );
    }

    const status = decideFinalStatus(result);
    const errorSummary = buildErrorSummary(result);
    await finalizeSyncRun(
      deps.port,
      syncRunId,
      status,
      errorSummary,
      result.callLog.length,
      rateLimitHits,
      false,
    );
    syncRunFinalized = true;

    // 6. Resposta — mínima e sanitizada. Falha técnica/funcional do núcleo finaliza o
    // run como FAILED (já feito acima via decideFinalStatus) e responde com um código
    // de erro fixo, nunca o texto cru de result.detail.
    if (
      result.kind === "TECHNICAL_FAILURE" ||
      result.kind === "FUNCTIONAL_FAILURE"
    ) {
      return jsonResponse(
        { success: false, status, syncRunId, error: "SYNC_EXECUTION_FAILED" },
        500,
      );
    }

    // COMPLETED ou COMPLETED_WITH_ERRORS (divergência/inválido) — ambos são uma
    // execução HTTP bem-sucedida (dado real processado); a distinção fica só no campo
    // `status`, nunca no código HTTP.
    return jsonResponse(
      {
        success: true,
        status,
        syncRunId,
        period: result.period,
        quotesReceived: result.quotesReceived,
        counts: result.counts,
      },
      200,
    );
  } catch (error) {
    // Defesa em profundidade — qualquer exceção não prevista (ex.: repository.insertRate
    // lançando por falha de rede/DB dentro de persistPtaxRates) finaliza o run como
    // FAILED, se ainda não finalizado, e nunca expõe error.message na resposta HTTP.
    if (syncRunId && !syncRunFinalized) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(
        deps.port,
        syncRunId,
        "FAILED",
        message,
        0,
        0,
        false,
      );
    }
    console.error(error);
    return jsonResponse({ success: false, error: "INTERNAL_ERROR" }, 500);
  }
}
