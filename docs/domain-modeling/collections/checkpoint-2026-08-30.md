# Collection — Checkpoint de Consolidação do Bloco Layout (2026-08-30)

| Campo | Valor |
|--------|-------|
| **Documento** | Checkpoint de Consolidação — Collection Layout / Page / Slot |
| **Arquivo** | `docs/domain-modeling/collections/checkpoint-2026-08-30.md` |
| **Data** | 2026-08-30 |
| **Origem** | `COLLECTIONS-LAYOUT-MODELING-CONSOLIDATION-01` — encerramento formal de dez rodadas de modelagem conceitual (`COLLECTIONS-LAYOUT-MODELING-01` a `-10`), conduzidas nesta mesma janela de sessão, sobre o núcleo `Collection Layout`/`Page`/`Slot`/`Expected Content`/`Lock`/`Slot Assignment`/`Bandeja`/`Layout Region`. |
| **Objetivo** | Registrar o diagnóstico de reconciliação entre as decisões de trabalho das dez rodadas e o corpus canônico (`concept-decisions.md`, `logical-model.md`), e apontar para os novos C-38–C-46 / LDM-29–LDM-37 já incorporados. |
| **Documentos Relacionados** | `concept-decisions.md` (C-38 a C-46, novo bloco; C-49 a C-54, bloco adicional — ver Seção 7; C-55 a C-66, bloco adicional — ver Seção 8; C-67 a C-81, bloco adicional — ver Seção 9; C-82 a C-90, bloco adicional — ver Seção 10; C-91 a C-102, bloco adicional — ver Seção 11; C-103 a C-120, bloco adicional — ver Seção 12; C-121 a C-140, bloco adicional — ver Seção 13; C-141 a C-165, bloco adicional — ver Seção 14; C-166 a C-186, bloco adicional — ver Seção 15), `logical-model.md` (LDM-29 a LDM-37, novo bloco; LDM-38 a LDM-43, bloco adicional — ver Seção 7; LDM-44 a LDM-54, bloco adicional — ver Seção 8; LDM-55 a LDM-69, bloco adicional — ver Seção 9; LDM-70 a LDM-78, bloco adicional — ver Seção 10; LDM-79 a LDM-90, bloco adicional — ver Seção 11; LDM-91 a LDM-108, bloco adicional — ver Seção 12; LDM-109 a LDM-128, bloco adicional — ver Seção 13; LDM-129 a LDM-153, bloco adicional — ver Seção 14; LDM-154 a LDM-174, bloco adicional — ver Seção 15), `05f-pricing.md` (tabela `card_condition`, CONFIRMADO EXECUTADO, referenciada não editada — ver Seções 12 e 13), `checkpoint-2026-08-28.md`, `checkpoint-2026-08-29.md` (§5, itens 4–5, agora resolvidos — ver Seção 3 abaixo), `ux-exploration-2026-08-29.md` (§"Implicações", itens 3/5/8, terminologia superada — ver Seção 4), `pkmnbindr-benchmark.md` (§4, §13, §29 — prior art não-normativo, usado como evidência, não como fonte de decisão). |

---

## 1. Estado que este checkpoint assume como ponto de partida

- Conceitual: `concept-decisions.md`, C-01 a C-37 — CLOSED, inalterado por este checkpoint. C-38 a C-46 — novo bloco, Aprovado nesta rodada.
- Lógico: `logical-model.md`, LDM-01 a LDM-24 — inalteradas. LDM-25/26/27 — seguem superseded (`checkpoint-2026-08-28.md`). LDM-28 original — segue void em conteúdo e não é reocupado, nem em conteúdo nem em número; o bloco novo abre em LDM-29 (a LDM-37) para evitar colisão com essa numeração void — novo bloco, Aprovado nesta rodada.
- Físico: NÃO iniciado — continua não iniciado após este checkpoint.
- `checkpoint-2026-08-29.md` §5, itens 4 e 5 (próximo foco declarado: "modelo formal de Slot/Placement" e "se/como a Bandeja precisa de representação formal") — **resolvidos por este checkpoint**, ver Seção 3.

---

## 1.1 Status desta subfrente

**Collections — Layout/Page/Slot conceptual modeling: CLOSED**

Isto **não** significa que Collections como um todo esteja completo. Significa apenas que o núcleo conceitual desta subfrente — Layout, Page, Slot, Lock, Expected Content, Slot Assignment, Bandeja (Tray) e Layout Region — está suficientemente fechado nesta etapa (C-38–C-46, LDM-29–LDM-37). Seguem explicitamente fora deste fechamento e em aberto: Grid Change, artwork de Layout Region, histórico/Undo-Redo de Slot Assignment (Seção 6), e todos os pontos já listados em `checkpoint-2026-08-28.md` §9 (Inventory, Favorite, transferência entre usuários, Storage, permissões, Audit Log).

---

## 2. Diagnóstico de reconciliação

### 2.1 — Decisões reutilizadas (fundação já existente, não alterada)

O núcleo das dez rodadas se apoiou consistentemente em decisões já fechadas, sem contradizer nenhuma:

- **C-04 / C-28** — alocação colecionável é independente de localização física; base direta para "Collection Allocation independe de Slot Assignment" (C-44).
- **C-16 / C-17 / C-25–C-27** — Storage é dimensão independente de Collection; base direta para "Layout é independente de Storage" (C-38).
- **C-19 / C-20 / LDM-20** — completude é derivada exclusivamente da alocação à Collection frente ao universo de referência; base direta para "Expected Content não participa de completude" (C-42).
- **C-24** — layout físico/visual é livre e não determina ordem lógica; base conceitual direta de todo o bloco Layout, citada explicitamente ao longo das dez rodadas.
- **C-26** — Physical Card pode existir sem Storage (à época deste checkpoint, `Collection Item`); usada por dedução direta para responder a Questão 1 da rodada 01 ("Collection Allocation pode existir sem Slot Assignment") — não uma escolha nova, uma consequência lógica de C-26 já aprovada.
- **LDM-06** — rejeição de estrutura polimórfica solta (`reference_type + reference_id`) em favor de FKs fortes por subtipo — usada por analogia repetidamente para preferir entidades próprias com FKs explícitas (Slot Assignment, Expected Content, Layout Region) a atributos genéricos ou ponteiros soltos.
- **LDM-19/LDM-23/LDM-24** — identidade única da Physical Card (nome vigente desde 2026-08-30; à época deste checkpoint, `Inventory Item`), independente de Collection/Storage — usada por analogia direta para justificar identidade estável de Slot e Page (C-39/C-41).
- **C.2 (Parte C, diretriz de UX)** — já antecipava "um slot não precisa obrigatoriamente conter uma Physical Card" (à época deste checkpoint, `Collection Item`) e "elementos visuais personalizados" distintos de slot — confirmado e formalizado, não contradito.
- **`pkmnbindr-benchmark.md` §4** (não-normativo) — esboço `Binder Slot { expected_card/variant, inventory_item = NULL }` (citação literal do pseudo-código do benchmark, não atualizada) e a distinção quádrupla Wishlist/Binder Slot/Physical Card/Completion Requirement (termo do quarto elemento atualizado para `Physical Card`; à época deste checkpoint, `Inventory Item`) — usado como evidência de prior art para C-41/C-42, nunca como fonte de decisão por si só.

