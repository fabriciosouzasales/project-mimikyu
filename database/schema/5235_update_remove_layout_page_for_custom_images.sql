/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5235 - remove_layout_page(uuid): imagem personalizada conta
              como conteúdo da página (evolução da 5126, CREATE OR REPLACE)
              (P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01)
Versão......: 1.0 (2026-10-23)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-BINDER-CUSTOM-IMAGES-LIVE-APPLY-01, autorização expressa de
              Fabrício; ledger 20261023185359 `5235_update_remove_layout_page_for_custom_images`).
              Do `begin;` ao `commit;` byte a byte idêntica ao texto aplicado e
              ao arquivo da pasta database/proposals/2026-10-23-p2-binder-custom-images/
              (só este bloco Status difere). POST-1 13/13 PASS; baseline
              preservado (contagens e md5); harness 5852 NÃO EXECUTADO (cria
              dados — proibido no LIVE); prova funcional F1–F7 PENDENTE (sem
              prova comportamental).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Única mudança em relação à 5126 (LIVE): o passo 5 ganha uma quarta
contagem — bolsos da página com imagem personalizada — e recusa com a
mesma forma de mensagem das outras três. Sem ela, a FK RESTRICT da 5232
já impediria a remoção, mas com erro cru de FK; agora o erro é explicativo
e consistente. Assinatura, travas, ordem, grants e renumeração INALTERADOS
(diff do bloco executável = precheck + bloco "5235").

Como validar: Query 5852 (Seção 4).
Como reverter: reaplicar o bloco BEGIN..COMMIT de 5126.
================================================================
*/

BEGIN;

DO $pre$
BEGIN
    IF to_regclass('public.collection_layout_slot_image') IS NULL THEN
        RAISE EXCEPTION 'PRECHECK 5235: aplique 5232 antes';
    END IF;
END;
$pre$;

CREATE OR REPLACE FUNCTION public.remove_layout_page(
    p_page_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_layout_id   UUID;
    v_page_number INTEGER;
    v_count       INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED. Page inexistente e Page alheia caem no
    -- MESMO ramo — nenhum oráculo de existência.
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

    -- 4) REVALIDAÇÃO PÓS-LOCK — page_number é RELIDO AQUI, depois de
    -- adquirir o lock, e é este valor que a renumeração usa.
    SELECT p.page_number
      INTO v_page_number
      FROM public.collection_layout_page p
     WHERE p.id = p_page_id
       AND p.layout_id = v_layout_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    -- 5) Estado dos filhos, também lido pós-lock.
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

    -- 5235 (C-198): imagem personalizada também é conteúdo da página.
    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_image i
      JOIN public.collection_layout_slot s ON s.id = i.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % custom image(s) — remove them before deleting the page', v_count;
    END IF;

    -- 6) MUTAÇÃO, com o page_number pós-lock.
    DELETE FROM public.collection_layout_page
     WHERE id = p_page_id;

    UPDATE public.collection_layout_page
       SET page_number = page_number - 1
     WHERE layout_id   = v_layout_id
       AND page_number > v_page_number;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_layout_page(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_layout_page(uuid)
    TO authenticated;

COMMIT;
