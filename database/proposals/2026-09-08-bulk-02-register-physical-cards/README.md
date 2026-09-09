# BULK-02 — `register_physical_cards_bulk`

| Campo | Valor |
|---|---|
| **Pacote** | `COLLECTIONS-BULK-02` — B1, registro em massa de Physical Cards |
| **Rodada** | `-GATE-A-01` → `-GATE-A-REVISION-01` → `-GATE-A-REVISION-02` → `-GATE-A-FINAL-CORRECTION-01` → `-IMPLEMENTATION-01` → `-HARNESS-CORRECTION-01` → `-GATE-B-01` → **`-DOCUMENTATION-CLOSEOUT-01`** |
| **Status** | **`EXECUTED / VALIDATED / CONCURRENCY PROVEN / PROMOTED / DOCUMENTED`** — `5147`–`5150` aplicadas e promovidas para `database/schema/`; contrato canônico consolidado em `docs/05d-colecoes-e-usuarios.md`, revisão `1.23` |
| **Baseline de partida** | HEAD `9d149add43e93226331e4f4af4eaabd69ca46213` |
| **Vinculante** | `COLLECTIONS-BULK-OPERATIONS-MODELING-FINALIZATION-01` |
| **Depende de** | BULK-01 CLOSED (`5142`–`5146`, em `database/schema/`) |
| **Data** | 2026-09-08 (proposta) · 2026-09-09 (execução e promoção) |

---

## 0-A. Estado de execução — CONFIRMADO

### Ledger real das migrations

| Ordem | `version` | `name` | SHA-256 do corpo executável (`BEGIN..COMMIT`) |
|---|---|---|---|
| 1 | `20260908235708` | `create_bulk_canonicalization_functions` | `ffdc7df3172c59ac161db931541c307f7a8990048e013699f9b9603a4dd390b2` |
| 2 | `20260908235737` | `create_bulk_lock_operation_scope_function` | `c4d53932f6443585013e50e441d540ef14950bc0ea574cc9cf69860daf022b4a` |
| 3 | `20260908235815` | `create_preview_fingerprint_register_physical_cards_function` | `42b33dfcf913b0d247b6fc23f311cda2bea36e85453cad3fe7a18cd2f48d94c2` |
| 4 | `20260909000013` | `create_register_physical_cards_bulk_function` | `9f808c3b962dc268e7f87ff665b400f5ac82c1344c6eb1931363246a0d797237` |

### Validação

| Evidência | Resultado |
|---|---|
| Postcheck estrutural | **PASS** — `5147` IMMUTABLE/interno · `5148` `SECURITY DEFINER` owner `postgres` · `5149` `SECURITY INVOKER` + `VOLATILE` + sem `EXECUTE` para os 4 papéis · `5150` assinatura única `p_request jsonb → jsonb`, `authenticated=true`, demais `false` · helpers BULK-01 intactos |
| Harness `5822` v2.1 | **`64 TOTAL / 64 PASS / 0 FAIL / 0 NOT PROVEN`**, `gate_ok = true` |
| Zero resíduo | Δ = 0 nas **8** tabelas, baseline-relativo; `collection LIKE 'BULK02 HARNESS%'` = 0 |
| `CONCURRENCY-PROOF-PREVIEW-STALE` | **PASS** — B bloqueada por A (`wait_event = transactionid`); após COMMIT de A → `PREVIEW_STALE`; F0 ≠ F1; contraprova com F1 → `CREATED` / 2 cartas; claims = 0; fixtures = 0; role temporária = 0 |

### Promoção canônica

`5147`–`5150` promovidas para `database/schema/`, com **corpo executável byte-idêntico** ao das cópias desta pasta (SHA-256 acima, medido nos dois lados). Nas cópias promovidas mudaram **apenas duas linhas de cabeçalho** — `Status......:` e `STATUS DESTA QUERY:` → `CONFIRMADO EXECUTADO / LIVE / PROMOVIDO`.

