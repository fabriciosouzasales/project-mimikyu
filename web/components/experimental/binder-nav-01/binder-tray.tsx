"use client";

import { useDraggable, useDroppable } from "@dnd-kit/core";
import { ArrowDown, Inbox, X } from "lucide-react";
import { forwardRef, useCallback } from "react";
import type { RealCardData } from "@/app/experimental/binder-nav-01/mock-data";
import { cn } from "@/lib/utils";
import { RealCardFace } from "./real-card-face";

/**
 * BINDER-TRAY-01 (2026-08-29) — Bandeja, área temporária de manipulação do
 * Binder. Pedido explícito de Fabrício, inspirado num padrão observado no
 * benchmark PkmnBindr: complementa o DnD slot→slot/edge-navigation
 * (BINDER-DND-01) como o mecanismo PRINCIPAL para reorganizar cartas entre
 * páginas DISTANTES — a edge navigation continua existindo para páginas
 * próximas, nenhuma das duas substitui a outra.
 *
 * NÃO é uma nova entidade de domínio (pedido explícito, repetido três vezes
 * no pedido original): uma carta "na Bandeja" continua sendo o MESMO
 * Inventory Item, continua pertencendo à MESMA Collection — só o
 * `slot placement` fica temporariamente ausente. Nenhum "Tray Item"/
 * "Collection Item" paralelo, nenhuma cópia. Ver doc-comment de
 * `BinderPagesNav` em `binder-pages-nav.tsx` (seção BINDER-TRAY-01) para
 * como o estado `trayItems` se relaciona com `cardOverrides`/
 * `removedSlotIds`/`activeDrag` — a fonte de verdade real do estado mora lá;
 * este arquivo só contém a UI (botão/badge + superfície flutuante) e os
 * dois primitivos de identificação de arrasto (`trayItemDragId`/
 * `parseTrayItemDragId`), para que `binder-pages-nav.tsx` consiga distinguir
 * "arrasto originado de um slot" de "arrasto originado da Bandeja" só a
 * partir do id do `active` do dnd-kit — mesmo padrão já usado para
 * `EDGE_PREV_ID`/`EDGE_NEXT_ID`.
 *
 * Droppable único e permanente: `TRAY_DROP_ID` vive no próprio botão/badge
 * (`TrayToggleButton`), SEMPRE montado (não só quando a superfície está
 * aberta) — permite soltar uma carta na Bandeja arrastando até o badge sem
 * precisar abrir o painel primeiro (o próprio benchmark citado funciona
 * assim: o ícone da bandeja já aceita o drop). `useDroppable` não registra
 * nenhum listener de ponteiro próprio (só mede o retângulo do nó para
 * colisão) — não há conflito entre o `onClick` do botão (abrir/fechar) e o
 * `useDroppable` (só passivo), diferente do caso carta×alça de
 * `slot-quick-actions.tsx`, que precisou de um handle físico separado.
 *
 * Fechar a superfície: só por clique no botão (toggle), pelo × interno, ou
 * Esc (tratado em `binder-pages-nav.tsx`, junto do Esc que já limpa seleção
 * de slot). Deliberadamente SEM clique-fora-fecha nesta rodada: um listener
 * de `pointerdown` no documento fecharia a Bandeja no mesmo gesto que o
 * clique no PRÓPRIO botão de abrir/fechar dispara (pointerdown fecha,
 * click do mesmo toggle reabre logo em seguida — race conhecida de popover
 * sem guarda de "elemento disparador"), então preferi não implementar
 * clique-fora nesta rodada a arriscar essa combinação quebrada.
 *
 * `role="region"` (não `role="dialog"`) na superfície — é deliberadamente
 * NÃO modal: o resto do Binder continua interativo com ela aberta (dá para
 * navegar entre páginas e soltar novas cartas na Bandeja sem fechar o
 * painel), ao contrário de Card Detail/Card Picker.
 */

export const TRAY_DROP_ID = "__binder-tray__";
const TRAY_ITEM_ID_PREFIX = "tray-item-";

export function trayItemDragId(cardId: string): string {
  return `${TRAY_ITEM_ID_PREFIX}${cardId}`;
}

/** Retorna o `card.id` original se `id` for um arrasto originado da Bandeja, senão `null`. */
export function parseTrayItemDragId(id: string): string | null {
  return id.startsWith(TRAY_ITEM_ID_PREFIX) ? id.slice(TRAY_ITEM_ID_PREFIX.length) : null;
}

const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/80";

