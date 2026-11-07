"use client";

import { Library } from "lucide-react";
import {
  readAcervoValueReport,
  readDistributionReport,
  readDuplicatesReport,
  readFavoritesReport,
  readSetInventoryReport,
  readSetSummaryReport,
  readTopCardsReport,
  readWishlistReport,
} from "@/app/colecoes/acervo/relatorios/actions";
import { type AcervoReportId, acervoReport } from "@/lib/reports/acervo-reports";
import { setInventoryIncompleteText } from "@/lib/reports/acervo-set-inventory";
import { setSummaryIncompleteText } from "@/lib/reports/acervo-set-summary";
import { distributionIncompleteText } from "@/lib/reports/distribution";
import { duplicatesIncompleteText } from "@/lib/reports/duplicates";
import { favoritesIncompleteText } from "@/lib/reports/favorites-report";
import { topCardsIncompleteText } from "@/lib/reports/top-cards";
import { wishlistIncompleteText } from "@/lib/reports/wishlist-report";
import { AcervoValueSheet } from "./acervo-value-report";
import { DistributionSheet } from "./distribution-report";
import { DuplicatesSheet } from "./duplicates-report";
import { preparePrintImages } from "./print-image-gate";
import { FavoritesReportSheet } from "./favorites-report";
import { TopCardsSheet } from "./top-cards-report";
import { WishlistReportSheet } from "./wishlist-report";
import { AcervoSetInventorySheet } from "./acervo-set-inventory-report";
import { AcervoSetSummarySheet } from "./acervo-set-summary-report";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";
import { shareInFlight } from "@/lib/reports/in-flight";

/**
 * R1-G: uma leitura de "Cartas repetidas" por vez — a carga em dobro do Strict Mode (e qualquer
 * pedido equivalente enquanto a leitura corre) reaproveita a MESMA operação; nada fica em cache
 * depois que ela termina (cada abertura lê de novo).
 */
const readDuplicatesOnce = shareInFlight(() => readDuplicatesReport());
/** R1-H: mesma proteção — uma leitura da Distribuição por vez, sem cache depois. */
const readDistributionOnce = shareInFlight(() => readDistributionReport());

/** Cada relatório do Meu acervo tem leitura e folha próprias; a casca é a mesma. */
function loadReport(report: AcervoReportId): Promise<ReportSheetEntry> {
  if (report === "inventory-sets") {
    return readSetInventoryReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: setInventoryIncompleteText(r.data.report.incompleteReason),
            sheet: <AcervoSetInventorySheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  if (report === "favorites") {
    return readFavoritesReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: favoritesIncompleteText(r.data.report.incompleteReason),
            sheet: <FavoritesReportSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  if (report === "wishlist") {
    return readWishlistReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: wishlistIncompleteText(r.data.report.incompleteReason),
            sheet: <WishlistReportSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  if (report === "duplicates") {
    return readDuplicatesOnce().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: duplicatesIncompleteText(r.data.report.incompleteReason),
            sheet: <DuplicatesSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
            // Lista extensa: miniaturas sob demanda na tela, preparadas antes de abrir a impressão.
            preparePrint: (onProgress) => preparePrintImages(onProgress),
          }
        : { status: "error" },
    );
  }
  if (report === "distribution") {
    return readDistributionOnce().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: distributionIncompleteText(r.data.report.incompleteReason),
            sheet: <DistributionSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  if (report === "top") {
    return readTopCardsReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: topCardsIncompleteText(r.data.report.incompleteReason),
            sheet: <TopCardsSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  if (report === "value") {
    return readAcervoValueReport().then((r) =>
      r.status === "ready"
        ? {
            status: "ready",
            incomplete: setInventoryIncompleteText(r.data.report.incompleteReason),
            sheet: <AcervoValueSheet report={r.data.report} issuedAt={r.data.issuedAt} />,
          }
        : { status: "error" },
    );
  }
  return readSetSummaryReport().then((r) =>
    r.status === "ready"
      ? {
          status: "ready",
          incomplete: setSummaryIncompleteText(r.data.report.incompleteReason),
          sheet: <AcervoSetSummarySheet report={r.data.report} issuedAt={r.data.issuedAt} />,
        }
      : { status: "error" },
  );
}

/**
 * V1-14 R1-B — relatório do Meu acervo em SOBREPOSIÇÃO: 01 "Inventário resumido por Card Set"
 * (`readSetSummaryReport`: 5160/5159) e 02 "Inventário detalhado por Card Set"
 * (`readSetInventoryReport`: 5160/5159/3989) e 03 "Valor estimado total" (R1-C, `readAcervoValueReport`:
 * mesma leitura do 02, projetada por Card Set) e 04 "Minhas favoritas" (R1-D, `readFavoritesReport`:
 * 5336 + referência por carta + posse) e 05 "Minha Lista de Desejos" (R1-E, `readWishlistReport`:
 * 5350/5351 + 3989 por variante distinta) e 06 "Top 10 cartas mais valiosas" (R1-F, `readTopCardsReport`:
 * 5160/5159 + 3989, mesma base do 03) e 07 "Cartas repetidas" (R1-G, `readDuplicatesReport`: mesma
 * leitura, grupos com 2+ exemplares) e 08 "Distribuição por Set, raridade e idioma" (R1-H,
 * `readDistributionReport`: mesma leitura + 5355) — só o titular, somente leitura. Casca, cabeçalho
 * funcional e impressão: `ReportSheetOverlay`.
 */
export function AcervoReportOverlay({ report, onClose }: { report: AcervoReportId; onClose: () => void }) {
  const entry = acervoReport(report);
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <Library aria-hidden="true" />
          Relatório do acervo
        </>
      }
      title={entry.title}
      context={`Meu acervo · ${entry.purpose}`}
      errorNote="Nada foi alterado no seu acervo."
      load={() => loadReport(report)}
      onClose={onClose}
    />
  );
}
