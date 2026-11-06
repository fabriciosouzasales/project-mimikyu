"use client";

import { useRef, useState } from "react";
import { BarChart3 } from "lucide-react";
import { ActionCapsule } from "@/components/ui/action-capsule";
import capsuleStyles from "@/components/ui/action-capsule.module.css";
import { type AcervoReportId, ACERVO_REPORT_CATALOG, acervoReportMenuItems } from "@/lib/reports/acervo-reports";
import { AcervoReportOverlay } from "./acervo-report-overlay";
import { ReportMenu } from "./report-menu";

/**
 * Ação "Relatórios" do cabeçalho de Meu acervo (V1-14 R1-B), no mesmo padrão da coleção (R1-A):
 * cápsula de vidro → menu compacto ("Do acervo") → relatório em SOBREPOSIÇÃO. A página do Acervo
 * fica montada atrás — filtros (na URL), página da galeria e rolagem voltam exatamente como
 * estavam ao fechar. Não existe página central de relatórios (D7.1).
 */
export function AcervoReportsAction({ totalCopies }: { totalCopies: number }) {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [report, setReport] = useState<AcervoReportId | null>(null);

  return (
    <ActionCapsule label="Ações do acervo">
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
        contextLabel="Do acervo"
        items={acervoReportMenuItems({ totalCopies })}
        triggerRef={triggerRef}
        open={menuOpen}
        onOpenChange={setMenuOpen}
        onSelect={(id) => {
          const chosen = ACERVO_REPORT_CATALOG.find((entry) => entry.id === id && entry.implemented);
          if (chosen) setReport(chosen.id);
        }}
      />
      {report ? <AcervoReportOverlay report={report} onClose={() => setReport(null)} /> : null}
    </ActionCapsule>
  );
}
