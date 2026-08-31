# Collection — Concept Decisions

| Campo | Valor |
|--------|-------|
| **Documento** | Collection — Concept Decisions (Modelagem Conceitual) |
| **Arquivo** | `docs/domain-modeling/collections/concept-decisions.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` como fonte canônica em 2026-08-28 (pedido explícito de Fabrício). |
| **Decision Register** | C-01 a C-37 (núcleo Collection); C-38 a C-46 (bloco complementar Collection Layout, 2026-08-30); C-47 a C-48 (bloco complementar Physical Card & Inventory, 2026-08-30); C-49 a C-54 (bloco complementar Custody & Availability, 2026-08-30); C-55 a C-66 (bloco complementar Storage, 2026-08-30); C-67 a C-81 (bloco complementar Physical Card Lifecycle & Provenance, 2026-08-30); C-82 a C-90 (bloco complementar Favorite, 2026-08-30); C-91 a C-102 (bloco complementar Wishlist, 2026-08-30); C-103 a C-120 (bloco complementar Physical Card Condition, 2026-08-30) |
| **Status** | FECHADA / APROVADA PARA MODELAGEM LÓGICA (núcleo); bloco complementar de Layout também Aprovado; bloco complementar Physical Card & Inventory também Aprovado; bloco complementar Custody & Availability também Aprovado; bloco complementar Storage também Aprovado; bloco complementar Physical Card Lifecycle & Provenance também Aprovado; bloco complementar Favorite também Aprovado; bloco complementar Wishlist também Aprovado; bloco complementar Physical Card Condition também Aprovado |
| **Escopo** | Modelagem conceitual da entidade `Collection` (colecionador), desde 2026-08-30 de `Collection Layout`/`Page`/`Slot`, desde 2026-08-30 da identidade `Physical Card` e do agregado `Inventory`, desde 2026-08-30 das dimensões `Custody`/`Custodian`/`Availability`, desde 2026-08-30 de `Storage`/`Storage Container` (incluindo hierarquia opcional), desde 2026-08-30 de `Lifecycle`/`Provenance` (Ownership Entry/Transfer/Exit), desde 2026-08-30 de `Favorite` (preferência do User por Card), desde 2026-08-30 de `Wishlist` (intenção do User por Card Variant), e desde 2026-08-30 de `Physical Card Condition` (classificação padronizada do estado físico, referenciando a escala canônica compartilhada `card_condition`) — não contém SQL nem modelo físico. |
| **Documentos Relacionados** | `../../04-domain-model.md` (seções Collection/Collection Entry/Collection Item — ver nota de superação), `adr/ADR-013-collection-item-identity-model.md` e `adr/ADR-014-collection-and-collection-entry-model.md` (ambas **Substituídas** por este documento e por `logical-model.md`), `logical-model.md`, `pkmnbindr-benchmark.md`, `checkpoint-2026-08-28.md`, `checkpoint-2026-08-29.md`, `checkpoint-2026-08-30.md`, `ux-exploration-2026-08-29.md`. |

---

> **Nota de incorporação (2026-08-28).** Este documento chega ao repositório já FECHADO/APROVADO (produzido em sessão paralela de modelagem). A partir desta data, ele — junto com `logical-model.md` e `checkpoint-2026-08-28.md` — é a referência canônica e vigente para o domínio conceitual de `Collection`, substituindo o conteúdo equivalente de `ADR-013`/`ADR-014` e das seções correspondentes de `04-domain-model.md` (mantidas por rastreabilidade histórica, com nota de superação apontando para cá — ver `03-documentation-architecture.md`, "General Rules": preservar o histórico de decisões substituídas). Nenhuma decisão deste documento foi alterada na incorporação; reconciliação de prosa em `04-domain-model.md`/`05d-colecoes-e-usuarios.md` fica para quando a modelagem física começar (ver Parte F, abaixo, e `checkpoint-2026-08-28.md`).

---

## 1. Objetivo deste documento

Este documento registra as decisões conceituais consolidadas para a entidade `Collection` do MMKYU Collector.

Ele tem dois objetivos:

1. preservar o histórico das decisões tomadas durante a modelagem conceitual;
2. fornecer um estado canônico e inequívoco para a próxima fase de modelagem lógica.

Este documento **não contém SQL, modelo físico ou implementação**.

A modelagem lógica deverá derivar destas decisões, e não reinterpretá-las silenciosamente.

---

# PARTE A — DECISION REGISTER

## C-01 — Conceito de Collection

**Status:** Aprovada

`Collection` é uma estrutura persistente de organização de exemplares efetivamente possuídos pelo usuário.

Ela pode:

- funcionar como curadoria aberta, sem universo conhecido de completude;
- utilizar um universo de referência para medir progresso.

Composição e completude são conceitos independentes.

Uma Collection convencional baseada em Card Set pode conter múltiplas `Card Variants` da mesma `Card`, ainda que para completude baste ao menos uma variante válida daquela Card.

Em uma Collection Master Set, cada `Card Variant` relevante constitui individualmente uma posição de completude.

Cartas não possuídas não pertencem à Collection; intenções de aquisição pertencem à Wishlist.

**Princípio:**
`Posse ≠ Composição ≠ Completude ≠ Desejo`

---

## C-02 — Modo de organização explícito

**Status:** Aprovada

Toda Collection declara explicitamente seu modo de organização.

Modos conceituais:

- curadoria aberta;
- universo de referência estático;
- universo de referência dinâmico.

Em universos dinâmicos, a fonte canônica pode evoluir automaticamente no catálogo, mas o escopo adotado por uma Collection existente permanece congelado até aprovação explícita do usuário.

Exemplo: uma Pokédex já criada não recebe automaticamente novos Pokémon apenas porque o catálogo canônico evoluiu.

---

## C-03 — Participação intencional

**Status:** Aprovada

A participação de um exemplar em uma Collection é intencional.

Compatibilidade com a Collection torna o exemplar elegível, mas não determina automaticamente sua alocação.

A intenção pode ser expressa:

- individualmente;
- por operações em massa.

**Princípio:** explícito não significa manual um a um.

O produto deve suportar operações em massa para evitar inviabilidade de uso em acervos com centenas ou milhares de cartas.

---

## C-04 — Exclusividade colecionável e localização física

**Status:** Revisada e Aprovada

Cada `Physical Card` pode participar de zero ou uma `Collection` por vez.

Essa associação representa sua alocação colecionável, **não sua localização física**.

Um mesmo exemplar não pode contribuir simultaneamente para múltiplas Collections.

`Physical Cards` sem Collection continuam existindo normalmente e podem estar armazenadas em locais físicos independentes, como ETBs, caixas ou outros recipientes.

---

## C-05 — Vínculo obrigatório com Game

**Status:** Aprovada; posteriormente complementada pela C-35

Toda Collection pertence obrigatoriamente a um único `Game`.

Todas as `Physical Cards` alocadas nela devem pertencer ao mesmo Game.

Collections cross-game não são suportadas.

---

## C-06 — Arquivamento

**Status:** Aprovada

Uma Collection pode ser arquivada sem perder identidade ou histórico.

Arquivamento e exclusão são conceitos distintos.

---

## C-07 — Nome não é identidade

**Status:** Aprovada; posteriormente complementada pela C-34

O nome da Collection é atributo de apresentação e não participa de sua identidade técnica.

Collections distintas podem compartilhar o mesmo nome.

---

## C-08 — Owner, compartilhamento e permissões

**Status:** Aprovada

Toda Collection possui um único `Owner`.

A Collection pode ser compartilhada com zero ou vários usuários adicionais.

Para cada usuário compartilhado, o Owner define quais ações são permitidas naquela Collection.

As permissões pertencem à relação `User ↔ Collection` e podem diferir entre Collections.

Compartilhamento da Collection não altera a propriedade física das `Physical Cards`.

O Owner mantém autoridade administrativa principal sobre a Collection.

---

## C-09 — Mudança de modo

**Status:** Aprovada

O modo de organização da Collection é estrutural.

Ele não pode ser alterado como uma propriedade comum de edição.

Mudanças de modo, quando suportadas, devem ocorrer por fluxo explícito de conversão/migração.

---

## C-10 — Representação visual da Collection

**Status:** Superseded / Evoluída

Inicialmente, a Collection foi concebida visualmente como um Binder digital personalizável.

Durante a evolução do modelo, concluiu-se que Binder é apenas um tipo de `Storage Container`.

A diretriz visual permanece válida, porém a experiência principal evoluiu para um **Visual Collection Space / Carousel de Storage Containers**, podendo conter Binder, ETB, Storage Box e outros tipos.

O conceito de Binder como única representação da Collection foi superado.

---

## C-11 — Consolidação do universo de referência

**Status:** Aprovada

O universo de referência pode ser alterado enquanto a Collection **nunca tiver recebido a alocação de uma `Physical Card`**.

A associação do primeiro exemplar consolida essa referência.

Depois disso, a referência não pode ser alterada por edição comum, mesmo que a Collection volte a ficar vazia.

Mudanças posteriores somente podem ocorrer por processo explícito de conversão/migração.

Além disso, o universo de referência define a fronteira básica de elegibilidade da Collection.

---

## C-12 — Transferência de ownership

**Status:** Aprovada

O ownership de uma Collection pode ser transferido pelo Owner exclusivamente para um usuário que já participe da Collection como usuário compartilhado.

A transferência preserva:

- identidade;
- conteúdo;
- configuração;
- histórico.

Ela não transfere automaticamente a propriedade das `Physical Cards`.

A Collection deve possuir exatamente um Owner em todos os momentos.

---

## C-13 — Exclusão

**Status:** Aprovada

Uma Collection pode ser excluída somente quando não possuir nenhuma `Physical Card` associada.

A exclusão nunca remove, desaloca ou modifica automaticamente `Physical Cards`.

Caso existam itens associados, o usuário deve:

- removê-los;
- realocá-los;
- ou arquivar a Collection.

---

## C-14 — Idiomas

**Status:** Aprovada

Uma Collection pode conter `Physical Cards` em diferentes idiomas.

Idioma não constitui, por si só, restrição de alocação à Collection.

---

## C-15 — Visibilidade pública

**Status:** Aprovada

A visibilidade da Collection é independente do compartilhamento.

Toda Collection nasce privada.

O Owner pode torná-la pública para visualização.

Visibilidade pública:

- não transforma visitantes em membros;
- não concede permissões operacionais;
- não altera compartilhamentos existentes.

---

## C-16 — Capacidade física

**Status:** Aprovada

Collection não possui capacidade física própria.

Quantidade de páginas, slots, formato do Binder e demais limites físicos pertencem ao modelo de `Storage Container`.

Alterar capacidade física não altera a identidade ou semântica da Collection.

---

## C-17 — Distribuição física da Collection

**Status:** Revisada e Aprovada

Uma Collection pode ter suas `Physical Cards` distribuídas entre zero, um ou vários `Storage Containers`.

Tipos possíveis incluem:

- Binder;
- ETB;
- Storage Box;
- outros tipos futuros.

`Storage Container` não é propriedade exclusiva de uma Collection.

---

## C-18 — Storage inicial

**Status:** Absorvida / Substituída pela C-36

Foi definido que um Storage Container deve ser escolhido no momento da criação da Collection.

A semântica definitiva dessa decisão foi posteriormente consolidada na C-36 como `Default Storage Container`.

---

## C-19 — Itens que contam para progresso

**Status:** Aprovada

O progresso de uma Collection é calculado exclusivamente a partir das `Physical Cards` efetivamente alocadas àquela Collection.

Itens elegíveis:

- sem Collection;
- ou alocados em outra Collection;

não satisfazem posições de completude.

O sistema pode identificá-los e sugerir sua utilização, mas a associação depende de decisão explícita do usuário.

**Princípio:**
`Possuir ≠ Alocar ≠ Completar`

---

## C-20 — Completude calculada

**Status:** Aprovada

Em Collections com universo de referência, progresso e estado de completude são calculados automaticamente pelo sistema.

O usuário não pode marcar manualmente uma Collection como completa ou incompleta.

Collections de curadoria aberta não possuem estado de completude.

---

## C-21 — Duplicatas dentro da Collection

**Status:** Aprovada

