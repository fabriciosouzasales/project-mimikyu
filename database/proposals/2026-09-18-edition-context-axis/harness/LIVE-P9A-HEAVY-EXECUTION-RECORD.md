# LIVE — P9A HEAVY (B, M, 5.2/5.3/5.7) · Registro de execução

| Campo | Valor |
|---|---|
| **Mandato** | `BATCH12-PHASE6-P9A-HEAVY-LIVE-EXECUTION-01` (execução, 2026-10-03) · fechamento: `BATCH12-PHASE6-P9A-INDEPENDENT-CLOSEOUT-AND-EVIDENCE-PRESERVATION-01` |
| **Baseline** | HEAD `7cb7ebd4bc7386c21d015a93b236a69695e8ab01` (`fix(batch12): complete P9a heavy plan coverage`), árvore e índice limpos antes e depois da execução |
| **Artefato** | `2830H_P9A_heavy_sections_explain.sql` — md5 `9ccc3c87450c2d533a5bff1d2718bf78`, 63.644 B, blob `4ed793f3e49a8423713d75cc438517999d789ecd`; 4 statements, 4 `EXPLAIN (COSTS OFF)`, 0 ANALYZE |
| **Canal** | MCP Supabase `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`; uma chamada = um statement |
| **Evidência** | `evidence/P9A-HEAVY-LIVE-2026-10-03/` — `MANIFEST.md5` (25 entradas, `md5sum -c` 25/25 OK), `.gitattributes` `* -text` |
| **Resultado** | **P9(a) CLOSED** (auditoria independente PASS) |
| **FREEZE** | ATIVO. Nada aqui autoriza UNFREEZE. |

## 1. Sequência

Exatamente 5 chamadas, cada uma iniciada após a resposta da anterior (horários de envio, UTC, registrados no transcript da sessão):

| # | Chamada | Envio | Resultado |
|---|---|---|---|
| S1 | L3 (verbatim de `LIVE-VALIDATION-PROTOCOL.md` §3.2) | 23:32:06.975Z | PASS |
| S2 | P9A-B (E12 · VREC) | 23:32:55.832Z | VALID / REGISTERED |
| S3 | P9A-M (E13 · SMREC) | 23:34:14.955Z | VALID / REGISTERED |
| S4 | P9A-5X (E15/E15P · DERIV-5X) | 23:35:27.926Z | VALID / REGISTERED |
| S5 | P9A-D1X (E15 · DERIV-D1X · 5.3/5.7) | 23:38:14.314Z | VALID / REGISTERED |

Os statements foram separados do artefato de forma determinística (texto de `EXPLAIN (COSTS OFF)` até `;`, com LF final; cabeçalho + rótulos + statements reconstroem o artefato byte a byte). O parâmetro `query` de cada uma das 5 chamadas, registrado no transcript, é byte-idêntico ao texto aprovado (`*.submitted.sql` = `*.sql`).

## 2. L3

- `checked_at = 2026-10-03T23:30:12.838099Z`.
- 10 sessões `client backend` (8 `authenticator`/PostgREST, 2 `supabase_admin`), todas `idle`, todas `xact_start = null`; além delas, `pg_cron launcher` e `pg_net` worker (não são `client backend`).
- `locks_on_scope = []`.
- L3 md5 `b7bc3700aeef278f6a79bd30e6a8d229` (1.526 B), igual ao precedente de 2026-09-27.
- **PASS.**

## 3. Statements e saídas

| Statement | md5 SQL | bytes | linhas plano | md5 body | md5 resposta original | bytes resposta |
|---|---|---:|---:|---|---|---:|
| P9A-B | `02407ab479bdb7315030c1c09c514c83` | 7463 | 46 | `2f53066d2a50062680aaf2d7071c0a7b` | `76e9067e803cdce6cbdd1a07915f971c` | 3201 |
| P9A-M | `2c62627b66fb28e5e5c9a6b9157bf470` | 6675 | 11 | `43702c0fb4240268687b2c47da1c5c9c` | `7d855e28456e0d165ea17f3fe2664a25` | 1214 |
| P9A-5X | `008903402e7ec20785d6066f16dbea0d` | 17143 | 789 | `f2ffdd45c654b347b1af2bdc68ee564c` | `6b6bd17bccd96ced3904946622ac969d` | 51058 |
| P9A-D1X | `d22875b4e73e523b34aa30f748597a05` | 31153 | 430 | `1b4bcef40c5559bd5308fa6bf1fbd16b` | `c67f34a5c46ca96641bcddef91b73499` | 28622 |

