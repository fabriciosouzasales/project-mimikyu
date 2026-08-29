"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useCallback, useMemo, useRef, useState } from "react";
import { MOCK_STORAGE_CONTAINERS } from "@/app/experimental/collection-space/mock-data";
import { runWithViewTransition } from "@/lib/view-transitions";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { cn } from "@/lib/utils";
import { BinderInterior } from "./binder-interior";
import { CONTAINER_DIMENSIONS, StorageContainerVisual } from "./storage-container-visual";

/**
 * "Visual Collection Space" — spike client-facing de Collections (pedido
 * verbatim de Fabrício, 2026-08-28; refinado na Rodada UX-01.1, mesma data,
 * foco em materialidade/escala/composição — UX-01 foi aprovado
 * estruturalmente mas reprovado visualmente: "ainda parecem cards/
 * retângulos em perspectiva").
 *
 * Mudanças da Rodada UX-01.1 (só visual/composição — nenhuma interação,
 * rota, dado mockado ou dependência mudou):
 * - Objetos ancorados a uma linha de "chão" compartilhada (`FLOOR_TOP`),
 *   não mais centralizados verticalmente — como objetos físicos apoiados
 *   numa prateleira, cada um com sua sombra própria projetada na mesma linha.
 * - Escala do item central ampliada (>100%) e queda de escala/opacidade dos
 *   laterais mais acentuada — domínio claro do objeto central.
 * - Espaçamento horizontal não-linear (`GAP_MULTIPLIER`) — os laterais mais
 *   distantes abrem mais espaço entre si, evitando a leitura de "baralho
 *   empilhado atrás".
 * - Proporção por tipo de container (`CONTAINER_DIMENSIONS`, ver
 *   `storage-container-visual.tsx`) — cada objeto tem sua própria silhueta,
 *   não um retângulo genérico com ícone trocado.
 * - Nome/subtítulo/contagem saíram de dentro do objeto e viraram uma
 *   legenda abaixo do palco (só do item em foco) — o objeto carrega só
 *   material, a legenda carrega texto.
 * - Glow ambiente reforçado com o matiz dourado da marca (mesmo de
 *   `--nav-gold`/`--primary`), não mais um tom neutro genérico.
 *
 * Preservado integralmente: rota experimental, dados mockados, navegação
 * por teclado/mouse/trackpad/wheel/drag, foco acessível, `prefers-reduced-
 * motion`, ausência de dependência nova, ausência de persistência.
 */

const EASING = "cubic-bezier(0.22, 1, 0.36, 1)";
const DRAG_THRESHOLD_PX = 56;
const WHEEL_THRESHOLD = 40;
const WHEEL_COOLDOWN_MS = 350;
const BINDER_TRANSITION_NAME = (id: string) => `experimental-binder-${id}`;

/** Linha de "chão" compartilhada — objetos e suas sombras ancoram aqui, não no centro vertical do palco. */
const FLOOR_TOP = "64%";
const GAP_BASE = "min(20vw, 190px)";
/** Escala/opacidade por distância ao foco — domínio do central, queda acentuada nos laterais (não gradual como um baralho). */
const SCALE_BY_ABS_DIFF = [1.1, 0.6, 0.36];
const OPACITY_BY_ABS_DIFF = [1, 0.88, 0.58];

