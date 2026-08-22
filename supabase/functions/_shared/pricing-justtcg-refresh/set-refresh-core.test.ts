// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/set-refresh-core.test.ts
// Bateria de testes offline do dispatcher durável por Set (P15) — fase "implementar
// somente o dispatcher/Edge Function que consome as RPCs já criadas" (2026-08-22).
//
// 100% offline: fetch e a porta (SetRefreshPort) são sempre fakes controlados neste
// arquivo — nenhuma chamada real à JustTCG, nenhum SupabaseClient real, nenhuma RPC real.
// Mesmo padrão de pricing-justtcg-refresh.test.ts (fake da PORTA de domínio, nunca um fake
// de PostgREST) — a diferença é que aqui a porta simula diretamente o CONTRATO das 3 RPCs
// (open_/checkpoint_/close_pricing_set_refresh_attempt), não a lógica SQL interna delas
// (já validada em BEGIN/ROLLBACK e em produção na rodada anterior).
//
// Cobre os 11 cenários nomeados no pedido de Fabrício: Set pequeno, Set com múltiplas
// páginas, retomada por checkpoint, SOURCE_BUSY, NO_WORK, BUDGET_STOPPED,
// DEADLINE_STOPPED, RECONCILIATION_INCOMPLETE, R1/R5 REUSE, NEW, PRIMARY+ALTERNATE — mais
// cenários adicionais (LEASE_LOST, falha de leitura local pré-open, AUTH_FAILURE,
// TECHNICAL_FAILURE 404 vs. outros, SAME_PRICE_SKIP) que a implementação exige para ficar
// coberta ponta a ponta.

import type { Clock } from "./deadline.ts";
import {
  executeSetRefreshAttempt,
  type SetRefreshExecutionResult,
} from "./set-refresh-core.ts";
import type {
  CloseAttemptResult,
  InsertObservationInput,
  InsertObservationsResult,
  LatestObservationKey,
  LatestObservationRow,
  OpenAttemptResult,
  PageOutcome,
  PriceRefreshCallLogEntry,
  RefreshIdentityRow,
  ResolvedProductRow,
  ResolveProductsBatchInput,
  ResolveProductsBatchResult,
  RunStatus,
  SetRefreshPort,
} from "./set-refresh-port.ts";
import {
  CARDS_PAGE_LIMIT,
  type FetchLike,
  type JustTcgCard,
  type JustTcgVariant,
  JustTcgClient,
} from "../pricing-justtcg/mod.ts";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

const PRICING_SOURCE_ID = "fake-pricing-source-justtcg";
const CARD_SET_ID = "fake-card-set-id";
const EXTERNAL_SET_ID = "ext-set-a";
const SYNC_RUN_ID = "fake-sync-run-id";
const MAPPING_ID = "fake-pricing-card-mapping-id";

// ----------------------------------------------------------------------------
// Fake da PORTA (SetRefreshPort) — estado em memória, configurável por teste. Implementa
// exatamente a interface de set-refresh-port.ts.
// ----------------------------------------------------------------------------

interface RecordedCall {
  op:
    | "listConfirmedIdentitiesForSet"
    | "getConditionMap"
    | "findLatestObservations"
    | "resolveProductsBatch"
    | "insertObservations"
    | "insertSyncRunCalls"
    | "openAttempt"
    | "checkpointPage"
    | "closeAttempt";
  payload: unknown;
}

interface SeedProductRow {
  productId: string;
  pricingCardMappingId: string;
  pricingSourceCardIdentityId: string;
  externalProductId: string;
  sourcePrintingLabel: string;
}

interface FakeSetPortOptions {
  identityRows?: RefreshIdentityRow[];
  conditionMap?: Map<string, string>;
  existingProducts?: SeedProductRow[];
  latestObservationsByKey?: Map<string, LatestObservationRow>; // key: `${productId}::${conditionId}`
  openAttemptResult?: OpenAttemptResult;
  // Consumido em ordem por chamada a checkpointPage — o último valor repete se houver mais
  // chamadas que entradas configuradas (default: sempre true).
  checkpointResults?: boolean[];
  closeAttemptResult?: CloseAttemptResult;
  failListIdentities?: boolean;
  failResolveProducts?: boolean;
  failInsertObservations?: boolean;
  failInsertSyncRunCalls?: boolean;
  // Modo "retomada real entre invocações" (cenário 23) — em vez de um openAttemptResult
  // estático, a porta passa a rastrear resume_offset/cycle_seen_external_card_ids em
  // memória (mesma semântica de pricing_set_refresh_state) e devolvê-los atualizados a
  // CADA chamada de openAttempt(). checkpointPage() avança esse estado; closeAttempt()
  // decide SUCCESS/continuação exatamente como a RPC real: NO_MORE_PAGES zera o estado
  // (fim de ciclo) e compara seenCount x expectedCount; qualquer outro pageOutcome de
  // continuação (BUDGET_STOPPED/DEADLINE_STOPPED) preserva o estado intacto para a próxima
  // chamada. Permite provar retomada com DUAS chamadas separadas e independentes a
  // executeSetRefreshAttempt() sobre a MESMA instância de porta — sem precisar de um
  // SupabaseClient real nem de duas invocações HTTP reais.
  statefulResume?: { expectedCount: number };
}

