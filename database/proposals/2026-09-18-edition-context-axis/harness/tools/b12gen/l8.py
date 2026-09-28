# L8 — Seção R (routing terminal 2211): R1–R12. E10 + E10P.
from lib import *
import pre

TR = 'public.card_edition_context_trait'
MAP = 'public.card_edition_context_external_mapping'
NN = 'public.card_edition_context_external_mapping_trait'
PIN_2211 = 'f10af378c2d5d9fdfd207d9c7d9ff046'
PIN_2176 = 'b15a527d3b6adb1e50cbaafae22431bc'


def ord_t():
    return sql(f"SELECT COALESCE(max(display_order), 0) INTO v_ord_t FROM {TR} WHERE game_id = v_game AND family = 'EVENT';")


def trait(n, cid):
    return sql(f"INSERT INTO {TR} (game_id, family, code, name, display_order)\n"
               f"VALUES (v_game, 'EVENT', v_marker || '_T{n}', 'H2830 fixture {cid} T{n} ' || v_marker, v_ord_t + 100{n})\n"
               f"RETURNING id INTO v_t{n};")


def mapping(var, setexpr, raw_field, tok):
    return sql(f"INSERT INTO {MAP} (game_id, asset_source_id, external_set_id, raw_field, normalized_token)\n"
               f"VALUES (v_game, v_src, {setexpr}, '{raw_field}', {tok})\n"
               f"RETURNING id INTO {var};")


def nn(m, t):
    return sql(f"INSERT INTO {NN} (mapping_id, trait_id, game_id)\nVALUES ({m}, {t}, v_game);")


def retire(m, tok, raw_field):
    s = sql(f"UPDATE {MAP} SET is_active = false WHERE id = {m} AND normalized_token = {tok};\nGET DIAGNOSTICS v_n = ROW_COUNT;")
    s += iff('v_n <> 1', f'aposentadoria de {m} afetou %s linha(s) (esperado 1)', 'v_n')
    s += sql(f"SELECT count(*) INTO v_n FROM {MAP}\n WHERE id = {m} AND game_id = v_game AND asset_source_id = v_src\n"
             f"   AND raw_field = '{raw_field}' AND normalized_token = {tok} AND NOT is_active;")
    s += iff('v_n <> 1', f'depois da aposentadoria: identidade de {m} divergente ou ainda ativo (linhas=%s)', 'v_n')
    return s


def free(*toks):
    lst = ', '.join(toks)
    s = sql(f"SELECT count(*) INTO v_n FROM {MAP} WHERE normalized_token IN ({lst});")
    s += iff('v_n <> 0', 'pré-condição: token de fixture já tem mapping de EC (%s)', 'v_n')
    s += sql(f"SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token IN ({lst});")
    s += iff('v_n <> 0', 'pré-condição: token de fixture já tem mapping de Printing (%s)', 'v_n')
    return s


# escopo real de dp1: Card Set real → 2192 (mesmo padrão auditado do 3.7)
DP1 = (sql("SELECT r.card_set_id INTO STRICT v_cs FROM public.card_set_external_reference r\n"
           " WHERE r.asset_source_id = v_src AND r.external_set_id = 'dp1' AND r.is_active;\n"
           "SELECT s.external_set_id INTO STRICT v_scope FROM internal.resolve_variant_mapping_scope(v_cs, v_src) AS s;")
       + iff("v_scope IS DISTINCT FROM 'dp1'", 'escopo resolvido %s (esperado dp1)', 'v_scope')
       + sql(f"SELECT m.traits_signature INTO STRICT v_sig FROM {MAP} m\n"
             " WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'stamp'\n"
             "   AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = v_scope AND m.is_active;\n"
             "SELECT p.id INTO STRICT v_prof FROM public.card_edition_context_profile p\n"
             " WHERE p.game_id = v_game AND p.traits_signature = v_sig AND p.is_active;")
       + iff('v_sig IS NULL OR cardinality(v_sig) < 1', 'SET-LOGO em dp1: selo vazio (%s)', 'v_sig'))

