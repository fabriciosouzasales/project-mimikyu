/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2043 - Add EXPANSION_DELETED to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Adiciona 'EXPANSION_DELETED' às duas constraints de action de
public.catalog_admin_action_log (Query 2010), habilitando o
registro de auditoria de admin_delete_expansion() (Query 2044) —
ver ADR-023, emenda 2026-07-31 ("Expansion: exclusão real via
UI"), mesmo padrão já aplicado a Game (Query 2041).

Regras de Negócio:
- ck_catalog_admin_action_log_action_valid ganha 'EXPANSION_DELETED'
  na lista de ações reconhecidas.
- ck_catalog_admin_action_log_action_entity_match ganha
  'EXPANSION_DELETED' ao conjunto de ações válidas para
  entity_type = 'EXPANSION', junto com
  EXPANSION_CREATED/EXPANSION_UPDATED.
- Nenhuma linha existente é afetada — só a definição da constraint
  muda; ambas são recriadas via DROP + ADD (mesma técnica de 2041).

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2041 - Add GAME_DELETED to Catalog Admin Action Log.
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
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED'))
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
        );
