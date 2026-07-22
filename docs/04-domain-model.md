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
| **Documentos Relacionados** | `adr/ADR-003-multi-game-architecture.md`, `adr/ADR-004-set-identity.md`, `adr/ADR-005-catalog-language-model.md`, `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-007-card-translation-model.md`, `adr/ADR-008-external-catalog-data-sources.md`, `adr/ADR-009-card-variant-scope.md`, `adr/ADR-010-card-rarity-and-finish-model.md`, `02-architecture-principles.md` (AP-013, AP-014), `architecture/ubiquitous-language.md` |

---

# Purpose

Este documento descreve os conceitos fundamentais utilizados pelo sistema.

Seu objetivo é definir o domínio do problema antes da implementação no banco de dados.

Este documento não contém SQL nem detalhes físicos de implementação.

---

# Core Concepts

Os seguintes conceitos compõem o núcleo do domínio do sistema, organizados conforme a hierarquia editorial principal e as responsabilidades definidas em ADR-006.

- Game
- Expansion
- Set
- Card
- Card Category
- Card Translation
- Rarity
- Finish
- Card Finish
- Pokémon
- Illustrator
- Energy Type
- Inventory Item
- Storage Location
- Collection
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
- Base Set Count (Quantidade do Conjunto Base) — o denominador oficial exibido nas Cards;
- quantidade oficial total de cartas publicadas — ver "Official Card Count", na seção Card.

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

Uma **Card (Carta)** representa uma posição oficial numerada dentro de um **Set (Set)**, contendo todas as características editoriais **permanentes** daquela publicação — ou seja, características que continuam verdadeiras mesmo que nenhum usuário possua um exemplar dela (ver AP-013 — Permanence Principle).

Ela possui identidade editorial própria e existe independentemente de qualquer exemplar físico pertencente a um usuário.

A Card tende a ser a entidade mais rica do domínio — não por possuir muitas colunas, mas por ser o ponto de convergência de praticamente todo o conhecimento editorial do catálogo (Rarity, Card Category, Card Translation, Card Finish, e demais atributos e relações descritos em "Atributos e Relações da Card", abaixo).

Exemplo:

```text
Set: ME1 — Megaevolução
Card: Charizard ex
Número: 187/132
```

Nesse exemplo, `187` é o número oficial da Card e `132` é o Base Set Count do Set (ver "Três Métricas de Contagem do Catálogo", abaixo). Como `187` está acima do conjunto base, essa Card é uma posição independente, e não uma variante de uma Card de número menor.

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

Ela permite responder, entre outras, às seguintes perguntas — verdadeiras mesmo que ninguém no mundo possua aquela Card:

- quantas posições oficiais existem em um Set;
- quais Cards pertencem a determinado Set;
- quais Cards ainda faltam em uma coleção;
- qual é o número oficial da Card dentro do Set;
- qual Pokémon (quando aplicável) ela representa;
- qual o HP;
- qual o tipo (Energy Type);
- quais ataques e habilidades possui;
- quem ilustrou determinada Card;
- qual é a Rarity da Card;
- qual é a regra ou texto oficial da Card;
- em qual Set ela pertence.

---

### Identidade

Uma Card representa uma única posição catalográfica dentro de um Set.

Conceitualmente, a identidade de negócio de uma Card é formada por:

```text
Set + Número da Card
```

Exemplo:

```text
Charizard ex
187/132
```

Mesmo que essa Card exista em diferentes idiomas, formas de impressão ou exemplares físicos, ela permanece uma única Card no catálogo.

O denominador exibido junto ao número (`132`, no exemplo) representa a quantidade oficial do conjunto base do Set ao qual a Card pertence — é uma característica do Set, não da Card, e não precisa ser armazenada de forma redundante em cada Card. Duas Cards do mesmo Set compartilham o mesmo denominador.

