# LIVE — Lote L3 (E05): registro de execução

| Campo | Valor |
|---|---|
| **Documento** | Registro operacional da execução LIVE única e controlada do lote L3 (E05P + E05), Seção 2-QUATER da 2830 v7.0 |
| **Versão** | 1.1 |
| **Mandato** | BATCH12-2830-P5-L3-LIVE-EXECUTION-01 · HEAD `89736a60aa09fb332d4366dcd2757ba739f38812` · projeto Supabase `qjfutqujxrbzgrtkpgkg` · canal MCP `execute_sql` |
| **Resultado** | E05 `H283P` `pass=10/10`, 10 casos na ordem contratual, marcador `H2830_E8FD25ABE5D4449284E3AB87C96DD483`, `elapsed_ms=233`, CONTEXT `line 1302`; E99 9/9 (`d_diff=[]`, mapping 122 = 122); L3 final limpa; postcheck **ÍNTEGRO**; classificação proposta **CONFORME** |
| **Autorização de escrita** | Esgotada: uma única submissão do E05 (R1, rollback estrutural). Nenhum retry, nenhum outro envelope, nenhuma escrita persistente. |
| **Estado** | **CLOSED (v1.1):** parecer independente **PASS** — execução CONFORME, postcheck ÍNTEGRO, 2Q.1–2Q.10 **PASS** reconhecidos; cobertura automática vigente **54/135**; autorização LIVE do E05 esgotada; nenhuma repetição necessária. FREEZE ATIVO.<br>Histórico (v1.0): auditoria independente pendente; cobertura reconhecida 44/135 até o parecer; proposta 54/135. |

## 1. S0 — preflight local

| Item | Esperado | Obtido |
|---|---|---|
| HEAD | `89736a60…` | `89736a60aa09fb332d4366dcd2757ba739f38812` |
| Árvore / índice | limpos | `git status --porcelain` vazio; índice vazio; todo arquivo do harness com blob do índice = blob da árvore |
| E05P (100644) | `e5c27a56…` | `e5c27a569ab96937811b55bed4cfba39b85e9e1d` · md5 `f27cde7c67c649668cffa74a5ce66f27` · 17.539 B |
| E05 (100644) | `03a9ff02…` | `03a9ff029e38779338c308a847b4e3a26a773b44` · md5 `1625ada6431e2a6246e136c84a5b5559` · 79.252 B |
| static_check.py (100644) | `6a44ee7a…` | `6a44ee7aa12778f0e676c1598525c03e125dfc83` |
| Registro operacional L3 (100644) | `e52d68b9…` | `e52d68b9b5c9cf7bc83fadc1114d723acaf26a7e` |
| E00 (100644) | `a4dd8438…` | `a4dd84381b928727611a51147ba1a4c1d11b89ab` · md5 `45b6c35cca849ffbf49d22ec18e8283c` · 53.803 B |
| E99 base (100644) | `49a71ecb…` | `49a71ecb4525697858110ee71a3f61f5eee74a34` |
| Contrato 2830 (100644) | `b4647dcb…` | `b4647dcb59432405c8157e2733fd78678f35540e` |
| E03 / E03P / E03T / E04 / E04P | inalterados | `ef24a3be…` / `0fc2d83d…` / `9523bf23…` / `5b2a8b6f…` / `5cb4b893…` (índice = árvore; conferidos também pelo `static_check`) |
| L1 / L3 (runbook §3.1/§3.2) | md5 `0836c36a…` / `b7bc3700…` | idênticos (2.458 B / 1.526 B) |
| static_check | 444 · 88/79/6 · 65/94/7 · 58/54/6 | `444/444` · `88/88`, `79/79`, `6/6` · `65/65`, `94/94`, `7/7` · `58/58`, `54/54`, `6/6`, rc=0 |

## 2. Cronologia (7 chamadas `execute_sql`, uma por statement, conferência integral entre elas)

| Passo | Texto | `checked_at` (UTC) | pid | Resultado |
|---|---|---|---|---|
| S1 | L1 | 23:24:31.714067 | 3560679 | gravável (`transaction_read_only=off`, `in_recovery=false`), `statement_timeout=2min`, `lock_timeout=0`, PG 170006, `standard_conforming_strings=on`, 5 tabelas EC de `postgres`, `reads_all_stats=true` |
| S2 | L3 inicial | 23:24:48.063231 | — | `locks_on_scope=[]`; 14 sessões, todas `idle`/sem transação (nenhum `xact_start`) |
| S3 | E00 (`45b6c35c…`) | 23:27:35.927269 | 3560722 | **24/24 gates**, `gate_pass=true`, `d_canon_diff=[]`, `d_baseline_md5=5c329d5e38a7e369cc100ab08953e1a7`, `db_role_setting_rows=9` |
| S4 | E05P (`f27cde7c…`) | 23:28:48.987744 | 3560740 | **14/14 gates**, `gate_pass=true` |
| S5 | E05 (`1625ada6…`), submissão única | (erro terminal; o canal não devolve horário) | — | `H283P` `pass=10/10` (§4) |
| S6 | E99 preenchido (`00233aa6…`) | 23:34:06.499549 | 3560803 | **9/9**, `gate_pass=true`, `d_diff=[]`, `d_canon_diff=[]` |
| S7 | L3 final (despachada **só depois** da conferência do S6) | 23:34:17.865319 | — | `locks_on_scope=[]`; nenhuma sessão em transação; nenhum pid da rodada |

Ordem temporal: `L1 < L3 < E00 < E05P < S5 < E99 < L3 final` (S5 posicionado pela sequência de chamadas). S6 e S7 em chamadas separadas.

## 3. Gates críticos do E05P (S4)

