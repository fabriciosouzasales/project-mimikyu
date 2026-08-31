# COLLECTIONS-PHYSICAL-INCREMENT-01A — HISTÓRICO (PROMOVIDO A CANÔNICA EM 2026-08-31)

Data: 2026-08-31 (revisado em `COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01`, aplicado em `COLLECTIONS-PHYSICAL-INCREMENT-01B`)

**Esta pasta é histórico — preservada apenas como registro do processo de staging/auditoria, não é mais a fonte de verdade.** Os seis artefatos de estrutura (`5000`-`5012`) foram auditados, aprovados por Fabrício e efetivamente aplicados no Supabase em 2026-08-31 (`COLLECTIONS-PHYSICAL-INCREMENT-01B`), sem nenhuma alteração de conteúdo em relação ao que está descrito aqui. As versões `CANÔNICA`/`CONFIRMADO EXECUTADO` correspondentes vivem agora em `database/schema/` (mesmos seis arquivos, cabeçalho atualizado com a confirmação de execução) e as validações reais (com resultados observados, não roteiro) em `database/validations/5800_...`/`5801_...`. Ver `docs/05d-colecoes-e-usuarios.md`, seção "Physical Card / Inventory", para a documentação narrativa completa da fundação física.

## Ajustes da rodada de revisão (01A-REVISION-01)

1. **Provisionamento + backfill consolidados**: as antigas Queries `5002` (trigger) e `5003` (backfill) foram unificadas em uma única `5002_create_inventory_provisioning_and_backfill.sql`, com `BEGIN`/`COMMIT` explícitos — elimina a janela em que o trigger poderia existir sem que Users pré-existentes tivessem Inventory.
2. **Contrato da RPC explícito**: `add_physical_cards()` deixou de usar `RETURNS SETOF public.physical_card` e passou a `RETURNS TABLE(id, card_variant_id, language_id, created_at)` — evita que colunas futuras da tabela vazem automaticamente para o contrato público da função.
3. **Índice de idioma revisado**: `ix_physical_card_language_id` (global) substituído por `ix_physical_card_inventory_language (inventory_id, language_id)` — alinhado ao padrão de acesso real (sempre Inventory-scoped, inclusive via RLS). O índice `(inventory_id, card_variant_id)` não foi alterado.
4. **Validação (`5800`) ampliada**: testes de provisionamento automático (novo User → 1 Inventory) e idempotência do backfill; provas explícitas de INSERT/UPDATE/DELETE negados para `authenticated` em ambas as tabelas; isolamento RLS explícito de Inventory entre usuários.
5. **Plano de performance (`5801`) ampliado**: passo de geração de volume (≥ 20.000 Physical Cards, transacional/reversível) e consultas A (listar), B (contar por Variant), C (filtrar por Language, nova) e D (RPC bulk com 500 itens, nova).

## Por que esta pasta existe

`database/schema/` e `database/migrations/` só recebem SQL depois de execução confirmada (ver `database/README.md`) — nunca antes. Como Fabrício pediu explicitamente que os arquivos fossem criados nesta rodada sem aplicar nada no banco, esta pasta de staging evita violar essa regra: nada aqui é lido como estado físico real até ser auditado, aprovado, executado e só então reconciliado para as pastas oficiais.

## Autoridade

- `docs/domain-modeling/collections/concept-decisions.md` (C-47, C-48)
- `docs/domain-modeling/collections/logical-model.md` (LDM-23, LDM-24)
- `docs/architecture/ubiquitous-language.md`
- `docs/standards/STD-001-database-standards.md`
- Rodadas conceituais/preparatórias: `COLLECTIONS-PHYSICAL-MODELING-01`, `COLLECTIONS-PHYSICAL-MODELING-02`, `COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01` (READY FOR IMPLEMENTATION, 2026-08-31)

Nenhuma decisão conceitual (C-*/LDM-*) foi reaberta ou alterada na produção destes artefatos.

## Conteúdo

| Arquivo | Conteúdo | Numeração |
|---|---|---|
| `5000_create_inventory_table.sql` | tabela `inventory` + RLS + grants | provisória |
| `5001_create_inventory_trigger.sql` | trigger `updated_at` | provisória |
| `5002_create_inventory_provisioning_and_backfill.sql` | provisionamento automático + backfill, consolidados em 1 transação | provisória |
| `5010_create_physical_card_table.sql` | tabela `physical_card` + índices + RLS + grants | provisória |
| `5011_create_physical_card_trigger.sql` | trigger `updated_at` | provisória |
| `5012_create_add_physical_cards_function.sql` | RPC bulk-first de escrita, retorno explícito | provisória |
| `5800_validate_collections_physical_increment_01a.sql` | bateria de validação pós-migration (23 itens) | — |
| `5801_performance_checks_collections_physical_increment_01a.sql` | plano de teste de performance com volume ≥ 20.000 | — |

Numeração `5000-5999` é uma sugestão de milhar para Collections, **nunca formalmente reservada** (STD-001 Seção 10 proíbe pré-reserva de milhares — só é comprometida quando efetivamente aplicada). A numeração definitiva será confirmada no momento da reconciliação real para `database/schema/`/`database/migrations/`.

## Próximos passos (fora desta rodada)

1. Auditoria e aprovação explícita de Fabrício sobre este conteúdo.
2. Numeração definitiva confirmada (milhar Collections).
3. Aplicação real no Supabase (`apply_migration`/`execute_sql`), uma Query por vez, com validação após cada uma (padrão STD-001 Seção 10).
4. Backfill executado como parte da própria transação da Query `5002` (já consolidado — não é mais um passo separado).
5. Execução da bateria de validação (`5800`) e do plano de performance com volume (`5801`) com dado real.
6. Só então: cópia para `database/schema/`/`database/migrations/` com cabeçalho `CANÔNICA`, e atualização de `docs/domain-modeling/collections/` conforme o padrão de fundação física já usado em `COLLECTIONS-CARD-CONDITION-*` (não feita nesta rodada — nenhuma decisão C-*/LDM-* foi alterada).
