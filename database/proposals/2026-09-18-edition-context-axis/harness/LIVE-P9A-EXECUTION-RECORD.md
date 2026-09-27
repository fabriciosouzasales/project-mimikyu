# 2830H — Registro de execução LIVE de P9a (sete chamadas básicas)

| Campo | Valor |
|---|---|
| **Natureza** | Registro da execução das sete chamadas básicas de `P9A-READINESS.md` v1.2 (§7): L3 → P9A-00(a) → P9A-01 → P9A-02 → P9A-03 → P9A-04 → P9A-00(b). Só leitura. Sem ANALYZE, sem `EXPLAIN ANALYZE` e sem P9A-05. |
| **Mandatos** | Execução: `BATCH12-2830-P9A-LIVE-EXECUTION-01`, baseline HEAD `17857efb2b913bb742a4d771cb07108c5f5ad06a`. Registro: `BATCH12-2830-P9A-LIVE-EVIDENCE-CLOSEOUT-01` (documental, sem nova execução LIVE). |
| **Autorização** | Fabrício autorizou expressamente as sete chamadas, incluindo os SELECTs de catálogo L3 e P9A-00(a)/(b) (BL-1 resolvido para esta execução). Não houve autorização para P9A-05a/05b. |
| **Estado atual** | **Execução concluída, sem STOP.** Classificações:<br>• P9A-01 (E00) e P9A-02 (E99): **REGISTRADO**, sem bandeiras;<br>• 6.1: **NÃO DEMONSTRADO**;<br>• 6.2: **EVIDÊNCIA — CENÁRIO PEQUENO**, aguardando decisão de Fabrício.<br>P9a **não** está globalmente concluído, A2 **não** está cumprido e o UNFREEZE **não** está autorizado. FREEZE ATIVO. |
| **Papéis** | **Claude**: executor. **ChatGPT**: auditor independente. **Fabrício**: autorizações, decisão 6.2, commit e push. |

---

## 1. Preflight (S0, local)

| Item | Resultado |
|---|---|
| HEAD | `17857efb2b913bb742a4d771cb07108c5f5ad06a` = baseline do mandato |
| Árvore | limpa: `git status --porcelain --untracked-files=all` com 0 linhas |
| Blobs = HEAD | `P9A-READINESS.md` `99c32f78…` (md5 `0de2c1b8…`, 38.727 B); E00 `a4dd8438…`; E99 `49a71ecb…`; `LIVE-STAGE3-EXECUTION-RECORD.md` `974674f9…` (Apêndice A); `LIVE-VALIDATION-PROTOCOL.md` `abe806d6…` (L3) |
| Textos compostos | os sete textos foram gerados a partir do HEAD e conferidos contra o §5 do readiness v1.2: 7/7 md5 e tamanhos iguais aos publicados |
| `tools/static_check.py` | 444 / 444 PASS |
| Canal | Supabase MCP `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`, uma chamada por statement |

## 2. Cronologia e resultados

A ordem de submissão é a sequência de chamadas. Houve exatamente 7 chamadas `execute_sql` nesta execução, e nenhuma outra entre elas. A chamada anterior no canal foi a L3 final da Etapa 3 (2026-09-27, ~03:46Z).

O horário de banco só existe nas saídas com `checked_at`. Os EXPLAIN não trazem horário. Os carimbos do registro da sessão (relógio do cliente) ficam ~106 s **depois** do `checked_at` do banco (S2: 14:51:28.599Z × 14:49:40.983Z; S7: 14:57:05.138Z × 14:55:19.455Z). Por isso servem só como ordem, não como horário do servidor.

| # | Chamada | Horário de banco | Registro da sessão (cliente) | SQLSTATE | Resultado | Classificação |
|---|---|---|---|---|---|---|
| S1 | L3 | `checked_at` 14:49:18.001598Z | 14:51:03.874Z | nenhum | `locks_on_scope = []`; 12 `client backend`, todas `idle`, sem `xact_start` nem `backend_xid` | limpa |
| S2 | P9A-00(a) | `checked_at` 14:49:40.983172Z · pid 3521158 | 14:51:28.599Z | nenhum | snapshot integral (§5) | conforme (§6.4) |
| S3 | P9A-01 (E00) | — | 14:54:23.864Z | nenhum | plano de 795 linhas | **REGISTRADO** |
| S4 | P9A-02 (E99) | — | 14:56:22.987Z | nenhum | plano de 281 linhas | **REGISTRADO** |
| S5 | P9A-03 (6.1) | — | 14:56:32.886Z | nenhum | `Index Scan using ix_card_variant_card_id` | **6.1 NÃO DEMONSTRADO** |
| S6 | P9A-04 (6.2) | — | 14:56:42.298Z | nenhum | `Index Scan using ix_card_variant_card_id` | **6.2 EVIDÊNCIA — CENÁRIO PEQUENO** |
| S7 | P9A-00(b) | `checked_at` 14:55:19.455163Z · pid 3521878 | 14:57:05.138Z | nenhum | snapshot integral, igual a (a) exceto `checked_at`/`backend_pid` | conforme e estável |

## 3. Identidade dos textos e das saídas (EV1–EV4)

| # | md5 submetido (esperado = obtido) | Bytes | Saída: md5 do corpo (com LF final) | Bytes | Linhas / linhas de resultado | EV1 | EV2 | EV3 | EV4 |
|---|---|---|---|---|---|---|---|---|---|
| S1 | `b7bc3700aeef278f6a79bd30e6a8d229` | 1.526 | `a48686ed44ffde2be0fef48ba737b13e` | 3.787 | 1 | ✓ | ✓ | ✓ | ✓ (SELECT de catálogo) |
| S2 | `da737699bd8e870f9c26b76466f8281f` | 6.629 | `2539e3f57e3d7305889b25c1a7427d8e` | 6.947 | 1 | ✓ | ✓ | ✓ | ✓ (SELECT de catálogo) |
| S3 | `00301d286aac7e6425a94e81a08794f4` | 53.823 | `74288f9e194dfe0f24c1af64d3c4cfed` | 50.805 | 795 | ✓ | ✓ | ✓ | ✓ |
| S4 | `54919abf0abb8f65886f5c9c90e4fb13` | 13.064 | `2fec9e00152ab78837c7b8ed2161d858` | 16.750 | 281 | ✓ | ✓ | ✓ | ✓ |
| S5 | `3151a5d16d44373fe78732cb7eb56a57` | 131 | `03963bcf4712742ef24571dc7e404cf6` | 167 | 2 | ✓ | ✓ | ✓ | ✓ |
| S6 | `e917eb3928cc52b025a4b88afdaf9d22` | 358 | `45308e3a868c13b01c353d6b0796b1e3` | 251 | 2 | ✓ | ✓ | ✓ | ✓ |
| S7 | `da737699bd8e870f9c26b76466f8281f` | 6.629 | `f9a11071b11be9790ba96552a6ccb3ae` | 6.947 | 1 | ✓ | ✓ | ✓ | ✓ (SELECT de catálogo) |

- **EV1:** o md5 de cada texto submetido foi recalculado a partir do parâmetro `query` registrado na sessão e confere com o §5 do readiness v1.2.
- **EV2:** todas as respostas são arrays JSON válidos e não vazios.
  - A resposta do S3 (54.631 caracteres) ultrapassou o limite de **exibição** da ferramenta e foi gravada integralmente em arquivo pelo cliente. Não houve truncamento no canal: o array tem 795 linhas, de `Result` a `CTE Scan on sess sess_6`.
  - Os corpos de S3 e S4 são reconstruíveis byte a byte a partir das linhas do plano (Apêndice B), com serialização `[{"QUERY PLAN":…},…]` sem espaços.
- **EV3:** nenhuma chamada devolveu erro.
- **EV4:** nenhum nó `ModifyTable`, `Insert on`, `Update on`, `Delete on`, `Merge on` ou `LockRows` nos quatro planos. Nenhuma linha de JIT (`jit = off`).
- **Respostas originais** (com o invólucro de dados não confiáveis do canal), md5 e bytes: Apêndice C.

## 4. Planos P9A-01 (E00) e P9A-02 (E99)

L = {`catalog_variant_import_row`, `card_variant`}. As bandeiras foram avaliadas pela árvore de indentação do plano, com um script local (`analyze.py`, md5 `fc7d18747693193f8395d40534967836`, guardado junto às evidências) aplicado ao texto de exibição do Apêndice B, e com conferência manual dos nós de L. Os números de linha citados são os desse texto (1 = `Result`).

| Métrica | P9A-01 (E00) | P9A-02 (E99) |
|---|---|---|
| Linhas do plano | 795 | 281 |
| `InitPlan` / `SubPlan` / `CTE` | 163 / 11 / 22 | 80 / 0 / 4 |
| `Nested Loop` / `Hash Join` / `Merge Join` | 41 / 12 / 0 | 13 / 0 / 0 |
| Acessos a `card_variant` | Index Only Scan `ix_card_variant_variant_type_id` (l. 278), Index Only Scan `ix_card_variant_edition_context` (l. 281) | idem (l. 27, 30) |
| Acessos a `catalog_variant_import_row` | Index Only Scan `ix_catalog_variant_import_row_job` (l. 284); Index Scan `…_job_persistence` (l. 298); Index Scan `…_job` (l. 305); Seq Scan ×3 (l. 287, 292, 310) | idem (l. 33, 47, 54; Seq Scan l. 36, 41, 59) |
| `Nested Loop` com relação de L | 2 (l. 295, 302): externo Seq Scan em `catalog_variant_import_job` (145 linhas), **interno Index Scan** no staging | 2 (l. 44, 51): mesma forma |
| `SubPlan` correlacionado com Seq Scan em L | nenhum (os 11 SubPlans leem só catálogo) | não há SubPlan |
| **FLAG-NL** | nenhuma | nenhuma |
| **FLAG-SP** | nenhuma | nenhuma |

- Os três Seq Scans no staging, em ambos os planos, ficam sob `InitPlan → Aggregate` sem predicado de seleção: `max(updated_at)`, a distribuição `validation_status || '/' || persistence_status` e a contagem de lineage. É a forma inerente de uma contagem integral (§6.1 do readiness) e **não** é bandeira.
- Os demais Nested Loops e Hash Joins do E00 operam sobre catálogo (`pg_proc`, `pg_depend`, `pg_class`, `pg_event_trigger` etc.), fora de L.
- **Classificação (§6.1): P9A-01 REGISTRADO; P9A-02 REGISTRADO.**
  - Registram a forma do plano dos envelopes vigentes.
  - **Não** declaram P9a globalmente concluído: as seções B, M e 5.2/5.3/5.7 continuam sem artefato (BL-2).
  - **Não** servem como prova de tempo (P9b).

## 5. Requisitos 6.1 e 6.2

**P9A-03 (6.1):** plano integral (Apêndice B.3):

```text
Index Scan using ix_card_variant_card_id on card_variant cv
  Index Cond: (card_id = '00000000-0000-0000-0000-000000000000'::uuid)
```

**P9A-04 (6.2):** plano integral (Apêndice B.4):

```text
Index Scan using ix_card_variant_card_id on card_variant cv
  Index Cond: (card_id = ANY ('{00000000-0000-0000-0000-000000000001,00000000-0000-0000-0000-000000000002,00000000-0000-0000-0000-000000000003}'::uuid[]))
```

- **6.1 — NÃO DEMONSTRADO** (§6.2 do readiness).
  - Acesso indexado com `Index Cond` em `card_id`, mas pelo índice `ix_card_variant_card_id`, cujo `first_key = card_id` (P9A-00), e não por `uq_card_variant_identity`.
  - As pré-condições do PASS estavam presentes: `literals_in_mcv = false` conhecido, nenhuma configuração comprometedora e estabilidade (a)/(b). O que faltou foi o próprio uso do índice de identidade.
  - Não é FAIL.
  - P9A-03 é diagnóstico de planejamento com literal sintético, não prova de desempenho.
