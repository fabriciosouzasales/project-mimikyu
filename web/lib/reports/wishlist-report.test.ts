// V1-14 R1-E — "Minha Lista de Desejos" (5º relatório do Meu acervo): regras puras, leitura com
// cliente falso (5350/5351 + 3989 com Pricing Resilience) e checagens estáticas da folha.
// Executar: node --experimental-strip-types --test lib/reports/wishlist-report.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { ACERVO_REPORT_CATALOG, acervoReportMenuItems } from "./acervo-reports.ts";
import { getWishlistReport } from "./wishlist-report-queries.ts";
import {
  WISHLIST_REPORT_MAX,
  WISHLIST_REPORT_PAGE,
  type WishReportEntryInput,
  buildWishlistReport,
  parseWishlistReportPage,
  referenceOf,
  wishCoverageText,
  wishOwnershipText,
  wishValueText,
  wishVariantText,
  wishlistIncompleteText,
} from "./wishlist-report.ts";

const logs: string[] = [];
console.error = (...args: unknown[]) => void logs.push(args.map(String).join(" "));
console.warn = (...args: unknown[]) => void logs.push(args.map(String).join(" "));

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const brl = (n: number) => `R$ ${n.toFixed(2).replace(".", ",")}`;

let seq = 0;
function wish(over: Partial<WishReportEntryInput> = {}): WishReportEntryInput {
  seq += 1;
  return {
    entryId: uuid(10_000 + seq),
    cardVariantId: uuid(seq),
    cardId: uuid(20_000 + seq),
    cardName: `Carta ${seq}`,
    collectorNumber: String(seq),
    collectorTotal: 100,
    cardSetCode: "AAA",
    cardSetName: "Alfa",
    variantLabel: "Normal",
    variantAvailable: true,
    languageCode: null,
    ownership: "NONE",
    imagePath: null,
    wishedAt: "2026-11-01T12:00:00Z",
    ...over,
  };
}

const priced = (amount: number) => ({ hasPricing: true, brlAmount: amount });
const build = (entries: WishReportEntryInput[], prices = new Map<string, { hasPricing: boolean; brlAmount: number | null }>(), unavailable = new Set<string>()) =>
  buildWishlistReport({ entries, totalCount: entries.length, withinLimit: true, prices, unavailable });

test("identidade: um desejo = variante + idioma; mesma variante em dois idiomas = dois desejos, uma variante", () => {
  const v = uuid(900);
  const r = build([wish({ cardVariantId: v, languageCode: "pt-BR" }), wish({ cardVariantId: v, languageCode: "en" }), wish({ cardVariantId: v, languageCode: null })], new Map([[v, priced(10)]]));
  assert.equal(r.entryCount, 3);
  assert.equal(r.variantCount, 1);
  assert.equal(r.sets[0]?.lines.length, 3); // uma linha por desejo
  assert.deepEqual(r.sets[0]?.lines.map(wishVariantText), ["Normal · Português", "Normal · Inglês", "Normal · Qualquer idioma"]);
  // Referência sem duplicação: 1 variante → R$ 10, nunca 3 × R$ 10.
  assert.equal(r.all.totalBrl, 10);
  assert.equal(r.pending.totalBrl, 10);
  assert.equal(r.all.variants, 1);
  assert.equal(wishVariantText({ variantLabel: null, languageCode: null }), "Qualquer idioma");
});

test("pendentes e os quatro estados de posse", () => {
  const entries = [
    wish({ ownership: "SAME_VARIANT_LANGUAGE" }),
    wish({ ownership: "SAME_VARIANT_OTHER_LANGUAGE" }),
    wish({ ownership: "OTHER_VARIANT" }),
    wish({ ownership: "NONE" }),
  ];
  const r = build(entries);
  assert.equal(r.pendingCount, 3);
  assert.deepEqual(r.sets[0]?.lines.map((l) => [wishOwnershipText(l.ownership), l.pending]), [
    ["Já no acervo", false],
    ["No acervo em outro idioma", true],
    ["Você tem outra variante", true],
    ["Não possui", true],
  ]);
});