| Gate | Evidência LIVE |
|---|---|
| `g_l3_triggers`, `g_no_other_triggers_l3` | 5 triggers esperados, `tgtype` 7/19/5/19/31, habilitados; `trg_cecem_seal` único constraint trigger deferrable/initially deferred; nenhum outro trigger nas 3 tabelas |
| `g_seal_constraint_names_unique`, `g_deferrable_only_seal_l3` | `trg_cecp_seal` e `trg_cecem_seal` únicos no schema `public`; nenhuma outra constraint deferrable nas 3 tabelas |
| `g_l3_constraints` | 15 constraints exigidas validadas + `uq_cecem_active_global` / `uq_cecem_active_scoped` válidos, com predicado e colunas esperados |
| `g_l3_error_tokens` | `EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:`, `…_REACTIVATION_FORBIDDEN:` (header) e `…_EMPTY_TOKEN:` (normalize) presentes |
| `g_l3_function_pins` | 5 funções da 2207 = pinos (`9e5fba31…`, `28084443…`, `ad0c472c…`, `15ea6245…`, `49a4ea4b…`) |
| `g_normalize_identity` | `public.normalize_external_catalog_value(text)`: `sql`, `s`, não SECURITY DEFINER, `search_path=""`, md5 LF `1fdc2e7ebe2297f8db85be4aad2e5d33` = pino |
| `g_n3_normalization` | pela função LIVE: `set-logo`→`SET-LOGO`, `Pokébola`→`POKEBOLA`, `BLUE  BORDER`→`BLUE BORDER`, `'   '`→`''` (4/4) |
| `g_l3_no_sequence`, `g_l3_rls_bypass` | nenhuma sequence nas 3 tabelas; as 3 de `postgres`, RLS sem FORCE |
| `g_marker_absent_now` | 0 trait e 0 mapping com `H2830` (em `normalized_token` **e** em `external_set_id`) |
| informativo `d_n3_live` | `literal_tokens=3`, `set_dp1=1` (chaves disjuntas das fixtures por construção; sem gate) |

Nenhum pino, predicado ou resultado foi ajustado.

## 4. S5 — resposta literal do E05

```
ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E05_SECAO2Q_MAPPING_HEADER pass=10/10 casos=2Q.1,2Q.2,2Q.3,2Q.4,2Q.5,2Q.6,2Q.7,2Q.8,2Q.9,2Q.10 marker=H2830_E8FD25ABE5D4449284E3AB87C96DD483 elapsed_ms=233
CONTEXT:  PL/pgSQL function inline_code_block line 1302 at RAISE
```

| Critério do mandato §5 | Resultado |
|---|---|
| SQLSTATE `H283P` / prefixo `H2830_ROLLBACK_PASS` | sim |
| `envelope=E05_SECAO2Q_MAPPING_HEADER` | sim |
| `pass=10/10` e 10 casos na ordem contratual | sim (`2Q.1…2Q.10`) |
| marcador `H2830_` + 32 hex maiúsculos | `H2830_E8FD25ABE5D4449284E3AB87C96DD483` |
| `elapsed_ms ≤ 60000` | 233 |
| CONTEXT = RAISE terminal do blob publicado | `line 1302`: `DO $h2830_e05$` na linha 60 do arquivo e RAISE `H283P` na linha 1361 ⇒ linha 1302 do corpo |
| P8 fail-closed | o preâmbulo `SET LOCAL lock_timeout='5s'` + asserção não disparou `H283F`; E99 `g_lock_timeout_default=true` |
| N-3 (guardas de colisão) | nenhum `H2830_FAIL … colisão` (2Q.8 e 2Q.10 concluídos) |
| Gate interno do envelope | `v_done = c_expected` e 7 sondas (senão `H283F` antes do terminal) |

Nenhum `H283F`, `55P03`, `57014` ou SQLSTATE inesperado. Resposta definida, íntegra e não truncada.

## 5. S6 — E99 submetido

Valores copiados **da saída do S3 desta rodada** (`d_baseline` literal do canal, 787 B, sem apóstrofo; `d_baseline_md5=5c329d5e…`, recalculado localmente sobre a serialização jsonb = declarado; `db_role_setting_rows=9`). Texto gerado por substituição única dos 3 marcadores do blob `49a71ecb…`; difere do base só nas linhas 56–58. md5 `00233aa60c571994f39df2df3faf05ea` · sha256 `3a3da896400279791f5c2a36c33477f053d6d3eb3b9131d4f68b8b155762bd8d` · 13.044 B. O texto coincide byte a byte com o E99 do L2 (mesmo estado sob FREEZE); a vinculação documental é com o E00 **desta** rodada (S3, pid 3560722, 23:27:35Z). Texto integral no Apêndice A.

## 6. Integridade e superfície de escrita

| Evidência | Resultado |
|---|---|
| E99 9/9 | `g_captured_present`, `g_captured_integrity`, `g_keys_identical`, `g_baseline_equal` (`d_diff=[]`), `g_freeze_canonical_equal` (`d_canon_diff=[]`), `g_marker_absent`, `g_no_open_txn_others`, `g_lock_timeout_default`, `g_role_setting_unchanged` — todos `true` |
| N-3: contagem de mapping | **E00 `mapping=122` = E99 `mapping=122`** (e `mapping_trait` 122 = 122, `mapping_null_signature` 0 = 0): as 3 linhas literais de 2Q.8, o mapping `dp1` de 2Q.10, os 7 M1 e as 7 sondas não persistiram. O gate de marcador sozinho não cobriria 2Q.8; a igualdade integral das contagens cobre |
| trait | 115 = 115 (7 fixtures `EVENT` desfeitas); `marker_trait` 0 |
| baseline depois | `d_baseline_now_md5 = 5c329d5e…` = E00 |
| L3 final | `locks_on_scope=[]`; nenhuma sessão em transação; pids da rodada (3560679, 3560722, 3560740, 3560803) ausentes |

Superfície R1 transitória, só nas 3 tabelas EC autorizadas: `card_edition_context_trait` 7 INSERT; `card_edition_context_external_mapping` 19 INSERT (7 M1 + 7 sondas + 3 literais N-3 + 1 tentativa recusada + 1 `dp1`) e 11 UPDATE só em M1 de fixture (`WHERE id = v_m1 AND normalized_token = v_tok`; 6 recusados, 5 aceitos); `card_edition_context_external_mapping_trait` 7 INSERT; 0 DELETE. Tudo desfeito pelo término em exceção. Nenhuma linha preexistente modificada (os UPDATEs só alcançam ids obtidos por `RETURNING INTO` com token-marcador; E99 `d_diff=[]`).

**Postcheck: ÍNTEGRO.**

## 7. Desvios e limitações

