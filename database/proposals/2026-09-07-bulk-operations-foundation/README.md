# BULK-01 — Bulk Operations Foundation (2026-09-07)

| Campo | Valor |
|--------|-------|
| **Rodada** | `COLLECTIONS-BULK-OPERATIONS-MODELING-AUDIT-01` → `-REVISION-01` → `-FINALIZATION-01` → `COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01` → `-REVISION-01` → `-IMPLEMENTATION-01` → `-POST-AUDIT-HARDENING-01` → `-REVISION-02` → `-VALIDATION-02` → `-DOCUMENTATION-CLOSURE-01` → `-PRECOMMIT-AUDIT-BUNDLE-01` → `-PRECOMMIT-CORRECTION-02` → `-SCHEMA-PROMOTION-01` |
| **Status** | **`IMPLEMENTED / VALIDATED / CONCURRENCY PROVEN / CLEAN`** — `5142`–`5146` CONFIRMADO EXECUTADO; `5821` v1.3 executado; `K01`/`K02`/`K03` provados externamente. **`5142`–`5146` PROMOVIDAS para `database/schema/`** em `COLLECTIONS-BULK-01-SCHEMA-PROMOTION-01` (2026-09-08); `5821`, o runbook e este `README.md` permanecem aqui como evidência histórica e **não** são promovidos, por convenção. |
| **Escopo** | **Exclusivamente BULK-01**: `bulk_operation` + infraestrutura mínima de idempotência. Nenhuma RPC de negócio (B1/B2/B3) entra aqui. |
| **Baseline do repositório** | HEAD `b65b95de19618d17fdca292b986c31bb2a9aa3f9`, árvore limpa no início da rodada |

## 0. Estado de execução

| Artefato | Estado | Ledger |
|---|---|---|
| `5142_create_bulk_operation_table.sql` | **CONFIRMADO EXECUTADO** | `20260908003848` |
| `5143_create_bulk_operation_result_summary_presence_trigger.sql` | **CONFIRMADO EXECUTADO** | `20260908003907` |
| `5144_create_claim_bulk_operation_function.sql` | **CONFIRMADO EXECUTADO** | `20260908003935` |
| `5145_create_complete_bulk_operation_function.sql` | **CONFIRMADO EXECUTADO** | `20260908003951` |
| `5146_harden_bulk_operation_result_summary_contract.sql` | **CONFIRMADO EXECUTADO** | `20260908011925` |
| `5821_validate_bulk_operation_foundation.sql` | **EXECUTADO** — gate `39 / 36 / 0 / 3` | — |
| `CONCURRENCY-PROOF-BULK-CLAIM.sql` | **EXECUTADO** — `K01`/`K02`/`K03` PASS | — |

**Ordem de aplicação:** `5142` → `5143` → `5144` → `5145` → `5146`. As quatro primeiras foram aplicadas juntas; `5146` é **incremental** e não edita nenhuma delas.

### Numeração — auditada antes de nomear

`5141` era o último `5xxx` usado (Binder). `5142`–`5146` foram consumidas nesta frente — `5146` foi auditado como livre antes de ser criado (ausente de `database/schema/`, de `database/proposals/` e do ledger). `5821` é a validação; faixa `5800`–`5899` = Validações de Collections (`STD-001`).

---

## 1. Diagnóstico

`bulk_operation` existe por **um** motivo: tornar idempotente uma operação de criação de patrimônio em massa. Sem ela, um clique duplo cria patrimônio fantasma **indistinguível** de duplicata legítima — e duplicatas são explicitamente permitidas por `C-21`.

O ambiente favoreceu: `physical_card` = 0, `collection` = 0, `collection_allocation` = 0 no momento da aplicação. Nenhum dado de usuário real, nenhuma migração, nenhuma compatibilidade retroativa a preservar.

Decisões congeladas que este incremento materializa: **D3** (ledger mínimo), **D9** (ledger transacional, sem `FAILED`, claim na mesma transação) e **R9** (invariante de commit por constraint trigger diferido).

**Este incremento não entrega operação de negócio alguma.** Ele entrega a infraestrutura sobre a qual `BULK-02` (`register_physical_cards_bulk`) e os seguintes serão construídos.

---

## 2. Arquivos

