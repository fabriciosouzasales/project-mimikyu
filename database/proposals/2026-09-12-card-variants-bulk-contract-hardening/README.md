# Card Variants — Hardening do contrato bulk de importação de variantes

| Campo | Valor |
|---|---|
| **Mandato** | `BULK-CONTRACT-HARDENING-GATE-A-01` + `GATE-A-CORRECTION-01` + `GATE-A-EXECUTE-NOW-01` + `BULK-CONTRACT-HARDENING-CLOSEOUT-01` |
| **Data** | 2026-09-12 |
| **Status** | **CLOSED / VALIDATED** — Gate A executado e aprovado em 2026-09-12 |
| **Diagnóstico** | `CARD-VARIANTS-GLOBAL-RECONCILIATION — AUDIT-01` / `AUDIT-01-CORRECTION-01` |
| **Endurece** | `2144` `admin_decide_catalog_variant_import_row()` · `2145` `admin_confirm_catalog_variant_import()` |
| **Escopo** | Contrato de payload `UUID[]` e teto de lote. **Zero** alteração de regra de negócio. |
| **Desbloqueia** | **Bloco 1** da campanha (aprovar + confirmar as 519 rows `VALID` dos 4 jobs `STAGED`) |

---

## Fechamento — `BULK-CONTRACT-HARDENING-CLOSEOUT-01`

Gate A **executado, validado e aprovado** em 2026-09-12.

| Artefato | Estado | Onde vive agora |
|---|---|---|
| `2163` | **LIVE** — `CONFIRMADO EXECUTADO` | `database/migrations/2163_…` (canônica) + cópia histórica aqui |
| `2164` v1.1 | **LIVE** — `CONFIRMADO EXECUTADO` | `database/migrations/2164_…` (canônica) + cópia histórica aqui |
| `2822` v1.1 | **VALIDADO / PASS** | **somente aqui** — não é promovida (mesmo padrão de `6800`/`6810`/`6820`/`6821`/`6841`/`6842`) |

**`2163` — o que ficou LIVE**

- teto explícito de **10.000** ids por chamada (`c_max_row_ids`);
- `array_ndims` (dimensionalidade) e `cardinality` (elementos reais) no
  lugar do `array_length(...,1)` que subcontava;
- todos os guards novos rodam **antes** de qualquer `ANY()` ou `UPDATE` —
  zero acesso ao banco na validação de payload;
- ordem verificada no LIVE: `is_admin` < `array_ndims` < `cardinality` <
  teto < `ANY()`.

**`2164` v1.1 — o que ficou LIVE**

- teto efetivo de **1.000** rows por chamada (`c_max_rows`);
- `p_row_ids = NULL` **preservado**: continua significando "todas as rows
  elegíveis no instante da operação";
- **conjunto congelado** `v_effective_row_ids` — uma única leitura,
  `ORDER BY r.created_at, r.id`, `LIMIT c_max_rows + 1`;
- **TOCTOU eliminado**: o teto deixou de ser uma medição e passou a ser
  propriedade estrutural;
- o `LOOP` consome **exclusivamente** o conjunto congelado
  (`AND r.id = ANY(v_effective_row_ids)`); o padrão antigo
  `p_row_ids IS NULL OR r.id = ANY(p_row_ids)` está **ausente** do corpo LIVE.

**`2822` v1.1 — resultado da validação**

- **37 asserções PASS** em 4 Seções (`S1` 13 · `S2` 8 · `S3` 11 · `S4` 5),
  todas fail-closed;
- **zero fixture residual**: `HARNESS-2822` = 0 jobs;
- baseline preservado, medido antes e depois: `card_variant` **6.483** ·
  jobs `STAGED` **4** · `VALID`/`PENDING` **519** ·
  `NEEDS_REVIEW`/`PENDING` **505**.

---

## Por que esta frente existe

O `AUDIT-01` mediu o estado global de Card Variants no catálogo POKEMON e
encontrou **16,62 % de cobertura** (3.480 de 20.939 Cards ativas). Fechar
esse gap exige uma campanha operacional sobre ~174 Card Sets, e essa
campanha passa inteiramente por duas RPCs: `2144` (decidir rows) e `2145`
(confirmar rows).

O `AUDIT-01-CORRECTION-01` auditou o contrato `UUID[]` das duas e encontrou
gaps reais de **robustez de payload** e **controle de recurso**:

| Vetor | `2144` | `2145` |
|---|---|---|
| `NULL` | coberto ✅ | coberto (`p_job_id`); `p_row_ids` é opcional por desenho |
| Array vazio | coberto ✅ | **no-op silencioso** ❌ |
| **Multidimensional** | **não bloqueia** ❌ | **não bloqueia** ❌ |
| **Cardinality** | usa `array_length` (subconta) ❌ | **nenhuma** ❌ |
| **Teto** | **nenhum** ❌ | **nenhum** ❌ |

Prova do gap multidimensional, executada read-only em 2026-09-12 sobre um
array `2×3`:

```
array_ndims        = 2
array_length(m,1)  = 2     <- o que o guard da 2144 media
cardinality(m)     = 6     <- o que ANY() realmente varre
```

**Nenhum desses pontos é falha de autorização.** `public.is_admin()` é a
primeira instrução das duas funções, `search_path` está travado em `''` e
os grants estão corretos (`authenticated` + owner). Os gaps são de forma
de payload e de limite de lote.

### Por que agora, e não depois

Até aqui as duas funções só foram chamadas pela UI de revisão, onde o
tamanho do array é "quantas linhas o admin marcou na tela". A campanha
muda a natureza do uso: arrays montados programaticamente, fora da UI,
em lotes de centenas.

Três consequências concretas medidas no `AUDIT-01-CORRECTION-01`:

1. **`2144` perde seu único teto de fato.** Hoje o limite é a seleção
   humana. No Bloco 1 passa a ser "quantas rows `VALID` o job tem" — **408
   no SV5**.
2. **O gap multidimensional deixa de ser teórico.** Um array construído por
   script pode ser multidimensional por acidente de serialização; o guard
   atual **passa** e a função opera sobre mais ids do que mediu.
3. **`decidirLinhasVariantes()` não tem chunking.** Confirmado em
   `web/app/catalogo/importar-variantes/actions.ts` (linhas 228-241): envia
   o array **inteiro** em uma chamada. `confirmarImportacaoVariantes()`,
   ao contrário, usa `CONFIRM_CHUNK_SIZE = 50` (linhas 255-263, 318). É a
   única escrita administrativa do módulo **sem teto em lugar nenhum** —
   nem frontend, nem backend.

---

## Arquivos

| Arquivo | O quê | Estado |
|---|---|---|
| `2163_harden_admin_decide_catalog_variant_import_row_contract.sql` **v1.0** | Migration incremental sobre a `2144`. Adiciona `array_ndims`, `cardinality`, teto **10.000**. | **CONFIRMADO EXECUTADO / LIVE** (2026-09-12) · **promovida** para `database/migrations/` · cópia aqui é evidência histórica |
| `2164_harden_admin_confirm_catalog_variant_import_contract.sql` **v1.1** | Migration incremental sobre a `2145`. Adiciona `array_ndims`, rejeição de vazio, teto **1.000**, e o **conjunto efetivo congelado** que elimina o TOCTOU do caminho `NULL`. | **CONFIRMADO EXECUTADO / LIVE** (2026-09-12) · **promovida** para `database/migrations/` · cópia aqui é evidência histórica |
| `2822_validate_variant_import_bulk_contract.sql` **v1.1** | Harness de validação — 4 Seções, **todas fail-closed**, fixtures revertidas. | **VALIDADO / PASS** (2026-09-12) — 37 asserções, 4 Seções, zero resíduo · **não promovida**, permanece só aqui |

### Revisão `GATE-A-CORRECTION-01` — três blockers fechados

A auditoria direta dos artefatos encontrou três defeitos reais na v1.0. Os três eram meus, e os três estavam na `2164`/`2822` — a `2163` passou intocada.

