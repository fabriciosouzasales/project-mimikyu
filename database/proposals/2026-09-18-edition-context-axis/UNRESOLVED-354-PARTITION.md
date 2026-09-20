# As 354 NÃO RESOLVIDAS — partição disjunta e exaustiva

**`EDITION-CONTEXT-AXIS-SEMANTIC-PARTITION-UNRESOLVED-01`.** Read-only.
Tudo abaixo foi medido no LIVE; nada foi classificado por nome.

---

## 0. A contradição que originou esta rodada

O retorno anterior apresentou `74 subtype` + `70 PRINTING` + `280 outras` =
**424 ≠ 354**. Três erros somados:

| Nº | Erro | Correto |
|---|---|---|
| **E1** | `70` tratado como grupo de rows | **não é grupo**: é o *déficit* do alvo PRINTING (alvo 70 − medido 0). Não tem pertinência definida em artefato nenhum |
| **E2** | `74` apresentado como "as rows de subtype" | rows com `subtype` = **82**. O 74 era só a parte **sem** stamp (P1 73 + P2 1) |
| **E3** | `74` e `280` somados como disjuntos | intersectam em **8 rows** (`BLUE-BORDER` + stamps, em MFB) |

A `2842` carregava o mesmo defeito internamente: dizia "74 rows" e logo em
seguida listava 14 unidades que somam 82. Corrigido na seção STOP.

---

## 1. Partição disjunta — soma exata 354

Critério: composição de campos residuais da própria row. Mutuamente
exclusivo e exaustivo por construção.

| Partição | rows | Sets | Composição residual |
|---|---:|---:|---|
| **P1_SUBTYPE_PURO** | 73 | 11 | só `subtype` |
| **P2_SUBTYPE_MAIS_FOIL** | 1 | 1 | `subtype` + `foil` |
| **P3_SUBTYPE_MAIS_STAMP** | 8 | 1 | `subtype` + `stamp` (aridade 2) |
| **P4_STAMP_MAIS_FOIL** | 8 | 4 | `stamp` + `foil` |
| **P5_STAMP_PURO** | 264 | 47 | só `stamp` |
| **Σ** | **354** | 52 | |

Conferência cruzada por campo: com `subtype` = 82 · com `stamp` = 280 ·
ambos = 8 · com `foil` = 9. **82 + 280 − 8 = 354** ✓

---

## 2. Sobreposição real — as perguntas do mandato, respondidas por medição

| Pergunta | Resposta | Como foi medida |
|---|---:|---|
| Quantas das rows de `subtype` estão dentro das "70" de PRINTING? | **0** | nenhuma row candidata a tiragem carrega `subtype` |
| Quantas das candidatas a PRINTING estão em `stamp`? | **68 / 68** | 100% |
| Quantas estão em `subtype`? | **0** | |
| Quantas das "280" incluem as candidatas a PRINTING? | **68** | todas as 68 estão dentro das 280 com stamp |

O bloco de subtype e o bloco candidato a tiragem são **disjuntos**. As duas
decisões editoriais pendentes não competem pelas mesmas rows.

---

## 3. O "bloco de 70" — FALSIFICADO

O conjunto **mais amplo** de unidades com semântica plausível de tiragem
dentro do não-resolvido:

| Unidade | `raw_field` | rows | Sets | Evidência semântica existente |
|---|---|---:|---:|---|
| `PRE-RELEASE` | stamp | 35 | 33 | **NENHUMA** — nenhum artefato decide se prerelease é tiragem ou evento de distribuição |
| `WINNER` | stamp | 19 | 5 | **NENHUMA** — 8 das 19 carregam `foil=COSMOS`, o que sugere acabamento, não tiragem |
| `PLATINUM` | stamp | 12 | 4 | **NENHUMA** |
| `1ST-EDITION-SCRATCH-ERROR` | stamp | 1 | 1 | **NENHUMA** |
| `D-EDITION-ERROR` | stamp | 1 | 1 | **NENHUMA** |
| **Σ** | | **68** | | |

**68 ≠ 70, e nenhum subconjunto destas unidades soma 70.**

Por que a v1.0 chegou a 70 — e por que aquilo não existe:

- contava `PRE-RELEASE = 49`, mas **14 dessas 49** carregam também um token
  ancorado (`STAFF`, `WORLDS-*`, …) e **já estão classificadas
  EDITION_CONTEXT**. Sobram 35;
- contava `W-PROMO = 1`, que tem destino EDITION_CONTEXT **aprovado** em
  `MIGRATION-MAP-365` → `CHANNEL_WOTC_PROMO`. Não está disponível.

