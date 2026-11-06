// V1-14 R1-B — Relatório 02 do Meu acervo, "Inventário detalhado por Card Set": regras (linha
// por variante + idioma, totais por exemplar, subtotais, cobertura), leitura com cliente falso
// (acervo inteiro, todas as páginas, teto, isolamento) e checagens estáticas da folha.
// Executar: node --experimental-strip-types --test lib/reports/acervo-set-inventory.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { PRICE_PARALLEL, SET_INVENTORY_MAX_ITEMS, SET_INVENTORY_PAGE, getSetInventoryReport } from "./acervo-set-inventory-queries.ts";
import { buildSetInventoryReport, coverageText, setInventoryIncompleteText, setInventorySummaryLine } from "./acervo-set-inventory.ts";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const id = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

const V = (n: number) => id(n);
const item = (variant: number, set: string, number: string, copies: number, extra: Partial<Record<string, unknown>> = {}) => ({
  cardVariantId: V(variant),
  languageCode: "en",
  cardName: `Carta ${variant}`,
  collectorNumber: number,
  collectorTotal: 100,
  cardSetCode: set,
  cardSetName: `Set ${set}`,
  variantLabel: null,
  isDefaultVariant: true,
  copies,
  ...extra,
});
const price = (brl: number, basis: "VARIANT" | "CARD_FALLBACK" = "VARIANT", observedAt = "2026-11-04T00:00:00Z") => ({ brl, basis, observedAt });

test("inventário por Card Set: linha por variante + idioma, totais por exemplar e subtotais por Set", () => {
  // Ordem de entrada = ordem canônica da 5159 (SET_NUMBER); o relatório não reordena.
  const items = [
    item(1, "SV2", "2", 1), // uma cópia
    item(1, "SV2", "2", 2, { languageCode: "pt-BR" }), // mesma variante, outro idioma → outra linha
    item(2, "SV2", "2", 1, { variantLabel: "Holofoil", isDefaultVariant: false }), // outra variante da mesma carta
    item(3, "SV2", "10", 3), // sem cotação
    item(4, "SV1", "1", 4),
  ];
  const report = buildSetInventoryReport({
    summary: { totalCopies: 11, distinctItems: 5, distinctSets: 2, duplicateCopies: 6 },
    items,
    prices: new Map([[V(1), price(1.1)], [V(2), price(10.05, "CARD_FALLBACK", "2026-11-01T00:00:00Z")], [V(4), price(0.35)]]),
    itemsComplete: true,
  });
  assert.equal(report.complete, true);
  assert.deepEqual(report.sets.map((g) => g.code), ["SV2", "SV1"]); // ordem preservada
  const sv2 = report.sets[0]!;
  assert.deepEqual(sv2.lines.map((l) => [l.collectorNumber, l.languageCode, l.copies, l.unitBrl, l.totalBrl]), [
    ["2", "en", 1, 1.1, 1.1],
    ["2", "pt-BR", 2, 1.1, 2.2],
    ["2", "en", 1, 10.05, 10.05],
    ["10", "en", 3, null, null], // nunca zero
  ]);
  assert.equal(sv2.copies, 7);
  assert.equal(sv2.pricedCopies, 4);
  assert.equal(sv2.unpricedCopies, 3);
  assert.equal(sv2.subtotalBrl, 13.35);
  assert.equal(report.sets[1]!.subtotalBrl, 1.4);
  assert.equal(report.totalBrl, 14.75); // centavos exatos, sem erro de ponto flutuante
  assert.equal(report.pricedCopies, 8);
  assert.equal(report.unpricedCopies, 3);
  assert.equal(report.sets.reduce((sum, g) => sum + g.copies, 0), report.totalCopies); // = total do acervo
  assert.equal(report.priceObservedMin, "2026-11-01T00:00:00Z");
  assert.equal(coverageText(report), "72% dos exemplares com preço");
  assert.equal(setInventorySummaryLine(report), "11 exemplares · 5 diferentes · 2 Card Sets");
});

