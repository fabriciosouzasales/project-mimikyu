"use client";

import { Library } from "lucide-react";
import { readAcervoValueReport, readFavoritesReport, readSetInventoryReport, readSetSummaryReport } from "@/app/colecoes/acervo/relatorios/actions";
import { type AcervoReportId, acervoReport } from "@/lib/reports/acervo-reports";
import { setInventoryIncompleteText } from "@/lib/reports/acervo-set-inventory";
import { setSummaryIncompleteText } from "@/lib/reports/acervo-set-summary";
import { favoritesIncompleteText } from "@/lib/reports/favorites-report";
import { AcervoValueSheet } from "./acervo-value-report";
import { FavoritesReportSheet } from "./favorites-report";
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
  if (report === "favorites") {
    return readFavoritesReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: favoritesIncompleteText(r.data.report.incompleteReason),
            sheet: <FavoritesReportSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  if (report === "value") {
    return readAcervoValueReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: setInventoryIncompleteText(r.data.report.incompleteReason),
            sheet: <AcervoValueSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
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
 * (`readSetInventoryReport`: 5160/5159/3989) e 03 "Valor estimado total" (R1-C, `readAcervoValueReport`:
 * mesma leitura do 02, projetada por Card Set) e 04 "Minhas favoritas" (R1-D, `readFavoritesReport`:
 * 5336 + referência por carta + posse) — só o titular, somente leitura. Casca, cabeçalho
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
