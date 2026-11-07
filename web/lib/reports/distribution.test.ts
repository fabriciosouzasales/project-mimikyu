// V1-14 R1-H — "Distribuição por Set, raridade e idioma" (8º relatório do Meu acervo): totais e
// reconciliação por dimensão, exemplares × itens, distribuição física e financeira, ordem, nomes de
// raridade repetidos, raridade desconhecida/ausente, sem cotação × indisponível, baixa cobertura,
// falha parcial e impressão bloqueada, estado vazio, teto de 5.000 grupos, leitura (paralelo,
// sem 5354, sem identificar o titular), leitura única simultânea e integração.
// Executar: node --experimental-strip-types --test lib/reports/distribution.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { acervoReportMenuItems } from "./acervo-reports.ts";
import { type SetInventoryItemInput, type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { buildAcervoValueReport } from "./acervo-value.ts";
import { getDistributionReport, parseRarityCatalog, readRarityCatalog } from "./distribution-queries.ts";
import {
  type RarityCatalogInput,
  buildDistributionReport,
  distributionCoverageText,
  distributionIncompleteText,
  distributionSetSummaryText,
  distributionShowsSetComposition,
  distributionShareText,
  distributionValueText,
} from "./distribution.ts";

console.error = () => {};
console.warn = () => {};
console.info = () => {};

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const brl = (n: number) => `R$ ${n.toFixed(2).replace(".", ",")}`;

const CATALOG: RarityCatalogInput = {
  status: "ok",
  entries: [
    { code: "COMMON", name: "Comum", symbolCode: "BLACK_CIRCLE", displayOrder: 1 },
    { code: "UNCOMMON", name: "Incomum", symbolCode: "BLACK_DIAMOND", displayOrder: 2 },
    { code: "RARE", name: "Rara", symbolCode: "BLACK_STAR", displayOrder: 3 },
    { code: "ULTRA_RARE", name: "Rara Ultra", symbolCode: "SILVER_DOUBLE_STAR", displayOrder: 6 },
    { code: "NONE", name: "Comum", symbolCode: "BLACK_CIRCLE", displayOrder: 21 },
  ],
};

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
    variantLabel: null,
    isDefaultVariant: true,
    copies: 1,
    rarityCode: "COMMON",
    ...over,
  };
}
const price = (b: number): SetInventoryPriceInput => ({ brl: b, basis: "VARIANT", observedAt: "2026-11-03T00:00:00Z" });

function build(
  items: SetInventoryItemInput[],
  prices = new Map<string, SetInventoryPriceInput>(),
  over: { unavailable?: Set<string>; rarities?: RarityCatalogInput; totalCopies?: number; distinctItems?: number; itemsComplete?: boolean } = {},
) {
  const inventory = buildSetInventoryReport({
    summary: {
      totalCopies: over.totalCopies ?? items.reduce((n, i) => n + i.copies, 0),
      distinctItems: over.distinctItems ?? items.length,
      distinctSets: new Set(items.map((i) => i.cardSetCode)).size,
      duplicateCopies: items.reduce((n, i) => n + i.copies - 1, 0),
    },
    items,
    prices,
    itemsComplete: over.itemsComplete ?? true,
  });
  return { inventory, report: buildDistributionReport({ inventory, unavailable: over.unavailable ?? new Set(), rarities: over.rarities ?? CATALOG }) };
}

test("totais e reconciliação: cada dimensão soma exemplares e itens do resumo e o valor do Valor estimado total", () => {
  const items = [
    item({ cardSetCode: "S1", cardSetName: "S1", copies: 3, rarityCode: "RARE" }),
    item({ cardSetCode: "S1", cardSetName: "S1", copies: 1, languageCode: "pt-BR", languageName: "Português" }),
    item({ cardSetCode: "S2", cardSetName: "S2", copies: 2, rarityCode: "ULTRA_RARE", languageCode: "ja", languageName: "Japonês" }),
  ];
  const prices = new Map([[items[0]!.cardVariantId, price(10.1)], [items[2]!.cardVariantId, price(0.33)]]);
  const { inventory, report } = build(items, prices);
  assert.equal(report.complete, true);
  for (const dim of [report.sets, report.rarities!, report.languages]) {
    assert.equal(dim.copies, 6);
    assert.equal(dim.items, 3);
    assert.equal(dim.valueBrl, 30.96); // 3 × 10,10 + 2 × 0,33 — centavos exatos
    assert.equal(dim.balanced, true);
  }
  assert.equal(report.totalBrl, buildAcervoValueReport(inventory).totalBrl);
  // Resumo divergente (acervo mudou durante a leitura) → incompleto.
  assert.equal(build(items, prices, { totalCopies: 7 }).report.incompleteReason, "mismatch");
  assert.equal(build(items, prices, { distinctItems: 4 }).report.incompleteReason, "mismatch");
  assert.match(distributionIncompleteText("mismatch") ?? "", /impressão fica indisponível/);
});

