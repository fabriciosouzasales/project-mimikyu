/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2141 - card_variant_type_external_mapping Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Trigger de updated_at para card_variant_type_external_mapping (Query
2140) — reaproveita set_updated_at(). Mesmo padrão de
rarity_external_mapping (Query 2097): sem trigger de normalização, os
campos normalized_* são responsabilidade de quem grava.

Pré-requisitos:
- Query 2140 - Create card_variant_type_external_mapping Table.
- set_updated_at() (função compartilhada já existente).
================================================================
*/

CREATE TRIGGER trg_card_variant_type_external_mapping_set_updated_at
    BEFORE UPDATE ON public.card_variant_type_external_mapping
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com as Queries 2136-2140/2142.
-- ================================================================
