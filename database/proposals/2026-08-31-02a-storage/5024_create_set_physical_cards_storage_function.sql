/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5024 - Create set_physical_cards_storage Function (PROPOSTA)
Versão......: 2.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em
               COLLECTIONS-PHYSICAL-INCREMENT-02A-STAGING-REVISION-01)

Descrição...:
Cria set_physical_cards_storage(p_storage_container_id,
p_physical_card_ids) — única via de escrita de
physical_card.storage_container_id para authenticated, bulk-first (1
chamada = 1 a 500 Physical Cards, mesmo teto de add_physical_cards(),
Query 5012).

Substitui assign_physical_cards_to_storage() (versão 1.0 desta Query,
COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01) por nome/semântica que
cobrem todo o ciclo de vida de Current Storage (C-58: uma Physical
Card possui 0..1 Storage Container corrente por vez, podendo não ter
nenhum). A versão anterior só cobria atribuir/mover; não existia
caminho oficial para "limpar" a localização corrente (Storage A ->
NULL) sem UPDATE direto (que não é permitido — sem policy de UPDATE
para authenticated, Query 5010).

Semântica do parâmetro p_storage_container_id:
- valor não-nulo -> atribui/move os Physical Cards informados para
  esse Storage Container (mesma validação de pertencimento ao
  Inventory do chamador da versão anterior);
- NULL -> limpa storage_container_id dos Physical Cards informados
  (Storage corrente -> nenhum). Não há Storage Container para
  verificar pertencimento quando o valor é NULL — o bloco de
  validação do container é pulado nesse caso; a única checagem que
  permanece é que os Physical Cards pertencem ao Inventory do
  chamador.

IDs duplicados no payload ([A, A, B]): normalizados internamente para
DISTINCT antes de qualquer verificação de pertencimento ou UPDATE — A
e B são processados exatamente uma vez, o retorno tem no máximo tantas
linhas quanto IDs distintos. O limite de 500 é avaliado sobre o
payload RECEBIDO (array_length antes da deduplicação), não sobre o
array já deduplicado — um payload com 501 elementos é rejeitado mesmo
que só existam 3 IDs distintos entre eles, por simplicidade e para não
criar uma superfície onde o cliente precisa entender "limite antes ou
depois de deduplicar" caso a caso.

Contrato de retorno explícito — RETURNS TABLE(id, storage_container_id,
updated_at), não RETURNS SETOF physical_card (mesma justificativa já
aplicada em add_physical_cards(), Query 5012): um retorno acoplado à
tabela inteira exporia automaticamente qualquer coluna futura de
physical_card como parte do contrato público desta RPC, sem decisão
deliberada no momento em que essa coluna fosse criada. Conjunto mínimo
útil para esta operação especificamente: id (qual Physical Card foi
afetado), storage_container_id (novo estado corrente — inclui NULL
quando a operação foi de limpeza, permitindo ao chamador confirmar
que a localização foi de fato removida), updated_at (confirmação de
quando a mudança ocorreu). Deliberadamente excluído: inventory_id (sem
valor informativo — nunca muda nesta operação, só existe um Inventory
possível, o do próprio chamador), card_variant_id/language_id (não
pertencem à semântica desta operação — expô-los aqui acoplaria o
contrato de Storage ao contrato de catálogo sem necessidade), created_at
(irrelevante para uma operação que só afeta o estado corrente de
Storage, não a criação do registro).

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
chk_physical_card_storage_requires_inventory (Query 5023, inalterados
nesta revisão) continuam sendo a garantia estrutural permanente da
integridade Inventory×Storage — a validação nesta RPC existe para dar
erro claro antes de tentar a escrita, não para substituir a
constraint.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Depende da execução
prévia de 5020/5022/5023.
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