| # | Blocker | Correção |
|---|---|---|
| **1** | **TOCTOU no teto do caminho `NULL`.** A v1.0 contava as rows elegíveis em uma instrução e o `LOOP` reabria o universo em **outra**. Em `READ COMMITTED` são snapshots distintos — a `2144` podia aprovar novas rows entre as duas e o `LOOP` processaria **mais** de 1.000. O teto era *verificado*, não *garantido*. | **Conjunto efetivo congelado** (`v_effective_row_ids`): uma única leitura materializada, `ORDER BY created_at, id`, `LIMIT c_max_rows + 1`; o `LOOP` passa a filtrar por `r.id = ANY(v_effective_row_ids)` em vez de reabrir o universo. O teto vira **propriedade estrutural**. |
| **2** | **Fixture impossível.** A v1.0 do `2822` exigia um Card Set POKEMON com ≥ 1.001 Cards ativas. O maior é **SWSHP, com 300** — `S3.FIXTURE` **sempre** teria abortado. | Fixture agora usa **uma única Card real**, repetida via `generate_series`. Legal porque o único índice único da tabela é **parcial**. |
| **3** | **`S1.11`/`S1.12` davam falso PASS.** `S1.11` usava `position('_TOO_MANY_ROWS')`, que casa com a **primeira** ocorrência (o teto do array explícito) — o guard do `NULL` podia estar ausente ou depois do `LOOP` e o teste passava. `S1.12` contava ocorrências de um fragmento repetido, o que não prova equivalência semântica. | `S1.11a–g` ancoram em **elementos exclusivos** do caminho `NULL` (`v_effective_row_ids`, `LIMIT c_max_rows + 1`, `cardinality(v_effective_row_ids) > c_max_rows`). `S1.12a–f` verificam os **três predicados literais** do snapshot, a ordenação determinística, o filtro por id do `LOOP` e a **ausência** do padrão antigo `p_row_ids IS NULL OR ...`. |

Além dos três, **`S1` e `S4` passaram a ser fail-closed** — antes apenas exibiam `PASS`/`FAIL`/`ATENCAO` e a execução podia continuar. Removi o `ATENCAO` do baseline de `card_variant`: divergência de baseline agora aborta, e o procedimento correto é **STOP / reauditar**, não suavizar a asserção.

**Numeração — prova de disponibilidade (2026-09-12):**

- Maior `2xxx` no repositório e no ledger `supabase_migrations.schema_migrations`: **`2162`** (`2162_normalize_card_set_release_order`). `2163` e `2164` **livres**, confirmados por glob em `database/**/` e por consulta ao ledger.
- Maior `28xx` de validação: **`2821`** (`2821_validate_cards_com_imagem_algum_idioma`). `2822` **livre**.
- Nenhum número existente foi reutilizado. `2144`/`2145` **não** são reescritas retroativamente — permanecem em `database/schema/` como as migrations de criação originais.

---

## Tetos — justificativa

Nenhum dos dois é número arbitrário.

| Função | Teto | Razão |
|---|---:|---|
| `2163` / `2144` | **10.000** | Mesmo teto de lote bulk já adotado pelo projeto: `c_max_batch_size = 10000` (Query `6115`) e `c_max_variant_ids = 10000` (Query `5079`). Não introduz constante nova. É 200× o lote da UI (50) e ~24× o maior lote plausível medido (408). A `2144` faz um `UPDATE` **set-based** — suporta esta ordem de grandeza com folga. |
| `2164` / `2145` | **1.000** | Uma ordem de grandeza **abaixo**, deliberadamente. A `2145` não faz varredura única: é um **loop** com `FOR UPDATE OF r` e escrita por linha via `internal.write_card_variant()`. O custo cresce linear em **tempo de lock**. 1.000 é 20× o `CONFIRM_CHUNK_SIZE` — cabe qualquer reuso legítimo — e mantém a janela de lock limitada. Precedente direto: a Query `5150` (`register_physical_cards_bulk`) adota exatamente 1.000 pelo mesmo motivo. |

---

## Contrato final de `p_row_ids = NULL` na `2164` — conjunto efetivo congelado

A semântica é **preservada**: `NULL` = "todas as rows elegíveis do job".
Não viramos `NULL` em array. Não mudamos o predicado de elegibilidade. O
que muda é **como o "instante" é definido**: uma única leitura,
materializada em variável local.

```sql
v_effective_row_ids UUID[];

IF p_row_ids IS NULL THEN
    v_effective_row_ids := ARRAY(
        SELECT r.id
        FROM public.catalog_variant_import_row r
        WHERE r.job_id = p_job_id
          AND r.persistence_status = 'PENDING'
          AND r.decision_status IN ('APPROVED', 'SKIPPED')
        ORDER BY r.created_at, r.id
        LIMIT c_max_rows + 1          -- 1001: só o suficiente p/ detectar estouro
    );

    IF cardinality(v_effective_row_ids) > c_max_rows THEN
        RAISE EXCEPTION '..._TOO_MANY_ROWS: ...';
    END IF;
ELSE
    v_effective_row_ids := p_row_ids;
END IF;
```

