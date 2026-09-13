# Card Variants — Printing Routing / External Mapping

| Campo | Valor |
|---|---|
| **Proposta** | `2026-09-12-card-variants-printing-routing` |
| **Mandato** | `STAGING-GATE-A-01` → `STAGING-REVISION-01` → `STAGING-REVISION-02` → `STAGING-FINAL-AUDIT-01` → `STAGING-CORRECTION-03` → `PHASE-A-EXECUTION-01` → `GATE-A-HARNESS-CORRECTION-01` → `PHASE-B-FINAL-AUDIT-01` → `STAGING-CORRECTION-04` → `STAGING-CORRECTION-05` → **`STAGING-CORRECTION-06`** (rodada atual) |
| **Queries** | 2172 – 2187 (16 migrations) · 2824 (harness) |
| **Depende de** | Proposta `2026-09-12-card-variants-printing-model` (2165–2171, **LIVE**) |
| **Criado em** | 2026-09-12 · revisado em 2026-09-12 |

## Estado por fase

| Fase | Estado | Queries |
|---|---|---|
| **PHASE A** | **EXECUTED / CLOSED / VALIDATED** | `2172` `2173` `2174` `2175` `2176` `2177` `2182` |
| **PHASE B** | **STAGED / NOT EXECUTED** | `2178` `2179` `2187` `2180` `2185` `2186` `2181` |
| **PHASE C** | **NOT STARTED** (deploy da Edge nova) | — |
| **PHASE D** | **DEFERRED** | `2183` |
| **PHASE E** | **DEFERRED** | `2184` |

> **Somente a PHASE A foi executada em LIVE**, em `PHASE-A-EXECUTION-01` (7 migrations,
> na ordem obrigatória, cada uma individualmente postcheckada) e validada em
> `GATE-A-HARNESS-CORRECTION-01` (96 asserções Phase-A-only PASS, zero regressão de
> dados, zero resíduo de fixture).
>
> **Nenhuma migration da PHASE B / D / E foi aplicada.** Nenhum deploy de Edge. Nenhum
> backfill. Nenhum `git add/commit/push` — commit e push são feitos por Fabrício pela
> interface do GitHub, após aprovação.

---

## 0. O que mudou na `STAGING-CORRECTION-03`

Dois blockers achados pela `STAGING-FINAL-AUDIT-01`, ambos fechados.

### B-01 — a Query 2176 não enxergava a composição antes do selo

`trg_card_printing_external_mapping_seal` é `DEFERRABLE INITIALLY DEFERRED`:
`traits_signature` só é gravada no COMMIT. A 2176 v1.0 usava esse campo para
**duas** coisas ao mesmo tempo — obter a composição *e* decidir se existe mapping
ativo. Dentro da transação que **cria** o mapping (a propagação da 2181), as duas
estavam erradas: assinatura NULL → caía no ramo "token já conhecido?" → o próprio
mapping recém-criado satisfazia a busca → `NEEDS_REVIEW_INACTIVE_MAPPING` →
`rows_revalidated = 0`, **sem erro**.

**2176 v1.1** separa os dois papéis:

- **existência** passa a ser decidida por `m.id`;
- **composição** passa a ser a **assinatura efetiva**:
  `COALESCE(traits_signature, composição atual da N:N ordenada)`.

E um estado novo, porque o caso patológico é real e distinto:

```
mapping ATIVO + assinatura efetiva vazia  ->  NEEDS_REVIEW_INVALID_PRINTING_MAPPING
```

Não é `RESOLVED_NO_PRINTING` (o token *tem* routing, só está quebrado — devolvê-lo
ao resíduo o reclassificaria como acabamento) e não é
`NEEDS_REVIEW_INACTIVE_MAPPING` (o mapping está ativo; o defeito é a composição).

**Por que esta regra existe:** exclusivamente por causa do selo deferido. Fora da
transação de criação, `traits_signature` está sempre preenchida e o `COALESCE`
nunca precisa do segundo braço.

### B-02 — a S14 não detectava propagação vazia

A v2.1 provava só `mapping_id IS NOT NULL` e `superseded_mapping_id IS NOT NULL`.
Ambas passariam com o B-01 presente — **falso PASS**.

**2824 v2.2**: a S14 agora monta uma row de staging real, executa uma ratificação
editorial real e exige `rows_revalidated = 1`, `jobs_affected = 1`,
`rows_still_pending = 0`, mais o estado final da própria row. Se a 2176 regredir,
**S14.02 falha**. H27 (snapshot de `card_variant` + `EXCEPT` nos dois sentidos)
foi preservado integralmente.

**S27 nova** prova o contrato temporal de dentro, sem passar pela 2181: chama a
função com o mapping ainda não selado, nos dois casos opostos (N:N completa →
resolve; N:N vazia → fail-closed).

**Rollout A→E inalterado.**

---

## 0-A. O que mudou na `STAGING-REVISION-02`

| | Item | Fechado por |
|---|---|---|
| **§1** | Log de Atualizações exibiria UUID cru para Mapeamento de Impressão | **`2186`** (nova) |
| **§2** | O mapeamento irmão (Tipo de Variação) também caía em UUID | `2186`, mesma migration |
| **§3** | Metadata da 2181 | Já conforme — verificado, sem `tokens` ambíguo |
| **§4** | Query 2126 | **Não tocada**, conforme instruído |
| **§7** | Provas L01–L07 | `2824` v2.1, Seção **S26** |
| **§8** | Inventário inconsistente no relatório | §13 deste README |
| **§9** | Terminologia dos GUCs de fase | Headers de `2183`/`2184` + §4 deste README |
| **§10** | Reader no rollout | PHASE B, §4 deste README |

### ⚠ Divergência encontrada — precisa da sua decisão

