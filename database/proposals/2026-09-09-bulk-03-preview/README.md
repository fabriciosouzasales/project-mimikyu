# BULK-03 — `preview_bulk_operation`

| Campo | Valor |
|---|---|
| **Pacote** | `COLLECTIONS-BULK-03` — Preview da família Bulk |
| **Rodada** | `-MODELING-01` → `-MODELING-FINALIZATION-01` → `-GATE-A-REVISION-01` → `-GATE-A-REVISION-02` → `-EXECUTION-01` → `-GATE-A-HARNESS-CORRECTION-01` → `-GATE-B-01` → **`-DOCUMENTATION-CLOSEOUT-01`** |
| **Status** | **`EXECUTED / VALIDATED / PROMOTED / DOCUMENTED`** — `5151` aplicada (ledger `20260909024422`) e promovida para `database/schema/`; `5823` v2.2 com gate `60/60/0/0`; Δ=0 nas 9 tabelas; contrato canônico consolidado em `docs/05d-colecoes-e-usuarios.md`, revisão `1.24`. |
| **Baseline** | HEAD `07e2ba474a16f50b5f08a960debda7dec05b56e0` |
| **Depende de** | BULK-01 (`5142`–`5146`) e BULK-02 (`5147`–`5150`), todos `LIVE / PROMOVIDOS` |
| **Escopo** | Somente `REGISTER_PHYSICAL_CARDS` (B1) |
| **Data** | 2026-09-09 |

---

## 1. Arquivos

| Arquivo | Papel | Executado? |
|---|---|---|
| `5151_create_preview_bulk_operation_function.sql` | a RPC pública de Preview | **SIM** — 2026-09-09, ledger `20260909024422` |
| `5823_validate_preview_bulk_operation.sql` | harness v2.2, gate `60/60/0/0` | **SIM** — 2026-09-09, `60/60/0/0`. **NÃO promovido** |
| `README.md` | este arquivo | — · **NÃO promovido** |

**Numeração**: `5151` **deixou de estar livre** — é agora o maior número em `database/schema/`, promovido em `-GATE-B-01`. `5823` permanece livre em `database/schema/` por política: harness não é promovido.

**Nada em `5147`–`5150` é alterado.** BULK-03 apenas *consome* `5149`, que permanece interna, com `EXECUTE` revogado dos quatro papéis.

---

## 2. Decisões desta rodada

| # | Decisão | Onde vive |
|---|---|---|
| D-1 | Namespace: `B1` = `REGISTER_PHYSICAL_CARDS`, `B2` = `REGISTER_CARD_SET`. `B3`/`B4`/`B5` **não** são operações — são riscos históricos de BULK-01 e não voltam a ser usados como nomes de operação. | este README |
| D-2 | RPC única `preview_bulk_operation(p_request jsonb) → jsonb`, contrato reutilizável da família; **só B1 implementado**. | `5151` |
| D-3 | `REGISTER_CARD_SET` é reconhecido como do vocabulário e recusado com mensagem própria de **não suportado nesta versão** — nunca como "inválido". | `5151` §1.1 · `5823` `V01`/`V02` |
| D-4 | Teto `1000` **literal**, duplicado de `5150`. Equivalência provada **comportamentalmente**, nunca por parsing de source. | `5151` · `5823` grupo `T` |
| D-5 | Contrato binário: `ok=true` ⇒ fingerprint preenchido e `issues=[]`; `ok=false` ⇒ fingerprint **JSON `null`** e ≥1 `BLOCKING`. | `5151` §5 · `5823` grupo `K`/`I` |
| D-6 | `SECURITY DEFINER`, `VOLATILE`, `search_path=''`, `EXECUTE` só para `authenticated`. | `5151` · `5823` grupos `E`/`S` |
| D-7 | Sem locks, sem `idempotency_key`, sem `request_hash` exposto. | `5151` · `5823` `E07`/`G03` |
| D-8 | Performance **observacional** com **1000 Card Variants REAIS e distintos**, `quantity = 1`. Se o catálogo não tiver 1000, o caso FALHA — a carga jamais é reduzida em silêncio. Sem índice novo, sem benchmark dedicado, sem SLO. | `5823` grupo `D` |

