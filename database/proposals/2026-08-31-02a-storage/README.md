# COLLECTIONS-PHYSICAL-INCREMENT-02A — Storage Foundation — HISTÓRICO (PROMOVIDO A CANÔNICA EM 2026-09-01)

Data: 2026-08-31 (`COLLECTIONS-PHYSICAL-MODELING-03` → `-REVISION-01` → `-REVISION-02` → `-FINAL-01` → `COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01`), aplicado em 2026-09-01 (`COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`)

**Esta pasta é histórico — preservada apenas como registro do processo de staging/auditoria, não é mais a fonte de verdade.** Os cinco artefatos de estrutura (`5020`-`5024`) foram auditados, aprovados por Fabrício e efetivamente aplicados no Supabase em 2026-09-01 (`COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`), sem nenhuma alteração de conteúdo em relação ao que está descrito aqui (exceto a renomeação de `assign_physical_cards_to_storage()` para `set_physical_cards_storage()`, já registrada e aplicada nesta própria pasta na `STAGING-REVISION-01`). As versões `CANÔNICA`/`CONFIRMADO EXECUTADO` correspondentes vivem agora em `database/schema/` e as validações reais (com resultados observados, não roteiro) em `database/validations/5802_.../5803_...`. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Storage / Storage Container", para a documentação narrativa completa.

**Esta pasta é staging — nada aqui é lido como estado físico real.** Nenhum destes artefatos foi executado no Supabase. `database/schema/` e `database/migrations/` só recebem SQL depois de execução confirmada (ver `database/README.md`) — nunca antes. Mesma governança já usada em `database/proposals/2026-08-31-collections-physical-increment-01a/` (Inventory + Physical Card).

## Por que este increment existe, e por que vem antes de Collection

`collection.default_storage_container_id` é `NOT NULL` desde a criação da Collection (C-36) — obrigatoriedade real, não sugestão de UX. Criar a tabela `collection` antes de `storage_container` existir geraria um estado fisicamente incompatível com C-36 assim que Storage passasse a existir (ALTER `NOT NULL` sem default numa tabela já povoada exige backfill). Por isso Storage Foundation precede Collection e Collection Allocation na sequência física:

```
Incremento 2A — Storage Foundation        (esta pasta)
Incremento 2B — Collection + Default Storage   (não preparado ainda)
Incremento 2C — Collection Allocation          (não preparado ainda)
Incremento futuro — Collection Reference → habilita REFERENCE_BASED
```

## Autoridade

- `docs/domain-modeling/collections/concept-decisions.md` — C-55 a C-59, C-61 (bloco Storage completo, lido integralmente nesta rodada)
- `docs/domain-modeling/collections/logical-model.md` — LDM-44 a LDM-54 (confirmado: nenhum skeleton físico de Storage Container havia sido fixado antes desta rodada)
- `docs/architecture/ubiquitous-language.md`
- `docs/standards/STD-001-database-standards.md`
- Padrões físicos já `CONFIRMADO EXECUTADO` em `database/schema/5000`-`5012` (Inventory + Physical Card)
- Rodadas de modelagem: `COLLECTIONS-PHYSICAL-MODELING-03`, `-REVISION-01`, `-REVISION-02`, `-FINAL-01`

Nenhuma decisão conceitual (C-*/LDM-*) foi reaberta ou alterada na produção destes artefatos.

## Decisão de desenho: FK composta em vez de trigger

