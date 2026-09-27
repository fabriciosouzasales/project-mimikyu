# 2830H — Registro de execução da Etapa 1 (LIVE)

| Campo | Valor |
|---|---|
| **Natureza** | Registro das tentativas da Etapa 1 do `LIVE-VALIDATION-PROTOCOL.md` v1.4, executadas pelo `LIVE-STAGE1-RUNBOOK.md` v1.3. |
| **Estado atual** | **Etapa 1 não concluída. Nenhum PASS formal registrado.** Ocorrência 01: governança, consultas feitas fora da atribuição. Tentativa 02: STOP em PC-1, sem SQL. Tentativa 03: **STOP em S1.3 (E00)** — `g_p7_identity_pinned = false` (L2: TRANSPORT/EOL-ONLY) e `g_no_enabled_event_triggers = false`; adjudicação documental feita. **Correção do harness aplicada localmente** (`…-CORRECTION-01`), não commitada e não compilada no PostgreSQL. D-9 pendente e `evt_allowlist` vazia. Etapa 2 **não autorizada**. |
| **Papéis** | **Claude**: único executor autorizado. **ChatGPT**: auditor independente, sem atribuição de execução. **Fabrício**: autorizações, commit e push. |
| **FREEZE** | ATIVO. |

---

## Ocorrência 01 — consultas executadas pelo auditor (ocorrência de governança)

**Registrada em:** `BATCH12-2830-LIVE-STAGE1-CHANNEL-BLOCKER-01`. **Reclassificada em:** `BATCH12-2830-LIVE-STAGE1-PC1-STOP-CLOSEOUT-01` (2026-09-26), a partir das informações de Fabrício no mandato `BATCH12-2830-LIVE-STAGE1-EXECUTION-01`.

### 1. Fatos

| Item | Registro |
|---|---|
| Quem executou | **ChatGPT**, fora de sua atribuição de auditor. Não houve mandato de execução em nome dele. |
| HEAD na ocasião | `44d8c5279b13972376b10254de01404053aa5cc4` (`44d8c52`), segundo a informação recebida |
| L1 (md5 `0836c36a…`) | executada via MCP `execute_sql`; retornou resultado **informado como conforme** |
| L3 (md5 `b7bc3700…`) | **tentativa bloqueada pela ferramenta** por configuração de segurança. **Nenhum resultado SQL** foi obtido. **Não há evidência de que a consulta tenha sido executada no PostgreSQL.** |
| E00 | **não executado** |
| Efeito no banco | nenhum conhecido. L1 é SELECT; da L3 não há evidência de chegada ao banco. |

A saída integral da L1, o texto literal da mensagem de bloqueio e os horários **não foram anexados** a este registro. Nada aqui os substitui.

### 2. Classificação

- **Ocorrência de governança, não rodada da Etapa 1.** As consultas foram feitas por quem não tinha atribuição de execução e sem mandato de execução.
- **A L1 não é PASS formal da Etapa 1.** O resultado não é evidência para nenhuma rodada, atual ou futura (decisão de Fabrício no mandato `…-EXECUTION-01`).
- **A L3 bloqueada não é erro do PostgreSQL**: não há SQLSTATE, não há resultado e não há evidência de execução no banco. Por analogia com o protocolo §3.4 ("saída truncada pelo canal") e com o roteiro §5 ("INVÁLIDA"), a tentativa fica como **INVÁLIDA — bloqueio de canal**.
- Nenhum caso da 2830 e nenhum gate do E00 foram avaliados.

### 3. Bloqueio de canal — alternativas (sem tocar no SQL nem no md5 da L3)

O diagnóstico da camada do bloqueio continua pendente e depende da mensagem literal. As camadas possíveis:
- (a) permissão do cliente;
- (b) política do conector ou da organização;
- (c) filtro de segurança do agente;
- (d) configuração do servidor MCP.

Como o bloqueio ocorreu na ferramenta usada pelo auditor, **não se sabe** se ele se repete no canal do executor autorizado. Só a execução formal da L3 pelo Claude, sob mandato, responde isso.

| # | Alternativa | Mantém canal MCP? | Revisão do protocolo? | Avaliação |
|---|---|---|---|---|
| A1 | Aprovar explicitamente a chamada no controle de permissão da ferramenta | sim | não | autorizável, se (a) |
| A2 | Ajustar a permissão do conector Supabase MCP para `execute_sql` no projeto `qjfutqujxrbzgrtkpgkg` | sim | não | autorizável, se (b) |
| A3 | Liberação explícita do conteúdo da L3 junto ao filtro do agente, com a consulta **inalterada** | sim | não | autorizável, se (c) |
| A4 | Revisar a configuração do servidor MCP, sem trocar de servidor | sim | não | autorizável, se (d) |
| A5 | Mesmo servidor Supabase MCP, outro cliente operado por Fabrício, mesmo `project_id` | sim | não; o registro deve identificar o cliente | autorizável |
| A6 | `psql` / Supabase CLI | **não** | **sim** (PC-3 / §2.2) | não recomendado agora |
| A7 | Dashboard / SQL Editor | não | — | **proibido** |
| A8 | Alterar, fragmentar ou substituir a L3 | — | — | **proibido** |

**Revisão formal do protocolo:**
- desnecessária para A1–A5;
- obrigatória para A6;
- **recomendada, não bloqueante:** uma linha explícita no §3.4 — *"chamada bloqueada pela ferramenta, sem SQLSTATE e sem resultado ⇒ rodada INVÁLIDA (STOP operacional); não é FAIL; retomada só com novo mandato, desde S1.0"*. **Não aplicada.**

