/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5125 - Create add_layout_page()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria uma Page ao final do Layout E, NA MESMA TRANSAÇÃO, todos os
grid_rows × grid_columns Slots estruturais correspondentes.

C-39, literal: "Toda Page nasce estruturalmente completa: recebe, no
mesmo ato lógico de sua criação, todos os Slots estruturais
determinados pelo Grid Configuration do Layout. Não existe Page
estruturalmente parcial." Cliente NUNCA cria Slot diretamente — não há
GRANT de INSERT em collection_layout_slot para authenticated, e não
existe RPC de criação de Slot avulso.

Os Slots são gerados por produto cartesiano de generate_series — a
capacidade é SEMPRE derivada de grid_rows × grid_columns (C-40),
nunca lida de um campo persistido.

page_number = (maior existente) + 1, ou 1 se for a primeira. A
contiguidade 1..N é mantida por construção aqui e por 5126/5127 nas
demais operações. O lock de collection_layout FOR UPDATE vem de
assert_collection_layout_mutable() (Query 5122) e serializa
add/remove/reorder concorrentes do mesmo Layout — inclusive entre duas
abas do mesmo usuário.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_page (Query 5108).
- public.collection_layout_slot (Query 5110).

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
AS $$
DECLARE
    v_grid_rows    INTEGER;
    v_grid_columns INTEGER;
    v_next_number  INTEGER;
    v_page_id      UUID;
    v_slot_count   INTEGER;
BEGIN
    PERFORM public.assert_collection_layout_mutable(p_layout_id);

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

    RETURN QUERY
    SELECT p.id, p.layout_id, p.page_number, v_slot_count
      FROM public.collection_layout_page p
     WHERE p.id = v_page_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_layout_page(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_layout_page(uuid)
    TO authenticated;

COMMIT;
