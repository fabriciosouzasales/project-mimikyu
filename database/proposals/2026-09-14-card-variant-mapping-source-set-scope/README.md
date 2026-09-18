# SOURCE-SET-SCOPED VARIANT TYPE MAPPING — Staging

| Campo | Valor |
|---|---|
| **Mandato** | CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 / SOURCE-SET-SCOPED-FOUNDATION / **FINAL-CLOSEOUT-DOCUMENTATION-01** |
| **Data** | 2026-09-14 |
| **Status** | **CONFIRMADO EXECUTADO — CLOSED / LIVE.** 2191–2197 aplicadas, Edge v10 ACTIVE, primeiro override real criado. Ver §0-Z. |
| **Projeto Supabase** | `qjfutqujxrbzgrtkpgkg` |

> **Nota de leitura.** As seções 0-A em diante preservam o histórico de revisão do ciclo
> (GATE-A-STAGING-01 → REV-01 → REV-02 → REV-03) e foram escritas quando o status era
> *PROPOSTA*. Elas **não** foram reescritas: descrevem o caminho, não o estado final.
> O estado final é o da §0-Z.

---

## 0-Z. FECHAMENTO — o que foi efetivamente executado

### Fundamento

A TCGdex usa `foil: galaxy` com dois sentidos editoriais incompatíveis: em `base3` é o
acabamento *default* do set inteiro; em `sv03.5`/`sv05`/`sv06` é um tratamento *especial*,
ao lado da holo default da mesma carta. Um mapping por Game+Fonte não distingue os dois —
corrigir um quebrava o outro. A divergência é **da fonte** e é **por set**, então o escopo
passou a pertencer ao vocabulário da fonte.

### Contrato

| escopo | `external_set_id` | significado |
|---|---|---|
| **GLOBAL** | `NULL` | vale para todos os Sets daquela Fonte/Game — comportamento histórico |
| **SOURCE_SET_SCOPED** | preenchido | vale só para aquele source-set |

**Precedência de UM nível, sem cascata: `scoped` > `global` > `NEEDS_REVIEW`.**
Determinismo garantido pelos dois índices parciais únicos (o conjunto candidato tem no
máximo 2 elementos) e por `ORDER BY (external_set_id IS NULL) ASC LIMIT 1`. Nunca se
desempata por `created_at`, `updated_at`, `display_order`, `is_active` ou `id`.
A autoridade do escopo é `card_set_external_reference` com `is_active = true` —
**nunca** `catalog_variant_import_job.external_set_id`.

### Banco — 2191–2197 LIVE

| Query | objeto |
|---|---|
| 2191 | coluna `external_set_id`, CHECK de não-vazio, FK composta **MATCH SIMPLE**, dois índices parciais únicos (GLOBAL/SCOPED), índice de lookup |
| 2192 | `internal.resolve_variant_mapping_scope` · `variant_type_mapping_impact` · `variant_type_mapping_decision` |
| 2193 | `internal.apply_variant_type_mapping` — worker único, mapping + propagation na mesma transação |
| 2194 | `public.admin_preview_catalog_variant_import_mapping` — leitura pura |
| 2195 | RPC GLOBAL reconciliada (assinatura/retorno/mensagens intactos) + `..._for_set` nova |
| 2196 | `internal.lookup_variant_type_for_row` + consumidor 1 |
| 2197 | consumidor 2 — corpo derivado mecanicamente do `prosrc` LIVE, provado por md5 |

### Provas

| superfície | resultado |
|---|---|
| Harness **2826** | **35 PASS / 0 FAIL / 35 registros** |
| **P_VECTORS** (SQL) | **10/10** — P1…P10 do arquivo único de vetores |
| Edge — vetores Deno | **12 PASS / 0 FAIL** (P1–P10 + `PARIDADE_INLINE` + `COBERTURA`) |
| Edge — `deno check index.ts` | **PASS** |
| Edge LIVE | `import-card-variants` **v10 · ACTIVE · verify_jwt=true** |
| **B-7** smoke E2E com sessão admin real | **8/8 PASS** |

