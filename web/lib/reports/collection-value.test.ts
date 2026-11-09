// V1-14 R2-E — "Valor estimado dos exemplares alocados" (D7 v1.59 §4m, D1–D12): E1 (leituras e
// preparação) + E2 (construtor financeiro puro).
// Executar: node --experimental-strip-types --test lib/reports/collection-value.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { type SetInventoryItemInput, type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import {
  COLLECTION_VALUE_MAX_GROUPS,
  type CollectionValueItemInput,
  type CollectionValueReadCheck,
  buildCollectionValueReport,
  collectionValueAllocatedText,
  collectionValueCoverageText,
  collectionValueIncompleteText,
  collectionValueNotes,
  collectionValuePriceFlags,
  collectionValueTotalText,
  collectionValueUnpricedText,
} from "./collection-value.ts";
import { prepareCollectionValueReport } from "./collection-value-queries.ts";

console.error = () => {};
console.warn = () => {};
console.info = () => {};

const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const COLLECTION = uuid(9001);
const NOW = Date.parse("2026-11-07T12:00:00Z");

// ---------------------------------------------------------------------------
// E2 — construtor puro

function item(n: number, over: Partial<CollectionValueItemInput> = {}): CollectionValueItemInput {
  return {
    cardVariantId: uuid(n),
    languageCode: "en",
    languageName: "Inglês",
    cardName: `Carta ${n}`,
    collectorNumber: String(n),
    collectorTotal: 200,
    cardSetCode: "ME5.5",
    cardSetName: "Celebração",
    variantLabel: null,
    isDefaultVariant: true,
    copies: 1,
    imagePath: `cards/${n}.webp`,
    order: n,
    ...over,
  };
}

const price = (brl: number, over: Partial<SetInventoryPriceInput> = {}): SetInventoryPriceInput => ({ brl, basis: "VARIANT", observedAt: "2026-11-05T00:00:00Z", ...over });

function checkOf(items: readonly CollectionValueItemInput[], over: Partial<CollectionValueReadCheck> = {}): CollectionValueReadCheck {
  return { totalCount: items.length, totalCopies: items.reduce((s, i) => s + i.copies, 0), duplicate: false, inconsistentPages: false, ...over };
}

function build(items: CollectionValueItemInput[], prices: Record<number, SetInventoryPriceInput>, options: { unavailable?: number[]; check?: Partial<CollectionValueReadCheck>; collectionCopies?: number } = {}) {
  const map = new Map(Object.entries(prices).map(([n, p]) => [uuid(Number(n)), p]));
  const copies = items.reduce((s, i) => s + i.copies, 0);
  return buildCollectionValueReport({
    items,
    prices: map,
    unavailable: new Set((options.unavailable ?? []).map(uuid)),
    read: checkOf(items, options.check),
    collectionCopies: options.collectionCopies ?? copies,
    now: NOW,
    imageUrl: (path) => `https://img/${path}`,
  });
}

test("cálculo em centavos: quantidade × unitário arredondado por unidade (regra da R1-B/R1-C)", () => {
  const items = [item(1, { copies: 3 }), item(2, { copies: 2 }), item(3)];
  const prices = { 1: price(10.005), 2: price(0.1), 3: price(1234.56) };
  const report = build(items, prices);
  const line1 = report.lines.find((l) => l.cardVariantId === uuid(1));
  assert.equal(line1?.unitCents, Math.round(10.005 * 100));
  assert.equal(line1?.lineCents, Math.round(10.005 * 100) * 3);
  assert.equal(report.totalCents, Math.round(10.005 * 100) * 3 + 10 * 2 + 123456);
  // Mesma conta do Inventário detalhado (R1-B) para o mesmo conjunto e preços.
  const inventory = buildSetInventoryReport({
    summary: { totalCopies: 6, distinctItems: 3, distinctSets: 1, duplicateCopies: 3 },
    items: items as SetInventoryItemInput[],
    prices: new Map(Object.entries(prices).map(([n, p]) => [uuid(Number(n)), p])),
    itemsComplete: true,
  });
  assert.equal(Math.round((inventory.totalBrl ?? 0) * 100), report.totalCents);
});

