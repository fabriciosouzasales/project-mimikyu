# Staging — Fechamento técnico do STEP 2, CARD SETS

| Campo | Valor |
|---|---|
| **Rodada** | `CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-CORRECTION-01` |
| **Data** | 2026-09-09 |
| **Status** | **CONFIRMADO EXECUTADO / VALIDADO** — 2026-09-10, em `...-FINALIZATION-IMPLEMENTATION-02` |
| **Ledger** | `2161` → `20260910025017` · `2162` → `20260910025112` |
| **Gate** | `921` = **14 PASS / 0 FAIL** |
| **Escopo** | Duas operações independentes: (A) reconciliação física do índice PROMO; (B) normalização de `release_order` dos 199 Card Sets Pokémon |

---

## Estado que motiva esta proposta (medido em 2026-09-09)

- 199 Card Sets Pokémon: 46 originais + 71 do Lote A + 82 do Lote B.
- 151 com logo, 48 sem — condição normal, fechada em rodada própria.
- 153 Card Sets ainda com `release_order >= 1000` (faixa temporária do bootstrap).
- Índice `uq_card_set_expansion_promo` **ausente** no banco físico.

---

## Arquivos

| Ordem | Arquivo | O que faz | Situação atual |
|---|---|---|---|
| 1 | `2161_create_card_set_expansion_promo_unique_index.sql` | Cria o índice único parcial de PROMO | **PROMOVIDA** para `database/migrations/` (v1.1) |
| 2 | `2162_normalize_card_set_release_order.sql` | Renumera `release_order` dos 199 Sets Pokémon | Permanece aqui — one-shot de dados, só ledger |
| 3 | `921_validate_card_set_finalization.sql` | Valida as duas, read-only, 14 verificações | Permanece aqui como evidência histórica |

### Registro de honestidade — `2161` abortou na primeira tentativa

Em `IMPLEMENTATION-01`, `2161` v1.0 **abortou no pós-check**, com rollback
total e zero resíduo (índice não criado, 3 índices, 153 valores temporários
intactos). O defeito era **exclusivamente da assertiva**, nunca do DDL: o
pós-check casava `indexdef ILIKE '%WHERE (set_type%'`, mas `pg_get_indexdef()`
injeta cast para coluna `character varying` e renderiza
`WHERE ((set_type)::text = 'PROMO'::text)` — DOIS parênteses. Coluna `boolean`
renderiza `WHERE (is_default = true)` — UM. Medido no schema `public`: 31
índices com um parêntese, 6 com dois.

`IMPLEMENTATION-02` trocou a assertiva por consulta ESTRUTURAL ao catálogo
(`pg_index`/`pg_class`/`pg_namespace`/`pg_attribute`/`pg_get_expr`), em `2161`
e na verificação #2 do `921`. **DDL, pré-flights, `2162` e a regra de
`release_order` não mudaram uma linha.** A rede de proteção falhou por estar
mal calibrada e abortou com segurança — que é o comportamento desejado.

As duas operações são **independentes**: nenhuma depende da outra. A ordem
sugerida (índice primeiro) é só conveniência — o índice é trivial e não toca
`release_order`.

---

## Numeração — por que estes números

- **`2161`** e **`2162`**: livres e inequívocos.
  - **`122` NÃO foi reutilizado** — já existe historicamente em
    `database/migrations/122_adapt_card_set_for_promo.sql`.
  - **`2160` foi evitado** — é o número da Query one-shot de
    `expansion.release_order` executada em 2026-09-09 (ledger
    `20260909231838`). Não gerou arquivo, mas o número está consumido.
- **`921`**: livre. `920_validate_card_set.sql` existe e **permanece
  intocado**; `921` é complementar e específico desta rodada.

---

## `database/schema/120_create_card_set_table.sql` — INTOCADO

O canônico **já está correto**. `120` está na Versão `2.2` e contém, nas
linhas 117-119:

```sql
CREATE UNIQUE INDEX uq_card_set_expansion_promo
    ON public.card_set (expansion_id)
    WHERE set_type = 'PROMO';
```

O próprio arquivo carrega o item aberto (linhas 64-67): *"o banco físico atual
foi construído pelo caminho antigo (120 v1.0 + migration 122), que não incluía
o índice `uq_card_set_expansion_promo`. Não presumir que esse índice já existe
no Supabase real até confirmação."*

