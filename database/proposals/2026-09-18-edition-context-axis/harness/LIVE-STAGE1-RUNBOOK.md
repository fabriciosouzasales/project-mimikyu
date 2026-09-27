# 2830H — Roteiro operacional da Etapa 1 (LIVE, somente SELECT)

| Campo | Valor |
|---|---|
| **Mandato de preparação** | `BATCH12-2830-LIVE-STAGE1-EXECUTION-READINESS-01` (2026-09-26) |
| **Status** | **v1.5 — D-9 incorporada LOCALMENTE** (`BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`), **não commitada**, pendente de auditoria independente. A v1.4 foi publicada em `9a4cff16` e está superada. O E00 vigente **não foi compilado nem executado** no PostgreSQL. A v1.3 foi executada na Tentativa 03 (STOP em S1.3; ver `LIVE-STAGE1-EXECUTION-RECORD.md`). Este roteiro **não autoriza** a execução. |
| **Baseline** | Correção feita sobre HEAD `b8925ed571127be8f05fac98f6a3afbad5fe74a3`, ainda não commitada. O baseline de execução é o commit que contiver esta correção; ele será fixado pelo mandato de execução (PC-1). |
| **Autoridade** | `LIVE-VALIDATION-PROTOCOL.md` **v1.6**, seção 3. Em caso de conflito, o protocolo prevalece e o conflito é STOP. |
| **Contrato** | 2830 v7.0, blob `b4647dcb59432405c8157e2733fd78678f35540e` — imutável. |
| **FREEZE** | ATIVO. |

---

## 0. Artefatos e identidade do texto submetido

Todo texto é submetido **verbatim**, uma consulta por chamada `execute_sql`. O executor confere o md5 do texto **antes** de submeter.