test("inventário por Card Set: Set sem nenhuma cotação, acervo sem cotação, mismatch e teto", () => {
  const none = buildSetInventoryReport({ summary: { totalCopies: 2, distinctItems: 1, distinctSets: 1, duplicateCopies: 1 }, items: [item(9, "A", "1", 2)], prices: new Map(), itemsComplete: true });
  assert.equal(none.totalBrl, null);
  assert.equal(none.sets[0]!.subtotalBrl, null);
  assert.equal(coverageText(none), "0% dos exemplares com preço");
  // Referência ≤ 0 não é cotação.
  const zero = buildSetInventoryReport({ summary: { totalCopies: 1, distinctItems: 1, distinctSets: 1, duplicateCopies: 0 }, items: [item(9, "A", "1", 1)], prices: new Map([[V(9), price(0)]]), itemsComplete: true });
  assert.equal(zero.totalBrl, null);
  const mismatch = buildSetInventoryReport({ summary: { totalCopies: 5, distinctItems: 1, distinctSets: 1, duplicateCopies: 0 }, items: [item(9, "A", "1", 2)], prices: new Map(), itemsComplete: true });
  assert.equal(mismatch.incompleteReason, "mismatch");
  assert.ok(setInventoryIncompleteText("mismatch"));
  const big = buildSetInventoryReport({ summary: { totalCopies: 2, distinctItems: 1, distinctSets: 1, duplicateCopies: 1 }, items: [item(9, "A", "1", 2)], prices: new Map(), itemsComplete: false });
  assert.equal(big.incompleteReason, "too_large");
  const empty = buildSetInventoryReport({ summary: { totalCopies: 0, distinctItems: 0, distinctSets: 0, duplicateCopies: 0 }, items: [], prices: new Map(), itemsComplete: true });
  assert.equal(empty.complete, true);
  assert.equal(setInventoryIncompleteText(null), null);
});

type Call = { fn: string; args: unknown };
function fakeClient(handler: (fn: string, args: Record<string, unknown>) => { data: unknown; error: { code?: string } | null }, calls: Call[]) {
  return {
    rpc: (fn: string, args?: Record<string, unknown>) => {
      calls.push({ fn, args: args ?? null });
      return Promise.resolve(handler(fn, args ?? {}));
    },
  } as never;
}

/** Acervo falso com `groups` linhas (2 cópias cada), em 3 Sets; variante par = cotada a R$ 1,25. */
function fakeAcervo(groups: number, calls: Call[], broken?: string) {
  const all = Array.from({ length: groups }, (_, i) => ({
    card_variant_id: V(i + 1),
    language_code: "en",
    card_name: `Carta ${i + 1}`,
    collector_number: String((i % 50) + 1),
    collector_total: 50,
    card_set_code: `S${Math.floor(i / 50) % 3}`,
    card_set_name: "Set",
    is_default_variant: true,
    variant_label: null,
    copies_count: 2,
    total_count: groups,
    total_copies: groups * 2,
  }));
  return fakeClient((fn, args) => {
    if (fn === broken) return { data: null, error: { code: "XX000" } };
    if (fn === "get_my_inventory_summary") return { data: [{ total_copies: groups * 2, distinct_items: groups, distinct_sets: 3, duplicate_copies: groups }], error: null };
    if (fn === "get_my_inventory_items") {
      const offset = Number(args.p_offset);
      return { data: all.slice(offset, offset + Number(args.p_limit)), error: null };
    }
    if (fn === "get_card_variants_pricing_summary") {
      const ids = args.p_card_variant_ids as string[];
      return {
        data: ids.map((vid) => {
          const even = Number.parseInt(vid.slice(-12), 16) % 2 === 0;
          return { card_variant_id: vid, has_pricing: even, brl_amount: even ? 1.25 : null, price_basis: even ? "VARIANT" : null, observed_at: "2026-11-04T00:00:00Z" };
        }),
        error: null,
      };
    }
    throw new Error(`RPC inesperada ${fn}`);
  }, calls);
}

test("leitura: acervo inteiro por SET_NUMBER, sem filtro de coleção, todas as páginas e preços em blocos de 100", async () => {
  const calls: Call[] = [];
  const load = await getSetInventoryReport(fakeAcervo(250, calls), new Date("2026-11-06T12:00:00Z"));
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  const r = load.data.report;
  assert.equal(r.complete, true);
  assert.equal(r.sets.reduce((n, g) => n + g.lines.length, 0), 250);
  assert.equal(r.totalCopies, 500);
  assert.equal(r.pricedCopies, 250); // metade das variantes cotadas, 2 cópias cada
  assert.equal(r.totalBrl, 312.5);
  const pages = calls.filter((c) => c.fn === "get_my_inventory_items").map((c) => c.args as Record<string, unknown>);
  assert.equal(pages.length, Math.ceil(250 / SET_INVENTORY_PAGE));
  for (const page of pages) {
    assert.equal(page.p_sort, "SET_NUMBER");
    assert.equal(page.p_collection_id, null); // não depende da alocação
    assert.equal(page.p_without_collection, false);
  }
  const priceCalls = calls.filter((c) => c.fn === "get_card_variants_pricing_summary");
  assert.equal(priceCalls.length, 3);
  assert.ok(priceCalls.every((c) => ((c.args as Record<string, unknown>).p_card_variant_ids as string[]).length <= 100));
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), ["get_card_variants_pricing_summary", "get_my_inventory_items", "get_my_inventory_summary"]);
  assert.ok(calls.every((c) => !JSON.stringify(c.args ?? {}).match(/user|owner/i))); // dono = auth.uid() no banco
});