### 2.2 — Decisões novas (convertidas para C-38–C-46 / LDM-29–LDM-37)

Todas as decisões de trabalho rotuladas D1–D69 ao longo das dez rodadas foram sintetizadas — não copiadas 1:1 — nos novos registros:

| Tema | Conceitual | Lógico |
|---|---|---|
| Collection Layout como entidade independente de Storage | C-38 | LDM-29 |
| Page como unidade estrutural estável | C-39 | LDM-30 |
| Grid Configuration no Layout, capacidade derivada | C-40 | LDM-31 |
| Slot: identidade ≠ posição, row/column 1-based | C-41 | LDM-32 |
| Expected Content: Card obrigatória + Variant opcional | C-42 | LDM-33 |
| Lock: propriedade do Slot | C-43 | LDM-34 |
| Slot Assignment: relação, cardinalidade, ciclo de vida | C-44 | LDM-35 |
| Bandeja: estado transitório de UX, não modelada fisicamente | C-45 | LDM-36 |
| Layout Region (Merge): entidade persistente, geometria retangular | C-46 | LDM-37 |

Decisões de trabalho que **não** viraram registro canônico próprio, por já estarem cobertas ou por serem iteração interna do próprio raciocínio das dez rodadas (não noise a preservar, per convenção de 2026-07-24 de `CLAUDE.md`): a hipótese intermediária de "Grid Size por Page" (rodada 03), corrigida na própria rodada 04 antes de qualquer registro canônico — nunca chegou a ser decisão fechada, não gera entrada de "superseded" no corpus oficial.

### 2.3 — Decisões superseded

- **Terminologia "Placement"** — usada em `ux-exploration-2026-08-29.md` (itens 3, 5, 8 de "Implicações dos spikes") e em `checkpoint-2026-08-29.md` §5 (itens 4–5) como nome de trabalho para a relação Physical Card × Slot (à época deste checkpoint, `Inventory Item` × Slot). Nunca teve lastro em C-*/LDM-* anteriores (confirmado por `COLLECTIONS-DOMAIN-REENTRY-01`). Superada por **Slot Assignment** (C-44/LDM-35), registrado explicitamente como item 14 da lista de hipóteses rejeitadas em `logical-model.md` §6.
- **Classificação de Lock em `ux-exploration-2026-08-29.md` item 5** ("Lock protege... o placement (slot)... não é uma propriedade da carta") — a conclusão prática já estava certa (Lock não segue a carta), mas o termo "placement (slot)" conflava, sem distinguir, o Slot e a relação de ocupação. A investigação fresca da rodada 06 (explicitamente instruída a não presumir a partir do spike) precisou e corrigiu: Lock é propriedade do **Slot**, não da Slot Assignment — mesma conclusão prática, terminologia agora precisa (C-43/LDM-34). Não é uma reversão de comportamento, é uma correção de precisão conceitual.
- **`checkpoint-2026-08-29.md` §5, itens 4 e 5** — "modelo formal de Slot/Placement" e "se/como a Bandeja precisa de representação formal" — ambos **resolvidos** por este checkpoint (C-41/C-44/LDM-32/LDM-35 para o primeiro; C-45/LDM-36 para o segundo, que resolve explicitamente como "não modelar fisicamente").

### 2.4 — Conflitos encontrados

**Nenhum conflito impeditivo.** As decisões novas se encaixam como extensão consistente do que já existia — nenhuma contradiz C-01–C-37 ou LDM-01–LDM-24 vigentes. A única divergência real (terminologia "Placement") já estava sinalizada como não-canônica desde `COLLECTIONS-DOMAIN-REENTRY-01` (rodada anterior a esta consolidação), não uma surpresa desta rodada.

---

## 3. `checkpoint-2026-08-29.md` §5 — itens resolvidos

| Item (texto original) | Status | Resolução |
|---|---|---|
| 4. "modelo formal de `Slot`/`Placement`" | **Resolvido** | C-41/C-44, LDM-32/LDM-35 |
| 5. "se e como a Bandeja/estado 'sem placement' precisa de representação formal" | **Resolvido** | C-45, LDM-36 — decisão explícita de **não** modelar fisicamente; Bandeja permanece estado de UX/sessão |

`checkpoint-2026-08-29.md` não foi editado — permanece como registro histórico do estado em 2026-08-29/30 antes desta consolidação, per convenção de preservar o histórico de decisões (`03-documentation-architecture.md`). Este checkpoint aponta para lá, não o reescreve.

---

## 4. `ux-exploration-2026-08-29.md` — nota de supersessão terminológica

Não editado (mesma razão da Seção 3). Registro aqui, não lá: os itens 3, 5 e 8 de "Implicações dos spikes para o modelo de Collections" usam "Placement" como termo — leia-se "Slot Assignment" (C-44) em todas as ocorrências ao consultar aquele documento daqui em diante. O item 5 especificamente ("Lock protege... o placement (slot)") deve ser lido com a precisão adicional de C-43: Lock é propriedade do Slot, não de uma relação de ocupação.

---

## 5. O que este checkpoint explicitamente NÃO faz

- Não altera código.
- Não cria migration, tabela, RPC, rota ou componente.
- Não reabre C-01–C-37 nem LDM-01–LDM-24.
- Não modela Grid Change, artwork de Layout Region, ou histórico/audit/Undo-Redo de Slot Assignment — permanecem em aberto (Seção 6). Bandeja **não** está nessa lista: seu comportamento está conceitualmente fechado por C-45/LDM-36 (estado transitório de UX, sem persistência de domínio) — não é uma pendência desta consolidação.
- Não faz commit/push.