O 2826 run #1 reprovou 3 casos (P_VECTORS, AE, AF) — **defeitos exclusivos do harness**,
não das migrations: duas fixtures omitiam `external_type` (NOT NULL) e o AE exigia ausência
textual de um nome de tabela que o próprio comentário da 2196 contém. Corrigidos em
GATE-B-HARNESS-CORRECTION-01; run #2 fechou 35/0/35.

### Primeiro override editorial real

```
TCGDEX / base3 / HOLO|GALAXY|NULL|{}  →  HOLO
mapping_id  142528df-085e-47a0-a9e0-21cee4f474ba
actor_id    fe316458-49dd-44e1-aac0-f4b7604ef8f2   (auth.uid() REAL, sessão da aplicação)
scope_kind  SOURCE_SET        external_set_id  base3
rows_reclassified 30          jobs_affected 1
```

Criado pelo caminho público `admin_resolve_catalog_variant_import_mapping_for_set`, com
sessão administrativa real — sem `service_role`, sem JWT fabricado, sem usuário temporário.
Foi ele que fechou os dois últimos itens do B-7 (fronteira scoped alcançável; ator real no
action log), como planejado em GATE-B-E2E-SMOKE-PLANNING-01 (recomendação B).

### Estado LIVE pós-override

| medida | valor |
|---|---|
| `card_variant_type_external_mapping` | **71** = 70 GLOBAL + **1 SCOPED** |
| `catalog_admin_action_log` | 1.223 |
| `card_variant` | 7.413 |
| staging / VALID / NEEDS_REVIEW | 6.340 / 6.145 / 195 |
| BASE3 total / VALID / NEEDS_REVIEW / `card_variant` | 177 / 80 / 97 / **0** |
| BASE3 HOLO\|GALAXY | 30 rows · 30 VALID · **30 HOLO** · 0 GALAXY_HOLO · 0 materializadas |
| modernos (SV3.5/SV5/SV6) com GALAXY_HOLO | **3 — preservados** |

O override reinterpretou exatamente as 30 linhas de `base3` e **não tocou** nos três
`card_variant` canônicos modernos. É o resultado que o vetor P9 previa e que o mapping
global sozinho não conseguia produzir.

### O que este fechamento **não** declara

- **BASE3 não está fechado.** Seguem 92 `NORMAL|GALAXY` em NEEDS_REVIEW + 5 resíduos.
- **`NORMAL|GALAXY` continua ABERTO** — decisão editorial separada, deliberadamente não tomada aqui.
- Variant Types **não** estão completos; Editorial Convergence **não** está encerrada.

O que está fechado é a **foundation de escopo**: o mecanismo que torna a decisão possível.

---

## 0-A. REV-03 — fechamento das provas

Cinco correções localizadas, nenhuma arquitetural:

| # | o que estava errado | correção |
|---|---|---|
| 1 | `bindings.source.SRC_A` era **lido mas não usado** — o runner SQL resolvia a Fonte de `_ctx2826` (TCGDEX fixo), enquanto o Deno lia do JSON. Trocar SRC_A no arquivo mudava um runner e não o outro | as duas Fontes e o `default` saem do arquivo nos **dois** runners; Fonte inexistente é FAIL. `bindSource()` do Deno perdeu o literal `"TCGDEX"` |
| 2 | o stub do Deno **ignorava** `.eq()` e o teste pré-filtrava por Fonte — se alguém removesse `.eq("asset_source_id", …)` da Edge, **P7 continuaria passando** | stub aplica os filtros de verdade; o teste injeta rows de **todas** as Fontes e prova que a função emitiu `.eq("game_id")` e `.eq("asset_source_id")` |
| 3 | identidade de combo comparada por **2 dimensões** (type+foil) em dois pontos do runner | expressão única `pg_temp._map_count()` com as **4** dimensões; `stamp` do vetor passa a ser transportado |
| 4 | caso **U** decidia o universo baseline com JOIN contra a tabela **atual** — job apagado sumia do JOIN, job movido para o alvo saía do universo | `card_set_id_orig` capturado no snapshot; FULL JOIN baseline-puro × atual detecta apagado, novo, alterado e **movido nos dois sentidos** |
| 5 | AE era chamado de "precheck" mas só roda **depois** da 2196 (o harness exige 2196 aplicada) | precheck por hash migrou para dentro da **Query 2196**, antes do primeiro `CREATE OR REPLACE`; AE virou **postcheck puro** e não aceita mais a baseline |

