"use client";

import { Gem } from "lucide-react";
import { type RarityDistributionReportResult, readRarityDistributionReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { rarityDistributionIncompleteText } from "@/lib/reports/rarity-distribution";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";
import { RARITY_DISTRIBUTION_TITLE, RarityDistributionSheet } from "./rarity-distribution-report";

/** Uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<RarityDistributionReportResult>>();
function readOnce(collectionId: string): Promise<RarityDistributionReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readRarityDistributionReport({ collectionId }));
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

/** Resultado da leitura → entrada da casca (exportada para teste). Incompleto → impressão bloqueada (D7.8). */
export function rarityDistributionEntry(result: RarityDistributionReportResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    return {
      status: "ready",
      incomplete: rarityDistributionIncompleteText(data.report.incompleteReason),
      sheet: <RarityDistributionSheet collection={data.collection} kind={data.kind} report={data.report} logoUrl={data.logoUrl} issuedAt={data.issuedAt} />,
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? {
        status: "ready",
        incomplete: "A Distribuição por raridade existe para coleções de Set padrão e Master Set.",
        sheet: unavailableSheet("Relatório indisponível para esta coleção", "Nesta etapa, o relatório existe para coleções de Set padrão e Master Set."),
      }
    : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * V1-14 R2-G — "Distribuição por raridade" em SOBREPOSIÇÃO à coleção (casca única dos relatórios
 * contextuais — `ReportSheetOverlay`). Somente leitura, só o titular; impressão A4.
 */
export function RarityDistributionOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <Gem aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={RARITY_DISTRIBUTION_TITLE}
      context="Coleção · posições do objetivo por raridade da carta"
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then(rarityDistributionEntry)}
      onClose={onClose}
    />
  );
}
