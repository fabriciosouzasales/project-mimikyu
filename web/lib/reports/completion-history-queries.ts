import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getSetLogoUrls } from "../colecoes/colecoes-queries.ts";
import { type ChecklistKind, checklistKindOf, issuedAtLabel } from "./collection-checklist.ts";
import { type CompletionReport, buildCompletionReport, parseCompletionHistory } from "./completion-history.ts";

export type CompletionHistoryCollection = { id: string; name: string; cardSetCode: string | null; cardSetName: string | null; archived: boolean };

export type CompletionHistoryReportData = {
  collection: CompletionHistoryCollection;
  kind: ChecklistKind;
  report: CompletionReport;
  logoUrl: string | null;
  issuedAt: string;
  /** Instante da leitura (ms) — posição do ponto "agora" no gráfico. */
  readAtMs: number;
};

export type CompletionHistoryPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: CompletionHistoryReportData };

/** Leitura do titular (5358): só a coleção autorizada; P0002 = alheia/compartilhada/inexistente. */
export const RPC_5358_HISTORY = "get_my_collection_completion_history";

type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string } | null }> };

/**
 * V1-14 R2-F (B2) — preparação de "Evolução da completude" (D7 §4n), em SEQUÊNCIA:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), objetivo (Set padrão ou Master Set; senão `unavailable`, sem ler histórico) e a
 *     completude ATUAL canônica (5188 dentro da 5332);
 *  2. 5358 `get_my_collection_completion_history` com o id DESSA coleção autorizada (nunca do
 *     navegador sem passar pela 5332). P0002 → `not_found`; forma incoerente → erro.
 * O logo do Set sai em paralelo com a 5358 (armazenamento, não banco). Somente leitura; sem SQL nova.
 */
export async function prepareCompletionHistoryReport(supabase: SupabaseClient, collectionId: string, now: Date = new Date()): Promise<CompletionHistoryPrepared> {
  const startedAt = Date.now();
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  if (kind === null) return { status: "unavailable", name: collection.name };
  const authorizedId = collection.id.toLowerCase();

  const logoPath = collection.cardSetLogoPath;
  const logoRead = logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null).catch(() => null) : Promise.resolve(null);

  const res = await (supabase as unknown as Rpc).rpc(RPC_5358_HISTORY, { p_collection_id: authorizedId });
  if (res.error) {
    if (res.error.code === "P0002") return { status: "not_found" };
    console.error("[reports] evolução da completude falhou", { stage: "history", code: res.error.code ?? "UNKNOWN", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const history = parseCompletionHistory(res.data);
  if (!history) {
    console.error("[reports] evolução da completude falhou", { stage: "shape", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const report = buildCompletionReport({
    history,
    now: {
      satisfied: collection.satisfiedPositions,
      total: collection.totalPositions,
      policy: collection.completionPolicy,
      lifecycle: collection.lifecycleStatus,
      cardSetId: collection.cardSetId ?? null,
    },
    at: now,
  });
  const logoUrl = await logoRead;
  console.info("[reports] evolução da completude", {
    ms: Date.now() - startedAt,
    state: report.state,
    snapshots: history.snapshots.length,
    intervals: history.coverage.length,
    gapDays: report.gapDays,
  });
  return {
    status: "ready",
    data: {
      collection: {
        id: collection.id,
        name: collection.name,
        cardSetCode: collection.cardSetCode,
        cardSetName: collection.cardSetName,
        archived: collection.lifecycleStatus === "ARCHIVED",
      },
      kind,
      report,
      logoUrl,
      issuedAt: issuedAtLabel(now),
      readAtMs: now.getTime(),
    },
  };
}
