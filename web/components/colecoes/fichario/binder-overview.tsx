"use client";

import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { ArrowLeftRight, ChevronLeft, ChevronRight, FilePlus2, LayoutGrid, Loader2, RotateCcw, X } from "lucide-react";
import { reorderPages } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { cardFrontUrl, formatCount } from "@/lib/colecoes/acervo";
import {
  type BinderPage,
  PAGES_PER_READ,
  isOccupied,
  moveInOrder,
  pageOccupancy,
  readBatchStart,
  sameOrder,
  slotFailureMessage,
  swapInOrder,
  viewCount,
  viewSides,
} from "@/lib/colecoes/binder";
import { cn } from "@/lib/utils";
import styles from "./binder-overview.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';
/** Acima disto a organização de páginas fica para uma rodada com carregamento dedicado. */
const ORGANIZE_MAX_PAGES = 400;

/**
 * Visão geral de páginas (P2-B-PAGE-OVERVIEW-AND-TOOL-RAIL-01).
 *
 * Modal sobre o fichário (sem mudar de rota): miniaturas de todas as páginas
 * em pares, como o fichário aberto (contracapa + 1, 2–3, 4–5…), com cartas,
 * reservas e bolsos vazios, página atual destacada, número e ocupação de
 * cada página. Clicar num par leva o fichário até ele.
 *
 * Carregamento progressivo: cada par pede o seu lote de páginas à 5223 só
 * quando entra na área visível (IntersectionObserver), reaproveitando o
 * mesmo cache e o mesmo leitor em lotes de 4 da área de trabalho — nada de
 * chamada por carta. Miniaturas usam o mesmo asset das cartas com
 * `loading="lazy"` e só dentro da área visível (`content-visibility`).
 *
 * Organizar páginas: só com o contrato LIVE `reorder_layout_pages` (5127),
 * que recebe a ordem COMPLETA. A ordem é montada localmente (selecionar,
 * mover para antes/depois, trocar duas de lugar) e gravada numa única
 * chamada em "Aplicar nova ordem"; "Descartar" não grava nada. Páginas
 * levam consigo bolsos, cartas, reservas e cadeados (C-39).
 */
