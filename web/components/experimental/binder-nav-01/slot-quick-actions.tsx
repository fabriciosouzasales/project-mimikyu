import type { DraggableAttributes, DraggableSyntheticListeners } from "@dnd-kit/core";
import type { LucideIcon } from "lucide-react";
import { Circle, CircleCheck, GripVertical, Heart, ImagePlus, Lock, LockOpen, MoreHorizontal, Plus, Repeat, Trash2 } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { cn } from "@/lib/utils";

/**
 * BINDER-INTERACTION-01 (2026-08-28) — quick actions contextuais por slot.
 * Pedido de Fabrício: "criar quick actions contextuais, discretas e premium
 * para slots vazios e ocupados, sem poluir visualmente o Binder." Arquivo
 * novo, isolado em `binder-nav-01/` (mesmo padrão de isolamento de todo o
 * resto do experimental) — sem dependências novas: só `lucide-react`
 * (já usado em `nav-controls.tsx`) e o mesmo token de focus ring dourado já
 * estabelecido lá (`FOCUS_RING`).
 *
 * Duas variantes:
 *  - `EmptySlotQuickActions`: ação primária "Adicionar carta" (rótulo
 *    fantasma, não um botão grande de UI) + espaço reservado, DESABILITADO,
 *    para a futura ação "Adicionar imagem" — só o espaço/affordance visual
 *    pedido explicitamente, sem lógica real ainda.
 *  - `FilledSlotQuickActions`: favoritar / bloquear layout / substituir /
 *    remover — remover isolado por um separador, como ação destrutiva
 *    secundária. IMPORTANTE (pedido explícito): favoritar referencia a
 *    CARD, nunca a Card Variant — `isFavorite`/`onToggleFavorite` são
 *    resolvidos pelo chamador (`binder-pages-nav.tsx`) a partir de
 *    `card.id`, nunca de um id de variante. Lock referencia o SLOT físico
 *    (`isLocked`/`onToggleLock`, por `slot.id`) — é proteção de LAYOUT
 *    (futuro auto-arrange/push/insert/reorganização), não um lock
 *    patrimonial do item do Inventory.
 *
 * Correção de composição (2026-08-28, mesma data — pedido final de
 * Fabrício): a lista aprovada de quick actions do slot ocupado é
 * "substituir carta / remover do slot / favoritar-desfavoritar Card" — SEM
 * "visualizar" e SEM "mover":
 *  - "Visualizar" removida da toolbar — a própria carta pode ser clicada
 *    para abrir seus detalhes no futuro, não precisa de um botão dedicado
 *    (nenhuma lógica de abertura de detalhes foi implementada nesta rodada,
 *    só a remoção do botão redundante).
 *  - "Mover" nunca existiu como botão aqui e continua fora de escopo —
 *    movimentação de carta dentro do Binder será tratada EXCLUSIVAMENTE por
 *    Drag and Drop numa rodada futura, nunca por um botão de quick action.
 *  - Uma proposta intermediária de "Adicionar à Wishlist" foi cogitada e
 *    depois REJEITADA por Fabrício antes de chegar a ser implementada:
 *    "não faz sentido oferecer Wishlist dentro de uma carta já inserida no
 *    Binder" — não há, portanto, nenhum código de Wishlist neste arquivo.
 *
 * Rodada visual (2026-08-28, mesma data) — pedido de Fabrício após ver o
 * resultado real: "funcionam conceitualmente, mas precisam de uma rodada
 * visual curta... fazer as quick actions parecerem parte natural do Binder,
 * não uma toolbar genérica sobre cards." Mudanças, SEM nenhuma função nova:
 *  1. Toolbar do slot ocupado deixou de ser uma faixa cheia (`inset-x-0`)
 *     com gradiente forte — passou a ser uma cápsula compacta. Ícones
 *     menores (glifo reduzido, alvo de toque mantido em 24px — ver nota de
 *     acessibilidade abaixo) e gap mais fechado.
 *  2. "Remover" passou a ser tratado como ação destrutiva SECUNDÁRIA: fica
 *     isolado por um separador fino depois do grupo principal, com a MESMA
 *     aparência neutra em repouso — só ganha cor/feedback vermelho em
 *     hover/focus (`variant="destructive"` em `QuickActionButton`). Não tem
 *     mais o mesmo peso visual das ações principais.
 *  3. Slot vazio: "Adicionar carta" perdeu a borda/preenchimento de pílula
 *     (lia como botão administrativo) — agora é um rótulo fantasma (texto +
 *     ícone) sem chrome em repouso, só ganha um fundo bem sutil no próprio
 *     hover/focus do botão. O vinhetado atrás dele também encolheu (de uma
 *     faixa forte cobrindo ~15% da altura para um degradê baixo e suave).
 *  4. Favorito já usava contorno quando não-favorito e preenchido quando
 *     favorito (`fill={active ? "currentColor" : "none"}`) — mantido, sem
 *     mudança funcional.
 *  5. Feedback de "ação ativa": todo botão ganha `active:scale-90` (só
 *     transform, sem custo) para dar retorno tátil imediato ao toque/clique,
 *     distinto de um toggle persistente (favorito/lock).
 *
 * BINDER-QUICK-ACTIONS-01 (2026-08-29) — pedido explícito de Fabrício,
 * reformulando o slot ocupado sobre a base de BINDER-INTERACTION-01:
 *  1. **Lock/Unlock Slot, ação nova** — protege o LAYOUT do slot (futuro
 *     auto-arrange/push/insert), não é um lock patrimonial do Inventory.
 *     Ícone alterna entre `Lock`/`LockOpen` (a própria forma do glifo já
 *     comunica o estado, além da cor de fundo ativa) — ver `activeTone`
 *     abaixo.
 *  2. **Cores de estado ativo reservadas por significado** (pedido
 *     explícito, "dourado permanece reservado à identidade/foco/premium do
 *     MMKYU"): Favorite ativo usa VERMELHO (nunca dourado/amarelo); Lock
 *     ativo usa um tom AZUL-frio, para não colidir nem com o vermelho do
 *     Favorite nem com o dourado do foco/seleção. `QuickActionButton` ganhou
 *     a prop `activeTone` (`"favorite" | "lock"`) para resolver a cor certa
 *     por botão, em vez do único tom dourado fixo usado antes (era genérico
 *     e cobria só o Favorite).
 *  3. **Removidas do escopo, por pedido explícito**: nenhum botão "View"
 *     (a carta já abre Card Detail ao ser clicada, ver `binder-slot-full.tsx`),
 *     nenhum "Move" (Drag and Drop, etapa futura), nenhuma Wishlist, nenhum
 *     "Mark as Missing", nenhum "Flip", nenhum Labels nesta etapa.
 *  4. **Foco no Favorite/`card-detail-modal.tsx`**: o mesmo estado de
 *     favorito é compartilhado com o Card Detail Overlay (`isFavorite` vem
 *     de `favoriteCardIds`, ver `binder-pages-nav.tsx`) — o botão de
 *     favoritar de lá também deixou de usar dourado, pela mesma regra.
 *
 * BINDER-QUICK-ACTIONS-01, revisão de posicionamento (2026-08-29, mesma
 * data) — Fabrício testou a primeira versão localmente (toolbar vertical
 * lateral) e pediu reversão do posicionamento: "prefiro o menu de ações
 * rápidas na parte inferior da carta, não na lateral" — preserva a carta
 * como protagonista, cria consistência com o slot vazio (que já usa
 * "Adicionar carta" na base) e evita uma coluna lateral competindo
 * visualmente com a carta. `FilledSlotQuickActions` voltou a ser uma cápsula
 * HORIZONTAL na base do slot (mesma região que `EmptySlotQuickActions` já
 * ocupava) — só o posicionamento mudou; a lógica/estado/cores/ordem das
 * ações (Favorite, Lock, Replace, separador, Remove) são as mesmas da
 * revisão anterior. Zona de interação/vinhete em `binder-slot-full.tsx`
 * também voltou de lateral (`right-0 w-[30%]`) para inferior
 * (`bottom-0 h-[30%]`), a mesma região usada pelo slot vazio.
 *
 * BINDER-MULTISELECT-BULK-01 (2026-08-29) — nova ação "Selecionar", pedido
 * explícito de Fabrício: a entrada em seleção múltipla não pode depender
 * SÓ de Ctrl/Cmd+click (atalho de desktop) — precisa de uma "ação
 * 'Selecionar' contextual ou equivalente discreto", que também funcione em
 * mobile. `CircleCheck`/`Circle` (mesmo padrão de troca de glifo já usado
 * por Lock/LockOpen) alternam `isMultiSelected` via `onToggleMultiSelect`.
 * Posicionada logo após a alça de arrastar + separador, antes de Favorite —
 * primeira ação do grupo, já que "entrar em modo de seleção" é
 * conceitualmente anterior às ações que operam sobre a carta individual.
 * `activeTone="select"` reaproveita o DOURADO já reservado a
 * seleção/foco/identidade no vocabulário visual do MMKYU (mesmo tom do
 * anel de `isSelected` em `binder-slot-full.tsx`) — coerente por ser,
 * também, uma seleção; o selo persistente (badge) no próprio slot é quem
 * garante que o estado não dependa só de cor (ver doc-comment de
 * `binder-slot-full.tsx`).
 *
 * Tooltip/aria-label: `title` nativo + `aria-label` em cada botão — o
 * projeto já tem `@radix-ui/react-tooltip` via `components/ui/tooltip`, mas
 * para um ícone de ~24px dentro de um slot de bolso, o overhead de
 * Portal/Provider por botão não se paga; `title` nativo cobre desktop,
 * `aria-label` cobre leitor de tela em qualquer dispositivo.
 *
 * Touch target: botões com no mínimo 24x24px (mínimo AA do WCAG 2.2 "Target
 * Size (Minimum)" — não o antigo 44px, que não cabe fisicamente num slot de
 * ~70-140px de largura sem cobrir a carta). O glifo interno encolheu nesta
 * rodada, mas a área de toque do `<button>` permanece 24px — decisão de
 * design consciente, não omissão.
 *
 * Mobile/touch (item explícito do pedido): "não depender de hover; tap/select
 * deve permitir acesso às ações". Já resolvido em `binder-slot-full.tsx`
 * antes desta rodada — tocar o slot (fora da arte da carta) alterna
 * `isSelected`, que força a toolbar visível via classe JS (sobrevive à
 * ausência de `:hover` em touch); tocar a própria carta abre o Card Detail
 * diretamente (accessível via foco no mesmo elemento). Nenhuma mudança nova
 * de comportamento mobile foi necessária nesta rodada — só a reposição
 * visual da toolbar (item 1 acima), mantendo os mesmos gatilhos de
 * visibilidade (hover OU focus-within OU selected).
 */

