/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5826 - Harness funcional de BULK-04 (REGISTER_CARD_SET)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — offline e LIVE em 2026-10-16,
              apos 5153-5158: gate 56/56/0/0; residuo zero nas 12
              tabelas (postcheck externo).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Valida......: 5153, 5154, 5155, 5156, 5157, 5158
Pré-req.....: 5152 e 5153–5158 aplicadas, nesta ordem.

================================================================
GATE DE ACEITE
================================================================
    TOTAL 56 / PASS 56 / FAIL 0 / NOT PROVEN 0

    X (2)  baseline e escrita real
    F (2)  fixtures (catálogo sintético + usuário/destinos)
    E (7)  estrutura: atributos, fonte única, Preview consultivo
    S (6)  ACL e prova em runtime (42501) dos helpers internos
    G (8)  guards estruturais da confirmação (SQLSTATE verificado)
    V (12) Preview do B2: ok, issues, exceções, sem escrita, rótulo
    H (5)  caminho feliz: Set inteiro, variante padrão, duplicatas,
           Collection/Storage, Reference elegível
    I (3)  idempotência: REPLAY, CONFLICT, namespace por tipo
    K (10) PREVIEW_STALE e validações na confirmação
    A (1)  atomicidade: falhas não consomem a chave
                                                  ----
                                         TOTAL    56

Linhas "*-ABORT" são fail-only (só gravadas em EXCEPTION WHEN OTHERS).

================================================================
PROTOCOLO DE TRÊS CHAMADAS — mesmo de 5822
================================================================
    CALL 1 — do BEGIN; até o SELECT final, inclusive
    CALL 2 — ROLLBACK;
    CALL 3 — postcheck externo de ZERO RESÍDUO, igualdade com a
             coluna `baseline` da CALL 1, nas DOZE tabelas abaixo
             (as oito de 5822 mais expansion, card_set, card,
             card_variant, tocadas pelo catálogo sintético).

Executor: postgres (mesmo papel de 5822). Identidade do chamador
apenas por request.jwt.claims; SET LOCAL ROLE só em S06, para provar
AUSÊNCIA de acesso.

Catálogo sintético, criado e desfeito dentro da transação:
  Expansion ZZB04_<único> (Game POKEMON)
  ZZB04-S   : S1, S2, S3 ativos com STANDARD padrão; S2 tem também
              HOLO não padrão; S4 INATIVO com STANDARD padrão.
  ZZB04-N   : N1 ativo com padrão; N2 ativo SEM nenhuma variante.
  ZZB04-E   : sem Cards.
  ZZB04-O   : O1 ativo com padrão (Reference não elegível para S).
  ZZB04-BIG : 1001 Cards ativos com padrão (teto).
================================================================
*/

BEGIN;

-- ================================================================
-- INFRAESTRUTURA
-- ================================================================
CREATE TEMP TABLE _r (
    grp    TEXT    NOT NULL,
    label  TEXT    NOT NULL,
    passed BOOLEAN NOT NULL,
    got    TEXT,
    want   TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _bl (k TEXT PRIMARY KEY, n BIGINT NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;
CREATE TEMP TABLE _tx (k TEXT PRIMARY KEY, v TEXT) ON COMMIT DROP;

CREATE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN, p_got TEXT, p_want TEXT
) RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO _r (grp, label, passed, got, want)
    VALUES (p_grp, p_label, COALESCE(p_passed, FALSE), p_got, p_want);
$$;

CREATE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_needle TEXT,
    p_sqlstate TEXT DEFAULT '22023'
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'NAO levantou excecao',
            format('excecao SQLSTATE %s contendo: %s', p_sqlstate, p_needle));
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM; v_state := SQLSTATE;
    END;
    PERFORM pg_temp._rec(p_grp, p_label,
        position(p_needle in v_msg) > 0 AND v_state = p_sqlstate,
        format('SQLSTATE=%s | %s', v_state, v_msg),
        format('excecao SQLSTATE %s contendo: %s', p_sqlstate, p_needle));
END;
$$;

CREATE FUNCTION pg_temp._as(p_uid UUID) RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims',
        json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, TRUE);
$$;

CREATE FUNCTION pg_temp._anon() RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims', '{}', TRUE);
$$;

CREATE FUNCTION pg_temp._fx(p_k TEXT) RETURNS UUID LANGUAGE sql STABLE AS $$
    SELECT v FROM _fx WHERE k = p_k;
$$;

