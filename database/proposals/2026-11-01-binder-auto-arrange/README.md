# Fichário — Organização automática (P2) — proposta SQL

| Campo | Valor |
|--------|-------|
| **Rodada** | `Binder · P2 AUTO-ARRANGE SQL FOUNDATION-06` (2026-11-01) |
| **Status** | **EXECUTADO NO LIVE / CANÔNICO / HOMOLOGADO** (`P2 SQL FOUNDATION CLOSEOUT-16`, 2026-11-01). 5341–5344 aplicadas (GATE 02/RESUME-13) e promovidas para `database/schema/` (só o bloco Status difere); harness 5872 v1.5 54/54 PASS (GATE 03 RERUN-15; v1.4 48/54 preservado como histórico); postcheck e medição ME3 PASS (GATE 04). Os arquivos desta pasta são o texto executado e auditado (não alterados); as seções abaixo são o histórico das rodadas. Concorrência real entre sessões (K-M1..K-M3) e `55P03` não provados. Nenhuma organização real executada. |
| **Decisões** | C-220–C-226 (`docs/domain-modeling/collections/concept-decisions.md`) |
| **Contrato** | `docs/domain-modeling/collections/binder-auto-arrange-contract.md` |
| **Base LIVE** | `P2 LIVE ELIGIBILITY DIAGNOSIS-05` (read-only): 148/148 candidatos únicos no recorte diagnosticado |

## Arquivos

| Ordem | Arquivo | Conteúdo |
|---|---|---|
| 1 | `5341_extend_binder_activity_auto_arrange_event.sql` | CHECK `chk_bae_event_type` + `CARDS_AUTO_ARRANGED`; `binder_activity_category` mapeia para `CARDS` |
| 2 | `5342_create_binder_auto_arrange_plan.sql` | `binder_auto_arrange_plan(uuid,uuid,uuid)` — SQL, STABLE, INVOKER, interna (sem EXECUTE para PUBLIC/anon/authenticated/service_role) |
| 3 | `5343_create_preview_my_binder_auto_arrange.sql` | `preview_my_binder_auto_arrange(uuid) → jsonb` — DEFINER, STABLE, `authenticated` |
| 4 | `5344_create_apply_my_binder_auto_arrange.sql` | `apply_my_binder_auto_arrange(uuid,text) → jsonb` — DEFINER, VOLATILE, `lock_timeout 5s`, `authenticated` |
| 5 | `5872_validate_binder_auto_arrange.sql` | Harness transacional (TR000), 54 ids, GATE por identificadores — **v1.5** (executado no GATE 03 RERUN-15; não promovido, por convenção) |
| — | `LIVE_00_precheck_readonly.sql` | Preflight R1 (PRE-1…PRE-9) e impressão digital (FP) dos dados reais |
| — | `LIVE_90_postcheck_readonly.sql` | Postcheck R1 independente do harness (POST-1…POST-7, SRC) |
| — | `LIVE_70_measure_me3_plan_readonly.sql` | Medição R1 do plano no fichário ME3 (corpo da 5342 como SELECT puro) |

Cada migration tem precheck fail-loud (dependências presentes, objeto ainda ausente) e `begin … commit`. Executar uma por vez, na ordem, confirmando cada uma (STD-001 §10). O harness só depois das quatro.

## Contrato resumido

- **Elegível:** Set/Master Set ativa do titular, no fichário próprio. Pokédex/Livre → `AUTO_ARRANGE_UNSUPPORTED_COLLECTION`; convidada → `AUTO_ARRANGE_NOT_BINDER_OWNER`.
- **Candidato:** exemplar alocado à proprietária, no local do fichário, inventário do titular, fora de bolsos. **Destino:** bolso reservado à proprietária, vazio, não travado, sem imagem, fora de mesclagem, compatível com carta / carta + acabamento / variante exata.
- **1:1 estrito** sobre todos os pares; variante inativa entra na contagem, nunca no INSERT.
- **Token** `aa1:` + SHA-256 dos pares a inserir; aplicação recalcula 2× sob travas; divergência → `40001 AUTO_ARRANGE_PLAN_CHANGED`; token já aplicado → `ALREADY_APPLIED`.
- **Limite** 500 por confirmação → acima, `54000 AUTO_ARRANGE_LIMIT_EXCEEDED`, nada escrito.
- **Escrita única:** INSERT em `collection_layout_slot_assignment` + 1 evento `CARDS_AUTO_ARRANGED` com 1 item `PLACED` por carta.

## Travas e concorrência

Coleção proprietária `FOR UPDATE` (5122) → bolsos do plano `FOR UPDATE` por id → exemplares do plano `FOR UPDATE` por id → evento → INSERTs. Mesma família de `place_my_physical_card_in_slot` (5272); escritores de local/alocação (5249) travam exemplares por id, sem ciclo. `uq_collection_layout_slot_assignment_slot` é `DEFERRABLE INITIALLY DEFERRED` (5115): a colisão de bolso é impedida pelas travas e pelo 2º recálculo, não pela captura de `unique_violation` (que só cobre a UNIQUE imediata de exemplar).

### Concorrência entre sessões

Classificação das provas K-M1..K-M3 (equivalente serial no harness, garantias estruturais, limite do protocolo) no plano executivo vigente, §1.

## Rollback (somente antes de qualquer uso)

```sql
begin;
drop function if exists public.apply_my_binder_auto_arrange(uuid, text);
drop function if exists public.preview_my_binder_auto_arrange(uuid);
drop function if exists public.binder_auto_arrange_plan(uuid, uuid, uuid);
-- 5341: só se não existir evento CARDS_AUTO_ARRANGED; recriar o CHECK e a função da 5269 sem o tipo.
commit;
notify pgrst, 'reload schema';
```

## Dependências externas

- Frontend: `web/lib/colecoes/binder-activity.ts` deve conhecer `CARDS_AUTO_ARRANGED` antes da publicação do botão (o evento cai no ramo padrão até lá).
- Desempenho: P.6 mede prévia com 501 candidatos × 504 bolsos e aplicação de 500 com histórico; limites do teste (3 s / 15 s) são de sanidade, não SLA.

## Revisão estática local (2026-11-01)

Delimitadores `$…$` balanceados; `begin`/`commit` presentes; `search_path = ''` em todas as funções; grants mínimos; nenhum `DELETE`/`UPDATE`/`ON CONFLICT` em 5344; nenhuma escrita em reservas, alocação, exemplar ou local; plano calculado 2× na aplicação; GATE do harness por lista de ids. Resultado detalhado no relatório da rodada.

## Auditoria direcionada — `TARGETED SQL SAFETY AUDIT-07` (2026-11-01)

Correções aplicadas (locais, nada executado):

