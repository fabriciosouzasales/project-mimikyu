# Batches de execução LIVE — Edition Context

**`EDITION-CONTEXT-AXIS-ROLLOUT-EXECUTION-READINESS-01`.** Nada executado.
Autoridade de ordem: `ROLLOUT-ORDER.md`. Este documento é a **projeção
operacional em lotes**, com STOP entre cada um.

Regra única: **um batch por vez. STOP. Postcheck read-only. Só então o
próximo.** Se qualquer postcheck falhar, o rollout para — não se "tenta o
próximo para ver".

---

## PRECHECK LIVE — antes do primeiro write

Read-only. Roda **imediatamente antes do Batch 1**. Se qualquer linha divergir
do esperado, **STOP**: o baseline mudou desde esta auditoria.

```sql
-- P1  As 5 tabelas de Edition Context ainda NÃO existem.  Esperado: 0
SELECT count(*) AS ec_tables
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
   AND c.relname LIKE 'card_edition_context%';

-- P2  card_variant AINDA NÃO tem a coluna do eixo 3.  Esperado: 0
SELECT count(*) AS ec_column
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'card_variant'
   AND column_name = 'edition_context_profile_id';

-- P3  Identidade ATUAL de card_variant.
--
--     CORRIGIDO (PREFLIGHT-CORRECTION-01). A versão anterior consultava
--     pg_constraint — e estava ERRADA: as duas identidades legadas são
--     ÍNDICES ÚNICOS PARCIAIS, não constraints. Elas NÃO aparecem em
--     pg_constraint. A query antiga devolvia card_variant_pkey,
--     uq_card_variant_card_order e uq_card_variant_id_card, que não têm
--     relação nenhuma com este gate — um verde falso.
--
--     P3a — os DOIS índices legados existem.  Esperado: EXATAMENTE 2 linhas,
--           ambas com indisunique = true e indpred NOT NULL (parciais).
SELECT c.relname                                   AS indice,
       i.indisunique                               AS unico,
       (i.indpred IS NOT NULL)                      AS parcial,
       i.indisvalid                                AS valido,
       pg_get_expr(i.indpred, i.indrelid)          AS predicado
  FROM pg_index i
  JOIN pg_class  c ON c.oid = i.indexrelid
 WHERE i.indrelid = 'public.card_variant'::regclass
   AND c.relname IN ('uq_card_variant_card_type_no_printing',
                     'uq_card_variant_card_type_printing')
 ORDER BY c.relname;

--     P3b — a identidade NOVA ainda não existe, em NENHUMA das duas formas.
--           Esperado: como_indice = 0  E  como_constraint = 0.
--           Separado de propósito: `uq_card_variant_identity` nasce como
--           ÍNDICE (2209 passo 1) e só depois vira CONSTRAINT (passo 2).
--           Provar as duas ausências elimina a confusão índice × constraint.
SELECT (SELECT count(*) FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
         WHERE i.indrelid = 'public.card_variant'::regclass
           AND c.relname = 'uq_card_variant_identity')          AS como_indice,
       (SELECT count(*) FROM pg_constraint
         WHERE conrelid = 'public.card_variant'::regclass
           AND conname  = 'uq_card_variant_identity')           AS como_constraint;

-- P4  Writer atual: EXATAMENTE 1 assinatura, de 6 args.  Esperado: 1 linha, pronargs=6
SELECT p.pronargs, p.prosecdef, p.proconfig
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

-- P5  Confirm atual NÃO passa o eixo 3.  Esperado: false
SELECT p.prosrc LIKE '%edition_context_profile_id%' AS confirm_ja_no_eixo3
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';

-- P6  Nenhuma execução PARCIAL do pacote: zero funções do eixo 3.  Esperado: 0
--
--     ATUALIZADO (BATCH1-RUNTIME-CORRECTION-02). A lista anterior citava
--     `seal_edition_context_signature`, que era o selo POR EVENTO NA N:N da
--     2206 v1.0 — função que a v2.0 NÃO cria mais. Um P6 que procura um nome
--     inexistente sempre devolve 0 para aquela entrada: deixa de detectar
--     execução parcial em vez de detectá-la.
--
--     REVISADO (MAPPING-LIFECYCLE-CORRECTION-02): a 2207 v4.0 ganhou os
--     GUARDS A e B do cabeçalho, então são **11** nomes — 4 da 2206 v2.0 +
--     5 da 2207 v4.0 + 2 de 2210/2211. Uma lista curta aqui volta a
--     sub-detectar execução parcial.
SELECT count(*) AS ec_functions
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'internal'
   AND p.proname IN (
        -- 2206 v2.0 — guards do PROFILE (4)
        'seal_edition_context_composition',
        'guard_edition_context_composition_immutable',
        'enforce_edition_context_signature_write',
        'guard_edition_context_trait_active',
        -- 2207 v4.0 — guards do EXTERNAL MAPPING (5)
        'normalize_edition_context_external_mapping',
        'enforce_edition_context_mapping_header',
        'seal_edition_context_external_mapping',
        'guard_edition_context_mapping_composition_immutable',
        'enforce_edition_context_mapping_signature_write',
        -- 2210 / 2211 (2)
        'resolve_variant_row_axes',
        'axis_identity_token');

-- P7  FREEZE: universo operacional de staging — BASELINE REAL.
--
--     CORRIGIDO (PREFLIGHT-CORRECTION-01). A versão anterior dizia
--     "esperado hoje: 0". Está ERRADO. Medição read-only do LIVE:
--
--         job.status          = STAGED
--         decision_status     = PENDING
--         validation_status   = NEEDS_REVIEW
--         persistence_status  = PENDING
--         n                   = 1.642
--
--     O FREEZE tem escopo REAL de 1.642 rows — são exatamente as 1.642 que
--     a partição semântica classificou e que a 2212 vai resolver. Tratar
--     isso como "universo vazio" era a premissa que mais poderia esconder
--     uma janela durante os Batches 5-9.
--
--     Esperado: UMA única linha — STAGED / PENDING / NEEDS_REVIEW / 1642.
--     Qualquer outro estado presente, ou n <> 1642 → **STOP antes de
--     qualquer write**. NÃO adaptar a expectativa ao que aparecer.
SELECT j.status            AS job_status,
       r.decision_status,
       r.validation_status,
       r.persistence_status,
       count(*)            AS n
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
 GROUP BY 1,2,3,4
 ORDER BY 1,2,3,4;

-- P8  Ledger: NENHUMA das 23 migrations deste rollout já registrada.
--
--     CORRIGIDO (PREFLIGHT-CORRECTION-01). A versão anterior usava três
--     padrões LIKE que NÃO cobriam o pacote: ficavam de fora, entre outras,
--     2217/2218/2219/2220/2221/2222/2223 e as três seeds. Retornar 0 não
--     provava nada — provava só que aqueles padrões não casaram.
--
--     Agora o manifesto é EXPLÍCITO e a prova é dupla: o próprio manifesto
--     precisa ter 23 entradas, e nenhuma pode estar no ledger.
--     Os nomes são os basenames dos arquivos, sem `.sql` — a convenção
--     `NNNN_nome` do projeto (ver nota histórica na migration 2200, que
--     registra a ÚNICA divergência conhecida dessa convenção).
--     BASELINE REVISADO (BATCH1-RUNTIME-CORRECTION-01). A 2203 FOI EXECUTADA
--     e ESTÁ no ledger. O gate deixa de ser "ja_registradas = 0" e passa a ser
--     um conjunto EXATO e nominal: a única migration deste rollout que pode
--     aparecer no ledger é a 2203. Um contador solto ("<= 1") aceitaria a
--     registrada errada; o teste abaixo compara o CONJUNTO.
--     Esperado: manifesto = 23 · ja_registradas = 1 · registradas_inesperadas = 0.
WITH manifesto(name) AS (VALUES
    ('2203_create_card_edition_context_trait_table'),
    ('2204_create_card_edition_context_profile_table'),
    ('2205_create_card_edition_context_profile_trait_table'),
    ('2206_create_edition_context_composition_guards'),
    ('2207_create_card_edition_context_external_mapping'),
    ('2208_add_edition_context_to_card_variant'),
    ('2209_reconcile_card_variant_identity_unique4'),
    ('2210_reconcile_staging_identity_edition_context'),
    ('2211_create_resolve_variant_row_axes_contract'),
    ('2212_backfill_staging_edition_context_key'),
    ('2214_promote_valid_requires_edition_context_key'),
    ('2215_drop_legacy_card_variant_identity_indexes'),
    ('2216_drop_legacy_staging_identity_indexes'),
    ('2217_redefine_write_card_variant_v3'),
    ('2218_redefine_admin_confirm_catalog_variant_import'),
    ('2219_redefine_apply_variant_type_mapping'),
    ('2220_redefine_variant_type_mapping_read_contract'),
    ('2221_redefine_admin_resolve_printing_mapping'),
    ('2222_redefine_create_card_printing_profile_with_backfill'),
    ('2223_contract_write_card_variant_drop_legacy_arity'),
    ('2230_seed_edition_context_traits'),
    ('2231_seed_edition_context_profiles'),
    ('2232_seed_edition_context_external_mappings'))
SELECT (SELECT count(*) FROM manifesto)                       AS manifesto,      -- 23
       (SELECT count(*) FROM supabase_migrations.schema_migrations s
         JOIN manifesto m ON m.name = s.name)                 AS ja_registradas, -- 1
       -- A 2203 é a ÚNICA registrada admissível. Qualquer outra do pacote no
       -- ledger significa que uma execução não documentada aconteceu -> STOP.
       (SELECT count(*) FROM supabase_migrations.schema_migrations s
         JOIN manifesto m ON m.name = s.name
        WHERE m.name <> '2203_create_card_edition_context_trait_table')
                                             AS registradas_inesperadas,         -- 0
       -- Confirmação positiva: a 2203 está mesmo lá (se sumiu, o baseline
       -- não é o que este documento descreve).
       (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE name = '2203_create_card_edition_context_trait_table')
                                                              AS r2203,          -- 1
       -- Rede de segurança: qualquer registro do pacote sob nome divergente
       -- da convenção (o risco que a 2200 documentou).
       -- O `NOT IN manifesto` é OBRIGATÓRIO desde BATCH1-RUNTIME-CORRECTION-01:
       -- sem ele, a 2203 — legitimamente registrada — casaria em
       -- `edition_context` e produziria um STOP falso.
       (SELECT count(*) FROM supabase_migrations.schema_migrations s
         WHERE s.name ~ '(edition_context|card_variant_identity|write_card_variant_v3
                        |resolve_variant_row_axes|apply_variant_type_mapping
                        |variant_type_mapping_read_contract
                        |admin_resolve_printing_mapping
                        |create_card_printing_profile_with_backfill)'
           AND s.name NOT IN (SELECT m.name FROM manifesto m))
                                                              AS por_padrao;     -- 0
```

