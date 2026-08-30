# Collection — Logical Data Model (LDM)

| Campo | Valor |
|--------|-------|
| **Documento** | Collection — Logical Data Model (Checkpoint Lógico) |
| **Arquivo** | `docs/domain-modeling/collections/logical-model.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` como fonte canônica em 2026-08-28 (pedido explícito de Fabrício). |
| **Decision Register** | LDM-01 a LDM-27 (núcleo Collection, checkpoint em evolução — ver banner de superação parcial abaixo); LDM-29 a LDM-37 (bloco complementar Collection Layout, 2026-08-30); LDM-23 revisada em 2026-08-30 (identidade e cardinalidade corrente de `Physical Card`, ver banner); LDM-38 a LDM-43 (bloco complementar Custody & Availability, 2026-08-30, sem skeleton físico); LDM-44 a LDM-54 (bloco complementar Storage, 2026-08-30, sem skeleton físico) |
| **Status** | Checkpoint lógico em evolução — modelo físico ainda NÃO iniciado |
| **Escopo** | Modelagem lógica da entidade `Collection`, do domínio de posse (`Physical Card` — nome canônico desde 2026-08-30, ver `concept-decisions.md` C-47/C-48), desde 2026-08-30 de `Collection Layout`/`Page`/`Slot`/`Slot Assignment`, desde 2026-08-30 das dimensões lógicas `Custody`/`Custodian`/`Availability` (sem skeleton físico — ver LDM-38 a LDM-43), e desde 2026-08-30 de `Storage`/`Storage Container` incluindo hierarquia opcional (sem skeleton físico — ver LDM-44 a LDM-54) — não contém SQL nem modelo físico. |
| **Documentos Relacionados** | `concept-decisions.md` (C-01 a C-48, base conceitual), `pkmnbindr-benchmark.md`, `checkpoint-2026-08-28.md` (**supersede parcialmente este documento — ver banner abaixo**), `checkpoint-2026-08-29.md`, `checkpoint-2026-08-30.md` (canônico para o bloco Layout), `../../04-domain-model.md`, `adr/ADR-013-collection-item-identity-model.md`/`adr/ADR-014-collection-and-collection-entry-model.md` (ambas **Substituídas**). |

---

> ⚠️ **Banner de superação parcial (2026-08-28) — ler antes de aplicar este documento.**
> Em 2026-08-28, Fabrício registrou decisões adicionais que simplificam o modelo de ownership de `Physical Card` (nome vigente desde 2026-08-30; o registro original de 2026-08-28 usava `Inventory Item` — ver nota de convergência terminológica abaixo) (ver `checkpoint-2026-08-28.md`, fonte canônica vigente para os pontos abaixo). Como consequência, **este documento contém três seções que não devem mais ser implementadas como escritas**:
>
> - **LDM-25 (Inventory Item Ownership)** — SUPERSEDED. `Physical Card` deixa de ter `owner_user_id` próprio; a posse deriva transitivamente de `Inventory` (ver checkpoint e, desde 2026-08-30, LDM-23 revisada abaixo).
> - **LDM-26 (Inventory Item Ownership Transfer)** — SUPERSEDED. Transferência de posse deixa de ser uma operação sobre o item individual; torna-se uma questão de transferência entre `Inventory`s, ainda não modelada em detalhe (ver LDM-23 revisada para a regra de cardinalidade que a governa).
> - **LDM-27 (Operational Authority and Approval for Patrimonial Actions)** — SUPERSEDED. O cenário que motivava esta seção (Collection compartilhada contendo itens de múltiplos owners) deixa de existir: uma Collection só aloca `Physical Cards` do `Inventory` do seu próprio dono (ver checkpoint). O conceito de aprovação/patrimonial pode voltar a ser necessário para outros cenários futuros (ex.: troca entre usuários), mas não pela razão original aqui registrada.
> - O tópico de continuação original, **"LDM-28 — Removing a Collection Member Who Still Owns Inventory Items Allocated to the Collection"** (Seção 9, abaixo, título preservado tal como escrito originalmente), está **void** — sua premissa (membro possuir itens alocados na Collection) não pode mais ocorrer, já que Members nunca introduzem `Physical Cards` próprias na Collection. Um novo tópico de LDM-28 precisa ser aberto quando a modelagem lógica for retomada; este documento não o antecipa.
>
> **LDM-01 a LDM-22 e LDM-24 permanecem válidas e não afetadas.** O texto original das seções superseded acima é preservado integralmente por rastreabilidade (mesma disciplina de "não contradizer silenciosamente" que o próprio documento estabelece na Seção 6) — a autoridade vigente para os pontos superados é `checkpoint-2026-08-28.md`, não esta seção.
>
> **Nota de convergência terminológica (2026-08-30).** Por decisão de Fabrício em `concept-decisions.md` (C-47/C-48), o termo canônico do exemplar físico passa a ser **`Physical Card`**, substituindo tanto `Collection Item` (nome original deste documento) quanto `Inventory Item` (nome introduzido pela reconciliação de 2026-08-28). Este documento foi revisado de ponta a ponta para usar `Physical Card` em todo texto normativo vigente (Seções 2 a 8, LDM-01 a LDM-24 e LDM-29 a LDM-37) — apenas o nome mudou; nenhuma decisão de conteúdo (cardinalidade, campos, comportamento) foi alterada por este motivo isoladamente. **LDM-23** foi, adicionalmente, revisada em conteúdo nesta mesma data: deixa de apenas apontar para o checkpoint e passa a formalizar diretamente, no nível lógico, a regra de cardinalidade corrente entre `Physical Card` e `Inventory` (contraparte lógica de C-48) — ver LDM-23 abaixo. O texto original de LDM-25, LDM-26, LDM-27 e da Seção 9 (marcados SUPERSEDED/void) foi deliberadamente **preservado com a terminologia antiga**, por ser texto histórico citado verbatim — não foi convergido.

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
- Logical model: **LDM-01 through LDM-27 — APPROVED** (LDM-25/26/27 superseded 2026-08-28, ver banner acima; LDM-23 revisada 2026-08-30 — `Physical Card` & cardinalidade corrente com `Inventory`); **LDM-29 through LDM-37 — APPROVED** (Collection Layout, 2026-08-30); **LDM-38 through LDM-43 — APPROVED** (Custody & Availability, 2026-08-30, sem skeleton físico); **LDM-44 through LDM-54 — APPROVED** (Storage, 2026-08-30, sem skeleton físico)
- Physical model: **NOT STARTED**

