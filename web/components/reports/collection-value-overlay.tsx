"use client";

import { BarChart3 } from "lucide-react";
import { type CollectionValueReportResult, readCollectionValueReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { COLLECTION_VALUE_PROVISIONAL_TEXT, collectionValueIncompleteText } from "@/lib/reports/collection-value";
import { shareInFlight } from "@/lib/reports/in-flight";
import { preparePrintImages } from "./print-image-gate";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";
import { COLLECTION_VALUE_TITLE, CollectionValueSheet } from "./collection-value-report";

/** Uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<CollectionValueReportResult>>();
function readOnce(collectionId: string): Promise<CollectionValueReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readCollectionValueReport({ collectionId }));
    inFlight.set(collectionId, shared);
  }
  return shared();
}

function unavailableSheet(title: string, text: string) {
  return (
    <div className="mx-auto max-w-[210mm] rounded-lg border border-border px-6 py-10 text-center print:hidden" role="status">
      <p className="text-sm font-semibold">{title}</p>
      <p className="mt-2 text-xs text-muted-foreground">{text}</p>
    </div>
  );
}

/** Resultado da leitura → entrada da casca (exportada para teste). */
export function collectionValueEntry(result: CollectionValueReportResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    const { report } = data;
    // Elegibilidade da impressão (E4): bloqueada só por integridade (D11) ou falha técnica de preço
    // (D7); ausência legítima de cotação NÃO bloqueia. Com linhas, o botão Imprimir prepara antes as
    // miniaturas (mecanismo da R1-G); se alguma falhar, a impressão não abre.
    const incomplete = !report.complete ? collectionValueIncompleteText(report.incompleteReason) : report.provisional ? COLLECTION_VALUE_PROVISIONAL_TEXT : null;
    return {
      status: "ready",
      incomplete,
      sheet: <CollectionValueSheet collection={data.collection} kind={data.kind} report={report} logoUrl={data.logoUrl} issuedAt={data.issuedAt} />,
      preparePrint: report.lines.length > 0 ? (onProgress) => preparePrintImages(onProgress) : undefined,
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? {
        status: "ready",
        incomplete: "O Valor estimado existe para coleções de Set padrão e Master Set.",
        sheet: unavailableSheet("Relatório indisponível para esta coleção", "Nesta etapa, o relatório existe para coleções de Set padrão e Master Set."),
      }
    : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * V1-14 R2-E — "Valor estimado dos exemplares alocados" em SOBREPOSIÇÃO à coleção (casca única dos
 * relatórios contextuais — `ReportSheetOverlay`). Somente leitura; provisório e incompleto
 * identificados na folha e com a impressão bloqueada; impressão A4 com miniaturas preparadas (E4).
 */
export function CollectionValueOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <BarChart3 aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={COLLECTION_VALUE_TITLE}
      context="Coleção · valor estimado dos exemplares alocados a ela, pela referência NM"
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then(collectionValueEntry)}
      onClose={onClose}
    />
  );
}