**Condição para iniciar — todas obrigatórias:**

| Gate | Esperado |
|---|---|
| P1 | `0` |
| P2 | `0` |
| **P3a** | **2 linhas** · `unico=true` · `parcial=true` · `valido=true` |
| **P3b** | `como_indice=0` **e** `como_constraint=0` |
| P4 | 1 linha, `pronargs=6` |
| P5 | `false` |
| P6 | `0` |
| **P7** | **1 linha: STAGED / PENDING / NEEDS_REVIEW / PENDING / 1642** |
| **P8** | `manifesto=23` · `ja_registradas=1` · `registradas_inesperadas=0` · `r2203=1` · `por_padrao=0` |

Qualquer divergência → **STOP**. O baseline mudou desde esta auditoria.

> **P9 — pré-condição de RETOMADA (`BATCH1-RUNTIME-CORRECTION-01`).** A 1ª
> tentativa do Batch 1 deixou a `2203` LIVE e abortou na `2204`. Antes de
> retomar, provar que o resíduo é exatamente esse — uma tabela, não duas:
>
> ```sql
> SELECT count(*) FILTER (WHERE c.relname = 'card_edition_context_trait')   AS t2203, -- 1
>        count(*) FILTER (WHERE c.relname = 'card_edition_context_profile') AS t2204, -- 0
>        count(*)                                                           AS total  -- 1
>   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
>  WHERE n.nspname = 'public' AND c.relkind = 'r'
>    AND c.relname LIKE 'card_edition_context%';
> ```
>
> **Esperado: `t2203=1` · `t2204=0` · `total=1`.** `t2204 = 1` significaria que
> a `2204` criou a tabela antes de abortar — contradiz a premissa de zero
> resíduo e exige investigação antes de qualquer write. `total > 1` idem.

