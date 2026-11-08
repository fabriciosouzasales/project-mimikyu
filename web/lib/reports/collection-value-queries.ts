import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getSetLogoUrls } from "../colecoes/colecoes-queries.ts";
import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import { type Rpc, SET_INVENTORY_PAGE, inventoryPriceInput, toItem } from "./acervo-set-inventory-queries.ts";
import type { SetInventoryPriceInput } from "./acervo-set-inventory.ts";
import { type ChecklistKind, checklistKindOf, issuedAtLabel } from "./collection-checklist.ts";
import {
  COLLECTION_VALUE_MAX_GROUPS,
  type CollectionValueItemInput,
  type CollectionValueReadCheck,
  type CollectionValueReport,
  buildCollectionValueReport,
} from "./collection-value.ts";

export type CollectionValueCollection = { id: string; name: string; cardSetCode: string | null; cardSetName: string | null };

export type CollectionValueReportData = {
  collection: CollectionValueCollection;
  kind: ChecklistKind;
  report: CollectionValueReport;
  logoUrl: string | null;
  issuedAt: string;
};

export type CollectionValuePrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: CollectionValueReportData };

const RPC_5159 = "get_my_inventory_items";

const itemsParams = (collectionId: string, offset: number) => ({
  p_search: null,
  p_card_set_code: null,
  p_language_code: null,
  p_collection_id: collectionId,
  p_without_collection: false,
  p_sort: "SET_NUMBER",
  p_limit: SET_INVENTORY_PAGE,
  p_offset: offset,
});

