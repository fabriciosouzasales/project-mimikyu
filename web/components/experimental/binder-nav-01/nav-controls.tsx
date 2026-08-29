import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Controles de navegação explícita do BINDER-NAV-01 (pedido de Fabrício,
 * 2026-08-28 — baseline operacional pós-encerramento dos experimentos de
 * page-turn físico; setas laterais ajustadas na Rodada 2, mesma data).
 * Dois conjuntos, mesma lógica de estado do pai (`binder-nav-view.tsx`):
 *  - `TopNavControls`: barra central no topo (« ‹ indicador › »).
 *  - `SideArrowButton`: atalho adicional, maior — o pai posiciona uma
 *    instância de cada lado (`direction="prev"|"next"`) como IRMà de flex
 *    fora da moldura do Binder (não mais overlay absoluto por cima das
 *    páginas — pedido explícito da Rodada 2: "mova as setas para fora das
 *    bordas externas do Binder... não sobrepor páginas/cartas"), alinhada
 *    verticalmente ao centro via `items-center` no container flex pai, e
 *    encolhendo em viewports menores (padding/ícone responsivos) em vez de
 *    ficar fixa e invadir a área de cartas. Sempre visível/tocável (nunca
 *    escondida até hover, para funcionar bem em touch).
 *
 * O indicador `N / total` é um `<span>`, não um `<button>` — item 8 do
 * pedido: precisa estar PREPARADO para um salto direto futuro (mesma
 * posição/tamanho de um controle), mas seletor/thumbnail não entra nesta
 * rodada, então não é interativo ainda.
 */

const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(30_20%_7%)]";

function NavButton({
  label,
  title,
  onClick,
  disabled,
  size = "md",
  children,
}: {
  label: string;
  title: string;
  onClick: () => void;
  disabled: boolean;
  size?: "md" | "lg";
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={title}
      className={cn(
        "rounded-full border border-white/15 bg-white/5 text-white/70 transition-colors hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-white/5 disabled:hover:text-white/70",
        size === "md" ? "p-1.5 sm:p-2" : "p-2.5 sm:p-3.5",
        FOCUS_RING,
      )}
    >
      {children}
    </button>
  );
}

function Icon({ as: As, size }: { as: LucideIcon; size: "md" | "lg" }) {
  return <As className={size === "md" ? "h-4 w-4" : "h-4 w-4 sm:h-5 sm:w-5 md:h-6 md:w-6"} aria-hidden />;
}

export function TopNavControls({
  index,
  total,
  onFirst,
  onPrev,
  onNext,
  onLast,
}: {
  index: number;
  total: number;
  onFirst: () => void;
  onPrev: () => void;
  onNext: () => void;
  onLast: () => void;
}) {
  const atStart = index <= 0;
  const atEnd = index >= total - 1;

  return (
    <div className="relative z-10 flex items-center justify-center gap-1.5 px-4 sm:gap-2">
      <NavButton label="Primeiro spread" title="Primeiro spread (Home)" onClick={onFirst} disabled={atStart}>
        <Icon as={ChevronsLeft} size="md" />
      </NavButton>
      <NavButton label="Spread anterior" title="Spread anterior (←)" onClick={onPrev} disabled={atStart}>
        <Icon as={ChevronLeft} size="md" />
      </NavButton>

      {/* Indicador — preparado para salto direto futuro, mas não interativo nesta rodada (item 8). */}
      <span
        aria-live="polite"
        aria-atomic="true"
        className="min-w-[64px] select-none rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-center text-xs font-medium tabular-nums text-white/70 sm:min-w-[72px] sm:text-sm"
      >
        {index + 1} / {total}
      </span>

      <NavButton label="Próximo spread" title="Próximo spread (→)" onClick={onNext} disabled={atEnd}>
        <Icon as={ChevronRight} size="md" />
      </NavButton>
      <NavButton label="Último spread" title="Último spread (End)" onClick={onLast} disabled={atEnd}>
        <Icon as={ChevronsRight} size="md" />
      </NavButton>
    </div>
  );
}

export function SideArrowButton({
  direction,
  onClick,
  disabled,
}: {
  direction: "prev" | "next";
  onClick: () => void;
  disabled: boolean;
}) {
  const isPrev = direction === "prev";
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={isPrev ? "Spread anterior" : "Próximo spread"}
      title={isPrev ? "Spread anterior (←)" : "Próximo spread (→)"}
      className={cn(
        "flex-shrink-0 rounded-full border border-white/15 bg-black/30 text-white/70 backdrop-blur-sm transition-colors hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-20 disabled:hover:bg-black/30 disabled:hover:text-white/70",
        "p-1.5 sm:p-2.5 md:p-3.5",
        FOCUS_RING,
      )}
    >
      <Icon as={isPrev ? ChevronLeft : ChevronRight} size="lg" />
    </button>
  );
}
