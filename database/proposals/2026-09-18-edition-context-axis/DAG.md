# DAG DE DEPENDÊNCIAS — grafo real, não lista numérica

**Correção 3 da `GATE-A-FINAL-CORRECTION-01`**, revisto pela
**Correção 6 da `BACKFILL-SEMANTICS-CORRECTION-01`** (o backfill semântico
moveu-se para depois dos seeds, e o FREEZE junto).

## O erro que esta página corrige

O inventário anterior declarava, ao mesmo tempo:

- *"2210 depende de 2208"*
- *"2210 ordem 5 · 2208 ordem 6"*

Um artefato não pode preceder aquilo de que depende. **A contradição era real
e a causa era metodológica:** a "ordem" tinha sido escrita como lista linear
de leitura, não derivada do grafo. Aqui a ordem é *consequência* do grafo.

Reconciliação: **`2208` passa a ser etapa 3** (a coluna entra inerte, junto
com a fundação) e **`2210` passa a ser etapa 6**. A dependência real é
`2208 → 2210` — o índice de staging cita a chave que só faz sentido porque a
coluna existe do lado de `card_variant`.

---

## Grafo

```
       ┌────────────────────────────────────────────────────┐
       │ 2203 trait ─▶ 2204 profile ─▶ 2205 N:N ─▶ 2206 guards│
       │                    │                                │
       │                    └──────────▶ 2207 mapping        │
       └───────────────────────────┬────────────────────────┘
                                   ▼
                          2208  coluna em card_variant
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
             2210 staging                   2211 routing
          (índice + shape PERMISSIVO)     (contrato terminal)
                    │                             │
                    └──────────────┬──────────────┘
                                   ▼
                     2230 ▶ 2231 ▶ 2232   SEEDS (classe B)
                     traits · profiles · mappings
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │ FREEZE de importação         │  ◀── move-se para CÁ
                    │ + captura de baseline real   │      (era a etapa 0)
                    └───────────────┬──────────────┘
                                    │
                                   ▼
                    2212 RESOLUÇÃO **OPERACIONAL**  ◀── ex-backfill global.
              (job vivo + PENDING = 1.642 rows)      Histórico INTOCADO:
                                   │                     ~23.957 terminais
                                   │                     + 415 CANCELLED
                                   ▼
                  2233 REPARO DE ESCOPO (INCIDENT-ONLY) ◀── SÓ no LIVE atual.
                 66 rows NULL→UUID · 1026/616/0 →        NÃO é etapa do
                 1092/550/0                              caminho limpo:
                                   │                     a 2212 v3.2 já
                                   ▼                     nasce correta.
                          2832 prova (14 casos)
                                   │
                                   ▼
                  2833 matriz de state machine (11) — job-aware
                                   │
                                   ▼
                 2219–2222  consumidores B  (classe B)
                           │
                           ▼
                 EDGE patch + 7 testes Deno
                           │
                           ▼
            2214 guard de TRANSIÇÃO OPERACIONAL   ◀── DEPOIS da Edge:
                           │                          o guard exige a chave
                           ▼                          que só a Edge produz
                 2217  EXPAND   cria a de 7 · preserva a de 6
                           │
                           ▼
                 2218  SWITCH   confirm passa a chamar a de 7
                           │
                           ▼
                 2223  CONTRACT prova · dropa a de 6
                           │
                           ▼
                 2209  UNIQUE(4) — identidade nova
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
   2215 DROP antigos               2216 DROP antigos
   (card_variant)                  (staging)
              └────────────┬────────────┘
                           ▼
                 2830 harness completo
                           │
                           ▼
                      UNFREEZE
                           │
                           ▼
                 2831 simulação ──▶ 2213 migration real (285)
```

---

## Tabela de dependências

