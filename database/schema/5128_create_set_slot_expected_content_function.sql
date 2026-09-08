/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5128 - Create set_slot_expected_content()
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Define (ou substitui) o Expected Content de um Slot. UPSERT sobre a PK
slot_id, materializando o "0..1 por Slot" sem ramificação.

LOCK NÃO BLOQUEIA Expected Content (C-43, por omissão deliberada — a
lista de operações bloqueadas não o inclui). Um Slot locked continua
aceitando definir/limpar a intenção editorial; o que o Lock protege é
a OCUPAÇÃO, não a expectativa.

A validação "Variant pertence à Card" NÃO é feita aqui: é a FK
composta da Query 5113 que a prova, declarativamente. Esta RPC apenas
traduz a violação em mensagem de domínio.

SECURITY DEFINER é OBRIGATÓRIO, não conveniência: card e card_variant
estão sob RLS admin-only (policy catalog_admin_select). Uma função
SECURITY INVOKER não conseguiria sequer verificar a existência da
Card para um usuário comum — exatamente o bloqueio real encontrado na
Fatia 02E com 5070/5071. Precedente registrado, não redescoberto.

Expected Content NUNCA entra em completion (C-42/LDM-20). Nada aqui
toca qualquer função de completion.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_slot_expected_content (Query 5113).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§3 + §4 NON-ENUMERATION. A v1.0 fazia raw child lookup: navegava
Slot -> Page para obter o layout_id SEM filtro de ownership, e só
depois provava ownership no helper. O resolve passa a ser
owner-scoped, e o Slot é lockado e REVALIDADO depois do lock da
Collection/Layout, antes do upsert.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, na rodada
`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`. Validada por
`5818` v7.2 (196/196 runtime, FAIL 0) e por `5819` v3.0 (22/22 HEALTHY,
nenhum indice novo criado). Ledger e evidencia completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). A copia historica permanece em
`database/proposals/2026-09-06-binder-layout-foundation/`, junto com os
harnesses `5818`/`5819`, o roteiro `CONCURRENCY-PROOF-C04-R18.sql` e o
`README.md` da rodada — esses quatro NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
(`BEGIN;` .. `COMMIT;`) permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_slot_expected_content(
    p_slot_id         UUID,
    p_card_id         UUID,
    p_card_variant_id UUID DEFAULT NULL
)
RETURNS TABLE (
    slot_id         UUID,
    card_id         UUID,
    card_variant_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_layout_id UUID;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED (nenhum raw child lookup).
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
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout slot not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 3) SLOT LOCK.
    PERFORM 1
       FROM public.collection_layout_slot s
      WHERE s.id = p_slot_id
      FOR UPDATE;

    -- 4) REVALIDAÇÃO PÓS-LOCK: o Slot ainda existe e ainda pertence a
    -- este Layout e a este Owner?
    PERFORM 1
       FROM public.collection_layout_slot s
       JOIN public.collection_layout_page p ON p.id = s.page_id
       JOIN public.collection_layout l      ON l.id = p.layout_id
       JOIN public.collection c             ON c.id = l.collection_id
      WHERE s.id = p_slot_id
        AND p.layout_id = v_layout_id
        AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'p_card_id é obrigatório';
    END IF;

    BEGIN
        INSERT INTO public.collection_layout_slot_expected_content AS ec
            (slot_id, card_id, card_variant_id)
        VALUES
            (p_slot_id, p_card_id, p_card_variant_id)
        ON CONFLICT ON CONSTRAINT collection_layout_slot_expected_content_pkey
        DO UPDATE SET card_id         = EXCLUDED.card_id,
                      card_variant_id = EXCLUDED.card_variant_id;
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE EXCEPTION
                'Card/Card Variant inválida — quando informada, a Card Variant deve pertencer à Card indicada';
    END;

    RETURN QUERY
    SELECT e.slot_id, e.card_id, e.card_variant_id
      FROM public.collection_layout_slot_expected_content e
     WHERE e.slot_id = p_slot_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_slot_expected_content(uuid, uuid, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_slot_expected_content(uuid, uuid, uuid)
    TO authenticated;

COMMIT;
