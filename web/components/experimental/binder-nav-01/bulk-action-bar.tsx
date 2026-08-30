import { Inbox, Lock, LockOpen, Trash2, X } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * BINDER-MULTISELECT-BULK-01 (2026-08-29) — Bulk Action Bar, pedido
 * explícito de Fabrício: "mostrada só quando `selectedCount > 0`... nunca
 * uma barra permanente sem seleção." Componente novo, isolado em
 * `binder-nav-01/` (mesmo padrão de isolamento do resto do experimental) —
 * sem dependência nova, só `lucide-react` (já usado em todo o resto da
 * rota).
 *
 * Renderizado condicionalmente por `binder-pages-nav.tsx` (só quando
 * `multiSelectedSlotIds.size > 0`) e portalado para uma faixa dedicada em
 * `binder-nav-view.tsx` — mesmo racional de posicionamento já usado para
 * `TrayToggleButton` (`binder-tray.tsx`): logicamente dentro da árvore de
 * `BinderPagesNav` (acesso direto a `multiSelectedSlotIds`/
 * `lockedSlotIds`/etc.), só a localização no DOM muda via `createPortal`.
 *
 * BINDER-MULTISELECT-UX-01 (2026-08-29) — posição MOVIDA: ficava abaixo do
 * Binder (BULK-01), "perdia hierarquia visual" ali; agora fica ACIMA do
 * Binder, imediatamente após a paginação — mesmo wrapper com `maxWidth` do
 * Binder ("não virar toolbar global"), associada visualmente a ele sem se
 * misturar com a paginação. A Bandeja permanente CONTINUA abaixo do Binder,
 * intocada (não fazia parte deste pedido).
 *
 * LIGHT/DARK — mesmo padrão dual-token já estabelecido por
 * `nav-controls.tsx`/`binder-tray.tsx` (`TOGGLE_FOCUS_RING`): este
 * componente senta DIRETAMENTE sobre o fundo do workspace, fora da moldura
 * de couro sempre-escura do Binder, então precisa de pares `dark:`
 * explícitos em vez do "branco translúcido sobre fundo escuro" fixo usado
 * dentro do Binder.
 *
 * Cores das ações — reaproveitam exatamente o vocabulário já estabelecido
 * em `slot-quick-actions.tsx`: Bandeja neutro (mesma família de
 * `TrayToggleButton`), Bloquear/Desbloquear em azul-frio (mesmo tom do
 * selo de Lock), Remover em vermelho só no hover/foco (ação destrutiva
 * secundária, nunca vermelho em repouso — mesma regra do Quick Action
 * "Remover do slot"). "Limpar seleção" é neutro/terciário, ação de saída,
 * não de transformação.
 *
 * `statusMessage` (opcional) — resultado textual da última Bulk Action
 * (ex.: "3 movidas para a Bandeja. 1 não movida — slot bloqueado."),
 * definido por `announceBulkStatus` em `binder-pages-nav.tsx`. Sem sistema
 * de toast novo (nenhuma dependência nova permitida nesta rodada): a
 * própria barra exibe o resultado por alguns segundos, dentro do MESMO
 * `aria-live="polite"` que também serve leitores de tela — cobre visão e
 * a11y com um único elemento.
 *
 * BINDER-MULTISELECT-BULK-02 (2026-08-29) — `showLock`/`showUnlock`
 * (calculados em `binder-pages-nav.tsx`, `bulkLockState`): "Bloquear" some
 * quando TODOS os selecionados já estão bloqueados, "Desbloquear" some
 * quando TODOS já estão desbloqueados; numa seleção mista, os dois
 * continuam visíveis (regra V1, sem dropdown/menu novo) — evita oferecer
 * uma ação que não faria nada em nenhum dos selecionados.
 */

const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-page-bg))]";

