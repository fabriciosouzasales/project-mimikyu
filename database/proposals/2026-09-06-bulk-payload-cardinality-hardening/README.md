# Bulk Payload Cardinality Hardening — Staging (2026-09-06)

| Campo | Valor |
|--------|-------|
| **Rodada** | criado em `...-CONSOLIDATED-CORRECTION-03` §6 SECURITY SPILLOVER; reconciliado em `...-CONSOLIDATED-CORRECTION-04` §6; **executado e fechado em `...-IMPLEMENTATION-01-CLOSE` (2026-09-07)** |
| **Status** | **IMPLEMENTED / VALIDATED (2026-09-07).** `5138`, `5139` e `5140` **aplicados** ao banco; `5820` **executado** com PASS `27/27/0/0`. Ainda **não** promovido para `database/schema/`; **nenhum commit/push realizado.** |
| **Natureza** | **Segurança material**, não higiene. Mesma classe do BLOCKER que a FINAL MATERIAL AUDIT encontrou nas RPCs da Binder/Layout Foundation. |
| **Escopo** | 3 migrations incrementais sobre RPCs públicas `SECURITY DEFINER` já LIVE + 1 harness funcional executável. |

---

## 1. Por que esta pasta existe

A `CORRECTION-02` da Binder/Layout Foundation citou `5024`, `5046` e
`5047` como **o padrão canônico** de teto de lote a ser seguido. A
`FINAL MATERIAL AUDIT` então apontou que o próprio padrão canônico
contém o defeito: o teto é medido com `array_length(x, 1)`.

Isto foi **verificado no repositório**, não presumido.

## 2. Achado — verificado nas definições canônicas efetivas

Investigação de qual é a definição **efetivamente mais recente** de
cada função:

| Função | Definição canônica efetiva | Outras definições | Bypass presente? |
|---|---|---|---|
| `set_physical_cards_storage()` | `database/schema/5024_create_set_physical_cards_storage_function.sql` | apenas a cópia histórica em `proposals/2026-08-31-02a-storage/` | **SIM** |
| `allocate_physical_cards_to_collection()` | `database/schema/5046_create_allocate_physical_cards_to_collection_function.sql` (já incorpora a extensão da Query `5064`) | `proposals/2026-09-01-02c-allocation/5046`, `proposals/2026-09-02-02d-reference/5064` — ambas históricas | **SIM** |
| `deallocate_physical_cards_from_collection()` | `database/schema/5047_create_deallocate_physical_cards_from_collection_function.sql` | apenas a cópia histórica em `proposals/2026-09-01-02c-allocation/` | **SIM** |

Trecho idêntico nas três:

```sql
IF p_physical_card_ids IS NULL OR array_length(p_physical_card_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'p_physical_card_ids não pode ser vazio';
END IF;

v_raw_count := array_length(p_physical_card_ids, 1);

IF v_raw_count > 500 THEN
    RAISE EXCEPTION 'lote excede o limite de 500 itens por chamada';
END IF;
```

### O bypass, em números

```
array_fill(uuid, ARRAY[2, 400])
    array_ndims        = 2
    array_length(x, 1) = 2      <- passa pelo teto de 500
    cardinality(x)     = 800
    unnest(x)          = 800 linhas processadas
```

Uma RPC pública `SECURITY DEFINER` executa `unnest` + sort + `DISTINCT`
+ validação linha a linha sobre um array de tamanho **escolhido pelo
chamador**, sem limite efetivo. O teto existia no papel, não no
comportamento.

## 3. Correção proposta

| Arquivo | Substitui | Função |
|---|---|---|
| `5138_harden_set_physical_cards_storage_payload_cardinality.sql` | `5024` | `set_physical_cards_storage(uuid, uuid[])` |
| `5139_harden_allocate_physical_cards_to_collection_payload_cardinality.sql` | `5046` | `allocate_physical_cards_to_collection(uuid, uuid[])` |
| `5140_harden_deallocate_physical_cards_from_collection_payload_cardinality.sql` | `5047` | `deallocate_physical_cards_from_collection(uuid, uuid[])` |

Guards, todos **antes** de qualquer `unnest`/`DISTINCT`, resolve de
ownership, lock ou escrita:

1. `NULL` → `'p_physical_card_ids não pode ser vazio'`
2. `cardinality(...) = 0` → mesma mensagem (cobre `'{}'`, cujo
   `array_ndims` é `NULL`)
3. `array_ndims(...) <> 1` → `'deve ser um array unidimensional'`
4. `cardinality(...) > 500` → `'lote excede o limite de 500 itens por chamada'`

### O diff EXATO, linha a linha

