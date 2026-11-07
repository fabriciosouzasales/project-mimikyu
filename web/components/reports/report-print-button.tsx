"use client";

import { useState } from "react";
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
 *
 * `prepare` (opcional; R1-G): preparo assíncrono antes de abrir a impressão — hoje, carregar as
 * miniaturas sob demanda de um relatório extenso, com progresso real ("Preparando imagens X/Y").
 * Se algo faltar, a impressão não abre; um novo clique tenta de novo só o que falta. Sem
 * `prepare`, o comportamento é o de sempre (relatórios anteriores).
 */
export function ReportPrintButton({
  ready,
  reason,
  prepare,
}: {
  ready: boolean;
  reason: string | null;
  /** Resolve `true` quando a folha está pronta; `false` = não abrir a impressão (aviso ao lado). */
  prepare?: (onProgress: (progress: { ready: number; total: number }) => void) => Promise<boolean>;
}) {
  const [preparing, setPreparing] = useState(false);
  const [prepareFailed, setPrepareFailed] = useState(false);
  const [progress, setProgress] = useState<{ ready: number; total: number } | null>(null);
  return (
    <span className={styles.printWrap}>
      <button
        type="button"
        className={styles.printButton}
        aria-disabled={!ready || preparing || undefined}
        aria-busy={preparing || undefined}
        aria-describedby={!ready && reason ? "report-print-reason" : undefined}
        onClick={() => {
          if (!ready) return;
          // Data/hora efetiva da impressão no rodapé institucional (o `beforeprint` regrava o mesmo texto).
          stampPrintFooter();
          if (preparing) return;
          const open = () => {
            if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined).finally(() => window.print());
            else window.print();
          };
          if (!prepare) {
            open();
            return;
          }
          setPreparing(true);
          setPrepareFailed(false);
          void prepare(setProgress)
            .catch(() => false)
            .then((ok) => {
              setPreparing(false);
              if (!ok) {
                setPrepareFailed(true);
                return;
              }
              stampPrintFooter();
              open();
            });
        }}
      >
        <Printer className="h-4 w-4" aria-hidden="true" />
        {preparing ? (progress && progress.total > 0 ? `Preparando imagens ${progress.ready}/${progress.total}` : "Preparando imagens…") : "Imprimir"}
      </button>
      {preparing && progress && progress.total > 0 ? (
        <span className="sr-only" role="status" aria-live="polite">
          {`Preparando imagens ${progress.ready} de ${progress.total}`}
        </span>
      ) : null}
      {ready && prepareFailed && !preparing ? (
        <span className={styles.printReason} role="status">
          {progress && progress.total > 0
            ? `${progress.total - progress.ready} de ${progress.total} miniaturas não carregaram. Verifique a conexão e clique em Imprimir para tentar de novo só as que faltam.`
            : "Algumas miniaturas não carregaram. Verifique a conexão e clique em Imprimir para tentar de novo só as que faltam."}
        </span>
      ) : null}
      {!ready && reason ? (
        <span id="report-print-reason" className={styles.printReason}>
          {reason}
        </span>
      ) : null}
    </span>
  );
}
