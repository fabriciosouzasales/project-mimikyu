"use client";

import { PieChart } from "lucide-react";
import { type CollectionCompositionResult, readCollectionComposition } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { COLLECTION_COMPOSITION_TITLE, compositionIncompleteText } from "@/lib/reports/collection-composition";
import { shareInFlight } from "@/lib/reports/in-flight";
import { CollectionCompositionSheet } from "./collection-composition-report";
// Celular: a folha A4 inteira cabe na largura da tela (FitSheet — só na tela; a impressão não muda).
import { FitSheet } from "./fit-sheet";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

/** Uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<CollectionCompositionResult>>();
function readOnce(collectionId: string): Promise<CollectionCompositionResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readCollectionComposition({ collectionId }));
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

/** Resultado da leitura → entrada da casca (exportada para teste). Incompleto → impressão bloqueada. */
export function collectionCompositionEntry(result: CollectionCompositionResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    return {
      status: "ready",
      incomplete: compositionIncompleteText(data.report.incompleteReason),
      sheet: <FitSheet><CollectionCompositionSheet collectionName={data.collection.name} kind={data.kind} satisfiedSpecies={data.satisfiedSpecies} report={data.report} issuedAt={data.issuedAt} /></FitSheet>,
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? {
        status: "ready",
        incomplete: "A Composição da coleção não está disponível para esta coleção.",
        sheet: unavailableSheet("Relatório indisponível para esta coleção", "A Composição da coleção existe para coleções Pokédex e coleções livres."),
      }
    : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * F2-3 (D7 §4q) — "Composição da coleção" em SOBREPOSIÇÃO à coleção (casca única dos relatórios
 * contextuais). Somente leitura, só o titular; impressão A4 sem imagens.
 */
export function CollectionCompositionOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <PieChart aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={COLLECTION_COMPOSITION_TITLE}
      context="Coleção · como os exemplares alocados se distribuem por Card Set, raridade e idioma"
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then(collectionCompositionEntry)}
      onClose={onClose}
    />
  );
}
