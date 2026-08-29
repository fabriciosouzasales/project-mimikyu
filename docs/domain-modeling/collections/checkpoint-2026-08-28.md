# Collection — Checkpoint Documental (2026-08-28)

| Campo | Valor |
|--------|-------|
| **Documento** | Checkpoint de Reconciliação Documental — Collections |
| **Arquivo** | `docs/domain-modeling/collections/checkpoint-2026-08-28.md` |
| **Data** | 2026-08-28 |
| **Origem** | Registrado diretamente nesta sessão do `project-mimikyu`, a partir de instrução explícita de Fabrício — não produzido no repositório de modelagem paralelo. |
| **Objetivo** | (1) Registrar decisões de ownership/simplificação mais recentes que ainda não estavam incorporadas em `logical-model.md`; (2) registrar a decisão de produto/UX de que Collections é a primeira grande superfície client-facing do MMKYU. Nenhuma decisão nova foi inventada nesta rodada — apenas as que Fabrício declarou explicitamente. |
| **Documentos Relacionados** | `concept-decisions.md` (C-01 a C-37), `logical-model.md` (LDM-01 a LDM-27, ver banner de superação parcial no topo), `pkmnbindr-benchmark.md`, `../../ROADMAP.md` (Sub-Fase 2 — Coleções). |

---

## 1. Estado que este checkpoint assume como ponto de partida

- Conceitual: `concept-decisions.md`, C-01 a C-37 — CLOSED, inalterado por este checkpoint.
- Lógico: `logical-model.md`, LDM-01 a LDM-24 — inalteradas por este checkpoint. LDM-25/26/27 — superseded pelas decisões da Seção 2, abaixo. LDM-28 (tópico original) — void, ver Seção 4.
- Físico: NÃO iniciado. Este checkpoint é puramente documental — nenhuma migration, tabela, rota ou componente foi criada nesta rodada.

---

## 2. Novas decisões registradas (simplificação do modelo de ownership)

Registradas na ordem em que Fabrício as declarou. Nenhuma foi reinterpretada ou expandida além do texto literal — onde uma implicação é apontada, ela está marcada como tal.

### 2.1 — Favorite referencia Card, nunca Card Variant

`Favorite` é um conceito novo, não modelado anteriormente em `concept-decisions.md` nem `logical-model.md`. Referencia `Card` diretamente — nunca `Card Variant`. Sem outros detalhes de modelagem (cardinalidade, dono, uso) fornecidos nesta rodada; permanece como conceito registrado, não modelado em profundidade (mesmo tratamento dado a outras entidades descobertas em `concept-decisions.md`, Parte D).

### 2.2 — Inventory Item não possui `owner_user_id` nem usuário responsável

Reverte o skeleton de `Inventory Item` descrito em LDM-23 (`owner_user_id` como campo direto) e a decisão de LDM-25 (Owner explícito por item). `Inventory Item` deixa de carregar qualquer referência direta a um usuário.

### 2.3 — Cada usuário possui um Inventory/Acervo

Introduz uma nova entidade de agregação, `Inventory` ("Acervo"), com relação 1:1 por usuário (um usuário possui exatamente um Inventory; um Inventory pertence a exatamente um usuário — cardinalidade exata não detalhada além disso nesta rodada, mas "cada usuário possui um" implica 1:1, não 1:N).

### 2.4 — Inventory Item pertence ao Inventory, não diretamente ao User

Corrige a cardinalidade: `Inventory Item → Inventory → User`, não `Inventory Item → User` direto. Combinado com 2.2/2.3, o skeleton de LDM-23 passa de:

```text
Inventory Item
├── id
├── owner_user_id       ← removido
├── card_variant_id
├── collection_id (0..1)
└── storage_container_id (0..1)
```

para (conceitual, sem nomes de coluna comprometidos — modelagem física ainda não iniciada):

```text
Inventory
├── id
└── user_id (1:1)

Inventory Item
├── id
├── inventory_id        ← novo
├── card_variant_id
├── collection_id (0..1)
└── storage_container_id (0..1)
```

### 2.5 — Collection pertence a um usuário

Reafirma LDM-02 (`owner_user_id` em Collection) — não alterada, incluída aqui só para deixar explícito que a simplificação de ownership atinge `Inventory Item`, não `Collection`.

