"use client";

import {
  DndContext,
  DragOverlay,
  closestCenter,
  pointerWithin,
  useDroppable,
  useSensor,
  useSensors,
  KeyboardSensor,
  PointerSensor,
  TouchSensor,
  type Announcements,
  type CollisionDetection,
  type DragCancelEvent,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import type { BinderSlotData, LeftPanel, RealCardData, RightPanel } from "@/app/experimental/binder-nav-01/mock-data";
import { parseBinderSlotId } from "@/app/experimental/binder-nav-01/card-detail-mock";
import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";
import { cn } from "@/lib/utils";
import { BinderSlotFull } from "./binder-slot-full";
import { TRAY_DROP_ID, TRAY_SURFACE_WIDTH_PX, TraySurface, TrayToggleButton, parseTrayItemDragId } from "./binder-tray";
import { ToolRail } from "./tool-rail";
import { CardDetailModal } from "./card-detail-modal";
import { CardPickerModal } from "./card-picker-modal";
import { RealCardFace } from "./real-card-face";
import { InsideCoverFace } from "./cover-panel";
import { BLACK_HUE, blackLeatherSurface, darkZipperTeeth } from "./binder-cover-closed";

// BINDER-DND-01 — ids sentinela dos dois droppables de navegação de borda
// (ver doc-comment abaixo). Nunca colidem com um id real de slot (formato
// `p{página}-{slot}`, ver `mock-data.ts`).
const EDGE_PREV_ID = "__binder-edge-prev__";
const EDGE_NEXT_ID = "__binder-edge-next__";
const EDGE_NAV_DWELL_MS = 650;

// BINDER-DND-01 — colisão: tenta primeiro `pointerWithin` (só considera um
// droppable "válido" se o ponteiro estiver LITERALMENTE dentro dele) e só
// cai para `closestCenter` quando não há nenhum (arrasto por teclado, sem
// ponteiro real). Sem isso, `closestCenter` sozinho podia resolver para as
// zonas de borda (finas, mas com centro geometricamente "mais perto" em
// alguns ângulos) mesmo com o ponteiro claramente em cima de um slot da
// borda da grade — padrão documentado do próprio dnd-kit para este tipo de
// ambiguidade (exemplo oficial de múltiplos containers).
const binderCollisionDetection: CollisionDetection = (args) => {
  const pointerCollisions = pointerWithin(args);
  if (pointerCollisions.length > 0) return pointerCollisions;
  return closestCenter(args);
};

// BINDER-TRAY-01 — origem de um arrasto: um SLOT físico (id no formato
// `p{página}-{slot}`, o de sempre) ou a Bandeja (id prefixado, ver
// `trayItemDragId`/`parseTrayItemDragId` em `binder-tray.tsx`). Resolvido só
// a partir do id do `active` do dnd-kit — nenhum estado adicional precisa
// saber "de onde" uma carta veio além disso.
type DragOrigin = { type: "slot"; slotId: string } | { type: "tray"; cardId: string };
function resolveDragOrigin(id: string): DragOrigin {
  const trayCardId = parseTrayItemDragId(id);
  return trayCardId ? { type: "tray", cardId: trayCardId } : { type: "slot", slotId: id };
}

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
 * BINDER-QUICK-ACTIONS-01 (2026-08-29) — nova ação Lock/Unlock Slot (pedido
 * explícito de Fabrício, lista final de ações do slot ocupado). Estado novo,
 * mesmo nível/racional dos demais (mock local, sem persistência):
 *  - `lockedSlotIds` — Set por `slot.id` (SLOT físico, não Card — proteção
 *    de LAYOUT contra futuro auto-arrange/push/insert, não um lock
 *    patrimonial do Inventory). Diferente de `favoriteCardIds`, que é por
 *    `card.id`: um mesmo slot físico pode ficar bloqueado independente de
 *    qual carta está nele no momento.
 *  - `handleToggleLock` — mesmo padrão de `handleToggleFavorite`, mas
 *    chaveado por `slot.id`.
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
 *
 * BINDER-ADD-REPLACE-CARD-01 (2026-08-29) — primeiro fluxo funcional de
 * Adicionar/Substituir carta (pedido de Fabrício, "retomar implementação
 * funcional" depois do encerramento da frente visual da Collection
 * Library). Reaproveita a MESMA infraestrutura de estado/mocks já
 * estabelecida aqui — `cardOverrides`/`removedSlotIds` continuam sendo os
 * ÚNICOS mecanismos de "o que está em cada bolso" (nenhum estado novo
 * paralelo foi criado):
 *  - `pickerState` (`{ mode: "add" | "replace"; slotId; currentCard? } |
 *    null`) — mesmo nível/racional de `detailState`: nunca remonta entre
 *    spreads, é limpo ao trocar de posição (`spreadKey`) e ao fechar.
 *  - `pickerTriggerRef` — mesmo padrão de `detailTriggerRef`: guarda o
 *    elemento que abriu o Card Picker ("Adicionar carta" do slot vazio, ou
 *    "Substituir carta" das quick actions) para restaurar o foco a ele ao
 *    fechar (acessibilidade, mesmo item já resolvido para o Card Detail).
 *  - `handleOpenAddPicker`/`handleOpenReplacePicker` substituem o antigo
 *    `handleAddCard` (que era um no-op explícito, "não precisa implementar
 *    lógica real ainda") e o antigo `handleReplace` (que cicla
 *    automaticamente para a "próxima" carta via `getNextReplacementCard`,
 *    REMOVIDO — ver `mock-data.ts`) — os dois agora abrem o MESMO
 *    `CardPickerModal` (`card-picker-modal.tsx`), só variando `mode`.
 *  - `handleSelectPickerCard` é o único ponto que efetivamente escreve em
 *    `cardOverrides` a partir do Picker — para ADD, também precisa marcar o
 *    slot como `filled: true` (o `effectiveSlot` abaixo, em `SlotsGrid`,
 *    ganhou esse ajuste: antes só um `override` de card em cima de um slot
 *    ORIGINALMENTE vazio não bastava, porque `filled` continuava vindo do
 *    slot base) e limpar `removedSlotIds` caso o slot tivesse sido removido
 *    antes (evita o estado "removido E com override" ficar ambíguo — a
 *    checagem de `removed` vem primeiro no cálculo de `effectiveSlot`, então
 *    um override sozinho não seria suficiente para "reviver" um slot
 *    removido sem essa limpeza).
 *
 * Mock explícito, documentado em `card-picker-mock.ts`: o Picker busca sobre
 * o MESMO pool `ME2_CARDS` (18 cartas) que já preenche os 224 bolsos, com um
 * número mock de "cópias disponíveis" por carta — não há Inventory real por
 * trás; ver relatório de implementação desta rodada para o detalhamento
 * completo do que está mockado.
 *
 * BINDER-DND-01 (2026-08-29) — Drag and Drop como mecanismo OFICIAL de MOVE
 * (pedido explícito: "não criar botão 'Move' nas Quick Actions"). Instalado
 * `@dnd-kit/core` (só este pacote — não `@dnd-kit/sortable`, que resolve
 * reordenação de LISTA, não swap/move num grid de posições arbitrárias; a
 * variante mais nova `@dnd-kit/react`/`@dnd-kit/dom` também não foi usada —
 * ainda em 0.x, com bugs abertos de Strict Mode específicos dela). Ver
 * relatório de implementação para o racional completo de compatibilidade
 * com React 19.1/Next 15.5.
 *
 * MODELO DE ESTADO — `cardOverrides`/`removedSlotIds` continuam sendo os
 * ÚNICOS mecanismos de "o que está em cada bolso" (mesma fonte de verdade
 * de BINDER-ADD-REPLACE-CARD-01, nenhum estado concorrente novo). Dois
 * helpers puros formalizam as duas operações atômicas que toda ação sobre
 * um slot acaba sendo:
 *  - `fillSlot(slotId, card)` — grava a carta no slot E limpa
 *    `removedSlotIds` para ele (um slot que estava "removido" e recebe uma
 *    carta nova deixa de estar removido). Usado por ADD via Picker, REPLACE
 *    via Picker, e agora também pelo destino de MOVE/SWAP.
 *  - `emptySlot(slotId)` — marca o slot como removido E limpa qualquer
 *    override — esvaziar sempre funciona, seja a carta atual "original" do
 *    slot base ou uma carta que só existe ali por causa de um MOVE/SWAP
 *    anterior. Usado por "Remover do slot" e agora pela ORIGEM de um MOVE.
 * `handleSelectPickerCard`/`handleRemove` foram refatorados para usar os
 * mesmos dois helpers — comportamento idêntico ao de BINDER-ADD-REPLACE-
 * CARD-01, só a implementação interna ficou compartilhada.
 *
 * DRAGGABLE/DROPPABLE por slot vivem em `binder-slot-full.tsx` (não aqui —
 * Hooks do dnd-kit só podem ser chamados dentro de um componente de
 * verdade, nunca dentro do `.map()` de `SlotsGrid`). Este arquivo é o dono
 * do `<DndContext>` (measurement/sensors/colisão/eventos) e da lógica de
 * negócio dos três casos:
 *  - **CASO 1 (ocupado → vazio, MOVE)**: `emptySlot(origem)` +
 *    `fillSlot(destino, carta)`.
 *  - **CASO 2 (ocupado → ocupado, SWAP)**: `fillSlot(origem, cartaB)` +
 *    `fillSlot(destino, cartaA)` — nenhuma carta é criada/duplicada, as
 *    DUAS trocam de posição no mesmo evento.
 *  - **CASO 3 (entre páginas/spreads)**: como só as 2 páginas VISÍVEIS têm
 *    slots montados como droppables reais a qualquer momento, o destino de
 *    outra página só existe depois de navegar até ela. Solução adotada
 *    (a mais simples das listadas pelo pedido — "edge navigation"): duas
 *    zonas invisíveis (`EdgeNavZone`, ids `EDGE_PREV_ID`/`EDGE_NEXT_ID`) nas
 *    bordas externas da moldura; pairar um arrasto sobre uma delas por
 *    `EDGE_NAV_DWELL_MS` chama `onNavigatePrev`/`onNavigateNext` (props
 *    novas, vêm de `binder-nav-view.tsx` — os MESMOS `goPrev`/`goNext` que
 *    já existiam para os botões de seta) e o usuário solta no slot da nova
 *    página. Funciona porque o `<DndContext>` NUNCA remonta entre spreads
 *    (só o conteúdo interno de `PanelTransition` remonta) — o estado do
 *    arrasto sobrevive à troca de página por trás dele.
 *  - `activeDrag` (`{slotId, card} | null`) — snapshot da carta sendo
 *    arrastada, capturado em `onDragStart` a partir de `active.data.current`
 *    (não relido do DOM depois) — precisa sobreviver ao desmonte do slot de
 *    ORIGEM quando o usuário navega para outra página no meio do arrasto
 *    (item essencial do Caso 3: sem isso, mover para outra página perderia
 *    a referência da carta assim que a página de origem saísse de tela).
 *    Também alimenta o `DragOverlay` (preview que segue o ponteiro/dedo,
 *    desacoplado do nó DOM original, mesma razão).
 *
 * CLIQUE × ARRASTAR: resolvido por CONSTRUÇÃO, não por heurística de
 * limiar/temporização — a arte da carta continua com só o `onClick` de
 * sempre (`CARD-DETAIL-01`, intocado); quem ativa o `useDraggable` é uma
 * alça FISICAMENTE separada (`DragHandleButton`, `slot-quick-actions.tsx`).
 * `PointerSensor` ainda usa `activationConstraint: {distance: 4}` como
 * higiene geral (evita que um tremor mínimo do mouse sobre a alça conte
 * como arrasto), não como mecanismo principal de diferenciação.
 *
 * LOCK: origem Locked nunca fica `draggable` (`useDraggable({disabled:
 * isLocked})`, `binder-slot-full.tsx`) — o dnd-kit nem inicia o gesto.
 * Destino Locked nunca fica `droppable` (`useDroppable({disabled:
 * isLocked})`) — a colisão simplesmente ignora esses slots, `over` nunca
 * aponta pra eles. Lock é por SLOT (`lockedSlotIds`, já existente) — MOVE/
 * SWAP nunca move um lock junto com uma carta, porque lock nunca esteve
 * associado a carta nenhuma (mesma regra já estabelecida:
 * "proteção de LAYOUT, não patrimonial do Inventory").
 *
 * FAVORITE: `favoriteCardIds` é indexado por `card.id`, nunca por
 * `slot.id` — MOVE/SWAP muda ONDE a carta está, nunca QUAL carta é qual;
 * favoritar permanece intacto por construção, sem nenhum código extra
 * precisar tratar esse caso.
 *
 * TOUCH: `TouchSensor` com `activationConstraint: {delay: 200, tolerance:
 * 8}` — padrão "long-press" recomendado pela própria documentação do
 * dnd-kit para computar a diferença entre arrastar e rolar a página: um
 * toque que se move cedo (rolagem) é liberado pro browser tratar como
 * scroll normal; um toque que fica parado por 200ms ativa o arrasto. Sem
 * `touch-action: none` global — só a alça de arrastar recebe `touch-none`
 * pontualmente (`slot-quick-actions.tsx`), o resto da página rola normal.
 *
 * KEYBOARD: `KeyboardSensor` com o `coordinateGetter` PADRÃO do dnd-kit
 * (nenhum customizado nesta rodada) — Espaço/Enter na alça foca e inicia o
 * arrasto, setas navegam para o droppable mais próximo na direção
 * pressionada (algoritmo de retângulo mais próximo, não específico de
 * lista), Enter/Espaço confirmam o drop, Esc cancela — comportamento
 * embutido do sensor, sem código adicional aqui. LIMITAÇÃO CONHECIDA
 * (documentada, não escondida): como o coordinateGetter padrão só enxerga
 * droppables MONTADOS (as 2 páginas visíveis), atravessar para outra
 * página inteiramente por teclado durante um arrasto ativo não é
 * suportado nesta rodada — o usuário cancela (Esc), navega pelos
 * controles normais (já acessíveis por teclado), e inicia um novo arrasto
 * na página de destino. Ver relatório de implementação, "limitações
 * encontradas".
 *
 * ANNOUNCEMENTS: `accessibility.announcements` do `<DndContext>` descreve
 * em português cada fase (pegar, sobrevoar destino ocupado/vazio/
 * bloqueado, resultado do drop, cancelamento) para leitor de tela — ver
 * `buildAnnouncements` abaixo.
 *
 * NÃO IMPLEMENTADO NESTA RODADA (pedido explícito): Push/Insert, auto-
 * arrange, Merge, multi-select, drag de múltiplas cartas, Custom Image,
 * drag entre Collections diferentes, backend, persistência, sincronização
 * de Inventory real, Undo/Redo global.
 *
 * BINDER-TRAY-01 (2026-08-29) — Bandeja, área temporária de manipulação
 * (padrão observado no benchmark PkmnBindr, pedido explícito de Fabrício).
 * UI em `binder-tray.tsx`; aqui mora só o estado e a integração com o
 * `<DndContext>` já existente de BINDER-DND-01 — reaproveitado por inteiro
 * (sensores, `DragOverlay`, `announcements`, colisão, edge navigation),
 * nenhum `DndContext` novo, nenhum sistema de drag paralelo.
 *
 * NÃO é uma nova entidade de domínio (repetido três vezes no pedido
 * original): uma carta "na Bandeja" continua sendo o MESMO Inventory Item e
 * a MESMA Collection allocation — só o `slot placement` fica temporariamente
 * ausente. Ver doc-comment de `binder-tray.tsx` para o racional de UI/a11y;
 * aqui, o que importa é como o TERCEIRO estado (`trayItems`) se relaciona
 * com os dois que já existiam:
 *  - `cardOverrides`/`removedSlotIds` descrevem exclusivamente "o que está
 *    em cada SLOT". Uma carta que vai para a Bandeja SAI completamente
 *    desses dois (o slot de origem passa por `emptySlot`, igual a uma
 *    remoção) — ela só existe daí em diante dentro de `trayItems`. Uma
 *    carta nunca é representada nos dois ao mesmo tempo; a transição entre
 *    "está num slot" e "está na Bandeja" é sempre uma operação atômica
 *    dentro do mesmo `handleDragEnd` (`emptySlot`/`fillSlot` de um lado,
 *    `addToTray`/`removeFromTray` do outro, nunca só um dos dois).
 *  - `activeDrag` ganhou um campo `from: DragOrigin` (`{type:"slot",
 *    slotId}` ou `{type:"tray", cardId}`, ver `resolveDragOrigin`) no lugar
 *    do antigo `slotId` fixo — o resto do snapshot (`card`, usado pelo
 *    `DragOverlay`) não mudou. A origem é resolvida SÓ a partir do id do
 *    `active` do dnd-kit (prefixo `tray-item-`, ver `trayItemDragId` em
 *    `binder-tray.tsx`), o mesmo padrão de namespacing de id já usado para
 *    `EDGE_PREV_ID`/`EDGE_NEXT_ID` — nenhum estado adicional precisa saber
 *    "de onde" veio a carta além disso.
 *  - `trayItems: RealCardData[]` guarda o objeto INTEIRO da carta (não só o
 *    id) porque, ao sair de um slot, a entrada correspondente de
 *    `cardOverrides` é apagada — sem persistir o objeto aqui, a carta
 *    "desapareceria" de vez em vez de ficar temporariamente sem posição.
 *    Deduplicado por `card.id`. NÃO é resetado no `useEffect` de troca de
 *    `spreadKey` (ao contrário de `selectedSlotId`/`detailState`/
 *    `pickerState`) — precisa sobreviver à navegação entre páginas, esse é
 *    o objetivo do recurso.
 *
 * DROP SLOT → BANDEJA / BANDEJA → SLOT VAZIO / BANDEJA → SLOT OCUPADO: as
 * três operações reaproveitam os mesmos `fillSlot`/`emptySlot` de sempre,
 * só adicionando `addToTray`/`removeFromTray` no lado da Bandeja — ver os
 * três ramos novos em `handleDragEnd`. BANDEJA → SLOT OCUPADO usa SWAP
 * (mesma decisão de V1 do slot↔slot): o item do destino não é descartado,
 * vai para a Bandeja no lugar do item que saiu de lá — "evita perda de item
 * e mantém operação reversível" (pedido explícito).
 *
 * LOCK: destino locked continua recusando o drop pelo MESMO mecanismo já
 * existente (`useDroppable({disabled: isLocked})` de cada slot, ver
 * `binder-slot-full.tsx`) — a Bandeja não precisou de nenhuma lógica de
 * lock adicional, ela só passa a ser mais uma origem possível de carta que
 * tenta soltar num slot. "Lock de origem" não se aplica a um item que já
 * está na Bandeja (não há mais um slot físico de origem para bloquear) —
 * por isso o item da Bandeja nunca é `disabled` no seu próprio
 * `useDraggable` (`TrayItem`, `binder-tray.tsx`).
 *
 * NÃO IMPLEMENTADO NESTA RODADA (pedido explícito): Multi-select, Bulk,
 * Merge, persistência, backend, Inventory real, drag entre Collections,
 * histórico global, Undo/Redo global. PERSISTÊNCIA FUTURA — pendência
 * documentada, não resolvida agora: quando existir backend real, será
 * preciso decidir o que acontece se o usuário sair do Binder com itens
 * ainda na Bandeja (ex.: bloquear a saída, persistir a Bandeja entre
 * sessões, ou devolver automaticamente cada item ao slot de origem) — ver
 * relatório de implementação.
 *
 * BINDER-TRAY-POSITION-01 (2026-08-29, mesma rodada) — correção de
 * composição: o posicionamento original do controle (badge `absolute`
 * centralizado sobre a lombada/topo da moldura, dentro deste componente) foi
 * REJEITADO por Fabrício — "prejudica hierarquia visual, leitura física do
 * Binder, navegação e composição da lombada". Nova direção: a Bandeja é uma
 * ferramenta do WORKSPACE do Binder, não parte física dele. Só o BOTÃO
 * (`TrayToggleButton`) mudou de lugar — via `createPortal` para
 * `trayPortalNode` (prop nova, o nó DOM da célula direita da faixa de
 * paginação em `binder-nav-view.tsx`) — TUDO o resto (semântica, estado,
 * `handleDragEnd`, announcements, sensores, edge navigation, Add/Replace,
 * DnD slot→slot) permanece exatamente como estava; nenhum desses foi
 * reaberto nesta rodada. `TraySurface` (o painel) continua renderizada
 * diretamente aqui (não portalada) — só passou a receber `anchor`,
 * calculado por `handleToggleTray` a partir da posição real do botão
 * portalado no momento em que a Bandeja abre, para abrir "abaixo, alinhada
 * pela direita" dele em vez de um canto fixo genérico da tela. Durante um
 * arrasto (`dragActive`), o próprio botão se expande fisicamente (ver
 * `binder-tray.tsx`) — a colisão do dnd-kit usa o retângulo REAL do nó, que
 * já reflete esse tamanho maior, sem nenhuma configuração extra.
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
  onNavigatePrev,
  onNavigateNext,
  canNavigatePrev,
  canNavigateNext,
  trayPortalNode,
  toolRailPortalNode,
  isFullscreen,
  onToggleFullscreen,
}: {
  left: LeftPanel;
  right: RightPanel;
  direction: 1 | -1;
  animate: boolean;
  /** BINDER-DND-01 — mesmos `goPrev`/`goNext` de `binder-nav-view.tsx`, reaproveitados pelas zonas de borda de arrasto (Caso 3). */
  onNavigatePrev: () => void;
  onNavigateNext: () => void;
  canNavigatePrev: boolean;
  canNavigateNext: boolean;
  /** BINDER-TRAY-POSITION-01 — nó DOM (na faixa de navegação de `binder-nav-view.tsx`) onde o botão da Bandeja é portalado. `null` até o primeiro commit do pai. */
  trayPortalNode: HTMLElement | null;
  /** BINDER-TOOL-RAIL-03 — nó DOM (item de flex dedicado, irmão da seta esquerda, em `binder-nav-view.tsx`) onde a Tool Rail é portalada. `null` até o primeiro commit do pai. */
  toolRailPortalNode: HTMLElement | null;
  /** BINDER-TOOL-RAIL-03 — estado/toggle de tela cheia, vivem em `binder-nav-view.tsx` (dono do `dialogRef`/container real a ser colocado em fullscreen); só repassados aqui para a ação fixa "Tela cheia" da Tool Rail. */
  isFullscreen: boolean;
  onToggleFullscreen: () => void;
}) {
  const isCoverSpread = left.kind === "insideCover";
  const isBackCoverSpread = right.kind === "backCover";

  // BINDER-BULK-ACTION-RAIL-POSITION-01 (2026-08-29) — `rootRef` passou a
  // apontar para o WRAPPER externo (`position: relative`, sem
  // `overflow-hidden`), não mais para a moldura de couro em si — ver
  // doc-comment completo no JSX abaixo, junto do `BulkActionRail`. Os dois
  // usos existentes de `rootRef` (listener de "clique fora" que limpa
  // `selectedSlotId`, e `onKeyDown` do Escape) continuam corretos com essa
  // mudança: agora cobrem tanto a moldura quanto o rail lateral, que passou
  // a viver FORA dela.
  const rootRef = useRef<HTMLDivElement>(null);

  const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
  const [removedSlotIds, setRemovedSlotIds] = useState<Set<string>>(() => new Set());
  const [cardOverrides, setCardOverrides] = useState<Map<string, RealCardData>>(() => new Map());
  const [favoriteCardIds, setFavoriteCardIds] = useState<Set<string>>(() => new Set());
  const [lockedSlotIds, setLockedSlotIds] = useState<Set<string>>(() => new Set());
  // BINDER-MULTISELECT-BULK-01 — seleção múltipla para Bulk Actions. QUARTO
  // estado independente, distinto de `selectedSlotId` (seleção única que só
  // revela a cápsula de quick actions, ver `binder-slot-full.tsx`). Set de
  // ids de SLOT (placement), nunca de Card — coerente com o resto do
  // modelo de estado deste arquivo (`lockedSlotIds`/`removedSlotIds`
  // também são por slot, não por card). Escopo V1: só slots do spread
  // ATUAL — limpo ao trocar de spread (useEffect de `spreadKey` abaixo) e
  // nunca acumula entre páginas, "evita estados invisíveis difíceis de
  // compreender" (pedido explícito de Fabrício).
  const [multiSelectedSlotIds, setMultiSelectedSlotIds] = useState<Set<string>>(() => new Set());
  const isMultiSelectActive = multiSelectedSlotIds.size > 0;
  // Mensagem de status das Bulk Actions — reporta resultado (ex.: slots
  // bloqueados ignorados em "Mover para Bandeja") tanto visualmente (dentro
  // da própria Bulk Action Bar) quanto para leitor de tela
  // (`aria-live="polite"`, ver JSX da barra) — sem precisar de um sistema de
  // toast novo (nenhuma dependência nova permitida nesta rodada).
  const [bulkStatusMessage, setBulkStatusMessage] = useState<string | null>(null);
  const bulkStatusTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const announceBulkStatus = useCallback((message: string) => {
    if (bulkStatusTimerRef.current) clearTimeout(bulkStatusTimerRef.current);
    setBulkStatusMessage(message);
    bulkStatusTimerRef.current = setTimeout(() => setBulkStatusMessage(null), 4000);
  }, []);
  const [detailState, setDetailState] = useState<{ slotId: string; card: MockCardData | RealCardData } | null>(null);
  const detailTriggerRef = useRef<HTMLElement | null>(null);
  // BINDER-ADD-REPLACE-CARD-01 — estado do Card Picker, mesmo nível/racional de `detailState` acima.
  const [pickerState, setPickerState] = useState<{
    mode: "add" | "replace";
    slotId: string;
    currentCard?: MockCardData | RealCardData;
  } | null>(null);
  const pickerTriggerRef = useRef<HTMLElement | null>(null);
  // BINDER-DND-01 — snapshot da carta sendo arrastada, ver doc-comment do
  // arquivo. BINDER-TRAY-01 — `slotId` virou `from: DragOrigin` para que o
  // mesmo snapshot também represente um arrasto originado da Bandeja (ver
  // `resolveDragOrigin` acima).
  const [activeDrag, setActiveDrag] = useState<{ from: DragOrigin; card: RealCardData } | null>(null);
  const edgeNavTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // BINDER-DND-EDGE-NAV-RACE-01 (2026-08-30) — "refs espelho", lidas em
  // tempo de DISPARO do timer de navegação (dentro do próprio `setTimeout`),
  // nunca por closure do momento em que o timer foi agendado. O bug
  // reportado: em alguns drags até a Bandeja, o drop concluía normalmente e,
  // "logo depois", o Binder navegava sozinho — sintoma de um timer de edge
  // navigation que sobrevivia ao fim do drag.
  //
  // Investigação: `handleDragEnd`/`handleDragCancel` já chamavam
  // `clearEdgeNavTimer()` incondicionalmente como primeira linha, e
  // `handleDragOver` já limpava o timer sempre que `over` deixava de ser
  // uma edge zone — ou seja, os pontos de cancelamento pedidos no
  // checklist (onDragEnd, onDragCancel, sair da EdgeNavZone) já existiam.
  // Também tracei o próprio dnd-kit instalado (`node_modules/@dnd-kit/core`
  // 6.3.1, `core.esm.js`): o efeito interno que despacha `onDragOver` só
  // roda se `activeRef.current` (setado a `null` de forma SÍNCRONA dentro
  // de `handleEnd`, antes de qualquer dispatch de `onDragEnd`) ainda for
  // não-nulo — ou seja, o próprio dnd-kit já impede, por design, que um
  // `onDragOver` antigo dispare DEPOIS de um `onDragEnd`.
  //
  // O que NENHUM dos dois níveis garantia: uma revalidação em tempo de
  // DISPARO do próprio `setTimeout`. O agendamento (`scheduleEdgeNav`) só
  // validava as condições no momento em que foi CRIADO; o callback que
  // executa ~650ms depois nunca conferia se o drag ainda estava ativo, se o
  // `over` atual ainda era a MESMA edge, ou se a direção continuava
  // navegável — só confiava cegamente em `edgeNavTimerRef.current` ter sido
  // zerado a tempo por algum dos cancelamentos acima. Não foi possível
  // reproduzir interativamente neste ambiente (sandbox sem navegador capaz
  // de simular um drag real com o app rodando — ver relatório), então esta
  // é a lacuna comprovada por leitura de código, não por log ao vivo: o
  // pipeline de cancelamento é bom mas não tinha uma segunda linha de
  // defesa. As três refs abaixo fecham essa lacuna — ver `scheduleEdgeNav`.
  const activeDragRef = useRef<{ from: DragOrigin; card: RealCardData } | null>(null);
  const currentOverIdRef = useRef<string | number | null>(null);
  const canNavigatePrevRef = useRef(canNavigatePrev);
  const canNavigateNextRef = useRef(canNavigateNext);
  canNavigatePrevRef.current = canNavigatePrev;
  canNavigateNextRef.current = canNavigateNext;

  // BINDER-TRAY-01 — estado da Bandeja. TERCEIRO estado independente,
  // paralelo a `cardOverrides`/`removedSlotIds` (que descrevem "o que está
  // em cada SLOT") — `trayItems` descreve "quais cartas estão FORA de
  // qualquer slot, temporariamente". Uma carta nunca aparece nos dois ao
  // mesmo tempo: sair de um slot para a Bandeja é sempre `emptySlot` +
  // adicionar aqui, na mesma atualização (`handleDragEnd` abaixo); sair da
  // Bandeja para um slot é sempre `fillSlot` + remover daqui. `RealCardData`
  // completo (não só o id) porque, ao sair do slot, a linha correspondente
  // de `cardOverrides` é apagada — sem guardar o objeto aqui, a carta
  // "desapareceria" de vez, não ficaria só temporariamente ausente do
  // layout. Deduplicado por `card.id` (nunca duas entradas para o mesmo
  // Inventory Item). Não é resetado no `useEffect` de troca de spread
  // (abaixo) — a Bandeja precisa sobreviver à navegação entre páginas, é
  // esse o ponto do recurso ("drag para Bandeja → navegar → abrir Bandeja
  // → drag da Bandeja → slot desejado").
  const [trayItems, setTrayItems] = useState<RealCardData[]>([]);
  const [trayOpen, setTrayOpen] = useState(false);
  // BINDER-TRAY-REPOSITION-01 — posição real do botão (agora um dock
  // centralizado abaixo do Binder, ver `binder-tray.tsx`/
  // `binder-nav-view.tsx`), medida sob demanda ao abrir, para ancorar
  // `TraySurface` centralizada horizontalmente sob o dock e "emergindo"
  // dele para CIMA (em direção ao Binder, não para baixo/fora de tela — o
  // dock já fica perto do rodapé do diálogo). `null` em telas estreitas
  // (`< 640px`, de propósito — ver doc-comment de `TraySurface`) ou antes
  // de qualquer medição.
  const trayButtonRef = useRef<HTMLButtonElement | null>(null);
  const [trayAnchor, setTrayAnchor] = useState<{ bottom: number; left: number } | null>(null);

  const addToTray = useCallback((card: RealCardData) => {
    setTrayItems((prev) => (prev.some((c) => c.id === card.id) ? prev : [...prev, card]));
  }, []);
  const removeFromTray = useCallback((cardId: string) => {
    setTrayItems((prev) => prev.filter((c) => c.id !== cardId));
  }, []);

  const handleToggleTray = useCallback(() => {
    setTrayOpen((wasOpen) => {
      const willOpen = !wasOpen;
      if (willOpen && trayButtonRef.current && typeof window !== "undefined" && window.innerWidth >= 640) {
        const rect = trayButtonRef.current.getBoundingClientRect();
        // Centralizado sob o meio do dock, sujeito a uma margem mínima de
        // 8px das bordas do viewport (dock pode estar perto o bastante da
        // borda para o painel de 280px estourar sem esse clamp).
        const left = Math.min(
          Math.max(8, rect.left + rect.width / 2 - TRAY_SURFACE_WIDTH_PX / 2),
          window.innerWidth - TRAY_SURFACE_WIDTH_PX - 8,
        );
        setTrayAnchor({ bottom: window.innerHeight - rect.top + 8, left });
      } else if (willOpen) {
        setTrayAnchor(null);
      }
      return willOpen;
    });
  }, []);

  const clearEdgeNavTimer = useCallback(() => {
    if (edgeNavTimerRef.current) {
      clearTimeout(edgeNavTimerRef.current);
      edgeNavTimerRef.current = null;
    }
  }, []);

  // BINDER-DND-01 — as duas operações atômicas de "o que está em cada
  // bolso" (ver doc-comment do arquivo). `fillSlot`/`emptySlot` substituem
  // a manipulação direta de `cardOverrides`/`removedSlotIds` que existia
  // espalhada em `handleSelectPickerCard`/`handleRemove` antes desta rodada.
  const fillSlot = useCallback((slotId: string, card: RealCardData) => {
    setCardOverrides((prev) => {
      const next = new Map(prev);
      next.set(slotId, card);
      return next;
    });
    setRemovedSlotIds((prev) => {
      if (!prev.has(slotId)) return prev;
      const next = new Set(prev);
      next.delete(slotId);
      return next;
    });
  }, []);

  // BINDER-MULTISELECT-UX-01 (2026-08-29) — pedido explícito: "se uma carta
  // selecionada for movida/removida/esvaziada, remover imediatamente aquele
  // slot da seleção. Eliminar seleção stale." `emptySlot` é a ÚNICA
  // operação atômica que esvazia um slot, reaproveitada por Remove
  // individual, Bulk Remove, MOVE/SWAP via DnD (origem) e Bulk → Bandeja —
  // corrigir aqui, na fonte única, cobre todos esses caminhos de uma vez,
  // sem precisar duplicar a limpeza em cada chamador. Na prática, DnD já
  // fica desligado durante multi-select (ver `binder-slot-full.tsx`) e as
  // Bulk Actions já limpam a seleção INTEIRA ao final — este guard é
  // defesa em profundidade para qualquer caminho futuro que esvazie um
  // slot sem passar por um desses fluxos.
  const emptySlot = useCallback((slotId: string) => {
    setRemovedSlotIds((prev) => new Set(prev).add(slotId));
    setCardOverrides((prev) => {
      if (!prev.has(slotId)) return prev;
      const next = new Map(prev);
      next.delete(slotId);
      return next;
    });
    setMultiSelectedSlotIds((prev) => {
      if (!prev.has(slotId)) return prev;
      const next = new Set(prev);
      next.delete(slotId);
      return next;
    });
  }, []);

  const clearSelection = useCallback(() => {
    setSelectedSlotId(null);
  }, []);

  // BINDER-MULTISELECT-BULK-01 — toggle único, reaproveitado tanto pela nova
  // Quick Action "Selecionar" (`slot-quick-actions.tsx`) quanto pelo
  // Ctrl/Cmd+click e pelo "clicar em outra carta enquanto o modo está
  // ativo" (`binder-slot-full.tsx`) — um único ponto de verdade para
  // "entrar/sair da seleção múltipla de UM slot".
  const toggleMultiSelect = useCallback((slotId: string) => {
    setMultiSelectedSlotIds((prev) => {
      const next = new Set(prev);
      if (next.has(slotId)) next.delete(slotId);
      else next.add(slotId);
      return next;
    });
  }, []);

  const clearMultiSelection = useCallback(() => {
    setMultiSelectedSlotIds(new Set());
  }, []);

  // BINDER-MULTISELECT-BULK-01 — resolve a carta REAL efetivamente presente
  // num slot AGORA, reaproveitando exatamente a mesma regra de precedência
  // que `SlotsGrid` já usa internamente para `effectiveSlot` (removido >
  // override > base) — sem duplicar essa lógica, as Bulk Actions agem sobre
  // o mesmo estado visível ao usuário, nunca um snapshot desatualizado.
  // Escopada ao spread atual (`left`/`right`), coerente com o escopo V1 de
  // seleção ("só slots montados/visíveis nesta rodada").
  const resolveEffectiveCard = useCallback(
    (slotId: string): RealCardData | undefined => {
      if (removedSlotIds.has(slotId)) return undefined;
      const override = cardOverrides.get(slotId);
      if (override) return override;
      const baseSlots = [
        ...(left.kind === "page" ? left.page.slots : []),
        ...(right.kind === "page" ? right.page.slots : []),
      ];
      const baseCard = baseSlots.find((s) => s.id === slotId)?.card;
      return baseCard && "imageUrl" in baseCard ? baseCard : undefined;
    },
    [removedSlotIds, cardOverrides, left, right],
  );

  // BINDER-TOOL-RAIL-02 (2026-08-29) — alvo da ação fixa "Adicionar carta"
  // da Tool Rail (`tool-rail.tsx`). É uma ação GLOBAL (não nasce de um
  // clique num slot vazio específico, como o fluxo individual já existente
  // em `slot-quick-actions.tsx`), então precisa resolver sozinha QUAL slot
  // preencher: o primeiro slot vazio do SPREAD ATUAL, na mesma ordem em que
  // `SlotsGrid` os renderiza (`left.page.slots` seguido de
  // `right.page.slots`) — mesma regra de "vazio" que `resolveEffectiveCard`
  // já usa em todo o resto do arquivo (removido > override > base),
  // reaproveitada aqui via o mesmo helper, não duplicada. `null` quando o
  // spread atual não tem nenhum slot vazio (ambas as páginas cheias, ou
  // `insideCover`/`backCover`, que não têm `slots`) — a Tool Rail usa isso
  // para desabilitar o botão em vez de escondê-lo (ação real, só
  // contextualmente indisponível, mesmo padrão já usado por
  // `showLock`/`showUnlock`).
  const firstEmptySlotId = useMemo(() => {
    const baseSlots = [
      ...(left.kind === "page" ? left.page.slots : []),
      ...(right.kind === "page" ? right.page.slots : []),
    ];
    for (const s of baseSlots) {
      if (resolveEffectiveCard(s.id) === undefined) return s.id;
    }
    return null;
  }, [left, right, resolveEffectiveCard]);

  // BINDER-MULTISELECT-BULK-01 — Ação 1: Mover para Bandeja. Por slot
  // selecionado: se Locked, PULA (nunca move um slot bloqueado — "V1:
  // operações de layout respeitam Lock", pedido explícito) e conta para o
  // relatório; senão, mesma operação atômica MOVE já usada por
  // `handleDragEnd` (SLOT → BANDEJA): `addToTray` + `emptySlot`, nunca
  // COPY. Seleção inteira é limpa ao final, MESMO com itens pulados —
  // escolha deliberada por previsibilidade (evita um estado residual de
  // "seleção parcial" confuso; itens não movidos continuam visíveis no
  // layout e podem ser reselecionados se necessário). Documentado no
  // relatório final, não uma omissão.
  const handleBulkMoveToTray = useCallback(() => {
    const slotIds = Array.from(multiSelectedSlotIds);
    let moved = 0;
    let skippedLocked = 0;
    // Slot selecionado que não resolve mais a uma carta real (ex.: já
    // esvaziado por um DnD individual de item único enquanto ainda constava
    // em `multiSelectedSlotIds` — ver limitação documentada no relatório
    // final, "seleção não é sincronizada após um drag individual") —
    // contabilizado à parte de `skippedLocked` para o relatório continuar
    // preciso mesmo nesse caso de borda.
    let skippedOther = 0;
    for (const slotId of slotIds) {
      if (lockedSlotIds.has(slotId)) {
        skippedLocked += 1;
        continue;
      }
      const card = resolveEffectiveCard(slotId);
      if (!card) {
        skippedOther += 1;
        continue;
      }
      addToTray(card);
      emptySlot(slotId);
      moved += 1;
    }
    clearMultiSelection();
    const parts = [`${moved} movida${moved === 1 ? "" : "s"} para a Bandeja.`];
    if (skippedLocked > 0) parts.push(`${skippedLocked} não movida${skippedLocked === 1 ? "" : "s"} — slot bloqueado.`);
    if (skippedOther > 0) parts.push(`${skippedOther} ignorada${skippedOther === 1 ? "" : "s"} — slot já vazio.`);
    announceBulkStatus(parts.join(" "));
  }, [multiSelectedSlotIds, lockedSlotIds, resolveEffectiveCard, addToTray, emptySlot, clearMultiSelection, announceBulkStatus]);

  // BINDER-MULTISELECT-BULK-01 — Ações 2/3: Bloquear/Desbloquear em lote.
  // Não alteram carta/item, só `lockedSlotIds` — mesmo racional de
  // `handleToggleLock`, mas aplicado ao conjunto inteiro de uma vez (nunca
  // um toggle por item: "Bloquear" sempre bloqueia todos os selecionados,
  // "Desbloquear" sempre desbloqueia todos, independente do estado
  // individual prévio de cada um). Seleção é MANTIDA após a ação — ao
  // contrário de Mover/Remover (destrutivas/alteram layout), Lock/Unlock
  // são reversíveis e não removem a carta do lugar selecionado, então
  // manter a seleção permite ao usuário encadear outra ação em seguida
  // (ex.: bloquear e, na sequência, revisar/limpar manualmente) sem
  // precisar reselecionar o mesmo grupo — escolha documentada, pedido
  // explícito de Fabrício ("escolher o comportamento mais coerente").
  const handleBulkLock = useCallback(() => {
    const count = multiSelectedSlotIds.size;
    setLockedSlotIds((prev) => {
      const next = new Set(prev);
      multiSelectedSlotIds.forEach((id) => next.add(id));
      return next;
    });
    announceBulkStatus(`${count} bloqueada${count === 1 ? "" : "s"}.`);
  }, [multiSelectedSlotIds, announceBulkStatus]);

  const handleBulkUnlock = useCallback(() => {
    const count = multiSelectedSlotIds.size;
    setLockedSlotIds((prev) => {
      const next = new Set(prev);
      multiSelectedSlotIds.forEach((id) => next.delete(id));
      return next;
    });
    announceBulkStatus(`${count} desbloqueada${count === 1 ? "" : "s"}.`);
  }, [multiSelectedSlotIds, announceBulkStatus]);

  // BINDER-MULTISELECT-BULK-02 — "Bloquear"/"Desbloquear" contextuais na
  // Bulk Action Bar, pedido explícito: "evitar mostrar as duas
  // simultaneamente quando não necessário." Se TODOS os selecionados já
  // estão desbloqueados, só faz sentido oferecer "Bloquear" (e
  // vice-versa); numa seleção mista, as duas continuam disponíveis (regra
  // explícita da V1, sem dropdown/menu novo). Set vazio (sem seleção) não
  // é um caso real — a barra inteira só existe quando `count > 0` — mas
  // `allUnlocked` parte de `true`/`allLocked` de `true` como neutros para
  // não quebrar o cálculo caso chamado nesse instante transitório.
  const bulkLockState = useMemo(() => {
    let allLocked = multiSelectedSlotIds.size > 0;
    let allUnlocked = true;
    multiSelectedSlotIds.forEach((id) => {
      if (lockedSlotIds.has(id)) allUnlocked = false;
      else allLocked = false;
    });
    return { allLocked, allUnlocked };
  }, [multiSelectedSlotIds, lockedSlotIds]);

  // BINDER-MULTISELECT-BULK-02 (2026-08-29) — Ação 4: Remover em lote,
  // semântica de Lock CORRIGIDA. A rodada anterior (BINDER-MULTISELECT-
  // BULK-01) tinha reportado, em vez de inventado, que "Remover do slot"
  // individual não verificava `isLocked` — Fabrício confirmou nesta rodada
  // que essa era uma inconsistência real a corrigir, não um comportamento
  // a preservar: "LOCK = proteção do layout... Locked deve impedir...
  // Remove... Bulk Remove." `handleRemove` (individual, abaixo) e este
  // handler agora SKIPAM slots bloqueados, mesmo padrão já usado por
  // `handleBulkMoveToTray` (conta e reporta em vez de falhar
  // silenciosamente ou pedir confirmação — "a ação deve ficar
  // indisponível ou ser ignorada de forma clara"). Remove ≠ Bandeja:
  // `emptySlot` sem passar pela Bandeja, exatamente como antes.
  const handleBulkRemove = useCallback(() => {
    const slotIds = Array.from(multiSelectedSlotIds);
    let removed = 0;
    let skippedLocked = 0;
    for (const slotId of slotIds) {
      if (lockedSlotIds.has(slotId)) {
        skippedLocked += 1;
        continue;
      }
      emptySlot(slotId);
      setSelectedSlotId((current) => (current === slotId ? null : current));
      removed += 1;
    }
    clearMultiSelection();
    announceBulkStatus(
      skippedLocked > 0
        ? `${removed} removida${removed === 1 ? "" : "s"} do layout. ${skippedLocked} não removida${skippedLocked === 1 ? "" : "s"} — slot bloqueado.`
        : `${removed} removida${removed === 1 ? "" : "s"} do layout.`,
    );
  }, [multiSelectedSlotIds, lockedSlotIds, emptySlot, clearMultiSelection, announceBulkStatus]);

  // Seleção é sobre um slot físico da posição ATUAL — ao trocar de spread não
  // há mais um "slot selecionado" coerente para manter. `spreadKey` usa os
  // ids reais (não a identidade de objeto de `left`/`right`, recriados a
  // cada render do pai mesmo sem navegação real).
  const spreadKey = `${left.kind === "page" ? left.page.id : left.kind}|${right.kind === "page" ? right.page.id : right.kind}`;
  useEffect(() => {
    clearSelection();
    setDetailState(null);
    setPickerState(null);
    // BINDER-MULTISELECT-BULK-01 — seleção múltipla é escopada ao spread
    // ATUAL (não implementamos seleção cross-page nesta rodada, pedido
    // explícito: "evita estados invisíveis difíceis de compreender").
    setMultiSelectedSlotIds(new Set());
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
      if (event.key !== "Escape") return;
      // BINDER-TRAY-01 — Esc fecha a Bandeja primeiro (é a UI mais "recente"
      // aberta). BINDER-MULTISELECT-BULK-01 — segundo nível: se HÁ seleção
      // múltipla ativa, Esc a limpa em seguida (só depois disso limpa a
      // seleção única de slot) — nunca duas coisas fechando/limpando de uma
      // vez só, mesmo racional de cascata já estabelecido para a Bandeja.
      if (trayOpen) {
        event.stopPropagation();
        setTrayOpen(false);
        return;
      }
      if (isMultiSelectActive) {
        event.stopPropagation();
        clearMultiSelection();
        return;
      }
      if (selectedSlotId) {
        // Evita que o mesmo Escape também feche o Binder inteiro (handler
        // do diálogo em `binder-nav-view.tsx`, mais acima na árvore real).
        event.stopPropagation();
        clearSelection();
      }
    },
    [trayOpen, isMultiSelectActive, clearMultiSelection, selectedSlotId, clearSelection],
  );

  const handleSelectSlot = useCallback((slotId: string) => {
    setSelectedSlotId((current) => (current === slotId ? null : slotId));
  }, []);

  const handleOpenAddPicker = useCallback((slotId: string, triggerEl: HTMLElement) => {
    pickerTriggerRef.current = triggerEl;
    setPickerState({ mode: "add", slotId });
  }, []);

  // BINDER-TOOL-RAIL-02 — ação fixa "Adicionar carta" da Tool Rail: mesmo
  // `handleOpenAddPicker` de sempre (nenhum picker novo), só decide sozinha
  // o slot-alvo (`firstEmptySlotId`, acima) em vez de receber um `slotId`
  // de um clique dentro de um slot específico. Sem slot vazio no spread
  // atual, ou sem o nó do próprio botão (guard defensivo, não deveria
  // acontecer — `ToolRail` só chama isto a partir do seu próprio `ref`), a
  // chamada é ignorada silenciosamente — o botão já vem `aria-disabled`
  // nesse caso (`tool-rail.tsx`), este é só defesa em profundidade.
  const handleGlobalAdd = useCallback(
    (triggerEl: HTMLElement | null) => {
      if (!firstEmptySlotId || !triggerEl) return;
      handleOpenAddPicker(firstEmptySlotId, triggerEl);
    },
    [firstEmptySlotId, handleOpenAddPicker],
  );

  // BINDER-MULTISELECT-BULK-02 (2026-08-29) — LOCK = proteção do layout,
  // "não pode ter sua composição alterada". Substituir muda a composição
  // do slot, então passa a ser bloqueado quando Locked. O botão já vem
  // `disabled` na origem (`slot-quick-actions.tsx`), então este guard é
  // defesa em profundidade (nenhum outro caminho de UI chama isto hoje,
  // mas evita reintroduzir o bug se um novo caminho aparecer sem passar
  // pelo botão) — ignorado de forma silenciosa e clara, sem confirmação,
  // pedido explícito de Fabrício.
  const handleOpenReplacePicker = useCallback(
    (slotId: string, currentCard: MockCardData | RealCardData, triggerEl: HTMLElement) => {
      if (lockedSlotIds.has(slotId)) return;
      pickerTriggerRef.current = triggerEl;
      setPickerState({ mode: "replace", slotId, currentCard });
    },
    [lockedSlotIds],
  );

  const handleClosePicker = useCallback(() => {
    setPickerState(null);
    const trigger = pickerTriggerRef.current;
    pickerTriggerRef.current = null;
    // Mesmo padrão de `handleCloseDetail` — restaura o foco só depois do
    // próximo paint. Diferença deliberada em relação ao Card Detail: no
    // fluxo REPLACE o botão "Substituir carta" continua no DOM (slot
    // ocupado antes e depois), mas no fluxo ADD bem-sucedido o botão
    // "Adicionar carta" deixa de existir — o slot muda de branch vazio→
    // ocupado no mesmo render que fecha o picker. `isConnected` evita
    // chamar `.focus()` num nó já desmontado (no-op silencioso no browser,
    // mas melhor checar explicitamente); quando isso acontece, o foco não é
    // forçado para outro lugar nesta rodada — ver relatório de
    // implementação, "próximo bloqueio funcional real".
    if (trigger && trigger.isConnected) requestAnimationFrame(() => trigger.focus());
  }, []);

  const handleSelectPickerCard = useCallback(
    (card: RealCardData) => {
      const current = pickerState;
      if (!current) return;
      fillSlot(current.slotId, card);
      handleClosePicker();
    },
    [pickerState, fillSlot, handleClosePicker],
  );

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

  // BINDER-MULTISELECT-BULK-02 — correção de semântica reportada na rodada
  // anterior: "Remover do slot" não verificava Lock. Passa a ignorar a
  // chamada quando o slot está bloqueado (defesa em profundidade — o botão
  // já vem `disabled` em `slot-quick-actions.tsx`), mesmo padrão do guard
  // de `handleOpenReplacePicker` acima.
  const handleRemove = useCallback(
    (slotId: string) => {
      if (lockedSlotIds.has(slotId)) return;
      emptySlot(slotId);
      setSelectedSlotId((current) => (current === slotId ? null : current));
    },
    [lockedSlotIds, emptySlot],
  );

  const handleToggleFavorite = useCallback((cardId: string) => {
    setFavoriteCardIds((current) => {
      const next = new Set(current);
      if (next.has(cardId)) next.delete(cardId);
      else next.add(cardId);
      return next;
    });
  }, []);

  const handleToggleLock = useCallback((slotId: string) => {
    setLockedSlotIds((current) => {
      const next = new Set(current);
      if (next.has(slotId)) next.delete(slotId);
      else next.add(slotId);
      return next;
    });
  }, []);

  // BINDER-DND-01 — sensores. `distance: 4` no pointer é higiene geral, não
  // o mecanismo principal de diferenciação clique×arrasto (isso é resolvido
  // pela alça física separada, ver doc-comment do arquivo). `delay`/
  // `tolerance` no touch seguem o padrão "long-press" documentado do
  // dnd-kit para não competir com rolagem da página.
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 8 } }),
    useSensor(KeyboardSensor),
  );

  const handleDragStart = useCallback((event: DragStartEvent) => {
    const data = event.active.data.current as { card?: RealCardData } | undefined;
    if (!data?.card) return;
    const drag = { from: resolveDragOrigin(String(event.active.id)), card: data.card };
    // BINDER-DND-EDGE-NAV-RACE-01 — grava na ref ANTES/junto do state, para
    // que `scheduleEdgeNav` (disparado até 650ms depois, dentro de um
    // `setTimeout`) sempre leia o valor mais recente, nunca uma closure do
    // momento do agendamento.
    activeDragRef.current = drag;
    currentOverIdRef.current = null;
    setActiveDrag(drag);
  }, []);

  const scheduleEdgeNav = useCallback(
    (edge: "prev" | "next") => {
      if (edgeNavTimerRef.current) return; // já agendado — não reinicia o dwell a cada onDragOver repetido
      edgeNavTimerRef.current = setTimeout(() => {
        edgeNavTimerRef.current = null;
        // BINDER-DND-EDGE-NAV-RACE-01 — PROTEÇÃO EXTRA: revalida em tempo
        // de DISPARO (não só em tempo de agendamento) que (1) o drag ainda
        // está ativo, (2) o `over` atual ainda é esta MESMA edge — não uma
        // edge diferente, nem a Bandeja, nem um slot — e (3) a direção
        // continua navegável. `edgeNavTimerRef.current` já ter sido zerado
        // a tempo por `clearEdgeNavTimer()` é o caminho normal; isto aqui é
        // a segunda linha de defesa para qualquer callback que escape desse
        // cancelamento por qualquer razão. Ver doc-comment das refs acima
        // para a investigação completa.
        if (!activeDragRef.current) return;
        if (edge === "prev") {
          if (currentOverIdRef.current === EDGE_PREV_ID && canNavigatePrevRef.current) onNavigatePrev();
        } else {
          if (currentOverIdRef.current === EDGE_NEXT_ID && canNavigateNextRef.current) onNavigateNext();
        }
      }, EDGE_NAV_DWELL_MS);
    },
    [onNavigatePrev, onNavigateNext],
  );

  const handleDragOver = useCallback(
    (event: DragOverEvent) => {
      const overId = event.over?.id ?? null;
      // BINDER-DND-EDGE-NAV-RACE-01 — única fonte de verdade para "qual é o
      // `over` atual", lida por `scheduleEdgeNav` em tempo de disparo.
      currentOverIdRef.current = overId;
      if (overId === EDGE_PREV_ID && canNavigatePrev) {
        scheduleEdgeNav("prev");
        return;
      }
      if (overId === EDGE_NEXT_ID && canNavigateNext) {
        scheduleEdgeNav("next");
        return;
      }
      clearEdgeNavTimer();
    },
    [canNavigatePrev, canNavigateNext, scheduleEdgeNav, clearEdgeNavTimer],
  );

  const handleDragEnd = useCallback(
    (event: DragEndEvent) => {
      clearEdgeNavTimer();
      // BINDER-DND-EDGE-NAV-RACE-01 — zeradas JUNTO do cancelamento do
      // timer, antes de qualquer outra lógica: mesmo que um timer antigo
      // ainda dispare por algum caminho não coberto, `activeDragRef.current`
      // já será `null` e a proteção extra em `scheduleEdgeNav` aborta.
      activeDragRef.current = null;
      currentOverIdRef.current = null;
      const drag = activeDrag; // snapshot capturado em onDragStart — nunca relido do DOM
      setActiveDrag(null);
      if (!drag) return;

      const overId = event.over?.id;
      // Solto fora de qualquer droppable, ou sobre uma zona de borda (só
      // serve para navegar, não é destino de drop): nenhuma mudança de
      // estado.
      if (!overId || overId === EDGE_PREV_ID || overId === EDGE_NEXT_ID) return;
      const overIdStr = String(overId);

      // Solto sobre a própria origem — slot sobre si mesmo, ou item da
      // Bandeja solto de volta na própria Bandeja: no-op nos dois casos.
      if (drag.from.type === "slot" && overIdStr === drag.from.slotId) return;
      if (drag.from.type === "tray" && overIdStr === TRAY_DROP_ID) return;

      if (overIdStr === TRAY_DROP_ID) {
        // BINDER-TRAY-01 — SLOT → BANDEJA. Só alcançável aqui quando a
        // origem é um slot (tray→tray já voltou como no-op acima): o item
        // se junta à Bandeja e o slot de origem esvazia — MOVE, nunca COPY.
        addToTray(drag.card);
        if (drag.from.type === "slot") emptySlot(drag.from.slotId);
        return;
      }

      // Destino é um slot real (vazio ou ocupado).
      const destinationSlotId = overIdStr;
      const overData = event.over?.data.current as { card?: RealCardData } | undefined;
      const destinationCard = overData?.card;

      if (destinationCard) {
        // SWAP — a carta de origem ocupa o destino; a que estava lá vai
        // para onde a origem "morava": outro slot (Caso 2 de sempre) OU de
        // volta para a Bandeja (BANDEJA → SLOT OCUPADO, pedido explícito:
        // "evita perda de item e mantém operação reversível").
        fillSlot(destinationSlotId, drag.card);
        if (drag.from.type === "slot") {
          fillSlot(drag.from.slotId, destinationCard);
        } else {
          removeFromTray(drag.card.id);
          addToTray(destinationCard);
        }
      } else {
        // MOVE para slot vazio — de outro slot (Caso 1 de sempre) ou da
        // Bandeja (BANDEJA → SLOT VAZIO).
        fillSlot(destinationSlotId, drag.card);
        if (drag.from.type === "slot") {
          emptySlot(drag.from.slotId);
        } else {
          removeFromTray(drag.card.id);
        }
      }
    },
    [activeDrag, clearEdgeNavTimer, fillSlot, emptySlot, addToTray, removeFromTray],
  );

  const handleDragCancel = useCallback(
    (_event: DragCancelEvent) => {
      clearEdgeNavTimer();
      // BINDER-DND-EDGE-NAV-RACE-01 — mesmo tratamento de `handleDragEnd`.
      activeDragRef.current = null;
      currentOverIdRef.current = null;
      setActiveDrag(null);
    },
    [clearEdgeNavTimer],
  );

  // BINDER-DND-01 — announcements em português para leitor de tela
  // (`accessibility.announcements` do `<DndContext>`, ver doc-comment do
  // arquivo). Descreve ocupação/lock do destino a partir do MESMO
  // `over.data.current` usado por `handleDragEnd` — não duplica lógica de
  // resolução de estado, só narra o que já foi calculado.
  const announcements: Announcements = useMemo(
    () => ({
      onDragStart({ active }) {
        const data = active.data.current as { card?: RealCardData } | undefined;
        if (!data?.card) return undefined;
        const fromTray = resolveDragOrigin(String(active.id)).type === "tray";
        return `Pegando ${data.card.name}${fromTray ? " da Bandeja" : ""}. Use as setas para escolher o destino, Enter ou Espaço para confirmar, Esc para cancelar.`;
      },
      onDragOver({ over }) {
        if (!over) return "Fora de qualquer slot.";
        if (over.id === EDGE_PREV_ID) return "Sobre a borda esquerda — segure para ir à página anterior.";
        if (over.id === EDGE_NEXT_ID) return "Sobre a borda direita — segure para ir à próxima página.";
        if (over.id === TRAY_DROP_ID) return "Sobre a Bandeja — soltar move a carta para lá.";
        const overData = over.data.current as { card?: RealCardData } | undefined;
        if (over.disabled) return "Sobre um slot bloqueado — não é possível soltar aqui.";
        return overData?.card ? `Sobre slot ocupado por ${overData.card.name} — soltar troca as duas cartas.` : "Sobre slot vazio — soltar move a carta para cá.";
      },
      onDragEnd({ active, over }) {
        const data = active.data.current as { card?: RealCardData } | undefined;
        const cardName = data?.card?.name ?? "Carta";
        const fromTray = resolveDragOrigin(String(active.id)).type === "tray";
        if (
          !over ||
          over.id === active.id ||
          over.id === EDGE_PREV_ID ||
          over.id === EDGE_NEXT_ID ||
          (fromTray && over.id === TRAY_DROP_ID)
        ) {
          return `${cardName} permaneceu ${fromTray ? "na Bandeja" : "no slot original"}.`;
        }
        if (over.id === TRAY_DROP_ID) {
          return `${cardName} movida para a Bandeja.`;
        }
        const overData = over.data.current as { card?: RealCardData } | undefined;
        if (overData?.card) {
          return fromTray
            ? `${cardName} trocou de posição com ${overData.card.name} — ${overData.card.name} foi para a Bandeja.`
            : `${cardName} trocou de posição com ${overData.card.name}.`;
        }
        return fromTray ? `${cardName} movida da Bandeja para o slot.` : `${cardName} movida para o novo slot.`;
      },
      onDragCancel() {
        return "Movimento cancelado — a carta permaneceu no lugar original.";
      },
    }),
    [],
  );

  const slotsGridProps = useMemo(
    () => ({
      selectedSlotId,
      favoriteCardIds,
      lockedSlotIds,
      removedSlotIds,
      cardOverrides,
      multiSelectedSlotIds,
      isMultiSelectActive,
      onSelectSlot: handleSelectSlot,
      onAddCard: handleOpenAddPicker,
      onOpenDetail: handleOpenDetail,
      onReplace: handleOpenReplacePicker,
      onRemove: handleRemove,
      onToggleFavorite: handleToggleFavorite,
      onToggleLock: handleToggleLock,
      onToggleMultiSelect: toggleMultiSelect,
    }),
    [
      selectedSlotId,
      favoriteCardIds,
      lockedSlotIds,
      removedSlotIds,
      cardOverrides,
      multiSelectedSlotIds,
      isMultiSelectActive,
      handleSelectSlot,
      handleOpenAddPicker,
      handleOpenDetail,
      handleOpenReplacePicker,
      handleRemove,
      handleToggleFavorite,
      handleToggleLock,
      toggleMultiSelect,
    ],
  );

  const detailParsed = detailState ? parseBinderSlotId(detailState.slotId) : null;

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={binderCollisionDetection}
      accessibility={{ announcements }}
      onDragStart={handleDragStart}
      onDragOver={handleDragOver}
      onDragEnd={handleDragEnd}
      onDragCancel={handleDragCancel}
    >
      {/* BINDER-TOOL-RAIL-03 (2026-08-30) — a estrutura de DOIS `<div>`
          aninhados introduzida em BINDER-BULK-ACTION-RAIL-POSITION-01 (um
          wrapper externo `relative` só para hospedar a Tool Rail como irmã
          da moldura, escapando do `overflow-hidden` dela) foi REVERTIDA
          para um único `<div>` — pedido explícito desta rodada: "corrigir
          ESTRUTURALMENTE... não resolver com novos offsets absolutos
          arbitrários". A Tool Rail deixou de ser posicionada por
          CSS absoluto calculado a partir do Binder e passou a ser um item
          de FLEX comum, irmão da seta esquerda, dentro da mesma faixa
          `[TOOL RAIL] [SETA] [BINDER] [SETA]` de `binder-nav-view.tsx` —
          ver doc-comment completo lá e no bloco de portal mais abaixo
          (`toolRailPortalNode`). Sem a Tool Rail para hospedar, este
          wrapper extra não tinha mais função nenhuma — `ref={rootRef}`/
          `onKeyDown={handleKeyDown}` voltam para a própria moldura de
          couro, exatamente como antes de POSITION-01. */}
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
        {/* BINDER-DND-01 — zonas de borda para navegação de spread durante um
            arrasto (Caso 3). Finas, discretas, só se destacam quando um
            arrasto está sobre elas. Ver doc-comment do arquivo. */}
        <EdgeNavZone edge="prev" active={!!activeDrag} enabled={canNavigatePrev} />
        <EdgeNavZone edge="next" active={!!activeDrag} enabled={canNavigateNext} />


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

      {/* Card Picker — mesmo racional de posicionamento do Card Detail acima
          (irmão da moldura, fora da árvore com `transform`/`perspective`). */}
      {pickerState && (
        <CardPickerModal
          mode={pickerState.mode}
          currentCard={pickerState.currentCard}
          onSelect={handleSelectPickerCard}
          onClose={handleClosePicker}
        />
      )}

      {/* BINDER-TRAY-01 — superfície da Bandeja, mesmo racional de
          posicionamento do Card Detail/Picker acima (irmã da moldura, fora
          da árvore com `transform`/`perspective`/`overflow-hidden`). NÃO é
          modal — o resto do Binder continua interativo com ela aberta. */}
      {trayOpen && <TraySurface items={trayItems} onClose={() => setTrayOpen(false)} anchor={trayAnchor} />}

      {/* BINDER-TRAY-POSITION-01 — o dock da Bandeja é portalado para fora da
          moldura, para dentro da faixa de navegação de
          `binder-nav-view.tsx` (ao lado da paginação « ‹ 2/14 › »). Continua
          logicamente dentro desta árvore — dentro do `<DndContext>`, com
          acesso a `trayItems`/`activeDrag`/etc. — só a localização no DOM
          muda; `ref` (`trayButtonRef`) segue a árvore do React, não o
          portal, então a medição de posição para `TraySurface` continua
          funcionando normalmente.
          BINDER-TRAY-DOCK-02 (2026-08-30) — `count`/`open`/`onToggle`
          voltam a esta chamada (tinham saído em TOOL-RAIL-02): o dock é de
          novo um controle permanente/clicável, coexistindo deliberadamente
          com a ação fixa "Bandeja" da Tool Rail (abaixo) — as duas chamam
          o MESMO `handleToggleTray`. Ver doc-comment completo de
          `TrayToggleButton` para o histórico da reversão. */}
      {trayPortalNode &&
        createPortal(
          <TrayToggleButton
            ref={trayButtonRef}
            count={trayItems.length}
            open={trayOpen}
            dragActive={!!activeDrag}
            onToggle={handleToggleTray}
          />,
          trayPortalNode,
        )}

      {/* BINDER-TOOL-RAIL-03 (2026-08-30) — mesmo racional de portal do
          botão da Bandeja logo acima: a Tool Rail é logicamente dona deste
          componente (acesso direto a todo o estado de multi-select/Bandeja/
          Add, sem prop-drilling adicional), só a localização no DOM muda —
          `binder-nav-view.tsx` reserva um item de FLEX dedicado na mesma
          faixa `[TOOL RAIL] [SETA] [BINDER] [SETA]` da navegação, ANTES da
          seta esquerda. Substitui o posicionamento `absolute`/
          `right-[calc(...)]` de BINDER-BULK-ACTION-RAIL-POSITION-01 —
          "corrigir estruturalmente... não resolver com novos offsets
          absolutos arbitrários", pedido explícito desta rodada. Ver
          doc-comment completo em `binder-nav-view.tsx`
          (`toolRailPortalNode`) para o racional da composição em flex. */}
      {toolRailPortalNode &&
        createPortal(
          <ToolRail
            canAdd={!!firstEmptySlotId}
            onAdd={handleGlobalAdd}
            trayOpen={trayOpen}
            trayCount={trayItems.length}
            onToggleTray={handleToggleTray}
            isFullscreen={isFullscreen}
            onToggleFullscreen={onToggleFullscreen}
            count={multiSelectedSlotIds.size}
            statusMessage={bulkStatusMessage}
            allLocked={bulkLockState.allLocked}
            allUnlocked={bulkLockState.allUnlocked}
            onMoveToTray={handleBulkMoveToTray}
            onLock={handleBulkLock}
            onUnlock={handleBulkUnlock}
            onRemove={handleBulkRemove}
            onClear={clearMultiSelection}
          />,
          toolRailPortalNode,
        )}

      {/* BINDER-DND-01 — preview do card sendo arrastado. Renderizado fora da
          árvore com `transform`/`perspective` pelo mesmo motivo do Card
          Detail/Picker acima; o dnd-kit posiciona este elemento via
          transform próprio, acompanhando o ponteiro/foco de teclado.

          BINDER-DND-DRAG-PREVIEW-01 (2026-08-29) — pedido de Fabrício: a
          carta durante o arrasto "fica pequena demais... parece um
          thumbnail... o ponto de fixação do ponteiro fica muito distante da
          carta." Causa raiz, confirmada lendo o source publicado do
          `@dnd-kit/core` (`PositionedOverlay`, `dist/core.esm.js`), não por
          tentativa: o WRAPPER que o `<DragOverlay>` renderiza já é
          posicionado E dimensionado corretamente por padrão —
          `width: rect.width, height: rect.height, top: rect.top, left:
          rect.left` vêm de `rect` (o `activeNodeRect`/`initialRect` do
          dnd-kit, medido automaticamente a partir do nó REAL do draggable —
          aqui, o slot inteiro em `binder-slot-full.tsx`, já que é lá que
          `setNodeRef` do `useDraggable` aponta, não a alça
          `DragHandleButton`/`setActivatorNodeRef` — activator e draggable
          node são propositalmente nós diferentes desde BINDER-DND-01, e só
          o draggable node importa para este cálculo). O `transform` que o
          dnd-kit aplica no wrapper é SÓ translação (`scaleX/scaleY: 1`,
          forçado sempre que a prop `adjustScale` não é passada — não
          passamos), acompanhando o delta do ponteiro em relação ao ponto
          onde o arrasto começou — ou seja, o dnd-kit já preserva sozinho a
          relação "pointer position ↔ retângulo original do draggable"
          (pedido explícito) SEM precisar de nenhum modifier customizado
          (`snapCenterToCursor` NÃO foi usado, nunca foi cogitado — mascararia
          o sintoma, não a causa).

          O bug inteiro estava no `<div>` FILHO que renderizamos dentro do
          `<DragOverlay>`: tinha `width` fixa em pixels (`w-[64px] sm:w-
          [76px]`, um valor de thumbnail arbitrário, sem relação com o
          tamanho real do slot de origem) em vez de preencher o wrapper já
          corretamente dimensionado. Como esse filho não ocupava 100% do
          wrapper, ele ficava plantado no canto superior-esquerdo do
          retângulo correto (comportamento padrão de bloco), pequeno e
          deslocado do ponteiro — exatamente os dois sintomas relatados, com
          a MESMA causa. Fix: `h-full w-full` no lugar da largura fixa — o
          filho passa a preencher o wrapper (que já tem `rect.width`/
          `rect.height` reais do slot/origem, entre ~90–100% do tamanho
          visual do card conforme a densidade responsiva do grid no momento,
          nunca um valor fixo). `rounded-[4px]` alinhado ao mesmo raio dos
          slots (era `[6px]`, inconsistente). "Levantar a carta": SÓ
          `transform: scale(1.02) rotate(-1deg)` no filho (dentro da faixa
          pedida, 1.00–1.03 / até ~2°) + sombra um pouco mais evidente — sem
          glow, sem bounce, sem thumbnail. Esse transform de escala/rotação
          fica numa camada separada do transform de translação do wrapper
          (pai só translada, filho só escala/rotaciona), então não interfere
          na ancoragem: a origem do transform do filho (`transform-origin`
          padrão, centro) desloca o card em frações de pixel, imperceptível
          nessa escala. Bandeja/slot→slot/Add-Replace/Lock/edge navigation:
          nada disso foi tocado — o preview não tem lógica própria de
          destino, só reflete `activeDrag.card`, que já existia. */}
      <DragOverlay dropAnimation={null}>
        {activeDrag ? (
          <div
            className="pointer-events-none h-full w-full overflow-hidden rounded-[4px]"
            style={{
              boxShadow: "0 20px 36px -14px rgba(0,0,0,0.8), 0 0 0 1px hsl(0 0% 100% / 0.14)",
              transform: "scale(1.02) rotate(-1deg)",
            }}
          >
            <RealCardFace card={activeDrag.card} />
          </div>
        ) : null}
      </DragOverlay>
      </div>
    </DndContext>
  );
}

