# EDITION CONTEXT AXIS — fundação física do terceiro eixo de identidade

| Campo | Valor |
|---|---|
| **Ciclo** | `VARIANT-DISPLAY-SEMANTICS-01 / EDITION-CONTEXT-AXIS-STAGING-01` |
| **Status** | **PROPOSTA — NADA EXECUTADO.** Nenhuma DDL aplicada, nenhuma escrita LIVE, nenhuma promoção para `schema/`. |
| **Revisão** | **1.6 — `WRITE-PATH-STAGING-01`.** Caminho de escrita FECHADO: `2218`–`2222` escritos por inteiro (2.738 linhas), Edge patch rev 2.0 com **D3 fechado** (espelho em memória), 8 testes Deno implementados, auditoria de read models e status A–G. Classe C (corpo não escrito) **vazia**. |
| **Revisão anterior** | **1.5 — `OPERATIONAL-BOUNDARY-CORRECTION-01`.** `VALID + PENDING` **não é** row operacional: atingia 415 rows de jobs `CANCELLED` e zero operacionais. Guard passa a ser **job-aware**; backfill global **eliminado**; `E1` deixa de bloquear a fundação. |
| **Baseline** | `HEAD origin/main eca288cf` · `card_variant` 24.893 · PostgreSQL 17.6 |
| **Autoridade** | `MODELING-AUDIT-01` → `PHYSICAL-IDENTITY-BOUNDARY-AUDIT-01` → `-CORRECTION-01` → `SET-LOGO-PHYSICAL-EVIDENCE-RECONCILIATION-01` (todos PASS) |

---

## 1. Achado bloqueante da rodada — 94/133 **não** era o universo

O mandato exigiu medir a **união** antes de congelar o modelo. Estava certo em exigir.

| Conjunto | Linhas | Cobertura | Traits | Profiles |
|---|---:|---:|---:|---:|
| **A** — `NEEDS_REVIEW` classificadas EDITION_CONTEXT | 1.069 | **100%** | 94 | 133 |
| **B** — legacy `READY_TO_DECOMPOSE` | 365 | **100%** | 35 | 52 |
| **A ∪ B** | — | **100%** | **115** | **173** |
| Exclusivos de A | — | — | 80 | 121 |
| Exclusivos de B | — | — | **21** | **40** |

**Aridade máxima na união: 2.** Nenhuma linha combina mais de dois tokens.

Os 21 traits exclusivos do legado — `WORLDS-2023/2024/2025`, `TOP-EIGHT`, `LEAGUE`, `PLAYER-REWARD`, `POKEMON-CENTER`, `POKEMON-CENTER-NY`, `1ST-MOVIE`, `1ST-MOVIE-INVERTED`, `30TH-POKEDAY`, `ASIA-2023-24`, `GYM-CHALLENGE`, `HORIZONS`, `INTERNATIONAL-CHAMPIONSHIP-EUROPE`, `INTERNATIONAL-CHAMPIONSHIP-NORTH-AMERICA`, `POKEMON-4-EVER`, `POKEMON-TOGETHER`, `POKETOUR-99`, `ULTRA-BALL-LEAGUE`, `WOTC`, `TOP-EIGHT` — não estão no resíduo **porque já foram materializados**. Seriam perdidos se o modelo fosse congelado só sobre A.

**Como B foi derivado sem inventar nada:** as 365 legacy têm **100% de lineage** (`catalog_variant_import_row.resulting_variant_id`), portanto o `raw_data` original está disponível. Os 35 traits de B vêm da **mesma fonte** que os de A, não de leitura do `code` do tipo contaminado.

**Não-explosão preservada:** 173/115 = **1,50**. Um Worlds novo custa **1 trait**, contra **+7 Variant Types** no modelo atual.

---

## 2. Pipeline semântico — fluxo único

```
RAW (type · foil · subtype · stamp[] · size)
  │
  ├─▶ 1. SIZE-SCOPE GATE ............ 2198. Fora de STANDARD ⇒ BLOCKED_*. Escopo, nunca identidade.
  │
  ├─▶ 2. PRINTING ROUTING ........... 2172/2176. Consome subtype/stamp com mapping ativo.
  │                                   Tokens consumidos SAEM do residual.
  │
  ├─▶ 3. EDITION CONTEXT ROUTING .... 2207 (NOVO). Consome stamp/subtype/foil-allowlist
  │                                   com mapping ativo. Tokens consumidos SAEM do residual.
  │
  ├─▶ 4. RESIDUAL FINISH SIGNATURE .. o que sobrou de (type, foil, subtype, stamp[])
  │
  ├─▶ 5. VARIANT TYPE LOOKUP ........ 2192/2196. scoped > global > NEEDS_REVIEW.
  │
  └─▶ 6. CARD VARIANT IDENTITY ...... (card, variant_type, printing_profile?, edition_context_profile?)
```

**Ordem 2 → 3 é deliberada.** Printing primeiro porque seu vocabulário é fechado e mais antigo; Edition Context consome o que restou. Um token não pode alimentar os dois eixos — o primeiro que o consumir o remove do residual.

### Fail-closed — o que é proibido, sem exceção

| Proibido | Por quê |
|---|---|
| Inferir por substring, regex ou heurística | Um token novo viraria contexto sem decisão humana |
| Derivar `code` canônico do vocabulário TCGdex | A taxonomia interna ficaria subordinada à fonte |
| Consumir token indeterminado | 61 linhas em X existem justamente por isso |
| "Adivinhar" família por padrão de nome | `DECK_PLAYER_*` exige decisão editorial |

**Token desconhecido não vira contexto.** Permanece no residual de Finish e a linha termina `NEEDS_REVIEW`.

### `raw_field` autorizados — decisão explícita

| Campo | Status | Justificativa medida |
|---|---|---|
| `stamp` | **autorizado** | 1.145 ocorrências em A; alimentador principal |
| `subtype` | **autorizado** | Printing já o consome; o que sobra pode ser contexto |
| `foil` | **PROIBIDO no DDL** (CORRECTION-01) | ver decisão abaixo |
| `type` | **proibido** | é o eixo de acabamento por definição |
| `size` | **proibido** | é escopo (2198), nunca identidade |

> **Decisão da CORRECTION-01 (Blocker 6) — `foil` sai do DDL.**
>
> O campo é semanticamente misto na fonte: carrega padrão físico (`COSMOS`, `CRACKED-ICE`, `ENERGY`) **e** nome de programa (`LEAGUE`, `PLAYER-REWARD`, `PROFESSOR-PROGRAM`). A assimetria A×B é real — o legado já tratou os três últimos como contexto (`STANDARDS_LEAGUE`, `PLAYER_REWARD_REVERSE`, `COSMOS_PROFESSOR_REVERSE`, todos em B), enquanto as **57 linhas equivalentes em A seguem `INDETERMINATE`**.
>
> A versão 1.0 desta proposta permitia `raw_field='foil'` com `CHECK` de allowlist de três tokens. **Isso foi revertido.** Legitimar `foil` no schema — ainda que restrito — significa **fixar no DDL uma semântica que ainda não foi decidida**: bastaria um `INSERT` futuro para que as 57 linhas fossem classificadas sem decisão editorial. O contrato agora é literalmente `CHECK (raw_field IN ('stamp','subtype'))`, e `ck_cecem_foil_allowlist` **não existe**.
>
> O legado que carrega esses três tokens **não depende do mapping externo**: recebe Edition Context por migração via lineage (`resulting_variant_id`), caminho que não passa por 2207. As 57 modernas **continuam em HOLD**. Ampliar o domínio de `raw_field` exigirá migration própria, depois que B3 for decidido — e o `CHECK` torna essa ampliação **visível e revisável**, em vez de silenciosa.