| Artefato | Predecessores obrigatórios | Sucessores | Paralelo? |
|---|---|---|:---:|
| `2203` | — (só `game`) | 2204 · 2207 | — |
| `2204` | 2203 | 2205 · 2206 | ❌ |
| `2205` | 2203 · 2204 | 2206 | ❌ |
| `2206` | 2205 | 2231 | ❌ |
| `2207` | 2203 | 2211 · 2232 | ✅ com 2204–2206 |
| `2208` | — | 2210 · 2217 · 2209 | ✅ com 2203–2207 |
<!-- `2230` NÃO depende de `2208` (ROLLOUT-DEPENDENCY-CORRECTION-01): a tabela
     declarava `2230 | 2203 · 2208`, dependência falsa. `2230` semeia
     card_edition_context_trait e não lê nem escreve card_variant. Prova pelo
     executado: `2230`/`2231`/`2232` entraram LIVE no Batch 2 e a `2208` só no
     Batch 4 — a ordem real já contradizia a aresta. -->

| `2230` | 2203 | 2231 | ✅ com 2210/2211 |
| `2231` | 2230 · 2204 · 2205 · 2206 | 2232 | ❌ |
| `2232` | 2231 · 2207 | 2211 (routing útil) | ❌ |
| `2210` | 2208 | 2212 | ✅ com 2211 e com o seed |
| `2211` | 2207 · `2176` (LIVE) | 2218–2222 | ✅ com 2210 |
| **`2212`** | 2210 · 2211 · 2232 (só se houver universo operacional) | **2233** (só no LIVE atual) · 2832 | ❌ |
| **`2233`** **INCIDENT-ONLY** | 2212 **v3.1 já executada** · 2211 · `resolve_variant_mapping_scope` | 2832 | ❌ — **não replayar em ambiente limpo** |
| `2832` | 2212 **e**, no LIVE atual, 2233 | 2833 | ❌ |
| **`2213`** (futuro) | 2831 PASS · Pricing · **lineage atômico (L1–L4)** | — | ❌ |
| **`2833`** | 2832 | 2214 | ❌ |
| `2214` ✅ **LIVE VALIDATED** | 2833 · **Edge deployada** | 2216 | ❌ |
| **`2224`** ✅ **LIVE VALIDATED** *(guard same-Game 3º eixo)* | **2208** · 2204 | **2217** | ❌ — precede o EXPAND |
| `2219`–`2222` | 2211 | Edge · 2217 | ✅ entre si (funções disjuntas) |
| **Edge** ✅ **v15 ACTIVE** | 2211 · 2219–2222 | 2214 · 2217 | ❌ |
| `2217` **EXPAND** | 2208 | 2218 | ❌ — **não** depende mais da 2218: cria a de 7 e preserva a de 6 |
| `2218` **SWITCH** | 2211 · 2217 (a de 7 precisa existir) | 2223 | ❌ |
| `2223` **CONTRACT** | 2218 (confirm já chama com 7) | 2209 | ❌ |
| `2209` | 2208 · 2223 · Edge | 2215 | ❌ |
| `2215` | 2209 | 2830 | ✅ com 2216 |
| `2216` | 2210 · 2212 · 2214 | 2830 | ✅ com 2215 |
| `2830` | todos acima | — | ❌ |
| `2831` | 2211 · 2232 · 2209 · 2215 | 2213 | ❌ |
| `2213` | 2831 PASS · Pricing fechado | — | ❌ |
| `2840` (T1) | — | **tudo** | ✅ isolado |

---

## Ordem topológica válida

> **RECONCILIADA COM O EXECUTADO (`ROLLOUT-DEPENDENCY-CORRECTION-01`).** A
> sequência abaixo é a ordem **efetivamente seguida** até aqui, e a ordem
> **planejada** daqui para a frente. A versão anterior punha `2210`/`2211`
> antes dos seeds e a `2208` antes de todos eles; o LIVE fez diferente — e o
> LIVE está correto. Não se reescreve histórico: o que foi executado está
> marcado, e o que resta é projeção.

