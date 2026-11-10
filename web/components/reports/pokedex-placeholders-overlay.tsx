"use client";

import { Scissors } from "lucide-react";
import { type PokedexSpeciesReportResult, readPokedexSpeciesReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { POKEDEX_PLACEHOLDERS_TITLE, buildPlaceholderKit } from "@/lib/reports/pokedex-placeholders";
import { pokedexReportIncompleteText } from "@/lib/reports/pokedex-species-report";
import { PokedexPlaceholders } from "./pokedex-placeholders";
import { preparePrintJpegs } from "./print-jpeg-images";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

/** Arte impressa com ~37 mm: a WebP de galeria (320 px) já é a maior disponível — ≈ 220 dpi. */
const PLACEHOLDER_PRINT_WIDTH = 320;

/** Uma leitura por coleção por vez (a mesma do Checklist e das Espécies faltantes); nada em cache depois. */
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

/**
 * Resultado da leitura → entrada da casca (exportada para teste). Leitura incompleta (conferência da
 * F2-2) → impressão bloqueada: um kit com espécie faltando ou repetida desalinharia o fichário.
 */
export function pokedexPlaceholdersEntry(result: PokedexSpeciesReportResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    const kit = buildPlaceholderKit(data.report);
    if (kit.species === 0) {
      return { status: "ready", incomplete: "Esta Pokédex não tem espécies no objetivo.", sheet: unavailableSheet("Nenhuma espécie no objetivo", "Escolha as gerações da Pokédex em Ajustes.") };
    }
    return {
      status: "ready",
      incomplete: pokedexReportIncompleteText(data.report.incompleteReason),
      sheet: <PokedexPlaceholders collectionName={data.collection.name} kit={kit} issuedAt={data.issuedAt} />,
      preparePrint: (onProgress) => preparePrintJpegs("[data-pokedex-placeholders] img[data-print-jpeg-species]", PLACEHOLDER_PRINT_WIDTH, onProgress),
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? { status: "ready", incomplete: "Os placeholders existem para coleções Pokédex.", sheet: unavailableSheet("Indisponível para esta coleção", "Os Placeholders da Pokédex existem para coleções Pokédex.") }
    : { status: "ready", incomplete: "Este material não está disponível.", sheet: unavailableSheet("Este material não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * Placeholders da Pokédex (D7 §4q) em SOBREPOSIÇÃO à coleção — casca única dos relatórios contextuais
 * (acesso, foco, Esc, tela cheia, impressão bloqueada quando incompleto). Somente leitura; só o titular.
 */
export function PokedexPlaceholdersOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <Scissors aria-hidden="true" />
          Kit de fichário
        </>
      }
      title={POKEDEX_PLACEHOLDERS_TITLE}
      context="Pokédex · um placeholder recortável por espécie do objetivo, no tamanho da carta"
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then(pokedexPlaceholdersEntry)}
      onClose={onClose}
    />
  );
}
