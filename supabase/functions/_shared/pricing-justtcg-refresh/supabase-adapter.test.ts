// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/supabase-adapter.test.ts
// Bateria de testes offline de buildPricingJustTcgRefreshSupabaseAdapter() — correção de
// segurança (2026-08-21, 3ª rodada, "gate local", item A): as 13 ocorrências de
// error.message cru (9 throws de leitura + 4 returns de escrita) foram substituídas por
// códigos fixos e distintos por operação. Este arquivo prova, com um erro PostgREST
// simulado contendo uma sentinela sensível, que essa sentinela nunca escapa para o valor
// retornado/lançado por nenhuma operação do adapter.
//
// 100% offline: `supabase` é sempre um fake mínimo neste arquivo (thenable + chainable,
// reproduzindo só o suficiente da API fluente do PostgREST para os call sites reais do
// adapter) — nenhum SupabaseClient real, nenhuma chamada de rede. Este arquivo era,
// deliberadamente, o único módulo do núcleo sem cobertura de teste até esta rodada (ver
// cabeçalho de supabase-adapter.ts) — Fabrício pediu explicitamente para cobri-lo agora.

import {
  buildPricingJustTcgRefreshSupabaseAdapter,
  type SanitizedLogger,
} from "./supabase-adapter.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

const SENTINEL = "FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR";
const PRICING_SOURCE_ID = "fake-pricing-source-justtcg";

// ----------------------------------------------------------------------------
// Fake mínimo do SupabaseClient — thenable E chainable simultaneamente (mesmo
// comportamento estrutural dos builders reais do supabase-js: `await` funciona em
// qualquer ponto da cadeia). Cada método intermediário devolve a própria cadeia; `then()`
// resolve sempre para o `result` configurado, independente de quantos métodos foram
// encadeados antes do `await`. Um fake por chamada de `.from()`/`.rpc()`, indexado por
// tabela/nome de RPC — suficiente porque cada cenário deste arquivo aciona no máximo um
// chunk (dados de teste pequenos, nunca >CHUNK_SIZE=200).
// ----------------------------------------------------------------------------

interface FakeResult {
  data: unknown;
  error: unknown;
}

function buildQueryChain(result: FakeResult): Record<string, unknown> {
  // deno-lint-ignore no-explicit-any
  const chain: any = {
    select: () => chain,
    eq: () => chain,
    in: () => chain,
    order: () => chain,
    range: () => chain,
    insert: () => chain,
    update: () => chain,
    single: () => chain,
    then: (
      onFulfilled: (r: FakeResult) => unknown,
      onRejected?: (e: unknown) => unknown,
    ) => Promise.resolve(result).then(onFulfilled, onRejected),
  };
  return chain;
}

function buildFakeSupabase(
  tableResults: Readonly<Record<string, FakeResult>>,
  rpcResults: Readonly<Record<string, FakeResult>> = {},
): SupabaseClient {
  const fake = {
    from(table: string) {
      const result = tableResults[table];
      if (!result) {
        throw new Error(
          `buildFakeSupabase: nenhuma resposta configurada para a tabela "${table}" (bug do teste, nunca do adapter)`,
        );
      }
      return buildQueryChain(result);
    },
    rpc(name: string, _payload: unknown) {
      const result = rpcResults[name];
      if (!result) {
        throw new Error(
          `buildFakeSupabase: nenhuma resposta configurada para o RPC "${name}" (bug do teste, nunca do adapter)`,
        );
      }
      return buildQueryChain(result);
    },
  };
  return fake as unknown as SupabaseClient;
}

function ok(data: unknown): FakeResult {
  return { data, error: null };
}

// Erro PostgREST simulado, com a sentinela em TODOS os campos de texto livre que um erro
// real do Postgres poderia carregar — exatamente o que item 3 do pedido de Fabrício lista
// como proibido de persistir: message/details/hint (+ .stack via Object.assign abaixo, já
// que PostgrestError não tem stack nativamente, mas um Error genérico teria).
function sensitiveError(code = "42501"): FakeResult {
  return {
    data: null,
    error: {
      message: SENTINEL,
      details: SENTINEL,
      hint: SENTINEL,
      code,
      stack: `Error: ${SENTINEL}\n    at algumaFuncaoInterna (arquivo.ts:1:1)`,
    },
  };
}

interface LoggedCall {
  code: string;
  context?: Readonly<Record<string, unknown>>;
}

function buildLogSpy(): { logError: SanitizedLogger; calls: LoggedCall[] } {
  const calls: LoggedCall[] = [];
  const logError: SanitizedLogger = (code, context) => {
    calls.push({ code, context });
  };
  return { logError, calls };
}