---

## 6. Próxima decisão em aberto (para quando a modelagem lógica for retomada)

Combinando o que já estava aberto em `checkpoint-2026-08-28.md` §9 com o que emergiu desta frente:

1. Transferência de Physical Card entre Inventories de usuários diferentes (já aberto; à época deste checkpoint, `Inventory Item`) — **atualização 2026-08-30**: a preservação de identidade da Physical Card durante a transferência (mudança de `inventory_id`, não criação de nova Physical Card) já está formalizada por C-48/LDM-23; o que permanece aberto é o mecanismo operacional da transferência (fluxo, autorização, aprovação entre usuários), não a regra de identidade/cardinalidade em si.
2. Modelo físico de `Inventory` — cardinalidade, criação automática vs. explícita (já aberto).
3. ~~Modelo de `Favorite` — cardinalidade, dono, uso (já aberto).~~ — **resolvido conceitualmente em 2026-08-30, ver Seção 10** (C-82–C-90, LDM-70–LDM-78). Permanece aberto apenas o skeleton físico da relação User↔Favorite↔Card.
4. **Novo**: mecanismo físico de Grid Change em um Layout já existente (migração no lugar vs. novo Layout) — C-40 reconhece a necessidade, não resolve o mecanismo.
5. **Novo**: representação física de Layout Region (tabela de junção vs. bounding box) e modelagem de conteúdo visual/artwork de Region — C-46/LDM-37 explicitamente não modelam.
6. **Novo**: mecanismo físico de ordenação de Page (índice sequencial, linked list, rank/order key) — LDM-30 fixa só que Page identity ≠ Page order, não o mecanismo.
7. **Novo**: histórico, audit trail, versionamento ou Undo/Redo de Slot Assignment — LDM-35 explicitamente adia, não modela.
8. Pontos já listados em `logical-model.md` §7 e reafirmados nos checkpoints anteriores, não afetados por este: Storage (ownership, sharing, movimentação), matriz de permissões completa de Collection Member, Audit Log transversal.

**Nota sobre a Bandeja**: não é uma decisão em aberto desta modelagem. D54–D59 (incorporadas em C-45/LDM-36) fecharam conceitualmente que a Bandeja é estado transitório de UX, não é entidade de domínio, não possui persistência, e que sair do Layout descarta o estado transitório preservando o estado persistido original. Se no futuro surgir uma necessidade real de staging persistente, isso será um requisito/conceito de produto novo — não uma pendência da Bandeja tal como definida aqui.

---

## 7. Custody & Availability — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento da subfrente de Layout (Seções 1–6 acima) e da reconciliação terminológica Physical Card: uma subfrente própria, `COLLECTIONS-CUSTODY-AVAILABILITY-CONSOLIDATION-01`, conceitualizou e formalizou `Custody`/`Custodian`/`Availability` a partir do memo `COLLECTIONS-INVENTORY-MODELING-05` (conduzido sem edição de arquivo).

**Status desta subfrente: Collections — Custody / Availability conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-49 a C-54) e `logical-model.md` (LDM-38 a LDM-43, deliberadamente sem skeleton físico). Termo canônico adotado: `Custody` (não `Possession`). `Custodian` preservado como distinção conceitual, sem entidade criada. Confirmado: Custody/Availability são independentes de Ownership (Inventory) e de Storage; nenhuma das duas altera Collection Allocation, Slot Assignment ou completion — completion permanece ownership-based (C-19/C-26 reafirmadas, não reabertas).

Explicitamente fora deste fechamento, permanecendo em aberto para rodada própria de Storage: estrutura física de Custody; entidade `Custodian`; enum de Availability; fluxo completo de empréstimo; fluxo de grading; Storage cross-Inventory (se um empréstimo pode usar o Storage Container de outro usuário). Nenhum código, SQL, tabela ou UUID foi tratado nesta subfrente. C-01–C-48 e LDM-01–LDM-37 não foram reabertas em conteúdo.

---

## 8. Storage — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Custody & Availability (Seção 7): uma subfrente própria, `COLLECTIONS-STORAGE-CONSOLIDATION-01`, formalizou `Storage`/`Storage Container` a partir de dois memos conceituais (`COLLECTIONS-STORAGE-MODELING-01`/`-02`) e uma rodada de correção sobre remoção/hierarquia — todos conduzidos sem edição de arquivo, revisados por Fabrício.

**Status desta subfrente: Collections — Storage conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-55 a C-66) e `logical-model.md` (LDM-44 a LDM-54, deliberadamente sem skeleton físico além do já fixado por LDM-24). Confirmado: Storage é dimensão distinta de Protection/Encapsulation (critério de endereçabilidade, não mera capacidade física de conter a carta); Storage Container pertence ao contexto patrimonial de exatamente um Inventory, nunca a uma Collection; Physical Card possui no máximo um Storage Container corrente, podendo não ter nenhum; mudança de Storage não afeta ownership, Collection Allocation, Slot Assignment nem completion; hierarquia opcional entre Storage Containers é suportada, sempre dentro do mesmo Inventory, com Physical Card referenciando apenas o container mais específico; Storage cross-Inventory está fechado como não suportado — Custody cobre empréstimo/grading/guarda por terceiro; capacidade é conceito opcional e não-uniforme; remoção exige vazio estrutural (zero Physical Cards e zero containers filhos), sem cascade; existem duas operações distintas de transferência (Bulk Card Transfer para Physical Cards, Reparent para containers), ambas restritas ao mesmo Inventory.

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: Protection/Encapsulation como dimensão própria (sleeve, toploader, one-touch, slab — apenas reconhecida, não modelada, incluindo o caso especial do slab de grading, potencialmente protetivo e endereçável ao mesmo tempo); histórico de Storage ("last known storage"); fórmula/mecânica de capacidade, inclusive capacidade agregada sob hierarquia; Product Behavior detalhado de remoção, Bulk Card Transfer e Reparent (fluxo, confirmação, tratamento de erro parcial); skeleton físico de Storage Container (id, inventory_id, parent_id). Nenhum código, SQL, tabela ou UUID foi tratado nesta subfrente. C-01–C-54 e LDM-01–LDM-43 não foram reabertas em conteúdo.

---