---

# 2. Core Logical Principles

The model preserves the separation between:

- **Physical Card:** permanent identity of one physical copy of a Card Variant (canonical name since 2026-08-30; superseded names: `Collection Item`, `Inventory Item` — see `concept-decisions.md`, C-47).
- **Collection:** collecting objective to which a Physical Card may be allocated.
- **Storage Container:** where the physical copy is stored.
- **Wishlist:** what the user wants to acquire.

> Owning, allocating, storing, completing and wishing are distinct concerns.

Every Physical Card is based on exactly one **Card Variant**. Current ownership of a Physical Card is aggregated by exactly one **Inventory** at a time (see LDM-23).

---

# 3. Approved Logical Decisions

## LDM-01 — Collection as Aggregate Root
`Collection` is a single aggregate root. Open curation, Card Set and Pokédex behaviors do not create independent root entities.

**Status:** APPROVED

## LDM-02 — Collection Ownership
Every Collection has exactly one explicit Owner through `owner_user_id`. Ownership is distinct from sharing/membership.

**Status:** APPROVED

## LDM-03 — Collection Member
Shared access is represented separately through `Collection Member`, relating Collection, User, permission profile and effective permissions. UX presets may simplify assignment, but effective permissions remain authoritative. The Owner is not simultaneously a normal Collection Member. Collection + User is unique. The complete permission matrix will be finalized after Physical Card/Inventory, Storage and Layout responsibilities are sufficiently modeled.

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
A reference may be changed while the Collection has never received a Physical Card. Current item count is insufficient because a Collection may have contained items and later become empty.

Collection persists `reference_locked_at`. On the first effective Physical Card allocation, the reference is consolidated and `reference_locked_at` is set. In normal flow it never returns to `NULL`.

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
Collection may define `default_storage_container_id`. It is an operational/UX default and does not mean every item must reside there. A Storage Container may be default for multiple Collections. Changing the default does not move existing Physical Cards.

**Status:** APPROVED — ⚠️ **redação parcialmente superada em 2026-08-28**: a frase "Collection *may* define" tratava o campo como opcional. `checkpoint-2026-08-28.md` registra que **C-36 prevalece sobre esta redação**: `default_storage_container_id` é **obrigatório**, definido na criação da Collection (a semântica operacional descrita aqui — default de UX, não exclusividade, não move itens existentes — permanece correta e válida).

