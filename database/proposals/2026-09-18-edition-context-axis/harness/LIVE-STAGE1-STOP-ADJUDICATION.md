# 2830H — Adjudicação do STOP da Etapa 1 (Tentativa 03)

| Campo | Valor |
|---|---|
| **Mandato** | `BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01` (2026-09-26). Só auditoria documental e preparação de proposta. |
| **SQL nesta rodada** | **Nenhum.** O LIVE não foi consultado nem modificado. Nenhum event trigger foi desabilitado. |
| **Estado** | Etapa 1 **STOP** (Tentativa 03, S1.3). Correção publicada em `9a4cff16`; L4 executada; **D-9 APROVADA e incorporada localmente** (§10). Tentativa 04 **não iniciada**. Etapa 2 **não autorizada**. FREEZE **ATIVO**. |
| **Baseline** | HEAD `b8925ed571127be8f05fac98f6a3afbad5fe74a3`. A árvore contém as alterações ainda não commitadas da Tentativa 03 (registro v1.2, README do harness e `docs/log.md`). |
| **Correções** | **Aplicadas LOCALMENTE** em `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`: não commitadas, **não compiladas nem executadas** no PostgreSQL, pendentes de auditoria independente. `LIVE-STAGE1-STOP-ADJUDICATION.diff` passou a ser o diff integral da correção contra o HEAD `b8925ed5`. **Estado vigente: §9, e §10 para D-9.** Onde as seções 0–8 divergirem da §9 (23 gates, hashes de E00, L4 e diff, "proposta não aplicada"), vale a §9; onde a §9 divergir da §10 (allowlist vazia, D-9 pendente, blob `88e9e7a4…`, 420/420), vale a §10. |
| **2830 canônica** | Blob `b4647dcb…`, inalterado. |

Rótulos usados neste documento:
- **[OBS]** observação: fato registrado sem prova suficiente para decisão, ou inferência declarada como tal.
- **[EVID]** evidência, com a fonte indicada:
  - **LIVE**: saídas da Tentativa 03;
  - **REPO**: arquivos do repositório no HEAD;
  - **EXT**: documentação pública, não verificada contra este LIVE.
- **[PROP]** proposta: não aplicada; depende de decisão e mandato.

---

## 0. Síntese

1. **D-6.** **[EVID]** A divergência de `public.normalize_external_catalog_value` é **exclusivamente CRLF/LF**, provada byte a byte (§2).
   - Corpo LIVE = corpo do repositório com cada LF trocado por CRLF.
   - Os demais atributos pinados são iguais.
   - **[PROP]** Normalização determinística nos dois lados (só CRLF). O md5 bruto é preservado como evidência. CR isolado continua STOP.
2. **Event triggers.** **[EVID LIVE]** Existem 6 event triggers habilitados (`O`), só em `ddl_command_end` e `sql_drop`.
   - **[EVID EXT]** Os nomes correspondem a event triggers da plataforma Supabase (PostgREST, pg_graphql, pg_cron, pg_net). **[OBS]** A identidade exata no LIVE (função, tags, dono) **não** foi lida.
   - **[EVID REPO]** Pela análise estática, nenhum envelope autorizado nem o fecho P7 emite comando capaz de disparar esses eventos.
   - Isso **não** dispensa o controle.
3. **[PROP]** Tratamento restritivo:
   - inventário integral;
   - evento não-DDL (`login`) ⇒ STOP sempre;
   - evento DDL só com exceção **individual**, por **identidade completa**, com justificativa;
   - `evt_allowlist` **vazia** até a L4 (só SELECT, mandato próprio) e a adjudicação D-9.
   - Com a allowlist vazia, o comportamento é **idêntico** ao atual.
4. **[PROP]** Falha de desenho achada: o P7 não detectava DDL estático no fecho. Novo gate `g_p7_no_ddl`.
5. **Diff proposto.** 4 arquivos, `git apply --check` limpo. A verificação estática sobe de 205/205 para **342/342** PASS, com 45 controles negativos em vez de 27.

---

## 1. Evidências integrais da Tentativa 03 (L1, L3, E00, L2)

Reproduzidas byte a byte de `LIVE-STAGE1-EXECUTION-RECORD.md` §6. O md5 abaixo é do texto de cada bloco, sem a quebra de linha final.

| Passo | Consulta (md5 do texto) | `checked_at` (relógio do banco) | md5 do bloco de evidência | Classificação |
|---|---|---|---|---|
| S1.1 | L1 `0836c36a…` | 2026-09-27 01:14:10.602003Z | `9fd1c5172e294768e60841b28a24387c` (770 B) | CONFORME |
| S1.2 | L3 `b7bc3700…` | 2026-09-27 01:14:24.605019Z | `347f45420850404b37e94592a0cba3e4` (3.784 B) | CONFORME |
| S1.3 | E00 `d00b7cec…` (blob `97410c3a…`) | 2026-09-27 01:16:20.815355Z | `9344547d0dcf212cfa3a2c269da04724` (14.754 B) | **STOP**: `g_p7_identity_pinned` e `g_no_enabled_event_triggers` falsos; os outros 19 gates são `true` |
| S1.4 | L2 `81d3472e…` | (a consulta não retorna horário) | `2ebd4830177512be970f5fffa423ee70` (3.227 B) | diagnóstico: 11 idênticas; 1 TRANSPORT/EOL-ONLY |

**[OBS]** O relógio do banco estava cerca de 1,5 min atrás do relógio do ambiente de verificação local. Os horários acima são os do banco.

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

## 2. D-6 — prova de que a divergência é exclusivamente CRLF/LF

### 2.1 Evidência

| # | Fato | Fonte |
|---|---|---|
| 1 | `public.normalize_external_catalog_value(p_value text)`: `md5_raw = 81361bb8f52ce142803d69c2b3028ae8`, `md5_lf = 1fdc2e7ebe2297f8db85be4aad2e5d33`, `len_raw = 104`, `cr_count = 2`; `sql`, `prosecdef = false`, `vol = s`, `proconfig = {search_path=""}` | [EVID LIVE] L2 |
| 2 | E00: `class = ALLOWLIST_MISMATCH`, `body_md5 = 81361bb8…`, `depth 2`, via `trg_cecem_normalize`; os outros 11 itens do escopo classificados | [EVID LIVE] E00 |
| 3 | Pino da allowlist: `1fdc2e7ebe2297f8db85be4aad2e5d33` | [EVID REPO] E00, linha da `p7_allowlist` |
| 4 | `database/schema/2095_…sql`: arquivo sem nenhum CR; corpo entre `$$` com 102 bytes, 2 LF, md5 `1fdc2e7e…` | [EVID REPO] |
| 5 | Corpo do repositório com cada LF trocado por CRLF: 104 bytes, 2 CR, md5 **`81361bb8f52ce142803d69c2b3028ae8`** | [EVID] reconstrução local, reproduzível (`static_check.py` proposto, "D-6 EVIDÊNCIA") |

### 2.2 Conclusão

- O `prosrc` LIVE é o corpo do repositório com as suas 2 quebras LF trocadas por CRLF. A igualdade vale para o md5 bruto e para o comprimento; a ressalva é só a colisão de md5, desprezível aqui.
- Não há CR isolado:
  - o md5 LF do LIVE é igual ao pino;
  - o corpo do repositório não tem CR;
  - logo, depois de trocar CRLF por LF não sobra CR, e os 2 CRs estavam em pares CRLF.
- Assinatura, linguagem, `SECURITY DEFINER`, volatilidade e `proconfig` conferem ([EVID LIVE] L2).
- **Classificação: TRANSPORT/EOL-ONLY, não material.** É a mesma classe da adjudicação G6.a da `2217` (EXECUTION-BATCHES).
- **[OBS] Origem provável, não provada:** o cabeçalho da 2095 diz "definição em produção lida via `pg_get_functiondef()` e conferida idêntica" (2026-08-07). Essa conferência não enxerga fim de linha. Colar pelo Windows ou pelo SQL Editor converte LF em CRLF, como no precedente da 2217. Nada disso altera a conclusão.

### 2.3 Opções

