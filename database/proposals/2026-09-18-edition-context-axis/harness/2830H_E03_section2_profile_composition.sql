-- ============================================================================
-- 2830H · ENVELOPE E03 — SEÇÃO 2 (COMPOSIÇÃO DO PROFILE) · lote L1, 13 casos:
--   2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14
--   (2.6 reservado ao lote L5 — NÃO implementado aqui)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12-2830-P5-L1-E03-IMPLEMENTATION-01).
--                 Execução exige mandato próprio, E00 e E03P com gate_pass e
--                 as decisões DP-1, DP-4, DP-5 (e DP-7 para o E03T).
-- Contrato ...... 2830_validate_edition_context_foundation.sql v7.0 · blob
--                 b4647dcb59432405c8157e2733fd78678f35540e (l. 453–477;
--                 autoridade imutável; este arquivo a implementa, não a altera)
-- Readiness ..... harness/L1-E03-IMPLEMENTATION-READINESS.md v1.1 · blob
--                 220fbd8be144d3c7e8a48615f3106290b8a6dfb0 (contrato de
--                 implementação: §2.3, §2.6, §3, §6)
-- Protocolo ..... P1 teste transacional com rollback integral (ESCREVE
--                 fixtures e desfaz) · P2 um único DO, sem COMMIT/TEMP/
--                 set_config/SET ROLE/EXECUTE, terminando SEMPRE em exceção ·
--                 P3 cada caso em subtransação; negativo confere SQLSTATE +
--                 prefixo do token (starts_with, nunca LIKE) ou CONSTRAINT_NAME
--                 + TABLE_NAME · P4 SET CONSTRAINTS nos dois triggers de selo,
--                 IMMEDIATE → medir → DEFERRED nos dois caminhos · P5 marcador
--                 único por execução (AD-6) em code e name · P13 cada positivo
--                 mede o efeito (selo, contagem, ROW_COUNT).
--
-- SINAIS (SQLSTATE próprios, classe H283x — não colidem com o PostgreSQL):
--   H283C  fim normal de um caso: desfaz as fixtures DO CASO e só então conta
--   H283F  H2830_FAIL — aborta o envelope inteiro (rollback)
--   H283P  H2830_ROLLBACK_PASS — sinal terminal de sucesso (rollback)
--   H283S  sentinela INTERNA da sonda de modo (readiness v1.1 §2.6): desfaz
--          só a linha e o evento da sonda; capturada por SQLSTATE + MESSAGE
--          exata dentro do próprio bloco; nunca sai dele (se saísse, o
--          WHEN OTHERS do caso a converteria em H283F)
--   Qualquer outro erro que escape é FAIL. Retorno [] do MCP = DEFEITO.
--
-- SONDAS DE MODO: 11 (uma por IMMEDIATE), sempre em nível de caso, depois do
--   DEFERRED do caminho normal ou do END do sub-bloco negativo; nunca dentro
--   de sub-bloco negativo nem de handler. Matriz de eventos: readiness §2.6.4
--   (caso 2.7) e §2.6.5 (demais casos).
--
-- FIXTURES (todas desfeitas pela subtransação do caso; nenhuma linha
--   pré-existente é alterada):
--   INSERT trait / profile / profile_trait (ids por RETURNING INTO);
--   UPDATE só em card_edition_context_profile WHERE id = v_p… AND
--   code = v_code_p… (2.11–2.14); DELETE só em card_edition_context_profile_
--   trait WHERE profile_id = v_p AND trait_id = v_t1 (2.4). Tabelas com id
--   UUID (gen_random_uuid): sem sequence (E03P g_nn_no_sequence + E00).
--
-- P8 lock_timeout — DECISÃO PENDENTE (DP-4). Se autorizada, uma linha
--   'SET LOCAL lock_timeout' passa a ser a PRIMEIRA instrução do corpo, com
--   asserção inicial e ajuste do perfil E03 do static_check. Enquanto não
--   autorizada, NÃO é emitida.
-- ============================================================================
DO $h2830_e03$
DECLARE
    c_env      CONSTANT text   := 'E03_SECAO2_COMPOSICAO_PROFILE';
    c_expected CONSTANT text[] := ARRAY['2.1','2.2','2.3','2.4','2.5','2.7',
                                        '2.8','2.9','2.10','2.11','2.12','2.13','2.14'];
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
    -- 2.1 — IMMEDIATE sela: traits_signature = ARRAY(N:N ORDER BY trait_id)
    --       FXd positivo; N:N inserida fora de ordem (T2, depois T1)
    -- ================================================================== --
    v_case := '2.1';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.1 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.1 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.1 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t2, v_game);
        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t1, v_game);

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE — o evento pendente de P dispara aqui
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        v_exp := ARRAY(SELECT u.x FROM unnest(ARRAY[v_t1, v_t2]) AS u(x) ORDER BY u.x);
        IF cardinality(v_exp) <> 2 OR v_exp[1] IS NULL OR v_exp[1] = v_exp[2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s esperado vácuo ou duplicado: %s', c_env, v_case, v_exp);
        END IF;
        -- P4 (2): medir
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;

        -- P4 (3): DEFERRED
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
    -- 2.2 — profile sem N:N: IMMEDIATE levanta EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION
    --       FXd negativo; INSERT e IMMEDIATE no MESMO sub-bloco (readiness §2.3);
    --       o erro é atribuído ao IMMEDIATE por v_step (E03-19)
    -- ================================================================== --
    v_case := '2.2';
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
            VALUES (v_game, v_code_p, 'H2830 fixture 2.2 P ' || v_marker, v_ord_p + 1001)
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
    -- 2.3 — INSERT na N:N de profile selado com trait DIFERENTE ⇒ COMPOSITION_IMMUTABLE
    --       (a reinserção idêntica passa por desenho — 2206 — e não é usada)
    -- ================================================================== --
    v_case := '2.3';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.3 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.3 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.3 P ' || v_marker, v_ord_p + 1001)
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
                'H2830_FAIL: envelope=%s caso=%s INSERT na N:N de profile selado foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_COMPOSITION_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT ARRAY(SELECT t.trait_id FROM public.card_edition_context_profile_trait t
                      WHERE t.profile_id = v_p ORDER BY t.trait_id) INTO v_arr;
        IF v_arr IS DISTINCT FROM ARRAY[v_t1] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s composição alterada: %s', c_env, v_case, v_arr);
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
    -- 2.4 — DELETE na N:N de profile selado ⇒ COMPOSITION_IMMUTABLE
    -- ================================================================== --
    v_case := '2.4';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.4 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.4 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.4 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t1, v_game);
        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t2, v_game);

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        v_exp := ARRAY(SELECT u.x FROM unnest(ARRAY[v_t1, v_t2]) AS u(x) ORDER BY u.x);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
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
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: selo alterado: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            DELETE FROM public.card_edition_context_profile_trait WHERE profile_id = v_p AND trait_id = v_t1;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s DELETE na N:N de profile selado foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_COMPOSITION_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT ARRAY(SELECT t.trait_id FROM public.card_edition_context_profile_trait t
                      WHERE t.profile_id = v_p ORDER BY t.trait_id) INTO v_arr;
        IF v_arr IS DISTINCT FROM v_exp THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s composição alterada: %s', c_env, v_case, v_arr);
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
    -- 2.5 — trait inativo em composição nova ⇒ TRAIT_INACTIVE
    --       FX negativo; profile em montagem (trg_cecpt_immutable deixa passar,
    --       trg_cecpt_trait_active levanta — ordem alfabética, readiness §1.5)
    -- ================================================================== --
    v_case := '2.5';
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

        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order, is_active)
        VALUES (v_game, 'EVENT', v_marker || '_TI', 'H2830 fixture 2.5 TI ' || v_marker, v_ord_t + 1009, false)
        RETURNING id INTO v_ti;

        SELECT count(*) INTO v_n FROM public.card_edition_context_trait WHERE id = v_ti AND NOT is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição trait inativo violada (%s)', c_env, v_case, v_n);
        END IF;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.5 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s antes do INSERT na N:N: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            VALUES (v_p, v_ti, v_game);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s INSERT na N:N com trait inativo foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_TRAIT_INACTIVE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
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
    -- 2.7 — mesma assinatura no mesmo Game ⇒ 23505 uq_cecp_game_signature
    --       Pa selado ANTES; sonda Q1 autocontida; no IMMEDIATE de Pb a fila
    --       contém SÓ o evento de Pb (readiness §2.6.4); erro atribuído por v_step
    -- ================================================================== --
    v_case := '2.7';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.7 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.7 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;

        v_code_pa := v_marker || '_PA';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_pa, 'H2830 fixture 2.7 PA ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_pa;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_pa, v_t1, v_game);
        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_pa, v_t2, v_game);

        -- etapa 3: IMMEDIATE processa exatamente o evento de Pa
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        v_exp := ARRAY(SELECT u.x FROM unnest(ARRAY[v_t1, v_t2]) AS u(x) ORDER BY u.x);
        IF cardinality(v_exp) <> 2 OR v_exp[1] IS NULL OR v_exp[1] = v_exp[2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s esperado vácuo ou duplicado: %s', c_env, v_case, v_exp);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_pa;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s Pa: selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;

        -- etapa 4: DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- etapas 5-7: sonda Q1 — linha e evento próprios, desfeitos por H283S
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
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_pa;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: selo alterado: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;

        -- etapas 8-10: sub-bloco negativo N (Pb)
        v_code_pb := v_marker || '_PB';
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            v_step := 'INSERT_PB';
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
            VALUES (v_game, v_code_pb, 'H2830 fixture 2.7 PB ' || v_marker, v_ord_p + 1002)
            RETURNING id INTO v_pb;
            v_step := 'INSERT_PB_T1';
            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            VALUES (v_pb, v_t1, v_game);
            v_step := 'INSERT_PB_T2';
            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            VALUES (v_pb, v_t2, v_game);
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

        -- etapa 11: aceite estrito
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s IMMEDIATE com assinatura repetida foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_cecp_game_signature' OR v_tab IS DISTINCT FROM 'card_edition_context_profile' OR v_step IS DISTINCT FROM 'IMMEDIATE' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_pb;
        IF v_pb IS NULL OR v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s Pb não foi desfeito (id=%s linhas=%s)', c_env, v_case, v_pb, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_profile_trait WHERE profile_id = v_pb;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N:N de Pb não foi desfeita (%s)', c_env, v_case, v_n);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_pa;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s Pa alterado pelo negativo: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;

        -- etapa 12: sonda Q2
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
    -- 2.8 — assinatura NULL não colide (predicado parcial do índice)
    --       FX positivo; 2 profiles sem N:N e SEM IMMEDIATE (eventos descartados
    --       pelo H283C)
    -- ================================================================== --
    v_case := '2.8';
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

        v_code_pa := v_marker || '_PA';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_pa, 'H2830 fixture 2.8 PA ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_pa;

        v_code_pb := v_marker || '_PB';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_pb, 'H2830 fixture 2.8 PB ' || v_marker, v_ord_p + 1002)
        RETURNING id INTO v_pb;

        SELECT count(*) INTO v_n FROM public.card_edition_context_profile
         WHERE id IN (v_pa, v_pb) AND game_id = v_game AND traits_signature IS NULL;
        IF v_pa IS NULL OR v_pb IS NULL OR v_pa = v_pb OR v_n <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2 profiles com selo NULL no mesmo Game: %s', c_env, v_case, v_n);
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
    -- 2.9 — N:N inserida em ordem DECRESCENTE ⇒ selo ascendente (ORDER BY trait_id)
    -- ================================================================== --
    v_case := '2.9';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.9 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.9 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T3', 'H2830 fixture 2.9 T3 ' || v_marker, v_ord_t + 1003)
        RETURNING id INTO v_t3;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.9 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        v_arr := ARRAY(SELECT u.x FROM unnest(ARRAY[v_t1, v_t2, v_t3]) AS u(x) ORDER BY u.x DESC);
        IF cardinality(v_arr) <> 3 OR NOT (v_arr[1] > v_arr[2] AND v_arr[2] > v_arr[3]) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ordem decrescente não construída: %s', c_env, v_case, v_arr);
        END IF;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_arr[1], v_game);
        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_arr[2], v_game);
        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_arr[3], v_game);

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        v_exp := ARRAY(SELECT u.x FROM unnest(ARRAY[v_t1, v_t2, v_t3]) AS u(x) ORDER BY u.x);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 3 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo não ascendente: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;
        IF v_sig[1] IS DISTINCT FROM v_arr[3] OR v_sig[3] IS DISTINCT FROM v_arr[1] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo não inverte a ordem de inserção: %s', c_env, v_case, v_sig);
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
    -- 2.10 — linha repetida na N:N ⇒ 23505 pk_cecpt; depois cardinality(selo) = COUNT(N:N) = 1
    -- ================================================================== --
    v_case := '2.10';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.10 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.10 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t1, v_game);

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s antes do INSERT duplicado: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            VALUES (v_p, v_t1, v_game);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s INSERT duplicado na N:N foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'pk_cecpt' OR v_tab IS DISTINCT FROM 'card_edition_context_profile_trait' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        SELECT count(*) INTO v_n FROM public.card_edition_context_profile_trait WHERE profile_id = v_p;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        IF v_n <> 1 OR cardinality(v_sig) <> v_n THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s cardinality(selo)=%s COUNT(N:N)=%s (esperado 1 = 1)', c_env, v_case, cardinality(v_sig), v_n);
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
    -- 2.11 — UPDATE falsificando o selo em montagem ⇒ EDITION_CONTEXT_SIGNATURE_MISMATCH
    --       FX negativo; sem IMMEDIATE (o evento de P é descartado pelo H283C)
    -- ================================================================== --
    v_case := '2.11';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.11 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.11 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.11 P ' || v_marker, v_ord_p + 1001)
        RETURNING id INTO v_p;

        INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p, v_t1, v_game);

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s antes do UPDATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_profile SET traits_signature = ARRAY[v_t2] WHERE id = v_p AND code = v_code_p;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE com selo falsificado foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_SIGNATURE_MISMATCH:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
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
    -- 2.12 — UPDATE alterando selo gravado ⇒ EDITION_CONTEXT_SIGNATURE_IMMUTABLE
    -- ================================================================== --
    v_case := '2.12';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.12 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.12 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.12 P ' || v_marker, v_ord_p + 1001)
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

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_profile SET traits_signature = ARRAY[v_t2] WHERE id = v_p AND code = v_code_p;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de selo gravado foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_SIGNATURE_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo alterado pelo negativo: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
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
    -- 2.13 — UPDATE voltando selo gravado a NULL ⇒ EDITION_CONTEXT_SIGNATURE_IMMUTABLE
    -- ================================================================== --
    v_case := '2.13';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.13 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.13 P ' || v_marker, v_ord_p + 1001)
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

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_profile SET traits_signature = NULL WHERE id = v_p AND code = v_code_p;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de selo para NULL foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_SIGNATURE_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo alterado pelo negativo: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
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
    -- 2.14 — UPDATE sem tocar o selo (name) é permitido; só linha de fixture
    --       trg_cecp_signature_write é BEFORE UPDATE OF traits_signature: não dispara
    -- ================================================================== --
    v_case := '2.14';
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
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2.14 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;

        v_code_p := v_marker || '_P';
        INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
        VALUES (v_game, v_code_p, 'H2830 fixture 2.14 P ' || v_marker, v_ord_p + 1001)
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

        UPDATE public.card_edition_context_profile SET name = 'H2830 fixture 2.14 renomeado ' || v_marker WHERE id = v_p AND code = v_code_p;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de name afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_profile
         WHERE id = v_p AND name = 'H2830 fixture 2.14 renomeado ' || v_marker;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s name não foi alterado (%s)', c_env, v_case, v_n);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_profile WHERE id = v_p;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s selo alterado pelo UPDATE de name: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
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
    -- GATE DO ENVELOPE: exatamente os casos esperados, na ordem, cada um uma
    -- vez; e exatamente 11 sondas executadas (uma por IMMEDIATE)
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;
    IF v_qn <> 11 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE sondas=%s (esperado 11)', c_env, v_qn);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END
$h2830_e03$;