| Arquivo | Papel | Destino canônico |
|---|---|---|
| `5142_create_bulk_operation_table.sql` | tabela, CHECKs, UNIQUE de identidade/serialização, RLS, revogação total de acesso direto | **`database/schema/`** (promovida) |
| `5143_create_bulk_operation_result_summary_presence_trigger.sql` | invariante de commit (R9) | **`database/schema/`** (promovida) |
| `5144_create_claim_bulk_operation_function.sql` | claim atômico — `INSERT … ON CONFLICT DO NOTHING` | **`database/schema/`** (promovida) |
| `5145_create_complete_bulk_operation_function.sql` | fecha o claim com `result_summary` | **`database/schema/`** (promovida) |
| `5146_harden_bulk_operation_result_summary_contract.sql` | contrato de `result_summary`: CHECK de tabela + guard no helper interno | **`database/schema/`** (promovida) |
| `5821_validate_bulk_operation_foundation.sql` | harness funcional fail-closed | permanece só aqui — harness **não** é promovido |
| `CONCURRENCY-PROOF-BULK-CLAIM.sql` | roteiro manual **genérico e reutilizável** de `K01`/`K02`/`K03` (não é migration) | permanece só aqui — runbook **não** é promovido |
| `README.md` (este arquivo) | registro de staging da rodada | permanece só aqui — **não** é promovido |

### Sobre o roteiro de concorrência

O arquivo é **genérico de propósito**: `<OWNER>`, `<CHAVE1>`, `<CHAVE2>`, `<OPERATION_ID_A>` e `<PID_*>` são placeholders. A execução de 2026-09-07 usou um arquivo instanciado, com IDs reais de `auth.users` e as duas chaves sorteadas — esse arquivo **não entra no repositório** e foi retirado do staging na rodada `-PRECOMMIT-AUDIT-BUNDLE-01`. O que se versiona é o procedimento, não os identificadores de uma execução.

Está na **v1.2** (`-PRECOMMIT-CORRECTION-02`), que corrigiu um defeito real de roteiro — ver §8.

---

## 3. Modelo

```
bulk_operation
  id                   uuid PK
  owner_user_id        uuid NOT NULL  FK auth.users RESTRICT/RESTRICT
  operation_type       text NOT NULL  CHECK vocabulário fechado
  idempotency_key      uuid NOT NULL
  request_hash         text NOT NULL  CHECK não-branco
  preview_fingerprint  text NOT NULL  CHECK não-branco
  result_summary       jsonb NULL     CHECK NULL ou JSON object (5146)
  created_at           timestamptz NOT NULL DEFAULT now()

  UNIQUE (owner_user_id, operation_type, idempotency_key)
```

**Sem coluna `status`.** Com `FAILED` nunca persistido, `status` teria um único valor possível. Linha committada **é** operação bem-sucedida — definição, não convenção.

**`preview_fingerprint` é `NOT NULL`.** Os dois `operation_type` do vocabulário atual exigem preview antes da confirmação — não existe operação legítima sem fingerprint. Ele continua **fora** da semântica de idempotência: replay nunca é invalidado por mudança posterior do mundo (D9). Ampliar o vocabulário com um tipo que dispense preview exige revisitar esta constraint.

**Nenhum índice além dos estruturais.** Só a PK e o índice implícito da UNIQUE. O índice `(owner_user_id, created_at DESC)` da primeira proposta foi **removido**: não há workload aprovado que o justifique, e índice sem medição é custo de escrita garantido contra benefício hipotético.

Vocabulário fechado na V1: `REGISTER_PHYSICAL_CARDS` (B1), `REGISTER_CARD_SET` (B2). Ampliar exige migration própria.

### Contrato de `result_summary` — três camadas complementares

| Camada | Query | Garante |
|---|---|---|
| `NOT NULL` estrutural | — | **não existe**: o claim precisa nascer NULL |
| Constraint trigger diferido | `5143` | nenhuma linha **persistente** com SQL NULL |
| `CHECK` imediato + guard no helper | `5146` | quando preenchido, é um **JSON object** |

A terceira camada não é redundância. `5143` só testa `IS NOT NULL`, e **`'null'::jsonb` não é SQL NULL** — passaria pelo trigger e seria devolvido no REPLAY como resultado legítimo de uma operação concluída. Array, string, number e boolean idem. O resumo tem campos nomeados (`created`, `allocated`, …); nada mais é um resumo.

