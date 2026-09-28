# LIVE — Lote L4 (E06): registro de execução

| Campo | Valor |
|---|---|
| **Documento** | Registro operacional da execução LIVE única e controlada do lote L4 (E06P + E06), Seção 3 da 2830 v7.0 (3.1, 3.2, 3.4, 3.5, 3.6, 3.7; 3.3 no L5) |
| **Versão** | 1.0 |
| **Mandato** | BATCH12-2830-P5-L4-LIVE-EXECUTION-01 · HEAD `945caa322f682ad73ab6aaa77e76d26e5649821f` · projeto Supabase `qjfutqujxrbzgrtkpgkg` · canal MCP `execute_sql` |
| **Resultado** | E06 `H283P` `pass=6/6`, casos `3.1,3.2,3.4,3.5,3.6,3.7`, marcador `H2830_0AB0CAA945C540FE9F668AE03C86384A`, `elapsed_ms=169`, `c35_token=GLOSSY`, `c35_overlap=f`, `u37=3`, CONTEXT `line 807`; E06P 20/20 (2192 demonstrada no LIVE); E99 9/9 (`d_diff=[]`; trait 115 = 115, mapping 122 = 122, mapping_trait 122 = 122); L3 final limpa; postcheck **ÍNTEGRO**; classificação proposta **CONFORME** |
| **Autorização de escrita** | Esgotada: uma única submissão do E06 (R1, rollback estrutural). Nenhum retry, nenhum outro envelope, nenhuma escrita persistente. |
| **Estado** | **AGUARDA AUDITORIA INDEPENDENTE.** Proposta: PASS de 3.1, 3.2, 3.4, 3.5, 3.6, 3.7 e cobertura **60/135**; até o parecer, a cobertura reconhecida permanece **54/135**. L5 não iniciado. FREEZE ATIVO. |

## 1. S0 — preflight local

| Item | Esperado | Obtido |
|---|---|---|
| HEAD | `945caa32…` | `945caa322f682ad73ab6aaa77e76d26e5649821f` |
| Árvore / índice | limpos | `git status --porcelain` vazio; índice = árvore em todo o harness |
| E06P (100644) | `486e3035…` | `486e3035d8a966c610633aa11d00f4ac03d5e75b` · md5 `0082e75bf4a9cf34f489ca1fea5dc40f` · 23.197 B / 337 linhas |
| E06 (100644) | `33079480…` | `33079480a70aec97a513f052c1ac18f763de34b9` · md5 `9f60c532c972bd29df30d9e0f194fb8d` · 56.403 B / 885 linhas |
| static_check.py (100644) | `574d7927…` | `574d7927565479770631fd7cd3fab3175a480a8a` |
| Registro operacional L4 (100644) | `51b6c30f…` | `51b6c30f…` (v1.0) |
| E00 (100644) | `a4dd8438…` | md5 `45b6c35cca849ffbf49d22ec18e8283c` · 53.803 B |
| E99 base (100644) | `49a71ecb…` | `49a71ecb4525697858110ee71a3f61f5eee74a34` |
| Contrato 2830 (100644) | `b4647dcb…` | `b4647dcb59432405c8157e2733fd78678f35540e` |
| E03 / E03P / E03T / E04 / E04P / E05 / E05P | inalterados | `ef24a3be…` / `0fc2d83d…` / `9523bf23…` / `5b2a8b6f…` / `5cb4b893…` / `03a9ff02…` / `e5c27a56…` |
| L1 / L3 (runbook §3.1/§3.2) | md5 `0836c36a…` / `b7bc3700…` | idênticos (2.458 B / 1.526 B) |
| static_check | 444 · 88/79/6 · 65/94/7 · 58/54/6 · 64/54/6 | idêntico, rc=0 |

## 2. Cronologia (7 chamadas `execute_sql`, uma por statement, conferência integral entre elas)