CREATE FUNCTION pg_temp._empty_search_path(p_oid OID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_elem TEXT; v_val TEXT;
BEGIN
    SELECT c INTO v_elem
      FROM pg_proc p, unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS c
     WHERE p.oid = p_oid AND c LIKE 'search_path=%'
     LIMIT 1;
    IF v_elem IS NULL THEN RETURN FALSE; END IF;
    v_val := substring(v_elem from length('search_path=') + 1);
    RETURN btrim(COALESCE(v_val, ''), '''" ') = '';
END; $fn$;

-- Envelope de Preview do B2.
CREATE FUNCTION pg_temp._preq(
    p_set UUID, p_lang UUID, p_col UUID DEFAULT NULL, p_stg UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'operation_type',       'REGISTER_CARD_SET',
        'card_set_id',          p_set::text,
        'language_id',          p_lang::text,
        'collection_id',        p_col::text,
        'storage_container_id', p_stg::text
    ));
$$;

-- Envelope de confirmação do B2.
CREATE FUNCTION pg_temp._creq(
    p_key UUID, p_fp TEXT, p_set UUID, p_lang UUID,
    p_col UUID DEFAULT NULL, p_stg UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'idempotency_key',      p_key::text,
        'preview_fingerprint',  p_fp,
        'card_set_id',          p_set::text,
        'language_id',          p_lang::text,
        'collection_id',        p_col::text,
        'storage_container_id', p_stg::text
    ));
$$;

CREATE FUNCTION pg_temp._has_issue(p_res JSONB, p_code TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_res -> 'issues') AS i(e)
         WHERE i.e ->> 'code' = p_code
           AND i.e ->> 'severity' = 'BLOCKING'
    );
$$;

CREATE FUNCTION pg_temp._pc_count() RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT count(*) FROM public.physical_card;
$$;

-- ================================================================
-- X01 — BASELINE das DOZE tabelas, antes de qualquer escrita.
-- ================================================================
INSERT INTO _bl (k, n)
SELECT 'bulk_operation',                  count(*) FROM public.bulk_operation
UNION ALL SELECT 'physical_card',                  count(*) FROM public.physical_card
UNION ALL SELECT 'collection_allocation',          count(*) FROM public.collection_allocation
UNION ALL SELECT 'collection',                     count(*) FROM public.collection
UNION ALL SELECT 'collection_reference',           count(*) FROM public.collection_reference
UNION ALL SELECT 'collection_card_set_reference',  count(*) FROM public.collection_card_set_reference
UNION ALL SELECT 'storage_container',              count(*) FROM public.storage_container
UNION ALL SELECT 'inventory',                      count(*) FROM public.inventory
UNION ALL SELECT 'expansion',                      count(*) FROM public.expansion
UNION ALL SELECT 'card_set',                       count(*) FROM public.card_set
UNION ALL SELECT 'card',                           count(*) FROM public.card
UNION ALL SELECT 'card_variant',                   count(*) FROM public.card_variant;

DO $X1$
BEGIN
    PERFORM pg_temp._rec('X','X01 - baseline das 12 tabelas capturado ANTES de qualquer escrita',
        (SELECT count(*) FROM _bl) = 12,
        (SELECT string_agg(k || '=' || n, ' ' ORDER BY k) FROM _bl),
        '12 contagens registradas');
END;
$X1$;

-- ================================================================
-- GRUPO F — FIXTURES
-- ================================================================
DO $F1$
DECLARE
    v_game UUID; v_rar UUID; v_cat UUID; v_std UUID; v_holo UUID;
    v_exp  UUID; v_code TEXT; v_ord INT;
    v_s UUID; v_n UUID; v_e UUID; v_o UUID; v_big UUID;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_rar  FROM public.rarity WHERE game_id = v_game AND code = 'COMMON';
    SELECT id INTO v_cat  FROM public.card_category WHERE game_id = v_game AND code = 'POKEMON';
    SELECT id INTO v_std  FROM public.card_variant_type WHERE game_id = v_game AND code = 'STANDARD';
    SELECT id INTO v_holo FROM public.card_variant_type WHERE game_id = v_game AND code = 'HOLO';

    v_code := 'ZZB04_' || upper(substr(md5(clock_timestamp()::text || random()::text), 1, 10));
    SELECT COALESCE(max(release_order), 0) + 1000 INTO v_ord
      FROM public.expansion WHERE game_id = v_game;

    INSERT INTO public.expansion (game_id, code, name, release_order)
    VALUES (v_game, v_code, 'BULK04 HARNESS EXPANSION', v_ord)
    RETURNING id INTO v_exp;

    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_exp, 'ZZB04-S',   'BULK04 S',   'REGULAR', 1, 4,    4)    RETURNING id INTO v_s;
    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_exp, 'ZZB04-N',   'BULK04 N',   'REGULAR', 2, 2,    2)    RETURNING id INTO v_n;
    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_exp, 'ZZB04-E',   'BULK04 E',   'REGULAR', 3, 1,    1)    RETURNING id INTO v_e;
    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_exp, 'ZZB04-O',   'BULK04 O',   'REGULAR', 4, 1,    1)    RETURNING id INTO v_o;
    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_exp, 'ZZB04-BIG', 'BULK04 BIG', 'REGULAR', 5, 1001, 1001) RETURNING id INTO v_big;

    -- S: S1..S3 ativos, S4 inativo.
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number,
                             collector_total, collector_order, name, is_active)
    SELECT v_s, v_rar, v_cat, 'S' || n, 4, n, 'BULK04 S' || n, (n <> 4)
      FROM generate_series(1, 4) AS n;
    -- N: N1 com variante, N2 sem nenhuma.
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number,
                             collector_total, collector_order, name, is_active)
    SELECT v_n, v_rar, v_cat, 'N' || n, 2, n, 'BULK04 N' || n, TRUE
      FROM generate_series(1, 2) AS n;
    -- O: O1.
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number,
                             collector_total, collector_order, name, is_active)
    VALUES (v_o, v_rar, v_cat, 'O1', 1, 1, 'BULK04 O1', TRUE);
    -- BIG: 1001 ativos.
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number,
                             collector_total, collector_order, name, is_active)
    SELECT v_big, v_rar, v_cat, 'G' || n, 1001, n, 'BULK04 G' || n, TRUE
      FROM generate_series(1, 1001) AS n;

    -- Variante padrao STANDARD: todos os Cards de S, O, BIG e N1.
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active)
    SELECT ca.id, v_std, 1, TRUE, TRUE
      FROM public.card ca
     WHERE ca.card_set_id IN (v_s, v_o, v_big)
        OR (ca.card_set_id = v_n AND ca.collector_number = 'N1');
    -- HOLO nao padrao em S2.
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active)
    SELECT ca.id, v_holo, 2, FALSE, TRUE
      FROM public.card ca
     WHERE ca.card_set_id = v_s AND ca.collector_number = 'S2';

    INSERT INTO _fx (k, v) VALUES
        ('game', v_game), ('set_s', v_s), ('set_n', v_n), ('set_e', v_e),
        ('set_o', v_o), ('set_big', v_big),
        ('card_s3', (SELECT id FROM public.card WHERE card_set_id = v_s AND collector_number = 'S3')),
        ('card_n2', (SELECT id FROM public.card WHERE card_set_id = v_n AND collector_number = 'N2')),
        ('cv_s4',   (SELECT cv.id FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id
                      WHERE ca.card_set_id = v_s AND ca.collector_number = 'S4')),
        ('cv_holo', (SELECT cv.id FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id
                      WHERE ca.card_set_id = v_s AND ca.collector_number = 'S2' AND NOT cv.is_default)),
        ('lang',    (SELECT id FROM public.language ORDER BY id LIMIT 1));
    INSERT INTO _tx (k, v) VALUES ('rar', v_rar::text), ('cat', v_cat::text), ('std', v_std::text);

    PERFORM pg_temp._rec('F','F01 - catalogo sintetico: S=4 (1 inativo, 1 HOLO extra), N=2 (1 sem variante), E=0, O=1, BIG=1001, padroes conforme o desenho',
        (SELECT count(*) FROM public.card WHERE card_set_id = v_s) = 4
        AND (SELECT count(*) FROM public.card WHERE card_set_id = v_s AND is_active) = 3
        AND (SELECT count(*) FROM public.card WHERE card_set_id = v_n) = 2
        AND (SELECT count(*) FROM public.card WHERE card_set_id = v_e) = 0
        AND (SELECT count(*) FROM public.card WHERE card_set_id = v_o) = 1
        AND (SELECT count(*) FROM public.card WHERE card_set_id = v_big) = 1001
        AND (SELECT count(*) FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id
              WHERE ca.card_set_id = v_s AND cv.is_default) = 4
        AND NOT EXISTS (SELECT 1 FROM public.card_variant WHERE card_id = pg_temp._fx('card_n2'))
        AND pg_temp._fx('cv_holo') IS NOT NULL AND pg_temp._fx('lang') IS NOT NULL,
        NULL, 'contagens do desenho');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - catalogo sintetico abortou', FALSE, SQLERRM, 'sem excecao');
END;
$F1$;

DO $F2$
DECLARE
    v_u1 UUID; v_u2 UUID; v_inv UUID; v_sc1 UUID;
    v_open UUID; v_ref_s UUID; v_ref_o UUID; v_arch UUID;
BEGIN
    SELECT id INTO v_u1 FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_u2 FROM auth.users WHERE id <> v_u1 ORDER BY created_at, id LIMIT 1;

    PERFORM pg_temp._as(v_u1);

    SELECT inv.id INTO v_inv FROM public.inventory inv WHERE inv.owner_user_id = v_u1;
    IF v_inv IS NULL THEN
        INSERT INTO public.inventory (owner_user_id) VALUES (v_u1) RETURNING id INTO v_inv;
    END IF;

    SELECT s.id INTO v_sc1 FROM public.create_storage_container('BULK04 HARNESS SC1') s;

    SELECT c.id INTO v_open
      FROM public.create_collection(pg_temp._fx('game'), 'BULK04 HARNESS OPEN', NULL, v_sc1) c;
    SELECT c.id INTO v_arch
      FROM public.create_collection(pg_temp._fx('game'), 'BULK04 HARNESS ARCHIVED', NULL, v_sc1) c;
    PERFORM public.archive_collection(v_arch);
    SELECT c.id INTO v_ref_s
      FROM public.create_reference_based_card_set_collection(
               pg_temp._fx('game'), 'BULK04 HARNESS REF S', NULL, v_sc1, pg_temp._fx('set_s')) c;
    SELECT c.id INTO v_ref_o
      FROM public.create_reference_based_card_set_collection(
               pg_temp._fx('game'), 'BULK04 HARNESS REF O', NULL, v_sc1, pg_temp._fx('set_o')) c;

    INSERT INTO _fx (k, v) VALUES
        ('u1', v_u1), ('u2', v_u2), ('inv1', v_inv), ('sc1', v_sc1),
        ('col_open', v_open), ('col_arch', v_arch), ('col_ref_s', v_ref_s), ('col_ref_o', v_ref_o);

    PERFORM pg_temp._rec('F','F02 - fixtures patrimoniais pelas RPCs canonicas (inventory, storage, collection aberta, arquivada e duas REFERENCE_BASED)',
        v_u1 IS NOT NULL AND v_inv IS NOT NULL AND v_sc1 IS NOT NULL AND v_open IS NOT NULL
        AND v_arch IS NOT NULL AND v_ref_s IS NOT NULL AND v_ref_o IS NOT NULL
        AND (SELECT lifecycle_status FROM public.collection WHERE id = v_arch) <> 'ACTIVE',
        NULL, 'todos NOT NULL e arquivada <> ACTIVE');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - fixtures patrimoniais abortaram', FALSE, SQLERRM, 'sem excecao');
END;
$F2$;

-- ================================================================
-- GRUPO E — ESTRUTURA
-- ================================================================
DO $E$
DECLARE
    o57 OID; o56 OID; o54 OID; o53 OID; o50 OID; o51 OID;
    s57 TEXT; s53 TEXT; s50 TEXT; s51 TEXT;
BEGIN
    o57 := to_regprocedure('public.register_card_set_bulk(jsonb)');
    o56 := to_regprocedure('public.preview_fingerprint_register_card_set(uuid,uuid,uuid,uuid)');
    o54 := to_regprocedure('public.bulk_expand_card_set(uuid,uuid)');
    o53 := to_regprocedure('public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)');
    o50 := to_regprocedure('public.register_physical_cards_bulk(jsonb)');
    o51 := to_regprocedure('public.preview_bulk_operation(jsonb)');
    SELECT prosrc INTO s57 FROM pg_proc WHERE oid = o57;
    SELECT prosrc INTO s53 FROM pg_proc WHERE oid = o53;
    SELECT prosrc INTO s50 FROM pg_proc WHERE oid = o50;
    SELECT prosrc INTO s51 FROM pg_proc WHERE oid = o51;

    PERFORM pg_temp._rec('E','E01 - register_card_set_bulk: 1 sobrecarga (p_request jsonb) -> jsonb, SECURITY DEFINER, owner postgres, search_path vazio',
        o57 IS NOT NULL
        AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'register_card_set_bulk') = 1
        AND pg_get_function_identity_arguments(o57) = 'p_request jsonb'
        AND pg_get_function_result(o57) = 'jsonb'
        AND (SELECT prosecdef AND pg_get_userbyid(proowner) = 'postgres' FROM pg_proc WHERE oid = o57)
        AND pg_temp._empty_search_path(o57),
        NULL, 'assinatura e atributos');

    PERFORM pg_temp._rec('E','E02 - preview_fingerprint_register_card_set: INVOKER, VOLATILE, owner postgres, search_path vazio',
        o56 IS NOT NULL
        AND (SELECT NOT prosecdef AND provolatile = 'v' AND pg_get_userbyid(proowner) = 'postgres' FROM pg_proc WHERE oid = o56)
        AND pg_temp._empty_search_path(o56), NULL, 'atributos');

    PERFORM pg_temp._rec('E','E03 - bulk_expand_card_set: INVOKER, VOLATILE, owner postgres, search_path vazio',
        o54 IS NOT NULL
        AND (SELECT NOT prosecdef AND provolatile = 'v' AND pg_get_userbyid(proowner) = 'postgres' FROM pg_proc WHERE oid = o54)
        AND pg_temp._empty_search_path(o54), NULL, 'atributos');

    PERFORM pg_temp._rec('E','E04 - bulk_register_physical_card_items: INVOKER, VOLATILE, owner postgres, search_path vazio',
        o53 IS NOT NULL
        AND (SELECT NOT prosecdef AND provolatile = 'v' AND pg_get_userbyid(proowner) = 'postgres' FROM pg_proc WHERE oid = o53)
        AND pg_temp._empty_search_path(o53), NULL, 'atributos');

    PERFORM pg_temp._rec('E','E05 - helper 5153 valida CARD_VARIANT_INACTIVE ANTES do INSERT em physical_card e nao tem lock proprio',
        position('CARD_VARIANT_INACTIVE' in s53) > 0
        AND position('CARD_VARIANT_INACTIVE' in s53) < position('INSERT INTO public.physical_card' in s53)
        AND position('FOR UPDATE' in s53) = 0 AND position('FOR SHARE' in s53) = 0,
        format('check=%s insert=%s', position('CARD_VARIANT_INACTIVE' in s53),
               position('INSERT INTO public.physical_card' in s53)), 'check < insert, sem lock');

    PERFORM pg_temp._rec('E','E06 - FONTE UNICA: B1 (5150) e B2 chamam o helper 5153 e o 5148, sem INSERT proprio em physical_card e sem lock proprio',
        position('bulk_register_physical_card_items' in s50) > 0
        AND position('bulk_register_physical_card_items' in s57) > 0
        AND position('bulk_lock_operation_scope' in s50) > 0
        AND position('bulk_lock_operation_scope' in s57) > 0
        AND position('INSERT INTO public.physical_card' in s50) = 0
        AND position('INSERT INTO public.physical_card' in s57) = 0
        AND position('FOR UPDATE' in s50) = 0 AND position('FOR SHARE' in s50) = 0
        AND position('FOR UPDATE' in s57) = 0 AND position('FOR SHARE' in s57) = 0,
        NULL, 'uma implementacao de validacao e escrita');

    PERFORM pg_temp._rec('E','E07 - Preview (5151) suporta REGISTER_CARD_SET via 5154/5156 e continua sem DML e sem lock',
        position('bulk_expand_card_set' in s51) > 0
        AND position('preview_fingerprint_register_card_set' in s51) > 0
        AND position('insert into' in lower(s51)) = 0 AND position('update public' in lower(s51)) = 0
        AND position('delete from' in lower(s51)) = 0 AND position('for update' in lower(s51)) = 0
        AND position('for share' in lower(s51)) = 0,
        NULL, 'consultivo');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('E','E-ABORT - grupo E abortou', FALSE, SQLERRM, 'sem excecao');
END;
$E$;

-- ================================================================
-- GRUPO S — ACL
-- ================================================================
DO $S$
DECLARE o57 OID; v_ok BOOLEAN := TRUE; f OID; r TEXT;
BEGIN
    o57 := to_regprocedure('public.register_card_set_bulk(jsonb)');

    PERFORM pg_temp._rec('S','S01 - authenticated TEM EXECUTE em register_card_set_bulk',
        has_function_privilege('authenticated', o57, 'EXECUTE'), NULL, 'true');
    PERFORM pg_temp._rec('S','S02 - anon NAO tem EXECUTE em register_card_set_bulk',
        NOT has_function_privilege('anon', o57, 'EXECUTE'), NULL, 'false');
    PERFORM pg_temp._rec('S','S03 - service_role NAO tem EXECUTE em register_card_set_bulk',
        NOT has_function_privilege('service_role', o57, 'EXECUTE'), NULL, 'false');
    PERFORM pg_temp._rec('S','S04 - PUBLIC NAO tem EXECUTE em register_card_set_bulk (proacl NOT NULL, sem grantee 0)',
        (SELECT p.proacl IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                                 WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
           FROM pg_proc p WHERE p.oid = o57), NULL, 'sem PUBLIC');

    FOREACH f IN ARRAY ARRAY[
        to_regprocedure('public.preview_fingerprint_register_card_set(uuid,uuid,uuid,uuid)'),
        to_regprocedure('public.bulk_expand_card_set(uuid,uuid)'),
        to_regprocedure('public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)')]::oid[] LOOP
        FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            IF f IS NULL OR has_function_privilege(r, f, 'EXECUTE') THEN v_ok := FALSE; END IF;
        END LOOP;
        IF f IS NULL OR (SELECT p.proacl IS NULL
                                OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                                            WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
                           FROM pg_proc p WHERE p.oid = f) THEN
            v_ok := FALSE;
        END IF;
    END LOOP;
    PERFORM pg_temp._rec('S','S05 - os tres helpers internos (5154, 5156, 5153) sem EXECUTE para PUBLIC, anon, authenticated e service_role',
        v_ok, NULL, 'helpers fechados');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('S','S-ABORT - grupo S abortou', FALSE, SQLERRM, 'sem excecao');
END;
$S$;

-- S06 — prova em RUNTIME. Unico SET ROLE do arquivo.
DO $S6$
DECLARE v_state TEXT := 'sem excecao';
BEGIN
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM public.bulk_register_physical_card_items(
            '[]'::jsonb, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0);
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
    END;
    RESET ROLE;
    PERFORM pg_temp._rec('S','S06 - authenticated chamando o helper de escrita recebe 42501 (nao alcancavel fora das RPCs)',
        v_state = '42501', v_state, '42501');
END;
$S6$;

-- ================================================================
-- GRUPO G — GUARDS DA CONFIRMACAO
-- ================================================================
DO $G$
DECLARE
    v_set TEXT := pg_temp._fx('set_s')::text;
    v_lang TEXT := pg_temp._fx('lang')::text;
    v_call TEXT := 'SELECT public.register_card_set_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    PERFORM pg_temp._expect_error('G','G01 - p_request nao-objeto e recusado',
        format(v_call, '[]'), 'p_request deve ser um objeto JSON');

    PERFORM pg_temp._expect_error('G','G02 - chave items (do B1) e recusada pelo envelope FECHADO do B2',
        format(v_call, (pg_temp._creq(gen_random_uuid(), 'fp', v_set::uuid, v_lang::uuid)
                        || '{"items":[]}'::jsonb)::text),
        'p_request aceita exatamente as chaves idempotency_key, preview_fingerprint, card_set_id, language_id');

    PERFORM pg_temp._expect_error('G','G03 - sem card_set_id e recusado',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text,
                                          'preview_fingerprint', 'fp', 'language_id', v_lang)::text),
        'p_request exige idempotency_key, preview_fingerprint, card_set_id e language_id');

    PERFORM pg_temp._expect_error('G','G04 - sem language_id (idioma unico obrigatorio) e recusado',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text,
                                          'preview_fingerprint', 'fp', 'card_set_id', v_set)::text),
        'p_request exige idempotency_key, preview_fingerprint, card_set_id e language_id');

    PERFORM pg_temp._expect_error('G','G05 - card_set_id invalido e recusado',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text,
                                          'preview_fingerprint', 'fp', 'card_set_id', 'nao-e-uuid',
                                          'language_id', v_lang)::text),
        'card_set_id deve ser um UUID valido');

    PERFORM pg_temp._expect_error('G','G06 - language_id invalido e recusado',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text,
                                          'preview_fingerprint', 'fp', 'card_set_id', v_set,
                                          'language_id', 'nao-e-uuid')::text),
        'language_id deve ser um UUID valido');

    PERFORM pg_temp._expect_error('G','G07 - preview_fingerprint em branco e recusado',
        format(v_call, pg_temp._creq(gen_random_uuid(), '   ', v_set::uuid, v_lang::uuid)::text),
        'preview_fingerprint e obrigatorio e nao pode ser vazio');

    PERFORM pg_temp._anon();
    PERFORM pg_temp._expect_error('G','G08 - sem auth.uid() a chamada e recusada com SQLSTATE 28000',
        format(v_call, pg_temp._creq(gen_random_uuid(), 'fp', v_set::uuid, v_lang::uuid)::text),
        'authentication required', '28000');
    PERFORM pg_temp._as(pg_temp._fx('u1'));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('G','G-ABORT - grupo G abortou', FALSE, SQLERRM, 'sem excecao');
END;
$G$;

-- ================================================================
-- GRUPO V — PREVIEW DO B2
-- ================================================================
DO $V$
DECLARE
    v_set UUID := pg_temp._fx('set_s');
    v_lang UUID := pg_temp._fx('lang');
    v_res JSONB; v_pc0 BIGINT; v_bo0 BIGINT; v_exp RECORD; v_b1fp TEXT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_pc0 := pg_temp._pc_count();
    SELECT count(*) INTO v_bo0 FROM public.bulk_operation;

    v_res := public.preview_bulk_operation(pg_temp._preq(v_set, v_lang));
    INSERT INTO _tx (k, v) VALUES ('fp_s', v_res ->> 'preview_fingerprint');

    PERFORM pg_temp._rec('V','V01 - Preview do Set S: ok=true, fingerprint presente, issues vazio, operation_type REGISTER_CARD_SET',
        (v_res ->> 'ok')::boolean AND btrim(COALESCE(v_res ->> 'preview_fingerprint', '')) <> ''
        AND jsonb_array_length(v_res -> 'issues') = 0
        AND v_res ->> 'operation_type' = 'REGISTER_CARD_SET',
        v_res::text, 'ok=true');

    PERFORM pg_temp._rec('V','V02 - summary: 3 Cards ativos expandidos (S4 inativo fora), 3 a criar, card_set_id e language_id ecoados',
        (v_res -> 'summary' ->> 'distinct_items')::int = 3
        AND (v_res -> 'summary' ->> 'will_create_count')::int = 3
        AND v_res -> 'summary' ->> 'card_set_id' = v_set::text
        AND v_res -> 'summary' ->> 'language_id' = v_lang::text,
        (v_res -> 'summary')::text, 'distinct=3 create=3');

    v_res := public.preview_bulk_operation(pg_temp._preq(gen_random_uuid(), v_lang));
    PERFORM pg_temp._rec('V','V03 - Card Set inexistente vira CARD_SET_NOT_FOUND, ok=false, fingerprint null',
        pg_temp._has_issue(v_res, 'CARD_SET_NOT_FOUND') AND NOT (v_res ->> 'ok')::boolean
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null', v_res::text, 'CARD_SET_NOT_FOUND');

    v_res := public.preview_bulk_operation(pg_temp._preq(pg_temp._fx('set_e'), v_lang));
    PERFORM pg_temp._rec('V','V04 - Set sem Card ativo vira CARD_SET_EMPTY, fingerprint null',
        pg_temp._has_issue(v_res, 'CARD_SET_EMPTY') AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        v_res::text, 'CARD_SET_EMPTY');

    v_res := public.preview_bulk_operation(pg_temp._preq(pg_temp._fx('set_n'), v_lang));
    PERFORM pg_temp._rec('V','V05 - Card ativo sem variante padrao vira CARD_DEFAULT_VARIANT_MISSING com o card_id em offenders',
        pg_temp._has_issue(v_res, 'CARD_DEFAULT_VARIANT_MISSING')
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_res -> 'issues') i(e), jsonb_array_elements_text(i.e -> 'offenders') o(x)
                     WHERE i.e ->> 'code' = 'CARD_DEFAULT_VARIANT_MISSING' AND o.x = pg_temp._fx('card_n2')::text)
        AND NOT (v_res ->> 'ok')::boolean, v_res::text, 'N2 em offenders');

    v_res := public.preview_bulk_operation(pg_temp._preq(v_set, gen_random_uuid()));
    PERFORM pg_temp._rec('V','V06 - idioma inexistente vira LANGUAGE_NOT_FOUND (reuso do Preview do B1)',
        pg_temp._has_issue(v_res, 'LANGUAGE_NOT_FOUND') AND NOT (v_res ->> 'ok')::boolean,
        v_res::text, 'LANGUAGE_NOT_FOUND');

    v_res := public.preview_bulk_operation(pg_temp._preq(v_set, v_lang, pg_temp._fx('col_arch')));
    PERFORM pg_temp._rec('V','V07 - Collection arquivada vira COLLECTION_ARCHIVED',
        pg_temp._has_issue(v_res, 'COLLECTION_ARCHIVED'), v_res::text, 'COLLECTION_ARCHIVED');

    v_res := public.preview_bulk_operation(pg_temp._preq(v_set, v_lang, pg_temp._fx('col_ref_o')));
    PERFORM pg_temp._rec('V','V08 - Collection REFERENCE_BASED de outro Set vira NOT_ELIGIBLE_FOR_REFERENCE',
        pg_temp._has_issue(v_res, 'NOT_ELIGIBLE_FOR_REFERENCE'), v_res::text, 'NOT_ELIGIBLE_FOR_REFERENCE');

    PERFORM pg_temp._expect_error('V','V09 - envelope do B2 com items e recusado (contrato fechado proprio)',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               (pg_temp._preq(v_set, v_lang) || '{"items":[]}'::jsonb)::text),
        'p_request aceita exatamente as chaves operation_type, card_set_id, language_id');

    PERFORM pg_temp._expect_error('V','V10 - Set com 1001 Cards ativos e recusado pelo teto, com a mesma mensagem da confirmacao',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq(pg_temp._fx('set_big'), v_lang)::text),
        'a operacao criaria 1001 Physical Cards e excede o limite de 1000');

    PERFORM pg_temp._rec('V','V11 - Preview nao escreveu nada (physical_card e bulk_operation inalterados)',
        pg_temp._pc_count() = v_pc0 AND (SELECT count(*) FROM public.bulk_operation) = v_bo0,
        format('pc %s->%s', v_pc0, pg_temp._pc_count()), 'inalterados');

    SELECT e.o_items, e.o_cards_without_default INTO v_exp FROM public.bulk_expand_card_set(v_set, v_lang) e;
    v_b1fp := public.preview_fingerprint_register_physical_cards(v_exp.o_items);
    INSERT INTO _tx (k, v) VALUES ('fp_b1_of_s', v_b1fp);
    PERFORM pg_temp._rec('V','V12 - fingerprint do B2 difere do fingerprint do B1 sobre os mesmos itens (rotulo proprio)',
        v_b1fp IS DISTINCT FROM (SELECT v FROM _tx WHERE k = 'fp_s'), NULL, 'diferentes');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('V','V-ABORT - grupo V abortou', FALSE, SQLERRM, 'sem excecao');
END;
$V$;

-- ================================================================
-- GRUPO H — CAMINHO FELIZ
-- ================================================================
DO $H$
DECLARE
    v_set UUID := pg_temp._fx('set_s');
    v_lang UUID := pg_temp._fx('lang');
    v_key UUID := gen_random_uuid();
    v_out JSONB; v_ids UUID[]; v_fp TEXT;
    v_defaults UUID[];
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    INSERT INTO _fx (k, v) VALUES ('key_h1', v_key);

    v_out := public.register_card_set_bulk(
                 pg_temp._creq(v_key, (SELECT v FROM _tx WHERE k = 'fp_s'), v_set, v_lang));
    INSERT INTO _tx (k, v) VALUES ('out_h1', v_out::text);
    SELECT array_agg(x::uuid) INTO v_ids
      FROM jsonb_array_elements_text(v_out -> 'result_summary' -> 'physical_card_ids') x;

    PERFORM pg_temp._rec('H','H01 - confirmacao do Set S: CREATED, 3 Physical Cards, distinct_items 3',
        v_out ->> 'outcome' = 'CREATED'
        AND (v_out -> 'result_summary' ->> 'created_count')::int = 3
        AND (v_out -> 'result_summary' ->> 'distinct_items')::int = 3
        AND cardinality(v_ids) = 3
        AND v_out -> 'result_summary' ->> 'operation_type' = 'REGISTER_CARD_SET',
        v_out::text, 'CREATED/3');

    SELECT array_agg(cv.id ORDER BY cv.id) INTO v_defaults
      FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id
     WHERE ca.card_set_id = v_set AND ca.is_active AND cv.is_default;

    PERFORM pg_temp._rec('H','H02 - as 3 cartas usam EXATAMENTE as variantes padrao dos Cards ativos (sem S4 inativo, sem HOLO), no idioma e Inventory do chamador',
        (SELECT array_agg(pc.card_variant_id ORDER BY pc.card_variant_id)
           FROM public.physical_card pc WHERE pc.id = ANY (v_ids)) = v_defaults
        AND NOT EXISTS (SELECT 1 FROM public.physical_card pc WHERE pc.id = ANY (v_ids)
                         AND pc.card_variant_id IN (pg_temp._fx('cv_s4'), pg_temp._fx('cv_holo')))
        AND NOT EXISTS (SELECT 1 FROM public.physical_card pc WHERE pc.id = ANY (v_ids)
                         AND (pc.language_id <> v_lang OR pc.inventory_id <> pg_temp._fx('inv1'))),
        NULL, 'padroes dos ativos');

    -- Set inteiro de novo, inclusive cartas ja possuidas (Q4).
    v_out := public.register_card_set_bulk(
                 pg_temp._creq(gen_random_uuid(), (SELECT v FROM _tx WHERE k = 'fp_s'), v_set, v_lang));
    PERFORM pg_temp._rec('H','H03 - segunda operacao (outra chave) cria o Set inteiro de novo: duplicatas permitidas, 6 cartas nas variantes padrao',
        v_out ->> 'outcome' = 'CREATED' AND (v_out -> 'result_summary' ->> 'created_count')::int = 3
        AND (SELECT count(*) FROM public.physical_card pc
              WHERE pc.inventory_id = pg_temp._fx('inv1') AND pc.card_variant_id = ANY (v_defaults)) >= 6,
        v_out::text, 'CREATED/3, total >= 6');

    v_fp := public.preview_bulk_operation(
                pg_temp._preq(v_set, v_lang, pg_temp._fx('col_open'), pg_temp._fx('sc1'))) ->> 'preview_fingerprint';
    v_out := public.register_card_set_bulk(
                 pg_temp._creq(gen_random_uuid(), v_fp, v_set, v_lang, pg_temp._fx('col_open'), pg_temp._fx('sc1')));
    SELECT array_agg(x::uuid) INTO v_ids
      FROM jsonb_array_elements_text(v_out -> 'result_summary' -> 'physical_card_ids') x;
    PERFORM pg_temp._rec('H','H04 - com Collection e Storage: 3 alocadas e 3 no Storage, numa unica operacao',
        v_out ->> 'outcome' = 'CREATED'
        AND (v_out -> 'result_summary' ->> 'allocated_count')::int = 3
        AND (SELECT count(*) FROM public.collection_allocation ca
              WHERE ca.collection_id = pg_temp._fx('col_open') AND ca.physical_card_id = ANY (v_ids)) = 3
        AND (SELECT count(*) FROM public.physical_card pc
              WHERE pc.id = ANY (v_ids) AND pc.storage_container_id = pg_temp._fx('sc1')) = 3,
        v_out::text, 'alocadas=3 storage=3');

    v_fp := public.preview_bulk_operation(
                pg_temp._preq(v_set, v_lang, pg_temp._fx('col_ref_s'))) ->> 'preview_fingerprint';
    v_out := public.register_card_set_bulk(
                 pg_temp._creq(gen_random_uuid(), v_fp, v_set, v_lang, pg_temp._fx('col_ref_s')));
    PERFORM pg_temp._rec('H','H05 - Collection REFERENCE_BASED do proprio Set S e elegivel: CREATED com 3 alocadas',
        v_out ->> 'outcome' = 'CREATED' AND (v_out -> 'result_summary' ->> 'allocated_count')::int = 3,
        v_out::text, 'CREATED/alocadas=3');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('H','H-ABORT - grupo H abortou', FALSE, SQLERRM, 'sem excecao');
END;
$H$;

-- ================================================================
-- GRUPO I — IDEMPOTENCIA
-- ================================================================
DO $I$
DECLARE
    v_set UUID := pg_temp._fx('set_s');
    v_lang UUID := pg_temp._fx('lang');
    v_key UUID := pg_temp._fx('key_h1');
    v_h1 JSONB := (SELECT v::jsonb FROM _tx WHERE k = 'out_h1');
    v_out JSONB; v_pc0 BIGINT; v_items JSONB; v_fp TEXT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_pc0 := pg_temp._pc_count();

    v_out := public.register_card_set_bulk(
                 pg_temp._creq(v_key, 'fp-qualquer', v_set, v_lang));
    PERFORM pg_temp._rec('I','I01 - mesma chave e mesma intencao devolve REPLAY com o resultado ja comprometido, sem escrita (D9)',
        v_out ->> 'outcome' = 'REPLAY'
        AND v_out ->> 'operation_id' = v_h1 ->> 'operation_id'
        AND (v_out -> 'result_summary') = (v_h1 -> 'result_summary')
        AND pg_temp._pc_count() = v_pc0,
        v_out::text, 'REPLAY identico, zero escrita');

    PERFORM pg_temp._expect_error('I','I02 - mesma chave com intencao diferente (destino outro) falha com BULK_IDEMPOTENCY_CONFLICT',
        format('SELECT public.register_card_set_bulk(%L::jsonb)',
               pg_temp._creq(v_key, 'fp', v_set, v_lang, pg_temp._fx('col_open'))::text),
        'BULK_IDEMPOTENCY_CONFLICT');

    -- Mesma chave no B1: namespace (owner, operation_type, key) independente.
    v_items := jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT cv.id::text FROM public.card_variant cv JOIN public.card ca ON ca.id = cv.card_id
                             WHERE ca.card_set_id = v_set AND ca.collector_number = 'S1' AND cv.is_default),
        'language_id', v_lang::text, 'quantity', 1));
    v_fp := public.preview_fingerprint_register_physical_cards(v_items);
    v_out := public.register_physical_cards_bulk(jsonb_build_object(
        'idempotency_key', v_key::text, 'preview_fingerprint', v_fp, 'items', v_items));
    PERFORM pg_temp._rec('I','I03 - a mesma idempotency_key no B1 e independente (namespace por operation_type): CREATED',
        v_out ->> 'outcome' = 'CREATED', v_out::text, 'CREATED');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('I','I-ABORT - grupo I abortou', FALSE, SQLERRM, 'sem excecao');
END;
$I$;

-- ================================================================
-- GRUPO K — PREVIEW_STALE E VALIDACOES NA CONFIRMACAO
-- ================================================================
DO $K$
DECLARE
    v_set UUID := pg_temp._fx('set_s');
    v_lang UUID := pg_temp._fx('lang');
    v_call TEXT := 'SELECT public.register_card_set_bulk(%L::jsonb)';
    v_fp TEXT; v_fake UUID := gen_random_uuid(); v_new_card UUID;
    v_keys UUID[] := ARRAY[]::uuid[]; v_k UUID; v_pc0 BIGINT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_pc0 := pg_temp._pc_count();

    -- K01: Card ativo desativado depois do Preview.
    v_fp := public.preview_bulk_operation(pg_temp._preq(v_set, v_lang)) ->> 'preview_fingerprint';
    UPDATE public.card SET is_active = FALSE WHERE id = pg_temp._fx('card_s3');
    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    PERFORM pg_temp._expect_error('K','K01 - Card desativado depois do Preview: PREVIEW_STALE',
        format(v_call, pg_temp._creq(v_k, v_fp, v_set, v_lang)::text), 'PREVIEW_STALE');
    UPDATE public.card SET is_active = TRUE WHERE id = pg_temp._fx('card_s3');

    -- K02: Card novo no Set depois do Preview.
    v_fp := public.preview_bulk_operation(pg_temp._preq(v_set, v_lang)) ->> 'preview_fingerprint';
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number,
                             collector_total, collector_order, name, is_active)
    VALUES (v_set, (SELECT v FROM _tx WHERE k = 'rar')::uuid, (SELECT v FROM _tx WHERE k = 'cat')::uuid,
            'S5', 4, 5, 'BULK04 S5', TRUE)
    RETURNING id INTO v_new_card;
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active)
    VALUES (v_new_card, (SELECT v FROM _tx WHERE k = 'std')::uuid, 1, TRUE, TRUE);
    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    PERFORM pg_temp._expect_error('K','K02 - Card novo no Set depois do Preview: PREVIEW_STALE',
        format(v_call, pg_temp._creq(v_k, v_fp, v_set, v_lang)::text), 'PREVIEW_STALE');
    UPDATE public.card SET is_active = FALSE WHERE id = v_new_card;

    -- K03: token do B1 sobre os mesmos itens nao vale no B2.
    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    PERFORM pg_temp._expect_error('K','K03 - fingerprint do B1 usado na confirmacao do B2: PREVIEW_STALE',
        format(v_call, pg_temp._creq(v_k, (SELECT v FROM _tx WHERE k = 'fp_b1_of_s'), v_set, v_lang)::text),
        'PREVIEW_STALE');

    -- K04..K10: fingerprint correto (5156), falha pela validacao.
    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(v_fake, v_lang);
    PERFORM pg_temp._expect_error('K','K04 - Card Set inexistente: card set not found',
        format(v_call, pg_temp._creq(v_k, v_fp, v_fake, v_lang)::text), 'card set not found');

    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(pg_temp._fx('set_n'), v_lang);
    PERFORM pg_temp._expect_error('K','K05 - Card ativo sem variante padrao: CARD_DEFAULT_VARIANT_MISSING com o card_id',
        format(v_call, pg_temp._creq(v_k, v_fp, pg_temp._fx('set_n'), v_lang)::text),
        'CARD_DEFAULT_VARIANT_MISSING: 1 card(s) sem variante padrao: ' || pg_temp._fx('card_n2')::text);

    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(pg_temp._fx('set_e'), v_lang);
    PERFORM pg_temp._expect_error('K','K06 - Set sem Card ativo: card set has no active cards',
        format(v_call, pg_temp._creq(v_k, v_fp, pg_temp._fx('set_e'), v_lang)::text),
        'card set has no active cards');

    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(pg_temp._fx('set_big'), v_lang);
    PERFORM pg_temp._expect_error('K','K07 - teto: 1001 Cards ativos excedem 1000, mesma mensagem do B1',
        format(v_call, pg_temp._creq(v_k, v_fp, pg_temp._fx('set_big'), v_lang)::text),
        'a operacao criaria 1001 Physical Cards e excede o limite de 1000 por chamada');

    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(v_set, v_fake);
    PERFORM pg_temp._expect_error('K','K08 - idioma inexistente: mensagem do B1 (helper 5153)',
        format(v_call, pg_temp._creq(v_k, v_fp, v_set, v_fake)::text),
        '1 language_id inexistente(s): ' || v_fake::text);

    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(v_set, v_lang, pg_temp._fx('col_arch'));
    PERFORM pg_temp._expect_error('K','K09 - Collection arquivada: mensagem do B1 (helper 5153)',
        format(v_call, pg_temp._creq(v_k, v_fp, v_set, v_lang, pg_temp._fx('col_arch'))::text),
        'collection is archived');

    v_k := gen_random_uuid(); v_keys := v_keys || v_k;
    v_fp := public.preview_fingerprint_register_card_set(v_set, v_lang, pg_temp._fx('col_ref_o'));
    PERFORM pg_temp._expect_error('K','K10 - Reference de outro Set: NOT eligible, mensagem do B1 (helper 5153)',
        format(v_call, pg_temp._creq(v_k, v_fp, v_set, v_lang, pg_temp._fx('col_ref_o'))::text),
        'nao pertence(m) ao Card Set referenciado pela Collection');

    -- A01 — atomicidade: nenhuma das 10 falhas escreveu nem consumiu a chave.
    PERFORM pg_temp._rec('A','A01 - as 10 falhas do grupo K nao criaram Physical Card nem consumiram idempotency_key',
        pg_temp._pc_count() = v_pc0
        AND NOT EXISTS (SELECT 1 FROM public.bulk_operation b WHERE b.idempotency_key = ANY (v_keys)),
        format('pc %s->%s', v_pc0, pg_temp._pc_count()), 'zero escrita, zero claim');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('K','K-ABORT - grupo K abortou', FALSE, SQLERRM, 'sem excecao');
END;
$K$;

-- ================================================================
-- X02 — o harness escreveu de fato
-- ================================================================
DO $X2$
BEGIN
    PERFORM pg_temp._rec('X','X02 - o harness ESCREVEU de fato (physical_card acima do baseline); zero residuo REAL e provado na CALL 3',
        pg_temp._pc_count() > (SELECT n FROM _bl WHERE k = 'physical_card'),
        format('baseline=%s fim=%s', (SELECT n FROM _bl WHERE k = 'physical_card'), pg_temp._pc_count()),
        'acima do baseline');
END;
$X2$;

-- ================================================================
-- RELATORIO FINAL — gate fail-closed + baseline para a CALL 3
-- ================================================================
SELECT
    count(*)                                           AS total,
    count(*) FILTER (WHERE passed)                     AS pass,
    count(*) FILTER (WHERE NOT passed)                 AS fail,
    0                                                  AS not_proven,
    (count(*) = 56 AND count(*) FILTER (WHERE NOT passed) = 0)
                                                       AS gate_ok,
    (SELECT jsonb_object_agg(k, n) FROM _bl)           AS baseline,
    jsonb_agg(jsonb_build_object('grupo', grp, 'caso', label,
                                 'got', got, 'want', want)
              ORDER BY grp, label)
        FILTER (WHERE NOT passed)                      AS failing_cases
FROM _r;

ROLLBACK;

-- ================================================================
-- APOS O ROLLBACK — CALL 3, POSTCHECK BASELINE-RELATIVO
-- ================================================================
-- SELECT (SELECT count(*) FROM public.bulk_operation)                AS bulk_operation,
--        (SELECT count(*) FROM public.physical_card)                 AS physical_card,
--        (SELECT count(*) FROM public.collection_allocation)         AS collection_allocation,
--        (SELECT count(*) FROM public.collection)                    AS collection,
--        (SELECT count(*) FROM public.collection_reference)          AS collection_reference,
--        (SELECT count(*) FROM public.collection_card_set_reference) AS collection_card_set_reference,
--        (SELECT count(*) FROM public.storage_container)             AS storage_container,
--        (SELECT count(*) FROM public.inventory)                     AS inventory,
--        (SELECT count(*) FROM public.expansion)                     AS expansion,
--        (SELECT count(*) FROM public.card_set)                      AS card_set,
--        (SELECT count(*) FROM public.card)                          AS card,
--        (SELECT count(*) FROM public.card_variant)                  AS card_variant;
-- Critério: cada contagem IGUAL à coluna `baseline` da CALL 1.
