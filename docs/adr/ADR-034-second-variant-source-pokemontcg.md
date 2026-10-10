# ADR-034 — Segunda fonte de Card Variants: Pokémon TCG API (pokemontcg.io)

| Campo | Valor |
|---|---|
| **Status** | Aprovado (2026-10-09, Fabrício) — revisado no mesmo dia para fonte congelada (v0.2) |
| **Decisão de origem** | Fabrício, 2026-10-09: "pokemontcg.io como 2ª fonte" (`CATALOG-VARIANT-COVERAGE-GAP-01`) |
| **Relaciona** | ADR-028 (governança de Card Variant), proposta `2026-10-09-variant-coverage-gap` |

## Contexto

6.727 cartas não têm nenhuma Card Variant, e sem variante não podem entrar em Collections. O TCGdex,
fonte única do Variant Import, não declara variantes para as eras BW/XY/SM, para promos e para os
especiais. O objeto `variants` que ele expõe nessas coleções é um default do compilador. A sonda de
2026-10-09 mostrou que a Pokémon TCG API (asset_source `POKEMON_TCG_API`, já cadastrada e sem uso)
lista as variantes por carta em 98,6% das cartas medidas.

## Decisão

1. **A Pokémon TCG API passa a ser a segunda fonte de variantes**, usando o mesmo pipeline de staging
   (`catalog_variant_import_job/row`), o mesmo resolver de três eixos e o mesmo decide/confirm.
   O código da fonte é `POKEMON_TCG_API`.
2. **Precedência (deny by default):** o TCGdex continua sendo a fonte das coleções que ele cobre. A
   segunda fonte só atua sobre **cartas sem nenhuma Card Variant**. O guard fica no servidor e é
   avaliado por carta no momento do staging e de novo no confirm. Nenhuma variante existente é
   alterada ou duplicada por esta fonte.
3. **Sinal de variante:** as chaves de `tcgplayer.prices` da carta. O dado bruto é preservado na
   linha. O vocabulário entra por `card_variant_type_external_mapping` do asset_source:
   `NORMAL`→STANDARD, `HOLOFOIL`→HOLO, `REVERSEHOLOFOIL`→REVERSE_HOLO. Qualquer outra chave
   (`1STEDITION*`, `UNLIMITED*`, novas) não tem mapping e cai em `NEEDS_REVIEW`.
4. **Carta sem preço não ganha variante padrão.** Ela é registrada como sem fonte e fica na lista.
5. **Correspondência:** `card_set_external_reference` explícita (coleção nossa ↔ `set.id` deles,
   curada e versionada) + número de coleção normalizado (maiúsculas, zeros à esquerda removidos em
   cada sequência de dígitos: `001`→`1`, `XY01`→`XY1`, `SV1`→`SV1`). Ambiguidade ou ausência
   bloqueia a carta. Nome de carta nunca é usado como chave.
6. **Fonte congelada (v0.2).** A Pokémon TCG API foi descontinuada: não há contas novas, e as chaves
   existentes funcionam até 01/03/2027 (Scrydex é a sucessora paga). As coleções do gap são históricas
   e não mudam mais. Por isso a fonte é um **snapshot único**, obtido pela API pública sem chave e
   versionado no repositório (`database/seeds/sources/pokemontcg-snapshot-2026-10-09/`), com hash e
   contagem por coleção. O staging é carregado desse arquivo. Não há dependência de rede em tempo
   de execução, nem chave, nem segredo.
7. **Integridade do snapshot:** uma coleção só entra no snapshot completa (contagem igual ao
   `totalCount` da fonte). O arquivo é imutável depois de commitado; uma correção gera um snapshot
   novo, com data.

## Consequências

- Fecha a maior parte do gap: BW/XY/SM, especiais, promos BW/XY/SWSH/SV e SWSH1/SWSH3.5.
- **Trainer Kits (270)** continuam sem fonte e ficam fora desta decisão.
- `catalog_variant_import_job.source` deixa de ser só `TCGDEX`: o CHECK passa a aceitar
  `POKEMON_TCG_API`. Callers que filtram `source = 'TCGDEX'` continuam corretos.
- As chaves de preço são um proxy de variantes impressas. Erros pontuais da fonte entram como
  identidade errada. A mitigação é a checagem cruzada com a regra era × raridade antes do confirm,
  com divergências indo para revisão.

## Alternativas rejeitadas

- Regra era × raridade sozinha: não distingue Rara de Rara Holo em pt-BR (1.356 cartas).
- Variante padrão (STANDARD) para todas: fabrica identidade e omite as reversas.
- TCGdex em inglês: separa a Rara, mas continua sem variantes.

## Revision History

| Versão | Descrição |
|---|---|
| 0.1 | **Proposta (2026-10-09).** Criada a partir da sonda de cobertura (`CATALOG-VARIANT-COVERAGE-GAP-01`). |
| 0.2 | **Aprovada e revisada (2026-10-09).** A API foi descontinuada (aviso oficial; chaves só até 01/03/2027). Por decisão de Fabrício, a fonte vira snapshot único versionado no repositório; saem a chave/segredo e o retry em tempo de execução. |
