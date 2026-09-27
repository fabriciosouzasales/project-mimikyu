# 2830H — Fase 5: decisões transversais (L2–L13) e encaminhamento da D-1

| Campo | Valor |
|---|---|
| **Documento** | `BATCH12-2830-P5-TRANSVERSAL-DECISIONS-AND-D1-01` (2026-09-27), baseline HEAD `e6af59c18e53b656a54410e80a8b070c4e292a89`. |
| **Natureza** | Auditoria de estado, matriz de decisões e análise técnica, **documental e local**. Nenhum SQL (nem SELECT), nenhum acesso ao LIVE, nenhum ambiente provisionado, nenhuma cópia de dados, nenhum envelope ou verificador alterado, contrato 2830 intacto. |
| **Estado** | **v1.2 — decisões de engenharia registradas** (`BATCH12-2830-P5-ENGINEERING-DECISIONS-01`, §9): D-2 = C, DP-2 = B, DP-3 = C, DP-4 = A, DP-5 = B; preparação de proposta v7.1 para A2/E1/R-P9 aberta; P7 em via 4 (bloqueio) com investigação das vias 2 e 3; D-1 com arquitetura CN-1/I-L adotada como **proposta**, P14 **não** cumprido. DV-1 **encerrada** (§1.2). A 2830 v7.0 segue vigente e inalterada; nenhuma autorização de escrita LIVE; L2 não implementado. **v1.0/v1.1 (histórico):** proposta sem decisões. **FREEZE ATIVO.** |
| **Autoridades** | 2830 v7.0 (blob `b4647dcb…`, P1–P14, CRITÉRIOS A–E) · `LIVE-VALIDATION-PROTOCOL.md` (`abe806d6…`, §7 AD-1..AD-10, §8 D-1..D-9) · `PHASE5-AUTOMATED-COVERAGE-READINESS.md` (`1aa8d71d…`, §3–§8) · `2830-V7.1-PROPOSAL-ADMIN-CONCURRENCY.md` (proposta, não aprovada; CN-1..CN-6) · registros LIVE do harness · `EXECUTION-BATCHES.md` (Batch 12). Em divergência, prevalecem as autoridades; este documento não cria critério. |
| **Convenção** | **[F]** fato comprovado nesta rodada (arquivo, blob, saída registrada) · **[V]** decisão anterior vigente · **[P]** proposta nova · **[E]** pendência de evidência · **[B]** blocker material. |

---

## 1. Estado atual do Batch 12

### 1.1 Gate de entrada (local, sem banco)

| Item | Resultado |
|---|---|
| HEAD | [F] `e6af59c18e53b656a54410e80a8b070c4e292a89` ("docs: close out audited E03 live execution with 13 contractual passes") = baseline |
| Árvore e índice | [F] 0 e 0 linhas |
| Último commit | [F] contém só `LIVE-L1-E03-EXECUTION-RECORD.md` (novo), a linha do README e a linha do `docs/log.md` |
| Três blobs publicados do E03 | [F] registro `65de509ca79110b474e9e3839b8e60e5b0c5f392` · envelope `ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e` · plano `b3eba41c2e1fb32efe1f3960762cfe1c23f9dbb1` — todos modo 100644, árvore = HEAD (readiness do E03 `9080f2ad…` idem) |
| `static_check` | [F] `444/444` · `88/88` · `79/79` · `6/6` (blob `79c4fd42…` inalterado) |
| Contrato 2830 | [F] `b4647dcb…`, inalterado |

### 1.2 Divergência documental (sinalizada, sem STOP) — **encerrada na v1.2**

- **DV-1 [F]:** o mandato declara E03 **CLOSED, auditado** e cobertura **30/135**. O commit `e6af59c` confirma o fechamento pela mensagem, mas o conteúdo publicado ainda diz o contrário: o registro do E03 (blob `65de509c…`) tem Estado "v1.0 — para auditoria independente" e "cobertura declarada 17/135 até o parecer"; a linha do README e a do `docs/log.md` dizem o mesmo; nenhum documento do repositório registra o parecer PASS nem 30/135.
- **Encerramento (v1.2):** `LIVE-L1-E03-EXECUTION-RECORD.md` v1.1 incorpora o parecer PASS e a cobertura 30/135 (novo §8), com o texto da v1.0 preservado; README e log alinhados.
- **Tratamento (v1.0, histórico):** este documento adota **30/135 como decisão vigente de Fabrício** (mandato + commit de fechamento) [V], e registra DV-1 como pendência documental. A correção (Revision History 1.1 do registro com o parecer, README, log e, se for o caso, `PHASE5` §3) **não é feita aqui**: está fora do escopo desta rodada. Não afeta segurança, integridade nem os lotes.

### 1.3 Cobertura e posições

| Frente | Estado |
|---|---|
| Automáticos PASS-LIVE | [V] **30/135**: 1.1–1.12 (Etapa 3), D1–D5 (Etapa 2), 2.1–2.5 e 2.7–2.14 (E03) |
| Automáticos restantes | [F] **105**, distribuídos em L2–L13 (§4) |
| Evidências históricas C1–C3 (D6–D8) | [F] sem registro de verificação no harness |
| Manuais | [V] 6.3 cumprido (2840, Batch 10); [F] 6.1 NÃO DEMONSTRADO; 6.2 EVIDÊNCIA — CENÁRIO PEQUENO, aguardando decisão; K1, K2, K8b e paridade (D4) não executados |
| UNFREEZE | [V] BLOQUEADO (2830 E1–E5; protocolo §8 D-1) |

### 1.4 Estado efetivo das decisões

| Decisão | Estado | Fonte |
|---|---|---|
| **D-1** — ambiente isolado para K1/K2/K8b (e D4) | [V] **PENDENTE**. Pago recusado; sem custo "não prescrito, P14 obrigatório" | protocolo §8; v7.1 §5.2 (proposta) |
| **D-2** — aceitar AD-2 no lugar de P9b (A2) | [V] **PENDENTE** como decisão global. Existem **só** decisões pontuais: E01 (Etapa 3, por mandato), E03T (DP-1 = A′) e E03 (DP-1 = A) | protocolo §8; readiness v1.3 §2.1; readiness do E03 §4.1 |
| **DP-2** — ordem dos lotes | [V] **PENDENTE** (proposta: desvio de L5; antecipação opcional de L8/L9) | `PHASE5` §5.4, §8 |
| **DP-3** — precheck por lote × sucessor do E00 | [V] **PENDENTE** como decisão geral. O L1 usou precheck complementar (E03P) com E00 intacto — decisão implícita **só para o L1** | `PHASE5` §8; E03P |
| **DP-4** — `lock_timeout` | [V] decidido **só** para E01 (D-3 = sem `SET LOCAL`), E03T (DP-4 = B) e E03 (DP-4 = A). **Não se estende** a L2–L13 | protocolo §8 D-3; readiness v1.3 §2.2; readiness do E03 §4.2 |
| **DP-5** — escrita transitória | [V] decidido **só** para E01, E03T e E03, cada uma **esgotada** na sua execução. **Nenhuma** autorização vigente para L2–L13 | registros LIVE |
| DP-6 — trilha 960 | [V] PENDENTE, não bloqueia lotes | `PHASE5` §6, §8 |

