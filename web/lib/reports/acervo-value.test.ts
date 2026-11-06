// V1-14 R1-C — "Valor estimado total": projeção por Card Set do inventário com preços.
// Executar: node --experimental-strip-types --test lib/reports/acervo-value.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { type SetInventoryItemInput, type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import {
  buildAcervoValueReport,
  priceObservationPeriod,
  valueCoveragePercent,
  valueCoverageText,
  valueShareBarPercent,
  valueShareText,
} from "./acervo-value.ts";

const item = (id: string, set: string, name: string, copies: number): SetInventoryItemInput => ({
  cardVariantId: id,
  languageCode: "EN",
  cardName: `Carta ${id}`,
  collectorNumber: "1",
  collectorTotal: 100,
  cardSetCode: set,
  cardSetName: name,
  variantLabel: null,
  isDefaultVariant: true,
  copies,
});
const price = (brl: number, basis: SetInventoryPriceInput["basis"] = "VARIANT", observedAt = "2026-11-05T12:00:00Z"): SetInventoryPriceInput => ({
  brl,
  basis,
  observedAt,
});

function inventory(items: SetInventoryItemInput[], prices: Record<string, SetInventoryPriceInput>, itemsComplete = true) {
  const totalCopies = items.reduce((n, i) => n + i.copies, 0);
  return buildSetInventoryReport({
    summary: { totalCopies, distinctItems: items.length, distinctSets: new Set(items.map((i) => i.cardSetCode)).size, duplicateCopies: totalCopies - items.length },
    items,
    prices: new Map(Object.entries(prices)),
    itemsComplete,
  });
}

test("valor: soma por Card Set em centavos, total = Σ Sets, sem cotação fora (nunca zero), ordem por valor", () => {
  const inv = inventory(
    [item("a1", "AAA", "Alpha", 3), item("a2", "AAA", "Alpha", 1), item("b1", "BBB", "Beta", 2), item("c1", "CCC", "Gama", 4)],
    // 0,10 × 3 = 0,30 (sem erro de ponto flutuante); a2 sem preço; b1 = 2 × 0,35 = 0,70; Gama sem nenhum cotado.
    { a1: price(0.1), b1: price(0.35, "CARD_FALLBACK", "2026-11-03T10:00:00Z"), c1: price(0) },
  );
  const r = buildAcervoValueReport(inv);
  assert.equal(r.totalBrl, 1.0);
  assert.deepEqual(
    r.sets.map((s) => [s.code, s.copies, s.pricedCopies, s.unpricedCopies, s.valueBrl]),
    [
      ["BBB", 2, 2, 0, 0.7],
      ["AAA", 4, 3, 1, 0.3],
      ["CCC", 4, 0, 4, null], // sem cotado: sem valor monetário fictício, por último
    ],
  );
  assert.equal(r.totalCopies, 10);
  assert.equal(r.pricedCopies, 5);
  assert.equal(r.unpricedCopies, 5);
  assert.equal(r.setCount, 3);
  assert.equal(r.pricedSetCount, 2);
  assert.equal(r.fallbackCopies, 2);
  assert.equal(r.sets[0]!.share, 0.7);
  assert.equal(r.sets[2]!.share, null);
  assert.equal(r.sets.reduce((n, s) => n + s.unpricedCopies, 0), r.unpricedCopies); // por Set fecha com o total
  assert.equal(priceObservationPeriod(r), "03/11/2026 a 05/11/2026");
  assert.equal(r.complete, true);
});

test("ordem determinística: valor igual → nome e código (pt-BR); Sets sem cotação também por nome", () => {
  const inv = inventory(
    [item("x", "ZZ2", "Ébano", 1), item("y", "ZZ1", "Ébano", 1), item("w", "AA9", "Ametista", 1), item("n1", "N2", "Nulo B", 1), item("n2", "N1", "Nulo A", 1)],
    { x: price(1), y: price(1), w: price(1) },
  );
  assert.deepEqual(
    buildAcervoValueReport(inv).sets.map((s) => s.code),
    ["AA9", "ZZ1", "ZZ2", "N1", "N2"],
  );
});

