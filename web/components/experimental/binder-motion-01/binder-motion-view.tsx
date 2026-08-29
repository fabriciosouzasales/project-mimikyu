"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { BINDER_NAME, BINDER_SUBTITLE } from "@/app/experimental/binder-spike/mock-data";
import { MOCK_BINDER_MOTION_SPREADS, SPREAD_COUNT } from "@/app/experimental/binder-motion-01/mock-data";
import { BinderCover, GOLD } from "@/components/experimental/binder-spike/binder-cover";
import { BinderPages } from "@/components/experimental/binder-spike/binder-pages";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";

/**
 * BINDER-MOTION-01 — spike isolado (pedido de Fabrício, 2026-08-28), na
 * sequência do Binder-First (aprovado) e BINDER-VIS-02 (aprovado como
 * baseline visual). Objetivo único desta rodada: testar "vertical scroll →
 * horizontal page navigation" (scrollytelling horizontal, inspirado em
 * product pages tipo Apple) como uma CAMADA DE NAVEGAÇÃO sobre o Binder já
 * aprovado — não uma reformulação visual. Capa, páginas e bolsos são
 * reaproveitados sem nenhuma edição (`BinderCover`/`BinderPages`,
 * importados direto de `binder-spike/`).
 *
 * Mecânica:
 * - Um wrapper alto (`TOTAL_UNITS` alturas de viewport) mantém uma seção
 *   `position: sticky` grudada no topo enquanto o usuário rola por ele.
 * - A posição de scroll dentro desse wrapper vira um "progresso" 0..1 lido
 *   a cada frame (`measure`/`tick`), que por sua vez vira (a) a transição
 *   capa-fechada → miolo-aberto (crossfade + leve escala) e (b) o
 *   deslocamento horizontal (`translateX`) da trilha de spreads.
 * - Isso é DELIBERADAMENTE feito sem `preventDefault`/scroll-jacking de
 *   verdade — o scroll nativo do navegador nunca é interceptado, só lido
 *   (`scroll` passive + `requestAnimationFrame`). É por isso que wheel,
 *   trackpad, touch/swipe (rolagem vertical em mobile) e teclado (setas/
 *   PageDown, que já rolam a página) funcionam de graça, sem nenhum código
 *   de gesto customizado. Isso também é o que torna "vertical input →
 *   horizontal output" possível: o input continua sendo scroll vertical
 *   comum, só a saída visual (transform) é horizontal.
 * - Ao final do último spread o wrapper alto termina — o scroll vertical
 *   segue normalmente para o conteúdo depois da seção (sem trap de scroll).
 * - Snap suave: ao detectar fim de rolagem (`scrollend` nativo, com
 *   fallback por debounce onde não suportado), corrige a posição para o
 *   degrau (spread) mais próximo via `scrollTo({ behavior: "smooth" })`.
 *
 * Navegação tradicional (exigência do pedido): botões Anterior/Próximo e
 * teclado (setas/PageUp/PageDown, só quando a seção está visível) sempre
 * funcionam, fazendo `scrollTo` para o ponto exato do spread — nunca
 * dependem do usuário "acertar" o scroll manualmente.
 *
 * `prefers-reduced-motion`: desliga o pin/scroll-jacking por completo (nem
 * monta o wrapper alto) e renderiza `ReducedMotionFlow` — fluxo vertical
 * comum com botão Abrir + Anterior/Próximo, zero transformação ligada a
 * scroll.
 *
 * Performance: só `transform`/`opacity` são escritos a cada frame (GPU,
 * sem layout thrashing), via refs direto no DOM — nenhum `setState` a cada
 * scroll (só quando o spread "inteiro" muda, para atualizar os pontos de
 * progresso/aria-live). Um único `requestAnimationFrame` pendente por vez
 * (`rafRef`); um `IntersectionObserver` restringe o teclado à seção
 * visível, sem custo de rodar a lógica de scroll fora dela.
 */

const OPEN_UNIT = 1;
const DWELL_UNIT = 1;
/** 1 unidade de abertura + (N-1) unidades de transição entre spreads + 1 unidade de fôlego final. */
const TOTAL_UNITS = OPEN_UNIT + (SPREAD_COUNT - 1) + DWELL_UNIT;

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

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
      <Footer note="prefers-reduced-motion ativo — navegação só por botões, sem scroll acoplado." />
    </div>
  );
}

/* ------------------------------ Fluxo motion ----------------------------- */

