"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { AlertCircle, ClipboardCheck, Maximize2, Minimize2, X } from "lucide-react";
import { readChecklistReport, type ChecklistReportResult } from "@/app/colecoes/colecoes/[id]/relatorios/actions";
import { BinderOverlayShell } from "@/components/colecoes/fichario/binder-overlay-shell";
import { Skeleton } from "@/components/ui/skeleton";
import type { PositionFilter } from "@/lib/colecoes/colecoes";
import type { ChecklistReportData } from "@/lib/reports/checklist-queries";
import { checklistKindLabel } from "@/lib/reports/collection-checklist";
import { CHECKLIST_TITLE, ChecklistReportBody, checklistIdentity, checklistPrintReason } from "./collection-checklist-report";
import { ReportPrintButton } from "./report-print-button";
import styles from "./report-overlay.module.css";

type Entry = { status: "loading" } | { status: "failed"; reason: "not_found" | "unavailable" | "error" } | { status: "ready"; data: ChecklistReportData };

/**
 * Checklist de completude em SOBREPOSIÇÃO à coleção (V1-14 R1-A UX REDIRECTION-02), no padrão
 * do Fichário digital: mesma casca (`BinderOverlayShell` — véu, foco preso e devolvido, fundo
 * inerte, rolagem travada sem perder a posição), área ampla com cabeçalho próprio (Tela cheia,
 * Imprimir, Fechar) e o MESMO corpo da rota de acesso direto (`ChecklistReportBody`).
 *
 * Dados: server action `readChecklistReport` (só o titular; conjunto INTEIRO do filtro). Cada
 * filtro é lido uma vez e guardado enquanto a sobreposição estiver aberta; ao trocar, o
 * resultado anterior continua visível (atenuado) até o novo chegar — sem piscar. Respostas fora
 * de ordem são descartadas.
 *
 * Impressão: `globals.css` (`[data-report-overlay]`) esconde a página de origem e desfaz o
 * posicionamento fixo da sobreposição só na impressão — sai apenas a folha A4 do relatório.
 * Esc fecha; em tela cheia, o primeiro Esc é do navegador (sai da tela cheia).
 */
export function CollectionReportOverlay({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  const titleId = useId();
  return (
    <BinderOverlayShell labelledBy={titleId} onClose={onClose}>
      {(close) => <ReportSheet collectionId={collectionId} titleId={titleId} close={close} />}
    </BinderOverlayShell>
  );
}

function ReportSheet({ collectionId, titleId, close }: { collectionId: string; titleId: string; close: () => void }) {
  const sheetRef = useRef<HTMLDivElement>(null);
  const [filter, setFilter] = useState<PositionFilter>("todas");
  const [entries, setEntries] = useState<Partial<Record<PositionFilter, Entry>>>({});
  const [pending, setPending] = useState<PositionFilter | null>(null);
  const [shown, setShown] = useState<PositionFilter>("todas");
  const latest = useRef<PositionFilter>("todas");
  const [fullscreen, setFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);

  const load = useCallback(
    (target: PositionFilter) => {
      latest.current = target;
      setPending(target);
      readChecklistReport({ collectionId, filter: target })
        .then((result: ChecklistReportResult) => {
          const entry: Entry = result.ok ? { status: "ready", data: result.data } : { status: "failed", reason: result.reason };
          setEntries((current) => ({ ...current, [target]: entry }));
          if (latest.current !== target) return;
          setShown(target);
          setPending(null);
        })
        .catch(() => {
          setEntries((current) => ({ ...current, [target]: { status: "failed", reason: "error" } }));
          if (latest.current !== target) return;
          setShown(target);
          setPending(null);
        });
    },
    [collectionId],
  );

  // Primeira leitura: "Todas".
  useEffect(() => {
    setEntries({ todas: { status: "loading" } });
    load("todas");
  }, [load]);

  const changeFilter = useCallback(
    (next: PositionFilter) => {
      setFilter(next);
      const cached = entries[next];
      if (cached && cached.status === "ready") {
        latest.current = next;
        setPending(null);
        setShown(next);
        return;
      }
      load(next);
    },
    [entries, load],
  );

  const retry = useCallback(() => load(filter), [filter, load]);

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

  // Tela cheia (mesmo padrão do Fichário): só quando o navegador oferece.
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

  const entry = entries[shown] ?? { status: "loading" };
  const data = entry.status === "ready" ? entry.data : null;
  const ready = data !== null && data.load.status === "ready" && data.load.complete;
  const printReason = data ? checklistPrintReason(data.load) : entry.status === "loading" ? "Preparando o checklist…" : "O checklist não pôde ser preparado.";

  return (
    <div className={styles.frame} data-report-overlay="">
      <div ref={sheetRef} className={styles.sheet} data-fullscreen={fullscreen || undefined}>
        <header className={`${styles.header} print:hidden`}>
          <div className={styles.heading}>
            <p className={styles.eyebrow}>
              <ClipboardCheck aria-hidden="true" />
              Relatório da coleção
            </p>
            <h2 id={titleId} className={styles.title}>
              {CHECKLIST_TITLE}
            </h2>
            <p className={styles.context}>
              {data ? `${checklistIdentity(data.collection)} · ${checklistKindLabel(data.kind)}` : " "}
            </p>
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
            <ReportPrintButton ready={ready} reason={ready ? null : printReason} />
            <button type="button" className={styles.closeButton} onClick={close} data-autofocus aria-label="Fechar relatório" title="Fechar (Esc)">
              <X aria-hidden="true" />
            </button>
          </div>
        </header>

        <div className={styles.body}>
          <p className="sr-only" role="status" aria-live="polite">
            {pending ? "Preparando o checklist…" : data ? "Checklist pronto." : ""}
          </p>
          {data ? (
            <ChecklistReportBody
              collection={data.collection}
              kind={data.kind}
              filter={shown}
              load={data.load}
              logoUrl={data.logoUrl}
              issuedAt={data.issuedAt}
              control={{ kind: "state", onChange: changeFilter, onRetry: retry, pending }}
            />
          ) : entry.status === "failed" ? (
            <div className={`${styles.state} print:hidden`} role="alert">
              <AlertCircle aria-hidden="true" />
              <h3>
                {entry.reason === "unavailable"
                  ? "Checklist indisponível para esta coleção"
                  : entry.reason === "not_found"
                    ? "Este relatório não está disponível"
                    : "Não foi possível preparar o checklist"}
              </h3>
              <p>
                {entry.reason === "unavailable"
                  ? "Nesta etapa, o Checklist de completude existe para coleções de Set padrão e Master Set."
                  : "Nada foi alterado na sua coleção."}
              </p>
              {entry.reason === "error" ? (
                <button type="button" className={styles.stateAction} onClick={retry}>
                  Tentar novamente
                </button>
              ) : null}
            </div>
          ) : (
            <div className="print:hidden" aria-busy="true" aria-label="Preparando o checklist">
              <Skeleton className="h-24 w-full rounded-2xl" />
              <Skeleton className="mt-5 h-10 w-64 rounded-full" />
              <div className="mt-5 grid gap-2 sm:grid-cols-2">
                {Array.from({ length: 12 }).map((_, index) => (
                  <Skeleton key={index} className="h-11 w-full rounded-lg" />
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
