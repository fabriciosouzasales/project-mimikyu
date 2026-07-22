# ADR-009 — Card Variant Scope

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-009 |
| **Título** | Card Variant Scope |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Card Variant é restrita a diferenças físicas de acabamento sobre a mesma posição catalográfica de uma Card (ex.: Standard, Reverse Holo). Formas de impressão com número, arte e raridade próprios (Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold, Rainbow) são Cards independentes, não Card Variants. |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-004-set-identity.md` |

---

# Context

Um ciclo anterior de modelagem havia levantado uma questão em aberto: um exemplo hipotético (`Mega Charizard X ex 125/094 Full Art` vs. `125/094 Rainbow Rare`, com o mesmo número) sugeria que a regra de identidade "Set + Número da Card" (ADR-004) poderia não ser suficiente, isoladamente, para diferenciar formas de impressão de uma Card.

A investigação histórica que resolveu essa questão analisou exemplos reais do catálogo Pokémon TCG:

- **`025/132` — Pikachu**: possui versões `Standard` e `Reverse Holo`. Mesmo número, mesma arte, mesma raridade — apenas o acabamento físico muda. Aqui existe, de fato, uma variação de acabamento sobre a mesma posição catalográfica.
- **`187/132` — Charizard ex (Secret Rare)**: não possui versão Standard. A própria Card já é uma impressão específica — não há Card Variant nesse caso.
- **`173/132` e `174/132` — dois Charizards do ME1**: são duas posições catalográficas distintas, cada uma com número oficial próprio. Nenhum colecionador trataria `174` como variante de `173` — são duas Cards.

Esse último ponto foi decisivo: quando se afirma que "o Set ME1 possui 188 cards" (e não "188 variantes"), o próprio catálogo oficial do Pokémon TCG já trata posições como Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold e Rainbow como Cards numeradas independentemente — cada uma com seu próprio número, arte e raridade.

Esta conclusão é consistente com uma decisão já registrada independentemente por Fabrício como consolidada: *"Full Art, Illustration Rare, Special Illustration Rare, Gold e similares não devem ser tratados automaticamente como variantes; quando possuem número, arte e posição próprios, são Cards distintas."*

---

# Decision

**Card Variant** é restrita a diferenças físicas de acabamento (finish) sobre a **mesma** posição catalográfica de uma Card — mesmo número, mesma arte, mesma raridade, mesmo registro editorial. Exemplos: Standard, Reverse Holo, Cosmos Holo, Mirror.

Formas de impressão que possuem número, arte ou raridade próprios — como Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold e Rainbow — **não são Card Variants**. São Cards independentes, regidas pela regra de identidade padrão "Set + Número da Card" (ADR-004), sem necessidade de tratamento especial ou de exceção a essa regra.

Não é necessária nenhuma exceção ou extensão à regra de identidade estabelecida em ADR-004: ela permanece suficiente, isoladamente, para toda posição catalográfica do domínio.

---

# Consequences

## Benefícios

- a regra de identidade "Set + Número da Card" (ADR-004) permanece única e sem exceções;
- o escopo de Card Variant torna-se pequeno e previsível — a maioria das Cards possui apenas Standard, ou Standard + Reverse Holo;
- elimina a necessidade de uma camada de decisão adicional para classificar cada forma de impressão;
- simplifica a métrica "Quantidade de Printing Variants colecionáveis" (ver `04-domain-model.md`), que passa a ficar muito mais próxima da "Quantidade oficial de Cards" do que inicialmente estimado.

## Restrições

- toda nova forma de impressão identificada durante a modelagem deve ser avaliada quanto a possuir número, arte ou raridade próprios (Card independente) antes de ser tratada como Card Variant;
- o nome "Card Variant" é o termo canônico deste conceito; "Printing Variant" e "Finish Variant" foram nomes considerados durante a modelagem histórica, mas não foram adotados — o schema físico já existente utiliza `card_variant`/`card_variant_type`.

---

# Alternatives Considered

## Tratar toda forma de impressão alternativa como Card Variant

Rejeitada por exigir uma exceção à regra de identidade de ADR-004 sempre que uma forma de impressão compartilhasse número com outra, e por inflar artificialmente a entidade Card Variant com posições que o próprio catálogo oficial já trata como Cards independentes.

## Renomear a entidade para "Finish Variant" ou "Printing Variant"

Não adotada nesta ADR. O schema físico já existente utiliza `card_variant`/`card_variant_type`; o nome canônico permanece Card Variant, com os demais nomes registrados apenas como sinônimos históricos.

---

# Related Documents

- `../04-domain-model.md`
- `ADR-004-set-identity.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão que restringe o escopo de Card Variant a diferenças de acabamento, resolvendo a questão de identidade sinalizada em aberto no ciclo anterior. |