### Delta em relação à modelagem aprovada — declarado

A modelagem listava oito `issues[].code`. A implementação tem **nove**: foi acrescentado **`INVENTORY_NOT_FOUND`**.

Não é escopo novo, é necessidade estrutural: `5148` aborta com `inventory not found for current user`, e `5149` faria o mesmo. Sem esse code, um usuário sem `inventory` receberia uma exceção crua de dentro de `5149` em vez de um `issues[]` — quebrando o próprio contrato `ok=false` que D-5 estabelece. A verificação de Storage também depende de `v_inventory`, e por isso é suprimida quando ele não existe (evita ruído redundante).

**Aprovado na auditoria de `-GATE-A-REVISION-01` e agora coberto por caso próprio (`I11`).** Os nove codes têm, cada um, prova dedicada.

### Correção de `-GATE-A-REVISION-02` — blocker no harness, não no produto

`5151` permanece **aprovada e intocada**. Dois defeitos eram do `5823`:

1. **`F03` passava `NULL` como `p_default_storage_container_id`.** O guard de `create_collection()` (`5034`) é um `NOT EXISTS` **incondicional**: com `NULL`, `sc.id = NULL` nunca é verdadeiro, o `NOT EXISTS` dispara e a RPC aborta com `default_storage_container_id does not belong to caller inventory`. A fixture teria derrubado o harness **antes do gate**. Corrigido para usar `sc1`, o Storage de `u1` já criado em `F02`. O `GAME_MISMATCH` que `I10` prova não muda: continua sendo entre a Collection no Game sintético e a Card Variant real do Game Pokémon — Storage não entra no cálculo de Game.

2. **Código de Game literal fixo.** `public.game.code` tem `uq_game_code`; um literal faria a segunda execução colidir com qualquer resíduo da primeira. Agora é `ZZTEST_BULK03_<32 hex maiúsculos>` — 46 chars (limite 50), no formato de `ck_game_code_format`. `F03` assere comprimento e formato.

### Registro de execução — `-EXECUTION-01` e `-GATE-A-HARNESS-CORRECTION-01` (2026-09-09)

**Primeira execução (`5823` v2.1): `60 TOTAL / 59 PASS / 1 FAIL / 0 NOT PROVEN`.**

O único FAIL foi `E06`, e era **defeito exclusivo do harness**:

- A v2.1 exigia `pg_get_function_identity_arguments(...) = 'jsonb'`. Essa função devolve os **nomes** dos parâmetros junto com os tipos quando eles têm nome — ou seja, `p_request jsonb`. A comparação nunca casaria.
- **`5151` estava e permaneceu correta e intocada.** Na mesma rodada, o postcheck estrutural externo mediu independentemente: 1 sobrecarga, `p_request jsonb`, retorno `jsonb`, `SECURITY DEFINER`, `VOLATILE`, owner `postgres`, `search_path` vazio, `authenticated` com EXECUTE e os outros três papéis sem.
- **Registro honesto:** o idioma correto já existia no repositório — é literalmente o `E06` do `5822` (BULK-02), que compara com `'p_request jsonb'`. Não foi reaproveitado na primeira escrita deste harness. Mesma classe do defeito de `search_path` em BULK-02.

**`5823` v2.2** corrigiu duas coisas, ambas só no harness:

1. `E06` passa a exigir 1 sobrecarga **+** `identity arguments = 'p_request jsonb'` **+** `format_type(prorettype) = 'jsonb'`.
2. O relatório final imprime `got` também nos **PASS do grupo `D`**. Sem isso, `D03` — um caso observacional — nunca entregava a medição, porque o relatório só mostrava `got` em falhas. Um caso observacional que só mostra o número quando falha não entrega medição nenhuma.

