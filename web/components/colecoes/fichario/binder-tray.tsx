"use client";

import { forwardRef, useCallback } from "react";
import { useDraggable, useDroppable } from "@dnd-kit/core";
import { ArrowDown, Inbox, Lock, LockOpen, Trash2, Undo2, X, type LucideIcon } from "lucide-react";
import { cardFrontUrl } from "@/lib/colecoes/acervo";
import { cn } from "@/lib/utils";
import { FOCUS_RING } from "./binder-chrome";
import type { SlotDragData } from "./binder-slot";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const DARK_RING = "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/80";

export const TRAY_DROP_ID = "tray";

export type TrayItem = { slotId: string; page: number; name: string; imagePath: string | null };

/**
 * Bandeja — recuperada do spike `binder-nav-01/binder-tray.tsx`: botão em
 * pílula abaixo do fichário (vira "↓ Bandeja" durante o arrasto e é alvo de
 * soltura) e superfície flutuante escura com as cartas em espera.
 *
 * Semântica real (C-45/LDM-36): a Bandeja é estado da tela. A carta continua
 * no bolso de origem (marcada "Na Bandeja") até ser solta num bolso; colocar
 * é UM mover/trocar no banco. "Devolver" só a tira da Bandeja, sem gravar.
 */
export const TrayToggleButton = forwardRef<HTMLButtonElement, { count: number; open: boolean; dragActive: boolean; disabled: boolean; onToggle: () => void }>(
  function TrayToggleButton({ count, open, dragActive, disabled, onToggle }, forwardedRef) {
    const { setNodeRef, isOver } = useDroppable({ id: TRAY_DROP_ID, disabled });
    const setRefs = useCallback(
      (node: HTMLButtonElement | null) => {
        setNodeRef(node);
        if (typeof forwardedRef === "function") forwardedRef(node);
        else if (forwardedRef) forwardedRef.current = node;
      },
      [setNodeRef, forwardedRef],
    );
    return (
      <button
        ref={setRefs}
        type="button"
        onClick={onToggle}
        aria-haspopup="true"
        aria-expanded={open}
        aria-label={count > 0 ? `Bandeja, ${count} ${count === 1 ? "carta" : "cartas"}` : "Bandeja, vazia"}
        title={dragActive ? "Solte aqui para levar a carta à Bandeja" : "Bandeja — espera temporária para reorganizar o fichário"}
        className={cn(
          "relative z-30 flex flex-shrink-0 items-center gap-1.5 rounded-full border font-medium transition-all",
          "text-black/75 hover:text-black/95 dark:text-white/80 dark:hover:text-white",
          dragActive ? "px-4 py-2 text-xs sm:px-5 sm:py-2.5 sm:text-sm" : "px-3 py-1.5 text-xs sm:px-3.5 sm:py-2 sm:text-sm",
          isOver
            ? "border-[hsl(40_70%_50%_/_0.85)] bg-[hsl(40_70%_55%_/_0.16)] text-[hsl(32_75%_30%)] shadow-[0_4px_14px_-4px_rgba(0,0,0,0.35)] dark:border-[hsl(40_70%_62%_/_0.75)] dark:bg-[hsl(40_70%_62%_/_0.22)] dark:text-[hsl(40_80%_82%)]"
            : dragActive
              ? "border-[hsl(40_60%_50%_/_0.5)] bg-black/[0.1] shadow-[0_4px_14px_-4px_rgba(0,0,0,0.3)] dark:border-[hsl(40_60%_62%_/_0.4)] dark:bg-white/10"
              : "border-black/25 bg-black/[0.08] hover:border-[hsl(40_50%_45%_/_0.4)] hover:bg-black/[0.14] dark:border-white/20 dark:bg-white/10 dark:hover:border-[hsl(40_60%_62%_/_0.4)] dark:hover:bg-white/[0.16]",
          FOCUS_RING,
        )}
      >
        {dragActive ? (
          <>
            <ArrowDown className="h-4 w-4" aria-hidden />
            {isOver ? "Soltar na Bandeja" : "Bandeja"}
          </>
        ) : (
          <>
            <Inbox className="h-3.5 w-3.5 sm:h-4 sm:w-4" aria-hidden />
            Bandeja
            {count > 0 ? (
              <span className="ml-0.5 inline-flex h-4 min-w-[16px] flex-shrink-0 items-center justify-center rounded-full bg-[hsl(38_65%_45%_/_0.18)] px-1 text-[10px] font-semibold tabular-nums text-[hsl(30_75%_28%)] dark:bg-[hsl(40_70%_62%_/_0.22)] dark:text-[hsl(40_80%_80%)] sm:h-[18px] sm:min-w-[18px] sm:text-[11px]">
                {count}
              </span>
            ) : null}
          </>
        )}
      </button>
    );
  },
);

