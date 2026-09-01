# COLLECTIONS-PHYSICAL-INCREMENT-02B — Collection + Default Storage

Data: 2026-08-31 (`COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01` → `-REVISION-01` → `-FINAL-01`)

**Esta pasta é staging — nada aqui é lido como estado físico real.** Nenhum destes artefatos foi executado no Supabase. `database/schema/` e `database/migrations/` só recebem SQL depois de execução confirmada (ver `database/README.md`) — nunca antes. Mesma governança já usada em `database/proposals/2026-08-31-collections-physical-increment-01a/` (Inventory + Physical Card) e `database/proposals/2026-08-31-02a-storage/` (Storage Foundation).

Pasta nomeada de forma curta (`2026-08-31-02b-collection`) desde a criação, para evitar o problema de comprimento de caminho já corrigido retroativamente na pasta do incremento anterior (`2026-08-31-02a-storage`, originalmente `2026-08-31-collections-physical-increment-02a-storage-foundation`).

## Por que este incremento existe, e por que vem depois de 2A

`collection.default_storage_container_id` é `NOT NULL` desde a criação da Collection (C-36) — obrigatoriedade real, não sugestão de UX. Por isso Storage Foundation (Incremento 2A, `storage_container` + `physical_card.storage_container_id`, CONFIRMADO EXECUTADO em 2026-09-01) precede Collection na sequência física:

```
Incremento 2A — Storage Foundation             (CONFIRMADO EXECUTADO, 2026-09-01)
Incremento 2B — Collection + Default Storage   (esta pasta)
Incremento 2C — Collection Allocation          (não preparado ainda)
Incremento futuro — Collection Reference → habilita REFERENCE_BASED e Public Access
```

## Autoridade

- `docs/domain-modeling/collections/concept-decisions.md` — C-01 a C-37 (núcleo Collection), C-141 (Collection Owner estrutural)
- `docs/domain-modeling/collections/logical-model.md` — LDM-01 a LDM-27 (checkpoint lógico), LDM-12 (skeleton físico do núcleo)
- `docs/05d-colecoes-e-usuarios.md` — seções "Physical Card (Exemplar Físico) / Inventory" e "Storage / Storage Container", já `CONFIRMADO EXECUTADO`
- Padrões físicos já `CONFIRMADO EXECUTADO` em `database/schema/5000`-`5024` (Inventory, Physical Card, Storage Container)
- Rodadas de modelagem: `COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01`, `-REVISION-01`, `-FINAL-01`

Nenhuma decisão conceitual (C-*/LDM-*) foi reaberta ou alterada na produção destes artefatos.

## Decisões de desenho fechadas nesta rodada

**Visibility restrita a `PRIVATE`.** Enquanto Public Access não tiver uma projeção/read model seguro implementado, nenhuma Collection pode declarar um estado `PUBLIC` sem efeito real. `chk_collection_visibility` permite fisicamente só `'PRIVATE'` nesta etapa; `set_collection_visibility()` **não é criada** neste incremento. Quando Public Access for implementado: a projeção segura é construída primeiro, a constraint é ampliada depois, a RPC é criada por último — nessa ordem, não invertida.

**Structural Identity.** `owner_user_id` e `game_id` são estruturalmente imutáveis após a criação — um trigger `BEFORE UPDATE` dedicado (`5032`) protege os dois campos, independente de qualquer RPC nunca aceitar esses campos como parâmetro de update.

**Default Storage Owner enforcement via trigger, não FK composta.** Diferente de `physical_card` × `storage_container` (FK composta, porque ambos compartilham `inventory_id` — `5023`), `collection.owner_user_id` e `storage_container.inventory_id` não têm coluna em comum. Adicionar um `inventory_id` redundante a `collection` só para viabilizar uma FK composta foi avaliado e descartado (`COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01`, item 3) — a garantia estrutural permanece um trigger (`5033`), com join até `inventory`.

**`reference_locked_at` presente, mas travado em `NULL`.** A coluna existe fisicamente (evita `ALTER TABLE` quando Collection Allocation chegar), mas `chk_collection_reference_locked_at_null` impede qualquer estado legítimo deste incremento de preenchê-la — Collection Allocation ainda não existe, e nenhum caminho privilegiado pode simular sua consequência (LDM-07). Constraint removida/revisada conscientemente no Incremento 2C.

**`completion_policy` deferido por completo.** Não incluído no skeleton físico — semanticamente vazio sem Collection Reference (LDM-08). Sem coluna, sem CHECK, sem menção em nenhuma RPC.

**Archive/Reactivate idempotentes.** Chamar `archive_collection()` numa Collection já `ARCHIVED` retorna o estado atual sem erro e sem sobrescrever `archived_at` — preserva o timestamp do primeiro arquivamento real. `reactivate_collection()` é o espelho exato.

**Delete sem guarda de C-13 nesta etapa — correção documental aplicada.** `physical_card` **não terá** `collection_id`. Quando Collection Allocation (2C) existir, a associação será representada por uma entidade própria (`collection_allocation`), e C-13 será protegida por `collection_allocation.collection_id` (FK `RESTRICT` e/ou checagem explícita). Neste incremento, sem `collection_allocation`, `delete_collection()` é incondicional para o próprio Owner — a pré-condição de C-13 está vacuamente satisfeita, não contornada.