---

## Batch 1 — FUNDAÇÃO (aditivo puro, reversível por `DROP`)

> ### ⚠️ INCIDENTE DE RUNTIME — 1ª tentativa interrompida (`BATCH1-RUNTIME-CORRECTION-01`)
>
> | Artefato | Estado real |
> |---|---|
> | `2203` | **EXECUTADA / LIVE** · ledger registrado · `card_edition_context_trait` existe · RLS/policy/ACL aprovados |
> | `2204` | **1ª tentativa ABORTADA** · `SQLSTATE 0A000` · **sem tabela criada, sem ledger** = zero resíduo · corrigida para **v1.1** |
> | `2205` · `2206` · `2207` | **PENDING** — nunca executadas. `2207` corrigida **preventivamente** para v1.1 (mesmo defeito) |
>
> **Erro:** `cannot use subquery in check constraint`, em
> `ck_cecp_signature_shape`, que tentava provar canonicalização do array dentro
> do próprio CHECK. Corrigido em `2204` v1.1 e `2207` v1.1 por dois CHECKs
> escalares em paridade literal com as Queries **2166** e **2172**, LIVE.
>
> **RETOMADA:** `2204` → `2205` → `2206` → `2207`.
> **NÃO reaplicar a `2203`** — ela está LIVE e no ledger; uma segunda tentativa
> abortaria por `42P07 duplicate_table` e sujaria o ledger sem necessidade.

