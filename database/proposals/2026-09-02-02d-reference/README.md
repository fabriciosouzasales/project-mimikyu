# Staging — Collections Physical Increment 02D — Collection Reference Foundation

| Campo | Valor |
|--------|-------|
| **Pasta** | `database/proposals/2026-09-02-02d-reference/` |
| **Status** | PROPOSTA — NENHUM ARQUIVO EXECUTADO NO SUPABASE |
| **Rodadas de origem** | `COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-01`, `-REVISION-01`, `-FINAL-01`, `-STAGING-REVISION-01` |
| **Data** | 2026-09-02 |

Esta pasta é **staging**: SQL proposto, pronto para revisão, mas nada
aqui foi rodado contra o Supabase real. Nenhum arquivo entra em
`database/schema/` até ser **confirmadamente executado** — mesma
disciplina do `CLAUDE.md` (seção "Escrita de SQL") e do precedente
direto desta pasta, `database/proposals/2026-09-01-02c-allocation/`.

## Por que este incremento existe

O Incremento 02C (Collection Allocation) fechou "como uma carta entra
numa Collection". Ficou em aberto a pergunta seguinte: **qual universo
de catálogo esta Collection pretende representar?** — hoje toda
Collection é `OPEN_CURATION` (curadoria livre, sem meta declarada). O
02D introduz o primeiro modo com meta declarada: `REFERENCE_BASED` com
`reference_kind = 'CARD_SET'` — uma Collection que se propõe a
representar um Card Set inteiro, com a infraestrutura para (fora desta
rodada) eventualmente calcular percentual de conclusão contra essa
meta.

## Autoridade conceitual

- `docs/domain-modeling/collections/concept-decisions.md` — C-01 a
  C-37, com ênfase em C-13 (mode), C-18/C-19 (Reference Locking),
  C-27 a C-31 (eligibility).
- `docs/domain-modeling/collections/logical-model.md` — LDM-01 a
  LDM-23, com ênfase em LDM-06 (Collection Reference como entidade
  supertype/subtype, não coluna polimórfica solta), LDM-07
  (`reference_locked_at`), LDM-17 (elegibilidade).
- `docs/05d-colecoes-e-usuarios.md` — modelo físico já confirmado
  executado de Collection (5030-5039), Collection Allocation
  (5040-5048) e as extensões de `started_at`/lock (5044/5045).
- `database/schema/5030_create_collection_table.sql` (v1.1) — DDL
  atual de `collection`, base de todas as extensões desta pasta.

## Decisões de desenho fechadas nesta rodada

**Imutabilidade de `mode`.** V1 não permite conversão
`OPEN_CURATION` <-> `REFERENCE_BASED` em nenhuma direção. Uma
Collection `REFERENCE_BASED` só nasce já com sua Reference — nunca
existe um estado intermediário persistente de "`REFERENCE_BASED` sem
Reference ainda". Reforçado estruturalmente por `5061` (imutabilidade
de `mode`) e pelos dois lados do par supertipo/subtipo (`5057`/`5058`).

**Consistência diferida em dois lados.** O par supertipo/subtipo
(`collection_reference` / `collection_card_set_reference`) precisa de
garantia bidirecional: uma mutação direta em qualquer um dos dois
lados — não só no supertipo — precisa ser pega. Um único
`CREATE CONSTRAINT TRIGGER` no supertipo não veria uma escrita direta
no subtipo. Resolvido com uma função compartilhada
(`check_collection_reference_subtype_consistency()`, em `5057`) e dois
`CREATE CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` distintos
— um em cada tabela (`5057`/`5058`) — ambos avaliados só no `COMMIT`,
permitindo que a RPC de criação atômica (`5065`) insira as três linhas
em `INSERT`s separados dentro da mesma transação sem que o estado
intermediário (incompleto) seja rejeitado. Primeira vez que este
padrão de trigger é usado no projeto — documentado em detalhe no
cabeçalho de `5057`/`5058`.

**Endurecimento de identidade estrutural.** Nenhuma das duas tabelas
novas permite reparenting: `collection_reference.collection_id`,
`collection_reference.reference_kind` e
`collection_card_set_reference.collection_reference_id` são todos
imutáveis após o `INSERT` (`5051`/`5054`). `reference_kind` hoje só
aceita `'CARD_SET'` (CHECK) — a imutabilidade por trigger só passa a
ser o mecanismo relevante (em vez do CHECK) quando um segundo valor
legal existir.

