# 2830H — Readiness de P9a (forma do plano por `EXPLAIN (COSTS OFF)`)

| Campo | Valor |
|---|---|
| **Natureza** | Preparação documental, **sem execução**. Nenhum SQL foi executado e o LIVE não foi acessado nesta rodada. |
| **Mandato** | `BATCH12-2830-P9A-READINESS-01`. Baseline HEAD `91de54efc99af341765200b3f7bfe22783c85cab`. |
| **Autoridades** | 2830 v7.0 (imutável, blob `b4647dcb…`): P9(a), A2, Seção 6 (6.1, 6.2) e D5. `LIVE-VALIDATION-PROTOCOL.md` v1.6 rev. 1.6.1: S1.6, AD-2, D-2. `LIVE-STAGE1-RUNBOOK.md`: P-2. Etapas 1–3 publicadas (`91de54ef`). |
| **Estado** | **PREPARADO — NÃO EXECUTADO.** P9a, P9b, A2, 6.1 e 6.2 continuam **não cumpridos**. D-2 e D-1/P14 continuam **PENDENTES** e não são presumidos. FREEZE ATIVO. A execução exige auditoria independente e mandato específico. |

---

## 1. Requisitos de origem (texto da 2830 v7.0)

| Id | Onde, na 2830 | Exigência |
|---|---|---|
| **P9(a)** | P9, "FORMA DO PLANO" | `EXPLAIN (COSTS OFF)` das **consultas pesadas**, no LIVE, read-only. Mostra índices e joins usados. **Não** mede tempo e **não** prova que o envelope cabe em 120 s. |
| **A2** | Critérios de aceite, A | Auditoria estática **+** P9a no LIVE **+** medição real de tempo em ambiente isolado (P9b). Os três juntos; P9a sozinho não cumpre A2. |
| **6.1** | Seção 6 (manual) | "EXPLAIN de busca por `card_id` usa `uq_card_variant_identity` (prefixo)". |
| **6.2** | Seção 6 (manual) | "decisão sobre `ix_card_variant_card_id` com EXPLAIN real". |
| **D5** | Critérios de aceite, D | 6.1 e 6.2: EXPLAIN **sem ANALYZE**, salvo autorização, no LIVE, **registrado**. |

A 2830 não enumera quais são as "consultas pesadas". A P9(b) nomeia as seções pesadas **B, M e 5.2/5.3/5.7**. O protocolo (S1.6) e o roteiro (P-2) nomeiam o **E00**.

## 2. Aplicabilidade por artefato vigente

| Artefato | Forma | Relações de dado lidas | P9a aplicável? | Motivo |
|---|---|---|---|---|
| **E00** (blob `a4dd8438…`) | 1 `SELECT` (`WITH … SELECT`, um só `;`) | as 11 relações `public` do escopo; `catalog_variant_import_row` (26.127) e `card_variant` (24.893) varridas integralmente pelo `BASELINE-BUILDER` | **Sim** | Protocolo S1.6 e roteiro P-2 o nomeiam; é a leitura mais pesada da rodada e roda antes de cada envelope. Como é um único `SELECT`, aceita `EXPLAIN` sem alterar o blob. |
| **E99** (blob `49a71ecb…`) | 1 `SELECT` com 3 marcadores | o mesmo `BASELINE-BUILDER` (bloco byte-idêntico ao do E00, provado por `static_check`), mais a busca de marcador nas tabelas EC | **Sim** | Roda depois de cada envelope, com a mesma carga do E00. O plano depende do statement inteiro, não só do bloco comum. |
| **E01** (blob `c4118b8c…`) | bloco `DO` | só catálogo (`pg_class`, `pg_index`, `pg_constraint`, `pg_attribute`) e tabelas pequenas (EC ≤ 196, `game`, `asset_source`) | **Não** | Não há consulta pesada. `EXPLAIN` não aceita `DO`; extrair statements criaria texto novo, sem correspondência de blob. Tempo medido no LIVE: `elapsed_ms=251`. |
| **E02** (blob `3357ed46…`) | bloco `DO` | só catálogo | **Não** | Mesmo motivo; `elapsed_ms=20`. |
| Seções **B, M, 5.2/5.3/5.7** | — | — | **Não preparável agora** | Não existe artefato de harness para elas (a rodada cobre 17/135). Pela AD-2, elas exigem readiness própria antes do LIVE. É **blocker de A2**, não desta readiness. |

## 3. Matriz requisito → consulta → fonte → evidência → aceite

