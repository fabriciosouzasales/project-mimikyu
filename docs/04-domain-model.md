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

> **Correção anunciada por Fabrício, SQL/migration ainda não recebida nesta sessão — código `ME0` estava errado.** Fabrício sinalizou (2026-07-23): "a decisão de cobrir o Set ME0 foi equivocada, pois não temos esse código como código oficial na API. Precisamos ajustar o código desse Set para `MEP`, que é o código oficial." Ou seja, o código correto do Set promocional da Expansion `ME` é **`MEP`**, não `ME0` — `ME0` não é um código reconhecido pelas fontes externas oficiais (relevante para o pipeline de importação `ADR-008`/`06-pipeline-importacao.md`, que depende de casar códigos locais com códigos de fontes como TCGdex/Pokémon TCG API). Esta correção ainda não foi acompanhada de SQL nesta sessão — os arquivos `database/schema/120_*.sql` e `database/seeds/820_*.sql`/`821_*.sql` ainda registram `ME0`. **Não presumir a migration** — aguardando a Query real antes de qualquer alteração em `database/`.
>
> **Também anunciado, mesma situação: novo Card Set oficial `MEE` — "Energy Set" da Expansion.** Fabrício: "decidimos criar o Set oficial de energias da Expansão. Criamos também o Set MEE." Nenhum detalhe de estrutura (quantidade de cartas, `release_order`, datas) foi fornecido ainda. **Possível relevância direta para a discrepância `ENERGY` já registrada há várias revisões** (9 Cards reais com `category = ENERGY` espalhadas em `ME2`/`ME2.5`/`ME3`/`ME4`, contradizendo a "Decisão de Escopo — Cartas de Energia" já documentada) — um Card Set dedicado a Energy pode ser exatamente o destino correto para essas cartas, ou pode ser um conjunto adicional/distinto. **Não presumido, não resolvido** — aguardando esclarecimento de Fabrício sobre a relação entre `MEE` e as 9 Cards `ENERGY` já cadastradas em `840`.

> **Nota cruzada — `PROMO` também é uma Rarity, não apenas um `set_type`:** ver seção Rarity, abaixo, "`PROMO` é uma Raridade Oficial" — uma carta promocional carrega dois fatos independentes: pertence a um Card Set com `set_type = 'PROMO'` (este bloco) **e** possui `rarity.code = 'PROMO'` (a raridade oficial impressa na carta). Não confundir os dois; a futura Card precisará dos dois.

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

> **Nota de revisão, RESOLVIDA — esta seção está confirmada como válida.** Um lote posterior de modelagem física chegou a reabrir esta questão, cogitando uma identidade editorial independente de Set (ver "Revisão Arquitetural — Identidade Editorial Independente de Set", mais abaixo). **Essa cogitação foi revertida** em uma sessão seguinte — Fabrício optou por manter Card vinculada a um Card Set específico, com a premissa "Set + Número" descrita nesta seção confirmada como final (ver "Revisão Arquitetural — Card Volta a Pertencer a um Card Set", mais abaixo, para o histórico completo de ambas as revisões). Nenhuma alteração é necessária aqui.

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

> **Histórico de duas revisões desde este ponto — a mais recente confirma a identidade `card_set_id + card_number` descrita aqui, mas com atributos finais diferentes.** Ordem dos eventos: (1) o conteúdo original desta seção (identidade `card_set_id + card_number`, atributos mínimos incluindo `card_set_id`/`rarity_id` diretamente em `card`); (2) uma sessão reabriu a questão e propôs uma identidade editorial independente de Set, com uma nova camada `Card Printing` (ver "Revisão Arquitetural — Identidade Editorial Independente de Set"); (3) uma sessão seguinte **reverteu** essa proposta, confirmando que Card pertence a um Card Set específico — mas com atributos finais diferentes dos originais aqui descritos (`collector_number` em vez de `card_number`; `category_id` referenciando uma nova entidade Card Category em vez de `category_code`; sem `card_order` — ver "Revisão Arquitetural — Card Volta a Pertencer a um Card Set", ao final desta seção, para o modelo final aprovado, ainda não executado). Preservado abaixo por rastreabilidade; usar a seção (3) como referência atual.

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

### Revisão Arquitetural — Identidade Editorial Independente de Set (discussão em andamento, não concluída)

**Contexto:** com Rarity oficialmente encerrada, a sessão paralela retomou a modelagem de Card do zero, com uma ressalva explícita do próprio material recebido: *"Antes de criarmos a Query 140, gostaria de respondêssemos essa única pergunta: Para o Project Mimikyu, uma 'Card' representa a carta editorial de forma única, que pode aparecer em vários Sets, ou representa a carta dentro de um Set específico?"* Motivação: a maioria dos sistemas modela Card como uma tabela "achatada" (`Number, Name, HP, Rarity, Illustrator, Language, Finish, Set...`), que funciona até aparecer uma reimpressão, uma versão em outro idioma, holo, reverse holo, promocional, jumbo ou de campeonato mundial — a partir daí o modelo começa a "remendar colunas". O objetivo explícito desta rodada foi evitar esse caminho.

**Resposta direta de Fabrício:** *"Representa a carta editorial de forma única, que pode aparecer em vários Sets."*

**Isso inverte a premissa de identidade usada até aqui neste documento** (ver "Identidade," acima, e ADR-004): Card deixa de pertencer diretamente a um Card Set. A relação correta passa a ser:

```text
Game
 ├── Card
 │     └── Card Printing
 │           └── Card Variant
 │                 └── Collection Item
 │
 └── Expansion
       └── Card Set
             └── Card Printing
```

`Card Printing` passa a depender de **dois** pais — `Card` (identidade editorial) e `Card Set` (onde/quando foi publicada) — em vez de Card depender diretamente de Card Set. Isso reflete um fato real do Pokémon TCG: a mesma carta editorial pode ser reimpressa em Sets diferentes ao longo do tempo, algo que a premissa anterior ("Set + Número" como identidade de Card) não conseguia representar sem tratar cada reimpressão como uma Card totalmente nova e desconectada.

**Definições revisadas, mais precisas que as versões anteriores deste documento:**

- **Card** — representa a identidade editorial única da carta. Existe independentemente de qualquer impressão física. Exemplo: `Pikachu`, ou, dependendo do nível de identidade adotado, `Pikachu ex`. Pode ser publicada várias vezes, em diferentes Sets, idiomas, numerações e acabamentos, permanecendo a mesma Card.
- **Card Printing** — representa uma publicação daquela Card dentro de um Set específico. Exemplos: `Pikachu – ME1 – nº 025`, `Pikachu – ME0 Promo – nº 001`, `Pikachu – ME5 – nº 074` (a mesma Card, três publicações diferentes). É em `card_printing` que devem ficar: `card_id`, `card_set_id`, número da carta no Set, ordem no checklist, raridade, ilustrador (quando variar por publicação), imagem oficial (futuramente) e demais atributos editoriais próprios daquela aparição específica.
- **Card Variant** — representa uma versão oficialmente fabricada daquela impressão (ex.: Normal, Reverse Holo, Holo, Stamped, Cosmos Holo, Staff).
- **Collection Item** — representa cada cópia física individual possuída (ex.: `ITEM_0003456`).

**Consequência imediata e explícita para a Query `140`:** a tabela `card` **não deverá conter** `card_set_id`, `card_number`, nem `rarity_id` — esses atributos identificam uma publicação em determinado Set e, portanto, pertencem a `card_printing`. A tabela `card` deve conter somente atributos intrínsecos à identidade editorial que permaneçam verdadeiros em todas as publicações da mesma carta. **Isso contradiz diretamente o modelo mínimo de `card` "aprovado por Fabrício" registrado mais acima nesta mesma seção** (`id, card_set_id, rarity_id, card_number, card_order, category_code`) — aquele modelo está superado por esta revisão, ainda que também não tenha sido substituído por uma versão final confirmada.

**Princípio: Identidade Editorial (novo, proposto nesta rodada):**

> Uma Card representa uma criação editorial única da The Pokémon Company. Uma nova Card somente é criada quando existe uma alteração editorial que faça a carta deixar de ser considerada a mesma publicação, independentemente do Set. Se uma carta puder ser republicada em outro Set sem mudar sua identidade editorial, continua sendo a mesma Card.

**O que NÃO cria uma nova Card** (tudo isto pertence a camadas posteriores): outro Set; outro idioma; outra impressão; outra tiragem; outro acabamento (Holo, Reverse, Cosmos...); outro número dentro do Set; outra raridade; carta promocional; reprint.

**O que cria uma nova Card** (muda a identidade editorial): `Pikachu`, `Pikachu ex`, `Pikachu V`, `Pikachu VMAX`, `Pikachu GX`, `Pikachu BREAK`, `Pikachu δ Species`, `Surfing Pikachu`, `Flying Pikachu` — "embora compartilhem parte do nome, editorialmente são cartas diferentes."

**Caso delicado 1 — mudança de ilustração:** `Charizard ex` com Arte A e `Charizard ex` com Arte B, se ambas possuem mesmo texto, mesmos ataques, mesmos efeitos e mesma mecânica, e apenas a arte mudou, **não** criam uma nova Card — a arte pertence à Card Printing. Explicitamente relevante porque diversos reprints usam novas ilustrações mantendo exatamente a mesma carta.

**Caso delicado 2 — mudança de texto:** `Professor's Research` com mesmo nome, mesmo tipo, mas texto completamente diferente **é** uma Card diferente — mudança de identidade editorial, não apenas de impressão.

**Consequência para a chave de identidade:** Card não será mais identificada pelo nome — o nome deixa de ser candidato a chave. Internamente, a identidade é um UUID (`id`).

**Primeira proposta para a tabela `card` (rascunho em discussão, NÃO aprovado, NÃO uma decisão final):**

```text
card
  id
  game_id
  name
  category_code       (ou category_id — variação de nome usada de forma inconsistente neste rascunho)
  editorial_key
  created_at
  updated_at
```

**Pontos genuinamente em aberto nesta proposta, sinalizados aqui e não resolvidos:**

- **`editorial_key`** — campo novo, sem definição precisa apresentada até o momento. Presumivelmente algum tipo de chave/identificador que distingue um "design editorial" de outro (para o problema descrito abaixo), mas seu formato, origem e regras de preenchimento não foram explicados nesta rodada. **Não presumir seu significado — aguardar esclarecimento.**
- **`name` como único discriminador é insuficiente**, e a própria discussão reconhece isso: se `card` armazenasse apenas `name`, milhares de cartas distintas chamadas "Pikachu" (com ilustrações, ataques, textos e estatísticas diferentes) seriam incorretamente consolidadas em um único registro. A pergunta explicitamente deixada em aberto ao final deste lote: *"quais atributos distinguem um design editorial de outro sem estruturar desnecessariamente os dados de gameplay?"* — **esta pergunta não foi respondida nesta rodada.** É provável que `editorial_key` seja parte da resposta, mas isso não foi confirmado.
- **`category_code` reaparece com `ENERGY` como exemplo explícito** ("categoria (Pokémon, Trainer, Energy)") — a mesma pendência já sinalizada em lotes anteriores (`ENERGY` contradiz a "Decisão de Escopo — Cartas de Energia" de Card Category). Este lote não resolve essa pendência; apenas a menciona de passagem, dentro de um exemplo. **Não tratar como confirmação de que `ENERGY` será incluído.**
- **`game_id` diretamente em `card`** é uma mudança de relacionamento: no modelo anterior, o vínculo com o Game era implícito via `card_set → expansion → game`. Neste rascunho, `card` referencia `game` diretamente — consistente com a nova independência de Card em relação a Card Set, mas ainda não confirmado como decisão final.

**Status desta revisão:** discussão real, em andamento, explicitamente não concluída — o próprio material terminou com a pergunta em aberto acima, sem uma resposta. **Nenhuma DDL deve ser escrita ou executada a partir deste rascunho.** Fabrício e a sessão pareada classificaram esta como possivelmente "a conversa mais importante de todo o Project Mimikyu até agora" — justificando a cautela redobrada antes de convertê-la em SQL.

