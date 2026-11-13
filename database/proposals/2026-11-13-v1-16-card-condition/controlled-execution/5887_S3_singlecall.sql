/*
================================================================
DERIVADO — NÃO EDITAR À MÃO (gerado por controlled-execution/derive_singlecall.py)
Harness....: 5887 recorte S3
Origem.....: proposals/2026-11-13-v1-16-card-condition/5887_validate_physical_card_condition_HARNESS.sql
SHA-256 origem: e0eac79266e525afc44213a94874dbe2baff9e896fa8f12d7d9c53867a861dd1
Grupos.....: X01 + F + A + B + C + X02
Gate.......: TOTAL 41 / PASS 41 / FAIL 0 / NOT PROVEN 0
Transporte.: CHAMADA ÚNICA. O relatório chega como ERRO 55000 (RAISE
             EXCEPTION). Erro 55000 com GATE_OK = true é o resultado de
             SUCESSO. Não existe COMMIT neste arquivo.
Canal......: psql -X -v ON_ERROR_STOP=1 -f <arquivo>  (ver
             CONTROLLED-EXECUTION-PROTOCOL.md). NUNCA apply_migration.
             NUNCA SQL Editor do Supabase.
Cabeçalho original (linhas 1–51) omitido; leia-o na origem.
================================================================
*/

BEGIN;

-- ================================================================
-- INFRAESTRUTURA
-- ================================================================
CREATE TEMP TABLE _r (grp TEXT NOT NULL, label TEXT NOT NULL, passed BOOLEAN NOT NULL, got TEXT, want TEXT) ON COMMIT DROP;
CREATE TEMP TABLE _bl (k TEXT PRIMARY KEY, n BIGINT NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;
CREATE TEMP TABLE _tx (k TEXT PRIMARY KEY, v TEXT) ON COMMIT DROP;

CREATE FUNCTION pg_temp._rec(p_grp TEXT, p_label TEXT, p_passed BOOLEAN, p_got TEXT, p_want TEXT)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO _r (grp, label, passed, got, want) VALUES (p_grp, p_label, COALESCE(p_passed, FALSE), p_got, p_want);
$$;

CREATE FUNCTION pg_temp._expect_error(p_grp TEXT, p_label TEXT, p_sql TEXT, p_needle TEXT, p_sqlstate TEXT DEFAULT '22023')
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp._rec(p_grp, p_label, FALSE, 'NAO levantou excecao',
            format('excecao SQLSTATE %s contendo: %s', p_sqlstate, p_needle));
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM; v_state := SQLSTATE;
    END;
    PERFORM pg_temp._rec(p_grp, p_label, position(p_needle in v_msg) > 0 AND v_state = p_sqlstate,
        format('SQLSTATE=%s | %s', v_state, v_msg), format('excecao SQLSTATE %s contendo: %s', p_sqlstate, p_needle));
END;
$$;

CREATE FUNCTION pg_temp._as(p_uid UUID) RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, TRUE);
$$;
CREATE FUNCTION pg_temp._anon() RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims', '{}', TRUE);
$$;
CREATE FUNCTION pg_temp._fx(p_k TEXT) RETURNS UUID LANGUAGE sql STABLE AS $$ SELECT v FROM _fx WHERE k = p_k; $$;
CREATE FUNCTION pg_temp._tx(p_k TEXT) RETURNS TEXT LANGUAGE sql STABLE AS $$ SELECT v FROM _tx WHERE k = p_k; $$;