`docs/log.md` [2026-08-16] afirma que a migration
`2050_humanize_variant_governance_action_log` foi **CONFIRMADO EXECUTADO** e deu a
`admin_list_catalog_action_log()` três branches novas (`CARD_VARIANT_TYPE`,
`CATALOG_VARIANT_IMPORT_JOB`, `CARD_VARIANT_TYPE_EXTERNAL_MAPPING`).

No repositório: **esse arquivo não existe**. O número 2050 pertence a
`2050_create_admin_delete_card_set_function.sql`, e `database/schema/2127` (v1.0,
única definição da função) tem só as 7 branches originais.

Ou o LIVE tem as três branches e a migration nunca foi promovida, ou o log.md está
errado. Não dá para decidir sem consultar o banco — o que esta rodada não faz.

**Como a `2186` lida com isso:** o corpo é um superconjunto (contém as 7 originais
+ as 3 da Governança de Variantes + as novas), e um GUARD extrai por regex todos os
literais `WHEN '...'` da definição **real** e aborta se encontrar algum que o
arquivo desconhece. Sob qualquer das duas realidades, nada é removido.

Independentemente disso, `docs/log.md` precisa ser reconciliado numa rodada
documental — está registrando uma migration que não existe no repositório.

---

## 0-B. O que mudou na `STAGING-REVISION-01`

Quatro blockers de rollout/integridade fechados.

| | Blocker | Fechado por |
|---|---|---|
| **R1** | PHASE D/E podiam ser aplicadas junto com A/B | Banner `DEFERRED / DO NOT PROMOTE` + **GUARD 0 de autorização de fase** em `2183`/`2184` |
| **R2** | O confirm rejeitaria em massa durante a janela do bridge | `2179` v1.1 — compatibilidade transitória **provada pelo resolvedor** e amarrada à existência do bridge |
| **R3** | Harness incompleto e inventário inconsistente | `2824` v2.0 — quatro blocos; **H13, H21, H23, H24, H27 promovidos ao Gate A** |
| **R4** | Log de auditoria semanticamente incorreto | **`2185`** (nova) — action e entity_type próprios; `2181` v1.1 passa a usá-los |
| **R5** | Faltava invariante estrutural final de `normalized_data` | `2184` v2.0 — nova constraint, `ADD NOT VALID` + `VALIDATE` |
| **R6** | PHASE E sem provas de precondição | `2184` v2.0 — **GUARD 0 + seis GUARDS**, tudo numa transação |

---

## 1. O problema que esta frente resolve

O Printing Model (2165–2171) criou o **domínio**. O que faltava era o caminho de
entrada: como uma assinatura externa (`type` / `foil` / `subtype` / `stamp[]`) vinda do
TCGdex deixa de ser texto e vira **dois resultados independentes** —

- **Variant Type** (acabamento: STANDARD, HOLO, REVERSE …)
- **Print Profile** (impressão: SHADOWLESS, 1ª edição, copyright 1999-2000 …)

Hoje o pipeline trata `subtype` e `stamp` como parte da identidade de *Variant Type*.
Esse é o defeito taxonômico que só some quando o **roteamento** existir.

### Os cinco bloqueadores originais

| | Bloqueador | Fechado por |
|---|---|---|
| **B1** | O índice de identidade de staging não distingue duas linhas da mesma Card com perfis diferentes → colisão em 408 das 410 linhas de BASE1 | 2177 |
| **B2** | `admin_confirm` casa variante por `(card, variant_type)` → MATCHED falso | 2179 |
| **B3** | `admin_resolve_..._mapping` lê o `raw_data` cru, não o resíduo | 2180 |
| **B4** | O validador 960 procura `uq_card_variant_card_type`, que deixou de existir | `database/validations/960` v2.2 |
| **B5** | Sem autoridade de unicidade, conjuntos disjuntos podiam ser mesclados | 2172 |

---

## 2. Os contratos ratificados

### C1 — Dois eixos, nunca misturados

`type` e `foil` **sempre** permanecem no resíduo. `subtype` e `stamp[]` podem ser
consumidos pelo Printing — e só pelo Printing.

### C2 — Token → traits é um agregado atômico

Um token aponta para um **conjunto**, criado atomicamente, nunca observado
parcialmente, imutável depois de publicado, seguro sob concorrência. Daí o par
cabeçalho + composição.

A alternativa (uma linha por par token-trait) foi **rejeitada**: duas sessões inserindo
`{SHADOWLESS}` e `{RED_CHEEK}` para o mesmo token produziriam, sem violar nada, um
terceiro conjunto que ninguém decidiu.

### C3 — `traits_signature UUID[]`, sem hash

Array ordenado, igualdade exata. Acumula duas funções deliberadas: **autoridade de
unicidade** (via índice único parcial real) e **estado de selamento** (`NULL` = em
montagem; `NOT NULL` = selado).

### C4 — Selamento diferido

`CONSTRAINT TRIGGER ... AFTER INSERT ... DEFERRABLE INITIALLY DEFERRED` no
**cabeçalho**. Fecha a brecha da composição vazia. Na N:N não funcionaria — ela não
dispara nada quando está vazia.

### C5 — UNIQUE parcial + histórico

```
uq_card_printing_external_mapping_active_token
  (game_id, asset_source_id, raw_field, normalized_token) WHERE is_active
```

Substituição = desativa o antigo + insere novo com `supersedes_mapping_id`. Nunca
`superseded_by_id` no antigo: exigiria FK para uma linha futura. `is_active` é
`NOT NULL` (NULL escaparia do índice parcial). Reativação é proibida.

### C6 — Três estados de token

| Estado | Situação | Resultado |
|---|---|---|
| **A** | Mapping ATIVO existe | usa o mapping |
| **B** | Só histórico INATIVO | `NEEDS_REVIEW`, chave **ausente**, **não** volta ao resíduo |
| **C** | Nunca conhecido | vai ao resíduo |

