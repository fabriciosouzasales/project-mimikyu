-- ============================================================================
-- 2830H · ENVELOPE E08 — SEÇÃO 4 (IDENTIDADE card_variant) · lote L6, 8 casos: 4.1–4.8
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E08P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 553–568).
-- Autoridades ... 2209 (uq_card_variant_identity UNIQUE NULLS NOT DISTINCT),
--                 160 (uq_card_variant_card_order, one_default), 161/2170/2224
--                 (triggers same-Game, pinados no E08P/P7X).
-- Fixtures ...... Card real + Variant Type do mesmo Game SEM Variant no par, por
--                 ORDER BY c.id, t.id; variant_order = max da Card + 1001..1004;
--                 profiles ativos do Game real por ORDER BY id; is_default = false
--                 (default). Nenhum UPDATE/DELETE; nenhuma linha pré-existente é
--                 alvo de escrita (FK só toma KEY SHARE nas referenciadas).
-- Escrita (R3) .. card_variant 12 tentativas de INSERT (4.2–4.5: 1 + 1 recusada
--                 cada; 4.6: 4). Tudo desfeito pelo término em exceção.
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e08$
DECLARE
    c_env      CONSTANT text   := 'E08_SECAO4_IDENTIDADE_CARD_VARIANT';
    c_expected CONSTANT text[] := ARRAY['4.1','4.2','4.3','4.4','4.5','4.6','4.7','4.8'];
    v_marker   text := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''));
    v_t0       timestamptz := clock_timestamp();
    v_done     text[] := ARRAY[]::text[];
    v_case     text;
    v_game     uuid;
    v_src      uuid;
    v_n        bigint;
    v_m        bigint;
    v_got      boolean;
    v_state    text;
    v_con      text;
    v_tab      text;
    v_msg      text;
    v_txt      text;
    v_card     uuid;
    v_vt       uuid;
    v_pp       uuid;
    v_eca      uuid[];
    v_ord      integer;
    v_cv1      uuid;
    v_cv2      uuid;
    v_cv3      uuid;
    v_cv4      uuid;
    v_k        bigint;
    v_b        boolean;
    v_arr      text[];
