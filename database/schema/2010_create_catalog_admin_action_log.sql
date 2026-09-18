/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2010 - Create Catalog Admin Action Log Table
Versão......: 2.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / RECONCILIADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26 (v1.1: 2026-07-26, v1.2: 2026-07-31, v1.3: 2026-08-01,
              v2.0: 2026-09-18 — estado terminal das três CHECK)

Descrição...:
Cria public.catalog_admin_action_log: auditoria própria do módulo
Catálogo Editorial — Escrita e Ingestão, deliberadamente separada
de public.admin_action_log (domínio de Identidade & Acesso,
ADR-021, CHECK restrito a GRANT_ADMIN/REVOKE_ADMIN). Ver ADR-023,
seção "Auditoria editorial própria, separada de admin_action_log".

Este é o nome definitivo da tabela — ADR-023 registrou apenas um
exemplo (catalog_admin_action_log) e deixou a confirmação para
este documento/Query, conforme previsto em sua seção
"Restrições / Pendências".

Regras de Negócio:
- Registra toda operação administrativa bem-sucedida das funções
  criadas por ADR-023 (Game/Expansion/Card Set/Card) e, em
  ADR-024, a confirmação em lote de importação — sempre uma linha
  agregada por chamada (referenciando o job), nunca uma linha por
  Card confirmada; o detalhe linha a linha já vive em
  catalog_import_row.
- actor_id anulável com ON DELETE SET NULL, mesmo padrão de
  admin_action_log (Query 1070): a exclusão futura do usuário
  nunca apaga o registro da ação, só desfaz a referência direta.
- entity_id é polimórfico (aponta para a tabela correspondente ao
  entity_type da linha — hoje uma das TREZE entidades previstas:
  game, expansion, card_set, card, catalog_import_job, rarity,
  rarity_external_mapping, catalog_variant_import_job,
  card_variant_type_external_mapping, card_variant_type,
  card_primary_species, card_printing_external_mapping e
  card_printing_profile) e por isso não tem FK — mesmo motivo
  estrutural pelo qual não há uma única tabela-alvo possível. É
  NOT NULL: toda ação registrada aqui sempre tem exatamente uma
  entidade concreta como alvo, nunca uma ação global.
- action restrito por CHECK. **Estado terminal LIVE: 31 ações.**
  A v1.0 desta Query nasceu com as 10 ações da fase inicial de
  ADR-023; a lista foi ampliada por migrations sucessivas
  (ingestão de Cards, raridade, Card Variant Type e seu mapeamento
  externo, Card Primary Species, Printing External Mapping e
  Printing Profile), e esta Query canônica passou a refletir esse
  acumulado na v2.0. Ampliar a lista segue sendo evolução simples
  (ALTER da constraint), não mudança estrutural — mesmo padrão já
  usado em admin_action_log.
- entity_type restrito por CHECK. **Estado terminal LIVE: 13
  valores**, enumerados no item de entity_id acima.
- CHECK adicional garante que action é sempre compatível com
  entity_type (ex.: GAME_CREATED só é aceito com entity_type =
  'GAME') — reforço de integridade de implementação, não uma
  decisão de ADR-023; impede que um erro na função de escrita
  grave uma combinação logicamente inválida na auditoria.
  **Estado terminal LIVE: 13 ramos**, um por entity_type,
  cobrindo as 31 ações.
- metadata (JSONB) anulável, sem valor padrão — mesmo padrão de
  admin_action_log (Query 1070), guarda um retrato dos dados
  relevantes da operação no momento da ação.
- RLS habilitado, sem nenhuma política: só funções SECURITY
  DEFINER escrevem aqui; não há leitura via API nesta fase, mesmo
  padrão de admin_action_log.
- Sem updated_at/trigger: tabela de auditoria append-only, nunca
  editada após a escrita.

Versão 1.1 (ADR-023, emenda 2026-07-26 "Game: exclusão real via
UI", Query 2041 — Princípio da Fonte Canônica, Autoria de Scripts
SQL): adiciona 'GAME_DELETED' às duas constraints de action. A
migration 2041_add_game_deleted_to_catalog_admin_action_log.sql
registra a execução histórica contra o banco já existente; este
arquivo canônico reflete a estrutura final para qualquer
instalação nova.

