/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5138 - Harden set_physical_cards_storage() — Payload Cardinality
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (criado em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-03,
               §6 SECURITY SPILLOVER)

Descrição...:
MIGRATION INCREMENTAL de segurança. NÃO edita a migration histórica
`5024`, que permanece intacta como registro do que foi executado.
Este arquivo faz `CREATE OR REPLACE FUNCTION` sobre
`public.set_physical_cards_storage(uuid, uuid[])`.

ACHADO (BYPASS REAL, MESMA CLASSE DO BLOCKER DA BINDER/LAYOUT
FOUNDATION)
----------------------------------------------------------------
A definição canônica efetiva desta função — `database/schema/5024` —
limita o lote com:

    IF p_physical_card_ids IS NULL OR array_length(p_physical_card_ids, 1) IS NULL ...
    v_raw_count := array_length(p_physical_card_ids, 1);
    IF v_raw_count > 500 THEN ...

`array_length(x, 1)` mede APENAS A PRIMEIRA DIMENSÃO. Um payload
multidimensional atravessa o teto:

    array_fill(uuid, ARRAY[2, 400])
        array_ndims        = 2
        array_length(x, 1) = 2      <- passa pelo teto de 500
        cardinality(x)     = 800
        unnest(x)          = 800 linhas

Ou seja: uma RPC pública `SECURITY DEFINER` executa trabalho não
limitado (unnest + sort + DISTINCT + validação linha a linha) sobre um
array de tamanho arbitrário escolhido pelo chamador. O teto existia no
papel e não no comportamento.

Isto é **segurança material**, não higiene: o mesmo padrão foi
classificado como BLOCKER nas RPCs da Binder/Layout Foundation pela
FINAL MATERIAL AUDIT, e estas três funções foram citadas como o
precedente canônico que aquelas seguiam.

CORREÇÃO
--------
Guards, todos ANTES de qualquer unnest/DISTINCT, resolve de ownership,
lock ou escrita:
  1. NULL                        -> 'não pode ser vazio';
  2. cardinality(...) = 0        -> 'não pode ser vazio'
                                    (cobre '{}', cujo array_ndims é NULL);
  3. array_ndims(...) <> 1       -> 'deve ser um array unidimensional';
  4. cardinality(...) > 500      -> 'lote excede o limite de 500 itens
                                    por chamada'.

ALTERAÇÃO MÍNIMA E VERIFICÁVEL: o restante do corpo é BYTE-IDÊNTICO ao
de `5024`. Assinatura, contrato de retorno, ownership,
não-enumeração, locks, semântica de lifecycle, grants — nada mudou.
As mensagens de erro pré-existentes foram preservadas literalmente.

COMPATIBILIDADE
---------------
Nenhum chamador legítimo envia array multidimensional: o cliente
JS/TS envia `uuid[]` plano. Nenhum lote legítimo de <= 500 itens muda
de comportamento.

Dependências:
- public.set_physical_cards_storage() já existente (5024).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_physical_cards_storage(
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

    IF v_owned_count <> cardinality(v_distinct_ids) THEN
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

COMMIT;

/*
Como validar (APÓS aplicar):

-- 1) a definicao efetiva usa cardinality e array_ndims, e nao usa mais
--    array_length sobre o parametro.
SELECT position('cardinality(p_physical_card_ids)' in pg_get_functiondef(p.oid)) > 0 AS usa_cardinality,
       position('array_ndims(p_physical_card_ids) <> 1' in pg_get_functiondef(p.oid)) > 0 AS usa_ndims,
       position('array_length(p_physical_card_ids' in pg_get_functiondef(p.oid)) = 0   AS sem_array_length
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='set_physical_cards_storage';

-- Esperado: t / t / t

-- 2) prova comportamental (dentro de BEGIN ... ROLLBACK, como owner):
--    payload multidimensional com cardinality > 500 deve FALHAR com
--    'unidimensional', e nao ser processado.
*/
