"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { BINDER_NAME, BINDER_SUBTITLE } from "@/app/experimental/binder-spike/mock-data";
import { MOCK_BINDER_MOTION_SPREADS, SPREAD_COUNT } from "@/app/experimental/binder-motion-02/mock-data";
import { BinderCover, GOLD, LEATHER_HUE, leatherSurface } from "@/components/experimental/binder-spike/binder-cover";
import { BinderPages } from "@/components/experimental/binder-spike/binder-pages";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { CoverFaceBack, CoverFaceFront } from "./cover-faces";
import { HingedLeaf, type HingedLeafHandle } from "./hinged-leaf";
import { EndOfBinderFace, PageFace } from "./page-face";

/**
 * BINDER-MOTION-02 — "Page Turn" (pedido de Fabrício, 2026-08-28), na
 * sequência da REPROVAÇÃO CONCEITUAL do BINDER-MOTION-01: aquele spike
 * media "vertical scroll → horizontal page navigation" com um carrossel
 * (translateX de spreads inteiros + crossfade na abertura), o que lia como
 * UI genérica — sem sensação de abrir/folhear um objeto físico. Este spike
 * substitui TODA a metáfora de motion (mantendo só os aprendizados
 * técnicos de scroll/reduced-motion/performance) por uma virada de página
 * de verdade: rotação 3D em torno da lombada/gutter, frente/verso
 * distintos, sombra dinâmica, palco espacialmente ESTÁVEL (nunca se move
 * ou redimensiona — só a folha ativa gira).
 *
 * Mecânica central — `HingedLeaf` (ver `hinged-leaf.tsx`): uma folha com
 * dobradiça na borda esquerda, usada duas vezes:
 *  1. A CAPA gira em torno da lombada (0° → -150°) revelando o palco do
 *     miolo por trás — nenhum crossfade, é rotação pura.
 *  2. A PÁGINA DIREITA ativa gira (0° → -180°) sobre o gutter: como a
 *     dobradiça da página é exatamente a mesma linha do gutter que separa
 *     página esquerda/direita, ao chegar a -180° a folha (agora mostrando
 *     seu VERSO) fica geometricamente sobreposta à posição da página
 *     esquerda — o "pouso" clássico de um page-flip. A página esquerda
 *     estática só troca de conteúdo no instante exato em que a folha volta
 *     a 0° para o próximo spread, então a troca é imperceptível (mesmo
 *     conteúdo, mesma posição, no mesmo frame).
 *
 * Mapeamento de dados: cada spread já é {left, right}; ao virar do spread i
 * para i+1, a folha ativa mostra FRENTE = spreads[i].right e VERSO =
 * spreads[i+1].left — os dois lados físicos da mesma folha, sem precisar
 * inventar um modelo de paginação contínua novo.
 *
 * Progresso (`virtualIndex`) varia de -1 (capa fechada) a SPREAD_COUNT-1
 * (último spread em repouso). [-1, 0] = abertura da capa; [0, N-1] = uma
 * unidade por virada de página. Igual ao MOTION-01, a leitura do scroll
 * nunca intercepta o scroll nativo (sem `preventDefault` em scroll) — só
 * lê a posição via `requestAnimationFrame`. Diferente do MOTION-01: o
 * ÂNGULO nunca passa por `useState` — é escrito direto no DOM via
 * `HingedLeaf.setAngle()` (ref imperativo), então não há re-render do React
 * a cada frame, só quando o spread ativo muda de fato (aprendizado de
 * performance preservado e reforçado).
 *
 * Input: scroll vertical (roda/trackpad/touch, sem gesto customizado),
 * clique nos botões Anterior/Próximo, teclado (setas/PageUp/PageDown, só
 * quando a seção está visível) e, opcionalmente, arraste na borda da
 * página — implementado como um input alternativo que empurra a MESMA
 * posição de scroll (não é um estado paralelo), reaproveitando 100% do
 * pipeline de scroll já existente.
 *
 * `prefers-reduced-motion`: nenhuma rotação 3D — troca instantânea de
 * spread via botões, reaproveitando `BinderCover`/`BinderPages` tal como
 * aprovados (mesmo padrão usado no fallback do MOTION-01).
 */

const TOTAL_UNITS = SPREAD_COUNT; // [-1, SPREAD_COUNT - 1]
const COVER_OPEN_ANGLE = -150;
const PAGE_TURN_ANGLE = -180;

