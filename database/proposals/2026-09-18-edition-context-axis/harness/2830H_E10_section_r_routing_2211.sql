-- ============================================================================
-- 2830H · ENVELOPE E10 — SEÇÃO R (ROUTING TERMINAL 2211) · lote L8, 12 casos: R1–R12
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).
--                 Execução exige E00 + E10P gate_pass = true e mandato próprio.
-- Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 624–653).
-- Autoridades ... 2211 (pino f10af378…), 2176 v2.0 (pino b15a527d…), 2192
--                 (escopo real de dp1 a partir do Card Set, nunca card_set.code),
--                 2207 (índices de ativo). R2/R10 são provas ESTÁTICAS declaradas.
-- Leitura ....... R6 "ambos UNRESOLVED" = nenhum eixo resolve: Printing
--                 RESOLVED_NO_PRINTING e EC RESOLVED_NO_EDITION_CONTEXT, residual
--                 intacto (estados LIVE da 2176/2211). R12 = saídas NEEDS_REVIEW_*
--                 de retorno antecipado (INACTIVE/INVALID_EC_MAPPING, achado A4 da
--                 2211): o residual devolvido é o residual integral do Printing.
--                 R10: a parte comportamental é inalcançável (nenhuma rota da 2176
--                 sem linha — provado sobre o prosrc pinado); nunca PASS
--                 comportamental.
-- Escrita (R1) .. só EC, fixture marcada: trait 11 · mapping 13 · N:N 11 ·
--                 UPDATE 4 (aposentadoria, WHERE id AND token) · DELETE 0.
--                 R12 cria 2 mappings ATIVOS sem N:N sem IMMEDIATE: o evento de selo
--                 pendente é descartado pelo H283C do caso (padrão L4).
-- P8 ............ SET LOCAL lock_timeout = '5s' + asserção (DP-4 = A).
-- ============================================================================
DO $h2830_e10$
DECLARE
    c_env      CONSTANT text   := 'E10_SECAO_R_ROUTING_2211';
    c_expected CONSTANT text[] := ARRAY['R1','R2','R3','R4','R5','R6','R7','R8','R9','R10','R11','R12'];
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
    v_t1       uuid;
    v_t2       uuid;
    v_t3       uuid;
    v_t4       uuid;
    v_m1       uuid;
    v_m2       uuid;
    v_m3       uuid;
    v_m4       uuid;
    v_m5       uuid;
    v_ord_t    integer;
    v_tok      text;
    v_tok2     text;
    v_tok3     text;
    v_tok4     text;
    v_tok5     text;
    v_tok6     text;
    v_cnt0     bigint[];
    v_cnt1     bigint[];
    v_set1     text;
    v_set2     text;
    v_raw      jsonb;
    v_cs       uuid;
    v_scope    text;
    v_sig      uuid[];
    v_prof     uuid;
    v_rf       text;
    v_ptok     text;
    v_psig     uuid[];
    v_pprof    uuid;
    v_ov       boolean;
    v_exp_st   text;
    v_k        bigint;
    v_k2       bigint;
    v_c1       text;
    v_b        boolean;
    v_cfg      text[];
    v_src2211  text;
    v_src2176  text;
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
    -- R1 — resolve_variant_row_axes(jsonb,uuid,uuid,text): STABLE, SECURITY DEFINER, search_path='', 10 OUT (RO)
    -- ================================================================== --
    v_case := 'R1';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT p.provolatile::text, p.prosecdef, p.proconfig::text[], p.pronargs::int,
               (SELECT count(*) FROM unnest(p.proargmodes) AS x(m) WHERE x.m = 't'),
               md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))
          INTO STRICT v_c1, v_b, v_cfg, v_n, v_m, v_txt
          FROM pg_proc p WHERE p.oid = to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)');
        IF v_c1 IS DISTINCT FROM 's' OR v_b IS DISTINCT FROM true OR v_cfg IS DISTINCT FROM ARRAY['search_path=""']
           OR v_n <> 4 OR v_m <> 10 OR v_txt IS DISTINCT FROM 'f10af378c2d5d9fdfd207d9c7d9ff046' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s assinatura da 2211 divergente: vol=%s secdef=%s config=%s nargs=%s out=%s md5=%s', c_env, v_case, v_c1, v_b, v_cfg, v_n, v_m, v_txt);
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
    -- R2 — prosrc chama internal.compute_variant_residual_signature (ST, declarado)
    -- ================================================================== --
    v_case := 'R2';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT p.prosrc, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) INTO STRICT v_src2211, v_txt
          FROM pg_proc p WHERE p.oid = to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)');
        IF v_txt IS DISTINCT FROM 'f10af378c2d5d9fdfd207d9c7d9ff046' OR strpos(v_src2211, 'FROM internal.compute_variant_residual_signature(p_raw_data, p_game_id, p_asset_source_id)') = 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s prosrc da 2211 não chama a 2176 como declarado (md5=%s)', c_env, v_case, v_txt);
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
    -- R3 — size fora de STANDARD ⇒ BLOCKED_* propagado, EC intocado (RC; controle standard)
    -- ================================================================== --
    v_case := 'R3';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT r.card_set_id INTO STRICT v_cs FROM public.card_set_external_reference r
         WHERE r.asset_source_id = v_src AND r.external_set_id = 'dp1' AND r.is_active;
        SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;
        IF v_scope IS DISTINCT FROM 'dp1' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s escopo resolvido %s (esperado dp1)', c_env, v_case, v_scope);
        END IF;
        SELECT m.traits_signature INTO STRICT v_sig FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'stamp'
           AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = v_scope AND m.is_active;
        SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p
         WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;
        IF v_sig IS NULL OR cardinality(v_sig) < 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET-LOGO em dp1: selo vazio (%s)', c_env, v_case, v_sig);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'size', 'JUMBO', 'stamp', jsonb_build_array('set-logo'));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_scope) AS r;
        IF v_ps IS DISTINCT FROM 'BLOCKED_SIZE_OUT_OF_SCOPE' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NOT_EVALUATED' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY['SET-LOGO'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (size JUMBO) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'size', 'oversized', 'stamp', jsonb_build_array('set-logo'));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_scope) AS r;
        IF v_ps IS DISTINCT FROM 'BLOCKED_SIZE_UNSUPPORTED' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NOT_EVALUATED' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY['SET-LOGO'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (size oversized) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'size', 'standard', 'stamp', jsonb_build_array('set-logo'));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_scope) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'RESOLVED_WITH_EC_PROFILE' OR v_ecp IS DISTINCT FROM v_prof OR v_ect IS DISTINCT FROM v_sig
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle: size standard) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- R4 — token consumido por Printing sai do residual e não alimenta EC (RC)
    -- ================================================================== --
    v_case := 'R4';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT c.raw_field, c.normalized_token, c.sig, pp.id,
               EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping e
                        WHERE e.game_id = v_game AND e.asset_source_id = v_src AND e.raw_field = c.raw_field
                          AND e.normalized_token = c.normalized_token AND e.is_active AND e.external_set_id IS NULL)
          INTO v_rf, v_ptok, v_psig, v_pprof, v_ov
          FROM (SELECT m.id, m.raw_field::text AS raw_field, m.normalized_token,
                       COALESCE(m.traits_signature,
                                ARRAY(SELECT mt.trait_id FROM public.card_printing_external_mapping_trait mt
                                       WHERE mt.mapping_id = m.id ORDER BY mt.trait_id)) AS sig
                  FROM public.card_printing_external_mapping m
                 WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.is_active
                   AND m.raw_field IN ('subtype', 'stamp')) c
          JOIN public.card_printing_profile pp ON pp.game_id = v_game AND pp.is_active AND pp.traits_signature = c.sig
         WHERE cardinality(c.sig) > 0
           AND NOT EXISTS (SELECT 1 FROM public.card_printing_trait t WHERE t.id = ANY (c.sig) AND NOT t.is_active)
           AND public.normalize_external_catalog_value(c.normalized_token) = c.normalized_token
         ORDER BY 5 DESC, c.id
         LIMIT 1;
        IF v_ptok IS NULL OR v_rf IS NULL OR v_pprof IS NULL OR v_ov IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem candidato de Printing (STOP; ver E10P g_35_candidate)', c_env, v_case);
        END IF;
        v_tok := v_marker || '_L';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        IF v_rf = 'subtype' THEN
            v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_ptok, 'stamp', jsonb_build_array(v_tok));
        ELSE
            v_raw := jsonb_build_object('type', 'H2830 TIPO', 'stamp', jsonb_build_array(v_ptok, v_tok));
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_WITH_PROFILE' OR v_pp IS DISTINCT FROM v_pprof OR v_pt IS DISTINCT FROM v_psig
           OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY[v_tok] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (token de Printing + token desconhecido) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        IF v_ptok = ANY (v_rsp) OR v_rst IS NOT DISTINCT FROM v_ptok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token de Printing %s voltou ao residual', c_env, v_case, v_ptok);
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
    -- R5 — token consumido por EC sai do residual de Finish (RC)
    -- ================================================================== --
    v_case := 'R5';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT r.card_set_id INTO STRICT v_cs FROM public.card_set_external_reference r
         WHERE r.asset_source_id = v_src AND r.external_set_id = 'dp1' AND r.is_active;
        SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;
        IF v_scope IS DISTINCT FROM 'dp1' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s escopo resolvido %s (esperado dp1)', c_env, v_case, v_scope);
        END IF;
        SELECT m.traits_signature INTO STRICT v_sig FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'stamp'
           AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = v_scope AND m.is_active;
        SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p
         WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;
        IF v_sig IS NULL OR cardinality(v_sig) < 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET-LOGO em dp1: selo vazio (%s)', c_env, v_case, v_sig);
        END IF;
        v_tok := v_marker || '_K';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array('set-logo'));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_scope) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'RESOLVED_WITH_EC_PROFILE' OR v_ecp IS DISTINCT FROM v_prof OR v_ect IS DISTINCT FROM v_sig
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (SET-LOGO consumido por EC) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- R6 — token desconhecido: nenhum eixo resolve, residual intacto; contagens inalteradas (RC+RO)
    -- ================================================================== --
    v_case := 'R6';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        v_tok2 := v_marker || '_L';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        SELECT ARRAY[(SELECT count(*) FROM public.card_edition_context_trait),
                     (SELECT count(*) FROM public.card_edition_context_profile),
                     (SELECT count(*) FROM public.card_edition_context_profile_trait),
                     (SELECT count(*) FROM public.card_edition_context_external_mapping),
                     (SELECT count(*) FROM public.card_edition_context_external_mapping_trait),
                     (SELECT count(*) FROM public.card_printing_trait),
                     (SELECT count(*) FROM public.card_printing_profile),
                     (SELECT count(*) FROM public.card_printing_external_mapping)]
          INTO v_cnt0;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok2));
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
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM ARRAY[v_tok2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (tokens desconhecidos) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        SELECT ARRAY[(SELECT count(*) FROM public.card_edition_context_trait),
                     (SELECT count(*) FROM public.card_edition_context_profile),
                     (SELECT count(*) FROM public.card_edition_context_profile_trait),
                     (SELECT count(*) FROM public.card_edition_context_external_mapping),
                     (SELECT count(*) FROM public.card_edition_context_external_mapping_trait),
                     (SELECT count(*) FROM public.card_printing_trait),
                     (SELECT count(*) FROM public.card_printing_profile),
                     (SELECT count(*) FROM public.card_printing_external_mapping)]
          INTO v_cnt1;
        IF v_cnt0 IS NULL OR v_cnt1 IS DISTINCT FROM v_cnt0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s contagens de vocabulário (EC trait/profile/profile_trait/mapping/mapping_trait · Printing trait/profile/mapping) alteradas pela RC: %s → %s', c_env, v_case, v_cnt0, v_cnt1);
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
    -- R7 — precedência scoped > global aplicada uma vez, por campo (FX+RC)
    -- ================================================================== --
    v_case := 'R7';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture R7 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture R7 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T3', 'H2830 fixture R7 T3 ' || v_marker, v_ord_t + 1003)
        RETURNING id INTO v_t3;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T4', 'H2830 fixture R7 T4 ' || v_marker, v_ord_t + 1004)
        RETURNING id INTO v_t4;
        v_tok := v_marker || '_K';
        v_tok2 := v_marker || '_L';
        v_set1 := v_marker || '_S1';
        v_set2 := v_marker || '_S2';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'stamp', v_tok2)
        RETURNING id INTO v_m3;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m3, v_t3, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'stamp', v_tok2)
        RETURNING id INTO v_m4;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m4, v_t4, v_game);
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok2));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY(SELECT unnest(ARRAY[v_t2, v_t4]) ORDER BY 1)
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (S1: SCOPED nos dois campos) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY(SELECT unnest(ARRAY[v_t1, v_t3]) ORDER BY 1)
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (NULL: GLOBAL nos dois campos) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set2) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY(SELECT unnest(ARRAY[v_t1, v_t3]) ORDER BY 1)
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (v_set2: GLOBAL nos dois campos) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- R8 — todo token de entrada aparece exatamente uma vez em Printing ∪ EC ∪ residual (RC)
    -- ================================================================== --
    v_case := 'R8';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT c.raw_field, c.normalized_token, c.sig, pp.id,
               EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping e
                        WHERE e.game_id = v_game AND e.asset_source_id = v_src AND e.raw_field = c.raw_field
                          AND e.normalized_token = c.normalized_token AND e.is_active AND e.external_set_id IS NULL)
          INTO v_rf, v_ptok, v_psig, v_pprof, v_ov
          FROM (SELECT m.id, m.raw_field::text AS raw_field, m.normalized_token,
                       COALESCE(m.traits_signature,
                                ARRAY(SELECT mt.trait_id FROM public.card_printing_external_mapping_trait mt
                                       WHERE mt.mapping_id = m.id ORDER BY mt.trait_id)) AS sig
                  FROM public.card_printing_external_mapping m
                 WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.is_active
                   AND m.raw_field IN ('subtype', 'stamp')) c
          JOIN public.card_printing_profile pp ON pp.game_id = v_game AND pp.is_active AND pp.traits_signature = c.sig
         WHERE cardinality(c.sig) > 0
           AND NOT EXISTS (SELECT 1 FROM public.card_printing_trait t WHERE t.id = ANY (c.sig) AND NOT t.is_active)
           AND public.normalize_external_catalog_value(c.normalized_token) = c.normalized_token
         ORDER BY 5 DESC, c.id
         LIMIT 1;
        IF v_ptok IS NULL OR v_rf IS NULL OR v_pprof IS NULL OR v_ov IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem candidato de Printing (STOP; ver E10P g_35_candidate)', c_env, v_case);
        END IF;
        SELECT r.card_set_id INTO STRICT v_cs FROM public.card_set_external_reference r
         WHERE r.asset_source_id = v_src AND r.external_set_id = 'dp1' AND r.is_active;
        SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;
        IF v_scope IS DISTINCT FROM 'dp1' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s escopo resolvido %s (esperado dp1)', c_env, v_case, v_scope);
        END IF;
        SELECT m.traits_signature INTO STRICT v_sig FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'stamp'
           AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = v_scope AND m.is_active;
        SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p
         WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;
        IF v_sig IS NULL OR cardinality(v_sig) < 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET-LOGO em dp1: selo vazio (%s)', c_env, v_case, v_sig);
        END IF;
        v_tok := v_marker || '_L';
        v_tok2 := v_marker || '_K';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        IF v_rf = 'subtype' THEN
            v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_ptok, 'stamp', jsonb_build_array('set-logo', v_tok));
            v_exp_st := NULL;
        ELSE
            v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok2, 'stamp', jsonb_build_array(v_ptok, 'set-logo', v_tok));
            v_exp_st := v_tok2;
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_scope) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_WITH_PROFILE' OR v_pp IS DISTINCT FROM v_pprof OR v_pt IS DISTINCT FROM v_psig
           OR v_ecs IS DISTINCT FROM 'RESOLVED_WITH_EC_PROFILE' OR v_ecp IS DISTINCT FROM v_prof OR v_ect IS DISTINCT FROM v_sig
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_exp_st OR v_rsp IS DISTINCT FROM ARRAY[v_tok] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (Printing ∪ EC ∪ residual) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        SELECT count(*) FILTER (WHERE x = v_ptok), count(*) FILTER (WHERE x = 'SET-LOGO'),
               count(*) FILTER (WHERE x = v_tok), count(*) FILTER (WHERE x = v_tok2)
          INTO v_n, v_m, v_k, v_k2
          FROM unnest(COALESCE(v_rsp, '{}'::text[]) || COALESCE(ARRAY[v_rst], '{}'::text[])) AS u(x);
        IF v_n <> 0 OR v_m <> 0 OR v_k <> 1 OR v_k2 <> (CASE WHEN v_rf = 'subtype' THEN 0 ELSE 1 END) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s soma divergente no residual: printing=%s ec=%s desconhecido1=%s desconhecido2=%s', c_env, v_case, v_n, v_m, v_k, v_k2);
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
    -- R9 — mapping scoped ao Set X não resolve row do Set Y nem com escopo NULL (FX+RC)
    -- ================================================================== --
    v_case := 'R9';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture R9 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture R9 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        v_tok2 := v_marker || '_L';
        v_set1 := v_marker || '_S1';
        v_set2 := v_marker || '_S2';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'stamp', v_tok2)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok2));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY(SELECT unnest(ARRAY[v_t1, v_t2]) ORDER BY 1)
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle: Set X) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set2) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM ARRAY[v_tok2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (v_set2: scoped de outro Set não resolve) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM ARRAY[v_tok2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (NULL: scoped de outro Set não resolve) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- R10 — guarda de nulidade antes do eixo 3; 2176 sem rota sem linha (ST, declarado)
    -- ================================================================== --
    v_case := 'R10';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT p.prosrc, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) INTO STRICT v_src2211, v_txt
          FROM pg_proc p WHERE p.oid = to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)');
        IF v_txt IS DISTINCT FROM 'f10af378c2d5d9fdfd207d9c7d9ff046' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 fora do pino (%s)', c_env, v_case, v_txt);
        END IF;
        v_n := strpos(v_src2211, 'IF p IS NULL OR p.printing_state IS NULL THEN');
        v_m := strpos(v_src2211, 'FROM public.card_edition_context_external_mapping m');
        v_k := strpos(v_src2211, 'VARIANT_AXES_UPSTREAM_NO_ROW');
        IF v_n = 0 OR v_m = 0 OR v_k = 0 OR NOT (v_n < v_k AND v_k < v_m) THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s guarda de nulidade ausente ou depois do eixo 3: guarda=%s token=%s eixo3=%s', c_env, v_case, v_n, v_k, v_m);
        END IF;
        SELECT p.prosrc, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) INTO STRICT v_src2176, v_txt
          FROM pg_proc p WHERE p.oid = to_regprocedure('internal.compute_variant_residual_signature(jsonb,uuid,uuid)');
        IF v_txt IS DISTINCT FROM 'b15a527d3b6adb1e50cbaafae22431bc' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2176 fora do pino (%s)', c_env, v_case, v_txt);
        END IF;
        v_n := (SELECT count(*) FROM regexp_matches(v_src2176, 'RETURN;', 'g'));
        v_m := (SELECT count(*) FROM regexp_matches(v_src2176, 'RETURN QUERY SELECT[^;]*;[[:space:]]*RETURN;', 'g'));
        v_k := strpos(v_src2176, 'COMPUTE_VARIANT_RESIDUAL_SIGNATURE_MISSING_ARGS');
        v_k2 := (SELECT count(*) FROM regexp_matches(v_src2176, 'RETURN QUERY SELECT[^;]*;[[:space:]]*END;[[:space:]]*$', 'g'));
        IF v_n = 0 OR v_n <> v_m OR v_k = 0 OR v_k2 <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2176 com rota possivelmente sem linha: RETURN=%s pareados=%s token_args=%s final=%s', c_env, v_case, v_n, v_m, v_k, v_k2);
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
    -- R11 — subtype com mapping conhecido e INATIVO ⇒ NEEDS_REVIEW_INACTIVE_EC_MAPPING; simetria com stamp (FX+RC)
    -- ================================================================== --
    v_case := 'R11';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture R11 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture R11 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        v_tok2 := v_marker || '_L';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok, v_tok2);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'stamp', v_tok2)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t1]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle: subtype ATIVO) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src
           AND raw_field = 'subtype' AND normalized_token = v_tok AND NOT is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois da aposentadoria: identidade de v_m1 divergente ou ainda ativo (linhas=%s)', c_env, v_case, v_n);
        END IF;
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m2 AND normalized_token = v_tok2;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m2 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m2 AND game_id = v_game AND asset_source_id = v_src
           AND raw_field = 'stamp' AND normalized_token = v_tok2 AND NOT is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois da aposentadoria: identidade de v_m2 divergente ou ainda ativo (linhas=%s)', c_env, v_case, v_n);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (subtype conhecido INATIVO) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'stamp', jsonb_build_array(v_tok2));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY[v_tok2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (simetria: stamp conhecido INATIVO) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- R12 — nas saídas NEEDS_REVIEW_* o residual preserva o token real (FX+RC)
    -- ================================================================== --
    v_case := 'R12';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_t4 := NULL;
    v_m1 := NULL;
    v_m2 := NULL;
    v_m3 := NULL;
    v_m4 := NULL;
    v_m5 := NULL;
    v_ord_t := NULL;
    v_tok := NULL;
    v_tok2 := NULL;
    v_tok3 := NULL;
    v_tok4 := NULL;
    v_tok5 := NULL;
    v_tok6 := NULL;
    v_cnt0 := NULL;
    v_cnt1 := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_raw := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_rf := NULL;
    v_ptok := NULL;
    v_psig := NULL;
    v_pprof := NULL;
    v_ov := NULL;
    v_exp_st := NULL;
    v_k := NULL;
    v_k2 := NULL;
    v_c1 := NULL;
    v_b := NULL;
    v_cfg := NULL;
    v_src2211 := NULL;
    v_src2176 := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture R12 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture R12 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        v_tok := v_marker || '_K';
        v_tok2 := v_marker || '_L';
        v_tok3 := v_marker || '_M';
        v_tok4 := v_marker || '_N';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok, v_tok2, v_tok3, v_tok4);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok, v_tok2, v_tok3, v_tok4);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_m1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m1, v_t1, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'stamp', v_tok2)
        RETURNING id INTO v_m2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m2, v_t2, v_game);
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src
           AND raw_field = 'subtype' AND normalized_token = v_tok AND NOT is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois da aposentadoria: identidade de v_m1 divergente ou ainda ativo (linhas=%s)', c_env, v_case, v_n);
        END IF;
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m2 AND normalized_token = v_tok2;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m2 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m2 AND game_id = v_game AND asset_source_id = v_src
           AND raw_field = 'stamp' AND normalized_token = v_tok2 AND NOT is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois da aposentadoria: identidade de v_m2 divergente ou ainda ativo (linhas=%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'stamp', v_tok3)
        RETURNING id INTO v_m3;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok4));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM ARRAY[v_tok4] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (INACTIVE via subtype: residual preservado) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok4, 'stamp', jsonb_build_array(v_tok2));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok4 OR v_rsp IS DISTINCT FROM ARRAY[v_tok2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (INACTIVE via stamp: residual preservado) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok4, 'stamp', jsonb_build_array(v_tok3));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INVALID_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok4 OR v_rsp IS DISTINCT FROM ARRAY[v_tok3] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (INVALID_EC_MAPPING: residual preservado) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_tok5 := v_marker || '_O';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok5);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok5);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok5)
        RETURNING id INTO v_m4;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok5, 'stamp', jsonb_build_array(v_tok4));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INVALID_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok5 OR v_rsp IS DISTINCT FROM ARRAY[v_tok4] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (INVALID_EC_MAPPING via subtype: residual preservado) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T3', 'H2830 fixture R12 T3 ' || v_marker, v_ord_t + 1003)
        RETURNING id INTO v_t3;
        v_tok6 := v_marker || '_P';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token IN (v_tok6);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN (v_tok6);
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok6)
        RETURNING id INTO v_m5;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m5, v_t3, v_game);
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok6, 'stamp', jsonb_build_array(v_tok4));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t3]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY[v_tok4] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (contraprova terminal NO_EC_PROFILE: token de EC consumido, desconhecido preservado) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok6, 'stamp', jsonb_build_array(v_tok2));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INACTIVE_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok6 OR v_rsp IS DISTINCT FROM ARRAY[v_tok2] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (contraprova INACTIVE via stamp após subtype consumido: residual integral) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok6, 'stamp', jsonb_build_array(v_tok3));
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_INVALID_EC_MAPPING' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok6 OR v_rsp IS DISTINCT FROM ARRAY[v_tok3] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (contraprova INVALID via stamp após subtype consumido: residual integral) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
$h2830_e10$;
