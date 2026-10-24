"use client";

import { useDroppable } from "@dnd-kit/core";
import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { openLeatherStops } from "@/lib/colecoes/binder-finish";
import { cn } from "@/lib/utils";

/**
 * Peças visuais do Fichário Digital recuperadas do spike aprovado
 * `components/experimental/binder-nav-01/` (P2-B-SPIKE-RECOVERY-01).
 *
 * Copiadas para produção — o experimental continua intacto e isolado (não
 * importamos de lá: ele depende de dados simulados). Mesmos valores visuais:
 * couro preto com trama, zíper escuro nas bordas, puxador, miolo marrom
 * profundo, contracapa com a marca em baixo-relevo, controles de navegação
 * em pílula (« ‹ n / N › ») acima do fichário e setas laterais redondas.
 *
 * Origem por peça:
 *  - `BLACK_HUE`, `blackLeatherSurface`, `darkZipperTeeth` ← binder-cover-closed.tsx
 *  - `INTERIOR_HUE`, moldura/miolo/lombada               ← binder-pages-nav.tsx
 *  - `TopNavControls`, `SideArrowButton`                  ← nav-controls.tsx
 *  - `InsideCoverFace`, `MmkyuWordmark`                   ← cover-panel.tsx / wordmark.tsx
 * Os tokens de fundo (`--binder-page-bg`, `--binder-ambient-glow`) já vivem
 * em `app/globals.css` sob `.binder-nav-01-scope` (claro e escuro).
 */

export const BLACK_HUE = 30;
export const INTERIOR_HUE = 26;

export function blackLeatherSurface() {
  return leatherSurface("onix");
}

/**
 * Couro da moldura externa do fichário aberto no acabamento da coleção
 * (BINDER-OPEN-COLOR-CONSISTENCY-01). Mesma trama, mesmo brilho e mesma
 * direção de luz do couro preto do spike — só a cor de base muda, com os
 * tons de `OPEN_LEATHER_STOPS` (derivados da capa fechada). Ônix produz
 * exatamente o couro preto aprovado.
 */
export function leatherSurface(finish: unknown) {
  const [hi, mid, deep] = openLeatherStops(finish);
  return [
    "repeating-linear-gradient(115deg, hsl(0 0% 100% / 0.025) 0px, hsl(0 0% 100% / 0.025) 1px, transparent 1px, transparent 2.5px)",
    "repeating-linear-gradient(25deg, hsl(0 0% 0% / 0.05) 0px, hsl(0 0% 0% / 0.05) 1px, transparent 1px, transparent 3px)",
    "linear-gradient(125deg, hsl(0 0% 100% / 0.05) 0%, transparent 26%)",
    `linear-gradient(155deg, hsl(${hi}) 0%, hsl(${mid}) 55%, hsl(${deep}) 100%)`,
  ].join(", ");
}

export function darkZipperTeeth(vertical: boolean) {
  const angle = vertical ? "180deg" : "90deg";
  return `repeating-linear-gradient(${angle}, hsl(0 0% 42%) 0px, hsl(0 0% 42%) 1.5px, hsl(0 0% 10%) 1.5px, hsl(0 0% 10%) 3px)`;
}

export const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-page-bg))]";

function NavButton({ label, onClick, disabled, children }: { label: string; onClick: () => void; disabled: boolean; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
      className={cn(
        "rounded-full border border-black/20 bg-black/[0.06] p-1.5 text-black/70 transition-colors hover:bg-black/[0.12] hover:text-black/95 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-black/[0.06] disabled:hover:text-black/70 sm:p-2",
        "dark:border-white/15 dark:bg-white/5 dark:text-white/70 dark:hover:bg-white/10 dark:hover:text-white dark:disabled:opacity-30 dark:disabled:hover:bg-white/5 dark:disabled:hover:text-white/70",
        FOCUS_RING,
      )}
    >
      {children}
    </button>
  );
}

function NavIcon({ as: As }: { as: LucideIcon }) {
  return <As className="h-4 w-4" aria-hidden />;
}

