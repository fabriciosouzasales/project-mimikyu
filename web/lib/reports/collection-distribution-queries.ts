import type { SupabaseClient } from "@supabase/supabase-js";
import { type DistributionCollectionInput, type CollectionDistributionReport, buildCollectionDistributionReport } from "./collection-distribution.ts";
import { issuedAtLabel } from "./collection-checklist.ts";

/** Teto de páginas de `get_my_collections` (100 por página → 2.000 coleções). Acima: incompleto. */
export const DISTRIBUTION_COLLECTION_PAGE = 100;
export const DISTRIBUTION_COLLECTION_MAX_PAGES = 20;

export type CollectionDistributionReportData = { report: CollectionDistributionReport; issuedAt: string };
export type CollectionDistributionReportLoad = { status: "ready"; data: CollectionDistributionReportData } | { status: "error" };

type Rpc = Pick<SupabaseClient, "rpc">;

function n(value: unknown): number | null {
  const v = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

/**
 * V1-14 R1-B — "Distribuição do Acervo por coleção" (Minhas coleções), só com leituras existentes do titular
 * (`auth.uid()` no banco; nenhum identificador vindo do cliente; nenhuma escrita):
 * 5160 (resumo), 5182 (coleções ativas e arquivadas, `copies_count`) e 5159 (exemplares sem
 * coleção). As três em paralelo; coleções em páginas de 100 até o total. Qualquer falha ou
 * resposta fora do contrato → erro (nunca número parcial apresentado como total).
 */
export async function getCollectionDistributionReport(supabase: Rpc, now: Date = new Date()): Promise<CollectionDistributionReportLoad> {
  const startedAt = Date.now();
  const summaryRead = supabase.rpc("get_my_inventory_summary");
  const unallocatedRead = supabase.rpc("get_my_inventory_items", {
    p_search: null,
    p_card_set_code: null,
    p_language_code: null,
    p_collection_id: null,
    p_without_collection: true,
    p_sort: "RECENT",
    p_limit: 1,
    p_offset: 0,
  });
  const collectionsRead = (async () => {
    const out: DistributionCollectionInput[] = [];
    for (let page = 0; page < DISTRIBUTION_COLLECTION_MAX_PAGES; page += 1) {
      const { data, error } = await supabase.rpc("get_my_collections", {
        p_include_archived: true,
        p_limit: DISTRIBUTION_COLLECTION_PAGE,
        p_offset: page * DISTRIBUTION_COLLECTION_PAGE,
      });
      if (error || !Array.isArray(data)) return null;
      for (const row of data as Record<string, unknown>[]) {
        const copies = n(row.copies_count);
        if (typeof row.collection_id !== "string" || typeof row.name !== "string" || copies === null) return null;
        out.push({
          id: row.collection_id,
          name: row.name,
          completionPolicy: typeof row.completion_policy === "string" ? row.completion_policy : null,
          lifecycleStatus: typeof row.lifecycle_status === "string" ? row.lifecycle_status : "ACTIVE",
          copiesCount: copies,
        });
      }
      const total = n((data[0] as Record<string, unknown> | undefined)?.total_count) ?? out.length;
      if (data.length < DISTRIBUTION_COLLECTION_PAGE || out.length >= total) return { items: out, complete: true };
    }
    return { items: out, complete: false };
  })();

  const [summaryRes, unallocatedRes, collections] = await Promise.all([summaryRead, unallocatedRead, collectionsRead]);
  const s = Array.isArray(summaryRes.data) ? (summaryRes.data[0] as Record<string, unknown> | undefined) : undefined;
  const summary = s
    ? { totalCopies: n(s.total_copies), distinctItems: n(s.distinct_items), distinctSets: n(s.distinct_sets), duplicateCopies: n(s.duplicate_copies) }
    : null;
  const unallocatedRows = Array.isArray(unallocatedRes.data) ? (unallocatedRes.data as Record<string, unknown>[]) : null;
  // Sem linhas = nenhum exemplar fora de coleção.
  const unallocated = unallocatedRows === null ? null : unallocatedRows.length === 0 ? 0 : n(unallocatedRows[0]?.total_copies);

  if (
    summaryRes.error || unallocatedRes.error || !summary || collections === null || unallocated === null ||
    summary.totalCopies === null || summary.distinctItems === null || summary.distinctSets === null || summary.duplicateCopies === null
  ) {
    console.error("[reports] distribuição por coleção falhou", {
      summary: summaryRes.error?.code ?? (summary ? "OK" : "BAD_SHAPE"),
      unallocated: unallocatedRes.error?.code ?? (unallocated === null ? "BAD_SHAPE" : "OK"),
      collections: collections === null ? "FAILED" : "OK",
      ms: Date.now() - startedAt,
    });
    return { status: "error" };
  }
  const report = buildCollectionDistributionReport({
    summary: {
      totalCopies: summary.totalCopies,
      distinctItems: summary.distinctItems,
      distinctSets: summary.distinctSets,
      duplicateCopies: summary.duplicateCopies,
    },
    collections: collections.items,
    unallocatedCopies: unallocated,
    collectionsComplete: collections.complete,
  });
  if (!report.complete) console.warn("[reports] distribuição por coleção incompleta", { reason: report.incompleteReason });
  return { status: "ready", data: { report, issuedAt: issuedAtLabel(now) } };
}