- Nenhum desvio de procedimento: 7 chamadas, uma por statement; S6 e S7 separadas; sem retry, sem SQL fora dos textos identificados, sem consulta exploratória.
- **Identidade do texto submetido (E00, E05P, E05):** transcritos dos arquivos com os blobs do §1; o canal não devolve hash do recebido. Evidência de identidade: o E05 aponta `line 1302`, exatamente o RAISE terminal do blob publicado; E00/E05P têm a forma e o número de gates esperados (24/14). Limitação idêntica à das execuções anteriores.
- `c_nil` (2Q.4): o guard BEFORE ROW recusou com `IDENTITY_IMMUTABLE` antes de qualquer FK (senão o caso teria falhado com `23503`).
- `g_no_open_txn_others` e a L3 medem outras sessões; a sessão do canal não mantém transação entre chamadas.

## 8. Classificação e proposta

**CONFORME** (critérios do §5 do mandato atendidos; postcheck ÍNTEGRO). Proposta, sujeita à auditoria independente: **PASS de 2Q.1, 2Q.2, 2Q.3, 2Q.4, 2Q.5, 2Q.6, 2Q.7, 2Q.8, 2Q.9, 2Q.10** e cobertura **54/135** (44 + 10). Até o parecer, a cobertura reconhecida permanece **44/135**. Não iniciar L4 nem outro lote. FREEZE ATIVO.

## 9. Fechamento (v1.1) — parecer independente e cobertura

| Item | Valor |
|---|---|
| Parecer independente | **PASS** (comunicado por Fabrício no mandato `BATCH12-2830-P5-L3-CLOSEOUT-AND-L4-IMPLEMENTATION-01`, baseline `89736a60`) |
| Classificação | **CONFORME** |
| Postcheck | **ÍNTEGRO** |
| Casos reconhecidos | 2Q.1, 2Q.2, 2Q.3, 2Q.4, 2Q.5, 2Q.6, 2Q.7, 2Q.8, 2Q.9, 2Q.10 — **PASS** (10) |
| Cobertura automática vigente | **54/135** (44 anteriores + 10) |
| Autorização LIVE do E05 | esgotada na submissão única do §4 |
| Repetição | nenhuma necessária |

As seções §1–§8 e os Apêndices A e B (E99 submetido e saídas integrais) são preservados sem alteração; o texto da v1.0 continua como registro da execução. Nada foi executado nesta revisão.

## Apêndice A — E99 submetido (texto integral)

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

## Apêndice B — saídas integrais

### B.1 L1 (S1)

```json
[
  {
    "l1_channel": {
      "checked_at": "2026-09-27T23:24:31.714067+00:00",
      "backend_pid": 3560679,
      "in_recovery": false,
      "current_user": "postgres",
      "is_superuser": false,
      "lock_timeout": "0",
      "session_user": "postgres",
      "ec_table_owner": {
        "card_edition_context_trait": "postgres",
        "card_edition_context_profile": "postgres",
        "card_edition_context_profile_trait": "postgres",
        "card_edition_context_external_mapping": "postgres",
        "card_edition_context_external_mapping_trait": "postgres"
      },
      "reads_all_stats": true,
      "application_name": "mgmt-api",
      "statement_timeout": "2min",
      "server_version_num": "170006",
      "transaction_read_only": "off",
      "visible_foreign_sessions": 2,
      "activity_rows_state_hidden": 0,
      "standard_conforming_strings": "on",
      "default_transaction_read_only": "off",
      "idle_in_transaction_session_timeout": "0"
    }
  }
]
```

### B.2 L3 inicial (S2)

```json
[
  {
    "l3_concurrency": {
      "sessions": [
        {
          "pid": 2819340,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-21T01:53:15.772737+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 2819351,
          "state": "idle",
          "usename": "supabase_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:24:20.009976+00:00",
          "wait_event_type": "Client",
          "application_name": "postgres_exporter"
        },
        {
          "pid": 2867551,
          "state": "idle",
          "usename": "supabase_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T12:46:12.093029+00:00",
          "wait_event_type": "Client",
          "application_name": ""
        },
        {
          "pid": 3559279,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:12:00.77489+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3559930,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:15:01.790493+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3559932,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:15:02.417615+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3559958,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:17:00.607738+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3559959,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:17:00.691842+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3559999,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:20:01.601615+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560000,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:20:01.738662+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560649,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:22:01.455214+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560650,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:22:01.613622+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 2819328,
          "state": null,
          "usename": "supabase_admin",
          "wait_event": "Extension",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "pg_cron launcher",
          "state_change": null,
          "wait_event_type": "Extension",
          "application_name": "pg_cron scheduler"
        },
        {
          "pid": 2819327,
          "state": "idle",
          "usename": "supabase_admin",
          "wait_event": "Extension",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "pg_net 0.20.4 worker",
          "state_change": "2026-09-27T23:22:04.653037+00:00",
          "wait_event_type": "Extension",
          "application_name": "pg_net 0.20.4"
        }
      ],
      "checked_at": "2026-09-27T23:24:48.063231+00:00",
      "locks_on_scope": []
    }
  }
]
```

### B.3 E00 (S3)

