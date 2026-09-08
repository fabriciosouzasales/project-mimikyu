/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5121 - Create Collection Layout Region Integrity Trigger
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Garante, em BEFORE INSERT OR UPDATE de collection_layout_region, as
três invariantes de C-46 que os CHECKs de coluna (Query 5119) não
alcançam sozinhos:

 1. BOUNDS — o retângulo cabe inteiro no grid do Layout:
      top_row     + height - 1 <= grid_rows
      left_column + width  - 1 <= grid_columns
    (o limite inferior >= 1 já é CHECK declarativo em 5119.)

 2. OVERLAP — nenhuma outra Region ATIVA da MESMA Page intersecta.
    Dois retângulos NÃO se sobrepõem sse forem disjuntos em pelo
    menos um eixo; a condição de sobreposição é a negação disso:
        a.top     <  b.top  + b.height  AND
        b.top     <  a.top  + a.height  AND
        a.left    <  b.left + b.width   AND
        b.left    <  a.left + a.width
    Em UPDATE, a própria linha é excluída da comparação (id <> NEW.id).
    "Um Slot participa de no máximo uma Layout Region ativa" (C-46) é
    consequência direta de não haver overlap.

 3. LOCK — nenhum Slot dentro do bounding box pode estar locked
    (C-43/C-46: "se qualquer Slot necessário à operação estiver
    locked, Merge e Unmerge ficam bloqueados").

CONCORRÊNCIA: este trigger é a garantia estrutural, mas NÃO substitui
o lock de Page. Duas transações simultâneas poderiam, cada uma, não
enxergar a Region da outra e ambas passarem. Por isso as RPCs
merge_layout_region()/unmerge_layout_region() (Queries 5134/5135)
OBRIGATORIAMENTE lockam a Page FOR UPDATE **antes** de validar — o
trigger fecha o caminho privilegiado, a RPC fecha a corrida.

Este trigger NÃO cobre DELETE. Unmerge é sempre operação de Layout e
passa pela RPC 5135, que checa Lock antes de apagar. Cobrir DELETE
aqui bloquearia também o caso legítimo de limpeza estrutural.

Dependências:
- public.collection_layout_region (Query 5119).
- public.collection_layout_page / _layout / _slot.

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§8 REGION — LOCK + DELETE + CONCORRÊNCIA.
A v1.0 era insuficiente como defesa estrutural. Três correções:

(a) COBERTURA DE DELETE. O trigger disparava apenas em
    INSERT/UPDATE, portanto o Unmerge dependia EXCLUSIVAMENTE da RPC
    5135: um DELETE privilegiado apagava uma Region cujos Slots
    estavam locked. Agora o trigger é BEFORE INSERT OR UPDATE OR
    DELETE; no ramo DELETE usa OLD, lockeia OLD.page_id e rejeita se
    houver Slot locked no bounding box OLD.

(b) PAGE LOCK DENTRO DO TRIGGER. A validação de overlap só é correta
    se serializada. A v1.0 dependia do lock feito pela RPC — logo o
    caminho privilegiado não tinha serialização nenhuma. O trigger
    passa a adquirir `collection_layout_page ... FOR UPDATE` ANTES de
    validar bounds/overlap/lock, e relê o estado depois de esperar.

(c) page_id IMUTÁVEL e geometria OLD considerada no UPDATE. Sem isso,
    um UPDATE privilegiado poderia "mover" a Region para longe de um
    Slot locked (ou para outra Page) e escapar do enforcement.

Sem GiST, sem EXCLUDE, sem extensão — a serialização vem do lock da
Page, exatamente como decidido em DP-04.

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

CREATE OR REPLACE FUNCTION public.enforce_collection_layout_region_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_grid_rows    INTEGER;
    v_grid_columns INTEGER;
    v_locked_count INTEGER;
BEGIN
    -- =========================================================
    -- RAMO DELETE — defesa estrutural do UNMERGE.
    -- =========================================================
    IF TG_OP = 'DELETE' THEN
        -- PAGE LOCK (geometria OLD) antes de qualquer leitura que decide.
        PERFORM 1
           FROM public.collection_layout_page p
          WHERE p.id = OLD.page_id
          FOR UPDATE;

        -- Leitura PÓS-LOCK do estado de Lock no bounding box OLD.
        SELECT count(*)
          INTO v_locked_count
          FROM public.collection_layout_slot s
         WHERE s.page_id = OLD.page_id
           AND s.locked
           AND s.row_index    BETWEEN OLD.top_row     AND OLD.top_row     + OLD.height - 1
           AND s.column_index BETWEEN OLD.left_column AND OLD.left_column + OLD.width  - 1;

        IF v_locked_count > 0 THEN
            RAISE EXCEPTION
                'Layout Region inclui % Slot(s) bloqueado(s) (locked) — Merge/Unmerge não permitido',
                v_locked_count;
        END IF;

        RETURN OLD;
    END IF;

    -- =========================================================
    -- RAMO INSERT / UPDATE
    -- =========================================================

    -- 0) page_id é IMUTÁVEL: não existe operação suportada de mover
    -- uma Region de Page. Sem isto, um UPDATE privilegiado escaparia
    -- do enforcement de Lock da Page original.
    IF TG_OP = 'UPDATE' AND NEW.page_id IS DISTINCT FROM OLD.page_id THEN
        RAISE EXCEPTION
            'page_id de uma Layout Region é IMUTÁVEL — faça Unmerge na Page atual e Merge na Page destino';
    END IF;

    -- 1) PAGE LOCK antes de validar. É isto que torna o trigger — e
    -- não a RPC — a defesa estrutural real também no caminho
    -- privilegiado.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.id = NEW.page_id
      FOR UPDATE;

    -- 2) BOUNDS contra o grid do Layout dono da Page (leitura PÓS-LOCK).
    SELECT l.grid_rows, l.grid_columns
      INTO v_grid_rows, v_grid_columns
      FROM public.collection_layout_page p
      JOIN public.collection_layout l ON l.id = p.layout_id
     WHERE p.id = NEW.page_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'page_id % não existe', NEW.page_id;
    END IF;

    IF NEW.top_row + NEW.height - 1 > v_grid_rows THEN
        RAISE EXCEPTION
            'Layout Region excede o grid: top_row % + height % ultrapassa grid_rows %',
            NEW.top_row, NEW.height, v_grid_rows;
    END IF;

    IF NEW.left_column + NEW.width - 1 > v_grid_columns THEN
        RAISE EXCEPTION
            'Layout Region excede o grid: left_column % + width % ultrapassa grid_columns %',
            NEW.left_column, NEW.width, v_grid_columns;
    END IF;

    -- 3) OVERLAP com outra Region da mesma Page (leitura PÓS-LOCK).
    IF EXISTS (
        SELECT 1
        FROM public.collection_layout_region r
        WHERE r.page_id = NEW.page_id
          AND r.id IS DISTINCT FROM NEW.id
          AND NEW.top_row     <  r.top_row     + r.height
          AND r.top_row       <  NEW.top_row   + NEW.height
          AND NEW.left_column <  r.left_column + r.width
          AND r.left_column   <  NEW.left_column + NEW.width
    ) THEN
        RAISE EXCEPTION
            'Layout Region sobrepõe outra Region da mesma Page — um Slot participa de no máximo uma Region ativa';
    END IF;

    -- 4) LOCK — nenhum Slot do bounding box NEW pode estar locked.
    SELECT count(*)
      INTO v_locked_count
      FROM public.collection_layout_slot s
     WHERE s.page_id = NEW.page_id
       AND s.locked
       AND s.row_index    BETWEEN NEW.top_row     AND NEW.top_row     + NEW.height - 1
       AND s.column_index BETWEEN NEW.left_column AND NEW.left_column + NEW.width  - 1;

    IF v_locked_count > 0 THEN
        RAISE EXCEPTION
            'Layout Region inclui % Slot(s) bloqueado(s) (locked) — Merge/Unmerge não permitido',
            v_locked_count;
    END IF;

    -- 5) UPDATE: a geometria OLD também é verificada. Um UPDATE não
    -- pode ser usado para "sair de cima" de um Slot locked.
    IF TG_OP = 'UPDATE' THEN
        SELECT count(*)
          INTO v_locked_count
          FROM public.collection_layout_slot s
         WHERE s.page_id = OLD.page_id
           AND s.locked
           AND s.row_index    BETWEEN OLD.top_row     AND OLD.top_row     + OLD.height - 1
           AND s.column_index BETWEEN OLD.left_column AND OLD.left_column + OLD.width  - 1;

        IF v_locked_count > 0 THEN
            RAISE EXCEPTION
                'Layout Region inclui % Slot(s) bloqueado(s) (locked) — Merge/Unmerge não permitido',
                v_locked_count;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_collection_layout_region_integrity()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_region_integrity
    BEFORE INSERT OR UPDATE OR DELETE ON public.collection_layout_region
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_region_integrity();

COMMIT;
