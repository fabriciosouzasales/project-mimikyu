"use client";

import {
  DndContext,
  DragOverlay,
  MeasuringStrategy,
  MouseSensor,
  TouchSensor,
  closestCenter,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type Announcements,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { type KeyboardEvent, type MouseEventHandler, type ReactNode, type TouchEventHandler, useEffect, useId, useMemo, useRef, useState } from "react";
import { GripVertical } from "lucide-react";
import { moveId, positionLabel, sameOrder, shiftId } from "@/lib/colecoes/library-order";
import styles from "./library-sortable.module.css";

/**
 * Lista reordenável da Biblioteca (LIBRARY-ORDER-01) — usada pelos modos
 * Cards e Lista. Cada item continua sendo o link da coleção; reordenar não
 * troca a navegação.
 *
 * Mouse: arrastar o item (a partir de 8 px — um clique simples continua
 * abrindo a coleção). Toque: pressionar e segurar ~¼ s; antes disso a tela
 * rola normalmente. Teclado: a alça (⋮⋮) de cada item — Espaço/Enter pega,
 * setas movem (na grade, ↑/↓ andam uma linha), Espaço/Enter solta, Esc
 * cancela; cada passo é anunciado.
 *
 * A prévia acompanha o gesto (os vizinhos abrem espaço); a ordem só é
 * gravada ao soltar, com UM movimento por vez (`onCommit`), e volta ao que
 * era se a gravação falhar. Só `@dnd-kit/core` (já no projeto, usado no
 * fichário) — nenhuma dependência nova.
 */
export function LibrarySortable({
  ids,
  labels,
  layout,
  className,
  ariaLabel,
  busy,
  renderItem,
  onCommit,
}: {
  ids: readonly string[];
  labels: Readonly<Record<string, string>>;
  layout: "grid" | "list";
  className: string;
  ariaLabel: string;
  /** Gravação em andamento: novos movimentos esperam. */
  busy: boolean;
  renderItem: (id: string) => ReactNode;
  /** Ordem final + coleção movida (uma por gesto). */
  onCommit: (next: string[], movedId: string) => void;
}) {
  const [preview, setPreview] = useState<string[]>(() => [...ids]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [grabbed, setGrabbed] = useState<string | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const listRef = useRef<HTMLUListElement>(null);
  const handleRefs = useRef(new Map<string, HTMLButtonElement>());
  const justDragged = useRef(false);
  const instructionsId = useId();

  // A ordem vinda de fora (gravada, revertida ou outra página) manda.
  useEffect(() => {
    setPreview((current) => (sameOrder(current, ids) ? current : [...ids]));
  }, [ids]);

  // Teclado: depois de mover, o foco continua na alça do mesmo item.
  useEffect(() => {
    if (grabbed) handleRefs.current.get(grabbed)?.focus();
  }, [preview, grabbed]);

  const sensors = useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 250, tolerance: 8 } }),
  );

  const name = (id: string | number) => labels[String(id)] ?? "coleção";

  const announcements: Announcements = useMemo(
    () => ({
      onDragStart: ({ active }) => `${name(active.id)} selecionada para mover.`,
      onDragOver: ({ active }) => `${name(active.id)} na posição ${positionLabel(preview, String(active.id))}.`,
      onDragEnd: ({ active }) => `${name(active.id)} solta na posição ${positionLabel(preview, String(active.id))}.`,
      onDragCancel: ({ active }) => `Movimento de ${name(active.id)} cancelado.`,
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- rótulos vêm do mesmo render
    [preview, labels],
  );

  const finish = (id: string) => {
    if (!sameOrder(preview, ids)) onCommit([...preview], id);
  };

  const onDragStart = ({ active }: DragStartEvent) => {
    setGrabbed(null);
    setActiveId(String(active.id));
  };

  const onDragOver = ({ active, over }: DragOverEvent) => {
    if (!over || over.id === active.id) return;
    setPreview((current) => moveId(current, String(active.id), String(over.id)));
  };

  const onDragEnd = ({ active }: DragEndEvent) => {
    setActiveId(null);
    justDragged.current = true;
    window.setTimeout(() => {
      justDragged.current = false;
    }, 0);
    finish(String(active.id));
  };

  const onDragCancel = () => {
    setActiveId(null);
    setPreview([...ids]);
  };

  /** Quantos itens por linha (grade) — ↑/↓ andam uma linha inteira. */
  const columns = () => {
    if (layout === "list") return 1;
    const items = Array.from(listRef.current?.children ?? []) as HTMLElement[];
    const top = items[0]?.offsetTop;
    const count = items.filter((item) => item.offsetTop === top).length;
    return Math.max(1, count);
  };

  const onHandleKeyDown = (id: string) => (event: KeyboardEvent<HTMLButtonElement>) => {
    if (busy) return;
    if (event.key === " " || event.key === "Enter") {
      event.preventDefault();
      if (grabbed === id) {
        setGrabbed(null);
        setAnnouncement(`${name(id)} solta na posição ${positionLabel(preview, id)}.`);
        finish(id);
      } else {
        setGrabbed(id);
        setAnnouncement(
          `${name(id)} selecionada, posição ${positionLabel(preview, id)}. Use as setas para mover, Espaço para soltar, Esc para cancelar.`,
        );
      }
      return;
    }
    if (grabbed !== id) return;
    if (event.key === "Escape") {
      event.preventDefault();
      setGrabbed(null);
      setPreview([...ids]);
      setAnnouncement(`Movimento de ${name(id)} cancelado.`);
      return;
    }
    const step = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: columns(), ArrowUp: -columns() }[event.key];
    if (step === undefined) return;
    event.preventDefault();
    const next = shiftId(preview, id, step);
    setPreview(next);
    setAnnouncement(`${name(id)} na posição ${positionLabel(next, id)}.`);
  };

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      measuring={{ droppable: { strategy: MeasuringStrategy.Always } }}
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDragEnd={onDragEnd}
      onDragCancel={onDragCancel}
      accessibility={{
        announcements,
        screenReaderInstructions: {
          draggable:
            "Para reordenar com o teclado, use a alça de cada coleção: Espaço pega, as setas movem, Espaço solta e Esc cancela.",
        },
      }}
    >
      <p id={instructionsId} className="sr-only">
        Para reordenar, arraste uma coleção ou use a alça dela: Espaço pega, setas movem, Espaço solta, Esc cancela.
      </p>
      <ul ref={listRef} className={className} aria-label={ariaLabel} data-reordering={activeId || grabbed ? "" : undefined}>
        {preview.map((id) => (
          <SortableItem
            key={id}
            id={id}
            layout={layout}
            label={name(id)}
            dragging={activeId === id}
            grabbed={grabbed === id}
            disabled={busy}
            describedBy={instructionsId}
            suppressClick={justDragged}
            handleRef={(node) => {
              if (node) handleRefs.current.set(id, node);
              else handleRefs.current.delete(id);
            }}
            onHandleKeyDown={onHandleKeyDown(id)}
          >
            {renderItem(id)}
          </SortableItem>
        ))}
      </ul>
      <DragOverlay dropAnimation={null}>
        {activeId ? <div className={styles.overlay} data-layout={layout}>{renderItem(activeId)}</div> : null}
      </DragOverlay>
      <span className="sr-only" role="status" aria-live="assertive">
        {announcement}
      </span>
    </DndContext>
  );
}

