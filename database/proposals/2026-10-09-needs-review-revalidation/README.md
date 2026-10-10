# NEEDS-REVIEW-REVALIDATION-01 — reavaliação das `NEEDS_REVIEW` já resolvíveis

**Status: EXECUTADO NO LIVE em 2026-10-09** (Claude, via MCP, com autorização de Fabrício).

Locais finais dos arquivos:

- `2238` está em `database/migrations/` (ledger `20261009231911`). A canônica `database/schema/2010` subiu para a v2.1.
- `2239` está em `database/schema/` (ledger `20261009232048`).
- `2843` continua nesta pasta como evidência de validação.

## Resultado da execução

| Etapa | Resultado |
|---|---|
| Pré-check | 1.642 `NEEDS_REVIEW`; a função não existia; a action não existia; 31 actions; `card_variant` = 24.893 |
| `2238` | O guard passou (as três CHECK eram iguais ao baseline). Ficaram 32 actions e o ramo `CATALOG_VARIANT_IMPORT_JOB` passou a ter 2 actions. |
| `2239` | Função criada: `SECURITY DEFINER`, `search_path=""`, `EXECUTE` só do owner. |
| `2843` v1.0 | Falhou em S1b por defeito do próprio teste: comparava `proconfig::text`, que vem com aspas escapadas. Nada foi escrito. Corrigido na v1.1. |
| `2843` v1.1 | **`NRR_2843_ROLLBACK_PASS`**: todos os casos passaram e o estado do banco foi conferido como intacto depois. |
| Dry-run | `plan_rows` 1.085 · 59 jobs · H2 excluídas 379 · H3 excluídas 57 · não resolvíveis 121 · conflitos 0 |
| Apply (`p_expected_rows` = 1.085) | **1.085 linhas revalidadas** em 59 jobs (`run_id` `39390676-f033-4000-a0e6-dc1a103f5921`) |

Na apply, as linhas revalidadas ficaram assim por tipo:

| Tipo | Linhas |
|---|---:|
| `STANDARD` | 897 |
| `HOLO` | 164 |
| `REVERSE_HOLO` | 16 |
| `COSMOS_HOLO` | 4 |
| `COSMOS_REVERSE` | 4 |

### Pós-check

- **Staging `STAGED`/`PENDING`:** `NEEDS_REVIEW` caiu de 1.642 para **557**; `VALID/PENDING` subiu de 48 para **1.133**; `VALID/SKIPPED` ficou em 64.
- **Nova medição da `NR-DRYRUN-01`:** `A_AUTO` = 1, que é a linha retida em H3. `B_FINISH_GAP` = 556, igual ao previsto.
- **Auditoria:** 59 linhas `CARD_VARIANT_IMPORT_ROWS_REVALIDATED`, somando 1.085.
- **`card_variant`:** continua em 24.893. Nada foi materializado.

**Próximo passo para as 1.085 linhas:** decidir e confirmar pelo fluxo normal (`2144` → `2145`), em mandato próprio.

---


## Por quê

A `NR-DRYRUN-01` foi uma medição só de leitura, feita em 2026-10-09. A evidência está em `docs/history/development/needs-review-remeasure-2026-10-09/`.

Ela mostrou que **1.086 das 1.642 `NEEDS_REVIEW`** já se resolvem nos três eixos com o vocabulário vigente. Essas linhas continuam pendentes porque nunca foram reavaliadas depois das seeds de Edition Context (`2230`–`2232`). O único caminho de reavaliação que existe hoje é o worker `2219`, e ele só dispara quando um mapping de acabamento novo é criado.

## Arquivos