Não é verdade que "fora o bloco de guards o corpo é byte-idêntico" —
houve **duas** classes de alteração, e ambas ficam registradas aqui.
Diff calculado sobre o intervalo `CREATE … FUNCTION` → `GRANT EXECUTE`,
com o arquivo canônico:

**(a) Cabeçalho da declaração — 2 dos 3 arquivos**

| Arquivo | Antes | Depois |
|---|---|---|
| `5138` | `CREATE FUNCTION public.set_physical_cards_storage(` | `CREATE OR REPLACE FUNCTION public.set_physical_cards_storage(` |
| `5140` | `CREATE FUNCTION public.deallocate_physical_cards_from_collection(` | `CREATE OR REPLACE FUNCTION …` |
| `5139` | já era `CREATE OR REPLACE` | inalterado |

**(b) Bloco de guards — os 3 arquivos**

```
-    IF p_physical_card_ids IS NULL OR array_length(p_physical_card_ids, 1) IS NULL THEN
+    IF p_physical_card_ids IS NULL THEN
-    v_raw_count := array_length(p_physical_card_ids, 1);
+    v_raw_count := cardinality(p_physical_card_ids);
+    IF v_raw_count = 0 THEN  RAISE EXCEPTION 'p_physical_card_ids não pode ser vazio';  END IF;
+    IF array_ndims(p_physical_card_ids) <> 1 THEN  RAISE EXCEPTION '… deve ser um array unidimensional …';  END IF;
```

**(c) TROCA SEGURA FORA DO BLOCO DE GUARDS — não é byte-identidade**

Também foi trocado `array_length(v_distinct_ids, 1)` por
`cardinality(v_distinct_ids)` nas comparações de contagem posteriores:

| Arquivo | Linha alterada |
|---|---|
| `5138` | `IF v_owned_count <> cardinality(v_distinct_ids) THEN` |
| `5139` | `IF v_owned_count <> cardinality(v_distinct_ids) THEN` **e** `IF v_eligible_count <> cardinality(v_distinct_ids) THEN` |
| `5140` | `IF v_allocated_count <> cardinality(v_distinct_ids) THEN` |

**Por que é segura:** `v_distinct_ids` vem de
`array_agg(DISTINCT x) FROM unnest(...)`, que é sempre unidimensional —
`cardinality()` e `array_length(…,1)` devolvem exatamente o mesmo valor
nesse caso. A troca não muda comportamento; existe para que a
propriedade "**zero `array_length` no corpo executável**" seja
verificável por prova estática (gate `S01` do `5820`), sem exceções a
justificar.

**Total: 24 linhas divergentes por arquivo** (contando as linhas de
comentário introduzidas no bloco de guards).

**O que NÃO mudou:** assinatura, contrato de retorno, ownership,
não-enumeração, locks, semântica de lifecycle, grants e as mensagens de
erro pré-existentes — preservadas literalmente.

**Migrations históricas não foram tocadas.** `5024`, `5046`, `5047` e
`5064` permanecem como registro do que foi executado. Estes três
arquivos são migrations **incrementais** (`CREATE OR REPLACE`).

## 4. Compatibilidade

Nenhum chamador legítimo envia array multidimensional — o cliente
TS/JS envia `uuid[]` plano via PostgREST. Nenhum lote legítimo de
≤ 500 itens muda de comportamento.

## 5. Varredura completa — o que MAIS foi encontrado

A varredura cobriu **todas** as funções de `database/schema/` que usam
`array_length(p_…)`. Resultado honesto:

| Objeto | Situação | Classificação |
|---|---|---|
| `5024` / `5046` / `5047` | teto de 500 medido por `array_length(x,1)` | **BYPASS — corrigido aqui** |
| `5012 add_physical_cards()` | usa `jsonb_array_length(p_items)`; JSONB não tem multidimensionalidade | **NÃO AFETADO** |
| `6104` / `6110` / `6115` | payload JSONB | **NÃO AFETADO** |
| `2081 admin_decide_catalog_import_row(p_row_ids uuid[])` | `array_length(p_row_ids,1) IS NULL` como guard de vazio **e** `array_length(p_row_ids,1) <> 1` para exigir "exatamente uma linha" quando `p_corrected_normalized_data` é informado. Um array 2-D `array_fill(u, ARRAY[1,5])` tem `array_length(dim1)=1` e **engana esse guard**. | **HARDENING DE CONTRATO — admin-only. Ver correção da avaliação abaixo.** |
| `2144 admin_decide_catalog_variant_import_row()` | mesmo padrão de `array_length(...,1) IS NULL` como guard de vazio | **HARDENING DE CONTRATO — admin-only** |
| `5098` / `5099` (`p_generation_ids uuid[]`) | `array_length(...,1) IS NULL` apenas como guard de vazio; não há teto nem decisão dependente de cardinalidade além disso | **BAIXA SEVERIDADE** |

