import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import { type Rpc, inventoryPriceInput, readInventoryItems } from "./acervo-set-inventory-queries.ts";
import { type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import { type TopCardsReport, buildTopCardsReport } from "./top-cards.ts";

export type TopCardsReportData = { report: TopCardsReport; issuedAt: string };
export type TopCardsReportLoad = { status: "ready"; data: TopCardsReportData } | { status: "error" };

/**
 * V1-14 R1-F — "Top 10 cartas mais valiosas": a leitura compartilhada do acervo (5160 + 5159 em
 * `SET_NUMBER`, todas as páginas, teto 5.000 grupos) + 3989 por variante distinta via
 * `readVariantPrices` (Pricing Resilience: blocos de 100, no máximo 2 simultâneos, uma nova
 * tentativa para 57014). Mesma regra de referência (`inventoryPriceInput`) e mesmo cálculo
 * monetário (`buildSetInventoryReport`) do Inventário detalhado e do Valor estimado total. Só o
 * titular (`auth.uid()` no banco; nenhum identificador do cliente); somente leitura; sem SQL nova.
 * Falha do acervo → erro; falha de preço → ranking provisório (impressão bloqueada).
 */
export async function getTopCardsReport(
  supabase: Rpc,
  now: Date = new Date(),
  imageUrl?: (path: string) => string | null,
): Promise<TopCardsReportLoad> {
  const startedAt = Date.now();
  const read = await readInventoryItems(supabase);
  if (read.status === "error") {
    console.error("[reports] top 10 falhou", { stage: read.stage, code: read.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const priceRead = await readVariantPrices(supabase, read.items.map((item) => item.cardVariantId));
  const prices = new Map<string, SetInventoryPriceInput>();
  for (const [id, price] of priceRead.prices) {
    const input = inventoryPriceInput(price);
    if (input) prices.set(id, input);
  }
  const inventory = buildSetInventoryReport({ summary: read.summary, items: read.items, prices, itemsComplete: read.complete });
  const report = buildTopCardsReport({ inventory, prices, unavailable: new Set(priceRead.unavailableIds), now: now.getTime(), imageUrl });
  if (!report.complete) console.warn("[reports] top 10 incompleto", { reason: report.incompleteReason, total: read.total, prices: priceRead.status });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