/** Superfície flutuante da Bandeja (não modal: o fichário continua utilizável). */
export function TraySurface({
  items,
  armed,
  onArm,
  onReturn,
  onClose,
}: {
  items: TrayItem[];
  armed: string | null;
  onArm: (slotId: string) => void;
  onReturn: (slotId: string) => void;
  onClose: () => void;
}) {
  return (
    <div
      role="region"
      aria-label="Bandeja — cartas esperando um novo bolso"
      className="absolute bottom-[calc(100%+10px)] left-1/2 z-[70] w-[min(300px,calc(100vw-24px))] -translate-x-1/2 rounded-[14px] p-3"
      style={{
        background: "hsl(0 0% 6% / 0.96)",
        boxShadow: ["0 20px 40px -10px rgba(0,0,0,0.7)", "inset 0 1px 0 hsl(0 0% 100% / 0.08)", "0 0 0 1px hsl(0 0% 100% / 0.08)"].join(", "),
      }}
    >
      <div className="mb-2 flex items-center justify-between">
        <span className="text-[11px] font-medium uppercase tracking-wide text-white/50">Bandeja{items.length > 0 ? ` · ${items.length}` : ""}</span>
        <button type="button" onClick={onClose} aria-label="Fechar Bandeja" className={cn("rounded-full p-1 text-white/50 transition-colors hover:bg-white/10 hover:text-white", DARK_RING)}>
          <X className="h-3.5 w-3.5" aria-hidden />
        </button>
      </div>
      {items.length === 0 ? (
        <p className="py-3 text-center text-[11px] leading-relaxed text-white/45">
          Arraste uma carta até o botão &quot;Bandeja&quot; para levá-la a outra página. Nada muda até você soltá-la num bolso.
        </p>
      ) : (
        <>
          <ul className="flex max-h-[45vh] flex-wrap justify-center gap-2 overflow-y-auto p-1">
            {items.map((item) => (
              <TrayCard key={item.slotId} item={item} armed={armed === item.slotId} onArm={onArm} onReturn={onReturn} />
            ))}
          </ul>
          <p className="mt-2 text-center text-[10px] leading-relaxed text-white/40">
            Arraste para um bolso, ou toque na carta e depois no bolso de destino.
          </p>
        </>
      )}
    </div>
  );
}

function TrayCard({ item, armed, onArm, onReturn }: { item: TrayItem; armed: boolean; onArm: (slotId: string) => void; onReturn: (slotId: string) => void }) {
  const { setNodeRef, listeners, isDragging } = useDraggable({ id: `tray:${item.slotId}`, data: { kind: "tray", slotId: item.slotId } satisfies SlotDragData });
  const src = cardFrontUrl(SUPABASE_URL, item.imagePath);
  return (
    <li className="relative">
      <button
        ref={setNodeRef}
        type="button"
        aria-pressed={armed}
        aria-label={`${item.name}, da página ${item.page}. ${armed ? "Escolhida: toque no bolso de destino." : "Escolher para colocar num bolso."}`}
        title={item.name}
        onClick={() => onArm(item.slotId)}
        className={cn(
          "flex aspect-[8/11] w-14 flex-shrink-0 cursor-grab touch-none overflow-hidden rounded-[4px] transition-transform active:cursor-grabbing sm:w-16",
          armed && "-translate-y-1",
          DARK_RING,
        )}
        style={{
          opacity: isDragging ? 0.35 : 1,
          boxShadow: armed
            ? "0 0 0 2px hsl(40 70% 62% / 0.95), 0 6px 12px -4px rgba(0,0,0,0.6)"
            : "0 0 0 1px hsl(0 0% 100% / 0.14), 0 2px 6px rgba(0,0,0,0.4)",
        }}
        {...listeners}
      >
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- mesmo asset do bolso (cache)
          <img src={src} alt="" className="h-full w-full object-cover" loading="lazy" draggable={false} />
        ) : (
          <span className="flex h-full w-full items-end bg-white/10 p-1 text-[9px] font-semibold leading-tight text-white/80">{item.name}</span>
        )}
      </button>
      <button
        type="button"
        onClick={() => onReturn(item.slotId)}
        aria-label={`Devolver ${item.name} ao bolso de origem`}
        title="Devolver ao bolso de origem"
        className={cn("absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-black text-white/70 ring-1 ring-white/20 hover:text-white", DARK_RING)}
      >
        <Undo2 className="h-3 w-3" aria-hidden />
      </button>
    </li>
  );
}

