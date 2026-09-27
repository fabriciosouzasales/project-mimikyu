# 2830H — Preparação da adjudicação do requisito 6.2 (`ix_card_variant_card_id`)

| Campo | Valor |
|---|---|
| **Natureza** | Proposta documental de adjudicação. **Sem execução**: nenhum SQL, nenhum acesso ao LIVE, nenhuma alteração de índice, tabela ou função. |
| **Mandato** | `BATCH12-2830-INDEX-6.2-ADJUDICATION-READINESS-01`. Baseline HEAD `1c565c431d804b2c98239e5cb5c77f1a20e230e0`. |
| **Autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável): Seção 6 (6.1, 6.2), critérios D e E.<br>`P9A-READINESS.md` v1.2 (blob `99c32f78…`): §4, §6.2, §6.3, BL-4.<br>`LIVE-P9A-EXECUTION-RECORD.md` v1.0 (blob `b1507378…`): §5, §6, §7, Apêndice B. |
| **Estado** | **PROPOSTA — NÃO APROVADA.** Nenhuma alternativa foi escolhida ou registrada como aprovada.<br>• 6.1: **NÃO DEMONSTRADO** (não FAIL);<br>• 6.2: **EVIDÊNCIA — CENÁRIO PEQUENO**, aguardando decisão de Fabrício;<br>• P9A-05: não autorizado, não executado;<br>• P9a não está globalmente concluído; A2 não está cumprido.<br>**FREEZE ATIVO.** |
| **Papéis** | **Fabrício**: decisão. **Claude**: preparação desta análise. **ChatGPT**: auditoria independente. |

---

## 0. Condição de STOP

Avaliada antes da análise. **Não há STOP.**

- **Divergência contratual:** nenhuma contradição entre a 2830 v7.0, o readiness v1.2 e o registro LIVE. Há duas **ambiguidades** de leitura que dependem de Fabrício (Q1 e Q2, §7). Elas não impedem a preparação e não são resolvidas aqui.
- **Evidência indispensável:** a 2830 pede, para 6.2, uma "decisão … com EXPLAIN real". O EXPLAIN real existe (P9A-04, registro §5). O que falta (§4) limita o **alcance** da decisão; não impede que ela seja preparada.

## 1. Rastreabilidade literal (A)

### 1.1 Contrato: 2830 v7.0 (blob `b4647dcb…`)

| Id | Linha(s) | Texto literal |
|---|---|---|
| **6.1** | 987–988 | "6.1  [MANUAL] EXPLAIN de busca por card_id usa uq_card_variant_identity (prefixo)" |
| **6.2** | 989 | "6.2  [MANUAL] decisão sobre ix_card_variant_card_id com EXPLAIN real" |
| Seção 6 | 985 | "SEÇÃO 6 — PERFORMANCE + TOOLING (3) · MANUAL 3 · FORA DO TOTAL AUTOMÁTICO" |
| Denominador | 73 e 1118 | "Manuais obrigatórios … 6 (K1 K2 K8b 6.1 6.2 6.3)" |
| **D** | 1164 | "D. MANUAIS OBRIGATÓRIOS (6/6, nenhum dispensável)" |
| **D5** | 1174–1175 | "D5 6.1 e 6.2 — EXPLAIN (sem ANALYZE, salvo autorização) no LIVE, registrado;" |
| **E1** | 1179–1180 | "E1 A, B, C e D integralmente satisfeitos e registrados na documentação (EXECUTION-BATCHES, HANDOFF, log);" |
| **P9(a)** | 307–309 | "FORMA DO PLANO — EXPLAIN (COSTS OFF) … Mostra índices/joins usados. NÃO mede tempo …" |
| **P9(b)** | 310–316 | "TEMPO REAL — medido em AMBIENTE ISOLADO REPRESENTATIVO (P14), nunca no LIVE: … mesma impressão digital de funções/índices (P14a)" |

