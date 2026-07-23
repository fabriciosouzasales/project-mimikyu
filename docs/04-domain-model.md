# Domain Model

| Campo | Valor |
|--------|-------|
| **Documento** | Domain Model |
| **Arquivo** | `docs/04-domain-model.md` |
| **Versão** | 2.0 |
| **Status** | Em elaboração |
| **Objetivo** | Definir o modelo conceitual do domínio do Project Mimikyu antes da modelagem lógica e física. |
| **Escopo** | Modelo conceitual do domínio: entidades, relacionamentos e regras de negócio atualmente vigentes. Não contém SQL, números de Query, versões de Seed, confirmações de execução, nem histórico de discussão de sessões — ver `05-modelo-de-dados.md` para a camada física e de execução, e `06-pipeline-importacao.md` para estratégias de importação. |
| **Dependências** | `00-project-charter.md`, `02-architecture-principles.md`, `standards/STD-002-domain-modeling.md` |
| **Documentos Relacionados** | `adr/ADR-003-multi-game-architecture.md`, `adr/ADR-004-set-identity.md`, `adr/ADR-005-catalog-language-model.md`, `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-007-card-translation-model.md`, `adr/ADR-008-external-catalog-data-sources.md`, `adr/ADR-009-card-variant-scope.md`, `adr/ADR-010-card-rarity-and-finish-model.md`, `adr/ADR-011-pokemon-tcg-domain-scope.md`, `adr/ADR-012-structured-vs-visual-card-data.md`, `adr/ADR-013-collection-item-identity-model.md`, `adr/ADR-014-collection-and-collection-entry-model.md`, `02-architecture-principles.md` (AP-013, AP-014, AP-015, AP-017), `standards/STD-002-domain-modeling.md`, `07-catalogo-editorial.md`, `architecture/ubiquitous-language.md` |

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
- Trainer Subcategory
- Card Translation
- Rarity
- Finish
- Card Finish
- Card Asset Type / Card Asset
- Card Details (Pokémon Card Details / Trainer Card Details)
- Pokémon
- Illustrator
- Energy Type
- Collection Item
- Storage Location
- Collection
- Collection Entry
- User Collection

---

# Concept Definitions

## Collection (Coleção)

### O que é?

Representa um agrupamento definido pelo colecionador para organizar um objetivo de coleção. Diferente do Set (ver abaixo), que pertence ao catálogo editorial oficial e existe independentemente dos usuários, a Collection pertence ao colecionador — não existe sem um usuário associado (ver ADR-014).

Exemplos:

- ME1 completa;
- Pokédex Nacional;
- Treinadores;
- Pokémon Trabalhando;
- Pikachu;
- Pokémon do tipo Fantasma;
- Ilustrações de determinado artista;
- Cartas com personagens humanos;
- Cartas favoritas do usuário.

Uma Collection pode reunir Cards provenientes de vários Sets, Expansions e idiomas.

---

### O que não é?

Collection não representa:

- um Set oficial;
- uma Expansion;
- uma pasta física;
- um simples filtro temporário;
- obrigatoriamente um agrupamento de itens já possuídos.

Uma Collection pode conter tanto Cards já adquiridas quanto Cards ainda desejadas.

---

### Qual problema resolve?

Permite responder perguntas como: quais Pokémon da Pokédex já possuo? quais Treinadores ainda faltam? quais Cards fazem parte da coleção "Pokémon Trabalhando"? quantas Cards do Pikachu tenho? qual é o progresso da minha coleção temática? em quais Sets estão as Cards necessárias?

---

### Tipos de Collection

**Official Set Collection (Coleção Baseada em Set)** — representa o objetivo de completar um Set oficial. As Cards esperadas podem ser obtidas diretamente do Set.

```text
Collection: ME1 — Megaevolução
Collection Type: SET_BASED
Reference Set: ME1
```

**Custom Collection (Coleção Personalizada)** — representa uma seleção independente de Set. A identidade da coleção não depende de nenhum Set específico; suas Cards podem vir de múltiplos Sets e Expansions.

```text
Collection: Pokémon Trabalhando
Collection Type: CUSTOM
Reference Set: null
```

---

### Características Conceituais

Conceitualmente, uma Collection possui: identidade própria; um usuário dono; nome; descrição; um tipo (`SET_BASED` ou `CUSTOM`); e, quando `SET_BASED`, uma referência ao Set correspondente.

A estrutura definitiva desses campos será avaliada durante a modelagem lógica.

---

### Relacionamentos

```text
User (Usuário)
 1
 │
 └── N Collection
        │
        └── N Collection Entry
```

---

## Collection Entry (Entrada da Coleção)

### O que é?

Representa um item que compõe o objetivo de uma Collection: uma Card específica, ou um assunto mais amplo que qualquer Card correspondente pode satisfazer.

---

### O que não é?

Não representa um Collection Item (o exemplar físico efetivamente possuído — ver acima). Collection Entry é o alvo/objetivo da coleção; o sistema verifica os Collection Items do usuário para determinar se uma Entry já foi atendida.

---

### Dois Tipos de Objetivo

**Card Target (Objetivo por Carta)** — a Collection exige uma Card específica.

Exemplos: todas as Cards do Set ME1; todas as Special Illustration Rare; todas as Cards da Acerola; todas as Cards ilustradas por determinado artista.

```text
Collection Entry
 │
 └── Card
```

**Subject Target (Objetivo por Tema)** — a Collection exige um assunto, mas aceita diferentes Cards como atendimento do objetivo.

Exemplo: na Pokédex, o objetivo pode ser "Bulbasaur" (o Pokémon), não uma Card específica — qualquer Card válida do Bulbasaur preenche a posição, independentemente do Set de origem. Isso é diferente de exigir "Bulbasaur 001/132 do ME1" especificamente (o que seria Card Target).

