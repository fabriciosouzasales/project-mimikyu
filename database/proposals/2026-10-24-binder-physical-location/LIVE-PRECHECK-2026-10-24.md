# BINDER-PHYSICAL-LOCATION — evidência do precheck LIVE (LIVE-PRECHECK-01)

| | |
|---|---|
| Data/hora | 2026-10-24 11:30 UTC |
| Projeto | `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`), via MCP `execute_sql` |
| Proteção | cada chamada: `begin transaction read only; set local statement_timeout = '30s'`; confirmado `transaction_read_only = on`, `statement_timeout = 30s` |
| Scripts | `LIVE_00_precheck_readonly.sql` (md5 `527d5053bd7b30c277b47fd5fa07f6ab`) executado; `LIVE_01_…` (md5 `4cf277a212ac85faac3b79b52c59d32e`) **não executado** (STOP) |
| Escritas | nenhuma |
| Veredito | 1ª execução: **STOP** (2 layouts, depois explicado). Reexecução após confirmação: **PASS** — LIVE_00 11/11, LIVE_01 15/15 (ver final do documento) |

## LIVE_00 — consulta 1 (checagens)

Todas verdadeiras: p01_ledger_tip_5246, p02_none_applied, p03_cols_absent, p04_new_funcs_absent, p05_old_contracts_present, p06_plan_v1, p07_triggers_present, p08_owner_default_binder, p09_all_positions_in_binder_location, p10_no_locked_slots, p11_no_active_queries = **true**.

Únicos acréscimos ao texto do script: duas colunas de guarda somente leitura (`current_setting('transaction_read_only')`, `current_setting('statement_timeout')`).

## LIVE_00 — consulta 2 (fatos de referência)

| item | obtido | esperado (fatos 2026-10-24) |
|---|---|---|
| layouts | **2** | 1 |
| guests | 1 | 1 |
| pages | 25 | — |
| slots | 232 | — |
| assignments | 155 | 155 |
| reservations | 158 | 158 |
| locked | 0 | 0 |
| slot_images | 0 | — |
| regions | 1 | — |
| region_images | 1 | — |
| allocations | 211 | — |
| f001_cards | 182 | 182 |
| assignments_md5 | `63e36528f57559f281230abb90fab5fe` | (referência) |
| layout_md5 | `b0906e79695b8a049b9120d99d4f7079` | (referência) |
| allocations_md5 | `a180e923764e3b5a9cb225ee68f873c0` | (referência) |

## Motivo do STOP

O plano exige 1 fichário digital; o LIVE tem **2**. As checagens booleanas passam (inclusive a regra de local padrão BINDER da proprietária e todas as posições no local do fichário), mas o segundo fichário não estava no levantamento de referência e não foi explicado. Não foi investigado, porque a autorização cobre apenas os dois scripts. O LIVE_01 não foi executado.

## Identificação dos fichários (LIVE-LAYOUT-IDENTIFICATION-01, leitura em transação READ ONLY, timeout 30 s)

| | Fichário 1 | Fichário 2 |
|---|---|---|
| layout | `0d550088-b5de-46d0-bc31-3cde93d3e6b7` | `bd2c0834-1310-4239-9aed-012df74ae97b` |
| proprietária | Celebração de 30 Anos (ACTIVE) | Minha Pokédex (ACTIVE) |
| local padrão | F001 - Fichário Coleção ME5.5 (`4f3a9ec2-…5d2d`), BINDER, mesmo dono | F002 - Fichário Pokédex (`0cc2006b-fca0-4dd7-b576-2b818d10bc32`), BINDER, mesmo dono |
| criado em | 2026-10-23 12:46 UTC | 2026-10-24 03:06 UTC (depois do levantamento de referência) |
| grade | 3×3 | 4×4 |
| páginas / bolsos | 24 / 216 | 1 / 16 |
| posições / reservas | 155 / 158 | 0 / 0 |
| convidadas | 1 (Coleção Clássica, padrão F001) | 0 |
| fichários no mesmo local | 1 | 1 |
| posições fora do local | 0 | 0 |
| exemplares guardados no local | 182 | 0 |

Somas = LIVE_00 (25 páginas, 232 bolsos, 155 posições, 158 reservas). Locais distintos; ambos atendem os prechecks da 5247 (local BINDER do mesmo dono, sem colisão); nenhum vínculo inconsistente. **Confirmado por Fabrício (2026-10-24): "Minha Pokédex" foi criado de propósito.** Divergência encerrada; fato esperado passa a 2 fichários. Próximo passo (requer autorização): reexecutar LIVE_00 e então LIVE_01.

## Reexecução autorizada (2026-10-24, após confirmação do Fichário 2) — READ ONLY, timeout 30 s

**LIVE_00 consulta 1:** p01–p11 = true (11/11).
**LIVE_00 consulta 2:** layouts 2 · guests 1 · pages 25 · slots 232 · assignments 155 · reservations 158 · locked 0 · slot_images 0 · regions 1 · region_images 1 · allocations 211 · f001_cards 182 · `assignments_md5` 63e36528f57559f281230abb90fab5fe · `layout_md5` b0906e79695b8a049b9120d99d4f7079 · `allocations_md5` a180e923764e3b5a9cb225ee68f873c0 — idêntico à 1ª execução e aos fatos esperados atualizados.
**LIVE_01:** 15/15 funções presentes com corpo idêntico à canônica (`body_matches_canonical` = true em todas); `search_path` vazio em todas; SECURITY DEFINER em 13 (as 2 auxiliares internas `collection_binder_plan` e `collection_binder_detach_snapshot` são INVOKER, como no canônico). Resumo: **`l01_all_canonical = true`, `l01_functions_checked = 15`**.

**Veredito do precheck: PASS.** Nenhuma escrita. Fingerprints acima são a referência para LIVE_50/90.