| Ordem | Artefato | Retomada |
|---|---|---|
| — | `2203` · trait | ✅ **JÁ LIVE — PULAR** |
| 1 | `2204` · profile **v1.1** | ▶ ponto de partida |
| 2 | `2205` · N:N | pending |
| 3 | `2206` · guards de composição | pending |
| 4 | `2207` · external mapping (+N:N) **v1.1** | pending |

**Expected ao fim da retomada:** 5 tabelas criadas, vazias (a de `2203` já
existe desde a 1ª tentativa); **9 trigger functions** e **9 triggers** — dos
quais **2 são CONSTRAINT TRIGGER deferidos** (`trg_cecp_seal`,
`trg_cecem_seal`); RLS e policy em todas as 5. O postcheck abaixo vale para o
**estado final do Batch 1 inteiro** — ele não distingue a tabela já criada das
quatro novas, e é exatamente isso que se quer verificar.

> **Contagem revisada em `MAPPING-LIFECYCLE-CORRECTION-02`** (era "3/2" na
> v1.0, "7/7" na CORRECTION-02). A 2206 v2.0 tem 4 guards; a 2207 **v4.0**
> tem **5** — os 3 de composição/selo mais GUARD A (normalização) e GUARD B
> (identidade imutável + lifecycle de `is_active`). 4 + 5 = 9.

**Postcheck (read-only):**
```sql
SELECT count(*) FILTER (WHERE c.relkind='r')            AS tabelas,       -- 5
       count(*) FILTER (WHERE c.relrowsecurity)         AS com_rls        -- 5
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname LIKE 'card_edition_context%';

SELECT count(*) AS policies FROM pg_policies             -- 5
 WHERE schemaname='public' AND tablename LIKE 'card_edition_context%'
   AND policyname='catalog_admin_select';

SELECT count(*) AS grants_indevidos                      -- 0
  FROM information_schema.role_table_grants
 WHERE table_schema='public' AND table_name LIKE 'card_edition_context%'
   AND (grantee='anon' OR (grantee IN ('authenticated','service_role')
                           AND privilege_type <> 'SELECT'));
```
**Prosseguir se:** tabelas=5 · com_rls=5 · policies=5 · grants_indevidos=0.

---

## Batch 2 — VOCABULÁRIO (seeds; só após Batch 1)

| Ordem | Artefato |
|---|---|
| 1 | `2230` · 115 traits |
| 2 | `2231` · 144 profiles + 196 links |
| 3 | `2232` · 122 mappings |

Os gates internos de cada seed já falham alto (`T1`–`T4`, `P1`–`P7`, `M3`, `H2`,
`C1`). Este postcheck é a confirmação externa.