e o `LOOP` passa a filtrar por `r.id = ANY(v_effective_row_ids)` — mantendo
os guards defensivos de `persistence_status` e `decision_status`.

### Por que isso elimina o TOCTOU

| | v1.0 (defeituosa) | v1.1 |
|---|---|---|
| Medição do teto | `COUNT(*)` em uma instrução | `ARRAY(SELECT id … LIMIT 1001)` em uma instrução |
| Universo do `LOOP` | **reaberto** por `p_row_ids IS NULL OR …` em **outra** instrução | **o array congelado** |
| Garantia | teto *verificado* — em `READ COMMITTED`, a `2144` podia aprovar rows entre as duas leituras e o `LOOP` processaria > 1.000 | teto **estrutural** — o `LOOP` só enxerga ids que já estão no array, e `cardinality(array) ≤ 1000` foi verificado antes |

Três propriedades garantidas:

1. **Teto estrutural.** O `LOOP` processa no máximo 1.000 linhas,
   independentemente do que qualquer sessão concorrente faça depois do
   snapshot.
2. **Determinismo.** `ORDER BY created_at, id` — `created_at` sozinho **não
   é único** (rows do mesmo job nascem no mesmo `now()`); o desempate por
   `id` torna o `LIMIT` reproduzível.
3. **Custo limitado.** `LIMIT c_max_rows + 1` lê no máximo 1.001 ids — o
   suficiente para distinguir "≤ 1000" de "> 1000" sem varrer um job grande
   só para descobrir que ele excede o teto.

### Semântica preservada

- **`0` elegíveis → VÁLIDO**, caminho de primeira classe. `ARRAY(SELECT …)`
  devolve `'{}'` (nunca `NULL`); `cardinality = 0`; o `LOOP` não itera; os
  contadores e o status final são recalculados normalmente.
- **Rows que se tornarem elegíveis depois do snapshot** não entram nesta
  chamada. Permanecem `PENDING` e são processadas em chamada posterior.
  O recálculo final continua sendo feito **por agregação sobre o estado
  real da tabela** — não sobre o snapshot —, então um job com sobra
  elegível termina corretamente em `CONFIRMING`.
- **Guards defensivos mantidos no `LOOP`.** Se uma linha do snapshot deixar
  de ser elegível entre o congelamento e o `LOOP`, ela é simplesmente
  ignorada, nunca reprocessada.

O congelamento está posicionado **antes** do `UPDATE ... SET status =
'CONFIRMING'`: uma chamada rejeitada por teto não deixa nenhum rastro de
estado.

Provas: `S1.11a`–`S1.11g` e `S1.12a`–`S1.12f` (estáticas), `S3.8`/`S3.9`
(rejeição sem rastro) e `S3.11a`–`S3.11c` (o `LOOP` consome o conjunto
congelado; row criada depois do snapshot permanece `PENDING`).

Para `p_row_ids` explicitamente **vazio**, o contrato passa a ser
`RAISE EXCEPTION` — "nenhum id" não é a mesma coisa que "todos os ids", e a
função agora diz isso em voz alta em vez de virar um no-op que ainda move o
job para `CONFIRMING`.

### Compatibilidade com `confirmarImportacaoVariantes()`

Rastreado em `web/app/catalogo/importar-variantes/actions.ts`:

```ts
const rowIds = (eligibleRows ?? []).map((row) => row.id as string);
const batches = rowIds.length > 0 ? chunk(rowIds, CONFIRM_CHUNK_SIZE) : [null];
```

| Caminho do caller | Payload enviado | Sob a `2164` |
|---|---|---|
| Há rows elegíveis | lotes de **50** ids | ✅ 50 ≤ 1.000 |
| **Zero** rows elegíveis | **`[null]`** → `p_row_ids = NULL` | ✅ `NULL` + 0 elegíveis é válido |
| Array vazio | **nunca acontece** — o caller envia `null`, não `[]` | n/a |

**O caller web não precisa de nenhuma alteração.** O ramo `[null]` — que é
o que transiciona um job sem linhas a persistir — continua funcionando
exatamente como hoje. Provado por `S3.6`.