| Id | Requisito | Consulta | Fonte (correspondência) | Evidência a registrar | Critério |
|---|---|---|---|---|---|
| **P9A-01** | P9(a) | `EXPLAIN (COSTS OFF)` + E00 verbatim | blob `a4dd8438…` (S1.6/P-2) | saída integral + md5; inventário de nós de acesso por relação de L | §6.1 |
| **P9A-02** | P9(a) | `EXPLAIN (COSTS OFF)` + E99 com marcadores | E99 blob `49a71ecb…`, com os marcadores do texto **publicado** no Apêndice A do registro da Etapa 3 (md5 `00233aa6…`) | idem | §6.1 |
| **P9A-03** | 6.1 (e D5) | `EXPLAIN (COSTS OFF)` de busca por `card_id` | texto literal de 6.1: "busca por `card_id`" | saída integral + md5; índice e `Index Cond` usados no acesso a `card_variant` (diagnóstico de planejamento, não desempenho) | §6.2 |
| **P9A-04** | 6.2 (e D5) | `EXPLAIN (COSTS OFF)` da forma do consumidor real por `card_id` | `listExistingCardVariantsMap` (`supabase/functions/import-card-variants/services/database.ts`, l. 605–631): projeção de identidade, filtro de pertença em `card_id` | idem; cenário pequeno (N = 3) | §6.3 |
| **P9A-05** | 6.2 (evidência complementar; cenários de catálogo) | P9A-05a (leitura dos cenários p50/p95/máximo, deduplicados por `card_set_id`) + P9A-05b (EXPLAIN por `card_set_id` distinto) | forma do consumidor (`index.ts`, l. 813/828); tamanho = **teto de catálogo** (todas as Cards do Set), não `correlatedCardIds` | saída integral + md5 de cada chamada, com `card_set_id` e rótulos | §5.6 e §6.3 — complementar, não conclusivo; **só com autorização expressa**; não coletado |
| **P9A-00** | representatividade de P9A-01…05b, e o "índices efetivamente existentes" de 6.1/6.2 | `SELECT` de catálogo e estatísticas (§5.1) | `pg_index`, `pg_stat_*`, `pg_stats`, `pg_settings` | saída integral, antes e depois dos EXPLAIN | §6.4 |

Todas as consultas propostas têm correspondência demonstrada com o requisito de origem. Não há condição de STOP nesta preparação. Os candidatos sem correspondência demonstrável **não** foram propostos (§8).

## 4. Parâmetros, dependências e limites de representatividade

**Parâmetros**
- P9A-01: nenhum. O texto é o blob.
- P9A-02: os 3 marcadores do E99. Usa-se o texto já publicado e executado na Etapa 3. `EXPLAIN` não executa, portanto os valores não são comparados, e **P9A-02 não é prova de resíduo**: nenhum gate do E99 é avaliado.
- P9A-03: um `uuid` sintético, `00000000-0000-0000-0000-000000000000`. É **diagnóstico de planejamento**: mostra qual caminho o planner escolhe para um valor fora da MCV. **Não** é prova representativa de desempenho. P9A-00 verifica se o literal está na MCV; com estatística ou MCV indisponível, o resultado é UNKNOWN.
- P9A-04: três `uuid` sintéticos (`…0001`, `…0002`, `…0003`), com a mesma verificação e a mesma leitura UNKNOWN. Cobre só o cenário pequeno (N = 3); cenários maiores de catálogo, não a cardinalidade efetivamente processada, estão no P9A-05 (§5.6).

**Dependências**
- HEAD `91de54ef` e árvore limpa.
- Blobs: E00 `a4dd8438…`, E99 `49a71ecb…`, registro da Etapa 3 `974674f9…` (Apêndice A), protocolo `abe806d6…` (L3).
- PG ≥ 16, por causa de `pg_stat_user_indexes.last_idx_scan`. A L1 registrou `170006`.
- Canal MCP `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`, papel `postgres`, dono das tabelas.

**Limites de representatividade (declarados, não mitigáveis nesta fase)**
1. **Estatísticas:** o plano reflete o `ANALYZE` vigente. Não se roda `ANALYZE`, que é escrita em catálogo. P9A-00 registra `last_analyze`/`last_autoanalyze` antes e depois.
2. **GUCs da sessão:** o plano vale para a configuração do canal. P9A-00 registra os parâmetros do planner.
3. **RLS:** o canal roda como dono, sem `FORCE RLS`, então as políticas não entram no plano. Consumidores `authenticated`/`service_role` podem ter predicados adicionais.
4. **Literal × valor real:** um valor frequente (MCV) pode gerar outro plano. P9A-00 verifica se os literais estão na MCV (tri-state, UNKNOWN sem estatística), mas não cobre cartas com muitas variantes.
5. **P9A-04 com N = 3:** o consumidor real envia todas as Cards correlacionadas de um Card Set, com N desconhecido nesta fase. Para N grande o plano pode mudar (Bitmap ou Seq Scan). A evidência vale **só** para N pequeno; o P9A-05 (§5.6), dependente de autorização futura, cobre só cenários de tamanho de catálogo (teto potencial), não a cardinalidade efetivamente processada.
6. **Texto do PostgREST:** o filtro `.in()` gera um predicado de pertença cujo texto exato não é observável sem log. O `IN (…)` usado é normalizado pelo planner para `= ANY(ARRAY[…])`.
7. **Contrafactual de 6.2:** o plano **sem** `ix_card_variant_card_id` não pode ser observado no LIVE. Exigiria `DROP INDEX` (DDL sob FREEZE), `SET enable_*` (alteração de sessão, proibida) ou extensão hipotética. Nenhum desses é permitido.
8. **Plano ≠ tempo:** nenhuma saída aqui serve como prova de tempo (P9b).