test("exemplares × itens: uma carta com várias cópias é 1 item; barras e % pela participação física", () => {
  const items = [item({ copies: 9, cardSetCode: "BIG", cardSetName: "Grande" }), item({ copies: 1, cardSetCode: "SMALL", cardSetName: "Pequeno" }), item({ copies: 1, cardSetCode: "SMALL", cardSetName: "Pequeno" })];
  const { report } = build(items);
  const [big, small] = report.sets.bands;
  assert.deepEqual([big?.key, big?.copies, big?.items], ["BIG", 9, 1]);
  assert.deepEqual([small?.key, small?.copies, small?.items], ["SMALL", 2, 2]);
  assert.equal(distributionShareText(big!.copiesShare), "81,8%"); // 9/11 truncado
  assert.equal(distributionShareText(small!.copiesShare), "18,1%");
  assert.equal(big?.top, true);
  assert.equal(small?.top, false);
  assert.equal(distributionShareText(1), "100,0%");
  assert.equal(distributionShareText(0.0004), "<0,1%");
  assert.equal(distributionShareText(null), "—");
});

test("distribuição financeira: valor só dos cotados, % do valor cotado; sem cotação nunca zero; faixa sem cotação → \"Sem cotação\" e \"—\"", () => {
  const a = item({ cardSetCode: "S1", cardSetName: "S1", copies: 2 });
  const b = item({ cardSetCode: "S2", cardSetName: "S2", copies: 5 });
  const c = item({ cardSetCode: "S3", cardSetName: "S3", copies: 1 });
  const { report } = build([a, b, c], new Map([[a.cardVariantId, price(30)], [c.cardVariantId, price(20)]]));
  const byKey = Object.fromEntries(report.sets.bands.map((band) => [band.key, band]));
  assert.equal(byKey.S1?.valueBrl, 60);
  assert.equal(distributionShareText(byKey.S1!.valueShare), "75,0%"); // 60 / 80
  assert.equal(byKey.S2?.valueBrl, null);
  assert.equal(distributionValueText(byKey.S2!, brl), "Sem cotação");
  assert.equal(distributionShareText(byKey.S2!.valueShare), "—");
  assert.equal(report.complete, true); // sem cotação não bloqueia
  // Nenhum cotado: visão física preservada; valor "Sem cotação".
  const none = build([item({ copies: 2 }), item()]).report;
  assert.equal(none.totalBrl, null);
  assert.equal(none.sets.valueBrl, null);
  assert.equal(none.sets.copies, 3);
  assert.equal(none.complete, true);
});

test("ordem: Sets por exemplares ↓, empate pelo lançamento mais recente e código; raridade na ordem do catálogo; idioma por exemplares ↓ e nome", () => {
  // As linhas chegam na ordem canônica da 5159 (Set mais recente primeiro: NEW, MID, OLD).
  const items = [
    item({ cardSetCode: "NEW", cardSetName: "Novo", copies: 2, rarityCode: "RARE", languageCode: "pt-BR", languageName: "Português" }),
    item({ cardSetCode: "MID", cardSetName: "Meio", copies: 5, rarityCode: "UNCOMMON", languageCode: "ja", languageName: "Japonês" }),
    item({ cardSetCode: "OLD", cardSetName: "Antigo", copies: 2, rarityCode: null, languageCode: "en", languageName: "Inglês" }),
    item({ cardSetCode: "OLD", cardSetName: "Antigo", copies: 1, rarityCode: "ULTRA_RARE", languageCode: "ja", languageName: "Japonês" }),
  ];
  const { report } = build(items);
  assert.deepEqual(report.sets.bands.map((b) => b.key), ["MID", "OLD", "NEW"]); // MID 5; OLD 3; NEW 2
  const tie = build([item({ cardSetCode: "NEW", cardSetName: "Novo", copies: 2 }), item({ cardSetCode: "OLD", cardSetName: "Antigo", copies: 2 })]).report;
  assert.deepEqual(tie.sets.bands.map((b) => b.key), ["NEW", "OLD"]); // empate: mais recente primeiro
  assert.deepEqual(report.rarities!.bands.map((b) => b.label), ["Incomum", "Rara", "Rara Ultra", "Sem raridade definida"]); // display_order; sem raridade por último
  assert.deepEqual(report.languages.bands.map((b) => [b.label, b.copies]), [
    ["Japonês", 6],
    ["Inglês", 2],
    ["Português", 2],
  ]); // empate Inglês/Português por nome
  assert.equal(report.rarities!.bands.find((b) => b.top)?.label, "Incomum"); // destaque = maior concentração, não a 1ª da ordem
});

