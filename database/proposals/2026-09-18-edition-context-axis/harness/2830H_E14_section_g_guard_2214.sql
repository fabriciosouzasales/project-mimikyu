-- ============================================================================
-- 2830H · ENVELOPE E14 — SEÇÃO G (GUARD 2214 v3.1, G1–G8) · lote L12, 8 casos
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E14P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 Seção G. Padrão: 2214 v3.1 PASSO 4 (Card/Variant Type
--                 por ORDER BY id; aqui do Game real, via bloco PICK compartilhado).
-- Negativos ..... P0001 + prefixo exato com dois-pontos (starts_with).
-- Escrita (R4) .. job 1–3 por caso (G7: 1 UPDATE de status no job de fixture) ·
--                 row: G1 1, G3 2, G5 3, G6 1, G7 1 + 1 UPDATE recusado + 1 UPDATE
--                 permitido, G8 2 + 2 UPDATE recusados; G2 1 e G4 3 recusadas.
--                 Nenhum DELETE. Tudo desfeito pelo término em exceção.
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e14$
DECLARE
    c_env      CONSTANT text   := 'E14_SECAO_G_GUARD_2214';
    c_expected CONSTANT text[] := ARRAY['G1','G2','G3','G4','G5','G6','G7','G8'];
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
    v_cs       uuid;
    v_vt       uuid;
    v_pp       uuid;
    v_ec       uuid;
    v_job1     uuid;
    v_job2     uuid;
    v_r1       uuid;
    v_r2       uuid;
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
    -- G1 [AUTO FX] STAGED · PENDING · NEEDS_REVIEW · chave ausente ⇒ permitido
    -- ================================================================== --
    v_case := 'G1';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, '{}'::jsonb, 'NEEDS_REVIEW', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G1 STAGED·PENDING·NEEDS_REVIEW·ausente: row não persistida', c_env, v_case);
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
    -- G2 [AUTO FX] STAGED · PENDING · VALID · ausente ⇒ CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY
    -- ================================================================== --
    v_case := 'G2';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G2 STAGED·PENDING·VALID·ausente foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G2 STAGED·PENDING·VALID·ausente: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
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
    -- G3 [AUTO FX] STAGED · PENDING · VALID · JSON null ⇒ permitido; UUID de profile existente ⇒ permitido
    -- ================================================================== --
    v_case := 'G3';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G3 JSON null: row não persistida', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', v_ec), 'VALID', 'PENDING')
        RETURNING id INTO v_r2;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r2;
        IF v_r2 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G3 UUID de profile existente: row não persistida', c_env, v_case);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_ec;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G3: profile usado não existe', c_env, v_case);
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
    -- G4 [AUTO FX] CONFIRMING, RECEIVED, PROCESSING · PENDING · VALID · ausente ⇒ mesmo código
    -- ================================================================== --
    v_case := 'G4';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'CONFIRMING')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CONFIRMING não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G4 CONFIRMING·PENDING·VALID·ausente foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G4 CONFIRMING·PENDING·VALID·ausente: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'RECEIVED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela RECEIVED não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G4 RECEIVED·PENDING·VALID·ausente foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G4 RECEIVED·PENDING·VALID·ausente: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J3', 'PROCESSING')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela PROCESSING não criado', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
            VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G4 PROCESSING·PENDING·VALID·ausente foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G4 PROCESSING·PENDING·VALID·ausente: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
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
    -- G5 [AUTO FX] COMPLETED, COMPLETED_WITH_ERRORS, FAILED · VALID · PENDING · ausente ⇒ permitido
    -- ================================================================== --
    v_case := 'G5';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'COMPLETED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G5 COMPLETED·VALID·PENDING·ausente: row não persistida', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'COMPLETED_WITH_ERRORS')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED_WITH_ERRORS não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G5 COMPLETED_WITH_ERRORS·VALID·PENDING·ausente: row não persistida', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J3', 'FAILED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela FAILED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G5 FAILED·VALID·PENDING·ausente: row não persistida', c_env, v_case);
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
    -- G6 [AUTO FX] CANCELLED · VALID · PENDING · ausente ⇒ permitido
    -- ================================================================== --
    v_case := 'G6';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'CANCELLED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CANCELLED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G6 CANCELLED·VALID·PENDING·ausente: row não persistida', c_env, v_case);
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
    -- G7 [AUTO FX] CANCELLED→STAGED não barrado; 1ª escrita na row sem chave recusada; G-BIS no-lockout
    -- ================================================================== --
    v_case := 'G7';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'CANCELLED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela CANCELLED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status, decision_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL), 'VALID', 'PENDING', 'SKIPPED')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G7 row histórica: row não persistida', c_env, v_case);
        END IF;
        UPDATE public.catalog_variant_import_job SET status = 'STAGED' WHERE id = v_job1;
        GET DIAGNOSTICS v_m = ROW_COUNT;
        SELECT status INTO v_txt FROM public.catalog_variant_import_job WHERE id = v_job1;
        IF v_m <> 1 OR v_txt IS DISTINCT FROM 'STAGED' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G7: reativação CANCELLED→STAGED barrada ou não aplicada (rows=%s status=%s)', c_env, v_case, v_m, v_txt);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.catalog_variant_import_row SET normalized_data = normalized_data WHERE id = v_r1;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G7 1ª escrita na row reativada sem a chave foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G7 1ª escrita na row reativada sem a chave: rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        UPDATE public.catalog_variant_import_row SET persistence_status = 'FAILED' WHERE id = v_r1;
        GET DIAGNOSTICS v_m = ROW_COUNT;
        SELECT persistence_status INTO v_txt FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_m <> 1 OR v_txt IS DISTINCT FROM 'FAILED' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G-BIS: saída de PENDING sem a chave barrada (rows=%s persistence=%s)', c_env, v_case, v_m, v_txt);
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
    -- G8 [AUTO FX] remover a chave de row VALID ⇒ CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN, inclusive em job terminal
    -- ================================================================== --
    v_case := 'G8';
    v_card := NULL;
    v_cs := NULL;
    v_vt := NULL;
    v_pp := NULL;
    v_ec := NULL;
    v_job1 := NULL;
    v_job2 := NULL;
    v_r1 := NULL;
    v_r2 := NULL;
    BEGIN
        SELECT c.id, c.card_set_id INTO v_card, v_cs
          FROM public.card c
          JOIN public.card_set cs ON cs.id = c.card_set_id
          JOIN public.expansion e ON e.id = cs.expansion_id
         WHERE e.game_id = v_game
         ORDER BY c.id
         LIMIT 1;
        SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;
        SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;
        IF v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J1', 'STAGED')
        RETURNING id INTO v_job1;
        IF v_job1 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela STAGED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_cs, 'TCGDEX', v_marker || '_J2', 'COMPLETED')
        RETURNING id INTO v_job2;
        IF v_job2 IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s job sentinela COMPLETED não criado', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job1, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'PENDING')
        RETURNING id INTO v_r1;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1;
        IF v_r1 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8 row operacional com chave: row não persistida', c_env, v_case);
        END IF;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)
        VALUES (v_job2, v_card, '{}'::jsonb, jsonb_build_object('variant_type_id', v_vt, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID', 'INSERTED')
        RETURNING id INTO v_r2;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r2;
        IF v_r2 IS NULL OR v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8 row terminal com chave: row não persistida', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.catalog_variant_import_row SET normalized_data = normalized_data - 'edition_context_profile_id' WHERE id = v_r1;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8 remoção da chave em row VALID (operacional) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8 remoção da chave em row VALID (operacional): rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r1 AND jsonb_exists(normalized_data, 'edition_context_profile_id');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8: chave ausente depois da recusa (operacional)', c_env, v_case);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.catalog_variant_import_row SET normalized_data = normalized_data - 'edition_context_profile_id' WHERE id = v_r2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8 remoção da chave em row VALID (terminal) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8 remoção da chave em row VALID (terminal): rejeição errada sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE id = v_r2 AND jsonb_exists(normalized_data, 'edition_context_profile_id');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s G8: chave ausente depois da recusa (terminal)', c_env, v_case);
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
$h2830_e14$;
