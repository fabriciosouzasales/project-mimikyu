"use client";

import { useContext } from "react";
import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import { ArrowDown, Bookmark, BookmarkX, FilePlus2, Focus, GalleryVerticalEnd, Inbox, LayoutGrid, Lock, LockOpen, Maximize2, Minimize2, PawPrint, Sparkles, Trash2, X, type LucideIcon } from "lucide-react";
import { BinderPortalContext } from "./binder-slot";
import styles from "./tool-rail.module.css";

/**
 * Menu lateral de organização do Fichário — `ToolRail` do spike
 * `binder-nav-01/tool-rail.tsx` (BINDER-TOOL-RAIL-03), recuperado em
 * P2-B-SPIKE-SIDEBAR-RECOVERY-01 e refinado em
 * P2-B-PAGE-OVERVIEW-AND-TOOL-RAIL-01 (visão geral + microinterações).
 *
 * Decisões preservadas do spike:
 *  - componente ESTRUTURAL e PERMANENTE: nenhum botão aparece/some com o
 *    contexto ("memória espacial"); ações sem alvo ficam indisponíveis;
 *  - cápsula escura vertical ao lado da seta esquerda, seções separadas por
 *    traço fino, tooltip escuro à direita;
 *  - indisponível = `aria-disabled` (continua focável e com tooltip que
 *    explica o porquê), nunca o atributo `disabled`;
 *  - "Bandeja" (fixa) usa `Inbox`; "Mover para a Bandeja" (seleção) usa
 *    `ArrowDown`; fixar/soltar em azul-frio; retirar em vermelho, isolado;
 *  - contador da seleção neutro com 0, dourado com seleção.
 *
 * Movimento: um só vocabulário para todos os botões (ver
 * `tool-rail.module.css`): hover 140 ms, pressão 110 ms, modo ativo 200 ms,
 * tooltip 170 ms; só transform/opacity/cor; movimento reduzido = imediato.
 *
 * Seções (só o que tem comportamento real — sem botão fictício):
 *  A Navegação/Organização — Visão geral (páginas), Adicionar páginas (5125),
 *                            Bandeja, Cartas disponíveis
 *                            (exemplares desta coleção ainda sem bolso) e, só em
 *                            fichário compartilhado, "Só desta coleção"
 *                            (P2-SHARED-BINDER-FRONTEND-01) e, só em fichário
 *                            de Pokédex, "Pokémon nos bolsos" (referências de
 *                            espécie; POKEDEX-BINDER-SPECIES-REFERENCE) e,
 *                            só em fichário Master Set com novidade do Catálogo
 *                            ainda sem lugar, "Novidades do Catálogo" com contador
 *                            (BINDER-CATALOG-RECONCILIATION-FRONTEND-01; some
 *                            quando não há novidade — é um aviso, não ferramenta).
 *  B Experiência           — Tela cheia.
 *  D Seleção               — contador, Mover para a Bandeja, Fixar, Soltar,
 *                            Reservar, Liberar reserva, Tirar do fichário, Limpar.
 * Fora (no spike eram "Em breve" ou dependiam de dados simulados):
 * Adicionar carta, Buscar, Exportar/Imprimir, Compartilhar, Desfazer/Refazer.
 */
export type ToolRailState = {
  editable: boolean;
  busy: boolean;
  overviewOpen: boolean;
  /** Pode acrescentar páginas ao fim (5125): fichário editável. */
  canAddPages: boolean;
  trayCount: number;
  trayOpen: boolean;
  /** Cartas desta coleção fora dos bolsos (5230). */
  availableCount: number;
  availableOpen: boolean;
  /** Fichário com mais de uma coleção: mostra o destaque "Só desta coleção". */
  shared: boolean;
  onlyMine: boolean;
  /** Fichário de Pokédex: botão "Pokémon nos bolsos" (ausente em qualquer outro fichário). */
  speciesAvailable?: boolean;
  /** Referências gravadas e exibidas. */
  speciesActive?: boolean;
  speciesCount?: number;
  /** Novidades do Catálogo pendentes (0 = botão ausente). Só Master Set elegível. */
  catalogCount?: number;
  catalogOpen?: boolean;
  canFullscreen: boolean;
  fullscreen: boolean;
  count: number;
  canTray: boolean;
  canLock: boolean;
  canUnlock: boolean;
  canReserve: boolean;
  canClearReserve: boolean;
  canRemove: boolean;
};