-- Item B1, com condição opcional (NULL = chave ausente).
CREATE FUNCTION pg_temp._it(p_cv UUID, p_lang UUID, p_qty INT, p_cond TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('card_variant_id', p_cv::text, 'language_id', p_lang::text, 'quantity', p_qty)
           || CASE WHEN p_cond IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('condition_code', p_cond) END;
$$;
CREATE FUNCTION pg_temp._prev1(p_items JSONB) RETURNS JSONB LANGUAGE sql AS $$
    SELECT public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS', 'items', p_items));
$$;
-- Confirmação B1 com fingerprint explícito (o fingerprint é estado do mundo).
CREATE FUNCTION pg_temp._reg1(p_key UUID, p_fp TEXT, p_items JSONB) RETURNS JSONB LANGUAGE sql AS $$
    SELECT public.register_physical_cards_bulk(jsonb_build_object(
        'idempotency_key', p_key::text, 'preview_fingerprint', p_fp, 'items', p_items));
$$;
CREATE FUNCTION pg_temp._prev2(p_set UUID, p_lang UUID, p_cond TEXT DEFAULT NULL) RETURNS JSONB LANGUAGE sql AS $$
    SELECT public.preview_bulk_operation(jsonb_build_object(
        'operation_type', 'REGISTER_CARD_SET', 'card_set_id', p_set::text, 'language_id', p_lang::text)
        || CASE WHEN p_cond IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('condition_code', p_cond) END);
$$;
CREATE FUNCTION pg_temp._reg2(p_key UUID, p_fp TEXT, p_set UUID, p_lang UUID, p_cond TEXT DEFAULT NULL) RETURNS JSONB LANGUAGE sql AS $$
    SELECT public.register_card_set_bulk(jsonb_build_object(
        'idempotency_key', p_key::text, 'preview_fingerprint', p_fp, 'card_set_id', p_set::text, 'language_id', p_lang::text)
        || CASE WHEN p_cond IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('condition_code', p_cond) END);
$$;
-- Condições dos exemplares criados por uma confirmação (ordenadas).
CREATE FUNCTION pg_temp._conds(p_res JSONB) RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT string_agg(pc.condition_code, ',' ORDER BY pc.condition_code)
      FROM jsonb_array_elements_text(p_res -> 'result_summary' -> 'physical_card_ids') AS x(id)
      JOIN public.physical_card pc ON pc.id = x.id::uuid;
$$;
CREATE FUNCTION pg_temp._has_issue(p_res JSONB, p_code TEXT) RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(p_res -> 'issues') AS i(e)
                    WHERE i.e ->> 'code' = p_code AND i.e ->> 'severity' = 'BLOCKING');
