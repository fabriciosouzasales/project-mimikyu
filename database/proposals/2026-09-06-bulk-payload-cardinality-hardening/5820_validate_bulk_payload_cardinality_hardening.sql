/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5820 - Validate Bulk Payload Cardinality Hardening
Versão......: 1.2 (somente documentação — lógica executável IDÊNTICA à v1.1)
Status......: EXECUTADO EM 2026-09-07 — PASS (27 TOTAL / 27 PASS / 0 FAIL / 0 NP)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (criado em
               ...-CONSOLIDATED-CORRECTION-04 §6 — validação
               transacional obrigatória antes de qualquer GO de
               execução de 5138/5139/5140;
               v1.1 em ...-CONSOLIDATED-CORRECTION-05 §2 — S02
               passa a provar `search_path` EFETIVAMENTE vazio;
               v1.2 em ...-IMPLEMENTATION-01-CLOSE §1 — retificação
               do GATE DE ACEITE. NENHUMA linha executável mudou.)

================================================================
GATE DE ACEITE (v1.2) — 28 É CONTAGEM DE RÓTULOS, NÃO ALVO DE RUNTIME
================================================================
O gate originalmente comunicado — "28 PASS / 0 FAIL / 0 NOT PROVEN" —
é ARITMETICAMENTE INALCANÇÁVEL. Isto foi medido na execução de
2026-09-07, não presumido.

O arquivo contém 28 RÓTULOS ESTÁTICOS únicos:

    E ... E01 E02                                            (2)
    F ... F01                                                (1)
    G ... G-ABORT G00 G01..G06 G11..G16 G21..G26            (20)
    S ... S01 S02 S03                                        (3)
    X ... X01 X02                                            (2)

O 28º é `G-ABORT`, que vive dentro do `EXCEPTION WHEN OTHERS` do
bloco G e é **fail-only e mutuamente exclusivo**:

  - se o grupo G roda inteiro -> `G-ABORT` NÃO é gravado; total 27,
    zero FAIL. Este é o resultado SAUDÁVEL.
  - se o grupo G aborta -> `G-ABORT` é gravado com `passed = FALSE`,
    e os casos seguintes do grupo nem chegam a rodar.

Ou seja: o 28º rótulo só existe no cenário de falha, e nesse cenário
ele nasce FAIL. Não há execução possível com 28 PASS.

GATE OFICIAL, RETIFICADO E APROVADO EM ...-IMPLEMENTATION-01-FINALIZE:

    TOTAL 27 / PASS 27 / FAIL 0 / NOT PROVEN 0

Qualquer valor diferente disto é STOP. `G-ABORT` presente = STOP.

RESULTADO REAL DE 2026-09-07 (canal MCP execute_sql):
    E 2/2 · F 1/1 · G 19/19 · S 3/3 · X 2/2 · TOTAL 27/27/0/0
    `failing_cases` NULL em todos os grupos.
    ROLLBACK emitido; postcheck pós-execução: zero resíduo
    (`__5820_*` = 0; collection_allocation = 0; physical_card = 0).

Precedente idêntico no projeto: o "205" do `5818`, que também era
contagem de rótulos estáticos (incluindo 9 rótulos de ramo mutuamente
exclusivos) e foi retificado para o alvo de runtime 196.
================================================================

Descrição...:
Harness FUNCIONAL fail-closed do hardening de cardinalidade de payload
`UUID[]` nas três RPCs bulk canônicas. Executado APÓS aplicar `5138`,
`5139` e `5140`.

POR QUE ESTE ARQUIVO EXISTE
---------------------------
`5138`–`5140` fazem `CREATE OR REPLACE` sobre funções que já estão
LIVE e são usadas pelo produto. Nenhuma delas pode ser aplicada com
base apenas em leitura de código: a `CORRECTION-04` exige **validação
transacional multidimensional** antes de qualquer GO.