| Query | Tipo | O que faz |
|---|---|---|
| `2238` (→ `database/migrations/`) | migration (DDL) | Widen aditivo do `catalog_admin_action_log`. Acrescenta a action `CARD_VARIANT_IMPORT_ROWS_REVALIDATED` e o par `(CATALOG_VARIANT_IMPORT_JOB, CARD_VARIANT_IMPORT_ROWS_REVALIDATED)`. O guard confere o estado real antes de qualquer DDL, comparando o conjunto exato de valores aceitos pelas CHECKs vigentes. |
| `2239` (→ `database/schema/`) | migration (função) | Cria `internal.revalidate_needs_review_variant_rows(p_actor_id, p_apply, p_expected_rows)`. O modo padrão é **dry-run**. Para aplicar, `p_expected_rows` precisa ser igual ao plano medido. Usa o mesmo contrato da `2219` (`resolve_variant_row_axes` + `lookup_variant_type_for_row`, gravando as três chaves de uma vez). Exclui os HOLDs H2 e H3. Detecta colisão de `uq_cvir_row_identity` antes de escrever. É idempotente e audita cada job afetado. |
| `2843` | validação | Um único bloco `DO` que **termina sempre em erro** e por isso desfaz tudo o que fez. Sucesso aparece como `NRR_2843_ROLLBACK_PASS`. Cobre estrutura, guards, pin, holds, shape, auditoria, idempotência e o fato de nenhuma `card_variant` ser criada. |
| — | frontend | `web/lib/catalogo/log-atualizacoes-labels.ts` ganha o rótulo da action nova e das chaves de metadata. Não tem efeito enquanto a `2238` não for aplicada. |

## O que a função NÃO faz

- Não cria mapping, perfil, trait nem `card_variant`.
- Não decide nem confirma linhas. As linhas promovidas ficam `VALID / PENDING / PENDING` e seguem o fluxo normal: `2144` (decide) e depois `2145` (confirm), em mandato próprio.
- Não toca linhas dos HOLDs:
  - **H2:** `set-logo` em EX7–EX10.
  - **H3:** `foil` `league`, `player-reward` ou `professor-program`. Uma linha de H3 resolveria sozinha como `STANDARDS_LEAGUE`, mas a decisão B3 ainda está pendente, então ela não é promovida.
- Não tem EXECUTE para `anon`, `authenticated` nem `service_role`. Uma RPC pública para a tela editorial, com `is_admin()`, fica para um mandato separado.

## Ordem de execução (referência — já executada em 2026-10-09)

1. Aplicar a `2238` e confirmar com a query de validação no rodapé do arquivo.
2. Aplicar a `2239` e confirmar com a query de validação no rodapé do arquivo.
3. Rodar a `2843`. O esperado é a mensagem `NRR_2843_ROLLBACK_PASS` com o plano, que deve ser **1.085** (1.086 − 1 linha de H3). O banco fica intacto.
4. Rodar o dry-run e anotar `plan_rows`:
   ```sql
   SELECT internal.revalidate_needs_review_variant_rows('<seu admin_user.id>', false, NULL);
   ```
5. Aplicar com o número anotado:
   ```sql
   SELECT internal.revalidate_needs_review_variant_rows('<seu admin_user.id>', true, <plan_rows>);
   ```
6. Pós-check: rodar de novo o `NR-DRYRUN-01`. O esperado é `A_AUTO` = 1 (a linha de H3) e `B_FINISH_GAP` = 556.

Os scripts só entram em `database/migrations` / `database/schema` depois de **confirmadamente executados**.

## Riscos registrados

- **Deriva entre o dry-run e o apply.** Coberta pelo pin `p_expected_rows`. Se o plano mudar, nada é escrito.
- **Concorrência com o worker `2219`.** Locks JOB → ROW na mesma ordem determinística da `2219`.
- **CHECK do log mudou desde a `2188`.** O guard da `2238` aborta antes de qualquer DDL.
- **Volume.** O plano tem cerca de 1,6 mil linhas, recalculadas em uma chamada (a mesma ordem de grandeza da `NR-DRYRUN-01`, que respondeu normalmente).

## NRR-CONFIRM-01 — decidir e confirmar as 1.085 linhas (2026-10-09)

O runner é `NRR-CONFIRM-01_decide_confirm_revalidated_rows.sql`. Ele usa só as RPCs que já estão LIVE (`2144` decide e `2145`/`2218` confirm), com o administrador real como ator: as claims ficam locais à transação.

| Etapa | Estado |
|---|---|
| Checagem semântica prévia | 0 identidades duplicadas no plano. As novas variantes não repetem as legadas da mesma carta: carta de World Championship Deck com o carimbo do jogador é variante diferente da base, e `REVERSE_HOLO` + logo do Set em DP1/SWSH9 não existia como legado. As 48 `VALID` do canary SVE ficaram **fora do escopo**. |
| **CANARY** (COL1, 1 linha) | **EXECUTADO**. 1 linha `INSERTED`, 1 Card Variant nova (`STANDARD` + `ROLE_STAFF`). `card_variant` foi de 24.893 para 24.894. 0 FAILED. |
| **FULL** (1.084 linhas, 58 jobs) | **EXECUTADO por Fabrício no SQL Editor** (2026-10-09; o editor mostra só “Success. No rows returned”, porque o NOTICE não aparece ali). |

