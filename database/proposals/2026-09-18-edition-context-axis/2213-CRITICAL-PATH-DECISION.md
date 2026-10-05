# `2213` é critical path? — decisão

**`EDITION-CONTEXT-AXIS-2213-CRITICAL-PATH-DECISION-01`.** Read-only.

## Veredito

### `2213` → **NOT CRITICAL PATH** · DEFERRED LEGACY RECONCILIATION

A–G: **7 PASS / 0 FAIL**.

> **Mas o caminho crítico tem outro blocker, e ele é maior.** Medido no LIVE:
> **nada do eixo Edition Context está aplicado.** `card_variant` não tem
> `edition_context_profile_id`; as UNIQUE ainda são as legadas de 3
> componentes; não existe nenhuma tabela `card_edition_context_*`. O pacote
> `2203`–`2222` + seeds `2230`–`2232` é inteiramente **proposta**.
>
> Isso não muda o veredito — reforça: `2213` opera *sobre* a coluna de `2208`
> e a UNIQUE de `2209`. Ela é **consequência** da implantação, nunca
> pré-requisito dela.

---

## 1. Correção de método

A primeira tentativa de reproduzir as 365 usou o CTE `src` da `2831`
(lineage menos `hold_frozen`) e devolveu **23.166**, não 365 — o `src` é o
universo de entrada, e o recorte READY depende do resolver de eixos, que
exige vocabulário semeado (inexistente hoje).

**Isso não invalida a auditoria, e a torna mais forte:** o conjunto de 23.166
usado nas medições abaixo é **over-broad em 63×** e cobre **93 % das 24.893**
`card_variant` do catálogo. Um conjunto que grande devolvendo zero em toda
tabela de negócio prova o ponto com folga muito maior do que as 365 exatas
provariam. Onde o número exato importa (os 80), a definição versionada do
guard H6 foi usada literalmente.

---

## 2. Referências estruturais a `card_variant.id`

Inventário completo por `pg_constraint` — **5 tabelas, 7 FKs**:

| Tabela | Coluna(s) | ON DELETE | Natureza |
|---|---|---|---|
| `catalog_variant_import_row` | `matched_variant_id` | SET NULL | catálogo (lineage) |
| `catalog_variant_import_row` | `resulting_variant_id` | SET NULL | catálogo (lineage) |
| `collection_layout_slot_expected_content` | `card_variant_id` · `(card_variant_id, card_id)` | RESTRICT | **negócio** |
| `collection_master_set_scope` | `card_variant_id` | RESTRICT | **negócio** |
| `physical_card` | `card_variant_id` | RESTRICT | **negócio** |
| `pricing_product` | `card_variant_id` | SET NULL | **negócio** |

`collection_allocation` **não** referencia `card_variant` — o caminho é
indireto, via `physical_card`.

## 3. Rows medidas

| Tabela | rows totais | rows apontando para o conjunto over-broad (23.166 variants) |
|---|---:|---:|
| `physical_card` | **0** | 0 |
| `collection_allocation` | **0** | — (indireto) |
| `collection_master_set_scope` | **0** | 0 |
| `collection_layout_slot_expected_content` | **0** | 0 |
| `collection` | **0** | — |
| `storage_container` | **0** | — |
| `pricing_product` | 50.127 | **0** (`card_variant_id IS NOT NULL` = **0**) |
| `catalog_variant_import_row` (`resulting`) | 23.955 | 23.881 |
| `catalog_variant_import_row` (`matched`) | 1.129 | 1.124 |

**Referências de negócio dos 285 READY_UNCONDITIONED: 0.**
**Referências de negócio dos 80 READY_PRICING_CONDITIONED: 0.**

As únicas referências reais são **lineage de catálogo**, com `ON DELETE SET
NULL` e — decisivo — `2213` é `UPDATE` puro que **preserva `card_variant.id`**
(invariante 1 do `MIGRATION-MAP-365`), então nem essas são tocadas.

> **Nota de correção (2026-10-04, `BATCH13-2831-READINESS-CONTRACT-RECONCILIATION-01`).** "Nem essas são tocadas"
> vale para os **vínculos** (`resulting_variant_id`, `matched_variant_id`,
> FKs), não para o **conteúdo** das rows. Pela Correção 6 de
> `LINEAGE-STRATEGY.md`, posterior a esta decisão, a `2213` reconcilia
> `normalized_data` das rows com `resulting_variant_id` ∈ (285), na mesma
> transação. O veredito (`NOT CRITICAL PATH` · `DEFERRED LEGACY
> RECONCILIATION`) **não muda**: nenhuma referência de negócio é afetada, e o
> requisito de integridade do lineage fica **mais** forte, não mais fraco.