**Postcheck:**
```sql
SELECT (SELECT count(*) FROM public.card_edition_context_trait)                  AS traits,   -- 115
       (SELECT count(*) FROM public.card_edition_context_profile)                AS profiles, -- 144
       (SELECT count(*) FROM public.card_edition_context_profile_trait)          AS links,    -- 196
       (SELECT count(*) FROM public.card_edition_context_external_mapping)       AS mappings, -- 122
       (SELECT count(*) FROM public.card_edition_context_profile
         WHERE traits_signature IS NULL)                            AS profiles_nao_selados, -- 0
       -- NOVO (BATCH1-RUNTIME-CORRECTION-02). Validar só o profile deixava o
       -- mapping fora: é ELE que a Edge lê, e um NULL aqui vira
       -- NEEDS_REVIEW_INVALID_EC_MAPPING em massa.
       (SELECT count(*) FROM public.card_edition_context_external_mapping
         WHERE traits_signature IS NULL)                            AS mappings_nao_selados, -- 0
       -- EQUIVALÊNCIA SQL x EDGE: selo idêntico à N:N nos 122.
       (SELECT count(*) FROM public.card_edition_context_external_mapping m
         WHERE m.traits_signature IS DISTINCT FROM ARRAY(
                 SELECT t.trait_id FROM public.card_edition_context_external_mapping_trait t
                  WHERE t.mapping_id = m.id ORDER BY t.trait_id))    AS mappings_divergentes; -- 0
```
**Prosseguir se:** 115 / 144 / 196 / 122 / **0 / 0 / 0**.

---

## Batch 3 — FREEZE + BASELINE

Ação **operacional**, não SQL: suspender a importação de Variants e capturar o
baseline com o sistema parado.

**O FREEZE tem escopo real: 1.642 rows** (`STAGED` / `PENDING` /
`NEEDS_REVIEW` / `PENDING`) — não é formalidade. Sem ele, os Batches 5–9 têm
janela de verdade.

**B3.1 — reexecutar P7.** Esperado: a mesma linha única com **1642**.
Divergência → **STOP**.

**B3.2 — capturar a baseline histórica de `CANCELLED`, ANTES da `2212`.**

> **CORRIGIDO (`PREFLIGHT-CORRECTION-01`).** A versão anterior do postcheck do
> Batch 5 comentava *"os 415 CANCELLED"* mas a query contava **todos** os
> `CANCELLED` sem a chave — que no LIVE são **847**. Comentário e query
> mediam coisas diferentes. São **dois** predicados distintos, e agora ambos
> são capturados e comparados separadamente.

```sql
-- Dois predicados, explicitamente separados. Registrar os DOIS números.
SELECT
  count(*)                                                   AS cancelled_sem_chave_total,          -- LIVE: 847
  count(*) FILTER (WHERE r.validation_status = 'VALID'
                     AND r.persistence_status = 'PENDING')    AS cancelled_valid_pending_sem_chave   -- LIVE: 415
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status = 'CANCELLED'
   AND NOT (r.normalized_data ? 'edition_context_profile_id');
```

**Prosseguir se:** FREEZE confirmado por Fabrício · P7 = 1642 ·
`cancelled_sem_chave_total` e `cancelled_valid_pending_sem_chave` **registrados
por escrito** (esperado hoje: **847** e **415**). Esses dois números viram a
referência do postcheck do Batch 5.

---

## Batch 4 — COLUNA (aditivo, inerte)

| Ordem | Artefato |
|---|---|
| 1 | `2208` |

**Postcheck:**
```sql
SELECT is_nullable, data_type FROM information_schema.columns     -- YES, uuid
 WHERE table_schema='public' AND table_name='card_variant'
   AND column_name='edition_context_profile_id';

SELECT count(*) AS nao_nulas FROM public.card_variant             -- 0
 WHERE edition_context_profile_id IS NOT NULL;
```
**Prosseguir se:** `YES`/`uuid` · nao_nulas=0.

---

## Batch 5 — STAGING: resolução + provas + guard

| Ordem | Artefato | Natureza |
|---|---|---|
| 1 | `2212` | **write** — resolução operacional |
| 2 | `2832` | prova, `ROLLBACK` |
| 3 | `2833` | prova, `ROLLBACK` |
| 4 | `2214` | **write** — guard de transição |

`2832`/`2833` rodam **entre** o backfill e o guard, de propósito: provam o
predicado contra as combinações reais **antes** de ele virar obrigatório.

