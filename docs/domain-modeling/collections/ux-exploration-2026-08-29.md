# Collections — Fechamento da Fase de Exploração Visual/Experimental (UX)

| Campo | Valor |
|--------|-------|
| **Documento** | Fechamento de Exploração UX/Visual — Collections |
| **Arquivo** | `docs/domain-modeling/collections/ux-exploration-2026-08-29.md` |
| **Nome do arquivo** | Pedido explicitamente por Fabrício como `ux-exploration-2026-08-29.md` — data da maior parte do trabalho de Collection Library (spikes ThreeUI, fechamento COLLECTION-LIBRARY-VIEW-MODES-01). O Binder Workspace (Seções B–F) foi conduzido entre 2026-08-28 e 2026-08-30, na mesma janela; este documento consolida os dois. **Produzido em 2026-08-30.** |
| **Status** | Fechamento de fase — exploração visual/experimental PAUSADA por instrução explícita (`COLLECTIONS-UX-EXPLORATION-CLOSEOUT-01`). |
| **Objetivo** | Consolidar tudo que foi aprendido nas rodadas de experimentação da Collection Library e do Binder Workspace (`web/app/experimental/`), classificar cada aprendizado (DOMAIN / PRODUCT BEHAVIOR / UX-PRESENTATION), e extrair implicações explícitas para a retomada da modelagem de domínio de Collections — sem inventar decisões novas. |
| **Documentos Relacionados** | `concept-decisions.md` (C-01–C-37), `logical-model.md` (LDM-01–LDM-27), `checkpoint-2026-08-28.md`, `pkmnbindr-benchmark.md`, `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` (raiz do repositório — curadoria técnica completa dos spikes visuais, seções 11–13), `.claude/skills/mmkyu-frontend-experience/SKILL.md`, `docs/log.md` (entradas de 2026-08-29/30). |

---

## Nota de divergência (obrigatória por `CLAUDE.md`)

A Seção 4 do pedido original listava, como pendências não bloqueantes a registrar: "fullscreen/light controls" e "possível edge-navigation race". No estado real do repositório neste momento, **as duas já foram investigadas e corrigidas** dentro desta mesma janela de sessão, antes deste fechamento documental:

- **Edge-navigation race** — corrigida (`BINDER-DND-EDGE-NAV-RACE-01`): timer de navegação automática por borda ganhou revalidação em tempo de disparo (drag ainda ativo, `over` ainda é a mesma edge, direção ainda navegável), fechando a lacuna que permitia o Binder navegar sozinho após um drop já concluído na Bandeja.
- **Fullscreen + light controls** — corrigida (`BINDER-FULLSCREEN-LIGHT-CONTROLS-01`): causa raiz era a ausência de background próprio no elemento promovido a tela cheia (o `::backdrop` padrão do navegador é preto opaco); corrigido reaproveitando o token `--binder-page-bg` já existente.

Por isso, esta Seção 4 abaixo NÃO repete os dois itens como pendências abertas — registra-os como **resolvidos nesta janela**, com a rodada que os fechou, e mantém como realmente pendentes apenas os três itens restantes do pedido original (persistência da Bandeja, Undo/Redo, estratégia mobile do Tool Rail). Não corrigi retroativamente o texto do pedido de Fabrício — só sinalizo a divergência aqui, como manda `CLAUDE.md`, em vez de aplicá-la silenciosamente.

---

## A. Collection Library

Três exploração paralelas ao Binder Workspace (Seções B–F), sob `app/experimental/`, `noindex`, fora da IA oficial.

- **Lista** (`CollectionListView`) — modo compacto operacional, novo nesta rodada. `USE`.
- **Cards** (`PremiumGrid`) — modo padrão inicial da tela "Minhas Collections". `USE`, aprovado desde a Seção 4/11 de `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md`, refinado nesta rodada para exibir o campo `code`.
- **Carrossel** — engine é o **Character Filmstrip** do ThreeUI (Tier A, DOM + CSS 3D puro, zero Three.js/WebGL/GSAP/CDN, mecânica authored intocada), com a skin **"Binder MMKYU"** (textura portada de `binder-cover-closed.tsx`: couro preto, zíper, sem borda colorida, círculo de progresso). `USE`.