const RAIL_BG = "hsl(0 0% 6% / 0.94)";
const RAIL_BORDER = "hsl(0 0% 100% / 0.1)";

function RailButton({ icon: Icon, label, onClick, tone = "neutral", disabled = false }: { icon: LucideIcon; label: string; onClick: () => void; tone?: "neutral" | "lock" | "destructive"; disabled?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
      className={cn(
        "group/rail relative flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full transition-colors active:scale-90",
        disabled
          ? "cursor-not-allowed text-white/25"
          : tone === "lock"
            ? "text-[hsl(205_80%_75%)] hover:bg-[hsl(205_70%_58%_/_0.22)]"
            : tone === "destructive"
              ? "text-red-400/90 hover:bg-red-500/15 hover:text-red-400"
              : "text-white/75 hover:bg-white/12 hover:text-white",
        DARK_RING,
      )}
    >
      <Icon className="h-4 w-4" aria-hidden />
      <span
        aria-hidden
        className="pointer-events-none absolute bottom-[calc(100%+10px)] left-1/2 z-[85] hidden -translate-x-1/2 whitespace-nowrap rounded-md px-2.5 py-1.5 text-xs font-medium text-white/90 opacity-0 transition-opacity group-hover/rail:opacity-100 group-focus-visible/rail:opacity-100 md:block"
        style={{ background: RAIL_BG, boxShadow: `0 6px 16px -4px rgba(0,0,0,0.6), 0 0 0 1px ${RAIL_BORDER}` }}
      >
        {label}
      </span>
    </button>
  );
}

/**
 * Barra contextual da seleção — spike `bulk-action-bar.tsx`/`bulk-action-rail.tsx`:
 * cápsula escura com o contador, Bandeja, fixar/soltar (contextual) e,
 * isolado por um separador, tirar do fichário; por fim limpar a seleção.
 * Só aparece com seleção ativa, na faixa inferior, ao lado da Bandeja;
 * coexiste com o menu lateral permanente (`binder-tool-rail.tsx`).
 * Todas com contrato (5130, 5133; Bandeja = estado da tela).
 */
export function BulkActionRail({
  count,
  canTray,
  showLock,
  showUnlock,
  canRemove,
  busy,
  onMoveToTray,
  onLock,
  onUnlock,
  onRemove,
  onClear,
}: {
  count: number;
  canTray: boolean;
  showLock: boolean;
  showUnlock: boolean;
  canRemove: boolean;
  busy: boolean;
  onMoveToTray: () => void;
  onLock: () => void;
  onUnlock: () => void;
  onRemove: () => void;
  onClear: () => void;
}) {
  return (
    <div
      role="toolbar"
      aria-label={`Ações para ${count} ${count === 1 ? "carta selecionada" : "cartas selecionadas"}`}
      className="pointer-events-auto flex items-center gap-1 rounded-full px-2 py-1"
      style={{ background: RAIL_BG, boxShadow: `0 12px 28px -8px rgba(0,0,0,0.65), inset 0 1px 0 hsl(0 0% 100% / 0.08), 0 0 0 1px ${RAIL_BORDER}` }}
    >
      <span
        aria-hidden
        className="flex h-6 w-6 flex-shrink-0 select-none items-center justify-center rounded-full text-[11px] font-semibold tabular-nums"
        style={{ background: "hsl(40 70% 62% / 0.22)", color: "hsl(40 80% 82%)" }}
      >
        {count}
      </span>
      <span className="mx-0.5 h-5 w-px flex-shrink-0" style={{ background: "hsl(0 0% 100% / 0.12)" }} aria-hidden />
      <RailButton icon={Inbox} label="Levar para a Bandeja" onClick={onMoveToTray} disabled={!canTray} />
      {showLock ? <RailButton icon={Lock} label="Fixar bolsos" onClick={onLock} tone="lock" disabled={busy} /> : null}
      {showUnlock ? <RailButton icon={LockOpen} label="Soltar bolsos" onClick={onUnlock} tone="lock" disabled={busy} /> : null}
      <span className="mx-0.5 h-5 w-px flex-shrink-0" style={{ background: "hsl(0 0% 100% / 0.12)" }} aria-hidden />
      <RailButton icon={Trash2} label="Tirar do fichário" onClick={onRemove} tone="destructive" disabled={!canRemove || busy} />
      <RailButton icon={X} label="Limpar seleção (Esc)" onClick={onClear} />
    </div>
  );
}