**Extra (§6):** medida a ordem real dos guards no contrato 2192 — `ORIGIN_NOT_NEEDS_REVIEW` (462) vem **antes** de `DUPLICATE` (526). Como a primeira aplicação do worker propaga e reclassifica a própria origem para VALID, a fixture de AF (aplicar duas vezes) **nunca chegaria ao DUPLICATE**. Substituída por INSERT direto do mapping, que preserva a origem em NEEDS_REVIEW e satisfaz todos os guards anteriores.

---

## 0. REV-01 — o que esta revisão mudou

O GATE-A-STAGING-01 entregou o desenho. O **REV-01** fechou as provas que faltavam e corrigiu defeitos reais. Resumo do que mudou:

| item | antes | depois |
|---|---|---|
| **2197** (consumidor 2) | recusada por exigir transcrever ~12.600 caracteres à mão | **criada**, derivada mecanicamente do `prosrc` LIVE e provada por md5 |
| `max(jsonb)` no caso W | defeito latente — PostgreSQL **não tem** `max(jsonb)`; abortaria o harness | dois statements, sem agregado sobre jsonb |
| Casos P/Q | só mediam `B=0` e `C=0` no corpus feliz | fixtures que fazem os guards **disparar** de verdade |
| Caso N | provava só que o preview lê a referência canônica | mismatch **real**, com `SCOPE_MISMATCH` e zero escrita |
| Casos T/U | `updated_at > now() - 1 minute` | snapshot de **row inteira** (`to_jsonb`) tirado antes |
| Caso X | provava só "não sobrou mapping scoped" | confronta **quatro** superfícies contra a baseline |
| Caso O | chamava a RPC pública `admin_preview_...` | exercita o **contrato internal**; a fronteira vira prova estática |
| P_VECTORS | FAIL deliberado e permanente | canal de carga real + bloco `bindings` no JSON |
| Gate | `v_fail = 0` | `v_fail = 0` **e** `v_pass = 33` **e** `count(*) = 33` **e** roster sem ausentes |
| Edge | notas em prosa | **patch aplicável** + teste Deno sobre o código real |

### 0.1 A limitação do canal `execute_sql` — e como a prova foi separada

Medido em 2026-09-14, dentro do canal do Management API:

```
current_user = postgres (NÃO superuser) | auth.uid() = NULL
request.jwt.claims = NULL               | public.is_admin() = FALSE
```

Como `is_admin()` é `EXISTS (SELECT 1 FROM admin_user WHERE id = auth.uid())`, **toda RPC pública protegida por esse guard é inalcançável por este canal**. Não é defeito do desenho — é ausência de sessão de aplicação autenticada no canal.

Decisão aprovada (opção 3): **separar a prova em três**, sem fabricar JWT, sem alterar `request.jwt.claims`, sem admin temporário, sem `service_role`.

| | o quê | onde |
|---|---|---|
| **A** | fronteira pública — assinatura, ACL, `SECURITY DEFINER`, `search_path`, guard, delegação | **estática**, casos AB e AD do 2826 |
| **B** | comportamento — precedência, guards, propagation, counters, action log, rollback | **runtime** pelas `internal.*`, Seções 3/5/7 |
| **C** | fronteira ponta a ponta, no caminho positivo | **sessão admin real da aplicação** — ver §11 |

> O harness **não afirma**, em nenhum ponto, ter executado positivamente uma RPC pública protegida por `is_admin()`.

É o mesmo padrão já aprovado em FIRST_EDITION: **wrapper público fino + worker interno testável**. O caso **AD** existe justamente para provar que o wrapper continua fino — se algum dos três wrappers passar a tocar staging, mapping ou recalcular assinatura residual, ele reprova.

---

## 1. O problema, em uma frase