**NÃO promovidos**, por política canônica — permanecem só aqui, como evidência histórica: `5822` (harness), `CONCURRENCY-PROOF-PREVIEW-STALE.sql` (runbook) e este `README.md`.

### Nota de execução — adaptação de transporte do harness

Foi **medido nesta rodada** que o canal MCP `execute_sql` não preserva sessão nem transação entre chamadas (`temp_sobreviveu = false`; xid `211038 → 211039`). O protocolo literal de três chamadas comitaria a CALL 1 e deixaria resíduo. O `5822` rodou então em **chamada única**, com o relatório final entregue por `RAISE EXCEPTION` — que aborta a transação e força o ROLLBACK por construção. Nenhum caso de teste foi alterado: o gate avaliado é o mesmo `count(*) = 64 AND fail = 0` do arquivo. Mesma classe de limitação de canal já registrada em `K01`–`K03` de BULK-01.

### Defeito real encontrado e corrigido — no harness, não no produto

A primeira execução do `5822` deu **59/64**. Os 5 FAIL eram `E01`–`E05`, todos pela mesma asserção: `proconfig @> ARRAY['search_path=']`. O PostgreSQL persiste `SET search_path = ''` como **`search_path=""`**, com o valor entre aspas — a comparação por literal nunca casaria. Os objetos estavam corretos; a expectativa é que estava errada.

Corrigido em `-HARNESS-CORRECTION-01` reaproveitando o helper canônico `pg_temp._empty_search_path(p_oid)` do `5821` (BULK-01), que remove o prefixo e desfaz o quoting. Registro honesto: o idioma correto já existia no repositório desde BULK-01 e não foi reaproveitado na primeira escrita do `5822`.

---

## 0. O que mudou na REVISION-02

A auditoria aprovou a arquitetura de `5147`, `5148` e o fluxo principal
de `5150`, e manteve NO-GO por dois blockers em `5149`, mais dois itens
de cobertura. **Nada da arquitetura aprovada foi tocado.**

| # | Blocker / item | Correção |
|---|---|---|
| 1 | `5149` era `STABLE` | Agora **`VOLATILE`**. `STABLE` usa o snapshot do início da query chamadora: depois de esperar no `FOR UPDATE` de `5148`, o recálculo poderia ler o estado ANTERIOR ao commit que liberou o lock — e `PREVIEW_STALE` nunca dispararia. Prova estrutural nova: **`E08`** (`provolatile = 'v'`). |
| 2 | `5149` era endpoint público | Agora **helper INTERNO**: `SECURITY INVOKER`, `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`/`service_role`. `BULK-03` será a interface pública de Preview. Motivo adicional: `5149` tem só guard mínimo e não impõe o teto de 1000 — pública e `SECURITY DEFINER`, abriria trabalho não limitado escolhido pelo chamador. **Não** foram duplicados nela os guards de `5150`; mantê-la interna é a solução. `S05` reescrito. |
| 3 | Faltava prova concorrente do blocker novo | Runbook **`CONCURRENCY-PROOF-PREVIEW-STALE.sql`**. Não repete `K01`/`K02`/`K03`. |
| 4 | Baseline cobria 6 tabelas | Agora **8**: `create_reference_based_card_set_collection()` escreve também em `collection_reference` e `collection_card_set_reference`. Baseline, relatório, CALL 3 e este README atualizados. |

Gate do harness: **63 → 64** (entrada de `E08`).

---

## 1. O que mudou na REVISION-01

A auditoria ChatGPT do GATE A **aprovou D-2** (`request_hash` derivado
dentro do banco, nunca recebido do cliente) e reprovou o resto por
divergência com o `FINALIZATION-01`. A proposta foi reconstruída.

