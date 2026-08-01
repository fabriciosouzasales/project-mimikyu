/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2055 - Add CATALOG_IMPORT_JOB Entity Type to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Corrige um gap real da Query 2054: catalog_admin_action_log (Query
2010) tem TRÊS constraints de validação, não duas —
ck_catalog_admin_action_log_action_valid,
ck_catalog_admin_action_log_entity_type_valid e
ck_catalog_admin_action_log_action_entity_match. A Query 2054
ampliou as duas primeiras... na verdade ampliou a primeira e a
terceira, mas esqueceu inteiramente
ck_catalog_admin_action_log_entity_type_valid (que restringe
entity_type a 'GAME'/'EXPANSION'/'CARD_SET'/'CARD', sem
'CATALOG_IMPORT_JOB') — descoberto na execução real de
admin_start_catalog_import() (Query 2080) pela Query 2814
(validação funcional), que falhou com
"new row for relation catalog_admin_action_log violates check
constraint ck_catalog_admin_action_log_entity_type_valid".

Regras de Negócio:
- ck_catalog_admin_action_log_entity_type_valid ganha
  'CATALOG_IMPORT_JOB' na lista de entity_type reconhecidos —
  única mudança desta migration.
- Nenhuma linha existente é afetada — só a definição da constraint
  muda; recriada via DROP + ADD (mesma técnica de 2041/2043/2049/
  2054).

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2054 - Widen Catalog Admin Action Log for Catalog Import
  (gap corrigido aqui).
================================================================
*/

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
        CHECK (
            entity_type IN ('GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB')
        );