A TCGdex usa o token `foil: galaxy` com **dois sentidos editoriais incompatíveis** — em `base3` é o acabamento *default* do set inteiro; em `sv03.5`/`sv05`/`sv06` é um tratamento *especial*, declarado pela fonte como uma terceira variante ao lado da holo default da mesma carta. O mapping global não distingue os dois, e não há como corrigir um sem quebrar o outro.

Proveniência provada em EDITORIAL-CONVERGENCE-12: `galaxy` nasce **upstream**; a Edge copia literalmente (`github-source.ts:120` → `index.ts:646`); nenhum branch por era ou Set existe no código.

---

## 2. Contrato aprovado (decisões 1–11 do mandato)

| # | Decisão |
|---|---|
| 1 | `SOURCE_SET_SCOPED` aprovado |
| 2 | `external_set_id` NULL = GLOBAL; preenchido = SOURCE_SET_SCOPED |
| 3 | FK composta `(asset_source_id, external_set_id)` → `card_set_external_reference`, **MATCH SIMPLE**, ON DELETE RESTRICT |
| 4 | Fonte canônica do escopo: `card_set_external_reference`. **Nunca** `catalog_variant_import_job.external_set_id` |
| 5 | UNIQUE: dois índices **parciais** (GLOBAL e SCOPED) |
| 6 | Precedência: scoped > global > NEEDS_REVIEW. Um nível, sem cascata |
| 7 | Coexistência. **Nunca** UPDATE destrutivo do mapping global |
| 8 | Propagation fail-closed → `RECONCILIATION_REQUIRED`. Sem force flag |
| 9 | Action log: **reutiliza** `CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED`. Sem widen |
| 10 | Primeiro override (`TCGDEX/base3 · HOLO·GALAXY → HOLO`) **não criado** nesta rodada |
| 11 | As 92 `NORMAL·GALAXY` permanecem NEEDS_REVIEW |

---

## 3. Arquivos staged

| Ordem | Arquivo | Objeto |
|---|---|---|
| 1 | `2191_add_source_set_scope_to_card_variant_type_external_mapping.sql` | coluna, CHECK, FK composta, `DROP INDEX` do combo + 2 índices parciais + índice de lookup |
| 2 | `2192_create_variant_type_mapping_scope_read_contract.sql` | `internal.resolve_variant_mapping_scope()` · `internal.variant_type_mapping_impact()` · `internal.variant_type_mapping_decision()` |
| 3 | `2193_create_apply_variant_type_mapping_worker.sql` | `internal.apply_variant_type_mapping()` — mapping + propagation na mesma transação |
| 4 | `2194_create_admin_preview_catalog_variant_import_mapping_function.sql` | `public.admin_preview_catalog_variant_import_mapping()` |
| 5 | `2195_reconcile_variant_type_mapping_public_rpcs_for_scope.sql` | `admin_resolve_catalog_variant_import_mapping()` (assinatura intacta) + `..._for_set()` (nova) |
| 6 | `2196_reconcile_variant_type_mapping_lookups_for_scope.sql` | `internal.lookup_variant_type_for_row()` + **Consumidor 1** (backfill de Printing Profile) |
| 7 | `2197_reconcile_variant_type_mapping_printing_lookup_for_scope.sql` | **Consumidor 2** — `admin_resolve_catalog_variant_import_printing_mapping()`, derivada do `prosrc` LIVE |
| 8 | `2826_validate_source_set_scoped_variant_type_mapping.sql` | harness, **35 casos** + runner de vetores |
| — | `test-vectors/variant-type-mapping-scope-vectors.json` | P1–P10 + bloco `bindings`, fonte única dos expected |
| — | `edge/EDGE-STAGING-NOTES.md` | decisões da Edge (v2.0) |
| — | `edge/2026-09-14-variant-source-set-scope.patch` | **patch aplicável** (`git apply`), dois arquivos |
| — | `edge/variant-scope-vectors.test.ts` | runner Deno P1–P10 sobre o código real da Edge |

### 3.1 Query 2197 — proveniência mecânica, provada por hash

