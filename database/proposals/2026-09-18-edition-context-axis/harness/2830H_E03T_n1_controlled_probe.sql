-- ============================================================================
-- 2830H · E03T — PROVA TÉCNICA CONTROLADA DE N-1 E DO ANTIGO BLOCKER B-1
--   T1, T2, T3 (readiness v1.1 §2.8)
-- ============================================================================
-- NATUREZA ...... NÃO é caso da 2830 v7.0: não conta nos 135 casos, não gera
--                 PASS de contrato e não substitui o E03. Isola, com a menor
--                 escrita possível, o padrão SET CONSTRAINTS dentro do DO e a
--                 sonda de modo autocontida.
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO
--                 (BATCH12-2830-P5-L1-E03-IMPLEMENTATION-01). Execução exige
--                 decisão DP-7 de Fabrício e o mesmo protocolo do E03:
--                 S0 → L1 (canal) → L3 → E00 → E03P → E03T → E99 → L3.
-- Readiness ..... L1-E03-IMPLEMENTATION-READINESS.md v1.1 · blob 220fbd8b…
-- Sinais ........ H283C/H283F/H283P como no E01/E03; H283S só na sonda.
-- Aceite ........ H283P 'H2830_ROLLBACK_PASS: envelope=E03T_N1_CONTROLE
--                 pass=3/3 casos=T1,T2,T3 marker=H2830_… elapsed_ms=N' e E99
--                 limpo.
-- LIMITE L-1 .... (achado desta implementação, ver harness/README.md) O
--                 selo da 2206 (l. 68–74) retorna sem efeito quando o profile
--                 do evento não existe mais. Um evento de sonda que
--                 sobrevivesse ao rollback da sonda encontraria a linha já
--                 desfeita e também seria no-op. Por isso T3 prova que o
--                 IMMEDIATE posterior NÃO É CONTAMINADO (sem erro, sem efeito,
--                 selo intacto), mas NÃO distingue "evento removido" de
--                 "evento executado como no-op". A remoção continua
--                 fundamentada só estaticamente (trigger.c).
-- P8 lock_timeout — DECISÃO PENDENTE (DP-4); NÃO emitido.
-- ============================================================================
DO $h2830_e03t$
DECLARE
    c_env      CONSTANT text   := 'E03T_N1_CONTROLE';
    c_expected CONSTANT text[] := ARRAY['T1','T2','T3'];
    v_marker   text        := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''));
    v_t0       timestamptz := clock_timestamp();
    v_done     text[]      := ARRAY[]::text[];
    v_case     text;
    v_game     uuid;
    v_n        bigint;
    v_got      boolean;
    v_state    text;
    v_con      text;
    v_tab      text;
    v_msg      text;
    v_step     text;
    v_ord_t    integer;
    v_ord_p    integer;
    v_order_q  integer;
    v_t1       uuid;
    v_t2       uuid;
    v_t3       uuid;
    v_ti       uuid;
    v_p        uuid;
    v_pa       uuid;
    v_pb       uuid;
    v_code_p   text;
    v_code_pa  text;
    v_code_pb  text;
    v_sig      uuid[];
    v_exp      uuid[];
    v_arr      uuid[];
    v_qn       integer     := 0;
    v_qtag     text;
    v_q        uuid;
    v_qok      boolean;
