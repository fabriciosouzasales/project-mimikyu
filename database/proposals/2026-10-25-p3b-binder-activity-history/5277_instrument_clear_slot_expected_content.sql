/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5277 - P3-B S3 · Histórico do Fichário — instrumentação E09 (Reservas liberadas)
              clear_slot_expected_content(uuid[])
Versão......: 1.0 (2026-10-27, P3-B S3 — instrumentação E08–E10)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5129 (LIVE = canônico: md5(prosrc) d4e229d6db9196bf8caa738b5ba2e8b0, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §7.2, §20 (W3), §30 (S3).

Diff mínimo: o corpo é o da base, byte a byte, mais as linhas marcadas com
"-- P3B-S3" (só begin/add_item/end e o necessário para elas). Removidas essas linhas e
trocado o delimitador $fn$ → $$, o corpo volta a ter o md5 acima
(static_check_p3b_s3.py). Assinatura, retorno, SET, mensagens, códigos de erro, ordem de
travas e permissões inalterados (REVOKE/GRANT originais reaplicados de forma idempotente).

Evento RESERVATIONS_RELEASED (lote atômico, até 500 bolsos — teto da própria 5129):
  · 1 item RESERVATION/RELEASED por reserva efetivamente apagada (origem = bolso), lido sob as
    travas de bolso já adquiridas (mesmo predicado do DELETE → itens = linhas apagadas);
  · bolsos sem reserva não geram item; pedido sem nenhuma reserva não gera evento.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null then
    raise exception 'PRECHECK 5277: aplique 5268 e 5275 antes';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) is distinct from 'd4e229d6db9196bf8caa738b5ba2e8b0' then
    raise exception 'PRECHECK 5277: função no LIVE diverge da base 5129 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.clear_slot_expected_content(
    p_slot_ids UUID[]
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
    v_deleted      INTEGER;
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

    -- E09: itens de origem ANTES do DELETE (I-10), em ordem de página/linha/coluna.  -- P3B-S3
    -- Nenhuma reserva nos bolsos pedidos → nenhum item → nenhum evento.  -- P3B-S3
    PERFORM public.binder_activity_begin(v_layout_id, 'RESERVATIONS_RELEASED', 'FICHARIO');  -- P3B-S3
    FOR r IN  -- P3B-S3
        SELECT e.slot_id  -- P3B-S3
          FROM public.collection_layout_slot_expected_content e  -- P3B-S3
          JOIN public.collection_layout_slot s ON s.id = e.slot_id  -- P3B-S3
          JOIN public.collection_layout_page p ON p.id = s.page_id  -- P3B-S3
         WHERE e.slot_id = ANY (v_ids)  -- P3B-S3
         ORDER BY p.page_number, s.row_index, s.column_index  -- P3B-S3
    LOOP  -- P3B-S3
        PERFORM public.binder_activity_add_reservation_item('RELEASED', r.slot_id);  -- P3B-S3
    END LOOP;  -- P3B-S3
  -- P3B-S3
    DELETE FROM public.collection_layout_slot_expected_content
     WHERE slot_id = ANY (v_ids);

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    PERFORM public.binder_activity_end();  -- P3B-S3
    RETURN v_deleted;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.clear_slot_expected_content(uuid[])
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_slot_expected_content(uuid[])
    TO authenticated;

commit;
