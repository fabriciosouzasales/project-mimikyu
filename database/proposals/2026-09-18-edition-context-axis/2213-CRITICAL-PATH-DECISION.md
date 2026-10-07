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

> **SUPERSEDED (2026-10-04, `BATCH13-2831-B-SEMANTIC-REMEDIATION-PREP-01`) por D1(a′), §9.1.** O trait é criado pela `2236`; as 6 ficam nas 285 e são resolvidas pela camada histórica da `2831` v3.1, sem mapping operacional `PIKACHU-TAIL`.

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

> **Atualização (2026-10-04, `BATCH13-2831-B-SEMANTIC-REMEDIATION-PREP-01`).** A adjudicação foi feita (`BATCH13-2831-B-SEMANTIC-ADJUDICATION-01`) e as decisões estão em §9.

---

## 9. B-SEMANTIC — decisões aprovadas e candidato de remediação (2026-10-04, `BATCH13-2831-B-SEMANTIC-REMEDIATION-PREP-01`)

### 9.1 Decisões de Fabrício — **APPROVED**

| # | Decisão | Escopo |
|---|---|---|
| **D1(a′)** | `PIKACHU-TAIL` **é** Edition Context = `CAMPAIGN_PIKACHU_WORLD_2000`. As 6 `STANDARD_PIKACHU_WORLD_2000` permanecem nas 285. | Uso **histórico e escopado** (camada histórica da `2831`/`2213`). **Nenhum** mapping operacional `PIKACHU-TAIL`. BASEP #24 (holo, fonte contraditória) e BASE2 #60 **não** são liberados. |
| **D2** | O `raw_data` imutável da lineage é **prova de composição** para o legado B. | Supera, neste escopo, o `DEFERRED` / `B_UNPROVEN` da `2231` e de `B-PROFILE-AUDIT-19.md` / `SEED-COVERAGE.md` §7 (que eram ausência de prova, não decisão contrária). `2230`–`2232` não são editadas: a mudança é a `2236`, nova e versionada. |
| **D3** | Resíduo sv05 Koraidon #119 GameStop `REVERSE\|GALAXY\|NULL\|{}` → `COSMOS_REVERSE`. | **SOURCE_SET** `sv05` apenas. Nenhum `GALAXY = COSMOS` global. |
| **D4** | SV5 #144 Buddy-Buddy Poffin / Poffin de Colega, legado `PLAYER_REWARD_REVERSE`, raw `reverse` / foil `player-reward` / subtype NULL / stamp NULL: `PLAYER-REWARD` é Edition Context histórico → `PROGRAM_PLAYER_REWARDS`; residual estrutural `REVERSE`, cujo lookup operacional SV5 `REVERSE\|NULL\|NULL\|{}` = `REVERSE_HOLO`. Destino: **`REVERSE_HOLO` + `PROGRAM_PLAYER_REWARDS`**, 1 Variant. | **HISTORICAL RECONCILIATION** apenas (`2831` v3.1 e futura `2213`, depois do Gate A). Nenhum mapping EC `raw_field=foil`, nenhum mapping de finish `PLAYER-REWARD`, nenhuma exceção no resolvedor/lookup, `ck_cecem_raw_field` intocado. |

### 9.2 Prova quantitativa (LIVE read-only, 2026-10-04)

**Provas independentes da auditoria (SELECT read-only, base de D4 — não são POST LIVE; `2236`/`2237` ainda não foram aplicadas):** bloqueio baseline = 46; projetado após `2236` + `2237` = 11; projetado após a camada histórica incluindo D4 = 0. Para a identidade futura das 285: alvos não resolvidos = 0; grupos de colisão intra-plano = 0; colisão com Variant externa = 0.

33 Variants NO_PROFILE = 14 de aridade 1 + 19 compostas → **30 assinaturas únicas** = 11 + 19 (3 assinaturas de aridade 1 servem 2 Variants cada: `CAMPAIGN_POKEMON_4EVER`, `CAMPAIGN_POKEMON_TOGETHER`, `CHANNEL_POKEMON_CENTER_NY`). Resolução atual das 33 conferida uma a uma: todas `NEEDS_REVIEW_NO_EC_PROFILE` com a assinatura esperada. Nenhuma assinatura-alvo tem profile; nenhum trait inativo.

### 9.3 Arquitetura

