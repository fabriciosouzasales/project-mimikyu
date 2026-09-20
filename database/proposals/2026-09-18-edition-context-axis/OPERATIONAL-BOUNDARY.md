# FRONTEIRA OPERACIONAL × HISTÓRICA — definição formal

**`OPERATIONAL-BOUNDARY-CORRECTION-01`.** Esta página é a autoridade sobre o
que é "row operacional". Qualquer artefato que contradiga esta definição é bug.

---

## O defeito

O predicado anterior era:

```
validation_status = 'VALID' AND persistence_status = 'PENDING'
```

e a `2833` afirmava que ele *"não atinge nenhuma combinação terminal"*.
**A afirmação era falsa.** Medido no LIVE:

| Recorte | Qtd |
|---|---:|
| `VALID` total | 24.372 |
| `VALID` + `persistence = PENDING` | **415** |
| └ job `CANCELLED` + decision `SKIPPED` | 414 |
| └ job `CANCELLED` + decision `PENDING` | 1 |
| Jobs `STAGED`/`CONFIRMING` · `PENDING` · `NEEDS_REVIEW` | 1.642 |
| Jobs `STAGED`/`CONFIRMING` · `PENDING` · **`VALID`** | **0** |

**As 415 são todas de jobs `CANCELLED`.** O predicado atingia 415 rows
históricas e **zero** rows operacionais — errava nas duas direções.

A causa raiz é conceitual: `persistence_status` descreve a **row**;
"operacional" é uma propriedade do **job**. Uma row `PENDING` num job
cancelado não é backlog — é um trabalho abandonado que ninguém vai retomar.

---

## Definição formal, derivada do código canônico

`database/schema/2145_…` — não inferido, lido:

| Linha | Contrato |
|---|---|
| **270** | `IF v_job.status NOT IN ('STAGED','CONFIRMING') THEN RAISE … INVALID_STATUS` |
| **286 · 307** | conjunto elegível: `persistence_status = 'PENDING' AND decision_status IN ('APPROVED','SKIPPED')` |
| **314** | `decision_status = 'SKIPPED'` ⇒ `persistence_status := 'UNCHANGED'`, `CONTINUE` — **nenhuma escrita** |
| **324** | `decision_status = 'APPROVED'` e `validation_status <> 'VALID'` ⇒ `NEEDS_REVIEW_CANNOT_BE_CONFIRMED` |

### Os três conjuntos

```
OPERACIONAL   ≡  job.status ∈ ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
                 AND row.persistence_status = 'PENDING'

CONFIRMÁVEL   ≡  job.status ∈ ('STAGED','CONFIRMING')
                 AND row.persistence_status  = 'PENDING'
                 AND row.decision_status     = 'APPROVED'
                 AND row.validation_status   = 'VALID'

HISTÓRICO     ≡  tudo o mais — inclusive job CANCELLED/COMPLETED/
                 COMPLETED_WITH_ERRORS/FAILED com row PENDING
```

`CONFIRMÁVEL ⊂ OPERACIONAL`. O guard protege **OPERACIONAL** (barreira
antecipada), não `CONFIRMÁVEL` — barrar só na confirmação seria tarde:
a row já teria sido marcada VALID e exibida ao revisor como pronta.

### Predicado do guard

```
job.status ∈ ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
AND row.persistence_status = 'PENDING'
AND row.validation_status  = 'VALID'
  →  edition_context_profile_id PRESENTE
```

`RECEIVED`/`PROCESSING` entram porque uma row pode nascer VALID durante o
processamento; deixá-los de fora criaria uma janela em que o estado proibido
é gravável e só seria detectado depois.

---

## CANCELLED é terminal

`job.status = 'CANCELLED'` é **histórico terminal**, sem exceção.

- A linha 270 de `2145` recusa confirmar qualquer job cancelado. As 415 rows
  **não podem** virar Card Variant por nenhum caminho existente.
- 414 delas têm `decision_status = 'SKIPPED'` — decisão editorial de não
  persistir, tomada e registrada.
- A única com `decision = 'PENDING'` nunca foi decidida e nunca será: o job
  que a continha foi cancelado.

**Consequências normativas:**

| Proibido | Por quê |
|---|---|
| exigir Edition Context das 415 | não são backlog |
| reativá-las | reabrir job cancelado é decisão editorial, não efeito colateral de migração |
| alterar `decision`/`persistence`/`validation` | reescreveria histórico |
| gravar `JSON null` nelas | placeholder estrutural — o defeito que a `BACKFILL-SEMANTICS-CORRECTION-01` eliminou |

> **Correção explícita.** A `2833` v1.0 afirmava que o predicado *"não atinge
> terminal"*. Atingia 415. A afirmação foi removida e substituída por uma
> prova que **mede** a interseção e exige que ela seja zero.

---

## Matriz de state machine

`2833` v2.0 a produz **medindo o LIVE**, não por enumeração hipotética. Colunas:

`job_status` × `validation_status` × `decision_status` × `persistence_status`
× `rows` × `com_chave` × `sem_chave` × **`pode_mutar`** × **`pode_confirmar`**

