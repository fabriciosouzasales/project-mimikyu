# ORDEM DE ROLLOUT SEM JANELA INSEGURA

**BLOCKER 9.** A ordem anterior ("UNIQUE4 → writers") criava janela em que a
identidade física exigia 4 componentes enquanto os writers só forneciam 3.

## Princípio

A coluna e o eixo entram **inertes**. A identidade só é estreitada **depois**
que todo produtor já escreve o 4º componente. Nenhuma etapa deixa um estado
representável que o passo seguinte não saiba ler.

> **Reconciliação `ROLLOUT-EXECUTION-READINESS-01`.** Quatro divergências reais
> corrigidas nesta tabela, nenhuma sequência nova inventada:
> (a) T1 estava como etapa pendente — agora **CLOSED**;
> (b) a etapa de seeds dizia *"173 profiles"* — o número canônico é **144**
> (`SEED-COVERAGE.md` v2.1);
> (c) duas etapas carregavam o número **6** — renumeradas;
> (d) *"Consumidores B"* não nomeava os artefatos — agora `2219`–`2222`.
> Acrescentados os harnesses `2830`/`2834`, que a tabela omitia.

| # | Etapa | Estados representáveis ao fim | Janela insegura? |
|---|---|---|---|
| **−1** | **`2840` — probe T1 (`NULLS NOT DISTINCT`) · ✅ EXECUTADO, 7/7 PASS, zero resíduo físico e de ledger. `2209` LIBERADA** | nenhum | — |
| 1 | `2203`–`2207` — tabelas de Edition Context, vazias. **Fronteira transacional explícita por arquivo** (`2203`–`2211` inteiros) | eixo existe, ninguém usa | **não** — aditivo puro, e **atômico por arquivo** |
| 2 | **`2230` → `2231` → `2232`** — **115 traits · 144 profiles · 196 links · 122 mappings**. **ANTES do FREEZE e ANTES do backfill** (Correção 6): o backfill semântico precisa do vocabulário para resolver UUID | vocabulário disponível, ninguém resolve ainda | **não** |
| 3 | **FREEZE DE IMPORTAÇÃO** + captura de baseline real | idêntico ao atual | — |
| 4 | `2208` — coluna `edition_context_profile_id` NULL em 24.893. `2208` precede `2210` | todas as Variants "sem contexto" (semanticamente correto) | **não** |
| 5 | `2210` — `axis_identity_token` + `uq_cvir_row_identity` (índice **normal**) + guard **PERMISSIVO**. **Movida para cá** (`ROLLOUT-DEPENDENCY-CORRECTION-01`): é predecessora da `2212`, que pressupõe `uq_cvir_row_identity` na sua prova de não-colisão | staging aceita rows legadas sem a chave; os índices antigos ainda existem e só caem na etapa 15 | **não** — o guard ainda não exige a chave, justamente por isso |
| 6 | `2211` — contrato terminal de routing. **Movida para cá**: a `2212` chama `internal.resolve_variant_row_axes()` e aborta com `ROUTING_MISSING` sem ela | resolução centralizada | **não** — ninguém o chama ainda |
| 7 | **`2212` RESOLUÇÃO OPERACIONAL** — só `job vivo + PENDING`, pelo routing canônico (UUID / JSON null / AUSENTE). **Universo vivo medido no LIVE: 1.642 rows** (STAGED / PENDING / NEEDS_REVIEW / PENDING) — a afirmação anterior, *"hoje o universo é vazio"*, estava ERRADA e foi corrigida em `PREFLIGHT-CORRECTION-01` (ver precheck P7). Histórico terminal e os 415 `CANCELLED` **não são tocados**. **v3.1**: `bf_params` resolve `POKEMON`/`TCGDEX` por code, com preflight fail-loud — executável **verbatim**, sem edição manual | tri-state verdadeiro no universo vivo; histórico intacto | **não** — guard ainda permissivo |
| 7-BIS | **`2233` REPARO DE ESCOPO — `INCIDENT-ONLY`** · **existe SOMENTE no CURRENT LIVE ROLLOUT**. A `2212` foi executada no LIVE na **v3.1**, que passava `cs.code` como `p_external_set_id`; os 14 mappings `SOURCE_SET_SCOPED` ficaram inalcançáveis e **66 rows** receberam JSON `null` no lugar de UUID. A `2212` não pode ser reexecutada (ledger 1×; `bf_operational` só pega rows *sem* a chave → plano vazio), então o reparo é **forward-fix**: 66 rows `NULL → UUID`, **1.026/616/0 → 1.092/550/0**. **NÃO REPLAYAR EM AMBIENTE LIMPO** — ver a nota de bifurcação abaixo | tri-state correto no universo vivo; histórico, `CANCELLED` e as 7 `LEAGUE+STAFF` intocados | **não** — guard ainda permissivo |
| 8 | **`2832`** (14 provas) → **`2833`** (11 provas, **job-aware**) — read-only, `ROLLBACK`. **Rodam DEPOIS da `2233`**: sobre 1.026/616/0 estariam medindo o dado defeituoso | predicado provado contra as combinações reais, incluindo `CANCELLED` | **não** — read-only |
| 9 | **Consumidores B — `2219` → `2220` → `2221` → `2222`** — passam a chamar `2211` | routing único; `normalized_data` nasce com os dois eixos | **não** |
| 9-BIS | **`2834`** — runner dos vetores compartilhados do eixo 3 (read-only, `ROLLBACK`) · ✅ **LIVE / PASS / CLOSED** (`LIVE-EXECUTION-06`): 18/18 casos · 17/17 vetores · 8/8 estados · 0 FAIL · 0 SKIP · zero resíduo. **Runner canônico = v2.6** (autoridade do repositório, **não foi o arquivo literalmente executado**); o **artefato executado foi o envelope transitório v2.7**, single-statement, rodado **no próprio SQL Editor** para contornar o **modo multi-statement**, que não preserva TEMP TABLEs. Auditoria: removido o wrapper, seus 9 `EXECUTE` recompõem exatamente o transient v2.6 — o PASS valida o **contrato funcional canônico**. O v2.7 **não é autoridade e não deve ser incorporado ao runner** | lado DB provado contra o JSON compartilhado; a paridade com a Edge fecha na etapa 10 | **não** |
| 10 | **EDGE** — deploy do eixo 3 + suíte Deno · ✅ **DEPLOYADA / v15 ACTIVE / CLOSED** (`BATCH8-EDGE-CLOSEOUT-01`). `verify_jwt=true`. Eixo 3 em `services/edition-context.ts` (módulo exportado, **não** inline no `index.ts`) + helpers puros `buildVariantIdentityKey` / `buildVariantNormalizedData`. Provas: `deno check` PASS · **136/136** Edition Context · **74/74** `services/` · **12/12** SOURCE_SET. Postdeploy **sob FREEZE**: PRE v14 × POST v15 iguais nos 5 probes (401 · 403 · 204+CORS · 400 `INVALID_JSON` · 400 `CARD_SET_ID_REQUIRED`); D/E param antes do primeiro write; **nenhum job criado** | **equivalência de CONTRATO** entre Edge e DB, pela fixture única em dois runners — **não** concordância observada em produção: com FREEZE ativo nenhuma importação real ocorreu e o eixo 3 **não rodou contra dado real**. Compatibilidade funcional com import real **INTENCIONALMENTE NÃO PROVADA até o UNFREEZE** | **não** |
| 11 | **`2214`** · ✅ **EXECUTADA / LIVE VALIDATED / CLOSED** (`BATCH8-BIS-2214-CLOSEOUT-01`, 2026-09-22) — guard de **TRANSIÇÃO OPERACIONAL** — `job ∈ (RECEIVED,PROCESSING,STAGED,CONFIRMING)` + `PENDING` + `VALID` exige a chave. Trigger job-aware; `CHECK` não serve. **Movida para DEPOIS da Edge** (`ROLLOUT-DEPENDENCY-CORRECTION-01`): o guard exige a chave nova, então só pode ser promovido quando já existe produtor capaz de gerá-la — antes disso a janela é "produtor antigo × banco novo", e o FREEZE a esconderia até o UNFREEZE. **Versão executada: v3.1**, blob `30e19523d91d9bc127dcefe6f4cb09e6c263ab73`, manualmente pelo **SQL Editor**, `Success. No rows returned`. Postcheck read-only **15/15 GATEs PASS**: trigger único · `tgtype = 23` exato · `UPDATE OF` = `normalized_data` + `persistence_status` + `validation_status` · `tgfoid` = OID da função canônica · G1 e G2 no corpo · `SECURITY INVOKER` · `proconfig = ARRAY['search_path=""']` · ACL fechada · operacional sem chave **0** · **847 / 415 preservados** · voo 0 · resíduo `GUARD2214-%` 0. **Ledger = 0 — diagnóstico de rastreabilidade da execução direta, NÃO "não executada"**: o ledger é escrito pela CLI, nunca pelo motor; a prova física são os catálogos. Mesma classe da `2202`. **NÃO REEXECUTAR sem novo mandato** | o que pode ser confirmado tem o eixo resolvido; histórico não mente | **não** — recusa promoção se restar row **operacional** sem chave |
| 12-A | **`2217` EXPAND** · **PRÓXIMO ESTÁGIO — NÃO EXECUTADA**, exige readiness audit e mandato explícito de Fabrício — cria `write_card_variant` de **7 args** e **PRESERVA** a de 6. Não dropa nada | duas assinaturas coexistem; o confirm antigo segue chamando a de 6 | **não** — aditivo puro. Nenhum caller aponta para assinatura ausente |
| 12-B | **`2218` SWITCH** — confirm: matching quádruplo + lock + `unique_violation`; passa a chamar **somente** a de 7 | writer fornece 4, identidade física ainda distingue 3 | **não — mas NÃO por ser "superconjunto compatível"** (correção do Gate A): duas Variants diferindo só em contexto colidiriam nos índices antigos e o writer levantaria `CARD_VARIANT_IDENTITY_CONFLICT_UNRESOLVED`. É o **FREEZE da etapa 3** que fecha a janela |
| 12-C | **`2223` CONTRACT** — prova database-wide que ninguém chama a de 6, então `DROP` dela | uma única assinatura, a de 7 | **não** — fail-loud se sobrar caller legado; sem wrapper de compatibilidade |
| 13 | `2209` — `CREATE UNIQUE INDEX` (normal) + `ADD CONSTRAINT … USING INDEX`, **atômicos entre si**. Liberada pelo T1 | identidade nova existe; **as antigas ainda existem e ainda mandam** | **não** — conviver é seguro: as antigas são mais restritivas |
| 14 | **`2215`** — `DROP` das duas antigas de `card_variant`, com prova antes e depois | **só a identidade nova** — o eixo passa a existir de fato | **não** — `2215` recusa rodar se a nova não for CONSTRAINT válida |
| 15 | **`2216`** — `DROP` das duas antigas de staging + prova funcional S4 | só a identidade nova | **não** — pré-condição **job-aware**: as 415 `CANCELLED` não bloqueiam |
| 16 | **`2830`** — harness da fundação (**144** automáticos, read-only) | fundação provada ponta a ponta | **não** — read-only |
| 17 | **UNFREEZE** | operação normal | — |
| → | **READY FOR 2213** | — | — |
| 18 | `2831` → `2213` — decomposição de **READY_UNCONDITIONED (285)** **+ lineage atômico** (L1–L4) | legado decomposto sem estado híbrido | **não** |
| 19 | `STAFF_HOLO` + `SET_LOGO_REVERSE` (80) | **bloqueado** até Pricing fechar | — |

