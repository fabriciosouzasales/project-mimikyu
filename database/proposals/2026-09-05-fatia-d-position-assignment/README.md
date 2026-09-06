# Staging — Collections Pokédex Fatia D — Position Assignment + Primary Representative

| Campo | Valor |
|--------|-------|
| **Pasta** | `database/proposals/2026-09-05-fatia-d-position-assignment/` |
| **Status** | **CLOSED / PROMOTED.** `6117`-`6126` `CONFIRMADO EXECUTADO` no banco real (projeto `qjfutqujxrbzgrtkpgkg`) e promovidos para `database/schema/` em `COLLECTIONS-POKEDEX-FATIA-D-PROMOTION-CLOSEOUT-01`. Seção 3 de `6830` concluída (Casos 1-24, zero FAIL residual — histórico de FAILs/SUPERSEDED preservado abaixo); único item não provado é o Caso 20b (`NOT EXECUTED / UNPROVEN`, aprovado como tal). Cleanup de fixtures/tabelas de rastreio concluído com zero-resíduo confirmado por identidade. `6830` permanece em `database/proposals/` como evidência de validação (não é schema, não promovido). |
| **Rodadas de origem** | `COLLECTIONS-POKEDEX-FATIA-D-PHYSICAL-MODELING-AUDIT-01` (auditoria read-only) → `-PHYSICAL-MODELING-REVISION-01` (imutabilidade da Assignment, prova de compatibilidade com fluxo UX atômico futuro, confirmações de Primary Representative) → `-STAGING-01` (staging físico) → `-STAGING-AUDIT-01` (GATE 4 — 3 correções pontuais: `6118`/`6119`/`6122`) → `-IMPLEMENTATION-01` (aplicação real, PAUSADA em `6122` por auditoria independente de Fabrício) → `PAUSE-SQL-DIRECT-AUDIT-01` (6 correções adicionais) → `RENUMBER-FIX-STAGING-01` (renumeração dos arquivos ainda não aplicados) → `6830-DIRECT-REVIEW-FIX-01`/`-FIX-02` (correções do roteiro de validação) → `IMPLEMENTATION-RESUME-02` (aplicação real de `6123`-`6125` + Seção 3 completa) → `6126-STAGING-01`/`-IMPLEMENT-RESUME-01` (bug funcional SQLSTATE 42702 e correção) → `FINAL-VALIDATION-CLEANUP-01` (Caso 16 explícito + cleanup + zero-resíduo) → `PROMOTION-CLOSEOUT-01` (promoção para `database/schema/` e fechamento, esta versão) |
| **Data** | 2026-09-05 |
| **Pré-requisito físico** | Fatia C (Card → Primary Species, `2159`/`6112`-`6116`, commit `ff613066`) e Fatia B (Collection Pokédex Reference / Adopted Scope, `5085`-`5099`) já `CONFIRMADO EXECUTADO`. Fatia A (`pokedex`/`pokedex_position`/`pokedex_external_reference`, `6030`-`6051`) já `CONFIRMADO EXECUTADO`, ainda com zero linhas (sourcing PokéAPI suspenso). |

## Objetivo

Materializar fisicamente LDM-179 (Pokédex Position Assignment) e LDM-180 (Primary Representative) — o vínculo explícito entre um Physical Card alocado a uma Collection Pokédex e uma `pokedex_position`, e a escolha opcional de qual exemplar representa cada Position. Não implementa completion (LDM-181) — isso é Fatia E, deliberadamente fora de escopo.

## Sequência de migrations