O QUE ESTE HARNESS PROVA
------------------------
Para CADA uma das três funções, comportamento real:
  - lote de 500 itens ACEITO (regressão: o caminho feliz não quebrou);
  - 501 elementos TODOS REPETIDOS rejeitados — condição NECESSÁRIA,
    não suficiente (passaria também com `array_length`);
  - 501 elementos DISTINTOS rejeitados pelo cap, e NÃO por
    'not found' — o cap antecede o resolve de ownership;
  - payload MULTIDIMENSIONAL com `array_length(x,1) = 2` e
    `cardinality(x) = 600` REJEITADO — este é o caso que distingue
    `cardinality()` de `array_length(x,1)`, e o único que
    verdadeiramente prova o fechamento do bypass;
  - payload MULTIDIMENSIONAL pequeno (`cardinality = 10`) também
    rejeitado: o contrato é de FORMA, não só de tamanho;
  - array vazio produz a mensagem de VAZIO, não a de dimensão.

Mais STATIC PROOF fail-closed (grupo S), no mesmo formato do B10 do
`5818`: sobre o source SEM comentários, a cadeia
`IF cap` < `RAISE EXCEPTION` < mensagem < primeiro `unnest`/`DISTINCT`,
com `cardinality()` e `array_ndims(...) <> 1` presentes e ZERO
ocorrências de `array_length` no corpo executável.

CONTRATO DE EXECUÇÃO
--------------------
- Executar como usuário PRIVILEGIADO (postgres/service_role). O script
  alterna para `authenticated` via SET LOCAL ROLE + request.jwt.claims
  onde a semântica de cliente precisa ser exercida, e faz RESET ROLE
  antes de gravar resultado.
- TUDO dentro de BEGIN ... ROLLBACK. Zero resíduo por construção.
- FAIL-CLOSED: nenhum caso passa por omissão. Erro inesperado NUNCA
  vira PASS. `NOT PROVEN` (passed IS NULL) é um terceiro estado,
  contado à parte.
- PROTOCOLO EM DUAS CHAMADAS (mesma disciplina do `5818`):
      CALL 1 — do `BEGIN;` até o `SELECT` final do relatório, INCLUSIVE.
               A transação permanece ABERTA.
      CALL 2 — `ROLLBACK;`
  Numa chamada única o último statement é o ROLLBACK, que não retorna
  linhas — o relatório não seria devolvido.

PRÉ-REQUISITOS
--------------
- `5138`, `5139` e `5140` aplicados.
- Catálogo mínimo: >= 1 game, >= 1 language, >= 1 card_variant.
  O script NÃO fabrica Catálogo: aborta fail-loud se não encontrar.
- >= 1 auth.users.

NOTA DE PROTOCOLO (v1.2, comportamento MEDIDO do canal)
-------------------------------------------------------
O texto acima descreve o protocolo em duas chamadas como se a
transação permanecesse aberta entre elas. Medição real no canal
`execute_sql`: a sessão NÃO é preservada entre chamadas (uma TEMP
TABLE criada na chamada 1 já não existe na chamada 2). Logo:

  CALL 1 — carrega tudo até o SELECT final; ao término da chamada a
           sessão encerra e a transação sofre ROLLBACK IMPLÍCITO
           (o arquivo abre `BEGIN;` e nunca dá `COMMIT;`).
  CALL 2 — `ROLLBACK;` é confirmação explícita e no-op.

A garantia de zero resíduo NÃO depende do protocolo: depende de o
arquivo não conter `COMMIT`. Confirmado por postcheck pós-execução.

