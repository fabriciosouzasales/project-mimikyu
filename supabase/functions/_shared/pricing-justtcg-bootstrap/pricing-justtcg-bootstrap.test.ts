// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-bootstrap/pricing-justtcg-bootstrap.test.ts
// Suite offline (100% sem rede real, sem Deno.serve, sem Supabase real) do executor de
// bootstrap de Set — P16.5.2/P16.5.3 ("executor de bootstrap + port/adapter", 2026-08-26).
// Cobre os 8 cenários mínimos exigidos por Fabrício mais estrutura/robustez adicional (dedup,
// página vazia, leitura local falha, LEASE_LOST). Mesmo estilo dos demais .test.ts deste
// diretório (pricing-set-matching-preview.test.ts, pricing-justtcg-matching.test.ts):
// assert() customizado, fetchImpl fake injetado no JustTcgClient, fake port em memória, sem
// nenhuma dependência externa.
//
// Autoria (revisão 2026-08-26, migrations 3957/3958): persistMatchingBatch() do port agora
// recebe syncRunId (cenário 13 prova o threading correto); os 6 cenários exigidos por Fabrício
// para a regra "exatamente um entre confirmed_by/confirmed_sync_run_id" (humano válido, sistema
// válido, ambos preenchidos, ambos nulos, REJECTED automático, dados existentes) são
// necessariamente testes de SQL/RPC contra o schema real — vivem na validação transacional
// (BEGIN/ROLLBACK) desta rodada, não neste arquivo, já que dependem do CHECK da migration 3957
// e da guarda num_nonnulls() da RPC 3958, nenhum dos dois expresso na camada TypeScript.

import { JustTcgClient } from "../pricing-justtcg/mod.ts";
import type { JustTcgCard } from "../pricing-justtcg/mod.ts";
import { decideMappingUpsert } from "../pricing-justtcg-matching/mod.ts";
import {
  dedupeCardsForStaging,
  executeBootstrapAttempt,
} from "./bootstrap-core.ts";
import type {
  BootstrapPhaseOutcome,
  BootstrapPort,
  BootstrapRunStatus,
  CheckpointAcquisitionResult,
  LocalActiveCard,
  OpenBootstrapAttemptResult,
  PersistBootstrapBatchResult,
  PersistBootstrapRowInput,
  StagedCardInput,
  StagedCardRow,
} from "./bootstrap-port.ts";

let failures = 0;
function assert(label: string, condition: boolean): void {
  if (!condition) {
    failures++;
    console.error(`FALHOU: ${label}`);
  } else {
    console.log(`OK: ${label}`);
  }
}

// ----------------------------------------------------------------------------
// Fakes
// ----------------------------------------------------------------------------

function makeFakeFetch(
  responses: Array<{ status: number; body: unknown }>,
): { fetchImpl: typeof fetch; callCount: () => number } {
  let index = 0;
  const fetchImpl = ((_url: string, _init?: RequestInit) => {
    const entry = responses[index] ?? responses[responses.length - 1];
    index++;
    return Promise.resolve(
      new Response(JSON.stringify(entry.body), { status: entry.status }),
    );
  }) as unknown as typeof fetch;
  return { fetchImpl, callCount: () => index };
}

function cardsPage(
  cards: Array<{ id: string; name: string; number?: string }>,
  hasMore: boolean,
) {
  return {
    status: 200,
    body: {
      data: cards.map((c) => ({
        id: c.id,
        name: c.name,
        number: c.number ?? null,
        variants: [],
      })),
      meta: { hasMore },
    },
  };
}

// Simula decideMappingUpsert (reuso direto da função real do núcleo P16.2 — nunca uma
// reimplementação divergente no teste) para a fake de persistMatchingBatch, permitindo provar
// idempotência ao chamar duas vezes com o mesmo lote.
class FakeMappingStore {
  private rows = new Map<
    string,
    {
      status: "CONFIRMED" | "PENDING" | "NOT_FOUND";
      externalCardId: string | null;
    }
  >();
  private identities = new Set<string>(); // chave: `${cardId}::${externalCardId}`

