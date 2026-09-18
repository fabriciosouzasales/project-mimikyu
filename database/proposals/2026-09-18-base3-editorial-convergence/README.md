# BASE3 — Editorial Convergence · Staging

| Campo | Valor |
|---|---|
| **Mandato** | `BASE3 — IMPLEMENTATION STAGING-01` |
| **Data** | 2026-09-18 |
| **Status** | **EXECUTADO / LIVE VALIDATED / CLOSED (2026-09-18)** |
| **Job LIVE** | `d5b7a148-0459-40fd-a32f-13fdcb845026` · `base3` · **`COMPLETED`** · 177 / 177 `VALID` / **0** `NEEDS_REVIEW` · 177 `APPROVED`+`INSERTED` · 0 `SKIPPED` · 0 `REJECTED` · 0 `UNCHANGED` · 0 `FAILED` · `error_summary = null` |
| **Resultado** | `card_variant` 7.494 → **7.671** · BASE3 **62/62** Cards com variante (177 variantes) |
| **Baseline git** | `80cc268` |

---

## Conteúdo

| Arquivo | O que é | Transporte |
|---|---|---|
| `2202_add_base3_evolution_box_error_trait.sql` | 1 `INSERT` em `card_printing_trait` (`EVOLUTION_BOX_ERROR`, ordem 9) | **migration guardada** (único SQL de escrita fora do caminho canônico) |
| `base3-authenticated-runner.js` | Runner efêmero de DevTools — 9 RPCs canônicas com a sessão admin real · **`DRY_RUN = true` por padrão** | **não é produto**; cola-se no console e morre com o refresh |
| `2829_base3_collision_gate.sql` | Harness **READ-ONLY** do COLLISION GATE (177 identidades) | SQL Editor, **duas execuções**: `2829 PRE` (antes de tudo) e `2829 POST` |

> **Por que três arquivos e não dois.** O mandato exige reprovar o COLLISION
> GATE "antes da primeira escrita e no final". Essa prova depende de
> `internal.compute_variant_residual_signature` e
> `internal.lookup_variant_type_for_row` — **não expostas ao PostgREST**. As
> alternativas seriam duplicar o resolver em JavaScript ou criar uma RPC
> permanente nova; o mandato proíbe as duas. Logo o gate completo é um harness
> SQL. O runner cobre só a parte que consegue observar sem duplicar nada
> (`card_variant` = 0 nas 62 Cards; tuplas `raw_data` distintas por Card) e diz,
> no próprio log, que a prova completa é a `2829`.

---

## Numeração — prova de que está livre

| verificação | resultado |
|---|---|
| `2202*` em `database/schema/` | **ausente** |
| `2202*` em `database/migrations/` | **ausente** (diretório sem arquivos `22xx`) |
| `2202*` em `database/proposals/` | **ausente** |
| maior `22xx` do repositório | `2201` (BASEP, executada) · `2200` (SV5, executada) |
| `2829*` em qualquer pasta | **ausente**; maior do range é `2828` (`2026-09-15-card-variant-size-scope-guard`) |

As ocorrências de "2202" em `docs/` são todas o SQLSTATE `22023`, não numeração de Query.

---

## Por que a Query 2202 existe

`card_printing_trait` continua sendo a **única** das cinco classes de objeto sem
writer canônico. Reauditado no LIVE nesta rodada:

```
writers_de_trait = 0      -- zero funções (public ou internal) com
                          -- INSERT INTO public.card_printing_trait
```

E `catalog_admin_action_log` não tem `entity_type` para trait. O modelo tratou
trait como **vocabulário semeado** — não como objeto editorial de runtime.
Precedente direto e recente: a **Query 2201** (BASEP), pela mesma razão.

**As Queries 2169 e 2201 NÃO são alteradas.** Ambas são histórico LIVE. A 2202 é
incremento — mesma disciplina de `6109`/`6110`/`6125`/`6126`.

---

## Divisão de trabalho

| objeto | transporte | writer |
|---|---|---|
| 1 trait `EVOLUTION_BOX_ERROR` | migration `2202` | — (não existe) |
| 1 profile `EVOLUTION_BOX_ERROR` | runner | `public.admin_create_card_printing_profile_with_backfill` |
| 1 printing mapping `subtype:evolution-box-error` | runner | `public.admin_resolve_catalog_variant_import_printing_mapping` |
| 3 variant types | runner | `public.admin_create_card_variant_type` |
| 3 VT mappings **SCOPED `base3`** | runner | `public.admin_resolve_catalog_variant_import_mapping_for_set` |
| 1 VT mapping **GLOBAL** | runner | `public.admin_resolve_catalog_variant_import_mapping` |
| aprovar 177 · confirmar | UI existente | `admin_decide_catalog_variant_import_row` (lote) · `admin_confirm_catalog_variant_import` |