test("A/B/C: cotada, sem cotação legítima e indisponível nunca se confundem; C nunca entra em B nem vale zero", () => {
  const items = [item(1, { copies: 2 }), item(2, { copies: 3 }), item(3, { copies: 4 }), item(4)];
  const report = build(items, { 1: price(5), 4: price(1) }, { unavailable: [3] });
  const state = (n: number) => report.lines.find((l) => l.cardVariantId === uuid(n))?.state;
  assert.equal(state(1), "priced");
  assert.equal(state(2), "unpriced");
  assert.equal(state(3), "unavailable");
  assert.deepEqual([report.pricedCopies, report.pricedGroups], [3, 2]);
  assert.deepEqual([report.unpricedCopies, report.unpricedGroups], [3, 1]); // só B
  assert.deepEqual([report.unavailableCopies, report.unavailableGroups], [4, 1]);
  assert.equal(report.totalCents, 1100);
  assert.equal(report.provisional, true);
  assert.equal(report.printable, false);
  assert.equal(collectionValueTotalText(report).replace(/\s/g, " "), "R$ 11,00 (parcial)");
  assert.equal(report.lines.find((l) => l.state === "unavailable")?.lineCents, null);
  // Indisponível vence mesmo se houver preço no mapa (o bloco falhou; nada lido dele é confiável).
  const both = build([item(7)], { 7: price(9) }, { unavailable: [7] });
  assert.equal(both.lines[0]?.state, "unavailable");
  assert.equal(both.totalCents, null);
});

test("sem nenhuma cotação válida: nunca R$ 0 — 'Sem cotação' (B) ou 'Indisponível' (C)", () => {
  const onlyB = build([item(1), item(2)], {});
  assert.equal(onlyB.totalCents, null);
  assert.equal(collectionValueTotalText(onlyB), "Sem cotação");
  assert.equal(onlyB.printable, true); // ausência legítima não bloqueia
  const onlyC = build([item(1), item(2)], {}, { unavailable: [1, 2] });
  assert.equal(collectionValueTotalText(onlyC), "Indisponível");
  assert.equal(onlyC.printable, false);
  const mixed = build([item(1), item(2)], {}, { unavailable: [1] });
  assert.equal(collectionValueTotalText(mixed), "Indisponível");
});

test("KPIs (D8): valor + cobertura em exemplares, exemplares alocados com grupos, sem cotação só B", () => {
  const report = build([item(1, { copies: 2 }), item(2, { copies: 1 }), item(3, { copies: 5 })], { 1: price(3) }, { unavailable: [3] });
  assert.equal(collectionValueCoverageText(report), "2 de 8 exemplares cotados");
  assert.deepEqual(collectionValueAllocatedText(report), { value: "8", note: "3 itens (variante e idioma)" });
  assert.deepEqual(collectionValueUnpricedText(report), { value: "1", note: "exemplar · 1 item" });
  assert.equal(collectionValueCoverageText({ pricedCopies: 1, copies: 1 }), "1 de 1 exemplar cotado");
});

test("ordem (D9): A por valor decrescente, empate pela ordem do Set e id; B e C intercalados no fim pela ordem do Set", () => {
  const items = [
    item(1, { order: 0 }), // B
    item(2, { order: 1, copies: 2 }), // A 2 × 5,00 = 10,00
    item(3, { order: 2 }), // C
    item(4, { order: 3 }), // A 10,00
    item(5, { order: 4 }), // A 50,00
    item(6, { order: 5 }), // B
  ];
  const report = build(items, { 2: price(5), 4: price(10), 5: price(50) }, { unavailable: [3] });
  assert.deepEqual(
    report.lines.map((l) => l.cardVariantId),
    [uuid(5), uuid(2), uuid(4), uuid(1), uuid(3), uuid(6)],
  );
  // Determinismo: a ordem não depende da ordem de entrada.
  const shuffled = build([...items].reverse(), { 2: price(5), 4: price(10), 5: price(50) }, { unavailable: [3] });
  assert.deepEqual(shuffled.lines.map((l) => l.cardVariantId), report.lines.map((l) => l.cardVariantId));
});

