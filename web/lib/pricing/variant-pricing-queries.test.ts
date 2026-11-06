// PRICING TIMEOUT CORRECTION-01 — leitura de preços por variante (3989) com concorrência limitada,
// uma nova tentativa para 57014 e estado explícito (completa / parcial / indisponível).
// Executar: node --experimental-strip-types --test lib/pricing/variant-pricing-queries.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { getMasterSetPositionPrices, getPokedexPositionPrices, getSetPositionPrices } from "./position-pricing-queries.ts";
import { combinePriceIssue, priceReadNoticeText } from "./variant-pricing.ts";
import {
  TIMEOUT_RETRY_DELAY_MS,
  VARIANT_PRICES_PARALLEL,
  getVariantPrices,
  readVariantPrices,
  runLimited,
} from "./variant-pricing-queries.ts";

// Silencia os logs estruturados esperados (falhas simuladas) sem perdê-los: ficam em `logs`.
const logs: string[] = [];
console.error = (line: unknown) => void logs.push(String(line));
console.warn = (line: unknown) => void logs.push(String(line));
/** Só as linhas estruturadas da leitura (ignora avisos do próprio Node). */
const entries = () => logs.filter((line) => line.startsWith("{")).map((line) => JSON.parse(line));

const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const ids = (count: number, from = 1) => Array.from({ length: count }, (_, i) => uuid(from + i));

function row(id: string, brl: number | null = 12.5, hasPricing = true) {
  return {
    card_variant_id: id,
    has_pricing: hasPricing,
    brl_amount: brl,
    source_amount: brl === null ? null : 2.5,
    source_currency: "USD",
    fx_status: "CONVERTED",
    printing_label: "Normal",
    price_basis: "VARIANT",
    price_origin: "AUTOMATIC",
    observed_at: "2026-11-01T00:00:00Z",
  };
}

type Response = { data: unknown; error: { code?: string } | null };
type Script = (chunk: string[], attempt: number) => Response | Promise<Response>;

/** Cliente falso: registra cada chamada, a simultaneidade máxima e responde pelo roteiro. */
function fakeClient(script: Script = (chunk) => ({ data: chunk.map((id) => row(id)), error: null }), delayMs = 5) {
  const calls: { fn: string; ids: string[] }[] = [];
  const attempts = new Map<string, number>();
  let inFlight = 0;
  let maxInFlight = 0;
  const client = {
    rpc: async (fn: string, args: Record<string, unknown>): Promise<Response> => {
      const chunk = (args.p_card_variant_ids as string[]) ?? [];
      calls.push({ fn, ids: chunk });
      const key = chunk[0] ?? "";
      const attempt = (attempts.get(key) ?? 0) + 1;
      attempts.set(key, attempt);
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
      inFlight -= 1;
      return script(chunk, attempt);
    },
  };
  return { client, calls, max: () => maxInFlight };
}

const noWait = { wait: async () => {} };
const TIMEOUT = { data: null, error: { code: "57014" } };

test("1. lotes de até 100 variantes, sem repetição, na ordem", async () => {
  const { client, calls } = fakeClient();
  const read = await readVariantPrices(client, [...ids(250), uuid(1), null, "não-uuid"], noWait);
  assert.deepEqual(
    calls.map((call) => call.ids.length),
    [100, 100, 50],
  );
  assert.ok(calls.every((call) => call.fn === "get_card_variants_pricing_summary"));
  assert.equal(read.status, "complete");
  assert.equal(read.prices.size, 250);
  assert.deepEqual([...read.prices.keys()], ids(250));
});

test("2. no máximo 2 chamadas simultâneas", async () => {
  assert.equal(VARIANT_PRICES_PARALLEL, 2);
  const { client, calls, max } = fakeClient(undefined, 15);
  await readVariantPrices(client, ids(520), noWait);
  assert.equal(calls.length, 6);
  assert.equal(max(), 2);
  // runLimited preserva a ordem dos resultados e respeita o teto.
  let running = 0;
  let peak = 0;
  const out = await runLimited(
    [30, 5, 20, 1, 10].map((ms, i) => async () => {
      running += 1;
      peak = Math.max(peak, running);
      await new Promise((resolve) => setTimeout(resolve, ms));
      running -= 1;
      return i;
    }),
    2,
  );
  assert.deepEqual(out, [0, 1, 2, 3, 4]);
  assert.equal(peak, 2);
});