**JÁ EXECUTADO** — `2840` (probe T1, 7/7) → `2203` → `2204` → `2205` →
`2206` → `2207` *(Batch 1)* → `2230` → `2231` → `2232` *(Batch 2)* →
**`FREEZE`** → *baseline `1642` / `847` / `415`* *(Batch 3)* → `2208`
*(Batch 4)* → `2210` → `2211` *(Batch 5)* → **`2212` v3.1** *(Batch 6,
parcial — ver incidente de escopo abaixo)*

---

## DOIS CAMINHOS — o LIVE atual e a instalação limpa

`SOURCE-SCOPE-CORRECTION-01` criou uma bifurcação permanente neste DAG, e ela
precisa ficar explícita para nunca mais ser lida errado.

### CURRENT LIVE ROLLOUT (o banco de hoje)

```
2212 v3.1  ── JÁ EXECUTADA (ledger 20260920172947, 1x, commit d07cbedf)
             passou cs.code como escopo → 66 rows com JSON null indevido
   │
   ▼
2233       ── INCIDENT REPAIR · ✅ EXECUTADA (ledger 20260920195704)
             66 rows NULL→UUID · 1026/616/0 → 1092/550/0
   │
   ▼
2832 → 2833
```

### CLEAN / CANONICAL PATH (instalação nova, replay, ambiente novo)

```
2212 v3.2  ── já contém o source-set canônico
             (resolve_variant_mapping_scope), nasce com 1092/550/0
   │
   ▼
2832 → 2833
```

**A `2233` NÃO existe neste caminho.** Ela é
**INCIDENT-ONLY / FORWARD-FIX / NÃO REPLAYAR EM AMBIENTE LIMPO**.

Isso não depende de disciplina humana: o gate `RP_G3_CURRENT_STATE` exige que
o estado atual seja **exatamente 1.026 / 616 / 0**. Num ambiente onde a
`2212` v3.2 rodou corretamente, o estado é 1.092 / 550 / 0 e a `2233`
**aborta alto**, antes de qualquer escrita, com a mensagem nomeando os dois
números. O mesmo vale para o `RP_G5_DELTA_SIZE` (delta = 66): num ambiente
limpo o delta é 0. O replay indevido é impossível por construção, não por
convenção.

**JÁ EXECUTADO** — `2233` *(reparo de incidente)* → `2832` → `2833`
*(Batch 6)* → `2219` · `2220` · `2221` · `2222` → **`2834` PASS**
*(Batch 7 · **CLOSED**)* → **Edge DEPLOYADA · v15 ACTIVE**
*(Batch 8 · **CLOSED**)* → **`2214` v3.1 LIVE VALIDATED**
*(Batch 8-BIS · **CLOSED**)* → **`2224` GUARD SAME-GAME do 3º eixo
LIVE VALIDATED** *(Batch 9 · **CLOSED**, 2026-09-22)*

**A EXECUTAR** — **`2217` (EXPAND)** *(Batch 9 · **próximo**, NÃO EXECUTADA)* →
**`2218` (SWITCH)** → **`2223` (CONTRACT)** *(Batch 9)* →
`2209` *(Batch 10)* → `2215` → `2216` *(Batch 11)* → `2830` → `UNFREEZE`
*(Batch 12)* → `2831` → `2213`

**27 passos.** Todo predecessor da tabela acima aparece antes de seu sucessor.

> **Fechamento do Batch 7 (`BATCH7-2834-LIVE-CLOSEOUT-01`).** `2219`–`2222` no
> ledger (`20260920212007` · `20260920212555` · `20260920214852` ·
> `20260920215837`); `2834` **PASS** no LIVE — 18/18 casos, 17/17 vetores, 8/8
> estados, 0 FAIL, 0 SKIP, zero resíduo persistente. O **FREEZE segue ATIVO** e
> a **`2214` segue NÃO EXECUTADA** (ledger = 0): ela é Batch 8-BIS e depende da
> Edge. **Artefato canônico × artefato executado:** o runner canônico é o
> **`2834` v2.6** (autoridade do repositório, **não foi o arquivo literalmente
> executado**); o executado foi o **envelope transitório v2.7**,
> single-statement, rodado **no próprio SQL Editor** — cuja auditoria provou
> que, removido o wrapper, seus 9 `EXECUTE` recompõem exatamente o transient
> v2.6. O PASS valida o **contrato funcional canônico**. O v2.7 **não é
> autoridade e não deve ser incorporado ao runner**.

