# Fatia E — Remediação de Performance do ramo REFERENCE_POSITION

| Campo | Valor |
|-------|-------|
| **Pasta** | `database/proposals/2026-09-06-fatia-e-performance-remediation/` |
| **Rodada** | `-REMEDIATION-AUDIT-01` → `-REMEDIATION-STAGING-01` → `-AB-HARNESS-FINAL-FIX-01` → `-AB-EXECUTION-01` → `-REMEDIATION-IMPLEMENTATION-01` → `-POSTCHECK-2C-CORRECTION-STAGING-01`/`-EXECUTION-01` → `-FINAL-LIVE-PERFORMANCE-01` → `-CLOSEOUT-01` |
| **Status** | **`5102`/`5103` LIVE / VALIDATED / PERFORMANCE-MEASURED / PROMOVIDOS.** `5816` e `5817` executados. Ver seção 9. |
| **Banco alvo** | `qjfutqujxrbzgrtkpgkg` (mimikyu-core) |
| **Depende de** | `database/proposals/2026-09-06-fatia-e-reference-position-completion/` (`5100`/`5101` — executados e posteriormente **superados LIVE** por `5102`/`5103`; `5814`/`5815` como evidência histórica) |

---

## 1. O blocker encontrado pelo 5815

A Fatia E foi validada funcionalmente em `COLLECTIONS-POKEDEX-FATIA-E-IMPLEMENTATION-01`: 5100 e 5101 aplicados, `5814` v1.3 com **87 PASS / 0 FAIL** e zero resíduo.

Em seguida, `COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-EXECUTION-01` executou `5815` v1.2 sobre a Pokédex **NATIONAL real (1025 Positions)** e encontrou um **BLOCKER de performance**:

| cenário | Execution Time | shared hit blocks | classificação |
|---------|---------------:|------------------:|---------------|
| FULL_REFERENCE 1025 / 0 Assignments — summary | 32,8 ms | 799 | HEALTHY |
| FULL_REFERENCE 1025 / 828 Alloc — summary | **1357,8 ms** | **2 557 414** | **BLOCKER** |
| FULL_REFERENCE 1025 / 828 Alloc — positions FALSE | **1357,5 ms** | **2 557 418** | **BLOCKER** |
| FULL_REFERENCE 1025 / 828 Alloc — positions TRUE | **1357,8 ms** | **2 557 418** | **BLOCKER** |
| + 50 duplicatas (878 Alloc) — summary | **1454,1 ms** | **2 713 214** | **BLOCKER** |
| GENERATION_FILTERED 156 / 156 — summary | 44,7 ms | 73 677 | ATTENTION |
| + 200 fora do Scope (356 Alloc) — summary | 95,6 ms | 167 745 | ATTENTION |

`shared read = 0` em todos os 13 workloads: os números acima são o **melhor caso**, com cache quente.

---

## 2. Causa observada

Normalizando os buffers pelo produto `|Scope| × |Allocations da Collection|`, a razão é **constante em ~3,02 shared blocks por par**, estável em quatro estados independentes que variam em duas ordens de grandeza:

| estado | \|S\| × \|A\| | shared hit | blocks/par |
|--------|-------------:|-----------:|-----------:|
| FULL_REFERENCE high-density | 1025 × 828 = 848 700 | 2 557 414 | 3,013 |
| + 50 duplicatas | 1025 × 878 = 899 650 | 2 713 214 | 3,016 |
| GENERATION_FILTERED parcial | 156 × 156 = 24 336 | 73 677 | 3,028 |
| + 200 fora do Scope | 156 × 356 = 55 536 | 167 745 | 3,020 |

Os fatores previstos pelo produto batem com os medidos dentro de 0,1–0,5%. **O custo cresce com o PRODUTO, não com a soma.**

**Causa estrutural (grafo de junção).** Em `reference_position_numer` (5100) e em `satisfied` (5101), o Scope e `collection_allocation` são **irmãos**: ambos se ligam apenas ao `target` pelo mesmo `collection_id` constante e **não existe predicado direto entre eles**. O único predicado que os correlaciona — `a.pokedex_position_id = s.pokedex_position_id` — vive numa **terceira** relação. Qualquer ordem de junção precisa, em algum momento, combinar Scope e Allocations, e a forma atual não força nem favorece a única ordem que evita o produto.

