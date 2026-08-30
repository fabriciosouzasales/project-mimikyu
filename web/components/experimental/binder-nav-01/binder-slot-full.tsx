"use client";

import { useDndContext, useDraggable, useDroppable } from "@dnd-kit/core";
import { Check, Heart, Lock } from "lucide-react";
import { useCallback } from "react";
import type { BinderSlotData, RealCardData } from "@/app/experimental/binder-nav-01/mock-data";
import { MockCardFace } from "@/components/experimental/binder-spike/mock-card-face";
import { cn } from "@/lib/utils";
import { RealCardFace } from "./real-card-face";
import { EmptySlotQuickActions, FilledSlotQuickActions } from "./slot-quick-actions";

/**
 * Variante local de `BinderSlot` (`binder-spike/binder-slot.tsx`) para o
 * BINDER-NAV-01 — pedido de Fabrício, 2026-08-28: "a carta deve ocupar 100%
 * do plástico do slot". O `BinderSlot` original reserva uma margem
 * (`inset-[4%] top-[3%]`) simulando a borda do bolso de PVC ao redor da
 * carta; aqui a carta preenche o bolso de ponta a ponta (`inset-0`) — mais
 * evidência/protagonismo para a carta, pedido explícito desta rodada.
 *
 * Cópia local, não edição do componente compartilhado: `binder-slot.tsx`
 * continua servindo Binder-First/BINDER-VIS-02 exatamente como estava
 * (isolamento experimental total, mesmo padrão já aplicado a
 * `cover-panel.tsx`/`binder-pages-nav.tsx`). Mesma lógica de bolso vazio,
 * abertura no topo e reflexo de plástico — só o preenchimento da carta
 * ocupada muda.
 *
 * Teste ME2 (mesma data) — `slot.card` agora pode ser a carta fictícia
 * (`MockCardData`, SVG sintético) ou uma carta REAL do ME2 (`RealCardData`,
 * artwork do Supabase via `RealCardFace`) — discriminado por `"imageUrl" in
 * slot.card`, já que só `RealCardData` tem esse campo.
 *
 * BINDER-INTERACTION-01 (2026-08-28) — quick actions contextuais por slot
 * (pedido completo de Fabrício, ver `slot-quick-actions.tsx`). O slot deixa
 * de ser puramente presentacional:
 *  - Container agora é `role="group"` + `tabIndex=0`, focável e clicável —
 *    clicar/Enter/Space alterna o estado SELECIONADO (`isSelected`, estado
 *    vem de cima, de `binder-pages-nav.tsx`, para ser efetivamente único por
 *    spread e permitir um único listener de clique-fora). Selecionar NÃO
 *    executa nenhuma ação — só revela/prende a toolbar; quem executa ações
 *    são os botões da própria toolbar (evita ambiguidade "selecionar vs.
 *    adicionar").
 *  - Visibilidade da toolbar = hover OU focus-within (100% CSS, via
 *    `group-hover`/`group-focus-within` — sem JS, sem custo, e sem risco de
 *    "foco chega num botão invisível": `:focus-within` casa no MESMO reflow
 *    em que o botão recebe foco) OU selecionado (classe condicional via
 *    JS, já que precisa sobreviver ao mouse saindo do slot). Isso cobre
 *    diretamente "em mobile, tap deve substituir hover" — o tap já dispara
 *    onClick → seleciona → toolbar aparece, sem depender de :hover.
 *  - Selo de favorito (Card, não Card Variant — `isFavorite` resolvido pelo
 *    pai a partir de `card.id`) fica visível permanentemente quando
 *    favoritado, independente de hover/seleção — sem isso a ação de
 *    favoritar pareceria não ter feito nada assim que o mouse sai do slot.
 *  - Anel de seleção dourado (mesmo tom do focus ring do resto da rota)
 *    para "deixar estado selecionado claro" (item 4 do pedido).
 *  - `prefers-reduced-motion`: já coberto pela regra global em
 *    `globals.css` (`transition-duration: 0.01ms !important` sob o media
 *    query) — nenhuma lógica adicional necessária aqui.
 *
 * CARD-DETAIL-01 (2026-08-29) — pedido de Fabrício: "Binder = contexto de
 * organização; Card Detail = contexto de informação da carta... ao clicar
 * diretamente em uma carta ocupando um slot, abrir um modal de detalhes."
 * Duas mudanças aqui, ambas escopadas a slot OCUPADO:
 *  - A própria arte da carta (o `<div>` que renderiza `RealCardFace`/
 *    `MockCardFace`, ocupando 100% do bolso) virou um elemento focável e
 *    clicável (`role="button"`), com `stopPropagation()` no click/Enter/
 *    Space para NÃO também disparar `onSelectToggle` do grupo pai — clicar
 *    na carta abre o Card Detail (`onOpenDetail`), não seleciona o slot.
 *  - A camada de quick actions (linha ~217 abaixo) tinha `absolute inset-0`
 *    — cobria o slot INTEIRO com `pointer-events-auto` assim que
 *    hover/focus-within ficava verdadeiro, mesmo a cápsula visível
 *    ocupando só uma faixa estreita perto da base. Isso bloqueava
 *    completamente o clique na carta em qualquer slot com o mouse em cima
 *    (que é o estado normal um instante antes de qualquer clique no
 *    desktop). Corrigido para `inset-x-0 bottom-0 h-[30%]` (mesma altura já
 *    usada pelo vinhetado logo acima) — a cápsula continua exatamente onde
 *    estava (ela mesma já é `bottom-[7%]`, bem dentro dessa faixa), só a
 *    área INVISÍVEL que capturava cliques encolheu para não competir com a
 *    arte da carta. Sem essa correção, "clicar na carta abre o Card Detail"
 *    simplesmente não funcionava em desktop.
 *  - Consequência aceita (documentada, não uma omissão): em touch/mobile,
 *    sem hover, tocar a carta agora abre o Card Detail diretamente em vez
 *    de "selecionar" o slot primeiro. As quick actions (Substituir/Remover/
 *    Favoritar) continuam alcançáveis em mobile porque o próprio elemento
 *    da carta é `tabIndex=0` — tocar nele move o foco do teclado para ele,
 *    o que já satisfaz `:focus-within` no slot pai e revela a cápsula (CSS
 *    puro, ver bloco de quick actions abaixo) — inclusive depois de fechar
 *    o Card Detail, já que o foco retorna para esse mesmo elemento
 *    (restaurado por `binder-pages-nav.tsx`).
 *
 * Rodada visual (2026-08-28, mesma data) — pedido de Fabrício: "as quick
 * actions funcionam conceitualmente, mas precisam de uma rodada visual
 * curta... diferenciar claramente hover/focus, selecionado e ação ativa. O
 * estado selecionado deve pertencer ao SLOT inteiro, não parecer apenas
 * seleção de um ícone." Mudanças (sem nenhuma função nova):
 *  - Novo anel de hover/focus, neutro (branco 35%) e mais fino que o de
 *    seleção — dá feedback ao passar/focar SEM ser confundido com
 *    "selecionado". Fica escondido quando `isSelected` para não empilhar
 *    dois contornos ao mesmo tempo.
 *  - Seleção ganhou um TINT translúcido (dourado, 5% de alfa) cobrindo o
 *    slot inteiro, além do anel — o objetivo explícito de Fabrício era que
 *    o estado pertencesse ao retângulo inteiro, não só à borda.
 *  - O vinhetado atrás das quick actions encolheu bastante (de uma faixa
 *    forte cobrindo boa parte da altura para um degradê baixo e suave) —
 *    a cápsula/rótulo de `slot-quick-actions.tsx` já trazem contraste
 *    próprio; isto é só o mínimo de apoio para legibilidade contra fundos
 *    claros.
 *
 * BINDER-QUICK-ACTIONS-01 (2026-08-29) — pedido explícito de Fabrício:
 *  - Nova ação Lock/Unlock: `isLocked`/`onToggleLock`, referenciando o SLOT
 *    físico (não a Card, ao contrário do favorito) — proteção de LAYOUT
 *    (futuro auto-arrange/push/insert), não lock patrimonial de Inventory.
 *  - Selo persistente de Lock (canto superior ESQUERDO, espelhando o selo
 *    de favorito no canto superior direito) — mesmo racional do favorito:
 *    sem um selo persistente, não haveria como saber que um slot está
 *    bloqueado sem passar o mouse/focar nele toda vez. Tom azul-frio,
 *    distinto do vermelho do favorito e do dourado de seleção/foco (regra
 *    explícita: "dourado permanece reservado à identidade/foco/premium").
 *  - Selo de favorito trocou de dourado para VERMELHO (mesma regra) —
 *    preenchido (`fill="currentColor"`) quando ativo, igual antes, só a cor
 *    base mudou.
 *
 * BINDER-QUICK-ACTIONS-01, revisão de posicionamento (2026-08-29, mesma
 * data) — Fabrício testou a primeira versão localmente (toolbar vertical
 * lateral, zona `inset-y-0 right-0 w-[30%]`) e pediu reversão do
 * posicionamento: "prefiro o menu de ações rápidas na parte inferior da
 * carta, não na lateral" — preserva a carta como protagonista, cria
 * consistência com o slot vazio (que já usa "Adicionar carta" na base) e
 * evita uma coluna lateral competindo visualmente com a carta. A zona de
 * interação/vinhete do slot OCUPADO voltou a `inset-x-0 bottom-0 h-[30%]`,
 * exatamente a mesma região já usada pelo slot vazio — só o
 * posicionamento mudou; lógica/estado/cores/ordem das ações (Favorite,
 * Lock, Replace, separador, Remove) são as mesmas da revisão anterior (ver
 * `slot-quick-actions.tsx`).
 *
 * BINDER-DND-01 (2026-08-29) — Drag and Drop, mecanismo oficial de MOVE
 * (pedido explícito: "não criar botão 'Move' nas Quick Actions"). `useDraggable`/
 * `useDroppable` (`@dnd-kit/core`) vivem AQUI, não em `SlotsGrid` — regra do
 * React (Hooks só podem ser chamados dentro de um componente de verdade,
 * nunca dentro do `.map()` de `SlotsGrid`), e este componente já é
 * instanciado uma vez por slot renderizado.
 *
 *  - Este slot é DROPPABLE sempre que não está Locked (`useDroppable({id:
 *    slot.id, disabled: isLocked, data: {card: realCard}})`) — vazio ou
 *    ocupado, os dois aceitam drop (vazio = MOVE, ocupado = SWAP, decidido
 *    em `binder-pages-nav.tsx`/`handleDragEnd`, não aqui).
 *  - Este slot é DRAGGABLE só quando ocupado, não Locked, e a carta é uma
 *    `RealCardData` de verdade (`"imageUrl" in slot.card` — `MockCardData`
 *    não é suportado por este spike de DnD, ver `card-picker-mock.ts` para o
 *    mesmo tipo de fronteira já aplicada ao Picker).
 *  - `setNodeRef` de drag e de drop apontam para o MESMO nó (o slot
 *    inteiro) — quem ativa o gesto não é a arte da carta nem o slot
 *    inteiro, é a alça dedicada `DragHandleButton`
 *    (`slot-quick-actions.tsx`, via `setActivatorNodeRef`). Isso resolve
 *    clique-abre-detalhe × arrastar-move SEM heurística de limiar: a arte
 *    da carta continua com só o `onClick` de sempre (`CARD-DETAIL-01`,
 *    intocado nesta rodada).
 *  - `isDragging` reduz a opacidade da ORIGEM (pedido: "slot origem pode
 *    reduzir opacidade"); o preview que o usuário vê seguindo o
 *    ponteiro/dedo é o `DragOverlay` global de `binder-pages-nav.tsx`, não
 *    este nó (que fica "para trás", semitransparente, no lugar de origem).
 *  - `isOver` (só verdadeiro para o slot que o dnd-kit está considerando
 *    como destino válido no momento) acende um highlight discreto,
 *    dourado/foco — mesma paleta já usada para seleção, "dourado apenas se
 *    coerente com foco" (pedido explícito).
 *  - `useDndContext().active` diz se HÁ algum arrasto em andamento no
 *    Binder inteiro (não só neste slot) — usado só para o slot Locked
 *    mostrar um selo "bloqueado" discreto ENQUANTO um arrasto está
 *    ativo em qualquer lugar (não é viável, com os hooks padrão do
 *    dnd-kit, saber com precisão "o ponteiro está sobre ESTE slot
 *    bloqueado especificamente" sem duplicar a detecção de colisão — ver
 *    relatório de implementação para o racional completo).
 *
 * BINDER-MULTISELECT-BULK-01 (2026-08-29) — seleção múltipla para Bulk
 * Actions, pedido explícito de Fabrício: "Não quero um 'modo
 * administrativo'. O Binder deve continuar sendo protagonista." Distinta da
 * seleção única `isSelected`/`onSelectToggle` já existente (que só revela a
 * cápsula de quick actions e nunca sai desse papel) — `isMultiSelected`
 * representa participação no `multiSelectedSlotIds` do pai
 * (`binder-pages-nav.tsx`), usado pela Bulk Action Bar. As duas seleções são
 * independentes e podem coexistir no mesmo slot sem conflito (mesma cor —
 * dourado é o tom de seleção/foco reservado do MMKYU — mas o selo de check
 * abaixo é o que efetivamente as distingue).
 *
 *  - Entrada/saída: (a) Ctrl/Cmd+click OU Enter/Espaço com Ctrl/Cmd na
 *    própria arte da carta (atalho de desktop); (b) enquanto HÁ seleção
 *    múltipla ativa em qualquer slot do spread (`isMultiSelectActive`),
 *    clicar em QUALQUER carta alterna a seleção dela em vez de abrir Card
 *    Detail — pedido explícito ("clicar em outro slot alterna seleção em
 *    vez de abrir Card Detail" enquanto o modo está ativo); (c) a nova
 *    Quick Action "Selecionar" (`slot-quick-actions.tsx`) — entrada
 *    explícita e acessível, não depende de hover/modificador de teclado,
 *    funciona igual em mobile. Um clique comum, sem modificador e sem
 *    seleção múltipla ativa, continua abrindo Card Detail exatamente como
 *    antes (`CARD-DETAIL-01`, comportamento default preservado).
 *  - Selo (badge) persistente no canto INFERIOR esquerdo — canto que
 *    restava livre (superior-esquerdo = Lock, superior-direito =
 *    Favorite) — ícone de check sobre fundo dourado sólido, sempre visível
 *    quando `isMultiSelected`, independente de hover/foco: é o indicador
 *    PRIMÁRIO e não depende de cor (requisito explícito de a11y — "não
 *    depender só de cor para indicar seleção"). O anel/tint dourado abaixo
 *    é reforço visual, não a única pista.
 *  - `aria-selected` no `role="group"` do slot como sinalização adicional
 *    para tecnologia assistiva (mesmo que `group` não seja, a rigor, um
 *    role com estado de seleção na especificação ARIA — "equivalente
 *    discreto" pedido explicitamente) — o `aria-label` do grupo também
 *    ganha o sufixo "(selecionada para ação em lote)" como reforço textual
 *    garantido de ser anunciado independente do mapeamento de role.
 */

