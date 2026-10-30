"use client";

import Link from "next/link";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { DndContext } from "@dnd-kit/core";
import { ArrowLeft, Eye, Maximize2, Minimize2, X } from "lucide-react";
import { readPublicBinderPages, readSharedBinderPages } from "@/app/colecoes/compartilhar/actions";
import { FOCUS_RING, SideArrowButton, TopNavControls } from "@/components/colecoes/fichario/binder-chrome";
import { BINDER_SPREAD_MEDIA, BinderObjectFrame } from "@/components/colecoes/fichario/binder-object";
import { PageGrid } from "@/components/colecoes/fichario/binder-page-grid";
import type { SlotHandlers } from "@/components/colecoes/fichario/binder-slot";
import ws from "@/components/colecoes/fichario/workspace.module.css";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  type BinderPage,
  type ViewSide,
  clampPage,
  computeBinderFit,
  firstPageOfView,
  modelLabel,
  readBatchStart,
  viewCount,
  viewForPage,
  viewLabel,
  viewSides,
} from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { type SharedBinderIdentity, type SharedBinderPage, sharedPageToBinderPage } from "@/lib/colecoes/sharing";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { cn } from "@/lib/utils";
import styles from "./share.module.css";

const NOOP = () => {};
/** Nenhuma ação de bolso existe no modo só leitura: clicar só foca. */
const READ_ONLY_HANDLERS: SlotHandlers = {
  onActivate: NOOP,
  onToggleSelect: NOOP,
  onToggleLock: NOOP,
  onToTray: NOOP,
  onReturnFromTray: NOOP,
  onReserve: NOOP,
  onClearReserve: NOOP,
  onRemove: NOOP,
  onAddCard: NOOP,
  onOpenImage: NOOP,
  onInsertGap: NOOP,
  onOpenRegion: NOOP,
};
const EMPTY_IDS = new Set<string>();

/**
 * Fichário Digital do participante VIEWER (V1-12 VIEWER EXPERIENCE PARITY
 * CORRECTION-02) — a MESMA camada visual do fichário do titular, em modo só
 * leitura:
 *  - moldura `ws.root` + cabeçalho `ws.top` (identidade, « ‹ n / N › »);
 *  - encaixe na tela por `computeBinderFit` (mesmo corte de spread);
 *  - objeto `BinderObjectFrame` (couro no acabamento, zíper, lombada,
 *    contracapa com nome próprio e logomarca — vista 1 = contracapa +
 *    página 1, como no titular);
 *  - folhas `PageGrid` → `BinderSlotView` (`editable=false`): bolsos 8:11,
 *    carta, reserva em marca-d'água, esqueleto e "Tentar de novo".
 *
 * O que muda é só ferramenta e permissão: nada de Centro de Controle, trilho
 * de organização, Bandeja, seleção, arrastar ou abrir espaço. Os dados vêm
 * mascarados pelo banco (5316 → 5315): só cartas e reservas DESTA coleção.
 * Lotes de 4 páginas sob demanda, com o próximo adiantado.
 */