```text
Collection Entry
 │
 └── Pokémon
```

---

### Exemplos de Aplicação

**Pokédex Nacional** — Subject Target, por Pokémon:

```text
Collection: Pokédex Nacional
Entries: 001 Bulbasaur, 002 Ivysaur, 003 Venusaur...
```

O sistema verifica se o usuário possui algum Collection Item relacionado àquele Pokémon (via Card → Pokémon), independentemente do Set. Uma Card repetida de qualquer Set preenche a posição correspondente.

**Pokémon Trabalhando** — não é uma característica oficial estruturável automaticamente; depende de curadoria manual. O colecionador escolhe manualmente quais Cards representam o tema (Card Target, com curadoria manual da lista).

**Coleção baseada em Set (ex.: ME1)** — Card Target, gerado automaticamente a partir das Cards do Set referenciado.

---

### Mecanismos de Inclusão

- **Manual Membership (Inclusão Manual)** — o colecionador adiciona manualmente Cards ou Pokémon à coleção.
- **Rule-Based Membership (Inclusão por Regra)** — entradas geradas automaticamente por regras estruturadas (ex.: `rarity = ILLUSTRATION_RARE`, `pokemon = PIKACHU`, `category = TRAINER`, `artist = ...`).

Para a primeira implementação estão previstos apenas Manual Membership e a geração automática simples de Official Set Collections. Um motor completo de regras (Rule-Based Membership) fica para um ciclo futuro, evitando modelagem excessiva antes de uma necessidade concreta (AP-004).

---

### Características Conceituais

Conceitualmente, uma Collection Entry possui: identidade própria; referência à Collection à qual pertence; uma referência a Card (quando Card Target) ou a Pokémon (quando Subject Target), nunca ambas simultaneamente; ordem de exibição; notas.

Esta é uma primeira aproximação; no modelo lógico, talvez sejam duas entidades especializadas, evitando campos nulos — decisão não fechada nesta versão.

---

### Relacionamentos

```text
Collection
 1
 │
 └── N Collection Entry
        ├── referencia 1 Card (quando Card Target), ou
        └── referencia 1 Pokémon (quando Subject Target)
```

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
- um produto comercial;
- uma identidade visual própria — logotipo e símbolo pertencem ao Set (ver seção "Set", abaixo), já que cada Set de uma mesma Expansion possui sua própria identidade visual.

Sua função é exclusivamente editorial.

---

### Qual problema resolve?

Organiza grandes volumes de conteúdo em agrupamentos editoriais permanentes.

Sem esse conceito, um catálogo precisaria administrar centenas de Sets diretamente sob um único Game, dificultando organização, navegação e evolução do domínio.

---

### Características

Conceitualmente, uma Expansion possui:

- código editorial;
- nome;
- ordem cronológica;
- data de início;
- data de encerramento (quando existir);
- Game ao qual pertence.

Essas características representam apenas o conceito do domínio e não definem atributos técnicos da implementação.

Exemplos (Pokémon):

| Code | Name |
|------|------|
| SV | Scarlet & Violet |
| SWSH | Sword & Shield |
| SM | Sun & Moon |
| XY | XY |

### Código e Nome

O código de uma Expansion é editorial e internacional — não muda entre idiomas (ex.: `SV` continua sendo `SV` em qualquer idioma). O nome pode ser localizado futuramente, quando houver necessidade, seguindo o mesmo padrão já estabelecido para conteúdo editorial em Card Translation (ver ADR-007). Este padrão — código internacional, nome localizável — se repete em todo o catálogo editorial.

### Ordem de Lançamento

A ordem de lançamento (`release_order`) é um número inteiro simples, refletindo a sequência editorial conhecida (ex.: Base, Neo, e-Card, EX, Diamond & Pearl, Black & White, XY, Sun & Moon, Sword & Shield, Scarlet & Violet). Foi deliberadamente mantida simples — sem reservar intervalos entre valores — porque uma renumeração completa é considerada aceitável no raro caso de uma nova Expansion precisar se inserir entre duas antigas por necessidade editorial (reedição, linha paralela etc.).

### Unicidade por Game

O código e a ordem de lançamento de uma Expansion são únicos **dentro do respectivo Game**, não globalmente. Isso decorre diretamente da arquitetura multi-TCG (ver ADR-003): outro Trading Card Game pode perfeitamente utilizar um código como `SV` para outra finalidade. Esta é uma regra que se repete em todo o catálogo — toda unicidade de código editorial deve respeitar o contexto do Game.

### Sem Status

Expansion não possui um campo `status`. Nenhum caso de uso concreto foi identificado até o momento (ex.: distinguir Expansions "anunciadas", "lançadas" ou "canceladas") — aplicação direta do Princípio da Simplicidade Inicial (ver AP-004). Se essa necessidade surgir, o campo será adicionado por uma nova migration, não antecipado agora.

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
- identidade visual própria (logotipo completo e símbolo usado nas Cards — ver "Identidade Visual", abaixo);
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

O idioma pertence ao exemplar físico do usuário (Collection Item).

### Classificação Editorial

Todo Set possui uma classificação editorial. São reconhecidos três tipos:

- Regular Set;
- Special Set;
- Promotional Set (Black Star Promos — ver "Card Set Promocional", abaixo).

A classificação não altera a natureza da entidade. Um Set Especial ou Promocional continua sendo um Set — a classificação editorial é uma característica do Set e não justifica a criação de entidades distintas, inclusive para o caso promocional (ver ADR-015).

### Card Set Promocional (Black Star Promos)

Existe um conjunto de cartas — as **cartas promocionais (Black Star Promos)** — diretamente ligado a uma Expansion, mas sem as características de um Set editorial tradicional: não possui necessariamente código ou nome oficial próprio, não ocupa uma posição fixa na sequência de Sets, e sua quantidade de cartas não é fechada — cresce ao longo do tempo, conforme novos produtos daquela Expansion são lançados.