## LDM-11 — Audit Timestamps and Business Milestones
Technical audit:
- `created_at`
- `updated_at`

Business milestones:
- `started_at`
- `reference_locked_at`
- `archived_at`

`started_at` = first effective Physical Card allocation and applies to open/reference-based Collections. `completed_at` is not persisted because completion is reversible.

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

## LDM-17 — Physical Card Eligibility
Eligibility validates only the canonical universe; there is no arbitrary user-defined rule engine.

- Open Curation: no canonical-universe restriction.
- Card Set: Physical Card's Card must belong to referenced Card Set.
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
Physical Card
→ Card Variant
→ Card
→ pokemon_id
=
Pokédex Position
→ pokemon_id
```

The earlier N:N Card ↔ Pokémon hypothesis is superseded and must not be implemented.

**Status:** APPROVED

## LDM-19 — Physical Card Always Originates from Card Variant
Every Physical Card references exactly one Card Variant regardless of Collection type.

```text
Physical Card
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

Numerator = distinct requirements satisfied by at least one Physical Card allocated to Collection. Duplicates do not create additional satisfied requirements. Counts/percentages may later be materialized for performance but are not canonical truth.

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

The user may include/exclude special variants such as Jumbo, League, Tournament and others. Scope may expand or shrink. Removing a variant changes completion requirements only; it does not delete Physical Cards or remove them from Collection.

Full historical changes belong to Audit Log.

The canonical Card Variant list of a validated Card Set is stable after its initial validated catalog load in normal operation. Later corrections, if ever required, are exceptional catalog-governance events, not normal Collection evolution.

**Status:** APPROVED

## LDM-22 — Completion Policy Changes and Master Set Scope Redefinition
Card Set Collections may change:
- `STANDARD_SET ↔ MASTER_SET`

Changing policy does not modify/remove Physical Cards.

When switching to Master Set, the user explicitly validates the Master Set Adopted Scope. When switching to Standard Set, prior Master Set Scope may be preserved but is inactive. If returning to Master Set, it may be restored.

While remaining `MASTER_SET`, the user may redefine Scope at any time by including/excluding existing canonical Card Variants.

Distinction:
1. Completion policy change: `STANDARD_SET ↔ MASTER_SET`
2. Completion scope change: policy stays `MASTER_SET`, adopted variants change.

Denominator changes are conscious user changes to the collecting objective, not automatic catalog expansion.

**Status:** APPROVED

## LDM-23 — Physical Card: Canonical Identity and Current Inventory Membership
The physical copy has one canonical identity: **Physical Card** (canonical name since 2026-08-30; superseded names, in order of adoption: `Collection Item`, then `Inventory Item` — see `concept-decisions.md`, C-47/C-48). Association with a Collection does not create a second physical identity, and neither does current membership in an Inventory.

```text
Physical Card
├── id
├── card_variant_id
├── inventory_id          (0..1 — see cardinality rule below)
├── collection_id         (0..1)
└── storage_container_id  (0..1)
```

A Physical Card associated with a Collection plays the contextual role previously described as a `Collection Item`.

**Cardinality with Inventory (current ownership).** A Physical Card under MMKYU-tracked current ownership participates in exactly one Inventory at a time — `inventory_id` is functionally 1:1 while tracked, and a Physical Card cannot participate in more than one current Inventory simultaneously. `inventory_id` may be null: a Physical Card can exist without a current Inventory when its ownership exits MMKYU's tracked scope (e.g. an external sale). This does not delete the Physical Card or its history — only current patrimonial ownership becomes untracked. Transferring a Physical Card between two MMKYU Users' Inventories preserves the same Physical Card identity: it is a change of `inventory_id`, not the creation of a new Physical Card. This is the logical-layer formalization of C-48.

It may exist without Collection, enter one, leave it, or move to another while retaining identity. It may belong to at most one Collection at a time. Collection allocation and physical Storage are independent of each other and of current Inventory membership.

**Status:** APPROVED (revisado 2026-08-30)

