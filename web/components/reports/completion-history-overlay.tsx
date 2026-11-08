"use client";

import { TrendingUp } from "lucide-react";
import { type CompletionHistoryReportResult, readCompletionHistoryReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";
import { COMPLETION_HISTORY_TITLE, CompletionHistorySheet } from "./completion-history-report";

/** Uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<CompletionHistoryReportResult>>();
function readOnce(collectionId: string): Promise<CompletionHistoryReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readCompletionHistoryReport({ collectionId }));
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
export function completionHistoryEntry(result: CompletionHistoryReportResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    // Sempre imprimível: só fechamentos registrados e a completude atual; nada estimado nem parcial.
    return {
      status: "ready",
      incomplete: null,
      sheet: <CompletionHistorySheet collection={data.collection} kind={data.kind} report={data.report} logoUrl={data.logoUrl} issuedAt={data.issuedAt} readAtMs={data.readAtMs} />,
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? {
        status: "ready",
        incomplete: "A Evolução da completude existe para coleções de Set padrão e Master Set.",
        sheet: unavailableSheet("Relatório indisponível para esta coleção", "Nesta etapa, o relatório existe para coleções de Set padrão e Master Set."),
      }
    : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * V1-14 R2-F (B2) — "Evolução da completude" em SOBREPOSIÇÃO à coleção (casca única dos relatórios
 * contextuais — `ReportSheetOverlay`). Somente leitura, só o titular; impressão A4 (D11).
 */
export function CompletionHistoryOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <TrendingUp aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={COMPLETION_HISTORY_TITLE}
      context="Coleção · completude registrada a cada fechamento diário, desde o início do acompanhamento"
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then(completionHistoryEntry)}
      onClose={onClose}
    />
  );
}