Em vez de criar uma entidade separada — o que obrigaria a Card a ter dois relacionamentos possíveis com sua entidade-pai, propagando duplicidade para coleção, inventário, traduções, imagens e importações —, a série promocional é registrada como um Set comum, do tipo `PROMO`, vinculado à sua Expansion, seguindo uma convenção fixa de preenchimento (não campos opcionais):

- **Código** e **Nome** são derivados do código/nome da Expansion, seguindo um padrão fixo de série promocional;
- **Posição na sequência** = sempre a primeira da Expansion, deslocando os demais Sets;
- **Data de lançamento** = a mesma data do primeiro Set regular/especial da Expansion;
- **Quantidade base e quantidade total** = sempre iguais entre si, representando a quantidade atualmente conhecida de cartas promocionais — cresce conforme novas cartas são catalogadas, não é uma quantidade editorial fechada.

Com essa convenção, todos os valores de uma série promocional são determináveis a partir da Expansion à qual pertence, sem necessidade de colunas anuláveis no Set. Uma carta promocional carrega dois fatos independentes e complementares: pertence a um Set do tipo `PROMO` e possui Rarity `PROMO` (ver seção Rarity, abaixo).

Ver ADR-015 para a decisão completa (incluindo a alternativa de campos opcionais, avaliada e descartada) e `05-modelo-de-dados.md` para o estado físico atual, incluindo a padronização em curso do código oficial da série por Expansion.

### Código Editorial

O código do Set representa um identificador de negócio. Ele deve ser tratado como texto e nunca como um valor numérico.

Exemplos válidos: `ME1`, `ME2`, `ME2.5`, `SV09`.

O código editorial não define ordem cronológica, classificação editorial ou identidade técnica — essas características são independentes.

### Unicidade por Expansion

O código e a ordem de lançamento de um Set são únicos **dentro da respectiva Expansion**, não globalmente. Mesmo padrão de unicidade escopada já estabelecido para Expansion dentro de Game (ver acima, "Unicidade por Game"; ADR-003).

### Identidade Visual

O Set possui duas identidades visuais distintas: um logotipo completo e um símbolo pequeno usado nas Cards. Ambos são preenchidos por importação automática a partir de fontes externas, não por preenchimento manual (ver `06-pipeline-importacao.md`).

### Ordem Cronológica

A ordem cronológica de um Set é independente de seu código editorial. O código pode sugerir uma sequência, mas nunca deve ser interpretado ou convertido para determinar a posição do Set dentro de uma Expansion.

Exemplo:

| Código | Ordem de lançamento |
|--------|---------------------|
| ME1 | 1 |
| ME2 | 2 |
| ME2.5 | 3 |
| ME3 | 4 |

Nesse exemplo, `ME2.5` representa o terceiro Set da Expansion. Seu código não representa o valor matemático `2.5`.

---

### Status — Decisão: sem campo `status`

Set não possui um campo `status`. O campo `release_date` (opcional) já cobre o caso de uso: ausência de data indica Set apenas anunciado; presença indica Set lançado — aplicação direta do Princípio da Simplicidade Inicial (AP-004). Se uma necessidade real de status explícito surgir no futuro (ex.: `cancelled`), o campo será adicionado então.

---

### Visão Conceitual Consolidada

Conceitualmente, um Set possui:

- identidade própria;
- relação com uma Expansion (e, transitivamente, com um Game);
- código editorial (textual, único por Expansion);
- nome;
- classificação editorial (`REGULAR`, `SPECIAL` ou `PROMO` — ver "Card Set Promocional", acima; ADR-015);
- ordem cronológica (única por Expansion);
- data de lançamento (opcional — cobre o caso de Set anunciado sem data confirmada, sem necessidade de campo `status`);
- quantidade oficial do conjunto base;
- quantidade oficial total (a quantidade de cartas secretas é derivada, nunca armazenada);
- identidade visual própria (logotipo e símbolo — ver "Identidade Visual", acima).

> **Nota sobre nomenclatura física:** `SET` é uma palavra reservada do SQL (PostgreSQL). Para evitar ambiguidade, a tabela física correspondente ao conceito Set é nomeada `card_set` (ver `standards/STD-001-database-standards.md`, Seção 2). O conceito de domínio continua sendo chamado de Set na documentação e na aplicação.

Ver `05-modelo-de-dados.md`, seção Set, para o modelo físico e o estado de execução atual.

### Responsabilidade sobre Quantidades e Data de Lançamento (Set vs. Expansion)

Uma Expansion agrupa vários Sets, e cada Set possui sua própria numeração e quantidade de cartas — por isso essas informações pertencem ao Set, não à Expansion:

- **Base Set Count** e a quantidade oficial total de cartas são características do Set (ver acima e "Official Card Count", na seção Card).
- A quantidade de cartas secretas (posições acima do conjunto base) é **derivada**, não armazenada: `secret_set_size = total_set_size - base_set_size`. Armazená-la redundantemente arriscaria inconsistência.
- A **data de lançamento** também pertence ao Set (`release_date`), podendo ser nula para Sets apenas anunciados. A Expansion não possui uma data de lançamento própria armazenada — quando necessário, pode ser derivada como a menor `release_date` entre seus Sets.

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
- possui um número oficial dentro do Set (preservando zeros à esquerda, prefixos e sufixos alfanuméricos, ex.: `003`, `TG01`);
- possui uma ordem de posição no checklist, tecnicamente distinta do número exibido (necessária porque comparar o número como texto nem sempre ordena corretamente, ex.: `001, 010, 011` vs. `002`);
- possui um nome, armazenado exatamente como impresso no Set em que foi cadastrada — Card não mantém uma camada de tradução própria (ver Card Translation, abaixo, para conteúdo editorial multi-idioma);
- possui uma Card Category (ver "Card Category", abaixo);
- possui uma Rarity (ver "Rarity", abaixo);
- quando sua Card Category for Pokémon, referencia um Pokémon — Cards de outras categorias (Trainer, Energy) não possuem essa referência (ver "Atributos e Relações da Card", abaixo);
- pode possuir informações editoriais associadas (ataques, habilidades, texto de regras, etc.), sujeitas às regras de estruturação descritas em "Atributos e Relações da Card";
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