## 9. Physical Card Lifecycle & Provenance — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Storage (Seção 8): uma subfrente própria, `COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-CONSOLIDATION-01`, formalizou a espinha dorsal patrimonial e a fronteira de privacidade de Lifecycle/Provenance a partir de dois memos conceituais (`COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-MODELING-01`/`-02`), ambos conduzidos sem edição de arquivo, revisados por Fabrício.

**Status desta subfrente: Collections — Physical Card Lifecycle / Provenance conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-67 a C-81) e `logical-model.md` (LDM-55 a LDM-69, deliberadamente sem skeleton físico além de `inventory_id`, já fixado por LDM-23). Confirmado: Lifecycle é o conjunto de fatos históricos sobre uma Physical Card, com identidade sempre preservada; Provenance é subconjunto de Lifecycle focado em origem e trajetória patrimonial — nunca Audit Log, histórico de Storage, histórico de condition, Pricing ou Valuation History; a espinha dorsal patrimonial tem três formas — Ownership Entry, Ownership Transfer (fato único e atômico, sem hiato) e Ownership Exit — com motivo qualificando o evento, nunca criando tipo estrutural próprio; Ownership Episode permanece ferramenta conceitual, sem entidade própria; Physical Card Provenance é distinta de Owner/Transaction Private Data — dados privados de um episódio (valor pago, seller, buyer, frete, margem, contraparte, notas) nunca são herdados automaticamente pelo owner seguinte; provenance é sempre descrita como "registrada/rastreada no MMKYU", nunca "verificada/certificada"; mudança de ownership gera três consequências paralelas e independentes sobre Collection Allocation, Slot Assignment e Storage; Custody permanece independente de ownership mesmo após Exit, corrigindo uma recomendação anterior que a levava a "não aplicável" — sem alterar C-49–C-54; o núcleo V1 é Entry/Transfer/Exit automáticos, sem histórico de Loan/LOST/Grading; Grading fica fechado no mínimo pedido; Valuation/Pricing History não são Provenance, sem reabrir Pricing V1.

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: Audit Log transversal; permissões detalhadas para separar Provenance de Private Data; evidence levels; workflow de grading (submission/return/regrade/cracking); histórico de Loan/LOST/Recovery; histórico detalhado de condition; skeleton físico de qualquer evento de lifecycle ou de Ownership Episode. Nenhum código, SQL, tabela ou UUID foi tratado nesta subfrente. C-01–C-66 e LDM-01–LDM-54 não foram reabertas em conteúdo — C-49–C-54/LDM-38–LDM-43 (Custody/Availability) permanecem integralmente vigentes.

---

## 10. Favorite — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Physical Card Lifecycle & Provenance (Seção 9): uma subfrente própria, `COLLECTIONS-FAVORITE-CONSOLIDATION-01`, formalizou `Favorite` a partir de um memo conceitual (`COLLECTIONS-FAVORITE-MODELING-01`, conduzido sem edição de arquivo, revisado por Fabrício).

**Status desta subfrente: Collections — Favorite conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-82 a C-90) e `logical-model.md` (LDM-70 a LDM-78, deliberadamente sem skeleton físico). Confirmado: Favorite representa a preferência editorial pessoal de um `User` por uma `Card` — referencia exclusivamente `Card`, nunca `Card Variant`, `Physical Card`, `Collection`, Collection Allocation, Slot Assignment ou Storage; pertence ao `User`, transversal a todas as Collections, independente do papel do User (Owner/Member) e sem relação com `Inventory`; é independente de ownership, sobrevivendo à ausência, existência ou alienação total de Physical Cards correspondentes; é independente de Collection, não alterando nem dependendo de completion, Collection Allocation, canonical ordering, Layout ou Slot Assignment; é binário — sem score, rating, prioridade, níveis ou ranking; cardinalidade conceitual é no máximo um Favorite por par (User, Card); é distinto de Wishlist, ambos independentes e podendo coexistir; cada Card permanece identidade editorial própria por Set, sem herança automática entre impressões do mesmo Pokémon/personagem em outros Sets.

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: Wishlist em profundidade; camada `Pokémon`/`Subject Reference`; ranking/grail como conceito próprio de produto; recomendações; notificações; skeleton físico da relação User↔Favorite↔Card; catalog lifecycle (hard delete/deprecation). Nenhum código, SQL, tabela ou UUID foi tratado nesta subfrente. C-01–C-81 e LDM-01–LDM-69 não foram reabertas em conteúdo.

---

## 11. Wishlist — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Favorite (Seção 10): uma subfrente própria, `COLLECTIONS-WISHLIST-CONSOLIDATION-01`, formalizou `Wishlist` a partir de dois memos conceituais (`COLLECTIONS-WISHLIST-MODELING-01`/`-02`, conduzidos sem edição de arquivo, revisados por Fabrício). A direção vigente é a do memo `-02`, que corrigiu a granularidade de alvo proposta no `-01` (Card obrigatório + Variant opcional) para `Card Variant` obrigatório — nenhuma das conclusões do `-01` havia sido consolidada em C-*/LDM-*, portanto não há supersessão de documento canônico.

**Status desta subfrente: Collections — Wishlist conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-91 a C-102) e `logical-model.md` (LDM-79 a LDM-90, deliberadamente sem skeleton físico). Confirmado: Wishlist representa a intenção pessoal declarada de um `User` de adquirir uma determinada `Card Variant` — referencia obrigatoriamente `Card Variant` (não `Card`, diferença intencional frente a Favorite), com idioma como refinamento opcional; é independente de ownership, sobrevivendo à ausência, existência ou posse exata da combinação desejada, sem remoção automática por aquisição; não é derivada de completion — Wishlist ≠ Collection Missing, sinais ortogonais em qualquer combinação (`Possuir ≠ Alocar ≠ Completar ≠ Desejar`); não possui vínculo estrutural com Collection; é independente de Expected Content (C-42 não reutilizada como justificativa de granularidade) e de Favorite (diferença Card vs. Card Variant intencional, ambos coexistindo livremente); é binária no núcleo V1, sem quantity/priority/price target; duplicidade conceitual exige mesma Card Variant e mesma condição de idioma; Marketplace e condition/grading são fronteiras futuras reconhecidas, sem dependência estrutural.

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: quantity, priority/grail, ranking, target price, alerts e procurement behavior; mecanismo de consumo por Marketplace; modelagem própria de `condition` (encaminhada para futura subfrente `Collections — Physical Card Condition Modeling`) e de Grading em detalhe; associação contextual opcional entre Wishlist e Collection/objetivo (estudada como Product Behavior, não decisão estrutural); skeleton físico da relação User↔Wishlist↔Card Variant(+idioma). Nenhum código, SQL, tabela ou UUID foi tratado nesta subfrente. C-01–C-90 e LDM-01–LDM-78 não foram reabertas em conteúdo — Favorite (C-82–C-90/LDM-70–LDM-78) permanece integralmente vigente.