1. **5342 v1.1 — idempotência.** O token passa a incluir a época (último evento `CARDS_AUTO_ARRANGED` do fichário/titular). Sem isso, um token antigo repetido depois de o mesmo conjunto de pares reaparecer (cartas removidas) seria reaplicado como se fosse nova intenção. Regra resultante: token = plano → aplica; token ≠ plano e presente em evento do fichário → `ALREADY_APPLIED`; senão → `PLAN_CHANGED`.
2. **5342 v1.1 — desempenho.** Os motivos usavam subconsultas escalares correlatas sobre a CTE de pares (O(C·P) sem índice). Substituídas por graus agregados (`GROUP BY`) e junções hash: O(S + C + P).
3. **5872 v1.1 — fixtures.** `ck_card_variant_default_active` impede desativar a variante padrão: K9 e C.4 da v1.0 falhariam. K9 passa a usar uma variante ALT não padrão; C.4 desativa a variante ALT do par K10. Reserva da convidada pela RPC oficial (5276 grava `collection_id = convidada`). Bolsos da proprietária aceitam `collection_id` nulo (montagem 5295) ou igual à proprietária (5276). Novo **I.4** cobre o reaparecimento de pares (52 ids).
4. **5344 v1.1** — só cabeçalho (protocolo de isolamento e regra de identidade). Corpo inalterado.

### Matriz de escritores concorrentes (efetivo no schema canônico)

| Escritor | Trava que serializa com 5344 | Efeito sobre o plano |
|---|---|---|
| `place_my_physical_card_in_slot` 5272, `move_slot_assignment` 5273, `remove_slot_assignment` 5274 | coleção proprietária (5122) → bolso → exemplar | serializado |
| `set_slot_expected_content` 5276, `clear_slot_expected_content` 5277, `set_slot_lock` 5278, páginas 5280/5282/5286, `merge/unmerge` 5134/5135 | coleção proprietária (5122) | serializado |
| mesclagem/imagem 5240/5233, lacunas 5243, novidades do catálogo 5296 | coleção via `binder_layout_lock_for_collection` (5122) | serializado |
| `attach`/`detach` 5290/5291, `dismantle` 5294, `transfer` 5292, `create_my_collection_binder` 5295 | coleção proprietária FOR UPDATE | serializado |
| `allocate`/`deallocate` 5046/5047 | coleção-alvo FOR UPDATE (entrar ou sair da proprietária passa por ela) | serializado |
| `set_physical_cards_storage` 5287, `organize_my_collection_storage` 5288 (NOWAIT), `remove_my_physical_card` 5289 | exemplar FOR UPDATE (planejados travados no passo 4) | serializado para exemplares do plano; só libera bolsos/acrescenta candidatos para os demais |
| cadastro em lote 5150/5152/5153 | nenhuma em comum | só acrescenta candidatos (equivalente serial) |
| desativação de variante (catálogo) | nenhuma em comum | equivalente serial; não invalida posição |

Gatilhos de `collection_layout_slot_assignment` (todos BEFORE, sem efeito colateral): integridade 5248 (dono e local do exemplar; grava a alocação vigente), trava 5118, fora de mesclagem 5238, sem imagem 5232. Nenhum escreve em outra tabela.

Plano de prova, medições e critérios de entrada desta auditoria: substituídos pelo plano executivo vigente (fim deste arquivo).

## Fechamento do token e da concorrência — `TOKEN & CONCURRENCY CLOSEOUT-08` (2026-11-01)

**Lacuna:** na v1.1 a época era só o id máximo de `CARDS_AUTO_ARRANGED`; a limpeza do histórico (5270) apaga esses eventos e o id regredia, então um token antigo podia voltar a coincidir com o plano e ser aplicado como nova autorização.

**Mecanismo monotônico existente:** a 5270 é a única porta de DELETE de eventos (gatilho 5267; a outra é a exclusão da conta, que elimina o titular) e, na mesma transação, regrava `binder_activity_coverage (owner_user_id, layout_key)` com `reason = HISTORY_PURGED` e `updated_at = now()`. A **5342 v1.2** inclui esse marco (motivo + `updated_at` em µs UTC, representação independente de DateStyle/TimeZone) na época. Nenhuma tabela, coluna ou função nova.

**Efeito:** depois de uma limpeza, todo token anterior diverge e, sem evento que prove a aplicação, recebe `PLAN_CHANGED`; nova intenção exige nova prévia. Coberto por **I.5** no harness (53 ids). 5344 e 5343: corpo inalterado.

| Cenário | Resultado |
|---|---|
| Primeira confirmação | token = plano → `APPLIED` |
| Repetição imediata / resposta perdida | época mudou → token ≠ plano; token no evento → `ALREADY_APPLIED` |
| Duas confirmações simultâneas | 2ª espera a trava da coleção; vê o commit → `ALREADY_APPLIED` |
| Plano alterado | token ≠ plano, ausente dos eventos → `PLAN_CHANGED` |
| Mesmos pares reaparecem | época (id) mudou → token antigo `ALREADY_APPLIED`; nova prévia aplica |
| Limpeza do histórico | marco mudou → qualquer token anterior `PLAN_CHANGED` |
| Token antigo após a limpeza, condições idênticas | `PLAN_CHANGED` (nunca reautoriza) |
| Limpeza concorrente com aplicação | entre os recálculos → `PLAN_CHANGED`; depois → evento sobrevive (não visto pelo DELETE) |

## Prontidão para execução controlada — `CONTROLLED EXECUTION READINESS-09` (2026-11-01)

### Época do token — evidência final (sem mudança de comportamento)

- `binder_activity_coverage` PK `(owner_user_id, layout_key)`; no LIVE o **único** escritor é `purge_my_binder_activity` (varredura de `pg_proc`, 2026-11-01), que grava `updated_at = now()` no mesmo comando/transação em que apaga os eventos; EXECUTE só para o dono do banco (nem `authenticated`, nem `anon`).
- Eventos só saem pela 5270 (porta do gatilho 5267) ou pela exclusão da conta (titular deixa de existir). Ids de evento são identidade, nunca reutilizados.
- Logo, para um token emitido com época `(m, c)` voltar a valer seria preciso a época voltar a `(m, c)` depois de uma aplicação: o id só regride por limpeza, e toda limpeza em outra transação grava `c' = now() ≠ c`. Duas limpezas na **mesma** transação dão o mesmo `now()`, mas aí a emissão do token, a aplicação e a repetição teriam de ocorrer dentro dessa mesma transação (o marco não commitado é invisível a outras sessões; a 5270 não é exposta; o PostgREST faz uma RPC por transação) — só uma sessão privilegiada do operador, que já é a autoridade. Resíduo teórico: regressão do relógio do servidor exatamente ao mesmo microssegundo.
- A premissa ("único escritor do marco = 5270 com now(), sem EXECUTE para clientes") passa a ser verificada pelo **S0.6** do 5872 v1.3; se alguém criar outro escritor ou liberar a 5270 sem revisar a época, o GATE falha.

### Preflight somente leitura no LIVE (2026-11-01)

| Verificação | Resultado |
|---|---|
| 23 RPCs/funções usadas pelas migrations e pelo harness | todas presentes com as assinaturas esperadas |
| `binder_auto_arrange_plan`, `preview_…`, `apply_…` | ausentes |
| `chk_bae_event_type` contém `CARDS_AUTO_ARRANGED` | não (5341 ainda não aplicada) |
| Eventos `CARDS_AUTO_ARRANGED` | 0 |
| Tabelas de histórico, mesclagem, imagem, convidadas | presentes |
| Catálogo: POKEMON, pt-BR, STANDARD, REVERSE_HOLO, GENERATION_I | presentes |
| Colunas obrigatórias de expansion/card_set/card/card_variant/physical_card | cobertas pelos INSERTs da fixture |
| `ck_card_set_type` (REGULAR), `ck_card_set_code_format`, UNIQUEs de card/card_set/card_variant | compatíveis com a fixture (códigos `AA<hex>`/`AL<hex>`, uma padrão por carta) |
| `ck_card_variant_default_active` | presente → fixture desativa só variantes não padrão |
| Attach de convidada | só exige mesmo local, ativa, sem fichário próprio → coleção Set convidada é viável |
| Isolamento padrão | `read committed` |
| Escritores do marco de cobertura | só `purge_my_binder_activity`; sem EXECUTE para `authenticated` |