| Query | Arquivo | Conteúdo |
|---|---|---|
| 6117 | `6117_create_collection_pokedex_position_assignment_table.sql` | Tabela `collection_pokedex_position_assignment` (PK/FK compartilhada `collection_allocation_id`) |
| 6118 | `6118_create_collection_pokedex_position_assignment_triggers.sql` | Trigger de exigência de ator em `USER_OVERRIDE` (BEFORE INSERT, `STAGING-AUDIT-01` item 1) + trigger de match Position↔Pokédex (BEFORE INSERT) + governança de imutabilidade com exceção técnica (BEFORE UPDATE) |
| 6119 | `6119_create_auto_species_match_after_allocation_trigger.sql` | Trigger `AFTER INSERT` em `collection_allocation` — auto-`SPECIES_MATCH`, restrito a Collections `mode = 'REFERENCE_BASED'` (explícito desde `STAGING-AUDIT-01` item 2) |
| 6120 | `6120_create_collection_pokedex_position_primary_representative_table.sql` | Tabela `collection_pokedex_position_primary_representative` (FKs explícitas, PK composta) |
| 6121 | `6121_create_primary_representative_integrity_trigger.sql` | Trigger de integridade cruzada Collection+Position + touch de `updated_at` |
| 6122 | `6122_create_set_pokedex_position_assignment_function.sql` | RPC `set_pokedex_position_assignment()` — cria ou move (DELETE+INSERT); checagem de no-op reordenada para logo após ownership+lifecycle (`STAGING-AUDIT-01` item 3). **JÁ APLICADA** ao banco real — correções de `PAUSE-SQL-DIRECT-AUDIT-01` entram via `6123` (incremental), este arquivo permanece como registro histórico exato do que foi executado |
| 6123 | `6123_fix_fatia_d_applied_objects_pause_sql_direct_audit.sql` | **NOVO, renumerado de 6125 em `RENUMBER-FIX-STAGING-01`** — migration incremental (`CREATE OR REPLACE`) para os 3 objetos JÁ APLICADOS ao banco real (`6118`/`6119`/`6122`): REFERENCE_BASED explícito no trigger 6118, POKEMON explícito em 6119, e em 6122 — NULL fail-closed, RETURNING/WHERE qualificados, lock Collection-first. Precisa ser aplicada ANTES de 6124/6125 abaixo — número escolhido para refletir essa ordem cronológica |
| 6124 | `6124_create_remove_pokedex_position_assignment_function.sql` | RPC `remove_pokedex_position_assignment()` — renumerado de 6123. v1.2: lock Collection-first + WHERE/RETURNING qualificados (`PAUSE-SQL-DIRECT-AUDIT-01`) |
| 6125 | `6125_create_primary_representative_functions.sql` | RPCs `set_/clear_pokedex_position_primary_representative()` — renumerado de 6124. v1.2: lock Collection-first + RETURNING qualificada em `set_...` (`PAUSE-SQL-DIRECT-AUDIT-01`); `clear_...` já estava correta |
| 6830 | `6830_validate_fatia_d_position_assignment.sql` | Validação — SQL ESTÁTICO executável hoje + roteiro de TESTE FUNCIONAL (24 casos + 2 novos: 2b e 20b) — v1.5: Caso 7 e Caso 8 reescritos (PAUSE-SQL-DIRECT-AUDIT-01); referências de numeração atualizadas (RENUMBER-FIX-STAGING-01); estado físico real, contexto/role por Caso de DML direto, Caso 10 dividido em duas provas, Caso 20b reforçado, Seção 1.7 reescrita com `aclexplode` (6830-DIRECT-REVIEW-FIX-01); Seção 1.7 corrigida (coluna inexistente + expectativa owner+authenticated) e sugestão de `service_role`/BYPASSRLS removida (6830-DIRECT-REVIEW-FIX-02) |

Numeração confirmada livre em `database/schema/` no momento desta auditoria (até `6116`/`6700`/`6701`; `6117` em diante disponível). Numeração de `6123`-`6125` fixada nesta rodada (`RENUMBER-FIX-STAGING-01`) para refletir a ordem cronológica real de aplicação — ainda sujeita a confirmação de Fabrício antes de qualquer `apply_migration`. `6830` segue a mesma convenção de `6800`/`6810`/`6820`/`6821` (validação, milhar `68xx`).

## Decisões físicas centrais

