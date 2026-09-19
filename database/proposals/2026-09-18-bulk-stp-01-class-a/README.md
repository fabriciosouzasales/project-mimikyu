# BULK-STP-01 / CLASSE A — Consumo automatizado das 17.222 linhas VALID

| Campo | Valor |
|---|---|
| **Ciclo** | `BULK-STP-01 / CLASSE A` |
| **Mandato desta pasta** | `BULK-STP-01-CLASS-A-RUNNER-STAGING-01` (2026-09-18) |
| **Autoridade de desenho** | `CLASS-A-OPERATIONAL-DESIGN-01` + `CORRECTION-01` (ambos APROVADOS) |
| **Status** | **`EXECUTED / LIVE VALIDATED / CLOSED`** (2026-09-18, `BULK-STP-01-CLASS-A-CLOSEOUT-01`). BASELINE DRY_RUN → CANARY → FULL, os três executados; **CAMPAIGN FREEZE encerrado**. |
| **Baseline de entrada** | `HEAD main 61a2d7d6` · CANONICAL RECONCILIATION `CLOSED / COMMITTED / PUSHED` |

---

## O que esta pasta contém

| Arquivo | Papel |
|---|---|
| `class-a-runner.js` | Runner efêmero autenticado, colado no console do DevTools. **O arquivo versionado permanece em `RUN_MODE = "DRY_RUN"`** — `CANARY` e `FULL` foram executados alterando a constante apenas no texto colado, nunca no arquivo, de modo que nada aqui é re-executável por acidente. |
| `class-a-runner.static-check.mjs` | 46 provas estáticas sobre o runner. Lê o arquivo como TEXTO — não importa, não executa, não abre rede. |

**Nada aqui cria tabela, RPC, Edge Function, policy ou grant.** O runner usa
exclusivamente dois contratos que já estão LIVE:

- `public.admin_decide_catalog_variant_import_row(UUID[], TEXT)` — Query 2144 v2.0
- `public.admin_confirm_catalog_variant_import(UUID, UUID[])` — Query 2145 v2.0

---

## Política — `VALID ⇒ APPROVED`

Pertencimento é decidido pelo **manifesto congelado dos 113 TARGET**, nunca por
status. `SM12` está `STAGED` e é `DEFERRED`: fica fora por **asserção
explícita**, não por consequência de filtro.

Elegibilidade, por linha:

```
job.card_set.code ∈ TARGET_SET_CODES (113)
AND row.validation_status  = 'VALID'
AND row.decision_status    = 'PENDING'
AND row.persistence_status = 'PENDING'
```

## Conjuntos — definição fechada

| Conj. | Predicado | Papel |
|---|---|---|
| **A** | `VALID` / `PENDING` / `PENDING` | Classe A — candidatos a `APPROVED` |
| **B** | `VALID` / `APPROVED` / `PENDING` | recuperação entre `decide` e `confirm` |
| **C** | **`INVALID`** / `SKIPPED` / `PENDING` **e** `skip_reason = 'SIZE_OUT_OF_SCOPE'` | automáticas do sistema (JUMBO), a consolidar em `UNCHANGED` |
| **N** | `NEEDS_REVIEW` / `PENDING` | **nunca tocadas**, só observadas |
| **F** | `persistence_status = 'FAILED'` | **estado de primeira classe**. Baseline 0. Qualquer F ⇒ STOP |

**C é fechado.** Qualquer `SKIPPED/PENDING` fora desse predicado ⇒
`STOP UNEXPECTED_SKIPPED_KIND`. Medido no LIVE em 2026-09-18: **76 em 29 jobs,
composição única `INVALID / SIZE_OUT_OF_SCOPE`, zero fora do predicado**.

## Fluxo por job