test("referência pendente: uma por variante distinta pendente; satisfeitas só na lista inteira; sem multiplicar", () => {
  const a = uuid(901);
  const b = uuid(902);
  const c = uuid(903);
  const entries = [
    wish({ cardVariantId: a, ownership: "SAME_VARIANT_LANGUAGE", languageCode: "en" }), // satisfeito…
    wish({ cardVariantId: a, ownership: "SAME_VARIANT_OTHER_LANGUAGE", languageCode: "pt-BR" }), // …mas a variante ainda tem desejo pendente
    wish({ cardVariantId: b, ownership: "SAME_VARIANT_LANGUAGE" }), // só satisfeito
    wish({ cardVariantId: c, ownership: "NONE" }),
  ];
  const r = build(entries, new Map([[a, priced(10.1)], [b, priced(5)], [c, priced(0.2)]]));
  assert.equal(r.pending.variants, 2);
  assert.equal(r.pending.totalBrl, 10.3); // a + c (centavos, sem erro de ponto flutuante)
  assert.equal(r.all.totalBrl, 15.3); // a + b + c
  assert.equal(wishCoverageText(r.pending), "2 de 2 variantes cotadas");
  assert.equal(wishValueText(r.pending, brl), "R$ 10,30");
});

test("ausência de cotação ≠ indisponível; referência ≤ 0 não é cotação; nunca R$ 0", () => {
  const none = uuid(904);
  const zero = uuid(905);
  const fail = uuid(906);
  const fx = uuid(907);
  const prices = new Map<string, { hasPricing: boolean; brlAmount: number | null }>([[none, { hasPricing: false, brlAmount: null }], [zero, priced(0)], [fx, { hasPricing: false, brlAmount: 3 }]]);
  const unavailable = new Set([fail]);
  assert.deepEqual(referenceOf(none, prices, unavailable), { kind: "none" });
  assert.deepEqual(referenceOf(zero, prices, unavailable), { kind: "none" });
  assert.deepEqual(referenceOf(fx, prices, unavailable), { kind: "none" });
  assert.deepEqual(referenceOf(uuid(999), prices, unavailable), { kind: "none" }); // lida, sem linha
  assert.deepEqual(referenceOf(fail, prices, unavailable), { kind: "unavailable" });
  // Só sem cotação: soma "Sem cotação", completo.
  const onlyNone = build([wish({ cardVariantId: none }), wish({ cardVariantId: zero })], prices);
  assert.equal(onlyNone.all.totalBrl, null);
  assert.equal(wishValueText(onlyNone.all, brl), "Sem cotação");
  assert.equal(onlyNone.complete, true);
});

test("falha parcial de preço: preços recuperados preservados, agregado parcial, impressão bloqueada", () => {
  const ok = uuid(908);
  const fail = uuid(909);
  const r = build([wish({ cardVariantId: ok }), wish({ cardVariantId: fail })], new Map([[ok, priced(7)]]), new Set([fail]));
  assert.equal(r.sets[0]?.lines[0]?.reference.kind, "priced");
  assert.equal(r.sets[0]?.lines[1]?.reference.kind, "unavailable");
  assert.equal(r.pending.totalBrl, 7);
  assert.equal(r.pending.unavailable, 1);
  assert.equal(wishValueText(r.pending, brl), "R$ 7,00 (parcial)"); // nunca apresentado como definitivo
  assert.equal(wishCoverageText(r.pending), "1 de 2 variantes cotadas · 1 indisponível agora");
  assert.equal(r.complete, false);
  assert.equal(r.incompleteReason, "prices_unavailable");
  assert.match(wishlistIncompleteText("prices_unavailable") ?? "", /impressão fica indisponível/);
  const allFailed = build([wish({ cardVariantId: fail })], new Map(), new Set([fail]));
  assert.equal(wishValueText(allFailed.pending, brl), "Indisponível");
});