- **Cardinalidade da Assignment**: PK/FK compartilhada em `collection_allocation_id` (não um par `physical_card_id`+`collection_id` duplicado) — aproveita que `collection_allocation.physical_card_id` já é `UNIQUE` globalmente. Mesmo padrão supertipo/subtipo de PK compartilhada já usado em `collection_reference`/`collection_pokedex_reference` (02D).
- **Imutabilidade (Revision-01)**: a linha de Assignment só existe via INSERT/DELETE — mover é sempre DELETE da linha antiga + INSERT de uma nova, na mesma transação de RPC. Única exceção estrutural: `assigned_by_user_id` pode transicionar de preenchido para `NULL` (efeito de `ON DELETE SET NULL` quando o usuário que confirmou um `USER_OVERRIDE` é excluído), com todos os outros campos obrigatoriamente inalterados — reforçado por trigger dedicado.
- **Auto-`SPECIES_MATCH`**: trigger `AFTER INSERT` em `collection_allocation` (não uma segunda RPC) — Allocation já é uma operação síncrona de até 500 itens na mesma transação; nenhuma mudança de assinatura em `allocate_physical_cards_to_collection()`.
- **Primary Representative como entidade separada** (não boolean na Assignment) — evita denormalizar `collection_id` na Assignment só para viabilizar um índice único parcial. Cardinalidade "no máximo um Primary por Collection+Position" vem de graça da PK composta.
- **Scope (LDM-177) nunca participa** de nenhuma constraint/trigger desta Fatia — Assignment pode existir fora do Scope corrente; isso é assunto exclusivo do numerador de completion (Fatia E).
- **Compatibilidade com fluxo UX atômico futuro** (Revision-01, item 2): provado, não implementado — `allocate_physical_cards_to_collection()` e `set_pokedex_position_assignment()` são funções `plpgsql` comuns no mesmo schema; uma futura RPC orquestradora pode compô-las na mesma transação sem duplicar nenhuma validação. Nenhuma RPC `fill_pokedex_position_slot` foi criada nesta rodada.

## Invariantes estruturais

1. Position pertence ao Pokédex referenciado pela Collection (trigger `6118`/trg_010, revalidado em `6122`).
2. 1 Allocation → no máximo 1 Assignment (PK física).
3. Assignment imutável, salvo a exceção técnica de `assigned_by_user_id` (trigger `6118`/trg_020).
4. Desalocar OU mover uma Assignment remove qualquer Primary Representative associado, via `ON DELETE CASCADE` — nenhum trigger de sincronização adicional.
5. Primary Representative: no máximo um por (Collection, Position) (PK física de `6120`); sempre pertence à Assignment/Position declarada (trigger `6121`); nunca órfão após remoção/movimento de Assignment (CASCADE).
6. Nenhuma escrita direta de cliente em nenhuma das duas tabelas — 4 RPCs `SECURITY DEFINER`, `search_path=''`, ownership via `auth.uid()`, `Collection.lifecycle_status = 'ACTIVE'` obrigatório.
7. `assignment_basis = 'USER_OVERRIDE'` exige `assigned_by_user_id IS NOT NULL` no momento da criação — reforçado estruturalmente por trigger dedicado (`6118`/trg_005, `STAGING-AUDIT-01` item 1), não apenas pela lógica da RPC. Nunca via `CHECK` constraint, para preservar a ação `ON DELETE SET NULL` (Query 6117).

## Riscos / pontos de atenção para a rodada de implementação

- O script de validação (`6830`) não pode ser um bloco transacional único e autossuficiente: `collection.owner_user_id`/`inventory.owner_user_id` têm FK real para `auth.users`, e este projeto nunca insere diretamente nessa tabela (gerenciada pelo serviço de Auth do Supabase) — mesma limitação já documentada em `5804`/`5806` (2B/2C). A Seção 1 (SQL ESTÁTICO) e a Seção 2 (fixtures de catálogo puro, sem Collection) são executáveis como estão; a Seção 3 é um roteiro de `TESTE FUNCIONAL` que exige um usuário de teste real no momento da execução. **Os casos funcionais owner-scoped deverão ser executados de verdade com rollback; roteiro sozinho não fecha a Fatia D** — a Seção 3 documenta o procedimento e o resultado esperado de cada caso, mas nenhum desses 24 itens está confirmado como comportamento real do banco até rodar de fato, na rodada de implementação, contra um usuário de teste real.
- `pokedex`/`pokedex_position` ainda têm zero linhas em produção (sourcing PokéAPI suspenso) — os 24 casos de validação dependem de fixtures sintéticas de catálogo (Species/Pokédex/Position de teste), não de dados reais.

## GATE 4 — STAGING-AUDIT-01 (correções aplicadas)

Auditoria focada sobre os arquivos exatos staged (`6117`-`6124`, `6830`, README — numeração da época, anterior a `RENUMBER-FIX-STAGING-01`) encontrou 3 divergências pontuais de implementação dentro do modelo já aprovado — nenhuma delas uma divergência estrutural do contrato congelado (Revision-01/Staging-01), portanto nenhum `STOP` foi necessário:

1. **`6118`** — nada impedia estruturalmente uma linha `USER_OVERRIDE` com `assigned_by_user_id NULL` (só a RPC garantia isso). Corrigido com `trg_005` (BEFORE INSERT), nunca via `CHECK` — preserva a ação `ON DELETE SET NULL`.
2. **`6119`** — o JOIN de auto-`SPECIES_MATCH` checava só `reference_kind = 'POKEDEX'`, assumindo implicitamente `mode = 'REFERENCE_BASED'`; essa implicação só é garantida em uma direção. Corrigido com `AND col.mode = 'REFERENCE_BASED'` explícito no JOIN.
3. **`6122`** — a checagem de no-op ("mesma Position → no-op real") rodava depois da resolução de `SPECIES_MATCH`/`USER_OVERRIDE`, podendo bloquear indevidamente uma reafirmação idempotente se a evidência de Species tivesse mudado depois da Assignment original. Corrigido reordenando o no-op check para logo após ownership+lifecycle, antes de qualquer outra validação.

`6830` e este README foram atualizados para refletir as 3 correções (novos casos 1b, 3b, 21b; trigger `trg_005` na lista esperada da Seção 1.4).

## PAUSE-SQL-DIRECT-AUDIT-01 (correções desta rodada, AGUARDANDO REVISÃO)

A implementação real (`COLLECTIONS-POKEDEX-FATIA-D-IMPLEMENTATION-01`) aplicou `6117`-`6122` ao banco real e foi PAUSADA por Fabrício antes do que era `6123` na numeração original, após uma auditoria independente linha a linha encontrar 6 divergências materiais adicionais, nenhuma delas capturada pelo GATE 4. Nenhuma das correções abaixo foi executada — apenas staged, aguardando aprovação. Numeração dos arquivos corrigidos abaixo já reflete `RENUMBER-FIX-STAGING-01` (ver seção própria mais abaixo) — onde a numeração original é citada por clareza histórica, está marcada como "(original)".

**Divergência factual identificada e corrigida nesta rodada**: a auditoria presumiu que os arquivos hoje numerados `6122` e `6124`/`6125` ainda não haviam sido aplicados. Confirmado via `pg_get_functiondef()` que `6122` (`set_pokedex_position_assignment`) JÁ ESTÁ aplicada e viva no banco real — só `6124`/`6125` (remove e Primary Representative) seguem não aplicados. Por isso a correção de `6122` foi entregue como migration incremental (`6123`, `CREATE OR REPLACE`), não como edição do arquivo `6122` histórico — mesma convenção já usada para `6118`/`6119`.

1. **`p_confirm_override` NULL** (item 1) — `IF NOT p_confirm_override` tratava `NULL` como falso-negativo (`NOT NULL = NULL`, `IF NULL` não entra no bloco), permitindo criar `USER_OVERRIDE` sem confirmação real quando o chamador passasse `NULL` explícito. Corrigido para `IF p_confirm_override IS DISTINCT FROM TRUE` em `6122` (via `6123`).
2. **RETURNING/WHERE ambíguos** (item 2) — confirmado via `SHOW plpgsql.variable_conflict` que o projeto real roda com `'error'`. `6122`/`6124`/`6125` tinham colunas bare (`collection_allocation_id`, `pokedex_position_id`, etc.) que colidem com os OUT-parameters do `RETURNS TABLE` de mesmo nome — ambíguo em tempo de execução, nunca capturado em `CREATE FUNCTION`. Achado mais amplo que o mandato original: a mesma ambiguidade também afetava a cláusula `WHERE` do `DELETE` em `6122`/`6124`, não só a `RETURNING`. Corrigido qualificando pelo nome da tabela em todos os pontos, padrão canônico de `5046`/`5047`.
3. **Lock order / concorrência** (item 3) — `6122`/`6124`/`set_pokedex_position_primary_representative` (`6125`) travavam a linha de `collection_allocation` ANTES de qualquer lock em `collection`, sem nenhuma proteção real contra `archive_collection()` concorrente. Corrigido para travar Collection PRIMEIRO (`FOR UPDATE`, ownership na própria `WHERE`, padrão `5046`/`5047`), só então revalidar e travar a Allocation. `clear_pokedex_position_primary_representative` já seguia esse padrão desde a v1.0.
4. **REFERENCE_BASED explícito** (item 4) — `6118`/trg_010 e `6122` validavam só `reference_kind = 'POKEDEX'`, sem `mode = 'REFERENCE_BASED'` explícito (mesma implicação one-way já corrigida em `6119` no GATE 4). Corrigido em `6122` (via `6123`, RPC) e via `6123` (trigger de `6118`, incremental).
5. **POKEMON explícito em 6119** (item 5) — o trigger de auto-SPECIES_MATCH dependia implicitamente da existência de `card_primary_species` para inferir "é POKEMON", sem checar `card_category.code`. Corrigido via `6123` (incremental).
6. **6830** (item 6) — Caso 8 reescrito (usava `USER_OVERRIDE` sem ator, interceptado por `trg_005` antes de provar a PK; agora usa `SPECIES_MATCH`); Caso 7 reescrito (chamava a RPC para a Position já atribuída — um no-op que não prova CREATE/MOVE fora do Scope; agora usa uma Allocation sem Assignment ainda); novo Caso 2b (`p_confirm_override = NULL`); novo Caso 20b (concorrência lifecycle, exige conexões reais); reforço transversal para capturar a `RETURNING` real das RPCs nos casos de CREATE/MOVE/SET/REPLACE.

