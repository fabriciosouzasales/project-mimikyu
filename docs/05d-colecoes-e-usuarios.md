# Modelo de Dados — Coleções e Usuários

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Coleções e Usuários |
| **Arquivo** | `docs/05d-colecoes-e-usuarios.md` |
| **Versão** | 1.2 |
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
| 1.3 | **Skeleton físico de Collection + Default Storage CONFIRMADO EXECUTADO (2026-09-01, `COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01`).** Seção "Collection (Coleção) / Collection Entry" ("Documentação pendente") substituída por "Collection (Coleção)", com Status/Decisão de Modelagem/Modelo Físico completos das dez Queries `5030`–`5039` (tabela `collection` com ownership direto por `owner_user_id` + 6 CHECKs, triggers de `updated_at`/Structural Identity/Default Storage Owner, seis RPCs `create_collection()`/`update_collection_metadata()`/`set_collection_default_storage()`/`archive_collection()`/`reactivate_collection()`/`delete_collection()`), Performance, Sequência e Pendências. Precedida por três rodadas de modelagem física sem alteração de banco (`-MODELING-01`/`-REVISION-01`/`-FINAL-01`), uma rodada de correção de concorrência/idempotência ainda em staging (`-STAGING-REVISION-01`) e uma rodada de staging auditado (`database/proposals/2026-08-31-02b-collection/`, agora histórica). Validação funcional/segurança (21+ casos) e plano de performance sob 20.000 linhas, ambos executados ao vivo — ver `database/validations/5804_...`/`5805_...`. Três achados reais corrigidos no mesmo ciclo, nunca detectáveis antes da execução real: (1) `game.is_active` nunca existiu fisicamente — checagem removida de `create_collection()`, decisão de Fabrício, sem ampliar escopo de Catálogo; (2) referência ambígua `id`/`lifecycle_status` entre coluna de tabela e parâmetro OUT de `RETURNS TABLE` em `UPDATE`/`DELETE` sem qualificação — corrigida em todas as RPCs afetadas; (3) as duas trigger functions nunca tiveram `EXECUTE` revogado de `PUBLIC`/`anon` (achado do Supabase Advisor) — corrigido com `REVOKE` explícito. Nenhuma decisão conceitual/lógica reaberta. `delete_collection()` explicitamente marcado para revisão obrigatória no Incremento 2C (guarda de C-13 via `collection_allocation`). Ver `docs/log.md`. |