# candidato real de Printing (núcleo idêntico ao E06/E06P/E10P)
C35 = (sql("SELECT c.raw_field, c.normalized_token, c.sig, pp.id,\n"
           "       EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping e\n"
           "                WHERE e.game_id = v_game AND e.asset_source_id = v_src AND e.raw_field = c.raw_field\n"
           "                  AND e.normalized_token = c.normalized_token AND e.is_active AND e.external_set_id IS NULL)\n"
           "  INTO v_rf, v_ptok, v_psig, v_pprof, v_ov\n"
           "  FROM (SELECT m.id, m.raw_field::text AS raw_field, m.normalized_token,\n"
           "               COALESCE(m.traits_signature,\n"
           "                        ARRAY(SELECT mt.trait_id FROM public.card_printing_external_mapping_trait mt\n"
           "                               WHERE mt.mapping_id = m.id ORDER BY mt.trait_id)) AS sig\n"
           "          FROM public.card_printing_external_mapping m\n"
           "         WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.is_active\n"
           "           AND m.raw_field IN ('subtype', 'stamp')) c\n"
           "  JOIN public.card_printing_profile pp ON pp.game_id = v_game AND pp.is_active AND pp.traits_signature = c.sig\n"
           " WHERE cardinality(c.sig) > 0\n"
           "   AND NOT EXISTS (SELECT 1 FROM public.card_printing_trait t WHERE t.id = ANY (c.sig) AND NOT t.is_active)\n"
           "   AND public.normalize_external_catalog_value(c.normalized_token) = c.normalized_token\n"
           " ORDER BY 5 DESC, c.id\n"
           " LIMIT 1;")
       + iff('v_ptok IS NULL OR v_rf IS NULL OR v_pprof IS NULL OR v_ov IS NULL',
             'sem candidato de Printing (STOP; ver E10P g_35_candidate)'))

PRO = "pg_proc p WHERE p.oid = to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)')"


def r1():
    b = sql("SELECT p.provolatile::text, p.prosecdef, p.proconfig::text[], p.pronargs::int,\n"
            "       (SELECT count(*) FROM unnest(p.proargmodes) AS x(m) WHERE x.m = 't'),\n"
            "       md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))\n"
            f"  INTO STRICT v_c1, v_b, v_cfg, v_n, v_m, v_txt\n  FROM {PRO};")
    b += iff(f"v_c1 IS DISTINCT FROM 's' OR v_b IS DISTINCT FROM true OR v_cfg IS DISTINCT FROM ARRAY['search_path=\"\"']\n"
             f"           OR v_n <> 4 OR v_m <> 10 OR v_txt IS DISTINCT FROM '{PIN_2211}'",
             'assinatura da 2211 divergente: vol=%s secdef=%s config=%s nargs=%s out=%s md5=%s', 'v_c1, v_b, v_cfg, v_n, v_m, v_txt')
    return b


def r2():
    b = sql(f"SELECT p.prosrc, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) INTO STRICT v_src2211, v_txt\n  FROM {PRO};")
    b += iff(f"v_txt IS DISTINCT FROM '{PIN_2211}' OR strpos(v_src2211, 'FROM internal.compute_variant_residual_signature(p_raw_data, p_game_id, p_asset_source_id)') = 0",
             'prosrc da 2211 não chama a 2176 como declarado (md5=%s)', 'v_txt')
    return b


