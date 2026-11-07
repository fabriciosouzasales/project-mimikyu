import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import { type Rpc, inventoryPriceInput, readInventoryItems } from "./acervo-set-inventory-queries.ts";
import { type SetInventoryPriceInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import {
  type DuplicateLocation,
  type DuplicateLocationGroup,
  type DuplicateLocationsInput,
  type DuplicatesReport,
  buildDuplicatesReport,
  duplicateGroupKey,
} from "./duplicates.ts";

export type DuplicatesReportData = { report: DuplicatesReport; issuedAt: string };
export type DuplicatesReportLoad = { status: "ready"; data: DuplicatesReportData } | { status: "error" };

/** Variantes por chamada da 5354 (a função aceita até 500; 250 mantém cada chamada curta). */
export const LOCATIONS_CHUNK = 250;
const LOCATIONS_RPC = "get_my_inventory_group_locations";

type RpcResponse = { data: unknown; error: { code?: string } | null };
type AnyRpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<RpcResponse> };

// ---------------------------------------------------------------------------
// 5354 — localização física por grupo variante + idioma
// ---------------------------------------------------------------------------

const isUuid = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v);
const isCount = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v >= 0;

function parseLocation(raw: unknown): DuplicateLocation | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const containerId = r.storage_container_id === null ? null : isUuid(r.storage_container_id) ? r.storage_container_id.toLowerCase() : undefined;
  if (containerId === undefined || !isCount(r.copies) || r.copies < 1 || !Array.isArray(r.pages)) return null;
  if (!r.pages.every((p) => isCount(p) && p > 0)) return null;
  const text = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v : null);
  return { containerId, name: text(r.name), kindLabel: text(r.kind_label), copies: r.copies, pages: [...(r.pages as number[])].sort((a, b) => a - b) };
}

/** Linhas da 5354 → grupos; `null` = fora do contrato (bloco tratado como falha, nunca meio-lido). */
export function parseGroupLocations(data: unknown): Map<string, DuplicateLocationGroup> | null {
  if (!Array.isArray(data)) return null;
  const groups = new Map<string, DuplicateLocationGroup>();
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (!isUuid(row.card_variant_id) || typeof row.language_code !== "string" || !isCount(row.copies) || !Array.isArray(row.locations)) return null;
    const locations: DuplicateLocation[] = [];
    for (const item of row.locations) {
      const location = parseLocation(item);
      if (!location) return null;
      locations.push(location);
    }
    const key = duplicateGroupKey(row.card_variant_id, row.language_code);
    if (groups.has(key)) return null; // uma linha por grupo — duplicada = fora do contrato
    groups.set(key, { copies: row.copies, locations });
  }
  return groups;
}

/**
 * Localizações dos grupos repetidos: 5354 em blocos de `LOCATIONS_CHUNK` variantes, um bloco por
 * vez (leitura leve; não disputa a CPU do banco com os preços). Um bloco com erro ou fora do
 * contrato → leitura inteira indisponível (relatório incompleto, impressão bloqueada).
 */
export async function readGroupLocations(supabase: AnyRpc, cardVariantIds: readonly string[]): Promise<DuplicateLocationsInput> {
  const ids = [...new Set(cardVariantIds.map((id) => id.toLowerCase()))];
  const groups = new Map<string, DuplicateLocationGroup>();
  for (let i = 0; i < ids.length; i += LOCATIONS_CHUNK) {
    const res = await supabase.rpc(LOCATIONS_RPC, { p_card_variant_ids: ids.slice(i, i + LOCATIONS_CHUNK) });
    const parsed = res.error ? null : parseGroupLocations(res.data);
    if (!parsed) {
      console.warn("[reports] cartas repetidas: localização indisponível", { code: res.error?.code ?? "BAD_SHAPE", block: i / LOCATIONS_CHUNK + 1 });
      return { status: "unavailable" };
    }
    for (const [key, group] of parsed) groups.set(key, group);
  }
  return { status: "ok", groups };
}

// ---------------------------------------------------------------------------
// Instrumentação (sem dados do titular: só tempos e contagens)
// ---------------------------------------------------------------------------

type Span = { first: number; last: number; calls: number };

