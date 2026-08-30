"use client";

import { X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { BINDER_NAME } from "@/app/experimental/binder-spike/mock-data";
import { SPREAD_COUNT, getPositionContent } from "@/app/experimental/binder-nav-01/mock-data";
import { runWithViewTransition } from "@/lib/view-transitions";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { ThemeToggle } from "@/components/theme-toggle";
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
 *
 * BINDER-NAV-01 LIGHT/DARK (2026-08-29) — pedido de Fabrício: "fazer o
 * experimental funcionar bem nos dois temas, sem redesenhar a experiência...
 * Binder pode continuar escuro... light não pode ser simples inversão de
 * cores... reutilizar a infraestrutura/tokens de tema já existentes."
 *
 * Reaproveita 100% da infraestrutura já aprovada e em produção no resto do
 * app (`next-themes` + Tailwind `darkMode: ["class"]` + tokens CSS em
 * `globals.css`) — nenhuma dependência nova, nenhum mecanismo de tema
 * paralelo. A raiz deste componente ganhou a classe `binder-nav-01-scope`
 * (mesmo padrão de "scope override" já validado em `.app-nav-rail`/
 * `.app-nav-panel`, ver `globals.css`): ela redeclara um pequeno conjunto de
 * tokens PRÓPRIOS (`--binder-page-bg`, `--binder-ambient-glow`,
 * `--binder-hero-*`, `--binder-modal-*`) com valor claro por padrão e um
 * bloco `.dark` com os valores ESCUROS ORIGINAIS, byte-a-byte — dark
 * continua exatamente como estava ("não degradar").
 *
 * O que muda com o tema, e por quê:
 *  - Este componente (fundo do workspace, glow ambiente, header, botões
 *    abrir/fechar) — sim, porque é literalmente a "página" ao redor do
 *    objeto.
 *  - `hero-stage-background.tsx` (atmosfera da tela fechada) — sim, mesma
 *    razão ("Binder fechado" está na lista de cobertura do pedido).
 *  - `nav-controls.tsx` — sim: os controles ficam FORA da moldura de couro,
 *    diretamente sobre o fundo do workspace, então herdam texto
 *    claro-sobre-escuro que ficaria ilegível se só o fundo virasse claro.
 *  - `card-detail-modal.tsx` — sim, pedido explícito ("Card Detail com
 *    superfícies claras premium").
 *  - Capa fechada/aberta, couro/gutter/slots, quick actions, contracapa —
 *    NÃO mudam, de propósito ("Binder pode continuar escuro" + "preservar
 *    materialidade de capa, PVC, slots e gutter"). Nenhum desses arquivos
 *    foi tocado nesta rodada.
 *
 * `ThemeToggle` (`components/theme-toggle.tsx`, componente global já usado
 * no resto do app) foi importado sem alteração — pedido explícito: "se
 * necessário, adicionar toggle apenas no experimental para avaliação", já
 * que esta rota não renderiza o `AppShell`/header padrão onde o toggle
 * global normalmente vive.
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
  // BINDER-TRAY-POSITION-01 — nó DOM da célula direita da faixa de
  // controles de topo, onde o botão da Bandeja é portalado a partir de
  // dentro de `BinderPagesNav` (que é quem tem o `<DndContext>` e o estado
  // real da Bandeja — só a POSIÇÃO visual do controle muda de lugar, ver
  // doc-comment em `binder-pages-nav.tsx`, seção BINDER-TRAY-POSITION-01).
  // `useState` (não `useRef`) porque uma ref só é populada DEPOIS do
  // primeiro commit — sem re-render nesse momento, `BinderPagesNav`
  // receberia `null` para sempre; um callback ref com `useState` dispara a
  // re-renderização necessária assim que o nó existe de verdade.
  const [trayPortalNode, setTrayPortalNode] = useState<HTMLDivElement | null>(null);
  // BINDER-TOOL-RAIL-03 (2026-08-30) — histórico do posicionamento da Tool
  // Rail: BINDER-MULTISELECT-RAIL-01 tentou um portal aqui, abandonado por
  // BINDER-BULK-ACTION-RAIL-POSITION-01 em favor de `absolute`/
  // `right-[calc(...)]` renderizado DIRETO dentro de `BinderPagesNav` — essa
  // segunda abordagem, por sua vez, foi rejeitada NESTA rodada: "a posição
  // atual continua inadequada porque a rail parece flutuar distante do
  // Binder... não resolver com novos offsets absolutos arbitrários." Pedido
  // explícito: compor `[TOOL RAIL] [SETA ESQUERDA] [BINDER] [SETA DIREITA]`
  // como um único layout lateral em FLEX, não com posicionamento calculado.
  // `toolRailPortalNode` é o nó-alvo desse item de flex (ver o `<div>` logo
  // antes da seta esquerda, mais abaixo) — a Tool Rail continua morando
  // logicamente dentro de `BinderPagesNav` (acesso direto a todo o estado de
  // multi-select/Bandeja/Add, sem prop-drilling adicional pela árvore
  // inteira), só a localização VISUAL muda via `createPortal`, exatamente o
  // mesmo mecanismo já usado por `trayPortalNode` acima. Centralização
  // vertical passa a vir de graça do `items-center` do próprio flex row
  // (MESMO mecanismo que já centraliza a seta lateral) — não precisa mais
  // calcular a altura do Binder isoladamente.
  const [toolRailPortalNode, setToolRailPortalNode] = useState<HTMLDivElement | null>(null);
  const prefersReducedMotion = usePrefersReducedMotion();
  const dialogRef = useRef<HTMLDivElement>(null);
  const swipeRef = useRef<{ startX: number; startY: number } | null>(null);

  // BINDER-TOOL-RAIL-03 (2026-08-30) — "Tela cheia" é a única ação nova da
  // Tool Rail implementada de verdade nesta rodada (permitido pelo pedido:
  // "se puder ser implementado trivialmente com API nativa e sem abrir nova
  // frente"). Fullscreen API nativa do browser, sem dependência nova — o
  // ALVO é `dialogRef` (o "miolo" aberto do Binder: header de controles +
  // faixa de navegação + Binder + dock da Bandeja), não `document.
  // documentElement` — fullscreen do elemento certo, não da página inteira.
  // `isFullscreen` é sincronizado via evento `fullscreenchange` (não um
  // estado otimista local) porque o navegador pode sair do fullscreen por
  // fora da nossa própria UI (tecla Esc nativa do browser, F11, etc.) — sem
  // isso o botão dessincronizaria do estado real.
  const [isFullscreen, setIsFullscreen] = useState(false);
  useEffect(() => {
    function handleFullscreenChange() {
      setIsFullscreen(document.fullscreenElement === dialogRef.current);
    }
    document.addEventListener("fullscreenchange", handleFullscreenChange);
    return () => document.removeEventListener("fullscreenchange", handleFullscreenChange);
  }, []);
  const handleToggleFullscreen = useCallback(() => {
    if (typeof document === "undefined") return;
    if (document.fullscreenElement) {
      void document.exitFullscreen();
    } else {
      void dialogRef.current?.requestFullscreen();
    }
  }, []);

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
    <div
      className="binder-nav-01-scope relative flex h-dvh w-full flex-col overflow-hidden bg-[hsl(var(--binder-page-bg))]"
      onKeyDown={handleKeyDown}
    >
      {/* Glow ambiente — Rodada 8: reduzido e dessaturado (pedido de Fabrício:
          "reduzir excesso de glow/halo/iluminação dourada"). O halo dourado
          herdado do Binder-First ficava "brilho artificial" demais para a
          sobriedade da nova referência preta; mantido só um resquício sutil
          e mais neutro, o suficiente para não achatar o objeto contra o
          fundo. LIGHT/DARK (2026-08-29): valor agora vem de
          `--binder-ambient-glow` (ver `globals.css`) — claro e escuro têm
          gradientes desenhados separadamente, não uma inversão. */}
      <div aria-hidden className="pointer-events-none absolute inset-0" style={{ background: "var(--binder-ambient-glow)" }} />

      <header className="relative z-10 flex items-start justify-between gap-3 px-6 pt-4 sm:px-10">
        <div>
          <p className="text-[11px] font-medium uppercase tracking-[0.18em] text-black/40 dark:text-white/35">
            Spike experimental · Binder-Nav-01 · não é a IA oficial
          </p>
          <h1 className="mt-0.5 text-base font-semibold text-black/85 dark:text-white/90 sm:text-lg">
            Navegação operacional do Binder
          </h1>
        </div>
        {/* Toggle de tema — só neste experimental (rota não usa o AppShell/header
            padrão onde `ThemeToggle` normalmente vive). Componente global
            reaproveitado sem nenhuma alteração. */}
        <ThemeToggle />
      </header>

      {!open ? (
        <div className="relative flex flex-1 items-center justify-center overflow-hidden">
          {/* Hero stage — só nesta tela; ver doc-comment BINDER-HERO-STAGE-01 no topo do arquivo. */}
          <HeroStageBackground animate={!prefersReducedMotion} />

          <button
            type="button"
            onClick={handleOpen}
            className="group relative z-10 flex items-center justify-center rounded-2xl focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-4 focus-visible:ring-offset-[hsl(var(--binder-page-bg))]"
            aria-label={`Abrir ${BINDER_NAME}`}
          >
            {/* Sombra de contato — camada ampla/difusa por baixo, reforça a
                separação luminosa entre o Binder e o palco (sensação de
                "levemente suspenso", item 3 do pedido). POLISH LIGHT MODE
                (2026-08-29): no claro, a camada encolhe (`h-7 w-40 blur-lg`
                em vez de `h-10 w-64 blur-xl`) e usa um marrom-neutro de alfa
                mais baixa (`--binder-contact-shadow-wide`) — pedido
                explícito "reduzir área difusa... sombra mais concentrada
                próxima ao objeto". O escuro preserva o tamanho/blur/cor
                originais via `dark:`. */}
            <span
              aria-hidden
              className="absolute h-7 w-40 rounded-[50%] blur-lg dark:h-10 dark:w-64 dark:blur-xl"
              style={{ background: "var(--binder-contact-shadow-wide)", top: "80%" }}
            />
            {/* Sombra de contato — camada estreita/definida, mais próxima da
                base real do objeto. Mesmo polish do claro que a camada acima. */}
            <span
              aria-hidden
              className="absolute h-4 w-32 rounded-[50%] blur-sm dark:h-6 dark:w-48 dark:blur-md"
              style={{ background: "var(--binder-contact-shadow-tight)", top: "78%" }}
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
          // BINDER-FULLSCREEN-LIGHT-CONTROLS-01 (2026-08-30) — `bg-[hsl(var(--binder-page-bg))]`
          // adicionado aqui. Causa raiz da regressão "nav superior + dock da
          // Bandeja somem no light + fullscreen": este `<div>` é o elemento
          // que `handleToggleFullscreen` promove via `requestFullscreen()`
          // (ver doc-comment logo acima) — e ele nunca teve background
          // PRÓPRIO, só herdava visualmente o `bg-[hsl(var(--binder-page-bg))]`
          // do `.binder-nav-01-scope` pai por estar na frente dele na ordem
          // normal de pintura. A API de Fullscreen promove o elemento para o
          // "top layer" do navegador — ele continua sendo descendente do pai
          // no DOM (as CSS custom properties, incluindo `--binder-page-bg`,
          // continuam herdando normalmente), mas deixa de ser pintado NA
          // FRENTE do pai; o que passa a ficar atrás dele é o `::backdrop`
          // do próprio elemento fullscreen, que o UA stylesheet de todo
          // navegador testado define como PRETO OPACO por padrão — sem
          // stylesheet nenhum do projeto envolvido, é comportamento nativo
          // do navegador para qualquer elemento fullscreen sem cor de fundo
          // própria. Como este `<div>` era transparente, o preto do
          // `::backdrop` passava a ser o fundo real em fullscreen.
          //
          // Por que só o LIGHT mostrava o problema: `--binder-page-bg`
          // escuro já é `30 20% 7%` (quase preto) — o preto do `::backdrop`
          // por trás de um fundo quase-preto é visualmente indistinguível,
          // mascarando o bug. `--binder-page-bg` claro é `34 18% 85%` (um
          // "warm stone" claro) — contra um fundo PRETO inesperado, os
          // controles que usam texto/bordas escuros translúcidos sobre fundo
          // claro (`NavButton` em `nav-controls.tsx`: `bg-black/[0.06]
          // text-black/70`; dock da Bandeja em `binder-tray.tsx`:
          // `bg-black/[0.08]`) ficam com contraste próximo de zero — preto
          // translúcido sobre preto opaco — e "somem" exatamente como
          // reportado. Os controles em si (Tool Rail, setas, Bandeja, Quick
          // Actions) nunca saíram do DOM, nunca perderam z-index/posição, e
          // já estavam TODOS dentro deste `<div>` (o container que entra em
          // fullscreen já contém Tool Rail/paginação/Binder/dock — nenhuma
          // composição precisou mudar). Correção: reaproveitar o MESMO token
          // já usado por `.binder-nav-01-scope` (nenhuma cor nova, nenhum
          // valor hardcoded) diretamente aqui, para que o elemento
          // fullscreen tenha sua PRÓPRIA cópia opaca do fundo correto do
          // tema em vez de depender de um pai que deixa de estar "por trás"
          // dele visualmente assim que a Fullscreen API o promove.
          className="relative z-10 flex flex-1 flex-col items-center justify-center gap-3 overflow-y-auto bg-[hsl(var(--binder-page-bg))] px-2 pb-4 outline-none sm:px-10"
          role="dialog"
          aria-modal="true"
          aria-label={`Interior de ${BINDER_NAME}`}
        >
          <button
            type="button"
            onClick={handleClose}
            className="absolute right-4 top-0 z-30 rounded-full border border-black/20 bg-white/75 p-2 text-black/70 transition-colors hover:bg-black/10 hover:text-black/95 focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-page-bg))] dark:border-white/15 dark:bg-black/20 dark:text-white/70 dark:hover:bg-white/10 dark:hover:text-white sm:right-10"
            aria-label="Fechar binder"
          >
            <X className="h-4 w-4" aria-hidden />
          </button>

          {/* 2. Setas laterais maiores — IRMÃS de flex fora da moldura do Binder (Rodada 2:
              não mais overlay sobre as páginas), alinhadas ao centro vertical via
              `items-center`, encolhendo em viewports menores junto com o gap.

              BINDER-TOOL-RAIL-03 (2026-08-30) — a Tool Rail passou a ser o
              PRIMEIRO item desta mesma faixa flex, pedido explícito:
              "[TOOL RAIL] [SETA ESQUERDA] [BINDER] [SETA DIREITA]... a Tool
              Rail e a seta esquerda devem fazer parte do MESMO layout
              lateral ancorado ao wrapper do Binder." Reaproveita o `gap-1
              sm:gap-3 md:gap-5` já existente da faixa para os dois
              respiros pedidos ("gap curto" rail→seta, "gap curto"
              seta→Binder — mesmo valor, sem inventar um novo) e o
              `items-center` já existente para a centralização vertical
              (mesmo mecanismo que já centraliza a seta, não um cálculo
              novo). Resultado: a posição da rail acompanha o Binder em
              qualquer largura de viewport por construção (fluxo normal de
              flex), sem nenhuma referência a viewport/posicionamento
              absoluto — exatamente o pedido. `flex-shrink-0` no nó-alvo
              evita que a rail (a coluna mais estreita da faixa) encolha
              antes da seta/Binder em viewports apertados. */}
          <div className="flex w-full items-center justify-center gap-1 px-1 sm:gap-3 sm:px-6 md:gap-5">
            <div ref={setToolRailPortalNode} className="flex-shrink-0" />
            <SideArrowButton direction="prev" onClick={goPrev} disabled={atStart} />

            <div
              className="relative min-w-0 flex-1 select-none touch-pan-y"
              style={{ maxWidth: "min(92rem, calc((100dvh - 220px) * 1.45))" }}
              onPointerDown={handlePointerDown}
              onPointerUp={handlePointerUp}
              onPointerCancel={handlePointerCancel}
            >
              {/* 1. Controles de topo: « ‹ indicador › » central — voltou a
                  ser um controle único e simples (BINDER-TRAY-REPOSITION-01,
                  2026-08-29: a Bandeja saiu desta faixa e desceu para um
                  dock abaixo do Binder, ver comentário junto de
                  `setTrayPortalNode` mais abaixo — "o problema principal
                  agora é ergonomia... quero reposicionar a Bandeja para a
                  PARTE CENTRAL INFERIOR do Binder"). Sem grid de 3 colunas
                  nem coluna-contrapeso: com só `TopNavControls` aqui, o
                  `items-center` do container pai já centraliza sozinho. */}
              <div className="mb-6">
                <TopNavControls index={activeIndex} total={SPREAD_COUNT} onFirst={goFirst} onPrev={goPrev} onNext={goNext} onLast={goLast} />
              </div>

              {/* 6/7. Casca/gutter/estrutura das páginas espacialmente estáveis — só o
                  conteúdo de cada lado troca, com transição digital curta. */}
              <BinderPagesNav
              left={content.left}
              right={content.right}
              direction={direction}
              animate={!prefersReducedMotion}
              onNavigatePrev={goPrev}
              onNavigateNext={goNext}
              canNavigatePrev={!atStart}
              canNavigateNext={!atEnd}
              trayPortalNode={trayPortalNode}
              toolRailPortalNode={toolRailPortalNode}
              isFullscreen={isFullscreen}
              onToggleFullscreen={handleToggleFullscreen}
            />

              {/* BINDER-TRAY-REPOSITION-01 (2026-08-29) — pedido explícito de
                  Fabrício: a Bandeja, ao lado da paginação (POSITION-01/02),
                  "ainda lê como algo distante do Binder" e — problema
                  ergonômico real, não só estético — como o ponto de pega da
                  carta fica na parte INFERIOR dela, arrastar para uma
                  Bandeja no TOPO cortava visualmente a carta. Nova posição:
                  dock centralizado logo ABAIXO da moldura, "para que ela
                  funcione como um dock/utilitário vinculado ao Binder".
                  Mesmo mecanismo de portal de sempre (`trayPortalNode`,
                  `binder-tray.tsx`/`binder-pages-nav.tsx` intocados nessa
                  parte) — só o nó-alvo mudou de lugar: agora é filho DESTE
                  MESMO wrapper com `maxWidth` do Binder (mesmo racional já
                  usado para a faixa de paginação acima — herda a largura
                  real do Binder sem duplicar o cálculo), abaixo de
                  `<BinderPagesNav>`, `flex justify-center` (dock único,
                  sem paginação para contrabalançar — não precisa mais do
                  grid de 3 colunas da versão anterior). `mt-3` (12px) é a
                  "pequena distância vertical" pedida — mais justo que os
                  28px usados quando a faixa ainda dividia espaço com a
                  paginação, para reforçar a leitura de "preso ao Binder",
                  mas nunca encostando na moldura (sempre um gap real,
                  nunca 0). */}
              <div className="mt-3 flex justify-center">
                <div ref={setTrayPortalNode} />
              </div>
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
