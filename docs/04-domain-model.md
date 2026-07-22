# Domain Model

| Campo | Valor |
|--------|-------|
| **Documento** | Domain Model |
| **Arquivo** | `docs/04-domain-model.md` |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Definir o modelo conceitual do domínio do Project Mimikyu antes da modelagem lógica e física. |
| **Escopo** | Modelo conceitual do domínio. Não contém SQL nem detalhes físicos de implementação. |
| **Dependências** | `00-project-charter.md`, `02-architecture-principles.md`, `standards/STD-002-domain-modeling.md` |
| **Documentos Relacionados** | `adr/ADR-003-multi-game-architecture.md`, `adr/ADR-004-set-identity.md`, `adr/ADR-005-catalog-language-model.md`, `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `architecture/ubiquitous-language.md` |

---

# Purpose

Este documento descreve os conceitos fundamentais utilizados pelo sistema.

Seu objetivo é definir o domínio do problema antes da implementação no banco de dados.

Este documento não contém SQL nem detalhes físicos de implementação.

---

# Core Concepts

Os seguintes conceitos compõem o núcleo do domínio do sistema.

- Collection
- Expansion
- Card Set
- Card
- Card Variant
- Inventory Item
- Storage Location
- Game
- User Collection

---

# Concept Definitions

## Collection

*Documentação pendente.*

---
## Game (Jogo)

### O que é?

Representa um Trading Card Game suportado pelo Project Mimikyu.

Exemplos:

- Pokémon TCG
- Magic: The Gathering
- Disney Lorcana
- One Piece Card Game

---

### O que não é?

Não representa uma coleção, expansão ou conjunto de cartas.

Também não representa um fabricante ou uma empresa.

---

### Qual problema resolve?

Define a raiz do catálogo oficial do sistema.

Todo catálogo pertence obrigatoriamente a um único Game.

---

### Conceitos relacionados

Um Game pode possuir uma ou mais Expansions.

Cada Expansion agrupa seus respectivos Sets.

---

## Expansion (Expansão)

### O que é?

Uma **Expansion (Expansão)** representa um grande ciclo editorial dentro de um **Game (Jogo)**.

Ela estabelece uma identidade cronológica, temática e mecânica que agrupa diversos **Sets (Sets)**.

Pode ser entendida como uma "era" do jogo.

---

### O que não é?

Uma Expansion não representa:

- uma carta;
- um Set;
- uma coleção do usuário;
- um produto comercial.

Sua função é exclusivamente editorial.

---

### Qual problema resolve?

Organiza grandes volumes de conteúdo em agrupamentos editoriais permanentes.

Sem esse conceito, um catálogo precisaria administrar centenas de Sets diretamente sob um único Game, dificultando organização, navegação e evolução do domínio.

---

### Características

Conceitualmente, uma Expansion possui:

- nome;
- ordem cronológica;
- data de início;
- data de encerramento (quando existir);
- identidade visual;
- Game ao qual pertence.

Essas características representam apenas o conceito do domínio e não definem atributos técnicos da implementação.

---

### Relacionamentos

```text
Game
   1
   │
   └── N Expansion

Expansion
   1
   │
   └── N Set
```

Uma Expansion pode conter Sets regulares e Sets especiais.

A característica "especial" pertence ao Set e não altera sua posição na hierarquia editorial.

---

## Set

### O que é?

 **Set (Set)** é uma publicação editorial oficial pertencente a uma **Expansion (Expansão)** e composta por um conjunto ordenado de **Cards (Cartas)**. Possui código editorial textual, nome, ordem cronológica, classificação regular ou especial e limites oficiais de numeração. O Set possui identidade única, independentemente do idioma dos exemplares físicos.

### O que não é?

Um Set não representa:

- uma Card;
- uma Expansion;
- uma tradução específica;
- um produto comercial.

Também não é duplicado por idioma.

---

### Qual problema resolve?

Organiza editorialmente um conjunto oficial de Cards pertencentes a uma Expansion.

Define a identidade oficial utilizada pelo catálogo do sistema.

---

### Características

Conceitualmente um Set possui:

- código editorial;
- nome;
- classificação editorial;
- ordem cronológica;
- Expansion à qual pertence;
- quantidade oficial de cartas do conjunto base;
- quantidade oficial total de cartas publicadas.

---

### Relacionamentos

```text
Game
 1
 │
 └── N Expansion

Expansion
 1
 │
 └── N Set

Set
 1
 │
 └── N Card
