/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2121 - Add Manual Card Asset Import Action to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Amplia duas das três CHECK constraints de public.catalog_admin_
action_log (Query 2010, última alteração real na Query 2098) para
reconhecer a nova ação CARD_ASSET_MANUAL_IMPORT_COMPLETED — auditoria
agregada por LOTE (não por arquivo) do canal de importação manual de
imagens via UI (ADR-026, emenda "Segundo ponto de entrada via UI").

Associada a entity_type = 'CARD_SET' (a Coleção é a entidade afetada
pelo lote inteiro) — mesma granularidade já usada por
CATALOG_IMPORT_CONFIRMED (entity_type = 'CATALOG_IMPORT_JOB', também
uma linha agregada por chamada, nunca uma por Card/Card Asset).
entity_type_valid NÃO precisa mudar: 'CARD_SET' já é reconhecido
desde a Query 2010.

Confirmado por grep em database/migrations/ (2026-08-07) que a Query
2098 é a última a alterar estruturalmente esta tabela — a 2111 só a
cita em comentário, sem tocar nas constraints.

Regras de Negócio:
- Mesma técnica das Queries 2041/2043/2049/2054/2098 (DROP + ADD
  CONSTRAINT — Postgres não permite ALTER CONSTRAINT em CHECK).
- Nenhuma linha existente é afetada — só a definição das duas
  constraints muda.
- admin_log_manual_card_asset_import_batch() (Query 2122, seguinte)
  depende desta Query já aplicada — sem ela, a primeira tentativa de
  gravar CARD_ASSET_MANUAL_IMPORT_COMPLETED falharia com violação de
  CHECK.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log
  (última definição cumulativa das duas constraints alteradas aqui).
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
                'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
                'CARD_ASSET_MANUAL_IMPORT_COMPLETED'
            )
        );

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match
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
                    'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED'
                ))
            OR (entity_type = 'RARITY' AND action IN ('RARITY_CREATED', 'RARITY_UPDATED'))
            OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action IN (
                    'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'
                ))
        );

-- ================================================================
-- Resultado esperado: "Success. No rows returned".
--
-- Como validar:
-- SELECT conname, pg_get_constraintdef(oid) AS definicao
-- FROM pg_constraint
-- WHERE conrelid = 'public.catalog_admin_action_log'::regclass
--   AND conname IN (
--       'ck_catalog_admin_action_log_action_valid',
--       'ck_catalog_admin_action_log_action_entity_match'
--   );
--
-- Esperado: CARD_ASSET_MANUAL_IMPORT_COMPLETED presente na primeira
-- definição e associada a entity_type = 'CARD_SET' na segunda.
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-07): pg_get_constraintdef() das duas
-- constraints, em produção, confere exatamente com o esperado.
-- ================================================================