```
1. ler A, B, C, N, F  (1 request por job)
2. A>0 && B>0                    ⇒ STOP RESUME_PARTIAL
   F>0                           ⇒ STOP FAILED_ROWS_PRESENT
   strayC>0                      ⇒ STOP UNEXPECTED_SKIPPED_KIND
3. se A>0:
     n = decide(A, 'APPROVED')
     n !== |A|                   ⇒ STOP DECIDE_ROWS_MISMATCH
     RELER e provar A ⊂ B        ⇒ senão STOP DECIDE_NOT_REFLECTED / DECIDE_LEFTOVER_A
4. confirm(job, A∪B∪C)  — array SEMPRE explícito, p_row_ids=NULL proibido
5. F novo                        ⇒ STOP CONFIRM_COMMITTED_WITH_FAILURES (ids + error_detail)
6. delta por snapshot PRE/POST   — NUNCA pelos contadores da RPC
```

**Por que `p_row_ids` explícito e nunca `NULL`:** `NULL` deixa o banco definir
o conjunto de escrita. O runner escreve apenas o que enumerou e provou.

**Por que os contadores da RPC não servem de delta:** `admin_confirm_...`
retorna contadores **acumulados do job**, não o delta da chamada. Deltas vêm de
`restCount` antes e depois.

## Atomicidade — o que a RPC garante e o que não garante

`admin_confirm_catalog_variant_import` é transacional **na chamada**, mas
captura exceção **por row** (`EXCEPTION WHEN OTHERS` dentro do loop). Pode
portanto **commitar** com parte `INSERTED`/`UNCHANGED` e parte `FAILED`.

Consequência direta: **"parte saiu de PENDING" NÃO é estado impossível.** O
protocolo de `NETWORK_ERROR_NO_RESPONSE` no confirm reflete isso, relendo os
próprios ids de `S`:

| Ramo | Observado | Ação |
|---|---|---|
| **A** | todas ainda `PENDING`, zero `FAILED` | não houve persistência observável — revalidar e permitir nova chamada |
| **B** | todas terminais, `FAILED = 0` | a chamada foi aplicada — seguir |
| **C** | qualquer `FAILED` | **STOP `CONFIRM_COMMITTED_WITH_FAILURES`** + ids + `error_detail`. **Nenhum retry.** |
| **D** | mistura de `PENDING` com terminais | **STOP `INDETERMINATE_CONFIRM_STATE`** — concorrência, não retry |

**Nunca há retry cego.** `NETWORK_ERROR_NO_RESPONSE` fica fora das três
allowlists (`ERR_PERMANENT` / `ERR_TRANSIENT` / `ERR_RATE_LIMIT`).

## Fases e números — previstos no desenho, **confirmados na execução**

Todas as três colunas abaixo foram escritas **antes** da primeira escrita LIVE e
**conferiram uma a uma** no postcheck. Nenhum número foi ajustado retroativamente.

| Métrica | INICIAL | PÓS-CANARY | FINAL |
|---|---|---|---|
| TARGET `STAGED` | **113** | **110** | **62** |
| TARGET `COMPLETED` | 0 | **3** | **51** |
| `SM12` (fora do manifesto) | `STAGED`, 0 rows | inalterado | inalterado |
| Classe A | **17.222** (109 jobs) | **16.734** (105 jobs) | **0** |
| `card_variant` | **7.671** | **8.159** | **24.893** |
| C (`SKIPPED/PENDING`) | **76** (29 jobs) | **73** (28 jobs) | **0** |
| `UNCHANGED` acumulado | 0 | 3 | **76** |
| `NEEDS_REVIEW` | **1.642** | **1.642** | **1.642** |
| B / F | 0 / 0 | 0 / 0 | 0 / 0 |

**Deltas mode-aware — o FULL NUNCA usa 7.671 como baseline físico:**

| Execução | Δ da execução | Acumulado | Baseline de entrada |
|---|---|---|---|
| CANARY | **+488** | +488 | **7.671** |
| FULL | **+16.734** | **+17.222** | **8.159** |