**Impacto sinalizado, não resolvido, sobre ADR-004:** ADR-004 (`Set Identity`) estabeleceu a identidade de Set como Set + Número da Card — na leitura atual, essa identidade pode precisar ser reatribuída de Card para Card Printing. **ADR-004 não foi alterada** nesta revisão — aguardando a resolução completa desta discussão antes de qualquer atualização formal de ADR, consistente com a prática do projeto de não editar ADRs a partir de discussões ainda não concluídas.

### Revisão Arquitetural — Card Volta a Pertencer a um Card Set (decisão final, revertendo a revisão anterior)

> **Esta seção reverte a "Revisão Arquitetural — Identidade Editorial Independente de Set", acima.** A discussão anterior é preservada por rastreabilidade, mas seu resultado (Card como identidade editorial Set-independente, com `Card Printing` como camada intermediária) **não foi adotado**. Ler esta seção como a mais atual.

**Motivo da reversão, nas palavras de Fabrício:** *"Estou pensando em mudar de ideia. Estou achando melhor considerar uma 'Card' como uma representação da carta dentro de um Set específico (como 'Charizard ex nº 021 da coleção ME4'). Fiquei com receio do modelo anterior trazer dificuldades no cadastro."* A resposta recebida na sessão paralela concordou e detalhou o motivo prático: o modelo editorial global (Card independente de Set) exigiria, no momento do cadastro de cada carta, decidir previamente se ela é uma reimpressão da mesma identidade editorial ou uma carta diferente — o que exigiria comparar ataques, habilidades, textos, ilustração e outras características que o projeto decidiu deliberadamente **não** estruturar (ver AP-017). Ou seja, o modelo mais "correto" teoricamente introduzia uma dependência operacional sobre dados que o projeto já havia decidido manter fora do banco.

**Nova definição final de Card:**

> Uma Card representa uma entrada específica no checklist oficial de um Card Set.

Exemplos — cada um é um registro `card` distinto, mesmo quando representam reimpressões ou conteúdo semelhante, porque pertencem a Sets ou posições editoriais diferentes:

```text
Charizard ex – ME4 – 021/xxx
Charizard ex – ME5 – 074/xxx
Charizard ex – Promo – 015
```

**Arquitetura revisada (final):**

```text
Game
 ├── Expansion
 │     └── Card Set
 │           └── Card
 │                 └── Card Variant
 │                       └── Collection Item
 │
 └── Rarity
```

`Card Printing`, proposta na revisão anterior, **deixa de ser necessária neste momento** — a própria `Card` já representa a publicação dentro do Set. Card volta a pertencer diretamente a um único Card Set, exatamente como no modelo original anterior à revisão passada (ADR-004 permanece válida, não precisa de atualização).

**Benefícios práticos confirmados:** o cadastro pode ser feito diretamente a partir dos checklists oficiais (Set, Número, Nome, Categoria, Raridade), sem precisar: identificar reprints; criar uma identidade editorial abstrata; decidir se duas cartas com o mesmo nome são a mesma carta; estruturar dados de gameplay apenas para diferenciar cartas; manter um processo de vinculação editorial entre Sets. Citado explicitamente como alinhado ao **AP-010 (Responsible Generalization / Princípio da Generalização Responsável)**, já registrado em `02-architecture-principles.md`: não adicionar uma camada complexa apenas porque ela poderá ser útil algum dia.

> **Tensão sinalizada, não resolvida — cross-check contra AP-011 (Editorial Identity):** AP-011 já registrado neste projeto afirma que "os conceitos editoriais do domínio devem possuir identidade única e independente de regionalizações" e que "características como idioma, distribuição ou impressão pertencem à representação do exemplar e não alteram a identidade editorial do catálogo." A decisão final desta seção — Card pertence a exatamente um Card Set, e uma reimpressão em outro Set é uma Card **diferente** — pode estar em tensão com essa leitura de AP-011, dependendo de se "impressão"/"distribuição" é interpretado como incluindo "em qual Set foi publicada". **Esta tensão não foi discutida nem resolvida pela sessão paralela** — sinalizada aqui para que Fabrício decida se AP-011 precisa de um esclarecimento/exceção, ou se a leitura de "impressão" ali não cobre este caso. Nenhuma alteração foi feita em AP-011.

**O que permanece em Card**: identifica a carta no checklist — Set, número, nome, categoria, raridade, ilustrador (quando disponível), imagem oficial (futuramente).

**O que permanece em Card Variant**: identifica as versões colecionáveis possíveis daquela carta (Normal, Holo, Reverse Holo, Cosmos Holo, Stamped, outras versões oficiais).

**O que permanece em Collection Item**: identifica cada cópia física individual (ex.: `ITEM_0003456`), com condição, aquisição, localização, idioma, certificação e demais dados patrimoniais. **Nota registrada, não resolvida:** com `Card Printing` removida, o idioma de uma publicação específica passou a ser listado como atributo do Collection Item nesta rodada — uma mudança sutil frente a discussões anteriores, onde o idioma era cogitado no nível da impressão (que serviria a múltiplas cópias físicas idênticas), não da cópia individual. Não avaliado a fundo nesta revisão; registrado para retomada quando `card_variant`/`collection_item` forem modeladas fisicamente.

**Reimpressões no futuro — extensão deliberadamente não construída agora:** caso se torne necessário relacionar reimpressões/mesma-arte/arte-alternativa entre Cards, uma tabela opcional `card_relation` (`source_card_id, target_card_id, relation_type` — ex. `REPRINT_OF`, `SAME_ARTWORK_AS`, `ALTERNATE_ART_OF`) poderá ser adicionada depois, sem que o cadastro inicial dependa dessa classificação (mesmo raciocínio de AP-010/AP-004).

**Três atributos discutidos e resolvidos antes da Query 140:**

1. **Número da carta** — renomeado de `card_number` para **`collector_number`**, `VARCHAR(20)`, preservando zeros à esquerda, prefixos e sufixos (`001`, `SVP001`, `TG07`, `GG32`, `RC15`, `12a`).
2. **Nome da carta** — armazenado exatamente como impresso (`Charizard`, `Charizard ex`), sem tentar separar o sufixo mecânico (`ex`, `V`, `GX`, `VMAX`) do nome — essas mecânicas podem mudar ao longo dos anos, e separá-las estruturaria uma distinção de jogo, não de colecionismo.
3. **Categoria** — confirmada como referência a uma nova entidade de domínio própria, **Card Category** (ver seção nova, abaixo), em vez de uma coluna de texto solta — mesmo padrão já usado para Rarity, e pela mesma razão: consistência com o resto do projeto e preparação para outros jogos (Magic, Yu-Gi-Oh, Lorcana) sem alterar a tabela `card`.

**Identificador composto (`ME4-021`, `SVP-001`) — decisão de não persistir:** cogitado como um campo `card_code` (concatenação de `card_set.code` + `collector_number`), mas **descartado deliberadamente** — pode ser obtido dinamicamente (`card_set.code || '-' || card.collector_number`), evitando redundância e o risco de inconsistência caso o código do Set ou o número da carta precisem ser corrigidos depois. Consistente com o princípio já aplicado a `secret_set_size` do Card Set (nunca armazenar o que pode ser derivado).

**Modelo aprovado por Fabrício ("Concordo") nesta rodada — refinado logo em seguida, ver "Refinamento do Modelo de Card" abaixo:**

```text
card
  id                 UUID
  card_set_id        UUID
  rarity_id          UUID
  category_id        UUID
  collector_number    VARCHAR(20)
  name               VARCHAR
  created_at         TIMESTAMPTZ
  updated_at         TIMESTAMPTZ
```

Regras confirmadas: Card representa uma carta específica dentro de um Set; `collector_number` é texto, preservando zeros/prefixos/sufixos; `name` é armazenado exatamente como consta oficialmente; `category_id` referencia a entidade própria Card Category; nenhum `card_code` é persistido — o código composto é derivado por aplicação ou `VIEW`.

**Sequência de execução decidida:** antes de `140`, criar a entidade `Card Category` (`132 - Create Card Category Table`, `133 - Create Card Category Trigger`, `831 - Seed Card Category`, `931 - Validate Card Category`) — já que `card.category_id` depende dela. Só então `140 - Create Card Table`, `141 - Create Card Trigger`, `840 - Seed Card`, `940 - Validate Card`. Ver seção "Card Category", nova, abaixo, para o registro da execução real desta primeira parte.

### Refinamento do Modelo de Card — Versão 1.1 (dois campos novos + decisão de idioma)

Com Card Category executada, a sessão paralela validou o modelo acima campo a campo antes de escrever a Query `140` — e essa validação levou a dois acréscimos e a uma decisão adicional, ainda dentro do mesmo ciclo de trabalho:

- **`collector_total` (novo, `INTEGER`, opcional).** Registra o denominador exibido na numeração oficial impressa da carta — o `182` em `021/182`. Motivo: esse denominador **não é sempre igual a `card_set.total_set_size`** — seções especiais do checklist (`Trainer Gallery`/`TG`, `Galarian Gallery`/`GG`) têm seu próprio total (`TG07/TG30`, `GG15/GG70`), e cartas promocionais frequentemente não exibem denominador nenhum (`SVP001`). Sem este campo, essa informação impressa se perderia.
- **`collector_order` (reintroduzido, `INTEGER`, obrigatório).** Esse campo já havia existido em rascunhos anteriores do modelo de Card (revisão 26 desta mesma seção) e foi removido silenciosamente na reversão para o modelo Set-específico (revisão 1.27), sem confirmação explícita de que não era mais necessário. Nesta validação campo a campo ele foi reintroduzido, com justificativa concreta: `collector_number` sozinho não ordena corretamente quando há prefixos/sufixos não puramente numéricos (`001, 002, TG01, TG02, GG15, SVP001, 12a` não têm uma ordenação textual simples e previsível). `collector_order` representa a posição editorial no checklist, independente do formato de `collector_number`.
- **Decisão sobre o idioma de `name` — Opção B, confirmada por Fabrício.** Duas opções foram apresentadas: (A) `name` guarda o nome conforme o idioma do Set — decisão relevante porque Fabrício pretende trabalhar com coleções em inglês a partir de ME3; (B) a Card sempre guarda o nome oficial da edição/Card Set em que foi cadastrada, sem camada de tradução própria. Fabrício escolheu a **Opção B**, com justificativa direta: *"Porque a Card representa exatamente o catálogo daquele Set. Não precisamos criar uma camada de tradução."* Ou seja, `name` continua sendo um único valor por Card (não multi-idioma) — uma eventual tradução/localização permanece responsabilidade de uma camada separada (Card Translation, ainda "documentação pendente"), não um campo de `card`.

**Nova regra de negócio, decorrente da ausência de `game_id` em `card`:** como `card` não armazena `game_id` (obtido via `Card → Card Set → Expansion → Game`), e `rarity_id`/`category_id` também pertencem a um Game próprio, nada impede — apenas com FKs simples — que uma Card referencie uma Rarity ou Card Category de um Game diferente do seu Card Set. Nova regra: **Card Set, Rarity e Card Category referenciados por uma mesma Card devem pertencer ao mesmo Game.** Como isso não pode ser expresso por um `CHECK` simples (compara colunas de tabelas diferentes), a validação foi implementada como um **trigger de validação** (função `validate_card_game_consistency()`, acionada em `INSERT`/`UPDATE` das três FKs) — primeira vez que este padrão (trigger dedicado a uma regra de integridade referencial cruzada, além do já-usual trigger de `updated_at`) aparece no projeto.

**Forma final da tabela, com os dois campos novos:**

```text
card
  id                  UUID
  card_set_id         UUID
  rarity_id           UUID
  category_id         UUID
  collector_number    VARCHAR(20)
  collector_total     INTEGER (opcional)
  collector_order     INTEGER
  name                VARCHAR(200)
  created_at          TIMESTAMPTZ
  updated_at          TIMESTAMPTZ
```

