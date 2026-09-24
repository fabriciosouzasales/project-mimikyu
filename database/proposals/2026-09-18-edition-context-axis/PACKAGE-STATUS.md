# STATUS DO PACOTE — classificação A–G

**`WRITE-PATH-STAGING-01`, item 15.** Estado de cada artefato, por classe.
Substitui a leitura rápida de `PENDING-ARTIFACTS.md`, que continua sendo a
autoridade sobre *por que* cada bloqueio existe.

> Instrução literal do mandato: *"Não chamar implementation-ready enquanto
> houver código faltante."* A resposta está na Seção "Veredito", ao final.

> ### ⚠️ ESTE DOCUMENTO ESTÁ PARCIALMENTE SUPERADO (2026-09-19)
>
> A classificação A–G abaixo é o retrato de `WRITE-PATH-STAGING-01` e
> **permanece correta quanto à estrutura**, mas três afirmações dela foram
> superadas por rodadas posteriores. A autoridade corrente sobre *o que pode
> ser executado e em que ordem* é `ROLLOUT-ORDER.md` + `EXECUTION-BATCHES.md`.
>
> | Afirmação abaixo | Estado real hoje | Onde está provado |
> |---|---|---|
> | Classe B — `2230`–`2232` "não têm conteúdo" | **RESOLVIDO.** Os três seeds estão preenchidos: **115 traits · 144 profiles · 196 links · 122 mappings**, cobertura **1.085/1.085** | `SEED-COVERAGE.md` · `2230` v2.1 · `2231` v3.1 |
> | "`T1` continua não autorizado" | **T1 CLOSED.** `2840` v2.0 executado no LIVE, **7/7 PASS**, zero resíduo físico e zero resíduo de ledger. `2209` liberada | `ROLLOUT-ORDER.md`, etapa −1 |
> | "Arquivos no pacote — 45" | **55** (31 `.sql` · 21 `.md` · 2 em `edge/`) | `ls` do diretório |
>
> **Classe G — `2213` — continua em aberto**, e continua sendo bloqueio de
> decisão editorial, não de código. O pacote termina deliberadamente em
> *READY FOR 2213*.

> ### ESTADO DE EXECUÇÃO — Batch 1 parcialmente LIVE (2026-09-19)
>
> | Artefato | Estado | Observação |
> |---|---|---|
> | **`2203`** | **EXECUTADA / LIVE** | ledger registrado · `card_edition_context_trait` existe · RLS/policy/ACL aprovados. **NÃO reaplicar, NÃO rearmar, NÃO editar** — o SQL fica intocado desde a execução, conforme a convenção das canônicas do projeto |
> | `2204` | v1.2 · **PENDING** | 1ª tentativa abortou (`0A000`), zero resíduo físico e de ledger |
> | `2205` | v1.0 · PENDING | inalterada |
> | `2206` | **v2.0** · PENDING | quatro guards, paridade real com 2168 |
> | `2207` | **v4.0** · PENDING | **cinco** guards do mapping + índices parciais em `is_active` |
>
> Retomada: **`2204` → `2205` → `2206` → `2207`**. Detalhe operacional,
> precheck P9 e manifesto de ledger revisado em `EXECUTION-BATCHES.md`.

---

# CURRENT STATE × HISTORICAL MEASUREMENT

**Exigido por `MAPPING-LIFECYCLE-CORRECTION-01`, item 4.** Este documento
acumulou números de rodadas diferentes. A tabela abaixo é a **única autoridade**
sobre o que vale HOJE. Qualquer número divergente no restante deste arquivo, ou
em `PENDING-ARTIFACTS.md` / `editorial/`, é **medição histórica** e só pode ser
lido como registro — nunca como estado.

## CURRENT STATE — vale agora

