"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
} from "react";
import { BinderMiniPreview } from "./binder-mini-preview";
import { collectionProgress, type MockCollection } from "./mock-collections";

/**
 * COLLECTION-GALLERY-SPIKE-01 — Modo A "Visual Gallery".
 *
 * Inspirado no COMPORTAMENTO do React Bits Depth Carousel (cards recuando
 * em profundidade sobre um trilho 3D), mas reimplementado do zero, sem
 * copiar a skin nem a dependência:
 *  - dependência original confirmada no discovery COLLECTION-GALLERY-01
 *    (2026-08-29) é GSAP — NÃO instalada aqui;
 *  - a mecânica de "tween" do GSAP (interpolar uma posição contínua e
 *    recalcular o layout a cada frame) foi substituída por: (1) estado
 *    discreto de foco (`focusIndex`, um inteiro, não uma posição
 *    fracionária contínua) e (2) `transition` CSS nativa no `transform` de
 *    cada card — o navegador interpola sozinho quando `focusIndex` muda,
 *    sem precisar de um motor de animação em JS. Ver nota "ADAPTAÇÃO" mais
 *    abaixo, perto de `TRANSITION_MS`;
 *  - Pointer Events ficam presos no elemento raiz do componente (`rootRef`),
 *    nunca em `window` — correção deliberada do problema encontrado no
 *    Circular Gallery original (listeners globais que vazam para a página
 *    inteira);
 *  - `prefers-reduced-motion` é checado e zera a duração da transição;
 *  - teclado (Arrow Left/Right) e ARIA de carousel (role/aria-roledescription/
 *    aria-label por slide, indicadores como tablist/tab) seguem o mesmo
 *    padrão que o Depth Carousel original já fazia bem;
 *  - skin 100% MMKYU: tokens do design system (`bg-background`,
 *    `text-foreground`, `bg-surface`, `text-muted-foreground`), sem os
 *    cantos/glass/paleta escura genéricos do componente de referência.
 */

const DEPTH_PX = 150;
const SPREAD_PX = 64;
const TILT_DEG = 16;
const VISIBLE_STEPS = 3;
const FALLOFF = 0.22;
const SWIPE_THRESHOLD_PX = 56;
// ADAPTAÇÃO (elimina GSAP): no componente original, o GSAP anima uma
// posição contínua com física própria (`ease: 'power3.out'`). Aqui, a
// "animação" é delegada à CSS transition abaixo — ela dispara sozinha toda
// vez que `focusIndex` muda, com o navegador cuidando da interpolação.
// `prefersReducedMotion` zera a duração, replicando o comportamento do
// original (que também respeita a preferência, mas via um branch no GSAP).
const TRANSITION_MS = 480;

function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mql = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mql.matches);
    const onChange = () => setReduced(mql.matches);
    mql.addEventListener("change", onChange);
    return () => mql.removeEventListener("change", onChange);
  }, []);
  return reduced;
}

function clamp(v: number, min: number, max: number) {
  return Math.min(Math.max(v, min), max);
}

/** Distância com wraparound (loop), igual ao princípio do Depth Carousel original. */
function wrappedDelta(index: number, focus: number, count: number) {
  let d = index - focus;
  d = ((d % count) + count) % count;
  if (d > count / 2) d -= count;
  return d;
}

interface VisualGalleryProps {
  collections: MockCollection[];
}

