# As 54 unidades — decisão semântica final

**`EDITION-CONTEXT-AXIS-SEMANTIC-PARTITION-FINAL-DECISION-01`.** Read-only.
Todas as 54 unidades decididas. **Zero rows com conflito de natureza** (gate
medido: uma row nunca recebe duas naturezas por tokens diferentes).

| Natureza | rows |
|---|---:|
| EDITION_CONTEXT | 278 |
| PRINTING | 72 |
| FINISH | 3 |
| HOLD_EDITORIAL | 1 |
| **Σ** | **354** |

---

## 0. A autoridade usada — e por que ela decide

A rodada anterior parou por falta de critério. Ele existia, versionado, e não
tinha sido lido: **o vocabulário de Printing já aprovado no LIVE**
(`card_printing_trait` / `card_printing_profile` / `card_printing_external_mapping`,
Queries `2169` e `2201`). Ele resolve as duas ambiguidades que travavam tudo.

### A1 — `subtype` de erro/variação impressa JÁ é PRINTING no projeto

Mappings de Printing ativos em `raw_field='subtype'`:
`SHADOWLESS` · `SHADOWLESS-RED-CHEEK` · `UNLIMITED` · `1999-2000-COPYRIGHT` ·
`AOKI-ERROR` · `EVOLUTION-BOX-ERROR` · `GLOSSY`.

As descrições dos traits são literais e decidem o caso:

- `EVOLUTION_BOX_ERROR` — *"**Erro de chapa** produzido em massa e corrigido em
  tiragem posterior — **variedade de tiragem catalogada, não defeito de
  exemplar**."*
- `AOKI_CREDIT` — *"Erro de **conteúdo impresso** … corrigido em tiragem
  posterior."*
- `GREY_STAR_SYMBOL` — *"Característica do **símbolo de coleção impresso**, não
  de selo aplicado após a impressão."*
- `GLOSSY_STOCK` — *"**Característica de tiragem, não de acabamento** de arte
  nem de selo."*
- `RED_CHEEK` — *"**Característica de arte impressa**: bochechas em vermelho em
  vez de amarelo."*
- `SHADOWLESS` — *"Impressão sem a sombra à direita da **moldura** da arte."*

Consequência normativa: no modelo deste projeto, **erro de chapa, erro de
conteúdo impresso, símbolo impresso, card stock e até diferença de arte
impressa são PRINTING — explicitamente NÃO são acabamento.** Isso prova a
hipótese PRINTING do mandato para os 11 tokens de erro/variação física.

### A2 — a bifurcação de `stamp`

Todo `stamp` com destino aprovado cai em exatamente um de dois grupos:

| grupo | destino | instâncias aprovadas |
|---|---|---|
| stamp que identifica a **tiragem / o símbolo de coleção impresso** | PRINTING | `1ST-EDITION` · `1ST-EDITION-ERROR` · `GREY-STAR` |
| stamp que identifica **onde / por que / para quem aquela cópia circulou** | EDITION_CONTEXT | `STAFF`→`ROLE_STAFF` · `REGIONAL-CHAMPIONSHIPS`→`EVENT_REGIONALS` · `GAMESTOP`/`EB-GAMES`/`W-PROMO`→`CHANNEL_*` · `PLAYER-REWARDS-PROGRAM`/`PROFESSOR-PROGRAM`→`PROGRAM_*` · `WORLDS-*`→`EVENT_WORLDS_*` · `TOP-*`/`FINALIST`→`PLACEMENT_*` · `SET-LOGO`→`ARTWORK_SET_LOGO` |

Essa bifurcação é derivada, não inventada: é a leitura exaustiva dos mappings
existentes. É ela que classifica os 40 stamps.

---

## 1. SUBTYPE — 14 unidades, 82 rows

### 1.1 Hipótese FINISH do mandato: 1 PROVADA, 2 REFUTADAS

| Unidade | rows | Set | Evidência | Hipótese | Decisão | Conf. |
|---|---:|---|---|---|---|---|
| `PEELABLE-DITTO` | 3 | SWSH10.5 (Pokémon GO) | `raw_data`: Spinarak 006, Numel 013, Bidoof 059, todas `reverse`. São as cartas de Ditto com **camada destacável** — construção física do exemplar, presente em todo exemplar, não variante de tiragem | FINISH | **FINISH** ✅ | ALTA |
| `BLUE-BORDER` | 8 | MFB (My First Battle) | Co-ocorre 8/8 com `stamp:pokeball`, sempre nos 4 iniciais e nas 4 Energias básicas. Fonte pública: a borda azul + selo Poké Ball marcam o **"First Pokémon" e a "Starting Energy"** de cada deck — designação de papel dentro do produto | FINISH | **EDITION_CONTEXT** ❌ | ALTA |
| `GOLD-BORDER` | 1 | BASE2 Selva · #56 Meowth | Fonte pública: variante de borda dourada distribuída em **caixas de Pokémon Fruit Rolls**, dez/1999 — canal promocional | FINISH | **EDITION_CONTEXT** ❌ | ALTA |

