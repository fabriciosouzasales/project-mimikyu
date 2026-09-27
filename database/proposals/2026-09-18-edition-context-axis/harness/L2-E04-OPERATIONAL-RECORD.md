# L2 · E04P + E04 — Registro operacional mínimo (Seções 2-BIS e 2-TER)

| Campo | Valor |
|---|---|
| **Documento** | Registro operacional mínimo do lote L2 para uma FUTURA execução LIVE |
| **Versão** | 1.0 |
| **Status** | IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no PostgreSQL. Aguarda auditoria independente e mandato próprio de execução. |
| **Mandato** | BATCH12-2830-P5-L2-FUNCTIONAL-IMPLEMENTATION-01 (baseline Git `36a3bc06`) |
| **Contrato** | `2830_validate_edition_context_foundation.sql` v7.0, blob `b4647dcb…`, l. 479–515 (inalterado) |

## 1. Artefatos (blobs Git locais)

| Artefato | Blob | Linhas |
|---|---|---|
| `2830H_E04P_precheck_section2b2t.sql` | `5cb4b893b2e7f611ea613919d21b3bd35f90bab8` | 264 |
| `2830H_E04_section2b_2t_mapping.sql` | `5b2a8b6f06a1edf25012d06003dedd7580fd4c03` | 1928 |
| `tools/static_check.py` (baseline `79c4fd42…` + perfil E04 aditivo) | `008c978868d7a747d5ef1a15dedcf315e8a59dce` | 1599 |

Reutilizados sem alteração: E00 `a4dd8438…`, E99 `49a71ecb…` (conferidos pelo próprio `static_check.py`).

## 2. Sequência de uma futura execução (uma chamada por passo, nunca em lote)

| Passo | Envelope | Aceite | Se falhar |
|---|---|---|---|
| S0 | preflight Git: HEAD e blobs da §1 | blobs idênticos | STOP |
| S1 | E00 | `gate_pass = true` | STOP |
| S2 | E04P | `gate_pass = true` (15 gates) | STOP — em especial `g_rc_identity = false` significa que a 2211/2176 do LIVE diverge do repositório: adjudicar, nunca ajustar o pino |
| S3 | E04 | mensagem `H2830_ROLLBACK_PASS: envelope=E04_SECAO2B_2T_MAPPING pass=14/14 … universo_2b5=N universo_2b6=N` com N > 0 (esperado 122) | `H2830_FAIL` ou retorno `[]` = STOP, sem retry |
| S4 | E99 | `gate_pass = true` (sem resíduo, `lock_timeout` default) | STOP |

## 3. Matriz caso → operação → resultado esperado → rollback