Nenhum caso foi adicionado ou removido; a lógica do gate não mudou. **Segunda execução: `60/60/0/0`, `GATE_OK = t`.**

**Medição observacional (`D03`): `338.43 ms`** para o Preview de 1000 `card_variant_id` reais e distintos, `quantity = 1`, sem Collection e sem Storage — 1000 resoluções reais de catálogo. Sem SLO nesta rodada.

### Promoção canônica — `-GATE-B-01` (2026-09-09)

`5151` promovida para `database/schema/5151_create_preview_bulk_operation_function.sql`.

| Fonte | SHA-256 do corpo executável (`BEGIN;`…`COMMIT;`) |
|---|---|
| proposal `5151` | `779801ddc1df8e2820e6b7b4cc13914da992e49bfa819894bdc918b5aeb3d049` |
| schema `5151` | `779801ddc1df8e2820e6b7b4cc13914da992e49bfa819894bdc918b5aeb3d049` |
| corpo aplicado (ledger `20260909024422`) | `779801ddc1df8e2820e6b7b4cc13914da992e49bfa819894bdc918b5aeb3d049` |

**Os três idênticos.** Entre as duas cópias mudaram **apenas as duas linhas de cabeçalho** de status — `Status......:` e `STATUS DESTA QUERY:` — pela convenção canônica auditada em `5142`–`5150`. O hash acima foi medido no arquivo **antes** dessa edição e reconferido depois nas duas cópias: idêntico, o que prova que a edição não tocou região executável.

**NÃO promovidos**, por política canônica — permanecem só aqui, como evidência histórica: `5823` (harness) e este `README.md`.

---

## 3. Contrato

### Request — chaves FECHADAS

```jsonc
{
  "operation_type":       "REGISTER_PHYSICAL_CARDS",
  "items":                [ { "card_variant_id", "language_id", "quantity" } ],
  "collection_id":        "<uuid>" | null,
  "storage_container_id": "<uuid>" | null
}
```

Sem `idempotency_key` — Preview não faz claim. A assimetria com `5150` é deliberada e testada (`G03`).

### Response

```jsonc
{
  "operation_type": "REGISTER_PHYSICAL_CARDS",
  "ok": true | false,
  "preview_fingerprint": "<text>" | null,
  "summary": { "distinct_items", "total_quantity", "will_create_count",
               "will_allocate_count", "collection_id", "storage_container_id" },
  "issues": [ { "code", "severity", "message", "offenders": [...] } ]
}
```

`request_hash` **não** é devolvido: `5150` o deriva server-side (D-2 de BULK-02, que fechou o risco `B4`). Expô-lo aqui só convidaria o cliente a mandá-lo de volta.

### Vocabulário de `issues[].code`

`DUPLICATE_ITEM` · `INVENTORY_NOT_FOUND` · `COLLECTION_NOT_ACCESSIBLE` · `COLLECTION_ARCHIVED` · `STORAGE_NOT_ACCESSIBLE` · `CARD_VARIANT_NOT_FOUND` · `LANGUAGE_NOT_FOUND` · `GAME_MISMATCH` · `NOT_ELIGIBLE_FOR_REFERENCE`

`severity` é `BLOCKING` em todos. `WARNING` não foi inventado sem caso de uso.

---

## 4. Exceção versus `issues[]`

| Classe | Tratamento | Por quê |
|---|---|---|
| **Bug de cliente** — envelope malformado, chave desconhecida, tipo errado, UUID inválido, `quantity` não-inteira, teto estourado | **exceção**, `ERRCODE` idêntico ao de `5150` | não há o que o usuário corrija na tela |
| **Situação do usuário** — carta inexistente, Collection arquivada, Game divergente, duplicata, recurso inacessível | **`issues[]`** com `ok=false` | precisa ver **tudo** de uma vez; estourar no primeiro problema faz quem tem 300 cartas descobrir um erro por round-trip |

