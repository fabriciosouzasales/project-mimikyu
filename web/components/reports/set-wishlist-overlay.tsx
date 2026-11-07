"use client";

import { Bookmark } from "lucide-react";
import { type SetWishlistReportResult, readSetWishlistReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { setWishlistIncompleteText } from "@/lib/reports/set-wishlist";
import { wishlistIncompleteText } from "@/lib/reports/wishlist-report";
import { preparePrintImages } from "./print-image-gate";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";
import { SET_WISHLIST_TITLE, SetWishlistSheet } from "./set-wishlist-report";

/** R2-C: uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<SetWishlistReportResult>>();
function readOnce(collectionId: string): Promise<SetWishlistReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readSetWishlistReport({ collectionId }));
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

function loadSetWishlist(collectionId: string): Promise<ReportSheetEntry> {
  return readOnce(collectionId).then((result): ReportSheetEntry => {
    if (result.ok) {
      const { data } = result;
      return {
        status: "ready",
        incomplete: setWishlistIncompleteText(data.report.incompleteReason, wishlistIncompleteText),
        sheet: <SetWishlistSheet collection={data.collection} kind={data.kind} report={data.report} logoUrl={data.logoUrl} issuedAt={data.issuedAt} />,
        // Miniaturas impressas (mecanismo da R1-G): só as pendentes, 6 simultâneas, progresso "Preparando imagens X/Y".
        preparePrint: data.report.state !== "empty" ? (onProgress) => preparePrintImages(onProgress) : undefined,
      };
    }
    if (result.reason === "error") return { status: "error" };
    return result.reason === "unavailable"
      ? {
          status: "ready",
          incomplete: "Cartas desejadas do Card Set existe para coleções de Set padrão e Master Set.",
          sheet: unavailableSheet("Relatório indisponível para esta coleção", "Nesta etapa, o relatório existe para coleções de Set padrão e Master Set, que têm um Card Set de referência."),
        }
      : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
  });
}

/**
 * V1-14 R2-C — "Cartas desejadas do Card Set" em SOBREPOSIÇÃO à coleção (casca única dos relatórios
 * contextuais — `ReportSheetOverlay`). Somente leitura; incompleto → impressão bloqueada com o motivo.
 */
export function SetWishlistOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <Bookmark aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={SET_WISHLIST_TITLE}
      context="Coleção · seus desejos deste Card Set, com a situação no acervo e a referência NM"
      errorNote="Nada foi alterado na sua coleção nem na sua Lista de Desejos."
      load={() => loadSetWishlist(collectionId)}
      onClose={onClose}
    />
  );
}