Arquivos afetados nesta rodada (numeração já pós-renumeração): `6124`/`6125` editados diretamente (staging, nunca aplicados); `6123` criado (migration nova, incremental, para os 3 objetos já aplicados); `6830` reescrito; este README atualizado. `6117`-`6122` permanecem inalterados como registro exato do que foi de fato executado.

## RENUMBER-FIX-STAGING-01 (ajuste de numeração, sem mudança funcional)

Após `PAUSE-SQL-DIRECT-AUDIT-01`, Fabrício pediu para a sequência física dos arquivos AINDA NÃO APLICADOS refletir a ordem cronológica real de aplicação futura — a migration incremental que corrige `6118`/`6119`/`6122` (objetos já vivos) precisa necessariamente ser aplicada ANTES de `remove_pokedex_position_assignment()` e das RPCs de Primary Representative, então ela não deveria ficar numerada depois delas.

Renumeração aplicada (arquivos renomeados via `mv`, nenhum SQL executado):
- Migration incremental (`6118`/`6119`/`6122`): **6125 → 6123**.
- `remove_pokedex_position_assignment()`: **6123 → 6124**.
- RPCs de Primary Representative (`set_/clear_...`): **6124 → 6125**.
- `6830` permanece `6830` — só teve suas referências internas de numeração atualizadas (v1.2 → v1.3).

Nenhum conteúdo funcional foi alterado nesta rodada — apenas nomes de arquivo, o campo "Query......." dos headers, e comentários/referências cruzadas que citavam os números antigos (em `6117`, `6120`, `6121`, `6830` e neste README). `6117`-`6122` (já aplicados) tiveram apenas seus comentários internos que citavam `6123`/`6124` (numeração antiga) corrigidos para os novos números — nenhuma mudança de comportamento, já que esses arquivos continuam intactos como registro do que foi de fato executado.

## 6830-DIRECT-REVIEW-FIX-01 (correção do roteiro de validação, `6123`/`6124`/`6125` intactos)

Fabrício executou uma auditoria direta linha a linha dos arquivos SQL exatos de `6123`/`6124`/`6125` (pós-renumeração) e concluiu **PASS — sem alteração** para os três. A mesma auditoria encontrou 4 problemas no roteiro de validação `6830` (metodologia de teste, não os objetos SQL sob teste):

