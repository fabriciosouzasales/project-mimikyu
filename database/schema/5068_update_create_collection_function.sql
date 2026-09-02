/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5068 - Update create_collection Function
Versão......: 1.2 (estende 5034 v1.1)
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01)

Descrição...:
Estende create_collection() (Query 5034, CREATE OR REPLACE, mesma
função já existente — nenhuma assinatura de parâmetro alterada:
p_game_id, p_name, p_description, p_default_storage_container_id
permanecem exatamente os mesmos) para gravar explicitamente
completion_policy = 'NONE' no INSERT — decisão fechada em
COLLECTIONS-PHYSICAL-INCREMENT-02E-MODELING-REVISION-01, item 6: "NÃO
adicionar p_completion_policy agora... Não expor escolha ao usuário
quando existe apenas um valor válido por operação nesta etapa."

RETURNS TABLE preservado INTEGRALMENTE — completion_policy NÃO é
adicionado ao contrato de retorno, mesma justificativa já registrada no
cabeçalho original de 5034: "evita vazar automaticamente colunas
futuras (ex.: completion_policy, quando existir) no contrato público
desta RPC." A coluna já existia como conceito quando aquele texto foi
escrito (LDM-08) — este incremento apenas materializa fisicamente o
que já estava previsto ali. Se o cliente precisar exibir a
completion_policy de uma Collection recém-criada, o valor é sempre
determinístico e conhecido de antemão pelo próprio caminho de criação
usado (create_collection() = sempre 'NONE'; create_reference_based_
card_set_collection() = sempre 'STANDARD_SET') — nenhuma necessidade
de round-trip adicional.

Todo o restante do corpo é idêntico a 5034 v1.1 (mesmas validações,
mesma resolução de Inventory, mesmo tratamento de erro) — único diff
real é a coluna adicional no INSERT INTO / VALUES.

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01,
Fase 1): aplicada via apply_migration; postcheck físico da Fase 2
confirmou assinatura preservada. Validado funcionalmente em 5810
(Caso E — create_collection() grava completion_policy=NONE, PASS).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.create_collection(
    p_game_id UUID,
    p_name TEXT,
    p_description TEXT,
    p_default_storage_container_id UUID
)
RETURNS TABLE (
    id                            UUID,
    name                          TEXT,
    mode                          TEXT,
    lifecycle_status              TEXT,
    visibility                    TEXT,
    default_storage_container_id  UUID,
    created_at                    TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id UUID;
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

    RETURN QUERY
    INSERT INTO public.collection (
        owner_user_id, game_id, name, description, default_storage_container_id,
        completion_policy
    )
    VALUES (
        auth.uid(), p_game_id, btrim(p_name), p_description, p_default_storage_container_id,
        'NONE'
    )
    RETURNING collection.id, collection.name, collection.mode, collection.lifecycle_status,
              collection.visibility, collection.default_storage_container_id, collection.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_collection(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_collection(uuid, text, text, uuid) TO authenticated;