| Dimensão | Valor CORRENTE | Autoridade |
|---|---|---|
| Traits · Profiles · Links · Mappings | **115 · 144 · 196 · 122** | `2230` v2.1 · `2231` v3.1 · `2232` |
| Cobertura do corpus EC | **1.085 / 1.085** | gate C1 da `2232` |
| Universo vivo de staging (FREEZE) | **1.642 rows** — STAGED / PENDING / NEEDS_REVIEW / PENDING | precheck **P7** |
| Harness `2830` | **144 automáticos** (+4 pendentes de `2213`, +3 manuais), 17 seções | `2830` v6.3 |
| T1 (`2840` `NULLS NOT DISTINCT`) | **CLOSED** — LIVE, 7/7 PASS, zero resíduo físico e de ledger | `ROLLOUT-ORDER.md`, etapa −1 |
| `2203` | **LIVE / SKIP na retomada** | ledger + bloco acima |
| Lifecycle do external mapping | **histórico + no máximo 1 ativo · identidade imutável · `is_active` só TRUE→FALSE · token canônico na entrada** (5 guards) | `2207` v4.0 |
| Índices do mapping | `uq_cecem_active_global` · `uq_cecem_active_scoped` · `ix_cecem_token` | `2207` v4.0 |
| Artefatos executáveis | **23**, todos armados em `COMMIT;` | `ROLLOUT-ORDER.md` |
| Arquivos no pacote | **55** (31 `.sql` · 21 `.md` · 2 em `edge/`) | `ls` |
| **Batch 7** | **CLOSED** — `2219` · `2220` · `2221` · `2222` no ledger; `2834` **PASS** no LIVE | ledger + `LIVE-EXECUTION-06` |
| **`2834`** | **contrato funcional VALIDADO NO LIVE / PASS / CLOSED** — 18/18 casos · 17/17 vetores · 8/8 estados · **0 FAIL · 0 SKIP** · zero resíduo persistente. Validado **via envelope transitório v2.7 auditado**, não por execução direta do arquivo canônico | `LIVE-EXECUTION-06` |
| Runner CANÔNICO do eixo 3 | **`2834` v2.6** (blob `fbabf0bf…`) — autoridade do repositório; **não foi o arquivo literalmente executado** | `BATCH7-2834-LIVE-CLOSEOUT-01` |
| Artefato EXECUTADO no LIVE | **envelope transitório v2.7** (MD5 `78acff39…`), single-statement, rodado **no SQL Editor**. Auditado: seus 9 `EXECUTE` recompõem exatamente o transient v2.6. **NÃO é autoridade e não deve ser incorporado ao runner** — ver item 10 | `BATCH7-2834-LIVE-CLOSEOUT-01` |
| **Batch 8 — EDGE** | **CLOSED** — implementado, deployado, **v15 ACTIVE**, `verify_jwt=true`, postdeploy validado sob FREEZE | `BATCH8-EDGE-CLOSEOUT-01` |
| Eixo 3 na Edge | `services/edition-context.ts` (módulo próprio, exportado) + `buildVariantIdentityKey` / `buildVariantNormalizedData` em `services/database.ts` + integração em `index.ts` | 6 artefatos auditados |
| Paridade Edge × SQL | **136/136** na suíte `services/edition-context.test.ts` — 18 casos × 6 asserções, E15 comportamental, 8/8 estados, contra a MESMA fixture do `2834` | `deno test` |
| Compatibilidade com import REAL | **INTENCIONALMENTE NÃO PROVADA** — ver item 11 | `BATCH8-EDGE-CLOSEOUT-01` |
| FREEZE de importação | **ATIVO** — inalterado pelo Batch 8 **e pelo Batch 8-BIS** | etapa 3 do `ROLLOUT-ORDER.md` |
| **Batch 8-BIS — `2214`** | **CLOSED** — `2214` **v3.1** (blob `30e19523…`) **EXECUTADA NO LIVE** em 2026-09-22, `LIVE VALIDATED` | `BATCH8-BIS-2214-CLOSEOUT-01` |
| `2214` (guard estrito) | **EXECUTADA / LIVE VALIDATED** — guard **job-aware ATIVO** no LIVE. Postcheck read-only **15/15 GATEs PASS**: trigger único · `tgtype = 23` exato · `UPDATE OF` = `normalized_data` + `persistence_status` + `validation_status` · `tgfoid` = OID da função canônica · G1 **e** G2 no corpo · `SECURITY INVOKER` · `proconfig = ARRAY['search_path=""']` · ACL sem `PUBLIC`/`anon`/`authenticated` · 3 triggers canônicos na tabela, nenhum duplicado · **operacional `VALID+PENDING` sem a chave = 0** · **histórico `CANCELLED` 847 / 415 PRESERVADOS** · jobs em voo = 0 · resíduo `GUARD2214-%` = 0 | `BATCH8-BIS-2214-LIVE-POSTCHECK-01` |
| `2214` no ledger | **0 entradas — DIAGNÓSTICO DE RASTREABILIDADE, NÃO "não executada"**. Rodou **direto no SQL Editor**, que não escreve em `supabase_migrations.schema_migrations` — só a CLI escreve. O estado físico é provado pelos catálogos (`pg_trigger` / `pg_proc`), medidos nos 15 gates. Mesma classe da `2202`. Reconciliação do ledger fica **fora** deste closeout | `BATCH8-BIS-2214-CLOSEOUT-01` |
| **Batch 9 — `2224`** | **CLOSED** — guard same-Game do 3º eixo **EXECUTADA NO LIVE** em 2026-09-22, `LIVE VALIDATED`. Blob executado `5bae844bc37022de3bb2ad34e52b5f8ac31da929`, publicado em `2fcd6231`, aplicada **direto no SQL Editor**. POSTCHECK read-only **20/20 GATEs · GLOBAL PASS**: 1 função (`RETURNS trigger` · `plpgsql` · `SECURITY DEFINER` · `proconfig = ARRAY['search_path=""']`) · **ACL owner-only** (owner `postgres`, único grantee com `EXECUTE` = `postgres`) · 1 trigger com `tgfoid` = OID da função, `tgtype = 23`, `UPDATE OF` = `card_id` + `edition_context_profile_id` · topologia = **os 4** triggers canônicos · duplicação cluster-wide **0** · órfão/irresolvível/mismatch **0/0/0** · locks conflitantes **0** · **zero drift** (24.893 → 24.893 · EC não-nulo 0 → 0) | `BATCH9-2224-CLOSEOUT-01` |
| `2224` no ledger | **0 entradas — DIAGNÓSTICO DE RASTREABILIDADE, NÃO "não executada"**. Mesma classe da `2202` e da `2214`: o ledger é escrito pela CLI, nunca pelo motor do Postgres. A prova física são os catálogos (`pg_proc` / `pg_trigger`), medidos nos 20 gates | `BATCH9-2224-LIVE-POSTCHECK-01` |
| **Batch 9 — `2217`** | **EXECUTED / LIVE VALIDATED** (2026-09-23) — EXPAND: cria `internal.write_card_variant` de 7 args (sem DEFAULT) e **preserva** a de 6. Blob `c9abf5d77be5823c888e594f93b754befe8cb991` (inalterado), aplicada pelo SQL Editor. POSTCHECK read-only **via MCP**: **35/36** (estruturais 32/33 · operacionais 3/3) — 2 overloads exatos · ACL owner-only nas duas · owners contínuos (`postgres`) · corpo de 6 args byte-idêntico · confirm ainda chama a de 6 · guard `2224` intacto · voo 0 · 24.893 · EC 0 · locks 0. **Exceção documental de EOL (G6.a):** raw byte identity **DIFFERENT só por CRLF** (`2909175f…` 2.761 B × `478aada8…` 2.707 B, delta 54 = 54 LF) · normalized identity **EXACT** (`478aada8…`) · divergência semântica **NONE** | `BATCH9-2217-LIVE-VALIDATION-CLOSEOUT-01` |
| `2217` no ledger | **0 entradas — DIAGNÓSTICO DE RASTREABILIDADE, NÃO "não executada"**. Mesma classe da `2202`, `2214` e `2224` | `BATCH9-2217-LIVE-POSTCHECK-CORRECTION-01` |
| Próximo estágio | **Batch 9 — `2218` SWITCH — READINESS** · **NÃO EXECUTADA / readiness NÃO iniciada** — exige readiness audit e mandato explícito de Fabrício. **Pré-requisito `2217` SATISFEITO**. Execução futura preferencialmente por **MCP/CLI**, não pelo Dashboard Query Editor | `EXECUTION-BATCHES.md` |

## HISTORICAL MEASUREMENT — registro, NÃO estado

| Número | Onde aparece | Por que não é o estado |
|---|---|---|
| **173 profiles** | `README.md` (tabela A ∪ B, marcada ⟨hist.⟩) · `SEED-COVERAGE.md` (tabela 173 → 144) · `PENDING-ARTIFACTS.md` · `editorial/E1-E2-E3-GATE.md` · linhas abaixo neste arquivo | combinações CANDIDATAS medidas na união, **antes** da curadoria. O corpus fechado é 144 |
| **114 / 126 / 134 automáticos** | histórico de versões do `2830` (v6.0 / v6.1 / v6.2) | superados por 144 (v6.3) |
| **"universo vivo é vazio"** | corrigido em `ROLLOUT-ORDER.md` etapa 5 | premissa errada; o LIVE tem 1.642 |
| **classe B bloqueada por vocabulário** | Seção "Veredito" abaixo | resolvida — os três seeds estão preenchidos |
| **`uq_cecem_global` / `uq_cecem_scoped`** | nota do caso 1.11 no `2830` | renomeados e partializados em `is_active` na `2207` v3.0 |
| **`2207` com 3 guards** | blocos v2.0 preservados no header da 2207 | a v4.0 tem **5** (paridade com a Query 2174) |