def r3():
    b = DP1
    for size, st in [('JUMBO', 'BLOCKED_SIZE_OUT_OF_SCOPE'), ('oversized', 'BLOCKED_SIZE_UNSUPPORTED')]:
        b += sql(f"v_raw := jsonb_build_object('type', 'H2830 TIPO', 'size', '{size}', 'stamp', jsonb_build_array('set-logo'));")
        b += rc('v_game', 'v_scope')
        b += expect(f'size {size}', f"'{st}'", 'NULL', EMPTY_U, "'NOT_EVALUATED'", 'NULL', EMPTY_U, 'NULL', "ARRAY['SET-LOGO']")
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'size', 'standard', 'stamp', jsonb_build_array('set-logo'));")
    b += rc('v_game', 'v_scope')
    b += expect('controle: size standard', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'RESOLVED_WITH_EC_PROFILE'", 'v_prof', 'v_sig', 'NULL', EMPTY_T)
    return b


def r4():
    b = C35 + sql("v_tok := v_marker || '_L';") + free('v_tok')
    b += sql("IF v_rf = 'subtype' THEN\n"
             "    v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_ptok, 'stamp', jsonb_build_array(v_tok));\n"
             "ELSE\n"
             "    v_raw := jsonb_build_object('type', 'H2830 TIPO', 'stamp', jsonb_build_array(v_ptok, v_tok));\n"
             "END IF;")
    b += rc('v_game', 'NULL')
    b += expect('token de Printing + token desconhecido', "'RESOLVED_WITH_PROFILE'", 'v_pprof', 'v_psig',
                "'RESOLVED_NO_EDITION_CONTEXT'", 'NULL', EMPTY_U, 'NULL', 'ARRAY[v_tok]')
    b += iff('v_ptok = ANY (v_rsp) OR v_rst IS NOT DISTINCT FROM v_ptok', 'token de Printing %s voltou ao residual', 'v_ptok')
    return b


def r5():
    b = DP1 + sql("v_tok := v_marker || '_K';") + free('v_tok')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array('set-logo'));")
    b += rc('v_game', 'v_scope')
    b += expect('SET-LOGO consumido por EC', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'RESOLVED_WITH_EC_PROFILE'", 'v_prof', 'v_sig', 'v_tok', EMPTY_T)
    return b


COUNTS = ("SELECT ARRAY[(SELECT count(*) FROM public.card_edition_context_trait),\n"
          "             (SELECT count(*) FROM public.card_edition_context_profile),\n"
          "             (SELECT count(*) FROM public.card_edition_context_profile_trait),\n"
          "             (SELECT count(*) FROM public.card_edition_context_external_mapping),\n"
          "             (SELECT count(*) FROM public.card_edition_context_external_mapping_trait),\n"
          "             (SELECT count(*) FROM public.card_printing_trait),\n"
          "             (SELECT count(*) FROM public.card_printing_profile),\n"
          "             (SELECT count(*) FROM public.card_printing_external_mapping)]")


def r6():
    b = sql("v_tok := v_marker || '_K';\nv_tok2 := v_marker || '_L';") + free('v_tok', 'v_tok2')
    b += sql(COUNTS + "\n  INTO v_cnt0;")
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok2));")
    b += rc('v_game', 'NULL')
    b += expect('tokens desconhecidos', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'RESOLVED_NO_EDITION_CONTEXT'", 'NULL', EMPTY_U, 'v_tok', 'ARRAY[v_tok2]')
    b += sql(COUNTS + "\n  INTO v_cnt1;")
    b += iff('v_cnt0 IS NULL OR v_cnt1 IS DISTINCT FROM v_cnt0',
             'contagens de vocabulário (EC trait/profile/profile_trait/mapping/mapping_trait · Printing trait/profile/mapping) alteradas pela RC: %s → %s', 'v_cnt0, v_cnt1')
    return b


def r7():
    b = ord_t() + trait(1, 'R7') + trait(2, 'R7') + trait(3, 'R7') + trait(4, 'R7')
    b += sql("v_tok := v_marker || '_K';\nv_tok2 := v_marker || '_L';\nv_set1 := v_marker || '_S1';\nv_set2 := v_marker || '_S2';") + free('v_tok', 'v_tok2')
    b += mapping('v_m1', 'NULL', 'subtype', 'v_tok') + nn('v_m1', 'v_t1')
    b += mapping('v_m2', 'v_set1', 'subtype', 'v_tok') + nn('v_m2', 'v_t2')
    b += mapping('v_m3', 'NULL', 'stamp', 'v_tok2') + nn('v_m3', 'v_t3')
    b += mapping('v_m4', 'v_set1', 'stamp', 'v_tok2') + nn('v_m4', 'v_t4')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok2));")
    b += rc('v_game', 'v_set1')
    b += expect('S1: SCOPED nos dois campos', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'NEEDS_REVIEW_NO_EC_PROFILE'", 'NULL',
                'ARRAY(SELECT unnest(ARRAY[v_t2, v_t4]) ORDER BY 1)', 'NULL', EMPTY_T)
    for s in ['NULL', 'v_set2']:
        b += rc('v_game', s)
        b += expect(f'{s}: GLOBAL nos dois campos', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'NEEDS_REVIEW_NO_EC_PROFILE'", 'NULL',
                    'ARRAY(SELECT unnest(ARRAY[v_t1, v_t3]) ORDER BY 1)', 'NULL', EMPTY_T)
    return b


