# Collection — Logical Data Model (LDM)

| Campo | Valor |
|--------|-------|
| **Documento** | Collection — Logical Data Model (Checkpoint Lógico) |
| **Arquivo** | `docs/domain-modeling/collections/logical-model.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` como fonte canônica em 2026-08-28 (pedido explícito de Fabrício). |
| **Decision Register** | LDM-01 a LDM-27 (núcleo Collection, checkpoint em evolução — ver banner de superação parcial abaixo); LDM-29 a LDM-37 (bloco complementar Collection Layout, 2026-08-30) |
| **Status** | Checkpoint lógico em evolução — modelo físico ainda NÃO iniciado |
| **Escopo** | Modelagem lógica da entidade `Collection`, do domínio de posse (`Inventory Item`) e, desde 2026-08-30, de `Collection Layout`/`Page`/`Slot`/`Slot Assignment` — não contém SQL nem modelo físico. |
| **Documentos Relacionados** | `concept-decisions.md` (C-01 a C-46, base conceitual), `pkmnbindr-benchmark.md`, `checkpoint-2026-08-28.md` (**supersede parcialmente este documento — ver banner abaixo**), `checkpoint-2026-08-29.md`, `checkpoint-2026-08-30.md` (canônico para o bloco Layout), `../../04-domain-model.md`, `adr/ADR-013-collection-item-identity-model.md`/`adr/ADR-014-collection-and-collection-entry-model.md` (ambas **Substituídas**). |

---

> ⚠️ **Banner de superação parcial (2026-08-28) — ler antes de aplicar este documento.**
> Em 2026-08-28, Fabrício registrou decisões adicionais que simplificam o modelo de ownership de `Inventory Item` (ver `checkpoint-2026-08-28.md`, fonte canônica vigente para os pontos abaixo). Como consequência, **este documento contém três seções que não devem mais ser implementadas como escritas**:
>
> - **LDM-25 (Inventory Item Ownership)** — SUPERSEDED. `Inventory Item` deixa de ter `owner_user_id` próprio; a posse deriva transitivamente de `Inventory` (ver checkpoint).
> - **LDM-26 (Inventory Item Ownership Transfer)** — SUPERSEDED. Transferência de posse deixa de ser uma operação sobre o item individual; torna-se uma questão de transferência entre `Inventory`s, ainda não modelada.
> - **LDM-27 (Operational Authority and Approval for Patrimonial Actions)** — SUPERSEDED. O cenário que motivava esta seção (Collection compartilhada contendo itens de múltiplos owners) deixa de existir: uma Collection só aloca `Inventory Items` do `Inventory` do seu próprio dono (ver checkpoint). O conceito de aprovação/patrimonial pode voltar a ser necessário para outros cenários futuros (ex.: troca entre usuários), mas não pela razão original aqui registrada.
> - O tópico de continuação original, **"LDM-28 — Removing a Collection Member Who Still Owns Inventory Items Allocated to the Collection"** (Seção 9, abaixo), está **void** — sua premissa (membro possuir itens alocados na Collection) não pode mais ocorrer, já que Members nunca introduzem Inventory Items próprios na Collection. Um novo tópico de LDM-28 precisa ser aberto quando a modelagem lógica for retomada; este documento não o antecipa.
>
> **LDM-01 a LDM-24 permanecem válidas e não afetadas.** O texto original abaixo é preservado integralmente por rastreabilidade (mesma disciplina de "não contradizer silenciosamente" que o próprio documento estabelece na Seção 6) — a autoridade vigente para os pontos superados é `checkpoint-2026-08-28.md`, não esta seção.

---

**Checkpoint (texto original):** LDM-01 through LDM-27 approved
**Next decision (texto original, ver banner acima):** ~~LDM-28 — Removal of a member who still owns Inventory Items allocated to the Collection~~ (void, ver banner)

---

## 1. Purpose

This document consolidates the approved logical modeling decisions for the **Collection** domain of MMKYU Collector.

It is the logical continuation of:

`01 - conceitual/collection/collection-concept-decisions.md` (no repositório de modelagem original; neste repositório, `concept-decisions.md`)

Only the **current canonical decisions** are recorded. Intermediate proposals that were rejected or superseded are intentionally excluded.

### Current modeling status

- Conceptual model: **C-01 through C-37 — CLOSED**; **C-38 through C-46 — APPROVED** (Collection Layout, 2026-08-30, ver `concept-decisions.md`)
- Logical model: **LDM-01 through LDM-27 — APPROVED** (LDM-25/26/27 superseded 2026-08-28, ver banner acima); **LDM-29 through LDM-37 — APPROVED** (Collection Layout, 2026-08-30)
- Physical model: **NOT STARTED**

