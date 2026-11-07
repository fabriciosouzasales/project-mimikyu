// V1-14 R1-G — "Cartas repetidas" (7º relatório do Meu acervo): agrupamento variante + idioma,
// adicionais, conciliação com a 5160, ordem, subtotais, valor e cobertura das adicionais, preço
// ausente × indisponível, sinais, estados, completude, localização física (5354), leitura em
// paralelo e sem N+1, leitura única simultânea, fila de miniaturas e integração (impressão).
// Executar: node --experimental-strip-types --test lib/reports/duplicates.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { acervoReportMenuItems } from "./acervo-reports.ts";
import { type SetInventoryItemInput, type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { buildAcervoValueReport } from "./acervo-value.ts";
import { LOCATIONS_CHUNK, getDuplicatesReport, parseGroupLocations, readGroupLocations, timedRpc } from "./duplicates-queries.ts";
import { shareInFlight } from "./in-flight.ts";
import { PRINT_IMAGE_CONCURRENCY, prepareImageQueue } from "./print-image-queue.ts";
import {
  type DuplicateLocationGroup,
  type DuplicateLocationsInput,
  buildDuplicatesReport,
  duplicateFlags,
  duplicateGroupKey,
  duplicateAdditionalLocations,
  duplicateAdditionalLocationsText,
  duplicateReferenceLocation,
  duplicateVariantText,
  duplicatesCoverageNote,
  duplicatesIncompleteText,
  duplicatesValueText,
} from "./duplicates.ts";

console.error = () => {};
console.warn = () => {};
console.info = () => {};

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const NOW = Date.parse("2026-11-06T12:00:00Z");
const brl = (n: number) => `R$ ${n.toFixed(2).replace(".", ",")}`;

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
const price = (b: number, over: Partial<SetInventoryPriceInput> = {}): SetInventoryPriceInput => ({ brl: b, basis: "VARIANT", observedAt: "2026-11-03T00:00:00Z", ...over });

/** Localização padrão dos testes: todos os exemplares de cada grupo repetido "sem local". */
function defaultLocations(items: SetInventoryItemInput[]): DuplicateLocationsInput {
  const groups = new Map<string, DuplicateLocationGroup>();
  for (const i of items)
    if (i.copies >= 2) groups.set(duplicateGroupKey(i.cardVariantId, i.languageCode), { copies: i.copies, locations: [{ containerId: null, name: null, kindLabel: null, copies: i.copies, pages: [] }] });
  return { status: "ok", groups };
}

function build(
  items: SetInventoryItemInput[],
  prices = new Map<string, SetInventoryPriceInput>(),
  unavailable = new Set<string>(),
  over: { duplicates?: number; itemsComplete?: boolean; locations?: DuplicateLocationsInput } = {},
) {
  const copies = items.reduce((n, i) => n + i.copies, 0);
  const duplicates = over.duplicates ?? items.reduce((n, i) => n + Math.max(0, i.copies - 1), 0);
  const inventory = buildSetInventoryReport({
    summary: { totalCopies: copies, distinctItems: items.length, distinctSets: new Set(items.map((i) => i.cardSetCode)).size, duplicateCopies: duplicates },
    items,
    prices,
    itemsComplete: over.itemsComplete ?? true,
  });
  return { inventory, report: buildDuplicatesReport({ inventory, prices, unavailable, locations: over.locations ?? defaultLocations(items), now: NOW }) };
}

test("agrupamento variante + idioma: idiomas/variantes diferentes da mesma carta não se somam", () => {
  const v = uuid(9000);
  const en = item({ cardVariantId: v, languageCode: "en", copies: 1 });
  const pt = item({ cardVariantId: v, languageCode: "pt-BR", languageName: "Português", copies: 1 });
  const holo = item({ collectorNumber: en.collectorNumber, variantLabel: "Holo", copies: 1 });
  const { report } = build([en, pt, holo]);
  assert.equal(report.repeatedGroups, 0); // nenhum grupo com 2+ exemplares
  const two = build([item({ copies: 2 }), item({ cardVariantId: v, languageCode: "pt-BR", copies: 3 })]).report;
  assert.equal(two.repeatedGroups, 2);
  assert.deepEqual(two.sets[0]?.lines.map((l) => [l.copies, l.additional]), [
    [2, 1],
    [3, 2],
  ]);
  assert.equal(duplicateVariantText({ variantLabel: null, isDefaultVariant: true, languageName: null, languageCode: "ja" }), "Padrão · ja");
});

test("contagem: adicionais = exemplares − 1; totais e conciliação com a 5160", () => {
  const items = [item({ copies: 1 }), item({ copies: 2 }), item({ copies: 5 })];
  const { report } = build(items);
  assert.equal(report.repeatedGroups, 2);
  assert.equal(report.additionalCopies, 5); // 1 + 4
  assert.equal(report.copiesInRepeated, 7);
  assert.equal(report.totalGroups, 3);
  assert.equal(report.canonicalDuplicates, 5);
  assert.equal(report.complete, true);
  // 5160 com repetidas diferentes → incompleto (totais não definitivos).
  const off = build(items, new Map(), new Set(), { duplicates: 6 }).report;
  assert.equal(off.incompleteReason, "mismatch");
  assert.match(duplicatesIncompleteText("mismatch") ?? "", /impressão fica indisponível/);
});

test("ordem: Sets na ordem do Inventário detalhado (lançamento); dentro do Set, número, variante, idioma, id", () => {
  // As linhas chegam na ordem canônica da 5159 (Set mais recente primeiro).
  const items = [
    item({ cardSetCode: "NEW", cardSetName: "Zeta (mais recente)", collectorNumber: "10", copies: 2 }),
    item({ cardSetCode: "NEW", cardSetName: "Zeta (mais recente)", collectorNumber: "9", copies: 2 }),
    item({ cardSetCode: "NEW", cardSetName: "Zeta (mais recente)", collectorNumber: "9", variantLabel: "Holo", copies: 2 }),
    item({ cardSetCode: "OLD", cardSetName: "Alfa (antigo)", collectorNumber: "1", languageCode: "pt-BR", copies: 2 }),
    item({ cardSetCode: "OLD", cardSetName: "Alfa (antigo)", collectorNumber: "1", languageCode: "en", copies: 2 }),
  ];
  const { report } = build(items);
  assert.deepEqual(report.sets.map((s) => s.code), ["NEW", "OLD"]); // não alfabético
  assert.deepEqual(report.sets[0]?.lines.map((l) => `${l.collectorNumber}-${l.variantLabel}`), ["9-Holo", "9-Normal", "10-Normal"]);
  assert.deepEqual(report.sets[1]?.lines.map((l) => l.languageCode), ["en", "pt-BR"]);
});

test("valor só das adicionais (unitário × adicionais, centavos); subtotais por Set e total; mesma base do Valor estimado total", () => {
  const a = item({ cardSetCode: "S1", cardSetName: "S1", copies: 3 });
  const b = item({ cardSetCode: "S1", cardSetName: "S1", copies: 2 });
  const c = item({ cardSetCode: "S2", cardSetName: "S2", copies: 4 });
  const single = item({ cardSetCode: "S2", cardSetName: "S2", copies: 1 });
  const prices = new Map([[a.cardVariantId, price(10.1)], [b.cardVariantId, price(0.33)], [c.cardVariantId, price(2)], [single.cardVariantId, price(100)]]);
  const { inventory, report } = build([a, b, c, single], prices);
  assert.equal(report.sets[0]?.lines[0]?.additionalBrl, 20.2); // 2 × 10,10 — nunca 3 ×
  assert.equal(report.sets[0]?.subtotalBrl, 20.53);
  assert.equal(report.sets[1]?.subtotalBrl, 6); // 3 × 2; a carta única não entra
  assert.equal(report.additionalBrl, 26.53);
  const value = buildAcervoValueReport(inventory);
  assert.equal(report.estimatedTotalBrl, value.totalBrl);
  assert.equal(report.share, 2653 / Math.round((value.totalBrl ?? 0) * 100));
  assert.equal(report.pricedAdditional, report.additionalCopies);
  assert.equal(duplicatesCoverageNote(report), "100% das adicionais");
});

test("sem cotação × indisponível: listados; sem cotação nunca zero e não bloqueia; falha de preço → provisório", () => {
  const priced = item({ copies: 2 });
  const none = item({ copies: 3 });
  const fail = item({ copies: 2 });
  const { report } = build([priced, none, fail], new Map([[priced.cardVariantId, price(5)]]), new Set([fail.cardVariantId]));
  const kinds = report.sets[0]?.lines.map((l) => [l.reference.kind, l.additionalBrl]);
  assert.deepEqual(kinds, [
    ["priced", 5],
    ["none", null],
    ["unavailable", null],
  ]);
  assert.equal(report.pricedAdditional, 1);
  assert.equal(report.unavailableAdditional, 1);
  assert.equal(report.incompleteReason, "prices_unavailable");
  assert.equal(duplicatesValueText(report.additionalBrl, true, brl), "R$ 5,00 (parcial)");
  assert.equal(report.sets[0]?.partial, true);
  // Só "sem cotação" (leitura concluída): completo, imprime.
  const onlyNone = build([priced, none], new Map([[priced.cardVariantId, price(5)]])).report;
  assert.equal(onlyNone.complete, true);
  assert.equal(duplicatesCoverageNote(onlyNone), "33% das adicionais"); // 1 de 3
  assert.equal(duplicatesValueText(null, false, brl), "Sem cotação");
  assert.equal(duplicatesValueText(null, true, brl), "Indisponível");
});

test("sinais: preço geral da carta e desatualizada (> 14 dias); sem \"Referência internacional\"", () => {
  const fb = item({ copies: 2 });
  const old = item({ copies: 2, languageCode: "pt-BR", languageName: "Português" });
  const { report } = build(
    [fb, old],
    new Map([
      [fb.cardVariantId, price(3, { basis: "CARD_FALLBACK", observedAt: null })],
      [old.cardVariantId, price(4, { observedAt: "2026-10-01T00:00:00Z" })],
    ]),
  );
  assert.deepEqual(duplicateFlags(report.sets[0]!.lines[0]!), ["Preço geral da carta"]);
  assert.deepEqual(duplicateFlags(report.sets[0]!.lines[1]!), ["Desatualizada"]); // pt-BR: sem sinal internacional
  assert.doesNotMatch(read("../../components/reports/duplicates-report.tsx"), /Referência internacional/);
});

test("estados: sem repetidas e acervo acima do teto", () => {
  const none = build([item(), item()]).report;
  assert.equal(none.repeatedGroups, 0);
  assert.equal(none.additionalBrl, null);
  assert.equal(none.complete, true);
  const big = build([item({ copies: 2 })], new Map(), new Set(), { itemsComplete: false }).report;
  assert.equal(big.incompleteReason, "too_large");
  for (const r of ["too_large", "mismatch", "prices_unavailable"] as const) assert.match(duplicatesIncompleteText(r) ?? "", /impressão fica indisponível/);
  assert.equal(duplicatesIncompleteText(null), null);
});

type Call = { fn: string; args: Record<string, unknown> };
function fakeClient(
  groups: number,
  calls: Call[],
  options: { failPricesFor?: string; duplicatesDelta?: number; failLocations?: boolean; locationsDelta?: number; timeline?: string[] } = {},
) {
  let inFlight = 0;
  let peak = 0;
  const rows = Array.from({ length: groups }, (_, i) => ({
    card_variant_id: uuid(1 + i),
    language_code: "en",
    language_name: "Inglês",
    card_name: `Carta ${i}`,
    collector_number: String(i + 1),
    collector_total: 999,
    card_set_code: "SV1",
    card_set_name: "Escarlate e Violeta",
    is_default_variant: true,
    variant_label: null,
    copies_count: i % 3 === 0 ? 3 : 1, // 1 em cada 3 grupos com 3 exemplares
    image_path: `cards/${i}.webp`,
    total_count: groups,
  }));
  const copies = rows.reduce((n, r) => n + r.copies_count, 0);
  const dup = rows.reduce((n, r) => n + r.copies_count - 1, 0) + (options.duplicatesDelta ?? 0);
  return {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      if (fn === "get_my_inventory_summary") return { data: [{ total_copies: copies, distinct_items: groups, distinct_sets: groups ? 1 : 0, duplicate_copies: dup }], error: null };
      if (fn === "get_my_inventory_items") {
        const offset = Number(args.p_offset);
        return { data: rows.slice(offset, offset + Number(args.p_limit)), error: null };
      }
      if (fn === "get_my_inventory_group_locations") {
        options.timeline?.push("locations:start");
        await new Promise((resolve) => setTimeout(resolve, 1));
        options.timeline?.push("locations:end");
        if (options.failLocations) return { data: null, error: { code: "57014" } };
        const ids = new Set(args.p_card_variant_ids as string[]);
        const out = rows
          .filter((r) => ids.has(r.card_variant_id))
          .map((r, i) => ({
            card_variant_id: r.card_variant_id,
            language_code: r.language_code,
            copies: r.copies_count,
            locations:
              r.copies_count === 3
                ? [
                    { storage_container_id: uuid(70_000 + 1), name: "Fichário Kanto", kind_code: "BINDER", kind_label: "Fichário", copies: 1, pages: [i + 1] },
                    { storage_container_id: uuid(70_000 + 2), name: "ETB Azul", kind_code: "ETB", kind_label: "Elite Trainer Box", copies: 1, pages: [] },
                    { storage_container_id: null, name: null, kind_code: null, kind_label: null, copies: 1 + (options.locationsDelta ?? 0), pages: [] },
                  ]
                : [{ storage_container_id: null, name: null, kind_code: null, kind_label: null, copies: r.copies_count, pages: [] }],
          }));
        return { data: out, error: null };
      }
      if (fn === "get_card_variants_pricing_summary") {
        options.timeline?.push("prices:start");
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 3));
        inFlight -= 1;
        options.timeline?.push("prices:end");
        const ids = args.p_card_variant_ids as string[];
        if (options.failPricesFor && ids.includes(options.failPricesFor)) return { data: null, error: { code: "42501" } };
        return { data: ids.map((id) => ({ card_variant_id: id, has_pricing: true, brl_amount: 1.5, price_basis: "VARIANT", price_origin: "AUTOMATIC", fx_status: "CONFIRMED", observed_at: "2026-11-01T00:00:00Z" })), error: null };
      }
      return { data: null, error: { code: "PGRST202" } };
    },
    peak: () => peak,
  };
}

