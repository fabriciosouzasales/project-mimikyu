# Pricing Payload Cardinality Hardening — Staging (2026-09-07)

| Campo | Valor |
|--------|-------|
| **Rodada** | `PRICING-PAYLOAD-CARDINALITY-HARDENING-01` → `-IMPLEMENTATION` → `-DOCUMENTATION-CLOSEOUT` (2026-09-07) |
| **Status** | **IMPLEMENTED / VALIDATED / CLOSED (2026-09-07).** `3972` **aplicada** (ledger `20260907231143`); `3860` v1.1 **executado** com `18 TOTAL / 18 PASS / 0 FAIL / 0 NOT PROVEN`; zero resíduo. **`3972` PROMOVIDA para `database/migrations/` em 2026-09-08** (`SCHEMA-PROMOTION-RECONCILIATION-01`) — destino canônico da faixa `3xxx`, promoção individual, **sem fold-in em `3968`**. O harness `3860` **não** é promovido e permanece aqui como evidência histórica. |
| **Natureza** | **Segurança material**, não higiene. Mesma classe do BLOCKER fechado em `5138`–`5140` (2026-09-07). |
| **Escopo** | **Exclusivamente** `public.get_cards_pricing_summary(p_card_ids uuid[])`. Nenhuma outra RPC, nenhum outro uso de `uuid[]`. |
| **Origem** | Achado do postcheck de fechamento da Binder/Layout Foundation (`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`), registrado em `docs/05f-pricing.md` §"PENDÊNCIA ABERTA". |

---

## 1. DIVERGÊNCIA DE PREMISSA — leia antes de tudo

O mandato instruía a não editar `3903`/`3904`/`3918`. **Essa lista está incompleta**, e a diferença é material.

A cadeia real de definição da função, verificada em `database/migrations/`:

| Query | Ação | Papel |
|---|---|---|
| `3903` | `CREATE FUNCTION` | criação (P12 v4) |
| `3904` | `DROP` + `CREATE` | hierarquia de 3 printings |
| `3918` | `CREATE OR REPLACE` | hierarquia estendida para 7 printings |
| `3924` | `CREATE OR REPLACE` | vocabulário de variante da fonte |
| **`3968`** | **`DROP` + `CREATE`** | **DEFINIÇÃO EFETIVA** — fallback de preço manual, colunas `printing_label` e `price_origin`, join com `pricing_source_card_identity` |

**A definição efetiva no banco é a `3968`, não a `3918`.** Confirmado por `pg_get_functiondef()` no banco real: o retorno tem **6 colunas**, e o corpo contém a CTE `manual` com `pricing_latest_manual_price()`.

Consequência: se a correção fosse escrita a partir da `3918` — como o enunciado sugeria —, **teria revertido silenciosamente o preço manual em produção**. O `3972` proposto é cópia verbatim da definição efetiva `3968`, com **apenas o bloco de guards** alterado.

## 2. Achado — verificado no banco real

Definição efetiva, primeiras instruções do corpo:

```sql
IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'PRICING_SUMMARY_REQUIRES_AUTHENTICATION' USING ERRCODE = '28000';
END IF;

IF p_card_ids IS NULL OR array_length(p_card_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'PRICING_SUMMARY_EMPTY_INPUT' USING ERRCODE = '22023';
END IF;

IF array_length(p_card_ids, 1) > 100 THEN          -- <== TETO BURLÁVEL
    RAISE EXCEPTION 'PRICING_SUMMARY_TOO_MANY_CARD_IDS' USING ERRCODE = '22023';
END IF;

RETURN QUERY
WITH input_ids AS (
    SELECT DISTINCT input_id FROM unnest(p_card_ids) AS input_id
), ...
```

### O bypass, medido (não presumido)

Prova aritmética executada no banco real em 2026-09-07, **somente leitura**, sem chamar a função:

```
array_fill(uuid, ARRAY[2, 300])
    array_ndims        = 2
    array_length(x, 1) = 2      <- passa pelo teto de 100
    cardinality(x)     = 600
    unnest(x)          = 600 linhas   <- CONFIRMADO
```

Uma RPC pública `SECURITY DEFINER` com `EXECUTE` para `authenticated` executa `unnest` + `DISTINCT` + toda a cadeia `candidate_by_printing` → `candidate` → `automatic` → `manual` — incluindo dois `LEFT JOIN LATERAL` de PTAX e uma chamada por linha a `pricing_latest_manual_price()` — sobre um array de tamanho arbitrário escolhido pelo chamador. O teto de 100 existia no papel, não no comportamento.

## 3. Contrato atual, confirmado no banco