---

## 12. Physical Card Condition — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Wishlist (Seção 11): uma subfrente própria, `COLLECTIONS-PHYSICAL-CARD-CONDITION-CONSOLIDATION-01`, formalizou `Physical Card Condition` a partir de um memo conceitual (`COLLECTIONS-PHYSICAL-CARD-CONDITION-MODELING-01`) e de um complemento de evidência de mercado brasileiro, ambos conduzidos sem edição de arquivo, revisados por Fabrício.

**Nota de divergência sinalizada explicitamente**: o pedido de consolidação referenciou "memos CONDITION-MODELING-01, CONDITION-MODELING-02 e o complemento" — nesta sessão não houve uma rodada entregue literalmente como `CONDITION-MODELING-02`; o complemento de evidência de mercado brasileiro cumpriu, em conteúdo, o papel equivalente de uma segunda rodada de refinamento (evidência de mercado, code vs. label, filter semantics) e é tratado como tal nesta consolidação, sem aplicar essa referência silenciosamente.

**Status desta subfrente: Collections — Physical Card Condition conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-103 a C-120) e `logical-model.md` (LDM-91 a LDM-108, deliberadamente sem skeleton físico). Achado central: a tabela física `card_condition` — já `CONFIRMADO EXECUTADO` em Pricing, Incremento P1, 2026-08-16, `docs/05f-pricing.md` — foi desenhada deliberadamente como referência compartilhada e neutra, antecipando exatamente este uso futuro por `collection_item`/`Physical Card`, mas nunca havia sido referenciada a partir dos documentos conceituais de Collections até esta rodada. Fica ratificado conceitualmente que `card_condition` representa a escala canônica de Condition do MMKYU — Collections não cria uma segunda escala nem um conceito paralelo; Physical Card Condition e os mapeamentos de condition de Pricing consomem a mesma referência. Nenhuma alteração de schema é proposta ou aplicada. Confirmado: Condition pertence exclusivamente à Physical Card; é opcional, sem bloquear cadastro básico/bulk import/Ownership Entry, e sem valor `UNKNOWN` para representar ausência; é classificação declarada/registrada, não certificada; é distinta de Damage/Defects (fora do núcleo V1) e de Grading (coexistência sem derivação automática — aplicabilidade a cards graded deferida para futura subfrente `Grading / Certification Domain Modeling`); "raw/graded" não é valor de Condition; não possui histórico no núcleo V1 (reafirma C-68/C-81); é independente da identidade da Physical Card e de Card Variant/ownership/Collection Allocation/Slot Assignment/Favorite/Wishlist/Storage/Custody; é independente de idioma; pode futuramente ser input de Valuation sem se tornar Price/Valuation, sem reabrir Pricing V1 (precedente já estabelecido em `05f-pricing.md`, que rejeitou embutir fator de desconto por condition em `card_condition`); expressões de filtro ("NM ou superior") são semântica de comparação sobre `condition_order`, não novos valores de escala; Wishlist V1 permanece sem Condition (C-91–C-102 não reabertas).

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: skeleton físico da referência Physical Card → `card_condition`; `Collections — Grading / Certification Domain Modeling` (fechamento da aplicabilidade de Condition a cards graded); Damage/Defects detalhados; Condition History; mecanismo/UX de filtro por ordenação; refinamento de Wishlist por Condition. Nenhum código, SQL, tabela, UUID ou migration foi tratado nesta subfrente. C-01–C-102 e LDM-01–LDM-90 não foram reabertas em conteúdo — Lifecycle/Provenance (C-67–C-81/LDM-55–LDM-69) e Wishlist (C-91–C-102/LDM-79–LDM-90) permanecem integralmente vigentes.

> **Nota de fechamento (2026-08-31, `COLLECTIONS-CARD-CONDITION-RECONCILIATION-02`)**: a discrepância "5 linhas" vs. "6 códigos" registrada acima como pendência está **CLOSED**. A condição física `M`/Mint foi incluída via UI (passo referido por Fabrício como "PRE-PHYSICAL-GATE"); a auditoria read-only `COLLECTIONS-CARD-CONDITION-MINT-POSTCHECK-01` confirmou as 6 linhas físicas de `card_condition` (M/NM/LP/MP/HP/DMG, `condition_order` 1..6) e concluiu **SAFE** — zero regressão de Pricing, nenhum código dependente de "exatamente 5 condições". `concept-decisions.md` C-105–C-107 e `logical-model.md` LDM-93–LDM-95 atualizadas na mesma rodada. Skeleton físico da referência Physical Card → `card_condition` permanece em aberto, sem relação com esta pendência de contagem.

---

## 13. Grading / Certification — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Physical Card Condition (Seção 12): uma subfrente própria, `COLLECTIONS-GRADING-CERTIFICATION-CONSOLIDATION-01`, formalizou `Grading`/`Certification` a partir de dois memos conceituais (`COLLECTIONS-GRADING-CERTIFICATION-MODELING-01`/`-02`, conduzidos sem edição de arquivo, revisados por Fabrício). A direção vigente é a do memo `-02`, que corrigiu a posição do `-01` sobre a aplicabilidade simultânea de Condition e Certification (Q9 do memo `-01`) — nenhuma conclusão do `-01` sobre esse ponto específico havia sido consolidada em C-*/LDM-*, portanto não há supersessão de documento canônico.

Achado de contexto registrado no memo `-01` e preservado aqui: diferente de Condition, não existe nenhuma tabela física equivalente a `card_condition` para Grading/Certification em Pricing ou em qualquer outro módulo — esta subfrente parte de base conceitual pura, sem prior art físico a ratificar.

