/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5065 - Create create_reference_based_card_set_collection Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Cria create_reference_based_card_set_collection(p_game_id, p_name,
p_description, p_default_storage_container_id, p_card_set_id) — única
via de criação de uma Collection REFERENCE_BASED/CARD_SET para
authenticated. Decisão fechada em COLLECTIONS-PHYSICAL-INCREMENT-02D-
MODELING-FINAL-01, item 7: "V1 terá operação dedicada... Não ampliar
create_collection() com parâmetros opcionais" — create_collection()
(Query 5034) permanece exclusiva para OPEN_CURATION, sem nenhuma
alteração nesta rodada.

Espelha create_collection() (5034) em toda validação já existente
(nome, Game, Inventory do chamador, Default Storage do mesmo
Inventory) e adiciona, sobre isso, a criação atômica de Collection
Reference + Card Set Reference na MESMA transação — mecanismo descrito
em detalhe no cabeçalho da Query 5057/5059: os dois constraint
triggers DEFERRABLE INITIALLY DEFERRED só avaliam a consistência
mode <-> Reference e supertipo <-> subtipo no COMMIT desta função,
quando as três linhas (collection, collection_reference,
collection_card_set_reference) já existem. Se qualquer INSERT
intermediário falhar (ex.: card_set_id de outro Game, capturado pela
Query 5055), a transação inteira sofre ROLLBACK — nunca existe
COMMIT parcial visível a outra sessão.

Validação early de Game (antes do primeiro INSERT) é conveniência de
UX — a garantia estrutural de fundo é o trigger da Query 5055,
disparado pelo INSERT em collection_card_set_reference, que
re-valida a mesma regra de forma independente.

owner_user_id NUNCA aceito como parâmetro — sempre auth.uid(), mesmo
padrão de 5034. mode NÃO é parâmetro — sempre 'REFERENCE_BASED', único
propósito desta RPC (para OPEN_CURATION, usar 5034).

Retorno explícito inclui card_set_id (a Reference recém-criada) além
dos campos já retornados por create_collection() — omite reference_
locked_at (sempre NULL neste momento, redundante informar) e os ids
internos de collection_reference/collection_card_set_reference (o
chamador não precisa deles; card_set_id já identifica a Reference de
forma suficiente para o cliente).

EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Validado em execução real (COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01, 5808, Casos A/B/F/J).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.create_reference_based_card_set_collection(
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
        owner_user_id, game_id, name, description, default_storage_container_id, mode
    )
    VALUES (
        auth.uid(), p_game_id, btrim(p_name), p_description, p_default_storage_container_id, 'REFERENCE_BASED'
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
