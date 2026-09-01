/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5034 - Create create_collection Function (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01
               → -REVISION-01 → -FINAL-01 →
               -IMPLEMENTATION-01, correção pré-Fase 2)

Descrição...:
Cria create_collection(p_game_id, p_name, p_description,
p_default_storage_container_id) — única via de escrita/criação de
public.collection para authenticated. Não é bulk — 1 chamada = 1
Collection, mesmo padrão de create_storage_container() (Query 5022).

owner_user_id NUNCA é aceito como parâmetro — sempre resolvido no
servidor via auth.uid(), estruturalmente impossível ao cliente forjar
o Owner. mode/lifecycle_status/visibility também não são parâmetros —
usam os DEFAULTs da tabela ('OPEN_CURATION'/'ACTIVE'/'PRIVATE'), únicos
valores fisicamente permitidos nesta etapa (Query 5030).

CORREÇÃO PRÉ-FASE 2 (COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-
01). A v1.0 desta Query dependia de public.game.is_active para
distinguir "game not found" de "game is not active" — checagem
herdada por analogia indevida do padrão real de card.is_active
(ADR-023), nunca de fato existente em game. Confirmado por leitura
direta do schema físico (information_schema.columns) que
public.game tem apenas id/code/name/created_at/updated_at — nenhuma
decisão conceitual deste incremento (C-*/LDM-*) documenta um estado
ativo/inativo para Game. Removida a dependência: create_collection()
agora exige apenas que p_game_id corresponda a um Game existente
(mesmo texto de erro 'game not found'); não há mais caso "game is
not active". A garantia estrutural de que game_id sempre aponta para
um Game real permanece a FK collection.game_id -> game.id (Query
5030), que já era a proteção de fundo independente desta checagem de
conveniência. Eventual lifecycle/ativação de Game é decisão futura do
domínio de Catálogo, fora do escopo de Collections — se um dia for
implementada, poderá exigir revisão desta política de
create_collection().

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_name obrigatório e não-vazio após btrim();
- p_game_id deve existir em public.game — não há checagem de
  ativo/inativo (ver correção acima); a FK collection.game_id ->
  game.id é a garantia estrutural de fundo;
- Inventory do chamador resolvido via public.inventory.owner_user_id
  = auth.uid(); se não encontrado, RAISE EXCEPTION;
- p_default_storage_container_id deve pertencer a um Storage Container
  do Inventory do chamador (early error; a garantia estrutural
  permanente é o trigger da Query 5033, que dispara de qualquer forma
  no INSERT abaixo);
- retorno explícito (id, name, mode, lifecycle_status, visibility,
  default_storage_container_id, created_at) — não usa
  RETURNS SETOF public.collection, mesma justificativa de contrato
  mínimo já aplicada em create_storage_container()/
  add_physical_cards(): evita vazar automaticamente colunas futuras
  (ex.: completion_policy, quando existir) no contrato público desta
  RPC. Omite description (o chamador já digitou o texto),
  owner_user_id/game_id (o chamador já sabe o que informou) e
  updated_at (== created_at neste momento, redundante);
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Requer que 5030-5033
estejam aplicadas.
================================================================
*/

CREATE FUNCTION public.create_collection(
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
        owner_user_id, game_id, name, description, default_storage_container_id
    )
    VALUES (
        auth.uid(), p_game_id, btrim(p_name), p_description, p_default_storage_container_id
    )
    RETURNING collection.id, collection.name, collection.mode, collection.lifecycle_status,
              collection.visibility, collection.default_storage_container_id, collection.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_collection(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_collection(uuid, text, text, uuid) TO authenticated;
