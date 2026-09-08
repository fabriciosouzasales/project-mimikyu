/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5112 - Create Collection Layout Slot Grid Bounds Trigger
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Garante row_index <= grid_rows e column_index <= grid_columns do
Layout dono da Page do Slot (C-41: "row = 1..rows, column =
1..columns").

Por que trigger e não CHECK: o limite superior vive em
collection_layout, duas tabelas acima do Slot (slot -> page ->
layout). Um CHECK de coluna só enxerga a própria linha. Os limites
INFERIORES (>= 1) ficam como CHECK declarativo na Query 5110 — só o
teto precisa de trigger.

Escopo: BEFORE INSERT OR UPDATE. Cobre tanto a criação em massa pela
RPC 5125 quanto qualquer tentativa privilegiada de inserir Slot fora
do grid.

Dependências:
- public.collection_layout_slot (Query 5110).
- public.collection_layout_page (Query 5108).
- public.collection_layout (Query 5105).

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

CREATE OR REPLACE FUNCTION public.enforce_collection_layout_slot_grid_bounds()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_grid_rows    INTEGER;
    v_grid_columns INTEGER;
BEGIN
    SELECT l.grid_rows, l.grid_columns
      INTO v_grid_rows, v_grid_columns
      FROM public.collection_layout_page p
      JOIN public.collection_layout l ON l.id = p.layout_id
     WHERE p.id = NEW.page_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'page_id % não existe', NEW.page_id;
    END IF;

    IF NEW.row_index > v_grid_rows THEN
        RAISE EXCEPTION
            'row_index % excede grid_rows % do Layout', NEW.row_index, v_grid_rows;
    END IF;

    IF NEW.column_index > v_grid_columns THEN
        RAISE EXCEPTION
            'column_index % excede grid_columns % do Layout', NEW.column_index, v_grid_columns;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_collection_layout_slot_grid_bounds()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_slot_grid_bounds
    BEFORE INSERT OR UPDATE ON public.collection_layout_slot
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_slot_grid_bounds();

COMMIT;