> **Fechamento do Batch 8 (`BATCH8-EDGE-CLOSEOUT-01`).** `import-card-variants`
> **v15 ACTIVE**, `verify_jwt=true`. O eixo 3 foi para
> `services/edition-context.ts` — módulo próprio e exportado, **não** inline no
> `index.ts` como o documento de desenho previa: `index.ts` registra o servidor
> no topo e não exporta nada, então uma função declarada lá não poderia ser
> importada por um teste sem subir um listener, e o teste voltaria a precisar de
> réplica. Provas: `deno check` PASS · **136/136** · **74/74** · **12/12**.
> Postdeploy **sob FREEZE**: PRE v14 × POST v15 iguais nos cinco probes; D/E
> param antes do primeiro write; **nenhum job, nenhum SQL, rollback
> desnecessário**.
>
> **O FREEZE segue ATIVO** e a **`2214` segue NÃO EXECUTADA** (ledger = 0) — mas
> a sua pré-condição *"Edge deployada"* está agora **satisfeita**: ela é o
> próximo estágio.
>
> **Limite declarado:** a compatibilidade funcional com **importação real**
> permanece **NÃO PROVADA até o UNFREEZE**. Sem job novo, os preloads, o
> roteamento, o `normalized_data` de três chaves e a identidade de 4
> componentes **não rodaram contra dado real**. O que existe é **equivalência
> de contrato** — mesma fixture, dois runners independentes (`2834` no LIVE,
> suíte Deno agora) —, não concordância observada em produção.

> **Fechamento do Batch 8-BIS (`BATCH8-BIS-2214-CLOSEOUT-01`, 2026-09-22).** A
> `2214` **v3.1** (blob `30e19523d91d9bc127dcefe6f4cb09e6c263ab73`) foi
> **EXECUTADA NO LIVE** e está **LIVE VALIDATED**: o guard de transição
> operacional job-aware está **ATIVO** no banco. Execução manual, **SQL Editor
> do Supabase**, `Success. No rows returned`. Postcheck read-only **15/15
> GATEs PASS** — trigger único · `tgtype = 23` exato · `UPDATE OF` com as três
> colunas · `tgfoid` = OID da função canônica (vínculo provado por OID, não
> por nome) · G1 e G2 no corpo · `SECURITY INVOKER` ·
> `proconfig = ARRAY['search_path=""']` · ACL sem `PUBLIC`/`anon`/
> `authenticated` · 3 triggers canônicos, nenhum duplicado · **operacional
> `VALID+PENDING` sem a chave = 0** · **histórico `CANCELLED` 847 / 415
> preservados** · jobs em voo 0 · resíduo `GUARD2214-%` 0.
>
> **Ledger = 0 — diagnóstico de RASTREABILIDADE, não estado de execução.** Não
> há linha para `2214_promote_valid_requires_edition_context_key` em
> `supabase_migrations.schema_migrations`, porque o ledger é escrito pela CLI
> do Supabase e nunca pelo motor do Postgres: a execução direta no SQL Editor
> aplica e comita o DDL sem passar por ele. Quem prova o estado físico são os
> catálogos (`pg_trigger`, `pg_proc`), e foram eles que os 15 gates mediram.
> `ledger = 1` também não provaria nada — a linha pode ser inserida à mão.
> Mesma classe da `2202`. Reconciliação do ledger **fora** deste closeout.
>
> **O FREEZE segue ATIVO.** Próximo estágio: **Batch 9 — `2217` EXPAND**,
> **NÃO EXECUTADA**, exigindo readiness audit e mandato de Fabrício. O limite
> declarado do Batch 8 permanece: compatibilidade funcional com importação
> **real** **NÃO PROVADA até o UNFREEZE** — o guard agora **existe e recusa**,
> mas sob FREEZE nenhuma importação o exercitou.

