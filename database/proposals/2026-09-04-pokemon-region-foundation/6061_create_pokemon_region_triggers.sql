/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6061 - Pokemon Region Triggers
Versão......: 1.0
Status......: PROPOSTO (staging — NÃO executado)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-REGION-FOUNDATION-
               PHYSICAL-STAGING-01)

Descrição...:
Normalização, governança de identidade e updated_at para pokemon_region
(Query 6060). Mesmo padrão de três triggers já estabelecido no
repositório para tabelas-raiz de catálogo (normalize_/govern_/
touch_..._updated_at, nomes de trigger numerados trg_010_/trg_020_/
trg_030_ — mesma convenção de pokemon_generation, Query 6001, e
pokedex, Query 6031).

Campos protegidos contra UPDATE por govern_pokemon_region() (decisão
congelada, POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01): id, code,
created_at. Diferente de pokemon_generation (que também protege
ordinal_number), pokemon_region não tem campo ordinal — não há
ranking sequencial de Região no domínio.

canonical_name e is_active permanecem corrigíveis administrativamente —
deliberadamente NÃO protegidos por este trigger.

Segurança: EXECUTE revogado de PUBLIC/anon/authenticated já nesta
Query, mesma disciplina de 6031/6041/6051 (correção retroativa aplicada
a 6001/6011/6021 via Query 6701 — aqui já nasce correto, sem precisar
de correção posterior).

Pré-requisitos:
- Query 6060 - Create Pokemon Region Table.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_pokemon_region()
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

CREATE OR REPLACE FUNCTION public.govern_pokemon_region()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEMON_REGION_ID_IMMUTABLE';
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code THEN
        RAISE EXCEPTION 'POKEMON_REGION_CODE_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEMON_REGION_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokemon_region_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_pokemon_region
BEFORE INSERT OR UPDATE
ON public.pokemon_region
FOR EACH ROW
EXECUTE FUNCTION public.normalize_pokemon_region();

CREATE TRIGGER trg_020_govern_pokemon_region
BEFORE UPDATE
ON public.pokemon_region
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokemon_region();

CREATE TRIGGER trg_030_touch_pokemon_region_updated_at
BEFORE UPDATE
ON public.pokemon_region
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokemon_region_updated_at();

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_region() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokemon_region() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokemon_region_updated_at() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ================================================================
-- PROPOSTO — staging, NÃO executado. Ver nota de status em 6060.
-- ================================================================