/**
 * BINDER-TRAY-VISUAL-PROMINENCE-01 — o botão agora vive na faixa de
 * navegação (`binder-nav-view.tsx`, desde POSITION-01/02), sentado
 * DIRETAMENTE sobre o fundo do workspace, exatamente como `NavButton`/o
 * indicador `N/total` de `nav-controls.tsx` — não mais dentro do interior
 * sempre-escuro do Binder. Por isso precisa do MESMO tratamento real de
 * tema que aqueles controles já têm (`dark:` pareado, ring-offset seguindo
 * `--binder-page-bg`) em vez do `FOCUS_RING`/tokens fixos-para-escuro
 * herdados de quando o botão morava dentro da moldura de couro — sem este
 * ajuste, o botão ficaria quase ilegível num workspace em tema claro
 * (branco translúcido sobre fundo claro). `PANEL_FOCUS_RING`/`FOCUS_RING`
 * continuam corretos para os elementos DENTRO da superfície flutuante
 * (`TrayItem`, botão fechar de `TraySurface`) — esses continuam sempre
 * escuros, sem mudança.
 */
const TOGGLE_FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-page-bg))]";

/** Badge de contagem — pill pequena, tom âmbar/dourado MODERADO (nunca
 * vermelho/erro, pedido explícito: "não parecer notificação de erro").
 * Par claro/escuro dedicado (não os tokens dourados fixos do resto do
 * Binder) pela mesma razão do `TOGGLE_FOCUS_RING` acima — precisa ler bem
 * sobre o fundo do workspace nos dois temas, não só sobre o couro escuro.
 * BINDER-TRAY-DOCK-02 (2026-08-30) — restaurada (tinha saído do arquivo em
 * BINDER-TOOL-RAIL-02, quando o dock ficava invisível em repouso e não
 * precisava mais exibir contagem própria); ver doc-comment de
 * `TrayToggleButton` abaixo para o histórico completo da reversão. */
function TrayCountBadge({ count }: { count: number }) {
  return (
    <span
      className={cn(
        "ml-0.5 inline-flex h-4 min-w-[16px] flex-shrink-0 items-center justify-center rounded-full px-1 text-[10px] font-semibold tabular-nums sm:h-[18px] sm:min-w-[18px] sm:text-[11px]",
        "bg-[hsl(38_65%_45%_/_0.18)] text-[hsl(30_75%_28%)]",
        "dark:bg-[hsl(40_70%_62%_/_0.22)] dark:text-[hsl(40_80%_80%)]",
      )}
    >
      {count}
    </span>
  );
}

/**
 * BINDER-TRAY-POSITION-01 (2026-08-29) — pedido explícito de Fabrício: o
 * posicionamento anterior (badge centralizado sobre a lombada/topo da
 * moldura, dentro de `BinderPagesNav`) foi REJEITADO — "prejudica hierarquia
 * visual, leitura física do Binder, navegação e composição da lombada". A
 * Bandeja é uma ferramenta do WORKSPACE do Binder, não parte física dele:
 * este botão agora é renderizado via `createPortal` (ver `binder-pages-nav.tsx`)
 * dentro da faixa superior de navegação de `binder-nav-view.tsx`, ao lado da
 * paginação « ‹ 2/14 › » — não mais como um elemento `absolute` sobre a
 * moldura. O droppable (`useDroppable({id: TRAY_DROP_ID})`) e o estado
 * (`trayItems`/`trayOpen`) continuam morando inteiramente em
 * `BinderPagesNav` (dono do `<DndContext>`) — só a localização VISUAL do
 * controle mudou; nenhuma semântica de Bandeja foi tocada nesta rodada.
 *
 * `forwardRef`: o container (`BinderPagesNav`) precisa medir a posição real
 * do botão (`getBoundingClientRect`) para ancorar `TraySurface` embaixo dele
 * ao abrir — como o botão é portalado para um nó DOM que vive em
 * `binder-nav-view.tsx`, um `ref` comum (criado em `BinderPagesNav`) ainda
 * funciona normalmente: `ref` segue a árvore do REACT, não a localização no
 * portal, e aponta para o nó DOM de verdade onde quer que ele esteja
 * montado. Precisei combinar esse ref externo com o `setNodeRef` interno do
 * `useDroppable` (dois refs para o mesmo nó) via um callback ref local.
 *
 * BINDER-TOOL-RAIL-02 (2026-08-29) — tentativa anterior: reclassificar este
 * dock como "só drop zone temporária", escondendo-o por completo em
 * repouso (`opacity-0 pointer-events-none aria-hidden`) e movendo o
 * controle permanente de abrir/fechar para a Tool Rail. REVERTIDA na
 * rodada seguinte — ver BINDER-TRAY-DOCK-02 logo abaixo.
 *
 * BINDER-TRAY-DOCK-02 (2026-08-30) — Fabrício sinalizou REGRESSÃO: "o
 * controle inferior da Bandeja desapareceu no estado normal e só aparece
 * quando existe movimento de carta... isso está errado." Decisão
 * DEFINITIVA, revertendo TOOL-RAIL-02: este dock volta a ser um controle
 * PERMANENTE e sempre visível — "não trocar um botão permanente por uma
 * zona de drop condicional." A Tool Rail (`tool-rail.tsx`) MANTÉM sua
 * própria ação fixa "Bandeja" (pedido explícito: "a Tool Rail pode ter
 * ação de Bandeja, mas o dock inferior também deve existir") — as DUAS
 * controlam o MESMO `trayOpen`/`handleToggleTray`, deliberadamente
 * duplicado agora por instrução direta, ao contrário da preferência
 * "evitar dois controles permanentes" de TOOL-RAIL-02.
 *
 * UM ÚNICO COMPONENTE cobre os dois estados (pedido explícito: "não criar
 * dois componentes distintos que aparecem e desaparecem"):
 *  - IDLE (`!dragActive`): visível, clicável (`onClick={onToggle}`),
 *    rótulo "Bandeja" + `TrayCountBadge` quando há itens — exatamente o
 *    tratamento visual de BINDER-TRAY-VISUAL-PROMINENCE-01, restaurado.
 *  - DRAG ACTIVE: o MESMO nó cresce (`px`/`py` maiores) e troca para
 *    `ArrowDown` + "Bandeja"/"Soltar na Bandeja" (quando `isOver`) — "o
 *    alvo de DROP durante drag precisa continuar grande e ergonômico",
 *    inalterado desde BINDER-TRAY-POSITION-01. `isOver` reforça o
 *    highlight dourado de destino válido.
 * `count`/`open`/`onToggle` voltam à assinatura (removidos em
 * TOOL-RAIL-02, restaurados aqui). `useDroppable({id: TRAY_DROP_ID})`
 * nunca deixou de estar sempre montado — só a VISIBILIDADE/estilo mudou de
 * volta; a existência do droppable nunca dependeu de `dragActive`.
 */
