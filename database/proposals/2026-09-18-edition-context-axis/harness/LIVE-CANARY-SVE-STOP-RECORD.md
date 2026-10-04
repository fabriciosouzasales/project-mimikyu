# Canary real pós-UNFREEZE (SVE): registro do STOP

| Campo | Valor |
|---|---|
| **Mandatos** | `EDITION-CONTEXT-POST-UNFREEZE-CANARY-EXECUTION-01` (execução) · `BATCH12-POST-UNFREEZE-CANARY-ACL-CORRECTION-01` (diagnóstico e correção proposta) |
| **Baseline Git** | HEAD `e40fc50c8195bcdf0a472bd2a98c71b884768616` (`docs(batch12): close formal unfreeze and authorize canary`) |
| **Card Set** | SVE — Energias Escarlate e Violeta · `4aa12397-fe3c-4ae3-95ba-63a17123a48a` · `external_set_id = sve` |
| **Edge** | `import-card-variants` v15, ACTIVE, `verify_jwt=true`, `ezbr_sha256 = e60203f6…d59382` |
| **PRE oficial** | `2026-10-04 14:36:23.746807+00` |
| **Submissão** | única, por Fabrício, na tela `/catalogo/importar-variantes` (Server Action `iniciarImportacaoVariantes`); sem retry |
| **Resultado** | **STOP.** Canary **não** aprovado. |

## 1. O que aconteceu

A tela devolveu `Falha ao processar a importação: VARIANT_IMPORT_ROWS_INSERT_FAILED: permission denied for function axis_identity_token`.

Único job criado depois do PRE:

| Campo | Valor |
|---|---|
| `id` | `3ec9c551-b91f-43df-b360-60d796e47623` |
| `card_set_id` | `4aa12397-fe3c-4ae3-95ba-63a17123a48a` |
| `source` / `external_set_id` | `TCGDEX` / `sve` |
| `status` / `progress_step` | `FAILED` / `NULL` |
| `error_summary` | `VARIANT_IMPORT_ROWS_INSERT_FAILED: permission denied for function axis_identity_token` |
| `created_at` | `2026-10-04 14:45:55.742895+00` |

## 2. Contenção (auditada independentemente)

- jobs 145 → 146; exatamente 1 job novo; nenhum outro.
- `catalog_variant_import_row` 26.127 → 26.127; o job FAILED tem **0 rows** (o INSERT em lote é atômico: nada parcial).
- `card_variant` 24.893 → 24.893; com EC 0 → 0; nenhuma `card_variant` atualizada depois do PRE.
- `in_flight = 0`; SVE ativo = 0 (FAILED fica fora do índice de idempotência; o SVE continua retentável).
- `uq_cvir_row_identity` e `uq_card_variant_identity` unique/valid/ready; guards 2214 e 2224 habilitados.

## 3. Causa raiz (confirmada no repositório e no LIVE, só leitura)

- A `2210` (LIVE `20260920171100`) criou `internal.axis_identity_token(jsonb,text)` e o índice de expressão `uq_cvir_row_identity`, que chama a função nos dois eixos.
- A ACL da função é `{postgres=X, authenticated=X}`: a 2210 revogou de PUBLIC e anon e concedeu só a `authenticated`.
- O writer real das rows é a Edge, com client `service_role`: tem INSERT na tabela, **não** tem EXECUTE na função. Avaliar a expressão do índice no INSERT exige EXECUTE do papel efetivo, daí o erro.
- `authenticated` não tem INSERT/UPDATE na tabela. As cinco RPCs que atualizam rows (`apply_variant_type_mapping`, `create_card_printing_profile_with_backfill`, `admin_confirm/decide/resolve_*`) são SECURITY DEFINER, owner `postgres`, e não são afetadas.
- Única função referenciada por índice/constraint/default da tabela: `axis_identity_token`. O trigger `trg_cvir_normalized_shape` não é afetado (EXECUTE de função de trigger só é verificado no CREATE TRIGGER).
- Por que os gates anteriores não pegaram: provaram existência, integridade e semântica do índice, mas nunca confrontaram o papel efetivo do writer com a ACL da função da expressão.

## 4. Correção proposta (não aplicada)

- `../2235_grant_axis_identity_token_service_role.sql` — um único `GRANT EXECUTE … TO service_role`, com pré e pós-condição fail-loud. Sem REINDEX, sem mudança de função, índice, guard, RLS, privilégio de tabela, Edge ou frontend. A 2210 não é editada.
- `../2835_validate_staging_writer_acl.sql` — regression gate read-only. Controle negativo executado no LIVE em `2026-10-04T14:58:07Z` (antes da 2235): `gate_pass = false`, falhando só `g_sr_exec_token` e `g_writer_execs_all_index_fns`; os outros 10 gates true.

## 5. Estado e próximo passo

**CANARY REAL PÓS-UNFREEZE = STOP.** Job FAILED preservado como evidência; nada limpo; `2831` e `2213` não executadas.

**NEXT:** auditoria independente da 2235/2835 → aplicação da 2235 com mandato próprio → 2835 `gate_pass = true` + Edge v15 inalterada → só então retry do canary SVE, com mandato próprio.