  persist(
    rows: readonly PersistBootstrapRowInput[],
  ): PersistBootstrapBatchResult {
    const out = [];
    for (const row of rows) {
      const newStatus = row.classification === "SAFE"
        ? "CONFIRMED"
        : row.classification === "AMBIGUOUS"
        ? "PENDING"
        : "NOT_FOUND";
      const existing = this.rows.get(row.cardId);
      const decision = decideMappingUpsert(
        existing ? { id: row.cardId, match_status: existing.status } : null,
        newStatus,
      );
      let finalStatus = existing?.status ?? newStatus;
      if (decision === "INSERTED" || decision === "UPGRADED_TO_CONFIRMED") {
        finalStatus = newStatus;
        this.rows.set(row.cardId, {
          status: newStatus,
          externalCardId: row.externalCardId,
        });
      }
      const action = decision === "UPGRADED_TO_CONFIRMED" && existing
        ? "UPGRADED"
        : decision === "INSERTED"
        ? "INSERTED"
        : decision.startsWith("NOOP")
        ? decision
        : "NOOP_SAME_STATUS";
      let identityCreated = false;
      if (finalStatus === "CONFIRMED" && row.externalCardId) {
        const key = `${row.cardId}::${row.externalCardId}`;
        if (!this.identities.has(key)) {
          this.identities.add(key);
          identityCreated = true;
        }
      }
      out.push({
        cardId: row.cardId,
        action,
        finalMatchStatus: finalStatus,
        identityCreated,
      });
    }
    return { ok: true, rows: out };
  }
}

type FakePortConfig = {
  openQueue: OpenBootstrapAttemptResult[];
  checkpointQueue?: CheckpointAcquisitionResult[]; // default: sempre true
  closeQueue?: string[]; // default: 'STUB_FINAL_STATUS' sempre
  staging?: StagedCardRow[];
  localCards?: LocalActiveCard[];
  persistImpl?: (
    pricingSourceId: string,
    syncRunId: string,
    rows: readonly PersistBootstrapRowInput[],
  ) => PersistBootstrapBatchResult;
  throwOnLoadStaging?: boolean;
  throwOnLoadLocalCards?: boolean;
};