| Camada | Artefato | O que faz |
|---|---|---|
| A — catálogo | `2236_forward_fix_b_semantic_edition_context_catalog.sql` | +1 trait (`CAMPAIGN_PIKACHU_WORLD_2000`, CAMPAIGN, ordem 140) · +31 profiles (1 D1 + 30 D2, ordens 1450–1750) · +50 links. 0 mappings. |
| B — finish | `2237_forward_fix_b_semantic_finish_mappings.sql` | +2 mappings SOURCE_SET: base3 `HOLO\|STARLIGHT` → `HOLO` (05b: starlight = galaxy em BASE3); sv05 `REVERSE\|GALAXY` → `COSMOS_REVERSE` (D3). 0 GLOBAL. |
| C — histórica | `2831` v3.1 (e a futura `2213`) | Camada HISTORICAL OVERRIDE só na simulação: Pikachu 6, League 4, Player Reward 1. Nunca no resolvedor, no lookup, em `ck_cecem_raw_field` ou no routing. |

Os três arquivos estão **PROPOSTOS, NÃO EXECUTADOS**. *(Atualização 2026-10-06: a `2236` está **APPLIED / PASS** — ver §9.9. `2237` e `2831` v3.1 seguem propostas, não executadas.)*

### 9.4 Os 30 profiles D2 (nomes derivados dos traits no LIVE pela regra da `2231`)

| Code | Aridade | Variants | Legado consumidor |
|---|---:|---:|---|
| `CAMPAIGN_POKEMON_4EVER` | 1 | 2 | `STANDARD_POKEMON_4EVER` |
| `CAMPAIGN_POKEMON_DAY_30TH` | 1 | 1 | `POKEDAY_HOLO` |
| `CAMPAIGN_POKEMON_TOGETHER` | 1 | 2 | `STANDARDS_POKEMON_TOGETHER` |
| `CHANNEL_ASIA_2023_24` | 1 | 1 | `STANDARDS_ASIA_2023_2024` |
| `CHANNEL_POKEMON_CENTER_NY` | 1 | 2 | `STANDARD_POKEMON_CENTER_NY` |
| `EVENT_INTERNATIONALS_EUROPE` | 1 | 1 | `INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO` |
| `EVENT_INTERNATIONALS_NORTH_AMERICA` | 1 | 1 | `INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE` |
| `EVENT_POKETOUR_99` | 1 | 1 | `STANDARD_POKETOUR_1999` |
| `EVENT_WORLDS_2023` | 1 | 1 | `STANDARDS_WORLDS_2023` |
| `EVENT_WORLDS_2025` | 1 | 1 | `STANDARDS_WORLDS_2025` |
| `PROGRAM_LEAGUE_ULTRA_BALL` | 1 | 1 | `STANDARD_ULTRA_BALL_LEAGUE` |
| `EVENT_INTERNATIONALS_NORTH_AMERICA__ROLE_STAFF` | 2 | 1 | `INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF` |
| `EVENT_WORLDS_2023__PLACEMENT_FINALIST` | 2 | 1 | `STANDARDS_WORLDS_2023_TOP_2` |
| `EVENT_WORLDS_2023__PLACEMENT_SEMI_FINALIST` | 2 | 1 | `STANDARDS_WORLDS_2023_TOP_4` |
| `EVENT_WORLDS_2023__PLACEMENT_TOP_16` | 2 | 1 | `STANDARDS_WORLDS_2023_TOP_16` |
| `EVENT_WORLDS_2023__PLACEMENT_TOP_32` | 2 | 1 | `STANDARDS_WORLDS_2023_TOP_32` |
| `EVENT_WORLDS_2023__PLACEMENT_TOP_8` | 2 | 1 | `STANDARDS_WORLDS_2023_TOP_8` |
| `EVENT_WORLDS_2023__ROLE_STAFF` | 2 | 1 | `STANDARDS_WORLDS_2023_STAFF` |
| `EVENT_WORLDS_2024__PLACEMENT_FINALIST` | 2 | 1 | `STANDARDS_WORLDS_2024_TOP_2` |
| `EVENT_WORLDS_2024__PLACEMENT_SEMI_FINALIST` | 2 | 1 | `STANDARDS_WORLDS_2024_TOP_4` |
| `EVENT_WORLDS_2024__PLACEMENT_TOP_16` | 2 | 1 | `STANDARDS_WORLDS_2024_TOP_16` |
| `EVENT_WORLDS_2024__PLACEMENT_TOP_32` | 2 | 1 | `STANDARDS_WORLDS_2024_TOP_32` |
| `EVENT_WORLDS_2024__PLACEMENT_TOP_8` | 2 | 1 | `STANDARDS_WORLDS_2024_TOP_8` |
| `EVENT_WORLDS_2024__ROLE_STAFF` | 2 | 1 | `STANDARDS_WORLDS_2024_STAFF` |
| `EVENT_WORLDS_2025__PLACEMENT_FINALIST` | 2 | 1 | `STANDARDS_WORLDS_2025_TOP_2` |
| `EVENT_WORLDS_2025__PLACEMENT_SEMI_FINALIST` | 2 | 1 | `STANDARDS_WORLDS_2025_TOP_4` |
| `EVENT_WORLDS_2025__PLACEMENT_TOP_16` | 2 | 1 | `STANDARDS_WORLDS_2025_TOP_16` |
| `EVENT_WORLDS_2025__PLACEMENT_TOP_32` | 2 | 1 | `STANDARDS_WORLDS_2025_TOP_32` |
| `EVENT_WORLDS_2025__PLACEMENT_TOP_8` | 2 | 1 | `STANDARDS_WORLDS_2026_TOP_8` (typo — §9.7) |
| `EVENT_WORLDS_2025__ROLE_STAFF` | 2 | 1 | `STANDARDS_WORLDS_2025_STAFF` |
| **Σ** | 11 + 19 | **33** | |