/**
 * BINDER-DND-01 — zona de borda para navegação de spread durante um arrasto
 * (Caso 3: mover entre páginas). Um droppable fino e discreto (`EDGE_PREV_ID`
 * / `EDGE_NEXT_ID`) sobreposto à borda esquerda/direita da moldura. Enquanto
 * um arrasto está em curso e a navegação correspondente está disponível
 * (`enabled`), pairar sobre a zona agenda a troca de spread via
 * `scheduleEdgeNav` (dwell timer, ver `handleDragOver` em `BinderPagesNav`) —
 * o item permanece "em mãos" (`activeDrag`) e o usuário solta no destino já
 * na nova página. Fora de um arrasto (`active === false`) a zona não
 * renderiza feedback nenhum, para não poluir a navegação normal por clique
 * nas setas laterais (`SideArrowButton`, em `binder-nav-view.tsx`).
 */
function EdgeNavZone({ edge, active, enabled }: { edge: "prev" | "next"; active: boolean; enabled: boolean }) {
  const { setNodeRef, isOver } = useDroppable({
    id: edge === "prev" ? EDGE_PREV_ID : EDGE_NEXT_ID,
    disabled: !enabled,
  });
  const highlight = active && enabled && isOver;
  return (
    <div
      ref={setNodeRef}
      aria-hidden
      className={cn(
        "pointer-events-none absolute top-0 z-30 h-full w-[8%] transition-opacity duration-150",
        edge === "prev" ? "left-0" : "right-0",
        active && enabled ? "pointer-events-auto" : "",
      )}
      style={{
        background: highlight
          ? `linear-gradient(${edge === "prev" ? "90deg" : "270deg"}, hsl(40 70% 62% / 0.16), transparent)`
          : "transparent",
        boxShadow: highlight ? `inset ${edge === "prev" ? "6px" : "-6px"} 0 14px -6px hsl(40 70% 62% / 0.35)` : "none",
        opacity: active && enabled ? 1 : 0,
      }}
    />
  );
}

