"use client";

import { ClipboardCheck, ListX } from "lucide-react";
import { type PokedexSpeciesReportResult, readPokedexSpeciesReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { pokedexReportIncompleteText } from "@/lib/reports/pokedex-species-report";
import { POKEDEX_CHECKLIST_TITLE, POKEDEX_MISSING_TITLE, type PokedexSheetMode, PokedexSpeciesSheet } from "./pokedex-species-report";
import { preparePrintJpegs } from "./print-jpeg-images";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

/** Arte da espécie impressa com ~16 mm: 240 px ≈ 380 dpi. */
const SPECIES_PRINT_WIDTH = 240;

/** Uma leitura por coleção por vez (os dois relatórios usam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<PokedexSpeciesReportResult>>();
function readOnce(collectionId: string): Promise<PokedexSpeciesReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readPokedexSpeciesReport({ collectionId }));
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
export function pokedexSpeciesEntry(mode: PokedexSheetMode, result: PokedexSpeciesReportResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    return {
      status: "ready",
      incomplete: pokedexReportIncompleteText(data.report.incompleteReason),
      sheet: <PokedexSpeciesSheet mode={mode} collectionName={data.collection.name} report={data.report} issuedAt={data.issuedAt} />,
      preparePrint: (onProgress) => preparePrintJpegs("[data-pokedex-report] img[data-print-jpeg-species]", SPECIES_PRINT_WIDTH, onProgress),
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? { status: "ready", incomplete: "Este relatório existe para coleções Pokédex.", sheet: unavailableSheet("Relatório indisponível para esta coleção", "Este relatório existe para coleções Pokédex.") }
    : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * F2-2 (D7 §4q) — "Checklist da Pokédex" e "Espécies faltantes" em SOBREPOSIÇÃO à coleção (casca
 * única dos relatórios contextuais). Somente leitura, só o titular; impressão A4.
 */
export function PokedexSpeciesOverlay({ collectionId, mode, onClose }: { collectionId: string; mode: PokedexSheetMode; onClose: () => void }) {
  const checklist = mode === "checklist";
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          {checklist ? <ClipboardCheck aria-hidden="true" /> : <ListX aria-hidden="true" />}
          Relatório da Pokédex
        </>
      }
      title={checklist ? POKEDEX_CHECKLIST_TITLE : POKEDEX_MISSING_TITLE}
      context={checklist ? "Pokédex · espécies do objetivo, por geração" : "Pokédex · espécies ainda não atendidas e a situação no seu acervo"}
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then((result) => pokedexSpeciesEntry(mode, result))}
      onClose={onClose}
    />
  );
}