---

# 2. Core Logical Principles

The model preserves the separation between:

- **Inventory Item:** physical card copy owned by a user.
- **Collection:** collecting objective to which a physical copy may be allocated.
- **Storage Container:** where the physical copy is stored.
- **Wishlist:** what the user wants to acquire.

> Owning, allocating, storing, completing and wishing are distinct concerns.

Every physical Inventory Item is based on exactly one **Card Variant**.

---

# 3. Approved Logical Decisions

## LDM-01 — Collection as Aggregate Root
`Collection` is a single aggregate root. Open curation, Card Set and Pokédex behaviors do not create independent root entities.

**Status:** APPROVED

## LDM-02 — Collection Ownership
Every Collection has exactly one explicit Owner through `owner_user_id`. Ownership is distinct from sharing/membership.

**Status:** APPROVED

## LDM-03 — Collection Member
Shared access is represented separately through `Collection Member`, relating Collection, User, permission profile and effective permissions. UX presets may simplify assignment, but effective permissions remain authoritative. The Owner is not simultaneously a normal Collection Member. Collection + User is unique. The complete permission matrix will be finalized after Collection Item/Inventory, Storage and Layout responsibilities are sufficiently modeled.

**Status:** APPROVED

## LDM-04 — Collection Mode and Reference
Collection has two primary modes:
- `OPEN_CURATION`
- `REFERENCE_BASED`

`STATIC/DYNAMIC` are characteristics of referenced universes, not Collection modes.

Rules:
- `OPEN_CURATION` → no Collection Reference.
- `REFERENCE_BASED` → exactly one Collection Reference.

**Status:** APPROVED

## LDM-05 — Adopted Scope for Dynamic References
Dynamic canonical references must not silently alter an existing Collection's objective when the canonical catalog evolves. The Collection explicitly persists the canonical positions it has adopted rather than relying only on version/count. The adopted scope is the authoritative denominator where applicable.

**Status:** APPROVED

## LDM-06 — Collection Reference and Explicit Subtypes
Reference-based Collections use a common `Collection Reference` with explicit subtypes:
- Collection Card Set Reference
- Collection Pokédex Reference

A loose polymorphic `reference_type + reference_id` structure is rejected. Each subtype uses a strong FK to its canonical entity.

**Status:** APPROVED

## LDM-07 — Reference Consolidation
A reference may be changed while the Collection has never received an Inventory Item. Current item count is insufficient because a Collection may have contained items and later become empty.

Collection persists `reference_locked_at`. On the first effective Inventory Item association, the reference is consolidated and `reference_locked_at` is set. In normal flow it never returns to `NULL`.

**Status:** APPROVED

## LDM-08 — Completion Policy
Mode, reference type and completion policy are independent.

Initial policies:
- `NONE`
- `STANDARD_SET`
- `MASTER_SET`
- `REFERENCE_POSITION`

Typical mapping:
- Open curation → `NONE`
- Card Set → `STANDARD_SET` or `MASTER_SET`
- Pokédex → `REFERENCE_POSITION`

Completion and progress remain derived.

**Status:** APPROVED

## LDM-09 — Lifecycle and Visibility
Independent dimensions:

Lifecycle:
- `ACTIVE`
- `ARCHIVED`

Visibility:
- `PRIVATE`
- `PUBLIC`

An archived Collection may remain public.

**Status:** APPROVED

## LDM-10 — Default Storage Container
Collection may define `default_storage_container_id`. It is an operational/UX default and does not mean every item must reside there. A Storage Container may be default for multiple Collections. Changing the default does not move existing Inventory Items.

**Status:** APPROVED — ⚠️ **redação parcialmente superada em 2026-08-28**: a frase "Collection *may* define" tratava o campo como opcional. `checkpoint-2026-08-28.md` registra que **C-36 prevalece sobre esta redação**: `default_storage_container_id` é **obrigatório**, definido na criação da Collection (a semântica operacional descrita aqui — default de UX, não exclusividade, não move itens existentes — permanece correta e válida).

## LDM-11 — Audit Timestamps and Business Milestones
Technical audit:
- `created_at`
- `updated_at`

Business milestones:
- `started_at`
- `reference_locked_at`
- `archived_at`

`started_at` = first effective Inventory Item association and applies to open/reference-based Collections. `completed_at` is not persisted because completion is reversible.