| # | Exigência da auditoria | Como foi atendida |
|---|---|---|
| 1 | Assinatura congelada `p_request jsonb → jsonb` | `5150` tem exatamente essa assinatura. Envelope com contrato FECHADO de chaves. `E06` prova assinatura e sobrecarga única. |
| 2 | Caminho NEW com locks `INVENTORY → COLLECTION → STORAGE`, fingerprint recalculado DENTRO da transação, `PREVIEW_STALE`, e só depois validar/escrever | Passos 4→5→6 de `5150`. `G05` prova que `PREVIEW_STALE` dispara **antes** da validação de lifecycle. REPLAY retorna no passo 3 e nunca chega ao fingerprint. |
| 3 | I9 — fonte canônica/reutilizável única de ordem de locks para B1/B2 | `5148` `bulk_lock_operation_scope()`. `L01` prova a ordem na fonte; `L02` prova que B1 **não tem `FOR UPDATE` próprio**. |
| 4 | `request_hash` server-side, independente da ordem, e fonte única para BULK-03 | `5147` `bulk_canonical_json()` + `bulk_request_hash()`. Grupo `H` (5 casos). |
| 5 | Duplicidade semântica `(uuid, uuid)`, não concatenação textual | `5150` §1.5 compara tuplas de `uuid`. `P13` usa o mesmo UUID em CAIXA ALTA — que a comparação textual deixaria passar. |
| 6 | IDs inválidos/inexistentes abortam com LISTA, antes das escritas | `5150` §1.3 (sintático), §6.2/§6.3 (inexistente) e §6.4/§6.5 (Game/elegibilidade), todos com lista na mensagem e completa no `DETAIL`. `P09`, `R06`, `A06`. |
| 7 | Segurança testada nos quatro papéis | `S01` authenticated=true · `S02` anon=false · `S03` service_role=false · `S04` PUBLIC=false por `aclexplode`. |
| 8 | Corrigir a justificativa D-1 | Reescrita. Ver §4 — o argumento anterior estava errado. |
| 9 | Gate do `5822` com a lista completa de casos + resíduo baseline-relativo | `5822` v2.0, **63/63**, postcheck relativo às **seis** tabelas tocadas. |

---

## 2. Arquivos

| Arquivo | Papel | Executado? |
|---|---|---|
| `5147_create_bulk_canonicalization_functions.sql` | `bulk_canonical_json()` + `bulk_request_hash()` — canonicalização única da família Bulk | **NÃO** |
| `5148_create_bulk_lock_operation_scope_function.sql` | `bulk_lock_operation_scope()` — ordem canônica única de locks (I9) | **NÃO** |
| `5149_create_preview_fingerprint_register_physical_cards_function.sql` | `preview_fingerprint_register_physical_cards()` — fonte única do fingerprint de B1. **Helper INTERNO, `VOLATILE`, `SECURITY INVOKER`** | **NÃO** |
| `5150_create_register_physical_cards_bulk_function.sql` | `register_physical_cards_bulk(p_request jsonb)` — a RPC | **NÃO** |
| `5822_validate_register_physical_cards_bulk.sql` | Harness fail-closed, gate 64/64 | **NÃO** |
| `CONCURRENCY-PROOF-PREVIEW-STALE.sql` | Runbook da prova externa de `PREVIEW_STALE` sob espera real de lock | **NÃO** |
| `README.md` | Este arquivo | — |

Ordem de aplicação obrigatória: **5147 → 5148 → 5149 → 5150 → 5822**.

Numeração conferida no repositório: `5147`–`5150` livres na faixa de
migrations estruturais de Collections; `5822` livre na faixa de
harnesses (`5821` é o de BULK-01).

**Nada é promovido para `database/schema/` no GATE A.**

### Nota documental — lacuna real registrada

O `FINALIZATION-01` **não tem artefato próprio no repositório**. O que
existe hoje é reflexo indireto: o `README.md` de BULK-01 e a seção
"Bulk Operations Foundation (BULK-01)" de `docs/05d`. A assinatura
`p_request jsonb`, a ordem de locks e o rótulo `I9` vieram da rodada de
modelagem, que viveu só no chat.

Isto é uma dívida documental concreta, e é exatamente o tipo de coisa
que o `CLAUDE.md` manda não deixar apenas na memória de sessão.
**Não foi corrigida aqui** porque o mandato desta rodada é a proposta
SQL de BULK-02, não documentação canônica. Fica registrada para o
closeout de BULK-02.

