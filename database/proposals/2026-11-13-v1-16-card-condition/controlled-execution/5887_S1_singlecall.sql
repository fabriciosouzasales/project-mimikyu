/*
================================================================
DERIVADO — NÃO EDITAR À MÃO (gerado por controlled-execution/derive_singlecall.py)
Harness....: 5887 recorte S1
Origem.....: proposals/2026-11-13-v1-16-card-condition/5887_validate_physical_card_condition_HARNESS.sql
SHA-256 origem: e0eac79266e525afc44213a94874dbe2baff9e896fa8f12d7d9c53867a861dd1
Grupos.....: X01 + F + A
Gate.......: TOTAL 9 / PASS 9 / FAIL 0 / NOT PROVEN 0
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
-- RELATÓRIO FINAL — CHAMADA ÚNICA (derivado): RAISE EXCEPTION aborta a
-- transação por construção. Gate idêntico ao da origem: count(*) = 9 AND fail = 0.
-- ================================================================
DO $REPORT$
DECLARE v_total INT; v_pass INT; v_fail INT; v_gate BOOLEAN; v_bl TEXT; v_failing TEXT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed)
      INTO v_total, v_pass, v_fail FROM _r;
    v_gate := (v_total = 9 AND v_fail = 0);
    SELECT string_agg(k || '=' || n, ' ' ORDER BY k) INTO v_bl FROM _bl;
    SELECT string_agg(format('%s | %s' || E'\n      got : %s' || E'\n      want: %s',
                             grp, label, coalesce(got, '<null>'), coalesce(want, '<null>')),
                      E'\n' ORDER BY grp, label)
      INTO v_failing FROM _r WHERE NOT passed;
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = format(
        E'\n============== 5887 S1 — CHAMADA ÚNICA ==============\n'
        'TOTAL=%s  PASS=%s  FAIL=%s  NOT PROVEN=0\n'
        'GATE ESPERADO: 9/9/0/0   ->   GATE_OK = %s\n'
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
