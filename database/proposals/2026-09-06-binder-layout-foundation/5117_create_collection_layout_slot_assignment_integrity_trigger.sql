/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5117 - Create Slot Assignment Integrity Trigger
Versão......: 2.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
O invariante central de C-44, e o único que nenhuma FK do Postgres
consegue provar sozinha:

    allocation.collection_id
      =
    slot.page.layout.collection_id

Ou seja: só é possível posicionar no Layout de uma Collection uma
Physical Card que esteja alocada A ESSA MESMA Collection. A recíproca
não vale — uma Physical Card pode estar alocada sem ter Assignment
nenhuma (recém-importada, Bandeja, layout não organizado). Nada aqui
exige Assignment.

Por que trigger: a comparação cruza QUATRO tabelas
(assignment -> allocation) e (assignment -> slot -> page -> layout).
FK composta não alcança essa profundidade.

Escopo: BEFORE INSERT OR UPDATE. Cobre ADD, MOVE (mudança de slot_id
para Slot de outro Layout seria rejeitada) e REPLACE.

Este trigger é DE INTEGRIDADE, separado do trigger de LOCK (Query
5118), que é DE OPERAÇÃO. Mantê-los separados preserva mensagens de
erro específicas e permite auditar cada regra isoladamente.

Dependências:
- public.collection_layout_slot_assignment (Query 5115).
- public.collection_allocation (Query 5040).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§6 collection_allocation_id IMUTÁVEL.
A v1.0 revalidava a integridade Allocation x Layout em INSERT e
UPDATE, mas PERMITIA que `collection_allocation_id` fosse trocado por
UPDATE direto. Dois problemas reais:

(a) viola a semântica congelada de REPLACE = DELETE da Assignment
    antiga + INSERT da nova (o `id` da Assignment é a identidade da
    ocupação daquele Slot por aquela Physical Card);

(b) abre BYPASS DE LOCK: como o `slot_id` permanece o mesmo, o trigger
    de Lock (5118) — que dispara em DELETE — nunca é acionado, e a
    carta de um Slot LOCKED poderia ser substituída por outra.

Agora qualquer UPDATE que altere `collection_allocation_id` é
rejeitado, com ou sem Lock ativo, e a mensagem orienta ao REPLACE.
MOVE e SWAP continuam permitidos porque alteram `slot_id`, nunca
`collection_allocation_id`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_collection_layout_slot_assignment_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_allocation_collection_id UUID;
    v_layout_collection_id     UUID;
BEGIN
    -- §6 IMUTABILIDADE DE collection_allocation_id.
    -- Vale inclusive para Slot UNLOCKED: o caminho suportado é
    -- REPLACE (DELETE + INSERT), nunca UPDATE do vínculo.
    IF TG_OP = 'UPDATE'
       AND NEW.collection_allocation_id IS DISTINCT FROM OLD.collection_allocation_id THEN
        RAISE EXCEPTION
            'collection_allocation_id de uma Slot Assignment é IMUTÁVEL — use a operação REPLACE (assign_card_to_slot), que remove a Assignment antiga e cria uma nova; UPDATE direto contornaria o enforcement de Lock';
    END IF;

    SELECT ca.collection_id
      INTO v_allocation_collection_id
      FROM public.collection_allocation ca
     WHERE ca.id = NEW.collection_allocation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'collection_allocation_id % não existe', NEW.collection_allocation_id;
    END IF;

    SELECT l.collection_id
      INTO v_layout_collection_id
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
     WHERE s.id = NEW.slot_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'slot_id % não existe', NEW.slot_id;
    END IF;

    IF v_allocation_collection_id IS DISTINCT FROM v_layout_collection_id THEN
        RAISE EXCEPTION
            'Physical Card não está alocada à mesma Collection do Layout — Slot Assignment exige alocação prévia à Collection dona do Layout';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_collection_layout_slot_assignment_integrity()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_slot_assignment_integrity
    BEFORE INSERT OR UPDATE ON public.collection_layout_slot_assignment
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_slot_assignment_integrity();

COMMIT;
