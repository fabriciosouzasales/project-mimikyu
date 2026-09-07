/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5129 - Create clear_slot_expected_content()
Versão......: 4.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Remove o Expected Content de um ou mais Slots. Assinatura em array
cobre individual e bulk sem RPC paralela (princípio de escopo do
MATERIALITY AUDIT: evitar RPC por micro-operação).

Idempotente: Slot sem Expected Content não é erro — o DELETE
simplesmente não afeta linha. Retorna quantos foram efetivamente
removidos.

Lock não bloqueia (C-43) — mesma justificativa de 5128.

Todos os Slots devem pertencer ao MESMO Layout; caso contrário a
operação é rejeitada inteira. Isso mantém a fronteira de autorização
em um único assert e impede que um array misturado escape da checagem.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_slot_expected_content (Query 5113).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§1 BLOCKER min(uuid) + §3 POST-LOCK REVALIDATION +
§4A NON-ENUMERATION EM ARRAYS.

(a) BLOCKER REAL: a v1.0 usava `min(p.layout_id)` sobre UUID.
    PostgreSQL NÃO possui `min(uuid)` built-in — a função abortaria
    com `function min(uuid) does not exist` na primeira execução.
    Corrigido SEM aggregate customizado e SEM cast para text: conta-se
    `count(DISTINCT p.layout_id)`, exige-se exatamente 1, e só então o
    layout_id é obtido por consulta separada e determinística a partir
    do PRIMEIRO Slot do array deduplicado.

(b) ORÁCULO DE EXISTÊNCIA: a v1.0 resolvia os Slots SEM filtro de
    ownership. Um array com [Slot próprio + Slot alheio existente]
    passava na contagem e falhava depois em 'mesmo Layout', enquanto
    [Slot próprio + UUID inexistente] falhava em 'not found' — dois
    ramos distinguíveis, portanto um oráculo. Agora o resolve é
    owner-scoped e QUALQUER id não visível ao caller produz sempre a
    mesma mensagem genérica 'layout slot not found or not owned by
    caller'. A validação de "mesmo Layout" só acontece DEPOIS disso.

(c) Os ids são deduplicados antes de tudo, e os Slots são REVALIDADOS
    depois do lock — nunca se decide com o snapshot pré-espera.

CORREÇÃO CONSOLIDADA 02 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-02):
§1 LIMITE RAW DE 500 ITENS POR CHAMADA.
BLOCKER material da FINAL DIRECT RE-AUDIT: esta RPC pública
SECURITY DEFINER aceitava `UUID[]` de tamanho arbitrário e executava
`unnest` + `DISTINCT` ANTES de qualquer rejeição — trabalho não
limitado sob privilégio elevado. Corrigido com o teto de 500 já
canônico em 5024/5046/5047, avaliado sobre o PAYLOAD BRUTO (antes da
deduplicação): 501 elementos repetidos também falham.
Nada mais mudou — ownership, não-enumeração, ordem de lock,
revalidação pós-lock, semântica de Lock e contrato de retorno
permanecem byte-semanticamente equivalentes.

CORREÇÃO CONSOLIDADA 03 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-03):
§1 CARDINALIDADE REAL DE UUID[] — BLOCKER DA FINAL MATERIAL AUDIT.

A CORREÇÃO 02 usava `array_length(p_slot_ids, 1)`, que mede APENAS a
PRIMEIRA DIMENSÃO. Isso é um BYPASS real: um payload multidimensional
como `ARRAY[[...],[...]]` com 2 linhas de 400 elementos tem
`array_length(x,1) = 2` — passaria pelo teto de 500 — mas
`cardinality(x) = 800`, e `unnest()` produziria 800 linhas. O teto
existia no papel e não no comportamento.

Corrigido com TRÊS guards, todos ANTES de qualquer unnest/DISTINCT,
ownership resolution, lock ou mutação:
  1. NULL                      -> 'não pode ser vazio';
  2. cardinality(...) = 0      -> 'não pode ser vazio'
                                  (cobre '{}' , cujo array_ndims é NULL);
  3. array_ndims(...) <> 1     -> 'deve ser um array unidimensional'
                                  — contrato de forma, rejeita qualquer
                                  payload multidimensional;
  4. cardinality(...) > 500    -> 'lote excede o limite de 500 itens
                                  por chamada' — quantidade REAL de
                                  elementos, não a primeira dimensão.