STATUS DESTA QUERY: EXECUTADO EM 2026-09-07 — PASS 27/27/0/0.
================================================================
*/

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =================================================================
-- INFRAESTRUTURA
-- =================================================================
CREATE TEMP TABLE _v (
    seq        SERIAL PRIMARY KEY,
    grp        TEXT NOT NULL,
    case_label TEXT NOT NULL,
    passed     BOOLEAN,          -- NULL = NOT PROVEN
    observed   TEXT,
    expected   TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;

GRANT ALL ON _v, _fx TO authenticated;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE _v_seq_seq TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN,
    p_observed TEXT DEFAULT NULL, p_expected TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    INSERT INTO _v (grp, case_label, passed, observed, expected)
    VALUES (p_grp, p_label, p_passed, p_observed, p_expected);
END; $fn$;

-- Remove diacríticos dos DOIS lados antes de comparar. Não relaxa a
-- semântica de substring.
CREATE OR REPLACE FUNCTION pg_temp._norm(p_text TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
    SELECT translate(
        lower(COALESCE(p_text, '')),
        'áàâãäéèêëíìîïóòôõöúùûüñçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÑÇ',
        'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC');
$fn$;

CREATE OR REPLACE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_fragment TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_msg TEXT; v_state TEXT; v_raised BOOLEAN := FALSE;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_raised := TRUE; v_msg := SQLERRM; v_state := SQLSTATE;
    END;

    IF NOT v_raised THEN
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'NENHUM erro levantado', 'erro contendo: ' || COALESCE(p_fragment, '(qualquer)'));
    ELSIF p_fragment IS NULL
       OR position(pg_temp._norm(p_fragment) in pg_temp._norm(v_msg)) > 0 THEN
        PERFORM pg_temp._rec(p_grp, p_label, TRUE,
            v_state || ' ' || left(v_msg, 160), 'erro contendo: ' || COALESCE(p_fragment, '(qualquer)'));
    ELSE
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'erro INESPERADO: ' || v_state || ' ' || left(v_msg, 160),
            'erro contendo: ' || p_fragment);
    END IF;
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._expect_ok(
    p_grp TEXT, p_label TEXT, p_sql TEXT
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    EXECUTE p_sql;
    PERFORM pg_temp._rec(p_grp, p_label, TRUE, 'executado sem erro', 'sem erro');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec(p_grp, p_label, FALSE,
        'erro: ' || SQLSTATE || ' ' || left(SQLERRM, 160), 'sem erro');
END; $fn$;

-- §2 CORRECAO CONSOLIDADA 05 — PROVA EFETIVA DE search_path VAZIO.
-- `array_to_string(proconfig,',') LIKE '%search_path=%'` era fraco:
-- `search_path=public` tambem casa. O que interessa e o VALOR.
-- proconfig guarda elementos `nome=valor`; para `SET search_path = ''`
-- o valor e vazio (podendo aparecer entre aspas conforme a forma
-- usada no DDL). Aqui: o elemento tem de existir E seu valor,
-- ignorando aspas e espacos, tem de ser vazio.
CREATE OR REPLACE FUNCTION pg_temp._empty_search_path(p_oid OID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_elem TEXT; v_val TEXT;
BEGIN
    SELECT c INTO v_elem
      FROM pg_proc p, unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS c
     WHERE p.oid = p_oid AND c LIKE 'search_path=%'
     LIMIT 1;

    IF v_elem IS NULL THEN
        RETURN FALSE;
    END IF;

    v_val := substring(v_elem from length('search_path=') + 1);
    RETURN btrim(COALESCE(v_val, ''), '''" ') = '';
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._as_user(p_user UUID)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_user::text, 'role', 'authenticated')::text, TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._as_admin()
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', TRUE);
END; $fn$;

-- =================================================================
-- FIXTURE — fail-loud. Nenhum Catálogo é fabricado.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_lang UUID; v_game UUID; v_var UUID;
    v_inv UUID; v_sc UUID; v_coll UUID; v_pc UUID;
BEGIN
    SELECT id INTO v_owner FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_lang  FROM public.language ORDER BY id LIMIT 1;

    SELECT cv.id, ex.game_id INTO v_var, v_game
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     ORDER BY cv.id LIMIT 1;

    IF v_owner IS NULL OR v_lang IS NULL OR v_var IS NULL OR v_game IS NULL THEN
        RAISE EXCEPTION
          'FIXTURE ABORT — Catalogo minimo ausente (owner=%, lang=%, variant=%, game=%). O harness NAO fabrica Catalogo.',
          v_owner, v_lang, v_var, v_game;
    END IF;

    INSERT INTO public.inventory (owner_user_id) VALUES (v_owner)
    ON CONFLICT (owner_user_id) DO NOTHING;
    SELECT id INTO v_inv FROM public.inventory WHERE owner_user_id = v_owner;

    INSERT INTO public.storage_container (inventory_id, name)
    VALUES (v_inv, '__5820_sc__') RETURNING id INTO v_sc;

    INSERT INTO public.collection
        (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    VALUES (v_owner, v_game, v_sc, '__5820_coll__', 'OPEN_CURATION', 'NONE')
    RETURNING id INTO v_coll;

    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_var, v_lang, v_inv) RETURNING id INTO v_pc;

    INSERT INTO _fx VALUES ('owner',v_owner),('inv',v_inv),('sc',v_sc),
                           ('coll',v_coll),('pc',v_pc);

    PERFORM pg_temp._rec('F','F01 - fixture minima criada (inventory, storage container, collection, physical card)',
        v_inv IS NOT NULL AND v_sc IS NOT NULL AND v_coll IS NOT NULL AND v_pc IS NOT NULL,
        format('inv=%s sc=%s coll=%s pc=%s', v_inv, v_sc, v_coll, v_pc),
        'todos nao nulos');
END $blk$;

-- =================================================================
-- GRUPO G — COMPORTAMENTO REAL DAS TRES RPCs
--
-- NENHUM caso isolado prova o fechamento do bypass. O papel de cada
-- peça está declarado no rótulo:
--   *_500        regressao do caminho feliz;
--   *_501rep     condicao NECESSARIA, nao suficiente;
--   *_501dist    cap antecede o resolve de ownership;
--   *_MULTI600   PROVA do fechamento (array_length(x,1)=2, card=600);
--   *_MULTI10    contrato de FORMA, nao so de tamanho;
--   *_VAZIO      mensagem de vazio, nao de dimensao.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_sc UUID; v_coll UUID; v_pc UUID;
    v_500 UUID[]; v_501 UUID[]; v_501d UUID[]; v_md600 UUID[]; v_md10 UUID[];
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_sc    FROM _fx WHERE k='sc';
    SELECT v INTO v_coll  FROM _fx WHERE k='coll';
    SELECT v INTO v_pc    FROM _fx WHERE k='pc';

    v_500   := array_fill(v_pc, ARRAY[500]);
    v_501   := array_fill(v_pc, ARRAY[501]);
    v_md600 := array_fill(v_pc, ARRAY[2, 300]);
    v_md10  := array_fill(v_pc, ARRAY[2, 5]);
    SELECT array_agg(gen_random_uuid()) INTO v_501d FROM generate_series(1, 501);

    PERFORM pg_temp._rec('G','G00 - fixture de payloads: multidimensional engana array_length(x,1) mas nao cardinality()',
        array_length(v_500,1) = 500
        AND array_length(v_501,1) = 501
        AND array_length(v_501d,1) = 501
        AND array_ndims(v_md600) = 2
        AND array_length(v_md600, 1) = 2
        AND cardinality(v_md600) = 600
        AND cardinality(v_md10) = 10,
        format('500=%s 501=%s 501d=%s | md600: ndims=%s dim1=%s card=%s | md10 card=%s',
               array_length(v_500,1), array_length(v_501,1), array_length(v_501d,1),
               array_ndims(v_md600), array_length(v_md600,1), cardinality(v_md600),
               cardinality(v_md10)),
        '500/501/501 e md600 com ndims=2, dim1=2, card=600');

    PERFORM pg_temp._as_user(v_owner);

    -- ---------------- set_physical_cards_storage -----------------
    PERFORM pg_temp._expect_ok('G','G01 - set_physical_cards_storage_500: lote de 500 ACEITO (regressao do caminho feliz)',
        format('SELECT * FROM public.set_physical_cards_storage(%L::uuid, %L::uuid[])', v_sc, v_500));

    PERFORM pg_temp._expect_error('G','G02 - set_physical_cards_storage_501rep: 501 repetidos rejeitado [necessario, nao suficiente]',
        format('SELECT * FROM public.set_physical_cards_storage(%L::uuid, %L::uuid[])', v_sc, v_501),
        'limite de 500');

    PERFORM pg_temp._expect_error('G','G03 - set_physical_cards_storage_501dist: 501 distintos rejeitado pelo cap, nao por not-found',
        format('SELECT * FROM public.set_physical_cards_storage(%L::uuid, %L::uuid[])', v_sc, v_501d),
        'limite de 500');

    PERFORM pg_temp._expect_error('G','G04 - set_physical_cards_storage_MULTI600: multidimensional dim1=2 card=600 REJEITADO [PROVA do fechamento]',
        format('SELECT * FROM public.set_physical_cards_storage(%L::uuid, %L::uuid[])', v_sc, v_md600),
        'unidimensional');

    PERFORM pg_temp._expect_error('G','G05 - set_physical_cards_storage_MULTI10: multidimensional pequeno REJEITADO [contrato de forma]',
        format('SELECT * FROM public.set_physical_cards_storage(%L::uuid, %L::uuid[])', v_sc, v_md10),
        'unidimensional');

    PERFORM pg_temp._expect_error('G','G06 - set_physical_cards_storage_VAZIO: array vazio produz mensagem de vazio, nao de dimensao',
        format('SELECT * FROM public.set_physical_cards_storage(%L::uuid, ARRAY[]::uuid[])', v_sc),
        'nao pode ser vazio');

    -- --------- allocate_physical_cards_to_collection -------------
    PERFORM pg_temp._expect_ok('G','G11 - allocate_500: lote de 500 ACEITO (regressao do caminho feliz)',
        format('SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])', v_coll, v_500));

    PERFORM pg_temp._expect_error('G','G12 - allocate_501rep: 501 repetidos rejeitado [necessario, nao suficiente]',
        format('SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])', v_coll, v_501),
        'limite de 500');

    PERFORM pg_temp._expect_error('G','G13 - allocate_501dist: 501 distintos rejeitado pelo cap, nao por not-found',
        format('SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])', v_coll, v_501d),
        'limite de 500');

    PERFORM pg_temp._expect_error('G','G14 - allocate_MULTI600: multidimensional dim1=2 card=600 REJEITADO [PROVA do fechamento]',
        format('SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])', v_coll, v_md600),
        'unidimensional');

    PERFORM pg_temp._expect_error('G','G15 - allocate_MULTI10: multidimensional pequeno REJEITADO [contrato de forma]',
        format('SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, %L::uuid[])', v_coll, v_md10),
        'unidimensional');

    PERFORM pg_temp._expect_error('G','G16 - allocate_VAZIO: array vazio produz mensagem de vazio, nao de dimensao',
        format('SELECT * FROM public.allocate_physical_cards_to_collection(%L::uuid, ARRAY[]::uuid[])', v_coll),
        'nao pode ser vazio');

    -- -------- deallocate_physical_cards_from_collection ----------
    -- Rodam DEPOIS do allocate: o caminho feliz exige a Allocation viva.
    PERFORM pg_temp._expect_error('G','G22 - deallocate_501rep: 501 repetidos rejeitado [necessario, nao suficiente]',
        format('SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, %L::uuid[])', v_coll, v_501),
        'limite de 500');

    PERFORM pg_temp._expect_error('G','G23 - deallocate_501dist: 501 distintos rejeitado pelo cap, nao por not-found',
        format('SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, %L::uuid[])', v_coll, v_501d),
        'limite de 500');

    PERFORM pg_temp._expect_error('G','G24 - deallocate_MULTI600: multidimensional dim1=2 card=600 REJEITADO [PROVA do fechamento]',
        format('SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, %L::uuid[])', v_coll, v_md600),
        'unidimensional');

    PERFORM pg_temp._expect_error('G','G25 - deallocate_MULTI10: multidimensional pequeno REJEITADO [contrato de forma]',
        format('SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, %L::uuid[])', v_coll, v_md10),
        'unidimensional');

    PERFORM pg_temp._expect_error('G','G26 - deallocate_VAZIO: array vazio produz mensagem de vazio, nao de dimensao',
        format('SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, ARRAY[]::uuid[])', v_coll),
        'nao pode ser vazio');

    -- Caminho feliz do deallocate por ultimo: remove a Allocation.
    PERFORM pg_temp._expect_ok('G','G21 - deallocate_500: lote de 500 ACEITO (regressao do caminho feliz)',
        format('SELECT * FROM public.deallocate_physical_cards_from_collection(%L::uuid, %L::uuid[])', v_coll, v_500));

    PERFORM pg_temp._as_admin();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('G','G-ABORT - grupo G abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo G completo');
END $blk$;

-- =================================================================
-- GRUPO E — EFEITO REAL. O multidimensional foi rejeitado ANTES de
-- qualquer escrita? Nenhuma Allocation pode ter sobrado.
-- =================================================================
DO $blk$
DECLARE
    v_coll UUID; v_pc UUID; v_n INTEGER; v_sc_now UUID;
BEGIN
    SELECT v INTO v_coll FROM _fx WHERE k='coll';
    SELECT v INTO v_pc   FROM _fx WHERE k='pc';

    SELECT count(*) INTO v_n
      FROM public.collection_allocation WHERE collection_id = v_coll;
    PERFORM pg_temp._rec('E','E01 - apos G21, zero Allocation remanescente na Collection de teste',
        v_n = 0, v_n::text, '0');

    SELECT storage_container_id INTO v_sc_now
      FROM public.physical_card WHERE id = v_pc;
    PERFORM pg_temp._rec('E','E02 - a Physical Card manteve o Storage Container atribuido por G01 (payloads rejeitados nao escreveram)',
        v_sc_now IS NOT NULL AND v_sc_now = (SELECT v FROM _fx WHERE k='sc'),
        COALESCE(v_sc_now::text,'NULL'), (SELECT v::text FROM _fx WHERE k='sc'));
END $blk$;

-- =================================================================
-- GRUPO S — STATIC PROOF FAIL-CLOSED (mesmo formato do B10 do 5818)
--
-- Comentarios removidos do pg_get_functiondef antes da busca (bloco,
-- depois linha). Busca literal com position(). Exige a cadeia
--   IF cap < RAISE EXCEPTION < mensagem < 1o unnest/DISTINCT
-- e nao apenas a presenca da string de erro.
-- =================================================================
DO $blk$
DECLARE
    f RECORD;
    v_exec TEXT; v_seg TEXT;
    v_pos_card INTEGER; v_pos_ndims INTEGER; v_pos_cap INTEGER;
    v_pos_unnest INTEGER; v_pos_distinct INTEGER; v_first_scan INTEGER;
    v_rel_raise INTEGER; v_rel_msg INTEGER;
    v_bad TEXT := ''; v_missing TEXT := ''; v_found BOOLEAN;
    t TEXT;
    v_names TEXT[] := ARRAY['set_physical_cards_storage',
                            'allocate_physical_cards_to_collection',
                            'deallocate_physical_cards_from_collection'];
BEGIN
    FOREACH t IN ARRAY v_names LOOP
        v_found := FALSE;
        FOR f IN
            SELECT p.oid, p.proname
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname = t
        LOOP
            v_found := TRUE;
            v_exec := regexp_replace(
                        regexp_replace(COALESCE(pg_get_functiondef(f.oid), ''),
                                       '/\*.*?\*/', ' ', 'gs'),
                        '--.*$', ' ', 'gn');

            v_pos_card  := position('cardinality(p_physical_card_ids)' in v_exec);
            v_pos_ndims := position('array_ndims(p_physical_card_ids) <> 1' in v_exec);
            v_pos_cap   := position('v_raw_count > 500' in v_exec);

            v_pos_unnest   := position('unnest(' in v_exec);
            v_pos_distinct := position('DISTINCT' in v_exec);
            v_first_scan := LEAST(
                CASE WHEN v_pos_unnest   = 0 THEN 2147483647 ELSE v_pos_unnest   END,
                CASE WHEN v_pos_distinct = 0 THEN 2147483647 ELSE v_pos_distinct END);

            v_rel_raise := 0; v_rel_msg := 0;
            IF v_pos_cap > 0 AND v_first_scan < 2147483647 AND v_first_scan > v_pos_cap THEN
                v_seg := substr(v_exec, v_pos_cap, v_first_scan - v_pos_cap);
                v_rel_raise := position('RAISE EXCEPTION' in v_seg);
                v_rel_msg   := position('lote excede o limite de 500 itens por chamada' in v_seg);
            END IF;

            IF v_pos_card = 0
               OR v_pos_ndims = 0
               OR v_pos_cap = 0
               OR v_first_scan = 2147483647
               OR position('array_length' in v_exec) > 0
               OR v_rel_raise = 0
               OR v_rel_msg = 0
               OR v_rel_msg < v_rel_raise
               OR NOT (v_pos_card  < v_pos_cap
                   AND v_pos_ndims < v_first_scan
                   AND v_pos_cap   < v_first_scan) THEN
                v_bad := v_bad || format(
                    '%s(card=%s,ndims=%s,cap=%s,raise_rel=%s,msg_rel=%s,first_scan=%s,array_length=%s) ',
                    f.proname, v_pos_card, v_pos_ndims, v_pos_cap,
                    v_rel_raise, v_rel_msg, v_first_scan,
                    position('array_length' in v_exec));
            END IF;
        END LOOP;
        IF NOT v_found THEN
            v_missing := v_missing || t || ' ';
        END IF;
    END LOOP;

    PERFORM pg_temp._rec('S','S01 - STATIC PROOF FAIL-CLOSED: nas 3 RPCs, IF cap < RAISE EXCEPTION < mensagem < 1o unnest/DISTINCT; cardinality e ndims presentes; zero array_length',
        v_missing = '' AND v_bad = '',
        CASE WHEN v_missing <> '' THEN 'FUNCAO AUSENTE: '||v_missing
             WHEN v_bad = ''      THEN 'as 3 conformes'
             ELSE 'INCORRETO em: '||v_bad END,
        'cadeia completa nas 3');

    -- S02: contrato de seguranca preservado pelo CREATE OR REPLACE.
    -- §2 CORRECAO 05: `search_path` provado EFETIVAMENTE vazio, nao
    -- apenas presente — `search_path=public` reprova.
    SELECT count(*) INTO v_pos_card
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname = ANY (v_names)
       AND p.prosecdef
       AND pg_temp._empty_search_path(p.oid)
       AND pg_get_userbyid(p.proowner) = 'postgres';
    PERFORM pg_temp._rec('S','S02 - as 3 continuam SECURITY DEFINER, search_path EFETIVAMENTE vazio, owner postgres',
        v_pos_card = 3, v_pos_card::text, '3');

    -- S03: grants inalterados — authenticated sim, anon nao.
    SELECT count(*) INTO v_pos_card
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname = ANY (v_names)
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
       AND NOT has_function_privilege('anon', p.oid, 'EXECUTE');
    PERFORM pg_temp._rec('S','S03 - as 3 mantem EXECUTE para authenticated e negam para anon',
        v_pos_card = 3, v_pos_card::text, '3');
END $blk$;

-- =================================================================
-- ZERO RESÍDUO
-- =================================================================
DO $blk$
DECLARE v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM public.collection WHERE name LIKE '\_\_5820\_%';
    PERFORM pg_temp._rec('X','X01 - fixture existe DENTRO da transacao (sera descartada no ROLLBACK)',
        v_n = 1, v_n::text, '1');

    PERFORM pg_temp._rec('X','X02 - EVIDENCIA ESTATICA: o arquivo termina em ROLLBACK e nao contem COMMIT (nao e prova de zero residuo pos-rollback)',
        TRUE,
        'zero residuo REAL exige postcheck pos-execucao',
        'ROLLBACK presente no arquivo');
END $blk$;

-- =================================================================
-- RELATÓRIO FINAL — PROTOCOLO EM DUAS CHAMADAS.
--   CALL 1: tudo desde BEGIN; ate o SELECT abaixo, INCLUSIVE.
--   CALL 2: ROLLBACK;
-- v1.2: no canal execute_sql a sessao NAO persiste entre chamadas —
-- a CALL 1 encerra com ROLLBACK IMPLICITO e a CALL 2 e confirmacao
-- explicita (no-op). Zero residuo depende de o arquivo nao ter COMMIT.
--
-- passed=TRUE -> PASS | FALSE -> FAIL | NULL -> NOT PROVEN
--
-- GATE OFICIAL (v1.2): TOTAL 27 / PASS 27 / FAIL 0 / NOT PROVEN 0.
-- 28 e a contagem de ROTULOS ESTATICOS; o 28o (`G-ABORT`) e ramo de
-- excecao fail-only e mutuamente exclusivo. Ver o cabecalho.
-- =================================================================
SELECT
    COALESCE(grp, 'TOTAL')                                   AS grp,
    count(*)                                                 AS total,
    count(*) FILTER (WHERE passed IS TRUE)                   AS passed,
    count(*) FILTER (WHERE passed IS FALSE)                  AS failed,
    count(*) FILTER (WHERE passed IS NULL)                   AS not_proven,
    string_agg(case_label || ' >> ' || COALESCE(observed,''), ' || ')
        FILTER (WHERE passed IS FALSE)                       AS failing_cases
FROM _v
GROUP BY ROLLUP (grp)
ORDER BY (grp IS NULL), grp;

ROLLBACK;