export function SharedBinderWorkspace({
  collectionId,
  collectionName,
  ownerDisplayName,
  finish,
  identity,
  columns,
  rows,
  pageCount,
  ownFilled,
  variant,
  titleId,
  onClose = null,
  backHref = null,
  initialAnchor = 1,
  initialPages,
  source = "shared",
}: {
  collectionId: string;
  collectionName: string;
  ownerDisplayName: string;
  finish: BinderFinish;
  /** Nome próprio e logomarca do fichário (5314 estendida); `null` = como o titular sem identidade gravada. */
  identity: SharedBinderIdentity | null;
  columns: number;
  rows: number;
  pageCount: number;
  /** Cartas desta coleção nos bolsos; `null` = não mostrar (vitrine pública). */
  ownFilled: number | null;
  variant: "page" | "overlay";
  titleId: string;
  onClose?: (() => void) | null;
  backHref?: string | null;
  /** Página de entrada (link direto `?pagina=`). */
  initialAnchor?: number;
  /** Primeiro lote já lido no servidor (rota dedicada); ausente = ler ao abrir; `null` = a leitura falhou. */
  initialPages?: SharedBinderPage[] | null;
  /**
   * `shared` = participante VIEWER (5316, sessão); `public` = vitrine
   * pública (5318, sem sessão). Mesma apresentação, mesmo mascaramento (5315).
   */
  source?: "shared" | "public";
}) {
  const reducedMotion = usePrefersReducedMotion();
  const rootRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLElement>(null);
  const totalPages = pageCount;
  const binderName = identity?.name ?? collectionName;
  const showBrandMark = identity?.showBrandMark ?? true;

  // ---- encaixe na tela (mesma conta do titular) ----
  const [allowSpread, setAllowSpread] = useState(true);
  const [box, setBox] = useState<{ w: number; h: number }>({ w: 0, h: 0 });
  useLayoutEffect(() => {
    const media = window.matchMedia(BINDER_SPREAD_MEDIA);
    const apply = () => setAllowSpread(media.matches);
    apply();
    media.addEventListener("change", apply);
    const stage = stageRef.current;
    if (!stage) return () => media.removeEventListener("change", apply);
    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return;
      const { width, height } = entry.contentRect;
      setBox({ w: Math.max(0, width - 8), h: Math.max(0, height - 12) });
    });
    observer.observe(stage);
    return () => {
      media.removeEventListener("change", apply);
      observer.disconnect();
    };
  }, []);
  const fit = useMemo(() => computeBinderFit(box.w, box.h, columns, rows, allowSpread), [allowSpread, box.h, box.w, columns, rows]);
  const perView = fit.perView;

  // ---- navegação (vista 1 = contracapa + página 1) ----
  const [anchor, setAnchor] = useState(() => clampPage(Math.max(1, initialAnchor), totalPages));
  const [direction, setDirection] = useState<1 | -1>(1);
  const view = Math.max(1, viewForPage(anchor, perView));
  const lastView = Math.max(1, viewCount(perView, totalPages) - 1);
  const sides = useMemo<ViewSide[]>(() => viewSides(view, perView, totalPages), [perView, totalPages, view]);
  const visiblePages = useMemo(() => sides.filter((side): side is number => typeof side === "number"), [sides]);

  const go = useCallback(
    (targetView: number) => {
      const next = Math.min(Math.max(1, targetView), lastView);
      if (next === view) return;
      setDirection(next > view ? 1 : -1);
      setAnchor(firstPageOfView(next, perView));
    },
    [lastView, perView, view],
  );

  // ---- leitura sob demanda (lotes de 4 páginas, só desta coleção) ----
  const [cache, setCache] = useState<Map<number, BinderPage>>(() =>
    initialPages ? toBinderCache(initialPages, readBatchStart(initialAnchor), totalPages, columns, rows) : new Map(),
  );
  const [failed, setFailed] = useState<Set<number>>(() => (initialPages === null ? new Set([readBatchStart(initialAnchor)]) : new Set()));
  const inflight = useRef(new Set<number>());

  const load = useCallback(
    async (batch: number) => {
      if (batch < 1 || batch > totalPages || inflight.current.has(batch)) return;
      inflight.current.add(batch);
      setFailed((prev) => {
        if (!prev.has(batch)) return prev;
        const next = new Set(prev);
        next.delete(batch);
        return next;
      });
      const read = source === "public" ? readPublicBinderPages : readSharedBinderPages;
      const result = await read({ collectionId, firstPage: batch, columns, rows }).catch(() => ({ ok: false }) as const);
      inflight.current.delete(batch);
      if (!result.ok) {
        setFailed((prev) => new Set(prev).add(batch));
        return;
      }
      setCache((prev) => {
        const next = new Map(prev);
        for (const [number, page] of toBinderCache(result.pages, batch, totalPages, columns, rows)) next.set(number, page);
        return next;
      });
    },
    [collectionId, columns, rows, totalPages, source],
  );

  useEffect(() => {
    const want = (page: number) => page >= 1 && page <= totalPages && !cache.has(page) && !failed.has(readBatchStart(page));
    for (const page of visiblePages) if (want(page)) void load(readBatchStart(page));
    const ahead = (visiblePages[visiblePages.length - 1] ?? 1) + perView;
    if (want(ahead)) void load(readBatchStart(ahead));
  }, [visiblePages, cache, failed, load, perView, totalPages]);

  // ---- teclado ----
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
      const target = event.target as HTMLElement | null;
      if (target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
      if (event.key === "ArrowLeft") go(view - 1);
      else if (event.key === "ArrowRight") go(view + 1);
      else if (event.key === "Home") go(1);
      else if (event.key === "End") go(lastView);
      else if (event.key === "Escape" && onClose) {
        if (document.fullscreenElement) void document.exitFullscreen();
        else onClose();
      } else return;
      event.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go, view, lastView, onClose]);

  // ---- tela cheia (mesmo alvo do titular: a raiz do fichário) ----
  const [fullscreen, setFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);
  useEffect(() => {
    setCanFullscreen(typeof document.documentElement.requestFullscreen === "function");
    const onChange = () => setFullscreen(document.fullscreenElement === rootRef.current);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);
  const toggleFullscreen = () => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void rootRef.current?.requestFullscreen?.().catch(() => setCanFullscreen(false));
  };

  const label = viewLabel(view, perView, totalPages);
  const sizes = `${Math.max(1, fit.pocket)}px`;

  return (
    <div ref={rootRef} className={cn("binder-nav-01-scope", ws.root)} data-variant={variant} data-fullscreen={fullscreen || undefined}>
      <div aria-hidden className={ws.glow} />

      <header className={ws.top}>
        <div className={ws.identity}>
          {variant === "page" && backHref ? (
            <Link href={backHref} className={cn(ws.iconButton, FOCUS_RING)} aria-label="Voltar à coleção">
              <ArrowLeft className="h-4 w-4" aria-hidden />
            </Link>
          ) : null}
          <div className={ws.identityText}>
            <h2 className={ws.title} id={titleId}>
              {binderName}
            </h2>
            <p className={ws.facts}>
              {binderName !== collectionName ? `${collectionName} · ` : ""}de {ownerDisplayName} · {modelLabel(columns, rows)} · {formatCount(totalPages)}{" "}
              {totalPages === 1 ? "página" : "páginas"}
              {ownFilled !== null ? ` · ${formatCount(ownFilled)} ${ownFilled === 1 ? "carta" : "cartas"}` : ""} · somente visualização
            </p>
          </div>
        </div>

        {totalPages > 0 ? (
          <TopNavControls index={view} total={lastView} label={label} onFirst={() => go(1)} onPrev={() => go(view - 1)} onNext={() => go(view + 1)} onLast={() => go(lastView)} />
        ) : (
          <span />
        )}

        <div className={ws.actions}>
          <span className={styles.accessBadge} title="Você vê o fichário como o titular o montou, sem ferramentas de edição">
            <Eye aria-hidden="true" />
            <span className="sr-only sm:not-sr-only">Somente visualização</span>
          </span>
          {canFullscreen ? (
            <button
              type="button"
              className={cn(ws.iconButton, FOCUS_RING)}
              onClick={toggleFullscreen}
              aria-pressed={fullscreen}
              aria-label={fullscreen ? "Sair da tela cheia" : "Tela cheia"}
              title={fullscreen ? "Sair da tela cheia" : "Tela cheia"}
            >
              {fullscreen ? <Minimize2 className="h-4 w-4" aria-hidden /> : <Maximize2 className="h-4 w-4" aria-hidden />}
            </button>
          ) : null}
          {onClose ? (
            <button type="button" className={cn(ws.iconButton, FOCUS_RING)} onClick={onClose} aria-label="Fechar o fichário (Esc)" title="Fechar (Esc)" data-autofocus>
              <X className="h-4 w-4" aria-hidden />
            </button>
          ) : null}
        </div>
      </header>

      {/* Os bolsos usam os ganchos de arrasto do titular desligados; o contexto só os hospeda. */}
      <DndContext>
        <div className={ws.prev}>
          <SideArrowButton direction="prev" onClick={() => go(view - 1)} disabled={view <= 1} dragActive={false} />
        </div>

        <section ref={stageRef} className={ws.stage} aria-label={`${binderName} — ${label}`} aria-roledescription="fichário somente leitura">
          {totalPages === 0 ? (
            <p className="max-w-sm text-center text-sm text-muted-foreground">Este fichário ainda não tem páginas.</p>
          ) : fit.pocket > 0 ? (
            <BinderObjectFrame
              key={sides.length}
              finish={finish}
              fit={fit}
              sides={sides}
              view={view}
              direction={direction}
              animate={!reducedMotion}
              coverName={binderName}
              coverBrandMark={showBrandMark}
              renderPage={(side, metrics) => (
                <PageGrid
                  pageNumber={side}
                  page={cache.get(side) ?? null}
                  failed={failed.has(readBatchStart(side))}
                  columns={columns}
                  rows={rows}
                  pocket={metrics.pocket}
                  gap={metrics.gap}
                  sizes={sizes}
                  editable={false}
                  selected={EMPTY_IDS}
                  selectionActive={false}
                  trayIds={EMPTY_IDS}
                  armed={null}
                  dragging={null}
                  placing={false}
                  placingAvailable={false}
                  focusCollectionId={null}
                  insertEnabled={false}
                  handlers={READ_ONLY_HANDLERS}
                  onRetry={() => void load(readBatchStart(side))}
                />
              )}
            />
          ) : null}
        </section>

        <div className={ws.next}>
          <SideArrowButton direction="next" onClick={() => go(view + 1)} disabled={view >= lastView} dragActive={false} />
        </div>
      </DndContext>

      <div className={ws.bottom} />
    </div>
  );
}

/** Lote lido → páginas do fichário. Página do lote que não veio (≤ total) = folha vazia. */
function toBinderCache(pages: SharedBinderPage[], batch: number, total: number, columns: number, rows: number): Map<number, BinderPage> {
  const byNumber = new Map(pages.map((page) => [page.pageNumber, page]));
  const cache = new Map<number, BinderPage>();
  for (let number = batch; number <= Math.min(total, batch + 3); number += 1) {
    cache.set(number, sharedPageToBinderPage(byNumber.get(number) ?? { pageNumber: number, pockets: emptyPockets(columns, rows) }));
  }
  return cache;
}

function emptyPockets(columns: number, rows: number) {
  const pockets = [];
  for (let row = 1; row <= rows; row += 1) {
    for (let column = 1; column <= columns; column += 1) {
      pockets.push({ row, column, kind: "empty" as const, cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null });
    }
  }
  return pockets;
}
