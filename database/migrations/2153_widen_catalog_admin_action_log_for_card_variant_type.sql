/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2153 - Widen Catalog Admin Action Log for Card Variant Type
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Amplia os três CHECKs de public.catalog_admin_action_log para
aceitar a auditoria do CRUD administrativo de Card Variant Type
(admin_create_card_variant_type()/admin_update_card_variant_type()/
admin_deactivate_card_variant_type()/admin_reactivate_card_variant_type(),
Queries 2154-2157) — mesma técnica das Queries 2146/2151 (DROP+ADD
CONSTRAINT, não existe ALTER CHECK direto no Postgres).

Regras de Negócio:
- action ganha 'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
  'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'.
  Nenhuma action de exclusão física — V1 desta governança não inclui
  DELETE (decisão explícita de Fabrício).
- entity_type ganha 'CARD_VARIANT_TYPE'.
- ck_catalog_admin_action_log_action_entity_match ganha a combinação
  (entity_type = 'CARD_VARIANT_TYPE' AND action IN (as 4 actions
  acima)).
- Nenhuma linha existente é afetada — CHECK só se aplica a novos
  INSERTs/UPDATEs; os valores antigos continuam válidos porque
  nenhum foi removido, só adicionado.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2151 - Widen Catalog Admin Action Log for Variant Mapping.
================================================================
*/

BEGIN;

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (action IN (
        'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
        'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
        'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
        'CARD_CREATED', 'CARD_UPDATED',
        'CARD_DEACTIVATED', 'CARD_REACTIVATED',
        'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED',
        'RARITY_CREATED', 'RARITY_UPDATED',
        'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
        'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
        'CARD_VARIANT_IMPORT_CONFIRMED',
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
        'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
        'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'
    ));

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
    CHECK (entity_type IN (
        'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
        'RARITY', 'RARITY_EXTERNAL_MAPPING',
        'CATALOG_VARIANT_IMPORT_JOB',
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING',
        'CARD_VARIANT_TYPE'
    ));

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match
    CHECK (
        (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED'))
        OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED'))
        OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED', 'CARD_ASSET_MANUAL_IMPORT_COMPLETED'))
        OR (entity_type = 'CARD' AND action IN ('CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'))
        OR (entity_type = 'CATALOG_IMPORT_JOB' AND action IN ('CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED'))
        OR (entity_type = 'RARITY' AND action IN ('RARITY_CREATED', 'RARITY_UPDATED'))
        OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action IN ('RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'))
        OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action = 'CARD_VARIANT_IMPORT_CONFIRMED')
        OR (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED')
        OR (entity_type = 'CARD_VARIANT_TYPE' AND action IN ('CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED', 'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'))
    );

COMMIT;

-- ================================================================
-- Como validar:
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.catalog_admin_action_log'::regclass AND contype = 'c'
-- ORDER BY conname;
-- Esperado: os três CHECKs incluindo os 4 actions de
-- CARD_VARIANT_TYPE_* / entity_type CARD_VARIANT_TYPE, todos os
-- valores antigos preservados.
-- ================================================================

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com a Query 2152. Validado via
-- pg_get_constraintdef() pós-execução: os três CHECKs incluem os 4
-- actions novos e o entity_type CARD_VARIANT_TYPE, todos os valores
-- antigos (RARITY_*, CARD_*, CARD_VARIANT_TYPE_EXTERNAL_MAPPING_*
-- etc.) preservados integralmente.
-- ================================================================