## 2. Matriz de decisões transversais (proposta; nada aprovado)

Cada decisão abaixo é **independente**; a §8 reúne os campos de deliberação.

### 2.1 D-2 — performance (P9b / A2)

**Requisito literal [F]:** 2830 P9(b): tempo real medido em **ambiente isolado representativo** (P14), mesmas contagens do FREEZE e mesma impressão digital (P14a), ANALYZE, 3 execuções (1 com cache frio), pior caso ≤ 60 s por envelope; "nenhum envelope vai ao LIVE sem a medição registrada"; e "pior tempo observado no LIVE acima do medido no ambiente = FAIL de harness". A2 exige isso; E1 exige A **integralmente satisfeito** para o UNFREEZE.

| Opção | Descrição | Segurança / integridade | Performance / concorrência | Reaproveita E03 | Dependências | Consequência |
|---|---|---|---|---|---|---|
| **A — literal** | P9b para todo envelope restante, no ambiente de D-1 | máxima; nenhuma escrita LIVE sem medição prévia | medição prévia real; **risco R-P9**: se o ambiente for mais rápido que o LIVE, qualquer execução LIVE mais lenta vira FAIL de harness pela regra literal | não (o E03 usou AD-2) | **D-1 resolvida com representatividade de dados** (cópia das contagens do FREEZE) | todos os 12 lotes esperam a D-1; caminho mais longo |
| **B — AD-2 global** | AD-2 para todos os lotes: tempo medido no próprio LIVE, `statement_timeout` 120 s comprovado na L1, aceite ≤ 60 s; P9a (EXPLAIN) obrigatório para seções pesadas (L10, L11, L13) | escrita LIVE sem medição prévia, limitada por teto duro de 120 s e rollback estrutural (precedente: E01, E03T, E03 — 251, 133 e 202 ms) | sem evidência prévia para as seções pesadas; risco de `57014` só descoberto no LIVE (sem dano: rollback) | **sim** (DP-1 = A do E03, integral) | nenhuma | lotes andam sem D-1; **A2 não é cumprido** (só adaptação operacional) — ver níveis abaixo |
| **C — híbrida** | AD-2 para lotes leves (L2–L9, L12); P9b literal, no ambiente de D-1, para **B, M e 5.x** (L10, L11, L13); P9a no LIVE para esses três | risco LIVE concentrado em envelopes de milissegundos, já com precedente | mede antes o que pode ser pesado; o resto segue o padrão aprovado | sim, para os leves | D-1 só para L10, L11, L13 | Grupo A e L5–L7, L12 avançam já; pesados esperam D-1 |

**Quatro níveis que não se confundem [F/P]:**

| Nível | O que é | Quem decide / como | Efeito sobre a 2830 |
|---|---|---|---|
| **1. Adaptação operacional** (AD-2) | autoriza **executar** um envelope no LIVE sem a medição prévia de P9b, com teto de 120 s e aceite ≤ 60 s | decisão de Fabrício, registrada no protocolo ou no mandato de execução (precedentes: E01, E03T, E03) | **nenhum**: a 2830 continua imutável; P9b e A2 **não** passam a estar cumpridos |
| **2. Cumprimento literal de P9b/A2** | medição em ambiente isolado representativo (P14a, contagens do FREEZE, ANALYZE, 3 execuções, 1 fria, pior ≤ 60 s) **antes** do LIVE | só pela execução da medição, com evidência registrada | é a única via, pela 2830 v7.0 vigente, de cumprir A2 |
| **3. Satisfação de E1 (UNFREEZE)** | E1 exige A, B, C e D **integralmente** satisfeitos | constatação sobre evidências | com o nível 1 apenas, A2 **não** está satisfeito ⇒ E1 **não** está satisfeito. Nenhuma deliberação operacional pode declarar o contrário |
| **4. Alteração formal do contrato** | nova versão da 2830 (v7.1 ou posterior) que mude A2, E1 ou a regra comparativa de P9b | mandato próprio de especificação, auditoria independente e publicação — como a v7.0 foi produzida | só este nível pode mudar critérios da 2830 |

- **Consequência [P]:** as opções B e C são adaptações de **nível 1**. Elas permitem avançar os lotes; **não** cumprem A2 e **não** satisfazem E1. Para que o UNFREEZE não dependa de P9b literal, seria necessário o **nível 4**, que esta rodada **não** propõe como aprovado.
- **Risco R-P9 (preservado) [F, texto da 2830 P9]:** "pior tempo observado no LIVE acima do medido no ambiente = FAIL de harness". Enquanto não houver alteração formal (nível 4), **essa regra vale como está** para toda medição feita sob P9b: um ambiente mais rápido que o LIVE pode produzir FAIL de harness. Substituí-la por uma comparação com o limite de 60 s **exige base contratual expressa**; uma deliberação operacional não basta. Mitigação sem mudar a regra (hipótese, não demonstrada): ambiente de medição com capacidade igual ou inferior à do LIVE.
- **Recomendação [P]:** **C** como adaptação operacional de nível 1 para executar os lotes. Separadamente, e sem pré-aprovação, Fabrício decide se abre um **mandato de especificação** (nível 4) para tratar A2/E1 e a regra R-P9; até lá, A2 e E1 seguem pendentes e R-P9 vigente. Se a D-1 não for adotada, **B** (nível 1) com P9a obrigatório para L10, L11, L13 — com o mesmo efeito: A2/E1 continuam não cumpridos.

### 2.2 DP-2 — ordem dos lotes

