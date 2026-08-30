"use client";

import { forwardRef, useRef } from "react";
import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import {
  ArrowDown,
  Download,
  Inbox,
  Lock,
  LockOpen,
  Maximize2,
  Minimize2,
  Plus,
  Redo2,
  Search,
  Share2,
  Trash2,
  Undo2,
  X,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * BINDER-TOOL-RAIL-03 (2026-08-30) — "a decisão arquitetural agora é
 * DEFINITIVA: a Tool Rail é um componente ESTRUTURAL E PERMANENTE do
 * Binder Workspace. Ela não é mais uma Bulk Action Rail adaptada." Terceira
 * rodada sobre este componente (BINDER-MULTISELECT-RAIL-01 → BINDER-BULK-
 * ACTION-RAIL-POSITION-01 → BINDER-TOOL-RAIL-02 → esta), pedido explícito
 * para consolidar a ARQUITETURA COMPLETA — não só o V1 mínimo de
 * TOOL-RAIL-02, mas o inventário inteiro de seções/ações que a rail vai
 * eventualmente ter, mesmo que a maioria comece `disabled`/"Em breve".
 *
 * TRÊS CORREÇÕES sobre TOOL-RAIL-02, pedidas explicitamente:
 *  1. POSICIONAMENTO — deixou de ser `absolute`/`right-[calc(...)]`
 *     calculado a partir do Binder (`binder-pages-nav.tsx`) e passou a ser
 *     um item de FLEX comum, irmão da seta esquerda, portalado para
 *     `binder-nav-view.tsx` (`toolRailPortalNode`) — ver doc-comment
 *     completo lá. Este arquivo não sabe mais NADA sobre onde é
 *     posicionado (nem antes sabia, mas agora nem o CHAMADOR precisa
 *     calcular offset nenhum — é só mais um filho de um `<div className="flex
 *     items-center gap-*">`).
 *  2. ESTABILIDADE — nenhum botão previsto aparece/desaparece mais
 *     conforme o contexto. Todos os botões da Seção D (multi-select) que
 *     antes só existiam quando `isMultiSelectActive` agora estão SEMPRE
 *     montados, alternando `disabled` conforme `count`/estado de Lock —
 *     "manter memória espacial e evitar que a rail mude de composição
 *     durante o uso".
 *  3. ARQUITETURA COMPLETA — quatro seções (A Organização, B Saída/
 *     Experiência, C Histórico, D Seleção múltipla), com separadores entre
 *     elas. A MAIORIA das ações novas desta rodada (Buscar, Exportar/
 *     Imprimir, Compartilhar, Desfazer, Refazer) são placeholders
 *     `disabled` com tooltip "Em breve" — presentes para validar o
 *     CONJUNTO completo, sem nenhuma lógica de negócio nova por trás
 *     ("botões futuros podem existir disabled para validarmos o conjunto
 *     completo... não implementar funcionalidade nova").
 *
 * FUNCIONAL DE VERDADE nesta rodada (zero placeholder): Adicionar carta,
 * Bandeja (ambas herdadas de TOOL-RAIL-02, mesmos handlers) e Tela cheia —
 * nova, mas permitida explicitamente ("se puder ser implementado
 * trivialmente com API nativa e sem abrir nova frente, pode funcionar").
 * Fullscreen API nativa do browser (`document.requestFullscreen`/
 * `exitFullscreen`), sem dependência nova, estado (`isFullscreen`) e
 * handler (`onToggleFullscreen`) vivem em `binder-nav-view.tsx` (dono do
 * elemento real a ser colocado em tela cheia) — este componente só recebe
 * os dois como props e desenha o botão.
 *
 * "BUSCAR" continua fora do funcional (mesma decisão documentada em
 * TOOL-RAIL-02): o único mecanismo de busca já existente no Binder é o
 * campo DENTRO do `CardPickerModal`, escopado para localizar uma carta a
 * ADICIONAR/SUBSTITUIR — não para localizar/pular para uma carta já
 * posicionada no layout. Vira botão disabled "Em breve" nesta rodada,
 * exatamente como pedido ("se já houver busca reutilizável adequada,
 * conectar; caso contrário manter botão disabled").
 *
 * DISABLED — `aria-disabled` (nunca o atributo `disabled` nativo): um
 * `<button disabled>` para de disparar hover/focus em vários navegadores,
 * o que quebraria o tooltip que precisa continuar explicando a ação
 * (inclusive as futuras: "Tooltip deve explicar também ações futuras
 * disabled", pedido explícito) — o botão continua focável/hover-ável, só o
 * clique vira no-op e o visual fica esmaecido (mas legível, nunca
 * invisível — pedido explícito de estilo).
 *
 * SEÇÃO D SEMPRE VISÍVEL — `count`/`allLocked`/`allUnlocked` chegam crus
 * (não mais como `showLock`/`showUnlock` pré-calculados por
 * `binder-pages-nav.tsx`, como em TOOL-RAIL-02); este arquivo deriva
 * `canMoveToTray`/`canLock`/`canUnlock`/`canRemove`/`canClear` sozinho a
 * partir deles, porque agora o `count === 0` também precisa desabilitar
 * tudo (antes a seção inteira nem existia nesse caso). `canRemove` reusa a
 * MESMA condição de `canLock` sendo falso por `allLocked` — "Remover...
 * respeita Lock": se todos os selecionados estão bloqueados, não sobra
 * nada removível, mesmo racional já usado por `handleBulkRemove` (que pula
 * bloqueados e reporta quantos pulou).
 *
 * ÍCONES — "Bandeja" (fixa) usa `Inbox`; "Mover para a Bandeja"
 * (contextual) usa `ArrowDown` — mesma diferenciação de TOOL-RAIL-02, ainda
 * necessária agora que as duas convivem permanentemente na mesma cápsula.
 *
 * ALTURA — com as quatro seções sempre montadas (14 itens + 3
 * separadores), a cápsula fica consideravelmente mais alta que a V1. Não
 * foi adicionado nenhum contêiner de scroll interno novo nesta rodada
 * (escopo explícito: "consolidar a ARQUITETURA", não polir densidade) — o
 * scroll vertical já existente no diálogo do Binder (`overflow-y-auto` em
 * `binder-nav-view.tsx`) cobre o caso de a rail não caber inteira na
 * viewport. Ver relatório de implementação para essa pendência sinalizada.
 */

const RAIL_BG = "hsl(0 0% 6% / 0.94)";
const RAIL_BORDER = "hsl(0 0% 100% / 0.1)";

function RailSeparator() {
  return <div className="h-px w-5 flex-shrink-0" style={{ background: "hsl(0 0% 100% / 0.12)" }} aria-hidden />;
}

/**
 * TOOLTIPS — `@radix-ui/react-tooltip` direto (já instalado, usado desde
 * BINDER-MULTISELECT-RAIL-01), hover + foco de teclado nativos, estilo
 * dark próprio em vez do wrapper claro de `components/ui/tooltip.tsx`.
 *
 * `disabled` — ver doc-comment do arquivo (seção DISABLED): `aria-disabled`
 * em vez do atributo nativo, para o tooltip continuar funcionando mesmo
 * desabilitado.
 *
 * `badge` — pill numérica pequena no canto superior-direito do ícone;
 * omitida quando `undefined`/`0`.
 */
const RailButton = forwardRef<
  HTMLButtonElement,
  {
    icon: LucideIcon;
    label: string;
    onClick: () => void;
    tone?: "neutral" | "lock" | "destructive";
    active?: boolean;
    badge?: number;
    disabled?: boolean;
  }
>(function RailButton({ icon: Icon, label, onClick, tone = "neutral", active = false, badge, disabled = false }, ref) {
  return (
    <TooltipPrimitive.Root>
      <TooltipPrimitive.Trigger asChild>
        <button
          ref={ref}
          type="button"
          onClick={disabled ? undefined : onClick}
          aria-label={label}
          aria-disabled={disabled}
          aria-pressed={active}
          className={cn(
            "relative flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full transition-colors active:scale-90 sm:h-8 sm:w-8",
            "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-[hsl(0_0%_6%)]",
            disabled
              ? "cursor-not-allowed text-white/25"
              : cn(
                  tone === "lock"
                    ? "text-[hsl(205_80%_75%)] hover:bg-[hsl(205_70%_58%_/_0.22)]"
                    : tone === "destructive"
                      ? "text-red-400/90 hover:bg-red-500/15 hover:text-red-400"
                      : "text-white/75 hover:bg-white/12 hover:text-white",
                  active && "bg-[hsl(40_70%_62%_/_0.18)] text-[hsl(40_80%_82%)] hover:bg-[hsl(40_70%_62%_/_0.26)]",
                ),
          )}
        >
          <Icon className="h-3.5 w-3.5 sm:h-4 sm:w-4" aria-hidden />
          {typeof badge === "number" && badge > 0 && (
            <span
              aria-hidden
              className="absolute -right-0.5 -top-0.5 flex h-3.5 min-w-[14px] flex-shrink-0 items-center justify-center rounded-full px-[3px] text-[9px] font-semibold tabular-nums"
              style={{ background: "hsl(40 70% 62% / 0.95)", color: "hsl(0 0% 8%)" }}
            >
              {badge}
            </span>
          )}
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
});

export function ToolRail({
  // Seção A — Organização
  canAdd,
  onAdd,
  trayOpen,
  trayCount,
  onToggleTray,
  // Seção B — Saída/Experiência
  isFullscreen,
  onToggleFullscreen,
  // Seção D — Seleção múltipla
  count,
  statusMessage,
  allLocked,
  allUnlocked,
  onMoveToTray,
  onLock,
  onUnlock,
  onRemove,
  onClear,
}: {
  /** Há ao menos um slot vazio no spread atual — se não, "Adicionar carta" fica desabilitado (não escondido). */
  canAdd: boolean;
  /** Recebe o próprio botão (para restaurar foco ao fechar o Picker, mesmo padrão de `pickerTriggerRef`) — `binder-pages-nav.tsx` resolve o slot-alvo. */
  onAdd: (triggerEl: HTMLElement | null) => void;
  trayOpen: boolean;
  trayCount: number;
  onToggleTray: () => void;
  isFullscreen: boolean;
  onToggleFullscreen: () => void;
  count: number;
  statusMessage: string | null;
  /** `true` só quando HÁ seleção e TODOS os selecionados já estão bloqueados. */
  allLocked: boolean;
  /** `true` quando NÃO há seleção OU nenhum selecionado está bloqueado. */
  allUnlocked: boolean;
  onMoveToTray: () => void;
  onLock: () => void;
  onUnlock: () => void;
  onRemove: () => void;
  onClear: () => void;
}) {
  const addButtonRef = useRef<HTMLButtonElement>(null);

  // BINDER-TOOL-RAIL-03 — habilitação da Seção D derivada aqui (ver
  // doc-comment do arquivo, "SEÇÃO D SEMPRE VISÍVEL").
  const canMoveToTray = count > 0;
  const canLock = count > 0 && !allLocked;
  const canUnlock = count > 0 && !allUnlocked;
  const canRemove = count > 0 && !allLocked;
  const canClear = count > 0;

  return (
    <TooltipPrimitive.Provider delayDuration={200} skipDelayDuration={100}>
      <div
        role="toolbar"
        aria-label="Ferramentas do Binder"
        aria-orientation="vertical"
        className="pointer-events-auto flex flex-col items-center gap-1 rounded-full px-1 py-2 sm:px-1.5 sm:py-2.5"
        style={{
          background: RAIL_BG,
          boxShadow: `0 12px 28px -8px rgba(0,0,0,0.65), inset 0 1px 0 hsl(0 0% 100% / 0.08), 0 0 0 1px ${RAIL_BORDER}`,
          backdropFilter: "blur(6px)",
        }}
      >
        {/* SEÇÃO A — Organização. Adicionar/Bandeja funcionais; Buscar disabled ("Em breve" — sem mecanismo reutilizável real, ver doc-comment do arquivo). */}
        <RailButton
          ref={addButtonRef}
          icon={Plus}
          label={canAdd ? "Adicionar carta" : "Nenhum slot vazio nesta página"}
          onClick={() => onAdd(addButtonRef.current)}
          disabled={!canAdd}
        />
        <RailButton
          icon={Inbox}
          label={
            trayOpen
              ? "Fechar Bandeja"
              : trayCount > 0
                ? `Bandeja — ${trayCount} ${trayCount === 1 ? "carta" : "cartas"}`
                : "Bandeja — vazia"
          }
          onClick={onToggleTray}
          active={trayOpen}
          badge={trayCount}
        />
        <RailButton icon={Search} label="Buscar — Em breve" onClick={() => {}} disabled />

        <RailSeparator />

        {/* SEÇÃO B — Saída/Experiência. Só Tela cheia é funcional (API nativa, trivial); Exportar/Compartilhar disabled ("Em breve"). */}
        <RailButton icon={Download} label="Exportar/Imprimir — Em breve" onClick={() => {}} disabled />
        <RailButton icon={Share2} label="Compartilhar — Em breve" onClick={() => {}} disabled />
        <RailButton
          icon={isFullscreen ? Minimize2 : Maximize2}
          label={isFullscreen ? "Sair da tela cheia" : "Tela cheia"}
          onClick={onToggleFullscreen}
          active={isFullscreen}
        />

        <RailSeparator />

        {/* SEÇÃO C — Histórico. Sempre disabled nesta rodada — pedido explícito: "não implementar Undo/Redo agora". */}
        <RailButton icon={Undo2} label="Desfazer — Em breve" onClick={() => {}} disabled />
        <RailButton icon={Redo2} label="Refazer — Em breve" onClick={() => {}} disabled />

        <RailSeparator />

        {/* SEÇÃO D — Seleção múltipla. SEMPRE montada (não mais condicionada a
            `isMultiSelectActive`) — pedido explícito: "manter memória
            espacial e evitar que a rail mude de composição durante o uso".
            Contador em estado neutro quando `count === 0`, accent dourado
            quando `count > 0`; ações habilitam conforme `canX` acima. */}
        <span
          aria-hidden
          className={cn(
            "flex h-6 w-6 flex-shrink-0 select-none items-center justify-center rounded-full text-[11px] font-semibold tabular-nums transition-colors",
            count > 0 ? "" : "bg-white/10 text-white/35",
          )}
          style={count > 0 ? { background: "hsl(40 70% 62% / 0.22)", color: "hsl(40 80% 82%)" } : undefined}
        >
          {count}
        </span>
        <span aria-live="polite" aria-atomic="true" className="sr-only">
          {count} {count === 1 ? "selecionada" : "selecionadas"}
          {statusMessage ? `. ${statusMessage}` : ""}
        </span>

        <RailButton
          icon={ArrowDown}
          label={canMoveToTray ? "Mover para a Bandeja" : "Mover para a Bandeja — selecione ao menos uma carta"}
          onClick={onMoveToTray}
          disabled={!canMoveToTray}
        />
        <RailButton
          icon={Lock}
          label={canLock ? "Bloquear" : count === 0 ? "Bloquear — selecione ao menos uma carta" : "Bloquear — todas já bloqueadas"}
          onClick={onLock}
          tone="lock"
          disabled={!canLock}
        />
        <RailButton
          icon={LockOpen}
          label={canUnlock ? "Desbloquear" : count === 0 ? "Desbloquear — selecione ao menos uma carta" : "Desbloquear — nenhuma bloqueada"}
          onClick={onUnlock}
          tone="lock"
          disabled={!canUnlock}
        />
        <RailButton
          icon={Trash2}
          label={canRemove ? "Remover" : count === 0 ? "Remover — selecione ao menos uma carta" : "Remover — todas bloqueadas"}
          onClick={onRemove}
          tone="destructive"
          disabled={!canRemove}
        />
        <RailButton
          icon={X}
          label={canClear ? "Limpar seleção" : "Limpar seleção — nenhuma selecionada"}
          onClick={onClear}
          disabled={!canClear}
        />
      </div>
    </TooltipPrimitive.Provider>
  );
}
