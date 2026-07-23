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
| **Documentos Relacionados** | `adr/ADR-003-multi-game-architecture.md`, `adr/ADR-004-set-identity.md`, `adr/ADR-005-catalog-language-model.md`, `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-007-card-translation-model.md`, `adr/ADR-008-external-catalog-data-sources.md`, `adr/ADR-009-card-variant-scope.md`, `adr/ADR-010-card-rarity-and-finish-model.md`, `adr/ADR-011-pokemon-tcg-domain-scope.md`, `adr/ADR-012-structured-vs-visual-card-data.md`, `adr/ADR-013-collection-item-identity-model.md`, `adr/ADR-014-collection-and-collection-entry-model.md`, `02-architecture-principles.md` (AP-013, AP-014, AP-015), `standards/STD-002-domain-modeling.md`, `07-catalogo-editorial.md`, `architecture/ubiquitous-language.md` |

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

### Características Conceituais (preliminar)

- id;
- owner_id (usuário dono da coleção);
- name;
- description;
- collection_type (`SET_BASED` | `CUSTOM`);
- reference_set_id (obrigatório quando `SET_BASED`; nulo quando `CUSTOM`).

Esta é uma primeira aproximação; a estrutura definitiva será avaliada durante a modelagem lógica.

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

### Mecanismos de Inclusão (preliminar)

- **Manual Membership (Inclusão Manual)** — o colecionador adiciona manualmente Cards ou Pokémon à coleção.
- **Rule-Based Membership (Inclusão por Regra)** — entradas geradas automaticamente por regras estruturadas (ex.: `rarity = ILLUSTRATION_RARE`, `pokemon = PIKACHU`, `category = TRAINER`, `artist = ...`).

Para a primeira implementação estão previstos apenas Manual Membership e a geração automática simples de Official Set Collections. Um motor completo de regras (Rule-Based Membership) fica para um ciclo futuro, evitando modelagem excessiva antes de uma necessidade concreta (AP-004).

---

### Características Conceituais (preliminar)

- id;
- collection_id;
- card_id (nullable — usado quando Card Target);
- pokemon_id (nullable — usado quando Subject Target);
- display_order;
- notes.

Regra: uma Collection Entry deve apontar para Card ou para Pokémon, nunca para ambos simultaneamente. Esta é uma primeira aproximação; no modelo lógico, talvez sejam duas entidades especializadas, evitando campos nulos — decisão não fechada nesta versão.

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
- um produto comercial.

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
- identidade visual;
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

O código de uma Expansion é editorial e internacional — não muda entre idiomas (ex.: `SV` continua sendo `SV` em qualquer idioma). O nome pode ser localizado futuramente, quando houver necessidade, seguindo o mesmo padrão já estabelecido para conteúdo editorial em Card Translation (ver ADR-007). Este padrão — código internacional, nome localizável — tende a se repetir em todo o catálogo editorial (ver também `standards/STD-001-database-standards.md`, Seção 5).

### Ordem de Lançamento

A ordem de lançamento (`release_order`) é um número inteiro simples, refletindo a sequência editorial conhecida (ex.: Base, Neo, e-Card, EX, Diamond & Pearl, Black & White, XY, Sun & Moon, Sword & Shield, Scarlet & Violet). Foi deliberadamente mantida simples — sem reservar intervalos entre valores — porque uma renumeração completa é considerada aceitável no raro caso de uma nova Expansion precisar se inserir entre duas antigas por necessidade editorial (reedição, linha paralela etc.).

### Unicidade por Game

O código e a ordem de lançamento de uma Expansion são únicos **dentro do respectivo Game**, não globalmente — `UNIQUE (game_id, code)` e `UNIQUE (game_id, release_order)`, nunca `UNIQUE (code)` isoladamente. Isso decorre diretamente da arquitetura multi-TCG (ver ADR-003): outro Trading Card Game pode perfeitamente utilizar um código como `SV` para outra finalidade. Este é o primeiro exemplo concreto de uma regra que provavelmente se repetirá em todo o catálogo — toda unicidade de código editorial deve respeitar o contexto do Game.

### Sem Status

Expansion não possui um campo `status`. Nenhum caso de uso concreto foi identificado até o momento (ex.: distinguir Expansions "anunciadas", "lançadas" ou "canceladas") — aplicação direta do Princípio da Simplicidade Inicial (ver AP-004). Se essa necessidade surgir, o campo será adicionado por uma nova migration, não antecipado agora.

### Identidade Visual — Correção: a logo pertence ao Set, não à Expansion

**Correção de modelagem (registrada ao concluir o modelo do Set).** Uma versão anterior desta documentação atribuía um logotipo próprio (`logo_url`) à Expansion. Ao modelar formalmente o Set, ficou claro que a identidade visual — logotipo completo e símbolo pequeno usado nas Cards — pertence ao **Set**, não à Expansion: cada Set dentro de uma mesma Expansion tem seu próprio logotipo editorial (ex.: o logotipo de `ME1` é diferente do logotipo de `ME2`, ainda que ambos pertençam à mesma Expansion `Mega Evolution`). A Expansion, como agrupamento cronológico/temático, não possui identidade visual própria conhecida até o momento — se essa necessidade surgir, será tratada como uma nova característica, não reintroduzida por padrão.

Esta correção fecha a pendência anteriormente registrada em `05-modelo-de-dados.md` sobre a ausência de `logo_url` no DDL executado de `expansion`: não se tratava de um descuido a corrigir por `ALTER TABLE`, e sim de um atributo que nunca deveria pertencer a esta entidade. Ver seção "Set", abaixo, para o tratamento correto de `logo_url`/`symbol_url`.

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

O idioma pertence ao exemplar físico do usuário (Collection Item).

### Classificação Editorial

Todo Set possui uma classificação editorial.

São reconhecidos três tipos:

- Regular Set;
- Special Set;
- Promotional Set (Black Star Promos — ver "Card Set Promocional", abaixo).

A classificação não altera a natureza da entidade.

Um Set Especial ou Promocional continua sendo um Set.

A classificação editorial é uma característica do Set e não justifica a criação de entidades distintas — inclusive para o caso promocional, que poderia parecer, à primeira vista, um conceito diferente (ver ADR-015).

### Card Set Promocional (Black Star Promos)

Existe um conjunto de cartas — as **cartas promocionais (Black Star Promos)** — diretamente ligado a uma Expansion, mas sem as características de um Set editorial tradicional: não possui necessariamente código ou nome oficial próprio, não ocupa uma posição fixa na sequência de Sets, e sua quantidade de cartas não é fechada — cresce ao longo do tempo, conforme novos produtos daquela Expansion são lançados.