**Fato [F]:** a ordem "contratual" é a ordem das seções na 2830 (1, 2, 2B, 2T, 2Q, 3, 4, S, R, K, B, M, G, D, 5). A 2830 não contém cláusula que obrigue executar os envelopes nessa ordem; a `PHASE5` §5.4 tratou qualquer desvio como sujeito a DP-2. 2.6 e 3.3 dependem de infraestrutura de `game` (I-3a/I-4a).

| Opção | Sequência | Impacto | Reaproveita E03 | Dependências | Consequência |
|---|---|---|---|---|---|
| **A — contratual com desvio único** | L2 → L3 → L4 → L5 → L6 → L7 → L8 → L9 → L10 → L11 → L12 → L13 | nenhum ganho de risco; L5 bloqueia L6–L13 enquanto I-3/I-4 não existirem | parcial | I-3/I-4 antes de L5 | Grupo A parado atrás de L5 |
| **B — por grupo de infraestrutura** | **Grupo A:** L2 → L3 → L4 → L8 → L9; em paralelo, implementação de I-3/I-4; **Grupo B:** L5 → L6 → L7 → L12 → L11; pesados **L10, L13** por último (D-2/D-1, I-5, I-6) | nenhum risco adicional: os lotes são independentes na verificação (arestas complementares não bloqueantes, `PHASE5` §5.1) | **máximo** para o Grupo A | I-3/I-4 para L5–L7, L11, L12; I-5 para L13; I-6 para L10, L11, L13 | 5 lotes (45 casos) sem infraestrutura nova |
| **C — pesados primeiro** | L10/L11/L13 antes | concentra risco de performance cedo | nenhum | D-1/D-2, I-5, I-6 | atrasa tudo |

**Recomendação [P]:** **B**. Desvios declarados: L8 e L9 antes de L5–L7; L12 antes de L11 (L11 depende também de I-6); L10 e L13 no fim. Nenhuma prova de um lote depende de outro lote ter passado (arestas V10↔G2/G8, SM10(ii)↔G2, S10(d)↔G5/G6, K4↔4.2 são complementares).

### 2.3 DP-3 — estratégia de precheck

**Fatos [F] (saída do E00 do E03, registro §B.3):**
- o gate P7 do E00 cobre só as 5 tabelas EC (`gate_scope`); `card_variant`, job, row, action log e `game` são só inventariados;
- no fecho P7 dessas tabelas há **8 funções `UNCLASSIFIED`**, das quais **4 com `search_path_unsafe = true`** (`public.set_updated_at` com `search_path=public, pg_temp`; `public.validate_card_variant_game_consistency`, `public.normalize_catalog_variant_import_job` e `public.normalize_catalog_variant_import_row` sem `proconfig`) e **4 com CRLF** no corpo (`enforce_card_variant_edition_context_profile_game` 36, `guard_cvir_normalized_shape` 62, `set_updated_at` 5, `validate_card_variant_game_consistency` 40);
- portanto, estender `gate_scope` a essas tabelas **reprova hoje** `g_p7_all_classified` e `g_p7_search_path_safe` [B para L6, L7, L11, L12 — ver §3 do Grupo B].

| Opção | Descrição | Segurança / integridade | Reaproveita E03 | Dependências | Consequência |
|---|---|---|---|---|---|
| **A — E00 intacto + precheck por lote (E0xP)** | padrão do E03P: SELECT único, gates do lote, E00 inalterado | provado no LIVE (E03T, E03); mas **não** estende o fecho P7 — um E0xP que reimplementasse o P7 para `game`/`card_variant`/job/row duplicaria a lógica mais complexa do harness | **sim** | I-2 por lote | serve integralmente ao Grupo A; insuficiente para o fecho P7 do Grupo B |
| **B — sucessor versionado único (E00′/E99′)** | novo blob do E00 e do E99 com `gate_scope` estendido, allowlist adjudicada das 8 funções e resíduo de `game`/`card_variant`/job/row | uma fonte de verdade para o P7; mas **muda o E00 já provado** e invalida a comparação byte a byte de blocos E00/E99 até nova auditoria | não | adjudicação das 8 funções (classe D-6/D-9) e decisão sobre as 4 `search_path_unsafe` | nova rodada de auditoria antes de qualquer lote |
| **C — híbrida** | Grupo A: **A**; Grupo B: **B** (sucessor versionado, construído uma vez, reaproveitado por L5–L7, L11, L12) | cada lote usa o precheck mínimo que cobre seu fecho P7 | sim, no Grupo A | como B, só para o Grupo B | Grupo A começa sem mexer no E00 |

**Recomendação [P]:** **C**. Para o Grupo B, as 4 funções `search_path_unsafe` são pré-requisito.

**Identidade pinada não corrige `search_path` inseguro [F].** Uma entrada de allowlist com pino (nome, argumentos, linguagem, `SECURITY DEFINER`, `proconfig`, md5 do corpo — padrão D-9) prova **que a função é exatamente aquela**; ela **não** muda o `search_path` da função nem o risco de resolução de nomes. Adjudicar e pinar não torna o fecho "search_path seguro" pela regra P7. As vias possíveis, distintas:

| Via | O que é | Requisito | Efeito sobre o gate `g_p7_search_path_safe` |
|---|---|---|---|
| **1. Exceção contratual formalmente aprovada** | a regra P7 passa a admitir, por texto, funções nomeadas com `search_path` não vazio, com justificativa | alteração formal (nova versão da 2830/protocolo, mandato de especificação, auditoria, publicação) | o gate passa a refletir a regra **nova**, explícita; o risco é aceito, não eliminado |
| **2. Correção efetiva da função** | `ALTER FUNCTION … SET search_path = ''` (ou equivalente) e qualificação dos nomes no corpo | DDL no LIVE: mandato próprio, blob, auditoria, decisão sobre o FREEZE | o gate fica verdadeiro porque a condição ficou verdadeira |
| **3. Reformulação tecnicamente demonstrada** | casos do lote que **não** disparam essas funções | prova estática e fecho P7 recalculado mostrando que as funções saem do fecho do lote | o gate não se aplica a funções fora do fecho — só se demonstrado |
| **4. Manutenção do bloqueio** | nada muda | — | o gate continua falso; os lotes afetados não executam |

**Proibição [P]:** nenhuma implementação pode transformar uma condição falsa em gate verdadeiro por alteração cosmética do verificador — por exemplo, remover tabelas ou funções do `gate_scope` sem a demonstração da via 3, afrouxar o padrão de `search_path`, tratar a allowlist como dispensa da checagem de `search_path` ou mudar o valor esperado. Qualquer mudança no E00, no E99 ou no `static_check` que afete esse gate exige a via 1, 2 ou 3 concluída e auditada.