Fabrício: *"Vamos em frente. Concordo!"*

**SQL real recebida para `140` (tabela) e `141` (função de validação + os dois triggers) — texto verbatim, com header oficial completo (`Status: CANÔNICA`, `Versão: 1.0`). Execução confirmada por inferência técnica direta** (ver subseção seguinte): não houve uma mensagem isolada "140/141 executado com sucesso", mas a Query `840` (Seed, abaixo) foi diretamente confirmada como executada e depende estruturalmente de `140`/`141` já existirem — conclusão documentada explicitamente como inferência, não presunção, para correção por Fabrício se necessário. Texto completo copiado para `database/schema/140_create_card_table.sql` e `database/schema/141_create_card_triggers.sql`.

### Seed `840` — Versão 2.1, executada e confirmada: catálogo completo da expansão Megaevolução (859 Cards)

Fabrício confirmou que o PDF `P10346_ME01_Card_List_PTBR.pdf` (checklist oficial de ME1, já arquivado em `assets/reference-sources/`) era suficiente para montar quase toda a Seed de ME1 — número, nome, categoria e raridade (via legenda de símbolos, já mapeada contra os códigos cadastrados em `rarity`) vêm diretamente do documento. Único ponto que exigiu uma decisão editorial explícita: o PDF não exibe o denominador completo (`021/182`) em todo registro, apenas a numeração (`001`...`188`); a leitura adotada foi usar `card_set.base_set_size` (132 para ME1) como `collector_total` para **todas** as 188 Cards, incluindo as secretas 133–188 — consistente com a lógica de numeração do Pokémon TCG, mas documentada explicitamente na Query como derivada, não lida diretamente do checklist.

Depois de montar a Seed inicial só para ME1, Fabrício propôs ampliar imediatamente: *"Se temos condições de fazer a carga com a lista de verificação oficial, porque não fazer o cadastro de todas as cartas da expansão Megaevolution? Temos condições de fazer o mesmo com ME2, ME2.5, ME3 e ME4."* A sessão pareada concordou e propôs uma mudança de arquitetura mais ampla: em vez de uma Seed por Card Set, uma **única Query `840` canônica cobrindo todo o catálogo oficial atualmente suportado** — porque `card` é "um catálogo mestre, não um cadastro operacional"; quando um novo Card Set for lançado (ex. `ME5`), a mesma Query `840` será atualizada, não uma nova migration criada — generalizando o Princípio da Fonte Canônica (já usado em `120`/`820` de Card Set e `130`/`830`/`930` de Rarity) de DDL/seeds-de-domínio também para seeds de dados de catálogo em massa.

**Resultado**: `840` v2.1 cadastra as **859 Cards dos cinco Card Sets da expansão Megaevolução** (`ME1`=188, `ME2`=130, `ME2.5`=295, `ME3`=124, `ME4`=122), com `collector_total` derivado do `base_set_size` de cada Set (132/94/217/88/86). A Query valida previamente a existência do Game, dos cinco Card Sets com seus tamanhos canônicos, das três Card Categories e de todas as nove Rarities usadas; insere/atualiza de forma idempotente (`ON CONFLICT ... DO UPDATE`); e valida ao final a quantidade exata por Set e o total de 859 — tudo dentro de uma transação (`BEGIN`/`COMMIT`) que reverte por completo em caso de qualquer divergência.

**Fabrício confirmou diretamente: "Executei com sucesso."** Esta é uma confirmação explícita de execução — não uma inferência — para a Query `840` em si.

> **Discrepância `ENERGY` — de "valor cadastrado" para "9 Cards reais em produção".** A seed real inclui Cards de categoria `ENERGY` com posição numerada de verdade: 1 em ME2 (`124 - Energia de Ignição`), 2 em ME2.5 (`216`/`217`), 3 em ME3 (`086`-`088`), 3 em ME4 (`084`-`086`) — 9 no total (ME1 não tem nenhuma). Isso é substancialmente mais concreto que a discrepância já sinalizada na revisão anterior (onde `ENERGY` era apenas um valor cadastrado em `card_category`, sem nenhuma Card de fato usando-o): agora há Cards reais, com `collector_number`/`collector_order` reais, ocupando posições no catálogo numerado sob a categoria `ENERGY` — o que contradiz diretamente a "Decisão de Escopo — Cartas de Energia" (ver seção Card Category, abaixo, onde o texto da discrepância foi atualizado). **Não resolvido unilateralmente** — a decisão de escopo original permanece intocada, aguardando confirmação explícita de Fabrício.

**Query `940` — reescrita para Versão 2.0, executada e confirmada.** Ampliada de 18 para **27 blocos de validação**, agora com uma seção canônica explícita (no mesmo padrão já usado pela CTE de `930`, de Rarity): quantidades canônicas por Card Set, total consolidado de 859, status `COMPLETE` para os cinco Sets, continuidade de `collector_order` de 1 até `total_set_size`, aderência de `collector_total` ao `base_set_size`, além das checagens já existentes (duplicidade, formato, integridade referencial, consistência de Game, distribuição por categoria/raridade, triggers, timestamps, RLS) e duas novas checagens de categorias/raridades não previstas. **Fabrício confirmou a execução diretamente: "Pronto! Executado com sucesso."** Com isso, o pacote técnico de Card (`140`/`141`/`840`/`940`) está **tecnicamente completo e confirmado** — a sessão pareada descreveu isso como um marco: "o banco deixou de ser apenas uma estrutura de tabelas e passou a conter um catálogo editorial canônico completamente validado."

> **Correção importante, feita pela própria sessão pareada antes de avançar: o "bloco 100 — Editorial Catalog" ainda NÃO está concluído.** A hierarquia já aprovada é `Game → Expansion → Card Set → Card → Card Variant → Collection Item` — falta modelar `Card Variant` (ver nota em aberto na seção Finish/Card Finish, abaixo) antes que o catálogo editorial esteja de fato completo. Avançar diretamente para o próximo domínio (Coleções) criaria uma dependência incompleta: uma Collection não deve controlar apenas a carta editorial, precisa controlar qual **versão colecionável** daquela carta está sendo colecionada (ex.: Bulbasaur 001 tem duas versões possíveis — Standard e Reverse Holo — que são itens colecionáveis distintos). Fabrício concordou com essa correção ("Vamos em frente!" foi dito antes da correção ser levantada, mas o plano imediato passou a ser Card Variant, não Coleções). Ver a seção Finish/Card Finish, abaixo, para a discussão iniciada (não concluída) sobre a modelagem física de Card Variant e sua tensão com a nomenclatura já estabelecida por ADR-010.

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

### `PROMO` é uma Raridade Oficial (confirmada e executada)

Fabrício identificou um detalhe que faltava ao conjunto de nove raridades já executado: *"Toda carta do set promocional terá a raridade PROMO, com símbolo Black Star."* `PROMO` não é uma raridade improvisada para organizar o Set promocional — é uma classificação oficial do próprio Pokémon TCG, confirmada com exemplos de diferentes eras (Promo SVP/Pikachu SVP001, Promo SM/SM01, Promo SWSH/SWSH001, todas `PROMO` com símbolo estrela preta).

**Insight de validação:** `PROMO` e `RARE` compartilham exatamente o mesmo `symbol_code` (`BLACK_STAR`) — confirmando que `symbol_code` está corretamente fora da chave de unicidade de Rarity (a chave permanece `UNIQUE (game_id, code)`); é um atributo puramente descritivo, nunca identificador. `PROMO` foi posicionada logo após `RARE` na ordem de exibição (paralela, não "mais alta").

**Consequência arquitetural para a futura Card:** uma carta promocional não é identificada apenas pela sua raridade — ela também precisa pertencer a um Card Set do tipo `PROMO` (ver "Card Set Promocional", acima). `card_set.set_type = 'PROMO'` (o conjunto ao qual a carta pertence) e `rarity.code = 'PROMO'` (a raridade oficial daquela carta) são **fatos independentes e complementares**; a modelagem de Card precisará contemplar os dois simultaneamente.

**Status:** executado com sucesso — `830`/`930` reescritas para v1.2 (incluindo `PROMO`) e confirmadas por Fabrício ("Tudo feito com sucesso. Vamos avançar!"); `130` permaneceu inalterada, como decidido. Ver `05-modelo-de-dados.md`, seção Rarity, "Descoberta — PROMO é uma Raridade Oficial (confirmada e executada)", para o registro técnico completo. **A entidade Rarity está oficialmente encerrada** — Fabrício: "Agora sim podemos dizer que a entidade Rarity está encerrada."

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