Em vez de criar uma entidade separada (o que obrigaria a Card a ter dois relacionamentos possíveis com sua entidade-pai, propagando duplicidade para coleção, inventário, traduções, imagens e importações), a série promocional é registrada como um Set comum, do tipo `PROMO`, vinculado à sua Expansion — seguindo uma **convenção fixa de preenchimento**, não campos opcionais:

- **Código** = código da Expansion + `0` (ex.: `ME0`);
- **Nome** = código da Expansion + `Black Star Promos` (ex.: `ME Black Star Promos`);
- **Posição na sequência** = sempre a primeira da Expansion (`release_order = 1`, deslocando os demais Sets);
- **Data de lançamento** = a mesma data do primeiro Set regular/especial da Expansion;
- **Quantidade base e quantidade total** = sempre iguais entre si, representando a quantidade atualmente conhecida de cartas promocionais (não uma quantidade editorial fechada) — cresce conforme novas cartas são catalogadas.

Com essa convenção, todos os valores de uma série promocional são determináveis a partir da Expansion à qual pertence — não é necessário relaxar nenhuma das colunas do Set para `NULL`. Ver ADR-015 para a decisão completa, incluindo a proposta intermediária (campos opcionais) que foi avaliada e descartada.

**Executado.** Para a Expansion `ME`, o Set promocional real é `ME0 — ME Black Star Promos`, com `base_set_size = total_set_size = 89` (quantidade informada por Fabrício no momento do cadastro — cresce conforme novas cartas promocionais são catalogadas). ADR-015 recomendava um índice único de banco para impedir mais de uma série promocional por Expansion; a migration originalmente executada não incluiu esse índice. Com a adoção do Princípio da Fonte Canônica (STD-001, Seção 10), esse índice já está presente na Query canônica `120` v2.0 — mas seu status no banco físico atual (construído pelo caminho antigo, anterior à consolidação) ainda não foi confirmado; até lá, a regra continua sendo verificada apenas por validação periódica (ver `05-modelo-de-dados.md`, seção Set).

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

### Unicidade por Expansion

O código e a ordem de lançamento de um Set são únicos **dentro da respectiva Expansion**, não globalmente — `UNIQUE (expansion_id, code)` e `UNIQUE (expansion_id, release_order)`, nunca `UNIQUE (code)` isoladamente. Mesmo padrão de unicidade escopada já estabelecido para Expansion dentro de Game (ver acima, "Unicidade por Game"; ADR-003).

### Identidade Visual (logo_url, symbol_url)

O Set possui duas identidades visuais distintas: um logotipo completo (`logo_url`) e um símbolo pequeno usado nas Cards (`symbol_url`). Correção importante: uma versão anterior desta documentação havia atribuído `logo_url` à Expansion — isso foi corrigido (ver seção "Expansion", acima, "Identidade Visual — Correção"). A logo pertence ao Set porque cada Set tem sua própria identidade visual, mesmo dentro da mesma Expansion.

Assim como para Expansion, os valores serão preenchidos por **importação automática via API**, com os arquivos armazenados no Supabase (Storage) — não por preenchimento manual (ver `06-pipeline-importacao.md`, seção "Importação de Ativos Visuais"). A estrutura física exata (colunas simples vs. referência a uma entidade de ativo) depende da mesma definição pendente do pipeline de ativos visuais, e por isso `logo_url`/`symbol_url` não fazem parte do modelo físico inicial do Set — ver `05-modelo-de-dados.md`, seção Set — "Campos que Não Incluiremos Agora".

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

### Status — Decisão: sem campo `status` por enquanto

**Hipótese anterior superada.** Uma versão anterior desta documentação cogitava um campo `status` com valores como `announced`/`released`. Ao modelar formalmente o Set, decidiu-se **não incluir `status`**: o campo `release_date` (opcional, `NULL` permitido) já resolve o caso de uso inicial — um Set sem `release_date` preenchida é, por definição, um Set apenas anunciado; um Set com `release_date` preenchida está lançado. Aplicação direta do Princípio da Simplicidade Inicial (AP-004) — não antecipar um campo de estado quando o dado já existente resolve a necessidade concreta.

Se uma necessidade real de status explícito surgir no futuro (ex.: `cancelled`), o campo será adicionado por uma nova migration, não antecipado agora.

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
- identidade visual própria (logotipo e símbolo — ver "Identidade Visual", acima; campos ainda não incluídos no modelo físico inicial).

Esta lista já reflete a modelagem lógica e física aprovada (ver `05-modelo-de-dados.md`, seção Set) — não é mais apenas uma projeção conceitual.

> **Nota sobre nomenclatura física:** `SET` é uma palavra reservada do SQL (PostgreSQL). Para evitar ambiguidade, a tabela física correspondente ao conceito Set é nomeada `card_set` (ver `standards/STD-001-database-standards.md`, Seção 2). O conceito de domínio continua sendo chamado de Set na documentação e na aplicação.

### Responsabilidade sobre Quantidades e Data de Lançamento (Set vs. Expansion)

Uma Expansion agrupa vários Sets, e cada Set possui sua própria numeração e quantidade de cartas — por isso essas informações pertencem ao Set, não à Expansion:

- **Base Set Count** e a quantidade oficial total de cartas são características do Set (ver acima e "Official Card Count", na seção Card).
- A quantidade de cartas secretas (posições acima do conjunto base) é **derivada**, não armazenada: `secret_set_size = total_set_size - base_set_size`. Armazená-la redundantemente arriscaria inconsistência.
- A **data de lançamento** também pertence ao Set (`release_date`), podendo ser nula para Sets apenas anunciados. A Expansion não possui uma data de lançamento própria armazenada — quando necessário, pode ser derivada como a menor `release_date` entre seus Sets.

> **Modelo executado (atualiza a prévia anterior):** o modelo lógico e físico do Set foi formalmente definido, aprovado e **executado no Supabase**, com os cinco primeiros Sets da Expansion `ME` cadastrados e validados contra fontes oficiais. Atributos: `id`, `expansion_id`, `code`, `name`, `set_type`, `release_order`, `release_date`, `base_set_size`, `total_set_size`, `created_at`, `updated_at` — sem `secret_set_size` (derivado) e, por ora, **sem** `logo_url`/`symbol_url`: embora a identidade visual pertença ao Set (ver "Identidade Visual", acima — corrigindo a atribuição anterior à Expansion), esses dois campos dependem de uma decisão ainda pendente sobre o pipeline de ativos visuais e por isso ficam fora do modelo físico (ver `05-modelo-de-dados.md`, seção Set). `set_type` foi ampliado de `REGULAR`/`SPECIAL` para incluir também `PROMO` (ver "Card Set Promocional", acima; ADR-015) — migration `122` executada, com o Set promocional `ME0` cadastrado. A Query de validação (`920`, versão 2.0) foi executada e confirmada por Fabrício ("Tudo ok") — pacote técnico da entidade concluído. Único item aberto: reescrever a Query de Seed `820` para incluir o Set promocional no snapshot completo da Expansion (ver `05-modelo-de-dados.md`, seção Set).

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