> **Regra de leitura:** da linha abaixo até o fim, este documento é o retrato de
> `WRITE-PATH-STAGING-01`. Onde ele divergir da tabela CURRENT STATE, a tabela
> vence.

---

---

## As sete classes

| | Classe | Significado |
|---|---|---|
| **A** | EXECUTÁVEL | SQL completo, gates fail-loud, sem placeholder, sem bloqueio |
| **B** | BLOQUEADO POR DADO | SQL completo; falta o vocabulário editorial (E1/E2/E3) |
| **C** | CORPO NÃO ESCRITO | delta especificado com âncora e invariante; corpo ausente |
| **D** | FORA DO BANCO | TypeScript/Deno — patch e testes da Edge |
| **E** | HARNESS | validação e simulação; não alteram estado de negócio |
| **F** | DOCUMENTAÇÃO NORMATIVA | decide o comportamento dos demais |
| **G** | INEXISTENTE | identificado, numerado, e deliberadamente não escrito |

---

## Classe A — EXECUTÁVEL (19)

### A.1 — Fundação física (14, inalterados nesta rodada)

| Artefato | Papel |
|---|---|
| `2203` · `2204` · `2205` · `2206` · `2207` | trait · profile · N:N · guards de composição · mapping externo |
| `2208` | coluna aditiva em `card_variant` |
| `2209` | `UNIQUE(4) NULLS NOT DISTINCT` — índice normal, sob FREEZE |
| `2210` | `axis_identity_token` + `uq_cvir_row_identity` + shape permissivo |
| `2211` | `resolve_variant_row_axes()` — contrato terminal único de três eixos |
| `2212` v3.0 | resolução OPERACIONAL (universo: **1.642**) |
| `2214` v3.0 | guard de transição job-aware |
| `2215` · `2216` | DROP das identidades antigas (`card_variant` · staging) |
| `2217` | `write_card_variant` v3.0, 7 args, sem DEFAULT |

### A.2 — Caminho de escrita (5, **escritos nesta rodada**)

| Artefato | Base canônica | Linhas de base | Delta central |
|---|---|---|---|
| `2218` | `2145` (519 li) | 270 · 286 · 307 · 314 · 324 · 394 | tri-state dos dois eixos · matching quádruplo · lock determinístico das Cards do lote · `unique_violation` tratada como corrida benigna |
| `2219` | `2193` (324 li) | 175 · 222 | partição A-RESOLVIDO × A-BLOQUEADO · três chaves numa operação · `rows_blocked_edition_context` |
| `2220` | `2192` (563 li) | 90-250 · 299-490 · 509-541 | `block_reason` `EDITION_CONTEXT_UNRESOLVED` · prova negativa de `lookup_variant_type_for_row` |
| `2221` | `2181` (linhas 297-584) | 470 | troca do contrato na CTE `touched` · terceira chave nos outcomes A/B, removida em C |
| `2222` | `2189` (worker 63-447) | 258 · 311 | os DOIS call sites · seleção por Impressão, classificação pelos dois eixos · prova negativa da RPC pública |

**Os cinco eram classe C na rodada anterior.** A classe C está agora vazia
— ver Seção própria.

---

## Classe B — BLOQUEADO POR DADO EDITORIAL (3)

| Artefato | Tem | Falta |
|---|---|---|
| `2230` | estrutura, 6 gates, lista congelada dos 21 tokens de B | os 115 `code`/`name` |
| `2231` | estrutura, 7 gates, selagem via `2206` | a composição dos 173 perfis |
| `2232` | estrutura, gates C1/C2/C3, guard H2 de `set-logo` | os mappings externos |

Os três **abortam** se o vocabulário estiver vazio — nenhum PASS por fixture
inexistente. Detalhe em `SEED-COVERAGE.md`.

**Não estão no caminho crítico da estrutura.** A fundação inteira
(`2203`–`2211`, `2214`–`2217`) executa sem eles. O vocabulário é
pré-requisito da *resolução editorial das 1.642*, não da estrutura física.

**Novo nesta rodada:** os seeds passam a ser pré-requisito também do
**deploy da Edge**. Sem eles, `activeTraitsByGlobalToken` nasce vazio e toda
linha cai em `RESOLVED_NO_EDITION_CONTEXT` — tecnicamente válido,
semanticamente uma afirmação falsa em massa. Registrado no rodapé do patch.

---

## Classe C — CORPO NÃO ESCRITO

**VAZIA.**

Era a classe que sustentava o veredito "não implementation-ready" da rodada
anterior. Os cinco artefatos que a compunham (`2218`–`2222`) foram escritos
por inteiro nesta rodada, como `CREATE OR REPLACE` de estado final —
nenhum pseudo-SQL, nenhum placeholder, nenhuma descrição no lugar de
implementação.

Cada um reemite integralmente o corpo canônico de base, preservando byte a
byte os guards, as mensagens de erro e os gates de reconciliação que não
pertencem ao delta, e carrega:

- pré-condições que abortam se a base não estiver no estado esperado
  (inclusive verificação de assinatura, para impedir sobrecarga silenciosa);
- postchecks que provam, **no banco**, que o contrato antigo não é mais
  chamado (`prosrc NOT LIKE`), que a ACL não mudou e que não há sobrecarga;
- `BEGIN; … ROLLBACK;` — a troca por `COMMIT` é ato de Fabrício, não do
  arquivo.

---

## Classe D — FORA DO BANCO (2)

| Artefato | Estado |
|---|---|
| `edge/import-card-variants.patch` rev 3.0 | **D3 FECHADO + fail-closed corrigido.** 5 diffs, 8 estados, tabela de paridade linha a linha |
| `edge/edition-context.test.ts` rev 3.0 | runner dos **17 vetores** da fixture + 5 casos meta. Nenhum expected local |
| `test-vectors/edition-context-axis-vectors.json` | **fixture canônica**, 17 vetores, 8/8 estados, `expected` só aqui |
| `2834_validate_edition_context_axis_vectors.sql` | **runner SQL** da mesma fixture (classe E) |

### O que mudou nesta rodada

**Correção de premissa.** A rev 1.0 afirmava que o eixo 3 seria consumido do
servidor, não espelhado em TypeScript. **Falso para esta função**: o
cabeçalho da PHASE C (`index.ts:128-134`) declara que o eixo de Impressão JÁ
é um espelho em memória, por decisão arquitetural, com reconciliação no
servidor como rede de segurança.