**Postcheck:**
```sql
-- (a) Nenhuma row OPERACIONAL VALID sem a chave.  Esperado: 0
SELECT count(*) AS operacional_sem_chave
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
   AND r.persistence_status='PENDING' AND r.validation_status='VALID'
   AND NOT (r.normalized_data ? 'edition_context_profile_id');

-- (b) Histórico terminal INTOCADO — OS MESMOS DOIS PREDICADOS do Batch 3,
--     comparados um a um contra os números capturados lá.
SELECT
  count(*)                                                   AS cancelled_sem_chave_total,         -- deve bater com B3.2 (847)
  count(*) FILTER (WHERE r.validation_status = 'VALID'
                     AND r.persistence_status = 'PENDING')    AS cancelled_valid_pending_sem_chave  -- deve bater com B3.2 (415)
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status = 'CANCELLED'
   AND NOT (r.normalized_data ? 'edition_context_profile_id');
```

**Prosseguir se:**

| Gate | Esperado |
|---|---|
| `operacional_sem_chave` | `0` |
| `2832` | 14/14 |
| `2833` | 11/11 |
| `cancelled_sem_chave_total` | **847 → 847** (idêntico a B3.2) |
| `cancelled_valid_pending_sem_chave` | **415 → 415** (idêntico a B3.2) |

Os dois números de `CANCELLED` são comparados **separadamente**. Qualquer um
que mude prova que a `2212` vazou para o histórico terminal — **STOP**.

---

## Batch 6 — IDENTIDADE DE STAGING + ROUTING

| Ordem | Artefato |
|---|---|
| 1 | `2210` · `axis_identity_token` + `uq_cvir_row_identity` + guard permissivo |
| 2 | `2211` · `resolve_variant_row_axes()` — contrato terminal |

**Postcheck:**
```sql
SELECT count(*) AS idx FROM pg_class                       -- 1
 WHERE relname='uq_cvir_row_identity';

SELECT p.proname, p.prosecdef, p.proconfig                 -- resolve: secdef=t, search_path
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='internal'
   AND p.proname IN ('axis_identity_token','resolve_variant_row_axes');

SELECT count(*) AS grant_indevido                          -- 0
  FROM information_schema.role_routine_grants
 WHERE routine_schema='internal' AND routine_name='resolve_variant_row_axes'
   AND grantee IN ('anon','authenticated','PUBLIC');
```
**Prosseguir se:** idx=1 · as 2 funções presentes · `resolve_variant_row_axes`
com `prosecdef=true` e `search_path` · grant_indevido=0.

---

## Batch 7 — CONSUMIDORES B + VETORES

| Ordem | Artefato |
|---|---|
| 1 | `2219` · `apply_variant_type_mapping` |
| 2 | `2220` · read contract |
| 3 | `2221` · `admin_resolve_printing_mapping` |
| 4 | `2222` · `create_card_printing_profile_with_backfill` |
| 5 | `2834` · runner dos vetores (read-only, `ROLLBACK`) |

Cada um dos quatro traz postcheck fail-loud próprio (sobrecarga = 1).

**Postcheck:**
```sql
-- Zero sobrecarga em qualquer um dos quatro contratos redefinidos.
SELECT n.nspname, p.proname, count(*) AS n
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.proname IN ('apply_variant_type_mapping',
                     'admin_resolve_catalog_variant_import_printing_mapping',
                     'create_card_printing_profile_with_backfill',
                     'admin_create_card_printing_profile_with_backfill')
 GROUP BY 1,2 HAVING count(*) <> 1;     -- esperado: ZERO linhas
```
**Prosseguir se:** zero linhas · `2834` com todos os vetores PASS.

---

## Batch 8 — EDGE

Deploy da `import-card-variants` com o patch do eixo 3 + suíte Deno.
Só aqui: antes, as tabelas que o preload lê não existiam.

**Postcheck:** suíte Deno verde + `2834` reexecutado — **os dois lados contra o
mesmo `edition-context-axis-vectors.json`**.

**Prosseguir se:** DB e Edge concordam vetor a vetor.

---

## Batch 9 — WRITER: EXPAND → SWITCH → CONTRACT

**Três artefatos, três STOPs.** Não colapsar em uma chamada.

| Ordem | Artefato | STOP obrigatório depois |
|---|---|---|
| 1 | `2217` EXPAND | **sim** |
| 2 | `2218` SWITCH | **sim** |
| 3 | `2223` CONTRACT | **sim** |

