/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6011 - Pokemon Species Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (aplicado em 2026-09-04,
               COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01)

Descrição...:
Normalização, governança de identidade e updated_at para
pokemon_species (Query 6010). Mesmo padrão de três triggers de Query
6001/241.

Campos protegidos contra UPDATE por govern_pokemon_species() (decisão
congelada, COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01):
id e created_at, apenas — identidade técnica.

generation_id, national_dex_number, canonical_name e is_active
permanecem corrigíveis administrativamente (reconciliação editorial),
deliberadamente NÃO protegidos por este trigger.

Pré-requisitos:
- Query 6010 - Create Pokemon Species Table.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_pokemon_species()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.canonical_name := BTRIM(NEW.canonical_name);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_pokemon_species()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEMON_SPECIES_ID_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEMON_SPECIES_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokemon_species_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_pokemon_species
BEFORE INSERT OR UPDATE
ON public.pokemon_species
FOR EACH ROW
EXECUTE FUNCTION public.normalize_pokemon_species();

CREATE TRIGGER trg_020_govern_pokemon_species
BEFORE UPDATE
ON public.pokemon_species
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokemon_species();

CREATE TRIGGER trg_030_touch_pokemon_species_updated_at
BEFORE UPDATE
ON public.pokemon_species
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokemon_species_updated_at();

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01). Postcheck
-- físico confirmou os 3 triggers ativos. Teste comportamental
-- confirmou rejeição de UPDATE em id (POKEMON_SPECIES_ID_IMMUTABLE) e
-- confirmou que national_dex_number/generation_id permanecem
-- corrigíveis.
-- ================================================================
