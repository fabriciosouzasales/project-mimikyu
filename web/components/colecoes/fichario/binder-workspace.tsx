"use client";

import Link from "next/link";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useTransition } from "react";
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  pointerWithin,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { AlertTriangle, ArrowLeft, CheckCircle2, Inbox, Plus, RotateCcw, X } from "lucide-react";
import {
  addPages,
  clearReservations,
  moveSlot,
  placeAvailableCard,
  readAvailableCards,
  readBinderPages,
  removeSlots,
  reserveSlot,
  restoreToSlot,
  setSlotImageFocus,
  setSlotsLock,
} from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { cardFrontUrl, formatCount } from "@/lib/colecoes/acervo";
import {
  type BinderPage,
  type BinderSlot,
  type SlotFailure,
  type ViewSide,
  SLOT_BATCH_MAX,
  applyClearReservation,
  applyLock,
  applyMove,
  applyRemove,
  applyReserveCurrent,
  binderHref,
  canReserveCurrent,
  clampPage,
  computeBinderFit,
  firstPageOfView,
  hasReservation,
  isOccupied,
  modelLabel,
  readBatchStart,
  slotFailureMessage,
  viewCount,
  viewForPage,
  viewLabel,
  viewSides,
  BINDER_UNITS,
  addPagesResultMessage,
  type BinderFit,
  type BinderRole,
} from "@/lib/colecoes/binder";
import {
  type AvailableCard,
  applyPlaceAvailable,
  canReceiveAvailable,
  isAddablePocket,
  isForeignSlot,
  mergeAvailable,
  placementSources,
} from "@/lib/colecoes/binder-share";
import { applySlotImage, imageFailureMessage } from "@/lib/colecoes/binder-images";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { cn } from "@/lib/utils";
import { INTERIOR_HUE, InsideCoverFace, SideArrowButton, TopNavControls, blackLeatherSurface, darkZipperTeeth, FOCUS_RING } from "./binder-chrome";
import { AddPagesDialog } from "./binder-add-pages";
import { AvailablePanel, type AvailableState } from "./binder-available";
import { ImageComposer, type ImageDialogMode, SlotImageDialog } from "./binder-image-editor";
import { type PreparedImage, clearSlotImageAndFile, linkNewSlotImage } from "./binder-image-io";
import { PocketPicker } from "./binder-pocket-picker";
import { BinderOverview } from "./binder-overview";
import { BinderPortalContext, BinderSlotView, type SlotDragData, type SlotHandlers } from "./binder-slot";
import { BinderToolRail } from "./binder-tool-rail";
import { BulkActionRail, type TrayItem, TraySurface, TrayToggleButton } from "./binder-tray";
import ws from "./workspace.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
/** Duas páginas só com largura de desktop/tablet deitado; abaixo, uma. */
const SPREAD_MEDIA = "(min-width: 900px)";
/** Pausa sobre a seta, arrastando, para virar a página (spike: ~650 ms). */
const EDGE_FLIP_MS = 650;
/** A 5128 reserva um bolso por chamada: lote de reservas limitado. */
const RESERVE_MAX = 50;
/** "Desfazer" refaz uma atribuição por vez (5131): só para lotes pequenos. */
const UNDO_MAX = 40;

type Toast = { tone: "success" | "error" | "info"; text: string; undo?: { slotId: string; allocationId: string }[] } | null;
type Confirm = { slotIds: string[]; lockedSkipped: number } | null;
type Entry = { page: number; slot: BinderSlot };

/**
 * Área de trabalho do Fichário Digital — experiência do spike aprovado
 * `binder-nav-01` (P2-B-SPIKE-RECOVERY-01) sobre dados e contratos reais.
 *
 * Composição (spike): « ‹ n / N › » acima; setas redondas nas laterais;
 * fichário de couro preto com zíper, contracapa ao lado da página 1, bolsos
 * escuros com a carta como protagonista; trilho de ações em lote à esquerda
 * quando há seleção; Bandeja em pílula embaixo. O fichário sempre cabe
 * inteiro (encaixe por `computeBinderFit`, sete modelos, 8:11).
 *
 * `variant="overlay"`: aberto sobre a página da coleção (ver
 * `binder-overlay.tsx`), sem mexer na URL; `variant="page"`: rota
 * `/fichario`, que acompanha a página em `?pagina=`.
 *
 * Organização — só contratos LIVE da Binder Foundation, via server actions:
 * mover/trocar (5132), fixar/soltar (5130), reservar (5128), liberar reserva
 * (5129), tirar do fichário (5133) com "Desfazer" (5131). A Bandeja é estado
 * da tela (C-45/LDM-36): só grava quando a carta é solta num bolso. Cada gesto
 * aparece na hora e relê o lote afetado da 5223. Coleção arquivada = leitura.
 *
 * Imagem personalizada no bolso (C-198, 5231–5236): aba "Imagem" no
 * seletor do bolso livre; bolso com imagem abre ver/ajustar/substituir/
 * remover. Envio e vínculo seguem `binder-image-io.ts` (caminho novo, apaga
 * só depois da resposta do banco). O bolso só muda depois da confirmação.
 */
