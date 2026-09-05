/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5096 - Create Collection Pokedex Scope Presence Trigger, lado Reference
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Espelha o papel da Query 5076 (Collection Master Set Scope Presence
Trigger, lado Collection) — CONSTRAINT TRIGGER DEFERRABLE INITIALLY
DEFERRED, AFTER INSERT OR UPDATE OF scope_kind ON
collection_pokedex_reference, chamando o helper da Query 5094.

Cobre a transição de scope_kind (FULL_REFERENCE <-> GENERATION_FILTERED)
e a criação inicial da própria Reference: se scope_kind nasce
GENERATION_FILTERED sem nenhuma linha de Generation ser inserida na
mesma transação, esta trigger falha no COMMIT — mesmo raciocínio de
5076 para MASTER_SET.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.enforce_collection_pokedex_scope_presence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM public.check_collection_pokedex_scope_presence(NEW.collection_reference_id);

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_collection_pokedex_scope_presence
    AFTER INSERT OR UPDATE OF scope_kind ON public.collection_pokedex_reference
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_pokedex_scope_presence();

REVOKE EXECUTE ON FUNCTION public.enforce_collection_pokedex_scope_presence()
    FROM PUBLIC, anon, authenticated;

COMMIT;
