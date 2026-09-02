/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5046 - Create allocate_physical_cards_to_collection Function
Versão......: 1.2 (estendida em 2026-09-02, aplicada em 2026-09-02, via
               Query 5064, COLLECTIONS-PHYSICAL-INCREMENT-02D-
               IMPLEMENTATION-01)
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02C-IMPLEMENTATION-01;
               estendida em 2026-09-02, via Query 5064, COLLECTIONS-
               PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Cria allocate_physical_cards_to_collection(p_collection_id,
p_physical_card_ids) — única via de escrita de INSERT em
collection_allocation para authenticated, bulk-first (1 chamada = 1 a
500 Physical Cards, mesmo teto de add_physical_cards()/
set_physical_cards_storage()). Owner-only (C-147 — "Collection
Allocation permanece Owner-only no V1").

Contrato de retorno explícito — RETURNS TABLE(physical_card_id,
collection_id, created_at), nunca RETURNS SETOF collection_allocation
(mesma justificativa já usada em toda RPC bulk do domínio): conjunto
mínimo útil — physical_card_id identifica a carta afetada,
collection_id confirma o destino, created_at confirma quando a
Allocation passou a existir.

CORREÇÃO (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-FINAL-01, item
3). A versão original desta proposta setava collection.started_at =
NOW() diretamente na RPC. Removida por completo — started_at agora é
materializado automaticamente pela trigger da Query 5045 como
consequência do próprio INSERT em collection_allocation, nunca uma
responsabilidade explícita desta função. A RPC não sabe, e não precisa
saber, se esta é a primeira Allocation da Collection ou não.

CORREÇÃO (COLLECTIONS-PHYSICAL-INCREMENT-02C-STAGING-REVISION-01, item
1 — não vazar existência de Collection alheia). A versão anterior fazia
SELECT ... FOR UPDATE só por id e SÓ DEPOIS comparava owner_user_id
contra auth.uid(), com duas mensagens de erro distintas ('collection
not found' vs 'collection not found or not owned by caller') — isso
permite a um caller autenticado distinguir "Collection não existe" de
"Collection existe mas é de outro Owner", uma enumeração real.
Corrigido incorporando owner_user_id = auth.uid() diretamente no WHERE
da própria SELECT ... FOR UPDATE: uma Collection de outro Owner
simplesmente não casa a query, produzindo o mesmo NOT FOUND e a mesma
mensagem genérica de uma Collection inexistente. Nenhuma variável
intermediária armazena mais o owner real antes de qualquer comparação
— não há comparação alguma, só (in)existência da linha sob aquele
filtro composto. Mesmo padrão aplicado a deallocate_physical_cards_
from_collection() (Query 5047).

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_physical_card_ids não vazio; teto de 500 avaliado sobre o array
  RECEBIDO, antes da deduplicação;
- deduplicação via array_agg(DISTINCT ...) sobre unnest(), mesmo
  padrão de set_physical_cards_storage();
- SELECT ... FOR UPDATE na linha de collection, com owner_user_id =
  auth.uid() já no próprio WHERE (não como comparação posterior) —
  lock explícito, não pré-leitura solta — fecha a race de lifecycle
  contra archive_collection()/reactivate_collection() (Query 5037/
  5038, mesmo UPDATE ... WHERE lifecycle_status = ...) e serializa
  allocate()/deallocate() concorrentes na mesma Collection, o que
  também torna segura a leitura implícita de started_at feita pela
  trigger de 5045 (nenhuma janela onde duas Allocations concorrentes
  decidem com base em estado desatualizado);
- rejeita com a MESMA mensagem genérica ('collection not found or not
  owned by caller') tanto Collection inexistente quanto Collection de
  outro Owner — nenhuma distinção observável entre os dois casos;
- rejeita se lifecycle_status <> 'ACTIVE' (só chega a esta checagem
  depois de já ter confirmado ownership);
- resolve Inventory do caller; valida que todos os physical_card_ids
  distintos pertencem a esse Inventory E ao mesmo game_id da
  Collection (C-05) — pré-validação amigável antes do INSERT; a
  trigger de 5042 é a garantia estrutural real, independente desta
  checagem;
- rejeita se qualquer physical_card_id já estiver em
  collection_allocation (nesta Collection ou em outra) — fail-closed,
  zero inserções, sem auto-move; mover uma carta entre Collections
  exige deallocate + allocate explícitos;
- único INSERT...SELECT...RETURNING como escrita, set-based, sem loop
  por linha — dispara as triggers de 5042 (validação estrutural) e
  5045 (materialização de started_at) como parte da mesma transação;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

EXTENSÃO (Query 5064, COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01). Extensão de regra sobre esta função (CREATE OR
REPLACE, mesma assinatura/contrato de retorno/teto de 500/deduplicação
/fail-closed de "já alocada"/lock de concorrência já existentes —
extensão pura), mesma instrução de -MODELING-FINAL-01, item 6, já
citada no cabeçalho de 5063. Adiciona uma pré-validação amigável de
elegibilidade de Reference, simétrica à checagem estrutural da Query
5063: quando a Collection é REFERENCE_BASED com Card Set Reference,
todo physical_card_id do lote deve ter Card pertencente ao card_set_id
referenciado. Fail-closed preservado — mesmo raciocínio de "uma ou
mais... rejeitado" já usado para a checagem de Owner/Game existente.
Resolvida com uma única consulta adicional, reaproveitando
v_collection_game/v_lifecycle_status já obtidos pelo SELECT ... FOR
UPDATE original (nenhuma segunda leitura de collection): busca o
Collection Reference/Card Set Reference da Collection (0 ou 1 linha,
LEFT JOIN), e só aplica a checagem quando existir. Segunda camada de
defesa: a checagem estrutural equivalente já existe em validate_
collection_allocation_integrity() (Query 5063, trigger independente de
RPC) — esta é só a mensagem amigável antecipada, não a garantia de
fundo. Validado em execução real (5808, Casos R/S).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.allocate_physical_cards_to_collection(
    p_collection_id      UUID,
    p_physical_card_ids  UUID[]
)
RETURNS TABLE (
    physical_card_id  UUID,
    collection_id     UUID,
    created_at         TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id       UUID;
    v_collection_game    UUID;
    v_lifecycle_status   TEXT;
    v_collection_mode    TEXT;
    v_reference_kind     TEXT;
    v_reference_card_set UUID;
    v_distinct_ids       UUID[];
    v_raw_count          INT;
    v_owned_count        INT;
    v_already_count      INT;
    v_eligible_count     INT;
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

    SELECT col.game_id, col.lifecycle_status, col.mode
    INTO v_collection_game, v_lifecycle_status, v_collection_mode
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before allocating';
    END IF;

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    SELECT count(*) INTO v_owned_count
    FROM public.physical_card pc
    JOIN public.card_variant cv ON cv.id = pc.card_variant_id
    JOIN public.card ca ON ca.id = cv.card_id
    JOIN public.card_set cs ON cs.id = ca.card_set_id
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE pc.id = ANY(v_distinct_ids)
      AND pc.inventory_id = v_inventory_id
      AND ex.game_id = v_collection_game;

    IF v_owned_count <> array_length(v_distinct_ids, 1) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não pertencem ao inventory do chamador ou ao Game da Collection';
    END IF;

    -- Elegibilidade de Reference (LDM-17): só se aplica quando a
    -- Collection é REFERENCE_BASED e tem Card Set Reference — 0 linhas
    -- para OPEN_CURATION, por causa do LEFT JOIN.
    SELECT cr.reference_kind, ccsr.card_set_id
    INTO v_reference_kind, v_reference_card_set
    FROM public.collection_reference cr
    LEFT JOIN public.collection_card_set_reference ccsr
        ON ccsr.collection_reference_id = cr.id
    WHERE cr.collection_id = p_collection_id;

    IF v_collection_mode = 'REFERENCE_BASED' AND v_reference_kind = 'CARD_SET' THEN
        SELECT count(*) INTO v_eligible_count
        FROM public.physical_card pc
        JOIN public.card_variant cv ON cv.id = pc.card_variant_id
        JOIN public.card ca ON ca.id = cv.card_id
        WHERE pc.id = ANY(v_distinct_ids)
          AND ca.card_set_id = v_reference_card_set;

        IF v_eligible_count <> array_length(v_distinct_ids, 1) THEN
            RAISE EXCEPTION 'uma ou mais physical_card_ids não pertencem ao Card Set referenciado pela Collection';
        END IF;
    END IF;

    SELECT count(*) INTO v_already_count
    FROM public.collection_allocation ca
    WHERE ca.physical_card_id = ANY(v_distinct_ids);

    IF v_already_count > 0 THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids já estão alocadas a uma Collection';
    END IF;

    RETURN QUERY
    INSERT INTO public.collection_allocation (physical_card_id, collection_id)
    SELECT x, p_collection_id
    FROM unnest(v_distinct_ids) AS x
    RETURNING
        collection_allocation.physical_card_id,
        collection_allocation.collection_id,
        collection_allocation.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.allocate_physical_cards_to_collection(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.allocate_physical_cards_to_collection(uuid, uuid[]) TO authenticated;
