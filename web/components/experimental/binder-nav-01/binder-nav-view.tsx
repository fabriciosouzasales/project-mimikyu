"use client";

import { X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { BINDER_NAME } from "@/app/experimental/binder-spike/mock-data";
import { SPREAD_COUNT, getPositionContent } from "@/app/experimental/binder-nav-01/mock-data";
import { runWithViewTransition } from "@/lib/view-transitions";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { BinderCoverClosed } from "./binder-cover-closed";
import { BinderPagesNav } from "./binder-pages-nav";
import { HeroStageBackground } from "./hero-stage-background";
import { SideArrowButton, TopNavControls } from "./nav-controls";

/**
 * BINDER-NAV-01 — baseline de navegação operacional do Binder (pedido de
 * Fabrício, 2026-08-28). Encerra os experimentos de page-turn físico
 * (BINDER-MOTION-01 "carrossel", BINDER-MOTION-02 "page turn 3D" — ambos
 * preservados intactos, não removidos, só não evoluídos): a decisão
 * aprovada é que o Binder V1 usa NAVEGAÇÃO EXPLÍCITA entre spreads
 * (botões/teclado/swipe), não gesto de scroll controlando rotação nem
 * simulação de folha física.
 *
 * Reaproveita, sem alteração, o fluxo fechado→aberto já aprovado do
 * Binder-First (`binder-spike-view.tsx`): clique/Enter/Espaço abre via
 * `runWithViewTransition` (morph capa→miolo, com fallback automático sem
 * suporte do navegador ou `prefers-reduced-motion`), Esc fecha. Isso não
 * está na lista de "não implementar mais" do pedido — só a ROTAÇÃO/VIRADA
 * de página está banida, não a transição de abertura do objeto.
 *
 * A novidade desta rodada é inteiramente dentro do estado "aberto":
 *  - `TopNavControls`/`SideArrowButton` (`nav-controls.tsx`) — controles
 *    explícitos, teclado (←/→/Home/End) e swipe horizontal (pointer
 *    events com limiar de distância, item 4 do pedido);
 *  - `BinderPagesNav` (`binder-pages-nav.tsx`) — mesma casca de
 *    couro/gutter/estrutura de páginas do Binder-First, mas ela NUNCA
 *    remonta entre spreads: só a grade de 9 bolsos de cada página troca de
 *    conteúdo, com uma transição digital curta (~200ms, translate pequeno +
 *    opacity, zero rotação 3D) — exatamente o item 6/7 do pedido ("Binder
 *    deve permanecer espacialmente estável... só o conteúdo do spread
 *    muda").
 *
 * `binder-spike/binder-pages.tsx` (o componente ORIGINAL de 2 páginas
 * fixas) não foi tocado — continua servindo Binder-First/BINDER-VIS-02
 * como estavam. Isolamento experimental total (item 9).
 *
 * Rodada 2 (2026-08-28, mesma data — dois ajustes aprovados por Fabrício
 * após ver o baseline em funcionamento):
 *  1. Setas laterais: deixaram de ser overlay absoluto sobre as páginas e
 *     passaram a ser IRMÃS de flex fora da moldura do Binder
 *     (`SideArrowButton` × 2 ao redor do wrapper do `BinderPagesNav`) — sem
 *     sobreposição a bolsos/cartas, alinhadas ao centro vertical, e
 *     encolhendo (ícone/padding/gap menores) em viewports estreitas em vez
 *     de invadir a área de conteúdo.
 * Rodada 8 (2026-08-28) — refinamento visual pedido por Fabrício a partir de
 * fotos reais de um binder PRETO com zíper (referência mais recente): a capa
 * fechada trocou de `binder-spike/binder-cover.tsx` (compartilhado, marrom)
 * para `binder-cover-closed.tsx` (cópia local, preto/grafite, sem escudo
 * central nem bolso frontal, zíper/puxador em metal escuro — ver doc-comment
 * daquele arquivo para o detalhamento completo) e o glow ambiente abaixo foi
 * reduzido/dessaturado. A primeira abertura (contracapa+página 1) e a
 * navegação operacional já estavam corretas desde a Rodada 2 — não precisou
 * de mudança funcional nesta rodada, só a identidade visual da contracapa
 * (`cover-panel.tsx`, também sem escudo agora).
 *
 *  2. Primeira abertura: passou a refletir a estrutura física real de um
 *     binder (referência: fotos de binders reais com zíper enviadas por
 *     Fabrício) — posição 0 mostra a CONTRACAPA INTERNA (painel sem bolsos,
 *     mesma linguagem de material da capa — `cover-panel.tsx`) ao lado da
 *     primeira página de bolsos, não duas páginas de bolsos direto. A
 *     partir da posição 1, voltam os spreads normais de duas páginas. Ver
 *     `mock-data.ts` (`getPositionContent`) para o deslocamento de
 *     pareamento e a nota sobre a página reservada para o futuro estado
 *     `[última página] | [contracapa traseira]` (não implementado ainda,
 *     por pedido explícito).
 *
 * BINDER-HERO-STAGE-01 (2026-08-28) — rodada focada EXCLUSIVAMENTE na tela
 * inicial fechada (pedido de Fabrício: "o fundo está vazio demais... o
 * binder parece solto em um espaço escuro sem contexto... transformar a
 * tela inicial em um 'hero stage' premium"). Escopo estritamente contido no
 * branch `!open` abaixo — nada na navegação, quick actions, DnD ou lógica
 * do Binder aberto foi tocado; o glow ambiente logo no topo deste arquivo
 * (usado em AMBOS os estados) também ficou intacto.
 *
 *  - `HeroStageBackground` (`hero-stage-background.tsx`, novo arquivo) —
 *    4 camadas reutilizáveis (atmosférica, profundidade, glow-base,
 *    partículas), 100% CSS/SVG, sem nenhum asset de imagem e sem referência
 *    literal à franquia (ver doc-comment daquele arquivo). Renderizada só
 *    dentro do wrapper do botão fechado, atrás dele (`z-0` implícito por
 *    ordem no DOM).
 *  - O botão de abrir ganhou um wrapper (`relative flex flex-1 ...`) só
 *    para acomodar o background atrás dele sem alterar o cálculo de
 *    centralização vertical que já existia (o `flex-1` migrou do `<button>`
 *    para este wrapper nele).
 *  - Sombra de contato do Binder fechado ganhou uma segunda camada, mais
 *    larga e difusa, além da original — reforça a leitura de "levemente
 *    suspenso" (item 3 do pedido) sem exagerar no efeito.
 */

const TRANSITION_NAME = "binder-nav-01-object";
const SWIPE_THRESHOLD_PX = 48;

function clamp(v: number, min: number, max: number) {
  return Math.min(max, Math.max(min, v));
}

export function BinderNavView() {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);
  const [direction, setDirection] = useState<1 | -1>(1);
  const prefersReducedMotion = usePrefersReducedMotion();
  const dialogRef = useRef<HTMLDivElement>(null);
  const swipeRef = useRef<{ startX: number; startY: number } | null>(null);

  const atStart = activeIndex <= 0;
  const atEnd = activeIndex >= SPREAD_COUNT - 1;

  const goTo = useCallback((index: number) => {
    setActiveIndex((current) => {
      const clamped = clamp(index, 0, SPREAD_COUNT - 1);
      if (clamped !== current) setDirection(clamped > current ? 1 : -1);
      return clamped;
    });
  }, []);
  const goFirst = useCallback(() => goTo(0), [goTo]);
  const goPrev = useCallback(() => goTo(activeIndex - 1), [goTo, activeIndex]);
  const goNext = useCallback(() => goTo(activeIndex + 1), [goTo, activeIndex]);
  const goLast = useCallback(() => goTo(SPREAD_COUNT - 1), [goTo]);

  const handleOpen = useCallback(() => {
    runWithViewTransition(() => setOpen(true));
  }, []);
  const handleClose = useCallback(() => {
    runWithViewTransition(() => setOpen(false));
  }, []);

  // Foco entra no "miolo" ao abrir — teclado (←/→/Home/End/Esc) funciona por
  // bubbling do onKeyDown abaixo, sem listener global (não rouba teclado do
  // resto da página quando o Binder não está aberto/focado).
  useEffect(() => {
    if (open) dialogRef.current?.focus();
  }, [open]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (!open) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          handleOpen();
        }
        return;
      }
      switch (event.key) {
        case "Escape":
          event.preventDefault();
          handleClose();
          break;
        case "ArrowLeft":
          event.preventDefault();
          goPrev();
          break;
        case "ArrowRight":
          event.preventDefault();
          goNext();
          break;
        case "Home":
          event.preventDefault();
          goFirst();
          break;
        case "End":
          event.preventDefault();
          goLast();
          break;
      }
    },
    [open, handleOpen, handleClose, goPrev, goNext, goFirst, goLast],
  );

  // Swipe horizontal (mobile, item 4) — limiar de distância em X maior que em
  // Y, para não competir com o scroll vertical normal da página.
  const handlePointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    swipeRef.current = { startX: event.clientX, startY: event.clientY };
  }, []);
  const handlePointerUp = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      const start = swipeRef.current;
      swipeRef.current = null;
      if (!start) return;
      const deltaX = event.clientX - start.startX;
      const deltaY = event.clientY - start.startY;
      if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX || Math.abs(deltaX) < Math.abs(deltaY)) return;
      if (deltaX < 0) goNext();
      else goPrev();
    },
    [goNext, goPrev],
  );
  const handlePointerCancel = useCallback(() => {
    swipeRef.current = null;
  }, []);

  const content = getPositionContent(activeIndex);

  return (
    <div className="relative flex h-dvh w-full flex-col overflow-hidden bg-[hsl(30_20%_7%)]" onKeyDown={handleKeyDown}>
      {/* Glow ambiente — Rodada 8: reduzido e dessaturado (pedido de Fabrício:
          "reduzir excesso de glow/halo/iluminação dourada"). O halo dourado
          herdado do Binder-First ficava "brilho artificial" demais para a
          sobriedade da nova referência preta; mantido só um resquício sutil
          e mais neutro, o suficiente para não achatar o objeto contra o
          fundo. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 60% 50% at 50% 36%, hsl(30 12% 16% / 0.18), transparent 68%), radial-gradient(ellipse 55% 42% at 50% 80%, hsl(30 14% 12% / 0.22), transparent 70%)",
        }}
      />

      <header className="relative z-10 px-6 pt-4 sm:px-10">
        <p className="text-[11px] font-medium uppercase tracking-[0.18em] text-white/35">
          Spike experimental · Binder-Nav-01 · não é a IA oficial
        </p>
        <h1 className="mt-0.5 text-base font-semibold text-white/90 sm:text-lg">Navegação operacional do Binder</h1>
      </header>

      {!open ? (
        <div className="relative flex flex-1 items-center justify-center overflow-hidden">
          {/* Hero stage — só nesta tela; ver doc-comment BINDER-HERO-STAGE-01 no topo do arquivo. */}
          <HeroStageBackground animate={!prefersReducedMotion} />

          <button
            type="button"
            onClick={handleOpen}
            className="group relative z-10 flex items-center justify-center rounded-2xl focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-4 focus-visible:ring-offset-[hsl(30_20%_7%)]"
            aria-label={`Abrir ${BINDER_NAME}`}
          >
            {/* Sombra de contato — camada ampla/difusa por baixo, reforça a
                separação luminosa entre o Binder e o palco (sensação de
                "levemente suspenso", item 3 do pedido). */}
            <span
              aria-hidden
              className="absolute h-10 w-64 rounded-[50%] blur-xl"
              style={{ background: "rgba(0,0,0,0.35)", top: "80%" }}
            />
            {/* Sombra de contato — camada estreita/definida, mais próxima da base real do objeto. */}
            <span
              aria-hidden
              className="absolute h-6 w-48 rounded-[50%] blur-md"
              style={{ background: "rgba(0,0,0,0.55)", top: "77%" }}
            />
            <span
              className={
                prefersReducedMotion
                  ? "inline-block"
                  : "inline-block transition-transform duration-300 ease-out group-hover:-translate-y-1 group-focus-visible:-translate-y-1"
              }
            >
              <BinderCoverClosed viewTransitionName={TRANSITION_NAME} />
            </span>
          </button>
        </div>
      ) : (
        <div
          ref={dialogRef}
          tabIndex={-1}
          className="relative z-10 flex flex-1 flex-col items-center justify-center gap-3 overflow-y-auto px-2 pb-4 outline-none sm:px-10"
          role="dialog"
          aria-modal="true"
          aria-label={`Interior de ${BINDER_NAME}`}
        >
          <button
            type="button"
            onClick={handleClose}
            className="absolute right-4 top-0 z-30 rounded-full border border-white/15 bg-black/20 p-2 text-white/70 transition-colors hover:bg-white/10 hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(30_20%_7%)] sm:right-10"
            aria-label="Fechar binder"
          >
            <X className="h-4 w-4" aria-hidden />
          </button>

          {/* 1. Controles de topo central: « ‹ indicador › » */}
          <TopNavControls index={activeIndex} total={SPREAD_COUNT} onFirst={goFirst} onPrev={goPrev} onNext={goNext} onLast={goLast} />

          {/* 2. Setas laterais maiores — IRMÃS de flex fora da moldura do Binder (Rodada 2:
              não mais overlay sobre as páginas), alinhadas ao centro vertical via
              `items-center`, encolhendo em viewports menores junto com o gap. */}
          <div className="flex w-full items-center justify-center gap-1 px-1 sm:gap-3 sm:px-6 md:gap-5">
            <SideArrowButton direction="prev" onClick={goPrev} disabled={atStart} />

            <div
              className="relative min-w-0 flex-1 select-none touch-pan-y"
              style={{ maxWidth: "min(92rem, calc((100dvh - 220px) * 1.45))" }}
              onPointerDown={handlePointerDown}
              onPointerUp={handlePointerUp}
              onPointerCancel={handlePointerCancel}
            >
              {/* 6/7. Casca/gutter/estrutura das páginas espacialmente estáveis — só o
                  conteúdo de cada lado troca, com transição digital curta. */}
              <BinderPagesNav left={content.left} right={content.right} direction={direction} animate={!prefersReducedMotion} />
            </div>

            <SideArrowButton direction="next" onClick={goNext} disabled={atEnd} />
          </div>

          <p aria-live="polite" className="sr-only">
            Spread {activeIndex + 1} de {SPREAD_COUNT}
          </p>
        </div>
      )}
    </div>
  );
}
