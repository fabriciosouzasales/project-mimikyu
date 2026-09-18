# CARD VARIANT — SIZE SCOPE SERVER GUARD — Staging

| Campo | Valor |
|---|---|
| **Mandato** | CARD-VARIANTS — JUMBO INCIDENT / **DOCUMENTATION-CLOSEOUT-01** (encerramento da frente) |
| **Data** | 2026-09-15 (atualizado 2026-09-16) |
| **Status** | **FRENTE TECNICAMENTE FECHADA (2026-09-16).** `2198` **LIVE** (`20260916012057`) · `2199` **LIVE** (`20260916170733`) · `2827` v1.1.1 **EXECUTADO — 29/29 PASS** · `2828` v2.0 **EXECUTADO — `gate_state = COMPLETE`** · canônico `2176` **não alterado** |
| **Projeto Supabase** | `qjfutqujxrbzgrtkpgkg` |
| **Arquivos** | `2198` + `2199` (migrations incrementais, ambas LIVE) · `2827` v1.1.1 + `2828` v2.0 (harnesses, ambos executados) · este README |

> **Leia a seção [§9 — Fechamento da frente](#9-fechamento-da-frente-2026-09-16) primeiro.** As
> seções `0`–`8` são o registro histórico da construção (incluindo estados
> intermediários hoje superados, como "`2827` NÃO EXECUTADA" e a pendência de E2E
> autenticado da §0.4). §9 é o estado terminal e prevalece sobre elas.

---

## 0. Estado atual — execuções reais

### 0.1 `2198` — APLICADA (2026-09-16)

| Item | Valor |
|---|---|
| migration version | `20260916012057` |
| `md5(pg_get_functiondef)` pré | `5411b79a6b8e8c8d739a1f282bc43868` |
| `md5(pg_get_functiondef)` pós | `1c5b8352ab53b1e6d4f1c08537824a4b` |
| `md5(prosrc)` pós | `b15a527d3b6adb1e50cbaafae22431bc` — **idêntico ao corpo do arquivo** |
| Contrato | `plpgsql` / `STABLE` / `SECURITY DEFINER` / `search_path=""` / `proacl = {postgres=X/postgres}` |
| Estados novos | `BLOCKED_SIZE_OUT_OF_SCOPE` e `BLOCKED_SIZE_UNSUPPORTED` presentes |
| Marcador v1.1 | `NEEDS_REVIEW_INVALID_PRINTING_MAPPING` intacto |
| Dados | 6340 / 0 / 85 / 89 / 7461 — **zero delta**; `max(updated_at)` de rows e jobs anterior à migration |

Sete casos de contrato read-only confirmaram o comportamento: ausente, `standard`,
branco e JSON `null` seguem o fluxo anterior; `jumbo` (em qualquer caixa) devolve
`BLOCKED_SIZE_OUT_OF_SCOPE`; valor desconhecido devolve `BLOCKED_SIZE_UNSUPPORTED`;
os dois bloqueados com `trait_ids = {}` e `printing_profile_id = NULL`; o residual
devolvido é idêntico ao de uma linha sem `size`.

### 0.2 `2827` v1.0 — EXECUTADA UMA VEZ, STOP (2026-09-16)

`GATE_2827_FAILED: 15 PASS / 5 FAIL / 20 registros`. **ZERO RESÍDUO** comprovado por
postcheck independente (contagens, ausência de fixtures, `max(updated_at)` anterior à
execução, `md5` da `2198` inalterado, nenhuma migration posterior, nenhum objeto TEMP
sobrevivente).

**Os seis casos de contrato puro do guard — `CT1`–`CT6` — passaram todos.** Nenhuma das
falhas é da `2198`; todas são de fixture/ambiente do harness:

| # | Falha | Causa-raiz |
|---|---|---|
| D1 | `S2_ABORT`, `S4_ABORT` — `VARIANT_IMPORT_SCOPE_MISMATCH` | O harness inventava `external_set_id` sintético. A Query 2192 trata divergência declarada contra `card_set_external_reference` ATIVA como fail-closed. Card Set sorteado: `2011BW`, referência ativa `2011bw`. |
| D2 | `F1` — `ADMIN_RESOLVE_PRINTING_MAPPING_FORBIDDEN` | O caso chamava uma RPC pública `is_admin()`-guarded (2181, l. 312), contradizendo o próprio cabeçalho do harness. |
| D3 | `F2` — `CREATE_CARD_PRINTING_PROFILE_DUPLICATE_SIGNATURE` | A fixture pegava o primeiro trait ativo (`FIRST_EDITION`), cuja assinatura singleton já tem Perfil. |
| D4 | `A, A_ZW, B, C, D, E, G, H` AUSENTES | O aborto da subtransação revertia junto os vereditos já gravados na TEMP table. |
| D5 | `I` | Dependência: `I_VT`/`I_PR` nunca chegaram a registrar. |

### 0.3 `2827` v1.1 — CORREÇÃO, NÃO EXECUTADA

Correções `C1`–`C5` (uma por defeito) + um achado novo:

| # | Correção |
|---|---|
| C1 | Seção 0.2 exige `card_set_external_reference` ATIVA da fonte TCGDEX e usa **esse** `external_set_id` canônico em todas as fixtures (Seções 2, 3A, 3B, 4), sem sufixos. Valor confrontado contra `internal.resolve_variant_mapping_scope()`. Sem candidato → ABORT. Zero resíduo passou a ser provado por **contagem**, não por `external_set_id` (que agora é canônico e pode existir legitimamente em jobs COMPLETED/CANCELLED). |
| C2 | `F1` → **`F1_CONTRATO`**: prova apenas o motor + evidência dirigida de que a 2181 LIVE classifica por `NOT IN` da whitelist. **Não é E2E** e diz isso no próprio detalhe. |
| C3 | `F2` escolhe dinamicamente a **menor** composição livre de traits ativos (singletons por `id`, depois pares com `b.id > a.id` — já distinta e ordenada). Sem composição livre → FALHA HIGH. Nenhum Perfil existente alterado ou inativado. |
| C4 | Vereditos produzidos dentro de subtransação são acumulados em array PL/pgSQL (`_rec2827`) e gravados por `_flush2827` **depois** que a subtransação termina. O aborto reverte as fixtures mas não apaga a prova. Roster do Gate passou de 20 para **29** casos. |
| C5 | `I` continua derivado de `I_VT`+`I_PR`, sem hardcode, e o detalhe imprime os vereditos reais (inclusive `AUSENTE`). |
| **D6** | **Achado novo, descoberto ao implementar C2.** O antigo caso `E` chamava `public.admin_create_card_variant_type_with_import_mapping`, também `is_admin()`-guarded (2158, l. 94). Sua asserção era "abortou **e** nenhum VT órfão" — satisfeita pelo aborto de **autorização**. Seria **PASS MASCARADO** se a Seção 2 tivesse chegado até lá. Renomeado para **`E_CONTRATO`**, com asserção honesta: fronteira pública fechada + prova dirigida de que 2158 delega a 2150 → worker e **não escreve `validation_status`** por conta própria + ausência de VT órfão. |

### 0.3b `2827` v1.1 — RUN-02, STOP (2026-09-16)

Pre-flight PASS em 4/4. `GATE_2827_FAILED: 27 PASS / 2 FAIL / 29 registros`.
**ZERO RESÍDUO** comprovado por postcheck independente.

**Passaram (27):** `CT1`–`CT6`, `A`, `A_ZW`, `B`, `C`, `D`, `E_CONTRATO`, `I_VT`,
`S2_ZERO_RESIDUO`, `F1_CONTRATO`, `F2`, `I_PR`, `S3_ZERO_RESIDUO`, `G`, `I`,
`S4_ZERO_RESIDUO`, `J`, `REG1`–`REG5`.

As correções C1–C4 funcionaram: `A`/`B`/`D` bloquearam **por tamanho** (a asserção
reprova `SCOPE_MISMATCH`), `F2` criou a composição livre sem `DUPLICATE_SIGNATURE`,
e `G` foi **reportado mesmo com a seção abortando depois** — na v1.0 esse veredito
teria desaparecido. `H` apareceu como **AUSENTE**, não sumiu.

| # | Falha | Causa-raiz |
|---|---|---|
| **D7** | `S4_ABORT` — `[23505] duplicate key value violates unique constraint "uq_cvir_job_card_type_no_printing"` · consequências: `H` AUSENTE e `S2_ABORT_OK` FAIL | A fixture da Seção 4 punha `G` e `H` no **mesmo `job_id`**, no **mesmo `card_id`**, mapeando **ambos para o mesmo `variant_type_id`** sem Printing Profile. O índice parcial `(job_id, card_id, (normalized_data->>'variant_type_id')) WHERE variant_type_id IS NOT NULL AND jsonb_typeof(printing_profile_id)='null'` é **invariante legítimo do staging** — o defeito é da fixture. A v1.0 abortava antes (SCOPE_MISMATCH) e nunca chegou nesse ponto. |

### 0.3c `2827` v1.1.1 — correção C6 (D7), NÃO EXECUTADA

**Auditoria de propagação feita ANTES de escolher a correção** (Query 2193 → universo
da Query 2192):

```sql
WHERE j.source = <fonte> AND e.game_id = <game>
  AND (GLOBAL, ou source-set casando)
  AND sg.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
  AND sg.residual_type/foil/subtype/stamp = os do mapping
```

1. o universo **não é escopado por job** — alcança qualquer linha do mesmo Game+Fonte
   cuja residual case, inclusive em outros jobs;
2. `size` **não participa** do filtro (é estado, não identidade) — coerente com a `2198`;
3. logo, o que hoje separa `H` de `G` é **apenas o token de stamp** — um argumento,
   não uma garantia estrutural.

**Opção adotada: (A).** `H` passa a rodar em subtransação própria (`S4B`), criada
**depois** do rollback integral da fixture de `G` (`S4A`). Quando `H` executa, o mapping
de `G` **não existe mais** — independência estrutural, não argumentativa. A opção (B)
(outro card) resolveria só a colisão do índice e deixaria a independência apoiada no
fato 3. Nenhum mecanismo novo: é o padrão `S3A`/`S3B` já validado.

`H` também deixou de ser asserção única e passou a provar diretamente:
(i) o motor devolve `RESOLVED_NO_PRINTING` para `size=standard` — não bloqueia por
tamanho; (ii) a linha chega ao apply ainda `NEEDS_REVIEW` — **prova positiva** de que
não herdou resolução; (iii) após o mapping próprio, resolve para `VALID`.

Nada de schema: o índice `uq_cvir_job_card_type_no_printing` **não foi tocado**.
Roster segue com **29 casos**, `H` continua obrigatório; se `S4B` abortar, `H` fica
AUSENTE e `S4_ABORT` é registrado.

### 0.4 Pendência declarada — E2E autenticado

As **duas** RPCs públicas admin-guarded do fluxo

- `public.admin_resolve_catalog_variant_import_printing_mapping` (caso `F1`)
- `public.admin_create_card_variant_type_with_import_mapping` (caso `E`)

**não são testáveis pelo canal SQL do harness** (`auth.uid() = NULL`, `is_admin() = FALSE`).
Contorná-las exigiria JWT fabricado, `request.jwt.claims`, `SET ROLE`, `service_role`
manual, admin temporário ou bypass de RLS — **todos proibidos**. O E2E dessas duas RPCs
será feito em **rodada separada, com a sessão administrativa real do usuário no
navegador, depois de `2827` PASS**. Não foi criado nesta rodada. O harness não finge
tê-las testado.

---

## 1. Causa

A TCGdex modela `size` no objeto de variante (`size: "jumbo"`). O extractor da Edge
`import-card-variants` lê **apenas** `type/foil/subtype/stamp` — `size` era descartado
silenciosamente. Prova upstream, medida em 2026-09-15 em `data/Base/Base Set/44.ts`:

```ts
{ type: "normal", size: "jumbo", stamp: ["pikachu"], … }
```

e a linha correspondente no LIVE:

```json
{"type":"normal","foil":null,"subtype":null,"stamp":["pikachu"]}
```

O Gate A (rodada seguinte) corrige o extractor e passa a **preservar** `size` em
`raw_data`. Mas preservar não basta, e o motivo é estrutural:

> `size` está **fora** da assinatura residual — por decisão editorial aprovada.

Logo uma linha com `size` desconhecido tem assinatura residual **idêntica** à da sua
gêmea sem `size`. Quatro riscos, todos comprovados no contrato LIVE:

| # | Risco | Evidência |
|---|---|---|
| 1 | Ser **origem** de mapping de Variant Type | `variant_type_mapping_decision` l.65 só exige `NEEDS_REVIEW` — e a linha É `NEEDS_REVIEW` |
| 2 | Ser **capturada na propagação** de um mapping criado por outra linha | `apply_variant_type_mapping` l.101 filtra por assinatura residual, que é idêntica |
| 3 | Ser promovida a `VALID` pelo **Printing mapping** | `admin_resolve_…_printing_mapping` l.193 + `validation_status = CASE outcome WHEN 'A' THEN 'VALID'` |
| 4 | Ser promovida a `VALID` pelo **backfill de Printing Profile** | `create_card_printing_profile_with_backfill` l.266/l.308, mesma estrutura |

**Os riscos 3 e 4 não estavam no enunciado do mandato — são achado desta auditoria.**
O risco 2 ocorre mesmo com a UI perfeita, que é o motivo pelo qual a barreira de UI
da REV-03 foi julgada insuficiente como estado final.

---

## 2. Decisão

`internal.compute_variant_residual_signature()` passa a ser o ponto central
**fail-closed** para `size`.

### Contrato — quatro ramos

| `size` normalizado | `printing_state` | efeito |
|---|---|---|
| ausente / JSON null / string vazia | inalterado | comportamento atual, **bit a bit** |
| `STANDARD` | inalterado | comportamento atual, **bit a bit** |
| `JUMBO` | **`BLOCKED_SIZE_OUT_OF_SCOPE`** | nenhum writer produz identidade canônica |
| qualquer outro não vazio | **`BLOCKED_SIZE_UNSUPPORTED`** | idem, e o job **não fecha** até decisão editorial |

### Invariantes

- `size` **não** integra a assinatura residual (`residual_type/foil/subtype/stamp`).
- Os dois estados novos são deliberadamente **fora** de
  `('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')`.
- Nenhum consumidor é alterado. Nenhuma constraint, índice, tabela ou grant.
- Nenhum dado é escrito: a migration é `CREATE OR REPLACE FUNCTION` e nada mais.

### Posição do guard

Depois da normalização de `type/foil/subtype/stamp` — para que o residual devolvido
seja **coerente** com a linha real e o diagnóstico editorial mostre a combinação
verdadeira — e **antes** do roteamento de Printing — para que uma linha fora de escopo
não consuma token de Impressão, não leia `card_printing_external_mapping` e não gere
trait.

---

## 3. Consumidores auditados

Auditoria **no LIVE** (não nos arquivos), 2026-09-15. Seis funções consomem
`compute_variant_residual_signature`:

| Consumidor | Linha | Tratamento de `printing_state` | Com `BLOCKED_SIZE_*` |
|---|---|---|---|
| `internal.variant_type_mapping_decision` | 81 | `NOT IN (RESOLVED_*)` → `block_reason` | **bloqueia a origem** |
| `internal.variant_type_mapping_impact` | 68 | `IN (RESOLVED_*)` | **exclui do universo** |
| `internal.apply_variant_type_mapping` | 101 | `IN (RESOLVED_*)` | **exclui do universo** |
| `internal.create_card_printing_profile_with_backfill` | 266 | `NOT IN (RESOLVED_*)` → outcome `C` | **mantém `NEEDS_REVIEW`** |
| `public.admin_resolve_catalog_variant_import_printing_mapping` | 193 | `NOT IN (RESOLVED_*)` → outcome `C` | **mantém `NEEDS_REVIEW`** |
| `public.admin_confirm_catalog_variant_import` | 151 | `IS DISTINCT FROM 'RESOLVED_NO_PRINTING'` → `RAISE` | **recusa a confirmação** |

**Todos tratam o par `RESOLVED_*` como whitelist** — nenhum enumera os estados de erro.
É a mesma propriedade que a v1.1 já usou para introduzir
`NEEDS_REVIEW_INVALID_PRINTING_MAPPING` de forma aditiva (ver `2176` v1.1, seção
"ESTADOS DE RETORNO"). Por isso um estado novo fora da whitelist cobre os quatro
riscos **sem tocar em nenhum writer**.

### Correção de premissa registrada

A rodada anterior afirmou que "apenas 2145/2181 consomem a função". **Estava
incompleto.** A varredura em `database/` encontrou referências também em
`migrations/2179`, `migrations/2180` e nas proposals `2189/2190/2192/2193/2196/2197`.
A prova que vale, porém, é a do LIVE acima — arquivos de proposal podem estar
superados; funções no catálogo, não.

### Limite honesto

O guard é eficaz para todo writer que passe pela função — e os seis passam. Um writer
**futuro** que consulte `catalog_variant_import_row` sem usar o ponto único escaparia.
O caso `J` do harness trava essa regressão arquitetural, e é **suplementar**: não
substitui nenhum caso comportamental.

---

## 4. Baseline LIVE (medido em 2026-09-15, pré-2198)

| Grandeza | Valor |
|---|---|
| `catalog_variant_import_row` | **6340** linhas |
| linhas com chave `raw_data.size` | **0** |
| linhas com `size` não vazio | **0** |
| `card_variant_type_external_mapping` | **85** |
| `card_variant_type` | **89** |
| `card_variant` | **7461** |
| `md5(pg_get_functiondef)` da `2176` LIVE | `5411b79a6b8e8c8d739a1f282bc43868` |
| `BLOCKED_SIZE_` presente na LIVE | **NÃO** |
| marcador v1.1 `NEEDS_REVIEW_INVALID_PRINTING_MAPPING` | **SIM** |
| volatilidade / segurança | `STABLE` / `SECURITY DEFINER` / `search_path=""` |

**Consequência direta:** com zero linha portando `size`, a migration **não altera
comportamento de nenhuma linha existente**. Todas caem no ramo "ausente".

### Pré-flight de numeração

| Número | Situação | Evidência |
|---|---|---|
| `2198` | **LIVRE** | `find database -name "2198*"` → vazio |
| `2827` | **LIVRE** | `find database -name "2827*"` → vazio |
| `2188` | **ocupado** | `proposals/2026-09-13-card-printing-profile-first-edition/2188_…` |
| `2822`–`2826` | **ocupados** | proposals de 2026-09-12 a 2026-09-14; `2826` é o harness SOURCE-SET-SCOPED |

As correções de premissa do mandato foram **confirmadas por medição**, não aceitas por
declaração.

---

## 5. Ordem de rollout

O guard server-side vem **antes** do Gate A. Se a Edge passasse a gravar `size` sem o
guard ativo, existiria uma janela em que linhas `UNSUPPORTED` poderiam ser promovidas.

| Fase | Ação | Gate |
|---|---|---|
| 1 | ~~Pre-flight: `2176` LIVE ≡ canônico; numeração livre~~ | ✅ **FEITO** |
| 2 | ~~**GATE 4** — auditoria física deste staging~~ | ✅ **PASS** |
| 3 | ~~Aplicar `2198`~~ | ✅ **FEITO** — version `20260916012057`, postcheck PASS, zero delta |
| 3b | ~~Executar `2827` v1.0~~ | ⛔ **STOP** 15/5 — defeitos de harness (§0.2), zero resíduo |
| 3c | ~~Corrigir `2827` → v1.1~~ | ✅ **FEITO** (§0.3) |
| 3d | ~~Executar `2827` v1.1 (RUN-02)~~ | ⛔ **STOP** 27/2 — defeito D7 na fixture da Seção 4 (§0.3b), zero resíduo |
| 3e | Corrigir `2827` → v1.1.1 (C6) | ✅ **FEITO** — não executada (§0.3c) |
| 4 | Executar `2827` **v1.1.1** | **roster de 29 casos PASS, zero FAIL** ← *próximo gate* |
| 4b | E2E autenticado das 2 RPCs públicas no navegador (§0.4) | admin real; sem bypass |
| 5 | Regressão: contadores dos 5 jobs STAGED inalterados | qualquer delta → **STOP** |
| 6 | Promover `2198` para `database/schema/` e atualizar `2176` canônico | — |
| 7 | **Só então** Gate A (6 arquivos: extractor + UI) | — |
| 8 | Deploy da Edge + typecheck | — |
| 9 | BASE1: reimport + gate G1–G7 | — |
| 10 | Documentação canônica | — |

> **O canônico `database/schema/2176_…` NÃO é alterado nesta rodada.** A promoção
> ocorre apenas após migration LIVE + `2827` PASS + postcheck.

---

## 6. Riscos

| # | Risco | Mitigação |
|---|---|---|
| R1 | `CREATE OR REPLACE` sobre função canônica LIVE | Derivada linha a linha da v1.1; o algoritmo existente não teve **uma única linha alterada** — só acréscimo de `v_size`, normalização e o bloco de guard. Caso `S0` do harness aborta se o marcador da v1.1 sumir. |
| R2 | Valor novo de `size` bloquear o fechamento de um job | **É o comportamento desejado** (fail-closed). O alternativo — seguir o fluxo normal — é o incidente original. |
| R3 | Regressão em linhas sem `size` | 6340 linhas, 0 com `size`. Casos `CT1`, `G` e `REG1-5` do harness. |
| R4 | Writer futuro fora do ponto único | Caso `J`, suplementar. Não é defesa em profundidade — é detecção de regressão. |
| R5 | Fixtures do harness colidirem com `uq_catalog_variant_import_job_fingerprint_active` | Seção 0.2 escolhe dinamicamente um Card Set **sem** job ativo e **aborta em voz alta** se não houver. |
| R6 | Harness deixar resíduo | Cada seção mutável vive em subtransação com sentinela; `S2/S3/S4_ZERO_RESIDUO` provam que nada sobreviveu — **por contagem** desde a v1.1. Confirmado empiricamente na execução da v1.0. |
| R7 | Ambiente sem `admin_user` ou sem `card_printing_trait` ativo | `F1_CONTRATO`/`F2` registram **FALHA HIGH** explícita em vez de PASS mascarado. |
| R8 | *(v1.1)* Fixture divergir da referência canônica de source-set | Seção 0.2 usa o `external_set_id` da referência ATIVA e o confronta com `internal.resolve_variant_mapping_scope()`. `A`, `B` e `D` **reprovam** se o bloqueio vier de `SCOPE_MISMATCH` em vez do guard de tamanho — o teste não aceita o motivo errado. |
| R9 | *(v1.1 / D6)* Caso passar por aborto de **autorização** em vez do contrato testado | `E_CONTRATO` exige o erro `..._FORBIDDEN` explicitamente e **complementa** com prova dirigida da cadeia de delegação. Nenhum caso declara ter exercitado positivamente uma RPC pública protegida. |
| R10 | *(v1.1)* Evidência perdida quando uma seção aborta | Vereditos vivem em array PL/pgSQL e são gravados após a subtransação (`_rec2827`/`_flush2827`). Casos que realmente não rodaram continuam AUSENTES e o gate continua fail-closed sobre eles. **Confirmado empiricamente no RUN-02:** `G` foi reportado mesmo com a Seção 4 abortando depois. |
| R11 | *(v1.1.1 / D7)* Fixtures do harness colidirem com invariantes de unicidade do staging | `G` e `H` passaram a viver em subtransações separadas (`S4A`/`S4B`), cada uma com um único par (job, card, VT). O índice `uq_cvir_job_card_type_no_printing` **não foi alterado** — ele estava correto. |
| R12 | *(v1.1.1)* `H` herdar resolução de `G` por propagação (o universo do writer não é escopado por job e `size` não entra na residual) | `S4B` roda **após** o rollback integral de `S4A`: o mapping de `G` não existe quando `H` executa. Além disso `H` assere **positivamente** que a linha ainda está `NEEDS_REVIEW` imediatamente antes do seu próprio apply. |

---

## 7. Critérios de PASS / STOP

### PASS exige, cumulativamente

1. ~~`2198` aplicada sem erro; postcheck 1–5 do rodapé do arquivo todos verdadeiros.~~ ✅ **cumprido** (§0.1)
2. `2827` **v1.1.1** com **zero FAIL** e **nenhum caso ausente** do roster de 29.
3. `A`, `B` — bloqueio **e** zero write nos dois escopos, **pelo motivo de tamanho** (bloqueio por `SCOPE_MISMATCH` reprova).
4. `C` — gêmea vira `VALID`, `UNSUPPORTED` permanece `NEEDS_REVIEW`.
5. `D` — preview e execute concordam na recusa (idem item 3 quanto ao motivo).
6. `E_CONTRATO` — fronteira pública fechada + cadeia de delegação provada + nenhum VT órfão `HARNESS_2827_ORPHAN`. **Não vale como E2E atômico** (§0.4).
7. `F1_CONTRATO`, `F2` — o motor devolve `BLOCKED_SIZE_UNSUPPORTED` fora da whitelist e o writer `internal.*` de Printing mantém `NEEDS_REVIEW`. **`F1_CONTRATO` não vale como E2E** (§0.4).
8. `G` — zero regressão para linha sem `size` (subtransação `S4A`). `H` — `size=standard` não é bloqueado pelo motor, chega ao apply ainda `NEEDS_REVIEW` (não herdou `G`) e resolve para `VALID` (subtransação `S4B`, após rollback integral de `S4A`).
9. `I` — linha JUMBO intocada pelos dois eixos, derivado de `I_VT`+`I_PR`.
10. `REG1`–`REG5` — corpus, contadores, mappings, VTs e `card_variant` idênticos.
11. `S2_ABORT_OK` — nenhum aborto fora de sentinela.
12. `S2/S3/S4_ZERO_RESIDUO` — contagens idênticas antes e depois.

> **PASS de `2827` não fecha a frente sozinho.** O E2E autenticado das duas RPCs
> públicas (§0.4) é requisito separado, e está declarado como pendência — não como
> algo já coberto.

### STOP imediato se

- a Seção 0 abortar (2198 ausente, v1.1 corrompida, sem Card Set livre **ou sem referência TCGDEX ativa**);
- qualquer caso `FAIL`;
- qualquer `*_ZERO_RESIDUO` falhar — **resíduo de harness é blocker, não ruído**;
- `REG3` divergir: contador de job alterado significa que o harness escreveu fora
  da sentinela;
- `J` apontar consumidor sem whitelist ou writer novo não catalogado.

---

## 8. O que a rodada CORRECTION-02 (2026-09-16) NÃO fez

- ❌ **não executou `2827` v1.1.1** — nenhum caso rerodado
- ❌ não executou **nenhum** SQL (nem leitura no LIVE)
- ❌ não alterou `2198` (arquivo ou objeto LIVE)
- ❌ não alterou `database/schema/2176_…`
- ❌ **não alterou schema nem o índice `uq_cvir_job_card_type_no_printing`**
- ❌ não criou contrato de produção novo
- ❌ não criou o E2E autenticado (§0.4)
- ❌ não promoveu nenhum arquivo
- ❌ não alterou a Edge `import-card-variants`
- ❌ não alterou frontend
- ❌ não reimportou BASE1, não cancelou job
- ❌ não tocou `docs/` fora desta proposal
- ❌ nenhum `git add/commit/push`

---

## 9. Fechamento da frente (2026-09-16)

`CARD-VARIANTS — JUMBO INCIDENT` está **tecnicamente fechado**. Esta seção é o
estado terminal e prevalece sobre qualquer afirmação anterior deste arquivo.

### 9.1 Causa raiz

A fonte TCGdex modela `size` no objeto de variante (`size: "jumbo"`). O extractor
histórico da Edge `import-card-variants` lia apenas `type`/`foil`/`subtype`/`stamp`
e **descartava `size` silenciosamente**. Consequência: uma variante JUMBO podia ser
absorvida pelo fluxo normal como se fosse a sua gêmea STANDARD.

O incidente não produzia apenas **falsa pendência editorial** — produzia também
**falsa classificação válida** (ver §9.4).

### 9.2 Semântica final

| `size` normalizado | Classificação | Efeito |
|---|---|---|
| ausente / `null` / branco / `STANDARD` | `IN_SCOPE` | fluxo legado, **bit a bit** |
| `JUMBO` | `OUT_OF_SCOPE` | decisão automática do sistema |
| qualquer outro valor não vazio | `UNSUPPORTED` | **fail-closed**, revisão humana |

`size` **permanece fora da identidade residual**. O guard ocorre **antes** de
`routePrinting` e do dedupe; a linha fora de escopo dedupa em espaço próprio
(`X|…`), nunca disputando com linhas em escopo.

### 9.3 Estado de uma linha JUMBO

| Momento | `validation` / `match` / `decision` / `persistence` |
|---|---|
| staging | `INVALID` / `NEW` / `SKIPPED` / `PENDING` |
| após confirmação | `INVALID` / `NEW` / `SKIPPED` / `UNCHANGED` |

`normalized_data.skip_reason = 'SIZE_OUT_OF_SCOPE'`. **Nunca materializa
`card_variant`** — `matched_variant_id` e `resulting_variant_id` permanecem `NULL`.

### 9.4 Descoberta final em BASE1 — **quatro** JUMBO, não três

| Card | Diagnóstico histórico |
|---|---|
| Bulbasaur **#044** | aparecia como `NEEDS_REVIEW` por `NORMAL` + `PIKACHU` |
| Charmander **#046** | idem |
| Squirtle **#063** | idem |
| **Pikachu #058** | `raw` real = `size=jumbo`, `normal`, **sem stamp/subtype**. Como `size` era descartado, foi **silenciosamente absorvido pelo fluxo normal como variante válida** |

Pikachu #058 é o caso que prova a segunda face do incidente: sem o eixo de tamanho,
a linha não tinha **nada** que a distinguisse de uma variante legítima.

### 9.5 Migrations LIVE

| Query | Objeto | Migration LIVE | md5 LIVE pós-aplicação |
|---|---|---|---|
| `2198` | `internal.compute_variant_residual_signature` — size guard no ponto único de routing | `20260916012057` | `1c5b8352ab53b1e6d4f1c08537824a4b` |
| `2199` | `public.admin_decide_catalog_variant_import_row` — imutabilidade da decisão `SIZE_OUT_OF_SCOPE` (GUARD 7) | `20260916170733` | `bc2e5f378a95e02fbcc8b10819451f52` |

`2199` aplicada com **delta de dados = ZERO** (14 fingerprints idênticos antes/depois).

### 9.6 Gates

| Gate | Resultado |
|---|---|
| Harness `2827` v1.1.1 | **29 PASS / 0 FAIL**, zero resíduo |
| Harness `2828` v2.0 | **`gate_state = COMPLETE`** — estrutural 18 PASS / 0 FAIL; E2E autenticado 5 PASS / 0 PENDING / 0 FAIL |
| E2E B1–B5 (sessão admin real, navegador) | **PASS integral** — B2/B3 são prova **direta** do GUARD 7; B1 prova a invariante final (GUARD 6c tem precedência); B4 idempotência; B5 atomicidade do lote misto |
| Fixture E2E | removida com **zero resíduo** (2 rows + 1 job), baseline restaurado |
| Suíte lógica Deno (canônica) | **Deno 2.9.3 — 81 casos / 81 PASS / 0 FAIL** |

**A pendência declarada na §0.4 está encerrada.** O E2E autenticado foi executado em
sessão administrativa real — sem `service_role`, sem JWT fabricado, sem
`request.jwt.claims`, sem `SET ROLE`, sem admin temporário.

`S1.15` teve prova **não-vácua** (`linhas_marcadas >= 1`, `divergentes = 0`) primeiro
com a fixture E2E e depois com a população produtiva real do rerun de BASE1.

### 9.7 Edge `import-card-variants`

| Item | Valor |
|---|---|
| versão | **v11** (sucede a v10) |
| status | `ACTIVE` |
| `verify_jwt` | `true` |
| `ezbr_sha256` | `751ac62dd99baea63d84ec755726e82e1d6829d178ce0f51f6ca02ca1cf0aa4a` |

### 9.8 BASE1 — job histórico preservado e rerun real

**Job histórico `af230406-9055-4df3-ac17-b837a4865e76`**: preservado com as **415 rows
intactas**; `status` alterado `STAGED → CANCELLED` **apenas** para liberar o escopo
para o rerun. Nenhuma row histórica foi removida ou alterada — provado por fingerprint
integral idêntico antes/depois (`c41957c0ca10a6666aee76918ab8ee12`).

**Job do rerun `c4d185ad-4971-4be6-af10-0b3e66466536`**:

| Momento | Estado |
|---|---|
| após staging | total 415 · `VALID` 411 · `INVALID` 4 · **`NEEDS_REVIEW` 0** · `SIZE_OUT_OF_SCOPE` 4 |
| após confirmação | `COMPLETED` · inserted 0 · **unchanged 415** · failed 0 · skipped 4 |

`card_variant` permaneceu **7461** — o rerun não materializou nenhuma variante nova,
que é exatamente o esperado para um Set já materializado.

**BASE1 passa a ter 0 `NEEDS_REVIEW`.** Os antigos "3 resíduos de BASE1" eram, na
verdade, 3 dos 4 JUMBO — não pendência editorial.

### 9.9 Frontend — READY, ainda NÃO publicado

O frontend antigo em produção exibiu, após a confirmação do rerun: *"4 sem
mapeamento"*, *"4 a revisar"*, *"Concluído com pendências"* e o botão *"Resolver
mapeamentos pendentes"*. **Causa**: `totalRows - validRows` usado como proxy de
pendência editorial — fórmula que era verdadeira antes do incidente e deixou de ser
quando `INVALID` ganhou um segundo significado (fora de escopo).

O working tree corrige integralmente: `mappingPendingRows` / `unsupportedSizeRows` /
`outOfScopeRows` separados e derivados dos **marcadores**; JUMBO visível como
**"Fora de escopo"** (tom `muted`, nunca `danger`); nenhuma ação editorial ou de
mapeamento; checkbox bloqueado; job apenas com OUT_OF_SCOPE classificado como
**sucesso**; contador explícito "Fora de escopo"; zeros de mapping não renderizados.

> **O código frontend está `READY / INCLUDED IN CLOSEOUT` — não publicado.** A Vercel
> segue servindo o commit anterior. A publicação ocorre no Commit + Push de Fabrício, e
> **a validação visual pós-deploy permanece como último postcheck operacional**, ainda
> não realizado. Nada neste documento afirma que a UI corrigida já foi validada em
> produção.

---

## Reconciliação canônica — 2026-09-18

`BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01` classificou cada Query
deste ciclo por **natureza**, e não em bloco. Esta pasta permanece como
**evidência histórica** do staging; a fonte executável passou a ser:

| Query | Natureza | Destino |
|---|---|---|
| `2198` | alteração de função canônica (`internal.compute_variant_residual_signature`) | `database/migrations/2198_...` · dobrada em `database/schema/2176_...` **v2.0** |
| `2199` | alteração de função canônica (`admin_decide_catalog_variant_import_row`) | `database/migrations/2199_...` · dobrada em `database/schema/2144_...` **v2.0**, junto com a `2163` |

Nada foi reexecutado contra o Supabase nesta rodada — promoção canônica e
fold-in são alteração de arquivo, não execução (ver `database/README.md`,
seção "Queries `CANÔNICA` vs. `MIGRATION`").
