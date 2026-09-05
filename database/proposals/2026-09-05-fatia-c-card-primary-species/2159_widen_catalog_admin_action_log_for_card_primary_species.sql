/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2159 - Widen Catalog Admin Action Log for Card Primary Species
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-REVISION-01;
               corrigido em ...-PREMISE-DIVERGENCE-FIX-01)

Correção v1.1 (PREMISE-DIVERGENCE-FIX-01) — a v1.0 partia do baseline
documentado em database/schema/2010_create_catalog_admin_action_log.sql
v1.3 (14 actions, 5 entity_types, 5 ramos de action_entity_match). A
tentativa de execução real (IMPLEMENTATION-01) foi interrompida pela
regra de parada antes de qualquer escrita: pre-flight (SELECT
pg_get_constraintdef() direto no banco, 2026-09-05) confirmou que o
estado físico real de public.catalog_admin_action_log já havia
evoluído para 27 actions / 10 entity_types / 10 ramos de match —
ampliado por outras frentes do projeto (Rarity, Rarity External
Mapping, Card Variant Type, Card Variant Type External Mapping, Card
Asset Manual Import, Catalog Variant Import Job, Catalog Import Rows
Revalidated) através de migrations já aplicadas ao banco mas nunca
promovidas de volta ao arquivo canônico database/schema/2010...sql —
esse arquivo está desatualizado frente ao banco real, por isso NÃO é
usado como baseline desta correção.

Confirmado por consulta direta (SELECT DISTINCT action, entity_type
FROM catalog_admin_action_log) que existem hoje 223 linhas reais
usando exatamente os 9 pares action/entity_type que a v1.0 desta Query
teria removido da CHECK — a v1.0, se executada, teria falhado na hora
(ADD CONSTRAINT valida linhas existentes por padrão) ou, na pior
hipótese, quebrado silenciosamente escritas futuras de funções
administrativas de Rarity/Card Variant Type/Card Asset Import ativas
em produção, sem nenhuma relação com esta Fatia C.

Esta v1.1 é ESTRITAMENTE ADITIVA sobre o estado físico real capturado
via pg_get_constraintdef() nesta correção (reproduzido abaixo,
byte-semanticamente idêntico às três CHECKs vigentes — apenas
reescrito de `= ANY (ARRAY[...])`, forma canônica de exibição do
Postgres, para `IN (...)`, forma de autoria já usada em todo o
projeto; ambas são semanticamente idênticas). Nenhum valor já aceito em
produção foi removido, renomeado ou reordenado — os dois valores novos
desta Fatia (`CARD_PRIMARY_SPECIES_RESOLVED`/`_CORRECTED`) e o
entity_type novo (`CARD_PRIMARY_SPECIES`) foram apenas acrescentados ao
final de cada lista/à lista de ramos:

ck_catalog_admin_action_log_action_valid (real, 27 valores, capturado
2026-09-05): GAME_CREATED, GAME_UPDATED, GAME_DELETED,
EXPANSION_CREATED, EXPANSION_UPDATED, EXPANSION_DELETED,
CARD_SET_CREATED, CARD_SET_UPDATED, CARD_SET_DELETED, CARD_CREATED,
CARD_UPDATED, CARD_DEACTIVATED, CARD_REACTIVATED, CATALOG_IMPORT_JOB,
CATALOG_IMPORT_CONFIRMED, CATALOG_IMPORT_ROWS_REVALIDATED,
RARITY_CREATED, RARITY_UPDATED, RARITY_EXTERNAL_MAPPING_CREATED,
RARITY_EXTERNAL_MAPPING_UPDATED, CARD_ASSET_MANUAL_IMPORT_COMPLETED,
CARD_VARIANT_IMPORT_CONFIRMED,
CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED, CARD_VARIANT_TYPE_CREATED,
CARD_VARIANT_TYPE_UPDATED, CARD_VARIANT_TYPE_DEACTIVATED,
CARD_VARIANT_TYPE_REACTIVATED. +2 novos desta Fatia =
CARD_PRIMARY_SPECIES_RESOLVED, CARD_PRIMARY_SPECIES_CORRECTED = 29
valores finais.