export function BinderWorkspace({
  variant,
  collectionId,
  collectionName,
  coverSubtitle,
  columns,
  rows,
  totalPages: initialTotalPages,
  layoutId,
  filledCount,
  editable,
  initialAnchor,
  initialPages,
  backHref,
  onClose,
  role = null,
  ownerCollectionId = null,
  ownerCollectionName = null,
  participantCount = 1,
  ownUnplacedCount = 0,
}: {
  variant: "overlay" | "page";
  collectionId: string;
  collectionName: string;
  /** Linha discreta da contracapa (ex.: "MMKYU · SV1"). */
  coverSubtitle: string | null;
  columns: number;
  rows: number;
  totalPages: number;
  /** Layout do fichário (5223) — necessário para reordenar páginas (5127). */
  layoutId: string | null;
  filledCount: number;
  editable: boolean;
  initialAnchor: number;
  initialPages: BinderPage[];
  backHref: string;
  /** Só no overlay: fechar e voltar à coleção. */
  onClose?: () => void;
  /** Fichário compartilhado (5230): papel desta coleção, proprietária e participantes. */
  role?: BinderRole | null;
  ownerCollectionId?: string | null;
  ownerCollectionName?: string | null;
  participantCount?: number;
  /** Cartas desta coleção ainda sem bolso (badge de "Cartas disponíveis"). */
  ownUnplacedCount?: number;
}) {
  const reducedMotion = usePrefersReducedMotion();
  // Total de páginas vivo: cresce quando o colecionador adiciona páginas (5125).
  const [totalPages, setTotalPages] = useState(initialTotalPages);
  const rootRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);

  // ---- encaixe na tela ----
  const [allowSpread, setAllowSpread] = useState(true);
  const [box, setBox] = useState<{ w: number; h: number }>({ w: 0, h: 0 });
  useLayoutEffect(() => {
    const media = window.matchMedia(SPREAD_MEDIA);
    const apply = () => setAllowSpread(media.matches);
    apply();
    media.addEventListener("change", apply);
    const stage = stageRef.current;
    if (!stage) return () => media.removeEventListener("change", apply);
    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return;
      const { width, height } = entry.contentRect;
      // Respiro para a sombra do objeto.
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

  // ---- navegação (vista 1 = contracapa + página 1; a capa fechada é a da coleção) ----
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
  const forward = useCallback(() => go(view + 1), [go, view]);
  const back = useCallback(() => go(view - 1), [go, view]);

  useEffect(() => {
    if (variant !== "page") return;
    const base = binderHref(collectionId);
    window.history.replaceState(window.history.state, "", anchor > 1 ? `${base}?pagina=${anchor}` : base);
  }, [anchor, collectionId, variant]);

  // ---- páginas (lotes de até 4 da 5223) ----
  const [cache, setCache] = useState<Map<number, BinderPage>>(() => new Map(initialPages.map((p) => [p.pageNumber, p])));
  const [failed, setFailed] = useState<Set<number>>(() => new Set());
  const [, startTransition] = useTransition();
  const pending = useRef<Set<number>>(new Set());
  /** Sobe a cada reordenação de páginas: leituras iniciadas antes são descartadas. */
  const generation = useRef(0);

  const fetchBatch = useCallback(
    async (first: number) => {
      const startedAt = generation.current;
      const result = await readBinderPages({ collectionId, page: first });
      if (startedAt !== generation.current) return;
      if (!result.ok) {
        setFailed((prev) => new Set(prev).add(first));
        return;
      }
      setFailed((prev) => {
        if (!prev.has(first)) return prev;
        const next = new Set(prev);
        next.delete(first);
        return next;
      });
      setCache((prev) => {
        const next = new Map(prev);
        for (const p of result.pages) next.set(p.pageNumber, p);
        return next;
      });
    },
    [collectionId],
  );

  const loadBatch = useCallback(
    (target: number) => {
      const first = readBatchStart(target);
      if (first > totalPages || pending.current.has(first)) return;
      pending.current.add(first);
      startTransition(async () => {
        await fetchBatch(first);
        pending.current.delete(first);
      });
    },
    [fetchBatch, totalPages],
  );

  const refreshPages = useCallback(
    async (pages: number[]) => {
      const batches = [...new Set(pages.filter((p) => p >= 1).map(readBatchStart))];
      await Promise.all(batches.map((first) => fetchBatch(first)));
    },
    [fetchBatch],
  );

  // ---- visão geral de páginas ----
  const [overviewOpen, setOverviewOpen] = useState(false);
  const closeOverview = useCallback(() => setOverviewOpen(false), []);
  const retryBatch = useCallback((page: number) => {
    const first = readBatchStart(page);
    setFailed((prev) => {
      if (!prev.has(first)) return prev;
      const next = new Set(prev);
      next.delete(first);
      return next;
    });
  }, []);

  useEffect(() => {
    const want = (p: number) => p >= 1 && p <= totalPages && !cache.has(p) && !failed.has(readBatchStart(p));
    const first = firstPageOfView(view, perView);
    const around = [...visiblePages, first + perView * 2, first - 1];
    for (const p of around) if (want(p)) loadBatch(p);
  }, [cache, failed, loadBatch, perView, totalPages, view, visiblePages]);

  const slotIndex = useMemo(() => {
    const index = new Map<string, Entry>();
    for (const page of cache.values()) for (const slot of page.slots) index.set(slot.slotId, { page: page.pageNumber, slot });
    return index;
  }, [cache]);

  const patchSlots = useCallback((patches: BinderSlot[]) => {
    if (patches.length === 0) return;
    const byId = new Map(patches.map((slot) => [slot.slotId, slot]));
    setCache((prev) => {
      const next = new Map(prev);
      for (const [number, page] of prev) {
        if (!page.slots.some((slot) => byId.has(slot.slotId))) continue;
        next.set(number, { ...page, slots: page.slots.map((slot) => byId.get(slot.slotId) ?? slot) });
      }
      return next;
    });
  }, []);

  // ---- seleção, Bandeja, mensagens ----
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  const [tray, setTray] = useState<TrayItem[]>([]);
  const [trayOpen, setTrayOpen] = useState(false);
  const [armed, setArmed] = useState<string | null>(null);
  const [toast, setToast] = useState<Toast>(null);
  const [confirm, setConfirm] = useState<Confirm>(null);
  const [busy, setBusy] = useState(false);
  const [filled, setFilled] = useState(filledCount);
  const trayIds = useMemo(() => new Set(tray.map((item) => item.slotId)), [tray]);
  const selectionActive = selected.size > 0;

  useEffect(() => {
    if (!toast || toast.undo) return;
    const timer = window.setTimeout(() => setToast(null), toast.tone === "error" ? 7000 : 3500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  // Seleção que deixou de valer (carta saiu do bolso) é descartada.
  useEffect(() => {
    setSelected((prev) => {
      let changed = false;
      const next = new Set<string>();
      for (const id of prev) {
        const entry = slotIndex.get(id);
        if (entry && isOccupied(entry.slot) && !trayIds.has(id)) next.add(id);
        else changed = true;
      }
      return changed ? next : prev;
    });
  }, [slotIndex, trayIds]);

  const fail = useCallback((reason: SlotFailure) => setToast({ tone: "error", text: slotFailureMessage(reason) }), []);

  // ---- fichário compartilhado: Cartas disponíveis e "Só desta coleção" ----
  const shared = participantCount > 1;
  const [onlyMine, setOnlyMine] = useState(false);
  const [availableOpen, setAvailableOpen] = useState(false);
  const [available, setAvailable] = useState<AvailableState>({ status: "idle", items: [], total: ownUnplacedCount, loadingMore: false });
  const [armedCard, setArmedCard] = useState<AvailableCard | null>(null);
  // "Adicionar carta" no bolso vazio e "Adicionar páginas" (P2-BINDER-CAPACITY-AND-EMPTY-SLOT-01).
  const [pocketTarget, setPocketTarget] = useState<Entry | null>(null);
  // Imagem personalizada (C-198): bolso aberto no diálogo da imagem.
  const [imageTarget, setImageTarget] = useState<{ slotId: string; mode: ImageDialogMode } | null>(null);
  /** Prévias locais (`blob:`) mostradas nos bolsos até a releitura — revogadas ao sair. */
  const blobUrls = useRef<Set<string>>(new Set());
  useEffect(() => {
    const urls = blobUrls.current;
    return () => {
      for (const url of urls) URL.revokeObjectURL(url);
    };
  }, []);
  const [addPagesOpen, setAddPagesOpen] = useState(false);
  const [addingPages, setAddingPages] = useState(false);
  const sources = useMemo(
    () => placementSources({ collectionId, collectionName, role, ownerCollectionId, ownerCollectionName }),
    [collectionId, collectionName, ownerCollectionId, ownerCollectionName, role],
  );
  const availableById = useMemo(() => new Map(available.items.map((card) => [card.allocationId, card])), [available.items]);

  const loadAvailable = useCallback(
    async (offset: number) => {
      setAvailable((prev) => (offset === 0 ? { ...prev, status: "loading" } : { ...prev, loadingMore: true }));
      const result = await readAvailableCards({ collectionId, offset });
      setAvailable((prev) => {
        if (!result.ok) return offset === 0 ? { ...prev, status: "error", loadingMore: false } : { ...prev, loadingMore: false };
        return {
          status: "ready",
          items: offset === 0 ? result.items : mergeAvailable(prev.items, result.items),
          total: result.total || (offset === 0 ? result.items.length : prev.total),
          loadingMore: false,
        };
      });
      if (!result.ok && offset > 0) setToast({ tone: "error", text: "Não conseguimos carregar mais cartas. Tente de novo." });
    },
    [collectionId],
  );

  const toggleAvailable = useCallback(() => {
    if (availableOpen) {
      setAvailableOpen(false);
      setArmedCard(null);
      return;
    }
    setAvailableOpen(true);
    // Cada abertura relê a lista (o banco é a autoridade; outra tela pode ter posicionado cartas).
    if (available.status !== "loading") void loadAvailable(0);
  }, [available.status, availableOpen, loadAvailable]);

  // ---- tela cheia ----
  const [fullscreen, setFullscreen] = useState(false);
  useEffect(() => {
    const onChange = () => setFullscreen(document.fullscreenElement === rootRef.current);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);
  const [canFullscreen, setCanFullscreen] = useState(false);
  useEffect(() => setCanFullscreen(typeof document.documentElement.requestFullscreen === "function"), []);
  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void rootRef.current?.requestFullscreen?.().catch(() => setToast({ tone: "error", text: "O navegador não permitiu a tela cheia." }));
  }, []);

  // ---- operações (o banco é a autoridade) ----

  const place = useCallback(
    async (fromId: string, toId: string) => {
      const from = slotIndex.get(fromId);
      const to = slotIndex.get(toId);
      if (fromId === toId) {
        setTray((prev) => prev.filter((item) => item.slotId !== fromId));
        setArmed(null);
        return;
      }
      if (!from || !to || !editable || busy) return;
      if (from.slot.locked || to.slot.locked) return fail("locked");
      if (to.slot.image) {
        setToast({ tone: "info", text: "Esse bolso tem uma imagem. Remova a imagem para colocar uma carta nele." });
        return;
      }
      if (trayIds.has(toId)) {
        setToast({ tone: "info", text: "Esse bolso está esperando uma carta da Bandeja. Escolha outro." });
        return;
      }
      if (!isOccupied(from.slot)) return fail("source_empty");
      const [nextFrom, nextTo] = applyMove(from.slot, to.slot);
      patchSlots([nextFrom, nextTo]);
      setTray((prev) => prev.filter((item) => item.slotId !== fromId));
      setArmed(null);
      setSelected(new Set());
      setBusy(true);
      const result = await moveSlot({ collectionId, fromSlotId: fromId, toSlotId: toId });
      setBusy(false);
      if (result.ok) {
        const name = from.slot.present?.cardName ?? "Carta";
        setToast({
          tone: "success",
          text: result.operation === "SWAP" ? `${name} e ${to.slot.present?.cardName ?? "a outra carta"} trocaram de lugar.` : `${name} foi para a página ${to.page}.`,
        });
      } else {
        patchSlots([from.slot, to.slot]);
        fail(result.reason);
      }
      await refreshPages([from.page, to.page]);
    },
    [busy, collectionId, editable, fail, patchSlots, refreshPages, slotIndex, trayIds],
  );

  /**
   * Adicionar páginas ao fim (5125): só depois da resposta do banco o total
   * cresce, as páginas novas são lidas e o fichário vai até a primeira delas.
   * Parcial (o banco recusou no meio) é dito com clareza.
   */
  const runAddPages = useCallback(
    async (count: number) => {
      if (!layoutId || !editable || addingPages) return;
      setAddingPages(true);
      const before = totalPages;
      const result = await addPages({ collectionId, layoutId, count }).catch(() => ({ ok: false as const, reason: "unknown" as const }));
      setAddingPages(false);
      if (!result.ok) {
        fail(result.reason);
        return;
      }
      const after = result.lastPageNumber ?? before + result.added;
      setAddPagesOpen(false);
      setTotalPages(after);
      setFailed(new Set());
      const fresh = Array.from({ length: Math.max(0, after - before) }, (_, index) => before + 1 + index);
      await refreshPages(fresh);
      setDirection(1);
      setAnchor(before + 1);
      const message = addPagesResultMessage(result.added, count, result.slotsPerPage ?? columns * rows);
      setToast(result.failure ? { tone: "error", text: `${message} ${slotFailureMessage(result.failure)}` } : { tone: "success", text: message });
    },
    [addingPages, collectionId, columns, editable, fail, layoutId, refreshPages, rows, totalPages],
  );

  /** Posicionar uma carta disponível (5131). Só bolso vazio e solto — nunca substitui outra carta. */
  const placeAvailable = useCallback(
    async (card: AvailableCard, toId: string, sourceCollectionId: string = collectionId) => {
      const to = slotIndex.get(toId);
      if (!to || !editable || busy) return;
      if (!canReceiveAvailable(to.slot, sourceCollectionId)) {
        setToast({
          tone: "info",
          text: to.slot.locked
            ? "Esse bolso está fixado. Escolha um bolso vazio e solto."
            : to.slot.image
              ? "Esse bolso tem uma imagem. Remova a imagem para colocar uma carta nele."
              : to.slot.state === "RESERVED_EMPTY"
              ? "Esse bolso está reservado para uma carta de outra coleção. Escolha um bolso vazio."
              : "Escolha um bolso vazio — uma carta disponível nunca substitui outra.",
        });
        return;
      }
      const own = sourceCollectionId === collectionId;
      patchSlots([applyPlaceAvailable(to.slot, card, sourceCollectionId)]);
      setArmedCard(null);
      setSelected(new Set());
      if (own) {
        setAvailable((prev) => ({ ...prev, items: prev.items.filter((item) => item.allocationId !== card.allocationId), total: Math.max(0, prev.total - 1) }));
      }
      setBusy(true);
      const result = await placeAvailableCard({ collectionId, slotId: toId, allocationId: card.allocationId });
      setBusy(false);
      if (result.ok) {
        setFilled((value) => value + 1);
        setToast({ tone: "success", text: `${card.cardName} foi para a página ${to.page}.` });
      } else {
        patchSlots([to.slot]);
        // Devolve a carta à lista; "já tem lugar" ou estado velho relê a lista do banco.
        if (own) {
          if (result.reason === "already_placed" || result.reason === "stale" || result.reason === "unknown") void loadAvailable(0);
          else setAvailable((prev) => ({ ...prev, items: [card, ...prev.items], total: prev.total + 1 }));
        }
        fail(result.reason);
      }
      await refreshPages([to.page]);
    },
    [busy, collectionId, editable, fail, loadAvailable, patchSlots, refreshPages, slotIndex],
  );

  // ---- imagem personalizada do bolso (C-198) ----

  /**
   * Envia (caminho novo) e vincula; serve para colocar e substituir. O bolso
   * só muda depois do "sim" do banco; resposta incerta relê a página e não
   * apaga nada. Devolve `null` no sucesso ou a mensagem para o diálogo.
   */
  const submitImage = useCallback(
    async (slotId: string, image: PreparedImage, focalY: number, onStage: (stage: "upload" | "link") => void): Promise<string | null> => {
      const entry = slotIndex.get(slotId);
      if (!entry || !layoutId || !editable) return imageFailureMessage("not_found");
      const outcome = await linkNewSlotImage({ collectionId, layoutId, slotId, image, focalY, onStage });
      if (!outcome.ok) {
        if (outcome.uncertain || outcome.reason === "slot_taken" || outcome.reason === "slot_reserved" || outcome.reason === "slot_locked" || outcome.reason === "not_found") {
          void refreshPages([entry.page]);
        }
        return outcome.message;
      }
      blobUrls.current.add(image.url);
      patchSlots([applySlotImage(entry.slot, { path: outcome.result.path, focalY: outcome.result.focalY, updatedAt: null, url: image.url })]);
      setPocketTarget(null);
      setImageTarget(null);
      setToast({ tone: "success", text: outcome.result.operation === "REPLACED" ? `Imagem substituída na página ${entry.page}.` : `Imagem colocada no bolso da página ${entry.page}.` });
      void refreshPages([entry.page]);
      return null;
    },
    [collectionId, editable, layoutId, patchSlots, refreshPages, slotIndex],
  );

  const saveImageFocus = useCallback(
    async (slotId: string, focalY: number): Promise<string | null> => {
      const entry = slotIndex.get(slotId);
      const current = entry?.slot.image;
      if (!entry || !current || !editable) return imageFailureMessage("image_missing");
      const result = await setSlotImageFocus({ collectionId, slotId, focalY }).catch(() => ({ ok: false as const, reason: "unknown" as const }));
      if (!result.ok) {
        if (result.reason === "image_missing" || result.reason === "unknown") void refreshPages([entry.page]);
        return imageFailureMessage(result.reason);
      }
      patchSlots([applySlotImage(entry.slot, { ...current, focalY: result.focalY })]);
      setImageTarget(null);
      setToast({ tone: "success", text: "Enquadramento salvo." });
      return null;
    },
    [collectionId, editable, patchSlots, refreshPages, slotIndex],
  );

  const removeImage = useCallback(
    async (slotId: string): Promise<string | null> => {
      const entry = slotIndex.get(slotId);
      if (!entry || !editable) return imageFailureMessage("image_missing");
      const result = await clearSlotImageAndFile({ collectionId, slotId });
      if (!result.ok) {
        void refreshPages([entry.page]);
        return result.message;
      }
      patchSlots([applySlotImage(entry.slot, null)]);
      setImageTarget(null);
      setToast({ tone: "success", text: result.removed ? "Imagem removida. O bolso está livre." : "Esse bolso já estava sem imagem." });
      void refreshPages([entry.page]);
      return null;
    },
    [collectionId, editable, patchSlots, refreshPages, slotIndex],
  );

  const entriesFor = useCallback(
    (ids: Iterable<string>) => [...ids].map((id) => slotIndex.get(id)).filter((entry): entry is Entry => Boolean(entry)),
    [slotIndex],
  );
  const selectedEntries = useMemo(() => entriesFor(selected), [entriesFor, selected]);

  const toTray = useCallback(
    (ids: string[]) => {
      const items: TrayItem[] = [];
      for (const { page, slot } of entriesFor(ids)) {
        if (slot.locked || !isOccupied(slot) || trayIds.has(slot.slotId)) continue;
        items.push({ slotId: slot.slotId, page, name: slot.present?.cardName ?? "Carta", imagePath: slot.present?.imagePath ?? null });
      }
      if (items.length === 0) return;
      setTray((prev) => [...prev, ...items]);
      setSelected(new Set());
      setToast({
        tone: "info",
        text:
          items.length === 1
            ? `${items[0]?.name} está na Bandeja. Vá até a página de destino e solte a carta num bolso.`
            : `${items.length} cartas na Bandeja. Vá até a página de destino e solte cada uma num bolso.`,
      });
    },
    [entriesFor, trayIds],
  );

  const runLock = useCallback(
    async (entries: Entry[], locked: boolean) => {
      const targets = entries.filter(({ slot }) => slot.locked !== locked && !(locked && trayIds.has(slot.slotId)));
      if (targets.length === 0 || busy || !editable) return;
      if (targets.length > SLOT_BATCH_MAX) return fail("too_many");
      patchSlots(targets.map(({ slot }) => applyLock(slot, locked)));
      setBusy(true);
      const result = await setSlotsLock({ collectionId, slotIds: targets.map(({ slot }) => slot.slotId), locked });
      setBusy(false);
      if (result.ok) {
        setToast({
          tone: "success",
          text: locked
            ? `${targets.length === 1 ? "Bolso fixado" : `${targets.length} bolsos fixados`}: nada sai nem entra até você soltar.`
            : `${targets.length === 1 ? "Bolso solto" : `${targets.length} bolsos soltos`}.`,
        });
      } else {
        patchSlots(targets.map(({ slot }) => slot));
        fail(result.reason);
      }
      await refreshPages(targets.map(({ page }) => page));
    },
    [busy, collectionId, editable, fail, patchSlots, refreshPages, trayIds],
  );

  const runReserve = useCallback(
    async (entries: Entry[]) => {
      const targets = entries.filter(({ slot }) => canReserveCurrent(slot));
      if (targets.length === 0 || busy || !editable) return;
      if (targets.length > RESERVE_MAX) {
        setToast({ tone: "error", text: `Reserve até ${RESERVE_MAX} bolsos por vez.` });
        return;
      }
      patchSlots(targets.map(({ slot }) => applyReserveCurrent(slot)));
      setBusy(true);
      let failure: SlotFailure | null = null;
      let done = 0;
      for (const { slot } of targets) {
        if (!slot.presentCardId) continue;
        const result = await reserveSlot({ collectionId, slotId: slot.slotId, cardId: slot.presentCardId, variantTypeId: slot.presentVariantTypeId });
        if (!result.ok) {
          failure = result.reason;
          break;
        }
        done += 1;
      }
      setBusy(false);
      if (failure) fail(failure);
      else setToast({ tone: "success", text: done === 1 ? "Bolso reservado para esta carta: se ela sair, o lugar fica guardado." : `${done} bolsos reservados.` });
      await refreshPages(targets.map(({ page }) => page));
    },
    [busy, collectionId, editable, fail, patchSlots, refreshPages],
  );

  const runClearReservation = useCallback(
    async (entries: Entry[]) => {
      const targets = entries.filter(({ slot }) => hasReservation(slot));
      if (targets.length === 0 || busy || !editable) return;
      if (targets.length > SLOT_BATCH_MAX) return fail("too_many");
      patchSlots(targets.map(({ slot }) => applyClearReservation(slot)));
      setBusy(true);
      const result = await clearReservations({ collectionId, slotIds: targets.map(({ slot }) => slot.slotId) });
      setBusy(false);
      if (result.ok) setToast({ tone: "success", text: targets.length === 1 ? "Reserva liberada." : `${targets.length} reservas liberadas.` });
      else {
        patchSlots(targets.map(({ slot }) => slot));
        fail(result.reason);
      }
      await refreshPages(targets.map(({ page }) => page));
    },
    [busy, collectionId, editable, fail, patchSlots, refreshPages],
  );

  const runRemove = useCallback(
    async (ids: string[]) => {
      const targets = entriesFor(ids).filter(({ slot }) => isOccupied(slot) && !slot.locked && !trayIds.has(slot.slotId));
      setConfirm(null);
      if (targets.length === 0 || busy || !editable) return;
      if (targets.length > SLOT_BATCH_MAX) return fail("too_many");
      const undo = targets.filter(({ slot }) => slot.allocationId).map(({ slot }) => ({ slotId: slot.slotId, allocationId: slot.allocationId as string }));
      patchSlots(targets.map(({ slot }) => applyRemove(slot)));
      setSelected(new Set());
      setBusy(true);
      const result = await removeSlots({ collectionId, slotIds: targets.map(({ slot }) => slot.slotId) });
      setBusy(false);
      if (result.ok) {
        setFilled((value) => Math.max(0, value - result.count));
        setToast({
          tone: "success",
          text: result.count === 1 ? "A carta saiu do fichário e continua na coleção." : `${result.count} cartas saíram do fichário e continuam na coleção.`,
          undo: undo.length > 0 && undo.length <= UNDO_MAX ? undo : undefined,
        });
      } else {
        patchSlots(targets.map(({ slot }) => slot));
        fail(result.reason);
      }
      await refreshPages(targets.map(({ page }) => page));
    },
    [busy, collectionId, editable, entriesFor, fail, patchSlots, refreshPages, trayIds],
  );

  const runUndo = useCallback(
    async (items: { slotId: string; allocationId: string }[]) => {
      if (busy) return;
      setToast(null);
      setBusy(true);
      let restored = 0;
      let failure: SlotFailure | null = null;
      for (const item of items) {
        const result = await restoreToSlot({ collectionId, slotId: item.slotId, allocationId: item.allocationId });
        if (!result.ok) {
          failure = result.reason;
          break;
        }
        restored += 1;
      }
      setBusy(false);
      setFilled((value) => value + restored);
      if (failure) fail(failure);
      else setToast({ tone: "success", text: restored === 1 ? "A carta voltou ao bolso." : `${restored} cartas voltaram aos bolsos.` });
      await refreshPages(items.map((item) => slotIndex.get(item.slotId)?.page ?? 0));
    },
    [busy, collectionId, fail, refreshPages, slotIndex],
  );

  // ---- gestos nos bolsos ----
  const justDragged = useRef(false);

  const toggleSelect = useCallback((slot: BinderSlot) => {
    if (!isOccupied(slot)) return;
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(slot.slotId)) next.delete(slot.slotId);
      else next.add(slot.slotId);
      return next;
    });
  }, []);

  const handlers = useMemo<SlotHandlers>(
    () => ({
      onActivate: (slot, additive) => {
        if (justDragged.current) return;
        if (armedCard) {
          void placeAvailable(armedCard, slot.slotId);
          return;
        }
        if (armed) {
          void place(armed, slot.slotId);
          return;
        }
        // Spike: com seleção ativa (ou Ctrl/⌘/Shift) o clique alterna a seleção.
        if (selectionActive || additive) {
          toggleSelect(slot);
          return;
        }
        // Bolso com imagem personalizada: abre a imagem (ver; ajustar/substituir/remover se editável).
        if (slot.image) {
          setImageTarget({ slotId: slot.slotId, mode: "view" });
          return;
        }
        // Spike binder-nav-01: tocar um bolso vazio e solto abre "Adicionar carta".
        if (editable && !busy && isAddablePocket(slot) && !trayIds.has(slot.slotId)) {
          const entry = slotIndex.get(slot.slotId);
          if (entry) setPocketTarget(entry);
        }
      },
      onToggleSelect: toggleSelect,
      onToggleLock: (slot) => {
        const entry = slotIndex.get(slot.slotId);
        if (entry) void runLock([entry], !slot.locked);
      },
      onToTray: (slot) => toTray([slot.slotId]),
      onReturnFromTray: (slot) => {
        // Devolver ao próprio bolso: só sai da Bandeja, nada é gravado.
        setTray((prev) => prev.filter((item) => item.slotId !== slot.slotId));
        setArmed((current) => (current === slot.slotId ? null : current));
      },
      onReserve: (slot) => {
        const entry = slotIndex.get(slot.slotId);
        if (entry) void runReserve([entry]);
      },
      onClearReserve: (slot) => {
        const entry = slotIndex.get(slot.slotId);
        if (entry) void runClearReservation([entry]);
      },
      // Retirada sempre confirmada (o "Desfazer" continua depois de tirar).
      onRemove: (slot) => {
        if (!isOccupied(slot) || slot.locked || trayIds.has(slot.slotId)) return;
        setToast(null);
        setConfirm({ slotIds: [slot.slotId], lockedSkipped: 0 });
      },
      onAddCard: (slot) => {
        if (!editable || busy || !isAddablePocket(slot)) return;
        const entry = slotIndex.get(slot.slotId);
        if (entry) setPocketTarget(entry);
      },
      onOpenImage: (slot, mode) => {
        if (!slot.image) return;
        setToast(null);
        setImageTarget({ slotId: slot.slotId, mode: editable ? mode : "view" });
      },
    }),
    [armed, armedCard, busy, editable, place, placeAvailable, runClearReservation, runLock, runReserve, selectionActive, slotIndex, toTray, toggleSelect, trayIds],
  );

  // ← → páginas, Home/End; Esc desfaz em camadas: confirmação → carta escolhida → Bandeja aberta → seleção → fechar.
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
      // A visão geral cuida do próprio teclado (Esc fecha só ela).
      if (overviewOpen) return;
      const target = event.target as HTMLElement | null;
      if (target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
      if (target?.closest("[role='menu']")) return;
      if (event.key === "ArrowRight" || event.key === "PageDown") {
        event.preventDefault();
        forward();
      } else if (event.key === "ArrowLeft" || event.key === "PageUp") {
        event.preventDefault();
        back();
      } else if (event.key === "Home") {
        event.preventDefault();
        go(1);
      } else if (event.key === "End") {
        event.preventDefault();
        go(lastView);
      } else if (event.key === "Escape") {
        event.preventDefault();
        if (imageTarget || pocketTarget) return;
        if (confirm) setConfirm(null);
        else if (armedCard) setArmedCard(null);
        else if (armed) setArmed(null);
        else if (availableOpen) setAvailableOpen(false);
        else if (trayOpen) setTrayOpen(false);
        else if (selected.size > 0) setSelected(new Set());
        else if (document.fullscreenElement) void document.exitFullscreen();
        else onClose?.();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [armed, armedCard, availableOpen, back, confirm, forward, go, imageTarget, lastView, onClose, overviewOpen, pocketTarget, selected.size, trayOpen]);

  // ---- arrastar e soltar (pointer/touch; teclado usa "…" → Bandeja → bolso) ----
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 8 } }),
  );
  const [dragging, setDragging] = useState<SlotDragData | null>(null);
  const [overEdge, setOverEdge] = useState<"prev" | "next" | null>(null);

  useEffect(() => {
    if (!overEdge || !dragging) return;
    const timer = window.setTimeout(() => (overEdge === "next" ? forward() : back()), EDGE_FLIP_MS);
    return () => window.clearTimeout(timer);
  }, [back, dragging, forward, overEdge, view]);

  const endDrag = useCallback(() => {
    setDragging(null);
    setOverEdge(null);
    justDragged.current = true;
    window.setTimeout(() => (justDragged.current = false), 0);
  }, []);

  const onDragStart = useCallback((event: DragStartEvent) => {
    const data = event.active.data.current as SlotDragData | undefined;
    if (data) setDragging(data);
    setConfirm(null);
  }, []);

  const onDragOver = useCallback((event: DragOverEvent) => {
    const id = event.over?.id;
    setOverEdge(id === "edge:next" ? "next" : id === "edge:prev" ? "prev" : null);
  }, []);

  const onDragEnd = useCallback(
    (event: DragEndEvent) => {
      const data = event.active.data.current as SlotDragData | undefined;
      const over = typeof event.over?.id === "string" ? event.over.id : null;
      endDrag();
      if (!data || !over) return;
      if (data.kind === "available") {
        const card = availableById.get(data.slotId);
        if (over === "tray") setToast({ tone: "info", text: "A Bandeja é para cartas que já estão no fichário. Solte esta carta num bolso vazio." });
        else if (card && over.startsWith("pocket:")) void placeAvailable(card, over.slice("pocket:".length));
        return;
      }
      if (over === "tray") {
        if (data.kind === "slot") toTray([data.slotId]);
        return;
      }
      if (over.startsWith("pocket:")) void place(data.slotId, over.slice("pocket:".length));
    },
    [availableById, endDrag, place, placeAvailable, toTray],
  );

  // ---- trilho de seleção ----
  const bulk = {
    tray: editable && selectedEntries.some(({ slot }) => !slot.locked && !trayIds.has(slot.slotId)),
    lock: editable && selectedEntries.some(({ slot }) => !slot.locked),
    unlock: editable && selectedEntries.some(({ slot }) => slot.locked),
    reserve: editable && selectedEntries.some(({ slot }) => canReserveCurrent(slot)),
    clearReserve: editable && selectedEntries.some(({ slot }) => hasReservation(slot)),
    remove: editable && selectedEntries.some(({ slot }) => !slot.locked && !trayIds.has(slot.slotId)),
  };
  const askBulkRemove = () => {
    const ids = selectedEntries.filter(({ slot }) => !slot.locked && !trayIds.has(slot.slotId)).map(({ slot }) => slot.slotId);
    if (ids.length === 0) return;
    setToast(null);
    setConfirm({ slotIds: ids, lockedSkipped: selectedEntries.length - ids.length });
  };

  const label = viewLabel(view, perView, totalPages);
  const sizes = `${Math.max(1, fit.pocket)}px`;
  const portalRef = rootRef;
  const placing = armed !== null || dragging !== null || armedCard !== null;
  const placingAvailable = armedCard !== null || dragging?.kind === "available";

  return (
    <BinderPortalContext.Provider value={portalRef}>
      <div ref={rootRef} className={cn("binder-nav-01-scope", ws.root)} data-variant={variant} data-fullscreen={fullscreen || undefined}>
        <div aria-hidden className={ws.glow} />

        <header className={ws.top}>
          <div className={ws.identity}>
            {variant === "page" ? (
              <Link href={backHref} className={cn(ws.iconButton, FOCUS_RING)} aria-label="Voltar à coleção">
                <ArrowLeft className="h-4 w-4" aria-hidden />
              </Link>
            ) : null}
            <div className={ws.identityText}>
              <h2 className={ws.title} id="fichario-titulo">
                {collectionName}
              </h2>
              <p className={ws.facts}>
                {role === "GUEST" && ownerCollectionName ? `Fichário de ${ownerCollectionName} · ` : shared ? "Compartilhado · " : ""}
                {modelLabel(columns, rows)} · {formatCount(totalPages)} {totalPages === 1 ? "página" : "páginas"} · {formatCount(filled)}{" "}
                {filled === 1 ? "carta" : "cartas"}
                {!editable ? " · somente leitura" : ""}
              </p>
            </div>
          </div>

          <TopNavControls index={view} total={lastView} label={label} onFirst={() => go(1)} onPrev={back} onNext={forward} onLast={() => go(lastView)} />

          <div className={ws.actions}>
            {onClose ? (
              <button type="button" className={cn(ws.iconButton, FOCUS_RING)} onClick={onClose} aria-label="Fechar o fichário (Esc)" title="Fechar (Esc)">
                <X className="h-4 w-4" aria-hidden />
              </button>
            ) : null}
          </div>
        </header>

        <DndContext sensors={sensors} collisionDetection={pointerWithin} onDragStart={onDragStart} onDragOver={onDragOver} onDragEnd={onDragEnd} onDragCancel={endDrag}>
          {/* Menu lateral de organização (spike TOOL-RAIL-03): permanente. */}
          <div className={ws.rail}>
            <BinderToolRail
              state={{
                editable,
                busy,
                overviewOpen,
                canAddPages: editable && layoutId !== null,
                trayCount: tray.length,
                trayOpen,
                availableCount: available.total,
                availableOpen,
                shared,
                onlyMine,
                canFullscreen,
                fullscreen,
                count: selected.size,
                canTray: bulk.tray,
                canLock: bulk.lock,
                canUnlock: bulk.unlock,
                canReserve: bulk.reserve,
                canClearReserve: bulk.clearReserve,
                canRemove: bulk.remove,
              }}
              actions={{
                onOpenOverview: () => {
                  setArmed(null);
                  setConfirm(null);
                  setOverviewOpen(true);
                },
                onAddPages: () => {
                  setArmed(null);
                  setArmedCard(null);
                  setConfirm(null);
                  setAddPagesOpen(true);
                },
                onToggleTray: () => setTrayOpen((value) => !value),
                onToggleAvailable: toggleAvailable,
                onToggleOnlyMine: () => setOnlyMine((value) => !value),
                onToggleFullscreen: toggleFullscreen,
                onMoveToTray: () => toTray([...selected]),
                onLock: () => void runLock(selectedEntries, true),
                onUnlock: () => void runLock(selectedEntries, false),
                onReserve: () => void runReserve(selectedEntries),
                onClearReserve: () => void runClearReservation(selectedEntries),
                onRemove: askBulkRemove,
                onClear: () => setSelected(new Set()),
              }}
            />
          </div>

          <div className={ws.prev}>
            <SideArrowButton direction="prev" onClick={back} disabled={view <= 1} dragActive={dragging !== null} />
          </div>

          <section ref={stageRef} className={ws.stage} aria-label={`Fichário — ${label}`}>
            {fit.pocket > 0 ? (
              <BinderObject
                key={sides.length}
                fit={fit}
                columns={columns}
                rows={rows}
                sides={sides}
                view={view}
                direction={direction}
                animate={!reducedMotion}
                cache={cache}
                failed={failed}
                coverTitle={collectionName}
                coverSubtitle={coverSubtitle}
                sizes={sizes}
                editable={editable && !busy}
                selected={selected}
                selectionActive={selectionActive}
                trayIds={trayIds}
                armed={armed}
                dragging={dragging}
                placing={placing}
                placingAvailable={placingAvailable}
                focusCollectionId={shared && onlyMine ? collectionId : null}
                handlers={handlers}
                onRetry={retryBatch}
                onAddPages={editable && layoutId && !busy ? () => setAddPagesOpen(true) : null}
              />
            ) : null}
          </section>

          <div className={ws.next}>
            <SideArrowButton direction="next" onClick={forward} disabled={view >= lastView} dragActive={dragging !== null} />
          </div>

          <div className={ws.bottom}>
            {confirm ? (
              <Message tone="error" role="alertdialog">
                <p>
                  {confirm.slotIds.length === 1
                    ? `Tirar ${slotIndex.get(confirm.slotIds[0] ?? "")?.slot.present?.cardName ?? "esta carta"} do fichário? Ela continua na coleção.`
                    : `Tirar ${confirm.slotIds.length} cartas do fichário? Elas continuam na coleção.`}
                  {confirm.lockedSkipped > 0 ? ` ${confirm.lockedSkipped} em bolso fixado ${confirm.lockedSkipped === 1 ? "fica" : "ficam"}.` : ""}
                </p>
                <span className={ws.messageActions}>
                  <Button size="sm" variant="outline" className="h-8 border-white/20 bg-transparent text-white hover:bg-white/10" onClick={() => setConfirm(null)}>
                    Cancelar
                  </Button>
                  <Button size="sm" variant="destructive" className="h-8" onClick={() => void runRemove(confirm.slotIds)} autoFocus>
                    Tirar
                  </Button>
                </span>
              </Message>
            ) : toast ? (
              <Message tone={toast.tone} role={toast.tone === "error" ? "alert" : "status"}>
                <p>{toast.text}</p>
                <span className={ws.messageActions}>
                  {toast.undo ? (
                    <Button size="sm" variant="outline" className="h-8 border-white/20 bg-transparent text-white hover:bg-white/10" onClick={() => void runUndo(toast.undo ?? [])}>
                      <RotateCcw className="h-3.5 w-3.5" aria-hidden />
                      Desfazer
                    </Button>
                  ) : null}
                  <button type="button" className="rounded-full p-1 text-white/60 hover:bg-white/10 hover:text-white" onClick={() => setToast(null)} aria-label="Dispensar mensagem">
                    <X className="h-3.5 w-3.5" aria-hidden />
                  </button>
                </span>
              </Message>
            ) : null}

            <div className={ws.trayAnchor}>
              {trayOpen ? (
                <TraySurface
                  items={tray}
                  armed={armed}
                  onArm={(id) => {
                    setSelected(new Set());
                    setArmedCard(null);
                    setArmed((current) => (current === id ? null : id));
                  }}
                  onReturn={(id) => {
                    setTray((prev) => prev.filter((item) => item.slotId !== id));
                    if (armed === id) setArmed(null);
                  }}
                  onClose={() => setTrayOpen(false)}
                />
              ) : null}
              {selectionActive ? (
                <div className={ws.contextBar}>
                  <BulkActionRail
                    count={selected.size}
                    canTray={bulk.tray}
                    showLock={bulk.lock}
                    showUnlock={bulk.unlock}
                    canRemove={bulk.remove}
                    busy={busy}
                    onMoveToTray={() => toTray([...selected])}
                    onLock={() => void runLock(selectedEntries, true)}
                    onUnlock={() => void runLock(selectedEntries, false)}
                    onRemove={askBulkRemove}
                    onClear={() => setSelected(new Set())}
                  />
                </div>
              ) : null}
              <TrayToggleButton count={tray.length} open={trayOpen} dragActive={dragging?.kind === "slot"} disabled={!editable} onToggle={() => setTrayOpen((value) => !value)} />
            </div>
          </div>

          {availableOpen ? (
            <AvailablePanel
              collectionName={collectionName}
              state={available}
              editable={editable}
              armedId={armedCard?.allocationId ?? null}
              onArm={(card) => {
                setSelected(new Set());
                setArmed(null);
                setArmedCard((current) => (current?.allocationId === card.allocationId ? null : card));
              }}
              onLoadMore={() => void loadAvailable(available.items.length)}
              onRetry={() => void loadAvailable(0)}
              onClose={() => {
                setAvailableOpen(false);
                setArmedCard(null);
              }}
            />
          ) : null}

          <DragOverlay dropAnimation={null}>
            {dragging ? <DragPreview data={dragging} slotIndex={slotIndex} availableById={availableById} pocket={fit.pocket} /> : null}
          </DragOverlay>
        </DndContext>

        {overviewOpen ? (
          <BinderOverview
            host={rootRef.current}
            collectionId={collectionId}
            layoutId={layoutId}
            editable={editable}
            columns={columns}
            rows={rows}
            totalPages={totalPages}
            filled={filled}
            currentPages={visiblePages}
            cache={cache}
            failed={failed}
            loadBatch={loadBatch}
            onRetry={retryBatch}
            onGoToPage={(page) => {
              const target = clampPage(page, totalPages);
              setDirection(target >= anchor ? 1 : -1);
              setAnchor(target);
            }}
            onReordered={(message) => {
              // Páginas trocaram de número: relê tudo a partir do LIVE (bolsos, Bandeja e seleção continuam válidos — ids de bolso não mudam).
              generation.current += 1;
              pending.current.clear();
              setFailed(new Set());
              setCache(new Map());
              setToast({ tone: "success", text: message });
            }}
            onRequestAddPages={editable && layoutId ? () => setAddPagesOpen(true) : null}
            onClose={closeOverview}
          />
        ) : null}

        {addPagesOpen ? (
          <AddPagesDialog
            host={rootRef.current}
            columns={columns}
            rows={rows}
            totalPages={totalPages}
            busy={addingPages}
            onConfirm={(count) => void runAddPages(count)}
            onClose={() => setAddPagesOpen(false)}
          />
        ) : null}

        {pocketTarget ? (
          <PocketPicker
            host={rootRef.current}
            target={pocketTarget.slot}
            pageNumber={pocketTarget.page}
            sources={sources}
            onPick={(card, source) => {
              const slotId = pocketTarget.slot.slotId;
              setPocketTarget(null);
              void placeAvailable(card, slotId, source);
            }}
            onClose={() => setPocketTarget(null)}
            imageTab={
              layoutId
                ? {
                    // Imagem só em bolso realmente livre: vazio, solto e sem reserva (5232).
                    available: pocketTarget.slot.state === "EMPTY" && !pocketTarget.slot.locked,
                    reason:
                      pocketTarget.slot.state === "RESERVED_EMPTY"
                        ? "Este bolso está reservado para uma carta — libere a reserva para usar uma imagem."
                        : pocketTarget.slot.locked
                          ? "Este bolso está fixado — solte o cadeado para usar uma imagem."
                          : null,
                    render: () => (
                      <ImageComposer
                        collectionId={collectionId}
                        onSubmit={(image, focalY, onStage) => submitImage(pocketTarget.slot.slotId, image, focalY, onStage)}
                      />
                    ),
                  }
                : null
            }
          />
        ) : null}

        {imageTarget
          ? (() => {
              const entry = slotIndex.get(imageTarget.slotId);
              const image = entry?.slot.image;
              if (!entry || !image) return null;
              return (
                <SlotImageDialog
                  key={`${imageTarget.slotId}:${imageTarget.mode}`}
                  host={rootRef.current}
                  collectionId={collectionId}
                  slot={entry.slot}
                  image={image}
                  pageNumber={entry.page}
                  editable={editable && layoutId !== null}
                  initialMode={imageTarget.mode}
                  onReplace={(next, focalY, onStage) => submitImage(entry.slot.slotId, next, focalY, onStage)}
                  onSaveFocal={(focalY) => saveImageFocus(entry.slot.slotId, focalY)}
                  onRemove={() => removeImage(entry.slot.slotId)}
                  onClose={() => setImageTarget(null)}
                />
              );
            })()
          : null}

        <p className="sr-only" aria-live="polite">
          {armedCard ? `Carta disponível escolhida: ${armedCard.cardName}. Escolha um bolso vazio.` : ""}
          {armed ? `Carta escolhida na Bandeja: ${tray.find((item) => item.slotId === armed)?.name ?? ""}. Escolha o bolso de destino.` : ""}
          {selectionActive ? ` ${selected.size} ${selected.size === 1 ? "carta selecionada" : "cartas selecionadas"}.` : ""}
        </p>
      </div>
    </BinderPortalContext.Provider>
  );
}

