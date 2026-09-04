/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6071 - Pokemon Region External Reference Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-REGION-FOUNDATION-
               PHYSICAL-STAGING-01; aplicado em 2026-09-04 via
               POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01)

Descrição...:
Normalização, governança de identidade e updated_at para
pokemon_region_external_reference (Query 6070). Mesmo padrão de três
triggers de pokemon_species_external_reference (Query 6021) e
pokedex_external_reference (Query 6051) — mesmos cinco campos
protegidos (id, FK para a entidade pai, FK para a Fonte, identificador
externo, created_at).

Campos protegidos contra UPDATE por govern_pokemon_region_external_
reference(): id, pokemon_region_id, asset_source_id, external_region_id,
created_at.

Segurança: EXECUTE revogado de PUBLIC/anon/authenticated já nesta
Query, mesma disciplina de 6031/6041/6051.

Pré-requisitos:
- Query 6070 - Create Pokemon Region External Reference Table.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_pokemon_region_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.external_region_id := BTRIM(NEW.external_region_id);
    IF NEW.source_url IS NOT NULL THEN
        NEW.source_url := NULLIF(BTRIM(NEW.source_url), '');
    END IF;
    NEW.metadata := COALESCE(NEW.metadata, '{}'::JSONB);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_pokemon_region_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEMON_REGION_EXTERNAL_REFERENCE_ID_IMMUTABLE';
    END IF;
    IF NEW.pokemon_region_id IS DISTINCT FROM OLD.pokemon_region_id THEN
        RAISE EXCEPTION 'POKEMON_REGION_EXTERNAL_REFERENCE_REGION_IMMUTABLE';
    END IF;
    IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
        RAISE EXCEPTION 'POKEMON_REGION_EXTERNAL_REFERENCE_ASSET_SOURCE_IMMUTABLE';
    END IF;
    IF NEW.external_region_id IS DISTINCT FROM OLD.external_region_id THEN
        RAISE EXCEPTION 'POKEMON_REGION_EXTERNAL_REFERENCE_EXTERNAL_ID_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEMON_REGION_EXTERNAL_REFERENCE_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokemon_region_external_reference_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_pokemon_region_external_reference
BEFORE INSERT OR UPDATE
ON public.pokemon_region_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.normalize_pokemon_region_external_reference();

CREATE TRIGGER trg_020_govern_pokemon_region_external_reference
BEFORE UPDATE
ON public.pokemon_region_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokemon_region_external_reference();

CREATE TRIGGER trg_030_touch_pokemon_region_external_reference_updated_at
BEFORE UPDATE
ON public.pokemon_region_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokemon_region_external_reference_updated_at();

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_region_external_reference() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokemon_region_external_reference() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokemon_region_external_reference_updated_at() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01). Postcheck
-- independente (GATE 8, POKEMON-REGION-FOUNDATION-CANONICAL-
-- PROMOTION-01) confirmou os três triggers ativos em pokemon_region_
-- external_reference e EXECUTE revogado (has_function_privilege false)
-- para anon/authenticated nas três funções. Comportamento de
-- imutabilidade e normalização re-verificados via função de sonda
-- observável (RAISE NOTICE não é visível pelas ferramentas de
-- execução MCP usadas nesta rodada).
-- ================================================================