**Nota de honestidade de evidência.** `INTERNAL PLAN VISIBILITY = NOT OBSERVABLE` — o EXPLAIN de uma chamada externa a estas funções expõe apenas `Function Scan`. Nenhuma alegação foi feita, em nenhum artefato desta rodada, sobre nós de scan internos efetivamente escolhidos pelo planner. O diagnóstico se apoia em tempo, buffers, cardinalidade, crescimento entre estados e no grafo de junção lido do corpo LIVE das funções.

---

## 3. Decisão de modelo — ALTERNATIVA B

Analisadas três alternativas em `COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-REMEDIATION-AUDIT-01`:

| | A — EXISTS dirigido pelo Scope | **B — satisfied pré-calculado** | C — índice composto |
|---|---|---|---|
| Elimina Scope × Allocations | ✗ | **✓** | ✓ |
| Índice novo | não resolve | **não precisa** | precisa |
| Coluna/trigger/backfill novos | não | **não** | sim |
| Blast radius | médio | **mínimo** | alto |
| Toca contrato da Fatia D | não | **não** | sim |

**A** foi descartada porque não corrige a assintótica com os índices atuais — ou revarre `|Allocations|` por Position (mesmo produto), ou entra pelo índice de `pokedex_position_id` e passa a depender do volume **global** de Assignments daquela Position em todas as Collections do banco.

**C** foi descartada porque nenhum índice composto resolve o problema: as duas colunas que precisariam ser combinadas — `collection_allocation.collection_id` e `collection_pokedex_position_assignment.pokedex_position_id` — vivem em **tabelas diferentes**. Só funcionaria denormalizando `collection_id` na tabela de Assignment, o que exige coluna nova, backfill, trigger e um invariante novo, colidindo com o contrato de Assignment imutável fechado na Fatia D.

**B — APROVADA.** Pré-calcular as Positions satisfeitas da Collection percorrendo `collection_allocation → collection_pokedex_position_assignment` (sem tocar o Scope) e **somente depois** intersectar esse conjunto com o Scope corrente. Complexidade esperada: **Θ(|Scope| + |Allocations|)** no lugar de Θ(|Scope| × |Allocations|).

---

## 4. Nenhum índice novo

B usa exclusivamente access paths que **já existem** no banco live (inventário confirmado por leitura direta de `pg_index`):

- `ix_collection_allocation_collection` sobre `collection_allocation(collection_id)` — resolve "as Allocations desta Collection";
- `collection_pokedex_position_assignment_pkey`, **UNIQUE** sobre `collection_pokedex_position_assignment(collection_allocation_id)` — resolve "o Assignment desta Allocation" em uma sonda, e garante no máximo **1 Assignment por Allocation**.

Nenhum arquivo desta pasta cria índice.

---

## 5. Arquivos

| Arquivo | O que é |
|---------|---------|
| `5102_update_collection_completion_summary_reference_position_performance.sql` | `CREATE OR REPLACE` incremental de `collection_completion_summary(uuid)`. Altera **somente** o numerator REFERENCE_POSITION. |
| `5103_update_collection_pokedex_scope_positions_performance.sql` | `CREATE OR REPLACE` incremental de `collection_pokedex_scope_positions(uuid,boolean)`. Altera **somente** a CTE `satisfied` e a cláusula ON do LEFT JOIN final. |
| `5816_performance_ab_fatia_e_reference_position_completion.sql` | **v1.1** — bateria A/B transacional: gate de equivalência semântica **fail-closed** + comparação de performance CURRENT vs CANDIDATE, sem tocar produção. |
| `5817_validate_fatia_e_reference_position_no_ux_dependencies.sql` | **v1.0** — validação incremental read-only que substitui exclusivamente a evidência do `5814` id 8 (POSTCHECK-2c). Ver seção 10. |
| `README.md` | Este arquivo. |

### 5102 / 5103 são correções **incrementais**

