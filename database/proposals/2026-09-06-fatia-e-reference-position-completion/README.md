# Staging — Collections Pokédex Fatia E (REFERENCE_POSITION Completion)

| Campo | Valor |
|--------|-------|
| **Mandato** | `COLLECTIONS-POKEDEX-FATIA-E-PHYSICAL-MODELING-AUDIT-01` → `-PHYSICAL-MODELING-REVISION-01` → `-STAGING-01` → `-STAGING-REVISION-01` → `-IMPLEMENTATION-01` → `-PERFORMANCE-01` (STOP) → `-PERFORMANCE-HARNESS-REVISION-01` → `-PERFORMANCE-EXECUTION-01` → `-CLOSEOUT-01` |
| **Data** | 2026-09-06 |
| **Status** | **EXECUTADO / PROMOVIDO / SUPERADO LIVE.** Ver seção "Estado final" abaixo. `5100`/`5101` foram aplicados ao banco real e **posteriormente superados LIVE** por `5102`/`5103` (pasta `2026-09-06-fatia-e-performance-remediation/`). `5814` e `5815` permanecem aqui como evidência histórica de validação/performance. |
| **Escopo** | Fechar o cálculo de completion para Collections Pokédex (`completion_policy = 'REFERENCE_POSITION'`, LDM-177/179/180/181/184): (1) estender `collection_completion_summary()` com um terceiro ramo mutuamente exclusivo; (2) criar um read model espelho de `collection_master_set_scope_positions()` para as Positions do Scope corrente + satisfação. |
| **Fora de escopo (explícito)** | Nenhum novo estado materializado (nenhuma tabela nova); nenhuma alteração em `collection_pokedex_reference`/`collection_pokedex_scope_generation` (Fatia B) nem em `collection_pokedex_position_assignment`/Primary Representative (Fatia D); nenhum índice novo; nenhum frontend. |

## Autoridade

Remapeamento confirmado em auditoria direta (`STAGING-REVISION-01`) —
substitui a numeração anterior deste documento:

- **LDM-177** (Collection Pokédex Scope — FULL_REFERENCE/GENERATION_FILTERED, derivado, nunca duplicado por construção).
- **LDM-179** (Pokédex Position Assignment — vínculo explícito Physical Card alocado → Position; múltiplos Assignments por Position permitidos; Allocation sozinha nunca satisfaz).
- **LDM-180** (Primary Representative é opcional e apresentacional — nunca insumo de completion).
- **LDM-181** (completion de uma Collection Pokédex é derivada do Scope corrente ∩ Assignments da própria Collection — nunca de todas as Assignments existentes, independente de Scope).
- **LDM-184** (correção editorial posterior de `card_primary_species`, Fatia C, não remove nem invalida Assignment já criada).

## Correção central desta rodada (herdada de MODELING-REVISION-01)

O `AUDIT-01` desenhou um numerator que contava **todas** as Assignments da Collection, sem interseção com o Scope corrente — violava LDM-177/LDM-181 ao contar Assignments preservadas fora do Scope (por exemplo, depois de uma mutação de Scope via `set_collection_pokedex_scope()`, Query 5099). A correção, fechada em `MODELING-REVISION-01` e implementada nesta rodada, torna o numerator uma interseção explícita entre `reference_position_scope` (Positions do Scope corrente) e as Assignments da Collection — uma Assignment fora do Scope permanece fisicamente preservada, mas nunca entra no denominator nem no numerator, em nenhuma das duas funções desta pasta.

## Arquivos desta pasta

| Arquivo | O que faz |
|---|---|
| `5100_update_collection_completion_summary_reference_position.sql` | `CREATE OR REPLACE` incremental de `collection_completion_summary()` (canônica em `5083` v3.0). Preserva `target`/`standard_denom`/`standard_numer`/`master_denom`/`master_numer`/SELECT final **byte-idênticos**. Adiciona 4 CTEs novas e independentes (`reference_position_target`, `reference_position_scope`, `reference_position_denom`, `reference_position_numer`) e estende os dois `UNION ALL` finais de 2 para 3 branches. |
| `5101_create_collection_pokedex_scope_positions_function.sql` | Nova função `public.collection_pokedex_scope_positions(p_collection_id UUID, p_only_missing BOOLEAN DEFAULT FALSE)` — espelho direto de `collection_master_set_scope_positions()` (5084). Ownership inteiramente na CTE `target`; `scope`+`satisfied` CTEs; `ORDER BY position_number, pokedex_position_id` obrigatório. |
| `5814_validate_fatia_e_reference_position_completion.sql` | Validação funcional (BEGIN/ROLLBACK, zero resíduo) — Pokédex de teste dedicado de 5 Positions (isolado do catálogo real, para tornar "Scope completo" e "Assignment fora do Scope" genuinamente controláveis), cobrindo os casos A–O do mandato. |
| `5815_performance_fatia_e_reference_position_completion.sql` | `EXPLAIN (ANALYZE, BUFFERS)` contra a Pokédex NATIONAL real (1025 Positions) em 5 cenários de volume. Nenhum índice novo. |