---

## Tentativa 02 — Claude, mandato `BATCH12-2830-LIVE-STAGE1-EXECUTION-01`: STOP em PC-1

**Data:** 2026-09-27 01:04 UTC (verificação local do repositório).

| Item | Registro |
|---|---|
| Executor | **Claude** (autorizado pelo mandato) |
| PC-1 | **FALHOU.** HEAD = `44d8c5279b13972376b10254de01404053aa5cc4` (conforme), mas a **árvore não estava limpa**. Havia três alterações documentais não commitadas, vindas de `…-CHANNEL-BLOCKER-01`: `harness/README.md` (M), `docs/log.md` (M) e `harness/LIVE-STAGE1-EXECUTION-RECORD.md` (novo) |
| PC-2 (verificação local, sem SQL) | E00 blob `97410c3a…`, md5 `d00b7cec2523b2ee3de9565a93dbae57`; L1 `0836c36a…`, L3 `b7bc3700…` e L2 `81d3472e…`: todos conferem. Roteiro v1.3, protocolo v1.4 e 2830 (`b4647dcb`) idênticos ao HEAD. |
| PC-3 / PC-5 | não exercidas |
| SQL submetido | **nenhum**: L1, L3, E00 e L2 não foram executadas |
| Resultado | **STOP em PC-1** (roteiro §1). Não houve dispensa da PC-1. |
| Caminho escolhido (auditoria) | **publicação documental**: commit destes três arquivos por Fabrício, gerando novo baseline, e novo mandato de execução com o novo HEAD. Sem dispensa da PC-1. |

---

## Retomada (após a Tentativa 02 — executada como Tentativa 03)

1. Fabrício faz o commit dos três arquivos documentais (`harness/LIVE-STAGE1-EXECUTION-RECORD.md`, `harness/README.md`, `docs/log.md`). O novo HEAD passa a ser o baseline.
2. Novo mandato de execução, citando:
   - o novo HEAD;
   - o `LIVE-STAGE1-RUNBOOK.md` v1.3;
   - o `LIVE-VALIDATION-PROTOCOL.md` v1.4;
   - este registro.
3. **Tentativa 03 pelo Claude, desde S1.0:**
   - PC-1…PC-5 integralmente, com a árvore limpa;
   - **L1 nova** (a L1 da Ocorrência 01 não é aproveitada);
   - depois L3 → E00 → (≥ 60 s) → E00, conforme o roteiro §2;
   - L2 só como diagnóstico após STOP de pino.
4. Se a L3 for bloqueada pela ferramenta do executor: STOP operacional (INVÁLIDA), diagnóstico da camada com a mensagem literal, e escolha entre A1–A5 por Fabrício. Nenhuma nova tentativa na mesma rodada.
5. `READY FOR STAGE 2` só com todos os critérios do roteiro §4 atendidos. A Etapa 2 continua exigindo mandato próprio.

---

## Tentativa 03 — Claude, mandato `BATCH12-2830-LIVE-STAGE1-EXECUTION-02`: STOP em S1.3

**Data:** 2026-09-27, 01:14–01:17 UTC (horários de `checked_at`, relógio do banco). **Baseline:** HEAD `b8925ed571127be8f05fac98f6a3afbad5fe74a3`. **Canal:** Supabase MCP `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`, uma consulta por chamada, texto integral e sem edição.

### 1. Pré-condições

| PC | Resultado |
|---|---|
| PC-1 | **PASS.** HEAD = `b8925ed5…`; árvore limpa (`git status --porcelain` = 0 linhas). Verificada antes de qualquer alteração documental. |
| PC-2 | **PASS.** E00 blob `97410c3a799d8fdec86cc6d3735993ab224f6c9e`, md5 `d00b7cec2523b2ee3de9565a93dbae57`, 35.744 bytes; L1 `0836c36a…`, L3 `b7bc3700…` e L2 `81d3472e…` iguais no roteiro e no protocolo; protocolo v1.4, roteiro v1.3, este registro v1.1 e 2830 (`b4647dcb…`) idênticos ao HEAD. |
| PC-3 | **PASS.** Canal MCP `execute_sql` no projeto `qjfutqujxrbzgrtkpgkg`. Nenhuma chamada bloqueada pela ferramenta. |
| PC-4 | **PASS.** Mandato `BATCH12-2830-LIVE-STAGE1-EXECUTION-02`. |
| PC-5 | **PASS.** Só as consultas do roteiro (L1, L3, E00, L2). Sem `set_config`, sem `TEMP`, sem sondas. |

### 2. Passos

| Passo | Consulta (md5) | `checked_at` (banco) | Classificação |
|---|---|---|---|
| S1.1 | L1 (`0836c36a…`) | 01:14:10.602003Z | **CONFORME** |
| S1.2 | L3 (`b7bc3700…`) | 01:14:24.605019Z | **CONFORME** |
| S1.3 | E00 (`d00b7cec…`), 1ª leitura | 01:16:20.815355Z | **STOP** — 2 gates falsos |
| S1.3-R | — | — | **não aplicável** (`g_no_concurrency = true`; os gates falsos são outros) |
| S1.4 | L2 (`81d3472e…`), diagnóstico | — | executada por `g_p7_identity_pinned = false`; a etapa permanece em STOP |
| S1.5 | — | — | **não executado** |

