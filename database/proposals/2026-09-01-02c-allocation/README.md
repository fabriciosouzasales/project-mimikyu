# COLLECTIONS-PHYSICAL-INCREMENT-02C — Collection Allocation

Data: 2026-09-01 (`COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-01` → `-REVISION-01` → `-FINAL-01` → `-STAGING-REVISION-01` → `-STAGING-FINAL-01` → `-STAGING-FINAL-FIX-01`)

**Esta pasta é staging — nada aqui é lido como estado físico real.** Nenhum destes artefatos foi executado no Supabase. `database/schema/` e `database/migrations/` só recebem SQL depois de execução confirmada (ver `database/README.md`) — nunca antes. Mesma governança já usada em `database/proposals/2026-08-31-collections-physical-increment-01a/` (Inventory + Physical Card), `database/proposals/2026-08-31-02a-storage/` (Storage Foundation) e `database/proposals/2026-08-31-02b-collection/` (Collection + Default Storage).

## Por que este incremento existe, e por que vem depois de 2B

`collection_allocation` é a entidade que finalmente liga Physical Card a Collection — decisão já anunciada desde 2B (`5039_create_delete_collection_function.sql`: "Collection Allocation (Incremento 2C, ainda não modelado fisicamente)... a associação Collection<->Physical Card... será representada por uma entidade própria (`collection_allocation`), não por uma coluna em `physical_card`"). Sem Collection (2B) já existindo fisicamente, não há o que alocar. Sem Collection Allocation, `collection.started_at` (LDM-11) permanece um fato sem nenhuma fonte real — por isso a coluna só é adicionada nesta rodada, não em 2B.

```
Incremento 2A — Storage Foundation             (CONFIRMADO EXECUTADO, 2026-09-01)
Incremento 2B — Collection + Default Storage   (CONFIRMADO EXECUTADO, 2026-09-01)
Incremento 2C — Collection Allocation          (esta pasta)
Incremento futuro — Collection Reference → habilita REFERENCE_BASED e Public Access
```

## Autoridade

- `docs/domain-modeling/collections/concept-decisions.md` — C-04 (exclusividade colecionável 0..1), C-05 (vínculo obrigatório com Game), C-13 (exclusão condicionada a zero Physical Cards), C-36 (Default Storage Container), C-37 (comportamento ARCHIVED), C-141/C-146/C-147/C-150 (Collaboration/Permissions — Collection Allocation Owner-only no V1)
- `docs/domain-modeling/collections/logical-model.md` — LDM-02 (Collection Allocation como entidade própria), LDM-04 (regras de `mode`, `OPEN_CURATION` sem Collection Reference), LDM-07 (consolidação de referência), LDM-11 (semântica de `created_at`/`started_at`), LDM-12 (skeleton físico do núcleo)
- `docs/05d-colecoes-e-usuarios.md` — seções "Physical Card (Exemplar Físico) / Inventory" e "Collection", já `CONFIRMADO EXECUTADO`
- Padrões físicos já `CONFIRMADO EXECUTADO` em `database/schema/5000`-`5039` (Inventory, Physical Card, Storage Container, Collection)
- Rodadas de modelagem: `COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-01`, `-REVISION-01`, `-FINAL-01`

Nenhuma decisão conceitual (C-*/LDM-*) foi reaberta ou alterada na produção destes artefatos.

## Decisões de desenho fechadas nesta rodada

**Owner × Inventory × Game — três camadas de integridade, não uma.** Toda Physical Card alocada precisa: (a) ter um `physical_card.inventory_id` não nulo (uma Physical Card sem Inventory corrente, após Ownership Exit — C-72 — não pode ser alocada); (b) pertencer, via esse Inventory, ao mesmo `owner_user_id` da Collection; (c) pertencer, via a cadeia `card_variant → card → card_set → expansion`, ao mesmo `game_id` da Collection (C-05, aprovado e obrigatório nesta rodada mesmo não tendo sido pedido explicitamente no escopo original — divergência sinalizada e depois confirmada). As três são garantidas estruturalmente por `trg_collection_allocation_validate_insert`/`_update` (`5042`), não só pela RPC.

**Trigger de integridade é `AFTER ... FOR EACH STATEMENT` com transition table, não `FOR EACH ROW`.** Primeira implementação real desse padrão no projeto — `5033` (02B) já mencionava a técnica hipoteticamente, nunca chegou a usá-la. Validação em lote (até 500 linhas por chamada) sem custo por linha. A checagem de Inventory-nulo é deliberadamente livre de `JOIN` (evita o bug corrigido nesta rodada — ver próximo item); as checagens de Owner e Game, que vêm depois, podem então usar `JOIN` normal com segurança.