Achado corrigido: o acabamento alternativo da fixture era "o primeiro por código ≠ STANDARD", que no LIVE é `COSMO_HOLO_EBGAMES`; fixado em `REVERSE_HOLO` (5872 v1.3). O harness usa só usuários efêmeros e catálogo sintético; nenhuma linha do titular real (fichário ME3) é lida para escrita.

## Plano executivo vigente — `P2 OPERATIONAL ROUTE CORRECTION-11` (2026-11-01)

**Governança (decisão do proprietário, definitiva):** o MMKYU Collector não usa ambientes isolados, homologação separada nem Supabase Branches. Execução no LIVE pelo protocolo: auditoria independente → preflight somente leitura → migrations só com GO explícito, uma por vez → harness sintético transacional com rollback integral → postchecks independentes e resíduo zero → STOP em qualquer divergência. Nenhuma escrita em exemplares, coleções, reservas ou posições reais. As rotas de ambiente isolado da rodada 10 foram revogadas e seus artefatos (`km/`) removidos.

**Pacote preservado sem alteração:** 5341 v1.0, 5342 v1.2, 5343, 5344 v1.2, 5872 v1.3 (54 ids) e C-220–C-226. Nenhum defeito demonstrado nesta revisão.

### 1. Provas K-M: alcance real no protocolo

| Classe | O que prova | Onde | Situação |
|---|---|---|---|
| **A. Equivalente serial, transação com rollback** | O estado que a sessão em espera encontra depois do commit da outra: K-M1 → `I.1` (repetição → `ALREADY_APPLIED`, mesmo `event_id`, 0 inserções), `I.4`, `I.5`; K-M2 → `C.2` (bolso ocupado após a prévia → `40001`, zero escrita); K-M3 → `C.1` (exemplar movido de local → `40001`, zero escrita); demais escritores `C.3`–`C.6` | 5872 v1.3 | executável; PASS só após execução |
| **B. Garantias estruturais (catálogo + código)** | Ordem de travas coleção → bolsos → exemplares e dois recálculos (`K.1`); 5344 `VOLATILE` em READ COMMITTED → cada comando, depois da espera pela trava, lê um snapshot novo e vê o commit concorrente (`S0.3`/`POST-3`); `UNIQUE (physical_card_id)` imediata e `UNIQUE (slot_id)` diferida impedem dupla posição em qualquer intercalação; gatilho 5248 (dono e local); falha em qualquer ponto desfaz a transação inteira (sem evento parcial) | 5872 (S0, K.1) + LIVE_90 + catálogo lido em 2026-11-01 | parcialmente lido; confirmação final no postcheck |
| **C. Concorrência real entre sessões** | Que a 2ª sessão de fato espera, o tempo de espera, `55P03` após 5 s, ausência de deadlock observada | — | **NÃO EXECUTÁVEL** sem fixture persistente ou dados reais (uma fixture não confirmada é invisível a outra sessão). Não será declarada PASS |
| **D. Riscos residuais** | ver §5 | — | registrados |

Leitura do catálogo LIVE (2026-11-01) usada na classe B: os 5 gatilhos de `collection_layout_slot_assignment` não travam linhas nem chamam a 5122; `binder_activity_begin` não trava linhas; `set_physical_cards_storage` (5287) trava exemplares e depois posições, nunca a coleção. Logo, no cenário K-M3 o grafo de espera é acíclico (a organização espera o exemplar; a mudança de local não espera nada da organização): **sem deadlock possível nesse par**. Nenhum gatilho com efeito fora da transação nas tabelas da fixture (rollback integral). CHECK `chk_bae_event_type` do LIVE = exatamente os 24 tipos que a 5341 regrava (sem regressão) e categorias idênticas; 363 eventos (validação do CHECK trivial).

### 2. Sequência de execução

Ferramenta: Supabase MCP (`execute_sql` para leitura e harness, `apply_migration` para DDL). Uma etapa por vez; cada uma só começa depois de conferido o resultado da anterior. Janela sem uso do app do início ao fim (o FP depende disso).

| # | Etapa | Comando | Evidência esperada | STOP se |
|---|---|---|---|---|
| 0 | Integridade local | `sha256sum 534*.sql 5872*.sql LIVE_*.sql` | hashes = tabela do §4 | qualquer divergência |
| 1 | Preflight R1 | `LIVE_00` bloco PRE | PRE-1…PRE-9 todos `ok = true` | qualquer `false` |
| 1b | Baseline | `LIVE_00` bloco FP | 17 linhas (n, fp) guardadas no relatório | — |
| — | **GO explícito do proprietário para DDL** | — | — | sem GO |
| 2 | 5341 | `apply_migration` nome `p2_5341_extend_binder_activity_auto_arrange_event`, conteúdo integral | sem erro; precheck verde | erro (transação desfeita; o LIVE fica como antes) |
| 3 | 5342 | idem `p2_5342_create_binder_auto_arrange_plan` | sem erro | erro |
| 4 | 5343 | idem `p2_5343_create_preview_my_binder_auto_arrange` | sem erro | erro |
| 5 | 5344 | idem `p2_5344_create_apply_my_binder_auto_arrange` | sem erro | erro |
| 6 | Harness | `execute_sql` com o arquivo 5872 v1.3 inteiro (uma chamada) | 54 linhas PASS + `GATE PASS 54/54`; sem `X.1`; `9.1` PASS | GATE ≠ PASS; qualquer FAIL; `X.1`; não modificar o harness para passar |
| 7 | Postcheck R1 | `LIVE_90` POST; SRC; FP do `LIVE_00`; `get_advisors(security)` | POST-1…7 `ok`; md5 dos corpos = arquivos; FP idêntico ao 1b (n e fp das 17 linhas); advisors sem achado novo nas 3 funções | qualquer divergência |
| 8 | Medições R1 | P.6 (já no passo 6) + `LIVE_70` (M2.0, M2.1, M2.2) | P.6 dentro dos limites de sanidade; M2.0 = 1; M2.1 plano e tempo real no ME3; M2.2 contagens por motivo coerentes com o diagnóstico 05 | M2.0 ≠ 1 (não medir); P.6 fora → investigar antes de liberar frontend |
| 9 | Consolidação | README, 05d, log, INDEX; promoção para `database/schema/` | — | — |

Passo 6 não toca dados reais: usuários, catálogo, coleções e exemplares são sintéticos e efêmeros, criados e desfeitos dentro da mesma chamada (sentinela `TR000`); `9.1` confere contagens antes/depois e o FP do passo 7 confirma conteúdo idêntico. Precedente do mesmo protocolo no LIVE: 5848 (50/50) e 5871 (20/20), resíduo zero.

