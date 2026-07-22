# ADR-007 — Card Translation Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-007 |
| **Título** | Card Translation Model |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | O conteúdo editorial de uma Card que varia por idioma (nome, texto de regras, ataques, habilidades, descrições) será representado por uma entidade subordinada, Card Translation, sem duplicar a identidade da Card. |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-004-set-identity.md`, `ADR-005-catalog-language-model.md`, `../architecture/ubiquitous-language.md` |

---

# Context

ADR-005 já havia estabelecido que o idioma não faz parte da identidade editorial do catálogo, e que Set e Card não são duplicados por idioma. Essa mesma ADR deixou registrada uma evolução futura em aberto:

> "Caso diferenças editoriais relevantes entre idiomas precisem ser representadas futuramente, poderá ser introduzido um conceito subordinado (...), preservando a identidade do Set."

Durante a modelagem, observou-se que resultados de busca em inglês e português (por exemplo, "Lysandre Labs" e "Laboratórios Lysandre") retornam a mesma posição catalográfica (`092/094`). Isso confirmou que o nome traduzido não cria uma nova posição catalográfica — mas também evidenciou que o texto traduzido precisa de um local oficial no catálogo, e não apenas no exemplar físico do usuário (Inventory Item).

Identificaram-se duas categorias distintas de informação linguística:

- **Tradução editorial**: nome da carta, texto de regras, ataques, habilidades, descrições e, eventualmente, nomes de categorias. Pertence ao catálogo.
- **Idioma do exemplar físico**: qual versão impressa um usuário efetivamente possui. Pertence ao patrimônio do usuário (Inventory Item), conforme já definido em ADR-006.

---

# Decision

Foi introduzida a entidade **Card Translation (Tradução da Carta)**, subordinada à Card:

```text
Card
 1
 │
 └── N Card Translation
```

Cada Card pode possuir uma Card Translation por idioma suportado pelo catálogo, contendo o conteúdo editorial traduzido correspondente (nome, texto de regras, ataques, habilidades, descrições, e outros campos textuais oficiais).

Card Translation:

- não é uma nova Card;
- não é uma nova posição catalográfica;
- não é uma Card Variant;
- não representa o idioma de um exemplar físico.

O idioma do exemplar físico continua pertencendo exclusivamente ao Inventory Item, conforme ADR-006.

---

# Consequences

## Benefícios

- o catálogo passa a conhecer oficialmente o conteúdo editorial de uma Card em mais de um idioma;
- a identidade da Card permanece única, independentemente da quantidade de idiomas suportados;
- elimina a necessidade de duplicar Card ou Set por idioma para representar textos traduzidos;
- separa claramente "o que o catálogo sabe" (Card Translation) de "o que o usuário possui" (Inventory Item).

## Restrições

- toda nova informação textual que varie por idioma deve ser avaliada quanto a pertencer a Card Translation, e não a campos fixos da Card;
- a ausência de uma Card Translation para um idioma não deve ser interpretada como ausência da Card nesse idioma — pode apenas refletir dado ainda não catalogado.

---

# Alternatives Considered

## Duplicar a Card por idioma

Rejeitada por violar a decisão já consolidada em ADR-004 e ADR-005 de que a identidade da Card não muda conforme o idioma.

## Armazenar o nome traduzido apenas no Inventory Item

Rejeitada porque o catálogo precisa conhecer os nomes oficiais em todos os idiomas suportados, independentemente de qualquer usuário possuir um exemplar físico naquele idioma.

---

# Related Documents

- `../04-domain-model.md`
- `ADR-004-set-identity.md`
- `ADR-005-catalog-language-model.md`
- `../architecture/ubiquitous-language.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão de introduzir Card Translation como resolução da evolução futura prevista em ADR-005. |
