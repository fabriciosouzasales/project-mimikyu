# Cobertura do seed de Edition Context — v2.1

> **`SECURITY-SEED-HARDENING-01` (B1).** `2230` → v2.1, `2231` → v3.1. O
> `name` das duas entidades passou a ser o **label canônico PT-BR**; o rótulo
> inglês migrou para `description` como *"Termo editorial de origem (en)"* —
> zero perda de informação. Nenhuma contagem mudou: **115 traits · 144
> profiles · 196 links · 122 mappings · 1.085/1.085**. A correção foi validada
> antes de escrever (144/144 `code`, aridade, composição EN e composição PT
> conferidas contra a N:N) e é agora **executável** pelos gates T4/P5/P6/P7.
>
> Maior `profile.name` PT-BR: **100 chars** contra `VARCHAR(200)`.

**`EDITION-CONTEXT-AXIS-EDITORIAL-VOCABULARY-02`.** Substitui a v1.0, que
media contra o corpus anterior (115 traits / 173 profiles) e listava E1–E3 como
BLOQUEADOS.

**E1 · E2 · E3 → CLOSED.** Os três seeds estão preenchidos. `PROPOSAL ONLY`.

---

## 1. O corpus mudou — e por isso os números mudaram

A v1.0 derivava a cobertura do universo `A ∪ B` de antes da partição semântica.
A partição canônica (`SEMANTIC-PARTITION-DECISIONS-54.md`) redefiniu A:

| Grupo | rows |
|---|---:|
| FINISH | 423 |
| PRINTING | 72 |
| **EDITION_CONTEXT** | **1.085** |
| INDETERMINATE | 61 |
| HOLD_EDITORIAL | 1 |
| **TOTAL operacional** | **1.642** |

O corpus de E1 são **exclusivamente as 1.085**. FINISH, PRINTING,
INDETERMINATE e HOLD ficaram fora por construção — o gate C1 da `2232` prova
isso executando o mesmo recorte.

---

## 2. Números canônicos

| Alvo | v1.0 (corpus antigo) | **v2.0 (corpus canônico)** |
|---|---:|---:|
| Traits | 115 | **115** |
| — do corpus A | 94 | **96** |
| — exclusivos do legado B | 21 | **19** |
| Profiles | 173 | **144** |
| — de A (corpus, composição medida) | — | **137** |
| — de B (composição PROVEN) | — | **7** |
| — de B diferidos para `2213` | — | **12** |
| Mappings (linhas) | — | **122** |
| Tokens de origem | 115 | **117** |
| `DECK_PLAYER_*` | 38 | **38** |

O total de traits coincidir em 115 é **coincidência aritmética**, não
preservação: 96 e 19 foram derivados de forma independente. O que mudou de
verdade é a composição (96 + 19 em vez de 94 + 21) e o número de profiles.

> **DESAMBIGUAÇÃO (`MAPPING-LIFECYCLE-CORRECTION-01`).** A redação anterior
> encerrava com *"(156, não 173)"*, o que contradizia a própria tabela acima e
> podia ser lido como "o corpus tem 156 profiles". Os três números, explícitos:
>
> | Número | O que é |
> |---:|---|
> | **173** | candidatas da união A ∪ B — **medição histórica**, pré-curadoria |
> | **156** | composições RE-DERIVADAS = 137 (A) + 7 (B PROVEN) + 12 (B DEFERRED) |
> | **144** | **CORPUS CANÔNICO SEMEADO** = 137 + 7. Os 12 de B ficam `DEFERRED` para a `2213` e **não** são semeados pela `2231` |
>
> O número que a `2231` grava, e que todos os gates cobram, é **144**.

### Por que 117 tokens → 115 traits

A relação token↔trait **não é 1:1**, e agora há prova:

| tokens de origem | trait |
|---|---|
| `PLAYER-REWARDS-PROGRAM` (A) + `PLAYER-REWARD` (B) | `PROGRAM_PLAYER_REWARDS` |
| `W-PROMO` (A) + `WOTC` (B) | `CHANNEL_WOTC_PROMO` |

### Por que 117 tokens → 122 linhas de mapping

Os 9 tokens `SOURCE_SET_SCOPED` geram uma linha por Set:
`SET-LOGO` 3 · `PLATINUM` 4 · os 6 de MFB 1 cada · `GOLD-BORDER` 1.
108 GLOBAL + 14 SCOPED = 122.

---

## 3. Distribuição de profiles — aridade medida, não arbitrada

| Aridade | composições | rows |
|---|---:|---:|
| 1 | 89 | 1.005 |
| 2 | 44 | 72 |
| **3** | **4** | **8** |
| **Σ A** | **137** | **1.085** |
| + B com composição **PROVEN** | 7 | — |
| **Σ** | **144** | |

> **Correção `FINAL-CORRECTION-01`:** a versão anterior desta tabela somava 19
> profiles de aridade 1, um por trait exclusivo de B, "para materializar o
> trait". Isso era invenção de composição. Auditados contra
> `MIGRATION-MAP-365.md`: **7 PROVEN · 12 NOT_PROVEN**. Os 12 foram removidos
> da `2231`; os traits e os mappings permanecem. Ver `B-PROFILE-AUDIT-19.md`.

> **Leitura da tabela.** As colunas acima são o subconjunto **A**. Na união
> canônica de 144, os 7 de B PROVEN são todos de aridade 1, logo a
> distribuição do corpus é **96 · 44 · 4**. Citar "89 de aridade 1" sobre um
> denominador de 144 é erro de leitura: 89 é sobre 137.

**Aridade máxima = 3**, confirmando o mandato. As 4 composições de aridade 3
são do Set MFB: `ARTWORK_MFB_BLUE_BORDER · ARTWORK_MFB_POKE_BALL ·
CHANNEL_MFB_DECK_<inicial>`.