---

## Ordem exata dos guards

### `2163` (mandato: auth → NULL → dimensionalidade → cardinalidade/vazio → teto → demais → `ANY()`)

```
1. is_admin()                              [2144, preservado]
2. p_row_ids IS NULL         -> _MISSING_IDS
3. array_ndims <> 1          -> _INVALID_ARRAY_SHAPE      [NOVO]
4. cardinality = 0           -> _MISSING_IDS              [NOVO]
5. cardinality > 10000       -> _TOO_MANY_IDS             [NOVO]
6. decision_status inválido  -> _INVALID_STATUS           [2144, preservado]
7. job não STAGED            -> _JOB_NOT_STAGED           [2144, preservado]
8. APPROVED em NEEDS_REVIEW  -> _NEEDS_REVIEW             [2144, preservado]
9. UPDATE ... WHERE id = ANY(p_row_ids)                   [2144, preservado]
```

Os guards 3-5 são **validação pura de payload** — zero acesso ao banco.
Nenhum `ANY()` e nenhuma leitura de tabela ocorrem antes deles.

### `2164`

```
1. is_admin()                                             [2145, preservado]
2. p_job_id IS NULL          -> _MISSING_JOB              [2145, preservado]
3. se p_row_ids NOT NULL:                                  [NOVO]
     array_ndims <> 1        -> _INVALID_ARRAY_SHAPE
     cardinality = 0         -> _EMPTY_ROW_IDS
     cardinality > 1000      -> _TOO_MANY_ROWS
4. SELECT job FOR UPDATE / NOT FOUND                      [2145, preservado]
5. status ∈ (STAGED, CONFIRMING)                          [2145, preservado]
6. lookup de card_set (auditoria)                         [2145, preservado]
7. CONGELAMENTO do conjunto efetivo:                       [v1.1, NOVO]
     se NULL  -> v_effective_row_ids := ARRAY(... LIMIT 1001)
                 cardinality > 1000 -> _TOO_MANY_ROWS
     se array -> v_effective_row_ids := p_row_ids
8. UPDATE status = 'CONFIRMING'                           [2145, preservado]
9. LOOP ... AND r.id = ANY(v_effective_row_ids)           [2145 + filtro v1.1]
```

O passo 3 vem **antes** do lock do job (passo 4) — de propósito: payload
malformado é rejeitado sem tomar nenhum lock. O passo 7 vem **antes** da
mutação do passo 8. O passo 9 consome **exclusivamente** o conjunto
congelado — nunca reabre o universo.

---

## Zero mudança de regra de negócio

Preservado integralmente nas duas funções: assinatura pública, colunas e
ordem do `RETURNS TABLE`, `SECURITY DEFINER`, `SET search_path = ''`,
grants, retorno, e toda a lógica de domínio — estados permitidos, regra de
job `STAGED`, regra `NEEDS_REVIEW`, `SELECT ... FOR UPDATE` do job,
recálculo de `match_status` contra `card_variant`, regra `MATCHED` (nenhuma
escrita) / `NEW` (`internal.write_card_variant`), cálculo de
`variant_order` (`MAX+1`), `is_default` nascendo `FALSE`, bloco `EXCEPTION`
isolado por linha, recálculo de contadores por agregação, lógica de três
camadas do status final, auditoria `CARD_VARIANT_IMPORT_CONFIRMED` e
idempotência, e a ordenação de processamento do `LOOP`
(`ORDER BY r.created_at`).

As únicas mudanças de **comportamento observável** são as quatro rejeições
novas (multidimensional ×2, vazio na `2145`, teto ×2) e a troca de
`array_length` por `cardinality` no guard de presença da `2144` — que é
estritamente mais correta e não muda nenhum resultado para array
unidimensional.

O **conjunto congelado** (v1.1) não é mudança de regra de negócio: para
`p_row_ids` explícito ele é literalmente `v_effective_row_ids := p_row_ids`,
e o filtro do `LOOP` fica **semanticamente idêntico** ao da `2145`; para
`NULL` ele torna determinístico e limitado um universo que a `2145` já
processava por inteiro. A única diferença observável é que rows que se
tornem elegíveis **depois** do snapshot não entram naquela chamada — que é
precisamente o comportamento correto sob teto, e elas seguem disponíveis
para a chamada seguinte.