> **Nota de proveniência (2026-08-30).** Este texto substitui diretamente a versão original de LDM-23 (que usava `owner_user_id` direto e não formalizava, no nível lógico, a regra de cardinalidade corrente com `Inventory`) e o banner de superação parcial de 2026-08-28 que a acompanhava (o skeleton `owner_user_id → inventory_id` mencionado ali). Não se trata de uma nova decisão isolada: é a primeira formalização, no nível lógico, da regra que `checkpoint-2026-08-28.md` §2.3–2.4 e os memos de modelagem de Inventory (nunca promovidos a LDM) descreviam apenas informalmente. Contraparte conceitual: C-47/C-48 em `concept-decisions.md`. O texto original desta seção permanece preservado no histórico de versões do repositório (git) e é referenciado, tal como escrito, na Revision History deste documento (linha 1.1).

## LDM-24 — Physical Card and Storage Container
Every Physical Card must reference exactly one Card Variant. Storage is optional (`0..1`).

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

Compatibilidade com a Slot Assignment corrente do mesmo Slot (LDM-35) é sempre derivada por comparação (`card_id`/`card_variant_id` do Expected Content vs. `card_variant_id` da Physical Card posicionada via sua Card Variant), nunca persistida como segunda fonte de verdade. Mismatch não invalida a Slot Assignment (C-42). Expected Content nunca entra no denominador/numerador de completude (LDM-20 permanece a única fonte).

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
├── physical_card_id   (nome de campo atualizado 2026-08-30; anteriormente inventory_item_id)
└── slot_id
```

Pré-condição: `physical_card_id.collection_id` deve ser igual ao `collection_id` do Layout ao qual `slot_id` pertence (via `slot_id → page_id → layout_id → collection_id`) — Slot Assignment exige alocação prévia à mesma Collection (C-44).

Cardinalidade: no máximo uma Slot Assignment ativa por par (`physical_card_id`, `layout_id`) — não uma restrição global por item; no máximo um `physical_card_id` ativo por `slot_id`.

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

## Bloco complementar — Custody & Availability (LDM-38 a LDM-43, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-49 a C-54 (`concept-decisions.md`), produzido por `COLLECTIONS-CUSTODY-AVAILABILITY-CONSOLIDATION-01`. Nenhum skeleton físico (campo, enum, tabela, UUID) é fixado neste bloco — por decisão explícita de escopo desta rodada, a estrutura física de Custody, a entidade `Custodian` e o detalhamento de Storage permanecem para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-37 não são reabertas.

## LDM-38 — Custody as Logical Dimension, Independent of Storage

Custody answers who currently holds physical control over a Physical Card — logically independent of Inventory (current ownership, LDM-23) and of Storage Container (LDM-24). No field is added to the Physical Card skeleton for Custody in this round; no structural relationship is fixed. Logical-layer formalization of C-49.

**Status:** APPROVED (decisão lógica, sem skeleton físico — ver nota de escopo acima)

## LDM-39 — Custodian: Conceptual Distinction, No Entity

Custodian (the agent holding Custody, when known) remains conceptually distinct from Custody itself, but no `Custodian` entity, table or enum is created at this logical layer. Logical-layer formalization of C-50.

**Status:** APPROVED (decisão lógica, sem entidade física)

## LDM-40 — Custody Operational Default

In the absence of an explicit Custody record, the logical model may assume Custody = owner for a Physical Card under current ownership — an operational default, not a materially proven fact, and not a mandatory field. Logical-layer formalization of C-51.

**Status:** APPROVED

## LDM-41 — LOST and Recovery: No Ownership Change

LOST does not change `inventory_id` (LDM-23) — current ownership is preserved; only reliable knowledge of Custody/location becomes unknown. Recovery does not create a new Physical Card — same `id`, same `card_variant_id`, restored knowledge of Custody/location. No new field, status column or lifecycle event table is fixed for LOST/Recovery at this logical layer — deferred to future Storage/Custody physical modeling. Logical-layer formalization of C-52.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-42 — Availability: Conceptually Scoped, Ownership-Dependent

Availability is only meaningful for a Physical Card with a current `inventory_id` (LDM-23) — without current Inventory, Availability is not applicable, not simply "not available". No enum or field is fixed at this logical layer. Logical-layer formalization of C-53.

**Status:** APPROVED (decisão lógica, sem enum físico)

## LDM-43 — Custody/Availability Do Not Affect Collection Allocation, Slot Assignment or Completion

Neither Custody nor Availability changes are inputs to Collection allocation (LDM-01 family), Slot Assignment (LDM-35) or the Completion Model (Section 5) — completion remains exclusively a function of current ownership (`inventory_id`) and Collection allocation, per LDM-20/LDM-23. Logical-layer formalization of C-54.

**Status:** APPROVED

---

## Bloco complementar — Storage (LDM-44 a LDM-54, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-55 a C-66 (`concept-decisions.md`), produzido por `COLLECTIONS-STORAGE-CONSOLIDATION-01`. Nenhum skeleton físico novo (campo, enum, tabela, fórmula de capacidade) é fixado além do que LDM-24 já estabelece (`storage_container_id`, 0..1) — por decisão explícita de escopo desta rodada, a estrutura física de Storage Container (inclusive seu próprio identificador, referência de Inventory e referência de parent) permanece para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-43 não são reabertas.

## LDM-44 — Storage as Logical Dimension, Distinct from Protection

Storage answers where a Physical Card is physically stored, within the organized structure of the acervo — logically distinct from Custody (LDM-38), Collection Layout (LDM-29–LDM-37) and Collection allocation. A Storage Container is only recognized as such when the user treats it as an addressable location — not any physical object capable of holding a card. No skeleton is added for a Protection/Encapsulation concept at this logical layer. Logical-layer formalization of C-55/C-56.

**Status:** APPROVED (decisão lógica, sem skeleton físico de Protection)

## LDM-45 — Storage Container Ownership Mediated by Inventory

A Storage Container belongs to exactly one Inventory — no direct `owner_user_id` field is introduced for Storage Container at this logical layer, mirroring the lesson already formalized for Physical Card (LDM-23 revised, superseding the direct-ownership design of LDM-25). Logical-layer formalization of C-57.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-46 — Physical Card and Storage: Cardinality Reaffirmed

Extends LDM-24: `storage_container_id` remains `0..1` on Physical Card — at most one current Storage Container, optional. Changing Storage never changes `inventory_id` (LDM-23), Collection allocation, Slot Assignment (LDM-35) or completion inputs (Section 5). Logical-layer formalization of C-58 — no new field introduced beyond what LDM-24 already fixes.

**Status:** APPROVED

## LDM-47 — Storage Container May Exist Empty; Independent of Collection

A Storage Container may exist with zero Physical Cards. Collection and Storage remain independent axes — a Storage Container may hold Physical Cards from multiple Collections of the same Inventory, or none. Default Storage Container (LDM-10, C-36) remains a suggested destination, not an exclusivity constraint. Storage is current-only, not historical — no "last known storage" field or table is fixed at this logical layer. Logical-layer formalization of C-59.

**Status:** APPROVED (decisão lógica, sem skeleton de histórico)

## LDM-48 — Storage Container Hierarchy (Optional Parent Reference)

A Storage Container may optionally reference a parent Storage Container — no field name or table is fixed at this layer, only the relationship itself is recognized. Physical Card continues to reference only the most specific ("leaf") Storage Container (LDM-24's `storage_container_id` is never a list, never a chain) — the full location path is always derived by walking parents, never stored redundantly. This preserves LDM-46's cardinality even under hierarchy. Logical-layer formalization of C-60.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-49 — Storage Never Crosses Inventory Boundaries

A Physical Card may only reference a Storage Container belonging to the same Inventory as its current `inventory_id` (LDM-23/LDM-45). Under hierarchy (LDM-48), parent and child Storage Container must belong to the same Inventory — no cross-Inventory edge is permitted anywhere in the tree. Custody (LDM-38/LDM-39) — not Storage — represents borrowing, grading, third-party custody or a card temporarily with another User. Logical-layer formalization of C-61.

**Status:** APPROVED

## LDM-50 — Storage Container Capacity: Optional, Non-Uniform

Capacity is an optional, type-dependent attribute of Storage Container — known, approximate or not applicable — never a uniform field across all types, and never a hard allocation-blocking rule at this logical layer. Distinct from Collection Layout's Grid Configuration capacity (LDM-31, digital slot count) — the two must not be conflated. Logical-layer formalization of C-62; no field or formula fixed.

**Status:** APPROVED (decisão lógica, sem fórmula física)

## LDM-51 — Storage Container Removal: Structural Emptiness

A Storage Container may only be removed when structurally empty: zero Physical Cards directly referencing it (LDM-46) and zero child Storage Containers (LDM-48) referencing it as parent. No cascading delete is defined — removal never deletes child Storage Containers nor invalidates Physical Card identity (LDM-19). Logical-layer formalization of C-63.

**Status:** APPROVED

## LDM-52 — Bulk Card Transfer

A logical operation moves, in a single act, all Physical Cards directly referencing a source Storage Container to a valid destination Storage Container (capable of directly holding Physical Cards), within the same Inventory (LDM-49). Only `storage_container_id` changes per affected Physical Card — `inventory_id`, Collection allocation, Slot Assignment and completion inputs are untouched, same guarantee as an individual move (LDM-46), applied at batch scope. Logical-layer formalization of C-64. Product-level flow (confirmation, partial-failure handling) deferred.

**Status:** APPROVED

## LDM-53 — Reparent Storage Container

A logical operation distinct from LDM-52 moves a child Storage Container to a different valid parent, within the same Inventory (LDM-49). Physical Cards referencing that Storage Container (or any of its descendants) are unaffected — no `storage_container_id` changes as a side effect. Logical-layer formalization of C-65. Product-level flow deferred.

**Status:** APPROVED

## LDM-54 — Default Storage Container Under Hierarchy

Collection's Default Storage Container (LDM-10) must reference a Storage Container capable of directly holding Physical Cards — never a purely organizational ancestor incapable of doing so. LDM-10 is not reopened; this only extends its semantics to the hierarchy introduced by LDM-48. Logical-layer formalization of C-66.

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

Physical Card
├── Inventory (0..1 — current tracked ownership; ver LDM-23)
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
        │   └── Slot Assignment (0..1, via Physical Card)
        └── Layout Region (0..N — agrupa Slots contíguos da mesma Page)

Physical Card
└── Slot Assignment (0..1 por Layout — ver LDM-35)
```