## 5. SQL proposto (íntegra)

Cada item é **uma chamada** `execute_sql`. O texto submetido é exatamente o indicado, verbatim, com LF.

| Chamada | Texto submetido | md5 esperado | Bytes |
|---|---|---|---|
| L3 | Query L3 do protocolo §3.2 | `b7bc3700aeef278f6a79bd30e6a8d229` | 1.526 |
| P9A-00 | conteúdo do bloco §5.1 (sem as cercas, com o LF final) | `da737699bd8e870f9c26b76466f8281f` | 6.629 |
| P9A-01 | §5.2 | `00301d286aac7e6425a94e81a08794f4` | 53.823 |
| P9A-02 | §5.3 | `54919abf0abb8f65886f5c9c90e4fb13` | 13.064 |
| P9A-03 | conteúdo do bloco §5.4 | `3151a5d16d44373fe78732cb7eb56a57` | 131 |
| P9A-04 | conteúdo do bloco §5.5 | `e917eb3928cc52b025a4b88afdaf9d22` | 358 |
| P9A-05a | conteúdo do bloco §5.6 (só com autorização) | `9836e429dcfc31e7ee8f0ad0ab2a6824` | 1.857 |
| P9A-05b | composto localmente, um por `card_set_id` distinto de P9A-05a (§5.6); md5 registrado antes da submissão | — | — |

**Verificação local feita:**
- parênteses balanceados, aspas pares e um único `;` por texto;
- 0 CR.

**Verificação não disponível:** não há parser PostgreSQL neste ambiente.
- A compilação de P9A-00/03/04/05a só é provada executando.
- P9A-01/02 reutilizam textos já compilados e executados no LIVE.
- Erro de sintaxe na execução ⇒ STOP sem retry e mandato de correção; nunca ajuste em linha.

### 5.0 L3 — concorrência (antes dos EXPLAIN)

- Texto literal da **Query L3** do `LIVE-VALIDATION-PROTOCOL.md` §3.2 (md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1.526 B), já executado nas Etapas 1–3.
- Serve só para mitigar o risco R1 (espera de lock).

### 5.1 P9A-00 — representatividade e índices efetivos (SELECT de catálogo)

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

Só lê catálogo e visões de estatística. Não lê linhas de negócio e não expõe valores de `card_id`: a MCV é usada apenas num teste de interseção.

`literals_in_mcv` é tri-state:
- `false` só quando `stats_state = MCV_PRESENT` e não há interseção;
- `true` quando há interseção;
- ausente ou `null` quando `stats_state` é `MCV_NULL` ou `NO_STATS_ROW`, que se lê **UNKNOWN**.

Estatística ou MCV indisponível **nunca** é tratada como prova de que os literais estão fora da MCV. `pg_stats` também oculta linhas sem privilégio de leitura da coluna; o canal roda como dono.

### 5.2 P9A-01 — E00

- **Texto submetido:** `EXPLAIN (COSTS OFF)` + LF + o conteúdo **byte a byte** do blob `a4dd84381b928727611a51147ba1a4c1d11b89ab`.
- **Esperado localmente:** md5 `00301d286aac7e6425a94e81a08794f4`, 53.823 B, 0 CR.
- O arquivo começa com comentários e termina em `FROM gates g;`. O prefixo não altera nenhum token do E00.

### 5.3 P9A-02 — E99

- **Texto submetido:** `EXPLAIN (COSTS OFF)` + LF + o texto do Apêndice A de `LIVE-STAGE3-EXECUTION-RECORD.md` (blob `974674f9…`). Esse texto é o E99 `49a71ecb…` com os 3 marcadores substituídos (md5 `00233aa60c571994f39df2df3faf05ea`, 13.044 B).
- **Esperado localmente:** md5 `54919abf0abb8f65886f5c9c90e4fb13`, 13.064 B, 0 CR.

### 5.4 P9A-03 — requisito 6.1

```sql
EXPLAIN (COSTS OFF)
SELECT cv.*
  FROM public.card_variant AS cv
 WHERE cv.card_id = '00000000-0000-0000-0000-000000000000'::uuid;
```

