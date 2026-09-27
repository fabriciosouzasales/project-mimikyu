# 2830H — Lote L1: registro de execução LIVE do E03T

| Campo | Valor |
|---|---|
| **Natureza** | Registro da execução controlada do E03T (diagnóstico T1–T3), conforme `L1-E03T-LIVE-EXECUTION-PLAN.md` v1.0 e `L1-EXECUTION-READINESS.md` v1.3. **Não é caso da 2830**: não gera PASS contratual e não altera a cobertura. |
| **Mandato** | `BATCH12-2830-P5-L1-E03T-LIVE-EXECUTION-01`. Baseline HEAD `7934fe47ef4f56b48de1e23e9400ff9234ab962e`. Decisões DP-1 = A′, DP-4 = B, DP-5 = A, DP-7 = A. `MAX_L3_D = 1`. |
| **Autorização** | Expressa e limitada, de Fabrício, no mandato: só as escritas transitórias do E03T publicado (blob `9523bf23…`), com rollback obrigatório e verificação posterior. Não contempla E03, alteração de SQL, migration, limpeza, teste experimental nem alteração de configuração. |
| **Resultado** | **CONFORME (diagnóstico)**. `H283P`, `pass=3/3`, marcador `H2830_4C4BA06675344B72ABCFA4D9995B4F7F`, `elapsed_ms=133`. Postcheck **ÍNTEGRO** (E99 9/9, `d_diff = []`; L3 final limpa). Fluxo normal, sem L3-D. |
| **Estado** | **v1.1 — fechamento documental** (`BATCH12-2830-P5-L1-E03T-PUBLICATION-CORRECTION-01`): execução do E03T **CONFORME (diagnóstico)**; auditoria técnica independente **PASS**; publicação documental **pendente de commit/push por Fabrício**. E03 **não autorizado**. Cobertura LIVE **17/135** (inalterada). **FREEZE ATIVO.** |
| **Papéis** | **Claude**: executor. **ChatGPT**: auditor independente. **Fabrício**: autorizações, commit e push. |

---

## 1. S0 — verificação local (antes de qualquer conexão)