- **6.2 — EVIDÊNCIA — CENÁRIO PEQUENO** (§6.3 do readiness).
  - EV1–EV4 em P9A-03 e P9A-04; inventário de índices completo no P9A-00; os dois planos classificados pelo caminho de acesso.
  - Vale só para N ≤ 3.
  - P9A-05 (cenários de catálogo) não foi autorizado nem executado.
  - A decisão sobre `ix_card_variant_card_id` (manter, remover ou adiar) é de Fabrício e **não** foi tomada aqui.
- **Leitura dos planos observados, que não é decisão:**
  - nos dois planos, nesta configuração e com estas estatísticas, o planner escolheu `ix_card_variant_card_id`;
  - isso registra uma escolha observada. **Não** demonstra que a existência de `ix_card_variant_card_id` impeça o uso de `uq_card_variant_identity`, nem que o índice composto seja inutilizável para busca por `card_id`: ele é válido e tem `card_id` como primeira chave (P9A-00);
  - o plano sem `ix_card_variant_card_id` não foi observado (limite 7 do §4 do readiness).
- **Insumo para a decisão 6.2** (P9A-00, contadores acumulados desde `stats_reset` 2026-07-15T14:26:35Z, iguais em (a) e (b)):

| Índice | `first_key` | Chaves | Único | Parcial | Tamanho | `idx_scan` | `last_idx_scan` |
|---|---|---|---|---|---|---|---|
| `ix_card_variant_card_id` | card_id | 1 | não | não | 843.776 B | 3.397.803 | 2026-09-27T03:56:08Z |
| `uq_card_variant_identity` | card_id | 4 | sim (NULLS NOT DISTINCT) | não | 1.515.520 B | 1.880 | 2026-09-27T03:56:08Z |
| `uq_card_variant_card_order` | card_id | 2 | sim | não | 1.327.104 B | 25.341 | 2026-09-25T02:36:18Z |
| `uq_card_variant_one_default_per_card` | card_id | 1 | sim | sim (`is_default`) | 81.920 B | 3.694 | 2026-09-19T01:00:40Z |

  Os contadores são acumulados de todo o tráfego desde o reset. Não isolam o consumidor de P9A-04 e não são medida de desempenho.

## 6. Snapshots P9A-00 (a) × (b)

- **Diferenças:** só `checked_at` e `backend_pid`, ambos esperados.
- **Iguais em (a) e (b):**
  - `planner_settings`;
  - as 11 `relations` (`reltuples`, `relpages`, `n_live_tup`, `n_dead_tup`, `n_mod_since_analyze`, `last_analyze`, `last_autoanalyze`, RLS);
  - os 9 `card_variant_indexes`, inclusive `idx_scan`/`last_idx_scan`: os EXPLAIN não executaram a consulta;
  - `card_id_stats`.
- **§6.4:**
  - `in_recovery = false`; `current_user = postgres`.
  - Todos os 13 `enable_*` = `on`: nenhuma configuração comprometedora.
  - `transaction_read_only = off`; `lock_timeout = 0`; `statement_timeout = 120000`; `jit = off`; `random_page_cost = 1.1`; `work_mem = 2184` (kB).
  - L:
    - `card_variant`: `reltuples` 24.893, `last_autoanalyze` 2026-09-19T00:48:33Z, `n_mod_since_analyze` 897;
    - `catalog_variant_import_row`: `reltuples` 26.127, `last_autoanalyze` 2026-09-20T17:30:38Z, `n_mod_since_analyze` 66.
    - Estatística conhecida para as duas.
  - `card_id_stats`: `MCV_PRESENT`, `mcv_count` 100, `mcv_max_freq` 0,000375063, `n_distinct` −0,567595, `literals_in_mcv = false` (conhecido, não UNKNOWN).
  - Estabilidade (a)/(b): cumprida.
- **Fora de L:** `game` e `asset_source` estão com `reltuples = -1` (nunca analisadas). É informação de contexto, sem efeito nas classificações.

## 7. Limitações e pendências

1. **P9a global** continua incompleto (BL-2): as seções B, M e 5.2/5.3/5.7 não têm artefato de harness.
2. **A2** não está cumprido: P9b sem ambiente isolado; D-2 (AD-2) e D-1/P14 PENDENTES.
3. **6.1** continua NÃO DEMONSTRADO. Uma nova tentativa exige mandato próprio e não pode usar alteração de sessão nem DDL.
4. **6.2** aguarda a decisão de Fabrício. A evidência cobre só o cenário pequeno (N ≤ 3). P9A-05 permanece proposta condicional, sem autorização.
5. **Limites de representatividade** do readiness (§4): o plano reflete estatísticas de 2026-09-19/20 e a configuração do canal. RLS não entra (dono). Os literais de P9A-03/04 são sintéticos, e o texto do PostgREST é aproximado por `IN (…)`.
6. **Horários:** os EXPLAIN não têm horário de servidor, e os carimbos do cliente estão defasados (§2).
7. **`P9A-READINESS.md`** continua com o cabeçalho "PREPARADO — NÃO EXECUTADO". Não foi alterado neste mandato: o readiness é o contrato auditado da execução, e o estado da execução está neste registro.

## 8. Resultado

**Execução concluída, sem STOP.**

| Item | Classificação |
|---|---|
| P9A-01 (E00) | REGISTRADO, sem FLAG-NL/FLAG-SP |
| P9A-02 (E99) | REGISTRADO, sem FLAG-NL/FLAG-SP |
| 6.1 | NÃO DEMONSTRADO |
| 6.2 | EVIDÊNCIA — CENÁRIO PEQUENO, aguardando decisão de Fabrício |
| P9A-00 (a)/(b) | conforme e estável |

Nenhuma escrita, DDL, SET, ANALYZE, TEMP, PREPARE ou retry. P9a não está globalmente concluído, A2 não está cumprido e o UNFREEZE não está autorizado. **FREEZE ATIVO.**

## Apêndice A — Textos submetidos

Cada bloco é o texto integral, sem as cercas e com o LF final. P9A-01 e P9A-02 são compostos: `EXPLAIN (COSTS OFF)` + LF + artefato verbatim. Eles não são repetidos aqui porque os artefatos-fonte são blobs imutáveis do HEAD.

### A.1 — S1 · L3 (md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1526 B)

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

### A.2 — S2 e S7 · P9A-00 (texto idêntico nas duas chamadas) (md5 `da737699bd8e870f9c26b76466f8281f`, 6629 B)

```sql
SELECT jsonb_build_object(
    'checked_at',         clock_timestamp(),
    'backend_pid',        pg_backend_pid(),
    'current_user',       current_user,
    'in_recovery',        pg_is_in_recovery(),
    'server_version_num', current_setting('server_version_num'),
    'stats_reset',        (SELECT d.stats_reset FROM pg_stat_database d WHERE d.datname = current_database()),
    'planner_settings',   (SELECT jsonb_object_agg(s.name, s.setting)
                             FROM pg_settings s
                            WHERE s.name IN ('enable_seqscan','enable_indexscan','enable_indexonlyscan',
                                             'enable_bitmapscan','enable_tidscan','enable_hashjoin',
                                             'enable_mergejoin','enable_nestloop','enable_hashagg',
                                             'enable_sort','enable_incremental_sort','enable_material',
                                             'enable_memoize','random_page_cost','seq_page_cost',
                                             'cpu_tuple_cost','cpu_index_tuple_cost','cpu_operator_cost',
                                             'effective_cache_size','work_mem','jit','jit_above_cost',
                                             'plan_cache_mode','default_statistics_target',
                                             'from_collapse_limit','join_collapse_limit','geqo',
                                             'geqo_threshold','row_security','transaction_read_only',
                                             'default_transaction_read_only','lock_timeout',
                                             'statement_timeout')),
    'relations',          (SELECT jsonb_agg(jsonb_build_object(
                                      'rel',                 c.relname,
                                      'reltuples',           c.reltuples,
                                      'relpages',            c.relpages,
                                      'n_live_tup',          st.n_live_tup,
                                      'n_dead_tup',          st.n_dead_tup,
                                      'n_mod_since_analyze', st.n_mod_since_analyze,
                                      'last_analyze',        st.last_analyze,
                                      'last_autoanalyze',    st.last_autoanalyze,
                                      'rls',                 c.relrowsecurity,
                                      'force_rls',           c.relforcerowsecurity) ORDER BY c.relname)
                             FROM pg_class c
                             JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
                             LEFT JOIN pg_stat_user_tables st ON st.relid = c.oid
                            WHERE c.relkind = 'r'
                              AND c.relname IN ('asset_source','card_edition_context_external_mapping',
                                                'card_edition_context_external_mapping_trait',
                                                'card_edition_context_profile',
                                                'card_edition_context_profile_trait',
                                                'card_edition_context_trait','card_variant',
                                                'catalog_admin_action_log','catalog_variant_import_job',
                                                'catalog_variant_import_row','game')),
    'card_variant_indexes', (SELECT jsonb_agg(jsonb_build_object(
                                      'index',         ic.relname,
                                      'def',           pg_get_indexdef(i.indexrelid),
                                      'first_key',     a.attname,
                                      'n_key_atts',    i.indnkeyatts,
                                      'unique',        i.indisunique,
                                      'partial',       i.indpred IS NOT NULL,
                                      'valid',         i.indisvalid,
                                      'ready',         i.indisready,
                                      'live',          i.indislive,
                                      'size_bytes',    pg_relation_size(i.indexrelid),
                                      'idx_scan',      si.idx_scan,
                                      'last_idx_scan', si.last_idx_scan) ORDER BY ic.relname)
                               FROM pg_index i
                               JOIN pg_class ic ON ic.oid = i.indexrelid
                               LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                               LEFT JOIN pg_stat_user_indexes si ON si.indexrelid = i.indexrelid
                              WHERE i.indrelid = to_regclass('public.card_variant')),
    'card_id_stats',      COALESCE(
                             (SELECT jsonb_build_object(
                                      'stats_state',     CASE WHEN ps.most_common_vals IS NULL
                                                              THEN 'MCV_NULL' ELSE 'MCV_PRESENT' END,
                                      'n_distinct',      ps.n_distinct,
                                      'null_frac',       ps.null_frac,
                                      'correlation',     ps.correlation,
                                      'mcv_count',       array_length(ps.most_common_freqs, 1),
                                      'mcv_max_freq',    (SELECT max(u.f) FROM unnest(ps.most_common_freqs) AS u(f)),
                                      'literals_in_mcv', CASE WHEN ps.most_common_vals IS NULL THEN NULL
                                                              ELSE (ps.most_common_vals::text)::uuid[] &&
                                                                   ARRAY['00000000-0000-0000-0000-000000000000',
                                                                         '00000000-0000-0000-0000-000000000001',
                                                                         '00000000-0000-0000-0000-000000000002',
                                                                         '00000000-0000-0000-0000-000000000003']::uuid[]
                                                         END)
                                FROM pg_stats ps
                               WHERE ps.schemaname = 'public'
                                 AND ps.tablename = 'card_variant'
                                 AND ps.attname = 'card_id'),
                             jsonb_build_object('stats_state', 'NO_STATS_ROW'))
) AS p9a_representativeness;
```

### A.3 — S3 · P9A-01 (md5 `00301d286aac7e6425a94e81a08794f4`, 53.823 B)