Para rodar o FULL:

1. Cole `NRR-CONFIRM-01_FULL_ready.sql` no SQL Editor do Supabase e execute.
2. O sucesso aparece como o NOTICE `NRR_CONFIRM_OK` com os totais.
3. Qualquer gate que falhar desfaz a transação inteira.
4. O esperado é `rows` = 1084, `inserted` + `unchanged` = 1084 e `card_variant_after` = 24.894 + `inserted`.

### Pós-check do NRR-CONFIRM-01 (canary + full), conferido por leitura

| Verificação | Resultado |
|---|---|
| `card_variant` | **24.893 → 25.978 (+1.085)** |
| Por tipo | `STANDARD` 897 · `HOLO` 164 · `REVERSE_HOLO` 16 · `COSMOS_HOLO` 4 · `COSMOS_REVERSE` 4. Todas com Edition Context. |
| Linhas dos 59 jobs | `VALID/APPROVED/INSERTED` 12.887 · `INVALID/SKIPPED/UNCHANGED` 57 · `NEEDS_REVIEW/PENDING` 551. **0** `VALID/PENDING`. |
| Jobs | **27 `COMPLETED`**, cada um com `CARD_VARIANT_IMPORT_CONFIRMED` no log. 32 seguem `STAGED`, porque ainda têm `NEEDS_REVIEW`. |
| Identidade duplicada em `card_variant` | **0** |
| `FAILED` no staging | **0** |
| Staging `STAGED`/`PENDING` restante | `NEEDS_REVIEW` 557 · `VALID/PENDING` 48 (canary SVE, fora do escopo) · `VALID/SKIPPED` 64 |

**NEEDS-REVIEW-REVALIDATION-01 está CONCLUÍDA.**

## Decisão H2 — `set-logo` em EX7–EX10 (2026-10-09)

**Decisão de Fabrício:** classificar como **Reverse Holo comum** (`REVERSE_HOLO`), com escopo apenas em EX7–EX10.

**Por que:**

- Nesses Sets a fonte só tem `normal`, `holo` e `reverse + set-logo`. Não existe reverse sem logo, então o logo não distingue nenhuma variante.
- Antes desta decisão, nenhuma das cartas tinha Reverse Holo no catálogo.
- Bulbapedia (EX Team Rocket Returns): a partir dessa expansão, toda Reverse Holofoil traz o logo do Set no canto inferior direito da arte.
- Com isso não se cria tipo composto.

**Execução:**

- O preview oficial (`2194`) devolveu 379 linhas (EX7 95, EX8 95, EX9 89, EX10 100), todas da classe A, sem bloqueio.
- Foram criados 4 mappings `SOURCE_SET` (`ex7`..`ex10`): `REVERSE` + `SET-LOGO` → `REVERSE_HOLO`. O caminho foi a RPC oficial `admin_resolve_catalog_variant_import_mapping_for_set`, com o administrador real como ator e 4 linhas de auditoria `CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED`.
- As 379 linhas foram para `VALID/PENDING`. O `NEEDS_REVIEW` total caiu de 557 para **178**.

**Confirmação:** Fabrício executou `NRR-CONFIRM-02_H2_ready.sql` no SQL Editor em 2026-10-09. A verificação por leitura mostrou:

- **379 linhas** `VALID/APPROVED/INSERTED`.
- **379 Reverse Holo novas**: EX7 95, EX8 95, EX9 89, EX10 100.
- `card_variant` foi de 25.978 para **26.357**.
- Os 4 jobs ficaram **COMPLETED**.
- 0 identidades duplicadas e 0 linhas FAILED.
- `NEEDS_REVIEW` restante: **178**.

**Inconsistência registrada, não tratada aqui:** em EX11–EX16 a fonte codifica a mesma reverse com logo como `normal + set-logo` e `holo + set-logo`. Esses casos viraram os tipos legados `SET_LOGO_STANDARDS` (449 variantes) e `SET_LOGO_REVERSE` (86). A reconciliação fica com a decisão D2 e com o Pricing 80, em frente própria.

## Decisão H3 — `foil` de programa (League / Player Rewards / Professor) (2026-10-09)

**Decisão de Fabrício:** modelar como **acabamento + Edition Context**, sem tipo composto:

- o tipo da fonte define o acabamento (`reverse` → `REVERSE_HOLO`, `holo` → `HOLO`, `normal` → `STANDARD`);
- o `foil` define o programa (`league` → `PROGRAM_LEAGUE`, `player-reward` → `PROGRAM_PLAYER_REWARDS`, `professor-program` → `PROGRAM_PROFESSOR`), combinado com `staff` quando houver.

**Sequência:** a H3 fica para depois das unidades que só precisam de mapping, como mini-frente própria. Hoje o eixo de Edition Context lê apenas `stamp` e `subtype` (CHECK de `raw_field`), então a H3 exige uma migration estrutural para que o eixo passe a ler `foil`.

**Escopo:** 57 linhas, todas da era DP / Platinum / HGSS. As 57 continuam retidas.

## Cracked Ice — `holo` + `foil cracked-ice` (2026-10-09)

**Classificação:** acabamento `CRACKED_ICE_HOLO`, sem Edition Context. O tipo já existe e está em uso: 20 variantes em PL2, PL4, POP8 e SVE, todas sem EC.

**Lacuna encontrada:** existia apenas o mapping GLOBAL `REVERSE` + `CRACKED-ICE`. As linhas com `holo` + `cracked-ice` ficavam sem resolução.

**Execução:**

- O preview `2194` (GLOBAL) devolveu 38 linhas em 12 jobs, todas resolvíveis e sem conflito.
- Foi criado o mapping GLOBAL `HOLO` + `CRACKED-ICE` → `CRACKED_ICE_HOLO` pela RPC oficial `admin_resolve_catalog_variant_import_mapping`, com o administrador real como ator.
- As 38 linhas foram para `VALID/PENDING`. Os Sets são DP3, EX5, HGSS1–4, HGSSP, PL3, POP8, SM3, SWSH3 e SWSH4.
- Nenhuma dessas cartas tinha Cracked Ice no catálogo.

**Confirmação:** Fabrício executou `NRR-CONFIRM-03_cracked_ice_ready.sql` no SQL Editor em 2026-10-09. O escopo foi por linha, porque os jobs também têm linhas H3 retidas. A verificação por leitura mostrou:

- **38 linhas** `VALID/APPROVED/INSERTED`, com 0 pendente.
- `CRACKED_ICE_HOLO` foi de 20 para **58** variantes.
- `card_variant` foi de 26.357 para **26.395**.
- 0 identidades duplicadas e 0 linhas FAILED.
- `NEEDS_REVIEW` restante: **140**; jobs STAGED: 27.

## Erros de impressão — `no-e-reader` e `missing-expansion-symbol` (2026-10-09)

**Decisão de Fabrício:** criar Printing para as duas famílias grandes agora. Os ~12 erros avulsos de 1–2 linhas (`text-error`, `rarity-error`, `phanphy-error`, `no-holo-error`, `d-ink-dot-error` etc.) continuam retidos para decisão individual.

**Evidência:**

- `NO_E_READER`: segundo a Bulbapedia, as reimpressões de EX Ruby & Sapphire e EX Sandstorm no EX Battle Stadium saíram sem a faixa de dot code do e-Reader e sem o logo "e". São 41 linhas: EX1, EX2 e NP.
- `MISSING_EXPANSION_SYMBOL`: as 16 holos de Jungle de uma tiragem inicial Unlimited saíram sem o símbolo da expansão. Fontes de colecionadores (checklists e fóruns) dizem que a PSA gradua essa versão como "No Symbol"; não achei confirmação da própria PSA. São 16 linhas de BASE2.
- Mesma classe semântica de `AOKI_CREDIT` e `EVOLUTION_BOX_ERROR`: variedade de tiragem, não defeito do exemplar.

**Execução (pelo agente, via MCP):**

1. `2240` (seed de traits, SQL direto; sem ledger, mesmo regime da `2202`): `card_printing_trait` POKEMON passou de 9 para 11. Promovida para `database/seeds/`.
2. Profiles `NO_E_READER` (ordem 12) e `MISSING_EXPANSION_SYMBOL` (ordem 13), criados por `admin_create_card_printing_profile_with_backfill`.
3. Mappings de `subtype`, criados por `admin_resolve_catalog_variant_import_printing_mapping`:
   - `no-e-reader`: 41 linhas em 3 jobs, 0 pendentes;
   - `missing-expansion-symbol`: 16 linhas em 1 job, 0 pendentes.

