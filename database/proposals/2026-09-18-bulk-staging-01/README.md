# BULK-STAGING-01 — Staging em massa de Card Variants históricos

| Campo | Valor |
|---|---|
| **Frente** | `CARD VARIANTS — HISTORICAL BULK IMPORT` / `BULK-STAGING-01` |
| **Rodada** | `IMPLEMENTATION-01` → `SOURCE-VARIANT-SAFETY-01` → `CLOSEOUT-DOCS-01` (2026-09-18) |
| **Status** | **CONFIRMADO EXECUTADO — FULL concluído e validado em LIVE (2026-09-18).** 113/113 TARGET `STAGED` · 56 `DEFERRED_SOURCE_COVERAGE` · 18.940 staging rows · `card_variant` inalterada em **7.671** · 0 `FAILED` correntes / 0 em voo. Comprovado por postcheck READ-ONLY **externo ao runner**. Nenhuma migration, nenhum SQL |
| **Baseline** | `HEAD 168873ef` · `VARIANT-CARD-CORRELATION-FALLBACK-01` `CLOSED / LIVE VALIDATED / COMMITTED / PUSHED` |
| **Autoridade** | `MODELING-AUDIT-02` (`CLOSED / APPROVED`) + decisão **B13 — OPÇÃO D** |
| **Artefatos** | `bulk-staging-runner.js` · `source-variant-coverage-169.md` · este `README.md` |

---

## Objetivo

Stagear em massa os **113 Card Sets do TARGET** — os elegíveis cuja fonte TCGdex
é `variants: [...]` em **100%** das Cards — sem trabalho manual Set por Set.

**Esta frente para no staging.** O runner **não aprova linhas, não confirma jobs e não materializa Card Variant** — a resolução editorial global vem depois, em frente própria.

### Escopo do FULL — 113 TARGET, 56 DEFERRED

A CANARY LIVE terminou 3/3 `STAGED`, mas SM12 produziu **0 rows** com 271 Cards
correlacionadas — e foi para `STAGED` com `error_summary` nulo, indistinguível
de sucesso. A auditoria `SOURCE-VARIANT-SCHEMA-COVERAGE-AUDIT-01` mostrou que
**`SOURCE_READY` ≠ `VARIANT_SOURCE_READY`**: o campo `variants` tem três formas
reais na fonte, e o parser só extrai uma.

| Classe | Sets | Cards | Destino | Motivo |
|---|---:|---:|---|---|
| `ARRAY_SUPPORTED` puro | **113** | 10.301 | **TARGET** | `variants: [...]` em todas as Cards |
| `MIXED` | 8 | 1.182 | DEFERRED | ARRAY e ABSENT no mesmo Set → staging parcial silencioso |
| `ABSENT` | 46 | 4.926 | DEFERRED | a fonte não declara variante |
| `OBJECT_BOOLEAN` | 2 | 296 | DEFERRED | `variants: { normal, reverse, holo }` — sem `foil`/`subtype` |
| **Total** | **169** | **16.705** | | |

Decisão de Fabrício em `SOURCE-VARIANT-SAFETY-01`: **MIXED fica fora do FULL.**
Um Set parcialmente extraível produziria staging incompleto que ninguém
conseguiria distinguir de staging completo.

Classificação Set a Set, método e validação contra a CANARY: **`source-variant-coverage-169.md`**.
As listas literais vivem em `TARGET_SET_CODES` e `DEFERRED_SET_REASON` no runner,
e `assertManifest()` prova a cada execução que são partição exata dos 169 —
cardinalidade, ausência de duplicados, interseção vazia e cobertura total.

Os 56 DEFERRED **nunca são invocados**, em nenhum modo: o filtro de cobertura é
estrutural, não condicional ao `RUN_MODE`. São registrados como
`DEFERRED_SOURCE_COVERAGE` e saem da fila antes da porta de invocação — por isso
SM12, que integrava o lote CANARY histórico, hoje sai ali.