export type ToolRailActions = {
  onOpenOverview: () => void;
  onAddPages: () => void;
  onToggleTray: () => void;
  onToggleAvailable: () => void;
  onToggleOnlyMine: () => void;
  onOpenSpecies?: () => void;
  onOpenCatalog?: () => void;
  onToggleFullscreen: () => void;
  onMoveToTray: () => void;
  onLock: () => void;
  onUnlock: () => void;
  onReserve: () => void;
  onClearReserve: () => void;
  onRemove: () => void;
  onClear: () => void;
};

function Separator() {
  return <span className={styles.separator} aria-hidden />;
}

function RailButton({
  icon: Icon,
  label,
  onClick,
  tone,
  active,
  badge,
  disabled = false,
  haspopup,
}: {
  icon: LucideIcon;
  label: string;
  onClick: () => void;
  tone?: "lock" | "danger";
  /** Modo/ferramenta ligado: `aria-pressed` + fundo e ícone dourados + traço indicador. */
  active?: boolean;
  badge?: number;
  disabled?: boolean;
  haspopup?: "dialog";
}) {
  const portal = useContext(BinderPortalContext);
  return (
    <TooltipPrimitive.Root>
      <TooltipPrimitive.Trigger asChild>
        <button
          type="button"
          className={styles.button}
          onClick={disabled ? undefined : onClick}
          aria-label={label}
          aria-disabled={disabled || undefined}
          aria-pressed={active === undefined ? undefined : active}
          aria-haspopup={haspopup}
          data-tone={tone}
        >
          <span className={styles.indicator} aria-hidden />
          <Icon aria-hidden />
          {typeof badge === "number" && badge > 0 ? (
            <span key={badge > 0 ? "on" : "off"} className={styles.badge} aria-hidden>
              {badge}
            </span>
          ) : null}
        </button>
      </TooltipPrimitive.Trigger>
      <TooltipPrimitive.Portal container={portal?.current ?? undefined}>
        <TooltipPrimitive.Content side="right" sideOffset={10} collisionPadding={8} className={styles.tip}>
          {label}
          <TooltipPrimitive.Arrow className={styles.tipArrow} width={10} height={5} />
        </TooltipPrimitive.Content>
      </TooltipPrimitive.Portal>
    </TooltipPrimitive.Root>
  );
}