| Propriedade | Valor |
|---|---|
| Assinatura | `p_card_ids uuid[]` (1 overload) |
| Retorno | `TABLE(card_id uuid, has_pricing boolean, brl_amount numeric, fx_status text, printing_label text, price_origin text)` |
| Segurança | `SECURITY DEFINER`, `STABLE` |
| `search_path` | `""` (efetivamente vazio) |
| Owner | `postgres` |
| ACL | `{postgres=X/postgres, authenticated=X/postgres}` |
| `anon` / `service_role` | **sem** `EXECUTE` |
| Autenticação | `auth.uid() IS NULL` → `28000`, primeira instrução do corpo |
| Teto atual | `100`, medido por `array_length(x, 1)` |

## 4. Callers — varredura completa

**Um único caller**, verificado em `web/` e `supabase/`:

`web/app/api/cards/pricing/batch/route.ts`, linha 348:

```ts
const { data, error } = await supabase.rpc("get_cards_pricing_summary", { p_card_ids: cardIds });
```

Ele já aplica, **antes** da chamada: `Array.isArray` + `length === 0` → 400; `length > MAX_CARD_IDS (100)` → 400; dedup por `new Set`; `UUID_RE.test` por elemento → 400; e exige sessão autenticada. Um array JS plano serializado pelo PostgREST é **sempre** unidimensional.

**Nenhum outro caller** — nem em Edge Functions, nem em SQL interno (as menções em `3921`/`3943`/`3944` são comentários, não chamadas).

## 5. Correção proposta

| Arquivo | Papel |
|---|---|
| `3972_harden_get_cards_pricing_summary_payload_cardinality.sql` | migration incremental, `CREATE OR REPLACE` |
| `3860_validate_pricing_payload_cardinality_hardening.sql` | harness funcional fail-closed |

Guards, todos **antes** do `RETURN QUERY` e portanto antes de qualquer `unnest`/`DISTINCT`/`LATERAL`:

1. `NULL` → `PRICING_SUMMARY_EMPTY_INPUT`
2. `cardinality(...) = 0` → `PRICING_SUMMARY_EMPTY_INPUT`
3. `array_ndims(...) <> 1` → `PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE` *(código novo)*
4. `cardinality(...) > 100` → `PRICING_SUMMARY_TOO_MANY_CARD_IDS`

**Ordem obrigatória: vazio antes de dimensão.** `array_ndims('{}')` é `NULL`, e `NULL <> 1` é `NULL` (não `TRUE`) — sem o teste de vazio primeiro, `'{}'` escaparia do guard de forma e cairia adiante com a mensagem errada. Mesma disciplina de `5138`–`5140`.

### Sobre o código de erro novo

`PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE`, `ERRCODE = '22023'` — o mesmo dos dois guards pré-existentes. É um estado que antes era **impossível de observar** (o payload multidimensional não era rejeitado, era processado), então nenhum chamador existente pode depender dele. As duas mensagens pré-existentes foram preservadas **literalmente**, com o mesmo `ERRCODE`.

### Por que `CREATE OR REPLACE` e não `DROP` + `CREATE`

Assinatura e tipo de retorno são **idênticos** aos da definição efetiva. `CREATE OR REPLACE` preserva o OID e os grants, e não abre janela em que a função deixa de existir. `3904` e `3968` precisaram de `DROP` porque mudaram o retorno; aqui não há mudança de retorno.

### O que **não** muda

Assinatura, retorno, `LANGUAGE`, `STABLE`, `SECURITY DEFINER`, `search_path = ''`, owner, `REVOKE`/`GRANT`, a verificação de autenticação, e **toda a lógica de negócio**: regra NM + `price_type = 'MARKET'`, a hierarquia de sete printings, o caminho `AUTOMATIC`, o fallback `MANUAL`, a conversão PTAX, `fx_status` e `price_origin` — byte-idênticos à `3968`.

## 6. Numeração

- **`3972`** — próximo livre em `database/migrations/` (maior atual: `3971`). Faixa `3900+` do módulo Pricing = funções de leitura/RPC (`STD-001`, §"Módulo: Pricing").
- **`3860`** — faixa `3800`–`3899` é a de **Validações** do módulo Pricing. Decênios `3800`/`3810`/`3820`/`3830`/`3840`/`3850` já usados (Incrementos P1–P6); `3860` é o próximo livre. Não é migration: roda em `BEGIN … ROLLBACK`, sem alterar schema.

## 7. Harness `3860` — gate e cobertura

**Gate: `TOTAL 18 / PASS 18 / FAIL 0 / NOT PROVEN 0`.**

