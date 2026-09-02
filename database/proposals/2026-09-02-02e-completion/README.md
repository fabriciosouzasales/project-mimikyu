# Staging — COLLECTIONS-PHYSICAL-INCREMENT-02E — Standard_Set Completion & Progress

| Campo | Valor |
|---|---|
| Rodada | `COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-01` |
| Status | PROPOSTA — NÃO EXECUTADA. Nenhuma Query desta pasta foi aplicada ao banco físico. |
| Autoridade | `COLLECTIONS-PHYSICAL-INCREMENT-02E-MODELING-01` → `-MODELING-REVISION-01` (fechada e aprovada por Fabrício antes desta rodada) |
| Precedido por | `2026-09-02-02d-reference/` (Collection Reference / Card Set Reference, `CONFIRMADO EXECUTADO`) |

## Estado final (STAGING-EXECUTION-SAFETY-FIX-01)

02E entrega exclusivamente **STANDARD_SET Completion/Progress**. MASTER_SET permanece **CONCEPTUALLY READY. PHYSICALLY DEFERRED FOR SCOPE CONTROL** — decisão de escopo do incremento, nunca atribuída à cobertura atual de `card_variant` no catálogo (ver seção própria abaixo). `SECURITY INVOKER` foi a postura original de `5070`/`5071`, **SUPERSEDED no staging** depois de prova real de que a RLS do Catálogo Editorial é admin-only (`ADR-030`); a postura final é `SECURITY DEFINER`, projeção estreita, owner-scoped, sob o precedente já aprovado do projeto em `ADR-030`.

Os 8 arquivos (`5067`-`5071`, `5810`, `5811`, este README) são o **staging final** desta rodada — não requerem mais nenhuma rodada de correção conhecida antes de uma futura `-IMPLEMENTATION-01`. `5810` (v4.0) **não usa mais `RAISE EXCEPTION` como gate final**: o comportamento do cliente/ferramenta de execução diante de um erro levantado no meio do batch (se ele continua enviando os statements restantes, entre eles o `ROLLBACK`) nunca foi comprovado — por isso o script foi corrigido para sempre alcançar `ROLLBACK` em execução normal, e a decisão de prosseguir com a implementação (`falharam = 0` → prosseguir; `falharam > 0` → **IMPLEMENTATION STOP**) passou a ser um gate de **processo**, fiscalizado por quem executa a rodada a partir do `SELECT` consolidado de `test_results`, nunca por uma exceção dentro da transação.

## Escopo físico desta rodada

Materializa exclusivamente:
- `collection.completion_policy` (`NONE`/`STANDARD_SET`);
- extensão de `create_collection()`/`create_reference_based_card_set_collection()` para gravar a policy automaticamente;
- os dois read models de progresso: `collection_completion_summary()` e `collection_completion_positions()`;
- plano de validação funcional e plano de performance.

**Não implementa nesta rodada** (por controle de escopo, não por limitação técnica ou de catálogo): `MASTER_SET`, `Collection Master Set Scope`, `REFERENCE_POSITION`, Pokédex Reference, RPC de troca de Completion Policy, cache/materialized view, frontend.

## Correção de segurança — SECURITY INVOKER rejeitado após prova real (STAGING-REVISION-02)

`5070`/`5071` foram desenhadas e reafirmadas em duas rodadas de modelagem como `SECURITY INVOKER`, sob a premissa de que a RLS existente de `collection`/.../`card`/`card_variant` seria suficiente para um Owner comum ler o próprio progresso. Essa premissa foi **testada e refutada** nesta rodada: `ADR-030-card-search-projection.md` (linhas 17/139) já documenta, com teste real, que o Catálogo Editorial (`ADR-022`) fecha `public.card`/`public.card_variant` a SELECT direto de `authenticated` — `card` tem RLS habilitado **sem nenhuma policy** (nem `catalog_admin_select`); `card_variant` tem só `catalog_admin_select` (`is_admin()`-gated). `SELECT count(*) FROM card` como `authenticated` retorna sempre 0. Logo, `SECURITY INVOKER` fazia `total_positions`/`satisfied_positions` serem sempre 0 para qualquer Owner real não-admin — quebrado para o único usuário que a função existe para servir.

**Decisão**: `5070`/`5071` convertidas para `SECURITY DEFINER`, projeção estreita — mesmo precedente já aprovado pelo projeto em `ADR-030` (`search_cards()`/`search_card_filter_options()`): `STABLE`, `SET search_path = ''`, verificação explícita de `(select auth.uid()) IS NOT NULL` (nunca `is_admin()` — Completion não é operação administrativa), `REVOKE ALL FROM PUBLIC`/`anon` + `GRANT EXECUTE TO authenticated`.

**O catálogo permanece fechado**: esta correção não abre nenhuma policy nova em `card`/`card_variant`/`card_set`, não concede nenhum `SELECT` editorial novo a `authenticated`, e não usa `service_role` no contrato funcional. Um `authenticated` comum continua vendo 0 linhas ao consultar `card`/`card_variant` diretamente — só as duas funções, com contrato de retorno mínimo e auditável, enxergam o catálogo, e só dentro de uma Collection já autorizada.

**Ownership é manual, não mais herdado da RLS**: como `SECURITY DEFINER` bypassa a RLS de `collection`/`collection_reference`/`collection_card_set_reference`/`collection_allocation`/`physical_card` também (não só a de `card`/`card_variant`), a fronteira de autorização foi reconstituída explicitamente dentro de cada função — a CTE `target` só resolve quando `collection.id = p_collection_id AND collection.owner_user_id = (select auth.uid())`, sempre o primeiro passo da query, nunca uma checagem posterior. Foreign owner e Collection inexistente continuam retornando exatamente a mesma forma (0 rows, sem mensagem distintiva) — não-enumeração preservada mesmo com RLS bypassada.

