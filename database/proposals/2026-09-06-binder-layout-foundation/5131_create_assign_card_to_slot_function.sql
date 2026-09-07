/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5131 - Create assign_card_to_slot()
Versão......: 2.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cobre ADD e REPLACE com semântica EXPLÍCITA, em uma assinatura.

- Slot VAZIO   -> ADD:     INSERT de nova Assignment.
- Slot OCUPADO -> REPLACE: DELETE da Assignment atual + INSERT da
                           nova, MESMO slot_id, MESMA transação
                           (LDM-35, literal).

Em REPLACE, "a carta anterior não é destruída, sai do slot" (regra de
produto observada nos spikes): a Physical Card e sua Collection
Allocation permanecem intactas — apenas a relação de posicionamento
termina. Nada além da linha de Assignment é tocado.

O retorno inclui `operation` ('ADD'|'REPLACE') e
`replaced_allocation_id`, para que o produto possa oferecer o
feedback correto (ex.: informar qual carta saiu do Slot) sem precisar
inferir do estado anterior.

Ordem determinística de lock (anti-deadlock): Layout (via assert) ->
Slot -> Assignment. Todas as RPCs de Assignment (5131/5132/5133)
seguem a MESMA ordem; quando há mais de um Slot/Assignment envolvido,
o lock é tomado ORDER BY id. Concorrência real: duas abas do mesmo
usuário é cenário esperado, "um Owner" não significa "sem corrida".

Invariante "mesma Collection" é provado pelo trigger 5117 — esta RPC
o antecipa apenas para produzir mensagem legível, nunca como única
barreira.

Lock do Slot destino é verificado pelo trigger 5118; a RPC antecipa
para erro amigável.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_slot_assignment (Query 5115).
- public.collection_allocation (Query 5040).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§4C NON-ENUMERATION EM ASSIGN + §3 POST-LOCK REVALIDATION.

(a) A v1.0 carregava uma `collection_allocation` ARBITRÁRIA por UUID
    sob SECURITY DEFINER (`WHERE ca.id = p_collection_allocation_id`,
    sem escopo) e, se a linha existisse mas fosse de outra Collection,
    respondia com uma mensagem DIFERENTE da de inexistente. Isso
    revelava a existência de Allocations alheias. Agora a Allocation é
    buscada JÁ ESCOPADA ao `collection_id` do Layout resolvido, e os
    três casos — inexistente, de outra Collection, de outro Owner —
    produzem exatamente a mesma mensagem.

(b) O resolve do Slot passa a ser owner-scoped (era raw child lookup).

(c) `locked` e a Assignment existente são lidos DEPOIS do lock.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.assign_card_to_slot(
    p_slot_id                  UUID,
    p_collection_allocation_id UUID
)
RETURNS TABLE (
    assignment_id            UUID,
    slot_id                  UUID,
    collection_allocation_id UUID,
    operation                TEXT,
    replaced_allocation_id   UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_layout_id             UUID;
    v_layout_collection_id  UUID;
    v_slot_locked           BOOLEAN;
    v_existing_assignment   UUID;
    v_replaced_allocation   UUID;
    v_operation             TEXT;
    v_new_assignment_id     UUID;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED do Slot.
    SELECT p.layout_id
      INTO v_layout_id
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE s.id = p_slot_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    -- 2) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE.
    BEGIN
        v_layout_collection_id := public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout slot not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 3) SLOT LOCK (ordem: Collection -> Layout -> Slot -> Allocation
    -- -> Assignment).
    PERFORM 1
       FROM public.collection_layout_slot s
      WHERE s.id = p_slot_id
      FOR UPDATE;

    -- 4) REVALIDAÇÃO PÓS-LOCK do Slot + leitura pós-lock de `locked`.
    SELECT s.locked
      INTO v_slot_locked
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
     WHERE s.id = p_slot_id
       AND p.layout_id = v_layout_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    IF v_slot_locked THEN
        RAISE EXCEPTION
            'Slot bloqueado (locked) — Add/Replace não permitido enquanto o Lock estiver ativo';
    END IF;

    -- 5) ALLOCATION JÁ ESCOPADA à Collection do Layout. Nunca se
    -- carrega uma Allocation arbitrária para depois compará-la:
    -- inexistente, de outra Collection e de outro Owner colapsam na
    -- MESMA mensagem.
    PERFORM 1
       FROM public.collection_allocation ca
      WHERE ca.id = p_collection_allocation_id
        AND ca.collection_id = v_layout_collection_id
      FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection allocation not found or not owned by caller';
    END IF;

    -- 6) REVALIDAÇÃO PÓS-LOCK da Allocation.
    PERFORM 1
       FROM public.collection_allocation ca
      WHERE ca.id = p_collection_allocation_id
        AND ca.collection_id = v_layout_collection_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection allocation not found or not owned by caller';
    END IF;

    -- 7) Assignment já existente NESTE Slot (REPLACE) — lock e leitura
    -- pós-lock.
    SELECT a.id, a.collection_allocation_id
      INTO v_existing_assignment, v_replaced_allocation
      FROM public.collection_layout_slot_assignment a
     WHERE a.slot_id = p_slot_id
     FOR UPDATE;

    IF FOUND THEN
        IF v_replaced_allocation = p_collection_allocation_id THEN
            RAISE EXCEPTION
                'no-op: esta Physical Card já ocupa este Slot';
        END IF;

        -- REPLACE = DELETE da Assignment antiga + INSERT da nova.
        -- Jamais UPDATE de collection_allocation_id (ver 5117).
        DELETE FROM public.collection_layout_slot_assignment
         WHERE id = v_existing_assignment;

        v_operation := 'REPLACE';
    ELSE
        v_replaced_allocation := NULL;
        v_operation           := 'ADD';
    END IF;

    BEGIN
        INSERT INTO public.collection_layout_slot_assignment AS a
            (slot_id, collection_allocation_id)
        VALUES
            (p_slot_id, p_collection_allocation_id)
        RETURNING a.id INTO v_new_assignment_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION
                'esta Physical Card já possui Slot Assignment neste Layout — mova-a em vez de atribuí-la novamente';
    END;

    RETURN QUERY
    SELECT a.id, a.slot_id, a.collection_allocation_id,
           v_operation, v_replaced_allocation
      FROM public.collection_layout_slot_assignment a
     WHERE a.id = v_new_assignment_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.assign_card_to_slot(uuid, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_card_to_slot(uuid, uuid)
    TO authenticated;

COMMIT;
