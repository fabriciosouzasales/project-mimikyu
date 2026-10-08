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
--     CORRIGIDO (BATCH3-P7-SCOPE-CORRECTION-01). A versão anterior filtrava
--     APENAS por `j.status` e exigia "UMA única linha". Essas duas coisas são
--     incompatíveis: sem `persistence_status = 'PENDING'`, a query agrega o
--     universo INTEIRO dos jobs vivos — inclusive rows já TERMINALIZADAS —, e
--     o LIVE devolve três combinações:
--
--         APPROVED / VALID   / INSERTED  = 12.314   <- terminal
--         PENDING  / NEEDS_REVIEW / PENDING = 1.642 <- ALVO
--         SKIPPED  / INVALID / UNCHANGED =     62   <- terminal
--
--     O critério era mais estreito do que a query, e produzia STOP em estado
--     saudável. A autoridade do universo é a PRÓPRIA 2212, que escreve em
--     `job vivo + persistence_status = 'PENDING'` — não em "job vivo".
--     O predicado da 2212 passa a ser o predicado do P7.
--
--     `decision_status` e `validation_status` continuam DELIBERADAMENTE FORA
--     do WHERE: são as colunas de diagnóstico. Mantê-las no GROUP BY é o que
--     faz o gate revelar qualquer combinação PENDING inesperada em vez de
--     escondê-la atrás de um filtro.
--
--     Esperado: UMA única linha — STAGED / PENDING / NEEDS_REVIEW / PENDING
--     / 1642. Qualquer OUTRA combinação dentro de
--     `persistence_status = 'PENDING'`, ou n <> 1642 → **STOP antes de
--     qualquer write**. NÃO adaptar a expectativa ao que aparecer.
--
--     INSERTED e UNCHANGED sob jobs STAGED NÃO são violação: ver a nota
--     "Estados terminais sob jobs STAGED" logo abaixo do Batch 3.
SELECT j.status            AS job_status,
       r.decision_status,
       r.validation_status,
       r.persistence_status,
       count(*)            AS n
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
   AND r.persistence_status = 'PENDING'
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
| **P7** | **1 linha: STAGED / PENDING / NEEDS_REVIEW / PENDING / 1642** — dentro de `persistence_status = 'PENDING'`, que é o universo de escrita da `2212`. Rows terminais (`INSERTED`, `UNCHANGED`) sob jobs `STAGED` ficam fora do recorte e não são violação (`BATCH3-P7-SCOPE-CORRECTION-01`) |
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
`C1`), e a partir de `BATCH2-GAME-CODE-CORRECTION-01` cada seed abre com um
**PASSO 0 — PREFLIGHT de referência obrigatória**, anterior a qualquer write:
`SEED_GAME_REFERENCE` em `2230`/`2231`/`2232` e `SEED_SOURCE_REFERENCE` em
`2232`. Eles existem porque a execução LIVE de `BATCH2-VOCABULARY-01` mostrou
que referência ausente não falhava — virava `INSERT` de 0 linhas, detectado só
três passos adiante pelo gate de contagem. Este postcheck é a confirmação
externa.

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

**B3.1 — reexecutar P7** (versão corrigida, com
`AND r.persistence_status = 'PENDING'`). Esperado: **uma única linha dentro do
recorte `PENDING`** — `STAGED / PENDING / NEEDS_REVIEW / PENDING / 1642`.
Qualquer **outra** combinação dentro de `PENDING`, ou n ≠ 1642 → **STOP**.

> **Estados terminais sob jobs `STAGED` — não são violação**
> (`BATCH3-P7-SCOPE-CORRECTION-01`).
>
> O LIVE tem, sob jobs `STAGED`, **12.314** rows `APPROVED / VALID / INSERTED`
> e **62** rows `SKIPPED / INVALID / UNCHANGED`. São **estados terminais**, e
> são **compatíveis com o closeout `BULK-STP-01 / CLASS A`**: os jobs
> permanecem `STAGED` justamente porque ainda **retêm as `NEEDS_REVIEW`** — foi
> o que aquele closeout registrou ao contabilizar *"51 `COMPLETED` / 62
> `STAGED`, os que retêm `NEEDS_REVIEW`"*.
>
> **Eles não pertencem ao universo de escrita da `2212`**, que opera em
> `job vivo + persistence_status = 'PENDING'`. Medido no LIVE: o recorte
> `PENDING` tem **1.642** rows, das quais **0** não são
> `NEEDS_REVIEW`/`PENDING`, e o alvo do guard `2214`
> (`job vivo + PENDING + VALID`) é **0**.
>
> Nada aqui reabre a Classe A: **nenhuma investigação, nenhuma correção de
> dados**. É reconciliação do contrato do gate, não do dado.

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

## Batch 5 — IDENTIDADE DE STAGING + ROUTING

> **REORDENADO (`ROLLOUT-DEPENDENCY-CORRECTION-01`).** Até esta correção, o
> Batch 5 executava a `2212` e o Batch 6 instalava `2210`/`2211` — ou seja, o
> plano rodava a `2212` **antes** dos seus dois predecessores. Isso é
> impossível por construção, e os próprios artefatos dizem: a `2212` aborta com
> `ROUTING_MISSING: rode a Query 2211 antes` e chama
> `internal.resolve_variant_row_axes()`, que nasce na `2211`; e a sua PROVA DE
> NÃO-COLISÃO pressupõe `uq_cvir_row_identity`, que nasce na `2210`. O `DAG.md`
> já declarava `2212 → predecessores 2210 · 2211 · 2232`: a tabela estava
> certa, a projeção operacional é que estava invertida. Batches 5 e 6 trocaram
> de conteúdo; a numeração foi preservada.

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

## Batch 6 — RESOLUÇÃO OPERACIONAL + PROVAS

| Ordem | Artefato | Natureza |
|---|---|---|
| 1 | `2212` | **write** — resolução operacional · **JÁ EXECUTADA NO LIVE (v3.1, defeituosa)** |
| 2 | `2233` | **write** — forward-fix do escopo · **PENDENTE** |
| 3 | `2832` | prova, `ROLLBACK` |
| 4 | `2833` | prova, `ROLLBACK` |

Pré-condição dura: **`2210` e `2211` LIVE** (Batch 5) e **`2232` LIVE**
(Batch 2). A `2212` os verifica ela mesma — `ROUTING_MISSING` e
`VOCABULARY_MISSING` — e aborta antes de qualquer write.

### O defeito de escopo e por que existe uma `2233`

A `2212` foi executada no LIVE na **v3.1** (ledger `20260920172947`, 1×,
commit `d07cbedf7c61830d748d92445f7e2aded9e373fa`). Aquela versão passava
`cs.code` como 4º argumento de `internal.resolve_variant_row_axes()`.

O 4º argumento é o identificador do Card Set **na Fonte externa**
(`card_set_external_reference.external_set_id`), comparado sem tradução contra
`card_edition_context_external_mapping.external_set_id`. `card_set.code` é o
código **interno**. Os dois divergem:

| Fonte (TCGdex) | `mfb` | `base2` | `dp1` | `dp4`–`dp7` | `svp` | `swsh9` |
|---|---|---|---|---|---|---|
| `card_set.code` | `MFB` | `BASE2` | `DP1` | `DP4`–`DP7` | `SVP` | `SWSH9` |

Resultado medido: **0 de 14** mappings `SOURCE_SET_SCOPED` casam literalmente;
todos ficaram inalcançáveis. O defeito é **silencioso** porque o eixo é
fail-closed — token sem mapping ativo no escopo permanece no residual de
Finish e a linha resolve como `RESOLVED_NO_EDITION_CONTEXT`, que a `2212`
grava como JSON `null`. Nenhuma exceção é levantada.

As 8 pós-condições internas da `2212` passaram porque ela registrou fielmente
o que a `2211` resolveu — o defeito estava no que ela **entregou** à `2211`.
O gate C1 da `2232` não pegou porque ele **traduz** (`LEFT JOIN
card_set_external_reference … AND cs2.code = k.set_code`); a `2211` roteava
**sem** traduzir. Essa assimetria era invisível a todos os gates anteriores e
só apareceu num postcheck **externo**, confrontando a partição semântica.

A `2212` **não pode ser reexecutada**: já consta no ledger 1× e seu
`bf_operational` só inclui rows *sem* a chave — após a v3.1 todas as 1.642 já
têm chave, então uma reexecução teria plano vazio. A idempotência que a
protege é o que a impede de se auto-reparar. Daí o forward-fix `2233`, único
mecanismo de reconciliação do dado já gravado. A `2212` v3.2 corrige o
**arquivo** (instalação limpa e próximo leitor), nunca o LIVE, e traz no topo
o bloco `*** NAO REEXECUTAR ***`.

### DUAS grandezas diferentes — não confundir

Este é o ponto que mais gerou leitura errada e fica registrado aqui em
definitivo. **1.085 e 1.092 não são o mesmo número medindo a mesma coisa.**

| | Partição semântica | Eixo Edition Context |
|---|---|---|
| **O que é** | classificação editorial de qual **eixo** explica o resíduo de cada row | resultado do **routing** (`2211`) sobre cada row |
| **Onde mora** | `SEMANTIC-PARTITION-DECISIONS-54.md` | `normalized_data.edition_context_profile_id` |
| **Valores** | FINISH 423 · PRINTING 72 · **EDITION_CONTEXT 1.085** · INDETERMINATE 61 · (1) | **UUID 1.092 · NULL 550 · AUSENTE 0** |
| **Soma** | 1.642 | 1.642 |
| **Natureza** | decisão editorial, estável | estado do dado, muda com o vocabulário |

A diferença de **7** é conhecida, explicada e **não é defeito**: são as 7 rows
`foil=LEAGUE + stamp=STAFF`. A partição as classifica fora de
`EDITION_CONTEXT` porque o que as mantém pendentes é o eixo de **acabamento**
(`foil=league` sem Variant Type). Mas o eixo de Contexto de Edição resolve
legitimamente `stamp=STAFF → papel STAFF`, e por isso elas **têm** perfil.
Os dois eixos são independentes: indeterminação no Finish não invalida
resolução no Edition Context. **Decisão fechada por Fabrício: preservar.** A
`2211` não deve ser alterada para bloquear isso, e o B3 não reabre.

Corolário que vale registrar: **JSON `null` significa apenas "esta row não tem
Contexto de Edição"** — não significa que a Variant esteja semanticamente
resolvida. A resolução semântica da Variant depende dos três eixos.

E **`AUSENTE = 0` é comportamento correto**, não lacuna: token desconhecido é
fail-closed, permanece no residual de Finish, produz `cardinality(v_ec_sig)=0`
e portanto `RESOLVED_NO_EDITION_CONTEXT`. Os estados `NEEDS_REVIEW_*` só
ocorrem para token **conhecido-mas-inativo** ou perfil ausente.

### A `2233` é `INCIDENT-ONLY` — dois caminhos, permanentemente

**CURRENT LIVE ROLLOUT** (o banco de hoje):
`2212` **v3.1** já executada → **`2233`** (reparo) → `2832` → `2833`

**CLEAN / CANONICAL PATH** (instalação nova, replay, ambiente novo):
`2212` **v3.2**, que já traz o source-set canônico e nasce em 1.092/550/0 →
`2832` → `2833`. **A `2233` não existe neste caminho.**

> `INCIDENT-ONLY` · `FORWARD-FIX` · **NÃO REPLAYAR EM AMBIENTE LIMPO**

A proteção é mecânica, não documental. O gate `RP_G3_CURRENT_STATE` exige
estado atual **exatamente 1.026 / 616 / 0**, e o `RP_G5_DELTA_SIZE` exige
delta **exatamente 66**. Num ambiente onde a v3.2 rodou correta, o estado é
1.092 / 550 / 0 e o delta é 0 — os dois gates falham alto, antes de qualquer
escrita, nomeando os números medidos e os esperados. Replay indevido é
impossível por construção.

### Contrato numérico da `2233`

| Momento | UUID | JSON `null` | AUSENTE | Total |
|---|---|---|---|---|
| Após `2212` v3.1 (estado LIVE hoje) | 1.026 | 616 | 0 | 1.642 |
| Após `2233` (correto) | **1.092** | **550** | **0** | **1.642** |
| Delta | **+66** | **−66** | 0 | 0 |

As 66 são **todas** `NULL → UUID`. Transições proibidas, provadas como zero
antes da escrita: `UUID → UUID diferente`, `UUID → NULL`, `qualquer → AUSENTE`.
Nenhuma das 7 `LEAGUE+STAFF` está entre as 66 — gate `RP_G8D`.

