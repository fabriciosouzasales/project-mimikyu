/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5285 - P3-B S4 · HOTFIX da 5281 — colisão de nome em remove_layout_page(uuid, integer)
Versão......: 1.0 (2026-10-27, P3-B S4 — hotfix)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5281 (md5(prosrc) LIVE 5ea978d582f055fb8690f9974a2bea2f).
Autoridade..: README da proposta §31.10.

Defeito: a 5281 declarou a variável RECORD "r", que colide com o alias "r" de
collection_layout_region na checagem de imagens em 2 bolsos (corpo da 5235/5260). O PL/pgSQL
resolve "r.page_id" como campo da variável não atribuída → erro 55000 "record r is not assigned
yet" em toda chamada (inclusive Desfazer espaço com página nova, via close_my_binder_gap).

Correção: só a variável do laço de renumeração muda de nome (r → v_renum), nas 3 linhas que a
5281 acrescentou. Nenhuma outra linha, assinatura, retorno, SET, mensagem, trava ou permissão
muda; o alias "r" de collection_layout_region volta a ser resolvido como alias de tabela.
A 5281 aplicada permanece no ledger como está.
================================================================
*/

begin;

do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.remove_layout_page(uuid, integer)')) is distinct from '5ea978d582f055fb8690f9974a2bea2f' then
    raise exception 'PRECHECK 5285: remove_layout_page(uuid, integer) no LIVE diverge da 5281 (md5)';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where name = '5281_instrument_remove_layout_page') then
    raise exception 'PRECHECK 5285: 5281 ausente do ledger';
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
    v_renum       RECORD;  -- P3B-S4
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
    FOR v_renum IN  -- P3B-S4
        SELECT p.page_number AS n  -- P3B-S4
          FROM public.collection_layout_page p  -- P3B-S4
         WHERE p.layout_id = v_layout_id AND p.page_number > v_page_number  -- P3B-S4
         ORDER BY p.page_number  -- P3B-S4
    LOOP  -- P3B-S4
        PERFORM public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', NULL, NULL, NULL, NULL, v_renum.n, v_renum.n - 1);  -- P3B-S4
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