## Baseline LIVE (2026-09-18, medida read-only)

| Fato | Valor |
|---|---:|
| Card Sets elegíveis | **169** |
| Sem job de Variant algum | **168** |
| Com job `STAGED` (canário `EX5.5`) | **1** |
| Jobs `FAILED` nos 169 | **0** |
| Sets com referência TCGdex ativa | **169 / 169** |
| Sets com `catalog_import_job` TCGdex | **169 / 169** |
| Sets com múltiplos `external_set_id` históricos | **0** |
| Divergências referência × proxy histórico | **0** |

`ME5.5` está **fora do denominador operacional** (2 Cards / 0 Variants, fonte imatura).

---

## B13 — OPÇÃO D: fronteira fechada preservada

**Decisão de Fabrício.** `card_set_external_reference` **não é legível** por `authenticated` — zero `GRANT SELECT`, zero policy. Essa fronteira é deliberada e **este runner a preserva**: não lê a tabela, não pede grant, não cria policy, não cria RPC, não altera Edge.

**A autoridade canônica do `external_set_id` continua sendo `card_set_external_reference`**, lida **internamente pela Edge** no momento da invocação (`findCardSetExternalReference`, `service_role`).

O runner usa `catalog_import_job.external_set_id` **exclusivamente como SNAPSHOT / PROXY OPERACIONAL** — e este documento registra, de forma explícita e permanente, que **ele nunca é autoridade canônica**. Serve apenas ao guard fail-closed de divergência:

| Condição (por Set) | Veredito |
|---|---|
| Exatamente **1** `external_set_id` TCGdex histórico distinto | segue |
| **0** distintos | **`BLOCKED`** (`PROXY_EXT_AUSENTE`) |
| **> 1** distintos | **`BLOCKED`** (`PROXY_EXT_MULTIPLO`) |
| Job Variant ativo com `external_set_id` ≠ proxy | **`BLOCKED`** (`EXTERNAL_SET_ID_DIVERGENTE`) |

**Por que o proxy é seguro neste recorte, e por que ainda assim não é autoridade:** `external_set_id` é imutável por trigger; a UNIQUE é total em `(card_set_id, asset_source_id)`; o writer normal (`import-catalog-cards`) faz `UPSERT`, então troca pelo fluxo normal falha; um remapeamento real exigiria operação privilegiada `DELETE + INSERT`. O proxy é, portanto, um espelho estável do estado atual — mas é um **espelho**, e espelhos podem descolar se alguém mexer no original.

### CAMPAIGN FREEZE — proibições operacionais durante `CANARY` e `FULL`

**A campanha tem UM ÚNICO operador/orquestrador.** Enquanto `BULK-STAGING-01` estiver em execução, as seguintes ações estão **proibidas** — não por convenção, mas porque cada uma quebra uma garantia específica do desenho:

| Proibido | O que quebra |
|---|---|
| Executar manualmente **"Analisar"** para qualquer dos 169 Sets pela UI | Cria job fora do PLAN; o runner vê `409`/`ACTIVE_WAIT` e a contagem de progresso deixa de refletir a campanha |
| **Resolver / Aprovar / Rejeitar** rows dos jobs desta campanha | Esta frente **para no staging**. Decisão editorial é frente própria, posterior |
| **Confirmar** jobs desta campanha | Materializaria `card_variant` — fora do escopo, e invalida a baseline `7.671` do gate G6 |
| **Cancelar ou remover** jobs desta campanha | Apaga a evidência durável de que `RESUME` depende: retry budget, cooldown e `FAILED_PERMANENT` deixam de ser reconstruíveis |
| **Remapear `card_set_external_reference`** (incl. `DELETE + INSERT` privilegiado) | Descola o snapshot/proxy B13 da autoridade canônica sem que o runner consiga perceber |
| Rodar uma **segunda instância do runner em paralelo** (outra aba, outro browser, outra máquina) | Duas instâncias competem pelo mesmo orçamento de rate limit, produzem `409` cruzados e tornam o pacing de 65 s ineficaz |

