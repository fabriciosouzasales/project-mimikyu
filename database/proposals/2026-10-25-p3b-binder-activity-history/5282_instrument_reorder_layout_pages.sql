/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5282 - P3-B S4 · Histórico do Fichário — instrumentação E15 (Páginas reordenadas)
              reorder_layout_pages(uuid, uuid[])
Versão......: 1.0 (2026-10-27, P3-B S4 — instrumentação E11–E15)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5127 (md5(prosrc) LIVE 39b8b80f3f3cb0f0a0f88a98352a52c9, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §5.2, §7.2 (R5), §20 (W3), §31 (S4).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S4". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s4.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento PAGES_REORDERED (lote atômico de todas as páginas):
  · 1 item PAGE/PAGE_RENUMBERED por página que muda de número (origem antigo → destino novo);
  · ordem igual à atual → nenhum item, nenhum evento (C-206).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5282: dependência ausente (binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb))';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.reorder_layout_pages(uuid, uuid[])')) is distinct from '39b8b80f3f3cb0f0a0f88a98352a52c9' then
    raise exception 'PRECHECK 5282: função no LIVE diverge da base 5127 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.reorder_layout_pages(
    p_layout_id        UUID,
    p_page_ids_ordered UUID[]
)
RETURNS TABLE (
    id          UUID,
    page_number INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
    v_total_pages    INTEGER;
    v_input_count    INTEGER;
    v_distinct_count INTEGER;
    v_belong_count   INTEGER;
    r                RECORD;  -- P3B-S4
BEGIN
    -- COLLECTION LOCK -> LAYOUT LOCK + ACTIVE (helper 5122).
    PERFORM public.assert_collection_layout_mutable(p_layout_id);

    IF p_page_ids_ordered IS NULL THEN
        RAISE EXCEPTION 'p_page_ids_ordered não pode ser vazio';
    END IF;

    -- (2b) §1 CORREÇÃO CONSOLIDADA 03 — CARDINALIDADE REAL, O(1).
    -- cardinality() conta TODOS os elementos em qualquer número de
    -- dimensões; array_length(x,1) contaria apenas a primeira e
    -- permitiria bypass multidimensional do short-circuit.
    v_input_count := cardinality(p_page_ids_ordered);

    IF v_input_count = 0 THEN
        RAISE EXCEPTION 'p_page_ids_ordered não pode ser vazio';
    END IF;

    -- (2c) CONTRATO DE FORMA: somente array unidimensional. Avaliado
    -- ANTES de qualquer unnest/DISTINCT.
    IF array_ndims(p_page_ids_ordered) <> 1 THEN
        RAISE EXCEPTION
            'p_page_ids_ordered deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_page_ids_ordered);
    END IF;

    -- (4) Total de Pages, com o Layout JÁ LOCKADO pelo helper acima.
    SELECT count(*) INTO v_total_pages
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    -- (5) SHORT-CIRCUIT (§2 CORREÇÃO CONSOLIDADA 02): rejeita ANTES de
    -- qualquer unnest/DISTINCT. Nenhum trabalho proporcional ao payload
    -- é executado por uma chamada que já se sabe inválida.
    IF v_input_count <> v_total_pages THEN
        RAISE EXCEPTION
            'p_page_ids_ordered deve conter todas as % Pages do Layout (recebidas %)',
            v_total_pages, v_input_count;
    END IF;

    -- (6) SOMENTE DEPOIS do short-circuit: unnest + DISTINCT.
    SELECT count(DISTINCT x) INTO v_distinct_count
      FROM unnest(p_page_ids_ordered) AS x;

    -- (7) Duplicados.
    IF v_distinct_count <> v_input_count THEN
        RAISE EXCEPTION 'p_page_ids_ordered contém ids duplicados';
    END IF;

    -- (8) PAGE LOCK em ordem determinística.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.layout_id = p_layout_id
      ORDER BY p.id
      FOR UPDATE;

    -- (9) REVALIDAÇÃO PÓS-LOCK — preservada integralmente da v2.0.
    -- O total é RECONTADO depois de esperar o lock: a leitura do
    -- passo (4) serviu apenas para o short-circuit e NUNCA é reusada
    -- como decisão final.
    SELECT count(*) INTO v_total_pages
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    IF v_input_count <> v_total_pages THEN
        RAISE EXCEPTION
            'p_page_ids_ordered deve conter todas as % Pages do Layout (recebidas %)',
            v_total_pages, v_input_count;
    END IF;

    SELECT count(*) INTO v_belong_count
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id
       AND p.id = ANY (p_page_ids_ordered);

    IF v_belong_count <> v_input_count THEN
        RAISE EXCEPTION
            'p_page_ids_ordered contém Page(s) que não pertencem a este Layout';
    END IF;

    -- E15: um item por página cuja numeração muda; ordem idêntica → nenhum item, nenhum evento.  -- P3B-S4
    PERFORM public.binder_activity_begin(p_layout_id, 'PAGES_REORDERED', 'FICHARIO');  -- P3B-S4
    FOR r IN  -- P3B-S4
        SELECT p.page_number AS old_n, u.ord::integer AS new_n  -- P3B-S4
          FROM unnest(p_page_ids_ordered) WITH ORDINALITY AS u(page_id, ord)  -- P3B-S4
          JOIN public.collection_layout_page p ON p.id = u.page_id AND p.layout_id = p_layout_id  -- P3B-S4
         WHERE p.page_number <> u.ord  -- P3B-S4
         ORDER BY u.ord  -- P3B-S4
    LOOP  -- P3B-S4
        PERFORM public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', NULL, NULL, NULL, NULL, r.old_n, r.new_n);  -- P3B-S4
    END LOOP;  -- P3B-S4
  -- P3B-S4
    UPDATE public.collection_layout_page p
       SET page_number = src.new_number
      FROM (
            SELECT u.page_id, u.ord AS new_number
              FROM unnest(p_page_ids_ordered) WITH ORDINALITY AS u(page_id, ord)
           ) AS src
     WHERE p.id = src.page_id
       AND p.layout_id = p_layout_id;

    RETURN QUERY
    SELECT p.id, p.page_number
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id
     ORDER BY p.page_number;
    PERFORM public.binder_activity_end();  -- P3B-S4
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.reorder_layout_pages(uuid, uuid[])
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reorder_layout_pages(uuid, uuid[])
    TO authenticated;

commit;