$$;
CREATE FUNCTION pg_temp._empty_search_path(p_oid OID) RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_elem TEXT;
BEGIN
    SELECT c INTO v_elem FROM pg_proc p, unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS c
     WHERE p.oid = p_oid AND c LIKE 'search_path=%' LIMIT 1;
    IF v_elem IS NULL THEN RETURN FALSE; END IF;
    RETURN btrim(COALESCE(substring(v_elem from length('search_path=') + 1), ''), '''" ') = '';
END; $fn$;
CREATE FUNCTION pg_temp._pc_count() RETURNS BIGINT LANGUAGE sql STABLE AS $$ SELECT count(*) FROM public.physical_card; $$;

-- ================================================================
-- X01 — BASELINE, antes de qualquer escrita
-- ================================================================
INSERT INTO _bl (k, n)
SELECT 'bulk_operation', count(*) FROM public.bulk_operation
UNION ALL SELECT 'physical_card',         count(*) FROM public.physical_card
UNION ALL SELECT 'collection_allocation', count(*) FROM public.collection_allocation
UNION ALL SELECT 'inventory',             count(*) FROM public.inventory
UNION ALL SELECT 'expansion',             count(*) FROM public.expansion
UNION ALL SELECT 'card_set',              count(*) FROM public.card_set
UNION ALL SELECT 'card',                  count(*) FROM public.card
UNION ALL SELECT 'card_variant',          count(*) FROM public.card_variant;

DO $X1$
BEGIN
    PERFORM pg_temp._rec('X','X01 - baseline das 8 tabelas capturado antes de qualquer escrita',
        (SELECT count(*) FROM _bl) = 8, (SELECT string_agg(k || '=' || n, ' ' ORDER BY k) FROM _bl), '8 contagens');
END;
$X1$;

-- ================================================================
-- GRUPO F — FIXTURES
-- ================================================================
DO $F1$
DECLARE
    v_game UUID; v_rar UUID; v_cat UUID; v_std UUID; v_exp UUID; v_code TEXT; v_ord INT; v_s UUID;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_rar  FROM public.rarity WHERE game_id = v_game AND code = 'COMMON';
    SELECT id INTO v_cat  FROM public.card_category WHERE game_id = v_game AND code = 'POKEMON';
    SELECT id INTO v_std  FROM public.card_variant_type WHERE game_id = v_game AND code = 'STANDARD';
    v_code := 'ZZV116_' || upper(substr(md5(clock_timestamp()::text || random()::text), 1, 10));
    SELECT COALESCE(max(release_order), 0) + 1000 INTO v_ord FROM public.expansion WHERE game_id = v_game;

    INSERT INTO public.expansion (game_id, code, name, release_order)
    VALUES (v_game, v_code, 'V116 HARNESS EXPANSION', v_ord) RETURNING id INTO v_exp;
    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_exp, 'ZZV116-S', 'V116 S', 'REGULAR', 1, 2, 2) RETURNING id INTO v_s;
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name, is_active)
    SELECT v_s, v_rar, v_cat, 'S' || n, 2, n, 'V116 S' || n, TRUE FROM generate_series(1, 2) AS n;
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active)
    SELECT ca.id, v_std, 1, TRUE, TRUE FROM public.card ca WHERE ca.card_set_id = v_s;

    INSERT INTO _fx (k, v) VALUES
        ('game', v_game), ('set_s', v_s),
        ('cv_a', (SELECT cv.id FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id WHERE ca.card_set_id = v_s AND ca.collector_number = 'S1')),
        ('cv_b', (SELECT cv.id FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id WHERE ca.card_set_id = v_s AND ca.collector_number = 'S2')),
        ('lang', (SELECT id FROM public.language ORDER BY id LIMIT 1));
    INSERT INTO _tx (k, v) VALUES ('lang_code', (SELECT code FROM public.language WHERE id = pg_temp._fx('lang')));

    PERFORM pg_temp._rec('F','F01 - catalogo sintetico: um Set com 2 Cards ativos, variante STANDARD padrao',
        pg_temp._fx('cv_a') IS NOT NULL AND pg_temp._fx('cv_b') IS NOT NULL AND pg_temp._fx('lang') IS NOT NULL,
        NULL, 'cv_a, cv_b e lang definidos');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - catalogo sintetico abortou', FALSE, SQLERRM, 'sem excecao');
END;
$F1$;

DO $F2$
DECLARE v_u1 UUID; v_u2 UUID; v_inv1 UUID; v_inv2 UUID;
BEGIN
    SELECT id INTO v_u1 FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_u2 FROM auth.users WHERE id <> v_u1 ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_inv1 FROM public.inventory WHERE owner_user_id = v_u1;
    IF v_inv1 IS NULL THEN INSERT INTO public.inventory (owner_user_id) VALUES (v_u1) RETURNING id INTO v_inv1; END IF;
    SELECT id INTO v_inv2 FROM public.inventory WHERE owner_user_id = v_u2;
    IF v_inv2 IS NULL THEN INSERT INTO public.inventory (owner_user_id) VALUES (v_u2) RETURNING id INTO v_inv2; END IF;
    INSERT INTO _fx (k, v) VALUES ('u1', v_u1), ('u2', v_u2), ('inv1', v_inv1), ('inv2', v_inv2);
    PERFORM pg_temp._rec('F','F02 - dois usuarios distintos com inventory',
        v_u1 IS NOT NULL AND v_u2 IS NOT NULL AND v_u1 <> v_u2 AND v_inv1 IS NOT NULL AND v_inv2 IS NOT NULL, NULL, 'u1 <> u2');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - usuarios abortou', FALSE, SQLERRM, 'sem excecao');
END;
$F2$;

-- ================================================================
-- GRUPO A — S1 (5361)
-- ================================================================
DO $A$
DECLARE v_typ TEXT; v_nn BOOLEAN; v_def TEXT; v_fk TEXT; v_val BOOLEAN; v_codes TEXT;
BEGIN
    SELECT format_type(a.atttypid, a.atttypmod), a.attnotnull, pg_get_expr(ad.adbin, ad.adrelid)
      INTO v_typ, v_nn, v_def
      FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
     WHERE a.attrelid = 'public.physical_card'::regclass AND a.attname = 'condition_code' AND NOT a.attisdropped;
    PERFORM pg_temp._rec('A','A01 - condition_code text NOT NULL DEFAULT NM',
        v_typ = 'text' AND v_nn AND v_def = '''NM''::text', format('%s %s %s', v_typ, v_nn, v_def), 'text true ''NM''::text');

    SELECT pg_get_constraintdef(c.oid), c.convalidated INTO v_fk, v_val
      FROM pg_constraint c WHERE c.conrelid = 'public.physical_card'::regclass AND c.conname = 'fk_physical_card_condition_code';
    PERFORM pg_temp._rec('A','A02 - FK validada para card_condition(code), RESTRICT/RESTRICT',
        v_val AND replace(v_fk, 'public.', '') = 'FOREIGN KEY (condition_code) REFERENCES card_condition(code) ON UPDATE RESTRICT ON DELETE RESTRICT',
        format('%s validada=%s', v_fk, v_val), 'FK validada');

    SELECT string_agg(code || ':' || condition_order, ',' ORDER BY condition_order) INTO v_codes FROM public.card_condition;
    PERFORM pg_temp._rec('A','A03 - escala canonica intacta: M,NM,LP,MP,HP,DMG (1..6)',
        v_codes = 'M:1,NM:2,LP:3,MP:4,HP:5,DMG:6', v_codes, 'M:1,NM:2,LP:3,MP:4,HP:5,DMG:6');

    PERFORM pg_temp._rec('A','A04 - todo exemplar com codigo existente na escala',
        NOT EXISTS (SELECT 1 FROM public.physical_card pc LEFT JOIN public.card_condition cc ON cc.code = pc.condition_code WHERE cc.code IS NULL),
        NULL, 'zero orfaos');

    -- Protecao EFETIVA contra escrita direta: RLS ligada e nenhuma politica que
    -- autorize INSERT/UPDATE/DELETE (ou ALL). Privilegio de tabela (GRANT) nao e o
    -- criterio: com RLS ligada e sem politica de escrita, a escrita direta de
    -- cliente e negada mesmo havendo privilegio. A condicao so muda pela 5364.
    PERFORM pg_temp._rec('A','A05 - physical_card: RLS ligada e nenhuma politica de escrita direta (so SELECT do dono)',
        (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.physical_card'::regclass)
        AND NOT EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public' AND tablename = 'physical_card'
                           AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL'))
        AND EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname = 'public' AND tablename = 'physical_card' AND cmd = 'SELECT'),
        (SELECT string_agg(policyname || ':' || cmd, ', ' ORDER BY policyname) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'physical_card'),
        'RLS on; politicas so SELECT');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('A','A-ABORT - grupo A abortou', FALSE, SQLERRM, 'sem excecao');
END;
$A$;

-- A06 — FK recusa codigo fora da escala (escrita direta como postgres, desfeita pelo ROLLBACK).
DO $A6$
DECLARE v_state TEXT := 'sem excecao';
BEGIN
    BEGIN
        INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id, condition_code)
        VALUES (pg_temp._fx('cv_a'), pg_temp._fx('lang'), pg_temp._fx('inv1'), 'SP');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    PERFORM pg_temp._rec('A','A06 - FK recusa rotulo de exibicao gravado como codigo (SP) com 23503', v_state = '23503', v_state, '23503');
