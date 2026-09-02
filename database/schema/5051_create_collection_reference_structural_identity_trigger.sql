/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5051 - Create Collection Reference Structural Identity Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Garante estruturalmente que collection_id e reference_kind são
imutáveis após a criação de um Collection Reference — decisão fechada
em COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-FINAL-01, item 2:
"Reference nunca muda de Collection. CARD_SET nunca vira outro kind."

Trigger BEFORE UPDATE simples (não diferida) — checagem imediata de
OLD vs NEW, sem dependência de estado de outras tabelas ainda não
escrito na mesma transação (ao contrário dos triggers das Queries
5057/5059, que precisam esperar o COMMIT). Mesmo padrão de
validate_collection_structural_identity() (Query 5032) e
validate_collection_default_storage_owner() (Query 5033).

Reparenting (mudar collection_id) nunca é uma operação de domínio
válida — se o Owner quiser uma Reference diferente numa outra
Collection, cria uma nova Collection REFERENCE_BASED (Query 5065);
não existe "mover" uma Reference entre Collections.

Trocar reference_kind (ex.: CARD_SET -> POKEDEX) também nunca é válido
— são objetivos de coleção conceitualmente distintos (LDM-06), não uma
edição da mesma Reference.

card_set_id (no subtipo) é o único campo estrutural editável desta
hierarquia, e só sob as condições da Query 5055.

EXECUTE revogado de PUBLIC/anon/authenticated — mesma correção de
segurança já aplicada a todo trigger function do domínio (5032/5033/
5042/5045).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.validate_collection_reference_structural_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.collection_id IS DISTINCT FROM OLD.collection_id THEN
        RAISE EXCEPTION 'collection_id é imutável';
    END IF;

    IF NEW.reference_kind IS DISTINCT FROM OLD.reference_kind THEN
        RAISE EXCEPTION 'reference_kind é imutável';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_reference_validate_structural_identity
    BEFORE UPDATE ON public.collection_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_reference_structural_identity();

REVOKE EXECUTE ON FUNCTION public.validate_collection_reference_structural_identity() FROM PUBLIC, anon, authenticated;