test("raridade: agrupada por code; nomes repetidos nunca se mesclam e ganham o código; sem ambiguidade, só o nome", () => {
  const both = build([item({ copies: 2, rarityCode: "COMMON" }), item({ copies: 1, rarityCode: "NONE" }), item({ rarityCode: "RARE" })]).report;
  const labels = both.rarities!.bands.map((b) => [b.label, b.detail, b.copies]);
  assert.deepEqual(labels, [
    ["Comum", "COMMON", 2],
    ["Rara", null, 1],
    ["Comum", "NONE", 1],
  ]);
  const single = build([item({ rarityCode: "COMMON" }), item({ rarityCode: "RARE" })]).report;
  assert.deepEqual(single.rarities!.bands.map((b) => [b.label, b.detail]), [
    ["Comum", null],
    ["Rara", null],
  ]);
  assert.equal(both.rarityCount, 3);
});

test("raridade: código fora do catálogo → inconsistência; catálogo indisponível → provisório; ausência → \"Sem raridade definida\"", () => {
  const unknown = build([item({ rarityCode: "MYSTERY_RARE", copies: 2 }), item()]).report;
  assert.equal(unknown.incompleteReason, "rarity_unknown");
  assert.equal(unknown.complete, false);
  const band = unknown.rarities!.bands.find((b) => b.kind === "rarity-unknown");
  assert.equal(band?.label, "Raridade não reconhecida no catálogo");
  assert.ok(!unknown.rarities!.bands.some((b) => b.label.includes("MYSTERY"))); // código nunca exposto
  const off = build([item()], new Map(), { rarities: { status: "unavailable" } }).report;
  assert.equal(off.incompleteReason, "rarity_unavailable");
  assert.equal(off.rarities, null);
  assert.equal(off.sets.copies, 1); // demais seções preservadas
  const missing = build([item({ rarityCode: null }), item({ rarityCode: undefined })]).report;
  assert.equal(missing.complete, true);
  assert.deepEqual(missing.rarities!.bands.map((b) => [b.kind, b.label, b.copies]), [["rarity-none", "Sem raridade definida", 2]]);
  for (const r of ["rarity_unknown", "rarity_unavailable", "prices_unavailable", "too_large"] as const) assert.match(distributionIncompleteText(r) ?? "", /impressão fica indisponível/);
  assert.equal(distributionIncompleteText(null), null);
});

test("preço inexistente × indisponível; baixa cobertura (< 50%); falha parcial → provisório com informação válida", () => {
  const priced = item({ cardSetCode: "S1", cardSetName: "S1", copies: 1 });
  const none = item({ cardSetCode: "S1", cardSetName: "S1", copies: 2 });
  const fail = item({ cardSetCode: "S2", cardSetName: "S2", copies: 3 });
  const { report } = build([priced, none, fail], new Map([[priced.cardVariantId, price(4)]]), { unavailable: new Set([fail.cardVariantId]) });
  const s1 = report.sets.bands.find((b) => b.key === "S1")!;
  const s2 = report.sets.bands.find((b) => b.key === "S2")!;
  assert.equal(distributionValueText(s1, brl), "R$ 4,00");
  assert.equal(distributionCoverageText(s1), "33%");
  assert.equal(s1.lowCoverage, true); // 1 de 3
  assert.equal(distributionValueText(s2, brl), "Indisponível"); // falha de leitura ≠ sem cotação
  assert.equal(s2.unavailableCopies, 3);
  assert.equal(report.incompleteReason, "prices_unavailable");
  assert.equal(report.unavailableCopies, 3);
  assert.equal(report.sets.copies, 6); // informação física preservada
  const half = build([item({ copies: 1 }), item({ copies: 1 })], new Map([[uuid(seq - 1), price(1)]])).report;
  assert.equal(half.sets.bands[0]?.lowCoverage, false); // exatamente 50% não é baixa
  assert.equal(distributionValueText({ valueBrl: 4, unavailableCopies: 1 }, brl), "R$ 4,00 (parcial)");
});

