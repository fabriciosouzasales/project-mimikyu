import type { SupabaseClient } from "@supabase/supabase-js";
import { chunkVariantIds, parseVariantPrices } from "../pricing/variant-pricing.ts";
import type { InventorySummaryInput } from "./acervo-reports.ts";
import { type SetSummaryReport, buildSetSummaryReport } from "./acervo-set-summary.ts";
import { type AcervoValueReport, buildAcervoValueReport } from "./acervo-value.ts";
import { type SetInventoryItemInput, type SetInventoryPriceInput, type SetInventoryReport, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { issuedAtLabel } from "./collection-checklist.ts";

/** Página máxima da 5159 (1..96). */
export const SET_INVENTORY_PAGE = 96;
/** Teto dos relatórios por Card Set: grupos Card Variant + idioma (≈ 53 páginas). Acima: incompleto, nunca truncado em silêncio. */
export const SET_INVENTORY_MAX_ITEMS = 5000;
/** Leituras simultâneas das páginas da 5159 (leves). */
const PAGE_PARALLEL = 6;
/**
 * Leituras simultâneas da 3989 (preços, até 100 variantes cada). Duas, não seis: chamadas
 * paralelas disputam a mesma CPU do banco e cada uma pode estourar o statement_timeout de 8 s
 * do papel authenticated (57014) — diagnóstico R1-B INVENTORY PERFORMANCE DIAGNOSIS-01.
 */
export const PRICE_PARALLEL = 2;

export type SetInventoryReportData = { report: SetInventoryReport; issuedAt: string };
export type SetInventoryReportLoad = { status: "ready"; data: SetInventoryReportData } | { status: "error" };
export type SetSummaryReportData = { report: SetSummaryReport; issuedAt: string };
export type SetSummaryReportLoad = { status: "ready"; data: SetSummaryReportData } | { status: "error" };
export type AcervoValueReportData = { report: AcervoValueReport; issuedAt: string };
export type AcervoValueReportLoad = { status: "ready"; data: AcervoValueReportData } | { status: "error" };

type Rpc = Pick<SupabaseClient, "rpc">;

function n(value: unknown): number | null {
  const v = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/** Linha da 5159 → item; `null` = fora do contrato. */
function toItem(row: Record<string, unknown>): SetInventoryItemInput | null {
  const copies = n(row.copies_count);
  const id = str(row.card_variant_id);
  const language = str(row.language_code);
  const name = str(row.card_name);
  const setCode = str(row.card_set_code);
  if (!id || !language || !name || !setCode || copies === null || copies < 1) return null;
  return {
    cardVariantId: id.toLowerCase(),
    languageCode: language,
    cardName: name,
    collectorNumber: str(row.collector_number),
    collectorTotal: n(row.collector_total),
    cardSetCode: setCode,
    cardSetName: str(row.card_set_name) ?? setCode,
    variantLabel: str(row.variant_label),
    isDefaultVariant: row.is_default_variant === true,
    copies,
  };
}

type RpcResult = { data: unknown; error: { code?: string } | null };

async function inBatches(tasks: (() => PromiseLike<RpcResult>)[], limit: number): Promise<RpcResult[]> {
  const out: RpcResult[] = [];
  for (let i = 0; i < tasks.length; i += limit) out.push(...(await Promise.all(tasks.slice(i, i + limit).map((t) => t()))));
  return out;
}

const itemsParams = (offset: number) => ({
  p_search: null,
  p_card_set_code: null,
  p_language_code: null,
  p_collection_id: null,
  p_without_collection: false,
  p_sort: "SET_NUMBER",
  p_limit: SET_INVENTORY_PAGE,
  p_offset: offset,
});

type ItemsRead =
  | { status: "ok"; summary: InventorySummaryInput; items: SetInventoryItemInput[]; complete: boolean; total: number }
  | { status: "error"; stage: string; code?: string };

/**
 * Leitura comum aos dois inventários por Card Set: 5160 (resumo) + 5159 em `SET_NUMBER`, todas
 * as páginas (a 1ª dá o total; as demais em paralelo), sem filtro de coleção. Só o titular
 * (`auth.uid()` no banco; nenhum identificador vindo do cliente; nenhuma escrita).
 */
async function readInventoryItems(supabase: Rpc): Promise<ItemsRead> {
  const [summaryRes, firstRes] = await Promise.all([
    supabase.rpc("get_my_inventory_summary"),
    supabase.rpc("get_my_inventory_items", itemsParams(0)),
  ]);
  if (summaryRes.error) return { status: "error", stage: "summary", code: summaryRes.error.code };
  if (firstRes.error) return { status: "error", stage: "items", code: firstRes.error.code };
  const s = Array.isArray(summaryRes.data) ? (summaryRes.data[0] as Record<string, unknown> | undefined) : undefined;
  const summary = s
    ? { totalCopies: n(s.total_copies), distinctItems: n(s.distinct_items), distinctSets: n(s.distinct_sets), duplicateCopies: n(s.duplicate_copies) }
    : null;
  if (!summary || summary.totalCopies === null || summary.distinctItems === null || summary.distinctSets === null || summary.duplicateCopies === null) {
    return { status: "error", stage: "summary" };
  }
  if (!Array.isArray(firstRes.data)) return { status: "error", stage: "items" };

  const firstRows = firstRes.data as Record<string, unknown>[];
  const total = firstRows.length === 0 ? 0 : n(firstRows[0]?.total_count);
  if (total === null) return { status: "error", stage: "items" };
  const readable = Math.min(total, SET_INVENTORY_MAX_ITEMS);
  const offsets: number[] = [];
  for (let offset = SET_INVENTORY_PAGE; offset < readable; offset += SET_INVENTORY_PAGE) offsets.push(offset);
  const pages = await inBatches(offsets.map((offset) => () => supabase.rpc("get_my_inventory_items", itemsParams(offset))), PAGE_PARALLEL);
  const rows: Record<string, unknown>[] = [...firstRows];
  for (const page of pages) {
    if (page.error || !Array.isArray(page.data)) return { status: "error", stage: "items", code: page.error?.code };
    rows.push(...(page.data as Record<string, unknown>[]));
  }
  const items: SetInventoryItemInput[] = [];
  for (const row of rows.slice(0, readable)) {
    const item = toItem(row);
    if (!item) return { status: "error", stage: "items" };
    items.push(item);
  }
  return {
    status: "ok",
    summary: {
      totalCopies: summary.totalCopies,
      distinctItems: summary.distinctItems,
      distinctSets: summary.distinctSets,
      duplicateCopies: summary.duplicateCopies,
    },
    items,
    complete: total <= SET_INVENTORY_MAX_ITEMS,
    total,
  };
}

type InventoryRead = { status: "ok"; report: SetInventoryReport; total: number } | { status: "error"; stage: string; code?: string };

/**
 * Leitura e cálculo do inventário por Card Set com preços: leitura comum + 3989
 * (`get_card_variants_pricing_summary`, referência NM por variante, blocos de 100, no máximo
 * `PRICE_PARALLEL` chamadas simultâneas). Compartilhada pelo relatório 02 (detalhado) e pelo 03
 * (Valor estimado total) — uma única regra monetária (`buildSetInventoryReport`, centavos).
 * Falha em qualquer leitura ou resposta fora do contrato → erro (nunca resultado parcial).
 */
async function readPricedInventory(supabase: Rpc): Promise<InventoryRead> {
  const read = await readInventoryItems(supabase);
  if (read.status === "error") return read;
  const { items } = read;

  const prices = new Map<string, SetInventoryPriceInput>();
  const chunks = chunkVariantIds(items.map((item) => item.cardVariantId));
  const priceReads = await inBatches(chunks.map((chunk) => () => supabase.rpc("get_card_variants_pricing_summary", { p_card_variant_ids: chunk })), PRICE_PARALLEL);
  for (const priceRead of priceReads) {
    if (priceRead.error) return { status: "error", stage: "prices", code: priceRead.error.code };
    const parsed = parseVariantPrices(priceRead.data);
    if (!parsed) return { status: "error", stage: "prices" };
    for (const [id, price] of parsed) {
      if (price.hasPricing && price.brlAmount !== null && price.brlAmount > 0) {
        prices.set(id, { brl: price.brlAmount, basis: price.basis, observedAt: price.observedAt });
      }
    }
  }

  const report = buildSetInventoryReport({ summary: read.summary, items, prices, itemsComplete: read.complete });
  return { status: "ok", report, total: read.total };
}

/** V1-14 R1-B — relatório 02, "Inventário detalhado por Card Set". */
export async function getSetInventoryReport(supabase: Rpc, now: Date = new Date()): Promise<SetInventoryReportLoad> {
  const startedAt = Date.now();
  const read = await readPricedInventory(supabase);
  if (read.status === "error") {
    console.error("[reports] inventário detalhado por Card Set falhou", { stage: read.stage, code: read.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const { report } = read;
  if (!report.complete) console.warn("[reports] inventário detalhado por Card Set incompleto", { reason: report.incompleteReason, total: read.total });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}

/**
 * V1-14 R1-C — relatório 03, "Valor estimado total": a mesma leitura e regra monetária do 02,
 * projetada por Card Set (`buildAcervoValueReport`). Sem SQL nova; só o titular.
 */
export async function getAcervoValueReport(supabase: Rpc, now: Date = new Date()): Promise<AcervoValueReportLoad> {
  const startedAt = Date.now();
  const read = await readPricedInventory(supabase);
  if (read.status === "error") {
    console.error("[reports] valor estimado total falhou", { stage: read.stage, code: read.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const report = buildAcervoValueReport(read.report);
  if (!report.complete) console.warn("[reports] valor estimado total incompleto", { reason: report.incompleteReason, total: read.total });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}

/**
 * V1-14 R1-B — relatório 01, "Inventário resumido por Card Set": só a leitura comum (sem preços).
 * Mesmas garantias de titularidade e de conferência com o resumo canônico.
 */
export async function getSetSummaryReport(supabase: Rpc, now: Date = new Date()): Promise<SetSummaryReportLoad> {
  const startedAt = Date.now();
  const read = await readInventoryItems(supabase);
  if (read.status === "error") {
    console.error("[reports] inventário resumido por Card Set falhou", { stage: read.stage, code: read.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const report = buildSetSummaryReport({ summary: read.summary, items: read.items, itemsComplete: read.complete });
  if (!report.complete) console.warn("[reports] inventário resumido por Card Set incompleto", { reason: report.incompleteReason, total: read.total });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