| Item | Resultado |
|---|---|
| HEAD | `7934fe47ef4f56b48de1e23e9400ff9234ab962e` = baseline do mandato |
| Árvore e índice | limpos: `git status --porcelain --untracked-files=all` 0 linhas; `git diff --cached --name-only` 0 linhas |
| E00 | blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` = HEAD · md5 `45b6c35cca849ffbf49d22ec18e8283c` · 53.803 B |
| E03P | blob `0fc2d83dff599fc6cc26e35399ebc519a5a51d0f` = HEAD · md5 `10457d87d4c25c93ab04d0fadf43dddc` · 13.335 B |
| **E03T** | blob **`9523bf23f68fe78a1e126dff1f85ccc8ece5c2dc`** = HEAD = blob autorizado · md5 `34d3826e1e8b4a3d3871b87733c6538b` · sha256 `2eb3e2a46bd644dafeb2b2c8307fb1f39af9c5e2743a1ddebbd9011ae10ec1f0` · 25.029 B |
| E99 (base) | blob `49a71ecb4525697858110ee71a3f61f5eee74a34` = HEAD · md5 `f0b91183a8649b990b080637dd56e74b` · 12.289 B |
| `tools/static_check.py` | blob `6b3689cc…` = HEAD; `TOTAL 444 PASS 444 FAIL 0`, `E03-PERFIL 85/85`, `E03-VERIFICADOR-NEG 56/56`, `E03-VERIFICADOR-POS 4/4` |
| Readiness v1.3 / plano v1.0 | blobs `76cca828…` / `f71e6b38…` = HEAD |
| Protocolo / roteiro / 2830 | `abe806d6…` / `9f454a96…` / `b4647dcb…` = HEAD |
| L1 / L3 | recalculados dos blocos do roteiro: md5 `0836c36a8d3749b1e7718223e064caf9` (2.458 B) e `b7bc3700aeef278f6a79bd30e6a8d229` (1.526 B) |
| Canal | Supabase MCP `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`; uma chamada por statement |

## 2. Sequência e cronologia

| Passo | Chamada | Horário (banco) | SQLSTATE | Resultado |
|---|---|---|---|---|
| S1 | L1 (`0836c36a…`) | `checked_at` 19:12:31.128686Z · pid 3541592 | nenhum | **conforme**: `transaction_read_only = off`, `default_transaction_read_only = off`, `in_recovery = false`, **`lock_timeout = '0'`**, **`statement_timeout = '2min'`**, PG `170006`, `standard_conforming_strings = on`, donos das 5 tabelas EC = `postgres` = `current_user`, visibilidade por `reads_all_stats = true` (e `visible_foreign_sessions = 2`) |
| S2 | L3 (`b7bc3700…`) | `checked_at` 19:12:50.062467Z | nenhum | **conforme**: `locks_on_scope = []`; 12 `client backend`, todas `idle`, sem `xact_start` e sem `backend_xid` |
| S3 | E00 (`45b6c35c…`), novo, desta rodada | `checked_at` 19:15:54.496955Z · pid 3541640 | nenhum | **24/24 gates `true`, `gate_pass = true`**; `d_canon_diff = []`; `d_baseline_md5 = 5c329d5e38a7e369cc100ab08953e1a7`; `db_role_setting_rows = 9` |
| S4 | E03P (`10457d87…`) | `checked_at` 19:18:00.211255Z · pid 3541667 | nenhum | **11/11 gates `true`, `gate_pass = true`** |
| S5 | **E03T** (`34d3826e…`), integral, **uma** submissão | entre S4 e S6; o canal não devolve horário para erro | **`H283P`** | resposta definida e conforme (§3) |
| S6 | E99 com os 3 marcadores do S3 (`00233aa60c571994f39df2df3faf05ea`) | `checked_at` 19:21:40.226267Z · pid 3542352 | nenhum | **9/9 gates `true`, `gate_pass = true`**, `d_diff = []`, `d_canon_diff = []` |
| S7 | L3 final (`b7bc3700…`) | `checked_at` 19:21:51.73575Z | nenhum | **limpa**: `locks_on_scope = []`; 12 `client backend`, todas `idle`, sem `xact_start` e sem `backend_xid`; nenhum pid desta rodada presente |

- Exatamente **7 chamadas** `execute_sql`, nesta ordem, sem repetição e sem nenhuma outra entre elas. **Nenhuma L3-D**: a resposta do S5 foi definida.
- Ordem temporal: `checked_at(L1) < checked_at(L3) < checked_at(E00) < checked_at(E03P) < S5 < checked_at(E99) < checked_at(L3 final)` — conferida localmente.
- Intervalo E00 → E99: 345,7 s. Janela L1 → L3 final: 560,6 s. Entre as chamadas houve só conferência local.
- O E00 é novo desta rodada (`backend_pid` 3541640 e `checked_at` próprios). Todo o `d_baseline` é igual ao das Etapas 2 e 3: o estado continuou estável sob FREEZE.

## 3. Resposta do E03T (S5) — literal

```
ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E03T_N1_CONTROLE pass=3/3 casos=T1,T2,T3 marker=H2830_4C4BA06675344B72ABCFA4D9995B4F7F elapsed_ms=133
CONTEXT:  PL/pgSQL function inline_code_block line 454 at RAISE
```

Resposta integral do canal (`HttpException`), preservada sem edição:

```
{"error":{"name":"HttpException","message":"Failed to run sql query: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E03T_N1_CONTROLE pass=3/3 casos=T1,T2,T3 marker=H2830_4C4BA06675344B72ABCFA4D9995B4F7F elapsed_ms=133\nCONTEXT:  PL/pgSQL function inline_code_block line 454 at RAISE\n"}}
```

| Critério (readiness §4.3 / plano §5) | Observado | Resultado |
|---|---|---|
| SQLSTATE | `H283P` | conforme |
| Mensagem casa com `^H2830_ROLLBACK_PASS: envelope=E03T_N1_CONTROLE pass=3/3 casos=T1,T2,T3 marker=H2830_[0-9A-F]{32} elapsed_ms=[0-9]+$` | sim, não truncada | conforme |
| Contexto `PL/pgSQL function inline_code_block line 454 at RAISE` (RAISE terminal l. 482, `DO` l. 29) | idêntico | conforme |
| `elapsed_ms ≤ 60000` (DP-1 = A′) | **133** | conforme |

`H283P` sozinho não é aceite: a classificação depende do postcheck (§4–§5).

## 4. Postcheck — E00 × E99 (S3 × S6)

### 4.1 Preparação do E99

- **Origem dos valores:** saída do S3 **desta** rodada: `d_baseline` na forma literal devolvida pelo canal (787 B, sem apóstrofo, contida byte a byte na resposta registrada do S3), `d_baseline_md5 = 5c329d5e38a7e369cc100ab08953e1a7`, `db_role_setting_rows = 9`.
- **Controles antes de submeter:** `md5(jsonb::text)` do JSON capturado, recalculado localmente (chaves por comprimento e bytes, separadores `", "`/`": "`), = `5c329d5e…`; cada literal substituído exatamente uma vez; o texto difere do arquivo base só nas linhas 56–58.
- **Texto submetido:** md5 `00233aa60c571994f39df2df3faf05ea`, 13044 B, integral no Apêndice A. É byte a byte igual ao E99 das Etapas 2 e 3, porque os três valores capturados agora são os mesmos (o `d_baseline` não mudou sob FREEZE). Os valores vêm do S3 desta rodada; a vinculação é documental (§2).
- **Registro de preparação:** a primeira geração local serializou o JSON na forma canônica do `jsonb::text` (861 B; texto md5 `54357836d9b39b3877eb8b30dae869b5`). Passou nos mesmos controles, mas **não foi submetida**: foi regenerada, da mesma saída do S3, na forma literal do canal, que é o que o E99 pede ("colar, nunca redigitar") e o precedente das Etapas 2 e 3. Nenhum SQL foi executado entre as duas gerações.

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
| `g_lock_timeout_default` | true |
| `g_role_setting_unchanged` | true |
| `gate_pass` | **true** |
| `d_diff` / `d_canon_diff` | `[]` / `[]` |
| `d_baseline_now_md5` | `5c329d5e38a7e369cc100ab08953e1a7` = `d_baseline_md5` do E00 |

### 4.3 Comparação chave a chave (seleção; as 22 chaves são iguais)

| Chave | E00 (S3) | E99 (S6) |
|---|---|---|
| `trait` | 115 | 115 |
| `profile` | 144 | 144 |
| `profile_trait` | 196 | 196 |
| `mapping` | 122 | 122 |
| `mapping_trait` | 122 | 122 |
| `marker_trait` / `marker_profile` / `marker_mapping` | 0 / 0 / 0 | 0 / 0 / 0 |
| `card_variant` | 24.893 | 24.893 |
| `action_log` | 1.352 | 1.352 |
| `staging_rows` | 26.127 | 26.127 |
| `jobs` | 145 | 145 |

### 4.4 Classificação do postcheck (readiness §4.4)

E99 completo com todos os critérios **e** L3 final completa, sem lock no escopo, sem sessão ativa ou em transação e sem pid desta rodada ⇒ **ÍNTEGRO**. Resíduo zero afirmado **só** nesta base.

**Prova de rollback — três fontes independentes:**

| Fonte | Evidência |
|---|---|
| 1. Mensagem terminal | `H283P` com o marcador desta execução; o `DO` terminou em exceção; T1, T2 e T3 terminaram em `H283C` dentro de subtransação; 4 sondas `H283S` descartadas |
| 2. E99 | 22 chaves do `d_baseline` iguais ao E00; `d_diff = []`; marcador ausente em `trait.code`, `profile.code` e `mapping.normalized_token`; `d_canon_diff = []` |
| 3. L3 final | `locks_on_scope = []`; nenhuma sessão remanescente ativa ou em transação; pids 3541592, 3541640, 3541667 e 3542352 ausentes |

## 5. Classificação final e fundamentação

**CONFORME (diagnóstico)**, pela regra da readiness v1.3 (§4.5, INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME): §4.3 conforme; postcheck ÍNTEGRO; `elapsed_ms = 133 ≤ 60000`; ordem temporal registrada. Nenhum evento da tabela STOP/CONTINUE foi acionado.

**O que este CONFORME demonstra (R, agora observado no LIVE 17.6):**
- `SET CONSTRAINTS … IMMEDIATE/DEFERRED` funciona dentro do `DO` (N-1), inclusive com IMMEDIATE que falha e é capturado (T2, `P0001` / `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION`, `v_step = IMMEDIATE`);
- as 4 sondas confirmaram DEFERRED e foram descartadas;
- o IMMEDIATE posterior à sonda não foi contaminado (T3: sem erro, selo intacto, nenhuma linha de sonda visível);
- o rollback deixou o estado igual ao baseline.

**O que não demonstra:**
- **limite L-1**: o T3 prova ausência de contaminação observável, **não** a remoção direta do evento diferido da fila;
- o comportamento dos 13 casos do E03, seus caminhos, tokens e constraints;
- o tempo do E03 (o `elapsed_ms` do E03T é só indício);
- concorrência com escritor real.

**Efeito contratual:** nenhum. Não é PASS de nenhum dos 135 casos. Cobertura LIVE **17/135**. O resultado atende às condições T-2 e T-3 do §6 da readiness, mas **não autoriza o E03**: T-4 (parecer independente), T-5 (DP-1/DP-4/DP-5 para o E03) e T-6 (mandato) continuam pendentes.

## 6. Incidentes, desvios e limitações

- **Incidentes:** nenhum. **STOP:** não houve.
- **Desvio de procedimento (local, sem SQL):** a primeira geração do texto do E99 usou a serialização canônica do JSON e foi descartada antes da submissão (§4.1). Registrado para a auditoria.
- **Relógio local ≠ relógio do banco:** o `date` do sandbox marcava 19:13:42Z no S0, e a L1 registrou 19:12:31Z. A ordem S0 → S1 é dada pela sequência das ações, não pelos relógios; a cronologia do §2 usa só o horário do banco.
- **Canal:**
  - o MCP não devolve o md5 do texto efetivamente submetido; a identidade dos textos vem de S0 e da submissão integral, sem edição;
  - a resposta de erro do E03T chega como `HttpException`, com o SQLSTATE no texto, sem horário do servidor e sem `backend_pid`;
  - `elapsed_ms` é medido dentro do bloco (`clock_timestamp()`), sem a latência do canal;
  - as conexões do canal são por chamada; a ausência do backend do E03T é inferida da L3 final (nenhuma sessão ativa ou em transação, nenhum lock no escopo).
- **Resíduo não-transacional declarado, aceito e não verificado:** contadores `pg_stat_*`, tuplas mortas até o autovacuum, WAL, XIDs de subtransação e linhas de log com o marcador. Nenhum é dado de negócio.
- **Texto histórico nos SQLs (blobs preservados):** o cabeçalho do E03T ainda diz "NÃO EXECUTADO" e "DECISÃO PENDENTE (DP-4)". A execução está neste registro; a decisão, na readiness v1.3.

## 7. Estado do repositório e governança

- Nenhum envelope, SQL, protocolo, migration ou configuração foi alterado. Nenhum `SET`, `pg_terminate_backend`, limpeza ou retry.
- Não executados: E03, E01, E02, L2, L4, L3-D.
- Sem `git add`, commit ou push. Este registro e as linhas de README e `docs/log.md` ficam para auditoria e publicação por Fabrício.
- A autorização de escrita transitória do E03T limitou-se a esta execução e está esgotada. **FREEZE ATIVO.**

---

## Apêndice A — E99, texto exato submetido (md5 `00233aa60c571994f39df2df3faf05ea`)

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
[{"l1_channel":{"checked_at":"2026-09-27T19:12:31.128686+00:00","backend_pid":3541592,"in_recovery":false,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","session_user":"postgres","ec_table_owner":{"card_edition_context_trait":"postgres","card_edition_context_profile":"postgres","card_edition_context_profile_trait":"postgres","card_edition_context_external_mapping":"postgres","card_edition_context_external_mapping_trait":"postgres"},"reads_all_stats":true,"application_name":"mgmt-api","statement_timeout":"2min","server_version_num":"170006","transaction_read_only":"off","visible_foreign_sessions":2,"activity_rows_state_hidden":0,"standard_conforming_strings":"on","default_transaction_read_only":"off","idle_in_transaction_session_timeout":"0"}}]
```

