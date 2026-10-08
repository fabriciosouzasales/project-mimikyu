# Batch 13 — `2831` → `2213` / Legacy Decomposition · Registro de encerramento

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH13-FINAL-CLOSEOUT-PREP-01` (preparação) · `BATCH13-FINAL-CLOSEOUT-01` (registro) |
| **Natureza** | Somente documental. Nenhum SQL, nenhum SELECT novo, nenhum acesso LIVE. O encerramento usa apenas evidência já publicada e auditada. |
| **Baseline Git** | branch `main` · HEAD `79e9239d20bd60691ae4c0a785ecea80bf34fe08` (`docs(batch13): close 2213 v1.0 live apply`) · parent `c7848edbd24046138b63d8e7f6b1cd9652220c5a` · árvore e índice limpos |
| **Data** | 2026-10-07 |
| **Decisão** | **BATCH 13 = CLOSED** |

## 1. Escopo

O Batch 13 é a frente **`2831` → `2213` / LEGACY DECOMPOSITION**: decompor as 285 READY_UNCONDITIONED legadas nos eixos Finish + Edition Context, com o lineage reconciliado na mesma transação. Inclui os pré-requisitos semânticos necessários: `2236`, `2237`, `2831` v3.1 e `2213` v1.0.

**Fora do escopo** (frentes posteriores próprias; nenhuma dívida delas é fechada aqui):

- as 80 READY_PRICING_CONDITIONED e `PRICING-CATALOG-VARIANT-RECONCILIATION-01`;
- `VARIANT-DISPLAY-SEMANTICS-01` e o frontend de exibição (`FRONTEND-DISPLAY-CONTRACT.md`);
- `NEEDS_REVIEW` editorial e `CATALOG-HISTORICAL-BOOTSTRAP-03`;
- `CATALOG-VARIANT-DEFAULT-BACKFILL-01`;
- `BULK-04` / `BULK-05` / `BULK-06`;
- Collections UX e Frontend.

## 2. Matriz final

| Artefato | Estado | Registro |
|---|---|---|
| `2236` | **CLOSED / APPLIED / PASS / DOCUMENTED** | `LIVE-2236-APPLY-RECORD.md` |
| `2237` v1.0 | **ATTEMPTED / FAILED INTERNAL POST / ROLLED BACK / ZERO LIVE DELTA / SUPERSEDED** | `LIVE-2237-FAILED-ATTEMPT-RECORD.md` |
| `2237` v1.1 | **CLOSED / APPLIED / PASS / DOCUMENTED** | `LIVE-2237-V11-APPLY-RECORD.md` |
| `2831` v3.1 | **SIMULATION PASS / ROLLED BACK / ZERO PERSISTENT DELTA / GATE A FINAL PASS / DOCUMENTED** | `LIVE-2831-V31-SIMULATION-RECORD.md` |
| `2213` v1.0 | **APPLIED / FINAL PASS / DOCUMENTED** | `LIVE-2213-V10-APPLY-RECORD.md` |

Os cinco registros estão neste diretório (`harness/`) e foram publicados no `main` até `79e9239d`. O cabeçalho do artefato `2213_decompose_legacy_card_variants.sql` continua dizendo "PROPOSTA / NÃO EXECUTADA": artefatos aplicados não são reescritos para atualizar status. A autoridade do estado de execução é o registro LIVE.

## 3. Cadeia causal

1. A readiness de B-SEMANTIC encontrou **46/285** Variants sem destino determinístico (33 `NEEDS_REVIEW_NO_EC_PROFILE` · 11 `RESOLVED_NO_EDITION_CONTEXT` · 2 finish NULL) — `2213-CRITICAL-PATH-DECISION.md` §8.
2. Fabrício adjudicou D1(a′), D2, D3 e D4 (APPROVED) — §9.1.
3. `2236` aplicada: catálogo de Edition Context +1 trait / +31 profiles / +50 links; **NO_PROFILE 33 → 0**.
4. `2237` v1.0 abortou no gate POST de fingerprint, que não era null-safe; ROLLBACK integral, zero delta LIVE.
5. `2237` v1.1 aplicada: +2 mappings de finish SOURCE_SET; **FINISH NULL 2 → 0**.
6. Fato LIVE do estágio genérico: **274/285**, com resíduo **11** = 6 Pikachu + 4 League + 1 Player Reward.
7. `2831` v3.1 executada como simulação: a camada HISTORICAL OVERRIDE provou **285/285** dentro da transação, terminou em ROLLBACK com zero delta persistente, e o **Gate A** foi declarado **FINAL PASS**.
8. `2213` v1.0 preparada (clone do corpo da `2831` v3.1 com 3 deltas), auditada, corrigida no contrato L5 e publicada (`c7848edb`).
9. PRE read-only congelou os conjuntos 285/336 e os fingerprints POST esperados; `2213` v1.0 aplicada com uma submissão, sem retry.
10. POST definitivo independente: **285/285** Variants e **336/336** rows de lineage iguais aos estados esperados congelados.
11. **Batch 13 CLOSED** (este registro).

## 4. Resultado material

| Medida | Valor |
|---|---|
| READY_UNCONDITIONED inicial | 285 |
| Materializadas pela `2213` | **285 / 285** |
| READY_UNCONDITIONED residual | **0** |
| Rows de lineage-alvo | 336 |
| Reconciliadas | **336 / 336** |
| Híbrido L2 | 0 |
| `card_variant` total | 24.893 (inalterado) |
| ids das 285 preservados | 285 / 285 |
| Fora do escopo | **zero drift** |

**Fingerprints definitivos:**

| Fingerprint | Valor |
|---|---|
| CV POST (285) | `c14f6fdbb838fa170db2c6db87dd54cc` |
| LINEAGE POST (336) | `a4b21ecda07ef7800bf0fdb74f18526d` |
| `cvir_out` (25.903 rows fora do lineage-alvo) | `d801514d9c60e0c5923c6578ca7fceff` |
| `cv_out` (24.608 Variants fora do plano) | `dd7108a9282b39062271c447fc8b6c82` |

Requisitos L1–L9 da Seção L da `2830` (`2830_validate_edition_context_foundation.sql`):

- todos estão implementados como gates fail-loud no próprio artefato;
- nenhum abortou na execução;
- o POST externo confirmou o efeito (L1, L2, L3, L4, L8, L9) e a exclusão de HOLD e Pricing (L5, L6, L7).

## 5. B-SEMANTIC — fechamento

| Etapa | Resultado |
|---|---|
| Baseline | 46 / 285 sem destino determinístico |
| Após `2236` | NO_PROFILE 33 → 0 |
| Após `2237` v1.1 | FINISH NULL 2 → 0 |
| Resíduo genérico | 11 = 6 Pikachu + 4 League + 1 Player Reward |
| `2831` v3.1 | HISTORICAL OVERRIDE provou 285/285 na simulação |
| `2213` v1.0 | **285/285 fisicamente decompostas no LIVE** |

O HISTORICAL OVERRIDE é **reconciliação histórica escopada** das 11 Variants legadas e **não** é routing operacional:

- nenhum mapping, resolvedor, lookup ou constraint foi alterado por ele;
- o mapping operacional **`PIKACHU-TAIL` = 0**.

## 6. Pricing — limite de escopo

| Medida | Valor |
|---|---|
| READY_PRICING_CONDITIONED | 80 |
| `STAFF_HOLO` | 40 |
| `SET_LOGO_REVERSE` | 40 |
| `edition_context_profile_id` não-NULL nas 80 | 0 |

Estado: **PROTEGIDAS / NÃO DECOMPOSTAS / FORA DO ESCOPO DO BATCH 13.** As 80 foram deliberadamente excluídas do plano 285 (guard do PASSO 0B; `pricing_source_card_identity` e `pricing_source_variant_mapping` testados separadamente). Elas pertencem à frente posterior `PRICING-CATALOG-VARIANT-RECONCILIATION-01` (`ROLLOUT-ORDER.md` etapa 19) e não impedem este encerramento. **Pricing não é declarado CLOSED.**

## 7. D1 / segurança de escopo

| Item | Estado |
|---|---|
| BASE2 #60 | fora do plano · STAGED · NEEDS_REVIEW / PENDING / PENDING · `resulting` NULL · `matched` NULL · md5 `a0acad95ae681cc607144681e42c718f` |
| BASEP #24 | fora do plano · md5 `bd9d0118b2502f636b0d1d83dae31979` |
| Mapping operacional `PIKACHU-TAIL` | 0 |
| Variants criadas | 0 |

**D1 HOLD-safe = PASS.** HOLD 107 intocado.

## 8. Forward-fixes finais

traits 116 · profiles 175 · profile_trait 246 · EC mappings 122 · EC mapping links 122 · finish mappings 96 (GLOBAL 75 · SOURCE_SET 21) · alvos da `2237` 2. Nenhuma regressão.

## 9. Incidentes históricos preservados

Os dois incidentes ficam registrados como aconteceram, sem reclassificação:

| Incidente | Estado | Registro | Sucessor PASS publicado |
|---|---|---|---|
| `2237` v1.0 | FAILED / ROLLED BACK | `LIVE-2237-FAILED-ATTEMPT-RECORD.md` | `2237` v1.1 |
| Primeiro canary SVE (Batch 12) | STOP / FAILED | `LIVE-CANARY-SVE-STOP-RECORD.md` | `2235` + retry SVE PASS |

Nenhum dos dois impede o encerramento, porque cada um tem sucessor PASS formalmente publicado.

## 10. Critério de CLOSED

| # | Critério | Evidência | Resultado |
|---|---|---|---|
| A | `2236` CLOSED | `LIVE-2236-APPLY-RECORD.md`; 2213 §9.12 | ✅ |
| B | `2237` v1.1 CLOSED | `LIVE-2237-V11-APPLY-RECORD.md`; 2213 §9.12 | ✅ |
| C | `2831` v3.1 Gate A FINAL PASS | `LIVE-2831-V31-SIMULATION-RECORD.md` §8 | ✅ |
| D | `2213` v1.0 APPLIED / FINAL PASS | `LIVE-2213-V10-APPLY-RECORD.md` §9 | ✅ |
| E | 285/285 materializadas | idem §7.1 (CV `c14f6fdb…`) | ✅ |
| F | 336/336 reconciliadas | idem §7.2 (lineage `a4b21ecd…`) | ✅ |
| G | READY_UNCONDITIONED residual = 0 | idem §7.4 | ✅ |
| H | zero out-of-scope drift | idem §7.3 | ✅ |
| I | Pricing 80 preservadas e fora do escopo | idem §7.5; §6 acima | ✅ |
| J | D1 intacto | idem §7.6 | ✅ |
| K | sem transação residual / sem blocker material conhecido | idem §7.8 (locks/xid/idle 0); nenhum record final registra blocker aberto do escopo | ✅ |

**11/11 sustentados documentalmente → BATCH 13 = CLOSED.**

## 11. Limites

- Este encerramento **não** autoriza staging, commit, push nem início de nova frente.
- Ele **não** fecha as 80 de Pricing, `VARIANT-DISPLAY-SEMANTICS-01`, as `NEEDS_REVIEW` editoriais nem qualquer item listado como fora do escopo (§1).
- Nenhuma reexecução da `2213` ou da `2831`. A `2213` é não idempotente por contrato (`PLAN_ALREADY_DECOMPOSED` aborta).
- Nenhuma edição dos artefatos `2213`/`2831`/`2236`/`2237` nem dos registros LIVE.

## 12. NEXT (sem iniciar)

A próxima frente funcional pelo roadmap vigente (`docs/ROADMAP.md`) é **`VARIANT-DISPLAY-SEMANTICS-01`**, junto com a experiência editorial de `NEEDS_REVIEW`.

O `FRONTEND-DISPLAY-CONTRACT.md` recomendava o deploy de exibição "depois da `2213`"; essa condição agora está satisfeita, e o contrato serve de insumo dessa frente, não de gate anterior a ela.

A etapa 19 do rollout (Pricing 80) continua **BLOQUEADA / PENDENTE**.

Nada começa sem mandato explícito de Fabrício.