> **Card Variant Type executada e confirmada — tensão de nomenclatura com ADR-010 agora concretizada em produção, ainda não resolvida por Fabrício.** A proposta de modelagem física sinalizada na revisão anterior foi executada: `card_variant_type` (`id, game_id, code, name, description, display_order, created_at, updated_at`; `UNIQUE (game_id, code)`; `UNIQUE (game_id, display_order)`; FK para `game` com `ON UPDATE/DELETE RESTRICT`; `code` validado por regex `^[A-Z][A-Z0-9_]*$`; `name` não vazio; `display_order` positivo; trigger de `updated_at`; RLS habilitado) — Queries `150`/`151` confirmadas por Fabrício ("Bloco Card Variant Type concluído"). Catálogo inicial (`850` v1.0, cinco tipos: `STANDARD`, `REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED`) executado, e em seguida ampliado para `850`/`950` v1.1 (seis tipos) após Fabrício identificar que `HOLO` — distinto de `REVERSE_HOLO` — faltava: "Se não a cadastrarmos agora, teremos problemas quando modelarmos coleções que possuem cartas holográficas padrão sem versão reverse." A versão 1.1 foi executada com sucesso (deslocamento temporário de `display_order` para contornar a `UNIQUE` já ocupada, seguido de UPSERT definitivo); `950` v1.1 confirmada, validando os seis tipos canônicos.
>
> **Card Variant (estrutura) também executada e confirmada — `160`/`161`/`960`.** Antes de escrever as Queries, Fabrício e a sessão pareada validaram formalmente a arquitetura: `card_variant` representa uma versão colecionável específica de uma `card` (exemplo: `ME1-001 — Bulbasaur` possui as variantes `STANDARD` e `REVERSE_HOLO`) — não representa uma cópia física; duas cópias físicas da mesma variante serão, no futuro, dois registros distintos no inventário. Estrutura executada: `id, card_id, variant_type_id, variant_order, is_default, created_at, updated_at`; `UNIQUE (card_id, variant_type_id)`; `UNIQUE (card_id, variant_order)`; `variant_order > 0`; índice único parcial garantindo no máximo uma variante `is_default = TRUE` por Card; trigger de `updated_at`; segundo trigger de consistência de Game entre Card e Card Variant Type (mesmo padrão já usado em `141` para Card), validado via `Card → Card Set → Expansion → Game` e `Card Variant Type → Game`. Decisão explícita de **não persistir** um campo `variant_code`: derivável quando necessário como `card_set.code || '-' || card.collector_number || '-' || card_variant_type.code` (ex.: `ME1-001-STANDARD`) — mesmo precedente já usado para `card_code` e `secret_set_size`. `variant_order` é local à Card (não ao catálogo geral de Card Variant Type): a ordem de apresentação das variantes de uma Card específica pode ser diferente da ordem canônica dos tipos.
>
> **Reflexão de Fabrício, resolvida sem alterar a arquitetura proposta**: Fabrício questionou se fazia sentido cadastrar variantes "da linha editorial" em vez de apenas registrar, na coleção, quais variações de uma Card específica o usuário possui — "Não importa para mim quais variações de um determinado SET. [...] É na coleção que preciso saber quais variações eu tenho de uma determinada carta." A resposta separou duas dimensões que a reflexão misturava: o catálogo editorial oficial (quais variantes existem para uma Card, independentemente de posse) e a posse física (quais dessas variantes o usuário possui). Uma variante não deixa de existir no catálogo por não estar na coleção do usuário — essa distinção é necessária para o sistema saber quais variantes faltam, o percentual de conclusão da coleção, e quais versões podem ser adicionadas ao inventário. A cadeia de responsabilidade confirmada: **Card (identidade editorial) → Card Variant (versão colecionável oficialmente existente) → Collection Item (cópia física possuída)** — o catálogo informa o que existe, o inventário informa o que o usuário possui. Isto reforça, não elimina, a necessidade de `card_variant`; formaliza a mesma cadeia já prevista em ADR-010 (`Card → Card Finish → Inventory Item`), agora sob o nome `Card Variant`.
>
> **Estratégia de fontes para o Seed `860` (ainda não escrito) — ver `06-pipeline-importacao.md` para o padrão geral de importação (ADR-008).** Não existe uma única fonte oficial da Pokémon que exponha, de forma estruturada e completa, todas as variantes de cada Card. O checklist oficial (já usado para `840`) confirma quais Cards pertencem ao Set, numeração, raridade e a impressão principal (inclusive quando holográfica), mas nem sempre lista individualmente variantes paralelas como `REVERSE_HOLO`, `POKE_BALL_REVERSE` ou `MASTER_BALL_REVERSE`. Fonte estruturada complementar identificada: a **TCGdex** expõe, por Card, um campo `variants` (`normal`/`reverse`/`holo`/`firstEdition`) que descreve explicitamente quais impressões são conhecidas — mapeamento proposto: `normal → STANDARD`, `holo → HOLO`, `reverse → REVERSE_HOLO`. A **Pokémon TCG API** não tem um campo tão direto, mas seu objeto de preços (`normal`/`holofoil`/`reverseHolofoil`) serve como evidência complementar — com a ressalva de que ausência de preço não comprova ausência da variante, então não deve ser usada isoladamente. `POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE` (específicas de certos Card Sets) e `PROMO_STAMPED` (pode vir de blister, box, evento, pré-lançamento, torneio, coleção especial, nem sempre representada no checklist do Set) exigirão validação individual, não regra global. Pipeline proposto: `Checklist oficial + TCGdex variants + Pokémon TCG API (evidência complementar) + validação manual de exceções → dataset intermediário rastreável (fonte + status de validação por linha) → Query 860`. Dado o volume estimado (859 Cards, entre 1.200 e 2.000 registros de Card Variant se a média for 1,5-2 variantes por Card), o Seed será construído e validado por Card Set (`860A`–`860E`, um por Set: ME1/ME2/ME2.5/ME3/ME4), consolidados depois na Query canônica `860` — mesma disciplina já usada no processo de validação do Rarity/Card. **Nada disso foi executado ainda**; é o plano confirmado por Fabrício antes de `860` ser escrita.
>
> **Isto reforça, com evidência ainda mais forte, a tensão já sinalizada aqui:** a modelagem física real — e não apenas uma proposta — usa "Card Variant"/"Card Variant Type" de ponta a ponta (nome das tabelas, catálogo, estrutura aprovada, mensagens de commit da sessão pareada), não "Finish"/"Finish Type" — e agora cobre tanto o catálogo de tipos (`card_variant_type`) quanto a associação por Card (`card_variant`), com a cadeia conceitual completa `Card → Card Variant → Collection Item` documentada e validada por Fabrício sem qualquer menção a "Finish". Achado adicional deste ciclo: **`ADR-008` (External Catalog Data Sources), já aprovada antes desta fase de execução, também lista "Card Variant" — não "Finish"/"Card Finish" — como uma das entidades do Catálogo Editorial mantidas com registros próprios** (`Decision`, linha de lista). Isso não resolve a tensão por si só (o nome físico já existia antes de ADR-010, como já registrado aqui), mas mostra que mesmo um documento conceitual já aprovado por Fabrício usa "Card Variant" nesse contexto. **A decisão continua não tomada por Fabrício** — antes de `860`/`860A`–`860E` serem escritas (ou de qualquer novo ADR que referencie esta entidade), é preciso decidir: (a) adotar "Card Variant"/"Card Variant Type" como os termos finais, revertendo ADR-010 (e ajustando a referência já existente em ADR-008); (b) manter Finish/Card Finish como termos conceituais e apenas mapear para as tabelas físicas já executadas `card_variant`/`card_variant_type`; ou (c) outra reconciliação. Não decidir isso silenciosamente.
>
> **Nota lateral, também não resolvida:** o exemplo ilustrativo de uma discussão anterior (`Card → Card Variant → Inventory Item`, com `ITEM_0003456`) usa "Inventory Item" — termo já renomeado para "Collection Item" neste projeto (ADR-013). Provavelmente um hábito de nomenclatura antiga da sessão pareada, não uma proposta deliberada de reverter o rename — mas sinalizado aqui por precaução, sem nenhuma alteração feita.
>
> **Marco confirmado por Fabrício**: com `160`/`161`/`960` executados, toda a estrutura do Catálogo Editorial (`100`–`160`: Game, Expansion, Card Set, Rarity, Card Category, Card, Card Variant Type, Card Variant) está modelada e criada no banco. Falta apenas povoar `card_variant` com o dataset editorial real (`860`) — a discrepância `ENERGY` e a decisão de nomenclatura Card Variant/Finish seguem como pendências não técnicas antes de declarar o bloco "Editorial Catalog" (100) verdadeiramente concluído.
>
> **Disciplina de sequenciamento reafirmada.** A sessão pareada chegou a recomendar avançar para o domínio `200 — Collections` em paralelo, argumentando que ele é "completamente independente" do Seed `860`. Fabrício não concordou: "Fico um pouco incomodado de avançar deixando pendências para trás... Eu gostaria [de concentrar] logo a energia na query 860. Não temos como fugir dele!" — a sessão pareada reconheceu o desvio e reafirmou a disciplina já registrada (não abrir Coleções enquanto o Catálogo Editorial estiver incompleto), consistente com o roadmap de prioridades já registrado em memória (Catálogo Editorial → Coleções → Inventário → ...). Também reconheceu que `860` deixou de ser "apenas um seed": na prática, será o catálogo editorial oficial do Project Mimikyu — um ativo de dados do sistema, não apenas uma carga inicial — o que justifica dedicar um processo próprio de extração/validação/consolidação em vez de gerá-lo por suposição.
>
> **Estratégia de construção do Seed `860` refinada (ainda não executada).** Confirmado: não será uma carga única baseada em suposições. Trabalho por Card Set, mantendo a numeração canônica `860`: `860A` (ME1), `860B` (ME2), `860C` (ME2.5), `860D` (ME3), `860E` (ME4) — a sessão pareada também citou um `860F` para um Card Set chamado "ME5", que **não existe no catálogo atual** (os cinco Card Sets reais da Expansion `ME` eram, até então, `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`, mais o Card Set promocional, cadastrado em `card_set` mas ainda sem Cards seedadas em `840`, que cobre apenas os 859 Cards de `ME1`–`ME4`). Este documento já usa "`ME5`" como exemplo hipotético de expansão futura (ver seção Card, "Card Printing"), então é provável que a sessão pareada tenha reaproveitado esse rótulo por engano. **Atualização (2026-07-23): a resposta não é `ME0` nem `ME5`.** Fabrício esclareceu que o próprio código `ME0` estava errado (código correto: `MEP`, ver "Card Set Promocional", acima) e que foi criado um novo Card Set oficial `MEE` ("Energy Set" da Expansão) — possivelmente relevante para a discrepância `ENERGY` já registrada. O plano de staging do Seed `860` precisará ser revisado à luz dessas duas mudanças assim que a SQL/migration correspondente for recebida; **nenhuma alteração foi feita em `database/` ainda**. Processo por Card Set (cinco etapas): identificar variantes conhecidas nas fontes; cruzar com as Cards já cadastradas; classificar automaticamente os casos seguros; separar divergências/exceções; gerar o UPSERT canônico. "Casos seguros": evidência estruturada da fonte (ex. TCGdex `normal`/`holo`/`reverse`) convertida diretamente em linhas de `card_variant` com `is_default` marcado na impressão principal. "Casos especiais" (`POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED`): tratados explicitamente, nunca inferidos globalmente — cada ocorrência precisa de suporte em checklist, API ou produto oficial correspondente. Regra de `variant_order`: local à Card, sequencial e sem lacunas, seguindo a ordem relativa do catálogo de Card Variant Type mas renumerada dentro da Card (ex.: Card com apenas `HOLO` e `REVERSE_HOLO` recebe `variant_order = 1` e `2`, não `2` e `3`). Regra de `is_default`: `STANDARD` é padrão quando há impressão normal; `HOLO` é padrão quando a impressão principal é holográfica; variantes paralelas (`REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED`) não são padrão, salvo evidência editorial excepcional. Forma da Query: `INSERT ... SELECT ... ON CONFLICT (card_id, variant_type_id) DO UPDATE SET variant_order, is_default, updated_at` (idempotente), com validações internas planejadas contra: Card inexistente; Variant Type inexistente; Card duplicada no dataset; mais de uma variante padrão por Card; Card sem variante padrão; ordem duplicada ou descontínua; associação entre Games diferentes; quantidade de Cards processadas divergente da esperada. Primeiro passo concreto confirmado: `860A` (ME1) como piloto, validando fontes, mapeamento, tratamento de holográficas/reverse, estrutura do UPSERT e consultas de auditoria antes de repetir o processo nos demais Sets sem alterar a lógica estrutural. **Nada disso foi executado ainda.**

---

## Card Asset Type (Tipo de Ativo da Carta) / Card Asset (Ativo da Carta)

### Status

**Card Asset Type: pacote técnico CONCLUÍDO E EXECUTADO** (`170`/`171`/`870`/`970`, ver "SQL confirmada" abaixo). **Card Asset: estrutura física já existente no Supabase, confirmada via inspeção (Table Editor); SQL de `180`/`181`/`980` recebida mas execução NÃO confirmada** (ver "SQL recebida para `180`/`181`/`980`", abaixo). Nomenclatura final: "Card Asset"/"Card Asset Type" — não "Card Image"/"Card Image Type", nome inicialmente cogitado e depois generalizado (ver "Como chegamos aqui", abaixo).

> **Colisão confirmada com tabelas físicas já existentes — divergências reais encontradas em relação à proposta.** `06-pipeline-importacao.md` já registrava que `card_asset` e `card_asset_type` fazem parte do conjunto original de 17 tabelas físicas pré-existentes a esta fase de documentação. Fabrício confirmou via captura de tela do Table Editor do Supabase: `card_asset_type` bate exatamente com a estrutura proposta abaixo. `card_asset`, porém, **diverge em pontos importantes** — ver "Estrutura Física Real (confirmada)", abaixo. A proposta de `170`/`180` foi desenvolvida sem checar a estrutura física existente (mesmo padrão já visto com `card_variant`/`card_variant_type`), e a Query `170`/`180` ainda não deve ser escrita como um `CREATE TABLE` novo — as tabelas já existem; o trabalho remanescente é de documentação retroativa (como já feito para Game/Card/etc.), não de criação.

### Como chegamos aqui

Durante um intervalo do trabalho em `860A`, Fabrício levantou uma lacuna: "Em qual tabela estarão as imagens das cartas, tendo em vista que a ilustração é específica da carta?" A resposta: a imagem não deveria ficar na tabela `card`, porque não é um atributo relacional da carta — é um ativo digital. Adicionar campos como `image_url`/`image_small`/`image_large`/`image_thumbnail`/`image_hash` diretamente em `card` misturaria duas responsabilidades (representar a carta; gerenciar ativos digitais), problema que tende a aparecer conforme o projeto cresce.