**Correção de um bug real: `INNER JOIN` deixava Physical Card sem Inventory escapar da validação.** A primeira proposta (`-MODELING-01`) validava Owner/Game com um único `JOIN` até `inventory` — como `physical_card.inventory_id` é nulável, uma linha com `inventory_id IS NULL` simplesmente não casava o `JOIN` e desaparecia do resultado, em vez de falhar. Corrigido com três checagens sequenciais, a primeira das quais (`inventory_id IS NULL`) não usa `JOIN` nenhum.

**`started_at` nunca escrito por `NOW()` em RPC — materializado por trigger a partir do fato real.** Correção final desta rodada (`-FINAL-01`, item 1): a proposta anterior tinha `allocate_physical_cards_to_collection()` escrevendo `SET started_at = NOW()`. Removida por completo. `started_at` agora é escrito só por `materialize_collection_started_at()` (`5045`), uma trigger `AFTER INSERT ... FOR EACH STATEMENT` sobre `collection_allocation` que calcula `MIN(new_table.created_at)` por Collection e grava só onde `started_at IS NULL`. Defesa em profundidade: `validate_collection_structural_identity()` (`5044`, extensão de `5032`) reconfirma de forma independente, a cada `UPDATE` de `collection`, que (a) `started_at` já definido é imutável (inclusive contra reset para `NULL`), e (b) a primeira definição só é aceita se corresponder exatamente ao `MIN(collection_allocation.created_at)` real da Collection — impede preencher `started_at` numa Collection sem nenhuma Allocation, mesmo por bug futuro no materializador.

**`started_at` nunca é resetado por deallocate, nem total.** Representa um fato histórico ("esta Collection já teve sua primeira alocação") — deallocate total esvazia a composição, não apaga o fato de que ela já começou.

**`reference_locked_at` — confirmado intocado nesta rodada.** A nota especulativa deixada em `5030` ("Collection Allocation (2C) é quem vai legitimamente controlá-lo") foi diagnosticada como imprecisa: `collection.mode` é fisicamente restrito a só `'OPEN_CURATION'` desde `chk_collection_mode` (2B), e LDM-04 estabelece que `OPEN_CURATION` não tem Collection Reference — logo não há, hoje, nenhum Reference para `reference_locked_at` consolidar. `chk_collection_reference_locked_at_null` permanece exatamente como está; a coluna será legitimamente controlada por uma Collection Reference futura, não por esta rodada.

**`delete_collection()` revisado — pré-check amigável, guarda real permanece a FK.** A garantia estrutural de C-13 já existe de forma declarativa desde `5040` (`collection_allocation.collection_id REFERENCES collection(id) ON DELETE RESTRICT`) — um `DELETE` em `collection` com Allocations existentes falharia de qualquer forma. `5048` adiciona só um pré-check de UX antes do `DELETE`, com mensagem que **não sugere `archive_collection()`** como alternativa (Collections `ARCHIVED` preservam todas as suas Allocations por C-37 — arquivar não desbloqueia a exclusão).

**Bulk fail-closed preservado em ambas as direções.** `allocate`: qualquer `physical_card_id` já alocado (nesta Collection ou em outra) aborta a chamada inteira, zero inserções. `deallocate`: qualquer `physical_card_id` não alocado a *esta* Collection aborta a chamada inteira, zero remoções. Nenhuma das duas RPCs faz "melhor esforço"/pula silenciosamente itens inválidos — mesmo padrão já usado em `add_physical_cards()`/`set_physical_cards_storage()`.

**Lock de concorrência preservado.** `SELECT ... FOR UPDATE` na linha de `collection`, no início de ambas as RPCs — mesmo padrão de `5035`-`5038` (02B) — fecha a race contra `archive_collection()`/`reactivate_collection()` e serializa `allocate`/`deallocate` concorrentes na mesma Collection, o que também torna segura a leitura implícita de `started_at` feita pela trigger de `5045`.

## Hardenings de `-STAGING-REVISION-01`

**Não vazar existência/ownership de Collection.** `5046`/`5047` faziam `SELECT ... FOR UPDATE` só por `id` e comparavam `owner_user_id` DEPOIS, com duas mensagens de erro distintas — um caller autenticado conseguia distinguir "Collection não existe" de "Collection existe mas é de outro Owner". Corrigido incorporando `owner_user_id = auth.uid()` diretamente no `WHERE` da própria `SELECT ... FOR UPDATE`: uma Collection alheia simplesmente não casa a query, produzindo o mesmo `NOT FOUND` e a mesma mensagem genérica (`'collection not found or not owned by caller'`) de uma Collection inexistente.