Versão 1.2 (2026-07-31 — correção de um gap + nova emenda):
- Correção: esta versão canônica nunca havia recebido
  'EXPANSION_DELETED', apesar de a migration
  2043_add_expansion_deleted_to_catalog_admin_action_log.sql já
  estar confirmada executada contra o banco real desde 2026-07-31
  (ADR-023, emenda "Expansion: exclusão real via UI"). Uma
  instalação nova a partir da Versão 1.1 ficaria, portanto,
  divergente do banco real — corrigido aqui, sem migration própria
  (o valor já existe fisicamente; só o arquivo canônico estava
  desatualizado).
- Nova emenda (ADR-023, "Card Set: atualização e exclusão real via
  UI", Query 2050): adiciona 'CARD_SET_DELETED' às duas
  constraints. A migration
  2049_add_card_set_deleted_to_catalog_admin_action_log.sql
  registra a execução real contra o banco existente.

Versão 1.3 (2026-08-01 — ADR-024, Ciclo 1 de ingestão de Cards):
- Adiciona 'CATALOG_IMPORT_JOB' e 'CATALOG_IMPORT_CONFIRMED' a
  ck_catalog_admin_action_log_action_valid, um novo entity_type
  'CATALOG_IMPORT_JOB' a ck_catalog_admin_action_log_entity_type_
  valid, e a combinação correspondente a
  ck_catalog_admin_action_log_action_entity_match. As migrations
  2054_widen_catalog_admin_action_log_for_catalog_import.sql e
  2055_add_catalog_import_job_entity_type_to_action_log.sql
  registram a execução real contra o banco existente — a segunda
  corrige um gap real da primeira (ela ampliou só duas das três
  constraints desta tabela, esquecendo entity_type_valid; descoberto
  na execução real de admin_start_catalog_import() pela validação
  funcional da Query 2814).

Versão 2.0 (2026-09-18 — BULK-STP-01-CANONICAL-RECONCILIATION-
IMPLEMENTATION-01): as três CHECK passam a representar o ESTADO
TERMINAL LIVE — 31 ações, 13 entity_types, 13 ramos de
correspondência. Até esta data a canônica ainda descrevia a fase
inicial: uma instalação limpa nasceria recusando a maior parte das
ações que o sistema emite hoje. Nenhuma migration nova foi criada
para isso — o acumulado já estava LIVE; as migrations que o
introduziram (entre elas 2159, ledger 20260905192310, e 2188,
ledger 20260913234544) seguem em database/migrations/ como
histórico. Ver REVISION HISTORY.

Pré-requisitos:
- Query 2000 - Create Internal Schema (mesmo módulo).
================================================================

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação da tabela de auditoria do Catálogo Editorial (2026-08).**
        15 ações · 5 entity_types. |
| 2.0 | **Estado terminal das três CHECK (2026-09-18, BULK-STP-01-CANONICAL-
        RECONCILIATION-IMPLEMENTATION-01).** A canônica v1.0 não refletia
        NENHUM dos alargamentos já aplicados ao LIVE — qualquer instalação
        limpa nasceria com uma CHECK que recusa a maior parte das ações que o
        sistema emite hoje. As três CHECK passam a representar o estado LIVE
        comprovado por `pg_get_constraintdef`: **31 ações · 13 entity_types ·
        13 ramos de correspondência**, acumulado de todas as migrations de
        alargamento, incluindo `2159` (Card Primary Species / Variant Type
        External Mapping, ledger `20260905192310`) e `2188` (Card Printing
        Profile, ledger `20260913234544`).
        Conforme `database/README.md`, as migrations que introduziram cada
        camada permanecem em `database/migrations/` como histórico e passam a
        ser lidas como `MIGRATION`, não como fonte canônica — inclusive a
        `2159`, que até esta data estava indevidamente em `database/schema/`. |
*/

CREATE TABLE public.catalog_admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL
                     REFERENCES auth.users(id)
                     ON DELETE SET NULL,
    action           TEXT NOT NULL,
    entity_type      TEXT NOT NULL,
    entity_id        UUID NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- ------------------------------------------------------------
    -- ESTADO TERMINAL LIVE (2026-09-18). 31 ações · 13 entity_types ·
    -- 13 ramos de correspondência. Acumulado de todas as migrations de
    -- alargamento até 2188 — ver REVISION HISTORY 2.0.
    -- ------------------------------------------------------------
    CONSTRAINT ck_catalog_admin_action_log_action_valid
        CHECK (
            action IN (
                'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
                'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
                'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
                'CARD_CREATED', 'CARD_UPDATED',
                'CARD_DEACTIVATED', 'CARD_REACTIVATED',
                'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED',
                'CATALOG_IMPORT_ROWS_REVALIDATED',
                'RARITY_CREATED', 'RARITY_UPDATED',
                'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
                'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
                'CARD_VARIANT_IMPORT_CONFIRMED',
                'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
                'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
                'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
                'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED',
                'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
                'CARD_PRINTING_PROFILE_CREATED'
            )
        ),

    CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
        CHECK (
            entity_type IN (
                'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
                'RARITY', 'RARITY_EXTERNAL_MAPPING',
                'CATALOG_VARIANT_IMPORT_JOB', 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING',
                'CARD_VARIANT_TYPE', 'CARD_PRIMARY_SPECIES',
                'CARD_PRINTING_EXTERNAL_MAPPING', 'CARD_PRINTING_PROFILE'
            )
        ),

    CONSTRAINT ck_catalog_admin_action_log_action_entity_match
        CHECK (
            (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED'))
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED'))
            OR (entity_type = 'CARD_SET' AND action IN (
                    'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
                    'CARD_ASSET_MANUAL_IMPORT_COMPLETED'
                ))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
            OR (entity_type = 'CATALOG_IMPORT_JOB' AND action IN (
                    'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED',
                    'CATALOG_IMPORT_ROWS_REVALIDATED'
                ))
            OR (entity_type = 'RARITY' AND action IN ('RARITY_CREATED', 'RARITY_UPDATED'))
            OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action IN (
                    'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'
                ))
            OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action = 'CARD_VARIANT_IMPORT_CONFIRMED')
            OR (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED')
            OR (entity_type = 'CARD_VARIANT_TYPE' AND action IN (
                    'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
                    'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'
                ))
            OR (entity_type = 'CARD_PRIMARY_SPECIES' AND action IN (
                    'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED'
                ))
            OR (entity_type = 'CARD_PRINTING_EXTERNAL_MAPPING' AND action = 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
            OR (entity_type = 'CARD_PRINTING_PROFILE' AND action = 'CARD_PRINTING_PROFILE_CREATED')
        )
);

COMMENT ON TABLE public.catalog_admin_action_log IS
    'Auditoria própria do Catálogo Editorial — Escrita e Ingestão (ADR-023/ADR-024), separada de admin_action_log.';

COMMENT ON COLUMN public.catalog_admin_action_log.actor_id IS
    'Administrador que executou a ação. Anulável: sobrevive à exclusão futura do usuário.';

COMMENT ON COLUMN public.catalog_admin_action_log.action IS
    'Ação administrativa executada. Estado terminal LIVE: 31 ações — ver a CHECK ck_catalog_admin_action_log_action_valid. A lista nasceu em ADR-023 e foi ampliada por migrations sucessivas.';

COMMENT ON COLUMN public.catalog_admin_action_log.entity_type IS
    'Tipo da entidade afetada. Estado terminal LIVE: 13 valores — ver a CHECK ck_catalog_admin_action_log_entity_type_valid.';

COMMENT ON COLUMN public.catalog_admin_action_log.entity_id IS
    'Identificador da entidade afetada. Polimórfico (sem FK) — a tabela real depende de entity_type.';

COMMENT ON COLUMN public.catalog_admin_action_log.metadata IS
    'Retrato dos dados relevantes da operação no momento da ação, para leitura futura mesmo após alterações posteriores.';

COMMENT ON COLUMN public.catalog_admin_action_log.created_at IS
    'Data e hora da ação. Tabela append-only, sem updated_at.';

ALTER TABLE public.catalog_admin_action_log ENABLE ROW LEVEL SECURITY;