> Nota (2026-08-28, terminologia atualizada 2026-08-30): o bloco `Physical Card → Inventory` acima reflete o modelo vigente (`Physical Card → Inventory → User`); o texto original desta seção usava `Owner` direto (`Inventory Item → Owner`) — ver `checkpoint-2026-08-28.md` e LDM-23 (revisada) para a regra de cardinalidade completa.
>
> Nota (2026-08-30): o bloco `Collection Layout` acima resume LDM-29 a LDM-37. `Storage Container` permanece inteiramente ortogonal a esta árvore — não aparece nela porque Layout é digital, nunca localização física (C-38/C-44).
>
> Nota (2026-08-30): `Custody`, `Custodian` e `Availability` (LDM-38 a LDM-43) não aparecem na árvore acima — são dimensões lógicas reconhecidas, ortogonais a Inventory/Storage/Collection/Layout, sem skeleton físico fixado nesta rodada (ver bloco complementar acima e `concept-decisions.md` C-49–C-54).
>
> Nota (2026-08-30): `Storage Container` (LDM-44 a LDM-54) passa a suportar hierarquia opcional (parent/child, sempre dentro do mesmo Inventory) — a árvore acima continua mostrando apenas `Physical Card → Storage Container (0..1)` porque a Physical Card sempre referencia o container mais específico; a cadeia de parents, quando existir, é derivada, nunca uma segunda referência na Physical Card. Nenhum skeleton de Storage Container (id, inventory_id, parent_id) é fixado nesta rodada.