**Nenhuma campanha concorrente** que toque Variant Import ou remapeie Sets pode rodar em paralelo.

O fechamento da frente terá **postcheck READ-ONLY externo ao runner**, comprovando que o snapshot permaneceu coerente com a autoridade.

---

## Desenho do runner

### PLAN — 3 leituras bulk, zero N+1

| # | Recurso REST (PostgREST existente) | Papel |
|---|---|---|
| **L1** | `catalog_card_set_variant_coverage` — `card_set_id, card_set_code, cards_cadastradas, cards_com_variante` | Universo elegível. View canônica (`ADR-027`, `security_invoker`, `SELECT` liberado a `authenticated`) |
| **L2** | `catalog_variant_import_job` — `…&card_set_id=in.(169 uuids)` | Jobs ativos + histórico de falhas |
| **L3** | `catalog_import_job` — `…&source=eq.TCGDEX&card_set_id=in.(…)` | **Proxy B13** do `external_set_id` |

Filtro do universo, em memória sobre L1: `cards_cadastradas > 0 ∧ cards_com_variante = 0 ∧ code ∉ {ME5.5}` → **169**.

**Nenhuma leitura por Set.** Agregação (`activeJobs`, `failedJobs`, `proxyExt`, `proxyDistinct`) é feita em memória, agrupando por `card_set_id`. Paginação explícita de 1.000 com teto de 50 páginas que **lança** em vez de truncar.

### Estados

Terminais: `STAGED` · `ALREADY_STAGED` · `BLOCKED` · `FAILED_PERMANENT`
Aguardando: `PENDING` · `RETRY_WAIT` · `COOLDOWN_WAIT` · `ACTIVE_WAIT`

Precedência da classificação, fixa: `BLOCKED → ALREADY_STAGED → ACTIVE_WAIT → FAILED_PERMANENT → COOLDOWN_WAIT → RETRY_WAIT → PENDING`.

### `INITIAL_BASELINE_GATE` × `RESUME_GATE`

Discriminante, **sem `localStorage`, sem `sessionStorage`, sem tabela nova**:

```
campanha_iniciada := ∃ Set elegível (≠ EX5.5) com job ativo OU job FAILED
```

`EX5.5` é excluído do discriminante porque seu job é **anterior** à campanha (canário do `FALLBACK-01`); sem essa exceção o gate inicial nunca dispararia.

| Gate | Assertivas | Divergência |
|---|---|---|
| `INITIAL_BASELINE_GATE` | 169 elegíveis · 1 `ALREADY_STAGED` (= `EX5.5`) · **0 `FAILED`** · 0 `BLOCKED` | **STOP** |
| `RESUME_GATE` | 169 elegíveis · 0 `BLOCKED` · **`FAILED > 0` é ESPERADO** | Só `BLOCKED > 0` ou contagem ≠ 169 abortam |

O `RESUME_GATE` **nunca aborta por `FAILED > 0`** — é dele que se reconstrói retry e cooldown.

### Reconstrução de retry/cooldown após refresh

Tudo derivado de `catalog_variant_import_job` (L2). Nada em memória:

| Variável | Derivação |
|---|---|
| `nTrans` | `COUNT(FAILED)` com `error_summary ∈ TRANSIENT` |
| `nRate` | `COUNT(FAILED)` com `error_summary ∈ RATE_LIMIT` |
| última classe / instante | `error_summary` / `updated_at` do `FAILED` de maior `updated_at` |
| cooldown restante | `last_fail_at + 65 min − now()` |
| backoff restante | `last_fail_at + backoff(nTrans) − now()` |
| `FAILED_PERMANENT` | última classe ∈ `PERMANENT` **ou** `nTrans ≥ 3` |