test("sinais (D4): preço geral da carta, desatualizada (> 14 dias) com data; sem 'Referência internacional'", () => {
  const items = [item(1, { languageCode: "pt-BR" }), item(2), item(3), item(4)];
  const report = build(items, {
    1: price(1),
    2: price(1, { basis: "CARD_FALLBACK" }),
    3: price(1, { observedAt: "2026-10-01T00:00:00Z" }),
    4: price(1, { basis: null, observedAt: null }),
  });
  const flags = (n: number) => collectionValuePriceFlags(report.lines.find((l) => l.cardVariantId === uuid(n)) as never);
  assert.deepEqual(flags(1), []);
  assert.deepEqual(flags(2), ["Preço geral da carta"]);
  assert.deepEqual(flags(3), ["Desatualizada"]);
  assert.equal(report.lines.find((l) => l.cardVariantId === uuid(3))?.observedAt, "2026-10-01T00:00:00Z");
  assert.deepEqual(flags(4), ["Preço geral da carta"]); // sem data: não afirma "desatualizada"
  assert.ok(!JSON.stringify(report).includes("internacional"));
});

test("integridade (D11): teto, repetição, páginas inconsistentes, totais e copies_count da coleção", () => {
  const items = [item(1, { copies: 2 }), item(2)];
  assert.equal(build(items, {}).complete, true);
  assert.equal(build(items, {}, { check: { totalCount: COLLECTION_VALUE_MAX_GROUPS + 1 } }).incompleteReason, "too_large");
  assert.equal(build([item(1), item(1, { order: 5 })], {}).incompleteReason, "duplicate");
  assert.equal(build(items, {}, { check: { duplicate: true } }).incompleteReason, "duplicate");
  assert.equal(build(items, {}, { check: { inconsistentPages: true } }).incompleteReason, "inconsistent_pages");
  assert.equal(build(items, {}, { check: { totalCount: 3 } }).incompleteReason, "total_mismatch");
  assert.equal(build(items, {}, { check: { totalCopies: 4 } }).incompleteReason, "total_mismatch");
  assert.equal(build(items, {}, { collectionCopies: 5 }).incompleteReason, "collection_mismatch");
  const bad = build(items, {}, { collectionCopies: 5 });
  assert.equal(bad.printable, false);
  assert.ok(collectionValueIncompleteText(bad.incompleteReason)?.includes("impressão fica indisponível"));
  assert.equal(collectionValueIncompleteText(null), null);
  // Coleção vazia e coerente → estado vazio, imprimível.
  const empty = build([], {});
  assert.equal(empty.state, "empty");
  assert.equal(empty.totalCents, null);
});

test("notas metodológicas (D12; D5 só no Master Set) e período das observações", () => {
  const set = collectionValueNotes({ masterSet: false, observedFrom: null, observedTo: null }).join(" ");
  assert.ok(set.includes("NM") && set.includes("condição física") && set.includes("revenda") && set.includes("completude"));
  assert.ok(!set.includes("Master Set"));
  const master = collectionValueNotes({ masterSet: true, observedFrom: "2026-10-01T00:00:00Z", observedTo: "2026-11-05T00:00:00Z" }).join(" ");
  assert.ok(master.includes("inclusive os que não atendem às posições atuais"));
  assert.ok(master.includes("PTAX"));
  const report = build([item(1), item(2)], { 1: price(1, { observedAt: "2026-10-01T00:00:00Z" }), 2: price(1, { observedAt: "2026-11-05T00:00:00Z" }) });
  assert.deepEqual([report.observedFrom, report.observedTo], ["2026-10-01T00:00:00Z", "2026-11-05T00:00:00Z"]);
});