Uma mesma numeração (Set + Número) associada a Sets diferentes representa Cards distintas. Por exemplo, `125/094` no Set `PFL` e `125/094` em outro Set não são a mesma Card.

Outro exemplo: um Charizard ex publicado no Set `ME1` e, anos depois, republicado no Set `ME8`, são **duas Cards distintas** — mesmo compartilhando o mesmo Pokémon, o mesmo HP e os mesmos ataques. Editorialmente, continuam sendo publicações diferentes, pertencentes a Sets diferentes.

---

### Características Conceituais

Conceitualmente, uma Card:

- pertence obrigatoriamente a um Set;
- possui um número oficial dentro do Set;
- possui um nome;
- possui uma Card Category (ver "Card Category", abaixo);
- possui uma Rarity (ver "Rarity", abaixo);
- quando sua Card Category for Pokémon, referencia um Pokémon — Cards de outras categorias (Trainer, Energy) não possuem essa referência (ver "Atributos e Relações da Card", abaixo);
- pode possuir informações editoriais associadas (ataques, habilidades, texto de regras, etc.);
- pode possuir uma ilustração e um Illustrator associado.

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

### Atributos e Relações da Card

Aplicando o Princípio da Reutilização Editorial (AP-014), nem toda informação associada a uma Card deve ser um simples campo de texto: informações compartilhadas entre milhares de Cards tendem a se tornar entidades de referência próprias, evitando duplicação e permitindo consistência (ex.: corrigir o nome de um Illustrator em um único lugar).

Dimensões já identificadas, associadas à Card:

- **Card Category** — classifica a Card (Pokémon, Trainer, Energy, entre outras). Ver seção própria, abaixo.
- **Card Translation** — conteúdo editorial por idioma. Ver seção própria, acima.
- **Rarity** — classificação de raridade. Ver seção própria, acima.
- **Card Finish** — acabamentos físicos disponíveis. Ver seção própria, abaixo.
- **Pokémon** — quando a Card Category for Pokémon, a Card referencia um Pokémon (entidade de referência, reutilizada por todas as Cards que representam aquele mesmo Pokémon através de diferentes Sets). Cards de outras categorias (Trainer, Energy) não possuem essa referência.
- **Illustrator** — o ilustrador responsável pela arte da Card; entidade de referência, reutilizada por todas as Cards ilustradas pela mesma pessoa.
- **Energy Type** — o tipo elemental da Card (ex.: Água, Fogo, Planta, Elétrico), quando aplicável; entidade de referência.

Dimensões identificadas mas ainda não detalhadas segundo o método de STD-002 (não se sabe ainda se serão entidades de referência próprias ou atributos simples da Card): Attack, Ability, Weakness, Resistance, Retreat Cost, Regulation Mark, Legality, Evolves From, Evolves To. Serão avaliadas em ciclos futuros de documentação.

> **Importante:** nem toda Card representa um Pokémon. A hipótese inicial de que toda Card se relacionaria diretamente com um Pokémon foi identificada como um erro de modelagem — uma confusão entre o domínio Pokémon (o personagem/espécie) e o domínio Pokémon TCG (o jogo de cartas). Existem Cards de categoria Trainer (ex.: Acerola — Supporter; Poké Pad — Item; Torre Prisma — Stadium) e Energy que não representam nenhum Pokémon. Essa relação é, portanto, condicional à Card Category, não universal.

---

### Três Métricas de Contagem do Catálogo

O catálogo precisa responder a três perguntas distintas, que não devem ser confundidas:

**1. Official Card Count (Quantidade Oficial de Cartas)**

Responde: *quantas posições numeradas existem em um Set?*

É a contagem das posições catalográficas (Cards) de um Set, do número `001` até o último número oficialmente publicado — incluindo posições acima do conjunto base.

Exemplo: o Set ME1 possui Official Card Count `188`.

**2. Base Set Count (Quantidade do Conjunto Base)**

Responde: *qual é o denominador oficial exibido nas Cards?*

