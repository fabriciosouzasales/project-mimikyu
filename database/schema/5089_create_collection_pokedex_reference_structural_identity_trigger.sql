/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5089 - Create Collection Pokedex Reference Structural Identity Trigger
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01; aplicado em
               2026-09-05 via COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Trigger BEFORE UPDATE bloqueando alteração de collection_reference_id
(a PK) — mesmo padrão de 5054 (Collection Card Set Reference Structural
Identity Trigger): fecha explicitamente uma lacuna que o Postgres não
recusa por si só (PK não é imutável por definição, só por UNIQUE+NOT
NULL). pokedex_id e scope_kind NÃO são protegidos por esta trigger —
suas regras de mutabilidade (imutável após lock / mutável sempre,
respectivamente) são responsabilidade da Query 5090.

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou a trigger e a função presentes, com EXECUTE revogado de
PUBLIC/anon/authenticated. Zero resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
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
