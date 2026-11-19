"use client";

import Link from "next/link";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { DndContext, DragOverlay, pointerWithin } from "@dnd-kit/core";
import { ArrowLeft, Eye, Layers, Maximize2, Minimize2, Pencil, X } from "lucide-react";
import { readPublicBinderPages, readSharedBinderPages } from "@/app/colecoes/compartilhar/actions";
import { FOCUS_RING, SideArrowButton, TopNavControls } from "@/components/colecoes/fichario/binder-chrome";
import { BINDER_SPREAD_MEDIA, BinderObjectFrame } from "@/components/colecoes/fichario/binder-object";
import { PageGrid } from "@/components/colecoes/fichario/binder-page-grid";
import { CardViewTransitionContext, type SlotHandlers } from "@/components/colecoes/fichario/binder-slot";
import { BinderCardView } from "@/components/colecoes/fichario/binder-card-view";
import { AvailablePanel } from "@/components/colecoes/fichario/binder-available";
import { TraySurface, TrayToggleButton } from "@/components/colecoes/fichario/binder-tray";
import { EditorDragPreview, SharedEditorMessages, useSharedBinderEditor } from "@/components/colecoes/sharing/shared-binder-editor";
import { ReservePicker } from "@/components/colecoes/fichario/binder-reserve-picker";
import { readEditorReserveCandidates } from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import { editorReserveScope } from "@/lib/colecoes/editor-binder";
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
import { canViewCard } from "@/lib/colecoes/binder-card-view";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { type SharedBinderIdentity, type SharedBinderPage, sharedPageToBinderPage } from "@/lib/colecoes/sharing";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { canUseViewTransitions, runWithViewTransition } from "@/lib/view-transitions";
import { cn } from "@/lib/utils";
import styles from "./share.module.css";