// Nenhuma chamada deste arquivo alcança um catch(unknown)/JSON.stringify amplo — cada
// asserção verifica o valor exato (mensagem do throw, ou campo .message do retorno)
// contra a sentinela, nunca uma inspeção solta.
async function assertThrowsSanitized(
  assert: (label: string, cond: boolean) => void,
  label: string,
  expectedCode: string,
  action: () => Promise<unknown>,
): Promise<void> {
  let thrown: unknown = null;
  try {
    await action();
  } catch (e) {
    thrown = e;
  }
  assert(`${label}: lançou um Error`, thrown instanceof Error);
  const message = thrown instanceof Error ? thrown.message : "";
  assert(`${label}: mensagem é exatamente o código fixo esperado`, message === expectedCode);
  assert(
    `${label}: sentinela sensível NUNCA aparece na mensagem do Error lançado`,
    !message.includes(SENTINEL),
  );
}

export async function runSupabaseAdapterTests(): Promise<TestSuiteResult> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // ── 1. Falha de leitura simples — getConditionMap (pricing_condition_mapping) ──────
  {
    const supabase = buildFakeSupabase({
      pricing_condition_mapping: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    await assertThrowsSanitized(
      assert,
      "falha de leitura (getConditionMap)",
      "CONDITION_MAPPING_QUERY_FAILED",
      () => port.getConditionMap(PRICING_SOURCE_ID),
    );
  }

  // ── 2. Falha de leitura paginada — listConfirmedIdentitiesForSet (pricing_source_card_identity) ──
  {
    const supabase = buildFakeSupabase({
      pricing_source_card_identity: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    await assertThrowsSanitized(
      assert,
      "falha de leitura paginada (listConfirmedIdentitiesForSet)",
      "PRICING_SOURCE_CARD_IDENTITY_PAGINATED_QUERY_FAILED",
      () => port.listConfirmedIdentitiesForSet(PRICING_SOURCE_ID, "set-a"),
    );
  }

  // ── 3. Falha de leitura — findExistingProducts (pricing_product, SELECT) ───────────
  {
    const supabase = buildFakeSupabase({
      pricing_product: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    await assertThrowsSanitized(
      assert,
      "falha de leitura (findExistingProducts)",
      "PRODUCT_BATCH_SELECT_FAILED",
      () => port.findExistingProducts(["identity-1"]),
    );
  }

  // ── 4. Falha de leitura — findLatestObservations (RPC) ──────────────────────────────
  {
    const supabase = buildFakeSupabase({}, {
      batch_select_latest_pricing_observation_by_identity: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    await assertThrowsSanitized(
      assert,
      "falha de leitura (findLatestObservations, RPC)",
      "OBSERVATION_LATEST_BATCH_SELECT_FAILED",
      () =>
        port.findLatestObservations([
          { productId: "product-1", conditionId: "condition-1" },
        ]),
    );
  }

  // ── 5. Falha de produto — insertProducts (pricing_product, INSERT) ─────────────────
  {
    const supabase = buildFakeSupabase({
      pricing_product: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    const result = await port.insertProducts([
      {
        pricingCardMappingId: "mapping-1",
        pricingSourceCardIdentityId: "identity-1",
        externalProductId: "ext-product-1",
        sourcePrintingLabel: "Normal",
      },
    ]);
    assert("falha de produto: ok=false", result.ok === false);
    assert(
      "falha de produto: message é exatamente o código fixo esperado",
      !result.ok && result.message === "PRODUCT_INSERT_FAILED",
    );
    assert(
      "falha de produto: sentinela sensível NUNCA aparece em result.message",
      !result.ok && !(result.message ?? "").includes(SENTINEL),
    );
    assert(
      "falha de produto: sentinela sensível NUNCA aparece em result (varredura completa do objeto)",
      !JSON.stringify(result).includes(SENTINEL),
    );
  }

  // ── 6. Falha de observação — insertObservations (pricing_observation, INSERT) ──────
  {
    const supabase = buildFakeSupabase({
      pricing_observation: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    const result = await port.insertObservations([
      {
        productId: "product-1",
        conditionId: "condition-1",
        syncRunId: "sync-run-1",
        price: 4.2,
        observedAt: "2026-08-21T00:00:00.000Z",
        rawPayload: { qualquerCoisa: true },
      },
    ]);
    assert("falha de observação: ok=false", result.ok === false);
    assert(
      "falha de observação: message é exatamente o código fixo esperado",
      !result.ok && result.message === "OBSERVATION_INSERT_FAILED",
    );
    assert(
      "falha de observação: sentinela sensível NUNCA aparece em result.message",
      !result.ok && !(result.message ?? "").includes(SENTINEL),
    );
    assert(
      "falha de observação: sentinela sensível NUNCA aparece em result (varredura completa)",
      !JSON.stringify(result).includes(SENTINEL),
    );
  }

  // ── 7. Falha de início/abertura do run — insertPriceRefreshRun (não-23505) ──────────
  {
    const supabase = buildFakeSupabase({
      pricing_sync_run: sensitiveError("53300"), // "too_many_connections" — qualquer código != 23505
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    const result = await port.insertPriceRefreshRun(PRICING_SOURCE_ID);
    assert(
      "falha ao abrir run: outcome=OTHER_ERROR (nunca CONCURRENT_CONFLICT para código != 23505)",
      result.outcome === "OTHER_ERROR",
    );
    assert(
      "falha ao abrir run: message é exatamente o código fixo esperado",
      result.outcome === "OTHER_ERROR" && result.message === "SYNC_RUN_START_FAILED",
    );
    assert(
      "falha ao abrir run: sentinela sensível NUNCA aparece em result (varredura completa)",
      !JSON.stringify(result).includes(SENTINEL),
    );
  }

  // ── 7b. 23505 continua classificado como CONCURRENT_CONFLICT (comportamento preservado) ──
  {
    const supabase = buildFakeSupabase({
      pricing_sync_run: sensitiveError("23505"),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    const result = await port.insertPriceRefreshRun(PRICING_SOURCE_ID);
    assert(
      "23505: outcome=CONCURRENT_CONFLICT preservado (correção não alterou esta lógica)",
      result.outcome === "CONCURRENT_CONFLICT",
    );
    assert(
      "23505: nenhum campo message/detail no resultado (nunca haveria sentinela mesmo antes da correção)",
      !("message" in result),
    );
  }

  // ── 8. Falha de atualização/finalização — insertSyncRunCalls (telemetria, INSERT) ──
  {
    const supabase = buildFakeSupabase({
      pricing_sync_run_call: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    const result = await port.insertSyncRunCalls("sync-run-1", [{
      sequence_number: 1,
      endpoint: "https://api.justtcg.com/v1/cards",
      http_status_code: 200,
      outcome: "SUCCESS",
      error_detail: null,
      api_requests_remaining: 29,
    }]);
    assert("falha de telemetria de calls: ok=false", result.ok === false);
    assert(
      "falha de telemetria de calls: message é exatamente o código fixo esperado",
      !result.ok && result.message === "SYNC_RUN_CALL_INSERT_FAILED",
    );
    assert(
      "falha de telemetria de calls: sentinela sensível NUNCA aparece em result (varredura completa)",
      !JSON.stringify(result).includes(SENTINEL),
    );
  }

  // ── 9. Falha de finalização — updateSyncRun (pricing_sync_run, UPDATE) — logger injetado ──
  {
    const supabase = buildFakeSupabase({
      pricing_sync_run: sensitiveError(),
    });
    const { logError, calls } = buildLogSpy();
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase, logError);
    // updateSyncRun nunca lança nem retorna algo inspecionável — a única superfície
    // observável é o próprio logger injetado (ver handler.ts, mesmo padrão).
    await port.updateSyncRun("sync-run-1", {
      status: "FAILED",
      errorSummary: null,
      requestsMade: 5,
      rateLimitHits: 0,
    });
    assert(
      "falha de finalização: logger foi chamado exatamente uma vez",
      calls.length === 1,
    );
    assert(
      "falha de finalização: código fixo correto e contexto só com syncRunId/intendedStatus",
      calls[0]?.code === "JUSTTCG_PRICE_REFRESH_SYNC_RUN_FINALIZE_FAILED" &&
        JSON.stringify(Object.keys(calls[0]?.context ?? {}).sort()) ===
          JSON.stringify(["intendedStatus", "syncRunId"]) &&
        calls[0]?.context?.syncRunId === "sync-run-1" &&
        calls[0]?.context?.intendedStatus === "FAILED",
    );
    assert(
      "falha de finalização: sentinela sensível NUNCA aparece em nenhuma chamada capturada do logger",
      !JSON.stringify(calls).includes(SENTINEL),
    );
  }

  // ── 10. updateSyncRun sem logger injetado -> usa defaultSanitizedLogger sem lançar ──
  {
    const supabase = buildFakeSupabase({
      pricing_sync_run: sensitiveError(),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    let threw = false;
    try {
      await port.updateSyncRun("sync-run-1", {
        status: "COMPLETED",
        errorSummary: null,
        requestsMade: 1,
        rateLimitHits: 0,
      });
    } catch {
      threw = true;
    }
    assert("updateSyncRun sem logger injetado: não lança", !threw);
  }

  // ── 11. Caminho feliz — getConditionMap sem erro, para confirmar que o fake em si não introduz falso positivo ──
  {
    const supabase = buildFakeSupabase({
      pricing_condition_mapping: ok([
        { external_condition_code: "NM", condition_id: "condition-nm" },
      ]),
    });
    const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);
    const map = await port.getConditionMap(PRICING_SOURCE_ID);
    assert(
      "caminho feliz: getConditionMap resolve o Map esperado (harness do fake funciona)",
      map.get("NM") === "condition-nm",
    );
  }

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — mesma disciplina dos demais arquivos deste
// incremento: guardado por `typeof Deno !== "undefined"` para permanecer importável a
// partir de Node (validação offline no sandbox). 100% offline — nenhuma permissão
// --allow-* necessária.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "supabase-adapter — suíte offline (correção de segurança, 2026-08-21, 3ª rodada)",
    async () => {
      const result = await runSupabaseAdapterTests();
      const falhas = result.assertions.filter(([, ok]) => !ok);
      if (falhas.length > 0) {
        throw new Error(
          `${falhas.length}/${result.assertions.length} asserções falharam:\n` +
            falhas.map(([label]) => `  - ${label}`).join("\n"),
        );
      }
    },
  );
}