---

## 3. Modelo físico proposto

| Query | Objeto | Papel |
|---|---|---|
| `2203` | `card_edition_context_trait` | átomo · 8 famílias · `DECK_PLAYER_*` obrigatório |
| `2204` | `card_edition_context_profile` | composição canônica por conjunto exato |
| `2205` | `card_edition_context_profile_trait` | N:N — **fonte da verdade** |
| `2206` | guards de composição | selagem · imutabilidade · trait ativo |
| `2207` | `card_edition_context_external_mapping` (+N:N) | ponte única com a fonte · fail-closed |

> **`2203`–`2211` — EXPLICIT TRANSACTION BOUNDARY → atomic rollback on failure**
> (`TRANSACTION-BOUNDARY-CORRECTION-01` para `2203`–`2207`; **`-02`** para
> `2208`–`2211`). Os **nove** arquivos são multi-statement e declaram `BEGIN;`
> antes do primeiro statement e `COMMIT;` depois do último — sem depender do
> comportamento implícito do executor. Paridade com `2165`–`2168`/`2172`–`2173`,
> já aplicadas assim. Compatibilidade provada: **zero** comandos que exijam
> execução fora de transação nos nove. O caso mais crítico é a `2209`, em que
> `CREATE UNIQUE INDEX` e `ADD CONSTRAINT … USING INDEX` passam a ser atômicos
> entre si — falha entre os dois deixaria índice órfão sem constraint,
> bloqueando o gate da `2215`. Ver `ROLLOUT-ORDER.md`, seção "Atomicidade por
> arquivo — `2203`–`2211`".
>
> **Segurança** (`SECURITY-SEED-HARDENING-01`, B3): as **5** tabelas do eixo
> têm `ENABLE ROW LEVEL SECURITY` + policy `catalog_admin_select` +
> `REVOKE ALL … FROM anon, authenticated, service_role` + `GRANT SELECT` a
> `authenticated`. `service_role` recebe **SELECT e só**, nas 3 tabelas que a
> Edge lê — zero superfície de escrita direta.
| `2208` | `card_variant.edition_context_profile_id` | aditivo, nullable |
| `2209` | `uq_card_variant_identity` | identidade de 4 componentes |
| **`2210`** | **identidade do staging** (`uq_cvir_row_identity` + shape guard) | **NOVO — Blocker 1** |
| **`2211`** | **`internal.resolve_variant_row_axes()`** | **NOVO — Blocker 2: contrato terminal único** |
| `2830` | harness de validação | **114 automáticos + 4 pendentes + 3 manuais**, 14 seções |
| **`2212`** v3.0 | **resolução OPERACIONAL** (ex-backfill global) | **OP-BOUNDARY 4·7** |
| **`2833`** v2.0 | **matriz de state machine job-aware** (11 gates) | **OP-BOUNDARY 1·3** |
| **`2214`** v3.0 | **guard de transição OPERACIONAL** (job-aware) | **OP-BOUNDARY 1·2·8** |
| **`2215`** | **DROP das 2 identidades antigas de `card_variant`** | **Correção 1** |
| **`2216`** | **DROP das 2 identidades antigas de staging** | **Correção 1** |
| **`2217`** v2.0 | **EXPAND — cria `write_card_variant` de 7 args, sem DEFAULT; preserva a de 6** | Correção 7 · `WRITER-EXPAND-CONTRACT-CORRECTION-01` |
| **`2223`** | **CONTRACT — prova database-wide de zero caller e `DROP` da de 6 args** | `WRITER-EXPAND-CONTRACT-CORRECTION-01` |
| **`2230`·`2231`·`2232`** | seeds 115 / 173 / mappings (classe **B**) | Correção 6 |
| **`2832`** | validação do backfill (10 casos) | Correção 5 |
| **`2840`** | probe **T1** — único probe LIVE restante | Correção 10 |
| **`edge/*.patch` · `edge/*.test.ts`** | patch reproduzível + 7 testes Deno | Correção 8 |
| **`2831`** | **simulação** da decomposição legada (`ROLLBACK`) | ex-`2210`; **não é migration** — Blocker 7 |

### O que foi herdado de Printing (2165–2174) — e o que **não** foi

**Herdado, porque provado:** N:N como fonte da verdade · `traits_signature` distinta e ordenada, selada por trigger · profile por conjunto exato · resolução por igualdade de array (nunca `LIKE`/concatenação) · composição imutável após commit · zero criação automática durante import · same-Game por FK composta · fail-closed.

**Deliberadamente diferente, porque a semântica é outra:**

| Diferença | Razão |
|---|---|
| `family` existe no trait | Printing tem vocabulário quase fechado; aqui são 115 átomos que precisam virar facetas de UI sem denormalizar rótulo |
| `display_order` único **por família** | ordenar dentro da faceta, não globalmente |
| `display_order` esparso no profile (passo 10) | cada temporada competitiva insere átomos novos; renumerar tudo a cada ano seria insustentável |
| `external_set_id` no mapping (2 índices parciais disjuntos) | o mesmo token pode ter alvo distinto por era — `set-logo` é o caso real e medido |
| `raw_field` restrito a `stamp`/`subtype` | Printing consome `subtype`/`stamp`; aqui o domínio é **menor de propósito** — `foil` fica fora até B3 |

---

## 4. Identidade — `UNIQUE(4) NULLS NOT DISTINCT`

```sql
UNIQUE NULLS NOT DISTINCT
  (card_id, variant_type_id, printing_profile_id, edition_context_profile_id)
```

**Semântica:** `NULL` significa *"sem esse eixo"* — um **valor**, não desconhecido. É exatamente o que `NULLS NOT DISTINCT` expressa.

### Provas exigidas pelo mandato

| Item | Status | Evidência |
|---|---|---|
| PostgreSQL 17.6 | ✅ | `PostgreSQL 17.6 on aarch64-unknown-linux-gnu`; `NULLS NOT DISTINCT` desde 15 |
| `ON CONFLICT` existente | ✅ **zero risco** | **Nenhuma** das 12 funções que tocam `card_variant` usa `ON CONFLICT` |
| Tratamento de `unique_violation` | ⚠️ **achado** | **Nenhuma** trata `23505`/`unique_violation`. Dependem de guard prévio. Ver Blocker B1 |
| Queries existentes | ✅ | Nenhuma referencia os índices por nome; `WHERE printing_profile_id IS NULL` continua válido |
| Dump/restore | ✅ **não aplicável** | Provado em `TOOLING-PROOF.md`: o projeto **não usa** `pg_dump`/restore. Sem `supabase/migrations/`, sem CLI de DB, sem CI de banco |
| Schema diff | ✅ **não aplicável** | idem — nenhum `db diff`/`db pull` no repositório |
| `apply_migration` aceita a cláusula | ⚠️ **único residual** | Teste de TEMP TABLE scriptado em `TOOLING-PROOF.md`; é o **primeiro passo** do Gate A |
| Performance | ✅ desenho | 1 índice (~1,5 MB) contra 4 parciais; serve 3 prefixos de leitura |

### Contratos impactados — classificação em 5 categorias (Blocker 4)

A versão 1.0 chamava os 12 objetos de "consumidores", achatando papéis muito diferentes. **Corrigido.** O inventário completo está em **`IMPACTED-CONTRACTS.md`**; resumo:

| Cat. | Papel | Qtd | Natureza da mudança |
|---|---|---:|---|
| **A** | **Write path** — escrevem `card_variant` | 4 | **bloqueante**: precisam emitir os 4 componentes |
| **B** | **Routing / staging** — resolvem eixos ou leem `normalized_data` | 6 | **bloqueante**: passam a chamar `resolve_variant_row_axes()` |
| **C** | **Read models** — leem identidade para projetar | 5 | exibem/agrupam pelo 4º componente |
| **D** | **Edge producer** — `import-card-variants` | 2 arquivos | **bloqueante**: chave de matching de 3 → 4 partes |
| **E** | **Não impactados** — provados por leitura | 9 | nenhuma ação |

**Prova de cobertura negativa:** os **6** callers de `internal.compute_variant_residual_signature()` estão **todos** em B — nenhum ficou fora. A categoria E não é "o resto": cada um dos 9 foi lido e a razão da não-impactação está registrada.

> **Nenhum contrato pode continuar ignorando Edition Context silenciosamente.** A+B+D são bloqueantes para o gate físico.

### Identidade do staging — reconciliada (Blocker 1)

A identidade de `card_variant` não valia nada se `catalog_variant_import_row` continuasse deduplicando por 3 componentes: duas rows legítimas que diferem **só** em Edition Context seriam colapsadas **antes** de chegarem ao writer.

**Medido no LIVE:** existiam **2 índices parciais** sobre `normalized_data`, ambos ignorando Edition Context. `2210` os substitui por **um único índice total**:

```sql
CREATE UNIQUE INDEX CONCURRENTLY uq_cvir_row_identity
    ON public.catalog_variant_import_row (
        job_id, card_id,
        (normalized_data ->> 'variant_type_id'),
        internal.axis_identity_token(normalized_data, 'printing_profile_id'),
        internal.axis_identity_token(normalized_data, 'edition_context_profile_id'))
    WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL;
```

**Contrato tri-state — distinguível só por `jsonb_typeof`:**

| Estado | JSONB | `jsonb_typeof` | Token | Significado |
|---|---|---|---|---|
| **ausente** | chave não existe | `NULL` | `'A'` | eixo **não resolvido** |
| **JSON null** | `{"k": null}` | `'null'` | `'N'` | resolvido **sem** o eixo |
| **UUID** | `{"k": "…"}` | `'string'` | `'U:…'` | resolvido **com** o eixo |

**Por que `NULLS NOT DISTINCT` foi REJEITADO aqui** (e aceito em `card_variant`): o tri-state vive **dentro** do JSONB. `->>` devolve SQL `NULL` tanto para *ausente* quanto para *JSON null* — **significados opostos**. `NULLS NOT DISTINCT` operaria sobre um `NULL` já ambíguo e colapsaria os dois. `axis_identity_token()` (`IMMUTABLE`, `PARALLEL SAFE`, `search_path=''`) resolve a ambiguidade **antes** do índice, tornando-o total em vez de parcial — o modo de falha de um predicado parcial errado é **silencioso**.

**Prova exigida pelo mandato — duas rows do mesmo job coexistindo:**

```sql
-- mesmo job_id, mesmo card_id, mesmo variant_type_id, mesmo printing (JSON null)
-- diferindo SOMENTE em edition_context_profile_id
{"variant_type_id":"…T", "printing_profile_id":null, "edition_context_profile_id":null}   -- token N
{"variant_type_id":"…T", "printing_profile_id":null, "edition_context_profile_id":"…W23"} -- token U:…
```
Sob o índice antigo: **colisão** (`23505`). Sob `uq_cvir_row_identity`: **duas rows válidas**. Casos `S1`–`S4` do harness.

**Guard de forma** — `internal.guard_cvir_normalized_shape()`: (a) cada chave de eixo, se presente, é `null` **ou** `string`; nunca número/array/objeto; (b) row `VALID` exige **ambas** as chaves presentes — não existe "VALID com eixo não resolvido".

### Routing — contrato terminal único (Blocker 2)

`internal.resolve_variant_row_axes(p_raw_data, p_game_id, p_asset_source_id, p_external_set_id)` é o **único** ponto onde a decisão dos eixos acontece. Retorna 10 campos: `printing_state` · `printing_profile_id` · `printing_trait_ids[]` · `edition_context_state` · `edition_context_profile_id` · `edition_context_trait_ids[]` · `residual_type` · `residual_foil` · `residual_subtype` · `residual_stamp[]`.

**Não duplica lógica:** *chama* `internal.compute_variant_residual_signature()` (que já resolve o gate de escopo 2198 e o Printing) e só então sobrepõe Edition Context ao residual que sobrou. Precedência **scoped > global**, um único nível, sem desempate implícito. Nenhum caller re-implementa a ordem 2→3 do pipeline.

---

## 5. Decomposição legada — **365 READY**, nenhuma a mais

| Partição | Tipos | `card_variant` | Elegível a `UPDATE`? |
|---|---:|---:|:---:|
| **READY_TO_DECOMPOSE** | 63 | **365** | ✅ |
| **HOLD_INDETERMINATE** | 5 | **107** | ❌ |
| **ZERO_VARIANT_TYPE** | 3 | 0 | ❌ (nada a mover) |
| **NÃO_CONTAMINADO_FINISH** (SET-LOGO EX11–EX16) | 2 | 555 | ❌ (já correto) |
| **FINISH_PURO** | 26 | 23.866 | ❌ |
| **Σ** | — | **24.893** ✔ | |

**Colisões projetadas contra a identidade NOVA: 188 de 365** (51,5%). Não são obstáculo — são a prova de que o quarto componente é necessário: sob a identidade atual, esses 188 `UPDATE` violariam `uq_card_variant_card_type_no_printing`.

### READY_STRUCTURAL ≠ elegível a migration (Blocker 5)

| Partição | `card_variant` | Migra? |
|---|---:|:---:|
| **READY_STRUCTURAL** | **365** | — |
| ├ **READY_UNCONDITIONED** | **285** | ✅ |
| └ **READY_PRICING_CONDITIONED** | **80** | 🔒 bloqueado |

Os 80 condicionados vêm de **dois** tipos, não um: `STAFF_HOLO` (17 `pscid` + 1 `psvm`) e **`SET_LOGO_REVERSE` (1 `pscid`)** — este segundo não havia sido identificado na versão 1.0. O guard é **executável**, derivado do LIVE, não comentário: a migration real aborta se qualquer `card_variant_id` do lote tiver `pricing_source_card_identity` ou `pricing_source_variant_mapping` associado. Detalhe em `HOLD-MANIFEST.md` §H6.

**Invariantes obrigatórios da migração real (`2213`, pós-Gate A):**

- `card_variant.id` **preservado** — decomposição é `UPDATE`, nunca `DELETE`+`INSERT`
- `variant_order` **preservado**
- `is_default` **preservado**
- lineage **preservado** (`resulting_variant_id` 23.955 · `matched_variant_id` 1.129 intactos por consequência)
- **nenhuma linha HOLD elegível** — guard por lista, não por comentário
- collision gate simula a identidade **nova** antes de qualquer escrita

Mapa linha a linha: **`MIGRATION-MAP-365.md`** (com os dois tipos condicionados marcados 🔒).

### Simulação × migration (Blocker 7)