**Por que as duas bordas não são FINISH.** O critério do próprio mandato:
*"FINISH somente quando a marca for tratamento/decorativo físico **sem
significado contextual independente**."* Ambas as bordas têm significado
contextual independente e verificável — papel no deck (MFB) e canal de
distribuição (Fruit Rolls). Além disso nenhuma é
tratamento/material/superfície/substrato: é moldura impressa.

`PEELABLE-DITTO` passa nos dois testes: é **material** (camada física
destacável) e não carrega contexto.

### 1.2 Hipótese PRINTING do mandato: 11 PROVADAS

Todas pelo precedente A1. Nenhuma foi aceita por soma.

| Unidade | rows | Set(s) | Evidência | Decisão | Conf. |
|---|---:|---|---|---|---|
| `NO-E-READER` | 41 | EX1, EX2, NP | tiragem sem a faixa de dot-code do e-Reader — **run/version**; irmão de `GREY_STAR_SYMBOL` (símbolo impresso presente/ausente) | PRINTING | ALTA |
| `MISSING-EXPANSION-SYMBOL` | 16 | BASE2 (Selva) | símbolo de expansão ausente na tiragem inicial de Selva — **erro de chapa corrigido em tiragem posterior**; irmão direto de `EVOLUTION_BOX_ERROR` | PRINTING | ALTA |
| `JAPANESE-BACK` | 2 | ECARD1 · Pichu 058, Hoppip 112 | verso japonês em frente inglesa — chapa de verso trocada, variedade catalogada | PRINTING | MÉDIA |
| `NO-HOLO-ERROR` | 2 | BASE5 (Time Rocket) | holo ausente por falha de chapa — irmão de `EVOLUTION_BOX_ERROR` | PRINTING | ALTA |
| `PHANPHY-ERROR` | 2 | COL1 | erro de conteúdo impresso — irmão de `AOKI_CREDIT` | PRINTING | ALTA |
| `RARITY-ERROR` | 2 | EX6 | símbolo de raridade impresso errado — irmão de `GREY_STAR_SYMBOL` | PRINTING | ALTA |
| `D-INK-DOT-ERROR` | 1 | BASE5 | artefato de tinta da chapa | PRINTING | ALTA |
| `ENERGY-SYMBOL-ERROR` | 1 | GYM2 | símbolo impresso errado | PRINTING | ALTA |
| `MISSING-RETREAT-COST` | 1 | EX2 | conteúdo impresso ausente | PRINTING | ALTA |
| `SHIFTED-ENERGY-COST` | 1 | LC | registro de chapa deslocado | PRINTING | ALTA |
| `TEXT-ERROR` | 1 | GYM2 | texto impresso errado | PRINTING | ALTA |
| **Σ** | **70** | | | | |

> Nota estrutural: uma das 2 rows de `RARITY-ERROR` é
> `REVERSE|ENERGY|RARITY-ERROR|` — carrega `foil` residual. A row vai para
> PRINTING pelo `subtype`; o `foil` continua sendo pendência do eixo Finish
> **na mesma row**, e isso não muda a natureza dela.

---

## 2. STAMP — 40 unidades, 280 rows

### 2.1 PRINTING — 2 unidades, 2 rows

| Unidade | rows | Set | Evidência | Decisão | Conf. |
|---|---:|---|---|---|---|
| `1ST-EDITION-SCRATCH-ERROR` | 1 | BASE2 | selo de 1ª Edição defeituoso — **irmão literal** do mapping aprovado `stamp:1ST-EDITION-ERROR` (criado no BASEP) | PRINTING | ALTA |
| `D-EDITION-ERROR` | 1 | BASE2 | selo de edição impresso como "d Edition" — mesma família | PRINTING | ALTA |

### 2.2 HOLD_EDITORIAL — 1 unidade, 1 row

| Unidade | rows | Set | Evidência | Decisão |
|---|---:|---|---|---|
| `PIKACHU-TAIL` | 1 | BASE2 · #60 Pikachu | **decisão versionada existente**: o `README` do staging BASEP registra `holo + pikachu-tail` como `DEFER_CANDIDATE` / **`SOURCE_CONTRADICTION`**, após a investigação `BASEP-EXT-EVIDENCE-01 §A`. O veredito editorial já tomado é "não resolvível pela fonte" | **HOLD_EDITORIAL** |

### 2.3 EDITION_CONTEXT — 37 unidades, 277 rows