/** « ‹ n / N › » — compacto, acima do fichário (spike `nav-controls.tsx`). */
export function TopNavControls({
  index,
  total,
  label,
  onFirst,
  onPrev,
  onNext,
  onLast,
}: {
  index: number;
  total: number;
  /** Texto acessível da vista atual ("Páginas 2–3 de 12"). */
  label: string;
  onFirst: () => void;
  onPrev: () => void;
  onNext: () => void;
  onLast: () => void;
}) {
  const atStart = index <= 1;
  const atEnd = index >= total;
  return (
    <div className="relative z-10 flex items-center justify-center gap-1.5 sm:gap-2">
      <NavButton label="Primeiras páginas (Home)" onClick={onFirst} disabled={atStart}>
        <NavIcon as={ChevronsLeft} />
      </NavButton>
      <NavButton label="Páginas anteriores (←)" onClick={onPrev} disabled={atStart}>
        <NavIcon as={ChevronLeft} />
      </NavButton>
      <span
        aria-live="polite"
        aria-atomic="true"
        aria-label={label}
        className="min-w-[64px] select-none rounded-full border border-black/20 bg-black/[0.06] px-3 py-1.5 text-center text-xs font-medium tabular-nums text-black/70 dark:border-white/10 dark:bg-white/5 dark:text-white/70 sm:min-w-[72px] sm:text-sm"
      >
        {index} / {total}
      </span>
      <NavButton label="Próximas páginas (→)" onClick={onNext} disabled={atEnd}>
        <NavIcon as={ChevronRight} />
      </NavButton>
      <NavButton label="Últimas páginas (End)" onClick={onLast} disabled={atEnd}>
        <NavIcon as={ChevronsRight} />
      </NavButton>
    </div>
  );
}

/**
 * Seta lateral redonda (spike). Também é alvo de soltura durante o arrasto:
 * parar sobre ela vira a página (navegação de borda do spike, ~650 ms).
 */
export function SideArrowButton({
  direction,
  onClick,
  disabled,
  dragActive,
}: {
  direction: "prev" | "next";
  onClick: () => void;
  disabled: boolean;
  dragActive: boolean;
}) {
  const isPrev = direction === "prev";
  const { setNodeRef, isOver } = useDroppable({ id: isPrev ? "edge:prev" : "edge:next", disabled });
  const hot = dragActive && isOver && !disabled;
  return (
    <button
      ref={setNodeRef}
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={isPrev ? "Páginas anteriores" : "Próximas páginas"}
      title={isPrev ? "Páginas anteriores (←)" : "Próximas páginas (→)"}
      className={cn(
        "flex-shrink-0 rounded-full border border-black/20 bg-white/75 p-1.5 text-black/70 backdrop-blur-sm transition-all hover:bg-black/10 hover:text-black/95 disabled:cursor-not-allowed disabled:opacity-35 disabled:hover:bg-white/75 disabled:hover:text-black/70 sm:p-2.5 md:p-3.5",
        "dark:border-white/15 dark:bg-black/30 dark:text-white/70 dark:hover:bg-white/10 dark:hover:text-white dark:disabled:opacity-20 dark:disabled:hover:bg-black/30 dark:disabled:hover:text-white/70",
        hot && "scale-110 border-[hsl(40_70%_55%)] bg-[hsl(40_70%_62%_/_0.22)] dark:border-[hsl(40_70%_62%)] dark:bg-[hsl(40_70%_62%_/_0.22)]",
        FOCUS_RING,
      )}
    >
      {isPrev ? (
        <ChevronLeft className="h-4 w-4 sm:h-5 sm:w-5 md:h-6 md:w-6" aria-hidden />
      ) : (
        <ChevronRight className="h-4 w-4 sm:h-5 sm:w-5 md:h-6 md:w-6" aria-hidden />
      )}
    </button>
  );
}

export function MmkyuWordmark({ size = "sm", tone }: { size?: "sm" | "md"; tone: string }) {
  return (
    <span
      aria-hidden
      className="font-semibold uppercase leading-none"
      style={{
        fontSize: size === "md" ? "1.05rem" : "0.62rem",
        letterSpacing: "0.28em",
        color: tone,
        textShadow: "0 1px 0 hsl(0 0% 100% / 0.06), 0 -1px 1px hsl(0 0% 0% / 0.55)",
      }}
    >
      MMKYU
    </span>
  );
}

/**
 * Logomarca MMKYU monocromática (P3-A, R8): o rosto do Mimikyu do asset
 * interno usado como MÁSCARA e pintado no tom da contracapa — sem fundo, sem
 * texto, sem asset novo. O canal alfa da versão clara preserva os traços dos
 * olhos (espirais vazadas), então o desenho continua legível em uma cor só.
 * O relevo (luz em cima, sombra embaixo) é o mesmo da antiga marca escrita.
 * Decorativa: `aria-hidden` — o nome do fichário é o que se lê.
 */
const BRAND_MARK_MASK = "url(/brand/icon-mark-light.png)";