**Rejeitado:** "mapping inativo → token volta ao resíduo". Transformaria de novo um
conceito de Impressão em Variant Type.

### C7 — Igualdade exata de token

`subtype` inteiro-ou-nada · `stamp` token a token. Nenhum prefixo, substring, `LIKE`,
fuzzy ou quebra por hífen. `1st-edition-error` **≠** `1st-edition`.

### C8 — Identidade de staging observável pelo banco

| Documento | `jsonb_typeof(nd -> k)` | `nd ->> k` | `nd ? k` |
|---|---|---|---|
| chave ausente | SQL `NULL` | SQL `NULL` | `false` |
| `{"k": null}` | `'null'` | SQL `NULL` | `true` |
| `{"k": "abc"}` | `'string'` | `'abc'` | `true` |

`->>` colapsa os dois primeiros casos — por isso os índices de staging são **dois
parciais**, não um estendido: `NULL` em UNIQUE composto não representa "sem Print
Profile", representa ausência de informação, e o Postgres nunca considera dois `NULL`
iguais.

### C9 — `service_role` só lê, e só o necessário

`SELECT` em exatamente três tabelas. As duas tabelas de composição ficam fora: o
cabeçalho selado já carrega os `trait_id`.

### C10 — Auditoria com contrato próprio *(R4)*

```
action      = CARD_PRINTING_EXTERNAL_MAPPING_CREATED
entity_type = CARD_PRINTING_EXTERNAL_MAPPING
entity_id   = id do mapping novo
```

Reusar o par de `CARD_VARIANT_TYPE_EXTERNAL_MAPPING` com `metadata.domain` foi
**rejeitado**: guardaria a identidade da entidade fora da coluna que existe para isso,
e toda consulta por `entity_type` precisaria ler JSON para não misturar dois domínios.

**Escolhido A, não B** (ver §7).

### C11 — Invariante final de `normalized_data` *(R5)*

```
validation_status <> 'VALID' OR normalized_data ? 'printing_profile_id'
```

Somada ao CHECK de forma da 2177, o contrato completo é:
`VALID → chave presente → valor é null OU UUID válido`. `NEEDS_REVIEW` pode manter a
chave ausente: "ainda não sei" é estado legítimo.

Entra na **PHASE E**, não antes — durante A/B ela invalidaria as 5.653 linhas legadas.

---

## 3. Mapa de arquivos

| Query | Arquivo | Fase | O que faz |
|---|---|---|---|
| **2172** | `..._create_card_printing_external_mapping_table.sql` | A | Cabeçalho + índice único parcial de ativo + índice de lookup |
| **2173** | `..._create_card_printing_external_mapping_trait_table.sql` | A | Composição N:N, same-Game por FKs compostas |
| **2174** | `..._create_card_printing_external_mapping_guards.sql` | A | Cinco guards |
| **2175** | `..._seed_card_printing_external_mappings.sql` | A | 5 mappings ativos / 6 vínculos |
| **2176** | `..._create_compute_variant_residual_signature_function.sql` **v1.1** | A | Núcleo do roteamento — assinatura **efetiva** (B-01) |
| **2177** | `..._reconcile_variant_import_row_staging_identity.sql` | A | CHECK de forma + dois índices canônicos + **bridge transitório** |
| **2182** | `..._grant_service_role_read_access_for_printing_routing.sql` | A | `SELECT` nas 3 tabelas de runtime |
| **2178** | `..._extend_internal_write_card_variant_for_printing.sql` | B | `write_card_variant` com perfil (6 args, sem overload) |
| **2179** | `..._extend_admin_confirm_catalog_variant_import_for_printing.sql` **v1.1** | B | Matching triplo + compatibilidade transitória (R2) |
| **2187** | `..._remove_write_card_variant_printing_default.sql` **(nova)** | B | Remove o `DEFAULT NULL` — fecha a rota de 5 args (D-01) |
| **2180** | `..._reconcile_variant_type_mapping_writers_to_residual.sql` | B | Writers de Variant Type passam a operar sobre o resíduo |
| **2185** | `..._widen_catalog_admin_action_log_for_printing_mapping.sql` **v1.3** | B | Contrato de auditoria próprio (R4) + prova **semântica** da matriz de pares antes do `DROP CONSTRAINT` (B-10/B-11) |
| **2186** | `..._extend_admin_list_catalog_action_log_for_mapping_entities.sql` | B | Contrato de **leitura** do log — labels humanos |
| **2181** | `..._create_admin_resolve_printing_mapping_function.sql` **v1.2** | B | RPC de ratificação/substituição — origin binding (B-04), NO_CHANGE efetivo (B-05), reconciliação terminal (B-06) |
| **2183** | `..._backfill_legacy_valid_printing_profile_null.sql` **v1.1** | **D — DEFERRED** | `null` explícito nas 5.653 VALID legadas |
| **2184** | `..._drop_staging_identity_bridge_index.sql` **v2.0** | **E — DEFERRED** | Invariante final + remoção do bridge |
| **2824** | `..._validate_card_printing_routing.sql` **v2.5** | — | Harness fail-closed, quatro blocos |

Fora da pasta: `database/validations/960_validate_card_variant.sql` **v2.2** (staged).

**Numeração verificada nesta rodada:** `database/**/21??_*.sql` devolveu tudo até 2184;
**2185 estava livre**. Gaps preexistentes (2107–2109, 2160) confirmam que o repositório
tolera lacunas.

### Ordem de aplicação ≠ ordem numérica

Os números são **identificadores**, não contrato de ordenação. A ordem de aplicação é a
das fases (§4). A única dependência real fora da ordem numérica — `2185` antes de
`2181` — é **auto-verificável**: a `2181` tem um guard que se recusa a criar a função
enquanto a CHECK do log não aceitar a action nova.

---

## 4. Rollout PHASE A → E

