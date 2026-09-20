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
                                   ▼                     + 415 CANCELLED
                          2832 prova (14 casos)
                                   │
                                   ▼
                  2833 matriz de state machine (11) — job-aware
                                   │
                                   ▼
                     2214 guard de TRANSIÇÃO OPERACIONAL
                                   │
                                   ▼
                 2219–2222  consumidores B  (classe B)
                           │
                           ▼
                 EDGE patch + 7 testes Deno
                           │
                           ▼
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
                 read models C  ──▶  UNFREEZE
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
| `2230` | 2203 · 2208 | 2231 | ✅ com 2210/2211 |
| `2231` | 2230 · 2204 · 2205 · 2206 | 2232 | ❌ |
| `2232` | 2231 · 2207 | 2211 (routing útil) | ❌ |
| `2210` | 2208 | 2212 | ✅ com 2211 e com o seed |
| `2211` | 2207 · `2176` (LIVE) | 2218–2222 | ✅ com 2210 |
| **`2212`** | 2210 · 2211 · 2232 (só se houver universo operacional) | 2832 | ❌ |
| `2832` | 2212 | 2833 | ❌ |
| **`2213`** (futuro) | 2831 PASS · Pricing · **lineage atômico (L1–L4)** | — | ❌ |
| **`2833`** | 2832 | 2214 | ❌ |
| `2214` | 2833 · **Edge deployada** | 2216 | ❌ |
| `2219`–`2222` | 2211 | Edge · 2217 | ✅ entre si (funções disjuntas) |
| **Edge** | 2211 · 2219–2222 | 2214 · 2217 | ❌ |
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

`2840` (probe T1) → `2203` → `2204` → `2205` → `2206` → `2207` → `2208` →
`2210` → `2211` → `2230` → `2231` → `2232` → **`0 FREEZE`** → *baseline* →
`2212` → `2832` → `2833` → `2219`…`2222` → **Edge** → `2214` →
**`2217` (EXPAND)** → **`2218` (SWITCH)** → **`2223` (CONTRACT)** →
`2209` → `2215` → `2216` → `2830` → read models C → `UNFREEZE` →
`2831` → `2213`

**28 passos.** Todo predecessor da tabela acima aparece antes de seu sucessor.

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