**Não usar `admin_create_card_variant_type_with_import_mapping`:** ele cria
mapping **GLOBAL** para todos, e três dos quatro mappings desta rodada são
**SOURCE_SET**.

---

## O pacote — 5 objetos, 5 mappings

### Objetos novos

| classe | code | ordem | composição |
|---|---|---|---|
| Printing trait | `EVOLUTION_BOX_ERROR` | 9 | — |
| Printing profile | `EVOLUTION_BOX_ERROR` | 11 | `{EVOLUTION_BOX_ERROR}` |
| Variant Type | `PRERELEASE_HOLO` | **95** | — |
| Variant Type | `PRERELEASE_COSMOS_HOLO` | **96** | — |
| Variant Type | `W_PROMO_STAMPED` | **97** | — |

> ⚠️ **display_order 95/96/97, não 90/91/92.** BASEP criou 5 Variant Types que
> ocupam exatamente 90–94 (`STANDARD_FIRST_MOVIE` … `STANDARD_POKEMON_CENTER_NY`).
> `card_variant_type` está hoje em **94**, com ordens 1..94 sem buracos.

### Mappings

| eixo | escopo | chave | alvo |
|---|---|---|---|
| Printing | — (Printing não tem escopo) | `subtype` = `evolution-box-error` | profile `EVOLUTION_BOX_ERROR` |
| Variant Type | **SOURCE_SET `base3`** | `HOLO / STARLIGHT / — / {PRE-RELEASE}` | `PRERELEASE_HOLO` |
| Variant Type | **SOURCE_SET `base3`** | `HOLO / COSMOS / — / {PRE-RELEASE}` | `PRERELEASE_COSMOS_HOLO` |
| Variant Type | **SOURCE_SET `base3`** | `HOLO / COSMOS / 1999-COPYRIGHT / {}` | `COSMOS_HOLO` (existente) |
| Variant Type | **GLOBAL** | `NORMAL / — / — / {WOTC}` | `W_PROMO_STAMPED` |

**GLOBAL é decisão semântica, não atalho.** O programa *W Promotional* é
transversal por definição — 7 cartas, 6 expansões, set./1999 a mar./2001
(Bulbapedia). Restringir a `base3` afirmaria que o selo "W" é fenômeno de Fossil,
o que a fonte nega nominalmente. Os outros seis aparecerão na campanha histórica.

**Os três SOURCE_SET também são decisão semântica.** O vocabulário de `foil` da
TCGdex está provadamente inconsistente dentro do próprio Set (`galaxy` e
`starlight` nomeiam o mesmo padrão físico — Bulbapedia define *Starlight* como o
padrão de Base/Jungle/Fossil; Elite Fourum chama o mesmo padrão de *Galaxy*). Um
mapping GLOBAL sobre `STARLIGHT` herdaria essa inconsistência. Lição `2200` /
Master Ball: ampliar depois é barato, revogar é caro.

---

## Ordem obrigatória

```
2829 PRE  →  2202 (trait)  →  runner  →  2829 POST  →  UI
```

**O `2829 PRE` roda antes da PRIMEIRA ESCRITA LIVE da rodada** — portanto antes
da migration `2202`, não entre ela e o runner. O collision gate precisa medir o
estado intocado; medi-lo depois de qualquer escrita já é medir outro estado.

O resolver consome o eixo Printing **antes** do Variant Type. Se o trait e o
profile não existirem primeiro, o token `evolution-box-error` permanece no
residual e nenhum mapping de VT casa.

### O runner tem dois passos, por desenho

`DRY_RUN = true` é o **valor padrão do arquivo staged** — fail-safe:

1. colar com `DRY_RUN = true` → roda só o preflight, **zero escrita**, e para;
2. **Fabrício audita o retorno**;
3. só então ele altera `DRY_RUN` para `false` explicitamente e cola de novo.

Não há outra lógica de guarda — é uma constante, lida uma vez, logo após o
preflight.

---

## Atomicidade — leia antes de executar

A migration `2202` é um bloco `DO` único, portanto atômica.

