# ADR-005 — Catalog Language Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-005 |
| **Título** | Catalog Language Model |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | O idioma não faz parte da identidade editorial do catálogo. |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-004-set-identity.md` |

---

# Context

O catálogo precisa representar publicações disponíveis em diferentes idiomas.

Era necessário decidir se cada idioma seria tratado como um Set distinto ou como diferentes representações da mesma publicação.

---

# Decision

O catálogo possuirá identidade única para Game, Expansion, Set e Card.

O idioma será tratado apenas no contexto do exemplar físico pertencente ao usuário.

Consequentemente:

- Set não será duplicado por idioma;
- Card não será duplicada por idioma;
- Physical Card armazenará o idioma do exemplar (nome vigente desde 2026-08-30; nomes anteriores: `Collection Item`, `Inventory Item` — ver `domain-modeling/collections/concept-decisions.md`, C-47/C-48).

O catálogo inicial suportará apenas:

- English;
- Portuguese.

Catálogos japoneses permanecem fora do escopo atual.

---

# Consequences

## Benefícios

- evita duplicação do catálogo;
- simplifica relacionamentos;
- reduz redundância;
- mantém compatibilidade entre idiomas.

## Evolução futura

Caso diferenças editoriais relevantes entre idiomas precisem ser representadas futuramente, poderá ser introduzido um conceito subordinado (por exemplo, Set Release), preservando a identidade do Set.

> **Nota (ADR-007):** essa evolução futura foi resolvida — não ao nível do Set, mas ao nível da Card, por meio da entidade Card Translation. Ver `ADR-007-card-translation-model.md` para a decisão completa. Este texto é preservado sem alteração como registro histórico da decisão original.

---

# Related Documents

- `../04-domain-model.md`
- `ADR-004-set-identity.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão sobre o modelo de idioma do catálogo. |
| 1.1 | Padronização do cabeçalho (campos ADR, Título, Decisores, Documentos Relacionados) e correção de caminhos relativos em Related Documents. |
| 1.2 | Adicionada nota de referência cruzada apontando para ADR-007, que resolveu a evolução futura prevista nesta ADR. Nenhum conteúdo original foi alterado. |
| 1.3 | Convergência terminológica (2026-08-30): referência a "Inventory Item" (consequência downstream da decisão, não a decisão em si) atualizada para "Physical Card" — ver `concept-decisions.md` C-47/C-48. A decisão desta ADR (idioma pertence ao exemplar físico, não ao catálogo) não foi alterada. |