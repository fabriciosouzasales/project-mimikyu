/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5126 - Create remove_layout_page()
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Remove uma Page. RECUSA se qualquer Slot dela tiver Slot Assignment ou
Expected Content, ou se a Page tiver Layout Region.

C-39, literal: "Remover uma Page exige resolver previamente qualquer
dependência persistente existente em seus Slots (Slot Assignments,
Expected Content, Layout Region) — não há remoção automática
silenciosa de conteúdo."

As três checagens são explícitas e produzem mensagens distintas, para
que o produto possa orientar o usuário sobre o que exatamente resolver.
Estruturalmente as FKs já garantiriam o bloqueio (RESTRICT em 5113/
5115/5119), mas o erro nu de constraint não diz O QUE resolver.

Sem dependências, o DELETE da Page cascateia nos Slots (FK slot ->
page ON DELETE CASCADE, Query 5110). Esse CASCADE só alcança
ESTRUTURA vazia — conteúdo já foi provado inexistente acima.

Após remover, renumera as Pages seguintes para manter contiguidade
1..N (DP-02). A UNIQUE DEFERRABLE (Query 5108) permite o UPDATE em
bloco sem colisão intermediária.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- Tabelas 5108/5110/5113/5115/5119.

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§3 POST-LOCK REVALIDATION + §4 NON-ENUMERATION.
Dois defeitos reais na v1.0:
(a) `page_number` era lido ANTES do lock e reutilizado depois dele
    para renumerar. Uma remoção concorrente de outra Page do mesmo
    Layout mudava a numeração enquanto esperávamos, e a renumeração
    saía do snapshot antigo — corrupção silenciosa da ordem de Pages.
(b) o resolve inicial da Page não era owner-scoped: Page inexistente e
    Page de outro Owner percorriam ramos distintos antes de o helper
    ser chamado.
Ordem obrigatória agora, e em toda a Foundation:
OWNER-FILTERED RESOLVE -> COLLECTION LOCK -> LAYOUT LOCK ->
PAGE LOCK -> RE-READ/REVALIDATE -> CALCULAR -> MUTAR.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, na rodada
`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`. Validada por
`5818` v7.2 (196/196 runtime, FAIL 0) e por `5819` v3.0 (22/22 HEALTHY,
nenhum indice novo criado). Ledger e evidencia completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). A copia historica permanece em
`database/proposals/2026-09-06-binder-layout-foundation/`, junto com os
harnesses `5818`/`5819`, o roteiro `CONCURRENCY-PROOF-C04-R18.sql` e o
`README.md` da rodada — esses quatro NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
(`BEGIN;` .. `COMMIT;`) permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

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