`5100` e `5101` permanecem como **artefatos históricos e nunca são reescritos** — mesma disciplina já aplicada em `5083` (que estendeu `5070` sem reescrevê-lo), em `6109`/`6110` e em `6125`/`6126`. `5102` e `5103` substituem os objetos vivos via `CREATE OR REPLACE`; o histórico da Fatia E fica legível na sequência 5100 → 5102 e 5101 → 5103.

### O que muda

**5102** — adiciona a CTE `reference_position_satisfied` (DISTINCT `collection_id`, `pokedex_position_id`, a partir de `target → collection_allocation → assignment`, sem referência ao Scope) e reescreve `reference_position_numer` como **interseção explícita** `reference_position_scope JOIN reference_position_satisfied` por `(collection_id, pokedex_position_id)`.

**5103** — reescreve `satisfied` na mesma forma (sem referência ao `scope`) e acrescenta a igualdade de `collection_id` à cláusula ON do LEFT JOIN final, já que `satisfied` passou a carregar essa coluna.

### O que **não** muda

Assinaturas · `RETURNS TABLE` · `LANGUAGE sql` · `STABLE` · `SECURITY DEFINER` · `SET search_path = ''` · ACL · fronteiras de autorização (`target`, `reference_position_target`) · `reference_position_scope` / `scope` · `reference_position_denom` · `standard_denom` / `standard_numer` / `master_denom` / `master_numer` · UNION de 3 branches · SELECT final (projeção, `p_only_missing`, `ORDER BY`) · **contratos externos**.

Efeito colateral esperado em 5103: com `satisfied` deixando de referenciar `scope`, o CTE `scope` passa a ser referenciado **uma única vez** e torna-se elegível a inlining pelo PostgreSQL — removendo também a barreira de materialização que existia na v1.0.

---

## 6. Semântica preservada

Regra inegociável mantida integralmente:

- **numerator = Scope corrente INTERSECT Assignments da mesma Collection.** Antes obtido implicitamente pelo triplo join; agora é uma interseção literal. Conjuntos provadamente iguais.
- **SPECIES_MATCH e USER_OVERRIDE contam igualmente** — nenhum filtro em `assignment_basis`.
- **Assignment fora do Scope**: permanece fisicamente; entra no conjunto satisfeito; é eliminado na interseção; **nunca** entra no numerator nem no denominator.
- **Duplicatas na mesma Position**: a PK única de Assignment garante 1 Assignment por Allocation; N duplicatas produzem N Assignments com o mesmo `pokedex_position_id`, colapsados pelo `DISTINCT`. Uma Position conta **uma** vez.
- **Primary Representative**: irrelevante, nunca consultado.
- **`card_primary_species`, `physical_card`, `card_variant`**: nunca consultados por este ramo.
- **STANDARD_SET e MASTER_SET**: intocados, byte-a-byte.
- **Segurança**: fronteira de autorização continua sendo o primeiro passo, com `auth.uid() IS NOT NULL` explícito e ownership reconstituído manualmente, nunca `is_admin()`. Não-enumeração preservada.

---

## 7. 5816 prova equivalência **antes** de qualquer aplicação live

`5816` roda inteiramente dentro de `BEGIN ... ROLLBACK`. As funções candidatas são criadas **dentro da transação**, com nomes distintos (`..._fatia_e_candidate`) — DDL de função é transacional no PostgreSQL, portanto o `ROLLBACK` as remove junto com fixtures, TEMP TABLEs e GRANTs. **As funções LIVE nunca são substituídas.**

**Gate de equivalência, antes de qualquer medição.** Para cada um dos 13 workloads: `count(CURRENT EXCEPT CANDIDATE) = 0` **e** `count(CANDIDATE EXCEPT CURRENT) = 0` **e** `rowcount_current = rowcount_candidate` (esta terceira condição captura regressões de multiplicidade que o `EXCEPT`, sendo set-based, esconderia). `summary` compara os 7 campos do contrato; `positions` compara os 5 campos do contrato congelado.

**O gate é FAIL-CLOSED** (`5816` v1.1, corrigido em `COLLECTIONS-POKEDEX-FATIA-E-AB-HARNESS-FINAL-FIX-01`). Se a equivalência falhar, `gate_summary()` / `gate_positions()` emitem `RAISE EXCEPTION` **imediatamente**, antes de qualquer `measure_pair` subsequente:

```
SEMANTIC_GATE_FAILED seq=% workload=% current_rows=% candidate_rows=%
current_except_candidate=% candidate_except_current=%
```

O `RAISE` aborta a CALL 1 inteira: nenhum workload do estado corrente é medido, nenhum estado posterior é executado, e o PostgreSQL desfaz a transação — fixtures, funções candidatas, TEMP TABLEs e GRANTs desaparecem, preservando o zero resíduo. A evidência necessária ao diagnóstico viaja na própria mensagem de erro.

A ordem em cada estado — **gates do estado → somente se todos passarem → `measure_pair` daquele estado** — somada ao `RAISE`, torna estruturalmente impossível produzir números de performance sobre uma candidata semanticamente divergente.

> A `v1.0` deste arquivo registrava a divergência mas seguia medindo (fail-open). Isso foi identificado como **BLOCKER** na auditoria direta e corrigido na `v1.1`. A decisão anterior de evitar `RAISE` "para não destruir evidência" está **superada**: a evidência está toda na mensagem do erro, e a prioridade do mandato é impedir que performance seja medida sobre semântica divergente.

**Defesa adicional:** `all_gates_passed` permanece no SELECT final. Se o PASSO 7 for alcançado, ele será `TRUE` por construção — qualquer outro valor indica falha do próprio harness e **REPROVA** a bateria.

**Medição A/B.** Os mesmos 13 workloads do `5815` v1.2, medidos para CURRENT e CANDIDATE = **26 planos**, com as **mesmas fixtures e dimensões**: NATIONAL 1025 · pool integral de Species resolvidas sem LIMIT · batching ≤ 500 · high-density · GENERATION_FILTERED · 50 duplicatas · até 200 fora do Scope. Alternância anti-viés de cache: `sequence_number` ímpar mede CURRENT primeiro, par mede CANDIDATE primeiro. Ambos os lados passam pelo mesmo helper, no mesmo estado de fixture, a instantes adjacentes.

Prefixo das fixtures: `AB-TEST-FATIA-E-%`, distinto do `PERF-TEST-FATIA-E-%` do 5815, para que os postchecks de resíduo das duas baterias nunca se confundam. O postcheck do PASSO 9 verifica também que **nenhuma função candidata sobreviveu ao ROLLBACK**.

### Critério de decisão

A candidata só avança se **todos** forem verdadeiros:

1. equivalência semântica 100% (13/13 gates);
2. nenhum runtime error;
3. o comportamento `Scope × Allocations` deixar de aparecer materialmente — verificável recalculando blocks/par: na CURRENT a constante é ~3,02; na CANDIDATE ela deve **deixar de ser constante**;
4. FULL_REFERENCE high-density com redução substancial frente aos ~1357 ms / ~2,56 M blocks;
5. duplicatas não recriarem comportamento multiplicativo;
6. out-of-scope crescendo com o número de Assignments acrescentadas, não com Scope × Assignments;
7. nenhuma regressão aparente nos estados vazios.

**Nenhum threshold artificial é fixado antes da medição.**

---

## 8. Ordem de execução prevista (quando houver GO)

1. **Precheck** — SHA-256 dos 3 SQL, estado live, resíduo `AB-TEST-FATIA-E-%` = 0, baseline de contagens físicas.
2. **`5816`** — CALL 1 (`BEGIN` → SELECT consolidado, última instrução) + CALL 2 (`RESET ROLE`/`ROLLBACK`/postchecks). Estratégia imposta pela limitação real do `execute_sql` (retorna apenas o result set da última instrução por chamada), já validada em `5814` e `5815` v1.2.
3. **Auditoria do resultado** contra os 7 critérios acima.
4. Somente se **aprovado**: autorização explícita para aplicar `5102` e `5103`.
5. Após aplicação: **reexecutar `5814` v1.3 INALTERADO** (87 casos) como regressão funcional obrigatória.
6. Somente então: promoção canônica e reconciliação documental.

---

## 9. Estado desta pasta

> **Atualizado em `COLLECTIONS-POKEDEX-FATIA-E-FINAL-DOC-CORRECTION-01` (2026-09-06).** As redações anteriores desta seção ("nada foi executado", depois "5817 NÃO EXECUTADO / 5815 NÃO executado / nenhum documento canônico tocado / nenhum arquivo promovido") descreviam momentos intermediários da cadeia e **não valem mais**. O estado final está abaixo.