`EXPLAIN (COSTS OFF)` + LF + conteúdo byte a byte do blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` (`2830H_E00_precheck_inventory.sql`, 53.803 B).

### A.4 — S4 · P9A-02 (md5 `54919abf0abb8f65886f5c9c90e4fb13`, 13.064 B)

`EXPLAIN (COSTS OFF)` + LF + Apêndice A de `LIVE-STAGE3-EXECUTION-RECORD.md` (blob `974674f9…`): E99 `49a71ecb…` com os 3 marcadores substituídos (md5 `00233aa60c571994f39df2df3faf05ea`, 13.044 B).

### A.5 — S5 · P9A-03 (md5 `3151a5d16d44373fe78732cb7eb56a57`, 131 B)

```sql
EXPLAIN (COSTS OFF)
SELECT cv.*
  FROM public.card_variant AS cv
 WHERE cv.card_id = '00000000-0000-0000-0000-000000000000'::uuid;
```

### A.6 — S6 · P9A-04 (md5 `e917eb3928cc52b025a4b88afdaf9d22`, 358 B)

```sql
EXPLAIN (COSTS OFF)
SELECT cv.id, cv.card_id, cv.variant_type_id, cv.printing_profile_id, cv.edition_context_profile_id
  FROM public.card_variant AS cv
 WHERE cv.card_id IN ('00000000-0000-0000-0000-000000000001'::uuid,
                      '00000000-0000-0000-0000-000000000002'::uuid,
                      '00000000-0000-0000-0000-000000000003'::uuid);