### 3. Fundamentação

**S1.1 — L1 (roteiro §4.1): conforme.**
- `in_recovery = false`; `standard_conforming_strings = on`; `server_version_num = 170006` (≥ 170000); `lock_timeout = '0'`.
- Visibilidade de `pg_stat_activity` pela **via 2**: `reads_all_stats = true`. A via 3 também se verifica (`visible_foreign_sessions = 2`).
- `ec_table_owner`: as 5 tabelas EC com dono `postgres` = `current_user` (`is_superuser = false`).
- Registrados: `transaction_read_only = off` e `default_transaction_read_only = off` (não é STOP na Etapa 1); `current_user` e `session_user` `postgres`; `statement_timeout = 2min`; `idle_in_transaction_session_timeout = 0`; `application_name = mgmt-api`; `backend_pid = 3460387`.

**S1.2 — L3 (roteiro §4.2): conforme.**
- `locks_on_scope = []`.
- 12 outras sessões `client backend`, **todas `idle`**: 10 `authenticator` / `PostgREST 14.5`; 1 `supabase_admin` / `postgres_exporter`; 1 `supabase_admin` sem `application_name`. Nenhuma em `active`, `idle in transaction` ou `idle in transaction (aborted)`.
- Outros `backend_type`, registrados sem efeito de gate: `pg_cron launcher` (estado nulo) e `pg_net 0.20.4 worker` (`idle`).
- Diferente da Ocorrência 01, a L3 **não** foi bloqueada pela ferramenta.

**S1.3 — E00, 1ª leitura (roteiro §4.3): STOP.**
- Sem erro de execução. 21 gates presentes; **19 `true` e 2 `false`**; `gate_pass = false`.
- **STOP-1 · `g_p7_identity_pinned = false`.** Única função em `ALLOWLIST_MISMATCH`: `public.normalize_external_catalog_value(p_value text)`, `body_md5` LIVE `81361bb8f52ce142803d69c2b3028ae8` × pino `1fdc2e7ebe2297f8db85be4aad2e5d33`. Os demais pinos (linguagem, `SECURITY DEFINER`, volatilidade, `proconfig`) não são distinguidos pelo E00; ver S1.4.
- **STOP-2 · `g_no_enabled_event_triggers = false`.** `d_event_triggers` tem 6 event triggers com `enabled = 'O'`:
  - `sql_drop`: `issue_graphql_placeholder`, `pgrst_drop_watch`;
  - `ddl_command_end`: `pgrst_ddl_watch`, `issue_pg_cron_access`, `issue_pg_net_access`, `issue_pg_graphql_access`.
  - Os nomes remetem a componentes da plataforma (PostgREST, pg_cron, pg_net, pg_graphql). A origem **não foi verificada** nesta tentativa.
  - Nenhuma decisão D-1…D-8 do protocolo cobre este caso. O critério não foi reinterpretado: continua STOP.
- **Demais critérios da §4.3.** Registrados para a auditoria; não alteram o resultado:
  - `d_canon_diff = []`: `g_freeze_canonical_equal = true`, estado igual ao canônico do FREEZE.
  - Identidades P7 não nativas (`gate_scope = true`, fora de `pg_catalog`) = **exatamente as 12** da allowlist.
  - `d_p7_unqualified_calls` no escopo só com `KEYWORD`/`BUILTIN`; `d_p7_writes` só em `public.card_edition_context_profile` e `public.card_edition_context_external_mapping`, ambos existentes; `d_p7_unresolved_qualified = []`; `d_p7_unqualified_writes = []`.
  - `d_sequences = []`, `d_p7_rules = []` e `d_publications = []`.
  - RLS habilitada sem `FORCE` nas 10 tabelas; dono `postgres`.
  - `d_concurrency.other_sessions_in_txn = 0`.
- **Saída completa.** `d_baseline` tem 22 chaves, entre elas as 17 canônicas, e `d_baseline_md5 = 5c329d5e38a7e369cc100ab08953e1a7`. O md5 foi recalculado localmente sobre o texto de `d_baseline` e é igual ao informado. `d_session` está presente.
- **Observações sem efeito de gate:**
  - (a) A chave de saída é `g_objects_d`, em minúsculas: o PostgreSQL dobra o alias não citado `g_objects_D`. É o mesmo gate, com valor `true`.
  - (b) Fora do escopo do gate (`gate_scope = false`) há 7 funções `UNCLASSIFIED`, 4 delas com `search_path_unsafe = true`. Isso é inventário previsto pelo cabeçalho do E00 e não bloqueia.
  - (c) Os horários deste registro vêm do relógio do banco. Ele estava cerca de 1,5 min atrás do relógio do ambiente de verificação local.

**S1.4 — L2, diagnóstico (protocolo §3.4, adjudicação por linha):** 12 linhas.

| Função | `md5_raw` = pino | `md5_lf` = pino | `cr_count` | Classificação |
|---|---|---|---|---|
| 9 funções `internal.*` | sim | sim | 0 | IDÊNTICO |
| `extensions.unaccent(text)` · `extensions.unaccent(regdictionary, text)` | — (C, sem pino de corpo) | — | 0 | `language = c`, conforme; E00 = `PURE_EXT` |
| `public.normalize_external_catalog_value(p_value text)` | **não** (`81361bb8…`) | **sim** (`1fdc2e7e…`) | **2** | **TRANSPORT/EOL-ONLY** |