**Status desta subfrente: Collections — Grading / Certification conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-121 a C-140) e `logical-model.md` (LDM-109 a LDM-128, deliberadamente sem skeleton físico). Confirmado: Grading (workflow, fora do V1) é distinto de Certification (resultado formal, modelada), que pertence exclusivamente à Physical Card; Grading Company é Reference Data própria; Grade depende de Grading Company + Grade Scale, sem assumir equivalência entre companies; Grade admite valor e/ou designação, sem enum físico; Certification Number é opcional, sem criar um conceito separado de "Grading Declaration"; no máximo uma Current Certification por Physical Card; raw/graded é predicado derivado da existência de Current Certification. **Fechamento definitivo da pendência deixada aberta por C-111/C-112**: Current Condition e Current Certification são mutuamente exclusivas quanto à aplicabilidade corrente — RAW pode ter Current Condition opcional; GRADED (existe Current Certification) tem Current Condition não aplicável enquanto a Certification permanecer corrente — sem que isso implique fusão, substituição ou derivação entre os dois valores (Grade ≠ Condition, sem de-para automático, C-133). Condition History permanece fora do V1: crack restaura a aplicabilidade de Current Condition, mas nenhum valor anterior é restaurado automaticamente; regrade preserva a identidade da Physical Card, sem canonizar o workflow temporal entre certificações. Certification é dado declarado/registrado, não verificado. Subgrades/qualifiers, Protection/Encapsulation detalhada, Custody durante grading (já fechada por C-49/C-50) e Storage permanecem com as fronteiras já estabelecidas — Certification não define nem absorve nenhuma delas. Relação futura com Valuation reconhecida, sem reabrir Pricing V1. Wishlist V1 permanece inalterada.

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: skeleton físico de Grading Company/Grade Scale/Grade/Certification; tipo de dado exato de Grade (valor+designação); cardinalidade de Grade Scale por Grading Company; taxonomia de status detalhado de Certification além de current/ausente; submission/regrade/crack workflow operacional; Certification History; subgrades/qualifiers em detalhe; verification externa; modelagem própria de Protection/Encapsulation; refinamento de Wishlist por Certification. Nenhum código, SQL, tabela, UUID ou migration foi tratado nesta subfrente. C-01–C-120 e LDM-01–LDM-108 não foram reabertas em conteúdo — Physical Card Condition (C-103–C-120/LDM-91–LDM-108), Custody/Availability (C-49–C-54/LDM-38–LDM-43), Storage (C-55–C-66/LDM-44–LDM-54), Lifecycle/Provenance (C-67–C-81/LDM-55–LDM-69) e Wishlist (C-91–C-102/LDM-79–LDM-90) permanecem integralmente vigentes.

---

## 14. Collection Collaboration / Permissions — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Grading/Certification (Seção 13): uma subfrente própria, `COLLECTIONS-COLLABORATION-PERMISSIONS-CONSOLIDATION-01`, formalizou `Collection Collaboration`/`Permissions` a partir de dois memos conceituais (`COLLECTIONS-COLLABORATION-PERMISSIONS-MODELING-01`/`-02`, conduzidos sem edição de arquivo, revisados por Fabrício). A direção vigente é a do memo `-02`, que corrigiu uma duplicidade conceitual do `-01` — Owner tratado simultaneamente como relação estrutural própria e como role de Collection Membership — antes de qualquer consolidação; nenhuma conclusão do `-01` sobre esse ponto havia sido consolidada em C-*/LDM-*, portanto não há supersessão de documento canônico.

**Status desta subfrente: Collections — Collaboration / Permissions conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-141 a C-165) e `logical-model.md` (LDM-129 a LDM-153, deliberadamente sem skeleton físico). Confirmado: Collection Owner é relação estrutural própria (`Collection → User`), fora de Collection Membership — Owner não é convidado, não aceita convite, não sai e não é removido por mecanismo de Membership; Collection Membership representa exclusivamente participação de Users não-owner (0..N), com roles V1 restritas a EDITOR e VIEWER (OWNER não é role de Membership); Membership nasce apenas por convite emitido pelo Owner + aceitação explícita, nunca silenciosamente; Collaboration nunca concede ownership sobre Physical Cards/Inventory/Storage/Favorite/Wishlist/dados privados do Owner. Fronteira central desta rodada: Editor cobre operações Collection-scoped (Layout, Expected Content, Slot Assignment de cartas já alocadas, metadata comum), enquanto Collection Allocation permanece Owner-only — reclassificada como **Owner-authorized Collection operation** (determina quais Physical Cards do Inventory do Owner participam da Collection, exigindo autoridade sobre o conjunto de exemplares elegíveis), corrigindo a formulação inicial do memo-01 que a descrevia genericamente como "operação patrimonial". Visibility (PUBLIC/PRIVATE), Archive/Delete e Membership management permanecem Owner-only. **Public Access formalizado como consequência de Visibility, distinto de Membership e da role VIEWER** — um User não-Member pode visualizar Collection PUBLIC sem se tornar Member nem receber role VIEWER (três eixos independentes: Visibility ≠ Membership ≠ Role). Privacidade por padrão confirmada: Storage, Provenance, Favorite, Wishlist e dados financeiros/privados de transação não são expostos automaticamente por Collaboration; Physical Card visibility é escopada às cartas já alocadas àquela Collection específica, sem navegação ao Inventory completo do Owner; Condition/Certification podem ser visíveis para fins curatoriais, mas edição permanece Owner-only. Necessidade futura de Audit Log sobre ações de Collaborators reconhecida e registrada, sem solução modelada.

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: sistema de permissão customizada/capability assignments granulares além de EDITOR/VIEWER; transferência de Collection ownership; mecanismo de private sharing link para Collection PRIVATE; desenho de Audit Log; distinção futura archive vs. hard delete. Nenhum código, SQL, tabela, UUID, RLS ou migration foi tratado nesta subfrente. C-01–C-140 e LDM-01–LDM-128 não foram reabertas em conteúdo — Collection core, Physical Card/Inventory, Custody/Availability, Storage, Layout/Page/Slot, Lifecycle/Provenance, Favorite, Wishlist, Physical Card Condition e Grading/Certification permanecem integralmente vigentes.

---

## 15. Collection Activity History / Audit — subfrente adicional consolidada em 2026-08-30

Registrado nesta mesma data, após o fechamento de Collaboration/Permissions (Seção 14): uma subfrente própria, `COLLECTIONS-ACTIVITY-HISTORY-AUDIT-CONSOLIDATION-01`, formalizou `Collection Activity History`/`Audit Log` a partir de um único memo conceitual (`COLLECTIONS-ACTIVITY-HISTORY-AUDIT-MODELING-01`, conduzido sem edição de arquivo, revisado por Fabrício, sem rodada de correção intermediária — direção aprovada diretamente).

