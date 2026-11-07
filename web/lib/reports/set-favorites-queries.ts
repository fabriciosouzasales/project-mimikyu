import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getSetLogoUrls } from "../colecoes/colecoes-queries.ts";
import { type Rpc, inBatches } from "./acervo-set-inventory-queries.ts";
import { checklistKindOf, issuedAtLabel, type ChecklistKind } from "./collection-checklist.ts";
import { FAVORITES_REPORT_MAX, FAVORITES_REPORT_PAGE, type FavoriteReportCardInput, buildFavoritesReport, parseFavoriteReportPage } from "./favorites-report.ts";
import { PAGE_PARALLEL, readOwnedCopies, readReferences } from "./favorites-report-queries.ts";
import { type SetFavoritesReport, buildSetFavoritesReport } from "./set-favorites.ts";

export type SetFavoritesCollection = { id: string; name: string; cardSetCode: string | null; cardSetName: string | null };

export type SetFavoritesReportData = {
  collection: SetFavoritesCollection;
  kind: ChecklistKind;
  report: SetFavoritesReport;
  logoUrl: string | null;
  issuedAt: string;
};

export type SetFavoritesPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: SetFavoritesReportData };

const RPC_5356 = "get_my_favorite_cards_by_card_set";

type FavoritesRead =
  | { status: "ok"; cards: FavoriteReportCardInput[]; order: string[]; totalCount: number; withinLimit: boolean; foreignSet: boolean }
  | { status: "error"; code?: string };

/**
 * Favoritas do titular num Card Set (5356 — filtro canônico `card.card_set_id` no banco): páginas
 * de 100, a 1ª dá o total, as demais em paralelo (4), teto de 5.000; mesma validação estrita da
 * R1-D (`parseFavoriteReportPage`) e conferência do `card_set_id` de cada linha (nunca descartada
 * em silêncio: linha de outro Set marca a leitura como inconsistente).
 */
export async function readSetFavorites(supabase: Rpc, cardSetId: string): Promise<FavoritesRead> {
  const args = (offset: number) => ({ p_card_set_id: cardSetId, p_limit: FAVORITES_REPORT_PAGE, p_offset: offset });
  const first = await supabase.rpc(RPC_5356, args(0));
  if (first.error) return { status: "error", code: first.error.code };
  const pages: unknown[] = [first.data];
  const firstPage = parseFavoriteReportPage(first.data);
  if (!firstPage) return { status: "error" };
  const totalCount = firstPage.cards.length === 0 ? 0 : firstPage.totalCount;
  const readable = Math.min(totalCount, FAVORITES_REPORT_MAX);
  const offsets: number[] = [];
  for (let offset = FAVORITES_REPORT_PAGE; offset < readable; offset += FAVORITES_REPORT_PAGE) offsets.push(offset);
  const rest = await inBatches(offsets.map((offset) => () => supabase.rpc(RPC_5356, args(offset))), PAGE_PARALLEL);
  const cards = [...firstPage.cards];
  for (const page of rest) {
    if (page.error) return { status: "error", code: page.error.code };
    const parsed = parseFavoriteReportPage(page.data);
    if (!parsed) return { status: "error" };
    pages.push(page.data);
    cards.push(...parsed.cards);
  }
  const wanted = cardSetId.toLowerCase();
  const foreignSet = pages.some((data) => (data as Record<string, unknown>[]).some((row) => typeof row?.card_set_id !== "string" || row.card_set_id.toLowerCase() !== wanted));
  const sliced = cards.slice(0, readable);
  return { status: "ok", cards: sliced, order: sliced.map((card) => card.cardId), totalCount, withinLimit: totalCount <= FAVORITES_REPORT_MAX, foreignSet };
}

/**
 * V1-14 R2-D — preparação de "Cartas favoritas do Card Set" (D7 §4l), em SEQUÊNCIA obrigatória:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), objetivo (Set padrão ou Master Set; senão `unavailable`) e Card Set;
 *  2. só então 5356 com `p_card_set_id` = o Card Set DESSA coleção autorizada (nunca do navegador);
 *     o logo do Set em paralelo;
 *  3. em paralelo, referência geral NM por carta (`readReferences`, R1-D) e posse no acervo inteiro
 *     (`readOwnedCopies`, R1-D: 5160 + 5159 + variante → carta).
 * Falha da coleção, das favoritas ou da posse → erro; falha de preço → relatório provisório
 * (referências "Indisponível", impressão bloqueada). Só o titular (`auth.uid()` no banco); nenhuma
 * escrita; sem SQL nova além da 5356 (já aplicada).
 */
export async function prepareSetFavoritesReport(
  supabase: SupabaseClient,
  collectionId: string,
  imageUrl?: (path: string) => string | null,
  now: Date = new Date(),
): Promise<SetFavoritesPrepared> {
  const startedAt = Date.now();
  const rpc = supabase as unknown as Rpc;
  // 1. Autorização e contexto — antes de qualquer leitura de favoritas.
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  const cardSetId = collection.cardSetId ?? null;
  if (kind === null || cardSetId === null) return { status: "unavailable", name: collection.name };

  // 2. Favoritas do Card Set da coleção autorizada (+ logo em paralelo).
  const logoPath = collection.cardSetLogoPath;
  const [favorites, logoUrl] = await Promise.all([
    readSetFavorites(rpc, cardSetId),
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null) : Promise.resolve(null),
  ]);
  if (favorites.status === "error") {
    console.error("[reports] favoritas do Card Set falhou", { stage: "favorites", code: favorites.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }

  // 3. Referência por carta e posse (regras da R1-D).
  let references = new Map<string, number>();
  let owned = new Map<string, number>();
  let ownershipComplete = true;
  let pricesUnavailable = false;
  if (favorites.cards.length > 0) {
    const [prices, ownership] = await Promise.all([readReferences(rpc, favorites.cards.map((card) => card.cardId)), readOwnedCopies(rpc)]);
    if (ownership.status === "error") {
      console.error("[reports] favoritas do Card Set falhou", { stage: ownership.stage, code: ownership.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
      return { status: "error" };
    }
    owned = ownership.owned;
    ownershipComplete = ownership.complete;
    if (prices.status === "error") pricesUnavailable = true;
    else references = prices.references;
  }
  const report = buildSetFavoritesReport({
    favorites: buildFavoritesReport({ cards: favorites.cards, totalCount: favorites.totalCount, references, ownedCopies: owned, withinLimit: favorites.withinLimit, ownershipComplete, imageUrl }),
    order: favorites.order,
    foreignSet: favorites.foreignSet,
    pricesUnavailable,
  });
  console.info("[reports] favoritas do Card Set", { ms: Date.now() - startedAt, cards: report.cardCount, owned: report.ownedCount, complete: report.complete });
  if (!report.complete) console.warn("[reports] favoritas do Card Set incompleto", { reason: report.incompleteReason, total: favorites.totalCount });
  return {
    status: "ready",
    data: {
      collection: { id: collection.id, name: collection.name, cardSetCode: collection.cardSetCode, cardSetName: collection.cardSetName },
      kind,
      report,
      logoUrl,
      issuedAt: issuedAtLabel(now),
    },
  };
}