Uma Collection pode conter múltiplas `Physical Cards` correspondentes à mesma `Card` e inclusive à mesma `Card Variant`.

Cada exemplar físico permanece individualmente registrado.

Exemplares adicionais não aumentam artificialmente o progresso.

Cada requisito do universo de referência é considerado satisfeito apenas conforme sua regra de completude.

---

## C-22 — Uma única fonte canônica de referência

**Status:** Aprovada

Uma Collection com universo de referência possui exatamente uma fonte canônica.

Não são suportados universos compostos formados pela combinação de múltiplos Card Sets ou outras fontes.

Collections que reúnam conteúdos de diferentes universos devem usar curadoria aberta.

---

## C-23 — Mudança entre Set convencional e Master Set

**Status:** Aprovada

Em Collections baseadas em Card Set, o Owner pode alterar o critério de completude entre:

- Set convencional;
- Master Set.

A alteração pode ocorrer mesmo após existirem `Physical Cards`.

Ela preserva:

- referência;
- exemplares;
- organização física.

Somente os requisitos de completude e o progresso são recalculados.

---

## C-24 — Layout livre

**Status:** Aprovada

A organização física/visual da Collection é definida livremente pelo usuário e é independente da ordem lógica do universo de referência.

A numeração e estrutura canônica continuam sendo usadas para:

- elegibilidade;
- progresso;
- completude.

Mas não determinam a posição física das `Physical Cards`.

**Princípio:**
O universo responde "o que falta".
O layout responde "como quero organizar".

---

## C-25 — Storage Container compartilhado entre Collections

**Status:** Aprovada

Um `Storage Container` pode armazenar:

- itens de diferentes Collections;
- itens sem Collection.

Não existe exclusividade entre `Storage Container` e `Collection`.

Para ETBs e Storage Boxes, fica registrada a diretriz futura de UX de utilizar separadores/divisórias para representar diferentes agrupamentos.

---

## C-26 — Physical Card sem Storage

**Status:** Aprovada

Uma `Physical Card` pode existir sem `Storage Container`.

A localização física é opcional e pode ser definida ou alterada posteriormente.

A ausência de Storage não impede a alocação à Collection nem contribuição para completude.

---

## C-27 — Compartilhamento e Storage

**Status:** Aprovada

O compartilhamento de uma Collection propaga automaticamente aos usuários compartilhados o acesso aos `Storage Containers` utilizados por suas `Physical Cards`, somente no contexto necessário para visualizar ou operar aquela Collection.

Isso não representa compartilhamento irrestrito do Storage Container.

Itens:

- de outras Collections;
- ou sem Collection;

permanecem protegidos por suas próprias regras.

As permissões nesse contexto derivam da Collection.

---

## C-28 — Movimentação física

**Status:** Aprovada

Mover uma `Physical Card` entre `Storage Containers` é independente de sua associação com a Collection.

Alterar localização física não modifica automaticamente:

- alocação colecionável;
- elegibilidade;
- contribuição para completude.

---

## C-29 — Realocação entre Collections

**Status:** Aprovada

Uma `Physical Card` pode ser:

- realocada entre Collections;
- removida de uma Collection e ficar sem Collection.

A realocação preserva a identidade do exemplar e não altera automaticamente seu `Storage Container`.

Antes de ingressar na Collection de destino, sua elegibilidade deve ser validada.

As Collections afetadas têm progresso e completude recalculados automaticamente.

---

## C-30 — Lifecycle

**Status:** Aprovada

A Collection possui dois estados explícitos:

- `ACTIVE`;
- `ARCHIVED`.

Toda Collection nasce `ACTIVE`.

Completude e progresso são estados derivados e não fazem parte do lifecycle.

Exclusão é uma operação sobre a entidade, não um lifecycle status.

---

## C-31 — Metadados da entidade

**Status:** Aprovada

Collection mantém apenas metadados ligados a:

- identidade;
- propriedade;
- contexto colecionável;
- regras de funcionamento.

Elementos físicos e visuais pertencem aos `Storage Containers`.

---

## C-32 — Múltiplas Collections para a mesma referência

**Status:** Aprovada

Um usuário pode possuir múltiplas Collections baseadas no mesmo universo de referência.

A referência canônica não é exclusiva por usuário.

Cada Collection possui:

- identidade própria;
- exemplares próprios;
- progresso próprio;
- compartilhamentos próprios;
- configurações próprias.

---

## C-33 — Validação mínima de elegibilidade

**Status:** Aprovada

Em Collections com universo de referência, o sistema valida apenas se a `Physical Card` pertence ao universo aplicável.

Não são aplicadas regras adicionais de elegibilidade baseadas em:

- raridade;
- idioma;
- borda;
- estética;
- outros atributos de preferência pessoal.

O sistema garante a integridade do universo; o usuário define o estilo da coleção.

Exemplos:

- Card Set: validar se a Card pertence ao Set.
- Pokédex: validar se a Card representa o Pokémon correto para aquela posição.

---

## C-34 — Nome não único

**Status:** Aprovada

O nome da Collection é obrigatório, mas não precisa ser único.

Collections diferentes podem possuir nomes idênticos, inclusive sob o mesmo Owner.

A identidade é determinada por identificador interno.

A interface pode alertar sobre duplicidade, mas não bloquear.

---

## C-35 — Game imutável

**Status:** Aprovada

Toda Collection pertence obrigatoriamente a exatamente um `Game`.

O Game é definido na criação e é imutável durante todo o ciclo de vida.

Uma Collection nunca pode conter `Physical Cards` de Games diferentes.

Se uma Collection vazia for criada no Game incorreto, deve ser excluída e recriada.

---

## C-36 — Default Storage Container

**Status:** Aprovada

Toda Collection possui um `Default Storage Container`, obrigatoriamente definido em sua criação.

Ele representa o destino físico padrão sugerido para novas `Physical Cards` associadas à Collection.

Pode ser alterado pelo Owner a qualquer momento.

Não estabelece exclusividade.

Cada `Physical Card` mantém sua própria localização física independente e pode estar:

- no Default Storage;
- em outro Storage Container;
- sem localização definida.

---

## C-37 — Comportamento de ARCHIVED

**Status:** Aprovada

Uma Collection `ARCHIVED` permanece integralmente preservada e disponível para consulta, mas não aceita operações que alterem:

- composição;
- organização colecionável;
- configuração.

Seus:

- `Physical Cards`;
- `Storage Containers`;
- progresso;
- compartilhamentos;
- relações;

permanecem preservados.

Para voltar a operar, o Owner deve reativá-la para `ACTIVE`.

Arquivamento não altera:

- localização física;
- propriedade dos exemplares;
- completude.

---

## Bloco complementar — Collection Layout (2026-08-30)

Adicionado após reconciliação da frente `COLLECTIONS-LAYOUT-MODELING` (dez rodadas de modelagem conceitual conduzidas em 2026-08-30, consolidadas em `checkpoint-2026-08-30.md`). Não reabre C-01–C-37; complementa a Parte D (entidades descobertas), fechando a modelagem de `Binder Page`, `Binder Slot` e parte de `Placeholder`, ali listadas como pendentes.

## C-38 — Collection Layout como entidade independente de Storage

**Status:** Aprovada

`Collection Layout` é a organização visual/espacial de uma `Collection` — a forma como o usuário arranja livremente (C-24) a apresentação de suas `Physical Cards` alocadas. É independente de `Storage Container`: trocar o Storage Container físico não destrói nem recria o Layout.

Todo `Collection Layout` possui exatamente uma `Collection` como contexto funcional. Uma `Collection` pode existir sem Layout. O modelo conceitual permite, no futuro, mais de um Layout por Collection, mesmo que a primeira versão do produto exponha apenas um Layout principal.

Hierarquia conceitual:

```text
Collection
└── Layout
    └── Page
        └── Slot
```

`Storage` permanece ortogonal a esta hierarquia. Não modelar, nesta rodada, um "Storage Layout" (organização interna de um Storage Container independente de qualquer Collection) — mas a arquitetura não deve impedir essa extensão futura.

---

## C-39 — Page como unidade estrutural do Layout

**Status:** Aprovada

`Page` é entidade conceitual própria e estável, pertencente a exatamente um `Collection Layout`. Sua identidade independe de sua posição/ordem entre as demais Pages do mesmo Layout (Page identity ≠ Page order); a ordenação é mutável sem afetar identidade.

Toda Page nasce estruturalmente completa: recebe, no mesmo ato lógico de sua criação, todos os `Slots` estruturais determinados pelo Grid Configuration do Layout (ver C-40). Não existe Page estruturalmente parcial.

Remover uma Page exige resolver previamente qualquer dependência persistente existente em seus Slots (Slot Assignments, Expected Content, Layout Region) — não há remoção automática silenciosa de conteúdo.

Elementos como capa externa, lombada, inner cover e decorações do Binder Workspace não são Page enquanto não existir requisito funcional que lhes dê Slots estruturais reais.

`Spread` (par de Pages exibidas lado a lado) não é conceito de domínio — é apresentação derivada, de responsabilidade exclusiva da camada de UX.

---

## C-40 — Grid Configuration pertence ao Layout

**Status:** Aprovada

A configuração de grade (`columns × rows`) pertence ao `Collection Layout`, não à Page individualmente. Todas as Pages de um mesmo Layout usam obrigatoriamente a mesma Grid Configuration — não são permitidas Pages com grids diferentes dentro do mesmo Layout.

A capacidade estrutural de cada Page (`capacity_per_page = columns × rows`) é inteiramente derivada dessa configuração, nunca um valor independente.

Mudança de grid de um Layout já existente ("Grid Change", ex. 3×3 → 4×4) é reconhecida como necessidade futura, mas seu mecanismo (migração no lugar vs. novo Layout, tratamento de Slots/Assignments fora dos novos limites) não é decidido nesta rodada.

---

## C-41 — Slot como posição estrutural estável

**Status:** Aprovada

`Slot` é entidade conceitual própria e estável, pertencente a exatamente uma `Page`. Sua identidade é independente de: estar ocupado por uma `Physical Card`; ter `Expected Content` definido; e das operações (Move/Swap/Replace) que alteram seu conteúdo ao longo do tempo. Slot nasce e morre junto com mudanças estruturais da Page (grid/capacidade), nunca junto com mudanças de conteúdo.

Posição do Slot dentro de sua Page é representada por coordenadas absolutas `row + column`, 1-based (`row = 1..rows`, `column = 1..columns`). Posição não é identidade (Slot position ≠ Slot identity) — um índice de exibição sequencial, se necessário no futuro, é sempre derivado de row/column e da Grid Configuration, nunca uma segunda fonte de verdade persistida.

---

## C-42 — Expected Content do Slot

**Status:** Aprovada

Um Slot pode possuir, opcionalmente, `Expected Content` — a intenção/expectativa editorial daquela posição ("o que esta posição deveria representar"), independente de sua ocupação física atual. Expected Content referencia obrigatoriamente uma `Card` e, opcionalmente, de forma mais específica, uma `Card Variant`. Ausência de Variant significa que qualquer Variant compatível daquela Card satisfaz a expectativa.

Expected Content e ocupação física (ver C-44) são independentes: são válidos os quatro estados — nenhum; só Expected Content; só ocupação; ambos. Incompatibilidade entre Expected Content e a `Physical Card` ocupando o Slot (mismatch) nunca bloqueia a ocupação — é estado derivado, apenas sinalizável pelo produto.

Expected Content **não participa** do cálculo de completude da Collection — completude permanece exclusivamente derivada da alocação à Collection frente ao universo de referência (C-19/C-20), nunca do Layout.

Expected Content representa exclusivamente conteúdo editorial/colecionável. Não incorpora custom image, divisor visual, região decorativa ou outros elementos puramente visuais — esses pertencem a uma futura frente própria de Layout, não modelada aqui.

---

## C-43 — Lock protege a posição do Slot

**Status:** Aprovada

`Lock` é propriedade do `Slot` — protege a posição/configuração daquela posição no Layout, não a `Physical Card` que porventura a ocupa, nem a relação de ocupação corrente. Um Slot pode estar locked mesmo vazio, sem Expected Content e sem ocupação.