### 1.2 Origem do índice composto: 2209 (blob `2c36fd26…`)

| Linha(s) | Texto literal |
|---|---|
| 56–58 | "um índice único serve os prefixos (card_id), (card_id, variant_type_id) e (card_id, variant_type_id, printing_profile_id)" |
| 62–65 | "card_id primeiro: toda consulta de UI parte da Card. Isso torna a UNIQUE utilizável como índice de leitura e permite avaliar a remoção futura de ix_card_variant_card_id (NÃO removido aqui — ver harness)." |

A 2209 afirma que o índice composto é **utilizável** para o prefixo. Não afirma equivalência de desempenho.

### 1.3 Condições operacionais: `P9A-READINESS.md` v1.2 (blob `99c32f78…`)

| Ponto | Linha(s) | Conteúdo |
|---|---|---|
| §1 | 18–20 | 6.1, 6.2 e D5, transcritos da 2830 |
| §4, limite 5 | 66 | P9A-04 com N = 3 vale só para N pequeno; P9A-05 cobre teto de catálogo, não a cardinalidade processada |
| §4, limite 7 | 68 | o plano sem `ix_card_variant_card_id` não é observável no LIVE (exigiria DDL, `SET enable_*` ou extensão hipotética, todos proibidos) |
| §6.2 | 339–348 | 6.1 PASS só com acesso via `uq_card_variant_identity` e `Index Cond` em `card_id`. Outro índice com `first_key = card_id` (inclusive `uq_card_variant_card_order`) leva a **NÃO DEMONSTRADO**, e não a FAIL |
| §6.3 | 352–360 | 6.2 é uma **decisão**; a execução só produz evidência. "**6.2 CUMPRIDO** — Só quando Fabrício registrar a decisão (manter, remover ou adiar) com referência a essa evidência … A remoção é DDL: exige mandato próprio e não é permitida sob FREEZE." |
| §6.3 | 362–364 | leitura condicional, não decisória: com `ix_card_variant_card_id` nos planos, 6.1 fica NÃO DEMONSTRADO enquanto o índice existir |
| BL-4 | 421 | 6.1 literal "pode ser indemonstrável enquanto existir índice mais estreito em `card_id`" |

### 1.4 Ordem de rollout: `EXECUTION-BATCHES.md` (blob `ebbd91e8…`), l. 1267

Os manuais obrigatórios antes do UNFREEZE ("nenhum dispensável") incluem "`6.1`/`6.2` (EXPLAIN)".

## 2. Evidências obtidas (B)

Todas vêm da execução `BATCH12-2830-P9A-LIVE-EXECUTION-01` (baseline `17857efb`). Estão registradas em `LIVE-P9A-EXECUTION-RECORD.md` (blob `b1507378…`), publicado em `1c565c43`.

### 2.1 Planos

| Evidência | Conteúdo | Referência |
|---|---|---|
| **P9A-03** (6.1) | `Index Scan using ix_card_variant_card_id on card_variant cv`<br>`Index Cond: (card_id = '00000000-0000-0000-0000-000000000000'::uuid)` | registro §5 (l. 85–90); Apêndice B.3 (l. 329), saída md5 `03963bcf…`, 167 B |
| **P9A-04** (6.2) | `Index Scan using ix_card_variant_card_id on card_variant cv`<br>`Index Cond: (card_id = ANY ('{…0001,…0002,…0003}'::uuid[]))` | registro §5 (l. 92–97); Apêndice B.4 (l. 335), saída md5 `45308e3a…`, 251 B |
| Classificação | 6.1 **NÃO DEMONSTRADO** (não FAIL); 6.2 **EVIDÊNCIA — CENÁRIO PEQUENO** | registro §5 (l. 99–108) e §8 |
| Contrafactual | **não obtido**: nenhum plano sem `ix_card_variant_card_id` | registro §5 (l. 112); readiness §4, limite 7 |
| P9A-05 | não autorizado, não executado | registro, cabeçalho (l. 7) e §5 (l. 107) |