1. **Estado físico desatualizado no header/Descrição/Pré-requisitos** — `6830` ainda afirmava que "nenhuma das Queries 6117-6125 foi aplicada", falso desde a implementação real de `6117`-`6122`. Corrigido para declarar explicitamente: `6117`-`6122` `CONFIRMADO EXECUTADO`; `6123`-`6125` `PROPOSTO`/não executados (`6123` = migration incremental sobre objetos já vivos; `6124`/`6125` = primeira aplicação).
2. **Contexto/role incorreto nos Casos de DML direto** (1b, 3b, 8, 9, 10, 17) — esses Casos fazem `INSERT`/`UPDATE` direto nas duas tabelas para isolar trigger/constraint, bypassando as RPCs; mas `authenticated` deliberadamente não tem `INSERT`/`UPDATE`/`DELETE` nelas (invariante 6). Rodar esses Casos como `authenticated` produziria "permission denied for table" ANTES de qualquer trigger/constraint ser exercido — um falso-positivo se confundido com o resultado esperado. Cada Caso agora anota explicitamente o contexto/role privilegiado exigido (table owner, dentro de transação com `ROLLBACK`), a exceção/constraint ESPECÍFICA a validar (nunca "permission denied" genérico como PASS), e a necessidade de restaurar o contexto `authenticated` + `request.jwt.claim.sub` do owner de teste antes de prosseguir.
3. **Caso 10 misturava duas provas distintas** — dividido em Prova A (`pg_constraint`, confirma que a FK de `assigned_by_user_id` é `ON DELETE SET NULL` contra `auth.users(id)`) e Prova B (UPDATE privilegiado, confirma apenas que `trg_020` aceita essa transição técnica específica — sem afirmar que reproduz uma exclusão real de usuário). Nenhum usuário de teste real foi criado/apagado só para isto.
4. **Caso 20b (concorrência) dependia de leitura estática do código** — reforçado para exigir evidência real (timing/blocking/estado final observados via `pg_locks`/`pg_stat_activity`) se o ambiente sustentar duas sessões persistentes reais, ou marcação explícita "NOT EXECUTED / UNPROVEN" caso contrário — nunca inferir aprovação só da existência do `FOR UPDATE` no código.
5. **Seção 1.7 (grants EXECUTE) frágil** — dependia de "exatamente 4 linhas" em `information_schema.role_routine_grants`, que pode não expor todo principal com `EXECUTE`. Reescrita com `aclexplode(proacl)` para enumerar literalmente todo o ACL de cada uma das 4 RPCs.

Nenhuma mudança em `6123`/`6124`/`6125` (aprovados PASS por Fabrício) nem no modelo físico. Apenas `6830` foi editado.

## 6830-DIRECT-REVIEW-FIX-02 (2 correções residuais, `6123`/`6124`/`6125` intactos)

Segunda rodada de auditoria direta de Fabrício sobre `6830` v1.4, com `6123`/`6124`/`6125` novamente NÃO reabertos (permanecem `PASS`), encontrando 2 problemas residuais no roteiro de validação:

1. **Seção 1.7 (EXECUTE das 4 RPCs) com coluna inexistente** — a query reescrita em `6830-DIRECT-REVIEW-FIX-01` referenciava `acl.grantee_role`, que não existe no retorno de `aclexplode()` (que devolve `grantee` como OID, `0` = `PUBLIC`). Corrigida para resolver o OID via `LEFT JOIN pg_roles` + `CASE` explícito. Expectativa também corrigida: cada RPC deve ter exatamente dois `EXECUTE` legítimos — o **owner** da função e **authenticated** — nunca "só uma linha authenticated"; `PUBLIC`/`anon`/`service_role`/qualquer outro principal devem estar ausentes, e `proacl` `NULL` fazendo `PUBLIC` aparecer via `acldefault` é declarado explicitamente como **FALHA**.
2. **Sugestão indevida de `service_role` com `BYPASSRLS`** para DML direto estrutural (Caso 1b e a regra geral de contexto da Seção 3) — removida. `BYPASSRLS` não concede `INSERT`/`UPDATE`/`DELETE`; o modelo desta Fatia deixa `service_role` deliberadamente sem esses grants. Para DML direto estrutural, usar somente `postgres`/table owner, sempre em transação com `ROLLBACK`.

`6830` subiu para v1.5. Nenhuma mudança em `6123`/`6124`/`6125` nem no modelo físico.

## IMPLEMENTATION-RESUME-02 (aplicação real de `6123`-`6125` + Seção 3 completa)

Após dupla aprovação PASS de `6123`/`6124`/`6125` (ver seções acima), Fabrício autorizou a retomada. `6123`, `6124` e `6125` foram aplicados ao banco real via `apply_migration`, cada um seguido de validação estrutural imediata (A/B/C). A Seção 1 (SQL ESTÁTICO) e Seção 2 (fixtures estruturais) de `6830` foram executadas por completo, e a Seção 3 (24 casos de teste funcional) foi executada integralmente contra o banco real, usando o usuário de teste real existente e `set_config('request.jwt.claim.sub', ...)` para simular `authenticated` — nunca `INSERT` direto em `auth.users`. Caso 20b (concorrência) permaneceu `NOT EXECUTED / UNPROVEN`, conforme já aprovado (ambiente sem duas sessões persistentes simultâneas).

## 6126-STAGING-01 / 6126-IMPLEMENT-RESUME-01 (bug funcional real e correção)