def r8():
    b = C35 + DP1 + sql("v_tok := v_marker || '_L';\nv_tok2 := v_marker || '_K';") + free('v_tok', 'v_tok2')
    b += sql("IF v_rf = 'subtype' THEN\n"
             "    v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_ptok, 'stamp', jsonb_build_array('set-logo', v_tok));\n"
             "    v_exp_st := NULL;\n"
             "ELSE\n"
             "    v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok2, 'stamp', jsonb_build_array(v_ptok, 'set-logo', v_tok));\n"
             "    v_exp_st := v_tok2;\n"
             "END IF;")
    b += rc('v_game', 'v_scope')
    b += expect('Printing ∪ EC ∪ residual', "'RESOLVED_WITH_PROFILE'", 'v_pprof', 'v_psig', "'RESOLVED_WITH_EC_PROFILE'", 'v_prof', 'v_sig',
                'v_exp_st', 'ARRAY[v_tok]')
    b += sql("SELECT count(*) FILTER (WHERE x = v_ptok), count(*) FILTER (WHERE x = 'SET-LOGO'),\n"
             "       count(*) FILTER (WHERE x = v_tok), count(*) FILTER (WHERE x = v_tok2)\n"
             "  INTO v_n, v_m, v_k, v_k2\n"
             "  FROM unnest(COALESCE(v_rsp, '{}'::text[]) || COALESCE(ARRAY[v_rst], '{}'::text[])) AS u(x);")
    b += iff("v_n <> 0 OR v_m <> 0 OR v_k <> 1 OR v_k2 <> (CASE WHEN v_rf = 'subtype' THEN 0 ELSE 1 END)",
             'soma divergente no residual: printing=%s ec=%s desconhecido1=%s desconhecido2=%s', 'v_n, v_m, v_k, v_k2')
    return b


def r9():
    b = ord_t() + trait(1, 'R9') + trait(2, 'R9')
    b += sql("v_tok := v_marker || '_K';\nv_tok2 := v_marker || '_L';\nv_set1 := v_marker || '_S1';\nv_set2 := v_marker || '_S2';") + free('v_tok', 'v_tok2')
    b += mapping('v_m1', 'v_set1', 'subtype', 'v_tok') + nn('v_m1', 'v_t1')
    b += mapping('v_m2', 'v_set1', 'stamp', 'v_tok2') + nn('v_m2', 'v_t2')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok2));")
    b += rc('v_game', 'v_set1')
    b += expect('controle: Set X', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'NEEDS_REVIEW_NO_EC_PROFILE'", 'NULL',
                'ARRAY(SELECT unnest(ARRAY[v_t1, v_t2]) ORDER BY 1)', 'NULL', EMPTY_T)
    for s in ['v_set2', 'NULL']:
        b += rc('v_game', s)
        b += expect(f'{s}: scoped de outro Set não resolve', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'RESOLVED_NO_EDITION_CONTEXT'", 'NULL',
                    EMPTY_U, 'v_tok', 'ARRAY[v_tok2]')
    return b