**Premissa que governa tudo:** banco e Edge Function **não** sobem atomicamente. Existe
uma janela real em que o banco novo convive com o writer antigo. Toda a sequência
abaixo existe para que essa janela seja segura em vez de ser um acidente.

### PHASE A — Fundação (banco), compatível com o writer antigo

```
2172 → 2173 → 2174 → 2175 → 2176 → 2177 → 2182
```

Ao fim: domínio de roteamento existe e sedimentado; dois índices canônicos criados; o
**bridge** protege as linhas que a Edge antiga continua gravando sem a chave; o
`service_role` já lê o necessário.

**Nada quebra.** A Edge antiga cai no predicado `jsonb_typeof(...) IS NULL` e é
protegida pelo bridge, exatamente como antes.

**Validação:** harness 2824, **BLOCO I** (S1–S21) — exceto S19/S20, que dependem da
Fase B.

### PHASE B — Funções do pipeline + contrato de auditoria + contrato de leitura

**ORDEM RATIFICADA (STAGING-CORRECTION-04 §6):**

```
2178 → 2179 → 2187 → 2180 → 2185 → 2186 → 2181
```

Ao fim: `write_card_variant` aceita perfil e **exige** o argumento (sem DEFAULT);
`admin_confirm` faz matching triplo e aplica a compatibilidade transitória; writers de
Variant Type operam sobre o resíduo; o log tem contrato próprio de **escrita** (2185) e
de **leitura** (2186); e só então a RPC de ratificação existe.

**Por que a 2181 é a ÚLTIMA.** Ela é a primeira função capaz de gerar um evento de
Impressão. Quando a primeira ratificação editorial puder acontecer, tudo o que esse
evento toca já tem que estar pronto:

| Pré-condição | Garantida por |
|---|---|
| o writer está fechado em 6 args, sem rota de 5 | `2178` + `2187` |
| o confirm entende Printing e faz matching triplo | `2179` |
| o resolver de Variant Type usa o resíduo | `2180` |
| o action/entity domain aceita o evento | `2185` |
| o reader exibe label humano, não UUID cru | `2186` |

Se o reader chegasse **depois** da 2181, o intervalo produziria linhas de log exibindo
UUID cru na tela — exatamente o defeito que a REVISION-02 veio fechar. A 2181 tem um
guard de dependência próprio que aborta se a CHECK do log ainda não aceitar a action
nova, tornando a ordem `2185 → 2181` auto-verificável.

**Por que a 2187 entra logo após a 2179.** A 2178 cria a assinatura de 6 argumentos com
`DEFAULT NULL` por uma razão transitória: na janela entre a 2178 e a 2179, o corpo LIVE
da 2164 ainda chama o writer com **cinco** argumentos posicionais. Depois que a 2179
comita, esse caller deixa de existir — e o DEFAULT vira apenas uma porta destrancada,
pela qual qualquer writer futuro que esqueça o perfil gravaria `NULL` silenciosamente.
`NULL` aqui não é placeholder: é "sem perfil de impressão declarado". A 2187 fecha essa
porta e converte o erro de omissão em erro de compilação. Ela carrega dois guards que
abortam se a 2179 ainda não estiver instalada.

**O que NÃO acontece mais aqui (R2):** o confirm **não** passa a rejeitar em massa. Uma
linha VALID legada sem a chave é confirmada como "sem perfil" **se e somente se** o
resolvedor provar que sua assinatura bruta não contém Impressão conhecida — ativa ou
histórica. Se contiver, é recusada com `PRINTING_NOT_RESOLVED`.

**Validação:** harness 2824, **BLOCO I completo** — ordem de execução `S1..S20`, depois
`S26` (contrato de leitura), e `S21` (zero resíduo) **por último**. O PASS integral do
BLOCO I autoriza a PHASE C.

### PHASE C — Edge Function nova

Deploy de `import-card-variants` com o contrato do §5.

**Invariante de saída:** toda linha nova nasce com `printing_profile_id` presente —
`null` explícito ou UUID. Nunca VALID sem a chave.

**Validação:** harness 2824, **BLOCO II** (S22), depois de uma importação real. O PASS
autoriza a PHASE D.

### PHASE D — Reconciliar o legado

```
BEGIN;
SET LOCAL mimikyu.phase_c_edge_deployed = 'CONFIRMED';
\i 2183_backfill_legacy_valid_printing_profile_null.sql
```

**O que esse GUC é:** uma **confirmação operacional explícita do executor**. Ele impede
que a PHASE D dispare por acidente — reexecução do lote A/B, replay por runner de
migrations. É uma trava, e o guard de conteúdo da 2183 **passaria hoje**, antes do
deploy, então essa trava é necessária.

**O que esse GUC não é:** prova técnica de que a Edge foi deployed ou de que o writer
antigo deixou de existir. O banco não consegue verificar nada disso; o `SET LOCAL`
registra uma afirmação, não a verifica.

A autorização real da PHASE D é a conjunção de **(a)** PASS do BLOCO II (S22), que é a
única evidência observável de que o writer vigente honra o contrato de saída, **(b)**
este checklist, e **(c)** o operador executar o `SET LOCAL`. O GUC é o (c).

As **505 NEEDS_REVIEW não são tocadas**. Elas serão reavaliadas pelo roteamento e
algumas terão perfil de verdade (as 410 de BASE1). Dar `null` a elas seria afirmar "sem
perfil" antes de perguntar.

**Validação:** harness 2824, **BLOCO III** (S23). O PASS autoriza a PHASE E.

### PHASE E — Fechar o estado e remover o bridge

```
BEGIN;
SET LOCAL mimikyu.phase_e_authorized = 'CONFIRMED';
\i 2184_drop_staging_identity_bridge_index.sql
```

