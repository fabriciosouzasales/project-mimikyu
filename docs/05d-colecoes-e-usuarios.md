# Modelo de Dados — Coleções e Usuários

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Coleções e Usuários |
| **Arquivo** | `docs/05d-colecoes-e-usuarios.md` |
| **Versão** | 1.17 |
| **Status** | Em elaboração |
| **Objetivo** | Modelo lógico e físico de Physical Card (nome canônico desde 2026-08-30; ver `domain-modeling/collections/concept-decisions.md` C-47/C-48), Storage/Storage Container, Collection/Collection Entry, User Profile/Reserved Username e Administração de Usuários. |
| **Escopo** | Parte de `docs/05-modelo-de-dados.md` (índice) — resultado da divisão de 2026-08-06, motivada pelo tamanho do arquivo original (mais de 700 KB, acima do que ferramentas de leitura processam em uma chamada). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md`, `05-modelo-de-dados.md` |

Ver `docs/05-modelo-de-dados.md` para o mapa completo do domínio, a metodologia (Roteiro por Entidade) e o histórico de revisão consolidado até 2026-08-06 (revisões anteriores a esta divisão não foram redistribuídas retroativamente por entidade — ver nota na Revision History de lá).

---

# Physical Card (Exemplar Físico) / Inventory

## Status

**Fundação física de Inventory + Physical Card CONFIRMADO EXECUTADO em 2026-08-31** (`COLLECTIONS-PHYSICAL-INCREMENT-01B`, primeira entidade do milhar `5000`–`5999`, Módulo Collections — Modelo Modular de Numeração, STD-001 Seção 10). Precedida por três rodadas de modelagem física sem alteração de banco (`COLLECTIONS-PHYSICAL-MODELING-01`/`-02`, `COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01`) e por uma rodada de staging auditada em `database/proposals/2026-08-31-collections-physical-increment-01a/` antes da aplicação real. Seis Queries estruturais (`5000`–`5012`), uma bateria de validação de 23 itens e um plano de performance sob volume de 20.000 linhas — todos executados e confirmados ao vivo na mesma rodada. Modelagem lógica/conceitual canônica em `domain-modeling/collections/concept-decisions.md` (C-47/C-48) e `logical-model.md` (LDM-23) — nenhuma das duas foi reaberta nesta rodada; nenhuma divergência entre o conceitual e o físico aplicado foi encontrada.

## Decisão de Modelagem

`Inventory` é um agregado de domínio próprio — não compartilha PK com `auth.users` (contraste deliberado com o padrão de `user_profile`, ver acima): tem `id` gerado independente, com a cardinalidade 1:1 por User garantida por `UNIQUE(owner_user_id)`, não pelo PK. Decisão revisada em `COLLECTIONS-PHYSICAL-MODELING-02` a partir de uma primeira proposta que usava PK=FK — rejeitada porque `Inventory` é um agregado patrimonial com identidade e ciclo de vida próprios (C-48), não um apelido para o próprio User.

`Physical Card` é o exemplar físico individual (C-47) — cada cópia possuída é sua própria linha, sem coluna `quantity`. `inventory_id` é nulável por desenho (uma Physical Card pode existir sem custódia corrente — saída de custódia, fora de escopo desta fundação) mas a FK usa `ON DELETE RESTRICT`, nunca `SET NULL`: mudança de custódia é sempre uma operação de domínio explícita futura (Lifecycle/Provenance, C-67–C-81), nunca efeito colateral de um `DELETE`.

Toda escrita em `physical_card` passa exclusivamente pela RPC `add_physical_cards()` (bulk-first, 1–500 itens por chamada) — não existe policy de `INSERT`/`UPDATE`/`DELETE` para `authenticated` em nenhuma das duas tabelas; o Inventory de destino é sempre resolvido no servidor a partir de `auth.uid()`, nunca aceito como parâmetro, tornando estruturalmente impossível ao cliente forjar o Inventory de outro usuário.

## Modelo Físico — `inventory` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.inventory (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id  UUID NOT NULL UNIQUE
                       REFERENCES auth.users(id)
                       ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY inventory_select_own
    ON public.inventory FOR SELECT
    USING (owner_user_id = (select auth.uid()));

GRANT SELECT ON public.inventory TO authenticated;
```

`owner_user_id` é `UNIQUE` (garante exatamente 1 Inventory por User) e `ON DELETE RESTRICT` (nenhum `DELETE` em `auth.users` remove silenciosamente um Inventory com Physical Cards vinculados — não existe fluxo de exclusão de conta no repositório hoje, confirmado por Gate 1 de `COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01`). Única policy de RLS é `SELECT` do próprio owner; nenhuma via de escrita direta — provisionamento é exclusivamente pelo trigger `SECURITY DEFINER` da Query `5002`. Confirmado via `information_schema`/`pg_policies`/`pg_class` contra o banco real. Arquivo em `database/schema/5000_create_inventory_table.sql`.

## Query `5001` — Create Inventory Trigger (CONFIRMADO EXECUTADO)

Mantém `updated_at`, reaproveitando `public.set_updated_at()` — mesmo padrão de toda a base. Confirmado via `information_schema.triggers`. Arquivo em `database/schema/5001_create_inventory_trigger.sql`.

## Query `5002` — Create Inventory Provisioning and Backfill (CONFIRMADO EXECUTADO, v1.1)

Consolida em uma única transação (`BEGIN`/`COMMIT` explícitos — padrão comprovado do projeto, confirmado em 72 arquivos de `database/` antes desta rodada, ver `COLLECTIONS-PHYSICAL-INCREMENT-01A-FINAL-CHECK`): `handle_new_user_inventory()` (`SECURITY DEFINER`, `SET search_path = ''`, `INSERT ... ON CONFLICT (owner_user_id) DO NOTHING`), o trigger `on_auth_user_created_inventory AFTER INSERT ON auth.users` (independente de `handle_new_user()`/Query `1020` — decisão deliberada para não introduzir risco em um mecanismo já em produção), e o backfill idempotente dos Users pré-existentes. Consolidar as duas operações na mesma transação elimina a janela em que o trigger existiria sem que Users antigos tivessem Inventory (achado da revisão `COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01`, item 1).

Validado ao vivo em três frentes: backfill dos 2 Users pré-existentes confirmado por contagem; reexecução idempotente do backfill sem duplicar linhas; e — por exigência explícita de Fabrício de que a prova fosse observada ao vivo, não indireta — provisionamento automático de um **novo** User testado através do fluxo real de signup da aplicação (um `INSERT` direto em `auth.users` foi bloqueado pelo classificador de segurança do Auto Mode; a alternativa de signup real foi escolhida explicitamente por Fabrício). Resultado: exatamente 1 Inventory criado para o novo User, `owner_user_id` correto. Arquivo em `database/schema/5002_create_inventory_provisioning_and_backfill.sql`.

## Modelo Físico — `physical_card` (Versão 1.1, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.physical_card (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_variant_id UUID NOT NULL REFERENCES public.card_variant(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    language_id     UUID NOT NULL REFERENCES public.language(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    inventory_id    UUID NULL REFERENCES public.inventory(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_physical_card_inventory_variant ON public.physical_card (inventory_id, card_variant_id);
CREATE INDEX ix_physical_card_inventory_language ON public.physical_card (inventory_id, language_id);

ALTER TABLE public.physical_card ENABLE ROW LEVEL SECURITY;

CREATE POLICY physical_card_select_own
    ON public.physical_card FOR SELECT
    USING (inventory_id = (SELECT i.id FROM public.inventory i WHERE i.owner_user_id = (select auth.uid())));

GRANT SELECT ON public.physical_card TO authenticated;
```

Sem `UNIQUE(card_variant_id, language_id)` — duplicatas são o comportamento esperado (múltiplas cópias da mesma Card Variant/idioma). Dois índices compostos, ambos liderados por `inventory_id` (padrão de acesso real, inclusive a própria RLS) — nenhum índice isolado em `card_variant_id`/`language_id`; a versão original cogitava um índice isolado de `language_id`, substituído nesta revisão pelo composto `(inventory_id, language_id)` por não haver consumidor real do índice isolado. Uso real de ambos os índices (e do `UNIQUE(owner_user_id)` de `inventory` na resolução da RLS) confirmado por `EXPLAIN (ANALYZE, BUFFERS)` sob volume sintético de 20.000 linhas, contexto transacional reversível — ver `database/validations/5801_performance_checks_collections_physical_increment_01a.sql`. Arquivo em `database/schema/5010_create_physical_card_table.sql`.

## Query `5011` — Create Physical Card Trigger (CONFIRMADO EXECUTADO)

Mesmo padrão de `5001`, reaproveitando `set_updated_at()`. Arquivo em `database/schema/5011_create_physical_card_trigger.sql`.

## Query `5012` — Create `add_physical_cards()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER` (estruturalmente necessária, não estilística: não existe policy de `INSERT` para `authenticated`, então uma função `SECURITY INVOKER` seria bloqueada pela própria RLS), `SET search_path = ''`, `RETURNS TABLE (id, card_variant_id, language_id, created_at)` — deliberadamente não `RETURNS SETOF public.physical_card`, para que colunas futuras da tabela (Collection, Storage, Condition, Certification, Lifecycle, Audit) não vazem automaticamente para o contrato público da RPC. Único parâmetro é `p_items jsonb` (array de 1 a 500 objetos `{card_variant_id, language_id}`) — sem `inventory_id`, sem `quantity`; o Inventory de destino é sempre resolvido no servidor via `auth.uid()`.

Validações no corpo da função: `auth.uid() IS NULL` rejeitado; `p_items` deve ser array JSON, não vazio, no máximo 500 itens (limite justificado por tamanho de payload, tempo de transação, Set físico realista e prevenção de abuso); item inválido (FK inexistente) aborta o lote inteiro (atomicidade nativa de um único `INSERT...SELECT...RETURNING`); duplicatas de `card_variant_id`+`language_id` são permitidas. `EXECUTE` revogado de `PUBLIC`/`anon`, concedido apenas a `authenticated`.

Validado ao vivo, todos os cenários transacionais com `ROLLBACK`: lote válido N→N (3→3, com duplicatas); item inválido → exceção de FK, 0 persistidos; lote vazio, payload não-array e lote >500 rejeitados com a mensagem esperada; `UPDATE`/`DELETE` direto negados em `physical_card` mesmo para o próprio dado do usuário (RPC é a única superfície de escrita, sem exceção); chamada bulk de 500 itens medida sob `EXPLAIN (ANALYZE, BUFFERS)` com 20.000 Physical Cards já existentes no Inventory alvo — 52,525 ms. Arquivo em `database/schema/5012_create_add_physical_cards_function.sql`.

## Sequência

```text
5000 - Create Inventory table                              (CONFIRMADO EXECUTADO — database/schema/5000_create_inventory_table.sql)
5001 - Create Inventory trigger                             (CONFIRMADO EXECUTADO — database/schema/5001_create_inventory_trigger.sql)
5002 - Create Inventory provisioning and backfill (v1.1)     (CONFIRMADO EXECUTADO — database/schema/5002_create_inventory_provisioning_and_backfill.sql)
5010 - Create Physical Card table (v1.1)                     (CONFIRMADO EXECUTADO — database/schema/5010_create_physical_card_table.sql)
5011 - Create Physical Card trigger                          (CONFIRMADO EXECUTADO — database/schema/5011_create_physical_card_trigger.sql)
5012 - Create add_physical_cards() function (v1.1)            (CONFIRMADO EXECUTADO — database/schema/5012_create_add_physical_cards_function.sql)
5800 - Validate Collections Physical Increment 01A (23 itens) (EXECUTADA — database/validations/5800_validate_collections_physical_increment_01a.sql)
5801 - Performance Checks Collections Physical Increment 01A  (EXECUTADA — database/validations/5801_performance_checks_collections_physical_increment_01a.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída nesta rodada — fundação exclusivamente de banco (`inventory`/`physical_card`/`add_physical_cards()`). Saída de custódia (transferência/perda/venda), Collection/Collection Entry (alocação de Physical Card dentro de uma Coleção específica), Condition, Certification, Lifecycle/Provenance detalhado, Favorite, Wishlist e Activity History/Audit têm modelagem conceitual já fechada (`concept-decisions.md`/`logical-model.md`) mas nenhuma delas tem modelo físico ainda — cada uma será um incremento físico separado, seguindo o mesmo padrão desta rodada (staging auditado → aplicação real gateada por fase → reconciliação). Storage/Storage Container física já consolidada — ver seção própria a seguir.

---

# Storage / Storage Container

## Status

**Fundação física de Storage Container + `physical_card.storage_container_id` CONFIRMADO EXECUTADA em 2026-09-01** (`COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`, Incremento 2A — Storage Foundation, dentro do milhar `5000`–`5999`, Módulo Collections). Precedida por três rodadas de modelagem física sem alteração de banco (`COLLECTIONS-PHYSICAL-MODELING-03`, `-REVISION-01`, `-REVISION-02`, `-FINAL-01`) e por uma rodada de staging auditada em `database/proposals/2026-08-31-02a-storage/` antes da aplicação real. Cinco Queries estruturais (`5020`–`5024`), uma bateria de validação de 19 itens (incluindo os casos estruturais A–E da FK composta e os casos funcionais F–J da RPC de Current Storage) e um plano de performance sob volume de 20.000 linhas — todos executados e confirmados ao vivo na mesma rodada. Modelagem lógica/conceitual canônica em `domain-modeling/collections/concept-decisions.md` (C-55–C-61) e `logical-model.md` (LDM-44–LDM-54) — nenhuma das duas foi reaberta nesta rodada. Este é o primeiro incremento físico de Storage Container do projeto — nenhum skeleton físico havia sido fixado em rodada lógica anterior.

Este incremento existe especificamente para desbloquear Collection (ainda não iniciada fisicamente): `collection.default_storage_container_id` será `NOT NULL` desde a criação (C-36), e criar `collection` antes de `storage_container` existir geraria estado fisicamente incompatível com C-36.

## Decisão de Modelagem

`storage_container` é a unidade física endereçável de armazenamento corrente (C-55/C-56), com ownership mediado por Inventory (C-57) — mesmo padrão já usado em `physical_card`, nunca `owner_user_id` direto como fonte paralela de ownership. Escopo desta fundação é deliberadamente mínimo: apenas identidade, `name` e vínculo com Inventory — hierarquia (C-60), capacidade (C-62), Bulk Card Transfer (C-64), Reparent (C-65) e Protection/Encapsulation (C-56) permanecem fora, sem nenhum campo/tabela/relação criado para eles.

Integridade Inventory × Storage (C-61 — Storage nunca cruza Inventory) é garantida de forma **declarativa**, via FK composta, não por trigger: `storage_container` ganha `UNIQUE(id, inventory_id)` e `physical_card.storage_container_id` referencia essas duas colunas junto de `inventory_id` via `FOREIGN KEY (storage_container_id, inventory_id) REFERENCES storage_container(id, inventory_id)`. A validação técnica desta rodada identificou um caso não coberto por `MATCH SIMPLE` (padrão do Postgres quando `MATCH` não é especificado): a constraint é pulada quando qualquer coluna referenciadora é NULL, o que deixaria passar `storage_container_id` preenchido com `inventory_id` NULL. Fechado com um `CHECK` local adicional (`chk_physical_card_storage_requires_inventory`), sem depender de outra tabela.

Toda escrita de Current Storage passa exclusivamente pela RPC `set_physical_cards_storage()` (bulk-first, 1–500 itens por chamada, `p_storage_container_id` nulável — `NULL` limpa a localização corrente, cobrindo o ciclo de vida completo 0..1 de C-58) — não existe policy de `UPDATE` para `authenticated` em `physical_card` para esta coluna. IDs duplicados no payload são normalizados internamente para `DISTINCT`; o teto de 500 é avaliado sobre o array recebido, antes da deduplicação. Não há auto-provisionamento de um Storage Container "padrão" por Inventory — Storage Container representa unidade física real do acervo, nunca um placeholder; fica como requisito de UX futuro (não desenhado nesta rodada) permitir, na criação da Collection, selecionar um Storage Container existente ou criar um novo no próprio fluxo.

## Modelo Físico — `storage_container` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.storage_container (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_id   UUID NOT NULL
                       REFERENCES public.inventory(id)
                       ON UPDATE RESTRICT ON DELETE RESTRICT,
    name           TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_storage_container_id_inventory UNIQUE (id, inventory_id)
);

ALTER TABLE public.storage_container ENABLE ROW LEVEL SECURITY;

CREATE POLICY storage_container_select_own
    ON public.storage_container FOR SELECT
    USING (inventory_id = (SELECT i.id FROM public.inventory i WHERE i.owner_user_id = (select auth.uid())));

GRANT SELECT ON public.storage_container TO authenticated;
```

`UNIQUE(id, inventory_id)` não é uma segunda chave candidata independente — existe exclusivamente para servir de alvo da FK composta a partir de `physical_card`. RLS/grants no mesmo padrão de `inventory`/`physical_card`: única policy é `SELECT` do próprio owner (via Inventory), nenhuma via de escrita direta. Validado ao vivo: usuário A não vê Storage Container de B; `INSERT` direto e acesso `anon` negados (permission denied, não apenas 0 linhas). Arquivo em `database/schema/5020_create_storage_container_table.sql`.

## Query `5021` — Create Storage Container Trigger (CONFIRMADO EXECUTADO)

Mantém `updated_at`, reaproveitando `public.set_updated_at()`. Arquivo em `database/schema/5021_create_storage_container_trigger.sql`.

## Query `5022` — Create `create_storage_container()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, único parâmetro `p_name text` — sem `inventory_id`, resolvido no servidor via `auth.uid()`. Não é bulk (criação de Storage Container é evento de UX único). Retorno explícito `(id, name, created_at)`, não `RETURNS SETOF storage_container`, mesma justificativa de contrato mínimo de `add_physical_cards()`. Validado ao vivo: Storage Container criado sempre resolve para o Inventory do próprio chamador. Arquivo em `database/schema/5022_create_create_storage_container_function.sql`.

## Query `5023` — Alter Physical Card: Add Storage Container Link (CONFIRMADO EXECUTADO)

```sql
ALTER TABLE public.physical_card ADD COLUMN storage_container_id UUID NULL;

ALTER TABLE public.physical_card
    ADD CONSTRAINT fk_physical_card_storage_same_inventory
    FOREIGN KEY (storage_container_id, inventory_id)
    REFERENCES public.storage_container (id, inventory_id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE public.physical_card
    ADD CONSTRAINT chk_physical_card_storage_requires_inventory
    CHECK (storage_container_id IS NULL OR inventory_id IS NOT NULL);

CREATE INDEX ix_physical_card_storage_container ON public.physical_card (storage_container_id);
```

`storage_container_id` é 0..1 (LDM-46/C-58), nulável por desenho. Índice isolado (não composto com `inventory_id`) justificado por workload confirmado — "conteúdo deste Storage Container" — e por RLS já escopar por Inventory antes de qualquer filtro de Storage. Validado ao vivo, por tentativa de escrita real (não apenas introspecção): Physical Card + Storage do mesmo Inventory aceito; Physical Card + Storage de outro Inventory rejeitado (violação da FK composta); `storage_container_id` NULL aceito independente de `inventory_id`; mudar `inventory_id` mantendo Storage de outro Inventory rejeitado (FK composta); Storage preenchido + `inventory_id` NULL rejeitado (via CHECK, não via FK — confirma que os dois mecanismos cobrem casos complementares de `MATCH SIMPLE`). Performance: consulta "conteúdo de um Storage Container" sobre 20.000 Physical Cards usou `ix_physical_card_storage_container` (Index Scan), 0,764ms, 284 buffer hits, 0 leituras de disco. Arquivo em `database/schema/5023_alter_physical_card_add_storage_container.sql`.

## Query `5024` — Create `set_physical_cards_storage()` (CONFIRMADO EXECUTADO, v2.0)

Function `SECURITY DEFINER`, `SET search_path = ''`, `RETURNS TABLE (id, storage_container_id, updated_at)` — não `RETURNS SETOF physical_card`. Parâmetros: `p_storage_container_id UUID` (nulável — `NULL` limpa Current Storage) e `p_physical_card_ids UUID[]` (1–500 por chamada, deduplicados internamente via `array_agg(DISTINCT ...)`, teto avaliado sobre o array recebido antes da deduplicação). Substitui a v1.0 (`assign_physical_cards_to_storage()`, só atribuía/movia) — a v2.0 cobre o ciclo de vida completo 0..1 de Current Storage.

Validado ao vivo: `NULL` limpa a localização corrente; payload `[A,A,B]` afeta A e B exatamente uma vez; lote misto (cartas do próprio Owner + carta de outro User) rejeitado com zero alterações, inclusive nas cartas do próprio Owner (atomicidade real); lote de 501 elementos rejeitado antes da deduplicação; Storage Container de outro Inventory rejeitado. Performance sobre 20.000 Physical Cards: bulk assign de 500 itens ~61–65ms, bulk clear (NULL) de 500 itens ~55ms — mesma ordem de grandeza de `add_physical_cards()` (52,525ms). Arquivo em `database/schema/5024_create_set_physical_cards_storage_function.sql`.

## Sequência

```text
5020 - Create Storage Container table                         (CONFIRMADO EXECUTADO — database/schema/5020_create_storage_container_table.sql)
5021 - Create Storage Container trigger                        (CONFIRMADO EXECUTADO — database/schema/5021_create_storage_container_trigger.sql)
5022 - Create create_storage_container() function               (CONFIRMADO EXECUTADO — database/schema/5022_create_create_storage_container_function.sql)
5023 - Alter Physical Card: add storage_container_id            (CONFIRMADO EXECUTADO — database/schema/5023_alter_physical_card_add_storage_container.sql)
5024 - Create set_physical_cards_storage() function (v2.0)      (CONFIRMADO EXECUTADO — database/schema/5024_create_set_physical_cards_storage_function.sql)
5802 - Validate Collections Physical Increment 02A (19 itens)   (EXECUTADA — database/validations/5802_validate_collections_physical_increment_02a.sql)
5803 - Performance Checks Collections Physical Increment 02A    (EXECUTADA — database/validations/5803_performance_checks_collections_physical_increment_02a.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída nesta rodada — fundação exclusivamente de banco. Hierarquia de Storage Container, capacidade, Bulk Card Transfer, Reparent e Protection/Encapsulation permanecem sem modelo físico, cada um como incremento próprio se/quando necessário. Incremento 2B (Collection + Default Storage) e Incremento 2C (Collection Allocation) já **CONFIRMADOS EXECUTADOS** — ver seções próprias a seguir. Collection Reference permanece deferida a um incremento posterior, sem bloquear os anteriores.

---

# Collection (Coleção)

## Status

**Skeleton físico do núcleo de Collection + Default Storage CONFIRMADO EXECUTADO em 2026-09-01** (`COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`, Incremento 2B, dentro do milhar `5000`–`5999`, Módulo Collections). Precedida por três rodadas de modelagem física sem alteração de banco (`COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01`, `-REVISION-01`, `-FINAL-01`), uma rodada de correção de concorrência/idempotência ainda em staging (`-STAGING-REVISION-01`) e uma rodada de staging auditado em `database/proposals/2026-08-31-02b-collection/` antes da aplicação real. Dez Queries estruturais (`5030`–`5039`), uma bateria de validação (21+ casos, 2 achados reais corrigidos no mesmo ciclo) e um plano de performance sob volume de 20.000 linhas — todos executados e confirmados ao vivo na mesma rodada. Modelagem lógica/conceitual canônica em `domain-modeling/collections/concept-decisions.md` (C-01–C-37, C-141) e `logical-model.md` (LDM-01–LDM-27, skeleton físico LDM-12) — nenhuma das duas foi reaberta nesta rodada.

Este incremento depende de Storage Foundation (2A) já existir fisicamente, porque `collection.default_storage_container_id` é `NOT NULL` desde a criação (C-36).

## Decisão de Modelagem

`collection` tem identidade própria (`id` gerado) e ownership **direto** por `owner_user_id` — diferente de `storage_container`/`physical_card`, NÃO mediado por Inventory (decisão já fixada em LDM-02/C-141, não reaberta). Materialização deliberadamente mínima do skeleton de LDM-12 nesta rodada (2B): campos preservados exatamente conforme a modelagem lógica, com exclusões explícitas — sem `started_at` (C-30/LDM-11, primeira alocação ainda não existia nesta rodada; passou a existir fisicamente no Incremento 2C, ver seção própria a seguir), sem `created_by_user_id`/`updated_by_user_id`, sem `completion_policy` (LDM-08, semanticamente vazio sem Collection Reference), sem Collection Allocation (idem — resolvida no 2C) nem Collection Reference/Membership/Layout (permanecem deferidas).

Duas restrições físicas temporárias, ambas conscientemente reversíveis quando os incrementos que as tornam desnecessárias existirem: `mode` fisicamente só `'OPEN_CURATION'` (`REFERENCE_BASED` aguarda Collection Reference) e `visibility` fisicamente só `'PRIVATE'` (Public Access/C-15 não tem projeção/read model seguro implementado ainda — `set_collection_visibility()` deliberadamente não criada nesta rodada; quando Public Access existir, a projeção segura vem primeiro, a constraint é ampliada depois, a RPC vem por último, nessa ordem). `reference_locked_at` existe fisicamente (evita `ALTER TABLE` futuro) mas travado em `NULL` por CHECK — o Incremento 2C (Collection Allocation) NÃO o tocou; quem vai legitimamente controlá-lo é o futuro incremento de Collection Reference (LDM-07), ainda sem data.

`owner_user_id`/`game_id` são estruturalmente imutáveis após a criação (trigger dedicado, não CHECK — CHECK não compara OLD/NEW). Integridade Owner × Default Storage é garantida por **trigger** (não FK composta, ao contrário de `physical_card`×`storage_container`): `collection.owner_user_id` e `storage_container.inventory_id` não compartilham nenhuma coluna, e adicionar um `inventory_id` redundante a `collection` só para viabilizar uma FK composta foi avaliado e descartado (`COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01`, item 3).

Todas as seis operações de escrita passam por RPC `SECURITY DEFINER` — nenhuma policy de `INSERT`/`UPDATE`/`DELETE` para `authenticated`. As quatro RPCs de edição/lifecycle (`update_collection_metadata`/`set_collection_default_storage`/`archive_collection`/`reactivate_collection`) usam o padrão **UPDATE-atômico-com-guard-no-WHERE**: o guard de estado (`lifecycle_status = 'ACTIVE'` ou `'ARCHIVED'`, conforme o caso) é parte do próprio `WHERE` da `UPDATE`, não uma checagem `SELECT` separada — sob READ COMMITTED, isso elimina a janela de corrida entre checar e escrever (ex.: editar metadata de uma Collection concorrentemente arquivada). `archive_collection()`/`reactivate_collection()` são idempotentes por desenho: uma segunda chamada no mesmo estado-alvo não realiza novo `UPDATE` e retorna `archived_at`/`updated_at` idênticos à chamada anterior — provado por execução real, não apenas por design.

`delete_collection()` é incondicional para o próprio Owner nesta rodada (2B) — a pré-condição de C-13 (zero Physical Cards associadas) está vacuamente satisfeita porque Collection Allocation ainda não existe. `physical_card` **nunca terá** `collection_id`; a associação é uma entidade própria (`collection_allocation`), e C-13 passou a ser protegida por `collection_allocation.collection_id` (FK `RESTRICT`) mais um pré-check amigável na própria RPC — `delete_collection()` recebeu a revisão obrigatória anunciada aqui no Incremento 2C (Query 5048/5039 v1.3, ver seção "Collection Allocation" a seguir).

**Dois achados reais corrigidos durante a implementação** (nunca detectáveis em `CREATE FUNCTION`, só na primeira execução real): (1) `create_collection()` v1.0 dependia de `game.is_active`, coluna que nunca existiu fisicamente em `public.game` — checagem removida, `game_id` inexistente continua rejeitado via `EXISTS`/FK; (2) `RETURNS TABLE (id UUID, ...)` cria parâmetros OUT que colidem com colunas homônimas da tabela (`id`, e em `archive_collection()`/`reactivate_collection()` também `lifecycle_status`) quando referenciados sem qualificação no `WHERE` de um `UPDATE`/`DELETE` — `ERROR: column reference "id" is ambiguous`, corrigido qualificando todas as ocorrências com `collection.`. Um terceiro achado de segurança (Supabase Advisor): as duas trigger functions nunca tiveram `EXECUTE` revogado de `PUBLIC`/`anon`, ficando chamáveis diretamente via `/rest/v1/rpc/...` fora do contexto de trigger — corrigido com `REVOKE` explícito.

## Modelo Físico — `collection` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.collection (
    id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id                UUID NOT NULL REFERENCES auth.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    game_id                      UUID NOT NULL REFERENCES public.game(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    default_storage_container_id UUID NOT NULL REFERENCES public.storage_container(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    name                         TEXT NOT NULL,
    description                  TEXT NULL,
    mode                         TEXT NOT NULL DEFAULT 'OPEN_CURATION',
    lifecycle_status             TEXT NOT NULL DEFAULT 'ACTIVE',
    visibility                   TEXT NOT NULL DEFAULT 'PRIVATE',
    reference_locked_at          TIMESTAMPTZ NULL,
    archived_at                  TIMESTAMPTZ NULL,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- + 6 CHECKs (mode, lifecycle_status, visibility, name_not_blank,
    --   archived_at_consistency, reference_locked_at_null)
);

CREATE INDEX ix_collection_owner_lifecycle ON public.collection (owner_user_id, lifecycle_status);

ALTER TABLE public.collection ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_select_own ON public.collection FOR SELECT
    USING (owner_user_id = (select auth.uid()));

GRANT SELECT ON public.collection TO authenticated;
```