Proposta inicial: nova entidade `170 - Card Image`, entre Card e Card Variant. Refinamento imediato, ainda na mesma discussão: a ilustração central pertence à Card, mas a imagem completa de uma carta pode mudar conforme a variante (`STANDARD`, `REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED` alteram acabamento, brilho, textura e selo, mesmo com a mesma arte) — limitar o ativo apenas à Card criaria uma nova lacuna. Generalização final: em vez de "Card Image", a entidade deveria se chamar **Card Asset**, já que o projeto pode querer armazenar, no futuro, mais do que imagens (imagem em alta resolução, verso da carta, PNG com fundo transparente, ícone, áudio do Pokémon, vídeo promocional, PDF do checklist, arquivo 3D) — tudo continua sendo um ativo da Card. Fabrício confirmou explicitamente que o projeto pretende ser um catálogo completo, com governança de dados, rastreabilidade e potencial de crescimento — não um banco simples para um app de checklist — o que justificou o ajuste arquitetural antes de avançar para `860`.

### Card Asset Type

Representa a finalidade semântica do ativo (não a resolução/dimensão). Estrutura proposta: `id, game_id, code, name, description, asset_order, is_active, created_at, updated_at`. Catálogo inicial sugerido: `CARD_FRONT`, `CARD_BACK`, `ARTWORK`, `THUMBNAIL`, `SET_SYMBOL`. Deliberadamente **não** inclui `SMALL`/`LARGE`/`HIRES` como tipos — esses termos descrevem resolução, não finalidade; uma imagem `CARD_FRONT` pode ter várias dimensões (`245×342`, `734×1024`, `1468×2048`) e continuar sendo `CARD_FRONT`.

### Card Asset

Representa o arquivo ou recurso digital propriamente dito. Estrutura proposta: `id, card_id, card_variant_id, asset_type_id, source_code, source_reference, storage_provider, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at`.

Relacionamento com Card e Card Variant: `card_id` obrigatório; `card_variant_id` **opcional**. Exemplo de ativo comum a todas as variantes: `card_id = ME1-001`, `card_variant_id = NULL`, `asset_type = ARTWORK`. Exemplo de imagem específica da versão Reverse Holo: `card_id = ME1-001`, `card_variant_id = ME1-001-REVERSE_HOLO`, `asset_type = CARD_FRONT`. Quando `card_variant_id` estiver preenchido, um trigger planejado deverá garantir que essa variante pertence ao mesmo `card_id` (mesmo padrão de consistência já usado entre Card/Card Variant Type em `161`). A duplicação de `card_id` (presente mesmo quando `card_variant_id` também está preenchido) é intencional — simplifica consultas, organização do Storage e validações de cobertura.

`source_code` (proposto: `POKEMON`, `TCGDEX`, `LOCAL_SCAN`, `CUSTOM`) permite governança de procedência — mesmo padrão já usado em `ADR-008`/`06-pipeline-importacao.md`. Exemplo dado por Fabrício: se amanhã o usuário escanear suas próprias cartas, nada muda na Card — apenas se adiciona um novo `card_asset` com `source_code = LOCAL_SCAN`, sem alterar a imagem oficial já cadastrada (podendo coexistir `Official Large`, `Official Small`, `Local Scan Front`, `Local Scan Back` para a mesma Card).

### Estrutura Física Real (confirmada via Table Editor)

`card_asset_type`: `id, game_id, code, name, description, asset_order, is_active, created_at, updated_at` — **idêntica** à proposta acima.

`card_asset`: `id, card_id, asset_type_id, source_code, source_reference, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at, language_id, storage_bucket_id`.

Três divergências em relação à proposta original — a primeira agora explicada e resolvida, as outras duas ainda abertas:

1. **`card_variant_id` ausente — RESOLVIDO/EXPLICADO.** Em uma retomada da discussão, Fabrício corrigiu explicitamente o rumo do design: "Não pretendi representar com imagens as variações das cartas! A ilustração será representada de uma única forma." A resposta confirmou: a imagem pertence exclusivamente à Card; não há (nem deve haver) relacionamento entre `card_asset` e `card_variant`. Arquitetura final: `Card` possui uma identidade visual única; `Card Variant` representa acabamento, impressão ou distribuição; `Card Asset` representa digitalmente a Card, nunca a Variant — os dois filhos de Card (`Card Variant` e `Card Asset`) são independentes entre si. Isso explica (não apenas coincide com) a ausência de `card_variant_id` na tabela física real — era intencional desde o início, não uma lacuna.
2. **`storage_provider` (texto livre) vs. `storage_bucket_id` (FK) — ainda não resolvida.** Uma nova rodada de discussão reintroduziu `storage_provider` (com valores como `SUPABASE`/`EXTERNAL`) na proposta, mas a tabela física real confirmada continua usando `storage_bucket_id`. Não presumido — os dois desenhos coexistem apenas como histórico de discussão; a estrutura física é a que vale até indicação contrária de Fabrício.
3. **`language_id` — ainda não resolvida.** Ausente de todas as propostas de `card_asset` vistas até agora (incluindo a mais recente), mas presente na tabela física real. Não presumido — aguardando esclarecimento de Fabrício sobre a relação entre `card_asset.language_id` e a ainda-não-documentada Card Translation.

### Regras adicionais de `card_asset` (discussão, não executadas)

**Localização do arquivo**: um registro pode apontar para armazenamento interno ou externo — `storage_provider = SUPABASE` com `storage_path` preenchido e `external_url = NULL`, ou `storage_provider = EXTERNAL` com `storage_path = NULL` e `external_url` preenchido. Uma constraint deve exigir pelo menos uma localização válida.

**Ativo principal**: no máximo um ativo principal (`is_primary = TRUE`) por combinação `card_id` + `asset_type_id`, garantido por índice único parcial: `CREATE UNIQUE INDEX uq_card_asset_one_primary ON public.card_asset (card_id, asset_type_id) WHERE is_primary = TRUE`.

**Integridade técnica planejada**: dimensões (`width_pixels`/`height_pixels`) maiores que zero; `file_size_bytes` não negativo; `asset_order` maior que zero; `external_url` ou `storage_path` informado; Asset Type pertencente ao mesmo Game da Card; ausência de duplicidade lógica; exclusão protegida das entidades referenciadas; RLS habilitado.

**Cardinalidade e escopo inicial reduzido**: `Card 1 — N Card Asset` — mesmo representando a carta visualmente de uma única forma, é possível manter mais de um arquivo técnico para a mesma Card (ex.: `CARD_FRONT`-thumbnail, `CARD_FRONT`-resolução padrão, `CARD_FRONT`-alta resolução, `ARTWORK`-ilustração recortada) — esses arquivos não representam variantes colecionáveis, apenas formatos/finalidades digitais diferentes da mesma ilustração editorial. Decisão de escopo: como o objetivo imediato é exibir uma imagem única da frente da carta, o seed inicial usará apenas o tipo `CARD_FRONT` — os demais tipos (`ARTWORK`, `CARD_BACK`) permanecem catalogados para uso futuro, sem uso imediato.

### SQL confirmada — `170`/`171`/`870`/`970` (Card Asset Type) — CONCLUÍDA E EXECUTADA

**Bloco encerrado.** As quatro Queries foram escritas em `database/` (`schema/170_create_card_asset_type_table.sql`, `schema/171_create_card_asset_type_triggers.sql`, `seeds/870_seed_card_asset_type.sql`, `validations/970_validate_card_asset_type.sql`), com o cabeçalho reformatado para o padrão STD-001 e os comentários `COMMENT ON` traduzidos para português (lógica SQL preservada integralmente frente ao texto executado).

`170`/`171` foram confirmados por **inferência técnica direta** (mesmo padrão já usado anteriormente para `140`/`141`): a Query `970`, que valida estruturalmente a existência de tabela, PK, FK, constraints, índices, trigger e RLS, foi executada com sucesso e produziu seu próprio marcador de conclusão — o que não seria tecnicamente possível se `170`/`171` não tivessem sido aplicadas antes.

**Ciclo real de erro e correção no Seed `870`** — o problema sinalizado antes da execução (ver histórico abaixo) se confirmou na prática:

1. **v1.0** (recebida com dois problemas já sinalizados nesta documentação): cabeçalho fora do padrão STD-001 e código de Game `POKEMON_TCG` (inexistente no projeto). Fabrício tentou executar a versão original e obteve exatamente o erro previsto: `ERROR: P0001: Game with code POKEMON_TCG was not found. Query 870 cannot continue.` — confirmando o alerta desta documentação.
2. **v1.1**: corrigiu apenas o idioma de `name`/`description` (inglês → português), sem corrigir o código de Game.
3. **v1.2** (executada com sucesso): corrigiu simultaneamente o código de Game para `POKEMON` — o único código real, já usado por todos os demais seeds do projeto — e o idioma de `name`/`description`. A sessão pareada (ChatGPT) chegou a cogitar inserir um novo Game ou adivinhar um código alternativo; Fabrício rejeitou essa direção explicitamente ("Mas você não está guardando o histórico das nossas querys? Não quero correr o risco de outras inconsistências"), levando à correção correta baseada no histórico real do projeto.

**Episódio de perda de contexto e autocorreção**: a sessão pareada reconheceu formalmente o problema — "eu não deveria ter inferido um novo código. Deveria ter preservado o padrão já estabelecido ou solicitado confirmação antes de gerar o bloco" — e se comprometeu a validar explicitamente nomes/códigos consolidados do projeto (tabelas, colunas, FKs, códigos de negócio, triggers, funções utilitárias, ordem de migrations) antes de gerar cada nova Query daqui em diante.

`970` v1.2 confirmou sucesso com seu próprio marcador de saída: *"Query 970 concluída com sucesso: card_asset_type está estruturalmente válida e com a carga canônica correta."* Catálogo canônico final, Game `POKEMON`: `CARD_FRONT` (ordem 1), `ARTWORK` (ordem 2), `CARD_BACK` (ordem 3) — todos `is_active = TRUE`.

> **Nota técnica preservada**: como `card_asset_type` já existia fisicamente antes deste ciclo, `170` como `CREATE TABLE IF NOT EXISTS` não adicionou retroativamente constraints a uma tabela pré-existente com estrutura divergente — neste caso a estrutura física já batia exatamente com a proposta, então não houve impacto prático.

### SQL confirmada — `180`/`181`/`980` (Card Asset) — CONCLUÍDA E EXECUTADA (v1.1), com uma ressalva técnica importante NÃO resolvida

Fabrício regenerou as três Queries ("Vamos garantir que esse bloco não tenha erro. Gere novamente as querys 180... 181... 980") e confirmou diretamente: **"Excelente. Executadas com sucesso."** Diferente do lote anterior (`870` v1.0), o cabeçalho já veio no padrão STD-001, sem necessidade de reformatação — escrito em `database/schema/180_create_card_asset_table.sql`, `database/schema/181_create_card_asset_triggers.sql`, `database/validations/980_validate_card_asset_structure.sql`, verbatim. A função/trigger de consistência de Game em `181` foi conferida como estruturalmente idêntica ao padrão já usado em `161` (mesmo formato de `DECLARE`/`SELECT`/`RAISE EXCEPTION`).

> **Ressalva técnica importante, sinalizada e NÃO resolvida unilateralmente: a Query `180` provavelmente não alterou a estrutura física real da tabela.** `card_asset` já existia fisicamente antes desta Query (confirmado via Table Editor na revisão anterior, com 20 colunas reais incluindo `storage_bucket_id` e `language_id`, sem `storage_provider`). A `180` v1.1 usa `CREATE TABLE IF NOT EXISTS`, que em PostgreSQL é um no-op completo quando a tabela já existe — nenhuma coluna, constraint ou índice novo é de fato aplicado, e nenhum erro é lançado. A `180` v1.1 propõe 19 colunas com `storage_provider` (texto), sem `storage_bucket_id` nem `language_id` — divergente da estrutura física real já confirmada. **"Executadas com sucesso" é tecnicamente compatível com um no-op silencioso** para a parte de tabela. Já a `181` (triggers) é diferente: como o trigger só referencia `card_id`/`asset_type_id` (ambas colunas presentes na estrutura real), a criação do trigger é genuína e provavelmente foi de fato aplicada. A `980` (validação) é composta inteiramente por `SELECT`s informativos, sem `RAISE EXCEPTION` — ou seja, não teria lançado erro mesmo que a contagem real de colunas/constraints divergisse dos valores "esperado" nos comentários (ex.: bloco 2 espera 19 colunas; a estrutura real tem 20). **Pergunta em aberto para Fabrício**: os blocos 2 e 3 da `980` retornaram de fato os números documentados (19 colunas; 1 PK + 2 FK + 1 UNIQUE + 13 CHECK), ou a tabela real continua com a estrutura de 20 colunas já confirmada anteriormente? Se a segunda opção for verdadeira, será necessária uma migration/`ALTER TABLE` explícita para aplicar as novas regras de `180` — não presumido, nem corrigido unilateralmente.

