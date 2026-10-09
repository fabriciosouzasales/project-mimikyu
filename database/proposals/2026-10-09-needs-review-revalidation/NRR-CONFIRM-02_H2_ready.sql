-- NRR-CONFIRM-02 — decide+confirm das 379 linhas H2 (EX7–EX10, reverse+set-logo → REVERSE_HOLO)
-- Mesmo runner do NRR-CONFIRM-01 (2144/2145, ator = admin real), escopo = jobs STAGED de EX7–EX10.
-- Pré-condição: mappings SOURCE_SET ex7..ex10 criados em 2026-10-09 (379 linhas VALID/PENDING/PENDING).
-- Esperado: rows=379, inserted+unchanged=379; qualquer gate falho desfaz tudo. Colar no SQL Editor.

DO $nrr$
DECLARE
    c_mode      CONSTANT TEXT := 'FULL';
    c_sets      CONSTANT TEXT[] := ARRAY['EX7','EX8','EX9','EX10'];
    c_expected  CONSTANT INTEGER := 379;
    v_admin     UUID;
    v_job       RECORD;
    v_a         UUID[];
    v_b         INTEGER;
    v_n         INTEGER;
    v_ins       INTEGER;
    v_unc       INTEGER;
    v_fail      INTEGER;
    v_cv0       INTEGER;
    v_cv1       INTEGER;
    v_tot_a     INTEGER := 0;
    v_tot_ins   INTEGER := 0;
    v_tot_unc   INTEGER := 0;
    v_jobs      INTEGER := 0;
    v_scope     INTEGER;
    v_report    JSONB := '[]'::jsonb;
BEGIN
    IF c_expected IS NULL THEN RAISE EXCEPTION 'NRR_CONFIRM_EXPECTED_REQUIRED'; END IF;
    SELECT id INTO v_admin FROM public.admin_user;
    IF (SELECT count(*) FROM public.admin_user) <> 1 THEN
        RAISE EXCEPTION 'NRR_CONFIRM_ADMIN_AMBIGUOUS: esperado exatamente 1 admin_user.';
    END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'NRR_CONFIRM_NOT_ADMIN_CONTEXT'; END IF;

    IF EXISTS (SELECT 1 FROM public.catalog_variant_import_row WHERE persistence_status = 'FAILED') THEN
        RAISE EXCEPTION 'NRR_CONFIRM_PRE_FAILED_PRESENT';
    END IF;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    -- Escopo do modo
    CREATE TEMP TABLE nrr_scope ON COMMIT DROP AS
    SELECT j.id AS job_id, cs.code AS set_code,
           count(*) FILTER (WHERE r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING') AS a_n
      FROM public.catalog_variant_import_job j
      JOIN public.card_set cs ON cs.id = j.card_set_id
      JOIN public.catalog_variant_import_row r ON r.job_id = j.id
     WHERE cs.code = ANY (c_sets)
       AND j.status = 'STAGED'
     GROUP BY 1, 2
    HAVING count(*) FILTER (WHERE r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING') > 0;

    IF c_mode = 'CANARY' THEN
        DELETE FROM nrr_scope WHERE job_id NOT IN (SELECT job_id FROM nrr_scope ORDER BY a_n, set_code LIMIT 1);
    ELSIF c_mode <> 'FULL' THEN
        RAISE EXCEPTION 'NRR_CONFIRM_INVALID_MODE: %', c_mode;
    END IF;

    SELECT coalesce(sum(a_n),0) INTO v_scope FROM nrr_scope;
    IF v_scope IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION 'NRR_CONFIRM_SCOPE_DRIFT: escopo % linhas, esperado %.', v_scope, c_expected;
    END IF;

    FOR v_job IN SELECT * FROM nrr_scope ORDER BY a_n, set_code LOOP
        SELECT array_agg(r.id ORDER BY r.id) INTO v_a
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job.job_id AND r.validation_status='VALID'
           AND r.decision_status='PENDING' AND r.persistence_status='PENDING';
        SELECT count(*) INTO v_b FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job.job_id AND r.validation_status='VALID'
           AND r.decision_status='APPROVED' AND r.persistence_status='PENDING';
        IF v_b > 0 THEN RAISE EXCEPTION 'NRR_CONFIRM_RESUME_PARTIAL: job % (%).', v_job.job_id, v_job.set_code; END IF;

        v_n := public.admin_decide_catalog_variant_import_row(v_a, 'APPROVED');
        IF v_n <> cardinality(v_a) THEN
            RAISE EXCEPTION 'NRR_CONFIRM_DECIDE_MISMATCH: job % decidiu %, esperado %.', v_job.set_code, v_n, cardinality(v_a);
        END IF;

        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job.job_id, v_a);

        SELECT count(*) FILTER (WHERE persistence_status='INSERTED'),
               count(*) FILTER (WHERE persistence_status='UNCHANGED'),
               count(*) FILTER (WHERE persistence_status NOT IN ('INSERTED','UNCHANGED'))
          INTO v_ins, v_unc, v_fail
          FROM public.catalog_variant_import_row WHERE id = ANY (v_a);
        IF v_fail <> 0 THEN
            RAISE EXCEPTION 'NRR_CONFIRM_ROWS_NOT_PERSISTED: job % — % linha(s) fora de INSERTED/UNCHANGED.', v_job.set_code, v_fail;
        END IF;

        v_tot_a := v_tot_a + cardinality(v_a);
        v_tot_ins := v_tot_ins + v_ins;
        v_tot_unc := v_tot_unc + v_unc;
        v_jobs := v_jobs + 1;
        v_report := v_report || jsonb_build_object('set', v_job.set_code, 'a', cardinality(v_a), 'ins', v_ins, 'unc', v_unc,
                     'job_status', (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job.job_id));
    END LOOP;

    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 - v_cv0 <> v_tot_ins THEN
        RAISE EXCEPTION 'NRR_CONFIRM_CARD_VARIANT_DELTA: card_variant % -> %, inseridas %.', v_cv0, v_cv1, v_tot_ins;
    END IF;
    IF EXISTS (SELECT 1 FROM public.catalog_variant_import_row WHERE persistence_status = 'FAILED') THEN
        RAISE EXCEPTION 'NRR_CONFIRM_POST_FAILED_PRESENT';
    END IF;

    PERFORM set_config('request.jwt.claims', '', true);
    RAISE NOTICE 'NRR_CONFIRM_OK %', jsonb_build_object('mode', c_mode, 'jobs', v_jobs, 'rows', v_tot_a,
        'inserted', v_tot_ins, 'unchanged', v_tot_unc, 'card_variant_before', v_cv0, 'card_variant_after', v_cv1,
        'per_job', v_report);
END;
$nrr$;