Contagens por classe são independentes — um rate limit não consome budget transitório. Reexecutar o runner **não zera budget, não esquece `FAILED_PERMANENT`, não ignora cooldown vigente e não repete erro permanente**.

### ALLOWLIST de erros — fail-closed

```
RATE_LIMIT  = GITHUB_CONTENTS_HTTP_403 · GITHUB_CONTENTS_HTTP_429
TRANSIENT   = GITHUB_CONTENTS_TIMEOUT · TCGDEX_SET_METADATA_TIMEOUT
              TCGDEX_SET_METADATA_HTTP_{500,502,503,504}
PERMANENT   = CARD_SET_NOT_FOUND · CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND
              GITHUB_SOURCE_SET_FOLDER_EMPTY_OR_NOT_FOUND · GITHUB_CONTENTS_HTTP_404
              GITHUB_CONTENTS_UNEXPECTED_SHAPE · TCGDEX_SET_METADATA_INCOMPLETE
```

As três listas classificam **apenas `error_summary` persistido pela Edge em um job `FAILED`**. **Qualquer token fora delas → `BLOCKED` + `ABORT`.** Nunca "transitório por exclusão": um erro novo introduzido por evolução futura da Edge não pode ser retentado às cegas.

Retry transitório: **1ª → 30 s · 2ª → 120 s · 3ª → `FAILED_PERMANENT`** (terminal só com `nTrans ≥ 3`), **exclusivamente** para falhas transitórias persistidas em `FAILED`.

### Erro de transporte — caminho próprio, fora da allowlist

`NETWORK_ERROR_NO_RESPONSE` **não existe mais como classe transitória** (CORRECTION-01). Um `fetch` do browser pode falhar **antes** de a request chegar à Edge; nesse caso **não há job `FAILED` no banco**, e contar a tentativa criaria um retry budget que só existe em memória — apagado no primeiro refresh, exatamente o que o contrato de resumabilidade proíbe.

Contrato para `fetch` sem resposta / exception de transporte:

1. **re-PLAN pontual imediato** do Set (`replanSet`);
2. se houver **evidência durável nova** (`activeJobs` ou `failedJobs` cresceram), classificar por ela:
   - `STAGED` → `ALREADY_STAGED`
   - `RECEIVED` / `PROCESSING` → `ACTIVE_WAIT`
   - `FAILED` → classificar pelo `error_summary` persistido
   - conflito (`>1` ativo, `external_set_id` divergente) → `BLOCKED`
3. se **não** houver evidência durável nova → **`ABORT("EDGE_OUTCOME_UNKNOWN_NO_DURABLE_EVIDENCE")`**.

Nunca consumir retry budget só em memória. Nunca tentar de novo às cegas após erro de transporte — a invocação **pode** ter chegado e estar em curso.

### Rate limit

Pacing normal **65 s** entre invocações reais (≈ 55 req/h, margem sob o teto de 60/h da Contents API). Ao receber `403`/`429`: a Edge já grava o job como `FAILED`; o runner entra em **cooldown de 65 min**, reconstruível por `updated_at`. **Segundo rate limit após cooldown completo → `ABORT`** com relatório.

`github-source.ts` **não é tocado**. Git Trees API **não é adotada**.

### Sessão / visibility / token

- `readAccessToken()` **antes de cada request** (REST e Edge) — nunca congelado, nunca entre ciclos;
- token **nunca** armazenado (`localStorage`/`sessionStorage`/cookie) e **nunca** impresso;
- pausa enquanto `document.visibilityState !== "visible"`, retomada automática;
- `401` / sessão ilegível / `403 FORBIDDEN_NOT_ADMIN` → **`ABORT` fail-closed**;
- **a aba precisa ficar visível e em foco durante toda a execução** — o `SessionRefresher` só renova o token com a aba ativa, e o middleware de refresh está órfão desde 2026-08-14;
- sem `service_role`, sem JWT fabricado, sem `SET ROLE`, sem segredo novo. `ANON_KEY` é pública por desenho.