BEGIN
    -- ------------------------------------------------------------------ --
    -- P8 / DP-4 = A: lock_timeout transacional, primeira instrução executável
    -- ------------------------------------------------------------------ --
    SET LOCAL lock_timeout = '5s';
    IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT lock_timeout=%s (esperado 5s)', c_env, current_setting('lock_timeout'));
    END IF;

    -- ------------------------------------------------------------------ --
    -- PREFLIGHT (não é caso; falha = H2830_FAIL, nunca PASS)
    -- ------------------------------------------------------------------ --
    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT game code=POKEMON count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT count(*) INTO v_n FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT asset_source code=TCGDEX count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';

    -- ================================================================== --
    -- 4.1 — uq_card_variant_identity UNIQUE NULLS NOT DISTINCT (4 colunas), constraint u validada (RO)
    -- ================================================================== --
    v_case := '4.1';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM pg_constraint c
         WHERE c.conrelid = to_regclass('public.card_variant') AND c.conname = 'uq_card_variant_identity'
           AND c.contype = 'u' AND c.convalidated
           AND c.conindid = to_regclass('public.uq_card_variant_identity');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s constraint ''u'' validada uq_card_variant_identity ausente ou não ligada ao índice (%s)', c_env, v_case, v_n);
        END IF;
        SELECT i.indisunique AND i.indisvalid AND i.indisready AND i.indnullsnotdistinct AND i.indpred IS NULL
               AND i.indexprs IS NULL AND i.indnkeyatts = 4,
               (SELECT array_agg(a.attname::text ORDER BY k.ord)
                  FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
                  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum)
          INTO STRICT v_b, v_arr
          FROM pg_index i
         WHERE i.indexrelid = to_regclass('public.uq_card_variant_identity')
           AND i.indrelid = to_regclass('public.card_variant');
        IF NOT v_b OR v_arr IS DISTINCT FROM ARRAY['card_id','variant_type_id','printing_profile_id','edition_context_profile_id'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s índice uq_card_variant_identity divergente: flags=%s colunas=%s (esperado UNIQUE NULLS NOT DISTINCT total nas 4 colunas)', c_env, v_case, v_b, v_arr);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.2 — (card, vt, NULL, NULL) duplicado ⇒ 23505 uq_card_variant_identity (FX)
    -- ================================================================== --
    v_case := '4.2';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT c.id, t.id INTO v_card, v_vt
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
          JOIN public.card_variant_type t ON t.game_id = e.game_id
         WHERE e.game_id = v_game
           AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
         ORDER BY c.id, t.id
         LIMIT 1;
        IF v_card IS NULL OR v_vt IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem par (Card, Variant Type) livre no Game real (STOP; ver E08P)', c_env, v_case);
        END IF;
        SELECT COALESCE(max(variant_order), 0) INTO v_ord FROM public.card_variant WHERE card_id = v_card;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p
         WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT array_agg(x.id ORDER BY x.id) INTO v_eca
          FROM (SELECT p.id FROM public.card_edition_context_profile p
                 WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1) x;
        IF v_pp IS NULL OR cardinality(v_eca) IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s profiles de Printing/EC do Game real ausentes (STOP; ver E08P)', c_env, v_case);
        END IF;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1001, NULL, NULL)
        RETURNING id INTO v_cv1;
        IF v_cv1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s primeira Variant de fixture não criada', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
            VALUES (v_card, v_vt, v_ord + 1002, NULL, NULL)
            RETURNING id INTO v_cv2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, NULL, NULL) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_card_variant_identity' OR v_tab IS DISTINCT FROM 'card_variant' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, NULL, NULL): rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_variant
         WHERE card_id = v_card AND variant_type_id = v_vt;
        IF v_n <> 1 OR v_cv2 IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s Variant(s) no par de fixture (esperado 1)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.3 — (card, vt, pp, NULL) duplicado ⇒ 23505 (FX)
    -- ================================================================== --
    v_case := '4.3';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT c.id, t.id INTO v_card, v_vt
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
          JOIN public.card_variant_type t ON t.game_id = e.game_id
         WHERE e.game_id = v_game
           AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
         ORDER BY c.id, t.id
         LIMIT 1;
        IF v_card IS NULL OR v_vt IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem par (Card, Variant Type) livre no Game real (STOP; ver E08P)', c_env, v_case);
        END IF;
        SELECT COALESCE(max(variant_order), 0) INTO v_ord FROM public.card_variant WHERE card_id = v_card;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p
         WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT array_agg(x.id ORDER BY x.id) INTO v_eca
          FROM (SELECT p.id FROM public.card_edition_context_profile p
                 WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1) x;
        IF v_pp IS NULL OR cardinality(v_eca) IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s profiles de Printing/EC do Game real ausentes (STOP; ver E08P)', c_env, v_case);
        END IF;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1001, v_pp, NULL)
        RETURNING id INTO v_cv1;
        IF v_cv1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s primeira Variant de fixture não criada', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
            VALUES (v_card, v_vt, v_ord + 1002, v_pp, NULL)
            RETURNING id INTO v_cv2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, pp, NULL) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_card_variant_identity' OR v_tab IS DISTINCT FROM 'card_variant' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, pp, NULL): rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_variant
         WHERE card_id = v_card AND variant_type_id = v_vt;
        IF v_n <> 1 OR v_cv2 IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s Variant(s) no par de fixture (esperado 1)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.4 — (card, vt, NULL, ec) duplicado ⇒ 23505 (FX)
    -- ================================================================== --
    v_case := '4.4';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT c.id, t.id INTO v_card, v_vt
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
          JOIN public.card_variant_type t ON t.game_id = e.game_id
         WHERE e.game_id = v_game
           AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
         ORDER BY c.id, t.id
         LIMIT 1;
        IF v_card IS NULL OR v_vt IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem par (Card, Variant Type) livre no Game real (STOP; ver E08P)', c_env, v_case);
        END IF;
        SELECT COALESCE(max(variant_order), 0) INTO v_ord FROM public.card_variant WHERE card_id = v_card;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p
         WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT array_agg(x.id ORDER BY x.id) INTO v_eca
          FROM (SELECT p.id FROM public.card_edition_context_profile p
                 WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1) x;
        IF v_pp IS NULL OR cardinality(v_eca) IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s profiles de Printing/EC do Game real ausentes (STOP; ver E08P)', c_env, v_case);
        END IF;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1001, NULL, v_eca[1])
        RETURNING id INTO v_cv1;
        IF v_cv1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s primeira Variant de fixture não criada', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
            VALUES (v_card, v_vt, v_ord + 1002, NULL, v_eca[1])
            RETURNING id INTO v_cv2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, NULL, ec) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_card_variant_identity' OR v_tab IS DISTINCT FROM 'card_variant' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, NULL, ec): rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_variant
         WHERE card_id = v_card AND variant_type_id = v_vt;
        IF v_n <> 1 OR v_cv2 IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s Variant(s) no par de fixture (esperado 1)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.5 — (card, vt, pp, ec) duplicado ⇒ 23505 (FX)
    -- ================================================================== --
    v_case := '4.5';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT c.id, t.id INTO v_card, v_vt
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
          JOIN public.card_variant_type t ON t.game_id = e.game_id
         WHERE e.game_id = v_game
           AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
         ORDER BY c.id, t.id
         LIMIT 1;
        IF v_card IS NULL OR v_vt IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem par (Card, Variant Type) livre no Game real (STOP; ver E08P)', c_env, v_case);
        END IF;
        SELECT COALESCE(max(variant_order), 0) INTO v_ord FROM public.card_variant WHERE card_id = v_card;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p
         WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT array_agg(x.id ORDER BY x.id) INTO v_eca
          FROM (SELECT p.id FROM public.card_edition_context_profile p
                 WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1) x;
        IF v_pp IS NULL OR cardinality(v_eca) IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s profiles de Printing/EC do Game real ausentes (STOP; ver E08P)', c_env, v_case);
        END IF;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1001, v_pp, v_eca[1])
        RETURNING id INTO v_cv1;
        IF v_cv1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s primeira Variant de fixture não criada', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
            VALUES (v_card, v_vt, v_ord + 1002, v_pp, v_eca[1])
            RETURNING id INTO v_cv2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, pp, ec) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_card_variant_identity' OR v_tab IS DISTINCT FROM 'card_variant' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s duplicata (card, vt, pp, ec): rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_variant
         WHERE card_id = v_card AND variant_type_id = v_vt;
        IF v_n <> 1 OR v_cv2 IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s Variant(s) no par de fixture (esperado 1)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.6 — mesma Card, mesmo finish, contextos diferentes ⇒ coexistem (FX)
    -- ================================================================== --
    v_case := '4.6';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT c.id, t.id INTO v_card, v_vt
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
          JOIN public.card_variant_type t ON t.game_id = e.game_id
         WHERE e.game_id = v_game
           AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
         ORDER BY c.id, t.id
         LIMIT 1;
        IF v_card IS NULL OR v_vt IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem par (Card, Variant Type) livre no Game real (STOP; ver E08P)', c_env, v_case);
        END IF;
        SELECT COALESCE(max(variant_order), 0) INTO v_ord FROM public.card_variant WHERE card_id = v_card;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p
         WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT array_agg(x.id ORDER BY x.id) INTO v_eca
          FROM (SELECT p.id FROM public.card_edition_context_profile p
                 WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 2) x;
        IF v_pp IS NULL OR cardinality(v_eca) IS DISTINCT FROM 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s profiles de Printing/EC do Game real ausentes (STOP; ver E08P)', c_env, v_case);
        END IF;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1001, NULL, NULL)
        RETURNING id INTO v_cv1;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1002, NULL, v_eca[1])
        RETURNING id INTO v_cv2;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1003, NULL, v_eca[2])
        RETURNING id INTO v_cv3;
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
        VALUES (v_card, v_vt, v_ord + 1004, v_pp, NULL)
        RETURNING id INTO v_cv4;
        SELECT count(*), count(DISTINCT edition_context_profile_id), count(*) FILTER (WHERE edition_context_profile_id IS NULL)
          INTO v_n, v_m, v_k
          FROM public.card_variant WHERE card_id = v_card AND variant_type_id = v_vt;
        IF v_n <> 4 OR v_m <> 2 OR v_k <> 2 OR v_cv1 IS NULL OR v_cv2 IS NULL OR v_cv3 IS NULL OR v_cv4 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s coexistência divergente: linhas=%s contextos_distintos=%s sem_contexto=%s (esperado 4/2/2)', c_env, v_case, v_n, v_m, v_k);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.7 — uq_card_variant_card_order preservado (RO)
    -- ================================================================== --
    v_case := '4.7';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM pg_constraint c
         WHERE c.conrelid = to_regclass('public.card_variant') AND c.conname = 'uq_card_variant_card_order'
           AND c.contype = 'u' AND c.convalidated
           AND (SELECT array_agg(a.attname::text ORDER BY k.ord)
                  FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum) = ARRAY['card_id','variant_order'];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_card_variant_card_order não preservado como UNIQUE (card_id, variant_order) validado (%s)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ================================================================== --
    -- 4.8 — uq_card_variant_one_default_per_card preservado (RO)
    -- ================================================================== --
    v_case := '4.8';
    v_card := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_eca := NULL;
    v_ord := NULL;
    v_cv1 := NULL;
    v_cv2 := NULL;
    v_cv3 := NULL;
    v_cv4 := NULL;
    v_k := NULL;
    v_b := NULL;
    v_arr := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM pg_index i
         WHERE i.indexrelid = to_regclass('public.uq_card_variant_one_default_per_card')
           AND i.indrelid = to_regclass('public.card_variant')
           AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts = 1
           AND (SELECT a.attname::text FROM pg_attribute a WHERE a.attrelid = i.indrelid AND a.attnum = i.indkey[0]) = 'card_id'
           AND regexp_replace(pg_get_expr(i.indpred, i.indrelid), '[() ]', '', 'g') = 'is_default=true';
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_card_variant_one_default_per_card não preservado como UNIQUE (card_id) WHERE is_default = true (%s)', c_env, v_case, v_n);
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

    -- ------------------------------------------------------------------ --
    -- GATE DO ENVELOPE: exatamente os casos esperados, na ordem, cada um uma vez
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END
$h2830_e08$;