Informações comuns a toda Card, independentemente da categoria:

- **Card Category** — classifica a Card (Pokémon ou Trainer). Ver seção própria, abaixo.
- **Card Translation** — conteúdo editorial por idioma. Ver seção própria, acima.
- **Rarity** — classificação de raridade. Ver seção própria, acima.
- **Card Finish** — acabamentos físicos disponíveis. Ver seção própria, acima.
- **Illustrator** — o ilustrador responsável pela arte da Card; entidade de referência, reutilizada por todas as Cards ilustradas pela mesma pessoa. **Correção (ver "Modelagem Física — Discussão Iniciada," abaixo):** um lote de modelagem física reclassificou Illustrator para o nível de Card Printing, não de Card — a autoria pertence à impressão visual concreta (que pode variar entre traduções com artes distintas sob o mesmo número), não à posição abstrata do checklist. Proposto, ainda não aprovado por Fabrício.

Informações específicas por categoria, agrupadas em Card Details (ver seção própria, abaixo): quando a Card Category for Pokémon, a Card referencia um Pokémon e conhece HP, Stage, Attacks, Ability, Weakness, Resistance, Retreat Cost e Energy Type (Pokémon Card Details); quando for Trainer, conhece apenas Effect (Trainer Card Details). Cards de categoria Trainer não possuem referência a Pokémon.

> **Importante:** nem toda Card representa um Pokémon. A hipótese inicial de que toda Card se relacionaria diretamente com um Pokémon foi identificada como um erro de modelagem — uma confusão entre o domínio Pokémon (o personagem/espécie) e o domínio Pokémon TCG (o jogo de cartas). Cards de categoria Trainer (ex.: Acerola — Supporter; Poké Pad — Item; Torre Prisma — Stadium) não representam nenhum Pokémon. Essa relação é, portanto, condicional à Card Category, não universal (ver ADR-011).

> **Atualização (ver AP-017 e "Modelagem Física — Discussão Iniciada," abaixo):** Fabrício determinou diretamente que HP, Stage, Attacks, Ability, Weakness, Resistance, Retreat Cost e Energy Type — todo o conteúdo de "Pokémon Card Details" listado acima — não serão estruturados no banco de dados, por serem mecânica de jogo, não informação de colecionismo. Permanecem visíveis apenas na imagem oficial da Card (ADR-012). O padrão Card Details / Pokémon Card Details / Trainer Card Details continua válido como arquitetura (ADR-011), mas sem conteúdo concreto planejado.

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

### Modelagem Física — Discussão Iniciada (Query 130), Não Concluída

**Nota de processo:** a modelagem física da Card (rumo à Query `130`) começou a ser discutida diretamente no par Fabrício/ChatGPT responsável pela execução real no Supabase, em paralelo a este documento. O material recebido cruza a discussão real com as decisões já consolidadas aqui. Um segundo lote avançou substancialmente a discussão (resumido abaixo), mas ainda não inclui SQL executado nem uma confirmação explícita de Fabrício sobre os pontos ainda em aberto — nada nesta seção deve ser tratado como definitivo, e nenhuma tabela física de Card deve ser criada a partir dela ainda.

**Confirmado — consistente com decisões já registradas neste documento, sem necessidade de nova ADR:**

- Identidade de negócio = `card_set_id` + `card_number`, mesma regra de "Set + Número da Card" (ADR-004, ver "Identidade," acima).
- A numeração exibida (`001/132`) é derivada de `card.card_number` + `card_set.base_set_size`/`total_set_size`, nunca armazenada de forma redundante — mesmo princípio já aplicado ao denominador (ver "Identidade," acima).
- Fronteira Card vs. Collection Item confirmada: preço pago, quantidade possuída, localização física, grading e notas particulares pertencem ao Collection Item, nunca à Card (mesma separação de ADR-006 e "Atributos e Relações da Card," acima).
- A divisão em "conteúdo comum a toda Card" vs. "conteúdo específico por categoria" confirma o padrão já registrado como Card Details / Pokémon Card Details / Trainer Card Details (ver "Card Details," abaixo; ADR-011, ADR-012).

**Modelo em quatro camadas (proposto pelo par Fabrício/ChatGPT, ainda não aprovado por Fabrício nem executado):**

```text
Game
 ↓
Expansion
 ↓
Card Set
 ↓
Card
 ↓
Card Printing
 ↓
Card Variant
 ↓
Collection Item
```

A regra prática proposta: *"Produto diferente não cria uma variante. Carta fisicamente diferente cria uma variante."* Um mesmo produto de origem (booster, box, coleção especial, produto promocional) distribuindo a mesma carta fisicamente idêntica não gera uma nova Card Variant — a origem de distribuição poderia ser registrada futuramente em uma entidade separada (`product`/`card_variant_distribution`, não modelada ainda) ou via a proveniência de um Collection Item específico.

**Critério proposto para decidir se uma diferença gera nova Card, nova Card Printing ou nova Card Variant:**

| Diferença | Nova Card | Nova Printing | Nova Variant |
|---|---|---|---|
| Número diferente | Sim | — | — |
| Set diferente | Sim | — | — |
| Idioma diferente | Não | Sim | Não |
| Nome traduzido | Não | Sim | Não |
| Holo x Reverse | Não | Não | Sim |
| Selo promocional | Não | Não | Sim |
| Produto de origem diferente | Não | Não | Não |
| Ilustração diferente com mesmo número | Depende da identidade editorial (ver abaixo) | Possivelmente | Possivelmente |
| Texto corrigido ou errata impressa | Não | Sim ou variante editorial | Não necessariamente |

O caso "mesma numeração, ilustração/arte diferente" foi testado explicitamente contra a premissa `card_set_id + card_number identifica unicamente uma carta editorial?`. Duas alternativas foram avaliadas: (A) tratar como duas Cards distintas, exigindo um discriminador adicional na chave (ex. `edition_code`) — descartada porque esse código pode não existir oficialmente; (B) manter Card como a posição editorial abstrata do checklist, e tratar a diferença de arte como uma Card Printing diferente sob a mesma Card — **recomendada**. Sob essa definição, a chave `UNIQUE (card_set_id, card_number)` permanece válida, desde que Card seja entendida como *"a posição editorial numerada no checklist do Set, e não cada impressão física distinta."*

**Card — definição e atributos mínimos (APROVADOS por Fabrício; execução ainda pendente):**