export function CollectionSpaceView() {
  const containers = MOCK_STORAGE_CONTAINERS;
  const [focusedIndex, setFocusedIndex] = useState(0);
  const [openBinderId, setOpenBinderId] = useState<string | null>(null);
  const [dragDeltaPx, setDragDeltaPx] = useState(0);
  const prefersReducedMotion = usePrefersReducedMotion();

  const buttonRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const dragState = useRef<{ pointerId: number; startX: number } | null>(null);
  const wheelCooldownRef = useRef(false);
  const rafRef = useRef<number | null>(null);
  const pendingDragDeltaRef = useRef(0);

  const focusedContainer = containers[focusedIndex];
  const openBinderContainer = openBinderId ? containers.find((c) => c.id === openBinderId) ?? null : null;

  const moveTo = useCallback(
    (nextIndex: number) => {
      const clamped = Math.max(0, Math.min(containers.length - 1, nextIndex));
      setFocusedIndex(clamped);
      buttonRefs.current[clamped]?.focus();
    },
    [containers.length],
  );

  const handleOpen = useCallback((container: (typeof containers)[number]) => {
    if (!container.interactive) return;
    runWithViewTransition(() => setOpenBinderId(container.id));
  }, []);

  const handleClose = useCallback(() => {
    runWithViewTransition(() => setOpenBinderId(null));
  }, []);

  const handleContainerActivate = useCallback(
    (index: number) => {
      if (index !== focusedIndex) {
        moveTo(index);
        return;
      }
      const container = containers[index];
      if (container) handleOpen(container);
    },
    [focusedIndex, moveTo, handleOpen, containers],
  );

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (openBinderId) {
        if (event.key === "Escape") {
          event.preventDefault();
          handleClose();
        }
        return;
      }
      if (event.key === "ArrowRight") {
        event.preventDefault();
        moveTo(focusedIndex + 1);
      } else if (event.key === "ArrowLeft") {
        event.preventDefault();
        moveTo(focusedIndex - 1);
      } else if (event.key === "Home") {
        event.preventDefault();
        moveTo(0);
      } else if (event.key === "End") {
        event.preventDefault();
        moveTo(containers.length - 1);
      }
    },
    [openBinderId, focusedIndex, moveTo, containers.length, handleClose],
  );

  const handleWheel = useCallback(
    (event: React.WheelEvent<HTMLDivElement>) => {
      if (openBinderId) return;
      const horizontalIntent = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
      if (Math.abs(horizontalIntent) < WHEEL_THRESHOLD || wheelCooldownRef.current) return;
      event.preventDefault();
      wheelCooldownRef.current = true;
      moveTo(focusedIndex + (horizontalIntent > 0 ? 1 : -1));
      window.setTimeout(() => {
        wheelCooldownRef.current = false;
      }, WHEEL_COOLDOWN_MS);
    },
    [openBinderId, focusedIndex, moveTo],
  );

  const flushDrag = useCallback(() => {
    setDragDeltaPx(pendingDragDeltaRef.current);
    rafRef.current = null;
  }, []);

  const handlePointerDown = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (openBinderId) return;
      dragState.current = { pointerId: event.pointerId, startX: event.clientX };
      event.currentTarget.setPointerCapture(event.pointerId);
    },
    [openBinderId],
  );

  const handlePointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (!dragState.current || dragState.current.pointerId !== event.pointerId) return;
      pendingDragDeltaRef.current = event.clientX - dragState.current.startX;
      if (rafRef.current === null) {
        rafRef.current = window.requestAnimationFrame(flushDrag);
      }
    },
    [flushDrag],
  );

  const endDrag = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (!dragState.current || dragState.current.pointerId !== event.pointerId) return;
      const delta = pendingDragDeltaRef.current;
      dragState.current = null;
      pendingDragDeltaRef.current = 0;
      if (rafRef.current !== null) {
        window.cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      setDragDeltaPx(0);
      if (Math.abs(delta) > DRAG_THRESHOLD_PX) {
        moveTo(focusedIndex + (delta < 0 ? 1 : -1));
      }
    },
    [focusedIndex, moveTo],
  );

  const transitionStyle = prefersReducedMotion ? "none" : `transform 480ms ${EASING}, opacity 320ms ${EASING}`;

  const liveAnnouncement = useMemo(
    () => (focusedContainer ? `${focusedContainer.name} — ${focusedContainer.itemCount} itens` : ""),
    [focusedContainer],
  );

  return (
    <div className="relative flex h-dvh w-full flex-col overflow-hidden bg-[hsl(30_20%_7%)]">
      {/* Glow ambiente — matiz dourado da marca (mesmo de --nav-gold/--primary), não um tom neutro genérico. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 65% 50% at 50% 40%, hsl(37 55% 28% / 0.32), transparent 68%), radial-gradient(ellipse 60% 42% at 50% 72%, hsl(37 60% 22% / 0.4), transparent 70%)",
        }}
      />
      {/* Plano de chão — os objetos "pousam" aqui (FLOOR_TOP), não flutuam no vazio. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0"
        style={{
          top: FLOOR_TOP,
          background: "linear-gradient(to bottom, hsl(37 26% 12% / 0.55), hsl(30 20% 7% / 0.92))",
        }}
      />
      <div aria-hidden className="pointer-events-none absolute inset-x-0" style={{ top: FLOOR_TOP, height: 1, background: "hsl(0 0% 100% / 0.05)" }} />

      <header className="relative z-10 px-6 pt-6 sm:px-10">
        <p className="text-xs font-medium uppercase tracking-[0.18em] text-white/40">Spike experimental · não é a IA oficial</p>
        <h1 className="mt-1 text-lg font-semibold text-white/95">Collection Space</h1>
      </header>

      <div
        role="listbox"
        aria-label="Containers da coleção"
        aria-activedescendant={focusedContainer ? `collection-space-item-${focusedContainer.id}` : undefined}
        tabIndex={-1}
        onKeyDown={handleKeyDown}
        onWheel={handleWheel}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        className="relative z-10 flex flex-1 touch-pan-y items-center justify-center"
        style={{ perspective: "1500px" }}
      >
        {containers.map((container, index) => {
          const diff = index - focusedIndex;
          const absDiff = Math.abs(diff);
          if (absDiff > 2) return null;

          const dragOffset = dragState.current ? dragDeltaPx : 0;
          const gapMultiplier = 1 + absDiff * 0.25;
          const translateXExpr = `calc(${diff} * ${gapMultiplier} * ${GAP_BASE} + ${dragOffset}px)`;
          const scale = SCALE_BY_ABS_DIFF[absDiff] ?? 0.3;
          const opacity = OPACITY_BY_ABS_DIFF[absDiff] ?? 0;

          return (
            <div
              key={`${container.id}-shadow`}
              aria-hidden
              className="pointer-events-none absolute rounded-full"
              style={{
                left: "50%",
                top: FLOOR_TOP,
                width: "12rem",
                height: 16,
                transform: `translate(-50%, -30%) translateX(${translateXExpr}) scale(${scale})`,
                background: "radial-gradient(ellipse, rgba(0,0,0,0.55) 0%, transparent 72%)",
                opacity: opacity * 0.85,
                transition: dragState.current ? "none" : transitionStyle,
                zIndex: 1,
              }}
            />
          );
        })}

        {containers.map((container, index) => {
          const diff = index - focusedIndex;
          const absDiff = Math.abs(diff);
          if (absDiff > 2) return null;

          const dims = CONTAINER_DIMENSIONS[container.type];
          const dragOffset = dragState.current ? dragDeltaPx : 0;
          const gapMultiplier = 1 + absDiff * 0.25;
          const isBeingOpened = openBinderId === container.id;

          const scale = SCALE_BY_ABS_DIFF[absDiff] ?? 0.3;
          const opacity = OPACITY_BY_ABS_DIFF[absDiff] ?? 0;
          const rotateY = prefersReducedMotion ? 0 : diff * -12;

          return (
            <button
              key={container.id}
              id={`collection-space-item-${container.id}`}
              ref={(el) => {
                buttonRefs.current[index] = el;
              }}
              type="button"
              role="option"
              aria-selected={index === focusedIndex}
              tabIndex={index === focusedIndex ? 0 : -1}
              onClick={() => handleContainerActivate(index)}
              className={cn("absolute cursor-pointer text-left focus-visible:rounded-xl")}
              style={{
                left: "50%",
                top: FLOOR_TOP,
                width: `clamp(${dims.widthRem}rem, 20vw, ${dims.widthRemLg}rem)`,
                aspectRatio: String(dims.aspect),
                transform: `translate(-50%, -100%) translateX(calc(${diff} * ${gapMultiplier} * ${GAP_BASE} + ${dragOffset}px)) scale(${scale}) rotateY(${rotateY}deg)`,
                transformOrigin: "bottom center",
                opacity,
                zIndex: 100 - absDiff,
                transition: dragState.current ? "none" : transitionStyle,
                viewTransitionName:
                  !isBeingOpened && container.type === "binder" ? BINDER_TRANSITION_NAME(container.id) : undefined,
              }}
            >
              <StorageContainerVisual container={container} />
            </button>
          );
        })}

        <button
          type="button"
          onClick={() => moveTo(focusedIndex - 1)}
          disabled={focusedIndex === 0}
          className="absolute left-3 top-1/2 z-20 -translate-y-1/2 rounded-full border border-white/10 bg-black/30 p-2 text-white/70 transition-colors hover:bg-black/50 hover:text-white disabled:pointer-events-none disabled:opacity-30 sm:left-6"
          aria-label="Container anterior"
        >
          <ChevronLeft className="h-5 w-5" aria-hidden />
        </button>
        <button
          type="button"
          onClick={() => moveTo(focusedIndex + 1)}
          disabled={focusedIndex === containers.length - 1}
          className="absolute right-3 top-1/2 z-20 -translate-y-1/2 rounded-full border border-white/10 bg-black/30 p-2 text-white/70 transition-colors hover:bg-black/50 hover:text-white disabled:pointer-events-none disabled:opacity-30 sm:right-6"
          aria-label="Próximo container"
        >
          <ChevronRight className="h-5 w-5" aria-hidden />
        </button>
      </div>

      <div className="relative z-10 flex flex-col items-center gap-1 pb-8 text-center">
        <h2 className="text-base font-semibold text-white/95 sm:text-lg">{focusedContainer?.name}</h2>
        <p className="text-xs text-white/50">
          {focusedContainer?.subtitle} · {focusedContainer?.itemCount} itens
        </p>
        <p className="mt-1 text-[11px] text-white/35">
          {focusedContainer?.interactive
            ? "Enter/Espaço ou clique novamente para abrir"
            : "Setas, arraste ou role para navegar · este container ainda não abre"}
        </p>
      </div>

      <div aria-live="polite" className="sr-only">
        {liveAnnouncement}
      </div>

      {openBinderContainer && (
        <BinderInterior
          container={openBinderContainer}
          transitionName={BINDER_TRANSITION_NAME(openBinderContainer.id)}
          onClose={handleClose}
        />
      )}
    </div>
  );
}
