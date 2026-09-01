/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5022 - Create create_storage_container Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01)

Descrição...:
Cria create_storage_container(p_name text) — única via de escrita de
public.storage_container para authenticated. Não é bulk (criação de
Storage Container é evento de UX único, não operação em massa como
add_physical_cards()) — 1 chamada = 1 Storage Container. Inventory do
chamador é resolvido no servidor a partir de auth.uid() — o parâmetro
NÃO aceita inventory_id, mesma técnica de add_physical_cards() (Query
5012): estruturalmente impossível ao cliente forjar o Inventory de
destino.

SECURITY DEFINER é estruturalmente necessário, não estilístico: não
existe nenhuma policy de INSERT para authenticated em
storage_container, então uma função SECURITY INVOKER seria bloqueada
pela própria RLS ao tentar inserir — mesma justificativa de
add_physical_cards() (COLLECTIONS-PHYSICAL-MODELING-02, item 6).

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_name obrigatório e não-vazio após btrim();
- Inventory do chamador resolvido via public.inventory.owner_user_id
  = auth.uid(); se não encontrado, RAISE EXCEPTION;
- retorno explícito (id, name, created_at) — não usa
  RETURNS SETOF public.storage_container, mesma justificativa de
  contrato mínimo já aplicada em add_physical_cards() (Query 5012):
  evita vazar automaticamente colunas futuras (ex.: parent, capacity)
  no contrato público da RPC;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

CONFIRMADO EXECUTADO em 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02A-
IMPLEMENTATION-01, Fase 1) via apply_migration (versão de migration
Supabase 20260901002947). Validado ao vivo (transacional, sem commit):
Storage Container criado sempre resolve para o Inventory do próprio
chamador (matches_own_inventory = true); EXPLAIN (ANALYZE, BUFFERS)
sobre chamada single-row: 0,780ms — ver
database/validations/5803_performance_checks_collections_physical_increment_02a.sql.
================================================================
*/

CREATE FUNCTION public.create_storage_container(p_name text)
RETURNS TABLE (
    id           UUID,
    name         TEXT,
    created_at   TIMESTAMPTZ
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

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    RETURN QUERY
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES (v_inventory_id, btrim(p_name))
    RETURNING storage_container.id, storage_container.name, storage_container.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_storage_container(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_storage_container(text) TO authenticated;
