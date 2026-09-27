-- ============================================================================
-- 2830H · ENVELOPE E04 — SEÇÕES 2-BIS e 2-TER (COMPOSIÇÃO E LIFECYCLE DO
--   EXTERNAL MAPPING) · lote L2, 14 casos:
--   2B.1, 2B.2, 2B.3, 2B.4, 2B.5, 2B.6, 2T.1, 2T.2, 2T.3, 2T.4, 2T.5, 2T.6,
--   2T.7, 2T.8
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12-2830-P5-L2-FUNCTIONAL-IMPLEMENTATION-01,
--                 baseline Git 36a3bc06). Execução exige auditoria deste blob,
--                 mandato próprio e E00 + E04P com gate_pass = true.
-- Contrato ...... 2830_validate_edition_context_foundation.sql v7.0 · blob
--                 b4647dcb59432405c8157e2733fd78678f35540e (l. 479–515;
--                 autoridade imutável; este arquivo a implementa, não a altera)
-- Autoridades ... 2207 (tabelas, índices parciais, 5 guards, tokens de erro);
--                 2211 internal.resolve_variant_row_axes (RC de 2T.6–2T.8);
--                 2176 v2.0 internal.compute_variant_residual_signature
--                 (chamada pela 2211). A 2233 NÃO redefine a 2211.
-- Padrão ........ reutiliza o E03 auditado (blob ef24a3be…): P1–P5, P8/DP-4,
--                 P13, subtransação por caso, sinais H283C/F/P/S.
-- Risco ......... DP-5 = B, tier R1: escreve SÓ em card_edition_context_trait,
--                 card_edition_context_external_mapping e
--                 card_edition_context_external_mapping_trait. D-2 = C: AD-2
--                 (elapsed_ms ≤ 60000 é operacional; não satisfaz A2/E1).
--
-- SINAIS (SQLSTATE próprios, classe H283x — não colidem com o PostgreSQL):
--   H283C  fim normal de um caso: desfaz as fixtures DO CASO e só então conta
--   H283F  H2830_FAIL — aborta o envelope inteiro (rollback)
--   H283P  H2830_ROLLBACK_PASS — sinal terminal de sucesso (rollback)
--   H283S  sentinela INTERNA da sonda de modo: desfaz só a linha e o evento da
--          sonda; capturada por SQLSTATE + MESSAGE exata dentro do próprio
--          bloco; nunca sai dele
--   Qualquer outro erro que escape é FAIL. Retorno [] do MCP = DEFEITO.
--
-- P4 — EVENTOS DIFERIDOS (trg_cecem_seal, DEFERRABLE INITIALLY DEFERRED):
--   · caminho medido: SET CONSTRAINTS dos 2 selos IMMEDIATE → medir →
--     DEFERRED; negativo com IMMEDIATE (2B.2): DEFERRED no corpo E no handler;
--   · 12 IMMEDIATE ⇒ 12 SONDAS (uma por IMMEDIATE, nível de caso, fora de
--     negativo/handler). A sonda insere um mapping SEM composição: em modo
--     DEFERRED o selo não dispara (traits_signature IS NULL) e a sentinela
--     H283S desfaz linha + evento; se o modo tivesse ficado IMMEDIATE, o
--     AFTER INSERT dispararia EMPTY_COMPOSITION e o WHEN OTHERS da sonda
--     converteria em H283F ("modo não DEFERRED");
--   · casos FX sem IMMEDIATE (2B.3, 2T.4, 2T.5) deixam o evento de selo de M1
--     PENDENTE de propósito: ele é descartado pelo rollback da subtransação do
--     caso (H283C) e nunca alcança caso seguinte nem o fim do DO;
--   · RO (2B.5, 2B.6) não escreve e não gera evento.
--
-- FIXTURES (todas desfeitas pela subtransação do caso; nenhuma linha
--   pré-existente é alterada; ids só por RETURNING INTO):
--   INSERT trait (code/name com v_marker) · INSERT mapping (normalized_token =
--   v_tok := v_marker || '_K'; external_set_id NULL ou v_set… := v_marker ||
--   '_S…') · INSERT N:N (mapping de fixture × trait de fixture).
--   UPDATE só em mapping de fixture: WHERE id = v_m… AND normalized_token =
--   v_tok (2B.3/2B.4: traits_signature; 2T.1/2T.2/2T.3/2T.7: is_active =
--   false, ROW_COUNT = 1). Nenhum DELETE. Sem LOOP: superfície de escrita
--   estática e finita (limites R1 por caso no registro operacional).
--   Tabelas com id UUID (gen_random_uuid) e N:N sem sequence (E04P
--   g_l2_no_sequence).
--
-- RC (2T.6–2T.8) — p_external_set_id = external_set_id DECLARADO da própria
--   fixture de mapping (v7.0; nunca card_set.code). raw_data sintético
--   {type, subtype = v_tok}: o token-marcador é desconhecido do eixo Printing
--   (E04P g_marker_absent_now inclui card_printing_external_mapping), logo a
--   2176 devolve RESOLVED_NO_PRINTING com o token no residual e o eixo 3 é
--   avaliado. Identidade da 2211/2176: NÃO demonstrada no LIVE por evidência
--   existente ⇒ fail-closed no E04P (pinos md5 LF do corpo do repositório,
--   volatilidade, SECURITY DEFINER, search_path, resultado); divergência =
--   STOP antes do E04. INTO STRICT: 0 ou >1 linha ⇒ erro ⇒ H283F.
--
-- P8 lock_timeout — DP-4 = A, estendida ao E04 pela regra E04-20 (perfil
--   próprio; a regra E03-20 do perfil E03 não é alterada). A PRIMEIRA
--   instrução executável é SET LOCAL lock_timeout = '5s' + asserção
--   fail-closed; espera de lock > 5s ⇒ 55P03 ⇒ H2830_FAIL, sem retry.
--   Não persistência provada fora pelo E99 (g_lock_timeout_default).
--
-- TERMINAL: H2830_ROLLBACK_PASS com pass, casos, marker, elapsed_ms e os
--   universos de 2B.5/2B.6 (P13; esperado LIVE 122, gate só exige > 0 e
--   2B.5 = 2B.6 — o valor canônico é gate do E00).
-- ============================================================================
DO $h2830_e04$
DECLARE
    c_env      CONSTANT text   := 'E04_SECAO2B_2T_MAPPING';
    c_expected CONSTANT text[] := ARRAY['2B.1','2B.2','2B.3','2B.4','2B.5','2B.6',
                                        '2T.1','2T.2','2T.3','2T.4','2T.5','2T.6','2T.7','2T.8'];
    v_marker   text        := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''));
    v_t0       timestamptz := clock_timestamp();
    v_done     text[]      := ARRAY[]::text[];
    v_case     text;
    v_game     uuid;
    v_src      uuid;
    v_n        bigint;
    v_n2       bigint;
    v_got      boolean;
    v_state    text;
    v_con      text;
    v_tab      text;
    v_msg      text;
    v_step     text;
    v_ord_t    integer;
    v_t1       uuid;
    v_t2       uuid;
    v_m1       uuid;
    v_m2       uuid;
    v_mg       uuid;
    v_ms       uuid;
    v_tok      text;
    v_set1     text;
    v_set2     text;
    v_txt      text;
    v_act      boolean;
    v_sig      uuid[];
    v_exp      uuid[];
    v_raw      jsonb;
    v_ps       text;
    v_ecs      text;
    v_ect      uuid[];
    v_rst      text;
    v_univ5    bigint      := NULL;
    v_univ6    bigint      := NULL;
    v_qn       integer     := 0;
    v_qtag     text;
    v_q        uuid;
    v_qok      boolean;
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
    -- 2B.1 — IMMEDIATE sela o mapping: traits_signature = ARRAY(N:N ORDER BY trait_id)
    --        FXd positivo; N:N inserida fora de ordem (T2, depois T1)
    -- ================================================================== --
    v_case := '2B.1';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2B.1 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2B.1 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t2, v_game);
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE — o evento pendente de M1 dispara aqui
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;

        v_exp := ARRAY(SELECT u.x FROM unnest(ARRAY[v_t1, v_t2]) AS u(x) ORDER BY u.x);
        IF cardinality(v_exp) <> 2 OR v_exp[1] IS NULL OR v_exp[1] = v_exp[2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s esperado vácuo ou duplicado: %s', c_env, v_case, v_exp);
        END IF;
        -- P4 (2): medir
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM v_exp OR cardinality(v_sig) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, v_exp);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
    -- 2B.2 — mapping sem N:N: IMMEDIATE levanta EDITION_CONTEXT_EXTERNAL_MAPPING_EMPTY_COMPOSITION
    --        FXd negativo; INSERT e IMMEDIATE no MESMO sub-bloco; erro atribuído ao IMMEDIATE por v_step
    -- ================================================================== --
    v_case := '2B.2';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            v_step := 'INSERT_M';
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_tok)
            RETURNING id INTO v_m1;
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
                'H2830_FAIL: envelope=%s caso=%s IMMEDIATE de mapping sem composição foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_EXTERNAL_MAPPING_EMPTY_COMPOSITION:') OR v_step IS DISTINCT FROM 'IMMEDIATE' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_m1 IS NULL OR v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mapping do sub-bloco não foi desfeito (id=%s linhas=%s)', c_env, v_case, v_m1, v_n);
        END IF;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
    -- 2B.3 — UPDATE falsificando o selo (mapping em montagem, selo NULL) ⇒ EDITION_CONTEXT_MAPPING_SIGNATURE_MISMATCH
    --        FX negativo, sem IMMEDIATE: o evento de selo pendente de M1 é
    --        descartado pelo rollback da subtransação do caso (P4, sem sonda)
    -- ================================================================== --
    v_case := '2B.3';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2B.3 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2B.3 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET traits_signature = ARRAY[v_t2] WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de selo falsificado foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_SIGNATURE_MISMATCH:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo gravado pelo negativo, selo=%s', c_env, v_case, v_sig);
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
    -- 2B.4 — UPDATE alterando selo gravado ⇒ EDITION_CONTEXT_MAPPING_SIGNATURE_IMMUTABLE (FXd negativo)
    -- ================================================================== --
    v_case := '2B.4';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2B.4 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2B.4 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        -- pré-condição conferida de novo depois da sonda
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 pós-sonda: selo alterado: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET traits_signature = ARRAY[v_t2] WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de selo gravado foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_SIGNATURE_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo alterado pelo negativo: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
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
    -- 2B.5 — RO: mappings com traits_signature NULL = 0; universo emitido e > 0 (P13)
    -- ================================================================== --
    v_case := '2B.5';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE strpos(normalized_token, 'H2830') > 0 OR strpos(COALESCE(external_set_id, ''), 'H2830') > 0;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo contaminado por fixture H2830: %s linha(s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) FILTER (WHERE traits_signature IS NULL), count(*)
          INTO v_n, v_univ5
          FROM public.card_edition_context_external_mapping;
        IF v_univ5 IS NULL OR v_univ5 <= 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo vazio: %s mapping(s) — prova vácua', c_env, v_case, v_univ5);
        END IF;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s %s de %s mapping(s) com traits_signature NULL', c_env, v_case, v_n, v_univ5);
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
    -- 2B.6 — RO: para todo mapping, traits_signature = ARRAY(N:N ORDER BY trait_id); universo > 0 (P13)
    -- ================================================================== --
    v_case := '2B.6';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE strpos(normalized_token, 'H2830') > 0 OR strpos(COALESCE(external_set_id, ''), 'H2830') > 0;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo contaminado por fixture H2830: %s linha(s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) FILTER (WHERE m.traits_signature IS DISTINCT FROM ARRAY(
                   SELECT mt.trait_id FROM public.card_edition_context_external_mapping_trait mt
                    WHERE mt.mapping_id = m.id ORDER BY mt.trait_id)),
               count(*)
          INTO v_n, v_univ6
          FROM public.card_edition_context_external_mapping m;
        IF v_univ6 IS NULL OR v_univ6 <= 0 OR v_univ6 IS DISTINCT FROM v_univ5 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s universo vazio ou instável: %s (2B.5=%s) — prova vácua', c_env, v_case, v_univ6, v_univ5);
        END IF;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s %s de %s mapping(s) com selo divergente da N:N', c_env, v_case, v_n, v_univ6);
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
    -- 2T.1 — correção completa numa transação: M1 ativo selado → M1 is_active = FALSE →
    --        M2 ativo com composição diferente → IMMEDIATE sem erro (FXd)
    -- ================================================================== --
    v_case := '2T.1';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2T.1 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2T.1 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE sela M1
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        -- M1 aposentado (TRUE → FALSE é a única transição de lifecycle permitida)
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        -- M2 ativo, mesmo token, composição diferente (T2)
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m2 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE sela M2 — qualquer erro aqui cai no WHEN OTHERS do caso (H283F)
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t2] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m2 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t2]);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
    -- 2T.2 — após 2T.1 (cenário reconstruído neste caso): 2 linhas no token, exatamente 1 ativa (M2)
    -- ================================================================== --
    v_case := '2T.2';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2T.2 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2T.2 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE sela M1
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        -- M1 aposentado (TRUE → FALSE é a única transição de lifecycle permitida)
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        -- M2 ativo, mesmo token, composição diferente (T2)
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m2 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE sela M2 — qualquer erro aqui cai no WHEN OTHERS do caso (H283F)
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t2] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m2 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t2]);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        SELECT count(*), count(*) FILTER (WHERE is_active)
          INTO v_n, v_n2
          FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND raw_field = 'subtype'
           AND normalized_token = v_tok AND external_set_id IS NULL;
        IF v_n <> 2 OR v_n2 <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s linhas no token=%s ativas=%s (esperado 2 e 1)', c_env, v_case, v_n, v_n2);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_act IS DISTINCT FROM true THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ativo não é M2 (M2.is_active=%s)', c_env, v_case, v_act);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM false THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s M1 não está aposentado (M1.is_active=%s)', c_env, v_case, v_act);
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
    -- 2T.3 — composição de M1 intacta e selada depois da correção (cenário 2T.1 reconstruído)
    -- ================================================================== --
    v_case := '2T.3';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2T.3 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2T.3 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE sela M1
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        -- M1 aposentado (TRUE → FALSE é a única transição de lifecycle permitida)
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        -- M2 ativo, mesmo token, composição diferente (T2)
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m2 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        -- P4 (1): IMMEDIATE sela M2 — qualquer erro aqui cai no WHEN OTHERS do caso (H283F)
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m2;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t2] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m2 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t2]);
        END IF;
        -- P4 (3): DEFERRED
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo de M1 alterado pela correção: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping_trait WHERE mapping_id = v_m1;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N:N de M1 com %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping_trait WHERE mapping_id = v_m1 AND trait_id = v_t1;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N:N de M1 não contém T1 (%s)', c_env, v_case, v_n);
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
    -- 2T.4 — dois ativos GLOBAIS do mesmo token ⇒ uq_cecem_active_global (23505)
    --        FX negativo, sem IMMEDIATE (evento de selo de M1 descartado pelo rollback do caso)
    -- ================================================================== --
    v_case := '2T.4';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_tok)
            RETURNING id INTO v_m2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s segundo ativo GLOBAL foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_cecem_active_global' OR v_tab IS DISTINCT FROM 'card_edition_context_external_mapping' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND raw_field = 'subtype'
           AND normalized_token = v_tok AND is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ativos no token=%s (esperado 1)', c_env, v_case, v_n);
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
    -- 2T.5 — dois ativos SCOPED (token, mesmo Set) ⇒ uq_cecem_active_scoped (23505)
    --        FX negativo, sem IMMEDIATE (evento de selo de M1 descartado pelo rollback do caso)
    -- ================================================================== --
    v_case := '2T.5';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        v_set1 := v_marker || '_S1';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_m1;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
            RETURNING id INTO v_m2;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s segundo ativo SCOPED no mesmo Set foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_cecem_active_scoped' OR v_tab IS DISTINCT FROM 'card_edition_context_external_mapping' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND raw_field = 'subtype'
           AND normalized_token = v_tok AND external_set_id = v_set1 AND is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ativos SCOPED no token=%s (esperado 1)', c_env, v_case, v_n);
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
    -- 2T.6 — 1 GLOBAL (T1) + 1 SCOPED (Set S1, T2) do mesmo token coexistem e a 2211 escolhe o
    --        SCOPED para p_external_set_id = S1 (fixture declarada). Controle: para S2 (Set
    --        declarado sem mapping escopado) a 2211 escolhe o GLOBAL. FXd + RC
    -- ================================================================== --
    v_case := '2T.6';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2T.6 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 2T.6 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        v_set1 := v_marker || '_S1';
        v_set2 := v_marker || '_S2';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_mg;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_mg, v_t1, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_ms;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_ms, v_t2, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_mg;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_ms;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_mg;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_mg antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_ms;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_ms antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_mg;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_mg selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_ms;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t2] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_ms selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t2]);
        END IF;
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);
        SELECT r.printing_state, r.edition_context_state, r.edition_context_trait_ids, r.residual_subtype
          INTO STRICT v_ps, v_ecs, v_ect, v_rst
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE'
           OR v_ect IS DISTINCT FROM ARRAY[v_t2] OR v_rst IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (Set S1: SCOPED) divergente: printing=%s ec=%s traits=%s residual_subtype=%s', c_env, v_case, v_ps, v_ecs, v_ect, v_rst);
        END IF;

        v_ps := NULL; v_ecs := NULL; v_ect := NULL; v_rst := NULL;
        SELECT r.printing_state, r.edition_context_state, r.edition_context_trait_ids, r.residual_subtype
          INTO STRICT v_ps, v_ecs, v_ect, v_rst
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set2) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE'
           OR v_ect IS DISTINCT FROM ARRAY[v_t1] OR v_rst IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle Set S2: GLOBAL) divergente: printing=%s ec=%s traits=%s residual_subtype=%s', c_env, v_case, v_ps, v_ecs, v_ect, v_rst);
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
    -- 2T.7 — token só com histórico inativo ⇒ 2211 devolve NEEDS_REVIEW_INACTIVE_EC_MAPPING
    --        (fixture SCOPED em S1, selada e aposentada; p_external_set_id = S1, declarado). FXd + RC
    -- ================================================================== --
    v_case := '2T.7';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2T.7 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        v_tok := v_marker || '_K';
        v_set1 := v_marker || '_S1';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_m1 selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND raw_field = 'subtype'
           AND normalized_token = v_tok AND is_active;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token ainda tem %s ativo(s) (esperado só histórico)', c_env, v_case, v_n);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);
        SELECT r.printing_state, r.edition_context_state, r.edition_context_trait_ids, r.residual_subtype
          INTO STRICT v_ps, v_ecs, v_ect, v_rst
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING'
           OR v_ect IS DISTINCT FROM '{}'::uuid[] OR v_rst IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (histórico inativo) divergente: printing=%s ec=%s traits=%s residual_subtype=%s', c_env, v_case, v_ps, v_ecs, v_ect, v_rst);
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
    -- 2T.8 — ativo SCOPED de OUTRO Set (S1) não conta como "known": para a linha do Set S2
    --        (declarado) o token fica no residual de Finish (RESOLVED_NO_EDITION_CONTEXT), não
    --        INACTIVE. Controle anti-vácuo: para S1 o mesmo mapping é alcançado. FXd + RC
    -- ================================================================== --
    v_case := '2T.8';
    v_t1 := NULL;
    v_t2 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_mg := NULL;
    v_ms := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_exp := NULL;
    v_ord_t := NULL;
    v_n2 := NULL;
    v_raw := NULL;
    v_ps := NULL;
    v_ecs := NULL;
    v_ect := NULL;
    v_rst := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2T.8 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        v_tok := v_marker || '_K';
        v_set1 := v_marker || '_S1';
        v_set2 := v_marker || '_S2';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_ms;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_ms, v_t1, v_game);
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_ms;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_ms;
        IF v_sig IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_ms antes do IMMEDIATE: pré-condição em montagem violada, selo=%s', c_env, v_case, v_sig);
        END IF;

        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
        SELECT traits_signature INTO v_sig FROM public.card_edition_context_external_mapping WHERE id = v_ms;
        IF v_sig IS NULL OR v_sig IS DISTINCT FROM ARRAY[v_t1] OR cardinality(v_sig) <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s v_ms selo divergente: selo=%s esperado=%s', c_env, v_case, v_sig, ARRAY[v_t1]);
        END IF;
        SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;

        -- SONDA DE MODO (P4): subtransação própria, sentinela H283S, alvo trg_cecem_seal
        v_qn      := v_qn + 1;
        v_qtag    := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
        v_q       := NULL;
        v_qok     := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'subtype', v_marker || '_Q' || v_qn)
            RETURNING id INTO v_q;
            SELECT (traits_signature IS NULL) INTO v_qok
              FROM public.card_edition_context_external_mapping WHERE id = v_q;
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
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE id = v_q;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
        END IF;
        v_q := NULL;

        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);
        SELECT r.printing_state, r.edition_context_state, r.edition_context_trait_ids, r.residual_subtype
          INTO STRICT v_ps, v_ecs, v_ect, v_rst
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set2) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT'
           OR v_ect IS DISTINCT FROM '{}'::uuid[] OR v_rst IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (Set S2: residual de Finish) divergente: printing=%s ec=%s traits=%s residual_subtype=%s', c_env, v_case, v_ps, v_ecs, v_ect, v_rst);
        END IF;

        v_ps := NULL; v_ecs := NULL; v_ect := NULL; v_rst := NULL;
        SELECT r.printing_state, r.edition_context_state, r.edition_context_trait_ids, r.residual_subtype
          INTO STRICT v_ps, v_ecs, v_ect, v_rst
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE'
           OR v_ect IS DISTINCT FROM ARRAY[v_t1] OR v_rst IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle Set S1: SCOPED alcançado) divergente: printing=%s ec=%s traits=%s residual_subtype=%s', c_env, v_case, v_ps, v_ecs, v_ect, v_rst);
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
    -- vez; exatamente 12 sondas (uma por IMMEDIATE); universos 2B.5/2B.6 > 0
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;
    IF v_qn <> 12 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE sondas=%s (esperado 12)', c_env, v_qn);
    END IF;
    IF v_univ5 IS NULL OR v_univ5 <= 0 OR v_univ6 IS DISTINCT FROM v_univ5 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE universo_2b5=%s universo_2b6=%s', c_env, v_univ5, v_univ6);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s universo_2b5=%s universo_2b6=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), v_univ5, v_univ6);
END
$h2830_e04$;