**Status:** APPROVED

## LDM-12 — Collection Root Logical Skeleton

```text
Collection
├── id
├── game_id
├── owner_user_id
├── name
├── description
├── mode
├── completion_policy
├── lifecycle_status
├── visibility
├── default_storage_container_id
├── started_at
├── reference_locked_at
├── archived_at
├── created_at
├── created_by_user_id
├── updated_at
└── updated_by_user_id
```

`owner_user_id` differs from `created_by_user_id`; ownership transfer does not rewrite original authorship. `created_at/by + updated_at/by` is a candidate transversal standard, not yet automatically generalized.

**Status:** APPROVED

## LDM-13 — Collection Reference

```text
Collection Reference
├── id
├── collection_id
├── reference_kind
├── created_at
├── created_by_user_id
├── updated_at
└── updated_by_user_id
```

`collection_id` is unique. Initial kinds:
- `CARD_SET`
- `POKEDEX`

The concrete canonical identifier lives in the subtype. `reference_kind` is a discriminator, not a generic polymorphic reference. `game_id` is not duplicated.

**Status:** APPROVED

## LDM-14 — Collection Card Set Reference

```text
Collection Card Set Reference
├── collection_reference_id
└── card_set_id
```

`card_set_id` is a strong FK to canonical Card Set. The Card Set must belong to the same Game as Collection. Metadata is not duplicated. Completion policy stays on Collection. After reference consolidation, `card_set_id` is immutable in normal flow.

**Status:** APPROVED

## LDM-15 — Collection Pokédex Reference and Expandable Adopted Scope
A Pokédex Collection references canonical Pokédex via `pokedex_id`. Its effective objective is a separate Adopted Scope.

Initial scope may contain one generation, multiple generations, or the entire desired universe. Every Pokédex Collection is expandable through explicit user action.

Examples:
- Kanto → 151
- Kanto + Johto → 251
- Kanto + Johto + Hoenn → 386

Completion uses the currently adopted scope, never the whole current canonical Pokédex. In normal flow the Pokédex scope is monotonic: positions may be added but not removed.

**Status:** APPROVED

## LDM-16 — Pokédex Adopted Scope by Canonical Position
Scope references canonical `Pokédex Position`, not directly Pokémon.

Canonical dependency:

```text
Pokédex
└── Pokédex Position
    ├── id
    ├── pokemon_id
    └── position_number
```

Collection scope:

```text
Collection Pokédex Scope
├── collection_pokedex_reference_id
├── pokedex_position_id
├── adopted_at
└── adopted_by_user_id
```

Each position may be adopted at most once. Adoption metadata preserves when/by whom it entered the objective. Pokédex and Pokédex Position belong to their canonical domain, not Collection.

**Status:** APPROVED

## LDM-17 — Inventory Item Eligibility
Eligibility validates only the canonical universe; there is no arbitrary user-defined rule engine.

- Open Curation: no canonical-universe restriction.
- Card Set: Inventory Item's Card must belong to referenced Card Set.
- Pokédex: Card's principal Pokémon must correspond to a Pokédex Position in the Adopted Scope.

Language, rarity, variant and aesthetic preferences do not independently restrict eligibility unless a future explicit completion requirement uses them. Eligibility is derived, not stored as `is_eligible`. Eligibility and completion are independent.

**Status:** APPROVED

## LDM-18 — Card to Pokémon Relationship for Pokédex Eligibility
Every Card classified as Pokémon is associated with exactly one canonical Pokémon: the principal Pokémon in evidence. Incidental Pokémon in artwork do not generate eligibility.

```text
Card (category = POKEMON)
└── pokemon_id → exactly one canonical Pokemon
```

Eligibility path:

```text
Inventory Item
→ Card Variant
→ Card
→ pokemon_id
=
Pokédex Position
→ pokemon_id
```

The earlier N:N Card ↔ Pokémon hypothesis is superseded and must not be implemented.

**Status:** APPROVED

## LDM-19 — Inventory Item Always Originates from Card Variant
Every physical Inventory Item references exactly one Card Variant regardless of Collection type.

```text
Inventory Item
→ Card Variant
→ Card
```

Completion projection:
- `STANDARD_SET`: Card Variant → Card
- `MASTER_SET`: Card Variant
- `REFERENCE_POSITION`: Card Variant → Card → Pokemon → Pokédex Position

Requirement satisfaction is derived rather than persisted as a second source of truth.

**Status:** APPROVED

## LDM-20 — Completion Denominator
Requirements depend on `completion_policy`:

- `NONE`: no denominator.
- `STANDARD_SET`: each Card of referenced Card Set is a requirement.
- `MASTER_SET`: Card Variants explicitly selected in the Collection's Master Set Adopted Scope.
- `REFERENCE_POSITION`: each Pokédex Position in Adopted Scope.

Numerator = distinct requirements satisfied by at least one Inventory Item allocated to Collection. Duplicates do not create additional satisfied requirements. Counts/percentages may later be materialized for performance but are not canonical truth.

**Status:** APPROVED

## LDM-21 — Master Set Adopted Scope
A `MASTER_SET` Collection has a user-defined Master Set Adopted Scope.

```text
Collection Master Set Scope
├── collection_id
├── card_variant_id
├── adopted_at
└── adopted_by_user_id
```

The source of truth is explicit individual `card_variant_id` selection. Variant types/presets/bulk tools are UX mechanisms only.

The user may include/exclude special variants such as Jumbo, League, Tournament and others. Scope may expand or shrink. Removing a variant changes completion requirements only; it does not delete Inventory Items or remove them from Collection.

Full historical changes belong to Audit Log.

The canonical Card Variant list of a validated Card Set is stable after its initial validated catalog load in normal operation. Later corrections, if ever required, are exceptional catalog-governance events, not normal Collection evolution.

**Status:** APPROVED

## LDM-22 — Completion Policy Changes and Master Set Scope Redefinition
Card Set Collections may change:
- `STANDARD_SET ↔ MASTER_SET`

Changing policy does not modify/remove Inventory Items.

When switching to Master Set, the user explicitly validates the Master Set Adopted Scope. When switching to Standard Set, prior Master Set Scope may be preserved but is inactive. If returning to Master Set, it may be restored.

While remaining `MASTER_SET`, the user may redefine Scope at any time by including/excluding existing canonical Card Variants.

Distinction:
1. Completion policy change: `STANDARD_SET ↔ MASTER_SET`
2. Completion scope change: policy stays `MASTER_SET`, adopted variants change.

Denominator changes are conscious user changes to the collecting objective, not automatic catalog expansion.

**Status:** APPROVED

## LDM-23 — Single Canonical Identity for the Physical Item
The physical copy has one canonical Inventory identity. Association with Collection does not create a second physical identity.

```text
Inventory Item
├── id
├── owner_user_id
├── card_variant_id
├── collection_id (0..1)
└── storage_container_id (0..1)
```

An Inventory Item associated with Collection plays the contextual role previously described as a `Collection Item`.

It may exist without Collection, enter one, leave it, or move to another while retaining identity. It may belong to at most one Collection at a time. Collection allocation and physical Storage are independent.

**Status:** APPROVED — ⚠️ **skeleton parcialmente superado em 2026-08-28**: o campo `owner_user_id` acima é substituído por `inventory_id` (Inventory Item pertence ao `Inventory`, não diretamente ao User) — ver `checkpoint-2026-08-28.md`. A identidade única do exemplar físico (o ponto central desta decisão) permanece válida e não afetada.

## LDM-24 — Inventory Item and Storage Container
Every Inventory Item must reference exactly one Card Variant. Storage is optional (`0..1`).

An item may temporarily have no defined location, supporting recent acquisitions, bulk imports, temporary reorganization or unknown location.

No Storage does not prevent Collection association or completion contribution. UX should favor contextual/default Storage assignment, especially One-Click and bulk workflows, without making Storage structurally mandatory.

**Status:** APPROVED

## LDM-25 — Inventory Item Ownership
Every Inventory Item has exactly one explicit Owner, independent of Collection ownership.

A shared Collection may contain items owned by different authorized members.

Transferring Collection ownership does not transfer Inventory Items. Item ownership transfer is independent. To associate another user's item, that Owner must have an authorized relationship with Collection.

Storage ownership remains a separate concern.

**Status:** APPROVED — 🔴 **SUPERSEDED em 2026-08-28** (ver banner no topo do documento e `checkpoint-2026-08-28.md`). Texto original preservado por rastreabilidade; não implementar como escrito.

## LDM-26 — Inventory Item Ownership Transfer
Ownership transfer preserves physical identity and does not automatically change:
- Card Variant
- Storage Container
- Collection association

If new Owner is already authorized in current Collection, the item may remain. If not, transfer must not silently create an invalid state or silently remove the item; incompatibility must be explicitly resolved before completion.

Physical ownership transfer and Collection reallocation are distinct.