test("variante desativada continua listada e sinalizada", () => {
  const r = build([wish({ variantAvailable: false }), wish()]);
  assert.equal(r.entryCount, 2);
  assert.deepEqual(r.sets[0]?.lines.map((l) => l.variantAvailable), [false, true]);
  const sheet = read("../../components/reports/wishlist-report.tsx");
  assert.match(sheet, /line\.variantAvailable \? null : <span[^>]*>· Indisponível no catálogo<\/span>/);
});

test("ordenação: Sets por nome pt-BR e código; cartas por número crescente; empates mantêm variante e idioma do banco", () => {
  const entries = [
    wish({ cardSetCode: "ZZZ", cardSetName: "Écran", collectorNumber: "10" }),
    wish({ cardSetCode: "BBB", cardSetName: "Beta", collectorNumber: "10", variantLabel: "Normal", languageCode: "pt-BR" }),
    wish({ cardSetCode: "BBB", cardSetName: "Beta", collectorNumber: "10", variantLabel: "Normal", languageCode: "en" }),
    wish({ cardSetCode: "BBB", cardSetName: "Beta", collectorNumber: "2" }),
    wish({ cardSetCode: "AAB", cardSetName: "alfa", collectorNumber: "1" }),
    wish({ cardSetCode: "AAA", cardSetName: "Alfa", collectorNumber: "TG05" }),
    wish({ cardSetCode: "AAA", cardSetName: "Alfa", collectorNumber: "9" }),
  ];
  const r = build(entries);
  assert.deepEqual(r.sets.map((s) => s.code), ["AAA", "AAB", "BBB", "ZZZ"]); // "Alfa"="alfa" → código desempata; "Écran" depois de "Beta"
  assert.deepEqual(r.sets[0]?.lines.map((l) => l.collectorNumber), ["9", "TG05"]);
  assert.deepEqual(r.sets[2]?.lines.map((l) => [l.collectorNumber, l.languageCode]), [
    ["2", null],
    ["10", "pt-BR"],
    ["10", "en"],
  ]);
  assert.equal(r.setCount, 4);
});

test("integridade: repetição entre páginas, total divergente e teto → incompleto", () => {
  const e = wish();
  const dup = buildWishlistReport({ entries: [e, e], totalCount: 2, withinLimit: true, prices: new Map(), unavailable: new Set() });
  assert.equal(dup.entryCount, 1);
  assert.equal(dup.incompleteReason, "changed");
  assert.equal(buildWishlistReport({ entries: [wish()], totalCount: 2, withinLimit: true, prices: new Map(), unavailable: new Set() }).incompleteReason, "changed");
  assert.equal(buildWishlistReport({ entries: [wish()], totalCount: 1, withinLimit: false, prices: new Map(), unavailable: new Set() }).incompleteReason, "too_large");
  for (const reason of ["too_large", "changed", "prices_unavailable"] as const) assert.match(wishlistIncompleteText(reason) ?? "", /impressão fica indisponível/);
  assert.equal(wishlistIncompleteText(null), null);
});

function row(i: number, total: number, over: Record<string, unknown> = {}) {
  return {
    entry_id: uuid(50_000 + i),
    card_variant_id: uuid(1 + (i % 150)), // 150 variantes distintas no máximo
    card_id: uuid(60_000 + i),
    card_name: `Carta ${i}`,
    collector_number: String(i + 1),
    collector_total: 999,
    card_set_id: uuid(70_000),
    card_set_code: "SV1",
    card_set_name: "Escarlate e Violeta",
    rarity_id: null,
    rarity_name: null,
    variant_label: "Normal",
    variant_available: true,
    language_code: i % 2 === 0 ? null : "pt-BR",
    ownership: i % 5 === 0 ? "SAME_VARIANT_LANGUAGE" : "NONE",
    image_path_pt: i % 3 === 0 ? `cards/${i}-pt.webp` : null,
    image_path_en: `cards/${i}-en.webp`,
    wished_at: "2026-11-02T10:00:00Z",
    total_count: total,
    ...over,
  };
}

