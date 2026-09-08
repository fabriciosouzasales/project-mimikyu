/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5134 - Create merge_layout_region()
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria uma Layout Region (Merge) sobre um retângulo de Slots de uma
Page. Recebe o bounding box diretamente (DP-04) — não recebe lista de
Slots, porque a representação É o retângulo.

CONCORRÊNCIA (exigência explícita do MATERIALITY AUDIT): locka a PAGE
FOR UPDATE **antes** de validar overlap/Lock. O trigger 5121 fecha o
caminho privilegiado, mas só o lock fecha a corrida — duas transações
simultâneas poderiam, cada uma, não enxergar a Region da outra.
Ordem determinística: Layout (via assert) -> Page -> validações.

Validações (todas também garantidas pelo trigger 5121, aqui
antecipadas para mensagem de domínio legível):
- retângulo cabe no grid do Layout;
- mínimo 2 Slots (CHECK da Query 5119);
- nenhum overlap com outra Region da mesma Page;
- nenhum Slot do bounding box locked (C-43/C-46).

Criar a Region NÃO altera Slot Assignments nem Expected Content
(C-46, literal) — esta RPC não escreve em nenhuma das duas tabelas.

Uma Region NUNCA atravessa Pages (C-46): o bounding box é sempre
relativo a UMA page_id.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_region (Query 5119).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§3 POST-LOCK REVALIDATION + §4 NON-ENUMERATION + §8 REGION.
Resolve da Page passa a ser owner-scoped. O grid do Layout e o estado
de overlap/lock são lidos DEPOIS do lock da Page, não antes. A defesa
estrutural real do bounding box passa a viver no trigger 5121 v2.0
(que agora também lockeia a Page e cobre DELETE); esta RPC mantém as
mesmas validações como PRECHECK AMIGÁVEL, para devolver mensagens de
domínio em vez de erro de trigger.

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

CREATE OR REPLACE FUNCTION public.merge_layout_region(
    p_page_id     UUID,
    p_top_row     INTEGER,
    p_left_column INTEGER,
    p_height      INTEGER,
    p_width       INTEGER
)
RETURNS TABLE (
    id          UUID,
    page_id     UUID,
    top_row     INTEGER,
    left_column INTEGER,
    height      INTEGER,
    width       INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_layout_id    UUID;
    v_grid_rows    INTEGER;
    v_grid_columns INTEGER;
    v_locked_count INTEGER;
    v_new_id       UUID;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED da Page.
    SELECT p.layout_id INTO v_layout_id
      FROM public.collection_layout_page p
      JOIN public.collection_layout l ON l.id = p.layout_id
      JOIN public.collection c        ON c.id = l.collection_id
     WHERE p.id = p_page_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    -- 2) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE.
    BEGIN
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout page not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 3) PAGE LOCK antes de qualquer leitura que decide.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.id = p_page_id
        AND p.layout_id = v_layout_id
      FOR UPDATE;

    -- 4) REVALIDAÇÃO PÓS-LOCK da Page.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.id = p_page_id
        AND p.layout_id = v_layout_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    IF p_height IS NULL OR p_width IS NULL
       OR p_top_row IS NULL OR p_left_column IS NULL THEN
        RAISE EXCEPTION 'bounding box incompleto';
    END IF;

    IF p_height * p_width < 2 THEN
        RAISE EXCEPTION
            'Layout Region exige no mínimo 2 Slots — uma região 1x1 não é mesclagem';
    END IF;

    -- 5) Grid lido PÓS-LOCK.
    SELECT l.grid_rows, l.grid_columns
      INTO v_grid_rows, v_grid_columns
      FROM public.collection_layout l
     WHERE l.id = v_layout_id;

    IF p_top_row < 1 OR p_left_column < 1
       OR p_top_row + p_height - 1 > v_grid_rows
       OR p_left_column + p_width - 1 > v_grid_columns THEN
        RAISE EXCEPTION
            'Layout Region excede os limites do grid % x %', v_grid_rows, v_grid_columns;
    END IF;

    -- 6) Overlap lido PÓS-LOCK.
    IF EXISTS (
        SELECT 1
        FROM public.collection_layout_region r
        WHERE r.page_id = p_page_id
          AND p_top_row     <  r.top_row     + r.height
          AND r.top_row     <  p_top_row     + p_height
          AND p_left_column <  r.left_column + r.width
          AND r.left_column <  p_left_column + p_width
    ) THEN
        RAISE EXCEPTION
            'Layout Region sobrepõe outra Region da mesma Page — um Slot participa de no máximo uma Region ativa';
    END IF;

    -- 7) Lock dos Slots do bounding box, lido PÓS-LOCK.
    SELECT count(*) INTO v_locked_count
      FROM public.collection_layout_slot s
     WHERE s.page_id = p_page_id
       AND s.locked
       AND s.row_index    BETWEEN p_top_row     AND p_top_row     + p_height - 1
       AND s.column_index BETWEEN p_left_column AND p_left_column + p_width  - 1;

    IF v_locked_count > 0 THEN
        RAISE EXCEPTION
            'Merge bloqueado: % Slot(s) da região estão locked', v_locked_count;
    END IF;

    -- 8) O trigger 5121 v2.0 revalida tudo estruturalmente no INSERT.
    INSERT INTO public.collection_layout_region AS r
        (page_id, top_row, left_column, height, width)
    VALUES
        (p_page_id, p_top_row, p_left_column, p_height, p_width)
    RETURNING r.id INTO v_new_id;

    RETURN QUERY
    SELECT r.id, r.page_id, r.top_row, r.left_column, r.height, r.width
      FROM public.collection_layout_region r
     WHERE r.id = v_new_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.merge_layout_region(uuid, integer, integer, integer, integer)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merge_layout_region(uuid, integer, integer, integer, integer)
    TO authenticated;

COMMIT;
