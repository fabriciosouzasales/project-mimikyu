# Collection — Logical Data Model (LDM)

| Campo | Valor |
|--------|-------|
| **Documento** | Collection — Logical Data Model (Checkpoint Lógico) |
| **Arquivo** | `docs/domain-modeling/collections/logical-model.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` como fonte canônica em 2026-08-28 (pedido explícito de Fabrício). |
| **Decision Register** | LDM-01 a LDM-27 (núcleo Collection, checkpoint em evolução — ver banner de superação parcial abaixo); LDM-29 a LDM-37 (bloco complementar Collection Layout, 2026-08-30); LDM-23 revisada em 2026-08-30 (identidade e cardinalidade corrente de `Physical Card`, ver banner); LDM-38 a LDM-43 (bloco complementar Custody & Availability, 2026-08-30, sem skeleton físico); LDM-44 a LDM-54 (bloco complementar Storage, 2026-08-30, sem skeleton físico); LDM-55 a LDM-69 (bloco complementar Physical Card Lifecycle & Provenance, 2026-08-30, sem skeleton físico); LDM-70 a LDM-78 (bloco complementar Favorite, 2026-08-30, sem skeleton físico); LDM-79 a LDM-90 (bloco complementar Wishlist, 2026-08-30, sem skeleton físico); LDM-91 a LDM-108 (bloco complementar Physical Card Condition, 2026-08-30, sem skeleton físico); LDM-109 a LDM-128 (bloco complementar Grading / Certification, 2026-08-30, sem skeleton físico); LDM-129 a LDM-153 (bloco complementar Collection Collaboration / Permissions, 2026-08-30, sem skeleton físico); LDM-154 a LDM-174 (bloco complementar Collection Activity History / Audit, 2026-08-30, sem skeleton físico); LDM-175 a LDM-185 (bloco complementar Pokédex / REFERENCE_POSITION, 2026-09-03, sem skeleton físico — supersede LDM-16 e a cláusula Pokédex de LDM-17) |
| **Status** | Checkpoint lógico em evolução — modelo físico iniciado em 2026-08-31 (Inventory + Physical Card, LDM-23 core skeleton, CONFIRMADO EXECUTADO) e estendido em 2026-09-01 (Storage Container + `physical_card.storage_container_id`, LDM-44/LDM-45/LDM-46/LDM-49 primeira materialização física, CONFIRMADO EXECUTADO; Collection root, LDM-12 primeira materialização física, CONFIRMADO EXECUTADO; demais frentes NOT STARTED). Pokédex / REFERENCE_POSITION (LDM-175 a LDM-185): **CONCEPTUALLY CLOSED em 2026-09-03** e, desde 2026-09-06, **PHYSICALLY IMPLEMENTED / CLOSED** — Fatias A–E do Pokédex materializadas, validadas e promovidas (`6000`–`6126` e `5085`–`5103`; ver `docs/05d-colecoes-e-usuarios.md`). Próxima frente do projeto: **Binder/Layout Foundation**, ainda não iniciada. |
| **Escopo** | Modelagem lógica da entidade `Collection`, do domínio de posse (`Physical Card` — nome canônico desde 2026-08-30, ver `concept-decisions.md` C-47/C-48), desde 2026-08-30 de `Collection Layout`/`Page`/`Slot`/`Slot Assignment`, desde 2026-08-30 das dimensões lógicas `Custody`/`Custodian`/`Availability` (sem skeleton físico — ver LDM-38 a LDM-43), desde 2026-08-30 de `Storage`/`Storage Container` incluindo hierarquia opcional (sem skeleton físico — ver LDM-44 a LDM-54), desde 2026-08-30 de `Lifecycle`/`Provenance` (Ownership Entry/Transfer/Exit, sem skeleton físico — ver LDM-55 a LDM-69), desde 2026-08-30 de `Favorite` (User↔Card, sem skeleton físico — ver LDM-70 a LDM-78), desde 2026-08-30 de `Wishlist` (User↔Card Variant, sem skeleton físico — ver LDM-79 a LDM-90), desde 2026-08-30 de `Physical Card Condition` (sem skeleton físico — ver LDM-91 a LDM-108), desde 2026-08-30 de `Grading`/`Certification` (sem skeleton físico — ver LDM-109 a LDM-128), e desde 2026-08-30 de `Collection Collaboration`/`Permissions` (Owner estrutural, Membership, roles EDITOR/VIEWER, sem skeleton físico — ver LDM-129 a LDM-153), e desde 2026-08-30 de `Collection Activity History`/`Audit Log` (três camadas distintas — Lifecycle/Provenance, Activity History, Audit —, sem skeleton físico — ver LDM-154 a LDM-174) — não contém SQL nem modelo físico. |
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
- Logical model: **LDM-01 through LDM-27 — APPROVED** (LDM-25/26/27 superseded 2026-08-28, ver banner acima; LDM-23 revisada 2026-08-30 — `Physical Card` & cardinalidade corrente com `Inventory`); **LDM-29 through LDM-37 — APPROVED** (Collection Layout, 2026-08-30); **LDM-38 through LDM-43 — APPROVED** (Custody & Availability, 2026-08-30, sem skeleton físico); **LDM-44 through LDM-54 — APPROVED** (Storage, 2026-08-30, sem skeleton físico); **LDM-55 through LDM-69 — APPROVED** (Physical Card Lifecycle & Provenance, 2026-08-30, sem skeleton físico); **LDM-70 through LDM-78 — APPROVED** (Favorite, 2026-08-30, sem skeleton físico); **LDM-79 through LDM-90 — APPROVED** (Wishlist, 2026-08-30, sem skeleton físico)
- Physical model: **Inventory + Physical Card (LDM-23 core skeleton) — CONFIRMADO EXECUTADO (2026-08-31)**; **Storage Container + `physical_card.storage_container_id` (LDM-44/LDM-45/LDM-46/LDM-49 primeira materialização física) — CONFIRMADO EXECUTADO (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`)**; **Collection root (LDM-12 primeira materialização física) — CONFIRMADO EXECUTADO (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`)**; todas as demais frentes NOT STARTED — ver seção "Physical", abaixo

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

**Status:** APPROVED — 🔴 **parcialmente superseded em 2026-08-30** (`COLLECTIONS-TRANSVERSAL-RECONCILIATION-01`, ver LDM-129–LDM-153). Texto original preservado por rastreabilidade; frases superadas riscadas abaixo.

Shared access is represented separately through `Collection Member`, relating Collection, User, ~~permission profile and effective permissions~~. ~~UX presets may simplify assignment, but effective permissions remain authoritative.~~ The Owner is not simultaneously a normal Collection Member. Collection + User is unique. ~~The complete permission matrix will be finalized after Physical Card/Inventory, Storage and Layout responsibilities are sufficiently modeled.~~

> **Autoridade vigente para roles/permissões**: V1 fixed roles EDITOR/VIEWER, no custom permission profile and no future permission matrix (LDM-131/LDM-153 — logical formalization of C-143/C-165). "Collection + User is unique" and "the Owner is not simultaneously a normal Collection Member" remain valid — reaffirmed by LDM-129/LDM-130.

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

> **Nota de materialização física (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`).** A tabela `public.collection` foi construída cobrindo `id`, `game_id`, `owner_user_id`, `name`, `description`, `mode`, `lifecycle_status`, `visibility`, `default_storage_container_id`, `reference_locked_at`, `archived_at`, `created_at`, `updated_at` — sem reabrir nenhuma decisão abaixo. `completion_policy`, `started_at`, `created_by_user_id`, `updated_by_user_id` não foram materializados nesta rodada (fora de escopo do incremento 2B; `created_by_user_id`/`updated_by_user_id` seguem como candidato transversal não generalizado, ver nota abaixo do skeleton). Seis RPCs (`create_collection`, `update_collection_metadata`, `set_collection_default_storage`, `archive_collection`, `reactivate_collection`, `delete_collection`) formalizam as transições de lifecycle e as regras de imutabilidade (`owner_user_id`, `game_id`) já descritas neste skeleton. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Collection (Coleção)", para o modelo físico completo, e `database/schema/5030`-`5039` para o SQL `CANÔNICA`.

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

**Status:** SUPERSEDED (2026-09-03, `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`) — ver LDM-177. O mecanismo de Scope por adoção individual de Position como verdade primária (`Collection Pokédex Scope` acima) é substituído por Scope declarado (`FULL_REFERENCE`/`GENERATION_FILTERED`) do qual as Positions adotadas são **derivadas**, nunca selecionadas uma a uma. Texto original preservado abaixo, integralmente, por rastreabilidade — não implementar a partir daqui.

## LDM-17 — Physical Card Eligibility
Eligibility validates only the canonical universe; there is no arbitrary user-defined rule engine.

- Open Curation: no canonical-universe restriction.
- Card Set: Physical Card's Card must belong to referenced Card Set.
- ~~Pokédex: Card's principal Pokémon must correspond to a Pokédex Position in the Adopted Scope.~~ **SUPERSEDED (2026-09-03, `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`) — ver LDM-178.** Esta cláusula, isoladamente, lia como bloqueio duro (`hard block`) por incompatibilidade. A regra vigente para Pokédex passa a ser Species Match/Mismatch com aviso e confirmação explícita do usuário (`USER_OVERRIDE`), nunca bloqueio por incompatibilidade semântica — ver LDM-178. As cláusulas Open Curation e Card Set acima **não são afetadas** e permanecem vigentes sem alteração.

Language, rarity, variant and aesthetic preferences do not independently restrict eligibility unless a future explicit completion requirement uses them. Eligibility is derived, not stored as `is_eligible`. Eligibility and completion are independent.

**Status:** APPROVED (Open Curation e Card Set); cláusula Pokédex SUPERSEDED, ver acima

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

**Status:** APPROVED — decisão central inalterada. Nota de terminologia/sourcing (2026-09-03, `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`): "Pokémon"/`pokemon_id` neste LDM correspondem ao que passa a se chamar **Pokémon Species** (`species_id` no nível lógico) — ver LDM-175. A evidência estruturada para resolver este vínculo (`dexId` único da TCGdex) e a exigência de reconciliação editorial quando `dexId` for múltiplo/ausente estão formalizadas em LDM-182, sem reabrir esta decisão central.

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
- `REFERENCE_POSITION`: Card Variant → Card → Pokémon Species → Pokédex Position

Requirement satisfaction is derived rather than persisted as a second source of truth. Para `REFERENCE_POSITION`, "requirement satisfaction" refere-se à Position possuir Pokédex Position Assignment explícito — Allocation sozinha não basta (ver LDM-179/LDM-181, que revisam a leitura deste projection sem alterar a mecânica de `STANDARD_SET`/`MASTER_SET`, que permanecem satisfeitas por Allocation).

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

> **Nota de materialização física (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`).** A fundação física deste bloco foi construída, sem reabrir nenhuma decisão C-*/LDM-* abaixo: tabela `storage_container` (identidade própria + `inventory_id`, formalizando LDM-45), `physical_card.storage_container_id` (0..1, formalizando LDM-46), e a garantia estrutural de que Storage nunca cruza Inventory (LDM-49) via FK composta `(storage_container_id, inventory_id) → storage_container(id, inventory_id)` complementada por um CHECK que fecha uma lacuna de `MATCH SIMPLE` não prevista nesta rodada lógica. Hierarquia (LDM-48), capacidade (LDM-50), remoção estrutural (LDM-51), Bulk Card Transfer (LDM-52) e Reparent (LDM-53) permanecem sem skeleton físico — nenhuma linha deste bloco além de LDM-45/46/49 foi materializada. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Storage / Storage Container", para o modelo físico completo, e `database/schema/5020`-`5024` para o SQL `CANÔNICA`.

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