export const TrayToggleButton = forwardRef<HTMLButtonElement, { count: number; open: boolean; dragActive: boolean; onToggle: () => void }>(
  function TrayToggleButton({ count, open, dragActive, onToggle }, forwardedRef) {
    const { setNodeRef, isOver } = useDroppable({ id: TRAY_DROP_ID });
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
        title={dragActive ? "Solte aqui para mover a carta para a Bandeja" : "Bandeja — área temporária para reorganizar o Binder"}
        className={cn(
          "relative z-30 flex flex-shrink-0 items-center gap-1.5 rounded-full border font-medium transition-all",
          "text-black/75 hover:text-black/95 dark:text-white/80 dark:hover:text-white",
          dragActive ? "px-4 py-2 text-xs sm:px-5 sm:py-2.5 sm:text-sm" : "px-3 py-1.5 text-xs sm:px-3.5 sm:py-2 sm:text-sm",
          isOver
            ? "border-[hsl(40_70%_50%_/_0.85)] bg-[hsl(40_70%_55%_/_0.16)] text-[hsl(32_75%_30%)] shadow-[0_4px_14px_-4px_rgba(0,0,0,0.35)] dark:border-[hsl(40_70%_62%_/_0.75)] dark:bg-[hsl(40_70%_62%_/_0.22)] dark:text-[hsl(40_80%_82%)]"
            : dragActive
              ? "border-[hsl(40_60%_50%_/_0.5)] bg-black/[0.1] shadow-[0_4px_14px_-4px_rgba(0,0,0,0.3)] dark:border-[hsl(40_60%_62%_/_0.4)] dark:bg-white/10"
              : "border-black/25 bg-black/[0.08] hover:border-[hsl(40_50%_45%_/_0.4)] hover:bg-black/[0.14] dark:border-white/20 dark:bg-white/10 dark:hover:border-[hsl(40_60%_62%_/_0.4)] dark:hover:bg-white/[0.16]",
          TOGGLE_FOCUS_RING,
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
            {count > 0 && <TrayCountBadge count={count} />}
          </>
        )}
      </button>
    );
  },
);

/** Uma carta dentro da superfície aberta — inteiramente arrastável (sem alça
 * separada: ao contrário da carta num slot, aqui não existe uma ação de
 * clique concorrente como "abrir Card Detail" para desambiguar). */
