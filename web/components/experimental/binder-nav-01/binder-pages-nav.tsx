"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { BinderSlotData, LeftPanel, RealCardData, RightPanel } from "@/app/experimental/binder-nav-01/mock-data";
import { getNextReplacementCard } from "@/app/experimental/binder-nav-01/mock-data";
import { parseBinderSlotId } from "@/app/experimental/binder-nav-01/card-detail-mock";
import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";
import { cn } from "@/lib/utils";
import { BinderSlotFull } from "./binder-slot-full";
import { CardDetailModal } from "./card-detail-modal";
import { InsideCoverFace } from "./cover-panel";
import { BLACK_HUE, blackLeatherSurface, darkZipperTeeth } from "./binder-cover-closed";

// Tom do FORRO interno (bolsos/gutter) — mantido como o couro âmbar herdado
// de `binder-spike/binder-cover.tsx` (não importado de lá para evitar
// acoplamento; mesmo valor numérico, `LEATHER_HUE`). Isto é intencional e
// separado da MOLDURA externa: um binder preto real pode perfeitamente ter
// um forro interno de tom diferente. O pedido de Fabrício de 2026-08-28 ("a
// cor da borda da parte interna deve sempre estar de acordo com a cor do
// binder") é sobre a MOLDURA/borda/zíper/puxador visíveis ao redor das
// páginas — esses agora usam `BLACK_HUE`/`blackLeatherSurface`/
// `darkZipperTeeth` importados de `binder-cover-closed.tsx`, ver abaixo.
const INTERIOR_HUE = 26;