export function BrandMark({ tone = "hsl(38 22% 62% / 0.5)", className }: { tone?: string; className?: string }) {
  return (
    <span aria-hidden className={cn("block", className)} style={{ filter: "drop-shadow(0 1px 0 hsl(0 0% 100% / 0.05)) drop-shadow(0 -1px 1px hsl(0 0% 0% / 0.55))" }}>
      <span
        className="block w-full"
        style={{
          aspectRatio: "546 / 309",
          backgroundColor: tone,
          WebkitMaskImage: BRAND_MARK_MASK,
          maskImage: BRAND_MARK_MASK,
          WebkitMaskSize: "contain",
          maskSize: "contain",
          WebkitMaskRepeat: "no-repeat",
          maskRepeat: "no-repeat",
          WebkitMaskPosition: "center",
          maskPosition: "center",
        }}
      />
    </span>
  );
}

/**
 * Contracapa interna: marca em baixo-relevo e, no rodapé, a identidade.
 *
 * Composição, tipografia, escala e posições são as da P2 (último commit
 * consolidado) — P3A-BINDER-BACK-COVER-VISUAL-CORRECTION-01. A P3-A muda só:
 *  - o texto do rodapé passa a ser o nome do fichário (mesmo tratamento do
 *    antigo nome da coleção);
 *  - sai o código da coleção ("MMKYU · SV1"); a assinatura é a própria marca
 *    "MMKYU / Collector" do centro, que continua igual;
 *  - entra o rosto monocromático do Mimikyu acima da marca, no mesmo tom e
 *    relevo dela, com o mínimo de espaço extra. Oculto, a contracapa fica
 *    idêntica à da P2 (salvo as mudanças de texto acima).
 */
export function InsideCoverFace({ name, showBrandMark }: { name: string; showBrandMark: boolean }) {
  return (
    <div aria-hidden className="flex h-full w-full flex-col items-center justify-between">
      <div className="flex flex-1 flex-col items-center justify-center gap-1.5 opacity-60">
        {showBrandMark ? <BrandMark tone="hsl(38 20% 55% / 0.55)" className="mb-0.5 w-9 sm:w-11" /> : null}
        <MmkyuWordmark size="md" tone="hsl(38 20% 55% / 0.55)" />
        <span className="text-[9px] font-medium uppercase tracking-[0.3em] sm:text-[10px]" style={{ color: "hsl(38 18% 50% / 0.4)" }}>
          Collector
        </span>
      </div>
      <div className="flex flex-col items-center gap-1 px-2 pb-2 text-center sm:pb-3">
        <span className="line-clamp-2 text-xs font-medium tracking-wide" style={{ color: "hsl(38 22% 70% / 0.55)" }}>
          {name}
        </span>
      </div>
    </div>
  );
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
 *
 * Revisão P3-A (CORRECTION-01): a contracapa é REBAIXADA na moldura de couro.
 * Ver a nota em `boxShadow` — sombra para dentro no alto/esquerda, fio de luz
 * embaixo/direita, e sem sombra projetada (camada 2 × 3 px removida só para a
 * contracapa em `binder-workspace.tsx`).
 */
export function insideCoverSurface(position: "left" | "right" | "single"): React.CSSProperties {
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
    // P3-A-BINDER-CONTROL-IDENTITY-CORRECTION-01 — baixo relevo: com a luz do
    // alto à esquerda, a moldura (mais alta) faz sombra para DENTRO no alto e à
    // esquerda; a borda de baixo e da direita recebe só um fio de luz. Antes
    // era o inverso (fio de luz em cima/esquerda + sombra embaixo/direita), a
    // leitura de almofada saliente. Textura (background) intocada.
    boxShadow: [
      // sombra da moldura caindo sobre o fundo rebaixado (alto e esquerda)
      "inset 0 1px 0 hsl(0 0% 0% / 0.55)",
      "inset 0 9px 12px -8px hsl(0 0% 0% / 0.6)",
      position === "right" ? null : "inset 1px 0 0 hsl(0 0% 0% / 0.45)",
      position === "right" ? null : "inset 9px 0 12px -8px hsl(0 0% 0% / 0.5)",
      // fio de luz muito sutil na parede oposta (baixo e direita)
      "inset 0 -1px 0 hsl(38 30% 85% / 0.05)",
      position === "left" ? null : "inset -1px 0 0 hsl(38 30% 85% / 0.04)",
      gutter,
    ]
      .filter(Boolean)
      .join(", "),
  };
}