Papel de cada modo: os três representam a **mesma** Collection com o **mesmo** núcleo de informação (Binder, nome, código, progresso) — o que muda é só densidade/apresentação, nunca o dado exibido. Nomenclatura para o usuário final é só "Lista/Cards/Carrossel"; termos internos de discovery (Signature View, Operational View, Filmstrip, Premium Grid) não aparecem na UI.

**Binder MMKYU como representação visual**: a identidade visual "binder de couro preto com zíper" nasceu como refinamento do spike Complete Shelf (correção de causa raiz em `MMKYU-SHELF-VISUAL-POLISH-01` — a capa não refletia dado nenhum do MMKYU, corrigida com selo de código + zíper + motif geométrico) e foi reaproveitada como skin do Carrossel (Character Filmstrip) e, em paralelo — mesma referência fotográfica de binder preto com zíper fornecida por Fabrício —, como identidade do próprio Binder Workspace aberto/fechado (Seção B). Os dois trabalhos convergiram para a mesma linguagem visual sem que um dependesse do outro.

## B. Binder Workspace

Spike `app/experimental/binder-nav-01/` — decisão fundacional de 2026-08-28: encerra os experimentos de page-turn físico (ver Seção G) em favor de **navegação operacional explícita**.

- **Binder-first** — reaproveita o fluxo fechado→aberto já aprovado do spike anterior (`binder-spike/`): clique/Enter/Espaço abre via View Transition (morph capa→miolo), Esc fecha.
- **Closed Binder** — `binder-cover-closed.tsx`, identidade preta/grafite com zíper e puxador em metal escuro (referência fotográfica real fornecida por Fabrício), sem escudo central nem bolso frontal.
- **Open Binder** — casca de couro/gutter/estrutura de duas páginas que **nunca remonta** entre posições (só o conteúdo de cada lado troca, transição digital curta ~200ms). Primeira abertura mostra contracapa interna + primeira página de bolsos (não duas páginas de bolsos direto); última posição espelha a mesma configuração da contracapa.
- **Spreads/pages/slots** — cada página é uma grade 3×3 de bolsos (`SlotsGrid`, `grid-cols-3`); um spread é sempre [página esquerda] + [página direita], navegado por posição inteira, nunca por bolso.
- **Navegação** — botões (topo + setas laterais), teclado (←/→/Home/End), swipe horizontal (mobile), e arraste até a borda do Binder durante um drag (edge navigation, dwell ~650ms — ver Seção D).

## C. Card interaction

- **Card Detail** — modal com imagem em `fit="contain"` (nunca corta a arte), proporção real 8:11 desde `BINDER-CARD-ASPECT-RATIO-01`.
- **Favorite** — toggle por carta (`FilledSlotQuickActions`), consistente com a decisão de domínio já registrada em `checkpoint-2026-08-28.md` §2.1: referencia `Card`, nunca `Placement`/`Card Variant`.
- **Quick Actions** — menu contextual por slot (`SlotOverflowMenu`, botão "…", via portal): slot ocupado tem Selecionar (entra em multi-select)/Favoritar/Bloquear/Substituir/Remover; slot vazio tem Adicionar. Mesmo menu dentro e fora de fullscreen (portal segue `document.fullscreenElement`).
- **Add** — Card Picker em modo `add`, aberto a partir de um slot vazio específico ou do botão global "Adicionar carta" da Tool Rail (primeiro slot vazio do spread atual).
- **Replace** — Card Picker em modo `replace`, aberto via Quick Action de um slot ocupado; a carta anterior não é destruída, sai do slot (mesma regra de "nunca perder item" da Bandeja).

## D. Layout manipulation

- **DnD** — `@dnd-kit/core`, cada slot é simultaneamente nó arrastável e alvo de drop; sensores de pointer/touch/keyboard.
- **Move** — origem (slot ou Bandeja) → destino vazio: origem esvazia, destino preenche.
- **Swap** — slot ocupado → slot ocupado: as duas cartas trocam de lugar atomicamente, nenhuma é criada/duplicada.
- **Lock** — protege um slot contra Replace e Remove, tanto individual quanto em lote (Bulk Remove); não é uma propriedade da carta, é do **placement** (slot) — uma mesma carta física pode estar bloqueada num slot e, se movida, o bloqueio não a segue automaticamente (fica com o slot).
- **Edge navigation** — zonas invisíveis nas bordas esquerda/direita da moldura; segurar um drag sobre a borda por ~650ms navega para o spread adjacente sem soltar a carta. Endurecida nesta sessão contra timer sobrevivendo ao fim do drag (`BINDER-DND-EDGE-NAV-RACE-01`, ver nota de divergência acima).
- **Bandeja / Tray** — área temporária para cartas fora de qualquer slot; dock permanente abaixo do Binder com dois estados visuais no MESMO componente (idle/drag-ativo), nunca dois controles concorrentes. Sobrevive à navegação entre spreads (não é resetada ao trocar de página).

