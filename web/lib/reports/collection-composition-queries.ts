import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection } from "../colecoes/colecoes-queries.ts";
import type { Rpc } from "./acervo-set-inventory-queries.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import { type CollectionCompositionReport, type CompositionKind, buildCollectionCompositionReport, compositionKindOf } from "./collection-composition.ts";
import type { CollectionValueItemInput, CollectionValueReadCheck } from "./collection-value.ts";
import { readAllocatedGroups } from "./collection-value-queries.ts";
import { readRarityCatalog } from "./distribution-queries.ts";

export type CollectionCompositionData = {
  collection: { id: string; name: string };
  kind: CompositionKind;
  /** Pokédex: espécies atendidas do resumo canônico (5332) — só contexto, nunca unidade do relatório. */
  satisfiedSpecies: number | null;
  report: CollectionCompositionReport;
  issuedAt: string;
};

export type CollectionCompositionPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: CollectionCompositionData };

type AnyRpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string } | null }> };

/**
 * F2-3 (D7 §4q) — preparação de "Composição da coleção" (Pokédex e Coleção livre), em sequência:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), modalidade (só Pokédex e livre; outra → `unavailable`) e `copies_count`;
 *  2. coleção com exemplares: em PARALELO a 5159 com `p_collection_id` = o id DESSA coleção autorizada
 *     (`readAllocatedGroups`, a leitura homologada do Valor estimado da coleção — só exemplares alocados a
 *     ela) e a 5355 (catálogo de raridades, a mesma da R1-H). Sem preços, sem miniaturas.
 * Coleção sem exemplares → vazio, sem 5159 nem 5355. Somente leitura; sem SQL nova.
 */
export async function prepareCollectionComposition(supabase: SupabaseClient, collectionId: string, now: Date = new Date()): Promise<CollectionCompositionPrepared> {
  const startedAt = Date.now();
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = compositionKindOf(collection.completionPolicy);
  if (kind === null) return { status: "unavailable", name: collection.name };
  const authorizedId = collection.id.toLowerCase();

  let items: CollectionValueItemInput[] = [];
  let read: CollectionValueReadCheck = { totalCount: 0, totalCopies: 0, duplicate: false, inconsistentPages: false };
  let rarities: Awaited<ReturnType<typeof readRarityCatalog>> = { status: "ok", entries: [] };
  if (collection.copiesCount > 0) {
    const [groups, catalog] = await Promise.all([readAllocatedGroups(supabase as unknown as Rpc, authorizedId), readRarityCatalog(supabase as unknown as AnyRpc)]);
    if (groups.status === "error") {
      console.error("[reports] composição da coleção falhou", { stage: "items", code: groups.code ?? "BAD_SHAPE", ms: Date.now() - startedAt });
      return { status: "error" };
    }
    items = groups.items;
    read = groups.check;
    rarities = catalog;
  }

  const report = buildCollectionCompositionReport({ items, read, collectionCopies: collection.copiesCount, rarities });
  console.info("[reports] composição da coleção", { ms: Date.now() - startedAt, groups: report.items, copies: report.copies, sets: report.sets, complete: report.complete });
  if (!report.complete) console.warn("[reports] composição da coleção incompleta", { reason: report.incompleteReason });
  return {
    status: "ready",
    data: {
      collection: { id: collection.id, name: collection.name },
      kind,
      satisfiedSpecies: kind === "POKEDEX" ? collection.satisfiedPositions : null,
      report,
      issuedAt: issuedAtLabel(now),
    },
  };
}