**Recomendação para as 4 funções [P]:** via **4** (manter o bloqueio) até que a via **2** ou a **3** seja demonstrada e aprovada; a via **1** só por alteração formal. Nenhuma via é proposta como aprovada.

### 2.4 DP-4 — `lock_timeout` por lote

**Fatos [F]:** 2830 P8 especifica `SET LOCAL lock_timeout = '5s'` como primeira instrução com asserção; o E03 provou no LIVE a aplicação (asserção passou) e a não persistência (`g_lock_timeout_default`); o `static_check` E03-20 é **específico do E03** (regra por nome de envelope) e o E03T proíbe `SET LOCAL`.

| Situação | Opção | Impacto | Reaproveita E03 | Dependência |
|---|---|---|---|---|
| Lotes que escrevem (L2–L8, L11, L12) | **A — transacional** (preâmbulo P8 idêntico ao E03) | limita espera a 5 s; `55P03` fail-closed; custo zero | **sim** (texto, semântica, §5.7 da readiness do E03) | generalizar a regra E03-20 do `static_check` para o perfil de cada lote (I-2) |
| | B — ausência autorizada (como E01/E03T) | espera limitada só pelos 120 s | sim (padrão E01) | decisão registrada por lote (A5) |
| Lotes só leitura (L9, L10, L13) | **A** (mesmo preâmbulo) ou B | leituras podem esperar `AccessExclusiveLock` de DDL; sob FREEZE improvável | sim | idem |
| Envelope dividido (L10, se a readiness de seção pesada exigir) | A em **cada** envelope | cada envelope é uma transação | sim | readiness do L10 |
| Situações que exigem **novo mecanismo** | K1/K8b (espera **deliberada** por lock, sessões persistentes) | `lock_timeout` de 5 s interromperia a prova de espera; exige valor próprio **no ambiente isolado** e nunca no LIVE | não | D-1 |

**Recomendação [P]:** **A** como padrão para todos os envelopes de L2–L13, cada um com asserção fail-closed e prova de não persistência pelo E99; B só por decisão individual registrada; K1/K8b fora deste padrão (D-1).

### 2.5 DP-5 — superfície de escrita transitória

**Fato [F] (`PHASE5` §5.4):** L2, L3, L4, L8 escrevem só em tabelas EC; L5 em `game` (sentinela) + EC; L6 em `card_variant` (só INSERT); L7, L11, L12 em job/row; L9, L10, L13 não escrevem.

| Opção | Descrição | Consequência |
|---|---|---|
| **A — autorização por lote no mandato de execução** (padrão E03) | superfície inventariada por caso a partir do **blob auditado**, nomeada tabela a tabela, esgotada numa execução | segurança máxima; uma deliberação por lote |
| **B — política-padrão + autorização por lote** | Fabrício aprova agora **só a política** (o que toda autorização de lote deve conter e os níveis de risco); a autorização concreta continua por lote, vinculada ao blob e ao mandato | reduz retrabalho de deliberação sem criar autorização coletiva |
| ~~C — autorização coletiva~~ | — | **rejeitada** pelo mandato |

Níveis de risco propostos para a política (B): **R1** só EC (L2, L3, L4, L8); **R2** `game` sentinela (L5); **R3** `card_variant` com triggers `set_updated_at` e `validate_card_variant_game_consistency` (L6); **R4** job/row com guard 2214 e índice de fingerprint (L7, L11, L12); **R0** sem escrita (L9, L10, L13 — sem DP-5).

**Recomendação [P]:** **B**. Conteúdo mínimo de toda autorização de lote: blob do envelope; tabelas; contagem de INSERT/UPDATE/DELETE por tabela; eventos diferidos; subtransações; proibição de tocar linha pré-existente; rollback obrigatório; E99 (ou sucessor) + L3 final; esgotamento na execução.

## 3. D-1 — ambiente isolado (análise técnica)

### 3.1 O que P14 exige, literalmente [F]

- **(a)** paridade **provada** por impressão digital read-only no LIVE e no ambiente (md5 de `pg_get_functiondef` do confirm, writer, guard 2214, guard 2224, `axis_identity_token`, `resolve_variant_row_axes`; índices e constraints de identidade; triggers); o ambiente é montado com os **blobs exatamente executados** (o ledger não reproduz o LIVE);
- **(b1)** K2 com **usuário admin real**, promovido pelo mecanismo real de `is_admin()`, chamado **via HTTP com JWT**; **(b2)** K1/K8b em **conexões Postgres persistentes**, identidade do mesmo UUID por `SET LOCAL` de papel/claims **só no ambiente**;
- **(c)** prova de canal (pid constante, `txid_current()`/`now()` constantes, `idle in transaction` visível, `auth.uid()` = admin e `is_admin() = true`);
- **(d)** fixtures sintéticas; ambiente descartado e descarte registrado; **(e)** evidências registradas.
- **P9(b)**, se o mesmo ambiente medir tempo: **mesmas contagens do FREEZE** (staging 26.127, jobs 145, `card_variant` 24.893, vocabulário 115/144/196/122, universo 1.642) — isso exige **dados**, não só fixtures.

### 3.2 Fatos locais relevantes [F]

- `supabase/config.toml` só tem seções `[functions.*]`: não há configuração de stack local (`[db]`, `major_version`); `supabase/migrations/` não existe; o schema do projeto vive em `database/` (207 arquivos em `migrations/`, 298 em `schema/`), sem ordem de replay provada contra o LIVE.
- LIVE: PostgreSQL `170006` (L1 das rodadas).
- `public.is_admin()` é `SECURITY DEFINER`, `search_path = ''`, baseada em `public.admin_user` (`database/schema/1060`).
- Documentação Supabase: a CLI local exige `supabase init` (gera `config.toml`) e a versão major do Postgres local deve ser a mesma do remoto; branches cobram uso (a partir de US$ 0,01344/h na Micro); o plano Free concede dois projetos gratuitos por titular. (Fontes no fim.)

### 3.3 Alternativas