**Status desta subfrente: Collections — Activity History / Audit conceptual modeling: CLOSED.**

Resultado incorporado a `concept-decisions.md` (C-166 a C-186) e `logical-model.md` (LDM-154 a LDM-174, deliberadamente sem skeleton físico). Confirmadas três camadas conceitualmente distintas: `Physical Card Lifecycle/Provenance` (não reaberta), `Collection Activity History` (novo — sequência temporal de acontecimentos de domínio significativos, Collection-scoped, user-facing, em linguagem de domínio, nunca mutação técnica) e `Audit Log` (necessidade já registrada em C-164, agora com propósito mínimo formalizado — governança/segurança/accountability, reconstrução conceitual de "quem fez o quê, quando, sobre qual entidade/contexto"). Activity Trigger refinado do memo original: não mais limitada a "ação que muda diretamente o estado", mas "acontecimento de domínio significativo relacionado à evolução/operação da Collection". Actor pode ser Owner, Editor ou System; Viewer/Public User não geram Activity por simples leitura. Visibilidade de Activity History: Owner + Members (EDITOR/VIEWER), nunca automática a Public User mesmo em Collection PUBLIC — Public Access ≠ acesso ao histórico interno de colaboração. Activity histórica permanece atribuída ao ator após saída/remoção de Membership, sem conceder direito residual. Privacidade confirmada: Activity nunca expõe amount paid, seller/buyer, dados financeiros, Storage, Provenance privada, Favorite ou Wishlist. Audit coverage priorizado por risco — ações Owner-sensitive (Membership, Visibility, Collection Allocation, Archive/Delete) e ações state-changing de Collaborators (Layout, Expected Content, Slot Assignment, metadata editável), sem auditar toda mutação técnica. Reconhecidas quatro combinações Activity×Audit (Activity+Audit, Audit-only, Activity-only, nenhuma), sem matriz exaustiva fechada. Registros históricos são imutáveis enquanto existirem, sem retenção/TTL definidos. Fronteira identificada, não resolvida: destino de Activity/Audit após archive/hard-delete da Collection, distinto do ciclo de vida de Physical Card Lifecycle (que permanece independente). History ≠ Undo/Restore; History ≠ fonte de estado corrente (sem event sourcing implícito); Activity ≠ Lifecycle (sem duplicação automática de fatos patrimoniais, mas possibilidade futura reconhecida sem fusão dos conceitos).