Assimetria consciente com `5150`: lá, duplicata é guard estrutural que aborta; aqui é `issues[]`. Não há contradição — Preview é consultivo e `5150` continua abortando sob lock. **`ok=true` não é autorização.**

---

## 5. Por que `SECURITY DEFINER` — o achado que decide a assinatura

`5149` lê `card_variant → card → card_set → expansion` e `language`. O Catálogo Editorial (`ADR-022`) fecha essas tabelas ao `authenticated` comum: `public.card` tem RLS habilitado **sem nenhuma policy**; `card_variant` tem só `catalog_admin_select`, gated por `is_admin()`. Um `authenticated` comum lê **zero** linhas — registrado em `ADR-030` e no cabeçalho de `5070`, que teve exatamente este bug como `SECURITY INVOKER` e foi corrigido para `DEFINER`.

Se `5151` fosse `INVOKER`, seu `catalog` viria vazio para todo usuário real, enquanto `5150` (`DEFINER` como `postgres`) o montaria cheio. Os fingerprints jamais bateriam e **100% das execuções falhariam com `PREVIEW_STALE`**.

`DEFINER` troca o **privilégio**, não a **identidade**: `auth.uid()` segue devolvendo o usuário real, então ownership e não-enumeração continuam corretos.

### O grupo `P` do harness existe por causa disso — e por isso troca de papel

Rodando como `postgres` (o executor normal), uma `5151` **INVOKER passaria no teste** e quebraria em produção. Um teste que passa tanto no código certo quanto no errado não prova nada. Por isso `P` usa `SET LOCAL ROLE authenticated` de verdade — a única parte do harness que faz isso, contrariando conscientemente a escolha do grupo `C` de `5821`.

Consequência operacional herdada de `5808`: com o papel trocado, não se lê `pg_temp` nem tabela temporária. Todas as fixtures são capturadas antes; todo `_rec` acontece depois do `RESET ROLE`.

---

## 6. Não-enumeração

`5148`/`5149`/`5150` colapsam deliberadamente "não existe" e "é de terceiro" na mesma mensagem. Respostas estruturadas são mais informativas que exceções — e é aí que mora o risco de regressão.

`COLLECTION_NOT_ACCESSIBLE` e `STORAGE_NOT_ACCESSIBLE` cobrem os dois casos com **mensagem byte-idêntica** e mesma contagem de issues.

O grupo `N` prova os três ângulos para **cada um dos dois recursos** — porque um contador diferente também seria canal lateral, e porque Storage é tão enumerável quanto Collection:

| Ângulo | Collection | Storage |
|---|---|---|
| mesmo `code` | `N01` | `N04` |
| mensagem byte-idêntica | `N02` | `N05` |
| mesma contagem de issues | `N03` | `N06` |

`offenders` traz apenas ids que o próprio chamador enviou. Não há vazamento: ele já os conhecia.

---

## 7. Teto de cardinalidade

`c_max_total = 1000`, literal, igual ao de `5150`. `5150` está `CLOSED / PROMOTED` e **não é reaberto** nesta frente, então não há helper compartilhado.

A equivalência é **comportamental**, no grupo `T`:

| Caso | Prova |
|---|---|
| `T01` | 1000 itens brutos **passam** o guard de cardinalidade — a recusa vem de `issues`, nunca do teto |
| `T02` | 1001 itens brutos são **rejeitados** por exceção |
| `T03` | total expandido de exatamente 1000 é **aceito**, com `will_create_count = 1000` |
| `T04` | total expandido de 1001 é **rejeitado** |

Do lado da execução, os mesmos limites já estão provados em `5822` (grupos `P` e `A`) — não são reexecutados aqui. **Não se parseia o source de `5150`** para comparar a constante: o que importa é o comportamento na fronteira.

**Registro honesto:** duas fontes de verdade para o mesmo número é dívida, não virtude. A forma correta — `bulk_max_items(operation_type)` — fica para quando `5150` for tocado por outro motivo legítimo.