---

## 4. Matriz de grants e RLS

`bulk_operation` é **ledger interno**, não Activity/Audit. Na V1 **nenhum papel de aplicação tem caminho de acesso direto**:

| Papel | SELECT | INSERT | UPDATE | DELETE | TRUNCATE/REFERENCES/TRIGGER/MAINTAIN |
|---|:--:|:--:|:--:|:--:|:--:|
| `authenticated` | **não** | não | não | não | `REVOKE ALL` |
| `anon` | não | não | não | não | `REVOKE ALL` |
| `service_role` | não | não | não | não | `REVOKE ALL` |
| `postgres` (owner) | — | — | — | — | — |

`relacl` medida após a aplicação: `postgres=arwdDxtm/postgres` — nenhum papel de aplicação na ACL.

Leitura e escrita operacionais acontecem **exclusivamente** dentro das funções `SECURITY DEFINER` de `5144`/`5145`, que rodam como `postgres`.

RLS fica **ligada** e a policy `bulk_operation_select_own` (`FOR SELECT USING (owner_user_id = (select auth.uid()))`, `polroles = {0}`, sem `WITH CHECK`) existe como **defesa em profundidade**: se um `GRANT` de leitura for concedido no futuro — uma tela de histórico, por exemplo —, o escopo por dono já está em vigor. Hoje ela não é exercida, porque não há caminho de acesso.

`S06` prova isso em **runtime**, não por leitura de catálogo: uma sessão `authenticated` recebe `42501 insufficient_privilege` antes mesmo de a RLS ser avaliada.

As três funções: `SECURITY DEFINER`, `search_path = ''`, owner `postgres`, `proacl = postgres=X/postgres` — não-NULL e **sem entrada `grantee = 0`** (PUBLIC). Nenhuma é RPC pública — precedente `5122` (`assert_collection_layout_mutable`), helper interno do Binder com o mesmo tratamento.

---

## 5. Invariante de commit (R9)

`NOT NULL` não serve: o claim nasce antes do resultado. `CHECK` não serve: PostgreSQL não permite `CHECK` DEFERRABLE. Só um **CONSTRAINT TRIGGER `DEFERRABLE INITIALLY DEFERRED`** — precedente literal `5057`/`5058`/`5059`.

O trigger **não inspeciona `NEW.result_summary`** — esse valor é o do instante do INSERT, quando é legitimamente NULL. Ele **reconsulta a linha por `NEW.id`** no disparo (fim da transação) e avalia o **estado final**, já com o UPDATE de `5145` aplicado.

`AFTER INSERT OR UPDATE`: sem grants de UPDATE para cliente algum, o caminho de regressão seria uma RPC futura zerando `result_summary`. Cobrir UPDATE é defesa em profundidade barata.

Linha apagada na mesma transação: a reconsulta não encontra nada, não há invariante a violar, retorna sem erro. Tratado explicitamente.

---

## 6. Idempotência e serialização

O mecanismo de serialização é o **índice único**, não código de aplicação. `INSERT … ON CONFLICT DO NOTHING` sem `SELECT`-antes-de-`INSERT`:

| Situação | Comportamento do índice | Desfecho |
|---|---|---|
| Nenhuma linha | insere | **CLAIMED** |
| Linha **visível** (committada ou da própria transação) | 0 linhas, imediato | decidido pelo **estado lido** — ver abaixo |
| Linha **em voo** (outra sessão) | **BLOQUEIA** até a outra resolver | outra COMMITOU → 0 linhas → estado lido · outra ABORTOU → linha some → insere → **CLAIMED** |

`SELECT`-antes-de-`INSERT` seria corrida: entre a leitura e a escrita, outra sessão insere a mesma chave. Não existe consulta que feche essa janela sem lock explícito.

### "0 linhas" não significa "linha committada"

A primeira proposta assumia isso. É **falso**: 0 linhas significa apenas *existe linha visível para esta transação*, e essa linha pode ser a da própria transação, ainda com `result_summary` NULL. Tratá-la como REPLAY devolveria `result_summary` NULL ao chamador como resultado legítimo — patrimônio nunca criado apresentado como criado.

O desfecho é decidido pelo **estado lido**:

| Estado lido | Desfecho |
|---|---|
| linha ausente | erro `55000` — invariante interno |
| `request_hash` **diferente** | **CONFLICT** (o chamador traduz em `BULK_IDEMPOTENCY_CONFLICT`) |
| mesmo hash + `result_summary` **NULL** | erro `55000` — operação incompleta. **Nunca REPLAY** |
| mesmo hash + `result_summary` **preenchido** | **REPLAY** |

O terceiro caso é inalcançável em produção sob o contrato vigente — `5143` impede que uma linha assim seja committada. Ele é tratado assim mesmo por ser exatamente a situação em que a premissa antiga mentiria. Falhar alto ali é bug de fluxo do chamador, não desfecho de negócio.

**Replay é independente do mundo (D9).** `5144` não valida `preview_fingerprint` — isso é do caminho novo (passo 5 de B1/B2). Consequência assumida: se o usuário apagou depois as cartas criadas, o replay ainda devolve os ids originais. É o comportamento correto de um replay.

---

## 7. Harness `5821` v1.3 — gate atingido

**`TOTAL 39 / PASS 36 / FAIL 0 / NOT PROVEN 3`**, executado ao vivo em 2026-09-07 com baseline 0 e postcheck pós-`ROLLBACK` = 0. `failing_cases` = `null`. Os 3 NOT PROVEN são **exatamente** `K01`, `K02` e `K03`; nenhum `*-ABORT` presente.

Aritmética — **contada mecanicamente no arquivo**, não estimada:

```
rótulos estáticos distintos                       43
− fail-only (F/T/C/R-ABORT)                      − 4   inalcançáveis no caminho saudável
= TOTAL de runtime                                39
    NOT PROVEN (K01, K02, K03)                     3
    PASS                                          36
    FAIL                                           0
```

(`T01` aparece em dois pontos do arquivo — ramo de sucesso e ramo de exceção —, mutuamente exclusivos: um rótulo, um registro de runtime. `E05` e `R08` são gravados através de `_expect_error`, não de `_rec` direto.)