def r10():
    b = sql(f"SELECT p.prosrc, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) INTO STRICT v_src2211, v_txt\n  FROM {PRO};")
    b += iff(f"v_txt IS DISTINCT FROM '{PIN_2211}'", '2211 fora do pino (%s)', 'v_txt')
    b += sql("v_n := strpos(v_src2211, 'IF p IS NULL OR p.printing_state IS NULL THEN');\n"
             "v_m := strpos(v_src2211, 'FROM public.card_edition_context_external_mapping m');\n"
             "v_k := strpos(v_src2211, 'VARIANT_AXES_UPSTREAM_NO_ROW');")
    b += iff('v_n = 0 OR v_m = 0 OR v_k = 0 OR NOT (v_n < v_k AND v_k < v_m)',
             'guarda de nulidade ausente ou depois do eixo 3: guarda=%s token=%s eixo3=%s', 'v_n, v_k, v_m')
    b += sql("SELECT p.prosrc, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) INTO STRICT v_src2176, v_txt\n"
             "  FROM pg_proc p WHERE p.oid = to_regprocedure('internal.compute_variant_residual_signature(jsonb,uuid,uuid)');")
    b += iff(f"v_txt IS DISTINCT FROM '{PIN_2176}'", '2176 fora do pino (%s)', 'v_txt')
    # toda saída 'RETURN;' é precedida de RETURN QUERY; a última instrução é RETURN QUERY
    b += sql("v_n := (SELECT count(*) FROM regexp_matches(v_src2176, 'RETURN;', 'g'));\n"
             "v_m := (SELECT count(*) FROM regexp_matches(v_src2176, 'RETURN QUERY SELECT[^;]*;[[:space:]]*RETURN;', 'g'));\n"
             "v_k := strpos(v_src2176, 'COMPUTE_VARIANT_RESIDUAL_SIGNATURE_MISSING_ARGS');\n"
             "v_k2 := (SELECT count(*) FROM regexp_matches(v_src2176, 'RETURN QUERY SELECT[^;]*;[[:space:]]*END;[[:space:]]*$', 'g'));")
    b += iff('v_n = 0 OR v_n <> v_m OR v_k = 0 OR v_k2 <> 1',
             '2176 com rota possivelmente sem linha: RETURN=%s pareados=%s token_args=%s final=%s', 'v_n, v_m, v_k, v_k2')
    return b


def r11():
    b = ord_t() + trait(1, 'R11') + trait(2, 'R11')
    b += sql("v_tok := v_marker || '_K';\nv_tok2 := v_marker || '_L';") + free('v_tok', 'v_tok2')
    b += mapping('v_m1', 'NULL', 'subtype', 'v_tok') + nn('v_m1', 'v_t1')
    b += mapping('v_m2', 'NULL', 'stamp', 'v_tok2') + nn('v_m2', 'v_t2')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);")
    b += rc('v_game', 'NULL')
    b += expect('controle: subtype ATIVO', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'NEEDS_REVIEW_NO_EC_PROFILE'", 'NULL', 'ARRAY[v_t1]', 'NULL', EMPTY_T)
    b += retire('v_m1', 'v_tok', 'subtype') + retire('v_m2', 'v_tok2', 'stamp')
    b += rc('v_game', 'NULL')
    b += expect('subtype conhecido INATIVO', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'NEEDS_REVIEW_INACTIVE_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok', EMPTY_T)
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'stamp', jsonb_build_array(v_tok2));")
    b += rc('v_game', 'NULL')
    b += expect('simetria: stamp conhecido INATIVO', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U, "'NEEDS_REVIEW_INACTIVE_EC_MAPPING'", 'NULL', EMPTY_U, 'NULL', 'ARRAY[v_tok2]')
    return b