> **Etapa "READ MODELS C" removida (`ROLLOUT-PREFLIGHT-CORRECTION-01`).** A
> linha não tinha artefato, arquivo nem ação associada. O `READ-MODELS-AUDIT.md`
> prova negativamente que **nenhum read model de Collections precisa mudar**
> ("Veredito: nenhum é classe A. Nenhum é alterado nesta rodada.") e que os dois
> consumidores classe B (`web/lib/catalogo/queries.ts` e
> `revisao-importacao-variantes-table.tsx`) são o frontend já **`DEFERRED UNTIL
> AFTER 2213`** pelo `FRONTEND-DISPLAY-CONTRACT.md`. Não há deploy de leitura a
> fazer antes da `2213`, e **nenhum código novo foi criado para justificar a
> etapa**. As etapas seguintes foram renumeradas (18→17, 19→18, 20→19); a
> classificação **C — READ MODELS** do `IMPACTED-CONTRACTS.md` permanece válida
> como categoria de análise — o que caiu foi a *etapa de rollout*, não a
> taxonomia.

## DOIS CAMINHOS — `SOURCE-SCOPE-CORRECTION-01`

A etapa **7-BIS** não é uma etapa normal desta ordem de rollout. Ela existe
por causa de um incidente já materializado no LIVE, e a distinção entre os
dois caminhos é permanente:

**CURRENT LIVE ROLLOUT** — etapas 1–7 executadas, sendo a 7 na **v3.1**
defeituosa → **7-BIS (`2233`, reparo)** → 8 (`2832` → `2833`) → 9 em diante.

**CLEAN / CANONICAL PATH** — etapas 1–7, sendo a 7 na **v3.2**, que já
resolve o escopo por `internal.resolve_variant_mapping_scope()` e nasce com
1.092 / 550 / 0 → 8 (`2832` → `2833`) → 9 em diante. **A etapa 7-BIS não
existe.**

A `2233` é **INCIDENT-ONLY / FORWARD-FIX / NÃO REPLAYAR EM AMBIENTE LIMPO**.
A proteção é mecânica, não documental: o gate `RP_G3_CURRENT_STATE` exige
estado atual **exatamente 1.026 / 616 / 0**, e o `RP_G5_DELTA_SIZE` exige
delta **exatamente 66**. Num ambiente onde a v3.2 rodou correta, ambos falham
alto antes de qualquer escrita — o estado lá é 1.092 / 550 / 0 e o delta é 0.

A `2212` v3.2 **não deve ser reexecutada no LIVE**: já consta no ledger 1× e
seu próprio cabeçalho traz o bloco `*** NAO REEXECUTAR ***`. A correção do
arquivo serve à instalação limpa e ao próximo leitor; o LIVE é reconciliado
pela `2233`.

