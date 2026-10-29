/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5281 - P3-B S4 · Histórico do Fichário — instrumentação E14 (Página removida)
              remove_layout_page(uuid, integer)  — o invólucro remove_layout_page(uuid) não muda (§7.2-3)
Versão......: 1.0 (2026-10-27, P3-B S4 — instrumentação E11–E15)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5260 (md5(prosrc) LIVE 4baf044d8df24aa957873fce2cf5529a, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §5.2, §7.2 (R5), §20 (W3), §31 (S4).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S4". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s4.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento PAGE_REMOVED (atômico; só página vazia — a função recusa cartas, reservas, regiões e imagens):
  · 1 item PAGE/PAGE_REMOVED (origem = número da página; detalhe com referências de espécie
    removidas, quando houver);
  · 1 item PAGE/PAGE_RENUMBERED por página posterior (origem n → destino n-1).
  · Embutida em close_my_binder_gap (E12): itens entram no evento GAP_CLOSED (R5).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5281: dependência ausente (binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb))';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.remove_layout_page(uuid, integer)')) is distinct from '4baf044d8df24aa957873fce2cf5529a' then
    raise exception 'PRECHECK 5281: função no LIVE diverge da base 5260 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.remove_layout_page(
    p_page_id                    UUID,
    p_confirm_species_references INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
    v_layout_id   UUID;
    v_page_number INTEGER;
    v_count       INTEGER;
    r             RECORD;  -- P3B-S4
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED (5235).
    SELECT p.layout_id
      INTO v_layout_id
      FROM public.collection_layout_page p
      JOIN public.collection_layout l ON l.id = p.layout_id
      JOIN public.collection c        ON c.id = l.collection_id
     WHERE p.id = p_page_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    -- 2) COLLECTION LOCK -> LAYOUT LOCK (helper 5122) + ACTIVE.
    BEGIN
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout page not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 3) PAGE LOCK.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.id = p_page_id
        AND p.layout_id = v_layout_id
      FOR UPDATE;

    -- 4) REVALIDAÇÃO PÓS-LOCK.
    SELECT p.page_number
      INTO v_page_number
      FROM public.collection_layout_page p
     WHERE p.id = p_page_id
       AND p.layout_id = v_layout_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    -- 5) Estado dos filhos (5235), lido pós-lock.
    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id = a.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % slot assignment(s) — remove them before deleting the page', v_count;
    END IF;

    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_expected_content e
      JOIN public.collection_layout_slot s ON s.id = e.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % expected content entr(y/ies) — clear them before deleting the page', v_count;
    END IF;

    SELECT count(*) INTO v_count
      FROM public.collection_layout_region r
     WHERE r.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % layout region(s) — unmerge them before deleting the page', v_count;
    END IF;

    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_image i
      JOIN public.collection_layout_slot s ON s.id = i.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % custom image(s) — remove them before deleting the page', v_count;
    END IF;

    -- 5b) 5260 (ajuste B): referências de espécie da proprietária atual exigem
    -- confirmação com a contagem exata; nunca são apagadas em silêncio.
    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_species_reference sr
      JOIN public.collection_layout_slot s ON s.id = sr.slot_id
      JOIN public.collection_layout l      ON l.id = sr.layout_id AND l.collection_id = sr.collection_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        IF p_confirm_species_references IS DISTINCT FROM v_count THEN
            RAISE EXCEPTION
                'page has % species reference(s) — confirm their removal before deleting the page', v_count
                USING HINT = 'SPECIES_REFERENCES_ON_PAGE:' || v_count;
        END IF;
    END IF;

    -- E14: itens de origem ANTES de apagar/renumerar (I-10). v_count = referências de espécie (5b).  -- P3B-S4
    PERFORM public.binder_activity_begin(v_layout_id, 'PAGE_REMOVED', 'FICHARIO');  -- P3B-S4
    PERFORM public.binder_activity_add_item('PAGE', 'PAGE_REMOVED', NULL, NULL, NULL, NULL, v_page_number, NULL,  -- P3B-S4
                                            CASE WHEN v_count > 0 THEN jsonb_build_object('species_references_removed', v_count) END);  -- P3B-S4
    FOR r IN  -- P3B-S4
        SELECT p.page_number AS n  -- P3B-S4
          FROM public.collection_layout_page p  -- P3B-S4
         WHERE p.layout_id = v_layout_id AND p.page_number > v_page_number  -- P3B-S4
         ORDER BY p.page_number  -- P3B-S4
    LOOP  -- P3B-S4
        PERFORM public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', NULL, NULL, NULL, NULL, r.n, r.n - 1);  -- P3B-S4
    END LOOP;  -- P3B-S4
  -- P3B-S4
    DELETE FROM public.collection_layout_slot_species_reference sr
     USING public.collection_layout_slot s
     WHERE s.id = sr.slot_id
       AND s.page_id = p_page_id;

    -- 6) MUTAÇÃO, com o page_number pós-lock (5235).
    DELETE FROM public.collection_layout_page
     WHERE id = p_page_id;

    UPDATE public.collection_layout_page
       SET page_number = page_number - 1
     WHERE layout_id   = v_layout_id
       AND page_number > v_page_number;
    PERFORM public.binder_activity_end();  -- P3B-S4
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.remove_layout_page(uuid, integer)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_layout_page(uuid, integer)
    TO authenticated;

commit;