**Ponto de não retorno.** Antes de modificar qualquer coisa, a 2184 prova seis
precondições (§6). Só então declara e valida a constraint final e remove o bridge —
tudo em uma transação. Qualquer precondição falhando: STOP sem alteração parcial.

Mesma ressalva do GUC da PHASE D: `mimikyu.phase_e_authorized` é confirmação
operacional do executor, não prova técnica. **A prova técnica desta fase são os GUARDS
1–6** — esses o banco verifica de fato.

**Efeito colateral desejado:** o ramo de compatibilidade da 2179 está amarrado à
*existência* do bridge. Removê-lo extingue a compatibilidade no mesmo instante, sem
migration adicional. A compatibilidade transitória não pode virar contrato permanente,
e a forma de garantir isso é amarrá-la ao objeto que define a janela — não à memória de
quem operou o rollout.

**Validação:** harness 2824, **BLOCO IV** (S24–S25).

### Rollback por fase

| Fase | Reversível? | Como |
|---|---|---|
| A | Sim | `DROP` dos objetos novos; o bridge restaura o comportamento anterior |
| B | Parcial | `2178` removeu a assinatura de 5 args de `write_card_variant`; reverter exige recriá-la. `2185` é reversível por um novo widen. As demais são `CREATE OR REPLACE`. |
| C | Sim | redeploy da versão anterior da Edge |
| D | Sim | remover a chave do `jsonb` — mas só enquanto o bridge existir |
| E | Sim, com custo | `DROP CONSTRAINT` + recriar o bridge |

---

## 5. Contrato da Edge Function — STAGED, NÃO IMPLEMENTADO

> Os arquivos TypeScript canônicos de `supabase/functions/` **não** foram alterados.
> `npm run typecheck` não pôde ser executado nesta sessão (§9); editar código em
> produção sem verificação de tipos seria pior do que documentar o contrato.

### 5.1 `services/database.ts`

**`buildVariantComboKey` (116–128)** — passa a compor a chave a partir do **resíduo**:
`type|foil|residual_subtype|residual_stamp` + `printing_profile_id`. Sem isso, duas
linhas que diferem só na impressão colidem no dedupe em memória antes de chegar ao
banco.

**Preload de mappings (137–141)** — carrega também `card_printing_external_mapping`
(incluindo o histórico inativo, necessário para distinguir o estado B do C),
`card_printing_trait` e `card_printing_profile`.

**`listExistingCardVariantsMap` (160–179)** — chave passa de
`${card_id}|${variant_type_id}` para
`${card_id}|${variant_type_id}|${printing_profile_id ?? 'NULL'}`. É o B2 do lado do
TypeScript.

### 5.2 `index.ts`

| Linha | Hoje | Depois |
|---|---|---|
| 241 | preload de Variant Type | + preload de Printing |
| 258–259 | `comboKey` / lookup pelo bruto | pelo resíduo + perfil |
| 279 | dedupe pelo bruto | pelo resíduo + perfil |
| 286 | `matched` por `(card, type)` | por `(card, type, profile)` |
| 293 | `normalized_data` sem a chave | **sempre** com a chave |
| 295–297 | status | `NEEDS_REVIEW` também para estado B, trait inativo, perfil ausente e perfil inativo |

### 5.3 A ordem é de propósito

O roteamento roda **antes** do lookup de Variant Type, porque o lookup precisa operar
sobre o resíduo. Inverter reintroduz o B3 dentro da Edge.

---

## 6. Precondições da PHASE E

Todas verificadas por `DO` block antes de qualquer DDL, na mesma transação.

| # | Precondição | Como é provada |
|---|---|---|
| 0 | PHASE E autorizada pelo operador | GUC `mimikyu.phase_e_authorized` |
| 1 | O bridge ainda existe | `pg_indexes` |
| 2 | Os dois índices canônicos existem | `pg_indexes` |
| 3 | O CHECK de forma da 2177 existe | `pg_constraint` |
| 4 | A constraint final ainda não existe | `pg_constraint` |
| 5 | `VALID` com chave ausente = 0 | contagem direta — é também a prova de que a constraint **pode** ser validada |
| 6 | Nenhuma linha conflita nos índices finais | `GROUP BY ... HAVING count(*) > 1` — o bridge pode estar mascarando uma colisão |

---

## 7. Decisão fechada — auditoria de substituição: A, não B

| | |
|---|---|
| **A** *(escolhido)* | Uma única action `CARD_PRINTING_EXTERNAL_MAPPING_CREATED`, com `supersedes_mapping_id`, `rows_revalidated`, `rows_still_pending`, `jobs_affected` em `metadata` |
| **B** *(rejeitado)* | A mesma, mais `CARD_PRINTING_EXTERNAL_MAPPING_SUPERSEDED` |

A substituição **não é um evento independente**: criação do sucessor, desativação do
predecessor e propagação acontecem na mesma transação. Dois eventos para um ato atômico
criam duas linhas que podem divergir, e nenhuma delas seria a verdade sozinha.

Teste de suficiência aplicado:

- *"Quando o token X deixou de usar M1?"* → a linha CREATED com
  `metadata.supersedes_mapping_id = M1`; seu `created_at` é o instante.
- *"Qual a cadeia histórica?"* → `supersedes_mapping_id` encadeia M3→M2→M1.
- *"Quantas linhas foram revalidadas?"* → `metadata.rows_revalidated`.

Nenhuma pergunta de auditoria fica sem resposta. B seria redundância, não cobertura.

**Reabre-se se** um dia a desativação puder ocorrer sem sucessor na mesma transação.
Hoje isso é impossível por construção.

---

## 8. Harness 2824 v2.5 — quatro blocos

| Bloco | Seções | Quando rodar | Autoriza |
|---|---|---|---|
| **I — GATE-A** | S1–S21 | depois de 2172–2182/2185 | PHASE C |
| **II — POST-EDGE** | S22 | depois do deploy + uma importação real | PHASE D |
| **III — POST-BACKFILL** | S23 | depois da 2183 | PHASE E |
| **IV — FINAL-E** | S24–S25 | depois da 2184 | fechamento |

