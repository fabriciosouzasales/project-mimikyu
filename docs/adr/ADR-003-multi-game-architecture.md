# ADR-003 — Multi-Game Architecture

| Campo | Valor |
|--------|-------|
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisão** | O Project Mimikyu será arquitetado para suportar múltiplos Trading Card Games (TCGs), tendo Pokémon TCG como primeiro catálogo oficial. |

---

# Context

Durante a modelagem do domínio foi identificada a necessidade de definir o escopo arquitetural do sistema.

Duas abordagens foram consideradas:

- Sistema especializado exclusivamente em Pokémon;
- Sistema genérico para múltiplos TCGs.

---

# Decision

Foi adotada a arquitetura multi-TCG.

O conceito raiz do catálogo oficial passa a ser **Game**, seguido pela hierarquia:

```text
Game
    ↓
Expansion
    ↓
Set
    ↓
Card
```

Todo conteúdo do catálogo pertence obrigatoriamente a um único Game.

---

# Consequences

## Benefícios

- desacoplamento do domínio Pokémon;
- reutilização da arquitetura para novos TCGs;
- baixo aumento de complexidade;
- maior longevidade do projeto.

## Restrições

O projeto continuará priorizando Pokémon TCG.

Outros jogos somente serão adicionados quando fizerem sentido para o produto.

---

# Related Documents

- 04-domain-model.md
- 02-architecture-principles.md