A Storage Container may optionally reference a parent Storage Container — no field name or table is fixed at this layer, only the relationship itself is recognized. Physical Card continues to reference only the Storage Container it is directly/most specifically assigned to (LDM-24's `storage_container_id` is never a list, never a chain) — the full location path, when the referenced container has a parent, is always derived by walking parents, never stored redundantly. This preserves LDM-46's cardinality even under hierarchy. Logical-layer formalization of C-60.

> **Nota (2026-08-30, ajuste de precisão textual — `COLLECTIONS-TRANSVERSAL-RECONCILIATION-01`)**: o termo "leaf" foi removido por poder sugerir, incorretamente, que somente Storage Containers sem filhos podem conter Physical Cards diretamente. Nenhuma decisão C-*/LDM-* estabelece essa restrição — C-63 reconhece explicitamente que um container com filhos também pode conter Physical Cards diretamente (a condição de remoção exige zero cards **e** zero filhos, não uma coisa ou outra). Sem mudança de semântica além da redação.

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

## Bloco complementar — Physical Card Lifecycle & Provenance (LDM-55 a LDM-69, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-67 a C-81 (`concept-decisions.md`), produzido por `COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-CONSOLIDATION-01`. Nenhum skeleton físico (campo, tabela, enum, entidade `Ownership Episode`) é fixado além do que LDM-23 já estabelece (`inventory_id`) — por decisão explícita de escopo, a estrutura física de Entry/Transfer/Exit, de Acquisition e de qualquer registro de Provenance permanece para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-54 não são reabertas — em particular, LDM-38 a LDM-43 (Custody/Availability) permanecem integralmente vigentes.

## LDM-55 — Lifecycle: Historical Facts, Permanent Identity

Lifecycle is the set of historical facts about a Physical Card over time, distinct from current-state fields (`inventory_id`, Custody, `storage_container_id`, Availability, condition). No event ever recreates the Physical Card's identity (LDM-19). Logical-layer formalization of C-67.

**Status:** APPROVED

## LDM-56 — Provenance: Subset of Lifecycle, Explicit Exclusions

Provenance is the subset of Lifecycle scoped to origin, ownership entry and relevant patrimonial trajectory. Provenance is not: a transversal Audit Log; full Storage history; full condition history; Pricing History; Valuation History. Logical-layer formalization of C-68.

**Status:** APPROVED

## LDM-57 — Current State vs. Historical Event

Current State fields (`inventory_id`, Custody, `storage_container_id`, Availability, condition) answer "what is true now"; Historical Event facts answer "what happened, and when" — repeatable, immutable once recorded. No current-state field is required to be derived from an event log by this decision. Logical-layer formalization of C-69.

**Status:** APPROVED

## LDM-58 — Ownership Entry

When tracked ownership of a Physical Card begins with no prior known MMKYU owner, an Ownership Entry exists conceptually. Associated acquisition data (date, origin, method, amount paid, currency, notes) is optional — none of it is required for basic Physical Card registration or bulk import, and no field is fixed at this logical layer. Logical-layer formalization of C-70.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-59 — Ownership Transfer: Single, Atomic Fact

An MMKYU-to-MMKYU transfer is a single patrimonial fact, not two independent Exit + Entry facts. It ends A's current ownership, begins B's current ownership, preserves the same Physical Card identity (LDM-19), and has no conceptual gap between the two — `inventory_id` moves directly from A's Inventory to B's Inventory (LDM-23). Logical-layer formalization of C-71.

**Status:** APPROVED

## LDM-60 — Ownership Exit

Ownership Exit ends tracked ownership with no known new MMKYU owner — `inventory_id` becomes null (LDM-23), without invalidating or recreating Physical Card identity. Logical-layer formalization of C-72.

**Status:** APPROVED

## LDM-61 — Reasons Qualify the Event

The reason for an Ownership Entry, Transfer or Exit qualifies the event as an attribute — never a separate structural event type per reason. No enum is fixed at this logical layer. Logical-layer formalization of C-73.

**Status:** APPROVED (decisão lógica, sem enum físico)

## LDM-62 — Ownership Episode: Conceptual Tool, No Entity

Ownership Episode — the interval during which a Physical Card remains under current ownership of a given Inventory/titular — is used only as a reasoning aid for Acquisition and Provenance. No entity, table or identifier is created for it at this logical layer. Logical-layer formalization of C-74.

**Status:** APPROVED (decisão lógica, sem entidade física)

## LDM-63 — Physical Card Provenance vs. Owner/Transaction Private Data

Physical Card Provenance (the card's own trajectory — episodes, approximate dates, general event category) is distinct from Owner/Transaction Private Data (amount paid, seller, buyer, freight, margin, counterpart, private notes) tied to a specific episode. Private data belonging to one owner's episode is never automatically inherited or exposed to the next owner. Detailed permissions are deferred. Logical-layer formalization of C-75.

**Status:** APPROVED (decisão lógica, sem modelo de permissão)

## LDM-64 — Evidence/Verification: Safe Language

Provenance is described as "recorded/tracked in MMKYU" — never "verified", "certified" or an "authenticated chain". No authenticity, certification, infallible physical matching or blockchain mechanism is assumed. A future evidence-level mechanism may exist but is not modeled here. Logical-layer formalization of C-76.

**Status:** APPROVED

## LDM-65 — Transfer Integrity: Parallel Consequences

An ownership change (Transfer or Exit) must result in a consistent state regarding Collection allocation, dependent Slot Assignment, and Storage — three parallel, independent consequences of the same patrimonial change, not a chain where Collection allocation derives from the Storage rule. Collection allocation incompatibility follows its own invariant (a Collection belongs to a titular); Slot Assignment dependency follows from requiring prior Collection allocation (LDM-35); Storage incompatibility follows from the Inventory boundary already fixed (LDM-49). No resolution Product Behavior is defined at this layer. Logical-layer formalization of C-77.

**Status:** APPROVED

## LDM-66 — Custody Remains Independent of Ownership, Including After Exit

Custody (LDM-38–LDM-43, not reopened) remains independent of current ownership. Ownership Exit does not force Custody to "not applicable" — no Custody decision conditions its applicability on current tracked ownership. Custody may remain conceptually meaningful after Exit (e.g., seller still physically holding the card, carrier, third party); in practice it tends to go stale absent a reason to update it — a practical concern, not a domain rule. Logical-layer formalization of C-78.

**Status:** APPROVED

## LDM-67 — Lifecycle V1 Core

The V1 core of Lifecycle is Ownership Entry, Ownership Transfer and Ownership Exit, existing as a natural consequence of patrimonial flows the product already supports — never requiring manual acquisition data entry. Loan, LOST/Recovery and Grading history are out of the V1 core; already-modeled current-state dimensions (Custody, Availability) remain fully valid. Logical-layer formalization of C-79.

**Status:** APPROVED

## LDM-68 — Grading: Minimal Closure

Closed at only: Grading may change a Physical Card's current certification state, and may in the future produce relevant lifecycle facts. Submission, return, regrade, cracking and any grading workflow are not modeled at this logical layer. Logical-layer formalization of C-80.

**Status:** APPROVED (decisão lógica, sem workflow)

## LDM-69 — Valuation/Pricing History Are Not Provenance

Pricing History and Valuation History are not part of Provenance (reaffirms LDM-56). Amount paid / sale amount may exist as private transactional data of an ownership episode (LDM-63) — never as the continuous market signal Pricing/Valuation represents. Pricing V1 is not reopened by this decision. Logical-layer formalization of C-81.

**Status:** APPROVED

---

## Bloco complementar — Favorite (LDM-70 a LDM-78, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-82 a C-90 (`concept-decisions.md`), produzido por `COLLECTIONS-FAVORITE-CONSOLIDATION-01`. Nenhum skeleton físico (campo, tabela, enum) é fixado — a estrutura física da relação User↔Favorite↔Card permanece para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-69 não são reabertas.

## LDM-70 — Favorite: Definition and Target Entity

Favorite represents a User's personal editorial preference for a Card. References exclusively Card — never Card Variant, Physical Card, Collection, Collection Allocation, Slot Assignment or Storage. Logical-layer formalization of C-82.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-71 — Favorite Belongs to the User, Transversal to Collections

Favorite belongs to the User, not to any Collection. It is transversal across all of the user's Collections and independent of the user's role toward a Collection (Owner or Member). No relation is fixed between Favorite and Inventory. Logical-layer formalization of C-83.

**Status:** APPROVED

## LDM-72 — Independence from Ownership

Favorite is independent of ownership. It may exist whether the User never owned any corresponding Physical Card, owns one, owns several, sold all, or reacquires in the future. Logical-layer formalization of C-84.

**Status:** APPROVED

## LDM-73 — Independence from Collection

Favorite neither alters nor depends on completion, Collection Allocation, canonical ordering, Layout or Slot Assignment. Logical-layer formalization of C-85.

**Status:** APPROVED

## LDM-74 — Favorite Is Binary

Favorite answers only whether a Card is a favorite of a User — yes or no. No score, rating, priority, level or ranking is modeled at this logical layer. Logical-layer formalization of C-86.

**Status:** APPROVED (decisão lógica, sem escala/ranking)

## LDM-75 — Conceptual Cardinality

A User may favorite N Cards; a Card may be favorited by N Users; at most one Favorite per (User, Card) pair. Physical constraint is not discussed at this logical layer. Logical-layer formalization of C-87.

**Status:** APPROVED (decisão lógica, sem constraint física)

## LDM-76 — Favorite vs. Wishlist

Favorite and Wishlist are independent concepts that may coexist without structural dependency between them. Wishlist itself remains unmodeled in depth at this logical layer. Logical-layer formalization of C-88.

**Status:** APPROVED

## LDM-77 — Each Card Is Its Own Editorial Identity

Each Card remains its own editorial identity per Set (reaffirms LDM-23's Card Variant/Card chain). Favoriting a Card from a given Set does not imply favoriting other Cards of the same Pokémon/character in other Sets — each printing requires its own Favorite. A future Pokémon/Subject Reference layer remains out of this round. Logical-layer formalization of C-89.

**Status:** APPROVED

## LDM-78 — Catalog Lifecycle Not Modeled

While a Card exists as an editorial identity in the catalog, Favorite remains bound to that same Card. Hard delete, deprecation behavior and catalog lifecycle are not modeled at this logical layer. Logical-layer formalization of C-90.

**Status:** APPROVED (decisão lógica, sem modelo de catalog lifecycle)

---

## Bloco complementar — Wishlist (LDM-79 a LDM-90, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-91 a C-102 (`concept-decisions.md`), produzido por `COLLECTIONS-WISHLIST-CONSOLIDATION-01`. Nenhum skeleton físico (campo, tabela, enum) é fixado — a estrutura física da relação User↔Wishlist↔Card Variant(+idioma) permanece para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-78 não são reabertas.

## LDM-79 — Wishlist: Definition and Mandatory Target Card Variant

Wishlist represents a User's personally declared intent to acquire a given Card Variant. Every Wishlist entry references a Card Variant mandatorily — there is no generic Card-level Wishlist in the current core. The corresponding Card is known indirectly through the Card Variant, at the same specificity level a Physical Card itself is referenced (C-47). Logical-layer formalization of C-91.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-80 — Language as Optional Refinement

Wishlist may optionally specify a desired language over the target Card Variant. Absence of language means any language is acceptable. Logical-layer formalization of C-92.

**Status:** APPROVED

## LDM-81 — Ownership Independence, No Automatic Removal

Wishlist is fully independent of current ownership. It may exist whether the User never owned any corresponding Physical Card, owns one, owns several, or owns exactly the same Card Variant + language desired — wanting a combination already owned, even in multiple copies, remains valid without requiring quantity. Acquisition (Ownership Entry or Transfer, LDM-58/LDM-59) does not automatically remove the Wishlist entry — it ceases to exist only by explicit User decision or by a future assisted product behavior, not modeled at this logical layer. Logical-layer formalization of C-93.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-82 — Independence from Completion: Wishlist Is Not Collection Missing

Wishlist is not derived from completion. All combinations are valid: a completion gap without Wishlist; Wishlist without a completion gap; both; neither. Logical-layer formalization of C-94.

**Status:** APPROVED

## LDM-83 — No Structural Link to Collection

No structural link exists between Wishlist and Collection at this logical layer — Wishlist does not belong to any Collection. A future contextual association may be studied as Product Behavior or future extension, without making Collection the owner of Wishlist. Logical-layer formalization of C-95.

**Status:** APPROVED (decisão lógica, sem vínculo estrutural)

## LDM-84 — Independence from Expected Content

Wishlist and Expected Content (LDM-31/C-42) are independent. Expected Content answers what a Slot expects (organizational, belongs to the Slot); Wishlist answers what Card Variant the User intends to acquire (personal intent, belongs to the User). They share catalog vocabulary, but Expected Content's granularity (mandatory Card, optional Variant) is not reused as justification for Wishlist's shape. Logical-layer formalization of C-96.

**Status:** APPROVED

## LDM-85 — Independence from Favorite

Wishlist and Favorite (LDM-70–LDM-78) are independent — valid in any combination: Favorite without Wishlist; Wishlist without Favorite; both; neither. The granularity difference is intentional: Favorite targets Card (broad editorial preference); Wishlist targets Card Variant (specific acquisition intent). Logical-layer formalization of C-97.

**Status:** APPROVED

## LDM-86 — Binary V1 Core

Wishlist is binary at the V1 core: the existence of an entry means "this combination is still desired." Quantity, priority, grail, ranking, target price, alerts and procurement behavior remain out of the V1 core. Logical-layer formalization of C-98.

**Status:** APPROVED (decisão lógica, sem escala/quantity)

## LDM-87 — Conceptual Cardinality/Duplicity

Conceptual duplicity exists only when two entries share the same Card Variant and the same language condition (both without language, or the same specific language). Different combinations are not structural duplicity — e.g., "Variant X + any language" and "Variant X + JP" may coexist. Any warning or merge between overlapping entries is Product Behavior, not a domain rule. Logical-layer formalization of C-99.

**Status:** APPROVED (decisão lógica, sem constraint física)

## LDM-88 — Condition/Grading: Future Boundary

Condition and grading are not incorporated into Wishlist at this round. Only the future possibility of refinements such as condition, raw/graded, grader and grade is registered — only after those dimensions are formally modeled in their own round. The existing finding is preserved: historical textual references treat `condition` as a Physical Card dimension without corresponding C-*/LDM-* — not corrected at this round, deferred to a future dedicated subfrente, `Collections — Physical Card Condition Modeling`. Logical-layer formalization of C-100.

**Status:** APPROVED (decisão lógica, sem modelo de condition/grading)

## LDM-89 — Marketplace: Future Boundary, No Structural Dependency

Marketplace may future consume Wishlist for matching, suggestions, alerts and purchase opportunities. Wishlist does not structurally depend on Marketplace — its existence and meaning do not presuppose that module, whose boundaries remain undecided. Logical-layer formalization of C-101.

**Status:** APPROVED

## LDM-90 — User Scope

Wishlist belongs to the User. It does not belong to Collection, Inventory, or a specific Physical Card. Logical-layer formalization of C-102.

**Status:** APPROVED

---

## Bloco complementar — Physical Card Condition (LDM-91 a LDM-108, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-103 a C-120 (`concept-decisions.md`), produzido por `COLLECTIONS-PHYSICAL-CARD-CONDITION-CONSOLIDATION-01`. Nenhum skeleton físico (campo, tabela, enum) é fixado — a estrutura física de Condition, incluindo a forma exata de referenciar `card_condition` a partir de Physical Card, permanece para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-90 não são reabertas.

## LDM-91 — Condition: Definition and Target Entity

Condition is the standardized classification of a Physical Card's current physical state, according to MMKYU's canonical scale. It belongs exclusively to Physical Card — never to Card, Card Variant, Collection, Wishlist, or Storage. Logical-layer formalization of C-103.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-92 — Canonical Reference Ratified: card_condition

It is conceptually ratified that the existing shared reference `card_condition` (CONFIRMED EXECUTED, Pricing Increment P1, 2026-08-16 — see `docs/05f-pricing.md`) represents MMKYU's canonical Condition scale. Collections does not create a second scale, a second vocabulary, or a parallel Condition concept — Physical Card Condition and Pricing's condition mappings (`pricing_condition_mapping`) consume the same canonical reference. No schema change is proposed or applied at this round. Logical-layer formalization of C-104.

**Status:** APPROVED (decisão lógica, sem alteração de schema)

## LDM-93 — Canonical Scale Formalized

The confirmed physical canonical scale in `card_condition` is: **M** (Mint), **NM** (Near Mint), **LP** (Lightly Played), **MP** (Moderately Played), **HP** (Heavily Played), **DMG** (Damaged) — `condition_order` 1 through 6, in that order. The long-form codes previously cited in this decision (`MINT`, `NEAR_MINT`, `LIGHTLY_PLAYED`, `MODERATELY_PLAYED`, `HEAVILY_PLAYED`, `DAMAGED`) were never the physical/canonical codes — they were this decision's textual expectation, not the real form stored in `card_condition.code`. They must no longer be used as physical/canonical codes. Logical-layer formalization of C-105.

> **Closure note (2026-08-31, `COLLECTIONS-CARD-CONDITION-RECONCILIATION-02`)**: the historical discrepancy registered by this decision (a post-migration validation mentioning 5 records vs. documentation listing 6 codes) is **CLOSED**. `M`/Mint was added physically via the UI — the step Fabrício refers to as "PRE-PHYSICAL-GATE" — and the subsequent read-only audit `COLLECTIONS-CARD-CONDITION-MINT-POSTCHECK-01` confirmed the 6 physical rows of `card_condition` are exactly M/NM/LP/MP/HP/DMG, `condition_order` 1..6, with no Pricing code depending on an "exactly 5 conditions"/fixed `condition_order` range assumption — conclusion **SAFE**, zero regression.

**Status:** APPROVED — 6 condições canônicas confirmadas fisicamente, `condition_order` 1..6, pendência histórica de contagem CLOSED.

## LDM-94 — Canonical Code vs. Localized Label

The Condition code (e.g. `NM`) is a stable, language-independent identity. The label displayed to the User is localized and translated separately (e.g. pt-BR "Praticamente Nova", en "Near Mint"). The internal code is never bound to a specific translated label. Logical-layer formalization of C-106.

**Status:** APPROVED — exemplo atualizado em 2026-08-31 (`COLLECTIONS-CARD-CONDITION-RECONCILIATION-02`) para usar um code físico real.

## LDM-95 — Brazilian Market Evidence

Registered as market-alignment evidence: the vocabulary observed on Brazilian specialized sites (M/Nova, NM/Praticamente Nova, SP-LP/Usada Levemente, MP/Usada Moderadamente, HP/Muito Usada, D/Danificada), which converges semantically, in order and meaning, with MMKYU's canonical scale (LDM-93). Market abbreviations do not become new canonical codes. Logical-layer formalization of C-107.

> **Precision note (2026-08-31, `COLLECTIONS-CARD-CONDITION-RECONCILIATION-02`)**: the market abbreviations listed above are observed external vocabulary, not MMKYU internal identity. In particular, the "D" in "D/Danificada" is **not** the canonical code — the canonical code is `DMG` (C-105/LDM-93); the coincidence between market "M" (Nova) and the canonical code `M` is market semantics, not a derivation or origin of the internal code. External nomenclatures may vary by source and never create, alter, or substitute `card_condition.code`. Any equivalence between an external source's code (e.g. a Pricing source such as JustTCG, or any other origin) and the canonical scale belongs exclusively to the mapping layer (`pricing_condition_mapping` or a future equivalent), never to the canonical vocabulary itself.

**Status:** APPROVED

## LDM-96 — Optionality

Condition is optional. It does not block basic registration, bulk import, or Ownership Entry (LDM-58). Absence of Condition means "not informed" — no `UNKNOWN` value is created merely to represent that absence. Logical-layer formalization of C-108.

**Status:** APPROVED

## LDM-97 — Declared, Not Certified

Raw Condition is a current declared/registered classification — no independent verification, certification, MMKYU inspection, or guaranteed objective truth is assumed. The same safe-evidence-language discipline already used for Provenance (LDM-64) applies. Logical-layer formalization of C-109.

**Status:** APPROVED

## LDM-98 — Damage/Defects Out of V1 Core

Condition represents a global classification. Detailed damage/defects (whitening, scratches, crease, dent, stains, edge wear, print lines, centering, water damage, and others) are not modeled at this round — they remain out of the V1 core. Logical-layer formalization of C-110.

**Status:** APPROVED

## LDM-99 — Condition × Grading

Condition ≠ Grading. Condition is a canonical/declared physical-state classification; Grading (LDM-68) is external certification. Neither is automatically derived from the other. This round does not decide whether a currently graded Physical Card retains a current Condition, treats Condition as not applicable, preserves only a prior evaluation, or can have both simultaneously — that applicability is deferred to a future `Collections — Grading / Certification Domain Modeling` subfrente. Logical-layer formalization of C-111.

**Status:** APPROVED (decisão lógica, aplicabilidade a graded cards não decidida)

## LDM-100 — Raw/Graded Is Not a Condition Value

"Raw vs. graded" is not a Condition value. That status structure belongs to Grading/Certification and, eventually, to Protection/Encapsulation (LDM-44) — not to the Condition canonical scale. Logical-layer formalization of C-112.

**Status:** APPROVED

## LDM-101 — No History at V1 Core

The V1 core keeps only Current Condition, without Condition History. Reaffirms the exclusion already registered in LDM-56/LDM-69 (Lifecycle & Provenance). Future material condition-change events may be evaluated later in a dedicated Lifecycle round. Logical-layer formalization of C-113.

**Status:** APPROVED

## LDM-102 — Independence from Identity and Other Dimensions

A Condition change does not alter: Physical Card identity (reaffirms C-47); Card Variant; ownership; Collection Allocation; Slot Assignment; Favorite; Wishlist; Storage; Custody. Logical-layer formalization of C-114.

**Status:** APPROVED

## LDM-103 — Independence from Language

Condition is independent of language. Language describes the specimen (printing/localization); Condition classifies its current physical state — orthogonal axes. Logical-layer formalization of C-115.

**Status:** APPROVED

## LDM-104 — Independence from Storage/Custody

Changes to Storage or Custody do not alter Condition by structural rule. Real-world damage may occur (handling, transport, storage conditions), but that is real-world causality, not a structural dependency between the concepts. Logical-layer formalization of C-116.

**Status:** APPROVED

## LDM-105 — Relationship with Valuation

Condition may future be an input to Valuation, but Condition ≠ Price and Condition ≠ Valuation. No fixed discount/price factor is included inside Condition — a precedent already established by Pricing V1 itself (`05f-pricing.md`), which explicitly rejected embedding that factor in `card_condition`. Pricing V1 is not reopened by this decision. Logical-layer formalization of C-117.

**Status:** APPROVED (decisão lógica, sem reabrir Pricing)

## LDM-106 — Filter Semantics Is Not a New Condition Value

Expressions such as "NM or better" / "Near Mint or better" are not additional Condition values — they are filter/comparison semantics based on the canonical scale's ordering (`condition_order`, already present in `card_condition`). UX and filter mechanism are not modeled at this round. Logical-layer formalization of C-118.

**Status:** APPROVED (decisão lógica, sem modelagem de UX)

## LDM-107 — Wishlist Remains Without Condition

Wishlist V1 (LDM-79–LDM-90) remains without Condition. The future possibility of refining Wishlist by Condition (already anticipated in LDM-88) can only be evaluated in a dedicated round, without altering LDM-79–LDM-90 at this consolidation. Logical-layer formalization of C-119.

**Status:** APPROVED

## LDM-108 — V1 Minimum Scope

The V1 minimum scope for Condition is: optional Current Condition; shared canonical scale (`card_condition`); language-independent code with localized label; no detailed defects; no history; no evidence levels; no mandatory fill; no automatic derivation from Grade. Logical-layer formalization of C-120.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

---

## Bloco complementar — Grading / Certification (LDM-109 a LDM-128, 2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-121 a C-140 (`concept-decisions.md`), produzido por `COLLECTIONS-GRADING-CERTIFICATION-CONSOLIDATION-01`. Nenhum skeleton físico (campo, tabela, enum) é fixado — a estrutura física de Grading Company, Grade Scale, Grade e Certification permanece para uma rodada de modelagem lógica/física própria. LDM-01 a LDM-108 não são reabertas.

## LDM-109 — Grading vs. Certification

Grading is the process/workflow of external evaluation performed by a specialized third party. Certification is the formal result issued by a Grading Company for a Physical Card. The V1 core models only the current Certification — the Grading workflow (submission, evaluation, turnaround) is not modeled (reaffirms LDM-68). Logical-layer formalization of C-121.

**Status:** APPROVED (decisão lógica, sem workflow)

## LDM-110 — Certification: Target Entity

Certification belongs exclusively to Physical Card — never to Card, Card Variant, Collection, Wishlist, or Storage. The same Card Variant may have raw, PSA 10, PSA 9, and CGC 10 Physical Cards simultaneously, each with its own identity (C-47). Logical-layer formalization of C-122.

**Status:** APPROVED

## LDM-111 — Grading Company: Reference Data

Grading Company is its own Reference Data, with stable identity, conceptually supporting at least name, code/abbreviation, and active/inactive status (e.g., PSA, CGC, BGS). No physical structure is created at this round. Logical-layer formalization of C-123.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-112 — Grade Scale

Grade has no isolated meaning — it depends on Grading Company + Grade Scale. No equivalence is assumed between PSA 10, BGS 10, and CGC 10. The future possibility of multiple Grade Scales per Grading Company is recognized, without fixing physical cardinality at this round. Logical-layer formalization of C-124.

**Status:** APPROVED (decisão lógica, cardinalidade não fixada)

## LDM-113 — Grade

Grade is the recognized result within a specific Grade Scale. Its representation may involve value (numeric, integer or decimal) and/or textual designation/label, per the Grading Company/Grade Scale convention — not reduced to a plain number nor to an unstructured free string. Future qualifiers (e.g., Black Label) are recognized as a possible third facet, not resolved into structure at this round. No enum or physical taxonomy is created. Logical-layer formalization of C-125.

**Status:** APPROVED (decisão lógica, sem enum físico)

## LDM-114 — Certification Number

Certification Number is the identifier issued by the Grading Company for that certification. At V1, it is optional — its absence does not prevent a declared Certification from existing, and its presence does not imply verification by MMKYU. No separate "Grading Declaration" concept is created: a single concept, Certification, covers both cases, with Certification Number as an optional refining/identifying attribute. Verification and physical uniqueness are deferred. Logical-layer formalization of C-126.

**Status:** APPROVED (decisão lógica, sem verification/uniqueness física)

## LDM-115 — Current Certification: Cardinality

A Physical Card has at most one Current Certification (0..1) — no multiple simultaneous Current Certifications. History of prior certifications is out of V1. Logical-layer formalization of C-127.

**Status:** APPROVED (decisão lógica, sem histórico)

## LDM-116 — Raw/Graded: Derived Predicate

Raw/Graded is a predicate derived exclusively from the existence of Current Certification: no Current Certification → RAW; with Current Certification → GRADED. No manually maintained parallel status is created. Logical-layer formalization of C-128.

**Status:** APPROVED

## LDM-117 — Condition × Certification: Current Applicability Exclusivity

Definitively closes the pending point left open by LDM-99/LDM-100 (C-111/C-112): Current Condition and Current Certification are mutually exclusive regarding current applicability at V1. RAW → Current Condition may optionally be informed (reaffirms LDM-96). GRADED (Current Certification exists) → Current Condition is not applicable while that Current Certification remains current. This does not mean Grade equals, semantically replaces, or derives Condition (PSA 9 ≠ NEAR_MINT) — Condition and Certification remain distinct concepts, each with its own scale and provenance (reaffirms LDM-99/LDM-100, not altered). Only simultaneous applicability changes, never the nature of the concepts. Logical-layer formalization of C-129.

**Status:** APPROVED (decisão lógica, fecha aplicabilidade simultânea)

## LDM-118 — Condition History Out of V1

Condition registered before a current Certification does not remain as Current Condition (reaffirms LDM-101, Condition History out of V1). If a future product need arises to preserve "Condition before grading," that belongs to Condition History/Lifecycle, a dedicated future round — not resolved here. Logical-layer formalization of C-130.

**Status:** APPROVED

## LDM-119 — Crack

Crack does not alter Physical Card identity (reaffirms C-47). When the Current Certification ceases to exist: the Physical Card becomes RAW by derivation (LDM-116); Current Condition becomes applicable again; no prior Condition value is automatically restored — if the User wants to inform Condition again, it is a new current evaluation, starting from the same "not informed" state as any raw Physical Card (LDM-96). Crack workflow/event is not modeled in detail. Logical-layer formalization of C-131.

**Status:** APPROVED (decisão lógica, sem workflow)

## LDM-120 — Regrade

Regrade preserves the same Physical Card (reaffirms C-47). Conceptually: the prior Certification stops being current; the new Certification becomes current. History of the prior one is out of V1. The temporal behavior of the workflow between submission and issuance of the new Certification is not canonized — the sufficient rule is: while a Current Certification exists, Current Condition is not applicable (LDM-117). Logical-layer formalization of C-132.

**Status:** APPROVED (decisão lógica, sem workflow temporal)

## LDM-121 — Grade ≠ Condition

No automatic Grade → Condition mapping is created. Any future correlation belongs to Analytics/Product Behavior, never to the domain's canonical rule. Logical-layer formalization of C-133.

**Status:** APPROVED

## LDM-122 — Certification Verification

Certification at V1 is registered/declared — it does not imply verified authenticity, official lookup, or MMKYU-confirmed certification (same safe-language discipline as LDM-64/LDM-97). External evidence/verification is out of V1. Logical-layer formalization of C-134.

**Status:** APPROVED

## LDM-123 — Subgrades / Qualifiers Out of V1 Core

Subgrades (e.g., Centering, Corners, Edges, Surface) are out of the V1 core. Special labels/qualifiers may exist per the Grade Scale (LDM-113), but their detailed structure is not modeled at this round. Logical-layer formalization of C-135.

**Status:** APPROVED

## LDM-124 — Certification ≠ Protection/Encapsulation

Certification is distinct from Protection/Encapsulation (LDM-44/C-56). A slab represents physical encapsulation, not the Certification itself. Protection/Encapsulation is not modeled at this round. Logical-layer formalization of C-136.

**Status:** APPROVED

## LDM-125 — Certification × Custody/Storage

Certification does not define Custody or Storage. During grading, Custody continues to be handled by the already-closed domain (LDM-39, which already lists "grading company" as an example Custodian — not reopened). A graded Physical Card may use any valid Storage (reaffirms LDM-46/C-58); a slab does not automatically become Storage (reaffirms LDM-44/C-56). Logical-layer formalization of C-137.

**Status:** APPROVED

## LDM-126 — Relationship with Valuation

Certification/Grade may future be inputs to Valuation, but Grade ≠ Price and Certification ≠ Valuation — same precedent as Condition (LDM-105/C-117). No fixed factor is created. Pricing V1 is not reopened. Logical-layer formalization of C-138.

**Status:** APPROVED (decisão lógica, sem reabrir Pricing)

## LDM-127 — Wishlist Remains Unchanged

Wishlist V1 (LDM-79–LDM-90) remains unchanged. Future refinements (graded only, specific Grading Company, minimum grade) may be studied in a dedicated round, without altering LDM-79–LDM-90 at this consolidation. Logical-layer formalization of C-139.

**Status:** APPROVED

## LDM-128 — V1 Minimum Scope

The V1 minimum scope for Grading/Certification is: Grading Company; Grade Scale; Grade (value and/or designation); optional Certification Number; 0..1 Current Certification per Physical Card; derived raw/graded; Condition not applicable while graded. Out of V1: submission workflow; regrade workflow; crack workflow; Certification History; Condition History; subgrades; external verification; evidence levels; detailed Protection/Encapsulation. Logical-layer formalization of C-140.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

---

## Bloco complementar — Collection Collaboration / Permissions (2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-141 a C-165 (`concept-decisions.md`). LDM-01 a LDM-128 não são reabertas.

## LDM-129 — Collection Owner as Structural Relation

Collection Owner is a structural relation between `Collection` and exactly one `User`, distinct from Collection Membership — Owner is not a Membership row. Collection ownership transfer remains out of scope. Logical-layer formalization of C-141.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-130 — Collection Membership

Collection Membership represents exclusively the collaborative participation of non-owner Users in a specific Collection. Conceptual cardinality: Collection → 0..N Memberships. Logical-layer formalization of C-142.

**Status:** APPROVED

## LDM-131 — Membership Roles

V1 Membership roles: EDITOR and VIEWER. OWNER is not a Membership role (reaffirms LDM-129). UX labels ("Proprietário", "Editor", "Visualizador") may exist without requiring structural identity with these roles. Logical-layer formalization of C-143.

**Status:** APPROVED

## LDM-132 — Collaboration ≠ Ownership

Membership/Collaboration never grants ownership over Physical Cards, Inventory, Storage, Favorite, Wishlist, or the Owner's private data. Editing a Collection is not equivalent to owning its exemplars. Logical-layer formalization of C-144.

**Status:** APPROVED

## LDM-133 — Viewer

VIEWER is a formal, read-only Member — may view Collection, Layout, Expected Content, and progress/completion; cannot edit. VIEWER does not mean "anyone who can view" — formally distinct from Public Access (LDM-140). Logical-layer formalization of C-145.

**Status:** APPROVED

## LDM-134 — Editor

EDITOR may edit common metadata, Layout, Expected Content, reorder Pages, and move Slot Assignments of already-allocated Physical Cards. By role, EDITOR may not create/remove Collection Allocation, nor alter Storage, Condition, Certification, Availability, or ownership/Inventory. Logical-layer formalization of C-146.

**Status:** APPROVED

## LDM-135 — Collection Allocation as Owner-Authorized Collection Operation

Collection Allocation remains Owner-only at V1. Not described as a patrimonial operation per se — Allocation does not alter ownership, Inventory participation, Storage, Condition, Certification, or Availability. It is Owner-only because it determines which private Physical Cards from the Owner's Inventory participate in that Collection, requiring authority over the set of eligible exemplars. Conceptual classification, no definitive technical naming: **Owner-authorized Collection operation**. Logical-layer formalization of C-147.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-136 — Slot Assignment After Allocation

Once a Physical Card is validly allocated to the Collection, EDITOR may operate on Slot Assignment/Layout. Conceptual split: Owner decides "which exemplars enter/leave the Collection?" (LDM-135); Editor decides "how already-allocated exemplars are organized?". Reaffirms LDM-35. Logical-layer formalization of C-148.

**Status:** APPROVED

## LDM-137 — Expected Content / Layout

EDITOR may edit Expected Content, Layout, Pages, grid (per already-closed rules), merge/unmerge, and slot lock/unlock, plus general visual organization — without reopening the Layout/Page/Slot semantics proper (LDM-29–LDM-37). Logical-layer formalization of C-149.

**Status:** APPROVED

## LDM-138 — Collection Metadata

Common metadata (name, description, objective, cover image) is editable by Owner + Editor. Sensitive structural decisions (Visibility, Archive/Delete, changes subject to existing locks/rules) remain Owner-only, without reopening reference locking. Logical-layer formalization of C-150.

**Status:** APPROVED

## LDM-139 — Visibility

PUBLIC/PRIVATE is Owner-only at V1. Editor cannot publish or privatize the Owner's Collection. Logical-layer formalization of C-151.

**Status:** APPROVED

## LDM-140 — Public Access ≠ Membership

A PUBLIC Collection may be viewed by a non-Member User; that User does not become a Member and does not receive the VIEWER role. Formalized: Visibility ≠ Membership ≠ Role. Public Access is a consequence of Visibility, not a fourth independent axis, and must not be confused with the VIEWER role. Logical-layer formalization of C-152.

**Status:** APPROVED

## LDM-141 — Invite / Acceptance

Membership arises only after an invite issued by the Owner and explicit acceptance by the User — never created silently. Notifications out of scope. Logical-layer formalization of C-153.

**Status:** APPROVED

## LDM-142 — Membership Management

At V1, only Owner invites and removes Members. A Member may leave voluntarily. Owner does not participate in these mechanisms as a Member (reaffirms LDM-129). Logical-layer formalization of C-154.

**Status:** APPROVED

## LDM-143 — Member Exit

Removal or voluntary exit ends Membership without altering Collection ownership, without transferring Physical Cards, without altering Favorite/Wishlist/personal data, and without undoing prior edits — which remain part of the Collection's state, not the editing user's. Logical-layer formalization of C-155.

**Status:** APPROVED

## LDM-144 — Owner Invariant

Owner is not invited, does not accept an invite, does not leave via Membership, and is not removed via Membership (reaffirms LDM-129/LDM-142). Collection ownership transfer is a separate, future flow, not decided at this round. Logical-layer formalization of C-156.

**Status:** APPROVED

## LDM-145 — Physical Card Visibility

Collaborator may only view Physical Cards already allocated to that specific Collection — no access to the Owner's full Inventory. Visibility limited to the context necessary for collaboration. Logical-layer formalization of C-157.

**Status:** APPROVED

## LDM-146 — Private Data

Collaboration does not automatically expose amount paid, seller/buyer, private transaction notes, financial data, Favorite, Wishlist, Inventory beyond necessary context, Storage, or Provenance. Logical-layer formalization of C-158.

**Status:** APPROVED

## LDM-147 — Storage Privacy

Storage remains private by default. Membership does not grant automatic access to the physical location of exemplars (reaffirms LDM-46/LDM-99). Any future exposure requires its own decision. Logical-layer formalization of C-159.

**Status:** APPROVED

## LDM-148 — Condition / Certification Visibility

Condition and Certification of allocated Physical Cards may be visible for curatorial purposes; editing remains Owner-only. Read access ≠ edit authority — reaffirms the independence of these dimensions from other structures (LDM-96/LDM-117). Logical-layer formalization of C-160.

**Status:** APPROVED

## LDM-149 — Provenance

At V1, Collaboration neither requires nor grants access to Provenance. Any future exposure is a specific product/privacy decision, without reopening Lifecycle (reaffirms LDM-55/LDM-63). Logical-layer formalization of C-161.

**Status:** APPROVED

## LDM-150 — Owner-Only Operations

Remain Owner-only at V1: Membership management; Visibility; Archive/Delete; Collection Allocation; Storage changes; Condition changes; Certification changes; Availability changes; ownership/Inventory operations; access/editing of private data. Logical-layer formalization of C-162.

**Status:** APPROVED

## LDM-151 — Sharing

Public View/shareable access ≠ Collaboration. A shareable link does not create Membership. A private link for a PRIVATE Collection remains a future possibility, with no mechanism decided. Logical-layer formalization of C-163.

**Status:** APPROVED

## LDM-152 — Audit (Future Need)

Future need to audit Collaborator actions is recognized, especially over Layout, Expected Content, Slot Assignment, and metadata. Audit Log is not modeled at this round — only the need is registered. Logical-layer formalization of C-164.

**Status:** APPROVED (necessidade registrada, sem solução modelada)

## LDM-153 — V1 Minimum Scope

Collection with exactly 1 structural Owner; Collection Membership with 0..N non-owner Members, role EDITOR or VIEWER; EDITOR covers Collection/Layout curation, Expected Content, Slot Assignment, common metadata; VIEWER covers collaborative read access; OWNER holds structural authority, Membership, Visibility, Archive/Delete, Collection Allocation, and remaining Owner/Inventory-scoped operations; Public User may view a PUBLIC Collection without becoming a Member or receiving the VIEWER role; no custom permission system at V1. Logical-layer formalization of C-165.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

---

## Bloco complementar — Collection Activity History / Audit (2026-08-30)

Formaliza, no nível lógico, o bloco conceitual C-166 a C-186 (`concept-decisions.md`). LDM-01 a LDM-153 não são reabertas.

## LDM-154 — Three Layers

`Physical Card Lifecycle/Provenance`, `Collection Activity History`, and `Audit Log` are distinct concepts; no layer substitutes the others. The same occurrence may eventually feed more than one layer, but they have different purpose, audience, and exposure. Logical-layer formalization of C-166.

**Status:** APPROVED

## LDM-155 — Collection Activity History

Collection Activity History is the temporal sequence of significant domain occurrences that let a user understand how a Collection evolved or was operated. It is Collection-scoped, user-facing, semantically understandable — not a raw view of technical mutations. Logical-layer formalization of C-167.

**Status:** APPROVED

## LDM-156 — Activity Trigger

Refinement over the memo: Activity is not literally limited to "action that directly changes Collection state" — it represents a significant domain occurrence related to the Collection's evolution/operation, normally arising from a persistent state change. Reading, navigation, no-effect attempts, internal technical logs, and user-irrelevant mutations do not generate Activity. Relevant system outcomes may future generate Activity if they satisfy the same semantic criterion. Logical-layer formalization of C-168.

**Status:** APPROVED

## LDM-157 — Semantic Activity

Activity uses domain language (e.g., "Card moved from Slot 12 to Slot 24"), never field names or technical schema (e.g., "slot_position changed"). Logical-layer formalization of C-169.

**Status:** APPROVED

## LDM-158 — Candidate Categories

Recognized as candidates, non-exhaustive: Collection metadata; Layout; Page; Slot/Region; Expected Content; Slot Assignment; Collection Allocation; Membership; Visibility; Archive; relevant system operations. Definitive catalog not closed at this round. Logical-layer formalization of C-170.

**Status:** APPROVED

## LDM-159 — Actor

Activity may have an actor when applicable: Owner, Editor, System. Viewer and Public User do not alter state in the V1 model and therefore do not generate Activity through simple reading. Logical-layer formalization of C-171.

**Status:** APPROVED

## LDM-160 — Activity Visibility

Activity History is visible at V1 to Owner, Members EDITOR, and Members VIEWER. Not automatically exposed to Public User, even when Collection = PUBLIC. Public Access ≠ access to internal collaboration history. Logical-layer formalization of C-172.

**Status:** APPROVED

## LDM-161 — Member Exit

Historical Activity remains after Member exit/removal; historical authorship remains associated with the occurrence. This does not grant the ex-Member any residual right over the Collection. Future account deletion/anonymization questions are out of scope. Logical-layer formalization of C-173.

**Status:** APPROVED

## LDM-162 — Privacy

Activity does not automatically expose amount paid, seller/buyer, financial data, Storage, private Provenance, Favorite, Wishlist, or other private data. The user-facing narrative contains only information necessary to understand the change in the Collection. Logical-layer formalization of C-174.

**Status:** APPROVED

## LDM-163 — Audit (Definition)

Audit Log is a separate layer for governance, security, accountability, investigation, and support. It must conceptually allow reconstructing who did what, when, over which context/entity. Physical schema not fixed at this round. Logical-layer formalization of C-175.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

## LDM-164 — Audit Coverage

Coverage proportional to risk and accountability need. Mandatory conceptual priority for: (A) Owner-sensitive actions — Membership, Visibility, Collection Allocation, Archive/Delete, other sensitive actions; (B) state-changing actions performed by Collaborators — Layout, Expected Content, Slot Assignment, editable metadata. Motivation: Owner must be able to future answer "who changed what in my Collection?". This does not mean auditing every technical mutation or UI interaction. Logical-layer formalization of C-176.

**Status:** APPROVED

## LDM-165 — Activity × Audit

Four possibilities recognized: Activity + Audit; Audit-only; Activity-only; neither. Exhaustive matrix not closed at this round. Example: Visibility PRIVATE → PUBLIC generates Activity + Audit; a security-relevant denied attempt/error generates Audit-only. Logical-layer formalization of C-177.

**Status:** APPROVED

## LDM-166 — Bulk / Grouping

Activity must conceptually support bulk operations without forcing a noisy history (e.g., preferring "7 Slots removed" over seven identical lines). Not decided whether the implementation will be an aggregated event, individually recorded events grouped at presentation, or both — future detail. Logical-layer formalization of C-178.

**Status:** APPROVED

## LDM-167 — Immutability

While they exist, historical records are not editable, silently rewritten, or freely deletable by regular Users. Retention and hard-delete policy are out of scope at this round. Logical-layer formalization of C-179.

**Status:** APPROVED

## LDM-168 — Retention

Activity History and Audit may have different retention policies. TTL/deadlines not defined at this round. Logical-layer formalization of C-180.

**Status:** APPROVED

## LDM-169 — Archive / Delete

Do not assume Activity, Audit, and Physical Card Lifecycle share the same lifecycle. Physical Card Lifecycle remains independent of the Collection (reaffirms LDM-23/LDM-55). The fate of Activity/Audit after Collection archive/hard-delete remains open. Logical-layer formalization of C-181.

**Status:** APPROVED

## LDM-170 — History ≠ Undo

History does not imply Undo, Restore, or automatic rollback. Reversibility requires its own future modeling. Logical-layer formalization of C-182.

**Status:** APPROVED

## LDM-171 — History ≠ Current State

Activity History and Audit are not the mandatory single source for reconstructing current state at V1. Event sourcing is not implicitly adopted. Current state remains modeled by the domain entities. Logical-layer formalization of C-183.

**Status:** APPROVED

## LDM-172 — System Activity

System may be an Activity actor when there is a semantically relevant occurrence to the user. Technical logs are not automatically transformed into Activity. Logical-layer formalization of C-184.

**Status:** APPROVED

## LDM-173 — Activity ≠ Lifecycle

Physical Card Lifecycle facts are not automatically duplicated. Ownership Entry/Transfer/Exit continue belonging to the lifecycle (LDM-55–LDM-69, not reopened). If a patrimonial fact also has explicit relevance to a Collection, a corresponding Activity may future exist, but the concepts remain independent. Logical-layer formalization of C-185.

**Status:** APPROVED

## LDM-174 — V1 Minimum Scope

**ACTIVITY HISTORY:** Collection-scoped; user-facing; domain language; actor when applicable; timestamp; relevant changes/occurrences; visible to Owner + Members; not public by default; no Undo; not a source of current state; does not replace Lifecycle. **AUDIT:** separate layer; security/governance/accountability; covers Owner-sensitive actions; covers relevant changes made by Collaborators; not necessarily user-facing; does not replace Activity/Lifecycle; not a source of current state. Logical-layer formalization of C-186.

**Status:** APPROVED (decisão lógica, sem skeleton físico)

---

## Bloco complementar — Pokédex / REFERENCE_POSITION (2026-09-03, `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`)

> Encerra a subfrente conceitual `Collections — Pokédex / REFERENCE_POSITION modeling`, iniciada em `COLLECTIONS-POKEDEX-MODELING-AUDIT-01` e reconciliada em `COLLECTIONS-POKEDEX-MODELING-RECONCILIATION-01` (auditoria read-only, não editada em disco). Estado: **POKÉDEX MODELING — CONCEPTUALLY CLOSED. PHYSICAL MODELING — NOT STARTED.** LDM-175 a LDM-185 abaixo formalizam as decisões conceituais; LDM-16 e a cláusula Pokédex de LDM-17 são supersedidas (ver anotações nos próprios itens, acima) — texto original preservado por rastreabilidade.

## LDM-175 — Pokémon Species, Generation, Pokémon Form/Variety

Três conceitos distintos, onde antes só existia "Pokémon" (ADR-011, LDM-13 a LDM-19 originais):

- **Pokémon Species** — identidade canônica de completion. Possui exatamente uma **Introduction Generation** (a geração de jogos em que a espécie foi introduzida).
- **Generation** — entidade própria, referenciada por exatamente uma Species como sua Generation de introdução.
- **Pokémon Form / Variety** — subordinada a uma Species; não cria uma nova Position por padrão; não altera completion por padrão (ver LDM-176).

Todo uso anterior de "Pokémon"/`pokemon_id` neste documento, quando referente à identidade de completion (LDM-16 a LDM-19), passa a se ler como **Pokémon Species**/`species_id` a partir desta data — nomenclatura apenas, nenhuma cardinalidade ou campo alterado por este motivo isoladamente (mesma disciplina já aplicada à convergência `Physical Card`, LDM revisão 1.3). Formaliza no nível lógico a revogação do adiamento de ADR-011 (ver emenda v1.2 do ADR).

**Status:** APPROVED

## LDM-176 — Pokédex Position References Exactly One Species

```text
Pokédex
└── Pokédex Position
    ├── id
    ├── species_id → exactly one Pokémon Species
    └── position_number
```

Uma Position nunca referencia uma Form/Variety diretamente — apenas a Species. Uma Card cuja Primary Species resolvida corresponda a uma Form/Variety específica (ex.: Mega, forma regional) ainda satisfaz a Position da Species-base, porque Form não gera identidade de completion própria (LDM-175).

**Status:** APPROVED

## LDM-177 — Collection Pokédex Scope (SUPERSEDE de LDM-16)

```text
Collection Pokédex Scope
├── FULL_REFERENCE (padrão)
│   └── todas as Positions da Pokédex referenciada
└── GENERATION_FILTERED (opcional)
    └── 1..N Generations selecionadas
        └── Positions cuja Species pertence a alguma das Generations selecionadas
```

Positions adotadas são **derivadas** do Scope declarado (`FULL_REFERENCE` ou `GENERATION_FILTERED` + conjunto de Generations) — não existe seleção individual de Position como verdade primária do Scope V1 (o modelo de LDM-16, `Collection Pokédex Scope` por linha `pokedex_position_id` adotada uma a uma, é substituído integralmente por este mecanismo).

Scope mutation (troca de `FULL_REFERENCE`↔`GENERATION_FILTERED`, ou troca do conjunto de Generations selecionadas):
- recalcula completion (denominador/numerador, ver LDM-181);
- **não remove** Physical Cards;
- **não remove** Collection Allocations;
- **não remove** Pokédex Position Assignments (LDM-179).

Um Position Assignment que caia fora do Scope corrente após uma mutação: permanece **permitido**, **preservado**, e **não participa do progress atual** — mesmo padrão já usado por `Collection Master Set Scope` (LDM-21/C-23, confirmado fisicamente em `COLLECTIONS-PHYSICAL-INCREMENT-02F`).

**Status:** APPROVED — supersede LDM-16 integralmente.

## LDM-178 — Species Match / Mismatch (SUPERSEDE da cláusula Pokédex de LDM-17)

Duas trilhas para associar uma Physical Card a uma Pokédex Position:

- **Species Match** — a Primary Species resolvida da Card (LDM-18/LDM-182) corresponde exatamente à Species da Position. `assignment_basis = SPECIES_MATCH`. Sem warning, sem confirmação adicional. **Materialização física (Fatia D, 2026-09-06, Query `6119`):** quando o match é *inequívoco*, a Assignment é criada **automaticamente** logo após a Allocation (trigger `AFTER INSERT` em `collection_allocation`), com `assigned_by_user_id = NULL` — ver LDM-179, "Dois caminhos válidos". O mesmo `assignment_basis = SPECIES_MATCH` também é alcançável pelo caminho manual/RPC (Query `6122`) quando a automação não ocorreu.
- **Mismatch, Primary Species ausente, ou Card de categoria Trainer/Energy** — associação manual à Position ainda é permitida, mas o sistema emite **warning** e exige **confirmação explícita do usuário**. Uma vez confirmada, `assignment_basis = USER_OVERRIDE`.

Incompatibilidade semântica **nunca** é bloqueio duro (`hard block`) — apenas aviso + confirmação. `USER_OVERRIDE` é Collection-local (ver LDM-179/C-referência de Collection) e **nunca** altera o Catálogo Editorial (Card, Card Variant, ou qualquer dado de Species/Pokédex canônico).

**Status:** APPROVED — supersede a cláusula Pokédex de LDM-17 (cláusulas Open Curation e Card Set de LDM-17 não afetadas).

## LDM-179 — Pokédex Position Assignment (novo conceito lógico)

```text
Pokédex Position Assignment
├── pokedex_position_id
├── physical_card_id
├── assignment_basis (SPECIES_MATCH | USER_OVERRIDE)
├── assigned_at
└── assigned_by_user_id
```

Nomes de campo acima são conceito lógico, não nome físico definitivo. *(Nota de estado, 2026-09-06: a modelagem física **foi executada** na Fatia D — tabela `collection_pokedex_position_assignment`, Queries `6117`–`6126` —, com PK/FK compartilhada em `collection_allocation_id`. O parágrafo original descrevia a frente como futura e é preservado como registro histórico.)*

Regras:
- a Physical Card precisa estar **alocada** à Collection (Collection Allocation) antes de qualquer Assignment;
- **Allocation sozinha não satisfaz uma Position** — um **Assignment explícito é obrigatório** (distingue `REFERENCE_POSITION` do modelo de `STANDARD_SET`/`MASTER_SET`, que continuam satisfeitos apenas por Allocation — LDM-19 nota acima, sem alteração naquelas duas políticas). **Desambiguação formal (2026-09-06, `COLLECTIONS-POKEDEX-AUTO-ASSIGNMENT-DOC-RECONCILIATION-01`):** "Assignment explícito" significa que **uma linha materializada própria de Position Assignment precisa existir** para a Position ser satisfeita — a relação nunca é inferida da Allocation nem derivada em tempo de leitura. **NÃO significa** que essa linha precise ser criada manualmente pelo usuário. Dois caminhos produzem a linha e ambos são válidos:
  - **A — SYSTEM `SPECIES_MATCH`.** Allocation + match de Species inequívoco → a Assignment é criada **automaticamente** pelo domínio (Fatia D, Query `6119`), com `assignment_basis = SPECIES_MATCH` e `assigned_by_user_id = NULL`, sem confirmação humana. A automação **não filtra por Scope corrente** (LDM-177) e **não** cria nada quando o match não é inequívoco — sem erro, sem `USER_OVERRIDE`.
  - **B — USER-DRIVEN.** Assignment criada pelo fluxo explícito/RPC (Query `6122`): `SPECIES_MATCH` quando a Species corresponde e a automação não havia ocorrido; `USER_OVERRIDE` **somente** após confirmação humana explícita em caso de mismatch (LDM-178). `USER_OVERRIDE` **nunca** é automático.
  Em ambos os caminhos, completion (LDM-181) consulta exclusivamente a **Assignment** — nunca a Allocation;
- uma Position pode ter **múltiplos** Assignments (múltiplas Physical Cards representando a mesma Position);
- uma Physical Card pode representar **no máximo uma** Position dentro da mesma Collection Pokédex;
- um Assignment pode existir **fora do Scope** corrente — permanece preservado, não conta para o progress atual (ver LDM-177);
- remover a Physical Card da Collection, ou realocá-la para fora dela, **remove o Assignment operacional** correspondente;
- o histórico de Assignments criados/removidos fica a cargo de Collection Activity History / Audit (LDM-154 a LDM-174, não reabertas) — nenhuma entidade de histórico própria é introduzida aqui.

**Status:** ADD — conceito lógico novo, sem skeleton físico.

## LDM-180 — Primary Representative (Pokédex Position)

Uma Position com um ou mais Assignments pode ter, opcionalmente, no máximo **uma** Physical Card marcada como Primary Representative — escolha do usuário, sem obrigatoriedade. Afeta somente **apresentação** (qual exemplar é mostrado como "a carta" daquela Position numa tela) — não afeta numerator/completion (ver LDM-181) e não é criada implicitamente pela existência de Assignments.

Não confundir com `Slot Assignment` do Binder/Layout (LDM-35) — são conceitos ortogonais: Primary Representative é sobre qual Physical Card representa uma Pokédex Position; Slot Assignment é sobre qual Physical Card ocupa um Slot físico de página.

**Status:** ADD — conceito lógico novo, sem skeleton físico.

## LDM-181 — REFERENCE_POSITION Completion (REVISE da Seção 5)

Para `completion_policy = REFERENCE_POSITION`:

- **Denominator** = Pokédex Positions distintas adotadas pelo Scope corrente (LDM-177).
- **Numerator** = Positions adotadas distintas com **≥ 1 Pokédex Position Assignment** (LDM-179) — Allocation sem Assignment **não** satisfaz a Position.
- Duplicatas (múltiplas Physical Cards satisfazendo a mesma Position) **não inflam** o progress — mesmo princípio de `DISTINCT` já provado fisicamente para `STANDARD_SET` (Query `5070`, 02E).
- `USER_OVERRIDE` (LDM-178) satisfaz a Position **normalmente** para fins de completion — nenhuma penalidade ou tratamento distinto do `SPECIES_MATCH`.
- Primary Representative (LDM-180) é **irrelevante** para completion — dimensão puramente de apresentação.

Isto revisa a linha `REFERENCE_POSITION` da Seção 5 (Completion Model Summary) e a nota adicionada a LDM-19 acima — sem alterar `NONE`/`STANDARD_SET`/`MASTER_SET`.

**Status:** APPROVED — revisa a leitura da Seção 5 para `REFERENCE_POSITION`.

## LDM-182 — Card Primary Species: Sourcing Estrutural

A decisão central de LDM-18 (Card categoria Pokémon possui no máximo uma Species principal para elegibilidade automática) permanece inalterada. O que se formaliza aqui é a fonte de evidência:

- `dexId` único e estruturado, retornado pela TCGdex para uma Card, é evidência estruturada suficiente para resolução automática da Primary Species (`assignment_basis = SPECIES_MATCH` candidato).
- `dexId` múltiplo (mais de um elemento no array) ou ausente exige **reconciliação editorial** — nunca resolução automática silenciosa.
- `card.name` (texto livre, localizado) **nunca** é fonte canônica por parsing — confirmado empiricamente (`COLLECTIONS-POKEDEX-TCGDEX-DEXID-PROOF-01`): Pokémon Paradoxo com nome PT sem relação lexical com a espécie-base, formas Mega/regionais/históricas sem campo estruturado equivalente no `name`.
- Pokémon incidental em artwork não gera elegibilidade automática (LDM-18, inalterado). N:N Card↔Pokémon Species para completion continua rejeitado (Seção 6, item 6, inalterado).

**Status:** ADD — formaliza sourcing sem reabrir LDM-18.

## LDM-183 — Modelo de Sourcing (PokéAPI + TCGdex + MMKYU Editorial Reconciliation)

```text
PokéAPI          → Species, Generation, Pokédex, Pokédex Position, Form/Variety relationships
TCGdex            → Card, dexId (já integrada ao pipeline do MMKYU — ADR-008/ADR-024)
MMKYU Editorial Reconciliation → resolve gaps/ambiguidades (dexId múltiplo/ausente — LDM-182)
MMKYU canonical catalog        → runtime authority
```

Nenhuma API externa é dependência estrutural em tempo real — mesmo princípio já estabelecido por ADR-008 para o Catálogo Editorial em geral, agora estendido a Species/Generation/Pokédex/Pokédex Position. Completion nunca depende de API externa em runtime.

**Editorial Reconciliation ≠ USER_OVERRIDE**: Editorial Reconciliation é uma correção/decisão sobre o dado do Catálogo Editorial (ex.: qual `dexId` é a Species correta para uma Card com `dexId` múltiplo) — afeta o Catálogo, visível a todas as Collections. `USER_OVERRIDE` (LDM-178) é uma decisão Collection-local de um usuário associando manualmente uma Card a uma Position — nunca altera o Catálogo Editorial. São mecanismos independentes, ainda que ambos lidem com incerteza de Species.

**Status:** ADD — conceitual, sem alteração de pipeline de importação nesta rodada.

## LDM-184 — Correção Editorial Posterior não Remove Assignment

Se a Primary Species de uma Card for corrigida (Editorial Reconciliation, LDM-183) depois de já existir um Pokédex Position Assignment baseado na resolução anterior:

- o Assignment existente **não é removido automaticamente**;
- o completion da Collection **não é invalidado automaticamente**;
- a escolha do usuário é preservada;
- a associação pode, no futuro, ser sinalizada como semanticamente divergente (mecanismo de sinalização não desenhado nesta rodada — apenas o princípio de não-remoção/não-invalidação automática é fixado agora).

Mesma disciplina de não-destruição silenciosa já aplicada a mutações de Scope (LDM-177) e a mudanças de `completion_policy` em geral (C-23/LDM-22).

**Status:** ADD.

## LDM-185 — ARCHIVED aplica-se a Collection Pokédex

Confirma, para Collection com `completion_policy = REFERENCE_POSITION`, o mesmo princípio geral já estabelecido para Collection em qualquer política de completion: uma Collection `ARCHIVED` permanece consultável; seu completion derivado continua computável normalmente; Scope (LDM-177), Assignments (LDM-179) e Primary Representative (LDM-180) tornam-se **imutáveis** enquanto `ARCHIVED`. Nenhuma decisão nova — apenas confirmação de aplicabilidade transversal.

**Status:** APPROVED — confirmação, não nova decisão.

---

## LDM-186 a LDM-190 — Pokémon Region (bloco complementar, 2026-09-04)

> Contexto: `POKEMON-REGION-DOMAIN-MODELING-AUDIT-01` (auditoria read-only direta da PokéAPI, `/region/`, 11 regiões — kanto/johto/hoenn/sinnoh/unova/kalos/alola/galar/hisui/paldea/orre, ids 1-11) → `POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01` (modelagem física, read-only) → staging/revisão/implementação/promoção física (`POKEMON-REGION-FOUNDATION-PHYSICAL-STAGING-01`/`-REVISION-01`/`-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`, todas 2026-09-04). Bloco inteiramente **aditivo** — não reabre nem altera LDM-175 a LDM-185.

### LDM-186 — Pokémon Region é entidade canônica própria

Region (ex.: Kanto, Johto, Hoenn) é modelada como entidade-raiz de catálogo própria, nunca como concatenação `TEXT` derivada de Generation. Confirmado empiricamente: existem Regiões sem nenhuma Generation principal associada (`main_generation: null` para Orre e Hisui na PokéAPI) — a existência de Region não depende da existência de uma Generation correspondente. **Status:** ADD.

### LDM-187 — Cardinalidade Generation ↔ Region é N:1 (Main Region)

Cada Pokémon Generation tem exatamente uma Main Region (`pokemon_generation.main_region_id`, `NOT NULL`); uma Region pode ser Main Region de 0..N Generations. A unicidade reversa observada no dataset atual da PokéAPI (aparentemente 1:1) **não é invariante de domínio** — é padrão observado, não regra imposta. Por isso, deliberadamente: nenhum `UNIQUE` em `main_region_id`; Region pode existir sem nenhuma Generation apontando para ela (Region → Generation é 0..N, nunca 1..N). **Status:** ADD.

### LDM-188 — Pokémon Region External Reference é a identidade externa da Region

Mesmo padrão de evidência-de-integração já usado por `pokemon_species_external_reference`/`pokedex_external_reference`: nenhuma coluna `pokeapi_id` solta na entidade canônica `pokemon_region` — o identificador externo (o id numérico estável do recurso `/region/{id}` da PokéAPI, nunca o slug/name roteável) mora exclusivamente em `pokemon_region_external_reference`, por Fonte (`asset_source`). **Status:** ADD.

### LDM-189 — Sourcing futuro de `canonical_name`; `main_generation` não duplicado em Region

Fonte esperada de `pokemon_region.canonical_name` no sourcing futuro (ainda SUSPENSO): `names[language=en].name` da PokéAPI, nunca o slug roteável — mesmo princípio já aplicado a Species/Pokédex. `main_generation` (a geração historicamente associada a uma Region, quando existe) não é duplicado como coluna em `pokemon_region` — é sempre a relação inversa derivada de `pokemon_generation.main_region_id`, nunca um dado armazenado redundantemente na Region. **Status:** ADD.

### LDM-190 — Escopo físico desta rodada e estado real

Nenhum índice dedicado em `main_region_id` nesta rodada — decisão proporcional ao volume esperado (dezenas de linhas em `pokemon_generation`), mesmo raciocínio já aplicado a `pokemon_generation`/`pokedex`; reconhecido pelo Performance Advisor como `unindexed_foreign_keys` INFO, aceito por decisão explícita. Locations, Areas, Version Groups e o grafo de navegação entre Regiões permanecem explicitamente fora de escopo (`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01`). Sourcing real (carga via PokéAPI) permanece **SUSPENSO**; `pokemon_region`, `pokemon_region_external_reference` e `pokemon_generation` seguem com zero linhas após esta rodada — apenas estrutura física, nenhum dado. **Status:** ADD.

**Aplicação física:** `pokemon_region`/triggers (Queries `6060`/`6061`), `pokemon_region_external_reference`/triggers (Queries `6070`/`6071`) e `pokemon_generation.main_region_id` (Query `6080`, FK `ON UPDATE RESTRICT ON DELETE RESTRICT` explícitos) — **CONFIRMADO EXECUTADO em 2026-09-04**, promovidas para `database/schema/`. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Collection Pokédex Reference / REFERENCE_POSITION", para o resumo físico narrativo.

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
        └── Adopted Scope (LDM-177 — FULL_REFERENCE | GENERATION_FILTERED)
            └── Pokédex Positions (derivadas do Scope, não selecionadas individualmente)
                └── Pokédex Position Assignment (0..N — LDM-179)
                    └── Primary Representative (0..1 — LDM-180)

Physical Card
├── Inventory (0..1 — current tracked ownership; ver LDM-23)
├── Card Variant
│   └── Card
│       ├── Card Set
│       └── Pokémon Species (when category = POKEMON; ver LDM-175)
├── Collection (0..1)
├── Storage Container (0..1)
└── Pokédex Position Assignment (0..1 por Collection Pokédex — LDM-179)

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
>
> Nota (2026-08-30): Lifecycle/Provenance (LDM-55 a LDM-69) não aparece na árvore acima — Ownership Entry/Transfer/Exit são fatos históricos sobre a transição de `inventory_id` (LDM-23), não uma relação estrutural nova de Physical Card. Nenhum skeleton de evento, Ownership Episode ou Acquisition é fixado nesta rodada.
>
> Nota (2026-08-30): Favorite (LDM-70 a LDM-78) não aparece na árvore acima porque não é uma relação de `Physical Card` — referencia diretamente `Card` (nível editorial, acima de `Card Variant`) a partir do `User`, nunca a partir de `Inventory`, `Collection` ou `Storage Container`. Nenhum skeleton (tabela, campo, enum) de Favorite é fixado nesta rodada.
>
> Nota (2026-08-30): Wishlist (LDM-79 a LDM-90) também não aparece na árvore acima — referencia `Card Variant` (não `Physical Card`) a partir do `User`, nunca a partir de `Inventory`, `Collection` ou `Storage Container`. Diferente de Favorite (que referencia `Card`), Wishlist referencia `Card Variant` diretamente, mesmo nível de especificidade de `Physical Card` — mas continua sendo intenção sobre o catálogo, não sobre um exemplar físico existente. Nenhum skeleton de Wishlist é fixado nesta rodada.
>
> Nota (2026-08-30): `Physical Card Condition` (LDM-91 a LDM-108) também não aparece na árvore acima — é uma dimensão lógica de `Physical Card`, ortogonal a Inventory/Storage/Collection/Layout, referenciando a escala canônica compartilhada `card_condition` (já existente em Pricing, não exclusiva dele). Mesmo padrão de `Custody`/`Availability` (LDM-38 a LDM-43): dimensão reconhecida, sem entrar na árvore estrutural. Nenhum skeleton (campo `condition_id` ou equivalente em Physical Card) é fixado nesta rodada.
>
> Nota (2026-08-30): `Grading`/`Certification` (LDM-109 a LDM-128) também não aparece na árvore acima — mesmo padrão de `Physical Card Condition`: dimensão lógica de `Physical Card`, ortogonal a Inventory/Storage/Collection/Layout, sem skeleton (campo `current_certification_id` ou equivalente) fixado nesta rodada. Diferente de Condition, não há referência a uma tabela física preexistente — Grading Company/Grade Scale/Grade/Certification partem de base puramente conceitual. Current Condition e Current Certification são mutuamente exclusivas quanto à aplicabilidade corrente (LDM-117), mas essa exclusividade é regra de aplicabilidade, não uma relação estrutural nova representada na árvore.
>
> Nota (2026-08-30): `Owner` e `Members`, na árvore acima, deixam de ser tratados como a mesma relação — `Owner` (LDM-129) é relação estrutural própria `Collection → User`, fora de Collection Membership; `Members` (LDM-130 a LDM-153) representa exclusivamente Users não-owner, 0..N, com role EDITOR ou VIEWER. Nenhum skeleton físico (tabela de Membership, enum de role) é fixado nesta rodada — ver bloco complementar `Collection Collaboration / Permissions` acima e `concept-decisions.md` C-141–C-165.
>
> Nota (2026-08-30): `Collection Activity History` e `Audit Log` (LDM-154 a LDM-174) não aparecem na árvore acima — não são relações estruturais de `Physical Card` nem de `Collection`, mas camadas transversais que registram/narram acontecimentos sobre as entidades já representadas na árvore. `Physical Card Lifecycle/Provenance` (LDM-55 a LDM-69) permanece a terceira camada, já reconhecida acima, sem sobreposição com as duas novas. Nenhum skeleton (tabela, campo, enum) de Activity History ou Audit é fixado nesta rodada.

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
18. Seleção individual de Pokédex Position como verdade primária do Scope V1 (modelo original de LDM-16) — substituída por Scope declarado (`FULL_REFERENCE`/`GENERATION_FILTERED`) com Positions derivadas (LDM-177).
19. Bloqueio duro (`hard block`) de associação Card↔Pokédex Position por incompatibilidade semântica (cláusula Pokédex original de LDM-17) — substituído por warning + confirmação explícita do usuário (`USER_OVERRIDE`), nunca bloqueio (LDM-178).

> Adendo (2026-08-28): também não implementar `owner_user_id` direto em Physical Card, nem qualquer fluxo de aprovação patrimonial fundamentado em "Collection compartilhada com itens de múltiplos owners" — ver `checkpoint-2026-08-28.md` e LDM-23 (revisada, 2026-08-30).
>
> Adendo (2026-08-30): ver `checkpoint-2026-08-30.md` para o diagnóstico completo de reconciliação da frente Collection Layout, incluindo a supersessão terminológica do item 14 acima.
>
> Adendo (2026-08-30): terminologia deste documento convergida de `Collection Item`/`Inventory Item` para `Physical Card` em todo texto normativo vigente — ver banner no topo do documento e `concept-decisions.md` C-47/C-48. Itens desta lista que citam terminologia histórica de outros documentos (ex.: item 14 acima, sobre `ux-exploration-2026-08-29.md`) preservam a citação e apenas anotam a atualização, sem reescrever a fonte citada.
>
> Adendo (2026-09-03, `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`): itens 18 e 19 encerram a subfrente conceitual Pokédex/`REFERENCE_POSITION` — ver bloco complementar LDM-175 a LDM-185, acima. Itens 6 e 7 (N:N Card↔Pokémon e artwork incidental) permanecem vigentes, não reabertos — as premissas desta rodada os reconfirmam, não os contradizem.

---

# 7. Dependencies Identified for Other Domains

## Canonical Catalog
- Card
- Card Variant
- Card Set
- Pokémon Species (nomenclatura atualizada 2026-09-03 — ver LDM-175; antes apenas "Pokemon")
- Generation
- Pokémon Form / Variety
- Pokédex
- Pokédex Position

Invariant: every Card classified as Pokémon identifies exactly one principal canonical Pokémon Species.

## Pokédex / REFERENCE_POSITION (Atualização 2026-09-03 — conceitualmente resolvido, ver LDM-175 a LDM-185)
Espécie (Pokémon Species) como identidade de completion, com exatamente uma Generation de introdução; Form/Variety subordinada à Species, sem gerar Position ou alterar completion por padrão (LDM-175); Pokédex Position referenciando exatamente uma Species (LDM-176); Collection Pokédex Scope reformulado de seleção individual de Position para Scope declarado com Positions derivadas — `FULL_REFERENCE` (padrão) ou `GENERATION_FILTERED` (1..N Generations) —, preservando Physical Cards/Allocations/Position Assignments em qualquer mutação (LDM-177, supersede LDM-16); elegibilidade Pokédex sem bloqueio duro — Species Match sem aviso, Mismatch/Species ausente/Trainer-Energy com aviso e confirmação explícita (`USER_OVERRIDE`) (LDM-178, supersede a cláusula Pokédex de LDM-17); Pokédex Position Assignment como conceito lógico explícito, distinto de Collection Allocation (LDM-179); Primary Representative opcional, só apresentação (LDM-180); completion revisada — denominador por Positions adotadas, numerador por Positions com Assignment, nunca só Allocation (LDM-181); sourcing conceitual de Primary Species via `dexId` estruturado da TCGdex, com reconciliação editorial obrigatória para múltiplo/ausente, nunca parsing de `card.name` (LDM-182); modelo de sourcing PokéAPI + TCGdex + MMKYU Editorial Reconciliation, catálogo MMKYU como runtime authority, sem dependência de API externa em runtime, Editorial Reconciliation distinta de `USER_OVERRIDE` (LDM-183); correção editorial posterior não remove Assignment nem invalida completion automaticamente (LDM-184); ARCHIVED confirmado aplicável (LDM-185). Formaliza no nível lógico a revogação do adiamento de ADR-011 (emenda v1.2). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: qualquer skeleton físico (tabela, coluna, enum) de Pokémon Species/Generation/Form/Pokédex/Pokédex Position/Collection Pokédex Scope/Pokédex Position Assignment/Primary Representative; pipeline de ingestão PokéAPI/TCGdex; mecanismo de sinalização de divergência semântica pós-correção editorial (LDM-184); UX/telas de confirmação de `USER_OVERRIDE`.

## Inventory
Physical Card requires its own detailed model beyond the Collection-allocation decisions captured here. **Atualização 2026-08-28**: o próprio conceito de `Inventory` (Acervo) como aggregate 1:1 por usuário, dono real de toda `Physical Card` sob ownership corrente, foi introduzido nesta data — ver `checkpoint-2026-08-28.md`. **Atualização 2026-08-30**: a regra de cardinalidade corrente (`Physical Card` participa de no máximo um `Inventory` por vez, podendo não ter nenhum quando fora do escopo rastreado) foi formalizada em LDM-23 (revisada) e C-48 — deixa de existir apenas em nível de checkpoint/memo.

## Storage (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-44 a LDM-54)
Ownership, hierarquia, cardinalidade, capacidade, remoção e as duas operações de transferência (Bulk Card Transfer, Reparent) foram formalizadas em LDM-44 a LDM-54 (`concept-decisions.md` C-55–C-66). Storage cross-Inventory foi fechado como **não suportado** (LDM-49/C-61) — Custody cobre os cenários de empréstimo/grading/guarda por terceiro. Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico de Storage Container (id, inventory_id, parent_id — nenhum fixado); Protection/Encapsulation como dimensão própria (LDM-44/C-56, apenas reconhecida, não modelada); histórico de Storage ("last known storage", LDM-47/C-59); fórmula/mecânica de capacidade, inclusive capacidade agregada sob hierarquia; Product Behavior detalhado de remoção, Bulk Card Transfer e Reparent (fluxo, confirmação, tratamento de erro parcial).

## Custody / Availability (Atualização 2026-08-30)
Reconhecidas como dimensões lógicas distintas de Inventory (ownership), Storage (localização) e Collection/Layout (organização colecionável) — ver LDM-38 a LDM-43 e `concept-decisions.md` C-49–C-54. Nenhum skeleton físico, enum ou entidade `Custodian` foi fixado nesta rodada. Dependências não resolvidas: estrutura física de Custody; enum de Availability; entidade Custodian; fluxo de empréstimo completo; fluxo de grading.

## Lifecycle / Provenance (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-55 a LDM-69)
Espinha dorsal patrimonial (Ownership Entry/Transfer/Exit, motivo como atributo, Ownership Episode como ferramenta conceitual) e fronteira Physical Card Provenance × Owner/Transaction Private Data formalizadas em LDM-55 a LDM-69 (`concept-decisions.md` C-67–C-81). Núcleo V1 confirmado: Entry/Transfer/Exit automáticos, sem histórico de Loan/LOST/Grading. Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico de qualquer evento de lifecycle; entidade Ownership Episode (mantida como ferramenta conceitual, não entidade); modelo de permissão para separar Provenance de Private Data; evidence levels; workflow de grading; histórico de Loan/LOST/Recovery; histórico detalhado de condition; Pricing/Valuation (não reabertos).

## Favorite (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-70 a LDM-78)
Definição, entidade-alvo (`Card`, nunca `Card Variant`/`Physical Card`), pertencimento ao `User` transversal a Collections, independência de ownership e de Collection, caráter binário, cardinalidade conceitual e fronteira com Wishlist formalizados em LDM-70 a LDM-78 (`concept-decisions.md` C-82–C-90). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico da relação User↔Favorite↔Card; Wishlist em profundidade; camada `Pokémon`/`Subject Reference`; ranking/grail como conceito de produto; consumo futuro por filtros/dashboards/recomendações/compartilhamento.

## Wishlist (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-79 a LDM-90)
Definição, alvo obrigatório `Card Variant` (não `Card`), idioma como refinamento opcional, independência de ownership/completion/Expected Content/Favorite, núcleo binário V1, cardinalidade/duplicidade conceitual, e fronteiras futuras (condition/grading, Marketplace) formalizados em LDM-79 a LDM-90 (`concept-decisions.md` C-91–C-102). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico da relação User↔Wishlist↔Card Variant(+idioma); quantity/priority/price target como extensões futuras; mecanismo de consumo por Marketplace; modelagem própria de `condition` (encaminhada para futura subfrente `Collections — Physical Card Condition Modeling`) e de Grading em detalhe.

## Physical Card Condition (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-91 a LDM-108)
Definição e entidade-alvo exclusivo `Physical Card`, ratificação conceitual da referência canônica compartilhada `card_condition` (já `CONFIRMADO EXECUTADO` em Pricing, Incremento P1, sem alteração de schema), escala formalizada (MINT/NEAR_MINT/LIGHTLY_PLAYED/MODERATELY_PLAYED/HEAVILY_PLAYED/DAMAGED), code canônico independente de idioma vs. label localizado, evidência de convergência de mercado brasileiro, opcionalidade, classificação declarada/não certificada, fronteira com Damage/Defects (fora do núcleo V1) e com Grading (coexistência sem derivação automática — aplicabilidade a cards graded deferida para futura subfrente `Grading / Certification Domain Modeling`), independência de identidade/idioma/Storage/Custody/Wishlist, relação futura com Valuation sem reabrir Pricing, e semântica de filtro ("NM ou superior") apoiada em `condition_order` sem novo valor de escala — formalizados em LDM-91 a LDM-108 (`concept-decisions.md` C-103–C-120). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico da referência Physical Card → `card_condition`; verificação da discrepância entre "5 linhas" (validação) e 6 códigos documentados; Grading/Certification em detalhe; Damage/Defects detalhados; Condition History; mecanismo/UX de filtro por ordenação; refinamento de Wishlist por Condition.

## Grading / Certification (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-109 a LDM-128)
Separação Grading (workflow, fora do V1) vs. Certification (resultado formal, modelada); entidade-alvo exclusivo `Physical Card`; Grading Company como Reference Data (nome, código/sigla, status ativo/inativo); Grade Scale (sem assumir equivalência entre companies, cardinalidade não fixada); Grade (valor e/ou designação, sem enum físico); Certification Number opcional, sem conceito separado de "Grading Declaration"; no máximo uma Current Certification por Physical Card (0..1); raw/graded como predicado derivado da existência de Current Certification; **fechamento definitivo da aplicabilidade simultânea Condition × Certification** (mutuamente exclusivas quanto à corrente, sem fusão/substituição/derivação entre os dois valores — fecha a pendência deixada aberta por LDM-99/LDM-100); Condition History fora do V1; efeitos de crack (Current Condition volta a ser aplicável, sem restauração automática de valor anterior) e regrade (identidade preservada, sem canonizar workflow temporal); Grade ≠ Condition sem de-para automático; Certification como dado declarado/registrado, não verificado; subgrades/qualifiers fora do núcleo V1; fronteiras com Protection/Encapsulation, Custody/Storage e Valuation; Wishlist inalterada — formalizados em LDM-109 a LDM-128 (`concept-decisions.md` C-121–C-140). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico de Grading Company/Grade Scale/Grade/Certification; tipo de dado exato de Grade (valor+designação); cardinalidade de Grade Scale por Grading Company; taxonomia de status detalhado de Certification além de current/ausente; verificação externa de Certification Number; refinamento de Wishlist por Certification; modelagem própria de Protection/Encapsulation.

## Permissions (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-129 a LDM-153)
Collection Owner formalizado como relação estrutural própria (`Collection → User`), fora de Collection Membership; Collection Membership restrita a Users não-owner (0..N), com roles V1 limitadas a EDITOR e VIEWER; fronteira Collection-scoped (Layout, Expected Content, Slot Assignment de cartas já alocadas, metadata comum — Editor-capable) vs. Owner-authorized Collection operation (Collection Allocation e demais operações Owner/Inventory-scoped); Public Access formalizado como consequência de Visibility, distinto de Membership e da role VIEWER; privacidade por padrão de Storage/Provenance/Favorite/Wishlist/dados financeiros; Condition/Certification legíveis para curadoria, não editáveis por Collaborator — formalizados em LDM-129 a LDM-153 (`concept-decisions.md` C-141–C-165). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: skeleton físico de Membership (tabela, enum de role); granularidade de capability assignments além de EDITOR/VIEWER; transferência de Collection ownership; mecanismo de private sharing link; Audit Log.

## Collection Activity History / Audit (Atualização 2026-08-30 — conceitualmente resolvido, ver LDM-154 a LDM-174)
Três camadas conceitualmente distintas formalizadas — `Physical Card Lifecycle/Provenance` (não reaberto), `Collection Activity History` (novo: sequência temporal user-facing de acontecimentos de domínio significativos, Collection-scoped, linguagem de domínio, nunca mutação técnica) e `Audit Log` (necessidade já registrada em C-164, agora com propósito mínimo formalizado — governança/segurança/accountability, reconstrução conceitual de quem/fez o quê/quando/contexto). Activity: actor Owner/Editor/System quando aplicável, Viewer/Public User nunca geram Activity; visível a Owner+Members, nunca automaticamente a Public User; permanece atribuída ao ator histórico após Member exit; nunca expõe dados privados (Storage/Provenance privada/dados financeiros/Favorite/Wishlist). Audit: cobertura priorizada por risco (ações Owner-sensitive e state-changing de Collaborators), não exaustiva. Quatro combinações Activity×Audit reconhecidas (Activity+Audit, Audit-only, Activity-only, nenhuma), matriz não fechada. Immutability de registros históricos; History ≠ Undo; History ≠ Current State (sem event sourcing implícito); Activity ≠ Lifecycle (sem duplicação automática) — formalizados em LDM-154 a LDM-174 (`concept-decisions.md` C-166–C-186). Dependências que permanecem não resolvidas, deliberadamente fora desta rodada: schema físico de qualquer uma das três camadas; lista exaustiva de categorias de Activity; algoritmo de agrupamento para operações em massa; retenção/TTL de Activity e Audit; política de hard-delete/archive sobre Activity/Audit; classificação exaustiva de cada categoria na matriz Activity×Audit; modelagem de Undo/Restore.

## Approval / Messaging
A transversal Pending Action / Approval Request mechanism and User Inbox / Notification Center are required for multi-user operations requiring explicit approval. **Atualização 2026-08-28**: a motivação original (LDM-27) não se aplica mais; este mecanismo permanece como backlog transversal para outros cenários futuros (ex.: troca entre usuários), não para o cenário original.

## Layout (Atualização 2026-08-30)
Collection Layout/Page/Slot/Expected Content/Lock/Slot Assignment/Layout Region agora possuem checkpoint lógico (LDM-29 a LDM-37). Permanecem como dependências não resolvidas por este bloco: mecanismo físico de ordenação de Page (LDM-30); mecanismo de Grid Change em Layout existente (C-40); representação física de Layout Region (bounding box vs. tabela de junção, LDM-37); modelagem de artwork/conteúdo visual de Region; Undo/Redo e histórico de Slot Assignment (explicitamente adiados por D53/LDM-35).

---

# 8. Current Architectural Checkpoint

## Conceptual
**C-01 through C-37 — CLOSED**; **C-38 through C-46 — APPROVED** (Collection Layout); **C-47/C-48 — APPROVED** (Physical Card & Inventory, 2026-08-30); **C-49 through C-54 — APPROVED** (Custody & Availability, 2026-08-30); **C-55 through C-66 — APPROVED** (Storage, 2026-08-30); **C-67 through C-81 — APPROVED** (Physical Card Lifecycle & Provenance, 2026-08-30); **C-82 through C-90 — APPROVED** (Favorite, 2026-08-30); **C-91 through C-102 — APPROVED** (Wishlist, 2026-08-30); **C-103 through C-120 — APPROVED** (Physical Card Condition, 2026-08-30); **C-121 through C-140 — APPROVED** (Grading / Certification, 2026-08-30); **C-141 through C-165 — APPROVED** (Collection Collaboration / Permissions, 2026-08-30); **C-166 through C-186 — APPROVED** (Collection Activity History / Audit, 2026-08-30)

Canonical document:
`concept-decisions.md`

## Logical
**LDM-01 through LDM-190 — APPROVED, LDM-25/26/27 SUPERSEDED (2026-08-28), LDM-16 SUPERSEDED (2026-09-03, ver LDM-177), cláusula Pokédex de LDM-17 SUPERSEDED (2026-09-03, ver LDM-178), LDM-23 REVISADA (2026-08-30), LDM-03 PARCIALMENTE SUPERSEDED (2026-08-30, ver LDM-129–LDM-153), LDM-186–LDM-190 bloco complementar Pokémon Region (2026-09-04), aditivo, física CONFIRMADO EXECUTADO**

This document is the canonical logical checkpoint for LDM-01 through LDM-24 (Collection core), LDM-29 through LDM-37 (Collection Layout, 2026-08-30), LDM-38 through LDM-43 (Custody & Availability, 2026-08-30, sem skeleton físico), LDM-44 through LDM-54 (Storage, 2026-08-30, sem skeleton físico), LDM-55 through LDM-69 (Physical Card Lifecycle & Provenance, 2026-08-30, sem skeleton físico), LDM-70 through LDM-78 (Favorite, 2026-08-30, sem skeleton físico), LDM-79 through LDM-90 (Wishlist, 2026-08-30, sem skeleton físico), LDM-91 through LDM-108 (Physical Card Condition, 2026-08-30, sem skeleton físico), LDM-109 through LDM-128 (Grading / Certification, 2026-08-30, sem skeleton físico), LDM-129 through LDM-153 (Collection Collaboration / Permissions, 2026-08-30, sem skeleton físico), LDM-154 through LDM-174 (Collection Activity History / Audit, 2026-08-30, sem skeleton físico), and LDM-175 through LDM-185 (Pokédex / REFERENCE_POSITION, 2026-09-03, sem skeleton físico — supersede LDM-16 e a cláusula Pokédex de LDM-17). `checkpoint-2026-08-28.md` is canonical for the ownership-model simplification (now formalized directly in LDM-23). `checkpoint-2026-08-30.md` is canonical for the Layout reconciliation diagnostic and for the current open point. Terminology across this document was converged to `Physical Card` on 2026-08-30 — see banner at the top and `concept-decisions.md` C-47/C-48. "Pokémon" foi convergido para "Pokémon Species" em 2026-09-03 nos LDM-16 a LDM-19 e no bloco novo — ver LDM-175.

## Physical
**Inventory + Physical Card (core skeleton, LDM-23): CONFIRMADO EXECUTADO (2026-08-31)** — ver `docs/05d-colecoes-e-usuarios.md`, seção "Physical Card (Exemplar Físico) / Inventory", e `database/schema/5000`–`5012`. Todas as demais frentes (Collection Layout, Custody & Availability, Storage, Lifecycle & Provenance, Favorite, Wishlist, Condition, Grading/Certification, Collaboration/Permissions, Activity History/Audit, Pokédex/REFERENCE_POSITION) permanecem **NOT STARTED** fisicamente — só a fundação patrimonial mínima (LDM-23) foi implementada. **Pokédex/REFERENCE_POSITION (LDM-175 a LDM-185): CONCEPTUALLY CLOSED (2026-09-03) e, desde 2026-09-06, PHYSICALLY IMPLEMENTED / VALIDATED / CLOSED** — Fatias A–E materializadas, validadas e promovidas (`6000`–`6126` e `5085`–`5103`); ver `docs/05d-colecoes-e-usuarios.md`. *(Este parágrafo dizia, até 2026-09-05, "PHYSICAL MODELING NOT STARTED — próximo checkpoint planejado da frente Collections"; era verdadeiro quando escrito e foi superado pelas Fatias A–E.)* **Próxima frente do projeto: Binder/Layout Foundation**, ainda não iniciada.

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
| 1.6 | **Bloco complementar Physical Card Lifecycle & Provenance, 2026-08-30** (`COLLECTIONS-PHYSICAL-CARD-LIFECYCLE-CONSOLIDATION-01`), encerrando a subfrente `Collections — Physical Card Lifecycle / Provenance conceptual modeling`. Adicionadas LDM-55 a LDM-69, formalizando no nível lógico o bloco conceitual C-67 a C-81 — deliberadamente sem skeleton físico além de `inventory_id` (LDM-23): nenhum campo, tabela, enum ou entidade `Ownership Episode` é introduzido. Cobre: Lifecycle e permanência de identidade (LDM-55); Provenance como subconjunto com exclusões explícitas (LDM-56); critério Current State vs. Historical Event (LDM-57); espinha dorsal Ownership Entry (LDM-58), Transfer atômico e sem hiato (LDM-59), Exit (LDM-60), com reason como atributo (LDM-61); Ownership Episode como ferramenta conceitual, sem entidade (LDM-62); fronteira Physical Card Provenance × Owner/Transaction Private Data (LDM-63); linguagem segura de evidência (LDM-64); Transfer Integrity com três consequências paralelas — Collection Allocation, Slot Assignment, Storage (LDM-65); Custody independente de ownership mesmo após Exit, corrigindo recomendação anterior (LDM-66, sem reabrir LDM-38–LDM-43); núcleo V1 (LDM-67); fechamento mínimo de Grading (LDM-68); Valuation/Pricing History não são Provenance (LDM-69). Seção 4 (nota adicional), Seção 7 (nova subseção `Lifecycle / Provenance`) e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-54 não reabertas em conteúdo — LDM-38 a LDM-43 permanecem integralmente vigentes. |
| 1.7 | **Bloco complementar Favorite, 2026-08-30** (`COLLECTIONS-FAVORITE-CONSOLIDATION-01`), encerrando a subfrente `Collections — Favorite conceptual modeling`. Adicionadas LDM-70 a LDM-78, formalizando no nível lógico o bloco conceitual C-82 a C-90 — deliberadamente sem skeleton físico (nenhum campo, tabela ou enum introduzido para a relação User↔Favorite↔Card). Cobre: definição e entidade-alvo, `Card` exclusivamente (LDM-70); pertencimento ao User, transversal a Collections, sem relação com Inventory (LDM-71); independência de ownership (LDM-72); independência de Collection (LDM-73); caráter binário (LDM-74); cardinalidade conceitual (LDM-75); fronteira com Wishlist (LDM-76); cada Card como identidade editorial própria por Set (LDM-77); catalog lifecycle não modelado (LDM-78). Seção 4 (nota adicional), Seção 7 (nova subseção `Favorite`) e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-69 não reabertas em conteúdo. |
| 1.8 | **Bloco complementar Wishlist, 2026-08-30** (`COLLECTIONS-WISHLIST-CONSOLIDATION-01`), encerrando a subfrente `Collections — Wishlist conceptual modeling`. Adicionadas LDM-79 a LDM-90, formalizando no nível lógico o bloco conceitual C-91 a C-102 — deliberadamente sem skeleton físico (nenhum campo, tabela ou enum introduzido para a relação User↔Wishlist↔Card Variant). Cobre: definição e alvo obrigatório `Card Variant` (LDM-79); idioma como refinamento opcional (LDM-80); independência de ownership, sem remoção automática, múltiplas cópias válidas (LDM-81); independência de completion (LDM-82); sem vínculo estrutural com Collection (LDM-83); independência de Expected Content (LDM-84); independência de Favorite, diferença de granularidade intencional (LDM-85); núcleo binário V1 (LDM-86); cardinalidade/duplicidade conceitual (LDM-87); condition/grading como fronteira futura, achado preservado (LDM-88); Marketplace como fronteira futura sem dependência estrutural (LDM-89); User scope (LDM-90). Seção 4 (nota adicional), Seção 7 (nova subseção `Wishlist`) e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-78 não reabertas em conteúdo. |
| 1.9 | **Bloco complementar Physical Card Condition, 2026-08-30** (`COLLECTIONS-PHYSICAL-CARD-CONDITION-CONSOLIDATION-01`), encerrando a subfrente `Collections — Physical Card Condition conceptual modeling`. Adicionadas LDM-91 a LDM-108, formalizando no nível lógico o bloco conceitual C-103 a C-120 — deliberadamente sem skeleton físico (nenhum campo, tabela ou enum introduzido para a referência Physical Card → `card_condition`). Cobre: definição e entidade-alvo exclusivo Physical Card (LDM-91); ratificação conceitual da referência canônica compartilhada `card_condition`, já `CONFIRMADO EXECUTADO` em Pricing, sem alteração de schema (LDM-92); escala canônica formalizada, com discrepância de contagem (5 vs. 6) registrada como pendência não investigada (LDM-93); code canônico independente de idioma vs. label localizado (LDM-94); evidência de mercado brasileiro (LDM-95); opcionalidade, sem valor UNKNOWN (LDM-96); classificação declarada/não certificada (LDM-97); Damage/Defects fora do núcleo V1 (LDM-98); fronteira Condition × Grading, aplicabilidade a cards graded deferida para futura subfrente `Grading / Certification Domain Modeling` (LDM-99); raw/graded não é valor de Condition (LDM-100); sem histórico no núcleo V1 (LDM-101); independência de identidade e de outras dimensões (LDM-102); independência de idioma (LDM-103); independência de Storage/Custody (LDM-104); relação futura com Valuation sem reabrir Pricing (LDM-105); filter semantics sem novo valor de escala (LDM-106); Wishlist permanece sem Condition (LDM-107); escopo mínimo V1 (LDM-108). Seção 4 (nota adicional, mesmo padrão de Custody/Availability), Seção 7 (nova subseção `Physical Card Condition`) e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-90 não reabertas em conteúdo. Nota de divergência registrada: o pedido de consolidação referenciou uma rodada "CONDITION-MODELING-02" não entregue literalmente sob esse nome nesta sessão — o complemento de evidência de mercado brasileiro cumpriu esse papel em conteúdo, tratado como equivalente (ver `concept-decisions.md`, bloco complementar Physical Card Condition, para o texto completo da nota). |
| 1.10 | **Bloco complementar Grading / Certification, 2026-08-30** (`COLLECTIONS-GRADING-CERTIFICATION-CONSOLIDATION-01`), encerrando a subfrente `Collections — Grading / Certification conceptual modeling`. Adicionadas LDM-109 a LDM-128, formalizando no nível lógico o bloco conceitual C-121 a C-140 — deliberadamente sem skeleton físico (nenhum campo, tabela ou enum introduzido para Grading Company/Grade Scale/Grade/Certification). Cobre: separação Grading vs. Certification (LDM-109); entidade-alvo exclusivo Physical Card (LDM-110); Grading Company como Reference Data (LDM-111); Grade Scale, sem equivalência entre companies, cardinalidade não fixada (LDM-112); Grade com valor e/ou designação, sem enum físico (LDM-113); Certification Number opcional, sem conceito separado de "Grading Declaration" (LDM-114); no máximo uma Current Certification por Physical Card (LDM-115); raw/graded como predicado derivado (LDM-116); **fechamento definitivo da pendência deixada aberta por LDM-99/LDM-100** — Current Condition e Current Certification mutuamente exclusivas quanto à aplicabilidade corrente, sem fusão/substituição/derivação entre os dois valores (LDM-117); Condition History fora do V1 (LDM-118); efeitos de crack, Current Condition volta a ser aplicável sem restauração automática (LDM-119); efeitos de regrade, identidade preservada sem canonizar workflow temporal (LDM-120); Grade ≠ Condition sem de-para automático (LDM-121); Certification declarada/registrada, não verificada (LDM-122); subgrades/qualifiers fora do núcleo V1 (LDM-123); fronteira com Protection/Encapsulation (LDM-124); fronteira com Custody/Storage, reafirmando LDM-39/LDM-44/LDM-46 (LDM-125); relação futura com Valuation sem reabrir Pricing (LDM-126); Wishlist inalterada (LDM-127); escopo mínimo V1 (LDM-128). Seção 4 (nota adicional), Seção 7 (nova subseção `Grading / Certification`) e Seção 8 (checkpoint conceitual e lógico) atualizadas. LDM-01 a LDM-108 não reabertas em conteúdo. Direção vigente é a do memo `-02` (`COLLECTIONS-GRADING-CERTIFICATION-MODELING-02`), que corrigiu a posição do `-01` sobre a aplicabilidade simultânea de Condition e Certification antes de qualquer consolidação — sem supersessão de documento canônico. |
| 1.11 | **Bloco complementar Collection Collaboration / Permissions, 2026-08-30** (`COLLECTIONS-COLLABORATION-PERMISSIONS-CONSOLIDATION-01`), encerrando a subfrente `Collections — Collaboration / Permissions conceptual modeling`. Adicionadas LDM-129 a LDM-153, formalizando no nível lógico o bloco conceitual C-141 a C-165 — deliberadamente sem skeleton físico (nenhuma tabela de Membership, enum de role, ou campo introduzido). Cobre: Collection Owner como relação estrutural própria, fora de Membership (LDM-129); Collection Membership restrita a Users não-owner, 0..N (LDM-130); roles V1 EDITOR/VIEWER, sem OWNER como role (LDM-131); Collaboration ≠ Ownership (LDM-132); Viewer read-only formal (LDM-133); Editor com fronteira precisa de capacidades (LDM-134); **Collection Allocation reclassificada como Owner-authorized Collection operation**, corrigindo a formulação "operação patrimonial" do memo-01 (LDM-135); Slot Assignment Collection-scoped após Allocation (LDM-136); Expected Content/Layout Editor-capable (LDM-137); metadata comum vs. estrutural sensível (LDM-138); Visibility Owner-only (LDM-139); **Public Access formalizado como consequência de Visibility, distinto de Membership e da role VIEWER** (LDM-140); Invite/Acceptance explícitos (LDM-141); Membership management Owner-only (LDM-142); efeitos de remoção/saída sobre o estado da Collection (LDM-143); invariante estrutural do Owner (LDM-144); Physical Card visibility escopada às cartas alocadas (LDM-145); private data não exposta automaticamente (LDM-146); Storage privado por padrão (LDM-147); Condition/Certification legíveis para curadoria, não editáveis (LDM-148); Provenance não exposta por Membership (LDM-149); lista de Owner-only operations (LDM-150); Sharing/link ≠ Collaboration (LDM-151); necessidade futura de Audit Log registrada (LDM-152); escopo mínimo V1 (LDM-153). Seção 4 (nota adicional sobre Owner/Members), Seção 7 (subseção `Permissions`, atualizada de placeholder original para "conceitualmente resolvido") e Seção 8 (checkpoint conceitual e lógico) atualizadas. Header table (Decision Register/Escopo) também atualizado nesta rodada para refletir os blocos Physical Card Condition e Grading/Certification, que haviam sido adicionados nas versões 1.9/1.10 sem correspondente atualização do cabeçalho — correção de consistência, sem alteração de conteúdo normativo. LDM-01 a LDM-128 não reabertas em conteúdo. Direção vigente é a do memo `-02` (`COLLECTIONS-COLLABORATION-PERMISSIONS-MODELING-02`), que corrigiu a duplicidade conceitual do `-01` (Owner tratado simultaneamente como estrutural e como role de Membership) antes de qualquer consolidação — sem supersessão de documento canônico. |
| 1.12 | **Bloco complementar Collection Activity History / Audit, 2026-08-30** (`COLLECTIONS-ACTIVITY-HISTORY-AUDIT-CONSOLIDATION-01`), encerrando a subfrente `Collections — Activity History / Audit conceptual modeling`. Adicionadas LDM-154 a LDM-174, formalizando no nível lógico o bloco conceitual C-166 a C-186 — deliberadamente sem skeleton físico (nenhuma tabela, campo ou enum introduzido para Activity History ou Audit). Cobre: três camadas conceitualmente distintas — Lifecycle/Provenance, Activity History, Audit (LDM-154); definição de Collection Activity History (LDM-155); Activity Trigger refinado para "acontecimento de domínio significativo" (LDM-156); linguagem de domínio, nunca schema técnico (LDM-157); categorias candidatas não exaustivas (LDM-158); actor Owner/Editor/System (LDM-159); visibilidade Owner+Members, nunca automática a Public User (LDM-160); Activity permanece após Member exit (LDM-161); privacidade — sem exposição automática de dados privados (LDM-162); definição de Audit Log (LDM-163); Audit coverage priorizado por risco (LDM-164); quatro combinações Activity×Audit, matriz não fechada (LDM-165); grouping/bulk reconhecido, mecanismo não decidido (LDM-166); immutability (LDM-167); retenção diferenciada, sem TTL (LDM-168); archive/delete boundary identificada — Lifecycle permanece independente da Collection (LDM-169); History ≠ Undo (LDM-170); History ≠ Current State, sem event sourcing implícito (LDM-171); System como actor possível (LDM-172); Activity ≠ Lifecycle (LDM-173); escopo mínimo V1 (LDM-174). Seção 4 (nota adicional), Seção 7 (subseção `Collection Activity History / Audit`, atualizada de placeholder original `## Audit` para "conceitualmente resolvido") e Seção 8 (checkpoint conceitual e lógico) atualizadas. Header table (Decision Register/Escopo) também atualizada. LDM-01 a LDM-153 não reabertas em conteúdo — todas as subfrentes anteriores permanecem integralmente vigentes. Direção vigente é a do memo único `COLLECTIONS-ACTIVITY-HISTORY-AUDIT-MODELING-01`, aprovado diretamente sem rodada de correção intermediária. |
| 1.13 | **Reconciliação transversal, 2026-08-30** (`COLLECTIONS-TRANSVERSAL-RECONCILIATION-01`), decorrente de `COLLECTIONS-TRANSVERSAL-DOMAIN-REVIEW-01`. Espelha, no nível lógico, a correção de `concept-decisions.md` v1.13: **LDM-03 parcialmente superseded** — preservadas "Collection + User is unique" e "the Owner is not simultaneously a normal Collection Member"; superada a semântica de "permission profile and effective permissions"/matriz de permissões futura, incompatível com LDM-131/LDM-153 (roles fixos EDITOR/VIEWER, sem custom permission system) — formalização lógica de C-08 parcialmente superada. **LDM-02 explicitamente confirmada, não alterada**: "explicit Owner through `owner_user_id`" e "ownership is distinct from sharing/membership" permanecem compatíveis com LDM-129 — a decisão conceitual de Owner como relação estrutural não determina, por si só, a representação física (coluna, relação separada ou outro mecanismo permanece decisão de modelagem física futura, não fixada nesta rodada). **LDM-48 ajustada** (redação apenas): removido o termo "leaf" por poder sugerir uma constraint física inexistente (nenhuma decisão restringe Physical Cards a containers sem filhos — ver C-63); sem mudança de semântica. Seção 8 (checkpoint lógico) atualizada para registrar a supersessão parcial de LDM-03. Nenhuma nova LDM-* criada — LDM-02, LDM-03 e LDM-48 mantiveram seus números originais, apenas com status/nota/redação ajustados. LDM-01 a LDM-174 não reabertas em conteúdo além do estritamente descrito acima. |
| 1.14 | **Reconciliação da escala física de Condition, 2026-08-31** (`COLLECTIONS-CARD-CONDITION-RECONCILIATION-02`), decorrente da auditoria read-only `COLLECTIONS-CARD-CONDITION-MINT-POSTCHECK-01`. Espelha, no nível lógico, a correção de `concept-decisions.md` v1.14: **LDM-93 atualizada** — escala canônica passa dos codes longos "pretendidos" (nunca gravados fisicamente) para os codes físicos reais confirmados em `card_condition` (`M`/`NM`/`LP`/`MP`/`HP`/`DMG`, `condition_order` 1..6); pendência histórica de contagem (5 vs. 6) registrada desde a versão 1.9 está **CLOSED**. **LDM-94 atualizada**: exemplo de code trocado de `NEAR_MINT` para `NM`. **LDM-95 atualizada**: nota de precisão distinguindo o "D" de mercado do code canônico `DMG`, e confirmando que equivalências de fonte externa pertencem à camada de mapping, nunca ao vocabulário canônico. Nenhuma nova LDM-* criada — LDM-93/LDM-94/LDM-95 mantiveram seus números originais, apenas conteúdo/status atualizados. LDM-01 a LDM-174 não reabertas além do estritamente descrito acima. Pricing e banco permanecem intocados nesta rodada (documental pura). |
| 1.15 | **Primeira materialização física do bloco Storage, 2026-09-01** (`COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`), decorrente das rodadas de modelagem física `COLLECTIONS-PHYSICAL-MODELING-03`/`-REVISION-01`/`-REVISION-02`/`-FINAL-01` e da rodada de staging `COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01`. Header (linha "Status") e Seção "Current modeling status" atualizados para registrar Storage Container + `physical_card.storage_container_id` como CONFIRMADO EXECUTADO. Adicionada nota de materialização física logo após a introdução do bloco complementar Storage (antes de LDM-44), apontando que apenas LDM-45 (ownership mediado por Inventory), LDM-46 (cardinalidade 0..1 reafirmada) e LDM-49 (Storage nunca cruza Inventory, via FK composta + CHECK) foram fisicamente materializadas — hierarquia (LDM-48), capacidade (LDM-50), remoção estrutural (LDM-51), Bulk Card Transfer (LDM-52) e Reparent (LDM-53) permanecem sem skeleton físico. Nenhuma LDM-* teve seu texto normativo alterado ou sua decisão reaberta — apenas anotado com um ponteiro para o novo estado físico, mesmo padrão já usado para LDM-23 na versão 1.3. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Storage / Storage Container", para a documentação física narrativa completa, e `database/schema/5020`-`5024`/`database/validations/5802`-`5803` para o SQL e as validações `CONFIRMADO EXECUTADO`. |
| 1.15 | **Fundação física de Inventory + Physical Card CONFIRMADO EXECUTADO, 2026-08-31** (`COLLECTIONS-PHYSICAL-INCREMENT-01B`, seis Queries `5000`–`5012`, primeira entidade do módulo Collections no Modelo Modular de Numeração). Apenas atualização de status/ponteiro — nenhum conteúdo normativo de LDM-23 (ou de qualquer outra LDM-*) foi reaberto ou alterado: a regra de cardinalidade e identidade já formalizada em LDM-23 (revisão 2026-08-30) foi implementada fisicamente exatamente como descrita, sem divergência encontrada. Header table (`Status`), "Current modeling status" (linha "Physical model") e seção "## Physical" (Seção 8) atualizados para refletir CONFIRMADO EXECUTADO do core skeleton (Inventory + Physical Card), com todas as demais frentes (Layout, Custody & Availability, Storage, Lifecycle & Provenance, Favorite, Wishlist, Condition, Grading/Certification, Collaboration/Permissions, Activity History/Audit) permanecendo explicitamente NOT STARTED fisicamente. Documentação física narrativa completa (SQL, decisões de índice/grants/RLS, resultados de validação) em `docs/05d-colecoes-e-usuarios.md`, não duplicada aqui. Ver `docs/log.md`. |
| 1.16 | **Primeira materialização física do skeleton raiz de Collection, 2026-09-01** (`COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`), decorrente das rodadas de modelagem física `COLLECTIONS-PHYSICAL-MODELING-03`/`2B-MODELING-01`/`2B-MODELING-FINAL-01` e da rodada de staging `2B-STAGING-REVISION-01`. Header (linha "Status") e Seção "Current modeling status" (linha "Physical model") atualizados para registrar o skeleton raiz de `Collection` (LDM-12) como CONFIRMADO EXECUTADO. Adicionada nota de materialização física logo após o título de LDM-12, apontando os campos efetivamente materializados na tabela `public.collection` (`id`, `game_id`, `owner_user_id`, `name`, `description`, `mode`, `lifecycle_status`, `visibility`, `default_storage_container_id`, `reference_locked_at`, `archived_at`, `created_at`, `updated_at`) e os campos deliberadamente fora de escopo nesta rodada (`completion_policy`, `started_at`, `created_by_user_id`, `updated_by_user_id`). Nenhuma LDM-* teve seu texto normativo alterado ou sua decisão reaberta — apenas anotado com um ponteiro para o novo estado físico, mesmo padrão já usado para LDM-23 (versão 1.3) e para o bloco Storage (versão 1.15). Divergência real encontrada e corrigida durante a implementação (não uma decisão desta rodada de documentação): a proposta física original de `create_collection()` dependia de `game.is_active`, coluna inexistente no modelo físico de `public.game` e sem decisão conceitual correspondente para Game — Fabrício optou por remover a dependência (não criar a coluna), preservando apenas a FK estrutural `collection.game_id → game.id`; eventual lifecycle/ativação de Game é registrado como decisão futura do domínio de Catálogo, fora desta subfrente de Collections. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Collection (Coleção)", para a documentação física narrativa completa, e `database/schema/5030`-`5039`/`database/validations/5804`-`5805` para o SQL e as validações `CONFIRMADO EXECUTADO`. |
| 1.17 | **Reconciliação e documentação canônica do bloco Pokédex / REFERENCE_POSITION, 2026-09-03** (`COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`), rodada exclusivamente de documentação, decorrente da cadeia de rodadas conceituais `COLLECTIONS-POKEDEX-MODELING-AUDIT-01` → `COLLECTIONS-POKEDEX-DATA-SOURCE-SPIKE-01` → `COLLECTIONS-POKEDEX-TCGDEX-DEXID-PROOF-01` → `COLLECTIONS-POKEDEX-MODELING-RECONCILIATION-01`. **LDM-16 SUPERSEDED** — Collection Pokédex Scope deixa de ser individualmente adotado por Position e passa a `FULL_REFERENCE` (padrão) ou `GENERATION_FILTERED` (1..N Generations), com Positions derivadas do Scope; texto original preservado, ver LDM-177. **Cláusula Pokédex de LDM-17 SUPERSEDED** — hard block de elegibilidade substituído por Species Match (silencioso, `assignment_basis=SPECIES_MATCH`) vs. Mismatch/sem Species/Trainer-Energy (aviso + confirmação explícita, `assignment_basis=USER_OVERRIDE`), nunca bloqueio duro; cláusulas de Open Curation e Card Set de LDM-17 não afetadas; texto original preservado, ver LDM-178. Adicionado novo bloco complementar **LDM-175 a LDM-185**: LDM-175 (Pokémon Species/Generation/Pokémon Form-Variety, convergência terminológica, formaliza a revogação do adiamento de ADR-011 no nível lógico), LDM-176 (Pokédex Position referencia exatamente uma Species), LDM-177 (Collection Pokédex Scope, supersede de LDM-16), LDM-178 (Species Match/Mismatch, supersede da cláusula Pokédex de LDM-17), LDM-179 (Pokédex Position Assignment, novo conceito lógico, sem tabela física), LDM-180 (Primary Representative, opcional, apresentacional), LDM-181 (Completion de REFERENCE_POSITION, revisão do denominador/numerador por Assignment), LDM-182 (sourcing de Card Primary Species — `dexId` único vs. reconciliação editorial, decisão central de LDM-18 inalterada), LDM-183 (Sourcing Model — PokéAPI + TCGdex + MMKYU Editorial Reconciliation + catálogo MMKYU como autoridade em runtime; Editorial Reconciliation ≠ USER_OVERRIDE), LDM-184 (Correção Editorial Posterior não remove Assignment nem invalida completion automaticamente), LDM-185 (confirmação de ARCHIVED para Pokédex — sem decisão nova). LDM-18 e LDM-19 tiveram apenas anotações/ponteiros adicionados (terminologia e projeção Card → Pokémon Species → Pokédex Position), sem reabertura de decisão. Seção 4 (árvore de relacionamento canônica), Seção 6 (hipóteses rejeitadas, itens 18 e 19 adicionados), Seção 7 (nova subseção "Pokédex / REFERENCE_POSITION", catálogo canônico atualizado para Pokémon Species/Generation/Form) e Seção 8 ("Logical" e "Physical" atualizados — Pokédex/REFERENCE_POSITION CONCEPTUALLY CLOSED, PHYSICAL MODELING NOT STARTED) também atualizadas, junto com a tabela header do documento. LDM-01 a LDM-174 não reabertas em conteúdo — apenas LDM-16, LDM-17 (cláusula Pokédex), LDM-18 e LDM-19 receberam anotações/ponteiros conforme descrito acima. Nenhuma mudança física, nenhum SQL, nenhum commit/push nesta rodada. Ver `docs/adr/ADR-011-pokemon-tcg-domain-scope.md` (nova emenda v1.2), `docs/04-domain-model.md`, `docs/05d-colecoes-e-usuarios.md` e `docs/log.md` para a documentação complementar do mesmo ciclo. |
| 1.18 | **Desambiguação de "Explicit Assignment" e reconciliação do status físico do bloco Pokédex, 2026-09-06 (`COLLECTIONS-POKEDEX-AUTO-ASSIGNMENT-DOC-RECONCILIATION-01`). Rodada exclusivamente documental — nenhuma entidade, cardinalidade ou decisão lógica alterada; nenhum SQL executado; Fatias D e E não reabertas.** LDM-179 passa a formalizar que **"Assignment explícito" significa que uma linha materializada própria de Position Assignment precisa existir** para a Position ser satisfeita — e **não** que essa linha precise ser criada manualmente pelo usuário. Os dois caminhos válidos ficam registrados: **(A) SYSTEM `SPECIES_MATCH`** — Allocation + match inequívoco → Assignment criada automaticamente pelo domínio (Fatia D, Query `6119`, `assigned_by_user_id = NULL`, sem filtro de Scope, sem erro quando não há match); **(B) USER-DRIVEN** — Assignment via fluxo explícito/RPC (Query `6122`), com `USER_OVERRIDE` exigindo confirmação humana e **nunca** sendo automático. Completion (LDM-181) segue consultando exclusivamente a Assignment, nunca a Allocation. LDM-178 ganhou a nota de materialização física correspondente. O campo **Status** do documento deixou de afirmar `PHYSICAL MODELING NOT STARTED` para o bloco Pokédex — as Fatias A–E estão fisicamente implementadas e fechadas desde 2026-09-06; próxima frente Binder/Layout Foundation. A frase original de LDM-179 que descrevia a modelagem física como "frente futura" foi preservada com nota de estado, sem reescrita da decisão histórica. Ver `docs/05d-colecoes-e-usuarios.md` revisão `1.17`, `docs/development/HANDOFF-2026-09-04.md` revisão `1.11` e `docs/log.md`. |
