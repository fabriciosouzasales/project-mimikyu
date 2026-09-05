/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5093 - Create Collection Pokedex Reference Consistency Trigger
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01; aplicado em
               2026-09-05 via COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Segundo lado do enforcement diferido de supertipo/subtipo para o
subtipo POKEDEX — espelha exatamente a Query 5058 (Collection Card Set
Reference Consistency Trigger), mas reage a eventos em
collection_pokedex_reference. Reaproveita a mesma função auxiliar
check_collection_reference_subtype_consistency() (5057, estendida pela
Query 5092 desta pasta) — nunca duas definições de "consistente".

Duas checagens, mesma ordem de 5058:
1. Direção subtipo -> supertipo: se esta linha existe, seu
   collection_reference_id deve apontar para um Collection Reference
   de reference_kind = 'POKEDEX'.
2. Direção supertipo -> subtipo: reconfirma que o Collection Reference
   apontado ainda tem exatamente 1 subtipo POKEDEX.

DEFERRABLE INITIALLY DEFERRED, mesmo raciocínio de 5057/5058: permite a
criação atômica de collection -> collection_reference ->
collection_pokedex_reference (e, quando aplicável,
collection_pokedex_scope_generation) na mesma transação, sem falhar
num estado intermediário incompleto.

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou a CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED e a função
presentes, EXECUTE revogado de PUBLIC/anon/authenticated. Validado
funcionalmente por duas Collections Pokédex reais criadas de ponta a
ponta em BEGIN/ROLLBACK, ambas as direções da checagem confirmadas.
Zero resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.validate_collection_pokedex_reference_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_reference_id UUID := COALESCE(NEW.collection_reference_id, OLD.collection_reference_id);
    v_kind         TEXT;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT cr.reference_kind INTO v_kind
        FROM public.collection_reference cr
        WHERE cr.id = NEW.collection_reference_id;

        IF v_kind IS DISTINCT FROM 'POKEDEX' THEN
            RAISE EXCEPTION 'Collection Pokedex Reference must point to a Collection Reference of kind POKEDEX';
        END IF;
    END IF;

    PERFORM public.check_collection_reference_subtype_consistency(v_reference_id);

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_collection_pokedex_reference_consistency
    AFTER INSERT OR UPDATE OR DELETE ON public.collection_pokedex_reference
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_pokedex_reference_consistency();

REVOKE EXECUTE ON FUNCTION public.validate_collection_pokedex_reference_consistency()
    FROM PUBLIC, anon, authenticated;

COMMIT;