Medição M2 (`LIVE_70`): o corpo da 5342 executado como SELECT puro em transação `read only`, parâmetros resolvidos por CTE (sem UUID no comando ou na saída); não chama prévia nem aplicação. Validado sintaticamente com `EXPLAIN` sem `ANALYZE` em 2026-11-01 (usa `ix_physical_card_storage_container`, `ix_bae_owner_layout_time`, UNIQUE de posição por exemplar).

Comparação de corpos (passo 7): `python -c "import hashlib,sys;s=open(sys.argv[1],encoding='utf-8').read();print(hashlib.md5(s.split('as $fn$',1)[1].split('$fn$;',1)[0].encode()).hexdigest())" <arquivo>` para 5341 (corpo de `binder_activity_category`), 5342, 5343, 5344.

### 3. Rollback

| Situação | Ação |
|---|---|
| Erro dentro de 5341–5344 | nenhuma: cada arquivo é uma transação; o erro desfaz tudo |
| STOP depois de aplicar parte (harness ou postcheck falhou) | bloco "Rollback" acima (DROP das 3 funções; 5341 só sem evento `CARDS_AUTO_ARRANGED`, recriando CHECK e categoria da 5269), com GO do proprietário; repetir `LIVE_00` PRE-3/PRE-4 para confirmar o estado anterior |
| Harness | sem rollback manual: desfeito pela sentinela; FP confirma |

### 4. Hashes de referência (SHA-256, 2026-11-01)

| Arquivo | SHA-256 |
|---|---|
| 5341 | `ef737043e8c59a18c58b139d0e781cdb741202da1bdf9fa9c834a0e52e4f4c1e` |
| 5342 | `eb319634b8f0f4cc8900263a72aaff28d88a0869d8bd72c021625a4a4eab27b6` |
| 5343 | `1fade081e78c17b06042fd5d94f64d4f77723bca99e1732a5e3e8e98fdc81e0a` |
| 5344 v1.3 | `5f4b0669148930bb4b290e6ae34236237160795d6da96e1bd67674a0987b921b` (v1.2, substituída: `caf1807b…980b`) |
| 5872 v1.4 | `84414defc7a1563e46ffd55fa95eece4174ee06a069516140c0536d22f533b77` (v1.3, substituída: `13ab89d1…7036`) |

Os três `LIVE_*.sql` são registrados no relatório da rodada (gerados nesta rodada).

### 5. Riscos residuais (não comprováveis pelo protocolo)

| # | Risco | Mitigação existente | Consequência se ocorrer |
|---|---|---|---|
| R1 | Espera real sob contenção não medida | `lock_timeout 5s`; travas curtas | `55P03`, nada escrito; interface informa indisponibilidade temporária e oferece nova tentativa iniciada por revalidação (nova prévia), sem repetir a escrita sozinha |
| R2 | Deadlock com algum escritor fora da matriz auditada | ordem coleção → bolsos → exemplares por id; par K-M3 provado acíclico | PostgreSQL aborta uma transação (`40P01`), nada parcial; interface informa falha temporária e oferece nova tentativa controlada iniciada por revalidação, sem repetir a escrita sozinha |
| R3 | Escritor que só acrescenta candidato confirma entre o 2º recálculo e o INSERT | equivale à ordem serial "organizar, depois a outra" (contrato §5) | nenhuma perda; o candidato novo fica para a próxima prévia |
| R4 | Uma subtransação por INSERT (bloco `exception` da 5344): até 500 por confirmação | transação curta; medido em P.6/L.3 | custo de CPU proporcional; observar P.6 |
| R5 | Volume real futuro maior que ME3 | M2 no ME3 + P.6 sintético 501×504 | reavaliar índices se M2 mostrar varredura dominante |

Frontend (`binder-activity.ts` conhecer `CARDS_AUTO_ARRANGED`; tratar `40001` como plano alterado → nova prévia e nova confirmação; `55P03` e `40P01` como indisponibilidade/falha temporária → nova tentativa oferecida, iniciada por revalidação; nunca repetir escrita automaticamente; plano mudado exige revisão e confirmação explícita — contrato §7, v1.4) continua pré-requisito da publicação do botão.

## Execução — `P2 LIVE EXECUTION — GATE 01` (2026-11-01) — **PASS / AWAITING MIGRATIONS GO**

**CONFIRMADO EXECUTADO** (somente leitura, `set transaction read only`; `transaction_read_only=on` confirmado na saída): `LIVE_00` blocos PRE e FP no projeto `mimikyu-core` (PG 17.6.1.147, sa-east-1, `ACTIVE_HEALTHY`). Nenhuma DDL/DML; 5341–5344, 5872, LIVE_70 e LIVE_90 não executados.

Integridade local: SHA-256 dos cinco arquivos = tabela do §4; `LIVE_00` `20a51ebb6a5799a16ea525eec334b6c2d4cbd73fc55288f1390021f9697dc40c`, `LIVE_70` `1672010ec3c4623686392541327c0700eb87d3121e52dc466a619b30af586c9a`, `LIVE_90` `a43cc3be4f29ec5bab2c03186480115a3a568207be96eaf285fc9bd4b1c30f15`. HEAD `a80baba`.

| PRE | Resultado |
|---|---|
| 1 | PASS — PG 17.6; isolamento padrão read committed |
| 2 | PASS — 23/23 dependências presentes |
| 3 | PASS — funções propostas ausentes |
| 4 | PASS — CHECK com os 24 tipos da 5341 (sem o novo); 0 eventos `CARDS_AUTO_ARRANGED` |
| 5 | PASS — categorias do LIVE = corpo substituído pela 5341 |
| 6 | PASS — único escritor do marco de cobertura = 5270, sem EXECUTE para clientes |
| 7 | PASS — POKEMON, pt-BR, STANDARD, REVERSE_HOLO, GENERATION_I |
| 8 | PASS — nenhum gatilho com efeito fora da transação |
| 9 | PASS — nenhuma transação de cliente aberta há mais de 60 s |

Baseline FP (comparar com o `LIVE_90`; md5 sobre linhas inteiras, sem identificadores expostos):

| Tabela | n | fp |
|---|---|---|
| auth.users (ids) | 3 | `485bd38ad30f498c1d8a0bf6eecc3e2e` |
| binder_activity_coverage | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| binder_activity_event | 363 | `320b4040b470da08a34fd598e320ee57` |
| card (ids) | 21246 | `a8440c677492cfc581fea2abfcb35290` |
| card_set (ids) | 201 | `d892e2cdcd7779ac10b572eadeef9ac7` |
| card_variant (id, ativo) | 38011 | `9a00fbf6b25dc0f118d114c2e8c0de4d` |
| collection | 10 | `54563c073b205bd85326f97c23e7ef04` |
| collection_allocation | 723 | `1e1f41d58c5e5457f45230f559db7086` |
| collection_layout | 5 | `808d4cf3e4247b0a7a84dae95313a506` |
| collection_layout_guest | 1 | `8c5d478c01d6eb8f5a275b48f4e467e8` |
| collection_layout_page | 209 | `1d3ae812cc132bbc20d67e5ba4bcaa82` |
| collection_layout_slot | 2343 | `2fad5838a4f806d44476ac2535bfd97d` |
| collection_layout_slot_assignment | 553 | `8e5cda6eaabe7df58f51434420f46f50` |
| collection_layout_slot_expected_content | 753 | `22330bc795990f5b5def666fb7ca46d1` |
| expansion (ids) | 26 | `23eb9c84fcac1d5395913790d08f1edc` |
| physical_card | 2955 | `9c9917d6b413a5acb7ec7a7ce1300e5b` |
| storage_container | 9 | `227adeda0e43fc75afee1da05bc498b7` |