ck_catalog_admin_action_log_entity_type_valid (real, 10 valores,
capturado 2026-09-05): GAME, EXPANSION, CARD_SET, CARD,
CATALOG_IMPORT_JOB, RARITY, RARITY_EXTERNAL_MAPPING,
CATALOG_VARIANT_IMPORT_JOB, CARD_VARIANT_TYPE_EXTERNAL_MAPPING,
CARD_VARIANT_TYPE. +1 novo desta Fatia = CARD_PRIMARY_SPECIES = 11
valores finais.

ck_catalog_admin_action_log_action_entity_match (real, 10 ramos,
capturado 2026-09-05): os 10 ramos vigentes (GAME/EXPANSION/CARD_SET
[incl. CARD_ASSET_MANUAL_IMPORT_COMPLETED]/CARD/CATALOG_IMPORT_JOB
[incl. CATALOG_IMPORT_ROWS_REVALIDATED]/RARITY/
RARITY_EXTERNAL_MAPPING/CATALOG_VARIANT_IMPORT_JOB/
CARD_VARIANT_TYPE_EXTERNAL_MAPPING/CARD_VARIANT_TYPE) preservados
integralmente, byte a byte. +1 ramo novo desta Fatia:
CARD_PRIMARY_SPECIES → (CARD_PRIMARY_SPECIES_RESOLVED,
CARD_PRIMARY_SPECIES_CORRECTED) = 11 ramos finais.

Validação cruzada contra dados reais (2026-09-05, antes de editar este
arquivo): SELECT DISTINCT action, entity_type FROM
catalog_admin_action_log retornou 23 pares distintos, todos já
cobertos pelos 27 actions / 10 entity_types / 10 ramos preservados
acima — nenhuma linha existente violaria as três CHECKs revisadas
desta v1.1 (a revisão é um superconjunto estrito do que já valida hoje,
nunca um subconjunto).

Duas ações desta Fatia permanecem inalteradas frente à v1.0:
CARD_PRIMARY_SPECIES_RESOLVED (primeira resolução — nenhuma linha
existia antes em card_primary_species para esta Card) e
CARD_PRIMARY_SPECIES_CORRECTED (já existia uma linha, seus valores
foram substituídos). entity_id = card_id (identidade natural —
card_primary_species.card_id é PK=FK 1:1 para card.id).

Resoluções automáticas em lote (Query 6115, service_role) continuam
NÃO usando nenhuma destas ações — não escrevem em
catalog_admin_action_log (ver racional completo no cabeçalho de 6112
v1.1 e no README desta pasta). Nenhuma outra Query desta Fatia
(6112/6113/6114/6115) foi tocada nesta correção.

IMPLEMENTATION-01 (rodada anterior) não chegou a executar nenhuma
Query no banco real — o STOP ocorreu no pre-flight, antes de qualquer
DDL. Esta correção não reverte nada: parte do mesmo estado físico
real (zero mudança) e apenas corrige o arquivo de proposta.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table (canônica no
  repositório, porém desatualizada frente ao banco real — não usada
  como baseline desta correção; ver acima).
- Query 6112 - Create Card Primary Species Table.
================================================================
*/

BEGIN;

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
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
            'CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED'
        )
    );

ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
    CHECK (
        entity_type IN (
            'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
            'RARITY', 'RARITY_EXTERNAL_MAPPING', 'CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', 'CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES'
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
                'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED', 'CARD_ASSET_MANUAL_IMPORT_COMPLETED'
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
        OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action = 'CARD_VARIANT_IMPORT_CONFIRMED')
        OR (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED')
        OR (entity_type = 'CARD_VARIANT_TYPE' AND action IN (
                'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
                'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'
            ))
        OR (entity_type = 'CARD_PRIMARY_SPECIES' AND action IN (
                'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED'
            ))
    );

COMMIT;
