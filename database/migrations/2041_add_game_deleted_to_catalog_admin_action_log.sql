/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2041 - Add GAME_DELETED to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Adiciona 'GAME_DELETED' às duas constraints de action de
public.catalog_admin_action_log (Query 2010), habilitando o
registro de auditoria de admin_delete_game() (Query 2042) — ver
ADR-023, emenda 2026-07-26 ("Game: exclusão real via UI").

Regras de Negócio:
- ck_catalog_admin_action_log_action_valid ganha 'GAME_DELETED'
  na lista de ações reconhecidas.
- ck_catalog_admin_action_log_action_entity_match ganha
  'GAME_DELETED' ao conjunto de ações válidas para
  entity_type = 'GAME', junto com GAME_CREATED/GAME_UPDATED.
- Nenhuma linha existente é afetada — só a definição da constraint
  muda; ambas são recriadas via DROP + ADD (mesma técnica já usada
  em correções de constraint anteriores no projeto).

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
        CHECK (
            action IN (
                'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
                'EXPANSION_CREATED', 'EXPANSION_UPDATED',
                'CARD_SET_CREATED', 'CARD_SET_UPDATED',
                'CARD_CREATED', 'CARD_UPDATED',
                'CARD_DEACTIVATED', 'CARD_REACTIVATED'
            )
        );

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match
        CHECK (
            (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED'))
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED'))
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
        );