**Status:** APPROVED — 🔴 **SUPERSEDED em 2026-08-28** (ver banner no topo do documento e `checkpoint-2026-08-28.md`). Texto original preservado por rastreabilidade; não implementar como escrito.

## LDM-27 — Operational Authority and Approval for Patrimonial Actions
Authority over an Inventory Item in a shared Collection has two dimensions.

### Collection operations
Collection permissions govern the item's role/organization inside Collection. Removing an item from Collection does not delete Inventory Item.

### Patrimonial/physical operations
Inventory Item Owner retains final authority over operations affecting ownership or existence of the physical asset.

Collection Owner may initiate a patrimonial operation over another member's item, but it is not executed immediately:

1. approval request is created;
2. Inventory Item Owner receives it in their inbox;
3. Owner approves or rejects;
4. no patrimonial state changes while pending;
5. approval executes the authorized operation;
6. rejection cancels it.

No self-approval is required when Collection Owner = Inventory Item Owner.

Examples include ownership transfer, deletion, and future operations materially affecting ownership/existence.

Future transversal dependency:
**Pending Action / Approval Request + User Inbox / Notification Center**

This should be platform-level, not Collection-specific.

**Status:** APPROVED — 🔴 **SUPERSEDED em 2026-08-28** (ver banner no topo do documento e `checkpoint-2026-08-28.md`). Texto original preservado por rastreabilidade; não implementar como escrito.

---

## Bloco complementar — Collection Layout (LDM-29 a LDM-37, 2026-08-30)

Reabre o ponto de retomada deixado explicitamente em aberto pelo banner do topo deste documento e por `checkpoint-2026-08-28.md` §4 ("um novo tópico de LDM-28 precisa ser aberto quando a modelagem lógica for retomada"). O LDM-28 original (Seção 9, abaixo) permanece void — para evitar colisão de numeração com esse tópico void, o bloco abaixo abre em LDM-29 (não reocupa LDM-28, nem em conteúdo nem em número). Base conceitual: C-38 a C-46 em `concept-decisions.md`. Nenhum campo de timestamp/audit/UUID é fixado aqui — fora de escopo desta rodada de modelagem (ver `checkpoint-2026-08-30.md`).

## LDM-29 — Collection Layout Skeleton

```text
Collection Layout
├── id
└── collection_id
```

Collection Layout pertence a exatamente uma Collection (C-38). Uma Collection pode ter zero Layouts. O modelo permite, futuramente, mais de um Layout por Collection; mecanismo de distinção entre eles (ex. "principal" vs. alternativos) não modelado nesta rodada.

**Status:** APPROVED

## LDM-30 — Page Skeleton

```text
Page
├── id
├── layout_id
└── order
```

Page pertence a exatamente um Layout (C-39). `order` é mutável e independente da identidade da Page — reordenar não recria a Page nem afeta identidade, row ou column dos seus Slots. O mecanismo físico exato de `order` (índice sequencial, linked list, rank/order key) é decisão de modelagem física, não fixada nesta rodada — a única decisão lógica é que Page identity ≠ Page order.

**Status:** APPROVED

## LDM-31 — Grid Configuration and Page Capacity

```text
Collection Layout
├── grid_columns
└── grid_rows

capacity_per_page = grid_columns × grid_rows   (derivado, não persistido como valor independente)
```

Grid Configuration pertence ao Layout (C-40), não à Page — todas as Pages de um Layout herdam a mesma capacidade. Criar uma Page cria, no mesmo ato lógico, todos os `capacity_per_page` Slots estruturais correspondentes (ver LDM-32). Não existe Page estruturalmente parcial.

**Status:** APPROVED

## LDM-32 — Slot Skeleton, Position and Identity

```text
Slot
├── id
├── page_id
├── row       (1..grid_rows)
└── column    (1..grid_columns)
```

`(page_id, row, column)` é único. Slot identity (`id`) é estável e independente de `row`/`column` — posição é atributo, não identidade (C-41). Slot sobrevive a Move, Swap e Replace sem ser recriado; nasce/morre apenas junto com mudanças estruturais da Page (criação da Page, Grid Change futuro).

**Status:** APPROVED

## LDM-33 — Expected Content Skeleton

```text
Slot Expected Content
├── id
├── slot_id          (0..1 por Slot — relação opcional)
├── card_id          (obrigatório)
└── card_variant_id  (opcional — ausente = qualquer Variant da Card satisfaz)
```