### Sequência de Queries

```text
170 - Create Card Asset Type Table       (EXECUTADA — confirmada por inferência técnica via 970)
171 - Create Card Asset Type Triggers    (EXECUTADA — confirmada por inferência técnica via 970)
870 - Seed Card Asset Type               (EXECUTADA v1.2 — corrigido código de Game e idioma)
970 - Validate Card Asset Type           (EXECUTADA v1.2 — sucesso confirmado com marcador próprio)

180 - Create Card Asset Table            (EXECUTADA v1.1 — CREATE TABLE IF NOT EXISTS, possível no-op contra tabela já existente, ver ressalva acima)
181 - Create Card Asset Triggers         (EXECUTADA v1.1 — trigger genuinamente criado, confirmado por Fabrício)
980 - Validate Card Asset Structure      (EXECUTADA v1.1 — sem erro, mas resultados numéricos dos blocos 2/3 não confirmados)

880 - Seed Card Asset                    (planejada — escopo confirmado: apenas CARD_FRONT, card_id direto, sem depender da Query 860; pré-requisitos ainda em aberto, ver seção "Query 880 — Escopo Confirmado", abaixo)
```

### Query 860 — Mudança de metodologia: Matriz Editorial explícita (Opção B, confirmada)

Com `170`/`171`/`870`/`970` e `180`/`181`/`980` concluídos, Fabrício confirmou: **"Excelente. Executadas com sucesso. Ficamos com duas querys importantes pendentes. Esse deve ser nosso foco agora. Querys 860 e 880."** Ordem confirmada: `860` antes de `880` — a `860` consolida todas as variações editoriais oficiais de cada Card antes de qualquer carga de imagem; a imagem não depende das variantes, mas concluir primeiro a `860` fecha integralmente o catálogo das Cartas antes de carregar os ativos digitais.

**Escopo confirmado da `860`**: cadastrar, para cada Card, apenas os tipos de Card Variant que realmente existem — `STANDARD`, `HOLO`, `REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED` — nunca presumidos. Define também: `variant_order` contínuo e local por Card; exatamente uma variante padrão (`is_default = TRUE`) por Card; vínculo correto com `card_variant_type`; carga idempotente; tratamento explícito das exceções editoriais.

**Mudança de metodologia proposta e adotada, antes de qualquer SQL.** A ideia original era popular direto por Card Set (`860A`–`860F` → `860` consolidada). Fabrício e a sessão pareada decidiram, em vez disso, criar uma **Matriz Editorial de Variantes** explícita para cada coleção antes de gerar qualquer SQL: uma tabela de referência (Card × tipo de variante, com marcação de existência) que serve como fonte da verdade para a `860`. Fluxo revisado: `860A.1` construção da matriz → `860A.2` validação da matriz → `860A.3` geração do SQL → validação → próxima coleção (`ME2`, `ME2.5`, ...). Racional: separar "quais variantes existem" de "como escrever o SQL" reduz o risco de ter que revisar centenas de registros depois — a `860` é considerada a maior migration do projeto até agora.

**Duas opções de regra de geração foram avaliadas — Opção A rejeitada, Opção B adotada.**
- **Opção A (rejeitada)**: derivar a variante principal dinamicamente a partir da Rarity da Card via `CASE` (`COMMON`/`UNCOMMON` → `STANDARD`; `RARE`/`DOUBLE_RARE` → `HOLO`), sem enumerar manualmente. Vantagem: SQL pequeno, fácil manutenção. Desvantagem, decisiva para a rejeição: assume que a relação raridade→variante é consistente entre todas as coleções — "nem sempre é verdade no Pokémon TCG". Esta lógica de derivação por raridade foi usada apenas como ferramenta de **validação** dos totais da ME1 (ver abaixo), não como base da Query final.
- **Opção B (adotada, confirmada por Fabrício: "Vamos com Opção B")**: Matriz Editorial explícita — cada combinação Card + Card Variant Type é declarada objetivamente (`collector_number, card_name, variant_type_code, variant_order, is_default, editorial_note`), sem nenhuma inferência automática. Mais fiel ao checklist oficial, sem depender de suposições que podem deixar de valer em coleções futuras, facilita auditoria contra fontes oficiais. Regras de construção: uma linha por variante real; nenhuma variante presumida; `variant_order` definido por Card; exatamente uma variante com `is_default = TRUE`; identificação da Card por `collector_number` dentro da coleção; identificação do tipo por `card_variant_type.code`; carga idempotente; validação da quantidade esperada antes do `COMMIT`.

**Ordem canônica global de `variant_order` proposta nesta rodada**: `STANDARD` (1), `HOLO` (2), `REVERSE_HOLO` (3), `POKE_BALL_REVERSE` (4), `MASTER_BALL_REVERSE` (5), `PROMO_STAMPED` (6) — mesma ordem já usada em `display_order` de `card_variant_type` (`850`). **Atenção, ainda não confirmado se contradiz regra anterior**: a revisão `1.32` já havia registrado que `variant_order` deve ser "local à Card, sequencial e sem lacunas" (ex.: Card só com `HOLO`+`REVERSE_HOLO` recebe `variant_order = 1` e `2`, não `2` e `3`) — a nova proposta desta rodada não deixou explícito se a ordem global 1–6 será renumerada localmente por Card antes da carga, ou se será usada diretamente como veio (o que geraria lacunas, ex. uma Card apenas `HOLO`+`REVERSE_HOLO` ficaria com `variant_order = 2` e `3`). **Sinalizado, não resolvido** — precisa de confirmação de Fabrício antes da geração do SQL real da `860A`.

**Regra de `is_default` confirmada**: `STANDARD` é padrão quando existir; `HOLO` é padrão apenas quando `STANDARD` não existir para aquela Card; todas as demais variantes (incluindo `REVERSE_HOLO`) nunca são padrão.

#### Matriz Editorial da ME1 — primeira consolidação (analítica, SQL ainda não gerado)

Usando o checklist oficial PT-BR (`P10346_ME01_Card_List_PTBR.pdf`, já arquivado) e a carga real de `840` (`ME1`, 188 Cards, `base_set_size = 132`), a matriz da ME1 foi consolidada:

- **Cartas `001`–`132` (conjunto base, `collector_order ≤ 132`)**: `COMMON`/`UNCOMMON` recebem `STANDARD` (`variant_order 1`, `is_default TRUE`) + `REVERSE_HOLO` (`variant_order 2`, `is_default FALSE`); as 11 Cards `RARE` recebem `HOLO` (`variant_order 1`, `is_default TRUE`) + `REVERSE_HOLO` (`variant_order 2`, `is_default FALSE`); as 10 Cards `DOUBLE_RARE` (todas Mega Pokémon `ex`) recebem **apenas** `HOLO` (`variant_order 1`, `is_default TRUE`) — não recebem `REVERSE_HOLO`.
- **Cartas `133`–`188` (acima do conjunto base — Full Art/Secret Rare/etc.)**: aparecem no checklist oficial como "Cartas Laminadas Padrão", recebendo apenas `HOLO` (`variant_order 1`, `is_default TRUE`), sem reversa adicional.
- **Correção de uma premissa inicial**: a hipótese preliminar de "10 cartas do conjunto base sem reversa, de forma arbitrária" foi substituída pela regra real — são exatamente as 10 Cards `DOUBLE_RARE` (`003` Mega Venusaur ex, `022` Mega Camerupt ex, `036` Abomasnow ex, `050` Mega Manectric ex, `060` Mega Gardevoir ex, `077` Mega Lucario ex, `086` Absol ex, `094` Mega Mawile ex, `100` Mega Latias ex, `104` Mega Kangaskhan ex). As 11 Cards `RARE` (`010` Meganium, `028` Cinderace, `034` Kyogre, `038` Clawitzer, `048` Raikou, `056` Alakazam, `064` Xerneas, `073` Hariyama, `088` Yveltal, `093` Steelix, `095` Dialga) recebem `HOLO`+`REVERSE_HOLO` normalmente.
- **`POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE` não existem na ME1** (documentação pública consultada não registra esse padrão para esta coleção). Produtos promocionais/estampados associados à era da coleção (ex. Bulbasaur box topper, promos de pré-lançamento/loja) existem, mas **não fazem parte da numeração editorial principal** — tratados separadamente, `PROMO_STAMPED` só entrará mediante identificação explícita das Cards promocionais dentro do escopo do catálogo.

**Total consolidado da ME1**: 111 `STANDARD` + 77 `HOLO` + 122 `REVERSE_HOLO` = **310 Card Variants esperados** (188 Cards base geram 188 variantes "principais" — 111 `STANDARD` das `COMMON`/`UNCOMMON` do conjunto base, mais 21 `HOLO` das `RARE`+`DOUBLE_RARE`, mais 56 `HOLO` das `133`–`188` = 77 `HOLO` total; `REVERSE_HOLO` = 111 `COMMON`/`UNCOMMON` + 11 `RARE` = 122, excluindo as 10 `DOUBLE_RARE`). Este total foi calculado, não ainda carregado — **nada foi executado na `860` até este ponto**, apenas a análise/matriz.

### Query 880 — Escopo Confirmado (SQL ainda não escrita)

Fabrício confirmou o escopo inicial da `880`: cadastrar a representação visual única de cada Card, com `asset_type = CARD_FRONT`, `is_primary = TRUE`, `asset_order = 1`, vinculado diretamente a `card_id` — **nunca a `card_variant`** (reforça a independência Card Asset ↔ Card Variant já decidida). Antes da carga, ainda é preciso definir (nenhum destes pontos decidido ainda): fonte oficial das imagens; padrão de `source_code`; padrão de `source_reference`; uso de `external_url` ou `storage_path`; convenção de nomes e caminhos; tratamento de imagens indisponíveis; estratégia de atualização futura. Próximo passo confirmado: iniciar a `860A` (ME1) — validando primeiro as regras de variantes da coleção antes de gerar qualquer SQL — e só depois seguir para `880`.

Fabrício confirmou avançar com as duas entidades, mas adiou o detalhamento fino: "Vamos chegar a detalhar essas três mais para frente. Vamos seguir o fluxo" (referindo-se também a `language`, `card_external_reference` e `card_set_external_reference`, tabelas físicas pré-existentes ainda não documentadas conceitualmente — ver `06-pipeline-importacao.md`).

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