20 rótulos estáticos; `F-ABORT` e `N-ABORT` são ramos fail-only mutuamente exclusivos, gravados só em `EXCEPTION WHEN OTHERS` e sempre com `passed = FALSE`. Máximo saudável de runtime = 18. Qualquer `*-ABORT` presente = STOP. O número do gate já é o de runtime — a lição de `205 → 196` (`5818`) e `28 → 27` (`5820`) está aplicada aqui desde a escrita.

Os nove cenários exigidos, todos sob `authenticated` com claim JWT real:

| Caso | Cenário | Esperado |
|---|---|---|
| `N01` | `NULL` | `PRICING_SUMMARY_EMPTY_INPUT` |
| `N02` | vazio `'{}'` | `PRICING_SUMMARY_EMPTY_INPUT` (**não** a de dimensão) |
| `N03` | 1 elemento | aceito, 1 linha |
| `N04` | 100 distintos | aceito, 100 linhas (teto exato) |
| `N05` | 101 distintos | `PRICING_SUMMARY_TOO_MANY_CARD_IDS` |
| `N06` | multidim `dim1=2`, `card=600` | `PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE` — **prova do fechamento** |
| `N07` | multidim `dim1=2`, `card=10` | `PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE` — contrato de **forma** |
| `N08` | payload válido, dado real | `printing_label` idêntico a uma referência independente |
| `X01`/`X02` | zero resíduo | somente leitura, sem `COMMIT` |

Mais `N00` (aritmética dos payloads), `R01`/`R02` (autenticação e ACL preservadas) e `S01`–`S04` (static proof: cadeia de guards antes do primeiro `unnest`/`DISTINCT`, zero `array_length(p_card_ids`, contrato de segurança, assinatura/retorno, regra de negócio).

**`N05` sozinho não prova nada** — passaria também com o `array_length` antigo. Só `N06` distingue `cardinality()` de `array_length(x,1)`.

### Zero resíduo por construção

O harness é **somente leitura**: não cria fixture, não insere, não atualiza, não apaga. Usa 101 Cards reais apenas como identificadores de entrada de uma função `STABLE`. `BEGIN … ROLLBACK`, sem `COMMIT` no arquivo.

### Pré-requisitos, verificados no ambiente

| Requisito | Medido em 2026-09-07 |
|---|---|
| `3972` aplicada | pendente (esta rodada) |
| ≥ 1 `auth.users` | **3** |
| ≥ 101 Cards ativos | **7.713** |
| ≥ 1 observação NM/MARKET `CONFIRMED` (para `N08`) | **138.888** |

## 8. Impacto esperado

**Segurança.** Fecha o último bypass conhecido desta classe em RPC exposta a `authenticated`. Depois desta rodada, todas as RPCs `public` com parâmetro `uuid[]` que têm **teto** medem por `cardinality()` com contrato de forma.

**Performance.** Nula no caminho feliz: quatro comparações escalares em PL/pgSQL, todas antes do `RETURN QUERY`. `cardinality()` e `array_ndims()` são O(1) sobre o cabeçalho do array — não percorrem elementos. Nenhum plano de consulta muda; nenhum índice criado ou alterado.

**Comportamento.** Nenhuma mudança para chamadas legítimas. Payload multidimensional passa de "processado silenciosamente" para "rejeitado com erro explícito" — o objetivo da correção.

**Regressão no frontend.** Nenhuma esperada. O caller já garante array plano de ≤ 100 UUIDs válidos e apenas registra o erro em log, sem parsear código.

## 9. Riscos e o que este staging **não** resolve

- **Não corrige** `admin_decide_catalog_import_row` nem os demais usos de `uuid[]` sem teto — fora do escopo por decisão explícita, registrados em `docs/05f-pricing.md` como *hardening de contrato `UUID[]` / admin*, para rodada própria.
- **Não afirma** que o bypass está ausente em todo o sistema. Afirma apenas o fechamento nesta RPC.
- `get_card_pricing_snapshot(uuid)` — a irmã por-carta — recebe `uuid` escalar, não array: **não é afetada** e não foi tocada.

## 10. GO/NO-GO — RESOLVIDO

**GO concedido e executado em 2026-09-07.**

| Passo | Objeto | Resultado |
|---|---|---|
| 1 | `3972` aplicada | ledger `20260907231143` |
| 2 | Postcheck imediato | conforme, ver §11 |
| 3 | Equivalência da lógica de negócio | **byte-a-byte idêntica** à `3968`, ver §12 |
| 4 | `3860` v1.1 executado | **18 / 18 / 0 / 0 — PASS** |

**Promoção para `database/schema/` continua NÃO autorizada** — depende de decisão de Fabrício, junto com o commit.

## 11. Registro de execução — postcheck (2026-09-07)