É a quantidade oficial de cartas do conjunto base do Set — uma característica do Set (ver "Características", acima), não da Card.

Exemplo: o Set ME1 possui Base Set Count `132`; suas Cards são numeradas de `001/132` até `188/132`.

**3. Collectible Finish Count (Quantidade de Acabamentos Colecionáveis)**

Responde: *quantas versões oficiais distintas podem ser colecionadas?*

É a soma dos acabamentos (Card Finish, ver abaixo) disponíveis para todas as Cards do Set. Essa quantidade pode ser superior ao Official Card Count, mas isso não altera o tamanho oficial do Set.

Exemplo hipotético:

```text
Card 001 → 2 acabamentos
Card 002 → 2 acabamentos
Card 003 → 1 acabamento
...
```

Essa contagem deve ser obtida somando os acabamentos efetivamente catalogados para cada Card — nunca por uma multiplicação fixa, já que nem todas as Cards de um Set necessariamente possuem os mesmos acabamentos disponíveis. Na prática, esse número tende a ser bem mais próximo do Official Card Count do que se imaginava inicialmente, já que formas de impressão como Full Art ou Special Illustration Rare já contam como Cards independentes — diferenciadas por Rarity própria — e não como acabamentos de outra Card (ver "Rarity" e "Finish", abaixo).

Essas três métricas atendem a propósitos diferentes do produto: a primeira mede a completude do catálogo editorial (quais posições existem); a segunda é uma característica de referência do Set; a terceira mede a completude colecionável (quantos itens distintos um colecionador pode efetivamente possuir).

---

## Card Translation (Tradução da Carta)

### O que é?

Representa o conteúdo editorial de uma Card em um idioma específico: nome traduzido e demais textos oficiais que variam por idioma.

Exemplo:

```text
Card: Laboratórios Lysandre / Lysandre Labs
Set: sm6, Número: 092

Card Translation (Portuguese): Laboratórios Lysandre
Card Translation (English): Lysandre Labs
```

Ambas as traduções pertencem à mesma Card, que ocupa uma única posição catalográfica (`092/094`).

---

### O que não é?

Uma Card Translation não representa:

- uma nova Card;
- uma nova posição catalográfica;
- um Finish ou Card Finish;
- o idioma de um exemplar físico pertencente a um usuário.

O nome traduzido de uma Card não cria uma nova posição no catálogo — apenas muda sua representação linguística.

---

### Qual problema resolve?

Permite que o catálogo conheça oficialmente o conteúdo editorial de uma Card em mais de um idioma, sem duplicar a identidade da Card e sem depender do idioma de exemplares pertencentes a usuários.

Sem esse conceito, o sistema não teria onde registrar, por exemplo, que uma Card se chama "Laboratórios Lysandre" em português e "Lysandre Labs" em inglês — ambos nomes oficiais da mesma posição catalográfica.

---

### Diferença entre Tradução Editorial e Idioma do Exemplar

Existem duas categorias distintas de informação linguística no domínio:

**Tradução editorial** — pertence ao catálogo (Card Translation). Pode variar entre idiomas:

- nome da carta;
- texto de regras;
- ataques;
- habilidades;
- descrições;
- eventualmente, nomes de categorias.

**Idioma do exemplar físico** — pertence ao patrimônio do usuário (Inventory Item). Indica qual versão linguística impressa o usuário efetivamente possui.

O catálogo conhece os nomes oficiais em todos os idiomas suportados, independentemente de qualquer usuário possuir um exemplar em determinado idioma.

---

### Características Conceituais

Conceitualmente, uma Card Translation:

- pertence obrigatoriamente a uma única Card;
- está associada a um idioma;
- possui conteúdo editorial traduzido correspondente àquele idioma.

A estrutura definitiva desses campos será avaliada durante a modelagem lógica.

---

### Relacionamentos

```text
Card
 1
 │
 └── N Card Translation
```

Cada Card pode possuir uma Card Translation por idioma suportado pelo catálogo.

