/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5278 - P3-B S3 · Histórico do Fichário — instrumentação E10 (Bolsos fixados / desfixados)
              set_slot_lock(uuid[], boolean)
Versão......: 1.0 (2026-10-27, P3-B S3 — instrumentação E08–E10)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S3, autorização expressa de Fabrício; harness dispensado sob H-A
              só para a S3; ledger 20261027221757 `5278_instrument_set_slot_lock`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo enviado (md5).
              LIVE_S3_90 bloco A 7/7; bloco B v1.1 6/6. Troca de reserva no mesmo
              evento não exercitada; concorrência e desempenho não medidos. README §30.8–§30.10.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5130 (LIVE = canônico: md5(prosrc) 782a551d7c3af03e74a56020802432d5, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §7.2, §20 (W3), §30 (S3).

Diff mínimo: o corpo é o da base, byte a byte, mais as linhas marcadas com
"-- P3B-S3" (só begin/add_item/end e o necessário para elas). Removidas essas linhas e
trocado o delimitador $fn$ → $$, o corpo volta a ter o md5 acima
(static_check_p3b_s3.py). Assinatura, retorno, SET, mensagens, códigos de erro, ordem de
travas e permissões inalterados (REVOKE/GRANT originais reaplicados de forma idempotente).

Evento POCKETS_LOCKED ou POCKETS_UNLOCKED (lote atômico, até 500 bolsos — teto da 5130):
  · 1 item POCKET/LOCKED (destino = bolso) ou POCKET/UNLOCKED (origem = bolso) por bolso cujo
    estado muda de fato — mesmo predicado do UPDATE (locked IS DISTINCT FROM p_locked);
  · bolsos já no estado pedido não geram item; nenhum bolso mudando → nenhum evento (C-206).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5278: aplique a 5268 antes';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) is distinct from '782a551d7c3af03e74a56020802432d5' then
    raise exception 'PRECHECK 5278: função no LIVE diverge da base 5130 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.set_slot_lock(
    p_slot_ids UUID[],
    p_locked   BOOLEAN
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
    v_raw_count    INTEGER;
    v_ids          UUID[];
    v_input_count  INTEGER;
    v_found_count  INTEGER;
    v_layout_count INTEGER;
    v_layout_id    UUID;
    v_updated      INTEGER;
    r              RECORD;  -- P3B-S3
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


    IF p_locked IS NULL THEN
        RAISE EXCEPTION 'p_locked não pode ser NULL';
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

    -- E10: um item POCKET por bolso que muda de estado (mesmo predicado do UPDATE → itens =  -- P3B-S3
    -- linhas alteradas). Fixar = destino; desfixar = origem. Nenhuma mudança → nenhum evento.  -- P3B-S3
    PERFORM public.binder_activity_begin(v_layout_id, CASE WHEN p_locked THEN 'POCKETS_LOCKED' ELSE 'POCKETS_UNLOCKED' END, 'FICHARIO');  -- P3B-S3
    FOR r IN  -- P3B-S3
        SELECT s.id  -- P3B-S3
          FROM public.collection_layout_slot s  -- P3B-S3
          JOIN public.collection_layout_page p ON p.id = s.page_id  -- P3B-S3
         WHERE s.id = ANY (v_ids)  -- P3B-S3
           AND s.locked IS DISTINCT FROM p_locked  -- P3B-S3
         ORDER BY p.page_number, s.row_index, s.column_index  -- P3B-S3
    LOOP  -- P3B-S3
        PERFORM public.binder_activity_add_item('POCKET', CASE WHEN p_locked THEN 'LOCKED' ELSE 'UNLOCKED' END, NULL, NULL,  -- P3B-S3
                                                CASE WHEN p_locked THEN NULL ELSE r.id END, CASE WHEN p_locked THEN r.id END);  -- P3B-S3
    END LOOP;  -- P3B-S3
  -- P3B-S3
    UPDATE public.collection_layout_slot
       SET locked = p_locked
     WHERE id = ANY (v_ids)
       AND locked IS DISTINCT FROM p_locked;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    PERFORM public.binder_activity_end();  -- P3B-S3
    RETURN v_updated;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.set_slot_lock(uuid[], boolean)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_slot_lock(uuid[], boolean)
    TO authenticated;

commit;
