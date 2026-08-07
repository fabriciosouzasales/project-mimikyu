/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2097 - rarity_external_mapping Triggers
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Trigger de updated_at para rarity_external_mapping (Query 2096) —
reaproveita set_updated_at(), já usada por outras tabelas do
módulo (ex. card_set, expansion). Nenhuma função nova criada
nesta Query.

Pré-requisitos:
- Query 2096 - Create rarity_external_mapping Table.
- set_updated_at() (função compartilhada já existente).
================================================================
*/

CREATE TRIGGER trg_rarity_external_mapping_set_updated_at
    BEFORE UPDATE ON public.rarity_external_mapping
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- ================================================================
-- Confirmado executado (2026-08-07): trigger presente em
-- pg_trigger, disparando corretamente em admin_update_rarity_
-- external_mapping() (Query 2102).
-- ================================================================
