import { chunkIds } from "../favorites/card-favorites.ts";
import { PRICE_PARALLEL, type Rpc, inBatches, readInventoryItems } from "./acervo-set-inventory-queries.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import {
  FAVORITES_REPORT_MAX,
  FAVORITES_REPORT_PAGE,
  type FavoriteReportCardInput,
  type FavoritesReport,
  buildFavoritesReport,
  ownedCopiesByCard,
  parseCardReferenceRows,
  parseFavoriteReportPage,
} from "./favorites-report.ts";

export type FavoritesReportData = { report: FavoritesReport; issuedAt: string };
export type FavoritesReportLoad = { status: "ready"; data: FavoritesReportData } | { status: "error" };

/** Páginas da 5336 lidas em paralelo depois da primeira (leves, índice da PK). */
const PAGE_PARALLEL = 4;
/** Referência por carta: teto da `get_cards_pricing_summary` (3972). */
const PRICE_IDS_PER_CALL = 100;

type Fail = { status: "error"; stage: string; code?: string };

/**
 * Todas as favoritas ativas do titular (`get_my_favorite_cards`, 5336, `auth.uid()`), páginas de
 * 100: a 1ª dá o total; as demais em paralelo, até o teto de 5.000. Página fora do contrato → erro.
 */
async function readAllFavorites(supabase: Rpc): Promise<{ status: "ok"; cards: FavoriteReportCardInput[]; totalCount: number; withinLimit: boolean } | Fail> {
  const first = await supabase.rpc("get_my_favorite_cards", { p_limit: FAVORITES_REPORT_PAGE, p_offset: 0 });
  if (first.error) return { status: "error", stage: "favorites", code: first.error.code };
  const firstPage = parseFavoriteReportPage(first.data);
  if (!firstPage) return { status: "error", stage: "favorites" };
  const totalCount = firstPage.cards.length === 0 ? 0 : firstPage.totalCount;
  const readable = Math.min(totalCount, FAVORITES_REPORT_MAX);
  const offsets: number[] = [];
  for (let offset = FAVORITES_REPORT_PAGE; offset < readable; offset += FAVORITES_REPORT_PAGE) offsets.push(offset);
  const pages = await inBatches(
    offsets.map((offset) => () => supabase.rpc("get_my_favorite_cards", { p_limit: FAVORITES_REPORT_PAGE, p_offset: offset })),
    PAGE_PARALLEL,
  );
  const cards = [...firstPage.cards];
  for (const page of pages) {
    if (page.error) return { status: "error", stage: "favorites", code: page.error.code };
    const parsed = parseFavoriteReportPage(page.data);
    if (!parsed) return { status: "error", stage: "favorites" };
    cards.push(...parsed.cards);
  }
  return { status: "ok", cards: cards.slice(0, readable), totalCount, withinLimit: totalCount <= FAVORITES_REPORT_MAX };
}

/** Referência NM por carta (`get_cards_pricing_summary`), blocos de 100, no máximo 2 simultâneos. */
async function readReferences(supabase: Rpc, cardIds: readonly string[]): Promise<{ status: "ok"; references: Map<string, number> } | Fail> {
  const blocks = chunkIds(cardIds, PRICE_IDS_PER_CALL);
  const reads = await inBatches(blocks.map((block) => () => supabase.rpc("get_cards_pricing_summary", { p_card_ids: block })), PRICE_PARALLEL);
  const references = new Map<string, number>();
  for (const read of reads) {
    if (read.error) return { status: "error", stage: "prices", code: read.error.code };
    const parsed = parseCardReferenceRows(read.data);
    if (!parsed) return { status: "error", stage: "prices" };
    for (const [id, brl] of parsed) references.set(id, brl);
  }
  return { status: "ok", references };
}

/**
 * Exemplares por carta: a leitura do acervo já homologada (5160 + 5159, todas as páginas) e a
 * carta de cada variante (`get_my_card_favorites_by_variant`, 5336, blocos de 500, 2 simultâneos).
 * Custo adicional da posse: as páginas do acervo + ceil(variantes / 500) chamadas.
 */
async function readOwnedCopies(supabase: Rpc): Promise<{ status: "ok"; owned: Map<string, number>; complete: boolean } | Fail> {
  const inventory = await readInventoryItems(supabase);
  if (inventory.status === "error") return inventory;
  const copiesByVariant = new Map<string, number>();
  for (const item of inventory.items) copiesByVariant.set(item.cardVariantId, (copiesByVariant.get(item.cardVariantId) ?? 0) + item.copies);
  const variantIds = [...copiesByVariant.keys()];
  const reads = await inBatches(
    chunkIds(variantIds).map((block) => () => supabase.rpc("get_my_card_favorites_by_variant", { p_card_variant_ids: block })),
    PRICE_PARALLEL,
  );
  const variantToCard = new Map<string, string>();
  for (const read of reads) {
    if (read.error || !Array.isArray(read.data)) return { status: "error", stage: "ownership", code: read.error?.code };
    for (const raw of read.data as Record<string, unknown>[]) {
      const variantId = typeof raw?.card_variant_id === "string" ? raw.card_variant_id.toLowerCase() : null;
      const cardId = typeof raw?.card_id === "string" ? raw.card_id.toLowerCase() : null;
      if (!variantId || !cardId) return { status: "error", stage: "ownership" };
      variantToCard.set(variantId, cardId);
    }
  }
  const owned = ownedCopiesByCard(
    [...copiesByVariant].map(([cardVariantId, copies]) => ({ cardVariantId, copies })),
    variantToCard,
  );
  if (!owned) return { status: "error", stage: "ownership" };
  return { status: "ok", owned, complete: inventory.complete };
}

/**
 * V1-14 R1-D — "Minhas favoritas": favoritas (5336) + referência por carta (pricing summary) +
 * posse (acervo + variante→carta). Favoritas e acervo em paralelo; preços depois das favoritas.
 * Só o titular (todas resolvem o dono por `auth.uid()`; nenhum identificador do cliente); sem SQL
 * nova; somente leitura. Falha em qualquer leitura → erro (nunca relatório parcial como inteiro).
 */
export async function getFavoritesReport(
  supabase: Rpc,
  now: Date = new Date(),
  /** URL pública da miniatura (bucket `card-front`); só a tela usa. */
  imageUrl?: (path: string) => string | null,
): Promise<FavoritesReportLoad> {
  const startedAt = Date.now();
  const fail = (stage: string, code?: string) => {
    console.error("[reports] minhas favoritas falhou", { stage, code: code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" } as const;
  };

  const favorites = await readAllFavorites(supabase);
  if (favorites.status === "error") return fail(favorites.stage, favorites.code);
  if (favorites.cards.length === 0) {
    const report = buildFavoritesReport({ cards: [], totalCount: favorites.totalCount, references: new Map(), ownedCopies: new Map(), withinLimit: true, ownershipComplete: true, imageUrl });
    return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
  }
  const [prices, owned] = await Promise.all([
    readReferences(supabase, favorites.cards.map((card) => card.cardId)),
    readOwnedCopies(supabase),
  ]);
  if (prices.status === "error") return fail(prices.stage, prices.code);
  if (owned.status === "error") return fail(owned.stage, owned.code);

  const report = buildFavoritesReport({
    cards: favorites.cards,
    totalCount: favorites.totalCount,
    references: prices.references,
    ownedCopies: owned.owned,
    withinLimit: favorites.withinLimit,
    ownershipComplete: owned.complete,
    imageUrl,
  });
  if (!report.complete) console.warn("[reports] minhas favoritas incompleto", { reason: report.incompleteReason, total: favorites.totalCount });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