Compatibilidade com a Slot Assignment corrente do mesmo Slot (LDM-35) é sempre derivada por comparação (`card_id`/`card_variant_id` do Expected Content vs. `card_variant_id` do Inventory Item posicionado via sua Card Variant), nunca persistida como segunda fonte de verdade. Mismatch não invalida a Slot Assignment (C-42). Expected Content nunca entra no denominador/numerador de completude (LDM-20 permanece a única fonte).

**Status:** APPROVED

## LDM-34 — Lock as Slot Attribute

```text
Slot
└── locked   (atributo do próprio Slot — ver LDM-32)
```

Não existe atributo de Lock em Slot Assignment nem em Layout Region. Bloqueio de operações (Move/Swap/Replace/Remove/Drop/Bandeja/Merge/Unmerge) sobre um Slot locked segue C-43.

**Status:** APPROVED

## LDM-35 — Slot Assignment: Relation, Cardinality and Lifecycle

```text
Slot Assignment
├── inventory_item_id
└── slot_id
```

Pré-condição: `inventory_item_id.collection_id` deve ser igual ao `collection_id` do Layout ao qual `slot_id` pertence (via `slot_id → page_id → layout_id → collection_id`) — Slot Assignment exige alocação prévia à mesma Collection (C-44).

Cardinalidade: no máximo uma Slot Assignment ativa por par (`inventory_item_id`, `layout_id`) — não uma restrição global por item; no máximo um `inventory_item_id` ativo por `slot_id`.

Ciclo de vida conceitual (sem histórico/audit/timestamps — fora de escopo desta rodada):
- **ADD** — nova Slot Assignment nasce.
- **MOVE** — a mesma relação muda de `slot_id` (não é encerrada e recriada).
- **SWAP** — duas relações existentes trocam mutuamente seu `slot_id`.
- **REPLACE** — a Slot Assignment do item atual termina; nova Slot Assignment nasce para o item substituto, no mesmo `slot_id`.
- **REMOVE / mover para Bandeja** — a Slot Assignment termina; nenhuma nova nasce.

Slot Assignment não requer identidade de negócio/lifecycle própria além da relação de estado atual — ADD/MOVE/SWAP/REPLACE/REMOVE descrevem mudanças do estado atual de posicionamento, não eventos de uma entidade com identidade rastreável ao longo do tempo. Um identificador técnico de implementação, se existir, não constitui identidade de domínio. Histórico, audit trail, versionamento ou Undo/Redo persistente, se necessários no futuro, serão modelados separadamente, não como consequência automática desta relação.

**Status:** APPROVED

## LDM-36 — Bandeja: Explicitamente Não Modelada

Bandeja não recebe skeleton físico nesta rodada — por C-45, é estado de UX/sessão, não estado de domínio persistente. Nenhuma tabela, campo ou relação é criada para representá-la. Se uma Slot Assignment "vai para a Bandeja" e a sessão termina sem reposicionamento, nenhuma mudança de estado persistido ocorreu — a Slot Assignment de origem nunca foi alterada; a UI simplesmente não a exibiu como ocupando o Slot durante a sessão de edição.

Este comportamento está fechado conceitualmente, não é uma pendência aberta. Se um produto futuro exigir algum mecanismo de staging que sobreviva ao fechar/reabrir o Layout, isso seria um requisito/conceito de produto novo e distinto — não uma extensão ou pendência da Bandeja tal como definida aqui.

**Status:** APPROVED (decisão explícita de não modelar)

## LDM-37 — Layout Region Skeleton

```text
Layout Region
├── id
├── page_id
└── (referência aos Slots agrupados — mecanismo físico exato, ex. tabela de junção vs. bounding box, não decidido nesta rodada)
```

Layout Region pertence a exatamente uma Page (C-46 — todos os Slots referenciados compartilham o mesmo `page_id`). Geometria: mínimo 2 Slots, contíguos, formando retângulo completo; sem sobreposição entre Regions (um Slot participa de no máximo uma Region ativa). Criar/remover uma Region não altera Slot Assignment nem Expected Content dos Slots envolvidos, e é bloqueada se qualquer Slot envolvido estiver `locked` (LDM-34).

**Status:** APPROVED

---

# 4. Canonical Relationship Summary