O corpo **não foi transcrito**. Foi derivado do `prosrc` LIVE por transformação textual verificada dentro do próprio PostgreSQL, e o arquivo foi devolvido ao banco para comparação:

| | valor |
|---|---|
| baseline LIVE — linhas / chars / md5 | 272 / 12.644 / `2063b34d552766ff8cb220c9c6099f40` |
| resultado — linhas / chars / md5 | 272 / 12.524 / `b98f96a287f7c4d270c4239433bb6f2c` |
| ocorrências de cada trecho antigo | `occ(o1..o4) = 1` cada — nenhuma substituição ambígua |
| resíduo de `vm.` / da tabela de mapping | **0 / 0** |
| **arquivo × esperado** | **md5 idêntico, 0 linhas divergentes** |

Diff autorizado: quatro substituições, todas consequência de **um** diff semântico (o lookup direto passa a usar o helper). Confronto LIVE × canônico 2181: as quatro âncoras batem — **sem divergência, nenhum STOP do §6 disparado**.

### 3.2 Compatibilidade da RPC GLOBAL legada — baseline medida no LIVE

Medido **antes** de aplicar a 2195, é o contrato que ela precisa preservar:

| propriedade | valor medido |
|---|---|
| definições (overload) | **1** |
| assinatura de identidade | `p_row_id uuid, p_variant_type_id uuid` |
| retorno | `TABLE(mapping_id uuid, rows_updated integer, jobs_affected integer)` |
| `prosecdef` | `true` |
| `proconfig` | `["search_path=\"\""]` |
| guard `public.is_admin()` / `auth.uid()` | presentes |
| ACL | `authenticated` = EXECUTE · `anon` = não · PUBLIC = não |
| mensagens históricas | `..._NOT_NEEDS_REVIEW`, `..._DUPLICATE` presentes |

O caso **AB** do harness reexecuta exatamente essas checagens depois da aplicação.

**Numeração conferida fisicamente em 2026-09-14:** último `21xx` usado é **2190**; último `28xx` é **2825**. `2191–2196` e `2826` estão livres em `database/schema/`, `database/migrations/`, `database/validations/` e `database/proposals/`.

---

## 4. Estratégia de assinatura (§5 — era blocker de staging)

| função | assinatura | mudança |
|---|---|---|
| `admin_resolve_catalog_variant_import_mapping` | `(p_row_id uuid, p_variant_type_id uuid)` → `TABLE(mapping_id, rows_updated, jobs_affected)` | **INTACTA.** `CREATE OR REPLACE` (OID e ACL preservados). Corpo delega ao worker com `GLOBAL` |
| `admin_resolve_catalog_variant_import_mapping_for_set` | `(p_row_id uuid, p_variant_type_id uuid)` → 7 colunas | **NOVA.** Opt-in explícito |
| `admin_preview_catalog_variant_import_mapping` | `(p_row_id, p_variant_type_id, p_scope_kind)` → 20 colunas | **NOVA.** Leitura pura |

- **zero função órfã** — a antiga não é dropada, é reescrita no lugar;
- **zero overload ambíguo** — nomes distintos, nenhum parâmetro com DEFAULT;
- **ACL** — `REVOKE PUBLIC/anon` + `GRANT authenticated` nas três;
- **clientes atuais** — assinatura, retorno e **mensagens de erro** preservados literalmente (`..._NOT_NEEDS_REVIEW`, `..._DUPLICATE`, `..._FORBIDDEN`, `..._MISSING_IDS`). Os 4 arquivos do frontend não precisam mudar;
- **`p_actor_id`** — passa `auth.uid()`. Seguro porque `is_admin()` é literalmente `EXISTS (SELECT 1 FROM admin_user WHERE id = auth.uid())`, confirmado no catálogo. Não pode introduzir recusa nova.

---

## 5. Preview × Execute — como a divergência foi eliminada

`internal.variant_type_mapping_decision()` avalia **todas** as pré-condições **e** o impacto A/B/C, e **nunca levanta exceção de regra de negócio**: devolve `ok` / `block_reason` como dado.

- o **preview** devolve esse retorno verbatim;
- o **worker** chama a mesma função e só converte `ok = FALSE` em exceção, antes de qualquer escrita.