> Uma Card representa uma posição oficial e única no checklist de um Card Set.

A Card `ME1 #003` existe uma única vez na tabela `card`, mesmo que possua impressão em português, impressão em inglês, versão Holofoil, versão com selo promocional e várias cópias físicas na coleção — todas essas variações pertencem às camadas abaixo dela.

**Modelo mínimo final, aprovado por Fabrício** ("Excelente. Temos a definição agora. Vamos seguir com a execução!"):

```text
card
  id             UUID
  card_set_id    UUID
  rarity_id      UUID
  card_number    VARCHAR(30)
  card_order     INTEGER
  category_code  (formato ainda em avaliação — ver abaixo)
  created_at     TIMESTAMPTZ
  updated_at     TIMESTAMPTZ
```

- `card_number` proposto como texto, não inteiro — para preservar zeros à esquerda (`003`), prefixos (`TG01`), sufixos e numerações alfanuméricas de outros TCGs/formatos editoriais futuros, sem conversão.
- `card_order` proposto como um campo novo, tecnicamente distinto de `card_number`: representa a posição sequencial no checklist (para ordenação correta — comparar texto ordenaria `001, 010, 011, 002` incorretamente) e sustenta numerações futuras não numéricas (`TG01`, `SV01`) sem regras especiais de conversão. `card_number` = identidade editorial exibida; `card_order` = ordenação técnica.
- `rarity_id`: `NOT NULL`, referencia `rarity.id` (ver "Rarity," acima — agora uma entidade de referência própria vinculada ao Game, não um texto solto).
- `category_code`: mantido em `card` (ver "Onde armazenar a categoria," abaixo) — formato de armazenamento (coluna simples com `CHECK` vs. entidade de referência) ainda não decidido; a recomendação atual é uma coluna simples nesta primeira versão, por Card Category ter poucos valores estáveis.
- Restrições propostas: `UNIQUE (card_set_id, card_number)`, `UNIQUE (card_set_id, card_order)`, `CHECK (btrim(card_number) <> '')`, `CHECK (card_order > 0)` — deliberadamente **sem** uma expressão regular de formato para `card_number` (justificativa: formatos variam entre jogos/publicações; uma restrição rígida poderia bloquear um código oficial válido).
- `card_set_id`: `ON DELETE RESTRICT`, mesmo padrão já usado em toda a hierarquia editorial.

**Critério campo-a-campo, usado para decidir Card vs. Card Printing:** *"Se o valor permanecer verdadeiro independentemente do idioma e da revisão impressa, ele pertence à Card. Se o valor puder mudar conforme idioma, mercado, arte ou revisão, ele pertence à Card Printing."*

**Critério campo-a-campo, refinado e usado para decidir o que é estruturado vs. deixado apenas na imagem (ver AP-017):** *"Estruturamos informações que permitem identificar, classificar, filtrar, organizar ou avaliar a coleção. Não estruturamos atributos usados exclusivamente para jogar."*

**Classificação Resolvida (RESOLVIDO — decisão direta de Fabrício, ver AP-017):**

Um lote de modelagem trouxe uma lista completa campo-a-campo (Rarity, Category, HP, Tipo Elemental, Estágio, Número da Pokédex, Evolui De, Fraqueza/Resistência/Recuo, Illustrator, Ilustração, Nome) com uma recomendação inicial de destino para cada um. Ao revisar essa lista, **Fabrício determinou diretamente**: *"Não faço questão dessas informações em nossa base de dados. Lembre que essas informações são relevantes para o jogo e não para o colecionismo."* — referindo-se especificamente a HP, estágio, tipo elemental, fraqueza, resistência, custo de recuo, espécie/Pokémon como entidade estrutural, ataques, habilidades e texto de regras. Essa diretriz foi formalizada como **AP-017 (Princípio do Escopo Colecionável)** e também atualiza ADR-011 e ADR-012 (ver ambas).

Classificação final, resultante dessa correção e confirmada num lote seguinte por dois casos de uso concretos de Fabrício (filtrar Treinadores de um Set; filtrar apenas cartas SAR possuídas):

| Informação | Destino |
|---|---|
| Set, Número oficial, Ordem no checklist | `card` |
| Categoria (Card Category) | `card` (`category_code`) |
| Raridade (Rarity) | `card` (`rarity_id`, FK — ver "Rarity," acima) |
| Nome localizado, Idioma, Arte, Ilustrador, Revisão impressa | `card_printing` |
| Holofoil, Reverse Holofoil, Selo | `card_variant` |
| Condição física, Preço pago, Quantidade possuída | `collection_item` |
| **HP, Estágio, Tipo elemental, Fraqueza, Resistência, Custo de recuo, Espécie/Pokémon (como entidade estrutural), Ataques, Habilidades, Texto de regras** | **Fora do banco de dados** — permanecem visíveis apenas na imagem oficial da Card (ADR-012, AP-017) |

**Consequência arquitetural:** a especialização por categoria de conteúdo de jogo (uma tabela `pokemon_card`, e por extensão `trainer_card`/`energy_card`) **deixa de ser necessária**. O modelo permanece nas quatro camadas já estabelecidas, sem uma camada adicional de "detalhes de jogo": `Card Set → Card → Card Printing → Card Variant → Collection Item`.

**Illustrator, especificamente, foi reclassificado para `card_printing`** (não para `card` como registrado anteriormente em "Atributos e Relações da Card," acima) — raciocínio: a autoria de uma ilustração pertence à impressão visual concreta, não à posição abstrata do checklist; se uma mesma posição editorial tiver impressões com artes distintas, o Illustrator também pode diferir entre elas. Ver nota de correção cruzada nessa seção.

**Onde armazenar a categoria (RESOLVIDO):** `category_code` permanece em `card`, mesmo não sendo essencial para identificar a Card (a identidade já está completa com `card_set_id + card_number`). Motivo, levantado por Fabrício com um caso de uso concreto ("Se eu quiser aplicar o filtro num determinado Set para listar apenas as cartas de Treinadores"): a categoria precisa existir como dado estruturado para filtrar/listar/separar/gerar estatísticas por categoria dentro do catálogo e da coleção — não é importante para a mecânica do jogo em si, mas é relevante para o uso do catálogo (mesmo critério do AP-017 refinado, acima). Valores iniciais previstos para o módulo Pokémon TCG: `POKEMON`, `TRAINER`, `ENERGY`.