```text
Collection
├── Owner
├── Members
├── Default Storage Container
└── Collection Reference (0..1)
    ├── Card Set Reference
    │   └── Card Set
    └── Pokédex Reference
        ├── Pokédex
        └── Adopted Scope
            └── Pokédex Positions

Inventory Item
├── Owner
├── Card Variant
│   └── Card
│       ├── Card Set
│       └── Pokemon (when category = POKEMON)
├── Collection (0..1)
└── Storage Container (0..1)

MASTER_SET Collection
└── Master Set Adopted Scope
    └── selected Card Variants

Collection
└── Collection Layout (0..N)
    └── Page (0..N)
        ├── Slot (N — derivado de Grid Configuration)
        │   ├── Slot Expected Content (0..1)
        │   ├── locked (atributo)
        │   └── Slot Assignment (0..1, via Inventory Item)
        └── Layout Region (0..N — agrupa Slots contíguos da mesma Page)

Inventory Item
└── Slot Assignment (0..1 por Layout — ver LDM-35)
```

> Nota (2026-08-28): o bloco `Inventory Item → Owner` acima reflete o texto original; ver `checkpoint-2026-08-28.md` para o resumo de relacionamento vigente (`Inventory Item → Inventory → User`).
>
> Nota (2026-08-30): o bloco `Collection Layout` acima resume LDM-29 a LDM-37. `Storage Container` permanece inteiramente ortogonal a esta árvore — não aparece nela porque Layout é digital, nunca localização física (C-38/C-44).

---

# 5. Completion Model Summary

```text
NONE
→ no completion calculation

STANDARD_SET
→ denominator = Cards of referenced Card Set
→ Inventory Item → Card Variant → Card

MASTER_SET
→ denominator = Card Variants selected in Master Set Adopted Scope
→ Inventory Item → Card Variant

REFERENCE_POSITION / POKEDEX
→ denominator = Pokédex Positions in Adopted Scope
→ Inventory Item → Card Variant → Card → Pokemon → Pokédex Position
```

Completion is derived. Inventory quantity is not equivalent to completion progress.

---

# 6. Superseded / Rejected Logical Hypotheses

Do **not** implement:

1. Generic polymorphic `reference_type + reference_id`.
2. `STATIC/DYNAMIC` as Collection modes.
3. Reference lock derived only from current item count.
4. Persisted `is_eligible` as canonical truth.
5. Arbitrary user-defined eligibility rule engine.
6. Card ↔ Pokémon N:N for Pokédex eligibility.
7. Incidental artwork Pokémon satisfying Pokédex positions.
8. A second physical identity solely because an Inventory Item joins a Collection.
9. Every canonical Card Variant being automatically mandatory in every Master Set.
10. Automatic Master Set denominator changes caused by normal catalog expansion.
11. Structurally mandatory Storage for Inventory Item creation.
12. Automatic Inventory Item transfer when Collection ownership changes.
13. Unconditional patrimonial authority for Collection Owner over items owned by other members.
14. `Placement` como nome canônico de entidade/relação para o posicionamento de um Inventory Item num Slot — terminologia superada por `Slot Assignment` (LDM-35, C-44). O termo apareceu apenas em `ux-exploration-2026-08-29.md` e `checkpoint-2026-08-29.md` (produzidos durante a exploração do spike visual do Binder), nunca havia sido ratificado em C-*/LDM-* anteriores; a reimersão documental (`COLLECTIONS-DOMAIN-REENTRY-01`) confirmou a ausência de lastro canônico antes de a frente `COLLECTIONS-LAYOUT-MODELING` decidir o nome definitivo a adotar.
15. Um Slot exigir ocupação (Slot Assignment) para existir, ou uma Slot Assignment exigir Expected Content prévio — ambas as relações são independentes entre si e da ocupação (C-41/C-42/C-44).
16. Cardinalidade global de 1 Slot Assignment por Inventory Item (independente de Layout) — rejeitada em favor de 1 por par (Inventory Item, Layout), necessária para suportar múltiplos Layouts da mesma Collection (LDM-35).
17. Slot Assignment criar implicitamente Collection Allocation (ou vice-versa) — as duas relações permanecem independentes; Slot Assignment apenas *exige* Collection Allocation prévia, nunca a cria (LDM-35).

> Adendo (2026-08-28): também não implementar `owner_user_id` direto em Inventory Item, nem qualquer fluxo de aprovação patrimonial fundamentado em "Collection compartilhada com itens de múltiplos owners" — ver `checkpoint-2026-08-28.md`.
>
> Adendo (2026-08-30): ver `checkpoint-2026-08-30.md` para o diagnóstico completo de reconciliação da frente Collection Layout, incluindo a supersessão terminológica do item 14 acima.

---

# 7. Dependencies Identified for Other Domains

## Canonical Catalog
- Card
- Card Variant
- Card Set
- Pokemon
- Pokédex
- Pokédex Position

Invariant: every Card classified as Pokémon identifies exactly one principal canonical Pokemon.

