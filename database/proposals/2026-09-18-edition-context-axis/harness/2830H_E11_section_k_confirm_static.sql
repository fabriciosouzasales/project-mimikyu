-- ============================================================================
-- 2830H · ENVELOPE E11 — SEÇÃO K (PROVA ESTÁTICA DO CONFIRM) · lote L9, 3 casos: K3, K4, K8
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
-- Contrato ...... 2830 v7.0 · K3-S, K4-S, K8a [AUTO ST]. Prova que o código DIZ
--                 isso; não prova que ELE FAZ (K3-B/K4-B/K8b são MANUAIS, P14).
-- Autoridade .... 2218 (confirm), corpo fixado: md5 LF b83f7708ca2b7498b753b394d768f66e.
-- Leitura ....... espaços normalizados (\s+ -> ' '); regiões: matching = [FOR v_row IN,
--                 WHEN unique_violation); handler = [WHEN unique_violation, WHEN OTHERS).
-- Escrita ....... NENHUMA. Nenhuma chamada ao confirm. Sem precheck próprio: o
--                 gate de entrada é o E00 (inventário) + o pino do corpo aqui.
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e11$
DECLARE
    c_env      CONSTANT text   := 'E11_SECAO_K_CONFIRM_ESTATICO';
    c_expected CONSTANT text[] := ARRAY['K3','K4','K8'];
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
    v_body     text;
    v_nrm      text;
    v_hnd      text;
    v_mat      text;
    v_ho       integer;
    v_hx       integer;
    v_lp       integer;
    v_lk       integer;
    v_le       integer;
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
    -- K3-S [AUTO ST] handler unique_violation: antes de OTHERS, CONSTRAINT_NAME,
    -- releitura 4 componentes IS NOT DISTINCT FROM, UNRESOLVED sem re-raise
    -- ================================================================== --
    v_case := 'K3';
    v_body := NULL;
    v_nrm := NULL;
    v_hnd := NULL;
    v_mat := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM pg_proc p WHERE p.oid = to_regprocedure('public.admin_confirm_catalog_variant_import(uuid,uuid[])');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s confirm ausente: %s', c_env, v_case, v_n);
        END IF;
        SELECT replace(p.prosrc, chr(13) || chr(10), chr(10)) INTO v_body
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.admin_confirm_catalog_variant_import(uuid,uuid[])');
        v_txt := md5(v_body);
        IF v_txt IS DISTINCT FROM 'b83f7708ca2b7498b753b394d768f66e' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s corpo LIVE do confirm fora do pino: md5_lf=%s', c_env, v_case, v_txt);
        END IF;
        v_nrm := regexp_replace(v_body, '\s+', ' ', 'g');
        v_ho := strpos(v_nrm, 'WHEN unique_violation THEN');
        v_hx := strpos(v_nrm, 'WHEN OTHERS THEN');
        v_lp := strpos(v_nrm, 'FOR v_row IN');
        IF v_ho = 0 OR v_hx = 0 OR v_lp = 0 OR NOT (v_lp < v_ho AND v_ho < v_hx) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s marcos do confirm fora de ordem: loop=%s unique_violation=%s others=%s', c_env, v_case, v_lp, v_ho, v_hx);
        END IF;
        IF strpos(substr(v_nrm, v_ho + 1), 'WHEN unique_violation THEN') <> 0 OR strpos(substr(v_nrm, v_hx + 1), 'WHEN OTHERS THEN') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mais de um handler unique_violation/OTHERS no corpo (leitura ambígua)', c_env, v_case);
        END IF;
        v_hnd := substr(v_nrm, v_ho, v_hx - v_ho);
        v_mat := substr(v_nrm, v_lp, v_ho - v_lp);
        IF NOT (strpos(v_hnd, 'GET STACKED DIAGNOSTICS') > 0 AND strpos(v_hnd, '= CONSTRAINT_NAME') > 0) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s handler unique_violation não lê CONSTRAINT_NAME por GET STACKED DIAGNOSTICS', c_env, v_case);
        END IF;
        IF NOT (strpos(v_hnd, 'SELECT cv.id INTO v_race_variant_id FROM public.card_variant cv') > 0 AND strpos(v_hnd, 'WHERE cv.card_id = v_row.card_id AND cv.variant_type_id = v_variant_type_id') > 0 AND strpos(v_hnd, 'AND cv.printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id') > 0 AND strpos(v_hnd, 'AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id') > 0) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s releitura do handler não usa a identidade de 4 componentes com IS NOT DISTINCT FROM', c_env, v_case);
        END IF;
        IF NOT strpos(v_hnd, 'error_detail = ''CARD_VARIANT_UNIQUE_VIOLATION_UNRESOLVED:') > 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s handler não grava CARD_VARIANT_UNIQUE_VIOLATION_UNRESOLVED: em error_detail', c_env, v_case);
        END IF;
        IF strpos(upper(v_hnd), 'RAISE') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s handler unique_violation re-levanta (RAISE presente)', c_env, v_case);
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
    -- K4-S [AUTO ST] matching e releitura com IS NOT DISTINCT FROM nos 2 eixos nuláveis
    -- ================================================================== --
    v_case := 'K4';
    v_body := NULL;
    v_nrm := NULL;
    v_hnd := NULL;
    v_mat := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM pg_proc p WHERE p.oid = to_regprocedure('public.admin_confirm_catalog_variant_import(uuid,uuid[])');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s confirm ausente: %s', c_env, v_case, v_n);
        END IF;
        SELECT replace(p.prosrc, chr(13) || chr(10), chr(10)) INTO v_body
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.admin_confirm_catalog_variant_import(uuid,uuid[])');
        v_txt := md5(v_body);
        IF v_txt IS DISTINCT FROM 'b83f7708ca2b7498b753b394d768f66e' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s corpo LIVE do confirm fora do pino: md5_lf=%s', c_env, v_case, v_txt);
        END IF;
        v_nrm := regexp_replace(v_body, '\s+', ' ', 'g');
        v_ho := strpos(v_nrm, 'WHEN unique_violation THEN');
        v_hx := strpos(v_nrm, 'WHEN OTHERS THEN');
        v_lp := strpos(v_nrm, 'FOR v_row IN');
        IF v_ho = 0 OR v_hx = 0 OR v_lp = 0 OR NOT (v_lp < v_ho AND v_ho < v_hx) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s marcos do confirm fora de ordem: loop=%s unique_violation=%s others=%s', c_env, v_case, v_lp, v_ho, v_hx);
        END IF;
        IF strpos(substr(v_nrm, v_ho + 1), 'WHEN unique_violation THEN') <> 0 OR strpos(substr(v_nrm, v_hx + 1), 'WHEN OTHERS THEN') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mais de um handler unique_violation/OTHERS no corpo (leitura ambígua)', c_env, v_case);
        END IF;
        v_hnd := substr(v_nrm, v_ho, v_hx - v_ho);
        v_mat := substr(v_nrm, v_lp, v_ho - v_lp);
        IF NOT (strpos(v_mat, 'SELECT cv.* INTO v_existing_variant FROM public.card_variant cv') > 0 AND strpos(v_mat, 'WHERE cv.card_id = v_row.card_id AND cv.variant_type_id = v_variant_type_id') > 0 AND strpos(v_mat, 'AND cv.printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id') > 0 AND strpos(v_mat, 'AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id') > 0) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s matching do confirm não usa IS NOT DISTINCT FROM nos dois eixos nuláveis', c_env, v_case);
        END IF;
        IF NOT (strpos(v_hnd, 'AND cv.printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id') > 0 AND strpos(v_hnd, 'AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id') > 0) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s releitura do confirm não usa IS NOT DISTINCT FROM nos dois eixos nuláveis', c_env, v_case);
        END IF;
        IF strpos(v_nrm, 'printing_profile_id = v_printing_profile_id') <> 0 OR strpos(v_nrm, 'edition_context_profile_id = v_edition_context_profile_id') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s igualdade simples (=) num eixo nulável da identidade', c_env, v_case);
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
    -- K8a [AUTO ST] FOR UPDATE das Cards do lote com ORDER BY c.id, antes do loop
    -- ================================================================== --
    v_case := 'K8';
    v_body := NULL;
    v_nrm := NULL;
    v_hnd := NULL;
    v_mat := NULL;
    BEGIN
        SELECT count(*) INTO v_n FROM pg_proc p WHERE p.oid = to_regprocedure('public.admin_confirm_catalog_variant_import(uuid,uuid[])');
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s confirm ausente: %s', c_env, v_case, v_n);
        END IF;
        SELECT replace(p.prosrc, chr(13) || chr(10), chr(10)) INTO v_body
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.admin_confirm_catalog_variant_import(uuid,uuid[])');
        v_txt := md5(v_body);
        IF v_txt IS DISTINCT FROM 'b83f7708ca2b7498b753b394d768f66e' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s corpo LIVE do confirm fora do pino: md5_lf=%s', c_env, v_case, v_txt);
        END IF;
        v_nrm := regexp_replace(v_body, '\s+', ' ', 'g');
        v_ho := strpos(v_nrm, 'WHEN unique_violation THEN');
        v_hx := strpos(v_nrm, 'WHEN OTHERS THEN');
        v_lp := strpos(v_nrm, 'FOR v_row IN');
        IF v_ho = 0 OR v_hx = 0 OR v_lp = 0 OR NOT (v_lp < v_ho AND v_ho < v_hx) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s marcos do confirm fora de ordem: loop=%s unique_violation=%s others=%s', c_env, v_case, v_lp, v_ho, v_hx);
        END IF;
        IF strpos(substr(v_nrm, v_ho + 1), 'WHEN unique_violation THEN') <> 0 OR strpos(substr(v_nrm, v_hx + 1), 'WHEN OTHERS THEN') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s mais de um handler unique_violation/OTHERS no corpo (leitura ambígua)', c_env, v_case);
        END IF;
        v_hnd := substr(v_nrm, v_ho, v_hx - v_ho);
        v_mat := substr(v_nrm, v_lp, v_ho - v_lp);
        v_lk := strpos(v_nrm, 'PERFORM 1 FROM public.card c WHERE c.id IN (');
        v_le := strpos(v_nrm, 'ORDER BY c.id FOR UPDATE;');
        IF v_lk = 0 OR v_le = 0 OR NOT (v_lk < v_le AND v_le < v_lp) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s lock das Cards ausente, sem ORDER BY c.id FOR UPDATE, ou depois do loop: lock=%s fim=%s loop=%s', c_env, v_case, v_lk, v_le, v_lp);
        END IF;
        IF strpos(substr(v_nrm, v_lk, v_le - v_lk), 'LIMIT') <> 0 OR strpos(substr(v_nrm, v_le + 1), 'PERFORM 1 FROM public.card c WHERE c.id IN (') <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s bloco de lock ambíguo (LIMIT ou lock repetido)', c_env, v_case);
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
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s confirm_md5=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), 'b83f7708ca2b7498b753b394d768f66e');
END
$h2830_e11$;