function buildFakePort(config: FakePortConfig): {
  port: BootstrapPort;
  calls: string[];
  checkpointPayloads: Array<{ offset: number; cards: StagedCardInput[] }>;
  closePayloads: Array<
    {
      phaseOutcome: BootstrapPhaseOutcome;
      runStatus: BootstrapRunStatus;
      requestsMade: number;
      rateLimitHits: number;
      errorSummary: string | null;
    }
  >;
  persistPayloads: Array<
    {
      pricingSourceId: string;
      syncRunId: string;
      rows: readonly PersistBootstrapRowInput[];
    }
  >;
} {
  const calls: string[] = [];
  const checkpointPayloads: Array<
    { offset: number; cards: StagedCardInput[] }
  > = [];
  const closePayloads: Array<
    {
      phaseOutcome: BootstrapPhaseOutcome;
      runStatus: BootstrapRunStatus;
      requestsMade: number;
      rateLimitHits: number;
      errorSummary: string | null;
    }
  > = [];
  const persistPayloads: Array<
    {
      pricingSourceId: string;
      syncRunId: string;
      rows: readonly PersistBootstrapRowInput[];
    }
  > = [];
  let openIndex = 0;
  let checkpointIndex = 0;
  let closeIndex = 0;

  const port: BootstrapPort = {
    openAttempt(pricingSourceId: string) {
      calls.push(`openAttempt(${pricingSourceId})`);
      const result = config.openQueue[openIndex] ??
        config.openQueue[config.openQueue.length - 1];
      openIndex++;
      return Promise.resolve(result);
    },
    checkpointAcquisitionPage(syncRunId, newResumeOffset, stagedCards) {
      calls.push(
        `checkpointAcquisitionPage(${syncRunId},${newResumeOffset},n=${stagedCards.length})`,
      );
      checkpointPayloads.push({
        offset: newResumeOffset,
        cards: [...stagedCards],
      });
      const queue = config.checkpointQueue;
      const result = queue
        ? (queue[checkpointIndex] ?? queue[queue.length - 1])
        : true;
      checkpointIndex++;
      return Promise.resolve(result);
    },
    closeAttempt(
      syncRunId,
      phaseOutcome,
      runStatus,
      requestsMade,
      rateLimitHits,
      errorSummary,
    ) {
      calls.push(`closeAttempt(${syncRunId},${phaseOutcome},${runStatus})`);
      closePayloads.push({
        phaseOutcome,
        runStatus,
        requestsMade,
        rateLimitHits,
        errorSummary,
      });
      const queue = config.closeQueue;
      const finalStatus = queue
        ? (queue[closeIndex] ?? queue[queue.length - 1])
        : "STUB_FINAL_STATUS";
      closeIndex++;
      return Promise.resolve({ finalStatus });
    },
    loadFullStaging(pricingSetMappingId: string) {
      calls.push(`loadFullStaging(${pricingSetMappingId})`);
      if (config.throwOnLoadStaging) {
        return Promise.reject(new Error("STAGING_READ_FAILED"));
      }
      return Promise.resolve(config.staging ?? []);
    },
    loadLocalActiveCards(cardSetId: string) {
      calls.push(`loadLocalActiveCards(${cardSetId})`);
      if (config.throwOnLoadLocalCards) {
        return Promise.reject(new Error("LOCAL_CARDS_READ_FAILED"));
      }
      return Promise.resolve(config.localCards ?? []);
    },
    persistMatchingBatch(pricingSourceId, syncRunId, rows) {
      calls.push(
        `persistMatchingBatch(${pricingSourceId},${syncRunId},n=${rows.length})`,
      );
      persistPayloads.push({ pricingSourceId, syncRunId, rows });
      if (config.persistImpl) {
        return Promise.resolve(
          config.persistImpl(pricingSourceId, syncRunId, rows),
        );
      }
      return Promise.resolve({
        ok: true,
        rows: rows.map((r) => ({
          cardId: r.cardId,
          action: "INSERTED",
          finalMatchStatus: r.classification === "SAFE"
            ? "CONFIRMED"
            : r.classification === "AMBIGUOUS"
            ? "PENDING"
            : "NOT_FOUND",
          identityCreated: r.classification === "SAFE",
        })),
      });
    },
  };

  return { port, calls, checkpointPayloads, closePayloads, persistPayloads };
}

const PRICING_SOURCE_ID = "1ffe42af-7b16-4406-88c8-ad2d57dde6f9";
const SYNC_RUN_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const PRICING_SET_MAPPING_ID = "11111111-1111-1111-1111-111111111111";
const CARD_SET_ID = "22222222-2222-2222-2222-222222222222";
const EXTERNAL_SET_ID = "swsh8-fusion-strike";

function claimedAcquiring(resumeOffset = 0): OpenBootstrapAttemptResult {
  return {
    outcome: "CLAIMED",
    syncRunId: SYNC_RUN_ID,
    pricingSetMappingId: PRICING_SET_MAPPING_ID,
    cardSetId: CARD_SET_ID,
    externalSetId: EXTERNAL_SET_ID,
    status: resumeOffset === 0 ? "PENDING" : "ACQUIRING",
    acquisitionResumeOffset: resumeOffset,
  };
}

function claimedMatching(): OpenBootstrapAttemptResult {
  return {
    outcome: "CLAIMED",
    syncRunId: SYNC_RUN_ID,
    pricingSetMappingId: PRICING_SET_MAPPING_ID,
    cardSetId: CARD_SET_ID,
    externalSetId: EXTERNAL_SET_ID,
    status: "MATCHING",
    acquisitionResumeOffset: 0,
  };
}

// Clock determinístico injetável — cada chamada avança N ms (default 0), permitindo simular
// deadline excedido sem esperar de verdade.
function makeClock(stepsMs: number[]): () => number {
  let base = 1_000_000;
  let idx = 0;
  return () => {
    if (idx < stepsMs.length) {
      base += stepsMs[idx];
      idx++;
    }
    return base;
  };
}