**As 9 RPCs do runner NÃO são.** Cada uma é sua própria transação e faz COMMIT
sozinha. Um erro na chamada N **não desfaz** as N−1 anteriores. Por isso o runner
é:

- **fail-closed** — para na primeira divergência, não compensa nada;
- **resumable** — antes de cada objeto consulta o estado: ausente → executa;
  presente e idêntico → checkpoint concluído, segue; presente e divergente →
  STOP. Nunca repete uma criação às cegas. Reexecutar o script após uma parada é
  seguro.

A resumabilidade é **real**, não nominal: as 5 rows da convergência são
identificadas pelas **assinaturas imutáveis de `raw_data`**, nunca por
`validation_status` — que muda a cada mapping que faz COMMIT.

---

## Diferenças em relação ao runner de BASEP v1.2

| # | mudança | por quê |
|---|---|---|
| 1 | `sigOf()` passa a incluir **`foil`** | Em BASE3 as duas rows de Prerelease do Aerodactyl diferem **só** no foil (`starlight` vs `cosmos`). Sem o foil, colapsariam numa assinatura só — e a âncora resolveria a row errada. |
| 2 | Invariante de workflow: **177 PENDING/PENDING** | Em BASEP 47 rows já estavam APPROVED/INSERTED. Em BASE3 nenhuma foi decidida. |
| 3 | **Zero deferidas** | Gate final exige 177 VALID / **0** NEEDS_REVIEW. |
| 4 | **Preview canônico** antes de cada mapping de VT | `admin_preview_catalog_variant_import_mapping` (read-only, já existente) prova `would_apply=true`, `block_reason=null`, `rows_total=1`, `rows_class_a=1`, `rows_class_b=0`, `canonical_class_c=0`, `jobs_affected=1` **antes** da escrita. |
| 5 | Fase F separada para o GLOBAL | Contrato de retorno diferente: `(mapping_id, rows_updated, jobs_affected)` — sem `rows_still_pending`, sem `scope_kind`. Há leitura de confirmação provando `external_set_id IS NULL`. |
| 6 | Guard A9 novo | Confirma que o mapping SCOPED `base3` `HOLO/GALAXY → HOLO` ainda existe: é ele que resolve o resíduo de `evolution-box-error` depois que o Printing consome o token. |

Mantidos integralmente: parser `@supabase/ssr`, Base64-URL, chunks contíguos,
token relido por request, probe `is_admin()`, identidade canônica por `code`,
checkpoints antes/depois de cada RPC, `DRY_RUN`.

---

## Gates

| fase | esperado | falha ⇒ |
|---|---|---|
| A — preflight | `is_admin()` = TRUE · job `base3/STAGED/177` · 5 assinaturas × 1 row · 172 históricas VALID · **177 PENDING/PENDING** · 9 traits · `HOLO`/`COSMOS_HOLO` ativos · mapping base3 `HOLO/GALAXY` presente · collision gate observável | STOP antes da 1ª escrita |
| B — profile | `rows_touched` = **0** · `jobs_affected` = **0** | STOP |
| C — printing mapping | `rows_updated` = **1** · `rows_still_pending` = **0** · `jobs_affected` = **1** | STOP |
| D — variant types | 3 UUIDs devolvidos | STOP |
| E — VT mappings SCOPED | preview OK + `scope_kind` = `SOURCE_SET` · `external_set_id` = `base3` · `rows_total` = 1 · `rows_reclassified` = 1 · `rows_still_pending` = 0 · `jobs_affected` = 1 | STOP |
| F — VT mapping GLOBAL | preview OK + `rows_updated` = 1 · `jobs_affected` = 1 · readback `external_set_id IS NULL` | STOP |
| G — gate final | job `STAGED/177/177` · **177 VALID · 0 NEEDS_REVIEW** · 177 PENDING/PENDING · collision gate observável | STOP — não decidir nem confirmar |

---

## Collision gate — o que cada artefato prova

| prova | onde | natureza |
|---|---|---|
| `card_variant` = 0 nas 62 Cards de BASE3 | runner (A10 e G4) + `2829` C6 | condição que torna toda colisão **intra-job** |
| tuplas `raw_data` distintas por Card | runner (A10 e G4) | condição **necessária** |
| **177 identidades projetadas, 177 distintas** | **`2829` C4/C5** | condição **suficiente** — a prova real |
| overlay × resolver conferem | `2829` C7 | detecta drift entre a decisão e o que o LIVE faz |
| `card_variant` projetado = 7.494 + 177 = **7.671** | `2829` C10 | consequência |

