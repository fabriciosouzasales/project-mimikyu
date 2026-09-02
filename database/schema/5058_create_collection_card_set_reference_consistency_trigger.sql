/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5058 - Create Collection Card Set Reference Consistency Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
BLOCKER identificado e fechado em COLLECTIONS-PHYSICAL-INCREMENT-02D-
MODELING-FINAL-01, item 1: "A constraint trigger somente em
collection_reference é insuficiente. DELETE/UPDATE direto em
collection_card_set_reference não dispara trigger do parent."

Este é o segundo lado do enforcement diferido de supertipo/subtipo —
espelha exatamente a Query 5057, mas reage a eventos na tabela do
subtipo, não do supertipo. Reaproveita a mesma função auxiliar
(check_collection_reference_subtype_consistency(), criada em 5057),
para nunca ter dois lugares com a definição de "consistente".

Duas checagens, nesta ordem:

1. Direção subtipo -> supertipo (não coberta por 5057 de forma
   alguma): se esta linha existe (INSERT ou UPDATE), seu
   collection_reference_id deve apontar para um Collection Reference
   de reference_kind = 'CARD_SET'. Hoje isso é vacuamente verdade
   (chk_collection_reference_kind só permite 'CARD_SET' — Query 5049),
   mas a checagem já fica pronta para quando 'POKEDEX' existir, sem
   precisar redesenhar nada. Cobre explicitamente o Caso D do plano de
   validação (Query 5808): "subtype apontando para kind incompatível
   futuro -> FAIL".

2. Direção supertipo -> subtipo (mesma checagem de 5057, chamada aqui
   pelo lado oposto): usa check_collection_reference_subtype_
   consistency() para reconfirmar que o Collection Reference apontado
   ainda tem exatamente 1 subtipo — cobre o Caso C ("subtype apagado
   isoladamente -> FAIL") e qualquer UPDATE que descasasse a relação.

DEFERRABLE INITIALLY DEFERRED, mesmo raciocínio de 5057: um DELETE
isolado desta linha só falha no COMMIT, dando tempo de, na mesma
transação, inserir uma linha de substituição se esse fosse o objetivo
(não é um fluxo desta rodada, mas o mecanismo não impede).

EXECUTE revogado de PUBLIC/anon/authenticated.

Validado em execução real (COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01, 5808, Casos C/D).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.validate_collection_card_set_reference_consistency()
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

        IF v_kind IS DISTINCT FROM 'CARD_SET' THEN
            RAISE EXCEPTION 'Collection Card Set Reference must point to a Collection Reference of kind CARD_SET';
        END IF;
    END IF;

    PERFORM public.check_collection_reference_subtype_consistency(v_reference_id);

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_collection_card_set_reference_consistency
    AFTER INSERT OR UPDATE OR DELETE ON public.collection_card_set_reference
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_card_set_reference_consistency();

REVOKE EXECUTE ON FUNCTION public.validate_collection_card_set_reference_consistency() FROM PUBLIC, anon, authenticated;
