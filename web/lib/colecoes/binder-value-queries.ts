import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollectionBinder } from "./binder-queries.ts";
import { readVariantPrices } from "../pricing/variant-pricing-queries.ts";
import { type Rpc, inventoryPriceInput, toItem } from "../reports/acervo-set-inventory-queries.ts";
import type { SetInventoryPriceInput } from "../reports/acervo-set-inventory.ts";
import {
  COLLECTION_VALUE_MAX_GROUPS,
  type CollectionValueItemInput,
  type CollectionValueReadCheck,
  buildCollectionValueReport,
} from "../reports/collection-value.ts";
import { type BinderValueSummary, summarizeBinderValue } from "./binder-value.ts";

/** Query 5357 (aplicada e validada no LIVE, ledger 20261108042423). */
export const RPC_5357 = "get_my_binder_value_groups";
/** Página máxima da 5357 (1..200). */
export const BINDER_VALUE_PAGE = 200;

export type BinderValuePrepared =
  | { status: "not_found" }
  | { status: "no_binder" }
  | { status: "error" }
  | { status: "ready"; summary: BinderValueSummary };

function count(value: unknown): number | null {
  const v = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

type GroupsRead =
  | { status: "ok"; items: CollectionValueItemInput[]; check: CollectionValueReadCheck }
  | { status: "not_found" }
  | { status: "error"; code?: string };

/**
 * Grupos variante + idioma dos exemplares nos bolsos (5357), páginas de 200 em
 * SEQUÊNCIA (lição do INCIDENT-01). Mesma conferência da leitura da R2-E: a 1ª
 * página dá `total_count`/`total_copies`; total diferente entre páginas, página
 * intermediária curta ou grupo repetido tornam a leitura inconsistente
 * (observável → "não definitivo"). Acima de 5.000 grupos não lê o resto.
 * A 5357 confere o dono (`auth.uid()`); coleção alheia/inexistente → P0002.
 */
export async function readBinderValueGroups(supabase: Rpc, collectionId: string): Promise<GroupsRead> {
  const items: CollectionValueItemInput[] = [];
  const seen = new Set<string>();
  let duplicate = false;
  let inconsistentPages = false;
  let totalCount = 0;
  let totalCopies = 0;
  for (let offset = 0, page = 0; ; offset += BINDER_VALUE_PAGE, page += 1) {
    const res = await supabase.rpc(RPC_5357, { p_collection_id: collectionId, p_limit: BINDER_VALUE_PAGE, p_offset: offset });
    if (res.error) return res.error.code === "P0002" ? { status: "not_found" } : { status: "error", code: res.error.code };
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
    if (offset + rows.length >= totalCount) break;
    if (rows.length < BINDER_VALUE_PAGE) {
      inconsistentPages = true;
      break;
    }
  }
  return { status: "ok", items, check: { totalCount, totalCopies, duplicate, inconsistentPages } };
}

/**
 * Valor do Fichário (D1–D9), em SEQUÊNCIA, só leitura, sessão do usuário:
 *  1. cabeçalho do fichário (5223/5252) — titularidade (alheia/inexistente →
 *     `not_found`, sem distinguir), existência do fichário e `filled_count`
 *     (total esperado da conferência). Nada financeiro antes disso;
 *  2. sem cartas nos bolsos → vazio, sem 5357 nem preços;
 *  3. 5357 em páginas sequenciais;
 *  4. 3989 por variante distinta (`readVariantPrices`: concorrência 2, uma nova
 *     tentativa em 57014) e regra de validade `inventoryPriceInput` (R2-E).
 * Cálculo uma única vez (`buildCollectionValueReport`, R2-E) com o total
 * esperado = `filled_count`; ao navegador vai só o resumo do cartão.
 */
export async function prepareBinderValue(supabase: SupabaseClient, collectionId: string, now: Date = new Date()): Promise<BinderValuePrepared> {
  const startedAt = Date.now();
  const rpc = supabase as unknown as Rpc;
  const header = await getMyCollectionBinder(supabase, collectionId);
  if (header === undefined) return { status: "not_found" };
  if (header === null) return { status: "error" };
  if (!header.hasBinder) return { status: "no_binder" };
  const expected = header.filledCount;

  let items: CollectionValueItemInput[] = [];
  let check: CollectionValueReadCheck = { totalCount: 0, totalCopies: 0, duplicate: false, inconsistentPages: false };
  if (expected > 0) {
    const read = await readBinderValueGroups(rpc, collectionId);
    if (read.status === "not_found") return { status: "not_found" };
    if (read.status === "error") {
      console.error("[binder] valor do fichário falhou", { stage: "groups", code: read.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
      return { status: "error" };
    }
    items = read.items;
    check = read.check;
  }

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

  const report = buildCollectionValueReport({ items, prices, unavailable, read: check, collectionCopies: expected, now: now.getTime() });
  const summary = summarizeBinderValue(report);
  console.info("[binder] valor do fichário", {
    ms: Date.now() - startedAt,
    groups: report.groups,
    copies: report.copies,
    priced: report.pricedGroups,
    unavailable: report.unavailableGroups,
    complete: report.complete,
  });
  if (!report.complete) console.warn("[binder] valor do fichário incompleto", { reason: report.incompleteReason });
  return { status: "ready", summary };
}