test("leitura: muitas linhas e teto; falhas → erro", async () => {
  const many = await getSetInventoryReport(fakeAcervo(SET_INVENTORY_MAX_ITEMS + 10, []));
  assert.equal(many.status, "ready");
  if (many.status === "ready") {
    assert.equal(many.data.report.incompleteReason, "too_large"); // nunca truncado em silêncio
    assert.equal(many.data.report.sets.reduce((n, g) => n + g.lines.length, 0), SET_INVENTORY_MAX_ITEMS);
  }
  for (const broken of ["get_my_inventory_summary", "get_my_inventory_items", "get_card_variants_pricing_summary"]) {
    assert.equal((await getSetInventoryReport(fakeAcervo(10, [], broken))).status, "error", broken);
  }
  const empty = await getSetInventoryReport(fakeAcervo(0, []));
  assert.equal(empty.status, "ready");
});

test("integração: folha própria por Card Set, ação e sobreposição dedicadas", () => {
  assert.match(read("../../app/colecoes/acervo/relatorios/actions.ts"), /export async function readSetInventoryReport\(\)/);
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /report === "inventory-sets"/);
  assert.match(overlay, /<AcervoSetInventorySheet /);
  const sheet = read("../../components/reports/acervo-set-inventory-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  assert.match(sheet, /acervoReport\("inventory-sets"\)/);
  // Ordem: cabeçalho → indicadores → títulos das colunas (no <thead>, repetem em toda folha) → grupos.
  const thead = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.ok(thead.indexOf("{cabecalho}") < thead.indexOf("Indicadores do inventário"));
  assert.ok(thead.indexOf("Indicadores do inventário") < thead.indexOf(">Número<"));
  assert.match(thead, /<DataTableHeadRow className="border-neutral-200 text-neutral-500">/);
  for (const label of ["Qtd\\.", "Unitário NM", "Total"]) assert.match(thead, new RegExp(`align="center"[^>]*>\\s*${label}\\s*<`), label);
  // Um <tbody> por Card Set; título não fica sozinho no pé da folha; subtotal e total.
  assert.match(sheet, /<tbody style=\{\{ breakInside: set\.lines\.length <= KEEP_TOGETHER_LINES \? "avoid" : "auto" \}\}>/);
  assert.match(sheet, /breakAfter: "avoid"/);
  assert.match(sheet, /Subtotal \{set\.code\}/);
  assert.match(sheet, /Total do acervo/);
  assert.match(sheet, /Sem cotação/);
  assert.doesNotMatch(sheet, /Sem coleção|Onde estão os exemplares|kindLabel/); // nada de coleções no Acervo
});

test("preços: no máximo duas leituras da 3983 simultâneas; resultado idêntico ao sequencial", async () => {
  assert.equal(PRICE_PARALLEL, 2);
  let inFlight = 0;
  let peak = 0;
  let calls = 0;
  const base = fakeAcervo(1301, []); // ~ acervo real: 1.301 variantes → 14 lotes de preço
  const client = {
    rpc: (fn: string, args?: Record<string, unknown>) => {
      const inner = (base as { rpc: (f: string, a?: Record<string, unknown>) => Promise<unknown> }).rpc(fn, args);
      if (fn !== "get_card_variants_pricing_summary") return inner;
      calls += 1;
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      return new Promise((resolve) => setTimeout(() => { inFlight -= 1; resolve(inner); }, 1));
    },
  } as never;
  const load = await getSetInventoryReport(client);
  assert.equal(load.status, "ready");
  assert.equal(calls, Math.ceil(1301 / 100));
  assert.equal(peak, 2);
  const sequential = await getSetInventoryReport(fakeAcervo(1301, []));
  if (load.status === "ready" && sequential.status === "ready") {
    assert.equal(load.data.report.totalBrl, sequential.data.report.totalBrl);
    assert.equal(load.data.report.pricedCopies, sequential.data.report.pricedCopies);
  }
});