`COLLECTIONS-PHYSICAL-MODELING-03-REVISION-02` havia proposto um par de triggers `AFTER INSERT`/`AFTER UPDATE` com transition table para validar que `physical_card.storage_container_id` e `physical_card.inventory_id` sempre apontam para o mesmo Inventory. `COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01` substituiu essa proposta por integridade **declarativa**: `storage_container` ganha `UNIQUE(id, inventory_id)` (Query 5020) e `physical_card` referencia essas duas colunas via FK composta (Query 5023) — o Postgres garante o invariante nativamente, sem função PL/pgSQL para manter. A validação técnica confirmou a FK composta válida e, adicionalmente, identificou um caso não coberto por `MATCH SIMPLE` (storage preenchido com `inventory_id` NULL) — fechado com um `CHECK` local (`chk_physical_card_storage_requires_inventory`, Query 5023). Ver cabeçalho de `5023_alter_physical_card_add_storage_container.sql` para o detalhamento completo dos casos A-E.

## Revisão: RPC de Current Storage cobre todo o ciclo de vida (0..1)

`COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01` substituiu `assign_physical_cards_to_storage()` por `set_physical_cards_storage(p_storage_container_id UUID, p_physical_card_ids UUID[])` (Query 5024, v2.0): `p_storage_container_id` não-nulo atribui/move; `NULL` limpa a localização corrente (Storage A → nenhum), caminho que faltava para cobrir C-58 integralmente (0..1 Storage Container corrente, podendo não ter nenhum). IDs duplicados no payload são normalizados para `DISTINCT` antes de qualquer validação/escrita; o teto de 500 é avaliado sobre o array recebido, antes da deduplicação. Contrato de retorno inalterado na forma (`id`, `storage_container_id`, `updated_at`), agora explicitamente justificado no cabeçalho da Query como o conjunto mínimo estável para esta operação — nunca `RETURNS SETOF physical_card`.

## Conteúdo

| Arquivo | Conteúdo | Numeração |
|---|---|---|
| `5020_create_storage_container_table.sql` | tabela `storage_container` (incl. `UNIQUE(id, inventory_id)`) + RLS + grants | provisória |
| `5021_create_storage_container_trigger.sql` | trigger `updated_at` | provisória |
| `5022_create_create_storage_container_function.sql` | RPC de criação, single-row | provisória |
| `5023_alter_physical_card_add_storage_container.sql` | `physical_card.storage_container_id` + FK composta + CHECK + índice | provisória |
| `5024_create_set_physical_cards_storage_function.sql` | RPC bulk-first de Current Storage (atribuir/mover/limpar via NULL, até 500 itens, dedup + atômica) | provisória |
| `5802_validate_collections_physical_increment_02a.sql` | bateria de validação pós-migration (19 itens, incl. casos A-H) | — |
| `5803_performance_checks_collections_physical_increment_02a.sql` | plano de teste de performance com volume ≥ 20.000 | — |

Numeração `5000-5999` continua sendo a milhar sugerida para Collections, **nunca formalmente reservada** (STD-001 Seção 10). A numeração definitiva será confirmada no momento da reconciliação real para `database/schema/`/`database/migrations/`. `5802`/`5803` (em vez de `5800`/`5801`, já ocupados por Increment 01A) evita colisão dentro da faixa de validações (`X800`-`X899`) mesmo em staging.

Fora do escopo desta pasta, deliberadamente: hierarquia de Storage Container (C-60), capacidade (C-62), Bulk Card Transfer (C-64), Reparent (C-65), Protection/Encapsulation (C-56), Collection, Collection Reference e Collection Allocation.

## Próximos passos (fora desta rodada)

1. Auditoria e aprovação explícita de Fabrício sobre este conteúdo.
2. Numeração definitiva confirmada (milhar Collections).
3. Aplicação real no Supabase (`apply_migration`/`execute_sql`), uma Query por vez, com validação após cada uma (padrão STD-001 Seção 10).
4. Execução da bateria de validação (`5802`) e do plano de performance com volume (`5803`) com dado real.
5. Só então: cópia para `database/schema/`/`database/migrations/` com cabeçalho `CANÔNICA`, e atualização de `docs/domain-modeling/collections/` conforme o padrão já usado em `COLLECTIONS-PHYSICAL-INCREMENT-01B`.
6. Só depois disso: preparar staging do Incremento 2B (Collection + Default Storage).