Lock é independente de Ownership, de alocação à Collection e de Expected Content. Enquanto locked, ficam bloqueadas as operações que alterariam a ocupação/configuração protegida: Move, Swap, Replace, Remove, Drop, mover para a Bandeja, e criar/desfazer uma `Layout Region` (Merge/Unmerge) que envolva aquele Slot. Substituir a Physical Card de um Slot nunca transfere o Lock para ela — Lock permanece no Slot.

Operações em lote (Bulk Lock/Unlock) aplicam a mesma propriedade uniformemente a um conjunto de Slots, independente da ocupação de cada um. Não existe "Region Lock" separado — regiões mescladas herdam a regra acima Slot a Slot.

---

## C-44 — Slot Assignment: posicionamento digital dentro do Layout

**Status:** Aprovada

`Slot Assignment` (nome adotado nesta consolidação — nasceu como rótulo de trabalho provisório ao longo da frente de modelagem, incorporado aqui como termo canônico; pode ser revisto se um nome melhor surgir) é a relação que registra que uma `Physical Card` está, agora, posicionada em um `Slot` de um `Collection Layout` — distinta de Ownership (quem possui), de alocação à Collection (por qual objetivo colecionável conta) e de Expected Content (o que a posição deveria representar).

Slot Assignment exige que a `Physical Card` já esteja alocada à mesma `Collection` dona do Layout — não é possível posicionar uma carta no Layout de uma Collection à qual ela não está alocada. A recíproca não vale: uma Physical Card pode estar alocada a uma Collection sem ter nenhuma Slot Assignment (ex.: recém-importada, na Bandeja, layout ainda não organizado).

`Slot Assignment` representa organização digital do Layout, nunca localização física real (Storage — C-16/C-17/C-25–C-28 permanecem a única fonte de verdade sobre onde o exemplar está fisicamente guardado). Por isso, a mesma `Physical Card` pode ter Slot Assignments simultâneas e independentes em Layouts diferentes da mesma Collection (ver C-38, múltiplos Layouts) — cardinalidade é no máximo uma Assignment ativa por par (Physical Card, Layout), não uma restrição global da carta.

Dentro de um mesmo Slot, no máximo uma Physical Card por vez.

`Slot Assignment` é uma relação conceitual própria de estado atual — não requer identidade de negócio/lifecycle própria no modelo conceitual atual (não é necessário distinguir "esta Assignment sobreviveu a um Move" de "a relação atual Item↔Slot mudou"). Um identificador técnico de implementação, se existir, não constitui identidade de domínio. Histórico, audit trail, versionamento ou Undo/Redo persistente, se necessários no futuro, serão modelados separadamente.

---

## C-45 — Bandeja é estado transitório de UX

**Status:** Aprovada

A "Bandeja" (área temporária para cartas fora de qualquer Slot durante a edição de um Layout) é estado transitório de UX/edição, não entidade de domínio, não estado persistente do Layout, não propriedade da Collection nem da Physical Card. Seu escopo é somente a sessão/interação ativa de edição daquele Layout.

Se o usuário mover um item para a Bandeja e sair da Collection/Layout antes de reposicioná-lo, a Bandeja é descartada e, ao retornar, o item está novamente em seu Slot Assignment persistido de origem — mover para a Bandeja não equivale a um Remove persistente da Slot Assignment. A Bandeja funciona como buffer temporário de reorganização: o resultado persistente de "Slot A → Bandeja → Slot B" é apenas "item passa de A para B"; o estado intermediário na Bandeja nunca integra o estado persistido.

---

## C-46 — Layout Region (mesclagem de Slots)

**Status:** Aprovada

`Layout Region` é o conceito persistente para representar a mesclagem visual de dois ou mais Slots contíguos ("Merge") — nunca destrói, recria ou altera a identidade dos Slots envolvidos. Pertence a exatamente uma Page, nunca atravessa Pages. Contém no mínimo 2 Slots contíguos, formando obrigatoriamente um retângulo completo (não suporta, nesta modelagem, formas em L, buracos ou regiões arbitrárias). Regions não podem se sobrepor — um Slot participa de no máximo uma Layout Region ativa.

Criar ou remover uma Layout Region não altera Slot Assignments nem Expected Content dos Slots envolvidos. Se qualquer Slot necessário à operação estiver locked (C-43), Merge e Unmerge ficam bloqueados.

Futuro conteúdo visual/artwork de uma Region é conceito distinto de Expected Content (C-42), que permanece exclusivamente editorial/colecionável — artwork não é modelado nesta rodada.

---

## Bloco complementar — Physical Card & Inventory (2026-08-30)

Adicionado durante a reconciliação terminológica `COLLECTIONS-PHYSICAL-CARD-RECONCILIATION-02`, formalizando como decisão conceitual C-* o que, até esta rodada, existia apenas em `checkpoint-2026-08-28.md` (introdução do agregado `Inventory`) e em quatro memos de modelagem conceitual conduzidos sem edição de arquivo (`COLLECTIONS-INVENTORY-MODELING-01` a `-04`), todos explicitamente registrados sem criar C-*/LDM-* própria. Nenhuma decisão de conteúdo nova é introduzida aqui além do que já havia sido aprovado nesses memos — este bloco só dá a essas decisões um lugar canônico que antes não existia. C-01–C-46 não são reabertas.

## C-47 — Physical Card: identidade permanente do exemplar físico

**Status:** Aprovada

`Physical Card` é a identidade permanente de uma cópia física individual de uma `Card Variant` — nome técnico canônico, sucedendo (nesta ordem histórica) "Collection Item" e "Inventory Item", ambos superseded (ver Parte D). Não é uma entidade paralela a esses nomes anteriores — é a mesma identidade física já reconhecida desde LDM-23, apenas correta e definitivamente nomeada.

A identidade de uma Physical Card independe de ownership corrente e de participação em `Inventory` (ver C-48): sobrevive a transferência entre usuários, venda para fora do MMKYU, perda e descarte — nunca é recriada por mudança de ownership, custody, Storage, condition ou availability. Cada cópia física possui identidade própria e permanente, mesmo quando editorialmente indistinguível de outra (mesma Card, mesma Card Variant, mesmo idioma) — nunca representada como quantidade agregada.

---

## C-48 — Inventory: agregado de ownership corrente sobre Physical Cards

**Status:** Aprovada

`Inventory` é o agregado patrimonial que reúne as `Physical Cards` atualmente sob ownership de seu titular no MMKYU — 1:1 por usuário. Inventory não é histórico, não é Storage, não é Collection, não é Layout, e não é agrupamento arbitrário definido pelo usuário.

Uma `Physical Card` sob ownership corrente representado pelo MMKYU participa de exatamente um Inventory. Uma Physical Card pode existir sem Inventory corrente quando não houver ownership atual rastreado pelo MMKYU (ex.: venda para fora da plataforma, perda, descarte) — a ausência de Inventory corrente não invalida nem recria sua identidade (C-47). Uma Physical Card não pode participar simultaneamente de mais de um Inventory corrente.

Esta regra substitui, com o refinamento de "ownership corrente" explicitado, a formulação original — nunca formalizada em C-*/LDM-* — de que "todo Inventory Item pertence obrigatoriamente a um Inventory" (memo `COLLECTIONS-INVENTORY-MODELING-01`, decisão de trabalho "I3", nunca promovida a C-*/LDM-*). Nada aqui é tecnicamente superseded no Decision Register — é a primeira formalização canônica do que antes só existia em `checkpoint-2026-08-28.md` §2.3–2.4 e nos memos de modelagem.

Participação em Inventory representa exclusivamente ownership patrimonial corrente — nunca Custody (quem está fisicamente com o exemplar, ver C-49–C-51), nunca Availability (se está oferecido para troca/venda/reserva, ver C-53). Essas dimensões são conceitualmente independentes de Inventory e, desde 2026-08-30, estão formalizadas no bloco complementar C-49–C-54 abaixo (nota atualizada nesta data; referenciava anteriormente o memo `COLLECTIONS-INVENTORY-MODELING-03`, que permanece válido como origem, agora promovido a C-*).

Collection Allocation associa uma Physical Card a uma Collection (C-04); Slot Assignment representa uma Physical Card posicionada em um Slot do Layout (C-44); Expected Content referencia exclusivamente Card/Card Variant, nunca Physical Card (C-42) — nenhuma dessas três relações é alterada, redefinida ou reaberta por este bloco.

---

## Bloco complementar — Custody & Availability (2026-08-30)

Adicionado ao final de `COLLECTIONS-CUSTODY-AVAILABILITY-CONSOLIDATION-01`, formalizando como decisão conceitual C-* o que, até esta rodada, existia apenas no memo de modelagem conceitual `COLLECTIONS-INVENTORY-MODELING-05` (Custody/Possession/Availability, conduzido sem edição de arquivo, explicitamente registrado sem criar C-*/LDM-* própria). Nenhuma decisão de conteúdo nova é introduzida além do que já havia sido aprovado nesse memo e revisado por Fabrício — este bloco só dá a essas decisões um lugar canônico que antes não existia. C-01–C-48 não são reabertas. Storage detalhado permanece OPEN, não tratado por este bloco (ver `logical-model.md` §7).

## C-49 — Custody: guarda física corrente, independente de Storage

**Status:** Aprovada

`Custody` é a dimensão que responde: *sob controle físico de quem está o exemplar, agora?* — termo canônico adotado; `Possession` não é utilizado como conceito concorrente. Custody é independente de ownership patrimonial (participação em Inventory, C-48) e independente de Storage: Storage responde onde o exemplar está organizado/guardado dentro da estrutura física modelada do acervo; Custody responde quem detém o controle físico corrente, que pode divergir da estrutura de Storage do titular (empréstimo, grading, trânsito, perda).

Não se formaliza regra rígida de que Storage preenchido implica Custody obrigatoriamente do owner — Storage normal do próprio acervo do titular pode sustentar essa presunção operacional (ver C-51), mas os dois conceitos permanecem independentes entre si.

---

## C-50 — Custodian: distinção conceitual sem entidade própria

**Status:** Aprovada

`Custodian` é o agente que exerce a Custody, quando conhecida — distinto de Custody (a relação/condição de guarda em si). Quando conhecida, Custody pode estar sob responsabilidade do próprio owner ou de um terceiro; terceiro pode futuramente ser outro User MMKYU, pessoa externa sem conta, grading company, loja/intermediário, transportadora ("em trânsito") ou outro agente. Nenhuma entidade `Custodian` é criada nesta rodada — preserva-se apenas a distinção conceitual para modelagem futura.

Terceiros externos ao MMKYU (grading company, loja, transportadora) são representáveis como valores de Custodian quando a Custody for modelada em detalhe — nunca como Storage Container, mesmo estando fisicamente com a Physical Card (ver C-49). "Em trânsito" não recebe conceito estrutural novo nesta rodada — permanece circunstância futura de Custody/lifecycle, não uma dimensão própria.

---

## C-51 — Default operacional de Custody

**Status:** Aprovada

Na ausência de evidência de Custody excepcional, o produto pode presumir que a Physical Card sob ownership corrente permanece sob Custody do próprio owner. Esta é uma presunção/default operacional de produto — não uma prova material de que o owner está fisicamente com a carta, e não obriga cadastro explícito de Custody para o volume normal de Physical Cards de um acervo.

---

## C-52 — LOST e Recovery: continuidade de ownership e identidade

**Status:** Aprovada

`LOST` é a situação em que o ownership corrente permanece (participação em Inventory inalterada) e a Custody/localização física confiável do exemplar é desconhecida — não uma fórmula estrutural fixa combinando Custody e Storage, e não um evento de lifecycle que encerra ownership. Distinguem-se sempre duas afirmações: "não sei onde está" (Custody desconhecida) é conceitualmente diferente de "não é mais meu" (evento de Ownership Lifecycle, fora de escopo desta rodada). LOST nunca implica, por si só, a segunda afirmação. O tratamento específico de Storage neste cenário fica para a modelagem detalhada de Storage.

`Recovery` preserva a mesma Physical Card — não cria nova identidade. Restabelece apenas o conhecimento confiável sobre Custody/localização física, revertendo o estado de LOST.

---