test("estado vazio e teto de 5.000 grupos", () => {
  const empty = build([]).report;
  assert.equal(empty.totalCopies, 0);
  assert.equal(empty.sets.bands.length, 0);
  assert.equal(empty.complete, true);
  assert.ok(acervoReportMenuItems({ totalCopies: 0 })[7]?.disabledReason); // menu desabilitado sem exemplares
  const big = build([item({ copies: 2 })], new Map(), { itemsComplete: false }).report;
  assert.equal(big.incompleteReason, "too_large");
});

test("resumo da composição por Card Set: Top 10 + Demais", () => {
  const items = Array.from({ length: 13 }, (_, i) => item({ cardSetCode: `S${String(i).padStart(2, "0")}`, cardSetName: `Set ${i}`, copies: 20 - i }));
  const { report } = build(items);
  assert.equal(report.setSummary.top.length, 10);
  assert.equal(report.setSummary.othersCount, 3);
  assert.equal(report.setSummary.othersCopies, 10 + 9 + 8);
  assert.equal(report.sets.bands.length, 13); // tabela completa
  assert.match(distributionSetSummaryText(report), /^Os 10 maiores Sets reúnem \d+,\d% dos exemplares; demais 3 Sets, \d+,\d%\.$/);
});

// ---------------------------------------------------------------------------
// Leitura
// ---------------------------------------------------------------------------

type Call = { fn: string; args: Record<string, unknown>; at: number };
function fakeClient(groups: number, calls: Call[], options: { failRarities?: boolean; failPricesFor?: string; unknownRarity?: boolean } = {}) {
  let t = 0;
  let inFlight = 0;
  let peak = 0;
  const rows = Array.from({ length: groups }, (_, i) => ({
    card_variant_id: uuid(1 + i),
    language_code: i % 4 === 0 ? "pt-BR" : "en",
    language_name: i % 4 === 0 ? "Português" : "Inglês",
    card_name: `Carta ${i}`,
    collector_number: String(i + 1),
    collector_total: 999,
    card_set_code: i % 2 === 0 ? "SV1" : "SV2",
    card_set_name: i % 2 === 0 ? "Escarlate e Violeta" : "Evoluções em Paldea",
    is_default_variant: true,
    variant_label: null,
    copies_count: i % 3 === 0 ? 2 : 1,
    image_path: null,
    total_count: groups,
    rarity_code: options.unknownRarity && i === 0 ? "MYSTERY" : i % 5 === 0 ? null : i % 2 === 0 ? "COMMON" : "RARE",
  }));
  const copies = rows.reduce((n, r) => n + r.copies_count, 0);
  return {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args, at: t++ });
      if (fn === "get_my_inventory_summary") return { data: [{ total_copies: copies, distinct_items: groups, distinct_sets: 2, duplicate_copies: copies - groups }], error: null };
      if (fn === "get_my_inventory_items") {
        await new Promise((resolve) => setTimeout(resolve, 1));
        const offset = Number(args.p_offset);
        return { data: rows.slice(offset, offset + Number(args.p_limit)), error: null };
      }
      if (fn === "get_rarity_catalog") {
        if (options.failRarities) return { data: null, error: { code: "57014" } };
        return {
          data: [
            { code: "COMMON", name: "Comum", symbol_code: "BLACK_CIRCLE", display_order: 1 },
            { code: "RARE", name: "Rara", symbol_code: "BLACK_STAR", display_order: 3 },
          ],
          error: null,
        };
      }
      if (fn === "get_card_variants_pricing_summary") {
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 2));
        inFlight -= 1;
        const ids = args.p_card_variant_ids as string[];
        if (options.failPricesFor && ids.includes(options.failPricesFor)) return { data: null, error: { code: "42501" } };
        return { data: ids.map((id) => ({ card_variant_id: id, has_pricing: true, brl_amount: 2, price_basis: "VARIANT", price_origin: "AUTOMATIC", fx_status: "CONFIRMED", observed_at: "2026-11-01T00:00:00Z" })), error: null };
      }
      return { data: null, error: { code: "PGRST202" } };
    },
    peak: () => peak,
  };
}

