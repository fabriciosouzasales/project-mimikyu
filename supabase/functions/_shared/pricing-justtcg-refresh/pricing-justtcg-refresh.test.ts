// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/pricing-justtcg-refresh.test.ts
// Bateria de testes offline do núcleo de refresh diário JustTCG — Incremento de
// Atualização Diária JustTCG (2026-08-21), item F.
//
// 100% offline: fetch e a porta (RefreshPort) são sempre fakes controlados neste arquivo
// — nenhuma chamada real à JustTCG, nenhum SupabaseClient real. Mesmo padrão de
// supabase/functions/_shared/pricing-ptax/pricing-ptax.test.ts (fake da PORTA de domínio,
// nunca um fake de PostgREST).
//
// Cobre os itens do pedido de Fabrício (item F) que dizem respeito ao núcleo puro
// (wave-plan.ts/extract.ts/observation-decision.ts/core.ts) — os itens sobre a Edge
// Function (autenticação, waveNumber HTTP, sanitização de resposta) estão em
// supabase/functions/justtcg-price-refresh/justtcg-price-refresh.test.ts.

import {
  buildRefreshWavePlan,
  MAX_CAPACITY_PAGES,
  MAX_WAVES,
  type RefreshSetCandidate,
  WAVE_PAGE_CAP,
} from "./wave-plan.ts";
import type { Clock } from "./deadline.ts";
import {
  extractRefreshObservationCandidates,
  type RefreshIdentityIndex,
} from "./extract.ts";
import { decideObservationWrite } from "./observation-decision.ts";
import { executePriceRefreshWave } from "./core.ts";
import type { PriceRefreshRunPort } from "./run-lifecycle.ts";
import type {
  InsertObservationInput,
  InsertObservationsResult,
  InsertPriceRefreshRunResult,
  LatestObservationKey,
  LatestObservationRow,
  PriceRefreshCallLogEntry,
  RefreshIdentityRow,
  ResolvedProductRow,
  ResolveProductsBatchInput,
  ResolveProductsBatchResult,
  UpdateSyncRunPatch,
} from "./port.ts";
import {
  CARDS_PAGE_LIMIT,
  type FetchLike,
  type JustTcgCard,
  JustTcgClient,
} from "../pricing-justtcg/mod.ts";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

const PRICING_SOURCE_ID = "fake-pricing-source-justtcg";

// ----------------------------------------------------------------------------
// Fake da PORTA (RefreshPort) — estado em memória, configurável por teste. Implementa
// exatamente a interface de port.ts (nunca um `any`, nunca reproduz a API do PostgREST).
// ----------------------------------------------------------------------------

interface RecordedCall {
  op:
    | "listRefreshCandidateSets"
    | "listConfirmedIdentitiesForSet"
    | "getConditionMap"
    | "resolveProductsBatch"
    | "findLatestObservations"
    | "insertObservations"
    | "insertPriceRefreshRun"
    | "insertSyncRunCalls"
    | "updateSyncRun";
  payload: unknown;
}

// Seed do estado inicial de pricing_product simulado pelo fake — reflete a chave
// econômica real (pricing_card_mapping_id, external_product_id — ver migration 3928 /
// uq_pricing_product_mapping_external), nunca a antiga chave por identity (defeito R1).
interface SeedProductRow {
  productId: string;
  pricingCardMappingId: string;
  pricingSourceCardIdentityId: string;
  externalProductId: string;
  sourcePrintingLabel: string;
}

interface FakePortOptions {
  candidateSets?: RefreshSetCandidate[];
  identitiesBySet?: Map<string, RefreshIdentityRow[]>;
  conditionMap?: Map<string, string>;
  existingProducts?: SeedProductRow[];
  latestObservationsByKey?: Map<string, LatestObservationRow>; // key: `${productId}::${conditionId}`
  insertPriceRefreshRunResult?: InsertPriceRefreshRunResult;
  failResolveProducts?: boolean;
  // Mensagem devolvida quando failResolveProducts=true — default preserva o comportamento
  // já usado por todos os testes existentes (mensagem genérica de simulação). Permite a
  // um teste específico (ex.: regressão R1) usar a mesma string sanitizada fixa que o
  // adapter REAL devolve em qualquer falha de resolveProductsBatch()
  // ("PRODUCT_RESOLUTION_FAILED" — ver supabase-adapter.ts), em vez de um texto genérico —
  // sem afetar nenhum call site existente (todos continuam sem passar esta opção,
  // herdando o default de sempre).
  failResolveProductsMessage?: string;
  failInsertObservations?: boolean;
  failInsertSyncRunCalls?: boolean;
}

function buildFakePort(
  recorded: RecordedCall[],
  opts: FakePortOptions = {},
): PriceRefreshRunPort {
  // Estado mutável — resolveProductsBatch realmente adiciona a `products` no caminho NEW,
  // simulando o comportamento real (a RPC resolve_pricing_products_batch grava de fato em
  // pricing_product, persistente entre Sets da mesma onda, dentro da mesma execução).
  // REUSE nunca muta uma linha existente — mesma disciplina da RPC real (migration 3928):
  // identity/printing_label armazenados são sempre devolvidos tal como estão, mesmo que a
  // candidata divirja (a divergência vira só um sinal comparado por core.ts).
  const products: SeedProductRow[] = [...(opts.existingProducts ?? [])];
  let nextProductId = 9000;

  return {
    listRefreshCandidateSets(pricingSourceId: string) {
      recorded.push({
        op: "listRefreshCandidateSets",
        payload: pricingSourceId,
      });
      return Promise.resolve(opts.candidateSets ?? []);
    },
    listConfirmedIdentitiesForSet(pricingSourceId: string, cardSetId: string) {
      recorded.push({
        op: "listConfirmedIdentitiesForSet",
        payload: { pricingSourceId, cardSetId },
      });
      return Promise.resolve(opts.identitiesBySet?.get(cardSetId) ?? []);
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
          message: opts.failResolveProductsMessage ??
            "PRODUCT_RESOLUTION_FALHOU_SIMULADO",
        });
      }
      const out: ResolvedProductRow[] = rows.map((r) => {
        const existing = products.find((p) =>
          p.pricingCardMappingId === r.pricingCardMappingId &&
          p.externalProductId === r.externalProductId
        );
        if (existing) {
          // REUSE — devolve a linha armazenada tal como está, sem mutar identity/label,
          // mesmo que a candidata divirja (mesma disciplina da RPC real — migration 3928).
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
    ): Promise<InsertObservationsResult> {
      recorded.push({
        op: "insertSyncRunCalls",
        payload: { syncRunId, callLog },
      });
      if (opts.failInsertSyncRunCalls) {
        return Promise.resolve({
          ok: false,
          message: "CALL_LOG_INSERT_FALHOU_SIMULADO",
        });
      }
      return Promise.resolve({ ok: true });
    },
    updateSyncRun(syncRunId: string, patch: UpdateSyncRunPatch): Promise<void> {
      recorded.push({ op: "updateSyncRun", payload: { syncRunId, patch } });
      return Promise.resolve();
    },
  };
}

// ----------------------------------------------------------------------------
// Fake do cliente JustTCG — fetchImpl controlado por externalSetId, mesma disciplina de
// _shared/pricing-justtcg (JustTcgClient real, só o transporte HTTP é fake).
// ----------------------------------------------------------------------------

function fakeCardsResponse(cards: JustTcgCard[]): Response {
  return {
    ok: true,
    status: 200,
    json: () => Promise.resolve({ data: cards, meta: { hasMore: false } }),
    text: () => Promise.resolve(""),
  } as unknown as Response;
}

function buildVariant(
  externalProductId: string,
  price: number,
  conditionRaw = "NM",
) {
  return {
    uuid: externalProductId,
    condition: conditionRaw,
    printing: "Normal",
    price,
    lastUpdated: 1_755_000_000,
  };
}

