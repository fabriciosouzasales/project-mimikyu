/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5066 - Create set_collection_card_set_reference Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Cria set_collection_card_set_reference(p_collection_id, p_card_set_id)
— única via de troca de card_set_id antes do lock. Decisão fechada em
COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-FINAL-01, item 7: "Troca
de card_set_id antes do lock: usar RPC própria. Não misturar com
update_collection_metadata()" — 5035 segue exclusiva para name/
description, sem nenhuma alteração nesta rodada.

SELECT ... FOR UPDATE na linha de collection, com owner_user_id =
auth.uid() já no próprio WHERE — mesmo padrão de não-enumeração já
usado em 5046/5047/5039: Collection inexistente e Collection de outro
Owner produzem a mesma mensagem genérica, mesma etapa, nenhuma
distinção observável. O lock serializa esta troca contra archive_
collection()/allocate_physical_cards_to_collection() concorrentes na
mesma Collection.

Early checks amigáveis, todas antes do UPDATE: mode deve ser
REFERENCE_BASED (não faz sentido chamar esta RPC numa Collection
OPEN_CURATION — não tem Reference nenhuma para trocar); lifecycle deve
ser ACTIVE (C-37); reference_locked_at deve ser NULL (LDM-07 — já
consolidada, imutável). A garantia estrutural de fundo para as duas
últimas é o trigger da Query 5055 (BEFORE UPDATE em collection_
card_set_reference), que dispara de qualquer forma no UPDATE abaixo —
esta RPC só antecipa a mensagem.

Game da nova card_set_id também é revalidado — não por esta RPC
diretamente (nenhuma checagem duplicada aqui), mas pelo mesmo trigger
da Query 5055, que dispara em UPDATE tanto quanto em INSERT (decisão
fechada em -MODELING-FINAL-01, item 7: "Game validation obrigatória em
INSERT E UPDATE").

updated_at do subtipo avançado explicitamente no UPDATE (não confia
apenas na trigger de set_updated_at() — mesmo padrão de outras RPCs do
domínio que fazem UPDATE direto sobre a linha que ela mesma edita).

EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Validado em execução real (COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01, 5808, Caso W).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.set_collection_card_set_reference(
    p_collection_id  UUID,
    p_card_set_id     UUID
)
RETURNS TABLE (
    collection_id  UUID,
    card_set_id     UUID,
    updated_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_mode                  TEXT;
    v_lifecycle_status        TEXT;
    v_reference_locked_at       TIMESTAMPTZ;
    v_reference_id                UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    SELECT col.mode, col.lifecycle_status, col.reference_locked_at
    INTO v_mode, v_lifecycle_status, v_reference_locked_at
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_mode <> 'REFERENCE_BASED' THEN
        RAISE EXCEPTION 'collection is not REFERENCE_BASED';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before changing Card Set Reference';
    END IF;

    IF v_reference_locked_at IS NOT NULL THEN
        RAISE EXCEPTION 'card_set_id is immutable after reference_locked_at is set';
    END IF;

    SELECT cr.id INTO v_reference_id
    FROM public.collection_reference cr
    WHERE cr.collection_id = p_collection_id;

    IF v_reference_id IS NULL THEN
        RAISE EXCEPTION 'collection has no Collection Reference';
    END IF;

    RETURN QUERY
    UPDATE public.collection_card_set_reference
    SET card_set_id = p_card_set_id,
        updated_at = NOW()
    WHERE collection_card_set_reference.collection_reference_id = v_reference_id
    RETURNING p_collection_id, collection_card_set_reference.card_set_id, collection_card_set_reference.updated_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_collection_card_set_reference(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_card_set_reference(uuid, uuid) TO authenticated;