RLS/grants no mesmo padrão de `inventory`/`storage_container`: única policy é `SELECT` do próprio owner, nenhuma via de escrita direta. Validado ao vivo: Owner B não vê Collection de Owner A; `INSERT`/`UPDATE`/`DELETE` diretos e acesso `anon` negados (permission denied 42501). Arquivo em `database/schema/5030_create_collection_table.sql`.

## Query `5031` — Create Collection `updated_at` Trigger (CONFIRMADO EXECUTADO)

Mantém `updated_at`, reaproveitando `public.set_updated_at()`. Arquivo em `database/schema/5031_create_collection_updated_at_trigger.sql`.

## Query `5032` — Create Collection Structural Identity Trigger (CONFIRMADO EXECUTADO)

Trigger `BEFORE UPDATE` bloqueando alteração de `owner_user_id`/`game_id`. Validado ao vivo: as duas tentativas rejeitadas com a mensagem exata esperada. `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated` (correção de segurança — trigger functions não precisam de `EXECUTE` concedido a nenhuma role para disparar). Estendida no Incremento 2C (Query 5044, v1.2) com a proteção de `started_at` — ver seção "Collection Allocation" a seguir. Arquivo em `database/schema/5032_create_collection_structural_identity_trigger.sql`.

## Query `5033` — Create Collection Default Storage Owner Trigger (CONFIRMADO EXECUTADO)

Trigger `BEFORE INSERT OR UPDATE OF default_storage_container_id`, join até `inventory` para confirmar que o Storage pertence ao mesmo Owner. Validado ao vivo: Owner A + Storage de Owner B rejeitado. `EXECUTE` revogado, mesma correção de segurança de `5032`. Arquivo em `database/schema/5033_create_collection_default_storage_owner_trigger.sql`.

## Query `5034` — Create `create_collection()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER`, `SET search_path = ''`, parâmetros `(p_game_id, p_name, p_description, p_default_storage_container_id)` — `owner_user_id`/`mode`/`lifecycle_status`/`visibility` nunca aceitos como parâmetro. Retorno explícito `(id, name, mode, lifecycle_status, visibility, default_storage_container_id, created_at)`. v1.1 remove a checagem de `game.is_active` (coluna inexistente — ver "Decisão de Modelagem" acima). Validado ao vivo: criação com valores iniciais corretos; Storage de outro Owner rejeitado; Game inexistente rejeitado (`'game not found'`); nome vazio rejeitado; chamada sem autenticação rejeitada. Arquivo em `database/schema/5034_create_create_collection_function.sql`.

## Query `5035` — Create `update_collection_metadata()` (CONFIRMADO EXECUTADO, v1.2)

Function `SECURITY DEFINER`, edita `name`/`description`. `UPDATE` atômico com guard `lifecycle_status = 'ACTIVE'` no próprio `WHERE` (ver "Decisão de Modelagem"). Validado ao vivo: ACTIVE aceita a edição; ARCHIVED rejeitado (`'collection is archived — reactivate before editing metadata'`), sem alterar `updated_at`. Arquivo em `database/schema/5035_create_update_collection_metadata_function.sql`.

## Query `5036` — Create `set_collection_default_storage()` (CONFIRMADO EXECUTADO, v1.2)

Function `SECURITY DEFINER`, única via de escrita de `default_storage_container_id` (obrigatório — não existe "limpar" Default Storage). Mesmo padrão atômico de `5035`. Validado ao vivo: ACTIVE aceita a troca; Storage de outro Owner rejeitado; ARCHIVED rejeitado. Arquivo em `database/schema/5036_create_set_collection_default_storage_function.sql`.

## Query `5037` — Create `archive_collection()` (CONFIRMADO EXECUTADO, v1.2)

Function `SECURITY DEFINER`, transição `ACTIVE -> ARCHIVED`, idempotente. `UPDATE` atômico com guard `lifecycle_status = 'ACTIVE'` no `WHERE`; zero linhas afetadas cai em leitura diagnóstica *read-only* que distingue "não existe/não é minha" de "já ARCHIVED" (retorna estado atual, sem novo `UPDATE`). Validado ao vivo: chamada real captura `archived_at`/`updated_at`; chamada repetida retorna os **mesmos valores exatos**, comprovando que nenhuma segunda escrita ocorreu. Arquivo em `database/schema/5037_create_archive_collection_function.sql`.

## Query `5038` — Create `reactivate_collection()` (CONFIRMADO EXECUTADO, v1.2)

Espelho exato de `5037` para `ARCHIVED -> ACTIVE`. Validado ao vivo com a mesma rigidez: `updated_at` idêntico entre a chamada real e a idempotente. Arquivo em `database/schema/5038_create_reactivate_collection_function.sql`.

## Query `5039` — Create `delete_collection()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER`, `DELETE` físico Owner-only, incondicional nesta rodada — v1.1 descrita aqui é o estado no momento do 2B; recebeu a guarda real de C-13 no Incremento 2C (v1.3, ver seção "Collection Allocation" a seguir). Validado ao vivo (2B): Owner B não consegue deletar Collection de Owner A; id inexistente rejeitado; Owner A deleta a própria com sucesso, remoção física confirmada. Arquivo em `database/schema/5039_create_delete_collection_function.sql`.

## Performance (volume de 20.000 Collections)

Quatro workloads medidos com `EXPLAIN (ANALYZE, BUFFERS)` sobre 20.000 Collections sintéticas (80% ACTIVE/20% ARCHIVED) do mesmo Owner: listagem sem filtro de status (Bitmap Scan via `ix_collection_owner_lifecycle`, 8,5ms), listagem ACTIVE (Index Scan, 11,2ms), listagem ARCHIVED (Index Scan mesmo com seletividade baixa, 5,0ms), abertura por PK (Index Scan, 0,03ms) — todos usando o índice pretendido, nenhuma alegação de performance para volumes maiores. Ver `database/validations/5805_performance_checks_collections_physical_increment_02b.sql`.

## Sequência

```text
5030 - Create Collection table                              (CONFIRMADO EXECUTADO — database/schema/5030_create_collection_table.sql)
5031 - Create Collection updated_at trigger                  (CONFIRMADO EXECUTADO — database/schema/5031_create_collection_updated_at_trigger.sql)
5032 - Create Collection Structural Identity trigger          (CONFIRMADO EXECUTADO — database/schema/5032_create_collection_structural_identity_trigger.sql)
5033 - Create Collection Default Storage Owner trigger         (CONFIRMADO EXECUTADO — database/schema/5033_create_collection_default_storage_owner_trigger.sql)
5034 - Create create_collection() function (v1.1)              (CONFIRMADO EXECUTADO — database/schema/5034_create_create_collection_function.sql)
5035 - Create update_collection_metadata() function (v1.2)      (CONFIRMADO EXECUTADO — database/schema/5035_create_update_collection_metadata_function.sql)
5036 - Create set_collection_default_storage() function (v1.2)  (CONFIRMADO EXECUTADO — database/schema/5036_create_set_collection_default_storage_function.sql)
5037 - Create archive_collection() function (v1.2)              (CONFIRMADO EXECUTADO — database/schema/5037_create_archive_collection_function.sql)
5038 - Create reactivate_collection() function (v1.2)           (CONFIRMADO EXECUTADO — database/schema/5038_create_reactivate_collection_function.sql)
5039 - Create delete_collection() function (v1.1)               (CONFIRMADO EXECUTADO — database/schema/5039_create_delete_collection_function.sql)
5804 - Validate Collections Physical Increment 02B              (EXECUTADA — database/validations/5804_validate_collections_physical_increment_02b.sql)
5805 - Performance Checks Collections Physical Increment 02B    (EXECUTADA — database/validations/5805_performance_checks_collections_physical_increment_02b.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída nesta rodada — fundação exclusivamente de banco. `completion_policy`, Collection Reference, `set_collection_visibility()`/Public Access, `created_by_user_id`/`updated_by_user_id` permanecem fora, sem nenhum campo/tabela criado para eles. `started_at` materializado desde o Incremento 2C — ver seção própria a seguir. Collection Reference permanece deferida a um incremento posterior, sem bloquear os anteriores.

---

# Collection Allocation

## Status

**Física CONFIRMADO EXECUTADO em 2026-09-02** (`COLLECTIONS-PHYSICAL-INCREMENT-02C-IMPLEMENTATION-01`, Incremento 2C, dentro do milhar `5000`–`5999`, Módulo Collections). Precedida por duas rodadas de modelagem física sem alteração de banco (`-MODELING-01`, `-REVISION-01`) e três rodadas de staging auditado em `database/proposals/2026-09-01-02c-allocation/` (`-STAGING-REVISION-01` — hardenings de não-enumeração e privilégio; `-STAGING-FINAL-01` — script de performance efetivamente executável; `-STAGING-FINAL-FIX-01` — grants de TEMP TABLE, correção de contagem, nota de planner) antes da aplicação real. Nove Queries estruturais (`5040`–`5048`), uma bateria de validação funcional (49 casos, 0 falhas — cobrindo A–Z) e um plano de performance real sob volume de ~21.000 Collection Allocations — todos executados e confirmados ao vivo na mesma rodada. Modelagem lógica/conceitual canônica em `domain-modeling/collections/concept-decisions.md` (C-04/C-05/C-13/C-37/C-141) e `logical-model.md` (LDM-07/LDM-11/LDM-12/LDM-23) — nenhuma das duas foi reaberta nesta rodada.

Cumpre a revisão obrigatória anunciada na seção "Collection" acima: `delete_collection()` (Query 5039, agora v1.3 via extensão 5048) ganhou a guarda real de C-13.

## Decisão de Modelagem

`collection_allocation` associa uma Physical Card a uma Collection (C-04) — entidade própria, nunca uma coluna em `physical_card` (decisão fixada desde `COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-FINAL-01`, item 7, não reaberta). `physical_card_id UNIQUE` garante estruturalmente Physical Card 0..1 Collection corrente, sem depender de nenhuma RPC. Integridade Owner × Inventory × Game (C-05, C-141) é garantida por trigger dedicado (`validate_collection_allocation_integrity()`, Query 5042) — três checagens sequenciais (Physical Card sem Inventory corrente / Owner incompatível / Game incompatível), cada uma set-based sobre a transition table do statement inteiro, não por CHECK declarativo (CHECK não faz JOIN).

`collection.started_at` (LDM-11) passa a existir fisicamente nesta rodada — nulável, imutável após definido, nunca escrito por RPC: materializado por trigger dedicado (`materialize_collection_started_at()`, Query 5045) a partir do fato físico real (`MIN(collection_allocation.created_at)`), e reconfirmado independentemente por uma segunda camada de defesa na trigger de identidade estrutural (`validate_collection_structural_identity()`, Query 5032, estendida v1.2 via 5044) — dupla camada, não uma dependendo silenciosamente da outra. Deallocate total (Collection volta a zero Allocations) nunca reseta `started_at` — é fato histórico, não reflexo do estado de composição atual.

`allocate_physical_cards_to_collection()`/`deallocate_physical_cards_from_collection()` (Queries 5046/5047) são a única via de escrita em `collection_allocation` para `authenticated` — bulk-first (1–500 por chamada, dedup via `array_agg(DISTINCT ...)`), Owner-only, fail-closed (qualquer item inválido do lote aborta o lote inteiro, zero inserções/remoções parciais). Não-enumeração: ambas incorporam `owner_user_id = auth.uid()` diretamente no `WHERE` da `SELECT ... FOR UPDATE`, de forma que Collection inexistente e Collection de outro Owner produzem exatamente a mesma mensagem genérica — nenhuma distinção observável. `delete_collection()` segue o mesmo padrão: ownership confirmado via `PERFORM ... FOR UPDATE` antes de qualquer pré-check de C-13, para que uma Collection alheia (com ou sem Allocations) nunca vaze essa distinção.

C-37 (ARCHIVED não aceita mudança de composição) e C-13 (exclusão só com zero Allocations) têm garantia estrutural declarativa independente de qualquer RPC: `collection_allocation.collection_id` é FK `ON DELETE RESTRICT` para `collection`, então mesmo um `DELETE` direto bypassando `delete_collection()` falha pela FK. O pré-check da RPC é só conveniência de UX (mensagem de domínio em vez do erro cru de FK).

## Modelo Físico — `collection_allocation` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.collection_allocation (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    physical_card_id UUID NOT NULL UNIQUE REFERENCES public.physical_card(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    collection_id    UUID NOT NULL REFERENCES public.collection(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_collection_allocation_collection ON public.collection_allocation (collection_id);

ALTER TABLE public.collection_allocation ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_allocation_select_own ON public.collection_allocation FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.collection c WHERE c.id = collection_allocation.collection_id AND c.owner_user_id = (select auth.uid())));

GRANT SELECT ON public.collection_allocation TO authenticated;
```

RLS/grants no mesmo padrão do restante do domínio: única policy é `SELECT` do próprio Owner (via join até `collection`, porque esta tabela não tem `owner_user_id` próprio), nenhuma via de escrita direta — toda escrita passa pelas RPCs 5046/5047. Validado ao vivo (5806): `anon` sem nenhum grant; `authenticated` só com `SELECT`; Owner B não vê Allocations de Owner A. Arquivo em `database/schema/5040_create_collection_allocation_table.sql`.

## Query `5041` — Create Collection Allocation `updated_at` Trigger (CONFIRMADO EXECUTADO)

Mesmo padrão de `set_updated_at()`. Arquivo em `database/schema/5041_create_collection_allocation_updated_at_trigger.sql`.

## Query `5042` — Create Collection Allocation Integrity Trigger (CONFIRMADO EXECUTADO, v1.1)

`validate_collection_allocation_integrity()`, `AFTER INSERT`/`AFTER UPDATE ... FOR EACH STATEMENT` com transition table — três checagens sequenciais (Inventory corrente / Owner / Game), cada uma capaz de disparar isoladamente mesmo em bypass direto da RPC. Validado ao vivo (5806, Casos I/J/K): Physical Card sem Inventory rejeitada; Physical Card de outro Owner rejeitada; Physical Card de Game diferente rejeitada — as três via `INSERT` direto em `collection_allocation`, não via RPC. `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`. Arquivo em `database/schema/5042_create_collection_allocation_integrity_trigger.sql`.

## Query `5043` — Alter Collection: Add `started_at` (CONFIRMADO EXECUTADO)

`ALTER TABLE public.collection ADD COLUMN started_at TIMESTAMPTZ NULL` + CHECK `started_at IS NULL OR started_at >= created_at`. Arquivo em `database/schema/5043_alter_collection_add_started_at.sql`.

## Query `5044`/`5032` v1.2 — Extensão da Collection Structural Identity Trigger (CONFIRMADO EXECUTADO)

Estende `validate_collection_structural_identity()` (já canônica desde 5032/Incremento 2B) com a proteção de `started_at`: já definido, qualquer tentativa de mudar (inclusive reset para `NULL`) é rejeitada; ainda `NULL`, só aceita o valor exato de `MIN(collection_allocation.created_at)`. Validado ao vivo (5806, Casos A/G): `UPDATE` direto sem nenhuma Allocation rejeitado; `UPDATE` após já definido rejeitado nas duas direções (mudar valor, resetar a `NULL`). Conteúdo incorporado ao arquivo canônico `database/schema/5032_create_collection_structural_identity_trigger.sql` (v1.2), não um arquivo `5044` isolado — mesmo padrão de correção-em-linha já usado no domínio.

## Query `5045` — Create Collection `started_at` From First Allocation Trigger (CONFIRMADO EXECUTADO)

`materialize_collection_started_at()`, `AFTER INSERT ... FOR EACH STATEMENT`, `started_at = MIN(collection_allocation.created_at)` do lote, só quando ainda `NULL`. Validado ao vivo (5806, Casos B–F): primeiro `allocate()` preenche `started_at`; segundo `allocate()` na mesma Collection não altera; `deallocate()` parcial e total preservam o valor. `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`. Arquivo em `database/schema/5045_create_collection_started_at_from_allocation_trigger.sql`.

## Query `5046` — Create `allocate_physical_cards_to_collection()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER`, `SET search_path = ''`, `RETURNS TABLE (physical_card_id, collection_id, created_at)`. Nunca referencia `started_at` no corpo (auditado textualmente, Caso Q). Validado ao vivo: primeiro allocate materializa `started_at`; Game incompatível rejeitado; Collection ARCHIVED rejeitada; bulk fail-closed (1 de N já alocada aborta o lote inteiro); teto de 500 avaliado antes da dedup; dedup de ids repetidos resulta em 1 linha; não-enumeração contra Collection alheia (vazia/com Allocations/inexistente) — mesma mensagem nos três casos. Arquivo em `database/schema/5046_create_allocate_physical_cards_to_collection_function.sql`.

## Query `5047` — Create `deallocate_physical_cards_from_collection()` (CONFIRMADO EXECUTADO, v1.1)

Espelho exato de 5046 para `DELETE`. Nunca toca `started_at`, mesmo esvaziando a Collection por completo. Validado ao vivo: bulk fail-closed; Collection ARCHIVED rejeitada; não-enumeração contra Collection alheia. Arquivo em `database/schema/5047_create_deallocate_physical_cards_from_collection_function.sql`.

## Query `5048`/`5039` v1.3 — Extensão do `delete_collection()` (CONFIRMADO EXECUTADO)

Cumpre a revisão obrigatória anunciada na seção "Collection": pré-check de C-13 (`EXISTS` em `collection_allocation`) antes do `DELETE`, ownership confirmado primeiro via `PERFORM ... FOR UPDATE` para não vazar existência/composição de Collection alheia. Mensagem deliberadamente não sugere `archive_collection()` como alternativa (ARCHIVED preserva Allocations — arquivar não desbloqueia a exclusão). Validado ao vivo (5806, Casos R/S/T/Z): exclusão com Allocation rejeitada; após `deallocate` total, exclusão bem-sucedida; `DELETE` direto bypassando a RPC falha pela FK `RESTRICT`; não-enumeração — Owner B nunca recebe a mensagem de C-13 sobre Collection alheia. Conteúdo incorporado ao arquivo canônico `database/schema/5039_create_delete_collection_function.sql` (v1.3).

## Validação Funcional (5806 — 49 casos, 0 falhas)

Bateria completa executada ao vivo com fixtures reversíveis (`BEGIN`/`ROLLBACK`, zero resíduo confirmado): Casos A–H (mecanismo `started_at`), I–K (integridade estrutural via bypass direto), L–M (ARCHIVED bloqueia allocate/deallocate), N (RLS cross-user), O–P (bulk fail-closed), Q (auditoria textual), R–T (semântica de delete), U–V (limite/dedup), W (sem overload), X–Z (prova de não-enumeração nas três RPCs). Nenhuma falha em nenhum caso.

## Performance (volume real de ~21.000 Collection Allocations)

Cinco workloads medidos com `EXPLAIN (ANALYZE, BUFFERS)` sobre dados sintéticos reversíveis (21.601 Physical Cards, 24 Collections, ~21.000 Allocations distribuídas): listar Allocations de 1 Collection (5.000 linhas, ~24% do total) — Bitmap Heap Scan via `ix_collection_allocation_collection`, 1,9ms, 65 buffer hits; mesma consulta contra Collection filler (750 linhas) — 0,6ms, 177 buffer hits; localizar Allocation por `physical_card_id` — Index Scan via índice único, 0,07ms, 6 buffer hits; `allocate()` de 500 numa Collection sem `started_at` — 50,0ms; `allocate()` de 500 numa Collection já com `started_at` — 43,8ms (diferença não significativa — dominada pelo custo comum de validação/INSERT, não pela materialização de `started_at`); `deallocate()` de 500 — 2,2ms. Índices dedicados usados em todas as leituras; nenhum Seq Scan observado.

## Segurança (Security Advisor)

Duas novas ocorrências de `authenticated_security_definer_function_executable` (WARN) — `allocate_physical_cards_to_collection()`/`deallocate_physical_cards_from_collection()` — da mesma categoria intencional já aceita para toda RPC Owner-scoped do domínio (`create_collection`, `delete_collection`, `set_physical_cards_storage`, etc., desde os incrementos anteriores): `SECURITY DEFINER` + `EXECUTE` restrito a `authenticated` é o desenho, não um achado a corrigir. Nenhum finding novo fora dessa categoria atribuível a este incremento.

## Sequência