**D3 decidido: espelho em memória (opção A)**, simétrico à PHASE C —
`+3 preloads por JOB`, nunca por linha. As alternativas (RPC por linha; RPC
em lote) estão comparadas e recusadas no patch, com o motivo de cada uma.

**Defeito semântico corrigido nos dois arquivos.** A rev 1.0 gravava
`edition_context_profile_id` sempre que a Impressão resolvia. Isso afirma
"resolvido sem contexto" sobre linha de contexto indeterminado — o mesmo
defeito que a `BACKFILL-SEMANTICS-CORRECTION-01` eliminou do lado SQL. O
gate passa a ser sobre os DOIS eixos: as três chaves saem juntas ou nenhuma
sai, espelhando os outcomes A/B/C de `2221`/`2222`.

**rev 3.0 — o que a rev 2.0 ainda errava.** O índice fazia
`if (!m.is_active) continue;` e o vocabulário tinha 2 estados. A `2211` tem
**8** e é **fail-closed**: token conhecido sem routing ativo devolve
`NEEDS_REVIEW_INACTIVE_EC_MAPPING` e não volta ao resíduo (2211:127-144,
171-184). A rev 2.0 deixava o token cair em Finish — o achado A3
reintroduzido pelo TypeScript.

**Paridade medida, não afirmada.** Os dois runners consomem a fixture única.
Prova de que ela discrimina: rodando o roteador da **rev 2.0** contra os
mesmos 17 vetores, **6 reprovam** (E6, E7, E12, E13, E14, E16) — exatamente
os casos que o mandato mandou cobrir.

---

## Classe E — HARNESS (6)

| Artefato | Cobertura |
|---|---|
| `2830` v6.0 | 114 casos automáticos em 12 de 14 seções · 4 pendentes de `2213` · 3 manuais |
| **`2834`** v2.6 | **runner SQL da fixture compartilhada do eixo 3** — **17 vetores / 18 casos, ZERO SKIP**. Monta fixture sintética de Impressão por vetor, em subtransação PL/pgSQL desfeita por sentinel `P2834`. **LIVE / PASS / CLOSED** na `LIVE-EXECUTION-06`: 18/18 PASS, 17/17 vetores, 8/8 estados, 0 FAIL, 0 SKIP, zero resíduo. Chegar lá custou seis tentativas — `-01` `raw_data.type` ausente · `-02` `family` NULL · `-03` colisão de `display_order` · `-04` `external_token` inexistente no mapping de EC · `-05` STOP semântico (2 PASS / 16 FAIL) por JSON `null` na montagem do raw; ver itens 4 a 7, 9 e 10 dos bloqueios. O item 8 registra um sexto defeito (lifecycle do trait inativo em E4) **encontrado por auditoria, não por execução** |
| `2831` v2.0 | simulação da decomposição legada; termina em `ROLLBACK` |
| `2832` v3.0 | 14 casos da resolução operacional |
| `2833` v2.0 | 11 gates; matriz de state machine job-aware que **mede** em vez de afirmar |
| `2840` | probe T1 — `apply_migration` × `NULLS NOT DISTINCT` (**não autorizado** a rodar) |

---

## Classe F — DOCUMENTAÇÃO NORMATIVA (14)

| Documento | Autoridade sobre |
|---|---|
| `README.md` | índice do pacote e ordem de leitura |
| `DAG.md` | dependências reais entre artefatos |
| `ROLLOUT-ORDER.md` | ordem de execução e janelas de FREEZE |
| `OPERATIONAL-BOUNDARY.md` | o que é row operacional — **1.642** × **0** confirmáveis |
| `LINEAGE-STRATEGY.md` | proibição de estado híbrido; requisitos L1–L4 |
| `CONCURRENCY-DESIGN.md` | onde mora o lock e por que não no writer |
| `IMPACTED-CONTRACTS.md` | os 7 call sites em 5 funções |
| `MIGRATION-MAP-365.md` | 285 + 80 |
| `HOLD-MANIFEST.md` | 107 + 379 + 57 |
| `SEED-COVERAGE.md` | A∪B = 115 traits / 173 perfis |
| `PENDING-ARTIFACTS.md` | por que cada bloqueio existe |
| `TOOLING-PROOF.md` | limites de `apply_migration` |
| **`READ-MODELS-AUDIT.md`** | **novo** — classe A × B dos consumidores de leitura |
| **`PACKAGE-STATUS.md`** | **novo** — este documento |

---

## Classe G — INEXISTENTE POR DECISÃO (1)

| Artefato | O que seria | Por que não existe |
|---|---|---|
| `2213` | migração de linhagem das **285** `READY_UNCONDITIONED` | Exige decidir, carta a carta, qual Contexto de Edição cada uma recebe — decisão **editorial**, de Fabrício, não derivável de dado. `LINEAGE-STRATEGY.md` fixa os requisitos L1–L4 que o artefato terá de cumprir (identidade completa atualizada atomicamente com a Variant, proibição de estado híbrido). Quatro casos da Seção L do `2830` ficam pendentes dele. |

Escrever `2213` agora seria fabricar decisões editoriais — a mesma classe de
erro do backfill `VALID → JSON null` que a
`BACKFILL-SEMANTICS-CORRECTION-01` eliminou.

---

## Contagem

| Classe | Artefatos |
|---|---:|
| A — executável | **19** |
| B — bloqueado por dado | 3 |
| C — corpo não escrito | **0** |
| D — fora do banco | 2 |
| E — harness | 6 |
| F — documentação | 14 |
| G — inexistente por decisão | 1 (não é arquivo) |
| **Arquivos no pacote** | **45** |

---

## Veredito

**O caminho de escrita está completo.** A classe C — a razão declarada do
"não implementation-ready" da rodada anterior — está vazia. Os cinco
contratos SQL existem como estado final auditável, e o patch da Edge fechou
o item D3 que estava aberto.

**O pacote ainda NÃO é implementation-ready**, por dois motivos, e apenas
dois:

1. **Classe B — vocabulário editorial (E1/E2/E3).** Os seeds `2230`–`2232`
   não têm conteúdo. Sem eles, o deploy da Edge produz afirmações falsas em
   massa e a resolução das 1.642 não tem para onde apontar. **Bloqueio de
   dado, não de código.**

2. **Classe G — `2213`.** As 285 linhas legadas não têm caminho de migração,
   e quatro casos do harness dependem dele. **Bloqueio de decisão editorial,
   não de código.**