Ou seja: a divergência é **exclusivamente** definição canônica correta × banco
físico antigo. `120` não é alterado nesta rodada nem em nenhuma outra por
causa disso. Quando `2161` for executada, o que muda é o **texto do item
aberto** — e essa edição pertence à rodada de closeout, não a esta.

---

## Regra determinística de `release_order`

Por Expansion, `1..N`, 1 = mais antigo. Nesta ordem:

1. `release_date` **ASC**
2. `set_type`: **ENERGY → PROMO → REGULAR/SPECIAL**
3. **publicação principal antes do subset/gallery** — 10 códigos:
   `EXU`, `RC`, `SMA`, `SWSH4.5SV`, `CEL25CC`, `SWSH9TG`, `SWSH10TG`,
   `SWSH11TG`, `SWSH12TG`, `SWSH12.5GG`
4. **`code` ASC em collation `"C"`** — desempate final determinístico

**Regra 2 não foi arbitrada:** é a convenção que os 46 Sets curados
manualmente já exibem (`SVE → SVP → SV1`; `MEE → MEP → ME1`; `BASEP` antes de
`BASE1`; `SMP` antes de `SM1`; `DPP` antes de `DP1`).

**Regras 3 e 4 coincidem nos 10 pares** — em collation `"C"`, `EX10 < EXU`,
`BW11 < RC`, `SM115 < SMA`, `SWSH9 < SWSH9TG`… A regra 3 é a normativa; a 4 é
a implementação mecânica. A verificação 13 do `921` existe justamente para
provar que a 4 nunca viola a 3.

### 26 grupos de empate de data

| Regra que resolveu | Grupos |
|---|---|
| Tipo (regra 2) | 5 — `BASEP/BASE1`, `DPP/DP1`, `SMP/SM1`, `MEP/ME1`, `SVE/SVP/SV1` |
| Principal antes de subset (regra 3) | 10 |
| `code` ASC (regra 4) | 11 — 10 pares de Trainer Kits gêmeos + `SV10.5B/SV10.5W` |

Nenhum grupo exigiu cronologia inventada.

---

## Impacto medido

- **176 das 199 linhas mudam de valor**, sendo **23 entre os 46 curados**.
- **Zero inversões relativas entre os 46** — medido par a par. As 23 mudanças
  são reindexação pura, não recuração. Aprovado por decisão de produto em
  `FINALIZATION-CORRECTION-01`.
- **Faixa final: `1..28`** (máximo em SWSH, que tem 28 Sets).
- SWSH hoje começa em 2 e tem buracos em 1, 8 e 14 — a normalização fecha.
- **Frontend: nenhuma alteração de código.** Todos os consumidores ordenam
  `release_order` DESC (`web/lib/catalogo/queries.ts`, linhas 433, 733, 742,
  928). Hoje os 153 valores `>= 1000` empurram os Sets do bootstrap
  indevidamente para o topo; a normalização **corrige** a exibição.

---

## Decisões técnicas de execução

**Two-pass obrigatório.** `uq_card_set_expansion_release_order` é
`UNIQUE (expansion_id, release_order)` e **não é DEFERRABLE**
(`condeferrable = f`, medido). Um UPDATE direto para os valores finais
colidiria; `SET CONSTRAINTS ALL DEFERRED` não tem efeito sobre constraint
não-deferrable — também medido. Faixa temporária `+10000`, verificada livre
(máximo atual em toda a tabela = 1026, zero linhas `>= 10000`). Origem
(`<= 1026`) e destino (`>= 10001`) são disjuntos, então o passo 1 não colide
consigo mesmo. Mesma técnica já comprovada na Query `2160`.

**Um bloco `DO` por Query.** Um bloco `DO` é um único statement e portanto sua
própria transação: qualquer `RAISE EXCEPTION` desfaz tudo por construção.
Medido no canal MCP que `execute_sql` não preserva sessão nem transação entre
chamadas — por isso não há `BEGIN`/`COMMIT` explícito.

**`CREATE UNIQUE INDEX` simples, não `CONCURRENTLY`.** 199 linhas não
justificam; e `CONCURRENTLY` não roda dentro de transação, o que destruiria a
atomicidade do pré-flight + criação + pós-check.

---

## Duas ressalvas declaradas (não escondidas)