Regra de nomenclatura (aridade 1, 2 e 3): `code` = codes dos traits em ordem
alfabética unidos por `__`; `name` = names na mesma ordem unidos por ` · `.
Mesma composição ⇒ mesmo code, **por construção**.

---

## 4. Escopo dos mappings

| Escopo | tokens | evidência |
|---|---:|---|
| **GLOBAL** | 108 | substantivo próprio cujo referente independe do Set (pessoa, evento nomeado, canal, programa) |
| **SOURCE_SET_SCOPED** | 9 | significado só determinável dentro do produto |

Os 9 escopados e o porquê:

| token | Sets | razão |
|---|---|---|
| `SET-LOGO` | dp1, swsh9, svp | **guard H2** — nunca GLOBAL. EX7–EX10 é FINISH; SV3/SV4 é INDETERMINATE |
| `BULBASAUR` `CHARMANDER` `PIKACHU` `SQUIRTLE` | mfb | nome de Pokémon que só significa "deck de origem" dentro de My First Battle |
| `POKEBALL` `BLUE-BORDER` | mfb | marcam "First Pokémon / Starting Energy" só nesse produto |
| `GOLD-BORDER` | base2 | promo de caixas de Fruit Rolls (dez/1999), específico da Selva |
| `PLATINUM` | dp4–dp7 | palavra ambígua (pode ser acabamento/raridade em outro contexto) |

---

## 5. Provas escritas nos seeds

| # | Prova | Onde |
|---|---|---|
| **T1** | exatamente 115 traits | `2230` |
| **T4** | `name` é label **atômico PT-BR**: não-vazio, sem ` · `, ≤ 120 chars; `description` é frase com o termo editorial de origem | `2230` v2.1 |
| **P5** | `name` do profile **recomputado a partir da N:N** e comparado ao persistido — prova PT-BR + ordem + ausência de texto livre | `2231` v3.1 |
| **P6** | maior `name` ≤ `VARCHAR(200)` — medido em **100 chars** | `2231` v3.1 |
| **P7** | `description` do profile é frase, nunca label alternativo | `2231` v3.1 |
| **T2** | os 21 tokens exclusivos de B têm destino — mapa explícito, não-1:1 | `2230` |
| **T3** | 38 `DECK_PLAYER_*`, todos com prefixo | `2230` |
| **S1** | zero code transliterado (`^[A-Z][A-Z0-9_]*$`) | `2230` |
| **S5** | nenhuma nona família criada | `2230` |
| **S6** | `display_order` único por família | `2230` |
| **P1** | exatamente 144 profiles, com split 137 A / 7 B verificado | `2231` |
| **B-UNPROVEN** | aborta se qualquer profile de origem B sair da lista nominal dos 7 | `2231` |
| **DEFERRED** | prova negativa: aborta se qualquer um dos 12 traits diferidos ganhar profile de aridade 1 | `2231` |
| **P4** | aridade máxima 3, e a aridade declarada bate com a composição real | `2231` |
| **S3** | `traits_signature` selada pelo trigger em 100% | `2231` |
| **S4** | zero duplicata por `traits_signature` **e** por composição | `2231` |
| **M3** | **zero mapping de `foil`/`type`/`size`** — no seed e no banco | `2232` |
| **H2** | `set-logo` nunca GLOBAL e só em dp1/swsh9/svp | `2232` |
| **C1** | **1.085/1.085 rows EC cobertas** — recorte executável, falha alto nomeando o token órfão | `2232` |

---

## 6. HOLD — permanece isolado

`PIKACHU-TAIL` (1 row, BASE2 #60 Pikachu) segue `HOLD_EDITORIAL` por decisão
versionada (`DEFER_CANDIDATE` / `SOURCE_CONTRADICTION`, staging BASEP). Ele
**não pertence ao corpus EC** e por isso não tem trait nem mapping. O gate C1
o exclui explicitamente — 1 row (0,06 % das 1.642) não bloqueia nada.

O blocker **B3** também segue intacto: `raw_field='foil'` está fora do
`ck_cecem_raw_field` de `2207`, logo as 57 rows de `foil`-programa
(`LEAGUE`, `PLAYER-REWARD`, `PROFESSOR-PROGRAM`) permanecem `INDETERMINATE` e
nenhum mapping pode ser semeado para elas — nem por engano.

---

## 7. Universo B — parcialmente diferido para `2213`

`MIGRATION-MAP-365.md` tem linhas **nomeadas** (destino EC completo) e linhas
**agregadas** (*"21× `STANDARDS_WORLDS_*` / `ASIA` → `EVENT_WORLDS_<ano>`
(+ `PLACEMENT_*` / `ROLE_STAFF`)"* e *"Demais (24 tipos, 1 cada) — conforme
família"*). Só as nomeadas provam composição.

| | traits | profiles |
|---|---:|---:|
| B com composição PROVEN | 7 | **7 na `2231`** |
| B com composição NOT_PROVEN | 12 | **0 — DEFERRED_TO_2213** |

Os 12 diferidos **mantêm trait** (`2230`) e **mantêm mapping** (`2232`): o que
não está provado é a composição, não a existência do trait nem o vínculo
token→trait. Sem profile, `2211` devolve `NEEDS_REVIEW_NO_EC_PROFILE` —
estado não-terminal, **fail-closed**. Nenhuma row de B é resolvida por engano.

Nada disso afeta a cobertura de A: **1.085/1.085**.

Detalhe linha a linha, com o Variant Type que sustenta cada PROVEN e a razão
de cada NOT_PROVEN, em **`B-PROFILE-AUDIT-19.md`** — que também registra um
achado adicional não corrigido nesta rodada (`CAMPAIGN_PIKACHU_WORLD_2000`).
