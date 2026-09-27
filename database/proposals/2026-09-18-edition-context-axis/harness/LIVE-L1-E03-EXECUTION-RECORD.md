# 2830H — Lote L1: registro de execução LIVE do E03 (Seção 2, 13 casos)

| Campo | Valor |
|---|---|
| **Natureza** | Registro da execução controlada do E03, conforme `L1-E03-LIVE-EXECUTION-PLAN.md` (blob `b3eba41c…`) e `L1-E03-LIVE-EXECUTION-READINESS.md` v1.2 (blob `9080f2ad…`). O E03 implementa casos da 2830 v7.0 (reconhecimento contratual = SIM): um CONFORME com postcheck ÍNTEGRO permite **propor** PASS, sujeito à auditoria independente. |
| **Mandato** | `BATCH12-2830-P5-L1-E03-LIVE-EXECUTION-01`. Baseline HEAD `3a089e08c17b8c790d991b584dd9301c69739117`. Decisões DP-1 = A, DP-4 = A, DP-5 = A, `MAX_L3_D = 2`, reconhecimento contratual = SIM. |
| **Autorização** | Expressa e limitada, de Fabrício, no mandato: só as escritas transitórias do E03 blob `ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e` (DP-5 = A), com rollback obrigatório e verificação posterior, numa única execução. Não contempla L2 nem outro lote, alteração de SQL, migration, limpeza, retry ou alteração de configuração. **Esgotada nesta execução.** |
| **Resultado** | **CONFORME.** `H283P`, `pass=13/13`, casos `2.1,2.2,2.3,2.4,2.5,2.7,2.8,2.9,2.10,2.11,2.12,2.13,2.14`, marcador `H2830_DB0A64F6039349658EA013D218D2C452`, contexto `line 1703`, `elapsed_ms=202`. Postcheck **ÍNTEGRO** (E99 9/9, `d_diff = []`, `d_canon_diff = []`; L3 final limpa). Fluxo normal, sem L3-D. |
| **Efeito contratual** | **v1.1 (vigente):** `2.1–2.5, 2.7–2.14 PASS` **reconhecidos** após a auditoria independente; cobertura LIVE **30/135** (§8). **v1.0 (histórico):** proposta sujeita à auditoria; cobertura declarada 17/135 até o parecer. |
| **Estado** | **v1.1 — CLOSED** (`BATCH12-2830-P5-ENGINEERING-DECISIONS-01`): auditoria independente **PASS**; registro publicado em `e6af59c1`; 13 PASS contratuais reconhecidos; cobertura LIVE **30/135** (§8). **v1.0 (histórico):** "para auditoria independente; registro não publicado". **FREEZE ATIVO.** |
| **Papéis** | **Claude**: executor. **ChatGPT**: auditor independente. **Fabrício**: autorizações, commit e push. |

---

## 1. S0 — verificação local (antes de qualquer conexão)