## C-53 — Availability: disposição transacional corrente, condicionada a ownership

**Status:** Aprovada

`Availability` representa a disposição transacional corrente do owner sobre uma Physical Card (exemplos conceituais: não oferecida, disponível para trade, disponível para sale, reservada) — não um enum definitivo, apenas o escopo conceitual da dimensão. Não pertencem a Availability: emprestada, perdida, enviada para grading, em trânsito — esses casos pertencem a Custody/lifecycle (C-49/C-50/C-52), não a Availability.

Availability só é semanticamente aplicável quando há ownership corrente rastreado pelo MMKYU (participação em Inventory, C-48). Para uma Physical Card sem Inventory corrente, Availability é conceitualmente **não aplicável** — nunca simplesmente "not available".

---

## C-54 — Custody/Availability não alteram Collection/Layout; completion é ownership-based

**Status:** Aprovada

Mudanças de Custody ou de Availability não alteram, por si próprias, Collection Allocation, completion ou Slot Assignment. Uma Physical Card enviada para grading continua contando para a Collection enquanto ownership e Collection Allocation permanecerem válidos; uma Physical Card disponível para trade continua contando até que ownership realmente mude.

Completion é ownership-based, não possession/custody-based — a pergunta conceitual respondida por completion é "o owner possui Physical Cards suficientes alocadas para satisfazer os requisitos da Collection?", nunca "todas estão fisicamente comigo neste instante?". Esta leitura já era consequência direta de C-19 ("Possuir ≠ Alocar ≠ Completar") e C-26 (ausência de Storage não impede completion) — este bloco apenas a confirma explicitamente para o eixo Custody/Availability, sem reabrir C-19/C-26. Custody pode ser exibida futuramente como informação complementar na UI, sem alterar completion.

---

## Bloco complementar — Storage (2026-08-30)

Adicionado ao final de `COLLECTIONS-STORAGE-CONSOLIDATION-01`, encerrando a subfrente `Collections — Storage conceptual modeling`, conduzida por três memos conceituais (`COLLECTIONS-STORAGE-MODELING-01`/`-02` e uma rodada de correção sobre remoção/hierarquia), todos sem edição de arquivo. Nenhuma decisão de conteúdo nova é introduzida além do que já havia sido aprovado nesses memos e revisado por Fabrício — este bloco só dá a essas decisões um lugar canônico que antes não existia. C-01–C-54 não são reabertas. Protection/Encapsulation, histórico de Storage ("last known storage") e modelagem física (SQL, capacidade rígida por tipo, UX detalhada) permanecem explicitamente fora de escopo.

## C-55 — Storage e Storage Container: definição e fronteira

**Status:** Aprovada

`Storage` é a dimensão que responde onde uma Physical Card está fisicamente guardada, dentro da organização estruturada e corrente do acervo. `Storage Container` é a unidade física endereçável que materializa essa dimensão (Binder, ETB, Storage Box, Deck Box, maleta, cofre, entre outros — tipos não fixados como enum fechado, ver C-17). Storage é distinto de Custody (quem detém controle físico corrente, C-49), de Collection Layout (organização digital, nunca física, C-38/C-44) e de Collection (organização de um objetivo colecionável, não localização física, C-16).

## C-56 — Storage × Protection: critério de endereçabilidade

**Status:** Aprovada

Nem todo objeto que envolve fisicamente uma Physical Card é Storage Container. O critério conceitual é a endereçabilidade: Storage Container é a unidade física que o usuário trata como localização endereçável dentro da organização do seu acervo — não qualquer objeto capaz de conter fisicamente a carta. Sleeves, toploaders, one-touch holders, slabs de grading e acessórios equivalentes podem futuramente compor uma dimensão distinta de Protection/Encapsulation, não modelada nesta rodada — não são, por si só, Storage Container.

## C-57 — Storage Container: ownership mediado por Inventory

**Status:** Aprovada

Um Storage Container pertence ao contexto patrimonial de exatamente um Inventory — nunca a uma Collection, e nunca via `owner_user_id` direto como fonte paralela de ownership (mesmo padrão já corrigido para Physical Card em C-48, evitando repetir o desenho SUPERSEDED de LDM-25).

## C-58 — Physical Card × Storage: cardinalidade e independência

**Status:** Aprovada

Uma Physical Card pode existir sem Storage Container corrente, e possui no máximo um Storage Container corrente por vez — nunca simultaneamente em dois. Mudança de Storage altera apenas localização física: não altera ownership, Collection Allocation, Slot Assignment, completion, nem a identidade da Physical Card (mesma independência já estabelecida por C-28/C-19/C-20/C-26, agora reafirmada explicitamente também frente a Slot Assignment).

## C-59 — Storage Container: existência vazia, independência de Collection e caráter corrente

**Status:** Aprovada

Um Storage Container pode existir vazio, sem nenhuma Physical Card associada. Collection e Storage permanecem dimensões independentes (C-16/C-17/C-25 reafirmadas): um Storage Container pode guardar Physical Cards de várias Collections do mesmo Inventory, ou Physical Cards sem Collection alguma; o Default Storage Container de uma Collection (C-36) permanece um vínculo/destino operacional, não uma exclusividade que obrigue todas as Physical Cards da Collection a estarem ali. Storage representa exclusivamente localização corrente confiável — nunca "last known storage"; histórico de Storage permanece fora desta subfrente.

## C-60 — Hierarquia de Storage Container

**Status:** Aprovada

Um Storage Container pode, opcionalmente, estar contido em outro Storage Container (relação parent/child), sem exigir hierarquia para todo Storage. Uma Physical Card referencia apenas o Storage Container mais específico que representa sua localização corrente — nunca a cadeia inteira; a localização superior (ex.: Armário → Caixa → Deck Box) é sempre derivada pela navegação da cadeia de parents, nunca armazenada redundantemente. Esta regra evita que uma mesma Physical Card tenha múltiplas localizações simultâneas mesmo sob hierarquia — preserva C-58 integralmente.

## C-61 — Fronteira de Inventory: Storage nunca cruza Inventory

**Status:** Aprovada

Storage cross-Inventory não é suportado: uma Physical Card só pode usar como Storage corrente um Storage Container do mesmo Inventory de seu ownership corrente (decorrência direta de C-57/C-48). Sob hierarquia (C-60), parent e child Storage Container devem sempre pertencer ao mesmo Inventory — a árvore de containers nunca cruza fronteiras patrimoniais. Empréstimo, grading, guarda por terceiro e Physical Card temporariamente com outro User são representados por Custody (C-49/C-50), nunca por referência a Storage de um Inventory diferente.

## C-62 — Capacidade de Storage Container

**Status:** Aprovada

Capacidade é conceito opcional e dependente do tipo/configuração do Storage Container — pode ser conhecida, aproximada ou não aplicável, nunca universal nem uma regra rígida de bloqueio nesta etapa. Capacidade física de Storage Container é distinta de Grid Configuration/capacidade de Collection Layout (C-40/LDM-31, digital) — os dois conceitos não devem ser confundidos.

## C-63 — Remoção de Storage Container: vazio estrutural

**Status:** Aprovada

Um Storage Container só pode ser removido quando estruturalmente vazio: zero Physical Cards diretamente associadas e zero Storage Containers filhos, simultaneamente. Um parent com filho vazio ainda não pode ser removido; um parent com descendentes que contenham Physical Cards também não pode. Não existe cascade conceitual de delete — remover um Storage Container nunca apaga containers filhos nem destrói ou invalida Physical Cards.

## C-64 — Bulk Card Transfer: transferência em massa de Physical Cards

**Status:** Aprovada

Existe a operação conceitual "Transferir todas as Physical Cards", que move em lote apenas as Physical Cards diretamente associadas a um Storage Container de origem para um Storage Container de destino válido (capaz de receber Physical Cards diretamente), sempre dentro do mesmo Inventory (C-61). Altera apenas o Storage corrente de cada Physical Card movida — não altera ownership, Collection Allocation, Slot Assignment, completion, nem identidade (mesma regra de C-28, aplicada em lote). Product Behavior detalhado (fluxo, confirmação, tratamento de erro parcial) fica para rodada própria.

## C-65 — Reparent Storage Container: reposicionamento na hierarquia

**Status:** Aprovada

Existe operação conceitual distinta, "Mover/Reparent Storage Container", que move um Storage Container filho para outro parent válido — não deve ser confundida com Bulk Card Transfer (C-64), que opera sobre Physical Cards, não sobre containers. Parent e child permanecem sempre no mesmo Inventory (C-61); a operação não altera as Physical Cards contidas no container movido, nem ownership, Collection Allocation, Slot Assignment ou completion. Product Behavior detalhado fica para rodada própria.

## C-66 — Default Storage sob hierarquia

**Status:** Aprovada

Sob hierarquia de Storage Container (C-60), o Default Storage Container de uma Collection (C-36) deve apontar para um Storage Container válido como destino operacional de novas Physical Cards — nunca para um container que não possa receber Physical Cards diretamente. Esta rodada não reabre a existência ou obrigatoriedade do Default Storage Container (C-36 permanece integralmente vigente); apenas precisa sua semântica para o cenário, agora suportado, de hierarquia.

---

## Bloco complementar — Physical Card Lifecycle & Provenance (2026-08-30)

Adicionado ao final de `COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-CONSOLIDATION-01`, encerrando a subfrente `Collections — Physical Card Lifecycle / Provenance conceptual modeling`, conduzida por dois memos conceituais (`COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-MODELING-01`/`-02`), ambos sem edição de arquivo. Nenhuma decisão de conteúdo nova é introduzida além do que já havia sido aprovado nesses memos e revisado por Fabrício — este bloco só dá a essas decisões um lugar canônico que antes não existia. C-01–C-66 não são reabertas — em particular, C-49–C-54 (Custody/Availability) permanecem integralmente vigentes, sem alteração de conteúdo. Audit Log transversal, permissões detalhadas, evidence levels, workflow de grading, histórico de Loan/LOST/Recovery, histórico detalhado de condition, Pricing e Valuation permanecem explicitamente fora de escopo.

## C-67 — Lifecycle: fatos históricos, identidade permanente

**Status:** Aprovada

`Lifecycle` é o conjunto de fatos históricos relevantes que acontecem a uma Physical Card ao longo do tempo — distinto dos estados correntes já fechados (Inventory, Custody, Storage, Availability, condition). A identidade da Physical Card (C-47) permanece a mesma através de todos os eventos de lifecycle; nenhum evento a recria.

## C-68 — Provenance: subconjunto de Lifecycle, com exclusões explícitas

**Status:** Aprovada

`Provenance` é o subconjunto de Lifecycle focado em origem, entrada em ownership e trajetória patrimonial relevante de uma Physical Card. Provenance explicitamente **não é**: Audit Log transversal; histórico completo de Storage; histórico completo de condition; Pricing History; Valuation History.

## C-69 — Current State vs. Historical Event: critério

**Status:** Aprovada

`Current State` responde "o que é verdade agora?" (Inventory, Custody, Storage, Availability e condition correntes, já fechados nas subfrentes anteriores). `Historical Event` responde "o que aconteceu, e quando?" — um fato imutável uma vez registrado, que pode se repetir ao longo do tempo. Nenhum estado corrente é obrigado a ser derivado de um log de eventos por força desta decisão — as duas camadas são conceitualmente complementares, não uma implementação obrigatória da outra.

## C-70 — Ownership Entry

**Status:** Aprovada

Quando o ownership rastreado de uma Physical Card começa sem owner MMKYU anterior conhecido, existe conceitualmente um `Ownership Entry`. Dados de aquisição associados são opcionais — podem incluir data, origem, forma, valor pago, moeda e notas — e nenhum deles bloqueia o cadastro básico ou bulk import de uma Physical Card.

## C-71 — Ownership Transfer: fato único e atômico

**Status:** Aprovada

Uma transferência MMKYU → MMKYU é **um único fato patrimonial**, não dois fatos independentes de saída e entrada. Ela encerra o ownership corrente de A, inicia o ownership corrente de B, preserva a mesma Physical Card (C-47), e não possui hiato conceitual entre os dois ownerships — a Physical Card nunca fica sem owner MMKYU corrente durante o ato.