`inventory` tem 3 rows, mas não referencia `card_variant`: é o contêiner de
posse, e `physical_card` (que faria a ponte) está vazia.

---

## 4. A–G

| # | Critério | Veredito | Evidência |
|---|---|---|---|
| **A** | nenhuma referência de negócio exige decomposição imediata | **PASS** | 4 tabelas de negócio vazias; `pricing_product` com **0** `card_variant_id` não-nulo em 50.127 rows |
| **B** | identidade de 4 componentes coexiste com legacy não migrado | **PASS** | `2208`: `edition_context_profile_id UUID NULL`, sem default. Legacy fica `NULL` = *"sem esse eixo"* — semanticamente correto, não "desconhecido" |
| **C** | novos writes ficam protegidos pelo modelo novo | **PASS** ⚠️ | alcançado nas **etapas 12-A → 14** do rollout (`2217` EXPAND → `2218` SWITCH → `2223` CONTRACT → `2209` → `2215`), **antes** da etapa 18 (`2213`). Não depende de `2213`. **Ressalva: hoje nada disso está aplicado** — ver §5 |
| **D** | legacy não migrado não colide na UNIQUE nova | **PASS** | prova estrutural abaixo |
| **E** | Collections usa `card_variant.id` de forma opaca | **PASS** | as FKs de Collections são por `id` e pelo par `(id, card_id)` — nunca pela composição. `MIGRATION-MAP-365` invariantes 1–3: `id` preservado em 365/365, `variant_order`/`is_default` fora do `SET`, lineage intacto por consequência |
| **F** | `2213` continua executável sem perda de informação | **PASS** | a evidência nasce do `raw_data` via lineage (100 % das 365), que é imutável. Adiar não degrada nada. *Escopo*, não perda: 12 composições de B seguem `DEFERRED` (`B-PROFILE-AUDIT-19.md`) |
| **G** | os 80 de Pricing permanecem isolados | **PASS** | guard H6 é **derivado do LIVE**, não lista estática: testa `pricing_source_card_identity` / `pricing_source_variant_mapping` por `variant_type_id`. Presente na `2831` e exigido na `2213`. Rollout separa em etapa 19 |

### Prova de D — por que legacy não pode colidir

`2209` cria:

```
UNIQUE (card_id, variant_type_id, printing_profile_id, edition_context_profile_id)
NULLS NOT DISTINCT
```

Todo o legado não migrado tem `edition_context_profile_id = NULL`. Com
`NULLS NOT DISTINCT`, `NULL` é **um valor**, não um curinga. Restrita a essas
rows, a chave de 4 componentes tem a 4ª constante — logo **colapsa exatamente
na chave de 3 componentes** já vigente
(`uq_card_variant_card_type_printing` + `..._no_printing`).

Acrescentar uma coluna a uma chave só pode **particionar** grupos, nunca
fundi-los. Portanto a UNIQUE nova é, no legado, **equivalente** à antiga:
nenhuma colisão nova é possível, nem corrupção.

Reforço operacional: a etapa 13 (`2209`) cria a nova **enquanto as antigas ainda
existem** (mais restritivas), e `2215` só as derruba com prova antes e depois.

---

## 5. O blocker real do caminho crítico

Medido no LIVE (read-only):

| Objeto | Esperado pós-implantação | **Medido hoje** |
|---|---|---|
| `card_variant.edition_context_profile_id` | existe | **ausente** |
| UNIQUE de identidade | `uq_card_variant_identity` (4 comp.) | **ausente** — só as legadas de 3 |
| `card_edition_context_trait/profile/…` | 4 tabelas | **0 tabelas** |

O `ROLLOUT-ORDER.md` já posiciona `2213` na **etapa 18**, depois do UNFREEZE
(etapa 17) — ou seja, a ordem versionada sempre tratou a decomposição legada
como pós-implantação. Esta auditoria confirma que essa ordem é a correta e que
nada de negócio a contradiz.

---

## 6. Sequência mínima até voltar a Collections

Etapas do `ROLLOUT-ORDER.md`, **sem** 15 e 16:

| # | Ação |
|---|---|
| 1 | `2203`–`2207` — tabelas de Edition Context, vazias (aditivo puro) |
| 2 | `2230` → `2231` → `2232` — 115 traits · 144 profiles · 122 mappings |
| 3 | **FREEZE de importação** + captura de baseline |
| 4 | `2208` — coluna `edition_context_profile_id` NULL |
| 5 | `2212` (resolução operacional) → `2832` → `2833` → `2214` (guard de transição) |
| 6 | `2210` (staging identity, guard permissivo) → `2211` (contrato de routing) |
| 7 | Consumidores B passam a chamar `2211` |
| 8 | Deploy da Edge + suíte Deno (fixture compartilhada, 19 PASS) |
| 9 | `2217` EXPAND → `2218` SWITCH → `2223` CONTRACT — **nesta ordem** (`WRITER-EXPAND-CONTRACT-CORRECTION-01`) |
| 10 | `2209` — UNIQUE de 4 componentes, convivendo com as antigas |
| 11 | `2215` → `2216` — `DROP` das legadas, com prova |
| 12 | Read models C |
| 13 | **UNFREEZE** |
| → | **Collections liberado** |