function SortableItem({
  id,
  layout,
  label,
  dragging,
  grabbed,
  disabled,
  describedBy,
  suppressClick,
  handleRef,
  onHandleKeyDown,
  children,
}: {
  id: string;
  layout: "grid" | "list";
  label: string;
  dragging: boolean;
  grabbed: boolean;
  disabled: boolean;
  describedBy: string;
  suppressClick: { current: boolean };
  handleRef: (node: HTMLButtonElement | null) => void;
  onHandleKeyDown: (event: KeyboardEvent<HTMLButtonElement>) => void;
  children: ReactNode;
}) {
  const drag = useDraggable({ id, disabled });
  const drop = useDroppable({ id });
  return (
    <li
      ref={(node) => {
        drag.setNodeRef(node);
        drop.setNodeRef(node);
      }}
      className={styles.item}
      data-layout={layout}
      data-dragging={dragging || undefined}
      data-grabbed={grabbed || undefined}
      onMouseDown={drag.listeners?.onMouseDown as MouseEventHandler<HTMLLIElement> | undefined}
      onTouchStart={drag.listeners?.onTouchStart as TouchEventHandler<HTMLLIElement> | undefined}
      // Link e imagens não viram "arrasto nativo" do navegador.
      onDragStartCapture={(event) => event.preventDefault()}
      // Soltar depois de arrastar não abre a coleção.
      onClickCapture={(event) => {
        if (suppressClick.current) {
          event.preventDefault();
          event.stopPropagation();
        }
      }}
    >
      {children}
      <button
        ref={handleRef}
        type="button"
        className={styles.handle}
        aria-label={`Mover ${label}`}
        aria-describedby={describedBy}
        aria-pressed={grabbed}
        disabled={disabled}
        onKeyDown={onHandleKeyDown}
        // A alça também arrasta com o mouse/toque (herda os listeners do item).
      >
        <GripVertical className="h-4 w-4" aria-hidden="true" />
      </button>
    </li>
  );
}
