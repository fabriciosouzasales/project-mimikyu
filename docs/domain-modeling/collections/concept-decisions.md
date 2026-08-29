# Collection — Concept Decisions

| Campo | Valor |
|--------|-------|
| **Documento** | Collection — Concept Decisions (Modelagem Conceitual) |
| **Arquivo** | `docs/domain-modeling/collections/concept-decisions.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` como fonte canônica em 2026-08-28 (pedido explícito de Fabrício). |
| **Decision Register** | C-01 a C-37 |
| **Status** | FECHADA / APROVADA PARA MODELAGEM LÓGICA |
| **Escopo** | Modelagem conceitual da entidade `Collection` (colecionador) — não contém SQL nem modelo físico. |
| **Documentos Relacionados** | `../../04-domain-model.md` (seções Collection/Collection Entry/Collection Item — ver nota de superação), `adr/ADR-013-collection-item-identity-model.md` e `adr/ADR-014-collection-and-collection-entry-model.md` (ambas **Substituídas** por este documento e por `logical-model.md`), `logical-model.md`, `pkmnbindr-benchmark.md`, `checkpoint-2026-08-28.md`. |

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

Compatibilidade com a Collection torna o exemplar elegível, mas não determina automaticamente seu pertencimento.

A intenção pode ser expressa:

- individualmente;
- por operações em massa.

**Princípio:** explícito não significa manual um a um.

O produto deve suportar operações em massa para evitar inviabilidade de uso em acervos com centenas ou milhares de cartas.

---

## C-04 — Exclusividade colecionável e localização física

**Status:** Revisada e Aprovada

Cada `Collection Item` pode participar de zero ou uma `Collection` por vez.

Essa associação representa sua alocação colecionável, **não sua localização física**.

Um mesmo exemplar não pode contribuir simultaneamente para múltiplas Collections.

`Collection Items` sem Collection continuam existindo normalmente e podem estar armazenados em locais físicos independentes, como ETBs, caixas ou outros recipientes.

---

## C-05 — Vínculo obrigatório com Game

**Status:** Aprovada; posteriormente complementada pela C-35

Toda Collection pertence obrigatoriamente a um único `Game`.

Todos os `Collection Items` alocados nela devem pertencer ao mesmo Game.

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

Compartilhamento da Collection não altera a propriedade física dos `Collection Items`.

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

O universo de referência pode ser alterado enquanto a Collection **nunca tiver recebido um `Collection Item`**.

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

Ela não transfere automaticamente a propriedade dos `Collection Items`.

A Collection deve possuir exatamente um Owner em todos os momentos.

---

## C-13 — Exclusão

**Status:** Aprovada

Uma Collection pode ser excluída somente quando não possuir nenhum `Collection Item` associado.

A exclusão nunca remove, desaloca ou modifica automaticamente `Collection Items`.

Caso existam itens associados, o usuário deve:

- removê-los;
- realocá-los;
- ou arquivar a Collection.

---

## C-14 — Idiomas

**Status:** Aprovada

Uma Collection pode conter `Collection Items` em diferentes idiomas.

Idioma não constitui, por si só, restrição de pertencimento à Collection.

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

Uma Collection pode ter seus `Collection Items` distribuídos entre zero, um ou vários `Storage Containers`.

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

O progresso de uma Collection é calculado exclusivamente a partir dos `Collection Items` efetivamente alocados àquela Collection.

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

Uma Collection pode conter múltiplos `Collection Items` correspondentes à mesma `Card` e inclusive à mesma `Card Variant`.

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

A alteração pode ocorrer mesmo após existirem `Collection Items`.

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

Mas não determinam a posição física dos `Collection Items`.

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

## C-26 — Collection Item sem Storage

**Status:** Aprovada

Um `Collection Item` pode existir sem `Storage Container`.

A localização física é opcional e pode ser definida ou alterada posteriormente.

A ausência de Storage não impede pertencimento à Collection nem contribuição para completude.

---

## C-27 — Compartilhamento e Storage

**Status:** Aprovada

O compartilhamento de uma Collection propaga automaticamente aos usuários compartilhados o acesso aos `Storage Containers` utilizados por seus `Collection Items`, somente no contexto necessário para visualizar ou operar aquela Collection.

Isso não representa compartilhamento irrestrito do Storage Container.

Itens:

- de outras Collections;
- ou sem Collection;

permanecem protegidos por suas próprias regras.

As permissões nesse contexto derivam da Collection.

---

## C-28 — Movimentação física

**Status:** Aprovada

Mover um `Collection Item` entre `Storage Containers` é independente de sua associação com a Collection.

Alterar localização física não modifica automaticamente:

- alocação colecionável;
- elegibilidade;
- contribuição para completude.

---

## C-29 — Realocação entre Collections

**Status:** Aprovada

Um `Collection Item` pode ser:

- realocado entre Collections;
- removido de uma Collection e ficar sem Collection.

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

Em Collections com universo de referência, o sistema valida apenas se o `Collection Item` pertence ao universo aplicável.

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

Uma Collection nunca pode conter `Collection Items` de Games diferentes.

Se uma Collection vazia for criada no Game incorreto, deve ser excluída e recriada.

---

## C-36 — Default Storage Container

**Status:** Aprovada

Toda Collection possui um `Default Storage Container`, obrigatoriamente definido em sua criação.

Ele representa o destino físico padrão sugerido para novos `Collection Items` associados à Collection.

Pode ser alterado pelo Owner a qualquer momento.

Não estabelece exclusividade.

Cada `Collection Item` mantém sua própria localização física independente e pode estar:

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

- `Collection Items`;
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

# PARTE B — ESTADO CANÔNICO CONSOLIDADO

## B.1 — Responsabilidades do domínio

### Collection

Responde:

> Para qual objetivo colecionável este exemplar foi destinado?

Collection organiza posse; não representa desejo nem localização física.

### Collection Item

Responde:

> Qual exemplar físico o usuário efetivamente possui?

Cada exemplar físico possui identidade própria.

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
  └── 0..N Collection Items

Collection Item
  ├── 0..1 Collection
  └── 0..1 Storage Container

Storage Container
  └── 0..N Collection Items
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
- referência consolidada após primeiro Collection Item.

### Universo dinâmico

Exemplo: Pokédex.

- fonte canônica pode crescer;
- Collection existente não expande automaticamente;
- usuário aprova a expansão do escopo.

---

## B.4 — Completude

### Card Set convencional

Uma Card é satisfeita quando existe ao menos um `Collection Item` válido correspondente a qualquer `Card Variant` daquela Card.

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
3. Um Collection Item pertence a no máximo uma Collection.
4. Um Collection Item pode existir sem Collection.
5. Um Collection Item pode existir sem Storage Container.
6. Storage e Collection são dimensões independentes.
7. Um Storage Container pode conter itens de diferentes Collections.
8. Um Storage Container pode conter itens sem Collection.
9. A referência de uma Collection é única.
10. A referência é consolidada após o primeiro Collection Item.
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
24. Collection só pode ser excluída se estiver sem Collection Items.
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

Um slot não precisa obrigatoriamente conter um `Collection Item`.

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

- `Collection Item`
- `Storage Container`
- `Binder`
- `Binder Page`
- `Binder Slot`
- `Placeholder`
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
