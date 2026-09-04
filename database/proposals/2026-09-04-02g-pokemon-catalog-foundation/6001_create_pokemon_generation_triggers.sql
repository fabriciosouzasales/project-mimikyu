/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6001 - Pokemon Generation Triggers
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04

Descrição...:
Normalização, governança de identidade e updated_at para
pokemon_generation (Query 6000). Mesmo padrão de três triggers já
estabelecido no repositório para tabelas com governança de identidade
plena (normalize_/govern_/touch_..._updated_at, nomes de trigger
numerados trg_010_/trg_020_/trg_030_ — mesma convenção de
card_set_external_reference, Query 241).

Campos protegidos contra UPDATE por govern_pokemon_generation()
(decisão congelada, COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01):
id, code, ordinal_number, created_at.

canonical_name e is_active permanecem corrigíveis administrativamente —
deliberadamente NÃO protegidos por este trigger.

Pré-requisitos:
- Query 6000 - Create Pokemon Generation Table.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_pokemon_generation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.code := UPPER(BTRIM(NEW.code));
    NEW.canonical_name := BTRIM(NEW.canonical_name);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_pokemon_generation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEMON_GENERATION_ID_IMMUTABLE';
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code THEN
        RAISE EXCEPTION 'POKEMON_GENERATION_CODE_IMMUTABLE';
    END IF;
    IF NEW.ordinal_number IS DISTINCT FROM OLD.ordinal_number THEN
        RAISE EXCEPTION 'POKEMON_GENERATION_ORDINAL_NUMBER_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEMON_GENERATION_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokemon_generation_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_pokemon_generation
BEFORE INSERT OR UPDATE
ON public.pokemon_generation
FOR EACH ROW
EXECUTE FUNCTION public.normalize_pokemon_generation();

CREATE TRIGGER trg_020_govern_pokemon_generation
BEFORE UPDATE
ON public.pokemon_generation
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokemon_generation();

CREATE TRIGGER trg_030_touch_pokemon_generation_updated_at
BEFORE UPDATE
ON public.pokemon_generation
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokemon_generation_updated_at();

COMMIT;