**Códigos de erro novos não exigem alteração no frontend:**
`traduzirErroCatalogo()` (`web/lib/supabase/catalogo-errors.ts`) extrai o
texto após o primeiro `: ` por regex genérica, sem mapa por código. Os
novos `_INVALID_ARRAY_SHAPE`, `_TOO_MANY_IDS`, `_TOO_MANY_ROWS` e
`_EMPTY_ROW_IDS` seguem o mesmo padrão `CODIGO: texto legível.` e já são
traduzidos.

---

## Matriz do harness (`2822`)

Matriz da **v1.1**. As quatro Seções são **fail-closed**: o sinal de PASS é
a ausência de exceção; qualquer divergência aborta nomeando o caso.

| Seção | Caso | Prova |
|---|---|---|
| **S1** (read-only, 13 asserções) | `S1.01`–`S1.02` | assinaturas públicas preservadas |
| | `S1.03`–`S1.04` | `SECURITY DEFINER` + `search_path=""` nas duas |
| | `S1.05` | grants **não** ampliados (só `authenticated` + owner) |
| | `S1.06`–`S1.08` | guards novos presentes no corpo LIVE |
| | `S1.09` | ordem `2163`: `is_admin` < `ndims` < `cardinality` < teto < `ANY()` |
| | `S1.10` | ordem `2164`: `is_admin` < guards de array < acesso ao job |
| | `S1.11a`–`c` | o corpo materializa `v_effective_row_ids`, usa `LIMIT c_max_rows + 1` e testa `cardinality(v_effective_row_ids) > c_max_rows` — **âncoras exclusivas do branch `NULL`** |
| | `S1.11d`–`g` | `v_effective_row_ids := ARRAY(` existe e vem **antes** de `SET status = 'CONFIRMING'` e do `FOR v_row IN`; o teste de teto também vem antes do `LOOP` |
| | `S1.12a`–`d` | os **três predicados** do snapshot verificados por presença literal (`job_id`, `persistence_status = 'PENDING'`, `decision_status IN ('APPROVED','SKIPPED')`) + `ORDER BY r.created_at, r.id` |
| | `S1.12e` | o `LOOP` restringe ao conjunto congelado (`AND r.id = ANY(v_effective_row_ids)`) |
| | `S1.12f` | **ausência** do padrão antigo `p_row_ids IS NULL OR r.id = ANY(p_row_ids)` — prova negativa do TOCTOU |
| | `S1.13` | o branch `ELSE` alimenta o mesmo conjunto (`v_effective_row_ids := p_row_ids`) |
| **S2** (`BEGIN…ROLLBACK`, 8 asserções, `2163`) | `S2.1` | não-admin bloqueado (`_FORBIDDEN`) |
| | `S2.2` | `NULL` rejeitado |
| | `S2.3` | **multidimensional rejeitado** |
| | `S2.4` | vazio rejeitado |
| | `S2.5` | **teto exato 10.000 ACEITO** (falha em `_NOT_FOUND`, não em `_TOO_MANY_IDS`) |
| | `S2.6` | **teto+1 (10.001) REJEITADO** sem tocar o banco |
| | `S2.7` | regressão: `decision_status` inválido |
| | `S2.8` | regressão: `APPROVED` em `NEEDS_REVIEW` real continua bloqueado |
| **S3** (`BEGIN…ROLLBACK`, 11 asserções, `2164`) | `S3.1` | não-admin bloqueado |
| | `S3.2` | multidimensional rejeitado **antes** de tocar o job (`job_id` falso) |
| | `S3.3` | array vazio rejeitado (`_EMPTY_ROW_IDS`) |
| | `S3.4` | **teto exato 1.000 ACEITO** (falha em `_JOB_NOT_FOUND`) |
| | `S3.5` | **teto+1 (1.001) REJEITADO** sem tocar o banco |
| | `S3.FIXTURE` | **uma única Card POKEMON ativa real**, repetida via `generate_series`, com asserção explícita de que `('{}'::jsonb ->> 'variant_type_id') IS NULL` — premissa do índice parcial da `2138` |
| | `S3.6` | **`NULL` + 0 elegíveis PERMITIDO** + job vai a `COMPLETED` |
| | `S3.7` | **`NULL` + exatamente 1.000 elegíveis PERMITIDO**; `card_variant` inalterado; as 1.000 viram `UNCHANGED` |
| | `S3.8` | **`NULL` + 1.001 elegíveis REJEITADO** antes do `LOOP` |
| | `S3.9` | a rejeição de `S3.8` **não deixou rastro** (job segue `STAGED`, rows `PENDING`, `card_variant` igual) |
| | `S3.11a`–`b` | **conjunto congelado**: exatamente o snapshot pré-medido foi processado, e não existem rows fora dele |
| | `S3.11c` | row elegível criada **depois** do snapshot permanece `PENDING` — o `LOOP` não reabriu o universo |
| | `S3.10` | array explícito ≤ 1.000 mantém o comportamento atual (sublote de 50 → `CONFIRMING`) |
| **S4** (read-only, 5 asserções) | `S4.1` | zero resíduo (`external_set_id = 'HARNESS-2822'` → 0) |
| | `S4.2`–`S4.5` | baseline intacto: `card_variant` = 6.483; 4 jobs `STAGED`; 519 `VALID`/`PENDING`; 505 `NEEDS_REVIEW`/`PENDING` |

