"use client";

import { BookOpen } from "lucide-react";
import { type CardBookletResult, readCardBooklet } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { bookletIncompleteText } from "@/lib/reports/card-booklet";
import { shareInFlight } from "@/lib/reports/in-flight";
import { CardBooklet } from "./card-booklet";
import { prepareBookletPrint } from "./booklet-print-images";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

/** Uma leitura por coleção por vez (Strict Mode e pedidos equivalentes reaproveitam a mesma); nada em cache depois. */
const inFlight = new Map<string, () => Promise<CardBookletResult>>();
function readOnce(collectionId: string): Promise<CardBookletResult> {
  let shared = inFlight.get(collectionId);
  if (!shared) {
    shared = shareInFlight(() => readCardBooklet({ collectionId }));
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
 * Resultado da leitura → entrada da casca (exportada para teste). Incompleto → impressão bloqueada;
 * pronto → o Imprimir converte as cartas para JPEG de impressão e prepara todas as imagens (R1-G).
 */
export function cardBookletEntry(result: CardBookletResult): ReportSheetEntry {
  if (result.ok) {
    const { data } = result;
    return {
      status: "ready",
      incomplete: bookletIncompleteText(data.report.incompleteReason),
      sheet: <CardBooklet collection={data.collection} kind={data.kind} report={data.report} logoUrl={data.logoUrl} issuedOn={data.issuedOn} />,
      // Cartas em JPEG no tamanho de impressão antes de abrir o PDF (o Chrome não embute WebP).
      preparePrint: (onProgress) => prepareBookletPrint(onProgress),
    };
  }
  if (result.reason === "error") return { status: "error" };
  return result.reason === "unavailable"
    ? {
        status: "ready",
        incomplete: "O Caderno de Cartas existe para coleções de Set padrão e Master Set.",
        sheet: unavailableSheet("Caderno indisponível para esta coleção", "O Caderno de Cartas existe para coleções de Set padrão e Master Set."),
      }
    : { status: "ready", incomplete: "Este caderno não está disponível.", sheet: unavailableSheet("Este caderno não está disponível", "Nada foi alterado na sua coleção.") };
}

/**
 * V1-14 — Caderno de Cartas da Coleção (D7 §4p) em SOBREPOSIÇÃO à coleção. Usa a casca dos relatórios
 * contextuais (acesso, foco, Esc, tela cheia, impressão bloqueada quando incompleto), mas a peça é
 * editorial: capa, abertura, páginas de cartas e encerramento. Somente leitura; só o titular.
 */
export function CardBookletOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <BookOpen aria-hidden="true" />
          Caderno da coleção
        </>
      }
      title="Caderno de Cartas"
      context="O Card Set completo, carta por carta, com a sua coleção como detalhe"
      errorNote="Nada foi alterado na sua coleção."
      load={() => readOnce(collectionId).then(cardBookletEntry)}
      onClose={onClose}
    />
  );
}