`2831_simulate_legacy_decomposition_365.sql` termina em `ROLLBACK`. **Um artefato que termina em `ROLLBACK` é simulação, não migration executável** — mantê-lo numerado como `2210`, na mesma faixa das DDLs, convidava a execução acidental. Foi **renumerado para a faixa 28xx** (validação/simulação), com cabeçalho declarando explicitamente o que é. A migration real será **`2213`**, escrita depois do Gate A, operando sobre **285** linhas e terminando em `COMMIT`.

---

## 6. HOLD — guards explícitos, não comentário

Cinco universos **intocados**, cada um com guard executável no `2210` e no harness:

| Universo | Qtd | Guard |
|---|---:|---|
| Legacy HOLD (`SET_LOGO_*` sem evidência + `PROMO_STAMPED`) | **107** | lista de `card_variant_id` congelada |
| Staging EX7–EX10 sem Finish canônico | **379** | `SET-LOGO-EX-ERA-FINISH-01` |
| Staging indeterminadas `foil`/programa | **57** | decisão editorial pendente |
| `PROMO_STAMPED` | 33 (⊂ 107) | mandato próprio |
| Pricing orphan (489 `pscid` + 5 `psvm`, **nunca somados**) | — | `PRICING-CATALOG-VARIANT-RECONCILIATION-01` |
| **READY_PRICING_CONDITIONED** (`STAFF_HOLO` + `SET_LOGO_REVERSE`) | **80** | **H6** — guard executável derivado do LIVE |

Detalhe: **`HOLD-MANIFEST.md`**.

---

## 7. SET-LOGO — fronteira respeitada

- **EX11–EX16 (555 Variants):** permanecem **FINISH**. Nenhuma decomposição nesta frente.
- **EX7–EX10 (379 staging):** pertencem ao eixo **FINISH**; alvo canônico é da frente `SET-LOGO-EX-ERA-FINISH-01`. **Edition Context não as absorve.**
- **DP1 · SWSH9 · SVP (44 materializadas + 5 staging):** documentados → **EDITION_CONTEXT**, dentro do escopo.

---

## 8. Pricing

Fora desta frente. `STAFF_HOLO` tem dependência conhecida — **17 `pricing_source_card_identity` + 1 `pricing_source_variant_mapping`** (nunca somados) — e sua decomposição fica **condicionada ao contrato de compatibilidade** definido em `PRICING-CATALOG-VARIANT-RECONCILIATION-01`. `POKEMON_CENTER_EXCLUSIVE` (24 + 3) tem 0 Variants: não há o que decompor.

---

## 9. Segurança e performance

**Segurança:** `SECURITY DEFINER` apenas nas trigger functions e writers admin · `search_path=''` em todas · writers admin-only via `is_admin()` · grants mínimos (`SELECT` para `authenticated`, escrita só `service_role`) · same-Game por FK composta · zero escrita direta de frontend · `audit_log` em `catalog_admin_action_log`.

**Performance:** 1 índice de identidade substitui 2 (futuramente 4) · resolução set-based, **um lookup de Edition Context por row**, sem N+1 · índice parcial em `edition_context_profile_id` (~1,5% preenchido) · nenhum índice redundante criado — a avaliação de remover `ix_card_variant_card_id` (coberto pelo prefixo da UNIQUE) fica para o harness, com `EXPLAIN` real.

---

## 9-BIS. Concorrência (Blocker 8)

Detalhe em **`CONCURRENCY-DESIGN.md`**. Contrato:

1. **Lock** — `SELECT … FROM public.card WHERE id = … FOR UPDATE` serializa por Card antes de qualquer escrita de Variant.
2. **Matching** — busca pela identidade de 4 componentes com `IS NOT DISTINCT FROM` (nunca `=`, que devolve `NULL` em comparação com `NULL`).
3. **Rede de segurança** — `EXCEPTION WHEN unique_violation`: relê pela mesma identidade. Se achar, é **corrida benigna** ⇒ `UNCHANGED`. Se não achar, é **erro sistêmico** ⇒ `CARD_VARIANT_IDENTITY_CONFLICT_UNRESOLVED`.
4. **Nenhum SQLSTATE cru chega à UI** — o único caminho de saída é um código de negócio nomeado.

Isso fecha o achado B1 da versão 1.0 ("nenhuma das 12 funções trata `23505`"): antes o guard prévio era a **única** defesa; agora há guard **e** rede.

---

## 9-TER. Ordem segura de rollout (Blocker 9)

**A ordem da versão 1.0 era insegura.** Ela estreitava a identidade (`2209`) *antes* de os produtores emitirem o 4º componente — janela em que uma escrita concorrente produziria estado não representável. Descartada.

A nova ordem tem **16 etapas** (`ROLLOUT-ORDER.md`), começando por **FREEZE de importação** e provando, etapa a etapa, quais estados são representáveis e qual é o rollback. Pontos críticos:

- o **backfill** da chave tri-state acontece **antes** do guard de forma, nunca depois (a cifra "24.020" desta linha estava STALE e foi eliminada na `BACKFILL-SEMANTICS-CORRECTION-01`);
- `2209` (identidade estreitada) só entra **depois** que A, B e D emitem 4 componentes;
- cada etapa declara o que é reversível e como.

---

## 9-QUATER. Impacto no Edge (Blocker 3)

`supabase/functions/import-card-variants/` — duas mudanças bloqueantes, ambas com linha exata em `IMPACTED-CONTRACTS.md`:

| Arquivo | Achado |
|---|---|
| `index.ts` (~1006) | `normalized_data` recebe `printing_profile_id` **sempre**, mas não tem chave de Edition Context. Precisa emitir `edition_context_profile_id` **sempre** (JSON `null` quando sem contexto) — do contrário toda row nasce no estado *ausente*, que o guard rejeita |
| `services/database.ts` (~511–521) | Chave de matching `` `${card_id}|${variant_type_id}|${part(printing)}` `` tem **3 partes**. Precisa de **4**, com a mesma disciplina tri-state do `axis_identity_token` |

**7 testes Deno** especificados (tri-state em ambos os eixos, matching 4-partes, colisão que deve deixar de colidir, forma inválida rejeitada).

---

## 10. UX / Display — o modelo suporta sem denormalizar

```
Finish  ·  Printing  ·  Edition Context
```

Badge = **só Finish**. Filtros = **três facetas independentes**, Edition Context agrupável por `family`. Profile = **rótulo de usuário**; traits só no detalhe. `code` estável + i18n por chave; composição por **template**, nunca concatenação. **Nenhuma string composta é persistida como identidade** — a identidade são quatro UUIDs.

---

## 11. Blockers

### Os 10 da CORRECTION-01 — todos fechados nesta revisão

| # | Blocker | Fechamento |
|---|---|---|
| 1 | Identidade do staging sem Edition Context | `2210` — índice total + tri-state + shape guard + VALID-requires-key; prova de coexistência nos casos `S1`–`S4` |
| 2 | Routing espalhado | `2211` — contrato terminal único, 10 campos, chamando (não duplicando) `compute_variant_residual_signature` |
| 3 | Edge não auditado | `IMPACTED-CONTRACTS.md` cat. D — 2 arquivos, linhas exatas, 7 testes Deno |
| 4 | "12 consumidores" achatados | 5 categorias A–E + prova de cobertura negativa dos 6 callers |
| 5 | READY sem qualificação | 365 = **285** + **80**, guard executável (`HOLD-MANIFEST.md` §H6) |
| 6 | `foil` legitimado no DDL | `CHECK (raw_field IN ('stamp','subtype'))`; `ck_cecem_foil_allowlist` removido |
| 7 | Simulação numerada como migration | renumerada `2210` → **`2831`**; migration real será `2213` |
| 8 | Concorrência não desenhada | `CONCURRENCY-DESIGN.md` — lock, matching, corrida benigna × erro sistêmico, zero SQLSTATE cru |
| 9 | Ordem de rollout insegura | `ROLLOUT-ORDER.md` — 16 etapas, FREEZE, backfill antes do guard |
| 10 | Tooling em aberto | `TOOLING-PROOF.md` — risco reduzido a **um** teste de `apply_migration` |

