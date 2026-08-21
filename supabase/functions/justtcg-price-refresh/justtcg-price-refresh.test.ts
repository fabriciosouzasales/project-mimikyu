// Project Mimikyu — supabase/functions/justtcg-price-refresh/justtcg-price-refresh.test.ts
// Bateria de testes offline da Edge Function justtcg-price-refresh — Incremento de
// Atualização Diária JustTCG (2026-08-21), item F.
//
// 100% offline: porta (PriceRefreshRunPort) e cliente JustTCG (fetchImpl) são sempre
// fakes controlados neste arquivo — nenhuma chamada real à JustTCG, nenhum SupabaseClient
// real. Mesmo padrão de supabase/functions/ptax-fx-refresh/ptax-fx-refresh.test.ts.
//
// Cobre os itens do pedido de Fabrício (item F) específicos da fronteira HTTP:
//   1. autenticação inválida -> zero banco/rede
//   18. segredos sanitizados (nunca aparecem em nenhuma resposta HTTP)
// mais a validação estrutural do handler (método, waveNumber, pricingSourceId ausente,
// corpo malformado, mapeamento completo de WaveExecutionResult.kind -> HTTP). A cobertura
// de negócio (planos, ondas, preços, concorrência real) já está em
// _shared/pricing-justtcg-refresh/pricing-justtcg-refresh.test.ts — este arquivo testa
// apenas como o handler HTTP reage a cada kind possível, não recalcula essa lógica.

import {
  handleJusttcgPriceRefreshRequest,
  type SanitizedLogger,
} from "./handler.ts";
import {
  extractProvidedSecret,
  isAuthorized,
  timingSafeEqual,
} from "./auth.ts";
import type { PriceRefreshRunPort } from "../_shared/pricing-justtcg-refresh/run-lifecycle.ts";
import type {
  ExistingProductRow,
  InsertObservationInput,
  InsertObservationsResult,
  InsertPriceRefreshRunResult,
  InsertProductInput,
  InsertProductsResult,
  LatestObservationKey,
  LatestObservationRow,
  PriceRefreshCallLogEntry,
  RefreshIdentityRow,
  UpdateSyncRunPatch,
} from "../_shared/pricing-justtcg-refresh/port.ts";
import type { RefreshSetCandidate } from "../_shared/pricing-justtcg-refresh/wave-plan.ts";
import {
  type FetchLike,
  type JustTcgCard,
  JustTcgClient,
} from "../_shared/pricing-justtcg/mod.ts";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

const EXPECTED_SECRET = "segredo-de-teste-justtcg-price-refresh-nao-real";
const PRICING_SOURCE_ID = "fake-pricing-source-justtcg";

// ----------------------------------------------------------------------------
// Fake da PORTA — mesmo desenho do arquivo irmão em _shared/pricing-justtcg-refresh/,
// simplificado ao necessário para exercitar cada branch do handler HTTP.
// ----------------------------------------------------------------------------

interface RecordedCall {
  op: string;
  payload: unknown;
}

interface FakePortOptions {
  candidateSets?: RefreshSetCandidate[];
  identitiesBySet?: Map<string, RefreshIdentityRow[]>;
  insertPriceRefreshRunResult?: InsertPriceRefreshRunResult;
}