**Resultado:** 57 linhas em `VALID/PENDING`:

- STANDARD + NO_E_READER: 37;
- HOLO + NO_E_READER: 2;
- REVERSE_HOLO + NO_E_READER: 2;
- HOLO + MISSING_EXPANSION_SYMBOL: 16.

Nenhuma dessas identidades já existia em `card_variant`. `NEEDS_REVIEW` caiu de 140 para **83**.

**Confirmação:** Fabrício executou `NRR-CONFIRM-04_printing_errors_ready.sql` no SQL Editor em 2026-10-09. A verificação por leitura mostrou:

- **57 linhas** `INSERTED`, com 0 pendente;
- 41 variantes `NO_E_READER` e 16 `MISSING_EXPANSION_SYMBOL`;
- `card_variant` de 26.395 para **26.452**;
- 0 duplicidade e 0 FAILED;
- `NEEDS_REVIEW` em **83** e 25 jobs STAGED.

## Famílias não-erro — cosmos, peelable-ditto, set-logo SV, energy EX6 (2026-10-09)

Política de Fabrício para os erros únicos: avaliar a evidência caso a caso. Só vira Printing o que tiver reconhecimento externo; o resto fica retido (DEFERRED). As decisões por família foram:

| Família | Linhas | Decisão | Execução |
|---|---|---|---|
| Cosmos SV3 (Pawniard 148, `normal` + `cosmos`) | 1 | `COSMOS_HOLO`, só em sv03 | Mapping `SOURCE_SET` sv03 `NORMAL` + `COSMOS` → `COSMOS_HOLO` via `admin_resolve_catalog_variant_import_mapping_for_set` (preview `2194`: 1 linha, sem conflito). Evidência na Bulbapedia: versão Cosmos Holo no Shrouded Fable Kingambit Illustration Collection. |
| Peelable Ditto SWSH10.5 (Spinarak, Numel, Bidoof) | 3 | `REVERSE_HOLO` + Printing `PEELABLE_DITTO` | Seed `2241` (traits 11 → 12, sem ledger, em `database/seeds/`), profile `PEELABLE_DITTO` (ordem 14) e mapping de `subtype` `peelable-ditto` (3 linhas, 1 job). |
| Set-logo SV3/SV4 (Espeon, Umbreon, Iron Moth, Slither Wing) | 4 | **Retido até a D2** | Reverse com carimbo do nome da coleção, brinde de varejo. Espeon já tem a variante legada `SET_LOGO_REVERSE`; a sobreposição é da D2. |
| Energy EX6 (Dewgong, Drowzee holo; Magikarp reverse + rarity-error) | 3 | **Retido (DEFERRED)** | Sem evidência externa clara para "holo + energy" em FireRed & LeafGreen. |

**Resultado:** 4 linhas em `VALID/PENDING`, todas identidades inéditas em `card_variant`. `NEEDS_REVIEW` caiu de 83 para **79**: H3 57 + set-logo SV 4 + energy 3 + 15 erros únicos.

**Achado:** os jobs STAGED ainda têm 48 linhas `VALID/PENDING` e 64 `VALID/SKIPPED` que não vieram desta frente; são o resíduo deferido do BULK-STP. Os scripts de confirmação desta frente usam escopo por linha e não tocam nessas linhas.

**Confirmação:** Fabrício executou `NRR-CONFIRM-05_cosmos_ditto_ready.sql` em 2026-10-09. A verificação por leitura mostrou:

- 4 linhas `INSERTED` (3 `PEELABLE_DITTO` e 1 `COSMOS_HOLO`);
- `card_variant` de 26.452 para **26.456**;
- 0 duplicidade e 0 FAILED;
- `NEEDS_REVIEW` em 79 e 24 jobs STAGED;
- 48 linhas `VALID/PENDING` do resíduo BULK-STP intactas.

## Erros únicos — evidência caso a caso (2026-10-09)

Fabrício aprovou 8 famílias com evidência forte ou documentada. As fracas ficam DEFERRED.

