# CALL GRAPH E CONTRATOS IMPACTADOS

Corrigido na `CORRECTION-01`. A versão anterior chamava tudo de "writer" e
parava em 12 funções SQL — **o inventário agora tem 5 categorias e inclui a Edge**.

## A — CARD_VARIANT WRITE PATH

Únicos caminhos que **escrevem** em `card_variant`.

| Objeto | Mudança |
|---|---|
| `internal.write_card_variant` | aceitar 4º componente `p_edition_context_profile_id`; matching por identidade de 4 |
| `public.admin_confirm_catalog_variant_import` | ler `normalized_data.edition_context_profile_id` (tri-state) e propagar ao writer |

## B — ROUTING / STAGING PROPAGATION

Resolvem eixos e/ou reescrevem `normalized_data`. **Nenhum pode reimplementar
Edition Context** — todos passam a chamar `internal.resolve_variant_row_axes` (2211).

| Objeto | Mudança |
|---|---|
| `internal.compute_variant_residual_signature` | **inalterada.** Continua resolvendo size-scope + Printing; passa a ser chamada por 2211 |
| `internal.apply_variant_type_mapping` | usar 2211; gravar as DUAS chaves de eixo |
| `internal.lookup_variant_type_for_row` | receber residual **pós-dois-eixos** |
| `internal.variant_type_mapping_decision` | idem |
| `internal.variant_type_mapping_impact` | contar impacto pela identidade de staging de 4 componentes |
| `public.admin_preview_catalog_variant_import_mapping` | expor `edition_context_state` no preview |
| `public.admin_resolve_catalog_variant_import_mapping` | revalidação em lote via 2211 |
| `public.admin_resolve_printing_mapping` | inalterada na lógica; revalidação passa por 2211 |
| `internal.create_card_printing_profile_with_backfill` | backfill **preservar** `edition_context_profile_id` |
| `public.admin_create_card_variant_type_with_import_mapping` | wrapper: revalidar via 2211 |

## C — READ MODELS

Expõem identidade para UX/progresso. Se ignorarem o eixo, a UI mente.

| Objeto | Mudança |
|---|---|
| `public.collection_master_set_scope_positions` | projetar `edition_context_profile_id` |
| `public.validate_card_variant_game_consistency` | ~~**ESTENDER** — validar same-Game do edition_context~~ · **DESCARTADO** em `BATCH9-2217-READINESS-CORRECTION-01`. Esta função **não é tocada**: permanece validando Card × Variant Type, com seu trigger `UPDATE OF card_id, variant_type_id` intacto. O same-Game do 3º eixo passa a ter **guard dedicado**, a **Query `2224`** — espelho da `2170`, que já resolve o mesmo problema para Impressão. Motivo: `161` é `SECURITY INVOKER` sem `search_path` fixado; estendê-la herdaria padrão de segurança inferior ao vigente, e uma função multi-eixo obriga o `UPDATE OF` a crescer a cada eixo novo — exatamente o modo de falha que deixou este eixo desprotegido |
| **`internal.enforce_card_variant_edition_context_profile_game`** | ✅ **CRIADA E ATIVA NO LIVE** (Query `2224`, 2026-09-22 — `BATCH9-2224-CLOSEOUT-01`) — autoridade **única** de same-Game do 3º eixo. `SECURITY DEFINER` · `search_path=''` · retorno imediato em `NULL` · trigger `trg_card_variant_edition_context_profile_game` `BEFORE INSERT OR UPDATE OF card_id, edition_context_profile_id` |
| `public.admin_get_pricing_mapping_detail` | expor o eixo (Pricing, mandato separado) |
| `public.admin_resolve_pricing_mapping` | idem |

## D — EDGE PRODUCER

`supabase/functions/import-card-variants/`

| Arquivo | Evidência | Mudança |
|---|---|---|
| `index.ts` **1004–1007** (verificado) | `const normalizedData: Record<string, unknown> = {};`<br>`if (variantTypeId !== null) normalizedData.variant_type_id = …;`<br>`normalizedData.printing_profile_id = printing.printingProfileId;` | acrescentar `normalizedData.edition_context_profile_id` **sempre** (JSON null ou UUID) |
| `services/database.ts` 455 · 492–497 | `buildPrintingProfileKeyPart()` e o comentário que documenta a chave composta de 3 partes | acrescentar a 4ª parte com a mesma disciplina tri-state |
| `services/database.ts` **521** (verificado) | `` `${row.card_id}\|${row.variant_type_id}\|${buildPrintingProfileKeyPart(row.printing_profile_id)}` `` — **3 partes** | **estender para 4 partes** — hoje colide com contextos distintos |

**Contrato semanticamente equivalente DB × Edge.** Toda linha VALID nova nasce
com **as duas chaves de eixo presentes**. O guard `trg_cvir_normalized_shape`
(2210) rejeita no banco o que a Edge produzir fora do contrato — a Edge não é
fonte de verdade da invariante, é apenas o primeiro produtor a respeitá-la.

**Testes Deno a acrescentar** (`edition-context.test.ts`):
1. token com mapping ativo ⇒ `edition_context_profile_id` = UUID
2. sem token ⇒ chave = `null` explícito, nunca ausente
3. token desconhecido ⇒ chave **ausente** + `NEEDS_REVIEW`
4. token consumido por Printing **não** reaparece no eixo 3
5. chave de matching de 4 partes distingue contextos diferentes
6. precedência scoped > global, um nível
7. linha VALID nunca sai da Edge sem as duas chaves

## E — NÃO IMPACTADOS (prova negativa)

`physical_card` (0 rows) · `collection_layout_slot_expected_content` (0) ·
`pricing_product` (0 com `card_variant_id`) · `catalog_variant_import_row`
FKs de lineage — preservadas porque `card_variant.id` não muda.

## Prova de cobertura — **RECONTADA no GATE-A-01**

> **Correção.** A versão anterior afirmava "**6** chamadores" e listava
> `lookup_variant_type_for_row` e `admin_preview_catalog_variant_import_mapping`,
> que **não chamam** a função, enquanto **omitia**
> `create_card_printing_profile_with_backfill`, que chama duas vezes.
> A lista era construída de memória. Abaixo está a medição sobre
> `database/schema/`, por arquivo e linha.

**Chamadas reais: 5 funções distintas, 7 call sites.**

| # | Função que chama | Arquivo | Linha(s) |
|---|---|---|---:|
| 1 | `public.admin_resolve_catalog_variant_import_printing_mapping` | `2181_…` | 470 |
| 2 | `internal.create_card_printing_profile_with_backfill` | `2189_…` | 258, 311 |
| 3 | `internal.variant_type_mapping_impact` | `2192_…` | 183 |
| 4 | `internal.variant_type_mapping_decision` | `2192_…` | 399 |
| 5 | `internal.apply_variant_type_mapping` | `2193_…` | 175, 222 |

**Os 5 estão em B.** `2144` e `2145` citam a função apenas em comentário de
cabeçalho — **não a invocam**; por isso não entram nesta contagem (`2145`
entra em A por escrever `card_variant`, não por chamar 2176).

`internal.lookup_variant_type_for_row` **não** chama 2176: recebe o residual
já computado como parâmetro. Permanece em B porque o residual que ele recebe
muda de significado (passa a ser pós-dois-eixos), não porque chame a função.

Após o rollout, nenhum dos 5 chama 2176 diretamente: todos passam por 2211,
que é o único ponto onde Edition Context é resolvido.