### 5.5 P9A-04 — requisito 6.2

```sql
EXPLAIN (COSTS OFF)
SELECT cv.id, cv.card_id, cv.variant_type_id, cv.printing_profile_id, cv.edition_context_profile_id
  FROM public.card_variant AS cv
 WHERE cv.card_id IN ('00000000-0000-0000-0000-000000000001'::uuid,
                      '00000000-0000-0000-0000-000000000002'::uuid,
                      '00000000-0000-0000-0000-000000000003'::uuid);
```

### 5.6 P9A-05 — requisito 6.2, cenários de catálogo p50/p95/máximo (PROPOSTA CONDICIONAL: DEFINIDO, NÃO AUTORIZADO, NÃO COLETADO)

**Estado:** nenhum parâmetro foi coletado e nenhuma consulta foi executada. P9A-05 **lê dado de negócio** (`card`, `catalog_variant_import_job`). Por isso só pode rodar com **autorização expressa** no futuro mandato LIVE. Sem essa autorização, 6.2 fica limitado ao cenário pequeno de P9A-04.

**Classificação:** P9A-05 é **evidência complementar de cenários de tamanho de catálogo**. **Não** é medição representativa da cardinalidade efetivamente processada pelo consumidor e **não** torna 6.2 conclusivo por si só.

**O que o consumidor envia e o que P9A-05 mede**
- O consumidor envia `correlatedCardIds`: só as Cards **distintas** de um Card Set que foram **correlacionadas** na importação (`supabase/functions/import-card-variants/index.ts`, l. 813 → `listExistingCardVariantsMap`, l. 828). É um subconjunto das Cards do Set, de tamanho não registrado no banco.
- P9A-05a usa **todas** as Cards de cada Card Set. Isso é o **teto potencial** do lote, não o lote efetivamente enviado.
- **Limite do universo:** o universo são os Card Sets com ao menos um `catalog_variant_import_job`. A existência de um job **não comprova** que `listExistingCardVariantsMap` foi chamado para aquele Set: o job pode ter parado antes da etapa de correlação (por exemplo, falha de fonte, erro ou cancelamento). O universo é, portanto, "Sets que entraram no fluxo de importação", não "Sets em que a consulta do consumidor rodou".

**Cenários:** três tamanhos-alvo, **p50**, **p95** e **máximo** da distribuição de Cards por Card Set no universo acima.
- Cada tamanho-alvo aponta para um Card Set real, com desempate determinístico pelo menor `card_set_id`.
- **Deduplicação no próprio SQL:** P9A-05a agrupa por `card_set_id` antes de devolver os lotes. Cada `card_set_id` aparece **uma vez**, com **todos** os rótulos que lhe couberam (ex.: `["p95","max"]`), em ordem determinística.
- Por isso P9A-05b gera **um plano por `card_set_id` distinto**, nunca dois planos para o mesmo Set: no máximo 3 chamadas, menos se houver coincidência.

**P9A-05a — leitura dos cenários** (SELECT; só com autorização)

```sql
WITH consumer_sets AS (
    SELECT DISTINCT j.card_set_id
      FROM public.catalog_variant_import_job AS j
),
per_set AS (
    SELECT s.card_set_id, count(c.id) AS n_cards
      FROM consumer_sets AS s
      JOIN public.card AS c ON c.card_set_id = s.card_set_id
     GROUP BY s.card_set_id
),
q AS (
    SELECT count(*)                                              AS n_sets,
           percentile_disc(0.50) WITHIN GROUP (ORDER BY n_cards) AS p50,
           percentile_disc(0.95) WITHIN GROUP (ORDER BY n_cards) AS p95,
           max(n_cards)                                          AS pmax
      FROM per_set
),
pick AS (
    SELECT t.label, t.target,
           (SELECT p.card_set_id
              FROM per_set AS p
             WHERE p.n_cards = t.target
             ORDER BY p.card_set_id
             LIMIT 1) AS card_set_id
      FROM q
     CROSS JOIN LATERAL (VALUES ('p50', q.p50), ('p95', q.p95), ('max', q.pmax)) AS t(label, target)
),
lots AS (
    SELECT k.card_set_id,
           min(k.target)                                AS n_cards,
           jsonb_agg(k.label ORDER BY k.target, k.label) AS labels
      FROM pick AS k
     GROUP BY k.card_set_id
)
SELECT jsonb_build_object(
    'checked_at', clock_timestamp(),
    'n_sets',     (SELECT n_sets FROM q),
    'lots',       (SELECT jsonb_agg(jsonb_build_object(
                             'card_set_id', l.card_set_id,
                             'labels',      l.labels,
                             'n_cards',     l.n_cards,
                             'card_ids',    (SELECT jsonb_agg(c.id ORDER BY c.id)
                                               FROM public.card AS c
                                              WHERE c.card_set_id = l.card_set_id))
                           ORDER BY l.n_cards, l.card_set_id)
                     FROM lots AS l)
) AS p9a05_lots;
```

