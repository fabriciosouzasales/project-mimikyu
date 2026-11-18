# V1-13 · E1-E1 — Reconciliação das evidências e preparação do protocolo de provas

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-E1 \| SECURITY EVIDENCE RECONCILIATION AND EXECUTION READINESS-01` (2026-11-15) |
| **Etapa oficial** | 6 — E1-E (provas de segurança). E1-E1, E1-E2 e E1-E3 são **subdivisões internas** da etapa 6, não fases novas. |
| **Status** | **E1 DEPLOY — PASS LIVE / BARRIER CLOSED (2026-11-18).** S0 v1.1, G2_A e G2_B aprovados no LIVE; E1 implantada (26 migrations) com a barreira CLOSED (`e1e2/README.md` §14–15). Provas com sessão real (S8 concorrente, S10, PR-04B, P4-A/P4-B, Storage pela API) continuam pendentes. Histórico: **PLANO DE EVIDÊNCIAS — DOCUMENTAL E ESTÁTICO. NADA EXECUTADO.** Sem conexão ao LIVE, sem S0, sem P1, sem SQL, sem harness, sem conta, sem fixture, sem commit. A aprovação deste plano **não** autoriza nenhuma execução. |
| **Revisão** | 1.2 — `D-E1 FORMALIZATION AND SERVER-SIDE BARRIER FEASIBILITY-03`: **D-E1 APROVADA (opção A)**; viabilidade estática da barreira em `BARRIER-FEASIBILITY-D-E1.md`. **Mecanismo NÃO aprovado; execução NÃO autorizada.** (1.1: P4 × etapas 7–10, isolamento da 5377, matriz de riscos.) |
| **Base** | `main` em `dbfdbaa` (E1-A … E1-D versionadas localmente). Contrato C-234–C-244, D1–D14, DR-1 inalterados. |
| **Vocabulário de estado** | **PREPARADO** (artefato escrito) · **ESTATICAMENTE VERIFICADO** (verificação de texto aprovada) · **EXECUTADO — PASS** · **EXECUTADO — FAIL** · **NÃO COMPROVADO** (sem execução dinâmica). Nenhuma prova recebe PASS dinâmico por inspeção. |

---

## 1. Inventário

### 1.1 Migrations (ordem canônica de aplicação; a numérica **não** é a de dependência)

| Inc. | Arquivo | Objetos | DDL / privilégios / gatilhos / políticas | Depende de (precheck) |
|---|---|---|---|---|
| E1-A | 5366 | CHECK de `collection_membership.role` passa a `VIEWER`/`EDITOR` | `ALTER TABLE collection_membership` (**ACCESS EXCLUSIVE**) | V1-12 (5300) |
| | 5367 | `collection_member_role` (interna) | EXECUTE revogado de PUBLIC/anon/authenticated (paridade de ACL com 5302) | 5300 |
| | 5368 | **substitui** 5309 `get_my_collection_invites`, 5311 `get_collections_shared_with_me`, 5312 `get_shared_collection` (chave `role`) | REVOKE/GRANT reaplicados | 5367 |
| | 5369 | convite `(uuid, text, text)` substitui `(uuid, text)` | troca de assinatura; GRANT authenticated | 5366, 5303 (md5) |
| | 5370 | `set_collection_member_role` | GRANT authenticated | 5366 |
| E1-B1 | 5371 | internas de autorização e classificação de bolsos | EXECUTE revogado | 5366, 5122 (md5) |
| | 5372 | **substitui** `binder_activity_add_item` (5268 → 5372) | precheck md5 = 5268 | E1-A, md5 5268 |
| | 5373 | `get_shared_binder_placeable_cards` | GRANT authenticated | 5366 |
| | 5374 | `editor_place/move/remove_*` | GRANT authenticated | 5371, 5372, 5272–5274 (md5) |
| E1-B2 | 5375 | reservas e fixação do EDITOR | GRANT authenticated | 5371, 5372, 5275, 5276–5278 (md5) |
| | 5376 | `assert_collection_editor` + metadados e capa | GRANT authenticated | 5366, 5035/5172/5178/5180 (md5) |
| | 5377 | 2 ajudantes + **3 políticas em `storage.objects`** (bucket `collection-cover`) | `CREATE POLICY` (**ACCESS EXCLUSIVE em `storage.objects`**, ver §6) | 5366, 5176, 5329 |
| E1-B3 | 5378 | **substitui** `binder_slot_editor_scope` (5371 → 5378) | — | md5 5371 |
| | 5379 | `binder_activity_item.collection_id`, `binder_activity_event.item_collection_recorded`; **substitui** `add_item` (5372 → 5379) | `ALTER TABLE` nas duas tabelas do histórico (**ACCESS EXCLUSIVE**, só catálogo) | md5 5372, 5257 |
| | 5380 | escritas Pokédex do EDITOR | GRANT authenticated | 5376, 6122–6126 (md5) |
| E1-C1 | 5381 | gatilho `trg_bae_editor_event_type` | `CREATE TRIGGER` em `binder_activity_event` (SHARE ROW EXCLUSIVE) | 5379 |
| | 5382 | páginas do EDITOR (fichário exclusivo) | GRANT authenticated | E1-B1, 5378, 5381 |
| | 5383 | referências de espécie do EDITOR | GRANT authenticated | 5258, 5382 |
| E1-C2 | 5384 | **substitui** a função do gatilho (5381 → 5384) | — | md5 5381 |
| | 5385–5387 | espaço, organização automática, novidades | GRANT authenticated | 5385: 5243, 5279, E1-B1, 5378, 5382 · 5386: 5360, 5385 · 5387: 5264, 5243, 5385. **5384 não é exigida pelo precheck**, mas é dependência funcional (§2) |
| E1-D | 5323, 5324 | grades de participante Master Set e Pokédex | GRANT authenticated | só 5302/5198/5204 (números reservados desde a V1-12; aplicadas **na E1-D**) |
| | 5388 v1.2 | histórico compartilhado + estado | GRANT authenticated | 5379, 5263, 5341 |

Tabelas cujo **esquema** muda: `collection_membership` (CHECK), `binder_activity_event`/`binder_activity_item` (colunas e gatilho), `storage.objects` (políticas). Tabelas cujos **dados** podem ser escritos pelas funções novas (quando aplicadas): bolsos, reservas, travas, páginas, referências de espécie e imagens de bolso do fichário; metadados e capa de `collection`; atribuições e representante Pokédex; histórico; objetos do bucket `collection-cover`. Nenhuma escreve em alocação, local, condição, inventário ou participações (exceto 5369/5370, do titular).

### 1.2 Harnesses, reversões e verificações

| Harness | Valida | Verificações | Válido no estado final? | Reversão do incremento | Estático |
|---|---|---|---|---|---|
| 5888 | E1-A | 54 | sim (fixa md5 de 5302 e da 5308 `get_my_collection_sharing`, que a cadeia não altera; correção de redação em 1.5) | `ROLLBACK_E1A.sql` | `static_check_e1a.py` 68/68 |
| 5861 v1.4 | regressão V1-12 adaptada à E1-A | 51 | sim | `ROLLBACK_v1_12.sql` exige `ROLLBACK_E1A` antes | idem (14.1–14.3) |
| 5862, 5863, 5864 | regressão V1-12 (paridade, imagens, logo) | — | **NÃO COMPROVADO** no estado final: válidos depois da E1-A pela análise da E1-A; sem reanálise para E1-B…E1-D | — | — |
| 5889 | E1-B1 | 56 | sim (aceita `add_item` da 5372 ou da 5379) | `ROLLBACK_E1B1.sql` | 61/61 |
| 5890 | E1-B2 (inclui Storage por SQL) | 45 | sim | `ROLLBACK_E1B2.sql` | 59/59 |
| 5891 | E1-B3 | 33 | só depois de 5378/5379 | `ROLLBACK_E1B3.sql` (5379 conservadora) | 42/42 |
| 5892 | E1-C1 | 27 | depois de 5378/5379/5381 | `ROLLBACK_E1C.sql` | 34/34 |
| 5893 | E1-C2 | 24 | depois de 5384 | `ROLLBACK_E1C2.sql` | 35/35 |
| 5894 v1.3 | E1-D | 29 | depois de 5366–5388 | `ROLLBACK_E1D.sql` | 52/52 |

Todos os harnesses: funções `pg_temp`, sem BEGIN/COMMIT próprios, sentinela que aborta, resíduo zero conferido; "executar SOMENTE sob protocolo controlado equivalente ao P1".

**Protocolo P1 (E1-A, `p1/`)**: gerador `build_p1_dryrun_e1a.py` (`--check` EM DIA), verificador 34/34, `MANIFEST.sha256` (10 arquivos), S0 e prova de aborto (`txid_status`) só leitura. **Cobre apenas 5366–5370 + 5888.**

### 1.3 Alterações de funções existentes (exigem regressão do titular)

5268 (`add_item`, duas vezes), 5309/5311/5312 (leituras V1-12), convite 5303→5369. Funções do titular instrumentadas e reusadas (5272–5296, 5243/5264, 5283/5284/5296/5360, 6122–6126) **não** são alteradas; os harnesses fixam os md5 delas (dever de espelho).

---

## 2. Compatibilidade entre migrations e harnesses

- **Estados intermediários existem em três funções:** `add_item` (5268 → 5372 → 5379), `binder_slot_editor_scope` (5371 → 5378) e o gatilho (5381 → 5384). Harness que fixa a versão final (5891–5894) falha num estado intermediário; 5889 aceita os dois `add_item`.
- **Dependência funcional não verificada por precheck:** 5385–5387 só funcionam para o EDITOR depois da 5384 (a 5381 recusa os quatro tipos novos). A ordem canônica (5384 antes) resolve; fora de ordem as operações falhariam por recusa em tempo de execução, sem efeito de segurança. Não é defeito bloqueante; o gerador do ensaio da cadeia (E1-E2) deve impor a ordem.
- **Regressão sobre o estado final é viável:** nenhum harness depende de versão intermediária que a cadeia substitua depois, salvo os já adaptados (5889 v1.2). Sequência proposta no estado final: 5888 → 5861 v1.4 → 5862 → 5863 → 5864 → 5889 → 5890 → 5891 → 5892 → 5893 → 5894.
- **5862–5864 sem reanálise para E1-B…E1-D:** antes de qualquer execução, revisão estática dirigida (E1-E2) — não é defeito bloqueante desta rodada.
- **Não há artefato de ensaio para E1-B…E1-D.** O P1 só gera 5366–5370 + 5888. Um ensaio da cadeia inteira (P1-CADEIA) exige gerador, verificador e manifesto novos — **bloqueio B1**, a preparar na E1-E2.
- **Nenhum harness foi alterado nesta rodada.** Nenhum defeito bloqueante de harness encontrado.

---

## 3. Matriz S1–S10 e provas complementares

Colunas comuns a todos: **identidades** sintéticas criadas dentro da transação (exceto onde indicado); **dados** sintéticos + catálogo real só como referência (FK), nunca dado de usuário real; **restauração** = aborto da transação (sentinela) + prova `txid_status = aborted` + S0/pós-estado; **STOP** = qualquer item da S0 divergente, `55P03`/`lock_timeout`, erro inesperado (X.1), `txid` ≠ `aborted`, resíduo ≠ 0.

| # | Requisito / capacidade | Risco detectado | Migrations | Harness (cobertura) | Sessões | Persistência | PASS objetivo | FAIL objetivo | Estado |
|---|---|---|---|---|---|---|---|---|---|
| S1 | EDITOR escreve em X em cada ✔ de C-234 | permissão faltante; histórico sem ator | 5371–5387 | 5889, 5890, 5891, 5892, 5893 (casos positivos) | 1 (papéis simulados) | transacional | GATE de cada harness PASS e eventos com ator EDITOR | qualquer FAIL | PREPARADO · ESTATICAMENTE VERIFICADO · **NÃO COMPROVADO** |
| S2 | recusa fora de X (outra coleção, outro titular, onde é VIEWER) | escrita cruzada; vazamento por erro | 5367, 5371, 5376, 5380, 5382 | 5888, 5889–5893 (negativos) | 1 | transacional | recusa com mensagem neutra, estado intacto | aceitação ou mensagem reveladora | idem |
| S3 | bolsos de terceiros em fichário de várias coleções | alteração de conteúdo alheio | 5371, 5378 | 5889, 5890, 5891 | 1 | transacional | recusa; md5 do conteúdo alheio igual | qualquer mudança alheia | idem |
| S4 | página/massa em fichário multi-coleção ou deslocando terceiros | deslocamento alheio | 5382, 5383, 5385–5387 | 5892, 5893 | 1 | transacional | `OPERATION_RESERVED_TO_OWNER`, nada anda | qualquer deslocamento | idem |
| S5 | exemplar inelegível (não alocado, outro local, outro titular, id forjado) | colocação indevida | 5371, 5374, 5380 | 5889, 5891 | 1 | transacional | `PHYSICAL_CARD_NOT_ELIGIBLE`; alocação/local/acervo iguais | aceitação | idem |
| S6 | ações do titular (alocar, local, condição, visibilidade, membros, papel, arquivo, exclusão, âncora, identidade, imagens) | escalada de privilégio | 5367–5370, 5376 | 5888, 5889, 5890, 5892 | 1 | transacional | recusa em todas | aceitação | idem |
| S7 | VIEWER, não membro, pendente/recusado, ex-membro, anon | escrita sem papel | todas | 5888–5894 (negativos), anon sem EXECUTE | 1 | transacional | recusa / sem EXECUTE | aceitação | idem |
| S8 seq. | troca EDITOR→VIEWER, saída, remoção (próxima chamada) | acesso residual | 5367, 5370, todas | 5888 (4.3, 5.11, 5.12), 5889–5894 (revogação) | 1 | transacional | recusa na chamada seguinte, leitura encerrada | acesso após revogação | idem |
| **S8 conc.** | revogação **durante** escrita | janela de corrida | 5370 + escritas | **nenhum** | **2 sessões reais** | **dados confirmados** | escrita em curso recusada ou serializada sem estado parcial | escrita gravada com papel revogado | **NÃO COMPROVADO — NO-GO (B3)** |
| S9 | leituras e histórico do EDITOR/VIEWER sem dados privados | vazamento de acervo, local, condição, ids, outras coleções | 5368, 5373, 5323, 5324, 5388 | 5894 (+ 5861 v1.4, 5862, 5888) | 1 | transacional | textos privados ausentes na saída inteira; grades iguais às do titular nas colunas comuns; sem inferência | qualquer dado privado | PREPARADO · ESTATICAMENTE VERIFICADO · **NÃO COMPROVADO** |
| **S10** | titular e EDITOR ao mesmo tempo no mesmo fichário | impasse, estado parcial, violação de C-237 | 5374–5387 + escritas do titular | **nenhum** | **2 sessões reais** | **dados confirmados** | serialização pela trava, sem impasse e sem estado parcial | impasse não resolvido, gravação parcial | **NÃO COMPROVADO — NO-GO (B3)** |

**Provas complementares**

| Prova | Harness / procedimento | Estado |
|---|---|---|
| Regressão do titular (funções alteradas e V1-12) | 5861 v1.4, 5862–5864 + md5 fixados nos harnesses | NÃO COMPROVADO |
| Resolução pelo PostgREST/JWT (limitação L1 de todos os harnesses) | **P4** (§13): P4-A pela tela atual (E1-A) e P4-B por chamadas diretas à API com JWT real de contas de teste (E1-B…E1-D); exige objetos **persistidos** | **NÃO COMPROVADO — NO-GO (B5)**; posição pela D-E1 (G4) |
| Storage pela API real | §5 | **NÃO COMPROVADO — NO-GO (B4)** |
| Idempotência e reexecução (tokens, prévias vencidas) | 5892, 5893 | NÃO COMPROVADO |
| Imutabilidade do histórico e atribuição por item | 5891, 5894 | NÃO COMPROVADO |
| Reversões (ROLLBACK_E1A … E1D) | ensaio de reversão ainda não especificado (E1-E2) | NÃO COMPROVADO |
| PR-04B (5364) | §4 | **NÃO COMPROVADO — NO-GO (B3)** |
| Desempenho | §7 | NÃO COMPROVADO |

**Segurança entre contas — o que uma única sessão com `SET LOCAL ROLE` + claims prova e o que não prova:** prova a lógica de autorização do banco para OWNER, EDITOR, VIEWER, não membro, pendente, removido, arquivada, fichário multi-coleção, conteúdo residual, exemplar inelegível, alteração patrimonial, histórico de outras coleções, Master Set, Pokédex e revogação **sequencial** (todos com identidades sintéticas dentro da transação). **Não prova:** o JWT real do PostgREST e do Storage (L1), concorrência entre sessões (S8 conc., S10, PR-04B), efeitos visíveis a outra sessão e o comportamento da API do Storage. Esses exigem **contas distintas reais** e dados confirmados.

---

## 4. Concorrência — S8 concorrente, S10 e PR-04B

| Caso | Sessão A | Sessão B | Ponto de corrida | Evidência necessária |
|---|---|---|---|---|
| C1 | titular move carta | EDITOR move carta no mesmo fichário | trava do fichário | uma serializa a outra; sem impasse; classificação C-237 preservada; histórico coerente |
| C2 | EDITOR escreve (transação aberta) | titular troca papel para VIEWER / remove | trava da coleção/participação | escrita recusada ou concluída antes da revogação, nunca depois |
| C3 | titular move exemplar de local / desaloca | EDITOR coloca o mesmo exemplar | trava de alocação | nenhuma colocação de exemplar inelegível |
| C4 | EDITOR de X | EDITOR de Y (convidada) no mesmo fichário | trava do fichário | sem cruzamento de bolsos |
| C5 | titular aplica organização automática | EDITOR aplica operação em massa | token/plano + trava | `PLAN_CHANGED` ou serialização; sem estado parcial |
| C6 | titular atribui Pokédex | EDITOR atribui/remove representante | trava de coleção e alocação | sem duas atribuições conflitantes |
| C7 | escritas simultâneas | leitura do histórico compartilhado | instantâneo STABLE | leitura coerente; nenhum item de outra coleção |
| PR-04B | duas sessões editando condição (5364) de contas distintas e da mesma conta | — | isolamento e rollback da 5364 (R1, R2, R3, R5, R6) | isolamento entre contas, sem perda de atualização |

**Condições mínimas** (VALIDATION-STRATEGY-E1A §4, mantidas): autorização própria; contas de teste **criadas pelo proprietário** (o agente não cria contas); dados **confirmados** visíveis às duas sessões, em coleções privadas dessas contas, com catálogo real e nenhum dado de usuário real; prefixo reservado e lista fechada de ids verificados antes/depois; compensação definida antes (exclusão das contas em cascata, inclusive histórico e Storage) e verificação de resíduo zero; duas sessões coordenadas por lock consultivo com ordem fixa, `lock_timeout`/`statement_timeout`; observabilidade (`pg_locks`, `pg_stat_activity`, resultado de cada passo registrado). Inspeção da ordem de travas **não** aprova concorrência.

**Estado:** sem caminho autorizado. **NO-GO — BLOQUEIO DE COMPROVAÇÃO DINÂMICA (B3)** até decisão expressa do proprietário sobre dados confirmados e contas de teste no LIVE. Não dispensável.

---

## 5. Storage (5377)

| # | Prova | SQL (5890, transacional) | Exige API real |
|---|---|---|---|
| ST1 | EDITOR envia capa para a pasta do titular da coleção autorizada | sim (linha em `storage.objects` sob claims) | **sim** — o arquivo, o dono gravado pela API e a política aplicada ao JWT |
| ST2 | EDITOR lê e apaga só os próprios envios | sim | sim (exclusão física do objeto) |
| ST3 | EDITOR não apaga arquivos do titular | sim | sim |
| ST4 | capa atual protegida | sim | sim |
| ST5 | revogação de papel encerra envio, leitura e exclusão | sim (sequencial) | sim |
| ST6 | formato e tamanho | **não** (regras do bucket são da API) | sim |
| ST7 | teto de 3 envios não usados | sim (trava transacional, sequencial) | sim |
| ST8 | envios simultâneos contra o teto | **não** | **sim, com concorrência real** |
| ST9 | divergência política SQL × comportamento da API (a 5377 depende de a API gravar o dono sob o JWT, "SEM PROVA" no cabeçalho) | não | sim |

**Estado:** ST1–ST5 e ST7 PREPARADO e ESTATICAMENTE VERIFICADO (5890), NÃO COMPROVADO. ST1–ST9 pela API: **NO-GO (B4)** — exigem contas reais no Auth, JWT real, objetos reais e compensação por exclusão; nenhum upload ou exclusão foi feito.

---

## 6. Prontidão do protocolo P1 e riscos operacionais do LIVE

### 6.1 P1 (E1-A) — reavaliação documental

| Item | Situação |
|---|---|
| R1 — indisponibilidade | `ACCESS EXCLUSIVE ... NOWAIT` em `collection_membership` da T6 ao aborto: todas as consultas que referenciam a tabela (leituras de participante, Biblioteca, convites) esperam. Teto por instrução 20 s (`statement_timeout`); **teto total só com PG ≥ 17** (`transaction_timeout`). Exige janela fora de uso. **Mantido** |
| R2 — efeitos externos | S0-5 recusa gatilhos com `pg_net`/`http`/`dblink`/`pg_notify`/webhook; persistem sequências, tuplas mortas, `pg_stat*`, log e WAL (sem efeito lógico). Rollback **não** desfaz essas marcas nem a espera imposta aos usuários. **Mantido** |
| R4 — provas ausentes | P1 prova só E1-A em ensaio; S8 conc., S10, PR-04B fora. **Mantido** |
| Verificação de aborto | `P1_POST_txid_readonly.sql` (`txid_status = aborted`) + S0/pós-estado; `committed` = incidente |
| Versão do PostgreSQL | **desconhecida** (não lida). < 14 → recusa; < 17 → sem teto total |
| Conclusão | **P1 especificado e estaticamente verificado; NÃO pronto para execução** (faltam S0 autorizada, versão, modo de conexão direta, janela e autorização por hash) |

**Só a S0 autorizada confirma:** `server_version_num`; `default_transaction_read_only`/`session_replication_role`; md5 vigentes de 5302–5312 e das funções do titular fixadas; CHECK e sobrecargas atuais; gatilhos nas tabelas tocadas (lista ampliada abaixo); publicações lógicas; `log_statement`; transações longas em curso; conexão direta; e, para a cadeia, se o executor pode criar políticas em `storage.objects` (dono `supabase_storage_admin`; a 5329 da V1-12 o fez).

### 6.2 Matriz de riscos operacionais de um ensaio da cadeia (P1-CADEIA ou por incremento)

Distinções obrigatórias: **espera para adquirir** (enquanto um `ACCESS EXCLUSIVE` espera na fila, **todas** as requisições novas à tabela esperam atrás dele — esperar já bloqueia); **retenção depois de adquirido** (vai até o fim da transação, isto é, até o aborto); **NOWAIT** só elimina a espera de aquisição e **não** limita a retenção nem a duração total; `statement_timeout` limita cada instrução; o teto **total** da transação só existe com `transaction_timeout` (PostgreSQL ≥ 17, versão do LIVE **desconhecida** — S0). Sem esse teto, só o próprio término do roteiro (sentinela) ou a interrupção manual pelo operador encerram a retenção.

| Risco | Origem | Espera para adquirir | Retenção após adquirir | Efeito externo | O que o rollback não desfaz | Janela | STOP | Mitigação (E1-E2) |
|---|---|---|---|---|---|---|---|---|
| O1 | 5366 `ALTER TABLE collection_membership` | `LOCK … NOWAIT` antecipado (P1 T6): zero ou `55P03` | da T6 ao aborto | nenhum direto | espera imposta a quem usou compartilhamento | sem uso de convites/compartilhadas | `55P03`, timeout | já especificado na P1 |
| **O2** | 5377 `CREATE POLICY` em `storage.objects` | sem LOCK explícito, a instrução **espera na fila** até `lock_timeout` e, enquanto espera, bloqueia o Storage inteiro | do `CREATE POLICY` ao aborto | requisições de imagens e envios de **todos** os usuários (inclusive vitrine pública) aguardam ou falham pelo timeout da API | falhas e esperas vistas pelos usuários; logs da API | sem tráfego relevante de Storage | `55P03`, timeout, privilégio insuficiente para LOCK/POLICY | `LOCK TABLE storage.objects IN ACCESS EXCLUSIVE MODE NOWAIT` imediatamente antes da 5377 (privilégio a confirmar na S0); ensaio próprio e curto (§14); confirmar o nível do lock na versão real |
| O3 | 5379 `ALTER TABLE` em `binder_activity_event`/`binder_activity_item` | idem (fila) se sem NOWAIT | da 5379 ao aborto | toda operação do fichário que grava histórico espera | idem | sem uso de fichários | idem | NOWAIT antecipado nas duas tabelas |
| O4 | 5381/5384 `CREATE TRIGGER` | SHARE ROW EXCLUSIVE; espera em fila | até o aborto | escritas no histórico esperam | idem | idem | idem | mesma aquisição antecipada da O3 |
| O5 | duração total | — | soma das migrations + harnesses | todos os acima, somados | — | maior que a da P1 | teto excedido | dividir por incremento; medir na E1-E2 sem estimativa inventada |
| O6 | fixtures em `auth.users`, catálogo, `storage.objects` | ROW EXCLUSIVE; KEY SHARE em linhas reais referenciadas | até o aborto | gatilhos externos (excluídos pela S0) | sequências, tuplas mortas, `pg_stat*`, log, WAL | — | gatilho externo na S0 | S0 ampliada |
| O7 | canal | — | — | pooler/SQL Editor/`apply_migration` não garantem o aborto | — | — | canal fora do aprovado (recusa) | só psql, conexão direta, `ON_ERROR_STOP` |

**S0 ampliada (lista de tabelas para gatilhos externos):** além das da P1 — `storage.objects` (e tabelas auxiliares do Storage que tiverem gatilho), `binder_activity_event`, `binder_activity_item`, `collection_layout_*` (slot, assignment, expected_content, species_reference, image, region, guest, catalog_marker, catalog_incorporation), `card_primary_species`, `collection_pokedex_position_assignment`, `collection_pokedex_position_primary_representative`, `collection_allocation`, `inventory`, `user_profile`.

---

## 7. Desempenho — cenários de medição M1–M7 (nenhum resultado existe; renomeados de P1h…P7 para não colidir com as fases P1–P4)

| Cenário | Função | Volume de referência | Métrica | Critério de aceitação proposto |
|---|---|---|---|---|
| M1 | histórico com eventos esparsos de X num fichário de várias coleções | ≥ 5.000 eventos do fichário, ≤ 1% de X | tempo e buffers da página de 20/50 (`EXPLAIN (ANALYZE, BUFFERS)`) | ≤ 300 ms por página (mesmo limite da 5198); acima → índice candidato `(owner_user_id, layout_key, collection_id, occurred_at desc, id desc)` só com medição |
| M2 | evento com centenas de itens e poucos de X | E21 com 500 itens | tempo por página | ≤ 300 ms |
| M3 | `history_may_be_partial` sem evento não atribuído | fichário com milhares de eventos | tempo do EXISTS | ≤ 100 ms |
| M4 | 5323 no maior Set | 336 posições / 2.492 exemplares (referência LIVE da 5198) | tempo da grade | ≤ 300 ms |
| M5 | 5324 Pokédex Nacional | 1.025 posições, 3 páginas de 500 | tempo por página | ≤ 300 ms |
| M6 | operações em massa (organização automática, espaços, novidades) | fichário de 50 páginas | tempo e duração das travas | sem lock retido além da chamada; tempo registrado |
| M7 | concorrência | casos C1–C7 | espera em `pg_locks`, impasses | sem impasse não resolvido |

Medição só sob protocolo (dados sintéticos dentro de transação abortada, ou dados confirmados de contas de teste); **medir sobre dados reais de usuários como fixture é vedado**. Nenhum índice especulativo.

---

## 8. Rollback e preservação de dados

| Situação | Mecanismo | Preserva | Não desfaz |
|---|---|---|---|
| Ensaio (P1/P1-CADEIA) | aborto da transação por sentinela; `txid_status` | tudo (nada confirmado) | marcas de §6.1 R2; espera imposta aos usuários |
| Implantação definitiva, antes de qualquer uso | `ROLLBACK_E1D` → `E1C2` → `E1C` → `E1B3` → `E1B2` → `E1B1` → `E1A` (ordem inversa, um bloco por transação) | dados (só DROP de funções/políticas; R5379 reaplica 5372 e **preserva** colunas) | — |
| Implantação definitiva, depois de uso | mesmos scripts, **conservadores**: bolsos, reservas, metadados, capas e eventos gravados por EDITOR permanecem (C-155, C-179); colunas da 5379 preservadas; R5379-D só antes de uso | histórico por item | objetos enviados ao Storage pelo EDITOR (compensação manual pelo titular, D11); efeitos vistos por usuários |
| Dados parcialmente aplicados | cada migration é uma transação com pre/postcheck; falha → nada daquela migration | estado anterior | migrations anteriores já confirmadas (seguir a ordem inversa) |
| Mudança de privilégios/políticas | reversão reaplica REVOKE/GRANT e DROP POLICY | — | requisições já atendidas |

**Interrupção imediata** em: precheck divergente, `55P03`, timeout, erro inesperado, `txid` ≠ `aborted`, resíduo ≠ 0, qualquer linha fora da lista fechada alterada, gatilho externo, executor fora do canal aprovado.

---

## 9. Critérios de decisão

| Decisão | Critério objetivo (todos obrigatórios) |
|---|---|
| **Autorizar S0** | autorização específica (arquivo por hash, executor, canal, janela); S0 só leitura revisada; conexão direta confirmada |
| **Autorizar P1** | S0 aprovada (versão ≥ 14, sem gatilho externo, md5 iguais, CHECK/sobrecargas esperadas, sem transação longa); arquivo gerado pelo script com hash do manifesto; verificador PASS; janela fora de uso; autorização por hash |
| **Autorizar P1-CADEIA / ensaios por incremento** | P1 PASS; gerador e verificador novos (E1-E2) PASS; plano de locks O1–O5 aprovado (incluindo a decisão sobre 5377); S0 ampliada aprovada |
| **Autorizar ensaios concorrentes** | decisão expressa sobre dados confirmados no LIVE; contas de teste criadas pelo proprietário; compensação e verificação de resíduo definidas antes; roteiro de duas sessões aprovado |
| **PASS de um cenário** | execução real; GATE do harness = esperado; `txid_status = aborted` (ensaios); pós-estado = S0; resíduo zero |
| **FAIL de um cenário** | qualquer verificação FAIL ou X.1; correção exige nova rodada local, nova verificação estática e nova autorização — nunca "repetir até passar" |
| **STOP** | §8 "Interrupção imediata" |
| **Liberação para a etapa 7** | **G5** de `BARRIER-FEASIBILITY-D-E1.md` §9: S1–S9 sequenciais PASS em ensaio; regressão do titular e das mudanças compartilhadas PASS; barreira persistida fechada e provada por negação com JWT real (G3); com contas de teste no modo restrito, S8 concorrente, S10, PR-04B, P4-A/P4-B, ST1–ST9 e M1–M7 com evidências (G4); parecer de segurança favorável e autorização do proprietário. Nenhuma prova dispensada; a etapa 7 **não** está liberada |
| **Manter NO-GO** | enquanto qualquer item acima estiver NÃO COMPROVADO; impossibilidade operacional **não** vira aceitação de risco (C-244) |

---

## 10. Sequência proposta dos ensaios (cada passo com autorização própria)

1. **E1-E2 (local, estático):** revisão de 5862–5864 para o estado final; gerador/verificador P1-CADEIA (ou por incremento) com plano de locks; decisão sobre isolar a 5377; S0 ampliada; ensaio de reversão especificado.
2. **S0** (só leitura, autorizada).
3. **P1** (E1-A em ensaio abortado).
4. **Ensaios por incremento** E1-B1 → … → E1-D (cada um reaplica a cadeia anterior na mesma transação e roda o harness do incremento), ou P1-CADEIA único, conforme decisão de locks.
5. **Regressão no estado final** (sequência de §2) em ensaio abortado.
6. **Persistência restrita (D-E1, dentro da etapa 6, cada passo com autorização própria):** G1 → G2 (ensaio com a porta) → G3 (porta fechada persistida antes da cadeia; prova de negação por JWT real) → G4 (contas de teste criadas pelo proprietário, modo restrito: S8 concorrente, S10, PR-04B, P4-A/P4-B, ST1–ST9, M1–M7) → G5. Detalhe em `BARRIER-FEASIBILITY-D-E1.md`.
7. **Parecer de segurança** → só então a etapa 7 (implantação controlada) pode ser considerada.

---

## 11. Bloqueios de comprovação identificados

| # | Bloqueio | Efeito | Saída |
|---|---|---|---|
| B1 | não existe artefato de ensaio para E1-B…E1-D | S1–S9 (exceto partes da E1-A) sem caminho de execução | preparar na E1-E2 |
| B2 | lock ACCESS EXCLUSIVE em `storage.objects` (5377) e nas tabelas do histórico (5379) somado ao de `collection_membership` | indisponibilidade ampla durante ensaio da cadeia | plano de locks e isolamento da 5377 (E1-E2) |
| B3 | S8 conc., S10 e PR-04B exigem dados confirmados e duas sessões | **NO-GO — BLOQUEIO DE COMPROVAÇÃO DINÂMICA** | decisão expressa do proprietário + contas de teste criadas por ele |
| B4 | Storage pela API exige contas reais, JWT e objetos reais | **NO-GO — BLOQUEIO DE COMPROVAÇÃO DINÂMICA** | idem |
| B5 | L1: `SET LOCAL ROLE` não prova o JWT do PostgREST | **NO-GO** para P4 (A e B) sem contas de teste; P4-B também exige funções persistidas (D-E1) | idem |
| B6 | versão do PostgreSQL desconhecida | teto total de transação indisponível se < 17 | S0 |
| B7 | desempenho só mensurável com as funções aplicadas (ou em ensaio) e volume | sem números | ensaios com volume sintético |

| B8 | **barreira de acesso no servidor ainda não comprovada** (G1 preparado em `g1/`, não executado) (D-E1 aprovada; mecanismo candidato só com viabilidade estática, G0) | sem barreira implementada, revisada (G1), provada em ensaio (G2) e persistida fechada com prova de negação por JWT real (G3), nenhuma persistência restrita nem prova persistente pode ocorrer | gates G1–G3 de `BARRIER-FEASIBILITY-D-E1.md`, cada um com autorização própria |

**Nenhum** desses bloqueios é dispensado nem convertido em aceitação de risco. B1–B7 mantêm a classificação anterior; B8 (1.1: decisão de produto) foi **substituído** em 1.2 pela pendência de comprovação técnica da barreira, depois da aprovação da D-E1.

---

## 12. Documentos

Criado: este README (1.0); revisado em 1.1 (§13–§15, §6.2, §7, §9–§11) e 1.2 (D-E1 aprovada: §9, §10, §11 B8, §13.3, §15). Criado em 1.2: `BARRIER-FEASIBILITY-D-E1.md`. Atualizados: `docs/05d-colecoes-e-usuarios.md` (estado da E1-E), `docs/ROADMAP.md` (linha V1-13), `docs/INDEX.md` (linha nova), `docs/log.md`. Nenhuma migration, harness, função ou contrato (C-234–C-244, D9–D14) alterado.

## 13. P4 × etapas 7–10 (`SECURITY EVIDENCE PLAN RECONCILIATION-02`)

### 13.1 Significado normativo de P4

P4 nasceu em `VALIDATION-STRATEGY-E1A.md` §3 (E1-A): **"Homologação pela tela atual: convite VIEWER e coleção compartilhada aberta como membro. Cobre a limitação L1, a resolução pelo PostgREST"**, depois de P3. É uma prova **técnica** (autenticação real, JWT, PostgREST) feita com a interface **já publicada** da V1-12 — não é homologação de interface nova. A C-244 não menciona P4; o roadmap de dez etapas também não.

**Incompatibilidade identificada:** a tela atual não tem nenhum controle do EDITOR. Para E1-B…E1-D, a P4 como definida não alcança as RPCs novas; usar "P4" para exigir a interface do EDITOR misturaria a prova técnica com a homologação da E4 (que depende de E2/E3).

### 13.2 Refinamento documental adotado (só neste plano; a estratégia da E1-A e os contratos não mudam)

| Nome | O quê | Como | Pertence a | Pré-condição de |
|---|---|---|---|---|
| **P4-A** | P4 original da E1-A | tela atual da V1-12 com contas de teste (convite VIEWER/EDITOR, abrir coleção compartilhada) | etapa 6/7 (técnica) | aplicação da E1-A |
| **P4-B** | prova técnica real das RPCs e políticas novas | chamadas diretas à API (PostgREST e Storage) com JWT real de contas de teste — sem interface nova | etapa 6/7 (técnica) | publicação (posição exata: D-E1) |
| Homologação de interface | fluxos funcionais e visuais do EDITOR e VIEWER nas quatro modalidades | interface construída na E2/E3 | **E4** (etapa 10) | publicação da V1-13 |

Nenhum requisito de segurança da etapa 7 foi reduzido: P4-A e P4-B seguem obrigatórias; a interface nova **não** é pré-condição para implantar a fundação E1.

### 13.3 D-E1 — APROVADA (opção A)

**DECISÃO APROVADA (proprietário, 2026-11-15, definitiva):** persistência técnica **restrita** das capacidades E1, protegida por **barreira de acesso no servidor**, para viabilizar provas dinâmicas com identidades e sessões reais, **antes** da habilitação pública.
**MECANISMO NÃO APROVADO:** a barreira candidata (porta central no banco + desligamento por privilégio) tem só viabilidade estática (G0).
**EXECUÇÃO NÃO AUTORIZADA:** nenhuma operação no banco.

Fato que motivou a decisão (mantido): um ensaio em transação abortada não é visível a outra sessão, ao PostgREST nem à API do Storage; S8 concorrente, S10, ST1–ST9 pela API e P4-B só existem sobre objetos persistidos; aplicar sem barreira já exporia as RPCs a qualquer conta pela API.

Forma aprovada: a persistência restrita acontece **dentro da etapa 6** (gates G3/G4), sob autorização individualizada; a **etapa 7 continua sendo o marco posterior ao parecer de segurança (G5)** e não foi iniciada. A sequência do `05d` ("Dependências e ordem") recebeu refinamento explícito marcado "D-E1"; C-234–C-244 e D9–D14 inalterados (sem conflito material: a C-244 bloqueia a publicação, exige protocolo, autorização, dados sintéticos e efeitos compensáveis — tudo preservado).

## 14. Independência da 5377 e dependências da 5890

### 14.1 Dependências reais

- **5377:** precheck exige 5366 (E1-A), bucket e políticas do dono da 5176 e a leitura da capa atual da 5329. Os dois ajudantes (`collection_cover_editor_folder_ok`, `collection_cover_editor_can_upload`) leem `collection`, `collection_reference` e `collection_membership` (papel `EDITOR`, que só existe depois da 5366). Não chamam funções da E1-B1/E1-B2.
- **Nenhuma migration posterior (5378–5388, 5323, 5324) referencia a 5377**, e os harnesses 5891–5894 não tocam `storage.objects`. Isso permite **omitir** a 5377 dos ensaios desses incrementos; **não** basta, sozinho, para afirmar que ela pode ser testada isoladamente.
- **5890:** pressupõe E1-A, E1-B1 e E1-B2 inteiras (5366–5377). As seções 1–3 usam reservas e fixação (5371, 5372, 5375); 4–5 metadados e capa (5376); 6 **Storage e imagem da placa** combina as políticas (5377) com `editor_set_collection_cover_logo` (5376); 7–11 troca de papel, histórico, titular, patrimônio e arquivada. A fixture cria o EDITOR pelo convite com papel (5369) e resposta. A verificação 0.x confere a estrutura de todas as funções da E1-B1/E1-B2.

### 14.2 Quatro provas distintas

| Prova | O que prova | Migrations e pré-condições mínimas | Transacional? | Artefato |
|---|---|---|---|---|
| **ST-AUT** autorização de Storage por SQL | políticas de inserção, leitura e exclusão do EDITOR, pasta do titular, teto de 3 (sequencial), revogação | 5366, 5377 e uma participação EDITOR (pela 5369, ou seja, 5366–5370) | sim (ensaio abortado) | **não existe** harness reduzido; a 5890 inteira exige 5366–5377. Harness reduzido = artefato novo (E1-E2) |
| **ST-INT** integração com as funções de capa | troca da imagem da placa pelo EDITOR, recusa de caminho inválido ou arquivo inexistente, proteção da capa atual | 5366–5370, 5376, 5377 (+ 5329, 5176) | sim | seção 6 da 5890 (dentro da 5890 inteira) |
| **ST-API** API real do Storage | dono gravado pela API sob o JWT, regras de formato/tamanho do bucket, exclusão física, divergência política × API (ST1–ST7, ST9) | 5366–5377 **persistidas**; contas de teste reais; objetos reais e compensação | **não** | inexistente; depende de D-E1 e B4 |
| **ST-CONC** envios simultâneos | teto de 3 sob corrida (ST8) | idem + duas sessões reais simultâneas | **não** | inexistente; depende de D-E1, B3 e B4 |

### 14.3 Efeitos da separação

- O ensaio que contém a 5377 retém **ao mesmo tempo** `collection_membership` (O1, desde a 5366) e `storage.objects` (O2) até o aborto. Rodando a 5890 inteira, a retenção do O2 cobre a 5890 toda; com um harness reduzido (ST-AUT), cobriria só as verificações de Storage — por isso o harness reduzido é a mitigação principal do O2, e a 5377 deve vir **por último** na cadeia do ensaio, com `LOCK … NOWAIT` imediatamente antes.
- Omitir a 5377 dos demais ensaios preserva a validade deles (não dependem dela). A **regressão no estado final** sem a 5377 não é, porém, o estado final: a combinação 5377 × E1-B3…E1-D só é provada por argumento estático (nenhuma referência cruzada), a registrar como tal — ou executada uma vez com a 5377 por último e retenção mínima. Escolha na E1-E2.
- **Interrupção e restauração:** `55P03` no LOCK de `storage.objects` → STOP sem efeito; qualquer erro → aborto; verificação `txid_status = aborted`, pós-estado igual à S0 e contagem de `storage.objects` igual à inicial (a 5890 já a inclui no resíduo).

## 15. Confirmação dos bloqueios

D-E1 APROVADA; barreira não comprovada (B8). S1–S10 sem prova dinâmica; S8, S10 e PR-04B obrigatórios; Storage pela API real NO-GO; autenticação/JWT real (P4-A/P4-B) NO-GO; desempenho não medido; nenhuma migration aplicada. B1–B7 sem reclassificação; B8 acrescentado. Próxima atividade interna da etapa 6 continua sendo a **E1-E2** (gerador e verificador dos ensaios da cadeia, revisão de 5862–5864, plano de travas, S0 ampliada, reconciliação dos rollbacks, e, se aprovado, harness reduzido ST-AUT) — não iniciada.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Plano de evidências (2026-11-15, `V1-13 / E1-E1 \| SECURITY EVIDENCE RECONCILIATION AND EXECUTION READINESS-01`).** Inventário, matriz S1–S10 e complementares, concorrência, Storage, P1, riscos operacionais (O2: `storage.objects`), rollback, critérios e sequência; bloqueios B1–B7 (B3–B5 NO-GO). Nada executado. |
| 1.1 | **Reconciliação (2026-11-15, `V1-13 / E1-E1 \| SECURITY EVIDENCE PLAN RECONCILIATION-02`).** P4 separada em P4-A (tela atual, E1-A) e P4-B (API com JWT real) e distinta da homologação de interface da E4; D-E1 (provas que exigem objetos persistidos × ordem prova → aplicação) registrada como decisão de produto, B8; independência da 5377 e dependências da 5890 analisadas (ST-AUT, ST-INT, ST-API, ST-CONC); matriz de riscos com espera × retenção × NOWAIT; cenários de desempenho renomeados M1–M7. B1–B7 inalterados. Nada executado. |
| 1.2 | **D-E1 aprovada (2026-11-15, `D-E1 FORMALIZATION AND SERVER-SIDE BARRIER FEASIBILITY-03`).** Opção A formalizada (estratégia aprovada; mecanismo não aprovado; execução não autorizada); B8 substituído pela pendência de comprovação técnica da barreira; liberação para a etapa 7 = G5; sequência com G1–G5 dentro da etapa 6; viabilidade estática em `BARRIER-FEASIBILITY-D-E1.md`. B1–B7, P4-A/P4-B e M1–M7 mantidos. Nada executado. |
| 1.3 | **G1 preparado (2026-11-15, `G1 SERVER-SIDE BARRIER PREPARATION-01`).** B8 aponta para `g1/` (porta 5389, versões protegidas, STOP, harness 5895); classificação inalterada (G2–G3 pendentes). Nada executado. |
| 1.4 | **Encerramento local do G1 (2026-11-15, `G1 BARRIER LOCAL CLOSEOUT AND COMMIT-02`).** Estado dos gates: D-E1 aprovada; Alternativa C selecionada (não homologada); G0 documentado; G1 preparado, não executado; G2–G5 não iniciados; etapa 6 não concluída. Nada executado. |
| 1.5 | **E1-E2 preparada (2026-11-15, `E1-E2 | PROTECTED CHAIN AND G2 TEST READINESS-01`).** Pasta `e1e2/` (gerador e ensaios G2, S0 ampliada, revisão 5862–5864, plano de travas, verificação estática); bloqueio E2-D1 (5380/5891 fixam o md5 da 6122, vigente é a 6123); §1.2 corrigida (5888 fixa a 5308). Nada executado; G2 não iniciado. |
| 1.6 | **Correção E2-D1 (2026-11-15, `CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02`).** Defeito de compatibilidade detectado e corrigido localmente; 5863 v1.2-E1E autorizada e reforçada; G1 e G2 regerados. Nada executado; G2 não iniciado. |