### Residuais após esta revisão

| # | Residual | Severidade | Gate |
|---|---|---|---|
| **R1** | `apply_migration` com `NULLS NOT DISTINCT` — teste de TEMP TABLE | **Baixa** | 1º passo do Gate A |
| **R2** | Tradução editorial dos 115 `code`, incl. 38 `DECK_PLAYER_*` | Média | Gate A |
| **R3** | `foil`-programa (57 linhas) segue indeterminado | Média | decisão editorial |
| **R4** | 80 READY condicionados a `PRICING-CATALOG-VARIANT-RECONCILIATION-01` | Média | mandato próprio |
| **R5** | Backfill semântico da chave (etapa 4 do rollout) — sem cardinalidade fixa | Média | Gate A |

**Nenhum residual impede este staging.** Todos são do gate de implementação.

---

## 12. Recomendação para o Gate A

**GO** para revisão física da proposta, com três provas obrigatórias antes de qualquer execução:

1. **`apply_migration` × `NULLS NOT DISTINCT`** — teste de TEMP TABLE (R1). É o primeiro passo; se falhar, toda a estratégia de identidade precisa ser rediscutida.
2. **Produtores** — implementar as categorias A, B e D (write path, routing/staging, Edge) **antes** de estreitar a identidade.
3. **Tradução editorial** — os 115 `code` canônicos, com `DECK_PLAYER_*` para os 38 de jogador (R2).

**Ordem de execução: as 16 etapas de `ROLLOUT-ORDER.md`.** A sequência linear da versão 1.0 foi descartada por criar janela insegura.

---

## 12-BIS. GATE A — auditoria estática (`EDITION-CONTEXT-AXIS-GATE-A-01`)

Resultado: **CORRECTION REQUIRED → corrigido nesta revisão.** 11 achados, dos
quais **6 eram fail-OPEN ou erro de execução**, não questões de redação.

### Achados corrigidos

| # | Sev. | Onde | Achado | Correção |
|---|---|---|---|---|
| **A1** | 🔴 | `2211` | Faltava filtro de `external_set_id` no `WHERE`. Com `p_external_set_id` NULL e sem mapping GLOBAL, o `LIMIT 1` elegia um mapping escopado a **outro Set** — vazamento cross-set | `WHERE` restringe a {scoped a ESTE Set} ∪ {GLOBAL}; desempate por `m.id` |
| **A2** | 🔴 | `2211` | `p.printing_state NOT IN (…)` avalia **NULL** se 2176 não devolver linha ⇒ o fluxo seguia para o eixo 3 com estado nulo | `RAISE` explícito antes do teste |
| **A3** | 🔴 | `2211` | `subtype` com mapping conhecido mas **inativo** caía no residual de Finish (fail-OPEN); `stamp` já retornava `NEEDS_REVIEW` | simetrizado |
| **A4** | 🟡 | `2211` | Saídas `NEEDS_REVIEW_*` descartavam `residual_subtype`/`residual_stamp` | residual preservado |
| **B1** | 🔴 | `2210` | **Exigido nominalmente pelo mandato como BLOCKER:** a regra de rebuild do índice de expressão não existia. Mudar `axis_identity_token()` corromperia `uq_cvir_row_identity` **em silêncio** | bloco `CONTRATO DE ESTABILIDADE` + regra no `COMMENT` + caso S2-BIS |
| **B2** | 🔴 | `2210` | Guard de forma só checava `jsonb_typeof`. `{"…":"banana"}` passava e virava o token `U:banana`. O harness (S9) **afirmava** essa prova | validação de formato UUID nos dois eixos |
| **B3** | 🔴 | `2209`·`2210` | `CREATE INDEX CONCURRENTLY` não roda em transação, e `apply_migration` transaciona. `grep -rl "INDEX CONCURRENTLY" database/schema database/migrations` → **vazio**: zero precedente | passos isolados anotados + teste **T2** em `TOOLING-PROOF.md` + plano B sob FREEZE |
| **C1** | 🟠 | `IMPACTED-CONTRACTS` | "6 chamadores" era memória, não medição: listava 2 que **não** chamam (`lookup_variant_type_for_row`, `admin_preview_…`) e omitia 1 que chama 2× (`create_card_printing_profile_with_backfill`) | recontado sobre `database/schema/`: **5 funções, 7 call sites**, com arquivo e linha |
| **C2** | 🟠 | `2207` | `CHECK` correto, mas o `COMMENT ON TABLE` ainda dizia *"raw_field restrito a stamp/subtype/foil; foil com allowlist"* — o comentário persiste no banco como documentação | reescrito |
| **C3** | 🟠 | `MIGRATION-MAP` | Tabela somava **384**, não 365 (linha residual em "~43"; soma das nomeadas = 341) | residual = **24**; conferência aritmética explícita |
| **C4** | 🟡 | `ROLLOUT-ORDER` | Etapa 9 justificada como *"superconjunto compatível"* — falso: sob a identidade antiga duas Variants diferindo só em contexto colidem. A conclusão ("sem janela") só se sustenta **pelo FREEZE** | justificativa corrigida; etapa 5 idem |

### `2831` — cinco defeitos, reescrito (v2.0)

Era o artefato mais frágil do pacote:

1. `PASSO 4` referenciava `p.finish_target_id` e `p.edition_context_profile_id`, **colunas que não existiam** em `plan_365` — abortaria no `UPDATE`.
2. Dois `-- placeholder:` embutidos. O gate de colisão usava o code `'STANDARD'` fixo ⇒ **não testava colisão nenhuma**, e a cifra de "188 colisões previstas" não era produzida pelo artefato.
3. Gates exigiam **365** enquanto a decisão H6 é **285** — e o próprio rodapé dizia que `STAFF_HOLO` fica fora. Contradição interna.
4. O guard `PRICING_CONDITIONED_IN_PLAN` que `HOLD-MANIFEST` H6 afirma existir "no 2831" **não estava no arquivo**.
5. `DISTINCT ON (cv.id)` sem `ORDER BY` correspondente ⇒ evidência **não-determinística**.

Na v2.0 o destino de acabamento é derivado de verdade, pelo caminho canônico:
`internal.resolve_variant_row_axes()` (2211) → `internal.lookup_variant_type_for_row()` (2192, assinatura verificada em `database/schema/2192_…:509`). Sem placeholder, com gate de colisão intra-plano, guard de Pricing derivado do LIVE e prova de preservação de `id`.

### Fecho end-to-end

| Elo | Provado por |
|---|---|
| RAW → size | `2176` (inalterado) · R3 |
| size → Printing | `2176` (inalterado) · §5 preservação |
| Printing → Edition Context | `2211` ordem fixa · R4 · R5 |
| EC → residual Finish | `2211` · R8 (invariante de soma) |
| residual → Variant Type | `2192` `lookup_variant_type_for_row` · R4 |
| → staging identity | `2210` `uq_cvir_row_identity` · S1–S11 |
| → `card_variant` identity | `2209` `UNIQUE(4) NULLS NOT DISTINCT` · 4.1–4.8 |