| Passo | Texto | `checked_at` (UTC, 2026-09-28) | pid | Resultado |
|---|---|---|---|---|
| S1 | L1 | 00:13:31.153924 | 3564203 | gravável (`transaction_read_only=off`, `in_recovery=false`), `statement_timeout=2min`, `lock_timeout=0`, PG 170006, `standard_conforming_strings=on`, 5 tabelas EC de `postgres`, `reads_all_stats=true`, `visible_foreign_sessions=15` |
| S2 | L3 inicial | 00:13:42.896336 | — | `locks_on_scope=[]`; 28 sessões, todas `idle` (ou launcher `pg_cron` sem estado), nenhum `xact_start`, nenhum `backend_xid` |
| S3 | E00 (`45b6c35c…`) | 00:18:09.532648 | 3564664 | **24/24 gates**, `gate_pass=true`, `d_canon_diff=[]`, `d_baseline_md5=5c329d5e38a7e369cc100ab08953e1a7`, `db_role_setting_rows=9` |
| S4 | E06P (`0082e75b…`) | 00:20:50.173367 | 3564721 | **20/20 gates**, `gate_pass=true` |
| S5 | E06 (`9f60c532…`), submissão única | (erro terminal; o canal não devolve horário) | — | `H283P` `pass=6/6` (§4) |
| S6 | E99 preenchido (`00233aa6…`) | 00:25:49.772193 | 3565393 | **9/9**, `gate_pass=true`, `d_diff=[]`, `d_canon_diff=[]` |
| S7 | L3 final (despachada **só depois** da conferência do S6) | 00:26:08.496698 | — | `locks_on_scope=[]`; 15 sessões, nenhuma em transação; nenhum pid da rodada |

Ordem temporal: `L1 < L3 < E00 < E06P < S5 < E99 < L3 final` (S5 posicionado pela sequência de chamadas). S6 e S7 em chamadas separadas.

## 3. Gates do E06P (S4) — dado real de 3.5 e 3.7

| Gate | Evidência LIVE |
|---|---|
| `g_game_pokemon_one`, `g_source_tcgdex_one` | 1 e 1 |
| `g_l4_triggers`, `g_no_other_triggers_l4` | 5 triggers esperados (`tgtype` 7/19/5/19/31), habilitados `O`; `trg_cecem_seal` único constraint trigger deferrable/initially deferred; `trg_cecem_signature_write` com `attrs=[traits_signature]`; nenhum outro trigger nas 3 tabelas |
| `g_seal_constraint_names_unique`, `g_deferrable_only_seal_l4` | `trg_cecp_seal` e `trg_cecem_seal` únicos em `public`; nenhuma outra constraint deferrable nas 3 tabelas |
| `g_l4_constraints` | 15 constraints exigidas validadas + `uq_cecem_active_global` (`external_set_id IS NULL AND is_active`) e `uq_cecem_active_scoped` (`external_set_id IS NOT NULL AND is_active`) válidos/prontos, colunas esperadas |
| `g_36_raw_field_check` | `ck_cecem_raw_field` validada, contém `'stamp'` e `'subtype'`, não contém `'type'` |
| `g_rc_identity` | 4/4 `ok=true`, md5 LF = pino: 2211 `f10af378c2d5d9fdfd207d9c7d9ff046`; 2176 `b15a527d3b6adb1e50cbaafae22431bc`; 2095 `1fdc2e7ebe2297f8db85be4aad2e5d33`; **2192 `internal.resolve_variant_mapping_scope(uuid,uuid)` `21a57ebf7e0d15fc14e576999523cd51`** (`sql`, `s`, SECURITY DEFINER, `search_path=""`, `TABLE(external_set_id text, reference_id uuid)`) — **primeira demonstração LIVE da identidade da 2192**; 4 tokens de estado presentes no corpo da 2211 |
| `g_rc_executable` | EXECUTE na 2211 e na 2192 |
| `g_35_candidate` | `d_35_candidate`: mapping de Printing `02cf8c46-e58e-42f5-a2a9-a2927a15a477`, `raw_field=subtype`, `normalized_token=GLOSSY`, `sig=[155c7392-92ee-4264-82f6-02904668bbc0]`, profile `e7ea2b9f-998a-4f54-a61a-fb36e2896e08`, `ec_overlap=false` |
| `g_37_h2` | 3 mappings SET-LOGO ativos, todos `stamp`, escopados: dp1 `52ffc7dd-…b700`, svp `a5412ead-…9fcf`, swsh9 `c7404778-…3269`; nenhum GLOBAL; nenhum fora dos três; assinatura `[767f2695-13c7-4c36-b51b-4fe11949ea9e]` |
| `g_37_scope_resolvable` | Card Set real → 2192: dp1 `36a79fc7-10b8-4992-bd91-872bc7874aae` → `dp1`; svp `f205e51c-e69b-4018-8e06-c1fa129464f3` → `svp`; swsh9 `4aca8a26-3737-4e16-b0e2-b18de3bd1b71` → `swsh9` (1 referência ativa e 1 escopo cada) |
| `g_37_profile` | 1 profile de EC ativo para a assinatura de cada um, traits ativos (3/3) |
| `g_37_no_printing` | nenhum mapping de Printing `stamp`/`SET-LOGO` |
| `g_37_out_of_scope_control` | Card Set real `0000fdc8-30fd-412f-88e7-40459092a9f1` (`swsh8`) resolve 1 escopo = `swsh8` |
| `g_37_normalization` | `set-logo` → `SET-LOGO` pela 2095 LIVE |
| `g_l4_no_sequence`, `g_l4_rls_bypass` | nenhuma sequence nas 3 tabelas; as 3 de `postgres`, RLS sem FORCE |
| `g_marker_absent_now` | 0 trait, 0 mapping de EC (token e Set), 0 mapping de Printing com `H2830` |