### Correção da avaliação de `2081` (CORRECTION-04)

A `CORRECTION-03` afirmou que, no `2081`, "uma correção destinada a UMA
linha seria aplicada a CINCO". **Isso estava errado e fica retificado
aqui.**

O que de fato acontece com `array_fill(u, ARRAY[1,5])`:

- o guard `array_length(p_row_ids, 1) <> 1` **é enganado** — a primeira
  dimensão vale 1, então o array 2-D atravessa a checagem de
  "exatamente uma linha";
- mas o consumo posterior do array **não** propaga a correção para as
  cinco linhas: um subscript simples como `p_row_ids[1]` sobre um array
  **multidimensional** tem número incorreto de subscritos e **não
  representa os cinco IDs** — não há um caminho pelo qual
  `p_corrected_normalized_data` seja gravado nas cinco linhas.

Ou seja: o defeito real é de **contrato de entrada** (um guard que não
mede o que diz medir), não de escrita indevida em massa. Continua
merecendo correção — pelo mesmo motivo dos `5024`/`5046`/`5047`: um
guard que pode ser contornado não é um guard —, mas **não é um vetor
de corrupção de dados**, e a classificação anterior estava
superdimensionada.

### Classificação vigente destes quatro

**HARDENING DE CONTRATO / ADMIN-ONLY** (`2081`, `2144`) e
**BAIXA SEVERIDADE** (`5098`, `5099`) — até que uma auditoria própria
os examine. Não são BLOCKER e **não bloqueiam** o GO de
`5138`/`5139`/`5140`.

Nenhum dos quatro foi alterado: o mandato delimita a investigação a
`5024`/`5046`/`5047`, e expandir para o Catálogo Editorial e o Pokédex
Scope seria alargar escopo conceitual. Ficam **registrados como
achado**, com o mecanismo exato, para rodada própria.

## 6. Validação transacional obrigatória — `5820`

A `CORRECTION-04` §6 exige que a validação multidimensional exista
**antes de qualquer GO de execução**. Ela existe:

| Arquivo | Papel |
|---|---|
| `5820_validate_bulk_payload_cardinality_hardening.sql` (v1.2) | **EXECUTADO EM 2026-09-07 — PASS `27/27/0/0`** |

Contrato do `5820`:

- `BEGIN … ROLLBACK`, zero resíduo por construção; fixture mínima
  criada e descartada; **protocolo em DUAS CHAMADAS** (relatório na
  chamada 1, `ROLLBACK` na 2) — mesma disciplina do `5818`;
- fail-closed: `_expect_error` reprova quando nenhum erro é levantado
  **e** quando o erro é outro; `_norm()` remove diacríticos dos dois
  lados; erro inesperado nunca vira PASS;
- para **cada uma das três** funções: `_500` (regressão do caminho
  feliz), `_501rep` (necessário, não suficiente), `_501dist` (cap
  antecede ownership), **`_MULTI600`** (`array_length(x,1)=2`,
  `cardinality=600` — a prova do fechamento), `_MULTI10` (contrato de
  forma) e `_VAZIO`;
- grupo `E`: efeito real — nenhuma Allocation remanescente e o Storage
  atribuído pelo caminho feliz preservado, provando que os payloads
  rejeitados **não escreveram**;
- grupo `S`: STATIC PROOF fail-closed no formato do `B10` do `5818` —
  `IF cap` < `RAISE EXCEPTION` < mensagem < primeiro `unnest`/`DISTINCT`,
  `cardinality()` e `array_ndims(...) <> 1` presentes, **zero
  `array_length`** no corpo executável, mais `SECURITY DEFINER` /
  `search_path` / owner / grants preservados — e o `search_path` é
  provado **efetivamente vazio** (`pg_temp._empty_search_path()` sobre
  `proconfig`), não apenas presente.

### 6-bis. Gate do `5820` — retificação (IMPLEMENTATION-01-CLOSE)

O gate comunicado até `...-FINALIZE` era **28 PASS / 0 FAIL / 0 NP**.
Esse número é **arquivo, não runtime**, e é inalcançável.

O `5820` tem **28 rótulos estáticos únicos** — `E01 E02` (2), `F01`
(1), `G-ABORT G00 G01..G06 G11..G16 G21..G26` (20), `S01..S03` (3),
`X01 X02` (2). O 28º é **`G-ABORT`**, gravado dentro do
`EXCEPTION WHEN OTHERS` do bloco G:

- grupo G roda inteiro → `G-ABORT` não é gravado → **27 registros, 0 FAIL**;
- grupo G aborta → `G-ABORT` é gravado com `passed = FALSE` e os casos
  restantes não rodam.

O 28º rótulo só existe no cenário de falha e nasce FAIL. **Gate
oficial retificado: `TOTAL 27 / PASS 27 / FAIL 0 / NOT PROVEN 0`.**
`G-ABORT` presente = STOP. Mesma classe do "205" do `5818`, retificado
para 196 pelo mesmo motivo.

Apenas **documentação/cabeçalho** foi alterada (`v1.1 → v1.2`). A
lógica executável do `5820` é idêntica e o harness **não** foi
reexecutado.

## 7. GO/NO-GO — RESOLVIDO

**GO concedido e executado em 2026-09-07.** Ordem real:

| Passo | Objeto | Resultado |
|---|---|---|
| 1 | `5138` aplicado | ledger `20260907215740` |
| 2 | `5139` aplicado | ledger `20260907215826` |
| 3 | `5140` aplicado | ledger `20260907215905` |
| 4 | `5820` executado | **27 / 27 / 0 / 0 — PASS** |

Validação estática pós-apply nas três funções: `usa_cardinality = t`,
`usa_ndims = t`, `sem_array_length = t`, `prosecdef = t`,
`proconfig = {search_path=""}`, `owner = postgres`,
`authenticated EXECUTE = t`, `anon EXECUTE = f`.

Resíduo pós-`ROLLBACK`: `__5820_*` = 0 em `collection` e
`storage_container`; `collection_allocation` = 0; `physical_card` = 0.

**Promoção para `database/schema/` continua NÃO autorizada** — depende
de decisão de Fabrício, junto com o commit.

**Numeração:** `5138`–`5140` e `5820` estavam livres.
`database/schema/` ocupa `5000`–`5103`; a proposal Binder/Layout ocupa
`5104`–`5137` + `5141`; as validações ocupadas iam até `5819`.

## 8. Achado adjacente NÃO corrigido nesta rodada

O postcheck final da `IMPLEMENTATION-01` varreu **todas** as funções
`public` com parâmetro `uuid[]`, e não só as do escopo. Achado novo:

> **`get_cards_pricing_summary(p_card_ids uuid[])`** — `SECURITY
> DEFINER`, `search_path=""`, owner `postgres`, `EXECUTE` para
> `authenticated` — mantém o bypass multidimensional **preexistente**:
>
> ```sql
> IF array_length(p_card_ids, 1) > 100 THEN
>     RAISE EXCEPTION 'PRICING_SUMMARY_TOO_MANY_CARD_IDS' ...
> END IF;
> RETURN QUERY
> WITH input_ids AS (SELECT DISTINCT input_id FROM unnest(p_card_ids) ...)
> ```
>
> `array_fill(uuid, ARRAY[2,300])` → `array_length(x,1) = 2` (passa
> pelo teto de 100) e `cardinality(x) = 600` (o que o `unnest`
> processa). **Mesma classe** de `5024`/`5046`/`5047`.

**Não corrigido aqui, por decisão explícita.** Próxima ação
obrigatória do projeto: **`PRICING-PAYLOAD-CARDINALITY-HARDENING-01`**.
**Bulk Collection Operations não pode iniciar antes** desse hardening
estar aplicado e validado.

Separadamente, e **fora** do hardening de Pricing:
`admin_decide_catalog_import_row` (guard `array_length(...,1) <> 1`
burlável por array 2-D com dim1=1) e os usos apenas-`IS NULL`
(`admin_decide_catalog_variant_import_row`,
`create_reference_based_pokedex_collection`,
`set_collection_pokedex_scope`, e `admin_confirm_catalog_import` /
`_variant_import`, que não têm teto algum) ficam registrados como
**hardening de contrato `UUID[]` / admin**, para rodada própria.

**Limite de alcance da afirmação de segurança desta pasta:** a classe
do bypass multidimensional está fechada **nas RPCs do escopo desta
implementação** — as três bulk (`5138`–`5140`) e as quatro do Binder
com `uuid[]` (`reorder_layout_pages`, `clear_slot_expected_content`,
`set_slot_lock`, `remove_slot_assignment`). **Não** se afirma ausência
do bypass em todo o sistema.

**Estado:** `5138/5139/5140 APLICADOS` · `5820 EXECUTADO — PASS` ·
`COMMIT/PUSH NÃO REALIZADO`.