## E. Operações em lote

- **Multi-select** — estado por slot (`multiSelectedSlotIds`), toggle via Quick Action "Selecionar" ou clique/teclado quando já em modo seleção; desliga DnD individual enquanto ativo.
- **Bulk actions** — Mover p/ Bandeja, Bloquear, Desbloquear, Remover (respeita Lock), Limpar seleção — mesmo conjunto de operações do modo individual, aplicado a todos os slots selecionados de uma vez.
- **Tool Rail permanente** — componente estrutural fixo do Binder Workspace (não mais uma barra de bulk actions adaptada), quatro seções com separadores discretos: Organização (Adicionar/Bandeja/Buscar), Saída/Experiência (Exportar/Compartilhar/Tela cheia), Histórico (Desfazer/Refazer, ambos placeholder), Seleção múltipla (as bulk actions acima). Princípio: todo botão planejado fica **sempre visível**, mesmo desabilitado — nunca aparece/desaparece por contexto, para preservar memória espacial.

## F. UX estrutural

- **Fullscreen** — Fullscreen API nativa sobre o "miolo" aberto do Binder (não a página inteira); estado sincronizado via evento `fullscreenchange` (nunca otimista); portais que hospedam menus contextuais seguem `document.fullscreenElement ?? document.body` dinamicamente, sem segunda implementação de menu.
- **Light/Dark** — 100% sobre a infraestrutura já aprovada (`next-themes` + Tailwind `darkMode: class`), tokens próprios com escopo (`.binder-nav-01-scope`) redeclarando valores claros por padrão e um bloco `.dark` com os valores escuros originais — nunca inversão automática de cor. O objeto Binder em si permanece escuro nos dois temas (materialidade de couro/PVC preservada); só o workspace ao redor e os controles fora da moldura mudam com o tema.
- **Card aspect ratio 8:11** — medição direta dos assets reais do Storage (dois exemplares checados, ambos 600×825px) revelou proporção real 8:11 (0,727273), diferente da suposição usada em toda a base (`5:7`, 0,714286) — corrigida em todos os pontos que renderizam a carta inteira (slot, Bandeja, Card Detail, Card Picker).
- **Responsive/accessibility/reduced-motion** — sensores de pointer/touch/keyboard em paralelo (nunca só mouse); `aria-disabled` (nunca `disabled` nativo) em controles que precisam permanecer com tooltip acessível mesmo inertes; `focus-visible` consistente em todo controle interativo; transições respeitam `prefers-reduced-motion`; Tool Rail reduz gaps antes de qualquer outra estratégia em viewports estreitos (estratégia mobile definitiva ainda em aberto — ver Seção 4).

## G. Abordagens rejeitadas/rebaixadas

| Abordagem | Status | Motivo |
|---|---|---|
| Page-turn físico literal (rotação 3D por scroll/gesto) | Rejeitada (2026-08-28) | Decisão de produto: Binder V1 usa navegação explícita (botões/teclado/swipe), não simulação de folha física. Spikes anteriores (BINDER-MOTION-01/02) preservados intactos, não evoluídos. |
| Complete Shelf (ThreeUI, prateleira 3D fotorrealista) como Binder final | `REFERENCE ONLY`, fora da Collection Library | Tier C (Three.js/WebGL real, iframe pesado) — fora de cogitação para a tela operacional; preservado para uma eventual experiência futura de showcase/social. |
| Character Wave para Collection Library | `REFERENCE ONLY` neste contexto | Avaliação visual direta (Wave × Filmstrip × Grid) favoreceu o Filmstrip com a skin "Binder MMKYU". Wave permanece `ADAPT CANDIDATE` só para Social/Profile — não descartado globalmente, só rebaixado para este contexto específico. |
| Hero Card pura (variante B) | `AVOID`, não reabrir | Testada em `COLLECTION-FILMSTRIP-BINDER-FIDELITY-01`; variante A (Binder puro) venceu a comparação A/B/C. |
| Binder + Hero Artwork como direção principal (variante C) | `AVOID`, não reabrir | Mesma comparação A/B/C — A venceu; C evoluiu para nada, descartada junto com B. |
| Barras horizontais de bulk actions | Superada | `BulkActionBar` (barra horizontal, topo do Binder) → `BulkActionRail` (cápsula vertical lateral) → `ToolRail` (componente estrutural permanente) — evolução em três rodadas dentro desta mesma sessão, cada uma corrigindo um problema de posicionamento/estabilidade da anterior. |

