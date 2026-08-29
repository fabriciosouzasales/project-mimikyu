# ADR-013 — Collection Item Identity Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-013 |
| **Título** | Collection Item Identity Model |
| **Status** | Substituído |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | O termo provisório "Inventory Item" é substituído por "Collection Item". Cada exemplar físico possui identidade individual e permanente — nunca é representado como quantidade agregada. Collection Item referencia Card Variant (não Card diretamente) e um idioma, identificando uma combinação editorial válida. Ownership Status e Availability Status são dimensões distintas. |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-010-card-rarity-and-finish-model.md`, `ADR-016-card-variant-naming-convention.md`, `ADR-006-separation-of-catalog-ownership-and-analytics.md`, `../domain-modeling/collections/` |

---

> ⚠️ **SUBSTITUÍDO em 2026-08-28.** A modelagem de domínio de Collections foi reconciliada em `docs/domain-modeling/collections/` (`concept-decisions.md`, `logical-model.md`, `checkpoint-2026-08-28.md`), que passam a ser a fonte canônica para este domínio. Em particular: o nome vigente da identidade física é **Inventory Item** (não "Collection Item" — a renomeação proposta nesta ADR foi revertida na modelagem nova); Inventory Item referencia Card Variant, mas não carrega mais `owner_user_id` — a posse é transitiva via um novo agregado `Inventory` (1:1 por usuário); Ownership Status/Availability Status como dimensões de status não foram reafirmadas na modelagem nova e não devem ser assumidas como vigentes sem confirmação em `logical-model.md`. Este documento é preservado abaixo, inalterado, por rastreabilidade histórica — não implementar a partir daqui.

# Context

A entidade que representa o exemplar físico pertencente a um usuário vinha sendo chamada de "Inventory Item" desde os primeiros ciclos de modelagem. Esse nome funciona bem para um sistema de controle de estoque, mas o Project Mimikyu é uma plataforma de colecionismo — essa diferença de propósito motivou a revisão do nome antes de detalhar essa entidade, por se tratar, muito provavelmente, da entidade mais acessada de todo o sistema.

Paralelamente, era preciso decidir: (1) se exemplares fisicamente idênticos deveriam ser representados como uma quantidade agregada por combinação de Card + Card Variant + Language, ou como registros individuais; e (2) como representar, sem ambiguidade, se um exemplar ainda pertence ao usuário e se está disponível para alguma finalidade (troca, venda).

---

# Decision

## Renomeação

O termo "Inventory Item" é substituído por **Collection Item (Item da Coleção)** em toda a documentação e, futuramente, na modelagem lógica e física.

## Identidade individual

Cada exemplar físico recebe identidade própria, permanente e individual — nunca uma quantidade agregada. Três cópias idênticas de uma mesma Card são três Collection Items distintos (`ITEM_0003456`, `ITEM_0003457`, `ITEM_0003458`), não um único registro com `quantity = 3`. Isso é necessário porque cada cópia pode ter origem, custo, condição, localização, histórico e destino diferentes.

## Relação com o catálogo

Collection Item referencia um Card Variant (não a Card diretamente — ver ADR-010, ADR-016) e um idioma, identificando uma combinação editorial válida de Card + Card Variant + Language.

## Ownership Status e Availability Status

São modeladas como duas dimensões distintas, e não como uma única lista de status combinados:

- Ownership Status — se o exemplar ainda pertence ao usuário (ex.: `OWNED`, `SOLD`, `DISPOSED`);
- Availability Status — se o exemplar está disponível para alguma finalidade (ex.: `AVAILABLE_FOR_TRADE`, `RESERVED`).

## Identidade técnica e permanente

Mudanças em condição, armazenamento ou disponibilidade nunca alteram a identidade do Collection Item.

---

# Consequences

## Benefícios

- nome alinhado ao propósito real da plataforma (colecionismo, não estoque);
- preserva o histórico individual de cada exemplar (aquisição, condição, movimentação, venda, troca);
- evita ambiguidade entre "o item ainda é meu?" e "o item está disponível para algo?".

## Restrições / Pendências

- a estrutura detalhada de informações do Collection Item (grupos Identity, Physical State, Collection Role, Lifecycle) é preliminar; parte dessas informações provavelmente se tornará entidades relacionadas próprias (ex.: Acquisition, Movement, Grading Submission, Trade, Sale, Valuation), a ser definida em ciclos futuros de documentação e na modelagem lógica;
- a relação entre `Collection Item.language` e Card Translation (referência direta vs. valor solto) permanece em aberto;
- Storage Location e o histórico de movimentação ainda não foram detalhados (ver `04-domain-model.md`).

---

# Alternatives Considered

## Manter o nome "Inventory Item"

Rejeitada por refletir um modelo mental de estoque, incompatível com o posicionamento do produto como plataforma de colecionismo.

## Representar exemplares idênticos como quantidade agregada (Card + Card Variant + Language + quantity)

Rejeitada por impedir o controle individual de condição, preço, origem, histórico e destino de cada cópia física — informações essenciais para um colecionador.

## Combinar Ownership Status e Availability Status em uma única lista de valores

Rejeitada por gerar ambiguidade entre duas perguntas conceitualmente diferentes ("ainda é meu?" vs. "está disponível para algo?").

---

# Related Documents

- `../04-domain-model.md`
- `ADR-010-card-rarity-and-finish-model.md`
- `ADR-016-card-variant-naming-convention.md`
- `ADR-006-separation-of-catalog-ownership-and-analytics.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da renomeação de Inventory Item para Collection Item, do modelo de identidade individual por exemplar, e da separação entre Ownership Status e Availability Status. |
| 1.1 | Referências a "Card Finish" atualizadas para "Card Variant" (Decisão, Context, Decision, Alternatives Considered), refletindo a convergência de nomenclatura de ADR-016. Nenhuma decisão desta ADR foi alterada. |
| 1.2 | **Substituído em 2026-08-28.** Status alterado para Substituído; banner adicionado apontando para `docs/domain-modeling/collections/` como fonte canônica do domínio Collections. Reconciliação motivada por três documentos de modelagem produzidos em paralelo (`concept-decisions.md`, `logical-model.md`, `pkmnbindr-benchmark.md`) e por decisões de simplificação de ownership registradas em `checkpoint-2026-08-28.md`. Conteúdo original preservado abaixo, sem alteração. |