// ---------------------------------------------------------------------------

function Message({ tone, role, children }: { tone: "success" | "error" | "info"; role: "status" | "alert" | "alertdialog"; children: React.ReactNode }) {
  return (
    <div className={ws.message} data-tone={tone} role={role}>
      {tone === "error" ? <AlertTriangle aria-hidden /> : tone === "success" ? <CheckCircle2 aria-hidden /> : <Inbox aria-hidden />}
      {children}
    </div>
  );
}

/**
 * O objeto fichário (spike `binder-pages-nav.tsx`): couro preto com trama,
 * zíper nas quatro bordas, puxador, duas folhas com leve inclinação 3D,
 * lombada escura. A geometria vem de `--pocket` (encaixe calculado).
 */
function BinderObject({
  fit,
  columns,
  rows,
  sides,
  view,
  direction,
  animate,
  cache,
  failed,
  coverTitle,
  coverSubtitle,
  sizes,
  editable,
  selected,
  selectionActive,
  trayIds,
  armed,
  dragging,
  placing,
  placingAvailable,
  focusCollectionId,
  handlers,
  onRetry,
  onAddPages,
}: {
  fit: BinderFit;
  columns: number;
  rows: number;
  sides: ViewSide[];
  view: number;
  direction: 1 | -1;
  animate: boolean;
  cache: Map<number, BinderPage>;
  failed: Set<number>;
  coverTitle: string;
  coverSubtitle: string | null;
  sizes: string;
  editable: boolean;
  selected: Set<string>;
  selectionActive: boolean;
  trayIds: Set<string>;
  armed: string | null;
  dragging: SlotDragData | null;
  placing: boolean;
  placingAvailable: boolean;
  focusCollectionId: string | null;
  handlers: SlotHandlers;
  onRetry: (page: number) => void;
  /** Contracapa traseira (fim do fichário): atalho discreto para acrescentar páginas. */
  onAddPages: (() => void) | null;
}) {
  const p = fit.pocket;
  const pad = p * BINDER_UNITS.pad;
  const pagePad = p * BINDER_UNITS.pagePad;
  const gap = p * BINDER_UNITS.gap;
  const spine = p * BINDER_UNITS.spine;
  const two = sides.length === 2;
  return (
    <div
      className="relative overflow-hidden rounded-[22px]"
      style={{
        width: fit.width,
        height: fit.height,
        // A borda de 1px entra na conta (border-box): o miolo fica com a medida exata do encaixe.
        padding: Math.max(0, pad - 1),
        backgroundImage: blackLeatherSurface(),
        boxShadow: ["inset 0 1px 0 hsl(0 0% 100% / 0.08)", "inset 0 -2px 10px hsl(0 0% 0% / 0.5)", "0 40px 60px -20px rgba(0,0,0,0.65)"].join(", "),
        border: "1px solid hsl(0 0% 0% / 0.5)",
      }}
    >
      <div className="pointer-events-none absolute left-[8%] right-[8%] top-[6px] h-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(false) }} aria-hidden />
      <div className="pointer-events-none absolute bottom-[6px] left-[8%] right-[8%] h-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(false) }} aria-hidden />
      <div className="pointer-events-none absolute bottom-[12%] left-[5px] top-[12%] w-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(true) }} aria-hidden />
      <div className="pointer-events-none absolute bottom-[12%] right-[5px] top-[12%] w-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(true) }} aria-hidden />
      <div
        className="pointer-events-none absolute left-[3px] top-[7%] h-3.5 w-2 rounded-[2px] opacity-80"
        style={{ background: "linear-gradient(160deg, hsl(0 0% 46%), hsl(0 0% 16%))", boxShadow: "0 1px 2px rgba(0,0,0,0.5)" }}
        aria-hidden
      />

      <div className="relative flex h-full" style={{ perspective: "2000px" }}>
        {sides.map((side, index) => {
          const position: "left" | "right" | "single" = !two ? "single" : index === 0 ? "left" : "right";
          const panel = (
            <div
              key={`${view}-${index}`}
              className="relative h-full flex-1"
              style={two ? { transform: position === "left" ? "rotateY(2deg)" : "rotateY(-2deg)", transformOrigin: position === "left" ? "right center" : "left center" } : undefined}
            >
              <div
                className={cn("absolute inset-0", position === "left" ? "rounded-l-lg" : position === "right" ? "rounded-r-lg" : "rounded-lg")}
                style={{ transform: "translate(2px, 3px)", background: `hsl(${INTERIOR_HUE} 10% 4%)` }}
                aria-hidden
              />
              <div
                className={cn("relative h-full overflow-hidden", position === "left" ? "rounded-l-lg" : position === "right" ? "rounded-r-lg" : "rounded-lg")}
                style={{
                  // Respiro extra (BINDER_MARGIN) só no alto, embaixo e na lateral externa; o lado da lombada fica como estava.
                  paddingTop: pagePad + fit.marginY,
                  paddingBottom: pagePad + fit.marginY,
                  paddingLeft: pagePad + (position === "right" ? 0 : fit.marginX),
                  paddingRight: pagePad + (position === "left" ? 0 : fit.marginX),
                  ...(side === "inner" ? insideCoverSurface(position) : pageSurface(position)),
                }}
              >
                <PanelTransition direction={direction} animate={animate}>
                  {side === "inner" ? (
                    <>
                      <InsideCoverFace title={coverTitle} subtitle={coverSubtitle} />
                      {/* Vista > 1: é a contracapa traseira — o fim do fichário. */}
                      {view > 1 && onAddPages ? <AddPagesCue onClick={onAddPages} /> : null}
                    </>
                  ) : (
                    <PageGrid
                      pageNumber={side}
                      page={cache.get(side) ?? null}
                      failed={failed.has(readBatchStart(side))}
                      columns={columns}
                      rows={rows}
                      pocket={p}
                      gap={gap}
                      sizes={sizes}
                      editable={editable}
                      selected={selected}
                      selectionActive={selectionActive}
                      trayIds={trayIds}
                      armed={armed}
                      dragging={dragging}
                      placing={placing}
                      placingAvailable={placingAvailable}
                      focusCollectionId={focusCollectionId}
                      handlers={handlers}
                      onRetry={() => onRetry(side)}
                    />
                  )}
                </PanelTransition>
              </div>
            </div>
          );
          if (index === 0 && two) {
            return [
              panel,
              <div key="spine" className="pointer-events-none relative flex-shrink-0" style={{ width: spine }} aria-hidden>
                <div
                  className="absolute inset-0"
                  style={{
                    background: `linear-gradient(90deg, transparent, hsl(${INTERIOR_HUE} 22% 5%) 30%, hsl(${INTERIOR_HUE} 16% 3%) 50%, hsl(${INTERIOR_HUE} 22% 5%) 70%, transparent)`,
                  }}
                />
                <div
                  className="absolute inset-0"
                  style={{ background: "radial-gradient(ellipse 60% 100% at 50% 50%, hsl(0 0% 0% / 0.55) 0%, transparent 70%)", boxShadow: "0 0 20px 6px rgba(0,0,0,0.55)" }}
                />
                <div className="absolute inset-y-2 left-[22%] w-px" style={{ background: "hsl(0 0% 100% / 0.07)" }} />
                <div className="absolute inset-y-2 right-[22%] w-px" style={{ background: "hsl(0 0% 100% / 0.07)" }} />
              </div>,
            ];
          }
          return panel;
        })}
      </div>
    </div>
  );
}