Todos os gates da `2233` são **pré-write**; qualquer divergência levanta
exceção nomeada e desfaz a transação inteira. Os baselines `1.642`, `847` e
`415` são **preservados e provados**, nunca recalculados.

### A convenção `cs.code` foi REMOVIDA

Até esta rodada, `2221` e `2222` documentavam no cabeçalho "`cs.code` como
`p_external_set_id` — a mesma convenção fixada em 2219 e 2221". **Essa
convenção estava errada e foi eliminada de todos os artefatos CURRENT.** A
convenção vigente, única, é:

> O 4º argumento de `internal.resolve_variant_row_axes()` vem de
> `internal.resolve_variant_mapping_scope(card_set_id, asset_source_id)`.
> Nunca de `card_set.code`.

Os **11 call sites reais** foram corrigidos: `2212` (1) · `2219` (3) ·
`2220` (2) · `2221` (1) · `2222` (2) · `2831` (1) · `2832` (1). O 12º
resultado da varredura, `2834:387` (`'VEC2834A'`), é **fixture sintético
deliberado** — uma `card_set_external_reference` criada dentro da própria
sentinela — e foi preservado. A Edge não chama a função (faz preload próprio e
compara contra o ID real da Fonte) e também não foi alterada.

**O guard `2214` saiu deste batch** e passou ao **Batch 8-BIS**, depois da
Edge. Ver a nota de posicionamento lá: promover o guard estrito antes de
existir um produtor capaz de gerar a chave nova tornaria a própria importação
irrecuperável durante a janela.

`2832`/`2833` rodam **entre** a resolução e o guard, de propósito: provam o
predicado contra as combinações reais **antes** de ele virar obrigatório —
agora com o guard duas etapas adiante, não uma.

**A `2212` é executável VERBATIM** desde a v3.1: o `PASSO 0` resolve
`game.code='POKEMON'` e `asset_source.code='TCGDEX'` por consulta, com
preflight fail-loud de exatamente-um. Não há UUID a colar, e **nenhuma edição
manual do arquivo durante a execução**.

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
| **tri-estado do universo operacional** | **UUID 1.092 · NULL 550 · AUSENTE 0** (após a `2233`) |
| `2233` | todos os gates `RP_*` passaram; 66 rows `NULL → UUID` |
| `2832` | 14/14 |
| `2833` | 11/11 |
| `cancelled_sem_chave_total` | **847 → 847** (idêntico a B3.2) |
| `cancelled_valid_pending_sem_chave` | **415 → 415** (idêntico a B3.2) |
| `bf_params` | resolvido por code, **1 linha**, zero NULL (`BF_GAME_REFERENCE` / `BF_SOURCE_REFERENCE` / `BF_PARAMS_CARDINALITY` não dispararam) |

> **Ordem obrigatória**: `2832` e `2833` só rodam **depois** da `2233`. Rodar
> a `2832` sobre o estado 1.026/616/0 mede o dado defeituoso — foi exatamente
> o que o postcheck externo detectou e o que motivou o STOP do Batch 6.

Os dois números de `CANCELLED` são comparados **separadamente**. Qualquer um
que mude prova que a `2212` vazou para o histórico terminal — **STOP**.

---

## Batch 7 — CONSUMIDORES B + VETORES · ✅ **CLOSED**

> **FECHADO em `BATCH7-2834-LIVE-CLOSEOUT-01`.** Os quatro consumidores estão
> no ledger e o `2834` passou no LIVE. Critério de prosseguir satisfeito;
> próximo estágio é o **Batch 8 — EDGE**.

| Ordem | Artefato | Estado |
|---|---|---|
| 1 | `2219` · `apply_variant_type_mapping` | **CLOSED** — ledger `20260920212007` |
| 2 | `2220` · read contract | **CLOSED** — ledger `20260920212555` |
| 3 | `2221` · `admin_resolve_printing_mapping` | **CLOSED** — ledger `20260920214852` |
| 4 | `2222` · `create_card_printing_profile_with_backfill` | **CLOSED** — ledger `20260920215837` |
| 5 | `2834` · runner dos vetores (read-only, `ROLLBACK`) | **PASS / CLOSED** — `LIVE-EXECUTION-06` |

**Evidência do `2834`:** 18/18 casos PASS · 17/17 vetores · 8/8 estados ·
**0 FAIL · 0 SKIP** · zero resíduo persistente (postcheck 8/8). O S3 é
fail-closed: terminar sem exception já implica todos esses números.

**Canal de execução.** A execução final bem-sucedida ocorreu **no SQL Editor do
Supabase**. O que falhou foi o **modo multi-statement**, que não preserva TEMP
TABLEs entre statements — provado por probe mínimo independente do `2834`
(`42P01 relation "_mmkyu_tx_probe" does not exist`). O caminho `psql` + Session
Pooler foi investigado e **abandonado**; em seguida **dois probes
independentes** provaram single-statement e `DO` aninhado no próprio SQL
Editor, e foi assim que passou: **envelope single-statement v2.7**. O
JIT/Temporary Access foi **encerrado antes da execução final**.

**Artefato canônico × artefato executado.** O **runner canônico é o `2834`
v2.6**; o **artefato efetivamente executado foi o envelope v2.7**, cuja
auditoria provou que, removido o wrapper, seus **9 `EXECUTE`** recompõem
exatamente o transient v2.6 funcional. O PASS **valida o contrato funcional
canônico**, mas o arquivo v2.6 não foi o literalmente executado. O v2.7 **não
vira autoridade canônica e não deve ser incorporado ao runner**.

Seis tentativas até aqui: `-01` `raw_data.type` · `-02` `family` NULL · `-03`
`display_order` · `-04` `external_token` · `-05` STOP semântico (JSON `null`) ·
**`-06` PASS**. O histórico completo está em `PACKAGE-STATUS.md`, itens 4 a 10.

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

## Batch 8 — EDGE · ✅ **CLOSED**

> **FECHADO em `BATCH8-EDGE-CLOSEOUT-01`.** `import-card-variants` **v15
> ACTIVE**, `verify_jwt=true`, postdeploy validado **sob FREEZE**. Próximo
> estágio: **Batch 8-BIS — `2214`**.

Deploy da `import-card-variants` com o eixo 3 + suíte Deno.
Só aqui: antes, as tabelas que o preload lê não existiam.

**O eixo 3 NÃO entrou inline no `index.ts`**, como o documento de desenho
previa: foi para `services/edition-context.ts`, exportado. `index.ts` registra
o servidor no topo do módulo e não exporta nada — uma função declarada lá não
pode ser importada por um teste sem subir um listener, e o teste voltaria a
precisar de réplica. Junto vieram dois helpers puros em `services/database.ts`
(`buildVariantIdentityKey`, `buildVariantNormalizedData`) que eliminaram as
três montagens independentes da chave de identidade.

**Provas offline:** `deno check` PASS · Edition Context **136/136** ·
`services/` **74/74** · SOURCE_SET **12/12** · `git diff --check` PASS.

**Postdeploy executado — PRE v14 × POST v15, todos iguais:**

| Probe | Resultado |
|---|---|
| A · POST sem `Authorization` | `401 UNAUTHORIZED_NO_AUTH_HEADER` |
| B · POST JWT não-admin | `403 FORBIDDEN_NOT_ADMIN` |
| C · `OPTIONS` origin permitido | `204` + CORS |
| D · POST admin + JSON malformado | `400 INVALID_JSON` |
| E · POST admin + `{}` | `400 CARD_SET_ID_REQUIRED` |

`INVALID_USER_SESSION` intermediários = tokens expirados, descartados após
renovação. Rollback não foi necessário.

**Zero writes de negócio, por construção:** D e E retornam nas linhas 507/512
do `index.ts`, antes do primeiro write (`createVariantJobProcessing`, 539) e de
qualquer leitura de catálogo. Nenhum `card_set_id` real, nenhum job, nenhum SQL.

> ### POSTCHECK ORIGINAL — RECONCILIADO, NÃO CUMPRIDO NO LIVE
>
> Este batch previa *"suíte Deno verde + `2834` reexecutado — os dois lados
> contra o mesmo `edition-context-axis-vectors.json`"*, com o critério de
> prosseguir *"DB e Edge concordam vetor a vetor"*.
>
> **A metade `2834` reexecutado não foi cumprida, e o critério não foi
> observado no LIVE** — ambos exigiriam criar job de importação, que o FREEZE
> proíbe. A reexecução do `2834` foi **removida do gate por ausência de
> justificativa material**: nada do lado SQL mudou nesta rodada (fixture blob
> `676b9103…` e `2834` blob `fbabf0bf…` intocados).
>
> O que existe no lugar: **dois runners independentes contra a MESMA fixture** —
> `2834` PASS no LIVE (Batch 7) e a suíte Deno 136/136 agora. Isso estabelece
> **equivalência de contrato**, e é o mais forte disponível sob FREEZE. Não é
> concordância observada em produção, e este documento não a declara como tal.
>
> **A compatibilidade funcional com importação real permanece
> INTENCIONALMENTE NÃO PROVADA até o UNFREEZE.**

**Prosseguir:** ✅ satisfeito pela equivalência de contrato acima, com a
limitação declarada.

---

## Batch 8-BIS — GUARD ESTRITO (`2214`) · ✅ **CLOSED**

> **FECHADO em `BATCH8-BIS-2214-CLOSEOUT-01` (2026-09-22).** A `2214` **v3.1**
> (blob `30e19523d91d9bc127dcefe6f4cb09e6c263ab73`) foi **EXECUTADA NO LIVE**,
> manualmente pelo **SQL Editor do Supabase**, retorno `Success. No rows
> returned`. Postcheck read-only `BATCH8-BIS-2214-LIVE-POSTCHECK-01`:
> **PASS / LIVE VALIDATED — 15/15 GATEs**. O guard job-aware está **ATIVO**.
> **FREEZE continua ATIVO.** Próximo estágio: **Batch 9 — `2217` EXPAND**,
> **NÃO EXECUTADA**, exigindo readiness audit e mandato de Fabrício.
>
> **Ledger = 0 — divergência de RASTREABILIDADE, declarada, não mascarada.**
> Não há linha para `2214_promote_valid_requires_edition_context_key` em
> `supabase_migrations.schema_migrations`. Isso **não** é "não executada": o
> ledger é escrito pela CLI (`db push` / `migration up`), nunca pelo motor do
> Postgres, e a execução direta no SQL Editor aplica e comita o DDL sem passar
> por ele. O estado físico é provado pelos catálogos que o próprio motor
> mantém — `pg_trigger` e `pg_proc` —, medidos nos 15 gates. A inversa também
> vale: `ledger = 1` não provaria nada, porque a linha pode ser inserida à mão
> sem o DDL ter rodado. Mesma classe da `2202`. **Reconciliação do ledger fica
> fora deste closeout**, por mandato; nada foi inserido.
>
> **⚠️ CURRENT LIVE — não reexecutar a `2214` sem novo mandato.**

> **REPOSICIONADO (`ROLLOUT-DEPENDENCY-CORRECTION-01`).** A `2214` estava no
> Batch 5, **antes** dos consumidores e da Edge. O `DAG.md` já declarava
> `2214 → predecessores 2833 · Edge deployada`: de novo, a tabela estava certa
> e a projeção operacional divergia.
>
> **Por que a ordem importa, e não é formalidade.** A `2214` é o guard que
> passa a **exigir** a chave de contexto de toda row operacional
> `PENDING + VALID`. Promovê-la antes da Edge capaz de produzir essa chave
> cria uma janela em que o produtor ainda escreve no contrato antigo e o banco
> já recusa o contrato antigo — importação quebrada, e quebrada de um jeito
> que o FREEZE esconde em vez de proteger, porque o defeito só apareceria no
> UNFREEZE. Com a Edge LIVE e validada vetor a vetor (Batch 8), o guard passa
> a exigir algo que já existe.

| Ordem | Artefato | Natureza |
|---|---|---|
| 1 | `2214` | **write** — guard de transição operacional |

Pré-condição dura: **`2833` PASS** (Batch 6) **e Edge LIVE e validada**
(Batch 8). A semântica do guard não mudou — continua job-aware, continua
exigindo a chave só do universo operacional, e continua não tocando histórico.