function SlotsGrid({
  slots,
  selectedSlotId,
  favoriteCardIds,
  lockedSlotIds,
  removedSlotIds,
  cardOverrides,
  multiSelectedSlotIds,
  isMultiSelectActive,
  onSelectSlot,
  onAddCard,
  onOpenDetail,
  onReplace,
  onRemove,
  onToggleFavorite,
  onToggleLock,
  onToggleMultiSelect,
}: {
  slots: BinderSlotData[];
  selectedSlotId: string | null;
  favoriteCardIds: Set<string>;
  lockedSlotIds: Set<string>;
  removedSlotIds: Set<string>;
  cardOverrides: Map<string, RealCardData>;
  /** BINDER-MULTISELECT-BULK-01 — Set de ids de slot participando da seleção múltipla (Bulk Actions). */
  multiSelectedSlotIds: Set<string>;
  /** BINDER-MULTISELECT-BULK-01 — HÁ seleção múltipla ativa em algum slot do spread. */
  isMultiSelectActive: boolean;
  onSelectSlot: (slotId: string) => void;
  /** BINDER-ADD-REPLACE-CARD-01 — abre o Card Picker em modo adicionar para este slot. */
  onAddCard: (slotId: string, triggerEl: HTMLElement) => void;
  onOpenDetail: (slotId: string, card: MockCardData | RealCardData, triggerEl: HTMLElement) => void;
  /** BINDER-ADD-REPLACE-CARD-01 — abre o Card Picker em modo substituição, já com a carta atual. */
  onReplace: (slotId: string, currentCard: MockCardData | RealCardData, triggerEl: HTMLElement) => void;
  onRemove: (slotId: string) => void;
  onToggleFavorite: (cardId: string) => void;
  onToggleLock: (slotId: string) => void;
  /** BINDER-MULTISELECT-BULK-01 — alterna a participação de um slot em `multiSelectedSlotIds`. */
  onToggleMultiSelect: (slotId: string) => void;
}) {
  return (
    <div className="grid grid-cols-3 gap-1 sm:gap-1.5">
      {slots.map((slot) => {
        // Mocks visuais de "remover"/"adicionar"/"substituir" (sem Inventory
        // real, sem persistência — ver doc-comment de `BinderPagesNav`
        // acima). `filled: true` no branch de `override` — BINDER-ADD-
        // REPLACE-CARD-01: sem isso, ADD sobre um slot originalmente vazio
        // (`slot.filled === false`) não aparecia preenchido, porque `filled`
        // continuava vindo do slot BASE, só `card` era sobrescrito.
        const removed = removedSlotIds.has(slot.id);
        const override = cardOverrides.get(slot.id);
        const effectiveSlot: BinderSlotData = removed
          ? { ...slot, filled: false, card: undefined }
          : override
            ? { ...slot, filled: true, card: override }
            : slot;
        const cardId = effectiveSlot.card?.id;
        return (
          <BinderSlotFull
            key={slot.id}
            slot={effectiveSlot}
            isSelected={selectedSlotId === slot.id}
            isFavorite={cardId ? favoriteCardIds.has(cardId) : false}
            isLocked={lockedSlotIds.has(slot.id)}
            isMultiSelected={multiSelectedSlotIds.has(slot.id)}
            isMultiSelectActive={isMultiSelectActive}
            onSelectToggle={() => onSelectSlot(slot.id)}
            onAddCard={(triggerEl) => onAddCard(slot.id, triggerEl)}
            onOpenDetail={(triggerEl) => effectiveSlot.card && onOpenDetail(slot.id, effectiveSlot.card, triggerEl)}
            onReplace={(triggerEl) => effectiveSlot.card && onReplace(slot.id, effectiveSlot.card, triggerEl)}
            onRemove={() => onRemove(slot.id)}
            onToggleFavorite={() => cardId && onToggleFavorite(cardId)}
            onToggleLock={() => onToggleLock(slot.id)}
            onToggleMultiSelect={() => onToggleMultiSelect(slot.id)}
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
