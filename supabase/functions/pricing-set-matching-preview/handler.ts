// Project Mimikyu — supabase/functions/pricing-set-matching-preview/handler.ts
// Handler puro e testável do preview de correspondência de Set (P16.3). Mesma disciplina de
// dependency injection já usada em justtcg-price-refresh-set/handler.ts: nenhum Deno.env,
// nenhum fetch global direto, nenhum SupabaseClient concreto criado aqui — tudo resolvido
// pelo chamador (index.ts) e injetado via HandlerDeps. `verifyAdmin` é injetável de propósito
// (Seção 16 do pedido: testes offline precisam simular "auth não admin" sem depender de um
// GoTrue real).
//
// Ordem de execução:
//   1. Método — só POST.
//   2. Autenticação — JWT + is_admin, ANTES de qualquer acesso a banco/rede (mesma fronteira
//      de import-card-variants/index.ts, aqui isolada em HandlerDeps.verifyAdmin para ser
//      testável).
//   3. Corpo — { card_set_id: string }, validado ANTES de qualquer leitura.
//   4. previewSetMatching() do núcleo (core.ts) — toda a decisão de negócio já vive lá; este
//      handler só traduz o resultado em HTTP.
//   5. Resposta JSON mínima e sanitizada — nunca credencial, URL interna, ou detalhe cru de
//      erro (Seção 12: NOT_FOUND nunca é tratado como erro técnico; falhas técnicas reais
//      nunca vazam detalhe interno para o chamador).

import type { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { previewSetMatching } from "./core.ts";
import type { SetMatchingPreviewPort } from "./port.ts";
import type { PreviewResult } from "./types.ts";

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

export type AdminVerification =
  | { ok: true; userId: string }
  | { ok: false; status: number; error: string };

export interface HandlerDeps {
  // Resolve identidade + papel admin a partir da própria Request (cabeçalho Authorization).
  // Produção: auth.getUser() + rpc('is_admin') com o JWT do chamador (mesmo padrão de
  // import-card-variants/index.ts). Testes: função fake determinística.
  verifyAdmin: (req: Request) => Promise<AdminVerification>;
  port: SetMatchingPreviewPort;
  // Fábrica do cliente JustTCG — chamada no máximo uma vez por requisição, só depois de
  // método/auth/corpo já validados (mesmo padrão de HandlerDeps.buildClient em
  // justtcg-price-refresh-set/handler.ts).
  buildClient: () => JustTcgClient;
  logError?: SanitizedLogger;
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return Response.json(body, { status });
}

function respondForResult(result: PreviewResult, logError: SanitizedLogger): Response {
  switch (result.kind) {
    case "SET_NOT_FOUND":
      return jsonResponse({ success: false, error: "SET_NOT_FOUND" }, 404);

    case "SET_NOT_ELIGIBLE":
      return jsonResponse({ success: true, state: "SET_NOT_ELIGIBLE" }, 200);

    case "NO_ACTIVE_SOURCE":
      return jsonResponse({ success: true, state: "NO_ACTIVE_SOURCE" }, 200);

    case "ALREADY_CONFIRMED":
      return jsonResponse(
        {
          success: true,
          state: "ALREADY_CONFIRMED",
          local: result.local,
          external_set_id: result.external_set_id,
          external_set_name: result.external_set_name,
          last_checked_at: result.last_checked_at,
        },
        200,
      );

    case "SAFE_CANDIDATE":
      return jsonResponse(
        { success: true, state: "SAFE_CANDIDATE", local: result.local, candidate: result.candidate },
        200,
      );

    case "AMBIGUOUS":
      return jsonResponse(
        {
          success: true,
          state: "AMBIGUOUS",
          local: result.local,
          candidates: result.candidates,
          evidence: result.evidence,
        },
        200,
      );

    case "NOT_FOUND":
      return jsonResponse(
        { success: true, state: "NOT_FOUND", local: result.local, evidence: result.evidence },
        200,
      );

    case "JUSTTCG_AUTH_FAILURE":
      logError("PRICING_SET_MATCHING_PREVIEW_JUSTTCG_AUTH_FAILURE");
      return jsonResponse({ success: false, error: "JUSTTCG_AUTH_FAILURE" }, 502);

    case "JUSTTCG_BUDGET_STOPPED":
      logError("PRICING_SET_MATCHING_PREVIEW_JUSTTCG_BUDGET_STOPPED");
      return jsonResponse({ success: false, error: "JUSTTCG_BUDGET_STOPPED" }, 503);

    case "JUSTTCG_TECHNICAL_FAILURE":
      // `detail` nunca chega à resposta HTTP — só ao log sanitizado (código fixo + booleano),
      // mesma disciplina de justtcg-price-refresh-set/pricing-source-lookup.ts.
      logError("PRICING_SET_MATCHING_PREVIEW_JUSTTCG_TECHNICAL_FAILURE", { hadDetail: Boolean(result.detail) });
      return jsonResponse({ success: false, error: "JUSTTCG_TECHNICAL_FAILURE" }, 502);
  }
}

export async function handlePricingSetMatchingPreviewRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const logError = deps.logError ?? defaultSanitizedLogger;

  // 1. Método.
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "METHOD_NOT_ALLOWED" }, 405);
  }

  // 2. Autenticação — ANTES de qualquer acesso a banco/rede.
  const admin = await deps.verifyAdmin(req);
  if (!admin.ok) {
    return jsonResponse({ success: false, error: admin.error }, admin.status);
  }

  // 3. Corpo — { card_set_id } é o ÚNICO parâmetro de negócio aceito (Seção 4 do pedido:
  // "o servidor resolve nome/código/release_date/jogo/fonte aplicável por conta própria —
  // nunca confia em nome/código enviados pelo frontend como fonte de verdade").
  let body: { card_set_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, error: "INVALID_JSON" }, 400);
  }

  const cardSetId = typeof body.card_set_id === "string" ? body.card_set_id.trim() : "";
  if (!cardSetId) {
    return jsonResponse({ success: false, error: "CARD_SET_ID_REQUIRED" }, 400);
  }

  try {
    const client = deps.buildClient();
    const result = await previewSetMatching(deps.port, client, cardSetId);
    return respondForResult(result, logError);
  } catch {
    // Defesa em profundidade — `catch` sem binding é deliberado (mesma disciplina de
    // justtcg-price-refresh-set/handler.ts): estruturalmente impossível repassar o Error cru
    // para o logger ou para a resposta HTTP a partir daqui.
    logError("PRICING_SET_MATCHING_PREVIEW_INTERNAL_ERROR");
    return jsonResponse({ success: false, error: "INTERNAL_ERROR" }, 500);
  }
}