3. **~~Paridade parcial no runner SQL~~ — RESOLVIDO em `BATCH7-2834-FULL-COVERAGE-CORRECTION-01`.**

   *Registro do que era:* o `2834` v1.0 executava **14 dos 17** vetores. `E3`,
   `E16` e `E17` exigem fixture do eixo de **Impressão** e ficavam **SKIP**.
   O cabeçalho da v1.0 afirmava que a fixture de Impressão era criada; o corpo
   não a criava. E o gate final só falhava para `FAIL > 0`, de modo que
   *14 PASS / 0 FAIL / 3 SKIP* encerrava sem exceção.

   Custo real medido: dois estados do vocabulário — `NOT_EVALUATED` e
   `NEEDS_REVIEW_NO_EC_PROFILE` — têm **um único vetor cada** (`E16` e `E3`),
   logo a perda não era de 3/17 dos vetores e sim de **2/8 do vocabulário**.

   *Estado agora:* o `2834` **v2.1** monta a fixture sintética de Impressão por
   vetor, dentro da mesma transação com `ROLLBACK`, e cobre **17 vetores /
   18 casos**, com **zero SKIP planejado** e **8/8 estados**. Os números são
   derivados do JSON em tempo de execução, nunca constantes no SQL. O gate S3
   falha se houver FAIL, se houver SKIP, se a contagem de casos divergir da
   fixture, se algum `vector_id` do roster ficar sem caso PASS, ou se algum
   estado do vocabulário ficar sem cobertura PASS.

   *Correção `BATCH7-2834-VECTOR-SUBTRANSACTION-CORRECTION-01` (v2.0 → v2.1):*
   o isolamento entre vetores da v2.0 era feito por `DELETE`, o que é
   **impossível** — os Perfis sintéticos precisam estar selados antes da
   medição, e depois do selo `card_printing_profile_trait` e
   `card_edition_context_profile_trait` rejeitam a filha (guard `BEFORE DELETE`
   de composição selada) enquanto a FK para o pai é `ON DELETE RESTRICT`. Não
   há ordem válida. A v2.1 roda cada vetor numa **subtransação PL/pgSQL**
   encerrada por `RAISE EXCEPTION ... USING ERRCODE = 'P2834'` deliberado,
   capturado por `EXCEPTION WHEN SQLSTATE 'P2834'` — sem `WHEN OTHERS`, de
   modo que qualquer exceção real continua abortando o runner. O SQLSTATE não
   é a identidade: a mensagem é determinística e específica do vetor
   (`VEC2834_VECTOR_ROLLBACK:<vector_id>`), fixada antes de a subtransação
   abrir, e o handler a compara com `SQLERRM` por **igualdade exata** — um
   `P2834` vindo de qualquer outra origem executa `RAISE;` e propaga
   intacto. Fail-closed. Os resultados
   são acumulados em JSONB na memória (que sobrevive ao rollback do bloco) e
   só então materializados em `_res2834`, criada fora da subtransação. Os
   blocos 2.0 e 2.4 deixam de apagar e passam a ser **gates de zero resíduo**
   sobre as dez tabelas sintéticas, na entrada e na saída de cada vetor.
   Nenhum FAIL vira exceção; selos, guards, FKs e imutabilidade permanecem
   exatamente como estão.

   > **SUPERADO (`BATCH7-2834-LIVE-CLOSEOUT-01`).** Esta linha dizia *"o
   > `2834` continua NÃO EXECUTADO com sucesso"* e que os números eram
   > *"capacidade do runner, não um resultado medido"*. Isso valia até a
   > `LIVE-EXECUTION-05`. Desde a **`LIVE-EXECUTION-06`** o `2834` está
   > **LIVE / PASS / CLOSED** e os números são **resultado medido**: 18/18
   > casos, 17/17 vetores, 8/8 estados, 0 FAIL, 0 SKIP. O critério de
   > `EXECUTION-BATCHES.md` — *"`2834` com todos os vetores PASS"* —
   > permaneceu intacto e foi **satisfeito**. Ver item 10.

4. **`BATCH7-2834-LIVE-EXECUTION-01` → STOP** *(HISTÓRICO — fechado pela
   `LIVE-EXECUTION-06`; registro preservado)*

   *Erro:* `COMPUTE_VARIANT_RESIDUAL_SIGNATURE_MISSING_TYPE: raw_data.type
   ausente.`

   *Causa:* o harness v2.1 construía `raw_data` sem `type`, embora o contrato
   de Impressão exija esse campo — `internal.compute_variant_residual_
   signature()` normaliza `raw_data.type` como primeira operação e levanta
   exceção se vier NULL ou vazio. O defeito nasceu com o gate de medição
   prévia introduzido na v2.0; a v1.0 não chamava essa função.

   *Impacto:* **ZERO persistente**, comprovado por postcheck read-only —
   zero resíduo `VEC2834*` nas dez tabelas, nenhuma temp table remanescente,
   baseline operacional **1642** com Edition Context **1092 / 550 / 0**
   intacto, CANCELLED **847 / 415** intacto, catálogos intactos
   (EC 115/144/122 · Printing 9/11/10), `2214` **= 0** no ledger. O erro
   ocorreu dentro do `BEGIN … ROLLBACK`, no primeiro vetor.

   *Correção:* `v_raw` passa a incluir `'type', 'normal'` — precedente
   canônico dos harnesses `2824` e `2827` — e a Seção 2.2 ganha o gate
   `PRINTING_TYPE_SCAFFOLD_MISMATCH`, que exige `residual_type = 'NORMAL'` e
   prova que o campo técnico permaneceu inerte. `size='STANDARD'` preservado.
   **Fixture JSON não alterada**: `type` é scaffold do raw externo, não
   dimensão do contrato compartilhado do eixo 3.

   *Estado:* a **v2.2 foi executada** na `LIVE-EXECUTION-02` e **não abortou
   por `type`**. Isso ainda NÃO é prova de que a correção funciona: o defeito
   de `family` (item 5) ocorre no bloco 2.1, **antes** de o gate de Impressão
   ser alcançado, de modo que `compute_variant_residual_signature()` nunca
   chegou a ser chamada. A correção de `type` permanece **não exercitada**.