> **Ponto em aberto, sinalizado, não resolvido unilateralmente:** o valor `ENERGY` aparece pela terceira vez em lotes de modelagem física (23º, 24º e este) como um valor inicial cogitado para `category_code` — mas isso segue contradizendo a "Decisão de Escopo — Cartas de Energia" já registrada abaixo em Card Category, que exclui cartas de Energia do catálogo numerado inteiramente (não ocupam posição no Set). Como o valor `ENERGY` já apareceu de forma concreta em exemplos de SQL neste lote, este ponto precisa de uma resposta explícita de Fabrício antes da Query `140`/`141`: cartas de Energia devem passar a ocupar posição no catálogo numerado (revertendo a decisão de Card Category), ou `ENERGY` é apenas um valor de exemplo genérico do material recebido, sem intenção real de uso?

Rarity, especificamente: **RESOLVIDO E EXECUTADO** — ver "Modelagem Lógica Resolvida" na seção Rarity, acima. `rarity_id` (FK para uma entidade de referência própria, vinculada ao Game), não um texto solto — decisão confirmada por Fabrício e já executada no Supabase (`130`/`131`/`830`).

**Em aberto — sinalizado, não resolvido unilateralmente:**

- **"Card Printing" vs. Card Translation:** o conceito `card_printing` tem escopo reconfirmado neste lote — idioma, nome/conteúdo localizado, arte (inclusive diferenças de ilustração sob o mesmo número), Illustrator e revisões/erratas. Isso é mais amplo do que o já registrado **Card Translation** (ver seção abaixo), que hoje cobre apenas conteúdo editorial por idioma. Ainda não decidido: se `card_printing` deve substituir/renomear Card Translation, se são conceitos distintos, ou se é uma reformulação a ser incorporada. **Não decidir isso unilateralmente** — aguardar confirmação explícita de Fabrício.
- **"Card Variant" (finish + stamp) vs. Finish / Card Finish:** o termo "Card Variant" — retirado do vocabulário conceitual por ADR-010 em favor de Finish/Card Finish — segue sendo usado de forma consistente e deliberada pelo par que executa no Supabase, incluindo exemplos concretos combinando acabamento e selo em uma mesma Card Variant (`Holofoil`, `Holofoil + Jogue Pokémon Stamp`). **Precisa da decisão de Fabrício**: qual nomenclatura prevalece no vocabulário do projeto — Finish/Card Finish (ADR-010) ou Card Variant (uso consistente no par Supabase)?
- **"ENERGY" como valor de `category_code`:** ver ponto em aberto destacado acima — contradiz a decisão de escopo já registrada em Card Category. Não presumir mudança.
- **Formato de armazenamento de `category_code`:** coluna simples com `CHECK` (recomendação atual) vs. entidade de referência própria — não decidido, mas de menor urgência que os pontos acima (Rarity já foi resolvida como entidade; Category segue como coluna simples até haver necessidade concreta de mudar).

Nenhuma dessas questões restantes foi respondida de forma definitiva por Fabrício até este ponto, com exceção da exclusão de mecânica de jogo (essa, sim, uma decisão direta e confirmada).

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

> **Nota em aberto:** um lote recente de modelagem física (ver "Modelagem Física — Discussão Iniciada," na seção Card, acima) propôs uma camada chamada `card_printing` com escopo muito próximo a este conceito. Ainda não confirmado se são o mesmo conceito sob nomes diferentes ou algo distinto — não presumir renomeação até confirmação de Fabrício.

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

Representa a classificação de raridade oficial de uma Card, indicada por um símbolo específico na lista oficial do catálogo.

**Executado.** Nove raridades cadastradas para o Game `POKEMON`, consolidadas a partir das legendas oficiais dos Sets já catalogados (`ME1`, `ME2`, `ME2.5`, `ME3`, `ME4` — fonte: `assets/reference-sources/`), em ordem de exibição (`display_order`):

1. Comum (`COMMON`);
2. Incomum (`UNCOMMON`);
3. Rara (`RARE`);
4. Rara Dupla (`DOUBLE_RARE`);
5. Rara Ultra (`ULTRA_RARE`);
6. Rara Mega Ataque (`MEGA_ATTACK_RARE`) — específica da legenda de `ME2.5`;
7. Ilustração Rara (`ILLUSTRATION_RARE`);
8. Ilustração Rara Especial (`SPECIAL_ILLUSTRATION_RARE`);
9. Mega Rara Hiper (`MEGA_HYPER_RARE`).

Esta lista reflete o conjunto real, executado (Query `830 - Seed Rarity`, ver `05-modelo-de-dados.md`) — segue sendo específica dos Sets já catalogados, não necessariamente exaustiva para Sets futuros ou outros Games suportados pelo Project Mimikyu, que cadastrarão suas próprias Rarities de forma independente.

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
- **pertence a um Game, não diretamente a uma Expansion ou Set** (ver "Modelagem Lógica Resolvida," abaixo) — cada jogo possui seu próprio conjunto de raridades, que não deve ser misturado com o de outro jogo.

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

### Modelagem Lógica Resolvida — Entidade de Referência Própria (aprovado por Fabrício)

Um lote de modelagem física (ver "Modelagem Física — Discussão Iniciada," na seção Card, acima) resolveu a questão de estrutura deixada em aberto acima: **Rarity é uma entidade de referência própria, vinculada ao Game — não um texto solto (`rarity_code VARCHAR`) na própria Card.**

Motivo, testado explicitamente contra um texto-solto: cada TCG possui raridades próprias; o mesmo conceito pode ter códigos diferentes conforme idioma ou mercado; raridades mudam entre eras editoriais de um mesmo jogo; texto livre tem risco de erro de digitação; controlar a ordem de apresentação é difícil sem um campo próprio; filtros poderiam misturar classificações de jogos diferentes sem uma entidade que as agrupe por Game.

Atributos propostos e aprovados:

```text
rarity
  id             UUID
  game_id        UUID
  code           VARCHAR
  name           VARCHAR
  symbol_code    VARCHAR
  display_order  INTEGER
  created_at     TIMESTAMPTZ
  updated_at     TIMESTAMPTZ
```

- `code` — código técnico estável (ex.: `SPECIAL_ILLUSTRATION_RARE`), ou, quando o código oficial curto for relevante para o mercado, uma forma abreviada (ex.: `SAR`).
- `name` — nome oficial ou principal de exibição (ex.: `Special Art Rare`).
- `symbol_code` — identificador técnico e estável do símbolo visual oficial da raridade (ex.: `BLACK_STAR`, `GOLD_DOUBLE_STAR`), **não** o próprio caractere/emoji nem uma URL de imagem. Ver "Identidade Visual da Raridade — Campo `symbol_code`", abaixo.
- `display_order` — permite ordenar raridades em uma sequência lógica (ex.: `1 COMMON, 2 UNCOMMON, 3 RARE, 4 DOUBLE_RARE, 5 ILLUSTRATION_RARE, 6 SPECIAL_ILLUSTRATION_RARE, 7 HYPER_RARE`); a ordem não deve ser inferida alfabeticamente.