---

## 3. Caminho NEW — ordem literal

```
1. GUARDS estruturais (envelope + payload)     nada tocado no banco
2. request_hash canonico ....................  5147  (fonte unica)
3. CLAIM ....................................  5144
     CONFLICT -> BULK_IDEMPOTENCY_CONFLICT
     REPLAY   -> RETORNA AQUI
                 sem locks, sem fingerprint,
                 sem validacao, sem escrita
4. LOCKS ....................................  5148  (fonte unica, I9)
     INVENTORY -> COLLECTION -> STORAGE
5. RECALCULO do preview_fingerprint .........  5149
     dentro da transacao, sobre o estado
     JA PINADO pelos locks do passo 4
     divergencia -> PREVIEW_STALE
6. VALIDACAO de dominio
     lifecycle · catalogo (LISTA) · Game (LISTA)
     · elegibilidade CARD_SET (LISTA)
7. ESCRITAS set-based (2 statements)
8. complete_bulk_operation() ................  5145
```

Ordem canônica **completa** de locks:
`BULK_OPERATION → INVENTORY → COLLECTION → STORAGE`.

### Por que o fingerprint não pode ser conferido na aplicação

TOCTOU. Conferir antes da chamada deixa uma janela entre a leitura e a
transação em que o mundo muda: a operação escreveria sobre estado
diferente do conferido e o `PREVIEW_STALE` nunca dispararia. Feita
depois dos locks, a janela tem largura zero — o estado conferido é
literalmente o estado travado sobre o qual se escreve.

`G05` prova isso de forma não-circular: o fingerprint é capturado, a
Collection é **de fato** arquivada por `archive_collection()`, e a
confirmação com o fingerprint antigo falha com `PREVIEW_STALE` — **não**
com "collection is archived". Se a ordem estivesse invertida, o erro
seria o outro.

### O que entra no fingerprint (`5149`)

`inventory_id` · Collection (`updated_at`, `lifecycle_status`, `mode`,
`game_id`, `reference_kind`, `reference_card_set_id`) · Storage
(`updated_at`) · catálogo **resolvido** (`card_set_id`, `game_id` por
tupla).

`updated_at` entra porque `collection` e `storage_container` têm
trigger `BEFORE UPDATE` (`5031`, `5021`) — qualquer mutação move o
fingerprint. `reference_kind`/`reference_card_set_id` entram à parte
porque mudar o Reference não necessariamente toca a linha de
`collection`.

`quantity` **não** entra: quantidade é intenção e mora no
`request_hash`. Manter os dois conceitos separados é `D9` (`G03`).

---

## 4. D-1 — justificativa CORRIGIDA

**O argumento anterior estava errado e foi descartado.** Ele dizia que
múltiplas chamadas internas quebrariam a atomicidade. Não quebrariam:
dentro da mesma transação, tudo cairia junto no ROLLBACK.

Os motivos **reais** de B1 fazer as próprias escritas:

1. **Teto.** `add_physical_cards()` (`5012`) rejeita array com mais de
   500 elementos; `allocate_physical_cards_to_collection()` (`5046`)
   rejeita mais de 500 ids. O contrato novo de B1 é 1000 cartas
   criadas. Fatiar só para caber é contorcer o helper, não reusá-lo.
2. **`quantity`.** `add_physical_cards()` não tem multiplicidade: 1000
   cartas exigiriam 1000 elementos — que ela rejeita. A expansão teria
   de ocorrer no cliente, jogando para fora do banco a validação do
   total expandido que o contrato manda fazer antes das escritas.
3. **Performance.** O caminho de B1 é um `INSERT ... SELECT` com
   `generate_series`. Passar por dois helpers acrescenta parsing,
   revalidação e materialização de arrays intermediários, sem ganho.
4. **Preservação.** As duas RPCs antigas seguem canônicas, com teto de
   500 e todos os seus callers, **até BULK-05**. Nenhuma é alterada,
   removida ou migrada aqui. `E07` prova que continuam existindo com o
   teto 500 intacto.

