import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import { type Rpc, inventoryPriceInput, readInventoryItems } from "./acervo-set-inventory-queries.ts";
import { type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import { type DistributionReport, type RarityCatalogEntry, type RarityCatalogInput, buildDistributionReport } from "./distribution.ts";
import { timedRpc } from "./duplicates-queries.ts";

export type DistributionReportData = { report: DistributionReport; issuedAt: string };
export type DistributionReportLoad = { status: "ready"; data: DistributionReportData } | { status: "error" };

type RpcResponse = { data: unknown; error: { code?: string } | null };
type AnyRpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<RpcResponse> };
type Span = { first: number; last: number; calls: number };

const RARITY_RPC = "get_rarity_catalog";

/** Linhas da 5355 → catálogo; `null` = fora do contrato (code duplicado, nome em branco, ordem inválida). */
export function parseRarityCatalog(data: unknown): RarityCatalogEntry[] | null {
  if (!Array.isArray(data)) return null;
  const out: RarityCatalogEntry[] = [];
  const seen = new Set<string>();
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const { code, name, symbol_code: symbolCode, display_order: displayOrder } = r;
    if (typeof code !== "string" || !/^[A-Z0-9][A-Z0-9_]*$/.test(code) || seen.has(code)) return null;
    if (typeof name !== "string" || name.trim() === "" || typeof symbolCode !== "string") return null;
    if (typeof displayOrder !== "number" || !Number.isInteger(displayOrder) || displayOrder <= 0) return null;
    seen.add(code);
    out.push({ code, name, symbolCode, displayOrder });
  }
  return out;
}

/** 5355: uma chamada; erro ou resposta fora do contrato → catálogo indisponível (provisório). */
export async function readRarityCatalog(supabase: AnyRpc): Promise<RarityCatalogInput> {
  const res = await supabase.rpc(RARITY_RPC);
  const entries = res.error ? null : parseRarityCatalog(res.data);
  if (!entries) {
    console.warn("[reports] distribuição: catálogo de raridades indisponível", { code: res.error?.code ?? "BAD_SHAPE" });
    return { status: "unavailable" };
  }
  return { status: "ok", entries };
}

const spanMs = (span: Span | undefined) => (span ? span.last - span.first : null);

/**
 * V1-14 R1-H — "Distribuição por Set, raridade e idioma": 5160 + 5159 (leitura compartilhada do
 * acervo, todas as páginas, teto 5.000 grupos) EM PARALELO com a 5355 (catálogo de raridades);
 * depois 3989 via `readVariantPrices` (Pricing Resilience, concorrência homologada inalterada).
 * Mesma regra monetária do Valor estimado total (`inventoryPriceInput`, `buildSetInventoryReport`).
 * Sem 5354, sem miniaturas. Só o titular (`auth.uid()` no banco; nenhum identificador do cliente);
 * somente leitura. Falha do acervo → erro; falha da 5355 ou de preço → provisório (impressão
 * bloqueada). Tempos por etapa no log do servidor, sem dados do titular.
 */
export async function getDistributionReport(supabase: Rpc, now: Date = new Date()): Promise<DistributionReportLoad> {
  const origin = Date.now();
  const spans = new Map<string, Span>();
  const client = timedRpc(supabase as unknown as AnyRpc, origin, spans);
  const [read, rarities] = await Promise.all([readInventoryItems(client as unknown as Rpc), readRarityCatalog(client)]);
  if (read.status === "error") {
    console.error("[reports] distribuição falhou", { stage: read.stage, code: read.code ?? "BAD_SHAPE", ms: Date.now() - origin });
    return { status: "error" };
  }
  const priceRead = await readVariantPrices(client, read.items.map((item) => item.cardVariantId));
  const buildStart = Date.now();
  const prices = new Map<string, SetInventoryPriceInput>();
  for (const [id, price] of priceRead.prices) {
    const input = inventoryPriceInput(price);
    if (input) prices.set(id, input);
  }
  const inventory = buildSetInventoryReport({ summary: read.summary, items: read.items, prices, itemsComplete: read.complete });
  const report = buildDistributionReport({ inventory, unavailable: new Set(priceRead.unavailableIds), rarities });
  const end = Date.now();
  console.info("[reports] distribuição", {
    ms: {
      total: end - origin,
      summary: spanMs(spans.get("get_my_inventory_summary")),
      inventory: spanMs(spans.get("get_my_inventory_items")),
      rarities: spanMs(spans.get(RARITY_RPC)),
      prices: spanMs(spans.get("get_card_variants_pricing_summary")),
      build: end - buildStart,
    },
    calls: { inventory: spans.get("get_my_inventory_items")?.calls ?? 0, prices: spans.get("get_card_variants_pricing_summary")?.calls ?? 0, rarities: spans.get(RARITY_RPC)?.calls ?? 0 },
    groups: read.total,
    complete: report.complete,
  });
  if (!report.complete) console.warn("[reports] distribuição incompleta", { reason: report.incompleteReason, total: read.total, prices: priceRead.status, rarities: rarities.status });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