Nenhum pino, predicado ou resultado foi ajustado.

## 4. S5 — resposta literal do E06

```
ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E06_SECAO3_ROUTING_FAIL_CLOSED pass=6/6 casos=3.1,3.2,3.4,3.5,3.6,3.7 marker=H2830_0AB0CAA945C540FE9F668AE03C86384A elapsed_ms=169 c35_token=GLOSSY c35_overlap=f u37=3
CONTEXT:  PL/pgSQL function inline_code_block line 807 at RAISE
```

| Critério do mandato | Resultado |
|---|---|
| SQLSTATE `H283P` / prefixo `H2830_ROLLBACK_PASS` | sim |
| `envelope=E06_SECAO3_ROUTING_FAIL_CLOSED` | sim |
| `pass=6/6`, `casos=3.1,3.2,3.4,3.5,3.6,3.7` | sim, na ordem contratual |
| marcador `H2830_` + 32 hex maiúsculos | `H2830_0AB0CAA945C540FE9F668AE03C86384A` |
| `elapsed_ms ≤ 60000` | 169 |
| `c35_token` = candidato do E06P | `GLOSSY` = `d_35_candidate.normalized_token` |
| `c35_overlap` booleano definido | `f` (false) = `d_35_candidate.ec_overlap` |
| `u37=3` | sim |
| CONTEXT = RAISE terminal do blob publicado | `line 807`: `DO $h2830_e06$` na linha 74 do arquivo e RAISE `H283P` na linha 880 ⇒ linha 807 do corpo |
| P8 fail-closed | o preâmbulo `SET LOCAL lock_timeout='5s'` + asserção não disparou `H283F`; E99 `g_lock_timeout_default=true` |
| Gate interno do envelope | `v_done = c_expected` e evidências `c35`/`u37` presentes (senão `H283F` antes do terminal) |

Nenhum `H283F`, `55P03`, `57014` ou SQLSTATE inesperado. Resposta definida, íntegra e não truncada. `c35_overlap=f`: o candidato real não tem mapping EC GLOBAL ativo; a asserção de 3.5 (token fora do residual, EC `RESOLVED_NO_EDITION_CONTEXT`, sem trait) vale e foi provada; o ramo com sobreposição não foi exercitado (não exigido pelo mandato).