const SHEEN =
  "linear-gradient(115deg, hsl(0 0% 100% / 0.2) 0%, transparent 32%, transparent 68%, hsl(0 0% 100% / 0.06) 100%)";

export function BinderSlotFull({
  slot,
  isSelected,
  isFavorite,
  isLocked,
  isMultiSelected,
  isMultiSelectActive,
  onSelectToggle,
  onAddCard,
  onOpenDetail,
  onReplace,
  onRemove,
  onToggleFavorite,
  onToggleLock,
  onToggleMultiSelect,
}: {
  slot: BinderSlotData;
  isSelected: boolean;
  isFavorite: boolean;
  isLocked: boolean;
  /** BINDER-MULTISELECT-BULK-01 — este slot participa da seleção múltipla (Bulk Actions). */
  isMultiSelected: boolean;
  /** BINDER-MULTISELECT-BULK-01 — HÁ seleção múltipla ativa em algum slot do spread (não necessariamente este) — muda o comportamento de clique na carta. */
  isMultiSelectActive: boolean;
  onSelectToggle: () => void;
  /** BINDER-ADD-REPLACE-CARD-01 — abre o Card Picker em modo adicionar. */
  onAddCard: (triggerEl: HTMLElement) => void;
  onOpenDetail: (triggerEl: HTMLElement) => void;
  /** BINDER-ADD-REPLACE-CARD-01 — abre o Card Picker em modo substituição. */
  onReplace: (triggerEl: HTMLElement) => void;
  onRemove: () => void;
  onToggleFavorite: () => void;
  onToggleLock: () => void;
  /** BINDER-MULTISELECT-BULK-01 — alterna a participação deste slot em `multiSelectedSlotIds`. */
  onToggleMultiSelect: () => void;
}) {
  const cardName = slot.card?.name;
  const groupLabel = `${slot.filled && cardName ? `Carta: ${cardName}` : "Slot vazio"}${isSelected ? " (selecionado)" : ""}${isMultiSelected ? " (selecionada para ação em lote)" : ""}`;

  // BINDER-DND-01 — ver doc-comment do arquivo. `realCard` é a fronteira
  // explícita: só cartas reais (`RealCardData`) participam do DnD nesta
  // rodada, mesmo racional já aplicado ao Card Picker.
  const realCard: RealCardData | undefined = slot.card && "imageUrl" in slot.card ? slot.card : undefined;
  // BINDER-MULTISELECT-UX-01 (2026-08-29) — Multi-drag não existe nesta V1;
  // pedido explícito de Fabrício: "quando multiSelectedSlotIds.size > 0...
  // impedir início de drag individual... não mostrar affordance de DnD" (a
  // affordance em si — a alça — deixa de renderizar mais abaixo, ver zona
  // de quick actions). Aqui, `!isMultiSelectActive` desliga o próprio
  // `useDraggable` do dnd-kit (não só a UI): mesmo se algo tentasse
  // arrastar sem passar pela alça, o gesto não teria efeito. Ao limpar a
  // seleção, `isMultiSelectActive` volta a `false` e o drag volta a
  // funcionar exatamente como antes — nenhuma mudança na mecânica do
  // dnd-kit fora deste estado.
  const isDraggable = slot.filled && !isLocked && !!realCard && !isMultiSelectActive;
  const {
    attributes: dragAttributes,
    listeners: dragListeners,
    setNodeRef: setDragNodeRef,
    setActivatorNodeRef,
    isDragging,
  } = useDraggable({
    id: slot.id,
    disabled: !isDraggable,
    data: isDraggable ? { card: realCard } : undefined,
  });
  const { setNodeRef: setDropNodeRef, isOver } = useDroppable({
    id: slot.id,
    disabled: isLocked,
    data: { card: realCard },
  });
  const setNodeRef = useCallback(
    (node: HTMLDivElement | null) => {
      setDragNodeRef(node);
      setDropNodeRef(node);
    },
    [setDragNodeRef, setDropNodeRef],
  );
  const { active: anyActiveDrag } = useDndContext();
  const showLockedDuringDrag = isLocked && !!anyActiveDrag;
  const showValidDropHighlight = isOver && !isLocked && !isDragging;

  return (
    <div
      ref={setNodeRef}
      role="group"
      aria-label={groupLabel}
      aria-selected={isMultiSelected}
      tabIndex={0}
      onClick={onSelectToggle}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onSelectToggle();
        }
      }}
      className={cn(
        // BINDER-CARD-ASPECT-RATIO-01 — era `aspect-[5/7]` (0.714286), um
        // valor assumido de "carta de trading card" que nunca correspondeu
        // ao asset real do ME2. Medição direta dos arquivos servidos pelo
        // Storage (`card-front/me2/pt-BR/001.webp` e `013.webp`) confirmou
        // 600×825px = 8:11 exato (0.727273) nas duas cartas checadas. O
        // slot agora usa a proporção real do asset — com `object-fit:
        // cover` (padrão de `RealCardFace`) o corte residual passa a ser
        // zero em vez do ~1,8% de largura que a proporção errada forçava.
        "group/slot relative aspect-[8/11] cursor-pointer overflow-hidden rounded-[4px] outline-none transition-transform duration-150",
        "focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/70",
      )}
      style={{
        background: slot.filled ? "hsl(0 0% 3% / 0.4)" : "hsl(0 0% 0% / 0.32)",
        boxShadow: [
          "inset 1px 1px 0 hsl(0 0% 100% / 0.14)",
          "inset -1px -1px 0 hsl(0 0% 0% / 0.4)",
          "inset 0 3px 7px rgba(0,0,0,0.55)",
        ].join(", "),
        // BINDER-DND-01 — origem de um drag em andamento fica semitransparente
        // ("slot origem pode reduzir opacidade", pedido explícito); o que o
        // usuário vê seguindo o ponteiro é o `DragOverlay` global de
        // `binder-pages-nav.tsx`, não este nó. BINDER-MULTISELECT-UX-01 —
        // segunda regra de opacidade, mutuamente exclusiva da primeira (DnD
        // já fica desligado durante multi-select, `isDragging` nunca é
        // `true` nesse estado): cartas OCUPADAS que não fazem parte da
        // seleção ficam levemente atenuadas enquanto o modo está ativo —
        // "ser óbvio, sem ler texto, quais cartas fazem parte da seleção"
        // (pedido explícito). Slots vazios e a própria carta selecionada
        // nunca são atenuados.
        opacity: isDragging ? 0.35 : isMultiSelectActive && slot.filled && !isMultiSelected ? 0.7 : 1,
      }}
    >
      {!slot.filled && (
        <div
          className="pointer-events-none absolute inset-[10%]"
          style={{
            backgroundImage:
              "repeating-linear-gradient(0deg, hsl(0 0% 100% / 0.03) 0px, hsl(0 0% 100% / 0.03) 1px, transparent 1px, transparent 6px)",
          }}
          aria-hidden
        />
      )}

      {slot.filled && slot.card && (
        <div
          role="button"
          tabIndex={0}
          aria-label={
            isMultiSelectActive || isMultiSelected
              ? `${isMultiSelected ? "Remover da seleção" : "Selecionar"}: ${cardName ?? "carta"}`
              : `Ver detalhes de ${cardName ?? "carta"}`
          }
          onClick={(event) => {
            event.stopPropagation();
            // BINDER-MULTISELECT-BULK-01 — Ctrl/Cmd+click SEMPRE alterna
            // seleção (atalho de desktop, independente do estado atual do
            // modo). Sem modificador, mas com seleção múltipla JÁ ativa em
            // algum slot do spread, clicar em QUALQUER carta também alterna
            // seleção em vez de abrir Card Detail — pedido explícito. Um
            // clique comum fora desses dois casos continua abrindo Card
            // Detail exatamente como antes (`CARD-DETAIL-01`, intocado).
            if (event.ctrlKey || event.metaKey || isMultiSelectActive) {
              onToggleMultiSelect();
              return;
            }
            onOpenDetail(event.currentTarget);
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              event.stopPropagation();
              if (event.ctrlKey || event.metaKey || isMultiSelectActive) {
                onToggleMultiSelect();
                return;
              }
              onOpenDetail(event.currentTarget);
            }
          }}
          className="absolute inset-0 cursor-pointer overflow-hidden outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[hsl(40_70%_62%)]"
        >
          {"imageUrl" in slot.card ? <RealCardFace card={slot.card} /> : <MockCardFace card={slot.card} />}
        </div>
      )}

      {/* Abertura do bolso — linha clara perto do topo, onde a carta é inserida. */}
      <div
        className="pointer-events-none absolute inset-x-0 top-[7%] h-[2px]"
        style={{ background: "hsl(0 0% 100% / 0.16)" }}
        aria-hidden
      />

      {/* Reflexo do plástico do bolso — por cima do conteúdo, vende "dentro do bolso". */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{ backgroundImage: SHEEN, opacity: slot.filled ? 0.35 : 0.75 }}
        aria-hidden
      />
      {/* Contorno externo do bolso — perceptível mesmo vazio. */}
      <div
        className="pointer-events-none absolute inset-0 rounded-[4px]"
        style={{ boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.1)" }}
        aria-hidden
      />

      {/* Selo de favorito — persistente, independente de hover/seleção (Card,
          não Card Variant). VERMELHO desde BINDER-QUICK-ACTIONS-01 (era
          dourado) — regra explícita: dourado fica reservado a
          identidade/foco/premium do MMKYU, nunca para Favorite.
          BINDER-MULTISELECT-UX-01 — cede o canto superior-direito para o
          selo de seleção múltipla especificamente NA carta selecionada
          (`!isMultiSelected`); em cartas não selecionadas o favorito
          continua normalmente (já fica visualmente atenuado junto com o
          resto do slot pela opacidade de "não selecionada", sem precisar
          de lógica própria de ocultação). */}
      {isFavorite && !isMultiSelected && (
        <div
          className="pointer-events-none absolute right-[6%] top-[6%] z-10 flex h-3.5 w-3.5 items-center justify-center rounded-full sm:h-4 sm:w-4"
          style={{ background: "hsl(0 0% 0% / 0.55)" }}
          aria-hidden
        >
          <Heart className="h-2 w-2 text-red-400 sm:h-2.5 sm:w-2.5" fill="currentColor" aria-hidden />
        </div>
      )}

      {/* Selo de Lock — persistente, espelha o selo de favorito no canto
          oposto. Lock é proteção de LAYOUT do slot físico (futuro
          auto-arrange/push/insert), não um lock patrimonial do Inventory —
          por isso mora no canto superior ESQUERDO, sem competir com o
          favorito (Card) no direito. Tom azul-frio, distinto do vermelho do
          favorito e do dourado de seleção/foco. */}
      {isLocked && (
        <div
          className="pointer-events-none absolute left-[6%] top-[6%] z-10 flex h-3.5 w-3.5 items-center justify-center rounded-full sm:h-4 sm:w-4"
          style={{ background: "hsl(0 0% 0% / 0.55)" }}
          aria-hidden
        >
          <Lock className="h-2 w-2 text-[hsl(205_80%_75%)] sm:h-2.5 sm:w-2.5" fill="currentColor" aria-hidden />
        </div>
      )}

      {/* Selo de seleção múltipla — BINDER-MULTISELECT-UX-01 (2026-08-29):
          movido do canto inferior-esquerdo para o SUPERIOR-DIREITO, pedido
          explícito de Fabrício ("o check pequeno atual não é suficiente...
          adicionar check circular no canto superior direito"). Ocupa o
          mesmo lugar do selo de Favorite (que cede espaço só nesta carta
          especificamente, ver bloco acima) — Lock permanece no canto
          oposto (superior-esquerdo), sem conflito. Ligeiramente maior que
          os outros dois selos (h-4/h-5 em vez de h-3.5/h-4) para ser mais
          perceptível sem virar um elemento gráfico pesado. Fundo dourado
          SÓLIDO (não translúcido) — indicador PRIMÁRIO e não dependente de
          cor isolada: o ícone de check em si já comunica "selecionada"
          mesmo em escala de cinza (requisito de a11y). `slot.filled` é
          guarda defensiva extra (item 3 do pedido, "slot vazio nunca
          mostra check") — `isMultiSelected` já não deveria ser `true` para
          um slot vazio (estruturalmente, só a arte da carta pode
          adicionar/remover de `multiSelectedSlotIds`, e agora `emptySlot`
          também limpa a seleção do slot que esvazia, ver
          `binder-pages-nav.tsx`), mas este guard elimina qualquer resíduo
          visual mesmo que o estado fique momentaneamente inconsistente. */}
      {isMultiSelected && slot.filled && (
        <div
          className="pointer-events-none absolute right-[6%] top-[6%] z-10 flex h-4 w-4 items-center justify-center rounded-full sm:h-5 sm:w-5"
          style={{ background: "hsl(40 70% 55%)", boxShadow: "0 1px 3px rgba(0,0,0,0.5)" }}
          aria-hidden
        >
          <Check className="h-2.5 w-2.5 text-black sm:h-3 sm:w-3" strokeWidth={3} aria-hidden />
        </div>
      )}

      {/* Anel de hover/focus — neutro, mais sutil que o de seleção; some
          quando selecionado para não empilhar dois contornos ao mesmo
          tempo (item 2 do pedido: hover/focus e seleção precisam ler como
          coisas diferentes). 100% CSS, sem JS. */}
      {!isSelected && !isMultiSelected && (
        <div
          className="pointer-events-none absolute inset-0 rounded-[4px] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
          style={{ boxShadow: "0 0 0 1px hsl(0 0% 100% / 0.35)" }}
          aria-hidden
        />
      )}

      {/* Seleção — tint translúcido cobrindo o slot INTEIRO + anel dourado.
          Pedido explícito: "o estado selecionado deve pertencer ao SLOT
          inteiro, não parecer apenas seleção de um ícone." */}
      {isSelected && (
        <>
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{ background: "hsl(40 70% 62% / 0.05)" }}
            aria-hidden
          />
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{ boxShadow: "0 0 0 2px hsl(40 70% 62% / 0.9), 0 0 10px 1px hsl(40 70% 62% / 0.35)" }}
            aria-hidden
          />
        </>
      )}

      {/* Seleção MÚLTIPLA (Bulk Actions) — mesmo tom dourado (é, também, uma
          seleção — vocabulário visual coerente). BINDER-MULTISELECT-UX-01
          (2026-08-29): reforçado a pedido de Fabrício ("contorno dourado
          MMKYU discreto mas claramente perceptível... opcionalmente pequena
          elevação visual") — anel um pouco mais opaco (0.65 → 0.85) e uma
          sombra de contato suave por baixo do slot, lendo como "levemente
          levantada" sem usar `transform` (evita interferir com o contexto
          3D/`perspective` dos containers pai). Ainda sem glow/neon: só tint
          + anel + sombra de contato, nunca um halo colorido. O selo de
          check (canto superior-direito, acima) continua sendo o indicador
          PRIMÁRIO; isto é reforço visual. */}
      {isMultiSelected && !isSelected && (
        <>
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{ background: "hsl(40 70% 62% / 0.06)" }}
            aria-hidden
          />
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{
              boxShadow: "0 0 0 2px hsl(40 70% 62% / 0.85), 0 6px 12px -4px rgba(0,0,0,0.45)",
            }}
            aria-hidden
          />
        </>
      )}

      {/* BINDER-DND-01 — destino válido em foco durante um arrasto: mesma
          paleta dourada de seleção/foco ("dourado apenas se coerente com
          foco", pedido explícito), nunca a origem (`!isDragging`). */}
      {showValidDropHighlight && (
        <div
          className="pointer-events-none absolute inset-0 z-20 rounded-[4px]"
          style={{
            background: "hsl(40 70% 62% / 0.12)",
            boxShadow: "0 0 0 2px hsl(40 70% 62% / 0.85), 0 0 14px 2px hsl(40 70% 62% / 0.3)",
          }}
          aria-hidden
        />
      )}

      {/* BINDER-DND-01 — recusa discreta: enquanto HÁ um arrasto em
          andamento em qualquer lugar do Binder, um slot Locked mostra uma
          textura "bloqueada" (hachura neutra, sem vermelho/neon) — "destino
          inválido claramente recusado", mas sem alarme visual. */}
      {showLockedDuringDrag && (
        <div
          className="pointer-events-none absolute inset-0 z-20 rounded-[4px]"
          style={{
            background: "hsl(0 0% 0% / 0.45)",
            backgroundImage:
              "repeating-linear-gradient(135deg, hsl(0 0% 100% / 0.06) 0px, hsl(0 0% 100% / 0.06) 2px, transparent 2px, transparent 8px)",
            boxShadow: "inset 0 0 0 1px hsl(205 40% 70% / 0.3)",
          }}
          aria-hidden
        />
      )}

      {slot.filled ? (
        <>
          {/* BINDER-MULTISELECT-UX-01 (2026-08-29) — pedido explícito de
              Fabrício: "Quick Actions individuais ficam completamente
              ocultas" durante o modo de seleção (não só a alça de
              arrastar, como a rodada anterior havia decidido — nova
              direção, ver doc-comment de `FilledSlotQuickActions`). Toda a
              zona (vinhetado de apoio + cápsula) deixa de renderizar
              quando `isMultiSelectActive`, para não sobrar um pill de
              fundo vazio flutuando sobre a carta. Entrar/sair da seleção
              de um slot específico continua funcionando sem esta zona:
              clicar na carta já alterna seleção enquanto o modo está
              ativo (ver `onClick` da arte da carta, abaixo). Ao limpar a
              seleção, esta zona volta a existir exatamente como antes. */}
          {!isMultiSelectActive && (
            <>
              {/* Vinhetado mínimo de apoio à leitura das quick actions — na
                  base (revisão de posicionamento, 2026-08-29: voltou de
                  lateral para inferior, mesma região já usada pelo slot
                  vazio). A cápsula de `slot-quick-actions.tsx` já traz
                  contraste próprio; isto é só o mínimo de apoio contra
                  fundos claros. */}
              <div
                className="pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
                style={{
                  background: "linear-gradient(0deg, hsl(0 0% 0% / 0.42) 0%, transparent 100%)",
                  ...(isSelected ? { opacity: 1 } : undefined),
                }}
                aria-hidden
              />

              {/* Quick actions do slot OCUPADO — visível em hover/focus-within
                  (CSS puro) OU seleção única (classe JS, sobrevive ao mouse
                  saindo do slot). Zona reduzida à faixa inferior (30% da
                  altura) para não competir com a carta, que permanece
                  clicável no restante do slot. */}
              <div
                className={cn(
                  "pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150",
                  "group-hover/slot:pointer-events-auto group-hover/slot:opacity-100",
                  "group-focus-within/slot:pointer-events-auto group-focus-within/slot:opacity-100",
                  isSelected && "pointer-events-auto opacity-100",
                )}
              >
                <FilledSlotQuickActions
                  isFavorite={isFavorite}
                  isLocked={isLocked}
                  isMultiSelected={isMultiSelected}
                  onReplace={onReplace}
                  onRemove={onRemove}
                  onToggleFavorite={onToggleFavorite}
                  onToggleLock={onToggleLock}
                  onToggleMultiSelect={onToggleMultiSelect}
                  dragHandle={{
                    disabled: isLocked,
                    attributes: dragAttributes,
                    listeners: dragListeners,
                    setActivatorNodeRef,
                  }}
                />
              </div>
            </>
          )}
        </>
      ) : (
        <>
          {/* Slot VAZIO — fora de escopo de BINDER-QUICK-ACTIONS-01, mantido
              exatamente como antes (faixa inferior horizontal, sem
              mudança visual ou funcional nesta rodada). */}
          <div
            className="pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
            style={{
              background: "linear-gradient(0deg, hsl(0 0% 0% / 0.4) 0%, transparent 100%)",
              ...(isSelected ? { opacity: 1 } : undefined),
            }}
            aria-hidden
          />
          <div
            className={cn(
              "pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150",
              "group-hover/slot:pointer-events-auto group-hover/slot:opacity-100",
              "group-focus-within/slot:pointer-events-auto group-focus-within/slot:opacity-100",
              isSelected && "pointer-events-auto opacity-100",
            )}
          >
            <EmptySlotQuickActions onAddCard={onAddCard} />
          </div>
        </>
      )}
    </div>
  );
}