```json
[
  {
    "e00_precheck": {
      "d_objects": {
        "indexes_D": 5,
        "indexes_1x": 4,
        "game_pokemon": 1,
        "source_tcgdex": 1,
        "constraints_1x": 7,
        "roles_anon_authenticated": 2
      },
      "d_session": {
        "checked_at": "2026-09-27T23:27:35.927269+00:00",
        "backend_pid": 3560722,
        "current_user": "postgres",
        "is_superuser": false,
        "lock_timeout": "0",
        "statement_timeout": "2min",
        "server_version_num": "170006",
        "db_role_setting_rows": 9,
        "session_replication_role": "origin"
      },
      "gate_pass": true,
      "d_baseline": {
        "jobs": 145,
        "trait": 115,
        "lineage": {
          "matched": 1129,
          "resulting": 23955
        },
        "mapping": 122,
        "profile": 144,
        "action_log": 1352,
        "card_variant": 24893,
        "marker_trait": 0,
        "staging_rows": 26127,
        "mapping_trait": 122,
        "profile_trait": 196,
        "jobs_by_status": {
          "FAILED": 8,
          "STAGED": 63,
          "CANCELLED": 3,
          "COMPLETED": 71
        },
        "jobs_in_flight": 0,
        "marker_mapping": 0,
        "marker_profile": 0,
        "staging_status": {
          "VALID/PENDING": 415,
          "VALID/INSERTED": 23240,
          "INVALID/PENDING": 6,
          "VALID/UNCHANGED": 717,
          "INVALID/UNCHANGED": 80,
          "NEEDS_REVIEW/PENDING": 1656,
          "NEEDS_REVIEW/UNCHANGED": 13
        },
        "jobs_max_upd_utc": "2026-09-19T00:48:41.964146Z",
        "staging_max_upd_utc": "2026-09-20T19:57:04.771758Z",
        "operational_tristate": {
          "A": 0,
          "N": 550,
          "U": 1092
        },
        "cancelled_without_key": {
          "total": 847,
          "valid_pending": 415
        },
        "mapping_null_signature": 0,
        "card_variant_ec_nonnull": 0
      },
      "d_p7_rules": [],
      "g_no_rules": true,
      "d_p7_writes": [
        {
          "target": "public.card_edition_context_profile",
          "writer": "internal.seal_edition_context_composition",
          "gate_scope": true,
          "target_exists": true
        },
        {
          "target": "public.card_edition_context_external_mapping",
          "writer": "internal.seal_edition_context_external_mapping",
          "gate_scope": true,
          "target_exists": true
        }
      ],
      "d_sequences": [],
      "g_objects_d": true,
      "g_p7_no_ddl": true,
      "d_canon_diff": [],
      "g_no_residue": true,
      "g_objects_1x": true,
      "g_rls_bypass": true,
      "g_roles_1_12": true,
      "d_concurrency": {
        "other_sessions_in_txn": 0
      },
      "g_game_source": true,
      "d_baseline_md5": "5c329d5e38a7e369cc100ab08953e1a7",
      "d_p7_functions": [
        {
          "fn": "internal.enforce_edition_context_mapping_header()",
          "via": "trigger trg_cecem_header",
          "class": "GUARD",
          "depth": 1,
          "body_md5": "9e5fba31721c5e84212bd2116d3fa214",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": "9e5fba31721c5e84212bd2116d3fa214",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.enforce_edition_context_mapping_signature_write()",
          "via": "trigger trg_cecem_signature_write",
          "class": "GUARD",
          "depth": 1,
          "body_md5": "28084443cf6f32f9336d470ca16b7e72",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": "28084443cf6f32f9336d470ca16b7e72",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.enforce_edition_context_signature_write()",
          "via": "trigger trg_cecp_signature_write",
          "class": "GUARD",
          "depth": 1,
          "body_md5": "caa2e4d40d8e4995e217d7284f9d6c3b",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_profile",
          "body_md5_lf": "caa2e4d40d8e4995e217d7284f9d6c3b",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.guard_edition_context_composition_immutable()",
          "via": "trigger trg_cecpt_immutable",
          "class": "GUARD",
          "depth": 1,
          "body_md5": "cfdcb500bb1090cd44c0e73d94c3f72e",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_profile_trait",
          "body_md5_lf": "cfdcb500bb1090cd44c0e73d94c3f72e",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.guard_edition_context_mapping_composition_immutable()",
          "via": "trigger trg_cecemt_immutable",
          "class": "GUARD",
          "depth": 1,
          "body_md5": "ad0c472cfa82c71ee955d9b653755bdc",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping_trait",
          "body_md5_lf": "ad0c472cfa82c71ee955d9b653755bdc",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.guard_edition_context_trait_active()",
          "via": "trigger trg_cecpt_trait_active",
          "class": "GUARD",
          "depth": 1,
          "body_md5": "68fb05f1c23db63a59611b0a12f79edd",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_profile_trait",
          "body_md5_lf": "68fb05f1c23db63a59611b0a12f79edd",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.normalize_edition_context_external_mapping()",
          "via": "trigger trg_cecem_normalize",
          "class": "NORMALIZE",
          "depth": 1,
          "body_md5": "15ea6245b8b8ce2173abb3d6b72c6736",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": "15ea6245b8b8ce2173abb3d6b72c6736",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "public.normalize_external_catalog_value(p_value text)",
          "via": "trigger trg_cecem_normalize",
          "class": "PURE",
          "depth": 2,
          "body_md5": "81361bb8f52ce142803d69c2b3028ae8",
          "cr_count": 2,
          "language": "sql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 2,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": "1fdc2e7ebe2297f8db85be4aad2e5d33",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "extensions.unaccent(regdictionary, text)",
          "via": "trigger trg_cecem_normalize",
          "class": "PURE_EXT",
          "depth": 3,
          "body_md5": null,
          "cr_count": 0,
          "language": "c",
          "proconfig": null,
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": null,
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "extensions.unaccent(text)",
          "via": "trigger trg_cecem_normalize",
          "class": "PURE_EXT",
          "depth": 3,
          "body_md5": null,
          "cr_count": 0,
          "language": "c",
          "proconfig": null,
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": null,
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.seal_edition_context_composition()",
          "via": "trigger trg_cecp_seal",
          "class": "SEAL",
          "depth": 1,
          "body_md5": "6077409ac2b5de7f788076e3b4b3f0c0",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_profile",
          "body_md5_lf": "6077409ac2b5de7f788076e3b4b3f0c0",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.seal_edition_context_external_mapping()",
          "via": "trigger trg_cecem_seal",
          "class": "SEAL",
          "depth": 1,
          "body_md5": "49a4ea4b34ccf06a4efdcf06270c52eb",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": true,
          "root_table": "card_edition_context_external_mapping",
          "body_md5_lf": "49a4ea4b34ccf06a4efdcf06270c52eb",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.axis_identity_token(p_data jsonb, p_key text)",
          "via": "index uq_cvir_row_identity",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "18682dce935281b0a4437628a6e8309a",
          "cr_count": 0,
          "language": "sql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": false,
          "root_table": "catalog_variant_import_row",
          "body_md5_lf": "18682dce935281b0a4437628a6e8309a",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.enforce_card_variant_edition_context_profile_game()",
          "via": "trigger trg_card_variant_edition_context_profile_game",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "21e3a4c08989545351e2757c59fc77c4",
          "cr_count": 36,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 36,
          "gate_scope": false,
          "root_table": "card_variant",
          "body_md5_lf": "27c1845dea596dd9b46413019799ab33",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.enforce_card_variant_printing_profile_game()",
          "via": "trigger trg_card_variant_printing_profile_game",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "e847a065643a7836085eefc8116bb9c5",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 0,
          "gate_scope": false,
          "root_table": "card_variant",
          "body_md5_lf": "e847a065643a7836085eefc8116bb9c5",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "internal.guard_cvir_normalized_shape()",
          "via": "trigger trg_cvir_normalized_shape",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "1cebffee8afb213481342a9d402eb462",
          "cr_count": 62,
          "language": "plpgsql",
          "proconfig": [
            "search_path=\"\""
          ],
          "crlf_count": 62,
          "gate_scope": false,
          "root_table": "catalog_variant_import_row",
          "body_md5_lf": "f5bcae1bd83a6880c63519b31f36c5c4",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": false,
          "unsupported_lexeme": false
        },
        {
          "fn": "public.normalize_catalog_variant_import_job()",
          "via": "trigger trg_catalog_variant_import_job_normalize",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "c01adb02245bd5a305e8f8987a30f1c1",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": null,
          "crlf_count": 0,
          "gate_scope": false,
          "root_table": "catalog_variant_import_job",
          "body_md5_lf": "c01adb02245bd5a305e8f8987a30f1c1",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": true,
          "unsupported_lexeme": false
        },
        {
          "fn": "public.normalize_catalog_variant_import_row()",
          "via": "trigger trg_catalog_variant_import_row_normalize",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "7ae9bd52e030b13c3a241debda491a99",
          "cr_count": 0,
          "language": "plpgsql",
          "proconfig": null,
          "crlf_count": 0,
          "gate_scope": false,
          "root_table": "catalog_variant_import_row",
          "body_md5_lf": "7ae9bd52e030b13c3a241debda491a99",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": true,
          "unsupported_lexeme": false
        },
        {
          "fn": "public.set_updated_at()",
          "via": "trigger trg_card_variant_set_updated_at",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "7933f81decf127af71628126ef109c81",
          "cr_count": 5,
          "language": "plpgsql",
          "proconfig": [
            "search_path=public, pg_temp"
          ],
          "crlf_count": 5,
          "gate_scope": false,
          "root_table": "card_variant",
          "body_md5_lf": "98a97559965c2e0ff884d95155ab5d3a",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": true,
          "unsupported_lexeme": false
        },
        {
          "fn": "public.validate_card_variant_game_consistency()",
          "via": "trigger trg_card_variant_validate_game_consistency",
          "class": "UNCLASSIFIED",
          "depth": 1,
          "body_md5": "331a5501cb28172a63d2c3202594beaa",
          "cr_count": 40,
          "language": "plpgsql",
          "proconfig": null,
          "crlf_count": 40,
          "gate_scope": false,
          "root_table": "card_variant",
          "body_md5_lf": "c1fe17587dfb3b0f6d7d5d690ca13636",
          "dynamic_sql": false,
          "ddl_statement": false,
          "external_signal": false,
          "search_path_unsafe": true,
          "unsupported_lexeme": false
        }
      ],
      "d_publications": [],
      "g_evt_ddl_only": true,
      "d_ownership_rls": [
        {
          "rls": true,
          "name": "card_edition_context_trait",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "card_edition_context_profile",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "card_edition_context_profile_trait",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "card_edition_context_external_mapping",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "card_edition_context_external_mapping_trait",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "card_variant",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "catalog_variant_import_job",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "catalog_variant_import_row",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "catalog_admin_action_log",
          "owner": "postgres",
          "force_rls": false
        },
        {
          "rls": true,
          "name": "game",
          "owner": "postgres",
          "force_rls": false
        }
      ],
      "d_event_triggers": [
        {
          "fn": "extensions.set_graphql_placeholder()",
          "name": "issue_graphql_placeholder",
          "tags": [
            "DROP EXTENSION"
          ],
          "event": "sql_drop",
          "owner": "supabase_admin",
          "enabled": "O",
          "fn_owner": "supabase_admin",
          "fn_config": [
            "search_path=\"\""
          ],
          "fn_md5_lf": "a2bc2d00b2cc2f5e8d2d6b8d73e2c360",
          "fn_secdef": false,
          "fn_md5_raw": "a2bc2d00b2cc2f5e8d2d6b8d73e2c360",
          "fn_language": "plpgsql",
          "fn_extension": null
        },
        {
          "fn": "extensions.grant_pg_cron_access()",
          "name": "issue_pg_cron_access",
          "tags": [
            "CREATE EXTENSION"
          ],
          "event": "ddl_command_end",
          "owner": "supabase_admin",
          "enabled": "O",
          "fn_owner": "supabase_admin",
          "fn_config": [
            "search_path=\"\""
          ],
          "fn_md5_lf": "3a3917aad6ddd66182bf45b7490c3029",
          "fn_secdef": false,
          "fn_md5_raw": "3a3917aad6ddd66182bf45b7490c3029",
          "fn_language": "plpgsql",
          "fn_extension": null
        },
        {
          "fn": "extensions.grant_pg_graphql_access()",
          "name": "issue_pg_graphql_access",
          "tags": [
            "CREATE EXTENSION"
          ],
          "event": "ddl_command_end",
          "owner": "supabase_admin",
          "enabled": "O",
          "fn_owner": "supabase_admin",
          "fn_config": [
            "search_path=\"\""
          ],
          "fn_md5_lf": "dd3f3e2bb94cff45ef24b9cecb6af1c8",
          "fn_secdef": false,
          "fn_md5_raw": "dd3f3e2bb94cff45ef24b9cecb6af1c8",
          "fn_language": "plpgsql",
          "fn_extension": null
        },
        {
          "fn": "extensions.grant_pg_net_access()",
          "name": "issue_pg_net_access",
          "tags": [
            "CREATE EXTENSION"
          ],
          "event": "ddl_command_end",
          "owner": "supabase_admin",
          "enabled": "O",
          "fn_owner": "supabase_admin",
          "fn_config": [
            "search_path=\"\""
          ],
          "fn_md5_lf": "2ee4e6920eeba3068bcfa838105352e2",
          "fn_secdef": false,
          "fn_md5_raw": "2ee4e6920eeba3068bcfa838105352e2",
          "fn_language": "plpgsql",
          "fn_extension": null
        },
        {
          "fn": "extensions.pgrst_ddl_watch()",
          "name": "pgrst_ddl_watch",
          "tags": null,
          "event": "ddl_command_end",
          "owner": "supabase_admin",
          "enabled": "O",
          "fn_owner": "supabase_admin",
          "fn_config": [
            "search_path=\"\""
          ],
          "fn_md5_lf": "7f27b8118fea5c88b0164331292859e3",
          "fn_secdef": false,
          "fn_md5_raw": "7f27b8118fea5c88b0164331292859e3",
          "fn_language": "plpgsql",
          "fn_extension": null
        },
        {
          "fn": "extensions.pgrst_drop_watch()",
          "name": "pgrst_drop_watch",
          "tags": null,
          "event": "sql_drop",
          "owner": "supabase_admin",
          "enabled": "O",
          "fn_owner": "supabase_admin",
          "fn_config": [
            "search_path=\"\""
          ],
          "fn_md5_lf": "bc09cc3003d66f91844af4cb05e203b7",
          "fn_secdef": false,
          "fn_md5_raw": "bc09cc3003d66f91844af4cb05e203b7",
          "fn_language": "plpgsql",
          "fn_extension": null
        }
      ],
      "g_no_concurrency": true,
      "g_p7_no_unresolved": true,
      "d_evt_catalog_count": 6,
      "d_evt_unadjudicated": [],
      "d_p7_eol_normalized": [
        "public.normalize_external_catalog_value(p_value text)"
      ],
      "g_p7_all_classified": true,
      "g_p7_identity_pinned": true,
      "g_p7_writes_in_scope": true,
      "g_evt_all_adjudicated": true,
      "g_p7_closure_complete": true,
      "g_p7_search_path_safe": true,
      "d_evt_allowlist_absent": [],
      "d_p7_unqualified_calls": [
        {
          "name": "jsonb_typeof",
          "caller": "internal.axis_identity_token",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "array",
          "caller": "internal.enforce_edition_context_mapping_signature_write",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "array",
          "caller": "internal.enforce_edition_context_signature_write",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "and",
          "caller": "internal.guard_cvir_normalized_shape",
          "gate_scope": false,
          "resolution": "KEYWORD"
        },
        {
          "name": "if",
          "caller": "internal.guard_cvir_normalized_shape",
          "gate_scope": false,
          "resolution": "KEYWORD"
        },
        {
          "name": "in",
          "caller": "internal.guard_cvir_normalized_shape",
          "gate_scope": false,
          "resolution": "KEYWORD"
        },
        {
          "name": "jsonb_exists",
          "caller": "internal.guard_cvir_normalized_shape",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "jsonb_typeof",
          "caller": "internal.guard_cvir_normalized_shape",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "exists",
          "caller": "internal.guard_edition_context_composition_immutable",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "exists",
          "caller": "internal.guard_edition_context_mapping_composition_immutable",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "exists",
          "caller": "internal.guard_edition_context_trait_active",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "btrim",
          "caller": "internal.normalize_edition_context_external_mapping",
          "gate_scope": true,
          "resolution": "BUILTIN"
        },
        {
          "name": "array",
          "caller": "internal.seal_edition_context_composition",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "cardinality",
          "caller": "internal.seal_edition_context_composition",
          "gate_scope": true,
          "resolution": "BUILTIN"
        },
        {
          "name": "exists",
          "caller": "internal.seal_edition_context_composition",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "now",
          "caller": "internal.seal_edition_context_composition",
          "gate_scope": true,
          "resolution": "BUILTIN"
        },
        {
          "name": "array",
          "caller": "internal.seal_edition_context_external_mapping",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "cardinality",
          "caller": "internal.seal_edition_context_external_mapping",
          "gate_scope": true,
          "resolution": "BUILTIN"
        },
        {
          "name": "exists",
          "caller": "internal.seal_edition_context_external_mapping",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "now",
          "caller": "internal.seal_edition_context_external_mapping",
          "gate_scope": true,
          "resolution": "BUILTIN"
        },
        {
          "name": "btrim",
          "caller": "public.normalize_catalog_variant_import_job",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "nullif",
          "caller": "public.normalize_catalog_variant_import_job",
          "gate_scope": false,
          "resolution": "KEYWORD"
        },
        {
          "name": "upper",
          "caller": "public.normalize_catalog_variant_import_job",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "btrim",
          "caller": "public.normalize_catalog_variant_import_row",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "nullif",
          "caller": "public.normalize_catalog_variant_import_row",
          "gate_scope": false,
          "resolution": "KEYWORD"
        },
        {
          "name": "upper",
          "caller": "public.normalize_catalog_variant_import_row",
          "gate_scope": false,
          "resolution": "BUILTIN"
        },
        {
          "name": "coalesce",
          "caller": "public.normalize_external_catalog_value",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "regexp_replace",
          "caller": "public.normalize_external_catalog_value",
          "gate_scope": true,
          "resolution": "BUILTIN"
        },
        {
          "name": "trim",
          "caller": "public.normalize_external_catalog_value",
          "gate_scope": true,
          "resolution": "KEYWORD"
        },
        {
          "name": "upper",
          "caller": "public.normalize_external_catalog_value",
          "gate_scope": true,
          "resolution": "BUILTIN"
        }
      ],
      "d_p7_unqualified_writes": [],
      "g_p7_no_unqualified_dml": true,
      "g_evt_inventory_complete": true,
      "g_freeze_canonical_equal": true,
      "g_p7_lexically_supported": true,
      "d_p7_unresolved_qualified": [],
      "g_pg17_maintain_privilege": true,
      "g_no_sequences_touched_now": true,
      "g_p7_no_external_or_dynamic": true
    }
  }
]
```

