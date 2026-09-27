# 2830H — Registro de execução da Etapa 2 (LIVE)

| Campo | Valor |
|---|---|
| **Natureza** | Registro da Etapa 2 do `LIVE-VALIDATION-PROTOCOL.md` v1.6, §4: L3 → E00 novo → E02 → E99, uma rodada. |
| **Mandato** | `BATCH12-2830-LIVE-STAGE2-EXECUTION-01`. Baseline HEAD `d12961571d22dbb5fb85677a9c1c4b60fd297d65`. Pré-requisito: Etapa 1 `READY FOR STAGE 2` (Tentativa 04, publicada em `d1296157`). |
| **Estado atual** | **Etapa 2: `D1–D5 PASS`** (2026-09-27, 03:05–03:10 UTC). O E02 terminou com `H283P` / `H2830_ROLLBACK_PASS`, `pass=5/5`, `elapsed_ms=20`. O E99 da mesma rodada deu `gate_pass = true`, `d_diff = []`, `d_canon_diff = []` e `g_captured_integrity = true`. **A Etapa 3 (E01) não está autorizada**: exige mandato próprio e os pré-requisitos do protocolo §5.1. FREEZE ATIVO. |
| **Papéis** | **Claude**: executor. **ChatGPT**: auditor independente. **Fabrício**: autorizações, commit e push. |

---

## 1. S2.0 — verificação do repositório