### 2.2 Índices de `card_variant` (P9A-00 (a) = (b))

Fonte: registro §5 (l. 115–120) e Apêndices B.2/B.5 (saídas md5 `2539e3f5…` e `f9a11071…`). Contadores acumulados desde `stats_reset` 2026-07-15T14:26:35Z.

| Índice | Definição (resumo) | `first_key` | Chaves | Tamanho | `idx_scan` | `last_idx_scan` |
|---|---|---|---|---|---|---|
| `ix_card_variant_card_id` | btree (card_id), não único | card_id | 1 | 843.776 B | 3.397.803 | 2026-09-27T03:56:08Z |
| `uq_card_variant_identity` | UNIQUE btree (card_id, variant_type_id, printing_profile_id, edition_context_profile_id) NULLS NOT DISTINCT | card_id | 4 | 1.515.520 B | 1.880 | 2026-09-27T03:56:08Z |
| `uq_card_variant_card_order` | UNIQUE btree (card_id, variant_order) | card_id | 2 | 1.327.104 B | 25.341 | 2026-09-25T02:36:18Z |
| `uq_card_variant_one_default_per_card` | UNIQUE btree (card_id) WHERE is_default = true | card_id | 1 | 81.920 B | 3.694 | 2026-09-19T01:00:40Z |

- `uq_card_variant_identity`: `valid`, `ready` e `live` = true; `first_key = card_id` (Apêndice B.2).
- Os outros cinco índices de `card_variant` não começam por `card_id`: `card_variant_pkey`, `uq_card_variant_id_card`, `ix_card_variant_variant_type_id`, `ix_card_variant_printing_profile_id` e `ix_card_variant_edition_context`.
- **`idx_scan` é contador acumulado de todo o tráfego desde o reset.** Não isola nenhum consumidor, não mede desempenho e não prova indispensabilidade.

### 2.3 Representatividade da janela (registro §6)

- **Planner:** 13 `enable_*` = `on`; `random_page_cost` = 1.1; `work_mem` = 2184 kB; `jit` = off.
- **`card_variant`:** `reltuples` = 24.893; `last_autoanalyze` = 2026-09-19T00:48:33Z; `n_mod_since_analyze` = 897.
- **`card_id_stats`:** `MCV_PRESENT`, `literals_in_mcv = false`.
- **Canal:** `postgres`, dono das tabelas; RLS fora do plano.
- **Estabilidade (a)/(b):** cumprida.

### 2.4 Consumidor de P9A-04 (evidência estática do repositório)

| Fato | Referência |
|---|---|
| `listExistingCardVariantsMap` lê `card_variant` com `.select("id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id").in("card_id", cardIds)` | `supabase/functions/import-card-variants/services/database.ts` (blob `db0dfed7…`), l. 605–631 |
| É chamado com `correlatedCardIds`, as Cards distintas correlacionadas do Card Set | `index.ts` (blob `50532edd…`), l. 814 e 828 |
| O cliente usado é criado com `SUPABASE_SERVICE_ROLE_KEY` | `index.ts`, l. 96 e 101 |
| `correlatedCardIds.length` aparece só na **resposta HTTP** (`cards.correlated`) | `index.ts`, l. 1093 e 1129 |
| O job persiste `total_rows`, `valid_rows`, `failed_rows` e `error_summary`, sem a contagem de correlacionadas | `database.ts`, l. 929–951 (`finalizeVariantJobStaged`) |

O código confirma o readiness §5.6: a cardinalidade de `correlatedCardIds` não fica gravada nas colunas do job.

### 2.5 Referências nominais a `ix_card_variant_card_id` no repositório (busca textual)

Esta lista cobre as ocorrências do **nome** do índice. **Não** é inventário de consumidores que se beneficiam do índice: consultas por `card_id` não citam o nome do índice (§4, linha F).