Cada Card pertence obrigatoriamente a um único Set. A identidade de uma Card é contextual ao Set ao qual ela pertence.

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

Aplicando o Princípio da Reutilização Editorial (AP-014), informações compartilhadas entre milhares de Cards são modeladas como entidades de referência próprias — evitando duplicação e permitindo consistência (ex.: corrigir o nome de um Illustrator em um único lugar) — em vez de simples campos de texto repetidos em cada Card.

Informações comuns a toda Card, independentemente da categoria: Card Category, Card Translation, Rarity, Card Finish, e Illustrator (o ilustrador responsável pela arte da Card).

Informações específicas por categoria são agrupadas em Card Details (ver seção própria, abaixo): quando a Card Category for Pokémon, a Card referencia um Pokémon; quando for Trainer, não possui essa referência. Nem toda Card representa um Pokémon — Cards de categoria Trainer (ex.: Acerola — Supporter; Poké Pad — Item; Torre Prisma — Stadium) não representam nenhum Pokémon. Essa relação é, portanto, condicional à Card Category, não universal (ver ADR-011).

Mecânica de jogo (HP, Stage, Attacks, Ability, Weakness, Resistance, Retreat Cost, Energy Type) não é estruturada no banco de dados — o Project Mimikyu é uma plataforma de colecionismo, não um banco de dados de mecânicas de jogo (AP-017). Essas informações permanecem visíveis apenas na imagem oficial da Card (ADR-012). O padrão Card Details / Pokémon Card Details / Trainer Card Details continua válido como arquitetura (ADR-011), sem conteúdo de jogo concreto planejado.

Nem toda informação acima precisa necessariamente de um campo estruturado e pesquisável desde a primeira versão — ver "Nota sobre estruturação de dados" na seção Card Details, ADR-012 e `07-catalogo-editorial.md`.

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

**Idioma do exemplar físico** — pertence ao patrimônio do usuário (Collection Item). Indica qual versão linguística impressa o usuário efetivamente possui.

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

### Nota sobre Imagem Editorial (Card Image)

A imagem oficial da Card é tratada como a fonte editorial completa (ver ADR-012 e AP-015 — Progressive Catalog Enrichment). Como existem múltiplos idiomas suportados, uma mesma Card pode possuir imagens diferentes por idioma — a existência de uma imagem por idioma não cria uma nova Card, apenas mais uma representação localizada.

A relação definitiva entre a imagem, a Card Translation e a Card Finish permanece em aberto e será decidida progressivamente: inicialmente, uma imagem por Card Translation pode ser suficiente; caso existam imagens digitais específicas por acabamento, a imagem poderá vir a se relacionar também com a Card Finish. Esta decisão não precisa ser fechada nesta versão do documento.

---

## Rarity (Raridade)

### O que é?

Representa a classificação de raridade oficial de uma Card, indicada por um símbolo específico na lista oficial do catálogo (ex.: Comum, Incomum, Rara, Rara Ultra, Ilustração Rara Especial). Cada Game mantém seu próprio catálogo de raridades, específico dos Sets já catalogados — o catálogo completo atualmente vigente para o Pokémon TCG está registrado em `05-modelo-de-dados.md`.

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
- pertence a uma Card como atributo/relação direta;
- **pertence a um Game, não diretamente a uma Expansion ou Set** — cada jogo possui seu próprio conjunto de raridades, que não deve ser misturado com o de outro jogo.

---

### Relacionamentos

```text
Game
 1
 │
 └── N Rarity
        │
        └── N Card
```

Cada Card possui uma única Rarity, referenciada por chave estrangeira (não por texto solto). Uma mesma Rarity pode se aplicar a diversas Cards. Uma Rarity pertence a exatamente um Game; diferentes Games não compartilham as mesmas linhas de Rarity, mesmo que usem nomes parecidos.

---

### Estrutura Conceitual

Rarity é uma entidade de referência vinculada ao Game — não um texto solto na própria Card. Cada Rarity possui um código técnico estável, um nome de exibição, um identificador do símbolo visual oficial (não o caractere ou uma URL de imagem — apenas um identificador estável; a renderização visual é responsabilidade da camada de apresentação) e uma ordem de exibição.

Códigos abreviados de mercado (ex.: `SAR`, `SIR`) podem representar classificações diferentes em catálogos ou mercados distintos — não devem ser presumidos equivalentes sem confirmação. O banco preserva a classificação oficial exatamente como usada no catálogo correspondente; a interface pode permitir busca por sinônimos de mercado apontando para a mesma raridade canônica.

`PROMO` é uma classificação de raridade oficial do próprio Pokémon TCG, não uma invenção do projeto. Uma carta promocional é caracterizada por dois fatos independentes e complementares: pertencer a um Set do tipo `PROMO` (ver "Card Set Promocional", na seção Set) e possuir Rarity `PROMO`.

---

### Observação Arquitetural — Card Depende de Dois Domínios

A existência de Rarity revela que `Card` não depende apenas da cadeia editorial `Game → Expansion → Set`, mas também diretamente de `Game → Rarity`:

```text
Game
 ├── Expansion
 │     └── Set
 │           └── Card
 │
 └── Rarity
       └── Card
```