## Sequência de números confirmada livre (Glob + `execute_sql` nesta rodada — sem assumir)

```text
5100 - Update collection_completion_summary() — ramo REFERENCE_POSITION   [NOVO]
5101 - Create collection_pokedex_scope_positions() function               [NOVO]
5814 - Validação funcional Fatia E                                        [NOVO]
5815 - Performance Fatia E                                                [NOVO]
```

Confirmado ausente em `database/schema/` e em `database/proposals/**` (Glob), e confirmado que a função `collection_pokedex_scope_positions` não existe no banco real (projeto `qjfutqujxrbzgrtkpgkg`, `execute_sql` read-only). `5814`/`5815` seguem a faixa de validação/performance por incremento já usada em `5808`–`5813` (Collections) — não a faixa `6800`–`6830` (Pokémon Catalog/Fatia D), porque esta rodada estende objetos do milhar `5000`, não do `6000`.

Ordem de aplicação (se/quando autorizada): `5100` antes de `5101` (independentes entre si na verdade — nenhuma depende da outra fisicamente — mas `5100` é a extensão do objeto mais antigo e crítico, aplicada primeiro por prudência). `5814` depende de `5100`+`5101` já aplicadas. `5815` depende de `5814` ter confirmado corretude funcional (medir performance de uma função ainda não validada funcionalmente seria prematuro).

## Modelo físico resultante (resumo)

```text
collection_completion_summary(p_collection_id)
├── target            (CARD_SET — intocado, 5083)
├── standard_denom/numer   (STANDARD_SET — intocado, 5083)
├── master_denom/numer     (MASTER_SET — intocado, 5083)
└── reference_position_target/scope/denom/numer   (REFERENCE_POSITION — NOVO, 5100)
        collection → collection_reference(kind=POKEDEX) → collection_pokedex_reference
                                                              ├── FULL_REFERENCE: pokedex_position (todas)
                                                              └── GENERATION_FILTERED: pokedex_position
                                                                    JOIN pokemon_species
                                                                    JOIN collection_pokedex_scope_generation
        numerator = scope ∩ (collection_allocation → collection_pokedex_position_assignment)

collection_pokedex_scope_positions(p_collection_id, p_only_missing)
├── target   (mesma fronteira de autorização do ramo REFERENCE_POSITION de 5100)
├── scope    (mesma semântica + position_number/species_id/species_name)
└── satisfied (target → collection_allocation → collection_pokedex_position_assignment)
```

Nenhuma tabela nova. Nenhuma coluna nova em tabela existente. `collection_pokedex_position_assignment` (Fatia D, Query 6117) e `collection_pokedex_reference`/`collection_pokedex_scope_generation` (Fatia B, Queries 5087/5091) permanecem exatamente como estão — esta Fatia só os LÊ.

## Decisões confirmadas nesta rodada

**Decisão 1 — `target` não polimórfica.** Por instrução explícita de Fabrício (`MODELING-REVISION-01`, item 2), a CTE `target` de `5083` (CARD_SET-específica) não foi generalizada. Quatro CTEs novas e independentes cobrem REFERENCE_POSITION — mínimo blast radius, regressão zero de STANDARD_SET/MASTER_SET (provado em `5814`, Casos N/O).

**Decisão 2 — numerator via interseção explícita com o Scope.** Nunca `COUNT(*)` de todas as Assignments da Collection — sempre `reference_position_scope JOIN collection_allocation JOIN collection_pokedex_position_assignment` pela MESMA `pokedex_position_id` do Scope. Prova formal em `5814`, Caso J (Assignment fora do Scope existe fisicamente, nunca conta, nunca aparece no read model) e Caso K (mutação de Scope recalcula sem tocar a Assignment).

**Decisão 3 — SPECIES_MATCH e USER_OVERRIDE contam igualmente.** Nenhum filtro em `assignment_basis` em nenhuma das duas funções. Provado em `5814`, Casos G/H (Collection completa combinando os dois `assignment_basis`).

**Decisão 4 — Primary Representative e `card_primary_species` nunca consultados (LDM-180).** Nem `5100` nem `5101` fazem JOIN com `collection_pokedex_position_primary_representative` ou `card_primary_species` — completion é derivada exclusivamente de Scope + Assignment. Provado em `5814`, Caso I (criar / trocar entre duas Assignments da mesma Position / remover o Primary Representative — completion idêntica nos três estados).

**Decisão 5 — zero-denominator via `LEFT JOIN` + `count()`, sem `CASE` no ramo novo.** `reference_position_denom` usa `LEFT JOIN reference_position_target → reference_position_scope`; quando o Scope tem 0 linhas, `count()` do lado direito retorna 0 nativamente — mesmo padrão de `standard_denom`/`master_denom`. A defesa explícita de zero-denominator no `SELECT` final (`total_positions = 0 → progress=0.00, is_complete=false`) permanece intocada e já cobre os três ramos por não referenciar nenhum por nome.

**Decisão 6 — nenhum índice novo.** Índices já existentes (`idx_collection_pokedex_position_assignment_position_id`, Query 6117; as duas `UNIQUE(pokedex_id, ...)` de `pokedex_position`, Query 6040) já cobrem os JOINs dos dois objetos novos. `5815` mede; não cria.