export function BinderOverview({
  host,
  collectionId,
  layoutId,
  editable,
  columns,
  rows,
  totalPages,
  filled,
  currentPages,
  cache,
  failed,
  loadBatch,
  onRetry,
  onGoToPage,
  onReordered,
  onRequestAddPages,
  onClose,
}: {
  host: HTMLElement | null;
  collectionId: string;
  layoutId: string | null;
  editable: boolean;
  columns: number;
  rows: number;
  totalPages: number;
  filled: number;
  /** Páginas visíveis agora no fichário (destaque "atual"). */
  currentPages: number[];
  cache: Map<number, BinderPage>;
  failed: Set<number>;
  loadBatch: (page: number) => void;
  onRetry: (page: number) => void;
  onGoToPage: (page: number) => void;
  onReordered: (message: string) => void;
  /** Fim da lista de páginas: acrescentar páginas (5125) — fecha a visão geral e abre a confirmação. */
  onRequestAddPages?: (() => void) | null;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  // Só pede lotes que ainda não estão no cache nem falharam (refs: o observer não é recriado a cada página que chega).
  const cacheRef = useRef(cache);
  const failedRef = useRef(failed);
  cacheRef.current = cache;
  failedRef.current = failed;
  const ensure = useCallback(
    (page: number) => {
      if (page < 1 || page > totalPages || cacheRef.current.has(page) || failedRef.current.has(readBatchStart(page))) return;
      loadBatch(page);
    },
    [loadBatch, totalPages],
  );
  const retry = useCallback(
    (page: number) => {
      onRetry(page);
      loadBatch(page);
    },
    [loadBatch, onRetry],
  );
  const [mode, setMode] = useState<"browse" | "organize">("browse");
  const capacity = columns * rows;
  const views = useMemo(() => {
    const count = Math.max(1, viewCount(2, totalPages) - 1);
    return Array.from({ length: count }, (_, index) => ({ view: index + 1, sides: viewSides(index + 1, 2, totalPages) }));
  }, [totalPages]);

  // Foco: entra no diálogo, Tab preso, Esc fecha, foco volta a quem abriu.
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    const dialog = dialogRef.current;
    dialog?.focus({ preventScroll: true });
    function onKey(event: KeyboardEvent) {
      if (!dialog) return;
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;
      // Tab é só da visão geral (o trap do overlay do fichário não deve reagir).
      event.stopPropagation();
      const items = [...dialog.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null);
      const first = items[0];
      const last = items[items.length - 1];
      if (!first || !last) return;
      if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
    window.addEventListener("keydown", onKey, true);
    return () => {
      window.removeEventListener("keydown", onKey, true);
      if (opener?.isConnected) opener.focus();
    };
  }, [onClose]);

  // Leva a página atual para a área visível ao abrir.
  useEffect(() => {
    const current = dialogRef.current?.querySelector<HTMLElement>("[data-current='true']");
    current?.scrollIntoView({ block: "center" });
  }, []);

  const loadedCount = useMemo(() => {
    let count = 0;
    for (let page = 1; page <= totalPages; page += 1) if (cache.has(page)) count += 1;
    return count;
  }, [cache, totalPages]);

  if (!host) return null;

  return createPortal(
    <div className={styles.veil} onPointerDown={(event) => event.target === event.currentTarget && onClose()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby="visao-geral-titulo" tabIndex={-1} className={styles.dialog}>
        <header className={styles.header}>
          <div className={styles.heading}>
            <LayoutGrid className={styles.headingIcon} aria-hidden />
            <div>
              <h2 id="visao-geral-titulo" className={styles.title}>
                {mode === "browse" ? "Visão geral" : "Organizar páginas"}
              </h2>
              <p className={styles.summary}>
                {formatCount(totalPages)} {totalPages === 1 ? "página" : "páginas"} · {capacity} bolsos por página ({columns} × {rows}) ·{" "}
                {formatCount(filled)} de {formatCount(totalPages * capacity)} com carta
              </p>
            </div>
          </div>
          <div className={styles.headerActions}>
            {editable && layoutId ? (
              <div className={styles.segmented} role="radiogroup" aria-label="Modo da visão geral">
                <button type="button" role="radio" aria-checked={mode === "browse"} onClick={() => setMode("browse")}>
                  Navegar
                </button>
                <button
                  type="button"
                  role="radio"
                  aria-checked={mode === "organize"}
                  onClick={() => setMode("organize")}
                  disabled={totalPages > ORGANIZE_MAX_PAGES}
                  title={totalPages > ORGANIZE_MAX_PAGES ? `Organizar está disponível para fichários de até ${ORGANIZE_MAX_PAGES} páginas` : undefined}
                >
                  Organizar
                </button>
              </div>
            ) : null}
            <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar a visão geral (Esc)" title="Fechar (Esc)">
              <X aria-hidden />
            </button>
          </div>
        </header>

        {mode === "browse" ? (
          <BrowseGrid
            views={views}
            columns={columns}
            rows={rows}
            cache={cache}
            failed={failed}
            currentPages={currentPages}
            loadBatch={ensure}
            onRetry={retry}
            onPick={(page) => {
              onGoToPage(page);
              onClose();
            }}
            onAddPages={
              editable && layoutId && onRequestAddPages
                ? () => {
                    onClose();
                    onRequestAddPages();
                  }
                : null
            }
          />
        ) : (
          <OrganizePanel
            collectionId={collectionId}
            layoutId={layoutId as string}
            totalPages={totalPages}
            columns={columns}
            rows={rows}
            cache={cache}
            loadedCount={loadedCount}
            failedCount={failed.size}
            loadBatch={ensure}
            onRetryAll={() => {
              for (const first of failed) retry(first);
            }}
            onCancel={() => setMode("browse")}
            onApplied={(message) => {
              onReordered(message);
              setMode("browse");
            }}
          />
        )}
      </div>
    </div>,
    host,
  );
}

// ---------------------------------------------------------------------------
// Navegar: pares de páginas
// ---------------------------------------------------------------------------

function BrowseGrid({
  views,
  columns,
  rows,
  cache,
  failed,
  currentPages,
  loadBatch,
  onRetry,
  onPick,
  onAddPages,
}: {
  views: { view: number; sides: (number | "inner")[] }[];
  columns: number;
  rows: number;
  cache: Map<number, BinderPage>;
  failed: Set<number>;
  currentPages: number[];
  loadBatch: (page: number) => void;
  onRetry: (page: number) => void;
  onPick: (page: number) => void;
  onAddPages: (() => void) | null;
}) {
  const listRef = useRef<HTMLUListElement>(null);

  // Pede o lote de cada par só quando ele se aproxima da área visível.
  useEffect(() => {
    const list = listRef.current;
    if (!list) return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const pages = (entry.target as HTMLElement).dataset.pages?.split(",").map(Number) ?? [];
          for (const page of pages) if (page > 0) loadBatch(page);
        }
      },
      { root: list.parentElement, rootMargin: "240px 0px" },
    );
    for (const item of list.querySelectorAll("[data-pages]")) observer.observe(item);
    return () => observer.disconnect();
  }, [loadBatch, views]);

  return (
    <div className={styles.body}>
      <ul ref={listRef} className={styles.grid} aria-label="Pares de páginas">
        {views.map(({ view, sides }) => {
          const pages = sides.filter((side): side is number => typeof side === "number");
          const first = pages[0] ?? 1;
          const current = pages.some((page) => currentPages.includes(page));
          const failedBatch = pages.find((page) => !cache.has(page) && failed.has(readBatchStart(page)));
          const label = pages.length === 2 ? `Páginas ${pages[0]} e ${pages[1]}` : `Página ${first}`;
          return (
            <li key={view} data-pages={pages.join(",")} data-current={current || undefined} className={styles.item}>
              <button type="button" className={styles.spread} aria-current={current ? "page" : undefined} aria-label={`${label}${current ? " (atual)" : ""}`} onClick={() => onPick(first)}>
                <span className={styles.spreadPages}>
                  {sides.map((side, index) =>
                    side === "inner" ? (
                      <span key={`inner-${index}`} className={styles.inner} aria-hidden />
                    ) : (
                      <MiniPage key={side} page={cache.get(side) ?? null} columns={columns} rows={rows} />
                    ),
                  )}
                </span>
                <span className={styles.caption}>
                  <span className={styles.captionPages}>
                    {pages.map((page) => (
                      <PageCaption key={page} number={page} page={cache.get(page) ?? null} />
                    ))}
                  </span>
                  {current ? <span className={styles.currentTag}>Atual</span> : null}
                </span>
              </button>
              {failedBatch ? (
                <button type="button" className={styles.retry} onClick={() => onRetry(failedBatch)}>
                  <RotateCcw aria-hidden /> Tentar de novo
                </button>
              ) : null}
            </li>
          );
        })}
        {onAddPages ? (
          <li className={styles.item}>
            <button type="button" className={styles.addTile} onClick={onAddPages} aria-haspopup="dialog">
              <FilePlus2 aria-hidden />
              <span className={styles.addTileTitle}>Adicionar páginas</span>
              <span className={styles.addTileHint}>No fim do fichário, com bolsos vazios</span>
            </button>
          </li>
        ) : null}
      </ul>
    </div>
  );
}

