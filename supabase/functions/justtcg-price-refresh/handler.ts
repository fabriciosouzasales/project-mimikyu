// Project Mimikyu — supabase/functions/justtcg-price-refresh/handler.ts
// Handler puro e totalmente testável da Edge Function justtcg-price-refresh —
// Incremento de Atualização Diária JustTCG (2026-08-21), item C.
//
// Mesma disciplina de dependency injection de supabase/functions/ptax-fx-refresh/
// handler.ts e do núcleo compartilhado (core.ts): nenhum Deno.env, nenhum fetch global
// direto, nenhum SupabaseClient concreto criado aqui dentro — tudo já resolvido pelo
// chamador (index.ts) e injetado via HandlerDeps. Isso torna
// handleJusttcgPriceRefreshRequest() executável em qualquer runtime com Request/Response
// nativos (Deno real ou Node >=18, usado neste projeto só para validação offline).
//
// Ordem de execução (contrato desta rodada, itens C do pedido de Fabrício):
//   1. Método — só POST.
//   2. Autenticação — segredo dedicado via header apikey, ANTES de qualquer acesso a
//      banco, corpo da requisição ou rede (JustTCG). Ver auth.ts.
//   3. Parâmetro waveNumber — único campo aceito no corpo, restrito a 1-30 (elevado de
//      1-10 nesta rodada — 2026-08-21, correção pós-incidente: WAVE_PAGE_CAP caiu de 30
//      para 10 e MAX_WAVES subiu de 10 para 30, mantendo o mesmo teto diário de 300
//      páginas, para que cada execução fique bem abaixo do deadline interno de 110s). Fora
//      do intervalo ou ausente/inválido -> 400, sem tocar banco/rede (mesma disciplina do
//      passo 2: validação de forma ANTES de qualquer efeito colateral).
//   4. executePriceRefreshWave() do núcleo compartilhado (core.ts) — toda a decisão de
//      NOOP sem run / capacidade excedida / conflito de concorrência / abertura de um
//      único PRICE_REFRESH por onda / telemetria antes da finalização já vive lá; este
//      handler só traduz o resultado em HTTP.
//   5. Resposta JSON mínima e sanitizada — nunca credencial, URL interna, ou detalhe cru
//      de erro (o texto sanitizado vai só para pricing_sync_run.error_summary via
//      core.ts, não para a resposta HTTP).

import {
  executePriceRefreshWave,
  type WaveExecutionResult,
} from "../_shared/pricing-justtcg-refresh/core.ts";
import type { PriceRefreshRunPort } from "../_shared/pricing-justtcg-refresh/run-lifecycle.ts";
import {
  MAX_CAPACITY_PAGES,
  MAX_WAVES,
} from "../_shared/pricing-justtcg-refresh/wave-plan.ts";
import type { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { extractProvidedSecret, isAuthorized } from "./auth.ts";

const MIN_WAVE_NUMBER = 1;
const MAX_WAVE_NUMBER = 30;

// Logger sanitizado e injetável (correção pontual, 2026-08-21 — item de segurança
// levantado pelos próprios testes offline: o catch final abaixo registrava o `Error` cru
// via `console.error(error)`, que em Function Logs do Supabase é texto plano legível por
// qualquer operador com acesso aos logs, mesmo sem acesso à resposta HTTP). Contrato:
// NUNCA recebe o objeto de erro, `error.message` ou `error.stack` — só um código fixo
// (nunca interpolado a partir do erro) e um contexto operacional já sabidamente seguro
// (ex.: waveNumber, que já é ecoado sem problema na própria resposta HTTP). O chamador
// (index.ts) pode injetar um logger diferente; testes injetam um logger-espião para
// provar, por asserção, que nenhum detalhe sensível chega aqui — nunca por captura global
// de console (mais frágil: um logger tipado é verificável em nível de assinatura).
export type SanitizedLogger = (
  code: string,
  context?: Readonly<Record<string, unknown>>,
) => void;

// Exportado (2026-08-21, 2ª rodada) para reuso por pricing-source-lookup.ts — mesmo
// default seguro, agora compartilhado entre os dois pontos desta Edge Function que
// registram falha sem vazar detalhe cru (o catch final acima e a resolução de
// pricing_source_id em index.ts/pricing-source-lookup.ts).
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
  port: PriceRefreshRunPort;
  pricingSourceId: string | null;
  // Fábrica do cliente JustTCG — chamada NO MÁXIMO uma vez por requisição, só depois de
  // método/auth/waveNumber já validados (nunca antes: evita construir um cliente
  // autenticado à toa em uma requisição malformada). Cada requisição recebe um cliente
  // novo (callLog/requestCount começam zerados) — mesmo precedente de client.ts.
  buildClient: () => JustTcgClient;
  // Opcional — default seguro (defaultSanitizedLogger acima) quando o chamador não injeta
  // nada. Nunca um parâmetro obrigatório: index.ts não precisa saber deste detalhe para
  // funcionar corretamente, só os testes precisam injetá-lo para inspecionar o que foi
  // logado sem depender de captura global de console.
  logError?: SanitizedLogger;
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  extraHeaders?: Record<string, string>,
): Response {
  return Response.json(body, { status, headers: extraHeaders });
}

