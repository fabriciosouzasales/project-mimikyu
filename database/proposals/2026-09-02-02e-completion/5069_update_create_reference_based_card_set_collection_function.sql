/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5069 - Update create_reference_based_card_set_collection Function (PROPOSTA)
Versão......: 1.1 (estende 5065 v1.0)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-01)

Descrição...:
Estende create_reference_based_card_set_collection() (Query 5065,
CREATE OR REPLACE, mesma função já existente — assinatura de parâmetro
inalterada: p_game_id, p_name, p_description,
p_default_storage_container_id, p_card_set_id) para gravar
explicitamente completion_policy = 'STANDARD_SET' no INSERT de
public.collection — decisão fechada em COLLECTIONS-PHYSICAL-
INCREMENT-02E-MODELING-REVISION-01, item 6, mesma justificativa de
5068: nesta etapa física, REFERENCE_BASED/CARD_SET só admite
STANDARD_SET (MASTER_SET: CONCEPTUALLY READY, PHYSICALLY DEFERRED FROM
02E FOR SCOPE CONTROL) — nenhum p_completion_policy exposto ao
chamador.

RETURNS TABLE preservado INTEGRALMENTE — completion_policy NÃO
adicionado ao contrato de retorno, mesma decisão e mesma justificativa
de 5068 (valor determinístico e conhecido de antemão pelo caminho de
criação usado).

Todo o restante do corpo é idêntico a 5065 v1.0 (mesmas validações de
Game/Inventory/Storage/Card Set, mesma criação atômica em 3 INSERTs
dentro da mesma transação — os triggers deferred de 5057/5058/5059
continuam avaliando a consistência mode <-> Reference e supertipo <->
subtipo só no COMMIT desta função) — único diff real é a coluna
adicional no primeiro INSERT (public.collection).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.create_reference_based_card_set_collection(
    p_game_id                      UUID,
    p_name                         TEXT,
    p_description                  TEXT,
    p_default_storage_container_id UUID,
    p_card_set_id                  UUID
)
RETURNS TABLE (
    id                            UUID,
    name                          TEXT,
    mode                          TEXT,
    lifecycle_status              TEXT,
    visibility                    TEXT,
    default_storage_container_id  UUID,
    card_set_id                   UUID,
    created_at                    TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id      UUID;
    v_collection_id      UUID;
    v_reference_id        UUID;
    v_card_set_game        UUID;
    v_created_at            TIMESTAMPTZ;
    v_lifecycle_status       TEXT;
    v_visibility               TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'p_name não pode ser vazio';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.game g WHERE g.id = p_game_id) THEN
        RAISE EXCEPTION 'game not found';
    END IF;

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.storage_container sc
        WHERE sc.id = p_default_storage_container_id
          AND sc.inventory_id = v_inventory_id
    ) THEN
        RAISE EXCEPTION 'default_storage_container_id does not belong to caller inventory';
    END IF;

    SELECT ex.game_id INTO v_card_set_game
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE cs.id = p_card_set_id;

    IF v_card_set_game IS NULL THEN
        RAISE EXCEPTION 'card_set not found';
    END IF;

    IF v_card_set_game IS DISTINCT FROM p_game_id THEN
        RAISE EXCEPTION 'card_set_id must belong to the same Game as the Collection';
    END IF;

    INSERT INTO public.collection (
        owner_user_id, game_id, name, description, default_storage_container_id, mode,
        completion_policy
    )
    VALUES (
        auth.uid(), p_game_id, btrim(p_name), p_description, p_default_storage_container_id, 'REFERENCE_BASED',
        'STANDARD_SET'
    )
    RETURNING collection.id, collection.created_at, collection.lifecycle_status, collection.visibility
    INTO v_collection_id, v_created_at, v_lifecycle_status, v_visibility;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_collection_id, 'CARD_SET')
    RETURNING collection_reference.id INTO v_reference_id;

    INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
    VALUES (v_reference_id, p_card_set_id);

    RETURN QUERY
    SELECT v_collection_id, btrim(p_name), 'REFERENCE_BASED'::TEXT, v_lifecycle_status, v_visibility,
           p_default_storage_container_id, p_card_set_id, v_created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_reference_based_card_set_collection(uuid, text, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_reference_based_card_set_collection(uuid, text, text, uuid, uuid) TO authenticated;