**Postcheck:**
```sql
-- Guard instalado, job-aware e ligado à função canônica.
-- Esperado: 1 linha, com TODAS as colunas booleanas em `true`.
SELECT t.tgname,
       count(*) OVER ()                    AS n_triggers,          -- 1
       t.tgtype::int = 23                  AS tgtype_exato,        -- BEFORE+ROW+INSERT+UPDATE,
                                                                   -- sem DELETE/TRUNCATE/INSTEAD
       t.tgfoid = to_regprocedure('internal.guard_cvir_normalized_shape()')::oid
                                           AS aponta_para_o_guard, -- vínculo por OID, não por nome
       (SELECT array_agg(a.attname ORDER BY a.attname)
          FROM unnest(t.tgattr::int2[]) u(attnum)
          JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attnum = u.attnum)
         = ARRAY['normalized_data','persistence_status','validation_status']::name[]
                                           AS update_of_exato
  FROM pg_trigger   t
  JOIN pg_class     c  ON c.oid  = t.tgrelid
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
 WHERE NOT t.tgisinternal
   AND ns.nspname = 'public'
   AND c.relname  = 'catalog_variant_import_row'
   AND t.tgname   = 'trg_cvir_normalized_shape';

-- Nenhuma row OPERACIONAL VALID sem a chave — o guard não teria o que recusar.
SELECT count(*) AS operacional_sem_chave                    -- esperado: 0
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
   AND r.persistence_status='PENDING' AND r.validation_status='VALID'
   AND NOT (r.normalized_data ? 'edition_context_profile_id');

-- Histórico terminal segue intocado — os MESMOS dois predicados do Batch 3.
SELECT
  count(*)                                                   AS cancelled_sem_chave_total,          -- 847
  count(*) FILTER (WHERE r.validation_status = 'VALID'
                     AND r.persistence_status = 'PENDING')    AS cancelled_valid_pending_sem_chave   -- 415
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status = 'CANCELLED'
   AND NOT (r.normalized_data ? 'edition_context_profile_id');
```

**Prosseguir se:** 1 linha na primeira query com `tgtype_exato`,
`aponta_para_o_guard` e `update_of_exato` **todos `true`** ·
`operacional_sem_chave = 0` · `847 → 847` e `415 → 415`.

> ### O POSTCHECK ACIMA FOI CORRIGIDO NO CLOSEOUT — o original era defeituoso
>
> **Registro do defeito, para que não se repita.** A primeira query deste
> postcheck, como escrita no planejamento, filtrava o trigger por
> `t.tgname LIKE '%edition_context%'`. O trigger instalado pela `2214` chama-se
> **`trg_cvir_normalized_shape`** — sem `edition_context` no nome. Rodada como
> estava, devolveria **zero linhas**, e "zero linhas" seria lido como "guard
> ausente": um falso STOP. Pior no sentido inverso, se alguém contornasse o
> zero: ela só olhava dois bits de `tgtype` e **nada** sobre qual função o
> trigger executa — um trigger canônico apontando para a função errada passaria.
>
> **Por que foi substituída em vez de apenas anotada
> (`BATCH8-BIS-2214-CLOSEOUT-CORRECTION-02`).** Este documento é **autoridade
> operacional** e pode ser reexecutado num CLEAN / CANONICAL PATH. Deixar SQL
> defeituoso como bloco normativo, ainda que comentado, é deixar uma armadilha
> armada. A versão vigente troca heurística de nome por **prova estrutural**:
> `tgtype` por **identidade exata** (`= 23`), `tgfoid` comparado ao **OID** da
> função canônica, e `tgattr` resolvido por `attnum` e comparado ao conjunto
> exato das três colunas. As duas outras queries do bloco **não** tinham
> defeito — seguem como estavam, com o mesmo predicado do harness LIVE.
>
> **Evidência forte do closeout, que este bloco não substitui:**
> `BATCH8-BIS-2214-LIVE-POSTCHECK-01` (+ `CORRECTION-01`) — bloco único
> READ-ONLY de **15 GATEs**, todos `OK`, superconjunto estrito do que está
> acima; e antes dele `BATCH8-BIS-2214-LIVE-PRECHECK-01` (+ `CORRECTION-01`),
> medindo o LIVE **antes** de autorizar a migration. O postcheck deste
> documento é a versão **concisa e correta** para reuso; o harness de 15 gates
> é o que foi efetivamente executado e validou o LIVE.

---

## Batch 9 — GUARD → WRITER: EXPAND → SWITCH → CONTRACT · **CLOSED**

> ✅ **BATCH 9 CLOSED em 2026-09-25** (`BATCH9-EDITION-CONTEXT-WRITER-CLOSEOUT-01`).
> **`2224` → `2217` → `2218` → `2223` todos `EXECUTED / LIVE VALIDATED /
> CLOSED`** — EXPAND → SWITCH → CONTRACT **completo**. Estado LIVE final:
> `internal.write_card_variant` com **uma única** assinatura (7 args, sem
> DEFAULT, SECDEF, `search_path=""`, owner `postgres`, ACL owner-only,
> corpo LF `478aada8…` 2.707 B / 54 LF); writer de 6 args **AUSENTE**;
> `admin_confirm_catalog_variant_import` = corpo LF `b83f7708…` 20.095 B /
> 389 LF, ACL `postgres` + `authenticated` (sem terceiros, sem GRANT OPTION);
> **1** caller do writer (o confirm); `card_variant` 24.893 · EC não-nulo 0 ·
> jobs em voo 0 · `session_replication_role = origin`. Ledger de `2218`/`2223`
> = 0 (rastreabilidade, mesma classe da `2214`/`2224`/`2217`). **FREEZE
> ATIVO.** ~~Próximo: **Batch 10 / `2209` — READINESS** (não iniciada).~~
> *(superado: o Batch 10 / `2209` foi executado e validado em 2026-09-25 —
> ver a seção do Batch 10 abaixo.)*
>
> *Histórico (texto de 2026-09-23, preservado):* **PARCIALMENTE EXECUTADO.** A **`2224` está `EXECUTED / LIVE VALIDATED /
> CLOSED`** (2026-09-22, `BATCH9-2224-CLOSEOUT-01`): blob executado
> `5bae844bc37022de3bb2ad34e52b5f8ac31da929`, publicado em `2fcd6231`,
> aplicada **direto no SQL Editor**, POSTCHECK read-only **20/20 GATEs ·
> GLOBAL PASS**, **zero drift** PRE→POST. A **`2217` está `EXECUTED / LIVE
> VALIDATED`** (2026-09-23, `BATCH9-2217-LIVE-VALIDATION-CLOSEOUT-01`), com
> **exceção documental explícita de terminador de linha** — ver o bloco
> "CUMPRIDO" abaixo do postcheck da `2217`. **`2218` e `2223` seguem **NÃO
> EXECUTADAS** — cada uma exige **readiness audit** e **mandato explícito de
> Fabrício**. Próximo estágio: **`2218` SWITCH — READINESS** (não iniciada).
> FREEZE **ATIVO**.
>
> **`2224` e `2217` no ledger = 0.** Diagnóstico de RASTREABILIDADE, **não** "não
> executada": o `supabase_migrations.schema_migrations` é escrito pela CLI,
> nunca pelo motor do Postgres. A prova física são os catálogos (`pg_proc` /
> `pg_trigger`), medidos nos 20 gates. Mesma classe da `2202` e da `2214`.
>
> ### A `2224` entrou na frente (`BATCH9-2217-READINESS-CORRECTION-01`)
>
> A `BATCH9-2217-READINESS-AUDIT-01` resultou em **STOP**: a `2217` declarava
> delegar o same-Game do 3º eixo a `validate_card_variant_game_consistency`,
> *"que a Query 2220 estende"*. **As duas metades eram falsas** — aquela
> função (`161:60-104`) compara Card × **Variant Type** e seu trigger é
> `UPDATE OF card_id, variant_type_id`; a `2220` redefine
> `variant_type_mapping_impact`/`_decision` e **não a toca**. Ou seja: **não
> existia** proteção server-side recusando `edition_context_profile_id` de
> outro Game — a FK da `2208` garante só existência.
>
> Decisão: **guard dedicado**, espelhando a `2170` (que já resolveu isto para
> Impressão). O writer continua sem validar same-Game, de propósito — agora
> apontando uma autoridade que de fato existe.

**Quatro artefatos, quatro STOPs.** Não colapsar em uma chamada.

| Ordem | Artefato | STOP obrigatório depois |
|---|---|---|
| 1 | **`2224` GUARD same-Game do 3º eixo** ✅ **EXECUTADA / LIVE VALIDATED / CLOSED** | **cumprido** |
| 2 | **`2217` EXPAND** ✅ **EXECUTADA / LIVE VALIDATED** *(exceção EOL documentada)* | **cumprido** |
| 3 | **`2218` SWITCH** ✅ **EXECUTADA / LIVE VALIDATED / CLOSED** (v1.3) | **cumprido** |
| 4 | **`2223` CONTRACT** ✅ **EXECUTADA / LIVE VALIDATED / CLOSED** (v1.1) | **cumprido** |

**Postcheck após `2224`:** 1 função `internal.enforce_card_variant_edition_
context_profile_game` (SECDEF · `proconfig = ARRAY['search_path=""']` · ACL sem
PUBLIC/anon/authenticated) · 1 trigger `trg_card_variant_edition_context_
profile_game` com `tgfoid` = OID dessa função, `tgtype = 23` e `UPDATE OF` =
`card_id` + `edition_context_profile_id`. O PASSO 5 da própria `2224` prova
tudo isso, fail-closed.

> ✅ **CUMPRIDO em 2026-09-22.** O POSTCHECK LIVE read-only externo
> (`BATCH9-2224-LIVE-POSTCHECK-01`) devolveu **20/20 GATEs · GLOBAL PASS**,
> e foi além do texto acima: ACL **owner-only** provada por `aclexplode`
> (owner `postgres`, **único** grantee com `EXECUTE` = `postgres` — não
> apenas "sem PUBLIC/anon/authenticated") · topologia de `card_variant` =
> **exatamente os 4** triggers canônicos · **duplicação cluster-wide do
> `tgfoid` = 0** · profile órfão `0` · Game irresolvível `0` · Same-Game
> mismatch `0` · locks conflitantes `0` · **zero drift** (`card_variant`
> 24.893 → 24.893, EC não-nulo 0 → 0).

**Postcheck após `2217`:** 2 assinaturas (6 e 7 args); confirm ainda chama a de 6.

> ✅ **CUMPRIDO em 2026-09-23 — com EXCEÇÃO DOCUMENTAL DE TERMINADOR DE
> LINHA** (`BATCH9-2217-LIVE-VALIDATION-CLOSEOUT-01`). Artefato: blob
> `c9abf5d77be5823c888e594f93b754befe8cb991` (publicado, **inalterado**),
> aplicado pelo SQL Editor. O POSTCHECK LIVE read-only
> (`BATCH9-2217-LIVE-POSTCHECK-CORRECTION-01`) rodou **via MCP
> `execute_sql`** — não pelo Dashboard — e devolveu **35/36 GATEs**
> (estruturais 32/33 · operacionais 3/3), **único STOP = G6.a**:
>
> - **exatamente 2** overloads de `internal.write_card_variant` (6 e 7 args);
>   7 args = `text, uuid, uuid, uuid, integer, uuid, uuid`, sem DEFAULT ·
>   ACL das duas **owner-only** `{postgres=X/postgres}` · owner writer6 =
>   writer7 = `admin_confirm` = `postgres`;
> - corpo de 6 args **byte-idêntico** ao esperado (md5 `d01cfc0b…`, 1.966
>   bytes) · `admin_confirm_catalog_variant_import` **ainda chama a de 6**;
> - guard `2224` intacto (`tgfoid` = OID da função, `tgtype = 23`) · jobs em
>   voo 0 · `card_variant` 24.893 · EC não-nulo 0 · locks conflitantes 0.
>
> **Adjudicação do G6.a: TRANSPORT/EOL-ONLY — NÃO MATERIAL.**
>
> | Identidade | Resultado |
> |---|---|
> | **raw byte identity** do `prosrc` de 7 args | **DIFFERENT — exclusivamente por CRLF**: LIVE md5 `2909175fe2122e0eb461a2416eee0c06`, 2.761 bytes × esperado (LF, derivado do blob) md5 `478aada84470a7fba1c9b6d5254a40f1`, 2.707 bytes. Delta = **54 bytes = 54 LF** do corpo |
> | **normalized body identity** (CRLF→LF) | **EXACT** — md5 normalizado = `478aada84470a7fba1c9b6d5254a40f1` (G6.b) |
> | **semantic / functional divergence** | **NONE** — nenhum dos 11 literais de string do corpo atravessa linha; o CR só aparece como whitespace entre tokens PL/pgSQL |
>
> Causa: colagem a partir do Windows no SQL Editor converteu LF → CRLF antes
> do envio. **Não se registra** *"audited = executed byte-identical"*: o que
> foi provado é identidade **normalizada**, não bruta. O arquivo da `2217`
> **não** foi alterado para "casar" com o LIVE.
>
> **Regra permanente (vale para `2218`, `2223` e execuções futuras):**
> (1) hash **bruto** diferente com hash **normalizado por EOL** idêntico =
> exceção documentável de transporte, adjudicada explicitamente; (2) hash
> **normalizado** diferente **continua sendo STOP**; (3) preferir canal que
> preserve o payload controlado — **MCP / CLI** — em vez do **Dashboard Query
> Editor**, que além do EOL já **anexou SQL próprio** ao payload (`ALTER TABLE
> public ENABLE ROW LEVEL SECURITY;`, causa do 42P01 do primeiro POSTCHECK).
> Norma em `docs/standards/STD-001-database-standards.md` §10.
>
> A validação da `2224` **não** é reaberta: sem nova evidência, permanece
> `CLOSED / LIVE VALIDATED`. **Ledger da `2217` = 0** — rastreabilidade,
> não "não executada".
**Postcheck após `2218`:** confirm chama a de 7; as 2 assinaturas seguem vivas.

