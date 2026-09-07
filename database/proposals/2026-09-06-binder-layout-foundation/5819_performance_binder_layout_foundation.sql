/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5819 - Performance Binder / Layout Foundation
Versão......: 3.0
Status......: PROPOSTA — HARNESS EXECUTÁVEL COMPLETO, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (v1.0 staging inicial;
               v2.0 em ...-STAGING-HARNESS-COMPLETION-01 — os 12
               workloads materializados;
               v3.0 em ...-CONSOLIDATED-CORRECTION-01 —
               §16 W12-G3 completo e §17 higiene)

Descrição...:
Harness de PERFORMANCE da Binder/Layout Foundation. Executado APÓS o
harness funcional 5818 ter dado PASS.

MUDANÇA v1.0 -> v2.0: a v1.0 descrevia os workloads como contrato para
um gate futuro. Isso não atendia ao requisito de STAGING fail-closed e
foi corretamente classificado como achado material. Nesta versão os 12
workloads são SQL executável.

FIXTURE (congelada no MATERIALITY AUDIT):
    1 Collection · 1 Layout 4x4 · 100 Pages · 1600 Slots
    800 Assignments (metade dos Slots) · 400 Expected Content
    50 Layout Regions

REGRA DE OURO: **NENHUM ÍNDICE É CRIADO ANTES DA MEDIÇÃO.** A
Foundation nasce apenas com índices estruturais (PK/UNIQUE). Se o
plano mostrar `uq_collection_layout_slot_position` sendo usada para
lookup por page_id (leading prefix), esse é o resultado ESPERADO e
fica registrado como tal. Só um BLOCKER medido justificaria propor
índice novo — em rodada própria, nunca aqui.

CAPTURA DE PLANO: EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) via
EXECUTE ... INTO, materializado em TEMP TABLE, porque a integração
execute_sql devolve apenas o resultado do ÚLTIMO statement. Precedente
arquitetural: 5813/5815.

HONESTIDADE DE EVIDÊNCIA: para as 13 RPCs, o EXPLAIN externo mostra
apenas `Function Scan` — **INTERNAL PLAN VISIBILITY = NOT OBSERVABLE**.
As RPCs são medidas por tempo de parede (clock_timestamp) e o campo
`plan_visibility` é gravado como NOT OBSERVABLE. NENHUMA alegação é
feita sobre nós de scan internos.

CLASSIFICAÇÃO: HEALTHY / ATTENTION / BLOCKER, por limiares explícitos
declarados junto de cada workload (colunas thr_healthy_ms /
thr_blocker_ms), nunca por impressão.

ZERO RESÍDUO: BEGIN ... ROLLBACK. A fixture de 1600 Slots NUNCA é
commitada.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

SET LOCAL client_min_messages = WARNING;