test("leitura estrita: linha fora do contrato invalida a página (nunca reinterpreta)", () => {
  assert.equal(parseWishlistReportPage([row(0, 1)])?.entries.length, 1);
  assert.equal(parseWishlistReportPage([row(0, 1)])?.entries[0]?.imagePath, "cards/0-pt.webp");
  assert.equal(parseWishlistReportPage([row(1, 1)])?.entries[0]?.imagePath, "cards/1-en.webp");
  for (const bad of [
    { ownership: "MAYBE" },
    { ownership: null },
    { language_code: "português" },
    { variant_available: null },
    { entry_id: "x" },
    { card_variant_id: null },
    { wished_at: null },
    { total_count: "abc" },
  ]) {
    assert.equal(parseWishlistReportPage([row(0, 1, bad)]), null, JSON.stringify(bad));
  }
  assert.equal(parseWishlistReportPage({}), null);
  assert.deepEqual(parseWishlistReportPage([]), { entries: [], totalCount: 0 });
});

type Call = { fn: string; args: Record<string, unknown> };
function fakeClient(total: number, calls: Call[], options: { failPricesFor?: string; failWishlist?: boolean } = {}) {
  let pricing = 0;
  let maxPricing = 0;
  return {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      if (fn === "get_my_wishlist_filtered") {
        if (options.failWishlist) return { data: null, error: { code: "XX000" } };
        const offset = Number(args.p_offset);
        const limit = Number(args.p_limit);
        const rows = Array.from({ length: Math.max(0, Math.min(limit, total - offset)) }, (_, k) => row(offset + k, total));
        return { data: rows, error: null };
      }
      if (fn === "get_card_variants_pricing_summary") {
        pricing += 1;
        maxPricing = Math.max(maxPricing, pricing);
        await new Promise((resolve) => setTimeout(resolve, 3));
        pricing -= 1;
        const ids = args.p_card_variant_ids as string[];
        if (options.failPricesFor && ids.includes(options.failPricesFor)) return { data: null, error: { code: "42501" } };
        return {
          data: ids.map((id) => ({ card_variant_id: id, has_pricing: true, brl_amount: 2, price_basis: "VARIANT", price_origin: "AUTOMATIC", fx_status: "CONVERTED" })),
          error: null,
        };
      }
      return { data: null, error: { code: "PGRST202" } };
    },
    maxPricing: () => maxPricing,
  };
}

test("leitura: lista inteira em SET_NUMBER, páginas de 100, preços de variantes distintas em blocos de 100 (máx. 2), sem identificar o titular", async () => {
  const calls: Call[] = [];
  const client = fakeClient(250, calls);
  const load = await getWishlistReport(client as never, new Date("2026-11-06T12:00:00Z"), (path) => `https://img/${path}`);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  const r = load.data.report;
  assert.equal(r.complete, true);
  assert.equal(r.entryCount, 250);
  assert.equal(r.variantCount, 150);
  assert.equal(r.all.totalBrl, 300); // 150 variantes × R$ 2 — nunca 250 × R$ 2
  const pages = calls.filter((c) => c.fn === "get_my_wishlist_filtered");
  assert.equal(pages.length, Math.ceil(250 / WISHLIST_REPORT_PAGE));
  for (const page of pages) {
    assert.equal(page.args.p_sort, "SET_NUMBER");
    assert.equal(page.args.p_limit, 100);
    for (const key of ["p_search", "p_card_set_id", "p_rarity_id", "p_language", "p_ownership"]) assert.equal(page.args[key], null, key); // lista integral (G)
  }
  const priceCalls = calls.filter((c) => c.fn === "get_card_variants_pricing_summary");
  assert.deepEqual(priceCalls.map((c) => (c.args.p_card_variant_ids as string[]).length), [100, 50]);
  assert.ok(client.maxPricing() <= 2);
  // Dono = auth.uid() no banco: nenhum argumento identifica o titular ("p_ownership" é o filtro de posse, nulo).
  assert.ok(calls.every((c) => Object.keys(c.args).every((key) => !/user|owner_id|^p_owner$|profile/i.test(key))));
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), ["get_card_variants_pricing_summary", "get_my_wishlist_filtered"]); // sem escrita
  assert.equal(r.sets[0]?.lines[0]?.imageUrl, "https://img/cards/0-pt.webp");
});