`cardinality()` é usado em todos os pontos de contagem; nenhum
`array_length(..., 1)` permanece nesta função. Ownership,
não-enumeração, ordem COLLECTION->LAYOUT, locks determinísticos,
ARCHIVED e revalidação pós-lock permanecem inalterados.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.clear_slot_expected_content(
    p_slot_ids UUID[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_raw_count    INTEGER;
    v_ids          UUID[];
    v_input_count  INTEGER;
    v_found_count  INTEGER;
    v_layout_count INTEGER;
    v_layout_id    UUID;
    v_deleted      INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_slot_ids IS NULL THEN
        RAISE EXCEPTION 'p_slot_ids não pode ser vazio';
    END IF;

    -- §1 CORREÇÃO CONSOLIDADA 03 — CARDINALIDADE REAL.
    -- cardinality() conta TODOS os elementos, em qualquer número de
    -- dimensões; array_length(x,1) contaria apenas a primeira.
    v_raw_count := cardinality(p_slot_ids);

    IF v_raw_count = 0 THEN
        RAISE EXCEPTION 'p_slot_ids não pode ser vazio';
    END IF;

    -- CONTRATO DE FORMA: somente array unidimensional. Avaliado ANTES
    -- de qualquer unnest/DISTINCT, resolve de ownership, lock ou
    -- mutação. Fecha o bypass multidimensional.
    IF array_ndims(p_slot_ids) <> 1 THEN
        RAISE EXCEPTION
            'p_slot_ids deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_slot_ids);
    END IF;

    -- TETO DE LOTE sobre a CARDINALIDADE BRUTA (payload recebido),
    -- antes da deduplicação. Padrão canônico de 5024/5046/5047.
    IF v_raw_count > 500 THEN
        RAISE EXCEPTION 'lote excede o limite de 500 itens por chamada';
    END IF;


    -- 1) DEDUPLICAÇÃO explícita (o contrato aceita repetições).
    v_ids := ARRAY(SELECT DISTINCT x
                     FROM unnest(p_slot_ids) AS x
                    WHERE x IS NOT NULL);
    v_input_count := cardinality(v_ids);

    IF v_input_count = 0 THEN
        RAISE EXCEPTION 'p_slot_ids não pode ser vazio';
    END IF;

    -- 2) RESOLVE OWNER-SCOPED. Inexistente e alheio são
    -- indistinguíveis por construção: ambos simplesmente não contam.
    SELECT count(*), count(DISTINCT p.layout_id)
      INTO v_found_count, v_layout_count
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE s.id = ANY (v_ids)
       AND c.owner_user_id = (select auth.uid());

    IF v_found_count <> v_input_count THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    -- 3) SOMENTE DEPOIS da prova de ownership: mesmo Layout.
    IF v_layout_count <> 1 THEN
        RAISE EXCEPTION 'todos os Slots devem pertencer ao mesmo Layout';
    END IF;

    -- 4) Layout único, obtido por consulta separada e determinística.
    -- NENHUM aggregate de ordenação sobre UUID (não existe min(uuid)).
    SELECT p.layout_id
      INTO v_layout_id
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
     WHERE s.id = v_ids[1];

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    -- 5) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE (helper 5122).
    BEGIN
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout slot not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 6) SLOT LOCK em ordem determinística.
    PERFORM 1
       FROM public.collection_layout_slot s
      WHERE s.id = ANY (v_ids)
      ORDER BY s.id
      FOR UPDATE;

    -- 7) REVALIDAÇÃO PÓS-LOCK dos Slots (existência + ownership +
    -- mesmo Layout). Se algo mudou durante a espera, erro uniforme.
    SELECT count(*), count(DISTINCT p.layout_id)
      INTO v_found_count, v_layout_count
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE s.id = ANY (v_ids)
       AND p.layout_id = v_layout_id
       AND c.owner_user_id = (select auth.uid());

    IF v_found_count <> v_input_count OR v_layout_count <> 1 THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    DELETE FROM public.collection_layout_slot_expected_content
     WHERE slot_id = ANY (v_ids);

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.clear_slot_expected_content(uuid[])
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_slot_expected_content(uuid[])
    TO authenticated;

COMMIT;