test("leitura: 5160 + 5159 em paralelo com a 5355 (uma chamada), 3989 com concorrência ≤ 2; sem 5354, sem identificar o titular", async () => {
  const calls: Call[] = [];
  const client = fakeClient(400, calls);
  const load = await getDistributionReport(client as never);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  const r = load.data.report;
  assert.equal(r.complete, true);
  assert.equal(r.sets.copies, r.totalCopies);
  assert.equal(r.totalBrl, r.totalCopies * 2);
  assert.equal(calls.filter((c) => c.fn === "get_rarity_catalog").length, 1);
  const rarityAt = calls.find((c) => c.fn === "get_rarity_catalog")!.at;
  const firstPrice = calls.find((c) => c.fn === "get_card_variants_pricing_summary")!.at;
  assert.ok(rarityAt < 3); // disparada junto com 5160 e a 1ª página da 5159
  assert.ok(rarityAt < firstPrice);
  assert.ok(client.peak() <= 2);
  assert.ok(!calls.some((c) => c.fn === "get_my_inventory_group_locations"));
  assert.ok(calls.every((c) => Object.keys(c.args).every((key) => !/user|owner|profile/i.test(key))));
  assert.deepEqual(r.rarities!.bands.map((b) => b.label), ["Comum", "Rara", "Sem raridade definida"]);
  // Falhas: 5355 → provisório; preço → provisório; raridade desconhecida → inconsistência; teto.
  const off = await getDistributionReport(fakeClient(30, [], { failRarities: true }) as never);
  assert.equal(off.status === "ready" && off.data.report.incompleteReason, "rarity_unavailable");
  const partial = await getDistributionReport(fakeClient(300, [], { failPricesFor: uuid(250) }) as never);
  assert.equal(partial.status === "ready" && partial.data.report.incompleteReason, "prices_unavailable");
  const unknown = await getDistributionReport(fakeClient(30, [], { unknownRarity: true }) as never);
  assert.equal(unknown.status === "ready" && unknown.data.report.incompleteReason, "rarity_unknown");
  const big = await getDistributionReport(fakeClient(5_010, []) as never);
  assert.equal(big.status === "ready" && big.data.report.incompleteReason, "too_large");
});

test("5355: contrato da resposta (code inválido ou repetido, nome em branco, ordem inválida → indisponível)", async () => {
  assert.equal(parseRarityCatalog([{ code: "COMMON", name: "Comum", symbol_code: "X", display_order: 1 }])?.[0]?.displayOrder, 1);
  assert.equal(parseRarityCatalog(null), null);
  assert.equal(parseRarityCatalog([{ code: "common", name: "Comum", symbol_code: "X", display_order: 1 }]), null);
  assert.equal(parseRarityCatalog([{ code: "A", name: " ", symbol_code: "X", display_order: 1 }]), null);
  assert.equal(parseRarityCatalog([{ code: "A", name: "A", symbol_code: "X", display_order: 0 }]), null);
  const row = { code: "A", name: "A", symbol_code: "X", display_order: 1 };
  assert.equal(parseRarityCatalog([row, row]), null);
  assert.deepEqual(await readRarityCatalog({ rpc: async () => ({ data: [row, row], error: null }) }), { status: "unavailable" });
});