**Postcheck após `2217`:** 2 assinaturas (6 e 7 args); confirm ainda chama a de 6.
**Postcheck após `2218`:** confirm chama a de 7; as 2 assinaturas seguem vivas.
**Postcheck após `2223`:** 1 assinatura, 7 args.

```sql
SELECT p.pronargs, p.pronargdefaults, p.prosecdef
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='internal' AND p.proname='write_card_variant'
 ORDER BY p.pronargs;

SELECT p.prosrc LIKE '%edition_context_profile_id%' AS confirm_no_eixo3
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import';
```
**Prosseguir se:** cada postcheck bate exatamente com o estado esperado da
sua etapa. Em nenhum instante existe caller apontando para assinatura ausente.

---

## Batch 10 — IDENTIDADE NOVA (liberada pelo T1)

| Ordem | Artefato |
|---|---|
| 1 | `2209` |

`CREATE UNIQUE INDEX` e `ADD CONSTRAINT … USING INDEX` são atômicos entre si.

**Postcheck:**
```sql
SELECT c.conname, c.contype, i.indnullsnotdistinct, i.indnatts, i.indisvalid
  FROM pg_constraint c JOIN pg_index i ON i.indexrelid = c.conindid
 WHERE c.conrelid='public.card_variant'::regclass
   AND c.conname='uq_card_variant_identity';
```
**Prosseguir se:** `contype='u'` · `indnullsnotdistinct=true` · `indnatts=4` ·
`indisvalid=true`. **As duas antigas ainda existem** — é o esperado.

---

## Batch 11 — RETIRADA DAS IDENTIDADES ANTIGAS

| Ordem | Artefato |
|---|---|
| 1 | `2215` · `DROP` das 2 antigas de `card_variant` |
| 2 | `2216` · `DROP` das 2 antigas de staging |

Só depois do Batch 10: `2215` recusa rodar se a nova não for constraint válida.

**Postcheck:**
```sql
SELECT conname FROM pg_constraint                 -- só uq_card_variant_identity
 WHERE conrelid='public.card_variant'::regclass AND contype='u';

SELECT count(*) AS antigos_staging FROM pg_class  -- 0
 WHERE relname IN ('uq_cvir_job_card_type_no_printing',
                   'uq_cvir_job_card_type_printing');
```
**Prosseguir se:** só a nova em `card_variant` · antigos_staging=0.

---

## Batch 12 — HARNESS + UNFREEZE

| Ordem | Item |
|---|---|
| 1 | `2830` — harness da fundação (**144** automáticos, read-only) |
| 2 | **UNFREEZE** |

> **"READ MODELS C" REMOVIDO (`PREFLIGHT-CORRECTION-01`).** A etapa não tinha
> artefato, arquivo nem ação — era uma linha sem referente. O
> `READ-MODELS-AUDIT.md` já a torna desnecessária, com prova negativa:
>
> > *"a conclusão desta auditoria é que **nenhum read model de Collections
> > precisa mudar**"* · *"**Veredito: nenhum é classe A. Nenhum é alterado
> > nesta rodada.**"*
>
> Os dois consumidores classificados **B** (`web/lib/catalogo/queries.ts` e
> `revisao-importacao-variantes-table.tsx`) são exatamente o frontend já
> **`DEFERRED UNTIL AFTER 2213`** pelo `FRONTEND-DISPLAY-CONTRACT.md`. Nenhum
> deploy de leitura é necessário antes da `2213`, e **nenhum código novo foi
> criado para justificar a linha** — ela simplesmente não existia.

O UNFREEZE é **o último passo**, e só depois de `2830` verde: o write path novo
precisa estar íntegro antes de voltar a receber importação. Com o UNFREEZE, as
1.642 rows congeladas no Batch 3 voltam a poder ser processadas — agora pelo
routing do eixo 3.

**Prosseguir se:** `2830` **144/144**.

---

## Estado final

```
EDITION CONTEXT LIVE / WRITE PATH ESTÁVEL
→ READY FOR 2213
```

Fora deste rollout, como dívida rotulada: `2831`→`2213` (285
`READY_UNCONDITIONED`) · 80 `READY_PRICING_CONDITIONED` (bloqueados por
Pricing) · 12 composições de B (`DEFERRED_TO_2213`) ·
`CAMPAIGN_PIKACHU_WORLD_2000` · frontend (`FRONTEND-DISPLAY-CONTRACT.md`,
`DEFERRED UNTIL AFTER 2213`).
