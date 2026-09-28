-- ============================================================================
-- 2830H · ENVELOPE E06 — SEÇÃO 3 (ROUTING FAIL-CLOSED) · lote L4, 6 casos:
--   3.1, 3.2, 3.4, 3.5, 3.6, 3.7 (3.3 fica no L5 — DP-2 = B, Game fixture)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no
--                 PostgreSQL (BATCH12-2830-P5-L3-CLOSEOUT-AND-L4-IMPLEMENTATION-01,
--                 baseline Git 89736a60). Execução exige auditoria deste blob,
--                 mandato próprio e E00 + E06P com gate_pass = true.
-- Contrato ...... 2830_validate_edition_context_foundation.sql v7.0 · blob
--                 b4647dcb59432405c8157e2733fd78678f35540e (l. 539–551;
--                 autoridade imutável; este arquivo a implementa, não a altera)
-- Autoridades ... 2211 internal.resolve_variant_row_axes (routing terminal;
--                 ordem size-scope → Printing → EC → residual; precedência
--                 scoped > global de UM nível; fail-closed), 2176 v2.0
--                 (chamada pela 2211), 2095 (normalização), 2192
--                 internal.resolve_variant_mapping_scope (autoridade de
--                 escopo, 3.7), 2207 (ck_cecem_raw_field e índices parciais
--                 de ativo), 2232 (H2: SET-LOGO só em dp1/swsh9/svp).
-- Padrão ........ reutiliza E03–E05 auditados e executados CONFORME no LIVE:
--                 P1–P3, P5, P8/DP-4 = A, subtransação por caso, sinais
--                 H283C/F/P. Casos FX/RC SEM IMMEDIATE ⇒ sem sonda de modo:
--                 todo evento de selo pendente de fixture é descartado pelo
--                 rollback da subtransação do caso (H283C), como em
--                 2B.3/2T.4/2T.5 e 2Q.8–2Q.10. A 2211 lê a composição pela
--                 N:N da própria transação (COALESCE(selo, N:N)).
-- Risco ......... DP-5 = B, tier R1: escreve SÓ em card_edition_context_trait,
--                 card_edition_context_external_mapping e
--                 card_edition_context_external_mapping_trait. LÊ (sem
--                 escrever) card_printing_* (3.5), card_edition_context_profile
--                 (3.7) e card_set_external_reference (3.7). D-2 = C: AD-2
--                 (elapsed_ms ≤ 60000 é operacional; não satisfaz A2/E1).
--
-- SINAIS: H283C fim de caso · H283F FAIL · H283P PASS terminal. Qualquer outro
--   erro que escape é FAIL. INTO STRICT sem linha ou com >1 linha ⇒ erro ⇒
--   H283F (fail-closed; em 3.7 é o "escopo não resolvível ⇒ STOP" do PHASE5).
--
-- LEITURA DOS CASOS (literal do contrato + comportamento da 2211 pinada):
--   3.1 RC — "token sem mapping ativo permanece no residual de Finish": token
--       (subtype e stamp) SEM nenhum mapping, em Printing e em EC (marcador;
--       ausência provada no próprio caso). O ramo "só histórico inativo" NÃO
--       volta ao residual por contrato (R11 / 2211 v1.1 A3) e é o 3.2.
--   3.2 FX+RC — mapping de fixture ativo resolve (controle positivo); o
--       MESMO mapping aposentado não resolve: EC NEEDS_REVIEW_INACTIVE_EC_
--       MAPPING, sem trait e sem profile, token preservado no residual (R12).
--   3.4 FX+RC — GLOBAL (T1) + SCOPED S1 (T2) + SCOPED S2 (T3) do mesmo token:
--       S1 → [T2], S2 → [T3], S3 sem escopo próprio → [T1], NULL → [T1];
--       sempre UM mapping (nunca a união); "sem desempate": 2º ativo SCOPED
--       no mesmo (escopo, token) ⇒ 23505 uq_cecem_active_scoped e o
--       resultado de S1 não muda.
--   3.5 RC — token REAL de Printing (candidato determinístico, E06P) sai do
--       residual e o eixo EC devolve RESOLVED_NO_EDITION_CONTEXT, sem trait;
--       a flag c35_overlap informa se o token também tem mapping EC GLOBAL
--       ativo (preferido na seleção; a asserção vale nos dois casos).
--   3.6 FX — raw_field = 'type' ⇒ 23514 ck_cecem_raw_field (redundante com
--       1.9, declarado); controle: o MESMO INSERT com 'stamp' é aceito.
--   3.7 RC — SET-LOGO (raw 'set-logo') resolve para o profile de EC em dp1,
--       swsh9 e svp, com escopo obtido de resolve_variant_mapping_scope a
--       partir do Card Set real; em Card Set real fora dos três e sem escopo
--       (NULL) fica no residual de stamp. Universo H2 = 3, emitido (P13).
--
-- ESCRITA (R1, só fixture, ids por RETURNING INTO, sem LOOP):
--   trait 4 (3.2: 1; 3.4: 3) · mapping 7 tentativas (3.2: 1; 3.4: 3 + 1
--   recusada; 3.6: 1 + 1 recusada) · N:N 4 (3.2: 1; 3.4: 3) · UPDATE 1
--   (3.2: is_active = false, WHERE id = v_m1 AND normalized_token = v_tok) ·
--   DELETE 0. Tokens e Sets de fixture sempre com marcador; 3.5/3.7 só leem
--   dado real.
--
-- P8 lock_timeout — DP-4 = A (regra E06-20, perfil próprio): primeira
--   instrução executável SET LOCAL lock_timeout = '5s' + asserção fail-closed.
--
-- TERMINAL: H2830_ROLLBACK_PASS com pass, casos, marker, elapsed_ms,
--   c35_token, c35_overlap e u37 (universo H2).
-- ============================================================================
DO $h2830_e06$
DECLARE
    c_env      CONSTANT text   := 'E06_SECAO3_ROUTING_FAIL_CLOSED';
    c_expected CONSTANT text[] := ARRAY['3.1','3.2','3.4','3.5','3.6','3.7'];
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
    v_ord_t    integer;
    v_t1       uuid;
    v_t2       uuid;
    v_t3       uuid;
    v_m1       uuid;
    v_mg       uuid;
    v_ms1      uuid;
    v_ms2      uuid;
    v_tok      text;
    v_set1     text;
    v_set2     text;
    v_set3     text;
    v_raw      jsonb;
    v_txt      text;
    v_sig      uuid[];
    v_prof     uuid;
    v_cs       uuid;
    v_scope    text;
    v_rf       text;
    v_ov       boolean;
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
    v_c35_tok  text;
    v_c35_ov   boolean;
    v_u37      bigint;
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
    -- 3.1 — token sem mapping ativo permanece no residual de Finish (RC; token marcado SEM mapping algum)
    -- ================================================================== --
    v_case := '3.1';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_m1 := NULL;
    v_mg := NULL;
    v_ms1 := NULL;
    v_ms2 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_set3 := NULL;
    v_ord_t := NULL;
    v_raw := NULL;
    v_txt := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_rf := NULL;
    v_ov := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        v_set1 := v_marker || '_S1';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE normalized_token IN (v_tok, v_marker || '_P1', v_marker || '_P2');
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de EC (%s)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_printing_external_mapping
         WHERE normalized_token IN (v_tok, v_marker || '_P1', v_marker || '_P2');
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping de Printing (%s)', c_env, v_case, v_n);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok,
                                    'stamp', jsonb_build_array(v_marker || '_P2', v_marker || '_P1'));
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
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM ARRAY[v_marker || '_P1', v_marker || '_P2'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (sem escopo) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS DISTINCT FROM v_tok OR v_rsp IS DISTINCT FROM ARRAY[v_marker || '_P1', v_marker || '_P2'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (Set de fixture S1) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- 3.2 — mapping inativo (fixture) não resolve (FX+RC): controle positivo ativo ⇒ [T1];
    --       aposentado ⇒ NEEDS_REVIEW_INACTIVE_EC_MAPPING, sem trait/profile, token no residual
    -- ================================================================== --
    v_case := '3.2';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_m1 := NULL;
    v_mg := NULL;
    v_ms1 := NULL;
    v_ms2 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_set3 := NULL;
    v_ord_t := NULL;
    v_raw := NULL;
    v_txt := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_rf := NULL;
    v_ov := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 3.2 T1 ' || v_marker, v_ord_t + 1001)
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
                'H2830_FAIL: envelope=%s caso=%s 2211 (controle: mapping ATIVO) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_m1 AND normalized_token = v_tok;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s aposentadoria de v_m1 afetou %s linha(s) (esperado 1)', c_env, v_case, v_n);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE id = v_m1 AND game_id = v_game AND asset_source_id = v_src AND external_set_id IS NULL
           AND raw_field = 'subtype' AND normalized_token = v_tok AND NOT is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois da aposentadoria: identidade de v_m1 divergente ou ainda ativo (linhas=%s)', c_env, v_case, v_n);
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
                'H2830_FAIL: envelope=%s caso=%s 2211 (mapping INATIVO) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- 3.4 — precedência scoped > global, UM nível, sem desempate (FX+RC): GLOBAL [T1], S1 [T2], S2 [T3];
    --       2º ativo SCOPED em S1 ⇒ 23505 uq_cecem_active_scoped
    -- ================================================================== --
    v_case := '3.4';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_m1 := NULL;
    v_mg := NULL;
    v_ms1 := NULL;
    v_ms2 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_set3 := NULL;
    v_ord_t := NULL;
    v_raw := NULL;
    v_txt := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_rf := NULL;
    v_ov := NULL;
    BEGIN
        SELECT COALESCE(max(display_order), 0) INTO v_ord_t
          FROM public.card_edition_context_trait WHERE game_id = v_game AND family = 'EVENT';
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T1', 'H2830 fixture 3.4 T1 ' || v_marker, v_ord_t + 1001)
        RETURNING id INTO v_t1;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T2', 'H2830 fixture 3.4 T2 ' || v_marker, v_ord_t + 1002)
        RETURNING id INTO v_t2;
        INSERT INTO public.card_edition_context_trait (game_id, family, code, name, display_order)
        VALUES (v_game, 'EVENT', v_marker || '_T3', 'H2830 fixture 3.4 T3 ' || v_marker, v_ord_t + 1003)
        RETURNING id INTO v_t3;
        v_tok := v_marker || '_K';
        v_set1 := v_marker || '_S1';
        v_set2 := v_marker || '_S2';
        v_set3 := v_marker || '_S3';
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token = v_tok;
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s pré-condição: token de fixture já tem mapping (%s)', c_env, v_case, v_n);
        END IF;
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'subtype', v_tok)
        RETURNING id INTO v_mg;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_mg, v_t1, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
        RETURNING id INTO v_ms1;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_ms1, v_t2, v_game);
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, v_set2, 'subtype', v_tok)
        RETURNING id INTO v_ms2;
        INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_ms2, v_t3, v_game);
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t2]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (S1: SCOPED) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set2) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t3]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (S2: SCOPED) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set3) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t1]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (S3 sem escopo próprio: GLOBAL) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
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
                'H2830_FAIL: envelope=%s caso=%s 2211 (sem escopo: GLOBAL) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, v_set1, 'subtype', v_tok)
            RETURNING id INTO v_m1;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s segundo ativo SCOPED no mesmo (escopo, token) foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM 'uq_cecem_active_scoped' OR v_tab IS DISTINCT FROM 'card_edition_context_external_mapping' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE normalized_token = v_tok AND external_set_id = v_set1 AND is_active;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s ativo(s) SCOPED em S1 (esperado 1)', c_env, v_case, v_n);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_set1) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM ARRAY[v_t2]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (S1 depois do negativo) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    -- 3.5 — token consumido por Printing não reaparece em EC (RC; candidato real determinístico = E06P)
    -- ================================================================== --
    v_case := '3.5';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_m1 := NULL;
    v_mg := NULL;
    v_ms1 := NULL;
    v_ms2 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_set3 := NULL;
    v_ord_t := NULL;
    v_raw := NULL;
    v_txt := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_rf := NULL;
    v_ov := NULL;
    BEGIN
        SELECT c.raw_field, c.normalized_token, c.sig, pp.id,
               EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping e
                        WHERE e.game_id = v_game AND e.asset_source_id = v_src AND e.raw_field = c.raw_field
                          AND e.normalized_token = c.normalized_token AND e.is_active AND e.external_set_id IS NULL)
          INTO v_rf, v_txt, v_sig, v_prof, v_ov
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
        IF v_txt IS NULL OR v_rf IS NULL OR v_prof IS NULL OR v_ov IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem candidato de Printing (STOP; ver E06P g_35_candidate)', c_env, v_case);
        END IF;
        IF v_rf = 'subtype' THEN
            v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_txt);
        ELSE
            v_raw := jsonb_build_object('type', 'H2830 TIPO', 'stamp', jsonb_build_array(v_txt));
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, NULL) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_WITH_PROFILE' OR v_pp IS DISTINCT FROM v_prof OR v_pt IS DISTINCT FROM v_sig
           OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM '{}'::text[] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (token de Printing) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        v_c35_tok := v_txt;
        v_c35_ov := v_ov;

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
    -- 3.6 — raw_field = 'type' impossível por CHECK (FX; redundante com 1.9, declarado):
    --       controle 'stamp' aceito; 'type' ⇒ 23514 ck_cecem_raw_field
    -- ================================================================== --
    v_case := '3.6';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_m1 := NULL;
    v_mg := NULL;
    v_ms1 := NULL;
    v_ms2 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_set3 := NULL;
    v_ord_t := NULL;
    v_raw := NULL;
    v_txt := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_rf := NULL;
    v_ov := NULL;
    BEGIN
        v_tok := v_marker || '_K';
        INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
        VALUES (v_game, v_src, NULL, 'stamp', v_tok)
        RETURNING id INTO v_m1;
        SELECT normalized_token INTO v_txt FROM public.card_edition_context_external_mapping WHERE id = v_m1;
        IF v_txt IS DISTINCT FROM v_tok THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s token normalizado divergente da fixture: %s (esperado %s)', c_env, v_case, v_txt, v_tok);
        END IF;
        v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;
        BEGIN
            INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
            VALUES (v_game, v_src, NULL, 'type', v_tok)
            RETURNING id INTO v_mg;
        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
        IF NOT v_got THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s raw_field = type foi ACEITO(A)', c_env, v_case);
        END IF;
        IF v_state IS NULL OR v_state <> '23514' OR v_con IS DISTINCT FROM 'ck_cecem_raw_field' OR v_tab IS DISTINCT FROM 'card_edition_context_external_mapping' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', c_env, v_case, v_state, v_con, v_tab, v_msg);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping WHERE normalized_token = v_tok;
        IF v_n <> 1 OR v_mg IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s depois do negativo: %s linha(s) com o token (esperado 1, só o controle stamp)', c_env, v_case, v_n);
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
    -- 3.7 — SET-LOGO só resolve para contexto em dp1/swsh9/svp (H2), escopo por
    --       resolve_variant_mapping_scope a partir do Card Set real (RC; universo H2 emitido)
    -- ================================================================== --
    v_case := '3.7';
    v_t1 := NULL;
    v_t2 := NULL;
    v_t3 := NULL;
    v_m1 := NULL;
    v_mg := NULL;
    v_ms1 := NULL;
    v_ms2 := NULL;
    v_tok := NULL;
    v_set1 := NULL;
    v_set2 := NULL;
    v_set3 := NULL;
    v_ord_t := NULL;
    v_raw := NULL;
    v_txt := NULL;
    v_sig := NULL;
    v_prof := NULL;
    v_cs := NULL;
    v_scope := NULL;
    v_rf := NULL;
    v_ov := NULL;
    BEGIN
        SELECT count(*) INTO v_u37 FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND normalized_token = 'SET-LOGO' AND is_active;
        IF v_u37 <> 3 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s H2: %s mapping(s) SET-LOGO ativo(s) (esperado 3)', c_env, v_case, v_u37);
        END IF;
        SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
         WHERE game_id = v_game AND asset_source_id = v_src AND normalized_token = 'SET-LOGO'
           AND (external_set_id IS NULL OR external_set_id NOT IN ('dp1', 'swsh9', 'svp'));
        IF v_n <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s H2: %s mapping(s) SET-LOGO GLOBAL ou fora de dp1/swsh9/svp', c_env, v_case, v_n);
        END IF;
        v_raw := jsonb_build_object('type', 'H2830 TIPO', 'stamp', jsonb_build_array('set-logo'));
        -- escopo dp1: Card Set real → resolve_variant_mapping_scope → 2211
        v_cs := NULL; v_scope := NULL; v_sig := NULL; v_prof := NULL;
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
        IF v_sig IS NULL OR cardinality(v_sig) < 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET-LOGO em dp1: selo vazio (%s)', c_env, v_case, v_sig);
        END IF;
        SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p
         WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;
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
                'H2830_FAIL: envelope=%s caso=%s 2211 (SET-LOGO em dp1) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        -- escopo swsh9: Card Set real → resolve_variant_mapping_scope → 2211
        v_cs := NULL; v_scope := NULL; v_sig := NULL; v_prof := NULL;
        SELECT r.card_set_id INTO STRICT v_cs FROM public.card_set_external_reference r
         WHERE r.asset_source_id = v_src AND r.external_set_id = 'swsh9' AND r.is_active;
        SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;
        IF v_scope IS DISTINCT FROM 'swsh9' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s escopo resolvido %s (esperado swsh9)', c_env, v_case, v_scope);
        END IF;
        SELECT m.traits_signature INTO STRICT v_sig FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'stamp'
           AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = v_scope AND m.is_active;
        IF v_sig IS NULL OR cardinality(v_sig) < 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET-LOGO em swsh9: selo vazio (%s)', c_env, v_case, v_sig);
        END IF;
        SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p
         WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;
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
                'H2830_FAIL: envelope=%s caso=%s 2211 (SET-LOGO em swsh9) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        -- escopo svp: Card Set real → resolve_variant_mapping_scope → 2211
        v_cs := NULL; v_scope := NULL; v_sig := NULL; v_prof := NULL;
        SELECT r.card_set_id INTO STRICT v_cs FROM public.card_set_external_reference r
         WHERE r.asset_source_id = v_src AND r.external_set_id = 'svp' AND r.is_active;
        SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;
        IF v_scope IS DISTINCT FROM 'svp' THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s escopo resolvido %s (esperado svp)', c_env, v_case, v_scope);
        END IF;
        SELECT m.traits_signature INTO STRICT v_sig FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'stamp'
           AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = v_scope AND m.is_active;
        IF v_sig IS NULL OR cardinality(v_sig) < 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s SET-LOGO em svp: selo vazio (%s)', c_env, v_case, v_sig);
        END IF;
        SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p
         WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;
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
                'H2830_FAIL: envelope=%s caso=%s 2211 (SET-LOGO em svp) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
        END IF;
        -- controle: Card Set real FORA de dp1/swsh9/svp
        v_cs := NULL; v_scope := NULL; v_txt := NULL;
        SELECT r.card_set_id, r.external_set_id INTO v_cs, v_txt FROM public.card_set_external_reference r
         WHERE r.asset_source_id = v_src AND r.is_active AND r.external_set_id NOT IN ('dp1', 'swsh9', 'svp')
         ORDER BY r.card_set_id, r.id
         LIMIT 1;
        IF v_cs IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sem Card Set real fora de dp1/swsh9/svp (STOP; ver E06P)', c_env, v_case);
        END IF;
        SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;
        IF v_scope IS DISTINCT FROM v_txt OR v_scope IN ('dp1', 'swsh9', 'svp') THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s controle fora de escopo resolveu %s (esperado %s)', c_env, v_case, v_scope, v_txt);
        END IF;
        v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;
        v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;
        SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,
               r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,
               r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp
          INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp
          FROM internal.resolve_variant_row_axes(v_raw, v_game, v_src, v_scope) AS r;
        IF v_ps IS DISTINCT FROM 'RESOLVED_NO_PRINTING' OR v_pp IS NOT NULL OR v_pt IS DISTINCT FROM '{}'::uuid[]
           OR v_ecs IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT' OR v_ecp IS NOT NULL OR v_ect IS DISTINCT FROM '{}'::uuid[]
           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY['SET-LOGO'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (SET-LOGO fora de escopo) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
           OR v_rst IS NOT NULL OR v_rsp IS DISTINCT FROM ARRAY['SET-LOGO'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s 2211 (SET-LOGO sem escopo) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s', c_env, v_case, v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp);
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
    IF v_c35_tok IS NULL OR v_c35_ov IS NULL OR v_u37 IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE evidência ausente c35_token=%s c35_overlap=%s u37=%s', c_env, v_c35_tok, v_c35_ov, v_u37);
    END IF;

    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s c35_token=%s c35_overlap=%s u37=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), v_c35_tok, v_c35_ov, v_u37);
END
$h2830_e06$;
