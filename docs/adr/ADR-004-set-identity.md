# ADR-004 — Set Identity

| Campo | Valor |
|--------|-------|
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisão** | Set representa uma única publicação editorial oficial do catálogo, independentemente do idioma em que seja distribuído. |

---

# Context

Durante a modelagem do domínio surgiu a necessidade de definir o significado oficial do conceito Set.

Existiam duas alternativas:

- considerar cada idioma como um Set distinto;
- considerar que todos os idiomas representam a mesma publicação editorial.

---

# Decision

Foi adotada a segunda alternativa.

Um Set representa uma única publicação oficial do catálogo.

Versões em inglês, português ou outros idiomas representam apenas distribuições regionais da mesma publicação.

Exemplo:

```text
Scarlet & Violet — Journey Together

├── English
├── Português
└── Outros idiomas
```

Todos pertencem ao mesmo Set.

---

# Consequences

## Benefícios

- identidade única para o catálogo;
- simplificação da modelagem;
- redução de duplicidades;
- compatibilidade com múltiplos idiomas;
- maior facilidade de integração com APIs.

## Restrições

Diferenças editoriais entre idiomas deverão ser tratadas em níveis inferiores do modelo (Card, Card Variant ou metadados específicos), nunca através da criação de novos Sets.

---

# Related Documents

- 04-domain-model.md
- ADR-003