/**
 * BINDER-DND-01 (2026-08-29) — alça de arrastar (`DragHandleButton`), pedido
 * de Fabrício: "DnD passa a ser o mecanismo oficial de MOVE. Não criar botão
 * 'Move' nas Quick Actions." Isto NÃO é um botão de ação (não tem
 * `onClick`) — é a alça física que carrega `attributes`/`listeners` do
 * `useDraggable` (`binder-slot-full.tsx`), resolvendo o conflito
 * clique-abre-detalhe × arrastar-move SEM precisar de nenhuma heurística de
 * limiar/temporização: a arte da carta continua tendo só o `onClick` de
 * sempre (`CARD-DETAIL-01`, intocado), e é esta alça — um elemento
 * FISICAMENTE separado — que responde a pointerdown/touchstart/teclado do
 * dnd-kit. `setActivatorNodeRef` (não `setNodeRef`) é o ref correto aqui,
 * por padrão documentado do dnd-kit para "drag handle" quando o nó
 * medido/arrastado (o slot inteiro) é diferente do nó que ativa o gesto.
 *
 * Só aparece em slot OCUPADO (mesma visibilidade hover/focus-within/
 * selecionado da cápsula de quick actions já existente) e é DESABILITADA
 * (sem `attributes`/`listeners`, ícone apagado, `title` explicando o
 * motivo) quando o slot está Locked — "feedback visual claro, mas
 * discreto" de que a origem não pode iniciar um arrasto, mesmo sem tentar.
 */