### `409` e `ACTIVE_WAIT`

`409 JOB_ALREADY_ACTIVE` **nunca vira `SKIPPED` cego** — dispara **re-PLAN do Set** e classificação pelo estado real do banco. `RECEIVED`/`PROCESSING` → `ACTIVE_WAIT`; **5 min sem avanço de `updated_at` → `BLOCKED`** (`JOB_ATIVO_ESTAGNADO`), nunca arbitrar nem cancelar. A campanha **não termina** enquanto existir `ACTIVE_WAIT`.

---

## Modos de execução

| | `RUN_MODE = "CANARY"` (default) | `RUN_MODE = "FULL"` |
|---|---|---|
| Escopo | Lote histórico **SV2 → SM12 → SV4**, já filtrado por cobertura (SM12 sai como `DEFERRED_SOURCE_COVERAGE`) | **Os 113 TARGET**, maiores primeiro |
| Ao terminar | **PARA com relatório** | Segue até a condição de conclusão |
| Continua p/ FULL? | **Nunca automaticamente** | — |
| Autorização | — | **Explícita de Fabrício, posterior** |

`DRY_RUN = true` é o **safe default**: monta o PLAN, roda todos os gates, imprime o que faria e **não invoca nada**.

A onda canária existe para converter o risco `B10` (maior Set nunca exercitado × teto de execução da Edge) de suposição em fato **nos primeiros minutos**, com 3 jobs em risco — não com 100 após 3 h.

---

## Condição de conclusão (`FULL`)

```
∀ Set ∈ 113 TARGET:                       ← o denominador é o TARGET, não os 169
      exatamente 1 job ativo  ∧  status = 'STAGED'
   ∧  external_set_id coerente com o proxy congelado
∧ BLOCKED = 0 ∧ FAILED_PERMANENT = 0
∧ RETRY_WAIT = 0 ∧ COOLDOWN_WAIT = 0 ∧ ACTIVE_WAIT = 0

os 56 DEFERRED não entram no denominador — são escopo EXCLUÍDO por decisão,
não pendência. Contá-los faria o FULL parecer eternamente incompleto.
```

Derivável do banco por qualquer sessão, sem histórico do runner. Sets stageados antes de um refresh contam normalmente como `ALREADY_STAGED` — que deixa de ser exceção e passa a ser o estado majoritário no fim. `EX5.5`, `SV2` e `SV4` já entram como `ALREADY_STAGED` (são TARGET e já têm job), e **nunca são recriados**.

**Idempotência:** reexecutar após a conclusão ⇒ **113 `ALREADY_STAGED` + 56 `DEFERRED_SOURCE_COVERAGE`, 0 invocações**.

**A conclusão é comprovada por postcheck READ-ONLY externo ao runner**, não pelo relatório do próprio runner.

---

## Gates obrigatórios da execução

| # | Gate |
|---|---|
| G1 | `DRY_RUN = true` e `RUN_MODE = "CANARY"` no arquivo versionado |
| G2 | `PREFLIGHT` aborta sem sessão, sem admin, com contagem ≠ 169 ou com qualquer `BLOCKED` |
| G2b | `MANIFEST_GATE` aborta se TARGET ≠ 113, DEFERRED ≠ 56, houver duplicado, interseção ou Set elegível não classificado |
| G2c | `FULL` aborta se a fila TARGET pós-filtro ≠ 113 (fila COMPLETA, incluindo os já `ALREADY_STAGED` — não só os invocáveis) |
| G3 | `INITIAL_BASELINE_GATE` aborta se `FAILED ≠ 0` ou `ALREADY_STAGED ≠ 1` |
| G4 | **Zero** `decide`/`confirm` no código — proibição estrutural |
| G5 | `EX5.5` nunca reinvocado, confirmado, rejeitado ou excluído |
| G6 | Baseline `card_variant = 7.671` **inalterada** ao fim da frente |
| G7 | `CAMPAIGN FREEZE` respeitado durante toda a campanha |
| G8 | Postcheck READ-ONLY externo no fechamento |