- Os demais atributos pinados de `normalize_external_catalog_value` conferem: `sql`, `prosecdef = false`, `vol = s`, `proconfig = {search_path=""}`.
- Consequência (protocolo §3.4): a etapa segue em STOP e o resultado vai para **D-6**. Nenhum pino foi editado.

### 4. Resultado

**STOP em S1.3 (E00, 1ª leitura).** Códigos:

1. `g_p7_identity_pinned = false`. L2: **TRANSPORT/EOL-ONLY** em `public.normalize_external_catalog_value`. Vai para D-6.
2. `g_no_enabled_event_triggers = false`: 6 event triggers habilitados no LIVE. Não há decisão prevista; exige adjudicação de Fabrício.

**Não é `READY FOR STAGE 2`.** S1.5 não foi executado. E01, E02 e E99 não foram executados. A Etapa 2 não foi iniciada. Todas as consultas eram SELECT, sem escrita no banco. Harness, consultas, md5, pinos e 2830 não foram alterados. FREEZE ATIVO.

### 5. Pendências para retomada (decisões de Fabrício)

1. **D-6.** Adjudicar o TRANSPORT/EOL-ONLY de `public.normalize_external_catalog_value`. Se aceito, é necessário um mandato de correção do harness, numa destas formas:
   - pinar o md5 bruto do LIVE, com proveniência;
   - normalizar o EOL antes do md5, nos dois lados.
2. **Event triggers.** Adjudicar o critério `g_no_enabled_event_triggers` frente aos 6 event triggers habilitados no LIVE. Mudar o critério exige mandato de correção do harness e/ou do protocolo. Nada foi alterado aqui.
3. **Nova tentativa** (Tentativa 04) só com novo mandato, desde S1.0: PC-1…PC-5, L1 nova, L3, E00 → (≥ 60 s) → E00.

### 6. Evidências integrais

As saídas estão como retornadas pelo `execute_sql`, com o invólucro de linha removido.

**S1.1 — L1**

```json
{"l1_channel":{"checked_at":"2026-09-27T01:14:10.602003+00:00","backend_pid":3460387,"in_recovery":false,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","session_user":"postgres","ec_table_owner":{"card_edition_context_trait":"postgres","card_edition_context_profile":"postgres","card_edition_context_profile_trait":"postgres","card_edition_context_external_mapping":"postgres","card_edition_context_external_mapping_trait":"postgres"},"reads_all_stats":true,"application_name":"mgmt-api","statement_timeout":"2min","server_version_num":"170006","transaction_read_only":"off","visible_foreign_sessions":2,"activity_rows_state_hidden":0,"standard_conforming_strings":"on","default_transaction_read_only":"off","idle_in_transaction_session_timeout":"0"}}
```

**S1.2 — L3**

```json
{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:14:20.035682+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-26T05:29:27.073328+00:00","wait_event_type":"Client","application_name":""},{"pid":3459608,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:02:01.49232+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3459637,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:05:01.590052+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3459640,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:05:01.933924+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3459667,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:07:00.953417+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3459668,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:07:01.04361+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3459706,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:10:01.829387+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3459707,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:10:01.991667+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3460353,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:12:01.759765+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3460354,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T01:12:01.960306+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T01:12:04.002333+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T01:14:24.605019+00:00","locks_on_scope":[]}}
```

**S1.3 — E00 (1ª leitura)**