function buildFakeSetPort(
  recorded: RecordedCall[],
  opts: FakeSetPortOptions = {},
): SetRefreshPort {
  const products: SeedProductRow[] = [...(opts.existingProducts ?? [])];
  let nextProductId = 9000;
  let checkpointCallIndex = 0;
  let openAttemptCount = 0;
  let resumeState = { offset: 0, seen: new Set<string>() };
  if (opts.statefulResume && opts.openAttemptResult?.outcome === "CLAIMED") {
    resumeState = {
      offset: opts.openAttemptResult.resumeOffset,
      seen: new Set(opts.openAttemptResult.cycleSeenExternalCardIds),
    };
  }

  return {
    listConfirmedIdentitiesForSet(pricingSourceId: string, cardSetId: string) {
      recorded.push({
        op: "listConfirmedIdentitiesForSet",
        payload: { pricingSourceId, cardSetId },
      });
      if (opts.failListIdentities) {
        return Promise.reject(new Error("SIMULATED_LOCAL_READ_FAILURE"));
      }
      return Promise.resolve(opts.identityRows ?? []);
    },
    getConditionMap(pricingSourceId: string) {
      recorded.push({ op: "getConditionMap", payload: pricingSourceId });
      return Promise.resolve(
        opts.conditionMap ?? new Map([["NM", "condition-nm"]]),
      );
    },
    findLatestObservations(keys: readonly LatestObservationKey[]) {
      recorded.push({ op: "findLatestObservations", payload: keys });
      const out: LatestObservationRow[] = [];
      for (const k of keys) {
        const row = opts.latestObservationsByKey?.get(
          `${k.productId}::${k.conditionId}`,
        );
        if (row) out.push(row);
      }
      return Promise.resolve(out);
    },
    resolveProductsBatch(
      rows: readonly ResolveProductsBatchInput[],
    ): Promise<ResolveProductsBatchResult> {
      recorded.push({ op: "resolveProductsBatch", payload: rows });
      if (opts.failResolveProducts) {
        return Promise.resolve({
          ok: false,
          message: "PRODUCT_RESOLUTION_FALHOU_SIMULADO",
        });
      }
      const out: ResolvedProductRow[] = rows.map((r) => {
        const existing = products.find((p) =>
          p.pricingCardMappingId === r.pricingCardMappingId &&
          p.externalProductId === r.externalProductId
        );
        if (existing) {
          return {
            productId: existing.productId,
            pricingCardMappingId: existing.pricingCardMappingId,
            externalProductId: existing.externalProductId,
            pricingSourceCardIdentityId: existing.pricingSourceCardIdentityId,
            classification: "REUSE",
            candidatePrintingLabel: r.sourcePrintingLabel,
            storedPrintingLabel: existing.sourcePrintingLabel,
          };
        }
        const created: SeedProductRow = {
          productId: `product-${nextProductId++}`,
          pricingCardMappingId: r.pricingCardMappingId,
          pricingSourceCardIdentityId: r.pricingSourceCardIdentityId,
          externalProductId: r.externalProductId,
          sourcePrintingLabel: r.sourcePrintingLabel,
        };
        products.push(created);
        return {
          productId: created.productId,
          pricingCardMappingId: created.pricingCardMappingId,
          externalProductId: created.externalProductId,
          pricingSourceCardIdentityId: created.pricingSourceCardIdentityId,
          classification: "NEW",
          candidatePrintingLabel: r.sourcePrintingLabel,
          storedPrintingLabel: r.sourcePrintingLabel,
        };
      });
      return Promise.resolve({ ok: true, rows: out });
    },
    insertObservations(
      rows: readonly InsertObservationInput[],
    ): Promise<InsertObservationsResult> {
      recorded.push({ op: "insertObservations", payload: rows });
      if (opts.failInsertObservations) {
        return Promise.resolve({
          ok: false,
          message: "OBSERVATION_INSERT_FALHOU_SIMULADO",
        });
      }
      return Promise.resolve({ ok: true });
    },
    insertSyncRunCalls(
      syncRunId: string,
      callLog: readonly PriceRefreshCallLogEntry[],
    ): Promise<InsertObservationsResult> {
      recorded.push({ op: "insertSyncRunCalls", payload: { syncRunId, callLog } });
      if (opts.failInsertSyncRunCalls) {
        return Promise.resolve({
          ok: false,
          message: "SYNC_RUN_CALL_INSERT_FALHOU_SIMULADO",
        });
      }
      return Promise.resolve({ ok: true });
    },
    openAttempt(pricingSourceId: string): Promise<OpenAttemptResult> {
      recorded.push({ op: "openAttempt", payload: pricingSourceId });
      if (opts.statefulResume && opts.openAttemptResult?.outcome === "CLAIMED") {
        openAttemptCount++;
        const claimed = opts.openAttemptResult;
        return Promise.resolve({
          ...claimed,
          // syncRunId distinto por chamada — mesmo padrão da RPC real, que faz um novo
          // INSERT em pricing_sync_run a cada open_pricing_set_refresh_attempt().
          syncRunId: `${claimed.syncRunId}-attempt-${openAttemptCount}`,
          resumeOffset: resumeState.offset,
          cycleSeenExternalCardIds: [...resumeState.seen],
        });
      }
      return Promise.resolve(opts.openAttemptResult ?? { outcome: "NO_CANDIDATE" });
    },
    checkpointPage(
      syncRunId: string,
      newResumeOffset: number,
      newlySeenExternalCardIds: readonly string[],
    ): Promise<boolean> {
      recorded.push({
        op: "checkpointPage",
        payload: { syncRunId, newResumeOffset, newlySeenExternalCardIds },
      });
      if (opts.statefulResume) {
        resumeState.offset = newResumeOffset;
        for (const id of newlySeenExternalCardIds) resumeState.seen.add(id);
      }
      const results = opts.checkpointResults ?? [true];
      const result = results[Math.min(checkpointCallIndex, results.length - 1)];
      checkpointCallIndex++;
      return Promise.resolve(result);
    },
    closeAttempt(
      syncRunId: string,
      pageOutcome: PageOutcome,
      runStatus: RunStatus,
      requestsMade: number,
      rateLimitHits: number,
      errorSummary: string | null,
    ): Promise<CloseAttemptResult> {
      recorded.push({
        op: "closeAttempt",
        payload: {
          syncRunId,
          pageOutcome,
          runStatus,
          requestsMade,
          rateLimitHits,
          errorSummary,
        },
      });
      if (opts.statefulResume) {
        // Mesma semântica de close_pricing_set_refresh_attempt (migration 3933):
        // NO_MORE_PAGES fecha o ciclo (compara cobertura e zera o estado para o próximo);
        // qualquer outro pageOutcome de continuação (BUDGET_STOPPED/DEADLINE_STOPPED)
        // preserva resumeState intacto — a PRÓXIMA chamada a openAttempt() retoma dali.
        if (pageOutcome === "NO_MORE_PAGES") {
          const seenCount = resumeState.seen.size;
          const expectedCount = opts.statefulResume.expectedCount;
          resumeState = { offset: 0, seen: new Set() };
          return Promise.resolve({
            finalOutcome: seenCount >= expectedCount ? "SUCCESS" : "RECONCILIATION_INCOMPLETE",
            seenCount,
            expectedCount,
          });
        }
        return Promise.resolve({ finalOutcome: pageOutcome, seenCount: null, expectedCount: null });
      }
      return Promise.resolve(
        opts.closeAttemptResult ?? {
          finalOutcome: pageOutcome,
          seenCount: null,
          expectedCount: null,
        },
      );
    },
  };
}

