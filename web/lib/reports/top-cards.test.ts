// V1-14 R1-F — "Top 10 cartas mais valiosas" (6º relatório do Meu acervo): ranking unitário,
// desempates, idiomas, fallback, desatualizada, empate na 10ª, concentração, falha parcial e leitura.
// Executar: node --experimental-strip-types --test lib/reports/top-cards.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { acervoReportMenuItems } from "./acervo-reports.ts";
import { type SetInventoryItemInput, type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { buildAcervoValueReport } from "./acervo-value.ts";
import { getTopCardsReport } from "./top-cards-queries.ts";
import {
  TOP_CARDS_LIMIT,
  buildTopCardsReport,
  topCardsIncompleteText,
  topCoverageText,
  topIdentityText,
  topObservedText,
  topPriceFlags,
  topTiedText,
} from "./top-cards.ts";

console.error = () => {};
console.warn = () => {};

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const NOW = Date.parse("2026-11-06T12:00:00Z");

let seq = 0;
function item(over: Partial<SetInventoryItemInput> = {}): SetInventoryItemInput {
  seq += 1;
  return {
    cardVariantId: uuid(seq),
    languageCode: "en",
    languageName: "Inglês",
    cardName: `Carta ${seq}`,
    collectorNumber: String(seq),
    collectorTotal: 200,
    cardSetCode: "AAA",
    cardSetName: "Alfa",
    variantLabel: "Normal",
    isDefaultVariant: true,
    copies: 1,
    imagePath: null,
    ...over,
  };
}
const price = (brl: number, over: Partial<SetInventoryPriceInput> = {}): SetInventoryPriceInput => ({ brl, basis: "VARIANT", observedAt: "2026-11-03T00:00:00Z", ...over });

function top(items: SetInventoryItemInput[], prices: Map<string, SetInventoryPriceInput>, unavailable = new Set<string>(), itemsComplete = true) {
  const copies = items.reduce((n, i) => n + i.copies, 0);
  const inventory = buildSetInventoryReport({
    summary: { totalCopies: copies, distinctItems: items.length, distinctSets: new Set(items.map((i) => i.cardSetCode)).size, duplicateCopies: 0 },
    items,
    prices,
    itemsComplete,
  });
  return { inventory, report: buildTopCardsReport({ inventory, prices, unavailable, now: NOW }) };
}

test("ranking pela referência UNITÁRIA em centavos, decrescente; a quantidade não muda a posição", () => {
  const a = item({ copies: 50 }); // barata, muitas cópias
  const b = item({ copies: 1 });
  const c = item({ copies: 3 });
  const { report } = top([a, b, c], new Map([[a.cardVariantId, price(10)], [b.cardVariantId, price(300.1)], [c.cardVariantId, price(300.09)]]));
  assert.deepEqual(report.lines.map((l) => [l.rank, l.cardVariantId]), [
    [1, b.cardVariantId],
    [2, c.cardVariantId],
    [3, a.cardVariantId],
  ]);
  assert.equal(report.lines[2]?.copiesBrl, 500); // 50 × R$ 10 — só no valor das cópias
  assert.equal(report.lines[1]?.copiesBrl, 900.27);
});

test("desempates: Card Set (pt-BR), número crescente, variante, idioma e id estável", () => {
  const p = (it: SetInventoryItemInput) => [it.cardVariantId, price(50)] as const;
  const s2 = item({ cardSetName: "Beta", cardSetCode: "BBB", collectorNumber: "1" });
  const s1n10 = item({ cardSetName: "alfa", cardSetCode: "AAA", collectorNumber: "10" });
  const s1n9 = item({ cardSetName: "Alfa", cardSetCode: "AAA", collectorNumber: "9" });
  const holo = item({ cardSetName: "Alfa", cardSetCode: "AAA", collectorNumber: "9", variantLabel: "Holo" });
  const v = uuid(9_000);
  const en = item({ cardVariantId: v, cardSetName: "Alfa", cardSetCode: "AAA", collectorNumber: "8", languageCode: "en" });
  const pt = item({ cardVariantId: v, cardSetName: "Alfa", cardSetCode: "AAA", collectorNumber: "8", languageCode: "pt-BR", languageName: "Português" });
  const { report } = top([s2, s1n10, s1n9, holo, pt, en], new Map([p(s2), p(s1n10), p(s1n9), p(holo), [v, price(50)]]));
  assert.deepEqual(report.lines.map((l) => `${l.cardSetCode}-${l.collectorNumber}-${l.variantLabel}-${l.languageCode}`), [
    "AAA-8-Normal-en",
    "AAA-8-Normal-pt-BR",
    "AAA-9-Holo-en",
    "AAA-9-Normal-en",
    "AAA-10-Normal-en",
    "BBB-1-Normal-en",
  ]);
});

test("mesma variante em dois idiomas: duas posições com a mesma referência; idioma ≠ inglês = referência internacional", () => {
  const v = uuid(9_100);
  const en = item({ cardVariantId: v, languageCode: "en", copies: 2 });
  const pt = item({ cardVariantId: v, languageCode: "pt-BR", languageName: "Português" });
  const { report } = top([en, pt], new Map([[v, price(80)]]));
  assert.equal(report.lines.length, 2);
  assert.deepEqual(report.lines.map((l) => l.unitBrl), [80, 80]);
  assert.deepEqual(report.lines.map((l) => l.international), [false, true]);
  assert.equal(report.topCopies, 3);
  assert.equal(report.topCopiesBrl, 240);
  assert.match(topIdentityText(report.lines[1]!), /Alfa \(AAA\) · \d+\/200 · Normal · Português/);
});

test("preço geral da carta entra sinalizado; desatualizada (> 14 dias) entra com a data; sem data → 'data não disponível'", () => {
  const fb = item();
  const old = item();
  const fresh = item();
  const { report } = top(
    [fb, old, fresh],
    new Map([
      [fb.cardVariantId, price(30, { basis: "CARD_FALLBACK", observedAt: null })],
      [old.cardVariantId, price(20, { observedAt: "2026-10-01T00:00:00Z" })],
      [fresh.cardVariantId, price(10)],
    ]),
  );
  const [l1, l2, l3] = report.lines;
  assert.deepEqual(topPriceFlags(l1!), ["Preço geral da carta"]);
  assert.equal(topObservedText(l1!), "data não disponível");
  assert.deepEqual(topPriceFlags(l2!), ["Desatualizada"]);
  assert.equal(topObservedText(l2!), "obs. 30/09/2026"); // America/Sao_Paulo
  assert.deepEqual(topPriceFlags(l3!), []);
  assert.equal(l3!.generalCardPrice, false); // VARIANT nunca vira "preço geral"
});

test("sem cotação nunca vale zero e fica fora; menos de 10 cotados → todos; nenhum cotado → vazio", () => {
  const priced = item();
  const none = item();
  const { report } = top([priced, none], new Map([[priced.cardVariantId, price(5)]]));
  assert.equal(report.lines.length, 1);
  assert.equal(report.pricedGroups, 1);
  assert.equal(report.totalGroups, 2);
  assert.equal(topCoverageText(report), "1 de 2 itens com cotação");
  assert.ok(report.lines.every((l) => l.unitBrl > 0));
  const empty = top([item()], new Map()).report;
  assert.equal(empty.lines.length, 0);
  assert.equal(empty.topCopiesBrl, null);
  assert.equal(empty.topShare, null);
  assert.equal(empty.complete, true);
});

test("exatamente 10 posições; empatados com a 10ª ficam fora pelo desempate e são informados", () => {
  const items = Array.from({ length: 14 }, (_, i) => item({ collectorNumber: String(i + 1) }));
  const prices = new Map(items.map((it, i) => [it.cardVariantId, price(i < 8 ? 100 - i : 50)] as const)); // 8 distintos + 6 empatados em R$ 50
  const { report } = top(items, prices);
  assert.equal(report.lines.length, TOP_CARDS_LIMIT);
  assert.deepEqual(report.lines.slice(8).map((l) => l.collectorNumber), ["9", "10"]); // desempate pelo número
  assert.equal(report.tiedBeyond, 4);
  assert.match(topTiedText(report) ?? "", /^e mais 4 itens com a mesma referência da 10ª posição/);
  assert.equal(topTiedText({ tiedBeyond: 0 }), null);
});

test("concentração: valor das cópias do Top 10 ÷ a MESMA base do Valor estimado total (exemplares cotados)", () => {
  const items = Array.from({ length: 12 }, (_, i) => item({ copies: i + 1 }));
  const prices = new Map(items.map((it, i) => [it.cardVariantId, price(10 + i)] as const));
  const unpriced = item({ copies: 7 });
  const { inventory, report } = top([...items, unpriced], prices);
  const value = buildAcervoValueReport(inventory);
  assert.equal(report.estimatedTotalBrl, value.totalBrl); // mesma base
  const expected = report.lines.reduce((n, l) => n + Math.round(l.unitBrl * 100) * l.copies, 0);
  assert.equal(Math.round((report.topCopiesBrl ?? 0) * 100), expected);
  assert.equal(report.topShare, expected / Math.round((value.totalBrl ?? 0) * 100));
  assert.ok((report.topShare ?? 0) < 1);
  // Grupos ≠ exemplares.
  assert.equal(report.totalGroups, 13);
  assert.equal(report.totalCopies, 78 + 7);
  assert.equal(report.pricedCopies, 78);
});

test("falha parcial de preço: ranking provisório com os dados válidos, incompleto (impressão bloqueada)", () => {
  const ok = item();
  const fail = item();
  const { report } = top([ok, fail], new Map([[ok.cardVariantId, price(9)]]), new Set([fail.cardVariantId]));
  assert.equal(report.lines.length, 1);
  assert.equal(report.unavailableGroups, 1);
  assert.equal(report.incompleteReason, "prices_unavailable");
  assert.equal(report.complete, false);
  assert.equal(topCoverageText(report), "1 de 2 itens com cotação · 1 indisponível agora");
  for (const reason of ["too_large", "mismatch", "prices_unavailable"] as const) assert.match(topCardsIncompleteText(reason) ?? "", /impressão fica indisponível/);
  assert.equal(topCardsIncompleteText(null), null);
  // Teto do acervo: incompleto.
  assert.equal(top([ok], new Map([[ok.cardVariantId, price(9)]]), new Set(), false).report.incompleteReason, "too_large");
});

type Call = { fn: string; args: Record<string, unknown> };
function fakeClient(groups: number, calls: Call[], options: { failPricesFor?: string; failItems?: boolean } = {}) {
  let inFlight = 0;
  let peak = 0;
  const rows = Array.from({ length: groups }, (_, i) => ({
    card_variant_id: uuid(1 + (i % 120)),
    language_code: i < 120 ? "en" : "pt-BR",
    language_name: i < 120 ? "Inglês" : "Português",
    card_name: `Carta ${i}`,
    collector_number: String(i + 1),
    collector_total: 999,
    card_set_code: "SV1",
    card_set_name: "Escarlate e Violeta",
    is_default_variant: true,
    variant_label: null,
    copies_count: 2,
    image_path: `cards/${i}.webp`,
    total_count: groups,
  }));
  return {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      if (fn === "get_my_inventory_summary") {
        return { data: [{ total_copies: groups * 2, distinct_items: groups, distinct_sets: groups ? 1 : 0, duplicate_copies: groups }], error: null };
      }
      if (fn === "get_my_inventory_items") {
        if (options.failItems) return { data: null, error: { code: "XX000" } };
        const offset = Number(args.p_offset);
        return { data: rows.slice(offset, offset + Number(args.p_limit)), error: null };
      }
      if (fn === "get_card_variants_pricing_summary") {
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 3));
        inFlight -= 1;
        const ids = args.p_card_variant_ids as string[];
        if (options.failPricesFor && ids.includes(options.failPricesFor)) return { data: null, error: { code: "42501" } };
        return {
          data: ids.map((id) => ({ card_variant_id: id, has_pricing: true, brl_amount: Number.parseInt(id.slice(-4), 16), price_basis: "VARIANT", price_origin: "AUTOMATIC", fx_status: "CONVERTED", observed_at: "2026-11-01T00:00:00Z" })),
          error: null,
        };
      }
      return { data: null, error: { code: "PGRST202" } };
    },
    peak: () => peak,
  };
}