test("propriedade: Σ coleções ≤ Acervo para o mesmo conjunto de exemplares e as mesmas referências", () => {
  let seed = 7;
  const rand = (max: number) => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed % max;
  };
  for (let round = 0; round < 40; round += 1) {
    const groups = 1 + rand(60);
    const prices = new Map<string, SetInventoryPriceInput>();
    const acervo: SetInventoryItemInput[] = [];
    const perCollection = new Map<number, CollectionValueItemInput[]>();
    for (let g = 0; g < groups; g += 1) {
      const id = uuid(round * 1000 + g);
      if (rand(4) !== 0) prices.set(id, price(rand(50_000) / 100 + 0.01));
      const copies = 1 + rand(6);
      acervo.push({ ...item(g), cardVariantId: id, copies });
      // Alocação 0..1 por exemplar (5040): cada exemplar vai para no máximo uma de 3 coleções.
      const split = new Map<number, number>();
      for (let c = 0; c < copies; c += 1) {
        const target = rand(4); // 3 = sem coleção
        if (target < 3) split.set(target, (split.get(target) ?? 0) + 1);
      }
      for (const [collection, n] of split) {
        const list = perCollection.get(collection) ?? [];
        list.push({ ...item(g), cardVariantId: id, copies: n, order: list.length });
        perCollection.set(collection, list);
      }
    }
    const acervoTotal = buildSetInventoryReport({
      summary: { totalCopies: acervo.reduce((s, i) => s + i.copies, 0), distinctItems: groups, distinctSets: 1, duplicateCopies: 0 },
      items: acervo,
      prices,
      itemsComplete: true,
    }).totalBrl;
    let sum = 0;
    for (const list of perCollection.values()) {
      const report = buildCollectionValueReport({ items: list, prices, unavailable: new Set(), read: checkOf(list), collectionCopies: list.reduce((s, i) => s + i.copies, 0), now: NOW });
      sum += report.totalCents ?? 0;
    }
    assert.ok(sum <= Math.round((acervoTotal ?? 0) * 100), `rodada ${round}: ${sum} > acervo`);
  }
});

// ---------------------------------------------------------------------------
// E1 — leituras (cliente falso: registra chamadas, ordem e concorrência)

type Group = { variant: number; lang?: string; copies: number };

function fakeClient(
  groups: Group[],
  options: {
    policy?: string;
    collection?: "missing" | "error";
    copiesCount?: number;
    failItems?: boolean;
    failPricesFor?: number;
    priced?: (variant: number) => number | null;
    duplicateOnPage2?: boolean;
    totalChangesOnPage2?: boolean;
    totalCountOverride?: number;
    shortPage?: boolean;
  } = {},
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const order: string[] = [];
  let inFlight5159 = 0;
  let peak5159 = 0;
  let inFlightPrices = 0;
  let peakPrices = 0;
  const copiesTotal = groups.reduce((s, g) => s + g.copies, 0);
  const client = {
    storage: { from: () => ({ createSignedUrls: async () => ({ data: [], error: null }) }) },
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      order.push(`${fn}:start`);
      if (fn === "get_my_inventory_items") {
        inFlight5159 += 1;
        peak5159 = Math.max(peak5159, inFlight5159);
      }
      if (fn === "get_card_variants_pricing_summary") {
        inFlightPrices += 1;
        peakPrices = Math.max(peakPrices, inFlightPrices);
      }
      await new Promise((resolve) => setTimeout(resolve, 2));
      order.push(`${fn}:end`);
      if (fn === "get_my_inventory_items") inFlight5159 -= 1;
      if (fn === "get_card_variants_pricing_summary") inFlightPrices -= 1;

      if (fn === "get_my_collection") {
        if (options.collection === "error") return { data: null, error: { code: "57014" } };
        if (options.collection === "missing" || args.p_collection_id !== COLLECTION) return { data: [], error: null };
        return {
          data: [
            {
              collection_id: COLLECTION,
              name: "Minha ME5.5",
              mode: "REFERENCE_BASED",
              completion_policy: options.policy ?? "STANDARD_SET",
              lifecycle_status: "ACTIVE",
              card_set_id: uuid(7000),
              card_set_code: "ME5.5",
              card_set_name: "Celebração",
              card_set_logo_path: null,
              total_positions: 158,
              satisfied_positions: 100,
              is_complete: false,
              copies_count: options.copiesCount ?? copiesTotal,
              cover_image_path: null,
              created_at: "2026-10-01T00:00:00Z",
              total_count: 1,
            },
          ],
          error: null,
        };
      }
      if (fn === "get_my_inventory_items") {
        if (options.failItems) return { data: null, error: { code: "57014" } };
        // O "banco": só os exemplares alocados à coleção pedida, se for a do titular.
        const mine = args.p_collection_id === COLLECTION ? groups : [];
        const offset = Number(args.p_offset);
        const limit = Number(args.p_limit);
        let page = mine.slice(offset, offset + limit);
        if (options.shortPage && offset === 0) page = page.slice(0, limit - 1);
        if (options.duplicateOnPage2 && offset > 0) page = [mine[0] as Group, ...page.slice(1)];
        const totalCount = (options.totalCountOverride ?? mine.length) + (options.totalChangesOnPage2 && offset > 0 ? 1 : 0);
        return {
          data: page.map((g) => ({
            card_variant_id: uuid(g.variant),
            language_code: g.lang ?? "en",
            language_name: "Inglês",
            card_name: `Carta ${g.variant}`,
            collector_number: String(g.variant),
            collector_total: 200,
            card_set_code: "ME5.5",
            card_set_name: "Celebração",
            is_default_variant: true,
            variant_label: null,
            copies_count: g.copies,
            last_added_at: "2026-11-01T00:00:00Z",
            image_path: `cards/${g.variant}.webp`,
            total_count: totalCount,
            copies_owned: g.copies + 1,
            total_copies: copiesTotal,
          })),
          error: null,
        };
      }
      if (fn === "get_card_variants_pricing_summary") {
        const ids = args.p_card_variant_ids as string[];
        if (options.failPricesFor !== undefined && ids.includes(uuid(options.failPricesFor))) return { data: null, error: { code: "42501" } };
        return {
          data: ids.map((id) => {
            const v = Number.parseInt(id.slice(-12), 16);
            const brl = options.priced ? options.priced(v) : v;
            return { card_variant_id: id, has_pricing: brl !== null && brl > 0, brl_amount: brl, price_basis: "VARIANT", price_origin: "AUTOMATIC", fx_status: "CONVERTED", observed_at: "2026-11-01T00:00:00Z" };
          }),
          error: null,
        };
      }
      return { data: null, error: { code: "PGRST202" } };
    },
  };
  return { client, calls, order, peak5159: () => peak5159, peakPrices: () => peakPrices };
}

