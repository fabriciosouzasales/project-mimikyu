"use client";

import { useRef, useState } from "react";
import { BarChart3 } from "lucide-react";
import { ActionCapsule } from "@/components/ui/action-capsule";
import capsuleStyles from "@/components/ui/action-capsule.module.css";
import { type LocationsReportId, locationsReportMenuItems } from "@/lib/reports/locations-reports";
import { BinderOccupancyOverlay } from "./binder-occupancy-overlay";
import { LocationDistributionOverlay } from "./location-distribution-overlay";
import { ReportMenu } from "./report-menu";

/**
 * Ação "Relatórios" do cabeçalho de Meus Locais de Armazenamento (V1-14, bloco
 * Locais), no mesmo padrão de Meu acervo e Minhas coleções: cápsula de vidro →
 * menu compacto ("De Meus locais") → relatório em SOBREPOSIÇÃO, com a página
 * montada atrás. O Inventário do Local continua sendo emitido no painel do local.
 */
export function LocationsReportsAction() {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [open, setOpen] = useState<LocationsReportId | null>(null);

  return (
    <ActionCapsule label="Ações de Meus locais">
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
        contextLabel="De Meus locais"
        items={locationsReportMenuItems()}
        triggerRef={triggerRef}
        open={menuOpen}
        onOpenChange={setMenuOpen}
        onSelect={(id) => {
          if (id === "distribution" || id === "binders") setOpen(id);
        }}
      />
      {open === "distribution" ? <LocationDistributionOverlay onClose={() => setOpen(null)} /> : null}
      {open === "binders" ? <BinderOccupancyOverlay onClose={() => setOpen(null)} /> : null}
    </ActionCapsule>
  );
}
