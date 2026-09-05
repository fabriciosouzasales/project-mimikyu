/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5088 - Create Collection Pokedex Reference updated_at Trigger
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01; aplicado em
               2026-09-05 via COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Mesmo padrão de set_updated_at() já reaproveitado por toda a base
(ver 5031/5041/5050/5053/5073).

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou a trigger presente em collection_pokedex_reference, disparando
BEFORE UPDATE via set_updated_at(). Zero resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

CREATE TRIGGER trg_collection_pokedex_reference_updated_at
    BEFORE UPDATE ON public.collection_pokedex_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMIT;