function buildFakePort(
  recorded: RecordedCall[],
  opts: FakePortOptions = {},
): PriceRefreshRunPort {
  const products: ExistingProductRow[] = [];
  let nextProductId = 1;
  return {
    listRefreshCandidateSets(pricingSourceId: string) {
      recorded.push({
        op: "listRefreshCandidateSets",
        payload: pricingSourceId,
      });
      return Promise.resolve(opts.candidateSets ?? []);
    },
    listConfirmedIdentitiesForSet(_pricingSourceId: string, cardSetId: string) {
      recorded.push({
        op: "listConfirmedIdentitiesForSet",
        payload: cardSetId,
      });
      return Promise.resolve(opts.identitiesBySet?.get(cardSetId) ?? []);
    },
    getConditionMap(pricingSourceId: string) {
      recorded.push({ op: "getConditionMap", payload: pricingSourceId });
      return Promise.resolve(new Map([["NM", "condition-nm"]]));
    },
    findExistingProducts(identityIds: readonly string[]) {
      recorded.push({ op: "findExistingProducts", payload: identityIds });
      return Promise.resolve(
        products.filter((p) =>
          identityIds.includes(p.pricingSourceCardIdentityId)
        ),
      );
    },
    findLatestObservations(keys: readonly LatestObservationKey[]) {
      recorded.push({ op: "findLatestObservations", payload: keys });
      return Promise.resolve([] as LatestObservationRow[]);
    },
    insertProducts(
      rows: readonly InsertProductInput[],
    ): Promise<InsertProductsResult> {
      recorded.push({ op: "insertProducts", payload: rows });
      const inserted = rows.map((r) => {
        const row = {
          productId: `product-${nextProductId++}`,
          pricingSourceCardIdentityId: r.pricingSourceCardIdentityId,
          externalProductId: r.externalProductId,
        };
        products.push(row);
        return row;
      });
      return Promise.resolve({ ok: true, inserted });
    },
    insertObservations(
      rows: readonly InsertObservationInput[],
    ): Promise<InsertObservationsResult> {
      recorded.push({ op: "insertObservations", payload: rows });
      return Promise.resolve({ ok: true });
    },
    insertPriceRefreshRun(
      pricingSourceId: string,
    ): Promise<InsertPriceRefreshRunResult> {
      recorded.push({ op: "insertPriceRefreshRun", payload: pricingSourceId });
      return Promise.resolve(
        opts.insertPriceRefreshRunResult ??
          { outcome: "STARTED", syncRunId: "fake-sync-run-id" },
      );
    },
    insertSyncRunCalls(
      syncRunId: string,
      callLog: readonly PriceRefreshCallLogEntry[],
    ) {
      recorded.push({
        op: "insertSyncRunCalls",
        payload: { syncRunId, callLog },
      });
      return Promise.resolve({ ok: true } as InsertObservationsResult);
    },
    updateSyncRun(syncRunId: string, patch: UpdateSyncRunPatch): Promise<void> {
      recorded.push({ op: "updateSyncRun", payload: { syncRunId, patch } });
      return Promise.resolve();
    },
  };
}

// ----------------------------------------------------------------------------
// Fake do transporte HTTP da JustTCG — mesma disciplina do arquivo irmão.
// ----------------------------------------------------------------------------

function fakeCardsResponse(cards: JustTcgCard[]): Response {
  return {
    ok: true,
    status: 200,
    json: () => Promise.resolve({ data: cards, meta: { hasMore: false } }),
    text: () => Promise.resolve(""),
  } as unknown as Response;
}

function buildVariant(externalProductId: string, price: number) {
  return {
    uuid: externalProductId,
    condition: "NM",
    printing: "Normal",
    price,
    lastUpdated: 1_755_000_000,
  };
}

function buildFakeFetch(
  bySetId: Map<string, JustTcgCard[]>,
  calls: { count: number },
): FetchLike {
  return ((url: string | URL) => {
    calls.count++;
    const u = new URL(String(url));
    const setId = u.searchParams.get("set") ?? "";
    return Promise.resolve(fakeCardsResponse(bySetId.get(setId) ?? []));
  }) as FetchLike;
}

function authFailureFetch(calls: { count: number }): FetchLike {
  return (() => {
    calls.count++;
    return Promise.resolve({
      ok: false,
      status: 401,
      json: () => Promise.resolve({}),
      text: () => Promise.resolve("UNAUTHORIZED"),
    } as unknown as Response);
  }) as FetchLike;
}