### 2.6 — Uma Collection só pode alocar Inventory Items do Inventory desse mesmo usuário

Nova invariante: a alocação de um `Inventory Item` a uma `Collection` exige que `Inventory.user_id = Collection.owner_user_id`. Um `Inventory Item` de um Inventory nunca pode ser alocado à Collection de outro usuário.

### 2.7 — Collection Members colaboram conforme permissões; não introduzem Inventory Items próprios

Um Collection Member (LDM-03) pode colaborar na Collection (organizar, editar conforme suas permissões efetivas), mas nunca aloca um Inventory Item do seu próprio Inventory a uma Collection que não é sua — a Collection permanece alimentada exclusivamente pelo Inventory do seu Owner.

---

## 3. Impacto explícito sobre `logical-model.md` (LDM-25/26/27)

- **LDM-25 (Inventory Item Ownership) — SUPERSEDED.** A premissa "Every Inventory Item has exactly one explicit Owner" (via `owner_user_id` próprio) é substituída por 2.2–2.4: a posse é sempre transitiva via `Inventory`.
- **LDM-26 (Inventory Item Ownership Transfer) — SUPERSEDED.** Sem `owner_user_id` no item, "transferir ownership de um item" deixa de fazer sentido como operação sobre o item individual. A pergunta correta passa a ser sobre mover um Inventory Item de um `Inventory` para outro (ex.: doação/troca entre usuários) — não modelada nesta rodada, fica como lacuna aberta explícita (ver Seção 5).
- **LDM-27 (Operational Authority and Approval for Patrimonial Actions) — SUPERSEDED.** O cenário que motivava esta seção ("a shared Collection may contain items owned by different authorized members") deixa de ser possível: por 2.6, uma Collection só aloca itens do Inventory do seu próprio Owner. O fluxo de aprovação patrimonial descrito (approval request → inbox do Owner do item → aprovação/rejeição) não tem mais aplicação para este cenário. O conceito de aprovação para operações patrimoniais pode ressurgir no futuro para outro cenário real (ex.: uma troca/transferência entre dois Inventories de usuários diferentes), mas isso seria uma decisão nova, não uma reaplicação desta seção.

---

## 4. LDM-28 original — void

O tópico de continuação registrado ao final de `logical-model.md` ("LDM-28 — Removing a Collection Member Who Still Owns Inventory Items Allocated to the Collection") depende diretamente da premissa superada em LDM-25/27: um Member possuindo itens alocados na Collection. Como Members nunca introduzem Inventory Items próprios na Collection (Seção 2.7), esse cenário não pode mais ocorrer — o tópico está void.

Um novo tópico de LDM-28 (ou numeração seguinte, a confirmar quando a modelagem lógica for retomada) precisa ser aberto quando o trabalho de modelagem lógica avançar novamente. Este checkpoint **não antecipa** qual deve ser esse novo tópico — decisão explícita de Fabrício nesta rodada: "sem inventar novas decisões".

---

## 5. Residual conflict resolvido — C-36 prevalece sobre a redação de LDM-10

`concept-decisions.md` (C-36) já declarava: "Toda Collection possui um Default Storage Container, obrigatoriamente definido em sua criação." `logical-model.md` (LDM-10), ao descrever o campo `default_storage_container_id`, usa a redação "Collection *may* define" — tratando-o como opcional na prática, mesmo sem contradizer C-36 explicitamente.

Fabrício confirmou nesta rodada: **C-36 prevalece sobre a redação de LDM-10** — `default_storage_container_id` é obrigatório, não opcional. A semântica operacional de LDM-10 (default de UX/sugestão, não exclusividade, não move itens existentes ao ser alterado) permanece correta e válida; só a obrigatoriedade na criação estava sub-representada. `logical-model.md` foi anotado com esta correção no próprio corpo do documento (ver banner e nota em LDM-10).

---

## 6. Reafirmações explícitas (sem mudança de modelo)