| Item | Resultado |
|---|---|
| HEAD | `3a089e08c17b8c790d991b584dd9301c69739117` = baseline do mandato ("docs: finalize E03 live execution plan and Batch 12 closeout path"); o commit contém só o plano, a linha do README e a linha do `docs/log.md` |
| Árvore e índice | limpos: `git status --porcelain --untracked-files=all` 0 linhas; `git diff --cached --name-only` 0 linhas |
| Plano | `git ls-files -s` → **`100644 b3eba41c2e1fb32efe1f3960762cfe1c23f9dbb1`** (modo e blob esperados); md5 `132b9922ef4be8805fbf12ed604248f6`, 33.083 B |
| **E03** | blob **`ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`** = HEAD = blob autorizado · md5 `e0aeb7e3dc4143d171cb4364d99069d8` · sha256 `e2949dc65a8215800af05bac209b5745287a755ad9e6a488e2ed00d08ce5215e` · 93.188 B |
| E00 | blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` = HEAD · md5 `45b6c35cca849ffbf49d22ec18e8283c` · 53.803 B |
| E03P | blob `0fc2d83dff599fc6cc26e35399ebc519a5a51d0f` = HEAD · md5 `10457d87d4c25c93ab04d0fadf43dddc` · 13.335 B |
| E99 (base) | blob `49a71ecb4525697858110ee71a3f61f5eee74a34` = HEAD · md5 `f0b91183a8649b990b080637dd56e74b` · 12.289 B |
| `tools/static_check.py` | blob `79c4fd42…` = HEAD; `TOTAL 444 PASS 444 FAIL 0`, `E03-PERFIL TOTAL 88 PASS 88 FAIL 0`, `E03-VERIFICADOR-NEG TOTAL 79 PASS 79 FAIL 0`, `E03-VERIFICADOR-POS TOTAL 6 PASS 6 FAIL 0` |
| Readiness do E03 v1.2 / readiness v1.3 | `9080f2ad…` / `76cca828…` = HEAD |
| Protocolo / roteiro / 2830 | `abe806d6…` / `9f454a96…` / `b4647dcb…` (md5 `7d816d18…`) = HEAD |
| L1 / L3 | recalculados dos blocos do roteiro: md5 `0836c36a8d3749b1e7718223e064caf9` (2.458 B) e `b7bc3700aeef278f6a79bd30e6a8d229` (1.526 B) |
| Canal | Supabase MCP `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`; uma chamada por statement |

## 2. Sequência e cronologia

| Passo | Chamada | Horário (banco) | SQLSTATE | Resultado |
|---|---|---|---|---|
| S1 | L1 (`0836c36a…`) | `checked_at` 20:42:33.344775Z · pid 3547914 | nenhum | **conforme**: `transaction_read_only = off`, `default_transaction_read_only = off`, `in_recovery = false`, **`lock_timeout = '0'`**, **`statement_timeout = '2min'`**, PG `170006`, `standard_conforming_strings = on`, donos das 5 tabelas EC = `postgres` = `current_user`, visibilidade por `reads_all_stats = true` (e `visible_foreign_sessions = 3`) |
| S2 | L3 (`b7bc3700…`) | `checked_at` 20:42:57.408256Z | nenhum | **conforme**: `locks_on_scope = []`; 12 `client backend`, todas `idle`, sem `xact_start` e sem `backend_xid` |
| S3 | E00 (`45b6c35c…`), novo, desta rodada | `checked_at` 20:46:04.514161Z · pid 3548582 | nenhum | **24/24 gates `true`, `gate_pass = true`**; `d_canon_diff = []`; `d_baseline_md5 = 5c329d5e38a7e369cc100ab08953e1a7`; `db_role_setting_rows = 9`; `lock_timeout = '0'`, `statement_timeout = '2min'` |
| S4 | E03P (`10457d87…`) | `checked_at` 20:47:38.127993Z · pid 3548611 | nenhum | **11/11 gates `true`, `gate_pass = true`** |
| S5 | **E03** (`e0aeb7e3…`), integral, **uma** submissão | entre S4 e S6; o canal não devolve horário para erro | **`H283P`** | resposta definida e conforme (§3) |
| S6 | E99 com os 3 valores do S3 (`00233aa60c571994f39df2df3faf05ea`) | `checked_at` 20:54:28.998387Z · pid 3549334 | nenhum | **9/9 gates `true`, `gate_pass = true`**, `d_diff = []`, `d_canon_diff = []` |
| S7 | L3 final (`b7bc3700…`) | `checked_at` 20:54:32.695074Z | nenhum | **limpa**: `locks_on_scope = []`; 12 `client backend`, todas `idle`, sem `xact_start` e sem `backend_xid`; pids 3547914, 3548582, 3548611 e 3549334 ausentes |

- Exatamente **7 chamadas** `execute_sql`, nesta ordem, sem repetição e sem nenhuma outra entre elas. **Nenhuma L3-D**: a resposta do S5 foi definida.
- Ordem temporal conferida localmente pelos horários do banco: `checked_at(L1) < checked_at(L3) < checked_at(E00) < checked_at(E03P) < S5 < checked_at(E99) < checked_at(L3 final)`.
- Intervalo E00 → E99: 504,5 s. Janela L1 → L3 final: 719,4 s. Entre as chamadas houve só conferência local, salvo o desvio D-1 (§6).
- O E00 é novo desta rodada (`backend_pid` 3548582 e `checked_at` próprios). O `d_baseline` é igual ao das rodadas anteriores: o estado continua estável sob FREEZE.

## 3. Resposta do E03 (S5) — literal

```
ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2.1,2.2,2.3,2.4,2.5,2.7,2.8,2.9,2.10,2.11,2.12,2.13,2.14 marker=H2830_DB0A64F6039349658EA013D218D2C452 elapsed_ms=202
CONTEXT:  PL/pgSQL function inline_code_block line 1703 at RAISE
```

Resposta integral do canal (`HttpException`), preservada sem edição:

```
{"error":{"name":"HttpException","message":"Failed to run sql query: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2.1,2.2,2.3,2.4,2.5,2.7,2.8,2.9,2.10,2.11,2.12,2.13,2.14 marker=H2830_DB0A64F6039349658EA013D218D2C452 elapsed_ms=202\nCONTEXT:  PL/pgSQL function inline_code_block line 1703 at RAISE\n"}}
```

Conferência por script local sobre o texto acima (plano §5):

| # | Controle | Observado | Resultado |
|---|---|---|---|
| R-1 | SQLSTATE `H283P` | `H283P` | conforme |
| R-2 | mensagem, não truncada, casa com a regex publicada | casa | conforme |
| R-3 | `pass=13/13` | `pass=13/13` | conforme |
| R-4 | os 13 casos na ordem, `2.6` ausente | `2.1,2.2,2.3,2.4,2.5,2.7,2.8,2.9,2.10,2.11,2.12,2.13,2.14` | conforme |
| R-5 | marcador `H2830_` + 32 hexadecimais maiúsculos | `H2830_DB0A64F6039349658EA013D218D2C452` | conforme |
| R-6 | contexto `PL/pgSQL function inline_code_block line 1703 at RAISE` (RAISE terminal l. 1767, `DO` l. 65) | idêntico | conforme |
| R-7 | `elapsed_ms ≤ 60000` (DP-1 = A) | **202** | conforme |

`H283P` sozinho não é aceite: a classificação depende do postcheck (§4–§5). Nenhuma resposta `H283F`, `55P03`, `57014`, outro SQLSTATE, `[]` ou ambígua ocorreu.

## 4. Postcheck — E00 × E99 (S3 × S6)

### 4.1 Preparação do E99

- **Origem dos valores:** saída do S3 **desta** rodada: `d_baseline` na forma literal devolvida pelo canal (787 B, sem apóstrofo), `d_baseline_md5 = 5c329d5e38a7e369cc100ab08953e1a7`, `db_role_setting_rows = 9`.
- **Controles antes de submeter:** `md5(jsonb::text)` do JSON capturado, recalculado localmente (chaves por comprimento e bytes, separadores `", "`/`": "`), = `5c329d5e…`; cada literal substituído exatamente uma vez, por script; o texto difere do blob base só nas linhas 56–58.
- **Texto submetido:** md5 `00233aa60c571994f39df2df3faf05ea`, 13.044 B, integral no Apêndice A. É byte a byte igual ao E99 do E03T e das Etapas 2 e 3, porque os três valores capturados agora são os mesmos. A vinculação é documental (§2): os valores vêm do S3 desta rodada.

### 4.2 Resultado do E99

| Gate | Valor |
|---|---|
| `g_captured_present` | true |
| `g_captured_integrity` | true |
| `g_keys_identical` | true |
| `g_baseline_equal` | true |
| `g_freeze_canonical_equal` | true |
| `g_marker_absent` | true |
| `g_no_open_txn_others` | true |
| `g_lock_timeout_default` | true (`lock_timeout = '0'`) |
| `g_role_setting_unchanged` | true (`db_role_setting_rows = 9` = E00) |
| `gate_pass` | **true** |
| `d_diff` / `d_canon_diff` | `[]` / `[]` |
| `d_baseline_now_md5` | `5c329d5e38a7e369cc100ab08953e1a7` = `d_baseline_md5` do E00 |

### 4.3 Comparação chave a chave (seleção; as 22 chaves são iguais)

| Chave | E00 (S3) | E99 (S6) |
|---|---|---|
| `trait` | 115 | 115 |
| `profile` | 144 | 144 |
| `profile_trait` | 196 | 196 |
| `mapping` / `mapping_trait` | 122 / 122 | 122 / 122 |
| `marker_trait` / `marker_profile` / `marker_mapping` | 0 / 0 / 0 | 0 / 0 / 0 |
| `card_variant` / `card_variant_ec_nonnull` | 24.893 / 0 | 24.893 / 0 |
| `action_log` | 1.352 | 1.352 |
| `staging_rows` | 26.127 | 26.127 |
| `jobs` / `jobs_in_flight` | 145 / 0 | 145 / 0 |

### 4.4 Classificação do postcheck (readiness v1.3 §4.4)

E99 completo com todos os critérios **e** L3 final completa, sem lock no escopo, sem sessão ativa ou em transação e sem pid desta rodada ⇒ **ÍNTEGRO**. Resíduo zero afirmado **só** nesta base.

**Prova de rollback — três fontes independentes:**

| Fonte | Evidência |
|---|---|
| 1. Mensagem terminal | `H283P` com o marcador desta execução; o `DO` terminou em exceção; os 13 casos terminaram em `H283C` dentro de subtransação (13/13 contados no gate `v_done = c_expected`); 11 sondas `H283S` descartadas (gate `v_qn = 11`) |
| 2. E99 | 22 chaves do `d_baseline` iguais ao E00; `d_diff = []`; marcador ausente em `trait.code`, `profile.code` e `mapping.normalized_token`; `d_canon_diff = []` |
| 3. L3 final | `locks_on_scope = []`; nenhuma sessão remanescente ativa ou em transação; pids desta rodada ausentes |

**DP-4 = A, provas separadas (readiness do E03 §5.6):**
- asserção interna: a execução passou do preflight; sem `H283F caso=PREFLIGHT lock_timeout`, então `current_setting('lock_timeout') = '5s'` dentro da transação do envelope;
- `H283P`: o envelope chegou ao fim e terminou em exceção, com rollback;
- E99: `g_lock_timeout_default` e `g_role_setting_unchanged` verdadeiros (nenhuma configuração persistente);
- L3 final: nenhum lock nem sessão remanescente;
- limite: o E99 roda noutra conexão; a não persistência na conexão do envelope vem da semântica transacional e da prova estática E03-20.

## 5. Classificação final e fundamentação

**CONFORME**, pela regra da readiness v1.3 §4.5 aplicada ao E03 (INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME): R-1 a R-7 conformes; postcheck ÍNTEGRO; `elapsed_ms = 202 ≤ 60000`; ordem temporal registrada. Nenhum evento da tabela STOP/CONTINUE foi acionado. O desvio D-1 (§6) é de procedimento e não altera nenhum critério.

**O que este CONFORME demonstra (R, observado no LIVE 17.6):**
- os 13 casos contratuais da Seção 2 (2.1–2.5, 2.7–2.14) passaram com as asserções do envelope, incluindo os 9 negativos (SQLSTATE + token exato, ou `23505` + constraint + tabela) e as 11 sondas de modo;
- o caso 2.7 (IMMEDIATE depois de sonda, `23505` em `uq_cecp_game_signature`, com `CONSTRAINT_NAME` e `TABLE_NAME` conferidos) passou;
- `SET LOCAL lock_timeout = '5s'` dentro do `DO` foi aplicado e não vazou;
- o rollback deixou o estado igual ao baseline.

**O que não demonstra:**
- **limite L-1**: a ausência de contaminação observável não prova a remoção direta do evento diferido da fila;
- os ramos PL/pgSQL de falha não percorridos (só verificação estática);
- concorrência com escritor real;
- tempo representativo de outros lotes.

**Efeito contratual (proposto, não declarado):** `2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14 PASS`, **sujeito à auditoria independente do ChatGPT**. Até o parecer, a cobertura LIVE continua **17/135**; 30/135 só depois dele. `2.6` permanece reservado ao lote L5.

## 6. Incidentes, desvios e limitações

- **Incidentes:** nenhum. **STOP:** não houve.
- **Desvio D-1 (procedimento, sem efeito sobre dados ou critérios):** as chamadas S6 (E99) e S7 (L3 final) foram despachadas no mesmo lote de ferramentas, e não uma após a conferência local da outra. Os horários do banco provam a ordem exigida (`checked_at(E99) 20:54:28.998Z < checked_at(L3 final) 20:54:32.695Z`), e o plano exige o S7 depois do S6 em qualquer resultado do E99, então nenhuma decisão foi antecipada. Ainda assim, contraria a instrução do mandato de não antecipar a próxima chamada antes de verificar a anterior. Registrado para a auditoria.
- **Relógio local ≠ relógio do banco:** o `date` do sandbox marcava 20:43:48Z no S0, e a L1 registrou 20:42:33Z. A ordem S0 → S1 vem da sequência das ações; a cronologia do §2 usa só o horário do banco.
- **Canal:**
  - o MCP não devolve o md5 do texto efetivamente recebido; a identidade dos textos vem do S0 e da submissão integral, sem edição. O contexto `line 1703`, a lista de 13 casos e o `pass=13/13` são coerentes com o blob `ef24a3be…`;
  - a resposta de erro do E03 chega como `HttpException`, com o SQLSTATE no texto, sem horário do servidor e sem `backend_pid`;
  - `elapsed_ms` é medido dentro do bloco (`clock_timestamp()`), sem a latência do canal;
  - as conexões do canal são por chamada; a ausência do backend do E03 é inferida da L3 final.
- **Resíduo não-transacional declarado, aceito e não verificado:** contadores `pg_stat_*`, tuplas mortas até o autovacuum, WAL, XIDs de subtransação e linhas de log com o marcador. Nenhum é dado de negócio. Sequences: nenhuma (E00 `g_no_sequences_touched_now`, E03P `g_nn_no_sequence`).
- **Texto histórico nos SQLs (blobs preservados):** o cabeçalho do E03 ainda diz "NÃO EXECUTADO". A execução está neste registro.

## 7. Estado do repositório e governança

- Nenhum envelope, SQL, protocolo, migration ou configuração foi alterado. Nenhum `SET` fora do preâmbulo P8 do próprio blob, nenhum `pg_terminate_backend`, limpeza ou retry.
- Não executados: L2, L3-D, L4, E01, E02, E03T, qualquer outro lote.
- Sem `git add`, commit ou push. Este registro, a linha do README e a linha do `docs/log.md` ficam para auditoria e publicação por Fabrício.
- A autorização de escrita transitória do E03 (DP-5 = A) limitou-se a esta execução e está esgotada. **FREEZE ATIVO.**

## 8. Fechamento (v1.1) — parecer independente e cobertura

- **Parecer:** auditoria técnica independente (ChatGPT) **PASS** sobre este registro, comunicada por Fabrício nos mandatos `BATCH12-2830-P5-TRANSVERSAL-DECISIONS-AND-D1-01` ("E03 CLOSED, auditado e publicado; cobertura contratual reconhecida: 30/135") e `BATCH12-2830-P5-ENGINEERING-DECISIONS-01`, e refletida no commit `e6af59c18e53b656a54410e80a8b070c4e292a89` ("close out audited E03 live execution with 13 contractual passes"). O texto integral do parecer não está no repositório; fica registrado o resultado.
- **Efeito contratual vigente:** `2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14 PASS`. Cobertura LIVE **30/135** = 1.1–1.12 (Etapa 3) + D1–D5 (Etapa 2) + os 13 acima. `2.6` continua reservado ao lote L5.
- **Desvio D-1 (§6):** permanece registrado como estava; o registro auditado já o continha. Nenhuma ressalva adicional consta do repositório.
- **Texto histórico preservado:** §5 ("efeito contratual proposto, não declarado"), §6 e §7 ("17/135 até o parecer") descrevem o estado da v1.0, antes do parecer, e não foram alterados.
- **Sem reabertura:** nenhum envelope, texto submetido ou resultado da execução foi alterado. A autorização DP-5 do E03 continua esgotada. **FREEZE ATIVO.**

---

## Apêndice A — E99, texto exato submetido (md5 `00233aa60c571994f39df2df3faf05ea`, 13.044 B)

Difere do blob `49a71ecb…` só nas linhas 56–58 (conferido por script: mesma contagem de linhas). Texto integral, inserido por script a partir do arquivo submetido (idêntico ao Apêndice A do registro do E03T):

```sql
-- ============================================================================
-- 2830H · E99 — POSTCHECK: COMPARAÇÃO INTEGRAL COM O E00 DA MESMA RODADA
-- ============================================================================
-- Status ........ PREPARADO — NÃO EXECUTADO. Somente SELECT, um statement.
-- Uso ........... statement SEPARADO, logo após cada envelope.
--
-- ANTES DE RODAR, o operador substitui EXATAMENTE TRÊS marcadores, copiando
-- da saída registrada do E00 DA MESMA RODADA (colar, nunca redigitar):
--   __E00_D_BASELINE__         ← o valor integral de d_baseline (JSON)
--   __E00_D_BASELINE_MD5__     ← o valor de d_baseline_md5
--   __E00_ROLE_SETTING_ROWS__  ← o valor de d_session.db_role_setting_rows
-- Marcador não substituído, JSON truncado ou alterado ⇒ gate falso.
--
-- O QUE O MD5 PROVA — E O QUE NÃO PROVA:
--   md5(capturado) = md5 declarado prova apenas FIDELIDADE DA CÓPIA: o JSON
--   colado é byte a byte o que algum E00 produziu junto com aquele md5. NÃO
--   prova de QUAL rodada ele veio: um par (d_baseline, d_baseline_md5)
--   copiado inteiro de outra rodada passaria nesse gate. A origem da rodada
--   é garantida pela VINCULAÇÃO DOCUMENTAL abaixo, não por este SQL.
--
-- VINCULAÇÃO DOCUMENTAL DA EVIDÊNCIA  E00 → envelope → E99
--   Uma rodada só é aceita se o registro de execução (README, seção
--   "Registro da rodada") contiver, na ordem, os três artefatos integrais e
--   coerentes entre si:
--     1. saída integral do E00, com d_session.checked_at e d_session.
--        backend_pid, d_baseline e d_baseline_md5;
--     2. mensagem terminal integral do envelope (H2830_ROLLBACK_PASS ou
--        H2830_FAIL), com envelope, marcador H2830_<uuid> e elapsed_ms;
--     3. este E99 JÁ COM OS MARCADORES SUBSTITUÍDOS (o texto exato submetido)
--        e sua saída integral, com d_session.checked_at.
--   Coerência exigida no registro: os valores colados no item 3 são
--   literalmente os do item 1; checked_at(E00) < submissão do envelope <
--   checked_at(E99); nenhum outro envelope entre eles; um E00 novo para
--   cada envelope (um E00 nunca é reaproveitado por dois envelopes).
--
-- O que é provado aqui (todos os g_* precisam ser TRUE; gate_pass agrega):
--   g_captured_present ....... os três marcadores foram substituídos
--   g_captured_integrity ..... md5(capturado::jsonb::text) = md5 declarado
--                              (fidelidade da cópia; NÃO origem da rodada)
--   g_keys_identical ......... o conjunto de chaves do capturado = do atual
--   g_baseline_equal ......... TODAS as chaves iguais, uma a uma; diferenças
--                              listadas em d_diff (chave, E00, agora)
--   g_freeze_canonical_equal . o estado de agora ainda é o canônico do FREEZE
--   g_marker_absent .......... marcador H2830 ausente (resíduo zero)
--   g_no_open_txn_others ..... nenhuma outra sessão em transação aberta
--   g_lock_timeout_default ... lock_timeout = '0' (SET LOCAL não vazou)
--   g_role_setting_unchanged . pg_db_role_setting com o mesmo número de
--                              linhas que o E00 registrou
--
-- O BASELINE-BUILDER e o FREEZE-CANON são cópias byte a byte dos blocos do
-- E00 (verificado por tools/static_check.py). Qualquer divergência entre as
-- duas cópias é defeito do harness.
-- ============================================================================
WITH
captured_raw AS (
    SELECT '{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0}'::text     AS baseline_text,
           '5c329d5e38a7e369cc100ab08953e1a7'::text AS baseline_md5,
           '9'::text AS role_setting_rows
),
captured AS (
    SELECT CASE WHEN baseline_text LIKE '\_\_E00%' THEN NULL ELSE baseline_text::jsonb END AS c,
           CASE WHEN baseline_md5  LIKE '\_\_E00%' THEN NULL ELSE baseline_md5 END        AS md5_declared,
           CASE WHEN role_setting_rows LIKE '\_\_E00%' THEN NULL ELSE role_setting_rows::bigint END AS role_rows_e00
      FROM captured_raw
),
base AS (
    -- BASELINE-BUILDER:BEGIN
    SELECT jsonb_build_object(
        'trait',                  (SELECT count(*) FROM public.card_edition_context_trait),
        'profile',                (SELECT count(*) FROM public.card_edition_context_profile),
        'profile_trait',          (SELECT count(*) FROM public.card_edition_context_profile_trait),
        'mapping',                (SELECT count(*) FROM public.card_edition_context_external_mapping),
        'mapping_trait',          (SELECT count(*) FROM public.card_edition_context_external_mapping_trait),
        'mapping_null_signature', (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE traits_signature IS NULL),
        'card_variant',           (SELECT count(*) FROM public.card_variant),
        'card_variant_ec_nonnull',(SELECT count(*) FROM public.card_variant WHERE edition_context_profile_id IS NOT NULL),
        'staging_rows',           (SELECT count(*) FROM public.catalog_variant_import_row),
        'staging_max_upd_utc',    (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_row),
        'staging_status',         (SELECT jsonb_object_agg(k, n) FROM (SELECT validation_status || '/' || persistence_status AS k, count(*) AS n
                                     FROM public.catalog_variant_import_row GROUP BY 1) s),
        'operational_tristate',   (SELECT jsonb_build_object(
                                        'U', count(*) FILTER (WHERE jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string'),
                                        'N', count(*) FILTER (WHERE jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null'),
                                        'A', count(*) FILTER (WHERE NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')))
                                     FROM public.catalog_variant_import_row r
                                     JOIN public.catalog_variant_import_job j ON j.id = r.job_id
                                    WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
                                      AND r.persistence_status = 'PENDING'),
        'cancelled_without_key',  (SELECT jsonb_build_object(
                                        'total', count(*),
                                        'valid_pending', count(*) FILTER (WHERE r.validation_status = 'VALID' AND r.persistence_status = 'PENDING'))
                                     FROM public.catalog_variant_import_row r
                                     JOIN public.catalog_variant_import_job j ON j.id = r.job_id
                                    WHERE j.status = 'CANCELLED'
                                      AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')),
        'lineage',                (SELECT jsonb_build_object('resulting', count(resulting_variant_id), 'matched', count(matched_variant_id))
                                     FROM public.catalog_variant_import_row),
        'jobs',                   (SELECT count(*) FROM public.catalog_variant_import_job),
        'jobs_by_status',         (SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) AS n
                                     FROM public.catalog_variant_import_job GROUP BY 1) s),
        'jobs_max_upd_utc',       (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_job),
        'jobs_in_flight',         (SELECT count(*) FROM public.catalog_variant_import_job WHERE status IN ('RECEIVED','PROCESSING','CONFIRMING')),
        'action_log',             (SELECT count(*) FROM public.catalog_admin_action_log),
        'marker_trait',           (SELECT count(*) FROM public.card_edition_context_trait WHERE code LIKE '%H2830%'),
        'marker_profile',         (SELECT count(*) FROM public.card_edition_context_profile WHERE code LIKE '%H2830%'),
        'marker_mapping',         (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE normalized_token LIKE '%H2830%')
    ) AS b
    -- BASELINE-BUILDER:END
),
canon AS (
    -- FREEZE-CANON:BEGIN
    SELECT '{
        "trait": 115,
        "profile": 144,
        "profile_trait": 196,
        "mapping": 122,
        "mapping_null_signature": 0,
        "card_variant": 24893,
        "card_variant_ec_nonnull": 0,
        "staging_rows": 26127,
        "staging_max_upd_utc": "2026-09-20T19:57:04.771758Z",
        "staging_status": {"VALID/INSERTED": 23240, "VALID/UNCHANGED": 717, "VALID/PENDING": 415,
                           "NEEDS_REVIEW/PENDING": 1656, "NEEDS_REVIEW/UNCHANGED": 13,
                           "INVALID/UNCHANGED": 80, "INVALID/PENDING": 6},
        "operational_tristate": {"U": 1092, "N": 550, "A": 0},
        "cancelled_without_key": {"total": 847, "valid_pending": 415},
        "lineage": {"resulting": 23955, "matched": 1129},
        "jobs": 145,
        "jobs_by_status": {"STAGED": 63, "COMPLETED": 71, "FAILED": 8, "CANCELLED": 3},
        "jobs_max_upd_utc": "2026-09-19T00:48:41.964146Z",
        "jobs_in_flight": 0
    }'::jsonb AS c
    -- FREEZE-CANON:END
),
all_keys AS (
    SELECT k FROM captured, jsonb_object_keys(captured.c) AS k
    UNION
    SELECT k FROM base, jsonb_object_keys(base.b) AS k
),
diff AS (
    SELECT a.k AS key, (SELECT c FROM captured) -> a.k AS e00, (SELECT b FROM base) -> a.k AS now
      FROM all_keys a
     WHERE (SELECT c FROM captured) -> a.k IS DISTINCT FROM (SELECT b FROM base) -> a.k
),
canon_diff AS (
    SELECT e.key, e.value AS canonical, (SELECT b FROM base) -> e.key AS live
      FROM canon, jsonb_each(canon.c) AS e
     WHERE (SELECT b FROM base) -> e.key IS DISTINCT FROM e.value
),
gates AS (
    SELECT
        ((SELECT c FROM captured) IS NOT NULL
         AND (SELECT md5_declared FROM captured) IS NOT NULL
         AND (SELECT role_rows_e00 FROM captured) IS NOT NULL)                         AS g_captured_present,
        (SELECT md5(c::text) = md5_declared FROM captured)                             AS g_captured_integrity,
        ((SELECT array_agg(k ORDER BY k) FROM captured, jsonb_object_keys(captured.c) AS k)
          = (SELECT array_agg(k ORDER BY k) FROM base, jsonb_object_keys(base.b) AS k)) AS g_keys_identical,
        ((SELECT c FROM captured) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM diff))     AS g_baseline_equal,
        NOT EXISTS (SELECT 1 FROM canon_diff)                                          AS g_freeze_canonical_equal,
        ((SELECT b->>'marker_trait' FROM base)::int = 0
         AND (SELECT b->>'marker_profile' FROM base)::int = 0
         AND (SELECT b->>'marker_mapping' FROM base)::int = 0)                         AS g_marker_absent,
        (SELECT count(*) = 0 FROM pg_stat_activity
          WHERE pid <> pg_backend_pid() AND datname = current_database()
            AND state IN ('idle in transaction','idle in transaction (aborted)')
            AND backend_type = 'client backend')                                       AS g_no_open_txn_others,
        current_setting('lock_timeout') = '0'                                          AS g_lock_timeout_default,
        ((SELECT count(*) FROM pg_db_role_setting) = (SELECT role_rows_e00 FROM captured)) AS g_role_setting_unchanged
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_diff',        COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.key) FROM diff d), '[]'::jsonb),
        'd_canon_diff',  COALESCE((SELECT jsonb_agg(to_jsonb(cd) ORDER BY cd.key) FROM canon_diff cd), '[]'::jsonb),
        'd_baseline_now',(SELECT b FROM base),
        'd_baseline_now_md5', (SELECT md5(b::text) FROM base),
        'd_session', jsonb_build_object(
            'lock_timeout',         current_setting('lock_timeout'),
            'db_role_setting_rows', (SELECT count(*) FROM pg_db_role_setting),
            'backend_pid',          pg_backend_pid(),
            'checked_at',           clock_timestamp())
    ) AS e99_postcheck
  FROM gates g;
```

## Apêndice B — Saídas integrais

### B.1 S1 — L1

```json
[{"l1_channel":{"checked_at":"2026-09-27T20:42:33.344775+00:00","backend_pid":3547914,"in_recovery":false,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","session_user":"postgres","ec_table_owner":{"card_edition_context_trait":"postgres","card_edition_context_profile":"postgres","card_edition_context_profile_trait":"postgres","card_edition_context_external_mapping":"postgres","card_edition_context_external_mapping_trait":"postgres"},"reads_all_stats":true,"application_name":"mgmt-api","statement_timeout":"2min","server_version_num":"170006","transaction_read_only":"off","visible_foreign_sessions":3,"activity_rows_state_hidden":0,"standard_conforming_strings":"on","default_transaction_read_only":"off","idle_in_transaction_session_timeout":"0"}}]
```

### B.2 S2 — L3

```json
[{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:42:21.237586+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T12:46:12.093029+00:00","wait_event_type":"Client","application_name":""},{"pid":3547846,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:17.117417+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547847,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:17.544796+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547848,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:17.474575+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547849,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:18.038969+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547850,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:18.071633+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547851,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:18.095205+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547852,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:40:18.14477+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547891,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:42:01.210579+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547892,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:42:01.40723+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3547913,"state":"idle","usename":"supabase_auth_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:42:31.714786+00:00","wait_event_type":"Client","application_name":""},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T20:42:04.442036+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T20:42:57.408256+00:00","locks_on_scope":[]}}]
```

### B.3 S3 — E00

Saída integral, em dois blocos literais (o objeto único devolvido pelo canal foi dividido só para leitura; nenhuma chave foi omitida). Bloco 1 — gates, sessão, baseline e diagnósticos curtos:

```json
{"d_objects":{"indexes_D":5,"indexes_1x":4,"game_pokemon":1,"source_tcgdex":1,"constraints_1x":7,"roles_anon_authenticated":2},"d_session":{"checked_at":"2026-09-27T20:46:04.514161+00:00","backend_pid":3548582,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","statement_timeout":"2min","server_version_num":"170006","db_role_setting_rows":9,"session_replication_role":"origin"},"gate_pass":true,"d_baseline":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"d_p7_rules":[],"g_no_rules":true,"d_p7_writes":[{"target":"public.card_edition_context_profile","writer":"internal.seal_edition_context_composition","gate_scope":true,"target_exists":true},{"target":"public.card_edition_context_external_mapping","writer":"internal.seal_edition_context_external_mapping","gate_scope":true,"target_exists":true}],"d_sequences":[],"g_objects_d":true,"g_p7_no_ddl":true,"d_canon_diff":[],"g_no_residue":true,"g_objects_1x":true,"g_rls_bypass":true,"g_roles_1_12":true,"d_concurrency":{"other_sessions_in_txn":0},"g_game_source":true,"d_baseline_md5":"5c329d5e38a7e369cc100ab08953e1a7","d_publications":[],"g_evt_ddl_only":true,"g_no_concurrency":true,"g_p7_no_unresolved":true,"d_evt_catalog_count":6,"d_evt_unadjudicated":[],"d_p7_eol_normalized":["public.normalize_external_catalog_value(p_value text)"],"g_p7_all_classified":true,"g_p7_identity_pinned":true,"g_p7_writes_in_scope":true,"g_evt_all_adjudicated":true,"g_p7_closure_complete":true,"g_p7_search_path_safe":true,"d_evt_allowlist_absent":[],"d_p7_unqualified_writes":[],"g_p7_no_unqualified_dml":true,"g_evt_inventory_complete":true,"g_freeze_canonical_equal":true,"g_p7_lexically_supported":true,"d_p7_unresolved_qualified":[],"g_pg17_maintain_privilege":true,"g_no_sequences_touched_now":true,"g_p7_no_external_or_dynamic":true}
```

Bloco 2 — `d_p7_functions`, `d_event_triggers` e `d_p7_unqualified_calls`, literais:

```json
{"d_p7_functions":[{"fn":"internal.enforce_edition_context_mapping_header()","via":"trigger trg_cecem_header","class":"GUARD","depth":1,"body_md5":"9e5fba31721c5e84212bd2116d3fa214","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"9e5fba31721c5e84212bd2116d3fa214","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_mapping_signature_write()","via":"trigger trg_cecem_signature_write","class":"GUARD","depth":1,"body_md5":"28084443cf6f32f9336d470ca16b7e72","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"28084443cf6f32f9336d470ca16b7e72","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_signature_write()","via":"trigger trg_cecp_signature_write","class":"GUARD","depth":1,"body_md5":"caa2e4d40d8e4995e217d7284f9d6c3b","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile","body_md5_lf":"caa2e4d40d8e4995e217d7284f9d6c3b","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_composition_immutable()","via":"trigger trg_cecpt_immutable","class":"GUARD","depth":1,"body_md5":"cfdcb500bb1090cd44c0e73d94c3f72e","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile_trait","body_md5_lf":"cfdcb500bb1090cd44c0e73d94c3f72e","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_mapping_composition_immutable()","via":"trigger trg_cecemt_immutable","class":"GUARD","depth":1,"body_md5":"ad0c472cfa82c71ee955d9b653755bdc","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping_trait","body_md5_lf":"ad0c472cfa82c71ee955d9b653755bdc","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_trait_active()","via":"trigger trg_cecpt_trait_active","class":"GUARD","depth":1,"body_md5":"68fb05f1c23db63a59611b0a12f79edd","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile_trait","body_md5_lf":"68fb05f1c23db63a59611b0a12f79edd","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.normalize_edition_context_external_mapping()","via":"trigger trg_cecem_normalize","class":"NORMALIZE","depth":1,"body_md5":"15ea6245b8b8ce2173abb3d6b72c6736","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"15ea6245b8b8ce2173abb3d6b72c6736","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_external_catalog_value(p_value text)","via":"trigger trg_cecem_normalize","class":"PURE","depth":2,"body_md5":"81361bb8f52ce142803d69c2b3028ae8","cr_count":2,"language":"sql","proconfig":["search_path=\"\""],"crlf_count":2,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"1fdc2e7ebe2297f8db85be4aad2e5d33","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(regdictionary, text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"cr_count":0,"language":"c","proconfig":null,"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":null,"dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"cr_count":0,"language":"c","proconfig":null,"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":null,"dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_composition()","via":"trigger trg_cecp_seal","class":"SEAL","depth":1,"body_md5":"6077409ac2b5de7f788076e3b4b3f0c0","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile","body_md5_lf":"6077409ac2b5de7f788076e3b4b3f0c0","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_external_mapping()","via":"trigger trg_cecem_seal","class":"SEAL","depth":1,"body_md5":"49a4ea4b34ccf06a4efdcf06270c52eb","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"49a4ea4b34ccf06a4efdcf06270c52eb","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.axis_identity_token(p_data jsonb, p_key text)","via":"index uq_cvir_row_identity","class":"UNCLASSIFIED","depth":1,"body_md5":"18682dce935281b0a4437628a6e8309a","cr_count":0,"language":"sql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"18682dce935281b0a4437628a6e8309a","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_edition_context_profile_game()","via":"trigger trg_card_variant_edition_context_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"21e3a4c08989545351e2757c59fc77c4","cr_count":36,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":36,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"27c1845dea596dd9b46413019799ab33","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_printing_profile_game()","via":"trigger trg_card_variant_printing_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"e847a065643a7836085eefc8116bb9c5","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"e847a065643a7836085eefc8116bb9c5","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_cvir_normalized_shape()","via":"trigger trg_cvir_normalized_shape","class":"UNCLASSIFIED","depth":1,"body_md5":"1cebffee8afb213481342a9d402eb462","cr_count":62,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":62,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"f5bcae1bd83a6880c63519b31f36c5c4","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_job()","via":"trigger trg_catalog_variant_import_job_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"c01adb02245bd5a305e8f8987a30f1c1","cr_count":0,"language":"plpgsql","proconfig":null,"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_job","body_md5_lf":"c01adb02245bd5a305e8f8987a30f1c1","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_row()","via":"trigger trg_catalog_variant_import_row_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"7ae9bd52e030b13c3a241debda491a99","cr_count":0,"language":"plpgsql","proconfig":null,"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"7ae9bd52e030b13c3a241debda491a99","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.set_updated_at()","via":"trigger trg_card_variant_set_updated_at","class":"UNCLASSIFIED","depth":1,"body_md5":"7933f81decf127af71628126ef109c81","cr_count":5,"language":"plpgsql","proconfig":["search_path=public, pg_temp"],"crlf_count":5,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"98a97559965c2e0ff884d95155ab5d3a","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.validate_card_variant_game_consistency()","via":"trigger trg_card_variant_validate_game_consistency","class":"UNCLASSIFIED","depth":1,"body_md5":"331a5501cb28172a63d2c3202594beaa","cr_count":40,"language":"plpgsql","proconfig":null,"crlf_count":40,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"c1fe17587dfb3b0f6d7d5d690ca13636","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false}],"d_event_triggers":[{"fn":"extensions.set_graphql_placeholder()","name":"issue_graphql_placeholder","tags":["DROP EXTENSION"],"event":"sql_drop","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"a2bc2d00b2cc2f5e8d2d6b8d73e2c360","fn_secdef":false,"fn_md5_raw":"a2bc2d00b2cc2f5e8d2d6b8d73e2c360","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_cron_access()","name":"issue_pg_cron_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"3a3917aad6ddd66182bf45b7490c3029","fn_secdef":false,"fn_md5_raw":"3a3917aad6ddd66182bf45b7490c3029","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_graphql_access()","name":"issue_pg_graphql_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"dd3f3e2bb94cff45ef24b9cecb6af1c8","fn_secdef":false,"fn_md5_raw":"dd3f3e2bb94cff45ef24b9cecb6af1c8","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_net_access()","name":"issue_pg_net_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"2ee4e6920eeba3068bcfa838105352e2","fn_secdef":false,"fn_md5_raw":"2ee4e6920eeba3068bcfa838105352e2","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.pgrst_ddl_watch()","name":"pgrst_ddl_watch","tags":null,"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"7f27b8118fea5c88b0164331292859e3","fn_secdef":false,"fn_md5_raw":"7f27b8118fea5c88b0164331292859e3","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.pgrst_drop_watch()","name":"pgrst_drop_watch","tags":null,"event":"sql_drop","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"bc09cc3003d66f91844af4cb05e203b7","fn_secdef":false,"fn_md5_raw":"bc09cc3003d66f91844af4cb05e203b7","fn_language":"plpgsql","fn_extension":null}],"d_p7_unqualified_calls":[{"name":"jsonb_typeof","caller":"internal.axis_identity_token","gate_scope":false,"resolution":"BUILTIN"},{"name":"array","caller":"internal.enforce_edition_context_mapping_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"array","caller":"internal.enforce_edition_context_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"and","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"if","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"in","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"jsonb_exists","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"jsonb_typeof","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.guard_edition_context_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_mapping_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_trait_active","gate_scope":true,"resolution":"KEYWORD"},{"name":"btrim","caller":"internal.normalize_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"coalesce","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"regexp_replace","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"},{"name":"trim","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"}]}
```

### B.4 S4 — E03P

```json
{"d_session":{"checked_at":"2026-09-27T20:47:38.127993+00:00","backend_pid":3548611,"current_user":"postgres","lock_timeout":"0","server_version_num":"170006"},"gate_pass":true,"g_s2_triggers":true,"g_nn_rls_bypass":true,"g_nn_no_sequence":true,"g_s2_constraints":true,"g_s2_error_tokens":true,"g_game_pokemon_one":true,"g_s2_function_pins":true,"g_marker_absent_now":true,"g_deferrable_only_seal":true,"g_no_other_triggers_l1":true,"g_seal_constraint_names_unique":true,"d_nn_sequences":[],"d_marker_counts":{"marker_trait":0,"marker_profile":0},"d_signature_index":[{"ready":true,"valid":true,"unique":true,"columns":["game_id","traits_signature"],"relation":"card_edition_context_profile","predicate":"(traits_signature IS NOT NULL)"}],"d_nn_ownership_rls":[{"rls":true,"owner":"postgres","force_rls":false}],"d_seal_constraints":[{"conname":"trg_cecem_seal","contype":"t","relation":"card_edition_context_external_mapping","condeferred":true,"condeferrable":true},{"conname":"trg_cecp_seal","contype":"t","relation":"card_edition_context_profile","condeferred":true,"condeferrable":true}],"d_function_pins":[{"fn":"internal.enforce_edition_context_signature_write()","pin":"caa2e4d40d8e4995e217d7284f9d6c3b","resolved":true,"body_md5_lf":"caa2e4d40d8e4995e217d7284f9d6c3b"},{"fn":"internal.guard_edition_context_composition_immutable()","pin":"cfdcb500bb1090cd44c0e73d94c3f72e","resolved":true,"body_md5_lf":"cfdcb500bb1090cd44c0e73d94c3f72e"},{"fn":"internal.guard_edition_context_trait_active()","pin":"68fb05f1c23db63a59611b0a12f79edd","resolved":true,"body_md5_lf":"68fb05f1c23db63a59611b0a12f79edd"},{"fn":"internal.seal_edition_context_composition()","pin":"6077409ac2b5de7f788076e3b4b3f0c0","resolved":true,"body_md5_lf":"6077409ac2b5de7f788076e3b4b3f0c0"}],"d_error_tokens":[{"tok":"EDITION_CONTEXT_SIGNATURE_IMMUTABLE:","present":true,"proname":"enforce_edition_context_signature_write"},{"tok":"EDITION_CONTEXT_SIGNATURE_MISMATCH:","present":true,"proname":"enforce_edition_context_signature_write"},{"tok":"EDITION_CONTEXT_COMPOSITION_IMMUTABLE:","present":true,"proname":"guard_edition_context_composition_immutable"},{"tok":"EDITION_CONTEXT_TRAIT_INACTIVE:","present":true,"proname":"guard_edition_context_trait_active"},{"tok":"EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:","present":true,"proname":"seal_edition_context_composition"}]}
```

`d_triggers` e `d_constraints`, literais (completam a saída integral):

```json
{"d_triggers":[{"fn":"internal.seal_edition_context_composition()","attrs":[],"tgname":"trg_cecp_seal","tgtype":5,"enabled":"O","relname":"card_edition_context_profile","deferrable":true,"initdeferred":true,"is_constraint":true},{"fn":"internal.enforce_edition_context_signature_write()","attrs":["traits_signature"],"tgname":"trg_cecp_signature_write","tgtype":19,"enabled":"O","relname":"card_edition_context_profile","deferrable":false,"initdeferred":false,"is_constraint":false},{"fn":"internal.guard_edition_context_composition_immutable()","attrs":[],"tgname":"trg_cecpt_immutable","tgtype":31,"enabled":"O","relname":"card_edition_context_profile_trait","deferrable":false,"initdeferred":false,"is_constraint":false},{"fn":"internal.guard_edition_context_trait_active()","attrs":[],"tgname":"trg_cecpt_trait_active","tgtype":7,"enabled":"O","relname":"card_edition_context_profile_trait","deferrable":false,"initdeferred":false,"is_constraint":false}],"d_constraints":[{"conname":"card_edition_context_profile_game_id_fkey","contype":"f","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"card_edition_context_profile_pkey","contype":"p","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_code_format","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_description_not_blank","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_display_order_positive","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_name_not_blank","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_signature_not_empty","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_signature_shape","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"trg_cecp_seal","contype":"t","relname":"card_edition_context_profile","condeferred":true,"convalidated":true,"condeferrable":true},{"conname":"uq_cecp_game_code","contype":"u","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cecp_game_order","contype":"u","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cecp_id_game","contype":"u","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"fk_cecpt_profile","contype":"f","relname":"card_edition_context_profile_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"fk_cecpt_trait","contype":"f","relname":"card_edition_context_profile_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"pk_cecpt","contype":"p","relname":"card_edition_context_profile_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"card_edition_context_trait_game_id_fkey","contype":"f","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"card_edition_context_trait_pkey","contype":"p","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_code_family_prefix","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_code_format","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_description_not_blank","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_display_order_positive","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_family","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_name_not_blank","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cect_game_code","contype":"u","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cect_game_family_order","contype":"u","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cect_id_game","contype":"u","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false}]}
```

### B.5 S5 — E03

Ver §3 (resposta integral do canal).

### B.6 S6 — E99

```json
[{"e99_postcheck":{"d_diff":[],"d_session":{"checked_at":"2026-09-27T20:54:28.998387+00:00","backend_pid":3549334,"lock_timeout":"0","db_role_setting_rows":9},"gate_pass":true,"d_canon_diff":[],"d_baseline_now":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"g_marker_absent":true,"g_baseline_equal":true,"g_keys_identical":true,"d_baseline_now_md5":"5c329d5e38a7e369cc100ab08953e1a7","g_captured_present":true,"g_captured_integrity":true,"g_no_open_txn_others":true,"g_lock_timeout_default":true,"g_freeze_canonical_equal":true,"g_role_setting_unchanged":true}}]
```

### B.7 S7 — L3 final

```json
[{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:54:20.182857+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T12:46:12.093029+00:00","wait_event_type":"Client","application_name":""},{"pid":3548641,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:26.324193+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548642,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:26.350312+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548643,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:30.884911+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548644,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:30.855609+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548645,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:31.088219+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548648,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:25.921976+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548649,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:50:26.278582+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548671,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:52:00.952685+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3548672,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T20:52:01.057957+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T20:52:04.075585+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T20:54:32.695074+00:00","locks_on_scope":[]}}]
```

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Execução e registro (2026-09-27, `BATCH12-2830-P5-L1-E03-LIVE-EXECUTION-01`, baseline `3a089e08`).** 7 chamadas `execute_sql` (L1 → L3 → E00 → E03P → E03 → E99 → L3 final), sem L3-D. E03 `ef24a3be…`: `H283P`, `pass=13/13`, 13 casos na ordem, marcador `H2830_DB0A64F6039349658EA013D218D2C452`, contexto `line 1703`, `elapsed_ms=202`. E99 9/9, `d_diff = []`; L3 final limpa; postcheck ÍNTEGRO; classificação **CONFORME**. Proposta `2.1–2.5, 2.7–2.14 PASS`, sujeita à auditoria independente; cobertura declarada 17/135 até o parecer. Desvio D-1 (S6 e S7 despachados no mesmo lote; ordem provada pelos horários do banco). DP-5 esgotada. FREEZE ATIVO. |
| 1.1 | **Fechamento (2026-09-27, `BATCH12-2830-P5-ENGINEERING-DECISIONS-01`, baseline `36a3bc06`), documental, sem SQL e sem LIVE.** Encerra a divergência DV-1: incorpora o parecer independente PASS (comunicado por Fabrício; commit `e6af59c1`) e a cobertura reconhecida **30/135** (novo §8; campos Estado e Efeito contratual com v1.1 vigente e v1.0 histórica). Execução, textos submetidos, saídas e §1–§7 preservados; E03 não reaberto. FREEZE ATIVO. |