Consequência prática: Rarity não é um atributo textual solto, mas um catálogo oficial do próprio Game — o que facilita filtros, estatísticas, internacionalização futura e evita inconsistências de cadastro entre Cards.

---

## Finish (Acabamento)

### O que é?

Representa um tipo de acabamento físico oficial em que uma Card pode ser impressa — um catálogo controlado de valores.

Exemplos de valores observados na lista oficial do ME1:

- Standard (Padrão);
- Standard Foil (Laminada Padrão).

Outros acabamentos identificados em ciclos anteriores de modelagem, ainda não confirmados por documento oficial:

- Reverse Holo;
- Cosmos Holo.

O nome canônico adotado para este conceito é **Finish** — os termos "Printing Variant" e "Finish Variant", usados informalmente durante a modelagem, foram descartados definitivamente por sugerirem, incorretamente, a criação de uma versão editorial derivada (ver ADR-010).

---

### O que não é?

Finish não representa:

- uma nova posição catalográfica;
- uma Card diferente;
- uma classificação de raridade (ver Rarity, acima);
- um exemplar físico específico do usuário (ver Collection Item).

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
- um exemplar físico específico do usuário (ver Collection Item).

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

Um exemplar físico do usuário (Collection Item) referencia uma Card Finish específica — não a Card diretamente — já que o acabamento físico é uma característica do exemplar impresso:

```text
Card
 │
 └── Card Finish
        │
        └── Collection Item
```

> **Nota de nomenclatura:** o schema físico usa os termos `card_variant`/`card_variant_type` para representar esta relação (ver `05-modelo-de-dados.md`). A escolha final do vocabulário do projeto entre esses termos e Finish/Card Finish (ADR-010) segue em aberto, não resolvida unilateralmente.

---

## Card Asset Type (Tipo de Ativo da Carta) / Card Asset (Ativo da Carta)

### O que é?

Card Asset representa um arquivo ou recurso digital associado a uma Card — tipicamente uma imagem, podendo no futuro incluir outros formatos (imagem em alta resolução, verso da carta, ícone, áudio, vídeo, arquivo 3D). Card Asset Type classifica a finalidade semântica do ativo (ex.: frente da carta, verso, ilustração isolada, miniatura, símbolo do Set) — não sua resolução ou dimensão; um mesmo tipo de ativo pode existir em múltiplas dimensões.

A imagem não é um campo direto de Card porque não é um atributo relacional da carta — é um ativo digital gerenciado separadamente, com procedência, formato e ciclo de vida próprios.

---

### O que não é?

Card Asset não representa uma variante colecionável (ver Card Variant/Card Finish, acima) nem um exemplar físico do usuário (ver Collection Item).

---

### Relacionamentos

```text
Card
 1
 │
 └── N Card Asset
        │
        └── referencia 1 Card Asset Type
```

Card Asset pertence diretamente à Card, não à Card Variant: a Card possui uma identidade visual única, independente do acabamento colecionável (Standard, Holo, Reverse Holo, etc.) — Card Variant e Card Asset são ramificações independentes a partir de Card.

---

### Características Conceituais

Conceitualmente, um Card Asset:

- pertence a uma única Card;
- possui um Card Asset Type que classifica sua finalidade;
- registra a fonte de origem (ex.: fonte oficial, importação externa, digitalização feita pelo próprio usuário) — permitindo que múltiplas fontes coexistam para a mesma Card sem conflito, já que uma nova fonte não substitui as anteriores;
- pode ser marcado como o ativo principal de seu tipo para aquela Card (no máximo um ativo principal por combinação Card + Asset Type).

Ver `05-modelo-de-dados.md` para a estrutura física e o estado de execução atual.

> **Distinção reconhecida, ainda não modelada:** o acabamento físico de uma Card (Finish) e o produto/origem de distribuição de uma impressão específica (ex.: um booster comum vs. uma coleção promocional) são dimensões conceitualmente independentes. Hoje o domínio representa apenas o acabamento. Uma futura entidade de "origem de impressão", vinculada a Card Finish, é uma necessidade reconhecida — ainda não modelada.

---

## Card Category (Categoria da Carta)

### O que é?

Classifica a natureza editorial primária de uma Card pertencente a um Set, respondendo: *esta posição oficial do Set representa uma carta de Pokémon ou uma carta de Treinador?*

Valores no escopo do catálogo numerado de um Set:

- **Pokémon**;
- **Trainer (Treinador)** — exige obrigatoriamente uma Trainer Subcategory (ver abaixo).

---

### O que não é?

Card Category não representa:

- uma Rarity;
- um Finish;
- um Energy Type (tipo elemental de uma carta de Pokémon — ver Energy Type, abaixo; não confundir com cartas de Energia, que não fazem parte deste catálogo numerado);
- uma relação direta e universal com a entidade Pokémon — apenas Cards de categoria Pokémon possuem essa referência (obrigatória nesse caso; inexistente para Trainer).

---

### Qual problema resolve?

Evita a suposição incorreta de que toda Card representa um Pokémon. Cards como Acerola (Supporter), Poké Pad (Item) e Torre Prisma (Stadium) não representam nenhum Pokémon, mas são Cards válidas do catálogo.

---

### Decisão de Escopo — Cartas de Energia

Cartas de Energia **não são tratadas como Cards do Set** neste modelo, porque, segundo a regra definida para o domínio, elas:

- não ocupam uma posição na numeração oficial do Set;
- não participam da contagem `001/132` até `188/132` (Official Card Count);
- não influenciam o progresso de conclusão do Set;
- não aparecem como itens obrigatórios no checklist oficial da coleção.