```

---

### Idioma

O idioma não faz parte da identidade do Set.

O catálogo considera uma única publicação oficial, independentemente de existirem versões em inglês ou português.

O idioma pertence ao exemplar físico do usuário (Inventory Item).

### Classificação Editorial

Todo Set possui uma classificação editorial.

Inicialmente são reconhecidos dois tipos:

- Regular Set;
- Special Set.

A classificação não altera a natureza da entidade.

Um Set Especial continua sendo um Set.

A classificação editorial é uma característica do Set e não justifica a criação de entidades distintas.

### Código Editorial

O código do Set representa um identificador de negócio.

Ele deve ser tratado como texto e nunca como um valor numérico.

Exemplos válidos:

- ME1
- ME2
- ME2.5
- SV09

O código editorial não define:

- ordem cronológica;
- classificação editorial;
- identidade técnica.

Essas características são independentes.

### Ordem Cronológica

A ordem cronológica de um Set é independente de seu código editorial.

O código pode sugerir uma sequência, mas nunca deve ser interpretado ou convertido para determinar a posição do Set dentro de uma Expansion.

Exemplo:

| Código | Ordem de lançamento |
|--------|---------------------|
| ME1 | 1 |
| ME2 | 2 |
| ME2.5 | 3 |
| ME3 | 4 |

Nesse exemplo, `ME2.5` representa o terceiro Set da Expansion. Seu código não representa o valor matemático `2.5`.

A ordem cronológica é uma característica própria do Set.

---

### Status

Um Set pode possuir um estado dentro do catálogo.

O escopo conceitual inicial reconhece:

- `announced` (anunciado);
- `released` (lançado).

Outros estados somente deverão ser introduzidos quando houver uma necessidade real e uma definição objetiva.

O estado `discontinued` (descontinuado) não faz parte do escopo inicial, pois nem sempre existe uma declaração oficial ou uma data inequívoca de encerramento de um Set.

---

### Visão Conceitual Consolidada

Conceitualmente, um Set possui:

- identidade própria;
- relação com um Game;
- relação com uma Expansion;
- código editorial;
- nome;
- classificação editorial;
- ordem cronológica;
- data de lançamento;
- quantidade oficial do conjunto base;
- quantidade oficial total;
- status.

Essa relação não representa uma definição automática de colunas ou atributos físicos do banco de dados. A modelagem lógica e física será definida posteriormente.

---

## Card (carta)

### O que é?

Uma **Card (Carta)** representa uma posição oficial do catálogo pertencente a um **Set (Set)**.

Ela possui identidade editorial própria e existe independentemente de qualquer exemplar físico pertencente a um usuário.

Exemplo:

```text
Set: ME1 — Megaevolução
Card: Charizard ex
Número: 187
```

Essa Card existe no catálogo independentemente:

- de um usuário possuir uma cópia;
- do idioma em que uma cópia foi impressa;
- da condição física de uma cópia;
- de uma cópia ter sido certificada;
- das formas oficiais de impressão disponíveis.

---

### O que não é?

Uma Card não representa:

- um exemplar físico;
- uma carta pertencente a um usuário;
- uma condição de conservação;
- uma certificação;
- um idioma;
- uma forma de impressão;
- uma localização física;
- uma transação de compra.

Essas informações pertencem a outros conceitos do domínio.

---

### Qual problema resolve?

A Card representa o catálogo editorial oficial.

Ela permite responder, entre outras, às seguintes perguntas:

- quantas posições oficiais existem em um Set;
- quais Cards pertencem a determinado Set;
- quais Cards ainda faltam em uma coleção;
- qual é a raridade de uma posição catalográfica;
- quem ilustrou determinada Card;
- qual é o número oficial da Card dentro do Set.

---

### Identidade

Uma Card representa uma única posição catalográfica dentro de um Set.

Exemplo:

```text
Charizard ex
187/188
```

Mesmo que essa Card exista em diferentes idiomas, formas de impressão ou exemplares físicos, ela permanece uma única Card no catálogo.

---

### Características Conceituais

Conceitualmente, uma Card:

- pertence obrigatoriamente a um Set;
- possui um número oficial dentro do Set;
- possui um nome;
- possui uma categoria;
- possui uma raridade;
- pode representar um Pokémon ou outro conteúdo oficial do jogo;
- pode possuir informações editoriais associadas;
- pode possuir uma ilustração.

A presença e a estrutura definitiva dessas informações serão avaliadas durante a modelagem lógica.

---

### Relacionamentos

```text
Set
 1
 │
 └── N Card
```

Cada Card pertence obrigatoriamente a um único Set.

A identidade de uma Card é contextual ao Set ao qual ela pertence.

---

### Limite da Hierarquia Editorial

A hierarquia editorial principal termina em Card:

```text
Game
  ↓
Expansion
  ↓
Set
  ↓
Card
```

Formas de impressão, idiomas, condições físicas, certificações e exemplares do usuário não fazem parte dessa hierarquia editorial principal.

---

## Card Variant

*Documentação pendente.*

---

## Inventory Item

*Documentação pendente.*

---

## Storage Location

*Documentação pendente.*

---

## User Collection

*Documentação pendente.*

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Estrutura inicial do modelo conceitual. |
| 1.1 | Padronização do cabeçalho (Arquivo, Escopo, Dependências, Documentos Relacionados) para consistência com os demais documentos centrais. |