---

## Rarity (Raridade)

### O que é?

Representa a classificação de raridade oficial de uma Card, indicada por um símbolo específico na lista oficial do catálogo.

Exemplos de valores observados na lista oficial do ME1:

- Common (Comum);
- Uncommon (Incomum);
- Rare (Rara);
- Double Rare (Rara Dupla);
- Ultra Rare (Rara Ultra);
- Illustration Rare (Ilustração Rara);
- Special Illustration Rare (Ilustração Rara Especial);
- Mega Hyper Rare (Mega Rara Hiper).

Esta lista reflete o que foi observado no documento oficial processado até o momento (`assets/reference-sources/P10346_ME01_Card_List_PTBR.pdf`) e não deve ser considerada exaustiva para todos os Sets ou Games suportados pelo Project Mimikyu.

---

### O que não é?

Rarity não representa:

- uma forma de impressão ou acabamento físico (ver Finish, abaixo);
- uma nova posição catalográfica;
- uma classificação derivada ou calculada — é um dado oficial publicado pelo catálogo.

Termos como Illustration Rare, Special Illustration Rare e Ultra Rare **não são variações de impressão**. São classificações de raridade da própria Card.

---

### Qual problema resolve?

Permite registrar oficialmente o nível de raridade de cada Card, exatamente como publicado na lista oficial do catálogo — informação usada, entre outros fins, para diferenciar Cards que representam o mesmo Pokémon (mesmo nome) mas ocupam posições catalográficas distintas por possuírem raridade, arte e tratamento editorial próprios.

---

### Características Conceituais

Conceitualmente, uma Rarity:

- é um valor de um conjunto controlado de classificações oficiais;
- pertence a uma Card como atributo/relação direta.

A estrutura definitiva (lista fechada vs. extensível, campos adicionais) será avaliada durante a modelagem lógica.

---

### Relacionamentos

```text
Card
 N
 │
 └── 1 Rarity
```

Cada Card possui uma única Rarity. Uma mesma Rarity pode se aplicar a diversas Cards.

---

## Finish (Acabamento)

### O que é?

Representa um tipo de acabamento físico oficial em que uma Card pode ser impressa — um catálogo controlado de valores.

Exemplos de valores observados na lista oficial do ME1:

- Standard (Padrão);
- Standard Foil (Laminada Padrão).

Outros acabamentos identificados em discussões anteriores da modelagem, ainda não confirmados por documento oficial:

- Reverse Holo;
- Cosmos Holo.

Durante a modelagem, o conceito de acabamento também foi referido informalmente como "Printing Variant" e "Finish Variant". Ambos os termos foram **descartados definitivamente** — o nome canônico adotado é **Finish**, por não sugerir a criação de uma versão editorial derivada (ver ADR-010).

---

### O que não é?

Finish não representa:

- uma nova posição catalográfica;
- uma Card diferente;
- uma classificação de raridade (ver Rarity, acima);
- um exemplar físico específico do usuário (ver Inventory Item).

Um Finish **não altera** o número da Card, sua posição no Set, sua raridade, seu nome ou sua identidade editorial.

---

### Qual problema resolve?

Permite representar em quais acabamentos físicos oficiais uma Card pode ser encontrada, sem tratar cada acabamento como uma nova Card.

---

## Card Finish (Acabamento da Carta)

### O que é?

Declara que uma determinada Card está oficialmente disponível em um determinado Finish.

Exemplo:

```text
Card: 001/132 — Bulbasaur (Rarity: Common)
Available Finishes:
- Standard
- Standard Foil

Card: 177/132 — Mega Venusaur ex (Rarity: Special Illustration Rare)
Available Finishes:
- Standard Foil
```

Não se deve assumir que todas as Cards de um Set possuem automaticamente os mesmos acabamentos disponíveis — cada Card Finish deve ser catalogada individualmente.

---

### O que não é?

Card Finish não representa:

- uma nova Card;
- uma nova posição catalográfica no Set;
- uma diferença de idioma (ver Card Translation);
- um exemplar físico específico do usuário (ver Inventory Item).

---

### Resolução da Questão de Identidade (histórico)

Um ciclo anterior desta documentação havia sinalizado como questão em aberto se formas de impressão (Full Art, Rainbow Rare, etc.) poderiam quebrar a regra de identidade "Set + Número da Card". Essa questão foi resolvida com apoio de um documento oficial (a lista de cartas do ME1): Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold e Rainbow não são diferenças de Finish — são **Cards independentes**, cada uma com número, arte e Rarity próprios, regidas normalmente pela regra "Set + Número da Card" (ADR-004), sem necessidade de tratamento especial. O que antes parecia uma questão de identidade de "variante" era, na verdade, uma mistura de três conceitos diferentes: Card, Rarity e Finish. Ver ADR-010 para o registro completo desta decisão.

Consequência prática: o escopo de Card Finish é mais estreito do que inicialmente hipotetizado — cobre apenas quais acabamentos físicos (tipicamente Standard e Standard Foil) estão disponíveis para uma mesma posição catalográfica. A maioria das Cards possui apenas um ou dois acabamentos.

---

### Características Conceituais

Conceitualmente, uma Card Finish:

- associa uma única Card a um único Finish;
- não altera número, arte, Rarity ou registro editorial da Card à qual pertence.

A estrutura definitiva desses campos será avaliada durante a modelagem lógica.

---

### Relacionamentos

```text
Card
 1
 │
 └── N Card Finish
        │
        └── referencia 1 Finish
```

Um exemplar físico do usuário (Inventory Item) referencia uma Card Finish específica — não a Card diretamente — já que o acabamento físico é uma característica do exemplar impresso:

```text
Card
 │
 └── Card Finish
        │
        └── Inventory Item
```

> **Nota sobre nomenclatura física:** o schema físico já existente no projeto utiliza as tabelas `card_variant` e `card_variant_type`, nomeadas antes desta refinamento conceitual. A relação entre esses nomes físicos e os termos conceituais Finish/Card Finish definidos aqui (renomear a tabela física ou apenas mapear os conceitos) é uma decisão que será tomada durante a modelagem física (`05-modelo-de-dados.md`), e não está resolvida por este documento.

---

## Card Category (Categoria da Carta)

### O que é?

Classifica a natureza de uma Card dentro do jogo. Corresponde à tabela física já existente `card_category`.

Valores confirmados até o momento:

- Pokémon;
- Trainer — famílias observadas: Item, Supporter, Stadium, Tool;
- Energy.

---

### O que não é?

Card Category não representa:

- uma Rarity;
- um Finish;
- uma relação direta e universal com a entidade Pokémon (ver "Atributos e Relações da Card", acima) — apenas Cards de categoria Pokémon possuem essa referência.

---

### Qual problema resolve?

Evita a suposição incorreta de que toda Card representa um Pokémon. Cards como Acerola (Supporter), Poké Pad (Item) e Torre Prisma (Stadium) não representam nenhum Pokémon, mas são Cards válidas do catálogo.

---

### ⚠️ Questão em Aberto — Taxonomia de Card Category

A discussão histórica que originou esta seção **não foi concluída** nos anexos processados até este ciclo (limitado a 20 anexos; Fabrício sinalizou que enviará um complemento).

Ainda não está definido:

- se "Trainer" é um valor armazenado de Card Category, com Item/Supporter/Stadium/Tool sendo uma subclassificação dentro dele; ou
- se Item/Supporter/Stadium/Tool são tratados como valores de Card Category no mesmo nível de Pokémon e Energy (sem um valor "Trainer" intermediário armazenado).

Nenhuma das duas estruturas deve ser assumida como definitiva até a continuação desta discussão ser recebida e analisada.

---

### Relacionamentos