> **Cuidado importante, sinalizado explicitamente pelo material recebido e confirmado na execução real:** códigos abreviados como `SAR` e `SIR` podem representar nomenclaturas distintas em diferentes mercados ou linhas editoriais — **não presumir automaticamente que são o mesmo valor** entre catálogos diferentes. O banco deve preservar a classificação oficial exatamente como usada no catálogo correspondente — por isso o código canônico executado é `SPECIAL_ILLUSTRATION_RARE` (nome oficial em português: "Ilustração Rara Especial"), e **não** um `SAR` cadastrado como raridade separada; a interface poderá permitir busca por `SAR`/`SIR`/"Ilustração Rara Especial" apontando para a mesma raridade canônica. Uma futura classificação normalizada para agrupar raridades equivalentes entre catálogos (ex.: `official_code`/`rarity_group`) foi mencionada como possibilidade, mas deliberadamente **não faz parte da primeira versão**, sem necessidade comprovada (AP-004).

Motivado por um caso de uso concreto levantado pelo próprio Fabrício ("Eventualmente posso querer aplicar um filtro para selecionar apenas as minhas cartas SAR"): Rarity foi confirmada como um atributo essencial para o colecionismo (ver AP-017 — serve para filtrar/classificar/organizar a coleção, não apenas para jogar), devendo ser estruturada desde a primeira versão da Card.

**Este modelo foi explicitamente aprovado por Fabrício** ("Excelente. Temos a definição agora. Vamos seguir com a execução!") **e já foi executado e confirmado no Supabase, incluindo a validação e o campo `symbol_code`** (Queries `130`, `131`, `830`, `930`) — ver `05-modelo-de-dados.md` para o modelo físico completo. Pacote técnico concluído, sem pendências estruturais.

### Identidade Visual da Raridade — Campo `symbol_code`

Uma proposta inicial de adicionar apenas um campo `symbol` (um único caractere, ex. `★`) foi refinada por Fabrício antes de ser adotada: *"não usaremos apenas um caractere como ★ [...] As listas oficiais mostram que a identidade da raridade depende de três elementos: formato; quantidade; estilo/cor."* Duas raridades diferentes podem usar o mesmo elemento gráfico base sem serem visualmente equivalentes — `RARE` e `ILLUSTRATION_RARE` usam estrela, mas com cores/estilos diferentes (preta vs. dourada), confirmado contra as legendas oficiais dos Sets já catalogados.

Por isso, o campo adotado é `symbol_code` — um identificador técnico estável (ex.: `BLACK_STAR`, `GOLD_DOUBLE_STAR`), não o caractere em si. A camada de apresentação (Power Apps, Power BI, interface web) converte esse identificador em SVG, PNG, componente visual ou símbolo via CSS, sem que o banco precise conhecer arquivos de imagem — o banco sabe apenas qual símbolo representa cada raridade. `icon_url` (a URL do arquivo gráfico oficial) foi deliberadamente adiado até que esses arquivos estejam hospedados, seguindo o mesmo cuidado já aplicado a `logo_url`/`symbol_url` do Set (ver seção Set, acima).

**Ideia registrada para o futuro, não adotada agora:** uma tabela de domínio própria `symbol` (com `svg_url`/`png_url` etc.), substituindo `rarity.symbol_code` por `rarity.symbol_id`. Não adotada porque hoje existe exatamente um símbolo por raridade — a tabela aumentaria a complexidade sem benefício imediato (AP-004). Ver `05-modelo-de-dados.md`, seção Rarity, "Evolução do Modelo — Campo `symbol_code`", para o registro técnico completo, incluindo a tabela real de valores.

### Observação Arquitetural — Card Depende de Dois Domínios

A criação de Rarity revelou que `card` não depende apenas da cadeia editorial `Game → Expansion → Card Set`, mas também diretamente de `Game → Rarity`:

```text
Game
 ├── Expansion
 │     └── Card Set
 │           └── Card
 │
 └── Rarity
       └── Card
```

Consequência prática: Rarity deixa de ser um atributo textual solto e passa a ser um catálogo oficial do próprio Game — o que facilita filtros, estatísticas, internacionalização futura e evita inconsistências de cadastro entre Cards.

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

> **Nota sobre nomenclatura física:** o schema físico já existente no projeto utiliza as tabelas `card_variant` e `card_variant_type`, nomeadas antes desta refinamento conceitual. A relação entre esses nomes físicos e os termos conceituais Finish/Card Finish definidos aqui (renomear a tabela física ou apenas mapear os conceitos) é uma decisão que será tomada durante a modelagem física (`05-modelo-de-dados.md`), e não está resolvida por este documento.

> **Nota em aberto:** um lote recente de modelagem física (ver "Modelagem Física — Discussão Iniciada," na seção Card, acima) reintroduziu o termo "Card Variant" e propôs tratar `finish` e um novo campo `stamp` como dimensões independentes. Não avaliado nem aprovado — não implementar antes de decisão explícita.

---

## Card Category (Categoria da Carta)

### O que é?

Classifica a natureza editorial primária de uma Card pertencente a um Set, respondendo: *esta posição oficial do Set representa uma carta de Pokémon ou uma carta de Treinador?* Corresponde à tabela física já existente `card_category`. Classificação: Reference Data (Tabela de Domínio).

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

> **Nota em aberto:** um lote recente de modelagem física (ver "Modelagem Física — Discussão Iniciada," na seção Card, acima) mencionou "Energy Card" como uma terceira especialização de conteúdo, o que contradiz esta decisão de escopo. Não presumir que a decisão mudou — sinalizar a Fabrício antes de qualquer ajuste.

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

Classifica uma Card de categoria Trainer em uma das famílias oficiais de cartas de Treinador. Classificação: Reference Data (Tabela de Domínio).

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

Características conceituais mínimas propostas:

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

### Nota sobre estruturação de dados (ver ADR-012)

Nem todo campo listado acima (HP, Attacks, Ability, Weakness, Resistance, Retreat Cost, Evolution Stage, texto de regras) precisa necessariamente virar uma coluna pesquisável desde a primeira versão. Ver `07-catalogo-editorial.md` e ADR-012 para o critério de quando uma informação deve receber estrutura própria versus permanecer disponível apenas através da imagem oficial da Card.