**`delete_collection()` — pre-check owner-scoped.** `5048` (v1.2) consultava `collection_allocation` antes de comprovar ownership — um caller podia inferir, pela mensagem recebida, se uma Collection alheia tinha ou não Physical Cards alocadas. Corrigido (v1.3): ownership é confirmada primeiro via `PERFORM ... FOR UPDATE` com o mesmo filtro composto; o pré-check de C-13 só roda depois, já garantidamente sobre uma Collection do próprio caller.

**Privilege validation explícita em `5806`.** A v1.0 provava ausência de `EXECUTE` só via `information_schema.role_routine_grants`, filtrado por role — não provava de forma explícita que `PUBLIC` estava revogado, nem listava o que de fato sobrava no ACL. Reescrito com `has_function_privilege()` por role e `aclexplode(proacl)` para inspeção direta do ACL completo (incluindo o grantee interno `0`, que representa `PUBLIC`). Adicionados os Casos X/Y/Z — prova funcional de que `allocate`/`deallocate`/`delete_collection()` sobre uma Collection alheia produzem a mesma classe de erro, com ou sem Allocations.

**Fixtures autocontidas em `5807`.** A v1.0 partia da premissa de reaproveitar fixtures de `01B`/`02A`/`02B` — premissa falsa, essas rodadas terminaram com zero resíduo sintético comprovado. Reescrito para sintetizar, dentro da própria transação revertida, tudo que o plano de performance precisa (Storage Containers, Collections de teste, Physical Cards, ≥ 20.000 Collection Allocations), reaproveitando só catálogo permanente seguro (Game/Card/Card Variant) e abortando com diagnóstico explícito se não houver ≥ 1 Owner com Inventory real disponível no momento da execução. Ordem da `TEMP TABLE` de resultados também corrigida — criada e com `GRANT` concedido antes da troca de role, sem a contradição textual da v1.0.

## `5807` v1.2 — script efetivamente executável (`-STAGING-FINAL-01`)

As v1.0/v1.1 de `5807` eram majoritariamente esboço comentado — blocos `--` descrevendo a intenção, com placeholders tipo `:'owner_a_id'` que não são sintaxe SQL válida. A v1.2 é SQL real, para colar e executar em uma única chamada, sem editar nenhum UUID manualmente: toda resolução de identificadores é dinâmica, via `TEMP TABLE`s e subqueries.

Correção de quantidade: `UNIQUE(collection_allocation.physical_card_id)` significa que ≥ 20.000 Allocations exigem ≥ 20.000 Physical Cards distintas — não é possível reusar a mesma Physical Card em duas Allocations. `5807` v1.2 sintetiza **21.601** Physical Cards distintas (5.000 para o workload A + 15.000 de baseline distribuído entre 20 Collections filler + 500 para workload E pré-alocadas + 500 livres para workload C + 1 de priming + 500 livres para workload D + 100 de margem técnica).

Pré-condição reduzida de ≥ 2 Owners para ≥ 1 Owner com Inventory existente — os workloads A-E usam só Owner A; cross-user (RLS entre Owners) é responsabilidade de `5806`, fora do escopo de performance.

Setup (Storage Container, 21.601 Physical Cards, 24 Collections — 1 workload_a + 20 filler + 1 workload_c + 1 workload_d + 1 workload_e —, 20.500 Allocations de baseline+E) via `INSERT` direto, role privilegiada, **sem bypass de trigger** — `5042`/`5045` disparam normalmente. Os workloads C/D/E chamam as RPCs reais (`allocate_physical_cards_to_collection()`/`deallocate_physical_cards_from_collection()`), nunca `INSERT`/`DELETE` direto.

Zero resíduo: prova primária é o próprio `ROLLBACK` (garantia ACID, incondicional). Prova adicional pós-`ROLLBACK`, na mesma sessão/chamada (o `ROLLBACK` encerra a transação, não a conexão): recontagem de Physical Cards do Owner A resolvido, comparada contra a contagem feita antes do `BEGIN`, mais contagem de Collections/Storage Container com o prefixo `PERF-TEST-02C-%` (esperado 0 em ambos os casos).

## Hardenings de `-STAGING-FINAL-FIX-01`

**TEMP TABLE privileges — BLOCKER.** `set_config('role', 'authenticated', true)` muda a identidade de verificação de privilégio a partir daquele ponto — TEMP TABLEs criadas pela role privilegiada original não ficam automaticamente legíveis pela nova role, mesmo na mesma sessão (privilégio é por role, não por sessão). Sem `GRANT` explícito, todo `SELECT` contra `perf_ctx`/`perf_collections`/`perf_physical_cards` dentro dos blocos executados como `authenticated` falharia com "permission denied for table". Corrigido: os `GRANT SELECT` das três tabelas (mais `GRANT INSERT, SELECT` em `perf_results`) agora acontecem no Passo 3, antes de qualquer troca de role, seguidos de uma prova estática via `has_table_privilege()` confirmando as 4 concessões antes de prosseguir. `perf_storage` não recebe `GRANT` — nenhum bloco a consulta depois da troca de role.