> ✅ **CUMPRIDO em 2026-09-25.** Antes da execução: LIVE PRECHECK Parte 1
> **38/38 GATEs** e performance **6/6** (`P2.A`/`P2.B`/`P2.C` custom sobre a
> maior massa real, 507 rows / 284 Cards, e `G2.A`/`G2.B`/`G2.C` generic);
> faixa 508–1000 rows **não medida empiricamente** (extrapolação registrada,
> não blocker). 1ª tentativa (v1.2, blob `983dbb63…`) falhou no **parse**
> (42601: `$$` dentro de comentário no bloco `DO` do PASSO 3) e um probe
> read-only provou **zero efeito físico**; correção v1.3 trocou só os
> delimitadores dos dois `DO` por `$pre2218$`/`$post2218$` (4 linhas, corpo da
> função intacto). **Artefato EXECUTADO:** blob
> `6f4dbd9c5ffe15bbf093a0747b7e77e8cc525553` · md5 `bedb5e32…` · 49.403 B ·
> corpo LF `b83f7708…`, via **MCP `execute_sql`**, 1 execução, sem erro. O
> arquivo no repositório recebeu depois **apenas** um bloco de comentário de
> closeout (blob documental diferente; executável idêntico — ver HANDOFF
> §0-SEPTIES). POSTCHECK independente: **LIVE VALIDATED**.

**Postcheck após `2223`:** 1 assinatura, 7 args.

> ✅ **CUMPRIDO em 2026-09-25.** v1.1 endurecida (`CONTRACT-HARDENING-01`):
> assinaturas exatas, hash físico do confirm, exatamente 1 caller por
> identidade, dependências formais fail-closed, `DROP … RESTRICT` exato,
> **sem idempotência**. LIVE PRECHECK **9/9 gates** (regex e varredura
> textual ampla com a mesma lista; 0 dependências; 0 sessões concorrentes).
> **Artefato EXECUTADO:** blob `72ba009eb2c76b2683b113910b57c6abe0546956` ·
> md5 `58ddd68f…` · 19.484 B, via **MCP `execute_sql`**, 1 execução, sem
> erro. Depois, **apenas** comentário de closeout no arquivo. POSTCHECK
> independente: writer6 **ausente**, writer7 única (`478aada8…` / 2.707 / 54,
> owner-only), confirm `b83f7708…` intacto, 1 caller — **LIVE VALIDATED**.
> As queries abaixo são o esboço original; os harnesses executados são
> superconjuntos estritos delas.

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

## Batch 10 — IDENTIDADE NOVA (liberada pelo T1) · **CLOSED (técnico)**

> ✅ **BATCH 10 CLOSED tecnicamente em 2026-09-25**
> (`BATCH10-2209-LIVE-VALIDATION-CLOSEOUT-01`); closeout publicado em
> `c85c7717…`. **`2209` `EXECUTED / LIVE VALIDATED`**: executada **1x**
> via **MCP `execute_sql`** (~18:03Z), logo após o JIT PRECHECK read-only
> (**15/15 gates**, `gate_pass = true`), que teve auditoria independente.
> Artefato **exatamente executado**: blob
> `390848500603325b545c944184ac51fb45aeee16` · md5
> `4a10e6528d82562c22103bfccf8cad45` · 7.075 B · 0 CR. Depois o arquivo recebeu
> **só comentários** (prova léxica: 49 tokens, 5 statements e literal
> idênticos). **POSTCHECK LIVE:**
> - `uq_card_variant_identity`: índice OID 221012 + constraint `contype='u'`,
>   `convalidated`, não deferrable, `UNIQUE NULLS NOT DISTINCT (card_id,
>   variant_type_id, printing_profile_id, edition_context_profile_id)`;
> - o índice é unique/valid/ready/live com `indnullsnotdistinct`, não é
>   parcial nem tem expressão, e ocupa 1.515.520 B;
> - as duas antigas continuam presentes e saudáveis (OID 151290 / 151291);
> - `card_variant` 24.893 · EC não-nulo 0 · duplicidade UNIQUE(4) 0/0 ·
>   **11** índices, 0 inválidos · owner/RLS/ACL preservados · jobs em voo 0 ·
>   zero lock ou transação residual · `session_replication_role = origin`.
>
> **Ledger `2209` = 0**: é rastreabilidade (o MCP não escreve no ledger), não
> reconciliar manualmente.
>
> **Locks efetivos:** `CREATE UNIQUE INDEX` toma `ShareLock` (bloqueia
> escrita); `ADD CONSTRAINT … USING INDEX` toma `AccessExclusiveLock` até o
> `COMMIT` (bloqueia também leitura, por milissegundos).
>
> *(Histórico — vigorou só entre a `2209` e a `2215`; superado pela execução
> da `2215` em 2026-09-26, ver Batch 11.)* **Invariante entre `2209` e
> `2215`:** havia **três** garantias UNIQUE ativas.
> As antigas continuam **mais restritivas**, então duas Variants que diferem só
> em Edition Context **ainda são rejeitadas**. Não houve instante sem proteção
> de identidade. **FREEZE ATIVO** e obrigatório.
>
> ~~**Próximo: Batch 11 / `2215` — READINESS** — `NÃO EXECUTADA / NÃO
> AUTORIZADA`.~~ *(superado: `2215` executada em 2026-09-26 — ver Batch 11.)*

| Ordem | Artefato |
|---|---|
| 1 | `2209` · ✅ EXECUTED / LIVE VALIDATED (2026-09-25) |

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

## Batch 11 — RETIRADA DAS IDENTIDADES ANTIGAS · **EXECUÇÃO CONCLUÍDA — `2215` ✅ · `2216` ✅ · CLOSEOUT DOCUMENTAL REGISTRADO**

> ✅ **`2216` v4.1 `EXECUTED / LIVE VALIDATED / CLOSED` em 2026-09-26**
> (`BATCH11-2216-LIVE-VALIDATION-CLOSEOUT-01`). Executada **1x** via
> **MCP `execute_sql`** (retorno bruto `[]`, `COMMIT` concluído), logo após o
> JIT LIVE PRECHECK read-only (`2216_live_precheck_v1`, blob `a73adf44…`,
> **18/18 gates**, `gate_pass = true`, `d_checked_at` 2026-09-26
> 18:57:48.822115Z), que teve auditoria independente e `EXPLAIN (COSTS OFF)`.
> Artefato **exatamente executado**: blob
> `3fc30f42604d7b967f066ded46d13b458f522bd9` · md5
> `56e520b0d75cfbb19f1ad868b48284ac` · 55.544 B · 907 LF · 0 CR,
> **publicado antes da execução** em `a446797d…`. Depois o arquivo recebeu
> **só comentários** (token stream executável idêntico). A v4.1 é fail-closed
> e **deliberadamente não idempotente**: `DROP … RESTRICT` sem `IF EXISTS`;
> identidade nova e função de token provadas por estrutura (dependência
> `pg_proc` = exatamente a função resolvida pela assinatura) e por texto
> canonicalizado independente de `search_path`; prova S4 (α/β coexistem,
> γ rejeitada por `uq_cvir_row_identity`) em `SAVEPOINT` desfeito; prova de
> resíduo zero + topologia terminal antes do `COMMIT`.
>
> **POSTCHECK LIVE independente (29/29, 2026-09-26 19:01:39Z):**
> - `uq_cvir_job_card_type_no_printing` e `uq_cvir_job_card_type_printing`
>   **ausentes** (OIDs 152493/152494 inexistentes);
> - `uq_cvir_row_identity` (OID 192899) preservada: unique/valid/ready/live,
>   5/5 chaves, definição/predicado/expressões exatos, 0 constraints,
>   dependência `pg_proc` = `{internal.axis_identity_token(jsonb,text)}` `n`;
>   função e fronteira de segurança (`internal` sem USAGE para
>   authenticated/anon) preservadas;
> - **8** índices, 0 não saudáveis; UNIQUE exatamente
>   `{catalog_variant_import_row_pkey, uq_cvir_row_identity}`; PK e 6 `ix_*`
>   exatos;
> - staging 26.127 rows, `max(updated_at)` inalterado (nenhuma row
>   persistida/alterada) · jobs 145 (63/71/8/3, 0 em voo, `max(updated_at)`
>   inalterado) · `operational_missing_key` 0 · duplicidade 0 · vt NULL 1.755
>   / VALID 0;
> - resíduo S4 **zero** (IDs, marcador `2216-S4`, EC sentinela);
> - owner/RLS/ACL/policy e guard 2214 preservados; zero sessão, lock ou
>   transação residual; `session_replication_role = origin`.
>
> **Ledger `2216` = 0**: lacuna de rastreabilidade (o MCP não escreve no
> ledger), **não** ausência de execução; não reconciliar manualmente.
>
> **Efeito:** `uq_cvir_row_identity` é a **única** identidade única do
> staging (além da PK). Com `2215` + `2216`, o eixo Edition Context é
> fisicamente expressivo em `card_variant` **e** no staging. Isso **não**
> autoriza importação/revisão: **FREEZE ATIVO** até o UNFREEZE formal após o
> Batch 12.
>
> **Batch 11: EXECUÇÃO CONCLUÍDA; closeout documental registrado.**
> **Próximo: Batch 12 / `2830`** — ver a seção do Batch 12.

> ✅ **`2215` v1.1 `EXECUTED / LIVE VALIDATED / CLOSED` em 2026-09-26**
> (`BATCH11-2215-LIVE-VALIDATION-CLOSEOUT-01`). Executada **1x** via
> **MCP `execute_sql`** (retorno `[]`), logo após o JIT LIVE PRECHECK
> read-only (`2215_live_precheck_v1`, **16/16 gates**, `gate_pass = true`,
> `d_checked_at` 2026-09-26 01:40:48Z). Artefato **exatamente executado**:
> blob `426b35557be77eeec7a4cddd8c63e3fafea070f1` · md5
> `7fd1ba485a2a0a3e8f8fce9bb1e320a2`, **publicado antes da execução** em
> `e375c886…`. Depois o arquivo recebeu **só comentários** (token stream
> executável idêntico). A v1.1 é fail-closed e **deliberadamente não
> idempotente**: `DROP … RESTRICT` sem `IF EXISTS`, pré-condição exata e
> prova terminal por topologia.
>
> **POSTCHECK LIVE** (confirmado de novo por leitura independente em
> 2026-09-26 02:17Z):
> - as duas antigas de `card_variant` estão **ausentes**;
> - `uq_card_variant_identity` está preservada: índice OID 221012 +
>   constraint OID 221013 `u`, validada, imediata, `NULLS NOT DISTINCT`,
>   4 chaves em ordem;
> - **9** índices, 0 não saudáveis; conjunto UNIQUE exatamente
>   `{card_variant_pkey, uq_card_variant_card_order, uq_card_variant_id_card,
>   uq_card_variant_identity, uq_card_variant_one_default_per_card}`;
>   ortogonais exatas;
> - 24.893 · EC 0 · dup 0/0 · nenhuma row alterada · jobs em voo 0 · zero
>   lock ou transação residual · writer e confirm preservados.
>
> **Ledger `2215` = 0**: é rastreabilidade (o MCP não escreve no ledger), não
> reconciliar manualmente.
>
> **Efeito:** a identidade física de `card_variant` tem agora **uma única
> autoridade** (`uq_card_variant_identity`), e o eixo Edition Context passou a
> ser fisicamente expressivo. Isso **não** autoriza importação ou revisão:
> **FREEZE ATIVO** até o UNFREEZE (Batch 12, após `2216` e `2830`).
>
> ~~**Batch 11 segue ABERTO.** A `2216` (identidades antigas do **staging**)
> é passo separado: `NÃO EXECUTADA / NÃO AUTORIZADA`, com READINESS a iniciar.~~
> *(superado: `2216` executada em 2026-09-26 — ver bloco acima.)*