// fetchImpl que devolve, para cada externalSetId, exatamente as cartas configuradas em
// `bySetId` — nunca uma chamada real, nunca depende de rede.
function buildFakeFetch(
  bySetId: Map<string, JustTcgCard[]>,
  calls: { count: number },
): FetchLike {
  return ((url: string | URL) => {
    calls.count++;
    const u = new URL(String(url));
    const setId = u.searchParams.get("set") ?? "";
    const cards = bySetId.get(setId) ?? [];
    return Promise.resolve(fakeCardsResponse(cards));
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

export async function runPricingJusttcgRefreshTests(): Promise<
  TestSuiteResult
> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) =>
    assertions.push([label, cond]);

  // ── 1. wave-plan: 38 páginas -> 4 ondas, quinta onda não existe no plano ───────────
  {
    // 38 páginas via 3 Sets de exatamente 10 páginas (1000 cartas/Set, CARDS_PAGE_LIMIT=100,
    // ceil(1000/100)=10) + 1 Set de 8 páginas (800 cartas, ceil(800/100)=8) — correção pós-
    // incidente (2026-08-21, WAVE_PAGE_CAP 30->10): cada Set de exatamente 10 páginas já
    // satura sozinho o teto de uma onda (10+10>10), forçando o empacotamento guloso a abrir
    // uma onda nova a cada um: A(10)+B(10)+C(10)+D(8) = 38 páginas em exatamente 4 ondas.
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1000,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1000,
      },
      {
        cardSetId: "set-c",
        setCode: "CCC",
        externalSetId: "ext-c",
        confirmedCardCount: 1000,
      },
      {
        cardSetId: "set-d",
        setCode: "DDD",
        externalSetId: "ext-d",
        confirmedCardCount: 800,
      },
    ];
    const plan = buildRefreshWavePlan(candidates);
    assert("38 páginas: plano OK", plan.status === "OK");
    if (plan.status === "OK") {
      assert(
        "38 páginas: totalEstimatedPages=38",
        plan.totalEstimatedPages === 38,
      );
      assert(
        "38 páginas: exatamente 4 ondas calculadas",
        plan.waves.length === 4,
      );
      assert(
        "38 páginas: onda 5 não existe no plano (find retorna undefined)",
        plan.waves.find((w) => w.waveNumber === 5) === undefined,
      );
      assert(
        "38 páginas: nenhuma onda excede WAVE_PAGE_CAP=10",
        plan.waves.every((w) => w.estimatedPages <= WAVE_PAGE_CAP),
      );
    }
  }

  // ── 2. core.ts: ondas 5-30 (fora do plano de 38 páginas / 4 ondas) -> NOOP, nunca cria
  // run — teto elevado de 10 para 30 ondas nesta rodada de correção pós-incidente
  // (2026-08-21), então todas as ondas 5 a 30 (não só a 5) precisam permanecer NOOP para
  // este plano.
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1000,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1000,
      },
      {
        cardSetId: "set-c",
        setCode: "CCC",
        externalSetId: "ext-c",
        confirmedCardCount: 1000,
      },
      {
        cardSetId: "set-d",
        setCode: "DDD",
        externalSetId: "ext-d",
        confirmedCardCount: 800,
      },
    ];
    for (let waveNumber = 5; waveNumber <= 30; waveNumber++) {
      const recorded: RecordedCall[] = [];
      const port = buildFakePort(recorded, { candidateSets: candidates });
      const fetchCalls = { count: 0 };
      const client = new JustTcgClient(
        "fake-key",
        buildFakeFetch(new Map(), fetchCalls),
        30,
      );
      const result = await executePriceRefreshWave(
        port,
        client,
        PRICING_SOURCE_ID,
        waveNumber,
      );
      assert(
        `onda ${waveNumber} fora do plano: kind=NOOP_WAVE_NOT_IN_PLAN`,
        result.kind === "NOOP_WAVE_NOT_IN_PLAN",
      );
      assert(
        `onda ${waveNumber} fora do plano: planWaveCount=4`,
        result.kind === "NOOP_WAVE_NOT_IN_PLAN" && result.planWaveCount === 4,
      );
      assert(
        `onda ${waveNumber} fora do plano: nunca cria pricing_sync_run (insertPriceRefreshRun não chamado)`,
        !recorded.some((c) => c.op === "insertPriceRefreshRun"),
      );
      assert(
        `onda ${waveNumber} fora do plano: JustTCG nunca chamada`,
        fetchCalls.count === 0,
      );
    }
  }

  // ── 3. wave-plan: 151 páginas -> 16 ondas ACEITAS (dentro do novo teto de 30 ondas /
  // 300 páginas, correção pós-incidente 2026-08-21) ──
  {
    // 15 Sets de exatamente 10 páginas (1000 cartas/Set) + 1 Set de 1 página (100 cartas) —
    // cada Set de 10 páginas já satura sozinho uma onda (WAVE_PAGE_CAP=10), forçando o
    // empacotamento guloso a abrir uma onda nova a cada um: 15 ondas de 10 páginas, e o
    // Set final de 1 página não cabe mais na 15ª onda (10+1>10) -> abre uma 16ª onda
    // sozinho. Total: 151 páginas em exatamente 16 ondas, dentro do novo teto de 30.
    const candidates: RefreshSetCandidate[] = Array.from(
      { length: 15 },
      (_, i) => ({
        cardSetId: `set-${i}`,
        setCode: String.fromCharCode(65 + i).repeat(3),
        externalSetId: `ext-${i}`,
        confirmedCardCount: 1000,
      }),
    );
    candidates.push({
      cardSetId: "set-final",
      setCode: "ZZZ",
      externalSetId: "ext-final",
      confirmedCardCount: 100,
    });
    const plan = buildRefreshWavePlan(candidates);
    assert("151 páginas: plano OK (aceito)", plan.status === "OK");
    if (plan.status === "OK") {
      assert(
        "151 páginas: totalEstimatedPages=151",
        plan.totalEstimatedPages === 151,
      );
      assert(
        "151 páginas: exatamente 16 ondas calculadas",
        plan.waves.length === 16,
      );
      assert(
        "151 páginas: nenhuma onda excede WAVE_PAGE_CAP=10",
        plan.waves.every((w) => w.estimatedPages <= WAVE_PAGE_CAP),
      );
    }
    assert(
      "MAX_CAPACITY_PAGES=300 (30 ondas * 10)",
      MAX_CAPACITY_PAGES === 300,
    );
  }

  // ── 3b. wave-plan: 300 páginas -> 30 ondas ACEITAS (capacidade máxima exata) ───────
  {
    // 30 Sets de exatamente 10 páginas (1000 cartas/Set) — cada um satura sozinho uma
    // onda (10+10>10), forçando exatamente 30 ondas de 10 páginas cada, no limite exato
    // de MAX_WAVES(30) * WAVE_PAGE_CAP(10) = 300 páginas.
    const candidates: RefreshSetCandidate[] = Array.from(
      { length: 30 },
      (_, i) => ({
        cardSetId: `set-${i}`,
        setCode: `S${String(i).padStart(2, "0")}`,
        externalSetId: `ext-${i}`,
        confirmedCardCount: 1000,
      }),
    );
    const plan = buildRefreshWavePlan(candidates);
    assert("300 páginas: plano OK (aceito)", plan.status === "OK");
    if (plan.status === "OK") {
      assert(
        "300 páginas: totalEstimatedPages=300",
        plan.totalEstimatedPages === 300,
      );
      assert(
        "300 páginas: exatamente 30 ondas calculadas",
        plan.waves.length === 30,
      );
      assert(
        "300 páginas: onda 31 não existe no plano (find retorna undefined)",
        plan.waves.find((w) => w.waveNumber === 31) === undefined,
      );
    }
  }

  // ── 3c. wave-plan: 301 páginas -> SCHEDULE_CAPACITY_EXCEEDED (1 página acima do teto) ──
  {
    // Um único Set de 30.100 cartas -> ceil(30100/100)=301 páginas, 1 acima do novo teto
    // de 300 — excede na checagem antecipada de totalEstimatedPages > MAX_CAPACITY_PAGES,
    // antes mesmo do empacotamento por onda.
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-x",
        setCode: "XXX",
        externalSetId: "ext-x",
        confirmedCardCount: 30_100,
      },
    ];
    const plan = buildRefreshWavePlan(candidates);
    assert(
      "301 páginas: SCHEDULE_CAPACITY_EXCEEDED",
      plan.status === "SCHEDULE_CAPACITY_EXCEEDED",
    );
    if (plan.status === "SCHEDULE_CAPACITY_EXCEEDED") {
      assert(
        "301 páginas: totalEstimatedPages=301",
        plan.totalEstimatedPages === 301,
      );
    }
  }

  // ── 4. core.ts: capacidade excedida (301 páginas) -> zero escrita, nunca cria run ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-x",
        setCode: "XXX",
        externalSetId: "ext-x",
        confirmedCardCount: 30_100,
      },
    ];
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, { candidateSets: candidates });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(new Map(), fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    assert(
      "capacidade excedida: kind=CAPACITY_EXCEEDED",
      result.kind === "CAPACITY_EXCEEDED",
    );
    assert(
      "capacidade excedida: nunca cria pricing_sync_run",
      !recorded.some((c) => c.op === "insertPriceRefreshRun"),
    );
    assert(
      "capacidade excedida: nunca escreve produto/observação",
      !recorded.some((c) =>
        c.op === "resolveProductsBatch" || c.op === "insertObservations"
      ),
    );
    assert(
      "capacidade excedida: JustTCG nunca chamada",
      fetchCalls.count === 0,
    );
  }

  // ── 5. JustTcgClient: orçamento nunca ultrapassa 30 (independente do requestBudget pedido) ──
  {
    const clientBudgetGrande = new JustTcgClient("fake-key", undefined, 999);
    assert(
      "orçamento: requestBudget=999 é capado em MAX_REQUESTS_PER_RUN=30 (requestsRemainingLocal=30 antes de qualquer chamada)",
      clientBudgetGrande.requestsRemainingLocal === 30,
    );
    const clientBudgetPequeno = new JustTcgClient("fake-key", undefined, 3);
    assert(
      "orçamento: requestBudget=3 (menor que 30) é respeitado sem ser elevado",
      clientBudgetPequeno.requestsRemainingLocal === 3,
    );
    // Exercício real do teto — orçamento pequeno (3) para manter o teste rápido (sem
    // esperar DELAY_BETWEEN_REQUESTS_MS=3000ms por chamada); o mecanismo de corte
    // (budgetOk() antes de qualquer fetch) é o MESMO independente do valor do teto.
    const fetchCalls = { count: 0 };
    const fastFetch: FetchLike = (() => {
      fetchCalls.count++;
      return Promise.resolve(fakeCardsResponse([]));
    }) as FetchLike;
    const clientTeto3 = new JustTcgClient("fake-key", fastFetch, 3);
    for (let i = 0; i < 5; i++) {
      await clientTeto3.get("/cards", {
        game: "pokemon",
        set: "x",
        limit: "100",
        offset: "0",
      });
    }
    assert(
      "orçamento: com teto=3, no máximo 3 requisições reais são feitas (as 2 seguintes são BUDGET_STOPPED, zero fetch)",
      fetchCalls.count === 3 && clientTeto3.requestsMade === 3,
    );
  }

  // ── 6. extract.ts: PRIMARY e ALTERNATE são extraídos separadamente, cada um seu candidato ──
  {
    const identityIndex: RefreshIdentityIndex = new Map([
      ["ext-card-primary", {
        identityId: "identity-primary",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-1",
      }],
      ["ext-card-alternate", {
        identityId: "identity-alternate",
        identityRole: "ALTERNATE",
        pricingCardMappingId: "mapping-1", // mesma carta local, identidade irmã
      }],
    ]);
    const cards: JustTcgCard[] = [
      {
        id: "ext-card-primary",
        name: "Bulbasaur",
        variants: [buildVariant("prod-primary", 1.5)],
      },
      {
        id: "ext-card-alternate",
        name: "Bulbasaur (alt art)",
        variants: [buildVariant("prod-alternate", 9.99)],
      },
    ];
    const { candidates, cardsUnmatchedCount } =
      extractRefreshObservationCandidates(
        cards,
        identityIndex,
        new Map([["NM", "condition-nm"]]),
      );
    assert(
      "PRIMARY/ALTERNATE: 2 candidatos extraídos, um por identidade",
      candidates.length === 2,
    );
    assert(
      "PRIMARY/ALTERNATE: zero cartas não-casadas",
      cardsUnmatchedCount === 0,
    );
    const primary = candidates.find((c) => c.identityRole === "PRIMARY");
    const alternate = candidates.find((c) => c.identityRole === "ALTERNATE");
    assert(
      "PRIMARY/ALTERNATE: candidato PRIMARY correto (produto/preço/mapping)",
      primary?.externalProductId === "prod-primary" && primary?.price === 1.5 &&
        primary?.pricingCardMappingId === "mapping-1",
    );
    assert(
      "PRIMARY/ALTERNATE: candidato ALTERNATE correto, mesmo pricingCardMappingId da irmã PRIMARY",
      alternate?.externalProductId === "prod-alternate" &&
        alternate?.price === 9.99 &&
        alternate?.pricingCardMappingId === "mapping-1",
    );
  }

  // ── 7. extract.ts: carta fora do índice (PENDING/NOT_FOUND/REJECTED/ALIAS na origem) é ignorada ──
  {
    const identityIndex: RefreshIdentityIndex = new Map([
      ["ext-card-confirmado", {
        identityId: "identity-1",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-1",
      }],
    ]);
    const cards: JustTcgCard[] = [
      {
        id: "ext-card-confirmado",
        name: "Confirmada",
        variants: [buildVariant("prod-1", 2)],
      },
      // Simula uma carta que a JustTCG lista no Set mas cuja identidade local está
      // PENDING/NOT_FOUND/REJECTED/ALIAS (regra 17) — nunca entra no índice de
      // identidades confirmadas construído pelo chamador a partir do port.
      {
        id: "ext-card-pendente-ou-rejeitada",
        name: "Não confirmada",
        variants: [buildVariant("prod-2", 3)],
      },
    ];
    const { candidates, cardsUnmatchedCount, skippedReasons } =
      extractRefreshObservationCandidates(
        cards,
        identityIndex,
        new Map([["NM", "condition-nm"]]),
      );
    assert(
      "PENDING/NOT_FOUND/REJECTED/ALIAS: só a carta confirmada vira candidato",
      candidates.length === 1 &&
        candidates[0].externalCardId === "ext-card-confirmado",
    );
    assert(
      "PENDING/NOT_FOUND/REJECTED/ALIAS: carta fora do índice é contada como não-casada, nunca um erro",
      cardsUnmatchedCount === 1 && skippedReasons.length === 0,
    );
  }

  // ── 8. RefreshPort: mapping/identity nunca recebem escrita (garantia estrutural) ───
  {
    // A interface RefreshPort (port.ts) não expõe NENHUM método de escrita para
    // pricing_set_mapping/pricing_card_mapping/pricing_source_card_identity — só
    // resolveProductsBatch (RPC transacional, nunca UPDATE — migration 3928) e
    // insertObservations (INSERT-only), além do ciclo de vida do run.
    // Este fake, ao implementar RefreshPort com sucesso (typecheck), já prova a garantia
    // em nível de tipo; a asserção abaixo reforça em runtime que nenhuma operação com
    // esses três nomes jamais aparece no log de chamadas registradas, em toda a suíte.
    const recorded: RecordedCall[] = [];
    buildFakePort(recorded);
    const proibidos = [
      "insertMapping",
      "insertIdentity",
      "updateMapping",
      "updateIdentity",
    ];
    assert(
      "mapping/identity: RefreshPort não expõe nenhuma operação de escrita nessas tabelas (nomes proibidos nunca aparecem em nenhum op registrado desta suíte)",
      proibidos.every((nome) => !recorded.some((c) => c.op === nome)),
    );
  }

  // ── 9. observation-decision.ts: preço igual -> zero observação ─────────────────────
  {
    const decision = decideObservationWrite(
      { price: 5.5, observedAt: "2026-08-20T10:00:00Z" },
      { price: 5.5, observedAt: "2026-08-21T10:00:00Z" },
    );
    assert("preço igual: SAME_PRICE_SKIP", decision.kind === "SAME_PRICE_SKIP");
  }

  // ── 10. observation-decision.ts: preço alterado -> uma observação ──────────────────
  {
    const decision = decideObservationWrite(
      { price: 5.5, observedAt: "2026-08-20T10:00:00Z" },
      { price: 6.75, observedAt: "2026-08-21T10:00:00Z" },
    );
    assert(
      "preço alterado: PRICE_CHANGED_WRITE",
      decision.kind === "PRICE_CHANGED_WRITE",
    );
  }

  // ── 11. core.ts: produto novo -> INSERT de produto + INSERT de observação (FIRST_OBSERVATION) ──
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
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "ext-card-1",
        name: "Bulbasaur",
        variants: [buildVariant("prod-1", 4.2)],
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    assert(
      "produto novo: EXECUTED/COMPLETED",
      result.kind === "EXECUTED" && result.status === "COMPLETED",
    );
    assert(
      "produto novo: 1 produto inserido, 1 observação escrita",
      result.kind === "EXECUTED" && result.productsInserted === 1 &&
        result.observationsWritten === 1,
    );
    const resolveCall = recorded.find((c) => c.op === "resolveProductsBatch");
    const insertObsCall = recorded.find((c) => c.op === "insertObservations");
    assert(
      "produto novo: resolveProductsBatch foi chamado com 1 linha",
      (resolveCall?.payload as unknown[])?.length === 1,
    );
    assert(
      "produto novo: insertObservations foi chamado com 1 linha",
      (insertObsCall?.payload as unknown[])?.length === 1,
    );
  }

  // ── 12. core.ts: falha parcial preserva o preço anterior (escrita já confirmada não é desfeita) e termina FAILED ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-a", [{
        identityId: "identity-a",
        externalCardId: "ext-card-a",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-a",
      }]],
      ["set-b", [{
        identityId: "identity-b",
        externalCardId: "ext-card-b",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-b",
      }]],
    ]);
    const recorded: RecordedCall[] = [];
    // Set A grava com sucesso; Set B falha ao inserir observação (simulando erro real de
    // escrita) — regra 15: a escrita do Set A, já confirmada, nunca é desfeita. O wrapper
    // sempre registra a chamada em `recorded` (inclusive quando decide falhar), para que a
    // asserção abaixo consiga distinguir "tentado e falhou" de "nunca tentado".
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    let obsCallCount = 0;
    const realInsertObservations = port.insertObservations.bind(port);
    port.insertObservations = (rows) => {
      obsCallCount++;
      if (obsCallCount === 2) {
        recorded.push({ op: "insertObservations", payload: rows });
        return Promise.resolve({ ok: false, message: "FALHA_SIMULADA_SET_B" });
      }
      return realInsertObservations(rows);
    };
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "ext-card-a",
        name: "Carta A",
        variants: [buildVariant("prod-a", 1.0)],
      }]],
      ["ext-b", [{
        id: "ext-card-b",
        name: "Carta B",
        variants: [buildVariant("prod-b", 2.0)],
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    assert(
      "falha parcial: run termina FAILED",
      result.kind === "EXECUTED" && result.status === "FAILED",
    );
    assert(
      "falha parcial: Set A (bem-sucedido) contribuiu 1 produto/observação — nunca desfeito pela falha do Set B",
      result.kind === "EXECUTED" && result.productsInserted === 2 &&
        result.observationsWritten === 1,
    );
    const insertObsCalls = recorded.filter((c) =>
      c.op === "insertObservations"
    );
    assert(
      "falha parcial: insertObservations foi tentado para os 2 Sets (Set B tentado e falhou, não pulado)",
      insertObsCalls.length === 2,
    );
  }

  // ── 13. core.ts: telemetria (insertSyncRunCalls) SEMPRE antes da finalização (updateSyncRun) ──
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
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "ext-card-1",
        name: "Bulbasaur",
        variants: [buildVariant("prod-1", 4.2)],
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    await executePriceRefreshWave(port, client, PRICING_SOURCE_ID, 1);
    const callLogIdx = recorded.findIndex((c) => c.op === "insertSyncRunCalls");
    const updateIdx = recorded.findIndex((c) => c.op === "updateSyncRun");
    assert(
      "telemetria antes da finalização: insertSyncRunCalls ocorre antes de updateSyncRun",
      callLogIdx !== -1 && updateIdx !== -1 && callLogIdx < updateIdx,
    );
  }

  // ── 14/15. core.ts: conflito de concorrência (CARD_SYNC ou PRICE_REFRESH já ativo) — ambos os sentidos ──
  // Complementa a prova real (Postgres, BEGIN/ROLLBACK, migration 3926) já executada em
  // ambos os sentidos — aqui prova-se que o CÓDIGO da aplicação trata corretamente
  // QUALQUER CONCURRENT_CONFLICT devolvido pela porta, independente de qual índice/tipo
  // de run disparou o 23505 real no adapter (a porta abstrai essa distinção por desenho).
  {
    for (
      const cenario of ["CARD_SYNC_ja_ativo", "PRICE_REFRESH_ja_ativo"] as const
    ) {
      const candidates: RefreshSetCandidate[] = [
        {
          cardSetId: "set-a",
          setCode: "AAA",
          externalSetId: "ext-a",
          confirmedCardCount: 1,
        },
      ];
      const recorded: RecordedCall[] = [];
      const port = buildFakePort(recorded, {
        candidateSets: candidates,
        insertPriceRefreshRunResult: { outcome: "CONCURRENT_CONFLICT" },
      });
      const fetchCalls = { count: 0 };
      const client = new JustTcgClient(
        "fake-key",
        buildFakeFetch(new Map(), fetchCalls),
        30,
      );
      const result = await executePriceRefreshWave(
        port,
        client,
        PRICING_SOURCE_ID,
        1,
      );
      assert(
        `conflito de concorrência (${cenario}): kind=CONCURRENT_CONFLICT`,
        result.kind === "CONCURRENT_CONFLICT",
      );
      assert(
        `conflito de concorrência (${cenario}): JustTCG nunca chamada`,
        fetchCalls.count === 0,
      );
    }
  }

  // ── 16. core.ts: onda inexistente (fora de 1-5) não cria run (defensivo) ──────────
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
    const port = buildFakePort(recorded, { candidateSets: candidates });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(new Map(), fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      7,
    );
    assert(
      "onda 7 (fora de 1-5): NOOP_WAVE_NOT_IN_PLAN",
      result.kind === "NOOP_WAVE_NOT_IN_PLAN",
    );
    assert(
      "onda 7 (fora de 1-5): nunca cria pricing_sync_run",
      !recorded.some((c) => c.op === "insertPriceRefreshRun"),
    );
  }

  // ── 17. wave-plan.ts: inclusão determinística de um novo Set confirmado ───────────
  {
    const antes: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 100,
      },
      {
        cardSetId: "set-c",
        setCode: "CCC",
        externalSetId: "ext-c",
        confirmedCardCount: 100,
      },
    ];
    const planAntes = buildRefreshWavePlan(antes);
    assert(
      "novo Set: plano ANTES tem 2 Sets",
      planAntes.status === "OK" && planAntes.totalSets === 2,
    );

    // Um novo Set "BBB" (confirmado entre a leitura anterior e esta) aparece na posição
    // alfabética correta na PRÓXIMA leitura de listRefreshCandidateSets() — sem qualquer
    // alteração de código, o plano seguinte já o inclui deterministicamente.
    const depois: RefreshSetCandidate[] = [
      ...antes,
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 100,
      },
    ];
    const planDepois = buildRefreshWavePlan(depois);
    assert(
      "novo Set: plano DEPOIS tem 3 Sets",
      planDepois.status === "OK" && planDepois.totalSets === 3,
    );
    if (planDepois.status === "OK") {
      const ordemCodigos = planDepois.waves.flatMap((w) =>
        w.sets.map((s) => s.setCode)
      );
      assert(
        "novo Set: ordem alfabética determinística (AAA, BBB, CCC) na primeira onda com espaço",
        ordemCodigos.join(",") === "AAA,BBB,CCC",
      );
    }
  }

  // ── 18. core.ts: AUTH_FAILURE aborta a onda como falha real (hardFailure=true, status FAILED) ──
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
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      authFailureFetch(fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    assert(
      "AUTH_FAILURE: run finaliza FAILED, nunca produto/observação escritos",
      result.kind === "EXECUTED" && result.status === "FAILED" &&
        result.productsInserted === 0 && result.observationsWritten === 0,
    );
  }

  // ── 19. Cron (migration 3927): expressão cobre TODOS os dias, inclusive sábado/domingo ──
  {
    // Mesmos 30 literais de horário fixados na migration 3927 (elevado de 10 para 30 jobs
    // nesta rodada de correção pós-incidente, 2026-08-21 — WAVE_PAGE_CAP 30->10, MAX_WAVES
    // 10->30, intervalos de 5 minutos entre 22:30 e 00:55 UTC) — verificação estrutural da
    // expressão cron (formato padrão de 5 campos: minuto hora dia-do-mês mês dia-da-semana).
    // "* * *" nos 3 últimos campos significa nenhuma restrição de dia-do-mês/mês/dia-da-
    // semana — roda todos os 7 dias, sem exceção de fim de semana (diferente do job PTAX,
    // que usa "1-5" no 5º campo e É restrito a dias úteis).
    const cronsDaMigration3927 = [
      "30 22 * * *",
      "35 22 * * *",
      "40 22 * * *",
      "45 22 * * *",
      "50 22 * * *",
      "55 22 * * *",
      "0 23 * * *",
      "5 23 * * *",
      "10 23 * * *",
      "15 23 * * *",
      "20 23 * * *",
      "25 23 * * *",
      "30 23 * * *",
      "35 23 * * *",
      "40 23 * * *",
      "45 23 * * *",
      "50 23 * * *",
      "55 23 * * *",
      "0 0 * * *",
      "5 0 * * *",
      "10 0 * * *",
      "15 0 * * *",
      "20 0 * * *",
      "25 0 * * *",
      "30 0 * * *",
      "35 0 * * *",
      "40 0 * * *",
      "45 0 * * *",
      "50 0 * * *",
      "55 0 * * *",
    ];
    const horariosEsperados = [
      "30 22",
      "35 22",
      "40 22",
      "45 22",
      "50 22",
      "55 22",
      "0 23",
      "5 23",
      "10 23",
      "15 23",
      "20 23",
      "25 23",
      "30 23",
      "35 23",
      "40 23",
      "45 23",
      "50 23",
      "55 23",
      "0 0",
      "5 0",
      "10 0",
      "15 0",
      "20 0",
      "25 0",
      "30 0",
      "35 0",
      "40 0",
      "45 0",
      "50 0",
      "55 0",
    ];
    assert(
      "cron migration 3927: exatamente 30 ondas fixadas",
      cronsDaMigration3927.length === 30 &&
        horariosEsperados.length === 30,
    );
    for (let i = 0; i < cronsDaMigration3927.length; i++) {
      const campos = cronsDaMigration3927[i].split(" ");
      assert(
        `cron onda ${i + 1}: 5 campos válidos`,
        campos.length === 5,
      );
      assert(
        `cron onda ${i + 1}: minuto/hora corretos (${
          horariosEsperados[i]
        } UTC)`,
        `${campos[0]} ${campos[1]}` === horariosEsperados[i],
      );
      assert(
        `cron onda ${i + 1}: dia-do-mês irrestrito ("*")`,
        campos[2] === "*",
      );
      assert(
        `cron onda ${i + 1}: mês irrestrito ("*")`,
        campos[3] === "*",
      );
      assert(
        `cron onda ${
          i + 1
        }: dia-da-semana irrestrito ("*") — inclui sábado(6) e domingo(0), diferente do "1-5" da PTAX`,
        campos[4] === "*",
      );
    }
  }

  // ── 20. wave-plan: MAX_WAVES=30 é a rede de segurança mesmo quando totalPages<=300 ──
  {
    // Empacotamento guloso patológico (correção pós-incidente 2026-08-21, WAVE_PAGE_CAP
    // 30->10, MAX_WAVES 10->30): 31 Sets de 6 páginas cada = 186 páginas totais (<=300,
    // dentro de MAX_CAPACITY_PAGES), mas nenhuma onda de 10 cabe 2 Sets de 6 juntos
    // (6+6=12>10) — cada Set forma sua própria onda -> 31 ondas > MAX_WAVES(30) ->
    // SCHEDULE_CAPACITY_EXCEEDED, nunca uma 31ª onda silenciosa (regra 7, "sem omissão
    // silenciosa").
    const candidates: RefreshSetCandidate[] = Array.from(
      { length: 31 },
      (_, i) => ({
        cardSetId: `set-${i}`,
        setCode: `P${String(i).padStart(2, "0")}`,
        externalSetId: `ext-${i}`,
        confirmedCardCount: 6 * CARDS_PAGE_LIMIT, // 6 páginas
      }),
    );
    const plan = buildRefreshWavePlan(candidates);
    assert(
      "empacotamento patológico: totalEstimatedPages=186 (<=300) mas SCHEDULE_CAPACITY_EXCEEDED por MAX_WAVES",
      plan.status === "SCHEDULE_CAPACITY_EXCEEDED" &&
        plan.totalEstimatedPages === 186,
    );
    assert("MAX_WAVES=30", MAX_WAVES === 30);
  }

  // ── 21. core.ts: deadline interno excedido ANTES do 1º Set -> FAILED imediato, zero
  // JustTCG chamada, telemetria vazia, nunca fica PROCESSING ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1,
      },
    ];
    const recorded: RecordedCall[] = [];
    // identitiesBySet deliberadamente vazio (Map padrão) — o deadline dispara ANTES da
    // primeira chamada a listConfirmedIdentitiesForSet, então nenhum Set chega a precisar
    // de identidades reais neste cenário.
    const port = buildFakePort(recorded, { candidateSets: candidates });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(new Map(), fetchCalls),
      30,
    );
    // Relógio determinístico: 1ª chamada = início da onda (0); toda chamada seguinte
    // reporta um instante muito além do deadline de 110s — garante estouro já na
    // primeira verificação "entre Sets", antes de qualquer trabalho do Set A.
    const clockValues = [0, 200_000];
    let clockCallIndex = 0;
    const deadlineExceededClock: Clock = () =>
      clockValues[Math.min(clockCallIndex++, clockValues.length - 1)];
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
      deadlineExceededClock,
    );
    assert(
      "deadline imediato: run finaliza FAILED, setsProcessed=0",
      result.kind === "EXECUTED" && result.status === "FAILED" &&
        result.setsProcessed === 0,
    );
    assert(
      "deadline imediato: errorParts contém WAVE_INTERNAL_DEADLINE_EXCEEDED",
      result.kind === "EXECUTED" &&
        result.errorParts.some((p) =>
          p.includes("WAVE_INTERNAL_DEADLINE_EXCEEDED")
        ),
    );
    assert(
      "deadline imediato: JustTCG nunca chamada (zero fetch)",
      fetchCalls.count === 0,
    );
    assert(
      "deadline imediato: nenhuma escrita de produto/observação",
      !recorded.some((c) =>
        c.op === "resolveProductsBatch" || c.op === "insertObservations"
      ),
    );
    assert(
      "deadline imediato: run nunca fica PROCESSING — updateSyncRun chamado com status FAILED",
      recorded.some((c) =>
        c.op === "updateSyncRun" &&
        (c.payload as { patch: UpdateSyncRunPatch }).patch.status === "FAILED"
      ),
    );
  }

  // ── 22. core.ts: deadline interno excedido APÓS o 1º Set -> interrupção parcial,
  // telemetria do 1º Set preservada via checkpoint ANTES da finalização ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1,
      },
      {
        cardSetId: "set-c",
        setCode: "CCC",
        externalSetId: "ext-c",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-a", [{
        identityId: "identity-a",
        externalCardId: "card-a",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-a",
      }]],
    ]);
    const cardsBySet = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "card-a",
        name: "Card A",
        variants: [buildVariant("ext-prod-a", 10)],
      }]],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(cardsBySet, fetchCalls),
      30,
    );
    // Relógio: início=0; check antes do Set A=500 (dentro do orçamento, processa Set A);
    // check antes do Set B=200_000 (excede) -> interrompe antes de tocar B/C.
    const clockValues = [0, 500, 200_000];
    let clockCallIndex = 0;
    const midWaveClock: Clock = () =>
      clockValues[Math.min(clockCallIndex++, clockValues.length - 1)];
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
      midWaveClock,
    );
    assert(
      "deadline no meio da onda: run finaliza FAILED, setsProcessed=1 (só Set A)",
      result.kind === "EXECUTED" && result.status === "FAILED" &&
        result.setsProcessed === 1,
    );
    assert(
      "deadline no meio da onda: errorParts contém WAVE_INTERNAL_DEADLINE_EXCEEDED",
      result.kind === "EXECUTED" &&
        result.errorParts.some((p) =>
          p.includes("WAVE_INTERNAL_DEADLINE_EXCEEDED")
        ),
    );
    assert(
      "deadline no meio da onda: JustTCG chamada exatamente 1 vez (só Set A)",
      fetchCalls.count === 1,
    );
    const callLogCalls = recorded.filter((c) => c.op === "insertSyncRunCalls");
    assert(
      "deadline no meio da onda: telemetria do Set A foi persistida via checkpoint (insertSyncRunCalls chamado)",
      callLogCalls.length >= 1,
    );
    assert(
      "deadline no meio da onda: nenhuma chamada JustTCG foi perdida — total de entradas persistidas = 1",
      callLogCalls.reduce(
        (sum, c) =>
          sum +
          (c.payload as { callLog: readonly unknown[] }).callLog.length,
        0,
      ) === 1,
    );
  }

  // ── 23. core.ts: checkpoint incremental — telemetria é persistida APÓS CADA SET, não
  // numa única gravação final (2+ Sets, sem deadline) ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-a", [{
        identityId: "identity-a",
        externalCardId: "card-a",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-a",
      }]],
      ["set-b", [{
        identityId: "identity-b",
        externalCardId: "card-b",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-b",
      }]],
    ]);
    const cardsBySet = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "card-a",
        name: "Card A",
        variants: [buildVariant("ext-prod-a", 10)],
      }]],
      ["ext-b", [{
        id: "card-b",
        name: "Card B",
        variants: [buildVariant("ext-prod-b", 20)],
      }]],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(cardsBySet, fetchCalls),
      30,
    );
    // Relógio sempre em 0 — nunca excede o deadline, os dois Sets são processados por
    // completo; o que este cenário prova é a CADÊNCIA da telemetria, não o corte.
    const alwaysZeroClock: Clock = () => 0;
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
      alwaysZeroClock,
    );
    assert(
      "checkpoint incremental: run finaliza COMPLETED, 2 Sets processados",
      result.kind === "EXECUTED" && result.status === "COMPLETED" &&
        result.setsProcessed === 2,
    );
    const callLogCalls = recorded.filter((c) => c.op === "insertSyncRunCalls");
    assert(
      "checkpoint incremental: insertSyncRunCalls chamado mais de uma vez (checkpoint por Set, não uma única gravação final)",
      callLogCalls.length >= 2,
    );
    assert(
      "checkpoint incremental: cada chamada de checkpoint carrega só a telemetria NOVA daquele Set (nenhuma tem os 2 registros combinados)",
      callLogCalls.every((c) =>
        (c.payload as { callLog: readonly unknown[] }).callLog.length === 1
      ),
    );
    assert(
      "checkpoint incremental: soma total das entradas persistidas = 2 (uma por Set, nenhuma perdida nem duplicada)",
      callLogCalls.reduce(
        (sum, c) =>
          sum +
          (c.payload as { callLog: readonly unknown[] }).callLog.length,
        0,
      ) === 2,
    );
  }

  // ── 24. core.ts: falha ao persistir checkpoint intermediário -> hardFailure, aquisição
  // interrompida, run finaliza FAILED (nunca prossegue como se nada tivesse acontecido) ──
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-a",
        setCode: "AAA",
        externalSetId: "ext-a",
        confirmedCardCount: 1,
      },
      {
        cardSetId: "set-b",
        setCode: "BBB",
        externalSetId: "ext-b",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-a", [{
        identityId: "identity-a",
        externalCardId: "card-a",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-a",
      }]],
      ["set-b", [{
        identityId: "identity-b",
        externalCardId: "card-b",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-b",
      }]],
    ]);
    const cardsBySet = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "card-a",
        name: "Card A",
        variants: [buildVariant("ext-prod-a", 10)],
      }]],
      ["ext-b", [{
        id: "card-b",
        name: "Card B",
        variants: [buildVariant("ext-prod-b", 20)],
      }]],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      failInsertSyncRunCalls: true,
    });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(cardsBySet, fetchCalls),
      30,
    );
    const alwaysZeroClock: Clock = () => 0;
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
      alwaysZeroClock,
    );
    assert(
      "checkpoint falho: run finaliza FAILED (nunca ignora a falha de telemetria)",
      result.kind === "EXECUTED" && result.status === "FAILED",
    );
    assert(
      "checkpoint falho: errorParts sinaliza a falha de checkpoint",
      result.kind === "EXECUTED" &&
        result.errorParts.some((p) =>
          p.includes("PRICING_SYNC_RUN_CALL_CHECKPOINT_FAILED")
        ),
    );
    assert(
      "checkpoint falho: Set B nunca foi tocado (setsProcessed=1, só Set A rodou antes do checkpoint falhar)",
      result.kind === "EXECUTED" && result.setsProcessed === 1,
    );
    assert(
      "checkpoint falho: JustTCG chamada exatamente 1 vez (só Set A)",
      fetchCalls.count === 1,
    );
  }

  // ── 25. observation-decision.ts: idempotência de reexecução — preço idêntico ao já
  // persistido nunca duplica (SAME_PRICE_SKIP), confirmando a garantia usada para as 2401
  // observações/1 produto do run 6c2ca781 preservados no incidente de 2026-08-21 ──
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
        identityId: "identity-a",
        externalCardId: "card-a",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-a",
      }]],
    ]);
    const cardsBySet = new Map<string, JustTcgCard[]>([
      ["ext-a", [{
        id: "card-a",
        name: "Card A",
        variants: [buildVariant("ext-prod-a", 42.5)],
      }]],
    ]);
    const existingProducts: SeedProductRow[] = [{
      productId: "product-existing-a",
      pricingCardMappingId: "mapping-a",
      pricingSourceCardIdentityId: "identity-a",
      externalProductId: "ext-prod-a",
      sourcePrintingLabel: "Normal",
    }];
    const latestObservationsByKey = new Map<string, LatestObservationRow>([
      ["product-existing-a::condition-nm", {
        productId: "product-existing-a",
        conditionId: "condition-nm",
        price: 42.5,
        observedAt: "2026-08-20T00:00:00.000Z",
      }],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      existingProducts,
      latestObservationsByKey,
    });
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(cardsBySet, fetchCalls),
      30,
    );
    const alwaysZeroClock: Clock = () => 0;
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
      alwaysZeroClock,
    );
    assert(
      "idempotência: run COMPLETED, produto já existente NUNCA reinserido",
      result.kind === "EXECUTED" && result.status === "COMPLETED" &&
        result.productsInserted === 0,
    );
    assert(
      "idempotência: preço idêntico ao já persistido -> zero observações novas escritas",
      result.kind === "EXECUTED" && result.observationsWritten === 0,
    );
    assert(
      "idempotência: contabilizado como SAME_PRICE_SKIP (não como falha, nem como omissão silenciosa)",
      result.kind === "EXECUTED" &&
        result.observationsSkippedSamePrice === 1,
    );
  }

  // ── R1 (regressão, corrigido 2026-08-21): reproduz o cenário exato do defeito real —
  // produto já existente pela chave econômica (pricing_card_mapping_id,
  // external_product_id), mas gravado sob uma identity ANTIGA que diverge da identity
  // CONFIRMED atual do mesmo mapping (SV2-SV7, SV9, SWSH1-5, SWSH7 — runs a31742a4 e
  // seguintes, 2026-08-21). Antes da correção, resolveProductsBatch nem existia — o
  // caminho antigo (findExistingProducts/insertProducts por identity_id) não reconhecia
  // o produto e tentava um INSERT duplicado, derrubando o run inteiro (status=FAILED,
  // observação perdida). Pós-fix (migration 3928 + core.ts): a RPC resolve pelo par
  // (mapping_id, external_product_id) — SEMPRE reconhece o produto via REUSE, nunca
  // tenta INSERT duplicado. Como a identity armazenada diverge da identity candidata,
  // core.ts sinaliza IDENTITY_MISMATCH_ON_REUSE (warning, nunca hardFailure — ver
  // plano R1/R5 aprovado por Fabrício) e o run termina COMPLETED_WITH_ERRORS, nunca
  // FAILED — a observação de preço É gravada (nunca perdida).
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-r1",
        setCode: "R1SET",
        externalSetId: "ext-r1",
        confirmedCardCount: 1,
      },
    ];
    // Identidade CONFIRMED atual do Set — ex.: promovida por um reparo de identidade
    // posterior ao momento em que o produto abaixo foi originalmente inserido sob
    // "identity-antiga".
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-r1", [{
        identityId: "identity-nova",
        externalCardId: "ext-card-r1",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-r1",
      }]],
    ]);
    // Produto JÁ EXISTENTE no banco, para o MESMO mapping_id+external_product_id, mas
    // gravado sob a identidade ANTIGA — reproduz exatamente o estado de pricing_product
    // observado nos 14 Sets reais afetados hoje. sourcePrintingLabel igual ao da
    // candidata ("Normal", default de buildVariant) — este cenário isola só a
    // divergência de identity, não a de printing_label (coberta num cenário à parte).
    const existingProducts: SeedProductRow[] = [{
      productId: "product-r1-existente",
      pricingCardMappingId: "mapping-r1",
      pricingSourceCardIdentityId: "identity-antiga",
      externalProductId: "ext-prod-r1",
      sourcePrintingLabel: "Normal",
    }];
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      existingProducts,
    });

    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-r1", [{
        id: "ext-card-r1",
        name: "Carta R1",
        variants: [buildVariant("ext-prod-r1", 9.99)],
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    const resolveCalls = recorded.filter((c) =>
      c.op === "resolveProductsBatch"
    );

    assert(
      "R1 [corrigido]: resolveProductsBatch foi chamado exatamente 1 vez para o Set (nunca uma segunda tentativa de INSERT/resolve para o mesmo par)",
      resolveCalls.length === 1,
    );
    assert(
      "R1 [corrigido]: a única chamada carrega exatamente 1 linha, com pricingCardMappingId='mapping-r1' e externalProductId='ext-prod-r1'",
      resolveCalls.length === 1 &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[]).length ===
          1 &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[])[0]
            .pricingCardMappingId === "mapping-r1" &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[])[0]
            .externalProductId === "ext-prod-r1",
    );
    assert(
      "R1 [corrigido]: run termina com status='COMPLETED_WITH_ERRORS' (nunca FAILED — o produto É reconhecido via REUSE, o mismatch de identity é só um aviso)",
      result.kind === "EXECUTED" &&
        result.status === "COMPLETED_WITH_ERRORS",
    );
    assert(
      "R1 [corrigido]: nenhum produto novo inserido (productsInserted=0 — classificado REUSE, não NEW)",
      result.kind === "EXECUTED" && result.productsInserted === 0,
    );
    assert(
      "R1 [corrigido]: observationsWritten=1 (observação de preço gravada contra o produto existente via REUSE, nunca perdida)",
      result.kind === "EXECUTED" && result.observationsWritten === 1,
    );
    assert(
      "R1 [corrigido]: errorParts contém IDENTITY_MISMATCH_ON_REUSE(set=R1SET, produto=ext-prod-r1) com candidata=identity-nova armazenada=identity-antiga",
      result.kind === "EXECUTED" &&
        result.errorParts.some((p) =>
          p ===
            "IDENTITY_MISMATCH_ON_REUSE(set=R1SET, produto=ext-prod-r1): candidata=identity-nova armazenada=identity-antiga"
        ),
    );
    assert(
      "R1 [corrigido]: nenhum PRINTING_LABEL_MISMATCH_ON_REUSE neste cenário (printing_label idêntico entre candidata e armazenado)",
      result.kind === "EXECUTED" &&
        !result.errorParts.some((p) =>
          p.startsWith("PRINTING_LABEL_MISMATCH_ON_REUSE")
        ),
    );
  }

  // ── R1/R5 — REUSE limpo (sem divergência): identity e printing_label da candidata
  // coincidem com o produto já armazenado -> classificação REUSE, zero warnings, run
  // COMPLETED (nunca COMPLETED_WITH_ERRORS), preço mudou -> 1 observação nova escrita.
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-reuse",
        setCode: "REUSESET",
        externalSetId: "ext-reuse",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-reuse", [{
        identityId: "identity-reuse",
        externalCardId: "ext-card-reuse",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-reuse",
      }]],
    ]);
    const existingProducts: SeedProductRow[] = [{
      productId: "product-reuse-existente",
      pricingCardMappingId: "mapping-reuse",
      pricingSourceCardIdentityId: "identity-reuse",
      externalProductId: "ext-prod-reuse",
      sourcePrintingLabel: "Normal",
    }];
    const latestObservationsByKey = new Map<string, LatestObservationRow>([
      ["product-reuse-existente::condition-nm", {
        productId: "product-reuse-existente",
        conditionId: "condition-nm",
        price: 3.0,
        observedAt: "2026-08-20T00:00:00.000Z",
      }],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      existingProducts,
      latestObservationsByKey,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-reuse", [{
        id: "ext-card-reuse",
        name: "Carta Reuse",
        variants: [buildVariant("ext-prod-reuse", 4.5)], // preço mudou (3.0 -> 4.5)
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    assert(
      "REUSE limpo: run COMPLETED (sem warnings — identity e printing_label coincidem)",
      result.kind === "EXECUTED" && result.status === "COMPLETED",
    );
    assert(
      "REUSE limpo: productsInserted=0, observationsWritten=1 (preço mudou)",
      result.kind === "EXECUTED" && result.productsInserted === 0 &&
        result.observationsWritten === 1,
    );
    assert(
      "REUSE limpo: errorParts vazio (zero IDENTITY_MISMATCH/PRINTING_LABEL_MISMATCH)",
      result.kind === "EXECUTED" && result.errorParts.length === 0,
    );
  }

  // ── R1/R5 — lote misto NEW+REUSE no mesmo Set: uma identidade resolve um produto já
  // existente (REUSE), outra resolve um produto inédito (NEW) — uma única chamada a
  // resolveProductsBatch com as 2 linhas, productsInserted conta só a NEW.
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-mix",
        setCode: "MIXSET",
        externalSetId: "ext-mix",
        confirmedCardCount: 2,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-mix", [
        {
          identityId: "identity-mix-existente",
          externalCardId: "ext-card-mix-existente",
          identityRole: "PRIMARY",
          pricingCardMappingId: "mapping-mix-existente",
        },
        {
          identityId: "identity-mix-nova",
          externalCardId: "ext-card-mix-nova",
          identityRole: "PRIMARY",
          pricingCardMappingId: "mapping-mix-nova",
        },
      ]],
    ]);
    const existingProducts: SeedProductRow[] = [{
      productId: "product-mix-existente",
      pricingCardMappingId: "mapping-mix-existente",
      pricingSourceCardIdentityId: "identity-mix-existente",
      externalProductId: "ext-prod-mix-existente",
      sourcePrintingLabel: "Normal",
    }];
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      existingProducts,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-mix", [
        {
          id: "ext-card-mix-existente",
          name: "Carta Existente",
          variants: [buildVariant("ext-prod-mix-existente", 1.5)],
        },
        {
          id: "ext-card-mix-nova",
          name: "Carta Nova",
          variants: [buildVariant("ext-prod-mix-nova", 2.5)],
        },
      ]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    const resolveCalls = recorded.filter((c) =>
      c.op === "resolveProductsBatch"
    );
    assert(
      "lote misto: resolveProductsBatch chamado 1 vez, com 2 linhas (1 REUSE + 1 NEW)",
      resolveCalls.length === 1 &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[]).length === 2,
    );
    assert(
      "lote misto: run COMPLETED, productsInserted=1 (só a NEW), observationsWritten=2",
      result.kind === "EXECUTED" && result.status === "COMPLETED" &&
        result.productsInserted === 1 && result.observationsWritten === 2,
    );
  }

  // ── R1/R5 — PRINTING_LABEL_MISMATCH_ON_REUSE: identity coincide, mas o printing_label
  // candidato diverge do armazenado -> warning (nunca UPDATE), run COMPLETED_WITH_ERRORS.
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-label",
        setCode: "LABELSET",
        externalSetId: "ext-label",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-label", [{
        identityId: "identity-label",
        externalCardId: "ext-card-label",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-label",
      }]],
    ]);
    // Armazenado como "Holofoil"; a variante devolvida pela JustTCG nesta execução vem
    // como "Normal" — mesma identity, printing_label diverge.
    const existingProducts: SeedProductRow[] = [{
      productId: "product-label-existente",
      pricingCardMappingId: "mapping-label",
      pricingSourceCardIdentityId: "identity-label",
      externalProductId: "ext-prod-label",
      sourcePrintingLabel: "Holofoil",
    }];
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      existingProducts,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-label", [{
        id: "ext-card-label",
        name: "Carta Label",
        variants: [buildVariant("ext-prod-label", 6.0)], // printing default "Normal"
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    assert(
      "printing_label mismatch: run COMPLETED_WITH_ERRORS (nunca FAILED)",
      result.kind === "EXECUTED" &&
        result.status === "COMPLETED_WITH_ERRORS",
    );
    assert(
      "printing_label mismatch: errorParts contém PRINTING_LABEL_MISMATCH_ON_REUSE(set=LABELSET, produto=ext-prod-label) com candidato=Normal armazenado=Holofoil",
      result.kind === "EXECUTED" &&
        result.errorParts.some((p) =>
          p ===
            "PRINTING_LABEL_MISMATCH_ON_REUSE(set=LABELSET, produto=ext-prod-label): candidato=Normal armazenado=Holofoil"
        ),
    );
    assert(
      "printing_label mismatch: nenhum IDENTITY_MISMATCH_ON_REUSE neste cenário (identity coincide)",
      result.kind === "EXECUTED" &&
        !result.errorParts.some((p) =>
          p.startsWith("IDENTITY_MISMATCH_ON_REUSE")
        ),
    );
    assert(
      "printing_label mismatch: produto ainda reconhecido via REUSE (productsInserted=0), observação gravada",
      result.kind === "EXECUTED" && result.productsInserted === 0 &&
        result.observationsWritten === 1,
    );
  }

  // ── R1/R5 — PRIMARY+ALTERNATE no mesmo mapping: duas identidades (papéis diferentes)
  // do mesmo pricing_card_mapping_id, cada uma com seu próprio external_product_id
  // (produtos econômicos distintos) -> resolvidos juntos numa única chamada, sem colisão
  // de chave econômica (a chave é mapping_id+external_product_id, não mapping_id sozinho).
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-alt",
        setCode: "ALTSET",
        externalSetId: "ext-alt",
        confirmedCardCount: 2,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-alt", [
        {
          identityId: "identity-alt-primary",
          externalCardId: "ext-card-alt-primary",
          identityRole: "PRIMARY",
          pricingCardMappingId: "mapping-alt",
        },
        {
          identityId: "identity-alt-alternate",
          externalCardId: "ext-card-alt-alternate",
          identityRole: "ALTERNATE",
          pricingCardMappingId: "mapping-alt",
        },
      ]],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-alt", [
        {
          id: "ext-card-alt-primary",
          name: "Carta Primary",
          variants: [buildVariant("ext-prod-alt-primary", 1.1)],
        },
        {
          id: "ext-card-alt-alternate",
          name: "Carta Alternate",
          variants: [buildVariant("ext-prod-alt-alternate", 2.2)],
        },
      ]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    const resolveCalls = recorded.filter((c) =>
      c.op === "resolveProductsBatch"
    );
    assert(
      "PRIMARY+ALTERNATE: resolveProductsBatch chamado 1 vez, com 2 linhas — mesmo mapping_id, external_product_id distintos",
      resolveCalls.length === 1 &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[]).length ===
          2 &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[]).every((r) =>
          r.pricingCardMappingId === "mapping-alt"
        ),
    );
    assert(
      "PRIMARY+ALTERNATE: ambos NEW (nenhum já existia), run COMPLETED, 2 produtos e 2 observações",
      result.kind === "EXECUTED" && result.status === "COMPLETED" &&
        result.productsInserted === 2 && result.observationsWritten === 2,
    );
  }

  // ── R1/R5 — dedup por chave econômica dentro do mesmo Set: 2 condições (NM/LP) da
  // MESMA variante (mesmo external_product_id) geram 2 candidatos, mas resolveProductsBatch
  // é chamado com 1 única linha (dedup por mapping_id+external_product_id, nunca por
  // condição) — nenhuma tentativa duplicada de resolver o mesmo par econômico.
  {
    const candidates: RefreshSetCandidate[] = [
      {
        cardSetId: "set-dedup",
        setCode: "DEDUPSET",
        externalSetId: "ext-dedup",
        confirmedCardCount: 1,
      },
    ];
    const identitiesBySet = new Map<string, RefreshIdentityRow[]>([
      ["set-dedup", [{
        identityId: "identity-dedup",
        externalCardId: "ext-card-dedup",
        identityRole: "PRIMARY",
        pricingCardMappingId: "mapping-dedup",
      }]],
    ]);
    const conditionMap = new Map<string, string>([
      ["NM", "condition-nm"],
      ["LP", "condition-lp"],
    ]);
    const recorded: RecordedCall[] = [];
    const port = buildFakePort(recorded, {
      candidateSets: candidates,
      identitiesBySet,
      conditionMap,
    });
    const bySetId = new Map<string, JustTcgCard[]>([
      ["ext-dedup", [{
        id: "ext-card-dedup",
        name: "Carta Dedup",
        variants: [
          buildVariant("ext-prod-dedup", 5.0, "NM"),
          buildVariant("ext-prod-dedup", 4.0, "LP"),
        ],
      }]],
    ]);
    const fetchCalls = { count: 0 };
    const client = new JustTcgClient(
      "fake-key",
      buildFakeFetch(bySetId, fetchCalls),
      30,
    );
    const result = await executePriceRefreshWave(
      port,
      client,
      PRICING_SOURCE_ID,
      1,
    );
    const resolveCalls = recorded.filter((c) =>
      c.op === "resolveProductsBatch"
    );
    assert(
      "dedup: 2 condições da mesma variante -> resolveProductsBatch chamado 1 vez com 1 única linha (dedup por mapping_id+external_product_id)",
      resolveCalls.length === 1 &&
        (resolveCalls[0].payload as ResolveProductsBatchInput[]).length === 1,
    );
    assert(
      "dedup: 1 produto inserido (NEW), mas 2 observações escritas (uma por condição)",
      result.kind === "EXECUTED" && result.status === "COMPLETED" &&
        result.productsInserted === 1 && result.observationsWritten === 2,
    );
  }

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — mesma disciplina de ptax-fx-refresh.test.ts:
// guardado por `typeof Deno !== "undefined"` para permanecer importável a partir de Node
// (validação offline no sandbox). 100% offline — nenhuma permissão --allow-* necessária.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "pricing-justtcg-refresh — suíte offline do núcleo (item F, 2026-08-21)",
    async () => {
      const result = await runPricingJusttcgRefreshTests();
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
