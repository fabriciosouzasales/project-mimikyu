/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5024 - Create set_physical_cards_storage Function
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (v1.0 assign_physical_cards_to_storage,
               revisada em COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-
               REVISION-01 para v2.0/set_physical_cards_storage;
               aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01)

Descrição...:
Cria set_physical_cards_storage(p_storage_container_id,
p_physical_card_ids) — única via de escrita de
physical_card.storage_container_id para authenticated, bulk-first (1
chamada = 1 a 500 Physical Cards, mesmo teto de add_physical_cards(),
Query 5012).

Cobre todo o ciclo de vida de Current Storage (C-58: uma Physical Card
possui 0..1 Storage Container corrente por vez, podendo não ter
nenhum). Semântica do parâmetro p_storage_container_id: valor não-nulo
atribui/move os Physical Cards informados para esse Storage Container
(valida pertencimento ao Inventory do chamador); NULL limpa
storage_container_id dos Physical Cards informados (Storage corrente
-> nenhum) — o bloco de verificação de container é pulado por
completo nesse caso.

IDs duplicados no payload ([A, A, B]): normalizados internamente para
DISTINCT antes de qualquer validação/escrita — A e B processados
exatamente uma vez. O limite de 500 é avaliado sobre o array
RECEBIDO, antes da deduplicação.

Contrato de retorno explícito — RETURNS TABLE(id, storage_container_id,
updated_at), não RETURNS SETOF physical_card (mesma justificativa já
aplicada em add_physical_cards(), Query 5012): conjunto mínimo útil
para esta operação especificamente; id identifica o card afetado,
storage_container_id confirma o novo estado corrente (incluindo NULL,
para o chamador confirmar que a limpeza ocorreu), updated_at confirma
quando. Deliberadamente excluído: inventory_id (nunca muda nesta
operação, só um Inventory possível), card_variant_id/language_id (fora
da semântica desta operação), created_at (irrelevante — a operação não
cria registro).

SECURITY DEFINER estruturalmente necessário: não existe policy de
UPDATE para authenticated em physical_card (Query 5010) — SECURITY
INVOKER seria bloqueado pela própria RLS.

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_physical_card_ids não pode ser vazio;
- limite de 500 avaliado sobre o array recebido, antes da
  deduplicação;
- deduplicação via array_agg(DISTINCT ...) sobre unnest() do array
  recebido, antes de qualquer validação de pertencimento;
- quando p_storage_container_id IS NOT NULL, deve existir e pertencer
  ao Inventory do chamador (RAISE EXCEPTION caso contrário); quando
  IS NULL, este bloco é pulado inteiramente;
- todos os IDs distintos de p_physical_card_ids devem pertencer ao
  Inventory do chamador — validado por contagem antes do UPDATE
  (atomicidade: 1 id de outro Owner no lote -> 0 updates, nenhuma das
  demais cartas do lote é alterada);
- único UPDATE...WHERE...RETURNING como escrita, set-based, sem loop
  por linha;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

A FK composta fk_physical_card_storage_same_inventory e o CHECK
chk_physical_card_storage_requires_inventory (Query 5023) continuam
sendo a garantia estrutural permanente da integridade
Inventory×Storage — a validação nesta RPC existe para dar erro claro
antes de tentar a escrita, não para substituir a constraint.

CONFIRMADO EXECUTADO em 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02A-
IMPLEMENTATION-01, Fase 3) via apply_migration (versão de migration
Supabase 20260901003608). Validado ao vivo (transacional, sem commit),
casos F-J:
F. Storage A -> NULL: PASS, storage_container_id retornado NULL;
G. payload [A,A,B]: PASS, retorno com exatamente 2 linhas (A e B, uma
   vez cada), confirma deduplicação;
H. lote com card do próprio Owner + card de outro User: FAIL
   ('um ou mais physical_card_ids não pertencem ao inventory do
   chamador'), 0 alterações — inclusive nos cards do próprio Owner no
   mesmo lote (atomicidade confirmada; achado de metodologia: a
   primeira tentativa deste caso usou uma subquery live para montar o
   array de teste, que a própria RLS de physical_card filtrou antes de
   chegar à RPC, produzindo um falso PASS por motivo errado — corrigido
   capturando os IDs como literais antes de trocar de role, o que
   revelou o comportamento real e correto da RPC);
I. lote de 501 elementos (poucos distintos entre eles): FAIL
   ('lote excede o limite de 500 itens por chamada') — confirma que o
   teto é avaliado sobre o array recebido, antes da deduplicação;
J. Storage Container de outro Inventory: FAIL
   ('storage container does not belong to caller inventory').
Performance sobre volume sintético de 20.000 Physical Cards: bulk
assign de 500 itens ~61-65ms; bulk clear (NULL) de 500 itens ~55ms —
mesma ordem de grandeza já observada em add_physical_cards() (52,525ms
para 500 itens sobre 20k linhas) — ver
database/validations/5802_validate_collections_physical_increment_02a.sql
e 5803_performance_checks_collections_physical_increment_02a.sql.
================================================================
*/

CREATE FUNCTION public.set_physical_cards_storage(
    p_storage_container_id UUID,
    p_physical_card_ids UUID[]
)
RETURNS TABLE (
    id                    UUID,
    storage_container_id  UUID,
    updated_at            TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id           UUID;
    v_container_inventory_id UUID;
    v_distinct_ids           UUID[];
    v_raw_count               INT;
    v_owned_count             INT;
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

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    IF p_storage_container_id IS NOT NULL THEN
        SELECT sc.inventory_id INTO v_container_inventory_id
        FROM public.storage_container sc
        WHERE sc.id = p_storage_container_id;

        IF v_container_inventory_id IS NULL THEN
            RAISE EXCEPTION 'storage container not found';
        END IF;

        IF v_container_inventory_id IS DISTINCT FROM v_inventory_id THEN
            RAISE EXCEPTION 'storage container does not belong to caller inventory';
        END IF;
    END IF;

    SELECT count(*) INTO v_owned_count
    FROM public.physical_card pc
    WHERE pc.id = ANY(v_distinct_ids)
      AND pc.inventory_id = v_inventory_id;

    IF v_owned_count <> array_length(v_distinct_ids, 1) THEN
        RAISE EXCEPTION 'um ou mais physical_card_ids não pertencem ao inventory do chamador';
    END IF;

    RETURN QUERY
    UPDATE public.physical_card
    SET storage_container_id = p_storage_container_id
    WHERE physical_card.id = ANY(v_distinct_ids)
      AND physical_card.inventory_id = v_inventory_id
    RETURNING physical_card.id, physical_card.storage_container_id, physical_card.updated_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_physical_cards_storage(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_physical_cards_storage(uuid, uuid[]) TO authenticated;