Regras de derivação — as duas últimas colunas são **computadas**, não digitadas:

```
pode_mutar     = job_status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
                 AND persistence_status = 'PENDING'

pode_confirmar = job_status IN ('STAGED','CONFIRMING')
                 AND persistence_status = 'PENDING'
                 AND decision_status    = 'APPROVED'
                 AND validation_status  = 'VALID'
```

Projeção esperada com a baseline atual — **evidência, não contrato**:

| job_status | validation | decision | persistence | rows | mutar | confirmar |
|---|---|---|---|---:|:---:|:---:|
| `CANCELLED` | `VALID` | `SKIPPED` | `PENDING` | 414 | ❌ | ❌ |
| `CANCELLED` | `VALID` | `PENDING` | `PENDING` | 1 | ❌ | ❌ |
| `STAGED`/`CONFIRMING` | `NEEDS_REVIEW` | `PENDING` | `PENDING` | 1.642 | ✅ | ❌ |
| `STAGED`/`CONFIRMING` | `VALID` | — | `PENDING` | **0** | ✅ | ✅ se `APPROVED` |
| terminal (`COMPLETED`…) | `VALID` | — | `INSERTED`/`UNCHANGED` | ~23.957 | ❌ | ❌ |

**OPERACIONAL = 1.642** (as `NEEDS_REVIEW` em jobs vivos).
**CONFIRMÁVEL = 0** (nenhuma está `VALID` + `APPROVED`).

Os dois números são diferentes e a distinção importa: o `2212` trabalha sobre
as **1.642**; o guard `2214` protege a transição delas para `VALID`; o
confirmável vazio é o que torna o rollout barato.

---

## Por que não `CHECK` constraint

Um `CHECK` de `catalog_variant_import_row` só enxerga colunas da própria row.
`job.status` vive noutra tabela. As saídas possíveis eram:

| Opção | Veredito |
|---|---|
| `CHECK` row-local (`VALID + PENDING → key`) | ❌ **semanticamente falso** — atinge as 415 |
| coluna desnormalizada `job_status` na row | ❌ duplica fonte de verdade; exige sincronização |
| `CHECK` com função `IMMUTABLE` mentindo sobre estabilidade | ❌ corrupção silenciosa — a função lê outra tabela |
| **trigger que consulta o job** | ✅ |

A proteção é em **três camadas**, nenhuma substituindo a outra:

1. **Trigger** (`2214`) — barra a transição no banco, com o job em mãos.
2. **Routing/propagation** (`2211` · `2219`) — só marca `VALID` depois que o
   eixo resolve; indeterminado permanece `NEEDS_REVIEW` com a chave ausente.
3. **Revalidação defensiva** no confirm (`2218`) — recusa `fail-closed` com
   mensagem de negócio, mesmo que 1 e 2 falhassem. `2145` já faz isso para
   `validation_status` na linha 324; o padrão é estendido ao terceiro eixo.

---

## Os 7 casos do guard

| # | Cenário | Esperado |
|---|---|---|
| 1 | `STAGED` · `PENDING` · `NEEDS_REVIEW` · chave ausente | **permitido** |
| 2 | `STAGED` · `PENDING` · tentativa de `VALID` · chave ausente | **BLOQUEADO** |
| 3 | `STAGED` · `PENDING` · `VALID` · `JSON null` ou UUID | **permitido** |
| 4 | `CONFIRMING` · row elegível · chave ausente | **confirmação recusada** (fail-closed) |
| 5 | `COMPLETED`/`COMPLETED_WITH_ERRORS` terminal · chave ausente | **permitido** |
| 6 | `CANCELLED` terminal · `VALID` · `PENDING` · chave ausente | **permitido** — as 415 |
| 7 | transição terminal → operacional | **nunca silenciosa** |

**Caso 7** merece nota: o guard não impede um `UPDATE` de `job.status` de
`CANCELLED` para `STAGED` — isso é um contrato do job, não da row. O que o
guard garante é que, uma vez operacional, nenhuma row daquele job pode
*permanecer ou tornar-se* `VALID` sem a chave: qualquer `UPDATE` subsequente
em `normalized_data`/`validation_status`/`persistence_status` é barrado. A
reativação, portanto, não passa em silêncio — ela para na primeira escrita.
Fechar a porta por completo exigiria um guard na própria
`catalog_variant_import_job`, e isso é escopo de outro mandato.

---

## Ausência de lockout — prova

Um risco real de guards retroativos: criar um estado do qual a row não pode
sair. Aqui é impossível, por três razões:

1. **O estado proibido não existe hoje.** `STAGED`/`CONFIRMING` + `PENDING` +
   `VALID` = **0 rows**. O guard só pode impedir que ele seja criado.
2. **Sair de `PENDING` é sempre permitido.** O predicado testa
   `NEW.persistence_status = 'PENDING'`; o confirm grava `INSERTED`,
   `UNCHANGED` ou `FAILED`, e o guard não dispara.
3. **O gatilho é estreito.** `UPDATE OF normalized_data, validation_status,
   persistence_status` — mexer em `error_detail`, `decision_status` ou
   qualquer outra coluna não aciona o guard.
