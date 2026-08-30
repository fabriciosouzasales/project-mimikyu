"use client";

import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import { Inbox, Lock, LockOpen, Trash2, X, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * BINDER-MULTISELECT-RAIL-01 (2026-08-29) — substitui a `BulkActionBar`
 * horizontal (`bulk-action-bar.tsx`, BINDER-MULTISELECT-BULK-01/UX-01) por
 * um "action rail" vertical flutuante, pedido explícito de Fabrício:
 * "eliminar a linha horizontal de ações em lote que aparece acima do
 * Binder... evitar layout shift, deslocamento do Binder e corte das
 * setas/paginação." `bulk-action-bar.tsx` fica no repositório (histórico),
 * mas sai do fluxo — `binder-pages-nav.tsx` não a importa mais.
 *
 * Mesma lógica funcional de sempre, ZERO reimplementação de regra de
 * negócio — todos os handlers (`onMoveToTray`/`onLock`/`onUnlock`/
 * `onRemove`/`onClear`) e o cálculo de `showLock`/`showUnlock`
 * (`bulkLockState.allLocked`/`allUnlocked`) continuam vindo de
 * `binder-pages-nav.tsx` exatamente como antes; só a APRESENTAÇÃO mudou de
 * uma barra horizontal com rótulos de texto para uma cápsula vertical só
 * de ícones + tooltip.
 *
 * TOOLTIPS — pedido explícito: "hover/focus para todos os ícones" (essa
 * exigência importa mais aqui do que na barra anterior, que tinha rótulo
 * de texto ao lado de cada ícone; um rail só-ícone SEM tooltip acessível
 * por teclado seria pior a11y que antes). `title` nativo do HTML NÃO
 * dispara de forma confiável em foco de teclado (só hover, na maioria dos
 * navegadores) — por isso uso `@radix-ui/react-tooltip` diretamente (já
 * instalado no projeto, usado por `components/ui/tooltip.tsx`), que cobre
 * hover E focus nativamente, fecha com Esc, e não precisa de nenhuma
 * dependência nova. NÃO reaproveito o wrapper pré-estilizado de
 * `components/ui/tooltip.tsx` (`TooltipContent`) porque ele usa os tokens
 * CLAROS do app principal (`bg-surface`/`text-foreground`/`shadow-panel`)
 * — incoerente com a estética sempre-escura do Binder (mesmo racional já
 * aplicado a `slot-quick-actions.tsx`/`binder-tray.tsx`: este experimental
 * usa seus próprios tokens hsl() hardcoded, não os do design system
 * principal). Uso os primitivos do Radix crus, com estilo dark próprio.
 *
 * POSICIONAMENTO — v1 (BINDER-MULTISELECT-RAIL-01) renderizava o rail
 * DENTRO da moldura de couro (`rootRef`, absolute); BINDER-BULK-ACTION-
 * RAIL-POSITION-01 (2026-08-29) moveu para FORA dela, pedido explícito de
 * Fabrício após aprovar o conceito/visual: "continuar claramente
 * contextual ao Binder, mas não parecer parte da capa/página física". A
 * posição real (absolute, `right-[calc(100%_+_Npx)]`, `inset-y-0 flex
 * items-center`, sem nenhuma referência a viewport) vive em
 * `binder-pages-nav.tsx`, num wrapper `relative` que envolve a moldura e o
 * rail como irmãos — ver doc-comment completo lá. Este arquivo só desenha
 * o CONTEÚDO da cápsula, sem saber nada sobre onde é posicionado.
 *
 * `statusMessage` (resultado textual da última Bulk Action, ex.: "3
 * movidas para a Bandeja. 1 não movida — slot bloqueado.") deixou de ter
 * um lugar visível na cápsula compacta (rail vertical de ~40px de largura
 * não comporta uma frase) — continua sendo anunciado para leitor de tela
 * via `aria-live="polite"` (elemento `sr-only`), preservando a a11y sem
 * adicionar densidade visual. Sighted users veem o RESULTADO da ação
 * diretamente no Binder (cartas somem/aparecem na Bandeja/ficam
 * bloqueadas) — o texto era um reforço, não a única fonte de informação.
 */

const RAIL_BG = "hsl(0 0% 6% / 0.94)";
const RAIL_BORDER = "hsl(0 0% 100% / 0.1)";

function RailSeparator() {
  return <div className="h-px w-5 flex-shrink-0" style={{ background: "hsl(0 0% 100% / 0.12)" }} aria-hidden />;
}

function RailButton({
  icon: Icon,
  label,
  onClick,
  tone = "neutral",
}: {
  icon: LucideIcon;
  label: string;
  onClick: () => void;
  tone?: "neutral" | "lock" | "destructive";
}) {
  return (
    <TooltipPrimitive.Root>
      <TooltipPrimitive.Trigger asChild>
        <button
          type="button"
          onClick={onClick}
          aria-label={label}
          className={cn(
            "flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full transition-colors active:scale-90",
            "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-[hsl(0_0%_6%)]",
            tone === "lock"
              ? "text-[hsl(205_80%_75%)] hover:bg-[hsl(205_70%_58%_/_0.22)]"
              : tone === "destructive"
                ? "text-red-400/90 hover:bg-red-500/15 hover:text-red-400"
                : "text-white/75 hover:bg-white/12 hover:text-white",
          )}
        >
          <Icon className="h-4 w-4" aria-hidden />
        </button>
      </TooltipPrimitive.Trigger>
      <TooltipPrimitive.Portal>
        <TooltipPrimitive.Content
          side="right"
          sideOffset={10}
          className="z-[85] select-none rounded-md px-2.5 py-1.5 text-xs font-medium text-white/90"
          style={{ background: RAIL_BG, boxShadow: `0 6px 16px -4px rgba(0,0,0,0.6), 0 0 0 1px ${RAIL_BORDER}` }}
        >
          {label}
          <TooltipPrimitive.Arrow style={{ fill: RAIL_BG }} />
        </TooltipPrimitive.Content>
      </TooltipPrimitive.Portal>
    </TooltipPrimitive.Root>
  );
}

export function BulkActionRail({
  count,
  statusMessage,
  showLock,
  showUnlock,
  onMoveToTray,
  onLock,
  onUnlock,
  onRemove,
  onClear,
}: {
  count: number;
  statusMessage: string | null;
  /** BINDER-MULTISELECT-BULK-02 — "Bloquear" só aparece se ALGUM selecionado ainda não está bloqueado. */
  showLock: boolean;
  /** BINDER-MULTISELECT-BULK-02 — "Desbloquear" só aparece se ALGUM selecionado está bloqueado. */
  showUnlock: boolean;
  onMoveToTray: () => void;
  onLock: () => void;
  onUnlock: () => void;
  onRemove: () => void;
  onClear: () => void;
}) {
  return (
    <TooltipPrimitive.Provider delayDuration={200} skipDelayDuration={100}>
      <div
        role="toolbar"
        aria-label="Ações em lote"
        aria-orientation="vertical"
        className="pointer-events-auto flex flex-col items-center gap-1 rounded-full px-1.5 py-2.5"
        style={{
          background: RAIL_BG,
          boxShadow: `0 12px 28px -8px rgba(0,0,0,0.65), inset 0 1px 0 hsl(0 0% 100% / 0.08), 0 0 0 1px ${RAIL_BORDER}`,
          backdropFilter: "blur(6px)",
        }}
      >
        {/* Contador — topo da cápsula, pedido explícito ("contador de itens
            selecionados no topo, ex.: 3"). Accent dourado moderado, mesmo
            vocabulário já usado para seleção em todo o Binder — não é um
            botão/CTA. */}
        <span
          aria-hidden
          className="flex h-6 w-6 flex-shrink-0 select-none items-center justify-center rounded-full text-[11px] font-semibold tabular-nums"
          style={{ background: "hsl(40 70% 62% / 0.22)", color: "hsl(40 80% 82%)" }}
        >
          {count}
        </span>
        <span aria-live="polite" aria-atomic="true" className="sr-only">
          {count} {count === 1 ? "selecionada" : "selecionadas"}
          {statusMessage ? `. ${statusMessage}` : ""}
        </span>

        <RailSeparator />

        <RailButton icon={Inbox} label="Mover para a Bandeja" onClick={onMoveToTray} />
        {showLock && <RailButton icon={Lock} label="Bloquear" onClick={onLock} tone="lock" />}
        {showUnlock && <RailButton icon={LockOpen} label="Desbloquear" onClick={onUnlock} tone="lock" />}

        {/* Separador antes da ação destrutiva — pedido explícito. */}
        <RailSeparator />

        <RailButton icon={Trash2} label="Remover" onClick={onRemove} tone="destructive" />
        <RailButton icon={X} label="Limpar seleção" onClick={onClear} />
      </div>
    </TooltipPrimitive.Provider>
  );
}