A soma 70 dependia de 15 rows que provadamente não pertencem ao conjunto.
A coincidência aritmética está encerrada e **não deve ser reaberta**.

**Veredito: todas as 68 → `UNRESOLVED`.** Nenhuma tem evidência semântica.

---

## 4. As 14 unidades de `subtype` — 82 rows, individualmente

Nenhuma decidida por nome. `Coexiste com stamp` é medição, não inferência.

| Unidade | rows | Set(s) | raw signature | Coexiste com stamp | Evidência |
|---|---:|---|---|:---:|---|
| `NO-E-READER` | 41 | EX1, EX2, NP | `HOLO/NORMAL/REVERSE ‖ NO-E-READER ‖ —` | não | nenhuma |
| `MISSING-EXPANSION-SYMBOL` | 16 | BASE2 | `HOLO ‖ … ‖ —` | não | nenhuma |
| `BLUE-BORDER` | 8 | MFB | `NORMAL ‖ … ‖ <POKÉMON>+POKEBALL` | **sim (8)** | nenhuma |
| `PEELABLE-DITTO` | 3 | SWSH10.5 | `REVERSE ‖ … ‖ —` | não | nenhuma |
| `JAPANESE-BACK` | 2 | ECARD1 | `NORMAL ‖ … ‖ —` | não | nenhuma |
| `NO-HOLO-ERROR` | 2 | BASE5 | `HOLO ‖ … ‖ —` | não | nenhuma |
| `PHANPHY-ERROR` | 2 | COL1 | `NORMAL/REVERSE ‖ … ‖ —` | não | nenhuma |
| `RARITY-ERROR` | 2 | EX6 | `NORMAL ‖ … ‖ —` · `REVERSE|ENERGY ‖ … ‖ —` | não (1 tem `foil`) | nenhuma |
| `D-INK-DOT-ERROR` | 1 | BASE5 | `NORMAL ‖ … ‖ —` | não | nenhuma |
| `ENERGY-SYMBOL-ERROR` | 1 | GYM2 | `HOLO ‖ … ‖ —` | não | nenhuma |
| `GOLD-BORDER` | 1 | BASE2 | `NORMAL ‖ … ‖ —` | não | nenhuma |
| `MISSING-RETREAT-COST` | 1 | EX2 | `NORMAL ‖ … ‖ —` | não | nenhuma |
| `SHIFTED-ENERGY-COST` | 1 | LC | `REVERSE ‖ … ‖ —` | não | nenhuma |
| `TEXT-ERROR` | 1 | GYM2 | `NORMAL ‖ … ‖ —` | não | nenhuma |
| **Σ** | **82** | 12 Sets | | 8 | |

Duas observações medidas que impedem tratar o bloco como homogêneo:

- **`BLUE-BORDER` (8, MFB)** é o único que coexiste com `stamp`, e os stamps
  são `BULBASAUR`/`CHARMANDER`/`PIKACHU`/`SQUIRTLE` + `POKEBALL`. A row tem
  **duas pendências**, de campos diferentes. Classificá-la pelo `subtype`
  descartaria o `stamp`, e vice-versa.
- **`RARITY-ERROR` (2, EX6)**: uma das duas é `REVERSE|ENERGY|RARITY-ERROR|`
  — carrega `foil` residual, que é estruturalmente inelegível a Edition
  Context (S7). As duas rows do mesmo token têm situação estrutural diferente.

---

## 5. As 40 unidades de `stamp` — 280 rows

Todas com `em_map365 = false`, verificado mecanicamente contra o vocabulário
completo de `MIGRATION-MAP-365` **mais** os 21 tokens exclusivos de B
congelados em `SEED-COVERAGE.md`.