| Artefato | Linha(s) | Natureza |
|---|---|---|
| `database/schema/160_create_card_variant_table.sql` (blob `09ff8720…`) | 125–126 | cria o índice (canônico) |
| `database/validations/960_validate_card_variant.sql` (blob `6fe5ecd7…`) | 161–166 | exige a existência do índice por nome |
| `database/migrations/2135_…_coverage_view.sql` (blob `c36082e4…`) | 36, 63 | registro histórico (2026-08-14) de `Index Only Scan` sobre o índice na view `catalog_card_set_variant_coverage` |
| `database/schema/2171_…_for_printing.sql` | 50 | lista de objetos preservados |
| `2209_reconcile_card_variant_identity_unique4.sql` | 63–65 | "permite avaliar a remoção futura" |
| `2218_redefine_admin_confirm_catalog_variant_import.sql` (blob `cca9c6d7…`) | 902–911 | comentário de performance do matching quádruplo |
| `README.md` da proposta (blob `8e5d68b8…`) | 320 | "a avaliação de remover `ix_card_variant_card_id` (coberto pelo prefixo da UNIQUE) fica para o harness" |
| `docs/05b-cartas-e-raridade.md` | 1685 | DDL documentada |

## 3. Avaliação das alternativas (C)

### 3.1 Matriz

| Dimensão | 1. MANTER | 2. ADIAR (até evidência complementar) | 3. REMOVER no futuro (novo mandato + comprovação isolada) |
|---|---|---|---|
| **Estado físico** | inalterado | inalterado | inalterado agora; DDL só em mandato futuro |
| **Integridade** | Nenhum efeito. O índice é não único e não sustenta constraint: a unicidade vem dos índices únicos (2171 l. 43–50; `uq_card_variant_identity`, 2209). | Idem MANTER. | Remover um índice não único não altera PK, UNIQUE, CHECK ou FK. A FK `fk_card_variant_card` (`ON DELETE/UPDATE RESTRICT`, 160 l. 71–75) segue válida: o índice só afeta o **custo** da verificação, que não foi observada. |
| **Performance** | Mantém o caminho observado para N ≤ 3 sintético.<br>Custo: 843.776 B e manutenção a cada escrita que toque `card_id`, **não medida**. | Idem MANTER enquanto durar o adiamento. | **Efeito desconhecido.** Não há contrafactual. Restariam três índices com `first_key = card_id` (§2.2), e não está demonstrado qual o planner escolheria: o menor candidato completo é `uq_card_variant_card_order` (2 chaves, 1.327.104 B), não `uq_card_variant_identity` (4 chaves, 1.515.520 B). O parcial `…one_default_per_card` só serve a consultas que impliquem `is_default = true`. |
| **Segurança** | Nenhum efeito sobre grants, RLS ou funções. | Idem. | Nenhum efeito sobre grants, RLS ou funções. A DDL exige o dono e um mandato próprio; é proibida sob FREEZE (readiness §6.3). |
| **Operação** | Nenhuma ação física. Só o registro documental da decisão. | Nenhuma ação física agora. Exige definir **qual** evidência complementar, **quem** autoriza e **quando** reabrir. | Mandato de DDL com precheck de concorrência, como na 2209:<br>• `DROP INDEX` toma `ACCESS EXCLUSIVE` em `card_variant` até o COMMIT e bloqueia também a leitura;<br>• `DROP INDEX CONCURRENTLY` não bloqueia leitura, mas não roda em bloco de transação e, portanto, não segue o padrão transacional da 2209.<br>Reversível com `CREATE INDEX`, que toma `SHARE` e bloqueia escrita.<br>Atualizações canônicas: schema 160, validação 960, `docs/05b`, README da proposta l. 320. |
| **Requisito 6.1** | Continua **NÃO DEMONSTRADO** enquanto os planos escolherem o índice simples (BL-4). Não vira FAIL. Não pode ser forçado por `SET` nem por DDL no LIVE. | Continua **NÃO DEMONSTRADO**. | Pode ser retentado depois da remoção, com novo EXPLAIN no LIVE e novo mandato. **O PASS não é garantido:** se o planner escolher `uq_card_variant_card_order`, a classe continua NÃO DEMONSTRADO (readiness §6.2). A remoção, sozinha, não demonstra 6.1. |
| **Requisito 6.2** | A decisão registrada com referência à evidência e aos seus limites atende a condição literal de CUMPRIDO (readiness §6.3). **Não declarado aqui.** | O readiness §6.3 lista "adiar" entre as decisões possíveis. Se "adiar" é decisão registrada ou ausência de decisão é a **Q1** (§7). | A decisão de remover no futuro, se registrada, entra na lista do readiness §6.3. A execução é outro mandato. A evidência atual não sustenta a remoção (§4). |
| **Dependências posteriores** | Os planos futuros (2218, 2213, seções B/M/5.x) continuam avaliados sobre o conjunto atual de índices. | Os itens do §4 viram pré-requisitos da nova decisão:<br>• P9A-05 precisa de autorização;<br>• o contrafactual depende de D-1 (ambiente isolado sem custo, **PENDENTE**). | Depende de:<br>• D-1 e P14a (paridade);<br>• medição de tempo tipo P9b;<br>• inventário exaustivo de consumidores (§4 F);<br>• UNFREEZE ou mandato de DDL explícito.<br>Reabre a prova de plano do matching e do `MAX(variant_order)` da 2218 (l. 902–911), que presume um conjunto de índices. |
| **Reversibilidade** | total | total | reversível por recriação (lock de escrita, janela curta com 24.893 linhas, **não medida**) |