5. **`BATCH7-2834-LIVE-EXECUTION-02` → STOP** *(HISTÓRICO — fechado pela
   `LIVE-EXECUTION-06`; registro preservado)*

   *Erro:* SQLSTATE **23502** — `null value in column "family" of relation
   "card_edition_context_trait" violates not-null constraint`.

   *Causa:* os DOIS INSERTs sintéticos de Edition Context Trait — o de traits
   declarados e o de traits citados só em mappings/profiles — omitiam
   `family`, coluna **NOT NULL sem default** do schema atual, com domínio
   fechado por CHECK (`EVENT`, `PLACEMENT`, `ROLE`, `DECK_PLAYER`, `CHANNEL`,
   `PROGRAM`, `CAMPAIGN`, `ARTWORK_MARK`).

   *Impacto:* **ZERO persistente**, comprovado por postcheck read-only —
   zero resíduo `VEC2834*` nas dez tabelas, nenhuma temp table remanescente,
   baseline operacional **1642** com Edition Context **1092 / 550 / 0**
   intacto, CANCELLED **847 / 415** intacto, catálogos intactos
   (EC 115/144/122 · Printing 9/11/10), `2214` **= 0** no ledger. O erro
   ocorreu no primeiro INSERT do primeiro vetor, dentro da subtransação.

   *Estado:* correção **v2.3** — superada; fechada na `LIVE-EXECUTION-06` (v2.6). Os dois
   caminhos passam a declarar `family = 'ARTWORK_MARK'`. **Fixture JSON não
   alterada**: `family` é scaffold físico do schema — não participa da
   identidade (PK é `(id)`; a unicidade de negócio é `uq_cect_game_code`), não
   participa de `traits_signature` (`uuid[]` de `trait_id`), não é lida por
   `resolve_variant_row_axes()` nem por `compute_variant_residual_signature()`
   nem por qualquer guard/selo de Edition Context, e não é usada pelo Edge.
   A escolha de `ARTWORK_MARK` foi verificada contra `uq_cect_game_family_order`
   — UNIQUE em `(game_id, family, display_order)`: a faixa `>= 1000` está
   vazia para POKEMON em todas as famílias (máximo em ARTWORK_MARK = 30), e os
   `display_order` sintéticos reiniciam a cada vetor porque a subtransação
   desfaz os anteriores.

6. **`BATCH7-2834-LIVE-EXECUTION-03` → STOP** *(HISTÓRICO — fechado pela
   `LIVE-EXECUTION-06`; registro preservado)*

   *Erro:* SQLSTATE **23505** — `duplicate key value violates unique
   constraint "uq_cecp_game_order"`, chave `(game_id POKEMON,
   display_order 1000)`.

   *Causa:* a v2.3 usava o literal **1000** como base de `display_order` nos
   **quatro** objetos sintéticos. O catálogo real de Perfis de Edition Context
   do POKEMON já ocupa 1000 — `EVENT_WORLDS_2004__PLACEMENT_TOP_16` — e vai
   até **1440**.

   *Impacto:* **ZERO persistente**, comprovado por postcheck read-only —
   zero resíduo `VEC2834*` nas dez tabelas, nenhuma temp table remanescente,
   baseline operacional **1642** com Edition Context **1092 / 550 / 0**
   intacto, CANCELLED **847 / 415** intacto, catálogos intactos
   (EC 115/144/122 · Printing 9/11/10), `2214` **= 0** no ledger.

   *Estado:* correção **v2.4** — superada; fechada na `LIVE-EXECUTION-06` (v2.6). A correção
   **fecha a CLASSE**, não apenas o objeto que falhou: as quatro tabelas
   sintéticas têm UNIQUE sobre `display_order` e as quatro usavam o mesmo
   literal — só o EC Profile colidiu porque só nele o dado real alcança 1000;
   as outras três estavam a salvo por acidente de população, não por desenho.
   Agora cada uma tem base **medida** (`MAX(display_order)+1` do próprio
   escopo), calculada uma vez antes do laço, com gate preventivo fail-closed
   sobre o slot inicial. **Sem nova faixa mágica** e **sem captura de 23505**:
   uma corrida concorrente ainda aborta o runner. **Fixture JSON não
   alterada** — `display_order` é scaffold físico, como `type` e `family`:
   não participa da identidade nem de `traits_signature`, e nenhum dos dois
   contratos o lê (medido: `prosrc ILIKE '%display_order%'` = false).

7. **`BATCH7-2834-LIVE-EXECUTION-04` → STOP** *(HISTÓRICO — fechado pela
   `LIVE-EXECUTION-06`; registro preservado)*

   *Erro:* SQLSTATE **42703** — `column "external_token" of relation
   "card_edition_context_external_mapping" does not exist`.

   *Causa:* **vazamento de modelo entre Edition Context e Printing.** O INSERT
   do mapping de Edition Context escrevia `external_token`, coluna que existe
   apenas em `card_printing_external_mapping`. Não é erro de digitação: é a
   assinatura de uma tabela aplicada a outra. O eixo 3 escopa por Card Set
   (`external_set_id`); o eixo de Printing identifica por token externo
   (`external_token`). As duas tabelas **não compartilham assinatura** —
   `card_edition_context_external_mapping` não tem `external_token`, e
   `card_printing_external_mapping` não tem `external_set_id`. Medição nos
   artefatos: `2207` = 0, `2232` = 0, `2211` = 0, Edge = 0, `2172` = 2. O
   harness era o **único** artefato do eixo 3 a mencionar o token.

   *Impacto:* **ZERO persistente**, comprovado por postcheck read-only
   aprovado — zero resíduo `VEC2834*` nas dez tabelas, nenhuma temp table
   remanescente, baseline operacional **1642** com Edition Context
   **1092 / 550 / 0** intacto, CANCELLED **847 / 415** intacto, catálogos
   intactos (EC 115/144/122 · Printing 9/11/10), `2214` **= 0** no ledger.

   *Estado:* correção **v2.5** — superada; fechada na `LIVE-EXECUTION-06` (v2.6). Remove
   `external_token` e o segundo `v_tok` **somente** do INSERT de Edition
   Context; o INSERT de `card_printing_external_mapping` **continua**
   escrevendo `external_token`, onde a coluna existe e é NOT NULL. Contagem no
   runner v2.5: EC = 0, Printing = 1.