```text
5040 - Create Collection Allocation table                        (CONFIRMADO EXECUTADO — database/schema/5040_create_collection_allocation_table.sql)
5041 - Create Collection Allocation updated_at trigger            (CONFIRMADO EXECUTADO — database/schema/5041_create_collection_allocation_updated_at_trigger.sql)
5042 - Create Collection Allocation Integrity trigger (v1.1)      (CONFIRMADO EXECUTADO — database/schema/5042_create_collection_allocation_integrity_trigger.sql)
5043 - Alter Collection: add started_at                          (CONFIRMADO EXECUTADO — database/schema/5043_alter_collection_add_started_at.sql)
5044 - Extensão da Structural Identity trigger (dobra em 5032 v1.2) (CONFIRMADO EXECUTADO — database/schema/5032_create_collection_structural_identity_trigger.sql)
5045 - Create started_at From First Allocation trigger            (CONFIRMADO EXECUTADO — database/schema/5045_create_collection_started_at_from_allocation_trigger.sql)
5046 - Create allocate_physical_cards_to_collection() (v1.1)      (CONFIRMADO EXECUTADO — database/schema/5046_create_allocate_physical_cards_to_collection_function.sql)
5047 - Create deallocate_physical_cards_from_collection() (v1.1)  (CONFIRMADO EXECUTADO — database/schema/5047_create_deallocate_physical_cards_from_collection_function.sql)
5048 - Extensão do delete_collection() (dobra em 5039 v1.3)       (CONFIRMADO EXECUTADO — database/schema/5039_create_delete_collection_function.sql)
5806 - Validate Collections Physical Increment 02C (49 casos)     (EXECUTADA — database/proposals/2026-09-01-02c-allocation/5806_validate_collections_physical_increment_02c.sql)
5807 - Performance Checks Collections Physical Increment 02C      (EXECUTADA — database/proposals/2026-09-01-02c-allocation/5807_performance_checks_collections_physical_increment_02c.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída nesta rodada — fundação exclusivamente de banco. Collection Reference, `reference_locked_at` (ainda travado em `NULL`), `completion_policy`, `set_collection_visibility()`/Public Access permanecem fora, sem nenhum campo/tabela criado para eles. Layout/Slot/Placement, Custody & Availability, Lifecycle/Provenance, Favorite, Wishlist, Condition, Grading/Certification, Collaboration/Permissions e Activity History/Audit seguem sem modelo físico.

---

# Collection Reference / Card Set Reference

## Status

**Física CONFIRMADO EXECUTADO em 2026-09-02** (`COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01`, Incremento 02D, dentro do milhar `5000`–`5999`, Módulo Collections). Precedida por duas rodadas de modelagem física sem alteração de banco (`-MODELING-01`, `-REVISION-01`, `-FINAL-01`) e duas rodadas de staging auditado em `database/proposals/2026-09-02-02d-reference/` (`-STAGING-REVISION-01` — fechou o blocker de Reference-after-lock; `-STAGING-FINAL-FIX-01` — três correções pontuais de fixture) antes da aplicação real. Dezoito Queries estruturais (`5049`–`5066`), uma bateria de validação funcional de 25 casos (A–Z, 0 falhas) e um plano de performance real sob workloads de 200–500 operações — todos executados e confirmados ao vivo na mesma rodada. Modelagem lógica/conceitual canônica em `domain-modeling/collections/concept-decisions.md` (C-05/C-18/C-22/C-32/C-37/C-141) e `logical-model.md` (LDM-04/LDM-06/LDM-07/LDM-13–LDM-17) — nenhuma das duas foi reaberta nesta rodada.

Libera `mode = 'REFERENCE_BASED'` fisicamente pela primeira vez (Query 5060) — desde o Incremento 2B, `collection.mode` era fisicamente só `'OPEN_CURATION'`, um hardening temporário que já anunciava a própria condição de revisão ("alargável quando Collection Reference existir").

## Decisão de Modelagem

Collection agora tem dois modos operacionais reais: `OPEN_CURATION` (curadoria livre, sem Reference — comportamento inalterado desde o 2B) e `REFERENCE_BASED` (a Collection é definida por uma referência canônica externa — nesta rodada, um Card Set completo). `mode` passa a ser estruturalmente imutável após a criação (extensão da Query 5032 via 5061) — não existe conversão de uma Collection já criada entre os dois modos no V1 (decisão fechada em `-MODELING-FINAL-01`, item 1); trocar de modo exige criar uma nova Collection.

`collection_reference` (Query 5049) é o supertipo da hierarquia (LDM-06/LDM-13) — entidade própria, não uma coluna solta em `collection`, rejeitando deliberadamente um desenho polimórfico solto (`reference_type`/`reference_id` sem FK forte). `collection_id UNIQUE` estrutura fisicamente a cardinalidade 0..1 por Collection; `reference_kind` é um discriminador explícito, fisicamente só `'CARD_SET'` nesta etapa (mesmo padrão incremental de `chk_collection_mode`, alargável por `DROP`+`ADD CONSTRAINT` quando um segundo subtipo existir). `collection_card_set_reference` (Query 5052) é o primeiro subtipo físico — `collection_reference_id` é PK=FK (padrão clássico de subtipo 1:1, nunca um id próprio duplicando identidade), `card_set_id` é FK forte para `public.card_set`, sem duplicar nenhum metadado do Card Set. `card_set_id` **não** é `UNIQUE`: o mesmo Card Set pode ser referenciado por Collections diferentes, inclusive do mesmo Owner (C-32).

CASCADE composicional: `collection_reference.collection_id` e `collection_card_set_reference.collection_reference_id` usam `ON DELETE CASCADE` (não `RESTRICT`) — nenhuma das duas linhas tem existência independente da Collection que a contém (decisão fechada em `-MODELING-REVISION-01`, item 4); excluir a Collection leva consigo sua Reference e seu subtipo, sem exigir um passo extra em `delete_collection()`. `card_set_id` em si continua `ON DELETE RESTRICT` — excluir uma Collection nunca pode cascatear até excluir catálogo.

Duas garantias transacionais cruzam tabelas e por isso não podem ser CHECK/FK declarativa — modeladas como `CREATE CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` (avaliam só no COMMIT, não a cada `INSERT` isolado, permitindo que `create_reference_based_card_set_collection()` insira as três linhas — `collection`, `collection_reference`, `collection_card_set_reference` — na mesma transação sem falhar num estado intermediário incompleto): (1) `mode` ↔ presença de Reference (Queries 5057/5059 — `REFERENCE_BASED` sempre com exatamente 1 `collection_reference`, `OPEN_CURATION` sempre com 0); (2) supertipo ↔ subtipo (Queries 5057/5058, função auxiliar compartilhada `check_collection_reference_subtype_consistency()` — `reference_kind = 'CARD_SET'` sempre com exatamente 1 `collection_card_set_reference`, reagindo tanto a eventos no supertipo quanto no subtipo, cobrindo inclusive um `DELETE`/`UPDATE` direto só no subtipo).

Integridade de Game (C-05) — `card_set_id` deve pertencer ao mesmo `game_id` da Collection — é garantida por trigger imediato (Query 5055, `BEFORE INSERT OR UPDATE`), disparado tanto na criação quanto na troca de `card_set_id`; não é FK composta possível (`card_set` não tem `game_id` direto, só via `card_set.expansion_id -> expansion.game_id`, mesma limitação já enfrentada por `collection`×`storage_container` em 5033).

`reference_locked_at` (existente fisicamente em `collection` desde o Incremento 2C, mas travado em `NULL` por CHECK até esta rodada) é liberado pela Query 5060 e passa a ser materializado pela mesma trigger que já materializa `started_at` (extensão de 5045 via 5062): na primeira `collection_allocation` de uma Collection `REFERENCE_BASED`, `reference_locked_at` recebe o mesmo `MIN(created_at)` — na prática, os dois marcos coincidem no mesmo evento, porque a Reference já existe desde antes de qualquer Allocation ser possível (ver invariante seguinte). Imutável após definido, nunca `NOW()` arbitrário, reconfirmado contra a fonte de verdade real a cada `UPDATE` de `collection` (extensão de 5032 via 5061) — mesma dupla camada de defesa já usada para `started_at` desde o 2C.

**Invariante Reference-antes-da-primeira-Allocation** (LDM-07/C-18): uma Collection Reference precisa existir *antes* da primeira Allocation, não apenas coexistir com ela no estado final — uma regra sobre a *ordem* dos eventos, que nenhum trigger diferido consegue enxergar sozinho (só vê o snapshot no COMMIT). Fechada com checagem **imediata** (não diferida) no momento do `INSERT` de `collection_reference`/`collection_card_set_reference`: se `reference_locked_at` já está definido, o `INSERT` falha (Queries 5056/5055, blocker fechado em `-STAGING-REVISION-01`, item 1, antes da aplicação real). Sob o fluxo normal do V1 (só `create_reference_based_card_set_collection()`, que sempre cria uma Collection nova, `ACTIVE` por definição) este guard nunca deveria disparar em produção — existe como enforcement estrutural independente de qualquer comportamento de RPC.

**Elegibilidade de Reference** (LDM-17): quando a Collection é `REFERENCE_BASED`/`CARD_SET`, toda Physical Card alocada deve ter Card pertencente ao `card_set_id` referenciado. Dupla camada: pré-validação amigável em `allocate_physical_cards_to_collection()` (extensão de 5046 via 5064) e garantia estrutural independente de RPC na trigger de integridade de Allocation (extensão de 5042 via 5063, quarta checagem sequencial, depois de Inventory-nulo/Owner/Game). Fail-closed preservado — um único `physical_card_id` inelegível reprova o lote inteiro.

Duas RPCs novas, ambas `SECURITY DEFINER`, `EXECUTE` restrito a `authenticated`: `create_reference_based_card_set_collection()` (Query 5065) — única via de criação de uma Collection `REFERENCE_BASED`/`CARD_SET`, espelha toda validação de `create_collection()` (5034) e adiciona a criação atômica das três linhas na mesma transação; `create_collection()` permanece exclusiva para `OPEN_CURATION`, sem alteração. `set_collection_card_set_reference()` (Query 5066) — única via de troca de `card_set_id` antes do lock, com os mesmos early checks amigáveis (mode/lifecycle/lock) espelhando a garantia estrutural real de 5055; não misturada com `update_collection_metadata()` (decisão fechada em `-MODELING-FINAL-01`, item 7).

`completion_policy` (LDM-08) permanece deferida — semanticamente vazia sem Collection Reference até esta rodada, mas nenhum campo foi adicionado aqui; fica para um incremento posterior (02E), quando a semântica de "coleção completa" (percentual do Card Set possuído) puder ser definida sobre uma Reference que já existe fisicamente.

## Modelo Físico — `collection_reference` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.collection_reference (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id  UUID NOT NULL UNIQUE
                      REFERENCES public.collection(id)
                      ON UPDATE RESTRICT ON DELETE CASCADE,
    reference_kind TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- + CHECK chk_collection_reference_kind (fisicamente só 'CARD_SET')
);
```

RLS: `SELECT` via join até `collection.owner_user_id` — mesmo padrão de `collection_allocation` (5040), já que esta tabela não tem `owner_user_id` próprio. Nenhuma policy de escrita para `authenticated`; toda escrita passa pelas RPCs 5065/5066 ou pelos triggers estruturais desta rodada. Arquivo em `database/schema/5049_create_collection_reference_table.sql`.

## Query `5050` — Create Collection Reference `updated_at` Trigger (CONFIRMADO EXECUTADO)

Mesmo padrão de `set_updated_at()`. Arquivo em `database/schema/5050_create_collection_reference_updated_at_trigger.sql`.

## Query `5051` — Create Collection Reference Structural Identity Trigger (CONFIRMADO EXECUTADO)

Trigger `BEFORE UPDATE` (imediata, não diferida) bloqueando alteração de `collection_id` (reparenting nunca é operação válida) e `reference_kind` (CARD_SET nunca vira outro kind). Arquivo em `database/schema/5051_create_collection_reference_structural_identity_trigger.sql`.

