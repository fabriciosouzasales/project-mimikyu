"use client";

import { ListX } from "lucide-react";
import { type MissingCardsReportResult, readMissingCardsReport } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { missingIncompleteText } from "@/lib/reports/missing-cards";
import { MISSING_TITLE, MissingCardsSheet } from "./missing-cards-report";
import { preparePrintImages } from "./print-image-gate";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

/**
 * R2-B: uma leitura por coleção por vez — a carga em dobro do Strict Mode (e qualquer pedido
 * equivalente enquanto a leitura corre) reaproveita a MESMA operação; nada fica em cache depois.
 */
const inFlight = new Map<string, () => Promise<MissingCardsReportResult>>();
function readOnce(collectionId: string): Promise<MissingCardsReportResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readMissingCardsReport({ collectionId }));
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

function loadMissing(collectionId: string): Promise<ReportSheetEntry> {
  return readOnce(collectionId).then((result): ReportSheetEntry => {
    if (result.ok) {
      const { data } = result;
      return {
        status: "ready",
        incomplete: missingIncompleteText(data.report.incompleteReason),
        sheet: <MissingCardsSheet collection={data.collection} report={data.report} logoUrl={data.logoUrl} issuedAt={data.issuedAt} />,
        // Miniaturas impressas (mecanismo da R1-G): só as pendentes, 6 simultâneas, progresso "Preparando imagens X/Y".
        preparePrint: data.report.state === "list" ? (onProgress) => preparePrintImages(onProgress) : undefined,
      };
    }
    if (result.reason === "error") return { status: "error" };
    // Indisponível ou não encontrada: estado explicado, impressão bloqueada, nada de terceiros exposto.
    return result.reason === "unavailable"
      ? {
          status: "ready",
          incomplete: "Cartas faltantes existe para coleções de Set padrão e Master Set.",
          sheet: unavailableSheet("Cartas faltantes indisponível para esta coleção", "Nesta etapa, o relatório existe para coleções de Set padrão e Master Set."),
        }
      : { status: "ready", incomplete: "Este relatório não está disponível.", sheet: unavailableSheet("Este relatório não está disponível", "Nada foi alterado na sua coleção.") };
  });
}

/**
 * V1-14 R2-B — "Cartas faltantes" em SOBREPOSIÇÃO à coleção: a casca única dos relatórios
 * contextuais (`ReportSheetOverlay` — véu, foco preso e devolvido, Tela cheia, Imprimir, Fechar,
 * Esc; impressão só da folha; incompleto → impressão bloqueada com o motivo).
 */
export function MissingCardsOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <ListX aria-hidden="true" />
          Relatório da coleção
        </>
      }
      title={MISSING_TITLE}
      context="Coleção · o que falta para completar, e o que já está livre no seu acervo"
      errorNote="Nada foi alterado na sua coleção."
      load={() => loadMissing(collectionId)}
      onClose={onClose}
    />
  );
}
