"use client";

import { useRef, useState } from "react";
import { BarChart3 } from "lucide-react";
import type { ReportMenuItem } from "@/lib/reports/collection-checklist";
import { CollectionReportOverlay } from "./collection-report-overlay";
import { ReportMenu } from "./report-menu";

/**
 * Ação "Relatórios" da cápsula do cabeçalho da coleção (V1-14 R1-A UX REDIRECTION-02).
 *
 * Gatilho → menu compacto (`ReportMenu`) → o relatório escolhido abre em SOBREPOSIÇÃO sobre a
 * coleção (`CollectionReportOverlay`, casca do Fichário digital): a página de origem fica
 * montada atrás, com rolagem e estado intactos, e volta exatamente como estava ao fechar.
 * A rota `/relatorios/checklist` continua existindo só como acesso direto.
 */
export function CollectionReportsAction({
  collectionId,
  items,
  className,
  labelClassName,
}: {
  collectionId: string;
  items: ReportMenuItem[];
  className?: string;
  labelClassName?: string;
}) {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [report, setReport] = useState<string | null>(null);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        className={className}
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
        <span className={labelClassName}>Relatórios</span>
      </button>
      <ReportMenu
        contextLabel="Desta coleção"
        items={items}
        triggerRef={triggerRef}
        open={menuOpen}
        onOpenChange={setMenuOpen}
        onSelect={setReport}
      />
      {report === "checklist" ? <CollectionReportOverlay collectionId={collectionId} onClose={() => setReport(null)} /> : null}
    </>
  );
}