---

## 8. Matriz requisito → SQL → caso de teste

| # | Requisito | Onde em `5151` | Caso em `5823` |
|---|---|---|---|
| 1 | Assinatura pública única `(jsonb) → jsonb` | `CREATE FUNCTION` | `E01`, `E06` |
| 2 | `SECURITY DEFINER` (obrigatório, §5) | cláusula da função | `E02`, **`P01`**, **`P02`** |
| 3 | `VOLATILE` | cláusula da função | `E03` |
| 4 | `search_path` vazio | `SET search_path = ''` | `E04` |
| 5 | Owner `postgres` | — | `E05` |
| 6 | Preview **não escreve** (nenhuma DML), **não trava, não faz claim** | ausência por construção | `E07` (nove agulhas) |
| 7 | `EXECUTE` só para `authenticated` | `REVOKE`/`GRANT` | `S01`–`S04` |
| 8 | `PUBLIC` sem `EXECUTE` (`proacl` não-NULL) | `REVOKE ... FROM PUBLIC` | `S04` |
| 9 | `operation_type` fora do vocabulário → inválido | §1.1 | `V01` |
| 10 | `REGISTER_CARD_SET` → **não suportado nesta versão** | §1.1 | `V02` |
| 11 | `REGISTER_PHYSICAL_CARDS` → aceito | §1.1 | `V03` |
| 12 | Envelope de chaves FECHADO | §1 | `G01`, `G02`, `G04` |
| 13 | `idempotency_key` recusada (assimetria com `5150`) | §1 | `G03` |
| 14 | `items` vazio recusado | §2 | `G05` |
| 15 | Item de chaves FECHADO | §2 | `G06` |
| 16 | UUID inválido aborta com LISTA | §2 | `G07` |
| 17 | `quantity` inteira ≥ 1 | §2 | `G08`, `G09` |
| 17b | **Todo erro estrutural/vocabulário/teto tem SQLSTATE `22023`** | §1–§2 | todo `V`/`G`/`T` via `_expect_error` |
| 17c | **`auth.uid()` ausente → SQLSTATE `28000`**, distinto de `22023` | §0 | `G10` |
| 18 | Teto 1000 bruto | §2 | `T01`, `T02` |
| 19 | Teto 1000 expandido | §2 | `T03`, `T04` |
| 20 | `ok=true` ⇒ fingerprint preenchido | §5 | `K01` |
| 21 | `ok=true` ⇒ `issues=[]` | §5 | `K02` |
| 22 | `summary` correto | §4 | `K03`, `K04`, `I09` |
| 23 | `ok=false` ⇒ fingerprint **`null`** | §5 | `I02`, `I03`, `I04`, `I05`, `I06`, `I07` |
| 24 | Duplicidade **semântica** `(uuid, uuid)` | §3.1 | `I01` |
| 25 | `card_variant_id` inexistente com LISTA | §3.5 | `I03` |
| 26 | `language_id` inexistente com LISTA | §3.6 | `I04` |
| 27 | Collection `ARCHIVED` | §3.3 | `I05` |
| 28 | Elegibilidade de Reference | §3.8 | `I06` |
| 29 | Storage inacessível | §3.4 | `I07` |
| 30 | Todos os impedimentos **de uma vez** | §3 (sem `RETURN` precoce) | `I08` |
| 31 | Não-enumeração de Collection | §3.3 | `N01`, `N02`, `N03` |
| 31b | Não-enumeração de **Storage** | §3.4 | `N04`, `N05`, `N06` |
| 32 | Fingerprint Preview ≡ execução, como `authenticated` real | §5 + `5149` | **`P01`, `P02`, `P03`** |
| 33 | Performance observacional com **1000 Card Variants reais** (FAIL se o catálogo não tiver 1000) | — | `D01`, `D02`, `D03` |
| 34 | Zero resíduo baseline-relativo (**9** tabelas, incl. `game`) | — | `X01`, `X02` + postcheck externo |
| 35 | Fixtures pelas RPCs canônicas | — | `F01`, `F02` |
| 35b | Game sintético de código **único por execução** criado na transação, **sem catálogo sintético**, com o Storage `sc1` exigido por `5034` | — | `F03` |
| 36 | `GAME_MISMATCH` | §3.7 | **`I10`** |
| 37 | `INVENTORY_NOT_FOUND` | §3.2 | **`I11`** |
| 38 | `P03` registra FAIL legível se `5150` lançar exceção, em vez de abortar o harness | — | `P03` |