/**
 * Variante de `BinderPages` (Binder-First, `binder-spike/binder-pages.tsx`)
 * para o BINDER-NAV-01 (pedido de Fabrício, 2026-08-28 — encerramento dos
 * experimentos de page-turn físico em favor de navegação operacional
 * explícita; ajustada na Rodada 2 para a abertura real contracapa+primeira
 * página; refinada na Rodada 4 para reduzir a sensação de "painéis planos
 * colados lado a lado").
 *
 * Reaproveita a MESMA casca de couro/gutter/estrutura de duas páginas do
 * Binder-First — a casca/moldura/gutter/estrutura NUNCA remonta entre
 * posições (fica fora de qualquer `key`/transição). Só o CONTEÚDO de cada
 * lado (`PanelTransition`, keyed) troca com uma transição digital curta
 * (~200ms, translate pequeno + opacity, zero rotação 3D).
 *
 * Rodada 4 — 4 ajustes sobre a Rodada 3, todos escopados à abertura
 * contracapa+primeira página (`isCoverSpread = left.kind === "insideCover"`),
 * sem alterar navegação/funcionalidade:
 *  1. Zíper da MOLDURA: `frameZipperTeeth()` — traço permanente e discreto
 *     contornando os 4 lados da casca de couro externa (não mais dentro do
 *     painel de veludo da contracapa — fisicamente o zíper é do estojo, não
 *     do forro). Presente em qualquer posição de navegação, já que é um
 *     elemento fixo do case, não do conteúdo do spread.
 *  2. Vinco central mais espesso/profundo: radial de centro mais escuro
 *     (compressão) + duas linhas de luz finas perto das bordas internas das
 *     páginas, para quebrar a leitura de "divisão reta entre duas
 *     superfícies".
 *  3. Primeira página com mais respiro em relação à contracapa: vinco mais
 *     largo quando `isCoverSpread`, sombra de contato reforçada no lado
 *     esquerdo/inferior do conteúdo, e um verniz diagonal sutil (sheen) para
 *     reforçar leitura de material plástico/PVC.
 *  4. Contracapa com sombra mais pronunciada perto do vinco (ver
 *     `cover-panel.tsx`).
 *
 * Rodada 5 (mesma data) — a direção "capa acolchoada/painel independente"
 * da Rodada 3/4 foi REJEITADA por Fabrício: "a contracapa NÃO deve parecer
 * uma grande capa acolchoada/painel independente... deve seguir a mesma
 * lógica visual e proporção de uma página do Binder, porém sem slots."
 * Consequência aqui: o container do slot esquerdo agora recebe o MESMO
 * fundo/sombra/folhas-fantasma de uma página normal em QUALQUER kind
 * (`insideCover` ou `page`) — não existe mais um branch visual separado
 * para a contracapa a este nível; a única diferença é o CONTEÚDO renderizado
 * dentro (grade de bolsos vs. `InsideCoverFace`, que passou a ser só
 * logo+rodapé — ver `cover-panel.tsx`).
 *
 * Rodada 6 (mesma data) — pedido de Fabrício após ver o resultado real:
 * "as cartas devem ganhar mais evidência, diminua os espaços entre cartas e
 * nas margens... aumente o tamanho do binder." Reduzidos: padding do shell
 * externo (`clamp(10px,2.4vw,22px)` → `clamp(6px,1.4vw,14px)`), padding
 * interno de cada página (`p-3 sm:p-4` → `p-1.5 sm:p-2`) e o gap do grid de
 * bolsos (`gap-2 sm:gap-2.5` → `gap-1 sm:gap-1.5`) — cada carta ocupa mais
 * área do slot disponível. O aumento de tamanho do objeto em si é feito no
 * wrapper em `binder-nav-view.tsx` (`max-w-4xl` → `max-w-7xl`).
 *
 * `binder-pages.tsx` original NÃO foi editado — continua servindo o
 * baseline compartilhado de Binder-First/BINDER-VIS-02 e os spikes de
 * motion encerrados; esta variante isolada em `binder-nav-01/` evita
 * qualquer risco de regressão ali.
 *
 * Teste ME2 (mesma data) — `BinderPageData`/`BinderSlotData` passaram a vir
 * de `mock-data.ts` local (tipos próprios do BINDER-NAV-01, card pode ser
 * fictício ou artwork real do ME2) em vez do `binder-spike/mock-data.ts`
 * compartilhado — ver nota completa em `mock-data.ts`. `SlotsGrid`/
 * `BinderSlotFull` não mudaram de assinatura, só a origem do tipo.
 *
 * Rodada 7 (mesma data) — pedido de Fabrício: "a última página deve ter a
 * mesma configuração da contracapa". O slot direito deixou de ser sempre
 * `SlotsGrid` — agora é `RightPanel` (`{kind:"page"}` ou `{kind:"backCover"}`,
 * ver `mock-data.ts`), espelhando o slot esquerdo (`LeftPanel`). Quando
 * `right.kind === "backCover"`, renderiza o MESMO `InsideCoverFace` da
 * contracapa frontal — não existe um componente de "contracapa traseira"
 * separado, é literalmente a mesma configuração, como pedido.
 *
 * BINDER-INTERACTION-01 (2026-08-28) — quick actions contextuais por slot
 * (pedido completo de Fabrício, sem DnD nesta rodada). Este componente
 * passou a ser o dono de todo o estado efêmero de interação, já que ele
 * NUNCA remonta entre posições/navegação (só `PanelTransition`, dentro
 * dele, remonta) — isso garante:
 *  - `selectedSlotId`: seleção efetivamente única por vez, com um único
 *    listener de "clique fora" (`pointerdown` em `document`) montado
 *    SOMENTE enquanto existe uma seleção ativa (item "performance": sem
 *    listeners globais desnecessários) e removido assim que ela é limpa.
 *  - Escape limpa a seleção via `onKeyDown` (bubble, não capture) no root
 *    deste componente — como este root é descendente do `onKeyDown` do
 *    diálogo em `binder-nav-view.tsx` (que fecha o Binder no Escape), o
 *    handler daqui roda PRIMEIRO durante a subida do evento; ao limpar uma
 *    seleção ativa ele chama `stopPropagation()` para o Escape não também
 *    fechar o Binder inteiro no mesmo toque de tecla.
 *  - Seleção é limpa ao trocar de spread (`spreadKey`, derivado dos ids
 *    reais de página/contracapa, não da identidade de objeto de
 *    `left`/`right` — esses são recriados a cada render de
 *    `binder-nav-view.tsx`, então usar a referência causaria resets
 *    espúrios) — selecionar um slot só faz sentido para a posição visível.
 *  - `favoriteCardIds`: favoritar referencia a CARD (`card.id`), nunca uma
 *    Card Variant (pedido explícito) — como o mesmo `card.id` real se
 *    repete em vários slots físicos (18 cartas ciclando por 224 bolsos), o
 *    Set fica aqui, acima de ambos os `SlotsGrid` (esquerdo/direito), para
 *    que favoritar em QUALQUER ocorrência reflita em todas as outras
 *    ocorrências visíveis da mesma carta.
 *  - `removedSlotIds`/`cardOverrides`: mocks visuais de "remover"/
 *    "substituir" — sem Inventory real, sem persistência (resetam ao
 *    fechar o Binder, já que este componente desmonta com ele); ficam
 *    aqui, não em `SlotsGrid`, para sobreviver à navegação para outro
 *    spread e volta, coerente com o modelo físico ("eu mexi NESTE bolso").
 * Nada disto persiste de verdade — "a interação deve funcionar
 * visualmente, mas não precisa persistir" (pedido explícito).
 *
 * Correção de composição (2026-08-28, mesma data — pedido final de
 * Fabrício): a lista aprovada de quick actions do slot ocupado é
 * "substituir carta / remover do slot / favoritar-desfavoritar Card" — sem
 * "visualizar" e sem "mover" (ver nota completa em `slot-quick-actions.tsx`).
 * Consequência aqui: todo o mock de "visualizar" (`peekingSlotIds`,
 * `handleView`, `onView`) foi removido — não tinha mais nenhum botão que o
 * acionasse. Movimentação de carta dentro do Binder continua fora de escopo,
 * será tratada exclusivamente por Drag and Drop numa rodada futura.
 *
 * CARD-DETAIL-01 (2026-08-29) — "Binder = contexto de organização; Card
 * Detail = contexto de informação da carta." Clicar diretamente na arte de
 * uma carta ocupada (ver `binder-slot-full.tsx`) abre `CardDetailModal`.
 * Estado novo, mesmo nível dos demais (nunca remonta entre spreads):
 *  - `detailState` (`{ slotId, card } | null`) — qual carta está com o
 *    detalhe aberto. Guarda o `card` (já passado pelo `effectiveSlot`, ou
 *    seja, já reflete `cardOverrides`/`removedSlotIds` no momento do clique)
 *    em vez de só o `slotId`, porque `SlotsGrid` não tem acesso de volta ao
 *    slot original para "re-resolver" a carta depois.
 *  - `detailTriggerRef` — guarda o elemento DOM que abriu o modal (a própria
 *    arte da carta) para restaurar o foco a ele ao fechar (item 10,
 *    acessibilidade) — sem isso o foco cairia em `document.body`.
 *  - Fechar via spread trocando (`spreadKey`) também limpa `detailState`,
 *    igual a `selectedSlotId` — não faz sentido manter um Card Detail aberto
 *    de uma posição que não está mais visível.
 *  - `parseBinderSlotId` (novo, `card-detail-mock.ts`) decompõe o id físico
 *    do slot (`p{página}-{slot}`) para "Página X · Slot Y" no modal, sem
 *    precisar propagar `pageNumber`/`slotNumber` como props novas por toda a
 *    árvore só para isso.
 */

