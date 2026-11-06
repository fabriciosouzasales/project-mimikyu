"use client";

import { Library } from "lucide-react";
import { readSetInventoryReport, readSetSummaryReport } from "@/app/colecoes/acervo/relatorios/actions";
import { type AcervoReportId, acervoReport } from "@/lib/reports/acervo-reports";
import { setInventoryIncompleteText } from "@/lib/reports/acervo-set-inventory";
import { setSummaryIncompleteText } from "@/lib/reports/acervo-set-summary";
import { AcervoSetInventorySheet } from "./acervo-set-inventory-report";
import { AcervoSetSummarySheet } from "./acervo-set-summary-report";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

/** Cada relatório do Meu acervo tem leitura e folha próprias; a casca é a mesma. */
function loadReport(report: AcervoReportId): Promise<ReportSheetEntry> {
  if (report === "inventory-sets") {
    return readSetInventoryReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: setInventoryIncompleteText(r.data.report.incompleteReason),
            sheet: <AcervoSetInventorySheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  return readSetSummaryReport().then((r) =>
    r.status === "ready"
      ? {
          status: "ready",
          incomplete: setSummaryIncompleteText(r.data.report.incompleteReason),
          sheet: <AcervoSetSummarySheet report={r.data.report} issuedAt={r.data.issuedAt} />,
        }
      : { status: "error" },
  );
}

/**
 * V1-14 R1-B — relatório do Meu acervo em SOBREPOSIÇÃO: 01 "Inventário resumido por Card Set"
 * (`readSetSummaryReport`: 5160/5159) e 02 "Inventário detalhado por Card Set"
 * (`readSetInventoryReport`: 5160/5159/3983) — só o titular, somente leitura. Casca, cabeçalho
 * funcional e impressão: `ReportSheetOverlay`.
 */
export function AcervoReportOverlay({ report, onClose }: { report: AcervoReportId; onClose: () => void }) {
  const entry = acervoReport(report);
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <Library aria-hidden="true" />
          Relatório do acervo
        </>
      }
      title={entry.title}
      context={`Meu acervo · ${entry.purpose}`}
      errorNote="Nada foi alterado no seu acervo."
      load={() => loadReport(report)}
      onClose={onClose}
    />
  );
}
