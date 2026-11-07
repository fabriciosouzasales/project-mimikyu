import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getSetLogoUrls } from "../colecoes/colecoes-queries.ts";
import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import type { Rpc } from "./acervo-set-inventory-queries.ts";
import { checklistKindOf, issuedAtLabel, type ChecklistKind } from "./collection-checklist.ts";
import { type SetWishlistReport, buildSetWishlistReport } from "./set-wishlist.ts";
import { buildWishlistReport } from "./wishlist-report.ts";
import { readAllWishes } from "./wishlist-report-queries.ts";

export type SetWishlistCollection = { id: string; name: string; cardSetCode: string | null; cardSetName: string | null };

export type SetWishlistReportData = {
  collection: SetWishlistCollection;
  kind: ChecklistKind;
  report: SetWishlistReport;
  logoUrl: string | null;
  issuedAt: string;
};

export type SetWishlistPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: SetWishlistReportData };

/**
 * V1-14 R2-C — preparação de "Cartas desejadas do Card Set" (D7 §4k), em SEQUÊNCIA obrigatória:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), objetivo (Set padrão ou Master Set; senão `unavailable`) e Card Set;
 *  2. só então 5351 `get_my_wishlist_filtered` com `p_card_set_id` = o Card Set DESSA coleção
 *     autorizada (nunca do navegador), "Set e número", páginas de 100, teto 5.000 — a mesma leitura
 *     estrita da R1-E (`readAllWishes`); o logo do Set em paralelo com ela;
 *  3. 3989 para as variantes distintas (`readVariantPrices`, Pricing Resilience, concorrência 2).
 * Regras de posse, preço e completude da leitura: `buildWishlistReport` (R1-E), sem cópia.
 * Desejos só do titular (`auth.uid()` no banco); nenhuma escrita; sem SQL nova.
 */
export async function prepareSetWishlistReport(
  supabase: SupabaseClient,
  collectionId: string,
  imageUrl?: (path: string) => string | null,
  now: Date = new Date(),
): Promise<SetWishlistPrepared> {
  const startedAt = Date.now();
  // 1. Autorização e contexto — antes de qualquer leitura de desejos.
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  const cardSetId = collection.cardSetId ?? null;
  if (kind === null || cardSetId === null) return { status: "unavailable", name: collection.name };

  // 2. Desejos do Card Set da coleção autorizada (+ logo em paralelo).
  const logoPath = collection.cardSetLogoPath;
  const [wishes, logoUrl] = await Promise.all([
    readAllWishes(supabase as unknown as Rpc, cardSetId),
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null) : Promise.resolve(null),
  ]);
  if (wishes.status === "error") {
    console.error("[reports] desejos do Card Set falhou", { stage: wishes.stage, code: wishes.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
    return { status: "error" };
  }

  // 3. Referência NM por variante distinta (regras da R1-E).
  const variantIds = [...new Set(wishes.entries.map((entry) => entry.cardVariantId))];
  const prices = variantIds.length > 0 ? await readVariantPrices(supabase as unknown as Rpc, variantIds) : { status: "complete" as const, prices: new Map(), unavailableIds: [] };
  const wishlist = buildWishlistReport({
    entries: wishes.entries,
    totalCount: wishes.totalCount,
    withinLimit: wishes.withinLimit,
    prices: prices.prices,
    unavailable: new Set(prices.unavailableIds),
    imageUrl,
  });
  const report = buildSetWishlistReport({ wishlist, cardSetCode: collection.cardSetCode });
  console.info("[reports] desejos do Card Set", { ms: Date.now() - startedAt, wishes: report.entryCount, variants: report.variantCount, complete: report.complete });
  if (!report.complete) console.warn("[reports] desejos do Card Set incompleto", { reason: report.incompleteReason, total: wishes.totalCount, prices: prices.status });
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