| Artefato | Estado final |
|----------|--------------|
| `5102` | **CONFIRMADO EXECUTADO / LIVE / PROMOVIDO** para `database/schema/` — migration `20260906183951` |
| `5103` | **CONFIRMADO EXECUTADO / LIVE / PROMOVIDO** para `database/schema/` — migration `20260906184108` |
| `5816` v1.1 | **EXECUTADO** (A/B transacional, gate fail-closed) — **CANDIDATE PASS, 13/13**, zero resíduo |
| `5817` v1.0 | **EXECUTADO** — **1/1 PASS** |
| `5815` v1.2 (final) | **EXECUTADO contra as funções LIVE** — **13 HEALTHY / 0 ATTENTION / 0 BLOCKER** |

Nenhum índice criado (22 antes, 22 depois) — a remediação é exclusivamente de forma de junção.

**Promoção e documentação (estado corrente, após `-CLOSEOUT-01`):** `5102` e `5103` **foram promovidos** para `database/schema/`, com histórico incremental preservado e não foldado ao lado de `5100`/`5101`; corpo executável byte-idêntico ao auditado aqui. Os documentos canônicos **foram** atualizados — `docs/05d-colecoes-e-usuarios.md`, `docs/ROADMAP.md`, `docs/README.md`, `docs/INDEX.md` e `docs/log.md`. `5816`/`5817` **não** são schema e permanecem nesta pasta como evidência histórica de validação executada, junto com este README. Nenhum `git add` / `commit` / `push` em nenhuma rodada da cadeia.

---

## 10. `5814` id 8 (POSTCHECK-2c) — falso-positivo textual e a correção incremental `5817`

Rodada: `COLLECTIONS-POKEDEX-FATIA-E-POSTCHECK-2C-CORRECTION-STAGING-01`.

### O que aconteceu

Em `COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-REMEDIATION-IMPLEMENTATION-01`, com `5102` e `5103` já LIVE, o **`5814` v1.3 foi reexecutado INALTERADO** e retornou **87 casos / 86 PASS / 1 FAIL**. O único caso reprovado:

```
id 8 — POSTCHECK-2c - NAO contem Primary Representative/assignment_count/Physical Card/UX
```

### Por que falhou

A asserção do `5814` é textual sobre `pg_get_functiondef()`:

```sql
v_src NOT ILIKE '%primary_representative%'
AND v_src NOT ILIKE '%assignment_count%'
AND v_src NOT ILIKE '%physical_card%'
```

Duas causas somadas, ambas confirmadas por diagnóstico read-only:

1. **`_` é wildcard em LIKE/ILIKE.** `%primary_representative%` significa `primary` + *qualquer caractere* + `representative`. O comentário do `5103` contém a frase **"Primary Representative"** (com espaço) em **uma única linha**, e o espaço casa com o `_`. No `5101` a mesma frase estava quebrada em duas linhas, com quatro caracteres entre as palavras — por isso **não casava** e o caso passava.
2. **Token literal em comentário.** O comentário do `5103` contém literalmente `physical_card` na frase que explica que a função *nunca* consulta essas relações.

Ambas as ocorrências vivem **exclusivamente em linhas de comentário**. **A causa é o texto de comentário do `5103`, redigido durante o staging desta pasta** — não é defeito do `5814` nem regressão semântica.

### Decisões de governança

- **`5814` v1.3 permanece INTOCADO.** É evidência histórica já executada; seu resultado 86/87 fica registrado como está. Hash inalterado: `4d677b133ef917900d1864e9065782782c1a56b8c4e36f760cb804875ab19520`.
- **`5102` e `5103` permanecem LIVE e inalterados.** Sem rollback, sem edição. Hashes inalterados.
- **`pg_depend` NÃO é usado como prova.** Funções `LANGUAGE sql` com corpo textual não registram nesse catálogo todas as relações efetivamente referenciadas — ausência no catálogo **não** implica ausência no SQL. Usá-lo para afirmar ausência seria prova inválida por construção. O diagnóstico `pg_depend = 0` levantado durante o STOP fica registrado apenas como observação descartada, **não** como evidência.
- **`5817` é a correção incremental da evidência**, substituindo exclusivamente o id 8. Não repete nenhum dos outros 86 casos.