## Modelo Físico — `collection_card_set_reference` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.collection_card_set_reference (
    collection_reference_id UUID PRIMARY KEY
                                REFERENCES public.collection_reference(id)
                                ON UPDATE RESTRICT ON DELETE CASCADE,
    card_set_id               UUID NOT NULL
                                REFERENCES public.card_set(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Nenhum índice adicional em `card_set_id` nesta rodada — nenhum padrão de acesso "todas as Collections que referenciam este Card Set" identificado nos workloads pedidos; a PK (`collection_reference_id`) já cobre o único padrão de leitura conhecido (Collection → Reference → subtipo). RLS: mesmo padrão de `collection_reference`, `SELECT` via join duplo até `collection.owner_user_id`. Arquivo em `database/schema/5052_create_collection_card_set_reference_table.sql`.

## Query `5053` — Create Collection Card Set Reference `updated_at` Trigger (CONFIRMADO EXECUTADO)

Arquivo em `database/schema/5053_create_collection_card_set_reference_updated_at_trigger.sql`.

## Query `5054` — Create Collection Card Set Reference Structural Identity Trigger (CONFIRMADO EXECUTADO)

Trigger `BEFORE UPDATE` bloqueando alteração de `collection_reference_id` (a PK, fechando explicitamente uma lacuna que o Postgres não recusa por si só). Arquivo em `database/schema/5054_create_collection_card_set_reference_structural_identity_trigger.sql`.

## Query `5055` — Create Collection Card Set Reference Game and Lock Guard Trigger (CONFIRMADO EXECUTADO, v1.1)

`validate_collection_card_set_reference_game_and_lock()`, `BEFORE INSERT OR UPDATE`, imediata. Duas garantias: integridade de Game (checagem em INSERT e UPDATE) e lock/lifecycle guard sobre `card_set_id` (só aceita troca com `reference_locked_at IS NULL` e `lifecycle_status = 'ACTIVE'`). v1.1 (endurecida antes da aplicação real, em `-STAGING-REVISION-01`) fecha o blocker Reference-after-lock também no INSERT do subtipo, espelhando 5056. Arquivo em `database/schema/5055_create_collection_card_set_reference_game_and_lock_trigger.sql`.

## Query `5056` — Create Collection Reference Lifecycle Guard Trigger (CONFIRMADO EXECUTADO, v1.1)

`validate_collection_reference_lifecycle_guard()`, `BEFORE INSERT OR DELETE`, imediata. Impede criar/remover uma Collection Reference enquanto a Collection não está `ACTIVE` (C-37); v1.1 fecha o mesmo blocker Reference-after-lock do lado do supertipo — no `INSERT`, se `reference_locked_at` já está definido, `FAIL`. `DELETE` em cascata (a própria Collection sendo excluída) continua funcionando, via o mesmo padrão "a linha pai ainda existe?" usado em todo o domínio. Arquivo em `database/schema/5056_create_collection_reference_lifecycle_guard_trigger.sql`.

## Query `5057` — Create Collection Reference Consistency Trigger (CONFIRMADO EXECUTADO)

`CREATE CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`, dupla garantia diferida: `mode` ↔ presença de Reference, e supertipo ↔ subtipo (via a função auxiliar `check_collection_reference_subtype_consistency()`, reaproveitada pela Query 5058). Arquivo em `database/schema/5057_create_collection_reference_consistency_trigger.sql`.

## Query `5058` — Create Collection Card Set Reference Consistency Trigger (CONFIRMADO EXECUTADO)

Segundo lado do enforcement diferido de supertipo/subtipo, reagindo a eventos no subtipo (não no supertipo) — cobre `DELETE`/`UPDATE` direto em `collection_card_set_reference` que 5057 sozinha não detectaria. Arquivo em `database/schema/5058_create_collection_card_set_reference_consistency_trigger.sql`.

## Query `5059` — Create Collection Reference Presence Trigger (CONFIRMADO EXECUTADO)

Fecha a outra metade do enforcement `mode` ↔ Reference — o lado de `collection`: sem esta trigger, `INSERT INTO collection (mode = 'REFERENCE_BASED')` sem nunca inserir `collection_reference` na mesma transação nunca dispararia nenhum evento sobre a tabela vazia, e o COMMIT passaria silenciosamente. `AFTER INSERT` apenas (mode é imutável — 5061). Arquivo em `database/schema/5059_create_collection_reference_presence_trigger.sql`.

## Query `5060` — Alter Collection: Widen `mode` and Unlock `reference_locked_at` (CONFIRMADO EXECUTADO)

`chk_collection_mode` ampliada para incluir `'REFERENCE_BASED'`; `chk_collection_reference_locked_at_null` (travava o campo em `NULL` desde o 2B) removida. Aplicada na mesma transação em que 5049–5059 já haviam sido aplicadas antes — nenhuma janela onde `mode` aceita `REFERENCE_BASED` sem o enforcement completo já existir. Arquivo em `database/schema/5060_alter_collection_widen_mode_and_unlock_reference.sql`.

## Query `5061`/`5032` v1.3 — Extensão da Collection Structural Identity Trigger (CONFIRMADO EXECUTADO)

Estende `validate_collection_structural_identity()` (já canônica desde 5032/Incremento 2B, estendida uma vez em 5044/2C) com `mode` imutável e `reference_locked_at` (mesmo padrão de `started_at`, mais o barramento explícito por `mode` — só `REFERENCE_BASED` tem esse campo aplicável). Conteúdo incorporado ao arquivo canônico `database/schema/5032_create_collection_structural_identity_trigger.sql` (v1.3), não um arquivo `5061` isolado.

## Query `5062`/`5045` v1.1 — Extensão da Collection `started_at`/`reference_locked_at` Materializer Trigger (CONFIRMADO EXECUTADO)

Estende `materialize_collection_started_at()` (já canônica desde 5045/Incremento 2C) com o ramo de `reference_locked_at`, preservando `started_at` sem nenhuma mudança de comportamento. Conteúdo incorporado ao arquivo canônico `database/schema/5045_create_collection_started_at_from_allocation_trigger.sql` (v1.1).

## Query `5063`/`5042` v1.2 — Extensão da Collection Allocation Integrity Trigger (CONFIRMADO EXECUTADO)

Estende `validate_collection_allocation_integrity()` (já canônica desde 5042/Incremento 2C) com a quarta checagem — Elegibilidade de Reference. Conteúdo incorporado ao arquivo canônico `database/schema/5042_create_collection_allocation_integrity_trigger.sql` (v1.2).

## Query `5064`/`5046` v1.2 — Extensão do `allocate_physical_cards_to_collection()` (CONFIRMADO EXECUTADO)

Estende a função (já canônica desde 5046/Incremento 2C) com pré-validação amigável de Elegibilidade de Reference, simétrica à Query 5063. Nenhuma mudança de assinatura, contrato de retorno, teto de 500, deduplicação ou lock de concorrência já existentes. Conteúdo incorporado ao arquivo canônico `database/schema/5046_create_allocate_physical_cards_to_collection_function.sql` (v1.2).

## Query `5065` — Create `create_reference_based_card_set_collection()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, parâmetros `(p_game_id, p_name, p_description, p_default_storage_container_id, p_card_set_id)` — `owner_user_id`/`mode` nunca aceitos como parâmetro (`mode` sempre `'REFERENCE_BASED'`). Espelha `create_collection()` em toda validação já existente e adiciona a criação atômica de `collection` → `collection_reference` → `collection_card_set_reference` na mesma transação. Arquivo em `database/schema/5065_create_reference_based_card_set_collection_function.sql`.

## Query `5066` — Create `set_collection_card_set_reference()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, parâmetros `(p_collection_id, p_card_set_id)` — única via de troca de `card_set_id` antes do lock. `SELECT ... FOR UPDATE` com `owner_user_id = auth.uid()` no próprio `WHERE` (não-enumeração, mesmo padrão do domínio). Arquivo em `database/schema/5066_create_set_collection_card_set_reference_function.sql`.

## Validação Funcional (5808 — 25 casos, 0 falhas)

Bateria completa executada ao vivo com fixtures reversíveis (`BEGIN`/`ROLLBACK`, zero resíduo confirmado, incluindo checagem específica de nenhum `card_set` sintético sobrevivente): Casos A–F/J (criação REFERENCE_BASED atômica e suas rejeições), C/D (consistência supertipo/subtipo, incluindo bypass direto no subtipo), E (presença Reference no lado `collection`), G/H (mode imutável), I (reference_locked_at imutável/barrado por mode), K (Game da Reference diferente do Game da Collection → FAIL, via fixture sintético reversível — ver divergência de fixture abaixo), L (Card Set fora do Game → FAIL na criação), N (materialização real de `reference_locked_at`, timestamp exato confirmado), O–Q (imutabilidade/auditoria de `reference_locked_at`), R/S (elegibilidade de Reference — lote misto rejeitado, lote elegível aceito), T/U/V (lifecycle guard — ARCHIVED bloqueia criar/remover Reference, CASCADE via delete_collection funciona), W (troca de `card_set_id` antes do lock via 5066), X (existência/grants das 8 helpers + 2 RPCs), Z (blocker Reference-after-lock — assertion específica de `SQLERRM`, confirmando a mensagem exata de 5055/5056). Nenhuma falha em nenhum caso.

**Três divergências de fixture identificadas e corrigidas durante a execução real** (nunca detectáveis em `CREATE FUNCTION`, só na primeira execução contra o catálogo real): (1) o catálogo real do Supabase está materialmente incompleto em relação ao que o fixture original do Caso K assumia — só 1 dos 2 Games (Pokémon TCG) tem qualquer Card Set carregado (Lorcana tem 9 Expansions reais, 0 Card Sets); corrigido por instrução explícita de Fabrício (`FIXTURE CORRECTION K`): reutilizar uma Expansion real de Lorcana já existente e inserir apenas o Card Set sintético mínimo *dentro da própria transação* (nunca sobrevive ao `ROLLBACK`), sem carregar catálogo Lorcana permanente; (2) a seleção de Card Sets para os Casos CS1/CS2 não checava existência de Card Variant — corrigido com `EXISTS` na seleção, mesma categoria de correção, sem dado sintético; (3) os Casos G/I/W liam uma TEMP TABLE de fixture *depois* de impersonar a role `authenticated` via `set_config('role', ...)` — TEMP TABLEs pertencem à role de conexão, não à role impersonada; corrigido movendo as leituras para o `DECLARE` (antes do `BEGIN`, portanto antes da troca de role). Nenhuma das três correções alterou modelagem 02D, migrations 5049–5066, regras de Game, catálogo permanente ou documentação de produto — escopo confirmado por Fabrício antes da correção do Caso K. Ver `database/proposals/2026-09-02-02d-reference/5808_validate_collections_physical_increment_02d.sql` (v2.4).

## Performance (workloads reais de 200–500 operações)

Cinco workloads medidos com `EXPLAIN (ANALYZE, BUFFERS)`/timing real sobre dados sintéticos reversíveis: 200 criações via `create_reference_based_card_set_collection()` — 117,5ms total/588µs média; 200 chamadas de `set_collection_card_set_reference()` (Fase A) — 106,7ms/533µs média; flush de 200 (Fase B) — 62,4ms/312µs média; 200 trocas reais CS1→CS2 — 66,2ms total/331µs média; plano `EXPLAIN ANALYZE` da consulta de elegibilidade de Reference (JOIN `physical_card`→`card_variant`→`card`→`collection`→`collection_reference`→`collection_card_set_reference`) — 6,117ms, 13 linhas; `allocate_physical_cards_to_collection()` sobre 13 cartas elegíveis — 30,7ms. Nenhuma alegação de performance para volumes maiores que os medidos. Ver `database/proposals/2026-09-02-02d-reference/5809_performance_checks_collections_physical_increment_02d.sql` (v2.2).

## Segurança (Security/Performance Advisor)

Performance Advisor: uma nova ocorrência `unindexed_foreign_keys` (INFO) em `collection_card_set_reference_card_set_id_fkey` — mesma categoria de dezenas de outras FKs sem índice já pré-existentes no projeto, não um achado exclusivo desta rodada nem corrigido (nenhum padrão de acesso que o justifique, mesmo raciocínio já aplicado em 5052). Security Advisor: nenhum finding novo fora da categoria intencional já aceita para toda RPC `SECURITY DEFINER` `Owner`-scoped do domínio (`authenticated_security_definer_function_executable` WARN, confirmado presente para as duas RPCs novas — 5065/5066 — e confirmado **ausente** para todas as funções internas de trigger/helper desta rodada, ou seja, zero vazamento de `EXECUTE`). Nenhum finding novo de `rls_enabled_no_policy`, `function_search_path_mutable` ou qualquer outra categoria atribuível a este incremento.

## Sequência

```text
5049 - Create Collection Reference table                          (CONFIRMADO EXECUTADO — database/schema/5049_create_collection_reference_table.sql)
5050 - Create Collection Reference updated_at trigger               (CONFIRMADO EXECUTADO — database/schema/5050_create_collection_reference_updated_at_trigger.sql)
5051 - Create Collection Reference Structural Identity trigger       (CONFIRMADO EXECUTADO — database/schema/5051_create_collection_reference_structural_identity_trigger.sql)
5052 - Create Collection Card Set Reference table                   (CONFIRMADO EXECUTADO — database/schema/5052_create_collection_card_set_reference_table.sql)
5053 - Create Collection Card Set Reference updated_at trigger        (CONFIRMADO EXECUTADO — database/schema/5053_create_collection_card_set_reference_updated_at_trigger.sql)
5054 - Create Collection Card Set Reference Structural Identity trigger (CONFIRMADO EXECUTADO — database/schema/5054_create_collection_card_set_reference_structural_identity_trigger.sql)
5055 - Create Collection Card Set Reference Game and Lock trigger (v1.1) (CONFIRMADO EXECUTADO — database/schema/5055_create_collection_card_set_reference_game_and_lock_trigger.sql)
5056 - Create Collection Reference Lifecycle Guard trigger (v1.1)    (CONFIRMADO EXECUTADO — database/schema/5056_create_collection_reference_lifecycle_guard_trigger.sql)
5057 - Create Collection Reference Consistency trigger               (CONFIRMADO EXECUTADO — database/schema/5057_create_collection_reference_consistency_trigger.sql)
5058 - Create Collection Card Set Reference Consistency trigger      (CONFIRMADO EXECUTADO — database/schema/5058_create_collection_card_set_reference_consistency_trigger.sql)
5059 - Create Collection Reference Presence trigger                  (CONFIRMADO EXECUTADO — database/schema/5059_create_collection_reference_presence_trigger.sql)
5060 - Alter Collection: widen mode / unlock reference_locked_at    (CONFIRMADO EXECUTADO — database/schema/5060_alter_collection_widen_mode_and_unlock_reference.sql)
5061 - Extensão da Structural Identity trigger (dobra em 5032 v1.3)  (CONFIRMADO EXECUTADO — database/schema/5032_create_collection_structural_identity_trigger.sql)
5062 - Extensão do started_at/reference_locked_at Materializer (dobra em 5045 v1.1) (CONFIRMADO EXECUTADO — database/schema/5045_create_collection_started_at_from_allocation_trigger.sql)
5063 - Extensão da Allocation Integrity trigger (dobra em 5042 v1.2) (CONFIRMADO EXECUTADO — database/schema/5042_create_collection_allocation_integrity_trigger.sql)
5064 - Extensão do allocate_physical_cards_to_collection() (dobra em 5046 v1.2) (CONFIRMADO EXECUTADO — database/schema/5046_create_allocate_physical_cards_to_collection_function.sql)
5065 - Create create_reference_based_card_set_collection() function (CONFIRMADO EXECUTADO — database/schema/5065_create_reference_based_card_set_collection_function.sql)
5066 - Create set_collection_card_set_reference() function           (CONFIRMADO EXECUTADO — database/schema/5066_create_set_collection_card_set_reference_function.sql)
5808 - Validate Collections Physical Increment 02D (25 casos, v2.4) (EXECUTADA — database/proposals/2026-09-02-02d-reference/5808_validate_collections_physical_increment_02d.sql)
5809 - Performance Checks Collections Physical Increment 02D (v2.2) (EXECUTADA — database/proposals/2026-09-02-02d-reference/5809_performance_checks_collections_physical_increment_02d.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída nesta rodada — fundação exclusivamente de banco. `completion_policy` (LDM-08) foi materializada no incremento seguinte (02E — ver seção própria abaixo), não mais pendente. `collection_pokedex_reference` (segundo subtipo, `reference_kind = 'POKEDEX'`) permanece fora de escopo físico — Pokédex/Pokédex Position nem existem fisicamente ainda, ainda que a modelagem conceitual/lógica tenha sido fechada em 2026-09-03 (ver seção "Collection Pokédex Reference / REFERENCE_POSITION" abaixo); o desenho supertipo/subtipo já acomoda essa extensão futura sem migration destrutiva. `set_collection_visibility()`/Public Access seguem fora desde o 2B. Layout/Slot/Placement, Custody & Availability, Lifecycle/Provenance, Favorite, Wishlist, Condition, Grading/Certification, Collaboration/Permissions e Activity History/Audit seguem sem modelo físico.

---

# Collection Completion / Progress (02E — STANDARD_SET)

## Status

**STANDARD_SET Completion/Progress CONFIRMADO EXECUTADO em 2026-09-02** (`COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01`). Precedido por `COLLECTIONS-PHYSICAL-INCREMENT-02E-MODELING-01`/`-MODELING-REVISION-01` (modelagem conceitual/física, sem alteração de banco) e por uma rodada de staging auditada em `database/proposals/2026-09-02-02e-completion/` (`-STAGING-01` até `-STAGING-EXECUTION-SAFETY-FIX-01`) antes da implementação real. Cinco Queries físicas (`5067`–`5071`), uma bateria de validação funcional de 72 casos (0 falhas) e um plano de performance com 9 workloads (A–I) — todos executados e confirmados ao vivo na mesma rodada, contra o catálogo real do Supabase (não sintetizado do zero).

Completion é inteiramente **derivada** — nenhuma coluna de progresso persistida em `collection` ou em qualquer outra tabela. `total_positions`/`satisfied_positions`/`missing_positions`/`progress_percentage`/`is_complete` são sempre calculados em tempo de leitura pelas duas funções desta rodada, a partir do estado corrente de `collection_allocation`/`physical_card`/`card_variant`/`card` — nunca um contador incrementado por trigger. Coerente com C-23/LDM-22: quando `completion_policy` mudar de valor no futuro (STANDARD_SET <-> MASTER_SET), nenhuma migração de dado de progresso é necessária, porque não existe dado de progresso armazenado para migrar.

## Decisão de Modelagem — `completion_policy`

`public.collection.completion_policy` (Query 5067) materializa fisicamente LDM-08/LDM-20: `NONE` (obrigatório quando `mode = 'OPEN_CURATION'`) ou `STANDARD_SET` (obrigatório quando `mode = 'REFERENCE_BASED'`), enforced por `CHECK chk_collection_completion_policy` de coluna única — sem trigger cross-table, porque `mode` e `completion_policy` são colunas da mesma linha. `MASTER_SET`/`REFERENCE_POSITION` permanecem **CONCEPTUALLY READY. PHYSICALLY DEFERRED FROM 02E FOR SCOPE CONTROL** — decisão de escopo do incremento (a entidade `Collection Master Set Scope`, LDM-21, ampliaria significativamente o 02E), nunca atribuída à cobertura atual de `card_variant` no catálogo; cobertura de catálogo é matéria de governança/readiness operacional, tratada em rodada própria, jamais uma restrição de arquitetura ou produto. `completion_policy` permanece mutável por desenho (C-23/LDM-22, troca futura STANDARD_SET <-> MASTER_SET preservando identidade/Reference/Allocation/Storage) — nenhuma linha adicionada a `validate_collection_structural_identity()` nesta rodada.

`create_collection()` (Query 5068, `CREATE OR REPLACE` de 5034) grava sempre `'NONE'`; `create_reference_based_card_set_collection()` (Query 5069, `CREATE OR REPLACE` de 5065) grava sempre `'STANDARD_SET'` — nenhum parâmetro `p_completion_policy` exposto ao chamador em nenhuma das duas RPCs (só um valor válido por caminho de criação nesta etapa). Assinatura e `RETURNS TABLE` de ambas preservados integralmente; `completion_policy` não foi adicionado ao contrato de retorno de nenhuma das duas (o valor já é determinístico e conhecido de antemão pelo caminho de criação usado).

## Query `5067` — Alter Collection: Add `completion_policy` (CONFIRMADO EXECUTADO)

`ADD COLUMN` nulável sem `DEFAULT` seguido de backfill por `mode` (`OPEN_CURATION` → `NONE`, `REFERENCE_BASED` → `STANDARD_SET`), validação real (`RAISE EXCEPTION` se sobrar `NULL` ou combinação inválida) antes de `SET NOT NULL` + `CHECK`. Arquivo em `database/schema/5067_alter_collection_add_completion_policy.sql`.

## Query `5068` — Update `create_collection()` (CONFIRMADO EXECUTADO)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5068_update_create_collection_function.sql`.

## Query `5069` — Update `create_reference_based_card_set_collection()` (CONFIRMADO EXECUTADO)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5069_update_create_reference_based_card_set_collection_function.sql`.

## Query `5070` — Create `collection_completion_summary()` (CONFIRMADO EXECUTADO, v2.0)

Read model de resumo: `collection_id`, `completion_policy`, `total_positions`, `satisfied_positions`, `missing_positions`, `progress_percentage`, `is_complete`. DENOMINADOR (`public.card` por `card_set_id` da Reference, independente de Allocation) e NUMERADOR (`collection_allocation` → `physical_card` → `card_variant` → `card`, com `count(DISTINCT card.id)`) são duas metades independentes, nunca um único `GROUP BY` — **duplicatas nunca inflam progresso**: múltiplos exemplares físicos (`physical_card`) da mesma posição contam como 1 só via `DISTINCT`, validado ao vivo com 2.000 exemplares concentrados em 5 posições (Caso/workload D, `satisfied_positions = 5`) e com 5.000 alocações cicladas sobre um pool menor (workload F). `total_positions = 0` → `progress_percentage = 0.00`, `is_complete = false`, nunca divisão por zero.

**`SECURITY DEFINER` é uma projeção estreita, owner-scoped, não um relaxamento geral de RLS.** Achado real que motivou a correção (v1.0 era `SECURITY INVOKER`): o Catálogo Editorial (`ADR-022`, confirmado por `ADR-030`) fecha `public.card`/`public.card_variant` a `SELECT` direto de `authenticated` — `card` tem RLS habilitada sem nenhuma policy, `card_variant` só tem `catalog_admin_select` (`is_admin()`-gated) — logo `SECURITY INVOKER` fazia `total_positions`/`satisfied_positions` serem sempre 0 para qualquer Owner real não-admin. A correção para `SECURITY DEFINER` bypassa a RLS de `collection`/`collection_reference`/`collection_card_set_reference`/`collection_allocation`/`physical_card` também — por isso ownership é reconstituído manualmente dentro da própria função, na CTE `target` (`c.owner_user_id = (select auth.uid())`, sempre o primeiro passo, antes de qualquer tabela do Catálogo), nunca herdado implicitamente da RLS. **O Catálogo Editorial permanece admin-only**: esta função não abre nenhuma policy nova em `card`/`card_variant`/`card_set`, não concede nenhum `SELECT` editorial novo a `authenticated`, e um `authenticated` comum continua vendo 0 linhas ao consultar `card`/`card_variant` diretamente — confirmado ao vivo (5810, Caso SEC-M). `STABLE`, `SET search_path = ''`, `(select auth.uid()) IS NOT NULL` explícito (nunca `is_admin()` — Completion não é operação administrativa), `REVOKE ALL FROM PUBLIC`/`anon` + `GRANT EXECUTE TO authenticated`. Arquivo em `database/schema/5070_create_collection_completion_summary_function.sql`.

## Query `5071` — Create `collection_completion_positions()` (CONFIRMADO EXECUTADO, v2.0)

Read model de posições individuais: `card_id`, `collector_number`, `name`, `is_satisfied`, com `p_only_missing BOOLEAN DEFAULT FALSE` (nome deliberadamente não "missing_positions" — o filtro é explícito por parâmetro, não pelo nome da função). Mesma fronteira de autorização e mesma disciplina `SECURITY DEFINER` de `5070` v2.0 (ver acima, não duplicado aqui). Ordenação determinística via `card.collector_order`, com `card.collector_number`/`card.id` como desempate. Arquivo em `database/schema/5071_create_collection_completion_positions_function.sql`.

## Segurança — não-enumeração e ownership (evidência real, 5810)

Confirmado ao vivo, com dois Owners não-admin distintos (`is_admin() = false` provado para ambos antes de qualquer caso funcional/de segurança — `PRECOND-ADMIN-A`/`PRECOND-ADMIN-B`): Owner acessa a própria Collection (`SEC-A`/`X`, 1 row); Owner NÃO acessa a Collection real de outro Owner (`U`/`SEC-C`, `SEC-BYPASS`, 0 rows) e essa Collection real de outro Owner tem exatamente a mesma forma externa que uma Collection inexistente (`V`/`SEC-E`, `W`/`SEC-D`/`SEC-F`, `SEC-BYPASS`) — não-enumeração preservada mesmo com RLS bypassada por `SECURITY DEFINER`; `anon` recebe `EXECUTE` negado nas duas funções, comportamento real testado (`SEC-H`), não só ausência estática de GRANT; `authenticated` continua com 0 linhas ao consultar `public.card`/`public.card_variant` diretamente (`SEC-M`); `PUBLIC` sem `EXECUTE`, `anon` sem `EXECUTE`, `authenticated` com `EXECUTE`, `SECURITY DEFINER`/`STABLE`/`search_path=''` confirmados via `pg_proc`/`aclexplode` (`SEC-I`–`SEC-L`); exatamente 1 assinatura no catálogo para as 4 funções relevantes (nenhum overload inesperado). Zero policy nova em `card`/`card_variant`/`card_set`.

## Validação Funcional (5810 v4.1 — 72 casos, 0 falhas)

Bateria completa executada ao vivo com fixtures reversíveis (`BEGIN`/`ROLLBACK` incondicional, zero resíduo confirmado). Achado real de execução (nunca detectado em nenhuma rodada de staging/auditoria anterior, porque nenhuma delas de fato executou): `test_results.id` é `SERIAL`, e a função de log da própria bateria (`pg_temp.log_result()`) é `SECURITY INVOKER` — sem `GRANT USAGE ON SEQUENCE test_results_id_seq` para `authenticated`/`anon`, todo `INSERT` de resultado falhava com "permission denied for sequence". Corrigido no próprio arquivo de validação (v4.0 → v4.1), sem alterar `5067`–`5071`. Ver `database/proposals/2026-09-02-02e-completion/5810_validate_collections_physical_increment_02e.sql` (v4.1).

## Performance (9 workloads, 5811 v1.5)

Medido sobre um Card Set real do catálogo (295 posições, pool de 295 Card Variants — cobertura de catálogo é escolha de fixture, nunca requisito de STANDARD_SET), como `authenticated`/Owner não-admin, dentro de transação revertida. Todos os 9 workloads (A–I) executaram em menos de 30ms (`Execution Time`), nó do planner sempre `Function Scan`, `Shared Read Blocks = 0` em todos (totalmente cache-resident, nenhuma leitura de disco): A (Collection vazia) 2,4ms; B (~75%, 221/295) summary 3,2ms + positions 3,4ms; C (100%, pool=total) 3,5ms; D (2.000 Physical Cards / 5 posições, prova de `COUNT(DISTINCT)` sob duplicação pesada) 12,0ms; E (500 alocações) 4,8ms; F (5.000 alocações, maior volume) 29,5ms; G (6 Collections do mesmo Card Set em sequência, sem degradação por vizinhança) 1,5–29,3ms; H (`only_missing=true`) 3,1ms; I (experiência de tela real, `summary()` + `positions()`) 2,96ms + 2,92ms = 5,88ms combinado. Nenhum índice, cache ou materialized view criado — nenhum gargalo comprovado. Ver `database/proposals/2026-09-02-02e-completion/5811_performance_checks_collections_physical_increment_02e.sql` (v1.5).

## Sequência

```text
5067 - Alter Collection: add completion_policy                     (CONFIRMADO EXECUTADO — database/schema/5067_alter_collection_add_completion_policy.sql)
5068 - Update create_collection() function                          (CONFIRMADO EXECUTADO — database/schema/5068_update_create_collection_function.sql)
5069 - Update create_reference_based_card_set_collection() function (CONFIRMADO EXECUTADO — database/schema/5069_update_create_reference_based_card_set_collection_function.sql)
5070 - Create collection_completion_summary() function (v2.0)       (CONFIRMADO EXECUTADO — database/schema/5070_create_collection_completion_summary_function.sql)
5071 - Create collection_completion_positions() function (v2.0)     (CONFIRMADO EXECUTADO — database/schema/5071_create_collection_completion_positions_function.sql)
5810 - Validate Collections Physical Increment 02E (72 casos, v4.1) (EXECUTADA — database/proposals/2026-09-02-02e-completion/5810_validate_collections_physical_increment_02e.sql)
5811 - Performance Checks Collections Physical Increment 02E (v1.5) (EXECUTADA — database/proposals/2026-09-02-02e-completion/5811_performance_checks_collections_physical_increment_02e.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída nesta rodada — fundação exclusivamente de banco. `MASTER_SET`/`Collection Master Set Scope`/`REFERENCE_POSITION`/Pokédex Reference permanecem **CONCEPTUALLY READY. PHYSICALLY DEFERRED FOR SCOPE CONTROL** (ver "Decisão de Modelagem" acima) — nunca atribuído à cobertura atual do catálogo. RPC de troca de `completion_policy`, cache/materialized view sobre os read models, e qualquer superfície de frontend seguem fora de escopo. `MASTER_SET` materializado no incremento seguinte (02F — ver seção própria abaixo).

---

# Collection Master Set Scope (02F — MASTER_SET)

## Status

**`COLLECTIONS-PHYSICAL-INCREMENT-02F` — CLOSED (2026-09-02). MASTER_SET Scope & Completion — FINALIZADO.** Declaração formal via `COLLECTIONS-PHYSICAL-INCREMENT-02F-FINAL-CLOSURE-01`, após auditoria final (schema-vs-banco, zero divergência) e autorização explícita de Fabrício. Precedido por `COLLECTIONS-MASTER-SET-MODELING-01` até `-FINAL-FIX-02` (modelagem conceitual/física, sem alteração de banco), staging auditado em `database/proposals/2026-09-02-02f-master-set/` (`-STAGING-01`/`-STAGING-REVISION-01`), aplicação real (`-IMPLEMENTATION-01`) e promoção canônica (`-CANONICAL-PROMOTION-01`). Treze Queries físicas (`5072`–`5084`), validação funcional de 114 casos (0 falhas, 0 erros de runtime, zero resíduo) e performance com 10 workloads (A–J) sobre um pool combinado de 10.000 Card Variants — todos executados e confirmados ao vivo. Nenhuma alteração de schema/SQL nesta rodada de fechamento — só reconciliação documental.

Mesma disciplina de `STANDARD_SET` (02E): completion é inteiramente **derivada**, nenhuma coluna de progresso persistida. O que É persistido, e é a diferença central de `MASTER_SET`, é o próprio **Adopted Scope** (`collection_master_set_scope`, LDM-21/C-23) — o conjunto de `card_variant_id` que o Owner escolheu explicitamente como requisito de completude daquela Collection. Duas Collections do mesmo Card Set podem ter Scopes diferentes, ambos válidos; o denominador de `MASTER_SET` nunca é uma regra automática de catálogo decidindo se Reverse/Stamp/Jumbo/Tournament/Promo "conta".

## Decisão de Modelagem — `Collection Master Set Scope`

`public.collection_master_set_scope` (Query 5072) usa PK natural composta `(collection_id, card_variant_id)` — a invariante "uma Variant aparece no máximo uma vez no Scope de uma Collection" é exatamente o que a PK declara, sem UUID próprio nem UNIQUE separado. Tabela insert/delete-only por desenho: toda mudança de composição é REMOVE (`DELETE`) + ADD (`INSERT`), nunca `UPDATE` — formalizado estruturalmente pela Query `5074` (`trg_collection_master_set_scope_reject_update`), que rejeita incondicionalmente qualquer `UPDATE`, inclusive de `adopted_at`/`adopted_by_user_id`.

Elegibilidade imediata (Query 5073, `BEFORE INSERT`, fail-closed): a Collection referenciada deve ser `mode = 'REFERENCE_BASED'` com `collection_reference.reference_kind = 'CARD_SET'`, e a `card_variant_id` inserida deve pertencer ao mesmo Card Set referenciado — mesmo padrão de elegibilidade já usado para `collection_allocation` (02D).

**Invariante "MASTER_SET ativo nunca fica com Scope vazio" (LDM-20/LDM-21) — enforcement DIFERIDO bidirecional**, decisão central desta rodada: `CHECK` de coluna única (`chk_collection_completion_policy`, Query 5078) não consegue expressar essa regra (exige JOIN entre `collection` e `collection_master_set_scope`). Resolvida com dois `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` que convergem no mesmo helper: `check_master_set_scope_presence()` (Query 5075) sempre reconsulta o estado CORRENTE da Collection no momento em que é chamado — nunca decide a partir de `NEW`/`OLD` do evento que o disparou (que serve só como correlation key). Isso torna o enforcement correto mesmo quando a mesma Collection muda `completion_policy` mais de uma vez na mesma transação, ou quando o Scope passa por um instante vazio dentro de uma transação que termina com Scope não-vazio (`replace_master_set_scope()` opera assim por desenho). Lado "Collection" (Query 5076, `AFTER INSERT OR UPDATE OF completion_policy`) cobre a transição para `MASTER_SET`; lado "Scope" (Query 5077, `AFTER DELETE`) cobre a remoção da última linha — só `DELETE`, nunca `DELETE OR UPDATE`, porque `UPDATE` já é bloqueado imediatamente por `5074`. `DELETE` cascateado por exclusão da própria Collection sempre passa (a Collection já não existe mais no momento diferido — contrato explícito do helper).

`chk_collection_completion_policy` (Query 5078, `DROP`+`ADD` sobre a mesma constraint criada em `5067`/02E) alarga para a terceira combinação válida: `mode = 'REFERENCE_BASED' AND completion_policy = 'MASTER_SET'`. `completion_policy` continua mutável por desenho (C-23/LDM-22) — nenhuma linha adicionada a `validate_collection_structural_identity()` por esta rodada.

Semântica de mutação de Scope — **VALIDATE ALL -> KEEP -> ADD -> REMOVE** (nunca `DELETE` total + `INSERT` total, que destruiria `adopted_at`/`adopted_by_user_id` das Variants que permanecem), implementada uma única vez em `apply_master_set_scope_diff()` (Query 5079, helper interno compartilhado) e consumida por duas RPCs com contratos distintos: `set_collection_completion_policy_to_master_set()` (Query 5080, transição `STANDARD_SET -> MASTER_SET`, dois caminhos — Scope novo via `p_card_variant_ids` ou reaproveitamento do Scope já persistido) e `replace_master_set_scope()` (Query 5082, única RPC de mutação de Scope com a Collection já `MASTER_SET`). `set_collection_completion_policy_to_standard_set()` (Query 5081, transição inversa) preserva o Scope persistido integralmente — nenhum `DELETE` em `collection_master_set_scope`, só `collection.completion_policy` é escrito.

`apply_master_set_scope_diff()` valida o payload em camadas antes de qualquer escrita (shape/array não-vazio/guard de tamanho/todo elemento string/formato UUID por regex/duplicata rejeitada por identidade UUID — nunca normalizada silenciosamente/existência+pertencimento ao Card Set), sempre abortando a função inteira via `RAISE EXCEPTION` no primeiro problema encontrado, zero escrita parcial. Guard operacional `c_max_variant_ids = 10000` — decisão operacional, não arquitetural, ver seção "Bulk Guard" abaixo.

## Query `5072` — Create Collection Master Set Scope Table (CONFIRMADO EXECUTADO, v1.0)

Tabela `collection_master_set_scope`: `collection_id` (`ON DELETE CASCADE`), `card_variant_id` (`ON DELETE RESTRICT`), `adopted_at`, `adopted_by_user_id`. RLS: única policy é `SELECT` do próprio Owner via join até `collection.owner_user_id`; nenhuma policy de escrita para `authenticated` — toda escrita passa pelas RPCs `SECURITY DEFINER` (`5080`–`5082`). Arquivo em `database/schema/5072_create_collection_master_set_scope_table.sql`.

## Query `5073` — Create Collection Master Set Scope Eligibility Trigger (CONFIRMADO EXECUTADO, v1.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5073_create_collection_master_set_scope_eligibility_trigger.sql`.

## Query `5074` — Create Collection Master Set Scope Update Block Trigger (CONFIRMADO EXECUTADO, v1.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5074_create_collection_master_set_scope_update_block_trigger.sql`.

## Query `5075` — Create `check_master_set_scope_presence()` Helper (CONFIRMADO EXECUTADO, v1.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5075_create_check_master_set_scope_presence_function.sql`.

## Query `5076` — Create Collection Master Set Scope Presence Trigger, lado Collection (CONFIRMADO EXECUTADO, v1.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5076_create_collection_master_set_scope_presence_trigger.sql`.

## Query `5077` — Create Master Set Scope Presence Trigger, lado Scope/On Delete (CONFIRMADO EXECUTADO, v1.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5077_create_master_set_scope_presence_on_delete_trigger.sql`.

## Query `5078` — Alter Collection: Widen `completion_policy` for MASTER_SET (CONFIRMADO EXECUTADO, v1.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5078_alter_collection_widen_completion_policy_master_set.sql`.

## Query `5079` — Create `apply_master_set_scope_diff()` Helper (CONFIRMADO EXECUTADO, v2.1)

Ver "Decisão de Modelagem" acima e "Bulk Guard" abaixo. Arquivo em `database/schema/5079_create_apply_master_set_scope_diff_function.sql`.

## Query `5080` — Create `set_collection_completion_policy_to_master_set()` (CONFIRMADO EXECUTADO, v2.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5080_create_set_collection_completion_policy_to_master_set_function.sql`.

## Query `5081` — Create `set_collection_completion_policy_to_standard_set()` (CONFIRMADO EXECUTADO, v2.0)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5081_create_set_collection_completion_policy_to_standard_set_function.sql`.

## Query `5082` — Create `replace_master_set_scope()` (CONFIRMADO EXECUTADO, v1.1)

Ver "Decisão de Modelagem" acima. Arquivo em `database/schema/5082_create_replace_master_set_scope_function.sql`.

## Query `5083` — Update `collection_completion_summary()` (CONFIRMADO EXECUTADO, v3.0, estende `5070` v2.0/02E)

Estende o read model de resumo (02E) para suportar `MASTER_SET` além de `STANDARD_SET` — contrato externo de campos idêntico, só o cálculo interno muda por `completion_policy` (`UNION ALL` de dois pares de CTE mutuamente exclusivos, `LANGUAGE SQL` preservado). Ramo `STANDARD_SET` inalterado byte-a-byte. Ramo `MASTER_SET` (novo): denominador = `COUNT(DISTINCT card_variant_id)` do Adopted Scope; numerador = `COUNT(DISTINCT card_variant_id)` do Scope com correspondência EXATA de `card_variant_id` alocado (`pc.card_variant_id = s.card_variant_id`) — nunca "qualquer Variant da mesma Card", diferença central em relação a `STANDARD_SET` (LDM-19). Duplicatas de Physical Card da mesma Variant contam 1 só via `DISTINCT`, confirmado por medição real (5813, workload F — 2.000 Physical Cards concentrados em 10 posições, mesmo custo do baseline sem duplicatas). Segurança/ownership inalterados da v2.0. **Correção documental**: esta função é e sempre foi `LANGUAGE SQL` (confirmado por leitura direta de `pg_proc`/`pg_language` no banco físico) — não PL/pgSQL, como o relatório inicial de performance do `5813` chegou a descrever ao interpretar o nó `Function Scan` do `EXPLAIN`. Arquivo em `database/schema/5083_update_collection_completion_summary_function.sql`.

## Query `5084` — Create `collection_master_set_scope_positions()` (CONFIRMADO EXECUTADO, v1.0)

Read model NOVO, específico de `MASTER_SET` — `collection_completion_positions()` (5071, Card-oriented) permanece intocada. Grão: 1 linha por `card_variant_id` adotada no Scope (genuinamente diferente do grão de `5071`, porque uma mesma Card pode ter várias Variants adotadas simultaneamente). `LANGUAGE SQL`, `STABLE`, mesma disciplina de `SECURITY DEFINER`/ownership manual de `5070`/`5071`/`5083`. Ordenação determinística por `card.collector_order`/`card.collector_number`/`card_variant_type.display_order`. Arquivo em `database/schema/5084_create_collection_master_set_scope_positions_function.sql`.

## Bulk Guard — `c_max_variant_ids = 10000`

Guard **operacional** (proteção contra payload/tempo de transação abusivo), não uma decisão de domínio nem um limite arquitetural — não derivado do maior Card Set físico observado hoje (630 Card Variants). Confirmado, não alterado, após evidência real de performance (`5813` v2.0, `COLLECTIONS-PHYSICAL-INCREMENT-02F-PERFORMANCE-01`): testado com um pool combinado de 10.000 Card Variants (630 reais + 9.370 sintéticas, materialmente próximo ao teto do guard, ~16x o maior Card Set real hoje). `replace_master_set_scope()` mediu ~219ms para payload de 9.050 itens (alta sobreposição, KEEP=8.550/ADD=500/REMOVE=450) e ~151ms para payload de 1.900 itens (alta troca, KEEP=900/ADD=1.000/REMOVE=8.100) — sem spill de sort/hash em nenhum plano, custo aparentemente dominado pelo tamanho do payload JSON recebido, não pelo volume de linhas DELETE/INSERT. Leituras (`collection_completion_summary()`/`collection_master_set_scope_positions()`) no mesmo teto: 57–93ms, também sem spill, sem dependência mensurável do volume total de Inventory do Owner (confirmado comparando um Owner com 32.210 Physical Cards contra o mesmo cenário com Inventory pequeno — tempos praticamente idênticos). Nenhuma evidência de performance justifica reduzir o valor; permanece sujeito a revisão futura por nova evidência operacional, nunca ajuste silencioso. Sem ADR dedicado — decisão registrada aqui e no cabeçalho de `5079`, mesmo padrão já usado para outros guards operacionais do domínio (ex.: limite de 500 itens por chamada em `add_physical_cards()`/`allocate_physical_cards_to_collection()`).

## Validação Funcional (5812 v2.3 — 114 casos, 0 falhas, 0 erros de runtime, zero resíduo)

Bateria completa executada ao vivo, fixtures reversíveis, zero resíduo confirmado. Duas correções de test harness encontradas e corrigidas durante a implementação real (nunca do schema `5072`–`5084` em si, que não foi alterado em nenhuma das duas rodadas de correção): (1) `authenticated` não tem `INSERT` direto em `physical_card` por desenho — corrigido substituindo INSERTs diretos do harness pela RPC pública real `add_physical_cards()`, preservando o teste sob o contrato real de `authenticated`; (2) uma fixture de Card Set pequeno dedicado (REG-STD-7) resolvia catálogo diretamente após `SET ROLE authenticated`, mas o Catálogo Editorial é fechado por RLS para usuários comuns — corrigido movendo a resolução da fixture para contexto privilegiado (antes do `SET ROLE`), consumida via tabela de contexto de teste. Ver `database/proposals/2026-09-02-02f-master-set/5812_validate_collections_physical_increment_02f.sql` (v2.3).

## Performance (10 workloads A–J, 5813 v2.0)

Medido sobre um pool combinado de 10.000 Card Variants (`real_pool_size = 630`, `synth_buffer = 9.370`, `pool_size = 10.000` — acima do maior Card Set real hoje por desenho, para testar carga materialmente próxima do bulk guard), Inventory do Owner em 32.210 Physical Cards (≥ 20.000 exigido), como `authenticated`/Owner não-admin, dentro de transação revertida (zero resíduo confirmado). Destaques: summary sobre Scope de 10.000 posições (100% coberto) ~57ms; positions equivalente ~93ms, 10.000 linhas; `replace_master_set_scope()` alta sobreposição (payload 9.050) ~219ms; alta troca (payload 1.900) ~151ms; tela combinada (summary + positions sobre o Scope de 10.000) ~145ms total. Nenhum spill de sort/hash em nenhum dos planos capturados; nenhuma dependência mensurável do volume total de Inventory do Owner nas leituras; duplicatas de Physical Card não impõem custo adicional mensurável ao summary. Ver "Bulk Guard" acima para a decisão resultante. Ver `database/proposals/2026-09-02-02f-master-set/5813_performance_checks_collections_physical_increment_02f.sql` (v2.0).

## Sequência

```text
5072 - Create collection_master_set_scope table                        (CONFIRMADO EXECUTADO — database/schema/5072_create_collection_master_set_scope_table.sql)
5073 - Create Collection Master Set Scope Eligibility Trigger (v1.0)    (CONFIRMADO EXECUTADO — database/schema/5073_create_collection_master_set_scope_eligibility_trigger.sql)
5074 - Create Collection Master Set Scope Update Block Trigger (v1.0)   (CONFIRMADO EXECUTADO — database/schema/5074_create_collection_master_set_scope_update_block_trigger.sql)
5075 - Create check_master_set_scope_presence() helper (v1.0)          (CONFIRMADO EXECUTADO — database/schema/5075_create_check_master_set_scope_presence_function.sql)
5076 - Create Collection Master Set Scope Presence Trigger (v1.0)       (CONFIRMADO EXECUTADO — database/schema/5076_create_collection_master_set_scope_presence_trigger.sql)
5077 - Create Master Set Scope Presence Trigger On Delete (v1.0)        (CONFIRMADO EXECUTADO — database/schema/5077_create_master_set_scope_presence_on_delete_trigger.sql)
5078 - Alter Collection: widen completion_policy for MASTER_SET (v1.0) (CONFIRMADO EXECUTADO — database/schema/5078_alter_collection_widen_completion_policy_master_set.sql)
5079 - Create apply_master_set_scope_diff() helper (v2.1)              (CONFIRMADO EXECUTADO — database/schema/5079_create_apply_master_set_scope_diff_function.sql)
5080 - Create set_collection_completion_policy_to_master_set() (v2.0)  (CONFIRMADO EXECUTADO — database/schema/5080_create_set_collection_completion_policy_to_master_set_function.sql)
5081 - Create set_collection_completion_policy_to_standard_set() (v2.0) (CONFIRMADO EXECUTADO — database/schema/5081_create_set_collection_completion_policy_to_standard_set_function.sql)
5082 - Create replace_master_set_scope() (v1.1)                        (CONFIRMADO EXECUTADO — database/schema/5082_create_replace_master_set_scope_function.sql)
5083 - Update collection_completion_summary() function (v3.0)          (CONFIRMADO EXECUTADO — database/schema/5083_update_collection_completion_summary_function.sql)
5084 - Create collection_master_set_scope_positions() function (v1.0)  (CONFIRMADO EXECUTADO — database/schema/5084_create_collection_master_set_scope_positions_function.sql)
5812 - Validate Collections Physical Increment 02F (114 casos, v2.3)   (EXECUTADA — database/proposals/2026-09-02-02f-master-set/5812_validate_collections_physical_increment_02f.sql)
5813 - Performance Checks Collections Physical Increment 02F (v2.0)    (EXECUTADA — database/proposals/2026-09-02-02f-master-set/5813_performance_checks_collections_physical_increment_02f.sql)
```

## Pendências / Próximos Passos

Nenhuma superfície de frontend construída neste incremento — fundação exclusivamente de banco. `REFERENCE_POSITION`/Pokédex Reference tiveram sua **modelagem conceitual fechada em 2026-09-03** (ver seção própria "Collection Pokédex Reference / REFERENCE_POSITION" abaixo) — não materializados fisicamente ainda; Pokédex é a próxima frente planejada, com "POKEDEX PHYSICAL MODELING" como checkpoint seguinte. `add_master_set_variants()`/`remove_master_set_variants()` (mutação incremental por Variant individual, em vez de substituição completa via `replace_master_set_scope()`) permanecem deferidos, não implementados (decisão fechada em MODELING-REVISION-01 item 5). Cache/materialized view sobre os read models e qualquer superfície de frontend seguem fora de escopo. **Auditoria final de fechamento concluída (zero divergência entre `database/schema` e o banco físico) e `COLLECTIONS-PHYSICAL-INCREMENT-02F` declarado `CLOSED` por autorização explícita de Fabrício (`COLLECTIONS-PHYSICAL-INCREMENT-02F-FINAL-CLOSURE-01`, 2026-09-02).**

---

# Collection Pokédex Reference / REFERENCE_POSITION (Pokédex — CONCEPTUALLY CLOSED)

## Status

**Modelagem conceitual e lógica CONCEPTUALLY CLOSED em 2026-09-03** (`COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`), ao final de uma cadeia de cinco rodadas: `COLLECTIONS-POKEDEX-MODELING-AUDIT-01` (auditoria read-only do estado atual) → `COLLECTIONS-POKEDEX-DATA-SOURCE-SPIKE-01` (avaliação de fontes de dados — PokéAPI, TCGdex) → `COLLECTIONS-POKEDEX-TCGDEX-DEXID-PROOF-01` (prova empírica real, 9 casos representativos, contra a API real da TCGdex e da PokéAPI) → `COLLECTIONS-POKEDEX-MODELING-RECONCILIATION-01` (reconciliação da modelagem já existente contra as novas decisões) → `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01` (esta rodada, documentação canônica). **Fundação física de Pokémon Species/Generation CONFIRMADO EXECUTADO em 2026-09-04** (`COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01`), Queries `6000`–`6021` + `6700` (tabelas `pokemon_generation`/`pokemon_species`/`pokemon_species_external_reference`, sem `game_id` — entidades globais do universo Pokémon, não do TCG; ver `docs/standards/STD-001-database-standards.md` para o modelo físico completo, milhar `6000`–`6999`). **Fatia A ("Canonical Pokédex Foundation") também CONFIRMADO EXECUTADO em 2026-09-04** (`COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`), Queries `6030`/`6031` (`pokedex`), `6040`/`6041` (`pokedex_position`) e `6050`/`6051` (`pokedex_external_reference`) — as três tabelas existem fisicamente, RLS fechado (zero policy, zero privilégio de cliente); **populadas desde 2026-09-05** pelo Initial Load do Pokémon Catalog via PokéAPI (ver `docs/06a-pokemon-catalog-sourcing.md`, fonte canônica das contagens). **Pokémon Region Foundation também CONFIRMADO EXECUTADO E PROMOVIDO em 2026-09-04** (`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01` → `POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`), Queries `6060`/`6061` (`pokemon_region`), `6070`/`6071` (`pokemon_region_external_reference`) e `6080` (`pokemon_generation.main_region_id`) — ver subseção própria "Pokémon Region (extensão física, 2026-09-04)" abaixo. **Fatia B ("Collection Pokédex Reference + Adopted Scope") — IMPLEMENTED / VALIDATED / CLOSED em 2026-09-05** (`COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-IMPLEMENTATION-01` → `-CANONICAL-PROMOTION-01`), Queries `5085`–`5099` — ver subseção própria "Collection Pokédex Reference / Adopted Scope (Fatia B, extensão física, 2026-09-05)" abaixo. **Fatia C ("Card → Primary Species / sourcing") também CONFIRMADO EXECUTADO em 2026-09-05** (`COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-IMPLEMENTATION-01-RESUME` → `-INCREMENTAL-IMPLEMENTATION-01` → `-CANONICAL-CLOSEOUT-01`), Queries `2159`/`6112`–`6116` — ver subseção própria "Card → Primary Species (Fatia C, extensão física, 2026-09-05)" abaixo. **Fatia D ("Pokédex Position Assignment + Primary Representative") — IMPLEMENTED / VALIDATED / CLOSED em 2026-09-06** (`COLLECTIONS-POKEDEX-FATIA-D-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-STAGING-01` → `-IMPLEMENTATION-RESUME-02` → `-6126-STAGING-01`/`-IMPLEMENT-RESUME-01` → `-FINAL-VALIDATION-CLEANUP-01` → `-PROMOTION-CLOSEOUT-01`), Queries `6117`–`6126` — ver subseção própria "Pokédex Position Assignment / Primary Representative (Fatia D, extensão física, 2026-09-06)" abaixo. **Fatia E ("REFERENCE_POSITION Completion") — IMPLEMENTED / LIVE / VALIDATED / PERFORMANCE-MEASURED / CLOSED tecnicamente em 2026-09-06** (cadeia `COLLECTIONS-POKEDEX-FATIA-E-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-STAGING-01`/`-STAGING-REVISION-01` → `-IMPLEMENTATION-01` → `-PERFORMANCE-01` → `-PERFORMANCE-HARNESS-REVISION-01` → `-PERFORMANCE-EXECUTION-01` → `-PERFORMANCE-REMEDIATION-AUDIT-01`/`-STAGING-01` → `-AB-HARNESS-FINAL-FIX-01` → `-AB-EXECUTION-01` → `-PERFORMANCE-REMEDIATION-IMPLEMENTATION-01` → `-POSTCHECK-2C-CORRECTION-STAGING-01`/`-EXECUTION-01` → `-FINAL-LIVE-PERFORMANCE-01` → `-CLOSEOUT-01`), Queries `5100`–`5103` — ver subseção própria "REFERENCE_POSITION Completion & Scope Positions read model (Fatia E, extensão física, 2026-09-06)" abaixo. **Próxima frente do projeto: Binder/Layout Foundation.**

Fonte canônica e completa da modelagem lógica: `docs/domain-modeling/collections/logical-model.md`, bloco **LDM-175 a LDM-185** — não duplicada linha a linha aqui; esta seção é um resumo narrativo orientado a quem consulta a documentação física do módulo Collections. Decisão de escopo/elegibilidade em `ADR-011-pokemon-tcg-domain-scope.md` (atualização v1.2, que revoga o adiamento da entidade Pokémon/Pokémon Species).

## Decisão de Modelagem (conceitual/lógica — sem estrutura física)

**Identidade de base.** Uma Pokédex Position referencia exatamente uma Pokémon Species (não uma Card, não um Set) — a mesma entidade de identidade mínima já descrita em `04-domain-model.md` (renomeada "Pokémon" → "Pokémon Species" nesta mesma rodada). Cards de Form/Variety satisfazem a Position da Species base, sem criar uma Position própria.

**Collection Pokédex Scope (supersede de LDM-16).** O Scope de uma Collection Pokédex deixa de ser adotado posição-a-posição (modelo antigo, individualmente-adotado) e passa a ser `FULL_REFERENCE` (padrão, todas as Species conhecidas) ou `GENERATION_FILTERED` (1..N Generations selecionadas) — as Pokédex Positions são sempre **derivadas** do Scope, nunca uma lista adotada manualmente item a item. Mudar o Scope recalcula a completude sem apagar Physical Cards, Allocations ou Position Assignments já existentes; uma Assignment feita fora do Scope corrente permanece preservada, apenas não conta para a completude enquanto o Scope não a inclui — mesmo princípio não-destrutivo já usado por `completion_policy` (C-23/LDM-22) e por Master Set Scope (LDM-21).

**Species Match / Mismatch (supersede da cláusula Pokédex de LDM-17).** O antigo bloqueio duro de elegibilidade é substituído por uma verificação silenciosa: quando a Card alocada corresponde à Species da Position (Species Match), a Assignment é criada sem aviso, com `assignment_basis = SPECIES_MATCH`. Quando não corresponde, não possui Species, ou é uma Card de Trainer/Energy, o sistema exige aviso e confirmação explícita do usuário antes de prosseguir, com `assignment_basis = USER_OVERRIDE` — nunca um bloqueio impeditivo. `USER_OVERRIDE` é local à Collection, conta normalmente para a completude, e nunca altera o catálogo editorial.

**Pokédex Position Assignment** (conceito lógico introduzido nesta rodada de 2026-09-03; **materializado fisicamente na Fatia D, 2026-09-06** — `collection_pokedex_position_assignment`, Queries `6117`–`6126`, ver subseção própria abaixo). Ocupar uma posição fisicamente (Allocation) não é suficiente por si só — é necessária uma Assignment explícita associando um Physical Card a uma Position dentro de uma Collection Pokédex. Uma Position pode ter N Assignments (múltiplos exemplares); um Physical Card pode ter no máximo uma Assignment por Collection Pokédex; uma Assignment pode existir fora do Scope corrente (preservada, sem contar); remover ou realocar o Physical Card remove a Assignment operacional correspondente; histórico completo via Activity/Audit (mesmo mecanismo já modelado em LDM-154 a LDM-174, não duplicado aqui).

**Primary Representative (novo conceito, apresentacional).** Dentre as Assignments de uma Position, o usuário pode escolher no máximo uma como Primary Representative — opcional, apenas para exibição, sem efeito sobre numerador ou completude. Distinto de Binder Slot Assignment (LDM-35), que é um conceito de layout físico do binder, não de Pokédex.

**Completion de REFERENCE_POSITION (revisão do denominador/numerador).** Denominador = número de Pokédex Positions adotadas (derivadas do Scope); numerador = Positions com pelo menos uma Assignment. Allocation sem Assignment não satisfaz a Position; duplicatas de Physical Card não inflam o numerador; `USER_OVERRIDE` satisfaz normalmente; Primary Representative é irrelevante para o cálculo — mesma disciplina de derivação em tempo de leitura já usada por STANDARD_SET (`collection_completion_summary()`, Query 5070) e por MASTER_SET (Query 5083). **Materializado fisicamente na Fatia E, 2026-09-06** — Queries `5100`–`5103`, ver subseção própria abaixo, que registra a semântica final congelada (numerator = Scope corrente INTERSECT Positions com Assignment).

**Sourcing (PokéAPI + TCGdex + reconciliação editorial MMKYU).** PokéAPI é a fonte estruturada de Pokémon Species/Generation/Pokédex/Position/Form-Variety; TCGdex (já integrada ao catálogo MMKYU via `card_external_reference`) é a fonte de Card e do campo `dexId`, usado para resolver a Primary Species de cada Card. Quando `dexId` é único, é evidência estruturada direta (confirmado empiricamente contra 9 casos reais em `COLLECTIONS-POKEDEX-TCGDEX-DEXID-PROOF-01`, incluindo Mega, Dark, formas regionais e Paradox); quando múltiplo ou ausente, exige reconciliação editorial MMKYU — nunca inferência a partir de `card.name`. Nenhuma API externa é dependência de runtime (ADR-008); o catálogo MMKYU permanece a autoridade em tempo de execução. **Reconciliação editorial ≠ `USER_OVERRIDE`**: a primeira corrige o catálogo (afeta todos os usuários), a segunda é uma escolha local de um usuário dentro de uma Collection. Materializado fisicamente em 2026-09-05 — ver subseção "Card → Primary Species (Fatia C, extensão física, 2026-09-05)" abaixo.

**Correção editorial posterior.** Corrigir a Primary Species de uma Card depois que já existem Assignments baseadas nela não remove a Assignment nem invalida a completude automaticamente — a escolha do usuário é preservada; um mecanismo de sinalização de divergência semântica é reconhecido como possibilidade futura, ainda não desenhado. Fisicamente, a correção UPSERT já existe (`admin_resolve_card_primary_species()`, Query `6114`) — o mecanismo de sinalização de divergência acima permanece futuro, não bloqueante.

**ARCHIVED.** Uma Collection Pokédex arquivada permanece consultável, com a completude derivada ainda computável; Scope, Assignments e Primary Representative tornam-se imutáveis — confirmação do comportamento já estabelecido para Collections em geral, não uma decisão nova desta frente.

## Pokémon Region (extensão física, 2026-09-04)

`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01` (auditoria read-only direta da PokéAPI, `/region/`, 11 regiões — kanto/johto/hoenn/sinnoh/unova/kalos/alola/galar/hisui/paldea/orre) confirmou Pokémon Region como entidade canônica própria, independente de Generation (Orre e Hisui não têm nenhuma Generation principal associada). Fundação física aplicada e promovida em 2026-09-04 via `POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`:

- `pokemon_region` — catálogo raiz (`id`/`code`/`canonical_name`/`is_active`/timestamps), sem FK, mesmo esqueleto de `pokemon_generation`/`pokedex`; triggers normalize/govern/touch_updated_at (Queries `6060`/`6061`).
- `pokemon_region_external_reference` — evidência de integração externa por Fonte, mesmo padrão de `pokemon_species_external_reference`/`pokedex_external_reference`; RLS completamente fechado (Queries `6070`/`6071`).
- `pokemon_generation.main_region_id` — `UUID NOT NULL REFERENCES pokemon_region(id) ON UPDATE RESTRICT ON DELETE RESTRICT` (Query `6080`, v1.1 — ambas as cláusulas RESTRICT declaradas explicitamente, achado de auditoria externa GATE 4). Cardinalidade **N:1**: cada Generation tem exatamente uma Main Region; uma Region pode ser Main Region de 0..N Generations — a unicidade reversa observada hoje (aparentemente 1:1) **não é invariante de domínio**, por isso deliberadamente sem `UNIQUE` e sem índice dedicado nesta rodada (decisão proporcional ao volume, reconhecida pelo Performance Advisor como `unindexed_foreign_keys` INFO). `main_region_id` **não** foi adicionado à lista de campos protegidos por `govern_pokemon_generation()` (Query `6001`, não reescrita) — permanece corrigível a nível de banco; a proteção contra divergência não intencional vive na futura camada de sourcing/reconciliação (classificação DIVERGENT), não em trigger de imutabilidade.

Aplicadas ao banco real na ordem `6060`→`6061`→`6070`→`6071`→`6080`; validação estrutural+comportamental+privilégios de função (Query `6810`, dentro de `BEGIN...ROLLBACK`) confirmada PASS por postcheck independente ao vivo — inclui prova simultânea de `confupdtype='r' AND confdeltype='r'` na FK, todas as 5 UNIQUE/CHECK relevantes, zero DML de `service_role` via `has_table_privilege()`, e prova comportamental de N:1 (duas Generations distintas com o mesmo `main_region_id`). Zero resíduo. Após auditoria pós-implementação PASS (GATE 8), as 5 Queries de estrutura (`6060`/`6061`/`6070`/`6071`/`6080`) foram promovidas para `database/schema/` (corpo SQL byte-idêntico ao staging); `6810` não foi promovida — permanece em `database/proposals/2026-09-04-pokemon-region-foundation/` como evidência histórica, mesmo padrão de `6800`. `canonical_name` de Region seguirá `names[language=en]` da PokéAPI no sourcing futuro (ainda SUSPENSO), nunca o slug roteável. Locations, Areas, Version Groups e o grafo de navegação entre Regiões permanecem fora de escopo. Detalhamento lógico completo em `docs/domain-modeling/collections/logical-model.md`, LDM-186 a LDM-190, e `ADR-011` v1.3.

## Collection Pokédex Reference / Adopted Scope (Fatia B, extensão física, 2026-09-05)

**IMPLEMENTED / VALIDATED / CLOSED** (`COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-MODELING-AUDIT-01` → `-REVISION-01` → `-IMPLEMENTATION-01` → `-CANONICAL-PROMOTION-01`). Materializa fisicamente o par de conceitos já fechados na subseção "Decisão de Modelagem" acima — `collection_pokedex_reference` (subtipo POKEDEX de `collection_reference`, mesma família supertipo/subtipo de `collection_card_set_reference`, 02D) e o Collection Pokédex Scope (`FULL_REFERENCE`/`GENERATION_FILTERED`, LDM-177) — mais a correção REVISION-01 de que `completion_policy = 'REFERENCE_POSITION'` é a identidade física correta (não `'NONE'`, que mentiria sobre a política real; o cálculo de completion em si permanece integralmente responsabilidade de uma futura Fatia E).

Quinze Queries `5085`–`5099`:

- `5085` — alarga `chk_collection_reference_kind` para aceitar `'POKEDEX'` (era só `'CARD_SET'`).
- `5086` — alarga `chk_collection_completion_policy` para aceitar `(REFERENCE_BASED, REFERENCE_POSITION)`, pré-requisito da correção REVISION-01.
- `5087` — tabela `collection_pokedex_reference` (PK = FK 1:1 para `collection_reference`, `pokedex_id`, `scope_kind` `DEFAULT 'FULL_REFERENCE'`), RLS SELECT-própria, `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` já revogados de `service_role` na própria migration de criação (diferente do débito legado registrado abaixo).
- `5088` — trigger de `updated_at`.
- `5089` — trigger de identidade estrutural (bloqueia `UPDATE` de `collection_reference_id`).
- `5090` — trigger de Game Gate (só Game `code = 'POKEMON'`) + lock (`pokedex_id` imutável após `reference_locked_at`) — `scope_kind` explicitamente fora do lock.
- `5091` — tabela `collection_pokedex_scope_generation` (PK composta `collection_reference_id`+`generation_id`, insert/delete-only, sem `adopted_at`/`adopted_by_user_id` — sem proveniência por linha a preservar, ao contrário de `collection_master_set_scope`).
- `5092` — **incorporada ao arquivo canônico `database/schema/5057_create_collection_reference_consistency_trigger.sql` (bumped para v1.1)**, não promovida como arquivo `5092_*.sql` isolado (mesmo padrão "dobra" já usado em `5032`/`5042`/`5045`/`5046`): acrescenta o ramo `POKEDEX` a `check_collection_reference_subtype_consistency()`.
- `5093` — segundo lado do enforcement diferido supertipo/subtipo, espelhando `5058` para o subtipo POKEDEX.
- `5094` — helper `check_collection_pokedex_scope_presence()`, compartilhado pelos dois lados do enforcement de presença.
- `5095` — trigger de elegibilidade imediata (`BEFORE INSERT`) em `collection_pokedex_scope_generation`.
- `5096`/`5097` — enforcement diferido de presença (`CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED`), lado Reference (`5096`) e lado Generation/`ON DELETE` (`5097`) — mesmo par que `5076`/`5077` para MASTER_SET.
- `5098` — RPC `create_reference_based_pokedex_collection()` (única via de criação, grava `completion_policy = 'REFERENCE_POSITION'`).
- `5099` — RPC `set_collection_pokedex_scope()` (única via de troca de Scope, substituição total DELETE+INSERT em vez de diff KEEP/ADD/REMOVE).

Aplicadas ao banco real na ordem exata `5085`→`5099`, uma por vez, via MCP do Supabase (projeto `qjfutqujxrbzgrtkpgkg`); postcheck físico independente confirmou estrutura, triggers, RLS e privilégios (`EXECUTE`/`GRANT`/`REVOKE`) conforme especificado, com testes funcionais em `BEGIN...ROLLBACK` cobrindo criação FULL_REFERENCE e GENERATION_FILTERED, troca de Scope, rejeição de Game não-Pokémon e o round-trip completo de presença. Zero resíduo. Após o postcheck, as 15 Queries foram promovidas para `database/schema/` (13 arquivos novos + a extensão v1.1 de `5057`) — pasta de staging `database/proposals/2026-09-05-collections-pokedex-fatia-b-scope/` mantida integralmente como evidência histórica/auditoria, sem alteração.

**Débito registrado, não corrigido nesta rodada:** as 5 tabelas legadas de Collection (anteriores a este padrão) ainda concedem a `service_role` privilégios estruturais (`TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN`) que já foram fechados desde a origem em todas as tabelas novas desta Fatia B — item separado, não bloqueante, ver README de staging para o detalhe completo.

## Card → Primary Species (Fatia C, extensão física, 2026-09-05)

**CONFIRMADO EXECUTADO** (`COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-IMPLEMENTATION-01-RESUME` (backfill) → `-INCREMENTAL-INTEGRATION-AUDIT-01`/`-REVISION-01`/`-FINAL-CHECK-01` → `-INCREMENTAL-IMPLEMENTATION-01` → `-CANONICAL-CLOSEOUT-01`). Materializa fisicamente a resolução de Primary Species de uma Card (LDM-182/LDM-183 acima) via seis Queries:

- `2159` — alarga as três `CHECK`s de `catalog_admin_action_log` (Query `2010`) para acomodar as duas novas actions desta frente (`CARD_PRIMARY_SPECIES_RESOLVED`/`CARD_PRIMARY_SPECIES_CORRECTED`), o novo `entity_type` `CARD_PRIMARY_SPECIES` e o ramo action↔entity_type correspondente — migration incremental que reconcilia o estado físico real da tabela (29 actions / 11 entity_types / 11 ramos); `2010` permanece no repositório apenas como a migration de criação original, não reflete mais o estado atual das CHECKs sozinha.
- `6112` — tabela `card_primary_species` (PK = FK 1:1 para `card`, `pokemon_species_id` FK para `pokemon_species`, `resolution_basis` `CHECK`'d a `AUTOMATIC_DEXID`/`EDITORIAL_RECONCILIATION` com acoplamento obrigatório a `resolved_by_user_id`/evidência), RLS SELECT-própria, `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` já revogados de `service_role` desde a criação.
- `6113` — três triggers: `trg_010` (`BEFORE INSERT`, exige `card.category_id` = `POKEMON`), `trg_020` (governança de imutabilidade de `card_id`/`created_at` — `pokemon_species_id`/`resolution_basis`/`source_evidence` deliberadamente corrigíveis), `trg_030` (`updated_at`).
- `6114` — `admin_resolve_card_primary_species()`, único caminho de escrita individual/editorial (UPSERT), sempre grava `resolution_basis = 'EDITORIAL_RECONCILIATION'` e `resolved_by_user_id = auth.uid()` — usada tanto para a primeira resolução manual quanto para correção de uma resolução já existente (automática ou editorial).
- `6115` — `resolve_card_primary_species_bulk()`, único caminho de escrita automática em lote (`SERVICE_ROLE ONLY`, guard `c_max_batch_size = 10000`), nunca faz `UPDATE` — apenas `INSERT` quando não existe linha; correções automáticas sobre resolução já existente nunca acontecem por aqui (ficam para `6114`, editorial).
- `6116` — `resolve_card_primary_species_for_catalog_import_job()`, orquestração pós-confirmação de um job de importação: filtra `catalog_import_job.source = 'TCGDEX'` (outra fonte retorna `SOURCE_NOT_TCGDEX`, zero escrita — `source != 'TCGDEX'` nunca é interpretado como evidência TCGdex), extrai `dexId` de `catalog_import_row.raw_data` para as Cards POKEMON do job vinculadas via `resulting_card_id` (**nunca** `matched_card_id` — este último é ruído histórico, proibido para esta finalidade) e delega a escrita inteira à Query `6115`.

**Dois callers reais, ambos não-bloqueantes** (erro de resolução de Species nunca vira erro de importação/revalidação): (A) `confirmarImportacao()` em `web/app/catalogo/importar-cartas/tcgdex/actions.ts` chama `6116` uma única vez, após todo o loop de confirmação em lotes, via client `supabase` padrão; (B) o handler de `supabase/functions/revalidate-catalog-import-rows/index.ts` chama `6116` logo após `confirmCatalogImport()` ter sucesso, usando `userClient` (nunca service role). Novos imports TCGdex, a partir desta rodada, resolvem a Primary Species automaticamente após a confirmação, sem intervenção manual quando o `dexId` é único.

**Backfill do catálogo existente** (`COLLECTIONS-POKEDEX-FATIA-C-BACKFILL-APPLY-01`, 2026-09-05): das `6435` Cards `POKEMON` ativas no catálogo, `5675` foram resolvidas automaticamente (`AUTOMATIC_DEXID`, cobertura inicial de **88,19%**), vinculadas exclusivamente via `resulting_card_id`; as `760` restantes (dexId ausente ou múltiplo) permanecem pendentes de reconciliação editorial via `6114`, sem bloqueio de nenhuma funcionalidade existente. Executado com guard de divergência, dentro de transação com validação prévia (dry run) e zero resíduo pós-aplicação.

Aplicadas ao banco real na ordem `2159`→`6112`→`6113`→`6114`→`6115`→`6116`; postcheck estrutural/segurança e 26 cenários de teste funcional (`BEGIN...ROLLBACK`) confirmaram PASS. Edge Function `revalidate-catalog-import-rows` reimplantada com sucesso no projeto `qjfutqujxrbzgrtkpgkg` (versão 9, `ACTIVE`) contendo o novo Fluxo B. As 6 Queries promovidas para `database/schema/` (corpo SQL byte-idêntico ao executado, apenas cabeçalho Status/Versão/Data atualizados); `database/proposals/2026-09-05-fatia-c-card-primary-species/` e `database/proposals/2026-09-05-fatia-c-incremental-integration/` mantidas integralmente como evidência histórica de staging. Nenhuma decisão conceitual/lógica reaberta. **Fatia C concluída.**

## Pokédex Position Assignment / Primary Representative (Fatia D, extensão física, 2026-09-06)

**IMPLEMENTED / VALIDATED / CLOSED** (`COLLECTIONS-POKEDEX-FATIA-D-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-STAGING-01` → GATE 4 (`STAGING-AUDIT-01`) → `PAUSE-SQL-DIRECT-AUDIT-01` → `RENUMBER-FIX-STAGING-01` → `6830-DIRECT-REVIEW-FIX-01`/`-FIX-02` → `IMPLEMENTATION-RESUME-02` → `6126-STAGING-01`/`-IMPLEMENT-RESUME-01` → `FINAL-VALIDATION-CLEANUP-01` → `PROMOTION-CLOSEOUT-01`). Materializa fisicamente a Pokédex Position Assignment (LDM-178/LDM-179) e o Primary Representative (LDM-180) já fechados na subseção "Decisão de Modelagem" acima, via dez Queries `6117`–`6126`:

- `6117` — tabela `collection_pokedex_position_assignment` (PK/FK compartilhada `collection_allocation_id`, aproveitando que `collection_allocation.physical_card_id` já é `UNIQUE` globalmente — mesmo padrão supertipo/subtipo de PK compartilhada de `collection_reference`/`collection_pokedex_reference`, 02D), `assignment_basis` (`SPECIES_MATCH`/`USER_OVERRIDE`), RLS SELECT-própria.
- `6118` — três triggers: exigência de ator em `USER_OVERRIDE` no INSERT (`trg_005`), match Position↔Pokédex da Collection (`trg_010`), governança de imutabilidade com a única exceção técnica de `assigned_by_user_id` transicionar para `NULL` via `ON DELETE SET NULL` (`trg_020`) — mover uma Assignment é sempre DELETE+INSERT, nunca `UPDATE` de `pokedex_position_id`.
- `6119` — trigger `AFTER INSERT` em `collection_allocation` que cria a Assignment `SPECIES_MATCH` automaticamente quando a Primary Species da Card corresponde à Species da Position, restrito a Collections `mode = 'REFERENCE_BASED'` explícito.
- `6120` — tabela `collection_pokedex_position_primary_representative` (FKs explícitas para Collection/Position/Assignment, PK composta) — entidade separada, não boolean na Assignment, para evitar denormalizar `collection_id` só para um índice único parcial.
- `6121` — trigger de integridade cruzada Collection+Position (a Assignment referenciada precisa pertencer exatamente à mesma Collection+Position da linha) + `updated_at`.
- `6122` — RPC `set_pokedex_position_assignment()` — cria ou move (DELETE+INSERT na mesma transação).
- `6123` — migration incremental (`CREATE OR REPLACE`) sobre os objetos já vivos (`6118`/`6119`/`6122`) corrigindo `p_confirm_override IS DISTINCT FROM TRUE`, RETURNING/WHERE qualificados contra ambiguidade de OUT-parameters, lock Collection-first, e `REFERENCE_BASED`/`POKEMON` explícitos.
- `6124` — RPC `remove_pokedex_position_assignment()`.
- `6125` — RPCs `set_/clear_pokedex_position_primary_representative()`.
- `6126` — correção incremental de um bug funcional real encontrado em execução (não estrutural): `set_pokedex_position_primary_representative()` falhava com `SQLSTATE 42702` (`ON CONFLICT (collection_id, pokedex_position_id)` colidindo, sob `plpgsql.variable_conflict = 'error'`, com os OUT-parameters de mesmo nome do `RETURNS TABLE`) — corrigido trocando o alvo do conflito para `ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative`.

Nenhuma escrita direta de cliente em nenhuma das duas tabelas — 4 RPCs `SECURITY DEFINER`, `search_path=''`, ownership via `auth.uid()`, `Collection.lifecycle_status = 'ACTIVE'` obrigatório. `Scope` (LDM-177) nunca participa de nenhuma constraint/trigger desta Fatia — uma Assignment fora do Scope corrente permanece preservada, apenas não conta para completude (Fatia E). Desalocar ou mover uma Assignment remove qualquer Primary Representative associado via `ON DELETE CASCADE`, sem trigger de sincronização adicional.

Aplicadas ao banco real na ordem `6117`→`6126`; validação funcional (`6830`, 24 casos) confirmou PASS em todos, exceto o Caso 20b (concorrência lifecycle, `NOT EXECUTED / UNPROVEN` — ambiente sem duas sessões persistentes simultâneas, aprovado como tal). Cleanup de fixtures da bateria de testes executado com zero-resíduo confirmado por identidade; postcheck estrutural/segurança pós-cleanup confirmou os objetos intactos. As 10 Queries promovidas para `database/schema/` (corpo SQL byte-idêntico ao executado, apenas cabeçalho Status/Versão/Data atualizados); `database/proposals/2026-09-05-fatia-d-position-assignment/` mantida integralmente como evidência histórica de staging/validação (`6830` não é schema, não promovido). **Fatia D concluída.**

## REFERENCE_POSITION Completion & Scope Positions read model (Fatia E, extensão física, 2026-09-06)

**IMPLEMENTED / LIVE / VALIDATED / PERFORMANCE-MEASURED / CLOSED tecnicamente.** Quatro Queries, dois objetos, **nenhuma tabela nova, nenhuma coluna nova, nenhum índice novo, nenhuma denormalização**:

- `5100` — `CREATE OR REPLACE` de `collection_completion_summary()` (canônica em `5083` v3.0), acrescentando um **terceiro ramo mutuamente exclusivo** (`REFERENCE_POSITION`) com quatro CTEs novas e independentes (`reference_position_target`, `reference_position_scope`, `reference_position_denom`, `reference_position_numer`) e estendendo os dois `UNION ALL` finais de 2 para 3 branches. `target`/`standard_denom`/`standard_numer`/`master_denom`/`master_numer`/SELECT final preservados byte-idênticos — regressão zero de STANDARD_SET/MASTER_SET, provada nos Casos N/O de `5814`.
- `5101` — nova função `public.collection_pokedex_scope_positions(p_collection_id UUID, p_only_missing BOOLEAN DEFAULT FALSE)`, espelho direto de `collection_master_set_scope_positions()` (`5084`). Contrato de 5 campos: `pokedex_position_id`, `position_number`, `species_id`, `species_name`, `is_satisfied`; `ORDER BY position_number, pokedex_position_id`.
- `5102` — remediação de performance do corpo de `collection_completion_summary()` (ver abaixo).
- `5103` — remediação de performance do corpo de `collection_pokedex_scope_positions()`.

Segurança idêntica ao padrão já vigente nas demais funções de completion: `LANGUAGE sql`, `STABLE`, `SECURITY DEFINER`, `SET search_path = ''`, owner `postgres`, ownership reconstituído explicitamente em **cada** target CTE (`auth.uid() IS NOT NULL`, nunca `is_admin()`), `REVOKE ALL FROM PUBLIC`/`anon` + `GRANT EXECUTE TO authenticated`. Não-enumeração preservada: Collection inexistente, de outro Owner, `mode` diferente de `REFERENCE_BASED` ou `completion_policy` diferente de `REFERENCE_POSITION` → 0 linhas, nunca erro.

### Semântica final congelada

- **Denominator** = Positions do **Scope corrente** da Collection (LDM-177). `FULL_REFERENCE` = todas as `pokedex_position` da Pokédex referenciada; `GENERATION_FILTERED` = as Positions cujas Species pertencem às Generations do Scope, casadas por `generation_id` **e** `collection_reference_id` (nunca vaza para outra Collection). Os dois ramos são mutuamente exclusivos por construção.
- **Numerator** = **Scope corrente INTERSECT Positions com ≥1 Assignment da própria Collection** (LDM-181). Nunca a contagem bruta de Assignments.
- **Duplicatas nunca inflam completion.** N Physical Cards distintas satisfazendo a MESMA Position contam a Position **uma** vez.
- **`SPECIES_MATCH` e `USER_OVERRIDE` contam igualmente** — nenhum filtro em `assignment_basis` em nenhuma das duas funções.
- **Assignment fora do Scope é preservada, mas não conta no Scope atual.** Permanece fisicamente na tabela; não entra no denominator, no numerator nem no read model.
- **Primary Representative não interfere em completion** (LDM-180). Criar, trocar entre duas Assignments da mesma Position, ou remover o Primary Representative deixa os 5 campos do summary idênticos. `collection_pokedex_position_primary_representative` e `card_primary_species` **nunca** são consultados por estas funções.
- **Alteração de Scope não destrói Assignment** (LDM-177/LDM-181). Mutar o Scope recalcula completion sem tocar nenhuma Assignment; reativar o Scope anterior faz as Assignments preservadas voltarem a ser contadas, sem criar nada novo.
- **`collection_pokedex_scope_positions()` é o read model básico** de Position/Species/`is_satisfied` — sem Primary Representative, sem `assignment_count`, sem Physical Card, sem Card/Card Variant, sem nenhum dado de UX.

### Blocker de performance e remediação (query-shape)

O primeiro `5815` mediu as funções contra a Pokédex **NATIONAL real (1025 Positions)** e encontrou um **BLOCKER**: custo proporcional ao **produto** `|Scope| × |Allocations da Collection|`, com constante de **~3,02 shared blocks por par**, estável em quatro estados independentes separados por duas ordens de grandeza (desvio < 0,5%). FULL_REFERENCE 1025 Positions / 828 Allocations: **~1,36 s e ~2,56 M shared hits**.

**Causa: query-shape, não índice.** Em `reference_position_numer` (e na CTE `satisfied` de `5101`), o Scope e `collection_allocation` eram **irmãos** — ambos ligados apenas ao `target` pelo mesmo `collection_id` constante, sem predicado direto entre si; o predicado que os correlaciona vivia numa **terceira** relação. Registro de honestidade de evidência: o plano interno destas funções **não é observável** a partir do `Function Scan` externo do `EXPLAIN` (`INTERNAL PLAN VISIBILITY = NOT OBSERVABLE`); o diagnóstico apoia-se em tempo, buffers, cardinalidade, crescimento entre estados e no grafo de junção lido do corpo live — nenhuma alegação foi feita sobre nós de scan internos.

**Alternativa B, adotada:** pré-calcular as Positions satisfeitas da Collection percorrendo `collection_allocation → collection_pokedex_position_assignment` (**sem tocar o Scope**) e só então intersectar com o Scope corrente. Θ(\|Scope\| + \|Allocations\|) no lugar de Θ(\|Scope\| × \|Allocations\|), usando exclusivamente índices já existentes — `ix_collection_allocation_collection` e a PK única `collection_pokedex_position_assignment_pkey` (que garante no máximo 1 Assignment por Allocation).

Alternativas descartadas com evidência: **`EXISTS` dirigido pelo Scope** não corrige a assintótica com os índices atuais (ou revarre `|Allocations|` por Position — mesmo produto — ou passa a depender do volume **global** de Assignments daquela Position em todas as Collections do banco); **índice composto** é impossível isoladamente, porque as duas colunas que precisariam ser combinadas (`collection_allocation.collection_id` e `collection_pokedex_position_assignment.pokedex_position_id`) vivem em **tabelas diferentes** — só funcionaria denormalizando `collection_id` na tabela de Assignment, colidindo com o contrato de Assignment imutável fechado na Fatia D.

### Evidência

| Artefato | Resultado |
|----------|-----------|
| `5814` v1.3 contra `5100`/`5101` | **87/87 PASS**, zero resíduo |
| `5816` v1.1 (A/B transacional, gate fail-closed) | **CANDIDATE PASS** — 13/13 de equivalência semântica (`EXCEPT` nos dois sentidos + igualdade de contagem bruta) |
| `5814` v1.3 contra `5102`/`5103`, reexecutado inalterado | **86/87 PASS** — único FAIL = id 8 (POSTCHECK-2c), **falso-positivo textual** (`_` como wildcard em `ILIKE` + token literal dentro de comentário de `5103`) |
| `5817` v1.0 | **1/1 PASS** — substitui exclusivamente a evidência do id 8, por comparação **literal** com `position()` sobre o source com comentários removidos |
| `5815` v1.2 final, contra as funções live | **13 HEALTHY / 0 ATTENTION / 0 BLOCKER** |

Performance final: high-density em **4,7–8,8 ms** (reduções de 154× a 306× em tempo, ~1008–1010× em buffers), maior shared hit = **2 685**, `shared read = 0` em todos os workloads. **Custo marginal por Allocation invariante ao Scope**: 3,04 blocks num Scope de 1025 vs. 3,015 num Scope de 156 (antes da remediação: 3 095,5 vs. 470,3 — razão idêntica à dos Scopes).

`5100`–`5103` promovidas para `database/schema/` com o **histórico incremental preservado e não foldado** (`5100 → 5102`, `5101 → 5103`). `5814`/`5815` permanecem em `database/proposals/2026-09-06-fatia-e-reference-position-completion/` e `5816`/`5817` em `database/proposals/2026-09-06-fatia-e-performance-remediation/` como evidência de validação/performance. **Fatia E concluída.**

## Product / UX Traceability — Pokédex

> **O que esta seção é.** Memória de produto: o significado das decisões **já implementadas e congeladas** nas Fatias A–E, registrado aqui para que as futuras fases de read models de UX e de frontend não percam o contexto.
>
> **O que esta seção não é.** Não cria fase nova, não antecipa Binder, não define wireframes nem componentes, e não compromete nenhuma decisão de interface. Nenhum item abaixo é proposta — todos descrevem comportamento **já vigente no banco**.

1. **UX North Star — do FLUXO MANUAL.** No fluxo conduzido pelo usuário, ele escolhe a **Position** e o sistema encontra as Physical Cards elegíveis: a direção é Position → Card, não Card → Position. Isso descreve a *interação humana* e **não elimina automações determinísticas do domínio** — ver os itens 2 e 3.
2. **Allocation ≠ Position Assignment.** São **relações distintas e materializadas separadamente**: alocar uma Physical Card a uma Collection (`collection_allocation`) não é o mesmo que vinculá-la a uma Position da Pokédex (`collection_pokedex_position_assignment`). Completion **sempre** consulta a Assignment — a existência da Allocation, por si só, nunca é o critério. **Porém a Allocation pode disparar automaticamente a criação da Assignment** (Query `6119`, trigger `AFTER INSERT` em `collection_allocation`): ela *causa* a Assignment, não *substitui* a Assignment.
3. **`SPECIES_MATCH` inequívoco é automático.** Quando a Collection é Pokédex (`mode = REFERENCE_BASED` + `reference_kind = POKEDEX`) e a Primary Species da Card corresponde inequivocamente a uma Position do Pokédex referenciado, a Assignment é criada **automaticamente logo após a Allocation**, sem confirmação humana, com `assignment_basis = SPECIES_MATCH` e `assigned_by_user_id = NULL` (Query `6119`). Se a automação não ocorreu, a mesma Assignment `SPECIES_MATCH` pode ser criada depois pelo **fluxo manual/RPC** (`set_pokedex_position_assignment()`, Query `6122`) — os dois caminhos produzem o mesmo `assignment_basis`.
4. **Sem match inequívoco, a automação não faz nada — e `USER_OVERRIDE` é sempre humano.** Mismatch de Species, Card sem `card_primary_species` resolvida, Card de categoria TRAINER/ENERGY, Species fora do Pokédex referenciado: a automação **não cria Assignment, não cria `USER_OVERRIDE` e não gera erro** — apenas não faz nada. `USER_OVERRIDE` **nunca** nasce automaticamente; exige confirmação explícita do usuário via RPC.
5. **`USER_OVERRIDE` é local à Collection.** Nunca altera o Catálogo global nem `card_primary_species`.
6. **Múltiplas Physical Cards podem representar a mesma Position.** Completion conta a Position uma única vez, independentemente de quantas Cards a satisfaçam.
7. **Primary Representative define representação visual, não completion.** É opcional (0..1 por Position), nunca criado automaticamente, e não altera nenhum campo de progresso.
8. **Estreitar o Scope preserva as Assignments que ficaram de fora.** Nada é destruído. A automação de `6119` **não filtra por Scope**: uma auto-Assignment pode nascer fora do Scope corrente — é preservada fisicamente, mas **não conta no completion** enquanto a Position estiver fora do Scope.
9. **Reativar um Scope traz de volta as Assignments preservadas.** Elas voltam a contar sem que nada precise ser recriado.
10. **Binder Slot (futuro) ≠ Pokédex Position Assignment.** São relações de domínios diferentes e não devem ser confundidas nem unificadas ao modelar o Binder.

## Pendências / Próximos Passos

**Pokémon Species/Generation físicas desde 2026-09-04** (`pokemon_generation`, `pokemon_species`, `pokemon_species_external_reference` — Queries `6000`–`6021`/`6700`, ver `docs/standards/STD-001-database-standards.md`). **`pokedex`/`pokedex_position`/`pokedex_external_reference` físicas desde 2026-09-04** (Fatia A, Queries `6030`–`6051`) e **`pokemon_region`/`pokemon_region_external_reference`/`pokemon_generation.main_region_id` físicas desde 2026-09-04** (Pokémon Region Foundation, Queries `6060`–`6080`, ver subseção acima). **Estas tabelas não estão mais vazias**: o Initial Load do Pokémon Catalog via PokéAPI foi executado e fechado em 2026-09-05 — `11` Regions, `9` Generations, `1025` Species, `1` National Pokédex e `1025` Positions, com idempotência confirmada por segundo ciclo real. Contagens, `snapshot_hash`, run lifecycle e critérios PASS são canônicos em `docs/06a-pokemon-catalog-sourcing.md`; não duplicados aqui. **`collection_pokedex_reference`/`collection_pokedex_scope_generation` físicas e IMPLEMENTED/VALIDATED/CLOSED desde 2026-09-05** (Fatia B, Queries `5085`–`5099`, ver subseção acima) — 0 linhas cada, nenhuma Collection Pokédex real criada ainda. **`card_primary_species` física e CONFIRMADO EXECUTADO desde 2026-09-05** (Fatia C, Queries `2159`/`6112`–`6116`, ver subseção acima) — `5675`/`6435` Cards POKEMON resolvidas automaticamente (88,19%), `760` pendentes editoriais. **`collection_pokedex_position_assignment`/`collection_pokedex_position_primary_representative` físicas e IMPLEMENTED/VALIDATED/CLOSED desde 2026-09-06** (Fatia D, Queries `6117`–`6126`, ver subseção acima) — 0 linhas em produção (nenhuma Collection Pokédex real ainda). **`collection_completion_summary()` (ramo `REFERENCE_POSITION`) e `collection_pokedex_scope_positions()` vivas e IMPLEMENTED/VALIDATED/PERFORMANCE-MEASURED/CLOSED desde 2026-09-06** (Fatia E, Queries `5100`–`5103`, ver subseção acima) — nenhuma tabela/coluna/índice novos; 0 linhas em produção (nenhuma Collection Pokédex real ainda). Ainda não iniciado: Pokémon Form/Variety. **Próxima frente do projeto: Binder/Layout Foundation.** Sem bloqueio de nenhuma decisão já tomada.

---

# User Profile (Perfil de Usuário) / Reserved Username

## Status

**Camada Identidade e Acesso criada, semeada e homologada nesta revisão — Incremento 1 ("Meu Perfil") do módulo, `1000`–`1040`/`1710`/`1800`–`1840` CONFIRMADOS EXECUTADOS.** Primeira entidade fora do Catálogo Editorial, motivada pela decisão de arquitetura frontend (ADR-019) e formalizada em ADR-020 (User Profile and Username Identity Model). Introduz o Modelo Modular de Numeração (STD-001, Seção 10): esta é a primeira entidade do milhar `1000–1999`.

## Decisão de Modelagem

`user_profile` separa identidade de negócio (nome, avatar, username) da autenticação (`auth.users`, gerida pelo Supabase Auth) — ver ADR-020. Relação 1:1 via `id` compartilhado. `username` é a identidade pública, única e estável do usuário (imutável pelo próprio usuário); `display_name` é livremente editável. `reserved_username` é uma tabela de apoio (não uma entidade de domínio), consultada apenas por functions `SECURITY DEFINER`, sem acesso direto via API.

## Modelo Físico — `user_profile` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.user_profile (
    id            UUID PRIMARY KEY
                  REFERENCES auth.users(id)
                  ON DELETE CASCADE,
    username      TEXT NOT NULL,
    display_name  TEXT NOT NULL,
    avatar_path   TEXT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT user_profile_username_unique
        UNIQUE (username),
    CONSTRAINT user_profile_username_format
        CHECK (username ~ '^[a-z0-9_]{3,20}$'),
    CONSTRAINT user_profile_display_name_length
        CHECK (char_length(trim(display_name)) BETWEEN 1 AND 60)
);

ALTER TABLE public.user_profile
    ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: `username` minúsculo, 3–20 caracteres (letras, números, underscore), único, imutável após criado (garantido por trigger, não pela tabela em si); `display_name` sempre gravado já com `trim`; `avatar_path` guarda o caminho relativo dentro do bucket `avatars` (Query `1040`), não a URL pública completa (derivada em runtime); RLS habilitado. Confirmado executado por Fabrício (estrutura e colunas conferidas via `information_schema`). Arquivo em `database/schema/1000_create_user_profile_table.sql`.

## Query `1001` — Create User Profile Trigger (CONFIRMADO EXECUTADO)

Mantém `updated_at` atualizado, reaproveitando `public.set_updated_at()` — mesmo padrão de toda a base. Confirmado via `information_schema.triggers`. Arquivo em `database/schema/1001_create_user_profile_trigger.sql`.

## Query `1002` — Create User Profile Invariants Trigger (CONFIRMADO EXECUTADO)

Function `enforce_user_profile_invariants()` + trigger `BEFORE INSERT OR UPDATE`: normaliza `display_name` (`trim`) incondicionalmente e bloqueia qualquer alteração de `username` (`RAISE EXCEPTION`), sem válvula de exceção — imutabilidade total nesta fase, por decisão explícita de Fabrício. Uma futura correção administrativa será modelada apenas quando existir papel administrativo aprovado (ver ADR-020), sem reabrir este trigger. Confirmado via `information_schema.triggers` (três linhas: `enforce_invariants` em INSERT e UPDATE, `set_updated_at` em UPDATE). Arquivo em `database/schema/1002_create_user_profile_invariants_trigger.sql`.

## Query `1003` — Create User Profile RLS Policies (CONFIRMADO EXECUTADO)

`user_profile_select_own`/`user_profile_update_own`, ambas restritas a `auth.uid() = id`. Sem política de `INSERT`/`DELETE` — a única via de criação é o trigger da Query `1020` (roda como dono da function, ignora RLS). Confirmado via `pg_policies`. Arquivo em `database/schema/1003_create_user_profile_rls_policies.sql`.

## Modelo Físico — `reserved_username` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.reserved_username (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username   TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.reserved_username ENABLE ROW LEVEL SECURITY;
```

Tabela de apoio, não uma entidade de domínio — sem política de RLS para `anon`/`authenticated` (só as functions `SECURITY DEFINER` a leem). Confirmado executado. Arquivo em `database/schema/1010_create_reserved_username_table.sql`; trigger de `updated_at` em `1011` (mesmo padrão, confirmado via `information_schema.triggers`, arquivo `database/schema/1011_create_reserved_username_trigger.sql`).

## Query `1710` — Seed Reserved Username (v1.1, CONFIRMADA EXECUTADA)

Carga idempotente (`ON CONFLICT (username) DO NOTHING`) com 50 termos reservados (`admin`, `suporte`, `sistema`, `perfil`, `me`, `about`, entre outros) — nenhum usuário pode reivindicá-los como `username`. v1.0 tinha 48 termos; v1.1 acrescenta `me` (rotas futuras como `/me`, `/api/me`) e `about` (rota institucional comum), sugeridos por Fabrício após a execução original e já aplicados incrementalmente ao banco antes desta consolidação. Confirmado: `count(*) = 48` na execução original, lista conferida termo a termo contra a intenção. Arquivo em `database/seeds/1710_seed_reserved_username.sql`.

## Query `1020` — Create `handle_new_user()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, trigger `AFTER INSERT ON auth.users`: popula `user_profile` a partir de `raw_user_meta_data` (`username`/`display_name` enviados pelo formulário via `options.data` do `signUp()`), tratado como dado não confiável — normalizado e revalidado no próprio trigger (formato, reservados, presença). Qualquer falha cancela a transação inteira do `INSERT` em `auth.users`: a partir desta Query, nunca existe usuário sem perfil. `EXECUTE` revogado de `PUBLIC` — só o próprio trigger invoca. Confirmado: `prosecdef = true`, trigger correto em `auth.users`, `anon`/`authenticated` sem `EXECUTE`. Arquivo em `database/schema/1020_create_handle_new_user_function.sql`.

**Limitação de MVP documentada em ADR-020**: esta function assume que `username` sempre vem em `raw_user_meta_data`, o que só é verdade no cadastro por e-mail/senha controlado pelo próprio formulário. Login social (OAuth) não popula esse campo — precisará de um fluxo de onboarding pós-login, não implementado nesta fase.

**Achado real desta revisão**: a conta de teste de Fabrício (criada antes desta Query existir) ficou sem `user_profile` — detectado pela checagem de inconsistência da Query `1800`. Decisão tomada: excluir a conta de teste via painel do Supabase (Authentication → Users) e recriá-la pelo fluxo real assim que o frontend estiver pronto, em vez de criar um perfil manualmente ou deixar a conta órfã.

## Query `1030` — Create `username_available()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, retorno estritamente `BOOLEAN`, chamável por `anon`/`authenticated` (checagem de disponibilidade durante o cadastro, antes de existir sessão). Documentada explicitamente como antecipação de UX sujeita a condição de corrida — a autoridade final continua sendo o `UNIQUE` de `user_profile`, verificado no `INSERT` real da Query `1020`. Testado com três casos reais: `'admin'` → `false` (reservado), `'ab'` → `false` (formato inválido), `'fabricio_teste'` → `true` (disponível). Arquivo em `database/schema/1030_create_username_available_function.sql`.

## Query `1040` — Create bucket `avatars` (CONFIRMADO EXECUTADO)

Bucket Supabase Storage dedicado a avatares: leitura pública (única exceção aprovada), escrita restrita à própria pasta do usuário (`<uid>/<arquivo>`), MIME `image/png`/`image/jpeg`/`image/webp`, limite de 2 MB. Toda política em `storage.objects` filtra `bucket_id = 'avatars'` explicitamente (tabela compartilhada entre todos os buckets do projeto). Confirmado: bucket e as quatro políticas (`avatars_public_read`/`avatars_insert_own_folder`/`avatars_update_own_folder`/`avatars_delete_own_folder`) conferidos via `storage.buckets`/`pg_policies`. Arquivo em `database/schema/1040_create_avatars_bucket.sql`.

## Query `1004` — Grant User Profile Privileges (CONFIRMADO EXECUTADO)

**Bug real encontrado durante a integração do frontend (2026-07-26)**: `/perfil` retornava `permission denied for table user_profile` (`code 42501`) mesmo com as políticas de RLS da Query `1003` corretas. Causa: RLS restringe linhas, mas pressupõe que o privilégio de tabela já exista — o `GRANT` de base para o role `authenticated` nunca tinha sido emitido (mesma classe de lacuna já vista antes neste projeto com `service_role`/Edge Functions, ver revisão `0.69`, migration `272`). Corrigido com `GRANT SELECT, UPDATE ON public.user_profile TO authenticated;`, espelhando exatamente as duas políticas de RLS existentes — nenhum privilégio concedido a `anon` (perfil não é público neste incremento) nem `INSERT` (a criação da linha continua exclusiva de `handle_new_user()`, que roda como `SECURITY DEFINER`). Confirmado via `information_schema.role_table_grants`: `authenticated` com `SELECT`/`UPDATE`, `anon` sem nenhum dos dois. Arquivo em `database/schema/1004_grant_user_profile_privileges.sql`.

## Sequência

```text
1000 - Create User Profile table                       (CONFIRMADO EXECUTADO — database/schema/1000_create_user_profile_table.sql)
1001 - Create User Profile trigger                      (CONFIRMADO EXECUTADO — database/schema/1001_create_user_profile_trigger.sql)
1002 - Create User Profile invariants trigger           (CONFIRMADO EXECUTADO — database/schema/1002_create_user_profile_invariants_trigger.sql)
1003 - Create User Profile RLS policies                 (CONFIRMADO EXECUTADO — database/schema/1003_create_user_profile_rls_policies.sql)
1004 - Grant User Profile privileges                    (CONFIRMADO EXECUTADO — database/schema/1004_grant_user_profile_privileges.sql)
1010 - Create Reserved Username table                   (CONFIRMADO EXECUTADO — database/schema/1010_create_reserved_username_table.sql)
1011 - Create Reserved Username trigger                 (CONFIRMADO EXECUTADO — database/schema/1011_create_reserved_username_trigger.sql)
1020 - Create handle_new_user function and trigger      (CONFIRMADO EXECUTADO — database/schema/1020_create_handle_new_user_function.sql)
1030 - Create username_available function                (CONFIRMADO EXECUTADO — database/schema/1030_create_username_available_function.sql)
1040 - Create avatars bucket and storage policies         (CONFIRMADO EXECUTADO — database/schema/1040_create_avatars_bucket.sql)
1710 - Seed Reserved Username (v1.1, 50 termos)           (CONFIRMADA EXECUTADA — database/seeds/1710_seed_reserved_username.sql)
1800 - Validate User Profile                              (EXECUTADA — database/validations/1800_validate_user_profile.sql)
1810 - Validate Reserved Username                         (EXECUTADA — database/validations/1810_validate_reserved_username.sql)
1820 - Validate handle_new_user                           (EXECUTADA — database/validations/1820_validate_handle_new_user.sql)
1830 - Validate username_available                        (EXECUTADA — database/validations/1830_validate_username_available.sql)
1840 - Validate avatars bucket                            (EXECUTADA — database/validations/1840_validate_avatars_bucket.sql)
```

## Pendências / Próximos Passos

Frontend do Incremento 1 concluído e validado por Fabrício (2026-07-26): cadastro com `username`/`display_name`, tela `/perfil` real (avatar, nome de exibição editável, username bloqueado) — cadastro completo, carregamento de `/perfil`, edição de `display_name` e troca de avatar todos confirmados em produção. Incremento 2 (Administração de Usuários) iniciado — ver seção própria abaixo.

---

# Administração de Usuários

## Status

**Incremento 2, Fases 1–3 (fundação, leitura segura, interface) CONFIRMADAS EXECUTADAS e validadas em produção (2026-07-26).** Segunda entidade do módulo Identidade e Acesso (milhar `1000`–`1999`), formalizada em ADR-021 (Administrative Role Model). Fase 4 (correção administrativa de `username`) deliberadamente fora deste incremento — tratada como incremento futuro separado.

## Decisão de Modelagem

Papel administrativo modelado como presença de linha em `admin_user`, entidade separada de `user_profile` — nunca um atributo booleano nela, para não expor uma coluna autopromovível pelas políticas de RLS de `UPDATE` já existentes. Um único papel (`admin`), sem sistema genérico de papéis/permissões. Todo acesso administrativo passa por functions `SECURITY DEFINER`; `admin_user` e `admin_action_log` têm RLS habilitado e zero políticas — nenhum acesso direto via API, nem para o próprio admin. Ver ADR-021 para o raciocínio completo e as alternativas rejeitadas.

## Modelo Físico — `admin_user` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.admin_user (
    id           UUID PRIMARY KEY
                 REFERENCES auth.users(id)
                 ON DELETE CASCADE,
    granted_by   UUID NULL
                 REFERENCES auth.users(id)
                 ON DELETE SET NULL,
    granted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_user ENABLE ROW LEVEL SECURITY;
```

Sem `updated_at`/trigger: tabela de presença (INSERT/DELETE), não um registro editável. `granted_by` anulável com `ON DELETE SET NULL` — a exclusão futura de quem concedeu o papel nunca invalida a concessão em si. Confirmado via `information_schema`/`pg_tables`. Arquivo em `database/schema/1050_create_admin_user_table.sql`.

## Modelo Físico — `admin_action_log` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    target_user_id   UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    action           TEXT NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT admin_action_log_action_valid CHECK (action IN ('GRANT_ADMIN', 'REVOKE_ADMIN'))
);

ALTER TABLE public.admin_action_log ENABLE ROW LEVEL SECURITY;
```

FKs anuláveis com `ON DELETE SET NULL` (não `CASCADE`): o histórico administrativo sobrevive à exclusão futura de qualquer usuário envolvido — `metadata` grava um retrato (username/e-mail de ator e alvo) capturado no momento da ação, preservando contexto legível mesmo depois que a referência direta vira `NULL`. Ajuste pedido por Fabrício antes da implementação. Confirmado via `pg_constraint`/`pg_tables`. Arquivo em `database/schema/1070_create_admin_action_log_table.sql`.

## Query `1060` — Create `is_admin()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, **sem parâmetro** — verifica somente `auth.uid()`, o usuário da própria sessão. Ajuste pedido por Fabrício antes da implementação: a proposta original aceitava um `p_user_id` arbitrário, permitindo que qualquer usuário consultasse o status administrativo de outro UUID; rejeitado. `EXECUTE` concedido apenas a `authenticated`. Confirmado: `prosecdef = true`, `pronargs = 0`, grants corretos. Testado via SQL Editor retornando `false` (esperado — sem sessão real, `auth.uid()` é `NULL` nesse contexto). Arquivo em `database/schema/1060_create_is_admin_function.sql`.

## Query `1061` — Create `admin_list_users()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER` que lista usuários para fins administrativos — única via de leitura de e-mail (`auth.users`) para esse propósito; o frontend nunca consulta `auth.users` diretamente. Paginada desde a origem (`limit`/`offset`, teto de 100 controlado no servidor), mesmo sem busca/filtros nesta fase — ajuste pedido por Fabrício antes da implementação ("uma listagem ilimitada não é adequada à evolução comercial do sistema"). Retorna `total_count` via `count(*) OVER()` em cada linha, evitando uma segunda chamada para montar a paginação. Campos: `id`, `username`, `display_name`, `avatar_path`, `email`, `created_at`, `is_admin`.

**Bug real encontrado na integração da Fase 3**: `structure of query does not match function result type` (erro `42804`) — `auth.users.email` é `character varying(255)`, não `TEXT`; o `RETURN QUERY` exige tipo exato contra o `RETURNS TABLE` declarado. Corrigido com `au.email::text` (v1.1). Confirmado funcionando a partir do app real, retornando a lista corretamente. Arquivo em `database/schema/1061_create_admin_list_users_function.sql`.

## Query `1062` — Create `admin_grant_admin()` / `admin_revoke_admin()` (CONFIRMADO EXECUTADO)

Functions `SECURITY DEFINER` para conceder/revogar o papel administrativo, ambas exigindo `is_admin()` do chamador. Ambas adquirem a mesma trava consultiva de transação (`pg_advisory_xact_lock`), serializando concessões/revogações concorrentes — ajuste pedido por Fabrício antes da implementação, para que duas revogações simultâneas não possam remover o último administrador ao mesmo tempo. `admin_revoke_admin()` bloqueia explicitamente essa remoção (`RAISE EXCEPTION` se restaria zero administradores). Ambas gravam em `admin_action_log` com o retrato de `metadata`. Confirmado: `prosecdef = true`, `pronargs = 1`, grants corretos. Arquivo em `database/schema/1062_create_admin_grant_revoke_functions.sql`.

## Bootstrap administrativo — operação única (NÃO é uma migration replicável)

Como `admin_grant_admin()` exige que o chamador já seja administrador, a primeira concessão não pode passar pela function — é um `INSERT` direto, rodado uma única vez via SQL Editor, concedendo o papel a Fabrício (identificado por e-mail, evitando copiar/colar UUID manualmente) e registrando a ação em `admin_action_log` com uma nota explícita de que é bootstrap. Por decisão de Fabrício, esta operação **não** foi numerada na sequência estrutural nem gravada em `database/schema/` — é específica deste ambiente (hardcoda um e-mail real) e não deve ser reexecutada em outro projeto/ambiente sem ajuste.

```sql
INSERT INTO public.admin_user (id, granted_by)
SELECT id, NULL FROM auth.users WHERE email = 'fabricio.souza.sales@hotmail.com';

INSERT INTO public.admin_action_log (actor_id, target_user_id, action, metadata)
SELECT id, id, 'GRANT_ADMIN',
    jsonb_build_object('note', 'bootstrap inicial — primeiro administrador, concedido manualmente via SQL Editor')
FROM auth.users WHERE email = 'fabricio.souza.sales@hotmail.com';
```

Confirmado executado — Fabrício listado como administrador em `admin_user`, com o registro correspondente em `admin_action_log`.

## Sequência

```text
1050 - Create Admin User table                          (CONFIRMADO EXECUTADO — database/schema/1050_create_admin_user_table.sql)
1060 - Create is_admin() function                        (CONFIRMADO EXECUTADO — database/schema/1060_create_is_admin_function.sql)
1061 - Create admin_list_users() function (v1.1)          (CONFIRMADO EXECUTADO — database/schema/1061_create_admin_list_users_function.sql)
1062 - Create admin_grant_admin()/admin_revoke_admin()     (CONFIRMADO EXECUTADO — database/schema/1062_create_admin_grant_revoke_functions.sql)
1070 - Create Admin Action Log table                      (CONFIRMADO EXECUTADO — database/schema/1070_create_admin_action_log_table.sql)
      - Bootstrap administrativo                          (CONFIRMADO EXECUTADO — operação única, não numerada, não versionada em database/schema/)
1850 - Validate Admin User                                (EXECUTADA — database/validations/1850_validate_admin_user.sql)
1860 - Validate Admin Functions                           (EXECUTADA — database/validations/1860_validate_admin_functions.sql)
1870 - Validate Admin Action Log                          (EXECUTADA — database/validations/1870_validate_admin_action_log.sql)
```

## Frontend (Fase 3, CONFIRMADO EXECUTADO)

Rota `/usuarios` (já existia como placeholder desde a fundação do frontend, agora real): Server Component que redireciona para `/login` sem sessão, mostra "Acesso restrito a administradores" para não-admin, erro dedicado se `admin_list_users()` falhar, "Nenhum usuário encontrado" no caso vazio, e a tabela paginada nos demais casos. Item "Usuários" do menu (`nav-config.ts`) marcado `adminOnly` — some do menu para quem não é admin (checagem de UX; a autorização real está nas functions do banco, não no frontend). `AppShell` busca `is_admin()` uma única vez e repassa a `Sidebar`/`Header`/`MobileNav`. Tabela (`components/usuarios/users-table.tsx`) mostra username/nome/e-mail/data/papel e um botão conceder/revogar por linha, via Server Actions (`app/usuarios/actions.ts`) com tradução de erros dedicada (`lib/supabase/admin-errors.ts`).

## Pendências / Próximos Passos

Fase 4 (correção administrativa de `username`) deliberadamente fora deste incremento — mecanismo desenhado em nível conceitual no ADR-021 (flag local à transação sinalizando ao trigger `enforce_user_profile_invariants()`), implementação adiada para um incremento futuro. Testabilidade de `admin_grant_admin()`/`admin_revoke_admin()` com um segundo usuário real ainda pendente (Fabrício é hoje o único usuário/administrador cadastrado). Visualização do `admin_action_log` pela interface não faz parte deste incremento — o dado já é gravado, sem tela própria ainda.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste documento (2026-08-06), resultado da divisão de `05-modelo-de-dados.md` por área de domínio. Conteúdo inicial: seções placeholder de Physical Card e Collection/Collection Entry ("Documentação pendente"), mais o conteúdo físico completo (já existente antes da divisão) de User Profile/Reserved Username e Administração de Usuários. |
| 1.1 | **Fundação física de Inventory + Physical Card CONFIRMADO EXECUTADO (2026-08-31, `COLLECTIONS-PHYSICAL-INCREMENT-01B`).** Seção "Physical Card (Exemplar Físico)" substituída por "Physical Card (Exemplar Físico) / Inventory", com Status/Decisão de Modelagem/Modelo Físico completos das seis Queries `5000`–`5012` (tabelas `inventory`/`physical_card`, triggers de `updated_at`, provisionamento automático + backfill consolidados, RPC bulk-first `add_physical_cards()`), Sequência e Pendências. Precedida por três rodadas de modelagem física sem alteração de banco e uma rodada de staging auditada (`database/proposals/2026-08-31-collections-physical-increment-01a/`, agora histórica). Validação funcional/segurança de 23 itens e plano de performance sob 20.000 linhas, ambos executados ao vivo — ver `database/validations/5800_...`/`5801_...`. Nenhuma divergência entre o modelo conceitual (`concept-decisions.md` C-47/C-48, `logical-model.md` LDM-23) e o físico aplicado encontrada; nenhuma das duas foi alterada nesta rodada. Seção Collection/Collection Entry permanece "Documentação pendente" — fora de escopo. Ver `docs/log.md`. |
| 1.2 | **Fundação física de Storage/Storage Container CONFIRMADO EXECUTADO (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01`).** Nova seção "Storage / Storage Container" inserida entre "Physical Card (Exemplar Físico) / Inventory" e "Collection (Coleção) / Collection Entry", com Status/Decisão de Modelagem/Modelo Físico completos das cinco Queries `5020`–`5024` (tabela `storage_container`, trigger de `updated_at`, RPC `create_storage_container()`, `physical_card.storage_container_id` + FK composta `(id, inventory_id)` + CHECK complementar, RPC bulk-first `set_physical_cards_storage()` cobrindo o ciclo de vida 0..1 completo incluindo limpeza via `NULL`), Sequência e Pendências. Precedida por quatro rodadas de modelagem física sem alteração de banco (`COLLECTIONS-PHYSICAL-MODELING-03`/`-REVISION-01`/`-REVISION-02`/`-FINAL-01`) e uma rodada de staging auditada com correção (`database/proposals/2026-08-31-02a-storage/`, agora histórica). Validação funcional/segurança de 19 itens (casos A–J) e plano de performance sob 20.000 linhas, ambos executados ao vivo — ver `database/validations/5802_...`/`5803_...`. Achado de modelagem registrado nesta rodada: FK composta sob `MATCH SIMPLE` não cobre `storage_container_id` preenchido com `inventory_id` NULL — fechado com CHECK complementar, sem reabrir a decisão conceitual (C-61/LDM-49). Nenhuma decisão conceitual/lógica reaberta — `logical-model.md` recebeu apenas nota de materialização física (LDM-45/46/49), versão 1.15. Seção Collection/Collection Entry permanece "Documentação pendente" — fora de escopo. Ver `docs/log.md`. |
| 1.3 | **Skeleton físico de Collection + Default Storage CONFIRMADO EXECUTADO (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`).** Seção "Collection (Coleção) / Collection Entry" ("Documentação pendente") substituída por "Collection (Coleção)", com Status/Decisão de Modelagem/Modelo Físico completos das dez Queries `5030`–`5039` (tabela `collection` com ownership direto por `owner_user_id` + 6 CHECKs, triggers de `updated_at`/Structural Identity/Default Storage Owner, seis RPCs `create_collection()`/`update_collection_metadata()`/`set_collection_default_storage()`/`archive_collection()`/`reactivate_collection()`/`delete_collection()`), Performance, Sequência e Pendências. Precedida por três rodadas de modelagem física sem alteração de banco (`-MODELING-01`/`-REVISION-01`/`-FINAL-01`), uma rodada de correção de concorrência/idempotência ainda em staging (`-STAGING-REVISION-01`) e uma rodada de staging auditado (`database/proposals/2026-08-31-02b-collection/`, agora histórica). Validação funcional/segurança (21+ casos) e plano de performance sob 20.000 linhas, ambos executados ao vivo — ver `database/validations/5804_...`/`5805_...`. Três achados reais corrigidos no mesmo ciclo, nunca detectáveis antes da execução real: (1) `game.is_active` nunca existiu fisicamente — checagem removida de `create_collection()`, decisão de Fabrício, sem ampliar escopo de Catálogo; (2) referência ambígua `id`/`lifecycle_status` entre coluna de tabela e parâmetro OUT de `RETURNS TABLE` em `UPDATE`/`DELETE` sem qualificação — corrigida em todas as RPCs afetadas; (3) as duas trigger functions nunca tiveram `EXECUTE` revogado de `PUBLIC`/`anon` (achado do Supabase Advisor) — corrigido com `REVOKE` explícito. Nenhuma decisão conceitual/lógica reaberta. `delete_collection()` explicitamente marcado para revisão obrigatória no Incremento 2C (guarda de C-13 via `collection_allocation`). Ver `docs/log.md`. **Nota de campo (2026-09-02):** o campo "Versão" do cabeçalho deste documento não foi atualizado quando o Incremento 2C (Collection Allocation) foi consolidado na Revision `1.3`→(2C) — a seção "Collection Allocation" já existia completa no corpo do documento, mas sem entrada própria nesta tabela nem bump do campo "Versão". Divergência de campo sinalizada e corrigida nesta rodada (2D, Revision `1.4`, ver abaixo) sem reabrir ou reescrever o conteúdo já existente do 2C. |
| 1.4 | **Física de Collection Reference / Card Set Reference CONFIRMADO EXECUTADO (2026-09-02, `COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01`).** Nova seção "Collection Reference / Card Set Reference" inserida entre "Collection Allocation" e "User Profile (Perfil de Usuário) / Reserved Username", com Status/Decisão de Modelagem/Modelo Físico completos das dezoito Queries `5049`–`5066` (tabelas `collection_reference`/`collection_card_set_reference` — supertipo/subtipo com CASCADE composicional —, `mode = 'REFERENCE_BASED'` liberado fisicamente, `reference_locked_at` destravado e materializado, dois constraint triggers `DEFERRABLE INITIALLY DEFERRED` para as garantias transacionais `mode`↔Reference e supertipo↔subtipo, guard imediato de Reference-antes-da-primeira-Allocation, integridade de Game e elegibilidade de Reference sobre Allocation, duas RPCs novas `create_reference_based_card_set_collection()`/`set_collection_card_set_reference()`), Validação Funcional, Performance, Segurança, Sequência e Pendências. Precedida por duas rodadas de modelagem física sem alteração de banco (`-MODELING-01`/`-REVISION-01`/`-FINAL-01`) e duas rodadas de staging auditado em `database/proposals/2026-09-02-02d-reference/` (`-STAGING-REVISION-01` — fechou o blocker de Reference-after-lock antes da aplicação real; `-STAGING-FINAL-FIX-01` — três correções pontuais de fixture de validação). Validação funcional de 25 casos (A–Z, 0 falhas) e performance real sob workloads de 200–500 operações, ambos executados ao vivo — ver `database/proposals/2026-09-02-02d-reference/5808_...`(v2.4)/`5809_...`(v2.2). Três divergências de fixture (não de produto) identificadas e corrigidas durante a execução real, detalhadas na seção "Validação Funcional" acima — nenhuma alterou modelagem 02D, migrations 5049–5066, regras de Game, catálogo permanente ou documentação de produto. Nenhuma decisão conceitual/lógica reaberta. `completion_policy` permanece deferida a um incremento posterior (02E). Ver `docs/log.md`. |
| 1.5 | **STANDARD_SET Completion/Progress CONFIRMADO EXECUTADO (2026-09-02, `COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01`).** Nova seção "Collection Completion / Progress (02E — STANDARD_SET)" inserida entre "Collection Reference / Card Set Reference" e "User Profile (Perfil de Usuário) / Reserved Username", com Status/Decisão de Modelagem/Modelo Físico completos das cinco Queries `5067`–`5071` (`collection.completion_policy` NONE/STANDARD_SET com `CHECK` de coluna única, `create_collection()`/`create_reference_based_card_set_collection()` estendidas para gravar a policy automaticamente, dois read models `SECURITY DEFINER` `collection_completion_summary()`/`collection_completion_positions()` com ownership reconstituído manualmente — correção de segurança real após achado de que o Catálogo Editorial é admin-only sob RLS), Segurança, Validação Funcional, Performance, Sequência e Pendências. Precedida por uma rodada de modelagem física sem alteração de banco (`-MODELING-01`/`-MODELING-REVISION-01`) e cinco rodadas de staging auditado em `database/proposals/2026-09-02-02e-completion/` (`-STAGING-01` até `-STAGING-EXECUTION-SAFETY-FIX-01`, incluindo a correção de segurança SECURITY INVOKER→DEFINER). Validação funcional de 72 casos (0 falhas) e performance real sob 9 workloads (A–I, todos < 30ms, `Function Scan`, zero leitura de disco), ambos executados ao vivo contra o catálogo real do Supabase — ver `database/proposals/2026-09-02-02e-completion/5810_...`(v4.1)/`5811_...`(v1.5). Um achado real de execução corrigido no mesmo ciclo (`GRANT USAGE ON SEQUENCE` ausente na infraestrutura de log da própria bateria de validação, nunca detectado em staging porque nenhuma rodada anterior executou de fato) — não alterou `5067`–`5071`. `MASTER_SET`/`Collection Master Set Scope`/`REFERENCE_POSITION` permanecem CONCEPTUALLY READY, PHYSICALLY DEFERRED FOR SCOPE CONTROL — nunca atribuído à cobertura atual do catálogo. Nenhuma decisão conceitual/lógica reaberta. Ver `docs/log.md`. |
| 1.6 | **MASTER_SET Scope & Completion CONFIRMADO EXECUTADO (2026-09-02, `COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-01`, promoção canônica em `-CANONICAL-PROMOTION-01`).** Nova seção "Collection Master Set Scope (02F — MASTER_SET)" inserida entre "Collection Completion / Progress (02E — STANDARD_SET)" e "User Profile (Perfil de Usuário) / Reserved Username", com Status/Decisão de Modelagem/Modelo Físico completos das treze Queries `5072`–`5084` (tabela `collection_master_set_scope` insert/delete-only com PK natural composta, trigger de elegibilidade imediata, trigger de bloqueio de `UPDATE`, enforcement diferido bidirecional de "MASTER_SET ativo -> Scope não vazio" via helper compartilhado + dois `CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED`, `CHECK` alargado para a 3ª combinação de `completion_policy`, helper `apply_master_set_scope_diff()` KEEP/ADD/REMOVE compartilhado, duas RPCs de transição de policy e uma RPC de mutação de Scope, extensão do read model de resumo para MASTER_SET e um read model novo de posições por Variant), Bulk Guard, Validação Funcional, Performance, Sequência e Pendências. Precedida por duas rodadas de modelagem física sem alteração de banco (`COLLECTIONS-MASTER-SET-MODELING-01`/`-REVISION-01`/`-FINAL-FIX-01`/`-FINAL-FIX-02`) e staging auditado em `database/proposals/2026-09-02-02f-master-set/` (`-STAGING-01`/`-STAGING-REVISION-01`). Validação funcional de 114 casos (0 falhas, 0 erros de runtime) e performance real sob 10 workloads (A–J) num pool combinado de 10.000 Card Variants, ambos executados ao vivo — ver `database/proposals/2026-09-02-02f-master-set/5812_...`(v2.3)/`5813_...`(v2.0). Dois achados reais de test harness corrigidos durante a implementação (nunca do schema `5072`–`5084` em si): ausência de `INSERT` direto em `physical_card` para `authenticated` (corrigido roteando pela RPC pública `add_physical_cards()`) e leitura direta de catálogo pós-`SET ROLE authenticated` numa fixture (corrigido movendo a resolução para contexto privilegiado). Bulk guard `c_max_variant_ids = 10000` confirmado por evidência real de performance, sem redução — decisão operacional, não arquitetural, sem ADR dedicado. Correção documental: `collection_completion_summary()`/`collection_master_set_scope_positions()` são `LANGUAGE SQL` (nunca PL/pgSQL); só `apply_master_set_scope_diff()`/as RPCs de transição/mutação são `plpgsql`. Nenhuma decisão conceitual/lógica reaberta. Auditoria final schema-vs-banco e declaração formal de `COLLECTIONS-PHYSICAL-INCREMENT-02F — CLOSED` pendentes de auditoria externa e autorização de Fabrício. Ver `docs/log.md`. |
| 1.7 | **`COLLECTIONS-PHYSICAL-INCREMENT-02F` — CLOSED (2026-09-02, `COLLECTIONS-PHYSICAL-INCREMENT-02F-FINAL-CLOSURE-01`). MASTER_SET Scope & Completion — FINALIZADO.** Declaração formal, após auditoria final (comparação `database/schema` vs. banco físico, zero divergência) e autorização explícita de Fabrício. Seção "Status" e subseção "Pendências / Próximos Passos" de "Collection Master Set Scope (02F — MASTER_SET)" atualizadas de "CONFIRMADO EXECUTADO/aguardando auditoria" para "CLOSED/FINALIZADO" — nenhum conteúdo normativo (modelagem, semântica de Scope, KEEP/ADD/REMOVE, Completion, segurança, performance, bulk guard) reaberto, nenhuma alteração a `5072`–`5084` nem reexecução de `5812`/`5813` nesta rodada. Próximo checkpoint planejado: Pokédex (`REFERENCE_POSITION`/Catalog Species/Pokédex Position) — modelagem ainda não iniciada. Ver `docs/log.md` e `docs/ROADMAP.md`. |
| 1.8 | **Nova seção "Collection Pokédex Reference / REFERENCE_POSITION (Pokédex — CONCEPTUALLY CLOSED)" (2026-09-03, `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`)**, inserida entre "Collection Master Set Scope (02F — MASTER_SET)" e "User Profile (Perfil de Usuário) / Reserved Username" — rodada exclusivamente de documentação, sem SQL, sem alteração de banco. Resumo narrativo da modelagem conceitual/lógica fechada em `docs/domain-modeling/collections/logical-model.md` (LDM-175 a LDM-185): Collection Pokédex Scope `FULL_REFERENCE`/`GENERATION_FILTERED` (supersede de LDM-16), Species Match/Mismatch sem bloqueio duro (supersede da cláusula Pokédex de LDM-17), Pokédex Position Assignment, Primary Representative, Completion por Assignment, sourcing PokéAPI+TCGdex+reconciliação editorial MMKYU (Editorial Reconciliation ≠ `USER_OVERRIDE`), correção editorial posterior não-destrutiva, e confirmação de ARCHIVED — não duplicado linha a linha, apenas resumido, com a fonte lógica completa referenciada. Texto das seções "Collection Reference / Card Set Reference" (linha "Pendências") e "Collection Master Set Scope" (linha "Pendências") ajustado para apontar "CONCEPTUALLY CLOSED (2026-09-03)" em vez de "CONCEPTUALLY READY, PHYSICALLY DEFERRED" — sem reabrir nenhum conteúdo normativo dessas seções. **PHYSICALLY NOT STARTED** — nenhuma tabela/função/trigger criada; próximo checkpoint "POKEDEX PHYSICAL MODELING". Ver `docs/adr/ADR-011-pokemon-tcg-domain-scope.md` (v1.2) e `docs/04-domain-model.md` (Pokémon → Pokémon Species) para a documentação complementar do mesmo ciclo. Ver `docs/log.md`. |
| 1.9 | **Fundação física de Pokémon Generation/Species CONFIRMADO EXECUTADO (2026-09-04, `COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01`).** Seção "Collection Pokédex Reference / REFERENCE_POSITION" — "Status" e "Pendências" atualizados: `pokemon_generation`/`pokemon_species`/`pokemon_species_external_reference` (Queries `6000`–`6021`, seed `6700`) agora físicas, sem `game_id` (entidades globais do universo Pokémon, decisão congelada desta rodada) — modelo físico completo registrado em `docs/standards/STD-001-database-standards.md` (novo módulo, milhar `6000`–`6999`). Pokédex Position/Position Assignment/Primary Representative/pipeline de ingestão permanecem não iniciados; próximo checkpoint renomeado para "POKEDEX POSITION PHYSICAL MODELING". Precedida por uma rodada de auditoria física sem alteração de banco (`COLLECTIONS-PHYSICAL-INCREMENT-02G-MODELING-AUDIT-01`) e staging auditado em `database/proposals/2026-09-04-02g-pokemon-catalog-foundation/`. Validação estrutural de 18 itens e 13 testes comportamentais (duplicidade de `code`/`ordinal_number`/`national_dex_number`, FK inválida, duplicidade de referência externa por Species+Fonte e por Fonte+external_id, `metadata` não-objeto, imutabilidade de `id`/`code`/`ordinal_number`/`created_at`, correção permitida de `national_dex_number`/`generation_id`), ambos executados ao vivo via `BEGIN...ROLLBACK` — zero resíduo confirmado. `pricing_source` confirmado existente no banco real durante esta rodada (Query `3000`/`3001`/`3002`, per `STD-001`) mas não localizado como arquivo em `database/schema/` — registrado como gap de documentação/higiene do domínio Pricing, separado e não bloqueante, não investigado a fundo nesta rodada. Nenhuma decisão conceitual/lógica reaberta. Ver `docs/log.md`. |
| 1.11 | **Pokémon Region Foundation CONFIRMADO EXECUTADO E PROMOVIDO (2026-09-04, `POKEMON-REGION-DOMAIN-MODELING-AUDIT-01` → `POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`).** Nova subseção "Pokémon Region (extensão física, 2026-09-04)" inserida dentro de "Collection Pokédex Reference / REFERENCE_POSITION", entre a subseção conceitual/lógica e "Pendências / Próximos Passos"; "Status" e "Pendências" da seção-mãe também atualizados. `pokemon_region`/`pokemon_region_external_reference` (Queries `6060`/`6061`/`6070`/`6071`) e `pokemon_generation.main_region_id` (Query `6080`, v1.1 — FK `ON UPDATE RESTRICT ON DELETE RESTRICT` explícita) agora físicas e promovidas para `database/schema/`, 0 linhas cada. Region confirmada entidade canônica própria, independente de Generation (Orre/Hisui sem Main Generation); cardinalidade Generation→Main Region N:1, sem `UNIQUE`/índice em `main_region_id` (decisão proporcional ao volume). Precedida por duas rodadas de auditoria/modelagem física sem alteração de banco (`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01`/`POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01`) e staging auditado com revisão em `database/proposals/2026-09-04-pokemon-region-foundation/` (`-STAGING-01`/`-STAGING-REVISION-01`, GATE 4). As 5 Queries de estrutura aplicadas na ordem `6060`→`6061`→`6070`→`6071`→`6080`; validação estrutural+comportamental+privilégios de função (Query `6810`, `BEGIN...ROLLBACK`) confirmada PASS por postcheck independente (GATE 8) — inclui prova simultânea `confupdtype='r' AND confdeltype='r'`, todas as 5 UNIQUE/CHECK, zero DML de `service_role`, e prova comportamental de N:1. Zero resíduo. As 5 Queries de estrutura promovidas para `database/schema/` (corpo SQL byte-idêntico ao staging); `6810` não promovida, permanece em `database/proposals/2026-09-04-pokemon-region-foundation/` como evidência histórica. Detalhamento lógico completo em `logical-model.md` LDM-186 a LDM-190 e `ADR-011` v1.3. Nenhuma decisão conceitual/lógica reaberta. Ver `docs/log.md`. |
| 1.10 | **Fatia A ("Canonical Pokédex Foundation") CONFIRMADO EXECUTADO E PROMOVIDO (2026-09-04, `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`).** Seção "Collection Pokédex Reference / REFERENCE_POSITION" — "Status" e "Pendências" atualizados: `pokedex`/`pokedex_position`/`pokedex_external_reference` (Queries `6030`–`6051`) agora físicas e promovidas para `database/schema/`, com 0 linhas cada (nenhum seed, nenhum sourcing PokéAPI iniciado). Precedida por uma rodada de auditoria física sem alteração de banco (`COLLECTIONS-POKEDEX-POSITION-AUDIT-01`) e staging auditado em `database/proposals/2026-09-04-pokedex-foundation/` (`-STAGING-01`/`-STAGING-REVISION-01`). As 6 Queries de estrutura foram aplicadas ao banco real na ordem `6030`→`6031`→`6040`→`6041`→`6050`→`6051`; validação estrutural + comportamental + privilégios de função (Query `6800`, executada ao vivo via `BEGIN...ROLLBACK`) resultou PASS em todas as seções, zero resíduo confirmado. RLS fechado (zero policy, zero privilégio de cliente) nas três tabelas; as 8 trigger functions (3+2+3) sem `EXECUTE` para `anon`/`authenticated` desde a origem. Advisor de performance registrou um achado INFO aceito deliberadamente (`pokedex_position.species_id` sem índice — decisão de não antecipar índice especulativo sem volume real, documentada no header de `6040`). Após auditoria pós-implementação externa (PASS), as 6 Queries de estrutura foram promovidas para `database/schema/` — mudança restrita a cabeçalho (Status/Data) e rodapé de cada arquivo, corpo SQL byte-idêntico ao staging aprovado; `6800` **não** foi promovida, permanece em `database/proposals/2026-09-04-pokedex-foundation/` como evidência histórica de validação executada. Position Assignment, Primary Representative e o pipeline de ingestão PokéAPI/TCGdex/reconciliação editorial (Fatias B/C/D/E) permanecem não iniciados. Nenhuma decisão conceitual/lógica reaberta. Ver `docs/log.md`. |
| 1.12 | **Fatia B ("Collection Pokédex Reference + Adopted Scope") — IMPLEMENTED / VALIDATED / CLOSED (2026-09-05, `COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-IMPLEMENTATION-01` → `-CANONICAL-PROMOTION-01`).** Nova subseção "Collection Pokédex Reference / Adopted Scope (Fatia B, extensão física, 2026-09-05)" inserida dentro de "Collection Pokédex Reference / REFERENCE_POSITION", entre "Pokémon Region (extensão física, 2026-09-04)" e "Pendências / Próximos Passos"; "Status" e "Pendências" da seção-mãe também atualizados. Materializa fisicamente `collection_pokedex_reference` (subtipo POKEDEX de `collection_reference`) e o Collection Pokédex Scope (`FULL_REFERENCE`/`GENERATION_FILTERED`) via 15 Queries `5085`–`5099`: alargamento dos CHECKs de `reference_kind` (`5085`) e `completion_policy` (`5086`, habilitando `REFERENCE_POSITION` — correção REVISION-01, substituindo o `'NONE'` semanticamente falso da v1.0), tabela `collection_pokedex_reference` + triggers de `updated_at`/identidade/Game-Gate-e-lock (`5087`–`5090`), tabela `collection_pokedex_scope_generation` (`5091`), extensão do helper de consistência supertipo/subtipo incorporada ao arquivo canônico `5057` (v1.1, fold-in da Query `5092` — sem arquivo `5092_*.sql` isolado, mesmo padrão já usado em `5032`/`5042`/`5045`/`5046`), segundo lado do enforcement de consistência (`5093`), enforcement de presença Scope↔Generation (`5094`–`5097`) e as duas RPCs públicas `create_reference_based_pokedex_collection()`/`set_collection_pokedex_scope()` (`5098`/`5099`). Aplicadas ao banco real na ordem exata `5085`→`5099` via MCP do Supabase; postcheck físico independente PASS (estrutura, triggers, RLS, privilégios, testes funcionais em `BEGIN...ROLLBACK`). Zero resíduo. As 15 Queries promovidas para `database/schema/` (13 arquivos novos + extensão de `5057`); `database/proposals/2026-09-05-collections-pokedex-fatia-b-scope/` mantida integralmente como evidência histórica/auditoria. Débito de `service_role` nas 5 tabelas legadas de Collection registrado como item separado, não bloqueante, não corrigido nesta rodada. Próximo passo planejado: Fatia C — Card → Primary Species / sourcing. Nenhuma decisão conceitual/lógica reaberta. Ver `docs/log.md`. |
| 1.13 | **Fatia C ("Card → Primary Species / sourcing") — CONFIRMADO EXECUTADO (2026-09-05, `COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-IMPLEMENTATION-01-RESUME` → `-BACKFILL-APPLY-01` → `-INCREMENTAL-INTEGRATION-AUDIT-01`/`-REVISION-01`/`-FINAL-CHECK-01` → `-INCREMENTAL-IMPLEMENTATION-01` → `-CANONICAL-CLOSEOUT-01`).** Nova subseção "Card → Primary Species (Fatia C, extensão física, 2026-09-05)" inserida dentro de "Collection Pokédex Reference / REFERENCE_POSITION", entre "Collection Pokédex Reference / Adopted Scope (Fatia B...)" e "Pendências / Próximos Passos"; "Status" e "Pendências" da seção-mãe também atualizados. Materializa fisicamente a resolução de Primary Species de uma Card via 6 Queries `2159`/`6112`–`6116`: alargamento das 3 `CHECK`s de `catalog_admin_action_log` para o estado real reconciliado (29 actions/11 entity_types/11 ramos, `2159`), tabela `card_primary_species` + triggers de categoria/imutabilidade/`updated_at` (`6112`/`6113`), resolução editorial individual via UPSERT (`admin_resolve_card_primary_species()`, `6114`), resolução automática em lote apenas-INSERT (`resolve_card_primary_species_bulk()`, `6115`, `SERVICE_ROLE ONLY`) e a orquestração pós-confirmação de importação (`resolve_card_primary_species_for_catalog_import_job()`, `6116`, filtra `source = 'TCGDEX'`, vínculo exclusivo via `resulting_card_id` — nunca `matched_card_id`). Dois callers reais e não-bloqueantes integrados nesta rodada: `confirmarImportacao()` (`web/app/catalogo/importar-cartas/tcgdex/actions.ts`) e o handler de `supabase/functions/revalidate-catalog-import-rows/index.ts` (reimplantado, versão 9, `ACTIVE`). Backfill do catálogo existente: `5675`/`6435` Cards POKEMON resolvidas automaticamente (cobertura inicial 88,19%), `760` pendentes editoriais, executado com guard de divergência e zero resíduo. Postcheck estrutural/segurança e 26 cenários funcionais (`BEGIN...ROLLBACK`) PASS. As 6 Queries promovidas para `database/schema/` (corpo SQL byte-idêntico ao executado, apenas cabeçalho atualizado); `database/proposals/2026-09-05-fatia-c-card-primary-species/` e `database/proposals/2026-09-05-fatia-c-incremental-integration/` mantidas integralmente como evidência histórica. Nenhuma decisão conceitual/lógica reaberta. **Fatia C concluída** — próximo passo planejado: Fatia D. Ver `docs/log.md`. |
| 1.14 | **Fatia D ("Pokédex Position Assignment + Primary Representative") — IMPLEMENTED / VALIDATED / CLOSED (2026-09-06, `COLLECTIONS-POKEDEX-FATIA-D-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-STAGING-01` → GATE 4 → `PAUSE-SQL-DIRECT-AUDIT-01` → `RENUMBER-FIX-STAGING-01` → `6830-DIRECT-REVIEW-FIX-01`/`-FIX-02` → `IMPLEMENTATION-RESUME-02` → `6126-STAGING-01`/`-IMPLEMENT-RESUME-01` → `FINAL-VALIDATION-CLEANUP-01` → `PROMOTION-CLOSEOUT-01`).** Nova subseção "Pokédex Position Assignment / Primary Representative (Fatia D, extensão física, 2026-09-06)" inserida dentro de "Collection Pokédex Reference / REFERENCE_POSITION", entre "Card → Primary Species (Fatia C...)" e "Pendências / Próximos Passos"; "Status" e "Pendências" da seção-mãe também atualizados. Materializa fisicamente Pokédex Position Assignment (LDM-178/179) e Primary Representative (LDM-180) via 10 Queries `6117`–`6126`: tabela `collection_pokedex_position_assignment` (PK/FK compartilhada `collection_allocation_id`, `6117`) + 3 triggers de ator/match-Pokédex/imutabilidade (`6118`), trigger automático `SPECIES_MATCH` restrito a `mode = 'REFERENCE_BASED'` (`6119`), tabela `collection_pokedex_position_primary_representative` (`6120`) + trigger de integridade cruzada (`6121`), RPC `set_pokedex_position_assignment()` (`6122`), migration incremental sobre objetos já vivos (`6123`), RPC `remove_pokedex_position_assignment()` (`6124`), RPCs `set_/clear_pokedex_position_primary_representative()` (`6125`), e a correção de um bug funcional real (`SQLSTATE 42702`, ambiguidade de `ON CONFLICT` sob `plpgsql.variable_conflict = 'error'`) em `6126`. Aplicadas ao banco real na ordem `6117`→`6126`; validação funcional de 24 casos PASS, exceto Caso 20b (`NOT EXECUTED / UNPROVEN`, aprovado — ambiente sem duas sessões persistentes simultâneas). Cleanup de fixtures da bateria de testes executado com zero-resíduo confirmado por identidade (incluindo 2 fixtures não rastreadas em tabela de controle, achadas por auditoria de timestamp/dono, não por nome/prefixo); postcheck estrutural/segurança pós-cleanup confirmou os objetos intactos. As 10 Queries promovidas para `database/schema/` (corpo SQL byte-idêntico ao executado, apenas cabeçalho atualizado); `database/proposals/2026-09-05-fatia-d-position-assignment/` mantida integralmente como evidência histórica (script de validação `6830` não é schema, não promovido). Nenhuma decisão conceitual/lógica reaberta. **Fatia D concluída** — próximo passo planejado: Fatia E (REFERENCE_POSITION Completion). Ver `docs/log.md`. |
| 1.15 | **Fatia E ("REFERENCE_POSITION Completion") — IMPLEMENTED / LIVE / VALIDATED / PERFORMANCE-MEASURED / CLOSED tecnicamente (2026-09-06, `COLLECTIONS-POKEDEX-FATIA-E-PHYSICAL-MODELING-AUDIT-01`/`-REVISION-01` → `-STAGING-01`/`-STAGING-REVISION-01` → `-IMPLEMENTATION-01` → `-PERFORMANCE-01` → `-PERFORMANCE-HARNESS-REVISION-01` → `-PERFORMANCE-EXECUTION-01` → `-PERFORMANCE-REMEDIATION-AUDIT-01`/`-STAGING-01` → `-AB-HARNESS-FINAL-FIX-01` → `-AB-EXECUTION-01` → `-PERFORMANCE-REMEDIATION-IMPLEMENTATION-01` → `-POSTCHECK-2C-CORRECTION-STAGING-01`/`-EXECUTION-01` → `-FINAL-LIVE-PERFORMANCE-01` → `-CLOSEOUT-01`).** Duas novas seções inseridas entre "Pokédex Position Assignment / Primary Representative (Fatia D...)" e "Pendências / Próximos Passos": "REFERENCE_POSITION Completion & Scope Positions read model (Fatia E, extensão física, 2026-09-06)" e "Product / UX Traceability — Pokédex"; a subseção "Pendências / Próximos Passos" também atualizada. Fecha o ramo `REFERENCE_POSITION` de completion via 4 Queries `5100`–`5103`, **sem tabela nova, sem coluna nova, sem índice novo, sem denormalização**: `5100` estende `collection_completion_summary()` com um terceiro ramo mutuamente exclusivo (4 CTEs novas + `UNION ALL` de 2→3 branches, ramos STANDARD_SET/MASTER_SET preservados byte-idênticos); `5101` cria `collection_pokedex_scope_positions()` como espelho de `collection_master_set_scope_positions()`; `5102`/`5103` substituem os corpos vivos com a remediação de performance. Semântica congelada: numerator = Scope corrente INTERSECT Positions com Assignment da Collection; denominator = Positions do Scope corrente; duplicatas nunca inflam; `SPECIES_MATCH` e `USER_OVERRIDE` contam igualmente; Assignment fora do Scope preservada mas não contada; Primary Representative sem interferência; alteração de Scope não destrói Assignment; `FULL_REFERENCE` e `GENERATION_FILTERED` suportados. Um **BLOCKER de performance real** encontrado por `5815` contra a Pokédex NATIONAL real (1025 Positions): custo Θ(\|Scope\| × \|Allocations\|) a ~3,02 shared blocks/par (~1,36 s / ~2,56 M shared hits no pior workload) — causa de **query-shape**, não de índice; remediado pela Alternativa B (pré-calcular Positions satisfeitas via `collection_allocation → collection_pokedex_position_assignment` sem tocar o Scope, e só então intersectar), levando a Θ(\|Scope\| + \|Allocations\|) com os índices já existentes. Evidência: `5814` v1.3 87/87 PASS contra `5100`/`5101`; `5816` v1.1 A/B transacional com gate fail-closed CANDIDATE PASS (13/13 de equivalência semântica); `5814` reexecutado inalterado contra `5102`/`5103` 86/87 com o único FAIL sendo falso-positivo textual do POSTCHECK-2c (`_` como wildcard em `ILIKE` + token literal em comentário), substituído por `5817` v1.0 (1/1 PASS, comparação literal com `position()` sobre source sem comentários); `5815` v1.2 final contra as funções live 13 HEALTHY / 0 ATTENTION / 0 BLOCKER (4,7–8,8 ms, reduções de 154×–306× em tempo e ~1008×–1010× em buffers, `shared read = 0`, custo marginal por Allocation invariante ao Scope). `5100`–`5103` promovidas para `database/schema/` com **histórico incremental preservado e não foldado** (`5100 → 5102`, `5101 → 5103`, corpo SQL byte-idêntico ao auditado, apenas cabeçalho atualizado); `database/proposals/2026-09-06-fatia-e-reference-position-completion/` e `database/proposals/2026-09-06-fatia-e-performance-remediation/` mantidas integralmente como evidência histórica (`5814`/`5815`/`5816`/`5817` não são schema, não promovidos). Registro de honestidade de evidência mantido: `INTERNAL PLAN VISIBILITY = NOT OBSERVABLE` — nenhuma alegação sobre nós de scan internos das funções. Nenhuma decisão conceitual/lógica reaberta. **Fatia E concluída** — próxima frente do projeto: Binder/Layout Foundation. Ver `docs/log.md` e `docs/ROADMAP.md` (v1.87). Correção documental desta rodada: campo **Versão** do cabeçalho estava stale em `1.12` enquanto esta tabela já continha entradas até `1.14` — sincronizado para `1.15` sem alterar nenhuma entrada histórica (as linhas `1.10`/`1.11` permanecem fora de ordem cronológica ascendente, como já estavam; não reordenadas para não reescrever histórico). |
| 1.16 | **Correção final de consistência documental (2026-09-06, `COLLECTIONS-POKEDEX-FATIA-E-FINAL-DOC-CORRECTION-01`).** Rodada exclusivamente documental, após auditoria direta do closeout; **nenhuma decisão de domínio nova, Fatia E não reaberta tecnicamente, nenhum SQL executado, nenhum corpo executável alterado.** Quatro correções em texto de estado corrente: (1) item 3 de "Product / UX Traceability — Pokédex" reescrito — a redação anterior sugeria criação automática da Assignment; a semântica correta é que o usuário seleciona a Physical Card elegível e a Assignment é registrada com `assignment_basis = SPECIES_MATCH` sem warning nem confirmação adicional, permanecendo ato explícito — **não existe auto-assignment**; os outros 9 princípios preservados. (2) "Pokédex Position Assignment (novo conceito lógico, sem tabela física própria ainda)" passou a registrar a materialização na Fatia D (`6117`–`6126`). (3) O parágrafo de Completion de `REFERENCE_POSITION` deixou de dizer "a ser seguida quando a modelagem física desta frente começar" e passou a apontar a materialização na Fatia E (`5100`–`5103`). (4) "Status" e "Pendências / Próximos Passos" da seção Pokédex deixaram de afirmar que `pokedex`/`pokedex_position`/`pokemon_region` estão com 0 linhas e sem sourcing — o Initial Load via PokéAPI foi executado e fechado em 2026-09-05; contagens e evidência permanecem canônicas em `docs/06a-pokemon-catalog-sourcing.md`, não duplicadas aqui. Nenhuma entrada histórica desta Revision History foi reescrita. Ver `docs/log.md`. |
| 1.17 | **Reconciliação documental do auto-`SPECIES_MATCH` (2026-09-06, `COLLECTIONS-POKEDEX-AUTO-ASSIGNMENT-DOC-RECONCILIATION-01`). Nenhuma mudança física; Fatias D e E não reabertas; nenhum SQL executado, nenhum objeto de banco alterado.** A seção "Product / UX Traceability — Pokédex" afirmava, no item 3, que "**não existe auto-assignment**" e que a seleção da Card e a Assignment seriam sempre atos explícitos — o que contradiz o comportamento **já LIVE desde a Fatia D**: a Query `6119` (`auto_assign_pokedex_position_species_match()`, trigger `AFTER INSERT` `FOR EACH STATEMENT` em `collection_allocation`) cria a Assignment automaticamente, com `assignment_basis = SPECIES_MATCH` e `assigned_by_user_id = NULL`, quando a Collection é Pokédex e a Primary Species da Card corresponde inequivocamente a uma Position do Pokédex referenciado. Quatro itens reescritos, mantendo os 10: (1) o North Star Position → Card passa a ser declarado como do **fluxo manual**, sem eliminar automações determinísticas; (2) Allocation ≠ Position Assignment reforçado como *relações distintas*, com a ressalva de que a Allocation **causa** a Assignment via `6119` sem **substituí-la** — completion segue consultando exclusivamente a Assignment; (3) o `SPECIES_MATCH` inequívoco passa a ser descrito como automático, registrando também o caminho manual por `6122` quando a automação não ocorreu; (4) ausência de match inequívoco passa a registrar explicitamente que a automação não cria nada e não erra, e que `USER_OVERRIDE` nunca é automático. O item 8 ganhou a nota de que `6119` não filtra por Scope — auto-Assignment fora do Scope é preservada mas não conta. Demais princípios preservados sem alteração. Nenhuma entrada histórica reescrita. Ver `docs/development/HANDOFF-2026-09-04.md` revisão `1.11`, `docs/domain-modeling/collections/logical-model.md` e `docs/log.md`. |