test("3. 57014 recuperado com uma única nova tentativa, após espera curta", async () => {
  const waits: number[] = [];
  const { client, calls } = fakeClient((chunk, attempt) => (chunk[0] === uuid(101) && attempt === 1 ? TIMEOUT : { data: chunk.map((id) => row(id)), error: null }));
  const read = await readVariantPrices(client, ids(150), { wait: async (ms) => void waits.push(ms) });
  assert.equal(read.status, "complete");
  assert.equal(read.prices.size, 150);
  assert.equal(calls.length, 3);
  assert.deepEqual(waits, [TIMEOUT_RETRY_DELAY_MS]);
  assert.ok(TIMEOUT_RETRY_DELAY_MS > 0 && TIMEOUT_RETRY_DELAY_MS <= 1000);
  const retryLog = entries().find((entry) => entry.scope === "pricing.variants.retry" && entry.outcome === "recovered");
  assert.ok(retryLog, "registra a recuperação");
  assert.equal(retryLog.ids, 50);
  assert.equal(typeof retryLog.firstMs, "number");
  assert.equal(typeof retryLog.retryMs, "number");
  assert.ok(!JSON.stringify(retryLog).includes(uuid(101)), "log sem ids");
});

test("4. falha persistente depois da nova tentativa: bloco indisponível, sem terceira chamada", async () => {
  logs.length = 0;
  const { client, calls } = fakeClient((chunk) => (chunk[0] === uuid(1) ? TIMEOUT : { data: chunk.map((id) => row(id)), error: null }));
  const read = await readVariantPrices(client, ids(172), noWait);
  assert.equal(calls.filter((call) => call.ids[0] === uuid(1)).length, 2);
  assert.equal(read.status, "partial");
  assert.deepEqual(read.unavailableIds, ids(100));
  assert.equal(read.prices.size, 72);
  const logged = entries();
  assert.ok(logged.some((entry) => entry.scope === "pricing.variants.retry" && entry.outcome === "failed" && entry.retryCode === "57014"));
  assert.ok(logged.some((entry) => entry.scope === "pricing.variants.read" && entry.code === "57014" && entry.ids === 100));
});

test("5. erros não recuperáveis não são repetidos (permissão, formato, exceção)", async () => {
  for (const failure of [
    () => ({ data: null, error: { code: "42501" } }),
    () => ({ data: { not: "a list" }, error: null }),
    () => {
      throw new Error("rede");
    },
  ] as Script[]) {
    const { client, calls } = fakeClient((chunk, attempt) => (chunk[0] === uuid(1) ? failure(chunk, attempt) : { data: chunk.map((id) => row(id)), error: null }));
    const read = await readVariantPrices(client, ids(100), noWait);
    assert.equal(calls.length, 1);
    assert.equal(read.status, "unavailable");
    assert.equal(read.prices.size, 0);
    assert.deepEqual(read.unavailableIds, ids(100));
  }
});

test("6. preços válidos dos blocos lidos são preservados, valores intactos", async () => {
  const { client } = fakeClient((chunk) =>
    chunk[0] === uuid(101) ? { data: null, error: { code: "XX000" } } : { data: chunk.map((id, i) => row(id, 10 + i)), error: null },
  );
  const read = await readVariantPrices(client, ids(250), noWait);
  assert.equal(read.status, "partial");
  assert.equal(read.prices.get(uuid(1))?.brlAmount, 10);
  assert.equal(read.prices.get(uuid(250))?.brlAmount, 10 + 49);
  assert.equal(read.prices.has(uuid(150)), false);
  assert.ok(read.unavailableIds.includes(uuid(150)));
});

test("7. ausência confirmada de cotação ≠ indisponibilidade", async () => {
  // Bloco 1 lido: id 1 com cotação, id 2 sem cotação (has_pricing = false), id 3 sem linha. Bloco 2 falha.
  const { client } = fakeClient((chunk) =>
    chunk[0] === uuid(1)
      ? { data: [row(uuid(1)), row(uuid(2), null, false)], error: null }
      : { data: null, error: { code: "57014" } },
  );
  const read = await readVariantPrices(client, ids(150), noWait);
  assert.equal(read.status, "partial");
  assert.equal(read.prices.get(uuid(1))?.hasPricing, true);
  assert.equal(read.prices.get(uuid(2))?.hasPricing, false); // ausência confirmada
  assert.equal(read.prices.get(uuid(2))?.brlAmount, null); // nunca zero
  assert.equal(read.prices.has(uuid(3)), false); // lido, sem linha → sem preço
  assert.equal(read.unavailableIds.includes(uuid(3)), false);
  assert.equal(read.unavailableIds.includes(uuid(101)), true); // falha → indisponível
  for (const price of read.prices.values()) assert.notEqual(price.brlAmount, 0);
  assert.equal(priceReadNoticeText("complete"), null);
  assert.equal(priceReadNoticeText(null), null);
  assert.match(priceReadNoticeText("partial") ?? "", /Alguns preços de referência não puderam ser carregados/);
  assert.match(priceReadNoticeText("unavailable") ?? "", /não puderam ser carregados/);
  assert.doesNotMatch(`${priceReadNoticeText("partial")} ${priceReadNoticeText("unavailable")}`, /sem cotação|R\$ ?0/i);
});