### B.2 S2 — L3

```json
[{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:12:21.577259+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T12:46:12.093029+00:00","wait_event_type":"Client","application_name":""},{"pid":3540853,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:05:13.974251+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3540855,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:05:14.00888+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3540856,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:05:14.055776+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3540882,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:07:01.313842+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3540883,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:07:01.51213+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3540925,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:10:01.82554+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3540926,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:10:02.442438+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541588,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:12:02.00155+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541589,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:12:02.204725+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T19:12:04.248185+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T19:12:50.062467+00:00","locks_on_scope":[]}}]
```

### B.3 S3 — E00

```json
[{"e00_precheck":{"d_objects":{"indexes_D":5,"indexes_1x":4,"game_pokemon":1,"source_tcgdex":1,"constraints_1x":7,"roles_anon_authenticated":2},"d_session":{"checked_at":"2026-09-27T19:15:54.496955+00:00","backend_pid":3541640,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","statement_timeout":"2min","server_version_num":"170006","db_role_setting_rows":9,"session_replication_role":"origin"},"gate_pass":true,"d_baseline":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"d_p7_rules":[],"g_no_rules":true,"d_p7_writes":[{"target":"public.card_edition_context_profile","writer":"internal.seal_edition_context_composition","gate_scope":true,"target_exists":true},{"target":"public.card_edition_context_external_mapping","writer":"internal.seal_edition_context_external_mapping","gate_scope":true,"target_exists":true}],"d_sequences":[],"g_objects_d":true,"g_p7_no_ddl":true,"d_canon_diff":[],"g_no_residue":true,"g_objects_1x":true,"g_rls_bypass":true,"g_roles_1_12":true,"d_concurrency":{"other_sessions_in_txn":0},"g_game_source":true,"d_baseline_md5":"5c329d5e38a7e369cc100ab08953e1a7","d_p7_functions":[{"fn":"internal.enforce_edition_context_mapping_header()","via":"trigger trg_cecem_header","class":"GUARD","depth":1,"body_md5":"9e5fba31721c5e84212bd2116d3fa214","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"9e5fba31721c5e84212bd2116d3fa214","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_mapping_signature_write()","via":"trigger trg_cecem_signature_write","class":"GUARD","depth":1,"body_md5":"28084443cf6f32f9336d470ca16b7e72","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"28084443cf6f32f9336d470ca16b7e72","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_signature_write()","via":"trigger trg_cecp_signature_write","class":"GUARD","depth":1,"body_md5":"caa2e4d40d8e4995e217d7284f9d6c3b","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile","body_md5_lf":"caa2e4d40d8e4995e217d7284f9d6c3b","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_composition_immutable()","via":"trigger trg_cecpt_immutable","class":"GUARD","depth":1,"body_md5":"cfdcb500bb1090cd44c0e73d94c3f72e","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile_trait","body_md5_lf":"cfdcb500bb1090cd44c0e73d94c3f72e","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_mapping_composition_immutable()","via":"trigger trg_cecemt_immutable","class":"GUARD","depth":1,"body_md5":"ad0c472cfa82c71ee955d9b653755bdc","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping_trait","body_md5_lf":"ad0c472cfa82c71ee955d9b653755bdc","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_trait_active()","via":"trigger trg_cecpt_trait_active","class":"GUARD","depth":1,"body_md5":"68fb05f1c23db63a59611b0a12f79edd","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile_trait","body_md5_lf":"68fb05f1c23db63a59611b0a12f79edd","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.normalize_edition_context_external_mapping()","via":"trigger trg_cecem_normalize","class":"NORMALIZE","depth":1,"body_md5":"15ea6245b8b8ce2173abb3d6b72c6736","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"15ea6245b8b8ce2173abb3d6b72c6736","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_external_catalog_value(p_value text)","via":"trigger trg_cecem_normalize","class":"PURE","depth":2,"body_md5":"81361bb8f52ce142803d69c2b3028ae8","cr_count":2,"language":"sql","proconfig":["search_path=\"\""],"crlf_count":2,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"1fdc2e7ebe2297f8db85be4aad2e5d33","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(regdictionary, text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"cr_count":0,"language":"c","proconfig":null,"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":null,"dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"cr_count":0,"language":"c","proconfig":null,"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":null,"dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_composition()","via":"trigger trg_cecp_seal","class":"SEAL","depth":1,"body_md5":"6077409ac2b5de7f788076e3b4b3f0c0","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile","body_md5_lf":"6077409ac2b5de7f788076e3b4b3f0c0","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_external_mapping()","via":"trigger trg_cecem_seal","class":"SEAL","depth":1,"body_md5":"49a4ea4b34ccf06a4efdcf06270c52eb","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"49a4ea4b34ccf06a4efdcf06270c52eb","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.axis_identity_token(p_data jsonb, p_key text)","via":"index uq_cvir_row_identity","class":"UNCLASSIFIED","depth":1,"body_md5":"18682dce935281b0a4437628a6e8309a","cr_count":0,"language":"sql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"18682dce935281b0a4437628a6e8309a","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_edition_context_profile_game()","via":"trigger trg_card_variant_edition_context_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"21e3a4c08989545351e2757c59fc77c4","cr_count":36,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":36,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"27c1845dea596dd9b46413019799ab33","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_printing_profile_game()","via":"trigger trg_card_variant_printing_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"e847a065643a7836085eefc8116bb9c5","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"e847a065643a7836085eefc8116bb9c5","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_cvir_normalized_shape()","via":"trigger trg_cvir_normalized_shape","class":"UNCLASSIFIED","depth":1,"body_md5":"1cebffee8afb213481342a9d402eb462","cr_count":62,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":62,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"f5bcae1bd83a6880c63519b31f36c5c4","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_job()","via":"trigger trg_catalog_variant_import_job_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"c01adb02245bd5a305e8f8987a30f1c1","cr_count":0,"language":"plpgsql","proconfig":null,"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_job","body_md5_lf":"c01adb02245bd5a305e8f8987a30f1c1","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_row()","via":"trigger trg_catalog_variant_import_row_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"7ae9bd52e030b13c3a241debda491a99","cr_count":0,"language":"plpgsql","proconfig":null,"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"7ae9bd52e030b13c3a241debda491a99","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.set_updated_at()","via":"trigger trg_card_variant_set_updated_at","class":"UNCLASSIFIED","depth":1,"body_md5":"7933f81decf127af71628126ef109c81","cr_count":5,"language":"plpgsql","proconfig":["search_path=public, pg_temp"],"crlf_count":5,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"98a97559965c2e0ff884d95155ab5d3a","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.validate_card_variant_game_consistency()","via":"trigger trg_card_variant_validate_game_consistency","class":"UNCLASSIFIED","depth":1,"body_md5":"331a5501cb28172a63d2c3202594beaa","cr_count":40,"language":"plpgsql","proconfig":null,"crlf_count":40,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"c1fe17587dfb3b0f6d7d5d690ca13636","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false}],"d_publications":[],"g_evt_ddl_only":true,"d_ownership_rls":[{"rls":true,"name":"card_edition_context_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_profile","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_profile_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_external_mapping","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_external_mapping_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_variant","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_variant_import_job","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_variant_import_row","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_admin_action_log","owner":"postgres","force_rls":false},{"rls":true,"name":"game","owner":"postgres","force_rls":false}],"d_event_triggers":[{"fn":"extensions.set_graphql_placeholder()","name":"issue_graphql_placeholder","tags":["DROP EXTENSION"],"event":"sql_drop","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"a2bc2d00b2cc2f5e8d2d6b8d73e2c360","fn_secdef":false,"fn_md5_raw":"a2bc2d00b2cc2f5e8d2d6b8d73e2c360","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_cron_access()","name":"issue_pg_cron_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"3a3917aad6ddd66182bf45b7490c3029","fn_secdef":false,"fn_md5_raw":"3a3917aad6ddd66182bf45b7490c3029","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_graphql_access()","name":"issue_pg_graphql_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"dd3f3e2bb94cff45ef24b9cecb6af1c8","fn_secdef":false,"fn_md5_raw":"dd3f3e2bb94cff45ef24b9cecb6af1c8","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_net_access()","name":"issue_pg_net_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"2ee4e6920eeba3068bcfa838105352e2","fn_secdef":false,"fn_md5_raw":"2ee4e6920eeba3068bcfa838105352e2","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.pgrst_ddl_watch()","name":"pgrst_ddl_watch","tags":null,"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"7f27b8118fea5c88b0164331292859e3","fn_secdef":false,"fn_md5_raw":"7f27b8118fea5c88b0164331292859e3","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.pgrst_drop_watch()","name":"pgrst_drop_watch","tags":null,"event":"sql_drop","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"bc09cc3003d66f91844af4cb05e203b7","fn_secdef":false,"fn_md5_raw":"bc09cc3003d66f91844af4cb05e203b7","fn_language":"plpgsql","fn_extension":null}],"g_no_concurrency":true,"g_p7_no_unresolved":true,"d_evt_catalog_count":6,"d_evt_unadjudicated":[],"d_p7_eol_normalized":["public.normalize_external_catalog_value(p_value text)"],"g_p7_all_classified":true,"g_p7_identity_pinned":true,"g_p7_writes_in_scope":true,"g_evt_all_adjudicated":true,"g_p7_closure_complete":true,"g_p7_search_path_safe":true,"d_evt_allowlist_absent":[],"d_p7_unqualified_calls":[{"name":"jsonb_typeof","caller":"internal.axis_identity_token","gate_scope":false,"resolution":"BUILTIN"},{"name":"array","caller":"internal.enforce_edition_context_mapping_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"array","caller":"internal.enforce_edition_context_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"and","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"if","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"in","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"jsonb_exists","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"jsonb_typeof","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.guard_edition_context_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_mapping_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_trait_active","gate_scope":true,"resolution":"KEYWORD"},{"name":"btrim","caller":"internal.normalize_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"coalesce","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"regexp_replace","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"},{"name":"trim","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"}],"d_p7_unqualified_writes":[],"g_p7_no_unqualified_dml":true,"g_evt_inventory_complete":true,"g_freeze_canonical_equal":true,"g_p7_lexically_supported":true,"d_p7_unresolved_qualified":[],"g_pg17_maintain_privilege":true,"g_no_sequences_touched_now":true,"g_p7_no_external_or_dynamic":true}}]
```