test("integração: 8º relatório; leitura única simultânea; folha institucional; 1 em preparação", () => {
  const items = acervoReportMenuItems({ totalCopies: 3 });
  assert.equal(items[7]?.id, "distribution");
  assert.equal(items[7]?.icon, "distribution");
  assert.equal(items[8]?.label, "1 relatório em preparação");
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /const readDistributionOnce = shareInFlight\(\(\) => readDistributionReport\(\)\);/);
  assert.match(overlay, /if \(report === "distribution"\) \{\s*return readDistributionOnce\(\)\.then/);
  assert.match(overlay, /incomplete: distributionIncompleteText\(r\.data\.report\.incompleteReason\)/);
  const block = overlay.slice(overlay.indexOf('if (report === "distribution")'), overlay.indexOf('if (report === "top")'));
  assert.doesNotMatch(block, /preparePrint/); // sem miniaturas: imprime direto
  const menu = read("../../components/reports/report-menu.tsx");
  assert.match(menu, /distribution: PieChart,/);
  const sheet = read("../../components/reports/distribution-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  for (const label of ["Exemplares", "Diversidade", "Valor estimado", "Maior concentração"]) assert.match(sheet, new RegExp(`label="${label}"`), label);
  // Títulos exatos: FAIXA | EXEMPLARES | % | ITENS | VALOR ESTIMADO | % | COBERTURA (os dois % definidos na nota).
  const heads = [...sheet.matchAll(/<DataTableHeadCell[^>]*>\s*([^<]+?)\s*<\/DataTableHeadCell>/g)].map((m) => m[1]);
  assert.deepEqual(heads, ["Faixa", "Exemplares", "%", "Itens", "Valor estimado", "%", "Cobertura"]);
  assert.doesNotMatch(sheet, />\s*% dos exemplares\s*<|>\s*% do valor cotado\s*</);
  assert.match(sheet, /a primeira \(ao lado de Exemplares\) é a participação nos exemplares físicos/);
  assert.match(sheet, /a segunda \(ao lado de Valor\s+estimado\) é a participação no valor total cotado/);
  // Cabeçalho institucional completo em todas as páginas (thead da tabela externa); KPIs só na 1ª (no corpo).
  const outerHead = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.match(outerHead, /\{cabecalho\}/);
  assert.doesNotMatch(outerHead, /Indicator/);
  assert.ok(sheet.indexOf("</thead>") < sheet.indexOf('aria-label="Indicadores da distribuição"'));
  assert.match(sheet, /<tr style=\{\{ breakInside: "auto", pageBreakInside: "auto" \}\}>/); // a linha externa continua na página seguinte
  assert.doesNotMatch(sheet, /position: ?"?fixed|print:fixed|hidden print:table-row/); // sem posicionamento fixo; identificação curta substituída
  for (const title of ["Por Card Set", "Por raridade", "Por idioma"]) assert.match(sheet, new RegExp(`title="${title}"`), title);
  assert.ok(sheet.indexOf('title="Por Card Set"') < sheet.indexOf('title="Por raridade"') && sheet.indexOf('title="Por raridade"') < sheet.indexOf('title="Por idioma"'));
  assert.match(sheet, /Baixa cobertura de preços/);
  assert.doesNotMatch(sheet, /<img|echarts|MmkyuChart/); // sem miniaturas, sem biblioteca de gráfico
  assert.match(sheet, /breakInside: "avoid"/);
  for (const source of [read("./distribution.ts"), read("./distribution-queries.ts")]) assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(|\.upsert\(|\.from\("/);
  const actions = read("../../app/colecoes/acervo/relatorios/actions.ts");
  assert.match(actions, /export async function readDistributionReport\(\)/);
});

test("resumo Top 10 + Demais só com mais de 10 Card Sets (10 → oculto; 11 → visível); tabela completa nos dois", () => {
  const sets = (n: number) => Array.from({ length: n }, (_, i) => item({ cardSetCode: `T${String(i).padStart(2, "0")}`, cardSetName: `Set ${i}`, copies: 30 - i }));
  const ten = build(sets(10)).report;
  assert.equal(distributionShowsSetComposition(ten), false);
  assert.equal(ten.sets.bands.length, 10);
  assert.equal(ten.setSummary.othersCount, 0);
  const eleven = build(sets(11)).report;
  assert.equal(distributionShowsSetComposition(eleven), true);
  assert.equal(eleven.sets.bands.length, 11);
  assert.equal(eleven.setSummary.top.length, 10);
  assert.equal(eleven.setSummary.othersCount, 1);
  assert.match(distributionSetSummaryText(eleven), /; o outro Set, \d+,\d%\.$/);
  // Cálculos e ordem não mudam com a regra de exibição.
  assert.deepEqual(eleven.sets.bands.slice(0, 10).map((b) => [b.key, b.copies]), ten.sets.bands.map((b) => [b.key, b.copies]));
  assert.equal(distributionShowsSetComposition(build([item()]).report), false);
  const sheet = read("../../components/reports/distribution-report.tsx");
  assert.match(sheet, /if \(!distributionShowsSetComposition\(report\)\) return null;/);
  assert.match(sheet, /<SetComposition report=\{report\} \/>/);
  assert.match(sheet, /title="Por Card Set"/); // tabela completa sempre
});