> **Aresta nova: `2208 → 2224 → 2217` (`BATCH9-2217-READINESS-CORRECTION-01`).**
> A `BATCH9-2217-READINESS-AUDIT-01` resultou em **STOP** ao provar que o
> same-Game do terceiro eixo **não existia**: `validate_card_variant_game_
> consistency` (`161`) compara Card × **Variant Type** e seu trigger é
> `UPDATE OF card_id, variant_type_id` — não acorda para
> `edition_context_profile_id`; e a `2220`, que a documentação apontava como
> quem a estenderia, **não a toca** (seu escopo é
> `variant_type_mapping_impact`/`_decision`). A FK da `2208` garante apenas
> **existência** do profile, não o Game.
>
> Decisão de arquitetura: **guard dedicado**, a **`2224`**, espelhando a
> `2170` — `internal.enforce_card_variant_edition_context_profile_game()` +
> `trg_card_variant_edition_context_profile_game` `BEFORE INSERT OR UPDATE OF
> card_id, edition_context_profile_id`. Cada eixo com sua autoridade única; o
> writer (`2217`) continua validando só existência, de propósito.
>
> **A `2224` roda ANTES da `2217`**: o guard tem de existir antes de haver
> assinatura capaz de gravar a coluna. `2224 > 2223` é acidente de numeração —
> **este grafo é a autoridade de ordem, não o número do arquivo**.

**Duas correções de ordem nesta rodada**, ambas porque a projeção operacional
divergia da tabela de dependências — que já estava certa nos dois casos:

- **`2212` desceu para depois de `2210`/`2211`.** Ela aborta com
  `ROUTING_MISSING` sem a `2211` e a sua prova de não-colisão pressupõe
  `uq_cvir_row_identity`, da `2210`.
- **`2214` desceu para depois da Edge.** O guard estrito só pode exigir a
  chave nova depois de existir um produtor capaz de gerá-la.

A etapa *"read models C"* saiu da sequência: foi removida em
`ROLLOUT-PREFLIGHT-CORRECTION-01` por não ter artefato, arquivo nem ação — a
linha aqui era resíduo.

### Mudança de ordem na `BACKFILL-SEMANTICS-CORRECTION-01`

A ordem anterior colocava o backfill **antes** dos seeds. Com o backfill
passando a ser **semântico** — ele resolve cada row pelo routing canônico —
isso deixou de ser possível: sem traits, profiles e mappings, todas as rows
resolveriam para `NEEDS_REVIEW_NO_EC_PROFILE` e o backfill gravaria a chave
em ninguém. Tecnicamente inofensivo, operacionalmente inútil.

Sequência conceitual agora respeitada:

```
estrutura permissiva → seeds/profiles/mappings → routing final
→ FREEZE → baseline → backfill semântico → postcheck
→ guard operacional → identidade terminal → writers/Edge → unfreeze
```

**Consequência que precisa estar dita:** o backfill herdou o bloqueio
editorial **E1**. Ele não pode rodar antes da tradução dos 115 `code`.
O FREEZE também se moveu — passa a começar depois dos seeds, encurtando a
janela de parada.

---

## Impacto da `OPERATIONAL-BOUNDARY-CORRECTION-01` no grafo

**O backfill global saiu.** `2212` passou a operar só sobre o universo
operacional — **1.642 rows** (`NEEDS_REVIEW` em jobs vivos), não as ~26.127. Consequências:

| Antes | Agora |
|---|---|
| `2212` reescrevia ~26.127 rows | opera sobre `job vivo + PENDING` = **1.642** |
| `2212` bloqueado por **E1** | **continua** bloqueado — e agora é claro por quê: são as 1.642 que precisam do vocabulário para resolver |
| FREEZE precisava cobrir o backfill inteiro | janela menor: o freeze cobre `2212`+`2832`+`2833`+`2214`, todos baratos |