test("8. agregados: estado parcial nunca é apresentado como completo", async () => {
  const { client } = fakeClient((chunk) => (chunk[0] === uuid(101) ? TIMEOUT : { data: chunk.map((id) => row(id)), error: null }));
  const read = await readVariantPrices(client, ids(150), noWait);
  assert.notEqual(read.status, "complete");
  assert.equal(read.prices.size + read.unavailableIds.length, 150); // nada some em silêncio
  // Grade da Pokédex: página do servidor + "Mostrar mais".
  assert.equal(combinePriceIssue(null, "complete"), null);
  assert.equal(combinePriceIssue(null, "partial"), "partial");
  assert.equal(combinePriceIssue(null, "unavailable"), "partial");
  assert.equal(combinePriceIssue("unavailable", "unavailable"), "unavailable");
  assert.equal(combinePriceIssue("unavailable", "complete"), "partial");
  assert.equal(combinePriceIssue("partial", "complete"), "partial");
  // As telas da coleção não somam preços (só etiquetas por posição): nenhum agregado a suprimir.
  for (const file of ["collection-view.tsx", "master-set-gallery.tsx", "pokedex-grid.tsx", "free-collection-view.tsx"]) {
    const source = readFileSync(new URL(`../../components/colecoes/colecoes/${file}`, import.meta.url), "utf8");
    assert.doesNotMatch(source, /brlAmount\s*[+*]|reduce\([^)]*brlAmount/, `${file} não agrega preços`);
  }
});

test("9a. compatibilidade: getVariantPrices continua tudo-ou-nada (Acervo, Lista de desejos)", async () => {
  const ok = fakeClient();
  const complete = await getVariantPrices(ok.client as never, ids(48));
  assert.ok(complete instanceof Map);
  assert.equal(complete?.size, 48);
  const empty = fakeClient();
  assert.deepEqual(await getVariantPrices(empty.client as never, [null, "x"]), new Map());
  assert.equal(empty.calls.length, 0);
  const partial = fakeClient((chunk) => (chunk[0] === uuid(101) ? { data: null, error: { code: "42501" } } : { data: chunk.map((id) => row(id)), error: null }));
  assert.equal(await getVariantPrices(partial.client as never, ids(150)), null); // nunca "sem preço" para o que não foi lido
});

test("9b. compatibilidade: Set, Master Set e Pokédex devolvem estado + preços por posição", async () => {
  const cards = ids(3, 9000);
  const variants = ids(3, 500);
  const client = {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_my_collection_card_variants") {
        return { data: cards.map((cardId, i) => ({ card_id: cardId, card_variant_id: variants[i], variant_type_id: null, variant_label: "Normal", language_code: "en", copies: 1 })), error: null };
      }
      if (fn === "get_my_pokedex_representative_variants") return { data: null, error: { code: "57014" } };
      const chunk = args.p_card_variant_ids as string[];
      return { data: chunk.filter((id) => id !== variants[2]).map((id) => row(id)), error: null };
    },
  };
  const set = await getSetPositionPrices(client as never, uuid(1), cards.map((cardId) => ({ cardId, copiesInCollection: 1 })));
  assert.equal(set.status, "complete");
  assert.deepEqual(Object.keys(set.prices).sort(), [cards[0], cards[1]].sort()); // terceira: sem cotação confirmada
  const master = await getMasterSetPositionPrices(client as never, uuid(1), cards.map((cardId, i) => ({ key: `k${i}`, cardId, variantTypeId: null, copiesInCollection: 1 })));
  assert.equal(master.status, "complete");
  assert.equal(master.prices.k0?.price.brlAmount, 12.5);
  const none = await getSetPositionPrices(client as never, uuid(1), [{ cardId: cards[0] as string, copiesInCollection: 0 }]);
  assert.deepEqual(none, { status: "complete", prices: {} });
  const pokedex = await getPokedexPositionPrices(client as never, uuid(1), [
    { positionId: uuid(77), isSatisfied: true, representative: { collectorNumber: "1", setCode: "sv1" } },
  ]);
  assert.deepEqual(pokedex, { status: "unavailable", prices: {} }); // 5334 falhou: indisponível, nunca "sem preço"
});