| # | Opção | Avaliação |
|---|---|---|
| **A** | **[PROP, recomendada]** Comparar o pino com `md5(replace(prosrc, CRLF, LF))`. O repositório é LF, então o pino continua sendo o md5 do corpo do repositório: normalização nos dois lados. Só CRLF é normalizado; CR isolado ⇒ `ALLOWLIST_MISMATCH`. O E00 exporta `body_md5` (bruto), `body_md5_lf`, `cr_count`, `crlf_count` e a lista `d_p7_eol_normalized`. | Determinística. Cobre a regra permanente da 2217. Nada fica silencioso: o bruto vai para o registro e cada caso é listado. Os demais pinos continuam valendo. |
| B | Pinar também o md5 bruto do LIVE, com proveniência (`81361bb8…`, Tentativa 03) | Acopla o harness a um artefato de transporte do LIVE; dois pinos por função; quebra de novo se o LIVE for recolado. Não recomendada. |
| C | Recriar a função no LIVE com LF | DDL no LIVE sob FREEZE, fora do escopo. **Não proposta.** |
| D | Manter como está | A Etapa 1 nunca passa. |

---

## 3. Event triggers — origem, eventos, existência × habilitação × disparo

### 3.1 Existência e habilitação — [EVID LIVE] E00 `d_event_triggers`

| Nome | Evento | `enabled` |
|---|---|---|
| `issue_graphql_placeholder` | `sql_drop` | `O` |
| `pgrst_drop_watch` | `sql_drop` | `O` |
| `pgrst_ddl_watch` | `ddl_command_end` | `O` |
| `issue_pg_cron_access` | `ddl_command_end` | `O` |
| `issue_pg_net_access` | `ddl_command_end` | `O` |
| `issue_pg_graphql_access` | `ddl_command_end` | `O` |

`O` significa que o trigger dispara quando `session_replication_role` é `origin` (o padrão) ou `local`. **[OBS]** O `session_replication_role` da sessão MCP **não** foi capturado. A proposta passa a registrá-lo em `d_session` e na L4.

**[OBS] Lacuna do inventário atual.** O E00 v7.0 não lê função, tags (`WHEN TAG IN`), dono nem corpo. Sem isso, nenhuma exceção pode ser por identidade.

### 3.2 Origem — [EVID EXT], não verificada contra este LIVE

| Nome | Função esperada (imagem Supabase) | Finalidade declarada | Observação |
|---|---|---|---|
| `pgrst_ddl_watch` / `pgrst_drop_watch` | `extensions.pgrst_ddl_watch()` / `extensions.pgrst_drop_watch()` | `NOTIFY pgrst, 'reload schema'` (recarga do cache do PostgREST) | disparam em qualquer DDL, sem filtro de tag |
| `issue_pg_graphql_access` | `extensions.grant_pg_graphql_access()` | GRANTs do pg_graphql | tag `CREATE FUNCTION` em projetos antigos; `CREATE EXTENSION` nos recentes |
| `issue_graphql_placeholder` | `extensions.set_graphql_placeholder()` | placeholder de `graphql_public.graphql` | `sql_drop` |
| `issue_pg_cron_access` | `extensions.grant_pg_cron_access()` | GRANTs do pg_cron | tag `CREATE SCHEMA` em projetos antigos; `CREATE EXTENSION` nos recentes |
| `issue_pg_net_access` | `extensions.grant_pg_net_access()` | GRANTs e `SECURITY DEFINER` de `net.http_*` | tag `CREATE EXTENSION` |

Fontes:
- supabase/postgres `nix/tests/expected/evtrigs.out`: dono `supabase_admin`; funções em `extensions`.
- `migrations/db/init-scripts/00000000000003-post-setup.sql`.
- supabase/postgres PR #2478: tags diferentes conforme a idade do projeto.

Consequência: **as tags e os corpos deste LIVE não podem ser presumidos.** Só a L4 os fornece. **[OBS]** A imagem de referência lista 12 event triggers (inclui `graphql_watch_*`, `pgaudit_*`, `pgsodium_*`, `pg_tle_*`); o LIVE mostrou 6. A diferença é esperada por configuração, sem efeito no gate.

### 3.3 Possibilidade efetiva de disparo pelos envelopes autorizados

Base normativa **[EVID EXT]** (PostgreSQL 17, §38.1 e §38.2):
- `ddl_command_start`, `ddl_command_end` e `sql_drop` disparam só em `CREATE`, `ALTER`, `DROP`, `SECURITY LABEL`, `COMMENT`, `GRANT`, `REVOKE` e `SELECT INTO` (≡ `CREATE TABLE AS`) de SQL puro;
- `table_rewrite` dispara só em `ALTER TABLE` / `ALTER TYPE` que reescrevem a tabela;
- `login` dispara na conexão.

DML (`INSERT`/`UPDATE`/`DELETE`), `SELECT` e `DO` não disparam event trigger.

| Envelope / caminho | Conteúdo relevante | Pode disparar os 6? |
|---|---|---|
| L1, L2, L3, L4, E00, E99 | 1 SELECT, sem `INTO` | **Não.** [EVID REPO] E00/E99: `static_check` proposto, sem comando da matriz; L1–L4: varredura local do texto dos blocos do roteiro (nenhum `CREATE`/`ALTER`/`DROP`/`GRANT`/`REVOKE`/`COMMENT`/`INTO`/`SET`/DML; 1 `;`) |
| E02 | `DO`; só `SELECT … INTO` (atribuição PL/pgSQL, não é `CREATE TABLE AS`) | **Não.** [EVID REPO] |
| E01 | `DO`; 10 `INSERT INTO` nas tabelas EC + `SELECT … INTO` | **Não diretamente:** DML não dispara event trigger. [EVID REPO] |
| Fecho P7 alcançado pelo DML do E01 | 10 corpos não-C (9 `internal.*` + `normalize_external_catalog_value`) + `unaccent` (C) | **Não.** [EVID REPO] Nenhum comando DDL nos corpos do repositório; [EVID LIVE] corpos LIVE = repositório pelos pinos (11 brutos + 1 por LF) |
| Evento `login` | nenhum dos 6 é `login` [EVID LIVE] | não se aplica. Se existisse, dispararia **a cada chamada MCP** ⇒ proposta: STOP sempre |

**Conclusão.** Existência: provada. Habilitação: provada. Disparo pelos envelopes autorizados: **não possível pela análise estática** do texto e do fecho P7. Isso não é prova em runtime e **não dispensa** o gate.