END;
$A6$;

-- ================================================================
-- GRUPO B — S2 (5362)
-- ================================================================
DO $B0$
DECLARE v_ok BOOLEAN;
BEGIN
    PERFORM pg_temp._rec('B','B01 - corpos de 5153/5155/5157/5158 = versao 5362 (md5)',
        (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)')) = '86426fc066009400748cfccdf1fbf322'
        AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.register_physical_cards_bulk(jsonb)')) = 'd08dcc259222a286d99bcd53f9da7285'
        AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.register_card_set_bulk(jsonb)')) = '83cd76fcb38a41a3a2c0a77d36fa4196'
        AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.preview_bulk_operation(jsonb)')) = '99f7b2e2a723d599e06ef2e7ca9b1831',
        NULL, 'quatro md5 da 5362');
    v_ok := to_regprocedure('public.physical_card_unknown_condition_codes(text[])') IS NOT NULL
        AND NOT has_function_privilege('authenticated', 'public.physical_card_unknown_condition_codes(text[])', 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.physical_card_unknown_condition_codes(text[])', 'EXECUTE')
        AND NOT has_function_privilege('service_role', 'public.physical_card_unknown_condition_codes(text[])', 'EXECUTE');
    PERFORM pg_temp._rec('B','B02 - validacao unica existe e e interna (sem EXECUTE para clientes)', v_ok, NULL, 'interna');
    PERFORM pg_temp._rec('B','B03 - validacao: escala aceita os 6; recusa SP, DM, nm e nulo',
        public.physical_card_unknown_condition_codes(ARRAY['M','NM','LP','MP','HP','DMG']) IS NULL
        AND (SELECT string_agg(x, ',' ORDER BY x COLLATE "C")
               FROM unnest(public.physical_card_unknown_condition_codes(ARRAY['SP','DM','nm',NULL,'NM'])) AS x) = '<null>,DM,SP,nm',
        array_to_string(public.physical_card_unknown_condition_codes(ARRAY['SP','DM','nm',NULL,'NM']), ','), '<null>,DM,SP,nm (como conjunto)');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('B','B0-ABORT - estrutura B abortou', FALSE, SQLERRM, 'sem excecao');
END;
$B0$;

DO $B04$
DECLARE v_state TEXT := 'sem excecao';
BEGIN
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM public.physical_card_unknown_condition_codes(ARRAY['NM']);
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    RESET ROLE;
    PERFORM pg_temp._rec('B','B04 - authenticated chamando a validacao recebe 42501 em runtime', v_state = '42501', v_state, '42501');
END;
$B04$;

DO $B1$
DECLARE
    a UUID := pg_temp._fx('cv_a'); b UUID := pg_temp._fx('cv_b'); l UUID := pg_temp._fx('lang');
    v_fp TEXT; v_fp_lp TEXT; v_fp_b TEXT; v_fp_ab TEXT;
    v_res JSONB; v_res2 JSONB; v_key UUID; v_cnt BIGINT; v_hash TEXT; v_legacy TEXT;
    v_call TEXT := 'SELECT public.register_physical_cards_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    -- Fingerprint e estado do mundo: identico com e sem condicao.
    v_fp    := pg_temp._prev1(jsonb_build_array(pg_temp._it(a, l, 1))) ->> 'preview_fingerprint';
    v_fp_lp := pg_temp._prev1(jsonb_build_array(pg_temp._it(a, l, 1, 'LP'))) ->> 'preview_fingerprint';
    PERFORM pg_temp._rec('B','B05 - preview_fingerprint independe da condicao (5149 intocada)',
        v_fp IS NOT NULL AND v_fp = v_fp_lp, format('%s / %s', v_fp, v_fp_lp), 'iguais');

    -- O fingerprint cobre o CATALOGO resolvido das cartas do pedido (5149): cada
    -- conjunto de cartas confirmado usa o fingerprint do proprio conjunto, senao a
    -- confirmacao para em PREVIEW_STALE antes da validacao que o caso quer provar.
    -- (Quantidade e condicao nao entram — sao intencao, D9.)
    v_fp_b  := pg_temp._prev1(jsonb_build_array(pg_temp._it(b, l, 1))) ->> 'preview_fingerprint';
    v_fp_ab := pg_temp._prev1(jsonb_build_array(pg_temp._it(a, l, 1), pg_temp._it(b, l, 1))) ->> 'preview_fingerprint';
    IF v_fp_b IS NULL OR v_fp_ab IS NULL THEN
        RAISE EXCEPTION 'fixture: preview sem fingerprint para [b] ou [a,b]';
    END IF;

    -- Pedido legado (sem a chave) grava NM.
    v_key := gen_random_uuid();
    v_res := pg_temp._reg1(v_key, v_fp, jsonb_build_array(pg_temp._it(a, l, 2)));
    INSERT INTO _tx VALUES ('b06_key', v_key::text), ('b06_ids', v_res -> 'result_summary' ->> 'physical_card_ids');
    PERFORM pg_temp._rec('B','B06 - B1 sem condition_code (pedido legado) grava NM nos 2 exemplares',
        v_res ->> 'outcome' = 'CREATED' AND pg_temp._conds(v_res) = 'NM,NM', pg_temp._conds(v_res), 'NM,NM');

    -- Hash historico preservado: mesma intencao serializada como a 5155 canonica.
    v_legacy := public.bulk_request_hash('REGISTER_PHYSICAL_CARDS', jsonb_build_object(
        'collection_id', NULL::text, 'storage_container_id', NULL::text,
        'items', jsonb_build_array(jsonb_build_object('card_variant_id', a::text, 'language_id', l::text, 'quantity', 2::bigint))));
    SELECT request_hash INTO v_hash FROM public.bulk_operation WHERE idempotency_key = v_key;
    PERFORM pg_temp._rec('B','B07 - request_hash de pedido NM = hash da intencao historica (byte a byte)',
        v_hash = v_legacy, format('%s / %s', v_hash, v_legacy), 'iguais');

    -- NM explicito = ausente: mesma chave devolve REPLAY, nao CONFLICT.
    v_res2 := pg_temp._reg1(v_key, v_fp, jsonb_build_array(pg_temp._it(a, l, 2, 'NM')));
    PERFORM pg_temp._rec('B','B08 - NM explicito com a mesma chave = REPLAY (equivalencia no hash)',
        v_res2 ->> 'outcome' = 'REPLAY', v_res2 ->> 'outcome', 'REPLAY');

    -- Condicao diferente com a mesma chave = CONFLICT.
    PERFORM pg_temp._expect_error('B','B09 - mesma chave com LP = BULK_IDEMPOTENCY_CONFLICT',
        format(v_call, jsonb_build_object('idempotency_key', v_key::text, 'preview_fingerprint', v_fp,
            'items', jsonb_build_array(pg_temp._it(a, l, 2, 'LP')))::text), 'BULK_IDEMPOTENCY_CONFLICT');

    -- Condicao informada e gravada; Mint aceito.
    v_res := pg_temp._reg1(gen_random_uuid(), v_fp_ab, jsonb_build_array(pg_temp._it(a, l, 1, 'LP'), pg_temp._it(b, l, 1, 'M')));
    PERFORM pg_temp._rec('B','B10 - B1 grava a condicao de cada linha (LP e M)',
        v_res ->> 'outcome' = 'CREATED' AND pg_temp._conds(v_res) = 'LP,M', pg_temp._conds(v_res), 'LP,M');

    -- Mesma variante/idioma com condicoes diferentes = linhas legitimas.
    v_res := pg_temp._reg1(gen_random_uuid(), v_fp, jsonb_build_array(pg_temp._it(a, l, 1), pg_temp._it(a, l, 2, 'HP')));
    PERFORM pg_temp._rec('B','B11 - mesmo par com NM e HP no mesmo pedido: 1 NM + 2 HP',
        v_res ->> 'outcome' = 'CREATED' AND pg_temp._conds(v_res) = 'HP,HP,NM', pg_temp._conds(v_res), 'HP,HP,NM');

    -- Duplicidade do trio, com NM explicito equivalente a ausente.
    v_cnt := pg_temp._pc_count();
    PERFORM pg_temp._expect_error('B','B12 - trio duplicado (ausente + NM explicito, mesmo par) e rejeitado',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text, 'preview_fingerprint', v_fp,
            'items', jsonb_build_array(pg_temp._it(a, l, 1), pg_temp._it(a, l, 1, 'NM')))::text), 'duplicado(s)');
    PERFORM pg_temp._expect_error('B','B13 - trio duplicado (LP + LP, UUID em caixa alta) e rejeitado',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text, 'preview_fingerprint', v_fp,
            'items', jsonb_build_array(pg_temp._it(a, l, 1, 'LP'),
                jsonb_build_object('card_variant_id', upper(a::text), 'language_id', l::text, 'quantity', 1, 'condition_code', 'LP')))::text),
        'duplicado(s)');

    -- Codigo desconhecido, minusculo, tipo errado e vazio.
    v_key := gen_random_uuid();
    PERFORM pg_temp._expect_error('B','B14 - codigo fora da escala (XX) = CONDITION_NOT_FOUND, sem escrita',
        format(v_call, jsonb_build_object('idempotency_key', v_key::text, 'preview_fingerprint', v_fp_b,
            'items', jsonb_build_array(pg_temp._it(b, l, 1, 'XX')))::text), 'CONDITION_NOT_FOUND');
    v_res := pg_temp._reg1(v_key, v_fp_b, jsonb_build_array(pg_temp._it(b, l, 1)));
    PERFORM pg_temp._rec('B','B15 - falha nao consome a chave nem grava (mesma chave cria depois; contagem so do pedido valido)',
        v_res ->> 'outcome' = 'CREATED' AND pg_temp._pc_count() = v_cnt + 1, format('%s %s', v_res ->> 'outcome', pg_temp._pc_count() - v_cnt), 'CREATED 1');
    PERFORM pg_temp._expect_error('B','B16 - codigo em minusculas (nm) = CONDITION_NOT_FOUND (sensivel a caixa)',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text, 'preview_fingerprint', v_fp_b,
            'items', jsonb_build_array(pg_temp._it(b, l, 1, 'nm')))::text), 'CONDITION_NOT_FOUND');
    PERFORM pg_temp._expect_error('B','B17 - condition_code numerico e rejeitado na estrutura',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text, 'preview_fingerprint', v_fp_b,
            'items', jsonb_build_array(jsonb_build_object('card_variant_id', b::text, 'language_id', l::text, 'quantity', 1, 'condition_code', 1)))::text),
        'condition_code, quando informado');
    PERFORM pg_temp._expect_error('B','B18 - chave desconhecida no item continua rejeitada',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text, 'preview_fingerprint', v_fp_b,
            'items', jsonb_build_array(pg_temp._it(b, l, 1) || '{"lixo":1}'::jsonb))::text),
        'cada item de items aceita exatamente as chaves');

    -- Preview B1.
    v_res := pg_temp._prev1(jsonb_build_array(pg_temp._it(a, l, 1, 'XX')));
    PERFORM pg_temp._rec('B','B19 - Preview B1: codigo fora da escala = ok=false com CONDITION_NOT_FOUND',
        (v_res ->> 'ok')::boolean IS FALSE AND pg_temp._has_issue(v_res, 'CONDITION_NOT_FOUND'), v_res::text, 'issue CONDITION_NOT_FOUND');
    v_res := pg_temp._prev1(jsonb_build_array(pg_temp._it(a, l, 1), pg_temp._it(a, l, 1, 'NM')));
    v_res2 := pg_temp._prev1(jsonb_build_array(pg_temp._it(a, l, 1), pg_temp._it(a, l, 1, 'LP')));
    PERFORM pg_temp._rec('B','B20 - Preview B1: trio duplicado = DUPLICATE_ITEM; NM+LP do mesmo par = ok, distinct_items 2',
        pg_temp._has_issue(v_res, 'DUPLICATE_ITEM') AND (v_res2 ->> 'ok')::boolean
        AND (v_res2 -> 'summary' ->> 'distinct_items')::int = 2,
        format('%s | %s', v_res -> 'issues', v_res2 -> 'summary'), 'DUPLICATE_ITEM; ok/2');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('B','B1-ABORT - casos B1 abortaram', FALSE, SQLERRM, 'sem excecao');