| Unidade | rows | n_sets | Candidato semântico | reason_code |
|---|---:|---:|---|---|
| `25TH-CELEBRATION` | 50 | 1 | campanha | UNRESOLVED |
| `PRE-RELEASE` | 35 | 33 | evento ou tiragem | UNRESOLVED · candidato §3 |
| `COUNTDOWN-CALENDAR` | 24 | 6 | campanha | UNRESOLVED |
| `MCDONALDS` | 24 | 2 | canal | UNRESOLVED |
| `WINNER` | 19 | 5 | colocação ou tiragem | UNRESOLVED · candidato §3 |
| `BULBASAUR` | 12 | 1 | artwork de estampa | UNRESOLVED |
| `CHARMANDER` | 12 | 1 | artwork de estampa | UNRESOLVED |
| `PIKACHU` | 12 | 1 | artwork de estampa | UNRESOLVED |
| `PLATINUM` | 12 | 4 | campanha ou tiragem | UNRESOLVED · candidato §3 |
| `SQUIRTLE` | 12 | 1 | artwork de estampa | UNRESOLVED |
| `POKEMON-DAY` | 9 | 6 | evento | UNRESOLVED |
| `POKEBALL` | 8 | 1 | artwork de estampa | UNRESOLVED |
| `CITY-CHAMPIONSHIPS` | 6 | 6 | evento | UNRESOLVED |
| `NATIONAL-CHAMPIONSHIPS` | 6 | 6 | evento | UNRESOLVED |
| `STATE-CHAMPIONSHIPS` | 6 | 6 | evento | UNRESOLVED |
| `TRICK-OR-TRADE` | 6 | 2 | campanha | UNRESOLVED |
| `COMIC-CON` | 5 | 5 | evento | UNRESOLVED |
| `POP-TOURNAMENT` | 3 | 1 | evento | UNRESOLVED |
| `10TH-ANNIVERSARY` | 2 | 2 | campanha | UNRESOLVED |
| `ASIA-PROMO` | 2 | 2 | canal/região | UNRESOLVED |
| `DISTRIBUTOR-MEETING` | 2 | 1 | evento | UNRESOLVED |
| `GEN-CON` | 2 | 2 | evento | UNRESOLVED |
| `STADIUM-CHALLENGE` | 2 | 2 | evento | UNRESOLVED |
| `1ST-EDITION-SCRATCH-ERROR` | 1 | 1 | erro ou tiragem | UNRESOLVED · candidato §3 |
| `CHICAGO-2009` | 1 | 1 | evento | UNRESOLVED |
| `D-EDITION-ERROR` | 1 | 1 | erro ou tiragem | UNRESOLVED · candidato §3 |
| `DESTINY-DEOXYS` | 1 | 1 | campanha | UNRESOLVED |
| `GAMES-EXPO` | 1 | 1 | evento | UNRESOLVED |
| `INQUEST-GAMER` | 1 | 1 | canal | UNRESOLVED |
| `KRAZE-CLUB` | 1 | 1 | canal | UNRESOLVED |
| `NINTENDO-WORLD` | 1 | 1 | canal/evento | UNRESOLVED |
| `ORIGINS` | 1 | 1 | evento | UNRESOLVED |
| `ORIGINS-2008` | 1 | 1 | evento | UNRESOLVED |
| `PIKACHU-TAIL` | 1 | 1 | campanha | UNRESOLVED |
| `POKE-BALL-LEAGUE` | 1 | 1 | programa | UNRESOLVED |
| `POKEMON-ROCKS-AMERICA` | 1 | 1 | evento | UNRESOLVED |
| `SCRYE` | 1 | 1 | canal | UNRESOLVED |
| `THANK-YOU` | 1 | 1 | campanha | UNRESOLVED |
| `WIZARD-WORLD-CHICAGO` | 1 | 1 | evento | UNRESOLVED |
| `WIZARD-WORLD-PHILADELPHIA` | 1 | 1 | evento | UNRESOLVED |

A coluna "candidato semântico" é **descritiva e não normativa** — nenhuma
linha desta tabela classifica nada. `ORIGINS` (1) e `ORIGINS-2008` (1) são
unidades distintas e não foram fundidas.

---

## 6. Reconciliação

| | rows |
|---|---:|
| Partição disjunta P1–P5 | **354** |
| Classificado nesta rodada | **0** |
| **UNRESOLVED** | **354 / 354** |

O gate `FINISH +22 · PRINTING +70 · EDITION_CONTEXT +262` permanece **futuro**
e não foi tocado. Registre-se, porém, o que a §3 estabelece: o alvo PRINTING
de 70 **não é satisfazível** por nenhum subconjunto das unidades disponíveis
— o máximo plausível é 68. Isso é dado novo para quando esse gate for
reaberto.

---

## 7. Contradições encontradas

1. **Cabeçalho da `2842` v2.0 vs. sua própria seção STOP** — o STOP dizia
   "74 rows, 14 unidades" e listava unidades que somam 82. **Corrigido.**
2. **`70` usado como grupo de rows** — não tem pertinência em artefato nenhum;
   é déficit de alvo. **Corrigido** na `2842` e aqui.
3. **`PRE-RELEASE` contado duas vezes em papéis incompatíveis** — 49 no
   resíduo bruto, mas 14 já classificadas EDITION_CONTEXT por token ancorado.
   Usar 49 como candidato a PRINTING contradizia a própria regra V6 da v2.0.
   **Falsificado** na §3.
4. **`W-PROMO` listado como candidato a PRINTING na v1.0** enquanto tem
   destino EDITION_CONTEXT aprovado em `MIGRATION-MAP-365`. **Falsificado.**