### 9.5 Efeito esperado

| | Baseline | Após 2236 + 2237 (genérico) | Após camada histórica (2831 v3.1) |
|---|---:|---:|---:|
| NO_PROFILE | 33 | **0** | 0 |
| FINISH NULL | 2 | **0** | 0 |
| NO_EC | 11 | 11 | **0** |
| Bloqueio total | 46 | **11** | **0** |
| Determinístico | 239/285 | **274/285** | **285/285** |

Plano = 285 e âncora `a53343fa38bbbe6f45fea7a4dba4bbdb` inalterados. Isto é contrato projetado, **não** Gate A PASS.

A `2831` v3.1 prova isso como gate (`B_SEMANTIC_RESIDUAL` = exatamente as 11 das regras) e aborta se divergir.

### 9.6 Camada histórica e D1 HOLD-safe

| Regra | n | Forma exata do raw | Destino |
|---|---:|---|---|
| H-PIKACHU | 6 | legado `STANDARD_PIKACHU_WORLD_2000`, `normal`, stamp `["pikachu-tail"]` | `STANDARD` + `CAMPAIGN_PIKACHU_WORLD_2000` |
| H-LEAGUE | 4 | legado `STANDARDS_LEAGUE`, `normal`, foil `league` | `STANDARD` + `PROGRAM_LEAGUE` |
| H-PLAYER-REWARD | 1 | legado `PLAYER_REWARD_REVERSE`, `reverse`, foil `player-reward`, sem subtype, sem stamp | `REVERSE_HOLO` + `PROGRAM_PLAYER_REWARDS` (D4) |