function ScrollDrivenFlow() {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const heroRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const rafRef = useRef<number | null>(null);
  const rawIndexRef = useRef(0);
  const engagedRef = useRef(false);
  const scrollEndTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [spreadIndex, setSpreadIndex] = useState(0);
  const [phase, setPhase] = useState<"closed" | "opening" | "browsing">("closed");

  const applyStyles = useCallback((virtualIndex: number) => {
    const openT = clamp(virtualIndex / OPEN_UNIT, 0, 1);
    const horizontalRaw = clamp(virtualIndex - OPEN_UNIT, 0, SPREAD_COUNT - 1);

    if (heroRef.current) {
      const heroScale = lerp(1, 0.86, openT);
      heroRef.current.style.opacity = String(1 - openT);
      heroRef.current.style.transform = `scale(${heroScale})`;
      heroRef.current.style.pointerEvents = openT > 0.98 ? "none" : "auto";
    }
    if (trackRef.current) {
      trackRef.current.style.opacity = String(openT);
      trackRef.current.style.transform = `translateX(${-horizontalRaw * 100}%)`;
    }

    const nextPhase: "closed" | "opening" | "browsing" = openT >= 1 ? "browsing" : openT > 0 ? "opening" : "closed";
    setPhase((p) => (p === nextPhase ? p : nextPhase));
    const nextSpread = Math.round(horizontalRaw);
    setSpreadIndex((s) => (s === nextSpread ? s : nextSpread));
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
    const virtualIndex = p * TOTAL_UNITS;
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
    const p = clamp(virtualIndex / TOTAL_UNITS, 0, 1);
    const targetY = wrapper.offsetTop + p * scrollableDistance;
    window.scrollTo({ top: targetY, behavior: smooth ? "smooth" : "auto" });
  }, []);

  const goToSpread = useCallback(
    (index: number) => {
      scrollToVirtualIndex(OPEN_UNIT + clamp(index, 0, SPREAD_COUNT - 1));
    },
    [scrollToVirtualIndex],
  );

  const goOpen = useCallback(() => scrollToVirtualIndex(OPEN_UNIT), [scrollToVirtualIndex]);

  // Le a posicao de scroll a cada frame (nunca intercepta o scroll nativo).
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

  // So escuta teclado quando a secao esta visivel, para nao roubar as setas do resto da pagina.
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
        if (rawIndexRef.current < OPEN_UNIT - 0.01) goOpen();
        else goToSpread(Math.round(rawIndexRef.current - OPEN_UNIT) + 1);
      } else if (event.key === "ArrowLeft" || event.key === "PageUp") {
        event.preventDefault();
        goToSpread(Math.round(rawIndexRef.current - OPEN_UNIT) - 1);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [goOpen, goToSpread]);

  // Snap suave: ao "terminar" de rolar (scrollend nativo, com fallback por debounce),
  // corrige para o degrau mais proximo — evita parar "no meio" de uma transicao.
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

  return (
    <div className="relative w-full bg-[hsl(30_20%_7%)]">
      <Header />

      <a
        href="#binder-motion-fim"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-16 focus:z-50 focus:rounded-full focus:bg-white/90 focus:px-4 focus:py-2 focus:text-sm focus:font-medium focus:text-black"
      >
        Pular navegação horizontal do binder
      </a>

      <div ref={wrapperRef} style={{ height: `${TOTAL_UNITS * 100}vh` }} className="relative">
        <div className="sticky top-0 h-dvh w-full overflow-hidden">
          <div
            ref={heroRef}
            className="pointer-events-auto absolute inset-0 flex flex-col items-center justify-center"
            style={{ willChange: "transform, opacity" }}
          >
            <BinderCover />
          </div>

          <div
            ref={trackRef}
            className="absolute inset-0 flex items-center opacity-0"
            style={{ willChange: "transform, opacity" }}
            aria-hidden={phase !== "browsing"}
          >
            {MOCK_BINDER_MOTION_SPREADS.map((spread) => (
              <div key={spread.id} className="flex h-full w-full flex-shrink-0 items-center justify-center px-4">
                <BinderPages pages={[spread.left, spread.right]} />
              </div>
            ))}
          </div>

          <ProgressDots total={SPREAD_COUNT} current={spreadIndex} visible={phase !== "closed"} onSelect={goToSpread} />

          <SpreadNav
            index={spreadIndex}
            total={SPREAD_COUNT}
            visible={phase === "browsing"}
            onPrev={() => goToSpread(spreadIndex - 1)}
            onNext={() => goToSpread(spreadIndex + 1)}
          />

          <p aria-live="polite" className="sr-only">
            {phase === "closed"
              ? "Binder fechado"
              : phase === "opening"
                ? "Abrindo binder"
                : `Spread ${spreadIndex + 1} de ${SPREAD_COUNT}`}
          </p>

          {phase === "closed" && (
            <p className="pointer-events-none absolute bottom-10 left-1/2 -translate-x-1/2 text-[11px] uppercase tracking-[0.18em] text-white/35">
              Continue rolando para abrir
            </p>
          )}
        </div>
      </div>

      <div id="binder-motion-fim" />
      <Footer note="Scroll vertical liberado normalmente após o último spread — role para ver este rodapé." />
    </div>
  );
}

/* ------------------------------ Subcomponentes ---------------------------- */

function Header() {
  return (
    <header className="relative z-10 px-6 pt-4 sm:px-10">
      <p className="text-[11px] font-medium uppercase tracking-[0.18em] text-white/35">
        Spike experimental · Binder-Motion-01 · não é a IA oficial
      </p>
      <h1 className="mt-0.5 text-base font-semibold text-white/90 sm:text-lg">
        Vertical scroll → horizontal page navigation
      </h1>
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
      <p className="text-[11px] text-white/25">Fim do spike BINDER-MOTION-01.</p>
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
      className="pointer-events-auto absolute inset-x-0 top-1/2 flex -translate-y-1/2 items-center justify-between px-3 transition-opacity duration-300 sm:px-6"
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