| Ordem | Artefato |
|---|---|
| 1 | `2215` · `DROP` das 2 antigas de `card_variant` · ✅ EXECUTED / LIVE VALIDATED / CLOSED / PUBLISHED (2026-09-26) |
| 2 | `2216` · `DROP` das 2 antigas de staging · ✅ EXECUTED / LIVE VALIDATED / CLOSED (2026-09-26) |

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

> **ESTADO CORRENTE (2026-10-04, `BATCH12-POST-ACL-SVE-RETRY-LIVE-CLOSEOUT-01`):** **SVE RETRY = PASS** — retry único do canary SVE (1 clique de Fabrício; ACT PRE `2026-10-04 20:42:58.550978+00`), job `dcef3bd2-95f5-46de-894c-3dd125f185c9` **STAGED**, 112/112 válidas, 0 falhas; EC non-null **48 = 32 Player Rewards (`52447b63…`) + 16 Professor Program (`edea26c7…`)**, 64 sem eixo; MATCHED/SKIPPED 64 · NEW/PENDING 48; 112 identidades distintas; P1–P14 PASS; `2835` 12/12; L3 limpo. **Edition Context em importação real = PROVADO.** Contenção: jobs 146 → 147, staging 26.127 → 26.239, `card_variant` 24.893 → 24.893 (EC 0, zero drift) — `harness/LIVE-CANARY-SVE-RETRY-PASS-RECORD.md`. Sequência causal preservada: **primeiro canary SVE = STOP / FAILED (histórico, não reclassificado)** → **ACL blocker CLOSED (`2235` PASS)** → **retry PASS**. Staging **NÃO** confirmado; `2831`/`2213` **NÃO** executadas nem liberadas. **NEXT = auditar/publicar este closeout → só depois definir formalmente o próximo gate de rollout.**

> **ESTADO ANTERIOR — SUPERSEDED (2026-10-04, `BATCH12-POST-UNFREEZE-CANARY-ACL-LIVE-CLOSEOUT-01`; retry SVE já PASS, ver acima):** **ACL correction `2235` = APPLIED / PASS** (LIVE, ledger `20261004182941`, auditoria independente PASS) · **`2835` = PASS (`gate_pass = true`, 12/12)** · **ACL blocker = CLOSED** — `service_role` agora tem EXECUTE em `internal.axis_identity_token`; função, índice e guards inalterados; zero drift de dados (`harness/LIVE-ACL-2235-APPLY-RECORD.md`). O **primeiro canary SVE continua STOP / FAILED** (job `3ec9c551…`, `harness/LIVE-CANARY-SVE-STOP-RECORD.md`); o eixo 3 numa importação real **ainda não está provado** após a correção. Canary **não** retentado; `2831`/`2213` **não** executadas. **NEXT = AUDITAR E PREPARAR O RETRY ÚNICO DO CANARY SVE** (PRE novo → retry com mandato próprio → POSTCHECK completo → só então avaliar `2831`/`2213`).

> **ESTADO ANTERIOR — SUPERSEDED (2026-10-04, `BATCH12-POST-UNFREEZE-CANARY-ACL-CORRECTION-01`; 2235 já aplicada, ver acima):** **CANARY REAL PÓS-UNFREEZE (SVE) = STOP** — job `3ec9c551-b91f-43df-b360-60d796e47623` FAILED com `permission denied for function axis_identity_token`: o writer real (`service_role`, Edge `import-card-variants`) não tem EXECUTE na função do índice `uq_cvir_row_identity` (ACL da 2210 só concede a `authenticated`). Zero staging parcial; zero drift em `card_variant`; job preservado — `harness/LIVE-CANARY-SVE-STOP-RECORD.md`. Correção proposta, **não aplicada**: `2235_grant_axis_identity_token_service_role.sql` + regression gate `2835_validate_staging_writer_acl.sql`. **NEXT = auditar 2235 → aplicar (mandato próprio) → 2835 `gate_pass = true` → só então retry do canary SVE.** `2831`/`2213` não executadas.

> **ESTADO ANTERIOR (2026-10-04, `BATCH12-FORMAL-UNFREEZE-CLOSEOUT-01`):** Fabrício autorizou formalmente o UNFREEZE ("Autorizo formalmente o UNFREEZE.", sobre o HEAD `1c10ef23`) — `harness/UNFREEZE-AUTHORIZATION-RECORD.md`.
> **A, B, C, D CLOSED · E1, E2, E3 CLOSED · E4 SATISFIED · BATCH 12 / `2830` CLOSED · FREEZE do `EDITION-CONTEXT-AXIS` ENCERRADO · UNFREEZE FORMALMENTE AUTORIZADO / COMPLETED.**
> Nenhum SQL, LIVE, importação ou canary foi executado neste closeout; a compatibilidade do eixo 3 com importação real continua não provada.
> **NEXT = CANARY REAL PÓS-UNFREEZE** (mandato próprio). `2831` → `2213` só depois do canary aprovado. Os blocos abaixo são histórico.