8. **Blocker preventivo — lifecycle do trait inativo (E4)**
   *(encontrado pela `MODELING-RECONCILIATION-01`, **antes** de aparecer em
   execução LIVE — nunca chegou a produzir um STOP próprio; **HISTÓRICO**,
   fechado pela `LIVE-EXECUTION-06`)*

   A auditoria mecânica do DML do runner contra o catálogo canônico — a v2.4
   tinha 11 DML, todos INSERT; a v2.5 tem os **12 DML atuais (11 INSERTs +
   1 UPDATE)**, sendo o UPDATE o passo de lifecycle descrito abaixo —
   encontrou um defeito que nenhuma execução tinha alcançado: o vetor **E4**
   não era montável pela ordem da v2.4. E4 declara `T_OFF` com
   `is_active:false` e o coloca em `PF_A`; a v2.4 criava o trait já inativo e
   em seguida inseria a N:N, onde `trg_cecpt_trait_active` (BEFORE INSERT em
   `card_edition_context_profile_trait`) levanta
   `EDITION_CONTEXT_TRAIT_INACTIVE`. A `LIVE-EXECUTION-04` abortou **antes**
   desse ponto, no 42703 — por isso o defeito não apareceu lá.

   *Nem a fixture nem o guard estão errados.* E4 representa um profile
   **histórico** cujo trait foi inativado **depois** de composto, e existe para
   travar a ordem de avaliação da `2211` (trait inativo tem precedência sobre a
   busca de profile). Errada era a ordem de montagem do harness.

   *Estado:* corrigido na **v2.5**, que monta na ordem do domínio — trait
   **ativo** → profile → N:N → selo (`trg_cecp_seal` IMMEDIATE → prova →
   DEFERRED) → aplica o `is_active` declarado → **gate de estado** → mappings →
   medição. **Nenhum trigger desabilitado, nenhum constraint alterado, nenhum
   bypass.** O guard segue recusando exatamente o que sempre recusou. O gate
   novo (`EC_TRAIT_DECLARED_STATE_MISMATCH`) é estrutural e fail-closed:
   fixture física incorreta aborta o harness em vez de chegar à medição
   disfarçada de FAIL de caso. Traits **implícitos** — citados só em
   mapping/profile e ausentes de `ec_traits` — continuam nascendo ativos e
   ficam fora do gate. **Fixture JSON não alterada.**

9. **`BATCH7-2834-LIVE-EXECUTION-05` → STOP SEMÂNTICO** *(HISTÓRICO — fechado
   pela `LIVE-EXECUTION-06`; registro preservado)*

   **Natureza diferente de todos os anteriores.** Não houve aborto estrutural:
   o runner v2.5 atravessou S0, S1, S2, montou os 17 vetores, mediu **18 de 18
   casos com zero SKIP** e parou no gate de cobertura do S3 com **2 PASS /
   16 FAIL** — passaram apenas E1 e E17.

   *Causa:* **bug do runner**, demonstrado pelo `SEMANTIC-DIAGNOSTIC-01`. O
   bloco 2.2 monta cada caso com `jsonb_build_object(…, 'raw_before',
   v_vec->'raw_before_printing', …)`. Para os vetores que não declaram essa
   chave, o valor é materializado como **JSON `null`** — que não é SQL NULL.
   O predicado `IF v_case->'raw_before' IS NOT NULL` era portanto **TRUE para
   todos**, e E1–E16 entravam no ramo exclusivo de E17, montando o raw a
   partir de um objeto inexistente: subtype e stamp desapareciam, e em
   E3/E16 o `c_pr_fix_token` nunca era acrescentado — daí a Impressão medir
   `RESOLVED_NO_PRINTING` contra o que a fixture declarava. Os 16 `detail`
   recuperados são todos `PRINTING_RESIDUAL_MISMATCH` ou
   `PRINTING_FIXTURE_MISMATCH`. E1 passou por acidente (seu `expected` é
   vazio); E17 passou legitimamente (é o único vetor com
   `raw_before_printing`).

   *Método, para o registro:* a `SEMANTIC-FORENSICS-01` chegou a duas
   hipóteses e **não conseguiu separá-las estaticamente** — declarou "causa
   raiz NÃO demonstrada" em vez de eleger a mais plausível. Quem fechou a
   questão foi o diagnóstico, transportando pela própria exception os
   `detail` que o runner já calculava e que os NOTICEs não entregavam.

   *Impacto:* **ZERO persistente**, comprovado por postcheck read-only depois
   da EXECUTION-05 e de novo depois do diagnóstico — zero resíduo `VEC2834*`
   nas dez tabelas, 1642 operacional, tri-state **1092 / 550 / 0**, CANCELLED
   **847 / 415**, catálogos EC 115/144/122 e Printing 9/11/10, `2214` = 0.

   *Estado:* **v2.6 é a versão CANÔNICA**, e seu **contrato funcional foi
   VALIDADO NO LIVE** na `LIVE-EXECUTION-06` — via o envelope transitório
   **v2.7**, auditado como recomposição exata do corpo funcional v2.6. O
   arquivo v2.6 não foi o arquivo literalmente executado; ver item 10. A seleção de
   ramo passa a usar `jsonb_typeof(…) = 'object'` nos dois sítios que
   consultavam a chave, mais um gate fail-closed `RAW_BEFORE_TYPE_INVALID`
   (admissíveis: `object`, `null`). **Fixture não alterada**, `expected` não
   alterado, `2176`/`2211`/Edge não tocados.

   > **Nada foi revalidado.** Os 16 FAIL estão *explicados*, não *resolvidos*:
   > a fixture e o contrato do eixo 3 continuam sem prova. Só uma execução
   > nova da v2.6 dirá o que o contrato realmente faz — e ela pode muito bem
   > revelar divergências reais que o bug do harness estava mascarando.

10. **`BATCH7-2834-LIVE-EXECUTION-06` → PASS / CLOSED** — **a execução
    bem-sucedida.** Encerra os itens 4 a 9.

    *Resultado LIVE:* `Success. No rows returned`. O S3 permaneceu intacto e
    fail-closed, então alcançar o fim sem exception **é** a prova: o gate só
    deixa passar com **18/18 casos PASS · 17/17 vetores cobertos · 8/8 estados
    cobertos · 0 FAIL · 0 SKIP**.

    *Postcheck independente, 8/8:* resíduo `VEC2834*` **0** · temp tables **0**
    · operacional **1.642** · EC UUID/NULL/ABSENT **1.092/550/0** · CANCELLED
    total/VALID+PENDING **847/415** · catálogos EC **115/144/122** · Printing
    **9/11/10** · ledger `2214` **0**. **Zero resíduo persistente.**

    *Canal de execução — o que de fato aconteceu.* **A execução final
    bem-sucedida ocorreu NO SQL EDITOR do Supabase.** O SQL Editor não foi
    descartado; o que falhou foi o **modo multi-statement**, que não preserva
    TEMP TABLEs entre statements — provado por probe mínimo independente do
    `2834` (`42P01 relation "_mmkyu_tx_probe" does not exist`). O caminho
    `psql` + Session Pooler chegou a ser investigado e **foi abandonado**.
    Em seguida, **dois probes independentes** provaram que o SQL Editor
    suporta **single-statement** e **`DO` aninhado**, e foi por aí que a
    execução passou: o **envelope single-statement v2.7**, que embrulha o
    mesmo SQL em `EXECUTE` sem alterar uma linha de lógica funcional. O
    **JIT/Temporary Access foi encerrado ANTES da execução final** —
    `mappings = 0`, `state = disabled`, `appliedSuccessfully = true`.

    > ### ARTEFATO CANÔNICO × ARTEFATO EXECUTADO — não confundir
    >
    > | Artefato | Papel |
    > |---|---|
    > | **`2834` v2.6** — blob `fbabf0bf7409d8f6078c215d6250beed5b9dbd48` | **RUNNER CANÔNICO / autoridade do repositório.** Única autoridade sobre a semântica do harness. **NÃO foi o arquivo literalmente executado** |
    > | **Transient v2.6** — MD5 `21f81b065a1690dded7d9cd248bc7e0c` · SHA-256 `4743baf1…fc924` | **corpo funcional auditado** — a v2.6 com a fixture materializada no placeholder; reversível byte a byte ao v2.6 |
    > | **Envelope v2.7** — MD5 `78acff393a1c2131867c7217bc064130` · SHA-256 `8e98696d…448a43` | **ARTEFATO OPERACIONAL TRANSITÓRIO — este foi o efetivamente EXECUTADO** no SQL Editor. A auditoria provou que, removido o wrapper, seus **9 `EXECUTE`** recompõem **exatamente** o transient v2.6 funcional |
    >
    > **Leitura correta do resultado:** o PASS no LIVE **valida o contrato
    > funcional canônico da v2.6** — mas o arquivo v2.6 não foi o arquivo
    > literalmente executado. A ponte entre os dois é a auditoria de
    > recomposição do v2.7, não uma execução direta do canônico.
    >
    > **O v2.7 NÃO vira autoridade canônica** e **não deve ser incorporado ao
    > runner**, promovido, nem versionado como tal. Qualquer alteração de
    > fixture ou de semântica do harness exige mandato novo.

