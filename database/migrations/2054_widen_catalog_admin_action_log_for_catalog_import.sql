/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2054 - Widen Catalog Admin Action Log for Catalog Import
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Adiciona 'CATALOG_IMPORT_JOB' e 'CATALOG_IMPORT_CONFIRMED' às duas
constraints de action de public.catalog_admin_action_log (Query
2010), habilitando o registro de auditoria do fluxo de ingestão de
Cards — ver ADR-024 (Catalog Card Ingestion Strategy). Mesmo padrão
já aplicado a Game/Expansion/Card Set (Queries 2041/2043/2049).

Regras de Negócio:
- ck_catalog_admin_action_log_action_valid ganha
  'CATALOG_IMPORT_JOB' e 'CATALOG_IMPORT_CONFIRMED' na lista de
  ações reconhecidas.
- ck_catalog_admin_action_log_action_entity_match ganha um novo
  entity_type ('CATALOG_IMPORT_JOB') associado a essas duas ações —
  a entidade auditada é sempre o job de importação (catalog_import_
  job.id), nunca uma Card individual, mesmo em uma confirmação que
  afeta várias linhas. Ver ADR-024, "uma linha de auditoria
  agregada por chamada de confirmação, nunca uma por Card".
- 'CATALOG_IMPORT_JOB' é gravada por admin_start_catalog_import()
  (Query 2080), ao criar o job. 'CATALOG_IMPORT_CONFIRMED' é
  gravada por admin_confirm_catalog_import() (Query 2082), uma vez
  por chamada (não uma vez por Card confirmada).
- admin_decide_catalog_import_row() (Query 2081) delibera-mente NÃO
  grava nesta auditoria: decisões linha a linha durante a revisão
  são reversíveis e de baixo risco (a linha em si já guarda seu
  próprio decision_status); só a confirmação, que grava nas tabelas
  canônicas, é irreversível o suficiente para justificar uma
  entrada de auditoria administrativa.
- Nenhuma linha existente é afetada — só a definição da constraint
  muda; ambas são recriadas via DROP + ADD (mesma técnica de
  2041/2043/2049).

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2049 - Add CARD_SET_DELETED to Catalog Admin Action Log
  (estado real do banco do qual esta migration parte).
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
                'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED'
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
                    'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED'
                ))
        );