**Execução de referência da `2829` no LIVE (estado PRÉ-migration, 2026-09-18):
11/11 PASS, `GATE` PASS.** A `v1.0` do harness tinha um defeito real — usava UUID
na chave de identidade, e como os três VTs e o profile ainda não existem, ela
produzia colisões **falsas** (175/177, 2 grupos). Corrigido na `v1.1`: a chave usa
`code`, que é único por Game (`UNIQUE (game_id, code)`) e existe nos dois estados.

---

## Resultado esperado ao final

- `card_printing_trait` POKEMON: 8 → **9**
- `card_printing_profile`: 10 → **11**
- `card_printing_profile_trait`: 15 → **16**
- `card_printing_external_mapping`: 9 → **10**
- `card_variant_type`: 94 → **97**
- `card_variant_type_external_mapping`: 90 → **95** (GLOBAL 74 → 75 · `base3` 2 → 5)
- Job BASE3 após revalidation: **177 VALID · 0 NEEDS_REVIEW**, `STAGED`
- Job BASE3 após a UI: **177 APPROVED · 177 INSERTED · 0 SKIPPED · 0 FAILED**
- `card_variant`: 7.494 → **7.671**
- Cobertura de Card de BASE3: 0/62 → **62/62**

> `inserted_rows` **não** é igual a Δ`card_variant` em geral — em BASEP foram 72
> INSERTED para +25 variantes, porque 47 Cards já tinham variantes. Em BASE3 os
> dois números coincidem **porque o Set parte de zero** e as 177 identidades são
> distintas. É por isso que o collision gate é pré-requisito, não formalidade.

---

## Fora desta rodada

- Decidir/confirmar as 177 rows — é da UI, nunca do runner.
- Documentação canônica (`docs/`) — closeout em rodada própria.
- Promoção de `2202` para `database/schema/` — só após execução confirmada.
- ~~Contradição de fonte sobre grading.~~ **REVOGADA.** O PSA Pokémon Error Guide
  lista explicitamente *"Zapdos-Holo Corrected & Uncorrected Foil"* e registra
  que a PSA **reconhece as duas variações**; há certificados correntes rotulados
  *"1999 POKEMON FOSSIL #15 ZAPDOS-HOLO CORRECTED FOIL"*. A leitura anterior
  ("mesmo spec para erro e corrigido") vinha de dois links do guia comunitário
  que apontavam para a mesma página, não do catálogo da PSA. `EVOLUTION_BOX_ERROR`
  é **PROVEN** nas duas frentes: variedade de tiragem (Bulbapedia + Elite Fourum)
  **e** reconhecida por grading (PSA). O alinhamento com `AOKI_CREDIT` é completo.
  **A decisão semântica não muda:** continua Printing trait/profile.
- Limitação de domínio aceita: a identidade de `#15 Zapdos` Cosmos ©1999 fica
  `COSMOS_HOLO + NULL` — o modelo não registra que é especificamente a tiragem
  Cosmos ©1999. Inambíguo hoje dentro de BASE3; análogo à limitação de idioma
  aceita em `STANDARD_PIKACHU_WORLD_2000` (BASEP).

---

## Reconciliação canônica — 2026-09-18

`BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01` classificou cada Query
deste ciclo por **natureza**, e não em bloco. Esta pasta permanece como
**evidência histórica** do staging; a fonte executável passou a ser:

| Query | Natureza | Destino |
|---|---|---|
| `2202` | **seed / reference data** (1 `card_printing_trait`) | `database/seeds/2202_add_base3_evolution_box_error_trait.sql` |

**Execução direta, sem ledger — declarado, não mascarado.** A `2202` foi aplicada
por `execute_sql` direto em 2026-09-18 02:51:27 UTC e **não possui entrada** em
`supabase_migrations.schema_migrations`. Nenhuma entrada de migration foi
fabricada para encobrir isso. Prova independente por dado, e não por cabeçalho:
`public.card_printing_trait.code = 'EVOLUTION_BOX_ERROR'` tem
`created_at = 2026-09-18 02:51:27.65747+00`, exatamente o timestamp declarado.

Nada foi reexecutado contra o Supabase nesta rodada — promoção canônica e
fold-in são alteração de arquivo, não execução (ver `database/README.md`,
seção "Queries `CANÔNICA` vs. `MIGRATION`").