| Item | Resultado |
|---|---|
| Overloads | **1** |
| OID | `56577` — **preservado** (`CREATE OR REPLACE`, sem `DROP`) |
| Assinatura | `p_card_ids uuid[]` |
| Retorno | `TABLE(card_id uuid, has_pricing boolean, brl_amount numeric, fx_status text, printing_label text, price_origin text)` — 6 colunas preservadas |
| `SECURITY DEFINER` / volatilidade | `true` / `s` (`STABLE`) |
| `search_path` | `{search_path=""}` — efetivamente vazio |
| Owner / ACL | `postgres` / `{postgres=X/postgres,authenticated=X/postgres}` — `anon` e `service_role` **sem** `EXECUTE` |
| `cardinality(p_card_ids)` | presente, posição 734 |
| `array_ndims(p_card_ids) <> 1` | presente, posição 899 |
| `v_raw_count > 100` | presente, posição 1054 |
| `unnest(p_card_ids)` | posição 1272 — **todos os guards antes** |
| `array_length(p_card_ids` no corpo executável | **0 ocorrências** |

## 12. Prova de equivalência da lógica de negócio

Comparação normalizada (comentários removidos, whitespace colapsado, delimitador de dollar-quote descartado) entre a `3968` — baseline efetiva correta, ver §1 — e a `3972`, do `RETURN QUERY` até o fim do corpo:

```
md5 3968 : 858e53ff9740b1d3f0ffff829d2986e2   len: 3805
md5 3972 : 858e53ff9740b1d3f0ffff829d2986e2   len: 3805
>>> IDENTICAS
```

O `diff` do trecho de negócio (130 linhas em cada arquivo) veio **vazio**; md5 do trecho bruto: `82620684a6d24919630e122c02b37162`.

Marcadores confirmados `true` na definição live pós-`3972`: hierarquia dos 7 printings (`'1st Edition Holofoil'`), `identity_role = 'PRIMARY'`, `psci.match_status = 'CONFIRMED'`, `pcm.match_status = 'CONFIRMED'`, `'AUTOMATIC'`, `'MANUAL'`, `pricing_latest_manual_price`, `BCB_PTAX`, `printing_label`, `price_origin`, `'MARKET'`, `cc.code = 'NM'`.

**Nota metodológica.** Duas medições intermediárias acusaram falsa divergência, ambas por artefato de ancoragem: (a) o comentário do próprio `3972` contém a frase "antes do `RETURN QUERY`", e a busca casou nele em vez do statement; (b) o PostgreSQL reescreve `$$` como `$function$` em `pg_get_functiondef`. Nenhuma das duas era mudança de lógica — ficam registradas para que a próxima rodada que precisar dessa prova ancore no statement indentado e descarte o delimitador.

## 13. Resultado do `3860` v1.1

| grupo | total | PASS | FAIL | NOT PROVEN |
|---|--:|--:|--:|--:|
| F | 1 | 1 | 0 | 0 |
| N | 9 | 9 | 0 | 0 |
| R | 2 | 2 | 0 | 0 |
| S | 4 | 4 | 0 | 0 |
| X | 2 | 2 | 0 | 0 |
| **TOTAL** | **18** | **18** | **0** | **0** |

`failing_cases` e `not_proven_cases` = `NULL` em todos os grupos. **`N06`** — multidimensional `dim1=2`, `cardinality=600` — rejeitado com `PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE`: é a prova do fechamento do bypass. `N08` alcançou PASS com dado real.

### Defeito real encontrado — no harness, não na migration

A primeira execução abortou com `42883: function min(uuid) does not exist`. O grupo `R` usava `ARRAY[min(id)]`; **`min(uuid)` não existe em PostgreSQL** — limitação já registrada no projeto. Corrigido no `3860` (v1.0 → v1.1) para `ORDER BY id LIMIT 1`. **Nenhum caso de teste foi alterado, adicionado ou removido; o gate seguiu 18; a `3972` não foi tocada.** A falha foi alta e ruidosa, exatamente como um harness fail-closed deve falhar.

### Zero resíduo

`ROLLBACK;` emitido. Temp tables `_v`/`_fx`/`_ids` remanescentes = **0**. `pricing_observation` = 251.230 e `pricing_manual_price` = 19 — o harness é somente leitura e não escreveu nada.

**Estado:** `3972 APLICADA` · `3860 EXECUTADO — 18/18 PASS` · `3972 PROMOVIDA PARA database/migrations/ (2026-09-08, SCHEMA-PROMOTION-RECONCILIATION-01, sem fold-in em 3968)` · `3860 NÃO PROMOVIDO — evidência histórica`.
