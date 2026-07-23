# ADR-010 — Card Rarity and Finish Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-010 |
| **Título** | Card Rarity and Finish Model |
| **Status** | Substituído (parcialmente — ver ADR-016) |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Rarity é um atributo de primeira classe da Card. O conceito antes chamado "Card Variant" é retirado do vocabulário conceitual e substituído por Finish (catálogo de acabamentos físicos) e Card Finish (associação entre uma Card e um Finish disponível). Inventory Item passa a referenciar uma Card Finish, não a Card diretamente. |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-004-set-identity.md`, `ADR-009-card-variant-scope.md`, `ADR-016-card-variant-naming-convention.md` |

---

# Context

> **Nota (ADR-016):** a parte desta ADR que retirava "Card Variant" do vocabulário conceitual em favor de "Finish"/"Card Finish" foi **revertida** por `ADR-016-card-variant-naming-convention.md` — o vocabulário conceitual do domínio volta a usar Card Variant Type/Card Variant, convergindo com o nome já usado no schema físico. A **outra** decisão desta ADR — Rarity como atributo de primeira classe da Card, distinto de acabamento — **permanece válida** e não foi alterada. Este texto é preservado sem alteração como registro histórico da decisão original.

ADR-009 já havia restringido o escopo do então chamado "Card Variant" a diferenças de acabamento sobre a mesma posição catalográfica, e havia estabelecido que formas de impressão como Full Art e Rainbow Rare são Cards independentes. Essa conclusão permanece correta.

O que faltava era um documento oficial que comprovasse, de forma definitiva, por que essas formas de impressão são Cards independentes — e não apenas "grandes variantes". Esse documento foi fornecido: a lista oficial de cartas do Set ME1 (`assets/reference-sources/P10346_ME01_Card_List_PTBR.pdf`).

O documento oficial mostra que cada linha numerada (`001` a `188`) é acompanhada por dois elementos visuais distintos:

1. **Um símbolo de raridade** (à direita de cada linha), cuja legenda apresenta categorias como Common, Uncommon, Rare, Double Rare, Ultra Rare, Illustration Rare, Special Illustration Rare e Mega Hyper Rare.
2. **Caixas de seleção de acabamento** (Standard / Standard Foil), indicando em quais acabamentos aquela Card específica está disponível.

Isso comprova que **três conceitos estavam sendo tratados como um só**:

- **Card**: cada linha numerada do catálogo (ex.: `001 — Bulbasaur`, `003 — Mega Venusaur ex`, `133 — Bulbasaur`). Números diferentes = Cards diferentes, mesmo quando o nome se repete (`001 — Bulbasaur` e `133 — Bulbasaur` são Cards distintas).
- **Rarity**: a classificação de raridade da Card (o símbolo). Illustration Rare, Special Illustration Rare e Ultra Rare são valores de raridade, não "variações de impressão".
- **Finish**: o acabamento físico disponível para aquela Card (as caixas de seleção). Não altera número, posição, raridade, nome ou identidade editorial da Card.

---

# Decision

## Rarity (Raridade)

Passa a ser um atributo/relação de primeira classe da Card, com valores controlados (Common, Uncommon, Rare, Double Rare, Ultra Rare, Illustration Rare, Special Illustration Rare, Mega Hyper Rare, entre outros a confirmar em Sets futuros). Cada Card possui exatamente uma Rarity.

## Finish (Acabamento) e Card Finish (Acabamento da Carta)

O conceito antes chamado **Card Variant** (e informalmente "Printing Variant") é retirado do vocabulário conceitual do domínio. É substituído por dois conceitos relacionados:

- **Finish**: catálogo controlado de acabamentos físicos possíveis (ex.: Standard, Standard Foil, e outros a confirmar).
- **Card Finish**: declara que uma Card específica está disponível em um Finish específico. Relação: `Card 1 → N Card Finish`, cada Card Finish referenciando 1 Finish.

Os termos **"Printing Variant"** e **"Finish Variant"** são descartados definitivamente do vocabulário conceitual — a palavra "variant" sugeria (incorretamente) a criação de uma versão editorial derivada da Card.

## Relação com Inventory Item

Um exemplar físico do usuário (Inventory Item) passa a referenciar uma **Card Finish** específica, e não a Card diretamente — já que é necessário saber em qual acabamento o exemplar foi impresso:

```text
Card
  ↓
Card Finish
  ↓
Inventory Item
```

## Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold, Rainbow

Confirma-se, agora com apoio documental oficial: essas formas de impressão **não são Finish nem Card Finish**. São **Cards independentes**, cada uma com número, arte e Rarity próprios, regidas normalmente pela regra de identidade "Set + Número da Card" (ADR-004), sem necessidade de tratamento especial.

---

# Consequences

## Benefícios

- elimina a ambiguidade entre raridade e acabamento físico, que estavam sendo tratados como a mesma dimensão;
- Rarity passa a ser um dado oficial explícito e rastreável, alinhado ao schema físico já existente (tabela `rarity`);
- o escopo de Finish/Card Finish fica pequeno e previsível — a maioria das Cards possui apenas Standard, ou Standard + Standard Foil;
- a relação Card → Card Finish → Inventory Item permite saber exatamente qual acabamento cada exemplar físico do usuário representa;
- decisão fundamentada em documento oficial primário, reduzindo o risco de reinterpretação futura.

## Restrições

- toda nova forma de impressão identificada durante a modelagem deve ser avaliada quanto a possuir número, arte ou Rarity próprios (Card independente) antes de ser tratada como Finish;
- a lista de valores de Rarity e de Finish apresentada neste documento reflete apenas o que foi observado no Set ME1 até o momento e não deve ser considerada exaustiva;
- **nomenclatura física em aberto**: o schema físico já existente utiliza as tabelas `card_variant` e `card_variant_type`, nomeadas antes deste refinamento conceitual. Esta ADR não decide se essas tabelas físicas serão renomeadas para refletir "Finish"/"Card Finish" — essa decisão fica para o ciclo de modelagem física (`05-modelo-de-dados.md`).

---

# Alternatives Considered

## Manter "Card Variant" como nome canônico (ADR-009)

Rejeitada. Embora o schema físico já usasse esse nome, o documento oficial evidenciou que "Card Variant" misturava duas dimensões conceitualmente distintas (Rarity e Finish), tornando o nome impreciso mesmo com o escopo já restrito por ADR-009.

## Tratar raridade como parte do Finish

Rejeitada. Raridade não é uma característica de acabamento físico — é uma classificação editorial oficial que não muda entre os acabamentos disponíveis de uma mesma Card.

---

# Related Documents

- `../04-domain-model.md`
- `ADR-004-set-identity.md`
- `ADR-009-card-variant-scope.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão que separa Rarity e Finish/Card Finish, substituindo o conceito "Card Variant" de ADR-009, com base em documento oficial (lista de cartas do ME1). |
| 1.1 | Status alterado para Substituído (parcialmente). Adicionada nota de referência cruzada apontando para ADR-016, que reverte a nomenclatura Finish/Card Finish de volta para Card Variant Type/Card Variant. A decisão sobre Rarity como atributo de primeira classe da Card permanece válida e não foi alterada. Nenhum conteúdo original foi alterado. |