---

# 5. Completion Model Summary

```text
NONE
→ no completion calculation

STANDARD_SET
→ denominator = Cards of referenced Card Set
→ Physical Card → Card Variant → Card

MASTER_SET
→ denominator = Card Variants selected in Master Set Adopted Scope
→ Physical Card → Card Variant

REFERENCE_POSITION / POKEDEX
→ denominator = Pokédex Positions in Adopted Scope
→ Physical Card → Card Variant → Card → Pokemon → Pokédex Position
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
8. A second physical identity solely because a Physical Card joins a Collection.
9. Every canonical Card Variant being automatically mandatory in every Master Set.
10. Automatic Master Set denominator changes caused by normal catalog expansion.
11. Structurally mandatory Storage for Physical Card creation.
12. Automatic Physical Card transfer when Collection ownership changes.
13. Unconditional patrimonial authority for Collection Owner over items owned by other members.
14. `Placement` como nome canônico de entidade/relação para o posicionamento de uma Physical Card num Slot — terminologia superada por `Slot Assignment` (LDM-35, C-44). O termo apareceu apenas em `ux-exploration-2026-08-29.md` e `checkpoint-2026-08-29.md` (produzidos durante a exploração do spike visual do Binder), nunca havia sido ratificado em C-*/LDM-* anteriores; a reimersão documental (`COLLECTIONS-DOMAIN-REENTRY-01`) confirmou a ausência de lastro canônico antes de a frente `COLLECTIONS-LAYOUT-MODELING` decidir o nome definitivo a adotar. (Item 14 em si já usava, na sua origem em 2026-08-30, o nome então vigente `Inventory Item` para o exemplar — atualizado aqui para `Physical Card` por convergência terminológica, 2026-08-30.)
15. Um Slot exigir ocupação (Slot Assignment) para existir, ou uma Slot Assignment exigir Expected Content prévio — ambas as relações são independentes entre si e da ocupação (C-41/C-42/C-44).
16. Cardinalidade global de 1 Slot Assignment por Physical Card (independente de Layout) — rejeitada em favor de 1 por par (Physical Card, Layout), necessária para suportar múltiplos Layouts da mesma Collection (LDM-35).
17. Slot Assignment criar implicitamente Collection Allocation (ou vice-versa) — as duas relações permanecem independentes; Slot Assignment apenas *exige* Collection Allocation prévia, nunca a cria (LDM-35).

> Adendo (2026-08-28): também não implementar `owner_user_id` direto em Physical Card, nem qualquer fluxo de aprovação patrimonial fundamentado em "Collection compartilhada com itens de múltiplos owners" — ver `checkpoint-2026-08-28.md` e LDM-23 (revisada, 2026-08-30).
>
> Adendo (2026-08-30): ver `checkpoint-2026-08-30.md` para o diagnóstico completo de reconciliação da frente Collection Layout, incluindo a supersessão terminológica do item 14 acima.
>
> Adendo (2026-08-30): terminologia deste documento convergida de `Collection Item`/`Inventory Item` para `Physical Card` em todo texto normativo vigente — ver banner no topo do documento e `concept-decisions.md` C-47/C-48. Itens desta lista que citam terminologia histórica de outros documentos (ex.: item 14 acima, sobre `ux-exploration-2026-08-29.md`) preservam a citação e apenas anotam a atualização, sem reescrever a fonte citada.

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
Physical Card requires its own detailed model beyond the Collection-allocation decisions captured here. **Atualização 2026-08-28**: o próprio conceito de `Inventory` (Acervo) como aggregate 1:1 por usuário, dono real de toda `Physical Card` sob ownership corrente, foi introduzido nesta data — ver `checkpoint-2026-08-28.md`. **Atualização 2026-08-30**: a regra de cardinalidade corrente (`Physical Card` participa de no máximo um `Inventory` por vez, podendo não ter nenhum quando fora do escopo rastreado) foi formalizada em LDM-23 (revisada) e C-48 — deixa de existir apenas em nível de checkpoint/memo.

## Storage (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-44 a LDM-54)
Ownership, hierarquia, cardinalidade, capacidade, remoção e as duas operações de transferência (Bulk Card Transfer, Reparent) foram formalizadas em LDM-44 a LDM-54 (`concept-decisions.md` C-55–C-66). Storage cross-Inventory foi fechado como **não suportado** (LDM-49/C-61) — Custody cobre os cenários de empréstimo/grading/guarda por terceiro. Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico de Storage Container (id, inventory_id, parent_id — nenhum fixado); Protection/Encapsulation como dimensão própria (LDM-44/C-56, apenas reconhecida, não modelada); histórico de Storage ("last known storage", LDM-47/C-59); fórmula/mecânica de capacidade, inclusive capacidade agregada sob hierarquia; Product Behavior detalhado de remoção, Bulk Card Transfer e Reparent (fluxo, confirmação, tratamento de erro parcial).

## Custody / Availability (Atualização 2026-08-30)
Reconhecidas como dimensões lógicas distintas de Inventory (ownership), Storage (localização) e Collection/Layout (organização colecionável) — ver LDM-38 a LDM-43 e `concept-decisions.md` C-49–C-54. Nenhum skeleton físico, enum ou entidade `Custodian` foi fixado nesta rodada. Dependências não resolvidas: estrutura física de Custody; enum de Availability; entidade Custodian; fluxo de empréstimo completo; fluxo de grading.

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
**C-01 through C-37 — CLOSED**; **C-38 through C-46 — APPROVED** (Collection Layout); **C-47/C-48 — APPROVED** (Physical Card & Inventory, 2026-08-30); **C-49 through C-54 — APPROVED** (Custody & Availability, 2026-08-30); **C-55 through C-66 — APPROVED** (Storage, 2026-08-30)

Canonical document:
`concept-decisions.md`

## Logical
**LDM-01 through LDM-54 — APPROVED, LDM-25/26/27 SUPERSEDED (2026-08-28), LDM-23 REVISADA (2026-08-30)**

This document is the canonical logical checkpoint for LDM-01 through LDM-24 (Collection core), LDM-29 through LDM-37 (Collection Layout, 2026-08-30), LDM-38 through LDM-43 (Custody & Availability, 2026-08-30, sem skeleton físico), and LDM-44 through LDM-54 (Storage, 2026-08-30, sem skeleton físico). `checkpoint-2026-08-28.md` is canonical for the ownership-model simplification (now formalized directly in LDM-23). `checkpoint-2026-08-30.md` is canonical for the Layout reconciliation diagnostic and for the current open point. Terminology across this document was converged to `Physical Card` on 2026-08-30 — see banner at the top and `concept-decisions.md` C-47/C-48.

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
| 1.3 | **Convergência terminológica para `Physical Card`, 2026-08-30.** Por decisão de Fabrício (`concept-decisions.md`, C-47/C-48), todo texto normativo vigente deste documento (banner, header, Seções 1–8, LDM-01 a LDM-24 e LDM-29 a LDM-37) foi convertido de `Inventory Item`/`Collection Item` para `Physical Card` — apenas nomenclatura, nenhuma decisão de cardinalidade/campo/comportamento alterada por este motivo isoladamente (inclui a renomeação do campo `inventory_item_id` para `physical_card_id` no skeleton de Slot Assignment, LDM-35). Adicionalmente, **LDM-23 foi revisada em conteúdo**: deixou de ser um skeleton com `owner_user_id` anotado como parcialmente superado e passou a formalizar diretamente, no nível lógico, a regra de cardinalidade corrente entre `Physical Card` e `Inventory` (contraparte lógica de C-48) — primeira formalização lógica desta regra, que antes só existia em `checkpoint-2026-08-28.md` e em memos nunca promovidos a LDM. O texto original de LDM-23 é preservado no histórico de versões do repositório. **Texto de LDM-25, LDM-26, LDM-27 (SUPERSEDED) e da Seção 9 (void) foi deliberadamente preservado com a terminologia antiga**, por serem citações históricas verbatim, não normativa vigente — não convergidos. |
| 1.4 | **Bloco complementar Custody & Availability, 2026-08-30** (`COLLECTIONS-CUSTODY-AVAILABILITY-CONSOLIDATION-01`). Adicionadas LDM-38 a LDM-43, formalizando no nível lógico o bloco conceitual C-49 a C-54 (`concept-decisions.md`) — deliberadamente sem skeleton físico (campo, enum, tabela, entidade `Custodian`), por decisão explícita de escopo desta rodada. Seção 4 (nota adicional sobre ortogonalidade de Custody/Availability), Seção 7 (novas subseções `Storage` atualizada e `Custody / Availability`) e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-37 não reabertas em conteúdo. Storage detalhado permanece dependência não resolvida. |
| 1.5 | **Bloco complementar Storage, 2026-08-30** (`COLLECTIONS-STORAGE-CONSOLIDATION-01`), encerrando a subfrente `Collections — Storage conceptual modeling`. Adicionadas LDM-44 a LDM-54, formalizando no nível lógico o bloco conceitual C-55 a C-66 — deliberadamente sem skeleton físico além do que LDM-24 já fixa (`storage_container_id`, 0..1): nenhum campo, tabela ou identificador é introduzido para o próprio Storage Container, sua referência de Inventory ou sua referência de parent. Cobre: fronteira com Protection (LDM-44); ownership mediado por Inventory (LDM-45); cardinalidade reafirmada (LDM-46); existência vazia e caráter corrente (LDM-47); hierarquia opcional com regra de container-folha (LDM-48); fechamento de Storage cross-Inventory (LDM-49); capacidade opcional/não-uniforme (LDM-50); remoção condicionada a vazio estrutural (LDM-51); Bulk Card Transfer (LDM-52) e Reparent Storage Container (LDM-53); Default Storage sob hierarquia (LDM-54). Seção 4 (nota sobre hierarquia), Seção 7 (subseção `Storage` atualizada de "não resolvido" para "conceitualmente resolvido") e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-43 não reabertas em conteúdo. |