### Inventário — agora consistente

Os cinco casos que a v1.0 adiava indevidamente estão no **BLOCO I**:

| Caso | Seção | Como é provado sem Edge |
|---|---|---|
| **H13** duplicate trait | S13 | (a) PK `(mapping_id, trait_id)` torna a duplicata fisicamente impossível; (b) a RPC rejeita o payload com erro próprio, em fixture revertida |
| **H21** 5.653 VALID seguros | S15 | medição direta sobre dados reais — é a precondição da própria 2183 |
| **H22** contrato de reconciliação | S15 | o backfill da 2183 é simulado em `BEGIN/ROLLBACK` e a reconciliação é verificada |
| **H23** BASE1 410/410 | S16 | o **resolvedor** é rodado contra as 410 linhas que já existem; nenhuma Edge envolvida |
| **H24** BASEP/SVE/SV5 95 intactas | S17 | as 95 precisam dar `RESOLVED_NO_PRINTING` e continuar sem casar Variant Type |
| **H27** replacement não toca catálogo | S14 | snapshot de `card_variant` + `EXCEPT` nos dois sentidos, antes e depois de uma substituição real |

S13 e S14 exigem contexto de administrador: **impersonam um admin real já existente**
via `request.jwt.claims`, dentro da transação revertida. Nenhuma linha de `admin_user` é
criada. Sem admin cadastrado, a seção **falha alto** — nunca passa por omissão.

### Semântica

Fail-closed: cada asserção é um `RAISE EXCEPTION` dentro de um bloco `DO`. **PASS =
ausência de exceção** (o MCP não propaga `RAISE NOTICE`); cada seção termina com um
`SELECT ... AS resumo`.

### Lição incorporada da 2823 v1.1 → v1.2

O comparador de composição **não** pode depender de ordenação textual. Com
`datcollate = en_US.UTF-8` a pontuação é ignorada na primeira passada e
`SHADOWLESS_FIRST_EDITION=...` ordena **antes** de `SHADOWLESS=...` — o oposto de
`COLLATE "C"`. A correção não foi adicionar `COLLATE "C"`: composição é um **conjunto**,
e o harness prova igualdade de conjuntos diretamente (S2).

---

## 9. Limitações da sessão — declaradas

Sandbox indisponível durante toda a frente (`Plan9 share "c" which is not mounted`,
atualização do Windows de 08/09). Consequências, sem contorno:

- `npm run typecheck` não executado → arquivos TS de `supabase/functions/` não alterados.
- Nenhum comando `git`, nem de leitura.
- Nenhum arquivo pôde ser **renomeado** (`mv` indisponível) — o que reforça a decisão de
  §10 sobre manter os números 2183/2184.

O que não pôde ser provado está declarado como não provado.

---

## 10. Decisão sobre a numeração de 2183/2184

**Mantidos**, com três camadas de proteção em vez de renumeração.

**Por que a promoção tardia NÃO é insegura neste repositório:**

1. `database/migrations/` é **registro histórico**, não manifesto de execução. Não há
   runner que replique a pasta em ordem numérica; cada Query é aplicada manualmente
   segundo o plano de rollout.
2. Gaps e promoções tardias já são a prática vigente — 2107–2109 e 2160 são lacunas; a
   2159 foi staged em 05/09 e promovida bem depois.
3. Cada arquivo promovido carrega `Status: CONFIRMADO EXECUTADO` + data, que é o que
   registra a cronologia real.

**Custo residual, assumido:** se outra frente consumir 2186+ antes da PHASE D, a ordem
numérica em `migrations/` deixará de refletir a cronologia. Mitigado pelo cabeçalho
datado.

**O que substitui a renumeração:**

- Banner `DEFERRED / DO NOT PROMOTE / DO NOT APPLY DURING GATE A/B` no topo dos dois.
- **GUARD 0** em cada um: sem o GUC de autorização da fase, o script aborta sem
  escrever nada — mesmo que seja promovido por engano ou replicado por um runner.
- Seção 4 deste README, com a sequência exata e o que cada fase autoriza.

Esta é a implementação da preferência declarada no mandato; a alternativa
(de-numeração) segue disponível se você preferir, e nesse caso o custo é atualizar as
referências cruzadas em 2177, 2179, 2824 e neste README.

---

## 11. Contrato de leitura do log — labels finais

Fechado pela Query **2186** (antes era o resíduo conhecido desta seção).

| entity_type | Label | Fonte, em ordem |
|---|---|---|
| `CARD_PRINTING_EXTERNAL_MAPPING` | `subtype · SHADOWLESS-RED-CHEEK` | `metadata.raw_field` + `metadata.normalized_token` → tabela viva → UUID |
| `CARD_VARIANT_TYPE_EXTERNAL_MAPPING` | `normal · holo` · assinatura externa | `metadata.external_{type,foil,subtype,stamp}` → tabela viva → UUID |
| `CARD_VARIANT_TYPE` | nome da variação | `metadata.name` → `card_variant_type.name` → UUID |
| `CATALOG_VARIANT_IMPORT_JOB` | nome da Coleção | `metadata.card_set_name` → `card_set.name` via job → UUID |
| `CARD_PRIMARY_SPECIES` | nome da Carta | `metadata.name` → `card.name` → UUID |

Separador `·` para os componentes da assinatura, `+` entre elementos de `stamp` —
mantendo a leitura de que stamp é um conjunto, não uma sequência.

**Ponto aberto de gosto:** o label de Impressão usa `normalized_token`
(`SHADOWLESS-RED-CHEEK`), conforme pedido literal do mandato. O precedente de
`RARITY_EXTERNAL_MAPPING` usa o valor externo **cru** (`external_value`), o que aqui
daria `shadowless-red-cheek`. Trocar é uma palavra no arquivo — diga qual prefere.