---

## 9. Gate e grupos do harness

**`60 TOTAL / 60 PASS / 0 FAIL / 0 NOT PROVEN`.** Um caso que não consegue rodar é FAIL, não ausência.

| Grupo | n | Cobertura |
|---|---|---|
| `X` | 2 | baseline das **9** tabelas; prova de que o harness escreveu de fato |
| `F` | 3 | fixtures via RPCs canônicas + Game sintético `ZZTEST_BULK03_<único>` |
| `E` | 7 | DEFINER, VOLATILE, `search_path`, owner, sobrecarga única, ausência de **toda DML** e de lock/claim |
| `S` | 4 | ACL nos quatro papéis |
| `V` | 3 | as três situações de `operation_type` |
| `G` | 10 | guards estruturais → exceção, **com SQLSTATE verificado**; `G10` prova `28000` |
| `T` | 4 | teto 1000/1001, bruto e expandido |
| `K` | 4 | contrato `ok=true` |
| `I` | 11 | contrato `ok=false`, um por code (inclui `GAME_MISMATCH` e `INVENTORY_NOT_FOUND`) + multiplicidade |
| `N` | 6 | não-enumeração de Collection **e de Storage** |
| `P` | 3 | fingerprint Preview × execução, como `authenticated` real |
| `D` | 3 | performance observacional com **1000 Card Variants reais** |

### Transporte

Foi medido em BULK-02 que o canal MCP `execute_sql` **não preserva sessão nem transação entre chamadas**. O harness roda em **chamada única** e entrega o relatório por `RAISE EXCEPTION`, que aborta a transação e garante o ROLLBACK **por construção**. Nenhum caso de teste é alterado por isso: o gate avaliado é o mesmo `count(*) = 60 AND fail = 0`. Numa sessão `psql` real, `BEGIN; \i 5823...; ROLLBACK;` produz resultado idêntico sem a exceção final.

### Zero resíduo

Baseline-relativo sobre as **nove** tabelas — `bulk_operation`, `physical_card`, `collection_allocation`, `collection`, `collection_reference`, `collection_card_set_reference`, `storage_container`, `inventory` e **`game`**. `public.game` entrou na v2.0 porque a fixture de `I10` cria o Game sintético; toda tabela que o harness toca precisa estar no baseline, senão o postcheck mediria menos do que o harness escreveu.

O critério **não** é "tudo zero": é igualdade com o estado anterior. A verificação definitiva é **externa**, em chamada separada após o rollback (query no rodapé do `5823`), e inclui um complemento específico — `SELECT count(*) FROM public.game WHERE code LIKE 'ZZTEST_BULK03_%'` — porque `game` é catálogo global e é a única linha que este harness cria fora do escopo de um Owner. O `LIKE` casa **todas** as execuções, não só a última, já que o código é único por execução.

---

## 10. Riscos