test("participação: uma casa decimal truncada, <0,1% para mínimas, sem ajuste para 100%", () => {
  assert.equal(valueShareText(null), "—");
  assert.equal(valueShareText(0), "—");
  assert.equal(valueShareText(1), "100,0%");
  assert.equal(valueShareText(0.9999), "99,9%"); // nunca arredonda para 100,0%
  assert.equal(valueShareText(0.12345), "12,3%");
  assert.equal(valueShareText(0.1239), "12,3%"); // truncado, não arredondado
  assert.equal(valueShareText(0.001), "0,1%");
  assert.equal(valueShareText(0.000999), "<0,1%");
  assert.equal(valueShareText(0.0000001), "<0,1%");
  // Três Sets iguais: 33,3% cada — a soma exibida (99,9%) não é ajustada.
  const inv = inventory([item("a", "A", "A", 1), item("b", "B", "B", 1), item("c", "C", "C", 1)], { a: price(1), b: price(1), c: price(1) });
  assert.deepEqual(buildAcervoValueReport(inv).sets.map((s) => valueShareText(s.share)), ["33,3%", "33,3%", "33,3%"]);
  assert.equal(valueShareBarPercent(null), 0);
  assert.equal(valueShareBarPercent(0.5), 50);
  assert.ok(valueShareBarPercent(0.00001) > 0); // participação positiva mínima continua visível
});

test("cobertura: proporção de exemplares com preço (truncada), sem cotação nenhum e acervo vazio", () => {
  const inv = inventory([item("a", "A", "A", 2), item("b", "B", "B", 1)], { a: price(2) });
  const r = buildAcervoValueReport(inv);
  assert.equal(valueCoverageText(r), "2 de 3 exemplares com preço");
  assert.equal(valueCoveragePercent(r), "66%");
  const none = buildAcervoValueReport(inventory([item("a", "A", "A", 2)], {}));
  assert.equal(none.totalBrl, null);
  assert.equal(none.pricedSetCount, 0);
  assert.equal(none.sets[0]!.share, null);
  assert.equal(priceObservationPeriod(none), null);
  const empty = buildAcervoValueReport(inventory([], {}));
  assert.equal(empty.totalCopies, 0);
  assert.equal(empty.sets.length, 0);
});

test("completude herdada do inventário: incompleto bloqueia a impressão", () => {
  const tooLarge = buildAcervoValueReport(inventory([item("a", "A", "A", 1)], { a: price(1) }, false));
  assert.equal(tooLarge.complete, false);
  assert.equal(tooLarge.incompleteReason, "too_large");
  const inv = inventory([item("a", "A", "A", 1)], { a: price(1) });
  const mismatch = buildAcervoValueReport({ ...inv, complete: false, incompleteReason: "mismatch" });
  assert.equal(mismatch.incompleteReason, "mismatch");
});

const src = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

test("leitura: reaproveita a do inventário detalhado (5160/5159/3989, 2 preços simultâneos), sem SQL nem 5353", () => {
  const queries = src("./acervo-set-inventory-queries.ts");
  assert.match(queries, /export const PRICE_PARALLEL = 2;/);
  assert.match(queries, /getAcervoValueReport[\s\S]*readPricedInventory\(supabase\)[\s\S]*buildAcervoValueReport\(read\.report\)/);
  assert.equal((queries.match(/\.rpc\("get_card_variants_pricing_summary"/g) ?? []).length, 1); // uma única leitura de preços
  assert.doesNotMatch(queries, /get_my_inventory_value_report|inventory-value/);
  const action = src("../../app/colecoes/acervo/relatorios/actions.ts");
  assert.match(action, /export async function readAcervoValueReport\(\): Promise<AcervoValueReportLoad>/);
  assert.match(action, /if \(!user\) return \{ status: "error" \}/);
  const lib = src("./acervo-value.ts");
  assert.doesNotMatch(lib, /\.rpc\(|from "@supabase/);
});

test("folha: sem linhas por carta, sem lista de sem cotação, sem histórico/rentabilidade/custo/Top 10", () => {
  const sheet = src("../../components/reports/acervo-value-report.tsx");
  assert.match(sheet, /acervoReport\("value"\)/);
  assert.match(sheet, /não é avaliação nem garantia de valor de venda/);
  assert.match(sheet, /não mede a precisão nem a completude do valor patrimonial/);
  assert.match(sheet, /PTAX/);
  assert.doesNotMatch(sheet, /\.lines|collectorLabel|rentabilidade|custo de aquisição|histórico|Top 10/i);
  const overlay = src("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /report === "value"[\s\S]*readAcervoValueReport\(\)[\s\S]*setInventoryIncompleteText\(r\.data\.report\.incompleteReason\)/);
});