test("leitura: acervo inteiro (5160 + 5159), preços por variante (máx. 2), conciliação, miniatura, sem identificar o titular nem escrever", async () => {
  const calls: Call[] = [];
  const client = fakeClient(150, calls);
  const load = await getDuplicatesReport(client as never, new Date(NOW), (p) => `https://img/${p}`);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  const r = load.data.report;
  assert.equal(r.complete, true);
  assert.equal(r.repeatedGroups, 50);
  assert.equal(r.additionalCopies, 100);
  assert.equal(r.additionalBrl, 150); // 100 × R$ 1,50
  assert.equal(r.sets[0]?.lines[0]?.imageUrl, "https://img/cards/0.webp");
  assert.ok(client.peak() <= 2);
  for (const page of calls.filter((c) => c.fn === "get_my_inventory_items")) assert.equal(page.args.p_collection_id, null);
  assert.ok(calls.every((c) => Object.keys(c.args).every((key) => !/user|owner|profile/i.test(key))));
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), [
    "get_card_variants_pricing_summary",
    "get_my_inventory_group_locations",
    "get_my_inventory_items",
    "get_my_inventory_summary",
  ]);
  assert.equal(r.sets[0]?.lines[0]?.locations?.length, 3); // grupo com 3 exemplares em 3 lugares
  // Repetidas da 5160 divergentes → incompleto; falha de preço → provisório.
  const off = await getDuplicatesReport(fakeClient(30, [], { duplicatesDelta: 1 }) as never);
  assert.equal(off.status === "ready" && off.data.report.incompleteReason, "mismatch");
  const partial = await getDuplicatesReport(fakeClient(150, [], { failPricesFor: uuid(101) }) as never);
  assert.equal(partial.status === "ready" && partial.data.report.incompleteReason, "prices_unavailable");
  const big = await getDuplicatesReport(fakeClient(5_010, []) as never);
  assert.equal(big.status === "ready" && big.data.report.incompleteReason, "too_large");
});