### 3.2 Síntese técnica (sem escolha de alternativa)

1. **MANTER e ADIAR** deixam o banco no mesmo estado físico. Diferem só no plano documental:
   - o estado de 6.2 (ver Q1);
   - as obrigações de reabertura.
2. **REMOVER** é a única alternativa com efeito físico. Nenhuma evidência atual a sustenta:
   - não há contrafactual nem medição de tempo;
   - o consumidor com cardinalidade real não foi observado;
   - a própria alternativa, como formulada no mandato, está condicionada a comprovação em ambiente isolado.
3. **O prefixo não prova equivalência.** `card_id` como primeira chave de `uq_card_variant_identity` prova que o índice **pode** servir busca por `card_id` (P9A-00: válido, `first_key = card_id`). Não prova que o serviço seria equivalente em custo.
4. **Frequência não prova indispensabilidade.** O `idx_scan` de 3.397.803 é acumulado e não atribuível a um consumidor.
5. **6.1 fica NÃO DEMONSTRADO em qualquer das três alternativas**, pelo menos até nova evidência. Nenhuma delas o converte em PASS por si só.

## 4. O que não está demonstrado e evidência adicional necessária (D)

| # | Categoria | O que existe | O que **não** está demonstrado | Evidência adicional necessária | Pré-condição |
|---|---|---|---|---|---|
| A.a | **Forma de plano — `card_id` reais e cardinalidades diferentes, no canal `postgres`** | P9A-03 (N = 1) e P9A-04 (N = 3), com literais sintéticos fora da MCV, no canal `postgres` (dono, RLS fora do plano) | plano com `card_id` reais; plano para N maior (Bitmap ou Seq Scan possíveis, readiness §4 limite 5) | P9A-05 (§5.6 do readiness): P9A-05a e um P9A-05b por `card_set_id` distinto (p50/p95/máximo), **no mesmo canal `postgres`**.<br>Continua **evidência complementar, não conclusiva**:<br>• tamanhos de teto de catálogo, não a cardinalidade processada (linha B);<br>• **não** comprova a forma do plano sob o papel efetivo do consumidor (linha A.b). | autorização expressa de leitura de dado de negócio no mandato LIVE |
| A.b | **Forma de plano — papel efetivo do consumidor** | nenhuma. Todos os planos observados vieram do canal `postgres`. O consumidor usa um cliente criado com `SUPABASE_SERVICE_ROLE_KEY` via PostgREST (§2.4) | plano sob o papel, a sessão e o texto de predicado efetivos do consumidor. Não foram observados:<br>• as propriedades desse papel no LIVE;<br>• a aplicação ou não de RLS;<br>• a configuração de sessão do PostgREST;<br>• o texto exato do filtro `.in()` (readiness §4, limites 3 e 6). | a definir numa **readiness própria**, **se** essa avaliação for considerada necessária. Ela terá de demonstrar:<br>• o canal;<br>• a correspondência com o consumidor;<br>• que não usa os meios hoje proibidos no LIVE (`SET`, `set_config`, alteração de papel ou de sessão), nenhum dos quais é presumido aqui.<br>O P9A-05 **não** substitui esta evidência. | readiness própria e mandato próprio; não é pré-requisito presumido desta decisão, e a necessidade fica a critério de Fabrício |
| B | **Cardinalidade efetiva de `correlatedCardIds`** | só o código: é subconjunto das Cards do Set (§2.4) | nenhuma medida; o valor não é persistido no job (só na resposta HTTP) | uma de duas vias, ambas a definir:<br>(i) derivar de `catalog_variant_import_row` (`count(DISTINCT card_id)` por job), **com prova estática prévia** de que esse número equivale a `correlatedCardIds` em cada versão do Edge usada — a equivalência **não** está demonstrada, e houve exclusão de linhas de job CANCELLED;<br>(ii) passar a persistir a contagem (mudança de Edge, fora do FREEZE) | mandato próprio; leitura de dado de negócio ou mudança de código |
| C | **Cenários de teto de catálogo** | definição de P9A-05a/05b (readiness §5.6, md5 `9836e429…`) | distribuição de Cards por Set no universo do consumidor; planos nos tamanhos p50/p95/máximo | executar P9A-05a e até 3 P9A-05b | autorização expressa; não torna 6.2 conclusivo sozinho |
| D | **Desempenho medido** | nenhum (P9a ≠ tempo; sem `EXPLAIN ANALYZE`) | tempo e buffers da consulta do consumidor, com e sem o índice; custo de manutenção do índice na escrita | medição tipo P9b: execução real, repetida, com cache frio e quente, em ambiente isolado representativo | D-1 (ambiente isolado sem custo) **PENDENTE**; o ambiente pago foi recusado (`LIVE-VALIDATION-PROTOCOL.md`, l. 8) |
| E | **Contrafactual isolado** | nenhum | plano e tempo sem `ix_card_variant_card_id`; índice escolhido nesse caso (§3.1: pode não ser `uq_card_variant_identity`) | no ambiente isolado:<br>(1) provar a paridade P14a **com** o índice;<br>(2) mudar **uma** variável (remover o índice ou simular a remoção);<br>(3) repetir A e D. A mudança quebra de propósito a impressão digital de índices da P14a: declarar como variação controlada, não como paridade. | D-1; mandato próprio; `ANALYZE` permitido só no ambiente isolado (P9b) |
| F | **Consumidores além de P9A-04** (complementar) | as referências nominais do §2.5; o consumidor de P9A-04 | inventário exaustivo das consultas de `card_variant` por `card_id` (Edge, frontend, funções SQL, views, verificação de FK); os planos de cada uma | inventário estático dirigido por mandato, seguido dos planos relevantes | só leitura do repositório; os planos LIVE exigem autorização |

