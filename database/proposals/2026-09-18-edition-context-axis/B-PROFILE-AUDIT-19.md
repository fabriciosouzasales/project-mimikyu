# Auditoria dos 19 profiles de aridade 1 do legado B

**`EDITION-CONTEXT-AXIS-EDITORIAL-VOCABULARY-FINAL-CORRECTION-01`.**
Sem LIVE — toda a evidência é `MIGRATION-MAP-365.md`, que está versionado.

**Resultado: 7 PROVEN · 12 NOT_PROVEN.** Os 12 foram removidos da `2231`.

---

## 0. O defeito

A v2.0 da `2231` criou um profile de aridade 1 para cada um dos 19 traits
exclusivos de B, com a justificativa de que era "suficiente para existirem".

Isso é inválido pela definição que o próprio arquivo declara: **um profile é a
composição EXATA de traits de uma variante**, não um recibo de existência de
trait. Afirmar aridade 1 sem evidência é inventar composição — precisamente o
que o cabeçalho da `2231` proíbe.

A contradição era interna e explícita: o mesmo relatório afirmava que "as
composições de aridade ≥ 2 de B não são deriváveis" e mesmo assim declarava
aridade 1 para as 19.

---

## 1. O critério de prova

`MIGRATION-MAP-365.md` tem dois tipos de linha:

| tipo | exemplo | o que prova |
|---|---|---|
| **NOMEADA** | `` `POKEMON_CENTER_HOLO` \| 19 \| … \| `CHANNEL_POKEMON_CENTER` `` | destino EC **completo e explícito** → composição conhecida |
| **AGREGADA** | `` 21× `STANDARDS_WORLDS_*` / `ASIA` \| 21 \| … \| `EVENT_WORLDS_<ano>` (+ `PLACEMENT_*` / `ROLE_STAFF`) `` | destino **parcial** — o `(+ …)` declara que há combinação |
| **AGREGADA** | `` Demais (24 tipos, 1 cada) \| 24 \| … \| conforme família `` | destino **não enumerado** |

**PROVEN** = o trait aparece como destino EC completo de uma linha NOMEADA, e
essa linha não lista nenhum outro trait. **NOT_PROVEN** = o trait só é
alcançável por linha AGREGADA.

As duas linhas agregadas são explícitas sobre por que não servem: a dos Worlds
**declara** a combinação com `PLACEMENT_*` / `ROLE_STAFF`; a dos "Demais 24"
não nomeia trait nenhum.

---

## 2. Os 19, um a um

### 2.1 PROVEN — 7 permanecem na `2231`

| # | trait | source token | Variant Type de B que sustenta | qtd | composição observada | status |
|---|---|---|---|---:|---|---|
| 1 | `CHANNEL_POKEMON_CENTER` | `POKEMON-CENTER` | `POKEMON_CENTER_HOLO` | 19 | destino EC único; Finish vai para `HOLO` | **PROVEN** |
| 2 | `EVENT_GYM_CHALLENGE` | `GYM-CHALLENGE` | `STANDARD_GYM_CHALLENGE` + `GYM_CHALLENGE_HOLO` | 12 | **duas** linhas nomeadas, ambas com o mesmo destino EC único | **PROVEN** |
| 3 | `CAMPAIGN_FIRST_MOVIE` | `1ST-MOVIE` | `STANDARD_FIRST_MOVIE` | 4 | destino EC único | **PROVEN** |
| 4 | `CAMPAIGN_FIRST_MOVIE_INVERTED` | `1ST-MOVIE-INVERTED` | `STANDARD_FIRST_MOVIE_INVERTED` | 4 | destino EC único; trait separado de `CAMPAIGN_FIRST_MOVIE` por decisão já registrada | **PROVEN** |
| 5 | `PROGRAM_LEAGUE` | `LEAGUE` | `STANDARDS_LEAGUE` | 4 | destino EC único. A marca ⚠️ B3 é sobre `raw_field='foil'`, **não** sobre a composição | **PROVEN** |
| 6 | `EVENT_WORLDS_2024` | `WORLDS-2024` | `STANDARD_WORLDS_2024` | 3 | linha **própria e nomeada**, fora do agregado dos 21 Worlds | **PROVEN** |
| 7 | `CAMPAIGN_HORIZONS` | `HORIZONS` | `STANDARDS_HORIZONS` | 3 | destino EC único | **PROVEN** |

### 2.2 NOT_PROVEN — 12 removidos da `2231`