```

## Apêndice B — Saídas integrais

Corpo devolvido pelo `execute_sql`, sem o invólucro de dados não confiáveis. O md5 é do corpo com o LF final.

### B.1 — S1 · L3 (md5 `a48686ed44ffde2be0fef48ba737b13e`, 3787 B)

```json
[{"l3_concurrency":{"sessions":[{"pid":2819340,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-21T01:53:15.772737+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819351,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:48:20.887492+00:00","wait_event_type":"Client","application_name":"postgres_exporter"},{"pid":2867551,"state":"idle","usename":"supabase_admin","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T12:46:12.093029+00:00","wait_event_type":"Client","application_name":""},{"pid":3520379,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:37:01.01662+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3520415,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:40:02.080177+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3520416,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:40:02.209777+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3521062,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:42:01.298714+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3521063,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:42:01.53808+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3521095,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:45:01.445906+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3521096,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:45:01.990716+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3521124,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:47:00.753122+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":3521125,"state":"idle","usename":"authenticator","wait_event":"ClientRead","xact_start":null,"backend_xid":null,"backend_type":"client backend","state_change":"2026-09-27T14:47:00.855506+00:00","wait_event_type":"Client","application_name":"PostgREST 14.5"},{"pid":2819328,"state":null,"usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_cron launcher","state_change":null,"wait_event_type":"Extension","application_name":"pg_cron scheduler"},{"pid":2819327,"state":"idle","usename":"supabase_admin","wait_event":"Extension","xact_start":null,"backend_xid":null,"backend_type":"pg_net 0.20.4 worker","state_change":"2026-09-27T14:47:03.871143+00:00","wait_event_type":"Extension","application_name":"pg_net 0.20.4"}],"checked_at":"2026-09-27T14:49:18.001598+00:00","locks_on_scope":[]}}]
```

### B.2 — S2 · P9A-00(a) (md5 `2539e3f57e3d7305889b25c1a7427d8e`, 6947 B)

```json
[{"p9a_representativeness":{"relations":[{"rel":"asset_source","rls":true,"relpages":0,"force_rls":false,"reltuples":-1,"n_dead_tup":5,"n_live_tup":4,"last_analyze":null,"last_autoanalyze":null,"n_mod_since_analyze":6},{"rel":"card_edition_context_external_mapping","rls":true,"relpages":5,"force_rls":false,"reltuples":122,"n_dead_tup":22,"n_live_tup":122,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:48:32.681938+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_external_mapping_trait","rls":true,"relpages":2,"force_rls":false,"reltuples":122,"n_dead_tup":20,"n_live_tup":122,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:48:32.671692+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_profile","rls":true,"relpages":10,"force_rls":false,"reltuples":144,"n_dead_tup":68,"n_live_tup":144,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:46:32.69535+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_profile_trait","rls":true,"relpages":3,"force_rls":false,"reltuples":196,"n_dead_tup":88,"n_live_tup":196,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:46:32.696667+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_trait","rls":true,"relpages":4,"force_rls":false,"reltuples":115,"n_dead_tup":25,"n_live_tup":115,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:42:32.522323+00:00","n_mod_since_analyze":0},{"rel":"card_variant","rls":true,"relpages":310,"force_rls":false,"reltuples":24893,"n_dead_tup":0,"n_live_tup":24893,"last_analyze":null,"last_autoanalyze":"2026-09-19T00:48:33.800154+00:00","n_mod_since_analyze":897},{"rel":"catalog_admin_action_log","rls":true,"relpages":83,"force_rls":false,"reltuples":1333,"n_dead_tup":29,"n_live_tup":1352,"last_analyze":null,"last_autoanalyze":"2026-09-19T00:47:34.447399+00:00","n_mod_since_analyze":19},{"rel":"catalog_variant_import_job","rls":true,"relpages":4,"force_rls":false,"reltuples":145,"n_dead_tup":11,"n_live_tup":145,"last_analyze":null,"last_autoanalyze":"2026-09-19T00:48:34.831023+00:00","n_mod_since_analyze":9},{"rel":"catalog_variant_import_row","rls":true,"relpages":1409,"force_rls":false,"reltuples":26127,"n_dead_tup":3903,"n_live_tup":26127,"last_analyze":null,"last_autoanalyze":"2026-09-20T17:30:38.654967+00:00","n_mod_since_analyze":66},{"rel":"game","rls":true,"relpages":0,"force_rls":false,"reltuples":-1,"n_dead_tup":16,"n_live_tup":2,"last_analyze":null,"last_autoanalyze":null,"n_mod_since_analyze":4}],"checked_at":"2026-09-27T14:49:40.983172+00:00","backend_pid":3521158,"in_recovery":false,"stats_reset":"2026-07-15T14:26:35.343646+00:00","current_user":"postgres","card_id_stats":{"mcv_count":100,"null_frac":0,"n_distinct":-0.567595,"correlation":0.0136838,"stats_state":"MCV_PRESENT","mcv_max_freq":0.000375063,"literals_in_mcv":false},"planner_settings":{"jit":"off","geqo":"on","work_mem":"2184","enable_sort":"on","lock_timeout":"0","row_security":"on","seq_page_cost":"1","cpu_tuple_cost":"0.01","enable_hashagg":"on","enable_memoize":"on","enable_seqscan":"on","enable_tidscan":"on","geqo_threshold":"12","jit_above_cost":"100000","enable_hashjoin":"on","enable_material":"on","enable_nestloop":"on","plan_cache_mode":"auto","enable_indexscan":"on","enable_mergejoin":"on","random_page_cost":"1.1","cpu_operator_cost":"0.0025","enable_bitmapscan":"on","statement_timeout":"120000","from_collapse_limit":"8","join_collapse_limit":"8","cpu_index_tuple_cost":"0.005","effective_cache_size":"49152","enable_indexonlyscan":"on","transaction_read_only":"off","enable_incremental_sort":"on","default_statistics_target":"100","default_transaction_read_only":"off"},"server_version_num":"170006","card_variant_indexes":[{"def":"CREATE UNIQUE INDEX card_variant_pkey ON public.card_variant USING btree (id)","live":true,"index":"card_variant_pkey","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":527818,"first_key":"id","n_key_atts":1,"size_bytes":1114112,"last_idx_scan":"2026-09-27T03:56:16.09572+00:00"},{"def":"CREATE INDEX ix_card_variant_card_id ON public.card_variant USING btree (card_id)","live":true,"index":"ix_card_variant_card_id","ready":true,"valid":true,"unique":false,"partial":false,"idx_scan":3397803,"first_key":"card_id","n_key_atts":1,"size_bytes":843776,"last_idx_scan":"2026-09-27T03:56:08.64659+00:00"},{"def":"CREATE INDEX ix_card_variant_edition_context ON public.card_variant USING btree (edition_context_profile_id) WHERE (edition_context_profile_id IS NOT NULL)","live":true,"index":"ix_card_variant_edition_context","ready":true,"valid":true,"unique":false,"partial":true,"idx_scan":38,"first_key":"edition_context_profile_id","n_key_atts":1,"size_bytes":8192,"last_idx_scan":"2026-09-27T03:44:37.192548+00:00"},{"def":"CREATE INDEX ix_card_variant_printing_profile_id ON public.card_variant USING btree (printing_profile_id) WHERE (printing_profile_id IS NOT NULL)","live":true,"index":"ix_card_variant_printing_profile_id","ready":true,"valid":true,"unique":false,"partial":true,"idx_scan":15,"first_key":"printing_profile_id","n_key_atts":1,"size_bytes":32768,"last_idx_scan":"2026-09-25T17:33:23.262719+00:00"},{"def":"CREATE INDEX ix_card_variant_variant_type_id ON public.card_variant USING btree (variant_type_id)","live":true,"index":"ix_card_variant_variant_type_id","ready":true,"valid":true,"unique":false,"partial":false,"idx_scan":5293,"first_key":"variant_type_id","n_key_atts":1,"size_bytes":311296,"last_idx_scan":"2026-09-27T03:44:37.192548+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_card_order ON public.card_variant USING btree (card_id, variant_order)","live":true,"index":"uq_card_variant_card_order","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":25341,"first_key":"card_id","n_key_atts":2,"size_bytes":1327104,"last_idx_scan":"2026-09-25T02:36:18.879367+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_id_card ON public.card_variant USING btree (id, card_id)","live":true,"index":"uq_card_variant_id_card","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":31436,"first_key":"id","n_key_atts":2,"size_bytes":1400832,"last_idx_scan":"2026-09-20T21:14:29.452369+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_identity ON public.card_variant USING btree (card_id, variant_type_id, printing_profile_id, edition_context_profile_id) NULLS NOT DISTINCT","live":true,"index":"uq_card_variant_identity","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":1880,"first_key":"card_id","n_key_atts":4,"size_bytes":1515520,"last_idx_scan":"2026-09-27T03:56:08.64659+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_one_default_per_card ON public.card_variant USING btree (card_id) WHERE (is_default = true)","live":true,"index":"uq_card_variant_one_default_per_card","ready":true,"valid":true,"unique":true,"partial":true,"idx_scan":3694,"first_key":"card_id","n_key_atts":1,"size_bytes":81920,"last_idx_scan":"2026-09-19T01:00:40.660962+00:00"}]}}]
```

### B.3 — S5 · P9A-03 (md5 `03963bcf4712742ef24571dc7e404cf6`, 167 B)

```json
[{"QUERY PLAN":"Index Scan using ix_card_variant_card_id on card_variant cv"},{"QUERY PLAN":"  Index Cond: (card_id = '00000000-0000-0000-0000-000000000000'::uuid)"}]
```

### B.4 — S6 · P9A-04 (md5 `45308e3a868c13b01c353d6b0796b1e3`, 251 B)

```json
[{"QUERY PLAN":"Index Scan using ix_card_variant_card_id on card_variant cv"},{"QUERY PLAN":"  Index Cond: (card_id = ANY ('{00000000-0000-0000-0000-000000000001,00000000-0000-0000-0000-000000000002,00000000-0000-0000-0000-000000000003}'::uuid[]))"}]
```

### B.5 — S7 · P9A-00(b) (md5 `f9a11071b11be9790ba96552a6ccb3ae`, 6947 B)

```json
[{"p9a_representativeness":{"relations":[{"rel":"asset_source","rls":true,"relpages":0,"force_rls":false,"reltuples":-1,"n_dead_tup":5,"n_live_tup":4,"last_analyze":null,"last_autoanalyze":null,"n_mod_since_analyze":6},{"rel":"card_edition_context_external_mapping","rls":true,"relpages":5,"force_rls":false,"reltuples":122,"n_dead_tup":22,"n_live_tup":122,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:48:32.681938+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_external_mapping_trait","rls":true,"relpages":2,"force_rls":false,"reltuples":122,"n_dead_tup":20,"n_live_tup":122,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:48:32.671692+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_profile","rls":true,"relpages":10,"force_rls":false,"reltuples":144,"n_dead_tup":68,"n_live_tup":144,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:46:32.69535+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_profile_trait","rls":true,"relpages":3,"force_rls":false,"reltuples":196,"n_dead_tup":88,"n_live_tup":196,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:46:32.696667+00:00","n_mod_since_analyze":0},{"rel":"card_edition_context_trait","rls":true,"relpages":4,"force_rls":false,"reltuples":115,"n_dead_tup":25,"n_live_tup":115,"last_analyze":null,"last_autoanalyze":"2026-09-20T14:42:32.522323+00:00","n_mod_since_analyze":0},{"rel":"card_variant","rls":true,"relpages":310,"force_rls":false,"reltuples":24893,"n_dead_tup":0,"n_live_tup":24893,"last_analyze":null,"last_autoanalyze":"2026-09-19T00:48:33.800154+00:00","n_mod_since_analyze":897},{"rel":"catalog_admin_action_log","rls":true,"relpages":83,"force_rls":false,"reltuples":1333,"n_dead_tup":29,"n_live_tup":1352,"last_analyze":null,"last_autoanalyze":"2026-09-19T00:47:34.447399+00:00","n_mod_since_analyze":19},{"rel":"catalog_variant_import_job","rls":true,"relpages":4,"force_rls":false,"reltuples":145,"n_dead_tup":11,"n_live_tup":145,"last_analyze":null,"last_autoanalyze":"2026-09-19T00:48:34.831023+00:00","n_mod_since_analyze":9},{"rel":"catalog_variant_import_row","rls":true,"relpages":1409,"force_rls":false,"reltuples":26127,"n_dead_tup":3903,"n_live_tup":26127,"last_analyze":null,"last_autoanalyze":"2026-09-20T17:30:38.654967+00:00","n_mod_since_analyze":66},{"rel":"game","rls":true,"relpages":0,"force_rls":false,"reltuples":-1,"n_dead_tup":16,"n_live_tup":2,"last_analyze":null,"last_autoanalyze":null,"n_mod_since_analyze":4}],"checked_at":"2026-09-27T14:55:19.455163+00:00","backend_pid":3521878,"in_recovery":false,"stats_reset":"2026-07-15T14:26:35.343646+00:00","current_user":"postgres","card_id_stats":{"mcv_count":100,"null_frac":0,"n_distinct":-0.567595,"correlation":0.0136838,"stats_state":"MCV_PRESENT","mcv_max_freq":0.000375063,"literals_in_mcv":false},"planner_settings":{"jit":"off","geqo":"on","work_mem":"2184","enable_sort":"on","lock_timeout":"0","row_security":"on","seq_page_cost":"1","cpu_tuple_cost":"0.01","enable_hashagg":"on","enable_memoize":"on","enable_seqscan":"on","enable_tidscan":"on","geqo_threshold":"12","jit_above_cost":"100000","enable_hashjoin":"on","enable_material":"on","enable_nestloop":"on","plan_cache_mode":"auto","enable_indexscan":"on","enable_mergejoin":"on","random_page_cost":"1.1","cpu_operator_cost":"0.0025","enable_bitmapscan":"on","statement_timeout":"120000","from_collapse_limit":"8","join_collapse_limit":"8","cpu_index_tuple_cost":"0.005","effective_cache_size":"49152","enable_indexonlyscan":"on","transaction_read_only":"off","enable_incremental_sort":"on","default_statistics_target":"100","default_transaction_read_only":"off"},"server_version_num":"170006","card_variant_indexes":[{"def":"CREATE UNIQUE INDEX card_variant_pkey ON public.card_variant USING btree (id)","live":true,"index":"card_variant_pkey","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":527818,"first_key":"id","n_key_atts":1,"size_bytes":1114112,"last_idx_scan":"2026-09-27T03:56:16.09572+00:00"},{"def":"CREATE INDEX ix_card_variant_card_id ON public.card_variant USING btree (card_id)","live":true,"index":"ix_card_variant_card_id","ready":true,"valid":true,"unique":false,"partial":false,"idx_scan":3397803,"first_key":"card_id","n_key_atts":1,"size_bytes":843776,"last_idx_scan":"2026-09-27T03:56:08.64659+00:00"},{"def":"CREATE INDEX ix_card_variant_edition_context ON public.card_variant USING btree (edition_context_profile_id) WHERE (edition_context_profile_id IS NOT NULL)","live":true,"index":"ix_card_variant_edition_context","ready":true,"valid":true,"unique":false,"partial":true,"idx_scan":38,"first_key":"edition_context_profile_id","n_key_atts":1,"size_bytes":8192,"last_idx_scan":"2026-09-27T03:44:37.192548+00:00"},{"def":"CREATE INDEX ix_card_variant_printing_profile_id ON public.card_variant USING btree (printing_profile_id) WHERE (printing_profile_id IS NOT NULL)","live":true,"index":"ix_card_variant_printing_profile_id","ready":true,"valid":true,"unique":false,"partial":true,"idx_scan":15,"first_key":"printing_profile_id","n_key_atts":1,"size_bytes":32768,"last_idx_scan":"2026-09-25T17:33:23.262719+00:00"},{"def":"CREATE INDEX ix_card_variant_variant_type_id ON public.card_variant USING btree (variant_type_id)","live":true,"index":"ix_card_variant_variant_type_id","ready":true,"valid":true,"unique":false,"partial":false,"idx_scan":5293,"first_key":"variant_type_id","n_key_atts":1,"size_bytes":311296,"last_idx_scan":"2026-09-27T03:44:37.192548+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_card_order ON public.card_variant USING btree (card_id, variant_order)","live":true,"index":"uq_card_variant_card_order","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":25341,"first_key":"card_id","n_key_atts":2,"size_bytes":1327104,"last_idx_scan":"2026-09-25T02:36:18.879367+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_id_card ON public.card_variant USING btree (id, card_id)","live":true,"index":"uq_card_variant_id_card","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":31436,"first_key":"id","n_key_atts":2,"size_bytes":1400832,"last_idx_scan":"2026-09-20T21:14:29.452369+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_identity ON public.card_variant USING btree (card_id, variant_type_id, printing_profile_id, edition_context_profile_id) NULLS NOT DISTINCT","live":true,"index":"uq_card_variant_identity","ready":true,"valid":true,"unique":true,"partial":false,"idx_scan":1880,"first_key":"card_id","n_key_atts":4,"size_bytes":1515520,"last_idx_scan":"2026-09-27T03:56:08.64659+00:00"},{"def":"CREATE UNIQUE INDEX uq_card_variant_one_default_per_card ON public.card_variant USING btree (card_id) WHERE (is_default = true)","live":true,"index":"uq_card_variant_one_default_per_card","ready":true,"valid":true,"unique":true,"partial":true,"idx_scan":3694,"first_key":"card_id","n_key_atts":1,"size_bytes":81920,"last_idx_scan":"2026-09-19T01:00:40.660962+00:00"}]}}]
```

### B.6 — S4 · P9A-02 (E99)

- Corpo JSON: md5 `2fec9e00152ab78837c7b8ed2161d858`, 16750 B, 281 linhas `QUERY PLAN`.
- Abaixo, o texto de exibição, uma linha `QUERY PLAN` por linha: md5 `d3279d08d996f657e3b6b38a5d024921`, 11959 B.
- Nenhum caractere de controle nas linhas.
- Reconstrução exata do corpo: trocar `␍` por CR e serializar cada linha como `{"QUERY PLAN":<linha>}` (JSON sem espaços, UTF-8). Unir com `,` entre `[` e `]` e acrescentar LF. Conferido byte a byte.

```text
Result
  CTE captured
    ->  Result
  CTE base
    ->  Result
          InitPlan 2
            ->  Aggregate
                  ->  Index Only Scan using uq_cect_id_game on card_edition_context_trait
          InitPlan 3
            ->  Aggregate
                  ->  Index Only Scan using uq_cecp_game_order on card_edition_context_profile
          InitPlan 4
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_profile_trait
          InitPlan 5
            ->  Aggregate
                  ->  Index Only Scan using uq_cecem_id_game on card_edition_context_external_mapping
          InitPlan 6
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_external_mapping_trait
          InitPlan 7
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_external_mapping card_edition_context_external_mapping_1
                        Filter: (traits_signature IS NULL)
          InitPlan 8
            ->  Aggregate
                  ->  Index Only Scan using ix_card_variant_variant_type_id on card_variant
          InitPlan 9
            ->  Aggregate
                  ->  Index Only Scan using ix_card_variant_edition_context on card_variant card_variant_1
          InitPlan 10
            ->  Aggregate
                  ->  Index Only Scan using ix_catalog_variant_import_row_job on catalog_variant_import_row
          InitPlan 11
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_row catalog_variant_import_row_1
          InitPlan 12
            ->  Aggregate
                  ->  HashAggregate
                        Group Key: ((catalog_variant_import_row_2.validation_status || '/'::text) || catalog_variant_import_row_2.persistence_status)
                        ->  Seq Scan on catalog_variant_import_row catalog_variant_import_row_2
          InitPlan 13
            ->  Aggregate
                  ->  Nested Loop
                        ->  Seq Scan on catalog_variant_import_job j
                              Filter: (status = ANY ('{RECEIVED,PROCESSING,STAGED,CONFIRMING}'::text[]))
                        ->  Index Scan using ix_catalog_variant_import_row_job_persistence on catalog_variant_import_row r
                              Index Cond: ((job_id = j.id) AND (persistence_status = 'PENDING'::text))
          InitPlan 14
            ->  Aggregate
                  ->  Nested Loop
                        ->  Seq Scan on catalog_variant_import_job j_1
                              Filter: (status = 'CANCELLED'::text)
                        ->  Index Scan using ix_catalog_variant_import_row_job on catalog_variant_import_row r_1
                              Index Cond: (job_id = j_1.id)
                              Filter: (NOT jsonb_exists(normalized_data, 'edition_context_profile_id'::text))
          InitPlan 15
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_row catalog_variant_import_row_3
          InitPlan 16
            ->  Aggregate
                  ->  Index Only Scan using ix_catalog_variant_import_job_card_set on catalog_variant_import_job
          InitPlan 17
            ->  Aggregate
                  ->  HashAggregate
                        Group Key: catalog_variant_import_job_1.status
                        ->  Seq Scan on catalog_variant_import_job catalog_variant_import_job_1
          InitPlan 18
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_job catalog_variant_import_job_2
          InitPlan 19
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_job catalog_variant_import_job_3
                        Filter: (status = ANY ('{RECEIVED,PROCESSING,CONFIRMING}'::text[]))
          InitPlan 20
            ->  Aggregate
                  ->  Index Only Scan using ix_catalog_admin_action_log_created_at on catalog_admin_action_log
          InitPlan 21
            ->  Aggregate
                  ->  Index Only Scan using uq_cect_game_code on card_edition_context_trait card_edition_context_trait_1
                        Filter: ((code)::text ~~ '%H2830%'::text)
          InitPlan 22
            ->  Aggregate
                  ->  Index Only Scan using uq_cecp_game_code on card_edition_context_profile card_edition_context_profile_1
                        Filter: ((code)::text ~~ '%H2830%'::text)
          InitPlan 23
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_external_mapping card_edition_context_external_mapping_2
                        Filter: (normalized_token ~~ '%H2830%'::text)
  CTE diff
    ->  Subquery Scan on a
          InitPlan 25
            ->  CTE Scan on captured
          InitPlan 26
            ->  CTE Scan on base
          InitPlan 27
            ->  CTE Scan on captured captured_1
          InitPlan 28
            ->  CTE Scan on base base_1
          ->  HashAggregate
                Group Key: k.k
                ->  Append
                      ->  Nested Loop
                            ->  CTE Scan on captured captured_2
                            ->  Function Scan on jsonb_object_keys k
                                  Filter: (((InitPlan 27).col1 -> k) IS DISTINCT FROM ((InitPlan 28).col1 -> k))
                      ->  Nested Loop
                            ->  CTE Scan on base base_2
                            ->  Function Scan on jsonb_object_keys k_1
                                  Filter: (((InitPlan 27).col1 -> k) IS DISTINCT FROM ((InitPlan 28).col1 -> k))
  CTE canon_diff
    ->  Function Scan on jsonb_each e
          Filter: (((InitPlan 31).col1 -> key) IS DISTINCT FROM value)
          InitPlan 30
            ->  CTE Scan on base base_3
          InitPlan 31
            ->  CTE Scan on base base_4
  InitPlan 33
    ->  CTE Scan on captured captured_3
  InitPlan 34
    ->  CTE Scan on captured captured_4
  InitPlan 35
    ->  CTE Scan on captured captured_5
  InitPlan 36
    ->  CTE Scan on captured captured_6
  InitPlan 37
    ->  Aggregate
          ->  Sort
                Sort Key: k_2.k
                ->  Nested Loop
                      ->  CTE Scan on captured captured_7
                      ->  Function Scan on jsonb_object_keys k_2
  InitPlan 38
    ->  Aggregate
          ->  Sort
                Sort Key: k_3.k
                ->  Nested Loop
                      ->  CTE Scan on base base_5
                      ->  Function Scan on jsonb_object_keys k_3
  InitPlan 39
    ->  CTE Scan on captured captured_8
  InitPlan 40
    ->  CTE Scan on diff
  InitPlan 41
    ->  CTE Scan on canon_diff
  InitPlan 42
    ->  CTE Scan on base base_6
  InitPlan 43
    ->  CTE Scan on base base_7
  InitPlan 44
    ->  CTE Scan on base base_8
  InitPlan 45
    ->  Aggregate
          ->  Nested Loop
                Join Filter: (d.oid = s.datid)
                ->  Function Scan on pg_stat_get_activity s
                      Filter: ((state = ANY ('{"idle in transaction","idle in transaction (aborted)"}'::text[])) AND (backend_type = 'client backend'::text) AND (pid <> pg_backend_pid()))
                ->  Seq Scan on pg_database d
                      Filter: (datname = current_database())
  InitPlan 46
    ->  Aggregate
          ->  Seq Scan on pg_db_role_setting
  InitPlan 47
    ->  CTE Scan on captured captured_9
  InitPlan 63
    ->  Aggregate
          InitPlan 48
            ->  CTE Scan on captured captured_10
          InitPlan 49
            ->  CTE Scan on captured captured_11
          InitPlan 50
            ->  CTE Scan on captured captured_12
          InitPlan 51
            ->  CTE Scan on captured captured_13
          InitPlan 52
            ->  Aggregate
                  ->  Sort
                        Sort Key: k_4.k
                        ->  Nested Loop
                              ->  CTE Scan on captured captured_14
                              ->  Function Scan on jsonb_object_keys k_4
          InitPlan 53
            ->  Aggregate
                  ->  Sort
                        Sort Key: k_5.k
                        ->  Nested Loop
                              ->  CTE Scan on base base_9
                              ->  Function Scan on jsonb_object_keys k_5
          InitPlan 54
            ->  CTE Scan on captured captured_15
          InitPlan 55
            ->  CTE Scan on diff diff_1
          InitPlan 56
            ->  CTE Scan on canon_diff canon_diff_1
          InitPlan 57
            ->  CTE Scan on base base_10
          InitPlan 58
            ->  CTE Scan on base base_11
          InitPlan 59
            ->  CTE Scan on base base_12
          InitPlan 60
            ->  Aggregate
                  ->  Nested Loop
                        Join Filter: (d_1.oid = s_1.datid)
                        ->  Function Scan on pg_stat_get_activity s_1
                              Filter: ((state = ANY ('{"idle in transaction","idle in transaction (aborted)"}'::text[])) AND (backend_type = 'client backend'::text) AND (pid <> pg_backend_pid()))
                        ->  Seq Scan on pg_database d_1
                              Filter: (datname = current_database())
          InitPlan 61
            ->  Aggregate
                  ->  Seq Scan on pg_db_role_setting pg_db_role_setting_1
          InitPlan 62
            ->  CTE Scan on captured captured_16
          ->  Function Scan on jsonb_each_text e_1
  InitPlan 79
    ->  Function Scan on jsonb_each_text e_2
          Filter: (v IS NULL)
          InitPlan 64
            ->  CTE Scan on captured captured_17
          InitPlan 65
            ->  CTE Scan on captured captured_18
          InitPlan 66
            ->  CTE Scan on captured captured_19
          InitPlan 67
            ->  CTE Scan on captured captured_20
          InitPlan 68
            ->  Aggregate
                  ->  Sort
                        Sort Key: k_6.k
                        ->  Nested Loop
                              ->  CTE Scan on captured captured_21
                              ->  Function Scan on jsonb_object_keys k_6
          InitPlan 69
            ->  Aggregate
                  ->  Sort
                        Sort Key: k_7.k
                        ->  Nested Loop
                              ->  CTE Scan on base base_13
                              ->  Function Scan on jsonb_object_keys k_7
          InitPlan 70
            ->  CTE Scan on captured captured_22
          InitPlan 71
            ->  CTE Scan on diff diff_2
          InitPlan 72
            ->  CTE Scan on canon_diff canon_diff_2
          InitPlan 73
            ->  CTE Scan on base base_14
          InitPlan 74
            ->  CTE Scan on base base_15
          InitPlan 75
            ->  CTE Scan on base base_16
          InitPlan 76
            ->  Aggregate
                  ->  Nested Loop
                        Join Filter: (d_2.oid = s_2.datid)
                        ->  Function Scan on pg_stat_get_activity s_2
                              Filter: ((state = ANY ('{"idle in transaction","idle in transaction (aborted)"}'::text[])) AND (backend_type = 'client backend'::text) AND (pid <> pg_backend_pid()))
                        ->  Seq Scan on pg_database d_2
                              Filter: (datname = current_database())
          InitPlan 77
            ->  Aggregate
                  ->  Seq Scan on pg_db_role_setting pg_db_role_setting_2
          InitPlan 78
            ->  CTE Scan on captured captured_23
  InitPlan 80
    ->  Aggregate
          ->  Sort
                Sort Key: d_3.key
                ->  CTE Scan on diff d_3
  InitPlan 81
    ->  Aggregate
          ->  Sort
                Sort Key: cd.key
                ->  CTE Scan on canon_diff cd
  InitPlan 82
    ->  CTE Scan on base base_17
  InitPlan 83
    ->  CTE Scan on base base_18
  InitPlan 84
    ->  Aggregate
          ->  Seq Scan on pg_db_role_setting pg_db_role_setting_3
```

### B.7 — S3 · P9A-01 (E00)

- Corpo JSON: md5 `74288f9e194dfe0f24c1af64d3c4cfed`, 50805 B, 795 linhas `QUERY PLAN`.
- Abaixo, o texto de exibição, uma linha `QUERY PLAN` por linha: md5 `08269e7811841dc80bf76b838fef958e`, 37225 B.
- O caractere de controle CR (U+000D), presente 1 vez na linha 726 (literal `'\r\n'` do E00, cujo LF o próprio EXPLAIN converte em quebra de linha), é exibido como `␍` (U+240D). O símbolo não ocorre em nenhum outro ponto do plano.
- Reconstrução exata do corpo: trocar `␍` por CR e serializar cada linha como `{"QUERY PLAN":<linha>}` (JSON sem espaços, UTF-8). Unir com `,` entre `[` e `]` e acrescentar LF. Conferido byte a byte.

```text
Result
  CTE rel
    ->  Values Scan on "*VALUES*"
  CTE seq
    ->  Unique
          ->  Sort
                Sort Key: "*SELECT* 1".table_name, "*SELECT* 1".sequence_name, ('owned_by'::text COLLATE "C") COLLATE "C"
                ->  Append
                      ->  Subquery Scan on "*SELECT* 1"
                            ->  Nested Loop
                                  Join Filter: (d.refobjid = (r.oid)::oid)
                                  ->  CTE Scan on rel r
                                  ->  Materialize
                                        ->  Nested Loop
                                              ->  Seq Scan on pg_class s
                                                    Filter: (relkind = 'S'::"char")
                                              ->  Index Scan using pg_depend_depender_index on pg_depend d
                                                    Index Cond: ((classid = '1259'::oid) AND (objid = s.oid))
                                                    Filter: (deptype = ANY ('{a,i}'::"char"[]))
                      ->  Nested Loop
                            ->  Nested Loop
                                  ->  CTE Scan on rel r_1
                                  ->  Index Scan using pg_attrdef_adrelid_adnum_index on pg_attrdef ad
                                        Index Cond: (adrelid = (r_1.oid)::oid)
                                        Filter: (pg_get_expr(adbin, adrelid) ~~* '%nextval(%'::text)
                            ->  Index Scan using pg_attribute_relid_attnum_index on pg_attribute a
                                  Index Cond: ((attrelid = ad.adrelid) AND (attnum = ad.adnum))
  CTE p7_re
    ->  Result
  CTE p7_denylist
    ->  Values Scan on "*VALUES*_1"
  CTE p7_reach
    ->  CTE Scan on walk
          CTE walk
            ->  Recursive Union
                  ->  Subquery Scan on p7_roots
                        ->  Unique
                              ->  Sort
                                    Sort Key: tg.tgfoid, r_2.name, r_2.gate_scope, (('trigger '::text || (tg.tgname)::text)) COLLATE "C"
                                    ->  Append
                                          ->  Nested Loop
                                                ->  CTE Scan on rel r_2
                                                ->  Index Scan using pg_trigger_tgrelid_tgname_index on pg_trigger tg
                                                      Index Cond: (tgrelid = (r_2.oid)::oid)
                                                      Filter: (NOT tgisinternal)
                                          ->  Nested Loop
                                                ->  Nested Loop
                                                      ->  CTE Scan on rel r_3
                                                      ->  Index Scan using pg_constraint_conrelid_contypid_conname_index on pg_constraint c
                                                            Index Cond: (conrelid = (r_3.oid)::oid)
                                                ->  Index Scan using pg_depend_depender_index on pg_depend d_1
                                                      Index Cond: ((classid = '2606'::oid) AND (objid = c.oid))
                                                      Filter: (refclassid = '1255'::oid)
                                          ->  Nested Loop
                                                ->  Nested Loop
                                                      ->  Nested Loop
                                                            ->  CTE Scan on rel r_4
                                                            ->  Index Scan using pg_attrdef_adrelid_adnum_index on pg_attrdef ad_1
                                                                  Index Cond: (adrelid = (r_4.oid)::oid)
                                                      ->  Index Scan using pg_depend_depender_index on pg_depend d_2
                                                            Index Cond: ((classid = '2604'::oid) AND (objid = ad_1.oid))
                                                            Filter: (refclassid = '1255'::oid)
                                                ->  Index Scan using pg_attribute_relid_attnum_index on pg_attribute a_1
                                                      Index Cond: ((attrelid = ad_1.adrelid) AND (attnum = ad_1.adnum))
                                          ->  Subquery Scan on "*SELECT* 4"
                                                ->  Nested Loop
                                                      ->  Nested Loop
                                                            ->  CTE Scan on rel r_5
                                                            ->  Index Scan using pg_index_indrelid_index on pg_index i
                                                                  Index Cond: (indrelid = (r_5.oid)::oid)
                                                      ->  Index Scan using pg_depend_depender_index on pg_depend d_3
                                                            Index Cond: ((classid = '1259'::oid) AND (objid = i.indexrelid))
                                                            Filter: (refclassid = '1255'::oid)
                  ->  Nested Loop
                        ->  CTE Scan on p7_re re
                        ->  Nested Loop
                              Join Filter: ((ns.oid = callee.pronamespace) AND (callee.oid <> ALL (w.path)))
                              ->  Hash Join
                                    Hash Cond: (lower(m.m[1]) = ns.nspname)
                                    ->  Nested Loop
                                          ->  Nested Loop
                                                ->  WorkTable Scan on walk w
                                                      Filter: (depth < 8)
                                                ->  Index Scan using pg_proc_oid_index on pg_proc caller
                                                      Index Cond: (oid = w.fn)
                                          ->  Function Scan on regexp_matches m
                                    ->  Hash
                                          ->  Seq Scan on pg_namespace ns
                              ->  Memoize
                                    Cache Key: lower((m.m)[2])
                                    Cache Mode: logical
                                    ->  Index Scan using pg_proc_proname_args_nsp_index on pg_proc callee
                                          Index Cond: (proname = lower((m.m)[2]))
  CTE p7_flags
    ->  Hash Left Join
          Hash Cond: ((n.nspname = "*VALUES*_2".column1) AND (p.proname = "*VALUES*_2".column2) AND ((pg_get_function_identity_arguments(p.oid)) = "*VALUES*_2".column3))
          InitPlan 10
            ->  CTE Scan on p7_re
          InitPlan 11
            ->  CTE Scan on p7_re p7_re_1
          InitPlan 12
            ->  CTE Scan on p7_re p7_re_2
          InitPlan 13
            ->  CTE Scan on p7_re p7_re_3
          InitPlan 15
            ->  CTE Scan on p7_re p7_re_4
          InitPlan 16
            ->  CTE Scan on p7_re p7_re_5
          ->  Unique
                InitPlan 17
                  ->  CTE Scan on p7_re p7_re_6
                ->  Sort
                      Sort Key: x.fn, x.gate_scope, x.depth
                      ->  Nested Loop
                            ->  Nested Loop
                                  ->  Nested Loop
                                        ->  CTE Scan on p7_reach x
                                        ->  Index Scan using pg_proc_oid_index on pg_proc p
                                              Index Cond: (oid = x.fn)
                                  ->  Memoize
                                        Cache Key: p.pronamespace
                                        Cache Mode: logical
                                        ->  Index Scan using pg_namespace_oid_index on pg_namespace n
                                              Index Cond: (oid = p.pronamespace)
                            ->  Memoize
                                  Cache Key: p.prolang
                                  Cache Mode: logical
                                  ->  Index Scan using pg_language_oid_index on pg_language l
                                        Index Cond: (oid = p.prolang)
          ->  Hash
                ->  Values Scan on "*VALUES*_2"
          SubPlan 7
            ->  CTE Scan on p7_denylist
          SubPlan 9
            ->  Nested Loop
                  ->  Seq Scan on pg_extension e
                  ->  Index Scan using pg_depend_reference_index on pg_depend d_4
                        Index Cond: ((refclassid = '3079'::oid) AND (refobjid = e.oid))
                        Filter: ((classid = '1255'::oid) AND (deptype = 'e'::"char"))
          SubPlan 14
            ->  Aggregate
                  ->  Function Scan on unnest e_1
                        Filter: (v ~~ 'search_path=%'::text)
  CTE p7_text
    ->  CTE Scan on p7_flags f
          Filter: (language <> ALL ('{c,internal}'::name[]))
          InitPlan 19
            ->  CTE Scan on p7_re p7_re_7
  CTE p7_unresolved_qualified
    ->  Unique
          InitPlan 21
            ->  CTE Scan on p7_re p7_re_8
          ->  Sort
                Sort Key: t.fqname COLLATE "C", t.gate_scope, (((lower(m_1.m[1]) || '.'::text) || lower(m_1.m[2]))) COLLATE "C"
                ->  Nested Loop Anti Join
                      ->  Hash Anti Join
                            Hash Cond: ((lower(m_1.m[1]) = n_2.nspname) AND (lower(m_1.m[2]) = c_1.relname))
                            ->  Nested Loop
                                  ->  CTE Scan on p7_text t
                                  ->  Function Scan on regexp_matches m_1
                            ->  Hash
                                  ->  Hash Join
                                        Hash Cond: (c_1.relnamespace = n_2.oid)
                                        ->  Seq Scan on pg_class c_1
                                        ->  Hash
                                              ->  Seq Scan on pg_namespace n_2
                      ->  Nested Loop
                            Join Filter: (n_1.nspname = lower((m_1.m)[1]))
                            ->  Index Only Scan using pg_proc_proname_args_nsp_index on pg_proc p_1
                                  Index Cond: (proname = lower((m_1.m)[2]))
                            ->  Index Scan using pg_namespace_oid_index on pg_namespace n_1
                                  Index Cond: (oid = p_1.pronamespace)
  CTE p7_unqualified_calls
    ->  Unique
          InitPlan 29
            ->  CTE Scan on p7_re p7_re_9
          ->  Sort
                Sort Key: t_1.fqname COLLATE "C", t_1.gate_scope, (lower(m_2.m[1])) COLLATE "C", (CASE WHEN (ANY (lower(m_2.m[1]) = (hashed SubPlan 23).col1)) THEN 'KEYWORD'::text WHEN (ANY (lower(m_2.m[1]) = (hashed SubPlan 24).col1)) THEN 'DENIED'::text WHEN (ANY (lower(m_2.m[1]) = (hashed SubPlan 26).col1)) THEN 'BUILTIN'::text WHEN (ANY (lower(m_2.m[1]) = (hashed SubPlan 28).col1)) THEN 'BUILTIN_TYPE'::text ELSE 'UNRESOLVED'::text END)
                ->  Nested Loop
                      ->  CTE Scan on p7_text t_1
                      ->  Function Scan on regexp_matches m_2
                      SubPlan 23
                        ->  ProjectSet
                              ->  Result
                      SubPlan 24
                        ->  CTE Scan on p7_denylist p7_denylist_1
                      SubPlan 26
                        ->  Index Only Scan using pg_proc_proname_args_nsp_index on pg_proc p_2
                              Index Cond: (pronamespace = '11'::oid)
                      SubPlan 28
                        ->  Index Only Scan using pg_type_typname_nsp_index on pg_type ty
                              Index Cond: (typnamespace = '11'::oid)
  CTE p7_writes
    ->  HashAggregate
          Group Key: t_2.fqname, t_2.gate_scope, ((lower(w_1.w[4]) || '.'::text) || lower(w_1.w[5])), (to_regclass(((lower(w_1.w[4]) || '.'::text) || lower(w_1.w[5]))) IS NOT NULL)
          InitPlan 31
            ->  CTE Scan on p7_re p7_re_10
          ->  Nested Loop
                ->  CTE Scan on p7_text t_2
                ->  Function Scan on regexp_matches w_1
  CTE p7_unqualified_writes
    ->  HashAggregate
          Group Key: t_3.fqname, t_3.gate_scope, lower(w_2.w[1]), lower(w_2.w[4])
          InitPlan 33
            ->  CTE Scan on p7_re p7_re_11
          ->  Nested Loop
                ->  CTE Scan on p7_text t_3
                ->  Function Scan on regexp_matches w_2
  CTE p7_rules
    ->  Nested Loop
          ->  CTE Scan on rel r_6
          ->  Index Scan using pg_rewrite_rel_rulename_index on pg_rewrite rw
                Index Cond: (ev_class = (r_6.oid)::oid)
                Filter: (rulename <> '_RETURN'::name)
  CTE evt
    ->  Nested Loop
          ->  Nested Loop
                ->  Nested Loop
                      ->  Seq Scan on pg_event_trigger e_2
                      ->  Index Scan using pg_proc_oid_index on pg_proc p_3
                            Index Cond: (oid = e_2.evtfoid)
                ->  Memoize
                      Cache Key: p_3.pronamespace
                      Cache Mode: logical
                      ->  Index Scan using pg_namespace_oid_index on pg_namespace n_3
                            Index Cond: (oid = p_3.pronamespace)
          ->  Memoize
                Cache Key: p_3.prolang
                Cache Mode: logical
                ->  Index Scan using pg_language_oid_index on pg_language l_1
                      Index Cond: (oid = p_3.prolang)
          SubPlan 36
            ->  Nested Loop
                  Join Filter: (d_5.refobjid = x_1.oid)
                  ->  Index Scan using pg_depend_depender_index on pg_depend d_5
                        Index Cond: ((classid = '1255'::oid) AND (objid = p_3.oid))
                        Filter: ((refclassid = '3079'::oid) AND (deptype = 'e'::"char"))
                  ->  Seq Scan on pg_extension x_1
  CTE evt_allowlist
    ->  Values Scan on "*VALUES*_3"
  CTE evt_unadjudicated
    ->  Hash Right Anti Join
          Hash Cond: ((a_2.name = e_3.name) AND (a_2.event = e_3.event) AND (a_2.enabled = e_3.enabled) AND (a_2.owner = e_3.owner) AND (a_2.fn = e_3.fn) AND (a_2.fn_language = e_3.fn_language) AND (a_2.fn_owner = e_3.fn_owner) AND (a_2.fn_md5_lf = e_3.fn_md5_lf) AND (a_2.fn_secdef = e_3.fn_secdef))
          Join Filter: ((NOT (a_2.tags IS DISTINCT FROM e_3.tags)) AND (NOT (a_2.fn_config IS DISTINCT FROM e_3.fn_config)) AND (NOT (a_2.fn_extension IS DISTINCT FROM e_3.fn_extension)))
          ->  CTE Scan on evt_allowlist a_2
                Filter: ((event = ANY ('{ddl_command_start,ddl_command_end,sql_drop,table_rewrite}'::text[])) AND (NULLIF(btrim(justification), ''::text) IS NOT NULL))
          ->  Hash
                ->  CTE Scan on evt e_3
                      Filter: (enabled <> 'D'::text)
  CTE own
    ->  Nested Loop
          ->  CTE Scan on rel r_7
          ->  Index Scan using pg_class_oid_index on pg_class c_2
                Index Cond: (oid = (r_7.oid)::oid)
  CTE base
    ->  Result
          InitPlan 41
            ->  Aggregate
                  ->  Index Only Scan using uq_cect_id_game on card_edition_context_trait
          InitPlan 42
            ->  Aggregate
                  ->  Index Only Scan using uq_cecp_game_order on card_edition_context_profile
          InitPlan 43
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_profile_trait
          InitPlan 44
            ->  Aggregate
                  ->  Index Only Scan using uq_cecem_id_game on card_edition_context_external_mapping
          InitPlan 45
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_external_mapping_trait
          InitPlan 46
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_external_mapping card_edition_context_external_mapping_1
                        Filter: (traits_signature IS NULL)
          InitPlan 47
            ->  Aggregate
                  ->  Index Only Scan using ix_card_variant_variant_type_id on card_variant
          InitPlan 48
            ->  Aggregate
                  ->  Index Only Scan using ix_card_variant_edition_context on card_variant card_variant_1
          InitPlan 49
            ->  Aggregate
                  ->  Index Only Scan using ix_catalog_variant_import_row_job on catalog_variant_import_row
          InitPlan 50
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_row catalog_variant_import_row_1
          InitPlan 51
            ->  Aggregate
                  ->  HashAggregate
                        Group Key: ((catalog_variant_import_row_2.validation_status || '/'::text) || catalog_variant_import_row_2.persistence_status)
                        ->  Seq Scan on catalog_variant_import_row catalog_variant_import_row_2
          InitPlan 52
            ->  Aggregate
                  ->  Nested Loop
                        ->  Seq Scan on catalog_variant_import_job j
                              Filter: (status = ANY ('{RECEIVED,PROCESSING,STAGED,CONFIRMING}'::text[]))
                        ->  Index Scan using ix_catalog_variant_import_row_job_persistence on catalog_variant_import_row r_8
                              Index Cond: ((job_id = j.id) AND (persistence_status = 'PENDING'::text))
          InitPlan 53
            ->  Aggregate
                  ->  Nested Loop
                        ->  Seq Scan on catalog_variant_import_job j_1
                              Filter: (status = 'CANCELLED'::text)
                        ->  Index Scan using ix_catalog_variant_import_row_job on catalog_variant_import_row r_9
                              Index Cond: (job_id = j_1.id)
                              Filter: (NOT jsonb_exists(normalized_data, 'edition_context_profile_id'::text))
          InitPlan 54
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_row catalog_variant_import_row_3
          InitPlan 55
            ->  Aggregate
                  ->  Index Only Scan using ix_catalog_variant_import_job_card_set on catalog_variant_import_job
          InitPlan 56
            ->  Aggregate
                  ->  HashAggregate
                        Group Key: catalog_variant_import_job_1.status
                        ->  Seq Scan on catalog_variant_import_job catalog_variant_import_job_1
          InitPlan 57
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_job catalog_variant_import_job_2
          InitPlan 58
            ->  Aggregate
                  ->  Seq Scan on catalog_variant_import_job catalog_variant_import_job_3
                        Filter: (status = ANY ('{RECEIVED,PROCESSING,CONFIRMING}'::text[]))
          InitPlan 59
            ->  Aggregate
                  ->  Index Only Scan using ix_catalog_admin_action_log_created_at on catalog_admin_action_log
          InitPlan 60
            ->  Aggregate
                  ->  Index Only Scan using uq_cect_game_code on card_edition_context_trait card_edition_context_trait_1
                        Filter: ((code)::text ~~ '%H2830%'::text)
          InitPlan 61
            ->  Aggregate
                  ->  Index Only Scan using uq_cecp_game_code on card_edition_context_profile card_edition_context_profile_1
                        Filter: ((code)::text ~~ '%H2830%'::text)
          InitPlan 62
            ->  Aggregate
                  ->  Seq Scan on card_edition_context_external_mapping card_edition_context_external_mapping_2
                        Filter: (normalized_token ~~ '%H2830%'::text)
  CTE canon_diff
    ->  Function Scan on jsonb_each e_4
          Filter: (((InitPlan 65).col1 -> key) IS DISTINCT FROM value)
          InitPlan 64
            ->  CTE Scan on base
          InitPlan 65
            ->  CTE Scan on base base_1
  CTE obj
    ->  Result
          InitPlan 67
            ->  Aggregate
                  ->  Index Only Scan using pg_constraint_conname_nsp_index on pg_constraint
                        Index Cond: (conname = ANY ('{ck_cect_code_family_prefix,uq_cect_game_family_order,ck_cecp_signature_not_empty,ck_cecp_signature_shape,ck_cecem_raw_field,fk_cecpt_profile,fk_cecpt_trait}'::name[]))
          InitPlan 68
            ->  Aggregate
                  ->  Function Scan on unnest x_2
                        Filter: (to_regclass(('public.'::text || n)) IS NOT NULL)
          InitPlan 69
            ->  Aggregate
                  ->  Function Scan on unnest x_3
                        Filter: (to_regclass(('public.'::text || n)) IS NOT NULL)
          InitPlan 70
            ->  Aggregate
                  ->  Seq Scan on pg_authid
                        Filter: (rolname = ANY ('{anon,authenticated}'::name[]))
          InitPlan 71
            ->  Aggregate
                  ->  Index Only Scan using uq_game_code on game
                        Index Cond: (code = 'POKEMON'::text)
          InitPlan 72
            ->  Aggregate
                  ->  Index Only Scan using uq_asset_source_code on asset_source
                        Index Cond: (code = 'TCGDEX'::text)
  CTE conc
    ->  Result
          InitPlan 74
            ->  Aggregate
                  ->  Nested Loop
                        Join Filter: (d_6.oid = s_1.datid)
                        ->  Function Scan on pg_stat_get_activity s_1
                              Filter: ((backend_type = 'client backend'::text) AND (state = ANY ('{active,"idle in transaction","idle in transaction (aborted)"}'::text[])) AND (pid <> pg_backend_pid()))
                        ->  Seq Scan on pg_database d_6
                              Filter: (datname = current_database())
  CTE sess
    ->  Result
          InitPlan 76
            ->  Seq Scan on pg_authid pg_authid_1
                  Filter: (rolname = CURRENT_USER)
          InitPlan 77
            ->  Aggregate
                  ->  Seq Scan on pg_db_role_setting
  InitPlan 79
    ->  CTE Scan on obj
  InitPlan 80
    ->  CTE Scan on obj obj_1
  InitPlan 81
    ->  CTE Scan on obj obj_2
  InitPlan 82
    ->  CTE Scan on obj obj_3
  InitPlan 83
    ->  CTE Scan on sess
  InitPlan 84
    ->  CTE Scan on obj obj_4
  InitPlan 85
    ->  CTE Scan on obj obj_5
  InitPlan 86
    ->  CTE Scan on canon_diff
  InitPlan 87
    ->  Hash Join
          Hash Cond: (r_10.name = s_2.table_name)
          ->  CTE Scan on rel r_10
                Filter: touched_now
          ->  Hash
                ->  CTE Scan on seq s_2
  InitPlan 88
    ->  CTE Scan on p7_flags
          Filter: (gate_scope AND (class = ANY ('{UNCLASSIFIED,DENIED}'::text[])))
  InitPlan 89
    ->  CTE Scan on p7_flags p7_flags_1
          Filter: (gate_scope AND (class = 'ALLOWLIST_MISMATCH'::text))
  InitPlan 90
    ->  CTE Scan on p7_flags p7_flags_2
          Filter: (gate_scope AND search_path_unsafe)
  InitPlan 91
    ->  CTE Scan on p7_flags p7_flags_3
          Filter: (gate_scope AND (external_signal OR dynamic_sql))
  InitPlan 92
    ->  CTE Scan on p7_flags p7_flags_4
          Filter: (gate_scope AND ddl_statement)
  InitPlan 93
    ->  CTE Scan on p7_flags p7_flags_5
          Filter: (gate_scope AND unsupported_lexeme)
  InitPlan 94
    ->  CTE Scan on p7_unresolved_qualified
          Filter: gate_scope
  InitPlan 95
    ->  CTE Scan on p7_unqualified_calls
          Filter: (gate_scope AND (resolution = ANY ('{UNRESOLVED,DENIED}'::text[])))
  InitPlan 96
    ->  CTE Scan on p7_unqualified_writes
          Filter: gate_scope
  InitPlan 98
    ->  CTE Scan on p7_writes w_3
          Filter: (gate_scope AND ((NOT target_exists) OR (NOT (ANY (target = (hashed SubPlan 97).col1)))))
          SubPlan 97
            ->  CTE Scan on rel
                  Filter: gate_scope
  InitPlan 99
    ->  CTE Scan on p7_reach
          Filter: (gate_scope AND (depth >= 8))
  InitPlan 100
    ->  Hash Join
          Hash Cond: (rel_1.name = r_11.table_name)
          ->  CTE Scan on rel rel_1
                Filter: gate_scope
          ->  Hash
                ->  CTE Scan on p7_rules r_11
  InitPlan 101
    ->  CTE Scan on evt
          Filter: ((enabled <> 'D'::text) AND (event <> ALL ('{ddl_command_start,ddl_command_end,sql_drop,table_rewrite}'::text[])))
  InitPlan 102
    ->  CTE Scan on evt_unadjudicated
  InitPlan 103
    ->  Aggregate
          ->  Seq Scan on pg_event_trigger
  InitPlan 104
    ->  Aggregate
          ->  CTE Scan on evt evt_1
  InitPlan 105
    ->  Hash Join
          Hash Cond: (r_12.name = o.name)
          ->  CTE Scan on rel r_12
                Filter: touched_now
          ->  Hash
                ->  CTE Scan on own o
                      Filter: force_rls
  InitPlan 106
    ->  CTE Scan on sess sess_1
  InitPlan 107
    ->  Nested Loop
          Join Filter: (o_1.name = r_13.name)
          ->  CTE Scan on rel r_13
                Filter: touched_now
          ->  CTE Scan on own o_1
                Filter: (owner <> CURRENT_USER)
  InitPlan 108
    ->  CTE Scan on base base_2
  InitPlan 109
    ->  CTE Scan on base base_3
  InitPlan 110
    ->  CTE Scan on base base_4
  InitPlan 111
    ->  CTE Scan on conc
  InitPlan 145
    ->  Aggregate
          InitPlan 112
            ->  CTE Scan on obj obj_6
          InitPlan 113
            ->  CTE Scan on obj obj_7
          InitPlan 114
            ->  CTE Scan on obj obj_8
          InitPlan 115
            ->  CTE Scan on obj obj_9
          InitPlan 116
            ->  CTE Scan on sess sess_2
          InitPlan 117
            ->  CTE Scan on obj obj_10
          InitPlan 118
            ->  CTE Scan on obj obj_11
          InitPlan 119
            ->  CTE Scan on canon_diff canon_diff_1
          InitPlan 120
            ->  Hash Join
                  Hash Cond: (r_14.name = s_3.table_name)
                  ->  CTE Scan on rel r_14
                        Filter: touched_now
                  ->  Hash
                        ->  CTE Scan on seq s_3
          InitPlan 121
            ->  CTE Scan on p7_flags p7_flags_6
                  Filter: (gate_scope AND (class = ANY ('{UNCLASSIFIED,DENIED}'::text[])))
          InitPlan 122
            ->  CTE Scan on p7_flags p7_flags_7
                  Filter: (gate_scope AND (class = 'ALLOWLIST_MISMATCH'::text))
          InitPlan 123
            ->  CTE Scan on p7_flags p7_flags_8
                  Filter: (gate_scope AND search_path_unsafe)
          InitPlan 124
            ->  CTE Scan on p7_flags p7_flags_9
                  Filter: (gate_scope AND (external_signal OR dynamic_sql))
          InitPlan 125
            ->  CTE Scan on p7_flags p7_flags_10
                  Filter: (gate_scope AND ddl_statement)
          InitPlan 126
            ->  CTE Scan on p7_flags p7_flags_11
                  Filter: (gate_scope AND unsupported_lexeme)
          InitPlan 127
            ->  CTE Scan on p7_unresolved_qualified p7_unresolved_qualified_1
                  Filter: gate_scope
          InitPlan 128
            ->  CTE Scan on p7_unqualified_calls p7_unqualified_calls_1
                  Filter: (gate_scope AND (resolution = ANY ('{UNRESOLVED,DENIED}'::text[])))
          InitPlan 129
            ->  CTE Scan on p7_unqualified_writes p7_unqualified_writes_1
                  Filter: gate_scope
          InitPlan 131
            ->  CTE Scan on p7_writes w_4
                  Filter: (gate_scope AND ((NOT target_exists) OR (NOT (ANY (target = (hashed SubPlan 130).col1)))))
                  SubPlan 130
                    ->  CTE Scan on rel rel_2
                          Filter: gate_scope
          InitPlan 132
            ->  CTE Scan on p7_reach p7_reach_1
                  Filter: (gate_scope AND (depth >= 8))
          InitPlan 133
            ->  Hash Join
                  Hash Cond: (rel_3.name = r_15.table_name)
                  ->  CTE Scan on rel rel_3
                        Filter: gate_scope
                  ->  Hash
                        ->  CTE Scan on p7_rules r_15
          InitPlan 134
            ->  CTE Scan on evt evt_2
                  Filter: ((enabled <> 'D'::text) AND (event <> ALL ('{ddl_command_start,ddl_command_end,sql_drop,table_rewrite}'::text[])))
          InitPlan 135
            ->  CTE Scan on evt_unadjudicated evt_unadjudicated_1
          InitPlan 136
            ->  Aggregate
                  ->  Seq Scan on pg_event_trigger pg_event_trigger_1
          InitPlan 137
            ->  Aggregate
                  ->  CTE Scan on evt evt_3
          InitPlan 138
            ->  Hash Join
                  Hash Cond: (r_16.name = o_2.name)
                  ->  CTE Scan on rel r_16
                        Filter: touched_now
                  ->  Hash
                        ->  CTE Scan on own o_2
                              Filter: force_rls
          InitPlan 139
            ->  CTE Scan on sess sess_3
          InitPlan 140
            ->  Nested Loop
                  Join Filter: (o_3.name = r_17.name)
                  ->  CTE Scan on rel r_17
                        Filter: touched_now
                  ->  CTE Scan on own o_3
                        Filter: (owner <> CURRENT_USER)
          InitPlan 141
            ->  CTE Scan on base base_5
          InitPlan 142
            ->  CTE Scan on base base_6
          InitPlan 143
            ->  CTE Scan on base base_7
          InitPlan 144
            ->  CTE Scan on conc conc_1
          ->  Function Scan on jsonb_each_text e_5
  InitPlan 179
    ->  Function Scan on jsonb_each_text e_6
          Filter: (v IS NULL)
          InitPlan 146
            ->  CTE Scan on obj obj_12
          InitPlan 147
            ->  CTE Scan on obj obj_13
          InitPlan 148
            ->  CTE Scan on obj obj_14
          InitPlan 149
            ->  CTE Scan on obj obj_15
          InitPlan 150
            ->  CTE Scan on sess sess_4
          InitPlan 151
            ->  CTE Scan on obj obj_16
          InitPlan 152
            ->  CTE Scan on obj obj_17
          InitPlan 153
            ->  CTE Scan on canon_diff canon_diff_2
          InitPlan 154
            ->  Hash Join
                  Hash Cond: (r_18.name = s_4.table_name)
                  ->  CTE Scan on rel r_18
                        Filter: touched_now
                  ->  Hash
                        ->  CTE Scan on seq s_4
          InitPlan 155
            ->  CTE Scan on p7_flags p7_flags_12
                  Filter: (gate_scope AND (class = ANY ('{UNCLASSIFIED,DENIED}'::text[])))
          InitPlan 156
            ->  CTE Scan on p7_flags p7_flags_13
                  Filter: (gate_scope AND (class = 'ALLOWLIST_MISMATCH'::text))
          InitPlan 157
            ->  CTE Scan on p7_flags p7_flags_14
                  Filter: (gate_scope AND search_path_unsafe)
          InitPlan 158
            ->  CTE Scan on p7_flags p7_flags_15
                  Filter: (gate_scope AND (external_signal OR dynamic_sql))
          InitPlan 159
            ->  CTE Scan on p7_flags p7_flags_16
                  Filter: (gate_scope AND ddl_statement)
          InitPlan 160
            ->  CTE Scan on p7_flags p7_flags_17
                  Filter: (gate_scope AND unsupported_lexeme)
          InitPlan 161
            ->  CTE Scan on p7_unresolved_qualified p7_unresolved_qualified_2
                  Filter: gate_scope
          InitPlan 162
            ->  CTE Scan on p7_unqualified_calls p7_unqualified_calls_2
                  Filter: (gate_scope AND (resolution = ANY ('{UNRESOLVED,DENIED}'::text[])))
          InitPlan 163
            ->  CTE Scan on p7_unqualified_writes p7_unqualified_writes_2
                  Filter: gate_scope
          InitPlan 165
            ->  CTE Scan on p7_writes w_5
                  Filter: (gate_scope AND ((NOT target_exists) OR (NOT (ANY (target = (hashed SubPlan 164).col1)))))
                  SubPlan 164
                    ->  CTE Scan on rel rel_4
                          Filter: gate_scope
          InitPlan 166
            ->  CTE Scan on p7_reach p7_reach_2
                  Filter: (gate_scope AND (depth >= 8))
          InitPlan 167
            ->  Hash Join
                  Hash Cond: (rel_5.name = r_19.table_name)
                  ->  CTE Scan on rel rel_5
                        Filter: gate_scope
                  ->  Hash
                        ->  CTE Scan on p7_rules r_19
          InitPlan 168
            ->  CTE Scan on evt evt_4
                  Filter: ((enabled <> 'D'::text) AND (event <> ALL ('{ddl_command_start,ddl_command_end,sql_drop,table_rewrite}'::text[])))
          InitPlan 169
            ->  CTE Scan on evt_unadjudicated evt_unadjudicated_2
          InitPlan 170
            ->  Aggregate
                  ->  Seq Scan on pg_event_trigger pg_event_trigger_2
          InitPlan 171
            ->  Aggregate
                  ->  CTE Scan on evt evt_5
          InitPlan 172
            ->  Hash Join
                  Hash Cond: (r_20.name = o_4.name)
                  ->  CTE Scan on rel r_20
                        Filter: touched_now
                  ->  Hash
                        ->  CTE Scan on own o_4
                              Filter: force_rls
          InitPlan 173
            ->  CTE Scan on sess sess_5
          InitPlan 174
            ->  Nested Loop
                  Join Filter: (o_5.name = r_21.name)
                  ->  CTE Scan on rel r_21
                        Filter: touched_now
                  ->  CTE Scan on own o_5
                        Filter: (owner <> CURRENT_USER)
          InitPlan 175
            ->  CTE Scan on base base_8
          InitPlan 176
            ->  CTE Scan on base base_9
          InitPlan 177
            ->  CTE Scan on base base_10
          InitPlan 178
            ->  CTE Scan on conc conc_2
  InitPlan 180
    ->  Aggregate
          ->  Sort
                Sort Key: cd.key
                ->  CTE Scan on canon_diff cd
  InitPlan 181
    ->  CTE Scan on base base_11
  InitPlan 182
    ->  CTE Scan on base base_12
  InitPlan 183
    ->  Aggregate
          ->  CTE Scan on seq s_5
  InitPlan 184
    ->  Aggregate
          ->  Sort
                Sort Key: f_1.gate_scope DESC, f_1.class, f_1.fqname COLLATE "C"
                ->  CTE Scan on p7_flags f_1
  InitPlan 185
    ->  Aggregate
          ->  Sort
                Sort Key: f_2.fqname COLLATE "C"
                ->  CTE Scan on p7_flags f_2
                      Filter: (gate_scope AND (language <> ALL ('{c,internal}'::name[])) AND (md5(prosrc) <> md5(replace(prosrc, '␍
'::text, '
'::text))))
  InitPlan 186
    ->  Aggregate
          ->  CTE Scan on p7_unresolved_qualified u
  InitPlan 187
    ->  Aggregate
          ->  Incremental Sort
                Sort Key: u_1.caller COLLATE "C", u_1.name COLLATE "C"
                Presorted Key: u_1.caller
                ->  CTE Scan on p7_unqualified_calls u_1
  InitPlan 188
    ->  Aggregate
          ->  Sort
                Sort Key: w_6.writer COLLATE "C", w_6.target COLLATE "C"
                ->  CTE Scan on p7_writes w_6
  InitPlan 189
    ->  Aggregate
          ->  CTE Scan on p7_unqualified_writes w_7
  InitPlan 190
    ->  Aggregate
          ->  CTE Scan on p7_rules r_22
  InitPlan 191
    ->  Aggregate
          ->  Sort
                Sort Key: e_7.name COLLATE "C"
                ->  CTE Scan on evt e_7
  InitPlan 192
    ->  Aggregate
          ->  Seq Scan on pg_event_trigger pg_event_trigger_3
  InitPlan 193
    ->  Aggregate
          ->  Sort
                Sort Key: u_2.name COLLATE "C"
                ->  CTE Scan on evt_unadjudicated u_2
  InitPlan 194
    ->  Aggregate
          ->  Sort
                Sort Key: a_3.name
                ->  Hash Right Anti Join
                      Hash Cond: (e_8.name = a_3.name)
                      ->  CTE Scan on evt e_8
                      ->  Hash
                            ->  CTE Scan on evt_allowlist a_3
  InitPlan 195
    ->  Aggregate
          ->  Nested Loop
                Join Filter: (c_3.relnamespace = n_4.oid)
                ->  Index Scan using pg_namespace_nspname_index on pg_namespace n_4
                      Index Cond: (nspname = 'public'::name)
                ->  Nested Loop
                      ->  Seq Scan on pg_publication p_4
                      ->  Hash Join
                            Hash Cond: (gpt.relid = c_3.oid)
                            ->  Function Scan on pg_get_publication_tables gpt
                            ->  Hash
                                  ->  Nested Loop
                                        ->  CTE Scan on rel r_23
                                        ->  Index Scan using pg_class_relname_nsp_index on pg_class c_3
                                              Index Cond: (relname = (r_23.name)::text)
  InitPlan 196
    ->  Aggregate
          ->  CTE Scan on own o_6
  InitPlan 197
    ->  CTE Scan on obj obj_18
  InitPlan 198
    ->  CTE Scan on conc conc_3
  InitPlan 199
    ->  CTE Scan on sess sess_6
```

## Apêndice C — Respostas originais do canal

Texto bruto devolvido pelo MCP para cada chamada, com o invólucro `{"result": "… <untrusted-data-…> … </untrusted-data-…> …"}`. O identificador do invólucro é aleatório por chamada.

- Os arquivos brutos estão preservados no pacote de evidências fora do repositório (`p9a_live_17857efb/raw_S*.txt`).
- O corpo extraído de cada um é idêntico ao do Apêndice B.

| # | Arquivo | md5 | Bytes |
|---|---|---|---|
| S1 | `raw_S1_L3.txt` | `fafcecde8af66a2cd58843481df588ac` | 4786 |
| S2 | `raw_S2_P9A00.txt` | `29d6b444b6314d898918b90b0bb5e021` | 8190 |
| S3 | `raw_S3_P9A01.txt` | `41266247799884c39d95f7bc70ec9eb0` | 54631 |
| S4 | `raw_S4_P9A02.txt` | `354a9cf38c1b175c0ced0a237375af5a` | 18415 |
| S5 | `raw_S5_P9A03.txt` | `3a320354caa35f186af07e8b5b094760` | 692 |
| S6 | `raw_S6_P9A04.txt` | `2f406f138f1b8e9d1689845de248b00b` | 776 |
| S7 | `raw_S7_P9A00.txt` | `0547f6ab226ce7a84a7c4db5783d5be5` | 8190 |

A resposta do S3 excedeu o limite de exibição, e o cliente a gravou em `tool-results/mcp-…-execute_sql-1790520869663.txt`. `raw_S3_P9A01.txt` é cópia byte a byte desse arquivo.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P9A-LIVE-EVIDENCE-CLOSEOUT-01`), documental, sem nova execução LIVE.** Registra a execução `BATCH12-2830-P9A-LIVE-EXECUTION-01` (baseline `17857efb`, sete chamadas, sem STOP):<br>• preflight;<br>• cronologia;<br>• EV1–EV4 7/7;<br>• planos com FLAG-NL/FLAG-SP ausentes;<br>• snapshots (a)=(b) exceto `checked_at`/`backend_pid`.<br>Classificações: P9A-01/02 REGISTRADO; 6.1 NÃO DEMONSTRADO (planos observados usaram `ix_card_variant_card_id`, sem afirmar impossibilidade de uso de `uq_card_variant_identity`); 6.2 EVIDÊNCIA — CENÁRIO PEQUENO, aguardando decisão de Fabrício. P9a não concluído globalmente; A2 não cumprido; FREEZE ATIVO. |