function clamp(v: number, min: number, max: number) {
  return Math.min(max, Math.max(min, v));
}

export function BinderMotionView() {
  const prefersReducedMotion = usePrefersReducedMotion();
  return prefersReducedMotion ? <ReducedMotionFlow /> : <ScrollDrivenFlow />;
}

/* --------------------------- Fallback acessível -------------------------- */

function ReducedMotionFlow() {
  const [opened, setOpened] = useState(false);
  const [index, setIndex] = useState(0);
  const spread = MOCK_BINDER_MOTION_SPREADS[index]!;

  return (
    <div className="relative flex min-h-dvh w-full flex-col bg-[hsl(30_20%_7%)]">
      <Header />
      <div className="flex flex-1 flex-col items-center justify-center gap-6 px-4 py-10">
        {!opened ? (
          <>
            <BinderCover />
            <button
              type="button"
              onClick={() => setOpened(true)}
              className="rounded-full border border-white/15 bg-white/5 px-5 py-2 text-sm font-medium text-white/85 transition-colors hover:bg-white/10"
            >
              Abrir binder
            </button>
          </>
        ) : (
          <>
            <BinderPages pages={[spread.left, spread.right]} />
            <SpreadNav
              index={index}
              total={SPREAD_COUNT}
              onPrev={() => setIndex((i) => Math.max(0, i - 1))}
              onNext={() => setIndex((i) => Math.min(SPREAD_COUNT - 1, i + 1))}
            />
          </>
        )}
      </div>
      <Footer note="prefers-reduced-motion ativo — troca de spread instantânea, sem rotação 3D." />
    </div>
  );
}

/* ------------------------------ Fluxo motion ----------------------------- */

