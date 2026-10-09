# Remedição das `NEEDS_REVIEW` de Card Variants (2026-10-09)

Leituras read-only autorizadas por Fabrício: `NR-REMEASURE-01`, `NR-REMEASURE-02` e `NR-DRYRUN-01` (seção no fim), executadas pelo Claude via MCP do Supabase. Nenhuma escrita.

- A `NR-REMEASURE-02` v1.0 falhou sem efeito (`jsonb_array_length` sobre escalar).
- A v1.1, com a guarda via `CASE`, rodou normalmente.

**Universo:** igual ao da 2212, ou seja, staging de variantes com job vivo e `persistence_status = PENDING`.

## Resultado

| Item | Valor |
|---|---|
| `NEEDS_REVIEW` | **1.642**, igual ao baseline de 2026-09-18 |
| Outras linhas no universo | 48 `VALID/PENDING` + 64 `VALID/SKIPPED` |
| Jobs vivos | 64, todos `STAGED` |
| Card Sets afetados | 62 (maiores: EX7 123, EX8 123, EX10 121, EX9 116, EX1 67, HGSS1 59) |
| Assinaturas brutas distintas | 215 |
| `error_detail` | vazio nas 1.642 |

**Estado dos eixos**

- Acabamento: **não resolvido nas 1.642** (sem mapeamento da assinatura residual para `card_variant_type`).
- Tiragem: `null` em 1.641, UUID em 1.
- Edition Context: UUID em 1.092, `null` em 549. Esses valores vêm da 2212/2233.

## Famílias (atributos brutos da fonte)

| Família | Ocorrências | Observação |
|---|---|---|
| `stamp` = `set-logo` (reverse) | 388 | 8 Sets; relaciona-se com `SET_LOGO_REVERSE` (Pricing 80) |
| Assinatura de jogador (World Championship Decks) | 709 | 38 nomes; o maior é `jason-klaczynski` (43) |
| Evento, promo ou loja | 316 | `25th-celebration` 50, `pre-release` 49, `staff` 46, `countdown-calendar` 24, `mcdonalds` 24, entre outros |
| Torneio ou colocação | 142 | `winner` 19, `worlds-20xx`, `national/state/city-championships`, `finalist`… |
| Edição/erro de impressão via `stamp` | 3 | `1st-edition`, `1st-edition-scratch-error`, `d-edition-error` |
| Sem `stamp`: `foil` especial | — | `league` 53, `cracked-ice` 38, `cosmos` 9, `energy` 3, `player-reward` 2, `professor-program` 2 |
| Sem `stamp`: `subtype` de erro/variação | — | `no-e-reader` 41, `missing-expansion-symbol` 16, `blue-border` 8 e mais 10 tipos com 1–3 cada |

As contagens de `stamp` somam 1.558 ocorrências em 1.478 linhas, porque 80 linhas têm mais de um carimbo (ex.: `pre-release` + `staff`). Há 164 linhas sem `stamp`.

Por `type`: `normal` 945, `reverse` 460, `holo` 237.

## NR-DRYRUN-01 — o que cada linha precisa de verdade (2026-10-09)

A query reavalia cada linha com o vocabulário atual: eixos `2211`, depois mapping de acabamento `2192`, na mesma lógica do worker `2219`. Foi só leitura, autorizada por Fabrício. O resultado está em `NR-DRYRUN-01.result.json`.

| Classe | Linhas | Significado |
|---|---:|---|
| **A — automática** | **1.086** | Os três eixos já se resolvem hoje. A linha só segue `NEEDS_REVIEW` porque nunca foi reavaliada depois das seeds de Edition Context. |
| **B — falta acabamento** | **556** | Tiragem e Edition Context resolvidos, mas não há mapping de acabamento para o resíduo. |
| C — Edition Context pendente | 0 | |
| D — tiragem pendente | 0 | |

Na classe A, o acabamento que seria atribuído fica assim:

| Acabamento | Linhas |
|---|---:|
| `STANDARD` | 897 |
| `HOLO` | 164 |
| `REVERSE_HOLO` | 16 |
| `COSMOS_REVERSE` | 4 |
| `COSMOS_HOLO` | 4 |
| `STANDARDS_LEAGUE` | 1 |

A classe B se reduz a **27 unidades de decisão** (assinaturas residuais):

| Unidade | Linhas | Natureza já decidida (`2842` / `SEMANTIC-PARTITION-DECISIONS-54`) |
|---|---:|---|
| `reverse` + `stamp:set-logo` | 383 | 379 em EX7–EX10 = FINISH, retidas no HOLD H2. As outras 4 são INDETERMINATE (V3B) |
| `foil:league` (`reverse` 45 / `holo` 7) | 52 | `foil` de programa, retida no HOLD H3. A 57ª linha do H3 já resolveria sozinha como `STANDARDS_LEAGUE`, e isso precisa ser bloqueado: HOLD não pode ser movido pela reavaliação |
| `holo` + `foil:cracked-ice` | 38 | FINISH |
| `subtype` de erro de impressão (`no-e-reader` 41, `missing-expansion-symbol` 16, outros 12) | 69 | PRINTING. Falta o mapping de tiragem, e por isso o token ficou no resíduo de acabamento |
| `stamp` de erro de edição (`1st-edition-scratch-error`, `d-edition-error`) | 2 | PRINTING |
| `foil:energy` (2 `holo` + 1 `reverse` que também tem `rarity-error`) | 3 | FINISH, exceto a linha com `rarity-error`, que é PRINTING (mesma conta de 41 da `2842`) |
| `foil:player-reward` / `foil:professor-program` | 4 | `foil` de programa, retida no HOLD H3 |
| `subtype:peelable-ditto` | 3 | FINISH |
| `normal` + `foil:cosmos` | 1 | FINISH |
| `stamp:pikachu-tail` | 1 | HOLD_EDITORIAL |

**Leitura:** dois terços do resíduo não exigem decisão editorial. Eles precisam apenas de uma **reavaliação** com o vocabulário vigente. As decisões que restam são poucas e grandes: as duas retenções (H2 e H3), que somam 439 linhas, e o vocabulário de tiragem para os `subtype` de erro.