- L3: resposta original md5 `65d254121c7ff48970c8ef7f49703f19` (4.176 B); body md5 `59d6a3d8fbbecccd2608fb454a68573e`.
- *body* = array JSON `[{"QUERY PLAN":…},…]` com LF final; *resposta original* = invólucro integral do canal. Todos os valores conferem com o `MANIFEST.md5` preservado.
- A resposta do S4 (51.058 caracteres) excedeu o limite de exibição da ferramenta e foi gravada integralmente em arquivo pelo cliente; não houve truncamento no canal (mesma situação do S3 de 2026-09-27).
- Os 4 bodies são JSON válido, re-serializáveis byte a byte, com árvore completa do nó raiz ao último nó.

## 4. Integridade

Somente `EXPLAIN (COSTS OFF)`; zero ANALYZE; zero escrita; zero DDL; zero alteração de sessão (`SET`, `TEMP`, `PREPARE`); zero retry; nenhuma chamada além das 5 autorizadas (sem E00, E99 ou P9A-00/03/04/05); nenhum nó `ModifyTable`/`LockRows`, nenhuma linha de JIT ou de tempo nos planos; working tree limpa durante e após a execução.

## 5. Planos (resumo de `STRUCTURE.md`)

| Statement | Raiz | CTEs / InitPlans / SubPlans | Acessos |
|---|---|---|---|
| P9A-B | `Aggregate` | 2 / 5 / 0 | Seq Scan em `catalog_variant_import_row`, `catalog_variant_import_job`, `card` (Hash Join); Index Scan `uq_asset_source_code`, `uq_game_code`; `Memoize` + Function Scan `resolve_variant_mapping_scope`; Function Scan `resolve_variant_row_axes` |
| P9A-M | `Aggregate` | 0 / 0 / 0 | Sort → Append; Hash Join de Seq Scan `catalog_variant_import_row` × `catalog_variant_import_job`; Values Scan |
| P9A-5X | `Result` | 14 / 84 / 34 | 40 Seq Scans (27 em `card_variant_type`); Index Scan `uq_card_set_expansion_code` (12×), `ix_card_variant_variant_type_id`, `card_pkey`, `uq_*_code`; Index Only Scan `ix_catalog_variant_import_row_matched_variant`, `ix_pricing_source_card_identity_card_variant_type_id`; as 2 funções como Function Scan |
| P9A-D1X | `Nested Loop` | 33 / 32 / 6 | `d1_cv` MATERIALIZED (Hash Join `card_variant` × `card_variant_type` × `card` × `card_set`); 10 `HashSetOp Except` (vetores × baselines congelados); Hash Anti/Semi Join (contrato × derivado); mesmos índices de apoio do 5X |

**PERFORMANCE FINDING — NON-BLOCKING FOR P9(a):** varreduras sequenciais completas de `card_variant`, `card`, `card_set` e `catalog_variant_import_row` em vários CTEs, e as funções SECURITY DEFINER visíveis apenas como Function Scan (não inlined pelo EXPLAIN). P9(a) exige registrar a forma do plano; não pré-fixa índice, tipo de join nem ausência de Seq Scan, e não mede tempo.

## 6. Auditoria independente

**AUDIT PASS** — L3 PASS; P9A-B, P9A-M, P9A-5X e P9A-D1X VALID / REGISTERED.

Conclusão: **`P9(a) CLOSED`**. Com P9(b)′ v7.2 já CLOSED, **A2′ CLOSED** (auditoria estática + P9(a) + P9(b)′).

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-10-03).** Registro da execução LIVE `BATCH12-PHASE6-P9A-HEAVY-LIVE-EXECUTION-01` (5 chamadas) e do fechamento por auditoria independente; evidência preservada em `evidence/P9A-HEAVY-LIVE-2026-10-03/`. |
