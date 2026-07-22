# ADR-014 — Collection and Collection Entry Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-014 |
| **Título** | Collection and Collection Entry Model |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Set (catálogo editorial) e Collection (objetivo de organização do colecionador) são conceitos distintos. Uma Collection pode corresponder a um único Set (Official Set Collection) ou ser independente de qualquer Set (Custom Collection). Collection Entry representa um item do objetivo da Collection, em um de dois modos: Card Target (Card específica) ou Subject Target (ex.: um Pokémon, satisfeito por qualquer Card correspondente). |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-004-set-identity.md`, `ADR-006-separation-of-catalog-ownership-and-analytics.md`, `ADR-011-pokemon-tcg-domain-scope.md`, `ADR-013-collection-item-identity-model.md` |

---

# Context

O modelo conceitual já definia Set como a publicação editorial oficial, e Collection Item como o exemplar físico individual pertencente a um usuário (ADR-013). Faltava, porém, representar objetivos de organização definidos pelo próprio colecionador — como uma Pokédex Nacional, uma coleção temática de "Treinadores", ou uma seleção manual como "Pokémon Trabalhando" — que não correspondem a um único Set oficial e, no caso da Pokédex, nem exigem uma Card específica, apenas um representante de cada Pokémon.

Sem esse conceito, o sistema não teria como diferenciar o objetivo de completar o Set ME1 (Cards conhecidas e finitas) do objetivo de montar uma Pokédex pessoal (que aceita qualquer Card de cada Pokémon, de qualquer Set).

---

# Decision

## Set ≠ Collection

Set pertence ao Catálogo Editorial e existe independentemente dos usuários (ver ADR-004, ADR-006). Collection pertence ao colecionador e não existe sem um usuário associado (`owner_id`).

## Dois tipos de Collection

- **Official Set Collection (`SET_BASED`)** — o objetivo corresponde a um único Set; as Cards esperadas podem ser derivadas automaticamente do Set referenciado.
- **Custom Collection (`CUSTOM`)** — o objetivo é independente de Set; suas Cards podem vir de múltiplos Sets e Expansions.

## Collection Entry: Card Target vs. Subject Target

Cada Collection Entry representa um item do objetivo da Collection, em um de dois modos:

- **Card Target** — exige uma Card específica (ex.: todas as Cards do ME1; todas as Special Illustration Rare).
- **Subject Target** — exige um assunto mais amplo, satisfeito por qualquer Card correspondente (ex.: uma posição da Pokédex é satisfeita por qualquer Card válida daquele Pokémon, de qualquer Set).

## Mecanismos de inclusão

Duas formas de popular uma Collection são reconhecidas conceitualmente: Manual Membership (o colecionador adiciona manualmente) e Rule-Based Membership (entradas geradas por regras estruturadas, ex.: raridade, Pokémon, categoria, ilustrador). Apenas Manual Membership e a geração automática simples de Official Set Collections estão previstas para a primeira implementação; um motor completo de regras é deliberadamente adiado (AP-004 — Build for Growth without Premature Optimization).

---

# Consequences

## Benefícios

- permite representar tanto coleções oficiais (Set) quanto coleções temáticas e personalizadas (Pokédex, Treinadores, Pokémon Trabalhando), sem deformar a estrutura do catálogo;
- evita duplicar a identidade de Card em cada coleção — Collection Entry apenas referencia Card ou Pokémon;
- mantém o catálogo (Set, Card) livre de qualquer dependência do universo do colecionador (consistente com ADR-006 e AP-012).

## Restrições / Pendências

- a estrutura definitiva de Collection e Collection Entry (campos nullable `card_id`/`pokemon_id` vs. duas entidades especializadas) é uma primeira aproximação, a ser revisada na modelagem lógica;
- Rule-Based Membership (inclusão automática por regras) não está detalhado nesta ADR — fica para um ciclo futuro, quando houver necessidade concreta;
- a relação entre "User Collection" (termo provisório anterior, ainda registrado como stub em `04-domain-model.md`) e esta nova entidade Collection não foi explicitamente confirmada — tratada como possivelmente o mesmo conceito, sem exclusão do termo antigo até confirmação.

---

# Alternatives Considered

## Modelar Collection sempre vinculada 1:1 a um Set

Rejeitada por não suportar coleções temáticas ou personalizadas (Pokédex, Treinadores, Pokémon Trabalhando), que não correspondem a um único Set.

## Exigir que toda Collection Entry referencie sempre uma Card específica

Rejeitada por não suportar o caso da Pokédex, em que qualquer Card válida de um Pokémon deve satisfazer o objetivo, independentemente do Set de origem.

## Construir um motor completo de regras (Rule-Based Membership) desde a primeira versão

Rejeitada por antecipar complexidade sem necessidade comprovada (AP-004); Manual Membership e geração automática simples para Official Set Collection já atendem ao primeiro objetivo funcional.

---

# Related Documents

- `../04-domain-model.md`
- `ADR-004-set-identity.md`
- `ADR-006-separation-of-catalog-ownership-and-analytics.md`
- `ADR-011-pokemon-tcg-domain-scope.md`
- `ADR-013-collection-item-identity-model.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da distinção entre Set (catálogo editorial) e Collection (objetivo do colecionador), dos tipos Official Set Collection/Custom Collection, e do modelo Collection Entry com Card Target/Subject Target. |