É por construção impossível o preview dizer "pode aplicar" e o execute abortar. Sem `p_dry_run` — que criaria overload, duplicação de retorno e uma função cujo nome diz "resolve" e às vezes não resolve.

---

## 6. Classificação A / B / C e o limite de provenance

| classe | definição |
|---|---|
| **A** | job STAGED · `decision_status=PENDING` · `persistence_status=PENDING` · `resulting_variant_id IS NULL` |
| **B** | qualquer alvo fora de A |
| **C** | identidade canônica já materializada pela interpretação anterior |

**O bloqueio dispara por regra de DADO, não de escopo:** só quando o mapping novo **supera uma interpretação efetiva vigente**. Isso é o que preserva a retrocompatibilidade do caminho GLOBAL — que, pelo guard `DUPLICATE` herdado, sempre nasce sobre combo sem interpretação vigente, logo nunca bloqueia.

**Limite de provenance, declarado:** `public.card_variant` **não tem coluna de provenance** (auditado: id, card_id, variant_type_id, variant_order, is_default, created_at, updated_at, printing_profile_id). A única ligação é a inversa, `catalog_variant_import_row.resulting_variant_id`.

- detecção **exata** quando a row de origem existe;
- **ponto cego real** se as rows foram apagadas (precedente: as 410 rows do job CANCELLED em EDITORIAL-CONVERGENCE-09);
- **guard conservador** para o ponto cego: se há supersessão e a detecção exata deu zero, bloqueia com `PROVENANCE_INSUFFICIENT` caso exista qualquer `card_variant` das cards **daquele escopo** com o `variant_type` da interpretação vigente.

O guard pode gerar falso positivo. Aceito de propósito: falso positivo custa um bloqueio que um humano destrava; falso negativo custaria taxonomia mudada por baixo de identidade materializada. Nenhuma provenance foi inventada.

---

## 7. Gabarito seguro do primeiro uso — medido, read-only

`TCGDEX / base3 · HOLO|GALAXY|NULL|{}`:

| | medido |
|---|---|
| universo | **30** |
| `validation_status = VALID` | 30 |
| `decision_status = PENDING` | 30 |
| `persistence_status = PENDING` | 30 |
| `resulting_variant_id IS NULL` | 30 |
| com FIRST_EDITION | 15 |
| **classe A** | **30** · **B: 0** · **C: 0** |
| `card_variant` de BASE3 | **0** |
| `physical_card` global | **0** |

BASE3 permanece 177 / 80 VALID / 97 NEEDS_REVIEW — o override muda a **identidade editorial** das 30 verdes, não a contagem.

---

## 8. Dívidas e blockers para o GATE-B

| # | item | status após REV-01 |
|---|---|---|
| ~~B-1~~ | Query 2197 | **FECHADO.** Criada mecanicamente e provada por md5 (§3.1) |
| ~~B-2~~ | Runner de vetores acoplado ao JSON | **FECHADO.** Canal de carga + bloco `bindings`. Deixou de ser FAIL permanente |
| ~~B-3~~ | Fixtures negativas de P e Q | **FECHADO.** P, Q e Q2 disparam os guards de verdade |
| ~~B-4~~ | Edge | **FECHADO E LIVE.** Patch aplicado nos dois arquivos canônicos; vetores Deno 12/0; `deno check` PASS; `import-card-variants` **v10 ACTIVE**, `verify_jwt=true` |
| **B-5** | **Frontend** | **ABERTO.** 4 arquivos precisam expor escopo e preview. Não bloqueia o banco |
| **B-6** | **Rebase de 2196/2197** | **ABERTO por natureza.** Os corpos partem das versões vigentes (2190, 2181). Detecção de drift: caso **AA** (consumidor 2) e caso **AE** (consumidor 1) — ver §13 para a assimetria entre os dois |
| ~~B-7~~ | Smoke test E2E com sessão admin real | **FECHADO — 8/8.** Preview read-only provado (`error=null`, quadro A/B/C, zero escrita conferida por contagem absoluta) e escrita scoped provada pelo primeiro override real, com `actor_id = auth.uid()` real. Ver §0-Z e §11 |
| **D-1** | *(dívida, não blocker)* | as três funções antigas de propagação seguem com contratos divergentes (nenhuma checa `resulting_variant_id`; duas não filtram `persistence_status`; duas não recalculam counters). O worker novo converge o que está certo; convergir as três é trabalho posterior. **A 2197 preserva a divergência de propósito** — corrigi-la ali seria um quinto diff não autorizado escondido numa Query de escopo |