function buildClaimed(
  overrides: Partial<Extract<OpenAttemptResult, { outcome: "CLAIMED" }>> = {},
): OpenAttemptResult {
  return {
    outcome: "CLAIMED",
    syncRunId: SYNC_RUN_ID,
    pricingSetMappingId: "fake-pricing-set-mapping-id",
    cardSetId: CARD_SET_ID,
    externalSetId: EXTERNAL_SET_ID,
    resumeOffset: 0,
    cycleSeenExternalCardIds: [],
    ...overrides,
  };
}

function buildIdentity(
  identityId: string,
  externalCardId: string,
  identityRole: "PRIMARY" | "ALTERNATE" = "PRIMARY",
  pricingCardMappingId: string = MAPPING_ID,
): RefreshIdentityRow {
  return { identityId, externalCardId, identityRole, pricingCardMappingId };
}

function buildVariant(
  externalProductId: string,
  price: number,
  conditionRaw = "NM",
): JustTcgVariant {
  return {
    uuid: externalProductId,
    condition: conditionRaw,
    printing: "Normal",
    price,
    lastUpdated: 1_755_000_000,
  };
}

function buildCard(id: string, variants: JustTcgVariant[]): JustTcgCard {
  return { id, name: `Card ${id}`, variants };
}

// ----------------------------------------------------------------------------
// Fake do cliente JustTCG — fila de respostas consumida em ordem, mesma disciplina de
// pricing-justtcg-refresh.test.ts (só o transporte HTTP é fake).
// ----------------------------------------------------------------------------

function successResponse(cards: JustTcgCard[], hasMore: boolean): Response {
  return {
    ok: true,
    status: 200,
    json: () => Promise.resolve({ data: cards, meta: { hasMore } }),
    text: () => Promise.resolve(""),
  } as unknown as Response;
}

function authFailureResponse(): Response {
  return {
    ok: false,
    status: 401,
    json: () => Promise.resolve({}),
    text: () => Promise.resolve("UNAUTHORIZED"),
  } as unknown as Response;
}

function technicalFailureResponse(status: number): Response {
  return {
    ok: false,
    status,
    json: () => Promise.resolve({}),
    text: () => Promise.resolve("ERROR"),
  } as unknown as Response;
}

function buildQueuedFetch(
  responses: Response[],
  calls: { count: number; urls: string[] },
): FetchLike {
  return ((url: string | URL) => {
    calls.urls.push(String(url));
    const idx = Math.min(calls.count, responses.length - 1);
    calls.count++;
    return Promise.resolve(responses[idx]);
  }) as FetchLike;
}

function offsetOf(url: string): string | null {
  return new URL(url).searchParams.get("offset");
}

function buildStepClock(steps: number[]): Clock {
  let i = 0;
  return () => {
    const v = steps[Math.min(i, steps.length - 1)];
    i++;
    return v;
  };
}

