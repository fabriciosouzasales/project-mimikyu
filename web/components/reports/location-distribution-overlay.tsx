"use client";

import { PieChart } from "lucide-react";
import { readLocationDistribution } from "@/app/colecoes/locais/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import {
  LOCATION_DISTRIBUTION_TITLE,
  buildLocationDistribution,
  locationDistributionIncompleteText,
} from "@/lib/reports/location-distribution";
import { LOCATIONS_REPORT_PURPOSE } from "@/lib/reports/locations-reports";
import { FitSheet } from "./fit-sheet";
import { LocationDistributionSheet } from "./location-distribution-report";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

type DistributionResult = Awaited<ReturnType<typeof readLocationDistribution>>;

/** Uma leitura por vez; nada em cache depois (cada abertura é uma fotografia nova). */
const readOnce = shareInFlight(() => readLocationDistribution());

/** Resultado da leitura → entrada da casca (exportada para teste). Incompleto → impressão bloqueada. */
export function locationDistributionEntry(result: DistributionResult): ReportSheetEntry {
  if (!result.ok) return { status: "error" };
  const { locations, summary, readComplete } = result.data;
  const report = buildLocationDistribution({ locations, summary, readComplete });
  return {
    status: "ready",
    incomplete: locationDistributionIncompleteText(report.incompleteReason),
    // Celular: a folha A4 inteira cabe na largura da tela (mesmo padrão do Inventário do Local; impressão intacta).
    sheet: (
      <FitSheet>
        <LocationDistributionSheet report={report} issuedAt={result.issuedAt} />
      </FitSheet>
    ),
  };
}

/**
 * V1-14 — bloco Locais — "Distribuição do Acervo por Local" em SOBREPOSIÇÃO a
 * Meus locais, na casca única dos relatórios (foco, Esc, tela cheia, impressão
 * A4 bloqueada quando incompleto). Global: não depende do local aberto nem dos
 * filtros da página. Somente leitura; só o titular (5219).
 */
export function LocationDistributionOverlay({ onClose }: { onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <PieChart aria-hidden="true" />
          Relatório de Meus locais
        </>
      }
      title={LOCATION_DISTRIBUTION_TITLE}
      context={`Meus locais · ${LOCATIONS_REPORT_PURPOSE}`}
      errorNote="Nada foi alterado no seu acervo nem nos seus locais."
      load={() => readOnce().then(locationDistributionEntry)}
      onClose={onClose}
    />
  );
}