| Família | Linhas | Evidência | Resultado |
|---|---|---|---|
| Dark Dragonite sem holo (BASE5) | 2 | PSA e CGC graduam a variedade | `HOLO` + `NO_HOLO_ERROR` / `FIRST_EDITION_NO_HOLO_ERROR`. Decisão de Fabrício: manter o acabamento do slot 5/82. |
| Butterfree "d Edition" (BASE2) | 1 | PSA "D EDITION ERROR" | `STANDARD` + `D_EDITION_ERROR` (mapping de `stamp`) |
| Blaine's Charizard, símbolo de energia (GYM2) | 1 | Artigo PSA; corrigido na Unlimited | `HOLO` + `ENERGY_SYMBOL_ERROR` |
| Pichu e Hoppip, verso japonês (ECARD1) | 2 | Bulbapedia: pré-lançamento da E3 2002 | `STANDARD` + `JAPANESE_BACK` |
| Phanpy "Phanphy" (COL1) | 2 | Bulbapedia / PokeBeach | `STANDARD` e `REVERSE_HOLO` + `TEXT_ERROR` |
| Rocket's Minefield Gym (GYM2) | 1 | Bulbapedia, lista de erros corrigidos | `STANDARD` + `TEXT_ERROR` |
| Marill sem custo de recuo (EX2) | 1 | Bulbapedia; ruling PUI | `STANDARD` + `MISSING_RETREAT_COST` |
| Exeggcute, energia deslocada (LC) | 1 | Lista de erros graduados pela CGC | `REVERSE_HOLO` + `SHIFTED_ENERGY_COST` |

**DEFERRED (evidência fraca, só anúncios):**

- Charmander com mancha de tinta (BASE5);
- Pinsir scratch 1ª Ed. (BASE2);
- Magikarp com erro de raridade (EX6, normal);
- Pikachu tail (BASE2, já estava em HOLD).

**Atualização 2026-10-10 — Pinsir e Pikachu reavaliados e aprovados por Fabrício:**

| Linha | Evidência nova | Resultado |
|---|---|---|
| Pinsir 9/64 (BASE2), stamp `1st-edition-scratch-error` | PSA tem spec própria ("1st edition-scratch error", spec 7961534); PSA Set Registry lista o card entre os erros da Jungle | `HOLO` + perfil `FIRST_EDITION_SCRATCH_ERROR` (seed `2248`, perfil ordem 23, mapping de `stamp`) |
| Pikachu 60/64 (BASE2), stamp `pikachu-tail` | Bulbapedia: a Jungle Pikachu 60/64 é uma das 9 reimpressões do Pikachu World Collection 2000 (carimbo dourado de cauda; versão em chinês) | `STANDARD` + EC `CAMPAIGN_PIKACHU_WORLD_2000` (rota EC `base2` igual à da BASEP no D2-02) |

Execução direta pelo agente (MCP), num único bloco com gates: trait + perfil + mapping + rota EC,
revalidação 2245 apply (1 linha) e decide/confirm das 2 linhas. Job BASE2 `7744b44c` COMPLETED;
`card_variant` 37.307 → 37.309. Continuam DEFERRED: Charmander tinta (BASE5) e Magikarp raridade (EX6),
além das 2 linhas energy EX6 (Dewgong, Drowzee). `NEEDS_REVIEW` em jobs abertos: **5**.

**Execução (pelo agente, via MCP):**

- Seed `2242`: 7 traits, total de 12 para 19. Sem ledger; promovida para `database/seeds/`.
- 8 perfis (ordens 15–22) via `admin_create_card_printing_profile_with_backfill`.
- 8 mappings via `admin_resolve_catalog_variant_import_printing_mapping`:
  - `stamp` `d-edition-error`;
  - 7 de `subtype`: `phanphy-error` e `text-error` vão para o mesmo trait `TEXT_ERROR`.

**Resultado:** 11 linhas em `VALID/PENDING`, todas identidades inéditas. `NEEDS_REVIEW` caiu de 79 para **68**:

- H3: 57;
- set-logo SV: 4;
- energy EX6: 3;
- DEFERRED fracos: 4.

**Confirmação:** Fabrício executou `NRR-CONFIRM-06_documented_errors_ready.sql` em 2026-10-09. A verificação por leitura mostrou:

- **11 linhas** `INSERTED`;
- `card_variant` de 26.456 para **26.467**;
- 0 duplicidade e 0 FAILED;
- `NEEDS_REVIEW` em **68** e 19 jobs STAGED;
- as 48 linhas `VALID/PENDING` do resíduo BULK-STP continuam intactas.

## H3 — pacote estrutural (2026-10-09, EXECUTADO após autorização de Fabrício)

**Execução:**

