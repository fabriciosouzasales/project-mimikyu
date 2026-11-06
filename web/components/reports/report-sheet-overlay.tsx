"use client";

import { type ReactNode, useCallback, useEffect, useId, useRef, useState } from "react";
import { AlertCircle, Maximize2, Minimize2, X } from "lucide-react";
import { BinderOverlayShell } from "@/components/colecoes/fichario/binder-overlay-shell";
import { Skeleton } from "@/components/ui/skeleton";
import { ReportPrintButton } from "./report-print-button";
import styles from "./report-overlay.module.css";

/** Estado de um relatório na sobreposição: cada relatório entrega a própria folha pronta. */
export type ReportSheetEntry = { status: "loading" } | { status: "error" } | { status: "ready"; incomplete: string | null; sheet: ReactNode };

export type ReportSheetOverlayProps = {
  /** Ícone + rótulo curto acima do título ("Relatório do acervo", "Relatório de Minhas coleções"). */
  eyebrow: ReactNode;
  title: string;
  /** Linha de contexto ("Meu acervo · finalidade"). */
  context: string;
  /** Mensagem do estado de erro ("Nada foi alterado no seu acervo."). */
  errorNote: string;
  load: () => Promise<ReportSheetEntry>;
  onClose: () => void;
};

/**
 * V1-14 R1-B — casca única dos relatórios de página em SOBREPOSIÇÃO (Meu acervo e Minhas
 * coleções), a mesma da R1-A (`BinderOverlayShell`: véu, foco preso e devolvido, fundo inerte,
 * rolagem travada sem perder a posição) e o mesmo cabeçalho funcional (Tela cheia, Imprimir,
 * Fechar). A página continua montada atrás e volta como estava. Cada relatório traz a sua
 * leitura (`load`) e a sua folha; impressão: `globals.css` (`[data-report-overlay]`) — sai só a
 * folha A4; incompleto ou não pronto → impressão bloqueada (D7.8).
 */
export function ReportSheetOverlay(props: ReportSheetOverlayProps) {
  const titleId = useId();
  return (
    <BinderOverlayShell labelledBy={titleId} onClose={props.onClose}>
      {(close) => <ReportSheet {...props} titleId={titleId} close={close} />}
    </BinderOverlayShell>
  );
}

function ReportSheet({ eyebrow, title, context, errorNote, load: loadReport, titleId, close }: ReportSheetOverlayProps & { titleId: string; close: () => void }) {
  const sheetRef = useRef<HTMLDivElement>(null);
  const [entry, setEntry] = useState<ReportSheetEntry>({ status: "loading" });
  const [fullscreen, setFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);
  const request = useRef(0);
  const loadRef = useRef(loadReport);
  loadRef.current = loadReport;
  const load = useCallback(() => {
    const id = ++request.current;
    setEntry({ status: "loading" });
    loadRef.current()
      .then((result) => {
        if (request.current === id) setEntry(result);
      })
      .catch(() => {
        if (request.current === id) setEntry({ status: "error" });
      });
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // Esc fecha (o navegador já usa o Esc para sair da tela cheia antes).
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented || document.fullscreenElement) return;
      event.preventDefault();
      close();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [close]);

  useEffect(() => {
    setCanFullscreen(typeof document.documentElement.requestFullscreen === "function");
    const onChange = () => setFullscreen(document.fullscreenElement === sheetRef.current);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);
  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void sheetRef.current?.requestFullscreen?.().catch(() => setCanFullscreen(false));
  }, []);

  const incomplete = entry.status === "ready" ? entry.incomplete : null;
  const ready = entry.status === "ready" && incomplete === null;
  const printReason =
    entry.status === "loading" ? "Preparando o relatório…" : entry.status === "error" ? "O relatório não pôde ser preparado." : incomplete;

  return (
    <div className={styles.frame} data-report-overlay="">
      <div ref={sheetRef} className={styles.sheet} data-fullscreen={fullscreen || undefined}>
        <header className={`${styles.header} print:hidden`}>
          <div className={styles.heading}>
            <p className={styles.eyebrow}>{eyebrow}</p>
            <h2 id={titleId} className={styles.title}>
              {title}
            </h2>
            <p className={styles.context}>{context}</p>
          </div>
          <div className={styles.actions}>
            {canFullscreen ? (
              <button
                type="button"
                className={styles.iconButton}
                onClick={toggleFullscreen}
                aria-pressed={fullscreen}
                aria-label={fullscreen ? "Sair da tela cheia" : "Tela cheia"}
                title={fullscreen ? "Sair da tela cheia" : "Tela cheia"}
              >
                {fullscreen ? <Minimize2 aria-hidden="true" /> : <Maximize2 aria-hidden="true" />}
              </button>
            ) : null}
            <ReportPrintButton ready={ready} reason={printReason} />
            <button type="button" className={styles.closeButton} onClick={close} data-autofocus aria-label="Fechar relatório" title="Fechar (Esc)">
              <X aria-hidden="true" />
            </button>
          </div>
        </header>

        <div className={styles.body}>
          <p className="sr-only" role="status" aria-live="polite">
            {entry.status === "loading" ? "Preparando o relatório…" : entry.status === "ready" ? "Relatório pronto." : ""}
          </p>
          {/* Ctrl+P antes do relatório pronto: só um aviso, nunca uma folha parcial (D7.8). */}
          {!ready ? <p className="hidden text-sm print:block">O relatório {title} não estava pronto; nada foi impresso.</p> : null}
          {entry.status === "ready" ? (
            <>
              {incomplete ? (
                <p className="mx-auto mb-3 max-w-[210mm] rounded-lg border border-border px-3 py-2 text-xs print:hidden" role="status">
                  {incomplete}
                </p>
              ) : null}
              <div className={incomplete ? "print:hidden" : undefined}>
                {entry.sheet}
              </div>
            </>
          ) : entry.status === "loading" ? (
            <div className="print:hidden" aria-busy="true" aria-label="Preparando o relatório">
              <Skeleton className="mx-auto h-24 w-full max-w-[210mm] rounded-2xl" />
              <div className="mx-auto mt-5 grid max-w-[210mm] grid-cols-2 gap-2 sm:grid-cols-4">
                {Array.from({ length: 6 }).map((_, index) => (
                  <Skeleton key={index} className={`h-16 rounded-lg ${index < 2 ? "col-span-2" : ""}`} />
                ))}
              </div>
              <div className="mx-auto mt-5 grid max-w-[210mm] gap-2">
                {Array.from({ length: 10 }).map((_, index) => (
                  <Skeleton key={index} className="h-7 w-full rounded-md" />
                ))}
              </div>
            </div>
          ) : (
            <div className={`${styles.state} print:hidden`} role="alert">
              <AlertCircle aria-hidden="true" />
              <h3>Não foi possível preparar o relatório</h3>
              <p>{errorNote}</p>
              <button type="button" className={styles.stateAction} onClick={load}>
                Tentar novamente
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