/** Mesmo cliente, medindo o intervalo [1º início, último fim] e o número de chamadas por RPC. */
export function timedRpc<T extends AnyRpc>(supabase: T, origin: number, spans: Map<string, Span>, clock: () => number = Date.now): T {
  return {
    rpc: (fn: string, args?: Record<string, unknown>) => {
      const start = clock() - origin;
      return Promise.resolve(args === undefined ? supabase.rpc(fn) : supabase.rpc(fn, args)).finally(() => {
        const end = clock() - origin;
        const span = spans.get(fn);
        if (span) {
          span.first = Math.min(span.first, start);
          span.last = Math.max(span.last, end);
          span.calls += 1;
        } else spans.set(fn, { first: start, last: end, calls: 1 });
      });
    },
  } as unknown as T;
}

const spanMs = (span: Span | undefined) => (span ? span.last - span.first : null);

/**
 * V1-14 R1-G — "Cartas repetidas": a leitura compartilhada do acervo (5160 + 5159 em `SET_NUMBER`,
 * todas as páginas, teto 5.000 grupos); depois, EM PARALELO, 3989 por variante distinta via
 * `readVariantPrices` (Pricing Resilience, concorrência homologada inalterada) e 5354 só para as
 * variantes dos grupos repetidos (localização física). Mesma regra de referência
 * (`inventoryPriceInput`) e mesmo cálculo monetário (`buildSetInventoryReport`) do Inventário
 * detalhado, do Valor estimado total e do Top 10. Só o titular (`auth.uid()` no banco; nenhum
 * identificador do cliente); somente leitura. Falha do acervo → erro; falha de preço ou de
 * localização → relatório incompleto (impressão bloqueada). Tempos por etapa no log do servidor.
 */
export async function getDuplicatesReport(
  supabase: Rpc,
  now: Date = new Date(),
  imageUrl?: (path: string) => string | null,
): Promise<DuplicatesReportLoad> {
  const origin = Date.now();
  const spans = new Map<string, Span>();
  const client = timedRpc(supabase as unknown as AnyRpc, origin, spans);
  const read = await readInventoryItems(client as unknown as Rpc);
  if (read.status === "error") {
    console.error("[reports] cartas repetidas falhou", { stage: read.stage, code: read.code ?? "BAD_SHAPE", ms: Date.now() - origin });
    return { status: "error" };
  }
  const repeatedIds = read.items.filter((item) => item.copies >= 2).map((item) => item.cardVariantId);
  const [priceRead, locations] = await Promise.all([
    readVariantPrices(client, read.items.map((item) => item.cardVariantId)),
    repeatedIds.length > 0 ? readGroupLocations(client, repeatedIds) : Promise.resolve<DuplicateLocationsInput>({ status: "ok", groups: new Map() }),
  ]);
  const buildStart = Date.now();
  const prices = new Map<string, SetInventoryPriceInput>();
  for (const [id, price] of priceRead.prices) {
    const input = inventoryPriceInput(price);
    if (input) prices.set(id, input);
  }
  const inventory = buildSetInventoryReport({ summary: read.summary, items: read.items, prices, itemsComplete: read.complete });
  const report = buildDuplicatesReport({ inventory, prices, unavailable: new Set(priceRead.unavailableIds), locations, now: now.getTime(), imageUrl });
  const end = Date.now();
  console.info("[reports] cartas repetidas", {
    ms: {
      total: end - origin,
      summary: spanMs(spans.get("get_my_inventory_summary")),
      inventory: spanMs(spans.get("get_my_inventory_items")),
      prices: spanMs(spans.get("get_card_variants_pricing_summary")),
      locations: spanMs(spans.get(LOCATIONS_RPC)),
      build: end - buildStart,
    },
    calls: {
      inventory: spans.get("get_my_inventory_items")?.calls ?? 0,
      prices: spans.get("get_card_variants_pricing_summary")?.calls ?? 0,
      locations: spans.get(LOCATIONS_RPC)?.calls ?? 0,
    },
    groups: read.total,
    repeated: report.repeatedGroups,
    complete: report.complete,
  });
  if (!report.complete) console.warn("[reports] cartas repetidas incompleto", { reason: report.incompleteReason, total: read.total, prices: priceRead.status, locations: locations.status, locationMismatches: report.locationMismatches });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