/**
 * Zíper discreto contornando a moldura externa do Binder aberto — pedido de
 * Fabrício (Rodada 4): "manter presença visual no Binder aberto, contornando
 * a estrutura externa de forma discreta." Usa `darkZipperTeeth` (metal
 * escuro/grafite) importado de `binder-cover-closed.tsx` — antes era uma
 * função local em tom dourado/marrom, incoerente com a capa preta (fix de
 * 2026-08-28: "a cor da borda da parte interna deve sempre estar de acordo
 * com a cor do binder").
 */

export function BinderPagesNav({
  left,
  right,
  direction,
  animate,
}: {
  left: LeftPanel;
  right: RightPanel;
  direction: 1 | -1;
  animate: boolean;
}) {
  const isCoverSpread = left.kind === "insideCover";
  const isBackCoverSpread = right.kind === "backCover";

  const rootRef = useRef<HTMLDivElement>(null);

  const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
  const [removedSlotIds, setRemovedSlotIds] = useState<Set<string>>(() => new Set());
  const [cardOverrides, setCardOverrides] = useState<Map<string, RealCardData>>(() => new Map());
  const [favoriteCardIds, setFavoriteCardIds] = useState<Set<string>>(() => new Set());
  const [detailState, setDetailState] = useState<{ slotId: string; card: MockCardData | RealCardData } | null>(null);
  const detailTriggerRef = useRef<HTMLElement | null>(null);

  const clearSelection = useCallback(() => {
    setSelectedSlotId(null);
  }, []);

  // Seleção é sobre um slot físico da posição ATUAL — ao trocar de spread não
  // há mais um "slot selecionado" coerente para manter. `spreadKey` usa os
  // ids reais (não a identidade de objeto de `left`/`right`, recriados a
  // cada render do pai mesmo sem navegação real).
  const spreadKey = `${left.kind === "page" ? left.page.id : left.kind}|${right.kind === "page" ? right.page.id : right.kind}`;
  useEffect(() => {
    clearSelection();
    setDetailState(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spreadKey]);

  // Clique fora do Binder aberto limpa a seleção — listener só existe
  // enquanto HÁ uma seleção ativa (nunca um listener global permanente).
  useEffect(() => {
    if (!selectedSlotId) return;
    function handlePointerDown(event: PointerEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) {
        clearSelection();
      }
    }
    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, [selectedSlotId, clearSelection]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === "Escape" && selectedSlotId) {
        // Evita que o mesmo Escape também feche o Binder inteiro (handler
        // do diálogo em `binder-nav-view.tsx`, mais acima na árvore real).
        event.stopPropagation();
        clearSelection();
      }
    },
    [selectedSlotId, clearSelection],
  );

  const handleSelectSlot = useCallback((slotId: string) => {
    setSelectedSlotId((current) => (current === slotId ? null : slotId));
  }, []);

  const handleAddCard = useCallback(() => {
    // Mock: ação principal do slot vazio, sem Inventory real nesta rodada
    // (pedido explícito: "não precisa implementar lógica real ainda").
  }, []);

  const handleOpenDetail = useCallback((slotId: string, card: MockCardData | RealCardData, triggerEl: HTMLElement) => {
    detailTriggerRef.current = triggerEl;
    setDetailState({ slotId, card });
  }, []);

  const handleCloseDetail = useCallback(() => {
    setDetailState(null);
    const trigger = detailTriggerRef.current;
    detailTriggerRef.current = null;
    // Restaura o foco ao elemento que abriu o Card Detail (item 10,
    // acessibilidade) — só depois do próximo paint, já que o próprio
    // elemento (a arte da carta) continua no DOM (mesmo slot, mesmo spread).
    if (trigger) requestAnimationFrame(() => trigger.focus());
  }, []);

  const handleReplace = useCallback((slotId: string, currentCardId: string) => {
    setCardOverrides((current) => {
      const next = new Map(current);
      next.set(slotId, getNextReplacementCard(currentCardId));
      return next;
    });
  }, []);

  const handleRemove = useCallback((slotId: string) => {
    setRemovedSlotIds((current) => new Set(current).add(slotId));
    setSelectedSlotId((current) => (current === slotId ? null : current));
  }, []);

  const handleToggleFavorite = useCallback((cardId: string) => {
    setFavoriteCardIds((current) => {
      const next = new Set(current);
      if (next.has(cardId)) next.delete(cardId);
      else next.add(cardId);
      return next;
    });
  }, []);

  const slotsGridProps = useMemo(
    () => ({
      selectedSlotId,
      favoriteCardIds,
      removedSlotIds,
      cardOverrides,
      onSelectSlot: handleSelectSlot,
      onAddCard: handleAddCard,
      onOpenDetail: handleOpenDetail,
      onReplace: handleReplace,
      onRemove: handleRemove,
      onToggleFavorite: handleToggleFavorite,
    }),
    [
      selectedSlotId,
      favoriteCardIds,
      removedSlotIds,
      cardOverrides,
      handleSelectSlot,
      handleAddCard,
      handleOpenDetail,
      handleReplace,
      handleRemove,
      handleToggleFavorite,
    ],
  );

  const detailParsed = detailState ? parseBinderSlotId(detailState.slotId) : null;

  return (
    <div
      ref={rootRef}
      onKeyDown={handleKeyDown}
      className="relative w-full overflow-hidden rounded-[22px]"
      style={{
        backgroundImage: blackLeatherSurface(),
        boxShadow: [
          "inset 0 1px 0 hsl(0 0% 100% / 0.08)",
          "inset 0 -2px 10px hsl(0 0% 0% / 0.5)",
          "0 40px 60px -20px rgba(0,0,0,0.65)",
        ].join(", "),
        border: "1px solid hsl(0 0% 0% / 0.5)",
        padding: "clamp(6px, 1.4vw, 14px)",
      }}
    >
      {/* Zíper da moldura — permanente, discreto, contorna a estrutura externa (item 4, Rodada 4). */}
      <div
        className="pointer-events-none absolute left-[8%] right-[8%] top-[6px] h-[2.5px] rounded-full opacity-70"
        style={{ backgroundImage: darkZipperTeeth(false) }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute left-[8%] right-[8%] bottom-[6px] h-[2.5px] rounded-full opacity-70"
        style={{ backgroundImage: darkZipperTeeth(false) }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute top-[12%] bottom-[12%] left-[5px] w-[2.5px] rounded-full opacity-70"
        style={{ backgroundImage: darkZipperTeeth(true) }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute top-[12%] bottom-[12%] right-[5px] w-[2.5px] rounded-full opacity-70"
        style={{ backgroundImage: darkZipperTeeth(true) }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute left-[3px] top-[7%] h-3.5 w-2 rounded-[2px] opacity-80"
        style={{
          background: "linear-gradient(160deg, hsl(0 0% 46%), hsl(0 0% 16%))",
          boxShadow: "0 1px 2px rgba(0,0,0,0.5)",
        }}
        aria-hidden
      />

      <div className="relative flex" style={{ perspective: "2000px" }}>
        {/* Slot esquerdo — contracapa interna (posição 0) ou página normal de bolsos. */}
        <div className="relative flex-1" style={{ transform: "rotateY(2deg)", transformOrigin: "right center" }}>
          {/* Folhas fantasma — espessura de papel. Rodada 5: também atrás da
              contracapa, já que ela agora segue a mesma lógica visual/proporção
              de uma página (pedido explícito de Fabrício), não mais um painel
              à parte. */}
          <div
            className="absolute inset-0 rounded-l-lg"
            style={{ transform: "translate(2px, 3px)", background: `hsl(${INTERIOR_HUE} 10% 4%)` }}
            aria-hidden
          />
          <div
            className="absolute inset-0 rounded-l-lg"
            style={{ transform: "translate(1px, 1.5px)", background: `hsl(${INTERIOR_HUE} 12% 6%)` }}
            aria-hidden
          />
          <div
            className="relative h-full overflow-hidden rounded-l-lg p-1.5 sm:p-2"
            style={{
              background: `linear-gradient(100deg, hsl(${INTERIOR_HUE} 14% 11%) 0%, hsl(${INTERIOR_HUE} 18% 6%) 100%)`,
              boxShadow: [
                "inset -26px 0 30px -22px rgba(0,0,0,0.85)",
                "inset 3px 0 0 hsl(0 0% 100% / 0.05)",
                "inset 0 2px 6px rgba(0,0,0,0.4)",
              ].join(", "),
            }}
          >
            {left.kind === "insideCover" ? (
              <PanelTransition panelKey="inside-cover" direction={direction} animate={animate}>
                <InsideCoverFace />
              </PanelTransition>
            ) : (
              <PanelTransition panelKey={left.page.id} direction={direction} animate={animate}>
                <SlotsGrid slots={left.page.slots} {...slotsGridProps} />
              </PanelTransition>
            )}
          </div>
        </div>

        {/* Vinco central — mais espesso/profundo na abertura contracapa+página
            (item 2/3, Rodada 4), sem nunca remontar entre posições. */}
        <div
          className={cn(
            "pointer-events-none relative flex-shrink-0",
            isCoverSpread || isBackCoverSpread ? "w-7 sm:w-10" : "w-5 sm:w-6",
          )}
          aria-hidden
        >
          <div
            className="absolute inset-0"
            style={{
              background: `linear-gradient(90deg, transparent, hsl(${INTERIOR_HUE} 22% 5%) 30%, hsl(${INTERIOR_HUE} 16% 3%) 50%, hsl(${INTERIOR_HUE} 22% 5%) 70%, transparent)`,
            }}
          />
          <div
            className="absolute inset-0"
            style={{
              background: "radial-gradient(ellipse 60% 100% at 50% 50%, hsl(0 0% 0% / 0.55) 0%, transparent 70%)",
              boxShadow: "0 0 20px 6px rgba(0,0,0,0.55)",
            }}
          />
          {/* Linhas de luz nas bordas internas das páginas — quebram a divisão reta. */}
          <div className="absolute inset-y-2 left-[22%] w-px" style={{ background: "hsl(0 0% 100% / 0.07)" }} />
          <div className="absolute inset-y-2 right-[22%] w-px" style={{ background: "hsl(0 0% 100% / 0.07)" }} />
        </div>

        {/* Slot direito — sempre página normal de bolsos nesta rodada (primeira página quando isCoverSpread). */}
        <div className="relative flex-1" style={{ transform: "rotateY(-2deg)", transformOrigin: "left center" }}>
          <div
            className="absolute inset-0 rounded-r-lg"
            style={{ transform: "translate(2px, 3px)", background: `hsl(${INTERIOR_HUE} 10% 4%)` }}
            aria-hidden
          />
          <div
            className="absolute inset-0 rounded-r-lg"
            style={{ transform: "translate(1px, 1.5px)", background: `hsl(${INTERIOR_HUE} 12% 6%)` }}
            aria-hidden
          />
          <div
            className="relative h-full overflow-hidden rounded-r-lg p-1.5 sm:p-2"
            style={{
              background: `linear-gradient(260deg, hsl(${INTERIOR_HUE} 14% 11%) 0%, hsl(${INTERIOR_HUE} 18% 6%) 100%)`,
              boxShadow: isCoverSpread
                ? [
                    // Sombra de contato reforçada — a página "está inserida", não sobreposta.
                    "inset 32px 0 34px -20px rgba(0,0,0,0.9)",
                    "inset -3px 0 0 hsl(0 0% 100% / 0.05)",
                    "inset 0 3px 8px rgba(0,0,0,0.5)",
                    "inset 0 -10px 14px -10px rgba(0,0,0,0.55)",
                  ].join(", ")
                : [
                    "inset 26px 0 30px -22px rgba(0,0,0,0.85)",
                    "inset -3px 0 0 hsl(0 0% 100% / 0.05)",
                    "inset 0 2px 6px rgba(0,0,0,0.4)",
                  ].join(", "),
            }}
          >
            {right.kind === "page" ? (
              <PanelTransition panelKey={right.page.id} direction={direction} animate={animate}>
                <SlotsGrid slots={right.page.slots} {...slotsGridProps} />
              </PanelTransition>
            ) : (
              <PanelTransition panelKey="back-cover" direction={direction} animate={animate}>
                <InsideCoverFace />
              </PanelTransition>
            )}
            {isCoverSpread && (
              <div
                className="pointer-events-none absolute inset-0 rounded-r-lg"
                style={{
                  background:
                    "linear-gradient(115deg, hsl(0 0% 100% / 0.05) 0%, transparent 30%, transparent 68%, hsl(0 0% 100% / 0.035) 100%)",
                }}
                aria-hidden
              />
            )}
          </div>
        </div>
      </div>

      {/* Card Detail — renderizado como irmão da moldura, NÃO como descendente
          dos containers com `transform`/`perspective` acima (o flex com
          `perspective: 2000px`/`rotateY(...)`). `position: fixed` dentro de um
          ancestral com transform/perspective fica contido por ele em vez do
          viewport — renderizando aqui, fora dessa árvore, o overlay cobre a
          tela inteira corretamente (item 8: "o Binder deve continuar
          visível/perceptível atrás do modal", o que só funciona se o modal
          realmente escapar para o viewport). */}
      {detailState && (
        <CardDetailModal
          card={detailState.card}
          isFavorite={favoriteCardIds.has(detailState.card.id)}
          onToggleFavorite={() => handleToggleFavorite(detailState.card.id)}
          pageNumber={detailParsed?.pageNumber ?? 0}
          slotNumber={detailParsed?.slotNumber ?? 0}
          onClose={handleCloseDetail}
        />
      )}
    </div>
  );
}

function SlotsGrid({
  slots,
  selectedSlotId,
  favoriteCardIds,
  removedSlotIds,
  cardOverrides,
  onSelectSlot,
  onAddCard,
  onOpenDetail,
  onReplace,
  onRemove,
  onToggleFavorite,
}: {
  slots: BinderSlotData[];
  selectedSlotId: string | null;
  favoriteCardIds: Set<string>;
  removedSlotIds: Set<string>;
  cardOverrides: Map<string, RealCardData>;
  onSelectSlot: (slotId: string) => void;
  onAddCard: () => void;
  onOpenDetail: (slotId: string, card: MockCardData | RealCardData, triggerEl: HTMLElement) => void;
  onReplace: (slotId: string, currentCardId: string) => void;
  onRemove: (slotId: string) => void;
  onToggleFavorite: (cardId: string) => void;
}) {
  return (
    <div className="grid grid-cols-3 gap-1 sm:gap-1.5">
      {slots.map((slot) => {
        // Mocks visuais de "remover"/"substituir" (sem Inventory real, sem
        // persistência — ver doc-comment de `BinderPagesNav` acima).
        const removed = removedSlotIds.has(slot.id);
        const override = cardOverrides.get(slot.id);
        const effectiveSlot: BinderSlotData = removed
          ? { ...slot, filled: false, card: undefined }
          : override
            ? { ...slot, card: override }
            : slot;
        const cardId = effectiveSlot.card?.id;
        return (
          <BinderSlotFull
            key={slot.id}
            slot={effectiveSlot}
            isSelected={selectedSlotId === slot.id}
            isFavorite={cardId ? favoriteCardIds.has(cardId) : false}
            onSelectToggle={() => onSelectSlot(slot.id)}
            onAddCard={onAddCard}
            onOpenDetail={(triggerEl) => effectiveSlot.card && onOpenDetail(slot.id, effectiveSlot.card, triggerEl)}
            onReplace={() => cardId && onReplace(slot.id, cardId)}
            onRemove={() => onRemove(slot.id)}
            onToggleFavorite={() => cardId && onToggleFavorite(cardId)}
          />
        );
      })}
    </div>
  );
}

/**
 * Remonta a cada troca de posição (via `key` no pai = `panelKey`) e, se
 * `animate`, entra com um pequeno translateX (sinalizado por `direction`) +
 * fade-in via CSS transition padrão (180-250ms) — nunca rotação/perspectiva
 * 3D. Usado tanto para a grade de bolsos quanto para a contracapa, para que
 * a troca entre os dois tipos de conteúdo tenha a mesma transição digital
 * discreta. Com `prefers-reduced-motion` (`animate=false`), a troca é
 * instantânea, sem nenhum estilo de transição.
 */
function PanelTransition({
  panelKey,
  direction,
  animate,
  children,
}: {
  panelKey: string;
  direction: 1 | -1;
  animate: boolean;
  children: ReactNode;
}) {
  return (
    <PanelTransitionInner key={panelKey} direction={direction} animate={animate}>
      {children}
    </PanelTransitionInner>
  );
}

function PanelTransitionInner({
  direction,
  animate,
  children,
}: {
  direction: 1 | -1;
  animate: boolean;
  children: ReactNode;
}) {
  const [entered, setEntered] = useState(!animate);

  useEffect(() => {
    if (!animate) return;
    setEntered(false);
    const raf = requestAnimationFrame(() => setEntered(true));
    return () => cancelAnimationFrame(raf);
    // Roda uma vez por montagem (posição nova) — não a cada mudança de direction/animate.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div
      className={cn("h-full", animate && "transition-all duration-200 ease-out")}
      style={
        animate
          ? { transform: entered ? "translateX(0)" : `translateX(${direction * 8}px)`, opacity: entered ? 1 : 0 }
          : undefined
      }
    >
      {children}
    </div>
  );
}