END;
$B1$;

DO $B2$
DECLARE
    s UUID := pg_temp._fx('set_s'); l UUID := pg_temp._fx('lang');
    v_fp TEXT; v_res JSONB; v_res2 JSONB; v_key UUID;
    v_call TEXT := 'SELECT public.register_card_set_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_fp := pg_temp._prev2(s, l) ->> 'preview_fingerprint';

    v_res := pg_temp._prev2(s, l, 'ZZ');
    PERFORM pg_temp._rec('B','B21 - Preview B2 com condicao fora da escala = ok=false com CONDITION_NOT_FOUND; HP = ok',
        (v_res ->> 'ok')::boolean IS FALSE AND pg_temp._has_issue(v_res, 'CONDITION_NOT_FOUND')
        AND (pg_temp._prev2(s, l, 'HP') ->> 'ok')::boolean,
        v_res -> 'issues' ->> 0, 'CONDITION_NOT_FOUND e HP ok');

    v_res := pg_temp._reg2(gen_random_uuid(), v_fp, s, l, 'HP');
    PERFORM pg_temp._rec('B','B22 - B2 com HP: todos os exemplares do Set em HP',
        v_res ->> 'outcome' = 'CREATED' AND pg_temp._conds(v_res) = 'HP,HP', pg_temp._conds(v_res), 'HP,HP');

    v_key := gen_random_uuid();
    v_res := pg_temp._reg2(v_key, v_fp, s, l);
    v_res2 := pg_temp._reg2(v_key, v_fp, s, l, 'NM');
    PERFORM pg_temp._rec('B','B23 - B2 sem condicao = NM; NM explicito com a mesma chave = REPLAY',
        v_res ->> 'outcome' = 'CREATED' AND pg_temp._conds(v_res) = 'NM,NM' AND v_res2 ->> 'outcome' = 'REPLAY',
        format('%s %s %s', v_res ->> 'outcome', pg_temp._conds(v_res), v_res2 ->> 'outcome'), 'CREATED NM,NM REPLAY');

    PERFORM pg_temp._expect_error('B','B24 - B2 condition_code nao-string e rejeitado na estrutura',
        format(v_call, (jsonb_build_object('idempotency_key', gen_random_uuid()::text, 'preview_fingerprint', v_fp,
            'card_set_id', s::text, 'language_id', l::text, 'condition_code', jsonb_build_array('NM')))::text),
        'condition_code, quando informado');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('B','B2-ABORT - casos B2 abortaram', FALSE, SQLERRM, 'sem excecao');