## 5. S6 — E99 submetido

Valores copiados **da saída do S3 desta rodada** (`d_baseline` literal do canal, 787 B, sem apóstrofo; `d_baseline_md5=5c329d5e…`, recalculado localmente sobre a serialização jsonb = declarado; `db_role_setting_rows=9`). Texto gerado por substituição única dos 3 marcadores do blob `49a71ecb…`; difere do base só nas linhas 56–58. md5 `00233aa60c571994f39df2df3faf05ea` · sha256 `3a3da896400279791f5c2a36c33477f053d6d3eb3b9131d4f68b8b155762bd8d` · 13.044 B. O texto coincide byte a byte com o E99 do L3 (mesmo estado sob FREEZE); a vinculação documental é com o E00 **desta** rodada (S3, pid 3564664, 00:18:09Z). Texto integral no Apêndice A.

## 6. Integridade e superfície de escrita

| Evidência | Resultado |
|---|---|
| E99 9/9 | `g_captured_present`, `g_captured_integrity`, `g_keys_identical`, `g_baseline_equal` (`d_diff=[]`), `g_freeze_canonical_equal` (`d_canon_diff=[]`), `g_marker_absent`, `g_no_open_txn_others`, `g_lock_timeout_default`, `g_role_setting_unchanged` — todos `true` |
| trait | **E00 115 = E99 115** (4 fixtures `EVENT` desfeitas); `marker_trait` 0 |
| mapping | **E00 122 = E99 122** (5 fixtures aceitas e 2 tentativas recusadas não persistiram; o UPDATE de 3.2 só tocou a fixture); `marker_mapping` 0; `mapping_null_signature` 0 = 0 |
| mapping_trait | **E00 122 = E99 122** (4 N:N de fixture desfeitas) |
| baseline depois | `d_baseline_now_md5 = 5c329d5e…` = E00 |
| L3 final | `locks_on_scope=[]`; nenhuma sessão em transação; pids da rodada (3564203, 3564664, 3564721, 3565393) ausentes |

Superfície R1 transitória, só nas 3 tabelas EC autorizadas: `card_edition_context_trait` 4 INSERT (3.2: 1; 3.4: 3); `card_edition_context_external_mapping` 7 tentativas de INSERT (3.2: 1; 3.4: 3 + 1 recusada `23505 uq_cecem_active_scoped`; 3.6: 1 + 1 recusada `23514 ck_cecem_raw_field`) e 1 UPDATE (3.2, `WHERE id = v_m1 AND normalized_token = v_tok`, ROW_COUNT 1, identidade reconferida); `card_edition_context_external_mapping_trait` 4 INSERT; 0 DELETE. Leitura sem escrita de `card_printing_*` (3.1, 3.5), `card_edition_context_profile` (3.7) e `card_set_external_reference` (3.7). Sem `SET CONSTRAINTS`, sem sonda. Tudo desfeito pelo término em exceção. Nenhuma linha preexistente modificada (E99 `d_diff=[]`).

**Postcheck: ÍNTEGRO.**

## 7. Desvios e limitações

- Nenhum desvio de procedimento: 7 chamadas, uma por statement; S6 e S7 separadas; sem retry, sem SQL fora dos textos identificados, sem consulta exploratória.
- **Identidade do texto submetido (E00, E06P, E06):** transcritos dos arquivos com os blobs do §1; o canal não devolve hash do recebido. Evidência: o E06 aponta `line 807`, exatamente o RAISE terminal do blob publicado; E00/E06P têm a forma e o número de gates esperados (24/20). Limitação idêntica à das execuções anteriores.
- **Operacional (sem efeito no resultado):** na montagem local do E99, uma asserção do gerador (ausência total de `__E00_` no texto) falhou porque o cabeçalho do blob cita os marcadores em comentário (l. 9–11); nenhum texto foi submetido nessa tentativa. A asserção correta (sem marcador entre aspas) passou; o texto final é o mesmo do L3 (md5 `00233aa6…`).
- `visible_foreign_sessions=15` (L1) e 28 sessões na L3 inicial (L3: 14): variação de pool da plataforma (PostgREST, Storage, pgbouncer), todas ociosas e sem transação; a visibilidade está provada por `reads_all_stats=true`.
- `c35_overlap=false`: registrado; ver §4.
- `g_no_open_txn_others` e a L3 medem outras sessões; a sessão do canal não mantém transação entre chamadas.

