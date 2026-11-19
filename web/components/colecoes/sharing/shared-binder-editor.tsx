"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { type DragEndEvent, type DragStartEvent, PointerSensor, TouchSensor, useSensor, useSensors } from "@dnd-kit/core";
import { AlertTriangle, CheckCircle2, Inbox, RotateCcw, X } from "lucide-react";
import {
  editorClearReservation,
  editorMoveCard,
  editorPlaceCard,
  editorRemoveCard,
  editorSetLock,
  editorSetReservation,
  readEditorPlaceableCards,
} from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import type { AvailableState } from "@/components/colecoes/fichario/binder-available";
import type { SlotDragData, SlotHandlers } from "@/components/colecoes/fichario/binder-slot";
import type { TrayItem } from "@/components/colecoes/fichario/binder-tray";
import ws from "@/components/colecoes/fichario/workspace.module.css";
import { Button } from "@/components/ui/button";
import { cardFrontUrl } from "@/lib/colecoes/acervo";
import { type BinderPage, type BinderSlot, isOccupied } from "@/lib/colecoes/binder";
import type { ReserveCandidate, ReserveScope } from "@/lib/colecoes/binder-reserve";
import type { AvailableCard } from "@/lib/colecoes/binder-share";
import {
  type EditorOperation,
  type EditorOutcome,
  type PocketPosition,
  type SlotPatch,
  type UndoRemoval,
  applyPatch,
  editorCanPick,
  editorCanTarget,
  editorFailureMessage,
  findUndoCandidate,
  patchMove,
  patchPlace,
  patchRemove,
  patchRelease,
  patchReserve,
  applyLockLessons,
  knownLock,
  lockLessons,
  overlayLocks,
  type LockLesson,
  placeableEmptyState,
  settleEditorOutcome,
  sharedSlotPosition,
} from "@/lib/colecoes/editor-binder";
import { structuralBlocker } from "@/lib/colecoes/editor-binder-pages";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const IDLE: AvailableState = { status: "idle", items: [], total: 0, loadingMore: false };
const key = (p: PocketPosition) => `${p.page}:${p.row}:${p.column}`;

type Toast = { tone: "success" | "error" | "info"; text: string; undo?: UndoRemoval };

/**
 * V1-13 · E2-1 — curadoria do EDITOR no fichário compartilhado: colocar,
 * mover/trocar e retirar, com a Bandeja, o painel "Cartas disponíveis", a
 * confirmação de retirada e as mensagens do fichário do titular.
 *
 * A tela só OFERECE; quem decide é o servidor a cada chamada (5374 sob a
 * barreira 5389). Um bolso que parece vazio pode estar ocupado por conteúdo de
 * terceiros que o participante não vê (C-237): a recusa é neutra, a mudança
 * otimista é revertida e o lote é relido. Perda de papel, saída, remoção,
 * coleção arquivada ou barreira fechada desligam a edição nesta tela.
 */