test("leitura: falha de preço → relatório com Indisponível e incompleto; falha da lista → erro; vazia → pronta sem preços", async () => {
  const partial = await getWishlistReport(fakeClient(120, [], { failPricesFor: uuid(101) }) as never);
  assert.equal(partial.status, "ready");
  if (partial.status === "ready") {
    assert.equal(partial.data.report.incompleteReason, "prices_unavailable");
    assert.equal(partial.data.report.all.unavailable, 20); // ids 101..120 (bloco 2)
    assert.equal(partial.data.report.all.priced, 100);
  }
  assert.equal((await getWishlistReport(fakeClient(10, [], { failWishlist: true }) as never)).status, "error");
  const calls: Call[] = [];
  const empty = await getWishlistReport(fakeClient(0, calls) as never);
  assert.equal(empty.status, "ready");
  if (empty.status === "ready") {
    assert.equal(empty.data.report.entryCount, 0);
    assert.equal(empty.data.report.complete, true);
  }
  assert.equal(calls.filter((c) => c.fn === "get_card_variants_pricing_summary").length, 0);
});

test("teto de 5.000 desejos: lê até o teto e marca incompleto", async () => {
  const calls: Call[] = [];
  const load = await getWishlistReport(fakeClient(WISHLIST_REPORT_MAX + 30, calls) as never);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  assert.equal(load.data.report.entryCount, WISHLIST_REPORT_MAX);
  assert.equal(load.data.report.incompleteReason, "too_large");
  assert.equal(calls.filter((c) => c.fn === "get_my_wishlist_filtered").length, WISHLIST_REPORT_MAX / WISHLIST_REPORT_PAGE);
});

test("integração: 5º relatório do Meu acervo, folha institucional, impressão íntegra e sem SQL nova", () => {
  const entry = ACERVO_REPORT_CATALOG.find((e) => e.id === "wishlist");
  assert.equal(entry?.implemented, true);
  assert.equal(ACERVO_REPORT_CATALOG.filter((e) => e.implemented).map((e) => e.id).indexOf("wishlist"), 4);
  assert.equal(acervoReportMenuItems({ totalCopies: 0 }).find((i) => i.id === "wishlist")?.disabledReason, null);
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /if \(report === "wishlist"\) \{\s*return readWishlistReport\(\)/);
  assert.match(overlay, /incomplete: wishlistIncompleteText\(r\.data\.report\.incompleteReason\)/); // incompleto → impressão bloqueada pela casca
  const actions = read("../../app/colecoes/acervo/relatorios/actions.ts");
  assert.match(actions, /export async function readWishlistReport\(\)[\s\S]*if \(!user\) return \{ status: "error" \}/);
  const sheet = read("../../components/reports/wishlist-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  const thead = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.ok(thead.indexOf("{cabecalho}") < thead.indexOf("Indicadores da lista de desejos"));
  for (const label of ["Desejos", "Pendentes", "Card Sets", "Referência NM pendente"]) assert.match(thead, new RegExp(`label="${label}"`), label);
  for (const label of ["Número", "Carta", "Referência NM", "Situação no acervo", "Desejado em"]) assert.match(thead, new RegExp(`>\\s*${label}\\s*<`), label);
  assert.match(sheet, /breakInside: "avoid"/); // linhas indivisíveis
  assert.match(sheet, /loading=\{eagerImages \? "eager" : "lazy"\}/);
  assert.match(sheet, /saem na impressão como um quadro vazio/); // fallback explícito acima do teto de imagens imediatas
  assert.doesNotMatch(sheet, /print:hidden|aria-hidden="true" className="[^"]*hidden print/); // miniatura também na impressão
  assert.match(sheet, /Referência de toda a lista/);
  assert.doesNotMatch(sheet, /quantidade desejada|prioridade:|preço-alvo:|coleç(ão|ões) faltante/i);
  assert.doesNotMatch(sheet + read("./wishlist-report.ts") + read("./wishlist-report-queries.ts"), /\.from\("card_wishlist_entry"\)|\.insert\(|\.update\(|\.delete\(|\.upsert\(/);
  assert.ok(logs.length >= 0);
});