**`ON DELETE CASCADE` justificado.** `collection_reference.collection_id`
e `collection_card_set_reference.collection_reference_id` usam CASCADE
— exceção deliberada à postura padrão `RESTRICT` do projeto, porque
Reference/subtipo são sub-entidades de posse exclusiva da Collection,
sem existência própria fora dela. `collection_card_set_reference.card_set_id`
permanece `RESTRICT` (Card Set é catálogo compartilhado, nunca perde
linhas por causa de uma Collection).

**Reference não pode nascer depois do lock (blocker fechado em
`-STAGING-REVISION-01`).** Auditoria adicional revelou um cenário não
coberto pela versão original: dentro de uma única transação
privilegiada, era possível inserir uma Collection `REFERENCE_BASED`
sem Reference, alocar uma carta a ela (a checagem de elegibilidade usa
`LEFT JOIN` — sem Reference ainda, nada a checar), deixar
`reference_locked_at` materializar, e só então criar a Collection
Reference — os triggers diferidos veem o estado FINAL consistente e
deixam passar, mesmo violando a regra temporal ("a Reference precisa
preceder a primeira Allocation", não apenas coexistir com ela). Como
nenhum trigger diferido consegue enxergar ORDEM de eventos (só o
snapshot no `COMMIT`), a correção teve que ser uma checagem IMEDIATA:
`5055`/`5056` agora rejeitam o `INSERT` de Reference/subtipo sempre que
`reference_locked_at` já estiver definido no momento exato do insert —
independente do que os triggers diferidos veriam depois. Coberto pelo
Caso Z em `5808`.

**Elegibilidade em duas camadas.** Toda alocação para uma Collection
`REFERENCE_BASED`/`CARD_SET` exige que a Card pertença ao Card Set
referenciado. Camada 1: pré-checagem amigável na RPC
(`allocate_physical_cards_to_collection()`, `5064`). Camada 2: garantia
estrutural independente via trigger (`validate_collection_allocation_integrity()`,
`5063`), que vale mesmo contra um `INSERT` direto em
`collection_allocation`, bypassando a RPC. Fail-closed: qualquer carta
fora do Card Set reprova o lote inteiro.

**Mecanismo de `reference_locked_at`.** Reaproveita a mesma
materialização de `started_at` (Query 5045/`materialize_collection_started_at()`)
— estendida em `5062` para também gravar `reference_locked_at` na
primeira Allocation de uma Collection `REFERENCE_BASED`, com a mesma
fonte (`MIN(new_table.created_at)`). Imutável depois de setado, e sua
primeira gravação é validada contra o mesmo `MIN` (`5061`), com uma
guarda extra para nunca disparar em Collections `OPEN_CURATION` (que
também acumulam `collection_allocation`, mas nunca têm
`reference_locked_at`).

**Superfície de RPC.** Nenhum parâmetro novo em `create_collection()`
(5034) ou `update_collection_metadata()` (5035) — permanecem exclusivas
de `OPEN_CURATION`/nome-descrição. Duas RPCs novas e dedicadas:
`create_reference_based_card_set_collection()` (`5065`, criação
atômica) e `set_collection_card_set_reference()` (`5066`, troca de
Card Set só antes do lock). Ambas seguem o padrão de não-enumeração já
estabelecido (`owner_user_id = auth.uid()` no `WHERE`/`FOR UPDATE`).

**Delete/lifecycle.** `delete_collection()` (já existente, não alterada
nesta rodada) nunca exigiu `ACTIVE` — CASCADE precisa funcionar tanto
para Collections `ACTIVE` quanto `ARCHIVED`, contanto que zero
Allocations existam (regra já vigente de 2B/2C, não reaberta aqui). O
guard de lifecycle em `5056` usa a técnica "o pai ainda existe?" para
distinguir uma mutação standalone (bloqueada) de um efeito colateral
de CASCADE (permitido).

## Conteúdo

| Arquivo | Conteúdo |
|---------|----------|
| `5049_create_collection_reference_table.sql` | Tabela supertipo `collection_reference` |
| `5050_create_collection_reference_updated_at_trigger.sql` | `updated_at` do supertipo |
| `5051_create_collection_reference_structural_identity_trigger.sql` | Imutabilidade de `collection_id`/`reference_kind` |
| `5052_create_collection_card_set_reference_table.sql` | Tabela subtipo `collection_card_set_reference` |
| `5053_create_collection_card_set_reference_updated_at_trigger.sql` | `updated_at` do subtipo |
| `5054_create_collection_card_set_reference_structural_identity_trigger.sql` | Imutabilidade de `collection_reference_id` (sem reparenting) |
| `5055_create_collection_card_set_reference_game_and_lock_trigger.sql` | v1.1 — Guarda de Game + lock em INSERT/UPDATE de `card_set_id`, agora também rejeitando INSERT do subtipo se `reference_locked_at` já definido |
| `5056_create_collection_reference_lifecycle_guard_trigger.sql` | v1.1 — Guarda de lifecycle (ARCHIVED bloqueia, CASCADE não), agora também rejeitando INSERT de Reference se `reference_locked_at` já definido (blocker fechado em `-STAGING-REVISION-01`) |
| `5057_create_collection_reference_consistency_trigger.sql` | Trigger diferido (lado supertipo) + função compartilhada |
| `5058_create_collection_card_set_reference_consistency_trigger.sql` | Trigger diferido (lado subtipo) — fecha o blocker |
| `5059_create_collection_reference_presence_trigger.sql` | Trigger diferido: `mode = REFERENCE_BASED` exige Reference |
| `5060_alter_collection_widen_mode_and_unlock_reference.sql` | Amplia `chk_collection_mode`; libera `reference_locked_at` |
| `5061_update_collection_structural_identity_trigger.sql` | Extensão de 5032/5044: imutabilidade de `mode`/`reference_locked_at` |
| `5062_update_collection_started_at_from_allocation_trigger.sql` | Extensão de 5045: materializa `reference_locked_at` |
| `5063_update_collection_allocation_integrity_trigger.sql` | Extensão de 5042: checagem 4 (elegibilidade, camada estrutural) |
| `5064_update_allocate_physical_cards_to_collection_function.sql` | Extensão de 5046: checagem de elegibilidade (camada RPC) |
| `5065_create_reference_based_card_set_collection_function.sql` | RPC nova: criação atômica REFERENCE_BASED/CARD_SET |
| `5066_create_set_collection_card_set_reference_function.sql` | RPC nova: troca de Card Set antes do lock |
| `5808_validate_collections_physical_increment_02d.sql` | v2.1 — Plano de validação funcional — Casos A-Z (executável: sem SAVEPOINT em blocos DO, assinaturas reais de RPC, Caso Z cobrindo o blocker com assertion específica de SQLERRM, Caso U com pré-condição comprovada em vez de reexecutar operações já feitas, Caso X com existence count explícito) |
| `5809_performance_checks_collections_physical_increment_02d.sql` | v2.1 — Plano de performance — 4 workloads (executável: sem `\echo`, assinaturas reais, alternância DEFERRED/IMMEDIATE corrigida, Fases A/B separadas nos Workloads 1-2, Workload 3 medindo troca real CS1→CS2, Workload 4a sobre o mesmo lote real de 4b) |

Numeração: `5049`-`5066` contínua a partir do maior número já
CONFIRMADO EXECUTADO em `database/schema/` (`5047`, verificado via
`ls` antes desta rodada). `5808`/`5809` seguem a sub-faixa
`X800`-`X899` já reservada para pares validação/performance — `5806`/
`5807` já estão em uso pela pasta `2026-09-01-02c-allocation/`, também
verificado antes de reservar.

## Fora do escopo desta pasta

- `collection_pokedex_reference` (segundo `reference_kind`) — LDM-06
  já prevê a extensão, nada aqui a antecipa.
- `completion_policy` / cálculo de percentual de conclusão — deferido
  integralmente para um futuro "02E" (decisão fechada em
  `-REVISION-01`).
- Master Set / Adopted Scope — não mencionado em nenhuma das três
  rodadas de origem.
- Qualquer alteração de frontend/UX — as três rodadas foram
  exclusivamente de modelagem física de banco.
- Qualquer alteração em `create_collection()` (5034),
  `update_collection_metadata()` (5035), `archive_collection()`,
  `reactivate_collection()`, `delete_collection()` ou
  `deallocate_physical_cards_from_collection()` (5047) — nenhuma das
  cinco foi tocada nesta rodada.

## Próximos passos (fora desta rodada)

1. Revisão humana desta pasta por Fabrício.
2. Uma futura rodada `COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01`
   aplica `5049`-`5066` ao Supabase real (uma Query por vez, padrão
   STD-001 §10), executa `5808`/`5809` de fato, e só então promove os
   arquivos para `database/schema/` com o carimbo "CONFIRMADO
   EXECUTADO".
3. Reconciliação de documentação (`docs/05d-colecoes-e-usuarios.md`,
   `docs/INDEX.md`, `docs/log.md`, `docs/README.md`, handoff) no mesmo
   ciclo da implementação — mesmo padrão já usado para 2B/2C.