async function main() {
  // 1. NO_CANDIDATE -> NO_WORK, zero chamada à JustTCG, zero checkpoint/close.
  {
    const { port, calls } = buildFakePort({
      openQueue: [{ outcome: "NO_CANDIDATE" }],
    });
    const { fetchImpl, callCount } = makeFakeFetch([]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert("1. NO_CANDIDATE -> kind NO_WORK", result.kind === "NO_WORK");
    assert("1. NO_CANDIDATE -> zero chamada à JustTCG", callCount() === 0);
    assert("1. NO_CANDIDATE -> só openAttempt foi chamado", calls.length === 1);
  }

  // 2. SOURCE_BUSY -> kind SOURCE_BUSY, zero chamada à JustTCG.
  {
    const { port, calls } = buildFakePort({
      openQueue: [{ outcome: "SOURCE_BUSY" }],
    });
    const { fetchImpl, callCount } = makeFakeFetch([]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert("2. SOURCE_BUSY -> kind SOURCE_BUSY", result.kind === "SOURCE_BUSY");
    assert("2. SOURCE_BUSY -> zero chamada à JustTCG", callCount() === 0);
    assert("2. SOURCE_BUSY -> só openAttempt foi chamado", calls.length === 1);
  }

  // 3. Aquisição multi-página (2 páginas) -> 2 checkpoints com offsets 100/200, close com
  // NO_MORE_PAGES, pagesProcessed=2, cardsStaged=3 (2 + 1).
  {
    const { port, checkpointPayloads, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl, callCount } = makeFakeFetch([
      cardsPage([{ id: "c1", name: "Pikachu" }, {
        id: "c2",
        name: "Charizard",
      }], true),
      cardsPage([{ id: "c3", name: "Bulbasaur" }], false),
    ]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "3. Multi-página -> kind ACQUISITION_CLOSED",
      result.kind === "ACQUISITION_CLOSED",
    );
    assert("3. Multi-página -> 2 requisições HTTP", callCount() === 2);
    assert(
      "3. Multi-página -> pagesProcessed=2",
      result.kind === "ACQUISITION_CLOSED" && result.pagesProcessed === 2,
    );
    assert(
      "3. Multi-página -> cardsStaged=3",
      result.kind === "ACQUISITION_CLOSED" && result.cardsStaged === 3,
    );
    assert(
      "3. Multi-página -> 2 checkpoints, offsets 100 e 200",
      checkpointPayloads.length === 2 && checkpointPayloads[0].offset === 100 &&
        checkpointPayloads[1].offset === 200,
    );
    assert(
      "3. Multi-página -> fecha com NO_MORE_PAGES/COMPLETED",
      closePayloads.length === 1 &&
        closePayloads[0].phaseOutcome === "NO_MORE_PAGES" &&
        closePayloads[0].runStatus === "COMPLETED",
    );
  }

  // 4. Retomada após interrupção -> open_ devolve acquisition_resume_offset=100 (ciclo
  // anterior já persistiu 1 página); a PRIMEIRA requisição desta invocação já usa offset=100,
  // nunca reinicia do zero.
  {
    const { port } = buildFakePort({ openQueue: [claimedAcquiring(100)] });
    let capturedOffset: string | null = null;
    const fetchImpl = ((url: string) => {
      const u = new URL(url);
      capturedOffset = u.searchParams.get("offset");
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: [{ id: "c99", name: "Mew", number: "099" }],
            meta: { hasMore: false },
          }),
          { status: 200 },
        ),
      );
    }) as unknown as typeof fetch;
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "4. Retomada -> primeira requisição usa offset=100 (nunca 0)",
      capturedOffset === "100",
    );
    assert(
      "4. Retomada -> fecha com sucesso",
      result.kind === "ACQUISITION_CLOSED" &&
        result.phaseOutcome === "NO_MORE_PAGES",
    );
  }

  // 5. Deduplicação de external_card_id -> uma página com o mesmo id repetido é reduzida a 1
  // entrada ANTES de ser enviada ao checkpoint_ (evita erro de Postgres "cannot affect row a
  // second time" num único INSERT ... ON CONFLICT).
  {
    const cards: JustTcgCard[] = [
      { id: "dup-1", name: "Eevee", number: "133", variants: [] },
      { id: "dup-1", name: "Eevee", number: "133", variants: [] },
      { id: "dup-2", name: "Vaporeon", number: "134", variants: [] },
    ];
    const deduped = dedupeCardsForStaging(cards);
    assert(
      "5a. dedupeCardsForStaging -> 3 brutos viram 2 únicos",
      deduped.length === 2,
    );
    assert(
      "5a. dedupeCardsForStaging -> mantém a primeira ocorrência",
      deduped[0].id === "dup-1" && deduped[1].id === "dup-2",
    );

    const { port, checkpointPayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([
      cardsPage([
        { id: "dup-1", name: "Eevee" },
        { id: "dup-1", name: "Eevee" },
        { id: "dup-2", name: "Vaporeon" },
      ], false),
    ]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    await executeBootstrapAttempt(port, client, PRICING_SOURCE_ID);
    assert(
      "5b. Fluxo completo -> checkpoint recebe só 2 cartas (dedupe aplicado)",
      checkpointPayloads[0].cards.length === 2,
    );
  }

  // 6. Página vazia (Set sem nenhuma carta externa) -> ainda assim chama checkpoint_ UMA vez
  // (com array vazio) antes de close_(NO_MORE_PAGES) -- a RPC exige ao menos 1 checkpoint
  // bem-sucedido para transicionar PENDING->ACQUIRING.
  {
    const { port, checkpointPayloads, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([cardsPage([], false)]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "6. Página vazia -> 1 checkpoint com array vazio",
      checkpointPayloads.length === 1 &&
        checkpointPayloads[0].cards.length === 0,
    );
    assert(
      "6. Página vazia -> fecha NO_MORE_PAGES mesmo assim",
      closePayloads[0].phaseOutcome === "NO_MORE_PAGES",
    );
    assert(
      "6. Página vazia -> pagesProcessed=1, cardsStaged=0",
      result.kind === "ACQUISITION_CLOSED" && result.pagesProcessed === 1 &&
        result.cardsStaged === 0,
    );
  }

  // 7. BUDGET_STOPPED -> orçamento local do client esgota na 2ª página; fecha com
  // BUDGET_STOPPED/COMPLETED (nunca FAILED -- é continuação normal, não erro).
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([
      cardsPage([{ id: "c1", name: "A" }], true),
      cardsPage([{ id: "c2", name: "B" }], true),
    ]);
    const client = new JustTcgClient("fake-key", fetchImpl, 1); // orçamento=1 -> 2ª chamada é BUDGET_STOPPED
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "7. BUDGET_STOPPED -> phaseOutcome correto",
      result.kind === "ACQUISITION_CLOSED" &&
        result.phaseOutcome === "BUDGET_STOPPED",
    );
    assert(
      "7. BUDGET_STOPPED -> runStatus=COMPLETED (continuação, não erro)",
      closePayloads[0].runStatus === "COMPLETED",
    );
  }

  // 8. DEADLINE_STOPPED -> relógio injetado avança além do teto interno antes da 2ª página.
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([
      cardsPage([{ id: "c1", name: "A" }], true),
      cardsPage([{ id: "c2", name: "B" }], true),
    ]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const clock = makeClock([0, 200_000]); // 2ª chamada do clock já excede o teto de 110s
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
      clock,
    );
    assert(
      "8. DEADLINE_STOPPED -> phaseOutcome correto",
      result.kind === "ACQUISITION_CLOSED" &&
        result.phaseOutcome === "DEADLINE_STOPPED",
    );
    assert(
      "8. DEADLINE_STOPPED -> runStatus=COMPLETED",
      closePayloads[0].runStatus === "COMPLETED",
    );
  }

  // 9. AUTH_FAILURE (401) -> phaseOutcome=AUTH_FAILURE, runStatus=FAILED.
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([{ status: 401, body: {} }]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "9. AUTH_FAILURE -> phaseOutcome/runStatus corretos",
      result.kind === "ACQUISITION_CLOSED" &&
        result.phaseOutcome === "AUTH_FAILURE" &&
        closePayloads[0].runStatus === "FAILED",
    );
  }

  // 10. 404 -> SET_TERMINAL_ERROR/COMPLETED_WITH_ERRORS (Set não existe mais na JustTCG).
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([{ status: 404, body: {} }]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "10. 404 -> SET_TERMINAL_ERROR/COMPLETED_WITH_ERRORS",
      result.kind === "ACQUISITION_CLOSED" &&
        result.phaseOutcome === "SET_TERMINAL_ERROR" &&
        closePayloads[0].runStatus === "COMPLETED_WITH_ERRORS",
    );
  }

  // 11. 500 -> TRANSIENT_ERROR/COMPLETED_WITH_ERRORS (retry automático, nunca terminal).
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
    });
    const { fetchImpl } = makeFakeFetch([{ status: 500, body: {} }]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "11. 500 -> TRANSIENT_ERROR/COMPLETED_WITH_ERRORS",
      result.kind === "ACQUISITION_CLOSED" &&
        result.phaseOutcome === "TRANSIENT_ERROR" &&
        closePayloads[0].runStatus === "COMPLETED_WITH_ERRORS",
    );
  }

  // 12. LEASE_LOST -> checkpoint_ devolve false (lease expirada); núcleo para imediatamente,
  // NUNCA chama close_ (o run não é mais seu).
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedAcquiring(0)],
      checkpointQueue: [false],
    });
    const { fetchImpl } = makeFakeFetch([
      cardsPage([{ id: "c1", name: "A" }], false),
    ]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert("12. LEASE_LOST -> kind correto", result.kind === "LEASE_LOST");
    assert(
      "12. LEASE_LOST -> close_ NUNCA chamado",
      closePayloads.length === 0,
    );
  }

  // 13. Matching SAFE/AMBIGUOUS/ABSENT (3 categorias na mesma invocação) -> classificação
  // correta via reuso do núcleo P16.2, sem nenhuma chamada à JustTCG.
  {
    const staging: StagedCardRow[] = [
      {
        externalCardId: "ext-1",
        externalNumber: "001/198",
        externalName: "Bulbasaur",
      }, // único candidato p/ "1" -> SAFE
      {
        externalCardId: "ext-2a",
        externalNumber: "002/198",
        externalName: "Ivysaur (holo)",
      }, // 2 candidatos p/ "2" -> AMBIGUOUS
      {
        externalCardId: "ext-2b",
        externalNumber: "002/198",
        externalName: "Ivysaur",
      },
      // "003" ausente do staging -> ABSENT para a carta local abaixo
    ];
    const localCards: LocalActiveCard[] = [
      {
        cardId: "card-1",
        name: "Bulbasaur",
        collectorNumber: "001",
        collectorTotal: 198,
      },
      {
        cardId: "card-2",
        name: "Ivysaur",
        collectorNumber: "002",
        collectorTotal: 198,
      },
      {
        cardId: "card-3",
        name: "Venusaur",
        collectorNumber: "003",
        collectorTotal: 198,
      },
    ];
    const { port, calls, persistPayloads } = buildFakePort({
      openQueue: [claimedMatching()],
      staging,
      localCards,
    });
    const { fetchImpl, callCount } = makeFakeFetch([]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert("13. Matching -> zero chamada à JustTCG", callCount() === 0);
    assert(
      "13. Matching -> kind MATCHING_CLOSED",
      result.kind === "MATCHING_CLOSED",
    );
    assert(
      "13. Matching -> cardsSafe=1, cardsAmbiguous=1, cardsAbsent=1",
      result.kind === "MATCHING_CLOSED" && result.cardsSafe === 1 &&
        result.cardsAmbiguous === 1 && result.cardsAbsent === 1,
    );
    assert(
      "13. Matching -> persistMatchingBatch recebeu 3 linhas",
      persistPayloads.length === 1 && persistPayloads[0].rows.length === 3,
    );
    assert(
      "13. Matching -> persistMatchingBatch recebeu o syncRunId da própria invocação (autoria automatizada real, nunca um ator fictício)",
      persistPayloads[0].syncRunId === SYNC_RUN_ID,
    );
    const safeRow = persistPayloads[0].rows.find((r) => r.cardId === "card-1");
    assert(
      "13. Matching -> linha SAFE tem external_card_id preenchido",
      safeRow?.classification === "SAFE" && safeRow?.externalCardId === "ext-1",
    );
    assert(
      "13. Matching -> loadFullStaging/loadLocalActiveCards chamados 1x cada (sem N+1)",
      calls.filter((c) => c.startsWith("loadFullStaging")).length === 1 &&
        calls.filter((c) => c.startsWith("loadLocalActiveCards")).length === 1,
    );
  }

  // 14. Retry sem nova chamada externa quando status=MATCHING -> a fila de fetch fica VAZIA
  // de propósito (qualquer chamada real faria makeFakeFetch devolver undefined e o teste
  // falhar ao tentar ler .status); callCount() precisa ficar em 0.
  {
    const { port } = buildFakePort({
      openQueue: [claimedMatching()],
      staging: [],
      localCards: [],
    });
    const { fetchImpl, callCount } = makeFakeFetch([]);
    const client = new JustTcgClient("fake-key", fetchImpl, 10);
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "14. status=MATCHING -> zero chamada à JustTCG (client.requestsMade)",
      client.requestsMade === 0,
    );
    assert("14. status=MATCHING -> zero chamada HTTP real", callCount() === 0);
    assert(
      "14. status=MATCHING -> conclui MATCHING_CLOSED mesmo sem cartas",
      result.kind === "MATCHING_CLOSED",
    );
  }

  // 15. Persistência idempotente -> mesmo lote de matching processado 2x (simulando uma
  // retomada após falha entre a persistência e o close_) produz, na 2ª vez, ações NOOP —
  // nunca duplica mapping/identity. A fake usa decideMappingUpsert (P16.2) real, não uma
  // reimplementação divergente.
  {
    const store = new FakeMappingStore();
    const staging: StagedCardRow[] = [{
      externalCardId: "ext-9",
      externalNumber: "009/198",
      externalName: "Squirtle",
    }];
    const localCards: LocalActiveCard[] = [{
      cardId: "card-9",
      name: "Squirtle",
      collectorNumber: "009",
      collectorTotal: 198,
    }];
    const persistImpl = (
      _pricingSourceId: string,
      _syncRunId: string,
      rows: readonly PersistBootstrapRowInput[],
    ) => store.persist(rows);

    const { port: port1 } = buildFakePort({
      openQueue: [claimedMatching()],
      staging,
      localCards,
      persistImpl,
    });
    const client1 = new JustTcgClient(
      "fake-key",
      makeFakeFetch([]).fetchImpl,
      10,
    );
    const result1 = await executeBootstrapAttempt(
      port1,
      client1,
      PRICING_SOURCE_ID,
    );
    assert(
      "15a. 1ª persistência -> mappingsInserted=1",
      result1.kind === "MATCHING_CLOSED" && result1.mappingsInserted === 1,
    );
    assert(
      "15a. 1ª persistência -> identitiesCreated=1",
      result1.kind === "MATCHING_CLOSED" && result1.identitiesCreated === 1,
    );

    const { port: port2 } = buildFakePort({
      openQueue: [claimedMatching()],
      staging,
      localCards,
      persistImpl,
    });
    const client2 = new JustTcgClient(
      "fake-key",
      makeFakeFetch([]).fetchImpl,
      10,
    );
    const result2 = await executeBootstrapAttempt(
      port2,
      client2,
      PRICING_SOURCE_ID,
    );
    assert(
      "15b. 2ª persistência (retry idêntico) -> mappingsInserted=0",
      result2.kind === "MATCHING_CLOSED" && result2.mappingsInserted === 0,
    );
    assert(
      "15b. 2ª persistência -> mappingsNoop=1 (nunca duplica)",
      result2.kind === "MATCHING_CLOSED" && result2.mappingsNoop === 1,
    );
    assert(
      "15b. 2ª persistência -> identitiesCreated=0 (ON CONFLICT DO NOTHING)",
      result2.kind === "MATCHING_CLOSED" && result2.identitiesCreated === 0,
    );
  }

  // 16. Falha durante persistência -> persistMatchingBatch devolve {ok:false}; fecha com
  // TRANSIENT_ERROR/COMPLETED_WITH_ERRORS, nunca lança exceção não tratada.
  {
    const staging: StagedCardRow[] = [{
      externalCardId: "ext-1",
      externalNumber: "001/1",
      externalName: "X",
    }];
    const localCards: LocalActiveCard[] = [{
      cardId: "card-1",
      name: "X",
      collectorNumber: "001",
      collectorTotal: 1,
    }];
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedMatching()],
      staging,
      localCards,
      persistImpl: () => ({ ok: false }),
    });
    const client = new JustTcgClient(
      "fake-key",
      makeFakeFetch([]).fetchImpl,
      10,
    );
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "16. Falha na persistência -> phaseOutcome=TRANSIENT_ERROR",
      result.kind === "MATCHING_CLOSED" &&
        result.phaseOutcome === "TRANSIENT_ERROR",
    );
    assert(
      "16. Falha na persistência -> close_ chamado com TRANSIENT_ERROR/COMPLETED_WITH_ERRORS",
      closePayloads[0].phaseOutcome === "TRANSIENT_ERROR" &&
        closePayloads[0].runStatus === "COMPLETED_WITH_ERRORS",
    );
  }

  // 16b. Falha na leitura local (staging/cartas) durante matching -> TRANSIENT_ERROR/FAILED,
  // close_ chamado com erro sanitizado, zero trabalho inventado.
  {
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedMatching()],
      throwOnLoadStaging: true,
    });
    const client = new JustTcgClient(
      "fake-key",
      makeFakeFetch([]).fetchImpl,
      10,
    );
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "16b. Leitura local falha -> TRANSIENT_ERROR/FAILED",
      result.kind === "MATCHING_CLOSED" &&
        result.phaseOutcome === "TRANSIENT_ERROR" &&
        closePayloads[0].runStatus === "FAILED",
    );
  }

  // 17. Fechamento COMPLETE só quando a reconciliação do banco passa -> o núcleo NUNCA afirma
  // COMPLETE por conta própria; sempre relaya o finalStatus que a RPC close_ devolveu, mesmo
  // quando a RPC recusa (RECONCILIATION_INCOMPLETE) após MATCHING_COMPLETE ser enviado.
  {
    const staging: StagedCardRow[] = [{
      externalCardId: "ext-1",
      externalNumber: "001/1",
      externalName: "X",
    }];
    const localCards: LocalActiveCard[] = [{
      cardId: "card-1",
      name: "X",
      collectorNumber: "001",
      collectorTotal: 1,
    }];
    const { port, closePayloads } = buildFakePort({
      openQueue: [claimedMatching()],
      staging,
      localCards,
      closeQueue: ["RECONCILIATION_INCOMPLETE"],
    });
    const client = new JustTcgClient(
      "fake-key",
      makeFakeFetch([]).fetchImpl,
      10,
    );
    const result = await executeBootstrapAttempt(
      port,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "17. RPC recusa completude -> núcleo envia MATCHING_COMPLETE mesmo assim",
      closePayloads[0].phaseOutcome === "MATCHING_COMPLETE",
    );
    assert(
      "17. RPC recusa completude -> finalStatus relayado sem reinterpretação",
      result.kind === "MATCHING_CLOSED" &&
        result.finalStatus === "RECONCILIATION_INCOMPLETE",
    );

    // Caminho feliz -- quando a RPC confirma, o finalStatus também é relayado sem alteração.
    const { port: portOk, closePayloads: closePayloadsOk } = buildFakePort({
      openQueue: [claimedMatching()],
      staging,
      localCards,
      closeQueue: ["COMPLETE"],
    });
    const resultOk = await executeBootstrapAttempt(
      portOk,
      client,
      PRICING_SOURCE_ID,
    );
    assert(
      "17b. RPC confirma completude -> finalStatus=COMPLETE relayado",
      resultOk.kind === "MATCHING_CLOSED" &&
        resultOk.finalStatus === "COMPLETE",
    );
    assert(
      "17b. Ambos os casos chamaram close_ com MATCHING_COMPLETE/COMPLETED",
      closePayloadsOk[0].phaseOutcome === "MATCHING_COMPLETE" &&
        closePayloadsOk[0].runStatus === "COMPLETED",
    );
  }

  console.log(
    `\n${failures === 0 ? "TODOS OS TESTES PASSARAM" : `${failures} FALHA(S)`}`,
  );
  if (failures > 0) throw new Error(`${failures} teste(s) falharam.`);
}

Deno.test(
  "pricing-justtcg-bootstrap: suite offline completa (P16.5.2/P16.5.3)",
  main,
);