Consequentemente, Card Category possui apenas dois valores neste catálogo: **Pokémon** e **Trainer**. Isso não significa que uma carta física de Energia nunca poderá ser controlada pelo sistema — apenas que ela não pertence a este catálogo numerado. Caso futuramente exista necessidade concreta de controlar Energias avulsas, elas deverão ser avaliadas em outro contexto (ex.: uma entidade específica de acessório/suplemento), não antecipado por este documento.

> **Nota:** cartas de categoria Energy já aparecem cadastradas com posição numerada em alguns Sets, o que está em tensão com esta decisão de escopo. Pendência sinalizada, não resolvida unilateralmente — ver `05-modelo-de-dados.md` para o estado atual dos dados.

---

### Regra de Integridade Conceitual

```text
Se Card Category = Pokémon:
    Trainer Subcategory deve ser vazio;
    referência a Pokémon é obrigatória.

Se Card Category = Trainer:
    Trainer Subcategory é obrigatória;
    referência a Pokémon deve ser vazia.
```

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

## Trainer Subcategory (Subcategoria de Treinador)

### O que é?

Classifica uma Card de categoria Trainer em uma das famílias oficiais de cartas de Treinador.

Valores:

- Item;
- Supporter (Apoiador);
- Stadium (Estádio);
- Tool (Ferramenta).

---

### Qual problema resolve?

Permite diferenciar as regras de jogo aplicáveis dentro da família Trainer (ex.: um Stadium possui efeito permanente em campo; um Item ou Supporter possui apenas um efeito pontual).

---

### Relacionamentos

```text
Card (Category = Trainer)
 N
 │
 └── 1 Trainer Subcategory
```

Obrigatória quando, e somente quando, a Card Category for Trainer.

---

## Pokémon

### O que é?

Representa a identidade mínima do personagem/espécie Pokémon (ex.: Bulbasaur), referenciada por Cards de categoria Pokémon. Entidade de referência (Identity Entity), reutilizada por todas as Cards que representam aquele mesmo Pokémon em diferentes Sets (Princípio da Reutilização Editorial, AP-014).

O Pokémon existe independentemente do Pokémon TCG — mas o Project Mimikyu modela apenas o subconjunto mínimo necessário ao colecionismo, não o domínio completo da franquia (ver ADR-011).

Características conceituais mínimas:

- id (identificador);
- national_dex_number (número na Pokédex Nacional);
- canonical_name (nome canônico).

---

### O que não é?

Pokémon não representa nem armazena:

- uma Card específica — uma mesma espécie corresponde a muitas Cards distintas, uma por Set em que aparece;
- HP, ataques, fraqueza, resistência, custo de recuo ou estágio evolutivo **impressos** — esses valores pertencem à Card (ou à Pokémon Card Details, ver abaixo), pois uma mesma espécie pode ter valores diferentes impressos em Cards diferentes (ex.: dois "Bulbasaur" em Sets distintos podem ter HP diferente);
- dados de batalha dos jogos eletrônicos (estatísticas, movimentos aprendidos por nível, habitat, natureza, gerações/regiões) — fora do escopo do Project Mimikyu, salvo se algum desses dados vier a ter valor direto e concreto para o colecionismo;
- uma categoria de Card (ver Card Category, acima) — nem toda Card possui um Pokémon associado.

---

### Qual problema resolve?

Evita dois extremos: (1) modelar toda a franquia Pokémon, transformando o sistema em uma Pokédex completa e desviando do produto; e (2) tratar o nome do Pokémon apenas como texto solto em cada Card, o que impediria relacionar todas as Cards do mesmo Pokémon (ex.: pesquisar todas as cartas do Pikachu, montar uma coleção temática de Charizard, ou construir uma Pokédex pessoal do usuário).

O equilíbrio adotado é uma entidade Pokémon mínima e orientada ao colecionismo: *uma informação sobre Pokémon só entra no Project Mimikyu quando for necessária para identificar, pesquisar, agrupar ou analisar Cards e coleções* (ADR-011).

---

### Relacionamentos

```text
Pokémon
 1
 │
 └── N Card (apenas Cards de categoria Pokémon; pokemon_id obrigatório)
```

---

## Illustrator (Ilustrador)

### O que é?

Representa a pessoa responsável pela arte de uma Card. Entidade de referência (Identity Entity), reutilizada por todas as Cards ilustradas pela mesma pessoa (aplicação do Princípio da Reutilização Editorial, AP-014).

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

Representa o tipo elemental de uma Card de categoria Pokémon, quando aplicável (ex.: Água, Fogo, Planta, Elétrico). Entidade de referência (Reference Data), compartilhada por milhares de Cards (aplicação do Princípio da Reutilização Editorial, AP-014).

---

### O que não é?

Não deve ser confundido com Card Category = Energy (cartas de Energia), que estão fora do escopo do catálogo numerado (ver "Decisão de Escopo — Cartas de Energia", na seção Card Category). Energy Type é um atributo elemental de uma carta de Pokémon; cartas de Energia são um tipo de carta inteiramente diferente.

---

### Relacionamentos

```text
Energy Type
 1
 │
 └── N Card (Pokémon Card Details)
```

*Estrutura detalhada de características pendente — a ser avaliada em ciclo futuro de documentação.*

---

## Card Details (Detalhes Específicos da Carta)

### O que é?

Estrutura que agrupa as informações específicas de uma Card, que variam conforme sua Card Category — em oposição às informações comuns a toda Card (Set, Number, Category, Rarity, Regulation Mark, Illustrator, etc.).

Para o Pokémon TCG, assume duas formas:

```text
Card
 │
 └── Card Details (Pokémon TCG)
        ├── Pokémon Card Details (quando Category = Pokémon)
        └── Trainer Card Details (quando Category = Trainer)
```

**Pokémon Card Details** pode conhecer: HP, Stage (estágio evolutivo), Attacks, Ability, Weakness, Resistance, Retreat Cost, Energy Type.

