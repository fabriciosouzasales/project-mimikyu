"use client";

import { LibraryBig } from "lucide-react";
import { readCollectionDistributionReport } from "@/app/colecoes/colecoes/relatorios/actions";
import { collectionDistributionIncompleteText } from "@/lib/reports/collection-distribution";
import { type LibraryReportId, libraryReport } from "@/lib/reports/library-reports";
import { CollectionDistributionSheet } from "./collection-distribution-report";
// Celular: a folha A4 inteira cabe na largura da tela (FitSheet — só na tela; a impressão não muda).
import { FitSheet } from "./fit-sheet";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

function loadReport(): Promise<ReportSheetEntry> {
  return readCollectionDistributionReport().then((r) =>
    r.status === "ready"
      ? {
          status: "ready",
          incomplete: collectionDistributionIncompleteText(r.data.report.incompleteReason),
          sheet: <FitSheet><CollectionDistributionSheet report={r.data.report} issuedAt={r.data.issuedAt} /></FitSheet>,
        }
      : { status: "error" },
  );
}

/**
 * V1-14 R1-B — relatório da página Minhas coleções em SOBREPOSIÇÃO: "Distribuição do Acervo por
 * coleção" (`readCollectionDistributionReport`: 5160/5182/5159; só o titular, somente leitura).
 * Mesma casca e impressão dos relatórios do Meu acervo (`ReportSheetOverlay`); a estante
 * continua montada atrás.
 */
export function LibraryReportOverlay({ report, onClose }: { report: LibraryReportId; onClose: () => void }) {
  const entry = libraryReport(report);
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <LibraryBig aria-hidden="true" />
          Relatório de Minhas coleções
        </>
      }
      title={entry.title}
      context={`Minhas coleções · ${entry.purpose}`}
      errorNote="Nada foi alterado no seu acervo nem nas suas coleções."
      load={loadReport}
      onClose={onClose}
    />
  );
}