function DragHandleButton({
  disabled,
  attributes,
  listeners,
  setActivatorNodeRef,
}: {
  disabled: boolean;
  attributes?: DraggableAttributes;
  listeners?: DraggableSyntheticListeners;
  setActivatorNodeRef?: (element: HTMLElement | null) => void;
}) {
  if (disabled) {
    return (
      <span
        aria-hidden
        title="Slot bloqueado — desbloqueie para mover"
        className="flex h-6 w-6 flex-shrink-0 cursor-not-allowed items-center justify-center rounded-full text-white/20"
      >
        <GripVertical className="h-2.5 w-2.5" aria-hidden />
      </span>
    );
  }
  return (
    <button
      ref={setActivatorNodeRef}
      type="button"
      aria-label="Mover carta (arraste, ou selecione e use as setas)"
      title="Mover carta"
      className={cn(
        "flex h-6 w-6 flex-shrink-0 cursor-grab touch-none items-center justify-center rounded-full text-white/70 transition-colors hover:bg-white/15 hover:text-white active:cursor-grabbing",
        FOCUS_RING,
      )}
      {...attributes}
      {...listeners}
    >
      <GripVertical className="h-2.5 w-2.5" aria-hidden />
    </button>
  );
}

const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/80";

function QuickActionButton({
  icon: Icon,
  label,
  onClick,
  active,
  disabled,
  variant = "default",
  activeTone = "favorite",
}: {
  icon: LucideIcon;
  label: string;
  /**
   * BINDER-ADD-REPLACE-CARD-01 (2026-08-29) — recebe o elemento que disparou
   * o clique (`event.currentTarget`), para que o botão "Substituir carta"
   * possa guardar o trigger e restaurar o foco a ele ao fechar o Card
   * Picker (mesmo padrão já usado por `onOpenDetail` em
   * `binder-slot-full.tsx`). Os demais callers (Favorite/Lock/Remove) têm
   * tipo `() => void` e simplesmente ignoram o argumento extra — atribuição
   * válida em TypeScript (função com menos parâmetros é atribuível a um
   * tipo que espera mais).
   */
  onClick?: (triggerEl: HTMLElement) => void;
  active?: boolean;
  disabled?: boolean;
  variant?: "default" | "destructive";
  activeTone?: "favorite" | "lock" | "select";
}) {
  const activeClasses =
    activeTone === "lock"
      ? "bg-[hsl(205_70%_58%_/_0.22)] text-[hsl(205_80%_75%)] hover:bg-[hsl(205_70%_58%_/_0.32)]"
      : activeTone === "select"
        ? "bg-[hsl(40_70%_62%_/_0.22)] text-[hsl(40_80%_78%)] hover:bg-[hsl(40_70%_62%_/_0.32)]"
        : "bg-red-500/20 text-red-400 hover:bg-red-500/30";
  return (
    <button
      type="button"
      onClick={(event) => {
        event.stopPropagation();
        onClick?.(event.currentTarget);
      }}
      disabled={disabled}
      aria-label={label}
      aria-disabled={disabled || undefined}
      title={label}
      className={cn(
        "flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full transition-colors active:scale-90 sm:h-6 sm:w-6",
        disabled
          ? "cursor-not-allowed text-white/20"
          : active
            ? activeClasses
            : variant === "destructive"
              ? "text-white/45 hover:bg-red-500/15 hover:text-red-400 focus-visible:ring-red-400/70"
              : "text-white/70 hover:bg-white/15 hover:text-white",
        FOCUS_RING,
      )}
    >
      <Icon className="h-2.5 w-2.5" aria-hidden fill={active && activeTone === "favorite" ? "currentColor" : "none"} />
    </button>
  );
}

