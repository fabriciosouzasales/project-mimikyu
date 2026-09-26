-- ============================================================================
-- 2830H · ENVELOPE E01 — SEÇÃO 1 (ESTRUTURAL) · 12 casos: 1.1 – 1.12
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. Execução exige
--                 mandato próprio, precheck E00 com gate_pass e as decisões
--                 operacionais pendentes (ver harness/README.md).
-- Contrato ...... database/proposals/2026-09-18-edition-context-axis/
--                 2830_validate_edition_context_foundation.sql
--                 v7.0 · blob b4647dcb59432405c8157e2733fd78678f35540e
--                 (autoridade imutável; este arquivo a implementa, não a altera)
-- Protocolo ..... P1 teste transacional com rollback integral (ESCREVE
--                 fixtures e desfaz) · P2 um único DO, sem COMMIT/TEMP/
--                 set_config/SET ROLE, terminando SEMPRE em exceção ·
--                 P3 cada caso em subtransação; negativo confere SQLSTATE +
--                 CONSTRAINT_NAME + TABLE_NAME; positivo confere efeito;
--                 NOTICE nunca é evidência · P5 marcador único por execução ·
--                 P13 não aplicável (asserções de catálogo com cardinalidade
--                 exata e fixtures próprias; nenhum universo de dado LIVE).
--
-- SINAIS (SQLSTATE próprios, classe H283x — não colidem com o PostgreSQL):
--   H283C  fim normal de um caso: desfaz as fixtures DO CASO e só então conta
--   H283F  H2830_FAIL — aborta o envelope inteiro (rollback)
--   H283P  H2830_ROLLBACK_PASS — sinal terminal de sucesso (rollback)
--   Qualquer outro erro que escape é FAIL: o envelope nunca termina em
--   "sucesso" do ponto de vista do PostgreSQL. Retorno [] do MCP = DEFEITO.
--
-- FIXTURES DESTE ENVELOPE (todas desfeitas pela subtransação do caso):
--   1.3  INSERT card_edition_context_trait (1 negativo + 1 contraprova)
--   1.4  INSERT card_edition_context_trait (2 positivos + 1 negativo)
--   1.6  INSERT card_edition_context_profile (negativo)
--   1.7  INSERT card_edition_context_profile (negativo)
--   1.9  INSERT card_edition_context_external_mapping (2 negativos + 1
--        contraprova)
--   1.10 INSERT card_edition_context_external_mapping (negativo)
--   Nenhum UPDATE/DELETE em linha pré-existente. Nenhuma RPC. Tabelas com
--   id UUID (gen_random_uuid): sem sequence a consumir — confirmar em E00.
--   Triggers atingidos: trg_cecem_normalize (BEFORE INSERT, só normaliza);
--   trg_cecp_seal / trg_cecem_seal (AFTER, DEFERRED) só enfileiram evento
--   em INSERT BEM-SUCEDIDO (contraprova 1.9), e o evento é descartado pelo
--   rollback da subtransação do caso.
--
-- P8 lock_timeout — DECISÃO OPERACIONAL PENDENTE. Se autorizada, a linha
--   abaixo passa a ser a PRIMEIRA instrução do corpo, e a primeira asserção
--   confere current_setting('lock_timeout') = '5s':
--     -- SET LOCAL lock_timeout = '5s';
--   Enquanto não autorizada, NÃO é emitida.
-- ============================================================================
DO $h2830_e01$
DECLARE
    c_env      CONSTANT text   := 'E01_SECAO1_ESTRUTURAL';
    c_expected CONSTANT text[] := ARRAY['1.1','1.2','1.3','1.4','1.5','1.6',
                                        '1.7','1.8','1.9','1.10','1.11','1.12'];
    c_tables   CONSTANT text[] := ARRAY['card_edition_context_trait',
                                        'card_edition_context_profile',
                                        'card_edition_context_profile_trait',
                                        'card_edition_context_external_mapping',
                                        'card_edition_context_external_mapping_trait'];
    v_marker   text        := 'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''));
    v_t0       timestamptz := clock_timestamp();
    v_done     text[]      := ARRAY[]::text[];
    v_case     text;
    v_game     uuid;
    v_src      uuid;
    v_n        bigint;
    v_id       uuid;
    v_txt      text;
    v_arr      text[];
    v_got      boolean;
    v_state    text;
    v_con      text;
    v_tab      text;
    v_msg      text;
    v_order    integer;
    v_rel      oid;
    v_idx      oid;
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

    SELECT count(*) INTO v_n FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT asset_source code=TCGDEX count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';

    -- ================================================================== --
    -- 1.1 — as 5 tabelas EC existem em public como tabelas comuns
    -- ================================================================== --
    v_case := '1.1';
    BEGIN
        SELECT count(*) INTO v_n
          FROM unnest(c_tables) AS t(name)
          JOIN pg_class c ON c.oid = to_regclass('public.' || t.name)
         WHERE c.relkind = 'r';
        IF v_n <> 5 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tabelas EC presentes=%s (esperado 5)', c_env, v_case, v_n);
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
    -- 1.2 — card_edition_context_trait: exatamente 11 entradas em
    --       pg_constraint (9 nomeadas + PK + FK game; PG 17 não lista NOT NULL)
    -- ================================================================== --
    v_case := '1.2';
    BEGIN
        SELECT count(*) INTO v_n
          FROM pg_constraint
         WHERE conrelid = to_regclass('public.card_edition_context_trait');
        IF v_n <> 11 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pg_constraint(trait)=%s (esperado 11)', c_env, v_case, v_n);
        END IF;
        -- as 9 nomeadas do DDL (2203), uma a uma
        SELECT count(*) INTO v_n
          FROM pg_constraint
         WHERE conrelid = to_regclass('public.card_edition_context_trait')
           AND conname = ANY (ARRAY['ck_cect_family','ck_cect_code_format',
                                    'ck_cect_code_family_prefix','ck_cect_name_not_blank',
                                    'ck_cect_description_not_blank','ck_cect_display_order_positive',
                                    'uq_cect_game_code','uq_cect_game_family_order','uq_cect_id_game']);
        IF v_n <> 9 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s constraints nomeadas=%s (esperado 9)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) FILTER (WHERE contype = 'p'), count(*) FILTER (WHERE contype = 'f')
          INTO v_n, v_order
          FROM pg_constraint
         WHERE conrelid = to_regclass('public.card_edition_context_trait');
        IF v_n <> 1 OR v_order <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s PK=%s FK=%s (esperado 1/1)', c_env, v_case, v_n, v_order);
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
    -- 1.3 — ck_cect_code_family_prefix rejeita DECK_PLAYER sem prefixo
    --       negativo: 23514 + ck_cect_code_family_prefix + tabela
    --       contraprova: o MESMO insert com prefixo DECK_PLAYER_ é aceito
    -- ================================================================== --
    v_case := '1.3';
    BEGIN
        SELECT COALESCE(max(display_order), 0) + 1000 INTO v_order
          FROM public.card_edition_context_trait WHERE game_id = v_game;

        v_got := false;
        BEGIN
            INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
            VALUES (v_game, 'DECK_PLAYER', v_marker || '_NOPREFIX', 'H2830 fixture 1.3', v_order);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s INSERT DECK_PLAYER sem prefixo foi ACEITO', c_env, v_case);
        END IF;
        IF v_state <> '23514' OR v_con IS DISTINCT FROM 'ck_cect_code_family_prefix'
           OR v_tab IS DISTINCT FROM 'card_edition_context_trait' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s',
                c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;

        -- contraprova positiva: só o prefixo decide
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'DECK_PLAYER', 'DECK_PLAYER_' || v_marker, 'H2830 fixture 1.3 ok', v_order)
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s contraprova com prefixo não retornou id', c_env, v_case);
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
    -- 1.4 — uq_cect_game_family_order é por FAMÍLIA, não global
    --       RO: constraint 'u' com colunas exatas (game_id, family, display_order)
    --       FX: mesma ordem em famílias distintas coexiste; na mesma família,
    --           23505 + uq_cect_game_family_order
    -- ================================================================== --
    v_case := '1.4';
    BEGIN
        SELECT array_agg(a.attname::text ORDER BY k.ord) INTO v_arr
          FROM pg_constraint c
          CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
         WHERE c.conrelid = to_regclass('public.card_edition_context_trait')
           AND c.conname = 'uq_cect_game_family_order'
           AND c.contype = 'u';
        IF v_arr IS DISTINCT FROM ARRAY['game_id','family','display_order'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s colunas de uq_cect_game_family_order=%s', c_env, v_case, v_arr);
        END IF;

        SELECT COALESCE(max(display_order), 0) + 1000 INTO v_order
          FROM public.card_edition_context_trait WHERE game_id = v_game;

        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_A', 'H2830 fixture 1.4 A', v_order);
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'CHANNEL', v_marker || '_B', 'H2830 fixture 1.4 B', v_order);

        SELECT count(*) INTO v_n
          FROM public.card_edition_context_trait
         WHERE game_id = v_game AND display_order = v_order AND code IN (v_marker || '_A', v_marker || '_B');
        IF v_n <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mesma ordem em famílias distintas: %s linhas (esperado 2)', c_env, v_case, v_n);
        END IF;

        v_got := false;
        BEGIN
            INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
            VALUES (v_game, 'EVENT', v_marker || '_C', 'H2830 fixture 1.4 C', v_order);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mesma família + mesma ordem foi ACEITA', c_env, v_case);
        END IF;
        IF v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_cect_game_family_order'
           OR v_tab IS DISTINCT FROM 'card_edition_context_trait' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s',
                c_env, v_case, v_state, v_con, v_tab, v_msg);
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
    -- 1.5 — uq_cecp_game_signature existe, é UNIQUE e parcial em
    --       traits_signature IS NOT NULL, sobre (game_id, traits_signature)
    -- ================================================================== --
    v_case := '1.5';
    BEGIN
        v_idx := to_regclass('public.uq_cecp_game_signature');
        IF v_idx IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s índice uq_cecp_game_signature ausente', c_env, v_case);
        END IF;
        SELECT i.indrelid, (i.indisunique AND i.indisvalid AND i.indisready),
               pg_get_expr(i.indpred, i.indrelid)
          INTO v_rel, v_got, v_txt
          FROM pg_index i WHERE i.indexrelid = v_idx;
        IF v_rel IS DISTINCT FROM to_regclass('public.card_edition_context_profile')
           OR v_got IS NOT TRUE
           OR v_txt IS DISTINCT FROM '(traits_signature IS NOT NULL)' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tabela=%s unique/valid/ready=%s predicado=%s',
                c_env, v_case, v_rel::regclass, v_got, v_txt);
        END IF;
        SELECT array_agg(a.attname::text ORDER BY k.ord) INTO v_arr
          FROM pg_index i
          CROSS JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
         WHERE i.indexrelid = v_idx AND k.ord <= i.indnkeyatts;
        IF v_arr IS DISTINCT FROM ARRAY['game_id','traits_signature'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s colunas=%s', c_env, v_case, v_arr);
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
    -- 1.6 — ck_cecp_signature_not_empty rejeita '{}'
    --       (trg_cecp_signature_write é BEFORE UPDATE: não interfere no INSERT)
    -- ================================================================== --
    v_case := '1.6';
    BEGIN
        SELECT COALESCE(max(display_order), 0) + 1000 INTO v_order
          FROM public.card_edition_context_profile WHERE game_id = v_game;
        v_got := false;
        BEGIN
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order, traits_signature)
            VALUES (v_game, v_marker || '_EMPTY', 'H2830 fixture 1.6', v_order, '{}'::uuid[]);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s traits_signature ''{}'' foi ACEITA', c_env, v_case);
        END IF;
        IF v_state <> '23514' OR v_con IS DISTINCT FROM 'ck_cecp_signature_not_empty'
           OR v_tab IS DISTINCT FROM 'card_edition_context_profile' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s',
                c_env, v_case, v_state, v_con, v_tab, v_msg);
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
    -- 1.7 — ck_cecp_signature_shape rejeita array 2-D (2x1: não vazio,
    --       logo só a forma pode rejeitar)
    -- ================================================================== --
    v_case := '1.7';
    BEGIN
        SELECT COALESCE(max(display_order), 0) + 1000 INTO v_order
          FROM public.card_edition_context_profile WHERE game_id = v_game;
        v_got := false;
        BEGIN
            INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order, traits_signature)
            VALUES (v_game, v_marker || '_2D', 'H2830 fixture 1.7', v_order,
                    ARRAY[[gen_random_uuid()], [gen_random_uuid()]]);
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s traits_signature 2-D foi ACEITA', c_env, v_case);
        END IF;
        IF v_state <> '23514' OR v_con IS DISTINCT FROM 'ck_cecp_signature_shape'
           OR v_tab IS DISTINCT FROM 'card_edition_context_profile' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s',
                c_env, v_case, v_state, v_con, v_tab, v_msg);
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
    -- 1.8 — N:N (profile_trait) tem as DUAS FKs compostas same-Game
    --       fk_cecpt_profile: (profile_id, game_id) -> profile (id, game_id)
    --       fk_cecpt_trait:   (trait_id,   game_id) -> trait   (id, game_id)
    -- ================================================================== --
    v_case := '1.8';
    BEGIN
        SELECT count(*) INTO v_n
          FROM pg_constraint c
         WHERE c.conrelid = to_regclass('public.card_edition_context_profile_trait')
           AND c.contype = 'f'
           AND (
                 (c.conname = 'fk_cecpt_profile'
                  AND c.confrelid = to_regclass('public.card_edition_context_profile')
                  AND (SELECT array_agg(a.attname::text ORDER BY k.ord)
                         FROM unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
                         JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum)
                      = ARRAY['profile_id','game_id']
                  AND (SELECT array_agg(a.attname::text ORDER BY k.ord)
                         FROM unnest(c.confkey) WITH ORDINALITY k(attnum, ord)
                         JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.attnum)
                      = ARRAY['id','game_id'])
              OR (c.conname = 'fk_cecpt_trait'
                  AND c.confrelid = to_regclass('public.card_edition_context_trait')
                  AND (SELECT array_agg(a.attname::text ORDER BY k.ord)
                         FROM unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
                         JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum)
                      = ARRAY['trait_id','game_id']
                  AND (SELECT array_agg(a.attname::text ORDER BY k.ord)
                         FROM unnest(c.confkey) WITH ORDINALITY k(attnum, ord)
                         JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.attnum)
                      = ARRAY['id','game_id'])
           );
        IF v_n <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s FKs compostas exatas=%s (esperado 2)', c_env, v_case, v_n);
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
    -- 1.9 — ck_cecem_raw_field rejeita 'type' e 'size'
    --       (trg_cecem_normalize roda antes e só normaliza o token)
    --       contraprova: raw_field 'stamp' com token novo é aceito
    -- ================================================================== --
    v_case := '1.9';
    BEGIN
        FOREACH v_txt IN ARRAY ARRAY['type','size'] LOOP
            v_got := false;
            BEGIN
                INSERT INTO public.card_edition_context_external_mapping
                       (game_id, asset_source_id, raw_field, normalized_token)
                VALUES (v_game, v_src, v_txt, v_marker || '_RF_' || upper(v_txt));
            EXCEPTION WHEN OTHERS THEN
                v_got := true;
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                        v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
            END;
            IF NOT v_got THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s raw_field=%s foi ACEITO', c_env, v_case, v_txt);
            END IF;
            IF v_state <> '23514' OR v_con IS DISTINCT FROM 'ck_cecem_raw_field'
               OR v_tab IS DISTINCT FROM 'card_edition_context_external_mapping' THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s raw_field=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s',
                    c_env, v_case, v_txt, v_state, v_con, v_tab, v_msg);
            END IF;
        END LOOP;

        INSERT INTO public.card_edition_context_external_mapping
               (game_id, asset_source_id, raw_field, normalized_token)
        VALUES (v_game, v_src, 'stamp', v_marker || '_RF_STAMP')
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s contraprova stamp não retornou id', c_env, v_case);
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
    -- 1.10 — raw_field 'foil' rejeitado por ck_cecem_raw_field; e NÃO existe
    --        nenhuma constraint ck_cecem_foil_allowlist (em nenhum schema)
    -- ================================================================== --
    v_case := '1.10';
    BEGIN
        SELECT count(*) INTO v_n FROM pg_constraint WHERE conname = 'ck_cecem_foil_allowlist';
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ck_cecem_foil_allowlist existe (%s)', c_env, v_case, v_n);
        END IF;
        v_got := false;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping
                   (game_id, asset_source_id, raw_field, normalized_token)
            VALUES (v_game, v_src, 'foil', v_marker || '_RF_FOIL');
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s raw_field=foil foi ACEITO', c_env, v_case);
        END IF;
        IF v_state <> '23514' OR v_con IS DISTINCT FROM 'ck_cecem_raw_field'
           OR v_tab IS DISTINCT FROM 'card_edition_context_external_mapping' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s',
                c_env, v_case, v_state, v_con, v_tab, v_msg);
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
    -- 1.11 — uq_cecem_active_global e uq_cecem_active_scoped: UNIQUE,
    --        parciais em is_active e disjuntos pela nulidade de
    --        external_set_id; ix_cecem_token: NÃO único e NÃO parcial.
    --        Predicados literais medidos no LIVE em 2026-09-26.
    -- ================================================================== --
    v_case := '1.11';
    BEGIN
        -- global
        v_idx := to_regclass('public.uq_cecem_active_global');
        SELECT (i.indisunique AND i.indisvalid AND i.indisready), pg_get_expr(i.indpred, i.indrelid), i.indrelid
          INTO v_got, v_txt, v_rel FROM pg_index i WHERE i.indexrelid = v_idx;
        SELECT array_agg(a.attname::text ORDER BY k.ord) INTO v_arr
          FROM pg_index i
          CROSS JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
         WHERE i.indexrelid = v_idx AND k.ord <= i.indnkeyatts;
        IF v_idx IS NULL OR v_got IS NOT TRUE
           OR v_rel IS DISTINCT FROM to_regclass('public.card_edition_context_external_mapping')
           OR v_txt IS DISTINCT FROM '((external_set_id IS NULL) AND is_active)'
           OR v_arr IS DISTINCT FROM ARRAY['game_id','asset_source_id','raw_field','normalized_token'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_cecem_active_global divergente unique=%s pred=%s cols=%s',
                c_env, v_case, v_got, v_txt, v_arr);
        END IF;
        -- scoped
        v_idx := to_regclass('public.uq_cecem_active_scoped');
        SELECT (i.indisunique AND i.indisvalid AND i.indisready), pg_get_expr(i.indpred, i.indrelid), i.indrelid
          INTO v_got, v_txt, v_rel FROM pg_index i WHERE i.indexrelid = v_idx;
        SELECT array_agg(a.attname::text ORDER BY k.ord) INTO v_arr
          FROM pg_index i
          CROSS JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
         WHERE i.indexrelid = v_idx AND k.ord <= i.indnkeyatts;
        IF v_idx IS NULL OR v_got IS NOT TRUE
           OR v_rel IS DISTINCT FROM to_regclass('public.card_edition_context_external_mapping')
           OR v_txt IS DISTINCT FROM '((external_set_id IS NOT NULL) AND is_active)'
           OR v_arr IS DISTINCT FROM ARRAY['game_id','asset_source_id','external_set_id','raw_field','normalized_token'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_cecem_active_scoped divergente unique=%s pred=%s cols=%s',
                c_env, v_case, v_got, v_txt, v_arr);
        END IF;
        -- token (histórico + ativo)
        v_idx := to_regclass('public.ix_cecem_token');
        SELECT i.indrelid INTO v_rel FROM pg_index i WHERE i.indexrelid = v_idx;
        SELECT array_agg(a.attname::text ORDER BY k.ord) INTO v_arr
          FROM pg_index i
          CROSS JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
         WHERE i.indexrelid = v_idx AND k.ord <= i.indnkeyatts;
        SELECT count(*) INTO v_n FROM pg_index WHERE indexrelid = v_idx AND indpred IS NULL AND NOT indisunique;
        IF v_idx IS NULL OR v_n <> 1
           OR v_rel IS DISTINCT FROM to_regclass('public.card_edition_context_external_mapping')
           OR v_arr IS DISTINCT FROM ARRAY['game_id','asset_source_id','raw_field','normalized_token'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ix_cecem_token divergente total_nao_unico=%s cols=%s',
                c_env, v_case, v_n, v_arr);
        END IF;
        -- prova negativa de nome: os nomes antigos não existem mais
        SELECT count(*) INTO v_n FROM pg_class WHERE relname IN ('uq_cecem_global','uq_cecem_scoped');
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s índices antigos uq_cecem_global/scoped ainda existem (%s)', c_env, v_case, v_n);
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
    -- 1.12 — grants das 5 tabelas: anon nenhum privilégio; authenticated
    --        somente SELECT. Matriz COMPLETA de privilégios de tabela do
    --        PostgreSQL 17: SELECT, INSERT, UPDATE, DELETE, TRUNCATE,
    --        REFERENCES, TRIGGER, MAINTAIN (8) × 2 papéis × 5 tabelas = 80
    --        verificações. MAINTAIN (PG 17: VACUUM/ANALYZE/CLUSTER/REFRESH/
    --        REINDEX/LOCK) faltava na primeira versão — correção
    --        BATCH12-2830-HARNESS-FOUNDATION-CORRECTION-01.
    -- ================================================================== --
    v_case := '1.12';
    BEGIN
        SELECT count(*) INTO v_n
          FROM unnest(c_tables) AS t(name)
          CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) AS p(priv)
         WHERE has_table_privilege('anon', to_regclass('public.' || t.name), p.priv)
            OR (p.priv =  'SELECT' AND NOT has_table_privilege('authenticated', to_regclass('public.' || t.name), p.priv))
            OR (p.priv <> 'SELECT' AND     has_table_privilege('authenticated', to_regclass('public.' || t.name), p.priv));
        IF v_n <> 0 THEN
            SELECT string_agg(t.name || ':' || p.priv, ', ') INTO v_txt
              FROM unnest(c_tables) AS t(name)
              CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) AS p(priv)
             WHERE has_table_privilege('anon', to_regclass('public.' || t.name), p.priv)
                OR (p.priv =  'SELECT' AND NOT has_table_privilege('authenticated', to_regclass('public.' || t.name), p.priv))
                OR (p.priv <> 'SELECT' AND     has_table_privilege('authenticated', to_regclass('public.' || t.name), p.priv));
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s violações de grant=%s [%s]', c_env, v_case, v_n, v_txt);
        END IF;
        -- anti-vácuo do próprio caso: as 5 tabelas foram de fato avaliadas
        SELECT count(*) INTO v_n FROM unnest(c_tables) AS t(name) WHERE to_regclass('public.' || t.name) IS NOT NULL;
        IF v_n <> 5 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s tabelas avaliadas=%s (esperado 5)', c_env, v_case, v_n);
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
    -- GATE DO ENVELOPE: exatamente os 12 casos, na ordem, cada um uma vez
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
$h2830_e01$;