```json
{"e00_precheck":{"d_objects":{"indexes_D":5,"indexes_1x":4,"game_pokemon":1,"source_tcgdex":1,"constraints_1x":7,"roles_anon_authenticated":2},"d_session":{"checked_at":"2026-09-27T01:16:20.815355+00:00","backend_pid":3460409,"current_user":"postgres","is_superuser":false,"lock_timeout":"0","statement_timeout":"2min","server_version_num":"170006","db_role_setting_rows":9},"gate_pass":false,"d_baseline":{"jobs":145,"trait":115,"lineage":{"matched":1129,"resulting":23955},"mapping":122,"profile":144,"action_log":1352,"card_variant":24893,"marker_trait":0,"staging_rows":26127,"mapping_trait":122,"profile_trait":196,"jobs_by_status":{"FAILED":8,"STAGED":63,"CANCELLED":3,"COMPLETED":71},"jobs_in_flight":0,"marker_mapping":0,"marker_profile":0,"staging_status":{"VALID/PENDING":415,"VALID/INSERTED":23240,"INVALID/PENDING":6,"VALID/UNCHANGED":717,"INVALID/UNCHANGED":80,"NEEDS_REVIEW/PENDING":1656,"NEEDS_REVIEW/UNCHANGED":13},"jobs_max_upd_utc":"2026-09-19T00:48:41.964146Z","staging_max_upd_utc":"2026-09-20T19:57:04.771758Z","operational_tristate":{"A":0,"N":550,"U":1092},"cancelled_without_key":{"total":847,"valid_pending":415},"mapping_null_signature":0,"card_variant_ec_nonnull":0},"d_p7_rules":[],"g_no_rules":true,"d_p7_writes":[{"target":"public.card_edition_context_profile","writer":"internal.seal_edition_context_composition","gate_scope":true,"target_exists":true},{"target":"public.card_edition_context_external_mapping","writer":"internal.seal_edition_context_external_mapping","gate_scope":true,"target_exists":true}],"d_sequences":[],"g_objects_d":true,"d_canon_diff":[],"g_no_residue":true,"g_objects_1x":true,"g_rls_bypass":true,"g_roles_1_12":true,"d_concurrency":{"other_sessions_in_txn":0},"g_game_source":true,"d_baseline_md5":"5c329d5e38a7e369cc100ab08953e1a7","d_p7_functions":[{"fn":"public.normalize_external_catalog_value(p_value text)","via":"trigger trg_cecem_normalize","class":"ALLOWLIST_MISMATCH","depth":2,"body_md5":"81361bb8f52ce142803d69c2b3028ae8","language":"sql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_mapping_header()","via":"trigger trg_cecem_header","class":"GUARD","depth":1,"body_md5":"9e5fba31721c5e84212bd2116d3fa214","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_mapping_signature_write()","via":"trigger trg_cecem_signature_write","class":"GUARD","depth":1,"body_md5":"28084443cf6f32f9336d470ca16b7e72","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_edition_context_signature_write()","via":"trigger trg_cecp_signature_write","class":"GUARD","depth":1,"body_md5":"caa2e4d40d8e4995e217d7284f9d6c3b","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_profile","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_composition_immutable()","via":"trigger trg_cecpt_immutable","class":"GUARD","depth":1,"body_md5":"cfdcb500bb1090cd44c0e73d94c3f72e","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_profile_trait","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_mapping_composition_immutable()","via":"trigger trg_cecemt_immutable","class":"GUARD","depth":1,"body_md5":"ad0c472cfa82c71ee955d9b653755bdc","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_external_mapping_trait","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_edition_context_trait_active()","via":"trigger trg_cecpt_trait_active","class":"GUARD","depth":1,"body_md5":"68fb05f1c23db63a59611b0a12f79edd","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_profile_trait","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.normalize_edition_context_external_mapping()","via":"trigger trg_cecem_normalize","class":"NORMALIZE","depth":1,"body_md5":"15ea6245b8b8ce2173abb3d6b72c6736","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(regdictionary, text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"language":"c","proconfig":null,"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"extensions.unaccent(text)","via":"trigger trg_cecem_normalize","class":"PURE_EXT","depth":3,"body_md5":null,"language":"c","proconfig":null,"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_composition()","via":"trigger trg_cecp_seal","class":"SEAL","depth":1,"body_md5":"6077409ac2b5de7f788076e3b4b3f0c0","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_profile","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.seal_edition_context_external_mapping()","via":"trigger trg_cecem_seal","class":"SEAL","depth":1,"body_md5":"49a4ea4b34ccf06a4efdcf06270c52eb","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":true,"root_table":"card_edition_context_external_mapping","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.axis_identity_token(p_data jsonb, p_key text)","via":"index uq_cvir_row_identity","class":"UNCLASSIFIED","depth":1,"body_md5":"18682dce935281b0a4437628a6e8309a","language":"sql","proconfig":["search_path=\"\""],"gate_scope":false,"root_table":"catalog_variant_import_row","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_edition_context_profile_game()","via":"trigger trg_card_variant_edition_context_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"21e3a4c08989545351e2757c59fc77c4","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":false,"root_table":"card_variant","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.enforce_card_variant_printing_profile_game()","via":"trigger trg_card_variant_printing_profile_game","class":"UNCLASSIFIED","depth":1,"body_md5":"e847a065643a7836085eefc8116bb9c5","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":false,"root_table":"card_variant","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"internal.guard_cvir_normalized_shape()","via":"trigger trg_cvir_normalized_shape","class":"UNCLASSIFIED","depth":1,"body_md5":"1cebffee8afb213481342a9d402eb462","language":"plpgsql","proconfig":["search_path=\"\""],"gate_scope":false,"root_table":"catalog_variant_import_row","dynamic_sql":false,"external_signal":false,"search_path_unsafe":false,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_job()","via":"trigger trg_catalog_variant_import_job_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"c01adb02245bd5a305e8f8987a30f1c1","language":"plpgsql","proconfig":null,"gate_scope":false,"root_table":"catalog_variant_import_job","dynamic_sql":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.normalize_catalog_variant_import_row()","via":"trigger trg_catalog_variant_import_row_normalize","class":"UNCLASSIFIED","depth":1,"body_md5":"7ae9bd52e030b13c3a241debda491a99","language":"plpgsql","proconfig":null,"gate_scope":false,"root_table":"catalog_variant_import_row","dynamic_sql":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.set_updated_at()","via":"trigger trg_card_variant_set_updated_at","class":"UNCLASSIFIED","depth":1,"body_md5":"7933f81decf127af71628126ef109c81","language":"plpgsql","proconfig":["search_path=public, pg_temp"],"gate_scope":false,"root_table":"card_variant","dynamic_sql":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false},{"fn":"public.validate_card_variant_game_consistency()","via":"trigger trg_card_variant_validate_game_consistency","class":"UNCLASSIFIED","depth":1,"body_md5":"331a5501cb28172a63d2c3202594beaa","language":"plpgsql","proconfig":null,"gate_scope":false,"root_table":"card_variant","dynamic_sql":false,"external_signal":false,"search_path_unsafe":true,"unsupported_lexeme":false}],"d_publications":[],"d_ownership_rls":[{"rls":true,"name":"card_edition_context_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_profile","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_profile_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_external_mapping","owner":"postgres","force_rls":false},{"rls":true,"name":"card_edition_context_external_mapping_trait","owner":"postgres","force_rls":false},{"rls":true,"name":"card_variant","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_variant_import_job","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_variant_import_row","owner":"postgres","force_rls":false},{"rls":true,"name":"catalog_admin_action_log","owner":"postgres","force_rls":false},{"rls":true,"name":"game","owner":"postgres","force_rls":false}],"d_event_triggers":[{"name":"issue_graphql_placeholder","event":"sql_drop","enabled":"O"},{"name":"pgrst_ddl_watch","event":"ddl_command_end","enabled":"O"},{"name":"pgrst_drop_watch","event":"sql_drop","enabled":"O"},{"name":"issue_pg_cron_access","event":"ddl_command_end","enabled":"O"},{"name":"issue_pg_net_access","event":"ddl_command_end","enabled":"O"},{"name":"issue_pg_graphql_access","event":"ddl_command_end","enabled":"O"}],"g_no_concurrency":true,"g_p7_no_unresolved":true,"g_p7_all_classified":true,"g_p7_identity_pinned":false,"g_p7_writes_in_scope":true,"g_p7_closure_complete":true,"g_p7_search_path_safe":true,"d_p7_unqualified_calls":[{"name":"jsonb_typeof","caller":"internal.axis_identity_token","gate_scope":false,"resolution":"BUILTIN"},{"name":"array","caller":"internal.enforce_edition_context_mapping_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"array","caller":"internal.enforce_edition_context_signature_write","gate_scope":true,"resolution":"KEYWORD"},{"name":"and","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"if","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"in","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"KEYWORD"},{"name":"jsonb_exists","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"jsonb_typeof","caller":"internal.guard_cvir_normalized_shape","gate_scope":false,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.guard_edition_context_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_mapping_composition_immutable","gate_scope":true,"resolution":"KEYWORD"},{"name":"exists","caller":"internal.guard_edition_context_trait_active","gate_scope":true,"resolution":"KEYWORD"},{"name":"btrim","caller":"internal.normalize_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_composition","gate_scope":true,"resolution":"BUILTIN"},{"name":"array","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"cardinality","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"exists","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"KEYWORD"},{"name":"now","caller":"internal.seal_edition_context_external_mapping","gate_scope":true,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_job","gate_scope":false,"resolution":"BUILTIN"},{"name":"btrim","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"nullif","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_catalog_variant_import_row","gate_scope":false,"resolution":"BUILTIN"},{"name":"coalesce","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"regexp_replace","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"},{"name":"trim","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"KEYWORD"},{"name":"upper","caller":"public.normalize_external_catalog_value","gate_scope":true,"resolution":"BUILTIN"}],"d_p7_unqualified_writes":[],"g_p7_no_unqualified_dml":true,"g_freeze_canonical_equal":true,"g_p7_lexically_supported":true,"d_p7_unresolved_qualified":[],"g_pg17_maintain_privilege":true,"g_no_sequences_touched_now":true,"g_no_enabled_event_triggers":false,"g_p7_no_external_or_dynamic":true}}
```