/**
 * BINDER-QUICK-ACTIONS-DENSITY-01 (2026-08-29) — menu de overflow ("…") do
 * slot ocupado. Pedido de Fabrício: a barra tinha ações demais e excedia a
 * largura da carta; correção por HIERARQUIA, não por compressão de ícones/
 * padding — `FilledSlotQuickActions` mantém só Favorite/Lock/Replace
 * visíveis, e as duas ações menos frequentes (Selecionar, entrada do
 * multi-select — e Remover, destrutiva) migram para este menu.
 *
 * Sem dependência nova: o projeto não tem `@radix-ui/react-dropdown-menu`
 * nem `@radix-ui/react-popover` instalado (nem transitivamente — conferido
 * antes de escrever este componente), só `@radix-ui/react-dialog`/
 * `-collapsible`/`-tooltip`/`-slot`. Nenhum deles serve para um menu
 * pequeno ancorado a um botão sem repropósito forçado (Dialog é modal de
 * tela cheia; Collapsible expande inline, não ancorado). Em vez de
 * instalar uma dependência nova só para dois itens, este componente segue
 * o MESMO padrão local já estabelecido em `binder-tray.tsx`/`TraySurface`
 * para superfícies flutuantes pequenas: portal, posição calculada via
 * `getBoundingClientRect()` do botão no momento em que abre, e fechamento
 * por Esc/clique-fora — só que auto-contido (estado `open` local a cada
 * slot, não centralizado em `BinderPagesNav`, já que cada slot ocupado tem
 * seu próprio menu independente).
 *
 * BINDER-FULLSCREEN-QUICK-ACTIONS-01 (2026-08-30) — REGRESSÃO corrigida:
 * o alvo do portal era `document.body` fixo, hardcoded. Fora do modo Tela
 * Cheia isso sempre funcionou (mesmo racional de `CardDetailModal`/
 * `CardPickerModal`/`TraySurface`: `position: fixed` escapa de
 * `overflow-hidden`/`perspective` de ancestrais sem precisar que eles
 * também estejam sob o mesmo nó). Mas a Fullscreen API nativa (`tool-
 * rail.tsx`/`binder-nav-view.tsx`, ação "Tela cheia") promove o elemento
 * fullscreen (`dialogRef`, em `binder-nav-view.tsx`) para o "top layer" do
 * browser — SÓ o que está DENTRO da subárvore desse elemento é composto
 * nessa superfície; `document.body` continua existindo no DOM, mas deixa
 * de ser pintado enquanto outro elemento está em fullscreen. Um portal
 * hardcoded para `document.body` (fora da subárvore de `dialogRef`)
 * simplesmente para de aparecer nesse estado — causa raiz confirmada, não
 * suposta (mesma lógica que já explica por que os outros portais do
 * Binder — botão da Bandeja, Tool Rail — NUNCA tiveram esse problema: os
 * dois portalam para nós (`trayPortalNode`/`toolRailPortalNode`) que já
 * vivem DENTRO da subárvore de `dialogRef`, não em `document.body`).
 * CORREÇÃO — `document.fullscreenElement ?? document.body` como alvo do
 * portal, lido no momento do render: quando HÁ um elemento em fullscreen
 * (sempre `dialogRef` neste app, mas o código não precisa saber disso —
 * só precisa perguntar ao browser), o menu portala para DENTRO dele
 * (mesma subárvore promovida ao top layer, volta a ser pintado); fora de
 * fullscreen, `document.fullscreenElement` é `null` e o comportamento
 * cai exatamente no de sempre (`document.body`). Reaproveita a MESMA API
 * nativa que `binder-nav-view.tsx` já usa para gerenciar fullscreen — nenhuma
 * infraestrutura nova, nenhum prop novo passado por `SlotsGrid`/
 * `BinderSlotFull`/`FilledSlotQuickActions` (evitaria alterar a assinatura
 * de três componentes só para repassar um booleano que o próprio browser já
 * expõe globalmente), nenhuma segunda implementação do menu — é o MESMO
 * `SlotOverflowMenu`, só o alvo do portal responde ao estado real de
 * fullscreen. `position: fixed`/`getBoundingClientRect()` continuam
 * corretos sem nenhum ajuste: o elemento fullscreen ocupa exatamente o
 * viewport inteiro, então as coordenadas calculadas em viewport continuam
 * batendo com a posição real do botão.
 *
 * Direção (cima/baixo): calculada dinamicamente a partir do espaço
 * disponível abaixo do botão no momento do clique (`window.innerHeight -
 * rect.bottom`) — como a cápsula de quick actions já fica perto da base de
 * cada carta, e o grid pode posicionar qualquer carta em qualquer altura
 * da viewport, um menu de altura fixa (~84px estimados) simplesmente abre
 * para cima quando não há espaço suficiente abaixo, mesmo racional (mais
 * simples, sem realocação em scroll) já usado por `TraySurface`.
 *
 * Teclado — pedido explícito: Tab alcança o botão "…" (elemento nativo);
 * Enter/Espaço abre (comportamento nativo de `<button>`); ao abrir, foco
 * move para o primeiro item (`role="menu"`/`role="menuitem"`, padrão WAI-
 * ARIA de menu); ArrowUp/ArrowDown alternam foco entre os dois itens (só
 * dois, então um toggle simples resolve sem precisar de um índice
 * genérico); Esc fecha e devolve o foco ao botão "…" (quando ele ainda
 * existe — ver guarda `isConnected`, mesmo padrão já usado por
 * `handleClosePicker` em `binder-pages-nav.tsx`); clique/toque fora fecha
 * sem devolver foco (mesmo padrão do clique-fora de `selectedSlotId` em
 * `binder-pages-nav.tsx`); scroll/resize da janela também fecha (o painel
 * é `position: fixed` calculado uma única vez na abertura — sem isso,
 * rolar o diálogo enquanto o menu está aberto deixaria a posição
 * desalinhada do botão).
 *
 * "Remover" preserva a semântica de Lock já corrigida em BINDER-
 * MULTISELECT-BULK-02 ("slot locked não permite Remove") — item vem
 * `disabled`, sem confirmação, simplesmente indisponível.
 */