END;
$B2$;

-- ================================================================
-- GRUPO C — S3 (5363)
-- ================================================================
DO $C$
DECLARE
    v_oid OID := to_regprocedure('public.get_my_inventory_item_copies(uuid, text)');
    v_n INT; v_bad INT;
BEGIN
    PERFORM pg_temp._rec('C','C01 - retorno = 20 colunas da 5262 + condition_code ao final',
        pg_get_function_result(v_oid) = 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text, condition_code text)',
        pg_get_function_result(v_oid), '21 colunas');
    PERFORM pg_temp._rec('C','C02 - corpo = 5363 (md5), SECURITY DEFINER, search_path vazio',
        (SELECT md5(prosrc) FROM pg_proc WHERE oid = v_oid) = '77abbb9a33f2cb46280925bade22dee5'
        AND (SELECT prosecdef FROM pg_proc WHERE oid = v_oid)
        AND pg_temp._empty_search_path(v_oid),
        NULL, 'md5/definer/search_path');
    PERFORM pg_temp._rec('C','C03 - ACL: authenticated executa; anon nao',
        has_function_privilege('authenticated', v_oid, 'EXECUTE') AND NOT has_function_privilege('anon', v_oid, 'EXECUTE'), NULL, 'ACL');

    PERFORM pg_temp._as(pg_temp._fx('u1'));
    SELECT count(*), count(*) FILTER (WHERE r.condition_code IS DISTINCT FROM pc.condition_code)
      INTO v_n, v_bad
      FROM public.get_my_inventory_item_copies(pg_temp._fx('cv_a'), pg_temp._tx('lang_code')) r
      JOIN public.physical_card pc ON pc.id = r.physical_card_id;
    PERFORM pg_temp._rec('C','C04 - dono le a condicao de cada exemplar (igual a tabela)', v_n > 0 AND v_bad = 0, format('%s linhas, %s divergentes', v_n, v_bad), '>0 e 0');
    PERFORM pg_temp._rec('C','C05 - o grupo do u1 tem condicoes mistas visiveis (NM, LP, HP)',
        (SELECT count(DISTINCT r.condition_code) FROM public.get_my_inventory_item_copies(pg_temp._fx('cv_a'), pg_temp._tx('lang_code')) r) >= 3,
        NULL, '>= 3 condicoes');

    PERFORM pg_temp._as(pg_temp._fx('u2'));
    SELECT count(*) INTO v_n FROM public.get_my_inventory_item_copies(pg_temp._fx('cv_a'), pg_temp._tx('lang_code')) r
     WHERE r.physical_card_id IN (SELECT pc.id FROM public.physical_card pc WHERE pc.inventory_id = pg_temp._fx('inv1'));
    PERFORM pg_temp._rec('C','C06 - outro usuario nao enxerga exemplares (nem condicao) do u1', v_n = 0, v_n::text, '0');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('C','C-ABORT - grupo C abortou', FALSE, SQLERRM, 'sem excecao');