def r12():
    b = ord_t() + trait(1, 'R12') + trait(2, 'R12')
    b += sql("v_tok := v_marker || '_K';\nv_tok2 := v_marker || '_L';\nv_tok3 := v_marker || '_M';\nv_tok4 := v_marker || '_N';")
    b += free('v_tok', 'v_tok2', 'v_tok3', 'v_tok4')
    b += mapping('v_m1', 'NULL', 'subtype', 'v_tok') + nn('v_m1', 'v_t1')
    b += mapping('v_m2', 'NULL', 'stamp', 'v_tok2') + nn('v_m2', 'v_t2')
    b += retire('v_m1', 'v_tok', 'subtype') + retire('v_m2', 'v_tok2', 'stamp')
    # mapping ATIVO sem N:N (composição efetiva vazia; selo deferido nunca forçado)
    b += mapping('v_m3', 'NULL', 'stamp', 'v_tok3')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok, 'stamp', jsonb_build_array(v_tok4));")
    b += rc('v_game', 'NULL')
    b += expect('INACTIVE via subtype: residual preservado', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_INACTIVE_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok', 'ARRAY[v_tok4]')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok4, 'stamp', jsonb_build_array(v_tok2));")
    b += rc('v_game', 'NULL')
    b += expect('INACTIVE via stamp: residual preservado', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_INACTIVE_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok4', 'ARRAY[v_tok2]')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok4, 'stamp', jsonb_build_array(v_tok3));")
    b += rc('v_game', 'NULL')
    b += expect('INVALID_EC_MAPPING: residual preservado', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_INVALID_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok4', 'ARRAY[v_tok3]')
    # simetria A4: INVALID também pela via subtype (mapping ATIVO sem N:N)
    b += sql("v_tok5 := v_marker || '_O';") + free('v_tok5')
    b += mapping('v_m4', 'NULL', 'subtype', 'v_tok5')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok5, 'stamp', jsonb_build_array(v_tok4));")
    b += rc('v_game', 'NULL')
    b += expect('INVALID_EC_MAPPING via subtype: residual preservado', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_INVALID_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok5', 'ARRAY[v_tok4]')
    # CONTRAPROVAS (ramos da 2211): o residual devolvido nas saídas A4 é o
    # residual INTEGRAL do Printing, inclusive o token que o eixo 3 já tinha
    # consumido antes da saída; a saída terminal NEEDS_REVIEW_NO_EC_PROFILE
    # consome o token de EC e preserva só o desconhecido.
    b += trait(3, 'R12') + sql("v_tok6 := v_marker || '_P';") + free('v_tok6')
    b += mapping('v_m5', 'NULL', 'subtype', 'v_tok6') + nn('v_m5', 'v_t3')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok6, 'stamp', jsonb_build_array(v_tok4));")
    b += rc('v_game', 'NULL')
    b += expect('contraprova terminal NO_EC_PROFILE: token de EC consumido, desconhecido preservado', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_NO_EC_PROFILE'", 'NULL', 'ARRAY[v_t3]', 'NULL', 'ARRAY[v_tok4]')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok6, 'stamp', jsonb_build_array(v_tok2));")
    b += rc('v_game', 'NULL')
    b += expect('contraprova INACTIVE via stamp após subtype consumido: residual integral', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_INACTIVE_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok6', 'ARRAY[v_tok2]')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok6, 'stamp', jsonb_build_array(v_tok3));")
    b += rc('v_game', 'NULL')
    b += expect('contraprova INVALID via stamp após subtype consumido: residual integral', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_INVALID_EC_MAPPING'", 'NULL', EMPTY_U, 'v_tok6', 'ARRAY[v_tok3]')
    return b


HEAD = header(['2830H · ENVELOPE E10 — SEÇÃO R (ROUTING TERMINAL 2211) · lote L8, 12 casos: R1–R12'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E10P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 624–653).',
    'Autoridades ... 2211 (pino f10af378…), 2176 v2.0 (pino b15a527d…), 2192',
    '                (escopo real de dp1 a partir do Card Set, nunca card_set.code),',
    '                2207 (índices de ativo). R2/R10 são provas ESTÁTICAS declaradas.',
    'Leitura ....... R6 "ambos UNRESOLVED" = nenhum eixo resolve: Printing',
    '                RESOLVED_NO_PRINTING e EC RESOLVED_NO_EDITION_CONTEXT, residual',
    '                intacto (estados LIVE da 2176/2211). R12 = saídas NEEDS_REVIEW_*',
    '                de retorno antecipado (INACTIVE/INVALID_EC_MAPPING, achado A4 da',
    '                2211): o residual devolvido é o residual integral do Printing.',
    '                R10: a parte comportamental é inalcançável (nenhuma rota da 2176',
    '                sem linha — provado sobre o prosrc pinado); nunca PASS',
    '                comportamental.',
    'Escrita (R1) .. só EC, fixture marcada: trait 11 · mapping 13 · N:N 11 ·',
    '                UPDATE 4 (aposentadoria, WHERE id AND token) · DELETE 0.',
    '                R12 cria 2 mappings ATIVOS sem N:N sem IMMEDIATE: o evento de selo',
    '                pendente é descartado pelo H283C do caso (padrão L4).',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])

SPEC = dict(tag='h2830_e10', env='E10_SECAO_R_ROUTING_2211', header=HEAD,
            decl=[('v_t1', 'uuid', None), ('v_t2', 'uuid', None), ('v_t3', 'uuid', None), ('v_t4', 'uuid', None),
                  ('v_m1', 'uuid', None), ('v_m2', 'uuid', None), ('v_m3', 'uuid', None), ('v_m4', 'uuid', None), ('v_m5', 'uuid', None),
                  ('v_ord_t', 'integer', None), ('v_tok', 'text', None), ('v_tok2', 'text', None), ('v_tok3', 'text', None),
                  ('v_tok4', 'text', None), ('v_tok5', 'text', None), ('v_tok6', 'text', None), ('v_cnt0', 'bigint[]', None), ('v_cnt1', 'bigint[]', None), ('v_set1', 'text', None), ('v_set2', 'text', None), ('v_raw', 'jsonb', None),
                  ('v_cs', 'uuid', None), ('v_scope', 'text', None), ('v_sig', 'uuid[]', None), ('v_prof', 'uuid', None),
                  ('v_rf', 'text', None), ('v_ptok', 'text', None), ('v_psig', 'uuid[]', None), ('v_pprof', 'uuid', None),
                  ('v_ov', 'boolean', None), ('v_exp_st', 'text', None), ('v_k', 'bigint', None), ('v_k2', 'bigint', None),
                  ('v_c1', 'text', None), ('v_b', 'boolean', None), ('v_cfg', 'text[]', None),
                  ('v_src2211', 'text', None), ('v_src2176', 'text', None)] + RC_VARS,
            reset=['v_t1', 'v_t2', 'v_t3', 'v_t4', 'v_m1', 'v_m2', 'v_m3', 'v_m4', 'v_m5', 'v_ord_t', 'v_tok', 'v_tok2', 'v_tok3', 'v_tok4', 'v_tok5', 'v_tok6', 'v_cnt0', 'v_cnt1',
                   'v_set1', 'v_set2', 'v_raw', 'v_cs', 'v_scope', 'v_sig', 'v_prof', 'v_rf', 'v_ptok', 'v_psig', 'v_pprof',
                   'v_ov', 'v_exp_st', 'v_k', 'v_k2', 'v_c1', 'v_b', 'v_cfg', 'v_src2211', 'v_src2176'],
            cases=[('R1', "R1 — resolve_variant_row_axes(jsonb,uuid,uuid,text): STABLE, SECURITY DEFINER, search_path='', 10 OUT (RO)", r1()),
                   ('R2', 'R2 — prosrc chama internal.compute_variant_residual_signature (ST, declarado)', r2()),
                   ('R3', 'R3 — size fora de STANDARD ⇒ BLOCKED_* propagado, EC intocado (RC; controle standard)', r3()),
                   ('R4', 'R4 — token consumido por Printing sai do residual e não alimenta EC (RC)', r4()),
                   ('R5', 'R5 — token consumido por EC sai do residual de Finish (RC)', r5()),
                   ('R6', 'R6 — token desconhecido: nenhum eixo resolve, residual intacto; contagens inalteradas (RC+RO)', r6()),
                   ('R7', 'R7 — precedência scoped > global aplicada uma vez, por campo (FX+RC)', r7()),
                   ('R8', 'R8 — todo token de entrada aparece exatamente uma vez em Printing ∪ EC ∪ residual (RC)', r8()),
                   ('R9', 'R9 — mapping scoped ao Set X não resolve row do Set Y nem com escopo NULL (FX+RC)', r9()),
                   ('R10', 'R10 — guarda de nulidade antes do eixo 3; 2176 sem rota sem linha (ST, declarado)', r10()),
                   ('R11', 'R11 — subtype com mapping conhecido e INATIVO ⇒ NEEDS_REVIEW_INACTIVE_EC_MAPPING; simetria com stamp (FX+RC)', r11()),
                   ('R12', 'R12 — nas saídas NEEDS_REVIEW_* o residual preserva o token real (FX+RC)', r12())])


def e10():
    return envelope(SPEC)


PHEAD = header(['2830H · E10P — PRECHECK DO LOTE L8 (Seção R)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.',
    'Cobre ......... identidade da RC (2211/2176/2095/2192, bloco = E06P), candidato de',
    '                Printing (núcleo = E06P), escopo real de dp1 e profile de',
    '                SET-LOGO, triggers/constraints da 2207 (blocos = E06P via',
    '                static_check), marcador, P6/RLS das 3 tabelas EC escritas.',
])


def e10p():
    struct = [pre.e06p_cte(n) for n in pre.E06P_STRUCT_CTES]
    ctes = [pre.GS, pre.RC, pre.C35] + struct + ["""dp1 AS (
    SELECT (SELECT count(*) FROM public.card_set_external_reference r, gs
             WHERE r.asset_source_id = gs.src_id AND r.external_set_id = 'dp1' AND r.is_active) AS refs,
           (SELECT count(*) FROM public.card_edition_context_external_mapping m, gs
             WHERE m.game_id = gs.game_id AND m.asset_source_id = gs.src_id AND m.raw_field = 'stamp'
               AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = 'dp1' AND m.is_active
               AND cardinality(m.traits_signature) >= 1
               AND (SELECT count(*) FROM public.card_edition_context_profile p
                     WHERE p.game_id = gs.game_id AND p.traits_signature = m.traits_signature AND p.is_active) = 1) AS mapped
),"""]
    gates = (pre.GS_GATE + '\n' + pre.RC_GATE + '\n' + pre.MK_GATE + '\n'
             + '\n'.join(pre.e06p_gate(g) for g in pre.E06P_STRUCT_GATES) + """
        (SELECT count(*) FROM cand35) = 1                                             AS g_35_candidate,
        ((SELECT refs FROM dp1) = 1 AND (SELECT mapped FROM dp1) = 1
         AND (SELECT count(*) FROM internal.resolve_variant_mapping_scope(
                (SELECT r.card_set_id FROM public.card_set_external_reference r, gs
                  WHERE r.asset_source_id = gs.src_id AND r.external_set_id = 'dp1' AND r.is_active),
                (SELECT src_id FROM gs)) x WHERE x.external_set_id = 'dp1') = 1)     AS g_dp1_scope,
        ((SELECT public.normalize_external_catalog_value('set-logo')) = 'SET-LOGO'
         AND (SELECT public.normalize_external_catalog_value('oversized')) = 'OVERSIZED'
         AND (SELECT public.normalize_external_catalog_value('standard')) = 'STANDARD') AS g_normalization,""")
    det = pre.RC_DETAIL + """
        'd_35_candidate',   COALESCE((SELECT jsonb_agg(to_jsonb(c)) FROM cand35 c), '[]'::jsonb),
        'd_dp1',            (SELECT to_jsonb(d) FROM dp1 d),
        'd_triggers',       COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'fn_oid' ORDER BY t.relname, t.tgname) FROM trg t), '[]'::jsonb),
""" + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e10p_precheck')
