-- ============================================================================
-- 2830H · ENVELOPE E05 — SEÇÃO 2-QUATER (LIFECYCLE DO CABEÇALHO DO EXTERNAL
--   MAPPING) · lote L3, 10 casos: 2Q.1, 2Q.2, 2Q.3, 2Q.4, 2Q.5, 2Q.6, 2Q.7,
--   2Q.8, 2Q.9, 2Q.10
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12-2830-P5-L2-CLOSEOUT-AND-L3-IMPLEMENTATION-01,
--                 baseline Git 8e13354f). Execução exige auditoria deste blob,
--                 mandato próprio e E00 + E05P com gate_pass = true.
-- Contrato ...... 2830_validate_edition_context_foundation.sql v7.0 · blob
--                 b4647dcb59432405c8157e2733fd78678f35540e (l. 518–537;
--                 autoridade imutável; este arquivo a implementa, não a altera)
-- Autoridades ... 2207 GUARD B `internal.enforce_edition_context_mapping_header`
--                 (identidade imutável; FALSE → TRUE proibido) e NORMALIZE
--                 `internal.normalize_edition_context_external_mapping`
--                 (token via 2095; external_set_id só btrim).
-- Padrão ........ reutiliza E03/E04 auditados e executados CONFORME no LIVE:
--                 P1–P5, P8/DP-4 = A, subtransação por caso, sinais
--                 H283C/F/P/S, sonda de modo idêntica à do E04 (mapping sem
--                 composição, alvo trg_cecem_seal).
-- Risco ......... DP-5 = B, tier R1: escreve SÓ em card_edition_context_trait,
--                 card_edition_context_external_mapping e
--                 card_edition_context_external_mapping_trait. D-2 = C: AD-2
--                 (elapsed_ms ≤ 60000 é operacional; não satisfaz A2/E1).
--
-- SINAIS: H283C fim de caso · H283F FAIL · H283P PASS terminal · H283S
--   sentinela interna da sonda. Qualquer outro erro que escape é FAIL.
--
-- P4 — EVENTOS DIFERIDOS: 2Q.1–2Q.7 (FXd) selam M1 com IMMEDIATE → medem →
--   DEFERRED → sonda (7 IMMEDIATE ⇒ 7 sondas). 2Q.8–2Q.10 (FX) não usam
--   IMMEDIATE: o evento de selo pendente das fixtures é descartado pelo
--   rollback da subtransação do caso (H283C). Nenhum negativo contém
--   IMMEDIATE (todos são UPDATE/INSERT recusados por BEFORE ROW).
--
-- UPDATE DE CABEÇALHO (R1): SÓ em M1 de fixture, sempre
--   WHERE id = v_m1 AND normalized_token = v_tok (id por RETURNING INTO e
--   token-marcador ⇒ identidade comprovada). 11 UPDATEs: 6 recusados
--   (normalized_token, external_set_id, raw_field, game_id, asset_source_id,
--   is_active FALSE → TRUE) e 5 aceitos (is_active). Depois de cada um,
--   a identidade integral e o selo de M1 são reconferidos. c_nil é um UUID
--   que não existe: o guard BEFORE ROW recusa antes de qualquer FK.
--
-- N-3 — TOKENS LITERAIS SEM MARCADOR:
--   · 2Q.8: 'set-logo', 'Pokébola', 'BLUE  BORDER' em escopo SCOPED no Set de
--     fixture v_set1 := v_marker || '_S1'. A chave de uq_cecem_active_scoped
--     inclui external_set_id ⇒ disjunta de todo mapping LIVE. Antes do
--     INSERT: nenhum mapping no escopo v_set1 (senão H2830_FAIL = STOP).
--   · 2Q.10: Set literal '  dp1  ' com token-marcador v_tok ⇒ chave disjunta
--     de todo mapping LIVE. Antes do INSERT: nenhum mapping com v_tok.
--   · 2Q.9: '   ' é recusado; escopo v_set1 marcado.
--   · Resíduo de 2Q.8 NÃO tem marcador em normalized_token (o E99 procura o
--     marcador só ali): o resíduo é provado por CONTAGEM (E99
--     g_baseline_equal, chave mapping) e pelo E05P/E99 no escopo marcado.
--
-- P8 lock_timeout — DP-4 = A (regra E05-20, perfil próprio): primeira
--   instrução executável SET LOCAL lock_timeout = '5s' + asserção fail-closed.
--
-- TERMINAL: H2830_ROLLBACK_PASS com pass, casos, marker e elapsed_ms.
-- ============================================================================
DO $h2830_e05$
DECLARE
    c_env      CONSTANT text   := 'E05_SECAO2Q_MAPPING_HEADER';
    c_expected CONSTANT text[] := ARRAY['2Q.1','2Q.2','2Q.3','2Q.4','2Q.5','2Q.6','2Q.7','2Q.8','2Q.9','2Q.10'];
    c_nil      CONSTANT uuid   := '00000000-0000-4000-8000-000000000000';
    v_marker   text        := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''));
    v_t0       timestamptz := clock_timestamp();
    v_done     text[]      := ARRAY[]::text[];
    v_case     text;
    v_game     uuid;
    v_src      uuid;
    v_n        bigint;
    v_got      boolean;
    v_state    text;
    v_con      text;
    v_tab      text;
    v_msg      text;
    v_step     text;
    v_ord_t    integer;
    v_t1       uuid;
    v_m1       uuid;
    v_m2       uuid;
    v_m3       uuid;
    v_tok      text;
    v_set1     text;
    v_txt      text;
    v_act      boolean;
    v_sig      uuid[];
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
    -- 2Q.1 — UPDATE de normalized_token em mapping selado ⇒ EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE (FXd)
    -- ================================================================== --
    v_case := '2Q.1';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.1 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET normalized_token = v_tok || '_X' WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de normalized_token foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
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
    -- 2Q.2 — UPDATE de external_set_id (GLOBAL → SCOPED, Set de fixture) ⇒ IDENTITY_IMMUTABLE (FXd)
    -- ================================================================== --
    v_case := '2Q.2';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.2 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;
        v_set1 := v_marker || '_S1';

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET external_set_id = v_set1 WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE GLOBAL → SCOPED foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
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
    -- 2Q.3 — UPDATE de raw_field ('stamp' → 'subtype') ⇒ IDENTITY_IMMUTABLE (FXd)
    -- ================================================================== --
    v_case := '2Q.3';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.3 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'stamp', v_tok)
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'stamp' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET raw_field = 'subtype' WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de raw_field stamp → subtype foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'stamp' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
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
    -- 2Q.4 — UPDATE de game_id OU asset_source_id ⇒ IDENTITY_IMMUTABLE (FXd; as duas colunas, uma
    --        por sub-bloco; valor-alvo c_nil, que nunca existe: o guard BEFORE ROW recusa antes da FK)
    -- ================================================================== --
    v_case := '2Q.4';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.4 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET game_id = c_nil WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de game_id foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET asset_source_id = c_nil WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s UPDATE de asset_source_id foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
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
    -- 2Q.5 — is_active TRUE → FALSE permitido (FXd): ROW_COUNT 1, identidade e selo intactos
    -- ================================================================== --
    v_case := '2Q.5';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.5 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM false THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE: is_active=%s (esperado false)', c_env, v_case, v_act);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
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
    -- 2Q.6 — is_active FALSE → TRUE ⇒ EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN, mesmo sem outro
    --        ativo para o token (FXd)
    -- ================================================================== --
    v_case := '2Q.6';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.6 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM false THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE: is_active=%s (esperado false)', c_env, v_case, v_act);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND raw_field = 'subtype'
           AND normalized_token = v_tok AND is_active;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token ainda tem %s ativo(s) (esperado nenhum)', c_env, v_case, v_n);
        END IF;

        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            UPDATE public.card_edition_context_external_mapping SET is_active = true WHERE id = v_m1 AND normalized_token = v_tok;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s reativação FALSE → TRUE foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM false THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s M1 reativado pelo negativo (is_active=%s)', c_env, v_case, v_act);
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
    -- 2Q.7 — TRUE → TRUE e FALSE → FALSE são no-op sem erro (FXd)
    -- ================================================================== --
    v_case := '2Q.7';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 2Q.7 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
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

        -- pré-condição conferida de novo depois da sonda
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pós-sonda: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        UPDATE public.card_edition_context_external_mapping SET is_active = true WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s no-op TRUE → TRUE afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM true THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s no-op TRUE → TRUE: is_active=%s (esperado true)', c_env, v_case, v_act);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s no-op TRUE → TRUE: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM false THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE: is_active=%s (esperado false)', c_env, v_case, v_act);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria TRUE → FALSE: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
        END IF;

        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s no-op FALSE → FALSE afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT is_active INTO v_act FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_act IS DISTINCT FROM false THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s no-op FALSE → FALSE: is_active=%s (esperado false)', c_env, v_case, v_act);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND traits_signature = ARRAY[v_t1];
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s no-op FALSE → FALSE: identidade ou selo de M1 divergente (linhas=%s)', c_env, v_case, v_n);
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
    -- 2Q.8 — token não canônico persiste normalizado: 'set-logo' → 'SET-LOGO', 'Pokébola' → 'POKEBOLA',
    --        'BLUE  BORDER' → 'BLUE BORDER' (FX). N-3: tokens literais SEM marcador, escopo SCOPED no Set de
    --        fixture v_set1 (marcado) ⇒ chave única disjunta de todo mapping LIVE; colisão ⇒ H2830_FAIL (STOP)
    -- ================================================================== --
    v_case := '2Q.8';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        v_set1 := v_marker || '_S1';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND external_set_id = v_set1;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N-3: colisão com mapping existente no escopo de fixture (%s linha(s)) — STOP', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', 'set-logo')
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', 'Pokébola')
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', 'BLUE  BORDER')
        RETURNING id INTO v_m3;
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1 AND external_set_id = v_set1;
        IF v_txt IS DISTINCT FROM 'SET-LOGO' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token literal n.1 persistiu como %s (esperado %s)', c_env, v_case, v_txt, 'SET-LOGO');
        END IF;
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m2 AND external_set_id = v_set1;
        IF v_txt IS DISTINCT FROM 'POKEBOLA' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token literal n.2 persistiu como %s (esperado %s)', c_env, v_case, v_txt, 'POKEBOLA');
        END IF;
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m3 AND external_set_id = v_set1;
        IF v_txt IS DISTINCT FROM 'BLUE BORDER' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token literal n.3 persistiu como %s (esperado %s)', c_env, v_case, v_txt, 'BLUE BORDER');
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND external_set_id = v_set1;
        IF v_n <> 3 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N-3: %s fixture(s) no escopo v_set1 (esperado 3)', c_env, v_case, v_n);
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
    -- 2Q.9 — token que normaliza para vazio ('   ') ⇒ EDITION_CONTEXT_MAPPING_EMPTY_TOKEN (FX; escopo v_set1 marcado)
    -- ================================================================== --
    v_case := '2Q.9';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        v_set1 := v_marker || '_S1';
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, v_set1, 'subtype', '   ')
            RETURNING id INTO v_m1;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;

        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s INSERT de token vazio foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_MAPPING_EMPTY_TOKEN:') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s step=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_step, v_con, v_tab, v_msg);
        END IF;

        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND external_set_id = v_set1;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s %s linha(s) persistida(s) com token vazio', c_env, v_case, v_n);
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
    -- 2Q.10 — external_set_id só aparado, nunca uppercased: '  dp1  ' persiste 'dp1' (FX). N-3: Set literal
    --         sem marcador, token marcado v_tok ⇒ chave única disjunta de todo mapping LIVE; colisão ⇒ STOP
    -- ================================================================== --
    v_case := '2Q.10';
    v_t1 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_q := NULL;
    v_step := NULL;
    v_sig := NULL;
    v_ord_t := NULL;
    v_txt := NULL;
    v_act := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND normalized_token = v_tok;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s N-3: colisão com mapping existente no token de fixture (%s linha(s)) — STOP', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, '  dp1  ', 'subtype', v_tok)
        RETURNING id INTO v_m1;
        SELECT external_set_id INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1 AND normalized_token = v_tok;
        IF v_txt IS DISTINCT FROM 'dp1' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s external_set_id persistiu como %s (esperado dp1: só aparado, nunca uppercased)', c_env, v_case, v_txt);
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
    -- vez; exatamente 7 sondas (uma por IMMEDIATE)
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;
    IF v_qn <> 7 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE sondas=%s (esperado 7)', c_env, v_qn);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END
$h2830_e05$;