const NOOP = () => {};
/** Nenhuma ação de bolso existe no modo só leitura: clicar só foca (V1-08: na carta, abre a lupa — só consulta). */
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
  memberRole = null,
  editorEnabled = false,
  completionPolicy = null,
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
  /** V1-13 (5368): papel do participante, só para o selo discreto. */
  memberRole?: "EDITOR" | "VIEWER" | null;
  /**
   * V1-13 · E2-1: curadoria do EDITOR (colocar, mover/trocar, retirar). Vem do
   * servidor da página: configuração D1 ligada + papel EDITOR + coleção ativa.
   * Desligado = exatamente o leitor só leitura. Não é autorização: cada escrita
   * é decidida no servidor.
   */
  editorEnabled?: boolean;
  /** E2-2: tipo da coleção (5312), só para escolher a fonte das cartas na reserva do EDITOR. */
  completionPolicy?: string | null;
}) {
  const reducedMotion = usePrefersReducedMotion();
  const rootRef = useRef<HTMLDivElement>(null);
  /** V1-08 D1/D3: lupa aberta ao tocar/clicar na carta (só consulta, nenhuma ação). */
  const [cardViewSlotId, setCardViewSlotId] = useState<string | null>(null);
  /** Morph bolso → lupa, como no titular e no Catálogo (fora da tela cheia). */
  const [cardViewTarget, setCardViewTarget] = useState<string | null>(null);
  const [cardViewMorph, setCardViewMorph] = useState(false);
  const openCardView = useCallback((slotId: string) => {
    const morph = canUseViewTransitions() && !document.fullscreenElement;
    setCardViewMorph(morph);
    if (!morph) {
      setCardViewSlotId(slotId);
      return;
    }
    flushSync(() => setCardViewTarget(slotId));
    runWithViewTransition(() => setCardViewSlotId(slotId));
  }, []);
  const closeCardView = useCallback(() => {
    if (cardViewMorph) runWithViewTransition(() => setCardViewSlotId(null));
    else setCardViewSlotId(null);
    setCardViewTarget(null);
  }, [cardViewMorph]);
  const handlers = useMemo<SlotHandlers>(
    () => ({ ...READ_ONLY_HANDLERS, onActivate: (slot) => (canViewCard(slot) ? openCardView(slot.slotId) : undefined), onViewCard: (slot) => openCardView(slot.slotId) }),
    [openCardView],
  );
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

  const [filled, setFilled] = useState(ownFilled);
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

  const refresh = useCallback((pages: number[]) => {
    for (const batch of new Set(pages.map((page) => readBatchStart(page)))) void load(batch);
  }, [load]);
  const editor = useSharedBinderEditor({
    enabled: editorEnabled && source === "shared",
    collectionId,
    cache,
    setCache,
    refresh,
    onFilledDelta: (delta) => setFilled((value) => (value === null ? value : Math.max(0, value + delta))),
    reserveScope: editorReserveScope(completionPolicy),
  });
  const reserveScope = editorReserveScope(completionPolicy);
  const editing = editor.active;
  const editorHandlers = editor.handlers;
  const slotHandlers = useMemo(() => editorHandlers(handlers), [editorHandlers, handlers]);
  const [docked, setDocked] = useState(false);
  useEffect(() => {
    const media = window.matchMedia("(min-width: 1280px)");
    const apply = () => setDocked(media.matches);
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, []);

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
      // V1-08: com a lupa aberta, Esc fecha só ela e as setas não viram a página.
      if (cardViewSlotId) return;
      const target = event.target as HTMLElement | null;
      if (target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
      // E2-2: com o seletor de reserva aberto, o teclado é dele (Esc fecha o diálogo, setas não viram página).
      if (editor.reserveTarget) return;
      if (event.key === "Escape" && (editor.confirm || editor.armed || editor.armedCard)) {
        if (editor.confirm) editor.cancelConfirm();
        else editor.setArmed(null);
      } else if (event.key === "ArrowLeft") go(view - 1);
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
  }, [go, view, lastView, onClose, cardViewSlotId, editor]);

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

  // V1-08: bolso da lupa, sempre lido do cache atual (se sumir, a lupa fecha).
  const cardViewSlot = useMemo(() => {
    if (!cardViewSlotId) return null;
    for (const page of cache.values()) for (const slot of page.slots) if (slot.slotId === cardViewSlotId) return slot;
    return null;
  }, [cache, cardViewSlotId]);
  useEffect(() => {
    if (cardViewSlotId && !(cardViewSlot && canViewCard(cardViewSlot))) {
      setCardViewSlotId(null);
      setCardViewTarget(null);
    }
  }, [cardViewSlot, cardViewSlotId]);

  const label = viewLabel(view, perView, totalPages);
  const sizes = `${Math.max(1, fit.pocket)}px`;

  return (
    <CardViewTransitionContext.Provider value={cardViewSlotId ? null : cardViewTarget}>
    <div
      ref={rootRef}
      className={cn("binder-nav-01-scope", ws.root)}
      data-variant={variant}
      data-fullscreen={fullscreen || undefined}
      data-available={editing && editor.availableOpen ? (docked ? "side" : "bottom") : undefined}
    >
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
              {filled !== null ? ` · ${formatCount(filled)} ${filled === 1 ? "carta" : "cartas"}` : ""}
              {editing ? " · você pode organizar as cartas" : " · somente visualização"}
            </p>
          </div>
        </div>

        {totalPages > 0 ? (
          <TopNavControls index={view} total={lastView} label={label} onFirst={() => go(1)} onPrev={() => go(view - 1)} onNext={() => go(view + 1)} onLast={() => go(lastView)} />
        ) : (
          <span />
        )}

        <div className={ws.actions}>
          {memberRole === "EDITOR" ? (
            <span
              className={styles.accessBadge}
              title={
                editing
                  ? "Você é editor desta coleção: pode colocar, mover e retirar cartas do fichário. As cartas continuam do titular."
                  : "Você é editor desta coleção. A organização compartilhada ainda não está disponível nesta tela."
              }
            >
              <Pencil aria-hidden="true" />
              <span className="sr-only sm:not-sr-only">Editor</span>
            </span>
          ) : (
            <span className={styles.accessBadge} title="Você vê o fichário como o titular o montou, sem ferramentas de edição">
              <Eye aria-hidden="true" />
              <span className="sr-only sm:not-sr-only">Somente visualização</span>
            </span>
          )}
          {editing ? (
            <button
              type="button"
              className={cn(ws.iconButton, FOCUS_RING)}
              onClick={() => (editor.availableOpen ? editor.closeAvailable() : editor.openAvailable())}
              aria-pressed={editor.availableOpen}
              aria-label={editor.availableOpen ? "Fechar Cartas disponíveis" : "Cartas disponíveis"}
              title="Cartas disponíveis"
            >
              <Layers className="h-4 w-4" aria-hidden />
            </button>
          ) : null}
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

      {/* Leitor: ganchos de arrasto desligados (o contexto só os hospeda). EDITOR (E2-1): os mesmos do titular. */}
      <DndContext
        sensors={editing ? editor.sensors : undefined}
        collisionDetection={pointerWithin}
        onDragStart={editing ? editor.onDragStart : undefined}
        onDragEnd={editing ? editor.onDragEnd : undefined}
        onDragCancel={editing ? editor.onDragCancel : undefined}
      >
        <div className={ws.prev}>
          <SideArrowButton direction="prev" onClick={() => go(view - 1)} disabled={view <= 1} dragActive={false} />
        </div>

        <section
          ref={stageRef}
          className={ws.stage}
          aria-label={`${binderName} — ${label}`}
          aria-roledescription={editing ? "fichário compartilhado, organização pelo editor" : "fichário somente leitura"}
        >
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
                  page={editing ? editor.view(cache.get(side) ?? null) : (cache.get(side) ?? null)}
                  failed={failed.has(readBatchStart(side))}
                  columns={columns}
                  rows={rows}
                  pocket={metrics.pocket}
                  gap={metrics.gap}
                  sizes={sizes}
                  editable={editing}
                  selected={EMPTY_IDS}
                  selectionActive={false}
                  trayIds={editing ? editor.trayIds : EMPTY_IDS}
                  armed={editing ? editor.armed : null}
                  dragging={editing ? editor.dragging : null}
                  placing={editing && (editor.armed !== null || editor.dragging?.kind === "slot" || editor.dragging?.kind === "tray")}
                  placingAvailable={editing && (editor.armedCard !== null || editor.dragging?.kind === "available")}
                  focusCollectionId={null}
                  insertEnabled={false}
                  handlers={slotHandlers}
                  onRetry={() => void load(readBatchStart(side))}
                />
              )}
            />
          ) : null}
        </section>

        <div className={ws.next}>
          <SideArrowButton direction="next" onClick={() => go(view + 1)} disabled={view >= lastView} dragActive={false} />
        </div>

        {editing && editor.availableOpen ? (
          <AvailablePanel
            mode={docked ? "side" : "bottom"}
            collectionName={collectionName}
            state={editor.available}
            editable={editing}
            armedId={editor.armedCard?.physicalCardId ?? null}
            origin="THIS"
            onOrigin={() => {}}
            showOrigins={false}
            hint={
              editor.target
                ? "Toque na carta para colocá-la no bolso escolhido."
                : "Cartas desta coleção guardadas neste fichário e ainda sem bolso. Arraste até um bolso vazio, ou toque na carta e depois no bolso."
            }
            emptyTitle={editor.emptyState.title}
            emptyText={editor.emptyState.text}
            onArm={editor.armCard}
            onLoadMore={editor.loadMore}
            onRetry={editor.retryAvailable}
            onClose={editor.closeAvailable}
          />
        ) : null}

        {editing ? (
          <DragOverlay dropAnimation={null}>
            <EditorDragPreview editor={editor} pocket={fit.pocket} />
          </DragOverlay>
        ) : null}
      </DndContext>

      <div className={ws.bottom}>
        {editing || editor.toast ? <SharedEditorMessages editor={editor} /> : null}
        {editing ? (
          <div className={ws.trayAnchor}>
            {editor.trayOpen ? (
              <TraySurface
                items={editor.tray}
                armed={editor.armed}
                onArm={(id) => editor.setArmed(editor.armed === id ? null : id)}
                onReturn={editor.returnFromTray}
                onClose={() => editor.setTrayOpen(false)}
              />
            ) : null}
            <TrayToggleButton
              count={editor.tray.length}
              open={editor.trayOpen}
              dragActive={editor.dragging?.kind === "slot"}
              disabled={!editing}
              onToggle={() => editor.setTrayOpen(!editor.trayOpen)}
            />
          </div>
        ) : null}
      </div>

      {editing && editor.reserveTarget && reserveScope ? (
        <ReservePicker
          host={rootRef.current}
          target={editor.slotById(editor.reserveTarget.slot.slotId)?.slot ?? editor.reserveTarget.slot}
          pageNumber={editor.reserveTarget.page}
          collectionId={collectionId}
          mode={editor.reserveTarget.mode}
          targets={[{ collectionId, name: collectionName, role: "OWNER", scope: reserveScope }]}
          initialCollectionId={collectionId}
          ownerCollectionId={collectionId}
          loadedSlots={[]}
          busy={editor.busy}
          onConfirm={(candidate) => editor.confirmReserve(candidate)}
          onRelease={editor.releaseFromPicker}
          onClose={editor.closeReserve}
          loadCandidates={readEditorReserveCandidates}
          audience="editor"
        />
      ) : null}

      <BinderCardView
        slot={cardViewSlot && canViewCard(cardViewSlot) ? cardViewSlot : null}
        container={rootRef.current}
        useViewTransition={cardViewMorph}
        onClose={closeCardView}
      />
    </div>
    </CardViewTransitionContext.Provider>
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