A lacuna A foi dividida em A.a e A.b em `…-CORRECTION-01`. Onde "A" aparece como grupo (linha E, minuta §6 e Q4), refere-se a A.a e A.b.

## 5. Sinalizações (divergências encontradas, sem STOP; nada foi alterado)

| # | Onde | Divergência | Efeito |
|---|---|---|---|
| S1 | `README.md` da proposta, l. 320 | "coberto pelo prefixo da UNIQUE": afirma cobertura sem evidência de equivalência de desempenho | Documental. Não altera o contrato. Correção futura a critério de Fabrício. |
| S2 | `database/validations/960_validate_card_variant.sql`, l. 161–166 | exige `uq_card_variant_card_type_no_printing` e `uq_card_variant_card_type_printing`, que **não** constam do inventário P9A-00 (§2.2; a 2830 D1/D2 exige a ausência deles) | A 960 já não corresponde ao LIVE, **independentemente** de 6.2. Uma remoção futura de `ix_card_variant_card_id` acrescentaria mais um nome à divergência.<br>**Encaminhamento:** divergência a encaminhar à preparação da fase 5 (designação do mandato `…-CORRECTION-01`). A 960 **não** é alterada neste mandato. |
| S3 | `2218`, l. 902–904 | o comentário descreve o estado anterior à 2209 ("uq_card_variant_identity AINDA NÃO EXISTE"); P9A-00 mostra o índice existente | Temporal: o comentário era verdadeiro quando foi escrito. Relevante só se o plano da 2218 for reavaliado. |