> **Discrepância real, agora com Cards de fato cadastradas — sinalizada com urgência renovada, não resolvida unilateralmente.** Esta nota documentou originalmente que `card_category` incluía `ENERGY` como um terceiro valor cadastrado (`display_order = 3`), sem nenhuma Card ainda usando-o — deixando em aberto se era um valor de referência dormente ou uma reversão de escopo. **Essa ambiguidade foi resolvida na prática, não em palavras**: a Seed canônica `840` (v2.1, executada e confirmada — ver `05-modelo-de-dados.md`, seção Card) cadastrou **9 Cards reais de categoria `ENERGY`, com `collector_number`/`collector_order` reais, ocupando posições no catálogo numerado** — 1 em ME2 (`124 - Energia de Ignição`), 2 em ME2.5 (`216`/`217`), 3 em ME3 (`086`-`088`), 3 em ME4 (`084`-`086`). Isso é a leitura (b) do parágrafo anterior acontecendo de fato, em produção — cartas de Energia **estão** ocupando posições numeradas do catálogo, contradizendo diretamente o texto desta "Decisão de Escopo — Cartas de Energia". **Ainda assim, esta seção não foi alterada nem revogada unilateralmente** — nenhuma mensagem explícita de Fabrício confirmou "sim, revertemos a decisão de excluir Energia do catálogo numerado"; a inclusão aconteceu como efeito colateral de importar os checklists oficiais completos, sem uma discussão explícita sobre esta seção específica. Fabrício precisa confirmar diretamente se a decisão de escopo deve ser formalmente revertida (e esta seção reescrita) ou se as 9 Cards de Energia devem ser removidas do catálogo para manter a decisão original.

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
| 1.24 | **Correção de versão + descoberta de `PROMO` como raridade oficial** (mesma correção registrada em `05-modelo-de-dados.md` 0.20). Nova seção "`PROMO` é uma Raridade Oficial (decisão tomada, execução pendente)": `PROMO` é uma classificação oficial do Pokémon TCG, não uma invenção do projeto; compartilha `symbol_code = BLACK_STAR` com `RARE`, confirmando `symbol_code` fora da chave de unicidade; nova ordem de exibição decidida. Consequência arquitetural sinalizada para a futura Card: `card_set.set_type = PROMO` e `rarity.code = PROMO` são independentes e complementares. Adicionada nota cruzada na seção "Card Set Promocional". Decisão confirmada por Fabrício, mas Queries `830`/`930` (v1.2, incluindo `PROMO`) ainda não escritas nem executadas. |
| 1.25 | **Entidade Rarity oficialmente encerrada.** `PROMO` incluída via `830`/`930` v1.2, executadas e confirmadas por Fabrício. Seção "`PROMO` é uma Raridade Oficial" atualizada de "decisão tomada, execução pendente" para "confirmada e executada". |
| 1.26 | **Revisão arquitetural importante de Card iniciada, explicitamente não concluída.** Fabrício respondeu a uma pergunta direta: Card representa "a carta editorial de forma única, que pode aparecer em vários Sets" — não uma posição fixa dentro de um Set específico. Isso inverte a premissa de identidade "Set + Número" (ADR-004) usada até aqui: `Card Printing` passa a depender de dois pais (`Card` e `Card Set`), não apenas de `Card Set`. Adicionada nota de revisão na seção "Identidade" (preservada, não substituída) e callout no início de "Modelagem Física — Discussão Iniciada". Nova seção "Revisão Arquitetural — Identidade Editorial Independente de Set": definições revisadas de Card/Card Printing/Card Variant/Collection Item; novo "Princípio: Identidade Editorial"; listas do que cria/não cria uma nova Card; distinção ilustração-vs-texto; rascunho não aprovado de nova forma para `card` (`id, game_id, name, category_code, editorial_key, created_at, updated_at`) com `editorial_key` sinalizado como indefinido; `ENERGY` resurge como exemplo de categoria (não resolvido); pergunta final da discussão ("quais atributos distinguem um design editorial de outro") permanece sem resposta. ADR-004 sinalizada como potencialmente afetada, mas não alterada. |
| 1.27 | **Card reverte para identidade Set-específica (decisão final) + nova entidade Card Category executada.** Fabrício reconsiderou a "Revisão Arquitetural — Identidade Editorial Independente de Set" (revisão 1.26): "Estou achando melhor considerar uma 'Card' como uma representação da carta dentro de um Set específico [...] Fiquei com receio do modelo anterior trazer dificuldades no cadastro" — evitaria ter que comparar dados de gameplay (não estruturados, por AP-017) só para detectar reimpressões. Nova seção "Revisão Arquitetural — Card Volta a Pertencer a um Card Set": Card Printing removida por ora; `card_number` renomeado `collector_number`; `name` armazenado exatamente como impresso; categoria vira FK para nova entidade `Card Category`; nenhum `card_code` persistido (derivado via VIEW); tabela `card_relation` para reprints registrada como extensão futura, não construída. Citado explicitamente o AP-010 (Responsible Generalization) já existente. Sinalizada tensão não resolvida com AP-011 (Editorial Identity). Modelo final aprovado por Fabrício ("Concordo"), ainda não executado. Nova entidade **Card Category** executada e confirmada (`132`/`133`/`831`/`931`) com três valores reais: `POKEMON`, `TRAINER`, `ENERGY` — **`ENERGY` contradiz diretamente a "Decisão de Escopo — Cartas de Energia"** já registrada; sinalizado com urgência na seção correspondente, não resolvido unilateralmente. Callouts de "Identidade" e "Modelagem Física — Discussão Iniciada" atualizados para refletir o histórico completo (proposta → reaberta → revertida). |
| 1.28 | **Refinamento do modelo de Card (Versão 1.1) + SQL real de `140`/`141`/`940` recebida, execução não confirmada.** Validação campo a campo do modelo aprovado na revisão 1.27 levou a dois novos campos: `collector_total` (denominador impresso, ex. `182` em `021/182` — distinto de `card_set.total_set_size`, já que seções especiais como `TG`/`GG` têm denominador próprio e promocionais como `SVP001` não têm denominador) e `collector_order` (reintroduzido — havia sido removido silenciosamente na revisão 1.27; necessário porque `collector_number` sozinho não ordena corretamente números não puramente numéricos como `TG01`/`SVP001`/`12a`). Nova decisão sobre idioma de `name`: Opção B confirmada — Card sempre guarda o nome no idioma da edição/Card Set em que foi cadastrada, sem camada de tradução própria em `card` (Fabrício: "a Card representa exatamente o catálogo daquele Set. Não precisamos criar uma camada de tradução"). Nova regra de negócio: Card Set, Rarity e Card Category referenciados por uma mesma Card devem pertencer ao mesmo Game — implementada via trigger de validação dedicado (`validate_card_game_consistency()`), primeira vez que esse padrão aparece no projeto (além do já-usual trigger de `updated_at`). SQL verbatim de `140`/`141`/`940` recebida com header oficial completo (`Status: CANÔNICA`, `Versão: 1.0`), mas **não copiada para `database/`** — nenhuma confirmação explícita de execução foi recebida neste lote (regra de `database/README.md`: arquivos só são copiados após execução confirmada). Query `840 - Seed Card` permanece deliberadamente não escrita; PDF de referência de ME1 (`P10346_ME01_Card_List_PTBR.pdf`) já estava arquivado de um ciclo anterior. |
| 1.29 | **`140`/`141` confirmados por inferência técnica; Seed `840` v2.1 executada e confirmada por Fabrício — 859 Cards, os cinco Card Sets da expansão Megaevolução.** Fabrício validou o PDF de ME1 como fonte suficiente para número/nome/categoria/raridade (via legenda de símbolos), decidindo que `collector_total` seria derivado de `card_set.base_set_size` (não lido diretamente do checklist, que não exibe o denominador em toda carta). Propôs então ampliar de ME1 para os cinco Card Sets de uma vez ("Temos condições de fazer o mesmo com ME2, ME2.5, ME3 e ME4") — a sessão pareada foi além e recomendou uma mudança de arquitetura: uma única Query `840` canônica cobrindo todo o catálogo suportado (não uma Seed por Set), generalizando o Princípio da Fonte Canônica de DDL/domínios para seeds de dados de catálogo em massa; futuras expansões atualizarão a mesma Query. **Fabrício confirmou diretamente: "Executei com sucesso."** `140`/`141` tratadas como confirmadas por inferência técnica direta (a Seed de 859 linhas depende estruturalmente delas já existirem), documentada explicitamente como inferência, não presunção. **Discrepância `ENERGY` elevada de "valor cadastrado" para "9 Cards reais, numeradas, em produção"** (1 em ME2, 2 em ME2.5, 3 em ME3, 3 em ME4) — nota de discrepância na seção Card Category reescrita para refletir essa concretização, ainda sem confirmação de Fabrício sobre se a decisão de escopo original deve ser revertida. Query `940` reexecutada uma vez sobre os dados reais (resultados corretos), mas identificada como precisando de uma seção canônica explícita (5 Sets + total 859) antes de virar a versão final — reescrita ainda pendente, apesar de Fabrício ter confirmado a intenção ("Vamos atualizar query 940 então"). Arquivos `database/schema/140_*.sql`, `database/schema/141_*.sql`, `database/seeds/840_seed_card.sql` (v2.1) criados no repositório. |
| 1.30 | **Query `940` reescrita para Versão 2.0 (27 blocos), executada e confirmada — pacote técnico de Card tecnicamente completo; correção importante: bloco "Editorial Catalog" ainda não está de fato concluído.** Fabrício confirmou diretamente ("Pronto! Executado com sucesso.") a execução de `940` v2.0, fechando o ciclo `140`/`141`/`840`/`940`. Nova entidade proposta pela sessão pareada, sob o nome "Card Variant" (não "Finish"/"Card Finish"): `card_variant_type` (catálogo de tipos por Game, ex. `STANDARD`, `REVERSE_HOLO`, `PROMO_STAMPED`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`) e `card_variant` (`id, card_id, variant_type_id, variant_order, is_default, created_at, updated_at`) — sequência de Queries planejada (`150`/`151`/`850`/`950`, depois `160`/`161`/`860`/`960`), **nenhuma DDL escrita ou executada**. Nota em aberto pré-existente na seção Finish/Card Finish atualizada com esta proposta concreta: sinalizado que os nomes físicos `card_variant`/`card_variant_type` já existiam no banco desde antes da renomeação conceitual de ADR-010 (parte do conjunto original de 17 tabelas), então esta proposta pode ser simplesmente a implementação das tabelas físicas já existentes sob seus nomes originais — mas a tensão de nomenclatura com Finish/Card Finish não foi resolvida por Fabrício, e não deve ser decidida unilateralmente. Sinalizado também um uso do termo "Inventory Item" (já renomeado para Collection Item via ADR-013) no exemplo ilustrativo da sessão pareada — provável hábito antigo, não alteração deliberada. **Autocorreção importante da própria sessão pareada**: antes de avançar para o bloco "200 — Collections", identificou-se que o bloco "100 — Editorial Catalog" ainda não está de fato concluído — falta modelar Card Variant, sem o qual uma Collection não conseguiria referenciar qual versão colecionável de uma Card está sendo colecionada (ex. Standard vs. Reverse Holo). Proposta separada e explicitamente deferida para o backlog técnico, não construída: um "Gerador Oficial de Seeds" (pipeline Checklist PDF → Parser → Modelo JSON → Validações → Gerador SQL → Query 840), com pasta `tools/official-seed-generator/` esboçada — Fabrício e a sessão pareada concordaram que não é prioridade agora, com a sequência de prioridades confirmada: Catálogo Editorial → Coleções → Inventário → Aquisições → Armazenamento → Analytics e Views → Automação dos Seeds (esta sequência é conteúdo de processo/roadmap, registrado apenas em memória, não como nova seção deste documento, consistente com o precedente já estabelecido para conteúdo de metodologia/sequenciamento). |
| 1.31 | **Card Variant Type executada e confirmada (`150`/`151`/`850`/`950`) — bloco "Card Variant Type" concluído; tensão com ADR-010 concretizada em produção, ainda não resolvida.** Tabela `card_variant_type` criada (`150`/`151`, v1.0) e povoada (`850`/`950`, v1.1, seis tipos: `STANDARD`, `HOLO`, `REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED`). O tipo `HOLO` foi adicionado após Fabrício identificar que o catálogo inicial (v1.0, cinco tipos) omitia uma variante distinta de `REVERSE_HOLO` ("teremos problemas quando modelarmos coleções que possuem cartas holográficas padrão sem versão reverse") — `850`/`950` reescritas para v1.1 (Princípio da Fonte Canônica), com deslocamento temporário de `display_order` para contornar a `UNIQUE` já ocupada pela v1.0 já executada. "Nota em aberto" da seção Finish/Card Finish atualizada: a execução real usa "Card Variant"/"Card Variant Type" de ponta a ponta, sem qualquer menção a "Finish", o que reforça (sem provar sozinho, já que o nome físico é anterior a ADR-010) a tensão de nomenclatura já sinalizada — decisão de Fabrício continua pendente antes de `160`/`161`/`860`/`960` (Card Variant, associação Card ↔ Card Variant Type) serem escritas. |
| 1.32 | **Card Variant (estrutura) executada e confirmada (`160`/`161`/`960`) — todo o Catálogo Editorial (`100`–`160`) estruturalmente modelado; falta apenas o Seed `860`.** Arquitetura validada formalmente antes da escrita das Queries: `card_variant` representa uma versão colecionável específica de uma Card (não uma cópia física); estrutura `id, card_id, variant_type_id, variant_order, is_default, created_at, updated_at`, com índice único parcial garantindo no máximo uma variante padrão por Card, trigger de consistência de Game (mesmo padrão de `141`), e decisão de **não persistir** `variant_code` (derivável via `card_set.code`+`card.collector_number`+`card_variant_type.code`, mesmo precedente de `card_code`). Reflexão de Fabrício sobre cadastrar variantes "da coleção" em vez de "da linha editorial" resolvida sem alterar a arquitetura: reforça, não elimina, a cadeia `Card → Card Variant → Collection Item` (catálogo informa o que existe; inventário informa o que o usuário possui) — formaliza sob o nome "Card Variant" a mesma cadeia já prevista em ADR-010 como `Card → Card Finish → Inventory Item`. Estratégia de fontes para o Seed `860` (ainda não escrito) decidida: checklist oficial + campo `variants` da TCGdex (fonte estruturada principal) + Pokémon TCG API (evidência complementar) + validação manual para `POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE`/`PROMO_STAMPED`, com carga faseada por Card Set (`860A`–`860E`) antes da consolidação canônica — ver `06-pipeline-importacao.md` para o detalhamento. Tensão de nomenclatura com ADR-010 sinalizada com evidência adicional: **ADR-008 (já aprovada) também lista "Card Variant" como entidade do Catálogo Editorial**, não "Finish"/"Card Finish" — ainda não resolvida por Fabrício. |
| 1.33 | **Estratégia do Seed `860` refinada (processo, regras de `variant_order`/`is_default`, forma idempotente da carga) — nada executado; discrepância `ME5`/`ME0` sinalizada.** Fabrício recusou adiar `860` para abrir Coleções em paralelo, reafirmando a disciplina de sequenciamento já registrada. Plano de staging por Card Set (`860A`–`860E`) detalhado com cinco etapas, tratamento diferenciado de "casos seguros" vs. "casos especiais" (`POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE`/`PROMO_STAMPED`, sempre com suporte documental, nunca inferidos), e forma de carga via `ON CONFLICT ... DO UPDATE`. Sinalizado, não resolvido: o plano citou um `860F` para "`ME5`", Card Set inexistente no catálogo atual (os reais são `ME1`–`ME4` + o promocional `ME0`, que ainda não tem Cards seedadas em `840`) — provável reaproveitamento por engano do rótulo já usado neste documento como exemplo hipotético. **Nova entidade descoberta e discutida — Card Asset Type / Card Asset (`170`/`180`), aprovada por Fabrício, não executada.** Fabrício identificou lacuna arquitetural durante o trabalho em `860A`: onde ficam as imagens das cartas? Resolvido que não pertence a `card` (mistura identidade relacional com gestão de ativos digitais). Entidade nomeada inicialmente "Card Image", generalizada para "Card Asset" (cobre imagem, áudio, vídeo, PDF, 3D — qualquer ativo futuro da Card). `card_asset_type`: catálogo semântico por Game (`CARD_FRONT`/`CARD_BACK`/`ARTWORK`/`THUMBNAIL`/`SET_SYMBOL`). `card_asset`: arquivo/recurso propriamente dito, com `card_id` obrigatório e `card_variant_id` **opcional** (ativo pode ser comum a todas as variantes ou específico de uma) e `source_code` para rastreabilidade de procedência. **Achado crítico, mesmo padrão do episódio Card Variant/Finish**: `card_asset`/`card_asset_type` já existem fisicamente entre as 17 tabelas pré-existentes a esta fase de documentação (`06-pipeline-importacao.md`) — a proposta foi desenvolvida sem verificar a estrutura física real; precisa de confirmação antes de `170`/`180` virarem DDL. Fabrício adiou o detalhamento fino desta entidade e de `language`/`card_external_reference`/`card_set_external_reference` ("Vamos chegar a detalhar essas três mais para frente. Vamos seguir o fluxo"). |
| 1.34 | **Estrutura física real de Card Asset confirmada (diverge da proposta em 3 pontos) + correção anunciada de Card Set (`ME0` → `MEP`, novo `MEE`).** Fabrício confirmou via captura de tela do Table Editor: `card_asset_type` bate exatamente com a proposta; `card_asset` diverge — sem `card_variant_id` (contradiz a proposta de imagem específica por variante), `storage_bucket_id` (FK) no lugar de `storage_provider` (texto), e novo `language_id` (FK, possivelmente ligado a Card Translation) — nenhuma resolvida, sinalizadas para esclarecimento. Seção "Card Set Promocional" recebeu nota de correção anunciada por Fabrício (SQL/migration ainda não recebida): o código `ME0` estava errado — código oficial correto é `MEP` — e um novo Card Set oficial `MEE` ("Energy Set" da Expansão) foi criado, possivelmente relevante para a discrepância `ENERGY` já registrada há várias revisões. Nota `ME5`/`ME0` da revisão `1.33` corrigida: a resposta de Fabrício não foi "use `ME0`" — o próprio `ME0` estava errado. Nenhuma alteração feita em `database/` (nenhuma SQL recebida para as correções de Card Set; Card Asset já existe fisicamente, sem DDL formal ainda capturada). |
| 1.35 | **Card Asset: relação com Card Variant descartada explicitamente (resolve 1 das 3 divergências) + SQL recebida para `170`/`171`/`870`/`970`, execução não confirmada, 2 problemas identificados.** Fabrício corrigiu o design: "Não pretendi representar com imagens as variações das cartas! A ilustração será representada de uma única forma" — confirmado que `card_asset` não se relaciona com `card_variant` (Card Asset representa digitalmente a Card, nunca a Variant), explicando a ausência de `card_variant_id` na tabela física já confirmada na revisão anterior (era intencional, não uma lacuna). Novas regras documentadas: localização de arquivo (`storage_provider`/`storage_path`/`external_url`, uma reintrodução de `storage_provider` que segue divergindo da estrutura física real com `storage_bucket_id`), índice único parcial de ativo principal (`uq_card_asset_one_primary`), regras de integridade técnica, e decisão de escopo reduzido do seed inicial (apenas `CARD_FRONT`). Texto verbatim recebido para `170`/`171`/`870`/`970` (Card Asset Type: tabela, trigger, seed de 3 tipos, validação em 18 blocos) — **sem confirmação de execução, não copiado para `database/`**. Dois problemas sinalizados antes de qualquer execução: cabeçalhos fora do padrão STD-001 (Fabrício alertou que a sessão pareada está mostrando sinais de perda de janela de contexto a partir deste ponto, pediu que a documentação mantenha o padrão já estabelecido) e um bug no Seed `870` (usa código de Game `POKEMON_TCG`, inexistente — o código real usado em todos os seeds já executados é `POKEMON`; executar causaria falha no próprio `RAISE EXCEPTION` da Query). Nota técnica adicional: como `card_asset_type` já existe fisicamente, `170` como `CREATE TABLE IF NOT EXISTS` não adicionaria retroativamente as novas constraints à tabela existente. |
| 1.36 | **Card Asset Type — pacote técnico concluído e executado (`170`/`171`/`870`/`970`); bug de Game code previsto na revisão 1.35 confirmado na prática e corrigido; `180`/`181`/`980` (Card Asset) recebidas, execução não confirmada.** Fabrício tentou executar o `870` v1.0 original e obteve exatamente o erro previsto: `ERROR: P0001: Game with code POKEMON_TCG was not found`. Ciclo de correção: v1.1 corrigiu apenas o idioma; v1.2 corrigiu simultaneamente o código de Game (`POKEMON`) e o idioma — executada com sucesso, assim como `970` v1.2, cujo próprio marcador de conclusão ("Query 970 concluída com sucesso...") confirma a validação estrutural completa. `170`/`171` tratadas como confirmadas por inferência técnica direta (mesmo padrão já usado para `140`/`141`), já que a validação de `970` depende estruturalmente delas. Fabrício rejeitou a proposta da sessão pareada de adivinhar/inserir um novo código de Game ("Não quero correr o risco de outras inconsistências") — a sessão pareada reconheceu formalmente o lapso de contexto e se comprometeu a validar nomes/códigos consolidados do projeto antes de cada nova Query. Arquivos `database/schema/170_*.sql`, `database/schema/171_*.sql`, `database/seeds/870_seed_card_asset_type.sql` (v1.2), `database/validations/970_validate_card_asset_type.sql` (v1.2) criados, com cabeçalho reformatado para STD-001 e comentários traduzidos para português (lógica idêntica ao executado). SQL de `180`/`181`/`980` (Card Asset) regenerada a pedido de Fabrício, mas **ainda sem confirmação de execução** — mesmo problema de formatação de cabeçalho e `COMMENT ON` em inglês sinalizado novamente; não copiada para `database/`. |
| 1.37 | **Card Asset (`180`/`181`/`980` v1.1) confirmada executada por Fabrício — mas com ressalva técnica importante, sinalizada e não resolvida: a Query `180` provavelmente não alterou a estrutura física real da tabela** (`CREATE TABLE IF NOT EXISTS` é no-op contra a tabela já existente confirmada na revisão `1.34`, com 20 colunas reais incluindo `storage_bucket_id`/`language_id`; a `180` v1.1 propõe 19 colunas com `storage_provider`, divergente). `181` (triggers) é diferente — referencia apenas `card_id`/`asset_type_id`, ambas reais, então a criação do trigger é genuína e estruturalmente idêntica ao padrão de `161`. `980` é composta só de `SELECT`s informativos, sem `RAISE EXCEPTION` — não acusaria erro mesmo com contagens divergentes das documentadas ("esperado: 19 colunas" etc.). Pergunta explícita deixada para Fabrício confirmar os resultados reais dos blocos 2/3 de `980`. Arquivos `database/schema/180_*.sql`, `database/schema/181_*.sql`, `database/validations/980_*.sql` criados (v1.1, cabeçalho já em STD-001, sem reformatação necessária). **Nova fase: Query `860` (Seed Card Variant) e `880` (Seed Card Asset) confirmadas como as duas pendências finais do Catálogo Editorial, ordem `860` antes de `880`.** Mudança de metodologia adotada para `860`: Matriz Editorial explícita por coleção (`860A.1` construção → `860A.2` validação → `860A.3` geração do SQL → validação → próxima coleção), substituindo a ideia original de popular direto por Card Set. Opção A (derivação dinâmica via Rarity) avaliada e rejeitada — usada só para validar totais; Opção B (matriz explícita, sem inferência) adotada, confirmada por Fabrício ("Vamos com Opção B"). Ordem canônica de `variant_order` proposta (`STANDARD`1/`HOLO`2/`REVERSE_HOLO`3/`POKE_BALL_REVERSE`4/`MASTER_BALL_REVERSE`5/`PROMO_STAMPED`6) sinalizada como potencialmente conflitante com a regra já registrada de `variant_order` local e sem lacunas por Card — não resolvido. Matriz Editorial da ME1 consolidada analiticamente (nada executado): 310 Card Variants esperados (111 `STANDARD` + 77 `HOLO` + 122 `REVERSE_HOLO`), com a lista completa das 10 Cards `DOUBLE_RARE` (sem reversa) e das 11 Cards `RARE`. Escopo da `880` confirmado (`CARD_FRONT` apenas, vinculado a `card_id` direto), com seis pontos ainda em aberto antes da carga. |