### B.4 S4 — E03P

```json
[{"e03p_precheck":{"d_session":{"checked_at":"2026-09-27T19:18:00.211255+00:00","backend_pid":3541667,"current_user":"postgres","lock_timeout":"0","server_version_num":"170006"},"gate_pass":true,"d_triggers":[{"fn":"internal.seal_edition_context_composition()","attrs":[],"tgname":"trg_cecp_seal","tgtype":5,"enabled":"O","relname":"card_edition_context_profile","deferrable":true,"initdeferred":true,"is_constraint":true},{"fn":"internal.enforce_edition_context_signature_write()","attrs":["traits_signature"],"tgname":"trg_cecp_signature_write","tgtype":19,"enabled":"O","relname":"card_edition_context_profile","deferrable":false,"initdeferred":false,"is_constraint":false},{"fn":"internal.guard_edition_context_composition_immutable()","attrs":[],"tgname":"trg_cecpt_immutable","tgtype":31,"enabled":"O","relname":"card_edition_context_profile_trait","deferrable":false,"initdeferred":false,"is_constraint":false},{"fn":"internal.guard_edition_context_trait_active()","attrs":[],"tgname":"trg_cecpt_trait_active","tgtype":7,"enabled":"O","relname":"card_edition_context_profile_trait","deferrable":false,"initdeferred":false,"is_constraint":false}],"d_constraints":[{"conname":"card_edition_context_profile_game_id_fkey","contype":"f","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"card_edition_context_profile_pkey","contype":"p","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_code_format","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_description_not_blank","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_display_order_positive","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_name_not_blank","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_signature_not_empty","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cecp_signature_shape","contype":"c","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"trg_cecp_seal","contype":"t","relname":"card_edition_context_profile","condeferred":true,"convalidated":true,"condeferrable":true},{"conname":"uq_cecp_game_code","contype":"u","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cecp_game_order","contype":"u","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cecp_id_game","contype":"u","relname":"card_edition_context_profile","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"fk_cecpt_profile","contype":"f","relname":"card_edition_context_profile_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"fk_cecpt_trait","contype":"f","relname":"card_edition_context_profile_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"pk_cecpt","contype":"p","relname":"card_edition_context_profile_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"card_edition_context_trait_game_id_fkey","contype":"f","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"card_edition_context_trait_pkey","contype":"p","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_code_family_prefix","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_code_format","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_description_not_blank","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_display_order_positive","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_family","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"ck_cect_name_not_blank","contype":"c","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cect_game_code","contype":"u","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cect_game_family_order","contype":"u","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false},{"conname":"uq_cect_id_game","contype":"u","relname":"card_edition_context_trait","condeferred":false,"convalidated":true,"condeferrable":false}],"g_s2_triggers":true,"d_error_tokens":[{"tok":"EDITION_CONTEXT_SIGNATURE_IMMUTABLE:","present":true,"proname":"enforce_edition_context_signature_write"},{"tok":"EDITION_CONTEXT_SIGNATURE_MISMATCH:","present":true,"proname":"enforce_edition_context_signature_write"},{"tok":"EDITION_CONTEXT_COMPOSITION_IMMUTABLE:","present":true,"proname":"guard_edition_context_composition_immutable"},{"tok":"EDITION_CONTEXT_TRAIT_INACTIVE:","present":true,"proname":"guard_edition_context_trait_active"},{"tok":"EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:","present":true,"proname":"seal_edition_context_composition"}],"d_nn_sequences":[],"d_function_pins":[{"fn":"internal.enforce_edition_context_signature_write()","pin":"caa2e4d40d8e4995e217d7284f9d6c3b","resolved":true,"body_md5_lf":"caa2e4d40d8e4995e217d7284f9d6c3b"},{"fn":"internal.guard_edition_context_composition_immutable()","pin":"cfdcb500bb1090cd44c0e73d94c3f72e","resolved":true,"body_md5_lf":"cfdcb500bb1090cd44c0e73d94c3f72e"},{"fn":"internal.guard_edition_context_trait_active()","pin":"68fb05f1c23db63a59611b0a12f79edd","resolved":true,"body_md5_lf":"68fb05f1c23db63a59611b0a12f79edd"},{"fn":"internal.seal_edition_context_composition()","pin":"6077409ac2b5de7f788076e3b4b3f0c0","resolved":true,"body_md5_lf":"6077409ac2b5de7f788076e3b4b3f0c0"}],"d_marker_counts":{"marker_trait":0,"marker_profile":0},"g_nn_rls_bypass":true,"g_nn_no_sequence":true,"g_s2_constraints":true,"d_signature_index":[{"ready":true,"valid":true,"unique":true,"columns":["game_id","traits_signature"],"relation":"card_edition_context_profile","predicate":"(traits_signature IS NOT NULL)"}],"g_s2_error_tokens":true,"d_nn_ownership_rls":[{"rls":true,"owner":"postgres","force_rls":false}],"d_seal_constraints":[{"conname":"trg_cecem_seal","contype":"t","relation":"card_edition_context_external_mapping","condeferred":true,"condeferrable":true},{"conname":"trg_cecp_seal","contype":"t","relation":"card_edition_context_profile","condeferred":true,"condeferrable":true}],"g_game_pokemon_one":true,"g_s2_function_pins":true,"g_marker_absent_now":true,"g_deferrable_only_seal":true,"g_no_other_triggers_l1":true,"g_seal_constraint_names_unique":true}}]
```

