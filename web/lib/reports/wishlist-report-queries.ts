import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import { NO_WISHLIST_FILTERS, wishlistFilterArgs } from "../wishlist/wishlist.ts";
import { type Rpc, inBatches } from "./acervo-set-inventory-queries.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import {
  WISHLIST_REPORT_MAX,
  WISHLIST_REPORT_PAGE,
  type WishReportEntryInput,
  type WishlistReport,
  buildWishlistReport,
  parseWishlistReportPage,
} from "./wishlist-report.ts";

export type WishlistReportData = { report: WishlistReport; issuedAt: string };
export type WishlistReportLoad = { status: "ready"; data: WishlistReportData } | { status: "error" };

/** Páginas da 5350/5351 lidas em paralelo depois da primeira. */
const PAGE_PARALLEL = 4;

/**
 * Argumentos da lista INTEIRA (decisão G: os filtros da página não se aplicam), na ordem
 * "Set e número" da 5351 — os mesmos da página Lista de desejos, via `wishlistFilterArgs`.
 * `cardSetId` (R2-C): só o Card Set de uma coleção JÁ AUTORIZADA no servidor; R1-E passa `null`.
 */
function pageArgs(offset: number, cardSetId: string | null) {
  return { p_limit: WISHLIST_REPORT_PAGE, p_offset: offset, ...wishlistFilterArgs({ ...NO_WISHLIST_FILTERS, cardSetId, sort: "set" }) };
}

type Fail = { status: "error"; stage: string; code?: string };

export type WishesRead = { status: "ok"; entries: WishReportEntryInput[]; totalCount: number; withinLimit: boolean } | Fail;

/**
 * Todos os desejos do titular (ou só os de um Card Set — R2-C): a 1ª página dá o total; as demais
 * em paralelo, até o teto. Mesma leitura, páginas, teto e validação estrita da R1-E.
 */
export async function readAllWishes(supabase: Rpc, cardSetId: string | null = null): Promise<WishesRead> {
  const first = await supabase.rpc("get_my_wishlist_filtered", pageArgs(0, cardSetId));
  if (first.error) return { status: "error", stage: "wishlist", code: first.error.code };
  const firstPage = parseWishlistReportPage(first.data);
  if (!firstPage) return { status: "error", stage: "wishlist" };
  const totalCount = firstPage.entries.length === 0 ? 0 : firstPage.totalCount;
  const readable = Math.min(totalCount, WISHLIST_REPORT_MAX);
  const offsets: number[] = [];
  for (let offset = WISHLIST_REPORT_PAGE; offset < readable; offset += WISHLIST_REPORT_PAGE) offsets.push(offset);
  const pages = await inBatches(
    offsets.map((offset) => () => supabase.rpc("get_my_wishlist_filtered", pageArgs(offset, cardSetId))),
    PAGE_PARALLEL,
  );
  const entries = [...firstPage.entries];
  for (const page of pages) {
    if (page.error) return { status: "error", stage: "wishlist", code: page.error.code };
    const parsed = parseWishlistReportPage(page.data);
    if (!parsed) return { status: "error", stage: "wishlist" };
    entries.push(...parsed.entries);
  }
  return { status: "ok", entries: entries.slice(0, readable), totalCount, withinLimit: totalCount <= WISHLIST_REPORT_MAX };
}

/**
 * V1-14 R1-E — "Minha Lista de Desejos": desejos (5350/5351) + referência NM por variante
 * distinta (3989 via `readVariantPrices`: blocos de 100, no máximo 2 simultâneos, uma nova
 * tentativa para 57014). Só o titular (as RPCs resolvem o dono por `auth.uid()`; nenhum
 * identificador do cliente); sem SQL nova; somente leitura. Falha na lista → erro; falha de
 * preço → relatório com "Indisponível" nas variantes afetadas, totais parciais e impressão
 * bloqueada (nunca zero, nunca "sem cotação").
 */
export async function getWishlistReport(
  supabase: Rpc,
  now: Date = new Date(),
  imageUrl?: (path: string) => string | null,
): Promise<WishlistReportLoad> {
  const startedAt = Date.now();
  const wishes = await readAllWishes(supabase);
  if (wishes.status === "error") {
    console.error("[reports] lista de desejos falhou", { stage: wishes.stage, code: wishes.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const variantIds = [...new Set(wishes.entries.map((entry) => entry.cardVariantId))];
  const prices = await readVariantPrices(supabase, variantIds);
  const report = buildWishlistReport({
    entries: wishes.entries,
    totalCount: wishes.totalCount,
    withinLimit: wishes.withinLimit,
    prices: prices.prices,
    unavailable: new Set(prices.unavailableIds),
    imageUrl,
  });
  if (!report.complete) console.warn("[reports] lista de desejos incompleta", { reason: report.incompleteReason, total: wishes.totalCount, prices: prices.status });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
