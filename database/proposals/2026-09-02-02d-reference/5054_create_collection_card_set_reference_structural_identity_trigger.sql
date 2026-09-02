/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5054 - Create Collection Card Set Reference Structural Identity Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Garante estruturalmente que collection_reference_id é imutável —
decisão fechada em COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-
FINAL-01, item 3: "Não permitir reparenting do subtype."

collection_reference_id já é a PRIMARY KEY desta tabela — na prática,
um UPDATE tentando alterar uma PK é incomum, mas o Postgres não proíbe
a operação por si só (PK garante unicidade/NOT NULL, não imutabilidade
de valor). Este trigger fecha essa lacuna explicitamente, por
instrução direta, em vez de depender apenas da semântica implícita da
PK.

O único campo estrutural editável deste subtipo é card_set_id, e
somente sob as condições da Query 5055 (lifecycle ACTIVE + antes do
lock).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE FUNCTION public.validate_collection_card_set_reference_structural_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.collection_reference_id IS DISTINCT FROM OLD.collection_reference_id THEN
        RAISE EXCEPTION 'collection_reference_id é imutável';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_card_set_reference_validate_structural_identity
    BEFORE UPDATE ON public.collection_card_set_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_card_set_reference_structural_identity();

REVOKE EXECUTE ON FUNCTION public.validate_collection_card_set_reference_structural_identity() FROM PUBLIC, anon, authenticated;