**`game.is_active` removido — correção pré-Fase 2 (`COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`).** A v1.0 de `create_collection()` (Query 5034) dependia de `public.game.is_active` para diferenciar "game not found" de "game is not active" — checagem herdada por analogia indevida do padrão real de `card.is_active` (ADR-023), nunca de fato existente em `game`. Confirmado por leitura direta do schema físico que `public.game` tem só `id/code/name/created_at/updated_at`; nenhuma decisão conceitual deste incremento documenta um estado ativo/inativo para Game. Removida a checagem: `create_collection()` agora exige só que `p_game_id` corresponda a um Game existente. A garantia estrutural de fundo continua sendo a FK `collection.game_id -> game.id` (Query 5030). O Caso D de `5804` ("Game inativo → FAIL") foi removido pelo mesmo motivo. Eventual lifecycle/ativação de Game é decisão futura do domínio de Catálogo, fora do escopo de Collections — se implementada, poderá exigir revisão desta política.

**Concorrência das RPCs de lifecycle corrigida (`COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-REVISION-01`).** A versão 1.0 de `update_collection_metadata()`, `set_collection_default_storage()`, `archive_collection()` e `reactivate_collection()` fazia SELECT do estado atual seguido de UPDATE separado — uma janela real onde uma chamada concorrente podia mudar `lifecycle_status` entre a leitura e a escrita (ex. editar metadata depois que a Collection já havia sido arquivada por outra chamada). Corrigido para todas as quatro: o guard de estado (`lifecycle_status = 'ACTIVE'` ou `= 'ARCHIVED'`, conforme o caso) passou a ser parte do próprio `WHERE` da `UPDATE`, tornando checagem e escrita atômicas sob READ COMMITTED. Uma leitura diagnóstica *read-only*, executada só quando o UPDATE atômico afeta zero linhas, distingue "não existe/não é minha" de "já está no estado-alvo" (idempotência) — nunca reabre a janela de escrita, porque a decisão de escrita já foi finalizada atomicamente antes dela. Nenhum contrato externo (assinatura, `RETURNS TABLE`) mudou.

## Conteúdo

| Arquivo | Conteúdo | Numeração |
|---|---|---|
| `5030_create_collection_table.sql` | tabela `collection` (6 CHECKs, índice de listagem) + RLS + grants | provisória |
| `5031_create_collection_updated_at_trigger.sql` | trigger `updated_at` (reaproveita `set_updated_at()`) | provisória |
| `5032_create_collection_structural_identity_trigger.sql` | trigger de imutabilidade `owner_user_id`/`game_id` | provisória |
| `5033_create_collection_default_storage_owner_trigger.sql` | trigger de integridade Owner × Default Storage | provisória |
| `5034_create_create_collection_function.sql` | RPC de criação | provisória |
| `5035_create_update_collection_metadata_function.sql` | RPC de edição de metadata (name/description) | provisória |
| `5036_create_set_collection_default_storage_function.sql` | RPC de troca de Default Storage | provisória |
| `5037_create_archive_collection_function.sql` | RPC de arquivamento (idempotente) | provisória |
| `5038_create_reactivate_collection_function.sql` | RPC de reativação (idempotente) | provisória |
| `5039_create_delete_collection_function.sql` | RPC de exclusão (sem guarda de C-13 nesta etapa) | provisória |
| `5804_validate_collections_physical_increment_02b.sql` | bateria de validação pós-migration (21 casos + 6 itens SQL estáticos, incluindo auditoria de concorrência/idempotência do STAGING-REVISION-01) | — |
| `5805_performance_checks_collections_physical_increment_02b.sql` | plano de performance com volume ≥ 20.000, metodologia transacional corrigida (única chamada execute_sql) | — |

Numeração `5000-5999` continua sendo a milhar sugerida para Collections, **nunca formalmente reservada** (STD-001 Seção 10). `5804`/`5805` (em vez de `5802`/`5803`, já ocupados por 02A) evita colisão dentro da faixa de validações (`X800`-`X899`).

Fora do escopo desta pasta, deliberadamente: Collection Reference, Collection Allocation, Collection Membership, Collection Layout, `completion_policy`, `set_collection_visibility()`, `started_at`, `created_by_user_id`/`updated_by_user_id`.

## Próximos passos (fora desta rodada)

1. Auditoria e aprovação explícita de Fabrício sobre este conteúdo.
2. Numeração definitiva confirmada (milhar Collections).
3. Aplicação real no Supabase (`apply_migration`), uma Query por vez, com validação após cada uma (padrão STD-001 Seção 10).
4. Execução da bateria de validação (`5804`) e do plano de performance com volume (`5805`) com dado real.
5. Só então: cópia para `database/schema/`/`database/migrations/` com cabeçalho `CANÔNICA`, e atualização de `docs/05d-colecoes-e-usuarios.md`/`docs/domain-modeling/collections/` conforme o padrão já usado em `COLLECTIONS-PHYSICAL-INCREMENT-01B`/`-02A`.
6. Só depois disso: preparar staging do Incremento 2C (Collection Allocation), que precisará revisar `delete_collection()` (Query 5039) para adicionar a guarda real de C-13.