Fora desta sequência, como dívida rotulada:

- **`2213`** — decomposição dos 285, precedida por `2831`
- **80 READY_PRICING_CONDITIONED** — bloqueados até `PRICING-CATALOG-VARIANT-RECONCILIATION-01`
- **12 composições de B** — `DEFERRED_TO_2213`
- **`CAMPAIGN_PIKACHU_WORLD_2000`** — ver §7

---

## 7. Deferred evidence — `CAMPAIGN_PIKACHU_WORLD_2000`

| Campo | Valor |
|---|---|
| Destino EC | `CAMPAIGN_PIKACHU_WORLD_2000` |
| Origem | `MIGRATION-MAP-365.md`, linha **nomeada**: `STANDARD_PIKACHU_WORLD_2000 \| 6 \| STANDARD \| NULL \| CAMPAIGN_PIKACHU_WORLD_2000` |
| Variants | **6** (confirmado no LIVE: `card_variant_type.code = 'STANDARD_PIKACHU_WORLD_2000'` → 6) |
| Status da composição | **PROVEN** pelo critério do `B-PROFILE-AUDIT-19.md` (linha nomeada, destino único) |
| Presente nos 115 traits? | **NÃO** — o token de origem não consta da lista congelada dos 21 exclusivos de B |
| Ação nesta rodada | **nenhuma** — trait não adicionado, conforme o mandato |
| Pertence a | fechamento futuro de **B / `2213`** |

Na rodada de `2213`, uma das duas: ou o token entra na lista congelada e o
trait é criado, ou a linha do `MIGRATION-MAP-365` é reconciliada. Enquanto não
for resolvido, essas 6 variants ficam fora do plano de decomposição — o que é
seguro, porque `2213` é fail-closed por escopo.