## Armamento dos artefatos — `ROLLOUT-EXECUTION-READINESS-01`

Os **24** artefatos executáveis do pacote (`2203`–`2212`, `2214`–`2223`,
`2230`–`2232`, `2233`) terminam em **`COMMIT;`**, com fronteira transacional
explícita. A `2233` entrou em `SOURCE-SCOPE-CORRECTION-01` e é o único deles
marcado `INCIDENT-ONLY` — é migration de verdade (escreve e commita), mas
pertence apenas ao CURRENT LIVE ROLLOUT.
A única alteração de armamento foi `ROLLBACK;` → `COMMIT;`; **nenhum corpo
auditado foi tocado**. Em `2214` e `2216` o `ROLLBACK TO SAVEPOINT` interno foi
**preservado** — ele descarta apenas as fixtures do probe embutido, nunca o DDL.

Os **8** artefatos de prova (`2830`–`2834`, `2840`–`2842`) **permanecem em
`ROLLBACK;` por desenho** e nunca devem virar migration. `2831` é simulação: a
migration real é a `2213`.

A proteção contra execução prematura é **governança** — autorização de Fabrício
e a ordem de batches abaixo — não o terminador. Mesma decisão aceita em R1.

## A troca do writer é EXPAND → SWITCH → CONTRACT

**Correção `WRITER-EXPAND-CONTRACT-CORRECTION-01`.** A versão anterior desta
tabela trazia a etapa 9 como `2218` → `2217`, com o `DROP` da assinatura de 6
argumentos embutido na própria `2217`. As duas ordens possíveis nesse desenho
eram defeituosas:

| ordem | defeito |
|---|---|
| `2217` → `2218` | a `2217` chegava ao `DROP`, encontrava o confirm ainda chamando com 6 e **abortava** pelo guard `OVERLOAD_DROP_BLOCKED` |
| `2218` → `2217` | janela real: depois da `2218` e antes da `2217`, `admin_confirm_catalog_variant_import()` chamava um writer de 7 argumentos que **ainda não existia** — RPC instalada e inexequível |

Cindir a `2217` elimina as duas. Entre 9-A e 9-C o overload é **deliberado e
temporário**, e em nenhum instante existe caller apontando para assinatura
ausente. O `DROP` migrou para a `2223`, cuja responsabilidade é só provar e
remover.

Mesmo sob FREEZE a correção vale: FREEZE impede importação nova, não torna
aceitável deixar uma RPC instalada que falharia se chamada.

## Por que o freeze é necessário — e por que ele se moveu

Entre as etapas 4 e 9 o sistema tem produtores em versões diferentes. Com
importação ativa, uma linha nova poderia nascer sem a chave de contexto
*depois* do backfill e *antes* do guard — estado não representável no contrato.
O freeze é barato: a campanha `BULK-STP-01 / CLASS A` já está fechada e não há
importação em curso.

**Ele deixou de ser a etapa 0.** O backfill passou a ser semântico e depende
dos seeds; seeds são aditivos puros e não precisam de parada. Congelar antes
deles só alongaria a janela sem ganho. O freeze agora abre imediatamente antes
da captura de baseline — que também precisa ser feita com o sistema parado,
senão a fotografia já nasce velha.

**Baseline é evidência, não contrato.** Nenhuma etapa compara com
cardinalidade capturada antes do freeze. O número "24.020" da versão anterior
estava STALE (o LIVE media 24.372) e foi eliminado de todos os artefatos.

> **Esta tabela é a projeção operacional do `DAG.md`.** O grafo é a
> autoridade; divergência entre os dois é bug. A numeração foi reconciliada
> na `GATE-A-FINAL-CORRECTION-01` — antes, `2210` aparecia como etapa 5 e
> `2208` como 6, apesar de `2210` depender de `2208`.

