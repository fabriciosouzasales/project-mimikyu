# Canary real pós-UNFREEZE (SVE): retry único · Registro do PASS

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH12-POST-ACL-SVE-RETRY-LIVE-ACT-01` (execução) · `BATCH12-POST-ACL-SVE-RETRY-LIVE-CLOSEOUT-01` (registro) |
| **Autorização** | Fabrício: "Autorizo o retry único do canary SVE no LIVE." — cobre só o PRE JIT, um único retry pelo fluxo autenticado normal, polling read-only, POSTCHECK P1–P14, `2835` e L3 pós-execução. Não cobre segundo clique, confirmação de staging, escrita em `card_variant`, `2831`, `2213`, migration, deploy ou Git. |
| **Baseline Git** | HEAD `2a9c232b878901bc7bff57f5f238a1a85d7c6794` (`docs(batch12): close ACL apply and prepare SVE retry`), árvore e índice limpos |
| **Card Set** | SVE — Energias Escarlate e Violeta · `4aa12397-fe3c-4ae3-95ba-63a17123a48a` |
| **Edge** | `import-card-variants` v15, ACTIVE, `verify_jwt=true`, `ezbr_sha256 = e60203f6…d59382` (inalterada) |
| **Instrumentos** | `../2835_validate_staging_writer_acl.sql` blob `ef6d96c06c6964a83a32db4c84a03992dbfde783` · `evidence/P14A-LIVE-CAPTURE-2026-10-04/L3.sql` blob `b10d32e7ed57da2456a28de465e421cba263b08a` — ambos submetidos como publicados |
| **Resultado** | **PASS** — P1–P14 PASS. **Eixo 3 (Edition Context) provado em importação real.** |

## 1. Sequência

| # | Passo | Momento (servidor, UTC) | Resultado |
|---|---|---|---|
| 1 | PRE JIT renovado (SELECT) + `2835` + L3 + Edge | `act_pre_at = 2026-10-04 20:42:58.550978` | ACT-GATE PASS |
| 2 | Ação humana: **exatamente 1 clique** em "Analisar" (Fabrício, `/catalogo/importar-variantes?cardSetId=4aa12397-…`) | — | 1 submissão |
| 3 | Job criado | `created_at = 20:44:08.487163` | `dcef3bd2-95f5-46de-894c-3dd125f185c9` |
| 4 | Estado terminal | `updated_at = 20:44:11.228001` | `STAGED` |
| 5 | `2835` pós-ACT | `checked_at = 20:46:06.924687` | `gate_pass = true`, 12/12 |
| 6 | L3 pós-ACT | `checked_at = 20:46:13.45317` | `locks_on_scope = []` |

A tela exibiu "Concluído — 112 variantes propostas · 112 válidas"; Revisão: 112 analisadas, 0 aprovadas, 0 rejeitadas, 48 pendentes, 0 sem mapeamento; botão "Confirmar 64 variantes" **não** acionado.

## 2. Job `dcef3bd2-95f5-46de-894c-3dd125f185c9`

| Campo | Valor |
|---|---|
| `status` / `progress_step` / `error_summary` | `STAGED` / `NULL` / `NULL` |
| `total_rows` / `valid_rows` / `failed_rows` | 112 / 112 / 0 |

## 3. Composição das 112 rows

| Dimensão | Contagem |
|---|---|
| validation | VALID 112 |
| match | MATCHED 64 · NEW 48 |
| decision | SKIPPED 64 · PENDING 48 |
| persistence | PENDING 112 |
| `variant_type_id` null | 0 |
| printing resolver state | `RESOLVED_NO_PRINTING` 112 · outro / unresolved 0 |
| chave `printing_profile_id` presente em `normalized_data` | 112 / 112 |
| `printing_profile_id` non-null | 0 |
| edition_context resolver state | `RESOLVED_WITH_EC_PROFILE` 48 · `RESOLVED_NO_EDITION_CONTEXT` 64 · unresolved / outro 0 |
| chave `edition_context_profile_id` presente em `normalized_data` | 112 / 112 |
| `edition_context_profile_id` non-null | **48** = Player Rewards `52447b63-b80d-4917-88f7-43069b77fa80` **32** + Professor Program `edea26c7-ef0a-4174-a856-5520566182e0` **16**; outro UUID 0 |
| `edition_context_profile_id` null (resolvido sem eixo) | 64 |
| identidades distintas | 112 |
| `duplicate_resolved_skipped` | 0 |
| same-game mismatch | 0 |

**Dedupe (`duplicate_resolved_skipped = 0`).** Input esperado = 112 combinações; `total_rows` = 112; rows de staging = 112; identidades distintas = 112; `error_summary` NULL. No código publicado da Edge, uma row duplicada é contada em `duplicateResolvedSkipped` e descartada antes de entrar nas rows resolvidas; qualquer descarte teria reduzido `total_rows` abaixo das 112 combinações da fonte.

## 4. Contenção (PRE → POST)

| Métrica | PRE | POST |
|---|---|---|
| `catalog_variant_import_job` | 146 | 147 (+1) |
| `catalog_variant_import_row` | 26.127 | 26.239 (+112) |
| `card_variant` | 24.893 | 24.893 |
| `card_variant` com EC | 0 | 0 |
| max(`card_variant.updated_at`) | `2026-09-19 00:48:41.964146+00` | inalterado |
| `resulting_variant_id` non-null (job novo) | — | 0 |

Único delta funcional: +1 job, +112 rows de staging. Nenhuma `card_variant` criada ou atualizada (zero drift); staging **não** confirmado.

## 5. Infraestrutura pós-ACT

- `2835`: `gate_pass = true`, 12/12; `d_idx_def_md5 = ad46a9fedb3517431ecbbb0324d959c9`.
- L3: `locks_on_scope = []`.
- `uq_cvir_row_identity` e `uq_card_variant_identity`: unique / valid / ready.
- `trg_cvir_normalized_shape` (`catalog_variant_import_row`) e `trg_card_variant_edition_context_profile_game` (`card_variant`): `tgenabled = O`.

## 6. POSTCHECK P1–P14

| # | Critério | Resultado |
|---|---|---|
| P1 | exatamente 1 job SVE novo; jobs = 147 | PASS |
| P2 | STAGED, `progress_step` NULL, `error_summary` NULL, `failed_rows` 0 | PASS |
| P3 | total = valid = 112; 112 rows no job; staging global 26.239 | PASS |
| P4 | `variant_type` null = 0 | PASS |
| P5 | printing unresolved = 0 · `RESOLVED_NO_PRINTING` = 112 · chave presente 112/112 · `printing_profile_id` non-null = 0 | PASS |
| P6 | EC unresolved = 0 · chave presente 112/112 · 48 `RESOLVED_WITH_EC_PROFILE` (32 Player Rewards + 16 Professor Program, outro UUID 0) · 64 `RESOLVED_NO_EDITION_CONTEXT` | PASS |
| P7 | EC non-null = 48 | PASS |
| P8 | `52447b63` = 32 · `edea26c7` = 16 · outro = 0 · null = 64 | PASS |
| P9 | 112 identidades distintas · `duplicate_resolved_skipped` = 0 · MATCHED/SKIPPED 64 · NEW/PENDING 48 | PASS |
| P10 | `card_variant` 24.893, EC 0, max `updated_at` inalterado | PASS |
| P11 | +1 job, +112 rows, nada mais | PASS |
| P12 | `2835` 12/12; índices unique/valid/ready; guards habilitados; L3 limpo | PASS |
| P13 | job `3ec9c551…` continua FAILED / 0 rows | PASS |
| P14 | nenhuma confirmação; `resulting_variant_id` non-null 0 | PASS |

## 7. Sequência causal preservada

1. **Primeiro canary SVE = STOP / FAILED** — job `3ec9c551-b91f-43df-b360-60d796e47623`, 0 rows, causa ACL de `internal.axis_identity_token` (`LIVE-CANARY-SVE-STOP-RECORD.md`). **Não reclassificado.**
2. **ACL correction `2235` = PASS · ACL blocker CLOSED** — ledger `20261004182941` (`LIVE-ACL-2235-APPLY-RECORD.md`).
3. **Retry único SVE = PASS** — este registro.

## 8. Estado e próximo passo

- **SVE RETRY = PASS · Edition Context em importação real = PROVADO.**
- Staging do job `dcef3bd2…` **NÃO confirmado**; `card_variant` intacta.
- `2831` **NÃO** executado; `2213` **NÃO** executada; nenhum dos dois está liberado por este registro.
- **NEXT:** auditar e publicar este closeout → só depois definir formalmente o próximo gate de rollout.
