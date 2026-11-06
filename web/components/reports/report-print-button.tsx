"use client";

import { Printer } from "lucide-react";
import { stampPrintFooter } from "./print-footer";
import styles from "./report.module.css";

/**
 * "Imprimir" oficial dos relatórios contextuais (V1-14 D7.6/D7.7). Mesmo mecanismo da Central
 * de Relatórios (`window.print()`, `RelatorioPrintButton`) — sem motor de PDF próprio. A
 * diferença é a guarda de integridade: o servidor já preparou o conjunto INTEIRO do filtro
 * antes de renderizar; se ele não ficou completo, o botão fica indisponível com o motivo
 * (e a folha impressa por Ctrl+P mostra só o aviso, nunca uma lista parcial como integral).
 * Em tela cheia (sobreposição), sai da tela cheia antes de abrir a impressão.
 */
export function ReportPrintButton({ ready, reason }: { ready: boolean; reason: string | null }) {
  return (
    <span className={styles.printWrap}>
      <button
        type="button"
        className={styles.printButton}
        aria-disabled={!ready || undefined}
        aria-describedby={!ready && reason ? "report-print-reason" : undefined}
        onClick={() => {
          if (!ready) return;
          // Data/hora efetiva da impressão no rodapé institucional (o `beforeprint` regrava o mesmo texto).
          stampPrintFooter();
          if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined).finally(() => window.print());
          else window.print();
        }}
      >
        <Printer className="h-4 w-4" aria-hidden="true" />
        Imprimir
      </button>
      {!ready && reason ? (
        <span id="report-print-reason" className={styles.printReason}>
          {reason}
        </span>
      ) : null}
    </span>
  );
}
