# ADR-005 — Catalog Language Model

| Campo | Valor |
|--------|-------|
| Status | Aprovado |
| Data | 2026-07 |
| Decisão | O idioma não faz parte da identidade editorial do catálogo. |

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
- Inventory Item armazenará o idioma do exemplar.

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

---

# Related Documents

- 04-domain-model.md
- ADR-004