## 6. Minuta de decisão (E) — NÃO ASSINADA

> **Esta minuta não é decisão.** Os campos estão em branco. Nenhuma opção está pré-marcada.

| Campo | Valor |
|---|---|
| **Identificador** | `BATCH12-2830-INDEX-6.2-DECISION-__` |
| **Data** | ____ |
| **Decisor** | Fabrício |
| **Objeto** | 2830 v7.0, requisito 6.2: "decisão sobre `ix_card_variant_card_id` com EXPLAIN real" |
| **Alternativa escolhida** | ☐ MANTER ☐ ADIAR ☐ REMOVER no futuro (condicionada a novo mandato e comprovação em ambiente isolado) |
| **Justificativa** | ____ |
| **Evidência considerada** | ☐ P9A-03 (registro §5; B.3 md5 `03963bcf…`)<br>☐ P9A-04 (registro §5; B.4 md5 `45308e3a…`)<br>☐ inventário de índices P9A-00 (a)/(b) (registro §5 e §6)<br>☐ consumidor estático (§2.4 desta proposta)<br>☐ outra: ____ |
| **Limitações aceitas** (marcar cada uma explicitamente) | ☐ cenário pequeno (N ≤ 3), literais sintéticos<br>☐ canal dono, sem RLS; consumidor com service role<br>☐ estatísticas de 2026-09-19 (`card_variant`)<br>☐ sem contrafactual (plano sem o índice não observado)<br>☐ sem medição de tempo (P9a ≠ P9b)<br>☐ `idx_scan` acumulado, não atribuível<br>☐ cardinalidade de `correlatedCardIds` não medida<br>☐ P9A-05 não executado<br>☐ inventário de consumidores não exaustivo |
| **Estado de 6.2 após o registro** | ☐ CUMPRIDO (decisão registrada, nos termos do readiness §6.3)<br>☐ continua aberto (depende da Q1) |
| **Estado de 6.1 após o registro** | ☐ continua NÃO DEMONSTRADO<br>☐ outro encaminhamento: ____ (ver Q2 e Q3) |
| **Efeito sobre D5 / E1 (UNFREEZE)** | ____ (ver Q2) |
| **Evidência complementar exigida** (se ADIAR ou REMOVER) | ☐ A ☐ B ☐ C ☐ D ☐ E ☐ F (§4), com prazo ou gatilho: ____ |
| **Mandatos subsequentes necessários** | ____ |
| **Condição de revisão** | ____ |
| **Assinatura** | ____ (não assinada) |

## 7. Questões que dependem de Fabrício