### B.4 E05P (S4)

```json
[
  {
    "e05p_precheck": {
      "d_n3_live": {
        "set_dp1": 1,
        "literal_tokens": 3
      },
      "d_session": {
        "checked_at": "2026-09-27T23:28:48.987744+00:00",
        "backend_pid": 3560740,
        "current_user": "postgres",
        "lock_timeout": "0",
        "server_version_num": "170006"
      },
      "gate_pass": true,
      "d_triggers": [
        {
          "fn": "internal.enforce_edition_context_mapping_header()",
          "attrs": [],
          "tgname": "trg_cecem_header",
          "tgtype": 19,
          "enabled": "O",
          "relname": "card_edition_context_external_mapping",
          "deferrable": false,
          "initdeferred": false,
          "is_constraint": false
        },
        {
          "fn": "internal.normalize_edition_context_external_mapping()",
          "attrs": [],
          "tgname": "trg_cecem_normalize",
          "tgtype": 7,
          "enabled": "O",
          "relname": "card_edition_context_external_mapping",
          "deferrable": false,
          "initdeferred": false,
          "is_constraint": false
        },
        {
          "fn": "internal.seal_edition_context_external_mapping()",
          "attrs": [],
          "tgname": "trg_cecem_seal",
          "tgtype": 5,
          "enabled": "O",
          "relname": "card_edition_context_external_mapping",
          "deferrable": true,
          "initdeferred": true,
          "is_constraint": true
        },
        {
          "fn": "internal.enforce_edition_context_mapping_signature_write()",
          "attrs": [
            "traits_signature"
          ],
          "tgname": "trg_cecem_signature_write",
          "tgtype": 19,
          "enabled": "O",
          "relname": "card_edition_context_external_mapping",
          "deferrable": false,
          "initdeferred": false,
          "is_constraint": false
        },
        {
          "fn": "internal.guard_edition_context_mapping_composition_immutable()",
          "attrs": [],
          "tgname": "trg_cecemt_immutable",
          "tgtype": 31,
          "enabled": "O",
          "relname": "card_edition_context_external_mapping_trait",
          "deferrable": false,
          "initdeferred": false,
          "is_constraint": false
        }
      ],
      "d_constraints": [
        {
          "conname": "card_edition_context_external_mapping_asset_source_id_fkey",
          "contype": "f",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "card_edition_context_external_mapping_game_id_fkey",
          "contype": "f",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "card_edition_context_external_mapping_pkey",
          "contype": "p",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cecem_external_set_not_blank",
          "contype": "c",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cecem_raw_field",
          "contype": "c",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cecem_signature_not_empty",
          "contype": "c",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cecem_signature_shape",
          "contype": "c",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cecem_token_not_blank",
          "contype": "c",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "trg_cecem_seal",
          "contype": "t",
          "relname": "card_edition_context_external_mapping",
          "condeferred": true,
          "convalidated": true,
          "condeferrable": true
        },
        {
          "conname": "uq_cecem_id_game",
          "contype": "u",
          "relname": "card_edition_context_external_mapping",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "fk_cecemt_mapping",
          "contype": "f",
          "relname": "card_edition_context_external_mapping_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "fk_cecemt_trait",
          "contype": "f",
          "relname": "card_edition_context_external_mapping_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "pk_cecemt",
          "contype": "p",
          "relname": "card_edition_context_external_mapping_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "card_edition_context_trait_game_id_fkey",
          "contype": "f",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "card_edition_context_trait_pkey",
          "contype": "p",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cect_code_family_prefix",
          "contype": "c",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cect_code_format",
          "contype": "c",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cect_description_not_blank",
          "contype": "c",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cect_display_order_positive",
          "contype": "c",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cect_family",
          "contype": "c",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "ck_cect_name_not_blank",
          "contype": "c",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "uq_cect_game_code",
          "contype": "u",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "uq_cect_game_family_order",
          "contype": "u",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        },
        {
          "conname": "uq_cect_id_game",
          "contype": "u",
          "relname": "card_edition_context_trait",
          "condeferred": false,
          "convalidated": true,
          "condeferrable": false
        }
      ],
      "g_l3_triggers": true,
      "d_error_tokens": [
        {
          "tok": "EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:",
          "present": true,
          "proname": "enforce_edition_context_mapping_header"
        },
        {
          "tok": "EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN:",
          "present": true,
          "proname": "enforce_edition_context_mapping_header"
        },
        {
          "tok": "EDITION_CONTEXT_MAPPING_EMPTY_TOKEN:",
          "present": true,
          "proname": "normalize_edition_context_external_mapping"
        }
      ],
      "d_l3_sequences": [],
      "d_function_pins": [
        {
          "fn": "internal.enforce_edition_context_mapping_header()",
          "pin": "9e5fba31721c5e84212bd2116d3fa214",
          "resolved": true,
          "body_md5_lf": "9e5fba31721c5e84212bd2116d3fa214"
        },
        {
          "fn": "internal.enforce_edition_context_mapping_signature_write()",
          "pin": "28084443cf6f32f9336d470ca16b7e72",
          "resolved": true,
          "body_md5_lf": "28084443cf6f32f9336d470ca16b7e72"
        },
        {
          "fn": "internal.guard_edition_context_mapping_composition_immutable()",
          "pin": "ad0c472cfa82c71ee955d9b653755bdc",
          "resolved": true,
          "body_md5_lf": "ad0c472cfa82c71ee955d9b653755bdc"
        },
        {
          "fn": "internal.normalize_edition_context_external_mapping()",
          "pin": "15ea6245b8b8ce2173abb3d6b72c6736",
          "resolved": true,
          "body_md5_lf": "15ea6245b8b8ce2173abb3d6b72c6736"
        },
        {
          "fn": "internal.seal_edition_context_external_mapping()",
          "pin": "49a4ea4b34ccf06a4efdcf06270c52eb",
          "resolved": true,
          "body_md5_lf": "49a4ea4b34ccf06a4efdcf06270c52eb"
        }
      ],
      "d_marker_counts": {
        "marker_trait": 0,
        "marker_mapping": 0
      },
      "g_l3_rls_bypass": true,
      "d_active_indexes": [
        {
          "index": "uq_cecem_active_global",
          "ready": true,
          "valid": true,
          "unique": true,
          "columns": [
            "game_id",
            "asset_source_id",
            "raw_field",
            "normalized_token"
          ],
          "relation": "card_edition_context_external_mapping",
          "predicate_np": "external_set_id IS NULL AND is_active"
        },
        {
          "index": "uq_cecem_active_scoped",
          "ready": true,
          "valid": true,
          "unique": true,
          "columns": [
            "game_id",
            "asset_source_id",
            "external_set_id",
            "raw_field",
            "normalized_token"
          ],
          "relation": "card_edition_context_external_mapping",
          "predicate_np": "external_set_id IS NOT NULL AND is_active"
        }
      ],
      "g_l3_constraints": true,
      "g_l3_no_sequence": true,
      "g_l3_error_tokens": true,
      "d_l3_ownership_rls": [
        {
          "rls": true,
          "owner": "postgres",
          "relname": "card_edition_context_external_mapping",
          "force_rls": false
        },
        {
          "rls": true,
          "owner": "postgres",
          "relname": "card_edition_context_external_mapping_trait",
          "force_rls": false
        },
        {
          "rls": true,
          "owner": "postgres",
          "relname": "card_edition_context_trait",
          "force_rls": false
        }
      ],
      "d_n3_normalization": [
        {
          "got": "",
          "raw": "   ",
          "expected": ""
        },
        {
          "got": "BLUE BORDER",
          "raw": "BLUE  BORDER",
          "expected": "BLUE BORDER"
        },
        {
          "got": "POKEBOLA",
          "raw": "Pokébola",
          "expected": "POKEBOLA"
        },
        {
          "got": "SET-LOGO",
          "raw": "set-logo",
          "expected": "SET-LOGO"
        }
      ],
      "d_seal_constraints": [
        {
          "conname": "trg_cecem_seal",
          "contype": "t",
          "relation": "card_edition_context_external_mapping",
          "condeferred": true,
          "condeferrable": true
        },
        {
          "conname": "trg_cecp_seal",
          "contype": "t",
          "relation": "card_edition_context_profile",
          "condeferred": true,
          "condeferrable": true
        }
      ],
      "g_game_pokemon_one": true,
      "g_l3_function_pins": true,
      "g_n3_normalization": true,
      "g_marker_absent_now": true,
      "g_source_tcgdex_one": true,
      "d_normalize_identity": [
        {
          "cfg": [
            "search_path=\"\""
          ],
          "vol": "s",
          "lang": "sql",
          "secdef": false,
          "body_md5_lf": "1fdc2e7ebe2297f8db85be4aad2e5d33"
        }
      ],
      "g_normalize_identity": true,
      "g_no_other_triggers_l3": true,
      "g_deferrable_only_seal_l3": true,
      "g_seal_constraint_names_unique": true
    }
  }
]
```