11. **`BATCH8-EDGE` → IMPLEMENTED / DEPLOYED / POSTDEPLOY VALIDATED / CLOSED** —
    o terceiro eixo entrou na Edge `import-card-variants`, **v15 ACTIVE**,
    `verify_jwt=true`.

    **Artefatos (6):** `services/edition-context.ts` *(novo — PHASE C-bis em
    módulo próprio e exportado; `index.ts` chama o servidor no topo e não
    exporta nada, então uma função declarada lá não poderia ser importada por
    um teste sem subir um listener)*; `services/database.ts` *(+`NO_EDITION_
    CONTEXT_KEY`, `buildEditionContextKeyPart`, `buildVariantIdentityKey`,
    `buildVariantNormalizedData`, 3 preloads, `listExistingCardVariantsMap`
    com identidade de 4 componentes)*; `index.ts` *(3 preloads no mesmo
    `Promise.all`, índice por JOB, roteamento só após Impressão, resíduo
    pós-dois-eixos ao Variant Type, `isValid` de três eixos, dedupe/matching
    pelo helper único, `normalized_data` pelo helper puro, 2 contadores
    declarados/incrementados/publicados)*; `services/edition-context.test.ts`
    *(novo — **zero réplica**, importa o código real)*; o antigo
    `edge/edition-context.test.ts` **removido** *(era segunda autoridade
    executável, com réplica declarada do roteador: provava a cópia, não a
    Edge)*; `edge/import-card-variants.patch` **reclassificado como documento
    de desenho** *(não é aplicável por `git apply`; a alegação de "unified diff
    aplicável" era falsa e foi removida)*.

    **Provas offline:** `deno check` PASS · Edition Context **136/136** ·
    `services/` **74/74** · SOURCE_SET **12/12** · `git diff --check` PASS.

    **Postdeploy sob FREEZE — PRE v14 × POST v15, cinco probes, todos iguais:**
    A `401 UNAUTHORIZED_NO_AUTH_HEADER` · B `403 FORBIDDEN_NOT_ADMIN` ·
    C `204` + CORS · D `400 INVALID_JSON` · E `400 CARD_SET_ID_REQUIRED`.
    Os `INVALID_USER_SESSION` intermediários foram tokens expirados,
    descartados após renovação. **Rollback não foi necessário.**

    **Zero writes de negócio, por construção:** D e E retornam nas linhas 507 e
    512 do `index.ts`, **27 e 22 linhas antes** do primeiro write
    (`createVariantJobProcessing`, 539) e antes de qualquer leitura de
    catálogo. Nenhum `card_set_id` real foi enviado; nenhum job criado; nenhum
    SQL executado; **FREEZE permaneceu ATIVO** do início ao fim.

    > **O QUE ESTE BATCH NÃO PROVA, E É DELIBERADO.** A compatibilidade
    > funcional com **importação real** permanece **NÃO PROVADA até o
    > UNFREEZE**. Sem job novo, os 3 preloads, `buildEditionContextIndex`,
    > `routeEditionContext`, o `normalized_data` de três chaves, a identidade
    > de 4 componentes e o bloco `edition_context:` da resposta **nunca
    > rodaram contra dado real**. A prova disponível hoje é **offline**, contra
    > a mesma fixture que o `2834` consome — o que estabelece **equivalência de
    > contrato**, não comportamento observado em produção.
    >
    > Consequência direta: o postcheck que o `EXECUTION-BATCHES.md` previa para
    > o Batch 8 — *"`2834` reexecutado · DB e Edge concordam vetor a vetor"* —
    > **não foi satisfeito no LIVE**, porque exigiria importação. Ele foi
    > satisfeito **por fixture compartilhada em dois runners independentes**:
    > `2834` no LIVE (Batch 7) e a suíte Deno agora. A reexecução do `2834`
    > nesta rodada foi **removida do gate por ausência de justificativa
    > material** — nada do lado SQL mudou.
    >
    > Pendência aberta para o UNFREEZE: a compatibilidade do **caminho de
    > confirmação** com a chave `edition_context_profile_id` em
    > `normalized_data` **não foi exercitada** e não é requisito deste deploy.

O bloqueio de item 2 (`2213`) não é resolvível por quem escreve SQL: depende
de decisão de Fabrício sobre o vocabulário e sobre a linhagem.

`T1` continua não autorizado. **Um deploy foi feito** — a Edge
`import-card-variants` v15 (item 11); nenhum outro artefato saiu de
`database/proposals/2026-09-18-edition-context-axis/`.

> **Correção de registro (`MISSING-TYPE-CORRECTION-01`).** Esta linha dizia
> *"Nenhum artefato foi executado. Nenhum SQL rodou no LIVE"*. Isso deixou de
> ser verdade com a tentativa `BATCH7-2834-LIVE-EXECUTION-01`, que **rodou no
> LIVE** e abortou (item 4 acima) — com efeito persistente ZERO, mas rodou.
> A afirmação foi estreitada para o que continua verificável.