---

## 5. Matriz — cláusula congelada → SQL → harness

| # | Cláusula congelada | Trecho SQL | Caso(s) |
|---|---|---|---|
| 1 | Assinatura `p_request jsonb → jsonb` | `5150` `CREATE FUNCTION public.register_physical_cards_bulk(p_request JSONB) RETURNS JSONB` | `E06` |
| 2 | Uma operação = uma transação, all-or-nothing | RPC inteira na transação do chamador; qualquer `RAISE` derruba tudo, inclusive o claim | `A01`, `A02` |
| 3 | Máximo 1000 Physical Cards criados | `5150` `c_max_total CONSTANT INT := 1000` | `A05`, `P14`, `P15` |
| 4 | Validar payload **BRUTO** antes das escritas | `5150` §1.2 `IF v_raw_count > c_max_total` | `P14` |
| 5 | Validar **TOTAL EXPANDIDO** antes das escritas | `5150` §1.6 `IF v_total_expanded > c_max_total` | `P15`, `A05` |
| 6 | `quantity >= 1` | `5150` §1.4 `trunc(...)` + `< 1` | `P10`, `P11`, `P12` |
| 7 | Rejeitar `(card_variant_id, language_id)` duplicado | `5150` §1.5 `SELECT DISTINCT (...)::uuid, (...)::uuid` | `P13` |
| 8 | Multiplicidade só por `quantity` | consequência de (7) | `A03` |
| 9 | Storage opcional | `5150` `storage_container_id` no envelope; `5148` LOCK 3 condicional | `A04`, `R02`, `R03` |
| 10 | Collection opcional | `5150` `collection_id` no envelope; `5148` LOCK 2 condicional | `A04`, `A05`, `R04`, `R05` |
| 11 | Ownership antes das escritas | `5148` `owner_user_id` / `inventory_id` DENTRO do `WHERE` | `R02`, `R03`, `R04`, `R05` |
| 12 | Game antes das escritas | `5150` §6.4 | `A06` (passa no Game, barra depois) |
| 13 | Lifecycle antes das escritas | `5150` §6.1, sobre o estado lido sob lock | `G05` |
| 14 | Elegibilidade antes das escritas | `5150` §6.5 (`REFERENCE_BASED` + `CARD_SET`) | `A06` |
| 15 | Usar os helpers canônicos de BULK-01 | `5150` §3 `claim_bulk_operation`, §8 `complete_bulk_operation` | `I01`, `S07` |
| 16 | Não redefinir `bulk_operation` / claim / complete | nenhuma das quatro Queries os altera | `S07` |
| 17 | `request_hash` = intenção canônica, independente da ordem JSON | `5147` `bulk_canonical_json` (arrays ordenados, `COLLATE "C"`) | `H01`, `H02`, `H03`, `I02` |
| 18 | `request_hash` derivado server-side | `5150` §2; a RPC não o recebe | `E06` (envelope não tem a chave), `I02` |
| 19 | `preview_fingerprint` distinto de idempotência | `5149` não usa `quantity`; `5144` não o consulta | `G03`, `I03` |
| 20 | Fingerprint recalculado DENTRO da transação, depois dos locks | `5150` §5, após §4; `5149` **`VOLATILE`** para que o recálculo pós-espera leia o estado corrente | `G05`, `E08`, runbook `CONCURRENCY-PROOF-PREVIEW-STALE` |
| 21 | Divergência → `PREVIEW_STALE` | `5150` §5 `RAISE ... 'PREVIEW_STALE: ...'` | `G05`, runbook passo 7 |
| 22 | REPLAY NÃO valida fingerprint | `5150` §3 retorna antes do §5 | `I03` |
| 23 | REPLAY devolve o resultado já comprometido | `5150` §3 `RETURN ... v_claim.result_summary` | `I03` |
| 24 | REPLAY com zero escrita | mesmo `RETURN`, antes de qualquer INSERT | `I04` |
| 25 | Mesma chave + intenção diferente falha | `5150` §3 `CONFLICT → BULK_IDEMPOTENCY_CONFLICT` | `I05` |
| 26 | Zero partial success | guards `v_created_count <> v_total_expanded` e `v_allocated_count <> v_created_count` | `A01`, `A06` |
| 27 | Inserts/mutações set-based, sem loop | `INSERT ... SELECT ... CROSS JOIN LATERAL generate_series` | `A05` (1000 cartas em 2 statements) |
| 28 | `add_physical_cards()` permanece; sem migrar callers | nenhuma referência a ela em `5147`–`5150` | `E07` |
| 29 | I9 — fonte única de ordem de locks | `5148`, chamada por `5150` §4 | `L01`, `L02` |
| 30 | IDs inválidos/inexistentes com LISTA | `5150` §1.3, §6.2, §6.3, §6.4, §6.5 | `P09`, `R06`, `A06` |
| 31 | Segurança nos quatro papéis | `5150`: `REVOKE ... FROM PUBLIC, anon, service_role` + `GRANT ... TO authenticated`. `5147`/`5148`/**`5149`**: revogados dos quatro | `S01`–`S06` |
| 32 | `bulk_operation` sem caminho de acesso direto | inalterado desde BULK-01 | `S08` (42501 em runtime) |

---

## 6. Harness `5822` v2.1 — gate **64 / 64 / 0 FAIL / 0 NOT PROVEN**

| Grupo | Cobertura | Casos |
|---|---|---|
| `X` | contabilidade | 2 — baseline das **8** tabelas antes de escrever; prova de que escreveu |
| `F` | fixtures pelas RPCs canônicas | 2 |
| `E` | estrutural | 8 — assinatura congelada, preservação de `5012`/`5046`, `5149` como `SECURITY INVOKER` (`E04`) e **`VOLATILE` (`E08`)** |
| `S` | **segurança** | 8 — os quatro papéis em `5150`, `5149` sem execute para nenhum deles, helpers novos e antigos, e `42501` em runtime |
| `H` | **canonicalização** | 5 — ordem de array, ordem de chaves, `1.50 = 1.5`, `operation_type`, sanidade negativa |
| `L` | **ordem de locks (I9)** | 2 — ordem na fonte única; B1 sem `FOR UPDATE` próprio |
| `P` | **contrato de payload** | 15 — envelope, `["x"]`, UUID inválido com lista, `quantity` 0/negativa/fracionária, duplicidade com variação de caixa, bruto 1001, expandido 1001 com bruto 2 |
| `R` | relacional / não-enumeração | 6 — sem auth, Storage alheio × inexistente (mesma mensagem), Collection inexistente × de terceiro (mesma mensagem), `card_variant_id` inexistente com lista |
| `G` | **fingerprint / PREVIEW_STALE** | 5 — determinismo, ordem, `quantity`, mudança real do estado, `PREVIEW_STALE` antes do lifecycle |
| `A` | **atomicidade** | 6 — falha não escreve, falha não consome a chave, `3+2=5`, Storage+Collection nas 5, **expandido exatamente 1000 ACEITO**, elegibilidade `CARD_SET` com `cv_other_set` |
| `I` | **idempotência** | 5 — CREATED, REPLAY com JSON reordenado e UUID em outra caixa, REPLAY idêntico, REPLAY zero-write, CONFLICT |

### Protocolo de três chamadas

1. **CALL 1** — do `BEGIN;` ao `SELECT` final, inclusive.
2. **CALL 2** — `ROLLBACK;`.
3. **CALL 3** — postcheck **baseline-relativo**, sobre **8** tabelas:

```sql
SELECT (SELECT count(*) FROM public.bulk_operation)                 AS bulk_operation,
       (SELECT count(*) FROM public.physical_card)                  AS physical_card,
       (SELECT count(*) FROM public.collection_allocation)          AS collection_allocation,
       (SELECT count(*) FROM public.collection)                     AS collection,
       (SELECT count(*) FROM public.collection_reference)           AS collection_reference,
       (SELECT count(*) FROM public.collection_card_set_reference)  AS collection_card_set_reference,
       (SELECT count(*) FROM public.storage_container)              AS storage_container,
       (SELECT count(*) FROM public.inventory)                      AS inventory;
```

O critério **não** é "tudo zero" — é igualdade com a coluna `baseline`
do relatório da CALL 1, que traz exatamente estas oito contagens
medidas antes da primeira escrita. O harness funciona com o banco já
povoado.

São **oito, e não seis** (correção da REVISION-02): a fixture `col_ref`
é criada por `create_reference_based_card_set_collection()`, que
escreve também em `collection_reference` e
`collection_card_set_reference`. Com seis, o postcheck seria cego a
resíduo nessas duas.

### Concorrência — posição explícita

`K01`/`K02`/`K03` de BULK-01 **não** são repetidos: cobriram a
serialização de `claim_bulk_operation()`, que B1 apenas consome.

E **não se afirma que B1 não tem resource locks novos** — ele tem:
`5148` adquire `FOR UPDATE` em `inventory`, `collection` e
`storage_container`. É por isso que a ordem virou uma implementação
única (I9), provada por `L01`/`L02`.

**Existe agora UM blocker concreto novo**, e ele ganhou roteiro
próprio: `CONCURRENCY-PROOF-PREVIEW-STALE.sql`. Quando B espera no
`FOR UPDATE` da Collection e A comita a alteração, o recálculo do
fingerprint tem de enxergar o estado NOVO e devolver `PREVIEW_STALE`.
É a prova de correção do `VOLATILE` de `5149` — com `STABLE`, B
escreveria sobre um mundo já mudado, silenciosamente.

| Passo | Sessão | Ação |
|---|---|---|
| 0–2 | ADMIN | pré-condições, role temporária `bulk_preview_probe`, fixtures, **F0** |
| 3 | **A** (psql persistente) | `archive_collection()` — transação ABERTA, segura o lock |
| 4 | **B** (psql persistente) | `register_physical_cards_bulk()` com F0 — **bloqueia** |
| 5 | OBS (SQL Editor, one-shot) | `pg_blocking_pids(B) = [A]`, `wait_event = transactionid` |
| 6 | A | `COMMIT` |
| 7 | B | **obrigatório `PREVIEW_STALE`** |
| 9 | B | contraprova com F1: `CREATED`, 2 cartas |
| 10–12 | ADMIN | resíduo da chave de B = 0, cleanup, postcheck |

Rejeitado explicitamente no passo 7: `collection is archived`
(ordem invertida) e sucesso (`STABLE` lendo estado velho). A
contraprova do passo 9 existe para que um `PREVIEW_STALE` que
dispare SEMPRE não passe por prova.

---

## 7. Ordem de execução — CUMPRIDA

| # | Passo | Estado |
|---|---|---|
| 1 | Aplicar `5147` → `5148` → `5149` → `5150` | **FEITO** — ledger em §0-A |
| 2 | Postcheck estrutural (rodapé de `5150`) | **PASS** |
| 3 | Harness `5822`, gate `64/64/0/0` + postcheck baseline-relativo das 8 tabelas | **PASS** (após `-HARNESS-CORRECTION-01`) |
| 4 | Runbook `CONCURRENCY-PROOF-PREVIEW-STALE.sql` — duas sessões `psql` persistentes + observador one-shot | **PASS** |
| 5 | Promoção para `database/schema/` | **FEITO** — `-GATE-B-01`, equivalência por SHA-256 |
| 6 | Reconciliação documental canônica, incluindo a lacuna do `FINALIZATION-01` (§2) | **FEITO** — `-DOCUMENTATION-CLOSEOUT-01`; `docs/05d` revisão `1.23` é a fonte durável do contrato congelado |
| 7 | Proposta de commit | **FEITO** — entregue no bundle PRECOMMIT do closeout |

Frente **fechada e documentada**. O commit em si depende da autorização
explícita de Fabrício — nenhum `git add`, `commit` ou `push` foi feito.