> **Correção (2026-10-04, `BATCH13-2831-READINESS-CONTRACT-RECONCILIATION-01`).** A frase acima ("essas 6 variants
> ficam fora do plano") **não está implementada** em nenhum artefato: o plano
> contratual continua 285 (âncora `a53343fa…`, reproduzida no LIVE) e as 6
> estão nele. O bloqueio real é mais amplo — ver §8.

---

## 8. B-SEMANTIC — Gate A semantic readiness (2026-10-04, `BATCH13-2831-READINESS-CONTRACT-RECONCILIATION-01`)

**BLOCKER.** Resolvedor vigente (`2211`/`2233` + `lookup_variant_type_for_row`)
aplicado à evidência (row de lineage mais antiga) das 285, LIVE read-only
(`checked_at 2026-10-04T22:51:57Z`):

| Medida | Valor |
|---|---:|
| `RESOLVED_WITH_EC_PROFILE` | 241 |
| `NEEDS_REVIEW_NO_EC_PROFILE` | 33 |
| `RESOLVED_NO_EDITION_CONTEXT` | 11 |
| `edition_context_profile_id` NULL | 44 (= 33 + 11) |
| `finish_target_id` NULL | 2 (fora das 44) |
| destino de acabamento não puro | 11 (as mesmas 11 sem EC) |
| **sem destino determinístico** | **46 / 285** (239 OK) |

Escopo C3 **não derivou**: READY 365 · condicionadas 80 · plano 285 · md5
`a53343fa…` (mesma medição). Lineage-alvo: 336 rows; 51 Variants com mais de
uma row; **0** Variants com destinos distintos entre as próprias rows;
`card_id` row × Variant divergente = 0.

### 8.1 Matriz causal nominal (para adjudicação; nada corrigido)

Token = `raw_data` da evidência (`type` / `foil` / `stamp`); traits = os que o
mapping resolveu; profile = composição exata existente.

| Classe | Legacy type | n | Tokens | Traits mapeados | Profile | Finish | Causa |
|---|---|---:|---|---|---|---|---|
| FINISH NULL | `GAMESTOP_HOLO` | 1 | reverse / galaxy / `gamestop` | `CHANNEL_GAMESTOP` | sim | NULL | sem Variant Type para o residual `reverse`+`galaxy` |
| FINISH NULL | `PRERELEASE_HOLO` | 1 | holo / starlight / `pre-release` | `EVENT_PRERELEASE` | sim | NULL | sem Variant Type para o residual `holo`+`starlight` |
| NO_EC | `STANDARD_PIKACHU_WORLD_2000` | 6 | normal / — / `pikachu-tail` | — | — | o próprio legado | token `PIKACHU-TAIL` em `HOLD_EDITORIAL` (`SEED-COVERAGE.md`), sem mapping |
| NO_EC | `STANDARDS_LEAGUE` | 4 | normal / `league` / — | — | — | o próprio legado | conceito em `foil`, fora do domínio de mapping (H3 / B3) |
| NO_EC | `PLAYER_REWARD_REVERSE` | 1 | reverse / `player-reward` / — | — | — | o próprio legado | idem (H3 / B3) |
| NO_PROFILE | `INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO` | 1 | `international-championship-europe` | `EVENT_INTERNATIONALS_EUROPE` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE` | 1 | `international-championship-north-america` | `EVENT_INTERNATIONALS_NORTH_AMERICA` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF` | 1 | idem + `staff` | `…_NORTH_AMERICA` + `ROLE_STAFF` | ausente | STANDARD | composição não provada |
| NO_PROFILE | `POKEDAY_HOLO` | 1 | `30th-pokeday` | `CAMPAIGN_POKEMON_DAY_30TH` | ausente | HOLO | trait diferido B |
| NO_PROFILE | `STANDARD_POKEMON_4EVER` | 2 | `pokemon-4-ever` | `CAMPAIGN_POKEMON_4EVER` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARD_POKEMON_CENTER_NY` | 2 | `pokemon-center-ny` | `CHANNEL_POKEMON_CENTER_NY` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARD_POKETOUR_1999` | 1 | `poketour-99` | `EVENT_POKETOUR_99` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARD_ULTRA_BALL_LEAGUE` | 1 | `ultra-ball-league` | `PROGRAM_LEAGUE_ULTRA_BALL` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARDS_ASIA_2023_2024` | 1 | `asia-2023-24` | `CHANNEL_ASIA_2023_24` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARDS_POKEMON_TOGETHER` | 2 | `pokemon-together` | `CAMPAIGN_POKEMON_TOGETHER` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARDS_WORLDS_2023` | 1 | `worlds-2023` | `EVENT_WORLDS_2023` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARDS_WORLDS_2023_{STAFF,TOP_16,TOP_2,TOP_32,TOP_4,TOP_8}` | 6 | `worlds-2023` + `staff` / `top-sixteen` / `finalist` / `top-thirty-two` / `semi-finalist` / `top-eight` | `EVENT_WORLDS_2023` + `ROLE_STAFF` / `PLACEMENT_*` | ausente | STANDARD | composição não provada |
| NO_PROFILE | `STANDARDS_WORLDS_2024_{STAFF,TOP_16,TOP_2,TOP_32,TOP_4,TOP_8}` | 6 | `worlds-2024` + idem | `EVENT_WORLDS_2024` + `ROLE_STAFF` / `PLACEMENT_*` | ausente | STANDARD | composição não provada (trait 2024 é PROVEN só em aridade 1) |
| NO_PROFILE | `STANDARDS_WORLDS_2025` | 1 | `worlds-2025` | `EVENT_WORLDS_2025` | ausente | STANDARD | trait diferido B |
| NO_PROFILE | `STANDARDS_WORLDS_2025_{STAFF,TOP_16,TOP_2,TOP_32,TOP_4}` + `STANDARDS_WORLDS_2026_TOP_8` | 6 | `worlds-2025` + idem (o `…_2026_TOP_8` carrega `worlds-2025` + `top-eight`) | `EVENT_WORLDS_2025` + `ROLE_STAFF` / `PLACEMENT_*` | ausente | STANDARD | composição não provada; nome do tipo legado diverge do ano do token |

Σ: FINISH NULL 2 · NO_EC 11 · NO_PROFILE 33 (= 14 de aridade 1 + 19 compostas) = **46**.

Os 12 traits diferidos de `B-PROFILE-AUDIT-19.md` aparecem **todos** entre os
33, mas os 33 **não** se reduzem a eles: 19 Variants dependem de composições
de aridade 2 (`ROLE_STAFF`, `PLACEMENT_*`, `EVENT_WORLDS_2024 + …`) que também
não têm profile. As 6 `STANDARD_PIKACHU_WORLD_2000` são **uma** subclasse —
e o token real delas é `pikachu-tail`, não um token "Pikachu World 2000".

### 8.2 O que esta seção NÃO decide

Nenhum seed, mapping, trait, profile, `READY_DEF`, âncora ou exclusão do plano
foi alterado. Plano = 285, âncora = `a53343fa…`. Excluir Variants só para o
gate ficar verde é proibido. Próximo passo: adjudicação das 46 por classe
(Fabrício), e só então autorização para executar a `2831`.
