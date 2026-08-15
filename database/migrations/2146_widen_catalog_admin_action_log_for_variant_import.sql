/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2146 - Widen Catalog Admin Action Log for Variant Import
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Amplia os três CHECKs de public.catalog_admin_action_log para
aceitar a auditoria de confirmação de importação de Card Variant
(Incremento 3, ADR-028) — mesmo raciocínio da Query 2054 (que
ampliou os mesmos CHECKs para Importar Cartas). Nenhuma coluna
nova, nenhuma mudança de tipo — só os domínios fechados de
action/entity_type e a combinação permitida entre eles.

Regras de Negócio:
- action ganha 'CARD_VARIANT_IMPORT_CONFIRMED'.
- entity_type ganha 'CATALOG_VARIANT_IMPORT_JOB'.
- ck_catalog_admin_action_log_action_entity_match ganha a
  combinação (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND
  action = 'CARD_VARIANT_IMPORT_CONFIRMED') — só essa, nenhuma
  outra ação para esta entidade nesta rodada (não há decisão/
  revalidação com ação própria auditada, mesmo desenho do
  Incremento 3: admin_decide_catalog_variant_import_row, Query
  2144, não grava em catalog_admin_action_log).
- Nenhuma linha existente é afetada — CHECK só se aplica a novos
  INSERTs/UPDATEs; os valores antigos continuam válidos porque
  nenhum foi removido, só adicionado.
- DROP CONSTRAINT + ADD CONSTRAINT (não existe ALTER CHECK direto
  no Postgres) — mesma técnica já usada pela Query 2054.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2054 - Widen Catalog Admin Action Log for Catalog Import.
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
        'CARD_VARIANT_IMPORT_CONFIRMED'
    ));

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
    CHECK (entity_type IN (
        'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
        'RARITY', 'RARITY_EXTERNAL_MAPPING',
        'CATALOG_VARIANT_IMPORT_JOB'
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
    );

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com as Queries 2143-2145.
-- Validado por uma linha real de CARD_VARIANT_IMPORT_CONFIRMED gravada
-- durante o dry-run de 2145 (dentro de BEGIN...ROLLBACK) e aceita sem
-- violação de CHECK.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.catalog_admin_action_log'::regclass AND contype = 'c'
-- ORDER BY conname;
-- Esperado: os três CHECKs incluindo CARD_VARIANT_IMPORT_CONFIRMED /
-- CATALOG_VARIANT_IMPORT_JOB, todos os valores antigos preservados.
-- ================================================================
