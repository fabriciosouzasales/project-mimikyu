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

## Batch 9 — GUARD → WRITER: EXPAND → SWITCH → CONTRACT · **EM CURSO**

> **PARCIALMENTE EXECUTADO.** A **`2224` está `EXECUTED / LIVE VALIDATED /
> CLOSED`** (2026-09-22, `BATCH9-2224-CLOSEOUT-01`): blob executado
> `5bae844bc37022de3bb2ad34e52b5f8ac31da929`, publicado em `2fcd6231`,
> aplicada **direto no SQL Editor**, POSTCHECK read-only **20/20 GATEs ·
> GLOBAL PASS**, **zero drift** PRE→POST. **`2217`, `2218` e `2223` seguem
> **NÃO EXECUTADAS** — cada uma exige **readiness audit** e **mandato
> explícito de Fabrício**. Próximo estágio: **`2217` EXPAND**.
> FREEZE **ATIVO**.
>
> **`2224` no ledger = 0.** Diagnóstico de RASTREABILIDADE, **não** "não
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
| 2 | `2217` EXPAND · **próximo** | **sim** |
| 3 | `2218` SWITCH | **sim** |
| 4 | `2223` CONTRACT | **sim** |

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