function ScrollDrivenFlow() {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const rightAreaRef = useRef<HTMLDivElement>(null);
  const coverLeafRef = useRef<HingedLeafHandle>(null);
  const pageLeafRef = useRef<HingedLeafHandle>(null);
  const rafRef = useRef<number | null>(null);
  const rawIndexRef = useRef(-1);
  const engagedRef = useRef(false);
  const scrollEndTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const dragRef = useRef<{ startX: number; startScrollY: number; pageWidthPx: number } | null>(null);

  const [activeIndex, setActiveIndex] = useState(0);
  const [phase, setPhase] = useState<"closed" | "opening" | "browsing">("closed");

  const applyStyles = useCallback((virtualIndex: number) => {
    const coverT = clamp(virtualIndex + 1, 0, 1);
    coverLeafRef.current?.setAngle(COVER_OPEN_ANGLE * coverT);

    const pagePos = clamp(virtualIndex, 0, SPREAD_COUNT - 1);
    const nextActiveIndex = Math.min(Math.floor(pagePos), SPREAD_COUNT - 1);
    const frac = pagePos - nextActiveIndex;
    const canTurnForward = nextActiveIndex < SPREAD_COUNT - 1;
    pageLeafRef.current?.setAngle(canTurnForward ? PAGE_TURN_ANGLE * frac : 0);

    const nextPhase: "closed" | "opening" | "browsing" = coverT >= 1 ? "browsing" : coverT > 0 ? "opening" : "closed";
    setPhase((p) => (p === nextPhase ? p : nextPhase));
    setActiveIndex((i) => (i === nextActiveIndex ? i : nextActiveIndex));
  }, []);

  const measure = useCallback(() => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return null;
    const viewportH = window.innerHeight;
    const wrapperH = wrapper.offsetHeight;
    const scrollableDistance = wrapperH - viewportH;
    if (scrollableDistance <= 0) return null;
    const rectTop = wrapper.getBoundingClientRect().top;
    const scrolled = clamp(-rectTop, 0, scrollableDistance);
    return scrolled / scrollableDistance;
  }, []);

  const tick = useCallback(() => {
    rafRef.current = null;
    const p = measure();
    if (p == null) return;
    const virtualIndex = -1 + p * TOTAL_UNITS;
    rawIndexRef.current = virtualIndex;
    applyStyles(virtualIndex);
  }, [applyStyles, measure]);

  const scheduleTick = useCallback(() => {
    if (rafRef.current == null) {
      rafRef.current = requestAnimationFrame(tick);
    }
  }, [tick]);

  const scrollToVirtualIndex = useCallback((virtualIndex: number, smooth = true) => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const viewportH = window.innerHeight;
    const wrapperH = wrapper.offsetHeight;
    const scrollableDistance = wrapperH - viewportH;
    const p = clamp((virtualIndex + 1) / TOTAL_UNITS, 0, 1);
    const targetY = wrapper.offsetTop + p * scrollableDistance;
    window.scrollTo({ top: targetY, behavior: smooth ? "smooth" : "auto" });
  }, []);

  const goToSpread = useCallback(
    (index: number) => scrollToVirtualIndex(clamp(index, 0, SPREAD_COUNT - 1)),
    [scrollToVirtualIndex],
  );
  const goOpen = useCallback(() => scrollToVirtualIndex(0), [scrollToVirtualIndex]);

  useEffect(() => {
    const onScroll = () => scheduleTick();
    const onResize = () => scheduleTick();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onResize);
    scheduleTick();
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onResize);
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, [scheduleTick]);

  useEffect(() => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        engagedRef.current = !!entry?.isIntersecting;
      },
      { threshold: 0.15 },
    );
    observer.observe(wrapper);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!engagedRef.current) return;
      if (event.key === "ArrowRight" || event.key === "PageDown") {
        event.preventDefault();
        if (rawIndexRef.current < -0.01) goOpen();
        else goToSpread(Math.round(rawIndexRef.current) + 1);
      } else if (event.key === "ArrowLeft" || event.key === "PageUp") {
        event.preventDefault();
        goToSpread(Math.round(rawIndexRef.current) - 1);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [goOpen, goToSpread]);

  // Snap suave — mesma técnica do MOTION-01 (scrollend nativo + fallback por debounce).
  useEffect(() => {
    const supportsScrollEnd = "onscrollend" in window;
    const settle = () => {
      const virtualIndex = rawIndexRef.current;
      const nearest = Math.round(virtualIndex);
      if (Math.abs(virtualIndex - nearest) > 0.02) {
        scrollToVirtualIndex(nearest);
      }
    };
    const onScrollEnd = () => settle();
    const onScrollDebounced = () => {
      if (scrollEndTimerRef.current) clearTimeout(scrollEndTimerRef.current);
      scrollEndTimerRef.current = setTimeout(settle, 160);
    };
    if (supportsScrollEnd) {
      window.addEventListener("scrollend", onScrollEnd);
    } else {
      window.addEventListener("scroll", onScrollDebounced, { passive: true });
    }
    return () => {
      window.removeEventListener("scrollend", onScrollEnd);
      window.removeEventListener("scroll", onScrollDebounced);
      if (scrollEndTimerRef.current) clearTimeout(scrollEndTimerRef.current);
    };
  }, [scrollToVirtualIndex]);

  // Drag na borda da página — input alternativo que empurra a MESMA posição de
  // scroll (não é um estado paralelo), reaproveitando o pipeline inteiro acima.
  const onPointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const wrapper = wrapperRef.current;
    const rightArea = rightAreaRef.current;
    if (!wrapper || !rightArea) return;
    (event.target as HTMLElement).setPointerCapture(event.pointerId);
    dragRef.current = {
      startX: event.clientX,
      startScrollY: window.scrollY,
      pageWidthPx: rightArea.getBoundingClientRect().width,
    };
  }, []);

  const onPointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      const drag = dragRef.current;
      const wrapper = wrapperRef.current;
      if (!drag || !wrapper || drag.pageWidthPx <= 0) return;
      const deltaFraction = (drag.startX - event.clientX) / drag.pageWidthPx;
      const viewportH = window.innerHeight;
      const scrollableDistance = wrapper.offsetHeight - viewportH;
      const pixelsPerUnit = scrollableDistance / TOTAL_UNITS;
      window.scrollTo({ top: drag.startScrollY + deltaFraction * pixelsPerUnit, behavior: "auto" });
    },
    [],
  );

  const onPointerUp = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (dragRef.current) {
      dragRef.current = null;
      const nearest = Math.round(rawIndexRef.current);
      scrollToVirtualIndex(nearest);
    }
    (event.target as HTMLElement).releasePointerCapture?.(event.pointerId);
  }, [scrollToVirtualIndex]);

  const spread = MOCK_BINDER_MOTION_SPREADS[activeIndex]!;
  const nextSpread = MOCK_BINDER_MOTION_SPREADS[activeIndex + 1];

  return (
    <div className="relative w-full bg-[hsl(30_20%_7%)]">
      <Header />

      <a
        href="#binder-motion-02-fim"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-16 focus:z-50 focus:rounded-full focus:bg-white/90 focus:px-4 focus:py-2 focus:text-sm focus:font-medium focus:text-black"
      >
        Pular navegação do binder
      </a>

      <div ref={wrapperRef} style={{ height: `${TOTAL_UNITS * 100}vh` }} className="relative">
        <div className="sticky top-0 flex h-dvh w-full items-center justify-center overflow-hidden">
          {/* Wrapper único: tamanho/centralização do "livro" moram só aqui — o palco
              e a folha da capa são ambos `absolute inset-0` dentro dele, então a capa
              gira exatamente sobre o palco sem nenhuma matemática de margin/calc. */}
          <div className="relative" style={{ width: "clamp(300px, 92vw, 920px)", aspectRatio: "1.44" }}>
            {/* Palco do miolo — espacialmente estável, nunca se move/redimensiona. */}
            <div
              ref={stageRef}
              className="absolute inset-0 overflow-hidden rounded-[22px]"
              style={{
                perspective: 1800,
                backgroundImage: leatherSurface(LEATHER_HUE),
                boxShadow: [
                  "inset 0 1px 0 hsl(0 0% 100% / 0.1)",
                  "inset 0 -2px 10px hsl(0 0% 0% / 0.5)",
                  "0 40px 60px -20px rgba(0,0,0,0.65)",
                ].join(", "),
                border: `1px solid hsl(${GOLD} / 0.18)`,
              }}
            >
              <div className="absolute inset-0 flex" style={{ padding: "clamp(10px, 2.4vw, 22px)" }}>
              {/* Página esquerda — estática, só troca de conteúdo no instante do "pouso" da virada. */}
              <div className="relative h-full flex-1">
                <ThicknessStack side="left" count={Math.min(activeIndex, 4)} />
                <PageFace page={spread.left} side="left" />
              </div>

              {/* Vinco central */}
              <div
                className="pointer-events-none relative w-5 flex-shrink-0"
                style={{
                  background: `linear-gradient(90deg, transparent, hsl(${LEATHER_HUE} 20% 4%) 35%, hsl(${LEATHER_HUE} 20% 4%) 65%, transparent)`,
                  boxShadow: "0 0 16px 4px rgba(0,0,0,0.5)",
                }}
                aria-hidden
              />

              {/* Página direita — camada estática revelada por baixo + folha com dobradiça por cima. */}
              <div
                ref={rightAreaRef}
                className="relative h-full flex-1 touch-none"
                onPointerDown={onPointerDown}
                onPointerMove={onPointerMove}
                onPointerUp={onPointerUp}
                onPointerCancel={onPointerUp}
              >
                <ThicknessStack side="right" count={Math.min(SPREAD_COUNT - 1 - activeIndex, 4)} />
                <div className="absolute inset-0">
                  {nextSpread ? <PageFace page={nextSpread.right} side="right" /> : <EndOfBinderFace side="right" />}
                </div>
                <HingedLeaf
                  ref={pageLeafRef}
                  className="absolute inset-0"
                  style={{ position: "absolute" }}
                  front={<PageFace page={spread.right} side="right" />}
                  back={nextSpread ? <PageFace page={nextSpread.left} side="left" isVerso /> : <EndOfBinderFace side="left" />}
                />
              </div>
            </div>
            </div>

            {/* Capa — gira em torno da lombada (borda esquerda do palco inteiro), sem crossfade. */}
            <HingedLeaf
              ref={coverLeafRef}
              className="absolute inset-0 z-30"
              style={{ position: "absolute" }}
              front={<CoverFaceFront />}
              back={<CoverFaceBack />}
            />
          </div>

          <ProgressDots total={SPREAD_COUNT} current={activeIndex} visible={phase !== "closed"} onSelect={goToSpread} />

          <SpreadNav
            index={activeIndex}
            total={SPREAD_COUNT}
            visible={phase === "browsing"}
            onPrev={() => goToSpread(activeIndex - 1)}
            onNext={() => goToSpread(activeIndex + 1)}
          />

          <p aria-live="polite" className="sr-only">
            {phase === "closed"
              ? "Binder fechado"
              : phase === "opening"
                ? "Abrindo binder"
                : `Spread ${activeIndex + 1} de ${SPREAD_COUNT}`}
          </p>

          {phase === "closed" && (
            <p className="pointer-events-none absolute bottom-10 left-1/2 -translate-x-1/2 text-[11px] uppercase tracking-[0.18em] text-white/35">
              Continue rolando para abrir
            </p>
          )}
        </div>
      </div>

      <div id="binder-motion-02-fim" />
      <Footer note="Scroll vertical liberado normalmente após o último spread — role para ver este rodapé." />
    </div>
  );
}

