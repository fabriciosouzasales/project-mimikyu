/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2151 - Widen Catalog Admin Action Log for Variant Mapping
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Amplia os três CHECKs de public.catalog_admin_action_log para
aceitar a auditoria de resolução de mapeamento externo de Card
Variant Type (admin_resolve_catalog_variant_import_mapping(), Query
2150) — mesmo raciocínio da Query 2146 (que ampliou os mesmos
CHECKs para a confirmação de importação de variantes). Nenhuma
coluna nova, nenhuma mudança de tipo — só os domínios fechados de
action/entity_type e a combinação permitida entre eles.

Regras de Negócio:
- action ganha 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'.
- entity_type ganha 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING'.
- ck_catalog_admin_action_log_action_entity_match ganha a
  combinação (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING'
  AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED') — só
  essa, nenhuma ação de UPDATE nesta rodada (este incremento não
  permite editar um mapeamento já criado, só criar um novo — mesmo
  escopo aprovado por Fabrício).
- Nenhuma linha existente é afetada — CHECK só se aplica a novos
  INSERTs/UPDATEs; os valores antigos continuam válidos porque
  nenhum foi removido, só adicionado.
- DROP CONSTRAINT + ADD CONSTRAINT (não existe ALTER CHECK direto
  no Postgres) — mesma técnica já usada pelas Queries 2054/2146.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2146 - Widen Catalog Admin Action Log for Variant Import.
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
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'
    ));

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
    CHECK (entity_type IN (
        'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
        'RARITY', 'RARITY_EXTERNAL_MAPPING',
        'CATALOG_VARIANT_IMPORT_JOB',
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING'
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
    );

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com a Query 2150. Validado por
-- uma linha real de CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED gravada
-- pela execução real de admin_resolve_catalog_variant_import_mapping()
-- (mapping_id 1558d092-b768-473b-9abf-fc1e869c67af), aceita sem
-- violação de CHECK.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.catalog_admin_action_log'::regclass AND contype = 'c'
-- ORDER BY conname;
-- Esperado: os três CHECKs incluindo CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED /
-- CARD_VARIANT_TYPE_EXTERNAL_MAPPING, todos os valores antigos preservados.
-- ================================================================