### B.5 E99 (S6)

```json
[
  {
    "e99_postcheck": {
      "d_diff": [],
      "d_session": {
        "checked_at": "2026-09-27T23:34:06.499549+00:00",
        "backend_pid": 3560803,
        "lock_timeout": "0",
        "db_role_setting_rows": 9
      },
      "gate_pass": true,
      "d_canon_diff": [],
      "d_baseline_now": {
        "jobs": 145,
        "trait": 115,
        "lineage": {
          "matched": 1129,
          "resulting": 23955
        },
        "mapping": 122,
        "profile": 144,
        "action_log": 1352,
        "card_variant": 24893,
        "marker_trait": 0,
        "staging_rows": 26127,
        "mapping_trait": 122,
        "profile_trait": 196,
        "jobs_by_status": {
          "FAILED": 8,
          "STAGED": 63,
          "CANCELLED": 3,
          "COMPLETED": 71
        },
        "jobs_in_flight": 0,
        "marker_mapping": 0,
        "marker_profile": 0,
        "staging_status": {
          "VALID/PENDING": 415,
          "VALID/INSERTED": 23240,
          "INVALID/PENDING": 6,
          "VALID/UNCHANGED": 717,
          "INVALID/UNCHANGED": 80,
          "NEEDS_REVIEW/PENDING": 1656,
          "NEEDS_REVIEW/UNCHANGED": 13
        },
        "jobs_max_upd_utc": "2026-09-19T00:48:41.964146Z",
        "staging_max_upd_utc": "2026-09-20T19:57:04.771758Z",
        "operational_tristate": {
          "A": 0,
          "N": 550,
          "U": 1092
        },
        "cancelled_without_key": {
          "total": 847,
          "valid_pending": 415
        },
        "mapping_null_signature": 0,
        "card_variant_ec_nonnull": 0
      },
      "g_marker_absent": true,
      "g_baseline_equal": true,
      "g_keys_identical": true,
      "d_baseline_now_md5": "5c329d5e38a7e369cc100ab08953e1a7",
      "g_captured_present": true,
      "g_captured_integrity": true,
      "g_no_open_txn_others": true,
      "g_lock_timeout_default": true,
      "g_freeze_canonical_equal": true,
      "g_role_setting_unchanged": true
    }
  }
]
```