- `2243` via `apply_migration` (ledger `20261010003718`);
- `2244` via `execute_sql`, sem ledger;
- `2245` via `apply_migration` (ledger `20261010003802`). A aplicação foi por substituição textual do ramo H3 sobre a definição LIVE da 2239; os grants foram reconfirmados (`authenticated` sem EXECUTE).
- Os três arquivos foram promovidos para `database/migrations`, `database/seeds` e `database/schema`.

**Revalidação:** dry-run com plano de 57 linhas, 0 conflitos e 0 em H3. Apply no run `4627505e-3a74-4c03-9f4e-099aacaef87f`: 57 linhas em 12 jobs. Resultado:

| Acabamento | Edition Context | Linhas |
|---|---|---|
| REVERSE_HOLO | PROGRAM_LEAGUE | 40 |
| HOLO | PROGRAM_LEAGUE | 6 |
| REVERSE_HOLO | PROGRAM_LEAGUE__ROLE_STAFF | 5 |
| REVERSE_HOLO | PROGRAM_PLAYER_REWARDS | 2 |
| REVERSE_HOLO | PROGRAM_PROFESSOR | 2 |
| HOLO | PROGRAM_LEAGUE__ROLE_STAFF | 1 |
| STANDARD | PROGRAM_LEAGUE__ROLE_STAFF | 1 |

Nenhuma dessas identidades existia antes. `NEEDS_REVIEW` caiu de 68 para **11**, todas retidas de propósito:

- set-logo SV3/SV4: 4;
- energy EX6: 3;
- erros fracos DEFERRED: 4.

**Confirmação:** Fabrício executou `NRR-CONFIRM-07_h3_program_ready.sql` em 2026-10-09. A verificação por leitura mostrou:

- **57 linhas** `INSERTED`; com as 5 persistidas antes, o total de linhas de programa fica em 62;
- `card_variant` foi de 26.467 para **26.524**;
- 0 duplicidade e 0 FAILED;
- `NEEDS_REVIEW` em **11**, com 7 jobs STAGED.

## Encerramento da revisão das 557 (2026-10-09)

Das 557 linhas `NEEDS_REVIEW` que restavam depois da revalidação inicial, **546 foram materializadas** e **11 ficaram retidas de propósito**:

- set-logo em SV3/SV4: 4, aguardam a D2;
- energy foil de EX6: 3, DEFERRED;
- erros com evidência fraca: 4, DEFERRED.

Nos jobs STAGED ainda há 48 linhas `VALID/PENDING` e 64 `VALID/SKIPPED`. Elas são resíduo deferido do BULK-STP e ficam fora desta frente.

`card_variant` foi de 25.978 para **26.524** ao longo da revisão (+546).

### Proposta original (mantida como registro)

| Arquivo | O que faz |
|---|---|
| `2243_edition_context_axis_reads_foil.sql` | Amplia o CHECK `ck_cecem_raw_field` para incluir `foil`. Na `internal.resolve_variant_row_axes`, cria um bloco de `foil` no eixo 3, com o mesmo contrato do bloco de `subtype`. Sem mapping de `foil`, o comportamento é idêntico ao atual. |
| `2244_seed_edition_context_foil_program_mappings.sql` | Cria 3 mappings GLOBAIS de `foil` (`LEAGUE` → `PROGRAM_LEAGUE`, `PLAYER-REWARD` → `PROGRAM_PLAYER_REWARDS`, `PROFESSOR-PROGRAM` → `PROGRAM_PROFESSOR`) e o profile `PROGRAM_LEAGUE__ROLE_STAFF`. |
| `2245_revalidate_needs_review_lift_hold_h3.sql` | Cria a v2 da 2239: remove o HOLD H3; o resto fica idêntico. |

**Impacto medido:**

- Linhas não persistidas com esses `foil`: 57 (H3) mais 2 em jobs CANCELLED. Nenhum `card_variant` existente muda.
- Efeito permanente em importações futuras:
  - `normal + league` deixa de cair em `STANDARDS_LEAGUE` e passa a `STANDARD + PROGRAM_LEAGUE`;
  - `reverse + player-reward` em sv05 deixa de cair em `PLAYER_REWARD_REVERSE`.
- A reconciliação desses tipos legados vai para a D2.

**Resultado esperado após aplicar e revalidar:** as 57 linhas passam a VALID com acabamento pelo `type` e Edition Context pelo programa (Liga, Liga·Staff, Player Rewards ou Professor).