**P9A-05b — EXPLAIN por `card_set_id` distinto** (modelo; no máximo 3 chamadas; só com autorização)
- Uma chamada por elemento de `lots`, na ordem devolvida (`n_cards`, depois `card_set_id`). O registro de cada plano carrega o `card_set_id` e **todos** os seus `labels`.
- O texto é o de P9A-04 com a lista do `IN (…)` substituída pelos `card_ids` do lote, na ordem devolvida por P9A-05a.
- Cada literal tem a forma `'<uuid>'::uuid`, separado por `,` + LF + 22 espaços.
- O texto final de cada lote é composto localmente. Seu md5 é registrado **antes** da submissão (EV1). O texto não é redigitado: é gerado a partir da saída integral de P9A-05a.

**Critérios de P9A-05**
- `n_sets = 0`, ou lote com `card_set_id` ou `card_ids` nulo ou vazio ⇒ STOP: não há cenário de catálogo.
- `card_set_id` repetido em `lots` ⇒ STOP: violaria a deduplicação; não gerar P9A-05b.
- Cada P9A-05b segue EV1–EV4 e a classificação por caminho de acesso do §6.3, **sem** índice pré-fixado.
- Os literais são `card_id` reais do catálogo, então a verificação de MCV sintética não se aplica. Isso **não** torna o lote representativo da cardinalidade processada.
- **Limites residuais:**
  - o lote é o **teto** (todas as Cards do Set), maior ou igual ao conjunto correlacionado efetivo;
  - o universo pode incluir Sets em que o consumidor nunca chegou a consultar `card_variant`.

## 6. Evidências e critérios objetivos

**Evidência comum a toda chamada (EV):**
- **EV1:** o texto submetido tem o md5 registrado acima.
- **EV2:** a resposta é um array JSON íntegro e não vazio, com as linhas de `QUERY PLAN` (ou o objeto `p9a_representativeness`). Registrar md5 e bytes.
- **EV3:** nenhum SQLSTATE de erro.
- **EV4:** nenhum nó de escrita ou trava: `ModifyTable`, `Insert on`, `Update on`, `Delete on`, `Merge on`, `LockRows`.

**Definições usadas nos critérios:**
- **L** (relações grandes) = {`catalog_variant_import_row`, `card_variant`}.
- **Acesso indexado** = `Index Scan`, `Index Only Scan` ou `Bitmap Heap Scan` sobre `Bitmap Index Scan`.
- A árvore do plano é lida pela indentação das linhas `->`.

### 6.1 P9A-01 e P9A-02 (P9a)

| Classe | Condição |
|---|---|
| **REGISTRADO** | EV1–EV4; inventário de nós de acesso por relação de L anexado; nenhuma bandeira |
| **REGISTRADO COM ADJUDICAÇÃO** | EV1–EV4, mas com pelo menos uma bandeira:<br>• **FLAG-NL:** `Nested Loop` em que um dos lados acessa relação de L e o lado interno chega à sua relação por `Seq Scan` (direto ou sob `Materialize`/`Memoize`), sem acesso indexado;<br>• **FLAG-SP:** `SubPlan` (correlacionado; `InitPlan` não conta) cuja subárvore faz `Seq Scan` em relação de L.<br>Nesse caso não se avança para A2 sem adjudicação do auditor e de Fabrício. Não é FAIL por si: forma não é tempo. |
| **FAIL** | EV3 ou EV4 violado |
| **INVÁLIDO** | EV1 ou EV2 violado (texto divergente, saída truncada ou JSON inválido): não é evidência; STOP sem retry |

- `Seq Scan` isolado sobre relação de L na raiz de um agregado sem predicado (os `count(*)` do `BASELINE-BUILDER`) é a forma **inerente** a uma contagem integral. Não é bandeira.
- Os índices usados **não** são pré-fixados como critério.
- **REGISTRADO não significa P9a cumprido nem A2 cumprido**: P9a só se completa quando as seções pesadas também tiverem evidência (§8), e A2 depende ainda de P9b/D-2.

### 6.2 P9A-03 — 6.1

P9A-03 é **diagnóstico de planejamento** com literal sintético, não prova representativa de desempenho. A exigência literal de 6.1 é preservada: só há PASS se o plano **demonstrar** `uq_card_variant_identity`.

