"use client";

import { useDroppable } from "@dnd-kit/core";
import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
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
  return [
    "repeating-linear-gradient(115deg, hsl(0 0% 100% / 0.025) 0px, hsl(0 0% 100% / 0.025) 1px, transparent 1px, transparent 2.5px)",
    "repeating-linear-gradient(25deg, hsl(0 0% 0% / 0.05) 0px, hsl(0 0% 0% / 0.05) 1px, transparent 1px, transparent 3px)",
    "linear-gradient(125deg, hsl(0 0% 100% / 0.05) 0%, transparent 26%)",
    `linear-gradient(155deg, hsl(${BLACK_HUE} 6% 13%) 0%, hsl(${BLACK_HUE} 5% 8%) 55%, hsl(${BLACK_HUE} 6% 4%) 100%)`,
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

/** Contracapa interna: marca em baixo-relevo e, no rodapé, a identidade da coleção. */
export function InsideCoverFace({ title, subtitle }: { title: string; subtitle: string | null }) {
  return (
    <div aria-hidden className="flex h-full w-full flex-col items-center justify-between">
      <div className="flex flex-1 flex-col items-center justify-center gap-1.5 opacity-60">
        <MmkyuWordmark size="md" tone="hsl(38 20% 55% / 0.55)" />
        <span className="text-[9px] font-medium uppercase tracking-[0.3em] sm:text-[10px]" style={{ color: "hsl(38 18% 50% / 0.4)" }}>
          Collector
        </span>
      </div>
      <div className="flex flex-col items-center gap-1 px-2 pb-2 text-center sm:pb-3">
        <span className="line-clamp-2 text-xs font-medium tracking-wide" style={{ color: "hsl(38 22% 70% / 0.55)" }}>
          {title}
        </span>
        {subtitle ? (
          <span className="text-[9px] uppercase tracking-[0.2em]" style={{ color: "hsl(38 18% 60% / 0.35)" }}>
            {subtitle}
          </span>
        ) : null}
      </div>
    </div>
  );
}