Os rótulos de `ENTITY_TYPE_OPTIONS`, `ACTION_OPTIONS` e `METADATA_KEY_LABEL` em
`web/lib/catalogo/log-atualizacoes-labels.ts` seguem marcados `STAGED / NOT DEPLOYED`.

---

## 12-A. Inventário exato da proposta

Contagem conferida fisicamente no diretório em `STAGING-CORRECTION-05` e reconferida em
`STAGING-CORRECTION-06` (nenhum arquivo criado ou removido nesta rodada).

**Dentro de `database/proposals/2026-09-12-card-variants-printing-routing/` — 18 arquivos:**

| | |
|---|---|
| Migrations | **16** (`2172`–`2187`) |
| Harness | 1 (`2824`) |
| README | 1 |

Distribuição das 16 migrations por fase:

| Fase | Qtd | Queries |
|---|---|---|
| **PHASE A** — executada | **7** | `2172` `2173` `2174` `2175` `2176` `2177` `2182` |
| **PHASE B** — staged | **7** | `2178` `2179` `2187` `2180` `2185` `2186` `2181` |
| **DEFERRED D/E** | **2** | `2183` (D) · `2184` (E) |

**Fora da proposta — 2 arquivos:**

| Arquivo | Natureza |
|---|---|
| `database/validations/960_validate_card_variant.sql` | canônico, v2.1 → **v2.2** (staged) |
| `web/lib/catalogo/log-atualizacoes-labels.ts` | canônico, alterado (staged) |

**Total tocado pela frente: 20 arquivos.**

---

## 12-B. Estado

| Fase | Estado |
|---|---|
| **PHASE A** | **EXECUTED / CLOSED / VALIDATED** |
| **PHASE B** | **STAGED / NOT EXECUTED** |
| **PHASE C** | **NOT STARTED** |
| **PHASE D / E** | **DEFERRED** |

**O que já aconteceu em LIVE:** as 7 migrations da PHASE A, aplicadas uma a uma na
ordem obrigatória em `PHASE-A-EXECUTION-01`, cada uma individualmente postcheckada;
mais 96 asserções Phase-A-only do harness 2824, com zero regressão de dados e zero
resíduo de fixture (`GATE-A-HARNESS-CORRECTION-01`).