---

## 11. Gate futuro — smoke test E2E com sessão administrativa REAL

> Registrado aqui, na proposal, **não** na documentação canônica.

O canal `execute_sql` não tem sessão de aplicação autenticada (§0.1). Logo a fronteira pública é provada **estaticamente** neste ciclo. O caminho **positivo** da fronteira precisa de um teste que só a aplicação consegue fazer.

**Antes do technical close LIVE, executar 1 smoke test pela aplicação, com login de admin real:**

1. login real de administrador (sessão da aplicação, não `service_role`);
2. `admin_preview_catalog_variant_import_mapping` executa e devolve o quadro A/B/C;
3. a operação scoped pública (`..._for_set`) é alcançável;
4. o guard `is_admin()` **passa** (caminho positivo, que o harness não cobre);
5. o ator gravado em `catalog_admin_action_log` é o `auth.uid()` **real** do administrador;
6. nenhuma credencial `service_role`;
7. nenhum JWT fabricado;
8. nenhum usuário temporário criado.

**Este teste não pertence ao `execute_sql` e não foi executado neste ciclo.**

---

## 12. Cobertura final do harness 2826 — 35 casos

| seção | casos | o que cobrem |
|---|---|---|
| 1 | A B C D | coluna, CHECK, FK MATCH SIMPLE (global aceita, scoped válida/inválida) |
| 2 | E F G H | unicidade global, scoped, coexistência, dois Sets distintos |
| 3 | I J K L M | precedência scoped > global > NEEDS_REVIEW, isolamento entre Fontes, `is_active` |
| 4 | P_VECTORS | 10 vetores compartilhados: `variant_type` + `matched_scope` + `validation_status`, **todos** os escopos de cada vetor |
| 5 | N N0 O P Q Q2 R S T U V W X | mismatch real, escopo canônico, leitura pura, guards disparando **no decision e no worker**, propagation, preservação bidirecional, counters, action log, atomicidade |
| 6 | Y Z | retrocompatibilidade dos 70 globais, zero resíduo |
| 7 | AA AB AC AD AE AF | 2197 por hash, fronteira pública estática, GLOBAL legado em runtime, wrappers finos, drift do 2196, mensagens do worker em runtime |

**Gate:** `v_fail = 0` **e** `v_pass = 35` **e** `count(*) = 35` **e** roster completo. Caso ausente, duplicado ou extra reprova — um gate que só olha FAIL aprova silenciosamente a cobertura que não rodou.

---

## 13. Proteção de drift — assimetria declarada

O REV-01 afirmava proteção de rebase para "2196/2197". Na prática o caso AA cobria só o consumidor 2. Afirmação maior que a prova; corrigido no REV-02.

| | consumidor 2 (Query 2197) | consumidor 1 (Query 2196) |
|---|---|---|
| função | `admin_resolve_catalog_variant_import_printing_mapping` | `internal.create_card_printing_profile_with_backfill` |
| baseline LIVE | `2063b34d…9f40` · 12.644 · 272 linhas | `4ce5cc4c…3ca4` · 15.868 · 356 linhas |
| precheck | **hash** | **hash** |
| pós-aplicação | **hash** (`b98f96a2…6f2c`) | **propriedades**: zero `vm.`, zero referência à tabela de mapping, ≥1 chamada ao helper, `card_set_id` presente |
| caso | **AA** | **AE** |

**Por que a assimetria.** O corpo da 2197 foi **gerado mecanicamente** do `prosrc` LIVE, então o resultado é previsível byte a byte. O corpo da 2196 foi escrito com comentários explicativos próprios — o `prosrc` pós-aplicação **não** é byte-idêntico ao diff mínimo (que daria `1b506eec…3798` · 15.778 · 357 linhas). Fixar um hash de saída para o consumidor 1 seria inventar um número.