/* ------------------------------ Subcomponentes ---------------------------- */

function ThicknessStack({ side, count }: { side: "left" | "right"; count: number }) {
  if (count <= 0) return null;
  return (
    <>
      {Array.from({ length: count }, (_, i) => (
        <div
          key={i}
          className={`pointer-events-none absolute inset-0 ${side === "left" ? "rounded-l-lg" : "rounded-r-lg"}`}
          style={{
            transform: `translate(${side === "left" ? -(i + 1) : i + 1}px, ${(i + 1) * 1.2}px)`,
            background: `hsl(${LEATHER_HUE} ${10 + i}% ${5 + i}%)`,
          }}
          aria-hidden
        />
      ))}
    </>
  );
}

function Header() {
  return (
    <header className="relative z-10 px-6 pt-4 sm:px-10">
      <p className="text-[11px] font-medium uppercase tracking-[0.18em] text-white/35">
        Spike experimental · Binder-Motion-02 · Page Turn · não é a IA oficial
      </p>
      <h1 className="mt-0.5 text-base font-semibold text-white/90 sm:text-lg">Abrir e folhear um Binder físico</h1>
      <p className="mt-1 max-w-md text-xs text-white/40">
        {BINDER_NAME} · {BINDER_SUBTITLE} · {SPREAD_COUNT} spreads mockados
      </p>
    </header>
  );
}

