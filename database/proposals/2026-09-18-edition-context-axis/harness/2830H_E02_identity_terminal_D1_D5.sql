-- ============================================================================
-- 2830H · ENVELOPE E02 — SEÇÃO D (IDENTIDADE TERMINAL) · 5 casos: D1 – D5
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO (ver harness/README.md)
-- Contrato ...... 2830 v7.0 · blob b4647dcb59432405c8157e2733fd78678f35540e
-- Natureza ...... somente leitura de catálogo; NENHUMA fixture. Mesmo assim
--                 segue o envelope P2 (um DO, término obrigatório em exceção)
--                 para que o protocolo de leitura do resultado seja único.
-- Fora daqui .... D6, D7, D8 são EVIDÊNCIA HISTÓRICA (sem replay) e não
--                 pertencem a nenhum envelope automático.
-- P13 ........... não aplicável: universo = catálogo de índices, cardinalidade
--                 exata exigida (inclusive "zero" nos nomes removidos, que é a
--                 própria asserção, não vácuo).
-- P8 lock_timeout PENDENTE — não emitido (ver E01).
-- ============================================================================
DO $h2830_e02$
DECLARE
    c_env      CONSTANT text   := 'E02_SECAO_D_IDENTIDADE_TERMINAL';
    c_expected CONSTANT text[] := ARRAY['D1','D2','D3','D4','D5'];
    v_t0       timestamptz := clock_timestamp();
    v_done     text[]      := ARRAY[]::text[];
    v_case     text;
    v_n        bigint;
    v_m        bigint;
    v_arr      text[];
    v_att      int2;
    v_state    text;
    v_msg      text;
BEGIN
    -- ================================================================== --
    -- D1 — uq_card_variant_card_type_no_printing NÃO existe
    --      (nem como relação, nem como constraint, em nenhum schema)
    -- ================================================================== --
    v_case := 'D1';
    BEGIN
        SELECT count(*) INTO v_n FROM pg_class      WHERE relname = 'uq_card_variant_card_type_no_printing';
        SELECT count(*) INTO v_m FROM pg_constraint WHERE conname = 'uq_card_variant_card_type_no_printing';
        IF v_n <> 0 OR v_m <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s identidade antiga presente pg_class=%s pg_constraint=%s', c_env, v_case, v_n, v_m);
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
    -- D2 — uq_card_variant_card_type_printing NÃO existe
    -- ================================================================== --
    v_case := 'D2';
    BEGIN
        SELECT count(*) INTO v_n FROM pg_class      WHERE relname = 'uq_card_variant_card_type_printing';
        SELECT count(*) INTO v_m FROM pg_constraint WHERE conname = 'uq_card_variant_card_type_printing';
        IF v_n <> 0 OR v_m <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s identidade antiga presente pg_class=%s pg_constraint=%s', c_env, v_case, v_n, v_m);
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
    -- D3 — uq_cvir_job_card_type_no_printing e uq_cvir_job_card_type_printing
    --      NÃO existem
    -- ================================================================== --
    v_case := 'D3';
    BEGIN
        SELECT count(*) INTO v_n FROM pg_class
         WHERE relname IN ('uq_cvir_job_card_type_no_printing','uq_cvir_job_card_type_printing');
        SELECT count(*) INTO v_m FROM pg_constraint
         WHERE conname IN ('uq_cvir_job_card_type_no_printing','uq_cvir_job_card_type_printing');
        IF v_n <> 0 OR v_m <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s identidades antigas de staging presentes pg_class=%s pg_constraint=%s', c_env, v_case, v_n, v_m);
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
    -- D4 — SOMENTE a nova identidade permanece:
    --      card_variant: exatamente 1 índice único que contém variant_type_id,
    --        e é uq_card_variant_identity (válido e pronto);
    --      catalog_variant_import_row: exatamente 1 índice único que contém
    --        job_id (coluna OU expressão), e é uq_cvir_row_identity.
    -- ================================================================== --
    v_case := 'D4';
    BEGIN
        SELECT a.attnum INTO v_att
          FROM pg_attribute a
         WHERE a.attrelid = to_regclass('public.card_variant') AND a.attname = 'variant_type_id' AND NOT a.attisdropped;
        IF v_att IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s coluna card_variant.variant_type_id não encontrada', c_env, v_case);
        END IF;
        SELECT array_agg(c.relname::text ORDER BY c.relname) INTO v_arr
          FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
         WHERE i.indrelid = to_regclass('public.card_variant')
           AND i.indisunique
           AND v_att = ANY (i.indkey::int2[]);
        IF v_arr IS DISTINCT FROM ARRAY['uq_card_variant_identity'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s únicos de card_variant com variant_type_id=%s', c_env, v_case, v_arr);
        END IF;
        SELECT count(*) INTO v_n FROM pg_index
         WHERE indexrelid = to_regclass('public.uq_card_variant_identity') AND indisvalid AND indisready AND indislive;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_card_variant_identity não saudável', c_env, v_case);
        END IF;

        v_att := NULL;
        SELECT a.attnum INTO v_att
          FROM pg_attribute a
         WHERE a.attrelid = to_regclass('public.catalog_variant_import_row') AND a.attname = 'job_id' AND NOT a.attisdropped;
        IF v_att IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s coluna catalog_variant_import_row.job_id não encontrada', c_env, v_case);
        END IF;
        SELECT array_agg(c.relname::text ORDER BY c.relname) INTO v_arr
          FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
         WHERE i.indrelid = to_regclass('public.catalog_variant_import_row')
           AND i.indisunique
           AND (v_att = ANY (i.indkey::int2[])
                OR (i.indexprs IS NOT NULL AND pg_get_expr(i.indexprs, i.indrelid) ~ '\mjob_id\M'));
        IF v_arr IS DISTINCT FROM ARRAY['uq_cvir_row_identity'] THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s únicos de staging com job_id=%s', c_env, v_case, v_arr);
        END IF;
        SELECT count(*) INTO v_n FROM pg_index
         WHERE indexrelid = to_regclass('public.uq_cvir_row_identity') AND indisvalid AND indisready AND indislive;
        IF v_n <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s uq_cvir_row_identity não saudável', c_env, v_case);
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
    -- D5 — ortogonais preservados: uq_card_variant_card_order,
    --      uq_card_variant_one_default_per_card, uq_card_variant_id_card —
    --      cada um existe 1 vez, é UNIQUE, pertence a card_variant e é válido
    -- ================================================================== --
    v_case := 'D5';
    BEGIN
        SELECT count(*) INTO v_n
          FROM unnest(ARRAY['uq_card_variant_card_order','uq_card_variant_one_default_per_card',
                            'uq_card_variant_id_card']) AS x(name)
          JOIN pg_index i ON i.indexrelid = to_regclass('public.' || x.name)
         WHERE i.indrelid = to_regclass('public.card_variant')
           AND i.indisunique AND i.indisvalid AND i.indisready;
        SELECT count(*) INTO v_m FROM pg_class
         WHERE relname IN ('uq_card_variant_card_order','uq_card_variant_one_default_per_card','uq_card_variant_id_card');
        IF v_n <> 3 OR v_m <> 3 THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s ortogonais saudáveis=%s relações com o nome=%s (esperado 3/3)', c_env, v_case, v_n, v_m);
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

    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s elapsed_ms=%s',
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END
$h2830_e02$;