const groupsOf = (n: number, copies = 1): Group[] => Array.from({ length: n }, (_, i) => ({ variant: i + 1, copies }));

test("E1: ordem 5332 → 5159 (só a coleção autorizada, SET_NUMBER, 96 por página, em sequência) → 3989 (máx. 2)", async () => {
  const ok = fakeClient(groupsOf(250, 2));
  const result = await prepareCollectionValueReport(ok.client as never, COLLECTION, (p) => `https://img/${p}`, new Date(NOW));
  assert.equal(result.status, "ready");
  assert.equal(ok.calls[0]?.fn, "get_my_collection");
  assert.ok(ok.order.indexOf("get_my_collection:end") < ok.order.indexOf("get_my_inventory_items:start"));
  const pages = ok.calls.filter((c) => c.fn === "get_my_inventory_items");
  assert.deepEqual(pages.map((c) => c.args.p_offset), [0, 96, 192]);
  for (const page of pages) {
    assert.equal(page.args.p_collection_id, COLLECTION); // exclusivamente a coleção autorizada
    assert.equal(page.args.p_sort, "SET_NUMBER");
    assert.equal(page.args.p_limit, 96);
    assert.equal(page.args.p_without_collection, false);
  }
  assert.equal(ok.peak5159(), 1); // páginas em sequência
  assert.ok(ok.order.lastIndexOf("get_my_inventory_items:end") < ok.order.indexOf("get_card_variants_pricing_summary:start"));
  const priceCalls = ok.calls.filter((c) => c.fn === "get_card_variants_pricing_summary");
  assert.deepEqual(priceCalls.map((c) => (c.args.p_card_variant_ids as string[]).length), [100, 100, 50]); // uma vez por variante distinta
  assert.ok(ok.peakPrices() <= 2);
  assert.ok(ok.calls.every((c) => Object.keys(c.args).every((key) => !/user|owner|profile/i.test(key))));
  assert.deepEqual([...new Set(ok.calls.map((c) => c.fn))].sort(), ["get_card_variants_pricing_summary", "get_my_collection", "get_my_inventory_items"]); // sem escrita
  if (result.status === "ready") {
    const { report } = result.data;
    assert.equal(report.groups, 250);
    assert.equal(report.copies, 500);
    assert.equal(report.complete, true);
    assert.equal(report.lines[0]?.cardVariantId, uuid(250)); // maior referência primeiro
    assert.equal(report.lines[0]?.imageUrl, "https://img/cards/250.webp");
    assert.equal(result.data.kind, "STANDARD_SET");
  }
});