## C-72 — Ownership Exit

**Status:** Aprovada

`Ownership Exit` encerra o ownership rastreado de uma Physical Card sem que exista um novo owner MMKYU conhecido. A Physical Card pode continuar existindo sem Inventory corrente (C-48 reafirmada) — o Exit não invalida nem recria sua identidade.

## C-73 — Reasons qualificam o evento, não criam tipos estruturais

**Status:** Aprovada

O motivo de um Ownership Entry, Transfer ou Exit qualifica o evento como atributo — nunca cria um tipo estrutural próprio por motivo. Exemplos ilustrativos, não exaustivos e não fixados como enum: Entry (purchase, gift, trade, pull, unknown); Transfer (sale, gift, trade); Exit (external sale, external gift, external trade, disposal, destruction, outro).

## C-74 — Ownership Episode: ferramenta conceitual

**Status:** Aprovada

`Ownership Episode` é uma ferramenta conceitual — o intervalo durante o qual uma Physical Card permanece sob ownership corrente de um determinado Inventory/titular — usada para raciocinar sobre Acquisition e Provenance. Não constitui entidade canônica própria nesta rodada.

## C-75 — Physical Card Provenance vs. Owner/Transaction Private Data

**Status:** Aprovada

`Physical Card Provenance` (a trajetória patrimonial relevante da própria carta — que teve determinados episódios de ownership, aproximadamente quando, por qual categoria geral de evento) é distinta de `Owner/Transaction Private Data` (os detalhes de um episódio específico: valor pago, seller, buyer, frete, margem, contraparte, notas privadas). Dados privados de um episódio pertencem ao respectivo owner e **não são herdados nem expostos automaticamente** ao owner seguinte quando a Physical Card muda de mãos. A identidade de owners anteriores também não deve ser assumida como automaticamente pública/compartilhável. Permissões detalhadas ficam para frente própria — não modeladas aqui.

## C-76 — Evidência/verificação: linguagem segura

**Status:** Aprovada

Provenance é descrita como "registrada/rastreada no MMKYU" — nunca como "verificada", "certificada" ou parte de uma "cadeia autenticada". Não se assume autenticidade, certificação, matching físico infalível nem qualquer mecanismo de blockchain. Um futuro nível de evidência (ex.: autodeclarado vs. documentado) pode existir, mas não é modelado nesta rodada.

## C-77 — Transfer Integrity: consequências paralelas

**Status:** Aprovada

Uma mudança de ownership (Transfer ou Exit) deve resultar em estado consistente quanto a Collection Allocation, Slot Assignment dependente e Storage — três consequências **paralelas e independentes** da mesma mudança patrimonial, não uma cadeia onde Collection Allocation deriva da regra de Storage. Collection Allocation incompatível decorre de invariante própria (uma Collection pertence a um titular); Slot Assignment dependente decorre, essa sim, de exigir Collection Allocation prévia (C-44/LDM-35); Storage incompatível decorre da fronteira de Inventory já fechada (C-57/C-61). Product Behavior de resolução não é definido nesta etapa.

## C-78 — Custody permanece independente de ownership, inclusive após Exit

**Status:** Aprovada

Custody (C-49–C-54, não alteradas) permanece independente de ownership patrimonial. Ownership Exit não força Custody para "não aplicável" — Custody pode continuar conceitualmente significativa após um Exit (ex.: vendedor ainda fisicamente com a carta, transportadora, terceiro), já que nenhuma decisão fechada de Custody condiciona sua aplicabilidade à existência de ownership corrente. Na prática, Custody pós-Exit tende a ficar desatualizada por falta de motivo para atualização — uma questão prática, não uma regra de domínio.

## C-79 — Núcleo V1 de Lifecycle

**Status:** Aprovada

O núcleo de Lifecycle para V1 é: Ownership Entry, Ownership Transfer e Ownership Exit — existindo como consequência natural dos fluxos patrimoniais que o produto já precisa suportar, nunca exigindo preenchimento manual de dados de aquisição. Histórico de Loan, LOST/Recovery e Grading ficam fora do núcleo V1; os estados correntes já modelados (Custody, Availability) permanecem integralmente válidos.

## C-80 — Grading: fechamento mínimo

**Status:** Aprovada

Fecha-se apenas: Grading pode alterar o estado atual de certificação da Physical Card, e pode futuramente produzir fatos relevantes de lifecycle. Submission, return, regrade, cracking e qualquer workflow de grading não são modelados nesta rodada.

## C-81 — Valuation/Pricing History não fazem parte da Provenance

**Status:** Aprovada

Pricing History e Valuation History não fazem parte de Provenance (reafirma C-68). Amount paid / sale amount podem existir como dados transacionais privados de um episódio de ownership (Owner/Transaction Private Data, C-75) — nunca como o sinal de mercado contínuo que Pricing/Valuation representam. Pricing V1 (`05f-pricing.md`) não é reaberto por esta decisão.

---

## Bloco complementar — Favorite (2026-08-30)

Adicionado ao final de `COLLECTIONS-FAVORITE-CONSOLIDATION-01`, encerrando a subfrente `Collections — Favorite conceptual modeling`, conduzida por um memo conceitual (`COLLECTIONS-FAVORITE-MODELING-01`, sem edição de arquivo). Nenhuma decisão de conteúdo nova é introduzida além do que já havia sido aprovado nesse memo e revisado por Fabrício — este bloco só dá a essas decisões um lugar canônico que antes não existia. C-01–C-81 não são reabertas — em particular, `Custody`/`Availability` (C-49–C-54), `Storage` (C-55–C-66) e `Lifecycle`/`Provenance` (C-67–C-81) permanecem integralmente vigentes. Wishlist em profundidade, `Pokémon`/`Subject Reference`, ranking/grail, recomendações e notificações permanecem explicitamente fora de escopo.

## C-82 — Favorite: definição e entidade-alvo

**Status:** Aprovada

`Favorite` representa a preferência editorial pessoal de um `User` por uma `Card`. Referencia exclusivamente `Card` — nunca `Card Variant`, `Physical Card`, `Collection`, Collection Allocation, Slot Assignment ou Storage. Favoritar uma `Card` significa gostar dela editorialmente (arte, personagem, posição no Set), independentemente de acabamento — o usuário não favorita cada `Card Variant` separadamente.

## C-83 — Favorite pertence ao User, transversal às Collections

**Status:** Aprovada

`Favorite` pertence ao `User`, não à `Collection`. É transversal a todas as Collections do usuário — não pertence a nenhuma Collection específica e não é afetado pelo papel do User frente a uma Collection (Owner ou Member): o Favorite de um User independe de ele ser Collection Owner, ser Collection Member, ou não participar de nenhuma Collection. Não há relação entre Favorite e a existência de `Inventory`.

## C-84 — Independência de ownership

**Status:** Aprovada

`Favorite` é independente de ownership. Pode existir quando o User nunca possuiu nenhuma `Physical Card` correspondente à `Card` favoritada, possui uma, possui várias, vendeu todas, ou volta a adquirir no futuro — nenhum desses estados cria, altera ou invalida um Favorite.

## C-85 — Independência de Collection

**Status:** Aprovada

`Favorite` não altera nem depende de completion, Collection Allocation, canonical ordering, Layout ou Slot Assignment. É possível favoritar uma `Card` que não participa de nenhuma Collection do usuário.

## C-86 — Favorite é binário

**Status:** Aprovada

`Favorite` responde apenas "esta Card é favorita deste User? Sim ou não." Não são modelados score, rating, prioridade, níveis de favorito ou ranking. Um futuro conceito de "grail", ranking ou nível de interesse, se necessário, será conceito próprio de produto — não extensão implícita de Favorite.

## C-87 — Cardinalidade conceitual

**Status:** Aprovada

Um `User` pode favoritar N `Cards`; uma `Card` pode ser favorita de N `Users`; no máximo um Favorite por par (`User`, `Card`) — sem duplicidade. Constraint física não é discutida nesta rodada.

## C-88 — Favorite vs. Wishlist

**Status:** Aprovada

`Favorite` ("gosto/destaco esta Card") e `Wishlist` ("quero adquirir esta Card") são conceitos independentes, que podem coexistir ou não sem relação de dependência estrutural entre si. Wishlist em profundidade não é modelada nesta rodada (permanece pendência própria, já registrada em B.2).

## C-89 — Cada Card é identidade editorial própria

**Status:** Aprovada

Cada `Card` continua sendo identidade editorial própria (uma posição única por Set, C-47 reafirmada). Favoritar uma Card de determinado Set não implica favoritar outras Cards do mesmo Pokémon/personagem em outros Sets — cada impressão exige seu próprio Favorite. Uma futura camada `Pokémon`/`Subject Reference` permanece fora desta frente.

## C-90 — Catalog lifecycle não modelado

**Status:** Aprovada

Enquanto a `Card` existir como identidade editorial no catálogo, Favorite permanece ligado à mesma Card. Hard delete, deprecation behavior e catalog lifecycle não são modelados nesta rodada — ficam para frente própria de modelagem de catálogo.

---

## Bloco complementar — Wishlist (2026-08-30)

Adicionado ao final de `COLLECTIONS-WISHLIST-CONSOLIDATION-01`, encerrando a subfrente `Collections — Wishlist conceptual modeling`, conduzida por dois memos conceituais (`COLLECTIONS-WISHLIST-MODELING-01`/`-02`, sem edição de arquivo). A direção vigente é a do memo `-02`, que corrigiu a granularidade de alvo proposta no memo `-01` (Card obrigatório + Variant opcional) para `Card Variant` obrigatório — nenhuma dessas conclusões havia sido consolidada em C-*/LDM-*, portanto não há supersessão de documento canônico, apenas a formalização direta da versão corrigida. C-01–C-90 não são reabertas — em particular, `Favorite` (C-82–C-90) permanece integralmente vigente, com a diferença de granularidade frente a Wishlist tratada como intencional (C-97). Quantity, priority/grail, price target, Marketplace, condition e grading permanecem explicitamente fora de escopo.

## C-91 — Wishlist: definição e alvo obrigatório Card Variant

**Status:** Aprovada

`Wishlist` representa a intenção pessoal declarada de um `User` de adquirir uma determinada `Card Variant`. Toda Wishlist referencia obrigatoriamente uma `Card Variant` — não existe Wishlist genérica apenas para `Card` no núcleo atual. A `Card` correspondente é conhecida indiretamente através da `Card Variant`, no mesmo nível de especificidade em que uma `Physical Card` real é referenciada (ver `Physical Card`, C-47).

## C-92 — Idioma como refinamento opcional

**Status:** Aprovada

Wishlist pode opcionalmente especificar um idioma desejado sobre a `Card Variant` alvo. Ausência de idioma significa que qualquer idioma é aceitável. Exemplos válidos: Variant X + qualquer idioma; Variant X + PT-BR; Variant X + EN; Variant X + JP.

## C-93 — Independência de ownership, sem remoção automática

**Status:** Aprovada

Wishlist independe completamente de ownership corrente. Pode existir quando o User nunca possuiu nenhuma `Physical Card` correspondente, possui uma, possui várias, ou possui exatamente a mesma `Card Variant` + idioma desejados — é válido desejar uma combinação mesmo já possuindo uma ou várias `Physical Cards` compatíveis, sem que isso exija quantity para ser representado. `Possuir ≠ Desejar`. Aquisição de uma Physical Card correspondente (Ownership Entry ou Transfer, C-70/C-71) não remove automaticamente a Wishlist — a intenção só deixa de existir por decisão explícita do User ou por um futuro comportamento assistido de produto, não modelado nesta rodada.

## C-94 — Independência de completion: Wishlist ≠ Collection Missing

**Status:** Aprovada

Wishlist não é derivada de completion. São válidos, em qualquer combinação: lacuna de completion sem Wishlist; Wishlist sem lacuna de completion; ambos; nenhum. `Possuir ≠ Alocar ≠ Completar ≠ Desejar` (estende C-19).

## C-95 — Sem vínculo estrutural com Collection

**Status:** Aprovada