**A prova do teto sem fabricar dados** é o par `S2.5`/`S2.6` e
`S3.4`/`S3.5`: os guards de forma/teto rodam antes de qualquer acesso ao
banco, então um array com o teto exato de ids **inexistentes** passa por
eles e morre mais adiante (`_NOT_FOUND` / `_JOB_NOT_FOUND`), enquanto
teto+1 morre em `_TOO_MANY_*`. **A diferença entre as duas mensagens é a
prova.** Só o teto do caminho `NULL` precisa de fixture real
(`S3.7`/`S3.8`/`S3.11`), integralmente revertida — e, na v1.1, essa
fixture usa **uma Card só**, repetida 1.001 vezes, em vez do Card Set com
≥ 1.001 Cards que a v1.0 exigia e que **não existe** no catálogo (maior Set
POKEMON: SWSHP, 300 Cards).

**S4 é fail-closed por decisão explícita.** Se o baseline legítimo tiver
mudado entre esta revisão e a execução, a Seção aborta — e o procedimento
correto é **STOP / reauditar**, nunca suavizar a asserção para `ATENCAO`.

---

## Ordem de execução — **executada em 2026-09-12**

```
1. 2163  (migration incremental)                              APLICADA / PASS
2. 2164  (migration incremental, v1.1)                        APLICADA / PASS
3. 2822  Seção 1   — estrutural/estática, read-only           13 asserções PASS
4. 2822  Seção 2   — comportamental 2163, BEGIN ... ROLLBACK   8 asserções PASS
5. 2822  Seção 3   — comportamental 2164, BEGIN ... ROLLBACK  11 asserções PASS
6. 2822  Seção 4   — zero resíduo, read-only                   5 asserções PASS
```

`c_admin_user_id` das Seções 2 e 3 está preenchido com
`fe316458-49dd-44e1-aac0-f4b7604ef8f2` — a mesma identidade administrativa
já utilizada na Query `6130`. Sem preenchimento as seções abortam no próprio
preflight, por desenho.

⚠️ O MCP do Supabase **não propaga `RAISE NOTICE`**. Por isso **as quatro
Seções** são fail-closed (v1.1 — na v1.0 apenas as Seções 2 e 3 eram): o
sinal de PASS é a **ausência de exceção**; o sinal de FAIL é a exceção
nomeando o caso. Cada Seção é seguida de um `SELECT … AS resumo`
meramente informativo — ele só é alcançado se nenhuma asserção abortou.

**Rollback:** as duas migrations são `CREATE OR REPLACE FUNCTION`. Reverter
significa reaplicar o corpo da `2144`/`2145` a partir de
`database/schema/`. Nenhum dado é tocado, nenhuma estrutura é alterada —
não há migração de dado para desfazer.

---

## Fora de escopo desta frente

- Chunking de `decidirLinhasVariantes()` no frontend — **pendência
  registrada, não tratada**. Com teto de 10.000 no backend, os 408 do SV5
  passam com folga. Vira necessário só se a campanha do Bloco 3 gerar lotes
  maiores; e aí é rodada de frontend.