### B.5 S5 — E03T

Ver §3 (resposta integral do canal).

### B.6 S6 — E99

```json
[{"e99_postcheck":{"d_diff":[],"d_session":{"checked_at":"2026-09-27T19:21:40.226267+00:00","backend_pid":3542352,"lock_timeout":"0","db_role_setting_rows":9},"gate_pass":true,"d_canon_diff":[],"d_baseline_now":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"g_marker_absent":true,"g_baseline_equal":true,"g_keys_identical":true,"d_baseline_now_md5":"5c329d5e38a7e369cc100ab08953e1a7","g_captured_present":true,"g_captured_integrity":true,"g_no_open_txn_others":true,"g_lock_timeout_default":true,"g_freeze_canonical_equal":true,"g_role_setting_unchanged":true}}]
```

### B.7 S7 — L3 final

```json
[{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:21:21.638159+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T12:46:12.093029+00:00","wait_event_type":"Client","application_name":""},{"pid":3541705,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:24.548106+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541706,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:24.797107+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541707,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:25.314758+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541708,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:25.403044+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541709,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:25.443283+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541710,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:25.660595+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541711,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:18.680559+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541712,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:23.940342+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3541713,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T19:20:24.165339+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T19:20:26.859647+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T19:21:51.73575+00:00","locks_on_scope":[]}}]
```

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-E03T-LIVE-EXECUTION-01`, baseline `7934fe47`).** Execução LIVE do E03T em 7 chamadas (L1 → L3 → E00 → E03P → E03T → E99 → L3), fluxo normal, sem L3-D. `H283P` `pass=3/3`, `elapsed_ms=133`; E99 9/9, `d_diff = []`; L3 final limpa. Postcheck ÍNTEGRO; classificação **CONFORME (diagnóstico)**. Nenhum PASS contratual; 17/135. E03 não autorizado. Aguardando auditoria independente. FREEZE ATIVO. |
| 1.1 | **Fechamento documental (2026-09-27, `BATCH12-2830-P5-L1-E03T-PUBLICATION-CORRECTION-01`, baseline `7934fe47`), sem SQL e sem LIVE.** Só o campo Estado do cabeçalho: execução CONFORME (diagnóstico); auditoria técnica independente PASS; publicação pendente de commit/push por Fabrício; E03 não autorizado; 17/135; FREEZE ATIVO. Evidências, respostas brutas, Apêndices A/B e SQL submetido inalterados. |
