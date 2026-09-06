/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6121 - Create Primary Representative Integrity Trigger
Versão......: 1.0 (CONFIRMADO EXECUTADO E PROMOVIDO)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01;
               executada no banco real em IMPLEMENTATION-RESUME-02;
               promovida para database/schema/ em COLLECTIONS-POKEDEX-
               FATIA-D-PROMOTION-CLOSEOUT-01 — corpo SQL byte-idêntico
               ao executado, apenas cabeçalho Status/Versão/Data
               atualizados)

Descrição...:
Dois triggers sobre collection_pokedex_position_primary_representative
(Query 6120):

trg_010: integridade cruzada (mandato STAGING-01, item 2 — "Trigger
continua responsável por validar que a Assignment apontada pertence
exatamente à mesma Collection + Position"). As FKs de 6120 garantem que
collection_allocation_id referencia uma Assignment que EXISTE, mas não
impedem uma linha como (collection_id=X, pokedex_position_id=Y,
collection_allocation_id=<Assignment que na verdade pertence a
Z, W>) — essa checagem cruzada exige um JOIN até
collection_pokedex_position_assignment/collection_allocation, que uma
FK simples não expressa. BEFORE INSERT OR UPDATE (o único UPDATE real
esperado é a troca de collection_allocation_id via ON CONFLICT DO
UPDATE em set_pokedex_position_primary_representative(), Query 6125,
renumerada de 6124 em RENUMBER-FIX-STAGING-01 —
substituir qual Assignment é Primary da mesma Position).

trg_020: touch de updated_at, mesmo padrão de
touch_card_primary_species_updated_at() (Query 6113) — relevante aqui
porque, diferente da Assignment (Query 6117, imutável), esta tabela é
legitimamente atualizável (replace de Primary Representative).

Pré-requisitos:
- Query 6117 - Create Collection Pokédex Position Assignment Table.
- Query 6120 - Create Collection Pokédex Position Primary Representative Table.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.validate_pokedex_position_primary_representative_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_actual_collection_id       UUID;
    v_actual_pokedex_position_id UUID;
BEGIN
    SELECT ca.collection_id, a.pokedex_position_id
      INTO v_actual_collection_id, v_actual_pokedex_position_id
      FROM public.collection_pokedex_position_assignment a
      JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
     WHERE a.collection_allocation_id = NEW.collection_allocation_id;

    IF NOT FOUND THEN
        -- Defesa em profundidade: a FK de 6120 já deveria impedir isto.
        RAISE EXCEPTION 'PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND';
    END IF;

    IF v_actual_collection_id IS DISTINCT FROM NEW.collection_id
       OR v_actual_pokedex_position_id IS DISTINCT FROM NEW.pokedex_position_id
    THEN
        RAISE EXCEPTION 'PRIMARY_REPRESENTATIVE_ASSIGNMENT_MISMATCH: a Assignment referenciada não pertence a esta Collection+Position.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokedex_position_primary_representative_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_validate_primary_representative_integrity
BEFORE INSERT OR UPDATE
ON public.collection_pokedex_position_primary_representative
FOR EACH ROW
EXECUTE FUNCTION public.validate_pokedex_position_primary_representative_integrity();

CREATE TRIGGER trg_020_touch_primary_representative_updated_at
BEFORE UPDATE
ON public.collection_pokedex_position_primary_representative
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokedex_position_primary_representative_updated_at();

COMMIT;
