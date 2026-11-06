import type { SupabaseClient } from "@supabase/supabase-js";
import { toPositionsRpcFilter, type PositionFilter } from "@/lib/colecoes/colecoes";
import { getMyCollection, getSetLogoUrls } from "@/lib/colecoes/colecoes-queries";
import { type ChecklistKind, type ChecklistLoad, checklistKindOf, issuedAtLabel, loadChecklist } from "./collection-checklist";

/**
 * V1-14 R1-A — leitura do Checklist de completude: o conjunto INTEIRO do filtro, em lotes de
 * 500, pelas mesmas leituras canônicas da página da coleção — sem SQL novo:
 *   Set padrão → `get_my_collection_positions` (5169);
 *   Master Set → `get_my_master_set_positions` (5189, desempenho 5198).
 * Ambas são do titular (`auth.uid()`); coleção alheia devolve zero linhas. Nenhuma escrita.
 */
export async function getChecklist(
  supabase: SupabaseClient,
  collectionId: string,
  kind: ChecklistKind,
  filter: PositionFilter,
): Promise<ChecklistLoad> {
  const rpc = kind === "MASTER_SET" ? "get_my_master_set_positions" : "get_my_collection_positions";
  const startedAt = Date.now();
  const result = await loadChecklist(kind, async (offset, limit) => {
    const { data, error } = await supabase.rpc(rpc, {
      p_collection_id: collectionId,
      p_filter: toPositionsRpcFilter(filter),
      p_limit: limit,
      p_offset: offset,
    });
    if (error || !Array.isArray(data)) {
      console.error(`[reports] ${rpc} falhou`, { code: error?.code ?? "BAD_SHAPE", offset, ms: Date.now() - startedAt });
      return null;
    }
    return data;
  });
  if (result.status === "ready" && !result.complete) {
    console.warn(`[reports] checklist incompleto`, { reason: result.incompleteReason, loaded: result.rows.length, total: result.total });
  }
  return result;
}

/** Coleção como o relatório a apresenta (sem nada além do necessário à tela e à folha). */
export type ChecklistReportCollection = {
  id: string;
  name: string;
  cardSetCode: string | null;
  cardSetName: string | null;
  totalPositions: number;
  satisfiedPositions: number;
};

export type ChecklistReportData = {
  collection: ChecklistReportCollection;
  kind: ChecklistKind;
  filter: PositionFilter;
  load: ChecklistLoad;
  logoUrl: string | null;
  issuedAt: string;
};

/**
 * Preparação única do Checklist, usada pela sobreposição (server action) e pela rota de acesso
 * direto: dono via `get_my_collection` (5332) — `undefined` = alheia/compartilhada/inexistente
 * (404 sem distinguir), `null` = falha de leitura —, política elegível e o conjunto INTEIRO do
 * filtro em paralelo com o logo do Set. Somente leitura.
 */
export async function prepareChecklistReport(
  supabase: SupabaseClient,
  collectionId: string,
  filter: PositionFilter,
): Promise<{ status: "not_found" } | { status: "error" } | { status: "unavailable"; name: string } | { status: "ready"; data: ChecklistReportData }> {
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  if (kind === null) return { status: "unavailable", name: collection.name };
  const logoPath = collection.cardSetLogoPath;
  const [load, logoUrl] = await Promise.all([
    getChecklist(supabase, collectionId, kind, filter),
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null) : Promise.resolve(null),
  ]);
  return {
    status: "ready",
    data: {
      collection: {
        id: collectionId,
        name: collection.name,
        cardSetCode: collection.cardSetCode,
        cardSetName: collection.cardSetName,
        totalPositions: collection.totalPositions,
        satisfiedPositions: collection.satisfiedPositions,
      },
      kind,
      filter,
      load,
      logoUrl,
      issuedAt: issuedAtLabel(new Date()),
    },
  };
}