export function VisualGallery({ collections }: VisualGalleryProps) {
  const count = collections.length;
  const [focusIndex, setFocusIndex] = useState(0);
  const [isInteracting, setIsInteracting] = useState(false);
  const [dragPx, setDragPx] = useState(0);
  const prefersReducedMotion = usePrefersReducedMotion();

  const rootRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef<{ x: number; pointerId: number } | null>(null);

  useEffect(() => {
    setFocusIndex((i) => clamp(i, 0, Math.max(0, count - 1)));
  }, [count]);

  const navigateBy = useCallback(
    (step: number) => {
      setFocusIndex((i) => ((i + step) % count + count) % count);
    },
    [count],
  );

  const onPointerDown = useCallback((e: ReactPointerEvent<HTMLDivElement>) => {
    dragStartRef.current = { x: e.clientX, pointerId: e.pointerId };
    setIsInteracting(true);
    e.currentTarget.setPointerCapture(e.pointerId);
  }, []);

  const onPointerMove = useCallback((e: ReactPointerEvent<HTMLDivElement>) => {
    const start = dragStartRef.current;
    if (!start || start.pointerId !== e.pointerId) return;
    setDragPx(e.clientX - start.x);
  }, []);

  const endDrag = useCallback(
    (e: ReactPointerEvent<HTMLDivElement>) => {
      const start = dragStartRef.current;
      dragStartRef.current = null;
      setIsInteracting(false);
      const delta = start ? e.clientX - start.x : 0;
      setDragPx(0);
      if (Math.abs(delta) > SWIPE_THRESHOLD_PX) {
        navigateBy(delta < 0 ? 1 : -1);
      }
    },
    [navigateBy],
  );

  const onKeyDown = useCallback(
    (e: ReactKeyboardEvent<HTMLDivElement>) => {
      if (e.key === "ArrowLeft") {
        e.preventDefault();
        navigateBy(-1);
      } else if (e.key === "ArrowRight") {
        e.preventDefault();
        navigateBy(1);
      }
    },
    [navigateBy],
  );

  const focused = collections[focusIndex];
  if (count === 0 || !focused) return null;

  const focusedProgress = collectionProgress(focused);
  const transitionStyle =
    isInteracting || prefersReducedMotion
      ? "none"
      : `transform ${TRANSITION_MS}ms cubic-bezier(0.22,1,0.36,1), opacity 260ms ease, filter 260ms ease`;

  return (
    <div className="flex flex-col items-center gap-6">
      <div
        ref={rootRef}
        role="group"
        aria-roledescription="carousel"
        aria-label="Galeria visual de Collections"
        tabIndex={0}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onKeyDown={onKeyDown}
        className="relative flex h-[340px] w-full max-w-3xl cursor-grab touch-pan-y select-none items-center justify-center rounded-2xl bg-surface outline-none [perspective:1200px] active:cursor-grabbing focus-visible:ring-2 focus-visible:ring-accent"
      >
        {collections.map((collection, i) => {
          const d = wrappedDelta(i, focusIndex, count);
          const back = Math.max(0, d);
          const absD = Math.abs(d);
          const visible = absD <= VISIBLE_STEPS + 0.5;

          const tz = -DEPTH_PX * d;
          const tx = SPREAD_PX * d + (i === focusIndex ? dragPx : 0);
          const ry = TILT_DEG * clamp(d, 0, 1);
          let opacity = d < 0 ? Math.max(0, 1 + d) : 1;
          if (!visible) opacity = 0;
          const brightness = Math.max(0.55, 1 - back * FALLOFF);
          const blurPx = Math.min(4, back * 1.6);
          const isFocused = i === focusIndex;

          return (
            <div
              key={collection.id}
              role="group"
              aria-roledescription="slide"
              aria-label={`${collection.name}, ${i + 1} de ${count}, ${collectionProgress(collection)}% completo`}
              aria-hidden={!visible}
              onClick={() => (isFocused ? undefined : setFocusIndex(i))}
              className="absolute left-1/2 top-1/2 flex w-[168px] cursor-pointer flex-col items-center gap-2"
              style={{
                transform: `translate(-50%, -50%) translateX(${tx}px) translateZ(${tz}px) rotateY(${ry}deg)`,
                opacity,
                filter: `brightness(${brightness}) blur(${blurPx}px)`,
                zIndex: Math.round(1000 - d * 10),
                pointerEvents: visible ? "auto" : "none",
                transition: transitionStyle,
              }}
            >
              <BinderMiniPreview targetWidth={128} />
            </div>
          );
        })}
      </div>

      {/* Indicadores — mesma semântica ARIA do Depth Carousel original. */}
      <div role="tablist" aria-label="Selecionar Collection" className="flex gap-2">
        {collections.map((collection, i) => (
          <button
            key={collection.id}
            type="button"
            role="tab"
            aria-selected={i === focusIndex}
            aria-label={`Ir para ${collection.name}`}
            onClick={() => setFocusIndex(i)}
            className={`h-1.5 rounded-full transition-[width,background-color] duration-200 ${
              i === focusIndex ? "w-6 bg-foreground" : "w-1.5 bg-muted-foreground/30"
            }`}
          />
        ))}
      </div>

      {/* Nome + progresso apenas — nada de aparência administrativa. */}
      <div className="flex flex-col items-center gap-1 text-center">
        <p className="text-sm font-medium text-foreground">{focused.name}</p>
        <div className="h-1 w-40 overflow-hidden rounded-full bg-surface-muted">
          <div className="h-full rounded-full bg-foreground" style={{ width: `${focusedProgress}%` }} />
        </div>
        <p className="text-xs text-muted-foreground">
          {focused.ownedCards}/{focused.totalCards} · {focusedProgress}%
        </p>
        <button
          type="button"
          className="mt-2 rounded-md border border-border px-3 py-1.5 text-xs font-medium text-foreground hover:bg-accent"
          onClick={() => {
            // Spike sem backend — apenas confirma que o "acesso à Collection"
            // é acionável; não há navegação/domínio real neste componente.
            console.log(`[COLLECTION-GALLERY-SPIKE-01] Abrir Collection: ${focused.id}`);
          }}
        >
          Abrir Collection
        </button>
      </div>
    </div>
  );
}