Não existe vínculo estrutural entre Wishlist e Collection no núcleo atual — Wishlist não pertence a nenhuma Collection. Uma futura associação contextual (ex.: "quero esta Variant para determinado objetivo/Collection") pode ser estudada como Product Behavior ou extensão futura, sem transformar Collection em dona da Wishlist — não permanece como decisão estrutural em aberto desta consolidação.

## C-96 — Independência de Expected Content

**Status:** Aprovada

Wishlist e `Expected Content` (C-42) são independentes. Expected Content responde "o que este Slot espera?" (organizacional, pertence ao Slot); Wishlist responde "qual Variant desejo adquirir?" (intenção pessoal, pertence ao User). Compartilham vocabulário de catálogo, mas a granularidade de C-42 (Card obrigatório + Variant opcional) não é reutilizada como justificativa para a forma de Wishlist.

## C-97 — Independência de Favorite

**Status:** Aprovada

Wishlist e `Favorite` (C-82–C-90) são independentes — válidos em qualquer combinação: Favorite sem Wishlist; Wishlist sem Favorite; ambos; nenhum. A diferença de granularidade entre os dois é intencional: `Favorite → Card` (preferência editorial ampla); `Wishlist → Card Variant` (intenção específica de aquisição).

## C-98 — Núcleo binário V1

**Status:** Aprovada

Wishlist é binária no núcleo V1: a existência da entrada significa "ainda desejo esta combinação". Quantity, priority, grail, ranking, target price, alerts e procurement behavior ficam fora do núcleo V1.

## C-99 — Cardinalidade/duplicidade conceitual

**Status:** Aprovada

Duplicidade conceitual existe apenas quando duas entradas têm a mesma `Card Variant` e a mesma condição de idioma (ambas sem idioma, ou mesmo idioma específico). Combinações diferentes não são duplicidade estrutural — por exemplo, "Variant X + qualquer idioma" e "Variant X + JP" podem coexistir. Eventual aviso ou merge entre entradas sobrepostas é Product Behavior, não regra de domínio.

## C-100 — Condition/grading: fronteira futura

**Status:** Aprovada

Condition e grading não são incorporados a Wishlist nesta rodada. Registra-se apenas a possibilidade futura de refinamentos como condition, raw/graded, grader e grade — somente depois que essas dimensões forem formalmente modeladas em rodada própria. Preserva-se o achado já registrado (ver Bloco complementar Lifecycle & Provenance): há referências textuais a `condition` como dimensão de Physical Card sem C-*/LDM-* correspondente formalizando-a — não corrigido nesta rodada, encaminhado para uma futura subfrente própria, `Collections — Physical Card Condition Modeling`.

## C-101 — Marketplace: fronteira futura, sem dependência estrutural

**Status:** Aprovada

Marketplace pode futuramente consumir Wishlist para matching, sugestões, alerts e oportunidades de compra. Wishlist não depende estruturalmente de Marketplace — sua existência e significado não pressupõem esse módulo, cujos limites permanecem não decididos (ver `ROADMAP.md`).

## C-102 — User scope

**Status:** Aprovada

Wishlist pertence ao `User`. Não pertence a `Collection`, `Inventory` nem a uma `Physical Card` específica.

---

## Bloco complementar — Physical Card Condition (2026-08-30)

Adicionado ao final de `COLLECTIONS-PHYSICAL-CARD-CONDITION-CONSOLIDATION-01`, encerrando a subfrente `Collections — Physical Card Condition conceptual modeling`, conduzida por um memo conceitual (`COLLECTIONS-PHYSICAL-CARD-CONDITION-MODELING-01`) e um complemento de evidência de mercado brasileiro (entregue como `COMPLEMENTO — CONDITION / EVIDÊNCIA DE MERCADO BRASILEIRO`). Nota de divergência sinalizada explicitamente, não aplicada silenciosamente: o pedido de consolidação refere-se a "memos CONDITION-MODELING-01, CONDITION-MODELING-02 e o complemento"; nesta sessão não houve uma rodada entregue literalmente como `CONDITION-MODELING-02` — o complemento de evidência de mercado cumpriu, em conteúdo, o papel equivalente de um refinamento de segunda rodada (evidência de mercado brasileiro, code vs. label, filter semantics), e é tratado aqui como tal. Ambos previamente registrados sem edição de arquivo. Nenhuma decisão de conteúdo nova é introduzida além do que já havia sido explorado nesses dois textos e revisado por Fabrício — este bloco só dá a essas decisões um lugar canônico que antes não existia. C-01–C-102 não são reabertas — em particular, `Lifecycle`/`Provenance` (C-67–C-81, especialmente C-69/C-80/C-81) e `Wishlist` (C-91–C-102, especialmente C-100) permanecem integralmente vigentes. Grading/Certification em detalhe, Damage/Defects, Condition History, Valuation e Wishlist refinement permanecem explicitamente fora de escopo. Achado central desta rodada: a tabela física `card_condition`, já `CONFIRMADO EXECUTADO` em Pricing (Incremento P1, 2026-08-16 — ver `docs/05f-pricing.md`), é reconhecida e ratificada conceitualmente como a referência canônica compartilhada de Condition (C-104), sem propor ou alterar schema nesta rodada.

## C-103 — Condition: definição e entidade-alvo

**Status:** Aprovada

`Condition` é a classificação padronizada do estado físico corrente de uma `Physical Card`, segundo a escala canônica do MMKYU. Pertence exclusivamente à `Physical Card` — nunca a `Card`, `Card Variant`, `Collection`, `Wishlist` ou `Storage`.

## C-104 — Referência canônica ratificada: card_condition

**Status:** Aprovada

Fica ratificado conceitualmente que a referência compartilhada já existente `card_condition` (CONFIRMADO EXECUTADO, Incremento P1 de Pricing, 2026-08-16 — ver `docs/05f-pricing.md`) representa a escala canônica de Condition do MMKYU. Collections não cria uma segunda escala, um segundo vocabulário nem um conceito paralelo de Condition — Physical Card Condition e os mapeamentos de condition de Pricing (`pricing_condition_mapping`) consomem a mesma referência canônica. Nenhuma alteração de schema é proposta ou aplicada nesta rodada.

## C-105 — Escala canônica formalizada

**Status:** Aprovada

A escala canônica pretendida é: MINT, NEAR_MINT, LIGHTLY_PLAYED, MODERATELY_PLAYED, HEAVILY_PLAYED, DAMAGED (mesma ordem e códigos já documentados em `card_condition`, `docs/05f-pricing.md`). A discrepância histórica entre uma validação pós-migration que mencionava 5 registros e a documentação que lista 6 códigos fica registrada como pendência de verificação física (ver Parte D/decisões ainda abertas) — não investigada nem corrigida nesta rodada.

## C-106 — Condition code canônico vs. label localizado

**Status:** Aprovada

O código de Condition (ex.: `NEAR_MINT`) é identidade estável, independente de idioma. O rótulo exibido ao usuário é localizado e traduzido separadamente (ex.: pt-BR "Praticamente Nova", en "Near Mint"). O código interno nunca é amarrado a um rótulo traduzido específico.

## C-107 — Evidência de mercado brasileiro

**Status:** Aprovada

Registra-se como evidência de alinhamento de mercado o vocabulário observado em sites especializados brasileiros (M/Nova, NM/Praticamente Nova, SP-LP/Usada Levemente, MP/Usada Moderadamente, HP/Muito Usada, D/Danificada), que converge semanticamente, em ordem e significado, com a escala canônica do MMKYU (C-105). Abreviações de mercado não se tornam novos códigos canônicos.

## C-108 — Opcionalidade

**Status:** Aprovada

Condition é opcional. Não bloqueia cadastro básico, bulk import nem Ownership Entry (C-70). Ausência de Condition significa "não informada" — não se cria um valor `UNKNOWN` apenas para representar essa ausência.

## C-109 — Classificação declarada, não certificada

**Status:** Aprovada

Condition raw é classificação corrente declarada/registrada — não se assume verificação independente, certificação, inspeção MMKYU ou verdade objetiva garantida. Aplica-se a mesma disciplina de linguagem segura já usada para Provenance (C-76).

## C-110 — Damage/Defects fora do núcleo V1

**Status:** Aprovada

Condition representa classificação global do estado físico. Damage/defects detalhados (whitening, scratches, crease, dent, stains, edge wear, print lines, centering, water damage e outros) não são modelados nesta rodada — permanecem fora do núcleo V1.

## C-111 — Condition × Grading

**Status:** Aprovada

Condition ≠ Grading. Condition é classificação canônica/declarada do estado físico; Grading (C-80) é certificação externa. Nenhum é derivado automaticamente do outro. Não se decide nesta rodada se uma Physical Card atualmente graded mantém Condition corrente, deixa Condition não aplicável, preserva apenas avaliação anterior, ou pode ter ambas simultaneamente — essa aplicabilidade fica para a futura subfrente `Collections — Grading / Certification Domain Modeling`.

## C-112 — Raw/graded não é valor de Condition

**Status:** Aprovada

"Raw vs. graded" não é um valor de Condition. A estrutura desse status pertence a Grading/Certification e, eventualmente, a Protection/Encapsulation (C-56) — não à escala canônica de Condition.

## C-113 — Sem histórico no núcleo V1

**Status:** Aprovada

O núcleo V1 mantém apenas Current Condition, sem Condition History. Reafirma a exclusão já registrada em C-68/C-81 (Lifecycle & Provenance). Eventos materiais futuros de mudança de condition podem ser avaliados posteriormente em rodada própria de Lifecycle.

## C-114 — Independência de identidade e de outras dimensões

**Status:** Aprovada

Mudança de Condition não altera: a identidade da Physical Card (reafirma C-47); Card Variant; ownership; Collection Allocation; Slot Assignment; Favorite; Wishlist; Storage; Custody.

## C-115 — Independência de idioma

**Status:** Aprovada

Condition é independente de idioma. Idioma descreve o exemplar (impressão/localização); Condition classifica seu estado físico corrente — eixos ortogonais.

## C-116 — Independência de Storage/Custody

**Status:** Aprovada

Mudanças de Storage ou Custody não alteram Condition por regra estrutural. Danos reais podem ocorrer no mundo físico (manuseio, transporte, condições de armazenamento), mas isso é causalidade de mundo real, não dependência estrutural entre os conceitos.

## C-117 — Relação com Valuation

**Status:** Aprovada

Condition pode futuramente ser input de Valuation, mas Condition ≠ Price e Condition ≠ Valuation. Não se inclui fator fixo de desconto/preço dentro de Condition — precedente já estabelecido pelo próprio Pricing V1 (`05f-pricing.md`), que rejeitou explicitamente embutir esse fator em `card_condition`. Pricing V1 não é reaberto por esta decisão.

## C-118 — Filter semantics não é novo valor de Condition

**Status:** Aprovada

Expressões como "NM ou superior" / "Near Mint or better" não são valores adicionais de Condition — são semântica de filtro/comparação baseada na ordenação da escala canônica (`condition_order`, já existente em `card_condition`). UX e mecanismo de filtro não são modelados nesta rodada.

## C-119 — Wishlist permanece sem Condition

**Status:** Aprovada

Wishlist V1 (C-91–C-102) permanece sem Condition. A possibilidade futura de refinamento de Wishlist por Condition (já antecipada em C-100) só poderá ser avaliada em rodada própria, sem alterar C-91–C-102 nesta consolidação.

## C-120 — Escopo mínimo V1

**Status:** Aprovada

O escopo mínimo V1 de Condition é: Current Condition opcional; escala canônica compartilhada (`card_condition`); código independente de idioma, com label localizado; sem defects detalhados; sem histórico; sem evidence levels; sem obrigatoriedade de preenchimento; sem derivação automática a partir de Grade.

---

# PARTE B — ESTADO CANÔNICO CONSOLIDADO

## B.1 — Responsabilidades do domínio

### Collection

Responde:

> Para qual objetivo colecionável este exemplar foi destinado?

Collection organiza posse; não representa desejo nem localização física.

### Physical Card

Responde:

> Qual é a identidade permanente deste exemplar físico individual?

Cada exemplar físico possui identidade própria e permanente, independente de estar, neste momento, sob ownership corrente rastreado pelo MMKYU (ver C-47/C-48).

### Storage Container

Responde:

> Onde o exemplar está fisicamente armazenado?

