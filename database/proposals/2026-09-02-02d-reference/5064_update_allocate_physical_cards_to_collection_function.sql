/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5064 - Update allocate_physical_cards_to_collection Function (PROPOSTA)
Versão......: 1.2 (CREATE OR REPLACE sobre a função já CANÔNICA em
               database/schema/5046_create_allocate_physical_cards_
               to_collection_function.sql, hoje v1.1 — 5046 permanece
               intocada; esta Query é uma correção posterior, mesmo
               padrão de 5044/5048)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Extensão de regra sobre allocate_physical_cards_to_collection() (Query
5046) — mesma instrução de -MODELING-FINAL-01, item 6, já citada no
cabeçalho de 5063.

Adiciona uma pré-validação amigável de elegibilidade de Reference,
simétrica à checagem estrutural da Query 5063: quando a Collection é
REFERENCE_BASED com Card Set Reference, todo physical_card_id do lote
deve ter Card pertencente ao card_set_id referenciado. Fail-closed
preservado — mesmo raciocínio de "uma ou mais... rejeitado" já usado
para a checagem de Owner/Game existente, sem introduzir um segundo
estilo de mensagem/erro.

Resolvida com uma única consulta adicional, reaproveitando
v_collection_game/v_lifecycle_status já obtidos pelo SELECT ... FOR
UPDATE original (nenhuma segunda leitura de collection): busca o
Collection Reference/Card Set Reference da Collection (0 ou 1 linha,
LEFT JOIN), e só aplica a checagem quando existir. Nenhuma mudança na
assinatura, no contrato de retorno, no teto de 500, na deduplicação,
no fail-closed de "já alocada", ou no lock de concorrência já
existentes — extensão pura, mesmo padrão do domínio inteiro.

Segunda camada de defesa: a checagem estrutural equivalente já existe
em validate_collection_allocation_integrity() (Query 5063, trigger
independente de RPC) — esta é só a mensagem amigável antecipada, não a
garantia de fundo.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.allocate_physical_cards_to_collection(
    p_collection_id      UUID,
    p_physical_card_ids  UUID[]
)
RETURNS TABLE (
    physical_card_id  UUID,
    collection_id     UUID,
    created_at         TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id       UUID;
    v_collection_game    UUID;
    v_lifecycle_status   TEXT;
    v_collection_mode    TEXT;
    v_reference_kind     TEXT;
    v_reference_card_set UUID;
    v_distinct_ids       UUID[];
    v_raw_count          INT;
    v_owned_count        INT;
    v_already_count      INT;
    v_eligible_count     INT;
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

    SELECT col.game_id, col.lifecycle_status, col.mode
    INTO v_collection_game, v_lifecycle_status, v_collection_mode
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before allocating';
    END IF;

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    SELECT count(*) INTO v_owned_count
    FROM public.physical_card pc
    JOIN public.card_variant cv ON cv.id = pc.card_variant_id
    JOIN public.card ca ON ca.id = cv.card_id
    JOIN public.card_set cs ON cs.id = ca.card_set_id
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE pc.id = ANY(v_distinct_ids)
      AND pc.inventory_id = v_inventory_id
      AND ex.game_id = v_collection_game;

    IF v_owned_count <> array_length(v_distinct_ids, 1) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não pertencem ao inventory do chamador ou ao Game da Collection';
    END IF;

    -- Elegibilidade de Reference (LDM-17): só se aplica quando a
    -- Collection é REFERENCE_BASED e tem Card Set Reference — 0 linhas
    -- para OPEN_CURATION, por causa do LEFT JOIN.
    SELECT cr.reference_kind, ccsr.card_set_id
    INTO v_reference_kind, v_reference_card_set
    FROM public.collection_reference cr
    LEFT JOIN public.collection_card_set_reference ccsr
        ON ccsr.collection_reference_id = cr.id
    WHERE cr.collection_id = p_collection_id;

    IF v_collection_mode = 'REFERENCE_BASED' AND v_reference_kind = 'CARD_SET' THEN
        SELECT count(*) INTO v_eligible_count
        FROM public.physical_card pc
        JOIN public.card_variant cv ON cv.id = pc.card_variant_id
        JOIN public.card ca ON ca.id = cv.card_id
        WHERE pc.id = ANY(v_distinct_ids)
          AND ca.card_set_id = v_reference_card_set;

        IF v_eligible_count <> array_length(v_distinct_ids, 1) THEN
            RAISE EXCEPTION 'uma ou mais physical_card_ids não pertencem ao Card Set referenciado pela Collection';
        END IF;
    END IF;

    SELECT count(*) INTO v_already_count
    FROM public.collection_allocation ca
    WHERE ca.physical_card_id = ANY(v_distinct_ids);

    IF v_already_count > 0 THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids já estão alocadas a uma Collection';
    END IF;

    RETURN QUERY
    INSERT INTO public.collection_allocation (physical_card_id, collection_id)
    SELECT x, p_collection_id
    FROM unnest(v_distinct_ids) AS x
    RETURNING
        collection_allocation.physical_card_id,
        collection_allocation.collection_id,
        collection_allocation.created_at;
END;
$$;