function TrayItem({ card }: { card: RealCardData }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: trayItemDragId(card.id),
    data: { card },
  });
  return (
    <button
      ref={setNodeRef}
      type="button"
      {...attributes}
      {...listeners}
      aria-label={`${card.name} — arraste para um slot, ou selecione e use as setas do teclado`}
      title={card.name}
      className={cn(
        // BINDER-CARD-ASPECT-RATIO-01 — `aspect-[5/7]` → `aspect-[8/11]`,
        // proporção real do asset (600×825px, medido diretamente nos
        // arquivos do Storage). Ver doc-comment equivalente em
        // `binder-slot-full.tsx` para a medição completa.
        "flex aspect-[8/11] w-14 flex-shrink-0 cursor-grab touch-none overflow-hidden rounded-[4px] outline-none transition-opacity active:cursor-grabbing sm:w-16",
        FOCUS_RING,
      )}
      style={{
        opacity: isDragging ? 0.35 : 1,
        boxShadow: "0 0 0 1px hsl(0 0% 100% / 0.14), 0 2px 6px rgba(0,0,0,0.4)",
      }}
    >
      <RealCardFace card={card} />
    </button>
  );
}

/** Largura do painel ancorado (desktop/`sm:`) em px — única fonte de
 * verdade, importada por `binder-pages-nav.tsx` para centralizar
 * corretamente o `anchor` sob o dock (ver `handleToggleTray`). Mantida em
 * sincronia manual com o `w-[...]` usado no `className` abaixo. */
export const TRAY_SURFACE_WIDTH_PX = 280;

/**
 * Superfície flutuante — `position: fixed`, renderizada como irmã do Card
 * Detail/Card Picker em `binder-pages-nav.tsx` (mesmo racional: escapa do
 * `overflow-hidden`/`perspective` da moldura sem precisar de nenhum truque
 * extra, já que `rootRef` não estabelece um "containing block" para
 * elementos fixed — ver doc-comment de `BinderPagesNav`).
 *
 * BINDER-TRAY-REPOSITION-01 (2026-08-29) — o dock desceu para baixo do
 * Binder e virou centralizado (ver `binder-nav-view.tsx`); o painel
 * acompanha: `anchor` (calculado por `BinderPagesNav` a partir do
 * `getBoundingClientRect()` real do dock, medido no momento em que a
 * Bandeja abre) agora centraliza o painel horizontalmente sob o MEIO do
 * dock (`left`) e o abre para CIMA, em direção ao Binder (`bottom`, não
 * `top`) — "o painel deve parecer emergir dele" e o dock já fica perto do
 * rodapé do diálogo, então abrir para baixo arriscaria cortar o painel na
 * borda da tela. Só em telas `sm:` ou maiores (`BinderPagesNav` só calcula
 * `anchor` quando `window.innerWidth >= 640`; abaixo disso vem `null` de
 * propósito). Sem `anchor` (mobile, ou antes da primeira medição), cai no
 * bottom sheet de largura total (`inset-x-3 bottom-3`) — mesma ideia de
 * superfície ancorada na base já usada pelas quick actions dos slots.
 */
export function TraySurface({
  items,
  onClose,
  anchor,
}: {
  items: RealCardData[];
  onClose: () => void;
  anchor: { bottom: number; left: number } | null;
}) {
  return (
    <div
      role="region"
      aria-label="Bandeja — cartas temporariamente fora do Binder"
      className={cn(
        "fixed z-[70] rounded-[14px] p-3",
        anchor ? "w-[280px]" : "inset-x-3 bottom-3 sm:inset-x-auto sm:bottom-auto sm:right-4 sm:top-16 sm:w-[280px]",
      )}
      style={{
        ...(anchor ? { bottom: anchor.bottom, left: anchor.left } : undefined),
        background: "hsl(0 0% 6% / 0.96)",
        boxShadow: [
          "0 20px 40px -10px rgba(0,0,0,0.7)",
          "inset 0 1px 0 hsl(0 0% 100% / 0.08)",
          "0 0 0 1px hsl(0 0% 100% / 0.08)",
        ].join(", "),
        backdropFilter: "blur(6px)",
      }}
    >
      <div className="mb-2 flex items-center justify-between">
        <span className="text-[11px] font-medium uppercase tracking-wide text-white/50">
          Bandeja{items.length > 0 ? ` · ${items.length}` : ""}
        </span>
        <button
          type="button"
          onClick={onClose}
          aria-label="Fechar Bandeja"
          className={cn("rounded-full p-1 text-white/50 transition-colors hover:bg-white/10 hover:text-white", FOCUS_RING)}
        >
          <X className="h-3.5 w-3.5" aria-hidden />
        </button>
      </div>
      {items.length === 0 ? (
        <p className="py-3 text-center text-[11px] leading-relaxed text-white/40">
          Arraste uma carta para o botão &quot;Bandeja&quot; para movê-la temporariamente para cá.
        </p>
      ) : (
        <div className="flex max-h-[50vh] flex-wrap justify-center gap-1.5 overflow-y-auto sm:max-h-[60vh]">
          {items.map((card) => (
            <TrayItem key={card.id} card={card} />
          ))}
        </div>
      )}
    </div>
  );
}
