/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5280 - P3-B S4 · Histórico do Fichário — instrumentação E13 (Páginas adicionadas)
              add_layout_page(uuid)
Versão......: 1.0 (2026-10-27, P3-B S4 — instrumentação E11–E15)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5125 (md5(prosrc) LIVE cdcf89d386ed87ab69b8a17496170017, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §5.2, §7.2 (R5), §20 (W3), §31 (S4).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S4". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s4.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento PAGES_ADDED (uma página por chamada; a interface chama N vezes → N eventos, I7/D6):
  · 1 item PAGE/PAGE_ADDED com destino = número da página nova.
  · Chamada embutida (insert_my_binder_gap; futura E16 na S6): o begin só aumenta a
    profundidade e o item entra no evento externo (R5), sem evento próprio.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5280: dependência ausente (binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb))';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.add_layout_page(uuid)')) is distinct from 'cdcf89d386ed87ab69b8a17496170017' then
    raise exception 'PRECHECK 5280: função no LIVE diverge da base 5125 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.add_layout_page(
    p_layout_id UUID
)
RETURNS TABLE (
    id           UUID,
    layout_id    UUID,
    page_number  INTEGER,
    slots_created INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
    v_grid_rows    INTEGER;
    v_grid_columns INTEGER;
    v_next_number  INTEGER;
    v_page_id      UUID;
    v_slot_count   INTEGER;
BEGIN
    PERFORM public.assert_collection_layout_mutable(p_layout_id);
    PERFORM public.binder_activity_begin(p_layout_id, 'PAGES_ADDED', 'FICHARIO');  -- P3B-S4

    SELECT l.grid_rows, l.grid_columns
      INTO v_grid_rows, v_grid_columns
      FROM public.collection_layout l
     WHERE l.id = p_layout_id;

    SELECT COALESCE(max(p.page_number), 0) + 1
      INTO v_next_number
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    INSERT INTO public.collection_layout_page AS clp
        (layout_id, page_number)
    VALUES
        (p_layout_id, v_next_number)
    RETURNING clp.id INTO v_page_id;

    INSERT INTO public.collection_layout_slot
        (page_id, row_index, column_index)
    SELECT v_page_id, r, c
      FROM generate_series(1, v_grid_rows)    AS r
     CROSS JOIN generate_series(1, v_grid_columns) AS c;

    GET DIAGNOSTICS v_slot_count = ROW_COUNT;

    IF v_slot_count <> v_grid_rows * v_grid_columns THEN
        RAISE EXCEPTION
            'inconsistência estrutural: % Slots criados, esperado %',
            v_slot_count, v_grid_rows * v_grid_columns;
    END IF;

    -- E13: página gravada → item de destino (I-10; W1 recalcula o teto em PAGE_ADDED).  -- P3B-S4
    PERFORM public.binder_activity_add_item('PAGE', 'PAGE_ADDED', NULL, NULL, NULL, NULL, NULL, v_next_number);  -- P3B-S4
    RETURN QUERY
    SELECT p.id, p.layout_id, p.page_number, v_slot_count
      FROM public.collection_layout_page p
     WHERE p.id = v_page_id;
    PERFORM public.binder_activity_end();  -- P3B-S4
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.add_layout_page(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_layout_page(uuid)
    TO authenticated;

commit;