BEGIN
    -- ------------------------------------------------------------------ --
    -- PREFLIGHT (não é caso; falha = H2830_FAIL, nunca PASS)
    -- ------------------------------------------------------------------ --
    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT game code=POKEMON count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';

    -- ================================================================== --
    -- T1 — 2.1 reduzido: selo via IMMEDIATE + sonda
    -- ================================================================== --
    v_case := 'T1';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_ti := NULL;
    v_p := NULL;
    v_pa := NULL;
    v_pb := NULL;
    v_code_p := NULL;
    v_code_pa := NULL;
    v_code_pb := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_arr := NULL;
    v_ord_t := NULL;
    v_ord_p := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        SELECT COALESCE(max(display_order), 0) INTO v_ord_p
          FROM public.card_edition_context_profile WHERE game_id = v_game;

        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture T1 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture T1 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t1, v_game);

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (readiness v1.1 §2.6.2): subtransação própria, sentinela H283S
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        v_order_q := v_ord_p + 1090;
        BEGIN
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
            VALUES (v_game, v_marker || '_Q' || v_qn, 'H2830 sonda ' || v_marker, v_order_q)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_profile WHERE id = v_q;
            IF v_q IS NULL OR v_qok IS DISTINCT FROM true THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s sem efeito observável', c_env, v_case, v_qn);
            END IF;
            RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = v_qtag;
        EXCEPTION
            WHEN SQLSTATE 'H283S' THEN
                GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
                IF v_msg IS DISTINCT FROM v_qtag THEN
                    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                        'H2830_FAIL: envelope=%s caso=%s sentinela de sonda trocada (%s)', c_env, v_case, v_msg);
                END IF;
            WHEN SQLSTATE 'H283F' THEN RAISE;
            WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s modo não DEFERRED ou erro inesperado sqlstate=%s msg=%s',
                    c_env, v_case, v_qn, v_state, v_msg);
        END;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

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
    -- T2 — 2.2 reduzido: IMMEDIATE que falha, capturado + sonda
    -- ================================================================== --
    v_case := 'T2';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_ti := NULL;
    v_p := NULL;
    v_pa := NULL;
    v_pb := NULL;
    v_code_p := NULL;
    v_code_pa := NULL;
    v_code_pb := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_arr := NULL;
    v_ord_t := NULL;
    v_ord_p := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        SELECT COALESCE(max(display_order), 0) INTO v_ord_p
          FROM public.card_edition_context_profile WHERE game_id = v_game;

        v_code_p := v_marker || '_P';
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            v_step := 'INSERT_P';
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
            VALUES (v_game, v_code_p, 'H2830 fixture T2 P ' || v_marker, v_ord_p + 1001)
            RETURNING id INTO v_p;
            v_step := 'IMMEDIATE';
            SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
            v_step := 'DEFERRED';
            SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
            SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s IMMEDIATE de profile sem composição foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:') OR v_step IS DISTINCT FROM 'IMMEDIATE' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_p IS NULL OR v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s profile do sub-bloco não foi desfeito (id=%s linhas=%s)', c_env, v_case, v_p, v_n);
        END IF;

        -- SONDA DE MODO (readiness v1.1 §2.6.2): subtransação própria, sentinela H283S
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        v_order_q := v_ord_p + 1090;
        BEGIN
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
            VALUES (v_game, v_marker || '_Q' || v_qn, 'H2830 sonda ' || v_marker, v_order_q)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_profile WHERE id = v_q;
            IF v_q IS NULL OR v_qok IS DISTINCT FROM true THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s sem efeito observável', c_env, v_case, v_qn);
            END IF;
            RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = v_qtag;
        EXCEPTION
            WHEN SQLSTATE 'H283S' THEN
                GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
                IF v_msg IS DISTINCT FROM v_qtag THEN
                    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                        'H2830_FAIL: envelope=%s caso=%s sentinela de sonda trocada (%s)', c_env, v_case, v_msg);
                END IF;
            WHEN SQLSTATE 'H283F' THEN RAISE;
            WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s modo não DEFERRED ou erro inesperado sqlstate=%s msg=%s',
                    c_env, v_case, v_qn, v_state, v_msg);
        END;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

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
    -- T3 — reprodução mínima do antigo B-1: selo, DEFERRED, sonda Q1 e NOVO
    --      IMMEDIATE sem outro evento pendente — tem de ser no-op (sem erro e
    --      sem efeito); termina com a sonda Q2. Ver limite L-1 no cabeçalho.
    -- ================================================================== --
    v_case := 'T3';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_ti := NULL;
    v_p := NULL;
    v_pa := NULL;
    v_pb := NULL;
    v_code_p := NULL;
    v_code_pa := NULL;
    v_code_pb := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_arr := NULL;
    v_ord_t := NULL;
    v_ord_p := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        SELECT COALESCE(max(display_order), 0) INTO v_ord_p
          FROM public.card_edition_context_profile WHERE game_id = v_game;

        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture T3 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture T3 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t1, v_game);

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (readiness v1.1 §2.6.2): subtransação própria, sentinela H283S
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        v_order_q := v_ord_p + 1090;
        BEGIN
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
            VALUES (v_game, v_marker || '_Q' || v_qn, 'H2830 sonda ' || v_marker, v_order_q)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_profile WHERE id = v_q;
            IF v_q IS NULL OR v_qok IS DISTINCT FROM true THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s sem efeito observável', c_env, v_case, v_qn);
            END IF;
            RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = v_qtag;
        EXCEPTION
            WHEN SQLSTATE 'H283S' THEN
                GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
                IF v_msg IS DISTINCT FROM v_qtag THEN
                    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                        'H2830_FAIL: envelope=%s caso=%s sentinela de sonda trocada (%s)', c_env, v_case, v_msg);
                END IF;
            WHEN SQLSTATE 'H283F' THEN RAISE;
            WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s modo não DEFERRED ou erro inesperado sqlstate=%s msg=%s',
                    c_env, v_case, v_qn, v_state, v_msg);
        END;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        -- F-10: pré-condição conferida de novo depois da sonda
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: selo alterado: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;

        -- IMMEDIATE posterior à sonda: nenhum evento de selo pode estar pendente
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s IMMEDIATE posterior alterou o selo: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile
         WHERE game_id = v_game AND starts_with(code, v_marker || '_Q');
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s linha de sonda visível depois do IMMEDIATE posterior (%s)', c_env, v_case, v_n);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (readiness v1.1 §2.6.2): subtransação própria, sentinela H283S
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        v_order_q := v_ord_p + 1090;
        BEGIN
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
            VALUES (v_game, v_marker || '_Q' || v_qn, 'H2830 sonda ' || v_marker, v_order_q)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_profile WHERE id = v_q;
            IF v_q IS NULL OR v_qok IS DISTINCT FROM true THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s sem efeito observável', c_env, v_case, v_qn);
            END IF;
            RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = v_qtag;
        EXCEPTION
            WHEN SQLSTATE 'H283S' THEN
                GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
                IF v_msg IS DISTINCT FROM v_qtag THEN
                    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                        'H2830_FAIL: envelope=%s caso=%s sentinela de sonda trocada (%s)', c_env, v_case, v_msg);
                END IF;
            WHEN SQLSTATE 'H283F' THEN RAISE;
            WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sonda n=%s modo não DEFERRED ou erro inesperado sqlstate=%s msg=%s',
                    c_env, v_case, v_qn, v_state, v_msg);
        END;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

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
    -- GATE DO ENVELOPE: exatamente os casos esperados, na ordem, cada um uma
    -- vez; e exatamente 4 sondas executadas (uma por IMMEDIATE)
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;
    IF v_qn <> 4 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE sondas=%s (esperado 4)', c_env, v_qn);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END
$h2830_e03t$;