function BarButton({
  icon: Icon,
  label,
  onClick,
  tone = "neutral",
}: {
  icon: typeof Inbox;
  label: string;
  onClick: () => void;
  tone?: "neutral" | "lock" | "destructive";
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        "flex flex-shrink-0 items-center gap-1 rounded-full border px-2 py-1 text-[10px] font-medium transition-colors sm:px-2.5 sm:py-1.5 sm:text-xs",
        tone === "lock"
          ? "border-[hsl(205_60%_50%_/_0.35)] bg-[hsl(205_60%_50%_/_0.1)] text-[hsl(205_70%_35%)] hover:bg-[hsl(205_60%_50%_/_0.18)] dark:border-[hsl(205_60%_58%_/_0.4)] dark:bg-[hsl(205_60%_58%_/_0.14)] dark:text-[hsl(205_80%_78%)] dark:hover:bg-[hsl(205_60%_58%_/_0.22)]"
          : tone === "destructive"
            ? "border-black/20 bg-black/[0.06] text-black/70 hover:border-red-400/50 hover:bg-red-500/10 hover:text-red-600 dark:border-white/15 dark:bg-white/5 dark:text-white/70 dark:hover:border-red-400/40 dark:hover:bg-red-500/15 dark:hover:text-red-400"
            : "border-black/20 bg-black/[0.06] text-black/75 hover:bg-black/[0.12] hover:text-black/95 dark:border-white/15 dark:bg-white/5 dark:text-white/75 dark:hover:bg-white/10 dark:hover:text-white",
        FOCUS_RING,
      )}
    >
      <Icon className="h-3 w-3 flex-shrink-0" aria-hidden />
      <span className="whitespace-nowrap">{label}</span>
    </button>
  );
}

export function BulkActionBar({
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
  /** BINDER-MULTISELECT-BULK-02 — "Bloquear" só aparece se ALGUM selecionado ainda não está bloqueado (oculto quando todos já estão locked). */
  showLock: boolean;
  /** BINDER-MULTISELECT-BULK-02 — "Desbloquear" só aparece se ALGUM selecionado está bloqueado (oculto quando todos já estão unlocked). */
  showUnlock: boolean;
  onMoveToTray: () => void;
  onLock: () => void;
  onUnlock: () => void;
  onRemove: () => void;
  onClear: () => void;
}) {
  return (
    // BINDER-MULTISELECT-UX-01 (2026-08-29) — `my-3` (era `mt-3`): a barra
    // MOVEU de abaixo do Binder para ENTRE a paginação e o Binder — agora
    // precisa de respiro nos dois lados (acima, separando da paginação;
    // abaixo, separando do Binder), não só de um lado.
    <div className="my-3 flex w-full flex-col items-center gap-1.5">
      <div
        className={cn(
          "flex max-w-full flex-wrap items-center justify-center gap-1.5 rounded-full border px-2.5 py-1.5 sm:gap-2 sm:px-3 sm:py-2",
          "border-black/20 bg-white/75 backdrop-blur-sm dark:border-white/15 dark:bg-black/30",
        )}
      >
        <span
          aria-live="polite"
          aria-atomic="true"
          className="select-none whitespace-nowrap rounded-full bg-[hsl(40_70%_62%_/_0.18)] px-2 py-1 text-[10px] font-semibold text-[hsl(32_75%_30%)] dark:bg-[hsl(40_70%_62%_/_0.22)] dark:text-[hsl(40_80%_82%)] sm:text-xs"
        >
          {count} {count === 1 ? "selecionada" : "selecionadas"}
        </span>
        <BarButton icon={Inbox} label="Bandeja" onClick={onMoveToTray} />
        {showLock && <BarButton icon={Lock} label="Bloquear" onClick={onLock} tone="lock" />}
        {showUnlock && <BarButton icon={LockOpen} label="Desbloquear" onClick={onUnlock} tone="lock" />}
        <BarButton icon={Trash2} label="Remover" onClick={onRemove} tone="destructive" />
        <div className="mx-0.5 h-4 w-px flex-shrink-0 bg-black/15 dark:bg-white/15" aria-hidden />
        <BarButton icon={X} label="Limpar seleção" onClick={onClear} />
      </div>
      {statusMessage && (
        <span
          aria-live="polite"
          aria-atomic="true"
          className="max-w-[280px] text-center text-[10px] text-black/60 dark:text-white/55 sm:text-xs"
        >
          {statusMessage}
        </span>
      )}
    </div>
  );
}