| Consulta | Origem | Identidade |
|---|---|---|
| **L1** — canal e sessão | `LIVE-VALIDATION-PROTOCOL.md` §3.2, bloco SQL 1 (reproduzido em §3) | md5 do texto `0836c36a8d3749b1e7718223e064caf9` |
| **L3** — concorrência | idem, bloco SQL 3 | md5 `b7bc3700aeef278f6a79bd30e6a8d229` |
| **E00** — precheck | `2830H_E00_precheck_inventory.sql`, arquivo **inteiro**, comentários incluídos | blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` · md5 do arquivo `45b6c35cca849ffbf49d22ec18e8283c` (53.803 B, 24 gates; `evt_allowlist` com as 6 exceções de D-9) |
| **L2** — pinos, **só diagnóstico** | idem, bloco SQL 2 | md5 `81d3472e69d8490849b16a0918c3e35d` |
| **L4** — event triggers, **só adjudicação D-9** | este roteiro, §3.5 | md5 `f3670eb8f149064610055720b0636218` (2.416 B). **Fora** da sequência da Etapa 1; exige mandato próprio. |

Os md5 da tabela são do texto exato de cada bloco SQL deste documento: da linha após a abertura da cerca até a quebra de linha final, inclusive, antes da cerca de fechamento. O texto de L1, L2 e L3 é idêntico ao dos blocos do protocolo. Os hashes de E00 e L4 anteriores a esta versão (E00 `97410c3a…` / `d00b7cec…`, executado na Tentativa 03; E00 proposto `a10ffd81…`; E00 `88e9e7a4…` / `a9352afc…`, publicado em `9a4cff16` com `evt_allowlist` vazia; L4 `6bdc9dc4…`) são **históricos** e **não** são critério vigente.

---

## 1. Pré-condições (todas, antes de S1.1)

| # | Verificação | Evidência a registrar | Falha |
|---|---|---|---|
| PC-1 | `git rev-parse HEAD` = baseline do mandato de execução; `git status` limpo | saída literal | STOP |
| PC-2 | `git hash-object` do E00 = `a4dd84381b928727611a51147ba1a4c1d11b89ab` e md5 do arquivo = `45b6c35cca849ffbf49d22ec18e8283c`; md5 de L1/L3/L2 = tabela §0; `python3 tools/static_check.py` com `FAIL 0` | saídas literais | STOP |
| PC-3 | Canal = MCP Supabase `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`; nunca Dashboard/SQL Editor | parâmetro `project_id` de cada chamada, registrado | STOP |
| PC-4 | Mandato de execução assinado por Fabrício, citando este roteiro **v1.5**, o protocolo **v1.6** e o blob do E00 da PC-2 | referência do mandato | STOP |
| PC-5 | Nenhum `SET`/`set_config`/`CREATE TEMP`/sonda adicional; nenhuma consulta fora de L1, L3, E00 e L2 (a L4 só roda sob mandato próprio de adjudicação, nunca dentro da Etapa 1) | declaração no registro | STOP |

---

## 2. Sequência

Regra geral: **qualquer STOP encerra a etapa no passo em que ocorre**. Nenhum passo posterior é executado, **exceto** S1.4 (L2), e só no caso previsto.

| Passo | Chamada | Condição de entrada | Registrar | Saída |
|---|---|---|---|---|
| S1.1 | **L1** | PC-1…PC-5 OK | JSON integral `l1_channel` + horário | §4.1 conforme ⇒ S1.2; senão STOP |
| S1.2 | **L3** | S1.1 conforme | JSON integral `l3_concurrency` | §4.2 conforme ⇒ S1.3; senão STOP |
| S1.3 | **E00** (1ª leitura) | S1.2 conforme | JSON integral `e00_precheck` | §4.3 conforme ⇒ aguardar ≥ 60 s ⇒ S1.5. `g_p7_identity_pinned = false` ⇒ STOP ⇒ S1.4. `g_evt_inventory_complete`, `g_evt_ddl_only` ou `g_evt_all_adjudicated` = `false` ⇒ STOP (sem repetição; D-9). Único `g_no_concurrency = false` ⇒ S1.3-R. Qualquer outro desvio ⇒ STOP. |
| S1.3-R | **L3** e, ≥ 60 s após o S1.3, **E00** novo (repetição única, protocolo §3.4) | só se o **único** gate falso do S1.3 foi `g_no_concurrency` | as duas saídas + as do S1.3 | conforme ⇒ este E00 passa a ser a 1ª leitura ⇒ aguardar ≥ 60 s ⇒ S1.5; ainda falso ⇒ STOP |
| S1.4 | **L2** — **diagnóstico** | somente após STOP por `g_p7_identity_pinned = false` | tabela integral das 12 linhas | a etapa **permanece em STOP**; resultado vai para D-6 |
| S1.5 | **E00** (2ª leitura), ≥ 60 s após a 1ª leitura aceita | 1ª leitura conforme | JSON integral | §4.4 conforme ⇒ `READY FOR STAGE 2` (§5); senão STOP |

**Fora do roteiro:** a S1.6 do protocolo (`EXPLAIN (COSTS OFF)`, P9a) **não** faz parte da Etapa 1. P9a permanece **pendente de mandato próprio** antes do aceite de A2; ver P-2.

---

## 3. Consultas exatas

### 3.1 L1 — canal e sessão (md5 `0836c36a8d3749b1e7718223e064caf9`)

```sql
SELECT jsonb_build_object(
    'current_user',                        current_user,
    'session_user',                        session_user,
    'is_superuser',                        (SELECT rolsuper FROM pg_roles WHERE rolname = current_user),
    'reads_all_stats',                     pg_has_role(current_user, 'pg_read_all_stats', 'USAGE'),
    'in_recovery',                         pg_is_in_recovery(),
    'transaction_read_only',               current_setting('transaction_read_only'),
    'default_transaction_read_only',       current_setting('default_transaction_read_only'),
    'statement_timeout',                   current_setting('statement_timeout'),
    'lock_timeout',                        current_setting('lock_timeout'),
    'idle_in_transaction_session_timeout', current_setting('idle_in_transaction_session_timeout'),
    'standard_conforming_strings',         current_setting('standard_conforming_strings'),
    'server_version_num',                  current_setting('server_version_num'),
    'application_name',                    current_setting('application_name'),
    'backend_pid',                         pg_backend_pid(),
    'activity_rows_state_hidden',          (SELECT count(*) FROM pg_stat_activity
                                             WHERE pid <> pg_backend_pid()
                                               AND backend_type = 'client backend'
                                               AND state IS NULL),
    'visible_foreign_sessions',            (SELECT count(*) FROM pg_stat_activity a
                                             WHERE a.pid <> pg_backend_pid()
                                               AND a.backend_type = 'client backend'
                                               AND a.usename IS NOT NULL
                                               AND NOT pg_has_role(current_user, a.usename, 'MEMBER')
                                               AND a.state IS NOT NULL),
    'ec_table_owner',                      (SELECT jsonb_object_agg(c.relname, pg_get_userbyid(c.relowner) ORDER BY c.relname)
                                              FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                             WHERE n.nspname = 'public' AND c.relkind = 'r'
                                               AND c.relname LIKE 'card\_edition\_context%'),
    'checked_at',                          clock_timestamp()
) AS l1_channel;
```

### 3.2 L3 — concorrência (md5 `b7bc3700aeef278f6a79bd30e6a8d229`)

```sql
SELECT jsonb_build_object(
    'sessions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'pid', a.pid, 'usename', a.usename, 'application_name', a.application_name,
                    'backend_type', a.backend_type, 'state', a.state,
                    'wait_event_type', a.wait_event_type, 'wait_event', a.wait_event,
                    'xact_start', a.xact_start, 'state_change', a.state_change,
                    'backend_xid', a.backend_xid::text) ORDER BY a.backend_type, a.state, a.pid)
                  FROM pg_stat_activity a
                 WHERE a.pid <> pg_backend_pid() AND a.datname = current_database()), '[]'::jsonb),
    'locks_on_scope', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'pid', l.pid, 'relation', c.relname, 'mode', l.mode, 'granted', l.granted) ORDER BY c.relname, l.pid)
                  FROM pg_locks l JOIN pg_class c ON c.oid = l.relation
                 WHERE l.pid <> pg_backend_pid()
                   AND c.relname IN ('card_edition_context_trait','card_edition_context_profile',
                                     'card_edition_context_profile_trait','card_edition_context_external_mapping',
                                     'card_edition_context_external_mapping_trait','card_variant',
                                     'catalog_variant_import_job','catalog_variant_import_row',
                                     'catalog_admin_action_log','game')), '[]'::jsonb),
    'checked_at', clock_timestamp()
) AS l3_concurrency;
```

### 3.3 E00 — precheck

Submeter o **conteúdo integral** de `2830H_E00_precheck_inventory.sql` (blob `a4dd84381b928727611a51147ba1a4c1d11b89ab`, md5 `45b6c35cca849ffbf49d22ec18e8283c`), sem edição, sem recorte de comentários. O texto não é duplicado aqui, para não criar uma segunda fonte.

### 3.4 L2 — pinos, bruto × EOL (md5 `81d3472e69d8490849b16a0918c3e35d`) — SOMENTE DIAGNÓSTICO, SOMENTE APÓS STOP DE PINO

```sql
SELECT n.nspname || '.' || p.proname                                 AS fn,
       pg_get_function_identity_arguments(p.oid)                      AS identity_args,
       l.lanname                                                      AS language,
       p.prosecdef,
       p.provolatile::text                                            AS vol,
       p.proconfig,
       md5(p.prosrc)                                                  AS md5_raw,
       md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))            AS md5_lf,
       length(p.prosrc)                                               AS len_raw,
       length(p.prosrc) - length(replace(p.prosrc, chr(13), ''))      AS cr_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language  l ON l.oid = p.prolang
 WHERE (n.nspname = 'internal' AND p.proname IN (
            'seal_edition_context_composition','guard_edition_context_composition_immutable',
            'enforce_edition_context_signature_write','guard_edition_context_trait_active',
            'normalize_edition_context_external_mapping','enforce_edition_context_mapping_header',
            'seal_edition_context_external_mapping','guard_edition_context_mapping_composition_immutable',
            'enforce_edition_context_mapping_signature_write'))
    OR (n.nspname = 'public'     AND p.proname = 'normalize_external_catalog_value')
    OR (n.nspname = 'extensions' AND p.proname = 'unaccent')
 ORDER BY 1, 2;
