/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5286 - Fichário · remove_layout_page(uuid, integer): mínimo de páginas e bolso fixado
              (hardening da remoção segura de páginas)
Versão......: 1.0 (2026-10-27)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5285 (md5(prosrc) LIVE e482399664eeb4980436372b57cf378b).

Diff mínimo: o corpo é o da 5285, byte a byte, mais as linhas marcadas com "-- P3B-HARDEN".
Removidas essas linhas, o corpo volta ao md5 acima (static_check_p3b_s4_5286.py).
Assinatura, retorno, SECURITY DEFINER, search_path, ordem de travas, mensagens existentes,
confirmação de referências de espécie (5260), itens E14 (PAGE_REMOVED/PAGE_RENUMBERED) e
permissões ficam iguais. O invólucro remove_layout_page(uuid) não muda.

Duas recusas novas, sob a trava do fichário (5122), ANTES de qualquer exclusão ou item do
Histórico (nenhum evento em recusa):
  4b) 'layout has only N page(s) — a binder must keep at least one page'   (P0001)
  5a) 'page has N locked slot(s) — unlock them before deleting the page'   (P0001)

Referências de espécie de outra coleção (fichário compartilhado): SEM mudança. Só a
coleção proprietária grava referências (5258); as de outra coleção só existem como
resíduo invisível de uma proprietária anterior e a 5260 (ajuste B) decidiu que saem com
a página. Recusar por elas criaria página impossível de remover sem motivo visível.

Compatibilidade: close_my_binder_gap (5284) só remove a página que ela mesma acrescentou,
quando é a última, sem bolso fixado — e o fichário então tem ≥ 2 páginas; nenhuma das
novas recusas se aplica. insert_my_binder_gap não remove páginas.
================================================================
*/

begin;

do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.remove_layout_page(uuid, integer)')) is distinct from 'e482399664eeb4980436372b57cf378b' then
    raise exception 'PRECHECK 5286: remove_layout_page(uuid, integer) no LIVE diverge da 5285 (md5)';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where name = '5285_fix_remove_layout_page_variable_collision') then
    raise exception 'PRECHECK 5286: 5285 ausente do ledger';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.remove_layout_page(uuid)')) is distinct from '98736e42641bb8a592f2d8e4fd40fab1' then
    raise exception 'PRECHECK 5286: invólucro remove_layout_page(uuid) diverge (md5)';
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

    -- 4b) Mínimo de páginas: o fichário nunca fica sem página. Contado com o fichário já  -- P3B-HARDEN
    -- travado (5122) — toda criação/remoção/reordenação de página passa pela mesma trava.  -- P3B-HARDEN
    SELECT count(*) INTO v_count  -- P3B-HARDEN
      FROM public.collection_layout_page p  -- P3B-HARDEN
     WHERE p.layout_id = v_layout_id;  -- P3B-HARDEN
  -- P3B-HARDEN
    IF v_count <= 1 THEN  -- P3B-HARDEN
        RAISE EXCEPTION  -- P3B-HARDEN
            'layout has only % page(s) — a binder must keep at least one page', v_count;  -- P3B-HARDEN
    END IF;  -- P3B-HARDEN
  -- P3B-HARDEN
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
  -- P3B-HARDEN
    -- 5a) Bolso fixado: o cadeado é uma decisão do colecionador; a página não sai com ele.  -- P3B-HARDEN
    -- (a fixação passa pela mesma trava do fichário — 5130 → 5122).  -- P3B-HARDEN
    SELECT count(*) INTO v_count  -- P3B-HARDEN
      FROM public.collection_layout_slot s  -- P3B-HARDEN
     WHERE s.page_id = p_page_id  -- P3B-HARDEN
       AND s.locked;  -- P3B-HARDEN
  -- P3B-HARDEN
    IF v_count > 0 THEN  -- P3B-HARDEN
        RAISE EXCEPTION  -- P3B-HARDEN
            'page has % locked slot(s) — unlock them before deleting the page', v_count;  -- P3B-HARDEN
    END IF;  -- P3B-HARDEN

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