**O que NÃO aconteceu:** nenhuma migration da PHASE B, D ou E aplicada · nenhum deploy
de Edge · nenhum backfill · nenhuma linha de `card_variant` alterada · nenhum
`git add/commit/push`. Commit e push são feitos por Fabrício pela interface do GitHub,
após aprovação.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação da proposta de roteamento de impressão, 2026-09-12.** 13 migrations (2172–2184), harness (2824) e plano de rollout PHASE A→E. Fecha B1–B5. Nada executado. |
| 2.0 | **`STAGING-REVISION-01`, 2026-09-12.** Fecha R1–R6: autorização de fase por GUC em 2183/2184; compatibilidade transitória do confirm amarrada ao bridge (2179 v1.1); harness reestruturado em quatro blocos com H13/H21/H23/H24/H27 promovidos ao Gate A (2824 v2.0); contrato próprio de auditoria (2185 nova + 2181 v1.1); invariante final de `normalized_data` e seis precondições na PHASE E (2184 v2.0). Nada executado. |
| 3.0 | **`STAGING-REVISION-02`, 2026-09-12.** Fecha o contrato de **leitura** do Log de Atualizações: Query 2186 (nova) acrescenta 5 branches de `entity_label` a `admin_list_catalog_action_log()` — Impressão, Tipo de Variação, Variant Type, Job de Variação e Primary Species — eliminando a exibição de UUID cru; harness 2824 v2.1 ganha a Seção S26 (L01–L07 + 3 asserções de regressão); GUCs de fase reclassificados como confirmação operacional, não prova técnica; rollout revisado com o reader na PHASE B; inventário exato. Registra a divergência entre `docs/log.md` [2026-08-16] e o repositório quanto à migration `2050_humanize_variant_governance_action_log`. Nada executado. |
| 4.0 | **`STAGING-CORRECTION-03`, 2026-09-12.** Fecha B-01 e B-02, achados pela `STAGING-FINAL-AUDIT-01`. **2176 v1.1**: existência do mapping ativo decidida por `id`; composição passa a ser a assinatura **efetiva** (selada **ou** N:N da própria transação), porque o selo é deferido; novo estado fail-closed `NEEDS_REVIEW_INVALID_PRINTING_MAPPING` para mapping ativo com composição vazia. **2824 v2.2**: S14 reescrita para exigir propagação real (`rows_revalidated = 1` + estado final da row), preservando H27; S27 nova prova o contrato temporal diretamente. **2181**: cabeçalho reconciliado — a afirmação sobre a N:N passou a ser literalmente verdadeira. Rollout A→E inalterado. Nada executado. |
| 5.0 | **`GATE-A-HARNESS-CORRECTION-01`, 2026-09-12.** Corrige a fixture da S11, que colidia com dado real durante o SETUP (falso FAIL, não defeito LIVE): seleção da tripla `(job, card, variant_type)` passa a ser data-independent, por `NOT EXISTS` contra os três namespaces, com precondições fail-loud e regression guard. Cobertura de 3 → 9 asserções (H17 e H18 comportamentais entram; H19 vira censo dos três namespaces). Acrescenta S15.00, S16.06, S17.04 (não-vacuidade) e S21.12–.20. **PHASE A executada e validada em LIVE**: 7 migrations aplicadas, 96 asserções Phase-A-only PASS, zero regressão, zero resíduo. |
| 6.0 | **`STAGING-CORRECTION-04`, 2026-09-12.** Fecha B-04/B-05/B-06/B-07/B-08 e a decisão D-01, achados por `PHASE-B-FINAL-AUDIT-01`. **2181 v1.2**: origin-row binding — o token tem que existir por igualdade canônica exata na `raw_data` da linha informada, sem LIKE/substring/prefixo/fuzzy, validado DEPOIS do payload puro e ANTES do lock; NO_CHANGE passa a comparar a composição **efetiva** (selada **ou** N:N transacional), fechando o mesmo buraco do B-01 em outro ponto; e TODA linha atingida é reconciliada em um de três estados terminais (A: VALID com as duas chaves; B: NEEDS_REVIEW sem `variant_type_id`, com perfil explícito; C: NEEDS_REVIEW sem nenhuma das duas), com invariante de contagem fail-closed. **2187 nova**: remove o `DEFAULT NULL` de `internal.write_card_variant()` logo após a 2179, com guards de estado inicial, de caller e de estado final. **2185 v1.1**: guard anti-drift passa a casar o literal quoted completo. **2824 v2.3**: S12 prova `pronargdefaults = 0`; S14 ganha fixture data-independent para a identidade FINAL e fixture própria com token sintético (o mapping real de 1ST-EDITION deixa de ser tocado); S13b ganha asserção de ordem de validação; S28 nova cobre B-06 (casos A/B) e OB1–OB6. **Ordem da PHASE B ratificada: 2178 → 2179 → 2187 → 2180 → 2185 → 2186 → 2181.** Nada executado. |
| 7.0 | **`STAGING-CORRECTION-05`, 2026-09-12.** Correção final do staging, fechando B-09/B-10/D-02 de `PHASE-B-FINAL-AUDIT-01`. **2824 v2.4**: S14 PARTE 2 ganha par `(job, card)` PRÓPRIO, selecionado por `NOT EXISTS` contra a identidade final da composição A — a v2.3 reusava o par da PARTE 1, cuja identidade `(job, card, variant_type, printing_profile)` a PARTE 1 acabara de ocupar, o que faria a primeira propagação da PARTE 2 colidir no namespace B dentro da própria transação (falso FAIL); três guardas fecham o caso: candidato existe, é diferente do par da PARTE 1, e a identidade final está livre. S19 passa a provar o contrato de auditoria ESTRUTURALMENTE — três CHECKs presentes, 12 ramos, 30 pares, nenhum literal fora do universo ratificado —, sem depender de linha gravada. S28 passa a derivar `v_sig_no_profile` com `ORDER BY t.id`, a mesma ordenação canônica de `traits_signature`. **2185 v1.2**: o guard anti-drift passa a cobrir a TERCEIRA CHECK (`action_entity_match`), que era dropada e recriada sem prova prévia; a janela era real — outra frente podia ter permitido um par novo sem que nenhuma linha o usasse, e a prova por rows é cega para permissão não exercida. **README** reconciliado com o estado real: estado por fase, mandato até esta rodada, Queries 2172–2187, inventário 18 + 2 = 20 arquivos conferido fisicamente, Revision History cronológica. Nada executado nesta rodada. |
| 8.0 | **`STAGING-CORRECTION-06`, 2026-09-12.** Fecha B-11, F-12 e os resíduos de D-03. **B-11 — a prova por contagem era um falso FAIL garantido.** A 2185 v1.2 e a S19 v2.4 provavam o contrato da terceira CHECK (`action_entity_match`) contando ocorrências de literais quoted no TEXTO da definição, exigindo ocorrência = 1 por token em dois laços independentes. Mas `'CATALOG_IMPORT_JOB'` é ao mesmo tempo um `entity_type` e uma `action` do universo ratificado na Query 2159 — o literal aparece DUAS vezes na definição **correta**, e as duas contagens abortariam contra a baseline correta. A correção NÃO especializa o token: a contagem foi abandonada e substituída por avaliação **semântica** — `pg_get_expr(conbin, conrelid)` renderiza a expressão real com as colunas não-qualificadas `entity_type`/`action`, `format()` a injeta sobre uma tabela derivada que expõe exatamente esses dois nomes, e `EXECUTE` deixa o próprio PostgreSQL decidir cada par do produto cartesiano completo (2185 v1.3: 11 × 29 = 319 pares, 29 esperados, antes do `DROP CONSTRAINT`; 2824 S19: 12 × 30 = 360 pares, 30 esperados, no estado final). Sem parsing e sem contagem, a posição sintática do token é respeitada por construção e a colisão léxica deixa de ser representável. Duas provas nominais em cada ponto: regressão do B-11 (`CATALOG_IMPORT_JOB` × `CATALOG_IMPORT_JOB` DEVE ser aceito) e cross-pair inválido (`GAME` × `CARD_CREATED` DEVE ser recusado); a S19 acrescenta ainda a exclusividade de domínio entre os dois mappings. As listas planas `action_valid` e `entity_type_valid` continuam verificadas por extração textual, agora por **igualdade de conjuntos** nos dois sentidos — ali é legítimo, porque são `IN (...)` de coluna única, sem papel sintático a confundir; a distinção está registrada em comentário no próprio arquivo. **F-12**: a S19 terminava com duas linhas de resumo consecutivas (a nova e a obsoleta, de '7 assercoes'); a obsoleta foi removida e a contagem foi conferida contra os rótulos reais — S19.00 a S19.15, 16 asserções, sem lacuna e sem duplicidade. **D-03**: mapa de arquivos e heading da §8 reconciliados com as versões correntes (2185 v1.3, 2824 v2.5); versões históricas preservadas nas entradas anteriores desta tabela. As três `ADD CONSTRAINT` da 2185 permanecem byte a byte inalteradas (30 actions / 12 entity_types / 12 ramos) — nenhuma mudança de contrato, apenas de prova. Nada executado nesta rodada. |