- **OPEN_CURATION continua restrita ao mesmo Game.** Já decorria de C-05/C-35 (Collection pertence a exatamente um Game, imutável) combinado com LDM-04 (mode não afeta o campo `game_id` da Collection root, LDM-12) — reafirmado explicitamente por Fabrício nesta rodada para eliminar qualquer ambiguidade de que curadoria aberta pudesse ser cross-game.
- **Inventory Item é a única identidade física — não criar uma entidade física paralela "Collection Item".** Reafirma LDM-23 (identidade única do exemplar físico) e a terminologia já adotada em `logical-model.md` (que já havia descartado "Collection Item" como nome, preservando-o apenas como "papel contextual" de um Inventory Item associado a uma Collection). Relevante porque `ADR-013` (repositório antigo, ver nota de superação) usava "Collection Item" como nome da própria entidade física — este checkpoint reafirma que **Inventory Item**, não Collection Item, é o nome e a identidade física vigente.

---

## 7. Direção de Produto — Collections como primeira superfície client-facing

Registrado nesta mesma rodada, distinto das decisões de modelagem acima (produto/UX, não domínio de dados):

> Collections será a primeira grande superfície client-facing do MMKYU. Não deve herdar mentalidade de página administrativa de Catálogo/Pricing.

Direção declarada:

- visual-first;
- experiência premium;
- motion com propósito;
- manipulação direta;
- quick actions;
- drag & drop;
- bulk operations;
- responsividade e performance como requisitos de primeira classe.

**Contexto**: até aqui, toda superfície implementada do MMKYU (Catálogo Editorial, Pricing/"Valor de Mercado") é `adminOnly` — administrativa, densidade alta, sem exigência de "premium feel". Collections é a primeira tela pensada para o colecionador final, não para o administrador do sistema — a direção acima existe precisamente para que a equipe (e qualquer sessão futura de IA) não replique por inércia os padrões visuais/de interação do Catálogo/Pricing em Collections. Coerente com `pkmnbindr-benchmark.md` (Seções 27/30/32: "a sofisticação deve existir no modelo, a simplicidade deve existir na interface"; "não devemos... reduzir o MMKYU a uma página administrativa").

Esta direção não substitui nem executa nenhum documento de UX ainda — é o princípio orientador para quando a North Star UX de Collections for de fato desenhada (explicitamente **não** nesta rodada — ver Seção 8).

---

## 8. O que este checkpoint explicitamente NÃO faz

Por instrução direta de Fabrício:

- não implementa código;
- não cria migration, tabela, RPC, rota ou componente;
- não inicia UX-01 nem qualquer outra numeração de UX;
- não inventa decisões além das listadas nas Seções 2 e 7;
- não resolve o novo tópico de LDM-28 (Seção 4) — fica como lacuna aberta explícita.

---

## 9. Próxima decisão em aberto (para quando a modelagem lógica for retomada)

Substituindo o antigo LDM-28 (void, Seção 4), os pontos reais que a modelagem lógica de Collection precisará endereçar quando retomada:

1. **Transferência de Inventory Item entre Inventories de usuários diferentes** (ex.: troca, doação, venda) — mencionada como lacuna em `logical-model.md` §7 ("Approval / Messaging") e nesta Seção 3, mas não modelada.
2. **Modelo físico de `Inventory`** — cardinalidade exata (1:1 confirmado nesta rodada), criação automática vs. explícita (ex.: no cadastro do usuário), e se `Inventory` precisa de atributos próprios além do vínculo com `User`.
3. **Modelo de `Favorite`** (Seção 2.1) — cardinalidade, dono, e uso na experiência, ainda não detalhados.
4. Os pontos já listados em `logical-model.md` §7 que continuam abertos e não afetados por este checkpoint: Storage (ownership, sharing, movimentação), matriz de permissões completa de Collection Member, Audit Log transversal.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste checkpoint (2026-08-28) — registra a simplificação do modelo de ownership de Inventory Item (Favorite→Card, Inventory/Acervo 1:1 por usuário, Inventory Item pertence ao Inventory, restrição de alocação por usuário, Members sem Inventory Items próprios), o impacto explícito sobre LDM-25/26/27 e o LDM-28 original (void), a resolução do conflito C-36×LDM-10, duas reafirmações (OPEN_CURATION restrita ao Game; Inventory Item como única identidade física) e a decisão de produto de Collections como primeira superfície client-facing do MMKYU. |