test("E1: coleção alheia/inexistente, modalidade não suportada e falha da coleção → zero leituras financeiras", async () => {
  // F2-1 (D7 §4q): Pokédex (REFERENCE_POSITION) e Coleção livre (NONE) passaram a ser suportadas — ver o teste F2-1 abaixo.
  for (const [options, expected] of [
    [{ collection: "missing" as const }, "not_found"],
    [{ collection: "error" as const }, "error"],
    [{ policy: "UNKNOWN_POLICY" }, "unavailable"],
  ] as const) {
    const fake = fakeClient(groupsOf(5), options);
    const result = await prepareCollectionValueReport(fake.client as never, COLLECTION);
    assert.equal(result.status, expected);
    assert.deepEqual(fake.calls.map((c) => c.fn), ["get_my_collection"]);
  }
});

test("E1: Master Set suportado; todos os grupos alocados entram (sem leitura de posições nem da 5196)", async () => {
  const fake = fakeClient([{ variant: 1, copies: 1 }, { variant: 2, copies: 3 }], { policy: "MASTER_SET" });
  const result = await prepareCollectionValueReport(fake.client as never, COLLECTION, undefined, new Date(NOW));
  assert.equal(result.status, "ready");
  if (result.status === "ready") {
    assert.equal(result.data.kind, "MASTER_SET");
    assert.equal(result.data.report.copies, 4);
    assert.equal(result.data.report.totalCents, 100 * 1 + 200 * 3);
  }
  assert.ok(!fake.calls.some((c) => /master_set|positions/.test(c.fn)));
});

test("E1: coleção vazia → estado vazio, sem 5159 nem preços", async () => {
  const fake = fakeClient([], { copiesCount: 0 });
  const result = await prepareCollectionValueReport(fake.client as never, COLLECTION);
  assert.equal(result.status, "ready");
  if (result.status === "ready") assert.equal(result.data.report.state, "empty");
  assert.deepEqual(fake.calls.map((c) => c.fn), ["get_my_collection"]);
});

test("E1: divergências observáveis → incompleto (nunca truncado em silêncio)", async () => {
  const cases: [Parameters<typeof fakeClient>[1], string][] = [
    [{ duplicateOnPage2: true }, "duplicate"],
    [{ totalChangesOnPage2: true }, "inconsistent_pages"],
    [{ shortPage: true }, "inconsistent_pages"],
    [{ copiesCount: 999 }, "collection_mismatch"],
  ];
  for (const [options, reason] of cases) {
    const fake = fakeClient(groupsOf(150), options);
    const result = await prepareCollectionValueReport(fake.client as never, COLLECTION);
    assert.equal(result.status, "ready", reason);
    if (result.status === "ready") {
      assert.equal(result.data.report.incompleteReason, reason);
      assert.equal(result.data.report.printable, false);
    }
  }
  // 5332 com alocações, 5159 sem nenhuma (mudança entre as leituras) → incompleto, não vazio.
  const gone = fakeClient([], { copiesCount: 3 });
  const goneResult = await prepareCollectionValueReport(gone.client as never, COLLECTION);
  if (goneResult.status === "ready") {
    assert.equal(goneResult.data.report.state, "ready");
    assert.equal(goneResult.data.report.incompleteReason, "collection_mismatch");
  }
});