Durante a execução real da Seção 3 (Caso 14), `set_pokedex_position_primary_representative()` falhou com `SQLSTATE 42702` ("column reference \"collection_id\" is ambiguous") — a cláusula `ON CONFLICT (collection_id, pokedex_position_id)` de `6125` usa nomes de coluna sem qualificação que colidem, sob `plpgsql.variable_conflict = 'error'`, com os OUT-parameters de mesmo nome do `RETURNS TABLE`. Execução interrompida ali (STOP, conforme CLAUDE.md — erro inesperado em objeto já aplicado). Correção proposta e staged em `6126` (`ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative`, única mudança funcional). Após auditoria direta de Fabrício confirmar `6126` PASS, foi aplicada ao banco real; postcheck via `pg_get_functiondef` confirmou zero divergência em assinatura/`RETURNS TABLE`/`SECURITY DEFINER`/`search_path`/ownership/ACL/lock order/`RETURNING`. Seção 3 retomada a partir do Caso 14 (INSERT puro) e Caso 15 (caminho `DO UPDATE` do `ON CONFLICT`), ambos PASS, confirmando as duas ramificações do fix.

## FINAL-VALIDATION-CLEANUP-01 (Caso 16 explícito + cleanup + zero-resíduo)

Postcheck independente encontrou uma lacuna de rastreabilidade: `_fatia_d_results` não tinha registro explícito do Caso 16 (`clear_pokedex_position_primary_representative`, caminho "sem Primary preexistente" — só exercitado implicitamente via Caso 21 parte 4). Caso 16 foi executado explicitamente com um Primary Representative preparado para o caso, registrado PASS com evidência objetiva (RETURNING exato, 0 linhas remanescentes, Assignment/Allocation sobreviventes), sem reaproveitar o resultado do Caso 21. Matriz final consolidada: zero FAIL residual nos 24 casos (todo FAIL histórico foi SUPERSEDED por PASS posterior); Caso 20b permanece o único `NOT EXECUTED / UNPROVEN`. Cleanup final removeu exclusivamente fixtures desta bateria — incluindo 2 achadas por auditoria de identidade/timestamp e não rastreadas em `_fatia_d_run` (a Allocation do Caso 3b e a Collection+Allocation do Caso 1b "Fatia D Test OC Divergent") — nunca dados reais/preexistentes (Inventory, Expansion, Game, Rarity, Card Category, Card Variant Type, Language, Pokémon Species, Pokémon Generation, usuário real de teste). Zero-resíduo confirmado por identidade (IDs capturados de `_fatia_d_run` antes do `DROP TABLE`), não por nome/prefixo. Postcheck estrutural/segurança pós-cleanup confirmou `6117`-`6126` intactos.

## PROMOTION-CLOSEOUT-01 (promoção final)

`6117`-`6126` promovidos para `database/schema/` — corpo SQL byte-idêntico ao executado em cada arquivo, apenas cabeçalho `Status`/`Versão`/`Data` atualizado para `CONFIRMADO EXECUTADO E PROMOVIDO`. `6123` e `6126` permanecem correções incrementais explícitas (nunca foldadas em `6118`/`6119`/`6122` ou em `6125`, respectivamente) — a cronologia física real de aplicação é preservada nos próprios headers. `6830` permanece em `database/proposals/` como evidência de validação (não é DDL/DML de schema, não promovido); README atualizado para `CLOSED/PROMOTED` nesta versão.

## GO/NO-GO

**FECHADO — TECHNICAL CLOSEOUT PASS.** Todas as correções do GATE 4, `PAUSE-SQL-DIRECT-AUDIT-01`, `RENUMBER-FIX-STAGING-01` e `6830-DIRECT-REVIEW-FIX-01`/`-FIX-02` foram aplicadas e auditadas com sucesso. `6117`-`6126` estão `CONFIRMADO EXECUTADO` no banco real e promovidos para `database/schema/`. A Seção 3 de `6830` está concluída com zero FAIL residual, Caso 20b aprovado como `NOT EXECUTED / UNPROVEN`, e o cleanup de fixtures foi executado com zero-resíduo confirmado por identidade. Fatia D está tecnicamente fechada — próxima frente é Fatia E (REFERENCE_POSITION COMPLETION), não iniciada nesta rodada.

## Fora de escopo desta rodada

Fatia E (completion) — não iniciada; frontend; RPC orquestradora `fill_pokedex_position_slot`; alteração de `allocate_physical_cards_to_collection()`/`deallocate_physical_cards_from_collection()`; `git add`/`commit`/`push`.