**Nenhum caminho antigo ignora Edition Context** — os 5 chamadores de 2176 passam por 2211 (etapa 7 do rollout) e a Edge passa a emitir a chave (etapa 8), **antes** de a identidade ser estreitada (etapa 10).

### Blockers que permanecem ABERTOS

| # | Blocker | Por quê continua aberto |
|---|---|---|
| **R1 / T1** | `apply_migration` aceitar `NULLS NOT DISTINCT` | exige execução — vedada nesta rodada |
| **R2 / T2** | `apply_migration`/`execute_sql` aceitarem `INDEX CONCURRENTLY` | idem. **Zero precedente no repositório** |

Ambos têm SQL mínimo, resultado esperado, postcheck e cleanup em `TOOLING-PROOF.md`. São o **passo −1** do Gate B.

---

## 12-QUINQUIES. OPERATIONAL BOUNDARY — "operacional" era o job, não a row

### O defeito

Predicado anterior: `validation_status = 'VALID' AND persistence_status = 'PENDING'`.
Medido no LIVE:

| Recorte | Qtd |
|---|---:|
| `VALID` total | 24.372 |
| `VALID` + `PENDING` | **415** — *todas* de jobs `CANCELLED` |
| └ decision `SKIPPED` / `PENDING` | 414 / 1 |
| `STAGED`/`CONFIRMING` + `PENDING` + `NEEDS_REVIEW` | 1.642 |
| `STAGED`/`CONFIRMING` + `PENDING` + `VALID` (⇒ CONFIRMÁVEL) | **0** |

**Errava nas duas direções:** atingia 415 rows históricas e protegia zero
operacionais. Causa raiz: `persistence_status` descreve a **row**;
"operacional" é propriedade do **job**.

### Definição formal — derivada de `2145`, não inferida

| Linha | Contrato |
|---|---|
| `2145:270` | `job.status NOT IN ('STAGED','CONFIRMING')` ⇒ recusa |
| `2145:286·307` | elegível: `PENDING` + `decision ∈ (APPROVED, SKIPPED)` |
| `2145:314` | `SKIPPED` ⇒ `UNCHANGED`, sem escrita |
| `2145:324` | `APPROVED` exige `VALID` |

```
OPERACIONAL ≡ job ∈ (RECEIVED,PROCESSING,STAGED,CONFIRMING) ∧ PENDING
CONFIRMÁVEL ≡ job ∈ (STAGED,CONFIRMING) ∧ PENDING ∧ APPROVED ∧ VALID
HISTÓRICO   ≡ o resto — inclusive CANCELLED com row PENDING
```

O guard protege **OPERACIONAL**, não `CONFIRMÁVEL`: barrar só na confirmação
seria tarde — a row já teria sido exibida ao revisor como pronta.
Detalhe em `OPERATIONAL-BOUNDARY.md`.

### `CHECK` não serve

`CHECK` de `catalog_variant_import_row` não enxerga `job.status`. Não se
força uma regra row-local falsa só para poder usar `CHECK`. Proteção em
**três camadas**: trigger job-aware (`2214`) · routing/propagation
(`2211`·`2219`) · revalidação defensiva no confirm (`2218`).

### Backfill global ELIMINADO

**Nenhum requisito físico real** exige a chave nas rows terminais: o guard é
operacional; `uq_cvir_row_identity` aceita o token `'A'`; `2216` tem
pré-condição operacional; o confirm recusa job terminal; nenhum read model
as exibe. Reescrever ~23.957 rows seria mutação de histórico sem
contrapartida.

`2212` v3.0 opera só sobre `job vivo + PENDING` — **1.642 rows**. `P5`/`P6`
provam que nada fora desse escopo foi tocado, `CANCELLED` explicitamente.

### `CANCELLED` é terminal

As 415 não são backlog: `2145:270` recusa confirmar job cancelado, e 414
têm decisão `SKIPPED` registrada. Não exigem a chave, não são reativadas,
não recebem `JSON null`. **A `2833` v1.0 afirmava que o predicado "não
atinge terminal" — atingia 415.** SM5 agora **mede** em vez de afirmar.

### Lineage (Correções 5 e 6)

`2213` altera `card_variant` **e** o lineage das 285, **atomicamente** —
metade disso criaria o híbrido proibido: `variant_type_id` legado apontando
para Variant já decomposta. Os 80 de Pricing e o HOLD: nenhuma reconciliação.
`LINEAGE-STRATEGY.md`.

### E1 deixou de bloquear a fundação

| Bloco | Depende de E1? |
|---|---|
| Fundação estrutural · routing · Edge · identidade | **NÃO** |
| Resolução das 1.642 · legacy 285 | **SIM** |
| `2212` (as 1.642) | **SIM** |

**A fundação física inteira pode ser executada sem o vocabulário.**

---

## 12-QUATER. BACKFILL SEMANTICS — o blocker mais sério do ciclo

### O defeito

A regra do backfill era **`VALID → JSON null`**. É falsa. Medido no LIVE:

| Variant Type | rows | estado |
|---|---|---|
| `SATANDARD_REWARDS` | 51 INSERTED + 1 UNCHANGED | todos VALID |
| `STAFF_HOLO` | 40 INSERTED + 36 UNCHANGED | todos VALID |
| `SET_LOGO_REVERSE` | 185 INSERTED + 38 UNCHANGED | todos VALID |
| `SET_LOGO_STANDARDS` | 484 INSERTED | VALID |

Essas rows **são** contexto de edição. `JSON null` nelas afirma *"resolvido
SEM contexto"* — uma mentira gravada, com aparência de decisão tomada, que o
guard seguinte carimbaria como válida. **`JSON null` nunca é placeholder de
migração; é uma afirmação.**

### O contrato novo — três destinos, decididos pelo routing

| `edition_context_state` (2211) | destino | significado |
|---|---|---|
| `RESOLVED_WITH_EC_PROFILE` | **UUID** | resolvido COM contexto |
| `RESOLVED_NO_EDITION_CONTEXT` | **JSON null** | resolvido SEM contexto |
| qualquer `NEEDS_REVIEW_*` · `NOT_EVALUATED` | **AUSENTE** | ainda indeterminado |

O terceiro destino é o coração da correção: **row indeterminada fica sem a
chave.** É o estado `'A'` do tri-state, e é a verdade.

### Lineage não é 1:1

`B = 365` conta `card_variant` **estruturais**, não rows de staging.
`STAFF_HOLO` = 40 Variants, **76 rows**. O backfill é **por row**, dirigido
pelo `raw_data` da própria row — sem `DISTINCT ON`, sem "uma row por
Variant". O caso `V8` prova isso.

### Guard: global → operacional

```
validation_status = 'VALID' AND persistence_status = 'PENDING'
  →  edition_context_profile_id PRESENTE
```

*O que ainda pode virar Card Variant precisa ter o eixo resolvido; o que já
virou não precisa mentir.* Mais duas garantias: **G2** não-regressão (row
VALID que tem a chave nunca a perde, terminal inclusive) e **G3** forma.

O predicado é **candidato, não premissa** — `2833` o prova com 8 gates contra
as combinações reais, e aborta se aparecer um `persistence_status` fora do
vocabulário conhecido. O trigger passou a escutar `persistence_status`;
sem isso a transição terminal → PENDING escaparia (caso `f` do postcheck).

### Baseline é variável

"24.020" estava **STALE** — o LIVE media **24.372**. Eliminado de todos os
artefatos. Baseline é capturado após o FREEZE, em TEMP TABLE, como
**evidência do momento**; todos os gates são invariantes e pós-condições.