**Pré-condição de todo o rollout:** apenas **T1** (`2840`). `CONCURRENTLY`
saiu da proposta na Correção 2 — não há mais T2.

## Atomicidade por arquivo — `2203`–`2211`

**`TRANSACTION-BOUNDARY-CORRECTION-01`** (fundação `2203`–`2207`) **+ `-02`**
(núcleo `2208`–`2211`). Os **nove** arquivos são multi-statement. Até estas
correções, nenhum declarava `BEGIN;`/`COMMIT;` — a atomicidade dependia do
comportamento **implícito** do executor.

Agora os nove são **EXPLICIT TRANSACTION BOUNDARY → atomic rollback on
failure**. Não existe estado intermediário aplicável: ou o arquivo inteiro
entra, ou nada entra. Paridade com o eixo Printing (`2165`–`2168`,
`2172`–`2173`), já executado assim via `apply_migration`.

O que cada um deixaria de meio-feito, se falhasse sem fronteira:

| Arquivo | Estado parcial que era representável |
|---|---|
| `2203`–`2205`, `2207` | tabela sem RLS, ou com `GRANT` e sem policy |
| `2206` | um guard instalado sem o outro — composição meio protegida |
| `2208` | coluna sem FK, ou FK sem índice |
| **`2209`** | **índice órfão sem constraint — ver abaixo** |
| `2210` | função sem o índice que depende dela; função sem `REVOKE` |
| `2211` | resolver **executável por `anon`**, criado antes do `REVOKE` |

### `2209` — o caso que mais precisava

```sql
CREATE UNIQUE INDEX uq_card_variant_identity      -- cria o índice
ALTER TABLE ... ADD CONSTRAINT ... USING INDEX    -- PROMOVE, consumindo-o
```

Falha **entre** os dois deixaria `uq_card_variant_identity` como índice órfão:
sem constraint, invisível para quem consulta `pg_constraint`, e bloqueando a
reexecução do arquivo por colisão de nome. A `2215` exige essa constraint
**válida** antes de dropar as duas antigas — um órfão não satisfaz o gate, e o
pacote travaria num estado que nenhum artefato sabe desfazer. Com `BEGIN`/
`COMMIT`: ou existem índice **e** constraint, ou não existe nenhum dos dois.
As duas UNIQUE antigas ficam intactas em qualquer cenário de falha — a tabela
nunca fica sem identidade.

O arquivo sempre trouxe o comentário *"Uma unica chamada, transacional"*; até
a `-02` isso era uma **afirmação**, não uma garantia.

Compatibilidade provada nos nove: **zero** ocorrências de `CREATE/DROP INDEX
CONCURRENTLY`, `REINDEX CONCURRENTLY`, `REINDEX DATABASE/SYSTEM`, `VACUUM`,
`CLUSTER`, `ALTER SYSTEM`, `DISCARD`, `DROP OWNED`,
`CREATE/DROP DATABASE|TABLESPACE|SUBSCRIPTION` — com comentários e literais
entre aspas removidos antes da busca, para não contar menção em prosa como
uso. Todos os índices são `CREATE INDEX` / `CREATE UNIQUE INDEX` comuns,
consistente com o risco **B3** do `README.md`, que já registrava *"zero
precedente"* de `INDEX CONCURRENTLY` no repositório.

## Rollback por etapa

1 · 3 · 6 · 10: falha **durante** a aplicação não deixa resíduo —
`BEGIN;`/`COMMIT;` por arquivo em `2203`–`2211` (ver seção acima). Desfazer
**depois** da aplicação: `DROP` — nada depende ainda.
2: `DROP` — nada depende ainda.
4: reversível (`normalized_data - 'edition_context_profile_id'`).
5 · 10–12: `DROP` do índice/constraint novo restaura o anterior, que ainda existe.
7–8 · 13: `CREATE OR REPLACE` da versão anterior da função.
9-A: `DROP FUNCTION` da de 7 args — a de 6 nunca saiu, o confirm volta a funcionar sozinho.
9-B: `CREATE OR REPLACE` do confirm anterior (que chama com 6) — a de 6 ainda existe.
9-C: **ponto sem volta do writer.** Depois do `DROP` da de 6, reverter o confirm exige recriá-la a partir da canônica `2143`.
15: **irreversível sem backup** — é o único ponto sem volta; por isso o gate de
colisão roda antes, dentro da mesma transação.