function PageCaption({ number, page }: { number: number; page: BinderPage | null }) {
  if (!page) return <span className={styles.pageCaption}>Pág. {number}</span>;
  const occupancy = pageOccupancy(page);
  const empty = occupancy.occupied === 0 && occupancy.reservedMissing === 0 && occupancy.images === 0;
  return (
    <span className={styles.pageCaption}>
      Pág. {number}
      <span className={styles.pageCount} data-empty={empty || undefined}>
        {empty ? "vazia" : `${occupancy.occupied}/${occupancy.capacity}`}
      </span>
    </span>
  );
}

/** Página em miniatura: carta (imagem preguiçosa), reserva (contorno tracejado) ou bolso vazio. */
const MiniPage = memo(function MiniPage({ page, columns, rows }: { page: BinderPage | null; columns: number; rows: number }) {
  const style = { "--cols": columns } as React.CSSProperties;
  if (!page) {
    return (
      <span className={styles.mini} style={style} data-loading aria-hidden>
        {Array.from({ length: columns * rows }).map((_, index) => (
          <span key={index} className={styles.miniPocket} />
        ))}
      </span>
    );
  }
  return (
    <span className={styles.mini} style={style} aria-hidden>
      {page.slots.map((slot) => {
        const occupied = isOccupied(slot);
        const reserved = !occupied && slot.state === "RESERVED_EMPTY";
        const image = !occupied && !reserved ? (slot.image ?? null) : null;
        const src = occupied ? cardFrontUrl(SUPABASE_URL, slot.present?.imagePath ?? null) : (image?.url ?? null);
        return (
          <span
            key={slot.slotId}
            className={styles.miniPocket}
            data-kind={occupied ? "card" : reserved ? "reserve" : image ? "card" : "empty"}
            style={image ? ({ "--focal": `${image.focalY}%` } as React.CSSProperties) : undefined}
          >
            {src ? (
              // eslint-disable-next-line @next/next/no-img-element -- mesmo asset das cartas (cache), preguiçoso
              <img src={src} alt="" loading="lazy" decoding="async" draggable={false} />
            ) : null}
          </span>
        );
      })}
    </span>
  );
});