| Grupo | Casos | Cobre |
|---|---|---|
| `F` | F01 | fixture somente leitura, dois `auth.users` distintos |
| `E` | E01–E08 | tabela/owner/RLS · colunas exatas **sem `status`** e com `preview_fingerprint` NOT NULL · **UNIQUE com a lista ordenada de colunas conferida** · **FK com coluna local E remota conferidas** · CHECK de vocabulário (comportamental) · trigger `AFTER INSERT OR UPDATE` + `DEFERRABLE INITIALLY DEFERRED` (bits de `tgtype`) · **somente índices estruturais** · **CHECK de `result_summary` presente** |
| `S` | S01–S06 | **expressão efetiva da policy** conferida, mais `polroles={0}` e ausência de `WITH CHECK` · `authenticated` sem privilégio algum · **`anon` e `service_role` sem nenhum dos 4 verbos DML** · TRUNCATE/REFERENCES/TRIGGER/**MAINTAIN** revogados dos **três** papéis · as 3 funções conformes com **`proacl` não-NULL e sem `grantee = 0`** · ausência de caminho de acesso provada em runtime (`42501`) |
| `T` | T01–T05 | claim completo passa · **NULL impede commit** · **valida estado final, não `NEW`** · **UPDATE zerando também impede** · linha apagada não falha |
| `C` | C01–C06 | CLAIMED · REPLAY sobre claim **já completado**, ignorando fingerprint · CONFLICT · owner sempre `auth.uid()` · **prova estática** de `ON CONFLICT DO NOTHING` sem `SELECT` antes · **claim incompleto levanta erro e nunca vira REPLAY** |
| `R` | R01–R08 | SQL NULL · **`'null'::jsonb`** · array · string · number · boolean — todos rejeitados · JSON object aceito **no mesmo claim, intacto após as 6 rejeições** · **CHECK de tabela barra `UPDATE` direto**, sem passar pelo helper |
| `K` | K01–K03 | concorrência real — **NOT PROVEN no harness**, provado externamente (§8) |
| `X` | X01, X02 | **baseline** medido antes de qualquer escrita e obrigatoriamente 0 · o harness escreveu de fato. Nenhum dos dois afirma que o ROLLBACK ocorreu |

### Técnica obrigatória do grupo T

O trigger é DEFERRED e o harness nunca comita. Para provar "o COMMIT falha", o disparo é forçado com

```sql
SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;
```

dentro de um savepoint, revertido em seguida — o que também restaura o modo DEFERRED e descarta os eventos pendentes. Sem isso, `T02`/`T04` seriam impossíveis de provar sem comitar de verdade.

### Papel de execução

O `5821` roda como **`postgres`**, ou outra role administrativa com `EXECUTE` **explícito** sobre os três helpers.

**`service_role` não serve** como role SQL direta: `EXECUTE` foi revogado dela — é exatamente o que `S05` exige — e o grupo `C` abortaria com `42501`. O mesmo vale para `authenticated` e `anon`.

O grupo `C` define **apenas `request.jwt.claims`**, sem `SET ROLE` — que é como o chamador real opera: a RPC `SECURITY DEFINER` de BULK-02/BULK-04 roda como `postgres`. A primeira versão do harness trocava de role e chamava `claim_bulk_operation()` como `authenticated`, contradizendo `S05` e abortando o grupo inteiro. Defeito próprio, corrigido antes de qualquer execução. O único `SET ROLE` que resta está em `S06`, e existe para provar **ausência** de acesso.

### Zero resíduo — protocolo em três chamadas

O harness roda em `BEGIN … ROLLBACK` e o relatório é lido antes do rollback. Nenhum caso dentro dele pode, portanto, provar zero resíduo: quando os casos rodam, o rollback ainda não aconteceu. A prova é a **CALL 3**, fora do arquivo:

```
CALL 1 — do BEGIN; até o SELECT final, inclusive
CALL 2 — ROLLBACK;
CALL 3 — SELECT count(*) AS deve_ser_zero FROM public.bulk_operation;   -- medido: 0
```

`X01` garante o outro lado da conta: se a tabela já tivesse linhas antes, um `count = 0` depois seria impossível e um `count > 0` seria ambíguo. Baseline medido: **0**.

A v1.2 tentava provar isso dentro do harness com `xmin = pg_current_xact_id()::xid`. **Estava errado** — `pg_current_xact_id()` devolve o xid da transação de topo, e as linhas deste harness nascem dentro de blocos `DO` com `EXCEPTION`, que são subtransações e carregam SUBXID. A comparação reprovaria linhas legítimas.

---

## 8. Prova de concorrência externa — `K01`/`K02`/`K03` PASS

Os três casos exigem **duas sessões persistentes e simultâneas**, com a transação de A aberta enquanto B tenta o mesmo claim. Foi medido que o canal MCP `execute_sql` não preserva sessão nem transação entre chamadas — mesma classe de `C04`/`R18` do `5818`, e mesmo tratamento: gravados como NOT PROVEN no harness, **jamais convertidos em PASS artificial**, e provados por roteiro manual.

**Configuração efetivamente usada em 2026-09-07** — registrada com precisão porque só A e B precisam de persistência:

| Papel | Canal | Sessão | Privilégio |
|---|---|---|---|
| **A** (mutante) | `psql`, Session Pooler, porta 5432 | **persistente** | role temporária `bulk_k_probe` — `EXECUTE` explícito nos dois helpers, **sem acesso direto à tabela** |
| **B** (mutante) | `psql`, Session Pooler, porta 5432 | **persistente** | idem |
| **Observador** | SQL Editor do Supabase | **one-shot** | somente leitura de `pg_stat_activity`/`pg_blocking_pids` |

Ou seja: **duas sessões `psql` persistentes para A/B e observador externo via SQL Editor do Supabase.** O SQL Editor não serve para A/B (não preserva sessão/transação entre execuções), mas serve perfeitamente como observador, porque o observador não precisa manter transação alguma. `bulk_k_probe` foi removida no cleanup.

| Caso | Resultado | Evidência |
|---|---|---|
| `K01` | **PASS** | A segurou o claim; B bloqueou. Observador externo: `pg_blocking_pids(B) = [A]`, `bloqueado_por_a = true`, `wait_event_type = Lock`, `wait_event = transactionid` |
| `K02` | **PASS** | A completou e COMMITOU; B desbloqueou com **REPLAY**, mesmo `operation_id` da operação concluída; contagem final da identidade = 1 (B não criou linha nova) |
| `K03` | **PASS** | A fez claim, B bloqueou por A, A executou ROLLBACK; B desbloqueou com **CLAIMED**; rollback de B; contagem final = 0 |

Isto estabelece que o **índice único é o mecanismo de serialização**, não código de aplicação.

**Cleanup:** `fx_residuo = 0`; role temporária `bulk_k_probe` removida, `role_residuo = 0`.

**Nota de execução (registrada por honestidade):** houve uma primeira tentativa inválida de `K02` que fez `SELECT` direto na tabela usando a role temporária sem privilégio — o que é exatamente o comportamento correto do ledger interno. A transação foi revertida, a chave confirmada com `count = 0`, e `K02` foi reexecutado corretamente usando o `operation_id` devolvido pelo claim. **Não foi defeito da migration nem do produto — foi defeito do próprio roteiro**, cujo PASSO 4 recuperava o `operation_id` por `SELECT` na tabela. Corrigido na v1.2 do runbook: o id passa a ser anotado no PASSO 1 a partir do retorno de CLAIMED e usado literalmente no PASSO 4, sem tocar a tabela.

**Papel de conexão de A/B — regra correta (v1.2 do runbook):** exige-se papel com `EXECUTE` **explícito** nos dois helpers, não "postgres ou papel administrativo". No estado normal apenas `postgres` tem esse acesso; para a prova cria-se uma role temporária de teste com privilégio mínimo (EXECUTE nos helpers, nada na tabela), removida no cleanup. `authenticated`/`anon`/`service_role` continuam sem `EXECUTE` por padrão. As etapas de guard, contagem de estado e limpeza tocam a tabela e por isso rodam por **conexão administrativa** (owner) separada, one-shot.

**Resultado consolidado: 39/39 efetivamente provados** — 36 pelo harness, 3 pela prova externa.

---

## 9. Riscos restantes

| # | Risco | Severidade |
|---|---|---|
| **B4** | `request_hash` é calculado **fora** do banco (pelo chamador B1/B2). A normalização precisa ser idêntica nos dois lados, ou a idempotência silenciosamente não funciona. | **Alta** — `BULK-02` deve incluir caso provando que a mesma requisição, reordenada, produz o mesmo hash |
| **B3** | `bulk_operation` cresce sem política de retenção. Irrelevante na V1 (volume desprezível), vira dívida se o produto escalar. | Baixa — registrar, não resolver agora |
| **B5** | `add_physical_cards()` (`5012`) permanece canônica e **não removida** (D6). Auditoria/migração de callers e depreciação ficam para depois de `BULK-02`, em cleanup próprio. | Baixa |

Os riscos `B1`/`B2` da proposta original (concorrência desenhada mas não medida) foram **quitados** pela prova externa da §8.

---

## 10. Estado final e próximo passo

**`5142`–`5146` APLICADAS · `5821` v1.3 EXECUTADO · `K01`–`K03` PROVADOS · ZERO RESÍDUO · `5142`–`5146` PROMOVIDAS PARA `database/schema/` · COMMIT/PUSH NÃO REALIZADO.**

**Próxima frente canônica: `BULK-02` — `register_physical_cards_bulk`.** Sequência macro congelada:

```
BULK-02 → BULK-03 → CATALOG-VARIANT-DEFAULT-BACKFILL-01 → BULK-04 → BULK-05 → BULK-06
```

`BULK-02` **consome** `claim_bulk_operation()`/`complete_bulk_operation()` — não os redefine. O contrato está congelado e validado.

---

## 11. Nota sobre os cabeçalhos dos SQL

Os arquivos desta pasta declaravam `Status: PROPOSTA — NÃO EXECUTADO` enquanto eram proposta. Na rodada `-PRECOMMIT-AUDIT-BUNDLE-01`, antes do commit, os cabeçalhos foram corrigidos para `CONFIRMADO EXECUTADO (2026-09-07)` — informação factual, não decorativa: manter "NÃO EXECUTADO" num artefato versionado depois da aplicação seria mentira documental.

**A mudança foi exclusivamente de comentário/cabeçalho.** O corpo executável (`BEGIN;` … `COMMIT;`, ou `BEGIN;` … `ROLLBACK;` no `5821`) permaneceu **byte-idêntico**, provado por SHA-256 antes e depois:

| Arquivo | SHA-256 do corpo executável (antes = depois) |
|---|---|
| `5142` | `2d1e4bed104f0b21f57197c14e16f17566146bce342fac0cb814b495f78f4bbd` |
| `5143` | `2d690e2c8aaf78d339ef4b1f10de3b976a3608cf2d8fb827cce2b11bfc970c4b` |
| `5144` | `4d99b169b27d45739f9a2fb683034048a376e6cad1d080faf4ff93403a49cdca` |
| `5145` | `472a9f49a79e1e8e193e66cb5c7cf27c0dce15d54939d81808aa12351ae7eb36` |
| `5146` | `009106619564c0c223d8358c36cea60bb1c3083a3aadc4b03c6a827b43d9e344` |
| `5821` | `d84ab4ae2c81803e21dc1f2bbbcdeb82f38a0c6c5cffdef513484d075bc84ac3` |

Na rodada seguinte (`-PRECOMMIT-CORRECTION-02`), o `5821` recebeu **mais uma edição só de comentário**, na linha 110 — antes do `BEGIN;` da linha 213 —, trocando "três sessões `psql` reais" pela descrição factual da execução. O SHA-256 do corpo executável foi **reconferido e permanece `d84ab4ae…`**. Nenhum outro `.sql` foi tocado nessa rodada; o `CONCURRENCY-PROOF-BULK-CLAIM.sql` mudou de conteúdo, mas **não é migration e nunca foi aplicado** — é roteiro manual.


---

## 12. Promoção para `database/schema/` (2026-09-08)

Rodada `COLLECTIONS-BULK-01-SCHEMA-PROMOTION-01`. Nenhum SQL executado, nenhuma lógica alterada.

**Política canônica aplicada**, reconfirmada diretamente no histórico do repositório:

- migrations estruturais **executadas e validadas** são promovidas para `database/schema/`;
- as cópias em `database/proposals/` permanecem como **evidência histórica**;
- **harnesses, runbooks e `README.md` de staging NÃO são promovidos.**

| Arquivo | Promovido | SHA-256 do corpo executável (`BEGIN;`..`COMMIT;`) — proposal = schema |
|---|:--:|---|
| `5142_create_bulk_operation_table.sql` | sim | `2d1e4bed104f0b21f57197c14e16f17566146bce342fac0cb814b495f78f4bbd` |
| `5143_create_bulk_operation_result_summary_presence_trigger.sql` | sim | `2d690e2c8aaf78d339ef4b1f10de3b976a3608cf2d8fb827cce2b11bfc970c4b` |
| `5144_create_claim_bulk_operation_function.sql` | sim | `4d99b169b27d45739f9a2fb683034048a376e6cad1d080faf4ff93403a49cdca` |
| `5145_create_complete_bulk_operation_function.sql` | sim | `472a9f49a79e1e8e193e66cb5c7cf27c0dce15d54939d81808aa12351ae7eb36` |
| `5146_harden_bulk_operation_result_summary_contract.sql` | sim | `009106619564c0c223d8358c36cea60bb1c3083a3aadc4b03c6a827b43d9e344` |
| `5821_validate_bulk_operation_foundation.sql` | **não** | — |
| `CONCURRENCY-PROOF-BULK-CLAIM.sql` | **não** | — |
| `README.md` | **não** | — |

A única diferença entre a cópia em `proposals` e a cópia em `schema` está no **cabeçalho de comentário**, e ela é factual, não decorativa:

| Trecho | `proposals` | `schema` |
|---|---|---|
| `Status......:` | `CONFIRMADO EXECUTADO (2026-09-07)` | `CONFIRMADO EXECUTADO / LIVE / PROMOVIDO` |
| `STATUS DESTA QUERY:` | ponteiro curto para este README | bloco completo com ledger, gate do `5821`, prova externa de `K01`–`K03` e nota de promoção |

**Ambas as alterações ficam ANTES do `BEGIN;`** de cada arquivo — o `diff` proposal × schema toca exclusivamente a linha 6 e o bloco de rodapé do cabeçalho. O corpo executável é byte-idêntico, provado pelos SHA-256 da tabela acima.

Mesmo padrão de promoção já aplicado a `5100`–`5103` (Fatia E), `6117`–`6126` (Fatia D) e `5085`–`5099` (Fatia B).