function Footer({ note }: { note: string }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
      <p className="text-xs text-white/40">{note}</p>
      <p className="text-[11px] text-white/25">Fim do spike BINDER-MOTION-02.</p>
    </div>
  );
}

function ProgressDots({
  total,
  current,
  visible,
  onSelect,
}: {
  total: number;
  current: number;
  visible: boolean;
  onSelect: (index: number) => void;
}) {
  return (
    <div
      className="pointer-events-auto absolute bottom-6 left-1/2 flex -translate-x-1/2 items-center gap-2 transition-opacity duration-300"
      style={{ opacity: visible ? 1 : 0 }}
    >
      {Array.from({ length: total }, (_, i) => (
        <button
          key={i}
          type="button"
          aria-label={`Ir para spread ${i + 1}`}
          onClick={() => onSelect(i)}
          className="h-1.5 rounded-full transition-all duration-300"
          style={{
            width: i === current ? 18 : 6,
            background: i === current ? `hsl(${GOLD})` : "hsl(0 0% 100% / 0.25)",
          }}
        />
      ))}
    </div>
  );
}

function SpreadNav({
  index,
  total,
  visible = true,
  onPrev,
  onNext,
}: {
  index: number;
  total: number;
  visible?: boolean;
  onPrev: () => void;
  onNext: () => void;
}) {
  return (
    <div
      className="pointer-events-auto absolute inset-x-0 top-1/2 z-20 flex -translate-y-1/2 items-center justify-between px-3 transition-opacity duration-300 sm:px-6"
      style={{ opacity: visible ? 1 : 0 }}
    >
      <button
        type="button"
        onClick={onPrev}
        disabled={index <= 0}
        aria-label="Spread anterior"
        className="rounded-full border border-white/15 bg-black/30 p-2 text-white/70 backdrop-blur-sm transition-colors hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-30"
      >
        <ChevronLeft className="h-4 w-4" aria-hidden />
      </button>
      <button
        type="button"
        onClick={onNext}
        disabled={index >= total - 1}
        aria-label="Próximo spread"
        className="rounded-full border border-white/15 bg-black/30 p-2 text-white/70 backdrop-blur-sm transition-colors hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-30"
      >
        <ChevronRight className="h-4 w-4" aria-hidden />
      </button>
    </div>
  );
}