Todas pela bifurcação A2: o stamp diz **onde/por que/para quem** a cópia
circulou, e nenhuma identifica tiragem ou símbolo de coleção.

| Unidade | rows | n_sets | Família semântica | Conf. |
|---|---:|---:|---|---|
| `25TH-CELEBRATION` | 50 | 1 | campanha — o Set é literalmente *McDonald's Collection 2021*, 25º aniversário | ALTA |
| `PRE-RELEASE` | 35 | 33 | evento de distribuição; mesmo padrão de `STAFF` (mesma impressão, selada para o evento) | ALTA |
| `COUNTDOWN-CALENDAR` | 24 | 6 | campanha / produto sazonal | ALTA |
| `MCDONALDS` | 24 | 2 | canal — Sets *McDonald's Collection 2012 / 2014* | ALTA |
| `WINNER` | 19 | 5 | placement — irmão de `TOP-SIXTEEN`/`FINALIST` → `PLACEMENT_*` | ALTA |
| `BULBASAUR` | 12 | 1 | deck de origem (MFB) | ALTA |
| `CHARMANDER` | 12 | 1 | deck de origem (MFB) | ALTA |
| `PIKACHU` | 12 | 1 | deck de origem (MFB) | ALTA |
| `SQUIRTLE` | 12 | 1 | deck de origem (MFB) | ALTA |
| `PLATINUM` | 12 | 4 | campanha/promoção da série Platinum sobre cartas DP4–DP7 | **MÉDIA** |
| `POKEMON-DAY` | 9 | 6 | evento | ALTA |
| `POKEBALL` | 8 | 1 | papel no produto — "First Pokémon / Starting Energy" (MFB) | ALTA |
| `CITY-CHAMPIONSHIPS` | 6 | 6 | evento — irmão de `EVENT_REGIONALS` | ALTA |
| `NATIONAL-CHAMPIONSHIPS` | 6 | 6 | evento — idem | ALTA |
| `STATE-CHAMPIONSHIPS` | 6 | 6 | evento — idem | ALTA |
| `TRICK-OR-TRADE` | 6 | 2 | campanha sazonal | ALTA |
| `COMIC-CON` | 5 | 5 | evento | ALTA |
| `POP-TOURNAMENT` | 3 | 1 | evento/programa (Pokémon Organized Play) | ALTA |
| `10TH-ANNIVERSARY` | 2 | 2 | campanha comemorativa | ALTA |
| `ASIA-PROMO` | 2 | 2 | canal/região | ALTA |
| `DISTRIBUTOR-MEETING` | 2 | 1 | evento | ALTA |
| `GEN-CON` | 2 | 2 | evento | ALTA |
| `STADIUM-CHALLENGE` | 2 | 2 | evento | ALTA |
| `CHICAGO-2009` | 1 | 1 | evento | ALTA |
| `DESTINY-DEOXYS` | 1 | 1 | campanha de filme — irmão de `CAMPAIGN_FIRST_MOVIE` | ALTA |
| `GAMES-EXPO` | 1 | 1 | evento | ALTA |
| `INQUEST-GAMER` | 1 | 1 | canal (revista) — família `CHANNEL_*` | ALTA |
| `KRAZE-CLUB` | 1 | 1 | canal | ALTA |
| `NINTENDO-WORLD` | 1 | 1 | canal/evento | ALTA |
| `ORIGINS` | 1 | 1 | evento | ALTA |
| `ORIGINS-2008` | 1 | 1 | evento — **unidade distinta**, não fundida com `ORIGINS` | ALTA |
| `POKE-BALL-LEAGUE` | 1 | 1 | programa — irmão de `PROGRAM_LEAGUE` | ALTA |
| `POKEMON-ROCKS-AMERICA` | 1 | 1 | evento | ALTA |
| `SCRYE` | 1 | 1 | canal (revista) | ALTA |
| `THANK-YOU` | 1 | 1 | campanha | ALTA |
| `WIZARD-WORLD-CHICAGO` | 1 | 1 | evento | ALTA |
| `WIZARD-WORLD-PHILADELPHIA` | 1 | 1 | evento | ALTA |

> `PLATINUM` é a **única** unidade das 54 com confiança abaixo de ALTA. O eixo
> é seguro (é stamp de circunstância, não de tiragem: aparece sobre `normal`,
> `holo` e `reverse` indiferentemente, logo é ortogonal ao acabamento). O que
> não está fechado é o **nome** da campanha — e isso é questão de E1, não de
> eixo.

---

## 3. HOLD_EDITORIAL — materialidade