Riscos residuais:
- **R-E1** — DDL alheio (plataforma, pg_cron) dispara os triggers independentemente dos envelopes. Não é efeito do envelope. **[OBS]** O `g_no_concurrency` cobre só `client backend`.
- **R-E2** — **[EVID EXT]** O canal `apply_migration` do MCP executa DDL de bootstrap antes de cada migration (supabase/mcp issue #442, relato público, não verificado aqui). Esse DDL dispara `pgrst_ddl_watch`. O protocolo usa só `execute_sql`. A proposta reforça essa regra no §6.2.
- **R-E3** — **Achado:** o P7 v3 não detectava DDL **estático** num corpo alcançado; só `EXECUTE` dinâmico. Um trigger com `CREATE TEMP TABLE` passaria.
  - Hoje nenhum dos 10 corpos tem DDL.
  - **[PROP]** gate `g_p7_no_ddl`, com controles negativos.
- **R-E4** — Mesmo que um disparo ocorresse dentro do E01, os efeitos transacionais (GRANT, NOTIFY) seriam desfeitos pelo rollback estrutural: `NOTIFY` só é entregue no commit. **[OBS]** Não é usado como argumento de dispensa.

---

## 4. Tratamento restritivo proposto para o gate (D-9 / AD-10)

**[PROP]** Substituir `g_no_enabled_event_triggers` por dois gates.

1. **`g_evt_ddl_only`** — qualquer event trigger habilitado (`enabled <> 'D'`) com evento fora de `ddl_command_start` / `ddl_command_end` / `sql_drop` / `table_rewrite` ⇒ **STOP**. **Sem exceção possível** (ex.: `login`).
2. **`g_evt_all_adjudicated`** — todo event trigger habilitado precisa casar **exatamente** com uma linha de `evt_allowlist`, por:
   - `name`, `event` e `tags` (`IS NOT DISTINCT FROM`);
   - `enabled` e `owner`;
   - `fn` (`schema.nome(args)`), `fn_language` e `fn_owner`;
   - `fn_md5_lf`.

   Nome sozinho não basta. Linha com evento não-DDL nunca casa.

Regras de governança da `evt_allowlist`:
- **Nasce vazia** (`WHERE false`). Enquanto vazia, o comportamento é **idêntico** ao atual: qualquer habilitado ⇒ STOP.
- Uma linha só entra por **mandato de correção**, a partir de uma **L4** executada sob mandato próprio, com proveniência (horário, md5 da saída).
- Cada linha tem **justificativa individual**, com este modelo mínimo:
  - (a) evidência L4 (identidade completa e corpo);
  - (b) fonte externa da origem;
  - (c) eventos e tags;
  - (d) efeito da função;
  - (e) por que nenhum envelope autorizado nem o fecho P7 emite comando da matriz;
  - (f) revisão obrigatória se qualquer campo mudar — a mudança já é STOP pelo próprio gate.
- **Nenhum dos seis nomes é aceito nesta rodada.** Estado de adjudicação:

| Nome | Estado | Falta |
|---|---|---|
| `issue_graphql_placeholder` | **PENDENTE** | L4 (identidade, tags, corpo) + justificativa + decisão D-9 |
| `pgrst_drop_watch` | **PENDENTE** | idem |
| `pgrst_ddl_watch` | **PENDENTE** | idem |
| `issue_pg_cron_access` | **PENDENTE** | idem |
| `issue_pg_net_access` | **PENDENTE** | idem |
| `issue_pg_graphql_access` | **PENDENTE** | idem |

Inventário integral no E00: `d_event_triggers` passa a trazer identidade completa, com md5 bruto **e** LF da função. Novos diagnósticos:
- `d_evt_unadjudicated` — tem de ser `[]`;
- `d_evt_allowlist_absent` — linha adjudicada que sumiu do LIVE; registrada, sem efeito de gate.

**L4** — consulta só-SELECT, md5 `6bdc9dc44a90b4b43b87109beedb23d6`, no roteiro proposto §3.5. Fora da sequência da Etapa 1; **não executada**.

Alternativas rejeitadas:

| # | Alternativa | Motivo |
|---|---|---|
| E2 | Allowlist por nome | Proibido pelo mandato. Não detecta troca de função, tags ou corpo |
| E3 | Isenção global para eventos DDL | Dispensa global do controle, proibida |
| E4 | Desabilitar os event triggers no LIVE | Proibido. São da plataforma; alteraria o LIVE sob FREEZE |
| E5 | Manter o gate atual | Em LIVE Supabase a Etapa 1 nunca passa. Não gera informação nova |

---

## 5. Implicações (nada aplicado nesta rodada)

| Artefato | Implicação |
|---|---|
| **E00** | Blob novo, proposto `a10ffd81…`, md5 `470db26f…`, 41.646 B.<br>• Pino normalizado; `g_p7_no_ddl`; `g_evt_ddl_only` + `g_evt_all_adjudicated` no lugar de `g_no_enabled_event_triggers`: 21 → **23** gates.<br>• Saída nova: `body_md5_lf`, `cr_count`, `crlf_count`, `ddl_statement`, `d_p7_eol_normalized`, `d_event_triggers` completo, `d_evt_unadjudicated`, `d_evt_allowlist_absent`, `d_session.session_replication_role`.<br>• `BASELINE-BUILDER`/`FREEZE-CANON` **inalterados**.<br>• **[OBS]** O status do cabeçalho do E00 ("PREPARADO — NÃO EXECUTADO") está desatualizado desde a Tentativa 03. Corrigir no mandato de correção. |
| **E99** | Sem alteração: não tem P7 nem event triggers. Os blocos compartilhados com o E00 seguem byte-idênticos (a verificação estática confere). |
| **E01 / E02** | Sem alteração. A verificação estática nova prova que não emitem comando da matriz de disparo. |
| **L1 / L2 / L3** | Sem alteração: SQL e md5 preservados. A L2 continua diagnóstico após STOP de pino. |
| **`tools/static_check.py`** | 205 → **342** verificações, com 45 controles negativos em vez de 27. Novas verificações:<br>• pino = md5 LF do repositório;<br>• reprodução byte a byte da evidência LIVE;<br>• controles de CR isolado, CRLF + conteúdo e CRLF + `SECURITY DEFINER`;<br>• 4 controles de DDL;<br>• 11 controles EVT (identidade campo a campo, trigger novo, `login`, desabilitado);<br>• envelopes sem comando da matriz.<br>Rodado contra o E00 **atual**, o verificador novo falha de forma explícita (`KeyError: 'ddl_lexed'`): não passa em silêncio. |
| **Protocolo** | v1.5 proposta: §3.3, §3.4, §6.1 C-1, §6.2, §7 AD-8 reescrita e AD-10 nova, §8 D-6 e D-9, D-7 até AD-10. |
| **Roteiro** | v1.4 proposta: §0 (E00 novo e L4), PC-5, S1.3, §3.5 L4, §4.3 com 23 gates e itens 7/7a, P-4. |
| **README do harness** | No mandato de correção: seções "P7" e "Provas estáticas" (contagens) e tabela de arquivos com o blob novo. |
| **EXECUTION-BATCHES** | O protocolo §7 exige registrar lá o aceite de AD-8/AD-10 quando ele ocorrer. |
| **2830 v7.0** | Inalterada. Não contém pinos md5 nem critério de event trigger. |

---

## 6. Diffs propostos

`LIVE-STAGE1-STOP-ADJUDICATION.diff`:
- unified diff, `--suppress-blank-empty`: sem linhas com espaço final;
- md5 `a25d3142c32034877520da41795dadff`, 568 linhas;
- **não aplicado**.

| Arquivo | + | − |
|---|---|---|
| `harness/2830H_E00_precheck_inventory.sql` | 89 | 12 |
| `harness/tools/static_check.py` | 118 | 7 |
| `harness/LIVE-VALIDATION-PROTOCOL.md` | 14 | 5 |
| `harness/LIVE-STAGE1-RUNBOOK.md` | 52 | 9 |

Como auditar, sem banco:
1. `git apply --check database/proposals/2026-09-18-edition-context-axis/harness/LIVE-STAGE1-STOP-ADJUDICATION.diff`.
2. Numa cópia da árvore com o diff aplicado, `python3 tools/static_check.py` deve dar `TOTAL 342 PASS 342 FAIL 0`.
3. Os md5 dos blocos SQL do roteiro proposto devem ser L1 `0836c36a…`, L3 `b7bc3700…`, L2 `81d3472e…` e L4 `6bdc9dc4…`.

**Limite declarado:** o SQL novo do E00 e a L4 **não foram compilados**; não há PostgreSQL local. A compilação só é provada executando, sob mandato. Um erro de compilação seria STOP de harness (protocolo §3.4), nunca PASS.

---

## 7. Riscos da proposta

| # | Risco | Mitigação |
|---|---|---|
| P-1 | SQL novo do E00 não compilado | 1ª execução sob mandato; qualquer SQLSTATE ⇒ STOP de harness |
| P-2 | A normalização EOL mascarar alteração real | Só CRLF é normalizado; conteúdo, CR isolado e atributos continuam pinados (controles negativos); md5 bruto e `d_p7_eol_normalized` no registro |
| P-3 | Allowlist de event triggers virar dispensa | Nasce vazia; identidade completa; nunca `login`; linha só por mandato + L4; mudança em qualquer campo ⇒ STOP |
| P-4 | Falso positivo de `g_p7_no_ddl` (palavra `create`/`drop` fora de comentário ou literal) | Tende a STOP, nunca a PASS; os 10 corpos atuais passam (controle positivo) |
| P-5 | Tags e corpos dos triggers mudarem por atualização da plataforma (PR #2478) | O gate reprova a mudança ⇒ nova L4 e nova adjudicação |
| P-6 | Regex ARE × modelo Python (C-2) nos padrões novos | Mesma mitigação do P7: `d_p7_*` completo no registro para conferência humana |

---

## 8. Decisões pendentes (Fabrício)

1. **D-6:** aceitar a opção A (ou outra) e emitir **mandato de correção do harness** para aplicar o diff, fixar o blob novo do E00 e atualizar o README.
2. **D-9:**
   - (a) autorizar a **L4** sob mandato próprio (só SELECT);
   - (b) adjudicar **individualmente** cada um dos 6 event triggers a partir da L4;
   - (c) aceitar AD-10.
3. **Tentativa 04:** só com novo mandato, desde S1.0, com o E00 corrigido e a allowlist adjudicada. Sem isso, o resultado esperado continua STOP em `g_evt_all_adjudicated`.

A Etapa 1 permanece em **STOP**. A Etapa 2 não está autorizada. FREEZE **ATIVO**.

---

## 9. Correção local — `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01` (estado vigente)

**Auditoria:** CORRECTION REQUIRED. D-6 preservado pela opção A: CRLF→LF, com o md5 bruto como evidência. Nenhum SQL executado, LIVE não acessado, nenhuma exceção criada, nenhum commit, Tentativa 04 não iniciada. FREEZE ATIVO.

### 9.1 O que foi corrigido

| # | Achado | Correção aplicada |
|---|---|---|
| G-1 | Definição de `g_objects_1x`, `g_objects_D` e `g_game_source` não verificada | Lista `g00` com os 24 gates. O CTE `gates` precisa definir **exatamente** esses 24, sem extra, falta ou duplicata. Cada gate tem termos de predicado obrigatórios e é proibido esvaziá-lo (`WHERE false`, `OR true`). |
| G-2 | Modelo `evt_gate` aceitava `NULL = NULL` | Modelo com lógica de três valores: `=` em 9 atributos, `IS NOT DISTINCT FROM` em `tags`, `fn_config` e `fn_extension`. Controles de `NULL` nos 4 atributos obrigatórios testáveis. |
| G-3 | `JOIN` interno podia perder um trigger do inventário | Novo gate **`g_evt_inventory_complete`**: `(SELECT count(*) FROM pg_catalog.pg_event_trigger) = (SELECT count(*) FROM evt)`. O CTE `evt` não pode ter filtro (verificação estática). `d_evt_catalog_count` exportado. Controles negativos: catálogo 6 × inventário 5 (função perdida no JOIN) e catálogo 7 × inventário 6. |
| G-4 | Identidade do event trigger com 9 campos | **12 atributos**: + `fn_secdef` (`=`), `fn_config` e `fn_extension` (`IS NOT DISTINCT FROM`: `NULL` é estado pinado — sem `proconfig`, sem extensão — nunca curinga). Controles negativos isolados: `fn_secdef` false→true; `fn_config` NULL→valor, valor→NULL, valor→outro; `fn_extension` NULL→`pg_net`, `pg_graphql`→NULL, `pg_graphql`→`pg_net`. |
| G-5 | Roteiro com hashes antigos como critério | Cabeçalho, §0, PC-2, PC-4, §3.3 e P-1 citam o protocolo v1.5, o E00 vigente e a L4 revisada. Hashes anteriores só como histórico. O `static_check` recalcula o blob e o md5 do E00 e confere com a PC-2 e a §0. |
| Item 5 | Justificativa obrigatória | No SQL: `NULLIF(btrim(a.justification), '') IS NOT NULL` no casamento, sem justificativa não há adjudicação. Estático: validador de linhas futuras com 8 controles negativos (vazia, só espaços, `NULL`, `login`, `fn_md5_lf` `NULL`, `fn_secdef` `NULL`, `owner` `NULL`, linha sem a coluna). `evt_allowlist` **vazia**; nenhum dos 6 triggers inserido. |
| Item 3 | L4 sem contagem independente | L4 revisada (abaixo): `catalog_count` e `catalog_names` direto do catálogo; inventário com `LEFT JOIN` e `fn_resolved`; `inventory_count`, `inventory_complete` e `triggers_md5`; 6 regras de validação da saída no roteiro §3.5. |

**Total de gates reconciliado: 24.** São os 23 do relatório anterior mais `g_evt_inventory_complete`, na ordem do CTE:
- `g_objects_1x`, `g_objects_D`, `g_roles_1_12`, `g_pg17_maintain_privilege`, `g_game_source`;
- `g_freeze_canonical_equal`, `g_no_sequences_touched_now`;
- `g_p7_all_classified`, `g_p7_identity_pinned`, `g_p7_search_path_safe`, `g_p7_no_external_or_dynamic`, `g_p7_no_ddl`, `g_p7_lexically_supported`, `g_p7_no_unresolved`, `g_p7_no_unqualified_dml`, `g_p7_writes_in_scope`, `g_p7_closure_complete`;
- `g_no_rules`, `g_evt_ddl_only`, `g_evt_all_adjudicated`, `g_evt_inventory_complete`;
- `g_rls_bypass`, `g_no_residue`, `g_no_concurrency`.

`gate_pass` agrega todos dinamicamente. Com a allowlist vazia, o resultado projetado é **STOP em `g_evt_all_adjudicated`**; não é execução.

### 9.2 L4 revisada — md5 `f3670eb8f149064610055720b0636218` (2.416 B) — NÃO EXECUTADA

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

### 9.3 Identidade dos artefatos (árvore local, não commitada)

| Arquivo | blob git | md5 |
|---|---|---|
| `2830H_E00_precheck_inventory.sql` | `88e9e7a4c94ac71feef536d6fc18b0e61190479c` | `a9352afcb883f072e1baf8a3518536fb` (43.639 B; sha256 `94e9191b…`) |
| `tools/static_check.py` | `bf5c71e88881a33a5cae096d60d1b66bb0fc62d3` | `57d2425bcd510f5504e9e9d32c0dc486` |
| `LIVE-VALIDATION-PROTOCOL.md` (v1.5) | `c5739cefc11354b4ec7de10a3777d9094a866331` | `a6c5b78a369347a0a746e9019806e70b` |
| `LIVE-STAGE1-RUNBOOK.md` (v1.4) | `b881f073ff7762b6196dfed7d8ed78f0cb1584df` | `6f1127aaf36c5dad1ee9fcc1afa0e19a` |
| `LIVE-STAGE1-STOP-ADJUDICATION.diff` | `27e1c5bb3fd5b2d972d6e294c9eb2bb1bfd4169a` | `8836d369edf66a6c22e9bb9923012cd1` (821 linhas; sha256 `684514ca…`) |

Sobre o diff:
- Gerado com `diff -u --suppress-blank-empty` das versões do HEAD contra a árvore local.
- `git archive HEAD` + `patch -p1` reproduz os 4 arquivos byte a byte.
- Na árvore local, `git apply --check -R` passa: o diff já está aplicado.
- A proposta anterior (md5 `a25d3142…`) está **superada**.

### 9.4 Provas estáticas e mutação (sem banco)

| Verificação | Resultado |
|---|---|
| `python3 tools/static_check.py` | **420 / 420 PASS**: 72 controles negativos (34 P7 + 30 EVT + 8 validador) e 7 positivos |
| Mutação do E00 (Apêndice C.1): cada mutação enfraquece um controle (G-2, G-3, G-4, justificativa, allowlist não vazia, `login`, D-6 bruto, `g_p7_no_ddl`, G-1, gate extra, BUILDER/CANON só no E00) | **20 / 20 detectadas** |
| Esvaziamento do predicado de cada um dos 24 gates (Apêndice C.1) | **24 / 24 detectados** |
| Mutação do roteiro (Apêndice C.2): PC-2 com o blob antigo, PC-4 com v1.4, L4 sem contagem, L4 com `JOIN` interno, L4 editada sem recalcular o md5 | **5 / 5 detectadas** |
| Envelopes E00/E99/E01/E02 com comandos da matriz de disparo injetados (Apêndice B de `…-EVIDENCE.md`, md5 `9c3d523a…`) | **42 / 42 detectados** |
| P7-DDL suplementar (Apêndice C.3): 15 formas × 10 funções, `SELECT INTO`, 5 evasões, G-2 resolvido | **10 / 10 PASS** (inclui 150/150) |
| `git diff --check` | limpo |

**Prova estática ≠ compilação PostgreSQL.** Nenhum dos resultados acima compila ou executa o E00 corrigido ou a L4. Ficam **pendentes**, sob mandato próprio:
- a primeira compilação real;
- a semântica exata de `jsonb::text` usada em `triggers_md5`.

Um erro de compilação é STOP de harness (protocolo §3.4), nunca PASS.

### 9.5 Preservação

| Artefato | Evidência |
|---|---|
| `BASELINE-BUILDER` | Bloco byte-idêntico entre E00 do HEAD, E00 corrigido e E99 (4.106 B, sha256 `77b4cdb7786b0e7c…`) |
| `FREEZE-CANON` | Bloco byte-idêntico entre E00 do HEAD, E00 corrigido e E99 (979 B, sha256 `7155013916b26b3c…`) |
| E01 | blob `c4118b8c…` = HEAD |
| E02 | blob `3357ed46…` = HEAD |
| E99 | blob `49a71ecb…` = HEAD |
| 2830 v7.0 | blob `b4647dcb…` = HEAD |
| L1 / L2 / L3 | md5 `0836c36a…` / `81d3472e…` / `b7bc3700…` inalterados |

### 9.6 Decisões pendentes

1. Auditoria independente desta correção. Commit por Fabrício, se aprovada.
2. Mandato de compilação/execução, sem Tentativa 04 automática.
3. Mandato da L4 (D-9).
4. Adjudicação individual.
5. Tentativa 04, desde S1.0.

### Apêndice C.1 — `e00_mut.py` (md5 `80fa655a22d39e24cc068fe97e7f8c5c`)

```python
# Mutação do E00 corrigido: cada mutação enfraquece um controle; o static_check.py corrigido precisa reprovar.
import sys,shutil,subprocess
root=sys.argv[1]; H='/database/proposals/2026-09-18-edition-context-axis/harness/'
E00=open(root+H+'2830H_E00_precheck_inventory.sql',encoding='utf-8').read()
ROW="    SELECT 'pgrst_ddl_watch', 'ddl_command_end', NULL::text[], 'O', 'supabase_admin', 'extensions.pgrst_ddl_watch()', 'plpgsql', 'supabase_admin', true, NULL::text[], NULL::text, '"+'0'*32+"', 'x'"
MUT=[
 ('G-4 remove casamento fn_secdef',"                          AND a.fn_secdef = e.fn_secdef\n",""),
 ('G-4 remove casamento fn_config',"                          AND a.fn_config IS NOT DISTINCT FROM e.fn_config\n",""),
 ('G-4 remove casamento fn_extension',"                          AND a.fn_extension IS NOT DISTINCT FROM e.fn_extension\n",""),
 ('G-4 fn_config com = (NULL deixaria de casar estado pinado)',"a.fn_config IS NOT DISTINCT FROM e.fn_config","a.fn_config = e.fn_config"),
 ('G-2 owner com IS NOT DISTINCT FROM (NULL casaria NULL)',"AND a.owner = e.owner","AND a.owner IS NOT DISTINCT FROM e.owner"),
 ('G-2 tags com = ',"a.tags IS NOT DISTINCT FROM e.tags","a.tags = e.tags"),
 ('remove casamento fn_md5_lf'," AND a.fn_md5_lf = e.fn_md5_lf",""),
 ('remove justificativa obrigatória'," AND NULLIF(btrim(a.justification), '') IS NOT NULL",""),
 ('allowlist deixa de ser vazia (insere pgrst_ddl_watch)',"""    SELECT NULL::text, NULL::text, NULL::text[], NULL::text, NULL::text,
           NULL::text, NULL::text, NULL::text, NULL::boolean, NULL::text[],
           NULL::text, NULL::text, NULL::text
     WHERE false""",ROW),
 ('G-3 remove g_evt_inventory_complete',"""        (SELECT count(*) FROM pg_catalog.pg_event_trigger) = (SELECT count(*) FROM evt)
                                                                                      AS g_evt_inventory_complete,
""",""),
 ('G-3 inventário comparado consigo mesmo',"(SELECT count(*) FROM pg_catalog.pg_event_trigger) = (SELECT count(*) FROM evt)","(SELECT count(*) FROM evt) = (SELECT count(*) FROM evt)"),
 ('G-3 evt filtra desabilitados (esconde triggers)',"      JOIN pg_language l  ON l.oid = p.prolang\n),\n-- EVT-ALLOWLIST","      JOIN pg_language l  ON l.oid = p.prolang\n     WHERE e.evtenabled <> 'D'\n),\n-- EVT-ALLOWLIST"),
 ('login deixa de ser STOP',"event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite'))","event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite','login'))"),
 ('exceção deixa de exigir evento DDL',"WHERE a.event IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite')","WHERE true"),
 ('D-6 volta a comparar md5 bruto',"md5(replace(f.prosrc, chr(13) || chr(10), chr(10))) IS DISTINCT FROM a.body_md5","md5(f.prosrc) IS DISTINCT FROM a.body_md5"),
 ('g_p7_no_ddl esvaziado',"WHERE gate_scope AND ddl_statement)","WHERE false)"),
 ('G-1 remove g_game_source',"AS g_game_source,","AS g_game_source_x,"),
 ('24 → 25 gates (gate extra)',"AS g_no_concurrency\n","AS g_no_concurrency,\n        true AS g_extra\n"),
 ('BASELINE-BUILDER alterado só no E00',"'jobs_in_flight',         (SELECT count(*)","'jobs_in_flight',         (SELECT count(1)"),
 ('FREEZE-CANON alterado só no E00','"jobs_in_flight": 0','"jobs_in_flight": 1'),
]
tot=det=0
for label,a,b in MUT:
    assert E00.count(a)==1, label
    t='/tmp/e00mut_tree'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
    open(t+H+'2830H_E00_precheck_inventory.sql','w',encoding='utf-8').write(E00.replace(a,b))
    p=subprocess.run(['python3',t+H+'tools/static_check.py'],capture_output=True,text=True)
    fails=[l for l in p.stdout.splitlines() if l.startswith('FAIL')]; crash=p.returncode!=0 and not fails and 'Traceback' in p.stderr
    tot+=1; hit=bool(fails) or crash; det+=hit
    print(('DETECTADA ' if hit else 'NÃO DETECTADA ')+label+' | '+(fails[0][:110] if fails else ('crash: '+p.stderr.strip().splitlines()[-1][:80] if crash else '')))
print(f'MUTAÇÕES E00 DETECTADAS {det}/{tot}')
# Esvaziamento genérico: para cada um dos 24 gates, apaga o 1º termo efetivo do seu predicado (só dentro do segmento do gate).
import io,contextlib,re
ns={'__file__':root+H+'tools/static_check.py'}
with contextlib.redirect_stdout(io.StringIO()): exec(open(root+H+'tools/static_check.py',encoding='utf-8').read(),ns)
gcte=ns['_gcte']; seg=ns['_seg']; terms=ns['GATE_TERMS']
d2=t2=0
for g,tl in terms.items():
    sg=seg[g]; assert E00.count(sg)==1, g
    mutated=E00.replace(sg, sg.replace(tl[0],'/*removido*/ TRUE',1))
    t='/tmp/e00mut_tree'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
    open(t+H+'2830H_E00_precheck_inventory.sql','w',encoding='utf-8').write(mutated)
    p=subprocess.run(['python3',t+H+'tools/static_check.py'],capture_output=True,text=True)
    hit=any(l.startswith('FAIL') for l in p.stdout.splitlines()) or ('Traceback' in p.stderr)
    t2+=1; d2+=hit
    if not hit: print('NÃO DETECTADA: esvaziamento de',g)
print(f'ESVAZIAMENTO DE PREDICADO DETECTADO {d2}/{t2}')
```

### Apêndice C.2 — `rb_mut.py` (md5 `edd3012d06f599834d150837463df7fe`)

```python
import sys,shutil,subprocess
root=sys.argv[1]; H='/database/proposals/2026-09-18-edition-context-axis/harness/'
RB=open(root+H+'LIVE-STAGE1-RUNBOOK.md',encoding='utf-8').read()
L4=open('/tmp/q_L4v2.sql',encoding='utf-8').read()
MUT=[('PC-2 volta ao blob antigo','`88e9e7a4c94ac71feef536d6fc18b0e61190479c` e md5','`97410c3a799d8fdec86cc6d3735993ab224f6c9e` e md5'),
 ('PC-4 cita protocolo v1.4','o protocolo **v1.5** e o blob','o protocolo **v1.4** e o blob'),
 ('L4 perde contagem direta',"           'inventory_complete',       cat.catalog_count = jsonb_array_length(COALESCE(inv.triggers, '[]'::jsonb)),\n",""),
 ('L4 volta a JOIN interno','      LEFT JOIN pg_proc p      ON p.oid = e.evtfoid','      JOIN pg_proc p      ON p.oid = e.evtfoid'),
 ('L4 editada sem recalcular md5',"'fn_src',       p.prosrc)","'fn_src',       left(p.prosrc, 10))")]
det=0
for lab,a,b in MUT:
    assert RB.count(a)==1, lab
    t='/tmp/rbmut'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
    open(t+H+'LIVE-STAGE1-RUNBOOK.md','w',encoding='utf-8').write(RB.replace(a,b))
    p=subprocess.run(['python3',t+H+'tools/static_check.py'],capture_output=True,text=True)
    f=[l for l in p.stdout.splitlines() if l.startswith('FAIL')]; det+=bool(f)
    print(('DETECTADA ' if f else 'NÃO DETECTADA ')+lab+' | '+(f[0][:100] if f else ''))
print(f'MUTAÇÕES ROTEIRO DETECTADAS {det}/{len(MUT)}')
```

### Apêndice C.3 — `supp_ddl.py` (md5 `22150a1307837a66db8f93adc73994a5`)

```python
# Verificação suplementar P7-DDL (CORRECTION-01). Carrega o static_check.py PROPOSTO
# (árvore reconstruída = HEAD + diff) e exercita o modelo P7/EVT. Sem banco.
import io, contextlib, hashlib, sys, re
H=sys.argv[1]
ns={'__file__': H+'/tools/static_check.py'}
with contextlib.redirect_stdout(io.StringIO()):
    exec(open(H+'/tools/static_check.py',encoding='utf-8').read(), ns)
p7_gate=ns['p7_gate']; real=ns['real']; EXT=ns['EXT']; ALLOW=ns['ALLOW']; body_with=ns['body_with']; R=ns['R']
res=[]
def chk(n,c,d=''): res.append((n,bool(c),d))
# ---- 3. g_p7_no_ddl: cada forma da matriz × cada função não-C alcançada
FORMS=['CREATE TABLE public.x (a int);','create temp table x (a int);','CREATE OR REPLACE FUNCTION public.f() RETURNS int LANGUAGE sql AS 1;',
       'ALTER TABLE public.card_variant ADD COLUMN z int;','alter default privileges grant select on tables to anon;',
       'DROP TABLE public.x;','drop owned by anon;','GRANT SELECT ON public.card_variant TO anon;','REVOKE ALL ON public.card_variant FROM anon;',
       "COMMENT ON TABLE public.card_variant IS 'x';","SECURITY LABEL ON TABLE public.card_variant IS 'x';",'REINDEX TABLE public.card_variant;',
       'REFRESH MATERIALIZED VIEW public.mv;','IMPORT FOREIGN SCHEMA s FROM SERVER srv INTO public;','CREATE\n      INDEX ix ON public.x (a);']
nonc=[k for k,v in real.items() if v[3] not in ('c','internal')]
chk('funções não-C alcançadas no modelo = 10', len(nonc)==10, str(len(nonc)))
tot=ok_n=0
for fq in nonc:
    for form in FORMS:
        v=real[fq]; newsrc=body_with('    '+form) if v[3]=='plpgsql' else '\n    '+form+'\n'
        d=dict(real); t=list(d[fq]); t[7]=newsrc; d[fq]=tuple(t)
        key=(v[0],v[1],v[2]); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(newsrc.encode()).hexdigest()  # pino ajustado: isola o gate DDL
        ok,why=p7_gate(d,EXT); ALLOW[key]=saved
        tot+=1; ok_n+= (not ok) and any(w.startswith('g_p7_no_ddl:'+fq) for w in why)
chk(f'DDL da matriz bloqueado por g_p7_no_ddl em todas as funções (pino ajustado) {ok_n}/{tot}', ok_n==tot==150)
# SELECT INTO: sql ⇒ DDL; plpgsql ⇒ atribuição (não DDL)
nec='public.normalize_external_catalog_value'
src="\n    SELECT 1 INTO public.ghost;\n"; d=dict(real); t=list(d[nec]); t[7]=src; d[nec]=tuple(t)
k=('public','normalize_external_catalog_value','p_value text'); sv=dict(ALLOW[k]); ALLOW[k]['md5']=hashlib.md5(src.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[k]=sv
chk('função sql com SELECT INTO ⇒ g_p7_no_ddl', any(w.startswith('g_p7_no_ddl:') for w in why))
tg='internal.guard_edition_context_trait_active'; src=body_with('    SELECT 1 INTO NEW.a;')
d=dict(real); t=list(d[tg]); t[7]=src; d[tg]=tuple(t); k=('internal','guard_edition_context_trait_active',''); sv=dict(ALLOW[k]); ALLOW[k]['md5']=hashlib.md5(src.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[k]=sv
chk('plpgsql SELECT … INTO variável NÃO é DDL (sem falso positivo)', not any(w.startswith('g_p7_no_ddl:') for w in why), str(why))
# rotas de evasão ⇒ outro gate reprova
EV={"EXECUTE 'CREATE TABLE x (a int)';":'g_p7_no_external_or_dynamic',
    "NEW.a := $q$ x $q$; CREATE TABLE y (a int);":'g_p7_lexically_supported',
    'PERFORM internal.ghost_ddl();':'g_p7_no_unresolved',
    'CALL do_ddl();':'g_p7_no_unresolved',
    'PERFORM "Evil"();':'g_p7_lexically_supported'}
for stmt,gate in EV.items():
    src=body_with('    '+stmt); d=dict(real); t=list(d[tg]); t[7]=src; d[tg]=tuple(t)
    k=('internal','guard_edition_context_trait_active',''); sv=dict(ALLOW[k]); ALLOW[k]['md5']=hashlib.md5(src.encode()).hexdigest()
    ok,why=p7_gate(d,EXT); ALLOW[k]=sv
    chk(f'evasão [{stmt[:38]}] reprovada por {gate}', (not ok) and any(w.startswith(gate+':') for w in why), str(why[:2]))
# ---- G-2 resolvido: o modelo do static_check corrigido rejeita NULL=NULL nos atributos de '='
ev=ns['evt_gate']; live=ns['live']; allow=ns['allow']
a=[dict(x) for x in allow]; l=[dict(x) for x in live]; a[4]['owner']=None; l[4]['owner']=None
ok,why=ev(l,a,len(l)); chk('G-2 resolvido: evt_gate corrigido NÃO aceita owner NULL=NULL', not ok and any(w.startswith('g_evt_all_adjudicated:') for w in why))
bad=[r for r in res if not r[1]]
for n,ok,d in res: print(('PASS ' if ok else 'FAIL ')+n+((' '+d) if d and not ok else ''))
print(f'TOTAL {len(res)} PASS {len(res)-len(bad)} FAIL {len(bad)}')
```

## 10. D-9 — incorporação local da allowlist — `BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01` (estado vigente de D-9)

**Decisão de Fabrício:** D-9 APROVADA, sobre o baseline publicado `9a4cff16`. Sem SQL, sem acesso ao LIVE, nenhum event trigger alterado ou desabilitado, Tentativa 04 não iniciada, sem commit. FREEZE ATIVO.

### 10.1 O que mudou

- **E00** (blob `a4dd8438…`, md5 `45b6c35c…`, 53.803 B): a `evt_allowlist` deixa de ser vazia e passa a conter **exatamente 6 linhas**. Os 12 atributos de cada linha são copiados literalmente da saída da L4 executada (registro de execução, rev. 1.5, md5 `fc0d8cf7…`), preservando tipos SQL, arrays, `NULL` e o md5 integral. Nenhum gate, CTE, predicado ou bloco BUILDER/CANON foi alterado; os 24 gates são os mesmos.
- **Justificativa (a)–(f)** por linha: (a) evidência L4; (b) origem; (c) evento/tags; (d) efeito real; (e) ausência de caminho de disparo pelos envelopes atuais; (f) condição de reavaliação.
- **Categorias**, conforme o mandato:
  - `pgrst_ddl_watch` e `pgrst_drop_watch`: aceite **ordinário**, incluindo tags amplas `NULL` (efeito só `NOTIFY pgrst`);
  - `issue_pg_cron_access`: aceite **excepcional**, incluindo `ALTER DEFAULT PRIVILEGES`;
  - `issue_graphql_placeholder`: aceite **excepcional** pela criação da função placeholder;
  - `issue_pg_graphql_access`: aceite **excepcional** por DDLs e concessões de privilégio;
  - `issue_pg_net_access`: aceite **excepcional**, incluindo `CREATE USER` e concessões de acesso de rede.
- **AD-10/D-9** (protocolo v1.6): APROVADAS, **restritas aos envelopes atuais** (L1–L4, E00, E01, E02, E99). Não são autorização genérica para novas operações, migrations ou DDL. Uma linha nova exige nova L4, nova decisão e mandato de correção — nunca por nome.
- **`tools/static_check.py`**: as checagens de allowlist vazia foram substituídas pela validação das 6 linhas, dos pinos, das justificativas e da proveniência contra a L4 registrada, mais o modelo real (§10.3). Os controles negativos continuam.
- **Roteiro v1.5 / protocolo v1.6 / README / registro de execução / log:** reconciliados com os novos blobs.

### 10.2 Identidade dos artefatos

| Artefato | Blob | md5 | Bytes |
|---|---|---|---|
| E00 | `a4dd84381b928727611a51147ba1a4c1d11b89ab` | `45b6c35cca849ffbf49d22ec18e8283c` | 53.803 |
| `tools/static_check.py` | `378154507fadcb4f351c1a05ec475a1c32e272aa` | `e6a6b9ab5fc0e632dfc2ac293631b9ab` | 53.271 |
| Roteiro v1.5 | `9f454a9632f579607acadef1bfa076e3e5331e95` | `9ee3e8440ad86aeaa5aec51110a8a8e5` | 27.111 |
| Protocolo v1.6 | `f8d5218ba3aa446f7f76f2b99d4eab3a36bb152a` | `47a89b3a10aa8fc5e63c5681d0cd8557` | 48.077 |
| E01 / E02 / E99 | `c4118b8c…` / `3357ed46…` / `49a71ecb…` | inalterados | — |
| 2830 v7.0 | `b4647dcb59432405c8157e2733fd78678f35540e` | inalterado | 75.013 |

Diff integral contra `9a4cff16`: `LIVE-STAGE1-D9-ALLOWLIST.diff`.

### 10.3 Provas (sem banco)

| Prova | Resultado |
|---|---|
| `static_check.py` | **444 / 444 PASS** |
| Controle positivo: allowlist real × inventário real da L4 ⇒ `g_evt_all_adjudicated` e `g_evt_inventory_complete` verdadeiros | PASS |
| Alteração isolada de cada um dos 12 atributos em cada uma das 6 linhas do inventário | **72 / 72 reprovam** |
| Trigger adicional habilitado; linha removida; justificativa vazia; inventário 7×6; evento `login` | todos reprovam |
| Trigger adicional **desabilitado** (inventariado) | não reprova, como especificado |
| Mutação do E00 (Apêndice D.1): identidade alterada, tags, `enabled`, `fn_secdef`, `fn_extension`, linha removida, 7ª linha, justificativa sem (f), `pgrst` sem "tags NULL", categoria trocada, além dos controles da §9 | **29 / 29 detectadas** |
| Esvaziamento do predicado de cada um dos 24 gates | **24 / 24 detectados** |
| Mutação do roteiro (Apêndice D.2) | **5 / 5** |
| Envelopes com comandos da matriz de disparo (Apêndice B de `…-EVIDENCE.md`, md5 `9c3d523a…`) | **42 / 42** |
| DDL no corpo das funções (Apêndice C.3, md5 `22150a13…`) | **10 / 10** |
| Adulteração de um md5 dentro do bloco da L4 no registro de execução | **5 FAIL** (proveniência + controle positivo) |
| `BASELINE-BUILDER` / `FREEZE-CANON` E00 HEAD × E00 D-9 × E99 | idênticos (sha256 `77b4cdb7…` 4.106 B / `71550139…` 979 B) |

### 10.4 BLOCKER

**Nenhum BLOCKER real.** Duas dependências foram declaradas:

1. O commit precisa incluir o registro de execução, cuja seção L4 ainda não foi commitada. A proveniência verificada pelo `static_check.py` depende dela.
2. A compilação e a execução no PostgreSQL continuam pendentes. As comparações `text = name` são válidas no PG ≥ 12, mas só ficam provadas executando, o que exige mandato. A Tentativa 04 começa desde S1.0.

### 10.5 Decisões pendentes

1. Auditoria independente desta incorporação. Se aprovada, commit por Fabrício.
2. Mandato da Tentativa 04, desde S1.0, com o E00 `a4dd8438…`.

### Apêndice D.1 — `e00_mut_v2.py` (md5 `5858fe7a8615ecd268eeb2d53835bbbb`)

Executado como `python3 e00_mut_v2.py <cópia da árvore>`.

```python
# Mutação do E00 corrigido: cada mutação enfraquece um controle; o static_check.py corrigido precisa reprovar.
import sys,shutil,subprocess
root=sys.argv[1]; H='/database/proposals/2026-09-18-edition-context-axis/harness/'
E00=open(root+H+'2830H_E00_precheck_inventory.sql',encoding='utf-8').read()
import re as _re
R0=[l for l in E00.splitlines() if l.startswith("    ('pgrst_ddl_watch'")][0]
RN=[l for l in E00.splitlines() if l.startswith("    ('issue_pg_net_access'")][0]
MUT=[
 ('G-4 remove casamento fn_secdef',"                          AND a.fn_secdef = e.fn_secdef\n",""),
 ('G-4 remove casamento fn_config',"                          AND a.fn_config IS NOT DISTINCT FROM e.fn_config\n",""),
 ('G-4 remove casamento fn_extension',"                          AND a.fn_extension IS NOT DISTINCT FROM e.fn_extension\n",""),
 ('G-4 fn_config com = (NULL deixaria de casar estado pinado)',"a.fn_config IS NOT DISTINCT FROM e.fn_config","a.fn_config = e.fn_config"),
 ('G-2 owner com IS NOT DISTINCT FROM (NULL casaria NULL)',"AND a.owner = e.owner","AND a.owner IS NOT DISTINCT FROM e.owner"),
 ('G-2 tags com = ',"a.tags IS NOT DISTINCT FROM e.tags","a.tags = e.tags"),
 ('remove casamento fn_md5_lf'," AND a.fn_md5_lf = e.fn_md5_lf",""),
 ('remove justificativa obrigatória'," AND NULLIF(btrim(a.justification), '') IS NOT NULL",""),
 ('D-9: md5 de uma identidade alterado',"'7f27b8118fea5c88b0164331292859e3', 'D-9","'7f27b8118fea5c88b0164331292859e4', 'D-9"),
 ('D-9: tags de linha com filtro trocadas por NULL',"ARRAY['DROP EXTENSION']::text[]","NULL::text[]"),
 ('D-9: enabled O→A numa linha',"'issue_pg_cron_access', 'ddl_command_end', ARRAY['CREATE EXTENSION']::text[], 'O'","'issue_pg_cron_access', 'ddl_command_end', ARRAY['CREATE EXTENSION']::text[], 'A'"),
 ('D-9: fn_secdef false→true numa linha',"'extensions.grant_pg_net_access()', 'plpgsql', 'supabase_admin', false","'extensions.grant_pg_net_access()', 'plpgsql', 'supabase_admin', true"),
 ('D-9: fn_extension NULL→pg_net numa linha',"'extensions.grant_pg_net_access()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=\"\"']::text[], NULL::text","'extensions.grant_pg_net_access()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=\"\"']::text[], 'pg_net'"),
 ('D-9: linha removida (pg_net)',RN+"\n",""),
 ('D-9: 7ª linha acrescentada',R0+"\n",R0+"\n"+R0.replace("('pgrst_ddl_watch'","('pgrst_extra_watch'")+"\n"),
 ('D-9: justificativa de pg_net sem (f)',RN,RN.replace("(f) Reavaliar","Reavaliar")),
 ('D-9: justificativa de pgrst_ddl_watch sem "tags NULL"',R0,R0.replace("tags NULL","tags ausentes")),
 ('D-9: categoria de pg_net trocada para ORDINÁRIO',RN,RN.replace('ACEITE EXCEPCIONAL','ACEITE ORDINÁRIO')),
 ('G-3 remove g_evt_inventory_complete',"""        (SELECT count(*) FROM pg_catalog.pg_event_trigger) = (SELECT count(*) FROM evt)
                                                                                      AS g_evt_inventory_complete,
""",""),
 ('G-3 inventário comparado consigo mesmo',"(SELECT count(*) FROM pg_catalog.pg_event_trigger) = (SELECT count(*) FROM evt)","(SELECT count(*) FROM evt) = (SELECT count(*) FROM evt)"),
 ('G-3 evt filtra desabilitados (esconde triggers)',"      JOIN pg_language l  ON l.oid = p.prolang\n),\n-- EVT-ALLOWLIST","      JOIN pg_language l  ON l.oid = p.prolang\n     WHERE e.evtenabled <> 'D'\n),\n-- EVT-ALLOWLIST"),
 ('login deixa de ser STOP',"event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite'))","event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite','login'))"),
 ('exceção deixa de exigir evento DDL',"WHERE a.event IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite')","WHERE true"),
 ('D-6 volta a comparar md5 bruto',"md5(replace(f.prosrc, chr(13) || chr(10), chr(10))) IS DISTINCT FROM a.body_md5","md5(f.prosrc) IS DISTINCT FROM a.body_md5"),
 ('g_p7_no_ddl esvaziado',"WHERE gate_scope AND ddl_statement)","WHERE false)"),
 ('G-1 remove g_game_source',"AS g_game_source,","AS g_game_source_x,"),
 ('24 → 25 gates (gate extra)',"AS g_no_concurrency\n","AS g_no_concurrency,\n        true AS g_extra\n"),
 ('BASELINE-BUILDER alterado só no E00',"'jobs_in_flight',         (SELECT count(*)","'jobs_in_flight',         (SELECT count(1)"),
 ('FREEZE-CANON alterado só no E00','"jobs_in_flight": 0','"jobs_in_flight": 1'),
]
tot=det=0
for label,a,b in MUT:
    assert E00.count(a)==1, label
    t='/tmp/e00mut_tree'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
    open(t+H+'2830H_E00_precheck_inventory.sql','w',encoding='utf-8').write(E00.replace(a,b))
    p=subprocess.run(['python3',t+H+'tools/static_check.py'],capture_output=True,text=True)
    fails=[l for l in p.stdout.splitlines() if l.startswith('FAIL')]; crash=p.returncode!=0 and not fails and 'Traceback' in p.stderr
    tot+=1; hit=bool(fails) or crash; det+=hit
    print(('DETECTADA ' if hit else 'NÃO DETECTADA ')+label+' | '+(fails[0][:110] if fails else ('crash: '+p.stderr.strip().splitlines()[-1][:80] if crash else '')))
print(f'MUTAÇÕES E00 DETECTADAS {det}/{tot}')
# Esvaziamento genérico: para cada um dos 24 gates, apaga o 1º termo efetivo do seu predicado (só dentro do segmento do gate).
import io,contextlib,re
ns={'__file__':root+H+'tools/static_check.py'}
with contextlib.redirect_stdout(io.StringIO()): exec(open(root+H+'tools/static_check.py',encoding='utf-8').read(),ns)
gcte=ns['_gcte']; seg=ns['_seg']; terms=ns['GATE_TERMS']
d2=t2=0
for g,tl in terms.items():
    sg=seg[g]; assert E00.count(sg)==1, g
    mutated=E00.replace(sg, sg.replace(tl[0],'/*removido*/ TRUE',1))
    t='/tmp/e00mut_tree'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
    open(t+H+'2830H_E00_precheck_inventory.sql','w',encoding='utf-8').write(mutated)
    p=subprocess.run(['python3',t+H+'tools/static_check.py'],capture_output=True,text=True)
    hit=any(l.startswith('FAIL') for l in p.stdout.splitlines()) or ('Traceback' in p.stderr)
    t2+=1; d2+=hit
    if not hit: print('NÃO DETECTADA: esvaziamento de',g)
print(f'ESVAZIAMENTO DE PREDICADO DETECTADO {d2}/{t2}')
```

### Apêndice D.2 — `rb_mut.py` (md5 `4f0ccc71e1848273dc2c9017fcc58e38`)

`/tmp/q_L4v2.sql` é a L4 revisada extraída do roteiro (md5 `f3670eb8…`).

```python
import sys,shutil,subprocess
root=sys.argv[1]; H='/database/proposals/2026-09-18-edition-context-axis/harness/'
RB=open(root+H+'LIVE-STAGE1-RUNBOOK.md',encoding='utf-8').read()
L4=open('/tmp/q_L4v2.sql',encoding='utf-8').read()
MUT=[('PC-2 volta ao blob anterior (88e9e7a4)','`a4dd84381b928727611a51147ba1a4c1d11b89ab` e md5','`88e9e7a4c94ac71feef536d6fc18b0e61190479c` e md5'),
 ('PC-4 cita protocolo v1.5','o protocolo **v1.6** e o blob','o protocolo **v1.5** e o blob'),
 ('L4 perde contagem direta',"           'inventory_complete',       cat.catalog_count = jsonb_array_length(COALESCE(inv.triggers, '[]'::jsonb)),\n",""),
 ('L4 volta a JOIN interno','      LEFT JOIN pg_proc p      ON p.oid = e.evtfoid','      JOIN pg_proc p      ON p.oid = e.evtfoid'),
 ('L4 editada sem recalcular md5',"'fn_src',       p.prosrc)","'fn_src',       left(p.prosrc, 10))")]
det=0
for lab,a,b in MUT:
    assert RB.count(a)==1, lab
    t='/tmp/rbmut'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
    open(t+H+'LIVE-STAGE1-RUNBOOK.md','w',encoding='utf-8').write(RB.replace(a,b))
    p=subprocess.run(['python3',t+H+'tools/static_check.py'],capture_output=True,text=True)
    f=[l for l in p.stdout.splitlines() if l.startswith('FAIL')]; det+=bool(f)
    print(('DETECTADA ' if f else 'NÃO DETECTADA ')+lab+' | '+(f[0][:100] if f else ''))
print(f'MUTAÇÕES ROTEIRO DETECTADAS {det}/{len(MUT)}')
```

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01`).** Adjudicação documental do STOP da Tentativa 03, sem SQL:<br>• evidências integrais de L1, L3, E00 e L2;<br>• prova byte a byte de que `normalize_external_catalog_value` diverge só por CRLF;<br>• origem, eventos e possibilidade de disparo dos 6 event triggers;<br>• achado do P7 sem detecção de DDL estático;<br>• tratamento restritivo (D-9/AD-10);<br>• implicações, riscos e diff proposto de 4 arquivos, não aplicado. |
| 1.1 | **Correção local (2026-09-26, `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`, sem SQL).** Nova §9 (estado vigente):<br>• G-1 a G-5 incorporados;<br>• 24 gates, com `g_evt_inventory_complete`;<br>• identidade do event trigger com 12 atributos e justificativa obrigatória;<br>• L4 revisada (md5 `f3670eb8…`);<br>• roteiro reconciliado;<br>• novos blobs e hashes;<br>• 420/420 estático;<br>• mutação: 20/20, 24/24, 5/5 e 42/42;<br>• preservação de BUILDER/CANON/E01/E02/E99/2830.<br>Cabeçalho aponta para a §9. Compilação PostgreSQL pendente. |
| 1.2 | **D-9 incorporada localmente (2026-09-27, `BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`, sem SQL, baseline `9a4cff16`).** Nova §10 (estado vigente de D-9):<br>• 6 exceções da L4 com justificativa (a)–(f);<br>• categorias ordinária/excepcional conforme o mandato;<br>• AD-10/D-9 aprovadas e restritas aos envelopes atuais;<br>• novos blobs;<br>• 444/444 estático;<br>• mutação 29/29, 24/24, 5/5, 42/42, 10/10;<br>• preservação;<br>• apêndices D.1 e D.2.<br>Cabeçalho aponta para a §10. Nenhum BLOCKER real; compilação PostgreSQL pendente. |