**Contagem de Collections corrigida: 24, não 23.** 1 workload_a + 20 filler + 1 workload_c + 1 workload_d + 1 workload_e = 24 — corrigido em todas as ocorrências de `5807` e neste README.

**Interpretação do planner neutralizada.** O workload A lê ~24% do total de `collection_allocation` (5.000 de ~21.000) — nessa faixa de seletividade, Seq Scan é uma escolha legítima do planner, não uma falha por si só. A versão anterior da nota final de `5807` assumia Index Scan como "esperado" e Seq Scan como desvio. Corrigido para documentar (registrar tipo de nó, tempo, buffers, índice disponível) sem prescrever qual plano é o correto. Adicionado também o workload A2 (opcional) — mesma consulta contra uma Collection filler de 750 linhas (~3,6% do total), como ponto de contraste de seletividade mais alta, sem introduzir lógica nova ao benchmark.

## Conteúdo

| Arquivo | Conteúdo | Numeração |
|---|---|---|
| `5040_create_collection_allocation_table.sql` | tabela `collection_allocation` (FKs `RESTRICT`, `UNIQUE` em `physical_card_id`, índice de listagem) + RLS + grants | provisória |
| `5041_create_collection_allocation_updated_at_trigger.sql` | trigger `updated_at` (reaproveita `set_updated_at()`) | provisória |
| `5042_create_collection_allocation_integrity_trigger.sql` | trigger de integridade Owner × Inventory × Game (`AFTER ... FOR EACH STATEMENT`, transition table) | provisória |
| `5043_alter_collection_add_started_at.sql` | `ALTER TABLE collection ADD COLUMN started_at` + CHECK temporal | provisória |
| `5044_update_collection_structural_identity_trigger.sql` | extensão de `5032` — imutabilidade + validação de origem de `started_at` | provisória |
| `5045_create_collection_started_at_from_allocation_trigger.sql` | trigger de materialização de `started_at` a partir da primeira Collection Allocation real | provisória |
| `5046_create_allocate_physical_cards_to_collection_function.sql` (v1.1) | RPC de alocação em lote (1-500), não vaza existência de Collection alheia | provisória |
| `5047_create_deallocate_physical_cards_from_collection_function.sql` (v1.1) | RPC de desalocação em lote (1-500), mesmo hardening de não-enumeração | provisória |
| `5048_update_delete_collection_function.sql` (v1.3) | extensão de `5039` — pré-check amigável de C-13, owner-scoped | provisória |
| `5806_validate_collections_physical_increment_02c.sql` (v1.1) | bateria de validação pós-migration (26 casos + 11 itens SQL/ACL, incluindo os 8 casos A-H de `started_at` e os Casos X/Y/Z de não-enumeração) | — |
| `5807_performance_checks_collections_physical_increment_02c.sql` (v1.3) | script SQL efetivamente executável, 21.601 Physical Cards sintéticas, 24 Collections de teste, GRANT de TEMP TABLE antes da troca de role, workloads C/D/E via RPC real, prova de zero resíduo pré/pós-ROLLBACK | — |

Numeração `5000-5999` continua sendo a milhar sugerida para Collections, **nunca formalmente reservada** (STD-001 Seção 10). `5806`/`5807` (em vez de `5804`/`5805`, já ocupados por 02B) evita colisão dentro da faixa de validações (`X800`-`X899`).

Fora do escopo desta pasta, deliberadamente: Collection Reference, Collection Membership, Collection Layout, `completion_policy`, `set_collection_visibility()`, `created_by_user_id`/`updated_by_user_id`.

## Próximos passos (fora desta rodada)

1. Auditoria e aprovação explícita de Fabrício sobre este conteúdo.
2. Numeração definitiva confirmada (milhar Collections).
3. Aplicação real no Supabase (`apply_migration`), uma Query por vez, com validação após cada uma (padrão STD-001 Seção 10).
4. Execução da bateria de validação (`5806`) e do plano de performance com volume (`5807`) com dado real.
5. Só então: cópia para `database/schema/`/`database/migrations/` com cabeçalho `CANÔNICA`, e atualização de `docs/05d-colecoes-e-usuarios.md`/`docs/domain-modeling/collections/` conforme o padrão já usado em `COLLECTIONS-PHYSICAL-INCREMENT-01B`/`-02A`/`-02B`.
6. Só depois disso: avaliar o próximo incremento físico de Collections (Collection Reference), fora do escopo anunciado desta pasta.