**Trainer Card Details** conhece apenas: Effect (texto de efeito). Algumas regras podem variar conforme a Trainer Subcategory, mas continuam sendo Cards da categoria Trainer.

---

### O que não é?

Card Details **não é um conceito genérico da plataforma**. Ele pertence especificamente ao módulo Pokémon TCG:

```text
Catalog Domain (genérico, multi-TCG)
├── Game
├── Expansion
├── Set
└── Card

Pokémon TCG Domain (específico)
├── Pokémon
├── Pokémon Card Details
└── Trainer Card Details
```

`Card → Pokémon` **não deve ser uma regra universal da plataforma** — essa associação pertence exclusivamente ao módulo específico do Pokémon TCG. Isso preserva a expansão futura para outros TCGs (Magic, Lorcana, One Piece) sem obrigá-los a adotar conceitos como Pokémon, HP ou evolução (ver ADR-003, AP-010 e ADR-011).

---

### Nota sobre estruturação de dados

Os campos de mecânica de jogo listados acima (HP, Attacks, Ability, Weakness, Resistance, Retreat Cost, Evolution Stage, texto de regras) não são estruturados no banco de dados — permanentemente, não apenas na primeira versão — porque o Project Mimikyu é uma plataforma de colecionismo, não um banco de dados de mecânicas de jogo (AP-017). `Pokémon Card Details`/`Trainer Card Details` permanecem como arquitetura válida, sem conteúdo de jogo concreto planejado. Ver ADR-012 e `07-catalogo-editorial.md` para o critério de estruturação vs. conteúdo disponível apenas na imagem oficial.

---

## Collection Item (Item da Coleção)

### O que é?

Representa um exemplar físico individual e identificável de uma Card, pertencente ou anteriormente pertencente a um colecionador. Substitui o termo provisório "Inventory Item" (ver ADR-013): o Project Mimikyu é uma plataforma de colecionismo, não um sistema de estoque, e o nome deve refletir isso.

Cada cópia física possui identidade própria, mesmo quando indistinguível de outra:

```text
ITEM_0003456
ITEM_0003457
```

Ambos podem representar a mesma combinação editorial (`Bulbasaur 001/132`, `Standard Foil`, `Portuguese`, `Near Mint`) e, ainda assim, são dois Collection Items distintos — com origem, preço, condição, localização, histórico e destino potencialmente diferentes.

---

### O que não é?

Collection Item não representa:

- uma posição no Set (ver Card);
- uma Card do catálogo;
- um acabamento disponível (ver Card Finish);
- uma quantidade agregada;
- uma linha genérica de estoque.

Não deve ser representado como:

```text
Card: Bulbasaur 001/132
Quantity: 3
```

Mas sim como três registros individuais:

```text
ITEM_0003456
ITEM_0003457
ITEM_0003458
```

---

### Qual problema resolve?

Permite controlar individualmente: aquisição, custo, condição, idioma, acabamento, autenticação, graduação (grading), armazenamento, movimentação, venda, troca, perda e descarte de cada cópia física.

Também permite distinguir, entre exemplares de uma mesma Card: a cópia principal exibida na coleção, uma cópia repetida disponível para troca, uma cópia lacrada, uma cópia enviada para grading, e uma cópia já vendida.

---

### Relação com o Catálogo

```text
Card
 │
 └── Card Finish
        │
        └── N Collection Item
```

Cada Collection Item referencia uma combinação editorial válida de Card + Finish + Language (ver Card Finish, acima):

```text
Collection Item: ITEM_0003456
Card: Bulbasaur 001/132
Finish: Standard Foil
Language: Portuguese
```

O acabamento físico é uma característica do exemplar impresso — por isso o Collection Item referencia a Card Finish, não a Card diretamente (ver "Relacionamentos", na seção Card Finish).

---

### Por que o Idioma pertence ao Collection Item

O conteúdo editorial da Card é o mesmo em português e em inglês — essa variação pertence à Card Translation (ver acima). O exemplar físico, no entanto, foi impresso em um idioma concreto: é essa informação que o campo `language` do Collection Item identifica.

Conceitualmente, o Collection Item poderá vir a referenciar a Card Translation correspondente, em vez de armazenar o idioma como um valor solto — essa decisão permanece em aberto para a modelagem lógica.

---

### Grupos Conceituais de Informação (preliminar)

Para evitar que o Collection Item acumule responsabilidades demais, suas informações são organizadas conceitualmente em quatro grupos. Esta divisão é preliminar: algumas dessas informações provavelmente se tornarão entidades relacionadas próprias durante a modelagem lógica, e não campos diretos do Collection Item.

**1. Identity (Identidade)** — define qual exemplar é esse: id, owner, card, finish, language.

**2. Physical State (Estado Físico)** — descreve a condição atual: condition, grading_status, authentication_status, sealed_status.

**3. Collection Role (Papel na Coleção)** — descreve como o colecionador utiliza aquele exemplar: primary_collection_copy, duplicate, available_for_trade, available_for_sale, reserved.

**4. Lifecycle (Ciclo de Vida)** — descreve sua trajetória: acquisition, storage, movement, grading, sale, trade, disposal.

---

### Estado Atual vs. Histórico

Há uma distinção conceitual importante entre "onde o item está agora" e "por onde o item já passou":

- o estado atual (ex.: localização de armazenamento atual) pertence ao próprio Collection Item;
- o histórico (ex.: movimentações anteriores) pertence a entidades de histórico relacionadas, ainda não modeladas em detalhe (ver Storage Location, abaixo).

O mesmo vale para a posse: uma venda não deve simplesmente apagar o usuário anterior — ela encerra a posse e preserva o histórico.

---

### Ownership Status e Availability Status

São duas dimensões distintas, que não devem ser combinadas em uma única lista de valores:

- **Ownership Status (Status de Propriedade)** — responde se o exemplar ainda pertence ao usuário (ex.: `OWNED`, `SOLD`, `DISPOSED`).
- **Availability Status (Status de Disponibilidade)** — responde se o exemplar está disponível para alguma finalidade (ex.: `AVAILABLE_FOR_TRADE`, `RESERVED`).

Exemplo:

```text
Ownership Status: OWNED
Availability Status: AVAILABLE_FOR_TRADE
```

Misturar as duas dimensões em uma única lista (ex.: `SOLD`, `AVAILABLE_FOR_TRADE`, `IN_BINDER` juntos) produziria ambiguidade, pois representam perguntas diferentes.

---

### Regra de Identidade

A identidade de um Collection Item é técnica e permanente — não é alterada por mudanças de condição, armazenamento ou disponibilidade.

Exemplo: `ITEM_0003456` pode sair do binder, ser enviado para grading, retornar encapsulado e depois ser vendido — continua sendo o mesmo exemplar físico, com a mesma identidade.

---

### Relacionamentos

```text
User (Usuário)
 1
 │
 └── N Collection Item
        ├── Card
        ├── Card Finish
        ├── Language
        ├── Physical Condition
        ├── Ownership Status
        ├── Availability Status
        └── Current Storage Location
```

Entidades de histórico relacionadas a este conceito (estrutura detalhada pendente de ciclo futuro de documentação): Acquisition, Movement, Grading Submission, Trade, Sale, Valuation.

---

## Storage Location

*Documentação pendente.*

---

## User Collection

> **Nota:** este termo provisório parece ter sido absorvido pela entidade Collection (ver acima), já definida como pertencente a um usuário (`owner_id`) e independente do catálogo editorial (ver ADR-014). Mantido aqui como stub, sem exclusão, até confirmação explícita de que não há distinção adicional pretendida entre os dois termos.

*Documentação pendente — aguardando confirmação.*

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Estrutura inicial do modelo conceitual. |
| 1.1 | Padronização do cabeçalho para consistência com os demais documentos centrais. |
| 1.2 | Corrigido o exemplo de numeração da Card; adicionadas as Métricas de Contagem do Catálogo e a entidade Card Translation. |
| 1.3 | Resolvida a identidade de variante: Full Art/Illustration Rare/Special Illustration Rare/Hyper Rare/Gold/Rainbow passam a ser tratadas como Cards independentes, não variantes (ADR-009). |
| 1.4 | "Card Variant" substituído por três conceitos: Rarity, Finish e Card Finish, com base em documento oficial do ME1 (ADR-010, substitui ADR-009). |
| 1.5 | Adicionadas as entidades Card Category, Pokémon, Illustrator e Energy Type; relação Card↔Pokémon tornada condicional à Card Category. |
| 1.6 | Resolvida a taxonomia de Card Category (Pokémon/Trainer); adicionada Trainer Subcategory; Pokémon finalizado como entidade mínima; adicionado o padrão Card Details (ADR-011/ADR-012). |
| 1.7 | Renomeado "Inventory Item" para "Collection Item" em todo o documento (ADR-013); adicionada a seção completa de Collection Item. |
| 1.8 | Adicionadas as entidades Collection e Collection Entry, pertencentes ao colecionador e independentes do catálogo editorial (ADR-014). |
| 1.9 | Nota de nomenclatura física do Set (`SET` é palavra reservada do SQL; tabela física `card_set`). |
| 1.10–1.11 | Expandida e finalizada a seção Expansion: código editorial, ordem de lançamento, unicidade por Game, decisão de não incluir campo `status`. |
| 1.12–1.16 | Corrigido que a identidade visual (logotipo/símbolo) pertence ao Set, não à Expansion; adicionado o Set do tipo Promocional (Black Star Promos) e sua convenção de preenchimento (ADR-015). |
| 1.17–1.20 | Iniciada e avançada a modelagem física da Card; Rarity promovida de atributo textual a entidade de referência própria, vinculada ao Game. |
| 1.21–1.25 | Entidade Rarity finalizada: catálogo real de raridades, campo de identificador do símbolo visual, `PROMO` confirmada como raridade oficial. |
| 1.26–1.27 | Avaliada e revertida uma proposta de identidade editorial de Card independente de Set; decisão final mantém Card vinculada a um Set específico; adicionada a entidade Card Category. |
| 1.28–1.32 | Refinado o modelo de Card (numeração impressa, ordenação no checklist, decisão de idioma do nome); adicionadas Card Variant Type e Card Variant como estrutura de acabamentos colecionáveis, completando o Catálogo Editorial. |
| 1.33–1.36 | Adicionada a entidade Card Asset Type / Card Asset, para ativos digitais (imagens e futuros formatos) da Card, independente de Card Variant. |
| 1.37–1.38 | Catálogo de Card Variant Type expandido de 6 para 12 tipos, após identificar que a reversa holográfica de determinada coleção segue padrões distintos por linha evolutiva do Pokémon, não um padrão único genérico. |
| 2.0 | **Reestruturação editorial do documento.** Removido o conteúdo operacional acumulado ao longo dos ciclos anteriores (números de Query, SQL/DDL, versões de Seed, confirmações de execução, propostas rejeitadas mantidas na íntegra, citações de sessão, discussões não concluídas registradas linha a linha) — esse conteúdo permanece preservado em `05-modelo-de-dados.md` (camada física e de execução), `06-pipeline-importacao.md` (estratégias de importação) e no histórico de decisões do projeto. O documento passa a refletir apenas o modelo conceitual vigente de cada entidade: definição, características, relacionamentos e regras de negócio atuais. Histórico de revisões anteriores a esta reescrita comprimido para uma linha por versão (ou faixa de versões relacionadas). |