## 8. Classificação e proposta

**CONFORME** (critérios do mandato atendidos; postcheck ÍNTEGRO). Proposta, sujeita à auditoria independente: **PASS de 3.1, 3.2, 3.4, 3.5, 3.6, 3.7** e cobertura **60/135** (54 + 6). Até o parecer, a cobertura reconhecida permanece **54/135**. 3.3 continua reservado ao L5. Não iniciar L5 nem outro lote. FREEZE ATIVO.

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
      "checked_at": "2026-09-28T00:13:31.153924+00:00",
      "backend_pid": 3564203,
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
      "visible_foreign_sessions": 15,
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
          "state_change": "2026-09-28T00:13:20.923581+00:00",
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
          "pid": 3563913,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:10:01.620137+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563914,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:10:01.788272+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563946,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:43.7029+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563950,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:43.894308+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563951,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:43.926149+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563952,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:44.312038+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563953,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:47.325519+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563955,
          "state": "idle",
          "usename": "pgbouncer",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.744486+00:00",
          "wait_event_type": "Client",
          "application_name": ""
        },
        {
          "pid": 3563956,
          "state": "idle",
          "usename": "pgbouncer",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.507624+00:00",
          "wait_event_type": "Client",
          "application_name": ""
        },
        {
          "pid": 3563957,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.58975+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563958,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.562883+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563959,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.851637+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563960,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.564866+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563961,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.589843+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563962,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.564114+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563963,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.562734+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563964,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.563982+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563965,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:49.403421+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563966,
          "state": "idle",
          "usename": "pgbouncer",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.531595+00:00",
          "wait_event_type": "Client",
          "application_name": ""
        },
        {
          "pid": 3563967,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.562993+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563968,
          "state": "idle",
          "usename": "supabase_storage_admin",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:11:48.855556+00:00",
          "wait_event_type": "Client",
          "application_name": "Supabase Storage API"
        },
        {
          "pid": 3563970,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:12:00.77359+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3563971,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:12:00.886005+00:00",
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
          "state_change": "2026-09-28T00:12:03.905229+00:00",
          "wait_event_type": "Extension",
          "application_name": "pg_net 0.20.4"
        }
      ],
      "checked_at": "2026-09-28T00:13:42.896336+00:00",
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
        "checked_at": "2026-09-28T00:18:09.532648+00:00",
        "backend_pid": 3564664,
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

### B.4 E06P (S4)

