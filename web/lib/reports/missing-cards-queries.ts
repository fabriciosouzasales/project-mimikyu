import type { SupabaseClient } from "@supabase/supabase-js";
import { type ChecklistReportCollection, prepareChecklistReport } from "./checklist-queries";
import type { ChecklistKind } from "./collection-checklist";
import { type MissingCardsReport, buildMissingCardsReport } from "./missing-cards";

export type MissingCardsReportData = {
  collection: ChecklistReportCollection;
  kind: ChecklistKind;
  report: MissingCardsReport;
  logoUrl: string | null;
  issuedAt: string;
};

export type MissingCardsPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: MissingCardsReportData };

/**
 * V1-14 R2-B — preparação de "Cartas faltantes": EXATAMENTE a preparação homologada do Checklist
 * (`prepareChecklistReport`, filtro "faltam" → `MISSING`) — dono por `get_my_collection` (5332;
 * alheia/compartilhada/inexistente → `not_found`, sem distinguir), objetivo elegível (Set padrão ou
 * Master Set; Pokédex/livre → `unavailable`), conjunto INTEIRO em lotes de 500 por 5169/5198
 * (teto 5.000) e logo do Set em paralelo. Nenhuma SQL nova, nenhuma escrita, nenhum identificador
 * de titular vindo do cliente. Aqui só agrupamos (`buildMissingCardsReport`).
 */
export async function prepareMissingCardsReport(supabase: SupabaseClient, collectionId: string): Promise<MissingCardsPrepared> {
  const startedAt = Date.now();
  const prepared = await prepareChecklistReport(supabase, collectionId, "faltam");
  if (prepared.status !== "ready") return prepared;
  const { data } = prepared;
  if (data.load.status !== "ready") return { status: "error" };
  const report = buildMissingCardsReport({
    kind: data.kind,
    load: data.load,
    totalPositions: data.collection.totalPositions,
    satisfiedPositions: data.collection.satisfiedPositions,
  });
  console.info("[reports] cartas faltantes", {
    ms: Date.now() - startedAt,
    kind: data.kind,
    missing: report.missingPositions,
    available: report.availablePositions,
    complete: report.complete,
  });
  if (!report.complete) console.warn("[reports] cartas faltantes incompleto", { reason: report.incompleteReason, loaded: data.load.rows.length, total: data.load.total });
  return { status: "ready", data: { collection: data.collection, kind: data.kind, report, logoUrl: data.logoUrl, issuedAt: data.issuedAt } };
}
