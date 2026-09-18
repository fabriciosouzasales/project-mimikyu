# BASEP — Editorial Convergence · Staging

| Campo | Valor |
|---|---|
| **Mandato** | `BASEP — IMPLEMENTATION STAGING-01` |
| **Data** | 2026-09-18 |
| **Status** | **EXECUTADO / LIVE VALIDATED / CLOSED (2026-09-18)** |
| **Job LIVE** | `cf829d56-921c-4e97-983d-0aec56690464` · `basep` · **`COMPLETED`** · 74 / 72 `VALID` / 2 `NEEDS_REVIEW` deferidas · 72 `APPROVED`+`INSERTED` · 2 `SKIPPED`+`UNCHANGED` · 0 `FAILED` |
| **Resultado** | `card_variant` 7.469 → 7.494 · BASEP 53/53 Cards com variante (72 variantes) |
| **Baseline git** | `80cc268` |

---

## Conteúdo

| Arquivo | O que é | Transporte |
|---|---|---|
| `2201_add_basep_printing_traits.sql` | 3 `INSERT`s em `card_printing_trait` (`GREY_STAR_SYMBOL` 6, `GLOSSY_STOCK` 7, `AOKI_CREDIT` 8) | **migration guardada** (único SQL fora do caminho canônico) |
| `basep-authenticated-runner.js` | Runner efêmero de DevTools — 18 RPCs canônicas com a sessão admin real | **não é produto**; cola-se no console uma vez e morre com o refresh |

---

## Por que a Query 2201 existe

`card_printing_trait` é a **única** das cinco classes de objeto sem writer canônico:

```
writers_de_trait = []      -- zero funções com INSERT INTO card_printing_trait
```

E `catalog_admin_action_log` não tem `entity_type` para trait. O modelo tratou trait como
**vocabulário semeado** (os 5 atuais nasceram todos no mesmo timestamp, pela Query 2169),
não como objeto editorial de runtime. A 2201 segue esse precedente.

**A Query 2169 NÃO é alterada.** Ela é histórico LIVE e declara no cabeçalho que o SQL
executável permanece intocado desde 2026-09-12. A 2201 é incremento — mesma disciplina de
`6109`/`6110`/`6125`/`6126`.

---

## Divisão de trabalho

| objeto | transporte | writer |
|---|---|---|
| 3 traits | migration `2201` | — (não existe) |
| 3 profiles | runner | `public.admin_create_card_printing_profile_with_backfill` |
| 4 printing mappings | runner | `public.admin_resolve_catalog_variant_import_printing_mapping` |
| 5 variant types | runner | `public.admin_create_card_variant_type` |
| 6 VT mappings SCOPED | runner | `public.admin_resolve_catalog_variant_import_mapping_for_set` |
| aprovar 25 · pular 2 · confirmar | UI existente | `admin_decide_catalog_variant_import_row` (lote) · `admin_confirm_catalog_variant_import` |

**Não usar `admin_create_card_variant_type_with_import_mapping`:** ele chama
`admin_resolve_catalog_variant_import_mapping`, que cria mapping **GLOBAL**. BASEP exige **SCOPED**.

---

## Atomicidade — leia antes de executar

A migration `2201` é um bloco `DO` único, portanto atômica.

**As 18 RPCs do runner NÃO são.** Cada uma é sua própria transação e faz COMMIT sozinha.
Um erro na chamada N **não desfaz** as N−1 anteriores. Por isso o runner é:

- **fail-closed** — para na primeira divergência, não compensa nada;
- **resumable** — antes de cada objeto consulta o estado: ausente → executa; presente e
  idêntico → checkpoint concluído, segue; presente e divergente → STOP. Nunca repete uma
  criação às cegas. Reexecutar o script após uma parada é seguro.

---

## Ordem obrigatória

```
2201 (traits) → profiles → printing mappings → variant types → VT mappings → gate → UI
```

O resolver consome o eixo Printing **antes** do Variant Type. Se os 4 tokens de Printing
não existirem primeiro, eles permanecem no residual e **nenhum** mapping VT casa.

---

## Gates

| fase | esperado | falha ⇒ |
|---|---|---|
| A — preflight | `is_admin()` = TRUE · job `basep/STAGED/74/47` · 27 resíduos · 12 assinaturas exatas · 8 traits | STOP antes da 1ª escrita |
| B — profiles | `rows_touched` = **0** (mappings ainda não existem) | STOP |
| C — printing mappings | `jobs_affected` = **1** em cada | STOP — impacto fora de BASEP |
| D — variant types | 5 UUIDs devolvidos | STOP |
| E — VT mappings | `scope_kind` = `SOURCE_SET` · `external_set_id` = `basep` | STOP |
| F — gate final | **72 VALID · 2 NEEDS_REVIEW**, e as 2 são exatamente `holo + pikachu-tail` e `holo + subtype:missing-hp` | STOP — não decidir nem confirmar |

---

## Prova de impacto cross-job dos 4 tokens Printing

Varredura de 6.755 rows / 30 jobs, com a normalização do resolver:

| token | total | basep | base3 | outros Sets |
|---|---|---|---|---|
| `stamp:GREY-STAR` | 1 | 1 | 0 | 0 |
| `subtype:GLOSSY` | 1 | 1 | 0 | 0 |
| `subtype:AOKI-ERROR` | 3 | 3 | 0 | 0 |
| `stamp:1ST-EDITION-ERROR` | 1 | 1 | 0 | 0 |

Controle negativo — `stamp:1ST-EDITION` (token vizinho, já mapeado): 268 rows, **0 em basep**,
62 em BASE3 `STAGED`, 206 em base1. Strings distintas, casamento por igualdade exata: criar
`1st-edition-error` **não toca** nenhuma das 268.

---

## Resultado esperado ao final

- `card_printing_trait` POKEMON: 5 → **8**
- `card_printing_profile`: 7 → **10**
- `card_printing_external_mapping`: 5 → **9**
- `card_variant_type`: 89 → **94**
- `card_variant_type_external_mapping`: 84 → **90**
- Job BASEP: 25 resolvidas, **2 deferidas** (`DEFERRED`)
- `card_variant`: 7.469 → **7.494**
- Cobertura de Card de BASEP: 47/53 → **53/53**

---

## Fora desta rodada

- `MISSING_HP` — nenhum trait, profile ou mapping. `#17 Dark Persian` fica `DEFER_CANDIDATE`
  (`SOURCE_OMISSION / FINISH NOT SAFELY DERIVABLE`).
- `holo + pikachu-tail` (#24) — `DEFER_CANDIDATE` (`SOURCE_CONTRADICTION`).
- Documentação canônica (`docs/`) — closeout em rodada própria.