// ---------------------------------------------------------------------------
// Organizar: ordem local + uma gravação
// ---------------------------------------------------------------------------

function OrganizePanel({
  collectionId,
  layoutId,
  totalPages,
  columns,
  rows,
  cache,
  loadedCount,
  failedCount,
  loadBatch,
  onRetryAll,
  onCancel,
  onApplied,
}: {
  collectionId: string;
  layoutId: string;
  totalPages: number;
  columns: number;
  rows: number;
  cache: Map<number, BinderPage>;
  loadedCount: number;
  failedCount: number;
  loadBatch: (page: number) => void;
  onRetryAll: () => void;
  onCancel: () => void;
  onApplied: (message: string) => void;
}) {
  // A ordem completa exige todas as páginas (o contrato recebe todos os ids).
  useEffect(() => {
    for (let first = 1; first <= totalPages; first += PAGES_PER_READ) loadBatch(first);
  }, [loadBatch, totalPages]);

  const ready = loadedCount >= totalPages;
  const original = useMemo(() => {
    if (!ready) return [] as BinderPage[];
    return Array.from({ length: totalPages }, (_, index) => cache.get(index + 1)).filter((page): page is BinderPage => Boolean(page));
  }, [cache, ready, totalPages]);
  const [order, setOrder] = useState<BinderPage[] | null>(null);
  const [picked, setPicked] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (ready && order === null) setOrder(original);
  }, [order, original, ready]);

  const current = order ?? original;
  const changed = order !== null && !sameOrder(order.map((p) => p.pageId), original.map((p) => p.pageId));
  const pickedIndexes = picked.map((id) => current.findIndex((page) => page.pageId === id)).filter((index) => index >= 0);
  const single = pickedIndexes.length === 1 ? pickedIndexes[0] : undefined;

  const toggle = useCallback((pageId: string) => {
    setPicked((prev) => (prev.includes(pageId) ? prev.filter((id) => id !== pageId) : [...prev, pageId].slice(-2)));
  }, []);

  const move = (delta: number) => {
    if (single === undefined) return;
    setOrder(moveInOrder(current, single, delta));
  };
  const swap = () => {
    const [a, b] = pickedIndexes;
    if (a === undefined || b === undefined) return;
    setOrder(swapInOrder(current, a, b));
  };

  const apply = async () => {
    if (!changed || saving) return;
    setSaving(true);
    setError(null);
    const result = await reorderPages({ collectionId, layoutId, pageIds: current.map((page) => page.pageId) });
    setSaving(false);
    if (!result.ok) {
      setError(slotFailureMessage(result.reason));
      return;
    }
    onApplied("Nova ordem das páginas aplicada. Cartas, reservas e cadeados foram junto com cada página.");
  };

  if (!ready || !order) {
    return (
      <div className={styles.body}>
        {failedCount > 0 ? (
          <p className={styles.loading} role="alert">
            Algumas páginas não carregaram ({loadedCount} de {totalPages}).
            <button type="button" className={styles.retry} onClick={onRetryAll}>
              <RotateCcw aria-hidden /> Tentar de novo
            </button>
          </p>
        ) : (
          <p className={styles.loading} role="status">
            <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden />
            Carregando as páginas para organizar… {loadedCount} de {totalPages}
          </p>
        )}
      </div>
    );
  }

  return (
    <>
      <div className={styles.body}>
        <p className={styles.hint}>
          Toque numa página para escolhê-la e use as setas para mudar a posição; escolha duas para trocá-las de lugar. Nada é gravado até você aplicar.
        </p>
        <ol className={styles.organizeGrid} aria-label="Páginas na nova ordem">
          {current.map((page, index) => {
            const occupancy = pageOccupancy(page);
            const empty = occupancy.occupied === 0 && occupancy.reservedMissing === 0 && occupancy.images === 0;
            const isPicked = picked.includes(page.pageId);
            const moved = page.pageNumber !== index + 1;
            return (
              <li key={page.pageId}>
                <button
                  type="button"
                  className={styles.pageTile}
                  aria-pressed={isPicked}
                  aria-label={`Posição ${index + 1}: página ${page.pageNumber}${moved ? " (movida)" : ""}, ${empty ? "vazia" : `${occupancy.occupied} de ${occupancy.capacity} com carta`}`}
                  onClick={() => toggle(page.pageId)}
                >
                  <MiniPage page={page} columns={columns} rows={rows} />
                  <span className={styles.tileCaption}>
                    <strong>{index + 1}</strong>
                    {moved ? <span className={styles.movedTag}>era {page.pageNumber}</span> : null}
                    <span className={styles.pageCount} data-empty={empty || undefined}>
                      {empty ? "vazia" : `${occupancy.occupied}/${occupancy.capacity}`}
                    </span>
                  </span>
                </button>
              </li>
            );
          })}
        </ol>
      </div>
      <footer className={styles.footer}>
        <div className={styles.footerTools} role="toolbar" aria-label="Mover páginas">
          <button type="button" className={styles.tool} onClick={() => move(-1)} disabled={single === undefined || single === 0}>
            <ChevronLeft aria-hidden /> Antes
          </button>
          <button
            type="button"
            className={styles.tool}
            onClick={() => move(1)}
            disabled={single === undefined || single === current.length - 1}
          >
            Depois <ChevronRight aria-hidden />
          </button>
          <button type="button" className={styles.tool} onClick={swap} disabled={pickedIndexes.length !== 2}>
            <ArrowLeftRight aria-hidden /> Trocar de lugar
          </button>
        </div>
        {error ? (
          <p className={styles.error} role="alert">
            {error}
          </p>
        ) : null}
        <div className={styles.footerActions}>
          <Button
            variant="outline"
            onClick={() => {
              setOrder(original);
              setPicked([]);
              onCancel();
            }}
            disabled={saving}
          >
            Descartar
          </Button>
          <Button onClick={() => void apply()} disabled={!changed || saving} className={cn(saving && "cursor-wait")}>
            {saving ? <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden /> : null}
            Aplicar nova ordem
          </Button>
        </div>
      </footer>
    </>
  );
}