/**
 * Fim do fichário: convite discreto para acrescentar páginas, sobre a
 * contracapa traseira (abaixo do monograma). Mesmo vocabulário dos controles
 * do spike: pílula escura, fio de luz, dourado só no hover/foco.
 */
function AddPagesCue({ onClick }: { onClick: () => void }) {
  return (
    <div className="absolute inset-x-0 top-[62%] flex justify-center">
      <button
        type="button"
        onClick={onClick}
        aria-haspopup="dialog"
        className={cn(
          "inline-flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-[11px] font-semibold text-white/70 transition-colors duration-150",
          "hover:text-[hsl(40_80%_80%)] hover:shadow-[inset_0_0_0_1px_hsl(40_70%_62%_/_0.6)] active:scale-[0.97] motion-reduce:transition-none",
          FOCUS_RING,
        )}
        style={{ background: "hsl(0 0% 0% / 0.38)", boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.14)" }}
      >
        <Plus className="h-3.5 w-3.5" aria-hidden />
        Adicionar páginas
      </button>
    </div>
  );
}

/** Troca de vista do spike: deslocamento curto + opacidade (~200 ms), nunca virada 3D. */
function PanelTransition({ direction, animate, children }: { direction: 1 | -1; animate: boolean; children: React.ReactNode }) {
  const [entered, setEntered] = useState(!animate);
  useEffect(() => {
    if (!animate) return;
    const raf = requestAnimationFrame(() => setEntered(true));
    return () => cancelAnimationFrame(raf);
  }, [animate]);
  return (
    <div
      className={cn("h-full", animate && "transition-all duration-200 ease-out")}
      style={animate ? { transform: entered ? "translateX(0)" : `translateX(${direction * 8}px)`, opacity: entered ? 1 : 0 } : undefined}
    >
      {children}
    </div>
  );
}

function PageGrid({
  pageNumber,
  page,
  failed,
  columns,
  rows,
  pocket,
  gap,
  sizes,
  editable,
  selected,
  selectionActive,
  trayIds,
  armed,
  dragging,
  placing,
  placingAvailable,
  focusCollectionId,
  handlers,
  onRetry,
}: {
  pageNumber: number;
  page: BinderPage | null;
  failed: boolean;
  columns: number;
  rows: number;
  pocket: number;
  gap: number;
  sizes: string;
  editable: boolean;
  selected: Set<string>;
  selectionActive: boolean;
  trayIds: Set<string>;
  armed: string | null;
  dragging: SlotDragData | null;
  placing: boolean;
  placingAvailable: boolean;
  focusCollectionId: string | null;
  handlers: SlotHandlers;
  onRetry: () => void;
}) {
  return (
    <div
      role="list"
      aria-label={`Página ${pageNumber}`}
      aria-busy={!page || undefined}
      className="relative grid"
      style={{ gridTemplateColumns: `repeat(${columns}, ${pocket}px)`, gridAutoRows: `${(pocket * 11) / 8}px`, gap }}
    >
      {page
        ? page.slots.map((slot, index) => (
            <div role="listitem" key={slot.slotId}>
              <BinderSlotView
                slot={slot}
                sizes={sizes}
                priority={index < columns * 2}
                editable={editable}
                selected={selected.has(slot.slotId)}
                selectionActive={selectionActive}
                inTray={trayIds.has(slot.slotId)}
                placing={placing}
                isSource={dragging?.slotId === slot.slotId || armed === slot.slotId}
                pocket={pocket}
                handlers={handlers}
                placingAvailable={placingAvailable}
                dimmed={focusCollectionId !== null && isForeignSlot(slot, focusCollectionId)}
              />
            </div>
          ))
        : Array.from({ length: columns * rows }).map((_, index) => (
            <div
              key={index}
              aria-hidden
              className={cn("rounded-[4px]", !failed && "animate-pulse")}
              style={{ background: "hsl(0 0% 0% / 0.32)", boxShadow: "inset 0 3px 7px rgba(0,0,0,0.55), inset 0 0 0 1px hsl(0 0% 100% / 0.06)" }}
            />
          ))}
      {!page && failed ? (
        <div role="alert" className="absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-md p-4 text-center text-sm text-white/75" style={{ background: "hsl(0 0% 0% / 0.55)" }}>
          <p>Não conseguimos abrir esta página.</p>
          <Button variant="outline" size="sm" className="border-white/25 bg-transparent text-white hover:bg-white/10" onClick={onRetry}>
            <RotateCcw className="h-3.5 w-3.5" aria-hidden />
            Tentar de novo
          </Button>
        </div>
      ) : null}
    </div>
  );
}

/** Carta "em mãos" durante o arrasto: mesmo tamanho do bolso, levemente levantada (spike DRAG-PREVIEW-01). */
function DragPreview({
  data,
  slotIndex,
  availableById,
  pocket,
}: {
  data: SlotDragData;
  slotIndex: Map<string, Entry>;
  availableById: Map<string, AvailableCard>;
  pocket: number;
}) {
  const card = data.kind === "available" ? availableById.get(data.slotId) : undefined;
  const slot = data.kind === "available" ? undefined : slotIndex.get(data.slotId)?.slot;
  const imagePath = card ? card.imagePath : (slot?.present?.imagePath ?? null);
  const name = card ? card.cardName : (slot?.present?.cardName ?? "");
  const src = cardFrontUrl(SUPABASE_URL, imagePath);
  return (
    <div
      className="pointer-events-none overflow-hidden rounded-[4px]"
      style={{
        width: Math.max(48, pocket),
        aspectRatio: "8 / 11",
        boxShadow: "0 20px 36px -14px rgba(0,0,0,0.8), 0 0 0 1px hsl(0 0% 100% / 0.14)",
        transform: "scale(1.02) rotate(-1deg)",
        background: "hsl(0 0% 10%)",
      }}
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- mesmo asset do bolso
        <img src={src} alt="" className="h-full w-full object-cover" draggable={false} />
      ) : (
        <span className="block p-2 text-xs font-semibold text-white/80">{name}</span>
      )}
    </div>
  );
}