```text
Card
 N
 │
 └── 1 Card Category
```

Cada Card possui exatamente uma Card Category.

---

## Pokémon

### O que é?

Representa a espécie/personagem Pokémon (ex.: Bulbasaur) referenciada por uma Card de categoria Pokémon. Entidade de referência, reutilizada por todas as Cards que representam aquele mesmo Pokémon em diferentes Sets (aplicação do Princípio da Reutilização Editorial, AP-014).

---

### O que não é?

Pokémon não representa:

- uma Card específica — uma mesma espécie de Pokémon corresponde a muitas Cards distintas, uma por Set em que aparece;
- uma categoria de Card (ver Card Category, acima) — nem toda Card possui um Pokémon associado.

---

### Qual problema resolve?

Evita duplicar o nome e demais informações de uma espécie de Pokémon em cada uma das dezenas de Cards que a representam ao longo de diferentes Sets.

---

### Relacionamentos

```text
Pokémon
 1
 │
 └── N Card (apenas Cards de categoria Pokémon)
```

*Estrutura detalhada de características pendente — a ser avaliada em ciclo futuro de documentação.*

---

## Illustrator (Ilustrador)

### O que é?

Representa a pessoa responsável pela arte de uma Card. Entidade de referência, reutilizada por todas as Cards ilustradas pela mesma pessoa (aplicação do Princípio da Reutilização Editorial, AP-014).

---

### Qual problema resolve?

Evita duplicar o nome de um ilustrador em cada uma das centenas de Cards que ele ilustrou, e permite corrigir essa informação em um único lugar.

---

### Relacionamentos

```text
Illustrator
 1
 │
 └── N Card
```

*Estrutura detalhada de características pendente — a ser avaliada em ciclo futuro de documentação.*

---

## Energy Type (Tipo de Energia)

### O que é?

Representa o tipo elemental de uma Card, quando aplicável (ex.: Água, Fogo, Planta, Elétrico). Entidade de referência, compartilhada por milhares de Cards (aplicação do Princípio da Reutilização Editorial, AP-014).

---

### Relacionamentos

```text
Energy Type
 1
 │
 └── N Card
```

*Estrutura detalhada de características pendente — a ser avaliada em ciclo futuro de documentação.*

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
| 1.2 | Correção do exemplo de numeração da Card (denominador deve ser a quantidade do conjunto base, não o total de Cards). Adição de "Duas Métricas de Contagem do Catálogo", da entidade Card Translation, e de conteúdo parcial de Card Variant com questão de identidade sinalizada como em aberto. Correção da lista de Core Concepts ("Card Set" → "Set", reordenada pela hierarquia editorial). |
| 1.3 | Resolvida a questão de identidade de Card Variant: escopo restrito a diferenças de acabamento sobre a mesma posição catalográfica (Standard, Reverse Holo, etc.). Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold e Rainbow passam a ser tratadas explicitamente como Cards independentes, não como variantes — consistente com a decisão já registrada por Fabrício e agora fundamentada por ADR-009. |
| 1.4 | Com base em documento oficial (lista de cartas do ME1), substituído o conceito "Card Variant" por três conceitos distintos: Rarity (raridade, atributo da Card), Finish (catálogo de acabamentos físicos) e Card Finish (associação Card+Finish). Termos "Printing Variant" e "Finish Variant" descartados definitivamente. Relação Inventory Item atualizada para referenciar Card Finish, não a Card diretamente. Ver ADR-010 (substitui ADR-009 nesse ponto). |
| 1.5 | Expandida a métrica de contagem de duas para três (Official Card Count, Base Set Count, Collectible Finish Count). Adicionadas as entidades Card Category (com taxonomia de Trainer sinalizada como em aberto), Pokémon, Illustrator e Energy Type. Corrigida a suposição de que toda Card possui um Pokémon associado — relação agora condicional à Card Category. Adicionada seção "Atributos e Relações da Card" aplicando o novo AP-014. |