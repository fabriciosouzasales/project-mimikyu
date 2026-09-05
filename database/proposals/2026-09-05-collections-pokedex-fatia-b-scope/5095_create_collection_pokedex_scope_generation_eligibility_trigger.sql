/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5095 - Create Collection Pokedex Scope Generation Eligibility Trigger
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Espelha o papel da Query 5073 (Collection Master Set Scope Eligibility
Trigger) — BEFORE INSERT, imediata, fail-closed: só aceita inserir uma
linha em collection_pokedex_scope_generation quando a
collection_pokedex_reference correspondente já está com
scope_kind = 'GENERATION_FILTERED' no momento do INSERT, e a Collection
dona está ACTIVE (LDM-185 — Scope imutável quando ARCHIVED).

Existir esta trigger é o que permite que a Query 5097 (presence,
diferida) só precise reagir a DELETE — mesmo raciocínio já usado para
Master Set Scope (5073 cobre INSERT imediato; 5077 só cobre DELETE
diferido): por construção, nunca é possível inserir uma linha de
Generation "adiantada", antes do scope_kind já estar
GENERATION_FILTERED — logo o lado de INSERT nunca corre risco de violar
a invariante de presença.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.validate_collection_pokedex_scope_generation_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_scope_kind       TEXT;
    v_collection_id    UUID;
    v_lifecycle_status TEXT;
BEGIN
    SELECT cpr.scope_kind, cr.collection_id
    INTO v_scope_kind, v_collection_id
    FROM public.collection_pokedex_reference cpr
    JOIN public.collection_reference cr ON cr.id = cpr.collection_reference_id
    WHERE cpr.collection_reference_id = NEW.collection_reference_id;

    IF v_scope_kind IS NULL THEN
        RAISE EXCEPTION 'collection_reference_id não corresponde a nenhuma Collection Pokedex Reference existente';
    END IF;

    IF v_scope_kind <> 'GENERATION_FILTERED' THEN
        RAISE EXCEPTION 'só é possível adicionar uma Generation ao filtro quando scope_kind já é GENERATION_FILTERED — troque o scope_kind primeiro (set_collection_pokedex_scope())';
    END IF;

    SELECT col.lifecycle_status INTO v_lifecycle_status
    FROM public.collection col
    WHERE col.id = v_collection_id;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before changing the Pokedex Scope Generation filter';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_pokedex_scope_generation_eligibility
    BEFORE INSERT ON public.collection_pokedex_scope_generation
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_pokedex_scope_generation_eligibility();

REVOKE EXECUTE ON FUNCTION public.validate_collection_pokedex_scope_generation_eligibility()
    FROM PUBLIC, anon, authenticated;

COMMIT;
