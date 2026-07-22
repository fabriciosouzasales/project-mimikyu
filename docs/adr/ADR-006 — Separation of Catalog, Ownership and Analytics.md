# ADR-006 — Separation of Catalog, Ownership and Analytics

| Campo | Valor |
|--------|-------|
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisão** | O domínio será estruturado em três responsabilidades conceituais independentes: Catálogo Editorial, Patrimônio do Usuário e Análises. |

---

# Context

O Project Mimikyu precisa representar simultaneamente:

- informações oficiais publicadas pelos responsáveis pelos Trading Card Games;
- exemplares físicos pertencentes aos usuários;
- indicadores e análises derivados dessas informações.

Sem uma separação explícita, o sistema poderia duplicar dados editoriais no inventário dos usuários, misturar características de catálogo com condições físicas ou persistir informações analíticas que poderiam ser calculadas.

---

# Decision

O domínio será organizado em três responsabilidades conceituais independentes.

## 1. Editorial Catalog (Catálogo Editorial)

Representa exclusivamente os dados oficiais do catálogo.

Sua hierarquia principal é:

```text
Game
  ↓
Expansion
  ↓
Set
  ↓
Card
```

O Catálogo Editorial não depende da existência de usuários ou coleções pessoais.

---

## 2. User Ownership (Patrimônio do Usuário)

Representa exclusivamente os exemplares físicos pertencentes aos usuários.

Inclui informações próprias do exemplar, como:

- idioma;
- condição de conservação;
- certificação;
- data de aquisição;
- preço de aquisição;
- localização física;
- observações particulares.

O patrimônio referencia o catálogo, mas não duplica sua identidade editorial.

---

## 3. Analytics (Análises)

Representa informações derivadas do Catálogo Editorial e do Patrimônio do Usuário.

Sempre que uma informação puder ser calculada de forma confiável, ela não deverá ser persistida redundantemente sem justificativa técnica específica.

---

# Consequences

## Benefícios

- o catálogo permanece independente dos usuários;
- a remoção de uma coleção não afeta o catálogo;
- dados editoriais não são duplicados no patrimônio;
- atualizações no catálogo beneficiam todos os usuários;
- características físicas não contaminam o modelo editorial;
- análises podem evoluir sem alterar a identidade do catálogo;
- responsabilidades tornam-se mais claras para implementação e manutenção.

## Restrições

- entidades do patrimônio deverão referenciar entidades do catálogo;
- dados derivados não devem ser tratados automaticamente como fontes primárias;
- novas funcionalidades deverão ser classificadas em uma das três responsabilidades antes da implementação.

---

# Clarification

Conceitos relacionados a formas oficiais de impressão podem existir como estruturas subordinadas à Card.

Entretanto, eles não compõem a hierarquia editorial principal e não alteram a contagem oficial das posições catalográficas de um Set.

A definição definitiva desse conceito será tratada separadamente.

---

# Related Documents

- `../04-domain-model.md`
- `../02-architecture-principles.md`
- `ADR-004-set-identity.md`
- `ADR-005-catalog-language-model.md`