const OVERFLOW_MENU_WIDTH_PX = 168;

function SlotOverflowMenu({
  isMultiSelected,
  isLocked,
  onToggleMultiSelect,
  onRemove,
}: {
  isMultiSelected: boolean;
  isLocked: boolean;
  onToggleMultiSelect: () => void;
  onRemove: () => void;
}) {
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);
  const selectItemRef = useRef<HTMLButtonElement | null>(null);
  const removeItemRef = useRef<HTMLButtonElement | null>(null);
  const [menuStyle, setMenuStyle] = useState<{ top?: number; bottom?: number; left: number } | null>(null);

  const close = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    if (restoreFocus) {
      requestAnimationFrame(() => {
        if (triggerRef.current?.isConnected) triggerRef.current.focus();
      });
    }
  }, []);

  const openMenu = useCallback(() => {
    const btn = triggerRef.current;
    if (!btn || typeof window === "undefined") return;
    const rect = btn.getBoundingClientRect();
    const MARGIN = 8;
    const ESTIMATED_HEIGHT = 84;
    const openUpward = window.innerHeight - rect.bottom < ESTIMATED_HEIGHT + MARGIN;
    const left = Math.min(Math.max(MARGIN, rect.right - OVERFLOW_MENU_WIDTH_PX), window.innerWidth - OVERFLOW_MENU_WIDTH_PX - MARGIN);
    setMenuStyle(openUpward ? { bottom: window.innerHeight - rect.top + 4, left } : { top: rect.bottom + 4, left });
    setOpen(true);
  }, []);

  useEffect(() => {
    if (!open) return;
    selectItemRef.current?.focus();
    function handlePointerDown(event: PointerEvent) {
      const target = event.target as Node;
      if (menuRef.current?.contains(target) || triggerRef.current?.contains(target)) return;
      close(false);
    }
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.stopPropagation();
        close(true);
      }
    }
    function handleDismiss() {
      close(false);
    }
    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown, true);
    window.addEventListener("scroll", handleDismiss, true);
    window.addEventListener("resize", handleDismiss);
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown, true);
      window.removeEventListener("scroll", handleDismiss, true);
      window.removeEventListener("resize", handleDismiss);
    };
  }, [open, close]);

  const handleMenuKeyDown = useCallback((event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const onRemoveItem = document.activeElement === removeItemRef.current;
      (onRemoveItem ? selectItemRef : removeItemRef).current?.focus();
    }
  }, []);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={(event) => {
          event.stopPropagation();
          if (open) close(false);
          else openMenu();
        }}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Mais ações"
        title="Mais ações"
        className={cn(
          "flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full text-white/70 transition-colors active:scale-90",
          open ? "bg-white/15 text-white" : "hover:bg-white/15 hover:text-white",
          FOCUS_RING,
        )}
      >
        <MoreHorizontal className="h-2.5 w-2.5" aria-hidden />
      </button>
      {open &&
        menuStyle &&
        typeof document !== "undefined" &&
        createPortal(
          <div
            ref={menuRef}
            role="menu"
            aria-orientation="vertical"
            aria-label="Mais ações do slot"
            onKeyDown={handleMenuKeyDown}
            className="fixed z-[75] rounded-[10px] p-1"
            style={{
              ...menuStyle,
              width: OVERFLOW_MENU_WIDTH_PX,
              background: "hsl(0 0% 6% / 0.97)",
              boxShadow: [
                "0 12px 28px -8px rgba(0,0,0,0.65)",
                "inset 0 1px 0 hsl(0 0% 100% / 0.08)",
                "0 0 0 1px hsl(0 0% 100% / 0.08)",
              ].join(", "),
              backdropFilter: "blur(6px)",
            }}
          >
            <button
              ref={selectItemRef}
              type="button"
              role="menuitem"
              onClick={(event) => {
                event.stopPropagation();
                onToggleMultiSelect();
                close(true);
              }}
              className={cn(
                "flex w-full items-center gap-2 rounded-[6px] px-2.5 py-1.5 text-left text-[11px] font-medium text-white/85 transition-colors hover:bg-white/10 sm:text-xs",
                "focus:outline-none focus-visible:bg-white/10",
              )}
            >
              {isMultiSelected ? (
                <CircleCheck className="h-3 w-3 flex-shrink-0" aria-hidden />
              ) : (
                <Circle className="h-3 w-3 flex-shrink-0" aria-hidden />
              )}
              {isMultiSelected ? "Remover da seleção" : "Selecionar"}
            </button>
            <button
              ref={removeItemRef}
              type="button"
              role="menuitem"
              disabled={isLocked}
              aria-disabled={isLocked || undefined}
              title={isLocked ? "Remover do slot (desbloqueie o slot)" : "Remover do slot"}
              onClick={(event) => {
                event.stopPropagation();
                if (isLocked) return;
                onRemove();
                // BINDER-QUICK-ACTIONS-DENSITY-01 — sem `restoreFocus`: o
                // slot deixa de estar preenchido no próximo render (a
                // cápsula inteira, incluindo este botão "…", pode remontar/
                // sumir), então não faz sentido tentar devolver foco a um
                // trigger que pode não existir mais.
                close(false);
              }}
              className={cn(
                "mt-0.5 flex w-full items-center gap-2 rounded-[6px] px-2.5 py-1.5 text-left text-[11px] font-medium transition-colors sm:text-xs",
                "focus:outline-none",
                isLocked
                  ? "cursor-not-allowed text-white/25"
                  : "text-red-400/90 hover:bg-red-500/15 hover:text-red-400 focus-visible:bg-red-500/15",
              )}
            >
              <Trash2 className="h-3 w-3 flex-shrink-0" aria-hidden />
              Remover do slot
            </button>
          </div>,
          // BINDER-FULLSCREEN-QUICK-ACTIONS-01 — ver doc-comment do
          // componente. `document.fullscreenElement` é o nó promovido ao
          // top layer quando a Tela Cheia está ativa; sem fullscreen é
          // `null` e cai no `document.body` de sempre.
          document.fullscreenElement ?? document.body,
        )}
    </>
  );
}

