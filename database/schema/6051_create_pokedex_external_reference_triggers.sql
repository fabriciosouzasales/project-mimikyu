/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6051 - Pokedex External Reference Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em COLLECTIONS-POKEDEX-POSITION-
               PHYSICAL-STAGING-01, aplicado em 2026-09-04 via
               COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01)

Descrição...:
Normalização, governança de identidade e updated_at para
pokedex_external_reference (Query 6050). Mesmo padrão de três
triggers de pokemon_species_external_reference (Query 6021) — mesmos
cinco campos protegidos (id, FK para a entidade pai, FK para a Fonte,
identificador externo, created_at).

Campos protegidos contra UPDATE por govern_pokedex_external_
reference(): id, pokedex_id, asset_source_id, external_pokedex_id,
created_at.

Segurança: EXECUTE revogado de PUBLIC/anon/authenticated já nesta
Query, mesma disciplina de 6031/6041.

Pré-requisitos:
- Query 6050 - Create Pokedex External Reference Table.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_pokedex_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.external_pokedex_id := BTRIM(NEW.external_pokedex_id);
    IF NEW.source_url IS NOT NULL THEN
        NEW.source_url := NULLIF(BTRIM(NEW.source_url), '');
    END IF;
    NEW.metadata := COALESCE(NEW.metadata, '{}'::JSONB);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_pokedex_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEDEX_EXTERNAL_REFERENCE_ID_IMMUTABLE';
    END IF;
    IF NEW.pokedex_id IS DISTINCT FROM OLD.pokedex_id THEN
        RAISE EXCEPTION 'POKEDEX_EXTERNAL_REFERENCE_POKEDEX_IMMUTABLE';
    END IF;
    IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
        RAISE EXCEPTION 'POKEDEX_EXTERNAL_REFERENCE_ASSET_SOURCE_IMMUTABLE';
    END IF;
    IF NEW.external_pokedex_id IS DISTINCT FROM OLD.external_pokedex_id THEN
        RAISE EXCEPTION 'POKEDEX_EXTERNAL_REFERENCE_EXTERNAL_ID_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEDEX_EXTERNAL_REFERENCE_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokedex_external_reference_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_pokedex_external_reference
BEFORE INSERT OR UPDATE
ON public.pokedex_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.normalize_pokedex_external_reference();

CREATE TRIGGER trg_020_govern_pokedex_external_reference
BEFORE UPDATE
ON public.pokedex_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokedex_external_reference();

CREATE TRIGGER trg_030_touch_pokedex_external_reference_updated_at
BEFORE UPDATE
ON public.pokedex_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokedex_external_reference_updated_at();

REVOKE EXECUTE ON FUNCTION public.normalize_pokedex_external_reference() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokedex_external_reference() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokedex_external_reference_updated_at() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01). Postcheck
-- físico (Query 6800, Seção 1.8) confirmou os 3 triggers ativos.
-- Validação comportamental (Seção 2.3) confirmou normalize e as
-- imutabilidades; Seção 3 confirmou EXECUTE ausente para anon/
-- authenticated nas 3 funções. Script completo permanece em
-- database/proposals/2026-09-04-pokedex-foundation/ como evidência
-- histórica — não promovido para database/schema/.
-- ================================================================