---

## O que este runner NÃO faz

- não aprova linhas, não confirma jobs, não materializa `card_variant`;
- não lê `card_set_external_reference`;
- não executa SQL, não cria migration, não cria RPC, não cria tabela;
- não altera Edge Function, `github-source.ts`, frontend, grants ou policies;
- não usa `service_role`, não fabrica JWT, não usa `SET ROLE`;
- não grava `localStorage`, `sessionStorage` ou cookie;
- não imprime token nem segredo;
- não prossegue de `CANARY` para `FULL` sozinho.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.4 | **FULL `EXECUTED / LIVE VALIDATED` (2026-09-18, `BULK-STAGING-01-CLOSEOUT-DOCS-01`).** Status do documento passa de `PROPOSTA — NÃO EXECUTADO` para **`CONFIRMADO EXECUTADO`** — a campanha rodou e foi comprovada por postcheck READ-ONLY **externo ao runner**. Baseline terminal: **113/113 TARGET `STAGED`** · **56 `DEFERRED_SOURCE_COVERAGE`** · **18.940** staging rows (`VALID` 17.222 · `NEEDS_REVIEW` 1.642 · `INVALID` 76; por decisão `PENDING` 18.864 · `SKIPPED` 76) · **`card_variant` 7.671, inalterada — nenhuma materialização** · 0 `FAILED` correntes · 0 em voo. Edge `import-card-variants` **v14** LIVE, `verify_jwt=true`. **Retry real registrado:** `TK-DP-M` falhou na primeira invocação com `TCGDEX_SET_METADATA_HTTP_503` e 0 rows; a retentativa fechou `STAGED` com 12/12 `VALID` — o caminho transitório com backoff persistido funcionou em condição real. **Preservações verificadas:** `EX5.5`/`SV2`/`SV4` entraram como `ALREADY_STAGED` e nunca foram recriados; **`SM12` permanece `DEFERRED`/`ABSENT` com job `STAGED` de 0 rows**, não alterado, não cancelado, não excluído. **Os 56 `DEFERRED` seguem explicitamente fora do escopo de materialização** até tratamento futuro próprio. **Próxima frente: `BULK-STP-01`** — consumo editorial das 18.864 linhas `PENDING`. Nenhuma alteração de lógica, SQL, Edge Function ou runner nesta rodada: apenas status documental. |
| 1.3 | **`SOURCE-VARIANT-SAFETY-01 / IMPLEMENTATION-01 — CORRECTION-01` (2026-09-18).** Três blockers de integridade fechados na Edge, com dois erros novos refletidos aqui. **(1) Cobertura canônica por Card:** `expected_card_ids` MINUS representadas na fonte = ∅, com autoridade em `public.card` (nunca `total_set_size`, contagem de arquivos, snapshot ou referências externas). A leitura de membership foi extraída para `listCardIdsOfCardSet()` e é INJETADA em `listCardLineageCorrelationMap()`, que já precisava dela para o G0 — uma leitura, dois consumidores, **zero consulta adicional por Set**. Violação → `VARIANT_SOURCE_CARD_COVERAGE_INCOMPLETE`, adicionado a `ERR_PERMANENT`. **(2) Fetch falho de Card correlacionada:** `correlated` exclui `fetchError`, então uma Card MMKYU conhecida cujo arquivo falhou no fetch escapava de todos os guards. Violação → `VARIANT_SOURCE_FETCH_FAILED_FOR_CORRELATED_CARDS`, adicionado a `ERR_TRANSIENT` — legítimo ali porque a Edge o PERSISTE em job `FAILED`, então o retry budget (30 s → 120 s → terminal na 3ª) é reconstruível do banco, nunca de memória. Este guard roda **antes** do de cobertura de propósito: a mesma Card também sumiria da cobertura, e reportá-la como PERMANENTE perderia o retry. **(3) ARRAY all-or-nothing:** um array com um objeto válido e outro ilegível devolvia `ARRAY` com combos parciais; agora qualquer objeto sem `type` string não-vazia torna o array inteiro `UNSUPPORTED`. Manifesto 113/56, MIXED fora do FULL, OBJECT não suportado e ABSENT não derivado permanecem inalterados. |
| 1.2 | **`SOURCE-VARIANT-SAFETY-01 / IMPLEMENTATION-01` (2026-09-18).** Escopo do FULL reduzido de 169 para **113 TARGET**, após `SOURCE-VARIANT-SCHEMA-COVERAGE-AUDIT-01` provar que 56 Sets não têm variante extraível da fonte (8 `MIXED`, 46 `ABSENT`, 2 `OBJECT_BOOLEAN`). Por decisão de Fabrício, **MIXED também fica fora**: staging parcial é indistinguível de staging completo. Adicionados ao runner o manifesto congelado `TARGET_SET_CODES`/`DEFERRED_SET_REASON`, o `assertManifest()` (partição exata provada a cada execução), o filtro de cobertura **estrutural** que remove os DEFERRED da fila em *qualquer* modo, o estado `DEFERRED_SOURCE_COVERAGE` e o completion gate com denominador 113. `VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS` entra em `ERR_PERMANENT` no mesmo ciclo em que o guard é criado na Edge — sem isso o erro seria `UNKNOWN` → `BLOCKED` → `GATE_BLOCKED`, e um único Set travaria a campanha. Criado `source-variant-coverage-169.md` como evidência congelada. Jobs existentes preservados: `EX5.5`/`SV2`/`SV4` entram como `ALREADY_STAGED`; **SM12 (`STAGED`/0 rows) vai para DEFERRED e não é alterado, cancelado nem excluído**. Nenhum SQL, nenhum deploy, nenhuma execução. |
| 1.1 | **`IMPLEMENTATION-01 / CORRECTION-01` (2026-09-18).** Dois ajustes, ambos só em `bulk-staging-runner.js` e neste README. **(1) Blocker de resumabilidade:** `NETWORK_ERROR_NO_RESPONSE` **removido** da allowlist `TRANSIENT` — um `fetch` que falha antes de chegar à Edge não deixa job `FAILED`, e contá-lo como tentativa criaria retry budget só em memória. Erro de transporte passa a ter caminho próprio: re-PLAN pontual imediato, classificação **exclusivamente** pela evidência durável e, sem evidência nova, `ABORT("EDGE_OUTCOME_UNKNOWN_NO_DURABLE_EVIDENCE")` — nunca nova tentativa às cegas. Introduzido o helper `replanSet()`, que unifica as três leituras pontuais (409, erro e transporte) antes duplicadas. **(2) Hardening operacional:** seção `CAMPAIGN FREEZE` ampliada com as seis proibições explícitas durante `CANARY`/`FULL` e a regra de **operador único**. Todos os demais contratos preservados sem alteração. |
| 1.0 | **Criação (2026-09-18, `BULK-STAGING-01 / IMPLEMENTATION-01`).** Runner descartável de DevTools e este README, ambos `PROPOSTA — NÃO EXECUTADO`. Incorpora `MODELING-AUDIT-02` integralmente e a decisão **B13 — OPÇÃO D** (fronteira fechada de `card_set_external_reference` preservada; `catalog_import_job.external_set_id` usado **somente** como snapshot/proxy operacional, nunca como autoridade canônica). `DRY_RUN = true` e `RUN_MODE = "CANARY"` como safe defaults. Onda canária corrigida para **SV2 (279) · SM12 (271) · SV4 (266)**, medida no LIVE. Nenhum SQL, nenhuma migration, nenhum deploy, nenhuma escrita LIVE nesta rodada. |