O FP só é comparável se não houver uso do app entre este gate e o `LIVE_90`; qualquer uso intermediário exige recapturar o baseline imediatamente antes das migrations.

## Execução — `P2 LIVE GATE 02 — CONTROLLED MIGRATIONS` (2026-11-01) — **STOP antes da 5344**

Preflight: projeto `mimikyu-core` (PG 17.6.1.147); SHA-256 de 5341–5344 = §4; FP das 17 tabelas idêntico ao GATE 01; funções propostas ausentes; 0 eventos `CARDS_AUTO_ARRANGED`.

| Migration | Ledger | Verificação pós-aplicação | Resultado |
|---|---|---|---|
| 5341 | `20261101135916 p2_5341_extend_binder_activity_auto_arrange_event` | CHECK com 25 tipos (24 anteriores + `CARDS_AUTO_ARRANGED`), validado; 25 categorias corretas (novo → CARDS); ACL de `binder_activity_category` inalterada (`{postgres=X/postgres}`); IMMUTABLE, `search_path` vazio; md5 do corpo `a7f9f99f…0bc4` = arquivo; 363 eventos preservados | **CONFIRMADO EXECUTADO** |
| 5342 | `20261101140019 p2_5342_create_binder_auto_arrange_plan` | SQL, STABLE, INVOKER, `search_path` vazio; ACL `{postgres=X/postgres}` (sem EXECUTE para PUBLIC, anon, authenticated, service_role); 1 versão; md5 `990a31bb…dcee` = arquivo; nenhum comando DML (a palavra `INSERT` aparece só como rótulo de `item_kind`) | **CONFIRMADO EXECUTADO** |
| 5343 | `20261101140115 p2_5343_create_preview_my_binder_auto_arrange` | plpgsql, STABLE, DEFINER, `search_path` vazio, retorno `jsonb`; ACL `{postgres=X/postgres,authenticated=X/postgres}`; anon e PUBLIC sem EXECUTE; 1 versão; md5 `14dee353…7c35` = arquivo; sem DML/PERFORM | **CONFIRMADO EXECUTADO** |
| 5344 | — | — | **NÃO APLICADA** (STOP) |

**Motivo do STOP (defeito demonstrado no corpo aprovado da 5344):** o passo 2 envolve `assert_collection_layout_mutable` (5122, `FOR UPDATE` sem NOWAIT) num bloco `exception when others` que converte qualquer erro que não seja "collection is ARCHIVED" em `P0002 BINDER_NOT_FOUND`. Com o `lock_timeout = 5s` da própria 5344, uma espera pela trava da coleção acima de 5 s (`55P03`) é devolvida como "fichário não encontrado", contrariando o contrato (`55P03`, §3 do contrato e cabeçalho da 5344) e induzindo a interface a uma mensagem errada. Integridade e segurança não são afetadas (o erro aborta a transação inteira, sem escrita). Correção mínima proposta: no handler, re-propagar `lock_not_available` (e qualquer SQLSTATE fora do conjunto mapeado) com `raise;` antes do mapeamento — exige nova versão auditada da 5344.

**Segundo achado (harness 5872 v1.3, S0.4):** a checagem `q.prosrc !~* '\m(insert|update|delete)\M'` sobre o corpo da 5342 falharia, porque o corpo contém o literal `'INSERT'` (rótulo de `item_kind`). Confirmado no LIVE: nenhuma instrução DML, única ocorrência = literal. O GATE do harness seria FAIL por falso negativo; requer correção do harness (padrão de instrução, não de palavra) antes do GATE 03.

Dados reais: FP das 17 tabelas idêntico ao baseline do GATE 01 após 5341–5343. Estado do LIVE: 5341–5343 aplicadas e inertes (5342 interna; 5343 somente leitura, ainda sem consumidor no frontend); nenhuma organização executada. Rollback não aplicado (não autorizado e desnecessário: nenhum efeito sobre dados).

## Correção direcionada — `P2 GATE 02 TARGETED CORRECTION-12` (2026-11-01) — **READY FOR GATE 02 RESUME (aguardando auditoria independente)**

Somente correção local e estática; nada executado no LIVE. Estado do LIVE reconhecido: 5341–5343 aplicadas (GATE 02), 5344 ausente, nenhuma organização executada, nenhum rollback.

**5344 v1.3** — único trecho do corpo alterado: handler do passo 2 (bloco que envolve `assert_collection_layout_mutable`). `when others` → `when raise_exception` (P0001); traduz apenas as duas mensagens de domínio da 5122 (`collection is ARCHIVED…` → `55000 COLLECTION_ARCHIVED`; `collection layout not found or not owned by caller` → `P0002 BINDER_NOT_FOUND`); qualquer outro P0001 é re-propagado com `raise;`; erros de outras classes (55P03, 40P01, 42501, 23xxx) não são capturados. Ordem de travas, plano, token, inserções, histórico e ACL inalterados. Auditoria dos demais handlers: o único outro é `when unique_violation` no laço de INSERT (só 23505 da UNIQUE imediata de exemplar → 40001 PLAN_CHANGED, contratual); não captura trava, permissão nem deadlock. md5 do corpo v1.3: `3cd2d2c578fc4bd9661f6091c8a2198e`.

**5872 v1.4** — só S0.4: a busca de escrita roda sobre o código depois de remover literais e comentários; para a 5342 exige-se também `LANGUAGE sql` + `STABLE` (o PostgreSQL recusa DML em função SQL não volátil na execução, exercida por P.5/P.6). Mesmos 54 ids e mesmo GATE. Simulação local das expressões sobre os corpos dos arquivos: 5342 limpa sem `insert/update/delete`; 5344 limpa sem escrita proibida; controles negativos (DML injetado em cada corpo) detectados; K.1 (ordem de travas e 2 recálculos) continua satisfeito. Validação definitiva só na execução do harness (não autorizada nesta rodada).

| Erro | Origem | v1.2 | v1.3 |
|---|---|---|---|
| `collection is ARCHIVED…` (P0001, 5122) | arquivamento concorrente | 55000 COLLECTION_ARCHIVED | igual |
| `collection layout not found…` (P0001, 5122) | fichário sumiu/trocou | P0002 BINDER_NOT_FOUND | igual |
| `authentication required` (P0001, 5122) | inalcançável (5344 já exige sessão) | P0002 (mascarado) | P0001 propagado |
| 55P03 lock_not_available | `lock_timeout` 5 s na trava da coleção | P0002 (mascarado) | **55P03 propagado** |
| 40P01 deadlock / 40001 serialização | concorrência | P0002 (mascarado) | propagado |
| 42501 / 23xxx / outros | permissão, integridade | P0002 (mascarado) | propagado |
| Demais erros de domínio (28000, 22023, P0002, 55000, 42501 NOT_BINDER_OWNER, 40001, 54000) | fora do bloco | inalterados | inalterados |