| # | Risco | Sev. | Tratamento |
|---|---|---|---|
| `V1` | `5151` como `INVOKER` → `PREVIEW_STALE` universal | **Alta** | `E02` + `P01`/`P02` com `SET ROLE authenticated` real |
| `V2` | Teto divergir de `5150` | **Alta** | grupo `T`, comportamental nas quatro fronteiras |
| `V3` | `issues[]` virar oráculo de enumeração | **Alta** | grupo `N` (code, mensagem e contagem) |
| `V4` | Fingerprint de Preview reprovado chegar ao cliente | **Alta** | D-5; `I02`–`I07` exigem `jsonb_typeof = 'null'` |
| `V5` | Cliente tratar `ok=true` como autorização | Média | documentado em `5151` e aqui; `5150` revalida tudo sob lock |
| `V6` | Preview sem rate limit chamado em loop | Média | teto + `authenticated` + escopo por Owner; **rate limiting é não-objetivo declarado** desta frente |
| ~~`V7`~~ | ~~`GAME_MISMATCH` sem caso dedicado~~ | — | **FECHADO** em `-GATE-A-REVISION-01`: `I10`, com Game sintético de código único |
| `V8` | Duplicação da constante 1000 | Baixa | dívida registrada em §7; helper único quando `5150` for tocado |

---

## 11. Pendências conhecidas — declaradas, não escondidas

As duas lacunas declaradas na v1.0 do harness — `GAME_MISMATCH` e `INVENTORY_NOT_FOUND` sem caso dedicado — foram **fechadas** em `-GATE-A-REVISION-01` por `I10` e `I11`. Todos os nove `issues[].code` têm prova própria.

Permanecem, declaradas:

1. **Sem prova de concorrência.** Ao contrário de BULK-02, aqui a afirmação se sustenta: Preview não toma lock, não escreve e não serializa nada. Não há blocker concreto a provar, e nenhum runbook é criado.

2. **Sem benchmark dedicado nem índice novo.** Os joins são todos por PK; o precedente medido (`5070`/`5071`) ficou < 30 ms. `D03` registra o tempo real de 1000 resoluções de catálogo para leitura humana, sem SLO.

3. **Constante `1000` duplicada** entre `5151` e `5150` — dívida registrada em §7, com equivalência garantida comportamentalmente pelo grupo `T`. O helper único fica para quando `5150` for tocado por outro motivo legítimo.

4. **`public.game` passa a ser escrita pelo harness.** É a única tabela de catálogo global que ele toca, e a única linha criada fora do escopo de um Owner. Mitigado por: baseline de 9 tabelas, `X02` provando a escrita, código **único por execução** (`uq_game_code` nunca colide entre rodadas) e um complemento explícito de postcheck (`code LIKE 'ZZTEST_BULK03_%'`) no rodapé do `5823`.

---

## 12. Ordem de execução proposta

| # | Passo | Estado |
|---|---|---|
| 1 | Aplicar `5151` | **FEITO** — ledger `20260909024422` |
| 2 | Postcheck estrutural (DEFINER, VOLATILE, `search_path`, ACL, sobrecarga única) | **FEITO** — 7/7 PASS |
| 3 | Executar `5823` v2.2 em chamada única — gate `60/60/0/0` | **FEITO** — `-GATE-A-HARNESS-CORRECTION-01` |
| 4 | Postcheck externo baseline-relativo das **9** tabelas, Δ = 0, incluindo `game WHERE code LIKE 'ZZTEST_BULK03_%'` = 0 | **FEITO** — Δ=0 e complementos=0 nas duas execuções |
| 5 | Promoção de `5151` para `database/schema/` | **FEITO** — `-GATE-B-01`, corpo executável byte-idêntico |
| 6 | Reconciliação documental (`05d`, ROADMAP, README, INDEX, log, handoff) | **FEITO** — `-DOCUMENTATION-CLOSEOUT-01`; `05d` rev. `1.24` é a fonte durável do contrato |
| 7 | Proposta de commit | **FEITO** — entregue no bundle PRECOMMIT do closeout |

Frente **fechada e documentada**. `5151` aplicada, viva e promovida; `5823` v2.2 em `60/60/0/0`; contrato canônico em `docs/05d`, revisão `1.24`. O commit em si depende da autorização explícita de Fabrício — nenhum `git add`, `commit` ou `push` foi feito.