export function useSharedBinderEditor({
  enabled,
  collectionId,
  cache,
  setCache,
  refresh,
  onFilledDelta,
  reserveScope = null,
}: {
  /** Configuração ligada (D1) + papel EDITOR + coleção ativa, decidido no servidor da página. */
  enabled: boolean;
  collectionId: string;
  cache: Map<number, BinderPage>;
  setCache: (update: (prev: Map<number, BinderPage>) => Map<number, BinderPage>) => void;
  /** Relê os lotes das páginas (estado autorizado). */
  refresh: (pages: number[]) => void;
  onFilledDelta: (delta: number) => void;
  /** E2-2: escopo da reserva pelo tipo da coleção; `null` (Pokédex) = sem "Reservar para uma carta". */
  reserveScope?: ReserveScope | null;
}) {
  const router = useRouter();
  const [active, setActive] = useState(enabled);
  const [busy, setBusy] = useState(false);
  const [toast, setToastState] = useState<Toast | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [confirm, setConfirm] = useState<BinderSlot | null>(null);
  const [tray, setTray] = useState<TrayItem[]>([]);
  const [trayOpen, setTrayOpen] = useState(false);
  const [armed, setArmed] = useState<string | null>(null);
  const [armedCard, setArmedCard] = useState<AvailableCard | null>(null);
  const [target, setTarget] = useState<BinderSlot | null>(null);
  const [available, setAvailable] = useState<AvailableState>(IDLE);
  const [availableOpen, setAvailableOpen] = useState(false);
  const [dragging, setDragging] = useState<SlotDragData | null>(null);
  /** Curadoria comprovada nesta tela: a lista trouxe cartas ou o servidor aceitou uma escrita (ver `placeableEmptyState`). */
  const [confirmed, setConfirmed] = useState(false);
  /** Exemplares colocados nesta sessão, por posição — base do "Desfazer" quando a lista não basta. */
  const placedHere = useRef(new Map<string, string>());
  /**
   * E2-2 (P1/P2): fixação APRENDIDA nesta sessão por posição. Ausente = UNKNOWN
   * (nunca "solto"). Sobrevive às releituras, que não informam fixação; muda só
   * com resposta conclusiva do servidor.
   */
  const [locks, setLocks] = useState<Map<string, "LOCKED" | "UNLOCKED">>(() => new Map());
  const [reserveTarget, setReserveTarget] = useState<{ slot: BinderSlot; page: number; mode: "reserve" | "change" } | null>(null);
  const learn = useCallback((lessons: LockLesson[]) => {
    if (lessons.length > 0) setLocks((prev) => applyLockLessons(prev, lessons));
  }, []);

  const setToast = useCallback((next: Toast | null) => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToastState(next);
    if (next) toastTimer.current = setTimeout(() => setToastState(null), next.tone === "error" ? 7000 : next.undo ? 9000 : 3500);
  }, []);

  const slotById = useCallback(
    (slotId: string): { slot: BinderSlot; page: number } | null => {
      for (const [number, page] of cache) {
        for (const slot of page.slots) {
          if (slot.slotId !== slotId) continue;
          // O que a tela sabe da fixação (P1): `locked` só quando aprendido.
          return { slot: { ...slot, locked: knownLock(locks, sharedSlotPosition(slot.slotId)) === "LOCKED" }, page: number };
        }
      }
      return null;
    },
    [cache, locks],
  );

  /** Aplica o patch ao estado mais recente e devolve o conteúdo anterior dos bolsos tocados (lido agora, para reverter). */
  const patch = useCallback(
    (p: SlotPatch): SlotPatch => {
      const { previous } = applyPatch(cache, p);
      setCache((prev) => applyPatch(prev, p).cache);
      return previous;
    },
    [cache, setCache],
  );

  const loadAvailable = useCallback(
    async (offset: number): Promise<AvailableCard[] | null> => {
      setAvailable((prev) => (offset === 0 ? { ...prev, status: prev.status === "ready" ? "ready" : "loading" } : { ...prev, loadingMore: true }));
      const result = await readEditorPlaceableCards({ collectionId, offset }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      if (!result.ok) {
        setAvailable((prev) => ({ ...prev, status: offset === 0 ? "error" : prev.status, loadingMore: false }));
        return null;
      }
      if (result.items.length > 0) setConfirmed(true);
      let items: AvailableCard[] = result.items;
      setAvailable((prev) => {
        items = offset === 0 ? result.items : [...prev.items, ...result.items.filter((c) => !prev.items.some((p) => p.physicalCardId === c.physicalCardId))];
        return { status: "ready", items, total: result.total, loadingMore: false };
      });
      return items;
    },
    [collectionId],
  );

  const disable = useCallback(() => {
    setActive(false);
    setTray([]);
    setTrayOpen(false);
    setArmed(null);
    setArmedCard(null);
    setTarget(null);
    setConfirm(null);
    setAvailableOpen(false);
    setReserveTarget(null);
  }, []);

  /** Fecha a escrita: reverte o otimista nas recusas, mostra a mensagem e desliga/relê quando o acesso mudou. */
  const settle = useCallback(
    (op: EditorOperation, outcome: EditorOutcome, previous: SlotPatch, extra: Partial<Toast> = {}) => {
      const s = settleEditorOutcome(op, outcome, previous);
      if (s.revert) {
        const revert = s.revert;
        setCache((prev) => applyPatch(prev, revert).cache);
      }
      if (s.filledDelta !== 0) onFilledDelta(s.filledDelta);
      setToast({ ...s.toast, ...(outcome.ok ? extra : {}) });
      if (s.disable) disable();
      if (s.recheck) router.refresh();
      if (outcome.ok) setConfirmed(true);
      return outcome.ok;
    },
    [disable, onFilledDelta, router, setCache, setToast],
  );

  // ---- colocar (C-235) ----
  const place = useCallback(
    async (slot: BinderSlot, card: AvailableCard, page: number) => {
      const position = sharedSlotPosition(slot.slotId);
      if (!active || busy || !position) return;
      if (slot.locked) {
        setToast({ tone: "error", text: editorFailureMessage("locked") });
        return;
      }
      if (!editorCanTarget(slot) || isOccupied(slot)) {
        setToast({ tone: "info", text: "Escolha um bolso vazio para colocar a carta." });
        return;
      }
      setBusy(true);
      setArmedCard(null);
      setTarget(null);
      const previous = patch(patchPlace(slot, card));
      setAvailable((prev) => ({ ...prev, items: prev.items.filter((c) => c.physicalCardId !== card.physicalCardId), total: Math.max(0, prev.total - 1) }));
      const outcome: EditorOutcome = await editorPlaceCard({ collectionId, position, physicalCardId: card.physicalCardId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      learn(lockLessons({ kind: "place", position }, outcome));
      if (settle({ kind: "place", cardName: card.cardName, page: position.page }, outcome, previous)) placedHere.current.set(key(position), card.physicalCardId);
      void loadAvailable(0);
      refresh([page]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, loadAvailable, patch, refresh, setToast, settle],
  );

  // ---- mover / trocar (C-237) ----
  const move = useCallback(
    async (fromId: string, to: BinderSlot, toPage: number) => {
      const source = slotById(fromId);
      const from = source ? sharedSlotPosition(source.slot.slotId) : null;
      const dest = sharedSlotPosition(to.slotId);
      if (!active || busy || !source || !from || !dest || fromId === to.slotId) return;
      if (source.slot.locked || to.locked) {
        setToast({ tone: "error", text: editorFailureMessage("locked") });
        return;
      }
      if (!editorCanPick(source.slot)) {
        setToast({ tone: "error", text: editorFailureMessage("source_empty") });
        refresh([source.page]);
        return;
      }
      if (!editorCanTarget(to)) {
        setToast({ tone: "error", text: editorFailureMessage("not_editable") });
        return;
      }
      setBusy(true);
      setArmed(null);
      const previous = patch(patchMove(source.slot, to));
      setTray((prev) => prev.filter((item) => item.slotId !== fromId));
      const outcome: EditorOutcome = await editorMoveCard({ collectionId, from, to: dest }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      const op: EditorOperation = { kind: "move", cardName: source.slot.present?.cardName ?? "A carta", otherName: to.present?.cardName ?? null, page: dest.page };
      learn(lockLessons({ kind: "move", from, to: dest }, outcome));
      if (settle(op, outcome, previous)) {
        const a = placedHere.current.get(key(from));
        const b = placedHere.current.get(key(dest));
        placedHere.current.delete(key(from));
        placedHere.current.delete(key(dest));
        if (a) placedHere.current.set(key(dest), a);
        if (b && outcome.ok && outcome.operation === "SWAP") placedHere.current.set(key(from), b);
      }
      refresh(source.page === toPage ? [toPage] : [source.page, toPage]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, patch, refresh, setToast, settle, slotById],
  );

  // ---- retirar (C-236) + desfazer (D2) ----
  const runRemove = useCallback(
    async (slot: BinderSlot) => {
      setConfirm(null);
      const found = slotById(slot.slotId);
      const position = sharedSlotPosition(slot.slotId);
      if (!active || busy || !found || !position || !editorCanPick(found.slot)) return;
      setBusy(true);
      const removedSlot = found.slot;
      const previous = patch(patchRemove(removedSlot));
      const outcome: EditorOutcome = await editorRemoveCard({ collectionId, position })
        .then((r) => (r.ok ? ({ ok: true, operation: "REMOVED" } as const) : r))
        .catch(() => ({ ok: false, reason: "unknown" }) as const);
      let undo: UndoRemoval | null = null;
      if (outcome.ok) {
        // O exemplar retirado volta à lista elegível (continua alocado e no fichário): é ele que o Desfazer recoloca.
        const items = await loadAvailable(0);
        const known = placedHere.current.get(key(position)) ?? null;
        placedHere.current.delete(key(position));
        const candidate = known && items?.some((c) => c.physicalCardId === known) ? known : (findUndoCandidate(items ?? [], removedSlot)?.physicalCardId ?? null);
        if (candidate) undo = { position, physicalCardId: candidate, cardName: removedSlot.present?.cardName ?? "A carta" };
      }
      learn(lockLessons({ kind: "remove", position }, outcome));
      settle({ kind: "remove" }, outcome, previous, undo ? { undo } : {});
      refresh([found.page]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, loadAvailable, patch, refresh, settle, slotById],
  );

  /** Desfazer = NOVA colocação, validada por inteiro no servidor e com novo evento no histórico (D2). */
  const runUndo = useCallback(
    async (undo: UndoRemoval) => {
      if (!active || busy) return;
      setBusy(true);
      setToast(null);
      const outcome: EditorOutcome = await editorPlaceCard({ collectionId, position: undo.position, physicalCardId: undo.physicalCardId }).catch(
        () => ({ ok: false, reason: "unknown" }) as const,
      );
      // Falha no desfazer: a carta continua na coleção, fora do bolso; nada mais é tentado.
      learn(lockLessons({ kind: "undo", position: undo.position }, outcome));
      if (settle({ kind: "undo", cardName: undo.cardName }, outcome, new Map())) placedHere.current.set(key(undo.position), undo.physicalCardId);
      void loadAvailable(0);
      refresh([undo.position.page]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, loadAvailable, refresh, setToast, settle],
  );

  // ---- E2-2: reservar / trocar (5375; sempre registrada para esta coleção) ----
  const runReserve = useCallback(
    async (slotId: string, candidate: ReserveCandidate) => {
      const found = slotById(slotId);
      const position = found ? sharedSlotPosition(found.slot.slotId) : null;
      setReserveTarget(null);
      if (!active || busy || !found || !position) return;
      setBusy(true);
      const previous = patch(patchReserve(found.slot, candidate, collectionId));
      const outcome: EditorOutcome = await editorSetReservation({ collectionId, position, cardId: candidate.cardId, variantTypeId: candidate.variantTypeId }).catch(
        () => ({ ok: false, reason: "unknown" }) as const,
      );
      learn(lockLessons({ kind: "reserve", position }, outcome));
      settle({ kind: "reserve", cardName: candidate.cardName }, outcome, previous);
      refresh([found.page]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, patch, refresh, settle, slotById],
  );

  // ---- E2-2: liberar reserva (P4: só com reserva visível de X; o servidor decide, inclusive em bolso fixado) ----
  const runRelease = useCallback(
    async (slotId: string) => {
      const found = slotById(slotId);
      const position = found ? sharedSlotPosition(found.slot.slotId) : null;
      setReserveTarget(null);
      if (!active || busy || !found || !position || found.slot.state !== "RESERVED_EMPTY") return;
      setBusy(true);
      const previous = patch(patchRelease(found.slot));
      const outcome: EditorOutcome = await editorClearReservation({ collectionId, position }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      learn(lockLessons({ kind: "release", position }, outcome));
      settle({ kind: "release" }, outcome, previous);
      refresh([found.page]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, patch, refresh, settle, slotById],
  );

  // ---- E2-2: fixar / soltar (otimista só no estado aprendido, que reverte com segurança) ----
  const runLock = useCallback(
    async (slotId: string, lockedWanted: boolean) => {
      const found = slotById(slotId);
      const position = found ? sharedSlotPosition(found.slot.slotId) : null;
      if (!active || busy || !found || !position) return;
      if (lockedWanted && trayIdsRef.current.has(slotId)) {
        setToast({ tone: "info", text: "Devolva a carta da Bandeja antes de fixar o bolso." });
        return;
      }
      setBusy(true);
      const k = key(position);
      const before = locks.get(k) ?? null;
      setLocks((prev) => new Map(prev).set(k, lockedWanted ? "LOCKED" : "UNLOCKED"));
      const outcome: EditorOutcome = await editorSetLock({ collectionId, position, locked: lockedWanted }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      if (outcome.ok) {
        learn(lockLessons({ kind: "lock", locked: lockedWanted, position }, outcome));
      } else {
        // Recusa: volta ao que se sabia antes (inclusive UNKNOWN); nada é deduzido de uma recusa neutra.
        setLocks((prev) => {
          const next = new Map(prev);
          if (before) next.set(k, before);
          else next.delete(k);
          return next;
        });
      }
      settle({ kind: "lock", locked: lockedWanted }, outcome, new Map());
      refresh([found.page]);
      setBusy(false);
    },
    [active, busy, collectionId, learn, locks, refresh, setToast, settle, slotById],
  );

  const openAvailable = useCallback(
    (forSlot: BinderSlot | null) => {
      setTarget(forSlot);
      setAvailableOpen(true);
      if (available.status === "idle" || available.status === "error") void loadAvailable(0);
    },
    [available.status, loadAvailable],
  );

  // ---- ganchos dos bolsos (só as ações do E2-1) ----
  const handlers = useCallback(
    (base: SlotHandlers): SlotHandlers => {
      if (!active) return base;
      return {
        ...base,
        editorCore: true,
        onActivate: (slot, additive) => {
          const entry = slotById(slot.slotId);
          if (!entry) return;
          if (armed) {
            if (armed !== slot.slotId) void move(armed, slot, entry.page);
            else setArmed(null);
            return;
          }
          if (armedCard) {
            void place(slot, armedCard, entry.page);
            return;
          }
          if (!isOccupied(slot) && editorCanTarget(slot)) {
            openAvailable(slot);
            setToast({ tone: "info", text: `Escolha a carta para este bolso da página ${entry.page}.` });
            return;
          }
          base.onActivate(slot, additive);
        },
        onAddCard: (slot) => {
          const entry = slotById(slot.slotId);
          openAvailable(slot);
          if (entry) setToast({ tone: "info", text: `Escolha a carta para este bolso da página ${entry.page}.` });
        },
        onToTray: (slot) => {
          const entry = slotById(slot.slotId);
          if (!entry || !editorCanPick(slot)) return;
          setTray((prev) =>
            prev.some((item) => item.slotId === slot.slotId)
              ? prev
              : [...prev, { slotId: slot.slotId, page: entry.page, name: slot.present?.cardName ?? "Carta", imagePath: slot.present?.imagePath ?? null }],
          );
          setTrayOpen(true);
          setToast({ tone: "info", text: `${slot.present?.cardName ?? "A carta"} está na Bandeja. Vá até a página de destino e toque no bolso.` });
        },
        onReturnFromTray: (slot) => {
          setTray((prev) => prev.filter((item) => item.slotId !== slot.slotId));
          if (armed === slot.slotId) setArmed(null);
        },
        onRemove: (slot) => {
          const entry = slotById(slot.slotId);
          if (entry && editorCanPick(entry.slot)) setConfirm(entry.slot);
        },
        onReserveFor: reserveScope === null ? undefined : (slot) => {
          const entry = slotById(slot.slotId);
          if (!entry) return;
          setReserveTarget({ slot: entry.slot, page: entry.page, mode: entry.slot.state === "RESERVED_EMPTY" ? "change" : "reserve" });
        },
        onClearReserve: (slot) => void runRelease(slot.slotId),
        onToggleLock: (slot) => {
          const entry = slotById(slot.slotId);
          if (entry) void runLock(slot.slotId, !entry.slot.locked);
        },
      };
    },
    [active, armed, armedCard, move, openAvailable, place, reserveScope, runLock, runRelease, setToast, slotById],
  );

  // ---- arrastar (mesmos ganchos do titular) ----
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 8 } }),
  );
  const onDragStart = useCallback((event: DragStartEvent) => {
    const data = event.active.data.current as SlotDragData | undefined;
    setDragging(data ?? null);
  }, []);
  const onDragEnd = useCallback(
    (event: DragEndEvent) => {
      const data = event.active.data.current as SlotDragData | undefined;
      setDragging(null);
      const overId = typeof event.over?.id === "string" ? event.over.id : null;
      if (!data || !overId?.startsWith("pocket:")) return;
      const entry = slotById(overId.slice("pocket:".length));
      if (!entry) return;
      if (data.kind === "available") {
        const card = available.items.find((c) => c.physicalCardId === data.slotId);
        if (card) void place(entry.slot, card, entry.page);
        return;
      }
      void move(data.slotId, entry.slot, entry.page);
    },
    [available.items, move, place, slotById],
  );
  const onDragCancel = useCallback(() => setDragging(null), []);

  const trayIds = useMemo(() => new Set(tray.map((item) => item.slotId)), [tray]);
  const trayIdsRef = useRef(trayIds);
  trayIdsRef.current = trayIds;
  const availableById = useMemo(() => new Map(available.items.map((card) => [card.physicalCardId, card])), [available.items]);

  // ---- E2-3A: integração com as operações de página (estado único de "ocupado") ----
  const blocker = structuralBlocker({
    busy,
    trayCount: tray.length,
    armed: armed !== null,
    armedCard: armedCard !== null,
    dragging: dragging !== null,
    confirming: confirm !== null,
    reserving: reserveTarget !== null,
  });
  const structuralRef = useRef(false);
  /** Reserva o "ocupado" da curadoria para uma operação de página; `false` = não pode agora. */
  const beginStructural = useCallback((): boolean => {
    if (!active || blocker !== null || structuralRef.current) return false;
    structuralRef.current = true;
    setBusy(true);
    setTarget(null);
    return true;
  }, [active, blocker]);
  const endStructural = useCallback(() => {
    structuralRef.current = false;
    setBusy(false);
  }, []);
  /**
   * Números de página mudaram (remover/reordenar, ou resultado incerto): o que
   * a sessão sabia por POSIÇÃO deixa de valer. Fixação volta a UNKNOWN (P1, o
   * lado seguro) e o "Desfazer" por posição deixa de ser oferecido.
   */
  const afterRenumber = useCallback(() => {
    setLocks(new Map());
    placedHere.current.clear();
    setToastState((prev) => (prev?.undo ? null : prev));
  }, []);
  const loseAccess = useCallback(
    (recheck: boolean) => {
      disable();
      if (recheck) router.refresh();
    },
    [disable, router],
  );

  return {
    active,
    busy,
    handlers,
    sensors,
    onDragStart,
    onDragEnd,
    onDragCancel,
    dragging,
    tray,
    trayIds,
    trayOpen,
    setTrayOpen,
    armed,
    setArmed: (id: string | null) => {
      setArmedCard(null);
      setArmed(id);
    },
    returnFromTray: (id: string) => {
      setTray((prev) => prev.filter((item) => item.slotId !== id));
      if (armed === id) setArmed(null);
    },
    armedCard,
    target,
    available,
    emptyState: placeableEmptyState(confirmed),
    availableOpen,
    availableById,
    openAvailable: () => openAvailable(null),
    closeAvailable: () => {
      setAvailableOpen(false);
      setTarget(null);
      setArmedCard(null);
    },
    armCard: (card: AvailableCard) => {
      setArmed(null);
      if (target) {
        const entry = slotById(target.slotId);
        if (entry) void place(entry.slot, card, entry.page);
        return;
      }
      setArmedCard((current) => (current?.physicalCardId === card.physicalCardId ? null : card));
    },
    loadMore: () => void loadAvailable(available.items.length),
    retryAvailable: () => void loadAvailable(0),
    confirm,
    cancelConfirm: () => setConfirm(null),
    runRemove,
    toast,
    dismissToast: () => setToast(null),
    runUndo,
    slotById,
    /** Página com a fixação que a sessão aprendeu (selo e bloqueio local). */
    view: (page: BinderPage | null) => (page ? overlayLocks(page, locks) : null),
    locks,
    reserveTarget,
    closeReserve: () => setReserveTarget(null),
    confirmReserve: (candidate: ReserveCandidate) => reserveTarget && void runReserve(reserveTarget.slot.slotId, candidate),
    releaseFromPicker: () => reserveTarget && void runRelease(reserveTarget.slot.slotId),
    /** E2-3A: motivo pelo qual as páginas não podem mudar agora (`null` = livre). */
    structuralBlocker: blocker,
    beginStructural,
    endStructural,
    afterRenumber,
    loseAccess,
    notify: setToast,
  };
}

export type SharedBinderEditor = ReturnType<typeof useSharedBinderEditor>;

/** Mensagens e confirmação na base do fichário (mesmo visual do titular). */
export function SharedEditorMessages({ editor }: { editor: SharedBinderEditor }) {
  if (editor.confirm) {
    return (
      <EditorMessage tone="error" role="alertdialog">
        <p>{`Tirar ${editor.confirm.present?.cardName ?? "esta carta"} do fichário? Ela continua na coleção.`}</p>
        <span className={ws.messageActions}>
          <Button size="sm" variant="outline" className="h-8 border-white/20 bg-transparent text-white hover:bg-white/10" onClick={editor.cancelConfirm}>
            Cancelar
          </Button>
          <Button size="sm" variant="destructive" className="h-8" onClick={() => editor.confirm && void editor.runRemove(editor.confirm)} autoFocus disabled={editor.busy}>
            Tirar
          </Button>
        </span>
      </EditorMessage>
    );
  }
  const toast = editor.toast;
  if (!toast) return null;
  return (
    <EditorMessage tone={toast.tone} role={toast.tone === "error" ? "alert" : "status"}>
      <p>{toast.text}</p>
      <span className={ws.messageActions}>
        {toast.undo ? (
          <Button
            size="sm"
            variant="outline"
            className="h-8 border-white/20 bg-transparent text-white hover:bg-white/10"
            onClick={() => toast.undo && void editor.runUndo(toast.undo)}
            disabled={editor.busy}
          >
            <RotateCcw className="h-3.5 w-3.5" aria-hidden />
            Desfazer
          </Button>
        ) : null}
        <button type="button" className="rounded-full p-1 text-white/60 hover:bg-white/10 hover:text-white" onClick={editor.dismissToast} aria-label="Dispensar mensagem">
          <X className="h-3.5 w-3.5" aria-hidden />
        </button>
      </span>
    </EditorMessage>
  );
}

function EditorMessage({ tone, role, children }: { tone: "success" | "error" | "info"; role: "status" | "alert" | "alertdialog"; children: React.ReactNode }) {
  return (
    <div className={ws.message} data-tone={tone} role={role}>
      {tone === "error" ? <AlertTriangle aria-hidden /> : tone === "success" ? <CheckCircle2 aria-hidden /> : <Inbox aria-hidden />}
      {children}
    </div>
  );
}

/** Carta acompanhando o arraste (mesmo desenho do titular). */
export function EditorDragPreview({ editor, pocket }: { editor: SharedBinderEditor; pocket: number }) {
  const data = editor.dragging;
  if (!data) return null;
  const card = data.kind === "available" ? editor.availableById.get(data.slotId) : undefined;
  const slot = data.kind === "available" ? undefined : editor.slotById(data.slotId)?.slot;
  const imagePath = card ? card.imagePath : (slot?.present?.imagePath ?? null);
  const name = card ? card.cardName : (slot?.present?.cardName ?? "");
  const src = cardFrontUrl(SUPABASE_URL, imagePath);
  return (
    <div
      className="pointer-events-none overflow-hidden rounded-[4px]"
      style={{ width: Math.max(48, pocket), aspectRatio: "8 / 11", boxShadow: "0 20px 36px -14px rgba(0,0,0,0.8), 0 0 0 1px hsl(0 0% 100% / 0.14)", transform: "scale(1.02) rotate(-1deg)", background: "hsl(0 0% 10%)" }}
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