test("leitura: acervo inteiro (5160 + 5159 SET_NUMBER), preços por variante distinta (máx. 2), miniatura, sem identificar o titular", async () => {
  const calls: Call[] = [];
  const client = fakeClient(150, calls);
  const load = await getTopCardsReport(client as never, new Date(NOW), (path) => `https://img/${path}`);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  const r = load.data.report;
  assert.equal(r.complete, true);
  assert.equal(r.totalGroups, 150);
  assert.equal(r.lines.length, 10);
  assert.equal(r.lines[0]?.unitBrl, 120); // variante 120 (maior referência), só em inglês
  assert.equal(r.lines[0]?.imageUrl, "https://img/cards/119.webp");
  assert.equal(r.lines[0]?.languageName, "Inglês");
  const priceCalls = calls.filter((c) => c.fn === "get_card_variants_pricing_summary");
  assert.deepEqual(priceCalls.map((c) => (c.args.p_card_variant_ids as string[]).length), [100, 20]); // 120 variantes distintas
  assert.ok(client.peak() <= 2);
  for (const page of calls.filter((c) => c.fn === "get_my_inventory_items")) {
    assert.equal(page.args.p_sort, "SET_NUMBER");
    assert.equal(page.args.p_collection_id, null); // independe de coleção
  }
  assert.ok(calls.every((c) => Object.keys(c.args).every((key) => !/user|owner|profile/i.test(key))));
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), ["get_card_variants_pricing_summary", "get_my_inventory_items", "get_my_inventory_summary"]); // sem escrita
});