| Classe | Condição (acesso a `card_variant` no plano) |
|---|---|
| **6.1 PASS** | EV1–EV4 e acesso indexado **via `uq_card_variant_identity`** com `Index Cond` contendo `card_id = …`. Exige também, em P9A-00: `literals_in_mcv = false` (conhecido, não UNKNOWN), nenhuma configuração comprometedora (§6.4) e estabilidade (a)/(b). |
| **6.1 NÃO DEMONSTRADO** | EV1–EV4, mas o acesso não é o do PASS:<br>• outro índice com `first_key = card_id` em P9A-00 (ex.: `ix_card_variant_card_id`, `uq_card_variant_card_order`);<br>• `Seq Scan` em `card_variant`;<br>• índice usado sem `Index Cond` em `card_id`.<br>Registrar o caminho e alimentar 6.2. **Não é FAIL automático**: com literal sintético, um `Seq Scan` pode refletir estimativa, estatística ou configuração, e exige adjudicação. Planos com `card_id` reais de catálogo só vêm de P9A-05, se autorizado, e ainda assim como evidência complementar. |
| **6.1 INCONCLUSIVO** | Plano registrado, mas sem classificação possível: `literals_in_mcv` UNKNOWN, configuração comprometedora, estatística indisponível para `card_variant` ou instabilidade entre (a) e (b) |
| **FAIL** | EV3 ou EV4 violado |
| **INVÁLIDO** | EV1 ou EV2 violado; ou `literals_in_mcv = true`, porque o literal colide com a MCV e deixa de ser representativo: não classificar, STOP sem retry |
| **STOP (divergência)** | P9A-00 mostra `uq_card_variant_identity` ausente, inválida ou com `first_key` ≠ `card_id`. Contradiz a 2209 e o D4 da Etapa 2: preservar evidência, não prosseguir |

### 6.3 P9A-04 — 6.2

O requisito 6.2 é uma **decisão**. A execução só pode produzir **evidência completa**, nunca a decisão.

| Classe | Condição |
|---|---|
| **6.2 EVIDÊNCIA — CENÁRIO PEQUENO** | EV1–EV4 em P9A-03 e P9A-04. P9A-00 lista, para cada índice de `card_variant`: `def`, `first_key`, `valid`/`ready`/`live`, `size_bytes` e `idx_scan`/`last_idx_scan` (com `stats_reset`). Os dois planos são classificados pelo caminho de acesso. **Vale só para N ≤ 3**; não sustenta, sozinha, conclusão sobre o lote real. |
| **6.2 EVIDÊNCIA — CENÁRIOS DE CATÁLOGO (complementar)** | A anterior **mais** P9A-05a e um P9A-05b por `card_set_id` distinto (rótulos p50/p95/máximo preservados), com EV1–EV4 e estabilidade (a)/(b). Exige autorização expressa no mandato LIVE. **Não** mede a cardinalidade efetivamente processada (`correlatedCardIds` ⊆ Cards do Set; job ≠ chamada ao consumidor) e **não** torna 6.2 conclusivo por si só. |
| **6.2 INCONCLUSIVO** | Configuração comprometedora (§6.4) ou instabilidade entre (a) e (b): planos registrados, sem classificação |
| **6.2 CUMPRIDO** | Só quando Fabrício registrar a decisão (manter, remover ou adiar) com referência a essa evidência. A decisão registra explicitamente os limites da evidência usada: cenário pequeno e, se houver, cenários de catálogo complementares, nenhum dos dois equivalente à cardinalidade efetivamente processada. A remoção é DDL: exige mandato próprio e não é permitida sob FREEZE. |
| **STOP (divergência)** | `ix_card_variant_card_id` ausente em P9A-00. O repositório o cria na Query 160 e nenhum artefato o remove, então haveria deriva não registrada: sinalizar antes de qualquer conclusão. |

Leitura condicional, que não é decisão:
- Se os planos usam `ix_card_variant_card_id`, 6.1 fica NÃO DEMONSTRADO enquanto o índice existir. O plano contrafactual, sem esse índice, não é observável no LIVE (limite 7 do §4).
- Se os planos usam `uq_card_variant_identity`, a evidência sugere redundância, mas a decisão continua sendo de Fabrício.

### 6.4 P9A-00 — representatividade

**Snapshot:** a saída integral de P9A-00 (a) e (b) é preservada e registrada, incluindo todo o `planner_settings`. Nenhum valor de configuração causa STOP por si.

**Estabilidade (obrigatória):** (a) e (b) precisam ter `planner_settings`, e, por relação de L, `reltuples`, `last_analyze` e `last_autoanalyze` iguais. Divergência ⇒ os planos da janela ficam INCONCLUSIVOS: não classificar, registrar e adjudicar.

**Configuração comprometedora** — só a que altera o próprio critério de interpretação de cada plano:

| Plano | Parâmetros que, se `off`, comprometem a interpretação | Efeito |
|---|---|---|
| P9A-03, P9A-04, P9A-05b | `enable_seqscan`, `enable_indexscan`, `enable_indexonlyscan`, `enable_bitmapscan` (definem o caminho de acesso julgado) | classe INCONCLUSIVO; plano registrado |
| P9A-01, P9A-02 (bandeiras FLAG-NL/FLAG-SP) | os quatro acima e `enable_nestloop`, `enable_hashjoin`, `enable_mergejoin`, `enable_material`, `enable_memoize` (definem a forma de junção julgada) | bandeira afetada: INCONCLUSIVO; o inventário de nós continua REGISTRADO |

Os demais parâmetros (custos, `work_mem`, `effective_cache_size`, `jit`, `geqo`, `plan_cache_mode` etc.) são contexto de interpretação: registrados e não avaliados como gate.

**Demais condições**
- `in_recovery = false` e `current_user = postgres`; senão STOP (canal diferente do das Etapas 1–3).
- `transaction_read_only` registrado.
- **Estatística por relação de L:** `reltuples ≥ 0` **e** `last_analyze` ou `last_autoanalyze` não nulo. Se não, a estatística é UNKNOWN para essa relação: os planos que a julgam ficam INCONCLUSIVOS (P9A-03/04) ou REGISTRADO COM ADJUDICAÇÃO (P9A-01/02).
- **`card_id_stats`:**
  - `stats_state = MCV_PRESENT` e `literals_in_mcv = false`: literal conhecido fora da MCV;
  - `literals_in_mcv = true`: INVÁLIDO para P9A-03/04 (§6.2);
  - `stats_state` `MCV_NULL` ou `NO_STATS_ROW`: **UNKNOWN**, nunca "fora da MCV", e P9A-03/04 ficam INCONCLUSIVOS.

## 7. Riscos de execução no LIVE e sequência mínima

| # | Risco | Classe | Mitigação |
|---|---|---|---|
| R1 | O planejamento toma `AccessShareLock` em todas as relações citadas. Com `lock_timeout = '0'`, uma DDL concorrente faria a chamada esperar até o `statement_timeout` (120 s). | Baixo (FREEZE: nenhuma DDL legítima) | L3 antes. Lock no escopo ⇒ não iniciar. `57014` ⇒ STOP sem retry. |
| R2 | `EXPLAIN` sem `ANALYZE` não executa o executor. O planner pode avaliar funções imutáveis ou estáveis com argumentos constantes (dobra de constantes). | Muito baixo | E00 e E99 já foram planejados **e executados** no LIVE (Etapas 1–3) sem erro. P9A-03/04/05b só usam literais `uuid`. |
| R3 | Saída grande (o plano do E00 tem muitos `InitPlan`/`SubPlan`) truncada pelo canal. | Médio | EV2: truncamento ⇒ INVÁLIDO, nunca PASS. Registrar md5 e contagem de linhas. |
| R4 | Nenhuma escrita, `SET`, `ANALYZE`, `TEMP`, `PREPARE` nem `set_config`. | — | Proibidos. O texto proposto não contém nenhum deles. |
| R5 | Plano datado: muda após novo `ANALYZE`. | Baixo | P9A-00 (a)/(b) fixa o estado das estatísticas da janela. |
| R6 | Mudança de canal ou papel (RLS passaria a valer). | Baixo | P9A-00 registra `current_user`; divergência de `postgres` ⇒ STOP. |
| R7 | P9A-02 lido como prova de resíduo. | Documental | Declarado no §4: é só plano. |

**Sequência mínima proposta, exclusivamente de leitura** (7 chamadas, ou até 11 com S6b; uma por statement; sem retry; qualquer STOP encerra):

1. **S0 (local):** HEAD `91de54ef`; árvore limpa; blobs do §4; md5 locais dos textos compostos (§5.2, §5.3).
2. **S1:** L3. Precisa estar limpa.
3. **S2:** P9A-00 (a).
4. **S3:** P9A-01 (E00).
5. **S4:** P9A-02 (E99).
6. **S5:** P9A-03 (6.1).
7. **S6:** P9A-04 (6.2).
8. **S6b (condicional):** só se o mandato LIVE autorizar expressamente a leitura de dado de negócio: P9A-05a e um P9A-05b por `card_set_id` distinto, no máximo 3 (§5.6). Sem autorização, S6b não ocorre e 6.2 fica no cenário pequeno. Com ela, o resultado é evidência complementar, não conclusiva.
9. **S7:** P9A-00 (b), depois de S6/S6b.

## 8. Blockers e itens fora do escopo

