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
 *
 * LIGHT/DARK (2026-08-29) — diferente do resto do OBJETO Binder (que
 * continua escuro nos dois temas), estes controles sentam DIRETAMENTE sobre
 * o fundo do workspace (`binder-nav-view.tsx`), fora da moldura de couro —
 * por isso precisam de tratamento real por tema: o padrão "branco
 * translúcido sobre fundo escuro" (`bg-white/5 text-white/70`) ficaria quase
 * invisível/ilegível sobre um workspace claro. Ganharam pares `dark:`
 * explícitos (claro = tinta escura translúcida sobre o off-white do
 * workspace; escuro = valores originais, inalterados). O `ring-offset` do
 * foco usa `--binder-page-bg` (ver `globals.css`) para acompanhar o fundo
 * real em qualquer tema, em vez de um tom escuro fixo.
 *
 * POLISH LIGHT MODE (2026-08-29, rodada 2) — pedido de Fabrício: aumentar
 * levemente o contraste dos controles no claro (nav superior, setas
 * laterais, disabled/focus/hover), mantendo "disabled" perceptível em vez de
 * quase invisível. Ajuste ESCOPADO ao claro — todo valor `dark:` abaixo
 * permanece idêntico ao da Rodada 1.
 */

const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-page-bg))]";

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
        "rounded-full border border-black/20 bg-black/[0.06] text-black/70 transition-colors hover:bg-black/[0.12] hover:text-black/95 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-black/[0.06] disabled:hover:text-black/70",
        "dark:border-white/15 dark:bg-white/5 dark:text-white/70 dark:hover:bg-white/10 dark:hover:text-white dark:disabled:opacity-30 dark:disabled:hover:bg-white/5 dark:disabled:hover:text-white/70",
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
        className="min-w-[64px] select-none rounded-full border border-black/20 bg-black/[0.06] px-3 py-1.5 text-center text-xs font-medium tabular-nums text-black/70 dark:border-white/10 dark:bg-white/5 dark:text-white/70 sm:min-w-[72px] sm:text-sm"
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
        "flex-shrink-0 rounded-full border border-black/20 bg-white/75 text-black/70 backdrop-blur-sm transition-colors hover:bg-black/10 hover:text-black/95 disabled:cursor-not-allowed disabled:opacity-35 disabled:hover:bg-white/75 disabled:hover:text-black/70",
        "dark:border-white/15 dark:bg-black/30 dark:text-white/70 dark:hover:bg-white/10 dark:hover:text-white dark:disabled:opacity-20 dark:disabled:hover:bg-black/30 dark:disabled:hover:text-white/70",
        "p-1.5 sm:p-2.5 md:p-3.5",
        FOCUS_RING,
      )}
    >
      <Icon as={isPrev ? ChevronLeft : ChevronRight} size="lg" />
    </button>
  );
}