function count(value: unknown): number | null {
  const v = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

type AllocatedRead =
  | { status: "ok"; items: CollectionValueItemInput[]; check: CollectionValueReadCheck }
  | { status: "error"; code?: string };

/**
 * Exemplares ALOCADOS à coleção autorizada: 5159 com `p_collection_id` (o banco considera só
 * exemplares com alocação nessa coleção e confere o dono — `collection.owner_user_id = auth.uid()`),
 * em `SET_NUMBER` (ordem total e determinística: lançamento, código, `collector_order`,
 * `variant_order`, `language_order`, `card_variant_id`, `language_id`), páginas de 96 **em
 * sequência** (lição do INCIDENT-01). A 1ª página dá `total_count`/`total_copies`; acima de 5.000
 * grupos não lê o resto (incompleto explícito, nunca truncado). Cada página recalcula os totais no
 * banco: total diferente entre páginas, página intermediária curta ou grupo repetido tornam a leitura
 * inconsistente (observável). Não é um snapshot transacional único.
 */
export async function readAllocatedGroups(supabase: Rpc, collectionId: string): Promise<AllocatedRead> {
  const items: CollectionValueItemInput[] = [];
  const seen = new Set<string>();
  let duplicate = false;
  let inconsistentPages = false;
  let totalCount = 0;
  let totalCopies = 0;
  for (let offset = 0, page = 0; ; offset += SET_INVENTORY_PAGE, page += 1) {
    const res = await supabase.rpc(RPC_5159, itemsParams(collectionId, offset));
    if (res.error) return { status: "error", code: res.error.code };
    if (!Array.isArray(res.data)) return { status: "error" };
    const rows = res.data as Record<string, unknown>[];
    if (page === 0) {
      if (rows.length === 0) return { status: "ok", items, check: { totalCount: 0, totalCopies: 0, duplicate, inconsistentPages } };
      const t = count(rows[0]?.total_count);
      const c = count(rows[0]?.total_copies);
      if (t === null || c === null) return { status: "error" };
      totalCount = t;
      totalCopies = c;
      if (totalCount > COLLECTION_VALUE_MAX_GROUPS) return { status: "ok", items: [], check: { totalCount, totalCopies, duplicate, inconsistentPages } };
    }
    for (const row of rows) {
      const item = toItem(row);
      if (!item) return { status: "error" };
      if (count(row.total_count) !== totalCount || count(row.total_copies) !== totalCopies) inconsistentPages = true;
      const key = `${item.cardVariantId}|${item.languageCode}`;
      if (seen.has(key)) duplicate = true;
      seen.add(key);
      items.push({ ...item, order: items.length });
    }
    const readSoFar = offset + rows.length;
    if (readSoFar >= totalCount) break;
    // Página intermediária menor que a pedida, ou vazia antes do fim: omissão observável.
    if (rows.length < SET_INVENTORY_PAGE) {
      inconsistentPages = true;
      break;
    }
  }
  return { status: "ok", items, check: { totalCount, totalCopies, duplicate, inconsistentPages } };
}

/**
 * V1-14 R2-E — preparação de "Valor estimado dos exemplares alocados" (D7 §4m), em SEQUÊNCIA:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), objetivo (Set padrão ou Master Set; senão `unavailable`) e `copies_count`.
 *     Nada financeiro é lido antes disso nem para coleção não suportada;
 *  2. 5159 com `p_collection_id` = o id DESSA coleção autorizada (nunca do navegador), páginas
 *     em sequência; coleção sem alocações (`copies_count` = 0) → vazio, sem 5159 nem preços;
 *  3. 3989 por variante distinta via `readVariantPrices` (concorrência 2, uma nova tentativa para
 *     57014); só com exemplares. O logo do Set sai em paralelo com a 5159 (armazenamento, não banco).
 * Cálculo uma única vez (`buildCollectionValueReport`). Falha da coleção ou da 5159 → erro; falha
 * de preço → grupos "Preço indisponível" e relatório provisório. Somente leitura; sem SQL nova.
 */
export async function prepareCollectionValueReport(
  supabase: SupabaseClient,
  collectionId: string,
  imageUrl?: (path: string) => string | null,
  now: Date = new Date(),
): Promise<CollectionValuePrepared> {
  const startedAt = Date.now();
  const rpc = supabase as unknown as Rpc;
  // 1. Autorização e contexto — antes de qualquer leitura de exemplares ou preços.
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  if (kind === null) return { status: "unavailable", name: collection.name };
  const authorizedId = collection.id.toLowerCase();
  const collectionCopies = collection.copiesCount;

  const logoPath = collection.cardSetLogoPath;
  const logoRead = logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null) : Promise.resolve(null);

  // 2. Exemplares alocados (só se a coleção tem alocações).
  let items: CollectionValueItemInput[] = [];
  let check: CollectionValueReadCheck = { totalCount: 0, totalCopies: 0, duplicate: false, inconsistentPages: false };
  if (collectionCopies > 0) {
    const read = await readAllocatedGroups(rpc, authorizedId);
    if (read.status === "error") {
      console.error("[reports] valor estimado da coleção falhou", { stage: "items", code: read.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
      return { status: "error" };
    }
    items = read.items;
    check = read.check;
  }

  // 3. Preços (só com exemplares), uma vez por variante distinta.
  const prices = new Map<string, SetInventoryPriceInput>();
  let unavailable = new Set<string>();
  if (items.length > 0) {
    const priceRead = await readVariantPrices(rpc, [...new Set(items.map((item) => item.cardVariantId))]);
    for (const [id, price] of priceRead.prices) {
      const input = inventoryPriceInput(price);
      if (input) prices.set(id.toLowerCase(), input);
    }
    unavailable = new Set(priceRead.unavailableIds.map((id) => id.toLowerCase()));
  }

  const report = buildCollectionValueReport({ items, prices, unavailable, read: check, collectionCopies, now: now.getTime(), imageUrl });
  const logoUrl = await logoRead;
  console.info("[reports] valor estimado da coleção", {
    ms: Date.now() - startedAt,
    groups: report.groups,
    copies: report.copies,
    priced: report.pricedGroups,
    unavailable: report.unavailableGroups,
    complete: report.complete,
  });
  if (!report.complete) console.warn("[reports] valor estimado da coleção incompleto", { reason: report.incompleteReason, total: check.totalCount });
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
