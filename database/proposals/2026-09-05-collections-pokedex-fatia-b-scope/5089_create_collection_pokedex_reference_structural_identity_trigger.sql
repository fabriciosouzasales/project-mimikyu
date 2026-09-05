/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5089 - Create Collection Pokedex Reference Structural Identity Trigger
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Trigger BEFORE UPDATE bloqueando alteração de collection_reference_id
(a PK) — mesmo padrão de 5054 (Collection Card Set Reference Structural
Identity Trigger): fecha explicitamente uma lacuna que o Postgres não
recusa por si só (PK não é imutável por definição, só por UNIQUE+NOT
NULL). pokedex_id e scope_kind NÃO são protegidos por esta trigger —
suas regras de mutabilidade (imutável após lock / mutável sempre,
respectivamente) são responsabilidade da Query 5090.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.validate_collection_pokedex_reference_structural_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.collection_reference_id IS DISTINCT FROM OLD.collection_reference_id THEN
        RAISE EXCEPTION 'collection_reference_id é imutável (identidade do subtipo)';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_pokedex_reference_structural_identity
    BEFORE UPDATE ON public.collection_pokedex_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_pokedex_reference_structural_identity();

REVOKE EXECUTE ON FUNCTION public.validate_collection_pokedex_reference_structural_identity()
    FROM PUBLIC, anon, authenticated;

COMMIT;