**S1.4 — L2 (12 linhas)**

```json
[{"fn":"extensions.unaccent","identity_args":"regdictionary, text","language":"c","prosecdef":false,"vol":"s","proconfig":null,"md5_raw":"26018d65d186aaf6b4c5c0c20984ff03","md5_lf":"26018d65d186aaf6b4c5c0c20984ff03","len_raw":13,"cr_count":0},{"fn":"extensions.unaccent","identity_args":"text","language":"c","prosecdef":false,"vol":"s","proconfig":null,"md5_raw":"26018d65d186aaf6b4c5c0c20984ff03","md5_lf":"26018d65d186aaf6b4c5c0c20984ff03","len_raw":13,"cr_count":0},{"fn":"internal.enforce_edition_context_mapping_header","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"9e5fba31721c5e84212bd2116d3fa214","md5_lf":"9e5fba31721c5e84212bd2116d3fa214","len_raw":973,"cr_count":0},{"fn":"internal.enforce_edition_context_mapping_signature_write","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"28084443cf6f32f9336d470ca16b7e72","md5_lf":"28084443cf6f32f9336d470ca16b7e72","len_raw":823,"cr_count":0},{"fn":"internal.enforce_edition_context_signature_write","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"caa2e4d40d8e4995e217d7284f9d6c3b","md5_lf":"caa2e4d40d8e4995e217d7284f9d6c3b","len_raw":1247,"cr_count":0},{"fn":"internal.guard_edition_context_composition_immutable","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"cfdcb500bb1090cd44c0e73d94c3f72e","md5_lf":"cfdcb500bb1090cd44c0e73d94c3f72e","len_raw":1875,"cr_count":0},{"fn":"internal.guard_edition_context_mapping_composition_immutable","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"ad0c472cfa82c71ee955d9b653755bdc","md5_lf":"ad0c472cfa82c71ee955d9b653755bdc","len_raw":1483,"cr_count":0},{"fn":"internal.guard_edition_context_trait_active","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"68fb05f1c23db63a59611b0a12f79edd","md5_lf":"68fb05f1c23db63a59611b0a12f79edd","len_raw":272,"cr_count":0},{"fn":"internal.normalize_edition_context_external_mapping","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"15ea6245b8b8ce2173abb3d6b72c6736","md5_lf":"15ea6245b8b8ce2173abb3d6b72c6736","len_raw":663,"cr_count":0},{"fn":"internal.seal_edition_context_composition","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"6077409ac2b5de7f788076e3b4b3f0c0","md5_lf":"6077409ac2b5de7f788076e3b4b3f0c0","len_raw":1607,"cr_count":0},{"fn":"internal.seal_edition_context_external_mapping","identity_args":"","language":"plpgsql","prosecdef":true,"vol":"v","proconfig":["search_path=\"\""],"md5_raw":"49a4ea4b34ccf06a4efdcf06270c52eb","md5_lf":"49a4ea4b34ccf06a4efdcf06270c52eb","len_raw":1016,"cr_count":0},{"fn":"public.normalize_external_catalog_value","identity_args":"p_value text","language":"sql","prosecdef":false,"vol":"s","proconfig":["search_path=\"\""],"md5_raw":"81361bb8f52ce142803d69c2b3028ae8","md5_lf":"1fdc2e7ebe2297f8db85be4aad2e5d33","len_raw":104,"cr_count":2}]
```