### DAG remanejado

O backfill semântico **depende dos seeds** — sem vocabulário, tudo resolveria
`ABSENT`. Nova sequência: estrutura → **seeds** → routing → **FREEZE** →
baseline → backfill → postcheck → guard operacional → identidade terminal →
writers/Edge → unfreeze. **28 passos.** O FREEZE deixou de ser a etapa 0 e
abre logo antes do baseline.

**Consequência declarada:** o backfill herdou o bloqueio editorial **E1**.

### Harness

Seção **B reescrita** (12 casos: V1–V12) — a anterior provava a regra errada,
o que é pior que não provar nada. Seção **M** nova (8 casos, state machine).
**D7** novo. Total: **100 casos automáticos em 11 seções** + 3 manuais.

---

## 12-TER. GATE A FINAL — as 10 correções

### Correção 1 — os 4 índices antigos · **era BLOCKER, confirmado**

O relatório anterior afirmava que `2209`/`2210` substituíam as identidades
antigas **e** que a verificação final acusava zero `DROP`. As duas coisas
eram verdadeiras — e é exatamente aí que estava o defeito: **os quatro DROPs
estavam comentados.**

```
2209:65  -- DROP INDEX CONCURRENTLY public.uq_card_variant_card_type_no_printing;
2209:66  -- DROP INDEX CONCURRENTLY public.uq_card_variant_card_type_printing;
2210:121 -- DROP INDEX CONCURRENTLY public.uq_cvir_job_card_type_no_printing;
2210:122 -- DROP INDEX CONCURRENTLY public.uq_cvir_job_card_type_printing;
```

Com eles ativos, duas Variants que diferem só em contexto continuam sendo
rejeitadas com `23505`. **O eixo não existiria na prática.**

**Sequência exata, agora executável e sem janela desprotegida:**

| # | Passo | Artefato | Prova |
|---|---|---|---|
| **1** | criar a identidade nova | `2209` · `2210` | índice `UNIQUE` + `CONSTRAINT`; ao fim convivem as 3 garantias (seguro: as antigas são **mais** restritivas) |
| **2** | remover as antigas | `2215` · `2216` | cada `DROP` precedido de prova de que a nova existe, é única e é válida; `2216` também exige backfill concluído |
| **3** | provar que só a nova restou | `2215` PASSO 4 · `2216` PASSO 4 | `COUNT` de índices únicos contendo `variant_type_id` (resp. `job_id`) = **1**; ortogonais 1/1/1 |

`2216` PASSO 5 ainda executa a prova **S4** em `SAVEPOINT`: duas rows do
mesmo job/card/finish/printing coexistindo. A coexistência deixa de ser
afirmada e passa a ser exercitada no ato do `DROP`.

### Correção 2 — `CONCURRENTLY`: **decisão A acatada, T2 eliminado**

| | **A — índice normal sob FREEZE** ✅ | B — `CONCURRENTLY` |
|---|---|---|
| Lock | `ShareLock` (bloqueia escrita, não leitura) | `ShareUpdateExclusive` |
| Duração | 24.893 linhas / 9.064 kB ⇒ centenas de ms | 2 varreduras + espera |
| Transacional | **sim** | não |
| Precedente | todos os índices | **zero** |
| Falha parcial | aborta tudo | índice `INVALID` residual |

**Nenhuma prova concreta torna A inadequado.** O único benefício de B é
irrelevante sob FREEZE. `CONCURRENTLY` removido de `2209`/`2210`; `2215`/`2216`
nascem sem ele; **T2 deixou de existir**.

### Correção 3 — DAG real

A contradição era real: `2210 depende de 2208`, mas `2210` estava em 5 e
`2208` em 6. Causa: a "ordem" era lista de leitura, não derivada do grafo.
**`DAG.md`** traz o grafo, a tabela predecessor/sucessor/paralelo por
artefato e a ordem topológica de **26 passos**. `2208` → etapa 3;
`2210` → etapa 6.

### Correção 4 — A / B / C

**`PENDING-ARTIFACTS.md`.** Classificação original A/B/C.

> **Superado em parte pela revisão 1.6.** O caminho de escrita saiu da classe
> B: `2218`–`2222` estão escritos. A classificação vigente, em sete classes,
> é a de **`PACKAGE-STATUS.md`** — leia aquele documento para o estado atual.
> O pacote **continua não sendo implementation-ready**, agora por dois
> bloqueios de DADO e DECISÃO (seeds `2230`-`2232` e o inexistente `2213`),
> não por código faltante.

### Correção 5 — backfill

`2212` (backfill) + `2832` (10 provas) + `2214` (guard estrito). Ordem
imposta: **shape permissivo → backfill → prova → guard**. O `2210` foi
rebaixado: a exigência da chave de Edition Context saiu dele.

Universo: rows **VALID** recebem `JSON null`. **NEEDS_REVIEW não recebem** —
dar-lhes `null` seria promover pendência a decisão (caso `B3`). Idempotente
por `WHERE NOT jsonb_exists(...)` (`B9`). `validation_status`,
`decision_status`, `persistence_status`, lineage e contadores provados
intactos (`B4`–`B6`).

### Correção 6 — seeds

`2230`/`2231`/`2232`: **estruturalmente completos, lexicalmente vazios**, e
abortam se o vocabulário faltar. Preenchê-los por transliteração de token
TCGdex violaria a regra que a própria `2203` grava no schema.
`SEED-COVERAGE.md` lista os gates (115 · 173 · 21 · 40 · 38 · A∪B 100%) e os
bloqueios **E1 · E2 · E3 · E4**.

### Correção 7 — contratos

`2217` (`write_card_variant` v3.0) **escrito e completo**. `2218`–`2222`
foram numerados e especificados com âncora e invariante nesta revisão —
**corpo não escrito** à época, declarado classe B. **Escritos por inteiro na
revisão 1.6**; ver `PACKAGE-STATUS.md`, classe A.2. Achado no caminho: matching e lock **não estão** no
writer (a canônica `2143` é `INSERT` puro); estão no confirm. `CONCURRENCY-DESIGN.md`
foi corrigido.

### Correção 8 — Edge

`edge/import-card-variants.patch` (3 diffs, âncoras verificadas) e
`edge/edition-context.test.ts` (7 testes). **T3 e T7 falham contra o código
de hoje, por desenho** — são a prova executável de que o patch é necessário.
`supabase/` não foi tocado.

### Correção 9 — harness reconciliado

A conta de 73 tinha **8 parcelas para 9 seções**. A parcela ausente era a
**Seção 6, que só tem casos manuais** e nunca somou — a v3.0 não dizia isso.
Agora são **11 seções**, 10 automáticas:

```
12 + 8 + 7 + 8 + 12 + 12 + 8 + 10 + 6 + 6 = 89
 1   2   3   4    S    R    K    B    D    5      (Seção 6 = 3 manuais)
```

Seções novas: **B** (backfill, 10) e **D** (identidade terminal, 6 — os
índices antigos removidos e "somente a nova vigente", que nenhum caso
anterior cobria).

### Correção 10 — T1

`2840`: SQL mínimo, nome de migration (`2840_probe_nulls_not_distinct`),
resultado esperado, postcheck, cleanup e prova de resíduo zero. Prova
**estrutural** (`indnullsnotdistinct`) *e* **comportamental** — porque o modo
de falha que importa é a cláusula ser aceita e ignorada. **Não executado.**

---

## 13. Arquivos desta revisão