```

### 3.5 L4 — event triggers, identidade completa e completude (md5 `f3670eb8f149064610055720b0636218`) — SOMENTE SOB MANDATO DE ADJUDICAÇÃO (D-9), FORA DA ETAPA 1

Objetivo: dar à adjudicação de D-9 a identidade completa de cada event trigger e provar, na **mesma** leitura, que nenhum trigger ficou fora da saída.
- Identidade: os 12 atributos pinados pelo E00, mais `fn_resolved`, md5 bruto, comprimento e corpo.
- Completude: `catalog_count` e `catalog_names` são lidos direto de `pg_event_trigger`; o inventário usa `LEFT JOIN`, para que um trigger sem função resolvida apareça com `fn_resolved = false` em vez de sumir.
- Integridade: `triggers_md5` permite conferir localmente o texto recebido.

Só SELECT. O resultado **não** é critério de aceite de nenhuma etapa: alimenta, linha a linha, a `evt_allowlist` do E00, que só é preenchida por mandato de correção posterior.

```sql
WITH cat AS (
    SELECT count(*)                                  AS catalog_count,
           jsonb_agg(e.evtname::text ORDER BY e.evtname) AS catalog_names
      FROM pg_catalog.pg_event_trigger e
),
inv AS (
    SELECT jsonb_agg(jsonb_build_object(
             'name',         e.evtname,
             'event',        e.evtevent,
             'enabled',      e.evtenabled,
             'tags',         e.evttags,
             'owner',        pg_get_userbyid(e.evtowner),
             'fn_resolved',  p.oid IS NOT NULL,
             'fn',           n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
             'fn_language',  l.lanname,
             'fn_owner',     pg_get_userbyid(p.proowner),
             'fn_secdef',    p.prosecdef,
             'fn_config',    p.proconfig,
             'fn_extension', (SELECT x.extname
                                FROM pg_depend d
                                JOIN pg_extension x ON x.oid = d.refobjid
                               WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
                                 AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e'),
             'fn_md5_raw',   md5(p.prosrc),
             'fn_md5_lf',    md5(replace(p.prosrc, chr(13) || chr(10), chr(10))),
             'fn_len',       length(p.prosrc),
             'fn_src',       p.prosrc)
           ORDER BY e.evtname) AS triggers
      FROM pg_catalog.pg_event_trigger e
      LEFT JOIN pg_proc p      ON p.oid = e.evtfoid
      LEFT JOIN pg_namespace n ON n.oid = p.pronamespace
      LEFT JOIN pg_language l  ON l.oid = p.prolang
)
SELECT jsonb_build_object(
         'l4_event_triggers', jsonb_build_object(
           'checked_at',               clock_timestamp(),
           'session_replication_role', current_setting('session_replication_role'),
           'catalog_count',            cat.catalog_count,
           'catalog_names',            COALESCE(cat.catalog_names, '[]'::jsonb),
           'inventory_count',          jsonb_array_length(COALESCE(inv.triggers, '[]'::jsonb)),
           'inventory_complete',       cat.catalog_count = jsonb_array_length(COALESCE(inv.triggers, '[]'::jsonb)),
           'triggers_md5',             md5(COALESCE(inv.triggers, '[]'::jsonb)::text),
           'triggers',                 COALESCE(inv.triggers, '[]'::jsonb)
         )
       ) AS l4
  FROM cat, inv;
```

**Validação da saída (qualquer falha ⇒ leitura INVÁLIDA; nada é concluído, nenhuma linha candidata é preparada):**
1. As chaves `checked_at`, `session_replication_role`, `catalog_count`, `catalog_names`, `inventory_count`, `inventory_complete`, `triggers_md5` e `triggers` estão presentes.
2. `inventory_complete = true` **e** `catalog_count = inventory_count` = número de elementos de `triggers` = número de elementos de `catalog_names`.
3. O conjunto dos `name` de `triggers` é igual ao de `catalog_names`.
4. Todo elemento tem `fn_resolved = true`. Um `false` é divergência a adjudicar e nunca vira exceção.
5. O md5 recalculado localmente sobre o texto de `triggers`, no formato de texto do `jsonb`, é igual a `triggers_md5`. Se não for, houve truncamento ou alteração no transporte.
6. `catalog_count` é igual ao número de event triggers do último E00 registrado. Se for diferente, registrar a divergência e adjudicar só depois de uma nova E00.

Os critérios de mérito (evento, tags, donos, `SECURITY DEFINER`, `proconfig`, extensão, corpo) estão em `LIVE-STAGE1-STOP-ADJUDICATION-EVIDENCE.md` §2.3.

---

## 4. Evidências esperadas e critérios

### 4.1 L1 — conforme se **todos**

| Campo | Esperado | Divergência |
|---|---|---|
| `in_recovery` | `false` (primário) | STOP |
| `standard_conforming_strings` | `on` | STOP |
| `server_version_num` | ≥ `170000` | STOP (C-6; 1.12 depende de `MAINTAIN`) |
| `lock_timeout` | `'0'` | STOP · D-4 |
| visibilidade de `pg_stat_activity` | via 1 `is_superuser = true`, **ou** via 2 `reads_all_stats = true`, **ou** via 3 `visible_foreign_sessions ≥ 1` (registrar qual via) | nenhuma via ⇒ STOP · D-5. `activity_rows_state_hidden = 0` **sozinho não prova acesso**. |
| `ec_table_owner` | as 5 tabelas `card_edition_context*` com dono = `current_user`, **ou** `is_superuser = true` | STOP |
| `transaction_read_only` / `default_transaction_read_only` | **registrar** | não é STOP na Etapa 1 (é pré-requisito da Etapa 3) |
| `current_user`, `session_user`, `statement_timeout`, `idle_in_transaction_session_timeout`, `application_name`, `backend_pid`, `checked_at` | registrar | — |

### 4.2 L3 — conforme se

- `locks_on_scope = []`;
- nenhuma **outra** sessão `client backend` em `active`, `idle in transaction` ou `idle in transaction (aborted)`. A própria sessão já é excluída pela consulta (`pid <> pg_backend_pid()`).
- **Qualquer** outra sessão `client backend` ativa ou em transação ⇒ **STOP**. Classificar a sessão nominalmente (usuário, `application_name`, estado) serve **apenas** como registro para diagnóstico. Não dispensa o STOP e não dispensa o `g_no_concurrency` do E00.
- Sessões em `idle`, ou de outros `backend_type`, são registradas sem efeito de gate.
- **Precedência:** o protocolo v1.3 §3.2 e §6.3 adota este mesmo critério. A precedência formal continua sendo do protocolo; não há conflito.

### 4.3 E00 (cada leitura) — conforme se **todos**

1. Nenhum erro de execução. Qualquer SQLSTATE ⇒ STOP: defeito de harness, com mandato de correção.
2. Os **24** gates presentes e `true`; `gate_pass = true`. Qualquer `false` ou `NULL` ⇒ STOP, com a exceção única de S1.3-R. Os gates são:
   - `g_objects_1x`, `g_objects_D`, `g_roles_1_12`, `g_pg17_maintain_privilege`, `g_game_source`;
   - `g_freeze_canonical_equal`, `g_no_sequences_touched_now`;
   - `g_p7_all_classified`, `g_p7_identity_pinned` (pino com EOL normalizado, D-6), `g_p7_search_path_safe`, `g_p7_no_external_or_dynamic`, `g_p7_no_ddl`, `g_p7_lexically_supported`, `g_p7_no_unresolved`, `g_p7_no_unqualified_dml`, `g_p7_writes_in_scope`, `g_p7_closure_complete`;
   - `g_no_rules`, `g_evt_inventory_complete`, `g_evt_ddl_only`, `g_evt_all_adjudicated`, `g_rls_bypass`, `g_no_residue`, `g_no_concurrency`.
   - A saída chama `g_objects_d` (minúsculo) o gate `g_objects_D`: o PostgreSQL dobra o alias não citado. É o mesmo gate.
3. `d_canon_diff = []`. O estado é o canônico do FREEZE:
   - vocabulário 115 / 144 / 196 / 122; `mapping_null_signature` 0;
   - `card_variant` 24.893; `card_variant_ec_nonnull` 0;
   - staging 26.127, com a distribuição de `staging_status` do bloco FREEZE-CANON; tri-state U 1.092 / N 550 / A 0;
   - canceladas sem chave 847 / 415; lineage 23.955 / 1.129;
   - jobs 145 (STAGED 63 / COMPLETED 71 / FAILED 8 / CANCELLED 3), 0 em voo;
   - `staging_max_upd_utc` e `jobs_max_upd_utc` iguais às constantes.
4. **Identidades P7 não-nativas** (`d_p7_functions`, `gate_scope = true`, schema ≠ `pg_catalog`, campo `fn`) = exatamente as 12 da allowlist (protocolo §3.3). A mais ou a menos ⇒ STOP.
5. `d_p7_unqualified_calls` sem `UNRESOLVED`/`DENIED`; `d_p7_writes` com alvos só nas 5 tabelas EC; `d_p7_unresolved_qualified = []`; `d_p7_unqualified_writes = []`.
6. `d_sequences` sem entrada para as 3 tabelas tocadas por E01. O inventário das demais é registrado.
7. `d_event_triggers` registrado **integralmente** (12 atributos de identidade + md5 bruto); os 6 event triggers aprovados em D-9 casam com as 6 linhas da `evt_allowlist`; `d_evt_catalog_count` = número de linhas de `d_event_triggers`; `d_evt_unadjudicated = []`; cada exceção adjudicada citada no registro com a sua justificativa (D-9); `d_evt_allowlist_absent` registrado (sem efeito de gate); `d_p7_rules` sem regra nas 5 tabelas EC; `d_publications` registrado.
7a. `d_p7_eol_normalized` registrado. Cada item listado precisa ter `body_md5_lf` = pino e `crlf_count = cr_count` (só CRLF); o registro cita o md5 bruto (`body_md5`) como evidência. Item novo, não adjudicado em D-6, é registrado como observação para auditoria — a identidade já está provada pelo pino normalizado.
8. Saída **não truncada**: presença de `d_baseline`, `d_baseline_md5`, `d_session` e das 17 chaves canônicas em `d_baseline`. Truncada ⇒ rodada inválida (não é FAIL); nova rodada só com novo mandato.

### 4.4 Segunda leitura (S1.5) — adicionalmente

- `d_baseline_md5` (S1.5) = `d_baseline_md5` (1ª leitura aceita). Diferente ⇒ STOP (estado instável sob FREEZE).
- Intervalo entre os `d_session.checked_at` das duas leituras ≥ 60 s.

---

## 5. Resultado da Etapa 1

| Resultado | Condição | Consequência |
|---|---|---|
| **READY FOR STAGE 2** | PC-1…PC-5, S1.1, S1.2, 1ª leitura e S1.5 conformes | Registro no README (Registro da rodada) + `docs/log.md`. **Não** autoriza a Etapa 2, que exige mandato próprio. |
| **STOP (com código)** | qualquer desvio da §4 | Registro do passo, gate/campo e saída integral; nenhum passo posterior (salvo S1.4). Decisão de Fabrício. |
| **INVÁLIDA** | saída truncada ou canal fora de PC-3 | Nada é concluído; nova rodada só com novo mandato. |

Nenhum caso da 2830 é declarado PASS nesta etapa.

---

## 6. Pontos de decisão (antes do mandato de execução)

| # | Decisão | Recomendação técnica |
|---|---|---|
| P-1 | Mandato de execução da Etapa 1, citando baseline, este roteiro v1.5, o protocolo v1.6 e o blob do E00 (PC-2) | — |
| P-2 | S1.6 (`EXPLAIN (COSTS OFF)` do E00, P9a) | **Fora da Etapa 1.** Executar o E00 **não** prova a forma do plano: a execução só-leitura mede tempo (AD-2), enquanto P9a exige `EXPLAIN (COSTS OFF)` registrado. **P9a permanece PENDENTE** e exige **mandato próprio** antes do aceite de A2. Nenhum resultado da Etapa 1 conta como P9a. |
| P-3 | Quem executa: agente via MCP ou Fabrício | agente via MCP, sob mandato (padrão das rodadas anteriores); Fabrício, se preferir o canal manual — o critério PC-3 continua exigindo MCP |
| P-4 | Após qualquer STOP: D-4 (lock_timeout), D-5 (visibilidade), D-6 (pinos), D-9 (event triggers) ou mandato de correção do harness | por caso |

Decisões ainda pendentes e **não** resolvidas aqui: D-1 (ambiente isolado sem custo, P14 obrigatório), D-2, D-3, D-7 e D-8 do protocolo.

---

## 7. Achados desta validação (não corrigidos nesta rodada)

| # | Achado | Tratamento |
|---|---|---|
| A-1 | Protocolo §3.4 não enumera, um a um, STOP para os gates não-P7 (`g_objects_*`, `g_roles_1_12`, `g_pg17_maintain_privilege`, `g_game_source`, `g_no_sequences_touched_now`, `g_no_rules`, `g_no_enabled_event_triggers`, `g_rls_bypass`, `g_no_residue`). Estão cobertos por `gate_pass = true` (§3.3). | Explicitado neste roteiro (§4.3.2). Sem mudança de critério. |
| A-2 | Protocolo §3.4 não diz se um desvio da L1 (`in_recovery`, `standard_conforming_strings`, versão, dono) interrompe antes do E00. | Este roteiro fixa: STOP no passo (§2). Mais restritivo, nunca mais permissivo. |
| A-3 | `README.md` do harness, "Dependências" item 5, dizia "≤ 9 inserts". O E01 faz 11 tentativas de INSERT (4 positivas, 7 negativas), conforme o protocolo §5. | **Corrigido** em `…-READINESS-CORRECTION-01`. |
| A-4 | Protocolo v1.2 §3.2 (L3) admitia sessão classificada como plataforma, em conflito com o §4.2 deste roteiro. | **RESOLVIDO** em `…-READINESS-CLOSEOUT-01`: o protocolo v1.3 §3.2/§6.3 adota o STOP para qualquer outra sessão `client backend` ativa ou em transação, com a classificação nominal só diagnóstica. A precedência formal do protocolo está preservada. |

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-EXECUTION-READINESS-01`, baseline `1f3b72dc`).** Roteiro operacional da Etapa 1: pré-condições, sequência L1 → L3 → E00 → (≥ 60 s) → E00, repetição única por concorrência, L2 só como diagnóstico após STOP de pino, consultas exatas com md5, evidências esperadas por campo, resultados possíveis e pontos de decisão. Nenhum SQL executado; não autoriza a Etapa 2. |
| 1.1 | **Correção (2026-09-26, `BATCH12-2830-LIVE-STAGE1-READINESS-CORRECTION-01`).** (1) L3: qualquer outra sessão `client backend` ativa ou em transação = STOP; a classificação nominal é só registro e não dispensa `g_no_concurrency` (A-4 registra a precedência sobre o protocolo §3.2). (2) P-2: `EXPLAIN` fora da Etapa 1; P9a pendente de mandato próprio antes do aceite de A2; execução não prova a forma do plano. (3) A-3 marcado como corrigido (README). SQL e md5 das consultas inalterados; md5 do E00 = `d00b7cec2523b2ee3de9565a93dbae57`. |
| 1.2 | **Fechamento de A-4 (2026-09-26, `BATCH12-2830-LIVE-STAGE1-READINESS-CLOSEOUT-01`).** O protocolo foi alinhado (v1.3), e a nota de precedência do §4.2 e o achado A-4 passam a RESOLVIDO. Critérios, sequência, SQL e md5 inalterados. |
| 1.3 | **Referências (2026-09-26, `BATCH12-2830-LIVE-STAGE1-READINESS-CLOSEOUT-02`).** Cabeçalho (Autoridade), PC-4 e P-1 passam a citar o protocolo **v1.3**, a versão que contém o alinhamento de A-4. As menções históricas a v1.2 (A-4 e revisão 1.2) e a declaração de identidade dos blocos SQL (§0) ficam como estão. Critérios, consultas, md5 e sequência inalterados. |
| 1.4 | **Correção local (2026-09-26, `BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01` → `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`), não commitada, pendente de auditoria.** Após o STOP da Tentativa 03:<br>• E00 corrigido: blob `88e9e7a4…`, md5 `a9352afc…`, **24 gates**. Inclui pino P7 com EOL normalizado (D-6), `g_p7_no_ddl`, `g_evt_inventory_complete` (G-3) e `g_evt_ddl_only` + `g_evt_all_adjudicated` com identidade de 12 atributos (G-4) e justificativa obrigatória.<br>• §3.5 L4 revisada: contagem e nomes lidos direto do catálogo, `LEFT JOIN`, `triggers_md5`, validação de completude; md5 `f3670eb8…`. Só sob mandato de adjudicação (D-9), fora da Etapa 1.<br>• §4.3 itens 2, 7 e 7a.<br>• Cabeçalho, §0, PC-2, PC-4 e P-1 reconciliados com o protocolo v1.5, o E00 novo e a L4 (G-5); os hashes anteriores ficam só como histórico.<br>L1, L2 e L3 inalterados. Compilação PostgreSQL pendente. |
| 1.5 | **D-9 incorporada localmente (2026-09-27, `BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`), não commitada, pendente de auditoria.**<br>• E00 com as 6 exceções aprovadas em D-9 na `evt_allowlist`: blob `a4dd8438…`, md5 `45b6c35c…`.<br>• Cabeçalho, §0, PC-2, PC-4, §3.3, §4.3 item 7 e P-1 reconciliados com o protocolo v1.6; o E00 `88e9e7a4…` fica só como histórico.<br>L1, L2, L3 e L4 inalterados. Compilação PostgreSQL pendente. |