// Corpo aceito por esta função: SOMENTE { waveNumber: number } (regra E — "payload
// contém somente waveNumber"). Qualquer outro campo é ignorado silenciosamente (nunca um
// erro — não há necessidade de rejeitar campos extras que o Cron nunca enviará).
function parseWaveNumber(raw: unknown): number | null {
  if (
    typeof raw !== "object" || raw === null || Array.isArray(raw) ||
    !("waveNumber" in (raw as Record<string, unknown>))
  ) {
    return null;
  }
  const value = (raw as Record<string, unknown>).waveNumber;
  if (typeof value !== "number" || !Number.isInteger(value)) return null;
  if (value < MIN_WAVE_NUMBER || value > MAX_WAVE_NUMBER) return null;
  return value;
}

export async function handleJusttcgPriceRefreshRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const logError = deps.logError ?? defaultSanitizedLogger;

  // 1. Método — antes de qualquer outra coisa (nem sequer lê headers de auth).
  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, error: "METHOD_NOT_ALLOWED" },
      405,
      { Allow: "POST" },
    );
  }

  // 2. Autenticação — segredo dedicado, comparação em tempo constante. Acontece ANTES de
  // qualquer acesso a banco/corpo/JustTCG (requisito explícito de item C: "autenticação
  // antes de banco/rede").
  const providedSecret = extractProvidedSecret(req);
  if (!isAuthorized(providedSecret, deps.expectedSecret)) {
    return jsonResponse({ success: false, error: "UNAUTHORIZED" }, 401);
  }

  // 3. Configuração do servidor — pricing_source_id resolvido pelo chamador (index.ts).
  // Ausente aqui significa fonte JUSTTCG não encontrada/mal configurada — nunca um erro
  // do lado do chamador HTTP.
  if (!deps.pricingSourceId) {
    console.error(
      "JUSTTCG_PRICE_REFRESH: pricing_source_id ausente — fonte JUSTTCG não encontrada ou não resolvida pelo adapter.",
    );
    return jsonResponse({ success: false, error: "SERVER_MISCONFIGURED" }, 500);
  }

  // 4. Parâmetro waveNumber — único campo aceito, restrito a 1-10 (elevado de 1-5 nesta
  // rodada de escalabilidade, 2026-08-21). Corpo ausente/malformado ou fora do intervalo
  // -> 400, sem qualquer efeito colateral (banco/rede) até aqui.
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, error: "INVALID_JSON_BODY" }, 400);
  }
  const waveNumber = parseWaveNumber(body);
  if (waveNumber === null) {
    return jsonResponse(
      {
        success: false,
        error: "INVALID_WAVE_NUMBER",
        detail: "waveNumber deve ser um inteiro entre 1 e 30.",
      },
      400,
    );
  }

  try {
    // 5. Núcleo compartilhado — toda a decisão de negócio (plano, NOOP, capacidade,
    // concorrência, abertura/finalização do run, telemetria) vive em core.ts. O cliente
    // JustTCG só é construído agora, depois de toda validação de forma.
    const client = deps.buildClient();
    const result: WaveExecutionResult = await executePriceRefreshWave(
      deps.port,
      client,
      deps.pricingSourceId,
      waveNumber,
    );

    switch (result.kind) {
      case "NOOP_WAVE_NOT_IN_PLAN":
        // Regra 6 — onda fora do plano atual (ex.: onda 5 com só 4 ondas calculadas)
        // nunca cria pricing_sync_run. Resposta 200 informativa, nunca um erro (é o
        // comportamento esperado do desenho, não uma falha).
        return jsonResponse(
          {
            success: true,
            outcome: "NOOP_WAVE_NOT_IN_PLAN",
            waveNumber,
            planWaveCount: result.planWaveCount,
            totalEstimatedPages: result.totalEstimatedPages,
          },
          200,
        );

      case "CAPACITY_EXCEEDED":
        // Regra 7 — nenhuma onda escreve; "sem omissão silenciosa" (Fabrício): registrado
        // via log estruturado do lado da Edge Function (visível em Function Logs) além da
        // resposta HTTP, já que core.ts deliberadamente não cria pricing_sync_run neste
        // caso (nenhuma onda tem trabalho a fazer).
        console.error(
          `JUSTTCG_PRICE_REFRESH: SCHEDULE_CAPACITY_EXCEEDED — totalEstimatedPages=${result.totalEstimatedPages} totalSets=${result.totalSets} (teto=${MAX_CAPACITY_PAGES} páginas/${MAX_WAVES} ondas).`,
        );
        return jsonResponse(
          {
            success: true,
            outcome: "SCHEDULE_CAPACITY_EXCEEDED",
            waveNumber,
            totalEstimatedPages: result.totalEstimatedPages,
            totalSets: result.totalSets,
          },
          200,
        );

      case "CONCURRENT_CONFLICT":
        // 409 — CARD_SYNC ou PRICE_REFRESH já ativo para a fonte (regra 9). Nunca chega a
        // tocar a rede da JustTCG.
        return jsonResponse(
          { success: false, error: "CONCURRENT_SYNC_RUN_ACTIVE", waveNumber },
          409,
        );

      case "START_FAILED":
        return jsonResponse(
          { success: false, error: "SYNC_RUN_START_FAILED", waveNumber },
          500,
        );

      case "EXECUTED": {
        const httpStatus = result.status === "FAILED" ? 500 : 200;
        return jsonResponse(
          {
            success: result.status !== "FAILED",
            outcome: "EXECUTED",
            status: result.status,
            waveNumber,
            syncRunId: result.syncRunId,
            setsProcessed: result.setsProcessed,
            identitiesConsidered: result.identitiesConsidered,
            productsInserted: result.productsInserted,
            observationsWritten: result.observationsWritten,
            observationsSkippedSamePrice: result.observationsSkippedSamePrice,
            requestsMade: result.requestsMade,
          },
          httpStatus,
        );
      }
    }
  } catch {
    // Defesa em profundidade — qualquer exceção não prevista (ex.: uma leitura do port
    // lançando por falha de rede/DB fora do fluxo já tratado em core.ts). `catch` SEM
    // binding (nenhum `(error)`) é deliberado: a variável do erro nem existe neste escopo,
    // então é estruturalmente impossível — não só uma convenção — repassar o `Error` cru,
    // `error.message` ou `error.stack` para o logger ou para a resposta HTTP a partir
    // daqui. Só um código fixo e o waveNumber (já validado e já ecoado sem problema em
    // outras respostas desta função) chegam ao logger.
    logError("JUSTTCG_PRICE_REFRESH_INTERNAL_ERROR", { waveNumber });
    return jsonResponse({ success: false, error: "INTERNAL_ERROR" }, 500);
  }
}