export function BinderToolRail({ state: s, actions: a }: { state: ToolRailState; actions: ToolRailActions }) {
  const none = s.count === 0;
  const readOnly = !s.editable;
  const why = (ok: boolean, base: string, reason: string) =>
    ok ? base : readOnly ? `${base} — coleção arquivada, só leitura` : none ? `${base} — selecione ao menos uma carta` : `${base} — ${reason}`;

  return (
    <TooltipPrimitive.Provider delayDuration={350} skipDelayDuration={250}>
      <div role="toolbar" aria-label="Ferramentas do fichário" className={styles.rail}>
        {/* A — Navegação e organização */}
        <RailButton icon={LayoutGrid} label="Visão geral das páginas" onClick={a.onOpenOverview} active={s.overviewOpen} haspopup="dialog" />
        <RailButton
          icon={FilePlus2}
          label={s.canAddPages ? "Adicionar páginas ao fim do fichário" : "Adicionar páginas — coleção arquivada, só leitura"}
          onClick={a.onAddPages}
          disabled={!s.canAddPages || s.busy}
          haspopup="dialog"
        />
        <RailButton
          icon={Inbox}
          label={s.trayOpen ? "Fechar a Bandeja" : s.trayCount > 0 ? `Bandeja — ${s.trayCount} ${s.trayCount === 1 ? "carta" : "cartas"}` : "Bandeja — vazia"}
          onClick={a.onToggleTray}
          active={s.trayOpen}
          badge={s.trayCount}
        />
        <RailButton
          icon={GalleryVerticalEnd}
          label={
            s.availableOpen
              ? "Fechar Cartas disponíveis"
              : s.availableCount > 0
                ? `Cartas disponíveis — ${s.availableCount} desta coleção sem bolso`
                : "Cartas disponíveis — todas já estão nos bolsos"
          }
          onClick={a.onToggleAvailable}
          active={s.availableOpen}
          badge={s.availableCount}
        />
        {s.shared ? (
          <RailButton
            icon={Focus}
            label={s.onlyMine ? "Mostrar todas as coleções do fichário" : "Só desta coleção — destacar as cartas desta coleção"}
            onClick={a.onToggleOnlyMine}
            active={s.onlyMine}
          />
        ) : null}

        {s.speciesAvailable && a.onOpenSpecies ? (
          <RailButton
            icon={PawPrint}
            label={
              (s.speciesCount ?? 0) === 0
                ? "Pokémon nos bolsos — mostrar a arte de cada espécie nos bolsos vazios"
                : s.speciesActive
                  ? "Pokémon nos bolsos — exibidos"
                  : "Pokémon nos bolsos — ocultos"
            }
            onClick={a.onOpenSpecies}
            active={s.speciesActive === true}
            haspopup="dialog"
          />
        ) : null}

        {(s.catalogCount ?? 0) > 0 && a.onOpenCatalog ? (
          <RailButton
            icon={Sparkles}
            label={
              s.editable
                ? `Novidades do Catálogo — ${s.catalogCount} ${s.catalogCount === 1 ? "posição nova" : "posições novas"} do Set ainda sem bolso`
                : "Novidades do Catálogo — coleção arquivada, só leitura"
            }
            onClick={a.onOpenCatalog}
            active={s.catalogOpen === true}
            badge={s.catalogCount}
            disabled={!s.editable || s.busy}
            haspopup="dialog"
          />
        ) : null}

        {/* B — Experiência */}
        {s.canFullscreen ? (
          <>
            <Separator />
            <RailButton
              icon={s.fullscreen ? Minimize2 : Maximize2}
              label={s.fullscreen ? "Sair da tela cheia" : "Tela cheia"}
              onClick={a.onToggleFullscreen}
              active={s.fullscreen}
            />
          </>
        ) : null}

        <Separator />

        {/* D — Seleção (sempre montada) */}
        <span className={styles.count} data-active={!none} title={none ? "Nenhuma carta selecionada" : `${s.count} selecionada(s)`} aria-hidden>
          {s.count}
        </span>
        <span aria-live="polite" aria-atomic="true" className="sr-only">
          {s.count} {s.count === 1 ? "carta selecionada" : "cartas selecionadas"}
        </span>
        <RailButton icon={ArrowDown} label={why(s.canTray, "Mover para a Bandeja", "nenhuma pode sair (fixadas ou já na Bandeja)")} onClick={a.onMoveToTray} disabled={!s.canTray} />
        <RailButton icon={Lock} tone="lock" label={why(s.canLock && !s.busy, "Fixar bolsos", "todos já fixados")} onClick={a.onLock} disabled={!s.canLock || s.busy} />
        <RailButton icon={LockOpen} tone="lock" label={why(s.canUnlock && !s.busy, "Soltar bolsos", "nenhum fixado")} onClick={a.onUnlock} disabled={!s.canUnlock || s.busy} />
        <RailButton
          icon={Bookmark}
          label={why(s.canReserve && !s.busy, "Reservar os bolsos para as cartas", "já reservados para essas cartas")}
          onClick={a.onReserve}
          disabled={!s.canReserve || s.busy}
        />
        <RailButton
          icon={BookmarkX}
          label={why(s.canClearReserve && !s.busy, "Liberar reservas", "nenhum tem reserva")}
          onClick={a.onClearReserve}
          disabled={!s.canClearReserve || s.busy}
        />
        <Separator />
        <RailButton icon={Trash2} tone="danger" label={why(s.canRemove && !s.busy, "Tirar do fichário", "todas fixadas")} onClick={a.onRemove} disabled={!s.canRemove || s.busy} />
        <RailButton icon={X} label={none ? "Limpar seleção — nenhuma selecionada" : "Limpar seleção (Esc)"} onClick={a.onClear} disabled={none} />
      </div>
    </TooltipPrimitive.Provider>
  );
}