| # | Questão | Por que não se resolve pelos documentos |
|---|---|---|
| **Q1** | "Adiar" registrado conta como a decisão que torna 6.2 CUMPRIDO, ou 6.2 continua aberto até a decisão final? | O readiness §6.3 lista "adiar" entre as decisões que tornam 6.2 CUMPRIDO. O mandato descreve ADIAR como "adiar a decisão até evidência complementar". As duas leituras são possíveis. |
| **Q2** | Para D5, e portanto para E1 (UNFREEZE), basta 6.1 com EXPLAIN **registrado** (hoje NÃO DEMONSTRADO), ou é preciso 6.1 PASS? | A 2830 D5 (l. 1174–1175) pede "EXPLAIN … no LIVE, registrado". O texto de 6.1 (l. 987–988) enuncia o resultado esperado. O readiness definiu o PASS de 6.1, mas não disse se NÃO DEMONSTRADO satisfaz D5. |
| **Q3** | Se 6.1 continuar indemonstrável enquanto houver índice mais estreito em `card_id` (BL-4), o critério de 6.1 será reavaliado numa versão futura da 2830? | A 2830 v7.0 é imutável neste mandato. Existe precedente de proposta v7.1 (`2830-V7.1-PROPOSAL-ADMIN-CONCURRENCY.md`), mas nenhuma alteração de 6.1 foi proposta aqui. |
| **Q4** | Algum dos itens A–F do §4 será autorizado, e em que mandato? | Todos exigem autorização (leitura de dado de negócio, mudança de código ou D-1). |
| **Q5** | S1 e S2 (§5) devem virar item de correção documental separado? | Estão fora do escopo deste mandato. Nada foi alterado. |

## 8. Limites desta preparação

- Nenhum SQL executado, nenhum acesso ao LIVE, nenhum índice, tabela ou função alterados; P9A-05 não executado.
- A 2830 v7.0, o readiness v1.2, o registro LIVE e os artefatos canônicos não foram modificados.
- Nenhuma alternativa registrada como aprovada.
- Nada é declarado cumprido: nem 6.1 PASS, nem 6.2 CUMPRIDO, nem P9a global concluído, nem A2 cumprido.
- Os fatos de PostgreSQL citados (locks de `DROP INDEX`/`CREATE INDEX`, `CONCURRENTLY` fora de transação, índice parcial restrito ao seu predicado, índice não único sem papel em constraints) são comportamento documentado do motor. **Não** foram observados no LIVE nesta rodada.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-INDEX-6.2-ADJUDICATION-READINESS-01`, baseline `1c565c43`), documental, sem SQL e sem acesso ao LIVE.**<br>• Rastreabilidade literal de 6.1, 6.2, D5 e E1;<br>• inventário das evidências de P9a com referências;<br>• matriz MANTER / ADIAR / REMOVER no futuro;<br>• lacunas A–F com a evidência necessária;<br>• sinalizações S1–S3;<br>• minuta de decisão não assinada;<br>• questões Q1–Q5.<br>Nenhuma alternativa aprovada. 6.1 NÃO DEMONSTRADO; 6.2 aguardando decisão. FREEZE ATIVO. |
| 1.1 | **Correção localizada (2026-09-27, `BATCH12-2830-INDEX-6.2-ADJUDICATION-READINESS-CORRECTION-01`), documental, sem SQL e sem acesso ao LIVE.** Ponto da auditoria independente na lacuna A do §4:<br>• A dividida em A.a (`card_id` reais e cardinalidades diferentes, no canal `postgres`) e A.b (papel efetivo do consumidor);<br>• P9A-05 mantido como evidência complementar, não conclusiva, restrito a A.a; registrado que ele não comprova a forma do plano sob o papel do consumidor;<br>• A.b exige readiness e mandato próprios, se for considerada necessária;<br>• nota de leitura de "A" como grupo;<br>• S2 com encaminhamento à preparação da fase 5, sem alterar a 960.<br>Matriz de alternativas, minuta e Q1–Q5 inalteradas; contratos canônicos inalterados. FREEZE ATIVO. |