export function EmptySlotQuickActions({ onAddCard }: { onAddCard: (triggerEl: HTMLElement) => void }) {
  return (
    <div className="pointer-events-auto absolute inset-x-0 bottom-[7%] flex items-center justify-center gap-1">
      <button
        type="button"
        onClick={(event) => {
          event.stopPropagation();
          onAddCard(event.currentTarget);
        }}
        aria-label="Adicionar carta"
        title="Adicionar carta"
        className={cn(
          "flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[9px] font-medium text-white/80 transition-colors active:scale-95 hover:bg-white/10 hover:text-white sm:text-[10px]",
          FOCUS_RING,
        )}
      >
        <Plus className="h-2.5 w-2.5" aria-hidden />
        Adicionar carta
      </button>
      {/* Espaço reservado para a futura ação "Adicionar imagem" — sem lógica
          real ainda (pedido explícito: "não precisa implementar lógica real
          ainda"), só o espaço/affordance visual. */}
      <QuickActionButton icon={ImagePlus} label="Adicionar imagem (em breve)" disabled />
    </div>
  );
}

export function FilledSlotQuickActions({
  isFavorite,
  isLocked,
  isMultiSelected,
  onReplace,
  onRemove,
  onToggleFavorite,
  onToggleLock,
  onToggleMultiSelect,
  dragHandle,
}: {
  isFavorite: boolean;
  isLocked: boolean;
  /** BINDER-MULTISELECT-BULK-01 — este slot participa da seleção múltipla (Bulk Actions), não a seleção única de `selectedSlotId`. */
  isMultiSelected: boolean;
  /** BINDER-ADD-REPLACE-CARD-01 — abre o Card Picker em modo substituição; precisa do trigger para restaurar foco ao fechar. */
  onReplace: (triggerEl: HTMLElement) => void;
  onRemove: () => void;
  onToggleFavorite: () => void;
  onToggleLock: () => void;
  /** BINDER-MULTISELECT-BULK-01 — entrada/saída explícita e acessível da seleção múltipla (não depende de Ctrl/Cmd+click). */
  onToggleMultiSelect: () => void;
  /** BINDER-DND-01 — alça de arrastar, ver `DragHandleButton` acima. */
  dragHandle: { disabled: boolean; attributes?: DraggableAttributes; listeners?: DraggableSyntheticListeners; setActivatorNodeRef?: (element: HTMLElement | null) => void };
}) {
  // BINDER-MULTISELECT-UX-01 (2026-08-29) — a alça de arrastar só aparece
  // fora do modo multi-select (ver doc-comment do arquivo, seção BULK-02→
  // UX-01): quem decide se esta cápsula inteira renderiza ou não é o CALL
  // SITE (`binder-slot-full.tsx`), que já não renderiza
  // `<FilledSlotQuickActions>` nenhuma quando `isMultiSelectActive` — este
  // componente não precisa mais saber disso.
  //
  // BINDER-QUICK-ACTIONS-DENSITY-01 (2026-08-29) — HIERARQUIA DE AÇÕES,
  // pedido explícito de Fabrício: a barra tinha ações demais e excedia a
  // largura da carta ("não tentar resolver comprimindo excessivamente
  // ícones/padding... corrigir por hierarquia"). Nova composição visível:
  // alça de arrastar, separador, Favorite, Lock/Unlock, Replace, botão
  // overflow "…" — SEM separador extra antes do overflow (ele já é
  // visualmente distinto por ser o último elemento e ter ícone diferente,
  // um separador ali só adicionaria ruído sem necessidade). "Selecionar" e
  // "Remover" migraram para dentro do menu de overflow
  // (`SlotOverflowMenu`, acima) — menos frequentes (Selecionar) ou
  // destrutivo (Remover), exatamente o racional pedido. Ctrl/Cmd+click na
  // carta continua funcionando normalmente para entrar em multi-select
  // (lógica em `binder-slot-full.tsx`, intocada nesta rodada — só a UI da
  // barra mudou). Replace/Remove continuam desabilitados quando `isLocked`
  // (correção de semântica de BULK-02, preservada; Remove agora vive
  // dentro do `SlotOverflowMenu`, ver lá).
  return (
    <div className="pointer-events-auto absolute inset-x-0 bottom-[7%] flex items-center justify-center">
      <div
        className="flex items-center gap-0.5 rounded-full px-1 py-0.5"
        style={{
          background: "hsl(0 0% 0% / 0.62)",
          boxShadow: "0 2px 8px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.06)",
        }}
      >
        <DragHandleButton
          disabled={dragHandle.disabled}
          attributes={dragHandle.attributes}
          listeners={dragHandle.listeners}
          setActivatorNodeRef={dragHandle.setActivatorNodeRef}
        />
        <div className="mx-0.5 h-3 w-px flex-shrink-0" style={{ background: "hsl(0 0% 100% / 0.14)" }} aria-hidden />
        <QuickActionButton
          icon={Heart}
          label={isFavorite ? "Desfavoritar carta" : "Favoritar carta"}
          onClick={onToggleFavorite}
          active={isFavorite}
          activeTone="favorite"
        />
        <QuickActionButton
          icon={isLocked ? Lock : LockOpen}
          label={isLocked ? "Desbloquear slot" : "Bloquear slot"}
          onClick={onToggleLock}
          active={isLocked}
          activeTone="lock"
        />
        {/* BINDER-MULTISELECT-BULK-02 — Locked impede Replace (correção de
            semântica: "Locked = proteção do layout, não pode ter sua
            composição alterada"). Sem confirmação — a ação fica
            simplesmente indisponível quando bloqueada. */}
        <QuickActionButton
          icon={Repeat}
          label={isLocked ? "Substituir carta (desbloqueie o slot)" : "Substituir carta"}
          onClick={onReplace}
          disabled={isLocked}
        />
        <SlotOverflowMenu
          isMultiSelected={isMultiSelected}
          isLocked={isLocked}
          onToggleMultiSelect={onToggleMultiSelect}
          onRemove={onRemove}
        />
      </div>
    </div>
  );
}
