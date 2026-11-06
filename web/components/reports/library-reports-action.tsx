"use client";

import { useRef, useState } from "react";
import { BarChart3 } from "lucide-react";
import { ActionCapsule } from "@/components/ui/action-capsule";
import capsuleStyles from "@/components/ui/action-capsule.module.css";
import { type LibraryReportId, LIBRARY_REPORT_CATALOG, libraryReportMenuItems } from "@/lib/reports/library-reports";
import { LibraryReportOverlay } from "./library-report-overlay";
import { ReportMenu } from "./report-menu";

/**
 * Ação "Relatórios" do cabeçalho de Minhas coleções (V1-14 R1-B), no mesmo padrão do Meu acervo e
 * da coleção: cápsula de vidro → menu compacto ("De Minhas coleções", distinto do "Desta coleção"
 * das coleções individuais) → relatório em SOBREPOSIÇÃO, com a estante montada atrás.
 */
export function LibraryReportsAction() {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [report, setReport] = useState<LibraryReportId | null>(null);

  return (
    <ActionCapsule label="Ações de Minhas coleções">
      <button
        ref={triggerRef}
        type="button"
        className={capsuleStyles.item}
        aria-haspopup="menu"
        aria-expanded={menuOpen}
        onClick={() => setMenuOpen((value) => !value)}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" && !menuOpen) {
            event.preventDefault();
            setMenuOpen(true);
          }
        }}
      >
        <BarChart3 aria-hidden="true" />
        <span className={capsuleStyles.label}>Relatórios</span>
      </button>
      <ReportMenu
        contextLabel="De Minhas coleções"
        items={libraryReportMenuItems()}
        triggerRef={triggerRef}
        open={menuOpen}
        onOpenChange={setMenuOpen}
        onSelect={(id) => {
          const chosen = LIBRARY_REPORT_CATALOG.find((entry) => entry.id === id && entry.implemented);
          if (chosen) setReport(chosen.id);
        }}
      />
      {report ? <LibraryReportOverlay report={report} onClose={() => setReport(null)} /> : null}
    </ActionCapsule>
  );
}