Finish das 11 = lookup operacional do `type` residual sem o token histórico, conferido contra o código declarado (`H_OVERRIDE_FINISH_DRIFT`; nenhuma regra sem finish — `HISTORICAL_RULE_FINISH_UNDECLARED`). D4 tem gate positivo próprio, `D4_PLAYER_REWARD_FINISH_DRIFT`: 1 Variant, SV5, forma exata, profile esperado, lookup do residual `REVERSE` = `REVERSE_HOLO` = finish declarado, e a resolução genérica da mesma evidência continua no tipo legado (routing não ampliado). **HOLD-safe:** a `2236` não cria mapping `PIKACHU-TAIL`; as 8 rows `pikachu-tail` do LIVE (6 de lineage + BASEP #24 holo + BASE2 #60) seguem `RESOLVED_NO_EDITION_CONTEXT` com residual `{PIKACHU-TAIL}` — postcheck da `2236` exige exatamente isso; na `2831` só as 6 do plano casam a regra (gate `D1_PIKACHU_SCOPE`).

### 9.7 H-PLAYER-REWARD-FINISH (CLOSED) e dívidas

- **H-PLAYER-REWARD-FINISH — SUPERSEDED / CLOSED por D4.** Registro da candidata anterior (`BATCH13-2831-B-SEMANTIC-REMEDIATION-PREP-01`, não publicada), preservado: SV5 #144 Poffin de Colega: EC `PROGRAM_PLAYER_REWARDS` é suportado; o finish não. O residual sem token dá `REVERSE_HOLO`, mas o mapping sv05 `PLAYER_REWARD_REVERSE` nunca foi auditado externamente e não há evidência de impressão inglesa equivalente. Não se inventa destino para zerar o gate: a `2831` v3.1 abortava neste ponto até Fabrício decidir o finish com prova (localizado em 1/285). **Encerrado** em `BATCH13-2831-B-SEMANTIC-REMEDIATION-CORRECTION-02`: D4 APPROVED → `REVERSE_HOLO` + `PROGRAM_PLAYER_REWARDS`; o STOP foi substituído pelo gate positivo `D4_PLAYER_REWARD_FINISH_DRIFT`.
- **Dívida de catálogo — typo `STANDARDS_WORLDS_2026_TOP_8`.** Nome "Padrão Worlds 2025 - Top 8", raw/mapping `worlds-2025`, SVP #224. O destino vem do raw (`EVENT_WORLDS_2025__PLACEMENT_TOP_8`); o code legado não é renomeado nesta rodada.
- **Dívida de auditoria — `2237`** grava por INSERT direto (o writer canônico exige ator admin e row NEEDS_REVIEW), sem linha em `catalog_admin_action_log` (precedente `2200`).

### 9.8 Próximo passo

*(SUPERSEDED pela §9.9 quanto ao NEXT — a `2236` já foi aplicada.)* Auditar/publicar `2236` + `2237` + `2831` v3.1 + documentação → mandato LIVE próprio para a `2236` → postcheck → mandato LIVE próprio para a `2237` → postcheck → provar B-SEMANTIC genérico 46 → 11 → PRE JIT da `2831` v3.1 → só então considerar autorizar a simulação (com `ROLLBACK`). **Gate A não declarado PASS. `2213` continua posterior ao Gate A.**

### 9.9 Estado LIVE — `2236` APPLIED / PASS (2026-10-06, `BATCH13-2236-LIVE-APPLY-01`)

Registro completo: `harness/LIVE-2236-APPLY-RECORD.md` (auditoria independente PASS).

- **`2236` = APPLIED / PASS.** Blob `d3acb581…` executado uma vez via `execute_sql` (conteúdo exato, `BEGIN`/`COMMIT` do próprio artefato; não `apply_migration`), sem retry; objetos com `created_at = 2026-10-06 00:39:00.38976+00`.
- Counts PRE → POST: traits 115 → 116 · profiles 144 → 175 · links 196 → 246 · external mappings 122 → 122 · links de mapping 122 → 122.
- **D2 provada LIVE:** as 33 Variants consumidoras resolvem `RESOLVED_WITH_EC_PROFILE` 33/33, no profile esperado uma a uma. Os 31 profiles novos (1 D1 + 11 + 19) têm selo = N:N, sem duplicata.
- **D1(a′) HOLD-safe após aplicação:** 0 mapping `PIKACHU-TAIL`; as 8 rows `pikachu-tail` seguem `RESOLVED_NO_EDITION_CONTEXT`, sem profile, residual `{PIKACHU-TAIL}`. BASEP #24 e BASE2 #60 continuam sem Variant; BASE2 #60 **não** foi resolvida.

**Funil real (fato × projeção):**

| Componente das 46 | Baseline | Estado LIVE após a `2236` | Depende de |
|---|---:|---|---|
| NO_PROFILE | 33 | **0 — fato** | — |
| FINISH NULL | 2 | 2 — inalterado | `2237` (não aplicada) |
| NO_EC | 11 | 11 — inalterado | camada histórica da `2831` v3.1 |

O 46 → 11 genérico **ainda não é fato LIVE**: falta a `2237` e a prova genérica pós-2237. 46 → 11 → 0 continua projeção.

**NEXT:** publicar este closeout → PRE read-only da `2237` → mandato próprio → POST → só então provar B-SEMANTIC genérico = 11 → PRE JIT da `2831` v3.1. Gate A não declarado PASS; `2213` posterior ao Gate A.

### 9.10 Estado LIVE — `2237` v1.0 ATTEMPTED / ROLLED BACK (2026-10-06, `BATCH13-2237-LIVE-APPLY-01`)

Registro completo: `harness/LIVE-2237-FAILED-ATTEMPT-RECORD.md`.

- **`2236` = APPLIED / PASS / DOCUMENTED** (§9.9).
- **`2237` v1.0 = ATTEMPTED / ROLLED BACK / NOT APPLIED.** Submetida uma vez; abortou em `2237_POST_EXISTING_CHANGED` (P0001); ROLLBACK integral; mappings 94 / 75 GLOBAL / 19 SOURCE_SET e fingerprint `aba31a17…` preservados; 0 rows-alvo; zero retry.
- **Causa:** gate POST de fingerprint não null-safe — o filtro por exclusão da forma dos alvos avaliava NULL nos 2 mappings GLOBAL `HOLO|NULL` e `REVERSE|NULL` (92 TRUE / 2 NULL), e o fingerprint filtrado nunca igualava o PRE.
- **`2237` v1.1 = CORRECTION CANDIDATE / NÃO EXECUTADA:** conjunto PRE identificado por `id = ANY(fm_pre.ids)`; semântica, alvos e demais gates inalterados.

**B-SEMANTIC LIVE (fato, inalterado):** NO_PROFILE 0 · NO_EC 11 · FINISH NULL 2 · blocked 13 · determinísticas 272/285. Os efeitos 13 → 11 e 272 → 274 continuam **projeção** da `2237`, não fato.

**NEXT:** auditar candidata v1.1 → publicar → novo PRE LIVE read-only → nova autorização explícita → novo APPLY. `2831` não executada; `2213` não criada.

### 9.11 Estado LIVE — `2237` v1.1 APPLIED / PASS (2026-10-06, `BATCH13-2237-V11-LIVE-APPLY-01`)

Registro completo: `harness/LIVE-2237-V11-APPLY-RECORD.md` (auditoria independente PASS).

- **`2236` = APPLIED / PASS / DOCUMENTED** (§9.9).
- **`2237` v1.0 = ATTEMPTED / ROLLED BACK / SUPERSEDED** (§9.10).
- **`2237` v1.1 = APPLIED / PASS.** Blob `3ddc54f1…` executado uma vez via `execute_sql` (conteúdo exato, `BEGIN`/`COMMIT` do próprio artefato; não `apply_migration`), sem retry; rows com `created_at = 2026-10-06 02:38:59.15009+00`.
- Mappings 94 → 96 (GLOBAL 75 → 75, SOURCE_SET 19 → 21): M1 `9428e2ea…` base3 `HOLO|STARLIGHT|NULL|NULL` → `HOLO`; M2 `65fdd081…` sv05 `REVERSE|GALAXY|NULL|NULL` → `COSMOS_REVERSE`. As 94 rows PRE preservadas (ids md5 `cc4b339a…`, fingerprint `aba31a17…`). Lookup só no escopo; zero vazamento global.

**Funil real (fato × projeção):**

| Componente das 46 | Baseline | Estado LIVE após `2236` + `2237` | Depende de |
|---|---:|---|---|
| NO_PROFILE | 33 | **0 — fato** | — |
| FINISH NULL | 2 | **0 — fato** | — |
| NO_EC | 11 | 11 — inalterado | camada histórica da `2831` v3.1 |

**46 → 11 agora é fato LIVE** do estágio genérico (`2236` + `2237`): plano 285, blocked genérico 11, determinísticas genéricas **274/285**. As 11 restantes são exatamente 6 `STANDARD_PIKACHU_WORLD_2000` + 4 `STANDARDS_LEAGUE` + 1 `PLAYER_REWARD_REVERSE`. **11 → 0 continua NÃO sendo fato LIVE**: depende do HISTORICAL OVERRIDE da `2831` v3.1 (e da `2213` só após o Gate A).

**NEXT:** auditar/publicar o closeout da `2237` → PRE JIT próprio da `2831` v3.1 → nova autorização explícita → executar somente a simulação (`ROLLBACK`) → Gate A. Gate A não declarado PASS; `2213` posterior ao Gate A.

### 9.12 `2831` v3.1 SIMULATION PASS / ROLLED BACK — Gate A FINAL PASS (2026-10-06/07, `BATCH13-2831-V31-LIVE-SIMULATION-01`)

Registro completo: `harness/LIVE-2831-V31-SIMULATION-RECORD.md` (auditoria independente PASS).

- **`2236` = CLOSED / APPLIED / PASS / DOCUMENTED** · **`2237` v1.1 = CLOSED / APPLIED / PASS / DOCUMENTED.**
- **`2831` v3.1 = EXECUTED / SIMULATION PASS / ROLLED BACK / ZERO PERSISTENT DELTA.** Blob `65149642…` submetido uma vez via `execute_sql` (autorização de Fabrício só para a simulação com `ROLLBACK`); retorno `[]`, sem erro; NOTICE **não** devolvido pelo canal. Como o artefato é fail-loud, a ausência de exception implica que nenhum gate abortou (285 Variants e 336 rows de lineage atualizadas, colisões 0, L1/L2/L3/L4/L8/L9), e a transação terminou no `ROLLBACK` do próprio blob. POST externo: todos os fingerprints iguais ao PRE.
- D1 HOLD-safe intacto (BASE2 #60 e BASEP #24 fora do plano, md5 inalterados; mapping `PIKACHU-TAIL` 0). Forward-fixes intactos.

**B-SEMANTIC — não confundir os dois estados:**

| Estado | Determinísticas | Bloqueadas |
|---|---:|---:|
| Persistente no LIVE (`2236` + `2237`) | 274/285 | 11 (6 Pikachu + 4 League + 1 Player Reward) |
| Provado dentro da simulação (camada HISTORICAL OVERRIDE) | 285/285 | 0 |

**Gate A = FINAL PASS.** Gate A PASS **não** autoriza a `2213`, que segue **NÃO CRIADA**.

**NEXT:** closeout publicado → especificar/preparar a `2213` → auditoria independente da `2213` → mandato próprio futuro.

### 9.13 `2213` v1.0 APPLIED / FINAL PASS (2026-10-07, `BATCH13-2213-V10-LIVE-EXECUTION-01`)

Registro completo: `harness/LIVE-2213-V10-APPLY-RECORD.md` (auditoria independente PASS). Sucede o "`2213` NÃO CRIADA" da §9.12: a `2213` v1.0 foi preparada (`BATCH13-2213-MIGRATION-PREP-01` + correção do contrato L5), publicada em `c7848edb` e executada com mandato próprio.

- **`2236` = CLOSED** · **`2237` v1.1 = CLOSED** · **`2831` v3.1 = SIMULATION PASS / Gate A FINAL PASS** (§9.12).
- **`2213` v1.0 = APPLIED / FINAL PASS.** Autorização de Fabrício: "Autorizo a execução LIVE da migration 2213 v1.0, blob 4318ac9567b6489ca441e487e3ae8ebda0247ea6." Blob `4318ac95…` submetido uma vez via `execute_sql` (não `apply_migration`), sem retry; retorno `[]`, sem SQLSTATE; NOTICE não devolvido pelo canal. Timestamp transacional único das 285: `2026-10-07 02:21:39.898181 UTC` (205,07 s após o último gate de concorrência; limite de 60 s SUPERSEDED só para esta execução).
- **285 READY_UNCONDITIONED = materializadas:** POST CV `c14f6fdb…` = esperado congelado; ids 285/285 preservados; EC não-NULL 285/285 (global 285); `card_variant` 24.893.
- **336 rows de lineage = reconciliadas:** POST lineage `a4b21ecd…` = esperado congelado; ids 336/336; híbrido L2 0.
- Fora do escopo idêntico ao PRE (25.903 / `d801514d…` · 24.608 / `dd7108a9…` · 23.955 · 1.193). **READY_UNCONDITIONED residual 0.** **Pricing 80 protegidas** (STAFF_HOLO 40 + SET_LOGO_REVERSE 40, EC não-NULL 0). D1 HOLD-safe e forward-fixes intactos.

**B-SEMANTIC — distinguir os dois momentos:**

| Momento | Estado persistente |
|---|---|
| Antes da `2213` | 274/285 genericamente determinísticas + 11 pela camada histórica (6/4/1); nenhuma decomposta |
| Depois da `2213` | **285/285 fisicamente decompostas** (EC + finish puro); 336/336 rows de lineage reconciliadas |

READY_PRICING_CONDITIONED (80) segue fora do escopo, bloqueada até `PRICING-CATALOG-VARIANT-RECONCILIATION-01`; HOLD 107 intocado.

**Batch 13 não é declarado CLOSED aqui.** **NEXT:** publicar o closeout da `2213` → auditoria de encerramento do Batch 13 → só depois a próxima frente do roadmap.
