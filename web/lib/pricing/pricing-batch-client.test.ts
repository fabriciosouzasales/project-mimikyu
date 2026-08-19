// Teste unitário focado em estado/cache do detalhe de preço sob demanda
// (`fetchLiveDetail`/`getCachedLiveDetail`), escrito para reproduzir a causa
// raiz do bug "primeiro hover trava em 'Carregando detalhes...'"
// (2026-08-19): o efeito em `CardPriceDetails` (card-price-summary.tsx) tinha
// `liveStatus` na lista de dependências do próprio `useEffect` que o define
// via `setLiveStatus("loading")`, disparando um re-run/cleanup imediato que
// marcava `cancelled = true` antes da resposta real chegar — a resposta era
// descartada silenciosamente, mas ficava em `liveDetailCache` (por isso o
// segundo hover mostrava o dado na hora). Esse arquivo não reproduz o efeito
// React em si (não há infraestrutura de teste de componente/DOM no projeto —
// zero Jest/Vitest/Testing Library em package.json — e este teste
// deliberadamente não introduz nenhum framework novo); em vez disso, cobre o
// contrato de cache/dedupe do módulo do qual o efeito depende, usando apenas
// `node:test`/`node:assert` (nativos do Node, já disponíveis no runtime do
// projeto). A validação do próprio fluxo do efeito React é o roteiro visual
// manual descrito no relatório da correção (hover/foco/toque, troca rápida
// entre cartas, resposta após fechamento).
//
// Executar: node --experimental-strip-types --test lib/pricing/pricing-batch-client.test.ts
// (a partir de web/, sem instalar nada — Node 22 já suporta TypeScript nativo
// para este tipo de arquivo, que só usa sintaxe apagável: sem enum/namespace).

import assert from "node:assert/strict";
import { test } from "node:test";
import { fetchLiveDetail, getCachedLiveDetail, type PricingSnapshotRow } from "./pricing-batch-client.ts";

function nextCardId(): string {
  // UUID v4-ish sintético, único por teste — evita colisão com o cache
  // module-level compartilhado entre casos de teste no mesmo processo.
  return `00000000-0000-4000-8000-${Math.random().toString(16).slice(2).padEnd(12, "0").slice(0, 12)}`;
}

const sampleRow: PricingSnapshotRow = {
  sourceCode: "JUSTTCG",
  sourceName: "JustTCG",
  priceType: "MARKET",
  originalAmount: 42.11,
  originalCurrencyCode: "USD",
  equivalentBrlAmount: 219.15,
  fxStatus: "CONVERTED",
  fxRate: 5.2043,
  fxRateDate: "2026-08-19",
  equivalentLabel: "Equivalente em BRL pela PTAX Venda",
  conditionCode: "NM",
  conditionName: "Near Mint",
  printingLabel: "Unlimited Holofoil",
  marketLabel: null,
  observedAt: "2026-08-19T13:00:00Z",
};

test("fetchLiveDetail: chamadas concorrentes para a mesma carta geram uma única requisição de rede (dedupe in-flight)", async () => {
  const cardId = nextCardId();
  let networkCalls = 0;
  globalThis.fetch = (async () => {
    networkCalls++;
    await new Promise((resolve) => setTimeout(resolve, 10));
    return {
      ok: true,
      json: async () => ({ mode: "live", rows: [sampleRow] }),
    } as Response;
  }) as typeof fetch;

  const [first, second] = await Promise.all([fetchLiveDetail(cardId), fetchLiveDetail(cardId)]);

  assert.equal(networkCalls, 1, "duas chamadas simultâneas devem compartilhar a mesma requisição em voo");
  assert.deepEqual(first, [sampleRow]);
  assert.deepEqual(second, [sampleRow]);
});

test("fetchLiveDetail: resultado fica em cache e evita nova chamada de rede em requisições subsequentes", async () => {
  const cardId = nextCardId();
  let networkCalls = 0;
  globalThis.fetch = (async () => {
    networkCalls++;
    return { ok: true, json: async () => ({ mode: "live", rows: [sampleRow] }) } as Response;
  }) as typeof fetch;

  assert.equal(getCachedLiveDetail(cardId), undefined, "carta sem chamada prévia não deve estar em cache");

  await fetchLiveDetail(cardId);
  await fetchLiveDetail(cardId);
  await fetchLiveDetail(cardId);

  assert.equal(networkCalls, 1, "chamadas após a primeira resolução devem ser servidas pelo cache, sem nova rede");
  assert.deepEqual(getCachedLiveDetail(cardId), [sampleRow]);
});

test("fetchLiveDetail: resposta HTTP não-ok resolve com array vazio e não grava cache (permite nova tentativa depois)", async () => {
  const cardId = nextCardId();
  globalThis.fetch = (async () => ({ ok: false, json: async () => ({}) })) as unknown as typeof fetch;

  const rows = await fetchLiveDetail(cardId);

  assert.deepEqual(rows, []);
  assert.equal(getCachedLiveDetail(cardId), undefined, "falha não deve 'envenenar' o cache permanentemente");
});

test("fetchLiveDetail: falha de rede (exceção) resolve com array vazio, nunca rejeita a promise", async () => {
  const cardId = nextCardId();
  globalThis.fetch = (async () => {
    throw new Error("network down");
  }) as unknown as typeof fetch;

  await assert.doesNotReject(fetchLiveDetail(cardId));
  const rows = await fetchLiveDetail(cardId);
  assert.deepEqual(rows, []);
});

test("fetchLiveDetail: payload com error ou sem rows resolve com array vazio", async () => {
  const cardId = nextCardId();
  globalThis.fetch = (async () => ({
    ok: true,
    json: async () => ({ mode: "live", error: "pricing_summary_failed" }),
  })) as unknown as typeof fetch;

  const rows = await fetchLiveDetail(cardId);
  assert.deepEqual(rows, []);
});

test("fetchLiveDetail: cartas diferentes não compartilham cache nem deduplicação entre si", async () => {
  const cardA = nextCardId();
  const cardB = nextCardId();
  let networkCalls = 0;
  globalThis.fetch = (async (input: string | URL) => {
    networkCalls++;
    const url = String(input);
    const rows = url.includes(cardA) ? [{ ...sampleRow, originalAmount: 1 }] : [{ ...sampleRow, originalAmount: 2 }];
    return { ok: true, json: async () => ({ mode: "live", rows }) } as Response;
  }) as typeof fetch;

  const [rowsA, rowsB] = await Promise.all([fetchLiveDetail(cardA), fetchLiveDetail(cardB)]);

  assert.equal(networkCalls, 2, "duas cartas distintas em voo ao mesmo tempo geram duas requisições, uma por carta");
  assert.equal(rowsA[0]?.originalAmount, 1);
  assert.equal(rowsB[0]?.originalAmount, 2);
});