| # | Item | Efeito |
|---|---|---|
| BL-1 | O mandato fala em "apenas `EXPLAIN (COSTS OFF)`", mas L3 e P9A-00 são `SELECT` de catálogo, sem `EXPLAIN`. Eles são necessários para o item 3 (índices efetivos) e para a representatividade. | **Exige autorização explícita** no mandato de execução. Sem eles: 6.1/6.2 não distinguem NÃO DEMONSTRADO de STOP, e §6.4 não é avaliável. P9A-05 lê dado de negócio (`card`, `catalog_variant_import_job`) e também exige autorização expressa; sem ela, 6.2 fica limitado ao cenário pequeno. |
| BL-2 | Seções B, M, 5.2/5.3/5.7 sem artefato de harness. | P9a **não pode ser declarado completo** para a 2830. Estas consultas cobrem só os envelopes vigentes. |
| BL-3 | P9b sem ambiente isolado; D-2 (AD-2) **PENDENTE**; D-1/P14 **PENDENTE**. | **A2 não é cumprido** por nenhuma saída desta readiness. |
| BL-4 | 6.1 literal ("usa `uq_card_variant_identity`") pode ser indemonstrável enquanto existir índice mais estreito em `card_id`. | Pode exigir a decisão 6.2 ou o ambiente isolado (D-1). Não é presumido nem contornado por alteração de sessão ou DDL. |

**Candidatos avaliados e não propostos** (correspondência não demonstrável ou fora do requisito):
- statements internos do E01/E02: exigiriam texto novo sem blob e não são pesados;
- consultas internas da 2218 (matching quádruplo, `MAX(variant_order)`): pertencem à readiness da 2218, não à 2830;
- verificações de FK em `card_variant.card_id`: não são observáveis por `EXPLAIN`;
- P9A-04 com N real por Card Set: exigiria leitura de dados para fixar N.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P9A-READINESS-01`, baseline `91de54ef`), só documental, sem SQL executado e sem acesso ao LIVE.**<br>• P9a aplicável a E00 e E99 (um `SELECT` cada), não aplicável a E01/E02 (`DO`, sem consulta pesada); B/M/5.x sem artefato;<br>• consultas P9A-01/02 (prefixo `EXPLAIN (COSTS OFF)` + blob verbatim), P9A-03 (6.1), P9A-04 (6.2) e P9A-00 (representatividade e índices efetivos);<br>• critérios sem pré-fixar índice;<br>• riscos R1–R7; sequência mínima de 7 chamadas, só leitura;<br>• blockers BL-1 a BL-4.<br>Nenhum requisito (P9a, P9b, A2, 6.1, 6.2) declarado cumprido. D-2 e D-1/P14 PENDENTES. FREEZE ATIVO. |
| 1.1 | **Correção documental (2026-09-27, `BATCH12-2830-P9A-READINESS-CORRECTION-01`), sem SQL executado e sem acesso ao LIVE.** Quatro pontos da auditoria independente:<br>• §6.4: removido o STOP por qualquer `enable_* = off`; snapshot integral preservado, estabilidade (a)/(b) obrigatória e só a configuração que compromete o critério de cada plano leva a INCONCLUSIVO;<br>• P9A-00: `card_id_stats` tri-state (`MCV_PRESENT`/`MCV_NULL`/`NO_STATS_ROW`), estatística ou MCV indisponível = UNKNOWN, nunca prova de ausência (md5 `5d66fdc1…` → `da737699…`);<br>• 6.1: P9A-03 é diagnóstico de planejamento; `Seq Scan` passa a NÃO DEMONSTRADO com adjudicação, não FAIL automático; PASS continua exigindo `uq_card_variant_identity`;<br>• 6.2: N = 3 vale só para o cenário pequeno; novo P9A-05 (lotes p50/p95/máximo do consumidor real) definido, **não coletado**, dependente de autorização expressa (S6b condicional).<br>P9A-01/02, contratos canônicos e resultados das Etapas 1–3 inalterados. P9a, P9b, A2, 6.1 e 6.2 pendentes. FREEZE ATIVO. |
| 1.2 | **Correção documental (2026-09-27, `BATCH12-2830-P9A-READINESS-CORRECTION-02`), só da classificação do P9A-05, sem SQL executado e sem acesso ao LIVE.**<br>• P9A-05 reclassificado como **evidência complementar de cenários de catálogo** p50/p95/máximo (teto potencial: todas as Cards do Set), não medição da cardinalidade efetivamente processada (`correlatedCardIds` ⊆ Cards do Set); 6.2 não é conclusivo só com ela (§5.6, matriz, §4, §6.2, §6.3, §7);<br>• limite explícito: job existente ≠ chamada a `listExistingCardVariantsMap`;<br>• P9A-05a deduplica por `card_set_id` no SQL, preservando todos os rótulos; P9A-05b é um plano por Set distinto, e repetição ⇒ STOP (md5 `446bf32a…` → `9836e429…`, 1.857 B);<br>• P9A-05 segue proposta condicional, sem autorização LIVE.<br>P9A-00/01/02/03/04 inalterados. P9a, P9b, A2, 6.1 e 6.2 pendentes. FREEZE ATIVO. |
