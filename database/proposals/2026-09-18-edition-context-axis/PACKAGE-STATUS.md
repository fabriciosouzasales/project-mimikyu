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
| **`2834`** | **runner SQL da fixture compartilhada do eixo 3** — 14 vetores executáveis, 3 SKIP declarados |
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

3. **Paridade parcial no runner SQL (novo, `EDGE-D3-FINAL-CORRECTION-01`).**
   O `2834` executa **14 dos 17** vetores. Os três restantes — `E3`, `E16`,
   `E17` — exigem fixture do eixo de **Impressão** (`RESOLVED_WITH_PROFILE`
   ou `UNRESOLVED`) que este runner não monta, e ficam **SKIP com motivo
   explícito, nunca PASS**. Consequência medida: dois estados do vocabulário
   — `NOT_EVALUATED` e `NEEDS_REVIEW_NO_EC_PROFILE` — não têm nenhum vetor
   PASS do lado SQL. O lado TypeScript cobre os 17. **Bloqueio de cobertura,
   não de código** — resolve-se estendendo o `2834` com fixture de Impressão
   numa rodada própria.

Nenhum dos dois é resolvível por quem escreve SQL. Ambos dependem de
decisão de Fabrício sobre o vocabulário e sobre a linhagem.

**Nenhum artefato foi executado.** Nenhum SQL rodou no LIVE, nenhum deploy
foi feito, `T1` continua não autorizado, e nada saiu de
`database/proposals/2026-09-18-edition-context-axis/`.