## MASTER_SET — status registrado (não implementado)

**CONCEPTUALLY READY. PHYSICALLY DEFERRED FROM 02E FOR SCOPE CONTROL.**

A semântica de domínio está fechada: o denominador de MASTER_SET é o `Collection Master Set Scope` — o conjunto de `card_variant_id` explicitamente adotado pelo usuário para aquela Collection (LDM-21), nunca uma regra automática de catálogo decidindo se Reverse/Stamp/Jumbo/Tournament/Promo "conta". Duas Collections do mesmo Card Set podem ter Adopted Scopes diferentes, ambos válidos.

O diferimento desta rodada é decisão de escopo do incremento (a entidade `Collection Master Set Scope`, suas operações de inclusão/exclusão de Variant e seu contrato de UX ampliariam significativamente o 02E) — **não** é causado pela cobertura parcial atual de `card_variant` no catálogo. Cobertura de catálogo é matéria de governança/readiness operacional, tratada em rodada própria, nunca como restrição de arquitetura ou produto.

## Arquivos desta pasta

| Arquivo | Conteúdo |
|---|---|
| `5067_alter_collection_add_completion_policy.sql` | `ALTER TABLE collection ADD COLUMN completion_policy` + backfill + validação + `SET NOT NULL` + `CHECK chk_collection_completion_policy` |
| `5068_update_create_collection_function.sql` | `CREATE OR REPLACE` — grava `completion_policy = 'NONE'` |
| `5069_update_create_reference_based_card_set_collection_function.sql` | `CREATE OR REPLACE` — grava `completion_policy = 'STANDARD_SET'` |
| `5070_create_collection_completion_summary_function.sql` (v2.0) | Read model de resumo (`total_positions`/`satisfied_positions`/`missing_positions`/`progress_percentage`/`is_complete`) — `SECURITY DEFINER` com ownership manual (correção de segurança, ver seção acima) |
| `5071_create_collection_completion_positions_function.sql` (v2.0) | Read model de posições individuais (`card_id`/`collector_number`/`name`/`is_satisfied`, com `p_only_missing`) — `SECURITY DEFINER` com ownership manual (idem) |
| `5810_validate_collections_physical_increment_02e.sql` (v4.0) | Bateria de validação funcional (Casos A-Z + bloco SEC-A..SEC-M/SEC-BYPASS, todos com rótulo embutido, sem alias artificial) — SQL 100% executável: `BEGIN`/fixtures reais reversíveis/`pg_temp.log_result()`/impersonação `authenticated` (Owner A e Owner B, ambos com prova real `is_admin() = false`) e `anon`/prova real de bypass de ownership/prova de que o catálogo continua fechado a SELECT direto/todas as checagens estruturais e de segurança consolidadas em `test_results`/`SELECT` final consolidado/`ROLLBACK` **incondicional** (sem `RAISE EXCEPTION` — decisão de prosseguir é gate de processo, ver "Estado final" acima)/prova pós-`ROLLBACK` |
| `5811_performance_checks_collections_physical_increment_02e.sql` (v1.5) | Plano de performance (workloads A-I) sobre um Card Set real do catálogo (maior pool de Cards com Card Variant, escolha de fixture — cobertura de catálogo nunca é requisito de STANDARD_SET; workload C nunca alega "100%" incondicionalmente, comentário do bloco de sintetização alinhado ao rótulo dinâmico), contexto do benchmark exposto antes dos planos, tempo combinado do workload I extraído dos JSONs, sempre como `authenticated`/Owner A não-admin (prova real `is_admin() = false` no Passo 4), dentro de transação revertida |

Numeração `5067-5071` contínua após `5066` (último arquivo do incremento 02D). Numeração `5810`/`5811` — próximo par livre na faixa `58XX`, após `5808`/`5809` (02D).

## Sequência de aplicação (rodada futura de implementação)

Os 8 arquivos desta pasta são staging final — nenhum deles depende mais de uma rodada de correção adicional conhecida antes da implementação.

1. `5067` (coluna + backfill + `CHECK`);
2. `5068` (RPC `create_collection()` estendida);
3. `5069` (RPC `create_reference_based_card_set_collection()` estendida);
4. `5070` (read model `collection_completion_summary()`);
5. `5071` (read model `collection_completion_positions()`);
6. `5810` (validação funcional) → **prosseguir somente se `falharam = 0` no `SELECT` consolidado de `test_results` E zero resíduo confirmado no Passo 8 pós-`ROLLBACK`** — gate de processo fiscalizado pelo executor da rodada, não por exceção dentro da transação (`5810` v4.0 não usa mais `RAISE EXCEPTION` como gate final: o comportamento do cliente de execução diante de erro no meio do batch não está comprovado, então o script sempre alcança `ROLLBACK`, com ou sem FAIL registrado — ver "Estado final" acima). Se `falharam > 0`: **IMPLEMENTATION STOP** — não executar `5811`, não promover schema, reportar os rótulos falhos e corrigir antes de repetir este passo;
7. `5811` (performance sob volume sintético) → avaliar os planos capturados em `perf_results`, sem alegação de performance antes da execução real;
8. Promoção canônica para `database/schema/` + documentação (`05d-colecoes-e-usuarios.md`, `README.md`, `log.md`, `INDEX.md`, handoff) no mesmo ciclo.

## Banco físico

Nenhuma alteração aplicada. `mode`/`visibility`/`lifecycle_status`/`reference_locked_at`/`started_at` de `collection`, e toda a superfície de `collection_reference`/`collection_card_set_reference`/`collection_allocation`, permanecem exatamente como deixadas pelo incremento 02D (`CONFIRMADO EXECUTADO`).