### B.6 L3 final (S7)

```json
[
  {
    "l3_concurrency": {
      "sessions": [
        {
          "pid": 2819340,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-21T01:53:15.772737+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 2819351,
          "state": "idle",
          "usename": "supabase_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:33:20.015364+00:00",
          "wait_event_type": "Client",
          "application_name": "postgres_exporter"
        },
        {
          "pid": 2867551,
          "state": "idle",
          "usename": "supabase_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T12:46:12.093029+00:00",
          "wait_event_type": "Client",
          "application_name": ""
        },
        {
          "pid": 3560650,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:22:01.613622+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560688,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:25:01.67246+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560690,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:25:02.195002+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560714,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:27:00.792498+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560715,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:27:00.902898+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560754,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:30:01.745224+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560755,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:30:01.861638+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560776,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:32:01.375883+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3560778,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-27T23:32:01.543408+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 2819328,
          "state": null,
          "usename": "supabase_admin",
          "wait_event": "Extension",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "pg_cron launcher",
          "state_change": null,
          "wait_event_type": "Extension",
          "application_name": "pg_cron scheduler"
        },
        {
          "pid": 2819327,
          "state": "idle",
          "usename": "supabase_admin",
          "wait_event": "Extension",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "pg_net 0.20.4 worker",
          "state_change": "2026-09-27T23:32:04.567091+00:00",
          "wait_event_type": "Extension",
          "application_name": "pg_net 0.20.4"
        }
      ],
      "checked_at": "2026-09-27T23:34:17.865319+00:00",
      "locks_on_scope": []
    }
  }
]
```

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L3-LIVE-EXECUTION-01`, HEAD `89736a60`).** Registro da execução LIVE única do L3: S0 local; L1, L3, E00 24/24, E05P 14/14, E05 `H283P` `pass=10/10` (`line 1302`, `elapsed_ms=233`), E99 9/9, L3 final limpa; postcheck ÍNTEGRO; CONFORME proposto; 2Q.1–2Q.10 PASS e 54/135 sujeitos a auditoria (reconhecida 44/135). Autorização esgotada. FREEZE ATIVO. |
| 1.1 | **Fechamento (2026-09-27, `BATCH12-2830-P5-L3-CLOSEOUT-AND-L4-IMPLEMENTATION-01`, baseline `89736a60`).** Parecer independente PASS incorporado (§9): CONFORME, postcheck ÍNTEGRO, 2Q.1–2Q.10 PASS, cobertura vigente 54/135, autorização do E05 esgotada, sem repetição. §1–§8 e apêndices preservados. |