test("leitura: falha do acervo → erro; falha de preço → provisório; acervo acima do teto → incompleto", async () => {
  assert.equal((await getTopCardsReport(fakeClient(10, [], { failItems: true }) as never)).status, "error");
  const partial = await getTopCardsReport(fakeClient(150, [], { failPricesFor: uuid(101) }) as never, new Date(NOW));
  assert.equal(partial.status, "ready");
  if (partial.status === "ready") {
    assert.equal(partial.data.report.incompleteReason, "prices_unavailable");
    assert.equal(partial.data.report.unavailableGroups, 20); // variantes 101..120, só em inglês (linhas 100..119)
    assert.equal(partial.data.report.lines[0]?.unitBrl, 100); // dados válidos preservados
  }
  const big = await getTopCardsReport(fakeClient(5_010, []) as never);
  assert.equal(big.status, "ready");
  if (big.status === "ready") assert.equal(big.data.report.incompleteReason, "too_large");
});

test("integração: 6º relatório do Meu acervo, sobreposição comum, folha institucional e sem SQL nova", () => {
  const items = acervoReportMenuItems({ totalCopies: 3 });
  assert.equal(items[5]?.id, "top");
  assert.equal(items[5]?.icon, "top");
  assert.ok(acervoReportMenuItems({ totalCopies: 0 })[5]?.disabledReason);
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /if \(report === "top"\) \{\s*return readTopCardsReport\(\)/);
  assert.match(overlay, /incomplete: topCardsIncompleteText\(r\.data\.report\.incompleteReason\)/);
  assert.match(read("../../app/colecoes/acervo/relatorios/actions.ts"), /export async function readTopCardsReport\(\)[\s\S]*if \(!user\) return \{ status: "error" \}/);
  const sheet = read("../../components/reports/top-cards-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  for (const label of ["Cartas no Top 10", "Maior valor unitário", "Valor do Top 10", "Cobertura de preços"]) assert.match(sheet, new RegExp(`label="${label}"`), label);
  for (const label of ["Pos.", "Carta", "Referência NM", "Exemplares", "Valor das cópias"]) assert.match(sheet, new RegExp(`>\\s*${label.replace(".", "\\.")}\\s*<`), label);
  assert.match(sheet, /h-\[56px\] w-\[40px\]/);
  assert.match(sheet, /width=\{40\} height=\{56\} loading="eager"/);
  assert.match(sheet, /breakInside: "avoid"/);
  assert.doesNotMatch(sheet, /print:hidden/); // miniaturas e notas também na impressão
  for (const source of [read("./top-cards.ts"), read("./top-cards-queries.ts")]) assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(|\.upsert\(|\.from\("/);
  // Mesma regra de referência dos relatórios 02/03.
  assert.match(read("./acervo-set-inventory-queries.ts"), /const input = inventoryPriceInput\(price\);/);
  assert.match(read("./top-cards-queries.ts"), /const input = inventoryPriceInput\(price\);/);
});