O valor de referência do diff mínimo fica registrado como **referência semântica, não como gate**.

---

## 9. O que esta proposal **não** faz

- não cria o override `base3`;
- não decide as 92 `NORMAL·GALAXY`;
- não confirma BASE3;
- não toca `internal.compute_variant_residual_signature` — o núcleo do eixo Printing fica **intacto**;
- não faz widen do action log (o par já é válido na CHECK, confirmado em 2026-09-14);
- não altera nenhum dos 70 mappings existentes.

---

## 10. Clean install

Ordem de carga, consequência da FK composta:

1. `game`, `asset_source`, `card_variant_type`
2. `card_set` → **`card_set_external_reference`**
3. `card_variant_type_external_mapping` — globais
4. `card_variant_type_external_mapping` — overrides scoped

**Correção importante, acatada do §16 do mandato:** os mappings GLOBAIS (`external_set_id = NULL`) **não** dependem de existir linha correspondente em `card_set_external_reference` — `MATCH SIMPLE` dispensa a checagem quando qualquer coluna da FK é NULL. A **tabela** referenciada precisa existir; as **197 linhas**, não. Só os overrides SCOPED as exigem.

Os 70 mappings atuais nascem GLOBAL. Zero mudança semântica, provado pelo índice GLOBAL ser a expressão do índice removido mais o predicado.

---

## Reconciliação canônica — 2026-09-18

`BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01` classificou cada Query
deste ciclo por **natureza**, e não em bloco. Esta pasta permanece como
**evidência histórica** do staging; a fonte executável passou a ser:

| Query | Natureza | Destino |
|---|---|---|
| `2191` | alteração incremental (coluna + troca de índices) | `database/migrations/2191_...` · dobrada em `database/schema/2140_...` **v2.0** |
| `2192` | criação canônica (read contract de escopo) | `database/schema/2192_...` **v2.0** — agora também abriga `internal.lookup_variant_type_for_row()` |
| `2193` | criação canônica (worker) | `database/schema/2193_...` |
| `2194` | criação canônica (RPC de prévia) | `database/schema/2194_...` |
| `2195` | mista: reescreve a RPC GLOBAL + cria a `_for_set` | `database/migrations/2195_...` · dobrada em `database/schema/2150_...` **v2.0**, que passa a representar **GLOBAL + SOURCE_SET** |
| `2196` | mista: cria `lookup_variant_type_for_row` + altera o worker de Perfil | `database/migrations/2196_...` · o lookup vive em `schema/2192_...` v2.0; a alteração do worker, em `schema/2189_...` v3.0 |
| `2197` | alteração de função canônica | `database/migrations/2197_...` · dobrada em `database/schema/2181_...` **v2.0** |

**Decisão explícita de Fabrício (2026-09-18):** NÃO criar Queries `2203`/`2204`
para os dois objetos que nasceram sem Query canônica própria
(`admin_resolve_catalog_variant_import_mapping_for_set` e
`internal.lookup_variant_type_for_row`). O repositório já admite múltiplos
objetos semanticamente coesos numa mesma Query canônica — os dois foram
incorporados a `2150` v2.0 e `2192` v2.0, respectivamente.

**Nota de segurança registrada:** a `2197`, por ser reconciliação de corpo
(`CREATE OR REPLACE`), não repetia `REVOKE`/`GRANT` — corretos numa migration,
pois os grants já existiam no LIVE. Ao dobrar em `2181` v2.0 o par
`REVOKE ... FROM PUBLIC/anon` + `GRANT EXECUTE ... TO authenticated` foi
**reincorporado** da `2181` v1.2: sem ele, uma instalação limpa nasceria com
grants divergentes do LIVE.

Nada foi reexecutado contra o Supabase nesta rodada — promoção canônica e
fold-in são alteração de arquivo, não execução (ver `database/README.md`,
seção "Queries `CANÔNICA` vs. `MIGRATION`").
