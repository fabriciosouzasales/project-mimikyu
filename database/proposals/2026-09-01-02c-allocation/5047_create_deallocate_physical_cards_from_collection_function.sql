/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5047 - Create deallocate_physical_cards_from_collection Function (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-01
               → -REVISION-01 → -FINAL-01 → -STAGING-REVISION-01, item
               1 — não vazar existência de Collection alheia)

Descrição...:
Cria deallocate_physical_cards_from_collection(p_collection_id,
p_physical_card_ids) — única via de escrita de DELETE em
collection_allocation para authenticated, bulk-first, Owner-only,
espelho exato de allocate_physical_cards_to_collection() (Query 5046)
na estrutura de validação, inclusive na correção de não-enumeração
descrita no cabeçalho de 5046 (item 1 da rodada -STAGING-REVISION-01):
owner_user_id = auth.uid() já no WHERE da SELECT ... FOR UPDATE, uma
única mensagem genérica de erro tanto para Collection inexistente
quanto para Collection de outro Owner. Nome preservado desde a
proposta original — nenhuma alternativa melhor encontrada.

NUNCA toca collection.started_at, mesmo esvaziando a Collection por
completo (deallocate total não reseta started_at — confirmado
explicitamente em COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
REVISION-01, item 3, e reforçado pela própria trigger de 5044, que
rejeitaria uma tentativa de voltar started_at a NULL de qualquer
forma). Esta função não faz nenhum UPDATE em collection.

Regras de Negócio (idênticas a 5046 até a escrita final):
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_physical_card_ids não vazio; teto de 500 sobre o array recebido,
  antes da deduplicação; dedup via array_agg(DISTINCT ...);
- SELECT ... FOR UPDATE na linha de collection, com owner_user_id =
  auth.uid() já no próprio WHERE — mesmo lock de 5046, fecha a mesma
  race de lifecycle;
- rejeita com a MESMA mensagem genérica ('collection not found or not
  owned by caller') tanto Collection inexistente quanto Collection de
  outro Owner — nenhuma distinção observável entre os dois casos;
- rejeita se lifecycle_status <> 'ACTIVE' (C-37 — ARCHIVED não aceita
  mudança de composição, deallocate incluso), só checado depois de já
  ter confirmado ownership;
- fail-closed em não-alocada/alocada em outra Collection: valida que
  todos os physical_card_ids distintos possuem, hoje, uma
  collection_allocation cujo collection_id = p_collection_id — se
  algum não bate, zero remoções;
- único DELETE...WHERE...RETURNING como escrita, set-based, sem loop;
  nunca remove allocation de outra Collection, mesmo que pertença ao
  mesmo Owner;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE FUNCTION public.deallocate_physical_cards_from_collection(
    p_collection_id      UUID,
    p_physical_card_ids  UUID[]
)
RETURNS TABLE (
    physical_card_id  UUID,
    collection_id     UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_lifecycle_status TEXT;
    v_distinct_ids     UUID[];
    v_raw_count        INT;
    v_allocated_count  INT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_physical_card_ids IS NULL OR array_length(p_physical_card_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'p_physical_card_ids não pode ser vazio';
    END IF;

    v_raw_count := array_length(p_physical_card_ids, 1);

    IF v_raw_count > 500 THEN
        RAISE EXCEPTION 'lote excede o limite de 500 itens por chamada';
    END IF;

    SELECT array_agg(DISTINCT x) INTO v_distinct_ids
    FROM unnest(p_physical_card_ids) AS x;

    SELECT col.lifecycle_status
    INTO v_lifecycle_status
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before deallocating';
    END IF;

    SELECT count(*) INTO v_allocated_count
    FROM public.collection_allocation ca
    WHERE ca.physical_card_id = ANY(v_distinct_ids)
      AND ca.collection_id = p_collection_id;

    IF v_allocated_count <> array_length(v_distinct_ids, 1) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não estão alocadas a esta Collection';
    END IF;

    RETURN QUERY
    DELETE FROM public.collection_allocation
    WHERE collection_allocation.physical_card_id = ANY(v_distinct_ids)
      AND collection_allocation.collection_id = p_collection_id
    RETURNING
        collection_allocation.physical_card_id,
        collection_allocation.collection_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.deallocate_physical_cards_from_collection(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deallocate_physical_cards_from_collection(uuid, uuid[]) TO authenticated;