### E1 bloqueia a fundação física?

**Não.** Esta é a pergunta da Correção 10, e a resposta mudou:

| Bloco | Depende de E1? |
|---|---|
| **Fundação estrutural** — `2203`–`2211` · `2215`–`2218` · `2223` · `2209` | **NÃO** |
| **Routing/Edge** — `2211` · patch · testes | **NÃO** |
| Resolução das **1.642** `NEEDS_REVIEW` | **SIM** — é o propósito do vocabulário |
| `2212` (resolução das 1.642) | **SIM** |
| Legacy **285** (`2831` · `2213`) | **SIM** |
| Pricing-conditioned **80** | não (bloqueado por O2) |
| Histórico terminal | **não tocado** |

**A fundação física inteira pode ser executada sem E1.** O vocabulário é
pré-requisito da *resolução editorial das rows atuais*, não da estrutura.
Isso libera o Gate B da fundação para andar em paralelo com a tradução.

---

## Sete arestas que não são óbvias — e por que existem

**`Edge → 2214`.** O guard estrito rejeita row VALID sem a chave de contexto.
Se entrar antes do deploy, a Edge antiga passa a produzir rows inválidas e a
importação para. É a única aresta em que um artefato SQL depende de um deploy.

**`2217 → 2218 → 2223`.** `CREATE OR REPLACE` com aridade diferente cria um
**overload**, não substitui — e é esse overload que torna a troca segura.
`2217` (EXPAND) cria a de 7 e **preserva** a de 6: nada quebra, porque o
confirm antigo continua encontrando a assinatura que chama. `2218` (SWITCH)
troca a chamada para 7, que já existe. `2223` (CONTRACT) só então dropa a de
6, depois de provar database-wide que ninguém mais a chama.

A versão anterior deste grafo trazia a aresta `2218 → 2217`, com o `DROP`
embutido na `2217`. Era correta contra o erro *"function does not exist"* na
`2217`, mas produzia o mesmo erro do outro lado: entre `2218` e `2217` o
confirm chamava um writer de 7 argumentos ainda inexistente. Cindir em três
etapas remove as duas janelas. Ver `ROLLOUT-ORDER.md`, seção "A troca do
writer é EXPAND → SWITCH → CONTRACT".

**`2214 → 2216`, mas `2209 → 2215`.** Os dois pares de DROP têm pré-condições
diferentes. No `card_variant`, basta a identidade nova existir. No staging, é
preciso **também** que o backfill e o guard tenham passado — remover os
antigos antes deixaria a granularidade de proteção errada durante a janela em
que muitas rows ainda compartilham o token `'A'`.

**`2840` isolado, mas antes de tudo.** Se `NULLS NOT DISTINCT` não sobreviver
ao caminho de execução, `2209` precisa ser reescrito para quatro índices
parciais — e aí metade do grafo muda. Rodar T1 depois de `2203`–`2208` seria
descobrir tarde.

**`2232 → 2212`.** Amarra a resolução operacional ao bloqueio editorial E1.
Com o universo operacional vazio na baseline atual, a aresta existe mas não
está no caminho crítico da fundação — só da resolução das 1.642.

**`2213 → lineage` (Correção 6).** `2213` passa a alterar `card_variant`
**e** o lineage das 285, **atomicamente**. Metade disso — só a Variant —
criaria o estado híbrido proibido pela Correção 5: `variant_type_id` legado
no lineage apontando para uma Variant já decomposta. Ver `LINEAGE-STRATEGY.md`.

**`2833 → 2214`.** O guard não pode ser promovido sobre um predicado não
provado. `2833` enumera as combinações reais de
(`validation_status` × `decision_status` × `persistence_status`) e aborta se
o predicado `VALID + PENDING` não cobrir exatamente o universo operacional —
inclusive se aparecer um `persistence_status` fora do vocabulário conhecido.