---

## Classificação dos aprendizados

| Aprendizado | Classificação | Nota |
|---|---|---|
| Inventory Item (identidade física única) | DOMAIN | Já registrado em `checkpoint-2026-08-28.md` §6 — reafirmado, não redecidido aqui. |
| Placement (carta ocupando um Slot) | DOMAIN | Novo conceito que emerge dos spikes — ver Seção 3, item 3. |
| Slot (posição física dentro de um Page/Binder) | DOMAIN | Idem. |
| Favorite → Card | DOMAIN | Já registrado em `checkpoint-2026-08-28.md` §2.1 — reafirmado pelo comportamento observado em `FilledSlotQuickActions`. |
| Lock (protege um Placement) | DOMAIN | Ver Seção 3, item 5. |
| Move / Swap | PRODUCT BEHAVIOR | Operações sobre Placement, não entidades novas. |
| Remove (esvaziar um Slot) | PRODUCT BEHAVIOR | Distinto de mover para a Bandeja — ver Seção 3, item 7. |
| Bandeja / Tray | PRODUCT BEHAVIOR (estado transitório de UI, não entidade física) | Ver Seção 3, item 8. |
| Add / Replace via Card Picker | PRODUCT BEHAVIOR | Fluxos operacionais sobre Placement. |
| Multi-select | UX/PRESENTATION — estado transitório de interação | Ver Seção 3, item 9. |
| Tool Rail | UX/PRESENTATION | Componente de interface, não pertence ao domínio — ver Seção 3, item 10. |
| Bulk actions (Mover/Bloquear/Desbloquear/Remover/Limpar) | PRODUCT BEHAVIOR | Mesmas operações de D, aplicadas em lote — a operação é produto; o botão que a dispara é UX. |
| Edge navigation (dwell na borda) | UX/PRESENTATION | Mecanismo de navegação, não afeta dado nenhum. |
| Fullscreen | UX/PRESENTATION | |
| Light/Dark | UX/PRESENTATION | |
| Card aspect ratio 8:11 | UX/PRESENTATION | Correção de fidelidade visual, não modela nada nem cria conceito de domínio. |
| Collection Library — Lista/Cards/Carrossel | UX/PRESENTATION | Três apresentações da mesma Collection — nenhuma introduz dado novo (ver Seção A). |
| Binder MMKYU (skin visual) | UX/PRESENTATION | Identidade visual reaproveitada entre Collection Library e Binder Workspace — não é uma entidade, é tratamento visual. |

Nenhuma decisão visual foi transformada automaticamente em entidade de domínio — a tabela acima é o resultado desse filtro, não o processo bruto (o processo bruto incluiu descartar candidatos como "Tool Rail Item", "Drop Zone" e "Fullscreen Mode" como possíveis entidades, todos rebaixados a UX/PRESENTATION por não carregarem estado nenhum que sobreviva além da sessão de interação).

---

## Implicações dos spikes para o modelo de Collections