### CANARY congelado — 4 jobs / 488 linhas

| Set | A | N | print null | print string | C | Δ `card_variant` | Estado final |
|---|---|---|---|---|---|---|---|
| `FUT2020` | 5 | 0 | 5 | 0 | 0 | +5 | `COMPLETED` |
| `NEO3` | 132 | 0 | 66 | 66 | 0 | +132 | `COMPLETED` |
| `NEO1` | 222 | 0 | 111 | 111 | **3** | +222 | `COMPLETED` |
| `BASE2` | 129 | **21** | 65 | 64 | 0 | +129 | **`STAGED`** |

Cobre: `printing null` · `printing string` · job 100% VALID · job misto ·
ramo `SKIPPED → UNCHANGED` · fecha `COMPLETED` · volta a `STAGED`.

## Sequência obrigatória de gates

```
BASELINE DRY_RUN → CANARY PRECHECK → CANARY LIVE → CANARY POSTCHECK
                 → FULL DRY_RUN / PRECHECK (sobre o estado PÓS-CANARY)
                 → FULL LIVE → FULL POSTCHECK
```

**Sem auto-FULL.** Cada fase exige mandato próprio e edição explícita da
constante `RUN_MODE`. Não há prompt, não há `confirm()`, não há transição
automática. O `FULL PRECHECK` espera o baseline **pós-canary**; exigir 113
`STAGED` ou 7.671 abortaria a campanha por sucesso.

## CAMPAIGN FREEZE — premissa de concorrência (**encerrado em 2026-09-18**)

Vigorou durante `CANARY`, `FULL` e retomadas; **encerrado com o closeout**. Enquanto
esteve em vigor:

- o usuário **não** utiliza a UI de Importação / Revisão de Variantes;
- **nenhum** mapping é criado ou resolvido (`admin_resolve_*`, inclusive Printing);
- **nenhum** Print Profile é criado (`admin_create_card_printing_profile_with_backfill` faz backfill);
- **nenhuma** nova importação / novo job para os 113 TARGET;
- **nenhuma** segunda instância do runner, em nenhuma aba;
- **nenhum** write SQL paralelo.

Este é um **controle operacional aceito somente para esta campanha efêmera**.
**Não é precedente para bulk permanente multi-admin**: não há lock no banco, e
a garantia é disciplina humana. O runner não confia no freeze — ele o
**verifica**, por `rows_affected === |A|`, `RESUME_PARTIAL`, `F > 0` e o
precheck de baseline por fase.

## Segurança

- Sessão administrativa **real**, do navegador. `is_admin()` a cada chamada.
- **Nenhum `service_role`**, nenhum JWT fabricado, nenhum `SET ROLE`.
- `access_token` relido do cookie antes de cada request; nunca congelado,
  nunca impresso, nunca gravado.
- **Nenhuma escrita direta em tabela**, nenhum SQL. Só as duas RPCs.
- Fail-closed em toda decisão ambígua.

## Provas estáticas — 46 PASS / 0 FALHA

```
node database/proposals/2026-09-18-bulk-stp-01-class-a/class-a-runner.static-check.mjs
```

Cobrem: `p_row_ids=NULL` ausente no confirm · `service_role` ausente · zero SQL
direto · zero escrita em tabela · só as 2 RPCs autorizadas · manifesto 113 sem
duplicata · `SM12` fora · CANARY exatamente os 4 aprovados e todos no manifesto
· C exige `INVALID` + `SIZE_OUT_OF_SCOPE` · `RUN_MODE` default `DRY_RUN` e
atribuído uma única vez · zero auto-FULL · zero interação · DRY_RUN sem RPC ·
F como estado de primeira classe sem retry · gates de `decide` · quatro ramos do
`NO_RESPONSE` · deltas por snapshot · baselines mode-aware · tetos 10.000/1.000
· logs sem segredos · CAMPAIGN FREEZE registrado.