END;
$C$;

DO $C7$
BEGIN
    PERFORM pg_temp._anon();
    PERFORM pg_temp._expect_error('C','C07 - anonimo recebe 28000',
        format('SELECT * FROM public.get_my_inventory_item_copies(%L::uuid, %L)', pg_temp._fx('cv_a'), pg_temp._tx('lang_code')),
        'not_authenticated', '28000');
END;
$C7$;

-- ================================================================
-- X02 — houve escrita real (o ROLLBACK desfaz)
-- ================================================================
DO $X2$
BEGIN
    PERFORM pg_temp._rec('X','X02 - o harness escreveu de fato em physical_card (acima do baseline)',
        pg_temp._pc_count() > (SELECT n FROM _bl WHERE k = 'physical_card'),
        format('baseline=%s fim=%s', (SELECT n FROM _bl WHERE k = 'physical_card'), pg_temp._pc_count()), 'acima do baseline');
END;
$X2$;

-- ================================================================
-- RELATÓRIO FINAL — CHAMADA ÚNICA (derivado): RAISE EXCEPTION aborta a
-- transação por construção. Gate idêntico ao da origem: count(*) = 41 AND fail = 0.
-- ================================================================
DO $REPORT$
DECLARE v_total INT; v_pass INT; v_fail INT; v_gate BOOLEAN; v_bl TEXT; v_failing TEXT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed)
      INTO v_total, v_pass, v_fail FROM _r;
    v_gate := (v_total = 41 AND v_fail = 0);
    SELECT string_agg(k || '=' || n, ' ' ORDER BY k) INTO v_bl FROM _bl;
    SELECT string_agg(format('%s | %s' || E'\n      got : %s' || E'\n      want: %s',
                             grp, label, coalesce(got, '<null>'), coalesce(want, '<null>')),
                      E'\n' ORDER BY grp, label)
      INTO v_failing FROM _r WHERE NOT passed;
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = format(
        E'\n============== 5887 S3 — CHAMADA ÚNICA ==============\n'
        'TOTAL=%s  PASS=%s  FAIL=%s  NOT PROVEN=0\n'
        'GATE ESPERADO: 41/41/0/0   ->   GATE_OK = %s\n'
        'BASELINE: %s\n'
        'FALHAS:\n%s\n'
        'ROLLBACK GARANTIDO POR CONSTRUÇÃO (esta exceção aborta a transação).\n'
        '==============================================================',
        v_total, v_pass, v_fail, v_gate, v_bl, coalesce(v_failing, '(nenhuma)'));
END;
$REPORT$;

ROLLBACK;

-- ================================================================
-- CALL 3 — POSTCHECK BASELINE-RELATIVO (depois do ROLLBACK)
-- ================================================================
-- SELECT (SELECT count(*) FROM public.bulk_operation)        AS bulk_operation,
--        (SELECT count(*) FROM public.physical_card)         AS physical_card,
--        (SELECT count(*) FROM public.collection_allocation) AS collection_allocation,
--        (SELECT count(*) FROM public.inventory)             AS inventory,
--        (SELECT count(*) FROM public.expansion)             AS expansion,
--        (SELECT count(*) FROM public.card_set)              AS card_set,
--        (SELECT count(*) FROM public.card)                  AS card,
--        (SELECT count(*) FROM public.card_variant)          AS card_variant;
-- Critério: cada contagem IGUAL à coluna `baseline` da CALL 1.