**1. `updated_at` MUDA nas 199 linhas.** `public.card_set` tem o trigger
`trg_card_set_set_updated_at -> set_updated_at()`; qualquer UPDATE o bump.
A invariante da Seção 5 de `2162` cobre **todas** as demais colunas (`id`,
`expansion_id`, `code`, `name`, `set_type`, `release_date`, `base_set_size`,
`total_set_size`, `logo_storage_path`, `created_at`) por md5, e exclui
deliberadamente `release_order` (alvo) e `updated_at` (governança automática).
A exigência "nenhuma outra coluna pode mudar" é atendida no espírito e violada
na letra apenas por `updated_at`, que não é escolha do script.

**2. A invariante de "outros Games intocados" é hoje VAZIA.** Medido:
`card_set` tem 199 linhas no total, **todas Pokémon** — LORCANA tem zero Card
Sets. O escopo por `expansion.game_id` está correto e é mantido por
disciplina, mas a Seção 6 de `2162` não prova nada enquanto o conjunto for
vazio. Registrado para não inflar a força da evidência.

---

## Divergência registrada, não corrigida nesta rodada

`SV10.5B` e `SV10.5W` estão no banco com `release_date = 2025-07-18`; a TCGdex
informa `2025-07-17`. Diferença de um dia, sem efeito na ordenação (empatam
entre si de qualquer forma). Por decisão de produto, **o dado atual é mantido**
nesta rodada — não misturar correção de data com normalização. Fica para
revisão editorial futura.

---

## Gate de aceitação

`921` devolve 14 verificações. **14 PASS / 0 FAIL** é a condição de sucesso.
Qualquer `FAIL` reprova o fechamento do STEP 2.

| # | Verificação | Esperado |
|---|---|---|
| 1 | índice `uq_card_set_expansion_promo` existe | 1 |
| 2 | é UNIQUE, sobre `(expansion_id)`, parcial em `set_type = 'PROMO'` | 1 |
| 3 | `card_set` passa a ter 4 índices | 4 |
| 4 | zero Expansion com >1 PROMO (todos os Games) | 0 |
| 5 | PROMO: 10 Sets em 10 Expansions | 10/10 |
| 6 | `ck_card_set_promo_size` satisfeito | 0 |
| 7 | universo: 199 Sets em 17 Expansions | 199/17 |
| 8 | zero `release_order >= 1000` | 0 |
| 9 | toda Expansion contígua `1..N` | 0 |
| 10 | unicidade `(expansion_id, release_order)` | 0 |
| 11 | faixa global final | 1..28 |
| 12 | regra determinística aplicada linha a linha | 0 |
| 13 | principal antes do subset nos 10 pares | 0/10 |
| 14 | ENERGY antes de PROMO antes do resto, em empates | 0 |

---

## Resultado real da execução (2026-09-10)

`921` devolveu **14 PASS / 0 FAIL**. Pós-checks independentes: 199 Card Sets
Pokémon; 4 índices em `card_set`; `uq_card_set_expansion_promo` presente uma
única vez com predicado `((set_type)::text = 'PROMO'::text)`; 10 PROMO em 10
Expansions; zero Expansion com mais de um PROMO; zero `release_order >= 1000`;
faixa `1..28`; 17 Expansions com sequência `1..N`; regra determinística
199/199; principal antes de subset 0/10 violações; `SV10.5B`/`SV10.5W` com
`release_date` inalterada (`2025-07-18`).

### Divergência de contagem de logo — investigada, não é regressão

O roteiro esperava `151 com logo / 48 sem`. O medido é **`152 / 47`**.
Causa identificada: `SV/2024SV` (McDonald's Collection 2024) recebeu logo em
`2026-09-10 02:44:37`, isto é, **30 minutos depois** do backfill em massa
(`02:14`) e **antes** desta rodada — carga manual isolada pela UI
administrativa. Não foi efeito de `2161` nem de `2162`: a invariante de
colunas da Seção 5 de `2162` cobre `logo_storage_path` por md5 e passou.
O número 151 do roteiro estava apenas desatualizado.

O bucket `card-set-logo` tem 155 objetos para 152 ponteiros. Os **3 órfãos**
são de `2026-08-02`, `2026-08-04` e `2026-08-05` — resíduo histórico do
uploader do frontend, muito anterior a esta frente. Registrado, não tratado
aqui.

## O que esta rodada NÃO fez

Nenhum documento de closeout abrangente alterado (`ROADMAP`, `log.md`,
`README`, `INDEX`, `05a`, handoff, ADR-015 seguem intocados).
`database/schema/120_create_card_set_table.sql` **intocado** — o canônico já
estava correto na v2.2. Nenhum frontend ou pipeline tocado. Nenhum
`git add`/`commit`/`push`.