Condições para retomar o GATE 02: auditoria independente desta correção; GO explícito; preflight repetido (hashes acima, FP das 17 tabelas = GATE 01, 5341–5343 com md5 registrados, 5344 ausente, e leitura do corpo LIVE da 5122 confirmando as duas mensagens de domínio exatas usadas pelo handler — as mensagens foram tiradas de `database/schema/5122` v2.0, não do LIVE, porque esta rodada não autorizava SQL); aplicação da 5344 v1.3 com o nome `p2_5344_create_apply_my_binder_auto_arrange`; verificação pós-aplicação (config, ACL, md5 `3cd2d2c5…198e`). O harness 5872 v1.4 continua dependendo de GO próprio (GATE 03).

## Execução — `P2 LIVE GATE 02 RESUME-13` (2026-11-01) — **PASS / AWAITING HARNESS GO**

**CONFIRMADO EXECUTADO:** 5344 v1.3 no `mimikyu-core` (PG 17.6.1.147), ledger `20261101141543 p2_5344_create_apply_my_binder_auto_arrange`.

Preflight: SHA-256 do arquivo `5f4b0669…921b` = aprovado; diff do corpo contra a v1.2 restrito ao handler do passo 2 (e ao comentário que o descreve); fora do corpo, idêntico. 5341–5343 inalteradas no LIVE (md5 `a7f9f99f…0bc4`, `990a31bb…dcee`, `14dee353…7c35`; configurações e ACL iguais às do GATE 02; CHECK com 25 tipos); 5344 ausente antes; 0 eventos `CARDS_AUTO_ARRANGED`; FP das 17 tabelas = GATE 01. Corpo LIVE da 5122 (md5 `d600f36f…5070`): RAISE sem `ERRCODE` (SQLSTATE P0001) com as mensagens exatas `authentication required`, `collection layout not found or not owned by caller` e `collection is ARCHIVED — reactivate it before editing the layout` — coerentes com o handler.

Verificação pós-aplicação: assinatura `apply_my_binder_auto_arrange(uuid,text)` → `jsonb`; plpgsql, VOLATILE, SECURITY DEFINER; `proconfig = {search_path="", lock_timeout=5s}`; ACL `{postgres=X/postgres,authenticated=X/postgres}` (anon e PUBLIC sem EXECUTE); 1 versão; md5 do corpo `3cd2d2c578fc4bd9661f6091c8a2198e` = arquivo; corpo contém `when raise_exception then`, o mapeamento explícito de BINDER_NOT_FOUND e `raise;`, e nenhum `when others`. Nenhuma chamada de organização (0 eventos `CARDS_AUTO_ARRANGED`); FP das 17 tabelas idêntico ao GATE 01.

Propagação de `55P03`/P0001 verificada estaticamente no corpo instalado; prova comportamental fica para o harness (sem exemplares reais), não executado nesta rodada.

## Execução — `P2 LIVE GATE 03 — TRANSACTIONAL HARNESS` (2026-11-01) — **STOP (GATE FAIL 48/54)**

**CONFIRMADO EXECUTADO:** 5872 v1.4 (SHA-256 `84414def…3b77`) no `mimikyu-core`, uma chamada, sentinela TR000. Fidelidade do texto executado: md5 do corpo instalado em `pg_temp` = `aa56b4995d99403429a9dfb12ef556ae` = arquivo (linha de evidência acrescentada fora da função).

Preflight: 5341–5344 com md5/config/ACL aprovados; 0 eventos `CARDS_AUTO_ARRANGED`; nenhuma transação de cliente > 60 s; FP das 17 tabelas = GATE 01.

**Resultado:** 54 ids presentes uma vez, sem X.1, 9.1 PASS (resíduo zero e papel restaurado); **48 PASS, 6 FAIL (C.1–C.6)**. GATE = FAIL.

**Causa observada (C.1–C.6):** `42501 permission denied for table binder_activity_event`, levantado na *fixture* de cada caso, antes da chamada à 5344. No laço C do harness, a contagem `select count(*) into v_e0 from public.binder_activity_event …` roda **depois** de `execute 'set local role authenticated'` e **antes** do `reset role`; `authenticated` não tem SELECT nessa tabela (grant confirmado: nenhum). É defeito do harness (leitura de auditoria sob o papel errado), não das funções: nenhum dos seis casos chegou a chamar `apply_my_binder_auto_arrange`. Consequência: **PLAN_CHANGED por mudança concorrente de estado (C.1–C.6) não foi verificado nesta execução**; o R.1 (zero escrita nos caminhos de erro) passou sem a contribuição de C.1–C.6.

| Grupo | Ids | Resultado |
|---|---|---|
| Configuração/ACL/corpo | S0.1–S0.6, K.1 | PASS |
| Fixture | F.1 | PASS (convidada Set e K9 inativa OK) |
| Segurança e isolamento | A.1–A.6 | PASS (anon 42501; sem identidade 28000; usuário B → COLLECTION_NOT_FOUND sem escrita; função interna 42501) |
| Tipos de coleção | T.1–T.6 | PASS (Pokédex/Livre 22023; convidada 42501; sem fichário P0002; arquivada 55000; argumentos 22023) |
| Prévia, elegibilidade, 1:1, ambiguidade, bolsos protegidos | P.1–P.5, G.1–G.3, M.1–M.5 | PASS |
| PLAN_CHANGED por mudança de estado | C.1–C.6 | **FAIL — não executados (defeito de fixture)** |
| Aplicação e não interferência | D.1, D.2 | PASS |
| Histórico | H.1, H.2 | PASS |
| Token e idempotência | I.1–I.5 | PASS (ALREADY_APPLIED; EMPTY/NOTHING_TO_DO; token desconhecido 40001; época; limpeza → 40001) |
| Limite de 500 | L.1–L.3 | PASS |
| Desempenho | P.6 | PASS — prévia 501×504: 85 ms; aplicação de 500 com histórico: 527 ms |
| Atomicidade e resíduo | R.1, 9.1 | PASS (R.1 sem a contribuição de C.1–C.6) |

Não cobertos pelo harness: concorrência real entre sessões (K-M1..K-M3 — só equivalentes seriais), espera de trava/55P03 em execução.

Postcheck: nenhuma fixture remanescente (expansões `AA_*`, Sets `AA/AL…`, usuários `aa5872-*` = 0); FP das 17 tabelas idêntico ao GATE 01; 0 eventos `CARDS_AUTO_ARRANGED`; 5341–5344 com md5/config/ACL inalterados. Sem mudanças de usuários na janela.

Correção necessária (não aplicada; exige rodada própria): no laço C, mover as duas contagens (`v_n`, `v_e0`) para antes de `set local role authenticated` ou envolver com `reset role`/`set local role` — o mesmo padrão já usado no restante do harness.

## Correção do harness — `P2 HARNESS C-SERIES CORRECTION-14` (2026-11-01) — **READY FOR GATE 03 RERUN (aguardando auditoria independente)**

Somente correção local; nada executado no LIVE. O resultado histórico do GATE 03 (5872 v1.4: **48/54 PASS**, C.1–C.6 FAIL por defeito do harness, resíduo zero) permanece registrado acima e não é substituído.

