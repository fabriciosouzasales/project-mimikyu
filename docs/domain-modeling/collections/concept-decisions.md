# Collection — Concept Decisions

| Campo | Valor |
|--------|-------|
| **Documento** | Collection — Concept Decisions (Modelagem Conceitual) |
| **Arquivo** | `docs/domain-modeling/collections/concept-decisions.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` como fonte canônica em 2026-08-28 (pedido explícito de Fabrício). |
| **Decision Register** | C-01 a C-37 (núcleo Collection); C-38 a C-46 (bloco complementar Collection Layout, 2026-08-30); C-47 a C-48 (bloco complementar Physical Card & Inventory, 2026-08-30); C-49 a C-54 (bloco complementar Custody & Availability, 2026-08-30) |
| **Status** | FECHADA / APROVADA PARA MODELAGEM LÓGICA (núcleo); bloco complementar de Layout também Aprovado; bloco complementar Physical Card & Inventory também Aprovado; bloco complementar Custody & Availability também Aprovado |
| **Escopo** | Modelagem conceitual da entidade `Collection` (colecionador), desde 2026-08-30 de `Collection Layout`/`Page`/`Slot`, desde 2026-08-30 da identidade `Physical Card` e do agregado `Inventory`, e desde 2026-08-30 das dimensões `Custody`/`Custodian`/`Availability` — não contém SQL nem modelo físico. |
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
- `Storage Container`
- `Binder`
- ~~`Binder Page`~~ — resolvido em 2026-08-30 pelo Bloco complementar acima (C-39, `Page`).
- ~~`Binder Slot`~~ — resolvido em 2026-08-30 pelo Bloco complementar acima (C-41, `Slot`).
- `Placeholder` — parcialmente resolvido: o comportamento de "posição reservada sem carta" está coberto por `Expected Content` (C-42); placeholders puramente visuais/decorativos permanecem não modelados.
- `ETB / Storage Box Layout`
- `Storage Divider`
- `Wishlist`
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