| # | Alternativa | Isolamento | Representatividade (estrutura / dados) | Configuração relevante | K2 (b1) | K1/K8b (b2) | Performance (P9b) | Custo efetivo | Situação |
|---|---|---|---|---|---|---|---|---|---|
| **I-L** | **Supabase local via CLI + Docker** (CN-1) | total (máquina local) | estrutura: aplicar os blobs executados, na ordem, e provar P14a; dados: fixtures bastam para K; P9b exige cópia das contagens (dump seletivo, mandato próprio, sem dados de usuário) | PG major 17 fixável no `config.toml`; Auth local com JWT real; PostgREST local | **sim** (usuário real no Auth local + `admin_user`) | **sim** (psql, 3 conexões) | **com ressalva**: hardware local ≠ LIVE (risco R-P9) | zero monetário; exige Docker e disco na máquina de Fabrício | **hipótese não testada** |
| I-F | **Novo projeto Supabase no plano Free** | total (instância separada) | idem I-L; dados copiados para nuvem exigem avaliação de governança | versão do PG definida pela plataforma (verificar = 17) | sim (Auth real) | sim (conexão direta) | hardware de nuvem pequeno; ressalva R-P9 | zero **se** houver cota Free disponível e o projeto não cair numa organização paga — **não verificado** | hipótese; depende de fato de conta |
| I-B | **Branch do Supabase** | total | construído pelo fluxo de migrations do projeto, que **não** reproduz o LIVE (ledger incompleto); exigiria reaplicar blobs | igual ao projeto | sim | sim | idem | **pago por hora** | **contraria "sem custo"** (D-1 já recusou pago) |
| I-P | **PostgreSQL 17 puro (sem stack Supabase)** | total | estrutura precisa emular `auth` | sem Auth/PostgREST | **não** literal (sem JWT/HTTP real) | sim, com claims simuladas | ressalva R-P9 | zero | **não atende K2 (b1)** ⇒ só parcial |
| I-S | Supabase self-hosted (docker-compose) | total | idem I-L | completo | sim | sim | ressalva R-P9 | zero monetário, operação mais pesada | hipótese; sem vantagem sobre I-L |
| ~~I-X~~ | schema/banco temporário **no mesmo projeto LIVE** | **não** isolado | — | — | — | — | — | — | **rejeitada**: viola FREEZE e a proibição de claims/escrita no LIVE |

**Conclusão [P]:** a única classe que pode cumprir P14 (a, b, c) sem custo é **CN-1** (I-L, ou I-F se a cota Free for confirmada). **Nenhuma** foi demonstrada. D-1 **não está resolvida**.

### 3.4 Proposta operacional verificável (não executada)

**Fase D1-0 — decisão de Fabrício:** adotar CN-1 (tecnologia I-L preferencial; I-F como alternativa condicionada à verificação de cota), e decidir se o mesmo ambiente servirá **também** à P9b (exige cópia de dados) ou **só** a K1/K2/K8b (fixtures).

**Fase D1-1 — preparação (mandato próprio, sem LIVE):** `config.toml` com PG major 17; stack local de pé; lista ordenada dos **blobs executados** (fonte: registros e `EXECUTION-BATCHES`), com hash; script de montagem.

**Fase D1-2 — paridade (mandato próprio, SELECT no LIVE + ambiente):** consulta de impressão digital P14a, **um texto único com md5**, rodada nos dois lados.

**Fase D1-3 — canal:** P14c no ambiente.

**Critérios de aceite do ambiente (todos) [P]:**
1. `server_version_num` com mesma major (17) e diferença de minor registrada;
2. impressão digital P14a **igual** (hash normalizado LF; hash bruto diferente exige adjudicação, regra D-6);
3. `is_admin()` e `auth.uid()` reproduzidos com o mesmo corpo (md5) e um usuário admin real criado pelo Auth do ambiente;
4. P14c provado nas três sessões;
5. nenhuma credencial, dado de usuário ou segredo do LIVE copiado; dados de fixture sintéticos (se a P9b for incluída: cópia só das tabelas de catálogo/staging necessárias, por mandato próprio);
6. descarte do ambiente registrado ao final.

**STOP [P]:** qualquer divergência de impressão digital; major ≠ 17; necessidade de aplicar algo que não seja blob executado; dependência de claims no LIVE; necessidade de copiar dados de usuário; custo monetário não autorizado; conexão do ambiente com o LIVE fora da consulta de paridade.

**Limites declarados:** um CN-1 aceito resolve K1, K2, K8b e D4; **não** resolve 6.1/6.2 (EXPLAIN no LIVE), C1–C3 nem A2 (só P9b literal ou alteração formal do contrato); e a medição local de tempo está sujeita à regra R-P9 vigente.

## 4. Matriz de dependências dos 12 lotes restantes

| Lote | Casos (n) | Grupo | Escrita (DP-5) | Precheck (DP-3) | Infra nova | `lock_timeout` (DP-4) | Performance (D-2) | Bloqueios |
|---|---|---|---|---|---|---|---|---|
| **L2** | 2B.1–2B.6, 2T.1–2T.8 (14) | A | R1: mapping, mapping_trait, trait | E00 + E04P | I-2 (perfil) | A | AD-2 | universo 2B.5/2B.6 > 0 (P13) |
| **L3** | 2Q.1–2Q.10 (10) | A | R1: UPDATE de cabeçalho só em fixture | E00 + E05P | I-2 | A | AD-2 | tokens literais N-3; colisão com mapping LIVE = STOP |
| **L4** | 3.1, 3.2, 3.4–3.7 (6) | A | R1 + leitura de catálogo | E00 + E06P | I-2 | A | AD-2 | escopo de 3.7 resolvível |
| **L8** | R1–R12 (12) | A | R1 | E00 + E10P | I-2 | A | AD-2 | R2/R10 estáticos declarados |
| **L9** | K3, K4, K8 (3) | A | R0 | E00 (+ E11P se necessário) | I-2 | A ou B | AD-2 | nenhum |
| **L5** | 2.6, 3.3 (2) | B | R2: `game` sentinela + EC | sucessor E00′/E99′ | I-3a, I-4a | A | AD-2 | trigger de `game` a confirmar no fecho [E] |
| **L6** | 4.1–4.8 (8) | B | R3: `card_variant` INSERT | sucessor | I-3b, I-4b | A | AD-2 | **[B]** 2 funções `search_path_unsafe` e 3 com CRLF no fecho de `card_variant` |
| **L7** | S1–S11, S2-BIS (12) | B | R4: job/row | sucessor | I-3c, I-4c | A | AD-2 | **[B]** 2 funções `search_path_unsafe` e 1 com CRLF no fecho de job/row (o `DISTINCT ON` do E00 mostra uma raiz por função: funções compartilhadas com outras tabelas a confirmar [E]) |
| **L12** | G1–G8 (8) | B | R4 | sucessor | I-3c, I-4c | A | AD-2 | idem L7 |
| **L11** | SM1–SM11 (11) | B | R4 | sucessor | I-3c, I-4c, I-6 | A | P9b (opção C) | idem L7; universo confirmável vazio ⇒ controles negativos (P13) |
| **L10** | V1–V14 (14) | B | R0 | E00 + E12P | I-6 | A | P9b (opção C) | divisão do envelope definida após P9a |
| **L13** | 5.1–5.3, 5.6, 5.7 (5) | B | R0 | E00 + E15P | I-5, I-6 | A | P9b (opção C) | constante medida ≠ documento ⇒ STOP (5.2/5.7) |

