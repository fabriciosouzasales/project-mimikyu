"use client";

import { Heart } from "lucide-react";
import { type SetFavoritesReportResult, readSetFavoritesReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { favoritesIncompleteText } from "@/lib/reports/favorites-report";
import { shareInFlight } from "@/lib/reports/in-flight";
import { setFavoritesIncompleteText } from "@/lib/reports/set-favorites";
import { preparePrintImages } from "./print-image-gate";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";
import { SET_FAVORITES_TITLE, SetFavoritesSheet } from "./set-favorites-report";

/** R2-D: uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<SetFavoritesReportResult>>();
function readOnce(collectionId: string): Promise<SetFavoritesReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readSetFavoritesReport({ collectionId }));
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

function loadSetFavorites(collectionId: string): Promise<ReportSheetEntry> {
  return readOnce(collectionId).then((result): ReportSheetEntry => {
    if (result.ok) {
      const { data } = result;
      return {
        status: "ready",
        incomplete: setFavoritesIncompleteText(data.report.incompleteReason, favoritesIncompleteText),
        sheet: <SetFavoritesSheet collection={data.collection} kind={data.kind} report={data.report} logoUrl={data.logoUrl} issuedAt={data.issuedAt} />,
        // Miniaturas impressas (mecanismo da R1-G): só as pendentes, 6 simultâneas, progresso "Preparando imagens X/Y".
        preparePrint: data.report.state !== "empty" ? (onProgress) => preparePrintImages(onProgress) : undefined,
      };
    }
    if (result.reason === "error") return { status: "error" };
    return result.reason === "unavailable"
      ? {
          status: "ready",
          incomplete: "Cartas favoritas do Card Set existe para coleções de Set padrão e Master Set.",
          sheet: unavailableSheet("Relatório indisponível para esta coleção", "Nesta etapa, o relatório existe para coleções de Set padrão e Master Set, que têm um Card Set de referência."),
        }
      : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
  });
}

/**
 * V1-14 R2-D — "Cartas favoritas do Card Set" em SOBREPOSIÇÃO à coleção (casca única dos
 * relatórios contextuais — `ReportSheetOverlay`). Somente leitura; incompleto ou provisório →
 * impressão bloqueada com o motivo.
 */
export function SetFavoritesOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <Heart aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={SET_FAVORITES_TITLE}
      context="Coleção · suas cartas favoritas deste Card Set, com a posse no acervo e a referência NM"
      errorNote="Nada foi alterado na sua coleção nem nas suas favoritas."
      load={() => loadSetFavorites(collectionId)}
      onClose={onClose}
    />
  );
}