- Bloco 1 (aprovar + confirmar as 519 rows `VALID`) — **próximo passo**.
- Bloco 2 (resolução de mappings / classificação `NEEDS_REVIEW`).
- Bloco 3 (campanha de import dos ~174 Sets).
- `VARIANT DEFAULT BACKFILL`.
- `2143`, `card_variant`, `card_variant_type`, mappings, rows/jobs
  existentes, Primary Species, Assets.

### Próximo passo — `CARD-VARIANTS-GLOBAL-RECONCILIATION — BLOCK-01`

Aproveitar as **519 rows `VALID`** já disponíveis: **289 Cards**, nos Sets
**BASEP / SV5 / SVE**. **BASE1 fica de fora** porque tem **0** rows `VALID`.

Fluxo obrigatório (provado no `AUDIT-01-CORRECTION-01`): selecionar somente
rows `VALID` → `admin_decide_catalog_variant_import_row(..., 'APPROVED')`
(`2163`) → `admin_confirm_catalog_variant_import(...)` (`2164`). As 519
cabem em uma única chamada de cada lado: 519 ≤ 10.000 e 519 ≤ 1.000.

Depois do Bloco 1, e **antes** da campanha dos ~174 Sets, vem a
**classificação `NEEDS_REVIEW`** em `AUTO-MAPPABLE` / `AUTO-CREATABLE` /
`HUMAN-REVIEW` — direção registrada na seção seguinte.

---

## Direção registrada para a próxima etapa — automação de Variant Types

**Não implementado nesta rodada. Registro de direção da frente de Card
Variants, conforme mandato.**

O cadastro/mapeamento manual de Card Variant Types **não pode virar gargalo
da campanha global**. Hoje existem 505 rows `NEEDS_REVIEW` em 4 jobs, e a
campanha sobre os 174 Sets restantes vai gerar muito mais — tratar cada uma
como decisão humana individual inviabiliza a frente.

Antes de iniciar os 174 Sets em massa, as combinações `NEEDS_REVIEW` serão
auditadas e **classificadas** em três classes:

| Classe | Definição |
|---|---|
| **`AUTO-MAPPABLE`** | o tipo canônico existente pode ser determinado **objetivamente** a partir da combinação externa. |
| **`AUTO-CREATABLE`** | a combinação é nova, mas permite criar um tipo canônico de forma **inequívoca**, sem duplicar semanticamente a taxonomia existente. |
| **`HUMAN-REVIEW`** | semântica nova, ambígua ou não determinística. |

**Princípio: revisão humana é exceção.** Uma decisão tomada uma vez deve
virar **mapping canônico reutilizável** em
`card_variant_type_external_mapping`, valendo para Cards e Sets atuais
**e futuros** — nunca uma decisão que se repete Set a Set.

**Restrições explícitas:**

- **Não auto-criar tipos por simples concatenação de tokens externos.**
  `type + foil + subtype + stamp` concatenados produzem nomes sintáticos,
  não conceitos de domínio.
- **Evitar explosão e duplicidade da taxonomia.** O `AUDIT-01` já mediu o
  sintoma: dos 79 Variant Types existentes, mais de 60 têm **1 a 5**
  ocorrências, quase todos `STANDARDS_WORLDS_*` /
  `STANDARDS_*_CHAMPIONSHIPS` / promos de varejo. A cauda longa cresceu por
  criação sob demanda no pipeline. Uma revisão de taxonomia deve acompanhar
  a automação, não vir depois dela.

Amostra real do que a classificação vai enfrentar (medida em 2026-09-12):

| Card Set | Combinação externa | Rows |
|---|---|---:|
| `BASE1` | `normal` + subtype `shadowless` / `unlimited` / `1999-2000-copyright` / stamp `1st-edition` | **344** |
| `BASE1` | `holo` + as mesmas 4 edições | 64 |
| `SVE` | `reverse` + foil `cosmos` + stamp `player-rewards-program` / `professor-program` | 32 |
| `SVE` | `reverse` + foil `tinsel` / `cracked-ice` | 16 |
| `BASEP` | `normal` + stamps promocionais (`pikachu-tail`, `1st-movie`, …) | 27 |
| `SV5` | `normal` + stamps de campeonato (`international-championship-*`, `master-ball-league`, …) | 20 |

As 4 edições clássicas do Base Set (408 das 505 rows) são o caso mais
promissor de `AUTO-MAPPABLE`/`AUTO-CREATABLE`: são um eixo editorial
conhecido e finito, não semântica nova.