| Métrica | Valor |
|---|---|
| rows | **1** |
| % sobre as 354 não resolvidas | **0,28 %** |
| % sobre as 1.642 operacionais | **0,06 %** |
| tokens | 1 (`PIKACHU-TAIL`) |
| Sets | 1 (BASE2) |
| padrão recorrente | **nenhum** — token único, Set único, já com veredito versionado `SOURCE_CONTRADICTION` |

Limiar do mandato: `> 5 % das 354` (**> 17 rows**) ou padrão sistêmico ⇒ HOLD
REPRESENTATIVO. Medido: 1 row, sem padrão.

### ⇒ **HOLD RESIDUAL**

---

## 4. Reconciliação final — **NÃO FECHA**

Partição completa das 1.642 (v2.0 + estas 354):

| Grupo | Alvo histórico | Medido | Δ |
|---|---:|---:|---:|
| FINISH | 442 | 423 | **−19** |
| PRINTING | 70 | 72 | **+2** |
| EDITION_CONTEXT | 1.069 | 1.085 | **+16** |
| INDETERMINATE | 61 | **61** | **0** ✅ |
| HOLD_EDITORIAL | — | 1 | +1 |
| **TOTAL** | **1.642** | **1.642** | **0** ✅ |

Soma dos desvios: −19 + 2 + 16 + 1 = 0. Nenhuma regra foi recalibrada.

### Quais decisões explicam a divergência

| Decisão desta rodada | Efeito no alvo | rows |
|---|---|---:|
| `BLUE-BORDER` + `GOLD-BORDER` → EDITION_CONTEXT em vez de FINISH | FINISH −9 · EC +9 | 9 |
| `1ST-EDITION-SCRATCH-ERROR` + `D-EDITION-ERROR` → PRINTING | PRINTING +2 | 2 |
| `PIKACHU-TAIL` → HOLD_EDITORIAL | HOLD +1 | 1 |
| **Explicado por esta rodada** | | **12** |
| **NÃO explicado — resíduo** | FINISH −10 · EC +7 | **17** |

**O resíduo de 17 rows não está nas 354.** Ele está no universo já classificado
na v2.0 — ou seja, aponta para uma das regras anteriores (`V5_FOIL_ONLY` 41
rows → FINISH, ou `V6_EC_ANCORADO_365` 93 rows → EC), ou para o próprio
baseline histórico.

E o baseline tem exatamente o defeito que abriu esta frente: **442 / 70 / 1.069
/ 61 nunca foi versionado como critério.** Dois sinais de que a partição por
evidência pode estar certa e o baseline errado:

1. **INDETERMINATE fecha exato (61)** por duas evidências independentes
   (HOLD-MANIFEST H3 = 57 · README §7 = 4).
2. **PRINTING saiu de 0 para 72** aplicando só precedente aprovado, chegando a
   2 rows do alvo — depois de a v1.0 e a v2.0 declararem a regra de Printing
   "não derivável".

Não é possível decidir isso por dado: é decisão de autoridade sobre qual dos
dois números vale.

---

## 5. Veredito

**DECISION GATE** — não PASS.

As 54 unidades estão decididas, com zero conflito de natureza e HOLD residual
(1 row, 0,06 %). O que impede declarar `SEMANTIC PARTITION CLOSED` é uma única
pergunta, que só Fabrício responde:

> O baseline histórico **FINISH = 442 / EDITION_CONTEXT = 1.069** é autoridade,
> ou herda o mesmo defeito de proveniência que originou esta frente?
>
> - **Se o baseline é autoridade** → reabrir `V5_FOIL_ONLY` e
>   `V6_EC_ANCORADO_365` procurando as 17 rows de diferença.
> - **Se a partição por evidência é autoridade** → o baseline é substituído por
>   **FINISH 423 · PRINTING 72 · EDITION_CONTEXT 1.085 · INDETERMINATE 61 ·
>   HOLD 1**, e a partição fecha com proveniência versionada pela primeira vez.

Nenhuma das duas saídas exige nova classificação das 54 unidades.

---

## Fontes externas consultadas (item 3 do mandato)

- MFB / borda azul + selo Poké Ball: [PokéBeach — "My First Battle" Cards Revealed, Features Unique Cards, Blue Borders, and Different Backs](https://www.pokebeach.com/2023/09/my-first-battle-cards-revealed-feature-blue-borders-and-unique-backs) · [Bulbapedia — My First Battle (TCG)](https://bulbapedia.bulbagarden.net/wiki/My_First_Battle_(TCG))
- Meowth Selva #56 borda dourada: [Bulbapedia — Meowth (Jungle 56)](https://bulbapedia.bulbagarden.net/wiki/Meowth_(Jungle_56)) · [Sports Card Investor — 1999 Jungle Promo Gold Border 56/64](https://www.sportscardinvestor.com/cards/meowth-pokemon/1999-jungle-promo-gold-border-56-64)
