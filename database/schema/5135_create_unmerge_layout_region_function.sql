/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5135 - Create unmerge_layout_region()
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Remove uma Layout Region (Unmerge). Os Slots envolvidos NUNCA são
destruídos, recriados nem têm identidade alterada (C-46) — a Region é
uma camada visual sobre Slots que continuam existindo.

Remover a Region NÃO altera Slot Assignments nem Expected Content
(C-46, literal). Esta RPC não escreve em nenhuma das duas tabelas.

LOCK (C-43/C-46): se qualquer Slot do bounding box estiver locked, o
Unmerge é REJEITADO — "Merge e Unmerge ficam bloqueados" é simétrico,
não vale só para criar. O trigger 5121 não cobre DELETE (ver seu
cabeçalho); por isso esta verificação aqui é a barreira efetiva do
Unmerge, e o harness 5818 a exercita explicitamente.

CONCORRÊNCIA: locka a Page FOR UPDATE antes de validar, mesma ordem
determinística de 5134 (Layout -> Page -> validações).

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_region (Query 5119).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§3 POST-LOCK REVALIDATION + §4 NON-ENUMERATION + §8 REGION.
Resolve da Region passa a ser owner-scoped. A GEOMETRIA da Region é
RELIDA depois do lock da Page — a v1.0 lia top_row/left_column/height/
width antes do lock e usava esse snapshot para decidir se havia Slot
locked na área. Com o trigger 5121 v2.0 cobrindo também DELETE, o
Unmerge deixa de depender exclusivamente desta RPC; as validações aqui
permanecem como precheck amigável.

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

CREATE OR REPLACE FUNCTION public.unmerge_layout_region(
    p_region_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_page_id      UUID;
    v_layout_id    UUID;
    v_top_row      INTEGER;
    v_left_column  INTEGER;
    v_height       INTEGER;
    v_width        INTEGER;
    v_locked_count INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED da Region (apenas page_id/layout_id; a
    -- geometria será relida pós-lock).
    SELECT r.page_id, p.layout_id
      INTO v_page_id, v_layout_id
      FROM public.collection_layout_region r
      JOIN public.collection_layout_page p ON p.id = r.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE r.id = p_region_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout region not found or not owned by caller';
    END IF;

    -- 2) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE.
    BEGIN
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout region not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 3) PAGE LOCK.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.id = v_page_id
        AND p.layout_id = v_layout_id
      FOR UPDATE;

    -- 4) REVALIDAÇÃO PÓS-LOCK: a Region ainda existe e a GEOMETRIA é
    -- relida agora, nunca reaproveitada do snapshot anterior.
    SELECT r.top_row, r.left_column, r.height, r.width, r.page_id
      INTO v_top_row, v_left_column, v_height, v_width, v_page_id
      FROM public.collection_layout_region r
     WHERE r.id = p_region_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout region not found or not owned by caller';
    END IF;

    -- 5) Lock dos Slots do bounding box, lido PÓS-LOCK.
    SELECT count(*) INTO v_locked_count
      FROM public.collection_layout_slot s
     WHERE s.page_id = v_page_id
       AND s.locked
       AND s.row_index    BETWEEN v_top_row     AND v_top_row     + v_height - 1
       AND s.column_index BETWEEN v_left_column AND v_left_column + v_width  - 1;

    IF v_locked_count > 0 THEN
        RAISE EXCEPTION
            'Unmerge bloqueado: % Slot(s) da região estão locked', v_locked_count;
    END IF;

    -- 6) O trigger 5121 v2.0 revalida o DELETE estruturalmente.
    DELETE FROM public.collection_layout_region
     WHERE id = p_region_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.unmerge_layout_region(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unmerge_layout_region(uuid)
    TO authenticated;

COMMIT;