- **Soma [F]:** 14 + 10 + 6 + 12 + 3 = **45** (Grupo A) · 2 + 8 + 12 + 8 + 11 + 14 + 5 = **60** (Grupo B) · total **105**.
- Correção em relação ao plano do E03 §12.3 (47 casos no Grupo A): o número exato é **45**.

## 5. Caminho crítico até 135/135 e até o UNFREEZE

1. **135/135 automáticos:** Grupo A (45) → I-3/I-4 com a adjudicação das 8 funções [B] → L5, L6, L7, L12, L11 → I-5/I-6 + D-2 → L10, L13. O **caminho crítico dos automáticos** é a adjudicação P7 do Grupo B (DP-3, §2.3), não a D-1.
2. **UNFREEZE (E1–E5):** além dos 135, exige A2 (P9b literal ou alteração formal do contrato; adaptação operacional não basta), C1–C3, K1/K2/K8b + D4 (**D-1**), 6.1/6.2, baseline de FREEZE inalterado e mandato formal. O **caminho crítico do UNFREEZE** é a **D-1** (K2 não é dispensável).

## 6. Critérios históricos e manuais

| Critério | Dependência | Custo de prova | Situação |
|---|---|---|---|
| C1 (D6) | `git cat-file` dos blobs `426b3555…` (2215) e `3fc30f42…` (2216) + tokens antes do primeiro DROP | local, sem banco | [E] não registrado; executável num mandato curto |
| C2 (D7) | predicado no blob da 2216 + SELECT no LIVE | 1 SELECT | [E] mandato de leitura |
| C3 (D8) | SELECT no LIVE: 415 CANCELLED VALID+PENDING, `max(updated_at)`, identidades antigas ausentes | 1 SELECT | [E] mandato de leitura |
| D1–D4 (K1, K2, K8b, paridade) | **D-1** (CN-1) | ambiente + roteiros | [B] |
| D5 (6.1, 6.2) | decisão sobre a proposta 6.2 e encaminhamento de 6.1 | documental | [V] aguardando Fabrício |
| D6 (6.3) | — | — | [V] cumprido |

## 7. Próximo lote elegível para implementação

**L2** (2B.1–2B.6, 2T.1–2T.8; 14 casos) [P]: primeiro lote do Grupo A na ordem contratual; escreve só em tabelas EC; reaproveita E00, E99, o padrão E03/E03P, o protocolo S0–S7 e a classificação vigente; precisa de I-2 (perfil no `static_check`) e da generalização da regra E03-20. Condições para o **mandato de implementação** (não de execução): DP-3 (opção A para o Grupo A) e DP-4 (opção A) decididas; readiness de implementação do L2 própria. A execução exige, depois, D-2 (ao menos AD-2 para o L2), DP-5 do lote e mandato próprio.

## 8. Proposta de deliberação conjunta (campos em branco — histórico da v1.0/v1.1; a deliberação está no §9)

| # | Decisão | Recomendação técnica | Deliberação de Fabrício |
|---|---|---|---|
| 1 | **D-2** — A literal / B AD-2 global / C híbrida (adaptação operacional, nível 1; não altera a 2830, não cumpre A2, não satisfaz E1) | **C**; A2, E1 e R-P9 seguem a 2830 vigente | ☐ A ☐ B ☐ C · mandato de especificação (nível 4) para A2/E1/R-P9: ☐ abrir ☐ não abrir |
| 2 | **DP-2** — A contratual / B por grupo / C pesados primeiro | **B** | ☐ A ☐ B ☐ C |
| 3 | **DP-3** — A E0xP / B sucessor / C híbrida | **C** | ☐ A ☐ B ☐ C |
| 3a | Funções `search_path_unsafe` do Grupo B | manter o bloqueio (via 4) até a via 2 ou 3 ser demonstrada; via 1 só por alteração formal. Pino/adjudicação **não** corrige `search_path` | ☐ 1 exceção contratual formal (mandato de especificação) ☐ 2 corrigir funções (DDL, mandato próprio) ☐ 3 reformular casos (demonstração) ☐ 4 manter bloqueio |
| 4 | **DP-4** — padrão para L2–L13 | **A** (preâmbulo P8 + asserção), B só por exceção registrada | ☐ A ☐ B ☐ por lote |
| 5 | **DP-5** — A por lote / B política + por lote | **B** (política R0–R4; autorização sempre por lote/blob) | ☐ A ☐ B |
| 6 | **D-1** — CN-1 e tecnologia | adotar CN-1, I-L preferencial; decidir escopo (só K / K + P9b) | ☐ CN-1 I-L ☐ CN-1 I-F (após verificar cota) ☐ não adotar · escopo: ☐ só K ☐ K + P9b |
| 7 | **DV-1** — fechamento documental do E03 (parecer e 30/135 no repositório) | mandato documental curto | ☐ autorizar ☐ não |
| 8 | Próximo passo | mandato de implementação do **L2** após 3 e 4 | ☐ autorizar readiness do L2 |

Nenhum campo acima está preenchido. Nenhuma autorização de escrita LIVE é criada por este documento.

## 9. Decisões de engenharia registradas (v1.2)

Registro literal do mandato `BATCH12-2830-P5-ENGINEERING-DECISIONS-01` (baseline `36a3bc06`). Nenhuma decisão abaixo altera a 2830 v7.0, autoriza escrita LIVE ou implementa lote.