| Ação | Arquivo |
|---|---|
| **criado** | `2210_reconcile_staging_identity_edition_context.sql` |
| **criado** | `2211_create_resolve_variant_row_axes_contract.sql` |
| **criado** | `CONCURRENCY-DESIGN.md` · `ROLLOUT-ORDER.md` · `TOOLING-PROOF.md` |
| **renomeado** | `2210_decompose_legacy_365.sql` → `2831_simulate_legacy_decomposition_365.sql` |
| **editado** | `2207` (`raw_field` restrito) · `2830` (v3.0, 73 casos) · `HOLD-MANIFEST.md` (§H6) · `MIGRATION-MAP-365.md` (🔒) · `IMPACTED-CONTRACTS.md` (reescrito em 5 categorias) · `README.md` (este) |

### Revisão 1.6 — `WRITE-PATH-STAGING-01`

| Ação | Arquivo | Item do mandato |
|---|---|---|
| **criado** | `2218_redefine_admin_confirm_catalog_variant_import.sql` (502 li) | 1 · 2 · 4 · 5 |
| **criado** | `2219_redefine_apply_variant_type_mapping.sql` (406 li) | 1 · 6 · 7 |
| **criado** | `2220_redefine_variant_type_mapping_read_contract.sql` (479 li) | 1 · 6 · 12 |
| **criado** | `2221_redefine_admin_resolve_printing_mapping.sql` (595 li) | 1 · 6 |
| **criado** | `2222_redefine_create_card_printing_profile_with_backfill.sql` (756 li) | 1 · 6 |
| **criado** | `READ-MODELS-AUDIT.md` | 12 |
| **criado** | `PACKAGE-STATUS.md` | 15 |
| **reescrito** | `edge/import-card-variants.patch` → rev 2.0 (5 diffs, **D3 fechado**) | 9 · 10 |
| **reescrito** | `edge/edition-context.test.ts` → rev 2.0 (**8** testes) | 11 |
| **editado** | `PENDING-ARTIFACTS.md` (B.2 → classe A; B.3 rev 2.0; D3 fechado) | 15 |
| **editado** | `2219` · `2220` (comentário de corpo que causava falso-positivo no postcheck) | — |
| **editado** | `README.md` (este) | — |

**Correção factual aplicada.** A frase "job vivo + PENDING = 0 rows" estava
errada. Os números confirmados no LIVE são **OPERACIONAL = 1.642** e
**CONFIRMÁVEL = 0**, e são coisas distintas. Já estavam corretos em
`OPERATIONAL-BOUNDARY.md`, `DAG.md`, `PENDING-ARTIFACTS.md` e `2212` desde a
revisão 1.5; os novos artefatos seguem a mesma definição.

### Revisão 1.5 — `OPERATIONAL-BOUNDARY-CORRECTION-01`

| Ação | Arquivo | Correção |
|---|---|---|
| **reescrito** | `2212` → v3.0 (escopo operacional) | 4 · 7 |
| **reescrito** | `2214` → v3.0 (guard job-aware) | 1 · 2 · 8 |
| **reescrito** | `2833` → v2.0 (matriz job-aware, SM5 mede) | 1 · 3 |
| **editado** | `2832` → v3.0 (14 casos, V13/V14) · `2216` → v3.0 | 3 · 9 |
| **editado** | `2830` → v6.0 (100 → 114 + 4 pendentes) | 9 |
| **criado** | `OPERATIONAL-BOUNDARY.md` · `LINEAGE-STRATEGY.md` | 1·2·3 · 5·6 |
| **editado** | `DAG.md` · `ROLLOUT-ORDER.md` · `PENDING-ARTIFACTS.md` | 10 |

### Revisão 1.4 — `BACKFILL-SEMANTICS-CORRECTION-01`

| Ação | Arquivo | Correção |
|---|---|---|
| **reescrito** | `2212` → v2.0 (backfill semântico) | 1 · 2 · 7 |
| **reescrito** | `2214` → v2.0 (guard operacional) | 4 |
| **reescrito** | `2832` → v2.0 (12 provas de destino) | 8 |
| **criado** | `2833` (auditoria da state machine, 8 gates) | 4 |
| **editado** | `2216` → v2.0 (pré-condição operacional) | 3 · 4 |
| **editado** | `2830` → v5.0 (89 → 100) | 8 |
| **editado** | `DAG.md` · `ROLLOUT-ORDER.md` | 6 |
| **editado** | `PENDING-ARTIFACTS.md` · `README.md` | 9 |

### Revisão 1.3 — `GATE-A-FINAL-CORRECTION-01`

| Ação | Arquivo | Correção |
|---|---|---|
| **criado** | `2212` · `2214` · `2215` · `2216` · `2217` · `2230` · `2231` · `2232` · `2832` · `2840` | 1 · 5 · 6 · 7 · 10 |
| **criado** | `edge/import-card-variants.patch` · `edge/edition-context.test.ts` | 8 |
| **criado** | `DAG.md` · `PENDING-ARTIFACTS.md` · `SEED-COVERAGE.md` | 3 · 4 · 6 |
| **editado** | `2209` → v2.0 · `2210` → v2.0 | 1 · 2 · 5 |
| **editado** | `2830` → v4.0 (73 → 89) | 9 |
| **editado** | `TOOLING-PROOF.md` (T2 eliminado) · `ROLLOUT-ORDER.md` · `CONCURRENCY-DESIGN.md` | 2 · 3 · 7 |

### Revisão 1.2 — `GATE-A-01`

| Ação | Arquivo | Motivo |
|---|---|---|
| **editado** | `2211` → **v1.1** | achados A1 A2 A3 A4 |
| **editado** | `2210` → **v1.1** | achados B1 B2 B3 |
| **editado** | `2209` | achado B3 (passos isolados) |
| **editado** | `2207` | achado C2 (`COMMENT` obsoleto) |
| **reescrito** | `2831` → **v2.0** | 5 defeitos, incl. 2 que impediriam a execução |
| **editado** | `2830` → **v3.0** | 3 casos que afirmavam prova inexistente + 6 casos novos |
| **editado** | `IMPACTED-CONTRACTS.md` | achado C1 (call graph recontado) |
| **editado** | `MIGRATION-MAP-365.md` | achado C3 (aritmética) |
| **editado** | `ROLLOUT-ORDER.md` · `CONCURRENCY-DESIGN.md` | achado C4 + ordem de lock |
| **editado** | `TOOLING-PROOF.md` | teste **T2** (`CONCURRENTLY`) |

**Nada fora de `database/proposals/2026-09-18-edition-context-axis/` foi tocado.** Sem SQL executado, sem escrita LIVE, sem deploy de Edge, sem promoção para `schema/`, `migrations/` ou `seeds/`, sem `git add/commit/push`.

### Harness

`2830` v3.0: **73 casos** automáticos (12+8+7+8+12+12+8+6) + 4 manuais, em **9 seções**. As 3 seções novas cobrem exatamente o que a CORRECTION-01 exigiu: `S` (staging tri-state, shape guard, VALID-requires-key e a **coexistência de duas rows que diferem só em Edition Context**), `R` (routing terminal único) e `K` (concorrência + guards de HOLD/PRICING_CONDITIONED). Análise estática: `BEGIN`/`COMMIT` balanceados, `$$` pareados, zero `DROP`/`TRUNCATE` fora de `pg_temp`.

---

## Estado

**NADA EXECUTADO.** Nenhuma tabela, trait, profile, mapping, Variant Type, `NEEDS_REVIEW` resolvida, escrita LIVE, deploy ou promoção para `schema/`/`migrations/`.