| # | trait | source token | por que não está provado |
|---|---|---|---|
| 1 | `EVENT_WORLDS_2023` | `WORLDS-2023` | só via `21× STANDARDS_WORLDS_*`, que **declara** `(+ PLACEMENT_* / ROLE_STAFF)` |
| 2 | `EVENT_WORLDS_2025` | `WORLDS-2025` | idem |
| 3 | `PLACEMENT_TOP_8` | `TOP-EIGHT` | é justamente um dos `PLACEMENT_*` do `(+ …)` — por definição participa de composição maior |
| 4 | `CHANNEL_ASIA_2023_24` | `ASIA-2023-24` | o `/ ASIA` do mesmo agregado |
| 5 | `CHANNEL_POKEMON_CENTER_NY` | `POKEMON-CENTER-NY` | cai em "Demais (24 tipos) — conforme família" |
| 6 | `CAMPAIGN_POKEMON_DAY_30TH` | `30TH-POKEDAY` | idem |
| 7 | `EVENT_INTERNATIONALS_EUROPE` | `INTERNATIONAL-CHAMPIONSHIP-EUROPE` | idem |
| 8 | `EVENT_INTERNATIONALS_NORTH_AMERICA` | `INTERNATIONAL-CHAMPIONSHIP-NORTH-AMERICA` | idem |
| 9 | `CAMPAIGN_POKEMON_4EVER` | `POKEMON-4-EVER` | idem |
| 10 | `CAMPAIGN_POKEMON_TOGETHER` | `POKEMON-TOGETHER` | idem |
| 11 | `EVENT_POKETOUR_99` | `POKETOUR-99` | idem |
| 12 | `PROGRAM_LEAGUE_ULTRA_BALL` | `ULTRA-BALL-LEAGUE` | idem. Reforço: o irmão `PROGRAM_LEAGUE_POKE_BALL` (A) aparece sozinho em SWSH2, mas isso é evidência de **A**, não de B |

> Nota sobre o padrão dos "campeonatos internacionais": em **A**, nenhum
> `*-CHAMPIONSHIPS` isolado é raro, mas `REGIONAL-CHAMPIONSHIPS + STAFF`
> existe. Isso é indício, não prova, de que os internacionais de B também
> combinam. Indício não vira composição — por isso ficam diferidos.

---

## 3. O que foi feito com cada um

Conforme a regra do mandato:

| ação | onde | resultado |
|---|---|---|
| profile removido (12) | `2231` | 156 → **144** profiles · 208 → **196** links |
| trait mantido (19/19) | `2230` | **115 traits intactos** — a existência do trait está provada pela lista congelada dos 21 em `SEED-COVERAGE.md`; o que não estava provado é a composição |
| mapping mantido (21/21 tokens de B) | `2232` | **122 mappings intactos** — o vínculo token→trait é proven: o `EVENT_WORLDS_<ano>` e os `PLACEMENT_*` são nomeados pelo próprio agregado, e os "Demais 24" são cobertos por "conforme família" mais o gate T2 da `2230` |
| fail-closed | `2211` | sem profile, o contrato devolve **`NEEDS_REVIEW_NO_EC_PROFILE`** — estado **não-terminal**. Nenhuma row de B é resolvida por engano |
| composição | `2213` | **DEFERRED** |

### Prova negativa escrita no seed

A `2231` v3.0 carrega dois gates novos que tornam a regressão impossível:

- **`SEED_PROFILE_B_UNPROVEN`** — aborta se qualquer profile de origem `B`
  estiver fora da lista nominal dos 7.
- **`SEED_DEFERRED_HAS_PROFILE`** — aborta se qualquer um dos 12 traits
  diferidos voltar a ganhar profile de aridade 1.

---

## 4. Achado adicional — NÃO corrigido nesta rodada

`MIGRATION-MAP-365.md` tem uma linha **nomeada** cujo destino não existe entre
os 115 traits:

```
| `STANDARD_PIKACHU_WORLD_2000` | 6 | `STANDARD` | NULL | `CAMPAIGN_PIKACHU_WORLD_2000` | sim |
```

O token de origem correspondente **não está na lista congelada dos 21
exclusivos de B**, então o trait nunca entrou na derivação. Pelo critério
desta auditoria ele seria um **oitavo PROVEN** (linha nomeada, destino único,
6 variantes).

Não foi adicionado porque o mandato fixa: *"NÃO reabrir … 115 traits"*.
Fica registrado como entrada obrigatória da rodada de `2213`: ou o token
entra na lista congelada, ou a linha do `MIGRATION-MAP` precisa ser
reconciliada. **Isto não afeta o corpus A nem a cobertura 1.085/1.085.**