```json
[
  {
    "e06p_precheck": {
      "g_37_h2": true,
      "d_session": {
        "checked_at": "2026-09-28T00:20:50.173367+00:00",
        "backend_pid": 3564721,
        "current_user": "postgres",
        "lock_timeout": "0",
        "server_version_num": "170006"
      },
      "gate_pass": true,
      "d_37_scope": [
        {
          "refs": 1,
          "scope": "dp1",
          "n_scope": 1,
          "card_set_id": "36a79fc7-10b8-4992-bd91-872bc7874aae",
          "external_set_id": "dp1"
        },
        {
          "refs": 1,
          "scope": "svp",
          "n_scope": 1,
          "card_set_id": "f205e51c-e69b-4018-8e06-c1fa129464f3",
          "external_set_id": "svp"
        },
        {
          "refs": 1,
          "scope": "swsh9",
          "n_scope": 1,
          "card_set_id": "4aca8a26-3737-4e16-b0e2-b18de3bd1b71",
          "external_set_id": "swsh9"
        }
      ],
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
      "d_37_profile": [
        {
          "profiles": 1,
          "traits_active": true,
          "external_set_id": "dp1",
          "traits_signature": [
            "767f2695-13c7-4c36-b51b-4fe11949ea9e"
          ]
        },
        {
          "profiles": 1,
          "traits_active": true,
          "external_set_id": "svp",
          "traits_signature": [
            "767f2695-13c7-4c36-b51b-4fe11949ea9e"
          ]
        },
        {
          "profiles": 1,
          "traits_active": true,
          "external_set_id": "swsh9",
          "traits_signature": [
            "767f2695-13c7-4c36-b51b-4fe11949ea9e"
          ]
        }
      ],
      "g_37_profile": true,
      "d_37_set_logo": [
        {
          "id": "52ffc7dd-b855-43ee-a9bc-aa367c17b700",
          "is_active": true,
          "raw_field": "stamp",
          "external_set_id": "dp1",
          "traits_signature": [
            "767f2695-13c7-4c36-b51b-4fe11949ea9e"
          ]
        },
        {
          "id": "a5412ead-396d-4712-8666-fa53f99a9fcf",
          "is_active": true,
          "raw_field": "stamp",
          "external_set_id": "svp",
          "traits_signature": [
            "767f2695-13c7-4c36-b51b-4fe11949ea9e"
          ]
        },
        {
          "id": "c7404778-fdeb-4a85-8e9d-ee3a5c0d3269",
          "is_active": true,
          "raw_field": "stamp",
          "external_set_id": "swsh9",
          "traits_signature": [
            "767f2695-13c7-4c36-b51b-4fe11949ea9e"
          ]
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
      "d_rc_identity": [
        {
          "ok": true,
          "cfg": [
            "search_path=\"\""
          ],
          "pin": "b15a527d3b6adb1e50cbaafae22431bc",
          "sig": "internal.compute_variant_residual_signature(jsonb,uuid,uuid)",
          "vol": "s",
          "lang": "plpgsql",
          "result": "TABLE(residual_type text, residual_foil text, residual_subtype text, residual_stamp text[], printing_state text, trait_ids uuid[], printing_profile_id uuid)",
          "secdef": true,
          "body_md5_lf": "b15a527d3b6adb1e50cbaafae22431bc"
        },
        {
          "ok": true,
          "cfg": [
            "search_path=\"\""
          ],
          "pin": "21a57ebf7e0d15fc14e576999523cd51",
          "sig": "internal.resolve_variant_mapping_scope(uuid,uuid)",
          "vol": "s",
          "lang": "sql",
          "result": "TABLE(external_set_id text, reference_id uuid)",
          "secdef": true,
          "body_md5_lf": "21a57ebf7e0d15fc14e576999523cd51"
        },
        {
          "ok": true,
          "cfg": [
            "search_path=\"\""
          ],
          "pin": "f10af378c2d5d9fdfd207d9c7d9ff046",
          "sig": "internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)",
          "vol": "s",
          "lang": "plpgsql",
          "result": "TABLE(printing_state text, printing_profile_id uuid, printing_trait_ids uuid[], edition_context_state text, edition_context_profile_id uuid, edition_context_trait_ids uuid[], residual_type text, residual_foil text, residual_subtype text, residual_stamp text[])",
          "secdef": true,
          "body_md5_lf": "f10af378c2d5d9fdfd207d9c7d9ff046"
        },
        {
          "ok": true,
          "cfg": [
            "search_path=\"\""
          ],
          "pin": "1fdc2e7ebe2297f8db85be4aad2e5d33",
          "sig": "public.normalize_external_catalog_value(text)",
          "vol": "s",
          "lang": "sql",
          "result": "text",
          "secdef": false,
          "body_md5_lf": "1fdc2e7ebe2297f8db85be4aad2e5d33"
        }
      ],
      "g_l4_triggers": true,
      "g_rc_identity": true,
      "d_35_candidate": [
        {
          "id": "02cf8c46-e58e-42f5-a2a9-a2927a15a477",
          "sig": [
            "155c7392-92ee-4264-82f6-02904668bbc0"
          ],
          "raw_field": "subtype",
          "ec_overlap": false,
          "profile_id": "e7ea2b9f-998a-4f54-a61a-fb36e2896e08",
          "normalized_token": "GLOSSY"
        }
      ],
      "d_l4_sequences": [],
      "g_35_candidate": true,
      "d_marker_counts": {
        "marker_trait": 0,
        "marker_mapping": 0,
        "marker_printing_mapping": 0
      },
      "g_l4_rls_bypass": true,
      "g_rc_executable": true,
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
      "g_37_no_printing": true,
      "g_l4_constraints": true,
      "g_l4_no_sequence": true,
      "d_37_out_of_scope": [
        {
          "n_scope": 1,
          "card_set_id": "0000fdc8-30fd-412f-88e7-40459092a9f1",
          "external_set_id": "swsh8"
        }
      ],
      "d_l4_ownership_rls": [
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
      "g_37_normalization": true,
      "g_game_pokemon_one": true,
      "g_marker_absent_now": true,
      "g_source_tcgdex_one": true,
      "g_36_raw_field_check": true,
      "g_37_scope_resolvable": true,
      "g_no_other_triggers_l4": true,
      "g_37_out_of_scope_control": true,
      "g_deferrable_only_seal_l4": true,
      "g_seal_constraint_names_unique": true
    }
  }
]
```