function neverCalledFetch(calls: { count: number }): FetchLike {
  return (() => {
    calls.count++;
    throw new Error("fetchImpl NUNCA deveria ser chamado neste cenário");
  }) as FetchLike;
}

function buildRequest(
  opts: {
    method?: string;
    apikey?: string | null;
    body?: unknown;
    rawBody?: string;
  } = {},
): Request {
  const headers = new Headers();
  if (opts.apikey !== null) {
    headers.set("apikey", opts.apikey ?? EXPECTED_SECRET);
  }
  const init: RequestInit = { method: opts.method ?? "POST", headers };
  if (opts.rawBody !== undefined) {
    init.body = opts.rawBody;
  } else if (opts.body !== undefined) {
    init.body = JSON.stringify(opts.body);
  } else if ((opts.method ?? "POST") === "POST") {
    init.body = JSON.stringify({ waveNumber: 1 });
  }
  return new Request(
    "https://example.supabase.co/functions/v1/justtcg-price-refresh",
    init,
  );
}

function buildDeps(overrides: {
  expectedSecret?: string | null;
  port?: PriceRefreshRunPort;
  pricingSourceId?: string | null;
  fetchImpl?: FetchLike;
  // Opcional — só os cenários que precisam inspecionar o que chegaria a Function Logs
  // injetam um espião aqui (ver buildLogSpy() abaixo). Quando ausente, deps.logError fica
  // undefined e handler.ts usa seu próprio defaultSanitizedLogger (comportamento real de
  // produção), exatamente como já acontecia antes desta correção.
  logError?: SanitizedLogger;
}) {
  const recorded: RecordedCall[] = [];
  const fetchCalls = { count: 0 };
  const fetchImpl = overrides.fetchImpl ?? neverCalledFetch(fetchCalls);
  const deps = {
    // `??` trataria `expectedSecret: null` (o próprio cenário que este helper precisa
    // simular — segredo ausente no ambiente) como "não informado" e silenciosamente
    // recairia no EXPECTED_SECRET, mascarando o cenário. Comparação explícita contra
    // `undefined` — mesma disciplina já usada abaixo para pricingSourceId.
    expectedSecret: overrides.expectedSecret === undefined
      ? EXPECTED_SECRET
      : overrides.expectedSecret,
    port: overrides.port ?? buildFakePort(recorded),
    pricingSourceId: overrides.pricingSourceId === undefined
      ? PRICING_SOURCE_ID
      : overrides.pricingSourceId,
    buildClient: () => new JustTcgClient("fake-key", fetchImpl, 30),
    logError: overrides.logError,
  };
  return { deps, recorded, fetchCalls };
}

// ----------------------------------------------------------------------------
// Espião do logger sanitizado — substitui captura global de console (mais frágil e
// implícita) por um `SanitizedLogger` de verdade, injetado via HandlerDeps.logError.
// Cada chamada fica registrada em `calls`, permitindo provar por asserção (não por
// inspeção visual) que nenhum valor sensível chega ao logger, só o código fixo e o
// contexto operacional explicitamente permitido (ver handler.ts).
// ----------------------------------------------------------------------------

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

export async function runJusttcgPriceRefreshHandlerTests(): Promise<
  TestSuiteResult
> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) =>
    assertions.push([label, cond]);

  // ── 1. Método inválido -> 405, zero banco/rede (autenticação nem é lida) ───────────
  {
    const { deps, recorded, fetchCalls } = buildDeps({});
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ method: "GET" }),
      deps,
    );
    const body = await res.json();
    assert("método inválido: GET -> 405", res.status === 405);
    assert(
      "método inválido: header Allow: POST",
      res.headers.get("Allow") === "POST",
    );
    assert(
      "método inválido: nenhum acesso a banco/rede",
      recorded.length === 0 && fetchCalls.count === 0,
    );
    assert(
      "método inválido: corpo não expõe segredo",
      !JSON.stringify(body).includes(EXPECTED_SECRET),
    );
  }

  // ── 2. Autenticação — apikey ausente -> 401, zero banco/rede (item F.1) ───────────
  {
    const { deps, recorded, fetchCalls } = buildDeps({});
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: null }),
      deps,
    );
    assert("apikey ausente: 401", res.status === 401);
    assert(
      "apikey ausente: autenticação falha ANTES de qualquer acesso a banco/rede (item F.1)",
      recorded.length === 0 && fetchCalls.count === 0,
    );
  }

  // ── 3. Autenticação — apikey incorreto -> 401, zero banco/rede (item F.1) ─────────
  {
    const { deps, recorded, fetchCalls } = buildDeps({});
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: "valor-errado" }),
      deps,
    );
    assert("apikey incorreto: 401", res.status === 401);
    assert(
      "apikey incorreto: autenticação falha ANTES de qualquer acesso a banco/rede (item F.1)",
      recorded.length === 0 && fetchCalls.count === 0,
    );
  }

  // ── 4. expectedSecret ausente no ambiente -> nunca autoriza, mesmo com apikey certo ──
  {
    const { deps } = buildDeps({ expectedSecret: null });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      deps,
    );
    assert(
      "JUSTTCG_PRICE_REFRESH_SECRET ausente no ambiente: nunca autoriza (401)",
      res.status === 401,
    );
  }

  // ── 5. timingSafeEqual/isAuthorized/extractProvidedSecret — comparação sem early return de conteúdo ──
  {
    assert(
      "timingSafeEqual: strings iguais -> true",
      timingSafeEqual("abc123", "abc123"),
    );
    assert(
      "timingSafeEqual: difere no primeiro byte -> false",
      !timingSafeEqual("Xbc123", "abc123"),
    );
    assert(
      "timingSafeEqual: difere no último byte -> false",
      !timingSafeEqual("abc12X", "abc123"),
    );
    assert(
      "timingSafeEqual: comprimentos diferentes -> false",
      !timingSafeEqual("abc", "abc123"),
    );
    assert(
      "isAuthorized: guards de ausência não dependem do conteúdo do segredo esperado",
      !isAuthorized(null, EXPECTED_SECRET) &&
        !isAuthorized("qualquer-coisa", null),
    );
    assert(
      "extractProvidedSecret: lê sempre o header apikey, nunca Authorization",
      extractProvidedSecret(
        new Request("https://x.test", {
          headers: { apikey: "v1", Authorization: "Bearer outro" },
        }),
      ) === "v1",
    );
  }

  // ── 6. pricingSourceId ausente -> 500 SERVER_MISCONFIGURED, mesmo com auth OK e corpo válido ──
  {
    const { deps, fetchCalls } = buildDeps({ pricingSourceId: null });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      deps,
    );
    const body = await res.json();
    assert(
      "pricingSourceId ausente: 500 SERVER_MISCONFIGURED",
      res.status === 500 && body.error === "SERVER_MISCONFIGURED",
    );
    assert(
      "pricingSourceId ausente: JustTCG nunca chamada",
      fetchCalls.count === 0,
    );
  }

  // ── 7. Corpo JSON malformado -> 400 INVALID_JSON_BODY ──────────────────────────────
  {
    const { deps, fetchCalls } = buildDeps({});
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, rawBody: "{ isto não é json" }),
      deps,
    );
    const body = await res.json();
    assert(
      "corpo malformado: 400 INVALID_JSON_BODY",
      res.status === 400 && body.error === "INVALID_JSON_BODY",
    );
    assert("corpo malformado: JustTCG nunca chamada", fetchCalls.count === 0);
  }

  // ── 8. waveNumber ausente/fora de 1-30 -> 400 INVALID_WAVE_NUMBER, zero rede ───────
  // (limite elevado de 1-10 para 1-30 nesta rodada de correção pós-incidente, 2026-08-21 —
  // WAVE_PAGE_CAP 30->10, MAX_WAVES 10->30 — por isso o valor fora do intervalo testado é
  // 31, não mais 11, que agora é válido).
  {
    for (
      const bodyRuim of [{}, { waveNumber: 0 }, { waveNumber: 31 }, {
        waveNumber: 2.5,
      }, { waveNumber: "3" }]
    ) {
      const { deps, fetchCalls } = buildDeps({});
      const res = await handleJusttcgPriceRefreshRequest(
        buildRequest({ apikey: EXPECTED_SECRET, body: bodyRuim }),
        deps,
      );
      const body = await res.json();
      assert(
        `waveNumber inválido (${
          JSON.stringify(bodyRuim)
        }): 400 INVALID_WAVE_NUMBER`,
        res.status === 400 && body.error === "INVALID_WAVE_NUMBER",
      );
      assert(
        `waveNumber inválido (${
          JSON.stringify(bodyRuim)
        }): buildClient nunca chamado (zero rede)`,
        fetchCalls.count === 0,
      );
    }
  }

  // ── 9. waveNumber fora do plano -> 200 NOOP_WAVE_NOT_IN_PLAN ────────────────────────
  {
    const { deps, fetchCalls } = buildDeps({
      port: buildFakePort([], { candidateSets: [] }),
      fetchImpl: buildFakeFetch(new Map(), { count: 0 }),
    });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const body = await res.json();
    assert(
      "onda fora do plano: 200, outcome=NOOP_WAVE_NOT_IN_PLAN",
      res.status === 200 && body.outcome === "NOOP_WAVE_NOT_IN_PLAN",
    );
    assert(
      "onda fora do plano: planWaveCount=0 refletido na resposta",
      body.planWaveCount === 0,
    );
    assert("onda fora do plano: JustTCG nunca chamada", fetchCalls.count === 0);
  }

  // ── 10. Capacidade excedida -> 200 outcome=SCHEDULE_CAPACITY_EXCEEDED ───────────────
  // (30.100 cartas -> 301 páginas, 1 acima do teto de 300 = MAX_WAVES(30) * WAVE_PAGE_CAP
  // (10) — teto numérico inalterado pela correção pós-incidente de 2026-08-21, só a
  // composição mudou de 10 ondas * 30 para 30 ondas * 10).
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-x",
        setCode: "XXX",
        externalSetId: "ext-x",
        confirmedCardCount: 30_100,
      },
    ];
    const { deps, fetchCalls } = buildDeps({
      port: buildFakePort([], { candidateSets: candidates }),
    });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const body = await res.json();
    assert(
      "capacidade excedida: 200, outcome=SCHEDULE_CAPACITY_EXCEEDED",
      res.status === 200 && body.outcome === "SCHEDULE_CAPACITY_EXCEEDED",
    );
    assert(
      "capacidade excedida: JustTCG nunca chamada",
      fetchCalls.count === 0,
    );
  }

  // ── 11. Conflito de concorrência -> 409 CONCURRENT_SYNC_RUN_ACTIVE ──────────────────
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
    ];
    const { deps, fetchCalls } = buildDeps({
      port: buildFakePort([], {
        candidateSets: candidates,
        insertPriceRefreshRunResult: { outcome: "CONCURRENT_CONFLICT" },
      }),
    });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const body = await res.json();
    assert(
      "conflito de concorrência: 409",
      res.status === 409 && body.error === "CONCURRENT_SYNC_RUN_ACTIVE",
    );
    assert(
      "conflito de concorrência: JustTCG nunca chamada",
      fetchCalls.count === 0,
    );
  }

  // ── 12. Falha ao abrir o run (não-conflito) -> 500 SYNC_RUN_START_FAILED ───────────
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
    ];
    const { deps } = buildDeps({
      port: buildFakePort([], {
        candidateSets: candidates,
        insertPriceRefreshRunResult: {
          outcome: "OTHER_ERROR",
          message: "ERRO_SIMULADO",
        },
      }),
    });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const body = await res.json();
    assert(
      "falha ao abrir run: 500 SYNC_RUN_START_FAILED",
      res.status === 500 && body.error === "SYNC_RUN_START_FAILED",
    );
  }

  // ── 13. Execução bem-sucedida (produto novo) -> 200, outcome=EXECUTED/COMPLETED ────
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-a", [{
        identityId: "identity-1",
        externalCardId: "ext-card-1",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-1",
      }]],
    ]);
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "ext-card-1",
        name: "Bulbasaur",
        variants: [buildVariant("prod-1", 4.2)],
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const { deps } = buildDeps({
      port: buildFakePort([], { candidateSets: candidates, identitiesBySet }),
      fetchImpl: buildFakeFetch(bySetId, fetchCalls),
    });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const body = await res.json();
    assert(
      "execução bem-sucedida: 200, success=true, outcome=EXECUTED, status=COMPLETED",
      res.status === 200 && body.success === true &&
        body.outcome === "EXECUTED" && body.status === "COMPLETED",
    );
    assert(
      "execução bem-sucedida: productsInserted=1, observationsWritten=1",
      body.productsInserted === 1 && body.observationsWritten === 1,
    );
    assert(
      "execução bem-sucedida: syncRunId refletido na resposta",
      typeof body.syncRunId === "string" && body.syncRunId.length > 0,
    );
  }

  // ── 14. Execução com falha técnica (AUTH_FAILURE da JustTCG) -> 500, status=FAILED ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-a", [{
        identityId: "identity-1",
        externalCardId: "ext-card-1",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-1",
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const { deps } = buildDeps({
      port: buildFakePort([], { candidateSets: candidates, identitiesBySet }),
      fetchImpl: authFailureFetch(fetchCalls),
    });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const body = await res.json();
    assert(
      "AUTH_FAILURE na JustTCG: 500, success=false, status=FAILED",
      res.status === 500 && body.success === false && body.status === "FAILED",
    );
  }

  // ── 15. Exceção não prevista dentro do core -> 500 INTERNAL_ERROR, nunca error.message cru,
  //         nem na resposta HTTP nem no logger (correção 2026-08-21 — ver handler.ts) ──────
  {
    const throwingPort: PriceRefreshRunPort = {
      ...buildFakePort([]),
      listRefreshCandidateSets() {
        throw new Error("FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR");
      },
    };
    const { logError, calls: logCalls } = buildLogSpy();
    const { deps } = buildDeps({ port: throwingPort, logError });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const bodyText = await res.text();
    assert(
      "exceção não prevista: 500 INTERNAL_ERROR",
      res.status === 500 && JSON.parse(bodyText).error === "INTERNAL_ERROR",
    );
    assert(
      "exceção não prevista: mensagem crua do erro NUNCA aparece na resposta HTTP",
      !bodyText.includes("FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR"),
    );
    assert(
      "exceção não prevista: o logger injetado FOI de fato chamado (prova que o catch executou, não que ficou mudo)",
      logCalls.length === 1,
    );
    assert(
      "exceção não prevista: sentinela sensível NUNCA aparece em nenhuma chamada capturada do logger",
      !JSON.stringify(logCalls).includes(
        "FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR",
      ),
    );
    assert(
      "exceção não prevista: log capturado contém só o código fixo e {waveNumber} — nenhum campo capaz de carregar o erro cru (Error/message/stack)",
      logCalls[0].code === "JUSTTCG_PRICE_REFRESH_INTERNAL_ERROR" &&
        JSON.stringify(Object.keys(logCalls[0].context ?? {})) ===
          JSON.stringify(["waveNumber"]) &&
        logCalls[0].context?.waveNumber === 1,
    );
  }

  // ── 15b. Mesma exceção não prevista, mas com o run já aberto (insertPriceRefreshRun já
  //          confirmado) -> a sentinela também não aparece em nenhuma chamada registrada na
  //          porta (proxy de tudo que seria persistido/telemetria), nem no logger, nem na
  //          resposta. Cenário representativo do caso real relatado por Fabrício: o run já
  //          existe quando a falha ocorre, não é uma falha antes de qualquer persistência. ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
    ];
    const recorded: RecordedCall[] = [];
    const basePort = buildFakePort(recorded, { candidateSets: candidates });
    const throwingAfterStartPort: PriceRefreshRunPort = {
      ...basePort,
      listConfirmedIdentitiesForSet(
        _pricingSourceId: string,
        cardSetId: string,
      ) {
        recorded.push({
          op: "listConfirmedIdentitiesForSet",
          payload: cardSetId,
        });
        throw new Error(
          "FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR",
        );
      },
    };
    const { logError, calls: logCalls } = buildLogSpy();
    const { deps } = buildDeps({ port: throwingAfterStartPort, logError });
    const res = await handleJusttcgPriceRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
      deps,
    );
    const bodyText = await res.text();
    assert(
      "telemetria persistida: run já foi de fato aberto (insertPriceRefreshRun registrado) antes do throw — cenário representativo, não artificial",
      recorded.some((c) => c.op === "insertPriceRefreshRun"),
    );
    assert(
      "telemetria persistida: 500 INTERNAL_ERROR mesmo com o run já aberto",
      res.status === 500 && JSON.parse(bodyText).error === "INTERNAL_ERROR",
    );
    assert(
      "telemetria persistida: sentinela NUNCA aparece em nenhuma chamada registrada na porta (proxy de tudo que seria persistido/telemetria)",
      !JSON.stringify(recorded).includes(
        "FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR",
      ),
    );
    assert(
      "telemetria persistida: sentinela também não aparece no log capturado",
      !JSON.stringify(logCalls).includes(
        "FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR",
      ),
    );
    assert(
      "telemetria persistida: sentinela também não aparece na resposta HTTP",
      !bodyText.includes("FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR"),
    );
  }

  // ── 16. Nenhuma exposição de segredo em nenhuma resposta (item F.18) ───────────────
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
    ];
    const cenarios = await Promise.all([
      // 405
      handleJusttcgPriceRefreshRequest(
        buildRequest({ method: "DELETE" }),
        buildDeps({}).deps,
      ),
      // 401 (apikey errado)
      handleJusttcgPriceRefreshRequest(
        buildRequest({ apikey: "chute-errado" }),
        buildDeps({}).deps,
      ),
      // 400 (waveNumber inválido)
      handleJusttcgPriceRefreshRequest(
        buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 99 } }),
        buildDeps({}).deps,
      ),
      // 409 (conflito)
      handleJusttcgPriceRefreshRequest(
        buildRequest({ apikey: EXPECTED_SECRET, body: { waveNumber: 1 } }),
        buildDeps({
          port: buildFakePort([], {
            candidateSets: candidates,
            insertPriceRefreshRunResult: { outcome: "CONCURRENT_CONFLICT" },
          }),
        }).deps,
      ),
      // 500 (server misconfigured)
      handleJusttcgPriceRefreshRequest(
        buildRequest({ apikey: EXPECTED_SECRET }),
        buildDeps({ pricingSourceId: null }).deps,
      ),
    ]);
    let anyLeak = false;
    for (const res of cenarios) {
      const text = await res.text();
      if (text.includes(EXPECTED_SECRET)) anyLeak = true;
    }
    assert(
      "nenhuma resposta HTTP (405/401/400/409/500) contém o segredo esperado (item F.18)",
      !anyLeak,
    );
  }

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — guardado por `typeof Deno !== "undefined"` para
// permanecer importável a partir de Node (validação offline no sandbox). 100% offline —
// nenhuma permissão --allow-* necessária.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "justtcg-price-refresh — suíte offline do handler HTTP (item F, 2026-08-21)",
    async () => {
      const result = await runJusttcgPriceRefreshHandlerTests();
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