---

## Adjudicação do STOP da Tentativa 03 — `BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01` (sem SQL)

**Data:** 2026-09-26. Rodada só documental. **Nenhum SQL**, nenhuma alteração no LIVE, nenhum event trigger desabilitado. Relatório completo, opções, riscos e diff proposto em `LIVE-STAGE1-STOP-ADJUDICATION.md` e `LIVE-STAGE1-STOP-ADJUDICATION.diff` (**não aplicado**).

Tipos usados na tabela:
- **OBS**: observação;
- **EVID**: evidência — LIVE (saídas da Tentativa 03), REPO (repositório) ou EXT (fonte pública, não verificada contra este LIVE);
- **PROP**: proposta, não aplicada.

| # | Tipo | Registro |
|---|---|---|
| 1 | EVID LIVE | Saídas integrais de L1, L3, E00 e L2 em §6 da Tentativa 03, reproduzidas no relatório com md5 por bloco: L1 `9fd1c517…`, L3 `347f4542…`, E00 `9344547d…`, L2 `2ebd4830…`. |
| 2 | EVID LIVE + REPO | `public.normalize_external_catalog_value`: o corpo do repositório (`schema/2095`, 102 B, 2 LF, md5 `1fdc2e7e…` = pino) com LF→CRLF dá 104 B, 2 CR e md5 `81361bb8…` = `md5_raw` LIVE. Divergência **exclusivamente CRLF/LF**; demais atributos iguais. **TRANSPORT/EOL-ONLY**, mesma classe da 2217. |
| 3 | OBS | Origem provável do CRLF (colagem via Windows/SQL Editor, como na 2217): não provada; não altera a conclusão. |
| 4 | EVID LIVE | 6 event triggers, todos `enabled = O`: `sql_drop` (`issue_graphql_placeholder`, `pgrst_drop_watch`) e `ddl_command_end` (`pgrst_ddl_watch`, `issue_pg_cron_access`, `issue_pg_net_access`, `issue_pg_graphql_access`). |
| 5 | EVID EXT | Os nomes correspondem aos event triggers da imagem Supabase: funções em `extensions`, dono `supabase_admin`; as tags variam com a idade do projeto (supabase/postgres PR #2478). |
| 6 | OBS | O E00 v7.0 não lê função, tags, dono nem corpo dos event triggers, nem o `session_replication_role`. A identidade LIVE dos 6 **não é conhecida**. |
| 7 | EVID REPO | Nenhum envelope autorizado (L1–L3, E00, E02, E99; E01 só DML) emite comando da matriz de disparo; os 10 corpos não-C do fecho P7 não têm DDL. Disparo pelos envelopes: **não possível por análise estática**. Isso **não** dispensa o gate. |
| 8 | EVID REPO | **Achado:** o P7 v3 não detecta DDL **estático** em corpo alcançado; só `EXECUTE` dinâmico. |
| 9 | PROP | D-6, opção A: pino comparado a `md5(replace(prosrc, CRLF, LF))` nos dois lados; CR isolado continua STOP; md5 bruto, `cr_count`, `crlf_count` e `d_p7_eol_normalized` exportados. |
| 10 | PROP | D-9 / AD-10: `g_no_enabled_event_triggers` substituído por `g_evt_ddl_only` (evento não-DDL ⇒ STOP sempre) e `g_evt_all_adjudicated` (identidade completa). `evt_allowlist` **vazia** até L4 + adjudicação individual; **nenhum dos 6 nomes aceito**. Inventário integral no E00. |
| 11 | PROP | Novo gate `g_p7_no_ddl`. E00 passa de 21 para 23 gates. `static_check.py` passa de 205 para 342 verificações, todas PASS no diff proposto. |
| 12 | PROP | L4 (event triggers, identidade completa), md5 `6bdc9dc44a90b4b43b87109beedb23d6`: só SELECT, fora da Etapa 1, **não executada**. |

**Pendências de decisão (Fabrício):**
1. **D-6** — escolher a forma da correção dos pinos (proposta A) e emitir mandato de correção do harness: aplicar o diff, fixar o blob novo do E00, atualizar o README.
2. **D-9** — autorizar a L4 sob mandato próprio; adjudicar individualmente cada event trigger; aceitar AD-10.
3. **Tentativa 04** — só com novo mandato, desde S1.0, com E00 corrigido e allowlist adjudicada.

---

## Correção local do harness — `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01` (sem SQL)

**Data:** 2026-09-26. Auditoria prévia: CORRECTION REQUIRED. Nenhum SQL, LIVE não acessado, nenhuma exceção criada, sem commit, Tentativa 04 não iniciada. FREEZE ATIVO.

Tipos usados na tabela:
- **EVID REPO**: fato verificável no repositório local;
- **PROP**: decisão ou validação ainda pendente.

| # | Tipo | Registro |
|---|---|---|
| 13 | EVID REPO | D-6 preservado pela opção A: pino comparado a `md5(replace(prosrc, CRLF, LF))`; md5 bruto, `cr_count`, `crlf_count` e `d_p7_eol_normalized` exportados. |
| 14 | EVID REPO | G-1 a G-5 incorporados. **24 gates**, com o novo `g_evt_inventory_complete`, que compara a contagem direta de `pg_event_trigger` com o inventário. A identidade do event trigger tem 12 atributos (inclui `fn_secdef`, `fn_config` e `fn_extension`). Justificativa obrigatória no SQL e no validador estático. `evt_allowlist` **vazia**; nenhum dos 6 inserido. |
| 15 | EVID REPO | L4 revisada: md5 `f3670eb8f149064610055720b0636218`; contagem e nomes lidos direto do catálogo; `LEFT JOIN`; `triggers_md5`. **Não executada.** |
| 16 | EVID REPO | Roteiro v1.4 e protocolo v1.5 reconciliados. PC-2 exige o E00 vigente: blob `88e9e7a4c94ac71feef536d6fc18b0e61190479c`, md5 `a9352afcb883f072e1baf8a3518536fb`. O blob `97410c3a…` usado nesta Tentativa 03 passa a ser **histórico**. |
| 17 | EVID REPO | Verificação estática: **420/420**. Mutação: E00 20/20; esvaziamento de predicado 24/24; roteiro 5/5; envelopes 42/42; DDL suplementar 10/10. `git diff --check` limpo. |
| 18 | EVID REPO | Preservados byte a byte: `BASELINE-BUILDER` e `FREEZE-CANON` (E00 do HEAD = E00 corrigido = E99), E01, E02, E99 e 2830 v7.0. |
| 19 | PROP | Compilação e execução PostgreSQL do E00 corrigido e da L4: **pendentes**, sob mandato próprio. Prova estática não é compilação. |

Detalhes, hashes e scripts: `LIVE-STAGE1-STOP-ADJUDICATION.md` §9. Diff integral: `LIVE-STAGE1-STOP-ADJUDICATION.diff` (md5 `8836d369edf66a6c22e9bb9923012cd1`).

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-CHANNEL-BLOCKER-01`, HEAD `44d8c52`).** Registrava a "Rodada 01" como INVÁLIDA — STOP operacional por bloqueio de canal em S1.2 (L3), com a L1 descrita como conforme via MCP, sem identificar o executor. Alternativas A1–A8 e procedimento de retomada. |
| 1.1 | **Reclassificação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-PC1-STOP-CLOSEOUT-01`).** A antiga "Rodada 01" passa a **Ocorrência 01 — governança**: L1 e tentativa de L3 executadas pelo **ChatGPT**, fora da atribuição de auditor. A L1 **não é PASS formal**; a L3 foi bloqueada pela ferramenta, sem resultado SQL e **sem evidência de execução no PostgreSQL**. Registrada a **Tentativa 02** do Claude: STOP em PC-1 (árvore suja), nenhum SQL submetido, sem dispensa da PC-1. Retomada ajustada: commit documental, novo mandato e Tentativa 03 desde S1.0. |
| 1.2 | **Tentativa 03 (2026-09-27 UTC, `BATCH12-2830-LIVE-STAGE1-EXECUTION-02`, HEAD `b8925ed5`).** Claude executou a Etapa 1 desde S1.0: PC-1…PC-5 PASS; L1 e L3 conformes (a L3 não foi bloqueada pela ferramenta); E00, 1ª leitura: **STOP**, com `g_p7_identity_pinned = false` e `g_no_enabled_event_triggers = false` (6 event triggers habilitados no LIVE). L2 (diagnóstico): TRANSPORT/EOL-ONLY em `public.normalize_external_catalog_value` (`cr_count` 2, md5 LF = pino), para D-6. `d_canon_diff = []`. S1.5, E01, E02, E99 e a Etapa 2 não foram executados. Saídas integrais anexadas. Nenhuma alteração em harness, consultas, pinos ou 2830. |
| 1.3 | **Adjudicação do STOP da Tentativa 03 (2026-09-26, `BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01`, sem SQL).** Nova seção com 12 registros tipados (OBS / EVID / PROP):<br>• prova byte a byte de que `normalize_external_catalog_value` diverge só por CRLF;<br>• origem, eventos e habilitação dos 6 event triggers, e impossibilidade estática de disparo pelos envelopes;<br>• achado do P7 sem detecção de DDL estático;<br>• propostas D-6 (normalização) e D-9 / AD-10 (allowlist por identidade, vazia), com L4;<br>• pendências de decisão.<br>Correções não aplicadas: diff em `LIVE-STAGE1-STOP-ADJUDICATION.diff`. Estado atual atualizado. |
| 1.4 | **Correção local do harness (2026-09-26, `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`, sem SQL).** Registros 13 a 19:<br>• D-6 (opção A) e G-1 a G-5;<br>• 24 gates;<br>• L4 revisada;<br>• E00 vigente na PC-2;<br>• provas estáticas e de mutação;<br>• preservação;<br>• compilação pendente.<br>Estado atual atualizado. |