## Inventory
Inventory Item requires its own detailed model beyond the Collection-allocation decisions captured here. **Atualização 2026-08-28**: o próprio conceito de `Inventory` (Acervo) como aggregate 1:1 por usuário, dono real de todo `Inventory Item`, foi introduzido nesta data — ver `checkpoint-2026-08-28.md`.

## Storage
Storage ownership, sharing, physical organization and movement require their own model.

## Permissions
Complete permission matrix will be finalized after Collection, Inventory, Storage and Layout responsibilities are sufficiently defined.

## Audit
A transversal Audit Log should preserve meaningful changes without forcing every business relation into a temporal table.

## Approval / Messaging
A transversal Pending Action / Approval Request mechanism and User Inbox / Notification Center are required for multi-user operations requiring explicit approval. **Atualização 2026-08-28**: a motivação original (LDM-27) não se aplica mais; este mecanismo permanece como backlog transversal para outros cenários futuros (ex.: troca entre usuários), não para o cenário original.

## Layout (Atualização 2026-08-30)
Collection Layout/Page/Slot/Expected Content/Lock/Slot Assignment/Layout Region agora possuem checkpoint lógico (LDM-29 a LDM-37). Permanecem como dependências não resolvidas por este bloco: mecanismo físico de ordenação de Page (LDM-30); mecanismo de Grid Change em Layout existente (C-40); representação física de Layout Region (bounding box vs. tabela de junção, LDM-37); modelagem de artwork/conteúdo visual de Region; Undo/Redo e histórico de Slot Assignment (explicitamente adiados por D53/LDM-35).

---

# 8. Current Architectural Checkpoint

## Conceptual
**C-01 through C-37 — CLOSED**

Canonical document:
`concept-decisions.md`

## Logical
**LDM-01 through LDM-37 — APPROVED, LDM-25/26/27 SUPERSEDED (2026-08-28)**

This document is the canonical logical checkpoint for LDM-01 through LDM-24 (Collection core) and LDM-29 through LDM-37 (Collection Layout, 2026-08-30). `checkpoint-2026-08-28.md` is canonical for the ownership-model simplification. `checkpoint-2026-08-30.md` is canonical for the Layout reconciliation diagnostic and for the current open point.

## Physical
**NOT STARTED**

---

# 9. Exact Point of Resumption (texto original — void, ver banner no topo)

Next decision (texto original, preservado por rastreabilidade):

## LDM-28 — Removing a Collection Member Who Still Owns Inventory Items Allocated to the Collection

It must define what happens when a user is to be removed from Collection membership while one or more Inventory Items owned by that user remain allocated to Collection.

It must preserve:
- independent Inventory Item ownership;
- authorized Collection membership;
- no silent transfer of physical ownership;
- no silent invalid states;
- explicit approval for patrimonial operations when applicable.

> Resume from LDM-28 using LDM-01 through LDM-27 in this document as the approved logical baseline.

> **Esta seção está void desde 2026-08-28** — a premissa (member owns items allocated to the Collection) não pode mais ocorrer. Ver `checkpoint-2026-08-28.md`, seção "Próxima decisão em aberto", para o estado real de retomada.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Documento produzido no repositório de modelagem paralelo `mimikyu-modelagem-de-dados` — checkpoint LDM-01 a LDM-27 aprovado, LDM-28 como próxima decisão. |
| 1.1 | Incorporado a `project-mimikyu` (2026-08-28, pedido explícito de Fabrício) em `docs/domain-modeling/collections/`. Adicionado banner de superação parcial (LDM-25/26/27 superseded, LDM-28 original void) refletindo decisões novas de simplificação do modelo de ownership registradas na mesma data em `checkpoint-2026-08-28.md`. Nenhum texto original removido ou reescrito — apenas anotado. |
| 1.2 | **Bloco complementar Collection Layout, 2026-08-30.** Adicionadas LDM-29 a LDM-37 (Collection Layout, Page, Grid Configuration, Slot, Expected Content, Lock, Slot Assignment, Bandeja explicitamente não modelada, Layout Region), evitando colisão de numeração com o LDM-28 original (void, Seção 9) — que permanece void e não é reocupado, nem em conteúdo nem em número. Seção 4 (Canonical Relationship Summary) e Seção 6 (Superseded/Rejected, itens 14–17) atualizadas; item 14 registra a supersessão terminológica de `Placement` por `Slot Assignment`. Ver `checkpoint-2026-08-30.md` para o diagnóstico de reconciliação completo. |