**Decisão 7 — `5815` não fabrica completion 100% artificial (confirmada em `STAGING-REVISION-01`).** `5814` já prova semanticamente o estado COMPLETE (Caso E), com um Pokédex de teste pequeno e totalmente controlado — não é necessário, nem é objetivo de `5815`, forçar as 1025 Positions da Pokédex NATIONAL real a 100% via USER_OVERRIDE artificial. `5815` mede exclusivamente plano de execução/tempo em escala real: consome TODO o pool de Species resolvidas disponível no catálogo real (sem cap artificial), em lotes de no máximo 500 por chamada — o teto real de `add_physical_cards()` e de `allocate_physical_cards_to_collection()` (Query 5046 v1.2, confirmado por leitura direta do código-fonte) — via um laço `WHILE` que consome o pool inteiro, nunca um número fixo de "batches". A v1.0 desta Query continha uma divergência entre cabeçalho (alegava duas chamadas cobrindo até 1000 Species) e código (executava só um batch de até 500) — corrigida nesta revisão.

## Riscos restantes

- **R1 (baixo).** `5101` duplica a lógica de `scope` já presente em `5100` (necessário — são objetos SQL distintos, `LANGUAGE SQL` não suporta CTEs compartilhadas entre funções). Qualquer mudança futura em LDM-177 (nova forma de Scope) exige editar os dois arquivos em conjunto — risco de divergência silenciosa entre summary e read model se um for atualizado sem o outro. Mitigação: nenhuma nesta rodada além de comentários cruzados nos dois cabeçalhos.
- **R2 (baixo).** `5814` usa um Pokédex de teste isolado (5 Positions) em vez da Pokédex NATIONAL real — decisão deliberada para tornar os casos E (completa) e J (fora do Scope) genuinamente controláveis sem depender de nenhuma Generation real estar 100% coberta por `card_primary_species` (condição hoje desconhecida). `5815` compensa medindo performance contra a Pokédex NATIONAL real (1025 Positions).
- **R3 (baixo, esperado).** `create_reference_based_pokedex_collection()` (5098) e `set_collection_pokedex_scope()` (5099) não foram alteradas nesta rodada — nenhuma mudança nelas era necessária; confirmado por leitura direta nesta auditoria.

## Divergências entre LDM e banco

Nenhuma divergência nova encontrada nesta rodada — a única correção necessária (numerator Scope-aware) já havia sido identificada e fechada em `MODELING-REVISION-01`, antes deste staging.

## Não realizado no ciclo de staging (registro histórico)

No ciclo `-STAGING-01`/`-STAGING-REVISION-01` nenhuma migration foi executada, nenhum `docs/*.md` foi editado, nenhuma promoção foi feita e nenhum `git add`/`commit`/`push` foi realizado. **Esse parágrafo descreve apenas aquele momento** — o estado corrente está na seção seguinte.

---

## Estado final (`COLLECTIONS-POKEDEX-FATIA-E-CLOSEOUT-01`, 2026-09-06)

| Artefato | Estado |
|----------|--------|
| `5100` | **EXECUTADO / PROMOVIDO / SUPERADO LIVE por `5102`.** Aplicado em `-IMPLEMENTATION-01`; promovido para `database/schema/`. O corpo vivo de `collection_completion_summary()` hoje é o de `5102`. |
| `5101` | **EXECUTADO / PROMOVIDO / SUPERADO LIVE por `5103`.** Aplicado em `-IMPLEMENTATION-01`; promovido para `database/schema/`. O corpo vivo de `collection_pokedex_scope_positions()` hoje é o de `5103`. |
| `5814` v1.3 | **EVIDÊNCIA HISTÓRICA — permanece aqui, intocado.** Executado duas vezes: (1) contra `5100`/`5101` → **87/87 PASS**; (2) contra `5102`/`5103` → **86/87 PASS**, com o único FAIL sendo o id 8 (POSTCHECK-2c), **falso-positivo textual conhecido**. Ver seção 10 do README da pasta de remediação. |
| `5815` v1.2 | **EVIDÊNCIA HISTÓRICA — permanece aqui.** Executado duas vezes: (1) contra `5100`/`5101` → **BLOCKER de performance** (high-density ~1,36 s / ~2,56 M shared hits, custo ∝ \|Scope\| × \|Allocations\|); (2) contra `5102`/`5103` LIVE → **13 HEALTHY / 0 ATTENTION / 0 BLOCKER**. |

**Histórico incremental preservado, por decisão explícita:** `5100 → 5102` e `5101 → 5103`. Os pares **não** foram fundidos; os quatro arquivos vivem lado a lado em `database/schema/`, e a leitura sequencial dos números reconstitui a história material da Fatia E (implementação inicial → remediação de performance).

Nenhum índice foi criado em nenhuma das rodadas. Zero resíduo confirmado em todas as execuções. Ver `database/proposals/2026-09-06-fatia-e-performance-remediation/README.md` para o detalhamento da remediação, do A/B e da correção de evidência do POSTCHECK-2c.