export async function runSetRefreshCoreTests(): Promise<TestSuiteResult> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // ── 1. NO_WORK — NO_CANDIDATE nunca toca JustTCG nem chama checkpoint_/close_ ──────
  {
    const recorded: RecordedCall[] = [];
    const port = buildFakeSetPort(recorded, {
      openAttemptResult: { outcome: "NO_CANDIDATE" },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient("fake-key", buildQueuedFetch([], fetchCalls), 10);
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("NO_WORK: kind=NO_WORK", result.kind === "NO_WORK");
    assert("NO_WORK: zero requisições à JustTCG", fetchCalls.count === 0);
    assert(
      "NO_WORK: nunca chama checkpointPage/closeAttempt",
      !recorded.some((c) => c.op === "checkpointPage" || c.op === "closeAttempt"),
    );
  }

  // ── 2. SOURCE_BUSY — outro PRICE_REFRESH/CARD_SYNC ativo, nunca toca JustTCG ────────
  {
    const recorded: RecordedCall[] = [];
    const port = buildFakeSetPort(recorded, {
      openAttemptResult: { outcome: "SOURCE_BUSY" },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient("fake-key", buildQueuedFetch([], fetchCalls), 10);
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("SOURCE_BUSY: kind=SOURCE_BUSY", result.kind === "SOURCE_BUSY");
    assert("SOURCE_BUSY: zero requisições à JustTCG", fetchCalls.count === 0);
    assert(
      "SOURCE_BUSY: nunca chama checkpointPage/closeAttempt",
      !recorded.some((c) => c.op === "checkpointPage" || c.op === "closeAttempt"),
    );
  }

  // ── 3. Set pequeno — 1 página, NO_MORE_PAGES, SUCCESS ───────────────────────────────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-1", "card-1");
    const card = buildCard("card-1", [buildVariant("prod-1", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      closeAttemptResult: { finalOutcome: "SUCCESS", seenCount: 1, expectedCount: 1 },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Set pequeno: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("Set pequeno: pageOutcome=NO_MORE_PAGES", result.pageOutcome === "NO_MORE_PAGES");
      assert("Set pequeno: runStatus=COMPLETED", result.runStatus === "COMPLETED");
      assert("Set pequeno: finalOutcome=SUCCESS", result.finalOutcome === "SUCCESS");
      assert("Set pequeno: 1 página processada", result.pagesProcessed === 1);
      assert("Set pequeno: 1 candidato extraído", result.candidatesExtracted === 1);
      assert("Set pequeno: 1 produto NEW", result.productsNew === 1 && result.productsReused === 0);
      assert("Set pequeno: 1 observação escrita", result.observationsWritten === 1);
    }
    assert("Set pequeno: exatamente 1 requisição à JustTCG", fetchCalls.count === 1);
    assert(
      "Set pequeno: checkpointPage chamado com offset=100",
      recorded.some((c) =>
        c.op === "checkpointPage" &&
        (c.payload as { newResumeOffset: number }).newResumeOffset === CARDS_PAGE_LIMIT
      ),
    );
  }

  // ── 4. Set com múltiplas páginas — 2 páginas (1ª cheia, 2ª final) ──────────────────
  {
    const recorded: RecordedCall[] = [];
    const identity1 = buildIdentity("identity-1", "card-1");
    const identity2 = buildIdentity("identity-2", "card-2");
    const cardsPage1 = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-filler-${i}`, []),
    );
    cardsPage1[0] = buildCard("card-1", [buildVariant("prod-1", 10)]);
    const cardsPage2 = [buildCard("card-2", [buildVariant("prod-2", 20)])];
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity1, identity2],
      openAttemptResult: buildClaimed(),
      closeAttemptResult: { finalOutcome: "SUCCESS", seenCount: 2, expectedCount: 2 },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch(
        [successResponse(cardsPage1, true), successResponse(cardsPage2, false)],
        fetchCalls,
      ),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Multi-página: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("Multi-página: pageOutcome=NO_MORE_PAGES", result.pageOutcome === "NO_MORE_PAGES");
      assert("Multi-página: 2 páginas processadas", result.pagesProcessed === 2);
      assert("Multi-página: 2 candidatos extraídos", result.candidatesExtracted === 2);
    }
    assert("Multi-página: exatamente 2 requisições", fetchCalls.count === 2);
    assert("Multi-página: 1ª chamada offset=0", offsetOf(fetchCalls.urls[0]) === "0");
    assert(
      "Multi-página: 2ª chamada offset=100",
      offsetOf(fetchCalls.urls[1]) === String(CARDS_PAGE_LIMIT),
    );
  }

  // ── 5. Retomada por checkpoint — resumeOffset>0/cycleSeen não-vazio já herdados ────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-3", "card-3");
    const card = buildCard("card-3", [buildVariant("prod-3", 5)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed({
        resumeOffset: 200,
        cycleSeenExternalCardIds: ["card-1", "card-2"],
      }),
      closeAttemptResult: { finalOutcome: "SUCCESS", seenCount: 3, expectedCount: 3 },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert(
      "Retomada: 1ª (e única) chamada já parte do offset=200 (nunca reinicia do zero)",
      offsetOf(fetchCalls.urls[0]) === "200",
    );
    assert("Retomada: kind=CLOSED", result.kind === "CLOSED");
    assert(
      "Retomada: checkpoint final inclui os IDs herdados + o novo (card-1, card-2, card-3)",
      recorded.some((c) =>
        c.op === "checkpointPage" &&
        (c.payload as { newResumeOffset: number }).newResumeOffset === 300
      ),
    );
  }

  // ── 6. BUDGET_STOPPED — teto de requisições atingido no meio do Set = continuação normal
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-4", "card-4");
    const cardsFullPage = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-filler-${i}`, []),
    );
    cardsFullPage[0] = buildCard("card-4", [buildVariant("prod-4", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    // requestBudget=1 — a 1ª página é processada normalmente; a 2ª chamada de client.get()
    // (página seguinte, já que hasMore=true) devolve BUDGET_STOPPED SEM tocar fetchImpl.
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse(cardsFullPage, true)], fetchCalls),
      1,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("BUDGET_STOPPED: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("BUDGET_STOPPED: pageOutcome=BUDGET_STOPPED", result.pageOutcome === "BUDGET_STOPPED");
      assert(
        "BUDGET_STOPPED: runStatus=COMPLETED (continuação normal, nunca FAILED)",
        result.runStatus === "COMPLETED",
      );
      assert("BUDGET_STOPPED: 1 página processada antes do corte", result.pagesProcessed === 1);
    }
    assert("BUDGET_STOPPED: exatamente 1 requisição real à JustTCG", fetchCalls.count === 1);
    assert(
      "BUDGET_STOPPED: checkpoint da 1ª página foi persistido antes do corte",
      recorded.filter((c) => c.op === "checkpointPage").length === 1,
    );
  }

  // ── 7. DEADLINE_STOPPED — 110s excedidos entre páginas = continuação normal ────────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-5", "card-5");
    const cardsFullPage = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-filler-${i}`, []),
    );
    cardsFullPage[0] = buildCard("card-5", [buildVariant("prod-5", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse(cardsFullPage, true)], fetchCalls),
      10,
    );
    // startedAtMs=0 (1ª chamada); checagem antes da 1ª página: clock()=0 -> 0ms, dentro do
    // prazo; checagem antes da 2ª página: clock()=200000 -> 200s >= 110s -> corta.
    const clock = buildStepClock([0, 0, 200_000]);
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID, clock);
    assert("DEADLINE_STOPPED: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "DEADLINE_STOPPED: pageOutcome=DEADLINE_STOPPED",
        result.pageOutcome === "DEADLINE_STOPPED",
      );
      assert(
        "DEADLINE_STOPPED: runStatus=COMPLETED (continuação normal, nunca FAILED)",
        result.runStatus === "COMPLETED",
      );
      assert("DEADLINE_STOPPED: 1 página processada antes do corte", result.pagesProcessed === 1);
    }
    assert("DEADLINE_STOPPED: exatamente 1 requisição real (nunca chegou à 2ª)", fetchCalls.count === 1);
  }

  // ── 8. RECONCILIATION_INCOMPLETE — NUNCA conflated com SUCCESS ─────────────────────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-6", "card-6");
    const card = buildCard("card-6", [buildVariant("prod-6", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      closeAttemptResult: {
        finalOutcome: "RECONCILIATION_INCOMPLETE",
        seenCount: 1,
        expectedCount: 3,
      },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("RECONCILIATION_INCOMPLETE: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "RECONCILIATION_INCOMPLETE: finalOutcome nunca é SUCCESS",
        result.finalOutcome === "RECONCILIATION_INCOMPLETE" &&
          (result.finalOutcome as string) !== "SUCCESS",
      );
      assert(
        "RECONCILIATION_INCOMPLETE: pageOutcome ainda é NO_MORE_PAGES (todas as páginas disponíveis foram processadas — a incompletude é de COBERTURA, não de execução)",
        result.pageOutcome === "NO_MORE_PAGES",
      );
      assert(
        "RECONCILIATION_INCOMPLETE: seenCount/expectedCount repassados tal como a RPC devolveu",
        result.seenCount === 1 && result.expectedCount === 3,
      );
    }
  }

  // ── 9. R1/R5 REUSE — produto já existente pela chave econômica real é reaproveitado ─
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-7", "card-7");
    const card = buildCard("card-7", [buildVariant("prod-7", 15)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      existingProducts: [{
        productId: "product-existing-1",
        pricingCardMappingId: MAPPING_ID,
        pricingSourceCardIdentityId: "identity-antiga-diferente",
        externalProductId: "prod-7",
        sourcePrintingLabel: "Normal",
      }],
      latestObservationsByKey: new Map([
        ["product-existing-1::condition-nm", {
          productId: "product-existing-1",
          conditionId: "condition-nm",
          price: 10,
          observedAt: "2026-08-01T00:00:00.000Z",
        }],
      ]),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("R1/R5 REUSE: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "R1/R5 REUSE: produto reaproveitado pela chave econômica (mapping+external_product_id), mesmo com identity divergente",
        result.productsReused === 1 && result.productsNew === 0,
      );
      assert(
        "R1/R5 REUSE: preço mudou (15 != 10) -> observação nova escrita",
        result.observationsWritten === 1 && result.observationsSkippedSamePrice === 0,
      );
    }
  }

  // ── 10. NEW — produto inexistente é criado pela primeira vez ───────────────────────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-8", "card-8");
    const card = buildCard("card-8", [buildVariant("prod-8", 20)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("NEW: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "NEW: 1 produto NEW, zero REUSE",
        result.productsNew === 1 && result.productsReused === 0,
      );
      assert(
        "NEW: primeira observação sempre escrita (FIRST_OBSERVATION)",
        result.observationsWritten === 1,
      );
    }
  }

  // ── 11. PRIMARY+ALTERNATE — as duas identidades da mesma carta local são processadas ─
  {
    const recorded: RecordedCall[] = [];
    const primary = buildIdentity("identity-primary", "card-9a", "PRIMARY", MAPPING_ID);
    const alternate = buildIdentity("identity-alternate", "card-9b", "ALTERNATE", MAPPING_ID);
    const cardA = buildCard("card-9a", [buildVariant("prod-9a", 10)]);
    const cardB = buildCard("card-9b", [buildVariant("prod-9b", 12)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [primary, alternate],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([cardA, cardB], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("PRIMARY+ALTERNATE: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "PRIMARY+ALTERNATE: 2 candidatos extraídos (nenhuma das duas identidades é descartada)",
        result.candidatesExtracted === 2,
      );
      assert(
        "PRIMARY+ALTERNATE: 2 produtos NEW resolvidos (mesmo pricingCardMappingId, externalProductId distintos)",
        result.productsNew === 2,
      );
    }
    const resolveCalls = recorded.filter((c) => c.op === "resolveProductsBatch");
    assert(
      "PRIMARY+ALTERNATE: resolveProductsBatch recebeu as duas identidades (PRIMARY e ALTERNATE)",
      resolveCalls.some((c) =>
        (c.payload as ResolveProductsBatchInput[]).some((r) =>
          r.pricingSourceCardIdentityId === "identity-primary"
        )
      ) &&
        resolveCalls.some((c) =>
          (c.payload as ResolveProductsBatchInput[]).some((r) =>
            r.pricingSourceCardIdentityId === "identity-alternate"
          )
        ),
    );
  }

  // ── 12. SAME_PRICE_SKIP — preço idêntico ao último conhecido nunca gera observação ──
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-10", "card-10");
    const card = buildCard("card-10", [buildVariant("prod-10", 30)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      existingProducts: [{
        productId: "product-10",
        pricingCardMappingId: MAPPING_ID,
        pricingSourceCardIdentityId: "identity-10",
        externalProductId: "prod-10",
        sourcePrintingLabel: "Normal",
      }],
      latestObservationsByKey: new Map([
        ["product-10::condition-nm", {
          productId: "product-10",
          conditionId: "condition-nm",
          price: 30,
          observedAt: "2026-08-01T00:00:00.000Z",
        }],
      ]),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("SAME_PRICE_SKIP: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "SAME_PRICE_SKIP: zero observações escritas, 1 skip contabilizado",
        result.observationsWritten === 0 && result.observationsSkippedSamePrice === 1,
      );
    }
    assert(
      "SAME_PRICE_SKIP: insertObservations nunca chamado com linhas (zero writes reais)",
      recorded.filter((c) => c.op === "insertObservations").every((c) =>
        (c.payload as InsertObservationInput[]).length === 0
      ),
    );
  }

  // ── 13. LEASE_LOST — checkpoint recusado (lease expirada) nunca chama closeAttempt ──
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-11", "card-11");
    const card = buildCard("card-11", [buildVariant("prod-11", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      checkpointResults: [false],
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("LEASE_LOST: kind=LEASE_LOST", result.kind === "LEASE_LOST");
    assert(
      "LEASE_LOST: closeAttempt NUNCA chamado (o run não é mais nosso)",
      !recorded.some((c) => c.op === "closeAttempt"),
    );
  }

  // ── 14. Falha de leitura local pré-open (identidades/condições) -> FAILED sem tocar JustTCG
  {
    const recorded: RecordedCall[] = [];
    const port = buildFakeSetPort(recorded, {
      openAttemptResult: buildClaimed(),
      failListIdentities: true,
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient("fake-key", buildQueuedFetch([], fetchCalls), 10);
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Falha local pré-open: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("Falha local pré-open: runStatus=FAILED", result.runStatus === "FAILED");
      assert(
        "Falha local pré-open: pageOutcome=TRANSIENT_ERROR",
        result.pageOutcome === "TRANSIENT_ERROR",
      );
    }
    assert("Falha local pré-open: zero requisições à JustTCG", fetchCalls.count === 0);
  }

  // ── 15. AUTH_FAILURE da JustTCG -> FAILED, nunca continua para outras páginas ───────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-12", "card-12");
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([authFailureResponse()], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("AUTH_FAILURE: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("AUTH_FAILURE: pageOutcome=AUTH_FAILURE", result.pageOutcome === "AUTH_FAILURE");
      assert("AUTH_FAILURE: runStatus=FAILED", result.runStatus === "FAILED");
      assert("AUTH_FAILURE: zero páginas processadas", result.pagesProcessed === 0);
    }
    assert(
      "AUTH_FAILURE: checkpointPage nunca chamado para a página que falhou ao buscar",
      !recorded.some((c) => c.op === "checkpointPage"),
    );
  }

  // ── 16. TECHNICAL_FAILURE 404 -> SET_TERMINAL_ERROR (estrutural, pausa o Set) ───────
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-13", "card-13");
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([technicalFailureResponse(404)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("404: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("404: pageOutcome=SET_TERMINAL_ERROR", result.pageOutcome === "SET_TERMINAL_ERROR");
      assert(
        "404: runStatus=COMPLETED_WITH_ERRORS (nunca FAILED — o run em si não fracassou totalmente)",
        result.runStatus === "COMPLETED_WITH_ERRORS",
      );
    }
  }

  // ── 17. TECHNICAL_FAILURE não-404 (ex.: 500) -> TRANSIENT_ERROR (retry com backoff) ─
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-14", "card-14");
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([technicalFailureResponse(500)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("500: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert("500: pageOutcome=TRANSIENT_ERROR", result.pageOutcome === "TRANSIENT_ERROR");
      assert(
        "500: runStatus=COMPLETED_WITH_ERRORS",
        result.runStatus === "COMPLETED_WITH_ERRORS",
      );
    }
  }

  // ── 18. Telemetria — Set pequeno: 1 request real -> 1 pricing_sync_run_call SUCCESS ─
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-15", "card-15");
    const card = buildCard("card-15", [buildVariant("prod-15", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      closeAttemptResult: { finalOutcome: "SUCCESS", seenCount: 1, expectedCount: 1 },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse([card], false)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Telemetria Set pequeno: kind=CLOSED", result.kind === "CLOSED");
    const flushed = recorded
      .filter((c) => c.op === "insertSyncRunCalls")
      .flatMap((c) => (c.payload as { callLog: PriceRefreshCallLogEntry[] }).callLog);
    assert(
      "Telemetria Set pequeno: exatamente 1 entrada flushada, outcome=SUCCESS, http_status_code real (não-null)",
      flushed.length === 1 &&
        flushed[0].outcome === "SUCCESS" &&
        flushed[0].http_status_code === 200,
    );
    assert(
      "Telemetria Set pequeno: sequence_number=1 (1ª e única chamada real do client)",
      flushed[0].sequence_number === 1,
    );
  }

  // ── 19. Telemetria — Multi-página: sequence_number coerente/monotônico (1, 2) ─────
  {
    const recorded: RecordedCall[] = [];
    const identity1 = buildIdentity("identity-16", "card-16");
    const identity2 = buildIdentity("identity-17", "card-17");
    const cardsPage1 = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-filler2-${i}`, []),
    );
    cardsPage1[0] = buildCard("card-16", [buildVariant("prod-16", 10)]);
    const cardsPage2 = [buildCard("card-17", [buildVariant("prod-17", 20)])];
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity1, identity2],
      openAttemptResult: buildClaimed(),
      closeAttemptResult: { finalOutcome: "SUCCESS", seenCount: 2, expectedCount: 2 },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch(
        [successResponse(cardsPage1, true), successResponse(cardsPage2, false)],
        fetchCalls,
      ),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Telemetria multi-página: kind=CLOSED", result.kind === "CLOSED");
    const flushed = recorded
      .filter((c) => c.op === "insertSyncRunCalls")
      .flatMap((c) => (c.payload as { callLog: PriceRefreshCallLogEntry[] }).callLog);
    assert(
      "Telemetria multi-página: 2 entradas flushadas no total (checkpoints incrementais somados ao flush final, sem duplicar)",
      flushed.length === 2,
    );
    assert(
      "Telemetria multi-página: sequence_number monotônico 1, 2 (coerente por tentativa)",
      flushed.map((e) => e.sequence_number).join(",") === "1,2",
    );
    assert(
      "Telemetria multi-página: nenhuma reinserção da mesma sequence_number (uq_pricing_sync_run_call_run_sequence nunca violada)",
      new Set(flushed.map((e) => e.sequence_number)).size === flushed.length,
    );
  }

  // ── 20. Telemetria — BUDGET_STOPPED: entrada distinguível (http_status_code=null) ──
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-18", "card-18");
    const cardsFullPage = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-filler3-${i}`, []),
    );
    cardsFullPage[0] = buildCard("card-18", [buildVariant("prod-18", 10)]);
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse(cardsFullPage, true)], fetchCalls),
      1,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Telemetria BUDGET_STOPPED: kind=CLOSED", result.kind === "CLOSED");
    const flushed = recorded
      .filter((c) => c.op === "insertSyncRunCalls")
      .flatMap((c) => (c.payload as { callLog: PriceRefreshCallLogEntry[] }).callLog);
    assert(
      "Telemetria BUDGET_STOPPED: 2 entradas — 1 real (SUCCESS, http_status_code=200) + 1 BUDGET_STOPPED (http_status_code=null), claramente distinguíveis",
      flushed.length === 2 &&
        flushed.some((e) => e.outcome === "SUCCESS" && e.http_status_code === 200) &&
        flushed.some((e) => e.outcome === "BUDGET_STOPPED" && e.http_status_code === null),
    );
    if (result.kind === "CLOSED") {
      assert(
        "Telemetria BUDGET_STOPPED: requestsMade repassado a closeAttempt reconcilia com as calls reais (1), nunca conta o corte de orçamento",
        recorded.some((c) =>
          c.op === "closeAttempt" &&
          (c.payload as { requestsMade: number }).requestsMade === 1
        ),
      );
    }
  }

  // ── 21. Telemetria — requestsMade sempre reconcilia com calls reais (não-BUDGET_STOPPED)
  //       flushadas, também no caminho multi-página do cenário 19 ──────────────────────
  {
    const recorded: RecordedCall[] = [];
    const identity1 = buildIdentity("identity-19", "card-19");
    const identity2 = buildIdentity("identity-20", "card-20");
    const cardsPage1 = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-filler4-${i}`, []),
    );
    cardsPage1[0] = buildCard("card-19", [buildVariant("prod-19", 10)]);
    const cardsPage2 = [buildCard("card-20", [buildVariant("prod-20", 20)])];
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity1, identity2],
      openAttemptResult: buildClaimed(),
      closeAttemptResult: { finalOutcome: "SUCCESS", seenCount: 2, expectedCount: 2 },
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch(
        [successResponse(cardsPage1, true), successResponse(cardsPage2, false)],
        fetchCalls,
      ),
      10,
    );
    await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    const flushed = recorded
      .filter((c) => c.op === "insertSyncRunCalls")
      .flatMap((c) => (c.payload as { callLog: PriceRefreshCallLogEntry[] }).callLog);
    const realFlushed = flushed.filter((e) => e.outcome !== "BUDGET_STOPPED").length;
    assert(
      "Telemetria reconciliação: requestsMade do closeAttempt == quantidade de calls reais flushadas",
      recorded.some((c) =>
        c.op === "closeAttempt" &&
        (c.payload as { requestsMade: number }).requestsMade === realFlushed
      ),
    );
  }

  // ── 22. Telemetria — falha no flush FINAL (caminho sem checkpoint bem-sucedido antes,
  //       ex.: TECHNICAL_FAILURE 500) força runStatus=FAILED, nunca reinterpreta
  //       pageOutcome (que continua governando só pricing_set_refresh_state). Usa o mesmo
  //       cenário 17 (500 -> TRANSIENT_ERROR, normalmente runStatus=COMPLETED_WITH_ERRORS)
  //       como base — a única diferença observável deve ser o runStatus forçado.
  {
    const recorded: RecordedCall[] = [];
    const identity = buildIdentity("identity-21", "card-21");
    const port = buildFakeSetPort(recorded, {
      identityRows: [identity],
      openAttemptResult: buildClaimed(),
      failInsertSyncRunCalls: true,
    });
    const fetchCalls = { count: 0, urls: [] as string[] };
    const client = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([technicalFailureResponse(500)], fetchCalls),
      10,
    );
    const result = await executeSetRefreshAttempt(port, client, PRICING_SOURCE_ID);
    assert("Telemetria flush falho: kind=CLOSED", result.kind === "CLOSED");
    if (result.kind === "CLOSED") {
      assert(
        "Telemetria flush falho: pageOutcome permanece TRANSIENT_ERROR (mesmo do cenário 17, nunca reinterpretado pela falha de telemetria)",
        result.pageOutcome === "TRANSIENT_ERROR",
      );
      assert(
        "Telemetria flush falho: runStatus forçado a FAILED (diverge do cenário 17 sem falha de telemetria, que dá COMPLETED_WITH_ERRORS)",
        result.runStatus === "FAILED",
      );
      assert(
        "Telemetria flush falho: errorSummary=PRICING_SYNC_RUN_CALL_INSERT_FAILED",
        recorded.some((c) =>
          c.op === "closeAttempt" &&
          (c.payload as { errorSummary: string | null }).errorSummary ===
            "PRICING_SYNC_RUN_CALL_INSERT_FAILED"
        ),
      );
    }
  }

  // ── 23. RETOMADA REAL ENTRE DUAS INVOCAÇÕES (pedido de Fabrício, 2026-08-22) ────────
  //       Prova ponta-a-ponta do mecanismo de checkpoint/retomada com DUAS chamadas
  //       separadas e independentes a executeSetRefreshAttempt() sobre a MESMA instância
  //       de porta (estado em memória persistindo entre elas, exatamente como
  //       pricing_set_refresh_state faria entre duas invocações HTTP reais separadas às
  //       RPCs 3933) — cada chamada com seu próprio JustTcgClient/fetch, como duas
  //       invocações reais da Edge Function teriam.
  //
  //       Nenhum Set do catálogo real tem cartas suficientes na JustTCG para forçar
  //       BUDGET_STOPPED com SET_REQUEST_BUDGET=10 de produção (máximo observado: ~200
  //       cartas reais, contra >1000 necessárias) — Fabrício recusou tanto pausar Sets
  //       reais em massa quanto baixar a constante de produção só para o teste. Decisão:
  //       provar o mecanismo aqui, 100% offline, com requestBudget=1 SÓ no client de
  //       teste (nunca em SET_REQUEST_BUDGET/produção) e dados modelados no formato real
  //       de SWSHP (maior Set confirmado do catálogo — 300 cartas locais,
  //       external_set_id="swsh-sword-shield-promo-cards-pokemon" real).
  {
    const recorded: RecordedCall[] = [];
    const EXTERNAL_SET_ID_SWSHP = "swsh-sword-shield-promo-cards-pokemon";
    const identityPage1 = buildIdentity(
      "identity-swshp-1",
      "card-swshp-1",
      "PRIMARY",
      "mapping-swshp-1",
    );
    const identityPage2 = buildIdentity(
      "identity-swshp-2",
      "card-swshp-2",
      "PRIMARY",
      "mapping-swshp-2",
    );

    // Página 1 realista: 100 cartas (limite real da JustTCG), só 1 confirmada por nós —
    // as demais são promos/printings ainda não mapeados, mesma proporção esparsa do
    // piloto real anterior (SWSH4.5: 116 cartas vistas, 73 identidades confirmadas).
    const cardsPage1 = Array.from(
      { length: CARDS_PAGE_LIMIT },
      (_, i) => buildCard(`card-swshp-filler-${i}`, []),
    );
    cardsPage1[0] = buildCard("card-swshp-1", [buildVariant("prod-swshp-1", 8)]);
    const cardsPage2 = [buildCard("card-swshp-2", [buildVariant("prod-swshp-2", 12)])];

    const port = buildFakeSetPort(recorded, {
      identityRows: [identityPage1, identityPage2],
      openAttemptResult: buildClaimed({ externalSetId: EXTERNAL_SET_ID_SWSHP }),
      statefulResume: { expectedCount: 2 },
    });

    // ---- Invocação 1 — client próprio, budget=1 (SÓ neste client de teste) -----------
    const fetchCalls1 = { count: 0, urls: [] as string[] };
    const client1 = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse(cardsPage1, true)], fetchCalls1),
      1,
    );
    const result1 = await executeSetRefreshAttempt(port, client1, PRICING_SOURCE_ID);
    assert(
      "Retomada real (1ª invocação): checkpoint da página 1 persistido no offset=100",
      recorded.some((c) =>
        c.op === "checkpointPage" &&
        (c.payload as { newResumeOffset: number }).newResumeOffset === CARDS_PAGE_LIMIT
      ),
    );
    assert("Retomada real (1ª invocação): kind=CLOSED", result1.kind === "CLOSED");
    if (result1.kind === "CLOSED") {
      assert(
        "Retomada real (1ª invocação): pageOutcome=BUDGET_STOPPED (orçamento do teste esgotado)",
        result1.pageOutcome === "BUDGET_STOPPED",
      );
      assert(
        "Retomada real (1ª invocação): runStatus=COMPLETED (continuação normal, nunca FAILED)",
        result1.runStatus === "COMPLETED",
      );
      assert(
        "Retomada real (1ª invocação): 1 página processada, 1 produto NEW (card-swshp-1)",
        result1.pagesProcessed === 1 && result1.productsNew === 1 && result1.productsReused === 0,
      );
    }

    // ---- Invocação 2 — NOVO client (2ª chamada HTTP real simulada), MESMA porta ------
    const fetchCalls2 = { count: 0, urls: [] as string[] };
    const client2 = new JustTcgClient(
      "fake-key",
      buildQueuedFetch([successResponse(cardsPage2, false)], fetchCalls2),
      10,
    );
    const result2 = await executeSetRefreshAttempt(port, client2, PRICING_SOURCE_ID);
    assert(
      "Retomada real (2ª invocação): retoma exatamente do offset=100 — nunca reinicia do zero",
      offsetOf(fetchCalls2.urls[0]) === String(CARDS_PAGE_LIMIT),
    );
    assert("Retomada real (2ª invocação): kind=CLOSED", result2.kind === "CLOSED");
    if (result2.kind === "CLOSED") {
      assert(
        "Retomada real (2ª invocação): pageOutcome=NO_MORE_PAGES (ciclo concluído somando as 2 invocações)",
        result2.pageOutcome === "NO_MORE_PAGES",
      );
      assert(
        "Retomada real (2ª invocação): finalOutcome=SUCCESS",
        result2.finalOutcome === "SUCCESS",
      );
      assert(
        "Retomada real (2ª invocação): expectedCount=2 (as 2 identidades confirmadas do Set), seenCount cobre as duas (>=2) — cobertura completa, zero identidade perdida",
        result2.expectedCount === 2 && (result2.seenCount ?? 0) >= 2,
      );
      assert(
        "Retomada real (2ª invocação): 1 produto NEW nesta invocação (card-swshp-2) — nunca reprocessa o que a 1ª invocação já resolveu",
        result2.productsNew === 1 && result2.productsReused === 0,
      );
    }

    // ---- Zero perda/duplicidade global nas 2 invocações somadas ----------------------
    const resolveCalls = recorded.filter((c) => c.op === "resolveProductsBatch");
    const allResolvedExternalIds = resolveCalls.flatMap((c) =>
      (c.payload as ResolveProductsBatchInput[]).map((r) => r.externalProductId)
    );
    assert(
      "Retomada real: as 2 invocações resolveram produtos DISTINTOS e completos (prod-swshp-1 e prod-swshp-2), zero duplicidade/reparenting",
      allResolvedExternalIds.length === 2 &&
        new Set(allResolvedExternalIds).size === 2 &&
        allResolvedExternalIds.includes("prod-swshp-1") &&
        allResolvedExternalIds.includes("prod-swshp-2"),
    );
    assert(
      "Retomada real: 2 syncRunId distintos (1 por invocação) — mesma disciplina da RPC real (1 pricing_sync_run por open_pricing_set_refresh_attempt)",
      new Set(
        recorded.filter((c) => c.op === "closeAttempt").map((c) =>
          (c.payload as { syncRunId: string }).syncRunId
        ),
      ).size === 2,
    );
  }

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — mesma disciplina de
// pricing-justtcg-refresh.test.ts: guardado por `typeof Deno !== "undefined"` para
// permanecer importável a partir de Node (validação offline no sandbox). 100% offline —
// nenhuma permissão --allow-* necessária.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "set-refresh-core — suíte offline do dispatcher durável por Set (P15, 2026-08-22)",
    async () => {
      const result = await runSetRefreshCoreTests();
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