**Registro de honestidade:** o harness reprovou 3 casos no primeiro run
(`S9b`, `S12d`, `S19a`). Os três eram **defeitos do próprio harness**, não do
runner: casavam prosa dentro de literais de string — inclusive a própria frase
que declara a ausência de retry. Corrigidos com um `CODE_NOSTR` (código sem
literais) e provas estruturais; run #2 fechou **46/46**. Nenhuma linha do runner
foi alterada por causa disso.

## Estado terminal — `EXECUTED / LIVE VALIDATED / CLOSED` (2026-09-18)

Medido por postcheck READ-ONLY **externo ao runner**, após a FULL:

| Fato | Valor |
|---|---:|
| TARGET (manifesto congelado) | **113** |
| — `COMPLETED` | **51** |
| — `STAGED` (retêm `NEEDS_REVIEW`) | **62** |
| — `CONFIRMING` · `COMPLETED_WITH_ERRORS` · `FAILED` | **0 · 0 · 0** |
| `card_variant` | **7.671 → 24.893** |
| `persistence = INSERTED` nos TARGET | **17.222** |
| `persistence = UNCHANGED` nos TARGET | **76** |
| Classe A remanescente (A) | **0** |
| B · C · F · stray C | **0 · 0 · 0 · 0** |
| `NEEDS_REVIEW` nos TARGET | **1.642 — intactas** |
| Identidades duplicadas em `card_variant` | **0** |
| `is_default = true` criado nos TARGET | **0** |

**Deltas por execução:**

| Execução | Δ `card_variant` | Acumulado | Baseline de entrada |
|---|---:|---:|---:|
| CANARY (4 jobs / 488 linhas) | **+488** | +488 | 7.671 |
| FULL (pós-CANARY) | **+16.734** | **+17.222** | 8.159 |

As **76** linhas `SKIPPED` do conjunto C consolidaram em `UNCHANGED` — nenhuma virou
Variante, que é o resultado correto para JUMBO fora de escopo.

**O que permanece aberto, por decisão, e não é pendência desta frente:**

- **1.642 `NEEDS_REVIEW`** nos 62 TARGET ainda `STAGED` — frente editorial própria,
  destravada por `VARIANT-DISPLAY-SEMANTICS-01`.
- **56 `DEFERRED_SOURCE_COVERAGE`** — fora do escopo de materialização; 55 seguem sem
  job e `SM12` segue `STAGED` com 0 rows, preservado deliberadamente.

**Nota de precisão (fora do escopo dos 113 TARGET).** `decision_status` e
`persistence_status` são eixos independentes — uma linha `SKIPPED` já está decidida e
ainda assim segue `persistence_status = 'PENDING'` até ser confirmada. Por isso nenhum
número abaixo aparece como "`PENDING`" sem qualificação.

**2.077 linhas com `persistence_status = 'PENDING'` no total, sendo 1.642 nos TARGET e
435 fora do manifesto.** Composição das 435:

| Composição | Linhas |
|---|---:|
| `VALID` / `decision = SKIPPED` | **414** |
| `NEEDS_REVIEW` / `decision = PENDING` | **14** |
| `INVALID` / `decision = SKIPPED` | **6** |
| `VALID` / `decision = PENDING` | **1** |
| **Total** | **435** |

Pelo eixo de decisão: **1.657 linhas com `decision_status = 'PENDING'` no total, sendo
1.642 nos TARGET e apenas 15 fora do manifesto.** As outras 420 das 435 já estão
decididas como `SKIPPED` — aguardam confirmação, não decisão editorial.

Existem ainda **8** jobs históricos em `FAILED` (7 de agosto de 2026, 1 de `TK-DP-M` em
2026-09-18), **todos com 0 rows** — jobs que falharam na abertura, não jobs com linhas
falhadas. Nenhum deles é o job corrente de um TARGET. `persistence_status = 'FAILED'` é
**0 na tabela inteira**.