test("integração: 7º relatório; folha institucional; miniaturas preparadas para impressão; 1 em preparação", () => {
  const items = acervoReportMenuItems({ totalCopies: 3 });
  assert.equal(items[6]?.id, "duplicates");
  assert.equal(items[6]?.icon, "duplicates");
  assert.equal(items[8]?.label, "1 relatório em preparação");
  assert.ok(acervoReportMenuItems({ totalCopies: 0 })[6]?.disabledReason); // acervo vazio → desabilitado
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /if \(report === "duplicates"\) \{\s*return readDuplicatesOnce\(\)/);
  assert.match(overlay, /incomplete: duplicatesIncompleteText\(r\.data\.report\.incompleteReason\)/);
  assert.match(overlay, /preparePrint: \(onProgress\) => preparePrintImages\(onProgress\)/);
  assert.match(overlay, /const readDuplicatesOnce = shareInFlight\(\(\) => readDuplicatesReport\(\)\);/);
  assert.match(overlay, /return readDuplicatesOnce\(\)\.then/);
  // Só o R1-G compartilha a leitura; os outros relatórios seguem chamando a própria ação direto.
  for (const other of ["readSetInventoryReport", "readFavoritesReport", "readWishlistReport", "readTopCardsReport", "readAcervoValueReport", "readSetSummaryReport"])
    assert.match(overlay, new RegExp(`return ${other}\\(\\)\\.then`), other);
  const shell = read("../../components/reports/report-sheet-overlay.tsx");
  assert.match(shell, /prepare=\{entry\.status === "ready" \? entry\.preparePrint : undefined\}/);
  const button = read("../../components/reports/report-print-button.tsx");
  assert.match(button, /if \(!prepare\) \{\s*open\(\);\s*return;\s*\}/); // sem preparo: comportamento de sempre
  const gate = read("../../components/reports/print-image-gate.tsx");
  assert.match(gate, /if \(img\.loading === "lazy"\) img\.loading = "eager";/);
  assert.match(gate, /concurrency: PRINT_IMAGE_CONCURRENCY/);
  assert.match(gate, /loadImage\(img, PRINT_IMAGE_ITEM_TIMEOUT_MS\)/); // 30 s por imagem, sem teto global
  assert.doesNotMatch(gate, /render\/image|width=|quality=/); // nenhuma transformação de imagem (custo zero)
  assert.match(button, /Preparando imagens \$\{progress\.ready\}\/\$\{progress\.total\}/);
  assert.match(gate, /className=\{pending > 0 \? "print:hidden" : undefined\}/); // Ctrl+P com miniaturas pendentes: só aviso
  const sheet = read("../../components/reports/duplicates-report.tsx");
  assert.match(sheet, /<PrintImageGate>/);
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  for (const label of ["Itens repetidos", "Cópias adicionais", "Valor das adicionais", "Cobertura de preços"]) assert.match(sheet, new RegExp(`label="${label}"`), label);
  assert.match(sheet, /<Indicator label="Cópias adicionais" value=\{formatCount\(report\.additionalCopies\)\} emphasis \/>/); // sem texto de exemplares
  for (const label of ["Número", "Carta", "Cópias adicionais", "Referência NM", "Valor das adicionais"]) assert.match(sheet, new RegExp(`>\\s*${label}\\s*<`), label);
  assert.doesNotMatch(sheet, />\s*Exemplares\s*</); // coluna removida
  assert.doesNotMatch(sheet, /copiesInRepeated/); // total só com adicionais (contagem completa preservada no modelo)
  assert.match(sheet, /const COLUMNS = 5;/);
  // Cabeçalho institucional e indicadores fora do <thead> (só na 1ª página); thead = identificação curta + colunas.
  const thead = sheet.slice(sheet.indexOf("<thead>\n"), sheet.indexOf("</thead>"));
  assert.doesNotMatch(thead, /cabecalho|Indicator/);
  assert.match(thead, /hidden print:table-row/);
  assert.match(thead, /\{entry\.title\} · Meu acervo/);
  assert.ok(sheet.indexOf("{cabecalho}", sheet.indexOf("<PrintImageGate>")) < sheet.indexOf("<table"));
  assert.match(sheet, /duplicateAdditionalLocationsText\(line\.additionalLocations\)/);
  assert.match(sheet, /<RelatorioRodape \/>/);
  assert.match(sheet, /h-\[34px\] w-\[24px\]/);
  assert.match(sheet, /breakInside: set\.lines\.length <= KEEP_TOGETHER_LINES \? "avoid" : "auto"/);
  assert.match(sheet, /breakAfter: "avoid"/); // título do Set preso às linhas (sem Set órfão)
  assert.doesNotMatch(sheet, /venda disponível|para troca:|reservar/i);
  for (const source of [read("./duplicates.ts"), read("./duplicates-queries.ts")]) assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(|\.upsert\(|\.from\("/);
});

// ---------------------------------------------------------------------------
// Localização física (5354)
// ---------------------------------------------------------------------------

const loc = (copies: number, over: Partial<{ containerId: string | null; name: string | null; kindLabel: string | null; pages: number[] }> = {}) => ({
  containerId: uuid(80_000 + copies),
  name: `Caixa ${copies}`,
  kindLabel: "Caixa",
  pages: [] as number[],
  copies,
  ...over,
});

test("localização: 1, 2 e 3 recipientes, páginas do fichário e sem local; sem duplicar grupos nem valores", () => {
  const one = item({ copies: 2 });
  const two = item({ copies: 3 });
  const three = item({ copies: 4 });
  const groups = new Map<string, DuplicateLocationGroup>([
    [duplicateGroupKey(one.cardVariantId, "en"), { copies: 2, locations: [loc(2, { name: "Fichário Kanto", kindLabel: "Fichário", pages: [3, 7] })] }],
    [duplicateGroupKey(two.cardVariantId, "en"), { copies: 3, locations: [loc(2, { name: "ETB Azul" }), loc(1, { containerId: null, name: null, kindLabel: null })] }],
    [
      duplicateGroupKey(three.cardVariantId, "en"),
      { copies: 4, locations: [loc(2, { name: "Fichário Kanto", pages: [14] }), loc(1, { containerId: uuid(81_001), name: "Deck" }), loc(1, { containerId: null, name: null })] },
    ],
  ]);
  const prices = new Map([[one.cardVariantId, price(10)], [two.cardVariantId, price(1)], [three.cardVariantId, price(2)]]);
  const { report } = build([one, two, three], prices, new Set(), { locations: { status: "ok", groups } });
  assert.equal(report.complete, true);
  const lines = report.sets[0]!.lines;
  assert.equal(lines.length, 3); // uma linha por grupo, por mais locais que tenha
  assert.deepEqual(lines.map((l) => l.locations?.length), [1, 2, 3]);
  // Exibição = só as adicionais (a unidade de referência sai do local de onde foi tomada).
  assert.equal(duplicateAdditionalLocationsText(lines[0]!.additionalLocations), "Fichário Kanto: 1 adicional (p. 7)"); // 2 exemplares em 2 páginas: referência na menor
  assert.equal(duplicateAdditionalLocationsText(lines[1]!.additionalLocations), "ETB Azul: 1 adicional; Sem local definido: 1 adicional");
  assert.equal(
    duplicateAdditionalLocationsText(lines[2]!.additionalLocations),
    "Deck: 1 adicional; Fichário Kanto: 1 adicional (página não identificada); Sem local definido: 1 adicional",
  );
  // Valores e adicionais iguais aos de sem localização (nada multiplicado pelos locais).
  assert.deepEqual(lines.map((l) => [l.additional, l.additionalBrl]), [
    [1, 10],
    [2, 2],
    [3, 6],
  ]);
  assert.equal(report.additionalBrl, 18);
  assert.equal(report.additionalCopies, 6);
  assert.equal(duplicateAdditionalLocationsText(null), "Localização indisponível");
});

test("localização: separação por variante + idioma (mesma variante em dois idiomas, locais independentes)", () => {
  const v = uuid(9100);
  const en = item({ cardVariantId: v, languageCode: "en", copies: 2 });
  const pt = item({ cardVariantId: v, languageCode: "pt-BR", languageName: "Português", copies: 3 });
  const groups = new Map<string, DuplicateLocationGroup>([
    [duplicateGroupKey(v, "en"), { copies: 2, locations: [loc(2, { name: "ETB" })] }],
    [duplicateGroupKey(v, "pt-BR"), { copies: 3, locations: [loc(1, { name: "Fichário", pages: [5] }), loc(2, { containerId: null, name: null })] }],
  ]);
  const { report } = build([en, pt], new Map(), new Set(), { locations: { status: "ok", groups } });
  assert.equal(report.complete, true);
  const byLang = Object.fromEntries(report.sets[0]!.lines.map((l) => [l.languageCode, duplicateAdditionalLocationsText(l.additionalLocations)]));
  assert.equal(byLang.en, "ETB: 1 adicional");
  assert.equal(byLang["pt-BR"], "Sem local definido: 2 adicionais"); // referência = o exemplar do fichário (p. 5)
});

test("localização: conciliação — grupo ausente, Σ locais ≠ exemplares ou exemplares ≠ 5159 → incompleto; falha de leitura → incompleto", () => {
  const a = item({ copies: 3 });
  const b = item({ copies: 2 });
  const key = (i: SetInventoryItemInput) => duplicateGroupKey(i.cardVariantId, i.languageCode);
  const missing = build([a, b], new Map(), new Set(), { locations: { status: "ok", groups: new Map([[key(a), { copies: 3, locations: [loc(3)] }]]) } }).report;
  assert.equal(missing.incompleteReason, "locations_mismatch");
  assert.equal(missing.locationMismatches, 1);
  assert.equal(missing.sets[0]!.lines[1]!.locations, null);
  const sumOff = build([a], new Map(), new Set(), { locations: { status: "ok", groups: new Map([[key(a), { copies: 3, locations: [loc(2)] }]]) } }).report;
  assert.equal(sumOff.incompleteReason, "locations_mismatch");
  const countOff = build([a], new Map(), new Set(), { locations: { status: "ok", groups: new Map([[key(a), { copies: 4, locations: [loc(4)] }]]) } }).report;
  assert.equal(countOff.incompleteReason, "locations_mismatch");
  const failed = build([a, b], new Map(), new Set(), { locations: { status: "unavailable" } }).report;
  assert.equal(failed.incompleteReason, "locations_unavailable");
  assert.equal(failed.complete, false);
  assert.ok(failed.sets[0]!.lines.every((l) => l.locations === null));
  // Sem repetidas: a falha de localização não importa.
  assert.equal(build([item()], new Map(), new Set(), { locations: { status: "unavailable" } }).report.complete, true);
  // Precedência: divergência com a 5160 vem antes; preço indisponível vem depois.
  assert.equal(build([a], new Map(), new Set(), { duplicates: 9, locations: { status: "unavailable" } }).report.incompleteReason, "mismatch");
  assert.equal(build([a], new Map(), new Set([a.cardVariantId]), { locations: { status: "unavailable" } }).report.incompleteReason, "locations_unavailable");
  for (const r of ["locations_unavailable", "locations_mismatch"] as const) assert.match(duplicatesIncompleteText(r) ?? "", /impressão fica indisponível/);
});

test("5354: contrato da resposta (linha fora do contrato ou grupo duplicado → bloco inválido)", () => {
  const ok = parseGroupLocations([
    { card_variant_id: uuid(1).toUpperCase(), language_code: "en", copies: 2, locations: [{ storage_container_id: null, name: null, kind_code: null, kind_label: null, copies: 2, pages: [] }] },
  ]);
  assert.equal(ok?.get(duplicateGroupKey(uuid(1), "en"))?.copies, 2);
  assert.deepEqual(parseGroupLocations([]), new Map());
  assert.equal(parseGroupLocations(null), null);
  assert.equal(parseGroupLocations([{ card_variant_id: uuid(1), language_code: "en", copies: 2, locations: [{ storage_container_id: null, copies: 0, pages: [] }] }]), null);
  assert.equal(parseGroupLocations([{ card_variant_id: uuid(1), language_code: "en", copies: 2, locations: [{ storage_container_id: "x", copies: 2, pages: [] }] }]), null);
  assert.equal(parseGroupLocations([{ card_variant_id: uuid(1), language_code: "en", copies: 2, locations: [{ storage_container_id: null, copies: 2, pages: [0] }] }]), null);
  const row = { card_variant_id: uuid(1), language_code: "en", copies: 1, locations: [] };
  assert.equal(parseGroupLocations([row, row]), null);
});

test("5354: só variantes repetidas, blocos de até 250, sem N+1, em paralelo com os preços; falha → incompleto", async () => {
  const calls: Call[] = [];
  const timeline: string[] = [];
  // 2.400 grupos → 800 repetidos (1 a cada 3) → 4 blocos de até 250 (nunca uma chamada por grupo).
  const load = await getDuplicatesReport(fakeClient(2_400, calls, { timeline }) as never, new Date(NOW));
  assert.equal(load.status === "ready" && load.data.report.complete, true);
  const locCalls = calls.filter((c) => c.fn === "get_my_inventory_group_locations");
  assert.equal(locCalls.length, Math.ceil(800 / LOCATIONS_CHUNK));
  const requested = locCalls.flatMap((c) => c.args.p_card_variant_ids as string[]);
  assert.ok(locCalls.every((c) => (c.args.p_card_variant_ids as string[]).length <= LOCATIONS_CHUNK));
  assert.equal(new Set(requested).size, 800);
  assert.equal(requested.length, 800);
  assert.ok(requested.every((id) => (Number.parseInt(id.slice(-12), 16) - 1) % 3 === 0)); // só os repetidos
  assert.equal(calls.filter((c) => c.fn === "get_my_inventory_items").length, Math.ceil(2_400 / 96));
  assert.ok(locCalls.every((c) => Object.keys(c.args).join() === "p_card_variant_ids")); // nenhum id de titular
  // Paralelo: a 1ª localização começa antes de terminar o último bloco de preços.
  assert.ok(timeline.indexOf("locations:start") < timeline.lastIndexOf("prices:end"));
  assert.ok(timeline.indexOf("prices:start") < timeline.lastIndexOf("locations:end"));
  // Concorrência da Pricing Resilience inalterada (máx. 2).
  const client = fakeClient(2_400, []);
  await getDuplicatesReport(client as never);
  assert.ok(client.peak() <= 2);
  const failed = await getDuplicatesReport(fakeClient(150, [], { failLocations: true }) as never);
  assert.equal(failed.status === "ready" && failed.data.report.incompleteReason, "locations_unavailable");
  const off = await getDuplicatesReport(fakeClient(150, [], { locationsDelta: 1 }) as never);
  assert.equal(off.status === "ready" && off.data.report.incompleteReason, "locations_mismatch");
  // Sem repetidas: a 5354 nem é chamada.
  const noneCalls: Call[] = [];
  const rows = await readGroupLocations({ rpc: async (fn, args) => (noneCalls.push({ fn, args: args ?? {} }), { data: [], error: null }) }, []);
  assert.equal(rows.status, "ok");
  assert.equal(noneCalls.length, 0);
});

test("instrumentação: intervalo e chamadas por RPC, sem alterar a resposta", async () => {
  let t = 0;
  const spans = new Map<string, { first: number; last: number; calls: number }>();
  const base = { rpc: async (fn: string, _args?: Record<string, unknown>) => ({ data: fn, error: null }) };
  const timed = timedRpc(base, 0, spans, () => (t += 10));
  assert.deepEqual(await timed.rpc("a"), { data: "a", error: null });
  await timed.rpc("a", { x: 1 });
  assert.deepEqual(spans.get("a"), { first: 10, last: 40, calls: 2 });
  const source = read("./duplicates-queries.ts");
  assert.match(source, /console\.info\("\[reports\] cartas repetidas", \{\s*ms: \{\s*total:/);
  for (const stage of ["summary", "inventory", "prices", "locations", "build"]) assert.match(source, new RegExp(`${stage}: `), stage);
  assert.doesNotMatch(source.slice(source.indexOf("console.info")), /cardVariantId|user|email|name:/); // sem dados do titular
});

test("leitura única simultânea: pedidos equivalentes em andamento reutilizam a mesma operação; sem cache depois", async () => {
  let runs = 0;
  let release: (v: number) => void = () => {};
  const shared = shareInFlight(() => {
    runs += 1;
    return new Promise<number>((resolve) => (release = resolve));
  });
  const first = shared();
  const second = shared(); // Strict Mode: efeito de carga rodando de novo
  assert.equal(first, second);
  release(7);
  assert.deepEqual(await Promise.all([first, second]), [7, 7]);
  assert.equal(runs, 1);
  const third = shared(); // nova abertura: lê de novo
  release(8);
  assert.equal(await third, 8);
  assert.equal(runs, 2);
  const failing = shareInFlight(() => Promise.reject(new Error("x")));
  await assert.rejects(failing());
  await assert.rejects(failing()); // falha não fica guardada
});

test("fila de miniaturas: no máximo 6 simultâneas, progresso real, só pendentes, nova tentativa só das que falharam", async () => {
  type Img = { id: number; ready: boolean; failOnce: boolean };
  const images: Img[] = Array.from({ length: 40 }, (_, id) => ({ id, ready: id < 10, failOnce: id % 7 === 0 && id >= 10 }));
  let active = 0;
  let peak = 0;
  const loaded: number[] = [];
  const progress: number[] = [];
  const load = async (img: Img) => {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, 1 + (img.id % 3)));
    active -= 1;
    loaded.push(img.id);
    if (img.failOnce) {
      img.failOnce = false;
      return false; // não respondeu / erro: falha individual, a fila segue
    }
    img.ready = true;
    return true;
  };
  const first = await prepareImageQueue(images, { isReady: (i) => i.ready, load, onProgress: (r) => progress.push(r) });
  assert.equal(PRINT_IMAGE_CONCURRENCY, 6);
  assert.ok(peak <= 6 && peak > 1);
  assert.equal(first.total, 40);
  assert.deepEqual(first.failed.map((i) => i.id).sort((a, b) => a - b), [14, 21, 28, 35]);
  assert.equal(first.ready, 36);
  assert.equal(progress[0], 10); // as já carregadas contam desde o início
  assert.deepEqual(progress, [...progress].sort((a, b) => a - b));
  assert.ok(loaded.every((id) => id >= 10)); // as prontas nunca são pedidas de novo
  loaded.length = 0;
  const retry = await prepareImageQueue(images, { isReady: (i) => i.ready, load });
  assert.deepEqual(loaded.sort((a, b) => a - b), [14, 21, 28, 35]); // só as que faltavam
  assert.equal(retry.failed.length, 0);
  assert.equal(retry.ready, 40);
  const empty = await prepareImageQueue([], { isReady: () => true, load: async () => true });
  assert.deepEqual(empty, { total: 0, ready: 0, failed: [] });
});

test("impressão: incompleto bloqueia; Ctrl+P com miniaturas pendentes só imprime o aviso; relatórios anteriores sem preparo", () => {
  const shell = read("../../components/reports/report-sheet-overlay.tsx");
  assert.match(shell, /const ready = entry\.status === "ready" && incomplete === null;/);
  assert.match(shell, /<div className=\{incomplete \? "print:hidden" : undefined\}>/);
  const gate = read("../../components/reports/print-image-gate.tsx");
  assert.match(gate, /const isReady = \(img: HTMLImageElement\) => img\.complete && img\.naturalWidth > 0;/); // falha conta como pendente
  assert.match(gate, /data-print-images=\{pending === 0 \? "ready" : "pending"\}/);
  const button = read("../../components/reports/report-print-button.tsx");
  assert.match(button, /if \(!ready\) return;/);
  assert.match(button, /void prepare\(setProgress\)/);
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.equal(overlay.match(/preparePrint:/g)?.length, 1); // só o R1-G prepara imagens
});

// ---------------------------------------------------------------------------
// Só as cópias adicionais por local (DUPLICATE-ONLY PHYSICAL LOCATIONS-01)
// ---------------------------------------------------------------------------

const place = (id: number | null, name: string | null, copies: number, pages: number[] = []) => ({
  containerId: id === null ? null : uuid(90_000 + id),
  name,
  kindLabel: null,
  copies,
  pages,
});
const addText = (locations: Parameters<typeof duplicateAdditionalLocations>[0]) => duplicateAdditionalLocationsText(duplicateAdditionalLocations(locations));
const addSum = (locations: Parameters<typeof duplicateAdditionalLocations>[0]) => duplicateAdditionalLocations(locations).reduce((n, l) => n + l.copies, 0);

test("adicionais por local: 1 no fichário + 7 na ETB → 7 adicionais na ETB (exemplo Exeggcute)", () => {
  const locs = [place(6, "ETB006 — Celebração de 30 Anos", 7), place(1, "F006 — Fichário Coleção ME5.5", 1, [1])];
  assert.equal(duplicateReferenceLocation(locs)?.name, "F006 — Fichário Coleção ME5.5");
  assert.equal(addText(locs), "ETB006 — Celebração de 30 Anos: 7 adicionais"); // o fichário (referência) não aparece
  assert.equal(addSum(locs), 7);
});

test("adicionais por local: 2 no fichário + 3 na ETB → 4 adicionais (1 fichário + 3 ETB)", () => {
  const distinct = [place(6, "ETB", 3), place(1, "Fichário", 2, [1, 4])];
  assert.equal(addText(distinct), "ETB: 3 adicionais; Fichário: 1 adicional (p. 4)"); // páginas = exemplares: referência na p. 1
  assert.equal(addSum(distinct), 4);
  // Mesma página para os dois (ou um sem bolso): a página da adicional não é inventada.
  assert.equal(addText([place(6, "ETB", 3), place(1, "Fichário", 2, [1])]), "ETB: 3 adicionais; Fichário: 1 adicional (página não identificada)");
});

test("adicionais por local: todos no mesmo recipiente; recipientes sem fichário; sem local definido", () => {
  assert.equal(addText([place(6, "ETB", 4)]), "ETB: 3 adicionais");
  assert.equal(addText([place(1, "Fichário", 3, [2, 5, 9])]), "Fichário: 2 adicionais (p. 5, 9)");
  // Sem exemplar posicionado: referência = 1º recipiente definido por nome (estável, não pela quantidade).
  const noBinder = [place(7, "Caixa B", 3), place(8, "Caixa A", 1)];
  assert.equal(duplicateReferenceLocation(noBinder)?.name, "Caixa A");
  assert.equal(addText(noBinder), "Caixa B: 3 adicionais");
  assert.equal(addText([place(8, "Caixa A", 1), place(7, "Caixa B", 3)]), "Caixa B: 3 adicionais"); // ordem de entrada não importa
  // Sem local: a referência sai de um recipiente definido quando existe; só sem local → sai do "sem local".
  assert.equal(addText([place(null, null, 2), place(6, "ETB", 1)]), "Sem local definido: 2 adicionais");
  assert.equal(addText([place(null, null, 3)]), "Sem local definido: 2 adicionais");
  // O tipo do recipiente não prova posicionamento: fichário físico sem página não vira referência preferida.
  const binderNoPage = [{ ...place(1, "Fichário sem posição", 1), kindLabel: "Fichário" }, place(6, "ETB", 2, [3])];
  assert.equal(duplicateReferenceLocation(binderNoPage)?.name, "ETB"); // só a ETB tem exemplar num bolso do fichário digital
  // ETB: 2 exemplares e 1 página → a página da adicional que ficou na ETB não é determinável.
  assert.equal(addText(binderNoPage), "ETB: 1 adicional (página não identificada); Fichário sem posição: 1 adicional");
});

test("adicionais por local: mais de um fichário — referência determinística (nome, id); os outros mantêm as páginas", () => {
  const locs = [place(2, "Fichário Zeta", 1, [8]), place(3, "Fichário Alfa", 2, [3, 6]), place(6, "ETB", 1)];
  assert.equal(duplicateReferenceLocation(locs)?.name, "Fichário Alfa");
  assert.equal(addText(locs), "ETB: 1 adicional; Fichário Alfa: 1 adicional (p. 6); Fichário Zeta: 1 adicional (p. 8)");
  assert.equal(addText([...locs].reverse()), addText(locs)); // independente da ordem de chegada
  // Mesmo nome: desempate pelo id do recipiente.
  const same = [place(5, "Fichário", 1, [1]), place(4, "Fichário", 1, [2])];
  assert.equal(duplicateReferenceLocation(same)?.containerId, uuid(90_004));
  assert.equal(addText(same), "Fichário: 1 adicional (p. 1)");
});

test("adicionais por local no relatório: idiomas separados, Σ por local = adicionais, sem perda nem duplicação; valor e cobertura inalterados", () => {
  const v = uuid(9200);
  const en = item({ cardVariantId: v, languageCode: "en", copies: 8 });
  const pt = item({ cardVariantId: v, languageCode: "pt-BR", languageName: "Português", copies: 5 });
  const solo = item({ copies: 3 });
  const groups = new Map<string, DuplicateLocationGroup>([
    [duplicateGroupKey(v, "en"), { copies: 8, locations: [place(6, "ETB006", 7), place(1, "F006", 1, [1])] }],
    [duplicateGroupKey(v, "pt-BR"), { copies: 5, locations: [place(6, "ETB006", 3), place(1, "F006", 2, [2, 4])] }],
    [duplicateGroupKey(solo.cardVariantId, "en"), { copies: 3, locations: [place(null, null, 3)] }],
  ]);
  const prices = new Map([[v, price(4)], [solo.cardVariantId, price(1.25)]]);
  const withLoc = build([en, pt, solo], prices, new Set(), { locations: { status: "ok", groups } }).report;
  const plain = build([en, pt, solo], prices).report; // mesma base com a localização padrão
  assert.equal(withLoc.complete, true);
  const lines = withLoc.sets[0]!.lines;
  const text = Object.fromEntries(lines.map((l) => [`${l.cardVariantId}|${l.languageCode}`, duplicateAdditionalLocationsText(l.additionalLocations)]));
  assert.equal(text[`${v}|en`], "ETB006: 7 adicionais");
  assert.equal(text[`${v}|pt-BR`], "ETB006: 3 adicionais; F006: 1 adicional (p. 4)");
  assert.equal(text[`${solo.cardVariantId}|en`], "Sem local definido: 2 adicionais");
  for (const line of lines) {
    assert.equal(line.additionalLocations!.reduce((n, l) => n + l.copies, 0), line.additional);
    assert.ok(line.additionalLocations!.every((l) => l.copies > 0)); // zero não aparece
    assert.equal(line.locations!.reduce((n, l) => n + l.copies, 0), line.copies); // distribuição completa preservada no modelo
  }
  assert.equal(lines.length, 3);
  for (const key of ["additionalCopies", "additionalBrl", "pricedAdditional", "share", "repeatedGroups", "copiesInRepeated"] as const) assert.equal(withLoc[key], plain[key], key);
  assert.equal(withLoc.additionalBrl, 7 * 4 + 4 * 4 + 2 * 1.25);
  assert.equal(duplicatesCoverageNote(withLoc), duplicatesCoverageNote(plain));
  // Grupo que não concilia continua sem distribuição exibida (nada inventado).
  const off = build([en], prices, new Set(), { locations: { status: "ok", groups: new Map([[duplicateGroupKey(v, "en"), { copies: 8, locations: [place(6, "ETB006", 7)] }]]) } }).report;
  assert.equal(off.incompleteReason, "locations_mismatch");
  assert.equal(off.sets[0]!.lines[0]!.additionalLocations, null);
});
