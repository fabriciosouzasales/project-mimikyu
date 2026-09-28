-- ============================================================================
-- 2830H · ENVELOPE E07 — SEÇÕES 2 e 3 (GAME SENTINELA) · lote L5, 2 casos: 2.6, 3.3
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E07P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 463, 544; P5: Game de fixture
--                 é linha sentinela NOVA, nunca um Game real alterado).
-- Autoridades ... 2205 (fk_cecpt_trait, FK composta same-Game), 2207/2211 (routing
--                 por game_id), 2206 (guards da N:N de profile).
-- Leitura ....... 2.6 FX — trait de OUTRO Game na N:N de profile do Game real ⇒
--                 23503 fk_cecpt_trait. Nenhum IMMEDIATE: o evento de selo do
--                 profile de fixture fica pendente e é descartado pelo H283C.
--                 3.3 FX+RC — mapping ativo de OUTRO Game (fixture) não resolve
--                 no Game real: token no residual de Finish; controle positivo
--                 no próprio Game sentinela (mesmo mapping ⇒ [T1]).
-- Escrita (R2) .. game 2 INSERT (1 por caso) · trait 2 · profile 1 · N:N de
--                 profile 1 tentativa recusada · mapping 1 · N:N de mapping 1.
--                 Nenhum UPDATE/DELETE. Tudo desfeito pelo término em exceção.
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e07$
DECLARE
    c_env      CONSTANT text   := 'E07_GAME_SENTINELA_2_6_3_3';
    c_expected CONSTANT text[] := ARRAY['2.6','3.3'];
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
    v_g2       uuid;
    v_t1       uuid;
    v_t2       uuid;
    v_p        uuid;
    v_m1       uuid;
    v_ord_p    integer;
    v_tok      text;
    v_raw      jsonb;
    v_ps       text;
    v_pp       uuid;
    v_pt       uuid[];
    v_ecs      text;
    v_ecp      uuid;
    v_ect      uuid[];
    v_rty      text;
    v_rfo      text;
    v_rst      text;
    v_rsp      text[];
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
    -- 2.6 — trait de outro Game (Game sentinela) ⇒ 23503 FK composta fk_cecpt_trait
    -- ================================================================== --
    v_case := '2.6';
    v_g2 := NULL;
    v_t1 := NULL;
    v_t2 := NULL;
    v_p := NULL;
    v_m1 := NULL;
    v_ord_p := NULL;
    v_tok := NULL;
    v_raw := NULL;
    BEGIN
        INSERT INTO public.game (code, name)
        VALUES (v_marker, 'H2830 fixture Game ' || v_marker)
        RETURNING id INTO v_g2;
        IF v_g2 IS NULL OR v_g2 = v_game THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s Game sentinela não criado ou igual ao Game real', c_env, v_case);
        END IF;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_g2, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.6 T2 ' || v_marker, 1001)
        RETURNING id INTO v_t2;
        SELECT COALESCE(max(display_order), 0) INTO v_ord_p FROM public.card_edition_context_profile WHERE game_id = v_game;
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_marker || '_P', 'H2830 fixture 2.6 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;
        IF v_t2 IS NULL OR v_p IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture incompleta (trait do Game sentinela ou profile)', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            VALUES (v_p, v_t2, v_game);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N:N com trait de outro Game (FK composta) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23503' OR v_con IS DISTINCT FROM 'fk_cecpt_trait' OR v_tab IS DISTINCT FROM 'card_edition_context_profile_trait' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N:N com trait de outro Game (FK composta): rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile_trait WHERE profile_id = v_p;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s linha(s) na N:N do profile de fixture (esperado 0)', c_env, v_case, v_n);
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
    -- 3.3 — mapping de outro Game (Game sentinela) não resolve no Game real (FX+RC)
    -- ================================================================== --
    v_case := '3.3';
    v_g2 := NULL;
    v_t1 := NULL;
    v_t2 := NULL;
    v_p := NULL;
    v_m1 := NULL;
    v_ord_p := NULL;
    v_tok := NULL;
    v_raw := NULL;
    BEGIN
        INSERT INTO public.game (code, name)
        VALUES (v_marker, 'H2830 fixture Game ' || v_marker)
        RETURNING id INTO v_g2;
        IF v_g2 IS NULL OR v_g2 = v_game THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s Game sentinela não criado ou igual ao Game real', c_env, v_case);
        END IF;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_g2, 'EVENT', v_marker || '_T1', 'H2830 fixture 3.3 T1 ' || v_marker, 1001)
        RETURNING id INTO v_t1;
        v_tok := v_marker || '_K';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token = v_tok;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token = v_tok;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_g2, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_g2);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1 AND game_id = v_g2 AND is_active;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mapping de fixture divergente no Game sentinela: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_g2, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t1]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle: Game sentinela) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (Game real, sem escopo) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
$h2830_e07$;