Tipos previstos:

- Binder;
- ETB;
- Storage Box;
- outros.

### Wishlist

Responde:

> O que o usuário deseja possuir?

Itens ainda não possuídos não pertencem à Collection.

---

## B.2 — Cardinalidades conceituais principais

```text
Game
  1
  │
  └── 0..N Collection

Collection
  ├── exatamente 1 Owner
  ├── 0..N Shared Users
  ├── 0..1 universo de referência
  ├── exatamente 1 Default Storage Container
  └── 0..N Physical Cards (alocação)

Physical Card
  ├── 0..1 Collection (alocação)
  └── 0..1 Storage Container

Storage Container
  └── 0..N Physical Cards
```

Observação: o `Default Storage Container` não determina a localização real de todos os itens.

---

## B.3 — Tipos de comportamento de Collection

### Curadoria aberta

- sem universo total conhecido;
- sem estado de completude;
- conteúdo definido pelo usuário.

### Universo estático

Exemplo: Card Set.

- universo estável;
- progresso calculável;
- referência consolidada após primeira Physical Card alocada.

### Universo dinâmico

Exemplo: Pokédex.

- fonte canônica pode crescer;
- Collection existente não expande automaticamente;
- usuário aprova a expansão do escopo.

---

## B.4 — Completude

### Card Set convencional

Uma Card é satisfeita quando existe ao menos uma `Physical Card` válida e alocada correspondente a qualquer `Card Variant` daquela Card.

### Master Set

Cada `Card Variant` requerida constitui uma posição individual de completude.

### Pokédex

Cada posição representa um Pokémon canônico.

A Card utilizada deve representar aquele Pokémon.

### Curadoria aberta

Não possui completude.

---

## B.5 — Regras invariantes

1. Uma Collection pertence a exatamente um Game.
2. Game é imutável.
3. Uma Physical Card é alocada a no máximo uma Collection por vez.
4. Uma Physical Card pode existir sem estar alocada a uma Collection.
5. Uma Physical Card pode existir sem Storage Container.
6. Storage e Collection são dimensões independentes.
7. Um Storage Container pode conter itens de diferentes Collections.
8. Um Storage Container pode conter itens sem Collection.
9. A referência de uma Collection é única.
10. A referência é consolidada após a primeira Physical Card alocada.
11. Remover todos os itens não desbloqueia a referência.
12. Set convencional e Master Set podem ser alternados posteriormente.
13. Apenas itens efetivamente alocados contam para progresso.
14. Duplicatas são permitidas.
15. Duplicatas não inflam progresso.
16. Layout físico não determina ordem lógica.
17. Idiomas diferentes são permitidos.
18. Nome não precisa ser único.
19. Collection nasce privada.
20. Collection pode ser pública para visualização.
21. Visibilidade pública não concede edição.
22. Collection pode ser compartilhada com permissões por usuário.
23. Ownership pode ser transferido apenas para membro compartilhado existente.
24. Collection só pode ser excluída se estiver sem Physical Cards alocadas.
25. ACTIVE e ARCHIVED são os únicos estados explícitos.
26. ARCHIVED é somente leitura para operações colecionáveis.
27. Toda Collection possui Default Storage Container.

---

# PARTE C — DIRETRIZES DE UX REGISTRADAS

Estas diretrizes não fazem parte diretamente da entidade `Collection`, mas foram descobertas durante a modelagem e devem ser preservadas.

## C.1 — Visual Collection Space / Carousel

A tela principal do acervo deverá privilegiar experiência visual imersiva.

O Carousel pode conter diferentes `Storage Containers`:

```text
Binder → Binder → ETB → Storage Box → Binder
```

Características desejadas:

- navegação horizontal;
- objetos visualmente espaçados;
- sensação de flutuação;
- escala progressiva;
- container central em destaque;
- redução de escala nas extremidades;
- profundidade/perspectiva;
- transição para abertura/interação do container.

A interface não deve ser reduzida a uma grade convencional de cards administrativos.

---

## C.2 — Binder

Binder deverá futuramente reproduzir sua estrutura física interna.

Previsto:

- páginas;
- slots;
- placeholders;
- organização livre;
- elementos visuais personalizados.

Um slot não precisa obrigatoriamente conter uma `Physical Card`.

---

## C.3 — ETB / Storage Box

Quando um container possuir itens de diferentes Collections, a UX deverá suportar separadores/divisórias visuais.

---

## C.4 — One-Click / Bulk Registration

Cadastro em massa é requisito crítico de produto.

O sistema deve ser projetado para permitir operações próximas de:

```text
Adicionar Card
→ selecionar variante
→ informar quantidade
→ utilizar Default Storage quando aplicável
```

A arquitetura não deve exigir interação individual exaustiva para centenas ou milhares de cartas.

---

# PARTE D — ENTIDADES DESCOBERTAS PARA MODELAGEM POSTERIOR

As seguintes entidades/conceitos foram identificados durante a modelagem de Collection, mas **não foram modelados em profundidade neste documento**:

- `Collection Item` / `Inventory Item` — resolvido: ambos são nomes anteriores, superseded (ver Bloco complementar `Physical Card & Inventory`, C-47/C-48, 2026-08-30). A identidade física vigente do exemplar é `Physical Card`; sua participação patrimonial corrente é agregada por `Inventory`. Não são entidades próprias paralelas — ver `logical-model.md`, LDM-23 (revisado).
- `Storage Container` — resolvido conceitualmente em 2026-08-30 (Bloco complementar `Storage`, C-55–C-66): definição, fronteira com Protection, ownership mediado por Inventory, hierarquia opcional, fronteira de Inventory, capacidade (conceito, não fórmula), remoção e transferência (Bulk Card Transfer, Reparent). Modelagem física (SQL, capacidade rígida por tipo, UX detalhada) permanece não iniciada.
- `Binder` — tipo de Storage Container (C-17, reafirmado por C-55); estrutura interna (páginas/pockets) permanece não modelada.
- ~~`Binder Page`~~ — resolvido em 2026-08-30 pelo Bloco complementar acima (C-39, `Page`).
- ~~`Binder Slot`~~ — resolvido em 2026-08-30 pelo Bloco complementar acima (C-41, `Slot`).
- `Placeholder` — parcialmente resolvido: o comportamento de "posição reservada sem carta" está coberto por `Expected Content` (C-42); placeholders puramente visuais/decorativos permanecem não modelados.
- `ETB / Storage Box Layout` — capacidade/estrutura interna permanece não modelada (C-62 trata apenas o conceito de capacidade, não a fórmula).
- `Storage Divider` — permanece não modelado.
- `Protection / Encapsulation` — reconhecida como dimensão futura distinta de Storage (C-56), explicitamente não modelada nesta rodada (sleeve, toploader, one-touch, slab de grading).
- `Favorite` — resolvido conceitualmente em 2026-08-30 (Bloco complementar `Favorite`, C-82–C-90): definição e entidade-alvo (`Card`, nunca `Card Variant`/`Physical Card`), pertencimento ao `User` transversal a Collections, independência de ownership e de Collection, caráter binário, cardinalidade conceitual, fronteira com Wishlist. Modelagem física (SQL, tabelas, UUID, RLS) permanece não iniciada.
- `Wishlist` — resolvido conceitualmente em 2026-08-30 (Bloco complementar `Wishlist`, C-91–C-102): definição e alvo obrigatório (`Card Variant`, não `Card`), idioma como refinamento opcional, independência de ownership/completion/Expected Content/Favorite, núcleo binário, cardinalidade/duplicidade, e fronteiras futuras (condition/grading, Marketplace). Modelagem física (SQL, tabelas, UUID, RLS) permanece não iniciada.
- `Physical Card Condition` — resolvido conceitualmente em 2026-08-30 (Bloco complementar `Physical Card Condition`, C-103–C-120): definição e entidade-alvo (`Physical Card`), ratificação da referência canônica compartilhada `card_condition` (sem alteração de schema), escala formalizada, code vs. label localizado, evidência de mercado brasileiro, opcionalidade, linguagem declarada/não certificada, fronteira com Damage/Defects e com Grading (aplicabilidade a cards graded deixada para futura subfrente `Grading / Certification Domain Modeling`), independência de identidade/idioma/Storage/Custody/Wishlist, relação futura com Valuation sem reabrir Pricing, e semântica de filtro ("NM ou superior") sem novo valor de escala. Pendência registrada: discrepância entre "5 linhas" (validação) e 6 códigos documentados em `card_condition` — verificação física não realizada nesta rodada. Modelagem física (SQL, tabelas, UUID, RLS) permanece não iniciada.
- `Pokémon / Subject Reference`
- histórico/auditoria operacional detalhada
- engine de progresso
- permissões detalhadas de membros

Cada uma deverá possuir seu próprio ciclo de modelagem.

---

# PARTE E — GATE ARQUITETURAL

A modelagem conceitual de `Collection` foi submetida a revisão integral após as decisões C-01 a C-37.

Foram identificadas e corrigidas durante o processo:

- separação entre Collection e Storage;
- revisão da C-04;
- evolução/superação da C-10;
- revisão da C-17;
- absorção da C-18 pela C-36;
- consolidação de Game em C-35;
- consolidação de nome em C-34;
- definição operacional de ARCHIVED em C-37.

## Resultado

**GATE ARQUITETURAL: APROVADO**

A entidade `Collection` está conceitualmente fechada e apta para iniciar a fase de **Logical Data Model — LDM**.

---

# PARTE F — GOVERNANÇA PARA A PRÓXIMA FASE

As decisões de modelagem lógica deverão utilizar a nomenclatura:

```text
LDM-01
LDM-02
LDM-03
...
```

Nenhuma decisão LDM pode:

- contradizer silenciosamente uma decisão C-xx;
- alterar uma regra conceitual sem registrar revisão explícita;
- antecipar implementação SQL antes do fechamento do modelo lógico.

Antes do handoff final para implementação, o modelo deverá ser reconciliado com a documentação canônica do repositório `project-mimikyu`.

---