1. **Inventory Item continua sendo identidade física única.** Confirmado pelo comportamento do Binder: a mesma carta física (`card.id`) nunca é duplicada ao mover, trocar (Swap) ou passar pela Bandeja — sempre a mesma identidade mudando de posição, nunca uma cópia.
2. **Collection não cria Collection Item paralelo.** Reafirma `checkpoint-2026-08-28.md` §6 — nos spikes, "a carta que está no Binder" é sempre o mesmo Inventory Item, nunca uma projeção/cópia com identidade própria.
3. **Placement é diferente de Inventory Item.** O spike deixa isso operacionalmente muito claro: Swap troca DOIS placements sem tocar a identidade de nenhuma carta; Lock trava um placement, não uma carta (a mesma carta pode estar destravada em outro slot); Remove esvazia um placement sem destruir o Inventory Item. Placement é a relação (Inventory Item × Slot × posição), não o item em si.
4. **Slot pertence ao layout.** Um Slot é sempre relativo a uma posição física dentro de uma Page dentro de um Binder — no spike, `slotId` tem formato `p{página}-{posição}`, nunca existe um Slot "solto" fora de uma página.
5. **Lock protege layout.** Confirmado pela semântica implementada: Lock bloqueia Replace/Remove (individual e em lote) sobre um placement específico — protege "o que está fixado nesta posição", não a carta em si nem a Collection inteira.
6. **Move/Swap alteram placement.** Nenhuma das duas operações cria, destrói ou transfere ownership de um Inventory Item — só realocam onde ele está posicionado.
7. **Remove ≠ Bandeja.** São dois destinos distintos e não intercambiáveis para "tirar uma carta de um slot": Remove esvazia o slot sem mover a carta para lugar nenhum navegável (ela simplesmente deixa de estar posicionada — no spike, mock/visual, sem Inventory real ainda); mover para a Bandeja preserva a carta em um estado "fora de slot, mas ainda visível/recuperável" dentro da mesma sessão de edição do layout.
8. **Bandeja é temporária e não é nova entidade física.** No spike, `trayItems` é estado de sessão do componente (perdido ao fechar o Binder) — nunca um novo tipo de "lugar" persistente. Para o domínio, isso sugere que a Bandeja é uma conveniência de UX sobre placements não resolvidos, não uma localização física a modelar (equivalente, na prática, a "Inventory Item sem placement no momento").
9. **Multi-select é estado transitório.** Vive inteiramente no componente de interação (`multiSelectedSlotIds`), nunca persiste, nunca é lido por nenhuma outra parte do sistema — não deve virar nenhum campo/tabela.
10. **Tool Rail não pertence ao domínio.** É estrutura de interface (agrupamento de ações), não um conceito que o modelo de dados precisa representar.
11. **Favorite pertence a Card, não a Placement.** Confirmado pelo comportamento do spike (Favoritar em qualquer ocorrência de uma carta reflete em todas as outras ocorrências visíveis da mesma carta) — reafirma `checkpoint-2026-08-28.md` §2.1 com evidência de comportamento, não só de intenção declarada.
12. **Layout customizado é independente da ordem canônica.** O spike nunca ordena slots pela ordem canônica de coleção (número/Set) — a posição de uma carta num Binder é inteiramente definida pelo usuário (onde ele soltou/moveu), reforçando que "layout" é um conceito de posicionamento livre, não uma projeção automática de uma ordenação de catálogo.

---

## 4. Pendências não bloqueantes

Classificação única para todos os itens abaixo: **"UX/implementation follow-up — não bloqueia domain modeling."**

- ~~Fullscreen/light controls~~ — **resolvida nesta sessão** (`BINDER-FULLSCREEN-LIGHT-CONTROLS-01`), ver nota de divergência no topo deste documento.
- ~~Possível edge-navigation race~~ — **resolvida nesta sessão** (`BINDER-DND-EDGE-NAV-RACE-01`), ver nota de divergência no topo deste documento.
- **Comportamento final de persistência da Bandeja** — hoje é estado de sessão do componente (some ao fechar o Binder ou recarregar a página); não decidido se/como isso deveria persistir num produto real (ex.: sobreviver a fechar e reabrir o Binder Workspace).
- **Undo/Redo futuro** — Tool Rail já reserva os dois botões (placeholder, desabilitados, "Em breve"), mecanismo em si não implementado nem desenhado.
- **Estratégia mobile definitiva da Tool Rail** — a rodada `TOOL-RAIL-03` só aplicou a estratégia mais simples (reduzir gaps) e explicitamente não desenhou uma solução completa para viewports muito estreitos; decisão real ainda em aberto.

---

## 5. Ver também

Checkpoint de fechamento de fase, com a decisão de retomada, em `checkpoint-2026-08-29.md` (mesma pasta).

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste documento (2026-08-30), a pedido explícito de Fabrício (`COLLECTIONS-UX-EXPLORATION-CLOSEOUT-01`) — encerramento temporário da fase de exploração visual/experimental de Collections (Collection Library + Binder Workspace). Consolida seções A–G, classificação DOMAIN/PRODUCT BEHAVIOR/UX-PRESENTATION, doze implicações para a modelagem e cinco pendências não bloqueantes (duas já resolvidas nesta mesma janela de sessão, sinalizado explicitamente em vez de aplicado silenciosamente). Nenhum código alterado nesta rodada; `concept-decisions.md`/`logical-model.md` intencionalmente não tocados. |