**5872 v1.5** (SHA-256 `210fd31c4b2117292db1de7e99238ef2e623193f2f17acf055573561bf1e7ca1`) — alteração restrita ao laço C.1–C.6 (e às notas de cabeçalho):
- as leituras de controle (plano vigente, posições, eventos `CARDS_AUTO_ARRANGED`, impressão de reservas/alocações/exemplares/posições) passam a rodar como dono do banco (`reset role`); na v1.4 rodavam como `authenticated` — `42501` em `binder_activity_event` e, além disso, a contagem de posições ficaria filtrada por RLS;
- a alteração do cenário e a chamada da 5344 continuam como `authenticated` com a identidade de A (claims de A reafirmados antes da chamada); a 5344 não ganha privilégio;
- cada caso agora exige, além de `40001 AUTO_ARRANGE_PLAN_CHANGED` (SQLSTATE e mensagem): token da prévia ainda vigente antes da alteração; contagem de posições e de eventos inalterada pela chamada; impressão de reservas, alocações, exemplares e posições idêntica antes e depois da chamada; um erro de fixture continua aparecendo como FAIL com a causa, nunca como resultado esperado.

Revisão estática: no laço C, nenhuma leitura de tabela de controle ocorre sob `authenticated` (varredura linha a linha) e a chamada da 5344 ocorre sob `authenticated`; demais seções já liam o histórico como dono do banco (A, P.5, D/H, I.1–I.5, L — conferidas, sem mudança); 54 ids, GATE, TR000/TR_SUB, 9.1 e P.6 inalterados; 5341–5344 com SHA-256 inalterados; `git diff --check` limpo. Nenhum GRANT, migration ou mudança no banco.

## Execução — `P2 LIVE GATE 03 RERUN-15` (2026-11-01) — **PASS / AWAITING POSTCHECK GO**

**CONFIRMADO EXECUTADO:** 5872 v1.5 (SHA-256 `210fd31c…7ca1`) no `mimikyu-core`, uma única chamada `execute_sql`, fixtures sintéticas, sentinela TR000 (rollback integral) e TR_SUB por caso C. O md5 do corpo instalado em `pg_temp` (`a3b4c0d34d7295a45ce06fec7e4415b3`) é igual ao do arquivo, conferido por uma linha de evidência fora da função. Nenhuma função, migration ou GRANT foi alterado. O resultado histórico da v1.4 (**48/54**, seção acima) continua registrado.

Preflight (local + LIVE, somente leitura):
- SHA-256 do harness e de 5341–5344 iguais aos de referência;
- md5, configuração e ACL de 5341–5344 iguais aos do GATE 02/RESUME-13;
- CHECK com 25 tipos;
- ledger com as 4 migrations;
- 0 eventos `CARDS_AUTO_ARRANGED` e nenhuma transação de cliente > 60 s;
- TR000 (×2) e TR_SUB (×2) delimitados;
- 54 ids únicos em `v_expected`;
- no laço C, as leituras de controle rodam como dono do banco e a alteração do cenário e a chamada da 5344 rodam como `authenticated`, com identidade sintética;
- impressão digital (FP) das 17 tabelas igual ao GATE 01.

**Resultado: 54/54 PASS; GATE PASS** (54 ids, cada um uma vez; X.1 ausente; TR000 confirmada pelo 9.1).

| Grupo | Ids | Resultado |
|---|---|---|
| Configuração/ACL/corpo | S0.1–S0.6, K.1 | PASS |
| Fixture | F.1 | PASS (convidada Set e K9 inativa OK) |
| Segurança e isolamento | A.1–A.6 | PASS (anon 42501; sem identidade 28000; B → COLLECTION_NOT_FOUND sem escrita; função interna 42501) |
| Tipos de coleção | T.1–T.6 | PASS (Pokédex/Livre 22023; convidada 42501; sem fichário P0002; arquivada 55000; argumentos 22023) |
| Prévia, elegibilidade, 1:1, ambiguidade, bolsos protegidos | P.1–P.5, G.1–G.3, M.1–M.5 | PASS |
| PLAN_CHANGED por mudança de estado | C.1–C.6 | **PASS** (ver abaixo) |
| Aplicação e não interferência | D.1, D.2 | PASS (APPLIED, 2 inserções, K5 intocado) |
| Histórico | H.1, H.2 | PASS (1 evento por aplicação; 3 na transação) |
| Token e idempotência | I.1–I.5 | PASS |
| Limite de 500 | L.1–L.3 | PASS (501 → 54000 sem escrita; 500 → APPLIED com 500 itens) |
| Desempenho | P.6 | PASS (prévia 501×504: **86 ms**; aplicação de 500 com histórico: **500 ms**) |
| Atomicidade e resíduo | R.1, 9.1 | PASS (R.1 agora inclui C.1–C.6) |

C.1–C.6: em cada caso, o token da prévia é válido antes da alteração (pré-condição verificada como dono do banco). Em seguida, a alteração sintética é feita como `authenticated` ou como dono do banco, conforme o caso, e a 5344 é chamada efetivamente como `authenticated`, com a identidade de A e o token anterior. Resultado em todos os seis: `40001` + `AUTO_ARRANGE_PLAN_CHANGED`, contagem de posições e de eventos `CARDS_AUTO_ARRANGED` inalterada, e impressão (reservas do fichário, alocações, exemplares, posições) idêntica antes e depois da chamada.

| Caso | Alteração | SQLSTATE / mensagem | Impressão antes = depois |
|---|---|---|---|
| C.1 | exemplar movido para outro local | 40001 AUTO_ARRANGE_PLAN_CHANGED | true |
| C.2 | bolso ocupado depois da prévia | 40001 AUTO_ARRANGE_PLAN_CHANGED | true |
| C.3 | reserva removida | 40001 AUTO_ARRANGE_PLAN_CHANGED | true |
| C.4 | variante (não padrão) do par K10 desativada | 40001 AUTO_ARRANGE_PLAN_CHANGED | true |
| C.5 | bolso travado | 40001 AUTO_ARRANGE_PLAN_CHANGED | true |
| C.6 | nova cópia cria ambiguidade | 40001 AUTO_ARRANGE_PLAN_CHANGED | true |

Os casos C são equivalentes seriais (alteração e chamada na mesma sessão). **Concorrência real entre sessões (K-M1..K-M3) e espera de trava/55P03 continuam NÃO PROVADAS** por este harness.

Postcheck (somente leitura, logo após a execução):
- FP das 17 tabelas idêntico ao GATE 01;
- fixtures remanescentes = 0 (expansões `AA_*`, Sets `AA/AL…`, usuários `aa5872-*`, locais e coleções `AA *`);
- 0 eventos `CARDS_AUTO_ARRANGED`;
- 5341–5344 com md5, configuração e ACL inalterados;
- ledger com as 4 migrations;
- nenhuma transação de cliente > 60 s.

Observação: a sequência de `binder_activity_event` avançou (ids consumidos dentro da transação desfeita; maior id persistido continua 383). Isso não é resíduo de dados.

## Execução — `P2 LIVE GATE 04 — FINAL POSTCHECK & PERFORMANCE` (2026-11-01) — **P2 SQL FOUNDATION — HOMOLOGATED / READY FOR PRODUCT UI**

**CONFIRMADO EXECUTADO** (somente leitura; `set transaction read only` em todas as chamadas, `transaction_read_only = on` confirmado na saída): `LIVE_90` (POST, SRC, FP) e `LIVE_70` (M2.0, M2.1, M2.2) no `mimikyu-core`, nessa ordem. Nenhuma chamada a 5343/5344, nenhuma DDL/DML/GRANT.