| Item | Resultado |
|---|---|
| HEAD | `d12961571d22dbb5fb85677a9c1c4b60fd297d65` = baseline do mandato |
| Árvore | limpa: `git status --porcelain --untracked-files=all` com 0 linhas, verificada antes de qualquer SQL |
| E00 | blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` = HEAD; md5 `45b6c35cca849ffbf49d22ec18e8283c`; 53.803 B; LF |
| E02 | blob `3357ed46b77e3bfacbe5b1988820e495ce363dd1` = HEAD; md5 `c7c93dc172e4301ef7d398edad0c43ed`; 13.182 B; LF |
| E99 | blob `49a71ecb4525697858110ee71a3f61f5eee74a34` = HEAD; md5 `f0b91183a8649b990b080637dd56e74b`; 12.289 B; LF |
| E01 / 2830 | `c4118b8c…` / `b4647dcb…`, iguais ao HEAD (não usados) |
| `tools/static_check.py` | **444 / 444 PASS, FAIL 0** |
| Canal | Supabase MCP `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`, nas 4 chamadas; uma chamada por statement |

## 2. Sequência e cronologia

| Passo | Chamada | Horário (banco) | SQLSTATE | Resultado |
|---|---|---|---|---|
| S2.1 | L3 (`b7bc3700…`) | `checked_at` 03:05:16.511487Z | nenhum | **conforme**: `locks_on_scope = []`; 12 `client backend`, todas `idle` |
| S2.2 | E00 (`45b6c35c…`), novo, desta rodada | `checked_at` 03:08:09.962467Z | nenhum | **24/24 gates `true`, `gate_pass = true`**, `d_canon_diff = []`, `d_baseline_md5 = 5c329d5e38a7e369cc100ab08953e1a7` |
| S2.3 | E02 (`c7c93dc1…`) | entre S2.2 e S2.4; o canal não devolve horário para erro | **`H283P`** | **PASS**: `H2830_ROLLBACK_PASS: envelope=E02_SECAO_D_IDENTIDADE_TERMINAL pass=5/5 casos=D1,D2,D3,D4,D5 elapsed_ms=20` |
| S2.4 | E99 com marcadores substituídos (`00233aa60c571994f39df2df3faf05ea`) | `checked_at` 03:10:00.668086Z | nenhum | **9/9 gates `true`, `gate_pass = true`**, `d_diff = []`, `d_canon_diff = []`, `g_captured_integrity = true` |

Nenhuma outra chamada foi feita entre o E00 e o E99. Ordem de submissão: L3 → E00 → E02 → E99. Sobre a cronologia do E02:
- o E02 foi submetido depois de recebida a resposta do E00 (03:08:09Z) e antes da submissão do E99 (03:10:00Z);
- o canal não expõe o horário do servidor na resposta de erro, por isso a ordem vem da sequência das chamadas;
- intervalo E00 → E99: 110,7 s.

O E00 desta rodada é novo: `checked_at` e `backend_pid` (3468773) são diferentes das duas leituras da Etapa 1, que não foram reutilizadas. Todo o conteúdo do E00, exceto `d_session`, é idêntico ao da Etapa 1: o estado continuou estável sob FREEZE.

## 3. Critérios do protocolo §4.2

1. **Resposta do E02.**
   - Erro com SQLSTATE `H283P`, exposto pelo canal na forma `ERROR:  H283P: …`.
   - A mensagem segue exatamente o formato exigido, com `N = 20`.
   - Contexto: `PL/pgSQL function inline_code_block line 212 at RAISE`, o `RAISE` final do bloco. A linha 212 é contada a partir do início do corpo do `DO`, e o `RAISE` está na linha 227 do arquivo.
   - Mensagem não truncada.
2. **`elapsed_ms`:** 20 ≤ 60000.
3. **E99:**
   - `gate_pass = true`, `d_diff = []`, `d_canon_diff = []`;
   - `g_captured_integrity = true`;
   - `g_captured_present`, `g_keys_identical`, `g_baseline_equal`, `g_freeze_canonical_equal`, `g_marker_absent`, `g_no_open_txn_others`, `g_lock_timeout_default` e `g_role_setting_unchanged` também `true`;
   - `d_baseline_now_md5 = 5c329d5e…`, igual ao `d_baseline_md5` do E00.
4. **Ordem temporal:** `checked_at(E00) < S2.3 < checked_at(E99)`, sem outro envelope entre eles.

Pela tabela do §4.3, a classificação é **`H283P` com mensagem conforme ⇒ PASS**, confirmado pelo E99. A adaptação AD-7 se aplica: o E02 não tem fixture, portanto não gera marcador `H2830_<uuid>`.

## 4. Preparação do E99 (substituição dos três marcadores)

- **Origem dos valores:** saída do E00 desta rodada (S2.2).
  - `__E00_D_BASELINE__` ← JSON de `d_baseline` (787 B, sem apóstrofo);
  - `__E00_D_BASELINE_MD5__` ← `5c329d5e38a7e369cc100ab08953e1a7`;
  - `__E00_ROLE_SETTING_ROWS__` ← `9`.
- **Mecânica:**
  - os valores foram gravados num arquivo de captura;
  - o texto do E99 foi gerado por script que substitui só os três literais entre aspas de `captured_raw`;
  - os comentários do cabeçalho, que citam os nomes dos marcadores, ficaram intactos;
  - o texto submetido difere do arquivo `49a71ecb…` em exatamente 3 linhas (56–58).
- **Controles antes de submeter:**
  - `md5(jsonb::text)` do JSON capturado, recalculado localmente, deu `5c329d5e…`, igual ao declarado;
  - o JSON capturado é igual ao `d_baseline` do E00;
  - o E99 do banco confirmou com `g_captured_integrity = true`.
- **Texto exato submetido:** md5 `00233aa60c571994f39df2df3faf05ea`, 13044 B, integral no Apêndice A.

## 5. Verificação local (sem banco)

Um script conferiu **22 / 22** critérios sobre as saídas registradas:
- L3 sem locks e sem sessão ativa;
- E00 com 24/24 gates, `gate_pass`, `d_canon_diff = []`, novo em relação à Etapa 1 e idêntico a ela fora de `d_session`;
- captura igual ao E00 (JSON, md5 e `role_rows`);
- E99 submetido igual ao arquivo, salvo as 3 linhas, e sem marcador remanescente nos literais;
- E02 com `H283P` e mensagem no formato exato, `elapsed_ms ≤ 60000`;
- E99 com 9/9 gates, `d_diff = []`, `d_canon_diff = []` e `g_captured_integrity`, e `d_baseline_now` igual ao `d_baseline` do E00;
- cronologia L3 < E00 < E99.

## 6. Limitações do canal

- O md5 do texto efetivamente submetido não é devolvido pelo MCP. A identidade do E00 e do E02 vem da conferência do arquivo (S2.0) e da submissão integral, sem edição. A do E99 vem do arquivo gerado (md5 acima).
- A resposta de erro do E02 chega como `HttpException` com a mensagem do PostgreSQL. O SQLSTATE aparece no texto (`H283P`), mas o canal não traz o horário do servidor.
- O `elapsed_ms` é medido dentro do bloco (`clock_timestamp()`) e não inclui a latência do canal.

## 7. Resultado

**Etapa 2: `D1–D5 PASS`.**
- Nenhuma alteração no LIVE, em SQL, funções, event triggers ou allowlist.
- Não foram executados E01, L4, L1, L2 nem consultas fora do protocolo.
- Nenhum caso da Seção 1 (E01) foi avaliado.
- A **Etapa 3 não está autorizada**: exige mandato próprio e os pré-requisitos do protocolo v1.6 §5.1: Etapa 2 aceita em registro; decisão A5/P8 sobre `lock_timeout` (D-3); canal gravável na L1; autorização explícita, no mandato, de escrita transitória sob FREEZE; D-4 resolvida se `lock_timeout` ≠ `'0'`. D-1/P14 (ambiente isolado) pertencem ao fechamento global do Batch 12, não aos pré-requisitos da Etapa 3.
- P9a (`EXPLAIN`) continua pendente.
- FREEZE ATIVO.

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

Como retornadas pelo `execute_sql`, sem o invólucro de dados não confiáveis. O md5 é do texto do bloco, incluindo a quebra de linha final.

L3 (S2.1) — md5 `164a5a46727c333d3c425151a9890546`, 3787 B:

```json
[{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:04:20.01735+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-26T05:29:27.073328+00:00","wait_event_type":"Client","application_name":""},{"pid":3467988,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T02:55:02.77629+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468013,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T02:57:01.103916+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468014,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T02:57:01.194385+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468039,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:00:02.271051+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468040,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:00:02.551527+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468083,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:02:01.155814+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468084,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:02:01.316108+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468740,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:05:02.323142+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3468741,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T03:05:02.978905+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T03:05:05.001269+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T03:05:16.511487+00:00","locks_on_scope":[]}}]
```

E00 (S2.2) — md5 `ae11e03954ff2be8ec18032b5a5a9116`, 18760 B:

```json
[{"e00_precheck":{"d_objects":{"indexes_D":5,"indexes_1x":4,"game_pokemon":1,"source_tcgdex":1,"constraints_1x":7,"roles_anon_authenticated":2},"d_session":{"checked_at":"2026-09-27T03:08:09.962467+00:00","backend_pid":3468773,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","statement_timeout":"2min","server_version_num":"170006","db_role_setting_rows":9,"session_replication_role":"origin"},"gate_pass":true,"d_baseline":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"d_p7_rules":[],"g_no_rules":true,"d_p7_writes":[{"target":"public.card_edition_context_profile","writer":"internal.seal_edition_context_composition","gate_scope":true,"target_exists":true},{"target":"public.card_edition_context_external_mapping","writer":"internal.seal_edition_context_external_mapping","gate_scope":true,"target_exists":true}],"d_sequences":[],"g_objects_d":true,"g_p7_no_ddl":true,"d_canon_diff":[],"g_no_residue":true,"g_objects_1x":true,"g_rls_bypass":true,"g_roles_1_12":true,"d_concurrency":{"other_sessions_in_txn":0},"g_game_source":true,"d_baseline_md5":"5c329d5e38a7e369cc100ab08953e1a7","d_p7_functions":[{"fn":"internal.enforce_edition_context_mapping_header()","via":"trigger trg_cecem_header","class":"GUARD","depth":1,"body_md5":"9e5fba31721c5e84212bd2116d3fa214","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"9e5fba31721c5e84212bd2116d3fa214","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_mapping_signature_write()","via":"trigger trg_cecem_signature_write","class":"GUARD","depth":1,"body_md5":"28084443cf6f32f9336d470ca16b7e72","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"28084443cf6f32f9336d470ca16b7e72","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_signature_write()","via":"trigger trg_cecp_signature_write","class":"GUARD","depth":1,"body_md5":"caa2e4d40d8e4995e217d7284f9d6c3b","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile","body_md5_lf":"caa2e4d40d8e4995e217d7284f9d6c3b","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_composition_immutable()","via":"trigger trg_cecpt_immutable","class":"GUARD","depth":1,"body_md5":"cfdcb500bb1090cd44c0e73d94c3f72e","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile_trait","body_md5_lf":"cfdcb500bb1090cd44c0e73d94c3f72e","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_mapping_composition_immutable()","via":"trigger trg_cecemt_immutable","class":"GUARD","depth":1,"body_md5":"ad0c472cfa82c71ee955d9b653755bdc","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping_trait","body_md5_lf":"ad0c472cfa82c71ee955d9b653755bdc","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_trait_active()","via":"trigger trg_cecpt_trait_active","class":"GUARD","depth":1,"body_md5":"68fb05f1c23db63a59611b0a12f79edd","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile_trait","body_md5_lf":"68fb05f1c23db63a59611b0a12f79edd","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.normalize_edition_context_external_mapping()","via":"trigger trg_cecem_normalize","class":"NORMALIZE","depth":1,"body_md5":"15ea6245b8b8ce2173abb3d6b72c6736","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"15ea6245b8b8ce2173abb3d6b72c6736","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_external_catalog_value(p_value text)","via":"trigger trg_cecem_normalize","class":"PURE","depth":2,"body_md5":"81361bb8f52ce142803d69c2b3028ae8","cr_count":2,"language":"sql","proconfig":["search_path=\"\""],"crlf_count":2,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"1fdc2e7ebe2297f8db85be4aad2e5d33","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(regdictionary, text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"cr_count":0,"language":"c","proconfig":null,"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":null,"dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"cr_count":0,"language":"c","proconfig":null,"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":null,"dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_composition()","via":"trigger trg_cecp_seal","class":"SEAL","depth":1,"body_md5":"6077409ac2b5de7f788076e3b4b3f0c0","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_profile","body_md5_lf":"6077409ac2b5de7f788076e3b4b3f0c0","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_external_mapping()","via":"trigger trg_cecem_seal","class":"SEAL","depth":1,"body_md5":"49a4ea4b34ccf06a4efdcf06270c52eb","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":true,"root_table":"card_edition_context_external_mapping","body_md5_lf":"49a4ea4b34ccf06a4efdcf06270c52eb","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.axis_identity_token(p_data jsonb, p_key text)","via":"index uq_cvir_row_identity","class":"UNCLASSIFIED","depth":1,"body_md5":"18682dce935281b0a4437628a6e8309a","cr_count":0,"language":"sql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"18682dce935281b0a4437628a6e8309a","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_edition_context_profile_game()","via":"trigger trg_card_variant_edition_context_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"21e3a4c08989545351e2757c59fc77c4","cr_count":36,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":36,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"27c1845dea596dd9b46413019799ab33","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_printing_profile_game()","via":"trigger trg_card_variant_printing_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"e847a065643a7836085eefc8116bb9c5","cr_count":0,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":0,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"e847a065643a7836085eefc8116bb9c5","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_cvir_normalized_shape()","via":"trigger trg_cvir_normalized_shape","class":"UNCLASSIFIED","depth":1,"body_md5":"1cebffee8afb213481342a9d402eb462","cr_count":62,"language":"plpgsql","proconfig":["search_path=\"\""],"crlf_count":62,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"f5bcae1bd83a6880c63519b31f36c5c4","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_job()","via":"trigger trg_catalog_variant_import_job_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"c01adb02245bd5a305e8f8987a30f1c1","cr_count":0,"language":"plpgsql","proconfig":null,"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_job","body_md5_lf":"c01adb02245bd5a305e8f8987a30f1c1","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_row()","via":"trigger trg_catalog_variant_import_row_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"7ae9bd52e030b13c3a241debda491a99","cr_count":0,"language":"plpgsql","proconfig":null,"crlf_count":0,"gate_scope":false,"root_table":"catalog_variant_import_row","body_md5_lf":"7ae9bd52e030b13c3a241debda491a99","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.set_updated_at()","via":"trigger trg_card_variant_set_updated_at","class":"UNCLASSIFIED","depth":1,"body_md5":"7933f81decf127af71628126ef109c81","cr_count":5,"language":"plpgsql","proconfig":["search_path=public, pg_temp"],"crlf_count":5,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"98a97559965c2e0ff884d95155ab5d3a","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.validate_card_variant_game_consistency()","via":"trigger trg_card_variant_validate_game_consistency","class":"UNCLASSIFIED","depth":1,"body_md5":"331a5501cb28172a63d2c3202594beaa","cr_count":40,"language":"plpgsql","proconfig":null,"crlf_count":40,"gate_scope":false,"root_table":"card_variant","body_md5_lf":"c1fe17587dfb3b0f6d7d5d690ca13636","dynamic_sql":false,"ddl_statement":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false}],"d_publications":[],"g_evt_ddl_only":true,"d_ownership_rls":[{"rls":true,"name":"card_edition_context_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_profile","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_profile_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_external_mapping","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_external_mapping_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_variant","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_variant_import_job","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_variant_import_row","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_admin_action_log","owner":"postgres","force_rls":false},{"rls":true,"name":"game","owner":"postgres","force_rls":false}],"d_event_triggers":[{"fn":"extensions.set_graphql_placeholder()","name":"issue_graphql_placeholder","tags":["DROP EXTENSION"],"event":"sql_drop","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"a2bc2d00b2cc2f5e8d2d6b8d73e2c360","fn_secdef":false,"fn_md5_raw":"a2bc2d00b2cc2f5e8d2d6b8d73e2c360","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_cron_access()","name":"issue_pg_cron_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"3a3917aad6ddd66182bf45b7490c3029","fn_secdef":false,"fn_md5_raw":"3a3917aad6ddd66182bf45b7490c3029","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_graphql_access()","name":"issue_pg_graphql_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"dd3f3e2bb94cff45ef24b9cecb6af1c8","fn_secdef":false,"fn_md5_raw":"dd3f3e2bb94cff45ef24b9cecb6af1c8","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.grant_pg_net_access()","name":"issue_pg_net_access","tags":["CREATE EXTENSION"],"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"2ee4e6920eeba3068bcfa838105352e2","fn_secdef":false,"fn_md5_raw":"2ee4e6920eeba3068bcfa838105352e2","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.pgrst_ddl_watch()","name":"pgrst_ddl_watch","tags":null,"event":"ddl_command_end","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"7f27b8118fea5c88b0164331292859e3","fn_secdef":false,"fn_md5_raw":"7f27b8118fea5c88b0164331292859e3","fn_language":"plpgsql","fn_extension":null},{"fn":"extensions.pgrst_drop_watch()","name":"pgrst_drop_watch","tags":null,"event":"sql_drop","owner":"supabase_admin","enabled":"O","fn_owner":"supabase_admin","fn_config":["search_path=\"\""],"fn_md5_lf":"bc09cc3003d66f91844af4cb05e203b7","fn_secdef":false,"fn_md5_raw":"bc09cc3003d66f91844af4cb05e203b7","fn_language":"plpgsql","fn_extension":null}],"g_no_concurrency":true,"g_p7_no_unresolved":true,"d_evt_catalog_count":6,"d_evt_unadjudicated":[],"d_p7_eol_normalized":["public.normalize_external_catalog_value(p_value text)"],"g_p7_all_classified":true,"g_p7_identity_pinned":true,"g_p7_writes_in_scope":true,"g_evt_all_adjudicated":true,"g_p7_closure_complete":true,"g_p7_search_path_safe":true,"d_evt_allowlist_absent":[],"d_p7_unqualified_calls":[{"name":"jsonb_typeof","caller":"internal.axis_identity_token","gate_scope":false,"resolution":"BUILTIN"},{"name":"array","caller":"internal.enforce_edition_context_mapping_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"array","caller":"internal.enforce_edition_context_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"and","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"if","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"in","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"jsonb_exists","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"jsonb_typeof","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.guard_edition_context_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_mapping_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_trait_active","gate_scope":true,"resolution":"KEYWORD"},{"name":"btrim","caller":"internal.normalize_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"coalesce","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"regexp_replace","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"},{"name":"trim","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"}],"d_p7_unqualified_writes":[],"g_p7_no_unqualified_dml":true,"g_evt_inventory_complete":true,"g_freeze_canonical_equal":true,"g_p7_lexically_supported":true,"d_p7_unresolved_qualified":[],"g_pg17_maintain_privilege":true,"g_no_sequences_touched_now":true,"g_p7_no_external_or_dynamic":true}}]
```

E02 (S2.3), resposta de erro do canal — md5 `1716a997fbae3d7a425696947944025e`, 260 B:

```json
{"error":{"name":"HttpException","message":"Failed to run sql query: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E02_SECAO_D_IDENTIDADE_TERMINAL pass=5/5 casos=D1,D2,D3,D4,D5 elapsed_ms=20\nCONTEXT:  PL/pgSQL function inline_code_block line 212 at RAISE\n"}}
```

E99 (S2.4) — md5 `80f32ecd252c27a73735524b4efde1bf`, 1305 B:

```json
[{"e99_postcheck":{"d_diff":[],"d_session":{"checked_at":"2026-09-27T03:10:00.668086+00:00","backend_pid":3468793,"lock_timeout":"0","db_role_setting_rows":9},"gate_pass":true,"d_canon_diff":[],"d_baseline_now":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"g_marker_absent":true,"g_baseline_equal":true,"g_keys_identical":true,"d_baseline_now_md5":"5c329d5e38a7e369cc100ab08953e1a7","g_captured_present":true,"g_captured_integrity":true,"g_no_open_txn_others":true,"g_lock_timeout_default":true,"g_freeze_canonical_equal":true,"g_role_setting_unchanged":true}}]
```

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação — Etapa 2 `D1–D5 PASS` (2026-09-27 UTC, `BATCH12-2830-LIVE-STAGE2-EXECUTION-01`, HEAD `d1296157`).** Claude executou L3 → E00 novo → E02 → E99 via MCP:<br>• E00 com 24/24 gates `true`;<br>• E02 com `H283P` / `H2830_ROLLBACK_PASS`, `pass=5/5`, D1–D5, `elapsed_ms=20`;<br>• E99 com 9/9 gates, `d_diff = []`, `d_canon_diff = []` e `g_captured_integrity = true`;<br>• cronologia comprovada; 22/22 critérios verificados localmente.<br>Saídas integrais e texto exato do E99 anexados. Etapa 3 não autorizada. |