Explicitamente fora deste fechamento, permanecendo em aberto para rodadas futuras: lista exaustiva de categorias de Activity; algoritmo/mecanismo de agrupamento para operações em massa; classificação exaustiva da matriz Activity×Audit por categoria; retenção/TTL de Activity e Audit; política completa de hard-delete/archive sobre Activity/Audit; schema físico de qualquer uma das três camadas; modelagem de Undo/Restore/reversibilidade. Nenhum código, SQL, tabela, UUID, RLS ou migration foi tratado nesta subfrente. C-01–C-165 e LDM-01–LDM-153 não foram reabertas em conteúdo — todas as subfrentes anteriores permanecem integralmente vigentes.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste checkpoint (2026-08-30) — consolida dez rodadas de modelagem conceitual (`COLLECTIONS-LAYOUT-MODELING-01` a `-10`) sobre Collection Layout/Page/Slot/Expected Content/Lock/Slot Assignment/Bandeja/Layout Region. Registra diagnóstico de reconciliação (decisões reutilizadas, novas, superseded, conflitos), aponta para C-38–C-46 e LDM-29–LDM-37 já incorporados a `concept-decisions.md`/`logical-model.md`, resolve `checkpoint-2026-08-29.md` §5 itens 4–5, e declara a próxima decisão em aberto. |
| 1.1 | **Verificação final (`COLLECTIONS-LAYOUT-CONSOLIDATION-VERIFY-01`), a pedido explícito de Fabrício, antes de qualquer commit.** Removida "persistência futura da Bandeja" da lista de decisões abertas (Seção 5 e Seção 6) — D54–D59/C-45/LDM-36 já fecham esse comportamento conceitualmente; qualquer staging persistente futuro seria requisito de produto novo, não pendência da Bandeja atual. Adicionada Seção 1.1 com o status formal da subfrente ("Collections — Layout/Page/Slot conceptual modeling: CLOSED", com o escopo exato do que isso cobre e não cobre). `concept-decisions.md` C-44 recebeu parágrafo explícito confirmando que Slot Assignment não requer identidade de lifecycle própria no nível conceitual (ponto já presente em LDM-35, agora também na camada conceitual). Confirmado via `git status`/`git diff --stat`: exatamente 5 arquivos alterados nesta subfrente (4 modificados + 1 novo, 0 deletados) — nenhuma alteração fora do escopo esperado. |
| 1.2 | **Convergência terminológica para `Physical Card`, 2026-08-30.** Este checkpoint permanece ativo (não é puramente histórico como `checkpoint-2026-08-28.md`/`checkpoint-2026-08-29.md`), por isso suas próprias citações de terminologia foram atualizadas: `Inventory Item`/`Collection Item` → `Physical Card` nas Seções 2.1, 2.3 e 6, cada ocorrência anotada com "(à época deste checkpoint, ...)" para preservar rastreabilidade de qual termo era vigente quando este documento foi originalmente escrito. A citação literal do pseudo-código de `pkmnbindr-benchmark.md` §4 (`inventory_item = NULL`) não foi alterada, por citar um documento externo não editado nesta rodada. Seção 6, item 1 recebeu nota adicional: a preservação de identidade da Physical Card durante transferência entre Inventories já está formalizada por C-48/LDM-23 (2026-08-30); o que permanece aberto é apenas o mecanismo operacional da transferência. Ver `concept-decisions.md` C-47/C-48 e `logical-model.md` LDM-23 (revisada) para a base desta convergência. |
| 1.3 | **Custody & Availability, subfrente adicional (`COLLECTIONS-CUSTODY-AVAILABILITY-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 7, registrando o fechamento conceitual desta subfrente (`Collections — Custody / Availability conceptual modeling: CLOSED`) e apontando para C-49–C-54/LDM-38–LDM-43, já incorporados a `concept-decisions.md`/`logical-model.md`. Documentos Relacionados atualizado. Seções 1–6 (Layout) não alteradas em conteúdo. |
| 1.4 | **Storage, subfrente adicional (`COLLECTIONS-STORAGE-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 8, registrando o fechamento conceitual desta subfrente (`Collections — Storage conceptual modeling: CLOSED`) e apontando para C-55–C-66/LDM-44–LDM-54, já incorporados a `concept-decisions.md`/`logical-model.md`. Documentos Relacionados atualizado. Seções 1–7 não alteradas em conteúdo. |
| 1.5 | **Physical Card Lifecycle & Provenance, subfrente adicional (`COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 9, registrando o fechamento conceitual desta subfrente (`Collections — Physical Card Lifecycle / Provenance conceptual modeling: CLOSED`) e apontando para C-67–C-81/LDM-55–LDM-69, já incorporados a `concept-decisions.md`/`logical-model.md`. Documentos Relacionados atualizado. Seções 1–8 não alteradas em conteúdo. |
| 1.6 | **Favorite, subfrente adicional (`COLLECTIONS-FAVORITE-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 10, registrando o fechamento conceitual desta subfrente (`Collections — Favorite conceptual modeling: CLOSED`) e apontando para C-82–C-90/LDM-70–LDM-78, já incorporados a `concept-decisions.md`/`logical-model.md`. Seção 6, item 3 (pendência "Modelo de Favorite") marcada resolvida, apontando para a Seção 10 — permanece aberto apenas o skeleton físico. Documentos Relacionados atualizado. Seções 1–9 não alteradas em conteúdo. |
| 1.7 | **Wishlist, subfrente adicional (`COLLECTIONS-WISHLIST-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 11, registrando o fechamento conceitual desta subfrente (`Collections — Wishlist conceptual modeling: CLOSED`) e apontando para C-91–C-102/LDM-79–LDM-90, já incorporados a `concept-decisions.md`/`logical-model.md`. Documentos Relacionados atualizado. Seções 1–10 não alteradas em conteúdo. |
| 1.8 | **Physical Card Condition, subfrente adicional (`COLLECTIONS-PHYSICAL-CARD-CONDITION-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 12, registrando o fechamento conceitual desta subfrente (`Collections — Physical Card Condition conceptual modeling: CLOSED`) e apontando para C-103–C-120/LDM-91–LDM-108, já incorporados a `concept-decisions.md`/`logical-model.md`. Registrada a ratificação conceitual da referência canônica compartilhada `card_condition` (já `CONFIRMADO EXECUTADO` em Pricing) e a nota de divergência sobre a rodada "CONDITION-MODELING-02" referenciada no pedido de consolidação mas não entregue literalmente sob esse nome nesta sessão. Documentos Relacionados atualizado (inclui `05f-pricing.md`). Seções 1–11 não alteradas em conteúdo. |
| 1.9 | **Grading / Certification, subfrente adicional (`COLLECTIONS-GRADING-CERTIFICATION-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 13, registrando o fechamento conceitual desta subfrente (`Collections — Grading / Certification conceptual modeling: CLOSED`) e apontando para C-121–C-140/LDM-109–LDM-128, já incorporados a `concept-decisions.md`/`logical-model.md`. Registrado o fechamento definitivo da pendência deixada aberta por C-111/C-112 (Current Condition e Current Certification mutuamente exclusivas quanto à aplicabilidade corrente), o achado de ausência de fundação física equivalente a `card_condition` para Grading/Certification, e a direção vigente do memo `-02` (correção da posição do `-01` sobre a aplicabilidade simultânea, sem supersessão de documento canônico). Documentos Relacionados atualizado. Seções 1–12 não alteradas em conteúdo. |
| 1.10 | **Collection Collaboration / Permissions, subfrente adicional (`COLLECTIONS-COLLABORATION-PERMISSIONS-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 14, registrando o fechamento conceitual desta subfrente (`Collections — Collaboration / Permissions conceptual modeling: CLOSED`) e apontando para C-141–C-165/LDM-129–LDM-153, já incorporados a `concept-decisions.md`/`logical-model.md`. Registrada a separação estrutural entre Collection Owner (fora de Membership) e Collection Membership (EDITOR/VIEWER), a reclassificação de Collection Allocation como Owner-authorized Collection operation, a formalização de Public Access como consequência de Visibility distinta de Membership/role VIEWER, e a direção vigente do memo `-02` (correção da duplicidade conceitual Owner×Membership do `-01`, sem supersessão de documento canônico). Documentos Relacionados atualizado. Seções 1–13 não alteradas em conteúdo. |
| 1.11 | **Collection Activity History / Audit, subfrente adicional (`COLLECTIONS-ACTIVITY-HISTORY-AUDIT-CONSOLIDATION-01`), 2026-08-30.** Adicionada Seção 15, registrando o fechamento conceitual desta subfrente (`Collections — Activity History / Audit conceptual modeling: CLOSED`) e apontando para C-166–C-186/LDM-154–LDM-174, já incorporados a `concept-decisions.md`/`logical-model.md`. Registradas as três camadas conceitualmente distintas (Lifecycle/Provenance, Activity History, Audit), o refinamento do Activity Trigger para "acontecimento de domínio significativo", a visibilidade de Activity restrita a Owner+Members, e a cobertura de Audit priorizada por risco. Memo único (`COLLECTIONS-ACTIVITY-HISTORY-AUDIT-MODELING-01`) aprovado diretamente, sem rodada de correção intermediária. Documentos Relacionados atualizado. Seções 1–14 não alteradas em conteúdo. |
| 1.12 | **Fechamento da pendência de contagem de Condition (2026-08-31), a pedido de Fabrício — `COLLECTIONS-CARD-CONDITION-RECONCILIATION-02`, exclusivamente documental.** Decorrente da auditoria read-only `COLLECTIONS-CARD-CONDITION-MINT-POSTCHECK-01` (condição física `M`/Mint incluída via UI, zero regressão de Pricing confirmada — **SAFE**). Seção 12 recebeu nota de fechamento: a discrepância "5 linhas" vs. "6 códigos", registrada desde a criação desta seção como pendência aberta, está **CLOSED** — removida da lista "explicitamente fora deste fechamento". `concept-decisions.md` (C-105–C-107) e `logical-model.md` (LDM-93–LDM-95) atualizadas na mesma rodada para refletir os codes físicos reais (`M`/`NM`/`LP`/`MP`/`HP`/`DMG`, `condition_order` 1..6) em vez dos codes longos nunca gravados fisicamente. Seções 1–11 e 13–15 não alteradas em conteúdo. Nenhum código/SQL/tabela/migration alterado. |