Preflight:
- SHA-256 de `LIVE_90` (`a43cc3be…0f15`), `LIVE_70` (`1672010e…c9a`) e `LIVE_00` (`20a51ebb…c40c`) iguais aos registrados no GATE 01;
- SHA-256 de 5341–5344 e do 5872 v1.5 inalterados;
- HEAD `a80baba`, sem commit novo;
- conteúdo integral dos dois scripts revisto;
- o corpo do LIVE_70 (M2.1 e M2.2) é idêntico ao corpo da 5342 (md5 `990a31bb…dcee`) com `p_*` substituídos pelo CTE `km_params` — verificação textual automática; SELECT puro, sem chamada de função de escrita.

### LIVE_90 — integridade final

| Controle | Resultado |
|---|---|
| POST-1 (5342: SQL, STABLE, INVOKER, `search_path` vazio, sem EXECUTE de API) | ok |
| POST-2 (5343: plpgsql, STABLE, DEFINER, EXECUTE só authenticated) | ok |
| POST-3 (5344: plpgsql, VOLATILE, DEFINER, `search_path` vazio + `lock_timeout=5s`, EXECUTE só authenticated) | ok |
| POST-4 (uma versão de cada função) | ok |
| POST-5 (CHECK com 25 tipos, `CARDS_AUTO_ARRANGED` → CARDS; categorias preservadas) | ok |
| POST-6 (0 eventos `CARDS_AUTO_ARRANGED`) | ok |
| POST-7 (ledger com as 4 migrations) | ok |
| SRC (md5 dos corpos = arquivos: 5341 `a7f9f99f…`, 5342 `990a31bb…`, 5343 `14dee353…`, 5344 `3cd2d2c5…`) | idêntico |
| FP das 17 tabelas | idêntico ao GATE 01 (n e md5 em todas as linhas), repetido também ao final do LIVE_70 |

Security Advisor: 6 tipos de achado, nenhum novo ligado à P2.
- A 5342 não aparece em nenhum achado.
- A 5343 e a 5344 aparecem apenas em `authenticated_security_definer_function_executable` (WARN). É o padrão esperado de RPC DEFINER do produto: 260 funções na mesma lint, inclusive todas as RPCs do fichário.
- Nenhuma das quatro funções aparece em `anon_security_definer_function_executable` nem em `function_search_path_mutable`.
- Achados pré-existentes, sem relação com a P2: `enforce_user_profile_invariants` com `search_path` mutável, `pg_net` em `public`, proteção de senha vazada desativada e 42 INFO de RLS sem política.

### LIVE_70 — medição ME3 (dados reais, somente leitura)

- **M2.0:** 1 fichário ME3 resolvido pelo CTE.
- **M2.1** (`EXPLAIN (ANALYZE, BUFFERS)` do SELECT puro):

| Métrica | Valor |
|---|---|
| Tempo de execução | **43,3 ms** |
| Tempo de planejamento | 48,5 ms |
| Buffers na execução | 1.088 (todos `shared hit`, 0 lidos do disco) |
| Buffers no planejamento | 1.295 (todos `shared hit`) |
| Linhas devolvidas | 180 (1 HEADER + 148 INSERT + 31 UNFILLED_SLOT) |

Acessos por índice:
- `ix_physical_card_storage_container`;
- `uq_collection_layout_slot_assignment_physical_card` (index-only);
- `collection_layout_slot_image_pkey` (index-only);
- `ix_bae_owner_layout_time`;
- `pk_binder_activity_coverage`;
- `card_variant_pkey`;
- `inventory_pkey` (com Memoize).

As tabelas pequenas de layout são lidas por varredura sequencial.

- **M2.2** (agregado, sem identificadores): HEADER 1 (`insert_count = 148`), INSERT 148, UNFILLED_SLOT/NO_CANDIDATE 31, EXCLUDED_CARD 0.
  - 148 inserções coincidem com o diagnóstico `ELIGIBILITY DIAGNOSIS-05` (148/148 candidatos únicos).
  - O total fica abaixo do limite de 500, então a prévia real seria `READY`.

Risco de desempenho observado (não bloqueante):
- O planejador estima 1–3 linhas para os CTEs `pairs`/`sdeg`/`cdeg`/`cands`, contra 148 reais, e escolhe laços aninhados no CTE `ins`. Isso gera 3 × 21.756 comparações descartadas, crescimento quadrático no número de candidatos.
- No ME3 esses laços somam cerca de 13 ms. No sintético de 501 × 504 (P.6), a prévia inteira levou 86 ms e a aplicação de 500, 500 ms.
- Dentro do teto de 500 inserções por aplicação, o custo continua limitado.
- Monitorar se a regra de limite mudar ou se surgirem fichários com milhares de bolsos elegíveis. Correção possível no futuro (não autorizada aqui): `materialized` com `join` por hash ou índices temporários. Não é dívida estrutural no volume atual.

Não provados por este protocolo (permanecem): concorrência real entre sessões (K-M1..K-M3) e espera de trava/`55P03`.

## Fechamento — `P2 SQL FOUNDATION CLOSEOUT-16` (2026-11-01) — **HOMOLOGADO / PRONTO PARA A INTERFACE**

Consolidação local, sem SQL no LIVE. A auditoria independente aprovou o encerramento da fundação SQL.

**Promoção canônica** (convenção do repositório: cópia em `database/schema/` com apenas o bloco Status diferente; do `begin;` ao fim byte-idêntica à proposta; harness, `LIVE_*` e README permanecem nesta pasta):

| Arquivo canônico | SHA-256 canônico | Proposta (executada) SHA-256 | md5 do corpo = LIVE (GATE 04 SRC) |
|---|---|---|---|
| `database/schema/5341_extend_binder_activity_auto_arrange_event.sql` | `18755507…1f85` | `ef737043…4c1e` | `a7f9f99f…0bc4` |
| `database/schema/5342_create_binder_auto_arrange_plan.sql` | `36378361…bc77` | `eb319634…b6` | `990a31bb…dcee` |
| `database/schema/5343_create_preview_my_binder_auto_arrange.sql` | `2387797d…dfdf` | `1fade081…1e0a` | `14dee353…7c35` |
| `database/schema/5344_create_apply_my_binder_auto_arrange.sql` | `7bef60b3…7694` | `5f4b0669…921b` | `3cd2d2c5…198e` |

Permanecem nesta pasta, inalterados:
- `5872_validate_binder_auto_arrange.sql` v1.5 (`210fd31c…7ca1`; md5 do corpo da função `a3b4c0d3…15b3`, conferido no LIVE);
- `LIVE_00` (`20a51ebb…c40c`), `LIVE_70` (`1672010e…c9a`), `LIVE_90` (`a43cc3be…0f15`).

**Histórico preservado:** GATE 03 com v1.4 = **FAIL 48/54** (defeito do harness no laço C) e GATE 03 RERUN-15 com v1.5 = **PASS 54/54**; nenhum dos dois registros foi reescrito.

**Não provados (não são PASS):** K-M1–K-M3 (concorrência real entre sessões) e `55P03` sob contenção real. Riscos residuais R1–R5 no §5 do plano executivo e no contrato §9.

**Condição de uso real:** nenhuma organização sobre exemplares reais (inclusive no ME3) antes de a interface P2 ser implementada e homologada e de autorização explícita do proprietário.