> **Atualização (RESOLVIDO — ver AP-017):** o parágrafo acima tratava essa lista como uma classificação da primeira versão, com possível estruturação futura. Fabrício determinou diretamente que esse grupo específico (mecânica de jogo) não deve ser estruturado no banco de dados — permanentemente, não apenas por ora — porque o Project Mimikyu é uma plataforma de colecionismo, não um banco de dados de mecânicas de jogo (ver AP-017 e ADR-011/ADR-012 atualizadas). Consequência: `Pokémon Card Details`/`Trainer Card Details` permanecem como arquitetura válida, mas sem conteúdo de jogo concreto planejado — nenhuma tabela `pokemon_card`/`trainer_card` será criada com esses campos.

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
| 1.1 | Padronização do cabeçalho (Arquivo, Escopo, Dependências, Documentos Relacionados) para consistência com os demais documentos centrais. |
| 1.2 | Correção do exemplo de numeração da Card (denominador deve ser a quantidade do conjunto base, não o total de Cards). Adição de "Duas Métricas de Contagem do Catálogo", da entidade Card Translation, e de conteúdo parcial de Card Variant com questão de identidade sinalizada como em aberto. Correção da lista de Core Concepts ("Card Set" → "Set", reordenada pela hierarquia editorial). |
| 1.3 | Resolvida a questão de identidade de Card Variant: escopo restrito a diferenças de acabamento sobre a mesma posição catalográfica (Standard, Reverse Holo, etc.). Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold e Rainbow passam a ser tratadas explicitamente como Cards independentes, não como variantes — consistente com a decisão já registrada por Fabrício e agora fundamentada por ADR-009. |
| 1.4 | Com base em documento oficial (lista de cartas do ME1), substituído o conceito "Card Variant" por três conceitos distintos: Rarity (raridade, atributo da Card), Finish (catálogo de acabamentos físicos) e Card Finish (associação Card+Finish). Termos "Printing Variant" e "Finish Variant" descartados definitivamente. Relação Inventory Item atualizada para referenciar Card Finish, não a Card diretamente. Ver ADR-010 (substitui ADR-009 nesse ponto). |
| 1.5 | Expandida a métrica de contagem de duas para três (Official Card Count, Base Set Count, Collectible Finish Count). Adicionadas as entidades Card Category (com taxonomia de Trainer sinalizada como em aberto), Pokémon, Illustrator e Energy Type. Corrigida a suposição de que toda Card possui um Pokémon associado — relação agora condicional à Card Category. Adicionada seção "Atributos e Relações da Card" aplicando o novo AP-014. |
| 1.6 | Resolvida a taxonomia de Card Category: apenas Pokémon e Trainer no catálogo numerado (cartas de Energia fora de escopo); adicionada Trainer Subcategory (Item/Supporter/Stadium/Tool, obrigatória para Trainer). Pokémon finalizado como entidade mínima (id, national_dex_number, canonical_name) — HP/ataques/etc. pertencem à Card, não ao Pokémon, pois variam entre publicações da mesma espécie. Adicionado o padrão Card Details / Pokémon Card Details / Trainer Card Details, explicitamente não-genérico (específico do módulo Pokémon TCG). Ver ADR-011 e ADR-012. |
| 1.7 | Renomeado "Inventory Item" para "Collection Item" em todo o documento (ver ADR-013). Adicionada a seção completa de Collection Item: identidade individual por exemplar físico, relação com Card + Card Finish + Language, grupos preliminares de informação (Identity, Physical State, Collection Role, Lifecycle), separação entre Ownership Status e Availability Status, e regra de identidade técnica e permanente. Adicionada nota sobre Card Image (relação com Card Translation/Card Finish em aberto, decisão progressiva) na seção Card Translation. |
| 1.8 | Populada a entidade Collection (distinta do Set: pertence ao colecionador, não ao catálogo editorial), com os tipos Official Set Collection e Custom Collection. Adicionada a entidade Collection Entry, com os modos Card Target e Subject Target, e os mecanismos preliminares Manual Membership e Rule-Based Membership (este último deliberadamente adiado). Adicionada nota de correspondência entre o termo provisório "User Collection" e a nova entidade Collection. Ver ADR-014. |
| 1.9 | Adicionada nota sobre nomenclatura física do Set: `SET` é palavra reservada do SQL, tabela física é `card_set` (ver STD-001). |
| 1.10 | Expandida a seção Expansion: adicionado o atributo `código editorial`, exemplos reais (SV, SWSH, SM, XY) e a regra "código internacional, nome localizável" (ver STD-001, Seção 5). Documentação de Expansion segue em elaboração — complementos previstos para o próximo ciclo. |
| 1.11 | Finalizada a seção Expansion: ordem de lançamento (inteiro simples), unicidade de código/ordem por Game (não global — decorre de ADR-003), decisão de não incluir `status` (Princípio da Simplicidade Inicial), e identidade visual (`logo_url`, com localização futura deferida). Adicionada à seção Set a responsabilidade sobre quantidades e data de lançamento (pertencem ao Set, não à Expansion; quantidade de secretas é derivada, nunca armazenada) e uma nota preliminar (não fechada) sobre o futuro modelo lógico do Set. |
| 1.12 | Adicionada nota: `logo_url` da Expansion é preenchido por importação automática via API (armazenado no Supabase Storage), mesmo padrão de imagens de Card — não preenchimento manual. Ver `06-pipeline-importacao.md`. |
| 1.13 | **Correção:** a identidade visual (`logo_url`/`symbol_url`) pertence ao Set, não à Expansion — corrige a seção Expansion (1.11/1.12). Adicionadas à seção Set: "Unicidade por Expansion", "Identidade Visual", correção da seção "Status" (decisão final: sem campo `status`, `release_date` opcional cobre o caso de uso), "Visão Conceitual Consolidada" atualizada para refletir o modelo já aprovado (não mais apenas conceitual). Modelo lógico e físico do Set formalmente aprovado por Fabrício, execução no Supabase ainda pendente (ver `05-modelo-de-dados.md`). |
| 1.14 | Adicionado um terceiro tipo de Set: `PROMO` (cartas promocionais Black Star), registrado como `card_set` comum vinculado à Expansion, com convenção fixa de preenchimento (código/nome/ordem/data/quantidades derivados da Expansion) em vez de campos opcionais — ver ADR-015. Nova seção "Card Set Promocional" e atualização de "Classificação Editorial" e "Visão Conceitual Consolidada". Nota de modelo do Set atualizada: tabela física já executada no Supabase (cinco Sets reais cadastrados), `set_type` sendo ampliado via migration `122` (planejada, não executada), Query de validação `920` redigida mas ainda sem confirmação de execução. |
| 1.15 | **Pacote técnico da entidade Set concluído.** Migration `122` executada (constraint ampliada, `release_order` deslocado), Set promocional real cadastrado (`ME0 — ME Black Star Promos`, 89 cartas), validação `920` v2.0 confirmada por Fabrício. Seção "Card Set Promocional" atualizada com o dado real e a divergência sinalizada (índice único parcial recomendado por ADR-015 não foi implementado). Único item aberto: reescrita da Query de Seed `820` para incluir o Set promocional no snapshot completo da Expansion. |
| 1.16 | Atualizada a seção "Card Set Promocional" para refletir o Princípio da Fonte Canônica (STD-001, Seção 10): o índice único parcial, antes divergente, já está presente na Query canônica `120` v2.0 — mas seu status no banco físico atual permanece não confirmado (ver `05-modelo-de-dados.md`, seção Set). |
| 1.17 | Iniciada a discussão da modelagem física da Card (rumo à Query `130`), via o par Fabrício/ChatGPT que executa no Supabase. Adicionada a seção "Modelagem Física — Discussão Iniciada (Query 130), Não Concluída": confirma alinhamento com decisões já registradas (identidade Set+Número, derivação da numeração exibida, fronteira Card/Collection Item, padrão Card Details); sinaliza três pontos em aberto, não resolvidos unilateralmente — possível sobreposição entre a proposta "Card Printing" e o já registrado Card Translation; reintrodução do termo "Card Variant" (retirado por ADR-010) com uma nova ideia de dimensões independentes `finish`/`stamp`; menção a "Energy Card" como especialização, que contradiz a decisão de escopo já registrada em Card Category (exclusão de cartas de Energia do catálogo numerado). Adicionadas notas cruzadas em Card Translation, Card Finish e Card Category apontando para a discussão. Nenhuma tabela física de Card foi criada ou aprovada nesta revisão — discussão explicitamente continua em lote futuro. |
| 1.18 | Avançada a discussão da modelagem física da Card (segundo lote do par Fabrício/ChatGPT). Adicionado à seção "Modelagem Física — Discussão Iniciada": modelo proposto em quatro camadas (Card → Card Printing → Card Variant → Collection Item), a regra "produto diferente não cria variante, carta fisicamente diferente cria variante", a tabela de critério (qual diferença gera nova Card/Printing/Variant), o teste da premissa `card_set_id + card_number` contra o caso de arte diferente com mesmo número (resolvido a favor de manter Card como posição abstrata do checklist), e a definição + atributos mínimos propostos para `card` (id, card_set_id, `card_number` como texto, novo campo `card_order`, created_at, updated_at — deliberadamente sem nome/raridade/HP/tipo/ilustrador). As duas questões de nomenclatura seguem em aberto, agora mais concretas: Card Printing (escopo ampliado — também cobre arte e revisão/errata) vs. Card Translation; e Card Variant (uso consistente em dois lotes) vs. Finish/Card Finish (ADR-010). Adicionada quarta questão em aberto: onde ficam HP/Rarity/Category/Type/Stage/Pokédex Number/Illustrator — o próprio material propôs e depois recuou dessa divisão, deixando-a para um lote futuro. Nenhuma DDL de Card escrita ou aprovada — segue sem confirmação explícita de Fabrício sobre os pontos em aberto. |
| 1.19 | **Decisão direta de Fabrício, formalizada como AP-017 (Princípio do Escopo Colecionável):** mecânica de jogo (HP, estágio, tipo elemental, fraqueza, resistência, custo de recuo, ataques, habilidades, texto de regras, espécie/Pokémon como entidade estrutural) não será estruturada no banco de dados — permanece apenas na imagem oficial da Card. Adicionada "Classificação Resolvida" à seção Card com a tabela final de destino por informação; `category_code` e `rarity_code` adicionados aos atributos mínimos de `card` (formato de armazenamento ainda em avaliação); Illustrator reclassificado de Card para Card Printing (correção cruzada adicionada em "Atributos e Relações da Card"); nota de resolução adicionada a "Card Details" e seu "Nota sobre estruturação de dados". Questão "Energy Card" em grande parte esvaziada (não há mais tabelas especializadas por categoria de jogo). Seguem em aberto: nomenclatura Card Printing vs. Card Translation, Card Variant vs. Finish/Card Finish, e formato de armazenamento de `category_code`/`rarity_code`. ADR-011 e ADR-012 atualizadas com a mesma correção. |
| 1.20 | **Modelo de Card e Rarity aprovado por Fabrício** ("Excelente. Temos a definição agora. Vamos seguir com a execução!"). Rarity promovida de atributo solto a entidade de referência própria, vinculada ao Game (`id, game_id, code, name, display_order`), com alerta sobre não presumir equivalência entre códigos abreviados de mercados diferentes (ex. `SAR`/`SIR`). Card ganha `rarity_id` (FK, resolvendo a pendência de armazenamento de Rarity) mantendo `category_code` como coluna simples (categoria confirmada como necessária por um caso de uso concreto de filtro por Set). Adicionado critério refinado de estruturação ("identificar/classificar/filtrar/organizar/avaliar a coleção, não jogar"). Sinalizado novo ponto em aberto: `ENERGY` reapareceu como valor cogitado de `category_code`, pela terceira vez contradizendo a exclusão de cartas de Energia do catálogo numerado — precisa de resposta explícita de Fabrício antes da Query `140`/`141`. |
| 1.21 | **Rarity executada e confirmada no Supabase** (Queries `130`, `131`, `830`). Lista de raridades atualizada para o conjunto real de nove valores (adiciona `MEGA_ATTACK_RARE`, da legenda de `ME2.5`, ausente da lista anterior). Corrigido o código canônico de "Ilustração Rara Especial" para `SPECIAL_ILLUSTRATION_RARE` — `SAR` não é cadastrado como raridade separada. Adicionada "Observação Arquitetural — Card Depende de Dois Domínios" (`Game → Rarity`, além de `Game → Expansion → Card Set`). Único item pendente: confirmação de execução de `930 - Validate Rarity`. |
| 1.22 | **Pacote técnico da entidade Rarity concluído.** Query `930 - Validate Rarity` confirmada por Fabrício — sem pendências estruturais. Adicionada nota "Proposta em aberto, não decidida" sobre um campo `symbol` (símbolo textual da raridade) sugerido na sessão paralela, condicionado por essa própria sugestão a um levantamento prévio das legendas oficiais — não confirmado, nenhuma alteração de modelo feita. |
| 1.23 | **Campo `symbol_code` confirmado e executado.** Refinamento de Fabrício sobre a proposta anterior: não um caractere único, mas um identificador que capture formato+quantidade+estilo/cor da legenda oficial (ex.: `RARE` e `ILLUSTRATION_RARE` usam estrela, mas com cores diferentes). Adicionado `symbol_code` aos atributos de `rarity`; nova seção "Identidade Visual da Raridade — Campo `symbol_code`" com o raciocínio completo e a ideia registrada (não adotada) de uma futura tabela de domínio `symbol`. Removida a nota "Proposta em aberto" — resolvida. |