**Fim do documento**

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Documento produzido no repositório de modelagem paralelo `mimikyu-modelagem-de-dados`, FECHADO/APROVADO em 2026-08-10 (C-01 a C-37). |
| 1.1 | Incorporado a `project-mimikyu` (2026-08-28, pedido explícito de Fabrício) em `docs/domain-modeling/collections/`, como fonte canônica para o domínio conceitual de `Collection`, substituindo `ADR-013`/`ADR-014` para este fim. Nenhuma decisão alterada — apenas cabeçalho e nota de incorporação adicionados. |
| 1.2 | **Bloco complementar Collection Layout, 2026-08-30.** Adicionadas C-38 a C-46, consolidando dez rodadas de modelagem conceitual (`COLLECTIONS-LAYOUT-MODELING-01` a `-10`) sobre `Collection Layout`/`Page`/`Grid Configuration`/`Slot`/`Expected Content`/`Lock`/`Slot Assignment`/`Bandeja`/`Layout Region`. C-01–C-37 não reabertas. Parte D atualizada: `Binder Page` e `Binder Slot` resolvidos, `Placeholder` parcialmente resolvido. Ver `checkpoint-2026-08-30.md` para o diagnóstico de reconciliação completo. |
| 1.3 | **Reconciliação terminológica Physical Card, 2026-08-30 (`COLLECTIONS-PHYSICAL-CARD-RECONCILIATION-02`).** Convergência de duas gerações de terminologia nunca antes reconciliadas neste documento: "Collection Item" (usado em todo o núcleo C-01–C-37 e Partes B/D, nunca migrado durante a incorporação de 2026-08-28) e "Inventory Item" (usado no bloco C-38–C-46) — ambos substituídos por `Physical Card` em todo o texto normativo. Cada ocorrência revisada semanticamente, não apenas trocada por substituição literal: onde o texto original dizia "pertence à Collection", a formulação foi corrigida para "é alocada à Collection" (B.5 #3, C-03, C-14, C-26), preservando a distinção já estabelecida entre alocação colecionável e posse física. Adicionado bloco complementar C-47–C-48, formalizando pela primeira vez em C-*/LDM-* a identidade `Physical Card` e o agregado `Inventory` (previamente registrados apenas em `checkpoint-2026-08-28.md` e em quatro memos de modelagem — `COLLECTIONS-INVENTORY-MODELING-01` a `-04` — nunca promovidos a C-*/LDM-*). C-48 formaliza a regra de participação em Inventory ("ownership corrente"), substituindo a decisão de trabalho nunca formalizada "I3". C-01–C-46 não reabertas em conteúdo — apenas em nomenclatura e, onde apontado, na precisão do verbo/relação. |
| 1.4 | **Bloco complementar Custody & Availability, 2026-08-30** (`COLLECTIONS-CUSTODY-AVAILABILITY-CONSOLIDATION-01`). Adicionadas C-49 a C-54, formalizando pela primeira vez em C-*/LDM-* as decisões do memo conceitual `COLLECTIONS-INVENTORY-MODELING-05` (Custody/Possession/Availability), previamente registrado sem editar nenhum arquivo. Termo canônico `Custody` adotado (não `Possession`); `Custodian` preservado como distinção conceitual, sem entidade própria criada nesta rodada. A última frase de C-48 recebeu atualização de referência cruzada (aponta agora para C-49–C-54 em vez do memo `COLLECTIONS-INVENTORY-MODELING-03`) — a regra substantiva de cardinalidade de Inventory em C-48 não foi alterada. C-01–C-48 não reabertas em conteúdo. Storage detalhado permanece OPEN, fora do escopo deste bloco. |
| 1.5 | **Bloco complementar Storage, 2026-08-30** (`COLLECTIONS-STORAGE-CONSOLIDATION-01`), encerrando a subfrente `Collections — Storage conceptual modeling`. Adicionadas C-55 a C-66, formalizando pela primeira vez em C-*/LDM-* as decisões dos memos `COLLECTIONS-STORAGE-MODELING-01`/`-02` e da rodada de correção sobre remoção/hierarquia (todos previamente registrados sem editar arquivo): definição de Storage/Storage Container e fronteira com Protection (critério de endereçabilidade, C-56); ownership de Storage Container mediado por Inventory (C-57, evitando repetir o padrão SUPERSEDED de LDM-25); cardinalidade e independência de Physical Card × Storage frente a ownership/Collection Allocation/Slot Assignment/completion (C-58); existência vazia, independência de Collection e caráter corrente, não histórico (C-59); hierarquia opcional entre Storage Containers com regra de container-folha (C-60); fechamento de Storage cross-Inventory como não suportado, incluindo a regra de mesmo Inventory entre parent/child (C-61); capacidade como conceito opcional/informativo/dependente de tipo, distinto de Grid Configuration de Layout (C-62); remoção condicionada a vazio estrutural (zero Physical Cards e zero containers filhos), sem cascade (C-63); as duas operações de transferência, Bulk Card Transfer (C-64) e Reparent Storage Container (C-65); e a semântica de Default Storage sob hierarquia (C-66, sem reabrir C-36). Parte D atualizada: `Storage Container` e `Binder` marcados como conceitualmente resolvidos; `ETB / Storage Box Layout` e `Storage Divider` permanecem não modelados; adicionado `Protection / Encapsulation` como dimensão futura reconhecida, não modelada. C-01–C-54 não reabertas em conteúdo. Protection/Encapsulation, histórico de Storage e modelagem física (SQL, capacidade rígida, UX) permanecem fora de escopo. |
| 1.6 | **Bloco complementar Physical Card Lifecycle & Provenance, 2026-08-30** (`COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-CONSOLIDATION-01`), encerrando a subfrente `Collections — Physical Card Lifecycle / Provenance conceptual modeling`. Adicionadas C-67 a C-81, formalizando pela primeira vez em C-*/LDM-* as decisões dos memos `COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-MODELING-01`/`-02` (ambos previamente registrados sem editar arquivo): definição de Lifecycle e permanência de identidade (C-67); Provenance como subconjunto de Lifecycle, com exclusões explícitas — não é Audit Log, histórico de Storage, histórico de condition, Pricing nem Valuation History (C-68); critério Current State vs. Historical Event (C-69); espinha dorsal patrimonial de três formas — Ownership Entry (C-70), Ownership Transfer como fato único e atômico, sem hiato (C-71), Ownership Exit (C-72) — com motivo qualificando o evento, nunca criando tipo estrutural próprio (C-73); Ownership Episode como ferramenta conceitual, sem entidade própria (C-74); fronteira central entre Physical Card Provenance e Owner/Transaction Private Data, com dados privados de um episódio nunca herdados automaticamente pelo owner seguinte (C-75); linguagem segura de evidência/verificação — "registrada/rastreada", nunca "verificada/certificada" (C-76); Transfer Integrity com três consequências paralelas e independentes sobre Collection Allocation/Slot Assignment/Storage, corrigindo uma formulação anterior que sugeria dependência causal entre elas (C-77); confirmação de que Custody permanece independente de ownership mesmo após Exit, corrigindo uma recomendação anterior que a levava a "não aplicável" (C-78, sem alterar C-49–C-54); núcleo mínimo de Lifecycle para V1 — Entry/Transfer/Exit automáticos, sem histórico de Loan/LOST/Grading (C-79); fechamento mínimo de Grading, sem workflow (C-80); confirmação de que Valuation/Pricing History não fazem parte de Provenance, sem reabrir Pricing V1 (C-81, reafirma C-68). C-01–C-66 não reabertas em conteúdo — C-49–C-54 (Custody/Availability) permanecem integralmente vigentes. Audit Log transversal, permissões detalhadas, evidence levels, workflow de grading, histórico de Loan/LOST/Recovery, histórico detalhado de condition, Pricing e Valuation permanecem explicitamente fora de escopo. |
| 1.7 | **Bloco complementar Favorite, 2026-08-30** (`COLLECTIONS-FAVORITE-CONSOLIDATION-01`), encerrando a subfrente `Collections — Favorite conceptual modeling`. Adicionadas C-82 a C-90, formalizando pela primeira vez em C-*/LDM-* as decisões do memo `COLLECTIONS-FAVORITE-MODELING-01` (previamente registrado sem editar arquivo): definição e entidade-alvo — Favorite referencia exclusivamente `Card`, nunca `Card Variant`/`Physical Card`/Collection Allocation/Slot Assignment/Storage (C-82); pertencimento ao `User`, transversal a todas as Collections, independente do papel do User (Owner/Member) e sem relação com `Inventory` (C-83); independência de ownership (C-84); independência de Collection — completion, Collection Allocation, canonical ordering, Layout e Slot Assignment (C-85); caráter binário, sem score/rating/prioridade/níveis/ranking (C-86); cardinalidade conceitual, um Favorite por par User×Card (C-87); fronteira Favorite vs. Wishlist, independentes e coexistentes (C-88); cada Card como identidade editorial própria por Set, sem herança automática entre impressões do mesmo Pokémon/personagem (C-89); catalog lifecycle (hard delete/deprecation) não modelado (C-90). Parte D atualizada: `Favorite` marcado como conceitualmente resolvido. C-01–C-81 não reabertas em conteúdo — Custody/Availability (C-49–C-54), Storage (C-55–C-66) e Lifecycle/Provenance (C-67–C-81) permanecem integralmente vigentes. Wishlist em profundidade, `Pokémon`/`Subject Reference`, ranking/grail, recomendações e notificações permanecem explicitamente fora de escopo. |
| 1.8 | **Bloco complementar Wishlist, 2026-08-30** (`COLLECTIONS-WISHLIST-CONSOLIDATION-01`), encerrando a subfrente `Collections — Wishlist conceptual modeling`. Adicionadas C-91 a C-102, formalizando pela primeira vez em C-*/LDM-* as decisões dos memos `COLLECTIONS-WISHLIST-MODELING-01`/`-02` (ambos previamente registrados sem editar arquivo; direção vigente é a do `-02`, que corrigiu a granularidade de alvo proposta no `-01` antes de qualquer consolidação — sem supersessão de documento canônico): definição e alvo obrigatório `Card Variant`, não `Card` (C-91); idioma como refinamento opcional (C-92); independência de ownership, sem remoção automática por aquisição, múltiplas cópias desejadas válidas sem quantity (C-93); independência de completion — Wishlist ≠ Collection Missing, estende C-19 (C-94); sem vínculo estrutural com Collection, associação contextual futura como Product Behavior (C-95); independência de Expected Content, granularidade de C-42 não reutilizada como justificativa (C-96); independência de Favorite, diferença de granularidade (Card vs. Card Variant) intencional (C-97); núcleo binário V1, sem quantity/priority/grail/ranking/price target/alerts/procurement (C-98); cardinalidade/duplicidade conceitual por combinação exata de Variant+idioma (C-99); condition/grading como fronteira futura, achado documental preservado, encaminhado para futura subfrente `Collections — Physical Card Condition Modeling` (C-100); Marketplace como fronteira futura sem dependência estrutural (C-101); Wishlist pertence ao User, não a Collection/Inventory/Physical Card específica (C-102). C-01–C-90 não reabertas em conteúdo — Favorite (C-82–C-90) permanece integralmente vigente. Quantity, priority/grail, price target, Marketplace, condition e grading permanecem explicitamente fora de escopo. |
| 1.9 | **Bloco complementar Physical Card Condition, 2026-08-30** (`COLLECTIONS-PHYSICAL-CARD-CONDITION-CONSOLIDATION-01`), encerrando a subfrente `Collections — Physical Card Condition conceptual modeling`, aberta pelo memo `COLLECTIONS-PHYSICAL-CARD-CONDITION-MODELING-01` e por um complemento de evidência de mercado brasileiro (ambos previamente registrados sem editar arquivo; nota de divergência sinalizada explicitamente — o pedido de consolidação referenciou "MODELING-02", rodada não entregue literalmente sob esse nome nesta sessão, cujo conteúdo equivalente foi coberto pelo complemento). Adicionadas C-103 a C-120: definição e entidade-alvo exclusivo `Physical Card` (C-103); ratificação conceitual da referência canônica compartilhada já existente e `CONFIRMADO EXECUTADO` `card_condition` (Incremento P1 de Pricing, 2026-08-16), sem criar escala/vocabulário/conceito paralelo e sem alterar schema (C-104); escala canônica formalizada — MINT/NEAR_MINT/LIGHTLY_PLAYED/MODERATELY_PLAYED/HEAVILY_PLAYED/DAMAGED, com discrepância histórica de contagem (5 vs. 6) registrada como pendência de verificação física, não investigada (C-105); code canônico independente de idioma vs. label localizado (C-106); evidência de convergência semântica do vocabulário de mercado brasileiro, sem gerar novos códigos canônicos (C-107); opcionalidade, sem valor `UNKNOWN` para representar ausência (C-108); classificação declarada/registrada, não certificada, mesma disciplina de linguagem segura de C-76 (C-109); Damage/Defects detalhados fora do núcleo V1 (C-110); fronteira Condition × Grading, coexistência sem derivação automática, aplicabilidade a cards graded deixada para futura subfrente `Grading / Certification Domain Modeling` (C-111); "raw/graded" não é valor de Condition (C-112); sem histórico no núcleo V1, reafirma C-68/C-81 (C-113); independência de identidade da Physical Card e de Card Variant/ownership/Collection Allocation/Slot Assignment/Favorite/Wishlist/Storage/Custody (C-114); independência de idioma (C-115); independência estrutural de Storage/Custody (C-116); relação futura com Valuation sem reabrir Pricing, precedente já estabelecido em `05f-pricing.md` (C-117); semântica de filtro ("NM ou superior") apoiada em `condition_order`, sem novo valor de Condition, sem modelar UX (C-118); Wishlist V1 permanece sem Condition, sem reabrir C-91–C-102 (C-119); escopo mínimo V1 consolidado (C-120). Parte D atualizada: `Physical Card Condition` marcado como conceitualmente resolvido. C-01–C-102 não reabertas em conteúdo — Lifecycle/Provenance (C-67–C-81) e Wishlist (C-91–C-102) permanecem integralmente vigentes. Grading/Certification em detalhe, Damage/Defects, Condition History, Valuation e Wishlist refinement permanecem explicitamente fora de escopo. Nenhuma migration ou alteração de schema proposta ou aplicada. |