| Caso | Classe | Operação | Resultado esperado | Rollback |
|---|---|---|---|---|
| 2B.1 | FXd | T1, T2; M1 GLOBAL; N:N T2, T1; IMMEDIATE; sonda | selo = ARRAY ordenado de {T1, T2} | H283C do caso |
| 2B.2 | FXd | M1 sem N:N + IMMEDIATE no mesmo sub-bloco (`v_step`); sonda | P0001 `EDITION_CONTEXT_EXTERNAL_MAPPING_EMPTY_COMPOSITION:` no passo IMMEDIATE; M1 desfeito | sub-bloco + H283C |
| 2B.3 | FX | M1 em montagem (N:N T1); UPDATE selo = [T2] | P0001 `EDITION_CONTEXT_MAPPING_SIGNATURE_MISMATCH:`; selo continua NULL | evento pendente descartado pelo H283C |
| 2B.4 | FXd | M1 selado [T1]; sonda; UPDATE selo = [T2] | P0001 `EDITION_CONTEXT_MAPPING_SIGNATURE_IMMUTABLE:`; selo continua [T1] | H283C |
| 2B.5 | RO | contagem de selo NULL no universo | 0 de N, N > 0 | nenhum write |
| 2B.6 | RO | selo vs ARRAY(N:N ORDER BY trait_id) | 0 divergências de N, N = universo 2B.5 | nenhum write |
| 2T.1 | FXd | M1 selado → `is_active = false` (ROW_COUNT 1) → M2 [T2] → IMMEDIATE; 2 sondas | IMMEDIATE sem erro; M2 selado [T2] | H283C |
| 2T.2 | FXd | cenário 2T.1 reconstruído | 2 linhas no token, 1 ativa = M2, M1 inativa | H283C |
| 2T.3 | FXd | cenário 2T.1 reconstruído | M1 selo [T1], N:N = {T1} | H283C |
| 2T.4 | FX | 2 ativos GLOBAL no mesmo token | 23505 `uq_cecem_active_global` em `card_edition_context_external_mapping`; 1 ativo | H283C |
| 2T.5 | FX | 2 ativos SCOPED (mesmo Set) | 23505 `uq_cecem_active_scoped`; 1 ativo | H283C |
| 2T.6 | FXd+RC | GLOBAL [T1] + SCOPED S1 [T2]; 2211 com S1 e com S2 | S1 → traits [T2], residual NULL; S2 → traits [T1]; ambos `NEEDS_REVIEW_NO_EC_PROFILE` e `RESOLVED_NO_PRINTING` | H283C |
| 2T.7 | FXd+RC | SCOPED S1 selado e aposentado; 2211 com S1 | `NEEDS_REVIEW_INACTIVE_EC_MAPPING`, traits `{}`, residual = token | H283C |
| 2T.8 | FXd+RC | SCOPED S1 ativo; 2211 com S2 e controle com S1 | S2 → `RESOLVED_NO_EDITION_CONTEXT`, residual = token; S1 → traits [T1] | H283C |

Toda execução termina em exceção (H283P ou H283F): rollback estrutural integral.

## 4. Superfície de escrita (DP-5 = B, tier R1)

| Tabela | INSERT | UPDATE | DELETE |
|---|---|---|---|
| `card_edition_context_trait` | 16 (fixtures, `code`/`name` com marcador) | 0 | 0 |
| `card_edition_context_external_mapping` | 18 de fixture + 12 de sonda (token com marcador; Set NULL ou declarado com marcador) | 6, só `WHERE id = v_m… AND normalized_token = v_tok` (2 de selo, 4 de aposentadoria com ROW_COUNT = 1) | 0 |
| `card_edition_context_external_mapping_trait` | 14 (mapping de fixture × trait de fixture) | 0 | 0 |

Sem LOOP/FOR/WHILE: a superfície é estática e finita. Nenhuma outra tabela é escrita; profile e N:N de profile não são tocados. Leitura via RC: `internal.resolve_variant_row_axes` → `compute_variant_residual_signature` → `normalize_external_catalog_value` (todas pinadas no E04P).

## 5. Limitações declaradas

- **Sem compilação nem execução PostgreSQL local**: o sandbox não tem PostgreSQL nem acesso à rede para instalar um parser (`pglast`). As provas são estáticas (perfil E04/E04P no `static_check.py`) e NÃO substituem compilação nem comportamento real; erros de sintaxe PL/pgSQL, deparse de `pg_get_function_result` ou de predicado de índice só aparecem no primeiro E04P/E04 real e resultam em STOP (fail-closed), nunca em PASS indevido.
- **Identidade LIVE da 2211/2176 não demonstrada** por evidência existente: o E04P pina o corpo do repositório (md5 LF) e bloqueia se divergir. O corpo da 2211 é idêntico no commit executado no Batch 5 (`a3c1666c`) e no HEAD — evidência de linhagem do repositório, não do LIVE.
- Premissas de semântica PostgreSQL herdadas do E03 aprovado no LIVE: descarte de eventos diferidos no rollback de subtransação; `SET CONSTRAINTS` afetando todos os nomes correspondentes; variáveis PL/pgSQL não revertidas por rollback de sub-bloco.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27).** Registro operacional mínimo do lote L2 (E04P + E04), produzido junto da implementação local em BATCH12-2830-P5-L2-FUNCTIONAL-IMPLEMENTATION-01. |