> **ESTADO VIGENTE (2026-10-01, `BATCH12-E15-FINAL-LIVE-EVIDENCE-CLOSEOUT-01`):**
> `2830` **135/135 automáticos** — último lote L13/E15 executado uma única vez
> no LIVE, **PASS** (`H283P` `pass=5/5`, casos 5.1/5.2/5.3/5.6/5.7; evidência
> `E15-LIVE-EVIDENCE-02-20261001T002021Z.zip` md5 `cfdf7e14a1583299855a4ef95d5de10d`;
> `harness/LIVE-L13-E15-EXECUTION-RECORD.md`), com auditoria independente PASS.
> **Batch 12 — harness automático CLOSED; Batch 12 global OPEN.** FREEZE **ATIVO**: o UNFREEZE
> (ordem 3 abaixo) continua dependendo do gate completo desta seção e de
> mandato próprio. O texto abaixo é o histórico da especificação.
>
> **A2 / P9(b) — sucessora v7.2 (2026-10-03, `BATCH12-PHASE6-A2-P9B-V72-FORMALIZATION-01`):**
> `2830-V7.2-SUCCESSOR-A2-P9B.md` é delta normativo sobre a v7.0 (que permanece imutável),
> limitado a P9(b), R-P9 e ao componente de performance de A2. **P9(b) v7.0 e A2 v7.0 =
> NOT SATISFIED AS WRITTEN** (permanente) · **P9(b)′ v7.2 = CLOSED** (gate de evidência sem
> nova execução; BR-1 e BR-2 CLOSED) · **P9(a) CLOSED** (2026-10-03, LIVE heavy: L3 PASS + 4 EXPLAIN
> (COSTS OFF) VALID / REGISTERED; auditoria independente PASS — `harness/LIVE-P9A-HEAVY-EXECUTION-RECORD.md`)
> · **A2′ CLOSED** · **FASE 6 CLOSED** · **E1 OPEN** · E3 não executado · E4 OPEN · FREEZE ATIVO; UNFREEZE não autorizado.
>
> **P14 / D4 / E2 — closeout (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`):** nova captura LIVE da P14(a)
> com o mesmo instrumento pinado (`2738566c…`): L3 PASS, `PASS_EXACT` 31/31 contra o CN1, auditoria independente PASS
> (`harness/LIVE-P14A-EXECUTION-RECORD.md`). **P14(a) CLOSED · P14(e) CLOSED · D4 CLOSED · D1/D2/D3 CLOSED / CONTRACTUALLY
> ACCEPTED · E2 CLOSED** · **E1 CLOSED** (A/B/C/D CLOSED e registrados em EXECUTION-BATCHES, HANDOFF v1.21 e log) · **E3 não executado** ·
> **E4 OPEN** · FREEZE ATIVO; UNFREEZE não autorizado. *(Próxima frente então: E3 JIT — concluído em 2026-10-04, ver abaixo.)*
>
> **E3 — closeout (2026-10-04, `BATCH12-E3-INDEPENDENT-CLOSEOUT-01`):** E3 JIT em 4 chamadas read-only — S1 L1 PASS · S2 L3 inicial PASS ·
> S3 E00 PASS por adjudicação independente (24/24, `gate_pass`, FREEZE-CANON íntegro, `d_canon_diff = []`, `jobs_in_flight = 0`; `action_log`
> 1352 → 1354 = NON-BLOCKING / OUTSIDE FREEZE-CANON) · S4 L3 final PASS; auditoria independente PASS — `harness/LIVE-E3-JIT-EXECUTION-RECORD.md`; evidência `harness/evidence/E3-JIT-FINAL-PRECHECK-2026-10-04/` (18/18 + 24/24).
> **E1 CLOSED · E2 CLOSED · E3 CLOSED** · FREEZE ATIVO; UNFREEZE não autorizado. **Próximo: decisão formal de UNFREEZE por Fabrício**
> (é o que a 2830 chama de critério **E4** — critério de autorização, não work item).
>
> **6.1 — sucessora v7.3 (2026-10-03, `BATCH12-PHASE6-6.1-V73-FORMALIZATION-01`):** `2830-V7.3-SUCCESSOR-6.1.md`,
> delta restrito a 6.1 e ao componente de D5. **6.1 v7.0 = NOT SATISFIED AS WRITTEN** (permanente) ·
> **6.1′ v7.3 = CLOSED** (evidência já versionada do P9A-03/P9A-00; sem nova execução) · **6.2 OPEN** ·
> **D5 OPEN/PARTIAL** (aguarda 6.2). Não prova redundância nem autoriza remover `ix_card_variant_card_id`.
>
> **6.2 — decisão (2026-10-03, `BATCH12-PHASE6-6.2-DECISION-MAINTAIN-01`):** Fabrício decidiu **MANTER
> `ix_card_variant_card_id`** com a evidência já registrada (P9A-04 e P9A-00), sem nova execução.
> **6.2 = CLOSED** · **D5′ = CLOSED** (6.1′ + 6.2). A v7.3 não foi alterada.

### Gate global — estado vigente (2026-10-01, reconciliação final do gate global do Batch 12)

Rodada só documental. Nenhum SQL foi executado, nenhum teste foi executado e não houve acesso ao LIVE. Nenhuma evidência original foi alterada: a evidência histórica PG17 foi preservada no repositório por cópia byte a byte (`harness/evidence/PG17-2026-09-28/`). SQL, geradores, manifesto do harness e contrato ficaram inalterados. Baseline HEAD `249bc283`. Critérios: `2830` v7.0, *CRITÉRIOS DE ACEITE* A–E (inalterados).

**Decisões homologadas preservadas (não reabrir):**

- **Placar automático:** 130/135 reconhecidos antes do E15; E15 FINAL LIVE 5/5 PASS ⇒ **135/135 = CLOSED** (critério B). Não se recalcula cobertura nem se exige replay.
- **E12/E13 (L10/L11):** **25/25 HOMOLOGADOS na réplica PostgreSQL 17 representativa** (28/09), não executados no LIVE e sem necessidade de repetição. E12 14/14 (`H2830_ROLLBACK_PASS`, CONTEXT 712, `elapsed_ms=402`, E99 `d_diff=[]`/`d_canon_diff=[]`); E13 11/11 (CONTEXT 960, `elapsed_ms=78`, E99 idem, E98 PASS). Ressalvas ambientais conhecidas e aceitas, sem conversão em PASS: `catalog_admin_action_log` fora do export = `NOT_EXECUTED_LOCAL`; `g_evt_all_adjudicated=false` admitido como limitação da réplica. Evidência canônica: `harness/evidence/PG17-2026-09-28/RELATORIO-EVIDENCIAS.md` (+ `MANIFEST.md5` e `raw/`; origem: `C:\b12-pg17`, 28/09).
- **Parity / P9B de 28/09 (réplica):** Parity **PASS** (fingerprint `4f035e129221d0647259e9083599035e`, live = local, gates P1–P8); P9B M1/M2/M3 **PASS no escopo local** (212,2 / 722,6 / 47,7 ms). **P9B LOCAL PASS ≠ A2/P9(b) global CLOSED** (ver matriz). Evidência: mesmo relatório `harness/evidence/PG17-2026-09-28/`.
- **2234: EXECUTADA / VALIDADA no LIVE** (S-1 CLOSED). 1ª submissão: `42601`, rollback integral; correção `ded269f`; 2ª submissão: success. Migration `20260928023754` `2234_harden_search_path_edition_context_write_surface`, `created_by` = conta de Fabrício, 1 statement, md5 `991d77fdd553da1baf4a8c389267f443` (= arquivo publicado). Estado: 4 funções com `search_path=""`, SECURITY INVOKER; md5 de `prosrc`: `set_updated_at()` `98a97559965c2e0ff884d95155ab5d3a`, `validate_card_variant_game_consistency()` `c1fe17587dfb3b0f6d7d5d690ca13636`, `normalize_catalog_variant_import_job()` `c01adb02245bd5a305e8f8987a30f1c1`, `normalize_catalog_variant_import_row()` `7ae9bd52e030b13c3a241debda491a99`. O cabeçalho "PROPOSTA — NÃO EXECUTADA" dentro do `.sql` é **preservado de propósito**: o arquivo é, byte a byte, o statement executado (alterá-lo quebraria o md5).

**Decisão D-1 — CLOSED / DECIDIDA (2026-10-01, `BATCH12-PHASE6-D1-CN1-DECISION-AND-P14-READINESS-01`, baseline `dd96e8ff`; rodada sem SQL, sem LIVE, sem provisionamento):**

- Fabrício aprovou **CN-1 / I-L** como ambiente isolado oficial: **Supabase local via CLI + Docker**, sem custo monetário (`2830-V7.1-PROPOSAL-ADMIN-CONCURRENCY.md`, canal CN-1; `harness/P5-TRANSVERSAL-DECISIONS-AND-D1.md` §3.3, alternativa I-L).
- **Escopo:** P14a, P14b, P14c, K2, K1 e K8b. **Fora do escopo:** P9b/A2, que continua frente separada, OPEN e dependente de alteração formal da especificação (linha P9b/A2 abaixo).
- **Não reabrir** a comparação com projeto Supabase Free, branch pago, PostgreSQL puro ou outras arquiteturas: a tecnologia está decidida.
- A réplica PG17 de 28/09 continua **homologada no escopo já executado** (Parity, P9B local, E12/E13). Não é descartada nem rebaixada; é ativo reutilizável da montagem do CN-1 (imagem `supabase/postgres:17.6.1.147`, fingerprint de paridade como base adaptável).
- **Fonte estrutural do CN1-2 = S-A (decidida no mesmo marco, `…-CLOSEOUT-01`):** dump estrutural de 28/09 como base, completado **somente** com as definições canônicas do repositório para objetos faltantes (ex.: `public.admin_user`, `public.catalog_admin_action_log`). Nenhuma definição canônica é presumida equivalente ao LIVE antes da P14a, que é a prova final da equivalência estrutural; qualquer divergência na P14a = STOP. S-B (novo dump do LIVE) não é usada neste momento.
- A decisão **não** demonstra P14. O ambiente ainda não foi provisionado; P14a/b/c não foram executados; K1/K2/K8b continuam **BLOCKED** até a homologação P14 no CN-1. P14 continua obrigatório integralmente (2830 P14 a–e).

**Matriz do gate global** (CLOSED · PARTIAL · OPEN · BLOCKED):

| Item | Requisito literal (2830 v7.0) | Evidência existente | Estado | Gap real / menor ação |
|---|---|---|---|---|
| **D6 (C1)** | `git cat-file` dos blobs `426b3555…` (2215) e `3fc30f42…` (2216); hash confere; `PRE_NEW_IDENTITY_INDEX_INVALID`, `PRE_NEW_IDENTITY_CONSTRAINT_INVALID`, `OPERATIONAL_NOT_RESOLVED` antes do 1º DROP | Blobs **exatamente executados**, lidos do git: **2215** `426b35557be77eeec7a4cddd8c63e3fafea070f1` (16.467 B; md5 `7fd1ba48…`, já registrado no Batch 11) e **2216** `3fc30f42604d7b967f066ded46d13b458f522bd9` (55.544 B; md5 `56e520b0…`, idem). 2215: `PRE_NEW_IDENTITY_INDEX_INVALID` na l. 113 e `PRE_NEW_IDENTITY_CONSTRAINT_INVALID` na l. 123 (`RAISE EXCEPTION` em `DO $pre2215$`), antes do 1º `DROP INDEX` executável, na l. 165. 2216: `OPERATIONAL_NOT_RESOLVED` na l. 345 (`RAISE EXCEPTION` em `DO $boundary2216$`), antes do 1º `DROP INDEX` executável, na l. 366. Ocorrências de `DROP` em comentários não contam como statement. Consequência LIVE comprovada pelos POSTCHECKs do Batch 11 | **CLOSED** (2026-10-03, `BATCH12-PHASE6-C1-C2-C3-DOCUMENTAL-CLOSEOUT-01`) | — |
| **D7 (C2)** | predicado operacional no blob da 2216 + SELECT no LIVE: histórico VALID sem chave > 0 e identidades antigas ausentes | **Predicado** (blob `3fc30f42…`, l. 336–345): `OPERATIONAL_NOT_RESOLVED` conta job em `RECEIVED`/`PROCESSING`/`STAGED`/`CONFIRMING` ∧ `persistence_status = PENDING` ∧ `validation_status = VALID` ∧ `edition_context_profile_id` ausente. **Histórico VALID sem chave > 0:** o E00 LIVE (`2830H_E00_precheck_inventory.sql`, `cancelled_without_key`) mede por SELECT job `CANCELLED` ∧ chave ausente ∧ `VALID` ∧ `PENDING`; resultado LIVE registrado = **415** (E00 de 2026-10-01, `d_canon_diff = []`). `CANCELLED` é terminal e não operacional (2830 v7.0, V14). Logo 415 rows históricas VALID sem chave ⇒ histórico VALID sem chave > 0. **Identidades antigas ausentes:** POSTCHECK LIVE independente da 2216 (29/29, 2026-09-26 19:01:39Z, Batch 11): `uq_cvir_job_card_type_no_printing` e `uq_cvir_job_card_type_printing` ausentes, OIDs 152493/152494 inexistentes; o E02 (D3 PASS) é só corroboração. *Premissa histórica superada: a matriz dizia que a contagem LIVE não estava registrada; ela está, pela cadeia acima, e nenhum SELECT dedicado é necessário.* | **CLOSED** (2026-10-03, `BATCH12-PHASE6-C1-C2-C3-DOCUMENTAL-CLOSEOUT-01`) | — |
| **D8 (C3)** | SELECT no LIVE: 415 CANCELLED VALID+PENDING sem chave, `max(updated_at)` do staging < 2026-09-26, identidades antigas ausentes | E00 LIVE de 2026-10-01 (`d_canon_diff = []`; ZIP `cfdf7e14…`, `S3_E00.json`): `cancelled_without_key.valid_pending = 415` e `staging_max_upd_utc = 2026-09-20T19:57:04.771758Z`, anterior à execução da 2216 (2026-09-26). Identidades antigas do staging ausentes pelo POSTCHECK LIVE independente da 2216 (29/29, 2026-09-26 19:01:39Z, Batch 11) | **CLOSED** (2026-10-03, `BATCH12-PHASE6-C1-C2-C3-DOCUMENTAL-CLOSEOUT-01`) | — |
| **K1 / D1** | P14 (b2), conexões persistentes, prova de canal (P14c), corrida benigna com evidência de lock | CN-1 `CN1-6-K1`: 34 PASS / 0 STOP, VERDICT `K1 = PASS` (evidência primária em `harness/evidence/CN1-2026-10-02/`) | **CLOSED / CONTRACTUALLY ACCEPTED** (2026-10-04) — EXECUTION PASS + D4 CLOSED; não reexecutado | — *(texto anterior: não reexecutar; a aceitação dependia de D4 (P14(a)), porque a 2830 v7.0 faz de P14(a)+P14(c) condição de validade de D1–D3)* |
| **K2 / D2** | P14, identidade admin REAL via HTTP, K2.a–K2.e (inclui K3-B/K4-B); obrigatório para o UNFREEZE | CN-1 `CN1-6-K2-CORRECTION-02`: 42 PASS / 0 STOP, VERDICT `K2 = PASS` (K2.a–K2.e via HTTP/JWT real; `action_log=5`) (idem) | **CLOSED / CONTRACTUALLY ACCEPTED** (2026-10-04) — EXECUTION PASS + D4 CLOSED; não reexecutado | — |
| **K8b / D3** | P14 (b2/c), três sessões, A bloqueia X, `pg_blocking_pids = {A}`, NOWAIT, sem `40P01`, ROLLBACK integral | CN-1 `CN1-6-K8B-CORRECTION-04`: RESULT bruto = **STOP** por V5 (37 PASS / 1 STOP), preservado sem alteração. Adjudicação mecânica posterior (gate `P7d_k8b_pass_adjudicated` + `CN1-6-K1/07d_k8b_adjudication.txt`): V5 = falso positivo (`POSTGRES_PASSWORD` = literal local `postgres`; anon/JWT = 0). Execução comportamental (K8B-1…K8B-12) = PASS (idem, §5) | **CLOSED / CONTRACTUALLY ACCEPTED** (2026-10-04) — execução comportamental PASS + D4 CLOSED; não reexecutado. O RESULT bruto continua **STOP por V5** (falso positivo adjudicado mecanicamente) e não é reescrito como PASS | — |
| **6.1** | "EXPLAIN de busca por card_id usa uq_card_variant_identity (prefixo)" | P9A-03 registrado (`17857efb`): `Index Scan using ix_card_variant_card_id` | **6.1 v7.0: NOT SATISFIED AS WRITTEN** (permanente; NÃO DEMONSTRADO) · **6.1′ v7.3: CLOSED** (2026-10-03) | *2026-10-03: caminho (B) adotado — `2830-V7.3-SUCCESSOR-6.1.md` (6.1′: acesso indexado com `Index Cond` em `card_id` + integridade estrutural de `uq_card_variant_identity`, sem exigir a escolha do planner); LIVE-RERUN-NOT-JUSTIFIED; não prova redundância nem autoriza remover `ix_card_variant_card_id`; 6.2 inalterado.* Texto anterior: nenhuma decisão transforma esse resultado em PASS. Caminhos: (A) nova evidência em que o planner use `uq_card_variant_identity`, ou (B) alteração formal do requisito em versão sucessora da 2830. Nesta rodada: nenhum EXPLAIN novo, nenhuma remoção de índice |
| **6.2** | decisão sobre `ix_card_variant_card_id` com EXPLAIN real | P9A-04 registrado no LIVE (`LIVE-P9A-EXECUTION-RECORD.md` §5 e B.4, saída `45308e3a…`): `Index Scan using ix_card_variant_card_id`, `Index Cond` em `card_id`; inventário P9A-00 (a)=(b) | **CLOSED** (2026-10-03, `BATCH12-PHASE6-6.2-DECISION-MAINTAIN-01`) — decisão de Fabrício: **MANTER `ix_card_variant_card_id`** | Limites declarados: N ≤ 3, literais sintéticos, canal dono, sem contrafactual, sem medição de tempo, `idx_scan` acumulado, cardinalidade efetiva não medida. A decisão não prova indispensabilidade nem redundância e não autoriza remoção. Uma remoção futura exige novo mandato com evidência de performance adequada (`harness/INDEX-6.2-ADJUDICATION-READINESS.md` §9) |
| **D5′** | 6.1′ + 6.2, com EXPLAIN LIVE registrado, sem ANALYZE (2830 D5, l. 1174; v7.3 §5) | 6.1′ CLOSED pela v7.3; 6.2 CLOSED (MANTER) | **CLOSED** (2026-10-03) | — |
| **6.3** | `apply_migration` aceita UNIQUE NULLS NOT DISTINCT | 2840 v2.0, 7/7 PASS (Batch 10) | CLOSED | — |
| **P9a** | EXPLAIN (COSTS OFF) no LIVE das consultas pesadas | E00/E99 REGISTRADO (`17857efb`); seções B, M e 5.2/5.3/5.7 sem EXPLAIN LIVE registrado (BL-2). Lacuna de cobertura encontrada em 2026-10-03: o artefato tinha 3 statements (VREC, SMREC, DERIV-5X) e não cobria DERIV-D1X (`l13.d1x_select()`), base dos casos 5.3/5.7 do E15; corrigido pelo gerador canônico para **4 statements** (`BATCH12-PHASE6-P9A-D1X-COVERAGE-IMPLEMENTATION-01`; `2830H_P9A_heavy_sections_explain.sql` md5 `9ccc3c87…`, 63.644 B; b12_check R-9/R-10 exigem os 4). B, M e 5.2/5.3/5.7: PREPARED / NOT EXECUTED até a execução abaixo. **LIVE 2026-10-03 (`BATCH12-PHASE6-P9A-HEAVY-LIVE-EXECUTION-01`, HEAD `7cb7ebd4`, artefato `9ccc3c87…`):** L3 PASS + 4 EXPLAIN (COSTS OFF) VALID / REGISTERED — P9A-B (VREC, 46 linhas), P9A-M (SMREC, 11), P9A-5X (DERIV-5X, 789), P9A-D1X (DERIV-D1X, 430); auditoria independente PASS — `harness/LIVE-P9A-HEAVY-EXECUTION-RECORD.md`; evidência `harness/evidence/P9A-HEAVY-LIVE-2026-10-03/` (MANIFEST.md5 25/25). Seq Scans = PERFORMANCE FINDING — NON-BLOCKING FOR P9(a) | **CLOSED** (2026-10-03) | — |
| **P9b / A2** | A2 é **pré-requisito do harness**. P9(b): cada envelope executado integralmente 3×, 1 com cache frio, em ambiente isolado representativo (P14a), ANALYZE, pior caso ≤ 60 s, medição registrada antes do LIVE ("nenhum envelope vai ao LIVE sem a medição registrada"); R-P9: pior tempo no LIVE acima do medido no ambiente = FAIL de harness | **P9B LOCAL 28/09 = PASS (preservado)**: M1–M3 uma execução; E12 e E13 uma execução cada na réplica; B3H (E15) uma execução, `elapsed_ms=964`. Os envelopes já executados no LIVE rodaram sem a medição literal prévia, sob adaptações autorizadas (AD-2/D-2 = C). E15: LIVE 6.027 ms × B3H local 964 ms | **P9(b) v7.0 / A2 v7.0: NOT SATISFIED AS WRITTEN** (permanente) · **P9(b)′ v7.2: CLOSED** (2026-10-03) · **A2′: CLOSED** (2026-10-03; auditoria estática + P9(a) CLOSED + P9(b)′ CLOSED — `harness/LIVE-P9A-HEAVY-EXECUTION-RECORD.md`) | *2026-10-03: alteração formal publicada como `2830-V7.2-SUCCESSOR-A2-P9B.md` (P9(b)′ CLOSED por adjudicação sucessora, sem nova execução; R-P9/E15 = FINDING de calibração, sem fator k). P9a CLOSED em 2026-10-03 (linha P9a) ⇒ A2′ CLOSED.* Texto anterior: uma medição futura **não** torna retroativamente cumprida a condição temporal da v7.0 (medição antes do LIVE). O fechamento contratual de A2/E1 exige **alteração formal da especificação** (v7.1 ou sucessora) que adjudique explicitamente: as execuções LIVE feitas sob adaptações autorizadas, o requisito temporal do P9b, as evidências de performance existentes, a R-P9 (incluindo E15 LIVE 6.027 ms × local 964 ms) e o critério A2/E1. Medições adicionais podem ser exigidas como prova de performance, mas sozinhas não fecham o A2 v7.0. A v7.1 não é criada nem alterada nesta rodada |
| **P14a** | paridade por impressão digital (confirm, writer, guards 2214/2224, `axis_identity_token`, `resolve_variant_row_axes`, índices, constraints, triggers) | Parity 28/09 PASS (`4f035e12…`) no escopo E12/E13. CN-1 `CN1-4-P14A-LOCAL`: captura CN1 primária (31/31 itens, `agg_raw=6e2ef02e…`; VERDICT "paridade NAO decidida"). Captura LIVE e comparação LIVE×CN1 originais: **não recuperáveis** (2026-10-03; fato histórico preservado). **2026-10-04 — lacuna sanada por nova captura LIVE** com o mesmo instrumento pinado (`P14A_FINGERPRINT.sql` md5 `2738566c…`, submetido byte-idêntico; `BATCH12-P14A-LIVE-CAPTURE-EXECUTION-01`): L3 PASS; 34 linhas (31 ITEM / 1 CONTEXT / 2 AGGREGATE); comparação contra o CN1 (`P14A_CN1_OUTPUT.csv` `07cbe136…`) pelo comparador congelado `c1feb507…` = **`PASS_EXACT`**, rc 0, **31/31 EXACT**, contexto igual, `agg_raw`/`agg_lf` iguais; auditoria independente PASS — `harness/LIVE-P14A-EXECUTION-RECORD.md`; evidência `harness/evidence/P14A-LIVE-CAPTURE-2026-10-04/` (MANIFEST.md5 17/17) | **CLOSED** (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`) | — *(texto anterior: só o lado CN1 provado; reavaliação só com a evidência LIVE original, em mandato próprio)* |
| **P14b** | (b1) HTTP com admin real; (b2) conexões Postgres persistentes | CN-1 `CN1-5-P14BC-CORRECTION-02`: B1_1…B1_7 e B2_1…B2_5 PASS (evidência primária em `harness/evidence/CN1-2026-10-02/`) | **(b1) CLOSED · (b2) CLOSED** (2026-10-03) | — |
| **P14c** | prova de canal antes de K1/K8b (pid, txid, `idle in transaction`, `auth.uid()`, `is_admin()`) | idem: C1/C2, R1/R2 PASS | **CLOSED** (2026-10-03) | — |
| **P14d** | fixture sintética; ambiente descartado ao fim, descarte registrado | `P14D-RUN`: 35 PASS / 0 STOP, VERDICT `CN1 P14(d) = PASS` (idem) | **CLOSED** (2026-10-03) | — |
| **P14e** | evidência registrada: impressão digital LIVE × ambiente, prova de canal (c), script, saídas, `pg_locks`/`pg_stat_activity`/`pg_blocking_pids` nos pontos de espera | prova de canal, saídas, scripts SQL e `pg_locks`/`pg_stat_activity`/`pg_blocking_pids` nos pontos de espera preservados em `harness/evidence/CN1-2026-10-02/`; impressão digital do lado CN1 idem. **2026-10-04:** impressão digital LIVE, instrumento versionado e comparação LIVE × ambiente (`PASS_EXACT`) registrados em `harness/LIVE-P14A-EXECUTION-RECORD.md`; evidência `harness/evidence/P14A-LIVE-CAPTURE-2026-10-04/` (MANIFEST.md5 17/17). Prova componente a componente (7/7): `LIVE-P14A-EXECUTION-RECORD.md` §6 | **CLOSED** (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`) | — *(texto anterior: impressão digital só do lado CN1; mesma lacuna de P14(a))* |
| **D4** | paridade (P14a) e prova de canal (P14c) — condições de validade de D1–D3 | P14(c) CLOSED (2026-10-03) + P14(a) CLOSED (2026-10-04, `PASS_EXACT`) | **CLOSED** (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`) | — *(texto anterior: depende de P14a; mantinha D1–D3 em PARTIAL/OPEN)* |
| **A1, A3, A4, A5** | mandatos; precheck JIT; constantes; `lock_timeout` | cumpridos lote a lote (registros LIVE, B-5X/D1) | CLOSED | — |
| **B (135/135)** | todos os automáticos PASS, sem vácuo, resíduo zero | homologado | CLOSED | — |
| **Baseline de FREEZE** | inalterado entre o precheck e o UNFREEZE | E00 LIVE 2026-10-01T00:22:57Z: 24/24, `d_baseline_md5 5c329d5e…`; E99 00:29:50Z `d_diff=[]`. **E3 JIT 2026-10-04:** E00 24/24, `g_freeze_canonical_equal = true`, `d_canon_diff = []` (só `action_log` 1352 → 1354 no `d_baseline` amplo, fora do FREEZE-CANON) — `harness/LIVE-E3-JIT-EXECUTION-RECORD.md`; evidência `harness/evidence/E3-JIT-FINAL-PRECHECK-2026-10-04/` (18/18 + 24/24) | **CLOSED** (2026-10-04) | — *(texto anterior: PARTIAL; re-provar no precheck do mandato de UNFREEZE)* |
| **Zero jobs em voo** | E3 | E00 de 2026-10-01 conforme. **E3 JIT 2026-10-04:** `jobs_in_flight = 0` (145 = 63/71/8/3) | **CLOSED** (2026-10-04) | — *(texto anterior: PARTIAL)* |
| **Zero locks / sessões** | E3 | L3 2026-10-01T00:30:20Z limpa. **E3 JIT 2026-10-04:** L3 inicial e final limpas (`locks_on_scope = []`; 13/13 `client backend` `idle`, sem transação) | **CLOSED** (2026-10-04) | — *(texto anterior: PARTIAL; L3 imediatamente antes do UNFREEZE)* |
| **E1** | A, B, C e D integralmente satisfeitos e **registrados na documentação (EXECUTION-BATCHES, HANDOFF, log)** | **Reavaliação 2026-10-04 (`BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`):** **A** — A1, A3, A4, A5 CLOSED; A2 v7.0 NOT SATISFIED AS WRITTEN (permanente), sucedido por **A2′ CLOSED** (v7.2 + P9(a)). **B** — 135/135 CLOSED. **C** — C1/D6, C2/D7, C3/D8 CLOSED. **D** — D1/K1, D2/K2, D3/K8b CLOSED / CONTRACTUALLY ACCEPTED; D4 CLOSED (P14(a) + P14(c)); D5 v7.0 sucedido por **D5′ CLOSED** (6.1′ v7.3 + 6.2 MANTER); D6 (6.3) CLOSED. P14(a)–(e) CLOSED. Registro: EXECUTION-BATCHES, `docs/log.md` e **HANDOFF** (`docs/development/HANDOFF-2026-09-16.md` v1.21, §0-DUODECIES, `BATCH12-E1-HANDOFF-REGISTRATION-CLOSEOUT-01`) | **CLOSED** (2026-10-04) — A/B/C/D CLOSED + registrados em EXECUTION-BATCHES, HANDOFF e log; sem sucessora para E1 | — *(Texto anterior: P14(a)/(e), D1–D4 e E2 PARTIAL/OPEN; depois, em 2026-10-04, OPEN só pelo registro no HANDOFF — superado.)* |
| **E2** | K2 executado e aceito | K2 executado no CN-1: EXECUTION PASS (`harness/evidence/CN1-2026-10-02/`); D4 CLOSED (2026-10-04) ⇒ K2 contratualmente aceito | **CLOSED** (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`) | — *(texto anterior: executado, ainda não aceito contratualmente; a aceitação dependia de D4)* |
| **E3** | baseline inalterado, zero job em voo, zero lock residual | E3 JIT 2026-10-04: S1 L1 PASS · S2 L3 inicial PASS · S3 E00 PASS por adjudicação (FREEZE-CANON íntegro; `action_log` +2 NON-BLOCKING / OUTSIDE FREEZE-CANON) · S4 L3 final PASS; auditoria independente PASS — `harness/LIVE-E3-JIT-EXECUTION-RECORD.md`; evidência `harness/evidence/E3-JIT-FINAL-PRECHECK-2026-10-04/` (18/18 + 24/24) | **CLOSED** (2026-10-04, `BATCH12-E3-INDEPENDENT-CLOSEOUT-01`) | — *(texto anterior: snapshot de 2026-10-01; PARTIAL; re-provar no UNFREEZE)* |
| **E4** | mandato formal de UNFREEZE de Fabrício | Fabrício, 2026-10-04: "Autorizo formalmente o UNFREEZE." — `harness/UNFREEZE-AUTHORIZATION-RECORD.md` | **SATISFIED** (2026-10-04, `BATCH12-FORMAL-UNFREEZE-CLOSEOUT-01`) | critério de autorização, não work item *(texto anterior: NÃO SATISFEITO — aguardava a decisão formal; antes disso: OPEN; último passo)* |
| **E5** | requisitos da 2213 (L1–L9) **não** são condição | definição contratual | CLOSED | — |

**Estado (2026-10-04):** **Batch 12 / `2830` CLOSED**; E4 SATISFIED; **FREEZE ENCERRADO**; **UNFREEZE COMPLETED**; canary não executado. *(Texto anterior: harness automático CLOSED; Batch 12 global OPEN; FREEZE ATIVO; UNFREEZE não autorizado.)*

**Menor sequência restante até a elegibilidade ao UNFREEZE:**

1. **P14 / K1 / K2 / K8b** — *2026-10-03: CN-1 executado e descartado; evidência primária preservada em `harness/evidence/CN1-2026-10-02/`. P14(b1)/(b2)/(c)/(d) CLOSED; P14(a) e P14(e) PARTIAL/OPEN (captura LIVE e comparação LIVE×CN1 não recuperáveis), logo D4 PARTIAL/OPEN. K1/K2/K8b: EXECUTION PASS · CONTRACTUAL ACCEPTANCE OPEN (D1–D3 PARTIAL/OPEN), sem reexecução. Resta P14(a)/(e), só com a evidência LIVE original e mandato próprio.* *2026-10-04: **CONCLUÍDO** — nova captura LIVE com o mesmo instrumento pinado, `PASS_EXACT` 31/31 contra o CN1 (`harness/LIVE-P14A-EXECUTION-RECORD.md`); P14(a)/(e) CLOSED, D4 CLOSED, D1–D3 CLOSED / CONTRACTUALLY ACCEPTED, E2 CLOSED. E1 CLOSED após o registro no HANDOFF (item 7).* Texto anterior: D-1 decidida (CN-1/I-L). Montar o CN-1 (CN1-0 a CN1-6) e homologar P14a com a lista literal, P14b e P14c; depois K2, K1 e K8b.
2. **A2 / R-P9** — *2026-10-03: tratado formalmente pela v7.2 (`2830-V7.2-SUCCESSOR-A2-P9B.md`): P9(b)′ CLOSED; A2′ fecha com o P9a (item 6). 2026-10-03: A2′ CLOSED (item 6 concluído).* Texto anterior: tratamento formal em versão sucessora da 2830 (v7.1 ou sucessora), com mandato de especificação próprio; medições adicionais só como prova de performance.
3. **6.1** — *2026-10-03: alteração formal feita pela v7.3 (`2830-V7.3-SUCCESSOR-6.1.md`): 6.1′ CLOSED; 6.1 v7.0 NOT SATISFIED AS WRITTEN.* Texto anterior: nova evidência em que o planner use `uq_card_variant_identity`, ou alteração formal do requisito.
4. **6.2** — *2026-10-03: decisão de Fabrício registrada = **MANTER `ix_card_variant_card_id`** (`BATCH12-PHASE6-6.2-DECISION-MAINTAIN-01`); 6.2 CLOSED; D5′ CLOSED. Sem nova execução.* Texto anterior: decisão de Fabrício: MANTER, ADIAR ou REMOVER FUTURAMENTE.
5. **C1 / C2 / C3** — *2026-10-03: concluídos (`BATCH12-PHASE6-C1-C2-C3-DOCUMENTAL-CLOSEOUT-01`): C1/D6, C2/D7 e C3/D8 CLOSED com evidência existente, sem SQL e sem chamada LIVE. Com isso, **P9a é a única frente restante da Fase 6**.* Texto anterior: registro formal do C1 (local); SELECT LIVE do C2; adjudicação documental do C3.
6. **P9a** — **CONCLUÍDO (2026-10-03)**: EXPLAIN (COSTS OFF) LIVE das seções B, M e 5.2/5.3/5.7 (P9A-B, P9A-M, P9A-5X, P9A-D1X), L3 PASS, auditoria independente PASS — `harness/LIVE-P9A-HEAVY-EXECUTION-RECORD.md`; evidência `harness/evidence/P9A-HEAVY-LIVE-2026-10-03/`. P9(a) CLOSED ⇒ A2′ CLOSED ⇒ **FASE 6 — CLOSED**.
7. **Registro de E1 no HANDOFF** — **CONCLUÍDO (2026-10-04)**, `BATCH12-E1-HANDOFF-REGISTRATION-CLOSEOUT-01`: `HANDOFF-2026-09-16.md` v1.21 (§0-DUODECIES) registra A/B/C/D CLOSED; com isso **E1 CLOSED**.
8. **E3 JIT — precheck final do FREEZE** — **CONCLUÍDO (2026-10-04)**, `BATCH12-E3-INDEPENDENT-CLOSEOUT-01`: S1–S4 PASS (S3 por adjudicação), E3 CLOSED — `harness/LIVE-E3-JIT-EXECUTION-RECORD.md`. *(Texto anterior: próxima frente vigente, não executado.)*
9. **Decisão formal de UNFREEZE por Fabrício** — **CONCLUÍDO (2026-10-04)**, `BATCH12-FORMAL-UNFREEZE-CLOSEOUT-01`: "Autorizo formalmente o UNFREEZE." — E4 SATISFIED; FREEZE encerrado; Batch 12 / `2830` CLOSED (`harness/UNFREEZE-AUTHORIZATION-RECORD.md`). *(Texto anterior: próximo; nenhum UNFREEZE ocorrera.)*
10. **Canary real pós-UNFREEZE** — *2026-10-04, estado corrente (`BATCH12-POST-ACL-SVE-RETRY-LIVE-CLOSEOUT-01`):* **retry único SVE = PASS** (job `dcef3bd2…` STAGED, 112 rows, EC 48 = 32 + 16, P1–P14 PASS, zero drift em `card_variant`; `harness/LIVE-CANARY-SVE-RETRY-PASS-RECORD.md`); primeiro canary preservado como STOP; staging não confirmado; **NEXT = auditar/publicar o closeout → definir formalmente o próximo gate de rollout.** *(Estado anterior, SUPERSEDED:)* `2235` APPLIED / PASS e `2835` PASS 12/12 (`harness/LIVE-ACL-2235-APPLY-RECORD.md`); ACL blocker CLOSED; primeiro canary continua STOP; **NEXT = auditar e preparar o retry único do canary SVE** (mandato próprio). *(Texto anterior, SUPERSEDED:)* **EXECUTADO 2026-10-04 = STOP** (SVE, job `3ec9c551…` FAILED: ACL de `axis_identity_token` ausente para `service_role`; `harness/LIVE-CANARY-SVE-STOP-RECORD.md`). **NEXT:** auditar e aplicar `2235` (mandato próprio), `2835` `gate_pass = true`, depois retry do canary SVE com mandato próprio. *(Texto anterior: NEXT; mandato próprio; não executado. Prova a compatibilidade do eixo 3 com importação real.)*
   Depois do canary aprovado: `2831` → `2213` → Variant Display / roadmap vigente (`ROLLOUT-ORDER.md` etapa 18).

> **READINESS AUDIT concluída — NOT READY / BLOCKED**
> (`BATCH12-2830-READINESS-AUDIT-01`, 2026-09-26, SELECT-only). A `2830` v6.3
> era 100% comentário; só B e M tinham código (`2832`/`2833`, desenhados para
> antes da `2214`). Achados: contratos de erro divergentes do LIVE (S8, S9,
> S10, K3); K5–K7 sem objeto LIVE; D6–D8 não reexecutáveis; K1/K8 exigem
> duas sessões; falso PASS em V10, 5.4, 5.5 e nos triggers `DEFERRED`;
> V12/SM10 sem asserção.
>
> **ESPECIFICAÇÃO CORRIGIDA — `2830` v7.0** (`BATCH12-2830-SPEC-CORRECTION-01`,
> 2026-09-26, comment-only). Os 144 automáticos da v6.3 foram redistribuídos
> **um a um**: **134 AUTO · 3 HIST (D6–D8) · 2 MANUAL (K1, K2) · 5 `2213`
> (K5–K7, 5.4, 5.5)**. Novos: `5.7` (AUTO, exclusão dos 80
> PRICING_CONDITIONED) e `K8b` (MANUAL, duas sessões). O harness é definido
> como **teste transacional com rollback integral**, não SQL read-only
> (protocolo P1–P12 no próprio arquivo). O harness executável **não foi
> escrito**: `NÃO INICIADA / NÃO AUTORIZADA`.

| Ordem | Item |
|---|---|
| 1 | `2830` — harness da fundação (especificação v7.0: **135** automáticos + **3** evidências históricas; teste transacional com rollback integral) |
| 2 | Manuais obrigatórios antes do UNFREEZE — **nenhum dispensável**: `K1`, **`K2`** (identidade admin real, inclui K3-B/K4-B) e `K8b` (duas sessões, `ROLLBACK`) em **ambiente isolado com paridade provada** contra o LIVE; `6.1`/`6.2` (EXPLAIN); `6.3` já cumprido (`2840`). Nenhum `set_config` de claims no LIVE |
| 3 | **UNFREEZE** |

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

**Prosseguir se:** `2830` **135/135 automáticos** (sem PASS por vácuo) + **3/3 evidências históricas verificadas** + **6/6 manuais obrigatórios, inclusive `K2`**, com paridade do ambiente isolado provada + baseline de FREEZE inalterado + mandato formal de UNFREEZE. Critérios completos: seção *CRITÉRIOS DE ACEITE* da `2830` v7.0. Requisitos da `2213` (L1–L9) não entram no gate.

---

## Batch 13 — `2831` → `2213` / Legacy Decomposition · ✅ **CLOSED**

> **ESTADO (2026-10-07, `BATCH13-FINAL-CLOSEOUT-01`): CLOSED.** Registro de encerramento: `harness/BATCH13-FINAL-CLOSEOUT-RECORD.md` (critério A–K 11/11).

**Escopo:** decompor as 285 READY_UNCONDITIONED legadas (Finish + Edition Context) com o lineage reconciliado na mesma transação, incluindo os pré-requisitos semânticos `2236`, `2237`, `2831` v3.1 e `2213` v1.0.

| Artefato | Estado | Registro |
|---|---|---|
| `2236` | CLOSED / APPLIED / PASS | `harness/LIVE-2236-APPLY-RECORD.md` |
| `2237` v1.0 | ATTEMPTED / FAILED INTERNAL POST / ROLLED BACK / ZERO LIVE DELTA / SUPERSEDED | `harness/LIVE-2237-FAILED-ATTEMPT-RECORD.md` |
| `2237` v1.1 | CLOSED / APPLIED / PASS | `harness/LIVE-2237-V11-APPLY-RECORD.md` |
| `2831` v3.1 | SIMULATION PASS / ROLLED BACK / ZERO PERSISTENT DELTA / GATE A FINAL PASS | `harness/LIVE-2831-V31-SIMULATION-RECORD.md` |
| `2213` v1.0 | APPLIED / FINAL PASS | `harness/LIVE-2213-V10-APPLY-RECORD.md` |

**Sequência causal:**

1. A readiness de B-SEMANTIC encontrou 46/285 bloqueadas.
2. Adjudicação D1(a′)/D2/D3/D4.
3. `2236` aplicada (NO_PROFILE 33 → 0).
4. `2237` v1.0 falhou no POST interno e sofreu rollback.
5. `2237` v1.1 aplicada (FINISH NULL 2 → 0).
6. Genérico 274/285, resíduo 11 (6 Pikachu + 4 League + 1 Player Reward).
7. `2831` v3.1 SIMULATION PASS / Gate A FINAL PASS.
8. `2213` preparada e auditada.
9. `2213` aplicada.
10. POST definitivo 285/285 (CV `c14f6fdb…`) + 336/336 (lineage `a4b21ecd…`), zero drift fora do escopo.
11. Batch 13 CLOSED.

**Resultado:** READY_UNCONDITIONED residual **0**; `card_variant` 24.893; D1 HOLD-safe intacto (mapping `PIKACHU-TAIL` 0); forward-fixes intactos.

**Limites:** as 80 READY_PRICING_CONDITIONED (40 `STAFF_HOLO` + 40 `SET_LOGO_REVERSE`, EC 0) seguem **protegidas e fora do escopo** — `PRICING-CATALOG-VARIANT-RECONCILIATION-01`, etapa 19 do `ROLLOUT-ORDER.md`. Também não pertencem ao Batch 13: `VARIANT-DISPLAY-SEMANTICS-01`, `NEEDS_REVIEW` editorial, `CATALOG-HISTORICAL-BOOTSTRAP-03`, `CATALOG-VARIANT-DEFAULT-BACKFILL-01`, `BULK-04`/`05`/`06`, Collections UX e Frontend.

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

> **Atualização (2026-10-07, `BATCH13-FINAL-CLOSEOUT-01`).** Da dívida rotulada acima, o Batch 13 (CLOSED) fechou:
>
> - `2831`→`2213`: 285/285 decompostas;
> - as 12 composições de B: substituídas pela `2236`, D2;
> - `CAMPAIGN_PIKACHU_WORLD_2000`: trait criado pela `2236` e as 6 resolvidas pela camada histórica, sem mapping operacional.
>
> Continuam como dívida de frentes próprias:
>
> - as 80 `READY_PRICING_CONDITIONED`, bloqueadas por Pricing;
> - o frontend de exibição (`FRONTEND-DISPLAY-CONTRACT.md`), agora com a condição "depois da `2213`" satisfeita.
