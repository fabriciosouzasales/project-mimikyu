/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5047 - Create deallocate_physical_cards_from_collection Function
Versão......: 1.2 (hardening da Query 5140, foldado)
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02C-IMPLEMENTATION-01)

Descrição...:
Cria deallocate_physical_cards_from_collection(p_collection_id,
p_physical_card_ids) — única via de escrita de DELETE em
collection_allocation para authenticated, bulk-first, Owner-only,
espelho exato de allocate_physical_cards_to_collection() (Query 5046)
na estrutura de validação, inclusive na correção de não-enumeração
descrita no cabeçalho de 5046 (item 1 da rodada -STAGING-REVISION-01):
owner_user_id = auth.uid() já no WHERE da SELECT ... FOR UPDATE, uma
única mensagem genérica de erro tanto para Collection inexistente
quanto para Collection de outro Owner. Nome preservado desde a
proposta original — nenhuma alternativa melhor encontrada.

NUNCA toca collection.started_at, mesmo esvaziando a Collection por
completo (deallocate total não reseta started_at — confirmado
explicitamente em COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
REVISION-01, item 3, e reforçado pela própria trigger de 5044/5032,
que rejeitaria uma tentativa de voltar started_at a NULL de qualquer
forma). Esta função não faz nenhum UPDATE em collection.

Regras de Negócio (idênticas a 5046 até a escrita final):
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_physical_card_ids não vazio; teto de 500 sobre o array recebido,
  antes da deduplicação; dedup via array_agg(DISTINCT ...);
- SELECT ... FOR UPDATE na linha de collection, com owner_user_id =
  auth.uid() já no próprio WHERE — mesmo lock de 5046, fecha a mesma
  race de lifecycle;
- rejeita com a MESMA mensagem genérica ('collection not found or not
  owned by caller') tanto Collection inexistente quanto Collection de
  outro Owner — nenhuma distinção observável entre os dois casos;
- rejeita se lifecycle_status <> 'ACTIVE' (C-37 — ARCHIVED não aceita
  mudança de composição, deallocate incluso), só checado depois de já
  ter confirmado ownership;
- fail-closed em não-alocada/alocada em outra Collection: valida que
  todos os physical_card_ids distintos possuem, hoje, uma
  collection_allocation cujo collection_id = p_collection_id — se
  algum não bate, zero remoções;
- único DELETE...WHERE...RETURNING como escrita, set-based, sem loop;
  nunca remove allocation de outra Collection, mesmo que pertença ao
  mesmo Owner;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

HARDENING DE CARDINALIDADE DE PAYLOAD — FOLD-IN DA QUERY 5140
------------------------------------------------------------
Achado real (COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-
CORRECTION-03, §6 SECURITY SPILLOVER): o teto de 500 desta função era
medido com `array_length(p_physical_card_ids, 1)`, que conta APENAS a
primeira dimensão. Um payload multidimensional atravessava o teto — por
exemplo `array_fill(uuid, ARRAY[2, 400])` tem `array_length(x,1) = 2` e
`cardinality(x) = 800` — e o `unnest` processava os 800 elementos. Uma
RPC `SECURITY DEFINER` executava trabalho não limitado escolhido pelo
chamador; o teto existia no papel e não no comportamento.

A Query `5140` (`CREATE OR REPLACE`, aplicada ao banco real em
2026-09-07, `COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`)
substituiu o teto por, nesta ordem e todos ANTES de qualquer
`unnest`/`DISTINCT`/resolve de ownership/lock/escrita:

  1. NULL                     -> 'não pode ser vazio';
  2. cardinality(...) = 0     -> 'não pode ser vazio'
                                 (cobre '{}', cujo array_ndims é NULL);
  3. array_ndims(...) <> 1    -> 'deve ser um array unidimensional';
  4. cardinality(...) > 500   -> 'lote excede o limite de 500 itens
                                 por chamada'.

Assinatura, contrato de retorno, ownership, não-enumeração, locks,
semântica de lifecycle e grants permanecem inalterados; as mensagens de
erro pré-existentes foram preservadas literalmente. Validado por `5820`
v1.2 (27/27).

**O corpo executável deste arquivo é o da Query `5140`** — o estado
final efetivamente vivo no banco. `5140` permanece INTACTA em
`database/proposals/2026-09-06-bulk-payload-cardinality-hardening/` como
registro histórico. Por decisão de Fabrício em
`SCHEMA-PROMOTION-RECONCILIATION-01` (2026-09-08), **`5140` NÃO recebe
arquivo próprio em `database/schema/`**: a representação canônica é uma
definição por objeto. Mesmo padrão de `5039`×`5048`, `5046`×`5064` e
`5057`×`5092`.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO — corpo
efetivo = Query `5140` (fold-in em SCHEMA-PROMOTION-RECONCILIATION-01,
2026-09-08). O harness `5820` NÃO é promovido, por convenção.
================================================================
*/

CREATE OR REPLACE FUNCTION public.deallocate_physical_cards_from_collection(
    p_collection_id      UUID,
    p_physical_card_ids  UUID[]
)
RETURNS TABLE (
    physical_card_id  UUID,
    collection_id     UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_lifecycle_status TEXT;
    v_distinct_ids     UUID[];
    v_raw_count        INT;
    v_allocated_count  INT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_physical_card_ids IS NULL THEN
        RAISE EXCEPTION 'p_physical_card_ids não pode ser vazio';
    END IF;

    -- HARDENING: cardinality() conta TODOS os elementos, em qualquer
    -- numero de dimensoes. array_length(x, 1) contava apenas a
    -- primeira dimensao e permitia bypass do teto de 500.
    v_raw_count := cardinality(p_physical_card_ids);

    IF v_raw_count = 0 THEN
        RAISE EXCEPTION 'p_physical_card_ids não pode ser vazio';
    END IF;

    -- CONTRATO DE FORMA: somente array unidimensional. Avaliado ANTES
    -- de qualquer unnest/DISTINCT, resolve de ownership, lock ou
    -- escrita.
    IF array_ndims(p_physical_card_ids) <> 1 THEN
        RAISE EXCEPTION
            'p_physical_card_ids deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_physical_card_ids);
    END IF;

    IF v_raw_count > 500 THEN
        RAISE EXCEPTION 'lote excede o limite de 500 itens por chamada';
    END IF;

    SELECT array_agg(DISTINCT x) INTO v_distinct_ids
    FROM unnest(p_physical_card_ids) AS x;

    SELECT col.lifecycle_status
    INTO v_lifecycle_status
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before deallocating';
    END IF;

    SELECT count(*) INTO v_allocated_count
    FROM public.collection_allocation ca
    WHERE ca.physical_card_id = ANY(v_distinct_ids)
      AND ca.collection_id = p_collection_id;

    IF v_allocated_count <> cardinality(v_distinct_ids) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não estão alocadas a esta Collection';
    END IF;

    RETURN QUERY
    DELETE FROM public.collection_allocation
    WHERE collection_allocation.physical_card_id = ANY(v_distinct_ids)
      AND collection_allocation.collection_id = p_collection_id
    RETURNING
        collection_allocation.physical_card_id,
        collection_allocation.collection_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.deallocate_physical_cards_from_collection(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deallocate_physical_cards_from_collection(uuid, uuid[]) TO authenticated;
