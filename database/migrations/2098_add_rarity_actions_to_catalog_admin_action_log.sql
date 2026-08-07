/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2098 - Add Rarity Actions to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Amplia as três CHECK constraints de public.catalog_admin_action_log
(Query 2010, últimas alterações nas Queries 2041/2043/2049/2054) para
reconhecer as novas ações e os dois novos entity_type introduzidos
pelo cadastro self-service de Raridade (ADR-024, emenda "Raridade:
mapeamento self-service e revalidação"): RARITY_CREATED/
RARITY_UPDATED (entity_type RARITY),
RARITY_EXTERNAL_MAPPING_CREATED/RARITY_EXTERNAL_MAPPING_UPDATED
(entity_type RARITY_EXTERNAL_MAPPING), e CATALOG_IMPORT_ROWS_
REVALIDATED (entity_type CATALOG_IMPORT_JOB, junto de
CATALOG_IMPORT_JOB/CATALOG_IMPORT_CONFIRMED já existentes).

Regras de Negócio:
- Mesma técnica das Queries 2041/2043/2049 (DROP + ADD CONSTRAINT
  — Postgres não permite ALTER CONSTRAINT em CHECK).
- Nenhuma linha existente é afetada — só a definição das três
  constraints muda.
- ck_catalog_admin_action_log_entity_type_valid ganha 'RARITY' e
  'RARITY_EXTERNAL_MAPPING' à lista de entity_type reconhecidos —
  a única das três constraints que ainda não havia sido tocada
  desde a Query 2010.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2049 - Add CARD_SET_DELETED to Catalog Admin Action Log.
- Query 2054 - Add Catalog Import Actions to Catalog Admin Action Log.
================================================================
*/

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
        CHECK (
            action IN (
                'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
                'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
                'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
                'CARD_CREATED', 'CARD_UPDATED',
                'CARD_DEACTIVATED', 'CARD_REACTIVATED',
                'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED',
                'RARITY_CREATED', 'RARITY_UPDATED',
                'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'
            )
        );

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match
        CHECK (
            (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED'))
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED'))
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
            OR (entity_type = 'CATALOG_IMPORT_JOB' AND action IN (
                    'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED'
                ))
            OR (entity_type = 'RARITY' AND action IN ('RARITY_CREATED', 'RARITY_UPDATED'))
            OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action IN (
                    'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'
                ))
        );

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
        CHECK (
            entity_type IN (
                'GAME', 'EXPANSION', 'CARD_SET', 'CARD',
                'CATALOG_IMPORT_JOB', 'RARITY', 'RARITY_EXTERNAL_MAPPING'
            )
        );

-- ================================================================
-- Confirmado executado (2026-08-07): as três definições atuais em
-- produção (lidas via pg_get_constraintdef()) conferem exatamente
-- com o resultado desta migration. Usada por admin_create_rarity()
-- (2099), admin_update_rarity() (2100),
-- admin_create_rarity_external_mapping() (2101),
-- admin_update_rarity_external_mapping() (2102) e
-- svc_apply_catalog_import_revalidation() (2106), todas sem erro
-- de violação de CHECK observado em produção.
-- ================================================================