| # | Decisão | Conteúdo registrado | O que **não** decide |
|---|---|---|---|
| 1 | **D-2 = C** | estratégia híbrida: AD-2 operacional (nível 1) para lotes leves; P9b literal para **L10, L11, L13**. A 2830 v7.0 permanece vigente. **AD-2 não satisfaz A2/E1** | não cumpre A2; não satisfaz E1; não muda R-P9 |
| 1a | **D-2 contratual** | abrir a **preparação** de proposta v7.1 para A2, E1 e R-P9 (nível 4) | não altera nem aprova a 2830 vigente; a v7.1 exige mandato de especificação, auditoria e publicação |
| 2 | **DP-2 = B** | ordem por infraestrutura; Grupo A **L2 → L3 → L4 → L8 → L9**; Grupo B segundo as dependências documentadas (§4) | não autoriza nenhum lote |
| 3 | **DP-3 = C** | E00/E99 intactos + precheck específico por lote no Grupo A; sucessores versionados para o Grupo B **só depois** de resolvidos os bloqueios P7 | não cria o sucessor; não altera E00/E99 |
| 3a | **P7** | **via 4** — bloqueio preservado; investigar a via 2 (correção efetiva) e a via 3 (reformulação demonstrável). Identidade pinada não elimina `search_path` inseguro. Nenhum gate artificialmente verdadeiro | não aprova exceção contratual (via 1); não autoriza DDL |
| 4 | **DP-4 = A** | P8 transacional (`SET LOCAL lock_timeout = '5s'` + asserção fail-closed) em cada envelope aplicável; **verificador específico por lote**; K1/K8b fora dessa política | não altera o E03 nem a regra E03-20 existente |
| 5 | **DP-5 = B** | política R0–R4; autorização operacional concreta **sempre por lote**, identificando blob e superfície exata de escrita | não cria autorização coletiva |
| 6 | **D-1** | adotar **CN-1 / I-L** (Supabase local via CLI e Docker) como **arquitetura proposta**; escopo **K1, K2, K8b, P14 e preparação para P9b** | não declara P14 cumprido; não provisiona; não copia dados |
| 7 | **DV-1** | encerrada nesta rodada (§1.2) | não reabre o E03 |

**Consequência para o protocolo LIVE [F]:** `LIVE-VALIDATION-PROTOCOL.md` §8 continua registrando D-1 e D-2 como "PENDENTE"; o protocolo não foi alterado nesta rodada (fora do escopo). O estado vigente das duas decisões está neste §9.

## 10. Plano integrado de trabalho (L2, D-1, P7, v7.1)

Quatro trilhas independentes; cada passo exige mandato próprio. Nenhum passo abaixo está autorizado.

| Trilha | Passo | Entrega | Gate de entrada | Gate de saída (STOP se falhar) |
|---|---|---|---|---|
| **T1 — L2** | T1.1 readiness de implementação do L2 | contrato literal 2B/2T × 2207/2211, matriz caso → operação → aceite, contrato do E04P e do perfil E04 | §9 registrado e publicado | auditoria independente PASS |
| | T1.2 implementação local | `2830H_E04P_*.sql`, `2830H_E04_*.sql`, perfil E04 no `static_check` com controles negativos e positivos | T1.1 PASS | `static_check` com perfis E03 e E04 verdes; 444/444 preservado; E03 inalterado |
| | T1.3 readiness de execução + plano | S0–S7 do L2, DP-5 (R1) do lote | T1.2 auditado e publicado | auditoria PASS |
| | T1.4 execução LIVE | registro do L2 | mandato de execução próprio | CONFORME + ÍNTEGRO + auditoria ⇒ 44/135 |
| **T2 — D-1** | T2.1 especificação do ambiente | lista ordenada dos blobs executados (com hash), `config.toml` proposto (PG 17), consulta de impressão digital P14a com md5, roteiro P14c | §9 item 6 | auditoria PASS |
| | T2.2 provisionamento local | stack de pé na máquina de Fabrício | mandato próprio; Docker disponível [E] | major 17; nenhuma conexão ao LIVE |
| | T2.3 paridade | P14a nos dois lados (1 SELECT no LIVE, mandato próprio) | T2.2 | impressão digital igual (regra EOL D-6) |
| | T2.4 canal e K | P14c; K2 (b1), K1/K8b (b2) | T2.3 | critérios D1–D4 da 2830 |
| | T2.5 P9b (se escopo mantido) | cópia seletiva de catálogo/staging (mandato próprio, sem dados de usuário) e medição de L10, L11, L13 | T2.3 e lotes implementados | P9b literal; regra R-P9 vigente |
| **T3 — P7** | T3.1 investigação das 4 funções `search_path_unsafe` | para cada uma: corpo (repositório × E00), referências não qualificadas, efeito de `search_path = ''`, chamadores | §9 item 3a | documento de investigação auditado |
| | T3.2 via 2 ou via 3 | proposta de DDL corretiva (via 2) **ou** demonstração estática de que os casos não disparam a função (via 3) | T3.1 | aprovação expressa; nenhuma mudança cosmética no verificador |
| | T3.3 sucessor E00′/E99′ | só depois de T3.2 concluída | T3.2 | auditoria PASS |
| **T4 — v7.1** | T4.1 proposta de especificação | texto proposto para A2, E1 e R-P9, sem aplicar | §9 item 1a | auditoria PASS; aprovação expressa de Fabrício |

**Dependências entre trilhas [P]:** T1 não depende de T2, T3 ou T4 (L2 é Grupo A, AD-2). T3 bloqueia L6, L7, L11, L12. T2 bloqueia K1/K2/K8b, D4 e a P9b de L10, L11, L13. T4 condiciona a forma de cumprir A2/E1 (sem T4, só a P9b literal). O UNFREEZE depende de T2 e de A2 (T2.5 ou T4).

## 11. Minuta do próximo mandato de implementação LOCAL do L2 (não implementado)

**Identificador proposto:** `BATCH12-2830-P5-L2-IMPLEMENTATION-READINESS-01` (fase T1.1), seguido de `BATCH12-2830-P5-L2-IMPLEMENTATION-01` (fase T1.2), por mandatos separados, como no L1.

**Escopo [F, 2830 l. 480–515 e matriz `PHASE5` §2]:** 14 casos — 2B.1 (FXd), 2B.2 (FXd), 2B.3 (FX), 2B.4 (FXd), 2B.5 (RO), 2B.6 (RO), 2T.1–2T.3 (FXd), 2T.4–2T.5 (FX, 23505 em `uq_cecem_active_global` / `uq_cecem_active_scoped`), 2T.6–2T.8 (FXd + chamada à 2211).