### Como `5817` prova

Obtém o corpo via `pg_get_functiondef()`, constrói uma representação **somente para análise** removendo comentários SQL — primeiro os block comments `/* ... */` (não-guloso, flag `s`), depois os line comments `-- ...` (flag `n`) — e então verifica por **comparação literal** com `position()` sobre `lower(source_sem_comentarios)`, **nunca** `LIKE`/`ILIKE`:

```
position('primary_representative' in exec_lower) = 0
position('assignment_count'       in exec_lower) = 0
position('physical_card'          in exec_lower) = 0
```

Registra ainda, **separadamente e fora do critério**, o contraste que torna o falso-positivo auditável em números: os mesmos tokens no source **bruto** por `position()` literal, e a **reprodução exata do padrão `ILIKE` do `5814`** sobre o bruto. O resultado esperado demonstra explicitamente que `primary_representative`/`physical_card` **podem aparecer no raw** enquanto os três tokens estão **ausentes do executable-source**.

Verifica na mesma passagem: assinatura `(uuid, boolean)`, `LANGUAGE sql`, `STABLE`, `SECURITY DEFINER`, `search_path = ''`, owner `postgres`, `authenticated` com EXECUTE, `anon` sem EXECUTE e nenhum GRANT a PUBLIC.

**Limitação declarada no próprio arquivo:** a remoção de comentários é lexical e não interpreta literais de string; um `--` dentro de um literal truncaria a linha. As funções da Fatia E não possuem literais com `--`, mas o stripper não deve ser reaproveitado cegamente.

`5817` é **100% read-only**: uma única instrução `SELECT`, sem escrita, sem fixture, sem índice, sem função criada, sem TEMP TABLE e sem transação explícita — portanto sem resíduo possível.

**Contrato de saída:** `case_label = 'POSTCHECK-2C-CORRECTED'`, `total_cases = 1`, `passed`/`failed` derivados da conjunção de todas as verificações de executable-source e de segurança.

### Resultado real da execução

Executado em `COLLECTIONS-POKEDEX-FATIA-E-POSTCHECK-2C-CORRECTION-EXECUTION-01` (2026-09-06), contra as funções live, sem alteração ao arquivo:

- **`total_cases = 1`, `passed = 1`, `failed = 0` — 1/1 PASS.**
- **13/13 checks TRUE** — os três tokens ausentes do executable-source (`position(...) = 0` para `primary_representative`, `assignment_count` e `physical_card`) mais as dez verificações de estrutura/segurança (assinatura `(uuid, boolean)`, `LANGUAGE sql`, `STABLE`, `SECURITY DEFINER`, `search_path = ''`, owner `postgres`, `authenticated` com EXECUTE, `anon` sem EXECUTE, nenhum GRANT a PUBLIC).
- **POSTCHECK-2c = falso-positivo textual CONFIRMADO.** O contraste registrado fora do critério reproduziu o comportamento do `5814`: o padrão `ILIKE` casa no source **bruto** (por causa dos comentários de `5103` e do `_` como wildcard) e não casa no executable-source. A causa é o texto de comentário, não regressão semântica.
- Zero resíduo por construção — instrução `SELECT` única, read-only.

### `5815` v1.2 — FINAL LIVE PASS

Reexecutado **inalterado** contra as funções live em `COLLECTIONS-POKEDEX-FATIA-E-FINAL-LIVE-PERFORMANCE-01` (2026-09-06): **13 HEALTHY / 0 ATTENTION / 0 BLOCKER**. High-density em 4,7–8,8 ms (reduções de 154× a 306× em tempo e ~1008×–1010× em buffers frente à medição pré-remediação), maior shared hit = 2 685, `shared read = 0` em todos os workloads, e custo marginal por Allocation invariante ao Scope (3,04 blocks em Scope de 1025 vs. 3,015 em Scope de 156). `INTERNAL PLAN VISIBILITY` permanece **NOT OBSERVABLE** — nenhuma alegação sobre nós de scan internos.