/** Folha com bolsos: acabamento original (inalterado). */
function pageSurface(position: "left" | "right" | "single"): React.CSSProperties {
  return {
    background: `linear-gradient(${position === "right" ? "260deg" : "100deg"}, hsl(${INTERIOR_HUE} 14% 11%) 0%, hsl(${INTERIOR_HUE} 18% 6%) 100%)`,
    boxShadow: [
      position === "left" ? "inset -26px 0 30px -22px rgba(0,0,0,0.85)" : "inset 26px 0 30px -22px rgba(0,0,0,0.85)",
      "inset 0 2px 6px rgba(0,0,0,0.4)",
    ].join(", "),
  };
}

/**
 * Contracapa interna (P2-B-BACK-COVER-SHADOW-CORRECTION-01): couro acolchoado
 * com uma única fonte de luz, do alto à esquerda — coerente com a sombra
 * projetada que já sai para baixo/direita (camada deslocada 2 × 3 px).
 * Alto/esquerda: fio de luz sutil e tom um pouco mais claro; baixo/direita:
 * sombreamento suave. Antes, a sombra interna no alto (cue de rebaixo, luz de
 * baixo) contradizia a sombra projetada (cue de relevo, luz de cima) e, na
 * vista de uma página, a sombra da lombada caía na borda ESQUERDA. A sombra
 * da lombada continua só quando há lombada (vista dupla).
 */
function insideCoverSurface(position: "left" | "right" | "single"): React.CSSProperties {
  const gutter =
    position === "left"
      ? "inset -22px 0 26px -20px rgba(0,0,0,0.7)"
      : position === "right"
        ? "inset 22px 0 26px -20px rgba(0,0,0,0.7)"
        : null;
  return {
    background: [
      `radial-gradient(120% 90% at 22% 14%, hsl(${INTERIOR_HUE} 14% 13%) 0%, transparent 62%)`,
      `linear-gradient(135deg, hsl(${INTERIOR_HUE} 14% 11%) 0%, hsl(${INTERIOR_HUE} 18% 6%) 100%)`,
    ].join(", "),
    boxShadow: [
      // luz rasante nas bordas de cima e da esquerda
      "inset 0 1px 0 hsl(38 30% 85% / 0.07)",
      position === "right" ? null : "inset 1px 0 0 hsl(38 30% 85% / 0.05)",
      // volume: sombra suave para baixo e para a direita, sem brilho nessas bordas
      "inset -8px -10px 18px -10px rgba(0,0,0,0.55)",
      gutter,
    ]
      .filter(Boolean)
      .join(", "),
  };
}
