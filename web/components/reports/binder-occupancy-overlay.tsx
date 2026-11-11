"use client";

import { BookOpen } from "lucide-react";
import { readBinderOccupancy } from "@/app/colecoes/locais/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { BINDER_OCCUPANCY_TITLE, binderOccupancyIncompleteText, buildBinderOccupancy } from "@/lib/reports/binder-occupancy";
import { BINDER_OCCUPANCY_PURPOSE } from "@/lib/reports/locations-reports";
import { BinderOccupancySheet } from "./binder-occupancy-report";
import { FitSheet } from "./fit-sheet";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

type OccupancyResult = Awaited<ReturnType<typeof readBinderOccupancy>>;

/** Uma leitura por vez; nada em cache depois (cada abertura é uma fotografia nova). */
const readOnce = shareInFlight(() => readBinderOccupancy());

/** Resultado da leitura → entrada da casca (exportada para teste). Falha → erro; inconsistência → impressão bloqueada. */
export function binderOccupancyEntry(result: OccupancyResult): ReportSheetEntry {
  if (!result.ok) return { status: "error" };
  const report = buildBinderOccupancy({ binders: result.data.binders, readComplete: result.data.readComplete });
  return {
    status: "ready",
    incomplete: binderOccupancyIncompleteText(report.incompleteReason),
    // Celular: a folha A4 inteira cabe na largura da tela (padrão do bloco Locais; impressão intacta).
    sheet: (
      <FitSheet>
        <BinderOccupancySheet report={report} issuedAt={result.issuedAt} />
      </FitSheet>
    ),
  };
}

/**
 * V1-14 — bloco Locais — "Capacidade e Ocupação de Fichários" em SOBREPOSIÇÃO a
 * Meus locais, na casca única dos relatórios. Global; somente leitura; só o
 * titular (5219 + vínculo do fichário digital + 5245).
 */
export function BinderOccupancyOverlay({ onClose }: { onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <BookOpen aria-hidden="true" />
          Relatório de Meus locais
        </>
      }
      title={BINDER_OCCUPANCY_TITLE}
      context={`Meus locais · ${BINDER_OCCUPANCY_PURPOSE}`}
      errorNote="Nada foi alterado nos seus fichários nem no seu acervo."
      load={() => readOnce().then(binderOccupancyEntry)}
      onClose={onClose}
    />
  );
}