CREATE TEMP TABLE _p (
    seq            SERIAL PRIMARY KEY,
    workload       TEXT NOT NULL,
    description    TEXT,
    exec_ms        NUMERIC,
    shared_hit     BIGINT,
    shared_read    BIGINT,
    rows_out       BIGINT,
    top_node       TEXT,
    plan_visibility TEXT NOT NULL DEFAULT 'OBSERVABLE',
    thr_healthy_ms NUMERIC,
    thr_blocker_ms NUMERIC,
    classification TEXT,
    note           TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _f (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;

-- Physical Cards fabricadas por ESTE harness, rotuladas. Impede que a
-- fixture toque em Physical Cards reais pré-existentes do Inventory do
-- owner (que poderiam estar não alocadas e seriam varridas por um
-- INSERT ... SELECT sem limite).
CREATE TEMP TABLE _pc (k TEXT NOT NULL, id UUID PRIMARY KEY) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp._classify(p_ms NUMERIC, p_h NUMERIC, p_b NUMERIC)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE
        WHEN p_ms IS NULL      THEN 'UNKNOWN'
        WHEN p_ms <= p_h       THEN 'HEALTHY'
        WHEN p_ms <= p_b       THEN 'ATTENTION'
        ELSE                        'BLOCKER'
    END;
$fn$;

-- Mede uma QUERY com plano observável.
CREATE OR REPLACE FUNCTION pg_temp._measure(
    p_workload TEXT, p_desc TEXT, p_sql TEXT,
    p_thr_healthy NUMERIC, p_thr_blocker NUMERIC, p_note TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_json JSON; v_ms NUMERIC; v_hit BIGINT; v_read BIGINT; v_rows BIGINT; v_node TEXT;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_sql INTO v_json;
    v_ms   := (v_json->0->>'Execution Time')::NUMERIC;
    v_hit  := COALESCE((v_json->0->'Plan'->>'Shared Hit Blocks')::BIGINT, 0);
    v_read := COALESCE((v_json->0->'Plan'->>'Shared Read Blocks')::BIGINT, 0);
    v_rows := COALESCE((v_json->0->'Plan'->>'Actual Rows')::BIGINT, 0);
    v_node := v_json->0->'Plan'->>'Node Type';

    INSERT INTO _p (workload, description, exec_ms, shared_hit, shared_read, rows_out,
                    top_node, plan_visibility, thr_healthy_ms, thr_blocker_ms, classification, note)
    VALUES (p_workload, p_desc, v_ms, v_hit, v_read, v_rows, v_node, 'OBSERVABLE',
            p_thr_healthy, p_thr_blocker, pg_temp._classify(v_ms, p_thr_healthy, p_thr_blocker), p_note);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO _p (workload, description, plan_visibility, thr_healthy_ms, thr_blocker_ms, classification, note)
    VALUES (p_workload, p_desc, 'ERROR', p_thr_healthy, p_thr_blocker, 'BLOCKER',
            'ERRO na medicao: ' || SQLSTATE || ' ' || left(SQLERRM, 200));
END; $fn$;

-- Mede uma RPC por tempo de parede. Plano interno NAO observavel.
CREATE OR REPLACE FUNCTION pg_temp._measure_rpc(
    p_workload TEXT, p_desc TEXT, p_sql TEXT,
    p_thr_healthy NUMERIC, p_thr_blocker NUMERIC, p_note TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_t0 TIMESTAMPTZ; v_ms NUMERIC;
BEGIN
    v_t0 := clock_timestamp();
    EXECUTE p_sql;
    v_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000.0;

    INSERT INTO _p (workload, description, exec_ms, plan_visibility,
                    thr_healthy_ms, thr_blocker_ms, classification, note)
    VALUES (p_workload, p_desc, v_ms, 'NOT OBSERVABLE (Function Scan externo)',
            p_thr_healthy, p_thr_blocker, pg_temp._classify(v_ms, p_thr_healthy, p_thr_blocker),
            COALESCE(p_note, 'RPC: INTERNAL PLAN VISIBILITY = NOT OBSERVABLE'));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO _p (workload, description, plan_visibility, thr_healthy_ms, thr_blocker_ms, classification, note)
    VALUES (p_workload, p_desc, 'ERROR', p_thr_healthy, p_thr_blocker, 'BLOCKER',
            'ERRO na medicao: ' || SQLSTATE || ' ' || left(SQLERRM, 200));
END; $fn$;

-- =================================================================
-- FIXTURE — 1 Collection / 1 Layout 4x4 / 100 Pages / 1600 Slots
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_lang UUID; v_game UUID; v_varA UUID; v_cardA UUID;
    v_inv UUID; v_sc UUID; v_coll UUID; v_layout UUID; v_page UUID;
    v_n INTEGER; i INTEGER;
BEGIN
    SELECT id INTO v_owner FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_lang  FROM public.language ORDER BY id LIMIT 1;
    SELECT cv.id, cv.card_id, ex.game_id INTO v_varA, v_cardA, v_game
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     ORDER BY cv.id LIMIT 1;

    IF v_owner IS NULL OR v_lang IS NULL OR v_varA IS NULL THEN
        RAISE EXCEPTION
          'FIXTURE ABORT — Catálogo mínimo ausente (owner=%, lang=%, varA=%). O harness NAO fabrica medicao artificial.',
          v_owner, v_lang, v_varA;
    END IF;

    INSERT INTO public.inventory (owner_user_id) VALUES (v_owner)
    ON CONFLICT (owner_user_id) DO NOTHING;
    SELECT id INTO v_inv FROM public.inventory WHERE owner_user_id = v_owner;

    INSERT INTO public.storage_container (inventory_id, name)
    VALUES (v_inv, '__5819_sc__') RETURNING id INTO v_sc;

    INSERT INTO public.collection
        (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    VALUES (v_owner, v_game, v_sc, '__5819_coll__', 'OPEN_CURATION', 'NONE')
    RETURNING id INTO v_coll;

    INSERT INTO public.collection_layout (collection_id, grid_rows, grid_columns)
    VALUES (v_coll, 4, 4) RETURNING id INTO v_layout;

    INSERT INTO _f VALUES ('owner',v_owner),('lang',v_lang),('game',v_game),
        ('varA',v_varA),('cardA',v_cardA),('inv',v_inv),('sc',v_sc),
        ('coll',v_coll),('layout',v_layout);

    -- 100 Pages + 1600 Slots. Inserção em massa (a RPC 5125 seria 100
    -- chamadas; aqui o objetivo é montar VOLUME, não medir a criação.
    -- §17 CORREÇÃO CONSOLIDADA 01: a v2.0 dizia que a criação via RPC
    -- era "medida separadamente em W_ADDPAGE" — esse workload NÃO
    -- existe. Medir add_layout_page() não está no escopo dos 12
    -- workloads congelados, e nenhum workload foi inventado aqui para
    -- justificar a frase.
    INSERT INTO public.collection_layout_page (layout_id, page_number)
    SELECT v_layout, gs FROM generate_series(1, 100) AS gs;

    INSERT INTO public.collection_layout_slot (page_id, row_index, column_index)
    SELECT p.id, r, c
      FROM public.collection_layout_page p
     CROSS JOIN generate_series(1,4) AS r
     CROSS JOIN generate_series(1,4) AS c
     WHERE p.layout_id = v_layout;

    SELECT count(*) INTO v_n FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id=s.page_id WHERE p.layout_id=v_layout;
    IF v_n <> 1600 THEN
        RAISE EXCEPTION 'FIXTURE ABORT — esperado 1600 Slots, obtido %', v_n;
    END IF;

    -- 800 Physical Cards + Allocations. As Physical Cards criadas aqui são
    -- rotuladas em _pc para que a Allocation use EXATAMENTE estas — nunca
    -- Physical Cards reais pré-existentes do Inventory do owner.
    WITH ins AS (
        INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
        SELECT v_varA, v_lang, v_inv FROM generate_series(1, 800)
        RETURNING id
    )
    INSERT INTO _pc (k, id) SELECT 'coll', id FROM ins;

    INSERT INTO public.collection_allocation (physical_card_id, collection_id)
    SELECT x.id, v_coll FROM _pc x WHERE x.k = 'coll';

    -- 800 Assignments — metade dos Slots (colunas 1 e 2 de cada Page).
    WITH slots AS (
        SELECT s.id, row_number() OVER (ORDER BY p.page_number, s.row_index, s.column_index) AS rn
          FROM public.collection_layout_slot s
          JOIN public.collection_layout_page p ON p.id = s.page_id
         WHERE p.layout_id = v_layout AND s.column_index IN (1,2)
    ), allocs AS (
        SELECT ca.id, row_number() OVER (ORDER BY ca.created_at, ca.id) AS rn
          FROM public.collection_allocation ca WHERE ca.collection_id = v_coll
    )
    INSERT INTO public.collection_layout_slot_assignment (slot_id, collection_allocation_id)
    SELECT s.id, a.id FROM slots s JOIN allocs a ON a.rn = s.rn;

    SELECT count(*) INTO v_n FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id=a.slot_id
      JOIN public.collection_layout_page p ON p.id=s.page_id WHERE p.layout_id=v_layout;
    IF v_n <> 800 THEN
        RAISE EXCEPTION 'FIXTURE ABORT — esperado 800 Assignments, obtido %', v_n;
    END IF;

    -- 400 Expected Content (coluna 3 de cada Page + metade da coluna 4).
    INSERT INTO public.collection_layout_slot_expected_content (slot_id, card_id)
    SELECT s.id, v_cardA
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
     WHERE p.layout_id = v_layout AND s.column_index = 3
     LIMIT 400;

    -- 50 Layout Regions — linha 4, colunas 3-4, nas 50 primeiras Pages.
    INSERT INTO public.collection_layout_region (page_id, top_row, left_column, height, width)
    SELECT p.id, 4, 3, 1, 2
      FROM public.collection_layout_page p
     WHERE p.layout_id = v_layout AND p.page_number <= 50;

    -- Guardar ids de referência para os workloads.
    SELECT id INTO v_page FROM public.collection_layout_page
     WHERE layout_id=v_layout AND page_number=7;
    INSERT INTO _f VALUES ('page7', v_page);
    SELECT id INTO v_page FROM public.collection_layout_page
     WHERE layout_id=v_layout AND page_number=8;
    INSERT INTO _f VALUES ('page8', v_page);

    ANALYZE public.collection_layout_slot;
    ANALYZE public.collection_layout_page;
    ANALYZE public.collection_layout_slot_assignment;
    ANALYZE public.collection_layout_slot_expected_content;
    ANALYZE public.collection_layout_region;
END $blk$;

-- Variante de medição para chamadas de FUNÇÃO: o EXPLAIN externo captura
-- tempo e buffers agregados, mas os nós internos permanecem invisíveis.
CREATE OR REPLACE FUNCTION pg_temp._measure_fn(
    p_workload TEXT, p_desc TEXT, p_sql TEXT,
    p_thr_healthy NUMERIC, p_thr_blocker NUMERIC, p_note TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM pg_temp._measure(p_workload, p_desc, p_sql, p_thr_healthy, p_thr_blocker, p_note);
    UPDATE _p SET plan_visibility = 'NOT OBSERVABLE (nós internos da função)'
     WHERE seq = (SELECT max(seq) FROM _p);
END; $fn$;

-- =================================================================
-- FASE 1 — WORKLOADS DE LEITURA (estado íntegro da fixture)
-- =================================================================

-- W1 — Render de UMA Page (1 Page, 16 Slots, com Assignment e Lock).
DO $blk$
DECLARE v_page UUID := (SELECT v FROM _f WHERE k='page7');
BEGIN
    PERFORM pg_temp._measure('W1',
        'Render de 1 Page: 16 Slots + Assignment (LEFT JOIN) + locked',
        format($q$
            SELECT s.id, s.row_index, s.column_index, s.locked,
                   a.id AS assignment_id, a.collection_allocation_id
              FROM public.collection_layout_slot s
              LEFT JOIN public.collection_layout_slot_assignment a ON a.slot_id = s.id
             WHERE s.page_id = %L
             ORDER BY s.row_index, s.column_index
        $q$, v_page), 5, 50,
        'Espera-se uso de uq_collection_layout_slot_position (prefixo page_id).');
END $blk$;

-- W2 — Render de um SPREAD (2 Pages, 32 Slots) — caminho quente do Binder.
DO $blk$
DECLARE v_p7 UUID := (SELECT v FROM _f WHERE k='page7');
        v_p8 UUID := (SELECT v FROM _f WHERE k='page8');
BEGIN
    PERFORM pg_temp._measure('W2',
        'Render de spread (2 Pages, 32 Slots) + Assignment',
        format($q$
            SELECT p.page_number, s.row_index, s.column_index, s.locked, a.id AS assignment_id
              FROM public.collection_layout_page p
              JOIN public.collection_layout_slot s ON s.page_id = p.id
              LEFT JOIN public.collection_layout_slot_assignment a ON a.slot_id = s.id
             WHERE p.id IN (%L, %L)
             ORDER BY p.page_number, s.row_index, s.column_index
        $q$, v_p7, v_p8), 8, 80,
        'Caminho quente do Binder. Sem índice novo: page_id vem do prefixo da UNIQUE.');
END $blk$;

-- W3 — Spread ENRIQUECIDO: Slots + Assignment + Physical Card + Card
--      + Expected Content + Region. É o payload real de uma tela.
DO $blk$
DECLARE v_p7 UUID := (SELECT v FROM _f WHERE k='page7');
        v_p8 UUID := (SELECT v FROM _f WHERE k='page8');
BEGIN
    PERFORM pg_temp._measure('W3',
        'Spread enriquecido: + Physical Card + Card Variant + Expected Content + Region',
        format($q$
            SELECT p.page_number, s.row_index, s.column_index, s.locked,
                   pc.id AS physical_card_id, cv.id AS card_variant_id, c.id AS card_id,
                   ec.card_id AS expected_card_id,
                   r.id AS region_id, r.top_row, r.left_column, r.height, r.width
              FROM public.collection_layout_page p
              JOIN public.collection_layout_slot s ON s.page_id = p.id
              LEFT JOIN public.collection_layout_slot_assignment a ON a.slot_id = s.id
              LEFT JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
              LEFT JOIN public.physical_card pc ON pc.id = ca.physical_card_id
              LEFT JOIN public.card_variant cv ON cv.id = pc.card_variant_id
              LEFT JOIN public.card c ON c.id = cv.card_id
              LEFT JOIN public.collection_layout_slot_expected_content ec ON ec.slot_id = s.id
              LEFT JOIN public.collection_layout_region r
                     ON r.page_id = p.id
                    AND s.row_index    BETWEEN r.top_row     AND r.top_row + r.height - 1
                    AND s.column_index BETWEEN r.left_column AND r.left_column + r.width - 1
             WHERE p.id IN (%L, %L)
             ORDER BY p.page_number, s.row_index, s.column_index
        $q$, v_p7, v_p8), 15, 150,
        'Payload real de tela. O JOIN de Region usa bounding box (DP-04), sem GiST.');
END $blk$;

-- W4 — Overview do Binder inteiro: 100 Pages com contagens agregadas
--      (usado pela navegação/miniaturas).
DO $blk$
DECLARE v_layout UUID := (SELECT v FROM _f WHERE k='layout');
BEGIN
    PERFORM pg_temp._measure('W4',
        'Overview de 100 Pages: contagem de Slots preenchidos/locked/expected por Page',
        format($q$
            SELECT p.id, p.page_number,
                   count(s.id)                                      AS slots,
                   count(a.id)                                      AS filled,
                   count(*) FILTER (WHERE s.locked)                 AS locked,
                   count(ec.slot_id)                                AS expected
              FROM public.collection_layout_page p
              JOIN public.collection_layout_slot s ON s.page_id = p.id
              LEFT JOIN public.collection_layout_slot_assignment a ON a.slot_id = s.id
              LEFT JOIN public.collection_layout_slot_expected_content ec ON ec.slot_id = s.id
             WHERE p.layout_id = %L
             GROUP BY p.id, p.page_number
             ORDER BY p.page_number
        $q$, v_layout), 40, 400,
        'Varredura completa de 1600 Slots. Sequential Scan aqui é ESPERADO e aceitável.');
END $blk$;

-- W10a — Lookup de Region por Page e teste de OVERLAP (predicado que o
--        trigger 5121 executa a cada MERGE).
DO $blk$
DECLARE v_p7 UUID := (SELECT v FROM _f WHERE k='page7');
BEGIN
    PERFORM pg_temp._measure('W10a',
        'Lookup de Regions da Page + predicado de overlap do trigger 5121',
        format($q$
            SELECT r.id
              FROM public.collection_layout_region r
             WHERE r.page_id = %L
               AND 4 <= r.top_row     + r.height - 1 AND r.top_row     <= 4 + 1 - 1
               AND 3 <= r.left_column + r.width  - 1 AND r.left_column <= 3 + 2 - 1
        $q$, v_p7), 5, 50,
        'Predicado de overlap por bounding box. 50 Regions no Layout; poucas por Page.');
END $blk$;

-- W11 — JOIN de Expected Content com o catálogo (Card + Card Variant),
--       o read que alimenta o "slot esperado, ainda vazio".
DO $blk$
DECLARE v_layout UUID := (SELECT v FROM _f WHERE k='layout');
BEGIN
    PERFORM pg_temp._measure('W11',
        'Expected Content x Catálogo em todo o Layout (400 linhas), só Slots vazios',
        format($q$
            SELECT p.page_number, s.row_index, s.column_index,
                   ec.card_id, ec.card_variant_id, c.name
              FROM public.collection_layout_slot_expected_content ec
              JOIN public.collection_layout_slot s ON s.id = ec.slot_id
              JOIN public.collection_layout_page p ON p.id = s.page_id
              JOIN public.card c ON c.id = ec.card_id
              LEFT JOIN public.collection_layout_slot_assignment a ON a.slot_id = s.id
             WHERE p.layout_id = %L
               AND a.id IS NULL
             ORDER BY p.page_number, s.row_index, s.column_index
        $q$, v_layout), 25, 250,
        'ec.slot_id é PK; o filtro por layout_id força varredura de Page->Slot.');
END $blk$;

-- =================================================================
-- FASE 2 — WORKLOADS DE ESCRITA (via RPC pública, como o app chama)
--
-- As 13 RPCs são SECURITY DEFINER e checam auth.uid(). Portanto os
-- workloads de escrita rodam com o papel `authenticated` e com o claim
-- do owner da fixture — exatamente como a aplicação real chamaria.
-- Consequência de honestidade: o EXPLAIN externo de uma RPC mostra
-- apenas `Function Scan`. Esses workloads são medidos por wall clock e
-- registrados como INTERNAL PLAN VISIBILITY = NOT OBSERVABLE.
-- =================================================================

-- As TEMP TABLEs precisam ser graváveis pelo papel `authenticated`,
-- senão o registro da medição falharia após o SET LOCAL ROLE.
GRANT ALL ON _p, _f, _pc TO authenticated;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE _p_seq_seq TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp._as_user(p_uid UUID) RETURNS VOID
LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', p_uid::TEXT, 'role', 'authenticated')::TEXT,
                       TRUE);
    SET LOCAL ROLE authenticated;
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._as_admin() RETURNS VOID
LANGUAGE plpgsql AS $fn$
BEGIN
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);
END; $fn$;

-- W5 — REORDER de 100 Pages numa única chamada (inversão total).
--      Exercita a UNIQUE DEFERRABLE de page_number, que é DP-02
--      (page_number INTEGER + reorder em massa). §17 CORREÇÃO
--      CONSOLIDADA 01: a v2.0 atribuía isso a DP-03, que trata do
--      grid 1..10 e da alteração com zero Pages — decisão diferente.
DO $blk$
DECLARE
    v_owner  UUID := (SELECT v FROM _f WHERE k='owner');
    v_layout UUID := (SELECT v FROM _f WHERE k='layout');
    v_ids    UUID[];
BEGIN
    SELECT array_agg(id ORDER BY page_number DESC) INTO v_ids
      FROM public.collection_layout_page WHERE layout_id = v_layout;

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._measure_rpc('W5',
        'reorder_layout_pages(): inversão completa de 100 Pages em 1 chamada',
        format('SELECT * FROM public.reorder_layout_pages(%L, %L::UUID[])', v_layout, v_ids),
        150, 1500,
        'UNIQUE DEFERRABLE de page_number permite o UPDATE em massa sem tabela auxiliar. NOT OBSERVABLE.');
    PERFORM pg_temp._as_admin();
END $blk$;

-- W6 — MOVE de 1 Assignment para Slot vazio da mesma Page.
DO $blk$
DECLARE
    v_owner UUID := (SELECT v FROM _f WHERE k='owner');
    v_p7 UUID := (SELECT v FROM _f WHERE k='page7');
    v_from UUID; v_to UUID;
BEGIN
    SELECT id INTO v_from FROM public.collection_layout_slot
     WHERE page_id = v_p7 AND row_index = 1 AND column_index = 1;
    SELECT id INTO v_to FROM public.collection_layout_slot
     WHERE page_id = v_p7 AND row_index = 1 AND column_index = 4;

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._measure_rpc('W6',
        'move_slot_assignment(): MOVE para Slot vazio (destino livre)',
        format('SELECT * FROM public.move_slot_assignment(%L, %L)', v_from, v_to),
        20, 200, 'Caminho MOVE. NOT OBSERVABLE.');
    PERFORM pg_temp._as_admin();
END $blk$;

-- W7 — SWAP: as duas linhas trocam slot_id sob UNIQUE DEFERRABLE.
DO $blk$
DECLARE
    v_owner UUID := (SELECT v FROM _f WHERE k='owner');
    v_p8 UUID := (SELECT v FROM _f WHERE k='page8');
    v_a UUID; v_b UUID;
BEGIN
    SELECT id INTO v_a FROM public.collection_layout_slot
     WHERE page_id = v_p8 AND row_index = 1 AND column_index = 1;
    SELECT id INTO v_b FROM public.collection_layout_slot
     WHERE page_id = v_p8 AND row_index = 1 AND column_index = 2;

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._measure_rpc('W7',
        'move_slot_assignment(): SWAP (destino ocupado) sob UNIQUE DEFERRABLE',
        format('SELECT * FROM public.move_slot_assignment(%L, %L)', v_a, v_b),
        20, 200, 'Caminho SWAP: viola momentaneamente UNIQUE(slot_id), resolvido no fim do statement. NOT OBSERVABLE.');
    PERFORM pg_temp._as_admin();
END $blk$;

-- W8 — BULK REMOVE de 80 Assignments numa chamada (coluna 1, Pages 81..100).
DO $blk$
DECLARE
    v_owner UUID := (SELECT v FROM _f WHERE k='owner');
    v_layout UUID := (SELECT v FROM _f WHERE k='layout');
    v_ids UUID[]; v_n INTEGER;
BEGIN
    SELECT array_agg(s.id) INTO v_ids
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout_slot_assignment a ON a.slot_id = s.id
     WHERE p.layout_id = v_layout AND s.column_index = 1 AND p.page_number >= 81;

    v_n := COALESCE(array_length(v_ids,1), 0);
    IF v_n = 0 THEN
        INSERT INTO _p (workload, description, classification, note)
        VALUES ('W8','remove_slot_assignment() em massa','BLOCKER',
                'Fixture sem Slots elegíveis — medicao NAO realizada.');
    ELSE
        PERFORM pg_temp._as_user(v_owner);
        PERFORM pg_temp._measure_rpc('W8',
            format('remove_slot_assignment(): remoção em massa de %s Assignments em 1 chamada', v_n),
            format('SELECT public.remove_slot_assignment(%L::UUID[])', v_ids),
            80, 800, 'Bulk remove. Dispara o trigger de Lock (5118) por linha. NOT OBSERVABLE.');
        PERFORM pg_temp._as_admin();
    END IF;
END $blk$;

-- W10b — MERGE de Region: custo do enforcement de overlap + lock (5121).
DO $blk$
DECLARE
    v_owner UUID := (SELECT v FROM _f WHERE k='owner');
    v_layout UUID := (SELECT v FROM _f WHERE k='layout');
    v_page UUID;
BEGIN
    -- Page sem Region (page_number original > 50; após W5 a numeração foi
    -- invertida, então localizamos pela ausência de Region, não pelo número).
    SELECT p.id INTO v_page
      FROM public.collection_layout_page p
     WHERE p.layout_id = v_layout
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_region r WHERE r.page_id = p.id)
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_slot s
                        WHERE s.page_id = p.id AND s.locked)
     ORDER BY p.page_number LIMIT 1;

    IF v_page IS NULL THEN
        INSERT INTO _p (workload, description, classification, note)
        VALUES ('W10b','merge_layout_region()','BLOCKER',
                'Nenhuma Page sem Region e sem Lock — medicao NAO realizada.');
    ELSE
        PERFORM pg_temp._as_user(v_owner);
        PERFORM pg_temp._measure_rpc('W10b',
            'merge_layout_region(): enforcement de bounds + overlap + lock (trigger 5121)',
            format('SELECT * FROM public.merge_layout_region(%L, 1, 3, 1, 2)', v_page),
            20, 200,
            'Custo do bounding box sem GiST/EXCLUDE (DP-04). NOT OBSERVABLE.');
        PERFORM pg_temp._as_admin();
    END IF;
END $blk$;

-- W9 — BULK LOCK de 400 Slots numa chamada (coluna 2 de todas as Pages).
--      Roda DEPOIS de W8/W10b de propósito: Lock impede Remove e Merge.
DO $blk$
DECLARE
    v_owner UUID := (SELECT v FROM _f WHERE k='owner');
    v_layout UUID := (SELECT v FROM _f WHERE k='layout');
    v_ids UUID[]; v_n INTEGER;
BEGIN
    SELECT array_agg(s.id) INTO v_ids
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
     WHERE p.layout_id = v_layout AND s.column_index = 2;

    v_n := COALESCE(array_length(v_ids,1), 0);
    IF v_n = 0 THEN
        INSERT INTO _p (workload, description, classification, note)
        VALUES ('W9','set_slot_lock() em massa','BLOCKER',
                'Fixture sem Slots elegíveis — medicao NAO realizada.');
    ELSE
        PERFORM pg_temp._as_user(v_owner);
        PERFORM pg_temp._measure_rpc('W9',
            format('set_slot_lock(): Lock em massa de %s Slots em 1 chamada', v_n),
            format('SELECT public.set_slot_lock(%L::UUID[], TRUE)', v_ids),
            120, 1200, 'Bulk lock. NOT OBSERVABLE.');
        PERFORM pg_temp._as_admin();
    END IF;
END $blk$;

-- =================================================================
-- FASE 3 — W12: REGRESSÃO DE COMPLETION
--
-- Pergunta que este workload responde: **a existência de um Layout
-- degrada ou altera o cálculo de Completion já LIVE (5100/5102 e
-- 5101/5103)?**
--
-- GATE CORRETO (corrigido nesta versão — a v1.0 exigia wall clock
-- literalmente idêntico, o que é ruído, não evidência):
--   G1 IDENTIDADE SEMÂNTICA .. payload da resposta idêntico antes/depois.
--   G2 CARDINALIDADE ........ mesmo número de linhas antes/depois.
--   G3 DEPENDÊNCIA FUNCIONAL. o corpo das funções de Completion não
--                             referencia NENHUMA tabela collection_layout*.
--   G4 BUFFERS ............. sem aumento estrutural anormal
--                             (tolerância: +25% e +50 blocos).
--   G5 RUÍDO ............... tempo dentro de tolerância de ruído
--                             (3x ou +5 ms, o que for maior).
--                             NÃO se exige igualdade de wall clock.
--
-- Visibilidade: o EXPLAIN externo da função mostra apenas Function Scan.
-- Onde os nós internos não forem observáveis, registra-se literalmente
-- INTERNAL PLAN VISIBILITY = NOT OBSERVABLE. Nenhum nó interno é inferido.
-- =================================================================

-- G3 (§16 CORRECAO CONSOLIDADA 01) — prova estatica de independencia
-- funcional, agora COMPLETA e ROBUSTA.
--
-- Dois defeitos da v2.0:
--  (a) a lista de funcoes omitia collection_completion_positions()
--      (Query 5071), que tambem e read model de Completion;
--  (b) usava `ILIKE '%collection_layout%'`. Em LIKE/ILIKE o caractere
--      `_` e WILDCARD: 'collection_layout' casaria tambem com
--      'collectionXlayout'. Foi exatamente esse tipo de falso positivo
--      textual que produziu o POSTCHECK-2c errado da Fatia E.
--
-- Correcao: comentarios SQL sao removidos do pg_get_functiondef antes
-- da busca (bloco primeiro, depois linha — mesma abordagem do 5817), e
-- a busca usa `position(... in ...)`, que e literal e nao interpreta
-- `_`. Uma referencia que exista APENAS em comentario nao conta como
-- dependencia funcional.
DO $blk$
DECLARE
    v_src_exec TEXT;
    v_hits     TEXT := '';
    v_checked  TEXT := '';
    v_missing  TEXT := '';
    v_expected TEXT[] := ARRAY[
        'collection_completion_summary',
        'collection_completion_positions',
        'collection_master_set_scope_positions',
        'collection_pokedex_scope_positions'];
    t TEXT;
    f RECORD;
    v_found BOOLEAN;
BEGIN
    FOREACH t IN ARRAY v_expected LOOP
        v_found := FALSE;
        FOR f IN
            SELECT p.oid, p.proname
              FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = t
        LOOP
            v_found   := TRUE;
            v_checked := v_checked || f.proname || ' ';

            -- (a) comentarios de bloco; (b) comentarios de linha.
            v_src_exec := lower(
                regexp_replace(
                    regexp_replace(COALESCE(pg_get_functiondef(f.oid), ''),
                                   '/\*.*?\*/', ' ', 'gs'),
                    '--.*$', ' ', 'gn'));

            -- position() e literal: `_` NAO e wildcard aqui.
            IF position('collection_layout' in v_src_exec) > 0 THEN
                v_hits := v_hits || f.proname || ' ';
            END IF;
        END LOOP;

        IF NOT v_found THEN
            v_missing := v_missing || t || ' ';
        END IF;
    END LOOP;

    INSERT INTO _p (workload, description, plan_visibility, classification, note)
    VALUES ('W12-G3',
            'Dependencia funcional: NENHUMA das 4 funcoes de Completion referencia collection_layout* (comentarios removidos, busca literal)',
            'STATIC (pg_get_functiondef, comentarios removidos)',
            CASE WHEN v_missing <> '' THEN 'BLOCKER'
                 WHEN v_hits = ''     THEN 'HEALTHY'
                 ELSE                      'BLOCKER' END,
            CASE WHEN v_missing <> ''
                     THEN 'FUNCAO AUSENTE no banco (cobertura incompleta): ' || v_missing
                          || ' | verificadas: ' || COALESCE(NULLIF(v_checked,''),'(nenhuma)')
                 WHEN v_hits = ''
                     THEN 'Nenhuma referencia a collection_layout no corpo executavel. Verificadas: ' || v_checked
                 ELSE 'REFERENCIA ENCONTRADA em: ' || v_hits END);
END $blk$;

-- G1/G2/G4/G5 — medição ANTES/DEPOIS numa Collection dedicada.
--
-- ATENÇÃO DE AUTORIZAÇÃO (achado real, não teórico):
-- collection_completion_summary() é SECURITY DEFINER e reconstitui
-- ownership manualmente via auth.uid(). Rodando como admin/postgres sem
-- claim JWT, auth.uid() é NULL e a função devolve ZERO LINHAS — a
-- comparação "antes x depois" seria idêntica por vacuidade, um PASS
-- artificial. Além disso o ramo STANDARD_SET só existe para
-- mode=REFERENCE_BASED + completion_policy IN (STANDARD_SET, MASTER_SET).
-- Por isso a Collection de W12 é criada pela RPC real
-- create_reference_based_card_set_collection() SOB O OWNER, apontando
-- para um Card Set REAL, e TODAS as medições de W12 correm sob
-- `authenticated` com o claim do owner. Precedente literal: 5814,
-- Passo 5 (col_standard).
DO $blk$
DECLARE
    v_owner UUID := (SELECT v FROM _f WHERE k='owner');
    v_lang  UUID := (SELECT v FROM _f WHERE k='lang');
    v_game  UUID := (SELECT v FROM _f WHERE k='game');
    v_inv   UUID := (SELECT v FROM _f WHERE k='inv');
    v_sc    UUID := (SELECT v FROM _f WHERE k='sc');
    v_card_set UUID;
    v_collB UUID; v_layB UUID;
    v_n_alloc INTEGER;
    v_n_before BIGINT; v_n_after BIGINT;
    v_txt_before TEXT; v_txt_after TEXT;
    v_ms_before NUMERIC; v_ms_after NUMERIC;
    v_buf_before BIGINT; v_buf_after BIGINT;
    v_sql TEXT;
BEGIN
    -- Card Set REAL do mesmo Game, com pelo menos 4 Card Variants.
    -- Leitura privilegiada: card/card_variant são RLS admin-only, então
    -- isto NUNCA pode rodar sob `authenticated`.
    SELECT c.card_set_id INTO v_card_set
      FROM public.card c
      JOIN public.card_variant cv ON cv.card_id = c.id
      JOIN public.card_set cs     ON cs.id = c.card_set_id
      JOIN public.expansion ex    ON ex.id = cs.expansion_id
     WHERE ex.game_id = v_game
     GROUP BY c.card_set_id
    HAVING count(DISTINCT cv.id) >= 4
     ORDER BY c.card_set_id
     LIMIT 1;

    IF v_card_set IS NULL THEN
        INSERT INTO _p (workload, description, plan_visibility, classification, note)
        VALUES ('W12','Regressão de Completion','FIXTURE','BLOCKER',
                'Nenhum Card Set com >= 4 Card Variants no Game da fixture — W12 NAO medido. Nenhum PASS artificial registrado.');
        RETURN;
    END IF;

    -- Collection REFERENCE_BASED/STANDARD_SET criada pela RPC real, como owner.
    PERFORM pg_temp._as_user(v_owner);
    SELECT r.id INTO v_collB
      FROM public.create_reference_based_card_set_collection(
               v_game, '__5819_collB__', NULL, v_sc, v_card_set) r;
    PERFORM pg_temp._as_admin();

    IF v_collB IS NULL THEN
        INSERT INTO _p (workload, description, plan_visibility, classification, note)
        VALUES ('W12','Regressão de Completion','FIXTURE','BLOCKER',
                'create_reference_based_card_set_collection() nao devolveu id — W12 NAO medido.');
        RETURN;
    END IF;
    INSERT INTO _f VALUES ('collB', v_collB);

    -- Physical Cards a partir das Variants REAIS do Card Set (até 160),
    -- alocadas à Collection. Numerador de STANDARD_SET deixa de ser zero.
    WITH ins AS (
        INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
        SELECT cv.id, v_lang, v_inv
          FROM public.card_variant cv
          JOIN public.card c ON c.id = cv.card_id
         WHERE c.card_set_id = v_card_set
         ORDER BY cv.id
         LIMIT 160
        RETURNING id
    )
    INSERT INTO _pc (k, id) SELECT 'collB', id FROM ins;

    INSERT INTO public.collection_allocation (physical_card_id, collection_id)
    SELECT x.id, v_collB FROM _pc x WHERE x.k = 'collB';

    SELECT count(*) INTO v_n_alloc
      FROM public.collection_allocation WHERE collection_id = v_collB;

    v_sql := format('SELECT * FROM public.collection_completion_summary(%L)', v_collB);

    -- ---------- ANTES (Collection SEM Layout) ----------
    PERFORM pg_temp._as_user(v_owner);
    PERFORM * FROM public.collection_completion_summary(v_collB);   -- warm-up, não medido

    SELECT count(*), COALESCE(string_agg(to_jsonb(t)::TEXT, '|' ORDER BY to_jsonb(t)::TEXT), '')
      INTO v_n_before, v_txt_before
      FROM public.collection_completion_summary(v_collB) t;

    PERFORM pg_temp._measure_fn('W12a',
        'collection_completion_summary() ANTES de existir Layout na Collection',
        v_sql, 50, 500,
        format('Baseline sob owner. allocations=%s. INTERNAL PLAN VISIBILITY = NOT OBSERVABLE.', v_n_alloc));
    PERFORM pg_temp._as_admin();

    SELECT exec_ms, COALESCE(shared_hit,0)+COALESCE(shared_read,0)
      INTO v_ms_before, v_buf_before FROM _p WHERE seq = (SELECT max(seq) FROM _p);

    -- Prova de que o baseline NÃO é vazio por falta de autorização.
    INSERT INTO _p (workload, description, plan_visibility, rows_out, classification, note)
    VALUES ('W12-G0','Baseline de Completion é NÃO-VAZIO (senão a comparação seria vácua)',
            'AUTHORIZATION', v_n_before,
            CASE WHEN v_n_before > 0 THEN 'HEALTHY' ELSE 'BLOCKER' END,
            format('linhas do baseline=%s; allocations=%s. Zero linhas significaria auth.uid() nulo ou policy incompatível — nunca PASS.',
                   v_n_before, v_n_alloc));

    -- ---------- Criação do Layout NA MESMA Collection ----------
    -- 20 Pages / 320 Slots / até 160 Assignments / 80 Expected Content / 10 Regions.
    INSERT INTO public.collection_layout (collection_id, grid_rows, grid_columns)
    VALUES (v_collB, 4, 4) RETURNING id INTO v_layB;

    INSERT INTO public.collection_layout_page (layout_id, page_number)
    SELECT v_layB, gs FROM generate_series(1, 20) AS gs;

    INSERT INTO public.collection_layout_slot (page_id, row_index, column_index)
    SELECT p.id, r, c
      FROM public.collection_layout_page p
     CROSS JOIN generate_series(1,4) AS r
     CROSS JOIN generate_series(1,4) AS c
     WHERE p.layout_id = v_layB;

    WITH slots AS (
        SELECT s.id, row_number() OVER (ORDER BY p.page_number, s.row_index, s.column_index) AS rn
          FROM public.collection_layout_slot s
          JOIN public.collection_layout_page p ON p.id = s.page_id
         WHERE p.layout_id = v_layB AND s.column_index IN (1,2)
    ), allocs AS (
        SELECT ca.id, row_number() OVER (ORDER BY ca.created_at, ca.id) AS rn
          FROM public.collection_allocation ca WHERE ca.collection_id = v_collB
    )
    INSERT INTO public.collection_layout_slot_assignment (slot_id, collection_allocation_id)
    SELECT s.id, a.id FROM slots s JOIN allocs a ON a.rn = s.rn;

    INSERT INTO public.collection_layout_slot_expected_content (slot_id, card_id)
    SELECT s.id, (SELECT c.id FROM public.card c WHERE c.card_set_id = v_card_set ORDER BY c.id LIMIT 1)
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
     WHERE p.layout_id = v_layB AND s.column_index = 3
     LIMIT 80;

    INSERT INTO public.collection_layout_region (page_id, top_row, left_column, height, width)
    SELECT p.id, 4, 3, 1, 2
      FROM public.collection_layout_page p
     WHERE p.layout_id = v_layB AND p.page_number <= 10;

    ANALYZE public.collection_layout_slot;
    ANALYZE public.collection_layout_slot_assignment;

    -- ---------- DEPOIS (mesma Collection, agora COM Layout) ----------
    PERFORM pg_temp._as_user(v_owner);
    PERFORM * FROM public.collection_completion_summary(v_collB);   -- warm-up, não medido

    SELECT count(*), COALESCE(string_agg(to_jsonb(t)::TEXT, '|' ORDER BY to_jsonb(t)::TEXT), '')
      INTO v_n_after, v_txt_after
      FROM public.collection_completion_summary(v_collB) t;

    PERFORM pg_temp._measure_fn('W12b',
        'collection_completion_summary() DEPOIS de existir Layout na mesma Collection',
        v_sql, 50, 500,
        'Comparação sob o mesmo owner e a mesma Collection. INTERNAL PLAN VISIBILITY = NOT OBSERVABLE.');
    PERFORM pg_temp._as_admin();

    SELECT exec_ms, COALESCE(shared_hit,0)+COALESCE(shared_read,0)
      INTO v_ms_after, v_buf_after FROM _p WHERE seq = (SELECT max(seq) FROM _p);

    -- G1 IDENTIDADE SEMÂNTICA
    INSERT INTO _p (workload, description, plan_visibility, classification, note)
    VALUES ('W12-G1','Identidade semântica do payload de Completion antes x depois do Layout',
            'RESULT COMPARISON',
            CASE WHEN v_txt_before IS NOT DISTINCT FROM v_txt_after THEN 'HEALTHY' ELSE 'BLOCKER' END,
            CASE WHEN v_txt_before IS NOT DISTINCT FROM v_txt_after
                 THEN 'Payload idêntico: ' || left(COALESCE(v_txt_after,'<null>'), 300)
                 ELSE 'DIVERGENTE. antes=' || left(COALESCE(v_txt_before,'<null>'), 300)
                      || ' | depois=' || left(COALESCE(v_txt_after,'<null>'), 300) END);

    -- G2 CARDINALIDADE
    INSERT INTO _p (workload, description, plan_visibility, rows_out, classification, note)
    VALUES ('W12-G2','Cardinalidade do resultado de Completion antes x depois do Layout',
            'RESULT COMPARISON', v_n_after,
            CASE WHEN v_n_before = v_n_after THEN 'HEALTHY' ELSE 'BLOCKER' END,
            format('antes=%s depois=%s', v_n_before, v_n_after));

    -- G4 BUFFERS — aumento estrutural anormal
    INSERT INTO _p (workload, description, plan_visibility, shared_hit, classification, note)
    VALUES ('W12-G4','Buffers de Completion: sem aumento estrutural anormal causado pelo Layout',
            'BUFFERS', v_buf_after,
            CASE WHEN v_buf_after IS NULL OR v_buf_before IS NULL THEN 'UNKNOWN'
                 WHEN v_buf_after <= v_buf_before * 1.25 + 50 THEN 'HEALTHY'
                 ELSE 'BLOCKER' END,
            format('antes=%s depois=%s (tolerância: +25%% e +50 blocos)', v_buf_before, v_buf_after));

    -- G5 RUÍDO — explicitamente NÃO exige wall clock idêntico
    INSERT INTO _p (workload, description, plan_visibility, exec_ms, classification, note)
    VALUES ('W12-G5','Tempo de Completion dentro de tolerância de ruído (NÃO igualdade literal)',
            'WALL CLOCK (tolerância de ruído)', v_ms_after,
            CASE WHEN v_ms_after IS NULL OR v_ms_before IS NULL THEN 'UNKNOWN'
                 WHEN v_ms_after <= GREATEST(v_ms_before * 3, v_ms_before + 5) THEN 'HEALTHY'
                 ELSE 'ATTENTION' END,
            format('antes=%s ms depois=%s ms (tolerância: 3x ou +5 ms). Wall clock idêntico NAO e exigido.',
                   v_ms_before, v_ms_after));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    INSERT INTO _p (workload, description, plan_visibility, classification, note)
    VALUES ('W12','Regressão de Completion','FIXTURE','BLOCKER',
            'W12 abortou: ' || SQLSTATE || ' ' || left(SQLERRM, 250) || ' — NENHUM gate marcado como HEALTHY.');
END $blk$;

-- =================================================================
-- ZERO RESÍDUO
-- =================================================================
DO $blk$
DECLARE v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM public.collection WHERE name LIKE '\_\_5819\_%';
    INSERT INTO _p (workload, description, rows_out, plan_visibility, classification, note)
    VALUES ('X01','Fixtures existem DENTRO da transação (descartadas no ROLLBACK)',
            v_n, 'STATIC',
            CASE WHEN v_n = 2 THEN 'HEALTHY' ELSE 'BLOCKER' END,
            format('collections de fixture encontradas=%s (esperado 2: __5819_coll__ e __5819_collB__)', v_n));

    INSERT INTO _p (workload, description, plan_visibility, classification, note)
    VALUES ('X02','Zero resíduo garantido por BEGIN...ROLLBACK (sem COMMIT no arquivo)',
            'STATIC','HEALTHY','O arquivo termina em ROLLBACK. A fixture de 1600 Slots nunca é commitada.');
END $blk$;

-- =================================================================
-- RELATÓRIO FINAL — última instrução antes do ROLLBACK.
--
-- NOTA OPERACIONAL: integrações que devolvem apenas o resultado do
-- ÚLTIMO statement (caso do execute_sql) devem executar este arquivo em
-- DUAS chamadas: (1) tudo até o SELECT abaixo, inclusive; (2) `ROLLBACK;`.
-- Executar em uma única chamada não perde a garantia transacional, mas
-- perde a visualização do relatório.
--
-- CLASSIFICAÇÃO: HEALTHY = dentro do limiar declarado ·
--                ATTENTION = acima do limiar saudável, abaixo do blocker ·
--                BLOCKER = acima do limiar de blocker, ou medição impossível ·
--                UNKNOWN = insumo ausente (nunca convertido em HEALTHY).
--
-- LEMBRETE DE HONESTIDADE: onde plan_visibility disser
-- "NOT OBSERVABLE", NENHUM nó interno de plano foi inferido.
-- =================================================================
SELECT
    seq,
    workload,
    description,
    exec_ms,
    shared_hit,
    shared_read,
    rows_out,
    top_node,
    plan_visibility,
    thr_healthy_ms,
    thr_blocker_ms,
    classification,
    note
FROM _p
ORDER BY seq;

ROLLBACK;