test("E1: acima de 5.000 grupos → incompleto sem ler o resto nem preços", async () => {
  const fake = fakeClient(groupsOf(10), { totalCountOverride: COLLECTION_VALUE_MAX_GROUPS + 1 });
  const result = await prepareCollectionValueReport(fake.client as never, COLLECTION);
  assert.equal(result.status, "ready");
  if (result.status === "ready") assert.equal(result.data.report.incompleteReason, "too_large");
  assert.equal(fake.calls.filter((c) => c.fn === "get_my_inventory_items").length, 1);
  assert.equal(fake.calls.filter((c) => c.fn === "get_card_variants_pricing_summary").length, 0);
});

test("E1: falha da 5159 → erro; falha de um bloco de preço → provisório com o restante preservado; sem cotação ≠ falha", async () => {
  assert.equal((await prepareCollectionValueReport(fakeClient(groupsOf(5), { failItems: true }).client as never, COLLECTION)).status, "error");

  const partial = await prepareCollectionValueReport(fakeClient(groupsOf(150), { failPricesFor: 120 }).client as never, COLLECTION, undefined, new Date(NOW));
  assert.equal(partial.status, "ready");
  if (partial.status === "ready") {
    const r = partial.data.report;
    assert.equal(r.provisional, true);
    assert.equal(r.unavailableGroups, 50); // 2º bloco (101..150)
    assert.equal(r.unpricedGroups, 0);
    assert.equal(r.pricedGroups, 100);
    assert.equal(r.printable, false);
    assert.ok(collectionValueTotalText(r).endsWith("(parcial)"));
  }

  const unpriced = await prepareCollectionValueReport(fakeClient(groupsOf(4), { priced: (v) => (v % 2 === 0 ? v : null) }).client as never, COLLECTION, undefined, new Date(NOW));
  if (unpriced.status === "ready") {
    const r = unpriced.data.report;
    assert.equal(r.provisional, false);
    assert.deepEqual([r.pricedGroups, r.unpricedGroups, r.unavailableGroups], [2, 2, 0]);
    assert.equal(r.printable, true);
  }
});

test("F2-1: Pokédex e Coleção livre — mesma base (só exemplares ALOCADOS a esta coleção), mesmo cálculo, sem leitura de posições", async () => {
  for (const [policy, kind] of [["REFERENCE_POSITION", "POKEDEX"], ["NONE", "FREE"]] as const) {
    const fake = fakeClient([{ variant: 1, copies: 2 }, { variant: 2, copies: 1 }], { policy });
    const result = await prepareCollectionValueReport(fake.client as never, COLLECTION, undefined, new Date(NOW));
    assert.equal(result.status, "ready", policy);
    if (result.status === "ready") {
      assert.equal(result.data.kind, kind);
      assert.equal(result.data.report.copies, 3, "exemplares, nunca espécies ou posições");
      assert.equal(result.data.report.totalCents, 100 * 2 + 200 * 1, "mesma regra financeira da R2-E");
    }
    const items = fake.calls.filter((c) => c.fn === "get_my_inventory_items");
    assert.ok(items.length > 0 && items.every((c) => c.args.p_collection_id === COLLECTION && c.args.p_without_collection === false), "só a coleção autorizada");
    assert.ok(!fake.calls.some((c) => /pokedex|positions|master_set/.test(c.fn)), "nenhuma leitura de espécies/posições");
    assert.deepEqual([...new Set(fake.calls.map((c) => c.fn))].sort(), ["get_card_variants_pricing_summary", "get_my_collection", "get_my_inventory_items"]);
  }
  const empty = fakeClient([], { policy: "NONE", copiesCount: 0 });
  const emptyResult = await prepareCollectionValueReport(empty.client as never, COLLECTION);
  assert.equal(emptyResult.status === "ready" ? emptyResult.data.report.state : null, "empty", "sem exemplares alocados → vazio, sem leituras financeiras");
  assert.deepEqual(empty.calls.map((c) => c.fn), ["get_my_collection"]);
  const partial = await prepareCollectionValueReport(fakeClient(groupsOf(150), { policy: "REFERENCE_POSITION", failPricesFor: 120 }).client as never, COLLECTION, undefined, new Date(NOW));
  assert.equal(partial.status === "ready" ? partial.data.report.provisional : null, true, "preço indisponível → provisório, como na R2-E");
});