### B.5 E06 (S5) — resposta integral do canal

```json
{"error":{"name":"HttpException","message":"Failed to run sql query: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E06_SECAO3_ROUTING_FAIL_CLOSED pass=6/6 casos=3.1,3.2,3.4,3.5,3.6,3.7 marker=H2830_0AB0CAA945C540FE9F668AE03C86384A elapsed_ms=169 c35_token=GLOSSY c35_overlap=f u37=3\nCONTEXT:  PL/pgSQL function inline_code_block line 807 at RAISE\n"}}
```

### B.6 E99 (S6)

```json
[
  {
    "e99_postcheck": {
      "d_diff": [],
      "d_session": {
        "checked_at": "2026-09-28T00:25:49.772193+00:00",
        "backend_pid": 3565393,
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

### B.7 L3 final (S7)

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
          "state_change": "2026-09-28T00:25:21.700381+00:00",
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
          "pid": 3564634,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:15:01.885228+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564635,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:15:02.56268+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564656,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:17:01.359556+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564660,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:17:01.500288+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564691,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:20:01.657251+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564692,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:20:02.014864+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564726,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:22:01.751813+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564727,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:22:01.886044+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564987,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:25:02.003211+00:00",
          "wait_event_type": "Client",
          "application_name": "PostgREST 14.5"
        },
        {
          "pid": 3564989,
          "state": "idle",
          "usename": "authenticator",
          "wait_event": "ClientRead",
          "xact_start": null,
          "backend_xid": null,
          "backend_type": "client backend",
          "state_change": "2026-09-28T00:25:02.362648+00:00",
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
          "state_change": "2026-09-28T00:25:04.399042+00:00",
          "wait_event_type": "Extension",
          "application_name": "pg_net 0.20.4"
        }
      ],
      "checked_at": "2026-09-28T00:26:08.496698+00:00",
      "locks_on_scope": []
    }
  }
]
```

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L4-LIVE-EXECUTION-01`, HEAD `945caa32`).** Registro da execução LIVE única do L4: S0 local; L1, L3, E00 24/24, E06P 20/20 (identidade da 2192 demonstrada no LIVE), E06 `H283P` `pass=6/6` (`line 807`, `elapsed_ms=169`, `c35_token=GLOSSY`, `c35_overlap=f`, `u37=3`), E99 9/9 (trait/mapping/mapping_trait iguais ao E00), L3 final limpa; postcheck ÍNTEGRO; CONFORME proposto; PASS de 3.1, 3.2, 3.4–3.7 e cobertura 60/135 propostos, sujeitos a auditoria independente (54/135 reconhecidos). Autorização de escrita esgotada. FREEZE ATIVO. |