**Condições técnicas a tratar na readiness [P/E]:**
1. fixtures só em `card_edition_context_trait`, `card_edition_context_external_mapping` e `card_edition_context_external_mapping_trait` (R1); UPDATE só em mapping de fixture; nenhuma linha pré-existente tocada;
2. P4 com `trg_cecem_seal` (IMMEDIATE → medir → DEFERRED) e sondas de modo autocontidas no padrão do E03;
3. o fecho P7 de `external_mapping`/`mapping_trait` já está no `gate_scope` do E00 e classificado [F, E00 do E03]: `normalize_edition_context_external_mapping`, `enforce_edition_context_mapping_header`, `seal_edition_context_external_mapping`, `enforce_edition_context_mapping_signature_write`, `guard_edition_context_mapping_composition_immutable`, `public.normalize_external_catalog_value` (EOL normalizado, D-6) e `extensions.unaccent` — **não** é afetado pelos bloqueios P7 do Grupo B;
4. `mapping_trait` tem `touched_now = false` no E00: o E04P precisa provar ausência de sequence nela (padrão `g_nn_no_sequence` do E03P);
5. 2T.6–2T.8 chamam `internal.resolve_variant_row_axes` (2211; no repositório `STABLE SECURITY DEFINER`, sem DML) com `p_external_set_id` declarado da fixture (via `resolve_variant_mapping_scope`, v7.0): o E04P deve pinar a identidade LIVE da função (md5 com EOL normalizado) [E]; a versão LIVE efetiva (2211 × 2233) tem de ser confirmada;
6. 2B.5/2B.6 emitem universo (122 esperados) e reprovam com universo 0 sem controle negativo (P13);
7. DP-4 = A: preâmbulo P8 e generalização da regra E03-20 como regra do perfil E04, sem alterar o comportamento do perfil E03;
8. D-2 = C: L2 é lote leve (AD-2), aceite `elapsed_ms ≤ 60000`, sem efeito sobre A2/E1.

**Proibições do mandato proposto:** nenhum SQL, nenhum LIVE, nenhum DDL; E00, E99, E03, E03P, E03T e 2830 inalterados; nenhum gate verdadeiro por alteração cosmética; sem `git add`, commit ou push.

**Critério de saída da fase T1.1:** readiness auditada, com fontes pinadas por blob (2207, 2211/2233, 2830) e lista de STOP; nenhum código escrito.

---

**Fontes externas (consultadas só para fatos de custo e configuração):**
- [Manage Branching usage | Supabase Docs](https://supabase.com/docs/guides/platform/manage-your-usage/branching)
- [Billing FAQ | Supabase Docs](https://supabase.com/docs/guides/platform/billing-faq)
- [Supabase CLI config | Supabase Docs](https://supabase.com/docs/guides/cli/config)
- [Supabase CLI reference — supabase start](https://supabase.com/docs/reference/cli/supabase-start)

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-TRANSVERSAL-DECISIONS-AND-D1-01`, baseline `e6af59c1`), documental, sem SQL e sem LIVE.**<br>• gate de entrada conforme; divergência documental DV-1 (30/135 e parecer do E03 ainda não registrados no repositório) sinalizada, sem STOP;<br>• estado efetivo de D-1, D-2, DP-2 a DP-6 (decisões do E01/E03T/E03 não se estendem);<br>• matriz de decisões D-2, DP-2, DP-3, DP-4, DP-5 com opções, impactos, reaproveitamento do E03 e recomendação; ponto crítico: AD-2 não cumpre A2/E1 sem cláusula expressa; risco R-P9;<br>• achado [B]: 8 funções `UNCLASSIFIED` (4 `search_path_unsafe`, 4 com CRLF) no fecho P7 de `card_variant`/job/row, que impedem estender o E00 ao Grupo B sem adjudicação;<br>• D-1: alternativas I-L, I-F, I-B, I-P, I-S (I-X rejeitada), proposta D1-0..D1-3 com aceite e STOP; D-1 não resolvida;<br>• matriz dos 12 lotes (Grupo A 45 casos, Grupo B 60), caminho crítico, critérios históricos/manuais, próximo lote L2, deliberação conjunta em branco. FREEZE ATIVO. |
| 1.1 | **Correção da auditoria independente (2026-09-27, `BATCH12-2830-P5-TRANSVERSAL-AUDIT-CORRECTION-01`, baseline `e6af59c1`), documental, sem SQL e sem LIVE.**<br>• A-1: D-2 separa adaptação operacional (nível 1), cumprimento literal de P9b/A2 (nível 2), satisfação de E1 (nível 3) e alteração formal da 2830 (nível 4); retirada a ideia de que uma deliberação operacional faz AD-2 cumprir A2/E1 ou troca a regra R-P9; R-P9 preservado até alteração formal; §3.4, §5 e §8 alinhados;<br>• A-2: identidade pinada não corrige `search_path` inseguro; vias 1 (exceção contratual formal), 2 (correção da função), 3 (reformulação demonstrada) e 4 (manter bloqueio); proibição de gate verdadeiro por alteração cosmética do verificador; recomendação: via 4 até 2 ou 3 demonstradas;<br>• A-3: DP-2 = B com 45 casos (Grupo A 45, Grupo B 60, total 105).<br>Demais opções, recomendações e evidências inalteradas. FREEZE ATIVO. |
| 1.2 | **Decisões de engenharia (2026-09-27, `BATCH12-2830-P5-ENGINEERING-DECISIONS-01`, baseline `36a3bc06`), documental, sem SQL e sem LIVE.**<br>• §9: D-2 = C (AD-2 operacional nos leves, P9b literal em L10/L11/L13; 2830 v7.0 vigente; AD-2 não satisfaz A2/E1); preparação de proposta v7.1 para A2/E1/R-P9 aberta; DP-2 = B; DP-3 = C; P7 em via 4 com investigação das vias 2 e 3; DP-4 = A com verificador por lote; DP-5 = B; D-1 com CN-1/I-L como arquitetura proposta (P14 não cumprido);<br>• DV-1 encerrada (registro do E03 v1.1, README e log);<br>• §10 plano integrado T1 (L2), T2 (D-1), T3 (P7), T4 (v7.1) com gates; §11 minuta do mandato LOCAL do L2 (não implementado);<br>• §1–§8 preservados como histórico (§8 com campos em branco). FREEZE ATIVO. |
