/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2049 - Add CARD_SET_DELETED to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Adiciona 'CARD_SET_DELETED' às duas constraints de action de
public.catalog_admin_action_log (Query 2010), habilitando o
registro de auditoria de admin_delete_card_set() (Query 2050) —
ver ADR-023, emenda 2026-07-31 ("Card Set: atualização e
exclusão real via UI"), mesmo padrão já aplicado a Game (Query
2041) e Expansion (Query 2043).

Regras de Negócio:
- ck_catalog_admin_action_log_action_valid ganha 'CARD_SET_DELETED'
  na lista de ações reconhecidas.
- ck_catalog_admin_action_log_action_entity_match ganha
  'CARD_SET_DELETED' ao conjunto de ações válidas para
  entity_type = 'CARD_SET', junto com
  CARD_SET_CREATED/CARD_SET_UPDATED.
- Nenhuma linha existente é afetada — só a definição da constraint
  muda; ambas são recriadas via DROP + ADD (mesma técnica de 2041/
  2043).
- Esta migration parte do estado real do banco (já inclui
  'EXPANSION_DELETED', adicionada pela migration 2043 e confirmada
  executada por Fabrício em 2026-07-31) — não do arquivo canônico
  `database/schema/2010_create_catalog_admin_action_log.sql`
  anterior a este ciclo, que estava desatualizado (não incluía
  'EXPANSION_DELETED' — gap corrigido no mesmo commit que esta
  migration, ver o próprio arquivo canônico).

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2041 - Add GAME_DELETED to Catalog Admin Action Log.
- Query 2043 - Add EXPANSION_DELETED to Catalog Admin Action Log.
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
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
        );
